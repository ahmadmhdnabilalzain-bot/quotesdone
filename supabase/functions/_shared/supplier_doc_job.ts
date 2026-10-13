// A SUPPLIER'S PROFILE OR CATALOGUE IS READ IN THE BACKGROUND, A SLICE OF PAGES PER STEP.
// Seat: sales_engineer (the reading); it_engineer (the build). 13 Oct 2026, after #1412.
//
// WHY. Reading a real profile is a PDF parse bounded by the edge CPU cap (#1404: 700 ms of pages per worker) plus up
// to four model calls (#1412: choose, check, one retry each) that a single upload request cannot wait for. So the
// upload only stores the file, marks it 'reading' (markReading) and returns at once; supplier_api's read_docs_job then
// reads it in steps. Each step is its own invocation (its own CPU and wall time):
//   * a PDF: the next slice of pages (pdfjsText from the page the last step stopped at); the text so far is kept in
//     public.supplier_doc_read between steps and the document's evidence shows "pages N of M";
//   * when every page is read (or the file is not a PDF): the trades are chosen (readDocForTrades through
//     proposeTradesFromDocs), a picture or a PDF with no text layer first going to license_extract's profile mode;
//   * then the supplier gate is run again (fn_sales_engineer_verifies_supplier), since it held the supplier while the
//     document was 'reading'.
// A step that dies (a CPU kill, a worker timeout) leaves the document 'reading': the sweep of #1404 turns it unreadable
// after 30 minutes and hands it to the sales engineer. Nothing here is ever retried in a loop.
import { readDocument } from './doc_read/index.ts';
import { pdfjsText, PDFJS_MAX_PAGES } from './doc_read/pdf.ts';
import { LIMITS } from './doc_read/types.ts';
import { toB64 } from './document_expiry.ts';
import { markReading, modelReadText, proposeTradesFromDocs, type DocKind } from './supplier_doc_trades.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;
export type JobDoc = { path: string; name: string; kind: DocKind; mime: string };
export type JobStep = { supplier_id: number; doc: JobDoc };
export type StepResult = { done: boolean; status: string; pages_read?: number; pages_total?: number; error?: string };
/** The model's reading of a picture or a text-less PDF: its services become the document's photo_text. */
export type ProfileReader = (doc: { b64: string; mime: string; filename: string; image: boolean }) => Promise<{ services: string[]; summary?: string; products?: string[] } | null>;

export const PROFILE_MODEL_MAX = 12 * 1024 * 1024;   // the largest file sent to the vision model (supplier_api)
export const MAX_STEPS = 40;                          // a document no read can finish in 40 steps is left to the sweep

/** Hand documents to the background read: each is marked 'reading' first (a dead step leaves it held), then one
 *  read_docs_job call is fired per document and not waited for. */
export async function startReadJobs(admin: Admin, supplierId: number, docs: JobDoc[], fire: (step: JobStep) => Promise<void>): Promise<{ status: 'reading'; docs: { path: string; name: string; kind: DocKind }[] }> {
  const list = docs.filter((d) => d.kind !== 'licence');
  if (list.length) await markReading(admin, supplierId, list);
  for (const d of list) await fire({ supplier_id: supplierId, doc: d }).catch(() => { /* the sweep catches a step that never ran */ });
  return { status: 'reading', docs: list.map((d) => ({ path: d.path, name: d.name, kind: d.kind })) };
}

/** Write the progress of a document still being read into its evidence, so the portal can show it. */
async function progress(admin: Admin, supplierId: number, path: string, pagesRead: number, pagesTotal: number | null) {
  const { data: cur } = await admin.from('supplier_capabilities').select('source_docs').eq('supplier_id', supplierId).maybeSingle();
  const src = (cur?.source_docs && typeof cur.source_docs === 'object') ? cur.source_docs : {};
  const docs = Array.isArray(src.docs) ? src.docs : [];
  const at = new Date().toISOString();
  const next = docs.map((d: { path: string; status?: string }) => (d.path === path && d.status === 'reading' ? { ...d, read_at: at, pages_read: pagesRead, pages_total: pagesTotal } : d));
  await admin.from('supplier_capabilities').update({ source_docs: { ...src, docs: next } }).eq('supplier_id', supplierId);
}

/** One step of the read. Returns whether the document is finished; the caller fires the next step when it is not. */
export async function runReadStep(admin: Admin, step: JobStep, readProfile: ProfileReader): Promise<StepResult> {
  const { supplier_id: sid, doc } = step;
  const { data: blob, error: dlErr } = await admin.storage.from('supplier-docs').download(doc.path);
  if (dlErr || !blob) return { done: false, status: 'error', error: 'the file could not be fetched: ' + String(dlErr?.message || 'missing') };
  const bytes = new Uint8Array(await blob.arrayBuffer());
  const isPdf = /pdf/i.test(doc.mime) || /\.pdf$/i.test(doc.path);
  let read: Awaited<ReturnType<typeof readDocument>> | undefined;
  if (isPdf && bytes.length <= LIMITS.maxBytes) {
    const { data: st } = await admin.from('supplier_doc_read').select('pages_read,pages_total,text,steps').eq('supplier_id', sid).eq('path', doc.path).maybeSingle();
    const steps = Number(st?.steps ?? 0);
    if (steps >= MAX_STEPS) return { done: false, status: 'too_many_steps', error: `${steps} steps without finishing` };
    const r = await pdfjsText(bytes, PDFJS_MAX_PAGES, undefined, undefined, Number(st?.pages_read ?? 0) + 1);
    if (r.status === 'failed') {
      read = { ok: false, error: 'pdf_unreadable', detail: `The PDF could not be read: ${r.detail}` };
    } else {
      const text = (st?.text ? st.text + '\n' : '') + r.text;
      const total = Math.min(r.of ?? r.pages, PDFJS_MAX_PAGES);
      if (r.pages < total && text.length < LIMITS.maxTextChars) {
        await admin.from('supplier_doc_read').upsert({ supplier_id: sid, path: doc.path, pages_read: r.pages, pages_total: total, text, steps: steps + 1, updated_at: new Date().toISOString() }, { onConflict: 'supplier_id,path' });
        await progress(admin, sid, doc.path, r.pages, total);
        return { done: false, status: 'reading', pages_read: r.pages, pages_total: total };
      }
      read = /\p{L}{2}/u.test(text)
        ? { ok: true, kind: 'pdf', text, tables: [], quantities: [], children: [], needs: null, notes: total < (r.of ?? total) ? [`Read ${total} of ${r.of} pages.`] : [] }
        : { ok: true, kind: 'pdf', text: '', tables: [], quantities: [], children: [], needs: 'ocr', notes: ['This PDF has no text layer (a scan, or CAD exported as lines); its words need OCR.'] };
    }
  } else {
    read = await readDocument(bytes, doc.name, doc.mime, 0, { textOnly: true });
  }
  // A picture, or a PDF with no text layer: the vision model reads its services (ruling 1177).
  let photo_text: string | undefined;
  const image = /^image\//i.test(doc.mime);
  if (doc.kind === 'profile' && bytes.length <= PROFILE_MODEL_MAX && (image || (read?.ok && read.needs === 'ocr'))) {
    const pf = await readProfile({ b64: toB64(bytes), mime: doc.mime, filename: doc.name, image }).catch(() => null);
    if (pf?.services?.length) photo_text = modelReadText('profile', pf.services);
  }
  const res = await proposeTradesFromDocs(admin, sid, [{ path: doc.path, name: doc.name, kind: doc.kind, mime: doc.mime, read, photo_text }]);
  await admin.from('supplier_doc_read').delete().eq('supplier_id', sid).eq('path', doc.path);
  // The gate held this supplier while the document was 'reading': run it again now that it is read.
  try { await admin.rpc('fn_sales_engineer_verifies_supplier', { p_lead_id: sid, p_source: 'documents_read' }); } catch (_e) { /* the next save re-runs it */ }
  return res.ok ? { done: true, status: res.docs[0]?.status ?? 'read' } : { done: true, status: 'error', error: res.error };
}
