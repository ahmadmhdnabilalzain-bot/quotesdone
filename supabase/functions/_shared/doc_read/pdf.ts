// doc_read/pdf — a PDF's text layer, plus scale-aware quantities from its vector drawing.
//
// WHAT IT READS. Text runs rebuilt into visual lines (the same pdfPages + linesOf the drawing BOQ has
// used since 14 Sep), and, where a page prints its scale ("SCALE 1:100"), the stroked lengths and
// closed areas measured by pdf_measure. A PDF with no text layer — a scan, or CAD exported as lines —
// comes back needs:'ocr' with the reason, never an invented reading.
import { pdfPages } from '../pdf_text_positions.ts';
import { measurePdf } from '../pdf_measure.ts';
import { linesOf } from '../../drawing_boq/boq_from_text.ts';
import { getDocumentProxy } from 'npm:unpdf@0.11.0';
import { type Qty, type ReadContext, type ReadResult, LIMITS, empty, ok, refuse } from './types.ts';

export async function readPdf(bytes: Uint8Array, ctx: ReadContext): Promise<ReadResult> {
  const pages = await pdfPages(bytes);
  if (!pages.length) return ok(empty('pdf', ['The PDF could not be opened (encrypted, damaged or not a PDF).']));
  const lines = linesOf(pages);
  const notes: string[] = [];
  let quantities: Qty[] = [];
  if (!ctx.textOnly) try {
    const m = await measurePdf(bytes);
    quantities = m.pages.flatMap((p) => p.quantities).slice(0, LIMITS.maxQuantities);
    notes.push(...m.notes);
  } catch (_e) { notes.push('The drawing geometry could not be measured.'); }
  if (!lines.length) {
    return ok({ ...empty('pdf', [...notes, 'This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR.'], 'ocr'), quantities });
  }
  return ok({ kind: 'pdf', text: lines.map((l) => l.text).join('\n').slice(0, LIMITS.maxTextChars), tables: [], quantities, children: [], needs: null, notes });
}
