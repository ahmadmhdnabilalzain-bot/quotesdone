// One doc_backups row to Dropbox, verified (sales_engineer files it; moved out of index.ts on 7 Oct 2026
// so the scheduled queue, the tagged sandbox run and its rehearsal script walk exactly the same code).
//   * a 'generated' row is rendered by pdf_native into backups/generated/ first (a 'case_summary' row is a Markdown file
//     written by code, _shared/case_dropbox.ts, 11 Nov 2026: text needs no renderer);
//   * the source is read from storage with HTTP Range requests (uploadFile streams it in chunks);
//   * the upload is CONFIRMED with files/get_metadata: size AND content_hash, or the row is not done.
import type { DropboxClient } from './dropbox.ts';
import { CHUNK, uploadFile, type ReadChunk } from './upload.ts';
import { isTransientDbError } from './health.ts';
import { caseSummaryFile } from '../_shared/case_dropbox.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;
// deno-lint-ignore no-explicit-any
export type Row = Record<string, any> & { id: number; attempts: number };
export type RowOutcome = { done: number; chunks: number; retries: number } | { resuming: number } | { uploaded_not_marked: number };

const esc = (s: unknown) => String(s ?? '—').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' } as Record<string, string>)[c]);
const fmtD = (s: unknown) => { if (!s) return '—'; try { return new Date(String(s)).toISOString().slice(0, 10); } catch { return String(s); } };
function kvTable(rows: [string, unknown][]) { return '<table style="border-collapse:collapse;width:100%">' + rows.map(([k, v]) => `<tr><td style="padding:4px 10px 4px 0;color:#555;white-space:nowrap;vertical-align:top">${esc(k)}</td><td style="padding:4px 0"><b>${esc(v)}</b></td></tr>`).join('') + '</table>'; }
async function sec(admin: Admin, k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }

// files/get_metadata. A 409 path/not_found is an ANSWER ("missing"); any other non-200 throws so a
// Dropbox outage is never read as a missing file.
export async function dbxMeta(dbx: DropboxClient, path: string): Promise<{ missing: true } | { missing: false; size: number; content_hash: string }> {
  const r = await dbx.call('api', 'files/get_metadata', { path });
  const t = await r.text();
  if (r.status === 409 && t.includes('not_found')) return { missing: true };
  if (!r.ok) throw new Error('get_metadata ' + r.status + ' ' + t.slice(0, 160));
  const j = JSON.parse(t);
  if (j['.tag'] !== 'file') return { missing: true };
  return { missing: false, size: Number(j.size), content_hash: String(j.content_hash || '') };
}
export async function verifyUploaded(dbx: DropboxClient, dest: string, hash: string, size: number) {
  const m = await dbxMeta(dbx, dest);
  if (m.missing) throw new Error('verify: missing in Dropbox after upload');
  if (m.size !== size) throw new Error(`verify: size ${m.size} in Dropbox != ${size} sent`);
  if (m.content_hash !== hash) throw new Error('verify: content_hash mismatch ' + m.content_hash.slice(0, 12) + ' != ' + hash.slice(0, 12));
}

// A storage object read by HTTP Range: the first request also answers the size (Content-Range).
export async function storageSource(admin: Admin, bucket: string, path: string): Promise<{ size: number; read: ReadChunk }> {
  const { data: su, error } = await admin.storage.from(bucket).createSignedUrl(path, 3600);
  if (error || !su?.signedUrl) throw new Error('download ' + (error?.message || 'object not found'));
  const url = su.signedUrl;
  const get = async (o: number, n: number) => {
    const g = await fetch(url, { headers: { Range: `bytes=${o}-${o + n - 1}` } });
    if (g.status === 416) { await g.body?.cancel(); return { bytes: new Uint8Array(0), total: 0 }; }
    if (!(g.status === 206 || g.status === 200)) throw new Error('download range ' + g.status + ' ' + (await g.text()).slice(0, 120));
    const total = g.status === 200 ? Number(g.headers.get('content-length')) : Number((g.headers.get('content-range') || '').split('/')[1]);
    let bytes = new Uint8Array(await g.arrayBuffer());
    if (g.status === 200) bytes = bytes.slice(o, o + n);    // server ignored Range
    return { bytes, total };
  };
  const first = await get(0, CHUNK);
  if (!Number.isFinite(first.total)) throw new Error('download: size unknown');
  return { size: first.total, read: async (o, n) => (o === 0 && n <= first.bytes.length) ? first.bytes.slice(0, n) : (await get(o, n)).bytes };
}

export async function renderGenerated(admin: Admin, supabaseUrl: string, row: Row): Promise<{ bucket: string; path: string }> {
  // a case summary is the case as it is now, as text: no PDF (ruling 1635; one file per case, overwritten each version)
  if (row.gen_kind === 'case_summary') return await caseSummaryFile(admin, String(row.gen_ref));
  let title = 'Document'; let inner = '';
  if (row.gen_kind === 'supplier_details') {
    const { data: l } = await admin.from('leads').select('*').eq('id', Number(row.gen_ref)).maybeSingle();
    if (!l) throw new Error('supplier_missing');
    title = 'Company Details — ' + (l.company_name || ('Supplier ' + row.gen_ref));
    inner = `<h2>${esc(l.company_name)}</h2>` + kvTable([
      ['Supplier ID', l.id], ['Category', l.categories || l.sector], ['Sub-type', l.sub_type], ['Emirate', l.emirate], ['City', l.city], ['Contact', l.contact_name],
      ['Phone', l.phone_e164 || l.phone], ['Email', l.email], ['Website', l.website],
      ['Trade licence no', l.trade_license_no], ['Licence authority', l.license_authority], ['Licence expiry', fmtD(l.license_expiry)], ['TRN', l.trn], ['VAT number', l.vat_number],
      ['Registration status', l.registration_status], ['Approval status', l.approval_status], ['Approved at', fmtD(l.approved_at)], ['Services', Array.isArray(l.services) ? l.services.join(', ') : l.services],
    ]) + (l.capability_summary ? `<h3>Capability summary</h3><p>${esc(l.capability_summary)}</p>` : '');
  } else if (row.gen_kind === 'customer_details') {
    const { data: c } = await admin.from('customers').select('*').eq('id', row.gen_ref).maybeSingle();
    if (!c) throw new Error('customer_missing');
    title = 'Customer Details — ' + (c.full_name || 'Customer');
    inner = kvTable([
      ['Customer ID', c.id], ['Full name', c.full_name], ['Phone', c.phone], ['Phone verified', c.phone_verified ? 'Yes' : 'No'],
      ['Email', c.email], ['Email verified', c.email_verified ? 'Yes' : 'No'], ['Registered', fmtD(c.created_at)],
      ['Terms version', c.tos_version], ['Terms accepted', fmtD(c.tos_accepted_at || c.signed_terms_at)], ['WhatsApp', c.whatsapp_opt === 'other' ? (c.whatsapp_verified_at ? 'Confirmed number ' + (c.whatsapp_phone || '') : 'Different number, not confirmed (not used)') : c.whatsapp_opt === 'same' ? 'Same as mobile' : c.whatsapp_opt === 'none' ? 'Does not use WhatsApp' : 'Not answered'],
    ]);
  } else if (row.gen_kind === 'inquiry_summary') {
    const { data: i } = await admin.from('inquiries').select('*').eq('id', row.gen_ref).maybeSingle();
    if (!i) throw new Error('inquiry_missing');
    const { data: c } = await admin.from('customers').select('full_name').eq('id', i.customer_id).maybeSingle();
    title = 'Inquiry Summary — ' + String(row.gen_ref).slice(0, 8);
    inner = kvTable([['Inquiry ID', i.id], ['Customer', c?.full_name], ['Status', i.status], ['Created', fmtD(i.created_at)], ['Drawing on file', i.drawing_file_name || (i.drawing_file_path ? 'yes' : '—')]]) + (i.summary ? `<h3>Request</h3><p>${esc(i.summary)}</p>` : '');
  } else throw new Error('unknown_gen_kind');
  const body_html = inner + `<p style="margin-top:24px;color:#888;font-size:11px">Auto-generated backup document — QuotesDone · ${new Date().toISOString().slice(0, 10)}</p>`;
  const r = await fetch(supabaseUrl + '/functions/v1/pdf_native', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec(admin, 'cred_fn_to_pdf_native'), title, body_html, name: (row.gen_kind + '_' + row.gen_ref).replace(/[^a-z0-9_]+/gi, '_').slice(0, 60), bucket: 'backups', folder: 'generated', options: { letterhead: true } }) });
  const jd = await r.json().catch(() => ({} as Record<string, unknown>));
  if (!jd?.path) throw new Error('pdf_native ' + (jd?.error || r.status));
  return { bucket: 'backups', path: String(jd.path) };
}

// The whole of one row. Throws when the row did not succeed (drainClaim marks it failed); returns
// 'resuming' when a large file stopped at the deadline (state saved), and 'uploaded_not_marked' when
// only the bookkeeping failed. `simulateFailure` (the sandbox's retry test only) throws a provider error
// before anything is sent.
export async function backupRow(admin: Admin, dbx: DropboxClient, row: Row, o: { supabaseUrl: string; deadline: number; release: Record<string, null>;
  simulateFailure?: boolean; logRun?: (status: string, counts: Record<string, unknown>, note: string) => Promise<void> }): Promise<RowOutcome> {
  const now = () => new Date().toISOString();
  if (o.simulateFailure) throw new Error('simulated: Dropbox 503 service unavailable (tagged sandbox retry test)');
  let bucket = row.bucket, path = row.path;
  if (row.source === 'generated' && !path) { const g = await renderGenerated(admin, o.supabaseUrl, row); bucket = g.bucket; path = g.path; await admin.from('doc_backups').update({ bucket, path }).eq('id', row.id).eq('status', 'processing'); }
  if (!bucket || !path) throw new Error('no_source');
  const src = await storageSource(admin, bucket, path);
  const up = await uploadFile(dbx, row.dropbox_path, src.size, src.read, { state: row.upload_state, deadline: o.deadline });
  if (!up.done) {
    await admin.from('doc_backups').update({ status: 'pending', ...o.release, upload_state: up.state, bytes: src.size, last_attempt_at: now(),
      error: `resuming: ${up.state.offset} of ${src.size} bytes sent` }).eq('id', row.id).eq('status', 'processing');
    return { resuming: up.state.offset };
  }
  await verifyUploaded(dbx, row.dropbox_path, up.hash, src.size);
  const mark = { status: 'done', ...o.release, bytes: src.size, backed_up_at: now(), error: null, attempts: row.attempts + 1,
    last_attempt_at: now(), upload_state: null, dropbox_content_hash: up.hash, dropbox_size: src.size, verified_at: now() };
  let markErr = (await admin.from('doc_backups').update(mark).eq('id', row.id).eq('status', 'processing')).error;
  // a lock wait that timed out (measured 15 Sep 06:40Z, during a migration apply) clears in seconds
  for (let i = 1; markErr && i <= 2 && isTransientDbError(markErr.message) && Date.now() < o.deadline; i++) {
    await new Promise((r) => setTimeout(r, 2000 * i));
    markErr = (await admin.from('doc_backups').update(mark).eq('id', row.id).eq('status', 'processing')).error;
  }
  // Only the bookkeeping failed: the copy is uploaded and verified in Dropbox. The row stays
  // 'processing', the claim expires after 10 minutes and it is uploaded again (overwrite, same bytes).
  // 'warn', not 'error', for a transient wait: fn_backup_watch reads a latest 'error' run as a failed
  // backup. Any other mark-done failure repeats on every file and stays 'error'.
  if (markErr) {
    await o.logRun?.(isTransientDbError(markErr.message) ? 'warn' : 'error', { stage: 'mark_done', doc_backup_id: row.id }, 'Document ' + row.id + ' was uploaded and verified in Dropbox but could not be marked done; it is re-uploaded (overwrite) when its claim expires in 10 minutes: ' + markErr.message.slice(0, 160));
    return { uploaded_not_marked: src.size };
  }
  return { done: src.size, chunks: up.chunks, retries: up.retries };
}
