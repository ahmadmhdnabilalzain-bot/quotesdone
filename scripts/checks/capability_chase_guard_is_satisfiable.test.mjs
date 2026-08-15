// A GUARD NO ROW CAN SATISFY REPORTS SUCCESS FOREVER.
//
// 13 Aug 2026. fn_supplier_capability_chase is the only mechanism in the estate that asks a
// supplier to confirm their scope — the one thing standing between 15,306 capability records and
// more than one supplier an RFQ can reach. It is on cron and active. It had produced nothing:
//
//   agent_runs where agent='supplier_success'      24 runs, latest 2026-08-13 06:30 UTC
//   every note                                      "0 chased, 0 escalated, 0 flagged"
//   notifications where type='capability_chase'     0, ever
//
// Its loop opened with `sc.review_status in ('insufficient','awaiting_confirmation')`, and the only
// values that have ever existed in that column are 'derived' (15,305) and 'confirmed' (1). Those
// two statuses are written exclusively by capability_agent's `analyze` action, which reads a
// supplier's uploaded documents — a path no scraped directory lead has ever taken. The routine
// filtered for the output of a path that never ran, matched nothing, and logged 'ok' every morning.
//
// Nothing failed, so none of the watchers saw it. This check asserts the guard is SATISFIABLE:
// every review_status literal the routine tests against must be a value that actually occurs in
// supplier_capabilities. A routine that gates on a status no row holds is not conservative, it is
// switched off.
//
//   node --test scripts/checks/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const mgmtToken = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

const q = async (project, query) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${project}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + mgmtToken, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  assert.ok(r.ok, `query failed on ${project}: ${r.status}`);
  return r.json();
};

// staging was a second target until its Supabase project was deleted on 15 Aug 2026; the same
// assertions now run against production alone.
for (const [label, project] of [['production', 'htdblwldjkcgjvmqkbeh']]) {
  test(`the capability chase can select a row on ${label}`, async (t) => {
    if (!mgmtToken) {
      t.skip('no SUPABASE_ACCESS_TOKEN and no local access token, so the live routine cannot be read');
      return;
    }
    const [{ def }] = await q(project, "select pg_get_functiondef(p.oid) as def from pg_proc p "
      + "join pg_namespace n on n.oid = p.pronamespace "
      + "where n.nspname = 'public' and p.proname = 'fn_supplier_capability_chase'");
    assert.ok(def, 'fn_supplier_capability_chase is missing');

    // Only the selecting loop. The escalation branch further down legitimately reads review_status
    // into an agent_action payload without filtering on it.
    const loop = def.slice(def.indexOf('for rec in'), def.indexOf('loop\n'));
    const filters = [...loop.matchAll(/review_status\s+in\s*\(([^)]*)\)|review_status\s*=\s*'([^']+)'/gi)]
      .flatMap((m) => (m[1] ? [...m[1].matchAll(/'([^']+)'/g)].map((x) => x[1]) : [m[2]]));

    const rows = await q(project, 'select distinct review_status from public.supplier_capabilities');
    const live = new Set(rows.map((r) => r.review_status));

    const impossible = filters.filter((f) => !live.has(f)).sort();
    assert.deepEqual(impossible, [],
      `fn_supplier_capability_chase's selecting loop requires review_status in {${impossible.join(', ')}} `
      + `but supplier_capabilities only ever holds {${[...live].sort().join(', ')}} on ${label}. `
      + 'The chase will select nothing and report "0 chased, ok" every run — which is how it went '
      + '24 runs without sending a single email while 15,305 suppliers sat unconfirmed. Either the '
      + 'status is written by a path that has never executed, or the filter is wrong.');

    console.log(`${label}: chase filters on review_status {${filters.join(', ') || 'nothing — it gates on the relationship'}}; `
      + `live values {${[...live].sort().join(', ')}}`);
  });
}

test('the chase does not cold-email the directory', async (t) => {
  if (!mgmtToken) { t.skip('no management token'); return; }
  const [{ def }] = await q('htdblwldjkcgjvmqkbeh', "select pg_get_functiondef(p.oid) as def from pg_proc p "
    + "join pg_namespace n on n.oid = p.pronamespace "
    + "where n.nspname = 'public' and p.proname = 'fn_supplier_capability_chase'");
  const loop = def.slice(def.indexOf('for rec in'), def.indexOf('loop\n'));
  // The correction for the guard above must not be "select everything". 20,471 leads carry a
  // capability record or an address; the invite ramp is capped at 10/day with a bounce auto-pause
  // for exactly that reason. Only a supplier who has claimed their company has opted in.
  assert.match(loop, /coalesce\(l\.claimed,\s*false\)\s*=\s*true/,
    'the chase no longer restricts itself to suppliers who have claimed their company — as written it '
    + 'would mail scraped directory leads that have never heard of QuotesDone');
  assert.match(def, /fn_email_sendable/,
    'the chase does not consult fn_email_sendable, so it can queue mail to a domain that does not accept it '
    + '(every ZZ DEMO fixture carries an @example.invalid address)');
  assert.match(def, /My scope/,
    'the chase email must name the tab that actually carries the confirm button — it said "Profile" '
    + 'for months, which is the company-details form and has no confirm button on it');
});
