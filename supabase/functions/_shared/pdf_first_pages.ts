// pdf_first_pages — A SUPPLIER'S OWN PDF CUT TO ITS FIRST PAGES, FOR A READING MODEL ONLY (moved here 18 Nov 2026, sales_engineer, from
// supplier_docs_later.ts, where it was written for the company profile on 3 Nov 2026, review of #1796). Two readers cut a long file before a
// model sees it, because the model bills per page and an edge function has ~2 s of CPU: the profile (supplier_docs_later.ts, its first 30
// pages) and, since founder ruling 1728, the licence slot (licence_pages.ts, the first pages of a file longer than any licence). One home, so
// scripts/checks/every_pdf_we_issue_is_on_our_template.mjs names one file that may load and save a supplier's PDF.
// Prevented by: _shared/supplier_docs_later.test.ts (a 45-page scan cut to 30), _shared/a_long_licence_file_is_read_by_its_first_pages.test.ts.

/** The supplier's own PDF with every page after the first `n` removed, or null when it cannot be cut. It EDITS the supplier's file (load,
 *  remove pages, save) and authors nothing: no new document, no copied or drawn page. That is the one shape
 *  scripts/checks/every_pdf_we_issue_is_on_our_template.mjs allows outside pdf_native; the copy goes to the model, never to a person.
 *  The removed pages' objects stay in the file, so it is no smaller than the original; the model is billed by the pages it is given,
 *  which is what the cut bounds. */
export async function firstPdfPages(bytes: Uint8Array, n: number): Promise<Uint8Array | null> {
  try {
    const { PDFDocument } = await import('https://esm.sh/pdf-lib@1.17.1');
    const doc = await PDFDocument.load(bytes, { ignoreEncryption: true, updateMetadata: false });
    for (let i = doc.getPageCount() - 1; i >= n; i--) doc.removePage(i);
    return await doc.save();
  } catch (_e) { return null; }
}
