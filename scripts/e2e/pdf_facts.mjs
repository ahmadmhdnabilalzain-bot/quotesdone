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
  const runs = [];
  for (let i = 1; i <= Math.min(doc.numPages, 4); i++) {
    const items = (await (await doc.getPage(i)).getTextContent()).items;
    text += items.map((x) => x.str).join(' ') + '\n';
    // Where each run sits, so the money can be read in the page's reading order (moneyOf below).
    // pdfjs's y grows upward; it is negated so lines sort top to bottom.
    for (const x of items) if (x.str && x.transform) runs.push({ text: x.str, page: i, x: x.transform[4], y: -x.transform[5], w: Number(x.width) || 0 });
  }
  await doc.destroy().catch(() => {});
  const letters = text.match(/\p{L}/gu) || [];
  const arabic = letters.filter(isArabic).length;
  return { ok: true, bytes, sha256, creator: String(meta.info?.Creator || ''), pages: doc.numPages, text, runs, arabicShare: letters.length ? arabic / letters.length : 0 };
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
/**
 * The money a quotation states, in the order it states it: every amount written with two decimals
 * (rates, line amounts, the subtotal, the total). MEASURED 22 Sep 2026 on the production pair
 * QD-8B287960-A (en 99,734 bytes / 0% Arabic, ar 124,215 bytes / 78% Arabic): both read
 * 95.00, 17,100.00, 42.00, 8,820.00, 25,920.00, 25,920.00 - pdf_native writes Western digits in the
 * Arabic render too, so this is comparable across the two languages.
 */
export const amounts = (f) => String(f?.text || '').match(/\d[\d,]*\.\d\d/g) || [];

/**
 * Do two renders of one quotation state the same money? The languages differ on purpose; the
 * numbers must not. This is the assertion that "not the same file" alone cannot make: a translation
 * that quietly re-prices, drops a line or loses the total is a different document AND wrong.
 */
/**
 * The money a page states IN ITS READING ORDER (23 Sep 2026). pdf_native draws a right-to-left line as
 * visual runs from left to right (render.ts drawRTL), so an extractor reads an Arabic line's figures
 * backwards: the nightly of 23 Sep 00:40Z read the Arabic quotation's note "the line amounts add up to
 * 118,520.00 while the quoted total is 118,500.00" as 118,500.00 then 118,520.00 and reported that the
 * Arabic quotation states different money: same figures, same labels, read in the wrong direction.
 * Figures are grouped into lines (page, then baseline within `tol`), lines top to bottom, each line's
 * figures left to right, or right to left on an Arabic page. A figure's place inside one run is its
 * share of the run's width. Nothing is sorted by value, so a swapped subtotal and total still fail.
 */
export function amountsInReadingOrder(runs, rtl, tol = 2) {
  const hits = [];
  for (const r of runs || []) {
    const t = String(r.text || '');
    for (const m of t.matchAll(/\d[\d,]*\.\d\d/g)) hits.push({ v: m[0], page: r.page ?? 0, y: r.y, x: r.x + (t.length ? (m.index / t.length) * (r.w || 0) : 0) });
  }
  hits.sort((a, b) => a.page - b.page || a.y - b.y);
  const lines = [];
  for (const h of hits) { const last = lines[lines.length - 1]; if (last && last[0].page === h.page && Math.abs(last[0].y - h.y) <= tol) last.push(h); else lines.push([h]); }
  return lines.flatMap((l) => l.sort((a, b) => (rtl ? b.x - a.x : a.x - b.x)).map((h) => h.v));
}
/** A read PDF's money: in reading order when its runs are known, else in extraction order. */
export const moneyOf = (f) => (Array.isArray(f?.runs) && f.runs.length ? amountsInReadingOrder(f.runs, languageOf(f) === 'ar') : amounts(f));

export function sameMoney(a, b) {
  const [x, y] = [moneyOf(a), moneyOf(b)];
  if (!x.length || !y.length) return { comparable: false, same: null, why: `no amounts read: ${x.length} and ${y.length}` };
  const same = x.length === y.length && x.every((v, i) => v === y[i]);
  return { comparable: true, same, why: same ? `${x.length} amounts agree (total ${x[x.length - 1]})` : `amounts differ: [${x.join(' ')}] vs [${y.join(' ')}]` };
}

export function sameDocument(a, b) {
  const size = (f) => (f?.ok && f.bytes?.length) || 0;
  if (!size(a) || !size(b)) return { comparable: false, same: null, why: `cannot compare: ${size(a)} and ${size(b)} bytes` };
  const norm = (t) => String(t || '').replace(/\s+/g, ' ').trim();
  const sameBytes = a.sha256 === b.sha256;
  const sameText = norm(a.text) !== '' && norm(a.text) === norm(b.text);
  return { comparable: true, same: sameBytes || sameText, why: `${size(a)} vs ${size(b)} bytes, sha ${a.sha256.slice(0, 10)} vs ${b.sha256.slice(0, 10)}, text ${sameText ? 'identical' : 'differs'}` };
}
