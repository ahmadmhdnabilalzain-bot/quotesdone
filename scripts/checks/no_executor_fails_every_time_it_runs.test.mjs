// AN EXECUTOR THAT HAS NEVER ONCE SUCCEEDED IS SWITCHED OFF, NOT CAUTIOUS.
//
// 13 Aug 2026. knowledge_fill_gap: 0 succeeded, 3 failed, every one of them HTTP 400
// category_required, with 8 more steps queued behind them. Its only caller is
// fn_workflow_step_sweep, which builds the request from workflow_step_run.input and passes it
// through faithfully - and NO workflow_step_run row of ANY action_class has ever carried a
// `category`: 0 out of 1,000+ rows across 15 classes. The one caller it had could never satisfy
// the one argument it demanded, so the class could not succeed by construction.
//
// Nothing alerted. The dispatcher recorded each failure correctly, the cron kept running, and the
// aggregate looked healthy because 662 other executions succeeded around it. A per-class view is
// what makes it visible: every OTHER class has successes newer than its failures - they broke and
// recovered - while this one had failures and nothing else, ever.
//
// The check is deliberately about the SHAPE rather than about kb_fill_gap: any executor whose
// every recorded attempt failed is either misconfigured or wired to a caller that cannot call it,
// and both are worth stopping for. A deterministic 4xx makes it certain (the target understood the
// request and refused it), so that is reported separately from a timeout, which can be transient.
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
  test(`every executor that has run has succeeded at least once on ${label}`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }

    const rows = await q(project, `
      select a.action_class,
             count(*)::int                                              attempts,
             count(*) filter (where a.status = 'succeeded')::int        ok,
             count(*) filter (where a.status = 'failed')::int           bad,
             max((a.response->>'http_status'))                          last_http,
             max(left(coalesce(a.response->>'error',''), 120))          sample
        from public.action_execution a
       where a.status in ('succeeded','failed')
       group by a.action_class
      having count(*) filter (where a.status = 'succeeded') = 0
       order by count(*) desc`);

    // An action_class nobody has attempted is not a finding; this only sees classes with
    // recorded terminal attempts, and every one of them failed every time.
    if (rows.length) {
      const detail = rows.map((r) => `${r.action_class}: ${r.bad}/${r.attempts} failed, `
        + `last http ${r.last_http || '-'}, ${r.sample || 'no error text'}`).join('\n  ');
      assert.fail(`executor class(es) that have NEVER succeeded on ${label}:\n  ${detail}\n`
        + 'Either the executor is misconfigured or its caller cannot satisfy its contract. '
        + 'A class that fails every time it runs is switched off, not cautious.');
    }
  });

  // The fallback kb_fill_gap now relies on: it picks the active category agent with the fewest
  // kb_chunks when the caller names none. If the roster is empty the fallback has nothing to
  // choose from and the class silently goes back to refusing every call.
  test(`kb_fill_gap has a roster to choose a gap from on ${label}`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const [r] = await q(project, `select count(*)::int n from public.category_agents where active`);
    assert.ok(Number(r.n) > 0,
      'category_agents has no active row, so kb_fill_gap cannot choose a category when the workflow does not name one');
  });
}
