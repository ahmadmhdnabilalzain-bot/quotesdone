// quote_review_notes.test.ts — the sales engineer's notes on a quotation against the request (founder ledger 1588,
// 10 Nov 2026), and the ranking that weighs them (ledger 1590). Seat: sales_engineer.
// Before this change no note existed and deterministic.ts left missing_from_request / spec_deviation empty, so each
// test below fails on that code: a quote that is cheap because it is not what was asked for was simply ranked first.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { DEVIATION_CODES, NOTE_CODES, notesAsLists, reviewNotes, reviewPenalty, type ReviewInput } from './quote_review_notes.ts';
import { identitiesLeft } from './quote_generalise.ts';
import { deterministicCompare } from '../quote_compare/deterministic.ts';
import { CORPUS, NOW, specOf } from './quote_review.fixture.ts';

const req = (lines: [string, number, string][], requirements: Record<string, unknown> = {}, summary = 'Villa works'): ReviewInput['request'] =>
  ({ lines: lines.map(([description, qty, unit], i) => ({ line_no: i + 1, description, qty, unit })), spec: { customer_requirements: { version: 2, ...requirements } }, summary, now: NOW });
const codes = (r: ReturnType<typeof reviewNotes>) => r.map((n) => `${n.code}@${n.line_no ?? 'q'}`).sort();

Deno.test("the founder's example: Italian origin asked, Chinese quoted — a high note, in both languages", () => {
  const n = reviewNotes({ request: req([['Porcelain tiles 600x600, Italian origin', 100, 'm2']]), quote: {}, lines: [{ line_no: 1, description: 'Porcelain tiles 600x600', qty: 100, unit: 'm2', country_of_origin: 'China' }] });
  assertEquals(codes(n), ['origin_deviation@1']);
  assert(n[0].en.includes('Italian') && n[0].en.includes('Chinese'), n[0].en);
  assert(/[ء-ي]/.test(n[0].ar) && n[0].ar.includes('إيطاليا') && n[0].ar.includes('الصين'), n[0].ar);
  assertEquals(n[0].severity, 'high');
});

Deno.test('origin through the brand when no country is stated; a place in the brief is not an origin request', () => {
  const viaBrand = reviewNotes({ request: req([['Ducted split AC 5 TR, Japanese origin', 2, 'nos']]), quote: {}, lines: [{ line_no: 1, description: 'Gree ducted split AC 5 TR', qty: 2, unit: 'nos' }] });
  assertEquals(codes(viaBrand), ['origin_deviation@1']);
  assert(!viaBrand[0].en.includes('Gree') && viaBrand[0].en.includes('Chinese brand'), viaBrand[0].en);
  const place = reviewNotes({ request: req([['Ducted split AC 5 TR', 2, 'nos']], {}, 'Cooling for a warehouse in the UAE, Dubai'), quote: {}, lines: [{ line_no: 1, description: 'Daikin ducted split AC 5 TR', qty: 2, unit: 'nos' }] });
  assertEquals(codes(place), []);
});

Deno.test('"or equivalent": matches the requested brand yes / alternative offered, named only generically', () => {
  const r = req([['Basin mixer, Grohe or equivalent', 6, 'nos']]);
  const same = reviewNotes({ request: r, quote: {}, lines: [{ line_no: 1, description: 'Basin mixer chrome', brand: 'GROHE', qty: 6, unit: 'nos' }] });
  assertEquals(codes(same), ['brand_match@1']);
  assert(same[0].en.endsWith(': yes.'), same[0].en);
  const alt = reviewNotes({ request: r, quote: {}, lines: [{ line_no: 1, description: 'Basin mixer chrome', brand: 'Hansgrohe', qty: 6, unit: 'nos' }] });
  assertEquals(codes(alt), ['brand_alternative@1']);
  assert(alt[0].en.includes('Alternative offered: premium German brand'), alt[0].en);
  const lower = reviewNotes({ request: r, quote: {}, lines: [{ line_no: 1, description: 'Basin mixer chrome', brand: 'Roca', qty: 6, unit: 'nos' }] });
  assertEquals(codes(lower), ['brand_alternative@1', 'brand_tier_lower@1']);
  for (const n of [...same, ...alt, ...lower]) assertEquals(identitiesLeft(n.en + ' ' + n.ar), [], 'a note never names a brand: ' + n.en);
});

Deno.test('scope left out, scope excluded, supply only against installation asked', () => {
  const r = req([['Waterproofing membrane to wet areas', 40, 'm2'], ['Tile adhesive', 10, 'bags']], { installation: { required: 'yes' } });
  const n = reviewNotes({ request: r, quote: { exclusions: 'Waterproofing works, scaffolding', scope: 'Supply only' }, lines: [{ line_no: 1, description: 'Tile adhesive', qty: 10, unit: 'bags' }] });
  assertEquals(codes(n), ['scope_excluded@1', 'scope_excluded@q']);
  const m = reviewNotes({ request: r, quote: { scope: 'Supply and installation' }, lines: [{ line_no: 1, description: 'Tile adhesive', qty: 10, unit: 'bags' }] });
  assertEquals(codes(m), ['scope_missing@1']);
  // installation not asked: supply only is not a deviation
  const s = reviewNotes({ request: req([['Tile adhesive', 10, 'bags']], { installation: { required: 'supply_only' } }), quote: { scope: 'Supply only' }, lines: [{ line_no: 1, description: 'Tile adhesive', qty: 10, unit: 'bags' }] });
  assertEquals(codes(s), []);
});

Deno.test('a lower grade, a short quantity, a late lead time, a short warranty', () => {
  const r = req([['Grab bars stainless steel SS316', 4, 'nos'], ['Concrete C40', 20, 'm3']], { warranty: { required: 'yes', min_months: 24 }, required_by: { flexible: false, date: '2026-11-30' } });
  const n = reviewNotes({ request: r, quote: { lead_time: '6 weeks', warranty: '12 months' }, lines: [
    { line_no: 1, description: 'Grab bars stainless steel SS304', qty: 4, unit: 'nos' }, { line_no: 2, description: 'Concrete C30', qty: 15, unit: 'm3' }] });
  assertEquals(codes(n), ['grade_lower@1', 'grade_lower@2', 'lead_time_late@q', 'quantity_mismatch@2', 'warranty_short@q']);
  // the same quote in time, with the warranty asked, the grade asked and the full quantity: nothing to say
  const ok = reviewNotes({ request: r, quote: { lead_time: '14 days', warranty: '2 years' }, lines: [
    { line_no: 1, description: 'Grab bars stainless steel SS316L', qty: 4, unit: 'nos' }, { line_no: 2, description: 'Concrete C40/50', qty: 20, unit: 'm3' }] });
  assertEquals(codes(ok), []);
  // a flexible date accepts any lead time
  const flex = reviewNotes({ request: req([['Concrete C40', 20, 'm3']], { required_by: { flexible: true, date: '2026-11-12' } }), quote: { lead_time: '8 weeks' }, lines: [{ line_no: 1, description: 'Concrete C40', qty: 20, unit: 'm3' }] });
  assertEquals(codes(flex), []);
});

Deno.test('every note the code writes has the shape the database will hold (fn_quote_review_notes_are_valid)', () => {
  let seen = 0;
  for (const t of CORPUS) {
    const request = { lines: t.request.map((r, i) => ({ ...r, line_no: i + 1 })), spec: specOf(t), summary: t.summary, now: NOW };
    for (const side of [t.deviant, t.control]) for (const n of reviewNotes({ request, quote: side.quote, lines: side.lines, supplierNames: [t.supplier] })) {
      seen++;
      assert(NOTE_CODES.includes(n.code), n.code);
      assert(['high', 'medium', 'info'].includes(n.severity));
      assert(n.en.trim().length >= 10 && /[ء-ي]/.test(n.ar), `${n.code}: ${n.en} / ${n.ar}`);
      assert(!/(?:,|;|\?)(?=[ء-ي])|[ء-ي][,;?]/.test(n.ar), 'a Latin comma straight after an Arabic letter: ' + n.ar);
      assert(!/contact|call|ask the supplier|confirm with/i.test(n.en), 'a note never sends the customer to a supplier before the reveal: ' + n.en);
      // "ZZ DEMO Gala": the supplier's distinctive name (its first word alone can be the customer's own: "gala dinner")
      assertEquals(identitiesLeft(n.en + ' ' + n.ar, [t.supplier.split(' ').slice(0, 3).join(' ')]), [], n.en);
    }
  }
  assert(seen > 100, `the corpus wrote ${seen} notes`);
});

Deno.test('the ranking weighs the notes: the cheaper quote that is not what was asked for is not ranked first', () => {
  const r = req([['Porcelain tiles 600x600, Italian origin, 10 mm', 120, 'm2'], ['Epoxy grout', 20, 'kg']], { warranty: { required: 'yes', min_months: 24 } });
  const cheapNotes = reviewNotes({ request: r, quote: { warranty: '6 months' }, lines: [{ line_no: 1, description: 'Porcelain tiles 600x600, 8 mm', qty: 100, unit: 'm2', country_of_origin: 'China' }] });
  assert(reviewPenalty(cheapNotes) >= 2, String(reviewPenalty(cheapNotes)));
  const base = { itemised: true, lead_time: '14 days', payment_terms: '50% advance', validity: '30 days', completeness: { score: 90, passed: true, missing_mandatory: 0 } };
  const out = deterministicCompare([
    { ...base, label: 'Supplier A', price: 9000, warranty: '6 months', review_notes: cheapNotes },
    { ...base, label: 'Supplier B', price: 14000, warranty: '2 years', review_notes: [] },
  ], 'en');
  assertEquals(out.top3[0].label, 'Supplier B');
  const a = out.quotes.find((q) => q.label === 'Supplier A')!;
  assert(a.missing_from_request.length === 1 && a.spec_deviation.length >= 3, JSON.stringify(a));
  const lists = notesAsLists(cheapNotes, 'ar');
  assert(lists.spec_deviation.every((x) => /[ء-ي]/.test(x)));
  assert([...DEVIATION_CODES].every((c) => NOTE_CODES.includes(c)));
});
