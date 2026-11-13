// a_careless_model_reading_reaches_no_customer_document.test.ts — THE CODE BACKSTOP OF THE MODEL PATH, with a planted
// identity (13 Nov 2026, sales_engineer; anonymity audit REPORT_C L8, founder ledger 1683).
//
// WHY. The upload door is model-first since PR #1981: quote_extract's model reads the supplier's quotation and code only
// checks. The permanent planted-identity corpus (scripts/e2e/identity_leak_pipeline.ts) drove only the code reader the
// chat door uses, so nothing held the model path when the model reads carelessly. The auditor's harness (C1, 13 Nov) put
// a careless reading through the real chain and the customer's quotation PDF carried "Contact Rashid Khan", "from our Al
// Quoz warehouse", "FT-Q-", "Falcon premium paint" (with a ZZ DEMO name), and a cover warranty of 10 years where the
// supplier gave 5 ("5 years warranty by Falcon Trading LLC" was saved as "5 █").
//
// WHAT RUNS, each the module production runs (no network, no database):
//   quote_extract  modelAnonymiser + proposalFromModel + checkReading (model_reading.ts — index.ts calls the same)
//   submit_quote   scrubIdentity per term, scrubLine + deriveLineFields per line (supplier_api/actions/quotes.ts)
//   customer door  itemsOfRows, completenessOf, ctxOfQuote, generaliseLine, generaliseQuoteTerms, quoteDocument(maskNames)
//                  (customer_api/lib/pdfs.ts buildQuotePdf, unrevealed) and the portal's generaliseQuoteTerms
//                  (inquiry_lifecycle.ts my_inquiries); the comparison CSV's compareTable with the PDF's maskNames.
// The careless reading copies the document's words into every text field and reports nothing masked: the worst a model
// can do without inventing. Every planted string must be gone from what the customer is handed, and the warranty the
// supplier gave must survive.
// deno test --no-lock supabase/functions/quote_extract/a_careless_model_reading_reaches_no_customer_document.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { checkReading, modelAnonymiser, proposalFromModel } from './model_reading.ts';
import { scrubIdentity, scrubLine } from '../supplier_api/identity_scrub.ts';
import { deriveLineFields, deriveTermsFromScope } from '../_shared/line_specs/derive.ts';
import { compareTable, completenessOf, itemsOfRows, quoteDocument } from '../_shared/quote_documents.ts';
import { ctxOfQuote, generaliseLine, generaliseQuoteTerms } from '../_shared/quote_generalise.ts';

const LINES = [
  ['Falcon premium paint - interior emulsion, 2 coats, by ZZ DEMO Falcon Trading LLC', '450', 'm2', '18.00', '8,100.00', 'UAE'],
  ['Jotun Fenomastic Pure Colours Emulsion Matt (Brand: Jotun, Model: FPC-2026), 3 coats', '300', 'm2', '24.00', '7,200.00', 'UAE (Jotun factory, Jebel Ali)'],
  ['Waterproofing membrane Sika SikaProof A-08, from our Al Quoz warehouse, Plot 364-1172', '120', 'm2', '65.00', '7,800.00', 'Switzerland'],
  ['Site supervision by Eng. Rashid Khan (call 04 345 6789)', '1', 'lot (Falcon crew)', '1,500.00', '1,500.00', ''],
];
const CARELESS = {
  is_quotation: true, not_a_quotation_reason: '', request_reference: 'RFQ-990457', currency: 'AED', total: 25830, subtotal: 24600, vat_amount: 1230, vat_treatment: 'exclusive', options: [],
  line_items: LINES.map((l) => ({ description: l[0], qty: l[1], quantity: Number(l[1]), unit: l[2], unit_price: Number(l[3].replace(/,/g, '')), amount: Number(l[4].replace(/,/g, '')), country_of_origin: l[5] })),
  lead_time: '10 working days from advance (FT-Q-2026-0457)', validity: '30 days',
  payment_terms: '50% advance by cheque in favour of Falcon Trading L.L.C., IBAN AE07 0331 2345 6789 0123 456 (Emirates NBD).',
  warranty: '5 years warranty by Falcon Trading LLC on workmanship; Jotun manufacturer warranty 10 years.',
  scope: 'Quotation No. FT-Q-2026-0457. ZZ DEMO Falcon Trading LLC will supply and apply Falcon premium paint and Jotun Fenomastic, waterproofing by Sika. Falcon is your partner since 2009.',
  conditions: 'فالكون للتجارة ش.ذ.م.م - هاتف ٠٤ ٣٤٥ ٦٧٨٩ - الدفع بشيك باسم شركة فالكون للتجارة. Prepared by: Rashid Khan, Sales Manager. Signed and stamped.',
  exclusions: 'Scaffolding above 4m. Contact Rashid Khan for details.',
  notes: 'Visit our showroom in Al Quoz. Call Rashid on 050 123 4567 or zero five zero one two three four five six seven, WhatsApp wa.me/971501234567, Instagram @falcontrading.uae, '
    + 'or scan the QR code below. Mob ٠٥٠١٢٣٤٥٦٧. Licence 778899. TRN 100123456700003. Showroom 12, Al Quoz Industrial Area 3, Dubai. Falcontrading dot com. Regards, Rashid',
  description_anonymized: 'Falcon Trading interior painting quotation FT-Q-2026-0457', masked_terms: [], confidence: 'high',
};
// What the customer must never read before the reveal. Countries of origin ("UAE", "Switzerland"), quantities, rates and
// the emirate may show.
const PLANTED = ['Falcon', 'فالكون', 'Jotun', 'Fenomastic', 'FPC-2026', 'SikaProof', 'A-08', 'Rashid', 'Khan', 'Quoz', 'Showroom 12', 'Plot 364', '364-1172', 'FT-Q', '2026-0457', '050 123',
  '04 345', '345 6789', '٠٥٠١٢٣٤٥٦٧', '٣٤٥', 'zero five zero', 'wa.me', '971501234567', '@falcontrading', 'falcontrading', '100123456700003', '778899', 'AE07', 'Emirates NBD',
  'Jebel Ali', 'stamped', 'Sales Manager'];
const INQ = { id: 'zzdemo-careless-inq', rfq_no: 990457, category: 'painting', emirate: 'Dubai', summary: 'Interior painting of a villa and waterproofing of one wet area, Dubai.', spec: null, boq: null };

function chain(company: string) {
  const ai = structuredClone(CARELESS) as typeof CARELESS & { masked_terms: string[] };
  const read = checkReading(proposalFromModel(ai, modelAnonymiser({ supplierNames: [company] }, ai.masked_terms)), '', null);
  // deno-lint-ignore no-explicit-any
  const pr = read as any;
  const hits: string[] = [];
  const clip = (v: unknown, n: number) => (v == null || String(v).trim() === '') ? null : String(v).slice(0, n);
  const scrub = (v: unknown, n: number) => scrubIdentity(clip(v, n), company, hits);
  const fromScope = deriveTermsFromScope(pr.scope || pr.description_anonymized, pr.exclusions);
  const q = { id: 'zzdemo-careless-q1', inquiry_id: INQ.id, status: 'submitted', quote_amount: pr.amount, price_ex_vat: pr.price_ex_vat ?? pr.amount, vat_treatment: pr.vat_treatment, vat_amount: pr.vat_amount,
    notes: scrub(pr.notes, 1000), scope: scrub(pr.scope || pr.description_anonymized, 2000), conditions: scrub(pr.conditions, 2000), exclusions: scrub(pr.exclusions || fromScope.exclusions || '', 2000),
    lead_time: scrub(pr.lead_time, 200), validity: scrub(pr.validity, 200), payment_terms: scrub(pr.payment_terms, 400), warranty: scrub(pr.warranty, 200), source: 'upload' };
  // deno-lint-ignore no-explicit-any
  const rows = (pr.line_items || []).map((raw: any, i: number) => { const it = scrubLine(raw, company, hits); const dv = deriveLineFields(it);
    return { quote_id: q.id, line_no: i + 1, description: clip(it.description, 300), brand: clip(it.brand || dv.brand, 120), model: clip(it.model || dv.model, 120), specification: clip(it.specification || dv.specification, 800),
      qty: it.quantity ?? null, unit: clip(it.unit, 40), unit_price: it.unit_price ?? null, amount: it.amount ?? null, country_of_origin: clip(it.country_of_origin, 80), notes: clip(it.notes, 300) }; });
  // The customer door, unrevealed (customer_api/lib/pdfs.ts buildQuotePdf).
  const ids = [company, 'rashid@falcontrading.example.invalid', '+971 50 123 4567', '+971 50 123 4567', 'www.falcontrading.example.invalid'];
  let items = itemsOfRows(rows);
  // deno-lint-ignore no-explicit-any
  const done = completenessOf(q as any, items, INQ.category, INQ.spec); items = done.items;
  // deno-lint-ignore no-explicit-any
  const ctx = ctxOfQuote(items.map((it: any) => ({ brand: it.brand, model: it.model, spec: it.specs })), ids);
  // deno-lint-ignore no-explicit-any
  items = items.map((it: any) => generaliseLine(it, ctx));
  const quoteRow = generaliseQuoteTerms({ ...done.quote, scope: q.scope }, ctx);
  // deno-lint-ignore no-explicit-any
  const { body } = quoteDocument({ quote: quoteRow as any, inquiry: INQ as any, items, letter: 'A', lang: 'en', partyName: null, maskNames: ids, requestUrl: 'https://quotesdone.ae/portal', revealRate: 0.03, date: '13 November 2026' });
  const screen = generaliseQuoteTerms({ notes: q.notes, lead_time: q.lead_time, validity: q.validity, payment_terms: q.payment_terms, warranty: q.warranty, scope: q.scope, conditions: q.conditions, exclusions: q.exclusions }, ctxOfQuote(rows, [company]));
  // The comparison CSV, with the names the PDF masks (customer_api/actions/reports.ts compare_csv).
  const analysis = { quotes: [{ label: 'Supplier A', quote_id: q.id, price: 24600, lead_time: q.lead_time, validity: q.validity, warranty: q.warranty, payment_terms: q.payment_terms, exclusions: q.exclusions,
    getting: q.scope, includes: [q.scope], excludes: [q.exclusions], itemised: true }], top3: [], all_quotes: [{ label: 'Supplier A', quote_id: q.id }] };
  const csv = compareTable(analysis, false, {}, ids);
  return { body, screen, csv, rows, q };
}

for (const company of ['Falcon Trading LLC', 'ZZ DEMO Falcon Trading LLC']) {
  Deno.test(`a careless model reading of ${company}'s quotation: nothing planted reaches the customer's document, screen or CSV`, () => {
    const { body, screen, csv } = chain(company);
    const surfaces = { quotation_document: JSON.stringify(body), portal_screen: JSON.stringify(screen), comparison_csv: JSON.stringify(csv) };
    const left: string[] = [];
    for (const [where, text] of Object.entries(surfaces)) for (const p of PLANTED) if (text.toLowerCase().includes(p.toLowerCase())) left.push(`${where}: ${p}`);
    assertEquals(left, []);
  });
}
Deno.test('the warranty the supplier gave (5 years) is the one the customer reads; his name around it is gone', () => {
  const { q, body } = chain('Falcon Trading LLC');
  assert(String(q.warranty).startsWith('5 years warranty by '), String(q.warranty));
  const text = JSON.stringify(body);
  assert(/5 years/.test(text), 'the cover keeps 5 years');
  // The supplier's own five years is the first warranty the document states (the 10 years is the manufacturer's).
  const i5 = text.indexOf('5 years'), i10 = text.indexOf('10 years');
  assert(i10 < 0 || i5 < i10, `5 years must come before the manufacturer's 10: ${text.slice(Math.max(0, i10 - 120), i10 + 20)}`);
});
Deno.test('the unit is text the customer reads: it passes the anonymiser; the country of origin stays a country', () => {
  const { rows } = chain('Falcon Trading LLC');
  // deno-lint-ignore no-explicit-any
  assert(rows.every((r: any) => !/falcon/i.test(String(r.unit))), JSON.stringify(rows.map((r: { unit: unknown }) => r.unit)));
  // deno-lint-ignore no-explicit-any
  assertEquals(rows.map((r: any) => r.country_of_origin).filter(Boolean).slice(0, 1), ['UAE']);
});
