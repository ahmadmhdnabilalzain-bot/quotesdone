// HIS VAT ANSWER STANDS AT EVERY DOOR, AND THE FIGURES ARE READ THE ONE WAY (accountant, 15 Nov 2026; the independent review
// of branch accountant-a-total-stated-with-vat-is-never-read-as-without @ d2e2825d4, verdict FIX).
//
// d2e2825d4 asked the VAT question when a total is exactly the supplier's lines plus 5%, and let his answer stand on the hold
// desk (ruling 1207). The review found the other doors did not: in the chat review "before VAT" or a typed ex-VAT figure was
// asked again forever, and "including VAT" after "before VAT" kept the stale price; a re-submission after a desk answer was
// asked again; a discount hid the 5%; an inclusive total took total / 1.05 instead of the lines' own sum; and a fixed 0.05
// tolerance missed VAT rounded line by line on a dozen lines. Every case below fails on a6e2d3c84 (d2e2825d4 + the merge).
// Pure: no database, no network, no model.
// deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,RESEND_INBOUND_NO_SERVE --allow-read=. supabase/functions/supplier_api/his_vat_answer_stands_at_every_door.test.ts
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { feeBaseOf, statedPrice, storedPrice } from '../_shared/stated_price.ts';
import { readVat } from '../_shared/line_specs/vat.ts';
import { applyCorrections, readReply, reviewQuotation, type SafeInquiry, type Working } from './quote_review.ts';
import { carryHeldAnswers, heldAnswersOf, resolvedFrom, withResolved, workingFromSubmit } from './submit_review.ts';

const INQ: SafeInquiry = { id: 'inq-zz-vat', job_no: 'RFQ-ZZ9450', category: 'hvac', emirate: 'Dubai', spec: null, boq_rows: [], boq_withheld: false, concluded: false, revealed: false };
const NOW = new Date('2026-11-15T19:30:00Z');
// Two lines adding up to AED 9,000 and a total of AED 9,450 (9,000 x 1.05), basis not written in the file.
const LINES = [
  { description: 'Wall split unit 1.5 TR, inverter, supply and install', qty: '1', unit: 'nos', unit_price: 4000, amount: 4000 },
  { description: 'Wall split unit 2.0 TR, inverter, supply and install', qty: '1', unit: 'nos', unit_price: 5000, amount: 5000 },
];
const work = (over: Partial<Working> = {}): Working => ({
  lines: LINES.map((l) => ({ ...l })), amount: 9450, subtotal: null, vat_amount: null, vat_treatment: null, price_ex_vat: null, trn: null,
  lead_time: '14 days from LPO', validity: '30 days', payment_terms: '30% advance, 70% on completion', warranty: '2 years parts and labour',
  scope: 'Supply and install two split AC units', conditions: '', exclusions: 'Civil works.', notes: '',
  terms_spec: {}, masked_terms: [], option_totals: {}, foreign_currency: null, boq_excluded: {}, qty_explained: {}, corrections: [], ...over,
});
const codes = (w: Working) => reviewQuotation(INQ, w, NOW).issues.map((i) => i.code);
/** One chat message, as quote_review_flow/message.ts applies it: read against the open issues, then corrected. */
const say = (w: Working, text: string) => applyCorrections(w, readReply(text, reviewQuotation(INQ, w, NOW).issues).corrections);

// ── 1. The chat review takes his answer, exactly as the hold desk does ─────────────────────────────────────────────────
Deno.test('chat: the figures ask the VAT question first', () => {
  assert(codes(work()).includes('vat_basis'));
});

Deno.test('chat: "before VAT" is his answer; the VAT question is not asked again, and the lines must still add up', () => {
  const w = say(work(), 'The total is before VAT');
  assertEquals(w.vat_treatment, 'exclusive');
  const rv = reviewQuotation(INQ, w, NOW);
  assert(!rv.issues.some((i) => i.code === 'vat_basis'), JSON.stringify(rv.issues.map((i) => i.code)));
  assertEquals(rv.price_ex_vat, 9450);
  assert(rv.issues.some((i) => i.code === 'total_mismatch'), 'before VAT, his lines (9,000) do not add up to 9,450');
});

Deno.test('chat: an ex-VAT figure he types is his answer', () => {
  const w = say(work(), 'AED 9,450 before VAT');
  const rv = reviewQuotation(INQ, w, NOW);
  assert(!rv.issues.some((i) => i.code === 'vat_basis'), JSON.stringify(rv.issues.map((i) => i.code)));
  assertEquals(rv.price_ex_vat, 9450);
});

Deno.test('chat: "including VAT" after "before VAT" drops the stale 9,450 and reads 9,000', () => {
  const w = say(say(work(), 'The total is before VAT'), 'Sorry, the total is including VAT');
  assertEquals(w.vat_treatment, 'inclusive');
  const rv = reviewQuotation(INQ, w, NOW);
  assert(!rv.issues.some((i) => i.code === 'vat_basis' || i.code === 'total_mismatch'), JSON.stringify(rv.issues.map((i) => i.code)));
  assertEquals(rv.price_ex_vat, 9000);
});

Deno.test('chat -> submit_quote: the answer the chat recorded travels in quote_reviews.working, never in the request body', () => {
  // what the chat submits after "before VAT" (quote_review_flow/submit.ts submitPayload), re-reviewed by submit_quote
  const body = { amount: 9450, price_ex_vat: 9450, vat_treatment: 'exclusive', items: LINES, lead_time: '14 days from LPO', validity: '30 days', warranty: '2 years parts and labour', payment_terms: '30% advance' };
  const scrubbed = { notes: '', scope: 'Supply and install two split AC units', conditions: '', exclusions: '' };
  const chatWorking = say(work(), 'The total is before VAT');
  const answered = withResolved(workingFromSubmit(body, scrubbed, {}, [], null), resolvedFrom(chatWorking));
  assert(!codes(answered).includes('vat_basis'), 'the chat answer is read from the engineer-written working');
  // a caller who writes the answer into the body is not answering anything
  const forged = withResolved(workingFromSubmit({ ...body, vat_answered: 'exclusive' }, scrubbed, {}, [], null), resolvedFrom(null));
  assert(codes(forged).includes('vat_basis'));
  assertEquals((resolvedFrom({ vat_answered: 'anything' }) as Record<string, unknown>).vat_answered ?? null, null, 'only one of the three answers counts');
});

// ── 3. One number format in the question ─────────────────────────────────────────────────────────────────────────────
Deno.test('the VAT question writes both figures the same way', () => {
  const rv = reviewQuotation(INQ, work({ lines: [{ description: 'AC units supply and install', qty: '1', unit: 'lot', unit_price: 17957, amount: 17957 }], amount: 18854.85 }), NOW);
  assertStringIncludes(rv.issues.find((i) => i.code === 'vat_basis')!.en, 'Your line amounts add up to AED 17,957, and AED 18,854.85 is exactly that plus 5% VAT.');
});

// ── 4. A discount does not hide the 5% ─────────────────────────────────────────────────────────────────────────────
Deno.test('discount: lines 10,000, discount 1,000, total 9,450 marked "before VAT" is (10,000 - 1,000) x 1.05: asked, never stored as 9,450', () => {
  const sp = statedPrice({ amount: 9450, stated: 'exclusive', discount_amount: 1000, lines_sum: 10000, text: '' });
  assertEquals([sp.price_ex_vat, sp.basis_conflict], [null, true]);
  assertEquals(feeBaseOf(storedPrice(sp, 9450)), null);
  // answered "including 5% VAT": the fee base is 9,000
  const inc = statedPrice({ amount: 9450, stated: 'inclusive', discount_amount: 1000, lines_sum: 10000, text: '', answered: true });
  assertEquals([inc.treatment, inc.price_ex_vat], ['inclusive', 9000]);
  // the review asks it with the arithmetic, and raises no second "difference" question
  const rv = reviewQuotation(INQ, work({ lines: [{ description: 'AC units supply and install', qty: '1', unit: 'lot', unit_price: 10000, amount: 10000 }], vat_treatment: 'exclusive', price_ex_vat: 9450, discount_amount: 1000, discount_label: 'Discount' }), NOW);
  const q = rv.issues.find((i) => i.code === 'vat_basis');
  assert(q, JSON.stringify(rv.issues.map((i) => i.code)));
  assertStringIncludes(q!.en, 'less the discount of AED 1,000 come to AED 9,000, and AED 9,450 is exactly that plus 5% VAT.');
  assert(!rv.issues.some((i) => i.code === 'total_mismatch'));
});

// ── 5. Rounding: the lines' own sum, and a tolerance that grows with the lines ─────────────────────────────────────────
Deno.test('an inclusive total over lines that fit takes the lines\' sum to the fils, not total / 1.05', () => {
  assertEquals(readVat({ amount: 2100.04, stated: 'inclusive', lines_sum: 2000 }).price_ex_vat, 2000);
});

Deno.test('twelve lines with VAT rounded line by line (6 fils over) are still the lines plus 5%', () => {
  // 12 lines of 1,000.10: VAT 50.005 per line, rounded to 50.01, so the total is 12,601.32 where 12,001.20 x 1.05 = 12,601.26
  const sum = 12001.2, total = 12601.32;
  assertEquals(readVat({ amount: total, stated: 'inclusive', lines_sum: sum, lines_count: 12 } as never).price_ex_vat, sum);
  // and the same total typed as "before VAT" is asked, never stored as the price
  const sp = statedPrice({ amount: total, stated: 'exclusive', price_ex_vat: total, lines_sum: sum, lines_count: 12, text: '' } as never);
  assertEquals([sp.price_ex_vat, sp.basis_conflict], [null, true]);
});

// ── 6. A re-submission after a desk answer carries it ───────────────────────────────────────────────────────────────
Deno.test('re-submission: the desk answer on the earlier row is carried, and stands while he states that same basis', () => {
  const owner = { inquiry_id: INQ.id, supplier_id: 7 };
  const row = { id: 'q1', inquiry_id: INQ.id, supplier_id: 7, option_no: 1, validity: '30 days', terms_spec: {} };
  const holds = [{ quote_id: 'q1', supplier_values: [{ at: '2026-11-15T15:00:00Z', by: 'supplier', values: {}, answers: { vat: 'exclusive', total: '5% site overhead' } }] }];
  const held = heldAnswersOf(owner, row, [], holds)!;
  assertEquals((held as Record<string, unknown>).vat, 'exclusive');
  const body = { amount: 9450, price_ex_vat: 9450, vat_treatment: 'exclusive', items: LINES, validity: '30 days' };
  const carry = carryHeldAnswers(body, [held], [1, 1], [1]) as ReturnType<typeof carryHeldAnswers> & { vat_answered?: string | null };
  assertEquals(carry.vat_answered, 'exclusive');
  // what submit_quote stores with it (actions/quotes.ts: answered = answerStands(carried answer, stated basis))
  const sp = statedPrice({ amount: 9450, stated: 'exclusive', price_ex_vat: 9450, lines_sum: 9000, text: '', answered: carry.vat_answered === 'exclusive' });
  assertEquals([sp.treatment, sp.price_ex_vat], ['exclusive', 9450]);
  // and the review submit_quote runs reads it too
  const scrubbed = { notes: '', scope: 'Supply and install two split AC units', conditions: '', exclusions: '' };
  const w = withResolved(workingFromSubmit({ ...body, lead_time: '14 days from LPO', warranty: '2 years parts and labour', payment_terms: '30% advance' }, scrubbed, {}, [], null), { ...resolvedFrom(null), vat_answered: carry.vat_answered } as never);
  assert(!codes(w).includes('vat_basis'));
});
