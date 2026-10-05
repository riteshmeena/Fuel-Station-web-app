import { prisma } from './prisma.js';

// In-app notification inbox. Push delivery (FCM/APNs) can hook in here later at no cost.
export const notify = (userId, title, body, kind = 'INFO') =>
  prisma.notification.create({ data: { userId, title, body, kind } });
