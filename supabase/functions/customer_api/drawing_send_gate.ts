// drawing_send_gate — what may be written for suppliers from a request's drawing, decided at Send. Assigned: sales_engineer.
//
// WHY (evidence run ea40c830, 10 Nov 2026; docs/reports/2026-11-10-journey-evidence.md, still-seen item 2; ruling 1608).
// Journey 2's HVAC drawing was read in the customer's browser by OCR, because the portal had cut analyze_drawing at its
// 30 s fetch deadline (the server answered 200 after 39.7 s). The take-off of that OCR text held 13 junk lines, one of them
// ending "Mir. 22 Demo Owner": the title block's client, "Mr. ZZ Demo Owner", misread. Nothing stopped it on the way:
//   * the lines create_inquiry stores on inquiries.boq come from the request BODY (the composer's drawing.boq), so whatever
//     the browser read is what this function is given - the server-side gate in drawing_boq does not bind it;
//   * redactBoq knows the customer's ACCOUNT name, email, phone, project and file name. A drawing's client, consultant and
//     plot are the title block's words, not the account's, so redactBoq had nothing to look for;
//   * spec.boq_check.lines (supplier-facing: inquiries_supplier_safe.spec) was copied from the lines BEFORE redactBoq ran.
// In that run the customer then attached a BOQ sheet, whose lines replace a drawing's (src/lib/requestAttachments.ts), so
// the supplier copy carried the sheet's 10 lines and not the OCR line. Without the sheet, the OCR line was the BOQ.
//
// THE RULE, BY CONSTRUCTION: every BOQ written for suppliers passes drawing_identity_gate.gateDrawingBoq with the title
// strip's own terms, read HERE from the stored original (customer_api/lib/drawings.storedDrawingTerms), whatever read the
// lines and whatever the browser sent. A line carrying a term - as written or as OCR misreads it - is dropped; identity
// left outside the lines holds the whole BOQ. A drawing-derived BOQ whose drawing cannot be read back is held, because
// nothing can prove it clean. The open-line record (spec.boq_check) is taken from the gated lines only.
//
// NOT COVERED, AND SAID: a scan or a photo has no text layer, so no title-block term exists to look for; its lines pass the
// gate's shapes (phones, emails, firm names, plots, "Client:" labels) and folding, not a title-block match. The customer's
// own words (summary, the brief's details) are not the drawing's and are scrubbed where they always were.
import { gateDrawingBoq } from '../_shared/drawing_identity_gate.ts';

export type SendGate<T> = { boq: T | null; held: null | 'drawing_unreadable' | 'identity_left'; dropped_lines: number };

/** terms: the stored drawing's own identity terms; null when the file could not be read back. */
export function gateAtSend<T>(boq: T | null, terms: string[] | null, briefSource: string | null): SendGate<T> {
  if (!boq) return { boq: null, held: null, dropped_lines: 0 };
  // Lines read from a drawing nobody can read back cannot be proved clean. A customer's own BOQ sheet or quotation is
  // not the drawing's: it still passes the gate (with no title-block term) and redactBoq after it.
  if (terms === null && (briefSource === 'drawing' || briefSource === null)) return { boq: null, held: 'drawing_unreadable', dropped_lines: 0 };
  const g = gateDrawingBoq(boq, terms || [], false);
  if (!g.boq) return { boq: null, held: 'identity_left', dropped_lines: g.dropped_lines };
  return { boq: g.boq, held: null, dropped_lines: g.dropped_lines };
}
