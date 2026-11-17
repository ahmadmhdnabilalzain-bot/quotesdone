// drawing_plan — A PDF DRAWING'S TEXT LAYER IS READ PAGE BY PAGE, EACH PAGE IN A WORKER OF ITS OWN
// (17 Nov 2026, sales_engineer; live bug of the paid proof 712aae1d).
//
// MEASURED (SELECT on the function logs, 17 Nov 2026 12:58-12:59 UTC): analyze_drawing answered HTTP 546 "CPU Time
// exceeded" for an 8-sheet set (cpu_time_used 3108 ms) and for ONE sheet of the same set (3098 ms). Between its last
// outbound call (the app_secrets read at 12:59:00.595) and the kill (12:59:03.802) customer_api called nothing: it was
// decoding the whole original PDF, reading every page's text layer (pdfPages) and boxing every title block
// (titleBlockBoxes) on the request path, for every call — the one-sheet call carried the whole 8-sheet PDF too. The same
// two requests (the same body sizes to the byte) took 1354 ms and 1313 ms of CPU on 12 Nov (v425, runtime 1.78.1); no PDF
// drawing was analysed in production between 12 Nov 00:24 UTC and the proof (v451, runtime 1.79.1), so the logs cannot name
// one commit. LOCAL, the same set: the anonymity rounds of 13-15 Nov took titleBlockBoxes from about 265 to 430 ms (cold,
// one process; e2d78a0f3 and the merge 096c2607c the largest steps) and the whole handler from about 890 to 1,060 ms of CPU.
// Whatever share the runtime change has, the cost grows with the set and sat on the one worker that must answer.
//
// WHAT THIS CHANGES. The read is split in two steps that drawing_redact runs (mode 'plan'), each over a few pages:
//   1. 'strips'  - the page count, each page's word count and printed lines, and what its title strip names;
//   2. 'boxes'   - each page boxed by titleBlockBoxes with the strip seeds of the WHOLE set (setOf), so a page is boxed
//                  exactly as the whole-set call boxed it (the equivalence is tested on the 8-sheet set).
// customer_api only merges the answers (mergePlan). WHAT IT DOES NOT CHANGE: what is boxed, the set-level confidence (one
// low page still sends no server boxes for any page), the fail-closed answer (any part missing = the old parse failure:
// no server boxes, so drawing_redact holds or the models check), and the priced-document test on the printed lines.
// One difference, deliberate: the parser's operation budget is now per page, not per file, so a long set is read further.
import { linesFromRuns, pdfPages, type PdfPage } from './pdf_text_positions.ts';
import { setStripSeeds, titleBlockBoxes } from './anonymise.ts';

type Box = { x: number; y: number; w: number; h: number };

/** Pages per drawing_redact 'plan' call, and how many such calls run at once. One page per worker keeps each call far
 *  under the edge CPU cap whatever the set's length. LOCAL, cold process, sheet 4 of the 8-sheet set: 46 ms 'strips' +
 *  78 ms 'boxes', against about 715 ms for the whole set in one call; customer_api's own CPU for analyze_drawing with every
 *  outbound call stubbed fell from about 900 ms to 95 ms (one sheet) and 160 ms (eight). */
export const PLAN_PAGES_PER_CALL = 1;
export const PLAN_PARALLEL = 4;
/** The most pages one 'plan' call reads, whatever a caller asks. */
export const PLAN_MAX_PAGES_PER_CALL = 4;
/** The planned read's own wall clock (review, 17 Nov): every call of it ends inside this many ms of the read's start, so a
 *  long set (the PDF's page count is not capped by MAX_DRAWING_PAGES) cannot hold the redaction past its start-by or the
 *  answer past the edge wall. Past it the read is given up: no server boxes, the old parse failure. */
export const PLAN_BUDGET_MS = 30_000;

export type StripsPart = { pages: number; from: number; words: number[]; lines: string[]; strips: string[][] };
export type BoxesPart = { from: number; boxes: Box[][]; low: boolean; residual: string[]; setSeeds: string[] };
export type PdfPlan = { pdfWords: number; pdfLines: string[]; tb: { boxes: Box[][]; confidence: 'low' | 'medium'; residual: string[]; setSeeds: string[] } };

/** The pages [from, to) of the set, read alone (pdfPages gives the other pages empty). */
async function ownPages(bytes: Uint8Array, from: number, to: number): Promise<{ all: number; own: PdfPage[] }> {
  const pp = await pdfPages(bytes, [from, to], { layers: false });
  return { all: pp.length, own: pp.slice(from, Math.min(to, pp.length)) };
}

/** Step 1 (drawing_redact mode 'plan', step 'strips'). */
export async function planStrips(bytes: Uint8Array, from: number, to: number): Promise<StripsPart> {
  const { all, own } = await ownPages(bytes, from, to);
  return { pages: all, from, words: own.map((p) => p.runs.length), lines: own.map((p) => linesFromRuns([p])), strips: own.map((p) => setStripSeeds([p])) };
}

/** Step 2 (drawing_redact mode 'plan', step 'boxes'): `setOf` is every sheet's strip seeds, from step 1. */
export async function planBoxes(bytes: Uint8Array, from: number, to: number, seeds: string[], setOf: string[]): Promise<BoxesPart> {
  const { own } = await ownPages(bytes, from, to);
  const tb = titleBlockBoxes(own, seeds, setOf);
  // titleBlockBoxes numbers the pages it was given from 1: the set's own page number is put back.
  const residual = tb.residual.map((r) => r.replace(/^page (\d+):/, (_m, n) => `page ${from + Number(n)}:`));
  return { from, boxes: tb.boxes, low: tb.confidence === 'low', residual, setSeeds: tb.setSeeds };
}

const strs = (v: unknown): v is string[] => Array.isArray(v) && v.every((x) => typeof x === 'string');
const stripsOk = (j: any, from: number, to: number): j is StripsPart => {
  if (!j || j.ok !== true || !Number.isInteger(j.pages) || j.pages < 0 || j.from !== from) return false;
  const n = Math.max(0, Math.min(to, j.pages) - from);
  return Array.isArray(j.words) && j.words.length === n && j.words.every((w: unknown) => Number.isInteger(w) && (w as number) >= 0)
    && strs(j.lines) && j.lines.length === n && Array.isArray(j.strips) && j.strips.length === n && j.strips.every(strs);
};
const boxesOk = (j: any, from: number, n: number): j is BoxesPart =>
  !!j && j.ok === true && j.from === from && Array.isArray(j.boxes) && j.boxes.length === n && j.boxes.every((b: unknown) => Array.isArray(b))
  && typeof j.low === 'boolean' && strs(j.residual) && strs(j.setSeeds);

/** Run `job` over `items`, at most `width` at a time, in order of the answers' positions. */
async function pool<T, R>(items: T[], width: number, job: (t: T) => Promise<R>): Promise<R[]> {
  const out: R[] = new Array(items.length); let next = 0;
  await Promise.all(Array.from({ length: Math.min(width, items.length) }, async () => { while (next < items.length) { const i = next++; out[i] = await job(items[i]); } }));
  return out;
}

/** The two answers put together as the whole-set read made them (pdfWords, the printed lines, titleBlockBoxes' verdict). */
export function mergePlan(strips: StripsPart[], boxes: BoxesPart[], seeds: string[]): PdfPlan {
  const s = [...strips].sort((a, b) => a.from - b.from), b = [...boxes].sort((a, c) => a.from - c.from);
  const pages = s.length ? s[0].pages : 0;
  if (!pages) { const tb = titleBlockBoxes([], seeds); return { pdfWords: 0, pdfLines: [], tb: { boxes: tb.boxes, confidence: tb.confidence, residual: tb.residual, setSeeds: tb.setSeeds } }; }
  const residual = b.flatMap((x) => x.residual);
  const low = !seeds.length || b.some((x) => x.low);
  return {
    pdfWords: s.reduce((n, x) => n + x.words.reduce((m, w) => m + w, 0), 0),
    pdfLines: s.flatMap((x) => x.lines).join('\n').split('\n').map((l) => l.trim()).filter(Boolean),
    tb: { boxes: b.flatMap((x) => x.boxes), confidence: low || residual.length ? 'low' : 'medium', residual, setSeeds: b[0]?.setSeeds ?? [] },
  };
}

export type PlanCall = (body: Record<string, unknown>) => Promise<unknown>;

/**
 * THE ORIGINAL IS SERIALISED ONCE PER READ (17 Nov 2026, review of the page-by-page read). Every 'plan' call carries the
 * whole original, and JSON.stringify({ __secret, ...b, original_b64 }) per call re-serialised and UTF-8 encoded it each
 * time: measured by the review at ~55 ms per 32 MB of base64 per call, so a 24 MB, 20-page PDF (~41 calls) spent ~2 s of
 * customer_api's CPU on that alone. Here `,"original_b64":"…"}` is encoded to bytes once, wrapped in one Blob, and each
 * call's body is a Blob of its own small JSON head and that shared Blob (a Blob part is shared, not copied). The bytes on
 * the wire are exactly JSON.stringify({ __secret: secret, ...b, original_b64: original }) for every `b` without its own
 * original_b64 (one is dropped, so the shared copy is always the one sent).
 */
export function planBodies(secret: string | undefined, original: string): (b: Record<string, unknown>) => Blob {
  const tail = new Blob([new TextEncoder().encode(`"original_b64":${JSON.stringify(original)}}`)]);
  return (b) => {
    const { original_b64: _drop, ...rest } = b;
    const head = JSON.stringify({ __secret: secret, ...rest });
    // `{...}` -> `{...,` (or `{` when the head is empty) and the shared `"original_b64":"…"}` after it.
    return new Blob([head === '{}' ? '{' : head.slice(0, -1) + ',', tail], { type: 'application/json' });
  };
}

/**
 * The whole read, through `call` (one drawing_redact 'plan' request; null or a throw = no answer). null when any part did
 * not answer in shape: the caller then does what the old in-request parse did when it threw (no server boxes).
 */
export async function readPdfPlan(call: PlanCall, seeds: string[], per = PLAN_PAGES_PER_CALL, width = PLAN_PARALLEL): Promise<PdfPlan | null> {
  // A part that does not answer (a cold worker's 546, a timeout) is asked ONCE more (review, 17 Nov): one lost call of 2N
  // would otherwise take the whole set's server boxes, set seeds and printed lines (the priced-document test) with it.
  const ask = async (b: Record<string, unknown>) => {
    for (let k = 0; k < 2; k++) { try { const j: any = await call(b); if (j && j.ok === true) return j; } catch (_e) { /* asked again once */ } }
    return null;
  };
  const first: any = await ask({ mode: 'plan', step: 'strips', from: 0, to: per });
  if (!stripsOk(first, 0, per)) return null;
  const n = first.pages;
  const ranges: [number, number][] = [];
  for (let f = 0; f < n; f += per) ranges.push([f, Math.min(n, f + per)]);
  const rest = await pool(ranges.slice(1), width, async ([f, t]) => { const j: any = await ask({ mode: 'plan', step: 'strips', from: f, to: t }); return stripsOk(j, f, t) && j.pages === n ? j : null; });
  if (rest.some((x) => !x)) return null;
  const strips = [first as StripsPart, ...(rest as StripsPart[])];
  if (!n) return mergePlan(strips, [], seeds);
  const setOf = [...new Set(strips.flatMap((x) => x.strips.flat()))];
  const boxes = await pool(ranges, width, async ([f, t]) => { const j: any = await ask({ mode: 'plan', step: 'boxes', from: f, to: t, seed_terms: seeds, set_seeds: setOf }); return boxesOk(j, f, t - f) ? j : null; });
  if (boxes.some((x) => !x)) return null;
  return mergePlan(strips, boxes as BoxesPart[], seeds);
}
