// dropbox_backup v6 (14 Sep 2026, agent: ceo, owner: sales_engineer) — A BACKUP IS CONFIRMED, NOT ASSUMED.
// v5 marked a row 'done' the moment files/upload returned 200. v6 hashes the bytes it sent (Dropbox
// content_hash: SHA-256 per 4 MiB block, SHA-256 of the concatenation — see content_hash.ts), then
// asks Dropbox files/get_metadata for the same path and requires the size AND the hash to match.
// Only then is the row 'done', carrying dropbox_content_hash, dropbox_size and verified_at. A
// mismatch or a missing file is an ordinary failure: status 'error', attempts+1, retried.
// body.mode === 'reconcile' samples done rows (unverified first), re-reads each from Dropbox, and
// hands the outcomes to fn_dropbox_reconcile_apply, which requeues anything missing or changed and
// raises it to the sales engineer. Reconcile never logs as 'dropbox_backup', so it cannot claim the
// day's backup in fn_dropbox_backup_due. SQL: scripts/sql/the_dropbox_backup_is_confirmed_not_assumed.sql
//
// dropbox_backup v5 — organized Dropbox backup tree under '/QuotesDone Backup'. 'storage' rows are downloaded from
// Supabase Storage; 'generated' rows are rendered to branded PDF via pdf_native first (customer/supplier details,
// inquiry summary). Read-only on our storage; it only ever ADDS to Dropbox.
//
// RESTORED 9 Sep 2026 (agent: sales_engineer) after commit 182308b deleted it. Three changes from v4,
// each forced by something measured about the estate it is coming back into:
//
// 1. make_pdf -> pdf_native. make_pdf was deleted in the same sweep and is not coming back; pdf_native
//    is deployed (v29) and is what compliance_archive already renders its certificates with. Restoring
//    one PDF renderer instead of two is the whole reason a second one is not being restored.
//
// 2. THE QUOTE-COMPARISON DOCUMENT IS GONE. It called quote_compare, which needs a model, and all 8
//    llm_route_health routes are held with fn_kernel_paid_provider_gate denying globally. That path was
//    already the single largest source of failure in the live queue: 15 of the 26 error rows in
//    doc_backups are gen_kind='comparison', every one at attempts=5, sample error 'compare parse_failed'.
//    Restoring it would restore a guaranteed-failing writer. The enqueue no longer emits those rows
//    (see scripts/sql/...compliance_archive_and_the_dropbox_tree_back.sql) and this file no longer
//    renders them. Nothing else in the tree depends on a model.
//
// 3. op:pdpl_erase IS DISABLED. It deleted files from the founder's Dropbox (files/delete_v2) and from
//    storage. This restore is a backup that adds and never removes, so the branch now refuses and says
//    so rather than being silently absent. Re-enabling it is a deliberate decision for whoever owns
//    PDPL erasure, not a side effect of restoring a backup.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { observe } from '../_shared/observe.ts';
import { DropboxHasher, dropboxContentHash } from './content_hash.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'dropbox_backup', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
async function logThrottled(signal: string, minutes: number, status: string, counts: Record<string, unknown>, note: string) {
  try {
    const since = new Date(Date.now() - minutes * 60000).toISOString();
    const { data } = await admin.from('agent_runs').select('id').eq('agent', 'dropbox_backup')
      .gte('started_at', since).eq('counts->>signal', signal).limit(1);
    if (data && data.length) return;
  } catch (_e) { /* if the check fails, fall through and log */ }
  await logRun(status, { ...counts, signal }, note);
}
const BASE = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
const SINGLE_MAX = 140 * 1024 * 1024, HARD_MAX = 1073741824, CHUNK = 8 * 1024 * 1024;
const esc = (s: unknown) => String(s ?? '—').replace(/[&<>]/g, (c)=>({'&':'&amp;','<':'&lt;','>':'&gt;'} as any)[c]);
const fmtD = (s: unknown) => { if(!s) return '—'; try { return new Date(String(s)).toISOString().slice(0,10); } catch { return String(s); } };

async function accessToken(): Promise<string|null> {
  const rt = await sec('dropbox_refresh_token'); const ak = await sec('dropbox_app_key'); const as = await sec('dropbox_app_secret');
  if (!rt || !ak || !as) return null;
  const body = new URLSearchParams({ grant_type:'refresh_token', refresh_token:rt, client_id:ak, client_secret:as });
  const r = await fetch('https://api.dropboxapi.com/oauth2/token', { method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded'}, body });
  const j = await r.json(); return j?.access_token || null;
}
function arg(o: unknown){ return JSON.stringify(o).replace(/[-￿]/g, (c)=> '\\u'+c.charCodeAt(0).toString(16).padStart(4,'0')); }
async function uploadSingle(token: string, dest: string, bytes: ArrayBuffer){
  const r = await fetch('https://content.dropboxapi.com/2/files/upload', { method:'POST', headers:{ 'Authorization':'Bearer '+token, 'Content-Type':'application/octet-stream', 'Dropbox-API-Arg': arg({ path:dest, mode:'overwrite', autorename:false, mute:true, strict_conflict:false }) }, body: bytes });
  if (!r.ok) throw new Error('dbx_upload '+r.status+' '+(await r.text()).slice(0,200));
}
// Returns the content_hash of exactly the bytes appended, hashed as they stream.
async function uploadSession(token: string, dest: string, signedUrl: string, size: number): Promise<string>{
  const hasher = new DropboxHasher();
  let r = await fetch('https://content.dropboxapi.com/2/files/upload_session/start', { method:'POST', headers:{ 'Authorization':'Bearer '+token, 'Content-Type':'application/octet-stream', 'Dropbox-API-Arg': arg({ close:false }) }, body:new Uint8Array(0) });
  if (!r.ok) throw new Error('session_start '+r.status);
  const sid = (await r.json()).session_id as string; let off = 0;
  while (off < size){ const end = Math.min(off+CHUNK, size)-1; const g = await fetch(signedUrl, { headers:{ 'Range':`bytes=${off}-${end}` } }); if(!(g.status===206||g.status===200)) throw new Error('range_get '+g.status); const buf = await g.arrayBuffer(); if(buf.byteLength===0) throw new Error('empty_chunk'); await hasher.update(new Uint8Array(buf)); r = await fetch('https://content.dropboxapi.com/2/files/upload_session/append_v2', { method:'POST', headers:{ 'Authorization':'Bearer '+token, 'Content-Type':'application/octet-stream', 'Dropbox-API-Arg': arg({ cursor:{ session_id:sid, offset:off }, close:false }) }, body:buf }); if(!r.ok) throw new Error('append '+r.status); off += buf.byteLength; }
  r = await fetch('https://content.dropboxapi.com/2/files/upload_session/finish', { method:'POST', headers:{ 'Authorization':'Bearer '+token, 'Content-Type':'application/octet-stream', 'Dropbox-API-Arg': arg({ cursor:{ session_id:sid, offset:size }, commit:{ path:dest, mode:'overwrite', autorename:false, mute:true } }) }, body:new Uint8Array(0) });
  if (!r.ok) throw new Error('finish '+r.status);
  return hasher.hex();
}
// files/get_metadata. A 409 path/not_found is an ANSWER ("missing"), not a failure of the call;
// any other non-200 throws so a Dropbox outage is never read as a missing file.
async function dbxMeta(token: string, path: string): Promise<{ missing: true } | { missing: false, size: number, content_hash: string }>{
  const r = await fetch('https://api.dropboxapi.com/2/files/get_metadata', { method:'POST', headers:{ 'Authorization':'Bearer '+token, 'Content-Type':'application/json' }, body: arg({ path }) });
  const t = await r.text();
  if (r.status === 409 && t.includes('not_found')) return { missing: true };
  if (!r.ok) throw new Error('get_metadata '+r.status+' '+t.slice(0,160));
  const j = JSON.parse(t);
  if (j['.tag'] !== 'file') return { missing: true };
  return { missing: false, size: Number(j.size), content_hash: String(j.content_hash||'') };
}
async function verifyUploaded(token: string, dest: string, hash: string, size: number){
  const m = await dbxMeta(token, dest);
  if (m.missing) throw new Error('verify: missing in Dropbox after upload');
  if (m.size !== size) throw new Error(`verify: size ${m.size} in Dropbox != ${size} sent`);
  if (m.content_hash !== hash) throw new Error('verify: content_hash mismatch '+m.content_hash.slice(0,12)+' != '+hash.slice(0,12));
}

// WEEKLY RECONCILIATION. Verified rows are compared against the hash recorded at upload. Rows done
// before v6 have no recorded hash, so their source is downloaded and hashed once (if it still exists
// and is not huge) — the first real confirmation those rows ever get.
async function reconcile(token: string, n: number){
  const { data: rows, error } = await admin.rpc('fn_dropbox_reconcile_sample', { p_n: n });
  if (error) throw new Error('sample '+error.message);
  const results: any[] = [];
  for (const row of (rows||[]) as any[]){
    try {
      const m = await dbxMeta(token, row.dropbox_path);
      if (m.missing){ results.push({ id: row.id, outcome: 'missing' }); continue; }
      let expect: string | null = row.dropbox_content_hash, basis = 'recorded';
      if (!expect){
        if (!row.bucket || !row.path || Number(row.bytes||0) > SINGLE_MAX){ results.push({ id: row.id, outcome: 'unverifiable', hash: m.content_hash, size: m.size, note: 'no recorded hash and source not hashable' }); continue; }
        const { data: blob } = await admin.storage.from(row.bucket).download(row.path);
        if (!blob){ results.push({ id: row.id, outcome: 'unverifiable', hash: m.content_hash, size: m.size, note: 'source object no longer in storage' }); continue; }
        expect = await dropboxContentHash(new Uint8Array(await (blob as Blob).arrayBuffer())); basis = 'source';
      }
      results.push({ id: row.id, outcome: m.content_hash === expect ? 'ok' : 'changed', hash: m.content_hash, size: m.size, basis });
    } catch (e){ results.push({ id: row.id, outcome: 'error', note: String((e as Error)?.message||e).slice(0,160) }); }
  }
  const { data: applied, error: aerr } = await admin.rpc('fn_dropbox_reconcile_apply', { p_results: results });
  if (aerr) throw new Error('apply '+aerr.message);
  return applied;
}
function kvTable(rows: [string, unknown][]){ return '<table style="border-collapse:collapse;width:100%">' + rows.map(([k,v])=>`<tr><td style="padding:4px 10px 4px 0;color:#555;white-space:nowrap;vertical-align:top">${esc(k)}</td><td style="padding:4px 0"><b>${esc(v)}</b></td></tr>`).join('') + '</table>'; }

async function renderGenerated(row: any): Promise<{bucket:string, path:string}>{
  let title = 'Document'; let inner = '';
  if (row.gen_kind === 'supplier_details'){
    const { data: l } = await admin.from('leads').select('*').eq('id', Number(row.gen_ref)).maybeSingle();
    if (!l) throw new Error('supplier_missing');
    title = 'Company Details — ' + (l.company_name || ('Supplier '+row.gen_ref));
    inner = `<h2>${esc(l.company_name)}</h2>` + kvTable([
      ['Supplier ID', l.id], ['Category', l.categories || l.sector], ['Sub-type', l.sub_type], ['Emirate', l.emirate], ['City', l.city], ['Contact', l.contact_name],
      ['Phone', l.phone_e164 || l.phone], ['Email', l.email], ['Website', l.website],
      ['Trade licence no', l.trade_license_no], ['Licence authority', l.license_authority], ['Licence expiry', fmtD(l.license_expiry)], ['TRN', l.trn], ['VAT number', l.vat_number],
      ['Registration status', l.registration_status], ['Approval status', l.approval_status], ['Approved at', fmtD(l.approved_at)], ['Services', Array.isArray(l.services)? l.services.join(', ') : l.services],
    ]) + (l.capability_summary ? `<h3>Capability summary</h3><p>${esc(l.capability_summary)}</p>` : '');
  } else if (row.gen_kind === 'customer_details'){
    const { data: c } = await admin.from('customers').select('*').eq('id', row.gen_ref).maybeSingle();
    if (!c) throw new Error('customer_missing');
    title = 'Customer Details — ' + (c.full_name || 'Customer');
    inner = kvTable([
      ['Customer ID', c.id], ['Full name', c.full_name], ['Phone', c.phone], ['Phone verified', c.phone_verified? 'Yes':'No'],
      ['Email', c.email], ['Email verified', c.email_verified? 'Yes':'No'], ['Registered', fmtD(c.created_at)],
      ['Terms version', c.tos_version], ['Terms accepted', fmtD(c.tos_accepted_at || c.signed_terms_at)], ['WhatsApp opt-in', c.wa_optin? 'Yes':'No'],
    ]);
  } else if (row.gen_kind === 'inquiry_summary'){
    const { data: i } = await admin.from('inquiries').select('*').eq('id', row.gen_ref).maybeSingle();
    if (!i) throw new Error('inquiry_missing');
    const { data: c } = await admin.from('customers').select('full_name').eq('id', i.customer_id).maybeSingle();
    title = 'Inquiry Summary — ' + String(row.gen_ref).slice(0,8);
    inner = kvTable([ ['Inquiry ID', i.id], ['Customer', c?.full_name], ['Status', i.status], ['Created', fmtD(i.created_at)], ['Drawing on file', i.drawing_file_name || (i.drawing_file_path? 'yes':'—')] ]) + (i.summary ? `<h3>Request</h3><p>${esc(i.summary)}</p>` : '');
  } else throw new Error('unknown_gen_kind');

  // pdf_native takes body_html and adds its own letterhead/title, so the <html> wrapper and the <h1>
  // that make_pdf needed would both be duplicated here. It writes to storage and returns the path.
  const body_html = inner + `<p style="margin-top:24px;color:#888;font-size:11px">Auto-generated backup document — QuotesDone · ${new Date().toISOString().slice(0,10)}</p>`;
  const r = await fetch(`${BASE}/pdf_native`, { method:'POST', headers:{ 'Content-Type':'application/json' }, body: JSON.stringify({ __secret: await sec('cred_fn_to_pdf_native'), title, body_html, name: (row.gen_kind+'_'+row.gen_ref).replace(/[^a-z0-9_]+/gi,'_').slice(0,60), bucket:'backups', folder:'generated', options:{ letterhead:true } }) });
  const jd = await r.json().catch(()=>({} as any));
  if (!jd?.path) throw new Error('pdf_native '+(jd?.error||r.status));
  return { bucket: 'backups', path: String(jd.path) };
}

Deno.serve(observe('dropbox_backup', async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'dropbox_backup');
    if (!__auth.ok) { await logThrottled('forbidden', 60, 'error', { stage:'auth' }, 'dropbox_backup rejected a caller presenting a bad or missing inbound secret. If this is the scheduled caller, no Dropbox backup is running at all and every backup is stale.'); return J({ error:'forbidden' }, 403); }

    if (body.op === 'selftest'){
      const token = await accessToken(); if(!token) { await logThrottled('no_dropbox_auth', 60, 'error', { stage:'selftest' }, 'Dropbox selftest could not obtain an access token (refresh token / app key / app secret missing or rejected). Dropbox backups are not running; every document backup is stale until the OAuth credentials are restored.'); return J({ ok:false, error:'no_dropbox_auth' }); }
      const dest = '/QuotesDone Backup/_selftest/probe_'+Date.now()+'.txt';
      await uploadSingle(token, dest, new TextEncoder().encode('quotesdone dropbox backup selftest').buffer as ArrayBuffer);
      const del = await fetch('https://api.dropboxapi.com/2/files/delete_v2', { method:'POST', headers:{ 'Authorization':'Bearer '+token, 'Content-Type':'application/json' }, body: JSON.stringify({ path: dest }) });
      return J({ ok:true, uploaded:dest, deleted_probe: del.ok });
    }

    // DELETION IS NOT PART OF THIS RESTORE. The v4 body of this branch called Dropbox files/delete_v2
    // and storage.remove() for every row in pdpl_erase_files. It is refused rather than removed so a
    // caller learns the capability is off instead of getting a silent 'unknown op' and assuming the
    // erasure ran. pdpl_erase_files rows are left untouched — nothing is marked 'erased' that is not.
    if (body.op === 'pdpl_erase'){
      await logRun('error', { stage:'pdpl_erase_refused', request_id: String(body.request_id||'') },
        'A PDPL file-erasure was requested from dropbox_backup and REFUSED. This function was restored on '
        + '9 Sep 2026 as an add-only backup and its delete path is disabled, so no file was removed from '
        + 'Dropbox or storage and no pdpl_erase_files row was marked erased. The erasure request is still '
        + 'outstanding and needs an owner who will re-enable this deliberately.');
      return J({ ok:false, error:'deletion_disabled',
        message:'dropbox_backup is an add-only backup since the 9 Sep 2026 restore. It no longer deletes from Dropbox or storage. Nothing was erased and no row was marked erased.' }, 409);
    }

    if (body.mode === 'reconcile'){
      // Logged ONLY through fn_dropbox_reconcile_apply (agent 'dropbox_reconcile'); a logRun here
      // would write agent 'dropbox_backup' and a failure would read as a failed backup.
      try {
        const token = await accessToken();
        if (!token) throw new Error('no_dropbox_auth');
        return J({ ok:true, mode:'reconcile', result: await reconcile(token, Math.min(Number(body.limit)||20, 200)) });
      } catch (e){
        const msg = String((e as Error)?.message||e).slice(0,300);
        await admin.rpc('fn_dropbox_reconcile_apply', { p_results: [], p_error: msg });
        return J({ ok:false, mode:'reconcile', error: msg }, 500);
      }
    }

    const limit = Math.min(Number(body.limit)||8, 25);
    let enqueued = 0;
    if (body.mode !== 'process_only') { const { data, error: enqErr } = await admin.rpc('fn_enqueue_doc_backups'); enqueued = Number(data)||0; if (enqErr) { await logThrottled('enqueue_failed', 60, 'error', { stage:'enqueue' }, 'fn_enqueue_doc_backups failed, so no new documents are being queued for Dropbox backup; newly uploaded documents will never reach Dropbox until this is fixed. ' + String(enqErr?.message||enqErr).slice(0,160)); } }
    const token = await accessToken();
    if (!token) { await logThrottled('no_dropbox_auth', 60, 'error', { stage:'token', enqueued }, 'Dropbox backup could not obtain an access token (refresh token expired/revoked or app key/secret missing). No documents are being backed up to Dropbox and the backup set is going stale from this point onward.'); return J({ ok:false, error:'no_dropbox_auth', enqueued }); }

    const { data: rows } = await admin.from('doc_backups').select('*').in('status',['pending','error']).lt('attempts',5).order('id',{ ascending:true }).limit(limit);
    let done=0, failed=0, skipped=0; const results:any[]=[];
    const errNotes:string[] = [];
    for (const row of (rows||[])){
      try {
        let bucket = row.bucket, path = row.path;
        if (row.source === 'generated' && !path){ const g = await renderGenerated(row); bucket = g.bucket; path = g.path; await admin.from('doc_backups').update({ bucket, path }).eq('id', row.id); }
        if (!bucket || !path) throw new Error('no_source');
        const { data: blob, error: derr } = await admin.storage.from(bucket).download(path);
        if (derr || !blob) throw new Error('download '+(derr?.message||'missing'));
        const size = (blob as Blob).size;
        if (size > HARD_MAX){ await admin.from('doc_backups').update({ status:'skipped_large', bytes:size, error:'>1GB', attempts:row.attempts+1 }).eq('id',row.id); skipped++; results.push({ id:row.id, skipped_large:size }); continue; }
        let hash: string;
        if (size <= SINGLE_MAX){ const buf = await (blob as Blob).arrayBuffer(); hash = await dropboxContentHash(new Uint8Array(buf)); await uploadSingle(token, row.dropbox_path, buf); }
        else { const { data: su } = await admin.storage.from(bucket).createSignedUrl(path, 900); if(!su?.signedUrl) throw new Error('sign_failed'); hash = await uploadSession(token, row.dropbox_path, su.signedUrl, size); }
        // Throws on missing / size / hash mismatch -> the catch below marks 'error' and retries.
        await verifyUploaded(token, row.dropbox_path, hash, size);
        const now = new Date().toISOString();
        const { error: markErr } = await admin.from('doc_backups').update({ status:'done', bytes:size, backed_up_at:now, error:null, attempts:row.attempts+1, dropbox_content_hash:hash, dropbox_size:size, verified_at:now }).eq('id',row.id);
        if (markErr) { await logRun('error', { stage:'mark_done', doc_backup_id: row.id }, 'Document ' + row.id + ' was uploaded to Dropbox but could not be marked done, so it will be re-uploaded on every future run and the backup queue will never drain. ' + String(markErr?.message||markErr).slice(0,160)); }
        done++; results.push({ id:row.id, done:size, dest:row.dropbox_path });
      } catch (e){
        await admin.from('doc_backups').update({ status:'error', error:String((e as Error)?.message||e).slice(0,300), attempts:row.attempts+1 }).eq('id',row.id);
        failed++; results.push({ id:row.id, error:String((e as Error)?.message||e).slice(0,160) });
        if (errNotes.length < 3) errNotes.push('#'+row.id+': '+String((e as Error)?.message||e).slice(0,120));
      }
    }
    const processed = (rows||[]).length;
    if (processed > 0 || enqueued > 0 || failed > 0 || skipped > 0) {
      const counts = { enqueued, processed, done, failed, skipped };
      if (failed > 0 || skipped > 0) {
        await logRun('error', counts, 'Dropbox backup finished with ' + failed + ' failed and ' + skipped + ' oversized-skipped document(s) out of ' + processed + '; those documents are NOT in Dropbox and will be missing if the backup is ever needed. ' + errNotes.join(' | '));
      } else {
        await logRun('ok', counts, 'Dropbox backup uploaded ' + done + ' document(s); queue drained cleanly.');
      }
    }
    return J({ ok:true, enqueued, processed:(rows||[]).length, done, failed, skipped, results });
  } catch (e){ await logRun('error', { stage:'fatal' }, 'dropbox_backup crashed before completing; the Dropbox backup run did not finish and documents from this window are not backed up. ' + String((e as Error)?.message||e).slice(0,200)); return J({ error:String((e as Error)?.message||e) }, 500); }
}));
