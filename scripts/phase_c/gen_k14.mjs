// Build K14 from the LIVE fn_kernel_workflow_start body, deleting only block (e).
// Rewriting the function by hand risks silently dropping logic; this edits the deployed text.
import { readFileSync, writeFileSync } from 'node:fs';
import { sql } from './lib/db.mjs';

const [{ prosrc }] = await sql(
  `select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='fn_kernel_workflow_start'`);

const START = '  -- ---- (e) the initial handoff';
const END   = '  -- ---- (f) ONE factual event';
const i = prosrc.indexOf(START), j = prosrc.indexOf(END);
if (i < 0 || j < 0 || j < i) { console.error('block (e) or (f) marker not found'); process.exit(1); }

const replacement = `  -- ---- (e) NO HANDOFF AT START -- K14 -------------------------------------------------------
  -- Deliberately empty, and named so a reader looking for the block that used to be here finds the
  -- reason rather than a gap. The entry step's outgoing handoff run is created by
  -- fn_kernel_step_complete when that step completes, from its accepted output. Creating it here
  -- as well produced TWO open handoff runs on one registry edge the moment the entry step
  -- completed, and the successor step could then never be opened.

`;

let body = prosrc.slice(0, i) + replacement + prosrc.slice(j);

// The two remaining references to what block (e) used to produce, now truthfully null.
const before = body;
body = body
  .replace(/'step_run_id', v_step_run, 'task_id', v_task, 'handoff_run_id', v_handoff,/,
           `'step_run_id', v_step_run, 'task_id', v_task, 'handoff_run_id', null,`)
  .replace(/'handoff_run_id', v_handoff, 'handoff_id', \(case when v_handoff is null then null else h\.handoff_id end\),/,
           `'handoff_run_id', null, 'handoff_id', null,`)
  .replace(/'task_trace_id', v_task_trace, 'handoff_trace_id', v_ho_trace,/,
           `'task_trace_id', v_task_trace, 'handoff_trace_id', null,`)
  .replace(/\(case when v_ho_trace is null then 3 else 4 end\),/, `3,`)
  .replace(/'handoff', \(case when v_handoff is null then 0 else 1 end\), 'event',1\)\);/,
           `'handoff', 0, 'event',1));`);
if (body === before) { console.error('none of the four v_handoff references matched — refusing to emit'); process.exit(1); }
if (/v_handoff|v_ho_trace/.test(body.replace(/^\s*(v_handoff|v_ho_trace)\s+bigint;\s*$/gm, ''))) {
  console.error('a v_handoff / v_ho_trace reference survived:\n' +
    body.split('\n').filter(l => /v_handoff|v_ho_trace/.test(l)).join('\n'));
  process.exit(1);
}
// The two declarations are now unused. plpgsql tolerates that, but leaving them invites a reader
// to look for the code that filled them. `h` is still used by nothing else — check before dropping.
body = body.replace(/^\s*v_handoff\s+bigint;\s*\n/m, '').replace(/^\s*v_ho_trace\s+bigint;\s*\n/m, '');
if (!/\bh\b\s*\./.test(body) && !/into h\b/.test(body)) {
  body = body.replace(/^\s*h\s+public\.phase_b_handoff%rowtype;\s*\n/m, '');
}

const header = readFileSync('scripts/sql/kernel_k14_header.txt', 'utf8');
writeFileSync('scripts/sql/kernel_k14_start_does_not_pre_hand_off.sql',
  `${header}\nbegin;\n\ncreate or replace function public.fn_kernel_workflow_start(p_input jsonb)\n` +
  `returns jsonb\nlanguage plpgsql\nsecurity definer\nset search_path to 'public', 'pg_temp'\n` +
  `as $k14_start$${body}$k14_start$;\n\n` +
  `comment on function public.fn_kernel_workflow_start(jsonb) is\n` +
  `  'K2, corrected by K14. Starts one workflow run: run, entry step run, exactly one task, its '\n` +
  `  'parented traces and one factual event. It does NOT create a handoff run. A handoff is the '\n` +
  `  'transfer of an accepted output and the entry step has not run yet; creating one here left a '\n` +
  `  'second open handoff run on the same edge as soon as the entry step completed, and the '\n` +
  `  'successor step could then never be opened. fn_kernel_step_complete owns handoff creation.';\n\n` +
  `commit;\n`);
console.log('emitted. block (e) removed, ' + body.split('\n').length + ' body lines.');
