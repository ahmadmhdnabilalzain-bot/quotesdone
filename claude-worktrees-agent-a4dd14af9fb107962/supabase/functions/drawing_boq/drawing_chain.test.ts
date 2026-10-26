// drawing_chain.test.ts — the drawing's BOQ, all the way to the PDF a matched supplier downloads.
// deno test -A --no-lock supabase/functions/drawing_boq/drawing_chain.test.ts
//
// 21 Sep 2026, sales_engineer. Founder instruction 580: "make sure that the PDF that he generates for the
// BOQ and how he ingests it in the system so that it can be shared as an inquiry with the suppliers ...
// they should be perfect." Each link below is the production code, not a copy of it:
//   1. a BOQ in the drawing reader's shape (drawing_boq: section, description, qty, unit, basis,
//      confidence, qty_status, type) — a SYNTHETIC ZZ DEMO mechanical take-off;
//   2. create_inquiry's settle + gate (boq_open_lines.settleLines, then anonymise.redactBoq with the
//      customer's seed terms) — what inquiries.boq stores;
//   3. the supplier inbox's own gate (supplier_api/identity_scrub.ts: scrubIdentity for the summary,
//      inboxBoq for the BOQ) and its document list (quote_review_actions.inquiryDocuments);
//   4. the inquiry sheet on our template (quote_documents.inquiryDocument), EN and AR, rendered to real
//      PDF bytes by pdf_native's renderer in process;
//   5. the PDFs read BACK with the drawing reader (pdf_text_positions.pdfPages + linesFromRuns).
//
// WHAT IT FOUND, and what now fails if it returns:
//   * pdf_text_positions decoded every Tj/TJ string TWICE — our own inquiry PDF (Sora, Type0 /
//     Identity-H) read back as 0 runs on both pages. Fixed in pdf_text_positions.ts `show`.
//   * the inquiry PDF and the BOQ CSV dropped qty_status, so our take-off ESTIMATE printed exactly like
//     a quantity read off the drawing. Fixed: quote_documents.ts qtyBasis, "Quantity basis" column.
//
// FONTS. The brand fonts are fetched the way pdf_native fetches them (the public brand bucket). With no
// network (scripts/checks/run.mjs grants none) the renderer falls back to Helvetica, which cannot draw
// Arabic: the Arabic PDF is then asserted on the document CONTENT and the glyph read-back is skipped,
// said so on the console — never silently green.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { settleLines, openLines, type Line } from '../_shared/boq_open_lines.ts';
import { redactBoq, redactText, seedTerms } from '../_shared/anonymise.ts';
import { inboxBoq, scrubIdentity } from '../supplier_api/identity_scrub.ts';
import { inquiryDocuments, boqCsv } from '../supplier_api/quote_review_actions.ts';
import { inquiryDocument, type InquiryDocRow } from '../_shared/quote_documents.ts';
import { renderPdf } from '../pdf_native/render.ts';
import { linesFromRuns, pdfPages } from '../_shared/pdf_text_positions.ts';
import { boqFromDrawingSet } from './drawing_set.ts';
import { IDENTITY as SET_IDENTITY, sheetPdf } from './drawing_set.fixtures.ts';

// ── The ZZ DEMO customer: every identity the chain must remove ────────────────────────────────────
const CUSTOMER = { name: 'ZZ DEMO Rashid Kareem', email: 'rashid.owner@zzdemo-owner.example.invalid', phone: '+971500000017' };
const PROJECT = 'ZZ DEMO Kareem Warehouse';
const FORBIDDEN = ['ZZ DEMO', 'Rashid', 'Kareem', 'rashid.owner', 'zzdemo-owner', 'example.invalid', 'Holdings', '500000017', '500000018', 'drawings/'];
const INQUIRY_ID = 'd3a0c4a1-0b0e-4c21-9f00-00000000c580';
// The drawing's ORIGINAL (customer_api storeOriginal) and its redacted pages (drawing_redact).
const ORIGINAL = `drawings/c0ffee00-0000-4000-8000-00000000d580/1726900000_${'ZZ DEMO Kareem Warehouse M-101'.replace(/\s/g, '_')}.pdf`;
const REDACTED = [`redacted/${INQUIRY_ID}/page_p1.jpg`, `redacted/${INQUIRY_ID}/page_p2.jpg`];

// ── 1. What the drawing reader hands over (reader shape) ─────────────────────────────────────────
const READER_BOQ: Line[] = [
  { section: 'Equipment', type: 'equip:EF-1', item: 'Exhaust fan EF-1', description: 'Exhaust fan EF-1', qty: 1, unit: 'nos', basis: '"EF-1" printed on the plan', confidence: 'medium', qty_status: 'read' },
  { section: 'Air devices', type: 'air:A', item: 'Supply diffuser type A', description: 'Supply diffuser type A', qty: 12, unit: 'nos', basis: '12 "A" tags on the plan', confidence: 'medium', qty_status: 'read' },
  { section: 'Air devices', type: 'air:B', item: 'Return grille type B', description: 'Return grille type B', qty: 4, estimate: 4, unit: 'nos', basis: 'bubbles counted on M-101; no schedule row', confidence: 'low', qty_status: 'to_confirm' },
  { section: 'Ductwork', type: 'duct:gi', item: 'GI rectangular ductwork', description: 'GI rectangular ductwork', qty: null, estimate: null, unit: 'sqm', basis: 'not measured from the drawing', confidence: 'low', qty_status: 'to_confirm' },
  // A line whose text still carries the customer: phone, email, a company name and the customer's own name.
  { section: 'Equipment', type: 'equip:FCU-2', item: 'Fan coil unit FCU-2', description: `Fan coil unit FCU-2, call ${CUSTOMER.name} on ${CUSTOMER.phone} or ${CUSTOMER.email}, ZZ DEMO Holdings LLC`, qty: 2, unit: 'nos', basis: '"FCU-2" printed on the plan', confidence: 'medium', qty_status: 'read' },
];
const CLEAN_LINES = READER_BOQ.slice(0, 4); // the four lines whose text carries no identity

// ── 2 + 3. Ingestion (create_inquiry) and the inbox, exactly as production runs them ─────────────
const seeds = seedTerms({ name: CUSTOMER.name, email: CUSTOMER.email, phone: CUSTOMER.phone, project: PROJECT, extra: [ORIGINAL.split('/').pop()!] });
function ingest(): { stored: { boq: Line[]; confidence: string } | null; inbox: { boq: { boq: Line[] } | null; withheld: boolean }; hits: string[] } {
  // create_inquiry: the open lines were never answered by the customer, so they settle as "estimated".
  const settled = settleLines(READER_BOQ, { status: 'unanswered', lines: openLines(READER_BOQ) });
  const gate = redactBoq({ boq: settled, confidence: 'medium' }, seeds);
  const stored = gate.held ? null : gate.boq;
  const hits: string[] = [];
  const inbox = inboxBoq(stored, CUSTOMER.name, seeds, hits) as { boq: { boq: Line[] } | null; withheld: boolean };
  return { stored, inbox, hits };
}
function inboxRow(boq: { boq: Line[] } | null, withheld: boolean) {
  const hits: string[] = [];
  const summary = redactText(String(scrubIdentity(`Supply and install ventilation for the ${PROJECT}. Site contact ${CUSTOMER.name}, ${CUSTOMER.phone}.`, CUSTOMER.name, hits) ?? ''), seeds).text;
  // drawing_pages are what signRedactedDrawings returns: signed URLs of inquiries.drawing_redacted_paths only.
  const sign = (p: string) => `https://zzdemo.supabase.invalid/storage/v1/object/sign/drawing-files/${p}?token=zz`;
  return { id: INQUIRY_ID, category: 'hvac', emirate: 'Dubai', summary, spec: null, budget: null, scope_type: 'single', created_at: '2026-09-21T06:00:00.000Z',
    boq, boq_withheld: withheld, drawing_pages: REDACTED.map(sign), drawing_pages_expected: 2, drawing_pages_failed: 0 };
}
function docRow(i: ReturnType<typeof inboxRow>): InquiryDocRow {
  // supplier_api inquiry_pdf builds exactly this from the inbox row.
  const d = inquiryDocuments(i);
  return { id: i.id, category: i.category, emirate: i.emirate, summary: i.summary, budget: i.budget, scope_type: i.scope_type, created_at: i.created_at,
    spec: i.spec, boq: i.boq, boq_withheld: i.boq_withheld, documents: d.documents.map((x: { kind: 'drawing_page' | 'boq_csv'; name: string; lines?: number }) => ({ kind: x.kind, name: x.name, lines: x.lines })), drawing_pages_failed: d.drawing_pages_failed };
}

// ── 4 + 5. Render in process, read back ───────────────────────────────────────────────────────────
const BRAND = 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/';
async function fetchBytes(p: string): Promise<Uint8Array | null> {
  try { const r = await fetch(BRAND + p); if (r.ok) return new Uint8Array(await r.arrayBuffer()); } catch { /* no network */ }
  return null;
}
async function renderAndRead(body: Record<string, unknown>) {
  const out = await renderPdf(body, { fetchBytes });
  assert(out.ok, 'renderer refused: ' + JSON.stringify(!out.ok && out.body));
  if (!out.ok) throw new Error('unreachable');
  assertEquals(new TextDecoder().decode(out.bytes.slice(0, 5)), '%PDF-');
  const text = linesFromRuns(await pdfPages(out.bytes));
  return { out, text, lines: text.split('\n') };
}
// The reader returns Arabic in VISUAL order as presentation forms: normalise, then look for the reversed string.
const visual = (s: string) => [...s.normalize('NFKC')].reverse().join('');
const hasAr = (text: string, s: string) => text.normalize('NFKC').includes(visual(s));

Deno.test('ingestion: the identifying line is scrubbed, the BOQ is not held, and every qty_status survives to the inbox', () => {
  const { stored, inbox } = ingest();
  assert(stored, 'create_inquiry HELD the BOQ: the chain never reaches a supplier');
  assertEquals(inbox.withheld, false, 'the inbox withheld a BOQ create_inquiry had already cleaned');
  const lines = inbox.boq!.boq;
  assertEquals(lines.length, READER_BOQ.length);
  const json = JSON.stringify(inbox.boq);
  for (const f of FORBIDDEN) assert(!json.includes(f), `the inbox BOQ still carries "${f}": ${json}`);
  // The reader's statuses, after create_inquiry settled the unanswered open lines.
  assertEquals(lines.map((l) => l.qty_status), ['read', 'read', 'estimated_supplier_to_verify', 'estimated_supplier_to_verify', 'read']);
  assertEquals(lines.map((l) => l.qty), [1, 12, 4, null, 2]);
  assert(lines[4].description.startsWith('Fan coil unit FCU-2'), 'the trade words of the scrubbed line were lost: ' + lines[4].description);
  // The CSV the supplier downloads carries the same basis as the PDF.
  const csv = boqCsv(lines);
  assert(csv.includes('Qty basis') && csv.includes('To confirm: our estimate') && csv.includes('Not counted: take off from the drawing'), csv);
});

Deno.test('the inquiry sheet, rendered to a real PDF in English, carries every line, marks our estimates, and names no customer', async () => {
  const { inbox } = ingest();
  const row = inboxRow(inbox.boq, inbox.withheld);
  // The original drawing is never among what the supplier is offered.
  for (const u of row.drawing_pages) assert(!u.includes(ORIGINAL) && !u.includes('/drawings/'), 'an original drawing path reached the inbox: ' + u);
  const { out, text, lines } = await renderAndRead(inquiryDocument({ inquiry: docRow(row), lang: 'en', date: '21 September 2026' }).body);
  assertEquals(out.meta.glyphs_dropped, 0, 'the English inquiry lost characters: ' + JSON.stringify(out.meta.glyphs_dropped_sample));
  for (const l of CLEAN_LINES) {
    const want = `${l.description} ${l.qty == null ? '—' : l.qty} ${l.unit}`;
    const row = lines.find((x) => x.replace(/—/g, '-').includes(want.replace(/—/g, '-'))); // Helvetica (offline) prints — as -
    assert(row, `BOQ line not on the PDF as "${want}":\n${text}`);
    if (l.qty_status === 'to_confirm') assert(/To confirm|Not counted/.test(row), `our estimate is not marked on its own line: "${row}"`);
    else assert(row.includes('Read from'), `a read quantity is not labelled as read: "${row}"`);
  }
  assert(lines.some((x) => x.includes('Fan coil unit FCU-2') && / 2 nos /.test(x + ' ')), 'the scrubbed FCU-2 line lost its quantity:\n' + text);
  assert(text.includes('Quantity basis'), 'no quantity-basis column');
  assert(text.includes('Not counted'), 'the uncounted line is not marked');
  assert(/2 lines are marked "To confirm" or "Not counted"/.test(text.replace(/\s+/g, ' ')), 'the note explaining our estimates is missing');
  assertEquals((text.match(/Drawing page \(identity removed\)/g) || []).length, REDACTED.length, 'the redacted drawing pages are not listed as identity removed');
  for (const f of FORBIDDEN) assert(!text.includes(f), `the English PDF names the customer: "${f}"`);
  for (const l of lines) assert(!l.replace(/\D/g, '').includes('500000017'), 'the customer phone survived in digits: ' + l);
});

Deno.test('the inquiry sheet in Arabic carries Arabic headings, the quantities, the estimate marker, and no customer', async () => {
  const { inbox } = ingest();
  const body = inquiryDocument({ inquiry: docRow(inboxRow(inbox.boq, inbox.withheld)), lang: 'ar', date_ar: '21 سبتمبر 2026' }).body;
  const content = JSON.stringify(body);
  for (const f of FORBIDDEN) assert(!content.includes(f), `the Arabic document names the customer: "${f}"`);
  for (const h of ['جدول الكميات', 'المستندات المرفقة', 'أساس الكمية', 'للتأكيد', 'لم تُعدّ', 'صفحة مخطط (بعد إخفاء الهوية)']) assert(content.includes(h), 'missing from the Arabic document: ' + h);
  const { out, text } = await renderAndRead(body);
  if (!out.meta.fonts.arabic) { console.warn('drawing_chain: the brand Arabic font was not reachable, so the Arabic PDF was asserted on its content only (run with -A for the glyph read-back).'); return; }
  assertEquals(out.meta.glyphs_dropped, 0, 'the Arabic font is embedded yet characters were dropped');
  for (const h of ['جدول الكميات', 'المستندات المرفقة', 'أساس الكمية', 'للتأكيد', 'تقديرنا', 'إخفاء الهوية']) assert(hasAr(text, h), `Arabic heading not read back from the PDF: ${h}\n${text}`);
  for (const q of ['12', '4', '2', '1']) assert(new RegExp(`(^|\\s)${q}(\\s|$)`, 'm').test(text), `quantity ${q} not on the Arabic PDF`);
  for (const f of FORBIDDEN) assert(!text.includes(f), `the Arabic PDF names the customer: "${f}"`);
});

// ── The whole chain from the READER, not a literal: a synthetic rotated CAD sheet (drawing_set.fixtures.ts)
// read by pdf_text_positions, taken off by drawing_set.boqFromDrawingSet, ingested and rendered as the
// supplier's inquiry. Every take-off line reaches the PDF with its quantity, nothing of the title block does.
Deno.test('the drawing reader\'s own take-off reaches the supplier\'s inquiry PDF intact and anonymous', async () => {
  const set = boqFromDrawingSet(await pdfPages(sheetPdf()), '')!;
  assert(set && set.boq.length >= 8, 'the reader produced no take-off');
  const settled = settleLines(set.boq as Line[], { status: 'unanswered', lines: openLines(set.boq as Line[]) });
  const gate = redactBoq({ boq: settled, confidence: 'medium' }, seeds);
  assert(!gate.held, 'create_inquiry HELD the reader\'s BOQ: ' + gate.reasons.join('; '));
  const hits: string[] = [];
  const inbox = inboxBoq(gate.boq, CUSTOMER.name, seeds, hits) as { boq: { boq: Line[] } | null; withheld: boolean };
  assertEquals(inbox.withheld, false);
  const { text } = await renderAndRead(inquiryDocument({ inquiry: docRow(inboxRow(inbox.boq, false)), lang: 'en', date: '21 September 2026' }).body);
  const flat = text.replace(/\s+/g, ' ');
  for (const tag of ['EF-1', 'IRH-1', 'RTU1-2', 'WC/L-1', 'Air device type A', 'Air device type B']) assert(flat.includes(tag), `take-off line missing from the PDF: ${tag}`);
  assert(/To confirm/.test(flat), 'the reader\'s estimates are not marked on the PDF');
  for (const s of SET_IDENTITY) assert(!flat.includes(s), `title-block identity reached the supplier PDF: ${s}`);
});
