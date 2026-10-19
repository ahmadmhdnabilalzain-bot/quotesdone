// The exam answer of 19 Oct 2026 told a supplier our registered supplier count. No reply on any channel may state a
// count of our suppliers, customers or records; the published programme figures (first 1,000 free, fee from the
// 1,001st) still pass. Run: deno test supabase/functions/_shared/support_reply_guard_internal_number.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { guardSupportReply, replyViolations } from './support_reply_guard.ts';

const LEAKS = [
  'We currently have 19,901 registered suppliers on the platform.',
  'Our network has 19901 suppliers across the UAE.',
  'There are more than 20,000+ entries in our supplier directory.',
  'Registered suppliers: 16,242 in the sendable pool.',
  'We serve 350 customers today.',
  'لدينا ١٩٬٩٠١ مورد مسجل على المنصة.',
  'لدينا 19901 موردين مسجلين.',
];
const FINE = [
  'The first 1,000 suppliers join free, permanently.',
  'From the 1,001st registration the fee is AED 1,000 a year.',
  'The reveal fee is AED 150 per supplier.',
  'Your inquiry reference is QD-12345 and the quote is valid for 30 days.',
  'أول 1000 مورد يسجلون مجانًا بشكل دائم.',
];

Deno.test('a count of our suppliers or customers is an internal_number violation', () => {
  for (const s of LEAKS) assert(replyViolations(s).includes('internal_number'), s);
});

Deno.test('the published programme figures and ordinary numbers pass', () => {
  for (const s of FINE) assertEquals(replyViolations(s).filter((v) => v === 'internal_number'), [], s);
});

Deno.test('the guard drops the sentence and keeps the rest', () => {
  const g = guardSupportReply('Thank you for your interest in joining. We have 19,901 registered suppliers. You can register on the supplier portal.', 'en');
  assert(!/19,901/.test(g.text), g.text);
  assert(/supplier portal/.test(g.text), g.text);
});
