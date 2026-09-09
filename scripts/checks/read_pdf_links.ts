// READS A RENDERED PDF BACK AND REPORTS WHAT IS ACTUALLY IN IT.
//
//   deno run -A scripts/checks/read_pdf_links.ts <file.pdf>
//
// Prints JSON: { pages, bytes, links: [{ page, uri, rect }], streams: [<sha256:length per page>] }.
//
// WHY THIS IS NOT A GREP. pdf-lib writes cross-reference streams and object streams, so the page
// dictionaries — and every /Annot in them — are Flate-compressed inside the file. A regex over the
// bytes for "/Subtype /Link" finds nothing in a document that is full of links, which is exactly the
// kind of zero that reads like a finding. The file is parsed instead.
//
// `streams` is the per-page digest of the DRAWING INSTRUCTIONS. Two documents whose content streams
// hash the same drew the same thing, whatever their file lengths say about timestamps and
// compressed cross-reference tables — which is how "a document that passes no link renders exactly
// as it did before" is proved rather than asserted.
//
// Deno rather than Node because pdf-lib is not an npm dependency of this repository, and Deno is the
// runtime the edge function that WROTE the file uses.
import { PDFArray, PDFDict, PDFDocument, PDFName, PDFStream, PDFString } from 'https://esm.sh/pdf-lib@1.17.1';

const file = Deno.args[0];
if (!file) { console.error('usage: read_pdf_links.ts <file.pdf>'); Deno.exit(2); }

const bytes = await Deno.readFile(file);
const doc = await PDFDocument.load(bytes);
const pages = doc.getPages();
const links: { page: number; uri: string; rect: number[] }[] = [];
const streams: string[] = [];

for (let i = 0; i < pages.length; i++) {
  const node = pages[i].node;

  const cs = node.Contents();
  let raw = new Uint8Array();
  const take = (s: PDFStream) => {
    const c = (s as unknown as { getContents(): Uint8Array }).getContents();
    const j = new Uint8Array(raw.length + c.length); j.set(raw); j.set(c, raw.length); raw = j;
  };
  if (cs instanceof PDFArray) { for (let k = 0; k < cs.size(); k++) take(doc.context.lookup(cs.get(k)) as PDFStream); }
  else if (cs) take(doc.context.lookup(cs) as PDFStream);
  const h = await crypto.subtle.digest('SHA-256', raw as unknown as ArrayBuffer);
  streams.push([...new Uint8Array(h)].map((b) => b.toString(16).padStart(2, '0')).join('').slice(0, 16) + ':' + raw.length);

  const annots = node.lookupMaybe(PDFName.of('Annots'), PDFArray);
  if (!annots) continue;
  for (let k = 0; k < annots.size(); k++) {
    const a = doc.context.lookup(annots.get(k), PDFDict);
    if (!a || String(a.get(PDFName.of('Subtype'))) !== '/Link') continue;
    const act = a.lookupMaybe(PDFName.of('A'), PDFDict);
    const uri = act?.get(PDFName.of('URI'));
    const rect = a.lookupMaybe(PDFName.of('Rect'), PDFArray);
    links.push({
      page: i + 1,
      uri: uri instanceof PDFString ? uri.decodeText() : String(uri),
      rect: rect ? [...Array(rect.size()).keys()].map((n) => Number(String(rect.get(n)))) : [],
    });
  }
}

console.log(JSON.stringify({ pages: pages.length, bytes: bytes.length, links, streams }));
