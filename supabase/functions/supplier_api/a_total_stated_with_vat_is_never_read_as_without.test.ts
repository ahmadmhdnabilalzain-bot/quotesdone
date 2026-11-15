// A TOTAL STATED WITH VAT IS NEVER READ AS WITHOUT (accountant, 15 Nov 2026).
//
// Measured on the live site, journey A, run 8288bec3: supplier "Polar Tech Contracting" (a ZZ DEMO fixture) sent a quotation
// with a TRN, six lines adding up to AED 17,957.00 and one total, "Total price (inclusive of VAT) AED 18,854.85"
// (17,957.00 x 1.05). Its reading failed (HTTP 503), the form said "before VAT" with 18,854.85, the release review asked only
// why the lines did not add up, a free-text answer cleared that, and it was stored: excluding VAT 18,854.85, VAT none,
// treatment exclusive. The comparison ranked it 5% too high and the fee would have been 3% of 18,854.85 (AED 565.65) instead
// of 3% of 17,957.00 (AED 538.71). Every case below is that quotation; each fails on origin/main 06881a2d6 unless marked
// "control". Pure: no database, no network, no model.
// deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,RESEND_INBOUND_NO_SERVE --allow-read=. supabase/functions/supplier_api/a_total_stated_with_vat_is_never_read_as_without.test.ts
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { feeBaseOf, statedPrice, storedPrice, vatStated } from '../_shared/stated_price.ts';
import { readVat } from '../_shared/line_specs/vat.ts';
import { revealCharge } from '../_shared/reveal_fee.ts';
import { proposalFromModel } from '../quote_extract/model_reading.ts';
import { reviewQuotation, type SafeInquiry, type Working } from './quote_review.ts';
import { withDeskAnswers } from './submit_review.ts';

// Polar Tech Contracting's six lines, exactly as his file states them (journey A dossier, exhibit 7).
const POLAR_LINES = [
  { description: 'Removal and disposal of existing wall split units', qty: '4', unit: 'nos', unit_price: 171, amount: 684 },
  { description: 'Wall split unit 1.5 TR, inverter, supply and install', qty: '2', unit: 'nos', unit_price: 3021, amount: 6042 },
  { description: 'Wall split unit 2.0 TR, inverter, supply and install', qty: '2', unit: 'nos', unit_price: 3534, amount: 7068 },
  { description: 'Insulated copper piping where the existing cannot be reused', qty: '20', unit: 'm', unit_price: 97, amount: 1940 },
  { description: 'Service of ducted unit 3 TR: coils, filters, drain, gas check', qty: '3', unit: 'nos', unit_price: 513, amount: 1539 },
  { description: 'Testing and commissioning', qty: '1', unit: 'lot', unit_price: 684, amount: 684 },
];
const LINES_SUM = 17957;          // 684 + 6042 + 7068 + 1940 + 1539 + 684
const TOTAL = 18854.85;           // 17,957.00 x 1.05, "Total price (inclusive of VAT)"
const HIS_WORDS = 'Total price (inclusive of VAT) AED 18,854.85\nPrices: In AED, inclusive of VAT\nTRN 100000000020203';

Deno.test('the run-8288bec3 submission ("before VAT", ex-VAT typed as the total) is not settled: no fee base, held for the VAT question', () => {
  // What submit_quote computed from that request: amount and price_ex_vat 18,854.85, stated exclusive, the six lines.
  const sp = statedPrice({ amount: TOTAL, stated: 'exclusive', price_ex_vat: TOTAL, text: '', lines_sum: LINES_SUM });
  const row = storedPrice(sp, TOTAL);
  assertEquals([row.price_ex_vat, row.quote_amount, row.amount_as_stated, row.vat_treatment], [null, null, TOTAL, 'not_stated']);
  assertEquals(sp.basis_conflict, true);
  assertEquals(feeBaseOf(row), null, 'no page shows a fee, no comparison ranks it, until he answers');
});

Deno.test('the QuoteForm payload ("before VAT", no typed ex-VAT figure) is the same question', () => {
  const row = storedPrice(statedPrice({ amount: TOTAL, stated: 'exclusive', text: '', lines_sum: LINES_SUM }), TOTAL);
  assertEquals([row.price_ex_vat, row.quote_amount, row.vat_treatment], [null, null, 'not_stated']);
});

Deno.test('his own words with his TRN: "inclusive of VAT", no rate, no lines -> 18,854.85 / 1.05 = 17,957.00', () => {
  const v = readVat({ amount: TOTAL, text: HIS_WORDS });
  assertEquals([v.treatment, v.price_ex_vat, v.vat_rate, v.trn], ['inclusive', LINES_SUM, 5, '100000000020203']);
  // the TRN sent beside the text (a reading, the form) counts the same
  assertEquals(readVat({ amount: TOTAL, text: 'Prices inclusive of VAT', trn: '100000000020203' }).price_ex_vat, LINES_SUM);
});

Deno.test('"inclusive of VAT" over lines that add up to the total less exactly 5% -> 17,957.00, with no TRN needed', () => {
  const sp = statedPrice({ amount: TOTAL, stated: 'inclusive', text: '', lines_sum: LINES_SUM });
  const row = storedPrice(sp, TOTAL);
  assertEquals([row.vat_treatment, row.price_ex_vat, row.quote_amount, row.amount_as_stated], ['inclusive', LINES_SUM, LINES_SUM, TOTAL]);
  // the fee is 3% of the price before VAT: AED 538.71, not AED 565.65
  assertEquals(revealCharge(feeBaseOf(row)!, 0.03).base_fee, 538.71);
  assertStringIncludes(vatStated(row, 'en'), 'includes VAT');
});

Deno.test('control: "inclusive of VAT" with no TRN, no rate, no VAT amount and no lines that fit is never guessed', () => {
  const row = storedPrice(statedPrice({ amount: TOTAL, text: 'Total price (inclusive of VAT)' }), TOTAL);
  assertEquals([row.vat_treatment, row.price_ex_vat, row.quote_amount], ['inclusive', null, null]);
  // lines that do not add up to total / 1.05 are no evidence of the rate
  assertEquals(readVat({ amount: TOTAL, stated: 'inclusive', lines_sum: 17000 }).price_ex_vat, null);
});

Deno.test('a subtotal and a total 5% above it, "prices exclude VAT": the subtotal is the price, never the total', () => {
  const v = readVat({ amount: TOTAL, subtotal: LINES_SUM, stated: 'exclusive' });
  assertEquals([v.treatment, v.price_ex_vat], ['exclusive', LINES_SUM]);
});

Deno.test('control: a total that really is before VAT (the lines add up to it) stays exactly as stated', () => {
  const row = storedPrice(statedPrice({ amount: LINES_SUM, stated: 'exclusive', text: '', lines_sum: LINES_SUM }), LINES_SUM);
  assertEquals([row.vat_treatment, row.price_ex_vat, row.quote_amount], ['exclusive', LINES_SUM, LINES_SUM]);
});

Deno.test('the model reading of his file: inclusive total over his lines -> price before VAT 17,957.00, total 18,854.85 kept as stated', () => {
  const ai = { is_quotation: true, currency: 'AED', total: TOTAL, subtotal: null, vat_amount: null, vat_treatment: 'inclusive',
    line_items: POLAR_LINES.map((l) => ({ ...l, quantity: Number(l.qty) })), lead_time: '14 days from LPO', validity: '30 days' };
  const p = proposalFromModel(ai as never, (v) => String(v ?? ''));
  assertEquals([p.vat_treatment, p.price_ex_vat, p.amount, (p as { total?: number }).total], ['inclusive', LINES_SUM, LINES_SUM, TOTAL]);
});

// ── The release review (supplier_api quote_review/review.ts), the check every door runs ───────────────────────────────
const INQ: SafeInquiry = { id: 'inq-zz-polar', job_no: 'RFQ-ZZ8288', category: 'hvac', emirate: 'Dubai', spec: null, boq_rows: [], boq_withheld: false, concluded: false, revealed: false };
const polar = (over: Partial<Working> = {}): Working => ({
  lines: POLAR_LINES.map((l) => ({ ...l })), amount: TOTAL, subtotal: null, vat_amount: null, vat_treatment: 'exclusive', price_ex_vat: TOTAL, trn: null,
  lead_time: '14 days from LPO', validity: '30 days', payment_terms: '30% advance, 70% on completion', warranty: '5 years on compressors, 2 years on the installation',
  scope: 'Replace four split AC units and service three ducted units', conditions: '', exclusions: 'Civil works.', notes: '',
  terms_spec: {}, masked_terms: [], option_totals: {}, foreign_currency: null, boq_excluded: {}, qty_explained: {}, corrections: [], ...over,
});
const NOW = new Date('2026-11-15T14:19:00Z');

Deno.test('the review asks the VAT question with the arithmetic, and no free-text "explanation" of the 5% can release it', () => {
  const rv = reviewQuotation(INQ, polar(), NOW);
  const vat = rv.issues.find((i) => i.code === 'vat_basis');
  assert(vat, 'the VAT basis is asked: ' + JSON.stringify(rv.issues.map((i) => i.code)));
  assertStringIncludes(vat!.en, 'Your line amounts add up to AED 17957, and AED 18,854.85 is exactly that plus 5% VAT.');
  assert(!rv.issues.some((i) => i.code === 'total_mismatch'), 'the 5% gap is the VAT question, not a difference to explain');
  assertEquals(rv.price_ex_vat, null);
  // what released it in run 8288bec3: "As per the quotation" against the total. It no longer answers anything.
  const after = reviewQuotation(INQ, polar({ qty_explained: { total: 'As per the quotation' } }), NOW);
  assert(after.issues.some((i) => i.code === 'vat_basis'));
});

Deno.test('control: once he answers the VAT question on the hold desk his answer stands (ruling 1207), and the lines must still add up', () => {
  const rv = reviewQuotation(INQ, withDeskAnswers(polar(), { vat: 'exclusive' }), NOW);
  assert(!rv.issues.some((i) => i.code === 'vat_basis'), JSON.stringify(rv.issues.map((i) => i.code)));
  assert(rv.issues.some((i) => i.code === 'total_mismatch'), 'before VAT, his lines (17,957) do not add up to 18,854.85');
});
