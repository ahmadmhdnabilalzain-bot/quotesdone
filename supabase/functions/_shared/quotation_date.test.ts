// The date printed on a quotation becomes quotes.quotation_date only when it is read for certain (ledger 1697).
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/_shared/quotation_date.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { dubaiDay, quotationDateOf } from './quotation_date.ts';

const NOW = new Date('2026-11-15T06:00:00Z');   // 10:00 in Dubai

Deno.test('the date as a quotation prints it, day first, English or Arabic, becomes a calendar day', () => {
  const cases: [string, string | null][] = [
    ['12/11/2026', '2026-11-12'], ['12-11-2026', '2026-11-12'], ['12.11.2026', '2026-11-12'], ['2026-11-12', '2026-11-12'],
    ['12 Nov 2026', '2026-11-12'], ['12th November 2026', '2026-11-12'], ['November 12, 2026', '2026-11-12'],
    ['Date: 01/11/2026', '2026-11-01'], ['١٢/١١/٢٠٢٦', '2026-11-12'], ['12 نوفمبر 2026', '2026-11-12'], ['3 أكتوبر 2026', '2026-10-03'],
    ['16/11/2026', '2026-11-16'],            // tomorrow in Dubai: a time-zone edge, kept
  ];
  for (const [raw, want] of cases) assertEquals(quotationDateOf(raw, NOW), want, raw);
});

Deno.test('a date it cannot read for certain, or one in the future, is no date at all (never a guess)', () => {
  for (const raw of ['', '   ', null, undefined, 'TBA', 'as per our letter', '31/02/2026', '12/15/2026', '12/11/26', '17/11/2026', '1 Jan 2027', 'Ref QD-2026-118']) {
    assertEquals(quotationDateOf(raw, NOW), null, String(raw));
  }
});

Deno.test('the Dubai day is the UTC day four hours on', () => {
  assertEquals(dubaiDay(new Date('2026-11-15T19:59:00Z')), '2026-11-15');
  assertEquals(dubaiDay(new Date('2026-11-15T20:00:00Z')), '2026-11-16');
});
