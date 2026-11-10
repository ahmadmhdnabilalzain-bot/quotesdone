// document_dates_are_dubai_dates.test.ts — a date we print is the date in Dubai, not in UTC (10 Nov 2026,
// it_engineer, founder ledger 1605; docs/reports/2026-11-10-reliability-checklist-audit.md, item "time zones").
// deno test --no-lock supabase/functions/_shared/document_dates_are_dubai_dates.test.ts
//
// Edge functions run with TZ=UTC. Between 20:00 and 24:00 UTC it is already the next day in Dubai (UTC+4, no daylight
// saving), and a document dated with the runtime's own zone printed yesterday. Measured 10 Nov 2026 in pdf_native,
// quote_documents/kit.ts, quote_documents/inquiry_document.ts, customer_api reviews and fmtDate in
// supplier_charge_documents.ts. The same rule for every other date formatter is the repository check
// scripts/checks/every_date_we_print_is_dubai_time.test.mjs.
import { assertEquals } from 'jsr:@std/assert@1';
import { dubaiDay, fmtDate } from './supplier_charge_documents.ts';

Deno.test('a timestamp late in the UTC evening is the next day in Dubai', () => {
  assertEquals(dubaiDay('2026-09-14T22:30:00Z'), '2026-09-15');
  assertEquals(fmtDate('2026-09-14T22:30:00Z', 'en'), '15 September 2026');
  assertEquals(fmtDate('2026-09-14T22:30:00+00:00', 'ar'), '15 سبتمبر 2026');
});

Deno.test('a timestamp in the Dubai morning keeps its day, and the boundary is 20:00 UTC', () => {
  assertEquals(dubaiDay('2026-09-15T09:12:44Z'), '2026-09-15');
  assertEquals(dubaiDay('2026-09-14T19:59:59Z'), '2026-09-14');
  assertEquals(dubaiDay('2026-09-14T20:00:00Z'), '2026-09-15');
});

Deno.test('a plain date (a due date) is printed as written, never shifted', () => {
  assertEquals(dubaiDay('2026-10-31'), '2026-10-31');
  assertEquals(fmtDate('2026-10-31', 'en'), '31 October 2026');
});

Deno.test('the Intl formatters the documents use print the Dubai day when given the zone', () => {
  const late = new Date('2026-11-10T21:00:00Z');
  assertEquals(late.toLocaleDateString('en-GB', { timeZone: 'Asia/Dubai', day: 'numeric', month: 'long', year: 'numeric' }), '11 November 2026');
  assertEquals(late.toLocaleDateString('en-GB', { timeZone: 'UTC', day: 'numeric', month: 'long', year: 'numeric' }), '10 November 2026');
});
