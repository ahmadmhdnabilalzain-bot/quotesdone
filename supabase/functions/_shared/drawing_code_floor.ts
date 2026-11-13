// drawing_code_floor — what CODE covers on a drawing page whatever the vision models answered (drawing_redact's model
// path). Kept apart from drawing_redact_page.ts so it is tested without the image codec.
import type { PdfPage } from './pdf_text_positions.ts';
import { residualScan, runCover, titleBlockBoxes, type Box } from './anonymise.ts';
import { drawingLocation, namesParty, partyLabel, seedHit } from './drawing_text_policy.ts';

/**
 * THE CODE FLOOR under the vision models (13 Nov 2026, sales_engineer; anonymity audit B finding I1): the boxes code adds
 * to a page whatever the find and verify models answered. On a PDF page with a text layer: the server's own title-block
 * boxes (strip, revision table, key plans, every picture outside the strip) and every run that names a party, a place
 * below the emirate or a seed. A page with NO text layer (a scan, a photo) returns null and drawing_redact HOLDS it for
 * the scan route (scan_redact.ts on the CAD worker: OCR at four turns, the strip magnified, every line judged by the
 * drawing allow-list, the painted page read again, unread ink held), which is the code floor for pixels.
 * MEASURED before choosing that: a single upright OCR of the auditor's scan B2 (tesseract.js 7, eng+ara, the browser's
 * engine) used as a floor here missed the watermark, the vertical "AL BARSHA 2", the site plan's "VILLA 15", the edge
 * text and the owner's phone, and blacked out half the equipment schedule it misread. One pass of OCR is not a floor.
 */
export function codeFloorBoxes(page: PdfPage | undefined, seeds: string[]): Box[] | null {
  const party = (t: string) => namesParty(t) || partyLabel(t) || !!drawingLocation(t) || !!seedHit(t, seeds) || residualScan(t, seeds).length > 0;
  if (!page || !page.runs.length) return null;
  const tb = titleBlockBoxes([page], seeds);
  return [...(tb.boxes[0] ?? []), ...page.runs.filter((r) => party(r.text)).flatMap((r) => runCover(r, 0.01))];
}

/**
 * TEXT CODE CANNOT READ, LEFT TO MODELS THAT NAMED NOTHING (round 3, 13 Nov 2026, sales_engineer; brief f3_finish).
 * MEASURED with a LAZY model (reads every view, copies its mark, reports nothing) on the reviewer's corpus: v01 (labels
 * drawn as filled outlines: "AL BARSHA 2 / VILLA 15 / MR ZZ DEMO KAREEM") and v12 (a Type3 font with no ToUnicode
 * drawing "AL BARSHA 2 VILLA 15") were published, because the code floor cannot read what they say. Code still KNOWS
 * that text is there: rows of small filled shapes (pdf_text_positions glyphRows) and runs in an undecodable font
 * (TextRun.unread) that no box of the title-block reading covers. unreadAreas returns them.
 */
export function unreadAreas(page: PdfPage | undefined, seeds: string[]): Box[] {
  if (!page) return [];
  const tb = titleBlockBoxes([page], seeds).boxes[0] ?? [];
  const centreIn = (b: Box, r: Box) => r.x + r.w / 2 >= b.x && r.x + r.w / 2 <= b.x + b.w && r.y + r.h / 2 >= b.y && r.y + r.h / 2 <= b.y + b.h;
  const left = [...(page.glyphRows ?? []), ...page.runs.filter((r) => r.unread)].filter((g) => !tb.some((b) => centreIn(b, g)));
  return left.map((g) => ({ x: g.x, y: g.y, w: g.w, h: g.h }));
}
/**
 * The rule: a page on which code sees text it cannot read is published only when a model NAMED something on it - the
 * find model boxed a region, or the checker of another family was not clean on its first look. A sheet code cannot read
 * that both models call free of any identity (no title block, no name, nothing) is not believed: HELD, and said. A
 * faithful model names the title block every real sheet has, so this holds only a model that reported nothing.
 * Returns the reason to hold, or null.
 */
export function unreadTextHold(page: PdfPage | undefined, seeds: string[], findRegions: number, firstLookClean: boolean): string | null {
  if (findRegions > 0 || !firstLookClean) return null;
  const n = unreadAreas(page, seeds).length;
  return n ? 'unread_text_unclaimed' : null;
}
