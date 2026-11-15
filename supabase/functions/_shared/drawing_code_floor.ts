// drawing_code_floor — what CODE covers on a drawing page whatever the vision models answered (drawing_redact's model
// path). Kept apart from drawing_redact_page.ts so it is tested without the image codec.
import type { PdfPage } from './pdf_text_positions.ts';
import { residualScan, runCover, titleBlockBoxes, type Box } from './anonymise.ts';
import { drawingLocation, isVocabularyContent, namesParty, partyLabel, seedHit } from './drawing_text_policy.ts';
import { tradeWord } from './drawing_vocabulary.ts';

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
/** A box grown by `m` on every side (what paintBoxes and the model path's paint() actually blacken). */
export const padded = (b: Box, m: number): Box => ({ x: b.x - m, y: b.y - m, w: b.w + 2 * m, h: b.h + 2 * m });
/** The unread areas whose centre lies under NO painted box. */
export function unpaintedUnread(page: PdfPage | undefined, seeds: string[], painted: Box[]): Box[] {
  const centreIn = (b: Box, r: Box) => r.x + r.w / 2 >= b.x && r.x + r.w / 2 <= b.x + b.w && r.y + r.h / 2 >= b.y && r.y + r.h / 2 <= b.y + b.h;
  return unreadAreas(page, seeds).filter((a) => !painted.some((b) => centreIn(b, a)));
}
/**
 * The rule (round 4, 15 Nov 2026, sales_engineer; brief f3_fix4 item 1): a page on which code sees text it cannot read is
 * published only when EVERY such area lies under a painted box - the find model's regions, the code floor, the text
 * layer's boxes, the customer's or the server's boxes, and the boxes the checker named and had painted - judged by the
 * area's centre. One area left bare: HELD, and said.
 * WHY NOT A COUNT ANY MORE (third review, ANONYMITY F3 DRAWINGS 3, fix 1): round 3 skipped the hold as soon as the find
 * model boxed ANY region or the checker was not clean on its first look. A model that boxes only the title strip
 * (the reviewer's TITLE-ONLY stub: one box over the right 22%) therefore published v01 ("AL BARSHA 2", "VILLA 15", drawn
 * as outlines), v12 (a Type3 font: "AL BARSHA 2 VILLA 15") and n06 (a location inset: "AL KHAIL"). A faithful model boxes
 * the outlined labels themselves, so their centres are covered and the page goes; a model that names something else
 * does not vouch for text it did not cover. Returns the reason to hold, or null.
 */
export function unreadTextHold(page: PdfPage | undefined, seeds: string[], painted: Box[]): string | null {
  return unpaintedUnread(page, seeds, painted).length ? 'unread_text_unclaimed' : null;
}

/**
 * A CHECKER BOX OVER DRAWING WORDS ONLY IS NOT PAINTED (round 4, 15 Nov 2026, sales_engineer; third review fix 4(d), the
 * safe part). MEASURED by the reviewer: an OVER-EAGER checker (it boxes every line it reads) published 22 of 23 ordinary
 * previews with 0 of 28 quoting strings left, and nothing noticed. On a page with a text layer, code reads what lies under
 * each box the checker names; a box is IGNORED (not painted, logged in the gate's detail) only when ALL of this holds:
 *   - it covers at least one run (its centre inside the box) and every run it touches by a fifth or more is DRAWING
 *     VOCABULARY: the strict closed-list gate (drawing_text_policy.isVocabularyContent: every token a number, a size or
 *     device code, or a trade word; no company, licence, contact, label, place, Arabic, letter-spaced text), at least
 *     one real word of the trade in it (a bare number such as the reviewer's n03 plot "+6512" written like a level is
 *     NEVER ignored), and no party, seed or residual identity (the code floor's own test);
 *   - it covers no text code cannot read (unreadAreas, glyph rows) and touches no picture;
 *   - it does not reach past those runs by more than about a line height (it hides nothing but them).
 * Anything else the checker boxes is painted as before. Levels, grids, scales, sheet numbers, revision rows and schedule
 * rows are exactly such runs.
 */
export type Vet = (regions: Box[]) => { keep: Box[]; ignored: { box: Box; text: string }[] };
export function vocabularyVet(page: PdfPage | undefined, seeds: string[]): Vet | undefined {
  if (!page || !page.runs.length) return undefined;
  const area = (b: Box) => Math.max(0, b.w) * Math.max(0, b.h);
  const inter = (a: Box, b: Box) => area({ x: Math.max(a.x, b.x), y: Math.max(a.y, b.y), w: Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x), h: Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y) });
  const centreIn = (b: Box, r: Box) => r.x + r.w / 2 >= b.x && r.x + r.w / 2 <= b.x + b.w && r.y + r.h / 2 >= b.y && r.y + r.h / 2 <= b.y + b.h;
  const vocab = (t: string) => {
    const s = String(t || '').trim();
    if (!s || !isVocabularyContent(s)) return false;
    if (!s.split(/[^A-Za-z]+/).some((w) => w.length >= 2 && tradeWord(w))) return false;   // a real word of the trade, not a bare number
    return !(namesParty(s) || partyLabel(s) || drawingLocation(s) || seedHit(s, seeds) || residualScan(s, seeds).length > 0);
  };
  const unread = unreadAreas(page, seeds), pics = page.images ?? [];
  return (regions: Box[]) => {
    const keep: Box[] = [], ignored: { box: Box; text: string }[] = [];
    for (const b of regions) {
      const touched = page.runs.filter((r) => area(r) > 0 && inter(r, b) >= 0.2 * area(r));
      const covered = touched.filter((r) => centreIn(b, r));
      const ok = covered.length > 0 && touched.every((r) => !r.unread && vocab(r.text))
        && !unread.some((u) => inter(u, b) > 0) && !pics.some((im) => inter(im, b) > 0);
      if (ok) {
        const u = { x: Math.min(...touched.map((r) => r.x)), y: Math.min(...touched.map((r) => r.y)), w: 0, h: 0 };
        u.w = Math.max(...touched.map((r) => r.x + r.w)) - u.x; u.h = Math.max(...touched.map((r) => r.y + r.h)) - u.y;
        const pad = Math.max(0.01, Math.max(...touched.map((r) => r.h)));
        const within = b.x >= u.x - pad && b.y >= u.y - pad && b.x + b.w <= u.x + u.w + pad && b.y + b.h <= u.y + u.h + pad;
        if (within) { ignored.push({ box: b, text: touched.map((r) => r.text).join(' / ').slice(0, 80) }); continue; }
      }
      keep.push(b);
    }
    return { keep, ignored };
  };
}
