// scripts/e2e/journey_proof/dossier.ts — renders ONE journey's dossier PDF from its record, on the QuotesDone template,
// and binds the evidence after it. Seat: customer_support. Founder ledger 1684 (13 Nov 2026), 1671/1672 (every document
// is a PDF in our template).
//
//   deno run --no-lock --node-modules-dir=none --allow-read --allow-write scripts/e2e/journey_proof/dossier.ts <journey dir> [out.pdf]
//     <journey dir> holds record.json and every file it names; out.pdf defaults to "<dir>/Journey <key> dossier.pdf".
//
// THE TEMPLATE IS NOT COPIED. The report pages are drawn by supabase/functions/pdf_native/render.ts (renderPdf), the
// renderer every QuotesDone document goes through, wearing the letterhead of _shared/doc_template.ts. The exhibits after
// it are the platform's own documents (the signed-terms certificate, the inquiry, each quotation as the customer sees it,
// the comparison, the invoice) and the files people gave it (a supplier's own quotation, the customer's drawing), bound
// UNALTERED, each behind a one-page divider that is itself drawn by renderPdf. Nothing on an exhibit page is redrawn.
// Files that are not PDFs (voice notes, a spreadsheet, the raw record) are attached inside the PDF.
//
// Fonts are the committed copies (pdf_native/fixtures/brand). The logo lockup is read from the public brand bucket only
// when QD_BRAND_URL is set (e.g. https://<ref>.supabase.co/storage/v1/object/public/brand); without it the letterhead
// prints its words and no logo, exactly as the renderer degrades when the bucket cannot be read.
import { PDFDocument } from 'https://esm.sh/pdf-lib@1.17.1';
import { renderPdf } from '../../../supabase/functions/pdf_native/render.ts';
import { dossierBody, type Img } from './dossier_body.ts';

const FONTS = new URL('../../../supabase/functions/pdf_native/fixtures/brand/', import.meta.url);
const BRAND_URL = (() => { try { return Deno.env.get('QD_BRAND_URL') || ''; } catch { return ''; } })();
export async function fetchBytes(p: string): Promise<Uint8Array | null> {
  if (/\.ttf$/.test(p)) { try { return await Deno.readFile(new URL(p, FONTS)); } catch { return null; } }
  if (!BRAND_URL || /qd_(stamp|signature)\.png$/.test(p)) return null;   // the seal is never fetched for a report
  try { const r = await fetch(`${BRAND_URL}/${p}`); return r.ok ? new Uint8Array(await r.arrayBuffer()) : null; } catch { return null; }
}

// deno-lint-ignore no-explicit-any
type Any = any;
const join = (dir: string, f: string) => (f.startsWith('/') ? f : `${dir.replace(/\/$/, '')}/${f}`);
const isPdf = (b: Uint8Array) => b.length > 4 && b[0] === 0x25 && b[1] === 0x50 && b[2] === 0x44 && b[3] === 0x46;
const mimeOf = (f: string) => /\.wav$/i.test(f) ? 'audio/wav' : /\.xlsx$/i.test(f) ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' : /\.json$/i.test(f) ? 'application/json' : /\.png$/i.test(f) ? 'image/png' : /\.jpe?g$/i.test(f) ? 'image/jpeg' : /\.txt$/i.test(f) ? 'text/plain' : 'application/octet-stream';

/** Build the whole dossier: report pages, then each exhibit behind its divider, then the attachments. */
export async function buildDossier(rec: Any, dir: string): Promise<{ bytes: Uint8Array; pages: number; report_pages: number; dropped: number; missing: string[] }> {
  const missing: string[] = [];
  const read = (f: string): Uint8Array | null => { try { return Deno.readFileSync(join(dir, f)); } catch { missing.push(f); return null; } };
  const img = (f: string): Img => { const b = read(f); if (!b) return null; return { bytes: b, kind: b[0] === 0x89 ? 'png' : 'jpg' }; };
  // the exhibits: a PDF is bound, anything else is attached
  const ex = (rec.exhibits || []).map((e: Any, i: number) => { const b = read(e.file); return { ...e, n: i + 1, bytes: b, pdf: !!b && isPdf(b) }; });
  const pdfEx = ex.filter((e: Any) => e.pdf);
  const pageCount = new Map<string, number>();
  for (const e of pdfEx) { try { pageCount.set(e.file, (await PDFDocument.load(e.bytes, { ignoreEncryption: true })).getPageCount()); } catch { e.pdf = false; } }
  // two passes: the report's own length decides where each exhibit starts, and the report prints those page numbers
  let pages = new Map<string, number>(); let body: Any = null; let out: Any = null;
  for (let pass = 0; pass < 4; pass++) {
    body = dossierBody(rec, { img, pageOf: (f) => pages.get(f) ?? null, exhibitNo: (f) => ex.find((e: Any) => e.file === f)?.n ?? null });
    out = await renderPdf(body, { fetchBytes });
    if (!out.ok) throw new Error('the template refused the dossier: ' + JSON.stringify(out.body));
    const next = new Map<string, number>(); let at = out.meta.pages + 1;
    for (const e of pdfEx.filter((x: Any) => x.pdf)) { next.set(e.file, at); at += 1 + (pageCount.get(e.file) || 0); }
    const same = [...next].every(([k, v]) => pages.get(k) === v) && next.size === pages.size;
    pages = next; if (same && pass > 0) break;
  }
  const doc = await PDFDocument.load(out.bytes);
  const reportPages = doc.getPageCount();
  for (const e of pdfEx.filter((x: Any) => x.pdf)) {
    const div = await renderPdf({ title: `Exhibit ${e.n}`, lang: 'en', cover: { compact: true, kicker: `EXHIBIT ${e.n}`, title: e.title, subtitle: `${pageCount.get(e.file)} page${pageCount.get(e.file) === 1 ? ' follows' : 's follow'}, exactly as issued: ${e.file.split('/').pop()}`, meta: [['Journey', `Journey ${rec.journey?.key}`], ['Run', String(rec.journey?.run_tag || '—')]] },
      blocks: [{ t: 'p', text: String(e.why || '') }, { t: 'note', text: e.ours === false ? 'This file is NOT on the QuotesDone template, on purpose: it is the file a person gave the platform, shown so you can compare it with what the platform made of it.' : 'This document was issued by the platform on the QuotesDone template; it is bound here unaltered.' }], options: { letterhead: true } }, { fetchBytes });
    if (!div.ok) throw new Error('divider refused: ' + JSON.stringify(div.body));
    const d = await PDFDocument.load(div.bytes); for (const pg of await doc.copyPages(d, d.getPageIndices())) doc.addPage(pg);
    const src = await PDFDocument.load(e.bytes, { ignoreEncryption: true }); for (const pg of await doc.copyPages(src, src.getPageIndices())) doc.addPage(pg);
  }
  for (const e of ex.filter((x: Any) => !x.pdf && x.bytes)) await doc.attach(e.bytes, e.file.split('/').pop(), { mimeType: mimeOf(e.file), description: e.title });
  await doc.attach(new TextEncoder().encode(JSON.stringify(rec, null, 1)), 'record.json', { mimeType: 'application/json', description: 'the run\'s raw record this dossier was printed from' });
  // the properties say what the document is and nothing about either party
  doc.setTitle(`QuotesDone journey ${rec.journey?.key} proof`); doc.setSubject(String(rec.journey?.short || rec.journey?.title || '')); doc.setKeywords([]); doc.setAuthor('QuotesDone Technologies'); doc.setCreator('QuotesDone pdf_native (journey dossier)');
  const bytes = await doc.save();
  return { bytes, pages: doc.getPageCount(), report_pages: reportPages, dropped: out.meta.glyphs_dropped, missing: [...new Set(missing)] };
}

if (import.meta.main) {
  const [dir, outArg] = Deno.args;
  if (!dir) { console.error('usage: dossier.ts <journey dir> [out.pdf]'); Deno.exit(2); }
  const rec = JSON.parse(await Deno.readTextFile(join(dir, 'record.json')));
  const out = outArg || join(dir, `Journey ${rec.journey?.key} dossier.pdf`);
  const r = await buildDossier(rec, dir);
  await Deno.writeFile(out, r.bytes);
  console.log(JSON.stringify({ out, pages: r.pages, report_pages: r.report_pages, glyphs_dropped: r.dropped, missing_files: r.missing }));
  if (r.dropped) console.error(`WARNING: ${r.dropped} character(s) could not be drawn in the template's fonts`);
}
