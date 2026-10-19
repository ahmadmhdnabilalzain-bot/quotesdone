// The exam answer of 19 Oct 2026 told a supplier our registered supplier count. A reply may never state a count of OUR
// suppliers, customers or leads, in any form; and the guard must not drop ordinary numbers (review of #1549).
// Run: deno test supabase/functions/_shared/support_reply_guard_internal_number.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { guardSupportReply, replyViolations } from './support_reply_guard.ts';

const LEAKS = [
  'We currently have 19,901 registered suppliers on the platform.',
  'Our network has 19901 suppliers across the UAE.',
  'There are more than 20,000+ entries in our supplier directory.',
  'We have 15k suppliers on the platform.',
  'We have 15K registered suppliers.',
  'Our directory holds 1.9 thousand customers.',
  'We have nineteen thousand registered suppliers.',
  'There are twenty thousand suppliers registered with us.',
  'We have thousands of suppliers on our platform.',
  'Our database has 2 million leads.',
  'لدينا ١٩٬٩٠١ مورد مسجل على المنصة.',
  'لدينا 19901 موردين مسجلين.',
  'لدينا 15 ألف مورد على منصتنا.',
];
const FINE = [
  'Your reference is QD-10234.',
  'Your case reference is QD-S-KYUUSA and we will reply within 24 hours.',
  'The quote is valid for 120 days.',
  'Up to 1,000 suppliers can quote on your request.',
  'We have been operating since 2026.',
  'Our customers in 2026 can post requests for free.',
  'Call us on +971 4 123 4567.',
  'Suppliers can reach us on +971 50 123 4567.',
  'The first 1,000 suppliers join free, permanently.',
  'From the 1,001st registration the fee is AED 1,000 a year.',
  'The reveal fee is AED 150 per supplier.',
  'We have 3 suppliers who quoted on your request.',
  'Your request went to 12 suppliers in that trade.',
  'Please send drawings of up to 25 MB.',
  'أول 1000 مورد يسجلون مجانًا بشكل دائم.',
];

Deno.test('a count of our suppliers, customers or leads is an internal_number violation, in every form', () => {
  for (const s of LEAKS) assert(replyViolations(s).includes('internal_number'), 'not caught: ' + s);
});

Deno.test('references, durations, capacities, years, phones, prices and published figures pass', () => {
  for (const s of FINE) assertEquals(replyViolations(s).filter((v) => v === 'internal_number'), [], 'over-blocked: ' + s);
});

Deno.test('the guard drops only the sentence with the count and keeps the rest', () => {
  const g = guardSupportReply('Thank you for your interest. We have 19,901 registered suppliers. Your reference is QD-10234 and the quote is valid for 120 days.', 'en');
  assert(!/19,901/.test(g.text), g.text);
  assert(/QD-10234/.test(g.text) && /120 days/.test(g.text), g.text);
});
