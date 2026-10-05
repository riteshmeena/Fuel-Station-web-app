import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../lib/prisma.js';
import { ah, badRequest, forbidden, notFound, conflict } from '../lib/errors.js';
import { parse, fuelTypeSchema } from '../lib/validate.js';
import { newInvoiceNo } from '../lib/codes.js';
import { pointsFor, tierForSpend } from '../lib/loyalty.js';
import { getSetting } from '../lib/settings.js';
import { publicUser } from '../lib/auth.js';
import { notify } from '../lib/notify.js';
import { currentPrices } from './public.js';
import { serializeTx } from './me.js';

const router = Router();

// The card QR encodes "FS:<cardNumberDigits>"; staff may also type the card or phone number.
async function findCustomer(code) {
  const raw = String(code ?? '').trim().replace(/^FS:/, '');
  const digits = raw.replace(/\D/g, '');
  let user = null;
  if (digits.length === 12) {
    user = await prisma.user.findUnique({ where: { cardNumber: `${digits.slice(0, 4)} ${digits.slice(4, 8)} ${digits.slice(8)}` } });
  } else if (digits.length >= 10) {
    user = await prisma.user.findUnique({ where: { phone: digits.slice(-10) } });
  }
  if (!user) throw notFound('No customer found for this card');
  return user;
}

router.get('/lookup', ah(async (req, res) => {
  const user = await findCustomer(req.query.code);
  const vehicles = await prisma.vehicle.findMany({ where: { userId: user.id }, orderBy: [{ isDefault: 'desc' }] });
  res.json({ user: publicUser(user), vehicles });
}));

router.post('/transactions', ah(async (req, res) => {
  const body = parse(
    z
      .object({
        code: z.string().min(4),
        vehicleId: z.string().optional(),
        fuelType: fuelTypeSchema,
        amount: z.number().positive().max(500000).optional(),
        quantity: z.number().positive().max(5000).optional(),
        odometerKm: z.number().int().positive().max(5_000_000).optional(),
      })
      .refine((b) => b.amount || b.quantity, 'Enter amount or quantity'),
    req.body,
  );
  const customer = await findCustomer(body.code);
  if (customer.status !== 'VERIFIED') throw forbidden('This customer is not verified yet. Ask admin to verify the account.', 'ACCOUNT_PENDING');
  if (body.vehicleId && !(await prisma.vehicle.findFirst({ where: { id: body.vehicleId, userId: customer.id } }))) {
    throw badRequest('Vehicle does not belong to this customer');
  }
  const price = (await currentPrices()).find((p) => p.fuelType === body.fuelType);
  if (!price) throw badRequest('No price set for this fuel type');
  const amount = body.amount ?? Math.round(body.quantity * price.price * 100) / 100;
  const quantity = body.quantity ?? Math.round((body.amount / price.price) * 100) / 100;
  const cfg = await getSetting('loyalty');

  const result = await prisma.$transaction(async (tx) => {
    const fresh = await tx.user.findUnique({ where: { id: customer.id } });
    const pts = pointsFor(amount, fresh.tier, cfg);
    const spend = Number(fresh.lifetimeSpend) + amount;
    const newTier = tierForSpend(spend, cfg.tierThresholds);
    const t = await tx.transaction.create({
      data: {
        invoiceNo: newInvoiceNo(),
        userId: customer.id,
        vehicleId: body.vehicleId,
        staffId: req.user.id,
        fuelType: body.fuelType,
        quantity,
        pricePerUnit: price.price,
        amount,
        odometerKm: body.odometerKm,
        pointsEarned: pts,
      },
      include: { vehicle: true },
    });
    await tx.user.update({ where: { id: customer.id }, data: { points: { increment: pts }, lifetimeSpend: spend, tier: newTier } });
    if (pts) await tx.pointsLedger.create({ data: { userId: customer.id, type: 'EARN', points: pts, note: `Fuel ₹${amount}`, refId: t.id } });
    return { t, pts, upgraded: newTier !== fresh.tier ? newTier : null };
  });

  await notify(customer.id, `+${result.pts} points earned ⛽`, `₹${amount.toFixed(2)} • ${quantity} ${price.unit} ${body.fuelType.replace('_', ' ').toLowerCase()}. Thank you for fuelling with us!`, 'POINTS');
  if (result.upgraded) await notify(customer.id, `Welcome to ${result.upgraded} 🎉`, 'You have unlocked a higher tier with bonus point multipliers.', 'TIER');
  res.status(201).json({ transaction: serializeTx(result.t), pointsEarned: result.pts, tierUpgrade: result.upgraded });
}));

// Mark a reward redemption as handed over.
router.post('/redemptions/use', ah(async (req, res) => {
  const { code } = parse(z.object({ code: z.string().trim().toUpperCase() }), req.body);
  const r = await prisma.redemption.findUnique({ where: { code }, include: { reward: true, user: true } });
  if (!r) throw notFound('Redemption code not found');
  if (r.status !== 'PENDING') throw conflict(`This code is already ${r.status.toLowerCase()}`, 'ALREADY_USED');
  const updated = await prisma.redemption.update({ where: { id: r.id }, data: { status: 'USED', usedAt: new Date() }, include: { reward: true } });
  res.json({ redemption: updated, customer: { name: r.user.name, phone: r.user.phone } });
}));

router.get('/my-shift', ah(async (req, res) => {
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const items = await prisma.transaction.findMany({
    where: { staffId: req.user.id, createdAt: { gte: start } },
    orderBy: { createdAt: 'desc' },
    include: { user: { select: { name: true, phone: true } } },
  });
  const total = items.reduce((s, t) => s + Number(t.amount), 0);
  res.json({ count: items.length, total: Math.round(total * 100) / 100, items: items.map(serializeTx) });
}));

export default router;
