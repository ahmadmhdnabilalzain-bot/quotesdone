// drawing_identity_text — the DETERMINISTIC half of drawing_redact: which runs of a drawing's PDF
// text layer name a party (client, consultant, contractor, project, phone, email, "Drawn by") and
// must be boxed before the page reaches a competing supplier.
//
// Lifted verbatim from supabase/functions/drawing_redact/index.ts on 21 Sep 2026 so it can be tested
// against the demo plan (scripts/lib/demo_pdf.mjs demoOfficePlanPdf) without an edge runtime:
// drawing_identity_text.test.ts proves the boxes cover every title-block identity run and none of
// the technical content (room names, dimensions, legend, scale, north arrow). Behaviour is
// byte-identical to the 14 Sep original; only the file moved.
//
// Written 14 Sep 2026 because every model route was held, so vision detection failed and no drawing
// page reached a supplier (website audit 14 Sep, finding 3: pages_out=0). A PDF exported from CAD or
// a PDF writer usually carries its title block as REAL TEXT with a position, and a position can be
// boxed without a model. It never publishes a page on its own: a logo or a scanned title block has
// no text, so text-layer boxes without the customer's review or the verifier are not a clean page.
import type { PdfPage } from './pdf_text_positions.ts';
import { tradeOnly } from './drawing_vocabulary.ts';

export type Box = { x: number; y: number; w: number; h: number }; // normalised 0..1, top-left origin

/** Text that IS identity on its own: emails, URLs, UAE phones, company suffixes, Arabic firm words. The phone forms
 *  "(04) 123-4567", "04.123.4567", "050 1234 567" and digit-spaced "0 5 0 1 2 3 4 5 6 7" were added 25 Sep 2026
 *  (second review of #967: each reached a supplier's CAD page). */
export const ID_TEXT = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|\(?\b0\d{1,2}\)?[\s.\-]{0,2}\d{3,4}[\s.\-]?\d{3,4}\b|\b0(?:[\s.\-]\d){8,9}\b|\b(?:https?:\/\/|www\.)\S+|(?:\+|00)?971[\s-]?\d|\b0\d[\s-]?\d{3}[\s-]?\d{4}\b|\b05\d[\s-]?\d{3}[\s-]?\d{4}\b|\b(?:L\.?L\.?C|FZ-?LLC|FZE|FZCO|Est\.|Establishment|Consultants?|Contracting|Architects?|Developers?|Properties)\b|شركة|مؤسسة|ذ\.م\.م|مكتب\s+هندسي/i;
/** A PERSON NAMED AFTER AN HONORIFIC (round 3 of the anonymity fix, 13 Nov 2026). MEASURED on the reviewer's attack
 *  sheet v03: "HANDOVER TO MR ZZ DEMO RASHID" passed every code rule (no label, no seed, no company word), the vector PDF
 *  released to suppliers kept it in its text layer, and the preview hid it only because its neighbours' boxes happened
 *  to overlap the line. Mr / Mrs / Miss / Sheikh followed by words that are not all trade words names a person. MS (mild
 *  steel) and DR (a door, "Dr. Fixit") are left out: on a drawing they are materials and products far more often. */
const HONORIFIC = /\b(?:MR|Mr|MRS|Mrs|MISS|Miss|SHEIKH|Sheikh|SHAIKH|Shaikh)\.?\s+([A-Z][A-Za-z'\u2019\-]*(?:\s+[A-Z][A-Za-z'\u2019\-]*){0,3})/;
export function honorificPerson(text: string): boolean {
  const m = String(text || '').match(HONORIFIC);
  return !!m && !tradeOnly(m[1]);
}
/** Labels whose VALUE (the text to their right on the same line) is identity. */
export const ID_LABEL = /\b(drawn|checked|approved|prepared|reviewed|designed)\s*(by)?\b|\b(client|owner|employer|consultant|contractor|developer|project(?:\s*(?:name|no|number|title))?|plot(?:\s*no)?|makani|dwg\.?\s*no|drawing\s*no|address|tel|phone|mobile|fax|e-?mail)\b\s*[:.#]?|المالك|العميل|الاستشاري|المقاول|المشروع|رقم\s*القطعة|مكاني|رسم\s*بواسطة|اعتمد/i;

/**
 * Is this run a LABEL whose value is to its right? (second review, item 6, 13 Nov 2026.) ID_LABEL alone matched the word
 * "PLOT" in "PLOT BOUNDARY", so on the reviewer's 20 ordinary sheets the preview and the vector PDF lost "PLOT BOUNDARY"
 * (8 sheets) and the note printed beside it on the same line ("STAIR 2", "RAMP 1:8", "LEVEL 2"). A run is a label when a
 * "drawn / checked / approved by" names someone, when a colon or # follows the label, when nothing but the label is left,
 * or when what follows is not plain trade words ("CLIENT MR ZZ DEMO", "PLOT NO 345"); "PLOT BOUNDARY", "OWNER
 * ENTRANCE"-like trade phrases describe what is drawn and are content.
 */
export function isLabelRun(text: string): boolean {
  const t = String(text || '');
  const m = t.match(ID_LABEL);
  if (!m) return false;
  if (m[2] || /[:：#]/.test(m[0]) || /^\s*[:：#]/.test(t.slice((m.index ?? 0) + m[0].length))) return true;
  const rest = (t.slice(0, m.index ?? 0) + ' ' + t.slice((m.index ?? 0) + m[0].length)).replace(/[\s:：.#\-]+/g, ' ').trim();
  return !rest || !tradeOnly(rest);
}

export function textLayerBoxes(pages: PdfPage[], pageIndex: number): { boxes: Box[]; rotated: boolean } {
  const p = pages[pageIndex];
  if (!p) return { boxes: [], rotated: false };
  // Runs are in the display frame since 21 Sep 2026 (pdf_text_positions applies /Rotate), so a rotated
  // page is boxed like any other; `rotated` stays in the result for callers and is always false.
  const boxes: Box[] = [];
  for (const r of p.runs) {
    if (ID_TEXT.test(r.text) || honorificPerson(r.text)) { boxes.push({ x: r.x, y: r.y, w: r.w, h: r.h }); continue; }
    if (isLabelRun(r.text)) {
      // The label's value is the text to its right on the same line; cover the label and that run.
      const base = r.y + r.h;
      const line = p.runs.filter((o) => Math.abs((o.y + o.h) - base) <= r.h * 0.6 && o.x >= r.x && o.x <= r.x + r.w + 0.25);
      const x2 = Math.max(...line.map((o) => o.x + o.w), r.x + r.w);
      boxes.push({ x: r.x, y: r.y, w: Math.min(1 - r.x, x2 - r.x), h: r.h });
    }
  }
  return { boxes, rotated: false };
}
