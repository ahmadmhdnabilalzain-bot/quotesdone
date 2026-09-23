// Photos and scanned BOQs -> images and text, in the CUSTOMER'S BROWSER.
//
// WHY: the model/vision routes are on hold (no paid inference), and a Supabase Edge function gets
// ~2 s of CPU per request, too little for OCR. So free OCR runs here, on the customer's machine, and
// the server receives plain text it can parse deterministically.
//
// WHAT:
//   toJpegPages(file) -> base64 images for the existing drawing/image path. JPEG/PNG/WebP pass through
//     (downscaled if wider than 2400 px); HEIC/HEIF are decoded by the browser itself (Safari can,
//     most others cannot -> HEIC_UNSUPPORTED); TIFF is decoded with utif (MIT), up to 10 pages.
//   ocrImages(images) -> tesseract.js (Apache-2.0), 'eng+ara' by default, one worker reused across
//     up to 10 pages and terminated at the end. Returns the joined text and mean confidence (0-100).
//
// WHERE tesseract loads from: SELF-HOSTED under /public/ocr, same origin, so the CSP trusts no new
// host (see next.config.mjs). A CDN such as jsDelivr serves anything anyone publishes, and trusting it
// in script-src would let any package run on every page. Files, pinned and hashed (sha256, 14 Sep 2026):
//   /ocr/worker.min.js                            tesseract.js@7.0.0            111 KB
//     576b7df7e3393e137e51849357c9adb53fe7ac1bb69bfa06cf3d61520f182c6d
//   /ocr/core/tesseract-core-relaxedsimd-lstm.wasm.js  tesseract.js-core@7.0.0  3.9 MB
//   /ocr/core/tesseract-core-simd-lstm.wasm.js         tesseract.js-core@7.0.0  3.9 MB
//   /ocr/core/tesseract-core-lstm.wasm.js              tesseract.js-core@7.0.0  3.9 MB
//     (the worker's getCore loads exactly ONE of the three, by the browser's SIMD support; LSTM-only
//      because createWorker is called with OEM 1; hashes in public/ocr/SHA256SUMS)
//   /ocr/lang/eng.traineddata.gz   @tesseract.js-data/eng@1.0.0 4.0.0_best_int  2.95 MB
//     45b4cb346724ac1774f1c36f42f182b887bcdb28ebe63e6fff90ac41f3fcff91
//   /ocr/lang/ara.traineddata.gz   @tesseract.js-data/ara@1.0.0 4.0.0_best_int  1.66 MB
//     f4746c44b02342dd5b3d4f0198000f47d7c49f1a229e63e0f436c0592dcd9639
// FIRST USE costs the customer ~8.5 MB (111 KB worker + one 3.9 MB core + 4.6 MB language data); the
// browser caches it. None of it loads on page load: only when a photo or scan is attached.
//
// HEIC: heic2any was rejected. It bundles libheif (LGPL-3) and libheif's author disputes that
// bundling. iPhones already hand a JPEG to a file picker that does not list HEIC, so the fallback is
// a clear error, not a second decoder.
//
// WHAT IT NEVER DOES: it never uploads an image anywhere itself. The only network traffic is the
// tesseract code and language data coming IN. The OCR text is untrusted input: the server parses and
// scrubs it like anything else a customer types.
//
// Nothing here touches a browser API at import time; every library is a dynamic import, so the
// portal's main bundle does not grow until a customer actually attaches a photo or scan.

export type PageImage = { mime: string; data: string };

const MAX_WIDTH = 2400;
const MAX_PAGES = 10;
const JPEG_QUALITY = 0.85;

// Self-hosted, same-origin locations (absolute, because a worker resolves relative URLs against its own
// script). Bump the files together with package.json, never to a floating tag.
const ocrUrl = (p: string) => `${window.location.origin}/ocr/${p}`;

/** Thrown when the browser cannot decode a HEIC/HEIF photo. The UI maps it to "export as JPEG". */
export const HEIC_UNSUPPORTED = 'HEIC_UNSUPPORTED';

function canvasToJpeg(c: HTMLCanvasElement): PageImage {
  return { mime: 'image/jpeg', data: c.toDataURL('image/jpeg', JPEG_QUALITY).split(',')[1] };
}

function drawScaled(src: CanvasImageSource, w: number, h: number): HTMLCanvasElement {
  const s = Math.min(1, MAX_WIDTH / w);
  const c = document.createElement('canvas');
  c.width = Math.round(w * s); c.height = Math.round(h * s);
  const ctx = c.getContext('2d') as CanvasRenderingContext2D;
  ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, c.width, c.height); // transparent PNG -> white, not black
  ctx.drawImage(src, 0, 0, c.width, c.height);
  return c;
}

async function fileToBase64(file: Blob): Promise<string> {
  const buf = new Uint8Array(await file.arrayBuffer());
  let bin = '';
  for (let i = 0; i < buf.length; i += 0x8000) bin += String.fromCharCode(...buf.subarray(i, i + 0x8000));
  return btoa(bin);
}

export async function toJpegPages(file: File): Promise<PageImage[]> {
  const type = (file.type || '').toLowerCase();
  const name = file.name.toLowerCase();

  if (type === 'image/tiff' || /\.tiff?$/.test(name)) {
    // @ts-ignore utif ships no type declarations
    const mod: any = await import('utif');
    const UTIF = mod.default || mod;
    const buf = await file.arrayBuffer();
    const ifds = UTIF.decode(buf).slice(0, MAX_PAGES);
    const out: PageImage[] = [];
    for (const ifd of ifds) {
      UTIF.decodeImage(buf, ifd);
      const w = ifd.width, h = ifd.height;
      if (!w || !h) continue; // thumbnails / non-image IFDs
      const full = document.createElement('canvas');
      full.width = w; full.height = h;
      const ctx = full.getContext('2d') as CanvasRenderingContext2D;
      ctx.putImageData(new ImageData(new Uint8ClampedArray(UTIF.toRGBA8(ifd)), w, h), 0, 0);
      out.push(canvasToJpeg(w > MAX_WIDTH ? drawScaled(full, w, h) : full));
    }
    return out;
  }

  const heic = /^image\/hei[cf]/.test(type) || /\.hei[cf]$/.test(name);
  let bmp: ImageBitmap;
  try {
    bmp = await createImageBitmap(file);
  } catch (e) {
    if (heic) throw new Error(HEIC_UNSUPPORTED);
    throw e;
  }
  try {
    const passThrough = !heic && /^image\/(jpeg|png|webp)$/.test(type) && bmp.width <= MAX_WIDTH;
    if (passThrough) return [{ mime: type, data: await fileToBase64(file) }];
    return [canvasToJpeg(drawScaled(bmp, bmp.width, bmp.height))];
  } finally {
    bmp.close();
  }
}

// ── DRAWINGS (14 Sep 2026) ───────────────────────────────────────────────────────────────────────────
// ocrImages reads a page the way a document is read: one pass, the image as it is. On a drawing that
// read 0 of 70 device address tags on the founder's sample. ocrDrawing applies ocrPlan.ts — the plan
// measured on that sheet — and returns the lines WITH their page boxes (the server reads the title
// block by position), the sheet width, and the symbol counter's matches and per-type counts
// (supabase/functions/drawing_boq/symbol_count.ts, the same file the fixture test runs), which the
// portal draws as the marked-up copy (markup.ts). A phone runs only the first pass: the second costs
// another ~40% of the time for a few more tags.
export type DrawingOcr = {
  text: string;
  lines: { text: string; bbox: { x: number; y: number; w: number; h: number } }[];
  width: number; height: number;
  symbols: { counts: Record<string, number>; matches: { type: string; box: { x: number; y: number; w: number; h: number } }[] } | null;
  ms: number;
};

// vocab: what the drawing's printed lines NAME, reasoned on the server (customer_api drawing_vocabulary, decision point
// drawing_boq.vocabulary) — [printed text, device type] pairs. Without it (held, or offline) no legend row is taken as a
// device and no symbol is counted: nothing is decided here by reading a word.
export async function ocrDrawing(img: PageImage, opts?: { onProgress?: (p: number) => void; lite?: boolean; vocab?: (texts: string[]) => Promise<[string, string][] | null> }): Promise<DrawingOcr> {
  const t0 = Date.now();
  const plan = await import('./ocrPlan');
  const bmp = await createImageBitmap(await (await fetch(`data:${img.mime};base64,${img.data}`)).blob());
  const W0 = bmp.width, H0 = bmp.height;
  const { createWorker } = await import('tesseract.js');
  const worker = await createWorker('eng', 1, { workerPath: ocrUrl('worker.min.js'), corePath: ocrUrl('core'), langPath: ocrUrl('lang'), workerBlobURL: false });
  const passes = opts?.lite ? plan.OCR_PASSES.slice(0, 1) : plan.OCR_PASSES;
  const all: { text: string; bbox: { x: number; y: number; w: number; h: number }; pass: number }[] = [];
  let pixels: Uint8ClampedArray | null = null;
  try {
    const jobs = passes.map((p) => { const s = plan.scaleFor(p, W0, H0); return { p, s, tiles: plan.tiles(Math.round(W0 * s), Math.round(H0 * s), p.tile) }; });
    const total = jobs.reduce((n, j) => n + j.tiles.length, 0); let done = 0;
    for (let pi = 0; pi < jobs.length; pi++) {
      const { p, s, tiles } = jobs[pi];
      const W = Math.round(W0 * s), H = Math.round(H0 * s);
      const big = document.createElement('canvas'); big.width = W; big.height = H;
      const ctx = big.getContext('2d', { willReadFrequently: true }) as CanvasRenderingContext2D;
      ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, W, H); ctx.imageSmoothingQuality = 'high'; ctx.drawImage(bmp, 0, 0, W, H);
      const id = ctx.getImageData(0, 0, W, H);
      const g = plan.binarize(id.data, 4, W, H);
      for (let i = 0; i < g.length; i++) { const v = g[i]; id.data[i * 4] = v; id.data[i * 4 + 1] = v; id.data[i * 4 + 2] = v; id.data[i * 4 + 3] = 255; }
      ctx.putImageData(id, 0, 0);
      // deno-lint-ignore no-explicit-any
      await worker.setParameters({ tessedit_pageseg_mode: p.psm as any, user_defined_dpi: '300' } as any);
      for (const t of tiles) {
        const c = document.createElement('canvas'); c.width = t.w; c.height = t.h;
        (c.getContext('2d') as CanvasRenderingContext2D).drawImage(big, t.x, t.y, t.w, t.h, 0, 0, t.w, t.h);
        // deno-lint-ignore no-explicit-any
        const { data } = await worker.recognize(c, {}, { blocks: true } as any) as any;
        for (const b of data.blocks || []) for (const par of b.paragraphs || []) for (const ln of par.lines || []) {
          const bb = ln.bbox; all.push({ text: ln.text, pass: pi, bbox: { x: (t.x + bb.x0) / s, y: (t.y + bb.y0) / s, w: (bb.x1 - bb.x0) / s, h: (bb.y1 - bb.y0) / s } });
        }
        opts?.onProgress?.(++done / total);
      }
    }
    const c0 = document.createElement('canvas'); c0.width = W0; c0.height = H0;
    const x0 = c0.getContext('2d', { willReadFrequently: true }) as CanvasRenderingContext2D;
    x0.fillStyle = '#fff'; x0.fillRect(0, 0, W0, H0); x0.drawImage(bmp, 0, 0);
    pixels = x0.getImageData(0, 0, W0, H0).data;
  } finally { await worker.terminate(); bmp.close(); }
  const lines = plan.mergeLines(all).map(({ text, bbox }) => ({ text, bbox }));
  let symbols: DrawingOcr['symbols'] = null;
  try {
    const sc = await import('../../../supabase/functions/drawing_boq/symbol_count');
    const lv = await import('../../../supabase/functions/drawing_boq/legend_vocabulary');
    const pairs = opts?.vocab ? await opts.vocab([...new Set(lines.map((l) => l.text))].slice(0, 200)).catch(() => null) : null;
    const vocab = { ...lv.EMPTY_VOCAB, device: (pairs || []).map(([text, type]) => [text, lv.DEVICE_TYPES.find((d) => d.type === type)]).filter((e): e is [string, (typeof lv.DEVICE_TYPES)[number]] => !!e[1]) };
    const rows = vocab.device.length ? sc.legendRows(lines, W0, (t: string) => lv.deviceTypeIn(t, vocab)) : [];
    if (rows.length && pixels) { const r = sc.countSymbols({ w: W0, h: H0, px: pixels, channels: 4 }, rows); symbols = { counts: r.counts, matches: r.matches.map((m) => ({ type: m.type, box: m.box })) }; }
  } catch (_e) { symbols = null; }
  return { text: plan.linesToText(lines), lines, width: W0, height: H0, symbols, ms: Date.now() - t0 };
}

export async function ocrImages(
  images: PageImage[],
  opts?: { langs?: string; onProgress?: (p: number) => void },
): Promise<{ text: string; confidence: number; pages: number }> {
  const pages = images.slice(0, MAX_PAGES);
  if (!pages.length) return { text: '', confidence: 0, pages: 0 };
  const { createWorker } = await import('tesseract.js');
  let done = 0;
  const worker = await createWorker(opts?.langs || 'eng+ara', 1 /* LSTM only */, {
    workerPath: ocrUrl('worker.min.js'),
    corePath: ocrUrl('core'),
    langPath: ocrUrl('lang'),
    // Load the worker from its own URL (worker-src 'self') rather than a blob: bootstrap.
    workerBlobURL: false,
    logger: (m: { status: string; progress: number }) => {
      if (m.status === 'recognizing text') opts?.onProgress?.((done + m.progress) / pages.length);
    },
  });
  try {
    const texts: string[] = [];
    let conf = 0;
    for (const img of pages) {
      const { data } = await worker.recognize(`data:${img.mime};base64,${img.data}`);
      texts.push(data.text.trim());
      conf += data.confidence;
      done++;
      opts?.onProgress?.(done / pages.length);
    }
    return { text: texts.join('\n\n--- page break ---\n\n'), confidence: conf / pages.length, pages: pages.length };
  } finally {
    await worker.terminate();
  }
}

// ── SCHEDULES, CELL BY CELL (21 Sep 2026, sales_engineer, founder instruction 580) ───────────────────
// A drawing set's countable content sits in its schedules (RTU-1..3, EF-1..10, WC/L-1, FD-1...). On
// the two real US bid sets measured today they were raster images or vector strokes with no text
// layer, and ocrImages read the whole 36x24 sheet at ~72 dpi: 0 of 49 answer-key items, 4 invented BOQ
// lines. This renders EVERY page (up to PDF_MAX_PAGES) at reading resolution, finds the ruled tables
// (supabase/functions/_shared/table_grid.ts, pure, tested on a synthetic schedule and a floor plan),
// and OCRs each non-empty cell on its own, so the row/column structure survives: rows[r][c] is the
// text of grid cell (r, c), header rows included; a merged cell's text sits in its top-left grid cell
// and the cells it covers are ''. Grid columns and rows that came out empty everywhere are dropped.
//
// SETTINGS are measured on both real sets in a real browser; the numbers are at SCHEDULE_DPI and
// SCHEDULE_PSM. 'eng' only: every schedule on a drawing is Latin-script, and 'ara' only adds Arabic
// noise to a Latin page. Self-hosted paths exactly as ocrImages.
//
// CAPS (the server validates the same): 40 tables, 80 rows, 24 columns, 120 characters a cell.
export type ScheduleTable = {
  page: number; // 1-based
  bbox: { x: number; y: number; w: number; h: number }; // 0..1 of the displayed page, top-left origin
  rows: string[][];
  conf: number[][]; // 0-100 per cell; 0 for an empty cell
};
export const SCHEDULE_CAPS = { tables: 40, rows: 80, cols: 24, cell: 120 } as const;
export const SCHEDULE_DPI = 200;
// PSM 6 (a block) for every cell. MEASURED against 'auto' (PSM 7, one line, for a cell no taller than
// 1.6 rows): a tag or model printed on two lines in one cell ("RTU / 1", "UNISEX RR / 104") read as
// "RIV", "RH", "UNSEX RR" under PSM 7 and correctly under PSM 6, for +10 % time (54 s vs 49 s).
export const SCHEDULE_PSM: 'auto' | 6 | 7 = 6;

function cleanCell(s: string): string {
  // a rule remnant at a cell's edge reads as | [ ] or _ ; inside the text it is kept
  return String(s || '').replace(/\s+/g, ' ').replace(/^[\s|_[\]]+|[\s|_[\]]+$/g, '').slice(0, SCHEDULE_CAPS.cell);
}

export async function ocrSchedules(
  pdfBytes: Uint8Array,
  opts?: { onProgress?: (p: number) => void; dpi?: number; psm?: 'auto' | 6 | 7; maxPages?: number },
): Promise<{ schedule_tables: ScheduleTable[]; pages: number; ms: number }> {
  const t0 = Date.now();
  const raster = await import('./pdfRaster');
  const tg = await import('../../../supabase/functions/_shared/table_grid');
  const pdf = await raster.openPdf(pdfBytes);
  const nPages = Math.min(pdf.numPages, opts?.maxPages ?? raster.PDF_MAX_PAGES);
  const dpi = opts?.dpi ?? SCHEDULE_DPI;
  const psmMode = opts?.psm ?? SCHEDULE_PSM;
  const { createWorker } = await import('tesseract.js');
  const worker = await createWorker('eng', 1 /* LSTM only */, { workerPath: ocrUrl('worker.min.js'), corePath: ocrUrl('core'), langPath: ocrUrl('lang'), workerBlobURL: false });
  const out: ScheduleTable[] = [];
  const canvas = document.createElement('canvas');
  const cx = canvas.getContext('2d', { willReadFrequently: true }) as CanvasRenderingContext2D;
  let psmNow = -1;
  const setPsm = async (m: number) => {
    if (m === psmNow) return;
    // deno-lint-ignore no-explicit-any
    await worker.setParameters({ tessedit_pageseg_mode: String(m) as any, user_defined_dpi: String(Math.round(dpi)) } as any);
    psmNow = m;
  };
  try {
    for (let p = 1; p <= nPages && out.length < SCHEDULE_CAPS.tables; p++) {
      const g = await raster.renderPageGray(pdf, p, dpi);
      const tables = tg.detectTables(g).slice(0, SCHEDULE_CAPS.tables - out.length);
      const inset = Math.max(4, Math.round(Math.max(g.w, g.h) * 0.0007));
      const todo = tables.map((t) => t.cells.filter((c) => !tg.isEmptyCell(g, c, inset)));
      const total = todo.reduce((n, a) => n + a.length, 0) || 1;
      let done = 0;
      for (let ti = 0; ti < tables.length; ti++) {
        const t = tables[ti];
        const R = t.rowsY.length - 1, C = t.colsX.length - 1;
        const text: string[][] = Array.from({ length: R }, () => Array(C).fill(''));
        const conf: number[][] = Array.from({ length: R }, () => Array(C).fill(0));
        const rowH = t.rowsY.slice(1).map((y, i) => y - t.rowsY[i]).sort((a, b) => a - b)[Math.floor(R / 2)];
        for (const cell of todo[ti]) {
          const x0 = Math.round(cell.x + inset), y0 = Math.round(cell.y + inset);
          const w = Math.round(cell.w - 2 * inset), h = Math.round(cell.h - 2 * inset);
          done++;
          if (w < 4 || h < 4) continue;
          const pad = 12;
          canvas.width = w + 2 * pad; canvas.height = h + 2 * pad;
          const id = cx.createImageData(canvas.width, canvas.height);
          id.data.fill(255);
          // A horizontal ink run longer than half a row is not a letter stroke: it is an underline under a
          // tag (P-0.01 underlines every tag, and "FD-1" read "FDA", "WC/L-1" read "WCIL-1" with it) or
          // a rule remnant the inset missed. It is whitened before the cell is read.
          const maxRun = Math.max(12, Math.round(rowH * 0.5));
          for (let y = 0; y < h; y++) {
            const src = (y0 + y) * g.w + x0;
            const rowOut = ((y + pad) * canvas.width + pad) * 4;
            let run = 0;
            for (let x = 0; x <= w; x++) {
              const v = x < w ? g.data[src + x] : 255;
              if (v < 170) { run++; continue; }
              const lo = x - run, erase = run >= maxRun;
              for (let k = lo; k < x; k++) { const u = erase ? 255 : g.data[src + k]; const o = rowOut + k * 4; id.data[o] = u; id.data[o + 1] = u; id.data[o + 2] = u; }
              run = 0;
              if (x < w) { const o = rowOut + x * 4; id.data[o] = v; id.data[o + 1] = v; id.data[o + 2] = v; }
            }
          }
          cx.putImageData(id, 0, 0);
          await setPsm(psmMode === 'auto' ? (cell.h <= 1.6 * rowH ? 7 : 6) : psmMode);
          const { data } = await worker.recognize(canvas);
          const s = cleanCell(data.text);
          text[cell.r][cell.c] = s;
          conf[cell.r][cell.c] = s ? Math.round(data.confidence) : 0;
          opts?.onProgress?.((p - 1 + done / total) / nPages);
        }
        // Drop grid columns and rows that are empty everywhere (spacer columns, the ruled blank rows a
        // schedule leaves for additions), then cap.
        const keepC = [...Array(C).keys()].filter((c) => text.some((row) => row[c])).slice(0, SCHEDULE_CAPS.cols);
        const keepR = [...Array(R).keys()].filter((r) => text[r].some((s) => s)).slice(0, SCHEDULE_CAPS.rows);
        if (!keepR.length) continue;
        out.push({
          page: p,
          bbox: { x: t.bbox.x / g.w, y: t.bbox.y / g.h, w: t.bbox.w / g.w, h: t.bbox.h / g.h },
          rows: keepR.map((r) => keepC.map((c) => text[r][c])),
          conf: keepR.map((r) => keepC.map((c) => conf[r][c])),
        });
      }
      opts?.onProgress?.(p / nPages);
    }
  } finally {
    await worker.terminate();
    canvas.width = canvas.height = 0;
  }
  return { schedule_tables: out, pages: nPages, ms: Date.now() - t0 };
}
