// doc_read/pdf — a PDF's text layer, plus scale-aware quantities from its vector drawing.
//
// WHAT IT READS. Text runs rebuilt into visual lines (the same pdfPages + linesOf the drawing BOQ has
// used since 14 Sep), and, where a page prints its scale ("SCALE 1:100"), the stroked lengths and
// closed areas measured by pdf_measure. A PDF with no text layer — a scan, or CAD exported as lines —
// comes back needs:'ocr' with the reason, never an invented reading.
import { pdfPages } from '../pdf_text_positions.ts';
import { measurePdf } from '../pdf_measure.ts';
import { linesOf } from '../../drawing_boq/boq_from_text.ts';
import { type Qty, type ReadContext, type ReadResult, LIMITS, empty, ok } from './types.ts';

// WORDS ONLY, READ BY PDF.JS (13 Oct 2026, it_engineer; ACCURACY_real_profiles.md). A supplier's profile or catalogue
// (ctx.textOnly) is read for what it says, and the estate's own text reader (pdf_text_positions) is built for drawings:
// no font metrics, no xref. Measured on 29 real UAE company profiles: it returned 0 characters on two text PDFs
// (Royal Joinery 88 pages, Summertown 36), 20 runs for 36 pages of JAAN and 192 for 58 pages of ASGC, every glyph as
// its own word on three ("A D V A N C E D" - Maxfire, MAS Paints, Abu Hail), and Arabic in reverse order (BCG). pdf.js
// (unpdf, the serverless build doc_extract already runs on the edge) read every one of them in logical order, the
// 85 MB Al Shirawi brochure in 0.6 s. The drawing path (no textOnly) is unchanged; the old reader stays the fallback.
export async function pdfjsText(bytes: Uint8Array): Promise<string> {
  try {
    const { getDocumentProxy } = await import('https://esm.sh/unpdf@0.11.0');
    const pdf = await getDocumentProxy(bytes.slice());   // pdf.js takes ownership of the buffer it is given
    const out: string[] = [];
    let n = 0;
    for (let i = 1; i <= pdf.numPages && n < LIMITS.maxTextChars; i++) {
      const tc = await (await pdf.getPage(i)).getTextContent();
      // deno-lint-ignore no-explicit-any
      const page = tc.items.map((it: any) => (typeof it.str === 'string' ? it.str + (it.hasEOL ? '\n' : '') : '')).join('');
      out.push(page); n += page.length;
    }
    return out.join('\n').slice(0, LIMITS.maxTextChars);
  } catch (_e) { return ''; }
}

export async function readPdf(bytes: Uint8Array, ctx: ReadContext): Promise<ReadResult> {
  if (ctx.textOnly) {
    const text = await pdfjsText(bytes);
    if (/\p{L}{2}/u.test(text)) return ok({ kind: 'pdf', text, tables: [], quantities: [], children: [], needs: null, notes: [] });
  }
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
