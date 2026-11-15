// drawing_hold — what analyze_drawing hands back about the drawing, decided in one place. Assigned: sales_engineer.
//
// WHY (customer audit 21 Sep 2026, finding 9). A PDF whose title block the server could not box
// (anonymise.titleBlockBoxes: low) went to the model; the gateway refused; drawing_redact recorded
// detect_failed with no pages. customer_api then answered drawing_redacted_paths:[] and the composer
// told the customer to "mark what to hide below" — an editor that no longer opens (the customer's boxes
// stopped counting as verification on 14 Sep). Nothing reached a supplier (inquiries_supplier_safe
// carries no drawing_file_path, measured 21 Sep), but the customer was never told the drawing was HELD,
// and a PARTIAL run's pages were handed back and refused at Send (409 redaction_incomplete): a dead end.
//
// The rule: the supplier copy exists only when EVERY page came back verified. Anything less is a hold —
// no redacted paths leave this function, share_redacted is false, and the hold is said out loud.
import { PIXEL_BUDGET_MESSAGE } from '../_shared/drawing_pixel_gate.ts';

export type RedMeta = { redaction_pages_in: number; redaction_pages_out: number; redaction_complete: boolean };

export function drawingHandoff(meta: RedMeta, originalPath: string | null, redacted: string[]) {
  const held = !!originalPath && !meta.redaction_complete;
  return {
    drawing_redacted_paths: meta.redaction_complete ? redacted : [],
    drawing_held: held,
    // The explicit opt-out resolveRedactedPaths already honours: a held drawing shares nothing.
    ...(held ? { share_redacted: false as const } : {}),
  };
}

/** The ledger row for a held drawing (mirrors the 'boq_held' row create_inquiry writes). */
export function heldRun(o: { customerId: string; email: string; sourcePath: string; meta: RedMeta; reason: string }) {
  return {
    customer_id: o.customerId, owner_email: o.email, source_path: o.sourcePath, output_paths: [] as string[],
    pages_in: o.meta.redaction_pages_in, pages_out: o.meta.redaction_pages_out, skipped: Math.max(0, o.meta.redaction_pages_in - o.meta.redaction_pages_out),
    status: 'held', pages_verified: o.meta.redaction_pages_out, verify_failed: Math.max(0, o.meta.redaction_pages_in - o.meta.redaction_pages_out),
    verify_detail: { reason: o.reason },
  };
}

// A CAD ORIGINAL IS SAID TO BE HELD ON EVERY PATH (22 Sep 2026, sales_engineer). analyze_drawing reads a
// .dwg / .dxf on two paths. With no pictures of it, drawing_boq reads the file and the answer says
// 'cad_read_not_pictured'. When cad_convert DID picture it, the same take-off came back through the
// pictured path, whose answer carried no note (production, sample_2000.dwg, 22 Sep: HTTP 200, 3 lines,
// no note). A CAD picture has no text layer, so the server cannot box its title block and drawing_redact
// holds the pages; the answer now names that the same way on both paths. A picture set that WAS fully
// verified is not held and is not called unpictured.
export function cadNote(isCad: boolean, hand: { drawing_held: boolean }) {
  return isCad && hand.drawing_held ? { note: 'cad_read_not_pictured' as const } : {};
}

/**
 * A VECTOR PDF GOES TO SUPPLIERS AS ITS CHECKED PREVIEWS ONLY (round 4 of the drawings fix, 15 Nov 2026, sales_engineer;
 * third review ANONYMITY F3 DRAWINGS 3, fix 3). drawing_redact mode 'file' stores an anonymised PDF as 'awaiting_pixels'
 * until the released file's own pages are rendered and checked (lib/drawings.ts verifyReleasedFile), and nothing calls
 * that yet (READ, 15 Nov 2026). So every vector PDF was held with "you can upload a clearer copy", which is false, and
 * left an unsigned pending file in storage. Until verifyReleasedFile is wired, analyze_drawing does not attempt the file
 * for a PDF: suppliers get the checked preview of each sheet, and the customer is told so in plain words. The original is
 * not sent by the platform after a reveal either (supplier_api inbox: drawing_file_url is null, READ), so the message says
 * the customer can send it himself once he has opened that supplier's quotation.
 */
export const PDF_PREVIEWS_ONLY = 'pdf_previews_only';
export const PDF_PREVIEWS_MESSAGE = {
  en: 'Suppliers see a cleaned picture of each sheet, with your details removed. The drawing file itself is not sent to them now: when you open a supplier\'s quotation, you can send that supplier the original file.',
  ar: 'يطّلع المورّدون على صورة منقّحة لكل لوحة بعد حذف بياناتك منها. أمّا ملف المخطّط نفسه فلا يُرسَل إليهم الآن، وعند فتح عرض سعر أحد المورّدين يمكنك إرسال الملف الأصلي إليه.',
} as const;

/**
 * THE ANONYMISED FILE WAS HELD, AND THE CUSTOMER IS TOLD (review of #1838, 3 Nov 2026). drawing_redact mode 'file'
 * holds the vector PDF when an image the size of a drawing lies across the title block (image_straddles_title_block)
 * and records the hold on drawing_redaction_runs — but analyze_drawing said nothing, so nobody knew the suppliers
 * would get the page pictures and not the file they measure from. The customer is the one person who can fix the
 * sheet, so the answer says why and what to do; the previews still go if they were verified.
 */
export function fileHeldNote(reason: string | null) {
  if (!reason) return {};
  if (reason === 'pixels_budget') return { drawing_file_held: reason, drawing_file_message: PIXEL_BUDGET_MESSAGE };
  // A vector PDF is not made into a file today (PDF_PREVIEWS_ONLY below); a run still waiting for its pixels is the same
  // case. "Upload a clearer copy" was false for both: no re-upload changes it.
  if (reason === PDF_PREVIEWS_ONLY || reason === 'awaiting_pixels') return { drawing_file_held: reason, drawing_file_message: PDF_PREVIEWS_MESSAGE };
  const straddles = reason === 'image_straddles_title_block';
  return {
    drawing_file_held: reason,
    drawing_file_message: straddles
      ? { en: 'Suppliers will see your drawing as pictures, but the drawing file itself was not shared: an image lies across the title block, so we could not remove your details from the file with certainty. Move the image clear of the title block, or delete it, and upload the drawing again.',
          ar: 'سيطّلع المورّدون على مخطّطك كصور، أمّا ملف المخطّط نفسه فلم يُشارَك: توجد صورة ممتدّة على إطار العنوان، فتعذّر علينا التأكّد من حذف بياناتك من الملف. أبعِد الصورة عن إطار العنوان أو احذفها، ثم ارفع المخطّط من جديد.' }
      : { en: 'Suppliers will see your drawing as pictures, but the drawing file itself was not shared: we could not remove your details from the file with certainty. You can upload a clearer copy of the drawing.',
          ar: 'سيطّلع المورّدون على مخطّطك كصور، أمّا ملف المخطّط نفسه فلم يُشارَك: تعذّر علينا التأكّد من حذف بياناتك من الملف. يمكنك رفع نسخة أوضح من المخطّط.' },
  };
}

/**
 * THE SET IS PAST WHAT THE MODEL CHECK MAY SPEND, AND THE CUSTOMER IS TOLD SO (round 3 of the anonymity fix, 13 Nov 2026).
 * drawing_redact answers `customer_message` (PIXEL_BUDGET_MESSAGE) when the pixel gate held a page for its budget, and
 * customer_api dropped it: the customer saw the general "drawing held" text, with no word that the sheets were too many to
 * check today. The answer now carries the plain message beside the hold.
 */
export function budgetNote(hit: boolean) {
  return hit ? { drawing_held_reason: 'pixels_budget' as const, drawing_held_message: PIXEL_BUDGET_MESSAGE } : {};
}
