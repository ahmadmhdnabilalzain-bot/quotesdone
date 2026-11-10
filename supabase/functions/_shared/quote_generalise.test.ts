// quote_generalise.test.ts — a quotation the customer reads before the reveal names no brand, model or product line,
// and keeps origin, tier and every specification (founder ledger 1589, 10 Nov 2026). Seat: sales_engineer.
// Each test FAILS on the behaviour before this change: the brand passed through (quote_from_document, my_inquiries,
// the quotation PDF's "Brand: / Model:"), or the generic lost its origin ("premium branded mixer").
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { brandFact, generaliseBrandValue, generaliseDeep, generaliseLine, generaliseModelValue, generaliseQuoteTerms, generaliseText, genericBrand,
  identitiesLeft, MODEL_HIDDEN, ORIGIN, originOf, productWords, specCode, statedOriginOf } from './quote_generalise.ts';
import { BRAND_ROWS } from './brand_facts.generated.ts';

const T = (s: string, ctx = {}) => generaliseText(s, ctx).text;

Deno.test("the founder's own example: a named German premium mixer becomes 'premium German brand mixer', never Italian", () => {
  assertEquals(T('Grohe basin mixer'), 'premium German brand basin mixer');
  assertEquals(T('Supply of GROHE Eurosmart 33265003 basin mixer, chrome'), 'Supply of premium German brand basin mixer, chrome');
  assert(!/italian/i.test(T('Grohe Eurosmart Cosmopolitan mixer')));
  assertEquals(genericBrand('Grohe').ar, 'علامة ألمانية فاخرة');
});

Deno.test('an unknown brand is "branded" plus the tier the quote states — an origin is never guessed', () => {
  assertEquals(generaliseBrandValue('Aquaflo'), 'branded');
  assertEquals(T('Aquaflo premium shower set', { brands: ['Aquaflo'] }), 'premium branded shower set');
  assertEquals(genericBrand('Zxqvbrand').origin, null);
  // a known brand with no recorded origin is also only "branded"
  const noOrigin = Object.entries(BRAND_ROWS).find(([, r]) => !r.o && !r.t && !r.w)![0];
  assertEquals(generaliseBrandValue(noOrigin), 'branded');
});

Deno.test('model numbers and SKUs are withheld, labelled or not; specifications are kept', () => {
  for (const [input, gone] of [['Daikin RXYQ10U outdoor unit', 'RXYQ10U'], ['Wash basin, Model: 2339800E', '2339800E'], ['Safety shoes, model JUMPER3', 'JUMPER3'],
    ['Catalogue no. 33265003 mixer', '33265003'], ['Ergonomic chair AER1B23DW', 'AER1B23DW'], ['Door, ref DR-2190', 'DR-2190']] as const) {
    // after a make the code goes with the make's generic words; on its own it is replaced by the withheld phrase
    const out = T(input); assert(!out.includes(gone), `${input} -> ${out}`); if (!/^Daikin/.test(input)) assertStringIncludes(out, MODEL_HIDDEN.en);
  }
  const spec = 'SS316 DN50 PN16 pipe to BS EN 1092-1, IP65, C40 concrete, R410A, 600x600 mm, 10 mm, 5 TR, 4MP, M20 bolts, 315/80R22.5 tyres, Cat6A, E7018 rods, 15W-40 oil, A15 cover, 12-month warranty, 90-minute fire rating';
  assertEquals(T(spec), spec);
  for (const s of ['SS316', 'DN50', 'IP65', 'C40', 'R410A', '600x600', 'E7018', '15W-40', '6205-2RS', 'TIA-568.2-D', '10GBASE-T']) assert(specCode(s), s);
  assert(!specCode('M751dn') && !specCode('A27'), 'a letter, a long number and a suffix is a model');
});

Deno.test("the supplier's own name inside a description becomes 'the supplier', in full or shortened", () => {
  const ctx = { supplierNames: ['ZZ DEMO Cedar Line Joinery LLC'] };
  assertEquals(T('Door frames, ZZ DEMO Cedar Line signature profile', ctx), 'Door frames, the supplier signature profile');
  assertEquals(T('Installed by ZZ DEMO Cedar Line Joinery', ctx), 'Installed by the supplier');
  // a common word alone is not a name core ("Gulf Steel Trading" must not eat "Gulf")
  assertEquals(T('Delivery anywhere in the Gulf region', { supplierNames: ['Gulf Steel Trading LLC'] }), 'Delivery anywhere in the Gulf region');
});

Deno.test('a proprietary product line is "proprietary"; a quoted phrase or a spec is not', () => {
  assertEquals(T('AquaShield™ waterproofing membrane 4 mm'), 'proprietary waterproofing membrane 4 mm');
  assertEquals(T('Mixer from the Eurosmart series'), 'Mixer from the proprietary series');
  assertEquals(T('Compare BOQs line by line'), 'Compare BOQs line by line');
  assertEquals(T('Quotes for "AC for a 4-bedroom villa" mix systems'), 'Quotes for "AC for a 4-bedroom villa" mix systems');
});

Deno.test('a brand that is also a plain word is taken only where the text treats it as a make', () => {
  assertEquals(T('Continental breakfast for 50 guests'), 'Continental breakfast for 50 guests');
  assertEquals(T('Carrier 5 TR ducted split unit'), 'premium American brand 5 TR ducted split unit');   // the packs' brand_origins give its tier (10 Nov)
  assertEquals(T('Brand: Carrier'), 'Brand: premium American brand');
  assertEquals(brandFact('Malaysian'), null, 'a nationality is never a brand');
});

Deno.test('origin is read as an origin, never from a place name', () => {
  assertEquals(statedOriginOf('Porcelain tiles, Italian origin'), 'IT');
  assertEquals(statedOriginOf('Cartons, UAE origin'), 'AE');
  assertEquals(statedOriginOf('Nitrile gloves, made in Malaysia'), 'MY');
  assertEquals(statedOriginOf('Supply and delivery anywhere in the UAE'), null);
  assertEquals(statedOriginOf('American Standard WC'), null, "a brand's own name is not an origin");
  assertEquals(originOf('PRC'), 'CN');
  const pw = productWords('Solar PV panels 550 W, European origin, JinkoSolar or equivalent');
  assertStringIncludes(pw, 'Solar PV panels 550 W'); assert(!/European|origin|Jinko|equivalent/.test(pw), pw);
});

Deno.test('a line, the terms and a technical table are generalised the way every surface serves them', () => {
  const line = { description: 'Roca L20 basin mixer', brand: 'Roca', model: '5A3009C00', specification: 'chrome, 5A3009C00', country_of_origin: 'Spain', spec: { brand: 'Roca', finish: 'chrome' } };
  const g = generaliseLine(line);
  assertEquals(g.brand, 'mid-range Spanish brand');
  assertEquals(g.model, MODEL_HIDDEN.en);
  assertEquals(g.country_of_origin, 'Spain', 'the origin is kept: it names no supplier');
  assertEquals((g.spec as Record<string, string>).brand, 'mid-range Spanish brand');
  assert(!JSON.stringify(g).includes('Roca') && !JSON.stringify(g).includes('5A3009C00'), JSON.stringify(g));
  const q = generaliseQuoteTerms({ scope: 'Supply of Hansgrohe Talis mixers by ZZ DEMO Nahr Sanitary', exclusions: 'Civil works', price_ex_vat: 100 }, { supplierNames: ['ZZ DEMO Nahr Sanitary Trading LLC'] });
  assertEquals(q.scope, 'Supply of premium German brand mixers by the supplier');
  assertEquals(q.price_ex_vat, 100);
  // deno-lint-ignore no-explicit-any
  const table: any = { lines: [{ item: 'Basin mixer', attributes: [{ code: 'brand', requested: 'Grohe or equivalent', cells: [{ quote_id: 'a', value: 'Roca', flag: 'differs' }] }, { code: 'model', cells: [{ quote_id: 'a', value: 'CR 10-5' }] }] }] };
  const d = generaliseDeep(table);
  assertEquals(d.lines[0].attributes[0].cells[0].value, 'mid-range Spanish brand');
  assertEquals(d.lines[0].attributes[1].cells[0].value, MODEL_HIDDEN.en);
  assertEquals(d.lines[0].attributes[0].requested, 'Grohe or equivalent', "the customer's own request is theirs");
  assertEquals(d.lines[0].attributes[0].cells[0].flag, 'differs');
});

Deno.test('Arabic text and figures pass unchanged', () => {
  const ar = 'بلاط بورسلين 60×60 سم، منشأ إيطالي، الكمية 120 م2، السعر 14,400 درهم';
  assertEquals(T(ar), ar);
  assertEquals(T('Total AED 125,000.00 excluding VAT, 50% advance'), 'Total AED 125,000.00 excluding VAT, 50% advance');
  assertEquals(generaliseModelValue(''), '');
});

Deno.test('every origin the brand table names has its adjective in both languages', () => {
  for (const [name, r] of Object.entries(BRAND_ROWS)) if (r.o) assert(ORIGIN[r.o], `${name}: ${r.o} has no adjective`);
  assertEquals(identitiesLeft('premium German brand basin mixer'), []);
  assertEquals(identitiesLeft('Grohe basin mixer'), ['Grohe']);
});
