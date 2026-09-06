// Move the zero-cost evidence window's CLOSE to the newest timestamp any Phase D / freeze table
// carries, and assert the window is still true over its whole span before writing it.
//
// scripts/checks/zero_cost_evidence_window_covers_the_work.test.mjs reads exactly those columns from
// information_schema, so this reads them the same way rather than listing them — the mistake that
// put fifteen count literals in fn_phase_b_invariants.
//
// RUN THIS LAST. A window regenerated before the final apply closes before the work it covers, which
// is the defect that has now landed in this document five times.
import { readFileSync, writeFileSync } from 'node:fs';
import { q } from './q.mjs';

const DOC = 'docs/phase-d/PHASE_D_ZERO_COST_EVIDENCE.md';
let doc = readFileSync(DOC, 'utf8');

const m = doc.match(
  /Covers\s+\*{0,2}(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}(?::\d{2})?)\s*(?:→|->)\s*(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}(?::\d{2})?)\s*UTC\*{0,2}/);
if (!m) { console.error(`${DOC} no longer states a window in the form "Covers <open> → <close> UTC"`); process.exit(1); }
const open = `${m[1]} ${m[2].length === 5 ? m[2] + ':00' : m[2]}+00`;

const cols = await q(`
  select c.table_name, c.column_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema = c.table_schema and t.table_name = c.table_name
     and t.table_type = 'BASE TABLE'
   where c.table_schema = 'public'
     and c.data_type in ('timestamp with time zone','timestamp without time zone')
     and (c.table_name like 'phase_d\\_%' or c.table_name in
          ('phase_c_change_request','phase_c_freeze_amendment','phase_c_frozen_subject'))
   order by 1, 2`);
const union = cols
  .map((c) => `select max("${c.column_name}")::timestamptz as t, '${c.table_name}.${c.column_name}' as src from public."${c.table_name}"`)
  .join(' union all ');
const latest = await q(`select src, t from (${union}) z where t is not null order by t desc limit 5`);
console.log('five most recent Phase D / freeze writes:');
for (const r of latest) console.log(`  ${r.t}  ${r.src}`);

// THE SUBSTANCE, ASSERTED BEFORE THE DATE IS MOVED. A window is only worth extending while the
// claim it makes is still true over the whole of it.
const spend = await q(`select
  (select count(*) from public.ai_cost_log where occurred_at > '${open}'::timestamptz)::text cost_rows,
  (select count(*) from public.llm_attempt where created_at  > '${open}'::timestamptz)::text attempt_rows,
  (select coalesce(sum(cost_aed),0)::text from public.ai_cost_log where occurred_at > '${open}'::timestamptz) spend`);
const s = spend[0];
console.log(`\nover the window opening ${open}: ai_cost_log ${s.cost_rows} row(s) totalling ${s.spend}, llm_attempt ${s.attempt_rows} row(s)`);
if (Number(s.cost_rows) !== 0 || Number(s.attempt_rows) !== 0) {
  console.error('the zero-cost claim is NOT true over this window. Nothing written.');
  process.exit(1);
}

// A whole minute after the newest write, so a close is never equal-to-or-before a timestamp that
// arrives in the same second.
const newest = new Date(latest[0].t.endsWith('Z') || /[+-]\d\d(:?\d\d)?$/.test(latest[0].t)
  ? latest[0].t : latest[0].t + 'Z');
const close = new Date(Math.ceil((newest.getTime() + 1000) / 60000) * 60000);
const pad = (n) => String(n).padStart(2, '0');
const closeStr = `${close.getUTCFullYear()}-${pad(close.getUTCMonth() + 1)}-${pad(close.getUTCDate())} `
  + `${pad(close.getUTCHours())}:${pad(close.getUTCMinutes())}`;

const before = `${m[3]} ${m[4]}`;
if (before === closeStr) { console.log(`\nwindow already closes at ${closeStr}; unchanged`); process.exit(0); }
doc = doc.replace(m[0], m[0].replace(`${m[3]} ${m[4]}`, closeStr));
writeFileSync(DOC, doc);
console.log(`\nwindow close moved ${before} -> ${closeStr} UTC (newest write ${latest[0].t}, ${latest[0].src})`);
