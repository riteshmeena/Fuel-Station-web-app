import bcrypt from 'bcryptjs';
import { PrismaClient } from '@prisma/client';
import { newCardNumber, newReferralCode } from '../src/lib/codes.js';

const prisma = new PrismaClient();

async function upsertUser({ name, phone, pin, role, status = 'VERIFIED' }) {
  return prisma.user.upsert({
    where: { phone },
    update: {},
    create: {
      name, phone, role, status,
      pinHash: await bcrypt.hash(pin, 10),
      cardNumber: newCardNumber(),
      referralCode: newReferralCode(name),
      verifiedAt: status === 'VERIFIED' ? new Date() : null,
    },
  });
}

async function main() {
  const admin = await upsertUser({
    name: process.env.SUPERADMIN_NAME ?? 'Station Owner',
    phone: process.env.SUPERADMIN_PHONE ?? '9000000001',
    pin: process.env.SUPERADMIN_PIN ?? '1234',
    role: 'SUPERADMIN',
  });

  if (!(await prisma.fuelPrice.count())) {
    // Two days of prices so the ▲/▼ change indicator has data.
    const yesterday = new Date(Date.now() - 864e5);
    const base = { PETROL: 104.72, DIESEL: 90.21, PREMIUM_PETROL: 112.4, CNG: 79.5 };
    const today = { PETROL: 104.88, DIESEL: 90.08, PREMIUM_PETROL: 112.4, CNG: 79.5 };
    await prisma.fuelPrice.createMany({
      data: [
        ...Object.entries(base).map(([fuelType, p]) => ({ fuelType, pricePerUnit: p, effectiveDate: yesterday, updatedById: admin.id })),
        ...Object.entries(today).map(([fuelType, p]) => ({ fuelType, pricePerUnit: p, updatedById: admin.id })),
      ],
    });
  }

  if (!(await prisma.reward.count())) {
    await prisma.reward.createMany({
      data: [
        { title: 'Free Tyre Nitrogen Fill', description: 'Nitrogen top-up for all 4 tyres', pointsCost: 40, category: 'Services' },
        { title: 'Free Car Foam Wash', description: 'Exterior foam wash for one car', pointsCost: 150, category: 'Services' },
        { title: '₹100 Fuel Voucher', description: 'Get ₹100 off your next fill-up', pointsCost: 400, category: 'Fuel' },
        { title: '1L Engine Oil', description: 'Premium 4T / car engine oil, 1 litre', pointsCost: 600, category: 'Lubricants', stock: 50 },
        { title: 'Store Snack Combo', description: 'Chips + cold drink at our store', pointsCost: 80, category: 'Store' },
        { title: 'Free PUC Test', description: 'Pollution Under Control certificate', pointsCost: 120, category: 'Services' },
      ],
    });
  }

  if (!(await prisma.offer.count())) {
    const in30 = new Date(Date.now() + 30 * 864e5);
    await prisma.offer.createMany({
      data: [
        { title: 'Double Points Weekend', description: 'Earn 2× points every Saturday & Sunday this month.', endsAt: in30 },
        { title: 'Welcome Gift: +20 Points', description: 'Claim 20 bonus points as a thank-you for joining.', bonusPoints: 20, endsAt: in30 },
        { title: 'Gold Members: Free Wash', description: 'Gold & Platinum members get one free wash on ₹2,000+ fill.', minTier: 'GOLD', endsAt: in30 },
      ],
    });
  }

  if (!(await prisma.announcement.count())) {
    await prisma.announcement.create({ data: { title: 'Now open 24×7', body: 'We are now serving you round the clock with free air and clean restrooms.' } });
  }

  if (process.env.SEED_DEMO === 'true') {
    await upsertUser({ name: 'Demo Staff', phone: '9000000002', pin: '1111', role: 'STAFF' });
    await upsertUser({ name: 'Rahul Sharma', phone: '9876543210', pin: '4321', role: 'CUSTOMER', status: 'PENDING' });
  }
  console.log(`Seeded. Super admin phone ${admin.phone}`);
}

main().finally(() => prisma.$disconnect());
