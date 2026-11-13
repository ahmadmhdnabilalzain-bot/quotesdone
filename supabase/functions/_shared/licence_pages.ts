// licence_pages — A FILE LONGER THAN ANY TRADE LICENCE IS ANSWERED BEFORE ANY MODEL IS ASKED (13 Nov 2026, sales_engineer; founder
// ruling 1681: "A trade license can never be more than 5 pages, let's say ... someone attached something more than 5 pages blindly,
// the AI, without even reading, he would know this is not a trade license"). An exact count is code's job, like a size limit.
//
// WHY 8 AND NOT 5. Measured 13 Nov 2026: the founder's own real trade licence PDF has 4 pages; the certification's licence fixtures
// have 1; the accuracy corpus's multipage licences have 2; real company profiles are usually 10 to 40 pages (our ZZ DEMO profiles 1 to
// 2, which the page rule does not catch: the reader names them). One more page of partners or activities makes a real licence 5 or 6,
// and refusing a real licence without reading it is the one mistake a supplier cannot get past alone. ONE constant, so the founder can
// change it. A PDF whose pages cannot be counted (encrypted, damaged) goes to the reader as before; an image is one page; page pictures
// sent by a caller count as their number.
// Prevented by: _shared/the_reader_decides_what_is_a_trade_licence.test.ts.
import type { WrongDocument } from './licence_extract.ts';
import { NOT_A_LICENCE_WAY_TO_A_PERSON } from './licence_extract.ts';

export const LICENCE_MAX_PAGES = 8;

const bytesOf = (b64: string) => Uint8Array.from(atob(String(b64).replace(/^data:[^;]+;base64,/, '')), (c) => c.charCodeAt(0));

/** How many pages the file in the licence slot has, or null when code cannot count them (the reader then reads it as before). */
// deno-lint-ignore no-explicit-any
export async function licencePageCount(body: { images?: any[]; file_b64?: string; mime?: string }): Promise<number | null> {
  const images = Array.isArray(body.images) ? body.images : [];
  if (images.length) return images.length;
  if (!body.file_b64) return null;
  if (/^image\//i.test(String(body.mime || ''))) return 1;
  try {
    const bytes = bytesOf(String(body.file_b64));
    if (!(bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46)) return null;   // not %PDF
    const { getDocumentProxy } = await import('npm:unpdf@0.11.0');
    const pdf = await getDocumentProxy(bytes);
    const n = Number(pdf.numPages);
    try { await pdf.destroy?.(); } catch (_e) { /* the count is what matters */ }
    return Number.isInteger(n) && n > 0 ? n : null;
  } catch (_e) { return null; }   // encrypted, damaged: not counted, read by the reader as before
}

/** The sentence for a file longer than any licence (the count stated, what to do, and a way to a person). */
export const longFileSentence = (pages: number): string =>
  `This file has ${pages} pages. A trade licence is a short document, usually 1 to 4 pages, so this is not one. Please attach your trade licence here on its own. If this is your company profile, it goes in the Company profile box below. If your licence is inside this file, please attach just the licence pages. ${NOT_A_LICENCE_WAY_TO_A_PERSON}`;

/** The finding for a file longer than LICENCE_MAX_PAGES, or null (the reader reads it). */
export function tooManyPagesForALicence(pages: number | null): WrongDocument | null {
  if (pages == null || pages <= LICENCE_MAX_PAGES) return null;
  return { kind: 'long_file', why: `the file has ${pages} pages; a trade licence has at most ${LICENCE_MAX_PAGES}`, message: longFileSentence(pages) };
}
