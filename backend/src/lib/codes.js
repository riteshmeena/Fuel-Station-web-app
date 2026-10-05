import { customAlphabet } from 'nanoid';

const digits = customAlphabet('0123456789', 12);
const alnum = customAlphabet('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 8);

export const newCardNumber = () => {
  const d = digits();
  return `${d.slice(0, 4)} ${d.slice(4, 8)} ${d.slice(8, 12)}`;
};
export const newReferralCode = (name) => `${name.replace(/[^A-Za-z]/g, '').slice(0, 4).toUpperCase() || 'FUEL'}${alnum().slice(0, 4)}`;
export const newRedemptionCode = () => `RW-${alnum()}`;
export const newInvoiceNo = () => {
  const d = new Date();
  const ymd = `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}`;
  return `INV-${ymd}-${alnum().slice(0, 6)}`;
};
