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

// WORDS ONLY, READ BY PDF.JS (13 Oct 2026, it_engineer; ACCURACY_real_profiles.md). A supplier's profile or catalogue
// (ctx.textOnly) is read for what it says, and the estate's own text reader (pdf_text_positions) is built for drawings:
// no font metrics, no xref. Measured on 29 real UAE company profiles: it returned 0 characters on two text PDFs
// (Royal Joinery 88 pages, Summertown 36), 20 runs for 36 pages of JAAN and 192 for 58 pages of ASGC, every glyph as
// its own word on three ("A D V A N C E D" - Maxfire, MAS Paints, Abu Hail), and Arabic in reverse order (BCG). pdf.js
// (unpdf, the serverless build doc_extract already runs on the edge) read every one of them in logical order, the
// 85 MB Al Shirawi brochure in 0.6 s. The drawing path (no textOnly) is unchanged.
// BOUNDED (review of #1404): pdf.js is imported statically from a pinned npm: specifier (bundled at deploy, no runtime
// fetch), reads at most PDFJS_MAX_PAGES pages and gives up after PDFJS_DEADLINE_MS. A failure or an overrun is
// 'failed' - logged, and held by the caller as unreadable - never '' (which would read as a scan with no text layer).
// THE LAM-ALEF LIGATURE COMES OUT REVERSED (measured on the BCG Arabic brochure, 13 Oct 2026): pdf.js gives the glyph
// "لا" back as "ال", so "الأساسات" reads "األساسات" and "الانتهاء" "االنتهاء". At the START of a word the swap is
// unambiguous - no Arabic word begins alef, alef, lam - and is undone there. Inside a word it is not ("أعمال" ends in a
// real alef-lam), so it is left: an exact Arabic name split by it is missed, never matched wrongly.
// AFTER A ONE-LETTER PREFIX TOO, AND ANYWHERE FOR A HAMZA ALEF (3 Nov 2026, sales_engineer; scripts/e2e/document_reading_qualification.ts:
// the services of every Arabic profile of the generated set reached the model as "واإلنذار" for "والإنذار" and "واإلنارة" for
// "والإنارة", 0 of 80 gold lines intact). The article very often follows a conjunction or preposition written as one letter on the
// word (و ف ب ك ل: "والإنارة", "بالإضافة"), and alef followed directly by a hamza alef (اأ اإ اآ) is no Arabic spelling, so that
// swap is undone wherever it stands. Alef-alef-lam with no hamza is still undone only at a word start or after one such letter.
const AR_LIGATURE_START = /(^|[^؀-ۿ]|(?:^|[^؀-ۿ])[وفبكل])ا(ا)ل/gu;
const AR_LIGATURE_HAMZA = /ا([أإآ])ل/gu;
export const arabicLigatureFix = (t: string) => t.replace(AR_LIGATURE_HAMZA, 'ال$1').replace(AR_LIGATURE_START, '$1ال$2');
// THE BUDGET IS CPU, NOT WALL TIME (review of #1404). The edge worker is killed at about 2 s of CPU, and a kill runs no
// catch. pdf.js works on bytes already in memory, so its time between pages IS its CPU time; measured locally on the 28
// real PDFs (13 Oct 2026): opening a 25 MB file <= 30 ms, one page 3-37 ms on average and 211 ms at worst, a whole
// 208-page profile 1.7 s. So the read stops starting pages once PDFJS_BUDGET_MS is spent - 700 ms + the worst page +
// the open stays near half the cap - and the document says how many pages were read. Bytes are capped before the
// open (LIMITS.maxBytes, 25 MB). A kill is still possible on a pathological file, so the CALLER marks the document
// 'reading' before the parse (supplier_doc_trades.markReading): a kill leaves it held, never silently missing.
// 1000 PAGES, NOT 250 (3 Nov 2026, sales_engineer; scripts/e2e/document_reading_qualification.ts). The page cap was a second
// bound on what the budget and LIMITS.maxTextChars already bound, and it was the one that bit: a 300-page text profile was read
// to page 250 in 237 ms (locally) and its services on page 270 were never read. The budget and the text cap still stop the read.
export const PDFJS_MAX_PAGES = 1000, PDFJS_BUDGET_MS = 700, SCAN_PROBE_PAGES = 3;
export type PdfjsRead = { status: 'text' | 'no_text' | 'failed'; text: string; pages: number; of?: number; detail?: string };
// ABOVE LIMITS.maxBytes THE BUFFER IS HANDED OVER, NOT COPIED (19 Oct 2026, sales_engineer): copying an 85 MB brochure
// took the read to 265 MB, past the edge's 256 MB; handing it over keeps it at 171 MB (measurements in types.ts LIMITS).
// pdf.js detaches what it is handed, so a caller passing a file that large must not use those bytes again.
// RESUMABLE (3 Nov 2026): fromPage starts a read where an earlier one stopped; `pages` is then the last page read (absolute), so
// a document read over several runs keeps one ledger: pages 1..pages read, pages+1..of still to read (supplier_docs_later.stuckOf).
export async function pdfjsText(bytes: Uint8Array, maxPages = PDFJS_MAX_PAGES, budgetMs = PDFJS_BUDGET_MS, now: () => number = () => performance.now(),
  maxBytes: number = LIMITS.maxBytes, fromPage = 1): Promise<PdfjsRead> {
  const t0 = now();
  const first = Math.max(1, Math.floor(fromPage));
  let pages = first - 1;
  try {
    if (bytes.length > maxBytes) throw new Error(`${bytes.length} bytes is over the ${maxBytes} read limit`);
    const pdf = await getDocumentProxy(bytes.length > LIMITS.maxBytes ? bytes : bytes.slice());   // pdf.js takes ownership of the buffer it is given
    const out: string[] = [];
    let n = 0, words = false;
    for (let i = first; i <= Math.min(pdf.numPages, maxPages) && n < LIMITS.maxTextChars; i++) {
      // a partial read, said so in `pages` / `of`. The first page is always read: on a busy worker, opening a 19 MB profile
      // alone spent the budget, 0 pages were read and the text PDF was reported as a scan with no text layer (N01, 19 Oct 2026).
      // SCAN_PROBE_PAGES are always read (3 Nov 2026): a first page without words under load is not yet a verdict (below).
      if (pages >= first + (words ? 0 : SCAN_PROBE_PAGES - 1) && now() - t0 > budgetMs) break;
      const tc = await (await pdf.getPage(i)).getTextContent();
      // deno-lint-ignore no-explicit-any
      const page = tc.items.map((it: any) => (typeof it.str === 'string' ? it.str + (it.hasEOL ? '\n' : '') : '')).join('');
      out.push(page); n += page.length; pages = i; words ||= /\p{L}{2}/u.test(page);
    }
    const text = arabicLigatureFix(out.join('\n')).slice(0, LIMITS.maxTextChars);
    // a continuation is never judged a scan: the document's first pages had words, so later pages without any are simply read
    if (/\p{L}{2}/u.test(text) || first > 1) return { status: 'text', text, pages, of: pdf.numPages };
    // A SCAN UNDER LOAD WAS HELD UNREADABLE FOR GOOD (3 Nov 2026, sales_engineer; scripts/e2e/document_reading_qualification.ts). A
    // 20-page image-only profile read on a busy worker spent the budget on page 1, came back 'failed' ("The PDF could not be read") and
    // was never sent to the model; nothing re-reads an unreadable document. Now SCAN_PROBE_PAGES pages are read before the budget may
    // stop a read that has found no words yet (an image page's text content is cheap: its pixels are not decoded), and that many pages
    // without one word is a scan. ponytail: a text PDF opening with SCAN_PROBE_PAGES image-only pages is read as a scan (the model reads
    // its first PROFILE_PDF_PAGES pages; the ledger records the rest as unread). Fewer pages read than that is still held unreadable.
    if (pages < Math.min(pdf.numPages, maxPages, first + SCAN_PROBE_PAGES - 1)) return { status: 'failed', text: '', pages, detail: `no text on the first ${pages} of ${pdf.numPages} pages before the reading budget was spent` };
    return { status: 'no_text', text, pages, of: pdf.numPages };
  } catch (e) {
    const detail = String((e as Error)?.message || e).slice(0, 200);
    console.error(JSON.stringify({ at: 'doc_read.pdfjsText', status: 'failed', bytes: bytes.length, pages, ms: Math.round(now() - t0), detail }));
    return { status: 'failed', text: '', pages, detail };
  }
}

export async function readPdf(bytes: Uint8Array, ctx: ReadContext): Promise<ReadResult> {
  if (ctx.textOnly) {
    const r = await pdfjsText(bytes, PDFJS_MAX_PAGES, PDFJS_BUDGET_MS, undefined, ctx.maxBytes, ctx.fromPage);
    if (r.status === 'failed') return refuse('pdf_unreadable', `The PDF could not be read: ${r.detail}`);
    if (r.status === 'no_text') return ok(empty('pdf', ['This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR.'], 'ocr'));
    const notes = r.of && r.pages < r.of ? [`Read ${r.pages} of ${r.of} pages within the reading budget.`] : [];
    return ok({ kind: 'pdf', text: r.text, tables: [], quantities: [], children: [], needs: null, notes, ...(r.of ? { pages: { read: r.pages, of: r.of } } : {}) });
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
