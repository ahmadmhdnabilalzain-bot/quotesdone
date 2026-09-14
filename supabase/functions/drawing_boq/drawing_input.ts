// drawing_input — the portal's drawing OCR, validated at the trust boundary (14 Sep 2026).
//
// ocr_lines (ocrPlan.ts: OCR lines with page boxes), ocr_width and symbol_counts arrive from the
// customer's browser, so they are customer-controlled input. Shapes are validated here; the counts
// are only ever ESTIMATES the customer is asked to confirm (boq_open_lines); and the address
// cross-check is recomputed HERE from the lines, whatever the browser claimed about it.
import { addresses, type Counts, type OcrLine } from './drawing_from_ocr.ts';
import { crossCheck } from './symbol_count.ts';
import { DEVICE_TYPES } from './legend_vocabulary.ts';

const num = (v: unknown, max: number) => { const n = Number(v); return Number.isFinite(n) && n >= 0 && n <= max ? n : null; };

/** Lines: at most 4000, text at most 200 chars, a box of finite non-negative numbers. Counts: known device types, integers 0..2000. */
export function drawingInput(rawLines: unknown, rawWidth: unknown, rawCounts: unknown, ocrText: string): { lines?: OcrLine[]; width?: number; counts?: Counts } {
  const lines: OcrLine[] = [];
  if (Array.isArray(rawLines)) for (const l of rawLines.slice(0, 4000)) {
    const b = (l as { bbox?: Record<string, unknown> })?.bbox || {};
    const x = num(b.x, 20000), y = num(b.y, 20000), w = num(b.w, 20000), h = num(b.h, 20000);
    const text = typeof (l as { text?: unknown })?.text === 'string' ? String((l as { text: string }).text).slice(0, 200) : '';
    if (text && x != null && y != null && w != null && h != null) lines.push({ text, bbox: { x, y, w, h } });
  }
  const known = new Set(DEVICE_TYPES.map((d) => d.type));
  const raw: Record<string, number> = {};
  const src = (rawCounts && typeof rawCounts === 'object' ? (rawCounts as { counts?: unknown }).counts ?? rawCounts : {}) as Record<string, unknown>;
  for (const [t, v] of Object.entries(src || {})) { const n = num(v, 2000); if (known.has(t) && n != null && Number.isInteger(n)) raw[t] = n; }
  const loop = addresses(lines.length ? lines.map((l) => l.text).join('\n') : ocrText).find((l) => l.loop === 'L1') || null;
  const chk = crossCheck(raw, loop?.highest ?? null);
  const basis = chk.agrees
    ? `template match on the drawing; the per-type counts account for all ${chk.addresses} loop addresses`
    : `template match on the drawing; these counts imply ${chk.implied} loop addresses against ${chk.addresses ?? 'an unread number of'} read, so they are approximate`;
  const counts: Counts = Object.fromEntries(Object.entries(raw).map(([t, n]) => [t, { count: n, basis }]));
  const width = num(rawWidth, 20000);
  return { ...(lines.length ? { lines } : {}), ...(width ? { width } : {}), ...(Object.keys(counts).length ? { counts } : {}) };
}
