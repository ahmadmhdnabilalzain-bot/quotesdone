// The anonymity gate, format by format (founder, 14 Sep 2026: "any info related to the client name /
// project details contact info or anything that could let the supplier know who is the customer need
// to be removed before sharing the drawings" — "the same applies for boq's").
// deno test --no-lock supabase/functions/_shared/anonymise_formats.test.ts
//
// For every format the customer's own terms are PRESENT in what the reader produced, and ABSENT from
// what a supplier could receive — or the item is HELD. Held is an acceptable outcome; a leak is not.
import { assert, assertEquals } from 'jsr:@std/assert@1';
// @deno-types="./vendor/sheetjs-0.20.3/types/index.d.ts"
import * as XLSX from './vendor/sheetjs-0.20.3/xlsx.mjs';
import { readDocument } from './doc_read/index.ts';
import { redactDxf } from './doc_read/cad.ts';
import { dxfTitleBlockFixture } from './doc_read/cad.fixtures.ts';
import { pdfPages } from './pdf_text_positions.ts';
import { redactBoq, redactText, residualScan, seedTerms, titleBlockBoxes } from './anonymise.ts';
import { sanitizeUpload, SAFE_UPLOAD } from './attachment.ts';
import { boqFromExtracted } from '../drawing_boq/boq_from_document.ts';
import { supplierBoxes, supplierPageReadable } from './supplier_copy.ts';
import { empty } from './doc_read/types.ts';

const SEEDS = seedTerms({ name: 'Ahmed Al Mansoori', email: 'ahmed@almansoori.example.invalid', phone: '+971 50 123 4567', project: 'Jumeirah Park Villa 23' });
const LEAK = /mansoori|almansoori\.example|123\s?4567|jumeirah/i;
const enc = (s: string) => new TextEncoder().encode(s);

async function gate(bytes: Uint8Array, name: string) {
  const r = await readDocument(bytes, name);
  assert(r.ok, `${name}: ${JSON.stringify(r)}`);
  const before = boqFromExtracted(r);
  const g = redactBoq(before, SEEDS);
  return { before: JSON.stringify(before), after: g.held ? '' : JSON.stringify(g.boq), held: g.held, lines: before.boq.length };
}

const ROWS: (string | number)[][] = [
  ['Client: Ahmed Al Mansoori'],
  ['Project: Jumeirah Park Villa 23, Plot No. 345-678, Makani 12345 67890'],
  [],
  ['Item', 'Description', 'Qty', 'Unit', 'Rate', 'Amount'],
  ['1', 'Porcelain tiles for the Al Mansoori villa', 120, 'sqm', 85, 10200],
  ['2', 'Skirting 100mm', 45, 'm', 20, 900],
  ['', 'Prepared by Ahmed Al Mansoori, +971 50 123 4567', '', '', '', ''],
];

Deno.test('XLSX BOQ: client in the header rows, the sheet name, a footer and docProps never reach a supplier', async () => {
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(ROWS), 'Al Mansoori Villa');
  wb.Props = { Author: 'Ahmed Al Mansoori', Company: 'Al Mansoori Holdings', LastAuthor: 'Ahmed Al Mansoori', Title: 'Jumeirah Park Villa 23' };
  const g = await gate(new Uint8Array(XLSX.write(wb, { type: 'array', bookType: 'xlsx' })), 'boq.xlsx');
  assert(g.lines >= 2);
  assert(LEAK.test(g.before), 'the seed is present before the gate, or the test proves nothing');
  assert(!g.held, 'a BOQ that can be cleaned is shared, not held');
  assert(!LEAK.test(g.after), 'leak after the gate: ' + g.after);
  assert(!g.after.includes('345-678') && !g.after.includes('12345 67890') && !g.after.includes('10200'), 'plot / Makani / price after the gate');
});

Deno.test('CSV BOQ: the same rules as the workbook', async () => {
  const csv = ROWS.map((r) => r.map((c) => (/[,"]/.test(String(c)) ? `"${String(c).replace(/"/g, '""')}"` : String(c))).join(',')).join('\n');
  const g = await gate(enc(csv), 'boq.csv');
  assert(LEAK.test(g.before), 'precondition: the seed must reach the BOQ before the gate, or this test proves nothing: ' + g.before);
  assert(g.held || !LEAK.test(g.after), 'leak after the gate: ' + g.after);
});

Deno.test('email BOQ: the sender and the subject line never reach a supplier', async () => {
  const eml = 'From: Ahmed Al Mansoori <ahmed@almansoori.example.invalid>\r\nTo: rfq@quotesdone.example.invalid\r\nSubject: BOQ for Jumeirah Park Villa 23\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nPorcelain tiles for the Al Mansoori villa 120 sqm\r\nSkirting 45 m\r\nCall me on +971 50 123 4567\r\n';
  const g = await gate(enc(eml), 'boq.eml');
  assert(LEAK.test(g.before), 'precondition: the seed must reach the BOQ before the gate, or this test proves nothing: ' + g.before);
  assert(g.held || !LEAK.test(g.after), 'leak after the gate: ' + g.after);
});

Deno.test('DXF: the BOQ is clean or held, and the derived DXF for suppliers carries no seed term', async () => {
  const bytes = dxfTitleBlockFixture();
  const g = await gate(bytes, 'plan.dxf');
  assert(g.held || !LEAK.test(g.after), 'leak after the gate: ' + g.after);
  const d = redactDxf(bytes, (s) => redactText(s, SEEDS).text);
  assert(LEAK.test(new TextDecoder().decode(bytes)), 'the fixture carries the client');
  assert(!/mansoori/i.test(new TextDecoder().decode(d.bytes)), 'the derived DXF still names the client');
  assertEquals(residualScan(d.residualCheck, SEEDS), []);
});

function makePdf(lines: [number, number, string][]): Uint8Array {
  const content = lines.map(([x, y, t]) => `BT /F1 9 Tf 1 0 0 1 ${x} ${y} Tm (${t}) Tj ET`).join('\n');
  const objs = ['<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 1000 700] >>',
    '<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>', `<< /Length ${content.length} >>\nstream\n${content}\nendstream`];
  let pdf = '%PDF-1.4\n';
  objs.forEach((o, i) => { pdf += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  return Uint8Array.from(pdf + 'trailer << /Root 1 0 R >>\n%%EOF\n', (c) => c.charCodeAt(0) & 0xff);
}

Deno.test('PDF drawing: every title-block run naming the customer is inside a box, and the BOQ is clean or held', async () => {
  const bytes = makePdf([
    [80, 600, 'LIVING ROOM FLOOR TILES 32.5 m2'], [80, 580, 'Porcelain tiles Al Mansoori villa 120 sqm'],
    [760, 110, 'CLIENT: Ahmed Al Mansoori'], [760, 95, 'PROJECT: Jumeirah Park Villa 23'], [760, 80, 'CONSULTANT: ZZ DEMO Engineering Consultants'],
    [760, 65, 'Plot No. 345-678 Makani 12345 67890'], [760, 50, 'Tel +971 50 123 4567'], [760, 35, 'DRAWING NO. A-101 REV 2'],
  ]);
  const pages = await pdfPages(bytes);
  const tb = titleBlockBoxes(pages, SEEDS);
  const eps = 0.002;
  for (const r of pages[0].runs) {
    if (!/mansoori|jumeirah|345-678|12345|4567|consultant/i.test(r.text)) continue;
    const covered = (tb.boxes[0] || []).some((b) => b.x <= r.x + eps && b.y <= r.y + eps && b.x + b.w >= r.x + r.w - eps && b.y + b.h >= r.y + r.h - eps);
    assert(covered, `run not boxed: ${r.text}`);
  }
  const g = await gate(bytes, 'drawing.pdf');
  assert(LEAK.test(g.before), 'precondition: the seed must reach the BOQ before the gate, or this test proves nothing: ' + g.before);
  assert(g.held || !LEAK.test(g.after), 'leak after the gate: ' + g.after);
});

Deno.test('photo: EXIF / GPS is stripped from what is stored and forwarded', () => {
  const exif = enc('Exif\0\0GPSLatitude 25.2048 GPSLongitude 55.2708');
  const app1 = [0xff, 0xe1, (exif.length + 2) >> 8, (exif.length + 2) & 0xff, ...exif];
  const jpeg = new Uint8Array([0xff, 0xd8, ...app1, 0xff, 0xdb, 0x00, 0x04, 0x00, 0x00, 0xff, 0xda, 0x00, 0x02, 0x11, 0x22, 0xff, 0xd9]);
  const s = sanitizeUpload({ input: jpeg, allow: SAFE_UPLOAD });
  assert(s.ok && s.strippedMetadata);
  assert(!new TextDecoder('latin1').decode(s.bytes).includes('GPS'), 'GPS survived');
});

Deno.test('FAIL CLOSED: a residual seed, or no seed list at all, holds the BOQ', () => {
  const boq = { boq: [{ section: 'BOQ', item: '1', description: 'Tiles for the AlMansooriGroup showroom', qty: 10, unit: 'sqm', basis: 'row 2', confidence: 'medium' }], summary: '', assumptions: [], missing_info: [] };
  assert(redactBoq(boq, SEEDS).held, 'a name fused into another word must hold the BOQ');
  const clean = { ...boq, boq: [{ ...boq.boq[0], description: 'Porcelain tiles' }] };
  assert(!redactBoq(clean, SEEDS).held);
  assert(redactBoq(clean, []).held, 'with no seed list nothing can be proven clean');
});

// TRUST BOUNDARY (14 Sep 2026). OCR text and redaction boxes come from the customer's browser. These
// prove the supplier copy never depends on them: the server decides from the stored original.
Deno.test('TRUST BOUNDARY: client boxes never make an unreadable page shareable', () => {
  const full = [[{ x: 0, y: 0, w: 1, h: 1 }]];
  // A photo, a scan or a CAD raster: no text layer. Held, even when the client "covered" everything.
  assert(!supplierPageReadable({ runs: [] }), 'scan page');
  assert(!supplierPageReadable(undefined), 'image upload with no PDF at all');
  assert(!supplierPageReadable({ runs: [{}], rotate: 90 }), 'rotated page');
  // The server's own detection was not confident: client boxes are ignored, the answer is HOLD.
  assertEquals(supplierBoxes({ boxes: [[]], confidence: 'low', residual: [] }, full, 1), null);
  assertEquals(supplierBoxes({ boxes: [[]], confidence: 'medium', residual: ['seed:mansoori'] }, full, 1), null);
  // Confident: the server's boxes are always applied; a client's tiny or empty boxes cannot remove them.
  const server = [[{ x: 0.7, y: 0.8, w: 0.3, h: 0.2 }]];
  assertEquals(supplierBoxes({ boxes: server, confidence: 'medium', residual: [] }, [[]], 1), server);
  assertEquals(supplierBoxes({ boxes: server, confidence: 'medium', residual: [] }, null, 1), server);
});

Deno.test('TRUST BOUNDARY: tampered or skipped client OCR cannot put the customer in front of a supplier', () => {
  // Tampered: OCR text that names the customer is gated like any other text.
  const tampered = redactBoq(boqFromExtracted(empty('image'), '', 'Tiles for Ahmed Al Mansoori villa 120 sqm\nCall +971 50 123 4567'), SEEDS);
  assert(tampered.held || !LEAK.test(JSON.stringify(tampered.boq)), 'tampered OCR leaked');
  // Skipped: no OCR text means no BOQ lines, so there is nothing to share, and the page itself is held.
  assertEquals(boqFromExtracted(empty('image')).boq.length, 0);
  assert(!supplierPageReadable(undefined));
});
