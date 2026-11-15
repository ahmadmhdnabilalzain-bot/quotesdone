// request_fit.journey_a.fixture.ts — JOURNEY A of 15 Nov 2026 (run 8288bec3), as the platform stored it. ZZ DEMO data.
//
// The request: what the intake recorded, as the RFQ the suppliers received printed it ("What the customer asked for" and
// "The brief", inquiry_as_the_supplier_receives_it.pdf), and the customer's own typed words (raw_input). The quotations:
// the three suppliers of scripts/e2e/journey_proof/scenarios.mjs SCENARIOS.A (branch customer_support-a-journey-is-played-
// by-people-not-a-script), with the lines, rates, terms and line specs their own PDFs and the customer's quote PDFs show
// (dossier pages 44-61). Polar Tech's stored price is the VAT-inclusive AED 18,854.85 read as ex-VAT, exactly as the live
// comparison carried it (the reading is the accountant's fix, on another branch); this fixture keeps what was stored.
//
// journeyA(lang) runs the same pieces quote_compare/index.ts runs on these rows (labels, the technical comparison, the
// review notes, the generaliser, request_fit, the rules ranking, the roster, the last gate), so the report built from it
// is the report the customer would download now.
import { labelQuotes } from './quote_labels.ts';
import { requirementsOf } from './line_specs/assess.ts';
import { rendererView, technicalComparison } from './line_specs/compare.ts';
import { tradeOfCategory } from './line_specs/model.ts';
import { ctxOfQuote, generaliseDeep, generaliseLine, generaliseQuoteTerms, mergeCtx } from './quote_generalise.ts';
import { requestOf, reviewNotes } from './quote_review_notes.ts';
import { annotateTechnical, enforceFit, fitQuote, fitView, requestRequirements, siteVisitAsked, type QuoteFit } from './request_fit.ts';
import { deterministicCompare, rosterOf } from '../quote_compare/deterministic.ts';

export const NOW = new Date('2026-11-15T14:19:33.651Z');

const said = [
  'Hello. I need the air conditioning in my villa sorted out. It is a villa in Dubai. Four of the wall-mounted split units are old and no longer cool, I want them replaced with new ones, and the three ducted units serviced.',
  'For the three ducted units: full cleaning of coils and filters, drain line cleaning and a gas pressure check, one visit.',
  'Reuse the existing copper pipes if they are in good condition, otherwise allow up to 5 metres of new insulated pipe per unit.',
  'Inverter units, please.',
  'Two bedrooms have 1.5 ton units and the majlis and living room have 2 ton units, so two of 1.5 TR and two of 2.0 TR. The three ducted units are 3 TR each.',
  'The power points and isolators are already there; you only connect to them.',
  'Supply and installation of the four new split units, plus the service of the three ducted units.',
  'Daikin, Mitsubishi Electric or Gree, inverter, R32 or R410A.',
  'Yes, remove the old split units and take them away.',
  'We need it done by 15 December 2026.',
  'Indoor units on the ground and first floor; the outdoor units are on the roof, reached by a fixed ladder.',
  'At least 2 years on the installation and 5 years on the compressors.',
];

export const INQUIRY_A = {
  id: 'zzd3m0aa-8288-4bec-a3a0-000000166739', rfq_no: 166739, category: 'hvac', emirate: 'Dubai',
  summary: 'Replace 4 old wall split ACs with new inverter units (supply, install, remove old) and service 3 ducted units in a villa in Dubai',
  raw_input: said.join('\n'),
  boq: null,
  spec: {
    scope: 'At least 2 years on the installation and 5 years on the compressors.',
    location: 'Dubai',
    quantity: '4 wall splits (replace), 3 ducted (service)',
    site_visit: 'Site visit needed before a final price. A site visit is needed for replacements and ducted systems to check pipe runs, outdoor unit positions, drainage and the electrical supply.',
    system_type: 'The power points and isolators are already there; you only connect to them.',
    spec_warranty: 'At least 2 years on installation, 5 years on compressors',
    new_or_replace: 'Yes, remove the old split units and take them away.',
    spec_unit_type: 'Wall split (4, replacement); ducted (3, service only)',
    application_area: 'Daikin, Mitsubishi Electric or Gree, inverter, R32 or R410A.',
    spec_refrigerant: 'R32 or R410A',
    split_unit_count: '4',
    ducted_unit_count: '3',
    spec_cooling_capacity: 'Wall splits: 2 x 1.5 TR (bedrooms), 2 x 2.0 TR (majlis, living room); ducted: 3 x 3 TR (service only)',
    spec_outdoor_unit_mounting: 'Outdoor units on the roof, reached by a fixed ladder',
    spec_inverter_or_fixed_speed: 'Inverter',
    spec_number_of_units_per_type: '4 wall splits (replace), 3 ducted (service)',
    spec_brand_preference_or_equivalent_tier: 'Daikin, Mitsubishi Electric or Gree',
    spec_room_use_and_area_or_heat_load_calc: 'Rooms: 2 bedrooms, majlis, living room; areas not yet given',
    spec_copper_pipe_length_included_per_unit: 'Reuse existing copper if in good condition, otherwise up to 5 m new insulated pipe per unit',
    spec_electrical_isolator_and_cabling_scope: 'Existing power points and isolators in place; supplier only connects',
    spec_old_unit_removal_and_refrigerant_recover: 'Remove old split units and take them away',
    customer_requirements: {
      version: 2, recorded_by: 'sales_engineer', category: 'hvac', recorded_at: '2026-11-15T14:12:06.000Z',
      installation: { required: 'yes' },
      warranty: { required: 'yes', min_months: 24 },
      materials: [
        { component: 'brand', label_en: 'Air-conditioning brand', label_ar: 'ماركة المكيفات', choice: 'premium', choice_en: 'Premium brands', choice_ar: 'ماركات فاخرة', note: null },
        { component: 'ducting', label_en: 'Ducting', label_ar: 'مجاري الهواء', choice: 'gi', choice_en: 'Galvanised steel (GI)', choice_ar: 'حديد مجلفن', note: null },
      ],
      required_by: { flexible: false, date: '2026-12-15', text: 'By 2026-12-15' },
      display: { en: [], ar: [] },
    },
  },
};

// The supplier portal's line specs (scenarios.mjs hold / holdBy): every line naming a split or a unit was given the brand,
// model, refrigerant and ESMA rating — the removal and service lines too, which is why the live report printed a brand and a
// capacity "1" on them.
const S = (brand: string, model: string, extra: Record<string, string> = {}) => ({ brand, model: `${model} wall split inverter`, efficiency: 'ESMA 5-star', refrigerant: 'R32', ...extra });
type Line = { line_no: number; description: string; specification: string | null; brand: string | null; model: string | null; qty: number; unit: string; unit_price: number; amount: number; country_of_origin: string | null; notes: null; spec: Record<string, string> | null; spec_source: Record<string, string> | null };
const L = (line_no: number, description: string, specification: string | null, qty: number, unit: string, rate: number, spec: Record<string, string> | null): Line =>
  ({ line_no, description, specification, brand: spec?.brand ?? null, model: spec?.model ?? null, qty, unit, unit_price: rate, amount: Math.round(qty * rate * 100) / 100, country_of_origin: null, notes: null, spec, spec_source: spec ? Object.fromEntries(Object.keys(spec).map((k) => [k, 'supplier_portal'])) : null });

export const QUOTES_A = [
  { id: 'zzq-8288bec3-a2', supplier_id: 9002, supplier_name: 'ZZ DEMO Arabian Air Systems hvac 8288bec3', option_no: 1, quote_amount: 12279, price_ex_vat: 12279, vat_treatment: 'exclusive', vat_amount: 613.95, gross_amount: null, discount_amount: null,
    lead_time: '5 days from LPO', validity: '30 days', warranty: '1 year on the installation', payment_terms: '50% advance, 50% on completion',
    scope: 'Supply and installation of four inverter wall split AC units (two 1.5 TR and two 2.0 TR); removal and disposal of four existing wall split units; 20 m of insulated copper piping where existing piping cannot be reused; service of three 3 TR ducted units; testing and commissioning.',
    conditions: 'Prices in AED, excluding VAT; VAT 5% shown separately.', exclusions: 'Electrical works.', notes: null, status: 'submitted', source: 'upload', expires_at: '2026-12-15T00:00:00Z',
    terms_spec: { delivery: { value: '5 days from LPO', source: 'supplier_portal' }, installation: { included: 'yes', detail: 'Included as quoted', source: 'supplier_portal' }, warranty: { period: '1 year', coverage: '1 year on the installation', source: 'supplier_portal' } },
    quality: { score: 92, pass: true, category: { mandatory_missing: 0 } },
    items: [
      L(1, 'Removal and disposal of existing wall split AC units; disconnect, recover refrigerant, remove and dispose.', null, 4, 'nos', 117, S('Gree', 'Gree', { capacity_tr: '1' })),
      L(2, 'Supply and installation of 1.5 TR wall split inverter AC unit; Gree, R32 refrigerant, made in China.', 'Gree wall split inverter, R32, made in China', 2, 'nos', 2067, S('Gree', 'Gree', { capacity_tr: '1.5' })),
      L(3, 'Supply and installation of 2.0 TR wall split inverter AC unit; Gree, R32 refrigerant, made in China.', 'Gree wall split inverter, R32, made in China', 2, 'nos', 2418, S('Gree', 'Gree', { capacity_tr: '2' })),
      L(4, 'Insulated copper piping where existing piping cannot be reused; ASTM B280 copper, 19 mm insulation.', 'ASTM B280 copper, 19 mm insulation', 20, 'm', 66, S('Gree', 'Gree', { capacity_tr: '1' })),
      L(5, 'Service of 3 TR ducted AC units, including coils, filters, drain and gas check; chemical coil cleaning, filter service, drain flushing and pressure check.', 'Chemical coil cleaning, filters, drain flush, pressure check', 3, 'nos', 351, S('Gree', 'Gree', { capacity_tr: '3' })),
      L(6, 'Testing and commissioning, including pressure test, vacuum and performance readings.', 'Pressure test, vacuum, performance readings', 1, 'lot', 468, S('Gree', 'Gree', { capacity_tr: '1' })),
    ] },
  { id: 'zzq-8288bec3-a1', supplier_id: 9001, supplier_name: 'ZZ DEMO Cool Breeze HVAC hvac 8288bec3', option_no: 1, quote_amount: 15750, price_ex_vat: 15750, vat_treatment: 'exclusive', vat_amount: 787.5, gross_amount: null, discount_amount: null,
    lead_time: '10 days from LPO', validity: '30 days', warranty: '5 years on compressors; 2 years on the installation', payment_terms: '50% advance, 50% on completion',
    scope: 'Supply and installation of four inverter wall split AC units (two 1.5 TR and two 2.0 TR); removal and disposal of four existing wall split units; 20 m of insulated copper piping where existing piping cannot be reused; service of three 3 TR ducted units; testing and commissioning.',
    conditions: 'Prices in AED, excluding VAT; VAT 5% shown separately.', exclusions: 'Civil works, electrical works.', notes: null, status: 'submitted', source: 'upload', expires_at: '2026-12-15T00:00:00Z',
    terms_spec: { delivery: { value: '10 days from LPO', source: 'supplier_portal' }, installation: { included: 'yes', detail: 'Supply and installation of four inverter wall split AC units (two 1.5 TR and two 2.0 TR); removal and disposal of four existing wall split units', source: 'supplier_portal' }, warranty: { period: '5 years', coverage: '5 years on compressors; 2 years on the installation', source: 'supplier_portal' } },
    quality: { score: 92, pass: true, category: { mandatory_missing: 0 } },
    items: [
      L(1, 'Removal and disposal of existing wall split units; disconnect, recover refrigerant, remove and dispose.', null, 4, 'nos', 150, null),
      L(2, 'Supply and installation of Daikin wall split inverter, 1.5 TR, R32; made in Thailand.', 'Daikin wall split inverter, R32, made in Thailand', 2, 'nos', 2650, S('Daikin', 'Daikin', { capacity_tr: '1.5 TR' })),
      L(3, 'Supply and installation of Daikin wall split inverter, 2.0 TR, R32; made in Thailand.', 'Daikin wall split inverter, R32, made in Thailand', 2, 'nos', 3100, S('Daikin', 'Daikin', { capacity_tr: '2.0 TR' })),
      L(4, 'Insulated copper piping where existing piping cannot be reused; ASTM B280 copper, 19 mm insulation.', 'ASTM B280 copper, 19 mm insulation', 20, 'm', 85, { brand: 'Daikin', model: 'Daikin wall split inverter', efficiency: 'ESMA 5-star' }),
      L(5, 'Service of ducted unit, 3 TR: coils, filters, drain and gas check; chemical coil cleaning, filter service, drain flush and pressure check.', 'Chemical coil cleaning, filters, drain flush, pressure check', 3, 'nos', 450, S('Daikin', 'Daikin', { capacity_tr: '3 TR' })),
      L(6, 'Testing and commissioning; pressure test, vacuum and performance readings.', null, 1, 'lot', 600, null),
    ] },
  { id: 'zzq-8288bec3-a3', supplier_id: 9003, supplier_name: 'ZZ DEMO Polar Tech Contracting hvac 8288bec3', option_no: 1, quote_amount: 18854.85, price_ex_vat: 18854.85, vat_treatment: 'exclusive', vat_amount: null, gross_amount: null, discount_amount: null,
    lead_time: '14 days from LPO', validity: '30 days', warranty: '5 years on compressors, 2 years on the installation', payment_terms: '30% advance, 70% on completion',
    scope: 'Supply and installation of four inverter wall split AC units; removal and disposal of four existing units; copper piping; service of three ducted units; testing and commissioning.',
    conditions: null, exclusions: 'Civil works.', notes: null, status: 'submitted', source: 'upload', expires_at: '2026-12-15T00:00:00Z',
    terms_spec: { delivery: { value: '14 days from LPO', source: 'supplier_portal' }, installation: { included: 'yes', detail: 'Included as quoted', source: 'supplier_portal' }, warranty: { period: '5 years', coverage: '5 years on compressors, 2 years on the installation', source: 'supplier_portal' } },
    quality: { score: 92, pass: true, category: { mandatory_missing: 0 } },
    items: [
      L(1, 'Removal and disposal of existing wall split units', 'Disconnect, recover refrigerant, remove and dispose', 4, 'nos', 171, S('Mitsubishi Electric', 'Mitsubishi Electric', { capacity_tr: '1' })),
      L(2, 'Wall split unit 1.5 TR, inverter, supply and install', 'Mitsubishi Electric wall split inverter, R32, made in Japan', 2, 'nos', 3021, S('Mitsubishi Electric', 'Mitsubishi Electric', { capacity_tr: '1.5' })),
      L(3, 'Wall split unit 2.0 TR, inverter, supply and install', 'Mitsubishi Electric wall split inverter, R32, made in Japan', 2, 'nos', 3534, S('Mitsubishi Electric', 'Mitsubishi Electric', { capacity_tr: '2' })),
      L(4, 'Insulated copper piping where the existing cannot be reused', 'ASTM B280 copper, 19 mm insulation', 20, 'm', 97, S('Mitsubishi Electric', 'Mitsubishi Electric', { capacity_tr: '1' })),
      L(5, 'Service of ducted unit 3 TR: coils, filters, drain, gas check', 'Chemical coil cleaning, filters, drain flush, pressure check', 3, 'nos', 513, S('Mitsubishi Electric', 'Mitsubishi Electric', { capacity_tr: '3' })),
      L(6, 'Testing and commissioning', 'Pressure test, vacuum, performance readings', 1, 'lot', 684, S('Mitsubishi Electric', 'Mitsubishi Electric', { capacity_tr: '1' })),
    ] },
];
export const SUPPLIER_NAMES = QUOTES_A.map((q) => q.supplier_name).concat(['Arabian Air Systems', 'Cool Breeze HVAC', 'Polar Tech Contracting']);

/** The analysis quote_compare serves for journey A now (the rules path: the live run's model gateway refused the review author). */
// deno-lint-ignore no-explicit-any
export function journeyA(lang: 'en' | 'ar' = 'en'): { analysis: any; fits: Record<string, QuoteFit> } {
  const inq = INQUIRY_A; const qs = QUOTES_A; const nowTs = NOW.getTime();
  const labels = labelQuotes(qs.map((q) => ({ id: q.id, supplier_id: q.supplier_id, option_no: q.option_no })));
  const items = (q: typeof qs[number]) => q.items.map((it) => ({ ...it, line: it.line_no }));
  const technical = technicalComparison({ category: inq.category, request_lines: [], requirements: requirementsOf(inq.spec), on_hold: 0, now: NOW, accepted: [],
    quotes: qs.map((q) => { const lab = labels.get(q.id)!; return { quote_id: q.id, label_en: lab.en, label_ar: lab.ar, supplier_letter: lab.letter, option_no: lab.option_no,
      lines: q.items.map((it) => ({ ...it })) as never, terms: { lead_time: q.lead_time, warranty: q.warranty, scope: q.scope, exclusions: q.exclusions, conditions: q.conditions, notes: q.notes, terms_spec: q.terms_spec as never, price_ex_vat: q.price_ex_vat } }; }) });
  const request = requestOf(inq, NOW);
  const ctxBy = Object.fromEntries(qs.map((q) => [q.id, ctxOfQuote(items(q), [q.supplier_name])]));
  const notesBy = Object.fromEntries(qs.map((q) => [q.id, reviewNotes({ request, quote: q, lines: q.items, supplierNames: [q.supplier_name] })]));
  const allCtx = mergeCtx(...Object.values(ctxBy));
  const requirements = requestRequirements(inq);
  const trade = tradeOfCategory(inq.category); const siteVisit = siteVisitAsked(inq.spec);
  const fitById = Object.fromEntries(qs.map((q) => [q.id, fitQuote(requirements, { quote: { ...q, lead_time_shown: generaliseQuoteTerms({ lead_time: q.lead_time }, ctxBy[q.id]).lead_time ?? null }, lines: q.items, now: NOW, trade, site_visit: siteVisit })]));
  const fits: Record<string, QuoteFit> = Object.fromEntries(qs.map((q) => [labels.get(q.id)!.en, fitById[q.id]]));
  const labelled = qs.map((q) => {
    const it = items(q).map((x) => generaliseLine(x, ctxBy[q.id]));
    const gt = generaliseQuoteTerms({ lead_time: q.lead_time, validity: q.validity, warranty: q.warranty, payment_terms: q.payment_terms, scope: q.scope, conditions: q.conditions, exclusions: q.exclusions, notes: q.notes }, ctxBy[q.id]);
    return { quote_id: q.id, label: labels.get(q.id)!.en, price: q.price_ex_vat, gross_amount: q.gross_amount, discount_amount: q.discount_amount, vat_treatment: q.vat_treatment, vat_amount: q.vat_amount, ...gt,
      items: it, review_notes: notesBy[q.id], fit: fitById[q.id], itemised: it.length > 0, expired: new Date(q.expires_at).getTime() < nowTs, source: q.source,
      completeness: { score: q.quality.score, passed: q.quality.pass, missing_mandatory: q.quality.category.mandatory_missing } };
  });
  // deno-lint-ignore no-explicit-any
  const a: any = deterministicCompare(labelled as never, lang);
  // withRoster, as index.ts does it
  a.technical = annotateTechnical(rendererView(technical, lang), requirements, fits, technical.trade, lang);
  a.technical_detail = technical; a.on_hold = 0;
  a.request_fit = fitView(requirements, qs.map((q) => ({ label: labels.get(q.id)!.en, quote_id: q.id, fit: fitById[q.id] })));
  enforceFit(a, fits, lang, { rules: deterministicCompare(labelled as never, lang), prices: Object.fromEntries(labelled.map((l) => [l.label, l.price])) });
  a.all_quotes = rosterOf(labelled as never, a.top3, new Set());
  a.total_quotes = qs.length;
  const g = generaliseDeep(a, allCtx);
  g.review_notes = qs.map((q) => ({ quote_id: q.id, label: labels.get(q.id)!.en, notes: notesBy[q.id].map((n) => ({ code: n.code, severity: n.severity, text: lang === 'ar' ? n.ar : n.en })) }));
  return { analysis: g, fits };
}
