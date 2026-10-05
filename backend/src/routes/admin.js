import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { prisma } from '../lib/prisma.js';
import { ah, badRequest, forbidden, notFound } from '../lib/errors.js';
import { parse, paginationSchema, phoneSchema, pinSchema, fuelTypeSchema } from '../lib/validate.js';
import { publicUser } from '../lib/auth.js';
import { notify } from '../lib/notify.js';
import { getSetting, setSetting } from '../lib/settings.js';
import { requireRole } from '../middleware/auth.js';
import { newCardNumber, newReferralCode } from '../lib/codes.js';
import { serializeTx } from './me.js';

const router = Router();
const superOnly = requireRole('SUPERADMIN');

// ---------- Customers ----------
router.get('/users', ah(async (req, res) => {
  const { page, limit } = parse(paginationSchema, req.query);
  const q = String(req.query.q ?? '').trim();
  const where = {
    ...(req.query.status ? { status: String(req.query.status) } : {}),
    ...(req.query.role ? { role: String(req.query.role) } : {}),
    ...(q ? { OR: [{ name: { contains: q, mode: 'insensitive' } }, { phone: { contains: q } }, { cardNumber: { contains: q } }, { vehicles: { some: { regNumber: { contains: q.toUpperCase().replace(/\s/g, '') } } } }] } : {}),
  };
  const [items, total] = await Promise.all([
    prisma.user.findMany({ where, orderBy: { createdAt: 'desc' }, skip: (page - 1) * limit, take: limit, include: { vehicles: true } }),
    prisma.user.count({ where }),
  ]);
  res.json({ items: items.map((u) => ({ ...publicUser(u), vehicles: u.vehicles })), total, page, limit });
}));

router.get('/users/:id', ah(async (req, res) => {
  const u = await prisma.user.findUnique({
    where: { id: req.params.id },
    include: {
      vehicles: true,
      transactions: { orderBy: { createdAt: 'desc' }, take: 20 },
      ledger: { orderBy: { createdAt: 'desc' }, take: 20 },
      redemptions: { orderBy: { createdAt: 'desc' }, take: 20, include: { reward: true } },
      referredBy: { select: { id: true, name: true } },
    },
  });
  if (!u) throw notFound('User not found');
  res.json({ ...publicUser(u), vehicles: u.vehicles, transactions: u.transactions.map(serializeTx), ledger: u.ledger, redemptions: u.redemptions, referredBy: u.referredBy });
}));

// Super-admin approves new sign-ups. Welcome + referral bonuses are granted only here,
// so unverified/fake accounts never earn anything.
async function verifyUser(id, actor) {
  const cfg = await getSetting('loyalty');
  const user = await prisma.$transaction(async (tx) => {
    const u = await tx.user.findUnique({ where: { id } });
    if (!u) throw notFound('User not found');
    if (u.status === 'VERIFIED') throw badRequest('Already verified');
    const firstTime = !u.verifiedAt;
    const bonus = firstTime ? cfg.welcomeBonus : 0;
    const updated = await tx.user.update({
      where: { id: u.id },
      data: { status: 'VERIFIED', verifiedAt: u.verifiedAt ?? new Date(), verifiedById: actor.id, points: { increment: bonus } },
    });
    if (bonus) await tx.pointsLedger.create({ data: { userId: u.id, type: 'BONUS', points: bonus, note: 'Welcome bonus' } });
    if (firstTime && u.referredById && cfg.referralBonus) {
      await tx.user.update({ where: { id: u.referredById }, data: { points: { increment: cfg.referralBonus } } });
      await tx.pointsLedger.create({ data: { userId: u.referredById, type: 'REFERRAL', points: cfg.referralBonus, note: `Referral: ${u.name}`, refId: u.id } });
      await tx.notification.create({ data: { userId: u.referredById, title: `+${cfg.referralBonus} referral points 🤝`, body: `${u.name} joined using your code.`, kind: 'POINTS' } });
    }
    return updated;
  });
  await notify(user.id, 'Account verified ✅', 'Your fuel card is now active. Start earning points on every fill-up!', 'ACCOUNT');
  return user;
}

// Super-admin approves new sign-ups. Welcome + referral bonuses are granted only here,
// so unverified/fake accounts never earn anything.
router.post('/users/:id/verify', superOnly, ah(async (req, res) => {
  res.json(publicUser(await verifyUser(req.params.id, req.user)));
}));

router.post('/users/verify-bulk', superOnly, ah(async (req, res) => {
  const { ids } = parse(z.object({ ids: z.array(z.string()).min(1).max(200) }), req.body);
  const results = [];
  for (const id of ids) {
    try {
      await verifyUser(id, req.user);
      results.push({ id, ok: true });
    } catch (e) {
      results.push({ id, ok: false, error: e.message });
    }
  }
  res.json({ results });
}));

router.post('/users/:id/block', superOnly, ah(async (req, res) => {
  const { blocked } = parse(z.object({ blocked: z.boolean() }), req.body);
  const target = await prisma.user.findUnique({ where: { id: req.params.id } });
  if (!target) throw notFound('User not found');
  if (target.role === 'SUPERADMIN') throw forbidden('Cannot block a super admin');
  const user = await prisma.user.update({
    where: { id: target.id },
    data: { status: blocked ? 'BLOCKED' : target.verifiedAt ? 'VERIFIED' : 'PENDING', tokenVersion: { increment: blocked ? 1 : 0 } },
  });
  res.json(publicUser(user));
}));

// Forgot PIN: customer visits the station, admin checks ID and sets a temporary PIN.
router.post('/users/:id/reset-pin', ah(async (req, res) => {
  const { pin } = parse(z.object({ pin: pinSchema }), req.body);
  const target = await prisma.user.findUnique({ where: { id: req.params.id } });
  if (!target) throw notFound('User not found');
  if (target.role !== 'CUSTOMER' && req.user.role !== 'SUPERADMIN') throw forbidden('Only super admin can reset staff PINs');
  await prisma.user.update({ where: { id: target.id }, data: { pinHash: await bcrypt.hash(pin, 10), tokenVersion: { increment: 1 } } });
  res.json({ ok: true });
}));

router.post('/users/:id/role', superOnly, ah(async (req, res) => {
  const { role } = parse(z.object({ role: z.enum(['CUSTOMER', 'STAFF', 'ADMIN', 'SUPERADMIN']) }), req.body);
  if (req.params.id === req.user.id) throw badRequest('You cannot change your own role');
  const user = await prisma.user.update({ where: { id: req.params.id }, data: { role, tokenVersion: { increment: 1 } } });
  res.json(publicUser(user));
}));

router.post('/users/:id/points', ah(async (req, res) => {
  const { points, note } = parse(z.object({ points: z.number().int().refine((n) => n !== 0), note: z.string().trim().min(2).max(120) }), req.body);
  const user = await prisma.$transaction(async (tx) => {
    const u = await tx.user.findUnique({ where: { id: req.params.id } });
    if (!u) throw notFound('User not found');
    if (u.points + points < 0) throw badRequest('Balance cannot go below zero');
    await tx.pointsLedger.create({ data: { userId: u.id, type: 'ADJUST', points, note: `${note} (by ${req.user.name})` } });
    return tx.user.update({ where: { id: u.id }, data: { points: { increment: points } } });
  });
  await notify(user.id, points > 0 ? `+${points} points added` : `${points} points adjusted`, note, 'POINTS');
  res.json(publicUser(user));
}));

// Create staff/admin accounts directly (verified from the start).
router.post('/staff', superOnly, ah(async (req, res) => {
  const body = parse(z.object({ name: z.string().trim().min(2), phone: phoneSchema, pin: pinSchema, role: z.enum(['STAFF', 'ADMIN']) }), req.body);
  if (await prisma.user.findUnique({ where: { phone: body.phone } })) throw badRequest('Phone already registered — change their role instead');
  const user = await prisma.user.create({
    data: { name: body.name, phone: body.phone, pinHash: await bcrypt.hash(body.pin, 10), role: body.role, status: 'VERIFIED', verifiedAt: new Date(), verifiedById: req.user.id, cardNumber: newCardNumber(), referralCode: newReferralCode(body.name) },
  });
  res.status(201).json(publicUser(user));
}));

// ---------- Prices ----------
router.post('/prices', ah(async (req, res) => {
  const { prices, effectiveDate } = parse(
    z.object({
      prices: z.array(z.object({ fuelType: fuelTypeSchema, price: z.number().positive().max(1000) })).min(1),
      effectiveDate: z.coerce.date().optional(),
    }),
    req.body,
  );
  const at = effectiveDate ?? new Date();
  await prisma.fuelPrice.createMany({ data: prices.map((p) => ({ fuelType: p.fuelType, pricePerUnit: p.price, effectiveDate: at, updatedById: req.user.id })) });
  res.status(201).json({ ok: true });
}));

// ---------- Generic CRUD helper for rewards / offers / announcements ----------
function crud(path, model, schema) {
  router.get(`/${path}`, ah(async (_req, res) => res.json(await prisma[model].findMany({ orderBy: { createdAt: 'desc' } }))));
  router.post(`/${path}`, ah(async (req, res) => res.status(201).json(await prisma[model].create({ data: parse(schema, req.body) }))));
  router.patch(`/${path}/:id`, ah(async (req, res) => res.json(await prisma[model].update({ where: { id: req.params.id }, data: parse(schema.partial(), req.body) }))));
  router.delete(`/${path}/:id`, ah(async (req, res) => {
    await prisma[model].update({ where: { id: req.params.id }, data: model === 'announcement' ? { published: false } : { active: false } });
    res.status(204).end();
  }));
}

crud('rewards', 'reward', z.object({
  title: z.string().trim().min(2), description: z.string().trim().min(2), pointsCost: z.number().int().positive(),
  imageUrl: z.string().url().nullable().optional(), category: z.string().optional(), stock: z.number().int().min(0).nullable().optional(), active: z.boolean().optional(),
}));
crud('offers', 'offer', z.object({
  title: z.string().trim().min(2), description: z.string().trim().min(2), imageUrl: z.string().url().nullable().optional(),
  couponCode: z.string().trim().toUpperCase().nullable().optional(), bonusPoints: z.number().int().min(0).optional(),
  minTier: z.enum(['SILVER', 'GOLD', 'PLATINUM']).optional(), startsAt: z.coerce.date().optional(), endsAt: z.coerce.date(), active: z.boolean().optional(),
}));
crud('announcements', 'announcement', z.object({
  title: z.string().trim().min(2), body: z.string().trim().min(2), imageUrl: z.string().url().nullable().optional(), published: z.boolean().optional(),
}));

// ---------- Bookings ----------
router.get('/bookings', ah(async (req, res) => {
  const from = req.query.from ? new Date(String(req.query.from)) : new Date(Date.now() - 864e5);
  res.json(await prisma.booking.findMany({ where: { slot: { gte: from }, ...(req.query.status ? { status: String(req.query.status) } : {}) }, orderBy: { slot: 'asc' }, include: { user: { select: { name: true, phone: true } } } }));
}));
router.patch('/bookings/:id', ah(async (req, res) => {
  const { status } = parse(z.object({ status: z.enum(['CONFIRMED', 'COMPLETED', 'CANCELLED']) }), req.body);
  const b = await prisma.booking.update({ where: { id: req.params.id }, data: { status } });
  const label = { CONFIRMED: 'confirmed ✅', COMPLETED: 'completed 🎉', CANCELLED: 'cancelled' }[status];
  await notify(b.userId, `Booking ${label}`, `${b.service.replace('_', ' ')} on ${b.slot.toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' })}`, 'BOOKING');
  res.json(b);
}));

// ---------- Feedback ----------
router.get('/feedback', ah(async (req, res) => {
  res.json(await prisma.feedback.findMany({ where: req.query.status ? { status: String(req.query.status) } : {}, orderBy: { createdAt: 'desc' }, include: { user: { select: { name: true, phone: true } } } }));
}));
router.post('/feedback/:id/reply', ah(async (req, res) => {
  const { reply } = parse(z.object({ reply: z.string().trim().min(2).max(1000) }), req.body);
  const f = await prisma.feedback.update({ where: { id: req.params.id }, data: { reply, status: 'RESOLVED' } });
  await notify(f.userId, 'We replied to your feedback 💬', reply, 'FEEDBACK');
  res.json(f);
}));

// ---------- Broadcast ----------
router.post('/broadcast', ah(async (req, res) => {
  const { title, body, tier } = parse(z.object({ title: z.string().trim().min(2).max(80), body: z.string().trim().min(2).max(500), tier: z.enum(['SILVER', 'GOLD', 'PLATINUM']).optional() }), req.body);
  const users = await prisma.user.findMany({ where: { status: 'VERIFIED', ...(tier ? { tier } : {}) }, select: { id: true } });
  await prisma.notification.createMany({ data: users.map((u) => ({ userId: u.id, title, body, kind: 'BROADCAST' })) });
  res.json({ sent: users.length });
}));

// ---------- Settings ----------
router.get('/settings', ah(async (_req, res) => res.json({ station: await getSetting('station'), loyalty: await getSetting('loyalty') })));
router.patch('/settings/:key', superOnly, ah(async (req, res) => {
  if (!['station', 'loyalty'].includes(req.params.key)) throw notFound('Unknown setting');
  res.json(await setSetting(req.params.key, req.body ?? {}));
}));

// ---------- Transactions & analytics ----------
router.get('/transactions', ah(async (req, res) => {
  const { page, limit } = parse(paginationSchema, req.query);
  const where = {
    ...(req.query.from || req.query.to ? { createdAt: { ...(req.query.from ? { gte: new Date(String(req.query.from)) } : {}), ...(req.query.to ? { lte: new Date(String(req.query.to)) } : {}) } } : {}),
    ...(req.query.staffId ? { staffId: String(req.query.staffId) } : {}),
  };
  const [items, total] = await Promise.all([
    prisma.transaction.findMany({ where, orderBy: { createdAt: 'desc' }, skip: (page - 1) * limit, take: limit, include: { user: { select: { name: true, phone: true } }, staff: { select: { name: true } }, vehicle: true } }),
    prisma.transaction.count({ where }),
  ]);
  res.json({ items: items.map(serializeTx), total, page, limit });
}));

router.get('/analytics', ah(async (req, res) => {
  const days = Math.min(365, Math.max(1, Number(req.query.days ?? 30)));
  const since = new Date(Date.now() - days * 864e5);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const [pending, members, newMembers, todayAgg, periodAgg, byFuel, topCustomers, redemptions, openFeedback, upcomingBookings, txs] = await Promise.all([
    prisma.user.count({ where: { status: 'PENDING', role: 'CUSTOMER' } }),
    prisma.user.count({ where: { status: 'VERIFIED', role: 'CUSTOMER' } }),
    prisma.user.count({ where: { createdAt: { gte: since }, role: 'CUSTOMER' } }),
    prisma.transaction.aggregate({ where: { createdAt: { gte: today } }, _sum: { amount: true, quantity: true }, _count: true }),
    prisma.transaction.aggregate({ where: { createdAt: { gte: since } }, _sum: { amount: true, quantity: true, pointsEarned: true }, _count: true }),
    prisma.transaction.groupBy({ by: ['fuelType'], where: { createdAt: { gte: since } }, _sum: { amount: true, quantity: true } }),
    prisma.transaction.groupBy({ by: ['userId'], where: { createdAt: { gte: since } }, _sum: { amount: true }, _count: true, orderBy: { _sum: { amount: 'desc' } }, take: 10 }),
    prisma.redemption.count({ where: { createdAt: { gte: since } } }),
    prisma.feedback.count({ where: { status: 'OPEN' } }),
    prisma.booking.count({ where: { slot: { gte: new Date() }, status: { in: ['REQUESTED', 'CONFIRMED'] } } }),
    prisma.transaction.findMany({ where: { createdAt: { gte: since } }, select: { createdAt: true, amount: true } }),
  ]);
  const names = await prisma.user.findMany({ where: { id: { in: topCustomers.map((t) => t.userId) } }, select: { id: true, name: true, phone: true, tier: true } });
  const daily = {};
  for (const t of txs) {
    const k = t.createdAt.toISOString().slice(0, 10);
    daily[k] = (daily[k] ?? 0) + Number(t.amount);
  }
  res.json({
    pendingVerifications: pending,
    members,
    newMembers,
    today: { sales: Number(todayAgg._sum.amount ?? 0), quantity: Number(todayAgg._sum.quantity ?? 0), count: todayAgg._count },
    period: { days, sales: Number(periodAgg._sum.amount ?? 0), quantity: Number(periodAgg._sum.quantity ?? 0), count: periodAgg._count, pointsIssued: periodAgg._sum.pointsEarned ?? 0, redemptions },
    byFuel: byFuel.map((f) => ({ fuelType: f.fuelType, sales: Number(f._sum.amount ?? 0), quantity: Number(f._sum.quantity ?? 0) })),
    topCustomers: topCustomers.map((t) => ({ ...names.find((n) => n.id === t.userId), spend: Number(t._sum.amount ?? 0), visits: t._count })),
    dailySales: Object.entries(daily).sort().map(([date, sales]) => ({ date, sales: Math.round(sales * 100) / 100 })),
    openFeedback,
    upcomingBookings,
  });
}));

export default router;
