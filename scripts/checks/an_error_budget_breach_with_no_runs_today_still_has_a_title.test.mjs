// AN ERROR-BUDGET BREACH WITH NO RUNS TODAY STILL HAS A TITLE (it_engineer, 27 Oct 2026).
//
// it_engineer.latency_slo failed 116 runs in a row from 22 Oct 2026: customer_portal breached its 30-day error budget
// on a day it had no runs, fn_it_slo_judge rightly returned burn_rate_24h = null, the title concatenated it and became
// null, and fn_it_duty_settle refused the item - so no latency finding settled for any function.
// Fix: scripts/sql/an_error_budget_breach_with_no_runs_today_still_has_a_title.sql
//
//   node --test scripts/checks/an_error_budget_breach_with_no_runs_today_still_has_a_title.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { manifestWithPending, pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const FILE = 'scripts/sql/an_error_budget_breach_with_no_runs_today_still_has_a_title.sql';

function canonicalBody(fn) {
  const re = new RegExp(`create or replace function public\\.${fn}\\(`, 'i');
  const owner = [...manifestWithPending()].reverse().find((f) => existsSync(join(ROOT, f)) && re.test(R(f)));
  assert.ok(owner, `no applied or pending file defines ${fn}`);
  const src = R(owner).slice(R(owner).search(re));
  return src.split('$fn$')[1] || '';
}

test('the canonical fn_it_engineer_latency_slo never puts burn_rate_24h into a title unguarded', () => {
  const body = canonicalBody('fn_it_engineer_latency_slo').replace(/--[^\n]*/g, '');
  const title = body.slice(body.indexOf("x.fn || ':error_budget'"), body.indexOf("'evidence', j ||"));
  assert.ok(title.length > 0, 'the error-budget item was not found in the body');
  assert.match(title, /burn_rate_24h'\s+is\s+not\s+null/, 'the error-budget title concatenates burn_rate_24h without a null branch');
  assert.match(title, /coalesce\(round\(\(j->>'availability'\)/, 'the error-budget title concatenates availability without a coalesce');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

// A function with 10 failed runs two days ago and none in the last 24 h: a 30-day breach on a quiet day.
const PROBE = `
do $p$
declare v jsonb; t text;
begin
  insert into public.agent_runs (agent, started_at, finished_at, status, counts)
  select 'fn:zz_probe_quiet_day', now() - interval '2 days' - make_interval(mins => g), now() - interval '2 days', 'error',
         jsonb_build_object('ms', 100, 'budget_ms', 1000, 'http', 500)
    from generate_series(1, 10) g;
  v := public.fn_it_engineer_latency_slo();
  select title into t from public.it_engineer_finding
   where issue_key = 'duty:latency_slo:zz_probe_quiet_day:error_budget' and closed_at is null;
  raise exception 'CHK<<%>>', case when t is null then 'PROBE FAILED: no titled error-budget finding; settled=' || coalesce(v->>'settled', 'null')
                                   else 'PROBE OK ' || t end;
end $p$;`;

test('production, rolled back: a 30-day breach with no runs in the last 24 h settles a titled finding', { skip: SKIP }, async () => {
  const pre = pendingNotes().has(FILE) ? R(FILE) + '\n' : '';
  let out = null;
  try { await replaySql(pre + PROBE, { retry: false }); } catch (e) {
    out = String(e.message || e).match(/CHK<<([\s\S]*)>>/)?.[1];
    assert.ok(out, 'the probe failed before it could report: ' + String(e.message || e).slice(0, 800));
  }
  assert.ok(out, 'the probe committed instead of rolling back');
  assert.match(out, /^PROBE OK zz_probe_quiet_day had no runs in the last 24 h/, out);
});
