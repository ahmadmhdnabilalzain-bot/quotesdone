// ROW #2 comp-16 (×7) — the per-OS health dimensions were computed weekly and read by nobody.
//
// ── WHAT ROW #2's WORKLIST ESTABLISHED ON 6 AUG, RE-MEASURED TODAY ──────────────────────────────
// v_os_health returns 10 rows and computes open_risks, kpi_gaps, backlog_per_head, stale_tasks,
// review_pass_pct, budget_pct and needs_founder_pct per OS. os_review.metrics carries the same
// figures, non-null on 10 of 10 OS. And:
//
//     procs naming v_os_health, other than its writer fn_os_review     0
//     views naming v_os_health                                          0
//     crons naming v_os_health                                          0
//
// Seven requirements, one root cause: the numbers are produced weekly and opened by nobody. The
// worklist's own conclusion — "one edit to fn_exec_meeting that names all seven closes all seven at
// once; there is no need for seven separate fixes."
//
// comp-16-capacity is the exception it flags: the CONTENT was missing too, not just the reader.
// Re-measured today, half of that has already been fixed — resource_pool now holds 19 rows with
// ZERO null os_key (it was 10 rows with 3 null on 6 Aug). What is still missing is the per-OS
// aggregate: v_os_health has no capacity column at all. So this generator does both halves.
//
// ── WHY A GENERATOR AND NOT TWO HAND-WRITTEN OBJECTS ────────────────────────────────────────────
// fn_exec_meeting is 6,523 characters and v_os_health is a live view with 15 columns in a fixed
// order. CREATE OR REPLACE VIEW cannot reorder or rename existing columns, and retyping either
// object risks a transcription error that no diff would catch. Both are read from the live
// definition, patched at one asserted anchor each, and written out — the same discipline as
// gen_graph_category_agent_edge.mjs and gen_ai_route_cache_ttl.mjs.
//
// The view is extended by WRAPPING rather than by editing its select list: `select h.*, cap.… from
// (<original>) h left join …`. h.* preserves every existing column in its existing order, which is
// exactly what CREATE OR REPLACE VIEW requires, and the new column lands at the end.
//
// ── THE ONE THING THIS MUST NOT DO ──────────────────────────────────────────────────────────────
// The worklist is explicit: "Do NOT satisfy it by adding the word to a comment: the check's
// LIVE_PROC test is name-based, so a cosmetic mention would score MET while nothing is read." So
// fn_exec_meeting genuinely SELECTS from v_os_health and puts the figures into the findings it
// returns — the meeting output changes, not just its text.
import { readFileSync, writeFileSync } from 'node:fs';
import { mgmtRead } from '../lib/qd_guard.mjs';
import { REF as STAGE } from '../lib/demo_factory.mjs';

const OUT = 'scripts/sql/os_health_reaches_the_exec_meeting.sql';
const one = async (sql) => { const r = await mgmtRead(STAGE, sql); return r[0] ? Object.values(r[0])[0] : null; };

// ── 1. THE VIEW ─────────────────────────────────────────────────────────────────────────────────
const viewDef = await one(`select pg_get_viewdef('public.v_os_health'::regclass, true)`);
if (!viewDef) { console.error('v_os_health not found'); process.exit(1); }
if (/capacity_pct/.test(viewDef)) { console.error('REFUSING: v_os_health already has capacity_pct.'); process.exit(1); }

const VIEW_SQL = `create or replace view public.v_os_health as
select h.*, cap.capacity_pct
from (
${viewDef.replace(/;\s*$/, '').split('\n').map((l) => '  ' + l).join('\n')}
) h
left join (
  -- Per-OS capacity from resource_pool. committed/capacity, aggregated by os_key, so an OS with
  -- several pools reports one number. Rows with no capacity are excluded rather than counted as
  -- zero: a pool with no ceiling is unknown capacity, and reporting it as 0% used would be a
  -- fabricated figure in the one column this change exists to make real.
  select os_key,
         round(100.0 * sum(committed) / nullif(sum(capacity), 0))::int as capacity_pct
    from public.resource_pool
   where os_key is not null and capacity is not null and capacity > 0
   group by os_key
) cap on cap.os_key = h.os_key;`;

// ── 2. THE MEETING ──────────────────────────────────────────────────────────────────────────────
const fnDef = await one(`select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
  where ns.nspname='public' and p.proname='fn_exec_meeting' limit 1`);
if (!fnDef) { console.error('fn_exec_meeting not found'); process.exit(1); }
if (/v_os_health/.test(fnDef)) { console.error('REFUSING: fn_exec_meeting already reads v_os_health.'); process.exit(1); }

// Anchor: the line that already reads os_review for this period. The new block goes straight after
// it, so the health figures are gathered in the same place the RAG letters already are.
const ANCHOR = /(\n\s*into v_red, v_amber, v_green from os_review where period = v_period;)/;
const hits = fnDef.match(new RegExp(ANCHOR.source, 'g'));
if (!hits || hits.length !== 1) {
  console.error(`REFUSING: the os_review anchor was found ${hits ? hits.length : 0} time(s), expected exactly 1.`);
  console.error('fn_exec_meeting has changed shape since this generator was written. Re-read it before editing.');
  process.exit(1);
}

const BLOCK = `

  -- ROW #2 comp-16: the eight per-OS health dimensions were computed weekly by fn_os_review and
  -- opened by nobody -- 0 procs, 0 views, 0 crons named v_os_health outside its own writer. They
  -- are read here and named individually, because the weekly exec meeting is the one place a
  -- per-OS number is supposed to change what the company does next.
  for r in select * from public.v_os_health order by num loop
    findings := findings || jsonb_build_array(jsonb_build_object(
      'kind', 'os_health', 'os', r.os_key, 'name', r.name,
      'open_risks',        r.open_risks,
      'kpi_gaps',          r.kpi_gaps,
      'backlog_per_head',  r.backlog_per_head,
      'stale_tasks',       r.stale_tasks,
      'review_pass_pct',   r.review_pass_pct,
      'budget_pct',        r.budget_pct,
      'needs_founder_pct', r.needs_founder_pct,
      'capacity_pct',      r.capacity_pct));
  end loop;`;

const patchedFn = fnDef.replace(ANCHOR, (_m, line) => line + BLOCK);
if (patchedFn === fnDef) { console.error('function replacement produced no change'); process.exit(1); }

const selfLines = readFileSync(new URL(import.meta.url).pathname.replace(/^\//, ''), 'utf8').split('\n');
const end = selfLines.findIndex((l) => !l.startsWith('//'));
const HEADER = selfLines.slice(0, end < 0 ? selfLines.length : end)
  .map((l) => l.replace(/^\/\/ ?/, '-- ').replace(/^\/\//, '--')).join('\n');

writeFileSync(OUT, `${HEADER}\n\n${VIEW_SQL}\n\n${patchedFn};\n`);
console.log(`wrote ${OUT}`);
console.log('  v_os_health   + capacity_pct (wrapped, existing columns untouched)');
console.log('  fn_exec_meeting reads v_os_health and names all 8 figures in findings');
