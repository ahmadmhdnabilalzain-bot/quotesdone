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

// A TIME AND A PHRASE ARE NOT MODELS (sales_engineer, 12 Nov 2026; final audit customer_journey M3, fix group Q6). The
// audit's exact strings from the comparison the customer read; every true model beside them is still hidden.
Deno.test('an ISO time and hyphenated wording are kept; the models beside them are still hidden', () => {
  assertEquals(generaliseText('generated_at 2026-11-11T23:44:05.271Z').text, 'generated_at 2026-11-11T23:44:05.271Z');
  assertEquals(generaliseText('None of the quotes say they priced after-6-pm working or 14th-floor service-lift access.').text,
    'None of the quotes say they priced after-6-pm working or 14th-floor service-lift access.');
  assertEquals(generaliseText('Pump model XR-450, 2026-11-11 delivery').text, 'Pump model stated (shown after reveal), 2026-11-11 delivery');
  assertEquals(generaliseText('Daikin FXSQ100PAVE ducted unit, after-6-pm installation').text, 'premium Japanese brand ducted unit, after-6-pm installation');
  assertEquals(generaliseText('Code AB-12-CD wall panel').text.includes('AB-12-CD'), false);
});

// THE REVIEW'S ADVERSARIAL STRINGS (12 Nov 2026): the M3 exemptions must hide every lower-case hyphenated brand+model,
// every labelled date-shaped catalogue number, and every hyphenated code ending in a number, exactly as main did.
Deno.test('lower-case hyphenated brand+model slugs and labelled date-shaped codes stay hidden', () => {
  for (const s of ['daikin-fxsq-100 ducted unit', 'lg-artcool-18 split', 'gree-pular-12 wall split', 'midea-xtreme-save-24', 'series: aqua-flow-25',
    'Supply of 6 nos lg-dual-inverter-18 units', 'carrier-xpower-gold-24', 'toshiba-seiya-13', 'grohe-euro-33', 'rak-ceramics-60', 'Model: Eco-Smart-12',
    'ducted unit model fxsq-pave-100', 'Model: fxsq-pave-100', 'hansgrohe talis-select-80', 'model aura-pro-9-12',
    'Part no: 2211-15-00 basin mixer', 'Model: 2026-11-11', 'cat. no: 3310-05-75T23', 'item code: 2025-12-31T12', 'Model no: 1200-60-10']) {
    const out = generaliseText(s).text;
    // hidden as a model, or (since round 2 reads the brand in any case) folded into the brand's generic with nothing left
    assert(out.includes(MODEL_HIDDEN.en) || (out !== s && identitiesLeft(out).length === 0 && !/talis|euro|fxsq/i.test(out)), `"${s}" was shown as "${out}"`);
  }
});

// A MODEL THE TABLE OR THE LABEL GIVES AWAY (sales_engineer, 12 Nov 2026; found by the review of the M3 fix, shown on main
// too). The hider and identitiesLeft must agree: every MUST-HIDE string is caught by identitiesLeft as written and is gone
// after the hider; every MUST-KEEP specification is untouched by both.
const MUST_HIDE = ['jotun-fenomastic-5', 'unit type eco-smart-12', 'mixer type euro-smart-33',
  'Jotun-Fenomastic paint', 'type aquaflowmax-12', 'range ultra-flex-40', 'series aqua-flow-25', 'Daikin-FXSQ-100 unit', 'grohe-eurosmart-cosmo basin mixer',
  'model: aura-pro-12', 'item no. hydro-max-9', 'Supply of hansgrohe-talis-80 mixers', 'ducted unit type daikin-fbq'];
const MUST_KEEP = ['unit type ducted split', 'type wall-mounted', 'glass type tempered 6 mm', 'Type 2 connector', 'type B-s1,d0 panel',
  'temperature range 10-20 C', 'type 304L stainless', 'floor screed, type self-levelling', 'door-to-door delivery', 'water-based paint',
  'fire-rated 60-min door', 'price range mid-tier', 'series-connected panels'];
Deno.test('a brand inside a hyphenated token, or a model-shaped token after "type", is hidden, and identitiesLeft agrees', () => {
  for (const s of MUST_HIDE) {
    assert(identitiesLeft(s).length > 0, `identitiesLeft misses "${s}"`);
    const out = generaliseText(s).text;
    assertEquals(identitiesLeft(out), [], `"${s}" still identifies after the hider: "${out}"`);
    assert(out !== s, `"${s}" was shown as written`);
  }
});
Deno.test('a specification after "type" or "range", and hyphenated wording, are kept by the hider and by identitiesLeft', () => {
  for (const s of MUST_KEEP) { assertEquals(generaliseText(s).text, s); assertEquals(identitiesLeft(s), [], s); }
});

// ROUND 2 OF THE REVIEW (12 Nov 2026). The rule (quote_generalise.ts, "WHEN IS A TOKEN A MODEL CODE") in both directions, with
// identitiesLeft catching every MUST-HIDE string as written and nothing after the hider.
const R2_HIDE = ['grohe basin mixer', 'daikin ducted unit', 'daikin_fxsq_100', 'daikin.fxsq.100', 'Type XR450', 'type xr-450', 'مكيف دايكن 3 طن',
  'jotun paint', 'supply of hikvision cameras', 'MITSUBISHI electric', 'daikin‑fxsq‑100', '(daikin-fxsq-100)', 'range: eco_smart_12', 'series 5000-pro',
  'دهان جوتن', 'مكيفات ال جي', 'type ecosmart12', 'k-flex insulation'];
const R2_KEEP = ['type fire-rated-60', 'type double-glazed-24', 'series stainless-steel-304', 'type heavy-duty-10', 'type anti-slip-11', 'type moisture-resistant-18',
  'type 5-ton ducted', 'type cassette-4-way', 'type IP65', 'type R32', 'glass type tempered 6 mm', 'type split-ac', 'type 1-phase', 'range: 5-10 kW', 'model year 2026',
  'crown moulding', 'carrier bag', 'national standard'];
Deno.test('round 2: bare brands in any case, any separator, Arabic spellings and labelled codes are hidden, and identitiesLeft agrees', () => {
  for (const s of R2_HIDE) {
    assert(identitiesLeft(s).length > 0, `identitiesLeft misses "${s}"`);
    const out = generaliseText(s).text;
    assert(out !== s, `"${s}" was shown as written`);
    assertEquals(identitiesLeft(out), [], `"${s}" still identifies after the hider: "${out}"`);
  }
});
Deno.test('round 2: ordinary specifications after a label are kept, and a brand inside ordinary wording keeps the wording', () => {
  for (const s of R2_KEEP) { assertEquals(generaliseText(s).text, s); assertEquals(identitiesLeft(s), [], s); }
  assertEquals(generaliseText('non-daikin equivalent').text, 'non-premium Japanese brand equivalent');
  assert(!/brand/.test(generaliseText('crown-cut-06 veneer').text), 'a plain-word brand inside a veneer cut was named a brand');
});
