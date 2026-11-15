// ONE PRICE FOR THE RANKING AND THE FEE (accountant, 15 Nov 2026; journey A, run 8288bec3).
//
// The comparison ranked and showed `price_ex_vat ?? quote_amount`; the fee is charged on quotes.quote_amount (customer_api
// actions/reveal.ts and stripe_checkout call revealCharge(Number(q.quote_amount))); the customer's quotation page shows
// feeBaseOf. Three readings of two columns. Now the comparison reads comparedPrice = feeBaseOf, so for every quote that can
// be revealed the figure it is ranked on IS the figure the card is charged on, and a quote whose VAT basis is not settled
// has no price in the comparison at all. Pure: no database, no network.
// deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,RESEND_INBOUND_NO_SERVE --allow-read=. supabase/functions/quote_compare/one_price_for_rank_and_fee.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { comparedPrice, deterministicCompare, rosterOf } from './deterministic.ts';
import { feeBaseOf, statedPrice, storedPrice, type PriceRow } from '../_shared/stated_price.ts';
import { revealCharge } from '../_shared/reveal_fee.ts';

const RATE = 0.03;
/** What the card is charged on: the column customer_api reveal.ts and stripe_checkout read. */
const chargedOn = (row: PriceRow) => revealCharge(Number(row.quote_amount), RATE).base_fee;

// Rows as submit_quote stores them (storedPrice), one per way a supplier states a price.
const ROWS: Record<string, PriceRow> = {
  'before VAT, VAT added on top': storedPrice(statedPrice({ amount: 9450, subtotal: 9000, vat_amount: 450 }), 9450),
  'inclusive, VAT amount written': storedPrice(statedPrice({ amount: 9450, vat_amount: 450, text: 'Total including VAT' }), 9450),
  'Polar Tech: inclusive, his lines fit': storedPrice(statedPrice({ amount: 18854.85, stated: 'inclusive', lines_sum: 17957 }), 18854.85),
  'discount, then VAT': storedPrice(statedPrice({ amount: 1785, subtotal: 2000, discount_amount: 300, vat_amount: 85 }), 1785),
  'not VAT-registered': storedPrice(statedPrice({ amount: 1700, text: 'We are not VAT registered.' }), 1700),
};
// Rows whose VAT basis is not settled: the run-8288bec3 submission, and a legacy row from before 13 Nov that still carries
// its gross total in quote_amount with no ex-VAT figure.
const UNSETTLED: Record<string, PriceRow> = {
  'Polar Tech as submitted in run 8288bec3': storedPrice(statedPrice({ amount: 18854.85, stated: 'exclusive', price_ex_vat: 18854.85, lines_sum: 17957 }), 18854.85),
  'legacy inclusive row, gross in quote_amount': { quote_amount: 2100, price_ex_vat: null, vat_treatment: 'inclusive', amount_as_stated: 2100 },
};

Deno.test('every revealable quote is ranked on exactly the figure its fee is charged on', () => {
  for (const [name, row] of Object.entries(ROWS)) {
    const p = comparedPrice(row);
    assert(p != null && p > 0, name);
    assertEquals(p, feeBaseOf(row), name);
    assertEquals(p, Number(row.quote_amount), `${name}: the comparison and revealCharge read one figure`);
    assertEquals(revealCharge(p!, RATE).base_fee, chargedOn(row), name);
  }
  assertEquals(comparedPrice(ROWS['Polar Tech: inclusive, his lines fit']), 17957);
});

Deno.test('a quote whose VAT basis is not settled has no price in the comparison and never outranks a priced one', () => {
  for (const [name, row] of Object.entries(UNSETTLED)) assertEquals(comparedPrice(row), null, name);
  const labelled = [
    { label: 'Supplier A', quote_id: 'a', price: comparedPrice(ROWS['before VAT, VAT added on top']), itemised: true, lead_time: '14 days', warranty: '2 years' },
    { label: 'Supplier C', quote_id: 'c', price: comparedPrice(UNSETTLED['Polar Tech as submitted in run 8288bec3']), itemised: true, lead_time: '14 days', warranty: '5 years' },
  ];
  const top3 = deterministicCompare(labelled).top3 as { label: string; rank?: number }[];
  assertEquals(top3[0].label, 'Supplier A', 'a quote with no settled price never ranks first');
  const roster = rosterOf(labelled, top3);
  assertEquals(roster.find((r) => r.label === 'Supplier C')!.price, null);
  assertEquals(roster.find((r) => r.label === 'Supplier A')!.price, 9000);
});

Deno.test('quote_compare builds its roster and its technical comparison from comparedPrice, nowhere from a second column', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  // code only: a comment naming the old expression is not a use of it
  const code = src.split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n');
  assert(!/price_ex_vat\s*\?\?\s*q\.quote_amount/.test(code), 'quote_compare reads price_ex_vat ?? quote_amount again');
  assert(/\bprice:\s*comparedPrice\(q\)/.test(code), 'the roster price is not comparedPrice(q)');
  assert(/\bprice_ex_vat:\s*comparedPrice\(q\)/.test(code), 'the technical comparison price is not comparedPrice(q)');
});
