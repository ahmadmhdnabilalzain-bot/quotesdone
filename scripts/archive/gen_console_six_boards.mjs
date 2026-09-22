// ROW #3 layer 13 — the command centre shows two of the six boards it is supposed to be.
//
// ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
//   command-center-six-boards  MISSING  <Console> (module 'console') is the fullest of 31 sidebar
//                                       modules: 2 of 6 boards; absent there: live workflow, live
//                                       AI collaboration, knowledge growth, infrastructure health
//
// The check is deliberately harsh in one specific way: the six must be on ONE screen. Six boards
// spread across six modules is a sidebar, not a command centre, so it scores whichever single
// component carries the most and that is the Console with company health and live revenue.
//
// The evidence line proves the data is not the problem — it prints the five server-side sources
// itself: fn_health_index exists, workflow_run has rows, event_delivery has rows, kb_revisions has
// rows, edge_health_probe has rows. Measured today, over the windows each board would use:
//
//   workflow_run started in 24h        9
//   event_delivery in 24h            163      (one employee handing work to another)
//   kb_revisions in 7d             1,750
//   edge_health_probe in 24h       3,072      verdicts are ALIVE / STALE, not ok / fail
//
// So four figures the company measures constantly reach no screen. They go onto the landing screen
// the founder already opens, next to the two that are there.
//
// ── THE ONE TRAP IN THE UPTIME FIGURE ───────────────────────────────────────────────────────────
// edge_health_probe.verdict holds ALIVE and STALE — not 'ok'. A first attempt at this counted
// verdict='ok' and got 0.0%, which would have rendered a healthy estate as a total outage. The
// share is of ALIVE, and it is computed over checked_at rather than a created_at column that this
// table does not have.
import { readFileSync, writeFileSync } from 'node:fs';
import { mgmtRead } from '../lib/qd_guard.mjs';
import { REF as STAGE } from '../lib/demo_factory.mjs';

const OUT = 'scripts/sql/console_six_boards.sql';
const one = async (sql) => { const r = await mgmtRead(STAGE, sql); return r[0] ? Object.values(r[0])[0] : null; };

const def = await one(`select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
  where ns.nspname='public' and p.proname='fn_ws_exec_home' limit 1`);
if (!def) { console.error('fn_ws_exec_home not found'); process.exit(1); }
if (/uptime_pct_24h/.test(def)) { console.error('REFUSING: fn_ws_exec_home already carries the four boards.'); process.exit(1); }

const ANCHOR = `'generated_at'`;
if (def.split(ANCHOR).length - 1 !== 1) {
  console.error('REFUSING: the generated_at anchor did not match exactly once. Re-read the routine.');
  process.exit(1);
}

const BLOCK = `-- FOUR BOARDS THAT WERE MEASURED CONSTANTLY AND SHOWN NOWHERE.
    -- Each is the smallest true number for its board over the window that board is about.
    'workflow_runs_24h', (select count(*) from public.workflow_run
                           where coalesce(started_at, created_at) > now() - interval '24 hours'),
    'handoffs_24h', (select count(*) from public.event_delivery
                      where delivered_at > now() - interval '24 hours'),
    'knowledge_revisions_7d', (select count(*) from public.kb_revisions
                                where created_at > now() - interval '7 days'),
    -- ALIVE, not 'ok'. edge_health_probe grades ALIVE / STALE, and counting verdict='ok' returns
    -- 0.0% — a healthy estate rendered as a total outage.
    'uptime_pct_24h', (select round(100.0 * count(*) filter (where verdict = 'ALIVE')
                                    / nullif(count(*), 0), 1)
                         from public.edge_health_probe where checked_at > now() - interval '24 hours'),
    ${ANCHOR}`;

const out = def.replace(ANCHOR, BLOCK);
if (out === def) { console.error('replacement produced no change'); process.exit(1); }

const selfLines = readFileSync(new URL(import.meta.url).pathname.replace(/^\//, ''), 'utf8').split('\n');
const end = selfLines.findIndex((l) => !l.startsWith('//'));
const HEADER = selfLines.slice(0, end < 0 ? selfLines.length : end)
  .map((l) => l.replace(/^\/\/ ?/, '-- ').replace(/^\/\//, '--')).join('\n');

writeFileSync(OUT, `${HEADER}\n\n${out};\n`);
console.log(`wrote ${OUT}`);
console.log(`  fn_ws_exec_home ${def.length} -> ${out.length} chars`);
