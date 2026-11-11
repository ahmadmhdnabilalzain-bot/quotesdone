// ocr_plan_offline — the customer's browser OCR plan (src/components/me/ocrPlan.ts + tesseract.js 7.0.0) run
// offline, sharp standing in for the canvas. Shared by drawing_image_ocr.test.ts and drawing_bench.test.ts.
import { createWorker } from 'npm:tesseract.js@7.0.0';
import type { OcrLine } from './drawing_from_ocr.ts';
import { OCR_PASSES, binarize, mergeLines, scaleFor, skewDegrees, tiles } from '../../../src/components/me/ocrPlan.ts';

// sharp is PINNED to 0.34.5, the version the root deno.lock held (via next) when this was written; that file was
// removed on 11 Nov 2026 (nothing read it: every Deno call passes --no-lock). An unpinned specifier resolved
// to npm's newest, and on 28 Sep 2026 sharp 0.35.5 was tagged latest before its darwin-x64 binary
// resolved, which failed every PR's deno test with 'Could not find npm package'.

// sharp is loaded LAZILY: its module reads process.env on load, and the suite runner
// (scripts/checks/run.mjs) grants no permissions, so a top-level import crashed the whole file
// instead of letting this test report itself ignored (measured 14 Sep 2026: 357 passed, 1 failed).
// deno-lint-ignore no-explicit-any
let sharp: any;
export const loadSharp = async () => { if (!sharp) sharp = (await import('npm:sharp@0.34.5')).default; return sharp; };

/** The OCR plan, exactly as the browser runs it, with sharp standing in for the canvas. */
export async function ocrPlan(input: Uint8Array, LANG: string) {
  await loadSharp();
  // Straighten first, as ocrClient does: the sheet is read and counted level.
  const raw0 = await sharp(input).flatten({ background: '#ffffff' }).removeAlpha().raw().toBuffer({ resolveWithObject: true });
  const skew = skewDegrees(new Uint8Array(raw0.data), 3, raw0.info.width, raw0.info.height);
  const bytes: Uint8Array = skew ? new Uint8Array(await sharp(input).flatten({ background: '#ffffff' }).rotate(skew, { background: '#ffffff' }).png().toBuffer()) : input;
  const meta = await sharp(bytes).metadata();
  const worker = await createWorker('eng', 1, { langPath: LANG, gzip: true, cacheMethod: 'none' });
  const all: (OcrLine & { pass: number })[] = [];
  try {
    for (let pi = 0; pi < OCR_PASSES.length; pi++) {
      const p = OCR_PASSES[pi]; const s = scaleFor(p, meta.width!, meta.height!);
      const W = Math.round(meta.width! * s), H = Math.round(meta.height! * s);
      const raw = await sharp(bytes).flatten({ background: '#ffffff' }).resize(W, H, { kernel: 'lanczos3' }).removeAlpha().raw().toBuffer();
      const g = binarize(new Uint8Array(raw), 3, W, H);
      // deno-lint-ignore no-explicit-any
      await worker.setParameters({ tessedit_pageseg_mode: p.psm as any, user_defined_dpi: '300' } as any);
      for (const t of tiles(W, H, p.tile)) {
        const png = await sharp(Buffer.from(g), { raw: { width: W, height: H, channels: 1 } }).extract({ left: t.x, top: t.y, width: t.w, height: t.h }).png().toBuffer();
        // deno-lint-ignore no-explicit-any
        const { data } = await worker.recognize(png, {}, { blocks: true } as any) as any;
        for (const b of data.blocks || []) for (const par of b.paragraphs || []) for (const ln of par.lines || []) {
          const bb = ln.bbox; all.push({ text: ln.text, pass: pi, bbox: { x: (t.x + bb.x0) / s, y: (t.y + bb.y0) / s, w: (bb.x1 - bb.x0) / s, h: (bb.y1 - bb.y0) / s } });
        }
      }
    }
  } finally { await worker.terminate(); }
  return { lines: mergeLines(all), width: meta.width!, height: meta.height!, bytes, skew };
}

