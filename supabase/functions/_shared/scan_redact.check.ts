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
import { CUSTOMER, FILE_NAME, zzLeakyDxf, zzScanRgba, zzScanText } from './doc_read/zz_demo_drawings.fixtures.ts';
import { renderCadForSupplier } from './cad_render.ts';
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
    // 13 Nov 2026 (design change A): the worker asks drawing_redact mode 'gate' about every page before it publishes it.
    // A clean first look returns the page as it is.
    if (url.includes('/functions/v1/drawing_redact')) { const b = JSON.parse(String(init?.body || '{}')); return new Response(JSON.stringify(b.mode === 'gate' ? { ok: true, jpg_b64: b.jpg_b64, pixel_calls: 1, first_look_clean: true } : { ok: false }), { status: 200 }); }
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

// Review of #967: a firm printed left of the title column, on the DRAWN BY row, was published and a re-OCR still
// read it. Company words, licence numbers and the title block's own names are now boxed page-wide, and the re-read
// matches seeds fuzzily. Either the firm is covered, or the page is held; it is never published readable.
Deno.test({ name: 'the review case: a firm left of the title column is covered (or the page held), never published readable', sanitizeResources: false, sanitizeOps: false, fn: async () => {
  const e = await tesseractOcr('eng+ara');
  try {
    // Measured 24 Sep 2026: with page-wide boxing the page PUBLISHES with the firm covered (15 boxes); without it the
    // fuzzy re-read holds it. Publishing is asserted, so a lost page-wide rule fails here rather than hiding in a hold.
    const r = await redactScan(zzScanRgba({ rotateDeg: 0.6, noise: 0.002, leftFirm: true }), e.ocr, seeds);
    assert(r.ok, `held: ${!r.ok && r.held} ${!r.ok && JSON.stringify(r.detail)}`);
    if (!r.ok) return;
    const text = (await e.ocr(rgbaToBmp(r.image))).map((l) => l.text).join('\n');
    assert(!/ORBIT|ENGINEERING/i.test(text), `the firm is still readable on the published page:\n${text}`);
    for (const c of ['OFFICE', 'LEGEND']) assert(text.includes(c), `"${c}" was lost`);
  } finally { await e.done(); }
} });

// SECOND REVIEW OF #967 (25 Sep 2026). Its probe scan.ts published a stamp "ZZ ORBIT ENGINEERING" turned 90 and 30
// degrees in the drawing body, a body note "BY ZZ OMEGA", and a speckled phone number, each still readable by OCR.
// Every case here must be HELD, or published with nothing a supplier's OCR can read at ANY orientation.
const turned = (img: Rgba, q: number): Rgba => {
  let t = img;
  for (let i = 0; i < q; i++) {
    const o = new Uint8ClampedArray(t.rgba.length);
    for (let y = 0; y < t.h; y++) for (let x = 0; x < t.w; x++) { const s = (y * t.w + x) * 4, d = (x * t.h + (t.h - 1 - y)) * 4; o[d] = t.rgba[s]; o[d + 1] = t.rgba[s + 1]; o[d + 2] = t.rgba[s + 2]; o[d + 3] = 255; }
    t = { w: t.h, h: t.w, rgba: o };
  }
  return t;
};
Deno.test({ name: 'second review: a turned stamp, a body note, a speckled phone and a name variant are held or unreadable every way up', sanitizeResources: false, sanitizeOps: false, fn: async () => {
  const e = await tesseractOcr('eng+ara');
  try {
    const cases: [string, (i: Rgba) => void, RegExp][] = [
      ['a body note "BY ZZ OMEGA"', (i) => zzScanText(i, 300, 1200, 26, 'BY ZZ OMEGA'), /OMEGA/i],
      ['a body note "ZZ OMEGA CONTRACTING"', (i) => zzScanText(i, 300, 1200, 26, 'ZZ OMEGA CONTRACTING'), /OMEGA|CONTRACT/i],
      ['a stamp turned 90 degrees', (i) => zzScanText(i, 1750, 1250, 22, 'ZZ ORBIT ENGINEERING', -90), /ORBIT|ENGINEER/i],
      ['a stamp turned 30 degrees', (i) => zzScanText(i, 1000, 1250, 22, 'ZZ ORBIT ENGINEERING', -30), /ORBIT|ENGINEER/i],
      ['a speckled phone "TEL 04 123 4567"', (i) => zzScanText(i, 300, 1200, 24, 'TEL 04 123 4567', 0, 0.12), /123|4567|TEL/i],
      ['the customer as "RASHEED KARIM"', (i) => zzScanText(i, 300, 1200, 26, 'RASHEED KARIM'), /RASHEED|KARIM/i],
    ];
    const outcome: string[] = [];
    for (const [name, add, id] of cases) {
      const img = zzScanRgba({ rotateDeg: 0.6, noise: 0.002 });
      add(img);
      const r = await redactScan(img, e.ocr, seeds);
      if (!r.ok) { outcome.push(`${name}: held ${r.held}`); continue; }
      for (const q of [0, 1, 2, 3]) {
        const text = (await e.ocr(rgbaToBmp(turned(r.image, q)))).map((l) => l.text).join('\n');
        assert(!id.test(text), `${name}: published and readable at ${q * 90} degrees:\n${text}`);
      }
      outcome.push(`${name}: published, unreadable every way up`);
    }
    console.log(outcome.join('\n'));
  } finally { await e.done(); }
} });

// The CAD page, re-read from its PIXELS by OCR: an independent extraction of what a supplier would see, on the
// review's crafted drawing (a CLIENT_NAME attribute in block ISO_A1, bare firm names, a dimension override, a
// licence number and a letter-spaced name).
Deno.test({ name: 'the CAD page of the review\'s crafted drawing, read back by OCR, shows the rooms and no party', sanitizeResources: false, sanitizeOps: false, fn: async () => {
  const g = await renderCadForSupplier(zzLeakyDxf(), { seeds });
  assert(g.ok, `the crafted drawing was held: ${!g.ok && g.reason}`);
  if (!g.ok) return;
  const e = await tesseractOcr('eng');
  try {
    const text = (await e.ocr(rgbaToBmp({ w: g.width, h: g.height, rgba: g.rgba }))).map((l) => l.text).join('\n');
    assert(/OFFICE/.test(text) && /CORRIDOR/.test(text), `the rooms are not readable:\n${text}`);
    assert(!/ORBIT|HARBOUR|HOLDING|123456|RASHID|KAREEM|K\s*A\s*R\s*E\s*E\s*M/i.test(text), `a party is readable on the CAD page:\n${text}`);
  } finally { await e.done(); }
} });
