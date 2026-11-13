// A customer's existing quotation reaches suppliers as OUR inquiry: its items, quantities, units and specified makes, and
// nothing of the old supplier (13 Nov 2026, sales_engineer; founder ruling 1683; anonymity audit A, L2).
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/drawing_boq/a_quotation_reaches_suppliers_as_our_inquiry.test.ts
// The fixture is the audit's own ZZ DEMO Falcon Trading quotation (fixtures/zz_demo_customers_existing_quotation_falcon.pdf):
// letterhead, Arabic name, phones, TRN, IBAN, the customer's name and site, a project and a consultant, a priced table, totals,
// payment terms and a signature. The model step is STUBBED twice: the careless reading the auditor wrote
// (A_customer_to_supplier/s1_model_stub.ts, verbatim) and a faithful one. Before this change the careless one reached the
// supplier's BOQ with "Falcon Trading", "Ahmed Saeed", "FT/Q/2026/0412", "FT-SD-04", "AED 95.00/m2, amount 8,170.00",
// "rate 1,180" and "AED 32,816.70".
// deno-lint-ignore-file no-explicit-any
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { linesFromRuns, pdfPages } from '../_shared/pdf_text_positions.ts';
import { readDocument } from '../_shared/doc_read/index.ts';
import { boqFromExtracted } from './boq_from_document.ts';
import { gateDrawingBoq, setIdentityTerms } from '../_shared/drawing_identity_gate.ts';
import { redactBoq, seedTerms } from '../_shared/anonymise.ts';
import { isQuotationReading, looksPriced, priceResidue, pricedKind, quotationGate, quotationProse, quotationTerms, termsToKeep } from './quotation_gate.ts';
import { pricedRoute } from '../customer_api/lib/priced_document.ts';
import { quotationPartyTerms } from './quotation_parties.ts';
import { inboxBoq } from '../supplier_api/identity_scrub.ts';
import { attachedLine, forSource, newInquiryBody, requestSeeds, supplierBrief, supplierField } from '../supplier_api/what_a_supplier_receives.ts';
import { inquiryDocument, type InquiryDocRow } from '../_shared/quote_documents.ts';
import { renderPdf } from '../pdf_native/render.ts';
import { understoodMessage } from '../customer_api/lib/what_was_understood.ts';
import { drawingNoteOf } from '../inquiry_intake/attached_file.ts';

const FIX = new URL('./fixtures/zz_demo_customers_existing_quotation_falcon.pdf', import.meta.url);
const FILE = 'Falcon Trading LLC - Quotation FT-Q-2026-0412 - Omar Haddad Villa 15.pdf';
const CUST = { name: 'ZZ DEMO Omar Haddad', email: 'omar.haddad@zz-mail.example.invalid', phone: '+971550000499', project: 'ZZ DEMO Barsha Garden Villa' };
// What must never reach a supplier: the old supplier, its people and references, its prices and terms, the customer and his site.
const NEVER = ['Falcon', 'فالكون', 'Ahmed', 'Saeed', 'Mansoori', 'FT/Q', 'FT-SD', 'FT-AS', '0412', 'Omar', 'Haddad', 'Villa 15', 'Barsha', 'Mall of the Emirates', 'Quoz', 'Cedar', 'zz-falcon', 'zz-mail',
  '95.00', '8,170', '2,350', '9,400', '1,180', '4,720', '1,960', '5,880', '210.00', '1,260', '48.00', '1,824', '31,254', '1,562', '32,816', 'advance', 'Validity', 'IBAN', 'Cheques'];
// The over-redaction rows: content a supplier needs (items, sizes, makes, quantities, the emirate).
const MUST_CARELESS = ['Porcelain wall tiles 300x600mm', 'RAK Ceramics', 'Wall hung WC with concealed cistern', 'Grohe', 'Wash basin 600mm with pedestal', 'Duravit'];
const MUST_FAITHFUL = [...MUST_CARELESS.slice(1), 'Supply and fix porcelain wall tiles 300x600mm', 'Thermostatic shower mixer', '250mm', 'Hansgrohe', 'Floor drain 150x150', 'ACO', '150mm upstand', 'Sika'];
const hits = (t: string, list: string[]) => list.filter((x) => t.toLowerCase().includes(x.toLowerCase()));

const CARELESS = { document_kind: 'drawing', drawing_type: 'quotation', category: 'plumbing', summary: 'Bathroom sanitary ware and tiling for a villa (Villa 15) quoted by Falcon Trading',
  boq: [
    { section: 'Tiling', description: 'Porcelain wall tiles 300x600mm gloss white (RAK Ceramics)', qty: 86, unit: 'sqm', basis: 'as quoted at AED 95.00/m2, amount 8,170.00', confidence: 'high' },
    { section: 'Sanitary', description: 'Wall hung WC with concealed cistern, as per Falcon standard detail FT-SD-04 (Grohe)', qty: 4, unit: 'nos', basis: 'line 2 of quotation FT/Q/2026/0412', confidence: 'high' },
    { section: 'Sanitary', description: 'Wash basin 600mm with pedestal (Duravit)', qty: 4, unit: 'nos', basis: 'rate 1,180', confidence: 'high' },
  ], keywords: ['tiling', 'sanitary'], assumptions: ['Prices excluded; competitor total was AED 32,816.70 incl. VAT', 'Contact Ahmed Saeed for clarifications'], missing_info: [], confidence: 'medium' };
const B = "as listed in the customer's document";
const FAITHFUL = { document_kind: 'quotation', sufficiency: { verdict: 'not_yet', missing: ['whether the old fittings are removed first', 'supply and install, or supply only'] }, category: 'plumbing',
  summary: 'Supply and installation of bathroom sanitary ware and wall tiling for a villa.', boq: [
    { section: 'Tiling', description: 'Supply and fix porcelain wall tiles 300x600mm, gloss white, to bathrooms (RAK Ceramics)', qty: 86, unit: 'm2', basis: B, confidence: 'high' },
    { section: 'Sanitary', description: 'Wall hung WC with concealed cistern and dual flush plate (Grohe)', qty: 4, unit: 'set', basis: B, confidence: 'high' },
    { section: 'Sanitary', description: 'Wash basin 600mm with pedestal and chrome mixer (Duravit)', qty: 4, unit: 'set', basis: B, confidence: 'high' },
    { section: 'Sanitary', description: 'Thermostatic shower mixer with rain shower head 250mm (Hansgrohe)', qty: 3, unit: 'nos', basis: B, confidence: 'high' },
    { section: 'Drainage', description: 'Floor drain 150x150 stainless steel, anti-odour (ACO)', qty: 6, unit: 'nos', basis: B, confidence: 'high' },
    { section: 'Waterproofing', description: 'Waterproofing membrane to wet areas, two coats, 150mm upstand (Sika)', qty: 38, unit: 'm2', basis: B, confidence: 'high' },
  ], keywords: ['tiling'], assumptions: [], missing_info: [], confidence: 'high' };

async function pagesOfFixture() { const bytes = await Deno.readFile(FIX); const pages = await pdfPages(bytes, undefined, { layers: false }); return { bytes, pages, lines: linesFromRuns(pages).split('\n').map((l) => l.trim()).filter(Boolean) }; }

/** The path the reading takes: drawing_boq (gate in the model path), customer_api analyze_drawing (the gate again with the file
 *  name, the old supplier's terms kept), create_inquiry (identity gate, redactBoq with the customer's seeds, terms to the
 *  customer-only key), the supplier inbox (the one gate), the inquiry PDF. Returns what a supplier receives. */
async function toSupplier(reading: any, summary: string) {
  const { pages, lines } = await pagesOfFixture();
  let ai: any = structuredClone(reading);
  if (ai.document_kind !== 'quotation' && looksPriced(lines.join('\n'))) ai.document_kind = 'quotation';
  if (isQuotationReading(ai)) ai = quotationGate(ai, quotationTerms(lines));
  const g = gateDrawingBoq(ai, setIdentityTerms(pages), false);
  assert(g.boq, 'the drawing identity gate held the whole reading');
  const terms = quotationTerms(lines, [FILE.replace(/\.pdf$/, '')]);
  const analysed: any = quotationGate({ ...g.boq, document_kind: 'quotation' }, terms);
  const kept = termsToKeep(terms);
  const ci = redactBoq(analysed, seedTerms({ name: CUST.name, email: CUST.email, phone: CUST.phone, project: CUST.project, extra: [FILE] }));
  assert(!ci.held, 'create_inquiry held it: ' + ci.reasons.join('; '));
  const spec = { location: 'Dubai', site_location: 'Villa 15, Al Barsha 2', old_supplier_terms: kept };
  const buyer = { name: CUST.name, email: CUST.email, phone: CUST.phone, project: CUST.project };
  const seeds = requestSeeds(buyer, spec);
  const ib = inboxBoq(quotationGate(ci.boq, { parties: [], refs: [], prefixes: [] }), CUST.name, seeds, []);
  assertEquals(ib.withheld, false, 'the inbox withheld the BOQ');
  const sum = supplierField<string>(forSource(summary, 'quotation'), buyer, seeds);
  const row: InquiryDocRow = { id: 'd3a0c4a1-0b0e-4c21-9f00-00000000a101', rfq_no: 160501, category: 'plumbing_sanitary', emirate: 'Dubai', summary: sum.value, budget: null, scope_type: 'single', brief_source: 'quotation',
    created_at: '2026-11-13T06:00:00.000Z', spec: supplierBrief(spec, 'Dubai', buyer, seeds).value, boq: ib.boq as any, boq_withheld: false, documents: [{ kind: 'boq_csv', name: 'Job_160501_BOQ.csv', lines: (ib.boq as any).boq.length }], drawing_pages_failed: 0 };
  const doc = inquiryDocument({ inquiry: row, lang: 'en', date: '13 November 2026' });
  const pr = await renderPdf(doc.body, { fetchBytes: () => Promise.resolve(null) });
  assert(pr.ok, 'the inquiry PDF did not render');
  const pdfText = linesFromRuns(await pdfPages((pr as any).bytes));
  const email = newInquiryBody({ resolved: true, buyer, spec, summary, budget: null, extra: attachedLine('quotation', true, false), category: 'plumbing_sanitary', emirate: 'Dubai', briefSource: 'quotation' });
  return { boq: ib.boq as any, json: JSON.stringify({ ...row, boq: ib.boq }), pdfText, email, analysed };
}

Deno.test('the careless reading of a competitor quotation: nothing of the old supplier, its prices or the customer reaches a supplier; every item survives', async () => {
  const s = await toSupplier(CARELESS, 'Bathroom sanitary ware and wall tiling, as quoted by Falcon Trading at AED 32,816.70.');
  assertEquals(hits(s.json, NEVER), [], 'inbox JSON');
  assertEquals(hits(s.pdfText, NEVER), [], 'inquiry PDF');
  assertEquals(hits(s.email, NEVER), [], 'new-inquiry e-mail');
  assertEquals(MUST_CARELESS.filter((m) => !s.json.includes(m)), [], 'an item, a size or a make was removed');
  for (const l of s.boq.boq) assertEquals(priceResidue(JSON.stringify(l)), [], 'a price shape is left on a line');
  assert(s.boq.boq.every((l: any) => l.basis === 'As listed in the customer\'s document'), 'a line kept the old supplier\'s basis');
  assert(/Items to quote/.test(s.pdfText) && !/draft bill of quantities|drawing page/i.test(s.pdfText), 'the PDF calls the quotation a drawing');
  // review of F2: the careless PDF had a blank subtitle and a leftover "as per standard detail"
  assert(!/standard detail/i.test(s.pdfText), s.pdfText);
  assert(/Plumbing sanitary work in Dubai|Plumbing Sanitary in Dubai/i.test(s.pdfText), 'the cover subtitle is blank: ' + s.pdfText.slice(0, 300));
});

Deno.test('the faithful reading: all six items with their makes, the verdict said to the customer and printed for suppliers', async () => {
  const s = await toSupplier(FAITHFUL, 'Supply and installation of bathroom sanitary ware and wall tiling for a villa in Dubai.');
  assertEquals(hits(s.json + s.pdfText + s.email, NEVER), []);
  assertEquals(MUST_FAITHFUL.filter((m) => !s.pdfText.includes(m)), [], 'the PDF lost content');
  assert(s.pdfText.includes('Not stated in the customer\'s file') && s.pdfText.includes('supply only'), 'what is not known is not on the PDF');
  const u = understoodMessage(s.analysed, 'quotation')!;
  assert(/quotation from another supplier/.test(u.en) && /not yet enough/.test(u.en) && /send it as it is/.test(u.en), u.en);
  assert(/عرض سعر من مورّد آخر/.test(u.ar));
  const note = drawingNoteOf(s.analysed);
  assert(/EXISTING QUOTATION/.test(note) && /not yet sufficient/.test(note) && /send it as it is/.test(note) && /never write its name, prices or references/.test(note), note);
});

Deno.test('the code reader of the same PDF keeps the scope words and loses the old supplier\'s detail code', async () => {
  const { bytes, lines } = await pagesOfFixture();
  const r = await readDocument(bytes, FILE, 'application/pdf', 0, { pdfCadDrawingsOnly: true });
  assert(r.ok);
  const b0: any = boqFromExtracted(r as any, '', '', {});
  assert(isQuotationReading(b0), 'the code reader did not see a quotation');
  const b = quotationGate(b0, quotationTerms(String((r as any).text || '').split('\n')));
  const t = JSON.stringify(b.boq);
  assertEquals(hits(t, NEVER), [], t);
  // measured before this change: "fix porcelain wall tiles ... to bathrooms of" (the Subject line made "Supply and" a term)
  assert(/Supply and fix porcelain wall tiles 300x600mm/.test(t), t);
  assert(!quotationPartyTerms(lines).some((x) => /^Supply and|^Cheques|^Payment/i.test(x)), 'a scope or terms phrase became a party term');
  assert(quotationPartyTerms(lines).includes('Falcon Trading'));
  void lines;
});

Deno.test('priced or not: the code backstop and the over-redaction rows of the money gate', async () => {
  const { lines } = await pagesOfFixture();
  assert(looksPriced(lines.join('\n')));
  const drawing = linesFromRuns(await pdfPages(await Deno.readFile(new URL('./fixtures/zz_demo_villa_hvac_sheet_m101.pdf', import.meta.url)), undefined, { layers: false }));
  assert(!looksPriced(drawing), 'a drawing sheet read as priced');
  const t = { parties: ['Falcon Trading'], refs: ['FT/Q/2026/0412'], prefixes: ['FT'] };
  const keep = ['300x600mm', '1,200 m2', 'level +0.15', 'G+1', 'BS EN 997', 'Grohe Rapid SL 38772001', '2 years warranty', 'made in Italy', '15% slope', '2.40 m', '600x600', 'FD-1', 'Class 1'];
  const gated = quotationGate({ boq: keep.map((k) => ({ description: 'Item ' + k, qty: 1, unit: 'nos' })) }, t) as any;
  assertEquals(gated.boq.map((l: any) => l.description), keep.map((k) => 'Item ' + k));
  const gone = quotationGate({ boq: [{ description: 'Tiles @ AED 95/m2 as per Falcon Trading FT-SD-04, ref FT/Q/2026/0412, amount 8,170.00' }, { description: 'Grand Total 32,816.70' }] }, t) as any;
  assertEquals(gone.boq.length, 1);
  assertEquals(hits(JSON.stringify(gone.boq), ['95', 'Falcon', 'FT-SD', '0412', '8,170', '32,816']), []);
});

Deno.test('what the supplier is told is attached is said of what it is', () => {
  assert(/existing quotation/.test(attachedLine('quotation', true, false)) && !/drawing/i.test(attachedLine('quotation', true, false)));
  // a quotation AND a real drawing attached together keep the drawing (review of F2)
  assert(/existing quotation/.test(attachedLine('quotation', true, true)) && /redacted drawing is attached/.test(attachedLine('quotation', true, true)));
  assert(/bill of quantities/.test(attachedLine('boq', true, false)));
  assertEquals(attachedLine('drawing', true, false), ' A draft bill of quantities from the customer’s drawing is attached.');
  assertEquals(attachedLine('drawing', false, true), ' A redacted drawing is attached.');
});

// ── THE INDEPENDENT REVIEW OF 13 NOV 2026 (F2 DOORS 1), item 6 and the priced route. Each failed before its fix. ──────────

Deno.test('M12: the analyze_drawing route for a priced document: a quotation is rebuilt with no page, a priced BOQ hides its rates, a drawing goes on', async () => {
  const { lines } = await pagesOfFixture();
  const q = pricedRoute({ isCad: false, pdfLines: lines, reading: structuredClone(CARELESS) })!;
  assert(q, 'a quotation was routed as a drawing');
  assertEquals([q.brief_source, q.drawing_redacted_paths.length, q.share_redacted], ['quotation', 0, false]);
  assertEquals(hits(JSON.stringify(q.boq.boq) + String(q.boq.summary), NEVER), [], JSON.stringify(q.boq));
  assert(Array.isArray(q.boq.old_supplier_terms) && q.boq.old_supplier_terms.some((t: string) => /Falcon/.test(t)));
  assert(/quotation from another supplier/.test(String(q.understood_message)));
  // a consultant's priced BOQ: rates hidden, and never called another supplier's quotation
  const boq = ['BILL OF QUANTITIES - FIT-OUT', 'Item Description Qty Unit Rate Amount', '1 Porcelain tiles 600x600 86 m2 95.00 8,170.00', '2 Skirting 40 lm 25.00 1,000.00', 'Total 9,170.00'];
  const p = pricedRoute({ isCad: false, pdfLines: boq, reading: { document_kind: 'boq', boq: [{ description: 'Porcelain tiles 600x600', qty: 86, unit: 'm2', basis: 'rate 95.00' }] } })!;
  assertEquals([p.brief_source, p.note], ['boq', 'priced_rates_withheld']);
  assert(/rates in your document are not shared/i.test(String(p.understood_message)) && !/another supplier/i.test(String(p.understood_message)));
  // what goes on to suppliers (customer_rates is moved to the customer-only key at create_inquiry)
  assertEquals(hits(JSON.stringify({ ...p.boq, customer_rates: undefined }), ['95.00', '8,170', '9,170']), []);
  // a drawing whose text says "flow rate ... amount" is a drawing
  const dwg = ['MECHANICAL SCHEDULE', 'AHU-1 flow rate 2,400.50 l/s, amount of fresh air 30%', 'FCU-2 air flow 400 l/s, total 6 units'];
  assertEquals(pricedRoute({ isCad: false, pdfLines: dwg, reading: { document_kind: 'drawing', boq: [] } }), null);
  assertEquals(pricedKind(dwg.join('\n')), null);
});

Deno.test('item 6: the quotation gate keeps every quantity, standard, grade and material, and a file name adds no term', () => {
  const t = { parties: ['Falcon Trading', 'Falcon'], refs: ['FT/Q/2026/0412'], prefixes: ['FT'] };
  const keep = ['Porcelain tiles 2,400.00 m2', 'Cable 1,250.50 m', 'Paint 12,000.00 sqft', 'Valve DN-100-PN16', 'Repair mortar to EN-1504-2', 'Sealant ASTM-C-920',
    'SS-316-L handrail', 'Total 85 m2 of wall tiles', 'Cooling tower motor 15 kW', 'Chiller 250 TR', 'Duct 1,200 LM'];
  const g = quotationGate({ boq: keep.map((d) => ({ description: d, qty: 1, unit: 'nos' })) }, t) as any;
  assertEquals(g.boq.map((l: any) => l.description), keep);
  // a firm named after its trade keeps the trade word in every line, and only the full name is kept as a seed
  const mt = quotationTerms(['Marble Trading LLC', 'Steel Engineering LLC', 'Glass Contracting LLC', 'To: ZZ DEMO Omar', 'Quotation No: MT/Q/2026/11']);
  const out = quotationGate({ boq: [{ description: 'Marble threshold, steel door frame, glass partition' }] }, mt) as any;
  assertEquals(out.boq[0].description, 'Marble threshold, steel door frame, glass partition');
  assert(!termsToKeep(mt).some((x) => /^(marble|steel|glass)$/i.test(x)), JSON.stringify(termsToKeep(mt)));
  const ft = quotationTerms(['Kitchen Fit-out quotation'], ['tiles', 'kitchen']);
  assert(!ft.parties.some((x) => /^(tiles|kitchen)$/i.test(x)), JSON.stringify(ft.parties));
  // a sentence goes for the old offer's terms or for money, never for the word "total"
  assertEquals(quotationProse('Supply and fix tiles to 2 bathrooms, total area 85 m2. Payment 50% advance. Total AED 32,816.70.'), 'Supply and fix tiles to 2 bathrooms, total area 85 m2.');
});

Deno.test('second review: a model number stays; integer-rate and Arabic priced tables are seen as priced; the customer keeps his own rates', () => {
  const t = { parties: [], refs: ['FT/Q/2026/0412'], prefixes: ['FT'] };
  const g = quotationGate({ boq: [{ description: 'Split AC Model HD-2020-W, 2 TR', qty: 4, unit: 'nos' }, { description: 'Pump Type: KP-2019-B' }] }, t) as any;
  assertEquals(g.boq.map((l: any) => l.description), ['Split AC Model HD-2020-W, 2 TR', 'Pump Type: KP-2019-B']);
  // integer rates under a Rate / Amount heading, with no letterhead: the customer's own priced BOQ
  const intRates = ['BILL OF QUANTITIES', 'Item Description Qty Unit Rate Amount', '1 Tiles 600x600 86 m2 85 7310', '2 Skirting 40 lm 25 1000', 'Total 8310'];
  assertEquals(pricedKind(intRates.join('\n')), 'priced');
  // an Arabic quotation: a firm, priced lines and a total
  const ar = ['شركة زد زد ديمو للمقاولات ذ.م.م', 'السادة: زد زد ديمو', 'البند الوصف الكمية الوحدة السعر المبلغ', '1 بلاط بورسلين 86 م2 95.00 8,170.00', '2 مغسلة 4 عدد 1,180.00 4,720.00', 'الإجمالي 12,890.00'];
  assertEquals(pricedKind(ar.join('\n')), 'quotation');
  const p = pricedRoute({ isCad: false, pdfLines: intRates, reading: { document_kind: 'boq', boq: [{ description: 'Tiles 600x600', qty: 86, unit: 'm2', basis: 'rate AED 85, amount 7,310' }] } })!;
  assertEquals(p.brief_source, 'boq');
  assertEquals(hits(JSON.stringify(p.boq.boq), ['7,310', 'AED 85']), []);
  assert(Array.isArray(p.boq.customer_rates) && /7,310/.test(JSON.stringify(p.boq.customer_rates)), 'the customer\'s own rates were thrown away');
});

// FINAL REVIEW of the combined release, 13 Nov 2026 (item 2): the money shapes knew ASCII digits and "AED"/"Dhs" only, so the
// old supplier's rates crossed on our inquiry as "١٢٠ درهم للمتر", "120 dirhams per m2" and "rate ٤٥٫٠٠".
Deno.test('final review 2: the old supplier\'s prices in Arabic-Indic digits or spelled "dirhams" never pass the quotation gate', () => {
  const t = { parties: [], refs: [], prefixes: [] };
  const g = quotationGate({ boq: [{ description: 'Porcelain tiles 60x60, ١٢٠ درهم للمتر', qty: 85, unit: 'm2' }, { description: 'Tiles at 120 dirhams per m2', qty: 85, unit: 'm2' },
    { description: 'Grout, rate ٤٥٫٠٠ درهم', qty: 10, unit: 'kg' }, { description: 'Skirting 100 Dirham per lm', qty: 40, unit: 'lm' }] }, t) as any;
  const out = g.boq.map((l: any) => String(l.description));
  for (const d of out) assert(!/[١٢٠٤٥]|120|dirham|درهم/i.test(d), d);
  assert(out[0].includes('60x60') && out[0].includes('Porcelain tiles'), out[0]);
  for (const s of ['السعر السابق ٣٨٥٠٠ درهم', 'They charged 120 dirhams per sqm.', 'Old rate 45.00 AED per lm']) assert(!/[٣٨٥٠]|120|45|dirham|درهم|AED/i.test(quotationProse(s)), quotationProse(s));
  assertEquals(priceResidue('المجموع ٣٨٥٠٠ درهم').length, 1);
  // quantities in Arabic-Indic digits are not money
  const q = quotationGate({ boq: [{ description: 'بلاط بورسلان ٦٠×٦٠، المساحة ٨٥ م٢' }] }, t) as any;
  assertEquals(q.boq[0].description, 'بلاط بورسلان ٦٠×٦٠، المساحة ٨٥ م٢');
});
