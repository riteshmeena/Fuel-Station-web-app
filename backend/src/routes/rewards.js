import { Router } from 'express';
import { prisma } from '../lib/prisma.js';
import { ah, badRequest, conflict, notFound } from '../lib/errors.js';
import { newRedemptionCode } from '../lib/codes.js';
import { notify } from '../lib/notify.js';
import { TIER_ORDER } from '../lib/loyalty.js';

const router = Router();

router.get('/redemptions', ah(async (req, res) => {
  res.json(await prisma.redemption.findMany({ where: { userId: req.user.id }, include: { reward: true }, orderBy: { createdAt: 'desc' } }));
}));

router.post('/rewards/:id/redeem', ah(async (req, res) => {
  const redemption = await prisma.$transaction(async (tx) => {
    const reward = await tx.reward.findUnique({ where: { id: req.params.id } });
    if (!reward || !reward.active) throw notFound('Reward not found');
    if (reward.stock !== null && reward.stock <= 0) throw conflict('This reward is out of stock', 'OUT_OF_STOCK');
    // Conditional decrement guards against double-spend under concurrent requests.
    const { count } = await tx.user.updateMany({
      where: { id: req.user.id, points: { gte: reward.pointsCost } },
      data: { points: { decrement: reward.pointsCost } },
    });
    if (!count) throw badRequest('Not enough points', 'INSUFFICIENT_POINTS');
    if (reward.stock !== null) {
      const s = await tx.reward.updateMany({ where: { id: reward.id, stock: { gt: 0 } }, data: { stock: { decrement: 1 } } });
      if (!s.count) throw conflict('This reward is out of stock', 'OUT_OF_STOCK');
    }
    const r = await tx.redemption.create({
      data: { code: newRedemptionCode(), userId: req.user.id, rewardId: reward.id, pointsUsed: reward.pointsCost },
      include: { reward: true },
    });
    await tx.pointsLedger.create({ data: { userId: req.user.id, type: 'REDEEM', points: -reward.pointsCost, note: reward.title, refId: r.id } });
    return r;
  });
  await notify(req.user.id, 'Reward redeemed 🎁', `Show code ${redemption.code} at the counter to claim "${redemption.reward.title}".`, 'REWARD');
  res.status(201).json(redemption);
}));

router.post('/offers/:id/claim', ah(async (req, res) => {
  const offer = await prisma.offer.findUnique({ where: { id: req.params.id } });
  if (!offer || !offer.active || offer.endsAt < new Date() || offer.startsAt > new Date()) throw notFound('Offer not available');
  if (TIER_ORDER.indexOf(req.user.tier) < TIER_ORDER.indexOf(offer.minTier)) throw badRequest(`This offer is for ${offer.minTier} members and above`, 'TIER_TOO_LOW');
  try {
    const claim = await prisma.$transaction(async (tx) => {
      const c = await tx.userCoupon.create({ data: { userId: req.user.id, offerId: offer.id }, include: { offer: true } });
      if (offer.bonusPoints > 0) {
        await tx.user.update({ where: { id: req.user.id }, data: { points: { increment: offer.bonusPoints } } });
        await tx.pointsLedger.create({ data: { userId: req.user.id, type: 'BONUS', points: offer.bonusPoints, note: offer.title, refId: offer.id } });
      }
      return c;
    });
    res.status(201).json(claim);
  } catch (e) {
    if (e.code === 'P2002') throw conflict('You have already claimed this offer', 'ALREADY_CLAIMED');
    throw e;
  }
}));

router.get('/coupons', ah(async (req, res) => {
  res.json(await prisma.userCoupon.findMany({ where: { userId: req.user.id }, include: { offer: true }, orderBy: { createdAt: 'desc' } }));
}));

export default router;
