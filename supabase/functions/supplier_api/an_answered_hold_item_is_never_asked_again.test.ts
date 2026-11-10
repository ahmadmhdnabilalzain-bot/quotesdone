// AN ANSWERED HOLD ITEM IS NEVER ASKED AGAIN — defect F5 of the production walks, 10 Nov 2026
// (docs/reports/2026-11-10-walks-on-production.md). Seat: sales_engineer.
//
// What the walk measured: the sales engineer held a quote for `installation_included`; the supplier answered
// "Is installation included? yes" in the hold panel (spec_fill, which writes quotes.terms_spec.installation with
// source 'supplier_portal'); the quote was sent. He then refreshed the price through submit_quote. The quote form
// has no installation field, and submit_quote built the review from the request body alone, so the review held the
// quote for `installation_included` AGAIN, with no spec-hold panel to answer it on. He was stuck at "Held".
//
// These tests run the real review (reviewQuotation, with the mocked reading every review test uses) over the payload
// QuoteForm actually sends, before and after the answers the supplier gave on THAT quote are carried in.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { reviewQuotation, type SafeInquiry } from './quote_review.ts';
import { carryHeldAnswers, heldAnswersOf, optionOfEach, resolvedFrom, withResolved, workingFromSubmit, type HeldAnswers } from './submit_review.ts';
import { readFixture } from './review_reading.fixture.ts';

const INQ = 'd958e1ea-54f4-45a1-9214-d622ac52dce1';
const SUP = 4242;
const QID = '7b0c9a52-6a43-4c55-9d0f-0f3c1f0a1e01';

/** A job whose customer requires installation, with a two-line BOQ, as supplier_api `inbox` serves it. */
const job = (): SafeInquiry => ({
  id: INQ, job_no: 'RFQ-151767', category: 'gypsum', emirate: 'Dubai',
  spec: { customer_requirements: { version: 1, installation: { required: 'yes' }, warranty: { required: 'yes' } } },
  boq_withheld: false, concluded: false, revealed: false,
  boq_rows: [
    { description: 'Gypsum partition wall 100mm', qty: 120, unit: 'm2' },
    { description: 'Suspended ceiling tiles', qty: 80, unit: 'm2' },
  ],
});

const LINE1_SPEC = { board_type: 'Moisture-resistant board', thickness_mm: '12.5', frame: '75mm GI studs at 600mm centres', brand: 'Knauf' };
const LINE2_SPEC = { board_type: 'Mineral fibre tile', thickness_mm: '15', frame: 'Exposed 24mm white T-grid', brand: 'Armstrong Dune Supreme' };

/**
 * A PRICE REFRESH as QuoteForm `buildPayload()` sends it: every field on the screen, a new price, and NO word about
 * installation — the form has no field for it, and the scope he typed says "supply" only.
 */
const refresh = () => ({
  action: 'submit_quote', inquiry_id: INQ, amount: 57000, source: 'form',
  lead_time: '6 weeks from approval', validity: '30 days', payment_terms: '50% advance, 50% on completion',
  warranty: '12 months on materials and workmanship, parts and labour included',
  scope: 'Supply of gypsum partitions and suspended ceiling to the drawings.', notes: '', vat_treatment: 'exclusive',
  items: [
    { description: 'Gypsum partition wall 100mm', qty: 120, unit: 'm2', unit_price: 325, amount: 39000, specification: 'Knauf 100mm partition, 12.5mm board both sides, 75mm studs at 600mm centres', spec: { ...LINE1_SPEC } },
    { description: 'Suspended ceiling tiles', qty: 80, unit: 'm2', unit_price: 225, amount: 18000, specification: 'Armstrong Dune Supreme 600x600 mineral tile on exposed T-grid', spec: { ...LINE2_SPEC } },
  ] as Record<string, unknown>[],
} as Record<string, unknown>);

/** The quote row as it stands after the supplier answered the hold panel (workflow.ts fillIn). */
const storedRow = (over: Record<string, unknown> = {}) => ({
  id: QID, inquiry_id: INQ, supplier_id: SUP, option_no: 1, validity: '30 days',
  terms_spec: { installation: { included: 'yes', detail: 'Installation included, 5 working days on site', source: 'supplier_portal' } },
  ...over,
});
const storedLines = () => [
  { quote_id: QID, line_no: 1, description: 'Gypsum partition wall 100mm', spec: { ...LINE1_SPEC }, spec_source: { board_type: 'supplier_portal', thickness_mm: 'supplier_portal', frame: 'reasoned', brand: 'reasoned' } },
  { quote_id: QID, line_no: 2, description: 'Suspended ceiling tiles', spec: { ...LINE2_SPEC }, spec_source: {} },
];
const holdWith = (terms: Record<string, unknown>) => [{ quote_id: QID, supplier_values: [{ at: '2026-11-10T15:20:00Z', by: 'supplier', values: { terms } }] }];

const scrubbedOf = (b: Record<string, unknown>) => ({ notes: String(b.notes ?? ''), scope: String(b.scope ?? ''), conditions: String(b.conditions ?? ''), exclusions: String(b.exclusions ?? '') });
/** The review submit_quote runs, for a body (with its terms_spec, as quotes.ts reads it). */
const review = (body: Record<string, unknown>) => reviewQuotation(job(), readFixture(job(), withResolved(
  workingFromSubmit(body, scrubbedOf(body), (body.terms_spec ?? {}) as never, [], null), resolvedFrom(null))));
const codes = (r: { issues: { code: string }[] }) => [...new Set(r.issues.map((i) => i.code))].sort();
const INSTALL = ['installation_included', 'installation_detail'];

/** submit_quote's carry, for a single-option refresh of option 1. */
const carry = (body: Record<string, unknown>, held: (HeldAnswers | null)[]) => {
  const items = body.items as Record<string, unknown>[];
  return carryHeldAnswers(body, held.filter((h): h is HeldAnswers => !!h), optionOfEach(items, [{ option_no: 1, lines: items }]), [1]);
};
const OWNER = { inquiry_id: INQ, supplier_id: SUP };

Deno.test('the defect as measured: a price refresh reviewed from the body alone is held for installation again', () => {
  const r = review(refresh());
  assert(codes(r).includes('installation_included'), 'this is F5: ' + codes(r).join(','));
});

Deno.test('answered installation_included + a price refresh -> not held for it', () => {
  const h = heldAnswersOf(OWNER, storedRow(), storedLines(), holdWith({ installation_included: 'yes', installation_detail: 'Installation included, 5 working days on site' }));
  assert(h, 'the supplier\'s own quote must yield his answers');
  const c = carry(refresh(), [h]);
  const r = review(c.body);
  assert(!codes(r).some((x) => INSTALL.includes(x)), 'an answered hold item was asked again: ' + JSON.stringify(r.issues.map((i) => [i.code, i.en])));
  assertEquals(r.approved, true, JSON.stringify(r.issues.map((i) => [i.code, i.en])));
  // The row is written with the same answer the review read, so the hold gate (which reads the row) agrees.
  assertEquals(c.options['1'].terms_spec?.installation?.included, 'yes');
  assert(c.carried.includes('installation'), c.carried.join(','));
});

Deno.test('a line spec answered in the hold panel follows its line into the refresh', () => {
  const b = refresh();
  const items = b.items as Record<string, unknown>[];
  items[0] = { ...items[0], spec: { frame: LINE1_SPEC.frame, brand: LINE1_SPEC.brand } };   // the form lost board_type and thickness
  const before = review(b);
  assert(before.issues.some((i) => i.code === 'spec' && i.line_no === 1), 'precondition: line 1 is short of its answered specs');
  const c = carry(b, [heldAnswersOf(OWNER, storedRow(), storedLines(), [])]);
  const r = review(c.body);
  assert(!r.issues.some((i) => i.code === 'spec' && i.line_no === 1), JSON.stringify(r.issues.map((i) => [i.code, i.line_no, i.attr])));
  assertEquals((c.body.items as { spec: Record<string, string> }[])[0].spec.thickness_mm, '12.5');
});

Deno.test('a validity answered in the hold panel is carried when the refresh leaves it blank', () => {
  const b = { ...refresh(), validity: '' };
  assert(codes(review(b)).includes('validity'), 'precondition');
  const c = carry(b, [heldAnswersOf(OWNER, storedRow({ validity: '45 days' }), storedLines(), holdWith({ validity: '45 days' }))]);
  assertEquals(c.body.validity, '45 days');
  assert(!codes(review(c.body)).includes('validity'));
});

Deno.test('a new missing item -> still held', () => {
  // He answered installation; this refresh ALSO drops the validity, which he never answered in the panel.
  const b = { ...refresh(), validity: '' };
  const c = carry(b, [heldAnswersOf(OWNER, storedRow({ validity: '' }), storedLines(), holdWith({ installation_included: 'yes' }))]);
  const r = review(c.body);
  assertEquals(r.approved, false);
  assert(codes(r).includes('validity'), 'a genuinely new missing item must still hold: ' + codes(r).join(','));
  assert(!codes(r).some((x) => INSTALL.includes(x)), 'while the answered one stays answered');
  // And a validity only the original FORM stated (no hold answer for it) is not invented by the carry.
  const c2 = carry(b, [heldAnswersOf(OWNER, storedRow({ validity: '30 days' }), storedLines(), [])]);
  assertEquals(c2.body.validity, '');
});

Deno.test('a new BOQ line with no answer -> still held for its specs', () => {
  const b = refresh();
  (b.items as Record<string, unknown>[]).push({ description: 'Access panel 600x600', qty: 4, unit: 'nr', unit_price: 0, amount: 0 });
  const c = carry(b, [heldAnswersOf(OWNER, storedRow(), storedLines(), [])]);
  const items = c.body.items as { description: string; spec?: Record<string, string> }[];
  assertEquals(items[2].spec, undefined, 'no answer was given for this line, so none is carried to it');
});

Deno.test('the supplier restating it in the refresh wins over the carried answer', () => {
  const b = { ...refresh(), scope: 'Supply only, installation not included.' };
  const c = carry(b, [heldAnswersOf(OWNER, storedRow(), storedLines(), [])]);
  assert(!c.carried.includes('installation'), c.carried.join(','));
  assertEquals(c.options['1'].terms_spec?.installation, undefined);
  // An explicit terms_spec in the body wins too.
  const b2 = { ...refresh(), terms_spec: { installation: { included: 'no' } } };
  const c2 = carry(b2, [heldAnswersOf(OWNER, storedRow(), storedLines(), [])]);
  assertEquals((c2.body.terms_spec as { installation: { included: string } }).installation.included, 'no');
});

Deno.test('answers from a different quote are never carried over', () => {
  const ans = holdWith({ installation_included: 'yes' });
  // Another job's quote by the same supplier.
  assertEquals(heldAnswersOf(OWNER, storedRow({ inquiry_id: 'aaaaaaaa-0000-4000-8000-000000000000' }), storedLines(), ans), null);
  // The same job, another supplier's quote.
  assertEquals(heldAnswersOf(OWNER, storedRow({ supplier_id: SUP + 1 }), storedLines(), ans), null);
  // Lines and holds that belong to another quote id are not read as this quote's.
  const other = heldAnswersOf(OWNER, storedRow(), storedLines().map((l) => ({ ...l, quote_id: 'ffffffff-0000-4000-8000-000000000000' })), [{ ...ans[0], quote_id: 'ffffffff-0000-4000-8000-000000000000' }]);
  assertEquals(other?.lines, []);
  // This supplier's OTHER OPTION on the same job is a different quotation: its answers stay on it.
  const opt2 = heldAnswersOf(OWNER, storedRow({ option_no: 2 }), storedLines(), ans);
  const c = carry(refresh(), [opt2]);
  assertEquals(c.carried, []);
  assert(codes(review(c.body)).includes('installation_included'), 'option 2\'s answer must not answer option 1');
  // And with nothing held, the body is reviewed exactly as it was sent.
  assertEquals(carry(refresh(), []).body, refresh());
});

Deno.test('a two-option refresh: each option keeps its own answers; the shared review carries only what every option answered', () => {
  const items = [
    { description: 'Option 1 - Knauf', qty: null }, { description: 'Gypsum partition wall 100mm', qty: 120, unit: 'm2', unit_price: 325, amount: 39000 },
    { description: 'Option 2 - Gyproc', qty: null }, { description: 'Gypsum partition wall 100mm', qty: 120, unit: 'm2', unit_price: 300, amount: 36000 },
  ];
  const plan = [{ option_no: 1, lines: [items[1]] }, { option_no: 2, lines: [items[3]] }];
  const optOf = optionOfEach(items, plan);
  assertEquals(optOf, [null, 1, null, 2]);
  const h1 = heldAnswersOf(OWNER, storedRow({ option_no: 1 }), [{ quote_id: QID, description: 'Gypsum partition wall 100mm', spec: { thickness_mm: '12.5' }, spec_source: { thickness_mm: 'supplier_portal' } }], [])!;
  const h2 = heldAnswersOf(OWNER, storedRow({ id: 'b', option_no: 2, terms_spec: {} }), [{ quote_id: 'b', description: 'Gypsum partition wall 100mm', spec: { thickness_mm: '15' }, spec_source: { thickness_mm: 'supplier_portal' } }], [])!;
  const c = carryHeldAnswers({ ...refresh(), items }, [h1, h2], optOf, [1, 2]);
  const out = c.body.items as { spec?: Record<string, string> }[];
  assertEquals(out[1].spec?.thickness_mm, '12.5');
  assertEquals(out[3].spec?.thickness_mm, '15');
  // Only option 1 answered installation: its own row keeps it, option 2's row is not given it.
  assertEquals(c.options['1'].terms_spec?.installation?.included, 'yes');
  assertEquals(c.options['2'].terms_spec?.installation, undefined);
  assertEquals((c.body.terms_spec as Record<string, unknown> | undefined)?.installation, undefined);
});
