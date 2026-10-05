// End-to-end flow against a real Postgres (DATABASE_URL). Run: npm test
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../src/app.js';
import { prisma } from '../src/lib/prisma.js';

process.env.NODE_ENV = 'test';
let server, base;
const phone = `9${String(Date.now()).slice(-9)}`;
const friendPhone = `8${String(Date.now() + 7).slice(-9)}`;

const call = async (method, path, { token, body } = {}) => {
  const res = await fetch(base + path, {
    method,
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch { json = text; }
  return { status: res.status, json, headers: res.headers };
};

before(async () => {
  server = createApp().listen(0);
  base = `http://127.0.0.1:${server.address().port}/api/v1`;
});
after(async () => {
  await prisma.user.deleteMany({ where: { phone: { in: [phone, friendPhone] } } }).catch(() => {});
  server.close();
  await prisma.$disconnect();
});

test('full customer → admin verify → staff fill-up → redeem flow', async () => {
  const prices = await call('GET', '/public/prices');
  assert.equal(prices.status, 200);
  assert.ok(prices.json.find((p) => p.fuelType === 'PETROL'));

  // Register (no OTP), status PENDING
  const reg = await call('POST', '/auth/register', { body: { name: 'Test User', phone: `+91 ${phone}`, pin: '2468', vehicle: { regNumber: 'rj 14 cd 1234', fuelType: 'PETROL' } } });
  assert.equal(reg.status, 201, JSON.stringify(reg.json));
  assert.equal(reg.json.user.status, 'PENDING');
  const token = reg.json.token;

  const friend = await call('POST', '/auth/register', { body: { name: 'Friend', phone: friendPhone, pin: '1357', referralCode: reg.json.user.referralCode } });
  assert.equal(friend.status, 201);

  const dup = await call('POST', '/auth/register', { body: { name: 'Dup', phone, pin: '1111' } });
  assert.equal(dup.status, 409);

  const bad = await call('POST', '/auth/login', { body: { phone, pin: '0000' } });
  assert.equal(bad.status, 401);
  const login = await call('POST', '/auth/login', { body: { phone, pin: '2468' } });
  assert.equal(login.status, 200);

  // Pending users are blocked from loyalty
  const blocked = await call('GET', '/loyalty/redemptions', { token });
  assert.equal(blocked.status, 403);
  assert.equal(blocked.json.error.code, 'ACCOUNT_PENDING');

  // Super admin verifies
  const adm = await call('POST', '/auth/login', { body: { phone: '9000000001', pin: '1234' } });
  const at = adm.json.token;
  const pending = await call('GET', '/admin/users?status=PENDING&q=' + phone, { token: at });
  assert.equal(pending.json.items.length, 1);
  const v = await call('POST', '/admin/users/verify-bulk', { token: at, body: { ids: [reg.json.user.id, friend.json.user.id] } });
  assert.ok(v.json.results.every((r) => r.ok), JSON.stringify(v.json));

  const me = await call('GET', '/me', { token });
  assert.equal(me.json.user.status, 'VERIFIED');
  assert.equal(me.json.user.points, 25 + 50); // welcome + referral

  // Staff records fill-up by scanning QR
  const staff = await call('POST', '/auth/login', { body: { phone: '9000000002', pin: '1111' } });
  const card = `FS:${me.json.user.cardNumber.replace(/\s/g, '')}`;
  const look = await call('GET', `/staff/lookup?code=${encodeURIComponent(card)}`, { token: staff.json.token });
  assert.equal(look.status, 200);
  const fill = await call('POST', '/staff/transactions', { token: staff.json.token, body: { code: card, vehicleId: look.json.vehicles[0].id, fuelType: 'PETROL', amount: 30000, odometerKm: 12000 } });
  assert.equal(fill.status, 201, JSON.stringify(fill.json));
  assert.equal(fill.json.pointsEarned, 300);
  assert.equal(fill.json.tierUpgrade, 'GOLD');
  await call('POST', '/staff/transactions', { token: staff.json.token, body: { code: card, vehicleId: look.json.vehicles[0].id, fuelType: 'PETROL', quantity: 10, odometerKm: 12150 } });

  const custForbidden = await call('GET', '/staff/my-shift', { token });
  assert.equal(custForbidden.status, 403);

  const dash = await call('GET', '/me/dashboard', { token });
  assert.equal(dash.status, 200);
  assert.equal(dash.json.user.tier, 'GOLD');
  assert.ok(dash.json.unreadNotifications >= 2);

  const ins = await call('GET', '/me/insights', { token });
  assert.equal(ins.json.mileage[0].kmPerUnit, 15);

  // Invoice PDF
  const inv = await fetch(`${base}/me/transactions/${fill.json.transaction.id}/invoice.pdf`, { headers: { authorization: `Bearer ${token}` } });
  assert.equal(inv.headers.get('content-type'), 'application/pdf');

  // Redeem reward, staff marks it used
  const rewards = await call('GET', '/public/rewards');
  const wash = rewards.json.find((r) => r.pointsCost === 150);
  const red = await call('POST', `/loyalty/rewards/${wash.id}/redeem`, { token });
  assert.equal(red.status, 201, JSON.stringify(red.json));
  const use = await call('POST', '/staff/redemptions/use', { token: staff.json.token, body: { code: red.json.code } });
  assert.equal(use.status, 200);
  const again = await call('POST', '/staff/redemptions/use', { token: staff.json.token, body: { code: red.json.code } });
  assert.equal(again.status, 409);

  // Claim offer once
  const offers = await call('GET', '/public/offers');
  const gift = offers.json.find((o) => o.bonusPoints > 0);
  assert.equal((await call('POST', `/loyalty/offers/${gift.id}/claim`, { token })).status, 201);
  assert.equal((await call('POST', `/loyalty/offers/${gift.id}/claim`, { token })).status, 409);

  // Change PIN logs out old token
  const cp = await call('POST', '/auth/change-pin', { token, body: { currentPin: '2468', newPin: '9753' } });
  assert.equal(cp.status, 200);
  assert.equal((await call('GET', '/me', { token })).status, 401);
  assert.equal((await call('GET', '/me', { token: cp.json.token })).status, 200);

  const an = await call('GET', '/admin/analytics', { token: at });
  assert.equal(an.status, 200);
  assert.ok(an.json.today.sales >= 30000);
});
