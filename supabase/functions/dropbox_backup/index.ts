// dropbox_backup v4 — organized Dropbox backup tree under '/QuotesDone Backup'. 'storage' rows are downloaded from
// Supabase Storage; 'generated' rows are rendered to branded PDF via make_pdf first (customer/supplier details,
// inquiry summary, quote comparison). Read-only on our storage; only uploads to Dropbox. Exception: op:pdpl_erase deletes the
// files queued in pdpl_erase_files for an approved PDPL erasure request (Dropbox delete_v2 + storage remove). inbound_secret gated.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
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
async function uploadSession(token: string, dest: string, signedUrl: string, size: number){
  let r = await fetch('https://content.dropboxapi.com/2/files/upload_session/start', { method:'POST', headers:{ 'Authorization':'Bearer '+token, 'Content-Type':'application/octet-stream', 'Dropbox-API-Arg': arg({ close:false }) }, body:new Uint8Array(0) });
  if (!r.ok) throw new Error('session_start '+r.status);
  const sid = (await r.json()).session_id as string; let off = 0;
  while (off < size){ const end = Math.min(off+CHUNK, size)-1; const g = await fetch(signedUrl, { headers:{ 'Range':`bytes=${off}-${end}` } }); if(!(g.status===206||g.status===200)) throw new Error('range_get '+g.status); const buf = await g.arrayBuffer(); if(buf.byteLength===0) throw new Error('empty_chunk'); r = await fetch('https://content.dropboxapi.com/2/files/upload_session/append_v2', { method:'POST', headers:{ 'Authorization':'Bearer '+token, 'Content-Type':'application/octet-stream', 'Dropbox-API-Arg': arg({ cursor:{ session_id:sid, offset:off }, close:false }) }, body:buf }); if(!r.ok) throw new Error('append '+r.status); off += buf.byteLength; }
  r = await fetch('https://content.dropboxapi.com/2/files/upload_session/finish', { method:'POST', headers:{ 'Authorization':'Bearer '+token, 'Content-Type':'application/octet-stream', 'Dropbox-API-Arg': arg({ cursor:{ session_id:sid, offset:size }, commit:{ path:dest, mode:'overwrite', autorename:false, mute:true } }) }, body:new Uint8Array(0) });
  if (!r.ok) throw new Error('finish '+r.status);
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
  } else if (row.gen_kind === 'comparison'){
    const inqId = String(row.gen_ref);
    const r0 = await fetch(`${BASE}/quote_compare`, { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ __secret: await sec('inbound_secret'), inquiry_id: inqId }) });
    const cj = await r0.json().catch(()=>({} as any));
    if (!cj?.ok || !cj.analysis) throw new Error('compare '+(cj?.error||cj?.note||r0.status));
    const a = cj.analysis;
    try { const { data: inq } = await admin.from('inquiries').select('customer_id').eq('id', inqId).maybeSingle(); await admin.from('quote_comparisons').insert({ inquiry_id: inqId, customer_id: inq?.customer_id, lang:'en', quote_count:(a.quotes||[]).length, analysis:a }); } catch(_e){ await logRun('error', { stage:'quote_comparisons_insert', inquiry_id: inqId }, 'Backup rendered a quote comparison PDF but failed to store the comparison row for inquiry ' + inqId + '; the comparison history table is incomplete for this inquiry. ' + String((_e as Error)?.message||_e).slice(0,160)); }
    title = 'Quote Comparison — Inquiry ' + inqId.slice(0,8);
    const quotes = (a.quotes||[]).map((x:any)=>`<div style="margin:8px 0;padding:8px;border:1px solid #eee;border-radius:6px"><b>${esc(x.label)}</b>${x.price!=null?' — AED '+esc(x.price):''}${x.lead_time?' · '+esc(x.lead_time):''}${x.warranty?' · warranty '+esc(x.warranty):''}<br><span style="color:#555">${esc(x.getting||'')}</span>${(x.spec_deviation&&x.spec_deviation.length)?'<br>Δ '+x.spec_deviation.map(esc).join('; '):''}${(x.flags&&x.flags.length)?'<br>⚠ '+x.flags.map(esc).join('; '):''}</div>`).join('');
    const top3 = (a.top3||[]).map((t:any)=>`<li><b>#${esc(t.rank)} ${esc(t.label)}</b> — ${esc(t.why)}${t.tradeoff?' <i>('+esc(t.tradeoff)+')</i>':''}</li>`).join('');
    const watch = (a.watch_outs||[]).map((w:any)=>`<li>${esc(w)}</li>`).join('');
    inner = `<p><b>Bottom line:</b> ${esc(a.bottom_line)}</p>` + (a.overview?`<p>${esc(a.overview)}</p>`:'')
      + (top3?`<h3>Top picks</h3><ol>${top3}</ol>`:'') + `<h3>Quotes (anonymized)</h3>${quotes}`
      + (watch?`<h3>Watch-outs</h3><ul>${watch}</ul>`:'') + (a.advice?`<p><b>Advice:</b> ${esc(a.advice)}</p>`:'')
      + `<p style="color:#888;font-size:11px">Suppliers are anonymized (A/B/C). Comparison of the quotes on file at generation time.</p>`;
  } else throw new Error('unknown_gen_kind');

  const html = `<html><head><title>${esc(title)}</title></head><body><h1>${esc(title)}</h1>${inner}<p style="margin-top:24px;color:#888;font-size:11px">Auto-generated backup document — QuotesDone · ${new Date().toISOString().slice(0,10)}</p></body></html>`;
  const r = await fetch(`${BASE}/make_pdf`, { method:'POST', headers:{ 'Content-Type':'application/json' }, body: JSON.stringify({ __secret: await sec('inbound_secret'), html, title, name: (row.gen_kind+'_'+row.gen_ref).replace(/[^a-z0-9_]+/gi,'_').slice(0,60), bucket:'backups', folder:'generated' }) });
  const jd = await r.json().catch(()=>({} as any));
  if (!jd?.path) throw new Error('make_pdf '+(jd?.error||r.status));
  return { bucket: 'backups', path: String(jd.path) };
}

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    const __exp = await sec('inbound_secret');
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

    if (body.op === 'pdpl_erase'){
      const reqId = String(body.request_id||'');
      if (!reqId) return J({ ok:false, error:'request_id required' }, 400);
      const token = await accessToken();
      const { data: files } = await admin.from('pdpl_erase_files').select('*').eq('request_id', reqId).eq('status','pending').order('id',{ ascending:true }).limit(Math.min(Number(body.limit)||200, 500));
      let dbx=0, stg=0, failed=0; const results:any[]=[];
      for (const f of (files||[])){
        let ok=true, err='';
        if (f.dropbox_path){
          if (!token){ ok=false; err='no_dropbox_auth'; }
          else { const dr = await fetch('https://api.dropboxapi.com/2/files/delete_v2', { method:'POST', headers:{ 'Authorization':'Bearer '+token, 'Content-Type':'application/json' }, body: JSON.stringify({ path: f.dropbox_path }) });
            if (dr.ok) dbx++; else { const t = await dr.text(); if (t.includes('not_found')||t.includes('path_lookup')) dbx++; else { ok=false; err='dbx:'+dr.status; } } }
        }
        if (f.bucket && f.storage_path){ const { error: se } = await admin.storage.from(f.bucket).remove([f.storage_path]); if (se){ ok=false; err=(err?err+';':'')+'stg:'+se.message; } else stg++; }
        await admin.from('pdpl_erase_files').update({ status: ok?'erased':'error', error: ok?null:err.slice(0,300), erased_at: ok? new Date().toISOString(): null }).eq('id', f.id);
        if (!ok) failed++;
        results.push({ id:f.id, ok, err: ok?undefined:err });
      }
      try { await admin.from('security_events').insert({ kind:'pdpl_file_erasure', severity:'high', source:'dropbox_backup', subject: reqId, detail:{ request_id:reqId, dropbox_deleted:dbx, storage_deleted:stg, failed, processed:(files||[]).length } }); } catch(_e){ /* audit best-effort */ }
      await logRun(failed>0?'error':'ok', { pdpl_erase:reqId, dbx, stg, failed }, failed>0 ? ('PDPL file erasure for request '+reqId+' left '+failed+' file(s) undeleted; personal documents may remain in Dropbox/storage — inspect pdpl_erase_files.') : ('PDPL file erasure for request '+reqId+': '+dbx+' Dropbox + '+stg+' storage object(s) removed.'));
      return J({ ok: failed===0, request_id:reqId, processed:(files||[]).length, dropbox_deleted:dbx, storage_deleted:stg, failed, results });
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
        if (size <= SINGLE_MAX){ await uploadSingle(token, row.dropbox_path, await (blob as Blob).arrayBuffer()); }
        else { const { data: su } = await admin.storage.from(bucket).createSignedUrl(path, 900); if(!su?.signedUrl) throw new Error('sign_failed'); await uploadSession(token, row.dropbox_path, su.signedUrl, size); }
        const { error: markErr } = await admin.from('doc_backups').update({ status:'done', bytes:size, backed_up_at:new Date().toISOString(), error:null, attempts:row.attempts+1 }).eq('id',row.id);
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
});
