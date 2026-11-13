// A DRAWING REACHES A SUPPLIER WITH NO OWNER, NO AREA AND NO MAP (13 Nov 2026, sales_engineer; founder ruling 1683:
// "Dubai in general is okay … Al Barsha and Villa 15 need to be hidden"). The anonymity audit of that day (auditor B)
// planted a pool drawing's owner, villa, area, street, plot, Makani, a key-plan picture, a watermark and a surveyor on
// every route a drawing takes to a supplier, and each case is here, offline, with the pool's own quoting content beside
// it so a fix that removes MORE than identity fails too.
//   L1  the anonymised CAD FILE kept model-space "MR ZZ DEMO OWNER", "AL BARSHA 2", "UNIT 1204", "373 1234";
//   L2  a key plan pasted as a picture reached suppliers readable;
//   L3  "VILLA 15", "UNIT 1204", "373 1234", "12345 67890" passed the drawing-text allow-list, and "AL BARSHA 2" on the site
//       plan survived whenever the file name did not say "Barsha";
//   L4  a 28-degree watermark was covered by its axis-aligned box (28% of the sheet), destroying Section A-A;
//   G1  the anonymised vector PDF was held by an embedded font's licence URL and "971" inside coordinates;
//   G2  an ASCII85+Flate PDF read as no text at all.
// deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/_shared/a_drawing_reaches_a_supplier_with_no_owner_no_area_no_map.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { drawingLocation, isDrawingContent } from './drawing_text_policy.ts';
import { renderCadForSupplierSync } from './cad_render.ts';
import { redactCadFile, verifyCadRedaction } from './cad_file_redact.ts';
import { seedTerms, titleBlockBoxes } from './anonymise.ts';
import { pdfPages } from './pdf_text_positions.ts';
import { readerStrings, redactPdfVector, verifyPdfRedaction } from './pdf_vector_redact.ts';
import { ascii85, asciiHex, decodePdfStream, lzw, runLength } from './pdf_filters.ts';
import { POOL_ACCOUNT, POOL_CONTENT, POOL_DXF_CONTENT, POOL_DXF_IDENTITY, POOL_FILE_NAME, POOL_IDENTITY, zzPoolDxf, zzPoolPdf } from './doc_read/zz_demo_drawings.fixtures.ts';

const SEEDS = seedTerms({ ...POOL_ACCOUNT, extra: [POOL_FILE_NAME] });            // the account is NOT the owner
const B1 = () => Deno.readFile(new URL('./testdata/zz_pool_b1_embedded_font.pdf', import.meta.url));
const B1_A85 = () => Deno.readFile(new URL('./testdata/zz_pool_b1_ascii85_flate.pdf', import.meta.url));
const flat = (s: string) => s.replace(/\s+/g, ' ').toUpperCase();

Deno.test('L3: a place below the emirate is never drawing content; the pool\'s levels, schedule and notes are', () => {
  // 13 Nov 2026 review item 10: "UNIT 1204", "TOWER B", "BUILDING A" are no longer the code's to withhold (high precision):
  // the model reads them (drawing_string_reading.ts, drawing_pixel_gate.ts). Coordinates and "V-15" are (item 5).
  for (const t of ['VILLA 15', 'E 492 310.25 N 2 778 104.60', '25.1134 N, 55.2006 E', 'V-15', 'ARJAN', 'AL WARQAA 1', 'DUBAILAND', '373 1234', '373-1234', '12345 67890', 'AL BARSHA 2', 'STREET 23B', '23B STREET', 'STREET 23B, AL BARSHA 2', 'Umm Suqeim Rd', 'JUMEIRAH 1',
    'NEAR MALL OF THE EMIRATES', 'PLOT 373', 'فيلا 15', 'البرشاء', '(Survey by ZZ Demo Surveyors, Al Barsha 2)']) {
    assert(!isDrawingContent(t), `"${t}" passed as drawing content`);
  }
  for (const t of [...POOL_DXF_CONTENT, 'SHALLOW END  WL +0.00  FFL -1.20', 'CIRCULATION PUMP 1.5 HP 230V', 'SALT CHLORINATOR 25 G/H', '15 m3/h', 'MAIN DRAIN MD-1 (ANTI-VORTEX)',
    'UWL-1', 'P-1', 'TOC', 'IL -1.95', 'TOW +0.30', '3. WATERPROOFING: CEMENTITIOUS CRYSTALLINE 2 COATS + PU MEMBRANE.', 'OFFICE 101', 'FAN COIL UNIT 12', '3000 4500', 'DUBAI', 'UNIT 1200 W', 'TOWER B', 'BUILDING A']) {
    assert(isDrawingContent(t), `"${t}" was withheld`);
  }
  assertEquals(drawingLocation('DUBAI'), null, 'the emirate alone may cross');
});

Deno.test('L1: the CAD FILE keeps exactly what the preview draws: no owner, villa, unit, phone, Makani or area; every level', async () => {
  const dxf = zzPoolDxf();
  const g = renderCadForSupplierSync(dxf, { seeds: SEEDS });
  assert(g.ok);
  assertEquals(POOL_DXF_IDENTITY.filter((s) => g.drawn_texts.map(flat).includes(s)), [], 'the preview draws no identity');
  assertEquals(POOL_DXF_CONTENT.filter((s) => !g.drawn_texts.map(flat).includes(s)), [], 'the preview draws every level and note');
  const r = await redactCadFile(dxf, SEEDS);
  assert(r.ok, JSON.stringify(r));
  assertEquals(POOL_DXF_IDENTITY.filter((s) => r.dxf.includes(s)), [], 'identity left in the supplier\'s DXF');
  assertEquals(POOL_DXF_CONTENT.filter((s) => !r.dxf.includes(s)), [], 'content lost from the supplier\'s DXF');
  const v = await verifyCadRedaction(r.before_dxf, r.dxf, SEEDS, r);
  assert(v.ok, v.problems.join('; '));
  // The cause returning (the deny-list file: the original's text) is caught by the subset proof.
  const back = await verifyCadRedaction(r.before_dxf, r.dxf.replace('\nPOOL FINISH GLASS MOSAIC TILES 25X25', '\nAL BARSHA 2'), SEEDS, r);
  assert(!back.ok && back.problems.some((p) => /not drawn on the preview/.test(p)), back.problems.join('; '));
});

Deno.test('G2: a PDF written through ASCII85 (+Flate) is read as text, not sent down the scan route', async () => {
  const pp = await pdfPages(await B1_A85(), undefined, { layers: false });
  assertEquals(pp[0].runs.length, 121);
  const syn = await pdfPages(zzPoolPdf({ a85: true }), undefined, { layers: false });
  assert(syn[0].runs.some((r) => r.text === 'SECTION A-A SCALE 1:50'), 'the synthetic ASCII85 sheet reads');
  const enc = new TextEncoder();
  assertEquals(new TextDecoder().decode(ascii85(enc.encode('87cURD]i,"Ebo80~>'))), 'Hello World!');
  assertEquals(new TextDecoder().decode(asciiHex(enc.encode('48 65 6C6C6F>'))), 'Hello');
  assertEquals([...runLength(new Uint8Array([2, 65, 66, 67, 254, 68, 128]))], [65, 66, 67, 68, 68, 68]);
  // LZW of "-----A---B" from the PDF reference (7.4.4.2): 80 0B 60 50 22 0C 0C 85 01
  assertEquals(new TextDecoder().decode(lzw(new Uint8Array([0x80, 0x0b, 0x60, 0x50, 0x22, 0x0c, 0x0c, 0x85, 0x01]))), '-----A---B');
  assertEquals(await decodePdfStream('/Filter /DCTDecode', new Uint8Array([1])), null, 'an image codec is never guessed at');
});

Deno.test('L2 + L3 + L4: the title-block boxes cover the key plan, the site plan\'s area and the surveyor, and a watermark only along its own line', async () => {
  const pp = await pdfPages(await B1(), undefined, { layers: false });
  const tb = titleBlockBoxes(pp, SEEDS);
  assertEquals(tb.confidence, 'medium', tb.residual.join('; '));
  const p = pp[0];
  const cx = (r: { x: number; w: number }) => r.x + r.w / 2, cy = (r: { y: number; h: number }) => r.y + r.h / 2;
  const coveredAt = (x: number, y: number) => tb.boxes[0].some((b) => x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h);
  for (const s of ['AL BARSHA 2', 'STREET 23B, AL BARSHA 2', 'VILLA 15', 'KEY PLAN']) {
    const r = p.runs.find((x) => x.text.trim() === s)!; assert(r && coveredAt(cx(r), cy(r)), `${s} not covered`);
  }
  const survey = p.runs.find((x) => /Surveyors/.test(x.text))!; assert(coveredAt(cx(survey), cy(survey)), 'the surveyor note is not covered');
  const map = p.images!.find((im) => im.w * im.h > 0.02)!;
  assert(tb.boxes[0].some((b) => b.x <= map.x && b.y <= map.y && b.x + b.w >= map.x + map.w && b.y + b.h >= map.y + map.h), 'the key plan picture is not covered whole');
  // Section A-A and the pool's notes are not under any box (the watermark's axis-aligned box covered them).
  for (const s of ['SECTION A-A  SCALE 1:50', 'DEPTH 1200', 'DEPTH 1800', 'RC WALL 250 THK C40, 2 LAYERS T16@150', 'EQUIPMENT SCHEDULE', 'GENERAL NOTES', 'SITE PLAN (NTS)']) {
    const r = p.runs.find((x) => x.text.trim() === s)!; assert(r && !coveredAt(cx(r), cy(r)), `${s} is under a box`);
  }
  // The watermark is covered along its line, and the boxes outside the strip and the key plan stay a small share of the sheet.
  const wm = p.runs.find((x) => /CONFIDENTIAL/.test(x.text))!;
  assert(wm.quad, 'the watermark run carries its quad');
  const strip = tb.strips[0]!;
  let ink = 0; for (let i = 0; i < 200; i++) for (let j = 0; j < 140; j++) { const x = (i + 0.5) / 200, y = (j + 0.5) / 140; if (x < strip.x && coveredAt(x, y)) ink++; }
  assert(ink / (200 * 140) < 0.16, `outside the strip ${(100 * ink / 28000).toFixed(1)}% of the sheet is black (was 28% from the watermark alone)`);
});

Deno.test('G1 + L2: the vector PDF is released, with no map, no location, no owner, no watermark firm, and all the pool', async () => {
  const bytes = await B1();
  const r = await redactPdfVector(bytes, SEEDS);
  assert(r.ok, JSON.stringify(r));
  const v = await verifyPdfRedaction(bytes, r.bytes, SEEDS);
  assert(v.ok, v.problems.join('; '));
  assert(r.removed_images >= 1, 'the key plan picture is cut');
  const after = await pdfPages(r.bytes, undefined, { layers: false });
  assertEquals(after[0].images?.length ?? 0, 0, 'no picture is left on the sheet');
  const text = flat((await readerStrings(r.bytes)) + '\n' + after[0].runs.map((x) => x.text).join('\n'));
  assertEquals(['VILLA 15', 'BARSHA', 'STREET 23B', 'ZZ DEMO', 'CORAL', 'SURVEYOR', '373-1234', '12345 67890', '050 123', 'EXAMPLE.INVALID', 'CONFIDENTIAL'].filter((s) => text.includes(s)), []);
  for (const s of ['POOL PLAN SCALE 1:50', 'SECTION A-A SCALE 1:50', 'SHALLOW END WL +0.00 FFL -1.20', 'DEEP END FFL -1.80', 'DEPTH 1800', 'EQUIPMENT SCHEDULE', 'CIRCULATION PUMP 1.5 HP 230V',
    'GENERAL NOTES', '2. COPING: TRAVERTINE 600X300X30 MM, BULLNOSE EDGE.', 'SITE PLAN (NTS)', '10000', '5000']) assert(text.includes(s), `${s} lost`);
});

Deno.test('the synthetic pool sheet: identity outside the strip, a key-plan picture, a vector logo and QR, a watermark - all gone, the pool kept', async () => {
  for (const a85 of [false, true]) {
    const bytes = zzPoolPdf({ watermark: true, a85 });
    const r = await redactPdfVector(bytes, SEEDS);
    assert(r.ok, JSON.stringify(r));
    const v = await verifyPdfRedaction(bytes, r.bytes, SEEDS);
    assert(v.ok, v.problems.join('; '));
    const after = await pdfPages(r.bytes, undefined, { layers: false });
    const text = flat((await readerStrings(r.bytes)) + '\n' + after[0].runs.map((x) => x.text).join('\n'));
    assertEquals(POOL_IDENTITY.map(flat).filter((s) => text.includes(s)), [], `identity left (a85 ${a85})`);
    assertEquals(POOL_CONTENT.map(flat).filter((s) => !text.includes(s)), [], `content lost (a85 ${a85})`);
    assertEquals(after[0].images?.length ?? 0, 0, 'the key plan picture is cut');
    assert(r.removed_paths > 0, 'the vector logo and QR are cut');
  }
});

Deno.test('I1: the code floor under the vision models covers what a lazy model missed; a picture with no text layer is held for the scan route', async () => {
  const { codeFloorBoxes } = await import('./drawing_code_floor.ts');
  assertEquals(codeFloorBoxes(undefined, SEEDS), null, 'a scan or photo is never published on the models\' word alone');
  assertEquals(codeFloorBoxes({ width: 1, height: 1, rotate: 0, runs: [] }, SEEDS), null);
  const pp = await pdfPages(await B1(), undefined, { layers: false });
  const floor = codeFloorBoxes(pp[0], SEEDS)!;
  const at = (s: string) => { const r = pp[0].runs.find((x) => x.text.includes(s))!; const x = r.x + r.w / 2, y = r.y + r.h / 2; return floor.some((b) => x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h); };
  for (const s of ['AL BARSHA 2', 'VILLA 15', 'Surveyors', 'KEY PLAN', 'For site access', 'MR ZZ DEMO OWNER']) assert(at(s), `${s} is not under the code floor`);
  for (const s of ['SECTION A-A', 'DEPTH 1800', 'EQUIPMENT SCHEDULE']) assert(!at(s), `${s} is under the code floor`);
});
