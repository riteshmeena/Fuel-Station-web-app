import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { Prisma } from '@prisma/client';
import { config } from './config.js';
import { HttpError } from './lib/errors.js';
import { authenticate, requireRole, requireVerified } from './middleware/auth.js';
import authRoutes from './routes/auth.js';
import meRoutes from './routes/me.js';
import publicRoutes from './routes/public.js';
import rewardRoutes from './routes/rewards.js';
import staffRoutes from './routes/staff.js';
import adminRoutes from './routes/admin.js';
import invoiceRoutes from './routes/invoice.js';

export function createApp() {
  const app = express();
  app.set('trust proxy', 1);
  app.use(helmet());
  app.use(cors({ origin: config.corsOrigins.includes('*') ? true : config.corsOrigins }));
  app.use(express.json({ limit: '1mb' }));
  if (process.env.NODE_ENV !== 'test') app.use(morgan('dev'));

  app.get('/health', (_req, res) => res.json({ ok: true }));

  const api = express.Router();
  api.use('/auth', authRoutes);
  api.use('/public', publicRoutes);
  api.use('/me', authenticate, meRoutes);
  api.use('/me', authenticate, invoiceRoutes);
  api.use('/loyalty', authenticate, requireVerified, rewardRoutes);
  api.use('/staff', authenticate, requireRole('STAFF'), staffRoutes);
  api.use('/admin', authenticate, requireRole('ADMIN'), adminRoutes);
  app.use('/api/v1', api);

  app.use((_req, res) => res.status(404).json({ error: { message: 'Route not found', code: 'NOT_FOUND' } }));

  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => {
    if (err instanceof HttpError) return res.status(err.status).json({ error: { message: err.message, code: err.code } });
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2025') {
      return res.status(404).json({ error: { message: 'Not found', code: 'NOT_FOUND' } });
    }
    if (err.type === 'entity.parse.failed') return res.status(400).json({ error: { message: 'Invalid JSON', code: 'BAD_JSON' } });
    console.error(err);
    res.status(500).json({ error: { message: 'Something went wrong', code: 'INTERNAL' } });
  });
  return app;
}
