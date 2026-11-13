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
