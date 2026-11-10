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
//   * op 'health' (it_engineer, daily from resilience_ping): auth probe (write, read, delete in
//     /_selftest/), space usage and plan, each failure classed by health.ts, handed to
//     fn_it_dropbox_health_record (dropbox_is_checked_every_day_login_and_space.sql). op 'selftest_large': a synthetic multi-chunk file
//     uploaded in two runs (stopped after one chunk, then resumed), hash-verified and deleted.
//   * v9 (15 Sep 2026, it_engineer): op 'prune' deletes the Dropbox copies of export days the retention
//     rules expired (the_backups_are_kept_ninety_days_and_friday_copies_a_year.sql). Rows come only from
//     fn_doc_backups_prune_next, which returns nothing in dry run. This is retention of the table
//     exports only; op pdpl_erase stays refused.
//   * v10 (15 Sep 2026, it_engineer): a queue run that dies on a database wait (statement/lock timeout,
//     deadlock; measured 06:39-06:41Z during two migration applies, picker 4.2 ms on its own) hands on to
//     the next link, still capped at 20; a mark-done write that times out is retried twice, and if it
//     still fails is logged 'warn' (the copy is verified in Dropbox), so fn_backup_watch does not read
//     it as a failed backup.
//   * v11 (15 Sep 2026, it_engineer): the access token is shared across runs in app_secrets and
//     refreshed by one run at a time (dropbox.ts v2); a throttled or failed token call is retried and
//     never marks a document failed as no_dropbox_auth; rows a run claimed and never reached are
//     released at once (drain.ts). Measured 07:20-07:24Z: every run refreshed, two runs got a refused
//     refresh and left 24 + 7 rows 'processing' for 10 minutes.
// SQL: scripts/sql/a_document_reaches_dropbox_when_it_lands_and_only_once_it_exists.sql and
// scripts/sql/dropbox_is_checked_every_day_login_and_space.sql.
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
import { AuthUnavailable, DropboxClient, isAuthStop, refreshAccessToken, TokenCache, type TokenStore } from './dropbox.ts';
import { drainClaim } from './drain.ts';
import { uploadFile, type ReadChunk, type UploadState } from './upload.ts';
import { backupRow, dbxMeta, verifyUploaded } from './row.ts';
import { demoPurgeDeleteAllowed, signupPurgeDeleteAllowed } from './purge.ts';
import { compareListing, dailyRoots, fileSlices, listTree, type Expected } from './listing.ts';
import { dropboxExportAllowed } from '../_shared/backup_prune_allow.ts';
import { classifyDropboxFailure, isTransientDbError } from './health.ts';
import { J } from '../_shared/json_response.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const T0 = Date.now();
const DEADLINE = T0 + 110_000;           // leave room under the 150 s edge limit to record the result
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SELF = SUPABASE_URL + '/functions/v1/dropbox_backup';
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

// v11: the access token is shared by every run through app_secrets (dropbox.ts TokenCache). The
// compare-and-set on the row's updated_at is the single-flight guard: an update that names the old
// stamp changes one row or none. The filter carries only the stamp - the token goes in the request
// body, never in the URL. fn_security_audit redacts app_secrets values in security_audit_log.
const TOKEN_KEY = 'dropbox_access_token';
const tokenStore: TokenStore = {
  async get() {
    const { data, error } = await admin.from('app_secrets').select('value,updated_at').eq('key', TOKEN_KEY).maybeSingle();
    if (error) throw new Error('app_secrets read ' + error.message.slice(0, 120));
    if (!data) return { value: null, stamp: null };
    return { value: String(data.value ?? ''), stamp: String(data.updated_at ?? '') };
  },
  async cas(prev, next) {
    if (prev === null) {
      const { data, error } = await admin.from('app_secrets').insert({ key: TOKEN_KEY, value: next }).select('updated_at').single();
      if (error?.code === '23505') return null;
      if (error) throw new Error('app_secrets insert ' + error.message.slice(0, 120));
      return String(data.updated_at);
    }
    // the new stamp always differs from the old one, even inside one millisecond
    const stamp = new Date(Math.max(Date.now(), (Date.parse(prev) || 0) + 1)).toISOString();
    const { data, error } = await admin.from('app_secrets').update({ value: next, updated_at: stamp })
      .eq('key', TOKEN_KEY).eq('updated_at', prev).select('updated_at');
    if (error) throw new Error('app_secrets update ' + error.message.slice(0, 120));
    return data?.length === 1 ? String(data[0].updated_at) : null;
  },
};
function client(): DropboxClient {
  return new DropboxClient(new TokenCache(tokenStore, async () => {
    const [rt, key, secret] = await Promise.all([sec('dropbox_refresh_token'), sec('dropbox_app_key'), sec('dropbox_app_secret')]);
    return refreshAccessToken(rt, key, secret);
  }, { deadline: DEADLINE }));
}

// THE DAILY CHECK (it_engineer). v6/v7: the sample (new, unverified rows; a weekly random sample).
// v12 (7 Oct 2026, founder gate ledger 1162): plus the WHOLE listing (listing.ts), so a copy deleted
// or changed in Dropbox is found the next day, not by a 20-in-24,156 weekly draw. A listing finding
// goes through the same fn_dropbox_reconcile_apply hand-over as a sample finding.
async function reconcile(dbx: DropboxClient, n: number, ids?: number[]) {
  const { data: rows, error } = ids?.length
    ? await admin.from('doc_backups').select('id,dropbox_path,bucket,path,bytes,dropbox_content_hash').in('id', ids)
    : await admin.rpc('fn_dropbox_reconcile_sample', { p_n: n });
  if (error) throw new Error('sample ' + error.message);
  const results: Record<string, unknown>[] = [];
  // deno-lint-ignore no-explicit-any
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
  let listing: Record<string, unknown> | null = null;
  if (!ids?.length) {
    try {
      const l = await listingCheck(dbx, await dailyRoots(dbx), T0 + LISTING_BUDGET_MS, true);
      const seen = new Set(results.map((r) => Number(r.id)));
      for (const f of l.findings) if (!seen.has(Number(f.id))) results.push(f);
      listing = l.summary;
    } catch (e) { listing = { error: errText(e).slice(0, 200), unlisted_roots: 1 }; }
    const { error: le } = await admin.rpc('fn_it_backup_listing_record', { p_summary: listing });
    if (le) console.error('fn_it_backup_listing_record failed:', le.message);
  }
  const { data: applied, error: aerr } = ids?.length
    ? await admin.rpc('fn_it_backup_check', { p_results: results, p_job: 'targeted' })
    : await admin.rpc('fn_dropbox_reconcile_apply', { p_results: results });
  if (aerr) throw new Error('apply ' + aerr.message);
  return ids?.length ? applied : { applied, listing };
}

// resilience_ping waits 55 s for the reconcile call; the listing stops in time to report.
const LISTING_BUDGET_MS = 40_000;
const CONFIRM_MAX = 25;

// List each root, compare with doc_backups, and confirm every "missing" one by one with get_metadata
// (at most CONFIRM_MAX a run; the rest are counted and re-read the next day). A root the budget cut
// short is not compared at all. Returns the confirmed findings in fn_it_backup_check's shape.
async function listingCheck(dbx: DropboxClient, roots: string[], deadline: number, refreshFiles = false) {
  const summary = { roots: roots.length, unlisted_roots: 0, expected: 0, listed: 0, missing: 0, confirmed_missing: 0, changed: 0, stray: 0, files_refreshed: 0, files_removed: 0 };
  const stamp = new Date().toISOString();
  const findings: Record<string, unknown>[] = [];
  for (const root of roots) {
    if (Date.now() >= deadline) { summary.unlisted_roots++; continue; }
    const t = await listTree(dbx, root, deadline);
    if (!t.complete) { summary.unlisted_roots++; continue; }
    // public.dropbox_files follows the same complete walk (a root cut short is left as it was)
    if (refreshFiles) for (const sl of fileSlices(t.entries)) {
      const { data: fr, error: fe } = await admin.rpc('fn_dropbox_files_refresh', { p_root: root, p_rows: sl.rows, p_stamp: stamp, p_final: sl.final });
      if (fe) throw new Error('fn_dropbox_files_refresh ' + fe.message);
      summary.files_refreshed += Number(fr?.upserted || 0); summary.files_removed += Number(fr?.removed || 0);
    }
    const { data: exp, error } = await admin.rpc('fn_it_backup_listing_expected', { p_root: root });
    if (error) throw new Error('fn_it_backup_listing_expected ' + error.message);
    const c = compareListing((exp || []) as Expected[], t.entries);
    summary.expected += c.expected; summary.listed += c.listed; summary.stray += c.stray;
    summary.missing += c.missing.length; summary.changed += c.changed.length;
    for (const ch of c.changed) findings.push({ id: ch.id, outcome: 'changed', hash: ch.hash, size: ch.size, why: 'listing' });
    const byId = new Map(((exp || []) as Expected[]).map((e) => [e[0], e[1]]));
    for (const id of c.missing) {
      if (summary.confirmed_missing >= CONFIRM_MAX || Date.now() >= deadline + 10_000) break;
      const m = await dbxMeta(dbx, String(byId.get(id)));
      if (m.missing) { summary.confirmed_missing++; findings.push({ id, outcome: 'missing', why: 'listing' }); }
    }
  }
  return { summary, findings };
}

// ── THE TAGGED SANDBOX RUN (sales_engineer files, it_engineer verifies; ZZ DEMO data only) ──
// Rows come only from fn_doc_backups_sandbox_next (entity 'zz_demo', key SBX:<tag>:, path under
// /QuotesDone Backup/_sandbox/<tag>/); every row goes through backupRow exactly as the queue's do.
const SANDBOX_TAG = /^[A-Za-z0-9-]{6,40}$/;
const sandboxRoot = (tag: string) => '/QuotesDone Backup/_sandbox/' + tag;
async function sandboxUpload(tag: string, failIds: number[]) {
  const dbx = await client();
  const run = `dropbox_sandbox:${tag}:${T0}`;
  const out: Record<string, unknown>[] = []; let failed = 0, done = 0;
  for (let pass = 0; pass < 10 && Date.now() < DEADLINE; pass++) {
    const { data: rows, error } = await admin.rpc('fn_doc_backups_sandbox_next', { p_tag: tag, p_limit: 25, p_run: run });
    if (error) throw new Error('fn_doc_backups_sandbox_next: ' + error.message);
    // deno-lint-ignore no-explicit-any
    const claimed = (rows || []) as any[];
    if (!claimed.length) break;
    const d = await drainClaim(claimed, { deadline: DEADLINE,
      fail: async (row, msg) => {
        await admin.from('doc_backups').update({ status: 'error', claimed_at: null, claimed_by: null, error: msg, attempts: row.attempts + 1, last_attempt_at: new Date().toISOString(), upload_state: null }).eq('id', row.id).eq('status', 'processing');
        out.push({ id: row.id, error: msg.slice(0, 160) });
      },
      requeue: async (row, msg) => { await admin.from('doc_backups').update({ status: 'pending', claimed_at: null, claimed_by: null, error: 'requeued: ' + msg.slice(0, 200) }).eq('id', row.id); },
      release: async (ids) => { const { data } = await admin.from('doc_backups').update({ status: 'pending', claimed_at: null, claimed_by: null }).in('id', ids).eq('claimed_by', run).select('id'); return data?.length ?? 0; },
      process: async (row) => {
        // the retry test: a named row fails on its FIRST attempt only, as a provider outage would
        const r = await backupRow(admin, dbx, row, { supabaseUrl: SUPABASE_URL, deadline: DEADLINE, release: { claimed_at: null, claimed_by: null },
          simulateFailure: failIds.includes(Number(row.id)) && Number(row.attempts) === 0, logRun });
        if ('done' in r) done++;
        out.push({ id: row.id, ...r });
      },
    });
    failed += d.failed;
  }
  return { tag, done, failed, results: out };
}

// The same listing check the daily duty runs, on the sandbox folder only. Findings are returned, not
// handed over: a demo file never opens a refile for the sales engineer.
async function sandboxVerify(tag: string) {
  const dbx = await client();
  return await listingCheck(dbx, [sandboxRoot(tag)], Date.now() + 30_000);
}

// Remove the sandbox folder of ONE tag from Dropbox; the path is built here, never taken from the caller.
async function sandboxCleanup(tag: string) {
  const dbx = await client();
  const root = sandboxRoot(tag);
  const r = await dbx.call('api', 'files/delete_v2', { path: root });
  const t = await r.text();
  if (!r.ok && !(r.status === 409 && t.includes('not_found'))) throw new Error('delete_v2 ' + r.status + ' ' + t.slice(0, 160));
  const gone = await dbx.call('api', 'files/get_metadata', { path: root });
  const gt = await gone.text();
  return { tag, deleted: r.ok, folder_gone: gone.status === 409 && gt.includes('not_found') };
}

// it_engineer: the daily login check, write/read/delete probe in /_selftest/, and space reading.
// Every stage is recorded, never thrown away; a failure carries its class (health.ts). The space is
// read even when the probe failed, so a full account is measured on the day it stops the writes.
async function health() {
  const out: Record<string, unknown> = { auth_ok: false, write_ok: false, read_ok: false, delete_ok: false };
  let dbx: DropboxClient | null = null;
  try {
    dbx = await client();
    const probe = `/QuotesDone Backup/_selftest/auth_probe_${Date.now()}.txt`;
    const bytes = new TextEncoder().encode('quotesdone dropbox auth probe ' + new Date().toISOString());
    const up = await uploadFile(dbx, probe, bytes.length, (o, n) => Promise.resolve(bytes.slice(o, o + n)));
    out.auth_ok = true; out.write_ok = up.done;
    if (!up.done) throw new Error('probe upload did not finish');
    await verifyUploaded(dbx, probe, up.hash, bytes.length); out.read_ok = true;
    const d = await dbx.call('api', 'files/delete_v2', { path: probe });
    if (!d.ok) throw new Error('delete_v2 ' + d.status + ' ' + (await d.text()).slice(0, 160));
    await d.body?.cancel(); out.delete_ok = true;
  } catch (e) { out.error = errText(e).slice(0, 300); }
  if (dbx) {
    try {
      const s = await dbx.call('api', 'users/get_space_usage', null);
      if (!s.ok) throw new Error('get_space_usage ' + s.status + ' ' + (await s.text()).slice(0, 160));
      const sj = await s.json();
      out.used = Number(sj.used); out.allocated = Number(sj.allocation?.allocated ?? 0);
      const a = await dbx.call('api', 'users/get_current_account', null);
      out.plan = a.ok ? String((await a.json()).account_type?.['.tag'] || '') : 'unknown';
      if (!a.ok) await a.body?.cancel();
      out.refreshes = dbx.refreshes;
    } catch (e) { out.space_error = errText(e).slice(0, 300); }
  }
  if (out.error) out.class = classifyDropboxFailure(String(out.error));
  if (out.space_error) out.space_class = classifyDropboxFailure(String(out.space_error));
  const { data, error } = await admin.rpc('fn_it_dropbox_health_record', { p: out });
  if (error) throw new Error('fn_it_dropbox_health_record: ' + error.message);
  return { reading: out, recorded: data };
}

async function dbxDelete(dbx: DropboxClient, path: string): Promise<boolean> {
  const r = await dbx.call('api', 'files/delete_v2', { path }); await r.body?.cancel(); return r.ok;
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

// it_engineer (retention): delete the claimed rows' dropbox_path. A path already gone is an answer.
async function prune() {
  const run = `dropbox_prune:${T0}:${crypto.randomUUID().slice(0, 8)}`;
  const { data: rows, error } = await admin.rpc('fn_doc_backups_prune_next', { p_limit: 25, p_run: run });
  if (error) throw new Error('fn_doc_backups_prune_next: ' + error.message);
  if (!rows?.length) return { claimed: 0 };
  const dbx = await client();
  const results: Record<string, unknown>[] = [];
  // deno-lint-ignore no-explicit-any
  for (const row of rows as any[]) {
    if (Date.now() >= DEADLINE) { results.push({ id: row.id, ok: false, error: 'deadline' }); continue; }
    // the allow-list again, here: only a table-export file is ever deleted from Dropbox (counted as a
    // failure, so five refusals become an it_engineer finding)
    if (!dropboxExportAllowed(row)) { results.push({ id: row.id, ok: false, error: 'refused by the allow-list: not a table-export file' }); continue; }
    try {
      const r = await dbx.call('api', 'files/delete_v2', { path: row.dropbox_path });
      const t = await r.text();
      if (r.ok || (r.status === 409 && t.includes('not_found'))) results.push({ id: row.id, ok: true, already_gone: !r.ok });
      else results.push({ id: row.id, ok: false, error: `delete_v2 ${r.status} ${t.slice(0, 160)}` });
    } catch (e) { results.push({ id: row.id, ok: false, error: errText(e).slice(0, 200) }); }
  }
  const { data, error: de } = await admin.rpc('fn_doc_backups_prune_done', { p_results: results });
  if (de) throw new Error('fn_doc_backups_prune_done: ' + de.message);
  return { claimed: rows.length, result: data };
}

// it_engineer (founder ruling 1181, 12 Oct 2026): what fn_unfinished_signup_purge listed for a sign-up it removed is
// deleted, "as if he didn't even try": each Dropbox copy in signup_purge_dropbox (only inside the entity tree,
// signupPurgeDeleteAllowed), then its backup record; each storage object in signup_purge_object through the storage
// API. A copy already gone is an answer. Counts only are logged (agent_actions), never a name or a file.
async function purgeUnfinishedSignups(dbx: DropboxClient) {
  const out = { dropbox_deleted: 0, dropbox_already_gone: 0, dropbox_refused: 0, dropbox_failed: 0, records_deleted: 0, storage_removed: 0, storage_failed: 0 };
  // listed at least 15 minutes ago (an upload claimed before the purge has finished: claims expire after 10 minutes and a
  // run ends within 2), fewer than 5 attempts, never refused: a bad row cannot block the rows behind it
  const { data: copies } = await admin.from('signup_purge_dropbox').select('id,doc_backup_id,dropbox_file,attempts').is('done_at', null)
    .lt('attempts', 5).lt('listed_at', new Date(Date.now() - 15 * 60_000).toISOString()).order('attempts').order('id').limit(25);
  for (const c of copies || []) {
    if (Date.now() >= DEADLINE) break;
    if (!signupPurgeDeleteAllowed(String(c.dropbox_file)) && !demoPurgeDeleteAllowed(String(c.dropbox_file))) {
      out.dropbox_refused++;
      await admin.from('signup_purge_dropbox').update({ error: 'refused: not a file of the entity tree', attempts: 5 }).eq('id', c.id);
      continue;
    }
    try {
      const r = await dbx.call('api', 'files/delete_v2', { path: c.dropbox_file });
      const t = await r.text();
      const gone = r.status === 409 && t.includes('not_found');
      if (!r.ok && !gone) throw new Error('delete_v2 ' + r.status + ' ' + t.slice(0, 120));
      if (gone) out.dropbox_already_gone++; else out.dropbox_deleted++;
      // a whole demo folder (fn_demo_purge, ruling 1199) has no backup record of its own
      if (c.doc_backup_id != null) {
        const { data: del } = await admin.from('doc_backups').delete().eq('id', c.doc_backup_id).eq('status', 'signup_purge_pending').select('id');
        out.records_deleted += del?.length ?? 0;
      }
      await admin.from('signup_purge_dropbox').update({ done_at: new Date().toISOString(), error: null }).eq('id', c.id);
    } catch (e) {
      out.dropbox_failed++;
      await admin.from('signup_purge_dropbox').update({ error: 'attempt ' + (Number(c.attempts) + 1) + ': ' + errText(e).slice(0, 200), attempts: Number(c.attempts) + 1 }).eq('id', c.id);
    }
  }
  const { data: objs } = await admin.from('signup_purge_object').select('id,bucket,path').is('done_at', null).order('id').limit(50);
  for (const o of objs || []) {
    const { error } = await admin.storage.from(o.bucket).remove([o.path]);
    if (error) { out.storage_failed++; await admin.from('signup_purge_object').update({ error: error.message.slice(0, 200) }).eq('id', o.id); continue; }
    await admin.from('signup_purge_object').update({ done_at: new Date().toISOString(), error: null }).eq('id', o.id);
    out.storage_removed++;
  }
  if (Object.values(out).some((n) => n > 0)) {
    await admin.from('agent_actions').insert({ agent: 'it_engineer', kind: 'signup_purge', status: 'done', risk: 'low',
      title: 'Unfinished sign-up files deleted (founder ruling 1181)', detail: out, decided_at: new Date().toISOString(), decided_by: 'it_engineer' });
  }
  return out;
}

Deno.serve(observe('dropbox_backup', async (req) => {
  // deno-lint-ignore no-explicit-any
  let body: Record<string, any> = {}; let authed = false;
  try {
    body = await req.json().catch(() => ({} as Record<string, unknown>));
    const auth = await requireInternal(admin, body?.__secret, 'dropbox_backup');
    if (!auth.ok) { await logThrottled('forbidden', 60, 'error', { stage: 'auth' }, 'dropbox_backup rejected a caller presenting a bad or missing inbound secret. If this is the scheduled caller, no Dropbox backup is running at all and every backup is stale.'); return J({ error: 'forbidden' }, 403); }

    authed = true;
    if (body.op === 'health') return J({ ok: true, op: 'health', ...(await health()) });
    if (body.op === 'prune') return J({ ok: true, op: 'prune', ...(await prune()) });
    if (body.op === 'selftest_large') return J({ ok: true, op: 'selftest_large', ...(await selftestLarge(Number(body.mb) || 20)) });
    if (body.op === 'pdpl_erase') {
      await logRun('error', { stage: 'pdpl_erase_refused', request_id: String(body.request_id || '') },
        'A PDPL file-erasure was requested from dropbox_backup and REFUSED. This function is an add-only backup and its delete path is disabled, so no file was removed from Dropbox or storage and no pdpl_erase_files row was marked erased. The erasure request is still outstanding and needs an owner who will re-enable this deliberately.');
      return J({ ok: false, error: 'deletion_disabled', message: 'dropbox_backup is an add-only backup. It does not delete from Dropbox or storage. Nothing was erased and no row was marked erased.' }, 409);
    }
    // the tagged sandbox run (ZZ DEMO only; every path is built here from the validated tag)
    if (body.op === 'sandbox' || body.op === 'sandbox_verify' || body.op === 'sandbox_cleanup') {
      const tag = String(body.tag || '');
      if (!SANDBOX_TAG.test(tag)) return J({ ok: false, error: 'bad_tag' }, 400);
      if (body.op === 'sandbox') return J({ ok: true, op: 'sandbox', ...(await sandboxUpload(tag, Array.isArray(body.fail_ids) ? body.fail_ids.map(Number) : [])) });
      if (body.op === 'sandbox_verify') return J({ ok: true, op: 'sandbox_verify', ...(await sandboxVerify(tag)) });
      return J({ ok: true, op: 'sandbox_cleanup', ...(await sandboxCleanup(tag)) });
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
    let enqueued = 0, backfilled = 0;
    if (body.mode !== 'process_only') {
      // New documents first, on a statement of their own (owner rules only). The backfill (storage sweep,
      // pre-7-Sep exports) is a SECOND statement with its own 8 s: on 15 Sep 2026 the two ran as one call,
      // took 50 s and every new document stopped being queued. Each outcome raises or closes an
      // it_engineer finding (duty:backup_enqueue_<stage>:failing), so a failure is not only a throttled log.
      const { data, error } = await admin.rpc('fn_enqueue_doc_backups'); enqueued = Number(data) || 0;
      if (error) await logThrottled('enqueue_failed', 60, 'error', { stage: 'enqueue' }, 'fn_enqueue_doc_backups failed, so no new documents are being queued for Dropbox backup. ' + error.message.slice(0, 160));
      const bf = await admin.rpc('fn_enqueue_doc_backups_backfill'); backfilled = Number(bf.data) || 0;
      if (bf.error) await logThrottled('backfill_failed', 60, 'error', { stage: 'backfill' }, 'fn_enqueue_doc_backups_backfill failed; new documents are still queued, the storage sweep and pre-7-Sep exports are not. ' + bf.error.message.slice(0, 160));
      for (const [stage, e] of [['new_documents', error], ['backfill', bf.error]] as const) {
        const { error: oe } = await admin.rpc('fn_backup_enqueue_outcome', { p_stage: stage, p_error: e ? e.message.slice(0, 500) : null });
        if (oe) console.error('fn_backup_enqueue_outcome(' + stage + ') failed:', oe.message);
      }
    }
    const dbx = await client();
    // Take the token BEFORE claiming rows: when the token endpoint is throttled or down, nothing is
    // claimed, nothing is marked failed and no link is chained. A refusal ('no_dropbox_auth') is not
    // caught here: the first row then fails loudly exactly as before.
    try { await dbx.tokens.token(); } catch (e) {
      if (e instanceof AuthUnavailable) {
        await logRun('warn', { stage: 'token', enqueued, chain, refreshes: dbx.refreshes, token_reused: dbx.tokens.reused, reason: body.reason ?? null, class: classifyDropboxFailure(errText(e)) },
          'The Dropbox token endpoint did not answer usefully (' + errText(e).slice(0, 160) + '); no document was claimed or marked failed. The next scheduled run retries.');
        // 200, not 503 (9 Nov 2026: 73 of 619 runs showed as server errors during a passing Dropbox token outage; nothing
        // is claimed and the next run retries). Still visible: the 'warn' run above, the daily health probe (fn_it_dropbox_health_record)
        // and fn_backup_coverage, which raises when a queued row is not done after 48 h, so a sustained outage is not hidden.
        return J({ ok: false, status: 'skipped_token_unavailable', error: 'dropbox_token_unavailable', enqueued }, 200);
      }
      if (!isAuthStop(e)) throw e;     // 'no_dropbox_auth' falls through: the first row fails loudly as before
    }
    // an unfinished sign-up's files (founder ruling 1181): its listed Dropbox copies, records and storage objects deleted
    let unfinished: Record<string, number> | null = null;
    if (!chain) { try { unfinished = await purgeUnfinishedSignups(dbx); } catch (e) { console.error('unfinished sign-up purge failed:', errText(e)); } }
    const run = `dropbox_backup:${T0}:${crypto.randomUUID().slice(0, 8)}`;
    const { data: rows, error: qerr } = await admin.rpc('fn_doc_backups_next', { p_limit: limit, p_run: run });
    if (qerr) throw new Error('fn_doc_backups_next: ' + qerr.message);

    let done = 0, resumed = 0; const results: Record<string, unknown>[] = [];
    const now = () => new Date().toISOString();
    const release = { claimed_at: null, claimed_by: null };
    // deno-lint-ignore no-explicit-any
    const claimed = (rows || []) as any[];
    // drain.ts: a run that stops early (deadline, token endpoint unavailable, no_dropbox_auth) hands the
    // rows it never reached back to pending at once, instead of after the 10-minute claim expiry.
    const d = await drainClaim(claimed, { deadline: DEADLINE,
      fail: async (row, msg) => {
        await admin.from('doc_backups').update({ status: 'error', ...release, error: msg, attempts: row.attempts + 1, last_attempt_at: now(), upload_state: null }).eq('id', row.id).eq('status', 'processing');
        results.push({ id: row.id, error: msg.slice(0, 160) });
      },
      // provider-side and passing: attempts unchanged; upload_state cleared because chunks may have been
      // appended since the stored offset
      requeue: async (row, msg) => {
        await admin.from('doc_backups').update({ status: 'pending', ...release, upload_state: null, error: 'requeued: ' + msg.slice(0, 200) })
          .eq('id', row.id).eq('claimed_by', run);
        results.push({ id: row.id, requeued: 'token_unavailable' });
      },
      release: async (ids) => {
        const { data: rel, error: rerr } = await admin.from('doc_backups').update({ status: 'pending', ...release })
          .in('id', ids).eq('status', 'processing').eq('claimed_by', run).select('id');
        if (rerr) console.error('release of unreached claims failed (they requeue after 10 minutes):', rerr.message);
        return rel?.length ?? 0;
      },
      process: async (row) => {
        const r = await backupRow(admin, dbx, row, { supabaseUrl: SUPABASE_URL, deadline: DEADLINE, release, logRun });
        if ('resuming' in r) resumed++;
        if ('done' in r) done++;
        results.push({ id: row.id, ...r });
      },
    });
    const { failed, released, authUnavailable, notes: errNotes } = d;
    const processed = claimed.length;
    const counts = { enqueued, backfilled, unfinished, processed, done, failed, resumed, released, chain, refreshes: dbx.refreshes, token_reused: dbx.tokens.reused,
      ...(authUnavailable ? { token_unavailable: classifyDropboxFailure(authUnavailable) } : {}), reason: body.reason ?? null };
    if (processed || enqueued || backfilled || failed) {
      if (failed) await logRun('error', counts, 'Dropbox backup finished with ' + failed + ' failed document(s) out of ' + processed + '; the IT engineer classifies and fixes them. ' + errNotes.join(' | '));
      else if (authUnavailable) await logRun('warn', counts, 'Dropbox backup uploaded ' + done + ' document(s), then the Dropbox token endpoint did not answer usefully (' + authUnavailable.slice(0, 160) + '); ' + released + ' document(s) returned to the queue unchanged, none marked failed.');
      else await logRun('ok', counts, 'Dropbox backup uploaded ' + done + ' document(s)' + (resumed ? ', ' + resumed + ' large file(s) resume next run' : '') + '.');
    }
    // The batch was full: there is probably more. Drain it now instead of at the next tick. Not while
    // the token endpoint is refusing to answer: the next scheduled run retries.
    if ((processed === limit || resumed > 0) && chain < 20 && failed < processed && !authUnavailable) {
      const next = fetch(SELF, { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ __secret: body.__secret, mode: 'process_only', limit, chain: chain + 1, reason: 'drain' }) })
        .then((r) => r.body?.cancel()).catch((e) => console.error('drain link failed:', errText(e)));
      // deno-lint-ignore no-explicit-any
      (globalThis as any).EdgeRuntime?.waitUntil?.(next);
    }
    return J({ ok: true, ...counts, results });
  } catch (e) {
    const msg = errText(e);
    // A queue run that died waiting on our own database hands on to the next link instead of ending
    // the drain: the same call succeeds seconds later. Bounded like the drain itself (chain < 20), and
    // only for a transient wait - any other fatal error would fail the same way twenty times.
    const chain = Math.max(0, Math.min(Number(body.chain) || 0, 20));
    const handOff = authed && body.op === undefined && body.mode !== 'reconcile' && chain < 20 && isTransientDbError(msg);
    await logRun('error', { stage: 'fatal', chain, handed_off: handOff }, 'dropbox_backup crashed before completing; this run backed nothing up' + (handOff ? ' (a database wait timed out; the next link retries)' : '') + '. ' + msg.slice(0, 200));
    if (handOff) {
      const next = fetch(SELF, { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ __secret: body.__secret, mode: 'process_only', limit: Math.min(Number(body.limit) || 8, 25), chain: chain + 1, reason: 'drain_after_db_timeout' }) })
        .then((r) => r.body?.cancel()).catch((err) => console.error('drain link failed:', errText(err)));
      // deno-lint-ignore no-explicit-any
      (globalThis as any).EdgeRuntime?.waitUntil?.(next);
    }
    return J({ error: msg }, 500);
  }
}));
