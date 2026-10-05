import jwt from 'jsonwebtoken';
import { config } from '../config.js';

export const signToken = (user) =>
  jwt.sign({ sub: user.id, role: user.role, v: user.tokenVersion }, config.jwtSecret, { expiresIn: config.jwtExpiresIn });

export const verifyToken = (token) => jwt.verify(token, config.jwtSecret);

// Shape returned to clients — never leak pinHash / googleSub.
export const publicUser = (u) => ({
  id: u.id,
  name: u.name,
  phone: u.phone,
  email: u.email,
  role: u.role,
  status: u.status,
  cardNumber: u.cardNumber,
  points: u.points,
  tier: u.tier,
  lifetimeSpend: Number(u.lifetimeSpend),
  referralCode: u.referralCode,
  avatarUrl: u.avatarUrl,
  googleLinked: Boolean(u.googleSub),
  verifiedAt: u.verifiedAt,
  createdAt: u.createdAt,
});
