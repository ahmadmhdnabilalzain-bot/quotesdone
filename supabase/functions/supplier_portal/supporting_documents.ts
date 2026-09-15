// SUPPORTING COMPANY DOCUMENTS (15 Sep 2026, sales_engineer).
//
// The founder's spec for the Documents tab: besides the required trade licence and company profile, a
// supplier may upload ANY supporting company document — free upload, several types, a name, a list,
// download, replace and delete their own. The fixed document kinds (licence, profile, insurance, ISO,
// ...) stay exactly where they were: supplier_portal `documents` / `save_documents` and the leads columns
// fn_supplier_mandatory_six and fn_enqueue_doc_backups read. Nothing here writes a leads column, so the
// mandatory six cannot be satisfied or bypassed through this door.
//
// WHERE A FILE GOES, and why no schema change was needed:
//   - the bytes: storage bucket `supplier-docs`, path supporting/<supplier id>/<epoch>_<clean name>. The
//     bucket's own limits apply (25 MB, its MIME list) on top of sanitizeAndScan (type decided from the
//     bytes, malware scan) — the same upload path save_documents uses.
//   - the record: one row in public.documents, ref_table 'supplier_supporting', ref_id the supplier id,
//     kind 'supporting:<type>', file_name the label the supplier chose, status 'received'.
//       * NOT ref_table 'leads': fn_customer_document_refs shows every 'leads' document to a customer who
//         revealed that supplier, and a supplier's supporting file is theirs until they choose otherwise.
//       * NOT status 'pending': doc_extract claims pending rows for OCR and extraction, and nobody asked
//         for these to be read. documents.extracted is doc_extract's alone, so the label is not put there.
//   - Dropbox: measured 15 Sep 2026, fn_backup_source_registry lists supplier-docs as swept by the
//     STORAGE SWEEP of fn_enqueue_doc_backups, and fn_backup_sweep_objects owns a supplier-docs path whose
//     second segment is digits as supplier:<id>. supporting/<id>/... therefore reaches Dropbox under its
//     supplier with no new rule (demo suppliers excluded by the sweep, as for every other file).
// REMOVE hides a document from the supplier (status 'withdrawn'); the stored file and its backup are kept,
// the same as a replaced file: a document a supplier once showed us is part of the record.
//
// No Supabase client is created here; the caller passes admin and the upload dependencies, which is what
// lets supporting_documents.test.ts drive every path against a fake.

// deno-lint-ignore no-explicit-any
type Admin = any;
// deno-lint-ignore no-explicit-any
type Row = Record<string, any>;

export const SUPPORTING_TYPES = ['certificate', 'accreditation', 'reference_letter', 'project_reference', 'financial_statement', 'organisation_chart', 'hse_policy', 'quality_policy', 'brochure', 'other'] as const;
export type SupportingType = typeof SUPPORTING_TYPES[number];
export const REF_TABLE = 'supplier_supporting';
export const BUCKET = 'supplier-docs';
export const MAX_DOCUMENTS = 30;
export const MAX_LABEL = 120;
// 25 MB is the bucket's own file_size_limit (storage.buckets, measured 15 Sep 2026); base64 is 4/3 of it.
export const MAX_BYTES = 26214400;

export type SupportingDocument = { id: number; label: string; type: SupportingType; file_name: string; mime: string | null; uploaded_at: string; url: string | null };
export type SaveRequest = { id?: number | null; label?: string; type?: string; filename?: string; mime?: string; original_b64?: string };
export type Deps = {
  /** sanitizeAndScan from _shared/malware.ts, bound to this supplier. */
  scan: (input: { b64: string; mime?: string; filename: string }) => Promise<{ ok: true; bytes: Uint8Array; mime: string } | { ok: false; reason: string }>;
  safeFilename: (name: string, mime: string) => string;
  upload: (path: string, bytes: Uint8Array, mime: string) => Promise<{ error: string | null }>;
  sign: (path: string) => Promise<string | null>;
  now?: () => number;
};
type Res = { status: number; body: Row };
const R = (status: number, body: Row): Res => ({ status, body });

// Control characters out, whitespace collapsed, clipped. The label is shown back to its owner only.
export const cleanLabel = (v: unknown) => String(v ?? '').replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, MAX_LABEL);
export const typeOf = (kind: unknown): SupportingType => {
  const t = String(kind || '').replace(/^supporting:/, '');
  return (SUPPORTING_TYPES as readonly string[]).includes(t) ? t as SupportingType : 'other';
};
export const pathFor = (supId: number, clean: string, at: number) => `supporting/${supId}/${at}_${clean}`;
const tail = (p: string) => String(p || '').split('/').pop()?.replace(/^\d{10,}_/, '') || '';

const own = (admin: Admin, supId: number) => admin.from('documents').select('id,path,file_name,kind,mime,created_at,processed_at,status')
  .eq('ref_table', REF_TABLE).eq('ref_id', String(supId)).eq('bucket', BUCKET).neq('status', 'withdrawn');

const shape = async (r: Row, sign: Deps['sign']): Promise<SupportingDocument> => ({
  id: Number(r.id), label: String(r.file_name || tail(r.path)), type: typeOf(r.kind), file_name: tail(r.path),
  mime: r.mime || null, uploaded_at: String(r.processed_at || r.created_at), url: await sign(String(r.path)),
});

export async function listSupporting(admin: Admin, supId: number, sign: Deps['sign']): Promise<Res> {
  const { data, error } = await own(admin, supId).order('created_at', { ascending: false }).limit(MAX_DOCUMENTS);
  if (error) return R(500, { ok: false, error: 'load_failed' });
  const documents = await Promise.all(((data || []) as Row[]).map((r) => shape(r, sign)));
  return R(200, { ok: true, documents, types: SUPPORTING_TYPES, limits: { max_documents: MAX_DOCUMENTS, max_bytes: MAX_BYTES, max_label: MAX_LABEL } });
}

/** Upload a new document, or (with `id`) replace the file and/or rename one the supplier owns. */
export async function saveSupporting(admin: Admin, supId: number, b: SaveRequest, d: Deps): Promise<Res> {
  const id = b.id == null || b.id === ('' as unknown) ? null : Number(b.id);
  if (id != null && !(Number.isInteger(id) && id > 0)) return R(400, { ok: false, error: 'bad_id' });
  const label = cleanLabel(b.label);
  const type = b.type == null ? null : String(b.type);
  if (type != null && !(SUPPORTING_TYPES as readonly string[]).includes(type)) return R(400, { ok: false, error: 'bad_type' });
  const b64 = String(b.original_b64 || '');
  if (id == null && !b64) return R(400, { ok: false, error: 'file_required' });
  if (id == null && !label) return R(400, { ok: false, error: 'label_required' });
  if (b64 && Math.floor((b64.replace(/^data:[^;]+;base64,/, '').length * 3) / 4) > MAX_BYTES) return R(413, { ok: false, error: 'too_large', max_bytes: MAX_BYTES });

  let existing: Row | null = null;
  if (id != null) {
    const { data } = await own(admin, supId).eq('id', id).maybeSingle();
    if (!data) return R(404, { ok: false, error: 'not_found' });   // not theirs, or removed: the same answer
    existing = data as Row;
  } else {
    const { count } = await admin.from('documents').select('id', { count: 'exact', head: true })
      .eq('ref_table', REF_TABLE).eq('ref_id', String(supId)).eq('bucket', BUCKET).neq('status', 'withdrawn');
    if ((count || 0) >= MAX_DOCUMENTS) return R(409, { ok: false, error: 'limit_reached', max_documents: MAX_DOCUMENTS });
  }

  const upd: Row = {};
  if (b64) {
    const sc = await d.scan({ b64, mime: b.mime, filename: String(b.filename || label || 'document') });
    if (!sc.ok) return R(422, { ok: false, error: 'file_refused', reason: sc.reason });
    const clean = d.safeFilename(String(b.filename || label || 'document'), sc.mime);
    const path = pathFor(supId, clean, (d.now || Date.now)());
    const up = await d.upload(path, sc.bytes, sc.mime);
    if (up.error) return R(502, { ok: false, error: 'upload_failed' });
    upd.path = path; upd.mime = sc.mime; upd.processed_at = new Date((d.now || Date.now)()).toISOString();
  }
  if (label) upd.file_name = label;
  if (type) upd.kind = 'supporting:' + type;

  if (existing) {
    if (!Object.keys(upd).length) return R(400, { ok: false, error: 'nothing_to_change' });
    const { data, error } = await admin.from('documents').update(upd).eq('id', existing.id)
      .eq('ref_table', REF_TABLE).eq('ref_id', String(supId)).select('id,path,file_name,kind,mime,created_at,processed_at').maybeSingle();
    if (error || !data) return R(502, { ok: false, error: 'save_failed' });
    return R(200, { ok: true, replaced: !!b64, document: await shape(data as Row, d.sign) });
  }
  const { data, error } = await admin.from('documents').insert({ bucket: BUCKET, ref_table: REF_TABLE, ref_id: String(supId), status: 'received',
    kind: 'supporting:' + (type || 'other'), ...upd }).select('id,path,file_name,kind,mime,created_at,processed_at').maybeSingle();
  if (error || !data) return R(502, { ok: false, error: 'save_failed' });
  return R(200, { ok: true, document: await shape(data as Row, d.sign) });
}

export async function deleteSupporting(admin: Admin, supId: number, idIn: unknown): Promise<Res> {
  const id = Number(idIn);
  if (!(Number.isInteger(id) && id > 0)) return R(400, { ok: false, error: 'bad_id' });
  const { data, error } = await admin.from('documents').update({ status: 'withdrawn' }).eq('id', id)
    .eq('ref_table', REF_TABLE).eq('ref_id', String(supId)).eq('bucket', BUCKET).neq('status', 'withdrawn').select('id').maybeSingle();
  if (error) return R(502, { ok: false, error: 'delete_failed' });
  if (!data) return R(404, { ok: false, error: 'not_found' });
  return R(200, { ok: true, id });
}

/** A fresh signed URL (1 hour) for one of the supplier's own documents: the download a mobile app calls. */
export async function urlSupporting(admin: Admin, supId: number, idIn: unknown, sign: Deps['sign']): Promise<Res> {
  const id = Number(idIn);
  if (!(Number.isInteger(id) && id > 0)) return R(400, { ok: false, error: 'bad_id' });
  const { data } = await own(admin, supId).eq('id', id).maybeSingle();
  if (!data) return R(404, { ok: false, error: 'not_found' });
  const url = await sign(String((data as Row).path));
  return url ? R(200, { ok: true, id, url, expires_in: 3600, file_name: tail((data as Row).path) }) : R(502, { ok: false, error: 'url_failed' });
}
