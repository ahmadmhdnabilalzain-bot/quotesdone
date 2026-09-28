// drawing_format — which drawing formats a customer may upload. Assigned: sales_engineer.
// Founder ruling, 28 Sep 2026: customer drawing uploads accept ONLY PDF and CAD (DWG and DXF). Revit
// (RVT/RFA), IFC, DGN and every other drawing/model format are refused with one friendly message.
// The Revit, IFC and DGN readers were deleted (PR #1022, folded into #983); the refusal happens here:
// customer_api refuses by name and mime before storing, and drawing_boq refuses by the SNIFFED type
// (readDocument's pdfCadDrawingsOnly), which also covers a renamed file and a model inside a zip.
// Spreadsheets, Word, email and GAEB are BOQ/documents, not drawings, and are not affected.

export const DRAWING_FORMAT_ERROR = 'drawing_format_not_accepted';
export const DRAWING_FORMAT_MESSAGE = 'Please upload your drawing as PDF or CAD (DWG/DXF).';
export const DRAWING_FORMAT_MESSAGE_AR = 'يُرجى رفع المخطط بصيغة PDF أو CAD ‏(DWG/DXF).';

// Revit, IFC, MicroStation, DWF, SketchUp, Rhino, Navisworks, STEP, ArchiCAD.
const REFUSED_EXT = /\.(rvt|rfa|rte|rft|ifc|ifczip|ifcxml|dgn|dgnlib|dwf|dwfx|skp|3dm|nwd|nwc|nwf|step|stp|pln)$/i;
// Types doc_read's sniffer assigns to those files (attachment.ts SAFE_BIM, minus GAEB which is a BOQ).
export const REFUSED_DRAWING_MIMES: ReadonlySet<string> = new Set(['application/vnd.autodesk.revit', 'application/x-step', 'image/vnd.dgn']);
const REFUSED_MIME = /revit|x-step|ifc|dgn|dwf|sketchup|navisworks/i;

export type DrawingFormatRefusal = { ok: false; error: string; code: string; message: string; message_ar: string };

export const drawingFormatRefused = (): DrawingFormatRefusal =>
  ({ ok: false, error: DRAWING_FORMAT_ERROR, code: DRAWING_FORMAT_ERROR, message: DRAWING_FORMAT_MESSAGE, message_ar: DRAWING_FORMAT_MESSAGE_AR });

/** The refusal for a drawing format the ruling does not accept, or null when the file may go on. */
export function drawingFormatRefusal(name: string, mime = ''): DrawingFormatRefusal | null {
  return REFUSED_EXT.test(String(name || '').trim()) || REFUSED_MIME.test(String(mime || '')) ? drawingFormatRefused() : null;
}
