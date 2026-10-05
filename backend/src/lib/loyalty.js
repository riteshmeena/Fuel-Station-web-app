import { getSetting } from './settings.js';

export const TIER_ORDER = ['SILVER', 'GOLD', 'PLATINUM'];

export function tierForSpend(spend, thresholds) {
  let tier = 'SILVER';
  for (const t of TIER_ORDER) if (spend >= thresholds[t]) tier = t;
  return tier;
}

export function pointsFor(amount, tier, cfg) {
  const base = Math.floor(amount / 100) * cfg.pointsPer100;
  return Math.floor(base * (cfg.tierMultiplier[tier] ?? 1));
}

export async function tierProgress(user) {
  const cfg = await getSetting('loyalty');
  const spend = Number(user.lifetimeSpend);
  const idx = TIER_ORDER.indexOf(user.tier);
  const next = TIER_ORDER[idx + 1] ?? null;
  const currentFloor = cfg.tierThresholds[user.tier];
  const nextAt = next ? cfg.tierThresholds[next] : null;
  return {
    tier: user.tier,
    nextTier: next,
    lifetimeSpend: spend,
    nextTierAt: nextAt,
    remaining: next ? Math.max(0, nextAt - spend) : 0,
    progress: next ? Math.min(1, (spend - currentFloor) / (nextAt - currentFloor)) : 1,
    multiplier: cfg.tierMultiplier[user.tier],
    pointValueInr: cfg.pointValueInr,
  };
}
