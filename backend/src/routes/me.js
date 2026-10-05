import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../lib/prisma.js';
import { ah, conflict, notFound } from '../lib/errors.js';
import { parse, regNumberSchema, fuelTypeSchema, paginationSchema } from '../lib/validate.js';
import { publicUser } from '../lib/auth.js';
import { tierProgress } from '../lib/loyalty.js';
import { requireVerified } from '../middleware/auth.js';

const router = Router();

router.get(
  '/',
  ah(async (req, res) => {
    res.json({ user: publicUser(req.user), tierProgress: await tierProgress(req.user) });
  }),
);

router.patch(
  '/',
  ah(async (req, res) => {
    const data = parse(
      z.object({
        name: z.string().trim().min(2).max(60).optional(),
        email: z.string().email().nullable().optional(),
        avatarUrl: z.string().url().nullable().optional(),
        pushToken: z.string().max(300).nullable().optional(),
      }),
      req.body,
    );
    if (data.email) {
      const other = await prisma.user.findUnique({ where: { email: data.email } });
      if (other && other.id !== req.user.id) throw conflict('Email already in use', 'EMAIL_TAKEN');
    }
    const user = await prisma.user.update({ where: { id: req.user.id }, data });
    res.json({ user: publicUser(user) });
  }),
);

// Home screen payload in one request: profile, tier, prices, latest offers & activity.
router.get(
  '/dashboard',
  ah(async (req, res) => {
    const uid = req.user.id;
    const monthStart = new Date(new Date().getFullYear(), new Date().getMonth(), 1);
    const [tier, recent, monthAgg, unread, offers, reminders, vehicles] = await Promise.all([
      tierProgress(req.user),
      prisma.transaction.findMany({ where: { userId: uid }, orderBy: { createdAt: 'desc' }, take: 5, include: { vehicle: true } }),
      prisma.transaction.aggregate({ where: { userId: uid, createdAt: { gte: monthStart } }, _sum: { amount: true, quantity: true, pointsEarned: true }, _count: true }),
      prisma.notification.count({ where: { userId: uid, read: false } }),
      prisma.offer.findMany({ where: { active: true, endsAt: { gte: new Date() } }, orderBy: { createdAt: 'desc' }, take: 5 }),
      prisma.reminder.findMany({ where: { userId: uid, done: false }, orderBy: { dueDate: 'asc' }, take: 3 }),
      prisma.vehicle.findMany({ where: { userId: uid }, orderBy: [{ isDefault: 'desc' }, { createdAt: 'asc' }] }),
    ]);
    res.json({
      user: publicUser(req.user),
      tierProgress: tier,
      month: {
        spend: Number(monthAgg._sum.amount ?? 0),
        quantity: Number(monthAgg._sum.quantity ?? 0),
        points: monthAgg._sum.pointsEarned ?? 0,
        visits: monthAgg._count,
      },
      recentTransactions: recent.map(serializeTx),
      unreadNotifications: unread,
      offers,
      upcomingReminders: reminders,
      vehicles,
    });
  }),
);

export const serializeTx = (t) => ({
  ...t,
  quantity: Number(t.quantity),
  pricePerUnit: Number(t.pricePerUnit),
  amount: Number(t.amount),
});

// ---- Vehicles ----
const vehicleSchema = z.object({
  regNumber: regNumberSchema,
  fuelType: fuelTypeSchema,
  nickname: z.string().trim().max(30).optional(),
  make: z.string().trim().max(30).optional(),
  model: z.string().trim().max(30).optional(),
  isDefault: z.boolean().optional(),
});

router.get('/vehicles', ah(async (req, res) => {
  res.json(await prisma.vehicle.findMany({ where: { userId: req.user.id }, orderBy: [{ isDefault: 'desc' }, { createdAt: 'asc' }] }));
}));

router.post('/vehicles', ah(async (req, res) => {
  const data = parse(vehicleSchema, req.body);
  const count = await prisma.vehicle.count({ where: { userId: req.user.id } });
  if (count >= 10) throw conflict('You can save up to 10 vehicles');
  const isDefault = data.isDefault || count === 0;
  try {
    const vehicle = await prisma.$transaction(async (tx) => {
      if (isDefault) await tx.vehicle.updateMany({ where: { userId: req.user.id }, data: { isDefault: false } });
      return tx.vehicle.create({ data: { ...data, isDefault, userId: req.user.id } });
    });
    res.status(201).json(vehicle);
  } catch (e) {
    if (e.code === 'P2002') throw conflict('This vehicle is already saved');
    throw e;
  }
}));

router.patch('/vehicles/:id', ah(async (req, res) => {
  const data = parse(vehicleSchema.partial(), req.body);
  const existing = await prisma.vehicle.findFirst({ where: { id: req.params.id, userId: req.user.id } });
  if (!existing) throw notFound('Vehicle not found');
  const vehicle = await prisma.$transaction(async (tx) => {
    if (data.isDefault) await tx.vehicle.updateMany({ where: { userId: req.user.id }, data: { isDefault: false } });
    return tx.vehicle.update({ where: { id: existing.id }, data });
  });
  res.json(vehicle);
}));

router.delete('/vehicles/:id', ah(async (req, res) => {
  const { count } = await prisma.vehicle.deleteMany({ where: { id: req.params.id, userId: req.user.id } });
  if (!count) throw notFound('Vehicle not found');
  res.status(204).end();
}));

// ---- Fill-up history & insights ----
router.get('/transactions', ah(async (req, res) => {
  const { page, limit } = parse(paginationSchema, req.query);
  const where = { userId: req.user.id };
  const [items, total] = await Promise.all([
    prisma.transaction.findMany({ where, orderBy: { createdAt: 'desc' }, skip: (page - 1) * limit, take: limit, include: { vehicle: true } }),
    prisma.transaction.count({ where }),
  ]);
  res.json({ items: items.map(serializeTx), total, page, limit });
}));

router.get('/transactions/:id', ah(async (req, res) => {
  const tx = await prisma.transaction.findFirst({ where: { id: req.params.id, userId: req.user.id }, include: { vehicle: true } });
  if (!tx) throw notFound('Transaction not found');
  res.json(serializeTx(tx));
}));

// Monthly spend/litres for the last N months + mileage per vehicle (from odometer readings).
router.get('/insights', ah(async (req, res) => {
  const months = Math.min(24, Math.max(1, Number(req.query.months ?? 6)));
  const since = new Date(new Date().getFullYear(), new Date().getMonth() - months + 1, 1);
  const txs = await prisma.transaction.findMany({
    where: { userId: req.user.id, createdAt: { gte: since } },
    orderBy: { createdAt: 'asc' },
    include: { vehicle: true },
  });
  const buckets = new Map();
  for (let i = 0; i < months; i++) {
    const d = new Date(since.getFullYear(), since.getMonth() + i, 1);
    buckets.set(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`, { month: '', spend: 0, quantity: 0, visits: 0, points: 0 });
  }
  const byFuel = {};
  for (const t of txs) {
    const key = `${t.createdAt.getFullYear()}-${String(t.createdAt.getMonth() + 1).padStart(2, '0')}`;
    const b = buckets.get(key);
    if (b) {
      b.spend += Number(t.amount);
      b.quantity += Number(t.quantity);
      b.visits += 1;
      b.points += t.pointsEarned;
    }
    byFuel[t.fuelType] = (byFuel[t.fuelType] ?? 0) + Number(t.amount);
  }
  // Mileage: distance between consecutive odometer readings ÷ fuel added at the later fill.
  const mileage = {};
  const lastOdo = {};
  for (const t of txs) {
    if (!t.vehicleId || !t.odometerKm) continue;
    const prev = lastOdo[t.vehicleId];
    if (prev && t.odometerKm > prev) {
      const m = (mileage[t.vehicleId] ??= { vehicleId: t.vehicleId, regNumber: t.vehicle?.regNumber, km: 0, quantity: 0 });
      m.km += t.odometerKm - prev;
      m.quantity += Number(t.quantity);
    }
    lastOdo[t.vehicleId] = t.odometerKm;
  }
  res.json({
    monthly: [...buckets].map(([month, v]) => ({ ...v, month, spend: Math.round(v.spend * 100) / 100, quantity: Math.round(v.quantity * 100) / 100 })),
    byFuel: Object.entries(byFuel).map(([fuelType, spend]) => ({ fuelType, spend: Math.round(spend * 100) / 100 })),
    mileage: Object.values(mileage).map((m) => ({ ...m, kmPerUnit: m.quantity ? Math.round((m.km / m.quantity) * 10) / 10 : null })),
  });
}));

// ---- Points ledger ----
router.get('/points', requireVerified, ah(async (req, res) => {
  const { page, limit } = parse(paginationSchema, req.query);
  const where = { userId: req.user.id };
  const [items, total] = await Promise.all([
    prisma.pointsLedger.findMany({ where, orderBy: { createdAt: 'desc' }, skip: (page - 1) * limit, take: limit }),
    prisma.pointsLedger.count({ where }),
  ]);
  res.json({ balance: req.user.points, items, total, page, limit });
}));

// ---- Notifications ----
router.get('/notifications', ah(async (req, res) => {
  const { page, limit } = parse(paginationSchema, req.query);
  const items = await prisma.notification.findMany({ where: { userId: req.user.id }, orderBy: { createdAt: 'desc' }, skip: (page - 1) * limit, take: limit });
  res.json({ items, page, limit });
}));

router.post('/notifications/read-all', ah(async (req, res) => {
  await prisma.notification.updateMany({ where: { userId: req.user.id, read: false }, data: { read: true } });
  res.status(204).end();
}));

router.post('/notifications/:id/read', ah(async (req, res) => {
  await prisma.notification.updateMany({ where: { id: req.params.id, userId: req.user.id }, data: { read: true } });
  res.status(204).end();
}));

// ---- Reminders (PUC, insurance, service…) ----
const reminderSchema = z.object({
  type: z.enum(['PUC', 'INSURANCE', 'SERVICE', 'TYRE', 'CUSTOM']),
  title: z.string().trim().min(2).max(80),
  dueDate: z.coerce.date(),
  vehicleReg: z.string().trim().max(15).optional(),
  done: z.boolean().optional(),
});

router.get('/reminders', ah(async (req, res) => {
  res.json(await prisma.reminder.findMany({ where: { userId: req.user.id }, orderBy: [{ done: 'asc' }, { dueDate: 'asc' }] }));
}));
router.post('/reminders', ah(async (req, res) => {
  const data = parse(reminderSchema, req.body);
  res.status(201).json(await prisma.reminder.create({ data: { ...data, userId: req.user.id } }));
}));
router.patch('/reminders/:id', ah(async (req, res) => {
  const data = parse(reminderSchema.partial(), req.body);
  const { count } = await prisma.reminder.updateMany({ where: { id: req.params.id, userId: req.user.id }, data });
  if (!count) throw notFound('Reminder not found');
  res.json(await prisma.reminder.findUnique({ where: { id: req.params.id } }));
}));
router.delete('/reminders/:id', ah(async (req, res) => {
  const { count } = await prisma.reminder.deleteMany({ where: { id: req.params.id, userId: req.user.id } });
  if (!count) throw notFound('Reminder not found');
  res.status(204).end();
}));

// ---- Bookings (wash / oil change / PUC) — booking only, no payment ----
router.get('/bookings', ah(async (req, res) => {
  res.json(await prisma.booking.findMany({ where: { userId: req.user.id }, orderBy: { slot: 'desc' } }));
}));
router.post('/bookings', requireVerified, ah(async (req, res) => {
  const data = parse(
    z.object({
      service: z.enum(['CAR_WASH', 'OIL_CHANGE', 'PUC_TEST', 'TYRE_CHECK', 'GENERAL_SERVICE']),
      slot: z.coerce.date().refine((d) => d > new Date(), 'Slot must be in the future'),
      vehicleReg: z.string().trim().max(15).optional(),
      notes: z.string().trim().max(300).optional(),
    }),
    req.body,
  );
  const clash = await prisma.booking.count({ where: { slot: data.slot, service: data.service, status: { in: ['REQUESTED', 'CONFIRMED'] } } });
  if (clash >= 2) throw conflict('This slot is full, please pick another time', 'SLOT_FULL');
  res.status(201).json(await prisma.booking.create({ data: { ...data, userId: req.user.id } }));
}));
router.post('/bookings/:id/cancel', ah(async (req, res) => {
  const { count } = await prisma.booking.updateMany({
    where: { id: req.params.id, userId: req.user.id, status: { in: ['REQUESTED', 'CONFIRMED'] } },
    data: { status: 'CANCELLED' },
  });
  if (!count) throw notFound('Booking not found or already closed');
  res.json(await prisma.booking.findUnique({ where: { id: req.params.id } }));
}));

// ---- Feedback ----
router.get('/feedback', ah(async (req, res) => {
  res.json(await prisma.feedback.findMany({ where: { userId: req.user.id }, orderBy: { createdAt: 'desc' } }));
}));
router.post('/feedback', ah(async (req, res) => {
  const data = parse(
    z.object({
      rating: z.number().int().min(1).max(5),
      category: z.enum(['General', 'Fuel Quality', 'Quantity', 'Staff Behaviour', 'Cleanliness', 'App', 'Other']).default('General'),
      message: z.string().trim().min(3).max(1000),
    }),
    req.body,
  );
  res.status(201).json(await prisma.feedback.create({ data: { ...data, userId: req.user.id } }));
}));

// ---- Referrals ----
router.get('/referrals', ah(async (req, res) => {
  const referred = await prisma.user.findMany({
    where: { referredById: req.user.id },
    select: { name: true, status: true, createdAt: true },
    orderBy: { createdAt: 'desc' },
  });
  res.json({ code: req.user.referralCode, referred });
}));

export default router;
