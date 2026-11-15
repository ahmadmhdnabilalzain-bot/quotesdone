// request_fit.test.ts — journey A's comparison report measures each quote against what the customer asked for.
// Seat: sales_engineer. 15 Nov 2026. The fixture is journey A of 15 Nov 2026 (run 8288bec3): the request as the intake
// recorded it and the three quotations as stored (request_fit.journey_a.fixture.ts). Every test here fails on main, where
// the report read "You asked for: —" on every line, recommended Supplier A first with "Completeness 5" and "All 30 match"
// while it gave 1 year of warranty against his 2, scored 5/3/1, printed a brand and a capacity "1" on the removal and
// service lines, and said nothing of what to settle before paying the reveal fee.
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/_shared/request_fit.test.ts
// The PDF text snapshot is rewritten by hand, after reading the new text, with
//   QD_UPDATE_SNAPSHOT=1 deno test --no-lock --node-modules-dir=none --allow-read=. --allow-write=supabase/functions/_shared --allow-env=QD_UPDATE_SNAPSHOT supabase/functions/_shared/request_fit.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { INQUIRY_A, journeyA, NOW, QUOTES_A, SUPPLIER_NAMES } from './request_fit.journey_a.fixture.ts';
import { enforceFit, fitQuote, isProductLine, requestRequirements, siteVisitAsked, warrantyParts } from './request_fit.ts';
import { compareDocument } from './quote_documents.ts';
import { renderPdf } from '../pdf_native/render.ts';
import { pdfTextByRows } from './pdf_text_positions.ts';

const FONTS = new URL('../pdf_native/fixtures/brand/', import.meta.url);
const fetchBytes = async (p: string) => (/\.ttf$/.test(p) ? await Deno.readFile(new URL(p, FONTS)) : null);
const SNAPSHOT = new URL('./request_fit.journey_a.report.txt', import.meta.url);
const linkFor = (x: string) => `https://quotesdone.ae/me/requests/${INQUIRY_A.id}?quote=${x}`;
const doc = (lang: 'en' | 'ar') => compareDocument({ analysis: journeyA(lang).analysis, inquiry: INQUIRY_A as never, lang, maskNames: SUPPLIER_NAMES, portalUrl: 'https://quotesdone.ae/me', linkFor, ...(lang === 'ar' ? { date_ar: '15 نوفمبر 2026' } : { date: '15 November 2026' }) });
async function reportText(): Promise<string> {
  const r = await renderPdf(doc('en').body, { fetchBytes });
  assert(r.ok, 'the report renders');
  if (!r.ok) return '';
  assertEquals(r.meta.glyphs_dropped, 0);
  return (await pdfTextByRows(r.bytes)).split('\n').map((s) => s.replace(/\s+$/, '')).join('\n');
}

Deno.test('1. the customer\'s own requirements reach the comparison as "You asked for"', () => {
  const reqs = requestRequirements(INQUIRY_A);
  assertEquals(reqs.map((r) => r.code), ['brand_list', 'inverter', 'refrigerant', 'capacity', 'installation', 'removal', 'ducted_service', 'copper', 'isolator', 'date', 'warranty_installation', 'warranty_compressor', 'material.ducting']);
  const asked = Object.fromEntries(reqs.map((r) => [r.code, r.asked.en]));
  assertEquals(asked.capacity, '2 × 1.5 TR and 2 × 2.0 TR');
  assertEquals(asked.refrigerant, 'R32 or R410A');
  assertEquals(asked.date, 'By 15 December 2026');
  assertEquals([asked.warranty_installation, asked.warranty_compressor], ['At least 2 years', 'At least 5 years']);
  assertEquals(asked.ducted_service, '3 units (3.0 TR): coils, filters, drain, gas check');
  assertEquals(asked.copper, 'Reuse the existing, or up to 5 m new per unit (20 m)');
  // The line-by-line table: every product attribute he stated has his value beside it.
  const { analysis: a } = journeyA('en');
  for (const l of a.technical.lines) {
    const req = Object.fromEntries(l.attributes.map((at: { key: string; requested: string | null }) => [at.key, at.requested]));
    assertEquals(req.brand, 'One of the 3 brands you named');
    assertEquals(req.refrigerant, 'R32 or R410A');
    assert(/^(1\.5|2\.0) TR$/.test(String(req.capacity_tr)), `capacity asked on "${l.item}"`);
  }
  assertEquals(a.technical.terms.warranty.requested, 'Installation warranty: At least 2 years; Compressor warranty: At least 5 years');
});

Deno.test('2. a quote that fails a stated requirement is never called complete, nor ranked first without saying so', () => {
  const { analysis: a, fits } = journeyA('en');
  assertEquals(fits['Supplier A'].hard_fails.map((f) => `${f.noun.en}: ${f.detail.en}`), ['installation warranty: 1 year against the 2 years you asked for']);
  assertEquals(a.top3.map((t: { label: string }) => t.label), ['Supplier B', 'Supplier C', 'Supplier A']);
  const tA = a.top3.find((t: { label: string }) => t.label === 'Supplier A');
  assertEquals(tA.tradeoff, 'Fails your installation warranty: 1 year against the 2 years you asked for.');
  const qA = a.quotes.find((q: { label: string }) => q.label === 'Supplier A');
  assert(qA.quality_score < 5 && qA.fails_request === true, 'A is not scored complete');
  assert(qA.flags[0].startsWith('Fails your installation warranty'), 'the first thing said of A is that it fails');
  // The rule holds on the model's ranking too (and on an analysis cached before it).
  const model = { top3: [{ rank: 1, label: 'Supplier A', why: 'Cheapest.', tradeoff: '' }, { rank: 2, label: 'Supplier B', why: 'x', tradeoff: '' }], bottom_line: 'Supplier A is the best value.' };
  enforceFit(model, fits, 'en');
  assertEquals(model.top3.map((t) => [t.rank, t.label]), [[1, 'Supplier B'], [2, 'Supplier A']]);
  assert(model.bottom_line.startsWith('We place Supplier B first: Supplier A fails your installation warranty'));
  assert(model.top3[1].tradeoff.startsWith('Fails your installation warranty'));
});

Deno.test('2b. the brand is checked against his list BEFORE it is anonymised; only yes / no, tier and origin leave', () => {
  const { analysis: a, fits } = journeyA('en');
  // Gree is his only economy Chinese brand, so "one of yours, economy Chinese" would name it (ledger 1588): A says only "as you asked".
  assertEquals(['Supplier A', 'Supplier B', 'Supplier C'].map((l) => fits[l].cells.brand_list.shown.en), ['As you asked; the brand is shown after the reveal', 'Yes: premium Japanese brand', 'Yes: premium Japanese brand']);
  const json = JSON.stringify(a);
  for (const name of ['Daikin', 'Gree', 'Mitsubishi', 'Arabian Air', 'Cool Breeze', 'Polar Tech']) assert(!json.includes(name), `"${name}" reaches the analysis`);
  // A brand he did not name fails the request, and is said to.
  const reqs = requestRequirements(INQUIRY_A);
  const other = { ...QUOTES_A[0], items: QUOTES_A[0].items.map((l) => ({ ...l, brand: l.brand ? 'Midea' : null, spec: l.spec ? { ...l.spec, brand: 'Midea' } : null, specification: l.specification?.replace('Gree', 'Midea') ?? null, description: l.description.replace('Gree', 'Midea') })) };
  const f = fitQuote(reqs, { quote: other, lines: other.items, now: NOW, trade: 'hvac', site_visit: true });
  assertEquals(f.brand.listed, false);
  assertEquals(f.cells.brand_list.status, 'differs');
  assert(f.hard_fails.some((x) => x.code === 'brand_list' && !/midea/i.test(x.detail.en)), 'the failure names no brand');
});

Deno.test('3. the recommendation says plainly what the extra money buys, with the price difference', () => {
  const { analysis: a } = journeyA('en');
  assertEquals(a.bottom_line, 'We recommend Supplier B: one of your listed brands (premium Japanese brand), and it meets 11 of your 13 requirements, including the installation warranty you asked for. It costs AED 3,471 more than Supplier A, which fails your installation warranty: 1 year against the 2 years you asked for.');
  assert(!/Highest combined score/.test(JSON.stringify(a.top3)), 'no generic reason is left');
  assertEquals([a.top3[0].why, a.top3[0].tradeoff], ['One of your listed brands (premium Japanese brand), and it meets 11 of your 13 requirements, including the installation warranty you asked for.',
    'It costs AED 3,471 more than Supplier A, which fails your installation warranty: 1 year against the 2 years you asked for.']);
  assertEquals(a.top3[1].why, 'It meets 11 of your 13 requirements; AED 3,104.85 more than Supplier B.');
});

Deno.test('4. price scores are proportional, and the date is a yes / no, not a score', () => {
  const { analysis: a } = journeyA('en');
  const by = Object.fromEntries(a.quotes.map((q: { label: string }) => [q.label, q]));
  assertEquals([by['Supplier A'].price_score, by['Supplier B'].price_score, by['Supplier C'].price_score], [5, 3.9, 3.3]);
  assertEquals(a.quotes.map((q: { delivery_score: unknown; meets_date: unknown }) => [q.delivery_score, q.meets_date]), [[null, true], [null, true], [null, true]]);
});

Deno.test('5. service, removal, piping and testing lines carry no product attributes; one unit for capacity', () => {
  assert(!isProductLine('Removal and disposal of existing wall split units', 'hvac'));
  assert(!isProductLine('Service of ducted unit 3 TR: coils, filters, drain, gas check', 'hvac'));
  assert(!isProductLine('Insulated copper piping where the existing cannot be reused', 'hvac'));
  assert(!isProductLine('Testing and commissioning', 'hvac'));
  assert(isProductLine('Wall split unit 1.5 TR, inverter, supply and install', 'hvac'));
  const { analysis: a } = journeyA('en');
  assertEquals(a.technical.lines.length, 2);
  assertEquals(a.technical.scope_lines_dropped, 4);
  const caps = a.technical.lines.flatMap((l: { attributes: { key: string; values: Record<string, { value: string }> }[] }) => l.attributes.filter((at) => at.key === 'capacity_tr').flatMap((at) => Object.values(at.values).map((c) => c.value)));
  assertEquals(caps, ['1.5 TR', '1.5 TR', '1.5 TR', '2.0 TR', '2.0 TR', '2.0 TR']);
});

Deno.test('6. each quote says what to clarify before the reveal', () => {
  const { fits } = journeyA('en');
  assertEquals(fits['Supplier A'].asks.map((x) => x.en), [
    'Is this price final, or subject to the site visit your request mentions?',
    'It excludes electrical works. Is connecting the new units to your existing isolators included?',
    'What warranty does it give on the compressors? You asked for at least 5 years; the quote does not say.',
  ]);
  assertEquals(fits['Supplier C'].asks.map((x) => x.en), ['Is this price final, or subject to the site visit your request mentions?']);
  assert(siteVisitAsked(INQUIRY_A.spec));
  assertEquals(warrantyParts('1 year — 1 year on the installation'), { install: 12, compressor: null, general: 12 });
  assertEquals(warrantyParts('5 years on compressors; 2 years on the installation'), { install: 24, compressor: 60, general: null });
});

Deno.test('7. the Arabic report carries the same comparison in Arabic, with nothing of ours left in English', () => {
  const { analysis: a, fits } = journeyA('ar');
  assert(a.bottom_line.startsWith('نوصي بـSupplier B'), a.bottom_line);
  const d = doc('ar');
  // Our own sentences (a code such as "R32" is the same in both languages and is the supplier's value in the line table).
  const ours = Object.values(fits).flatMap((f) => [...Object.values(f.cells).map((c) => c.shown.en), ...f.asks.map((x) => x.en)]).filter((s) => /[a-z]{3}/.test(s));
  for (const s of d.untranslated) assert(!ours.includes(s), `our own text "${s}" needs Arabic`);
  const body = JSON.stringify(d.body);
  for (const s of ['You asked for', 'Ask before you reveal', 'Points QuotesDone settles', 'What you asked for', 'Meets your request', 'Not stated']) assert(!body.includes(s), `"${s}" on the Arabic page`);
});

Deno.test('8. the report a customer downloads for journey A (PDF text snapshot)', async () => {
  const text = await reportText();
  const flat = text.replace(/\s+/g, ' ');
  for (const s of ['What you asked for, quote by quote', 'Requirement You asked for Supplier B Supplier C Supplier A', 'Refrigerant R32 or R410A R32 R32 R32', 'Points QuotesDone settles with the supplier for you', 'Supplier A fails what you asked for', 'It costs AED 3,471 more than Supplier A', '1.5 TR units: you asked for 2', 'Price score Meets your request Done by your date Overall']) assert(flat.includes(s), `"${s}" is not on the page`);
  for (const s of ['All 30 match', 'Highest combined score', 'relative to the other quotes', 'Ask before you reveal', 'put them to the suppliers', 'economy Chinese']) assert(!text.includes(s), `"${s}" is still on the page`);
  let update = false;
  try { update = (await Deno.permissions.query({ name: 'env', variable: 'QD_UPDATE_SNAPSHOT' })).state === 'granted' && !!Deno.env.get('QD_UPDATE_SNAPSHOT'); } catch { update = false; }
  if (update) { await Deno.writeTextFile(SNAPSHOT, text); return; }
  assertEquals(text, await Deno.readTextFile(SNAPSHOT));
});
