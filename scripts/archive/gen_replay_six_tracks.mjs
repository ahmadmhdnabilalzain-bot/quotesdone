// ROW #3 s33 — the replay stores twelve days and can show one thing about each of them.
//
// ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
//   s33-replay-six-tracks  MISSING  4 of 6 track(s) have rows on 2026-08-08 (missing: KPIs,
//                                   outcomes); 0 reachable routine(s) span all six tables at once
//
// The second half is the one that decides whether this is a REPLAY or six unrelated tables that
// happen to be queryable. Nothing the browser can run reads decision_log, agent_chats,
// agent_actions, workflow_step_run, metric_snapshot and outcome_record together for one day, so
// the Replay card shows twelve dated chips and, for the day behind any of them, nothing.
//
// fn_ws_company_os already owns the replay surface and already carries the snapshot itself, so the
// six tracks go there rather than into a new routine with a new os_api action and a new module.
// The day is the newest company_snapshot day — the same day the card is already showing — so the
// counts describe the chip the founder is looking at.
//
// The KPI track is the one bi_snapshot_6h was scheduled for (scripts/sql/cron_bi_snapshot.sql):
// metric_snapshot had rows on two days ever, so from 00:35 every snapshot day has KPI rows. The
// outcomes track fills when fn_kpi_review opens outcomes on a Monday. Neither is fixed here; this
// change is the reader, and the reader is what was missing.
import { readFileSync, writeFileSync } from 'node:fs';
import { mgmtRead } from '../lib/qd_guard.mjs';
import { REF as STAGE } from '../lib/demo_factory.mjs';

const OUT = 'scripts/sql/replay_six_tracks.sql';
const one = async (sql) => { const r = await mgmtRead(STAGE, sql); return r[0] ? Object.values(r[0])[0] : null; };

const def = await one(`select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
  where ns.nspname='public' and p.proname='fn_ws_company_os' limit 1`);
if (!def) { console.error('fn_ws_company_os not found'); process.exit(1); }
if (/workflow_step_run/.test(def)) { console.error('REFUSING: fn_ws_company_os already reads workflow_step_run.'); process.exit(1); }

const ANCHOR = `      'days_on_file',`;
if (def.split(ANCHOR).length - 1 !== 1) {
  console.error('REFUSING: the days_on_file anchor did not match exactly once. Re-read the routine.');
  process.exit(1);
}

const BLOCK = `      -- THE SIX TRACKS OF THE CHOSEN DAY, in one place for the first time. The day is the newest
      -- company_snapshot day, which is the chip the Replay card is already showing, so these
      -- counts describe what the founder is looking at rather than a different day's activity.
      'tracks', (select jsonb_build_object(
          'day', dd.day,
          'decisions',     (select count(*) from public.decision_log      x where x.created_at::date = dd.day),
          'conversations', (select count(*) from public.agent_chats       x where x.created_at::date = dd.day),
          'approvals',     (select count(*) from public.agent_actions     x where coalesce(x.decided_at, x.created_at)::date = dd.day),
          'workflows',     (select count(*) from public.workflow_step_run x where coalesce(x.started_at, x.finished_at)::date = dd.day),
          'kpis',          (select count(*) from public.metric_snapshot   x where x.taken_at::date = dd.day),
          'outcomes',      (select count(*) from public.outcome_record    x where coalesce(x.observed_at, x.created_at)::date = dd.day))
        from (select coalesce(max(snapshot_on), current_date - 1) as day from public.company_snapshot) dd),
${ANCHOR}`;

const out = def.replace(ANCHOR, BLOCK);
if (out === def) { console.error('replacement produced no change'); process.exit(1); }

const selfLines = readFileSync(new URL(import.meta.url).pathname.replace(/^\//, ''), 'utf8').split('\n');
const end = selfLines.findIndex((l) => !l.startsWith('//'));
const HEADER = selfLines.slice(0, end < 0 ? selfLines.length : end)
  .map((l) => l.replace(/^\/\/ ?/, '-- ').replace(/^\/\//, '--')).join('\n');

writeFileSync(OUT, `${HEADER}\n\n${out};\n`);
console.log(`wrote ${OUT}`);
console.log(`  fn_ws_company_os ${def.length} -> ${out.length} chars`);
