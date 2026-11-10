// resilience_ping ticks owned by the it_engineer seat: dropbox, Vercel-configuration and table-export backup ticks. Moved out of ticks/it_engineer.ts unchanged (9 Nov 2026);
// the order the steps run in is still set in resilience_ping/index.ts (STEP_RUN).
import { httpHopError } from '../../steps.ts';
import { envCoverage as vercelEnvCoverage, snapshot as vercelSnapshot } from '../../../_shared/vercel_snapshot.ts';
import { FN, GATEWAY, admin, sec } from '../../shared.ts';

// The IT engineer's half of the backup (founder, 14 Sep 2026: "i think the IT agent need to check
// such details yea?"): close verified refiles, run the 48-hour coverage watch, file the daily line
// to the CEO, and once a Dubai week re-check a random sample of Dropbox files.
// deno-lint-ignore no-explicit-any
export async function dropboxVerifyTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_it_backup_tick');
    if (error) return { ok: false, error: error.message };
    // deno-lint-ignore no-explicit-any
    if (!(data as any)?.reconcile?.due) return data;
    const secret = await sec('cred_fn_resilience_ping');
    const r = await fetch(FN + '/dropbox_backup', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: secret, mode: 'reconcile', limit: 20 }), signal: AbortSignal.timeout(55000),
    });
    const reconcile_run = { status: r.status, result: await r.json().catch(() => null) };
    // deno-lint-ignore no-explicit-any
    return { ...(data as any), reconcile_run, ...(r.ok ? {} : { ok: false, error: httpHopError('dropbox_backup reconcile', r.status, reconcile_run.result) }) };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// DROPBOX IS CHECKED EVERY DAY (it_engineer, 15 Sep 2026): the login, a write/read/delete probe and
// the space used, once a Dubai day and two hours after a failed reading (fn_it_dropbox_health_due).
// Its own tick, never behind fn_it_backup_tick, so neither can stop the other. dropbox_backup records
// the reading itself; if the call never got that far (timeout, a 5xx from our own function), this
// records it as an internal failure so a silent probe is still a finding. Only the verdict comes back:
// this endpoint is public.
// THE VERCEL CONFIGURATION, ONCE A DAY (it_engineer, 12 Oct 2026; the_vercel_configuration_is_backed_up_every_day.sql).
// Read only: the project, its domains, its env var NAMES (never decrypted, and vercel_snapshot.ts drops every value
// again) and its crons. The JSON goes to the private backups bucket and is filed for Dropbox under Company/Vercel/.
// The env vars the site reads are the names in the site's own code (src/: process.env.*), listed here.
// 27 Oct 2026: the site reads the new keys first (NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, SUPABASE_SECRET_KEY) and the legacy
// ones only as the temporary fallback; drop the two legacy names with that fallback.
const SITE_ENV_NAMES = ['CRON_SECRET', 'NEXT_PUBLIC_SUPABASE_ANON_KEY', 'NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY', 'NEXT_PUBLIC_SUPABASE_URL', 'SITE_ERROR_INGEST_SECRET', 'SUPABASE_SECRET_KEY', 'SUPABASE_SERVICE_ROLE_KEY'];
export async function vercelSnapshotTick(): Promise<unknown> {
  try {
    const [token, pid, team] = await Promise.all([sec('vercel_token'), sec('vercel_project_id'), sec('vercel_team_id')]);
    if (!token || !pid) return { ok: false, error: 'vercel_token or vercel_project_id is not in app_secrets' };
    const q = team ? `?teamId=${encodeURIComponent(team)}` : '';
    const get = async (p: string) => {
      const r = await fetch('https://api.vercel.com' + p + q, { headers: { Authorization: 'Bearer ' + token }, signal: AbortSignal.timeout(15000) });
      if (!r.ok) throw new Error('vercel ' + p.split('/').slice(0, 3).join('/') + ' ' + r.status);
      return await r.json();
    };
    const [project, domains, env] = await Promise.all([get(`/v9/projects/${pid}`), get(`/v9/projects/${pid}/domains`), get(`/v10/projects/${pid}/env`)]);
    const day = new Date().toISOString().slice(0, 10);
    const snap = vercelSnapshot(project, domains, env, new Date().toISOString());
    const { data: keys } = await admin.from('app_secrets').select('key');
    const cov = vercelEnvCoverage(SITE_ENV_NAMES, snap.env, (keys || []).map((k: { key: string }) => k.key));
    const path = `engineering/vercel/${day}.json`;
    const up = await admin.storage.from('backups').upload(path, new TextEncoder().encode(JSON.stringify({ ...snap, env_sources: cov.sources }, null, 1)),
      { contentType: 'application/json', upsert: true });
    if (up.error) return { ok: false, error: 'backups upload ' + up.error.message };
    const summary = { domains: snap.domains.length, env_names: snap.env.length, missing_in_vercel: cov.missing_in_vercel, no_recoverable_source: cov.no_recoverable_source };
    const { error } = await admin.rpc('fn_vercel_snapshot_filed', { p_path: path, p_summary: summary });
    if (error) return { ok: false, error: error.message };
    return { ok: true, path, ...summary };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e).slice(0, 200) }; }
}

export async function dropboxHealthTick(): Promise<unknown> {
  try {
    const { data: due, error } = await admin.rpc('fn_it_dropbox_health_due');
    if (error) return { ok: false, error: error.message };
    if (due !== true) return { due: false };
    let status = 0; let recorded: string | null = null; let why = '';
    try {
      const r = await fetch(FN + '/dropbox_backup', {
        method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
        body: JSON.stringify({ __secret: await sec('cred_fn_resilience_ping'), op: 'health' }), signal: AbortSignal.timeout(55000),
      });
      status = r.status;
      // deno-lint-ignore no-explicit-any
      const j: any = await r.json().catch(() => null);
      recorded = j?.recorded?.status ?? null;
      if (!recorded) why = 'dropbox_backup op health answered ' + r.status + ' ' + String(j?.error ?? '').slice(0, 200);
    } catch (e) { why = 'dropbox_backup op health did not answer: ' + String((e as Error)?.message || e).slice(0, 200); }
    if (!recorded) {
      const { data: rec, error: re } = await admin.rpc('fn_it_dropbox_health_record', { p: { error: why, class: 'internal' } });
      if (re) return { due: true, status, ok: false, error: re.message };
      // deno-lint-ignore no-explicit-any
      recorded = (rec as any)?.status ?? null;
    }
    return { due: true, status, recorded };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

export async function backupTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_dropbox_backup_due');
    if (error) return { ok: false, error: error.message };
    if (!(data as any)?.due) return { due: false, ran_today: (data as any)?.ran_today, queued: (data as any)?.queued };
    const secret = await sec('cred_fn_resilience_ping');
    // STARTED, NOT AWAITED (18 Sep 2026, it_engineer) — the same shape as tableExportTick above, and for
    // the same reason. dropbox_backup v8 "calls itself again (process_only, up to 20 links) so a backlog
    // drains without waiting for the next tick": the chain runs in its OWN invocations whatever this tick
    // does, so awaiting the first pass bought nothing and cost everything. Measured 18 Sep: 2,006
    // documents queued, dropbox_backup averaging 33.8 s a call over 306 calls in 6 hours — of which only
    // ~4 an hour are this step; the rest are the chain draining itself. Awaiting it was ~25 s of a 110 s
    // tick spent watching a worker that did not need watching, and it is where the finding
    // duty:heartbeat:backup, "Signal timed out", seen 34 times by 07:17Z, came from: the 55 s timeout
    // fired on a pass that was working perfectly.
    // The pass still reports itself — dropbox_backup writes its own agent_runs rows, fn_it_backup_tick
    // and fn_dropbox_backup_due both read them, so a chain that stops is still a finding.
    const started = fetch(FN + '/dropbox_backup', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: secret, limit: 25 }),
    }).then((r) => r.body?.cancel()).catch(() => {});
    // deno-lint-ignore no-explicit-any
    (globalThis as any).EdgeRuntime?.waitUntil?.(started);
    return { due: true, started: true, queued: (data as any)?.queued };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}


// THE DAILY TABLE EXPORT HANGS HERE, FOR THE SAME REASON AS THE DROPBOX BACKUP (14 Sep 2026).
// Its pg_cron job (109) went on 7 Sep and its worker (supabase/functions/backup) on 8 Sep; the last
// export in the backups bucket is 2026-09-07. fn_table_export_due claims the Asia/Dubai day once
// after 03:00, resumes a chain whose heartbeat stopped, and retries a failed day. The chain runs on
// in its own invocations, so this tick only starts it and does not wait for it. Public endpoint:
// counts and dates only.
export async function tableExportTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_table_export_due');
    if (error) return { ok: false, error: error.message };
    // deno-lint-ignore no-explicit-any
    const d = data as any;
    if (!d?.due) return { due: false, stamp: d?.stamp, status: d?.status ?? null };
    const secret = await sec('cred_fn_resilience_ping');
    const started = fetch(FN + '/backup', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: secret, stamp: d.stamp, kind: d.kind, since: d.since ?? null, state: d.resume ?? null }),
    }).then((r) => r.body?.cancel()).catch(() => {});
    // deno-lint-ignore no-explicit-any
    (globalThis as any).EdgeRuntime?.waitUntil?.(started);
    return { due: true, stamp: d.stamp, attempt: d.attempt, resumed: d.resume != null };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// BACKUP RETENTION (15 Sep 2026, it_engineer): 90 days for every export day, 12 months for Friday full
// copies. fn_backup_prune_tick runs its pass once per Dubai day after that day's export finished, and
// in dry-run mode (the default) only logs what it would delete. In delete mode the two workers below
// remove what it logged: backup op 'prune' (storage) and dropbox_backup op 'prune' (Dropbox). Public
// endpoint: counts only.
export async function backupPruneTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_backup_prune_tick');
    if (error) return { ok: false, error: error.message };
    // deno-lint-ignore no-explicit-any
    const d = data as any;
    const out: Record<string, unknown> = { mode: d?.mode, pass: d?.pass ?? null, storage_pending: d?.storage_pending,
                                           dropbox_pending: d?.dropbox_pending, findings: d?.findings };
    if (!d?.storage_pending && !d?.dropbox_pending) return out;
    const secret = await sec('cred_fn_resilience_ping');
    const call = async (fn: string) => {
      const r = await fetch(FN + '/' + fn, { method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
        body: JSON.stringify({ __secret: secret, op: 'prune' }), signal: AbortSignal.timeout(55000) });
      await r.body?.cancel().catch(() => {});
      return r.status;
    };
    if (d.storage_pending) out.storage_run = await call('backup').catch((e) => String((e as Error)?.message || e));
    if (d.dropbox_pending) out.dropbox_run = await call('dropbox_backup').catch((e) => String((e as Error)?.message || e));
    // A prune worker that answered 4xx/5xx or threw is a failed step, not a number in a field.
    const bad = [out.storage_run, out.dropbox_run].find((v) => typeof v === 'string' || (typeof v === 'number' && v >= 400));
    if (bad !== undefined) { out.ok = false; out.error = 'a prune worker answered ' + bad; }
    return out;
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}
