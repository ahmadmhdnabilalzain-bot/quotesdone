// quote_documents.fixture.ts — two requests, all ZZ DEMO: the HVAC case (seven quotes) and a FIT-OUT
// joinery case (five quotes with rich material specs, one of them held for a missing thickness).
//
// Used by quote_documents.test.ts and by the sample renderer, so the documents the tests assert on
// are the documents a person looks at. Every name is "ZZ DEMO …", every email @example.invalid and
// every number +971 50 000 00xx: none of it can reach a real person, and none of it is a row in any
// database. The supplier identities are here ON PURPOSE — the test proves they never reach a page.
//
// The TechnicalComparison objects stand in for what the spec agent's contract
// (docs/contracts/technical_comparison.md) will produce: stated value per attribute, per line, per
// supplier, flagged against the request, plus the lead-time / installation / warranty checks.
import { supplierLabel, type InquiryDocRow, type Item, type TechnicalComparison } from './quote_documents.ts';
import { isLiveQuote } from './quote_live.ts';
import type { Labelled } from '../quote_compare/deterministic.ts';

export type FixtureQuote = {
  id: string; status: string; quote_amount: number | null; lead_time: string | null; validity: string | null; warranty: string | null;
  payment_terms: string | null; scope: string | null; conditions: string | null; exclusions: string | null; notes: string | null;
  installation_included?: boolean | null; installation_scope?: string | null; installation_timeline?: string | null; warranty_coverage?: string | null;
  supplier: { company_name: string; email: string; phone: string; website: string };
  items: Item[];
  completeness: { score: number | null; passed: boolean | null; missing_mandatory: number | null };
};
type Inquiry = { id: string; category: string; summary: string; emirate: string };

const sup = (n: number, name: string) => ({ company_name: `ZZ DEMO ${name} LLC`, email: `sales${n}@zzdemo-${n}.example.invalid`, phone: `+971 50 000 00${String(n).padStart(2, '0')}`, website: `www.zzdemo-${n}.example.invalid` });
const live = (qs: FixtureQuote[]) => qs.filter((q) => q.status !== 'draft').sort((a, b) => (a.quote_amount ?? Number.POSITIVE_INFINITY) - (b.quote_amount ?? Number.POSITIVE_INFINITY));
const labelOf = (qs: FixtureQuote[]) => live(qs).map((q, i) => ({
  quote_id: q.id, label: 'Supplier ' + supplierLabel(i), price: q.quote_amount, lead_time: q.lead_time, validity: q.validity,
  warranty: q.warranty, payment_terms: q.payment_terms, exclusions: q.exclusions, itemised: q.items.length > 0, expired: false,
  source: 'form', completeness: q.completeness,
}));
const idsOf = (qs: FixtureQuote[]) => qs.flatMap((q) => [q.supplier.company_name, q.supplier.email, q.supplier.phone, q.supplier.website]);

// ── Case 1: HVAC, seven quotes (one incomplete, one draft) ─────────────────────────────────────────
export const INQUIRY: Inquiry = {
  id: 'zzd3m0aa-7c1e-4f00-9a00-000000000001',
  category: 'hvac',
  summary: 'Supply and install ducted split AC for a 3-bedroom villa in Al Barsha (approx. 24 TR total), including copper piping, drain lines and thermostats.',
  emirate: 'Dubai',
};
const hvacItems = (brand: string): Item[] => [
  { desc: `${brand} ducted split unit 5 TR, R410A, inverter`, qty: '4', unit: 'Nos' },
  { desc: `${brand} ducted split unit 2 TR, R410A, inverter`, qty: '2', unit: 'Nos' },
  { desc: 'Copper piping, insulated, per ASHRAE sizing', qty: '120', unit: 'LM' },
  { desc: 'GI ductwork with 25mm insulation', qty: '85', unit: 'sqm' },
  { desc: 'Programmable wall thermostat', qty: '6', unit: 'Nos' },
  { desc: 'Testing and commissioning', qty: '1', unit: 'Lot' },
];
// Deliberately NOT in price order: the letters come from sorting, as they do in production.
export const QUOTES: FixtureQuote[] = [
  { id: 'q-4', status: 'submitted', quote_amount: 96500, lead_time: '3 weeks', validity: '30 days', warranty: '2 years', payment_terms: '40% advance, 60% on completion', scope: 'Full supply, installation, testing and commissioning.', conditions: 'Site access 8am-6pm.', exclusions: 'False ceiling works and electrical isolators.', notes: null, supplier: sup(4, 'Arctic Breeze'), items: hvacItems('Daikin'), completeness: { score: 90, passed: true, missing_mandatory: 0 } },
  { id: 'q-1', status: 'submitted', quote_amount: 78900, lead_time: '2 weeks', validity: '30 days', warranty: '12 months', payment_terms: '50% advance, 50% on completion', scope: 'Supply and install as per BOQ.', conditions: null, exclusions: 'Civil works, core cutting.', notes: 'Price includes delivery to site. For queries call ZZ DEMO Cool Air on +971 50 000 0001 or sales1@zzdemo-1.example.invalid. Prices exclude 5% VAT; our TRN is 100123456700003.', installation_included: true, installation_scope: 'Supply, installation, testing and commissioning', installation_timeline: '5 days', warranty_coverage: 'Parts and labour', supplier: sup(1, 'Cool Air'), items: hvacItems('Gree'), completeness: { score: 86, passed: true, missing_mandatory: 0 } },
  { id: 'q-7', status: 'submitted', quote_amount: null, lead_time: null, validity: null, warranty: null, payment_terms: null, scope: 'Rate on request after site visit.', conditions: null, exclusions: null, notes: null, supplier: sup(7, 'Frost Line'), items: [], completeness: { score: 22, passed: false, missing_mandatory: 5 } },
  { id: 'q-2', status: 'submitted', quote_amount: 84250, lead_time: '10-14 days', validity: '15 days', warranty: '18 months', payment_terms: '30% advance, 70% on delivery', scope: 'Supply, install, test.', conditions: 'Price valid for listed quantities only.', exclusions: 'Scaffolding above 4m.', notes: null, supplier: sup(2, 'Polar Tech'), items: hvacItems('Midea'), completeness: { score: 78, passed: true, missing_mandatory: 1 } },
  { id: 'q-5', status: 'submitted', quote_amount: 101200, lead_time: '4 weeks', validity: '45 days', warranty: '3 years', payment_terms: '100% advance', scope: 'Turnkey installation.', conditions: null, exclusions: null, notes: null, supplier: sup(5, 'Chill Masters'), items: hvacItems('Mitsubishi Electric'), completeness: { score: 88, passed: true, missing_mandatory: 0 } },
  { id: 'q-3', status: 'submitted', quote_amount: 88000, lead_time: '3 weeks', validity: '30 days', warranty: '12 months', payment_terms: 'LC at sight', scope: 'Supply and installation.', conditions: null, exclusions: 'Drain pumps.', notes: null, supplier: sup(3, 'Desert Cooling'), items: hvacItems('Carrier'), completeness: { score: 64, passed: true, missing_mandatory: 2 } },
  { id: 'q-6', status: 'submitted', quote_amount: 112000, lead_time: '6 weeks', validity: '30 days', warranty: '5 years', payment_terms: '20% advance, 80% on handover', scope: 'Premium VRF alternative offered as option.', conditions: null, exclusions: null, notes: null, supplier: sup(6, 'Oasis HVAC'), items: hvacItems('LG'), completeness: { score: 92, passed: true, missing_mandatory: 0 } },
  // A draft is not a quote the customer has: it must take no letter and appear nowhere.
  { id: 'q-draft', status: 'draft', quote_amount: 50000, lead_time: null, validity: null, warranty: null, payment_terms: null, scope: null, conditions: null, exclusions: null, notes: null, supplier: sup(9, 'Unsent Draft'), items: [], completeness: { score: null, passed: null, missing_mandatory: null } },
];
/** The live quotes in the order production labels them: non-draft, ascending price, no price last. */
export function liveQuotes(): FixtureQuote[] { return live(QUOTES); }
/** What quote_compare builds before ranking — the same shape, the same labels. */
export function labelled(): Array<Labelled & { quote_id: string }> { return labelOf(QUOTES); }
/** Every supplier identity in the fixture: the strings that must never appear on a page. */
export function identities(): string[] { return idsOf(QUOTES); }

const v = (value: string | null, flag: 'match' | 'differs' | 'missing' | 'na', note?: string) => ({ value, flag, ...(note ? { note } : {}) });
export const HVAC_TECHNICAL: TechnicalComparison = {
  suppliers: ['Supplier A', 'Supplier B', 'Supplier C'],
  lines: [
    { line_no: 1, item: 'Ducted split unit 5 TR', qty: 4, unit: 'Nos', attributes: [
      { key: 'cooling_capacity', label: 'Cooling capacity', requested: '5 TR', values: { 'Supplier A': v('5 TR', 'match'), 'Supplier B': v('5 TR', 'match'), 'Supplier C': v('5 TR', 'match') } },
      { key: 'refrigerant', label: 'Refrigerant', requested: 'R410A', values: { 'Supplier A': v('R410A', 'match'), 'Supplier B': v('R32', 'differs'), 'Supplier C': v(null, 'missing') } },
      { key: 'compressor', label: 'Compressor', requested: 'Inverter', values: { 'Supplier A': v('Inverter', 'match'), 'Supplier B': v('Inverter', 'match'), 'Supplier C': v('Non-inverter', 'differs') } },
      { key: 'brand', label: 'Brand', requested: 'Gree, Midea or approved equal', values: { 'Supplier A': v('Gree', 'match'), 'Supplier B': v('Midea', 'match'), 'Supplier C': v('Carrier', 'match') } },
    ] },
    { line_no: 2, item: 'Copper piping, insulated', qty: 120, unit: 'LM', attributes: [
      { key: 'material', label: 'Material', requested: 'Copper, insulated', values: { 'Supplier A': v('Copper, insulated', 'match'), 'Supplier B': v('Copper, insulated', 'match'), 'Supplier C': v('Copper, insulated', 'match') } },
      { key: 'insulation_thickness', label: 'Insulation thickness', requested: '19 mm', values: { 'Supplier A': v('19 mm', 'match'), 'Supplier B': v('13 mm', 'differs'), 'Supplier C': v(null, 'missing') } },
    ] },
    { line_no: 3, item: 'GI ductwork', qty: 85, unit: 'sqm', attributes: [
      { key: 'material', label: 'Material', requested: 'GI', values: { 'Supplier A': v('GI', 'match'), 'Supplier B': v('GI', 'match'), 'Supplier C': v('GI', 'match') } },
      { key: 'insulation_thickness', label: 'Insulation thickness', requested: '25 mm', values: { 'Supplier A': v('25 mm', 'match'), 'Supplier B': v('25 mm', 'match'), 'Supplier C': v('25 mm', 'match') } },
    ] },
    { line_no: 4, item: 'Programmable wall thermostat', qty: 6, unit: 'Nos', attributes: [
      { key: 'type', label: 'Type', requested: 'Programmable', values: { 'Supplier A': v('Programmable', 'match'), 'Supplier B': v('Programmable', 'match'), 'Supplier C': v('Non-programmable', 'differs') } },
    ] },
  ],
  terms: {
    lead_time: { requested: 'Within 3 weeks', values: { 'Supplier A': v('2 weeks', 'match'), 'Supplier B': v('10-14 days', 'match'), 'Supplier C': v('3 weeks', 'match') } },
    installation: { applicable: true, requested: 'Included, with testing and commissioning', values: { 'Supplier A': v('Included — supply, installation, testing and commissioning; 5 days on site', 'match'), 'Supplier B': v('Included — installation and testing', 'differs', 'commissioning not stated'), 'Supplier C': v(null, 'missing') } },
    warranty: { applicable: true, requested: '2 years, parts and labour', values: { 'Supplier A': v('12 months — parts and labour', 'differs'), 'Supplier B': v('18 months — parts only', 'differs'), 'Supplier C': v('12 months', 'missing', 'coverage not stated') } },
  },
};

// ── Case 2: FIT-OUT joinery, five quotes, one held for a missing thickness ────────────────────────
export const FITOUT_INQUIRY: Inquiry = {
  id: 'zzd3m0bb-7c1e-4f00-9a00-000000000002',
  category: 'carpentry-joinery',
  summary: 'Joinery package for a 3-bedroom apartment in Dubai Marina: built-in wardrobes, kitchen cabinets and internal doors, supply and installation.',
  emirate: 'Dubai',
};
type Spec = Record<string, string | null>;
const joinery = (w: Spec, kc: Spec, d: Spec, rates: [number, number, number]): Item[] => [
  { desc: 'Built-in wardrobe, full height, 2400 x 1800 mm', qty: '3', unit: 'Nos', unit_price: rates[0], amount: rates[0] * 3, specs: w },
  { desc: 'Kitchen cabinets, base and wall units', qty: '8.5', unit: 'LM', unit_price: rates[1], amount: Math.round(rates[1] * 8.5), specs: kc },
  { desc: 'Internal door with frame and ironmongery', qty: '5', unit: 'Nos', unit_price: rates[2], amount: rates[2] * 5, specs: d },
];
const REQ = {
  w: { carcass_material: 'Moisture resistant MDF', thickness: '18 mm', finish: 'PU lacquer, matt', edge_band: '1 mm PVC', hardware: 'Blum soft close' },
  k: { carcass_material: 'Marine plywood', thickness: '18 mm', door_finish: 'HPL, Egger', edge_band: '2 mm ABS', worktop: '20 mm quartz' },
  d: { leaf: 'Solid core, solid oak veneer', thickness: '44 mm', fire_rating: '30 min', finish: 'PU lacquer, matt' },
};
export const FITOUT_QUOTES: FixtureQuote[] = [
  { id: 'f-3', status: 'submitted', quote_amount: 68900, lead_time: '6 weeks', validity: '30 days', warranty: '1 year', payment_terms: '50% advance, 40% on delivery, 10% on handover', scope: 'Supply and installation as per drawings.', conditions: 'Final site measurements before production.', exclusions: 'Wall tiling, electrical points and appliances.', notes: null, installation_included: true, installation_scope: 'Installation', installation_timeline: '12 days', warranty_coverage: 'Workmanship only', supplier: sup(13, 'Oak and Grain'), completeness: { score: 80, passed: true, missing_mandatory: 0 },
    items: joinery({ ...REQ.w, finish: 'PU lacquer, high gloss' }, { ...REQ.k, thickness: '16 mm' }, REQ.d, [9400, 2600, 2700]) },
  { id: 'f-1', status: 'submitted', quote_amount: 62400, lead_time: '5 weeks', validity: '30 days', warranty: '2 years', payment_terms: '40% advance, 50% on delivery, 10% on handover', scope: 'Supply and installation as per drawings.', conditions: 'Final site measurements before production. Power and water by client.', exclusions: 'Wall tiling, electrical points and appliances.', notes: 'Samples of finishes available on request. Contact ZZ DEMO Woodline on +971 50 000 0011.', installation_included: true, installation_scope: 'Full installation', installation_timeline: '10 days', warranty_coverage: 'Materials and workmanship', supplier: sup(11, 'Woodline'), completeness: { score: 90, passed: true, missing_mandatory: 0 },
    items: joinery(REQ.w, REQ.k, REQ.d, [9800, 2400, 2520]) },
  { id: 'f-5', status: 'submitted', quote_amount: 88000, lead_time: '6 weeks', validity: '45 days', warranty: '5 years', payment_terms: 'LC at sight', scope: 'Supply and installation as per drawings.', conditions: null, exclusions: null, notes: null, installation_included: true, installation_scope: 'Full installation', installation_timeline: '10 days', warranty_coverage: 'Materials and workmanship', supplier: sup(15, 'Royal Joinery'), completeness: { score: 94, passed: true, missing_mandatory: 0 },
    items: joinery(REQ.w, REQ.k, REQ.d, [13600, 3400, 3480]) },
  // Held: it states no thickness on two lines and no warranty, so it fails the completeness check.
  { id: 'f-2', status: 'submitted', quote_amount: 66000, lead_time: '5 weeks', validity: '30 days', warranty: null, payment_terms: '50% advance, 50% on completion', scope: 'Supply and installation.', conditions: null, exclusions: null, notes: null, installation_included: true, installation_scope: 'Installation', installation_timeline: null, warranty_coverage: null, supplier: sup(12, 'Cedar Craft'), completeness: { score: 25, passed: false, missing_mandatory: 2 },
    items: joinery({ ...REQ.w, thickness: null }, { ...REQ.k, thickness: null }, REQ.d, [9600, 2500, 2600]) },
  { id: 'f-4', status: 'submitted', quote_amount: 74500, lead_time: '8 weeks', validity: '30 days', warranty: '2 years', payment_terms: '30% advance, 60% on delivery, 10% retention', scope: 'Supply and installation.', conditions: null, exclusions: 'Appliances.', notes: null, installation_included: true, installation_scope: 'Installation', installation_timeline: null, warranty_coverage: 'Materials and workmanship', supplier: sup(14, 'Timber Works'), completeness: { score: 85, passed: true, missing_mandatory: 0 },
    items: joinery({ ...REQ.w, carcass_material: 'Chipboard' }, REQ.k, { ...REQ.d, fire_rating: null }, [11200, 2800, 2600]) },
];
// ── Case 3: the HVAC request as the supplier's inbox serves it (the inquiry document) ───────────────
// The row is what supplier_api `inbox` returns AFTER its scrubbers: spec with the intake answers and
// the derived display rows, the BOQ, and the document list inquiry_documents offers. The summary
// deliberately carries a phone number and an e-mail, which the document must mask on its own.
export const REQUEST: InquiryDocRow = {
  id: INQUIRY.id, category: INQUIRY.category, emirate: INQUIRY.emirate, created_at: '2026-09-14T08:30:00.000Z', scope_type: 'supply_and_install', urgency: 'normal',
  summary: INQUIRY.summary + ' Site contact for access: +971 50 000 0099, access@zzdemo-owner.example.invalid.',
  budget: 'around 90k',
  spec: { customer_requirements: {
    version: 2, recorded_by: 'sales_engineer', category: 'hvac', recorded_at: '2026-09-14T08:29:00.000Z',
    installation: { required: 'yes' }, warranty: { required: 'yes', min_months: 24 },
    materials: [{ component: 'units', label_en: 'AC units', label_ar: 'وحدات التكييف', choice: 'other', choice_en: 'Other: Daikin or Gree', choice_ar: 'أخرى: دايكن أو جري', note: 'Daikin or Gree' }],
    required_by: { flexible: false, date: '2026-10-14', text: 'Within 1 month' },
    display: {
      en: [{ key: 'material.units', label: 'AC units', value: 'Daikin or Gree' }, { key: 'installation', label: 'Installation', value: 'Yes, install it' }, { key: 'warranty', label: 'Warranty', value: 'Yes, at least 2 years' }, { key: 'required_by', label: 'Required by', value: '14 October 2026' }],
      ar: [{ key: 'material.units', label: 'وحدات التكييف', value: 'دايكن أو جري' }, { key: 'installation', label: 'التركيب', value: 'نعم، مع التركيب' }, { key: 'warranty', label: 'الضمان', value: 'نعم، سنتان على الأقل' }, { key: 'required_by', label: 'مطلوب بحلول', value: '14 أكتوبر 2026' }],
    },
  } },
  boq: { boq: [
    { section: 'Equipment', description: 'Ducted split unit 5 TR, R410A, inverter', qty: 4, unit: 'Nos' },
    { section: 'Equipment', description: 'Ducted split unit 2 TR, R410A, inverter', qty: 2, unit: 'Nos' },
    { section: 'Piping', description: 'Copper piping, insulated, 19 mm', qty: 120, unit: 'LM' },
    { section: 'Ducting', description: 'GI ductwork with 25mm insulation', qty: 85, unit: 'sqm' },
    { section: 'Controls', description: 'Programmable wall thermostat', qty: 6, unit: 'Nos' },
    { section: 'Commissioning', description: 'Testing and commissioning', qty: 1, unit: 'Lot' },
  ] },
  boq_withheld: false,
  documents: [
    { kind: 'drawing_page', name: 'Job_ZZD3M0AA_drawing_p01.jpg' }, { kind: 'drawing_page', name: 'Job_ZZD3M0AA_drawing_p02.jpg' },
    { kind: 'boq_csv', name: 'Job_ZZD3M0AA_BOQ.csv', lines: 6 },
  ],
  drawing_pages_failed: 1,
};
/** The customer's contact details planted in the request: the strings that must never appear on the page. */
export const REQUEST_CONTACTS = ['+971 50 000 0099', 'access@zzdemo-owner.example.invalid'];
export function fitoutLive(): FixtureQuote[] { return live(FITOUT_QUOTES); }
export function fitoutLabelled(): Array<Labelled & { quote_id: string }> { return labelOf(FITOUT_QUOTES); }
export function fitoutIdentities(): string[] { return idsOf(FITOUT_QUOTES); }

/** The technical comparison for the fit-out case, built from the fixture's own specs against REQ —
 * the flags a contract producer would set: equal → match, different → differs, absent → missing. */
export function fitoutTechnical(): TechnicalComparison {
  const lab = fitoutLabelled(); const byLabel = new Map(lab.map((l) => [l.label, FITOUT_QUOTES.find((q) => q.id === l.quote_id)!]));
  const suppliers = lab.map((l) => l.label);
  const LINES: Array<[string, string, string, Spec]> = [['Built-in wardrobe', '3', 'Nos', REQ.w], ['Kitchen cabinets', '8.5', 'LM', REQ.k], ['Internal door', '5', 'Nos', REQ.d]];
  const LABEL: Record<string, string> = { carcass_material: 'Carcass material', thickness: 'Thickness', finish: 'Finish', edge_band: 'Edge band', hardware: 'Hardware', door_finish: 'Door finish', worktop: 'Worktop', leaf: 'Door leaf', fire_rating: 'Fire rating' };
  const lines = LINES.map(([item, qty, unit, req], li) => ({ line_no: li + 1, item, qty, unit, attributes: Object.entries(req).map(([key, want]) => ({
    key, label: LABEL[key] ?? key, requested: want,
    values: Object.fromEntries(suppliers.map((s) => { const got = byLabel.get(s)!.items[li].specs?.[key] ?? null; return [s, v(got, got == null ? 'missing' : got === want ? 'match' : 'differs')]; })),
  })) }));
  const term = (f: (q: FixtureQuote) => { value: string | null; flag: 'match' | 'differs' | 'missing' | 'na'; note?: string }) => Object.fromEntries(suppliers.map((s) => [s, f(byLabel.get(s)!)]));
  const weeks = (s: string | null) => Number(String(s || '').match(/\d+/)?.[0] || 0);
  return {
    suppliers, lines,
    terms: {
      lead_time: { requested: '6 weeks', values: term((q) => v(q.lead_time, !q.lead_time ? 'missing' : weeks(q.lead_time) <= 6 ? 'match' : 'differs')) },
      installation: { applicable: true, requested: 'Included, with timeline', values: term((q) => q.installation_included && q.installation_timeline ? v(`Included — ${q.installation_scope}; ${q.installation_timeline} on site`, 'match') : q.installation_included ? v('Included', 'missing', 'timeline not stated') : v(null, 'missing')) },
      warranty: { applicable: true, requested: '2 years, materials and workmanship', values: term((q) => !q.warranty ? v(null, 'missing') : !q.warranty_coverage ? v(q.warranty, 'missing', 'coverage not stated') : v(`${q.warranty} — ${q.warranty_coverage}`, weeks(q.warranty) >= 2 && /materials/i.test(q.warranty_coverage) ? 'match' : 'differs')) },
    },
  };
}

/** The reasoned Arabic, MOCKED: what reasoned_governance.arabicOf hands back once a model has answered — one
 * Arabic line per source text. Tests never call a model; they prove the page prints what reasoning returns. */
export function mockArabic(texts: string[]): Record<string, string> {
  return Object.fromEntries(texts.map((t, i) => [t, `ترجمة السطر ${i + 1}`]));
}
/** Build a document the way nativeArabic does, with the mocked translation standing in for the model. */
export function reasoned<T extends { untranslated: string[] }>(build: (arTexts: Record<string, string>) => T): T {
  const first = build({});
  return first.untranslated.length ? build(mockArabic(first.untranslated)) : first;
}
