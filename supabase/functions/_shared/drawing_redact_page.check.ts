// drawing_redact_page — the page a supplier receives, checked PIXEL BY PIXEL: every identity run of the drawing
// under solid black, every room name, dimension, tag and legend line still inked, and a JPEG that carries no
// text layer, no metadata and no identity bytes (24 Sep 2026, sales_engineer; founder instructions 580, 703).
//
//   deno test --no-lock --node-modules-dir=auto --allow-read=. --allow-net=deno.land \
//     supabase/functions/_shared/drawing_redact_page.check.ts
//
// WHY A .check.ts AND ITS OWN CI STEP (.github/workflows/checks.yml). drawing_redact decodes and encodes with
// imagescript 1.2.17, whose Deno build fetches its codec .wasm from deno.land when it is imported; the
// `npm test` Deno suite grants no network, so this file is run by its own step with --allow-net=deno.land,
// the same way dwg_samples.check.ts is. The drawing decisions themselves (which runs are boxed, what a CAD
// page draws) are proved offline in cad_render.test.ts and drawing_boq/every_drawing_format.test.ts.
//
// THE RASTER. The portal rasterises a PDF page with pdf.js in the customer's browser. Here each text run of
// the synthetic sheet is inked as grey stripes at its own position on a white page of the portal's width —
// the same geometry, with ink that cannot be mistaken for a redaction box (stripes are grey, boxes are black).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { Image } from 'https://deno.land/x/imagescript@1.2.17/mod.ts';
import { cadPage, MAXW, serverBoxedPage, supplierPagePrefix } from './drawing_redact_page.ts';
import { pdfPages, type PdfPage, type TextRun } from './pdf_text_positions.ts';
import { seedTerms, titleBlockBoxes } from './anonymise.ts';
import { supplierBoxes } from './supplier_copy.ts';
import { CONTENT, CUSTOMER, FILE_NAME, IDENTITY, PDF_TITLE, zzDxf, zzPdfScan, zzPdfSet, zzPdfSheet } from './doc_read/zz_demo_drawings.fixtures.ts';

const seeds = seedTerms({ ...CUSTOMER, extra: [FILE_NAME] });
const INK = 96;
const isIdentityRun = (r: TextRun) => PDF_TITLE.includes(r.text) || /zz\.site|CONSULTANT:|^ZZ DEMO ORBIT$/.test(r.text) || /^[A-Z]-\d\.\d{2}$/.test(r.text);
const isContentRun = (r: TextRun) => CONTENT.includes(r.text) || /^(FD|WC|FCU)-\d$/.test(r.text) || /^(OFFICE|MEETING ROOM|STORE) \d{3}$/.test(r.text);
const hasApp1 = (jpg: Uint8Array) => { for (let i = 2; i + 1 < Math.min(jpg.length, 8192); i++) if (jpg[i] === 0xff && jpg[i + 1] === 0xe1) return true; return false; };

/** The portal's raster of one page: white, each run inked as grey stripes over its box. */
async function raster(p: PdfPage): Promise<Uint8Array> {
  const W = MAXW, H = Math.round(MAXW * p.height / p.width);
  const img = new Image(W, H); img.fill(0xffffffff);
  const grey = Image.rgbaToColor(INK, INK, INK, 255);
  for (const r of p.runs) {
    const x0 = Math.floor(r.x * W), y0 = Math.floor(r.y * H), x1 = Math.ceil((r.x + r.w) * W), y1 = Math.ceil((r.y + r.h) * H);
    for (let y = y0; y < y1; y += 2) for (let x = x0; x < x1; x++) if (x >= 0 && y >= 0 && x < W && y < H) img.setPixelAt(x + 1, y + 1, grey);
  }
  return await img.encode();
}
/** Share of a run's pixels (inset one pixel) that are pure black, on the painted image. */
function blackShare(img: Image, r: TextRun): number {
  const W = img.width, H = img.height;
  const x0 = Math.floor(r.x * W) + 1, y0 = Math.floor(r.y * H) + 1, x1 = Math.ceil((r.x + r.w) * W) - 1, y1 = Math.ceil((r.y + r.h) * H) - 1;
  let n = 0, b = 0;
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) { n++; const k = (y * W + x) * 4; if (img.bitmap[k] === 0 && img.bitmap[k + 1] === 0 && img.bitmap[k + 2] === 0) b++; }
  return n ? b / n : 0;
}

for (const [name, make] of [['one vector sheet', zzPdfSheet], ['a 3-sheet set', zzPdfSet]] as const) {
  Deno.test(`PDF, ${name}: every identity run is under solid black, every content run is still inked, the JPEG carries nothing else`, async () => {
    const bytes = make();
    const pages = await pdfPages(bytes, undefined, { layers: false });
    const tb = titleBlockBoxes(pages, seeds);
    const boxes = supplierBoxes(tb, null, pages.length);
    assert(boxes, `the server could not box the title block (confidence ${tb.confidence}, residual ${tb.residual.join('; ')}): the page would be held`);
    let identityRuns = 0, contentRuns = 0;
    for (let i = 0; i < pages.length; i++) {
      const r = await serverBoxedPage(await raster(pages[i]), pages, i, boxes![i]);
      assert(r.ok, `page ${i + 1} was held: ${!r.ok && r.skipped}`);
      if (!r.ok) continue;
      for (const run of pages[i].runs) {
        if (isIdentityRun(run)) { identityRuns++; assertEquals(blackShare(r.image, run), 1, `page ${i + 1}: identity run "${run.text}" is not fully covered`); }
        else if (isContentRun(run)) { contentRuns++; assert(blackShare(r.image, run) < 0.5, `page ${i + 1}: content run "${run.text}" was blacked out`); }
      }
      assertEquals([r.jpg[0], r.jpg[1]], [0xff, 0xd8]);
      assert(!hasApp1(r.jpg), 'the JPEG carries an APP1 (EXIF / XMP) segment');
      const latin = new TextDecoder('latin1').decode(r.jpg);
      for (const id of [...IDENTITY, 'Orbit Consulting', 'Harbour Tower E-101']) assert(!latin.includes(id), `"${id}" survives in the JPEG bytes (text layer or /Info metadata)`);
    }
    assert(identityRuns >= 9 * (name === 'one vector sheet' ? 1 : 3) - 3, `too few identity runs were checked (${identityRuns})`);
    assert(contentRuns >= 10, `too few content runs were checked (${contentRuns})`);
  });
}

Deno.test('a scanned PDF and a photo are HELD: no text layer, so no box can be proved, whatever boxes arrive', async () => {
  const scan = await pdfPages(zzPdfScan(), undefined, { layers: false });
  assertEquals(scan[0].runs.length, 0);
  const img = new Image(400, 300); img.fill(0xffffffff);
  const png = await img.encode();
  const a = await serverBoxedPage(png, scan, 0, [{ x: 0.8, y: 0, w: 0.2, h: 1 }]);
  assertEquals(a.ok ? 'published' : a.skipped, 'held_unverifiable_client_boxes_ignored');
  const b = await serverBoxedPage(png, [], 0, []);
  assertEquals(b.ok ? 'published' : b.skipped, 'held_unverified_no_text_no_boxes');
  const c = await serverBoxedPage(png, scan, 0, null);
  assertEquals(c.ok ? 'published' : c.skipped, 'not_reviewed_by_customer');
});

Deno.test('a CAD drawing becomes one JPEG with no metadata and no identity bytes, at the portal\'s width', async () => {
  const r = await cadPage(zzDxf(), seeds);
  assert(r.ok, `held: ${!r.ok && r.skipped}`);
  if (!r.ok) return;
  assertEquals(r.image.width, MAXW);
  assert(!hasApp1(r.jpg));
  const latin = new TextDecoder('latin1').decode(r.jpg);
  for (const id of IDENTITY) assert(!latin.includes(id), id);
  const back = await Image.decode(r.jpg);
  assertEquals([back.width, back.height], [r.image.width, r.image.height]);
});

Deno.test('the stored path names nothing: only the namespace survives, the rest is a fresh UUID', () => {
  const p = supplierPagePrefix(`redacted/${FILE_NAME}/rashid.kareem@zzdemo.example.invalid/${Date.now()}`);
  assert(/^redacted\/[0-9a-f-]{36}\/page$/.test(p), p);
  assert(supplierPagePrefix('redacted') !== supplierPagePrefix('redacted'));
});
