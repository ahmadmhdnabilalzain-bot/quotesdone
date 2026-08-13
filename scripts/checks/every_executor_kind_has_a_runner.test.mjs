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

const PROJECTS = { production: 'htdblwldjkcgjvmqkbeh', staging: 'pglpqrhvozwepymcuunn' };

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
  test(`the rpc invoker is scheduled on ${label}`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const [j] = await q(project, `select count(*)::int n from cron.job
       where active and command like '%fn_action_invoke_rpc%'`);
    assert.ok(Number(j.n) > 0,
      'fn_action_invoke_rpc has no active cron entry, so rpc executors only run when somebody calls them by hand');
  });
}
