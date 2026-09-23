// THE REVIEW AS EACH DOOR MEETS IT — behavioural, not a grep (review of #854, finding SP-F-02).
//
// The first version of this fix was proved only by assertions on the source of index.ts, and that is
// how it shipped a hard 400 that would have taken both quoting doors offline: nothing ran a real
// payload through the real rules. These tests do. The payloads below are the ones the two portal doors
// actually build — SupplierPortal.tsx QuoteForm `buildPayload()` and SupplierQuoteBuilder.tsx
// `accept()` — and the assertions are about the VERDICT, so a change to the rules that closes a door
// fails here rather than in production.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { boqKey, reviewQuotation, type SafeInquiry } from './quote_review.ts';
import { resolvedFrom, withResolved, workingFromStoredQuote, workingFromSubmit } from './submit_review.ts';

const NO_SCRUB = { notes: '', scope: '', conditions: '', exclusions: '' };
const scrubbedOf = (b: Record<string, unknown>) => ({ notes: String(b.notes ?? ''), scope: String(b.scope ?? ''), conditions: String(b.conditions ?? ''), exclusions: String(b.exclusions ?? '') });

/** A job with a two-line BOQ, as supplier_api `inbox` serves it. */
const job = (over: Partial<SafeInquiry> = {}): SafeInquiry => ({
  id: 'd958e1ea-54f4-45a1-9214-d622ac52dce1', job_no: 'RFQ-151767', category: 'gypsum', emirate: 'Dubai',
  spec: null, boq_withheld: false, concluded: false, revealed: false,
  boq_rows: [
    { description: 'Gypsum partition wall 100mm', qty: 120, unit: 'm2' },
    { description: 'Suspended ceiling tiles', qty: 80, unit: 'm2' },
  ],
  ...over,
});

/** The BOQ match as the reasoning returns it for these fixtures: each item is the BOQ line of the same number (supplier_api's
 *  withReasonedMatch reasons it at the door; here it is the reasoned answer, given). */
const REASONED = (lines: unknown[]) => Object.fromEntries(lines.map((_, i) => [String(i + 1), i + 1]));
const review = (inq: SafeInquiry, body: Record<string, unknown>, resolved: unknown = null) => {
  const w = withResolved(workingFromSubmit(body, scrubbedOf(body), {}, [], null), resolvedFrom(resolved));
  return reviewQuotation(inq, { ...w, boq_match: REASONED(w.lines) });
};
const codes = (r: { issues: { code: string }[] }) => [...new Set(r.issues.map((i) => i.code))].sort();

// ── Door 1: the Quote Builder's one-click accept ────────────────────────────────────────────────
Deno.test('Quote Builder: an accept with no lines, no validity and no VAT basis is NOT approved', () => {
  // SupplierQuoteBuilder.tsx accept(): amount, lead_time, payment_terms, warranty, notes, source form.
  const r = review(job(), { action: 'submit_quote', amount: 61000, lead_time: '6 weeks', payment_terms: '50% advance', warranty: '1 year', notes: 'Prepared with the QuotesDone Quote Builder from 3 comparable bid(s).', source: 'form' });
  assertEquals(r.approved, false);
  // It is short of the rules it is short of; these three are the ones the builder can never satisfy
  // on its own, which is exactly why submit_quote HOLDS rather than refuses.
  for (const c of ['boq_line_not_priced', 'validity', 'vat_basis']) assert(codes(r).includes(c), `expected ${c} in ${codes(r).join(',')}`);
});

// ── Door 2: the portal quote form ───────────────────────────────────────────────────────────────
/** What QuoteForm sends when every field on the screen is filled and both BOQ lines are priced. */
const filledForm = () => ({
  action: 'submit_quote', amount: 61000, source: 'form',
  lead_time: '6 weeks from approval', validity: '30 days', payment_terms: '50% advance, 50% on completion',
  warranty: '12 months on materials and workmanship, parts and labour included',
  scope: 'Supply and installation of gypsum partitions and suspended ceiling. Installation included.',
  notes: '', vat_treatment: 'exclusive',
  items: [
    { description: 'Gypsum partition wall 100mm', qty: 120, unit: 'm2', unit_price: 350, amount: 42000, specification: 'Knauf 100mm partition, 12.5mm board both sides, 75mm studs at 600mm centres', spec: { board_type: 'Moisture-resistant board', thickness_mm: '12.5', frame: '75mm GI studs at 600mm centres', brand: 'Knauf' } },
    { description: 'Suspended ceiling tiles', qty: 80, unit: 'm2', unit_price: 237.5, amount: 19000, specification: 'Armstrong Dune Supreme 600x600 mineral tile on exposed T-grid', spec: { board_type: 'Mineral fibre tile', thickness_mm: '15', frame: 'Exposed 24mm white T-grid', brand: 'Armstrong Dune Supreme' } },
  ],
});

Deno.test('QuoteForm: a complete quotation IS approved — the door stays open', () => {
  const r = review(job(), filledForm());
  assertEquals(r.approved, true, 'the review refused a complete quotation: ' + JSON.stringify(r.issues.map((i) => [i.code, i.en])));
});

Deno.test('QuoteForm: an unpriced BOQ line is caught, and a foreign currency with it', () => {
  const b = filledForm();
  b.items = [b.items[0]];
  b.notes = 'Ceiling quoted separately in USD 5,000';
  const r = review(job(), b);
  assertEquals(r.approved, false);
  assert(codes(r).includes('boq_line_not_priced'));
  assert(codes(r).includes('currency_not_aed'));
});

Deno.test('QuoteForm: line amounts that do not add up to the total are caught', () => {
  const b = filledForm();
  b.amount = 99000;
  const r = review(job(), b);
  assertEquals(r.approved, false);
  assert(codes(r).includes('total_mismatch'));
});

// ── The explanations are the engineer's, never the caller's ─────────────────────────────────────
Deno.test('a caller cannot excuse a BOQ line by putting boq_excluded in its own request body', () => {
  const b = { ...filledForm(), boq_excluded: { '2': 'by others' }, qty_explained: { '1': 'measured on site' } } as Record<string, unknown>;
  (b as { items: unknown[] }).items = [(b as { items: unknown[] }).items[0]];
  b.amount = 42000;   // the one priced line, so only the BOQ rule is under test
  const forged = review(job(), b);
  assertEquals(forged.approved, false, 'a body-supplied exclusion must not silence the rule');
  assert(codes(forged).includes('boq_line_not_priced'));

  // The same exclusion, recorded by the sales engineer in quote_reviews.working, DOES silence it.
  const recorded = review(job(), b, { boq_excluded: { '2': 'by others' }, qty_explained: {} });
  assertEquals(recorded.approved, true, JSON.stringify(recorded.issues.map((i) => i.code)));
});

// ── Door 3: spec_approve releases the STORED quote ──────────────────────────────────────────────
Deno.test('spec_approve: the stored quote is reviewed as it stands, and a bad one is not released', () => {
  const stored = { quote_amount: 61000, price_ex_vat: 61000, vat_treatment: 'exclusive', lead_time: '6 weeks from approval', validity: '', warranty: '12 months on materials and workmanship, parts and labour included', scope: 'Supply and installation of gypsum partitions and suspended ceiling. Installation included.', conditions: '', exclusions: '', notes: '' };
  const rows = filledForm().items.map((i) => ({ ...i }));
  const bad = reviewQuotation(job(), { ...withResolved(workingFromStoredQuote(stored, rows), resolvedFrom(null)), boq_match: REASONED(rows) });
  assertEquals(bad.approved, false, 'a stored quote with no validity must not be released');
  assert(codes(bad).includes('validity'));

  const good = reviewQuotation(job(), { ...withResolved(workingFromStoredQuote({ ...stored, validity: '30 days' }, rows), resolvedFrom(null)), boq_match: REASONED(rows) });
  assertEquals(good.approved, true, JSON.stringify(good.issues.map((i) => i.code)));
});

Deno.test('the chat\'s REASONED match is carried only for exactly the lines it was reasoned for', () => {
  const b = filledForm();
  const w = workingFromSubmit(b, scrubbedOf(b), {}, [], null);
  const key = boqKey(job().boq_rows, w.lines);
  assertEquals(withResolved(w, resolvedFrom({ boq_match: { '1': 1, '2': 2 }, boq_match_for: key }), job().boq_rows).boq_match, { '1': 1, '2': 2 });
  assertEquals(withResolved(w, resolvedFrom({ boq_match: { '1': 1, '2': 2 }, boq_match_for: 'other-lines' }), job().boq_rows).boq_match, undefined, 'a match for other lines is not trusted');
  // no match at all: the review holds every BOQ line as a clarification rather than guessing
  const held = reviewQuotation(job(), w).issues.filter((i) => i.code === 'boq_line_not_priced');
  assertEquals(held.map((i) => i.kind), ['clarification', 'clarification']);
});

Deno.test('workingFromSubmit never carries the caller\'s explanations', () => {
  const w = workingFromSubmit({ boq_excluded: { '1': 'x' }, qty_explained: { '1': 'y' }, items: [] }, NO_SCRUB, {}, [], null);
  assertEquals(w.boq_excluded, {});
  assertEquals(w.qty_explained, {});
});
