// K24 — match a cron execution to its trace by OVERLAP, not by "starts inside the window".
//
// Generated from the LIVE fn_kernel_system_trace_state so only the has_trace predicate can move.
import { readFileSync, writeFileSync } from 'node:fs';
import { sql } from './lib/db.mjs';

const [{ prosrc }] = await sql(
  `select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='fn_kernel_system_trace_state'`);

const OLD = `         exists (select 1 from public.phase_c_system_execution se
                  where se.component_id = runs.component_id
                    and se.started_at >= runs.start_time
                    and se.started_at <= runs.end_time) as has_trace`;

const NEW = `         -- K24. Was: se.started_at between runs.start_time and runs.end_time. That is not the
         -- relationship; it is an approximation of it, and a three-millisecond clock difference
         -- broke it. cron:autonomy_dispose_hourly run 333732 was reported as an untraced NEW
         -- state-changing execution while its trace sat in phase_c_system_execution — the wrapper
         -- stamped started_at 2026-08-17 00:45:00.115196 and cron.job_run_details recorded
         -- start_time 00:45:00.118297, three milliseconds LATER. The trace legitimately begins
         -- before the scheduler notices the run has begun.
         --
         -- The real relationship is OVERLAP: the execution and the cron run cover the same
         -- instant. That is what "this run produced this trace" means, and it does not depend on
         -- two clocks agreeing to the millisecond.
         --
         -- The job identity is checked as well as the component, so overlap alone cannot match a
         -- different job that happened to run at the same moment. This is narrower than the old
         -- predicate in that respect and wider only in the one that was wrong.
         exists (select 1 from public.phase_c_system_execution se
                  where se.component_id = runs.component_id
                    and se.trigger_source like 'cron.job/' || runs.jobid::text || '%'
                    and se.started_at <= runs.end_time
                    and coalesce(se.finished_at, se.started_at) >= runs.start_time) as has_trace`;

if (!prosrc.includes(OLD)) { console.error('has_trace predicate not found verbatim — refusing to emit'); process.exit(1); }
const body = prosrc.replace(OLD, NEW);

writeFileSync('scripts/sql/kernel_k24_trace_match_by_overlap.sql',
  readFileSync('scripts/sql/kernel_k24_header.txt', 'utf8') +
  `\nbegin;\n\ncreate or replace function public.fn_kernel_system_trace_state()\n` +
  `returns table (check_name text, expected text, actual text, ok boolean)\n` +
  `language sql\nstable\nsecurity definer\nset search_path to 'public', 'cron', 'pg_temp'\n` +
  `as $k24_state$${body}$k24_state$;\n\ncommit;\n`);
console.log('emitted');
