// licence_pages — A FILE LONGER THAN ANY TRADE LICENCE IS READ BY ITS FIRST PAGES, AS A PERSON WOULD OPEN IT (18 Nov 2026, sales_engineer;
// founder ruling 1728). Code counts the pages; the model decides what the file is.
//
// WHAT CHANGED. Ruling 1681 (13 Nov 2026: "A trade license can never be more than 5 pages ... someone attached something more than 5
// pages blindly, the AI, without even reading, he would know this is not a trade license") refused a PDF of more than LICENCE_MAX_PAGES
// before any model was asked. Measured 17 Nov 2026: Shine Carpets' 28-page "TRADE LCS SHINE CARPETS WASHING LLC.pdf", the licence on
// its first pages, was filed "Not a trade licence" unread. Ruling 1728 (18 Nov 2026): read the first pages, enough to judge, and judge
// like a human, from ANY UAE licensing authority (Dubai DET mainland and every free zone and emirate: licence_extract.ts SYS_LICENSE
// names them); if a licence is on those pages it is read as the licence. So a longer file is now cut to its first
// LONG_FILE_PAGES_READ pages (page pictures by count; a PDF by pdf_first_pages.ts, which edits nothing but the page list) and those
// pages go to the same reader, told which pages it holds (longFileNote). Its answer decides, exactly as for a short file: a licence is
// the reading; a company profile or anything else at 'high' is named, with the pages read and "attach just the licence pages"
// (longFileNotALicenceSentence); an unsure answer goes to the second read and then a person (licence_extract.ts outcomes).
//
// WHY 3 PAGES. A trade licence prints its authority, number, name and expiry on page 1 (the founder's own DET licence: 4 pages, the
// fields on page 1; the accuracy corpus's multipage licences: 2), and a renewal receipt or cover page may come first. Three pages is the
// first-pages window a person reads to judge, and it bills three pages, not twenty-eight. A PDF above LONG_FILE_CUT_MAX_BYTES, or one
// pdf-lib cannot open, with no page pictures beside it, is answered by its count as before (tooManyPagesForALicence), never sent whole.
//
// CPU, THE WHOLE REQUEST (review of #2054, measured 18 Nov 2026 on a 28-page, 12.0 MB scanner-style PDF, one image per page, and 20
// portal pictures of 1071x1516; license_extract's path from the request's JSON to the gateway body, with the text layer and the SHA,
// no model call; process.cpuUsage, two runs, cold / warm): PDF alone 493-519 / 353-378 ms; 20 pictures + PDF, switch off 317-320 /
// 210-242 ms (the PDF is not cut: firstPagesOfALongFile sendsPdf); switch on 296-465 / 283-324 ms. Under the edge's ~2 s cap. Before
// the review's fixes the same request cost 2,297-3,526 ms: the cut kept the removed pages' objects (12 MB for 3 pages), and two
// base64 decodes used Uint8Array.from with a callback (1,281 ms and 1,106 ms for 12 MB). The page count is the file's own when
// pictures and the PDF both come (pdfRaster renders at most 20), so a 28-page file reads "the first 3 of its 28 pages".
//
// WHY 8 STAYS. Measured 13 Nov 2026: real licences have 1 to 4 pages (6 with partners or activities); real company profiles 10 to 40.
// Up to 8 pages a file is read whole, as before. ONE constant each, so the founder can change them.
// Prevented by: _shared/a_long_licence_file_is_read_by_its_first_pages.test.ts, _shared/the_reader_decides_what_is_a_trade_licence.test.ts.
import type { WrongDocument } from './licence_extract.ts';
import { NOT_A_LICENCE_WAY_TO_A_PERSON, pageB64, wrongDocumentLead } from './licence_extract.ts';
import { firstPdfPages } from './pdf_first_pages.ts';

export const LICENCE_MAX_PAGES = 8;
/** How many first pages of a longer file the reader is given (ruling 1728). */
export const LONG_FILE_PAGES_READ = 3;
/** A longer PDF above this size is not cut in an edge function (the profile cut's bound, supplier_docs_later.ts PROFILE_PDF_MODEL_MAX). */
export const LONG_FILE_CUT_MAX_BYTES = 12 * 1024 * 1024;

// One decode per file per request: the count and the cut read the same bytes (a 12 MB file is 16 MB of base64; measured below).
let lastB64 = '', lastBytes = new Uint8Array(0);
const bytesOf = (b64: string): Uint8Array => {
  if (b64 === lastB64) return lastBytes;
  const bin = atob(String(b64).replace(/^data:[^;]+;base64,/, ''));
  const u = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
  lastB64 = b64; lastBytes = u;
  return u;
};
/** The file's bytes from its base64 (the same decode, cached for the request's one file); callers that hand them to pdf.js pass a copy. */
export const b64Bytes = (b64: string): Uint8Array => bytesOf(b64);
const b64Of = (u8: Uint8Array) => { let s = ''; for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode(...u8.subarray(i, i + 0x8000)); return btoa(s); };
const isPdf = (b: Uint8Array) => b[0] === 0x25 && b[1] === 0x50 && b[2] === 0x44 && b[3] === 0x46;   // %PDF

/** How many pages the file in the licence slot has, or null when code cannot count them (the reader then reads it as before).
 *  Page pictures count as their number, except when there are more than LICENCE_MAX_PAGES and the PDF is beside them: the browser
 *  renders at most 20 (src/components/me/pdfRaster.ts PDF_MAX_PAGES), so a 28-page file sends 20 pictures and is counted from the
 *  file itself (review of #2054: "3 of its 20 pages" for a 28-page file). Below that the pictures are every page. */
// deno-lint-ignore no-explicit-any
export async function licencePageCount(body: { images?: any[]; file_b64?: string; mime?: string }): Promise<number | null> {
  const images = Array.isArray(body.images) ? body.images : [];
  if (images.length && !(images.length > LICENCE_MAX_PAGES && body.file_b64 && !/^image\//i.test(String(body.mime || '')))) return images.length;
  if (!body.file_b64) return images.length || null;
  const own = await pdfPageCountOf(body);
  return own ?? (images.length || null);
}
// deno-lint-ignore no-explicit-any
async function pdfPageCountOf(body: { file_b64?: string; mime?: string }): Promise<number | null> {
  if (/^image\//i.test(String(body.mime || ''))) return 1;
  try {
    const bytes = bytesOf(String(body.file_b64));
    if (!isPdf(bytes)) return null;
    const { getDocumentProxy } = await import('npm:unpdf@0.11.0');
    const pdf = await getDocumentProxy(bytes.slice());   // a copy: pdf.js detaches the buffer it is given, and the cut reads these bytes next
    const n = Number(pdf.numPages);
    try { await pdf.destroy?.(); } catch (_e) { /* the count is what matters */ }
    return Number.isInteger(n) && n > 0 ? n : null;
  } catch (_e) { return null; }   // encrypted, damaged: not counted, read by the reader as before
}

/** Which pages of a long file the reader was given: the first `read` of `of`. */
export type LongFileWindow = { read: number; of: number };
// deno-lint-ignore no-explicit-any
export type LicencePayload = { images?: any[]; file_b64?: string; mime?: string; filename?: string };

/** A file longer than LICENCE_MAX_PAGES as its first LONG_FILE_PAGES_READ pages, or null when it is not longer, or when its first pages
 *  cannot be given without sending the whole file (then tooManyPagesForALicence answers it). Page pictures are kept by count. The PDF is
 *  cut (pdf_first_pages.ts) ONLY when it will be sent: there are no usable pictures, or `sendsPdf` (license_extract's
 *  licence_read_sends_the_pdf switch). Otherwise it is dropped unread: loading and saving a file nobody is sent spends the edge's CPU
 *  for nothing (review of #2054). A PDF that must be sent and cannot be cut is never sent whole. */
export async function firstPagesOfALongFile(payload: LicencePayload, pages: number | null, opts: { sendsPdf?: boolean } = {}): Promise<{ payload: LicencePayload; window: LongFileWindow } | null> {
  if (pages == null || pages <= LICENCE_MAX_PAGES) return null;
  const k = LONG_FILE_PAGES_READ;
  const images = Array.isArray(payload.images) ? payload.images : [];
  const out: LicencePayload = { ...payload, images: images.slice(0, k) };
  const pictured = out.images!.some((im) => !!pageB64(im));
  if (payload.file_b64 && pictured && !opts.sendsPdf) delete out.file_b64;   // the pictures are its first pages; the PDF is never sent
  else if (payload.file_b64 && !/^image\//i.test(String(payload.mime || ''))) {
    let cut: Uint8Array | null = null;
    try {
      const bytes = bytesOf(String(payload.file_b64));
      if (isPdf(bytes) && bytes.length <= LONG_FILE_CUT_MAX_BYTES) cut = await firstPdfPages(bytes, k);
    } catch (_e) { cut = null; }
    if (cut) { out.file_b64 = b64Of(cut); out.mime = 'application/pdf'; }
    else if (out.images!.length) delete out.file_b64;
    else return null;
  }
  if (!out.images!.length && !out.file_b64) return null;
  return { payload: out, window: { read: Math.min(k, pages), of: pages } };
}

/** Said to the reader after its intro: the file is longer, and these are its first pages. */
export const longFileNote = (w: LongFileWindow): string =>
  `This file has ${w.of} pages; you are given only its first ${w.read}. Judge them as a person opening the file would: say whether a UAE trade licence from any UAE licensing authority (an emirate's economic department or any free zone) is on these pages, or whether the file is a company profile or something else; if a licence is on these pages, read it as the licence.`;

/** The sentence when the first pages of a long file are not a licence: what they are, the pages read, what to do, a way to a person. */
export const longFileNotALicenceSentence = (kind: unknown, w: LongFileWindow): string =>
  `${wrongDocumentLead(kind)} We read the first ${w.read} of its ${w.of} pages. If your licence is inside this file, please attach just the licence pages. ${NOT_A_LICENCE_WAY_TO_A_PERSON}`;

/** A long file's finding names the pages that were read (the kind and the reason stay the reader's). */
export function withLongFileWindow(wrong: WrongDocument, w: LongFileWindow): WrongDocument {
  return { ...wrong, message: longFileNotALicenceSentence(wrong.kind, w), why: `${wrong.why} (pages 1-${w.read} of ${w.of} read)`.trim() };
}

/** The sentence for a long file whose first pages could not be given to the reader (too large to cut, or it cannot be opened). */
export const longFileSentence = (pages: number): string =>
  `This file has ${pages} pages, and we could not open it to read its first pages. A trade licence is a short document, usually 1 to 4 pages. Please attach your trade licence here on its own. If this is your company profile, it goes in the Company profile box below. If your licence is inside this file, please attach just the licence pages. ${NOT_A_LICENCE_WAY_TO_A_PERSON}`;

/** The finding for a file longer than LICENCE_MAX_PAGES whose first pages could not be read, or null (the reader reads it). */
export function tooManyPagesForALicence(pages: number | null): WrongDocument | null {
  if (pages == null || pages <= LICENCE_MAX_PAGES) return null;
  return { kind: 'long_file', why: `the file has ${pages} pages and its first pages could not be read; a trade licence has at most ${LICENCE_MAX_PAGES}`, message: longFileSentence(pages) };
}
