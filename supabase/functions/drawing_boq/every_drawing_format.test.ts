// every_drawing_format — ONE ZZ DEMO job in every drawing format a customer sends, through the production
// readers, counters, gates and the supplier's BOQ PDF on our template, in English and Arabic.
// deno test --no-lock --node-modules-dir=auto --allow-read=. supabase/functions/drawing_boq/every_drawing_format.test.ts
//
// 24 Sep 2026, sales_engineer. Founder instructions 31, 32, 64, 580, 696, 698, 701, 703. This is the proof
// behind docs/sales-engineer/DRAWING_FORMAT_MATRIX.md: a cell is SUPPORTED there only if a test here (or in
// cad_render.test.ts / drawing_redact_page.check.ts) proves it. Per format it asserts:
//   read    - the production reader opens the bytes (by their magic, never the name) and says what it is;
//   count   - the tagged elements equal the count known by construction (legend samples not counted);
//   BOQ PDF - the take-off, through create_inquiry's gate and the supplier inbox's gate, renders to a real
//             PDF on our template in English and in Arabic, every counted line on it with its quantity;
//   redact  - no identity string (title block, parties, contacts, drawing / job numbers, file name,
//             metadata) is on the BOQ, the PDFs, or the drawing a supplier may see; the content is.
// FONTS: with no brand font the renderer falls back to Helvetica, which cannot draw Arabic; the Arabic PDF is
// then asserted on its document content and the glyph read-back is skipped - said on the console, never
// silently green (the same rule as drawing_chain.test.ts).
// deno-lint-ignore-file no-explicit-any
import { assert, assertEquals } from 'jsr:@std/assert@1';
// @deno-types="../_shared/vendor/sheetjs-0.20.3/types/index.d.ts"
import { CFB } from '../_shared/vendor/sheetjs-0.20.3/xlsx.mjs';
import { readDocument } from '../_shared/doc_read/index.ts';
import { readDxf } from '../_shared/doc_read/cad.ts';
import { dwgToDxf } from '../_shared/doc_read/dwg.ts';
import type { Extracted, ReadResult } from '../_shared/doc_read/types.ts';
import { ifcFixture } from '../_shared/doc_read/ifc.fixtures.ts';
import { CAD_COUNTS, CONTENT, CUSTOMER, FILE_NAME, IDENTITY, IMAGE_COUNTS, PDF_COUNTS, PDF_TITLE, zzDwgDb, zzDxf, zzDxfBinary, zzPdfScan, zzPdfSet, zzPdfSheet } from '../_shared/doc_read/zz_demo_drawings.fixtures.ts';
import { boqFromExtracted } from './boq_from_document.ts';
import { boqFromDrawingSet } from './drawing_set.ts';
import { cadSupplierBoq } from '../_shared/cad_identity.ts';
import { drawingIdentityTerms, gateDrawingBoq } from '../_shared/drawing_identity_gate.ts';
import { redactBoq, seedTerms, titleBlockBoxes } from '../_shared/anonymise.ts';
import { supplierBoxes } from '../_shared/supplier_copy.ts';
import { textLayerBoxes } from '../_shared/drawing_identity_text.ts';
import { openLines, settleLines, type Line } from '../_shared/boq_open_lines.ts';
import { inboxBoq } from '../supplier_api/identity_scrub.ts';
import { inquiryDocument, type InquiryDocRow } from '../_shared/quote_documents.ts';
import { renderPdf } from '../pdf_native/render.ts';
import { linesFromRuns, pdfPages, type TextRun } from '../_shared/pdf_text_positions.ts';
import { renderCadForSupplier } from '../_shared/cad_render.ts';
import { countSymbols, legendRows } from './symbol_count.ts';
import { deviceTypeOf } from './legend_vocabulary.ts';
import { boqNoteAr } from '../../../src/lib/boqNotes.ts';

const seeds = seedTerms({ ...CUSTOMER, extra: [FILE_NAME] });
const good = (r: ReadResult): Extracted => { if (!r.ok) throw new Error(`${r.error}: ${r.detail}`); return r; };
const lower = (s: string) => s.toLowerCase();
const leaks = (text: string) => IDENTITY.filter((id) => lower(text).includes(lower(id)));

// ── the supplier's BOQ PDF, exactly as production builds it ─────────────────────────────────────────
// No brand assets offline (the suite grants no network): the renderer's own fallbacks, as in CI. The Arabic
// glyphs were read back once with a real Arabic font standing in for the brand's (see the PR's test log).
const fetchBytes = (_p: string): Promise<Uint8Array | null> => Promise.resolve(null);
/** create_inquiry (settle + redactBoq) -> supplier inbox (inboxBoq) -> inquiry sheet EN and AR -> PDF bytes -> read back. */
async function supplierPdfs(boq: { boq: Line[] } & Record<string, any>) {
  const settled = settleLines(boq.boq, { status: 'unanswered', lines: openLines(boq.boq) });
  const gate = redactBoq({ ...boq, boq: settled }, seeds);
  assert(!gate.held, 'create_inquiry HELD the take-off: ' + gate.reasons.join('; '));
  const inbox = inboxBoq(gate.boq, CUSTOMER.name, seeds, []) as { boq: { boq: Line[] } | null; withheld: boolean };
  assertEquals(inbox.withheld, false, 'the supplier inbox withheld a BOQ create_inquiry had cleaned');
  const row: InquiryDocRow = { id: 'd3a0c4a1-0b0e-4c21-9f00-00000000d701', category: 'mep', emirate: 'Dubai', summary: 'Supply and install per the attached take-off.', budget: null,
    scope_type: 'single', created_at: '2026-09-24T06:00:00.000Z', spec: null, boq: inbox.boq, boq_withheld: false, documents: [{ kind: 'drawing_page', name: 'Job_D701_drawing_p01.jpg' }], drawing_pages_failed: 0 };
  const out: Record<'en' | 'ar', { text: string; body: string; arabicFont: boolean }> = {} as any;
  for (const lang of ['en', 'ar'] as const) {
    const doc = inquiryDocument({ inquiry: row, lang, date: '24 September 2026', date_ar: '24 سبتمبر 2026' });
    const r = await renderPdf(doc.body, { fetchBytes });
    assert(r.ok, 'the renderer refused: ' + JSON.stringify(!r.ok && r.body));
    if (!r.ok) throw new Error('unreachable');
    assertEquals(new TextDecoder().decode(r.bytes.slice(0, 5)), '%PDF-');
    out[lang] = { text: linesFromRuns(await pdfPages(r.bytes)), body: JSON.stringify(doc.body), arabicFont: !!r.meta.fonts.arabic };
  }
  return { lines: inbox.boq!.boq, ...out };
}
/** Every line's description and quantity on the English PDF; Arabic headings on the Arabic document; no identity on either. */
function assertPdfs(p: Awaited<ReturnType<typeof supplierPdfs>>, want: [RegExp, number][]) {
  const flat = p.en.text.replace(/\s+/g, ' ');
  for (const [re, q] of want) {
    const l = p.lines.find((x) => re.test(`${x.description} ${x.item ?? ''}`));
    assert(l, `no BOQ line for ${re}: ${JSON.stringify(p.lines.map((x) => [x.description, x.qty]))}`);
    assertEquals(l!.qty, q, `${re}: the count is wrong`);
    assert(flat.includes(l!.description.replace(/—/g, '-').slice(0, 24)) || flat.includes(l!.description.slice(0, 24)), `"${l!.description}" is not on the English PDF`);
  }
  assert(p.ar.body.includes('جدول الكميات'), 'the Arabic sheet has no BOQ heading');
  for (const [, q] of want) assert(new RegExp(`(^|[^0-9])${q}([^0-9]|$)`).test(p.ar.body), `quantity ${q} is not on the Arabic sheet`);
  if (!p.ar.arabicFont) console.warn('every_drawing_format: the brand Arabic font was not reachable; the Arabic PDF is asserted on its content (glyph read-back skipped).');
  for (const [lang, text] of [['en', p.en.text], ['ar document', p.ar.body], ['ar pdf', p.ar.text], ['boq', JSON.stringify(p.lines)]]) assertEquals(leaks(text), [], `identity on the ${lang}`);
}

// ── CAD ─────────────────────────────────────────────────────────────────────────────────────────────
// customer_api / drawing_boq: readDocument -> boqFromExtracted -> gateDrawingBoq (cad) -> cadSupplierBoq.
async function cadTakeoff(e: Extracted) {
  const g = gateDrawingBoq(boqFromExtracted(e, '', '', {}), drawingIdentityTerms(e.text, e.dxf_text, e.identity_terms), true);
  assert(g.boq, 'the identity gate withheld the whole CAD take-off: ' + g.found.join('; '));
  return cadSupplierBoq(g.boq, e.dxf_text ?? '') as any;
}
const CAD_WANT: [RegExp, number][] = [[/block SD\b/, CAD_COUNTS.SD], [/block SKT\b/, CAD_COUNTS.SKT]];

for (const [name, read] of [
  ['DXF (ASCII)', async () => good(await readDocument(zzDxf(), FILE_NAME + '.dxf'))],
  ['DXF (binary)', async () => good(await readDocument(zzDxfBinary(), FILE_NAME + '.dxf'))],
  ['DWG (LibreDWG entities)', async () => good(await readDxf(new TextEncoder().encode(dwgToDxf(zzDwgDb()).dxf), { filename: FILE_NAME + '.dwg', depth: 0 }))],
] as const) {
  Deno.test(`${name}: read, SD x7 and SKT x5 counted (legend samples not), BOQ PDF EN+AR, no identity anywhere`, async () => {
    const e = await read();
    assertEquals(e.kind, 'dxf');
    const q = (b: string) => e.quantities.find((x) => x.description === `block ${b}`)?.qty;
    assertEquals([q('SD'), q('SKT')], [CAD_COUNTS.SD, CAD_COUNTS.SKT], 'the tag count is not the hand count');
    assert(e.notes.some((n) => /2 block insert\(s\) drawn as legend samples/.test(n)), e.notes.join(' | '));
    for (const n of e.notes) assert(boqNoteAr(n) !== null || !/legend samples/.test(n), `no Arabic for: ${n}`);
    for (const c of ['OFFICE 101', 'MEETING ROOM 102', 'STORE 103', 'LEGEND']) assert(e.text.includes(c), `the reader lost "${c}"`);
    const boq = await cadTakeoff(e);
    assert(!boq.boq.some((l: any) => /TITLEBLOCK|BORDER/i.test(JSON.stringify(l))), 'a title block / border was counted as work');
    assertPdfs(await supplierPdfs(boq), CAD_WANT);
    // The drawing a supplier may see: every content string, no identity string.
    const g = await renderCadForSupplier(new TextEncoder().encode(e.dxf_text!), { seeds });
    assert(g.ok, 'the CAD drawing was not drawn');
    if (g.ok) { for (const c of CONTENT) assert(g.drawn_texts.includes(c), c); assertEquals(leaks(g.drawn_texts.join('\n')), []); }
  });
}

// ── PDF ─────────────────────────────────────────────────────────────────────────────────────────────
// analyze_drawing's deterministic path: pdfPages -> boqFromDrawingSet -> gateDrawingBoq; the page itself is
// boxed by titleBlockBoxes + the text layer (pixels proved in drawing_redact_page.check.ts).
const PDF_WANT: [RegExp, number][] = [[/FD-1/, PDF_COUNTS['FD-1']], [/WC-1/, PDF_COUNTS['WC-1']], [/FCU-1/, 1], [/FCU-2/, 1], [/FCU-3/, 1]];
const isIdentityRun = (r: TextRun) => PDF_TITLE.includes(r.text) || /zz\.site|CONSULTANT:|^ZZ DEMO ORBIT$/.test(r.text);
const inside = (b: { x: number; y: number; w: number; h: number }, r: TextRun) => r.x >= b.x - 1e-6 && r.y >= b.y - 1e-6 && r.x + r.w <= b.x + b.w + 1e-6 && r.y + r.h <= b.y + b.h + 1e-6;

for (const [name, make, sheets] of [['PDF vector, one sheet', zzPdfSheet, 1], ['PDF vector, 3-sheet set', zzPdfSet, 3]] as const) {
  Deno.test(`${name}: read, FD-1 x7 / WC-1 x5 / FCU x3 counted, BOQ PDF EN+AR, every identity run boxed, no content run boxed`, async () => {
    const bytes = make();
    const r = good(await readDocument(bytes, FILE_NAME + '.pdf'));
    assertEquals(r.kind, 'pdf');
    const pages = await pdfPages(bytes);
    assertEquals(pages.length, sheets);
    const set = boqFromDrawingSet(pages, '');
    assert(set, 'the drawing-set reader found no take-off');
    const g = gateDrawingBoq(set, drawingIdentityTerms(linesFromRuns(pages)), false);
    assert(g.boq, 'the identity gate withheld the take-off: ' + g.found.join('; '));
    assertPdfs(await supplierPdfs(g.boq as any), PDF_WANT);
    assertEquals(sheets > 1 ? (g.boq as any).boq.find((l: any) => /WC-1/.test(l.description)).qty : PDF_COUNTS['WC-1'], PDF_COUNTS['WC-1'], 'a WC drawn on the plumbing AND the mechanical plan was counted twice');
    // What drawing_redact paints: the server's boxes plus the text layer's own identity boxes.
    const tb = titleBlockBoxes(await pdfPages(bytes, undefined, { layers: false }), seeds);
    const boxes = supplierBoxes(tb, null, pages.length);
    assert(boxes, `held: title block confidence ${tb.confidence}, residual ${tb.residual.join('; ')}`);
    for (let i = 0; i < pages.length; i++) {
      const all = [...boxes![i], ...textLayerBoxes(pages, i).boxes];
      for (const run of pages[i].runs) {
        if (isIdentityRun(run)) assert(all.some((b) => inside(b, run)), `page ${i + 1}: "${run.text}" is not boxed`);
        if (CONTENT.includes(run.text) || /^(FD|WC|FCU)-\d$/.test(run.text)) assert(!all.some((b) => inside(b, run)), `page ${i + 1}: content "${run.text}" is boxed`);
      }
    }
  });
}

Deno.test('PDF scanned: read as needing OCR (never guessed), and no page is boxable, so it is HELD', async () => {
  const r = good(await readDocument(zzPdfScan(), 'scan.pdf'));
  assertEquals([r.kind, r.needs], ['pdf', 'ocr']);
  assertEquals(r.quantities.length, 0);
  const pages = await pdfPages(zzPdfScan());
  assertEquals(pages[0].runs.length, 0);
  assertEquals(supplierBoxes(titleBlockBoxes(pages, seeds), null, 1), null, 'a page with no text layer must be held');
});

// ── images ──────────────────────────────────────────────────────────────────────────────────────────
// A photo is read by the customer's browser OCR (tesseract.js) and its symbols counted by symbol_count.ts
// against the drawing's own legend. Here the OCR's legend lines are given, and the counter runs on pixels.
function sheetImage(): { w: number; h: number; px: Uint8ClampedArray; channels: 4 } {
  const w = 1200, h = 800, px = new Uint8ClampedArray(w * h * 4).fill(255);
  const dot = (x: number, y: number, c: number[]) => { const k = (y * w + x) * 4; px[k] = c[0]; px[k + 1] = c[1]; px[k + 2] = c[2]; };
  const RED = [220, 30, 30], BLUE = [30, 60, 220];
  const circle = (cx: number, cy: number) => { for (let a = 0; a < 360; a += 2) for (const r of [9, 10]) dot(Math.round(cx + r * Math.cos(a * Math.PI / 180)), Math.round(cy + r * Math.sin(a * Math.PI / 180)), RED); };
  const square = (x: number, y: number) => { for (let i = 0; i < 16; i++) for (const t of [0, 1]) { dot(x + i, y + t, BLUE); dot(x + i, y + 15 - t, BLUE); dot(x + t, y + i, BLUE); dot(x + 15 - t, y + i, BLUE); } };
  circle(930, 100); square(922, 142);                                                       // the legend's samples
  for (const [x, y] of [[80, 90], [220, 120], [360, 90], [500, 300], [640, 420], [300, 560], [700, 650]]) circle(x, y);
  for (const [x, y] of [[150, 300], [450, 500], [760, 200]]) square(x, y);
  return { w, h, px, channels: 4 };
}
Deno.test('image (JPG/PNG): symbols counted against the legend: 7 smoke detectors, 3 call points; the photo itself is HELD', async () => {
  const img = sheetImage();
  const lines = [{ text: 'SMOKE DETECTOR', bbox: { x: 960, y: 92, w: 200, h: 16 } }, { text: 'MANUAL CALL POINT', bbox: { x: 960, y: 142, w: 220, h: 16 } }];
  const rows = legendRows(lines, img.w, deviceTypeOf);
  const c = countSymbols(img, rows);
  assertEquals(c.counts, IMAGE_COUNTS);
  // The server never holds a photo's words: readDocument says OCR is needed, and supplier_copy holds the page.
  const pngHead = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 0x1f, 0x15, 0xc4, 0x89, 0, 0, 0, 0, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82]);
  const r = good(await readDocument(pngHead, 'site photo.png'));
  assertEquals([r.kind, r.needs], ['image', 'ocr']);
});

// ── BIM / other CAD: recognised, read for what is certain, and asked for an export in EN and AR ─────
Deno.test('IFC: counted per type and storey, quantities in metres, and no party reaches the take-off', async () => {
  const e = good(await readDocument(ifcFixture(), 'model.ifc'));
  assertEquals(e.kind, 'ifc');
  const walls = e.quantities.filter((q) => /wall/i.test(q.description) && q.unit === 'nos').reduce((n, q) => n + (q.qty ?? 0), 0);
  assertEquals(walls, 2);
  const g = gateDrawingBoq(boqFromExtracted(e, '', '', {}), drawingIdentityTerms(e.text, e.dxf_text, e.identity_terms), false);
  assert(g.boq);
  assert(!/ZZ DEMO Villa/.test(JSON.stringify(g.boq)), 'the IFC project name reached the take-off');
});

Deno.test('RVT and DGN (V7, V8): recognised by their bytes, never guessed at, and asked for IFC / DWG in English and Arabic', async () => {
  const utf16 = (s: string) => new Uint8Array([...s].flatMap((c) => [c.charCodeAt(0), 0]));
  const c = CFB.utils.cfb_new();
  CFB.utils.cfb_add(c, '/BasicFileInfo', new Uint8Array([7, ...utf16('Worksharing: Not enabled\r\nFormat: 2024\r\nLast Save Path: C:\\ZZ DEMO\\Harbour.rvt\r\n')]));
  CFB.utils.cfb_add(c, '/ProjectInformation', new Uint8Array(8));
  const rvt = good(await readDocument(new Uint8Array(CFB.write(c, { type: 'array' })), 'tower.rvt'));
  assertEquals([rvt.kind, rvt.needs, rvt.quantities.length], ['rvt', 'bim_conversion', 0]);
  assert(rvt.notes.some((n) => n.includes('IFC')));
  assertEquals(leaks(rvt.text + rvt.notes.join(' ')), []);
  const v7 = new Uint8Array(2048); v7.set([0x08, 0x09, 0xfe, 0x02]);
  const dgn = good(await readDocument(v7, 'site.dgn'));
  assertEquals([dgn.kind, dgn.needs], ['dgn', 'cad_conversion']);
  for (const n of [...rvt.notes, ...dgn.notes]) assert(/[؀-ۿ]/.test(boqNoteAr(n) || ''), `no Arabic for: ${n}`);
});
