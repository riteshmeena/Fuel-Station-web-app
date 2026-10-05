import { prisma } from './prisma.js';

export const DEFAULT_SETTINGS = {
  station: {
    name: 'My Fuel Station',
    brand: 'IOCL',
    tagline: 'Pure fuel. Honest measure.',
    address: 'NH-48, Near City Junction',
    city: 'Jaipur',
    state: 'Rajasthan',
    pincode: '302001',
    phone: '+919999999999',
    whatsapp: '+919999999999',
    email: 'hello@example.com',
    latitude: 26.9124,
    longitude: 75.7873,
    gstin: '',
    openHours: 'Open 24 × 7',
    services: ['Free Air', 'Nitrogen', 'PUC Centre', 'Car Wash', 'Lubricants', 'Convenience Store', 'Restroom', 'Drinking Water'],
    availableFuels: ['PETROL', 'DIESEL', 'PREMIUM_PETROL', 'CNG'],
  },
  loyalty: {
    pointsPer100: 1, // points earned per ₹100 spent (before tier multiplier)
    tierMultiplier: { SILVER: 1, GOLD: 1.5, PLATINUM: 2 },
    tierThresholds: { SILVER: 0, GOLD: 25000, PLATINUM: 100000 }, // lifetime spend in ₹
    referralBonus: 50,
    welcomeBonus: 25,
    pointValueInr: 0.25,
  },
};

export async function getSetting(key) {
  const row = await prisma.setting.findUnique({ where: { key } });
  return { ...DEFAULT_SETTINGS[key], ...(row?.value ?? {}) };
}

export async function setSetting(key, patch) {
  const current = await getSetting(key);
  const value = { ...current, ...patch };
  await prisma.setting.upsert({ where: { key }, update: { value }, create: { key, value } });
  return value;
}
