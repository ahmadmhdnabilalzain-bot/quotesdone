// scan_redact — a SCANNED drawing, redacted by the real OCR engine (tesseract.js 7.0.0, the repository's own
// eng language data) with no model: the title block blacked out, the rooms, dimensions and legend kept, and a
// page OCR cannot read in its title block HELD (24 Sep 2026, sales_engineer; founder instructions 579, 580, 703).
//
//   deno test --no-lock --node-modules-dir=auto --allow-read=. --allow-env --allow-net=deno.land \
//     supabase/functions/_shared/scan_redact.check.ts
//
// WHY A .check.ts: the OCR engine runs in a worker thread and needs --allow-env, and the CAD worker's JPEG codec
// (imagescript) fetches its .wasm from deno.land, neither of which the `npm test` Deno suite grants. .github/workflows/checks.yml runs it as its own step. The decisions without the engine are in
// scan_redact.test.ts (the npm test suite).
//
// THE PAGE: doc_read/zz_demo_drawings.fixtures.ts zzScanRgba. It is the ZZ DEMO job drawn as a raster with no text
// layer, turned 0.6 degrees and speckled like a scanner's output, with the title block down the right-hand side.
// Nothing real, nothing sent anywhere.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { redactScan, rgbaToBmp, type Rgba } from './scan_redact.ts';
import { seedTerms } from './anonymise.ts';
import { CUSTOMER, FILE_NAME, zzScanRgba } from './doc_read/zz_demo_drawings.fixtures.ts';
import { tesseractOcr } from '../../../scripts/lib/scan_ocr.ts';
import { scanDrawing } from '../../../scripts/cad_read_worker.ts';
import { Image } from 'https://deno.land/x/imagescript@1.2.17/mod.ts';

const seeds = seedTerms({ ...CUSTOMER, extra: [FILE_NAME] });
const IDENTITY_OCR = /ZZ|ORBIT|RASHID|KAREEM|HARBOUR|EXAMPLE|INVALID|0017|DRAFTER|CLIENT|PROJECT|DRAWN|TEL/i;
const blackShare = (img: Rgba, x0: number, y0: number, x1: number, y1: number) => {
  let n = 0, b = 0;
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) { n++; const k = (y * img.w + x) * 4; if (img.rgba[k] === 0 && img.rgba[k + 1] === 0 && img.rgba[k + 2] === 0) b++; }
  return b / n;
};

Deno.test({ name: 'a scanned sheet: the title block is black, the plan survives, and a second OCR of the result reads no identity', sanitizeResources: false, sanitizeOps: false, fn: async () => {
  const e = await tesseractOcr('eng+ara');
  try {
    const r = await redactScan(zzScanRgba({ rotateDeg: 0.6, noise: 0.002 }), e.ocr, seeds);
    assert(r.ok, `held: ${!r.ok && r.held} ${!r.ok && JSON.stringify(r.detail)}`);
    if (!r.ok) return;
    // The title strip (x 1940 to the frame, full height, allowing the 0.6 degree turn) is solid black.
    assert(blackShare(r.image, 1990, 80, 2500, 1320) > 0.99, 'the title block is not fully blacked out');
    // The plan is not: the room names, the dimension and the legend are still on white.
    const content: [string, number, number, number, number][] = [['OFFICE 101', 255, 370, 600, 430], ['MEETING ROOM 102', 845, 375, 1300, 435], ['6000', 385, 660, 500, 715], ['LEGEND', 95, 850, 330, 910]];
    for (const [name, x0, y0, x1, y1] of content) {
      assert(blackShare(r.image, x0, y0, x1, y1) < 0.2, `"${name}" was blacked out`);
    }
    // Read again as a supplier's OCR would: the content is there, the identity is not.
    const text = (await e.ocr(rgbaToBmp(r.image))).map((l) => l.text).join('\n');
    for (const c of ['OFFICE', 'MEETING', 'LEGEND', 'SMOKE DETECTOR', 'SOCKET']) assert(text.includes(c), `"${c}" is not readable on the redacted page:\n${text}`);
    assertEquals(text.split('\n').filter((l) => IDENTITY_OCR.test(l)), [], 'identity is still readable on the redacted page');
  } finally { await e.done(); }
} });

Deno.test({ name: 'a title block OCR cannot read confidently is HELD, never passed', sanitizeResources: false, sanitizeOps: false, fn: async () => {
  const e = await tesseractOcr('eng+ara');
  try {
    // Measured 24 Sep 2026 on this sheet: the clean title block reads at a mean confidence of 83; speckled at 6%
    // it still reads (the strip is found) at 62, under MIN_TITLE_CONF 70, and is held for exactly that reason.
    // Speckled harder (10% and up) OCR no longer finds the title block at all, and the page is held as
    // no_title_block_found: both are holds.
    const r = await redactScan(zzScanRgba({ rotateDeg: 0.6, noise: 0.002, titleNoise: 0.06 }), e.ocr, seeds);
    assertEquals(r.ok ? 'published' : r.held, 'title_block_low_confidence');
    const worse = await redactScan(zzScanRgba({ rotateDeg: 0.6, noise: 0.002, titleNoise: 0.2 }), e.ocr, seeds);
    assertEquals(worse.ok ? 'published' : worse.held, 'no_title_block_found');
  } finally { await e.done(); }
} });

Deno.test({ name: 'a scanned sheet with no title block to be found is HELD (identity may be anywhere)', sanitizeResources: false, sanitizeOps: false, fn: async () => {
  const e = await tesseractOcr('eng+ara');
  try {
    const r = await redactScan(zzScanRgba({ rotateDeg: 0.6, noise: 0.002, noTitle: true }), e.ocr, seeds);
    assertEquals(r.ok ? 'published' : r.held, 'no_title_block_found');
  } finally { await e.done(); }
} });

// THE WORKER'S OWN PATH (scripts/cad_read_worker.ts scanDrawing): the stored page is downloaded, OCR-redacted with
// eng + ara, encoded, uploaded under redacted/<uuid>/ and recorded as ONE complete run naming exactly those pages,
// the row signRedactedDrawings needs. Storage and the management API are replaced by a recorder: nothing here
// reaches production.
Deno.test({ name: 'the CAD worker publishes a proved-clean scan as one recorded run under redacted/, and records nothing for a held one', sanitizeResources: false, sanitizeOps: false, fn: async () => {
  const toJpg = async (o: Parameters<typeof zzScanRgba>[0]) => { const s = zzScanRgba(o); const im = new Image(s.w, s.h); im.bitmap.set(s.rgba); return await im.encodeJPEG(92); };
  const real = globalThis.fetch;
  const calls: { url: string; method: string; body: unknown }[] = [];
  let page: Uint8Array = new Uint8Array();
  globalThis.fetch = (async (u: string | URL | Request, init?: RequestInit) => {
    const url = String(u), method = init?.method || 'GET';
    if (url.includes('deno.land') || url.includes('jsr.io')) return real(u, init);
    calls.push({ url, method, body: init?.body });
    if (url.includes('/database/query')) return new Response('[]', { status: 200 });
    if (method === 'GET') return new Response(page as BodyInit, { status: 200 });
    return new Response('{}', { status: 200 });
  }) as typeof fetch;
  try {
    const job = { id: 'zz-job', customer_id: null, owner_email: 'qd-zz@example.invalid', source_path: 'drawings/zz/scan.pdf', file_name: 'ZZ DEMO scan.pdf', mime: 'application/pdf', attempts: 1, boq_in: null, why: 'scan_needs_ocr' };
    page = await toJpg({ rotateDeg: 0.6, noise: 0.002 });
    const ok = await scanDrawing(job, 'zz-key', ['drawings/zz/scan_page_1.jpg']);
    assertEquals(ok.redaction_complete, true, JSON.stringify(ok));
    const paths = ok.drawing_redacted_paths as string[];
    assertEquals(paths.length, 1);
    assert(/^redacted\/[0-9a-f-]{36}\/page_p0\.jpg$/.test(paths[0]), paths[0]);
    const up = calls.find((c) => c.method === 'POST' && c.url.includes('/storage/v1/object/drawing-files/redacted/'))!;
    const jpg = new Uint8Array(await (up.body as Blob).arrayBuffer());
    const back = await Image.decode(jpg);
    const black = (x0: number, y0: number, x1: number, y1: number) => { let n = 0, b = 0; for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) { n++; if (back.bitmap[(y * back.width + x) * 4] < 30) b++; } return b / n; };
    assert(black(2000, 100, 2480, 1300) > 0.97, 'the uploaded page does not have its title block covered');
    const insert = calls.filter((c) => c.url.includes('/database/query')).map((c) => String((JSON.parse(String(c.body || '{}')) as { query?: string }).query || '')).find((q) => q.includes('insert into public.drawing_redaction_runs'))!;
    assert(insert && insert.includes("'complete'") && insert.includes(paths[0]) && insert.includes('scan_ocr'), 'the run is not recorded as complete with its page');

    calls.length = 0;
    page = await toJpg({ rotateDeg: 0.6, noise: 0.002, titleNoise: 0.06 });
    const held = await scanDrawing(job, 'zz-key', ['drawings/zz/scan_page_1.jpg']);
    assertEquals([held.redaction_complete, held.held_reason], [false, 'scan_title_block_low_confidence']);
    assertEquals(calls.filter((c) => c.method === 'POST' && c.url.includes('/storage/')).length, 0, 'a held page was uploaded');
    assert(!calls.some((c) => String(c.body || '').includes('insert into public.drawing_redaction_runs')), 'a held page was recorded as a run');
  } finally { globalThis.fetch = real; }
} });
