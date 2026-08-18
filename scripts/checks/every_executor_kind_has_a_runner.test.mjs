// AN EXECUTOR KIND WITH NO RUNNER IS A QUEUE THAT FILLS AND NEVER DRAINS.
//
// 13 Aug 2026. org_action_executor holds two kinds - 'edge' (an edge function over HTTP) and 'rpc'
// (a SQL function). fn_action_invoke_dispatch filtered `e.kind = 'edge'` and fn_workflow_step_sweep
// filtered `e.kind = 'edge'` too, so the 16 rpc rows had no runner anywhere. knowledge_fill - low
// risk, advisory safe, reversible, notifies nobody - sat with 13 steps in 'ready' and raised
// "STALLED: 56 workflow step(s) are ready" 22 times in 24 hours.
//
// This asserts the general property rather than the one class: every kind that appears in
// org_action_executor must be named by something that can run it. A new kind added later with no
// invoker fails here instead of quietly accumulating work for a month.
//
//   node --test scripts/checks/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const mgmtToken = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

// staging was a second target until its Supabase project was deleted on 15 Aug 2026; the same
// assertions now run against production alone.
const PROJECTS = { production: 'htdblwldjkcgjvmqkbeh' };

const q = async (project, query) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${project}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + mgmtToken, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  const text = await r.text();
  assert.ok(r.ok, `query failed on ${project}: ${r.status} ${text}`);
  return JSON.parse(text);
};

for (const [label, project] of Object.entries(PROJECTS)) {
  test(`every executor kind has an invoker that names it on ${label}`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }

    const kinds = (await q(project, `select distinct kind from public.org_action_executor where kind is not null`))
      .map((r) => r.kind);
    assert.ok(kinds.length, 'org_action_executor holds no kinds at all');

    // The invokers, read as source. A kind is served if some invoker's body mentions it.
    const bodies = await q(project, `select p.proname, pg_get_functiondef(p.oid) def
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname in ('fn_action_invoke_dispatch','fn_action_invoke_rpc','fn_workflow_step_sweep')`);
    assert.ok(bodies.length >= 2, 'the invokers are missing; nothing can drain action_execution');

    const unserved = kinds.filter((k) => !bodies.some((b) => String(b.def).includes(`'${k}'`)));
    assert.deepEqual(unserved, [],
      `executor kind(s) with no invoker that names them: ${unserved.join(', ')}. `
      + 'Work queued for these accumulates and never drains.');
  });

  // The runner exists; it also has to be on a clock. A runner nobody calls is the same defect one
  // layer up, and this estate has produced that shape repeatedly.
  //
  // 18 AUG 2026 — THIS READ A COLUMN THE VALUE HAD MOVED OUT OF, AND DEMANDED THE HOLD BE BROKEN.
  // Two defects in four lines, both found by the final acceptance audit:
  //
  //   1. `command like '%fn_action_invoke_rpc%'` can no longer match ANY wrapped job. The kernel
  //      cutover rewrote every active cron command to `select public.fn_kernel_cron_exec(<jobid>)`
  //      and moved the original into phase_c_system_execution_wrapper.original_command. The filter
  //      was looking in a column the value had been moved out of, so it would report zero even
  //      with the job running every five minutes.
  //   2. `where active` demanded active = true. The three action_invoke_* jobs are deliberately
  //      inactive: that IS the Phase C business-automation hold, which the acceptance gate
  //      separately requires to stay in force. A test that goes green only when the hold is broken
  //      is asking for the wrong thing.
  //
  // What is asserted now is the thing that would actually be a defect: the invoker must be
  // REGISTERED on a schedule and WRAPPED, so it runs the moment the founder releases the hold.
  // Activation is reported, never demanded — and the reporting distinguishes "held" from "gone",
  // which is the distinction that matters when somebody asks why nothing is draining.
  test(`the rpc invoker is registered on a clock on ${label}`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const rows = await q(project, `select j.jobid, j.active, j.schedule,
              (j.command like '%fn_kernel_cron_exec%') as wrapped,
              coalesce(w.original_command, j.command) as effective_command
         from cron.job j
         left join public.phase_c_system_execution_wrapper w on w.jobid = j.jobid
        where coalesce(w.original_command, j.command) like '%fn_action_invoke_rpc%'`);
    assert.ok(rows.length > 0,
      'no cron job runs fn_action_invoke_rpc, through the kernel wrapper or directly, so rpc '
      + 'executors only run when somebody calls them by hand. Checked cron.job.command AND '
      + 'phase_c_system_execution_wrapper.original_command, because the kernel cutover moved the '
      + 'original command into the wrapper.');
    // Only a job that RUNS needs the wrapper. fn_kernel_cron_exec was applied to the active
    // state-changing cron components (fn_kernel_system_trace_state: 0 of 22 unwrapped); an
    // inactive job executes nothing, so there is no execution to trace and nothing to wrap. Held
    // jobs are wrapped when they are released, which is the moment the trace starts to matter.
    for (const j of rows.filter((x) => x.active)) {
      assert.ok(j.wrapped,
        `cron job ${j.jobid} is ACTIVE and runs fn_action_invoke_rpc without going through `
        + 'fn_kernel_cron_exec, so its execution carries no system-execution trace');
    }
    const live = rows.filter((j) => j.active).length;
    console.log(`      rpc invoker: ${rows.length} registered job(s), ${live} active`
      + `${live === 0 ? ' — held under the Phase C business-automation hold, not missing' : ''}`);
  });
}
