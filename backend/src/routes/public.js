import { Router } from 'express';
import { prisma } from '../lib/prisma.js';
import { ah } from '../lib/errors.js';
import { getSetting } from '../lib/settings.js';

const router = Router();

// Latest price per fuel type plus the previous one, so clients can show ▲/▼ change.
export async function currentPrices() {
  const station = await getSetting('station');
  const out = [];
  for (const fuelType of station.availableFuels) {
    const [latest, previous] = await prisma.fuelPrice.findMany({
      where: { fuelType, effectiveDate: { lte: new Date() } },
      orderBy: { effectiveDate: 'desc' },
      take: 2,
    });
    if (!latest) continue;
    const price = Number(latest.pricePerUnit);
    const prev = previous ? Number(previous.pricePerUnit) : price;
    out.push({
      fuelType,
      unit: fuelType === 'CNG' ? 'kg' : fuelType === 'EV' ? 'kWh' : 'L',
      price,
      previousPrice: prev,
      change: Math.round((price - prev) * 100) / 100,
      updatedAt: latest.effectiveDate,
    });
  }
  return out;
}

router.get('/station', ah(async (_req, res) => res.json(await getSetting('station'))));

router.get('/prices', ah(async (_req, res) => res.json(await currentPrices())));

router.get('/prices/history', ah(async (req, res) => {
  const days = Math.min(365, Math.max(1, Number(req.query.days ?? 30)));
  const rows = await prisma.fuelPrice.findMany({
    where: { effectiveDate: { gte: new Date(Date.now() - days * 864e5) } },
    orderBy: { effectiveDate: 'asc' },
  });
  res.json(rows.map((r) => ({ fuelType: r.fuelType, price: Number(r.pricePerUnit), date: r.effectiveDate })));
}));

router.get('/offers', ah(async (_req, res) => {
  res.json(await prisma.offer.findMany({ where: { active: true, startsAt: { lte: new Date() }, endsAt: { gte: new Date() } }, orderBy: { createdAt: 'desc' } }));
}));

router.get('/rewards', ah(async (_req, res) => {
  res.json(await prisma.reward.findMany({ where: { active: true }, orderBy: { pointsCost: 'asc' } }));
}));

router.get('/announcements', ah(async (_req, res) => {
  res.json(await prisma.announcement.findMany({ where: { published: true }, orderBy: { createdAt: 'desc' }, take: 20 }));
}));

router.get('/loyalty', ah(async (_req, res) => res.json(await getSetting('loyalty'))));

export default router;
