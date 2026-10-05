import { Router } from 'express';
import bcrypt from 'bcryptjs';
import rateLimit, { ipKeyGenerator } from 'express-rate-limit';
import { z } from 'zod';
import { OAuth2Client } from 'google-auth-library';
import { prisma } from '../lib/prisma.js';
import { ah, badRequest, conflict, unauthorized, forbidden } from '../lib/errors.js';
import { parse, phoneSchema, pinSchema, regNumberSchema, fuelTypeSchema } from '../lib/validate.js';
import { newCardNumber, newReferralCode } from '../lib/codes.js';
import { signToken, publicUser } from '../lib/auth.js';
import { config } from '../config.js';
import { authenticate } from '../middleware/auth.js';

const router = Router();
const google = new OAuth2Client();

// 4-digit PINs are guessable, so throttle attempts per phone number and per IP.
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 8,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  keyGenerator: (req) => `${ipKeyGenerator(req.ip)}:${String(req.body?.phone ?? '').slice(-10)}`,
  message: { error: { message: 'Too many attempts. Try again in 15 minutes.', code: 'RATE_LIMITED' } },
});

const registerSchema = z.object({
  name: z.string().trim().min(2).max(60),
  phone: phoneSchema,
  pin: pinSchema,
  email: z.string().email().optional().or(z.literal('').transform(() => undefined)),
  referralCode: z.string().trim().toUpperCase().optional().or(z.literal('').transform(() => undefined)),
  vehicle: z
    .object({ regNumber: regNumberSchema, fuelType: fuelTypeSchema, nickname: z.string().max(30).optional() })
    .optional(),
});

async function uniqueCardNumber() {
  for (;;) {
    const n = newCardNumber();
    if (!(await prisma.user.findUnique({ where: { cardNumber: n } }))) return n;
  }
}

async function uniqueReferral(name) {
  for (;;) {
    const c = newReferralCode(name);
    if (!(await prisma.user.findUnique({ where: { referralCode: c } }))) return c;
  }
}

router.post(
  '/register',
  ah(async (req, res) => {
    const body = parse(registerSchema, req.body);
    if (await prisma.user.findUnique({ where: { phone: body.phone } })) {
      throw conflict('This mobile number is already registered. Please log in.', 'PHONE_TAKEN');
    }
    if (body.email && (await prisma.user.findUnique({ where: { email: body.email } }))) {
      throw conflict('This email is already registered.', 'EMAIL_TAKEN');
    }
    let referredById;
    if (body.referralCode) {
      const ref = await prisma.user.findUnique({ where: { referralCode: body.referralCode } });
      if (!ref) throw badRequest('Referral code not found', 'BAD_REFERRAL');
      referredById = ref.id;
    }
    const user = await prisma.user.create({
      data: {
        name: body.name,
        phone: body.phone,
        email: body.email,
        pinHash: await bcrypt.hash(body.pin, 10),
        cardNumber: await uniqueCardNumber(),
        referralCode: await uniqueReferral(body.name),
        referredById,
        vehicles: body.vehicle ? { create: { ...body.vehicle, isDefault: true } } : undefined,
      },
    });
    res.status(201).json({ token: signToken(user), user: publicUser(user) });
  }),
);

router.post(
  '/login',
  loginLimiter,
  ah(async (req, res) => {
    const { phone, pin } = parse(z.object({ phone: phoneSchema, pin: pinSchema }), req.body);
    const user = await prisma.user.findUnique({ where: { phone } });
    if (!user || !(await bcrypt.compare(pin, user.pinHash))) throw unauthorized('Wrong mobile number or PIN', 'BAD_CREDENTIALS');
    if (user.status === 'BLOCKED') throw forbidden('Your account has been blocked. Please contact the station.', 'ACCOUNT_BLOCKED');
    res.json({ token: signToken(user), user: publicUser(user) });
  }),
);

// Free alternative to SMS OTP: sign in with a Google account previously linked to the profile.
router.post(
  '/google',
  ah(async (req, res) => {
    const { idToken } = parse(z.object({ idToken: z.string().min(10) }), req.body);
    if (!config.googleClientIds.length) throw badRequest('Google sign-in is not configured', 'GOOGLE_DISABLED');
    let payload;
    try {
      const ticket = await google.verifyIdToken({ idToken, audience: config.googleClientIds });
      payload = ticket.getPayload();
    } catch {
      throw unauthorized('Google sign-in failed', 'GOOGLE_INVALID');
    }
    const user = await prisma.user.findUnique({ where: { googleSub: payload.sub } });
    if (!user) throw unauthorized('No account is linked to this Google account. Log in with mobile + PIN and link Google from Profile.', 'GOOGLE_NOT_LINKED');
    if (user.status === 'BLOCKED') throw forbidden('Your account has been blocked.', 'ACCOUNT_BLOCKED');
    res.json({ token: signToken(user), user: publicUser(user) });
  }),
);

router.post(
  '/google/link',
  authenticate,
  ah(async (req, res) => {
    const { idToken } = parse(z.object({ idToken: z.string().min(10) }), req.body);
    if (!config.googleClientIds.length) throw badRequest('Google sign-in is not configured', 'GOOGLE_DISABLED');
    let payload;
    try {
      payload = (await google.verifyIdToken({ idToken, audience: config.googleClientIds })).getPayload();
    } catch {
      throw unauthorized('Google sign-in failed', 'GOOGLE_INVALID');
    }
    const other = await prisma.user.findUnique({ where: { googleSub: payload.sub } });
    if (other && other.id !== req.user.id) throw conflict('This Google account is linked to another profile', 'GOOGLE_TAKEN');
    const user = await prisma.user.update({ where: { id: req.user.id }, data: { googleSub: payload.sub } });
    res.json({ user: publicUser(user) });
  }),
);

router.post(
  '/change-pin',
  authenticate,
  ah(async (req, res) => {
    const { currentPin, newPin } = parse(z.object({ currentPin: pinSchema, newPin: pinSchema }), req.body);
    if (!(await bcrypt.compare(currentPin, req.user.pinHash))) throw unauthorized('Current PIN is wrong', 'BAD_CREDENTIALS');
    // Bumping tokenVersion logs out every other device.
    const user = await prisma.user.update({
      where: { id: req.user.id },
      data: { pinHash: await bcrypt.hash(newPin, 10), tokenVersion: { increment: 1 } },
    });
    res.json({ token: signToken(user), user: publicUser(user) });
  }),
);

export default router;
