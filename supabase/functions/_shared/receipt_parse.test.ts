// deno test supabase/functions/_shared/receipt_parse.test.ts
// The four shapes are the four real receipts that sat in front of the founder on 6 Sep 2026
// (inbound_messages 67, 73, 74, 75), reduced to the lines the parser reads.
import { parseReceipt } from './receipt_parse.ts';

const FROM = 'founder@example.invalid';
const eq = (a: unknown, b: unknown, msg: string) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(msg + ': got ' + JSON.stringify(a)); };

Deno.test('Stripe receipt (Resend): vendor from the forwarded From line, Amount paid, Paid date, month range', () => {
  const body = `From: Resend <invoice+statements@invoicing.resend.com>\nSent: Sunday, 16 August 2026 02:02:09\n\nReceipt from Resend\n$20.00\nPaid August 15, 2026\n\nAug 15–Sep 15, 2026\nTransactional Pro\nTotal\n$20.00\nAmount paid\n$20.00\nCharged AED76.39 using 1 USD = 3.8196 AED`;
  const r = parseReceipt({ from: FROM, subject: 'Fw: Your receipt from Resend #2675-9504', body })!;
  eq([r.vendor, r.amount, r.currency, r.date, r.period], ['Resend', 20, 'USD', '2026-08-15', 'monthly'], 'resend');
});

Deno.test('Orb invoice (Supabase): "$35.63 has been charged", Paid on, cadence from the subscription register', () => {
  const body = `From: Supabase Pte. Ltd. <invoice+statements@supabase.com>\nSent: Thursday, 27 August 2026 13:42:25\n\nYour invoice has been paid. $35.63 has been charged to your payment method.\nInvoice No. TLZLFZ-00006\nPaid on Aug 27, 2026`;
  const r = parseReceipt({ from: FROM, subject: 'Fw: Payment received for Supabase Pte. Ltd. invoice (#TLZLFZ-00006)', body, knownCadence: 'monthly' })!;
  eq([r.vendor, r.amount, r.currency, r.date, r.period], ['Supabase', 35.63, 'USD', '2026-08-27', 'monthly'], 'supabase');
});

Deno.test('Apify: "payment of 29 USD" (currency after the figure), date from the Sent line, "on behalf of" sender', () => {
  const body = `From: billing@apify.com <billing@apify.com> on behalf of Apify Billing <billing@apify.com>\nSent: Thursday, 03 September 2026 05:05:34\n\nThis is an automatic notification that we received your payment of 29 USD.\nThe invoice is attached.`;
  const r = parseReceipt({ from: FROM, subject: 'Fw: Apify invoice #202609032256 payment successful', body })!;
  eq([r.vendor, r.amount, r.currency, r.date, r.period], ['Apify', 29, 'USD', '2026-09-03', 'one_off'], 'apify');
  eq(parseReceipt({ from: FROM, subject: 'x', body, knownCadence: 'monthly' })!.period, 'monthly', 'apify cadence from register');
});

Deno.test('AED and annual', () => {
  const r = parseReceipt({ from: 'billing@tasjeel.ae', subject: 'Tax invoice - annual renewal', body: 'Total AED 1,250.00\n2026-06-08' })!;
  eq([r.vendor, r.amount, r.currency, r.date, r.period], ['Tasjeel', 1250, 'AED', '2026-06-08', 'annual'], 'aed');
});

Deno.test('no amount, or a bare number, is null — never a guessed booking', () => {
  eq(parseReceipt({ from: 'billing@apify.com', subject: 'Your invoice', body: 'Total 3 items. Thanks.' }), null, 'bare number');
  eq(parseReceipt({ from: FROM, subject: 'Fw: receipt', body: 'From: someone@gmail.com\nno money here' }), null, 'no vendor no amount');
});
