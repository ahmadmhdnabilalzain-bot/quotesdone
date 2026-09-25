// scan_ocr — the OCR engine the CAD worker hands to _shared/scan_redact.ts (24 Sep 2026, sales_engineer).
//
// WHY THIS ENGINE. tesseract.js 7.0.0 (Apache-2.0) is the engine the customer's browser already runs
// (src/components/me/ocrClient.ts), with the same eng + ara language data self-hosted in public/ocr/lang. So the
// server uses the same pinned engine and the same data, reads everything from the repository and the npm
// registry, and nothing is sent to a paid service or a model. It runs on the GitHub runner, never on the edge.
//
// Page segmentation mode 11 (sparse text): a drawing is scattered labels, not paragraphs, and mode 3 (the
// default) merges a title block and the plan beside it into one "column".
// deno-lint-ignore-file no-explicit-any
import { createWorker } from 'npm:tesseract.js@7.0.0';
import type { OcrLine } from '../../supabase/functions/_shared/scan_redact.ts';

const LANG = decodeURIComponent(new URL('../../public/ocr/lang', import.meta.url).pathname).replace(/^\/([A-Za-z]:)/, '$1');

/** A reusable OCR function; call `done()` when finished to free the engine. */
export async function tesseractOcr(langs = 'eng'): Promise<{ ocr: (image: Uint8Array) => Promise<OcrLine[]>; done: () => Promise<void> }> {
  const worker = await createWorker(langs, 1, { langPath: LANG, gzip: true, cacheMethod: 'none' } as any);
  await worker.setParameters({ tessedit_pageseg_mode: '11', user_defined_dpi: '300' } as any);
  const ocr = async (image: Uint8Array): Promise<OcrLine[]> => {
    const { data } = await worker.recognize(image as any, {}, { blocks: true } as any) as any;
    const out: OcrLine[] = [];
    for (const b of data.blocks || []) for (const p of b.paragraphs || []) for (const l of p.lines || []) {
      out.push({ text: String(l.text || '').trim(), conf: Number(l.confidence) || 0, bbox: l.bbox,
        words: (l.words || []).map((w: any) => ({ text: String(w.text || ''), conf: Number(w.confidence) || 0, bbox: w.bbox })) });
    }
    return out;
  };
  return { ocr, done: async () => { await worker.terminate(); } };
}

/**
 * Run `fn` with an OCR engine that is TERMINATED at the budget (third review of #967: a Promise.race rejected on time
 * but left tesseract working, so the runner kept spending past it). The engine is always terminated when `fn` ends.
 */
export async function withOcrBudget<T>(langs: string, ms: number, what: string, fn: (ocr: (image: Uint8Array) => Promise<OcrLine[]>) => Promise<T>): Promise<T> {
  const e = await tesseractOcr(langs);
  let stopped = false, timer: ReturnType<typeof setTimeout> | undefined;
  const stop = async () => { if (!stopped) { stopped = true; await e.done().catch(() => {}); } };
  try {
    return await Promise.race([fn(e.ocr), new Promise<never>((_, no) => { timer = setTimeout(() => { void stop(); no(new Error(`${what} ran past its ${Math.round(ms / 60_000)}-minute budget; the OCR engine was stopped`)); }, ms); })]);
  } finally { clearTimeout(timer); await stop(); }
}
