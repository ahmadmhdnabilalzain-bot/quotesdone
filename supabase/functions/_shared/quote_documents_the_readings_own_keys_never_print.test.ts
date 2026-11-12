// THE READING'S OWN KEYS NEVER PRINT ON THE CUSTOMER'S QUOTATION (sales_engineer, 12 Nov 2026; final audit customer_journey
// M4, fix group Q6, ledger 1642). The standardised quotation of the audit's villa HVAC quote 1 printed
// "na:brand: GI ductwork · na:model: … · names:ducting: …": the keys reasoning writes on a line for the hold gate
// (line_specs/assess.ts READ, all starting with '_') were rendered as specs. They are internal; the customer reads only the
// supplier's own specs. ZZ DEMO data only.
//   deno test --no-lock --node-modules-dir=none supabase/functions/_shared/quote_documents_the_readings_own_keys_never_print.test.ts
import { assert, assertStringIncludes } from 'jsr:@std/assert@1';
import { quoteDocument, type Item } from './quote_documents.ts';
import { READ } from './line_specs/assess.ts';
import * as F from './quote_documents.fixture.ts';

const INQ = { id: 'zzd3m0dd-1112-4f00-9a00-000000001112', rfq_no: 'ZZ1112', category: 'hvac', summary: 'ZZ DEMO: villa HVAC, six ducted units.', emirate: 'Dubai' };
const ITEMS: Item[] = [
  { desc: 'GI ductwork with 25 mm thermal insulation, to SMACNA', qty: '160', unit: 'm2', unit_price: 115, amount: 18400,
    specs: { [READ.na('brand')]: 'GI ductwork', [READ.na('model')]: 'GI ductwork', [READ.names('ducting')]: 'GI ductwork', insulation: '25 mm' } },
  { desc: 'Testing, commissioning and air balancing', qty: '1', unit: 'lot', unit_price: 4500, amount: 4500, specs: { [READ.notMaterial]: 'Testing, commissioning' } },
];
const QUOTE = { id: 'zz-q-1112', quote_amount: 22900, price_ex_vat: 22900, vat_treatment: 'exclusive', vat_amount: 1145, lead_time: '4 weeks', validity: '30 days',
  warranty: '2 years', payment_terms: '30% advance', scope: 'Supply and install.', conditions: null, exclusions: 'Civil works.', notes: null };

for (const lang of ['en', 'ar'] as const) {
  Deno.test(`${lang}: the hold gate's reading keys are not printed; the supplier's own spec is`, () => {
    const body = JSON.stringify(F.reasoned((arTexts) => quoteDocument({ quote: QUOTE, inquiry: INQ, items: ITEMS, letter: 'A', lang, ...(lang === 'ar' ? { date_ar: '12 نوفمبر 2026' } : { date: '12 November 2026' }), arTexts, revealRate: 0.03 })).body);
    for (const leak of ['na:brand', 'na:model', 'names:ducting', 'not material', 'Not material', '_na', '_names']) assert(!body.includes(leak), `${leak} printed on the customer's quotation`);
    if (lang === 'en') assertStringIncludes(body, 'Insulation: 25 mm');
  });
}
