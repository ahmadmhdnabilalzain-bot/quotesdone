// A SUPPLIER'S PROFILE AND CATALOGUES ARE READ AFTER THE ANSWER, AND MAY ARRIVE STRAIGHT IN STORAGE.
// Seat: sales_engineer. 19 Oct 2026, founder-confirmed requirements.
//
// MEASURED BEFORE THIS FILE. supplier_api.process_docs and supplier_portal.save_documents read the profile and the
// catalogues inside the upload request - the words, then up to four model calls in sequence (the trade chooser and its
// second look, license_extract's profile mode) - so the supplier watched a spinner and the request carried the edge's
// wall-time risk. And every file travelled as base64 in the request body, which Vercel caps at 4.5 MB, while the bucket
// capped a file at 25 MB: a 30-85 MB company brochure (3 of the 29 real UAE profiles) could not be uploaded at all.
//
// WHAT THIS DOES.
//   * signedUpload: a signed upload URL for a path in the supplier's OWN folder (profiles/<id>/, catalogs/<id>/). The
//     browser uploads straight to storage (uploadToSignedUrl), then names the path to process_docs / save_documents,
//     which check the path is the supplier's own and that storage holds it (storedAt) before recording it.
//   * gateStored: a file that arrived by path never passed sanitizeAndScan. Before it is read its stored bytes go
//     through the same type and malware gate; a refused file is recorded 'refused', removed from storage and from the
//     supplier's row, and never read.
//   * readStoredDocsLater: the read itself (gate -> the caller's profile hook -> proposeTradesFromDocs), one document at
//     a time so only one large file is in memory, run after the response by afterResponse (EdgeRuntime.waitUntil).
//     Each document is marked 'reading' BEFORE the response, so the portal shows it being read; when the read ends a
//     supplier the gate held for 'documents_being_read' is gated again.
//   * stuckReads: a document still 'reading' REREAD_AFTER_MIN minutes on is read once more by the sweep
//     (resilience_ping -> supplier_api docs_reread, every 30 min; and since 12 Nov 2026 pg_cron supplier_doc_reread_5min, every
//     5 min when something is due: a_supplier_document_whose_read_died_is_read_again_within_fifteen_minutes.sql), marked retry; a second stall is left to
//     fn_supplier_doc_reading_escalate (30 minutes), which hands it to the sales engineer. A document the model could not be
//     asked about (choice 'unavailable') is read together again from its kept text, with backoff (rereadTogether).
// It does NOT change how a document is read (supplier_doc_trades.ts) or the licence path, which stays in the request.
import { sanitizeAndScan } from './malware.ts';
import { SAFE_SUPPLIER_PAPERS, safeFilename } from './attachment.ts';
import { LIMITS } from './doc_read/types.ts';
import { liveTradeDeps } from './trade_resolve.ts';
import { knownNames, loadText, markReading, modelReadText, proposeFromRead, readTexts, type DocEvidence, type DocIn, type TradeResolveDeps } from './supplier_doc_trades.ts';
import { readDocument } from './doc_read/index.ts';
import { pagesLeft, pdfjsText } from './doc_read/pdf.ts';
import { toB64 } from './document_expiry.ts';
import { timedFetch } from './timed_fetch.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;
export const BUCKET = 'supplier-docs';
export const FOLDER = { profile: 'profiles', catalogue: 'catalogs' } as const;
export const REREAD_AFTER_MIN = 10;
/** gate: the file arrived by path and has not been through sanitizeAndScan yet. */
export type LaterDoc = DocIn & { gate?: boolean };

// A PICTURE, OR A PDF WITH NO TEXT LAYER, IS READ BY THE MODEL THE LICENCE USES (2 Nov 2026, founder ledger 1442: "Is our agent actually
// reading the company profile and the trade licence"; found by scripts/e2e/supplier_profile_read_walk.mjs, where a scanned profile
// stayed "needs_ocr" and a PNG's trades were never proposed). license_extract's profile mode returns the lines the page PRINTS, verbatim;
// they become the document's photo_text and are read for trades like a text layer's lines, each trade quoted from them (supplier_trade_choice).
// Two attempts, as the licence has, but a plain 4xx answer (the file itself was refused) is not asked again. A file it cannot read is left
// as it was (needs_ocr): never a false "no trades". supplier_portal.save_documents (the Documents tab) and supplier_api.process_docs
// (registration) BOTH read a profile through this one function; registration passes the page images the browser rendered and keeps the
// model's summary and services from the profile it returns.
//
// WHAT IT MAY COST (review of #1796): the model is billed per page and per image. So an image above PROFILE_IMAGE_MAX is not sent, a PDF above
// PROFILE_PDF_MODEL_MAX is not sent, and a PDF of more than PROFILE_PDF_PAGES pages is cut to its first pages (a profile says what the company
// does early; pdf-lib removes the later pages, and a PDF it cannot cut is not sent). Each is recorded on the document as the reason it was not read
// (`unread_reason`, worded for the supplier) instead of being sent whole. The call carries the supplier as its subject so the spend is theirs.
// ponytail: a big image is skipped, not downscaled (decoding 10 MB of JPEG is more CPU than an edge function has); upgrade: downscale to 2600 px.
export const PROFILE_PDF_MODEL_MAX = 12 * 1024 * 1024;
export const PROFILE_IMAGE_MAX = 10 * 1024 * 1024;
// 30 PAGES, NOT 10 (3 Nov 2026, sales_engineer; scripts/e2e/document_reading_qualification.ts). "A profile says what the company does
// early" is what the founder's 300-page scenario disproves: a 20-page scanned profile whose services are on page 15 was cut to pages
// 1-10 and its trades never reached the model (0 of 10 gold lines over 5 runs). One cut, one call, as before; the pages billed rise
// from 10 to at most 30 (license_extract: AED 0.0027-0.0048 a call, 30 days to 3 Nov). A longer scan is still cut, and the document
// now SAYS it was cut (DocIn.pages_read -> DocEvidence.pages).
// ponytail: one 30-page window per upload; upgrade: a window per sweep run (one cut + base64 of a 12 MB scan measured ~0.7 s CPU
// locally, so several windows in one edge run would pass the ~2 s CPU cap).
export const PROFILE_PDF_PAGES = 30;
export type ProfileAsk = (body: Record<string, unknown>) => Promise<{ ok?: boolean; status?: number; error?: string; profile?: { lines?: unknown; [k: string]: unknown } } | null>;
export type ProfileModelRead = { asked: boolean; ok: boolean; profile?: { lines?: unknown; [k: string]: unknown }; why?: string };

/** The number of pages pdf.js reports for a PDF (page objects can sit in compressed object streams, so they are not counted by pattern), or
 *  null when it cannot say: the caller then treats the file as over the cap. */
export async function pdfPageCount(bytes: Uint8Array): Promise<number | null> {
  const r = await pdfjsText(bytes, 1, undefined, undefined, LIMITS.maxPaperBytes);
  return typeof r.of === 'number' ? r.of : null;
}
/** The supplier's own PDF with every page after the first `n` removed, or null when it cannot be cut. It EDITS the supplier's file (load,
 *  remove pages, save) and authors nothing: no new document, no copied or drawn page. That is the one shape
 *  scripts/checks/every_pdf_we_issue_is_on_our_template.mjs allows outside pdf_native; the copy goes to the model, never to a person.
 *  The removed pages' objects stay in the file, so it is no smaller than the original (already under PROFILE_PDF_MODEL_MAX); the model
 *  is billed by the pages it is given, which is what the cut bounds. */
export async function firstPdfPages(bytes: Uint8Array, n: number): Promise<Uint8Array | null> {
  try {
    const { PDFDocument } = await import('https://esm.sh/pdf-lib@1.17.1');
    const doc = await PDFDocument.load(bytes, { ignoreEncryption: true, updateMetadata: false });
    for (let i = doc.getPageCount() - 1; i >= n; i--) doc.removePage(i);
    return await doc.save();
  } catch (_e) { return null; }
}

export async function readProfileByModel(d: LaterDoc, ask: ProfileAsk,
  o: { attempts?: number; subject?: unknown; images?: unknown[]; admin?: Admin } = {}): Promise<ProfileModelRead> {
  const attempts = o.attempts ?? 2;
  const mime = d.mime || '';
  let body: Record<string, unknown>;
  const own = !o.images?.length;   // the model reads this document's own bytes (so its lines become the document's photo_text)
  if (o.images?.length) body = { images: o.images.slice(0, PROFILE_PDF_PAGES) };
  else {
    if (!d.bytes) return { asked: false, ok: false };
    if (/^image\//i.test(mime)) {
      if (d.bytes.length > PROFILE_IMAGE_MAX) { d.unread_reason = 'The picture is larger than 10 MB. Upload a smaller photo or a PDF.'; return { asked: false, ok: false, why: 'image_too_large' }; }
      body = { images: [{ b64: toB64(d.bytes), mime }] };
    } else if (/pdf/i.test(mime)) {
      if (d.bytes.length > PROFILE_PDF_MODEL_MAX) { d.unread_reason = 'The scanned PDF is larger than 12 MB. Upload a smaller file.'; return { asked: false, ok: false, why: 'pdf_too_large' }; }
      // ONE read of the profile: kept on the item, so the trade read does not parse it again.
      d.read = await readDocument(d.bytes, d.name, mime, 0, { textOnly: true, maxBytes: LIMITS.maxPaperBytes });
      if (!(d.read.ok && d.read.needs === 'ocr')) return { asked: false, ok: false };
      let send = d.bytes;
      const pages = await pdfPageCount(d.bytes);
      if (pages === null || pages > PROFILE_PDF_PAGES) {
        const cut = await firstPdfPages(d.bytes, PROFILE_PDF_PAGES);
        if (!cut) { d.unread_reason = `The scanned PDF has more than ${PROFILE_PDF_PAGES} pages and could not be cut. Upload the first pages as a smaller PDF.`; return { asked: false, ok: false, why: 'pdf_not_cut' }; }
        send = cut;
        if (pages !== null) d.pages_read = { read: PROFILE_PDF_PAGES, of: pages };
      }
      body = { file_b64: toB64(send), mime, filename: d.name };
    } else return { asked: false, ok: false };
  }
  if (o.subject != null) body = { ...body, subject: o.subject };
  let last: Awaited<ReturnType<ProfileAsk>> = null, thrown = '';
  for (let i = 0; i < attempts; i++) {
    try { last = await ask(body); } catch (e) { last = null; thrown = String((e as Error)?.message || e).slice(0, 160); }
    if (last?.ok && last.profile) {
      if (own) { const t = modelReadText('profile', last.profile.lines); if (t) d.photo_text = t; }
      return { asked: true, ok: true, profile: last.profile };
    }
    const st = Number(last?.status ?? 0);
    if (st >= 400 && st < 500 && st !== 408 && st !== 429) break;   // the file itself was refused: asking again changes nothing
  }
  // NEVER SILENT (review of #1796): the document stays unread, and the failure is logged and filed as an IT finding.
  const why = last?.error || thrown || `HTTP ${last?.status ?? '?'}`;
  console.error(JSON.stringify({ at: 'supplier_docs_later.profile_model', path: d.path, mime, status: last?.status ?? null, error: String(why).slice(0, 200) }));
  const subject = (o.subject as { supplier_id?: number } | null | undefined)?.supplier_id;
  if (o.admin) {
    try {
      await o.admin.rpc('fn_it_engineer_finding_upsert', { p_issue_key: 'profile_model_read_failed:' + (subject ?? 'unknown'),
        p_title: 'A scanned or photographed company profile could not be read by the model, so the supplier gets no proposed services',
        p_where: 'edge function supplier_portal / supplier_api (license_extract profile mode)', p_blast: 'customer_facing', p_affected: 1,
        p_evidence: { supplier_id: subject ?? null, path: d.path, mime, status: last?.status ?? null, error: String(why).slice(0, 200) }, p_ruled_out: [], p_undetermined: [], p_raised_by: 'sales_engineer' });
    } catch (_e) { /* the document stays unread either way */ }
  }
  return { asked: true, ok: false, why: String(why).slice(0, 200) };
}

/** Keeps `job` alive after the response. Off the edge runtime (tests, local) the caller awaits what is returned. */
export function afterResponse(job: Promise<unknown>, at: string): Promise<void> | null {
  const w = job.then(() => {}, (e) => console.error(JSON.stringify({ at, error: String((e as Error)?.message || e).slice(0, 200) })));
  // deno-lint-ignore no-explicit-any
  const rt = (globalThis as any).EdgeRuntime;
  if (typeof rt?.waitUntil === 'function') { rt.waitUntil(w); return null; }
  return w;
}

/** A path is the supplier's own when it sits in its own folder of that kind and names no parent. */
export const ownPath = (path: unknown, kind: keyof typeof FOLDER, supplierId: number | string) =>
  String(path).startsWith(`${FOLDER[kind]}/${supplierId}/`) && !String(path).includes('..');

export async function signedUpload(admin: Admin, supplierId: number, kind: string, filename: unknown, mime: unknown):
  Promise<{ ok: true; path: string; token: string; max_bytes: number } | { ok: false; status: number; error: string; message: string }> {
  if (kind !== 'profile' && kind !== 'catalogue') return { ok: false, status: 400, error: 'bad_kind', message: 'Only a company profile or a catalogue can be uploaded this way.' };
  const m = String(mime || '');
  if (!(SAFE_SUPPLIER_PAPERS as readonly string[]).includes(m)) {
    return { ok: false, status: 415, error: 'file_type_not_allowed', message: 'Please upload a PDF, a Word or PowerPoint file, or an image (JPEG or PNG).' };
  }
  const path = `${FOLDER[kind]}/${supplierId}/${Date.now()}_${safeFilename(filename || kind, m)}`;
  const { data, error } = await admin.storage.from(BUCKET).createSignedUploadUrl(path);
  if (error || !data?.token) return { ok: false, status: 502, error: 'upload_url_failed', message: 'We could not prepare the upload. Please try again.' };
  return { ok: true, path, token: data.token, max_bytes: LIMITS.maxPaperBytes };
}

/** The stored object, streamed into ONE buffer of its own size (a Blob plus its arrayBuffer would hold it twice). */
export async function fetchStored(admin: Admin, path: string): Promise<{ bytes: Uint8Array } | { error: 'not_found' | 'file_too_large' }> {
  const { data } = await admin.storage.from(BUCKET).createSignedUrl(path, 600);
  if (!data?.signedUrl) return { error: 'not_found' };
  const res = await timedFetch(data.signedUrl, {}, 120_000);   // a stored file of up to 100 MB; a stall still ends
  if (!res.ok || !res.body) { await res.body?.cancel(); return { error: 'not_found' }; }
  const n = Number(res.headers.get('content-length') || 0);
  if (n > LIMITS.maxPaperBytes) { await res.body.cancel(); return { error: 'file_too_large' }; }
  if (!n) return { bytes: new Uint8Array(await res.arrayBuffer()) };
  const out = new Uint8Array(n); let o = 0;
  for await (const c of res.body) { if (o + c.length > n) return { error: 'file_too_large' }; out.set(c, o); o += c.length; }
  return { bytes: o === n ? out : out.subarray(0, o) };
}

/** A refused file leaves storage and the supplier's row: it is never offered to a customer or read. */
async function drop(admin: Admin, supplierId: number, path: string): Promise<void> {
  await admin.storage.from(BUCKET).remove([path]);
  const { data: l } = await admin.from('leads').select('company_profile_doc_path,catalog_doc_paths').eq('id', supplierId).maybeSingle();
  const upd: Record<string, unknown> = {};
  if (l?.company_profile_doc_path === path) upd.company_profile_doc_path = null;
  if (Array.isArray(l?.catalog_doc_paths) && l.catalog_doc_paths.includes(path)) upd.catalog_doc_paths = l.catalog_doc_paths.filter((p: string) => p !== path);
  if (Object.keys(upd).length) await admin.from('leads').update(upd).eq('id', supplierId);
}

export type GateDeps = { fetch: typeof fetchStored; scan: typeof sanitizeAndScan };
/** The same type / malware gate an upload in the request body gets, on the stored bytes. Never throws. */
export async function gateStored(admin: Admin, supplierId: number, d: LaterDoc, deps: GateDeps = { fetch: fetchStored, scan: sanitizeAndScan }): Promise<LaterDoc> {
  if (!d.gate) return d;
  try {
    const got = await deps.fetch(admin, d.path);
    if ('error' in got && got.error === 'not_found') return { ...d, gate: false };   // read as "could not be fetched"
    const sc = 'error' in got
      ? { ok: false as const, body: { error: 'file_too_large', detail: `over ${LIMITS.maxPaperBytes} bytes` } }
      : await deps.scan({ input: got.bytes, declaredMime: d.mime || '', filename: d.name, allow: SAFE_SUPPLIER_PAPERS, maxBytes: LIMITS.maxPaperBytes,
                          scan: { source: `supplier_docs_later.${d.kind}`, subject: String(supplierId), filename: d.name, bucket: BUCKET, path: d.path } });
    if (!sc.ok) {
      await drop(admin, supplierId, d.path);
      return { ...d, gate: false, bytes: undefined, refused: `${sc.body.error}${sc.body.detail ? ': ' + sc.body.detail : ''}` };
    }
    return { ...d, gate: false, bytes: sc.result.bytes, mime: sc.result.mime };
  } catch (e) {
    // The gate could not run: the file is held unread (refused), never read ungated.
    return { ...d, gate: false, bytes: undefined, refused: `the file could not be checked: ${String((e as Error)?.message || e).slice(0, 120)}` };
  }
}

export type LaterHooks = {
  /** Runs on a gated profile before its trades are read (the vision model for a picture or a scan). */
  profile?: (d: LaterDoc) => Promise<void>;
  /** Runs on a gated catalogue: a scanned or photographed catalogue goes to the same model (readProfileByModel), never left needs_ocr
   *  for good (3 Nov 2026: a 90-page scanned building-materials catalogue proposed nothing on 5 of 5 runs of the qualification). */
  catalogue?: (d: LaterDoc) => Promise<void>;
  retry?: boolean;
  deps?: TradeResolveDeps; gateDeps?: GateDeps;
};

export async function readStoredDocsLater(admin: Admin, supplierId: number, docs: LaterDoc[], hooks: LaterHooks = {}):
  Promise<{ docs: DocEvidence[]; proposed_trades: string[]; errors: string[] }> {
  const out: DocEvidence[] = [], errors: string[] = [];
  let proposed: string[] = [];
  const deps = hooks.deps ?? await liveTradeDeps(admin);
  // Each document is read into text on its own (one large file in memory at a time), then ALL the supplier's documents are
  // read together by the model once (supplier_doc_trades.proposeFromRead, ruling 1627): not once per document.
  const known = await knownNames(admin, supplierId);
  const fresh: DocEvidence[] = [];
  for (const d0 of docs) {
    const d = await gateStored(admin, supplierId, d0, hooks.gateDeps);
    const hook = d.kind === 'profile' ? hooks.profile : d.kind === 'catalogue' ? hooks.catalogue : undefined;
    if (!d.refused && hook && !d.from_page) {   // a continuation reads text pages on, never the model
      try { await hook(d); } catch (e) { errors.push(`${d.kind}: ${String((e as Error)?.message || e).slice(0, 160)}`); }
    }
    try {
      const markErr = await markReading(admin, supplierId, d.refused ? [] : [d], hooks.retry);
      if (markErr) errors.push(markErr);
      fresh.push(...await readTexts(admin, [d], known));
    } catch (e) { errors.push(`read: ${String((e as Error)?.message || e).slice(0, 160)}`); }
    d.bytes = undefined; d.read = undefined;   // one large file in memory at a time
  }
  if (fresh.length) {
    const r = await proposeFromRead(admin, supplierId, fresh, deps, known);
    if (r.ok) { out.push(...r.docs); proposed = r.proposed_trades; } else errors.push(r.error);
  }
  // A supplier held while its documents were being read is gated again now that they have been.
  try {
    const { data: l } = await admin.from('leads').select('licence_gate_reason').eq('id', supplierId).maybeSingle();
    if (l?.licence_gate_reason === 'documents_being_read') await admin.rpc('fn_sales_engineer_verifies_supplier', { p_lead_id: supplierId, p_source: 'documents_read' });
  } catch (e) { errors.push(`gate: ${String((e as Error)?.message || e).slice(0, 160)}`); }
  if (errors.length) console.error(JSON.stringify({ at: 'supplier_docs_later.read', supplier: supplierId, errors }));
  return { docs: out, proposed_trades: proposed, errors };
}

/** Documents 'reading' for REREAD_AFTER_MIN minutes or more that have not been re-read yet, grouped by supplier. */
// CHUNKED READING ACROSS RUNS (3 Nov 2026, sales_engineer; scripts/e2e/document_reading_qualification.ts). A long text PDF stops at the
// reader's CPU budget or text cap (doc_read/pdf.ts): measured locally on a 300-page profile, 156 to 300 pages in one run depending on the
// machine's load. Such a document is recorded read up to pages.read, marked `resume`, and the next sweep run reads it on from
// pages.read + 1, adding what those pages state to what the earlier pages proposed, until the last page is read. The gate already ran on
// the stored bytes, so a continuation is not gated again.
// READ AGAIN WHEN THE MODEL COULD NOT BE ASKED (11 Nov 2026, customer_support; founder ruling 1627). With no model, nothing is
// guessed from words: the documents are recorded read with choice 'unavailable' ("still being read"), the trade the supplier
// chose at sign-up stays on his checklist, and the sweep asks the model again from the text kept beside each file (no second
// parse), backing off REREAD_AFTER_MIN x 2^rereads minutes, at most REREAD_MAX times, as a licence our reader failed on is.
export const REREAD_MAX = 8;
export const rereadDue = (d: DocEvidence, now = Date.now()) => d.status === 'read' && d.choice === 'unavailable' && (d.rereads ?? 0) < REREAD_MAX
  && now - Date.parse(d.read_at) >= REREAD_AFTER_MIN * 2 ** (d.rereads ?? 0) * 60_000;
export type Stuck = { supplier_id: number; docs: LaterDoc[]; again: DocEvidence[] };
export function stuckOf(rows: { supplier_id: number; source_docs: unknown }[], now = Date.now()): Stuck[] {
  const out: Stuck[] = [];
  for (const r of rows) {
    const all = (r.source_docs as { docs?: DocEvidence[] })?.docs || [];
    const docs: LaterDoc[] = [...all
      .filter((d) => d.status === 'reading' && !d.retry && now - Date.parse(d.read_at) >= REREAD_AFTER_MIN * 60_000)
      .map((d) => ({ path: d.path, name: d.name, kind: d.kind, gate: d.kind !== 'licence' })),
      ...all.filter((d) => d.status === 'read' && d.resume && d.pages && pagesLeft(d.pages))
      .map((d) => ({ path: d.path, name: d.name, kind: d.kind, gate: false, from_page: d.pages!.read + 1, prev: d }))];
    const again = all.filter((d) => rereadDue(d, now) && !docs.some((x) => x.path === d.path));
    if (docs.length || again.length) out.push({ supplier_id: Number(r.supplier_id), docs, again });
  }
  return out;
}

export async function stuckReads(admin: Admin, limit = 2): Promise<Stuck[]> {
  const probes = [{ status: 'reading' }, { resume: true }, { choice: 'unavailable' }];
  const got = await Promise.all(probes.map((p) => admin.from('supplier_capabilities').select('supplier_id,source_docs')
    .contains('source_docs', { docs: [p] }).limit(50)));
  const seen = new Set<number>();
  const rows = got.flatMap((g: { data?: { supplier_id: number; source_docs: unknown }[] }) => g.data || []).filter((r) => !seen.has(r.supplier_id) && seen.add(r.supplier_id));
  return stuckOf(rows).slice(0, limit);
}

/** The documents the model could not be read for, read together again from their kept text (supplier_doc_trades.proposeFromRead). */
export async function rereadTogether(admin: Admin, supplierId: number, again: DocEvidence[], deps?: TradeResolveDeps):
  Promise<{ ok: boolean; proposed_trades?: string[]; error?: string }> {
  const at = new Date().toISOString();
  const fresh: DocEvidence[] = [];
  for (const d of again) {
    const text = await loadText(admin, d);
    fresh.push({ ...d, read_at: at, rereads: (d.rereads ?? 0) + 1, ...(text != null ? { text } : {}) });
  }
  const r = await proposeFromRead(admin, supplierId, fresh, deps ?? await liveTradeDeps(admin), await knownNames(admin, supplierId));
  if (!r.ok) console.error(JSON.stringify({ at: 'supplier_docs_later.rereadTogether', supplier: supplierId, error: r.error }));
  return r.ok ? { ok: true, proposed_trades: r.proposed_trades } : { ok: false, error: r.error };
}
