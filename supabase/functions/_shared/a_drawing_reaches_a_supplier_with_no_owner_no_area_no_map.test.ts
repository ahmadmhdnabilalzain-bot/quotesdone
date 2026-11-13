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
import { PDFDocument, PDFRawStream, decodePDFRawStream } from 'https://esm.sh/pdf-lib@1.17.1';
import { drawingLocation, isDrawingContent } from './drawing_text_policy.ts';
import { renderCadForSupplierSync } from './cad_render.ts';
import { redactCadFile, verifyCadRedaction } from './cad_file_redact.ts';
import { cadStrings } from './drawing_string_reading.ts';
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

Deno.test('L1 + B: the CAD FILE and preview carry no identity the model marked or the rules know; every level stays', async () => {
  const dxf = zzPoolDxf();
  const strings = cadStrings(new TextDecoder().decode(dxf));
  const faithful = new Set(strings.filter((x) => POOL_DXF_IDENTITY.includes(x)));
  for (const [name, identity, gone] of [['faithful', faithful, POOL_DXF_IDENTITY], ['lazy', new Set<string>(), POOL_DXF_IDENTITY.filter((x) => x !== 'UNIT 1204')]] as const) {
    const g = renderCadForSupplierSync(dxf, { seeds: SEEDS, identity });
    assert(g.ok);
    assertEquals(gone.filter((s) => g.drawn_texts.map(flat).includes(s)), [], `${name}: the preview draws identity`);
    assertEquals(POOL_DXF_CONTENT.filter((s) => !g.drawn_texts.map(flat).includes(s)), [], `${name}: the preview lost a level or a note`);
    const r = await redactCadFile(dxf, SEEDS, { identity });
    assert(r.ok, JSON.stringify(r));
    if (!r.ok) continue;
    assertEquals(gone.filter((s) => r.dxf.includes(s)), [], `${name}: identity left in the supplier's DXF`);
    assertEquals(POOL_DXF_CONTENT.filter((s) => !r.dxf.includes(s)), [], `${name}: content lost from the supplier's DXF`);
    const v = await verifyCadRedaction(r.before_dxf, r.dxf, SEEDS, r, [], r.removed);
    assert(v.ok, v.problems.join('; '));
    // The cause returning (a removed string written back) is caught by the bytes proof.
    // A string only the MODEL marked ("UNIT 1204": no rule knows it) written back is caught by the bytes proof alone.
    const back = await verifyCadRedaction(r.before_dxf, r.dxf.replace('\nPOOL FINISH GLASS MOSAIC TILES 25X25', name === 'faithful' ? '\nUNIT 1204' : '\nVILLA 15'), SEEDS, r, [], r.removed);
    assert(!back.ok, `${name}: a removed string written back passed`);
  }
  // A lazy reader leaves only what no rule can read ("UNIT 1204" is the model's, review item 10); no reader, no file.
  assertEquals((await redactCadFile(dxf, SEEDS)).ok, false);
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
  // The trailer names no /Info and no /ID (a dangling /Info made poppler refuse the released v15 file, 13 Nov 2026).
  const tail = new TextDecoder('latin1').decode(r.bytes.subarray(r.bytes.length - 600));
  assert(!/\/Info\b|\/ID\b/.test(tail.slice(tail.lastIndexOf('trailer'))), 'the released file\'s trailer still names /Info or /ID');
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

// ── the independent review of 13 Nov 2026 (items 1, 2, 4, 5, 6, 7, 9, 11): the reviewer's own attack sheets ─────────────
// testdata/review_f3/*.pdf (ZZ DEMO, generated by the reviewer's make_attacks.py). Each is either HELD, or released with
// no planted string anywhere in its bytes - every stream decoded, font programs included - and its preview boxes cover
// every identity run the reader can see.
// Round 3 (13 Nov 2026): widened. The old pattern had no "ZZ DEMO" with a space, no "RASHID", and only "373-1234": v03's
// "HANDOVER TO MR ZZ DEMO RASHID" was released in the vector PDF and this test passed (drawing_identity_text.honorificPerson).
const PLANT = /barsha|kareem|rashid|villa ?15|arjan|warqaa|dubailand|492 310|25\.1134|V-15|coral|050 123|al khail|6512|373-?123\d|zz ?demo|umm suqeim|mirdif|makani/i;
async function everyByte(bytes: Uint8Array): Promise<string> {
  const doc = await PDFDocument.load(bytes, { updateMetadata: false });
  const parts = [new TextDecoder('latin1').decode(bytes)];
  for (const [, o] of doc.context.enumerateIndirectObjects()) if (o instanceof PDFRawStream) { try { parts.push(new TextDecoder('latin1').decode(decodePDFRawStream(o).decode())); } catch { /* undecodable */ } }
  return parts.join('\n');
}
const REVIEW = ['v00_control', 'v01_outlined_site_labels', 'v03_location_shapes', 'v05_document_strings', 'v05c_document_strings_area_only', 'v06_unused_form_and_pattern',
  'v06c_unused_form_and_pattern_area_only', 'v08_inline_image_swallows_text', 'v09_endstream_in_string', 'v12_type3_obfuscated', 'v17_keyplan_label_over_pool'];
Deno.test('review items 1-11: every attack sheet is held, or released with no planted string in any byte and its preview boxes over every identity run', async () => {
  const { anonymisedDrawingFile } = await import('./drawing_file_redact.ts');
  const { supplierBoxes } = await import('./supplier_copy.ts');
  const { textLayerBoxes } = await import('./drawing_identity_text.ts');
  const out: Record<string, string> = {};
  for (const n of REVIEW) {
    const bytes = await Deno.readFile(new URL(`./testdata/review_f3/${n}.pdf`, import.meta.url));
    const f = await anonymisedDrawingFile(bytes, SEEDS);
    if (f.ok) { const all = await everyByte(f.bytes); const m = all.match(PLANT); assert(!m, `${n}: released with "${m?.[0]}"`); }
    const pp = await pdfPages(bytes, undefined, { layers: false });
    const tb = titleBlockBoxes(pp, SEEDS);
    const boxes = supplierBoxes(tb, null, pp.length);
    if (boxes) {
      for (const [i, p] of pp.entries()) {
        const all = [...boxes[i], ...textLayerBoxes(pp, i).boxes];
        for (const r of p.runs) if (PLANT.test(r.text)) { const x = r.x + r.w / 2, y = r.y + r.h / 2; assert(all.some((b) => x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h), `${n}: preview leaves "${r.text}"`); }
      }
    }
    out[n] = `${f.ok ? 'released' : 'held'} / preview ${boxes ? 'boxed' : 'to the models'}`;
  }
  // The ones code CANNOT read are held from the code route (they go to the models): outlines (item 2), Type3 (item 2), a
  // map label over the pool with no picture (item 9).
  for (const n of ['v01_outlined_site_labels', 'v12_type3_obfuscated', 'v17_keyplan_label_over_pool']) assert(out[n].startsWith('held / preview to the models'), `${n}: ${out[n]}`);
  // Items 1 and 4: the owner line between two inline images, and after an "endstream" inside a string, is READ now.
  for (const [n, s] of [['v08_inline_image_swallows_text', /KAREEM/], ['v09_endstream_in_string', /KAREEM|BARSHA/]] as const) {
    const pp = await pdfPages(await Deno.readFile(new URL(`./testdata/review_f3/${n}.pdf`, import.meta.url)), undefined, { layers: false });
    assert(pp[0].runs.some((r) => s.test(r.text)), `${n}: the hidden line is still not read`);
  }
  // Item 9: the control sheet (and the quoting content) is untouched: released with the pool.
  assertEquals(out['v00_control'], 'released / preview boxed');
});

Deno.test('review item 7: a released file is judged on what a reader can find - a mutant readerStrings that reads nothing must fail this', async () => {
  const { anonymisedDrawingFile } = await import('./drawing_file_redact.ts');
  const f = await anonymisedDrawingFile(await B1(), SEEDS);
  assert(f.ok);
  if (!f.ok) return;
  const doc = await PDFDocument.load(f.bytes);
  doc.setTitle('Plot 6512, Arjan');                                       // a document string only readerStrings reads
  const dirty = await doc.save();
  assert((await readerStrings(dirty)).includes('Arjan'));
  const v = await verifyPdfRedaction(await B1(), dirty, SEEDS);
  assert(!v.ok, 'a document title naming the plot and the area passed');
});

Deno.test('review item 12: hostile streams are refused (null = hold) within a time and memory limit', async () => {
  const enc = (s: string) => new TextEncoder().encode(s);
  const deflate = async (b: Uint8Array) => new Uint8Array(await new Response(new Blob([b as BlobPart]).stream().pipeThrough(new CompressionStream('deflate'))).arrayBuffer());
  const t0 = Date.now();
  assertEquals(await decodePdfStream('/Filter /FlateDecode /DecodeParms << /Predictor 2 /Columns 0 >>', await deflate(new Uint8Array(1000))), null, 'predictor 2 with no columns');
  assertEquals(await decodePdfStream('/Filter /FlateDecode /DecodeParms << /Predictor 12 /Columns 1000000000 >>', await deflate(new Uint8Array(1000))), null);
  assertEquals(await decodePdfStream('/Filter /ASCII85Decode', enc('uuuuu~>')), null, 'an ASCII85 group past 32 bits');
  let b = enc('BT (VILLA 15) Tj ET'); for (let i = 0; i < 20; i++) b = await deflate(b);
  assertEquals(await decodePdfStream('/Filter [' + ' /FlateDecode'.repeat(20) + ']', b), null, 'a chain longer than MAX_CHAIN');
  const parts: BlobPart[] = []; const z = new Uint8Array(1 << 20); for (let i = 0; i < 80; i++) parts.push(z);
  const bomb = new Uint8Array(await new Response(new Blob(parts).stream().pipeThrough(new CompressionStream('deflate'))).arrayBuffer());
  const rss0 = Deno.memoryUsage().rss;
  assertEquals(await decodePdfStream('/Filter /FlateDecode', bomb), null, 'an 80 MB inflate is past the cap');
  assert(Deno.memoryUsage().rss - rss0 < 400e6, 'the bomb was held in memory');
  assert(Date.now() - t0 < 15_000, `hostile streams took ${Date.now() - t0} ms`);
});

Deno.test('review item 9 / L2: a key plan drawn as a FRAME of lines (no picture) is covered with its label; a label with nothing under it holds', async () => {
  const keyFrame = zzPoolPdf({ keyFrame: true });
  const pp = await pdfPages(keyFrame, undefined, { layers: false });
  const tb = titleBlockBoxes(pp, SEEDS);
  // The frame's middle (the map drawn as paths) is under a box, and a REGION (paths there are cut from the file).
  const mid = { x: 0.40 + 0.075, y: 0.80 + 0.07 };
  assert(tb.boxes[0].some((b) => mid.x >= b.x && mid.x <= b.x + b.w && mid.y >= b.y && mid.y <= b.y + b.h), 'the key-plan frame is not covered');
  assert(tb.regions[0].some((b) => mid.x >= b.x && mid.x <= b.x + b.w && mid.y >= b.y && mid.y <= b.y + b.h), 'the key-plan frame is not a region');
});

// ── SECOND REVIEW (13 Nov 2026) ──────────────────────────────────────────────────────────────────────────────────────
Deno.test('second review 4: a place is a place on EITHER list - the text side never switches the drawing gazetteer off', () => {
  // Measured on the merge with the text branch: ARJAN, DEIRA and JVC stopped being places (the text side reads a bare
  // label only after a "Location:" cue) and v03 was released with "ARJAN". This holds on this branch and on the merge.
  for (const p of ['ARJAN', 'DEIRA', 'JVC', 'AL BARSHA 2', 'UMM SUQEIM ROAD', 'VILLA 15', 'PLOT NO. 345']) assert(drawingLocation(p), `${p} is a place`);
  for (const c of ['PLOT BOUNDARY', 'STAIR 2', 'LEVEL 2', 'RAMP 1:8', 'DUBAI', 'TOWER CRANE', 'STREET LIGHT', 'FLAT ROOF']) assertEquals(drawingLocation(c), null, `${c} is drawing content`);
  const src = Deno.readTextFileSync(new URL('./drawing_location.ts', import.meta.url));
  assert(/SHARED_BELOW\(t, \{ drawing: true \}\)/.test(src), 'the text side is asked for its drawing reading');
  assert(/const m = t\.match\(GAZ_RE\) \|\| t\.match\(PREMISES_NO\)/.test(src), 'the local rules always run');
});

Deno.test('round 3, item 4: where the text side exports locationBelowEmirate, a place only IT knows is a drawing place too', async () => {
  // On this branch alone the export is absent and the local list answers (the test above). On the merge with the text
  // branch (measured 13 Nov 2026, merged with 1f450d57d) these labels are places only on the text side's list; a
  // drawing_location that stopped asking it (or asked without { drawing: true }) would release them.
  const it = await import('./identity_text.ts') as Record<string, unknown>;
  if (typeof it.locationBelowEmirate !== 'function') return;
  for (const p of ['DUBAI INVESTMENTS PARK', 'IMPZ', 'REMRAAM', 'SOBHA HARTLAND', 'VILLANOVA', 'AL KIFAF']) {
    assert((it.locationBelowEmirate as (t: string, o?: { drawing?: boolean }) => string[])(p, { drawing: true }).length, `${p}: the text side reads it`);
    assert(drawingLocation(p), `${p} is a place on a drawing`);
  }
});

Deno.test('second review 6: "PLOT BOUNDARY" is not a label, and two columns on one baseline are not one line', async () => {
  const { isLabelRun, textLayerBoxes } = await import('./drawing_identity_text.ts');
  for (const c of ['PLOT BOUNDARY', 'PROJECT LEVELS SHOWN IN M', 'CLIENT ROOM']) assert(!isLabelRun(c), c);
  for (const l of ['CLIENT:', 'CLIENT MR ZZ DEMO', 'PLOT NO 345', 'DRAWN BY A. DEMO', 'PROJECT TITLE', 'OWNER']) assert(isLabelRun(l), l);
  const page = { width: 1190, height: 842, rotate: 0, runs: [
    { text: 'PLOT BOUNDARY', x: 0.1, y: 0.5, w: 0.08, h: 0.01 }, { text: 'STAIR 2', x: 0.33, y: 0.5, w: 0.04, h: 0.01 },
    { text: 'CLIENT:', x: 0.8, y: 0.9, w: 0.04, h: 0.01 }, { text: 'MR ZZ DEMO', x: 0.85, y: 0.9, w: 0.06, h: 0.01 }] };
  const boxes = textLayerBoxes([page], 0).boxes;
  // Round 3: "MR ZZ DEMO" is also boxed on its own now (drawing_identity_text.honorificPerson), so the count is 2; what
  // matters is unchanged: the client line is covered, PLOT BOUNDARY and STAIR 2 are not touched.
  const touches = (r: { x: number; y: number; w: number; h: number }) => boxes.some((b) => b.x < r.x + r.w && b.x + b.w > r.x && b.y < r.y + r.h && b.y + b.h > r.y);
  const [plot, stair, client, name] = page.runs;
  assert(!touches(plot) && !touches(stair), 'PLOT BOUNDARY and STAIR 2 are content');
  assert(touches(client) && touches(name), 'the client label and its value are boxed');
  const { linesFromRuns } = await import('./pdf_text_positions.ts');
  const two = { ...page, runs: [{ text: 'FIRE ALARM PANEL FACP-1', x: 0.08, y: 0.3, w: 0.14, h: 0.0095 }, { text: 'ALL WORKS IN THE VILLA SHALL FOLLOW DCD', x: 0.315, y: 0.3, w: 0.22, h: 0.0095 }] };
  assertEquals(linesFromRuns([two]), 'FIRE ALARM PANEL FACP-1 ALL WORKS IN THE VILLA SHALL FOLLOW DCD', 'the default still joins a line');
  assertEquals(linesFromRuns([two], 0.003, 3), 'FIRE ALARM PANEL FACP-1\nALL WORKS IN THE VILLA SHALL FOLLOW DCD', 'a column gap cuts it');
  const near = { ...page, runs: [{ text: 'ZZ DEMO', x: 0.5, y: 0.3, w: 0.04, h: 0.0095 }, { text: 'CORAL LLC', x: 0.545, y: 0.3, w: 0.05, h: 0.0095 }] };
  assertEquals(linesFromRuns([near], 0.003, 3), 'ZZ DEMO CORAL LLC', 'a name split into two runs is still read whole');
});

Deno.test('second review 7: rows of text drawn as shapes in the title-block band are BOXED (v02), elsewhere they only lower confidence', async () => {
  const v02 = await pdfPages(await Deno.readFile(new URL('./testdata/review_f3/v02_outlined_title_block.pdf', import.meta.url)));
  const rows = v02[0].glyphRows ?? [];
  assertEquals(rows.length, 10);
  const tb = titleBlockBoxes(v02, SEEDS);
  const inside = (b: { x: number; y: number; w: number; h: number }, r: typeof rows[0]) => r.x >= b.x && r.y >= b.y && r.x + r.w <= b.x + b.w && r.y + r.h <= b.y + b.h;
  assert(rows.every((r) => tb.boxes[0].some((b) => inside(b, r))), 'every outlined title-block row is under a box');
  assert(tb.boxes[0].every((b) => b.x >= 0.6), 'the band box stays in the band');
  // The same rows in the middle of the sheet are the drawing's business: not boxed, but the sheet is not confident.
  const mid = [{ ...v02[0], glyphRows: rows.map((r) => ({ ...r, x: r.x - 0.5 })) }];
  const tm = titleBlockBoxes(mid, SEEDS);
  assertEquals(tm.confidence, 'low');
  assert(!mid[0].glyphRows!.every((r) => tm.boxes[0].some((b) => inside(b, r))));
});

Deno.test('round 3: a person named after an honorific is identity on every drawing route; mild steel, a door and a slab are not', async () => {
  // MEASURED 13 Nov 2026: v03's "HANDOVER TO MR ZZ DEMO RASHID" passed every rule and the released vector PDF kept it.
  const { honorificPerson } = await import('./drawing_identity_text.ts');
  const { namesParty } = await import('./drawing_text_policy.ts');
  for (const p of ['HANDOVER TO MR ZZ DEMO RASHID', 'CONTACT Mr. Ahmed Ali', 'MRS FATIMA', 'SHEIKH ZZ DEMO']) { assert(honorificPerson(p), p); assert(namesParty(p), p); }
  for (const c of ['MR SLAB +32.10', 'LIFT MR', 'MR ROOM', 'MS ANGLE 50x50x5', 'DR. FIXIT PRIMER', 'MRV-1', 'MR 2', 'MR LEVEL']) assert(!honorificPerson(c), c);
  const { anonymisedDrawingFile } = await import('./drawing_file_redact.ts');
  const f = await anonymisedDrawingFile(await Deno.readFile(new URL('./testdata/review_f3/v03_location_shapes.pdf', import.meta.url)), SEEDS);
  assert(f.ok);
  if (f.ok) { const all = await everyByte(f.bytes); assert(!/RASHID|MIRDIF/i.test(all), 'the released v03 names no person and no landmark'); }
  assertEquals(drawingLocation('NEAR CITY CENTRE MIRDIFF'), 'MIRDIFF');
});
