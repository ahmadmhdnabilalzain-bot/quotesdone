// competitor_quote — a competitor's priced QUOTATION a customer uploads becomes OUR inquiry: every line with its
// quantity, unit and specification, no rate / amount / total, no supplier or customer identity, and the supplier's
// BOQ PDF on our template renders from it in English and Arabic (10 Nov 2026, sales_engineer; founder 10 Nov).
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/drawing_boq/competitor_quote.test.ts
// The two production paths, end to end with no model and no network:
//   PDF  - customer_api analyze_document -> drawing_boq mode 'document': readDocument -> boqFromExtracted -> gateDrawingBoq
//   XLSX - customer_api analyze_boq      -> drawing_boq mode 'sheet':    boqFromSheet
// then create_inquiry (settleLines + redactBoq) -> the supplier inbox (inboxBoq) -> inquiryDocument -> renderPdf.
// deno-lint-ignore-file no-explicit-any
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { readDocument } from '../_shared/doc_read/index.ts';
import { boqFromExtracted } from './boq_from_document.ts';
import { boqFromSheet } from './boq_from_sheet.ts';
import { drawingIdentityTerms, gateDrawingBoq } from '../_shared/drawing_identity_gate.ts';
import { redactBoq, seedTerms } from '../_shared/anonymise.ts';
import { openLines, settleLines, type Line } from '../_shared/boq_open_lines.ts';
import { inboxBoq } from '../supplier_api/identity_scrub.ts';
import { inquiryDocument, type InquiryDocRow } from '../_shared/quote_documents.ts';
import { renderPdf } from '../pdf_native/render.ts';
import { linesFromRuns, pdfPages } from '../_shared/pdf_text_positions.ts';
import { competitorQuotePdf, competitorQuoteXlsx, QUOTE_FILE, QUOTE_IDENTITY, QUOTE_LINES, QUOTE_PRICES } from './competitor_quote.fixtures.ts';

// The customer who uploaded it (the competitor's addressee): their own seeds, as create_inquiry builds them.
const CUSTOMER = { name: 'ZZ DEMO Rashid Kareem', email: 'rashid@zz-palm.example.invalid', phone: '+971500000177' };
const seeds = seedTerms({ ...CUSTOMER, extra: [QUOTE_FILE] });
const low = (s: string) => s.toLowerCase();
const leaks = (t: string) => QUOTE_IDENTITY.filter((id) => low(t).includes(low(id)));
const prices = (t: string) => QUOTE_PRICES.filter((p) => t.includes(p));

async function supplierSide(boq: { boq: Line[] } & Record<string, any>) {
  const settled = settleLines(boq.boq, { status: 'unanswered', lines: openLines(boq.boq) });
  const gate = redactBoq({ ...boq, boq: settled }, seeds);
  assert(!gate.held, 'create_inquiry HELD the inquiry: ' + gate.reasons.join('; '));
  const inbox = inboxBoq(gate.boq, CUSTOMER.name, seeds, []) as { boq: { boq: Line[] } | null; withheld: boolean };
  assertEquals(inbox.withheld, false, 'the supplier inbox withheld the BOQ');
  const row: InquiryDocRow = { id: 'd3a0c4a1-0b0e-4c21-9f00-00000000c901', category: 'fit_out_interior', emirate: 'Dubai', summary: 'Interior fit-out per the attached BOQ.', budget: null,
    scope_type: 'single', created_at: '2026-11-10T06:00:00.000Z', spec: null, boq: inbox.boq, boq_withheld: false, documents: [], drawing_pages_failed: 0 };
  const out: Record<'en' | 'ar', { text: string; body: string }> = {} as any;
  for (const lang of ['en', 'ar'] as const) {
    const doc = inquiryDocument({ inquiry: row, lang, date: '10 November 2026', date_ar: '10 نوفمبر 2026' });
    const r = await renderPdf(doc.body, { fetchBytes: () => Promise.resolve(null) });
    assert(r.ok, 'the renderer refused: ' + JSON.stringify(!r.ok && r.body));
    if (!r.ok) throw new Error('unreachable');
    assertEquals(new TextDecoder().decode(r.bytes.slice(0, 5)), '%PDF-');
    out[lang] = { text: linesFromRuns(await pdfPages(r.bytes)), body: JSON.stringify(doc.body) };
  }
  return { lines: inbox.boq!.boq, ...out };
}

function assertInquiry(boq: any, what: string) {
  const lines: any[] = boq.boq;
  for (const want of QUOTE_LINES) {
    const l = lines.find((x) => want.desc.test(String(x.description)));
    assert(l, `${what}: no line for ${want.desc} in ${JSON.stringify(lines.map((x) => [x.description, x.qty, x.unit]))}`);
    assertEquals(l.qty, want.qty, `${what}: ${want.desc} quantity`);
    assertEquals(String(l.unit).toLowerCase(), want.unit, `${what}: ${want.desc} unit`);
    if (want.spec) assert(want.spec.test(`${l.specification ?? ''} ${l.description}`), `${what}: ${want.desc} lost its brand / spec: ${JSON.stringify(l)}`);
  }
  assertEquals(lines.length, QUOTE_LINES.length, `${what}: only the priced items are lines (no total, VAT, term or letterhead line): ${JSON.stringify(lines.map((x) => x.description))}`);
  const all = JSON.stringify(boq);
  assertEquals(prices(all), [], `${what}: a price reached the inquiry`);
  assertEquals(leaks(all), [], `${what}: identity reached the inquiry`);
  assert(!/\bAED\b|\bVAT\b|grand total|sub ?total/i.test(JSON.stringify(lines)), `${what}: a commercial word reached a line`);
}

async function assertSupplierPdfs(boq: any, what: string) {
  const p = await supplierSide(boq);
  const flat = p.en.text.replace(/\s+/g, ' ');
  for (const want of QUOTE_LINES) {
    const l = p.lines.find((x) => want.desc.test(String(x.description)))!;
    assert(flat.includes(String(l.description).slice(0, 24)), `${what}: "${l.description}" is not on the English PDF`);
    assert(new RegExp(`(^|[^0-9])${want.qty}([^0-9]|$)`).test(p.ar.body), `${what}: quantity ${want.qty} is not on the Arabic sheet`);
  }
  assert(p.ar.body.includes('جدول الكميات'), `${what}: the Arabic sheet has no BOQ heading`);
  for (const [lang, t] of [['en pdf', p.en.text], ['ar document', p.ar.body], ['ar pdf', p.ar.text]]) {
    assertEquals(leaks(t), [], `${what}: identity on the ${lang}`);
    assertEquals(prices(t), [], `${what}: a competitor's price on the ${lang}`);
  }
}

Deno.test('competitor quotation PDF -> our inquiry: every line, qty, unit and brand; no price, no party; supplier PDF EN + AR', async () => {
  const bytes = competitorQuotePdf();
  const r = await readDocument(bytes, QUOTE_FILE + '.pdf', '', 0, { pdfCadDrawingsOnly: true });
  assert(r.ok, 'the PDF quotation was not read');
  if (!r.ok) return;
  // drawing_boq mode 'document', as index.ts runs it for a PDF.
  const g = gateDrawingBoq(boqFromExtracted(r, '', '', {}), drawingIdentityTerms(r.text), false);
  assert(g.boq, 'the identity gate withheld the whole inquiry: ' + g.found.join('; '));
  assertInquiry(g.boq, 'PDF');
  assert((g.boq as any).assumptions.some((a: string) => /quotation/i.test(a) && /no (rate|price)/i.test(a)), 'the inquiry does not say it was rebuilt from a priced quotation');
  await assertSupplierPdfs(g.boq, 'PDF');
});

Deno.test('competitor quotation XLSX -> our inquiry: every line, qty, unit and brand; no price, no party; supplier PDF EN + AR', async () => {
  const r = boqFromSheet(competitorQuoteXlsx(), '', QUOTE_FILE + '.xlsx');
  assert(r.ok, 'the XLSX quotation was not read');
  if (!r.ok) return;
  assertInquiry(r.boq, 'XLSX');
  assert(r.boq.assumptions.some((a: string) => /quotation/i.test(a) && /no (rate|price)/i.test(a)), 'the inquiry does not say it was rebuilt from a priced quotation');
  await assertSupplierPdfs(r.boq, 'XLSX');
});
