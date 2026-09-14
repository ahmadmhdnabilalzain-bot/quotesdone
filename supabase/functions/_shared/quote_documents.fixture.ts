// quote_documents.fixture.ts — one HVAC request with seven quotes, all ZZ DEMO.
//
// Used by quote_documents.test.ts and by the sample renderer, so the documents the tests assert on
// are the documents a person looks at. Every name is "ZZ DEMO …", every email @example.invalid and
// every number +971 50 000 00xx: none of it can reach a real person, and none of it is a row in any
// database. The supplier identities are here ON PURPOSE — the test proves they never reach a page.
import { supplierLabel } from './quote_documents.ts';
import type { Labelled } from '../quote_compare/deterministic.ts';

export const INQUIRY = {
  id: 'zzd3m0aa-7c1e-4f00-9a00-000000000001',
  category: 'hvac',
  summary: 'Supply and install ducted split AC for a 3-bedroom villa in Al Barsha (approx. 24 TR total), including copper piping, drain lines and thermostats.',
  emirate: 'Dubai',
};

export type FixtureQuote = {
  id: string; status: string; quote_amount: number | null; lead_time: string | null; validity: string | null; warranty: string | null;
  payment_terms: string | null; scope: string | null; conditions: string | null; exclusions: string | null; notes: string | null;
  supplier: { company_name: string; email: string; phone: string; website: string };
  items: { desc: string; qty: string; unit: string }[];
  completeness: { score: number | null; passed: boolean | null; missing_mandatory: number | null };
};

const sup = (n: number, name: string) => ({ company_name: `ZZ DEMO ${name} LLC`, email: `sales${n}@zzdemo-${n}.example.invalid`, phone: `+971 50 000 00${String(n).padStart(2, '0')}`, website: `www.zzdemo-${n}.example.invalid` });
const items = (brand: string) => [
  { desc: `${brand} ducted split unit 5 TR, R410A, inverter`, qty: '4', unit: 'Nos' },
  { desc: `${brand} ducted split unit 2 TR, R410A, inverter`, qty: '2', unit: 'Nos' },
  { desc: 'Copper piping, insulated, per ASHRAE sizing', qty: '120', unit: 'LM' },
  { desc: 'GI ductwork with 25mm insulation', qty: '85', unit: 'sqm' },
  { desc: 'Programmable wall thermostat', qty: '6', unit: 'Nos' },
  { desc: 'Testing and commissioning', qty: '1', unit: 'Lot' },
];

// Deliberately NOT in price order: the letters come from sorting, as they do in production.
export const QUOTES: FixtureQuote[] = [
  { id: 'q-4', status: 'submitted', quote_amount: 96500, lead_time: '3 weeks', validity: '30 days', warranty: '2 years', payment_terms: '40% advance, 60% on completion', scope: 'Full supply, installation, testing and commissioning.', conditions: 'Site access 8am-6pm.', exclusions: 'False ceiling works and electrical isolators.', notes: null, supplier: sup(4, 'Arctic Breeze'), items: items('Daikin'), completeness: { score: 90, passed: true, missing_mandatory: 0 } },
  { id: 'q-1', status: 'submitted', quote_amount: 78900, lead_time: '2 weeks', validity: '30 days', warranty: '12 months', payment_terms: '50% advance, 50% on completion', scope: 'Supply and install as per BOQ.', conditions: null, exclusions: 'Civil works, core cutting.', notes: 'Price includes delivery to site. For queries call ZZ DEMO Cool Air on +971 50 000 0001 or sales1@zzdemo-1.example.invalid', supplier: sup(1, 'Cool Air'), items: items('Gree'), completeness: { score: 86, passed: true, missing_mandatory: 0 } },
  { id: 'q-7', status: 'submitted', quote_amount: null, lead_time: null, validity: null, warranty: null, payment_terms: null, scope: 'Rate on request after site visit.', conditions: null, exclusions: null, notes: null, supplier: sup(7, 'Frost Line'), items: [], completeness: { score: 22, passed: false, missing_mandatory: 5 } },
  { id: 'q-2', status: 'submitted', quote_amount: 84250, lead_time: '10-14 days', validity: '15 days', warranty: '18 months', payment_terms: '30% advance, 70% on delivery', scope: 'Supply, install, test.', conditions: 'Price valid for listed quantities only.', exclusions: 'Scaffolding above 4m.', notes: null, supplier: sup(2, 'Polar Tech'), items: items('Midea'), completeness: { score: 78, passed: true, missing_mandatory: 1 } },
  { id: 'q-5', status: 'submitted', quote_amount: 101200, lead_time: '4 weeks', validity: '45 days', warranty: '3 years', payment_terms: '100% advance', scope: 'Turnkey installation.', conditions: null, exclusions: null, notes: null, supplier: sup(5, 'Chill Masters'), items: items('Mitsubishi Electric'), completeness: { score: 88, passed: true, missing_mandatory: 0 } },
  { id: 'q-3', status: 'submitted', quote_amount: 88000, lead_time: '3 weeks', validity: '30 days', warranty: '12 months', payment_terms: 'LC at sight', scope: 'Supply and installation.', conditions: null, exclusions: 'Drain pumps.', notes: null, supplier: sup(3, 'Desert Cooling'), items: items('Carrier'), completeness: { score: 64, passed: true, missing_mandatory: 2 } },
  { id: 'q-6', status: 'submitted', quote_amount: 112000, lead_time: '6 weeks', validity: '30 days', warranty: '5 years', payment_terms: '20% advance, 80% on handover', scope: 'Premium VRF alternative offered as option.', conditions: null, exclusions: null, notes: null, supplier: sup(6, 'Oasis HVAC'), items: items('LG'), completeness: { score: 92, passed: true, missing_mandatory: 0 } },
  // A draft is not a quote the customer has: it must take no letter and appear nowhere.
  { id: 'q-draft', status: 'draft', quote_amount: 50000, lead_time: null, validity: null, warranty: null, payment_terms: null, scope: null, conditions: null, exclusions: null, notes: null, supplier: sup(9, 'Unsent Draft'), items: [], completeness: { score: null, passed: null, missing_mandatory: null } },
];

/** The live quotes in the order production labels them: non-draft, ascending price, no price last. */
export function liveQuotes(): FixtureQuote[] {
  return QUOTES.filter((q) => q.status !== 'draft').sort((a, b) => (a.quote_amount ?? Number.POSITIVE_INFINITY) - (b.quote_amount ?? Number.POSITIVE_INFINITY));
}
/** What quote_compare builds before ranking — the same shape, the same labels. */
export function labelled(): Array<Labelled & { quote_id: string }> {
  return liveQuotes().map((q, i) => ({
    quote_id: q.id, label: 'Supplier ' + supplierLabel(i), price: q.quote_amount, lead_time: q.lead_time, validity: q.validity,
    warranty: q.warranty, payment_terms: q.payment_terms, exclusions: q.exclusions, itemised: q.items.length > 0, expired: false,
    source: 'form', completeness: q.completeness,
  }));
}
/** Every supplier identity in the fixture: the strings that must never appear on a page. */
export function identities(): string[] {
  return QUOTES.flatMap((q) => [q.supplier.company_name, q.supplier.email, q.supplier.phone, q.supplier.website]);
}
