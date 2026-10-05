import { prisma } from '../lib/prisma.js';
import { verifyToken } from '../lib/auth.js';
import { unauthorized, forbidden } from '../lib/errors.js';

export async function authenticate(req, _res, next) {
  try {
    const header = req.headers.authorization ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : null;
    if (!token) throw unauthorized();
    let payload;
    try {
      payload = verifyToken(token);
    } catch {
      throw unauthorized('Session expired, please log in again', 'TOKEN_INVALID');
    }
    const user = await prisma.user.findUnique({ where: { id: payload.sub } });
    if (!user || user.tokenVersion !== payload.v) throw unauthorized('Session expired, please log in again', 'TOKEN_INVALID');
    if (user.status === 'BLOCKED') throw forbidden('Your account has been blocked. Please contact the station.', 'ACCOUNT_BLOCKED');
    req.user = user;
    next();
  } catch (e) {
    next(e);
  }
}

// Pending accounts can log in and see their status, but cannot use loyalty features.
export function requireVerified(req, _res, next) {
  if (req.user.status !== 'VERIFIED') {
    return next(forbidden('Your account is awaiting verification by the station admin.', 'ACCOUNT_PENDING'));
  }
  next();
}

const RANK = { CUSTOMER: 0, STAFF: 1, ADMIN: 2, SUPERADMIN: 3 };
export const requireRole = (min) => (req, _res, next) =>
  RANK[req.user.role] >= RANK[min] ? next() : next(forbidden());
