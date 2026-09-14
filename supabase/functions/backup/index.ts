// backup v2 (14 Sep 2026, it_engineer) — the daily export of every business table, revived.
//
// WHY THIS FILE IS BACK. The 'backups' bucket holds a dated JSON export of the core tables for
// every day from 23 Jun to 7 Sep 2026 (<YYYY-MM-DD>/<table>/page_NNNN.json) and nothing since.
// Measured 14 Sep 2026 on production: the last export is 2026-09-07 03:30 UTC, written by pg_cron
// job 109 calling this function. pg_cron was emptied on
// 7 Sep at 17:51 UTC on the founder's instruction (cron.job holds one inactive row, wa_flush), and
// this function was deleted the next morning with 136 others by commit 182308b (#530), because no
// seat owned it then. Both removals were structural; neither was a decision to stop backing up the
// database. The founder, 14 Sep 2026: backups go to two places, the Supabase private 'backups'
// bucket and Dropbox, and "there is no reason for the loop of the back up to fail except literally
// a disconnection from dropbox and supabase for a server issue from their end".
//
// WHAT CHANGED FROM v1 (supabase/functions/backup at 182308b^):
//   * The table list lives in the database (fn_table_export_list), not in this file, so the IT
//     engineer's expected list and the writer read the same list.
//   * Rows are read through fn_table_export_page: keyset paging on the primary key (v1 used
//     .range() offsets and silently STOPPED at 200,000 rows), demo rows excluded (ZZ DEMO,
//     @example.invalid, is_demo, and any row belonging to such a customer, supplier, inquiry or
//     quote), vector columns stripped.
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

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SELF = Deno.env.get('SUPABASE_URL')! + '/functions/v1/backup';
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
const errText = (e: unknown) => String((e as Error)?.message || e).slice(0, 300);

const SLICE_MS = 30_000;   // hand off well inside the worker's compute budget (v1 measured a 546 at 102 s)
const MAX_HOPS = 80;       // ~90 tables at a few pages each; a runaway chain must stop and be visible
const PAGE = 500;          // rows per page file; the RPC caps it at 1,000

type Slot = { t: string; after: unknown; page: number; rows: number };
type State = {
  stamp: string; hop: number; bytes: number; queue: Slot[];
  tables: Record<string, { rows: number; pages: number }>; errors: Record<string, string>;
};

async function retry<T>(what: string, f: () => Promise<T>): Promise<T> {
  let last: unknown;
  for (const wait of [0, 1000, 3000]) {
    if (wait) await new Promise((r) => setTimeout(r, wait));
    try { return await f(); } catch (e) { last = e; }
  }
  throw new Error(what + ': ' + errText(last));
}

async function upload(path: string, body: string) {
  await retry('upload ' + path, async () => {
    const { error } = await admin.storage.from('backups')
      .upload(path, new Blob([body], { type: 'application/json' }), { contentType: 'application/json', upsert: true });
    if (error) throw new Error(error.message);
  });
}

// A table restarted on the same day must not keep yesterday's-run pages beyond its new last page:
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

// Returns true when the table is finished, false when the slice ran out mid-table (slot keeps the
// exact resume point: the last key read and the next page number).
async function exportSlot(st: State, slot: Slot, deadline: number): Promise<boolean> {
  if (slot.page === 0 && slot.after == null) await clearTable(st.stamp, slot.t);
  for (;;) {
    if (Date.now() > deadline) return false;
    // deno-lint-ignore no-explicit-any
    const r: any = await retry(`${slot.t} page ${slot.page}`, async () => {
      const { data, error } = await admin.rpc('fn_table_export_page', { p_table: slot.t, p_after: slot.after ?? null, p_limit: PAGE });
      if (error) throw new Error(error.message);
      return data;
    });
    const rows = Array.isArray(r?.rows) ? r.rows : [];
    // An empty table still writes page_0000 containing [] — no page at all is indistinguishable
    // from a missing backup.
    if (rows.length || slot.page === 0) {
      const json = JSON.stringify(rows);
      await upload(`${st.stamp}/${slot.t}/page_${String(slot.page).padStart(4, '0')}.json`, json);
      slot.page++; slot.rows += rows.length; st.bytes += json.length;
    }
    if (r?.done) return true;
    slot.after = r.last;
  }
}

async function finish(stamp: string, manifest: unknown, error: string | null) {
  const { data, error: fe } = await admin.rpc('fn_table_export_finish', { p_stamp: stamp, p_manifest: manifest, p_error: error });
  if (fe) throw new Error('fn_table_export_finish: ' + fe.message);
  return data;
}

Deno.serve(async (req) => {
  // deno-lint-ignore no-explicit-any
  let b: any = {}; try { b = await req.json(); } catch (_) { /* empty body is refused below */ }
  const auth = await requireInternal(admin, b?.__secret, 'backup');
  if (!auth.ok) return J({ error: 'forbidden' }, 403);
  const stamp = String(b?.stamp || '');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(stamp)) return J({ ok: false, error: 'stamp (the Asia/Dubai day from fn_table_export_due) is required' }, 400);
  const deadline = Date.now() + SLICE_MS;

  let st: State | null = b?.state && b.state.stamp === stamp && Array.isArray(b.state.queue) ? b.state as State : null;
  try {
    if (!st) {
      const { data: list, error } = await admin.rpc('fn_table_export_list');
      if (error) throw new Error('fn_table_export_list: ' + error.message);
      // deno-lint-ignore no-explicit-any
      st = { stamp, hop: 0, bytes: 0, tables: {}, errors: {}, queue: (list || []).map((x: any) => ({ t: String(x.table_name), after: null, page: 0, rows: 0 })) };
    }
    if (st.hop >= MAX_HOPS) {
      return J({ ok: false, stamp, result: await finish(stamp, null, `chain exceeded ${MAX_HOPS} hops with ${st.queue.length} table(s) left`) });
    }

    while (st.queue.length && Date.now() < deadline) {
      const slot = st.queue[0];
      try {
        if (!(await exportSlot(st, slot, deadline))) break;
        st.tables[slot.t] = { rows: slot.rows, pages: slot.page };
      } catch (e) { st.errors[slot.t] = errText(e); }
      st.queue.shift();
    }
    st.hop++;
    const { error: se } = await admin.rpc('fn_table_export_save', { p_stamp: stamp, p_state: st });
    if (se) throw new Error('fn_table_export_save: ' + se.message);

    if (st.queue.length) {
      const next = fetch(SELF, { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ __secret: b.__secret, stamp, state: st }) }).then((r) => r.body?.cancel()).catch(() => {});
      // deno-lint-ignore no-explicit-any
      (globalThis as any).EdgeRuntime?.waitUntil?.(next);
      return J({ ok: true, stamp, hop: st.hop, done: Object.keys(st.tables).length, remaining: st.queue.length });
    }

    const failed = Object.keys(st.errors);
    if (failed.length) {
      const msg = failed.map((t) => `${t}: ${st!.errors[t]}`).join(' | ').slice(0, 1000);
      return J({ ok: false, stamp, failed, result: await finish(stamp, null, msg) });
    }
    const manifest = { created_at: new Date().toISOString(), layout: 'paged', stamp, tables: st.tables, total_bytes: st.bytes,
      demo_excluded: 'rows marked ZZ DEMO, @example.invalid or is_demo, and rows of a demo customer, supplier, inquiry or quote',
      writer: 'supabase/functions/backup v2; rows read by public.fn_table_export_page' };
    await upload(`${stamp}/_manifest.json`, JSON.stringify(manifest, null, 2));
    return J({ ok: true, stamp, tables: Object.keys(st.tables).length, result: await finish(stamp, manifest, null) });
  } catch (e) {
    try { await finish(stamp, null, errText(e)); } catch (_) { /* the stale heartbeat restarts the day */ }
    return J({ ok: false, stamp, error: errText(e) });
  }
});
