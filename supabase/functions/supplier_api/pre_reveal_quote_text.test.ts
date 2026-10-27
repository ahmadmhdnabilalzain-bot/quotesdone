// Every supplier-typed quote field a customer reads before the reveal is scrubbed (13 Oct 2026, sales_engineer).
// Replays the leak: identity in payment_terms / a line's notes reached my_inquiries and quote_compare verbatim.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { scrubIdentity, scrubLine } from './identity_scrub.ts';

const NAME = 'Al Noor Trading LLC';
const LEAKS = ['050 123 4567', 'sales@alnoor.ae', 'www.alnoor.ae', 'Al Noor'];

Deno.test('a quote line loses the supplier\'s name and contacts in every text column, numbers untouched', () => {
  const hits: string[] = [];
  const out = scrubLine({ description: 'Split AC 2 ton by Al Noor', brand: 'Daikin', model: 'FTKM50', specification: 'call 050 123 4567',
    notes: 'sales@alnoor.ae', country_of_origin: 'see www.alnoor.ae', qty: 4, unit_price: 2500, spec: { remark: 'Al Noor Trading LLC install team' } }, NAME, hits);
  const text = JSON.stringify(out);
  for (const l of LEAKS) assert(!text.includes(l), 'leaked: ' + l);
  assertEquals(out.brand, 'Daikin'); assertEquals(out.model, 'FTKM50'); assertEquals(out.qty, 4); assertEquals(out.unit_price, 2500);
  assert(hits.length >= 4);
});

Deno.test('the short terms (payment, warranty, validity, lead time) are scrubbed the same way', () => {
  for (const t of ['50% advance to Al Noor Trading LLC, call 050 123 4567', 'warranty claims: sales@alnoor.ae', 'TRN 100123456700003, 30 days']) {
    const s = scrubIdentity(t, NAME, []) || '';
    for (const l of [...LEAKS, '100123456700003']) assert(!s.includes(l), t + ' -> ' + s);
  }
});

Deno.test('submit_quote routes the terms and every line through the scrub (fails if a column goes back to clip alone)', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  for (const f of ['lead_time', 'validity', 'payment_terms', 'warranty']) assert(src.includes(f + ': scrub(body.' + f), f + ' is not scrubbed');
  assert(src.includes('const it = scrubLine(raw, sup.company_name, maskHits)'), 'quote lines are not scrubbed');
  assert(src.includes('scrubDeep(body.values, sup.company_name'), 'spec_fill values are not scrubbed');
});
