// vision_count_wire — analyze_drawing asks drawing_boq's vision count for a photo or a scan (27 Oct 2026).
// Assigned: sales_engineer (the take-off).
//
// MEASURED 27 Oct 2026 (founder ledger 580, docs/reports "drawings_and_exam_27_oct"): drawing_boq mode 'vision_count'
// (drawing_boq/vision_count.ts, 19 Oct 2026) had NO caller anywhere in customer_api, src or scripts. Its design says
// where it belongs: "a model counts each legend symbol on the REDACTED page of a photo or scan, after redaction, like
// the confirm", and its route (drawing_vision_count, Sonnet 5.5 / Luna Pro) and flag (drawing_vision_count_enabled)
// shipped ON (scripts/sql/a_drawing_photo_is_counted_by_a_vision_model_within_its_legend.sql). So photos and scans
// were counted by template matching alone, which the drawing bench measured at 0/7 on a phone photo (53 call points
// read against 10, 74 smoke detectors against 11).
//
// WHAT THIS DOES. For a photo or a scanned PDF (no text layer) whose take-off carries legend device lines
// (drawing_from_ocr.ts readDrawing: section "... devices (from the legend)", `type` a legend device type, `estimate`
// the template count), it builds the vision_count body: the legend's types, the code's counts and the loop's highest
// address. drawing_boq picks which counts stand (vision_count.ts reconcile: the set that accounts for the loop's
// addresses, else the model's). Only when the model's set stands are the lines changed, and then only their
// `estimate` and `basis`: qty stays null and qty_status 'to_confirm', so the customer is still asked to confirm
// (boq_open_lines) and nothing becomes a settled quantity. It runs after redaction and before the confirm step, on
// the same verified redacted page; anything that fails leaves the code's counts standing.
// WHAT IT DOES NOT DO: a CAD file, a vector PDF and a PDF drawing set are counted by code and never reach it.

type Line = Record<string, unknown>;
export type VisionCountBody = { legend: { type: string; en: string }[]; code_counts: Record<string, number>; addresses: number | null };
export type VisionCountReply = { ok?: boolean; counts?: Record<string, number>; source?: string; agrees?: boolean; vision?: Record<string, number> | null; why?: string };

const LEGEND_SECTION = /devices \(from the legend\)/i;
const isLegendLine = (l: Line) => LEGEND_SECTION.test(String(l?.section ?? '')) && typeof l?.type === 'string' && String(l.type).trim() !== '';

/** A photo, or a PDF with no text layer (pdfWords 0, as analyze_drawing's scan path reads it); never a CAD file. */
export function isPhotoOrScan(mime: string, pdfWords: number, isCad: boolean): boolean {
  return !isCad && (/^image\//i.test(mime) || (/pdf/i.test(mime) && pdfWords === 0));
}

/** The vision_count request for this take-off, or null when it has no legend device line to count. */
export function visionCountBody(lines: unknown): VisionCountBody | null {
  const ls = Array.isArray(lines) ? (lines as Line[]).filter((l) => l && typeof l === 'object') : [];
  const legend: { type: string; en: string }[] = [];
  const code: Record<string, number> = {};
  for (const l of ls.filter(isLegendLine)) {
    const type = String(l.type).trim().slice(0, 60);
    if (legend.some((t) => t.type === type)) continue;
    legend.push({ type, en: String(l.description || l.item || type).slice(0, 80) });
    const n = Number(l.estimate);
    if (l.estimate != null && Number.isInteger(n) && n >= 0) code[type] = n;
  }
  if (!legend.length) return null;
  const loop = ls.find((l) => String(l?.type ?? '') === 'loop_l1_addresses');
  const a = Number(loop?.estimate);
  return { legend: legend.slice(0, 30), code_counts: code, addresses: loop && Number.isInteger(a) && a > 0 ? a : null };
}

/** The take-off with the vision count applied where drawing_boq chose it; unchanged otherwise. */
export function applyVisionCounts(lines: unknown, reply: VisionCountReply | null | undefined): unknown {
  if (!Array.isArray(lines) || !reply || reply.ok !== true || reply.source !== 'vision' || !reply.counts || !reply.vision) return lines;
  const counts = reply.counts, seen = reply.vision;
  return (lines as Line[]).map((l) => {
    if (!l || typeof l !== 'object' || !isLegendLine(l)) return l;
    const type = String(l.type).trim();
    const n = Number(counts[type]);
    if (!(type in seen) || !Number.isInteger(n) || n < 0) return l;
    const was = l.estimate == null ? 'no template count' : `template count ${l.estimate}`;
    return { ...l, qty: null, estimate: n, qty_status: 'to_confirm',
      basis: `counted within the legend by a vision model on the redacted drawing (${was})${reply.agrees ? '; the per-type counts account for the loop addresses' : ''}; to be confirmed`,
      count_source: 'vision' };
  });
}
