// backup v2 (14 Sep 2026, it_engineer) — the daily export of every business and knowledge table.
//
// WHY THIS FILE IS BACK. The 'backups' bucket holds a dated JSON export of the core tables for
// every day from 23 Jun to 7 Sep 2026 (<YYYY-MM-DD>/<table>/page_NNNN.json) and nothing since.
// Measured 14 Sep 2026 on production: the last export is 2026-09-07 03:30 UTC, written by pg_cron
// job 109 calling this function. pg_cron was emptied on 7 Sep at 17:51 UTC on the founder's
// instruction (cron.job holds one inactive row, wa_flush), and this function was deleted the next
// morning with 136 others by commit 182308b (#530), because no seat owned it then. Both removals were
// structural; neither was a decision to stop backing up the database. The founder, 14 Sep 2026:
// backups go to two places, the Supabase private 'backups' bucket and Dropbox, and "there is no
// reason for the loop of the back up to fail except literally a disconnection from dropbox and
// supabase for a server issue from their end".
//
// WHAT CHANGED FROM v1 (supabase/functions/backup at 182308b^):
//   * The table list lives in the database (fn_table_export_list), not in this file, so the IT
//     engineer's expected list and the writer read the same list.
//   * Rows are read through fn_table_export_page: keyset paging on the primary key (v1 used
//     .range() offsets and silently STOPPED at 200,000 rows — kb_chunks holds 2.6 M), demo rows
//     excluded, vector columns stripped.
//   * kb_chunks: a full copy on the days fn_table_export_due says 'full' (Fridays, and whenever no
//     full copy succeeded in the 7 days before); on 'incremental' days only the rows its change log
//     names since `since`. Measured: a full copy is ~2,616 pages of ~2.8 MB at ~1.25 s each, ~55
//     minutes, ~110 slices — so MAX_HOPS is sized for it.
//   * v1 caught a table's error, wrote -1 into the summary and still wrote an ok manifest. Now an
//     error fails the day: no _manifest.json is written, fn_table_export_finish records 'failed',
//     and the next heartbeat restarts the day (fn_table_export_due, at most 6 attempts). A missing
//     manifest is an expected item that never reaches Dropbox, so the IT engineer's backup watch
//     reports it.
//   * Every read and upload is retried three times with backoff before it counts as an error.
//   * After every slice the resume point is saved (fn_table_export_save). A chain whose next hop
//     never starts is resumed by the next heartbeat from the saved point, not restarted.
//   * No pg_cron: resilience_ping calls fn_table_export_due every 15 minutes and starts the chain.
//   * On success fn_table_export_finish checks every page is in storage and queues every file for
//     Dropbox through fn_enqueue_doc_backups (TABLE EXPORTS), filed under
//     /QuotesDone Backup/Company/Database Exports/<YYYY-MM>/<YYYY-MM-DD>/.
// The layout in the bucket is unchanged, so the monthly restore drill (PR #661) reads these files.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { exportPathAllowed } from '../_shared/backup_prune_allow.ts';
import { type Deps, ExportError, HOP_BYTES, type HopState, leftoverFailure, retry, runHop } from '../_shared/table_export_core.ts';
// v3 (15 Sep 2026, it_engineer): the first full copy failed twice on kb_chunks/page_0103.json with
// "Forbidden" — the edge firewall refused a body holding OWASP injection examples; the request never
// reached storage (see _shared/table_export_core.ts). Now: every page is written with its risky
// characters as JSON \u escapes (same value on parse); an internal refusal is not retried three times;
// a failing table stops the day with its resume point saved, and fn_table_export_due (v2,
// a_failed_export_day_resumes_from_its_failed_page.sql) resumes from that page instead of from the
// first table; every failed day is a loud it_engineer finding through fn_it_duty_settle, classed
// internal (ours) or provider (their outage), and a finished day closes it.

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SELF = Deno.env.get('SUPABASE_URL')! + '/functions/v1/backup';
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
const errText = (e: unknown) => String((e as Error)?.message || e).slice(0, 300);

const SLICE_MS = 30_000;   // hand off well inside the worker's compute budget (v1 measured a 546 at 102 s)
// Measured 15 Sep 2026 (attempt 2 of 2026-09-15): ~10 kb_chunks pages per hop, so a full day is ~262
// hops for kb_chunks + ~25 for the rest — v2's 300 left no room, and the hop count carries across a
// resumed attempt. 900 still stops a runaway chain (~9 h of 36 s hops).
// 15 Sep 2026: with the 12 MB per-hop budget (HOP_BYTES) a hop carries ~3 kb_chunks pages, so a full
// copy is ~2,616 / ~2.8 ≈ 935 hops + ~25 for the rest + whatever an earlier attempt carried (24 tonight):
// ~985. 2000 still stops a runaway chain.
const MAX_HOPS = 2000;
const PAGE = 1000;         // rows per page file (the RPC's cap); kb_chunks ~2.8 MB, ops_knowledge ~8.3 MB
// LIMIT (known, 15 Sep 2026): PAGE bounds ROWS, not bytes. One page whose rows carry an outsized text
// field is read, stringified and escaped whole before the 12 MB hop budget is checked, so a single such
// page can still cost more CPU than a hop should. Upgrade path: a byte-bounded page read
// (fn_table_export_page taking a byte cap and stopping at the row that crosses it).

type State = HopState & { kind: string; since: string | null; hop: number };

async function upload(path: string, body: string) {
  await retry('upload ' + path, async () => {
    const { error } = await admin.storage.from('backups')
      .upload(path, new Blob([body], { type: 'application/json' }), { contentType: 'application/json', upsert: true });
    // deno-lint-ignore no-explicit-any
    if (error) throw Object.assign(new Error(error.message), { status: Number((error as any).statusCode ?? (error as any).status) || undefined });
  });
}

// Every failed day is an it_engineer finding at once (duty 'table_export'); a finished day closes it.
async function settle(stamp: string, failure: { table: string; error: string; cause: string } | null) {
  const items = failure ? [{
    item: 'day_failed', owner_seat: 'it_engineer', subject: 'table_backup', blast: 'agent_facing', affected: 1,
    title: failure.cause === 'internal'
      ? `The daily table export ${stamp} failed for an internal cause on ${failure.table}: ${failure.error}`.slice(0, 300)
      : `The daily table export ${stamp} failed on ${failure.table} because the provider was unavailable: ${failure.error}`.slice(0, 300),
    evidence: { stamp, table: failure.table, error: failure.error, cause: failure.cause },
  }] : [];
  const { error } = await admin.rpc('fn_it_duty_settle', { p_duty: 'table_export', p_items: items });
  if (error) console.error('fn_it_duty_settle(table_export): ' + error.message);
}

// A table restarted on the same day must not keep an earlier attempt's pages beyond its new last page:
// uploads upsert, so a shorter re-run would otherwise leave stale pages that a restore concatenates.
async function clearTable(stamp: string, t: string) {
  for (;;) {
    const { data, error } = await admin.storage.from('backups').list(`${stamp}/${t}`, { limit: 1000 });
    if (error) throw new Error('list ' + t + ': ' + error.message);
    if (!data?.length) return;
    const { error: re } = await admin.storage.from('backups').remove(data.map((e) => `${stamp}/${t}/${e.name}`));
    if (re) throw new Error('clear ' + t + ': ' + re.message);
    if (data.length < 1000) return;
  }
}

// The live storage and database behind the hop loop in table_export_core.ts (runHop / exportSlot).
const DEPS: Deps = {
  now: Date.now,
  clear: clearTable,
  upload,
  readPage: (s) => retry(`${s.t} page ${s.page}`, async () => {
    const { data, error } = await admin.rpc('fn_table_export_page',
      { p_table: s.t, p_after: s.after ?? null, p_limit: PAGE, p_since: s.since });
    if (error) throw new Error(error.message);
    return data;
  }),
};

async function finish(stamp: string, manifest: unknown, error: string | null) {
  const { data, error: fe } = await admin.rpc('fn_table_export_finish', { p_stamp: stamp, p_manifest: manifest, p_error: error });
  if (fe) throw new Error('fn_table_export_finish: ' + fe.message);
  return data;
}

// RETENTION (15 Sep 2026): op 'prune' removes the export days fn_backup_prune_tick logged for deletion
// (90 days; Friday full copies 12 months; see the_backups_are_kept_ninety_days_and_friday_copies_a_year.sql).
// fn_backup_prune_storage_next re-decides each day before handing over a single name and refuses in dry
// run, so this loop cannot delete anything the rules keep. It never lists by prefix itself.
async function prune() {
  const deadline = Date.now() + SLICE_MS;
  const days: Record<string, number> = {}; let errors = 0;
  while (Date.now() < deadline) {
    const { data: next, error } = await admin.rpc('fn_backup_prune_storage_next');
    if (error) throw new Error('fn_backup_prune_storage_next: ' + error.message);
    // deno-lint-ignore no-explicit-any
    const n = next as any;
    if (!n?.log_id) return { days, errors, idle: n?.reason ?? n?.cancelled ?? null };
    // The allow-list again, here: a path the database offered that is not a table-export file stops the
    // day, nothing of it is removed, and the refusal is reported (fn_backup_prune_storage_done -> finding).
    const offered: string[] = Array.isArray(n.names) ? n.names : [];
    const names = offered.filter((p) => exportPathAllowed('backups', p));
    const refused = offered.length - names.length;
    let removed = 0;
    let err: string | null = refused
      ? `the allow-list refused ${refused} of ${offered.length} path(s) offered for ${n.day}; nothing was removed`
      : null;
    if (names.length && !err) {
      try {
        await retry('remove ' + n.day, async () => {
          const { data: gone, error: re } = await admin.storage.from('backups').remove(names);
          if (re) throw new Error(re.message);
          removed = (gone || []).length;
        });
      } catch (e) { err = errText(e); }
    }
    const { data: done, error: de } = await admin.rpc('fn_backup_prune_storage_done', { p_log_id: n.log_id, p_removed: removed, p_error: err });
    if (de) throw new Error('fn_backup_prune_storage_done: ' + de.message);
    days[n.day] = (days[n.day] || 0) + removed;
    if (err) { errors++; break; }                                      // counted; the tick raises the finding
    // deno-lint-ignore no-explicit-any
    if (!names.length && Number((done as any)?.left) > 0) break;        // storage disagrees with itself; do not spin
  }
  return { days, errors };
}

Deno.serve(async (req) => {
  // deno-lint-ignore no-explicit-any
  let b: any = {}; try { b = await req.json(); } catch (_) { /* empty body is refused below */ }
  const auth = await requireInternal(admin, b?.__secret, 'backup');
  if (!auth.ok) return J({ error: 'forbidden' }, 403);
  if (b?.op === 'prune') {
    try { return J({ ok: true, op: 'prune', ...(await prune()) }); }
    catch (e) { return J({ ok: false, op: 'prune', error: errText(e) }, 500); }
  }
  const stamp = String(b?.stamp || '');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(stamp)) return J({ ok: false, error: 'stamp (the Asia/Dubai day from fn_table_export_due) is required' }, 400);
  const kind = b?.kind === 'incremental' ? 'incremental' : 'full';
  const since = kind === 'incremental' && typeof b?.since === 'string' ? b.since : null;
  if (kind === 'incremental' && !since) return J({ ok: false, error: 'an incremental day needs since' }, 400);
  const deadline = Date.now() + SLICE_MS;

  let st: State | null = b?.state && b.state.stamp === stamp && Array.isArray(b.state.queue) ? b.state as State : null;
  try {
    if (!st) {
      const { data: list, error } = await admin.rpc('fn_table_export_list');
      if (error) throw new Error('fn_table_export_list: ' + error.message);
      st = { stamp, kind, since, hop: 0, bytes: 0, tables: {}, errors: {},
        // deno-lint-ignore no-explicit-any
        queue: (list || []).map((x: any) => ({ t: String(x.table_name), after: null, page: 0, rows: 0,
          since: since && x.change_log ? since : null })) };
    }
    if (st.hop >= MAX_HOPS) {
      return J({ ok: false, stamp, result: await finish(stamp, null, `chain exceeded ${MAX_HOPS} hops with ${st.queue.length} table(s) left`) });
    }

    // A failing table stops the day where it stands: the slot stays at the head of the queue holding the
    // refused page, is saved, and the next attempt resumes there (v2 used to shift it away and restart
    // every table on the retry, re-uploading ~400 MB to meet the same page again).
    // The CPU bound is the byte budget; the deadline is the wall-clock one. runHop also fails the day after
    // IDLE_HOPS hops that stored nothing, and that failure takes the same settle() path below.
    const failure = await runHop(st, DEPS, deadline, { spent: 0, max: HOP_BYTES });
    st.hop++;
    const { error: se } = await admin.rpc('fn_table_export_save', { p_stamp: stamp, p_state: st });
    if (se) throw new Error('fn_table_export_save: ' + se.message);

    if (failure) {
      await settle(stamp, failure);
      return J({ ok: false, stamp, failed: [failure.table], cause: failure.cause,
        result: await finish(stamp, null, `${failure.table}: ${failure.cause}: ${failure.error}`) });
    }

    if (st.queue.length) {
      const next = fetch(SELF, { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ __secret: b.__secret, stamp, kind: st.kind, since: st.since, state: st }) })
        .then((r) => r.body?.cancel()).catch(() => {});
      // deno-lint-ignore no-explicit-any
      (globalThis as any).EdgeRuntime?.waitUntil?.(next);
      return J({ ok: true, stamp, hop: st.hop, done: Object.keys(st.tables).length, remaining: st.queue.length });
    }

    // Reached on the version-skew path only: errors a v2 hop recorded before v3 was deployed.
    const leftover = leftoverFailure(st.errors);
    if (leftover) {
      await settle(stamp, leftover);
      return J({ ok: false, stamp, failed: Object.keys(st.errors), cause: leftover.cause,
        result: await finish(stamp, null, leftover.error) });
    }
    const manifest = { created_at: new Date().toISOString(), layout: 'paged', stamp, kind: st.kind, since: st.since,
      tables: st.tables, total_bytes: st.bytes,
      restore: 'every table is a full copy except where tables.<t>.mode says changes_since: restore those from the latest full day plus every later day',
      demo_excluded: 'rows marked ZZ DEMO, @example.invalid or is_demo, and rows of a demo customer, supplier, inquiry or quote',
      writer: 'supabase/functions/backup v2; rows read by public.fn_table_export_page' };
    await upload(`${stamp}/_manifest.json`, JSON.stringify(manifest, null, 2));
    const result = await finish(stamp, manifest, null);
    // deno-lint-ignore no-explicit-any
    if ((result as any)?.ok) await settle(stamp, null);
    return J({ ok: true, stamp, kind: st.kind, tables: Object.keys(st.tables).length, result });
  } catch (e) {
    const cause = e instanceof ExportError ? e.cause_ : 'internal';
    await settle(stamp, { table: '(the chain)', error: errText(e), cause }).catch(() => {});
    try { await finish(stamp, null, errText(e)); } catch (_) { /* the stale heartbeat restarts the day */ }
    return J({ ok: false, stamp, error: errText(e) });
  }
});
