import { Router } from 'express';
import PDFDocument from 'pdfkit';
import { prisma } from '../lib/prisma.js';
import { ah, notFound } from '../lib/errors.js';
import { getSetting } from '../lib/settings.js';

const router = Router();
const FUEL_LABEL = { PETROL: 'Petrol', DIESEL: 'Diesel', PREMIUM_PETROL: 'Premium Petrol', CNG: 'CNG', EV: 'EV Charging' };

// Free, generated-on-the-fly PDF receipt. (PDFKit's built-in fonts lack ₹, so "Rs." is used.)
router.get('/transactions/:id/invoice.pdf', ah(async (req, res) => {
  const t = await prisma.transaction.findFirst({ where: { id: req.params.id, userId: req.user.id }, include: { vehicle: true, user: true } });
  if (!t) throw notFound('Transaction not found');
  const s = await getSetting('station');
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="${t.invoiceNo}.pdf"`);
  const doc = new PDFDocument({ size: 'A5', margin: 36 });
  doc.pipe(res);
  doc.fontSize(18).font('Helvetica-Bold').text(s.name, { align: 'center' });
  doc.fontSize(9).font('Helvetica').text(`${s.brand} Dealer • ${s.address}, ${s.city}, ${s.state} ${s.pincode}`, { align: 'center' });
  if (s.gstin) doc.text(`GSTIN: ${s.gstin}`, { align: 'center' });
  doc.text(`Phone: ${s.phone}`, { align: 'center' }).moveDown();
  doc.fontSize(12).font('Helvetica-Bold').text('FUEL RECEIPT', { align: 'center' }).moveDown(0.5);
  const row = (k, v) => doc.fontSize(10).font('Helvetica').text(k, { continued: true }).font('Helvetica-Bold').text(`  ${v}`, { align: 'right' });
  row('Invoice No', t.invoiceNo);
  row('Date', t.createdAt.toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' }));
  row('Customer', `${t.user.name} (${t.user.phone})`);
  row('Card', t.user.cardNumber);
  if (t.vehicle) row('Vehicle', t.vehicle.regNumber);
  doc.moveDown(0.5).moveTo(36, doc.y).lineTo(384, doc.y).stroke().moveDown(0.5);
  const unit = t.fuelType === 'CNG' ? 'kg' : t.fuelType === 'EV' ? 'kWh' : 'L';
  row('Product', FUEL_LABEL[t.fuelType]);
  row('Rate', `Rs. ${Number(t.pricePerUnit).toFixed(2)} / ${unit}`);
  row('Quantity', `${Number(t.quantity).toFixed(2)} ${unit}`);
  doc.moveDown(0.5).moveTo(36, doc.y).lineTo(384, doc.y).stroke().moveDown(0.5);
  doc.fontSize(14);
  row('Total', `Rs. ${Number(t.amount).toFixed(2)}`);
  row('Points earned', `+${t.pointsEarned}`);
  doc.moveDown(2).fontSize(8).font('Helvetica').fillColor('#666')
    .text('Petrol, diesel and CNG are outside GST; prices include applicable state VAT & excise.', { align: 'center' })
    .text('Thank you for fuelling with us!', { align: 'center' });
  doc.end();
}));

export default router;
