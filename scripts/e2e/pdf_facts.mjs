// scripts/e2e/pdf_facts.mjs — what the journeys read out of a PDF: bytes, template, language, identity.
// Seat: sales_engineer (the customer's quotation PDF). Split out of journey_audit_buttons.mjs on 22 Sep
// 2026 so a check can import it without loading fixtures.mjs (which reads the management token).
//
// WHY THE BYTES ARE COPIED BEFORE PARSING (22 Sep 2026, measured). pdfjs-dist 4.x TRANSFERS the buffer
// it is given to its worker, so the caller's Uint8Array is detached and reads length 0 afterwards
// (the repository's own fixture quotation: 1,475 bytes before getDocument, 0 after). pdfFacts kept that
// detached array as `bytes`, and journey h compared the English and Arabic quotations with it — two
// empty buffers, always equal — so "the Arabic quotation is not the English file" FAILED every night
// (run 35671806988, 00:40Z) while the same run read the English file as 3 pages / 0% Arabic and the
// Arabic one as 2 pages / 79% Arabic. The product was right; the comparison could not see.
// pdfjs now gets a copy, and sameDocument refuses to compare an empty buffer rather than calling it
// equal — scripts/checks/the_arabic_quotation_is_never_the_english_file.test.mjs fails if either
// part comes back.
import { createHash } from 'node:crypto';

// pdf_native shapes Arabic before it draws it, so the text a PDF reader extracts is in the Arabic
// PRESENTATION FORMS (U+FB50–FDFF, U+FE70–FEFF), not the base block. Measured on the first run
// (21 Sep 2026): every Arabic document read as 0% Arabic against the base block alone.
export const isArabic = (ch) => /[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]/.test(ch);
export const languageOf = (f) => (f.arabicShare >= 0.3 ? 'ar' : f.arabicShare < 0.2 ? 'en' : 'mixed');

/** Facts about PDF bytes. `bytes` in the result is the caller's data, intact. */
export async function pdfFactsFromBytes(input) {
  const bytes = new Uint8Array(input);   // our own copy: the caller's buffer is never handed to pdfjs
  if (bytes.length < 5 || Buffer.from(bytes.subarray(0, 5)).toString() !== '%PDF-') {
    return { ok: false, why: `not a PDF (${Buffer.from(bytes.subarray(0, 12)).toString().replace(/\W+/g, ' ')})` };
  }
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  const pdfjs = await import('pdfjs-dist/legacy/build/pdf.mjs');
  const doc = await pdfjs.getDocument({ data: bytes.slice(), isEvalSupported: false, verbosity: 0 }).promise;
  const meta = await doc.getMetadata().catch(() => ({ info: {} }));
  let text = '';
  for (let i = 1; i <= Math.min(doc.numPages, 4); i++) text += (await (await doc.getPage(i)).getTextContent()).items.map((x) => x.str).join(' ') + '\n';
  await doc.destroy().catch(() => {});
  const letters = text.match(/\p{L}/gu) || [];
  const arabic = letters.filter(isArabic).length;
  return { ok: true, bytes, sha256, creator: String(meta.info?.Creator || ''), pages: doc.numPages, text, arabicShare: letters.length ? arabic / letters.length : 0 };
}

/** Fetch a URL and read it as a PDF. */
export async function pdfFacts(url) {
  if (!url) return { ok: false, why: 'no url' };
  const r = await fetch(url).catch((e) => ({ ok: false, status: 0, e }));
  if (!r.ok) return { ok: false, why: `HTTP ${r.status}` };
  return pdfFactsFromBytes(new Uint8Array(await r.arrayBuffer()));
}

/**
 * Are two read PDFs the same document? Same bytes, or the same extracted text (a re-render of one
 * document with a new timestamp is still the same document). An empty or unread side is NOT
 * comparable — the defect this replaced called two empty buffers "the same file".
 */
export function sameDocument(a, b) {
  const size = (f) => (f?.ok && f.bytes?.length) || 0;
  if (!size(a) || !size(b)) return { comparable: false, same: null, why: `cannot compare: ${size(a)} and ${size(b)} bytes` };
  const norm = (t) => String(t || '').replace(/\s+/g, ' ').trim();
  const sameBytes = a.sha256 === b.sha256;
  const sameText = norm(a.text) !== '' && norm(a.text) === norm(b.text);
  return { comparable: true, same: sameBytes || sameText, why: `${size(a)} vs ${size(b)} bytes, sha ${a.sha256.slice(0, 10)} vs ${b.sha256.slice(0, 10)}, text ${sameText ? 'identical' : 'differs'}` };
}
