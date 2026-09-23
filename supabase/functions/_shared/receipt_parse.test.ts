// deno test supabase/functions/_shared/receipt_parse.test.ts
// The four shapes are the four real receipts that sat in front of the founder on 6 Sep 2026
// (inbound_messages 67, 73, 74, 75), reduced to the lines the parser reads. 23 Sep 2026: the vendor and the
// period are REASONED upstream (reasoned_books.ts) and passed in; this file pins that only the FIGURES are read here.
import { parseReceipt } from './receipt_parse.ts';

const eq = (a: unknown, b: unknown, msg: string) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(msg + ': got ' + JSON.stringify(a)); };

Deno.test('Stripe receipt (Resend): Amount paid, Paid date; the reasoned vendor and period are carried, not derived', () => {
  const body = `From: Resend <invoice+statements@invoicing.resend.com>\nSent: Sunday, 16 August 2026 02:02:09\n\nReceipt from Resend\n$20.00\nPaid August 15, 2026\n\nAug 15–Sep 15, 2026\nTransactional Pro\nTotal\n$20.00\nAmount paid\n$20.00\nCharged AED76.39 using 1 USD = 3.8196 AED`;
  const r = parseReceipt({ subject: 'Fw: Your receipt from Resend #2675-9504', body, vendor: 'Resend', period: 'monthly' })!;
  eq([r.vendor, r.amount, r.currency, r.date, r.period], ['Resend', 20, 'USD', '2026-08-15', 'monthly'], 'resend');
});

Deno.test('Orb invoice (Supabase): "$35.63 has been charged", Paid on', () => {
  const body = `From: Supabase Pte. Ltd. <invoice+statements@supabase.com>\nSent: Thursday, 27 August 2026 13:42:25\n\nYour invoice has been paid. $35.63 has been charged to your payment method.\nInvoice No. TLZLFZ-00006\nPaid on Aug 27, 2026`;
  const r = parseReceipt({ subject: 'Fw: Payment received for Supabase Pte. Ltd. invoice (#TLZLFZ-00006)', body, vendor: 'Supabase', period: 'monthly' })!;
  eq([r.vendor, r.amount, r.currency, r.date, r.period], ['Supabase', 35.63, 'USD', '2026-08-27', 'monthly'], 'supabase');
});

Deno.test('Apify: "payment of 29 USD" (currency after the figure), date from the Sent line', () => {
  const body = `From: billing@apify.com <billing@apify.com> on behalf of Apify Billing <billing@apify.com>\nSent: Thursday, 03 September 2026 05:05:34\n\nThis is an automatic notification that we received your payment of 29 USD.\nThe invoice is attached.`;
  const r = parseReceipt({ subject: 'Fw: Apify invoice #202609032256 payment successful', body, vendor: 'Apify', period: 'one_off' })!;
  eq([r.vendor, r.amount, r.currency, r.date, r.period], ['Apify', 29, 'USD', '2026-09-03', 'one_off'], 'apify');
  eq(parseReceipt({ subject: 'x', body, vendor: 'Apify', period: 'monthly' })!.recurring, true, 'a reasoned monthly period is recurring');
});

Deno.test('AED and annual', () => {
  const r = parseReceipt({ subject: 'Tax invoice', body: 'Total AED 1,250.00\n2026-06-08', vendor: 'Tasjeel', period: 'annual' })!;
  eq([r.vendor, r.amount, r.currency, r.date, r.period], ['Tasjeel', 1250, 'AED', '2026-06-08', 'annual'], 'aed');
});

Deno.test('no amount, or a bare number, is null — never a guessed booking', () => {
  eq(parseReceipt({ subject: 'Your invoice', body: 'Total 3 items. Thanks.', vendor: 'Apify', period: 'one_off' }), null, 'bare number');
  eq(parseReceipt({ subject: 'Fw: receipt', body: 'no money here', vendor: 'Apify', period: 'one_off' }), null, 'no amount');
  eq(parseReceipt({ subject: 'Fw: receipt', body: 'Total AED 10.00', vendor: '', period: 'one_off' }), null, 'no reasoned vendor, no booking');
});

// 9 SEP 2026 — THE UAE RECEIPT THAT WAS INVISIBLE.
// The founder forwarded a Google Play receipt on 13 Aug 2026. It states a real total and a real
// VAT figure, and the parser read NEITHER: the amount is wrapped in U+200F right-to-left marks
// (which are not \s, so `Total:\s*<figure>` never reached the digits) and the currency is written
// `د.إ.` rather than AED. Held as unreadable — and so would be every UAE-issued invoice printing
// the dirham the way UAE invoices print it. Nothing here supplies a figure the document does not
// state; it only stops the formatting hiding one.
Deno.test('UAE dirham symbol and bidi marks: the stated total and the stated VAT are both read', () => {
  const RLM = '‏';
  const body = `From: Google Play <googleplay-noreply@google.com>\n`
    + `Sent: Thursday, 13 August 2026 14:19:45\n\n`
    + `Your subscription from Dropbox, Inc. on Google Play has renewed.\n`
    + `Item    Price\nDropbox Simple  ${RLM}26.99 د.إ.${RLM}/month\n`
    + `Auto-renewing subscription\nTotal: ${RLM}26.99 د.إ.${RLM}/month\n`
    + `(Includes VAT of ${RLM}1.29 د.إ.${RLM})\n`;
  const r = parseReceipt({ subject: 'Fw: Your Google Play Order Receipt from 13 Aug 2026', body, vendor: 'Dropbox', period: 'monthly' })!;
  eq([r.vendor, r.amount, r.currency, r.date, r.period, r.vat], ['Dropbox', 26.99, 'AED', '2026-08-13', 'monthly', 1.29], 'google play AED');
});

Deno.test('the normaliser adds no currency of its own — a bare figure is still not money', () => {
  eq(parseReceipt({ subject: 'x', body: 'Total: ‏26.99‏/month', vendor: 'Apify', period: 'monthly' }), null, 'no currency mark, no booking');
});
