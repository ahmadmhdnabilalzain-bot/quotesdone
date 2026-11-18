// pdf_first_pages — A SUPPLIER'S OWN PDF CUT TO ITS FIRST PAGES, FOR A READING MODEL ONLY (moved here 18 Nov 2026, sales_engineer, from
// supplier_docs_later.ts, where it was written for the company profile on 3 Nov 2026, review of #1796). Two readers cut a long file before a
// model sees it, because the model bills per page and an edge function has ~2 s of CPU: the profile (supplier_docs_later.ts, its first 30
// pages) and, since founder ruling 1728, the licence slot (licence_pages.ts, the first pages of a file longer than any licence). One home, so
// scripts/checks/every_pdf_we_issue_is_on_our_template.mjs names one file that may load and save a supplier's PDF.
// Prevented by: _shared/supplier_docs_later.test.ts (a 45-page scan cut to 30), _shared/a_long_licence_file_is_read_by_its_first_pages.test.ts.

/** The supplier's own PDF with every page after the first `n` removed, or null when it cannot be cut. It EDITS the supplier's file (load,
 *  remove pages, drop what nothing references any more, save) and authors nothing: no new document, no copied or drawn page. That is
 *  the one shape scripts/checks/every_pdf_we_issue_is_on_our_template.mjs allows outside pdf_native; the copy goes to the model, never
 *  to a person.
 *  WHAT NOTHING REFERENCES IS DROPPED (review of #2054, 18 Nov 2026). pdf-lib's removePage leaves the removed pages' objects in the file,
 *  so a 28-page, 12 MB scan cut to 3 pages was still 12 MB: measured, encoding it again cost 444 ms of CPU, decoding it for the text
 *  layer 1,281 ms, and the model was sent 16 MB of base64 for three pages. Every object no longer reachable from the trailer (Root,
 *  Info) is deleted before the save, so the cut holds the first pages' own objects only (3 of 28 pages: ~1.3 MB). */
export async function firstPdfPages(bytes: Uint8Array, n: number): Promise<Uint8Array | null> {
  try {
    const { PDFDocument, PDFDict, PDFArray, PDFRef, PDFStream } = await import('https://esm.sh/pdf-lib@1.17.1');
    const doc = await PDFDocument.load(bytes, { ignoreEncryption: true, updateMetadata: false });
    const before = doc.getPageCount();
    for (let i = before - 1; i >= n; i--) doc.removePage(i);
    if (before > n) {
      const ctx = doc.context;
      const seen = new Set<string>();
      // deno-lint-ignore no-explicit-any
      const walk = (o: any) => {
        const stack = [o];
        while (stack.length) {
          const x = stack.pop();
          if (x instanceof PDFRef) { const k = x.toString(); if (seen.has(k)) continue; seen.add(k); stack.push(ctx.lookup(x)); }
          else if (x instanceof PDFStream) stack.push(x.dict);
          else if (x instanceof PDFDict) for (const [, v] of x.entries()) stack.push(v);
          else if (x instanceof PDFArray) for (const v of x.asArray()) stack.push(v);
        }
      };
      const t = ctx.trailerInfo;
      for (const r of [t.Root, t.Info, t.Encrypt]) if (r) walk(r);
      for (const [ref] of ctx.enumerateIndirectObjects()) if (!seen.has(ref.toString())) ctx.delete(ref);
    }
    return await doc.save();
  } catch (_e) { return null; }
}
