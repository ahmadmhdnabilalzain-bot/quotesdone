import { readEveryAttachment, type Vision } from '../../_shared/read_every_attachment.ts';
import { readDocument } from '../../_shared/doc_read/index.ts';
import { quoteFromExtracted, quoteText } from '../../quote_extract/quote_from_document.ts';
import { type QuoteTermKey } from '../../_shared/reasoned_suppliers.ts';
import { type FileRead } from './types.ts';

// ---------------------------------------------------------------------------------------------
// Reading a quotation file — doc_read and quote_from_document read the PRICES with no model (the same pair
// quote_extract uses on its deterministic path). The TERMS (validity, lead time, payment, warranty,
// exclusions, installation) are what the file means, so they are REASONED by `readTerms` (quote_review_actions
// passes _shared/reasoned_suppliers.ts quoteTerms; founder_instruction 886-903). Held or absent: the
// terms stay empty and the review asks the supplier for them — never a label guess.
// ---------------------------------------------------------------------------------------------
/**
 * THE VISION MODEL WRITES MARKDOWN (13 Oct 2026, measured live). read_every_attachment's prompt asks for tables "as
 * markdown tables", so a photographed quotation comes back as "| Jotun ... | 450 | m2 | 20.00 | 9,000.00 |". The price
 * reader parses CSV and plain lines, and it read that transcription as NO quotation. Each table row becomes a CSV row
 * (numbers lose their thousands separators), separator rows and **emphasis** / # headings go; every other line stays.
 * prevented by: supplier_api/quote_review.test.ts ('a photographed quotation transcribed as a markdown table is priced')
 */
// ONLY TABLE ROWS ARE TOUCHED (review of #1396): a line outside a pipe table passes through byte for byte. Inside a
// cell, a comma goes only when it is a THOUSANDS separator (9,000.00 -> 9000.00; "1,5" and "12,50" are decimal commas
// and stay as written, CSV-quoted); Arabic-Indic digits and the Arabic separators (U+066C thousands, U+066B decimal)
// are read the same way; an escaped \| stays inside its cell; a short or merged row keeps the cells it has.
const ESC_PIPE = '\u0000';
const AR_DIGIT = /[\u0660-\u0669\u06F0-\u06F9]/g;
const THOUSANDS = /(^|[^\d,.])(-?\d{1,3}(?:,\d{3})+)(?=\.\d+(?![\d,])|(?![\d,.]))/g;
function tableCell(raw: string): string {
  let c = raw.replace(new RegExp(ESC_PIPE, 'g'), '|').trim().replace(/^(\*\*|__)(.*)\1$/, '$2').trim();
  c = c.replace(AR_DIGIT, (d) => String((d.charCodeAt(0) & 0xf) % 10)).replace(/\u066C/g, ',').replace(/\u066B/g, '.');
  c = c.replace(THOUSANDS, (_m, pre: string, n: string) => pre + n.replace(/,/g, ''));
  return /[",]/.test(c) ? '"' + c.replace(/"/g, '""') + '"' : c;
}
export function transcriptAsText(md: string): string {
  const isRow = (l: string) => /^\s*\|.*\|\s*$/.test(l);
  const isSep = (l: string) => /^\s*\|[\s:|-]*-{2,}[\s:|-]*\|\s*$/.test(l);
  return String(md ?? '').split(/\r?\n/).flatMap((l) => {
    if (!isRow(l)) return [l];
    if (isSep(l)) return [];
    const cells = l.replace(/\\\|/g, ESC_PIPE).trim().replace(/^\|/, '').replace(/\|$/, '').split('|');
    return [cells.map(tableCell).join(',')];
  }).join('\n');
}

export async function readQuotationFile(bytes: Uint8Array, filename: string, mime: string, supplierTerms: string[] = [],
  readTerms?: (text: string) => Promise<Partial<Record<QuoteTermKey, string>> | null>, vision?: Vision | null): Promise<FileRead> {
  const rd = await readDocument(bytes, filename, mime);
  if (!rd.ok && rd.error !== 'unreadable_document') return { proposal: null, text: '', kind: 'refused' };
  // RULING 1177 (12 Oct 2026): a photo or a scan of a quotation is READ — the vision model transcribes it (one more
  // asking, the gateway's second model) and the transcription goes through the SAME parser as typed lines. Before,
  // a scan got 'image' and a request for a text PDF. Unreadable only when both askings fail.
  if (vision && (!rd.ok || (!rd.text.trim() && !rd.tables.length && !rd.children.length))) {
    const a = await readEveryAttachment(bytes, filename, mime, vision);
    if (a.status === 'read' && a.by === 'model') return readQuotationFile(new TextEncoder().encode(transcriptAsText(a.text)), 'quotation.txt', 'text/plain', supplierTerms, readTerms, null);
    return { proposal: null, text: '', kind: rd.ok ? rd.kind : 'image', reason: a.reason };
  }
  if (!rd.ok) return { proposal: null, text: '', kind: 'refused' };
  const texts: string[] = [];
  // deno-lint-ignore no-explicit-any
  const visit = (e: any) => { if (e.text) texts.push(e.text); for (const t of e.tables || []) texts.push(t.map((r: unknown[]) => (r || []).join(' ')).join('\n')); for (const c of e.children || []) visit(c.doc); };
  visit(rd);
  const priced = quoteFromExtracted(rd, supplierTerms);
  const empty = priced.amount == null && !priced.line_items.some((l) => l.amount != null);
  // No model is asked about a file with no price.
  const terms = !empty && readTerms ? await readTerms(quoteText(rd)).catch(() => null) : null;
  const p = terms ? quoteFromExtracted(rd, supplierTerms, terms) : priced;
  return { proposal: empty ? null : p, text: texts.join('\n'), kind: rd.kind };
}
