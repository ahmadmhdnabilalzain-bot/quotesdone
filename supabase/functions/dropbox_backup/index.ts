// dropbox_backup v8 (14 Sep 2026; sales_engineer owns the upload, it_engineer owns auth and health).
// The founder, 14 Sep 2026: "we need to eliminate all other causes with fixes. unless its a server
// issue from dropbox or supabase then i see no reason for any failures".
//   * Every Dropbox call goes through DropboxClient (dropbox.ts): a fresh token from the offline
//     refresh token each run, and a 401 is refreshed and repeated once.
//   * Every file larger than 8 MiB is a chunked upload session (upload.ts): per-chunk retry, and a run
//     that reaches its deadline saves {session_id, offset, blocks} in doc_backups.upload_state so the
//     next run resumes. The source is read with HTTP Range requests, so a large file is never held
//     in memory whole. The 1 GB ceiling is gone.
//   * The queue is read through fn_doc_backups_next (backoff, resume-first, no ZZ DEMO rows).
//   * A pass that filled its batch calls itself again (process_only, up to 20 links) so a backlog
//     drains in minutes instead of one batch per 15-minute tick.
//   * op 'health' (it_engineer, daily): auth probe (write, read, delete in /_selftest/), space usage and
//     plan, handed to fn_it_dropbox_health_record. op 'selftest_large': a synthetic multi-chunk file
//     uploaded in two runs (stopped after one chunk, then resumed), hash-verified and deleted.
// SQL: scripts/sql/a_document_reaches_dropbox_when_it_lands_and_only_once_it_exists.sql and
// scripts/sql/the_it_engineer_fixes_what_it_finds_and_emails_only_a_new_bug.sql.
//
// v7 and earlier (kept as history, still true): v7 body.ids re-checks named rows (job 'targeted') and
// the daily sample is new-unverified rows plus a weekly random sample. v6 confirms every upload with
// files/get_metadata (size AND content_hash). v5 builds the organised tree; 'generated' rows are
// rendered by pdf_native. The quote-comparison document is gone (it needed a model). op pdpl_erase
// is refused: this is an add-only backup.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { observe } from '../_shared/observe.ts';
import { dropboxContentHash } from './content_hash.ts';
import { DropboxClient, refreshAccessToken } from './dropbox.ts';
import { CHUNK, uploadFile, type ReadChunk, type UploadState } from './upload.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const T0 = Date.now();
const DEADLINE = T0 + 110_000;           // leave room under the 150 s edge limit to record the result
const SELF = Deno.env.get('SUPABASE_URL')! + '/functions/v1/dropbox_backup';
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
const errText = (e: unknown) => String((e as Error)?.message || e);

async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  const { error } = await admin.from('agent_runs').insert({ agent: 'dropbox_backup', status, counts,
    note: String(note || '').slice(0, 500), started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  if (error) console.error('agent_runs insert failed:', error.message);
}
async function logThrottled(signal: string, minutes: number, status: string, counts: Record<string, unknown>, note: string) {
  const since = new Date(Date.now() - minutes * 60000).toISOString();
  const { data } = await admin.from('agent_runs').select('id').eq('agent', 'dropbox_backup')
    .gte('started_at', since).eq('counts->>signal', signal).limit(1);
  if (data && data.length) return;
  await logRun(status, { ...counts, signal }, note);
}
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
const esc = (s: unknown) => String(s ?? '—').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' } as Record<string, string>)[c]);
const fmtD = (s: unknown) => { if (!s) return '—'; try { return new Date(String(s)).toISOString().slice(0, 10); } catch { return String(s); } };

async function client(): Promise<DropboxClient> {
  const [rt, key, secret] = await Promise.all([sec('dropbox_refresh_token'), sec('dropbox_app_key'), sec('dropbox_app_secret')]);
  return new DropboxClient(() => refreshAccessToken(rt, key, secret));
}

// files/get_metadata. A 409 path/not_found is an ANSWER ("missing"); any other non-200 throws so a
// Dropbox outage is never read as a missing file.
async function dbxMeta(dbx: DropboxClient, path: string): Promise<{ missing: true } | { missing: false; size: number; content_hash: string }> {
  const r = await dbx.call('api', 'files/get_metadata', { path });
  const t = await r.text();
  if (r.status === 409 && t.includes('not_found')) return { missing: true };
  if (!r.ok) throw new Error('get_metadata ' + r.status + ' ' + t.slice(0, 160));
  const j = JSON.parse(t);
  if (j['.tag'] !== 'file') return { missing: true };
  return { missing: false, size: Number(j.size), content_hash: String(j.content_hash || '') };
}
async function verifyUploaded(dbx: DropboxClient, dest: string, hash: string, size: number) {
  const m = await dbxMeta(dbx, dest);
  if (m.missing) throw new Error('verify: missing in Dropbox after upload');
  if (m.size !== size) throw new Error(`verify: size ${m.size} in Dropbox != ${size} sent`);
  if (m.content_hash !== hash) throw new Error('verify: content_hash mismatch ' + m.content_hash.slice(0, 12) + ' != ' + hash.slice(0, 12));
}
async function dbxDelete(dbx: DropboxClient, path: string): Promise<boolean> {
  const r = await dbx.call('api', 'files/delete_v2', { path }); await r.body?.cancel(); return r.ok;
}

// A storage object read by HTTP Range: the first request also answers the size (Content-Range).
async function storageSource(bucket: string, path: string): Promise<{ size: number; read: ReadChunk }> {
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

// WEEKLY RECONCILIATION (v6/v7, unchanged in behaviour).
async function reconcile(dbx: DropboxClient, n: number, ids?: number[]) {
  const { data: rows, error } = ids?.length
    ? await admin.from('doc_backups').select('id,dropbox_path,bucket,path,bytes,dropbox_content_hash').in('id', ids)
    : await admin.rpc('fn_dropbox_reconcile_sample', { p_n: n });
  if (error) throw new Error('sample ' + error.message);
  const results: Record<string, unknown>[] = [];
  for (const row of (rows || []) as Record<string, any>[]) {
    try {
      const m = await dbxMeta(dbx, row.dropbox_path);
      if (m.missing) { results.push({ id: row.id, outcome: 'missing' }); continue; }
      let expect: string | null = row.dropbox_content_hash, basis = 'recorded';
      if (!expect) {
        if (!row.bucket || !row.path || Number(row.bytes || 0) > 140 * 1024 * 1024) { results.push({ id: row.id, outcome: 'unverifiable', hash: m.content_hash, size: m.size, note: 'no recorded hash and source not hashable' }); continue; }
        const { data: blob } = await admin.storage.from(row.bucket).download(row.path);
        if (!blob) { results.push({ id: row.id, outcome: 'unverifiable', hash: m.content_hash, size: m.size, note: 'source object no longer in storage' }); continue; }
        expect = await dropboxContentHash(new Uint8Array(await blob.arrayBuffer())); basis = 'source';
      }
      results.push({ id: row.id, outcome: m.content_hash === expect ? 'ok' : 'changed', hash: m.content_hash, size: m.size, basis, why: row.why });
    } catch (e) { results.push({ id: row.id, outcome: 'error', note: errText(e).slice(0, 160) }); }
  }
  const { data: applied, error: aerr } = ids?.length
    ? await admin.rpc('fn_it_backup_check', { p_results: results, p_job: 'targeted' })
    : await admin.rpc('fn_dropbox_reconcile_apply', { p_results: results });
  if (aerr) throw new Error('apply ' + aerr.message);
  return applied;
}

function kvTable(rows: [string, unknown][]) { return '<table style="border-collapse:collapse;width:100%">' + rows.map(([k, v]) => `<tr><td style="padding:4px 10px 4px 0;color:#555;white-space:nowrap;vertical-align:top">${esc(k)}</td><td style="padding:4px 0"><b>${esc(v)}</b></td></tr>`).join('') + '</table>'; }

// deno-lint-ignore no-explicit-any
async function renderGenerated(row: any): Promise<{ bucket: string; path: string }> {
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
  const r = await fetch(Deno.env.get('SUPABASE_URL')! + '/functions/v1/pdf_native', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec('cred_fn_to_pdf_native'), title, body_html, name: (row.gen_kind + '_' + row.gen_ref).replace(/[^a-z0-9_]+/gi, '_').slice(0, 60), bucket: 'backups', folder: 'generated', options: { letterhead: true } }) });
  const jd = await r.json().catch(() => ({} as Record<string, unknown>));
  if (!jd?.path) throw new Error('pdf_native ' + (jd?.error || r.status));
  return { bucket: 'backups', path: String(jd.path) };
}

// it_engineer: the daily auth probe and space/plan reading. Every stage is recorded, never thrown away.
async function health() {
  const out: Record<string, unknown> = { auth_ok: false, write_ok: false, read_ok: false, delete_ok: false };
  try {
    const dbx = await client();
    const probe = `/QuotesDone Backup/_selftest/auth_probe_${Date.now()}.txt`;
    const bytes = new TextEncoder().encode('quotesdone dropbox auth probe ' + new Date().toISOString());
    const up = await uploadFile(dbx, probe, bytes.length, (o, n) => Promise.resolve(bytes.slice(o, o + n)));
    out.auth_ok = true; out.write_ok = up.done;
    if (up.done) { await verifyUploaded(dbx, probe, up.hash, bytes.length); out.read_ok = true; }
    out.delete_ok = await dbxDelete(dbx, probe);
    const s = await dbx.call('api', 'users/get_space_usage', null);
    const sj = await s.json();
    if (!s.ok) throw new Error('get_space_usage ' + s.status);
    out.used = Number(sj.used); out.allocated = Number(sj.allocation?.allocated ?? sj.allocation?.used ?? 0);
    const a = await dbx.call('api', 'users/get_current_account', null);
    const aj = await a.json();
    out.plan = a.ok ? String(aj.account_type?.['.tag'] || '') : 'unknown';
    out.refreshes = dbx.refreshes;
  } catch (e) { out.error = errText(e).slice(0, 300); }
  const { data, error } = await admin.rpc('fn_it_dropbox_health_record', { p: out });
  if (error) throw new Error('fn_it_dropbox_health_record: ' + error.message);
  return { reading: out, recorded: data };
}

// sales_engineer: prove chunking and resume against the real Dropbox, in /_selftest/ only.
async function selftestLarge(mb: number) {
  const size = Math.round(Math.min(Math.max(mb, 9), 48) * 1024 * 1024);
  const src = new Uint8Array(size); for (let i = 0; i < size; i++) src[i] = (i * 31 + (i >> 13)) & 255;
  const read: ReadChunk = (o, n) => Promise.resolve(src.slice(o, o + n));
  const dbx = await client();
  const dest = `/QuotesDone Backup/_selftest/large_${Date.now()}.bin`;
  const first = await uploadFile(dbx, dest, size, read, { maxChunks: 1 });
  if (first.done) throw new Error('selftest_large: the first run was meant to stop after one chunk');
  const state: UploadState = JSON.parse(JSON.stringify(first.state));   // as it would be stored
  const stoppedAt = state.offset;
  const second = await uploadFile(dbx, dest, size, read, { state });
  if (!second.done) throw new Error('selftest_large: the resumed run did not finish');
  const expect = await dropboxContentHash(src);
  await verifyUploaded(dbx, dest, second.hash, size);
  const deleted = await dbxDelete(dbx, dest);
  return { bytes: size, chunks: first.chunks + second.chunks, stopped_at: stoppedAt, resumed: true,
           hash_matches_source: second.hash === expect, verified_in_dropbox: true, deleted, retries: first.retries + second.retries };
}

Deno.serve(observe('dropbox_backup', async (req) => {
  try {
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const auth = await requireInternal(admin, body?.__secret, 'dropbox_backup');
    if (!auth.ok) { await logThrottled('forbidden', 60, 'error', { stage: 'auth' }, 'dropbox_backup rejected a caller presenting a bad or missing inbound secret. If this is the scheduled caller, no Dropbox backup is running at all and every backup is stale.'); return J({ error: 'forbidden' }, 403); }

    if (body.op === 'health') return J({ ok: true, op: 'health', ...(await health()) });
    if (body.op === 'selftest_large') return J({ ok: true, op: 'selftest_large', ...(await selftestLarge(Number(body.mb) || 20)) });
    if (body.op === 'pdpl_erase') {
      await logRun('error', { stage: 'pdpl_erase_refused', request_id: String(body.request_id || '') },
        'A PDPL file-erasure was requested from dropbox_backup and REFUSED. This function is an add-only backup and its delete path is disabled, so no file was removed from Dropbox or storage and no pdpl_erase_files row was marked erased. The erasure request is still outstanding and needs an owner who will re-enable this deliberately.');
      return J({ ok: false, error: 'deletion_disabled', message: 'dropbox_backup is an add-only backup. It does not delete from Dropbox or storage. Nothing was erased and no row was marked erased.' }, 409);
    }
    if (body.op !== undefined) return J({ ok: false, error: 'unknown_op' }, 400);

    if (body.mode === 'reconcile') {
      // Logged ONLY through fn_dropbox_reconcile_apply (agent 'it_engineer'): a logRun here would read as a failed backup.
      try {
        const ids = Array.isArray(body.ids) ? body.ids.map(Number).filter(Number.isFinite).slice(0, 50) : undefined;
        return J({ ok: true, mode: 'reconcile', result: await reconcile(await client(), Math.min(Number(body.limit) || 20, 200), ids) });
      } catch (e) {
        const msg = errText(e).slice(0, 300);
        await admin.rpc('fn_dropbox_reconcile_apply', { p_results: [], p_error: msg });
        return J({ ok: false, mode: 'reconcile', error: msg }, 500);
      }
    }
    if (body.mode !== undefined && !['process_only', 'enqueue'].includes(String(body.mode))) return J({ ok: false, error: 'unknown_mode' }, 400);

    const limit = Math.min(Number(body.limit) || 8, 25);
    const chain = Math.max(0, Math.min(Number(body.chain) || 0, 20));
    let enqueued = 0;
    if (body.mode !== 'process_only') {
      const { data, error } = await admin.rpc('fn_enqueue_doc_backups'); enqueued = Number(data) || 0;
      if (error) await logThrottled('enqueue_failed', 60, 'error', { stage: 'enqueue' }, 'fn_enqueue_doc_backups failed, so no new documents are being queued for Dropbox backup. ' + error.message.slice(0, 160));
    }
    const dbx = await client();
    const run = `dropbox_backup:${T0}:${crypto.randomUUID().slice(0, 8)}`;
    const { data: rows, error: qerr } = await admin.rpc('fn_doc_backups_next', { p_limit: limit, p_run: run });
    if (qerr) throw new Error('fn_doc_backups_next: ' + qerr.message);

    let done = 0, failed = 0, resumed = 0; const results: Record<string, unknown>[] = []; const errNotes: string[] = [];
    // deno-lint-ignore no-explicit-any
    for (const row of (rows || []) as any[]) {
      const now = () => new Date().toISOString();
      const release = { claimed_at: null, claimed_by: null };
      try {
        if (Date.now() >= DEADLINE) { await admin.from('doc_backups').update({ status: 'pending', ...release }).eq('id', row.id); continue; }
        let bucket = row.bucket, path = row.path;
        if (row.source === 'generated' && !path) { const g = await renderGenerated(row); bucket = g.bucket; path = g.path; await admin.from('doc_backups').update({ bucket, path }).eq('id', row.id); }
        if (!bucket || !path) throw new Error('no_source');
        const src = await storageSource(bucket, path);
        const up = await uploadFile(dbx, row.dropbox_path, src.size, src.read, { state: row.upload_state, deadline: DEADLINE });
        if (!up.done) {
          await admin.from('doc_backups').update({ status: 'pending', ...release, upload_state: up.state, bytes: src.size, last_attempt_at: now(),
            error: `resuming: ${up.state.offset} of ${src.size} bytes sent` }).eq('id', row.id);
          resumed++; results.push({ id: row.id, resuming: up.state.offset }); continue;
        }
        await verifyUploaded(dbx, row.dropbox_path, up.hash, src.size);
        const { error: markErr } = await admin.from('doc_backups').update({ status: 'done', ...release, bytes: src.size, backed_up_at: now(), error: null, attempts: row.attempts + 1,
          last_attempt_at: now(), upload_state: null, dropbox_content_hash: up.hash, dropbox_size: src.size, verified_at: now() }).eq('id', row.id);
        if (markErr) await logRun('error', { stage: 'mark_done', doc_backup_id: row.id }, 'Document ' + row.id + ' was uploaded and verified but could not be marked done: ' + markErr.message.slice(0, 160));
        done++; results.push({ id: row.id, done: src.size, chunks: up.chunks, retries: up.retries });
      } catch (e) {
        const msg = errText(e).slice(0, 300);
        await admin.from('doc_backups').update({ status: 'error', ...release, error: msg, attempts: row.attempts + 1, last_attempt_at: now(), upload_state: null }).eq('id', row.id);
        failed++; results.push({ id: row.id, error: msg.slice(0, 160) });
        if (errNotes.length < 3) errNotes.push('#' + row.id + ': ' + msg.slice(0, 120));
        if (msg === 'no_dropbox_auth') break;   // every further row would fail the same way
      }
    }
    const processed = (rows || []).length;
    const counts = { enqueued, processed, done, failed, resumed, chain, refreshes: dbx.refreshes, reason: body.reason ?? null };
    if (processed || enqueued || failed) {
      if (failed) await logRun('error', counts, 'Dropbox backup finished with ' + failed + ' failed document(s) out of ' + processed + '; the IT engineer classifies and fixes them. ' + errNotes.join(' | '));
      else await logRun('ok', counts, 'Dropbox backup uploaded ' + done + ' document(s)' + (resumed ? ', ' + resumed + ' large file(s) resume next run' : '') + '.');
    }
    // The batch was full: there is probably more. Drain it now instead of at the next tick.
    if ((processed === limit || resumed > 0) && chain < 20 && failed < processed) {
      const next = fetch(SELF, { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ __secret: body.__secret, mode: 'process_only', limit, chain: chain + 1, reason: 'drain' }) })
        .then((r) => r.body?.cancel()).catch((e) => console.error('drain link failed:', errText(e)));
      // deno-lint-ignore no-explicit-any
      (globalThis as any).EdgeRuntime?.waitUntil?.(next);
    }
    return J({ ok: true, ...counts, results });
  } catch (e) {
    await logRun('error', { stage: 'fatal' }, 'dropbox_backup crashed before completing; this run backed nothing up. ' + errText(e).slice(0, 200));
    return J({ error: errText(e) }, 500);
  }
}));
