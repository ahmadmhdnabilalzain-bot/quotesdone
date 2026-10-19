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
  // bare counts, no 'we have' (second review of #1549)
  '19,901 suppliers.',
  '19 900 suppliers.',
  '19 901 suppliers.',
  'We work with 19 901 suppliers across the UAE.',
  '19901 suppliers are listed.',
  '15k suppliers.',
  '1.9 thousand customers use it.',
  'nineteen thousand suppliers.',
  'Twenty thousand companies trust it.',
  'QuotesDone has 19,901 suppliers.',
  'QuotesDone works with 2 million leads.',
  'Thousands of suppliers compete for your job.',
  'Over 16,242 companies in the pool.',
  '١٩٬٩٠١ مورد.',
  '15 ألف مورد.',
  'Our network has 450 suppliers.',
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
  'The quote is valid 120 days.',
  'Valid for 120 days from issue; 3 suppliers quoted.',
  'Call 800 1234 to reach our supplier desk.',
  'Call 04 123 4567 or 800-1234 and our customers team will help.',
  'Your request went to 120 suppliers in that trade.',
  'Attach files up to 2,000 KB for suppliers.',
  'The 1,001st supplier pays AED 1,000 a year.',
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
