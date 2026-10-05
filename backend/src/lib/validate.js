import { z } from 'zod';
import { badRequest } from './errors.js';

export const parse = (schema, data) => {
  const result = schema.safeParse(data);
  if (!result.success) {
    const issue = result.error.issues[0];
    throw badRequest(`${issue.path.join('.') || 'input'}: ${issue.message}`, 'VALIDATION');
  }
  return result.data;
};

// Indian mobile: 10 digits starting 6-9, optional +91 / 0 prefix.
export const phoneSchema = z
  .string()
  .transform((s) => s.replace(/[\s-]/g, '').replace(/^(\+91|91|0)(?=\d{10}$)/, ''))
  .pipe(z.string().regex(/^[6-9]\d{9}$/, 'Enter a valid 10-digit Indian mobile number'));

export const pinSchema = z.string().regex(/^\d{4}$/, 'PIN must be 4 digits');

// e.g. MH12AB1234, DL3CAF0001, 22BH1234AA (BH series)
export const regNumberSchema = z
  .string()
  .transform((s) => s.toUpperCase().replace(/[\s-]/g, ''))
  .pipe(z.string().regex(/^([A-Z]{2}\d{1,2}[A-Z]{0,3}\d{1,4}|\d{2}BH\d{4}[A-Z]{1,2})$/, 'Enter a valid vehicle number'));

export const fuelTypeSchema = z.enum(['PETROL', 'DIESEL', 'PREMIUM_PETROL', 'CNG', 'EV']);

export const paginationSchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});
