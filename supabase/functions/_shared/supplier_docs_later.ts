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
//     (resilience_ping -> supplier_api docs_reread), marked retry; a second stall is left to
//     fn_supplier_doc_reading_escalate (30 minutes), which hands it to the sales engineer.
// It does NOT change how a document is read (supplier_doc_trades.ts) or the licence path, which stays in the request.
import { sanitizeAndScan } from './malware.ts';
import { SAFE_SUPPLIER_PAPERS, safeFilename } from './attachment.ts';
import { LIMITS } from './doc_read/types.ts';
import { liveTradeDeps } from './trade_resolve.ts';
import { PHOTO_TEXT_MAX, proposeTradesFromDocs, type DocEvidence, type DocIn, type TradeResolveDeps } from './supplier_doc_trades.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;
export const BUCKET = 'supplier-docs';
export const FOLDER = { profile: 'profiles', catalogue: 'catalogs' } as const;
export const REREAD_AFTER_MIN = 10;
/** gate: the file arrived by path and has not been through sanitizeAndScan yet.
 *  ocr_text: a scan's words read by CODE in the supplier's browser (tesseract.js, #1483); read by supplier_doc_trades. */
export type LaterDoc = DocIn & { gate?: boolean; ocr_text?: string };
/** The browser's OCR text as sent, capped like photo_text; '' or absent is none. */
export const ocrOf = (t: unknown): string | undefined => (t ? String(t).slice(0, PHOTO_TEXT_MAX) : '') || undefined;

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
  const res = await fetch(data.signedUrl);
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
  retry?: boolean;
  deps?: TradeResolveDeps; gateDeps?: GateDeps;
};

export async function readStoredDocsLater(admin: Admin, supplierId: number, docs: LaterDoc[], hooks: LaterHooks = {}):
  Promise<{ docs: DocEvidence[]; proposed_trades: string[]; errors: string[] }> {
  const out: DocEvidence[] = [], errors: string[] = [];
  let proposed: string[] = [];
  const deps = hooks.deps ?? await liveTradeDeps(admin);   // read once: the vectors and meaning's budget are shared
  for (const d0 of docs) {
    const d = await gateStored(admin, supplierId, d0, hooks.gateDeps);
    if (!d.refused && d.kind === 'profile' && hooks.profile) {
      try { await hooks.profile(d); } catch (e) { errors.push(`profile: ${String((e as Error)?.message || e).slice(0, 160)}`); }
    }
    const r = await proposeTradesFromDocs(admin, supplierId, [d], deps, hooks.retry);
    if (r.ok) { out.push(...r.docs); proposed = r.proposed_trades; } else errors.push(r.error);
    d.bytes = undefined; d.read = undefined;   // one large file in memory at a time
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
export function stuckOf(rows: { supplier_id: number; source_docs: unknown }[], now = Date.now()): { supplier_id: number; docs: LaterDoc[] }[] {
  const out: { supplier_id: number; docs: LaterDoc[] }[] = [];
  for (const r of rows) {
    const docs = ((r.source_docs as { docs?: DocEvidence[] })?.docs || [])
      .filter((d) => d.status === 'reading' && !d.retry && now - Date.parse(d.read_at) >= REREAD_AFTER_MIN * 60_000)
      .map((d) => ({ path: d.path, name: d.name, kind: d.kind, gate: d.kind !== 'licence' }));
    if (docs.length) out.push({ supplier_id: Number(r.supplier_id), docs });
  }
  return out;
}

export async function stuckReads(admin: Admin, limit = 2): Promise<{ supplier_id: number; docs: LaterDoc[] }[]> {
  const { data } = await admin.from('supplier_capabilities').select('supplier_id,source_docs')
    .contains('source_docs', { docs: [{ status: 'reading' }] }).limit(50);
  return stuckOf(data || []).slice(0, limit);
}
