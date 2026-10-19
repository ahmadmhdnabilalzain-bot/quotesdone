// vision_count — a vision model counts each LEGEND symbol on a photographed or scanned drawing, where template matching
// cannot (19 Oct 2026, sales_engineer; founder ledger 580, 1177, ruling 1260; coordinator: Sonnet 5.5 or Luna Pro,
// never Gemini). Measured on the drawing bench: a phone photo of the sample fire-alarm sheet, straightened, still
// read 53 call points against 10 and 74 smoke detectors against 11 by template matching.
//
// WHAT GOES TO THE MODEL: the REDACTED page drawing_redact recorded as complete (as the confirm step) and the legend's
// type names. Never the original, never the title block.
// WHAT COMES BACK IS CHECKED: only the legend's own types are kept (anything else is dropped: "within the legend"),
// each a whole number 0..999. The counts stay estimates the customer confirms (qty_status 'to_confirm').
// WHICH COUNT STANDS (reconcile): on an addressable loop, the set whose implied addresses equal the loop's highest
// address wins (crossCheck); otherwise the model's count, which the bench measured nearer than the template counter.
import { crossCheck } from './symbol_count.ts';

export const VISION_COUNT_ROUTE = 'drawing_vision_count';
export const VISION_COUNT_FLAG = 'drawing_vision_count_enabled';
export const VISION_COUNT_MAX_TOKENS = 600;

export const VISION_COUNT_SYS = `You count symbols on a construction drawing. You are given the drawing and its LEGEND: a list of symbol types.
For EACH legend type, count how many times its symbol is drawn ON THE PLAN. Do NOT count the one sample drawn in the legend itself.
A symbol turned or mirrored is still that symbol. Count every instance; do not estimate from a sample area.
Reply with ONLY this JSON, every legend type present, whole numbers: {"counts":{"<type>":<n>, ...}}`;

export function visionUserText(types: { type: string; en: string }[]): string {
  return 'Legend types (key: what the legend calls it):\n' + types.map((t) => `${t.type}: ${t.en}`).join('\n');
}

/** The model's reply, kept only for the legend's types, each a whole number 0..999. Null when unreadable. */
export function parseVisionCounts(raw: string, types: string[]): Record<string, number> | null {
  let j: unknown = null;
  try { j = JSON.parse(raw); } catch { const m = String(raw || '').match(/\{[\s\S]*\}/); if (m) try { j = JSON.parse(m[0]); } catch { /* unreadable */ } }
  const c = (j as { counts?: Record<string, unknown> } | null)?.counts;
  if (!c || typeof c !== 'object') return null;
  const out: Record<string, number> = {};
  for (const t of types) { const n = Number(c[t]); if (Number.isInteger(n) && n >= 0 && n <= 999) out[t] = n; }
  return Object.keys(out).length ? out : null;
}

/** Which counts stand: the one that accounts for the loop's addresses, else the model's, else the code's. */
export function reconcile(code: Record<string, number>, vision: Record<string, number> | null, addresses: number | null): { counts: Record<string, number>; source: 'vision' | 'code'; agrees: boolean } {
  if (!vision) return { counts: code, source: 'code', agrees: crossCheck(code, addresses).agrees };
  const merged = { ...code, ...vision };
  const v = crossCheck(merged, addresses).agrees, c = crossCheck(code, addresses).agrees;
  if (c && !v) return { counts: code, source: 'code', agrees: true };
  return { counts: merged, source: 'vision', agrees: v };
}

if (import.meta.main) {
  // deno run supabase/functions/drawing_boq/vision_count.ts — the parser's and reconcile's own check.
  const t = ['smoke_detector', 'manual_call_point'];
  console.assert(JSON.stringify(parseVisionCounts('x {"counts":{"smoke_detector":11,"manual_call_point":10,"logo":3}} y', t)) === '{"smoke_detector":11,"manual_call_point":10}');
  console.assert(parseVisionCounts('{"counts":{"smoke_detector":-1}}', t) === null);
  console.assert(reconcile({ smoke_detector: 74 }, { smoke_detector: 11 }, null).counts.smoke_detector === 11);
  console.log('vision_count ok');
}
