// RETIRED 9 SEP 2026 — THE BASELINE, BOTH VIEWS AND THE LEDGER ARE GONE; THERE IS NOTHING TO COMPARE.
//
// This file was, by its own account below, only a backstop that noticed if a write-time guard had
// quietly gone. The guard, the thing it guarded and the baseline it compared against were all
// dropped with the Phase A–D estate on 9 Sep 2026 (the founder's 7 Sep ruling that everything
// outside the two-agent structure is deleted).
//
// MEASURED ON PRODUCTION (htdblwldjkcgjvmqkbeh) 9 SEP 2026, across EVERY schema via pg_class, not
// just public, and via pg_proc for the routines:
//
//   public.scenario_expectation_baseline    does not exist — no relation of that name in any schema
//   public.v_scenario_expectation_current   does not exist — no relation of that name in any schema
//   public.v_scenario_expectation_drift     does not exist — no relation of that name in any schema
//   public.scenario_expectation_change      does not exist — no relation of that name in any schema
//   public.fn_scenario_expectation_change   does not exist — 0 rows in pg_proc
//
// That is all three relations the single test read (42P01: relation
// "public.scenario_expectation_baseline" does not exist), plus the ledger and the ledger routine the
// header calls the actual defence.
//
// WHAT SURVIVES, AND WHY IT IS NOT A REPAIR TARGET. `scenario_tests` exists only as
// kb_stage.scenario_tests (3,324 rows) — a staging schema, not the public subject this check read —
// still carrying its trigger `scenario_expected_needs_ledger`. That trigger directs any writer to
// public.fn_scenario_expectation_change, which no longer exists, so the guard now refuses every edit
// rather than routing it: expectations there are frozen, not drifting. There is no baseline to
// compare them against in any case, and re-capturing one would mean rebuilding the ledger the
// founder deliberately deleted. Recommended to him, not done here.
//
// WHERE THE PROPERTY LIVES NOW. The scenarios that are actually run are
// scripts/checks/support_acceptance_scenarios.mjs, green at 103/103, and it carries its expectations
// INLINE — its own header: "EACH SCENARIO IS NAMED, AND THE EXPECTED VALUE IS WRITTEN BESIDE IT."
// An expected value committed to git beside its scenario cannot drift from a database baseline,
// because there is no database baseline; it drifts only in a diff a human reads. So the property is
// not lost, it moved into the suite and out of the estate.
//
// NOT SOFTENED, RETIRED. Nothing here was relaxed to make it green. Note in particular that the
// assertion this file was proudest of — that an EMPTY baseline is a failure and not a pass — would
// still be doing its job right up to the moment the table was dropped out from under it. It is
// retiring because its subject was deleted, which is the only legitimate way a check stops running.
//
// ORIGINAL HEADER FOLLOWS.
//
// A BACKSTOP FOR TWO GUARDS THAT ALREADY WORK — AND THE REASON THAT IS ALL IT IS.
//
// MEASURED 13 Aug 2026 while working through the tables nothing reads:
//
//   scenario_expectation_baseline   3,324 rows, one per scenario, captured 2 Aug
//   v_scenario_expectation_current  3,324 rows
//   v_scenario_expectation_drift    0 rows
//   scenario_expectation_change     2 rows
//
//   grep across the whole repository: src/ 0, supabase/functions/ 0, scripts/ 0.
//
// The first draft of this file said the obvious thing: a baseline nobody reads, so drift would
// appear tomorrow and nothing would notice. THAT WAS WRONG, and an aborted-transaction probe is
// what said so. Two triggers refused the probe in turn:
//
//   scenario_expectation_change is append-only: UPDATE is not permitted.
//   scenario_tests.expected cannot be changed directly — use
//     public.fn_scenario_expectation_change(scenario_id, new_expected, reason, work_item, changed_by).
//
// So unacknowledged drift is not merely unobserved, it is STRUCTURALLY IMPOSSIBLE through the
// normal path: the expectation cannot be edited without a ledger entry, and the drift view excludes
// exactly what the ledger acknowledges. The zero is earned at write time, loudly, by a guard.
//
// WHAT THIS CHECK IS THEREFORE FOR, stated narrowly so nobody later mistakes it for the defence:
// the trigger is the defence; this notices if the trigger stops being there. Drift can still arrive
// by a route that bypasses it — a restore, a migration run with session_replication_role set, a
// trigger dropped in a refactor, or a direct write to the baseline. Asserting zero costs one query
// and catches the case where the real guard has quietly gone.
//
// IT IS NOT A RATCHET AND HAS NO BASELINE OF ITS OWN. The correct number of drifted scenarios is
// zero. If that ever needs raising, the answer is to re-capture the baseline deliberately through
// the ledger, not to widen this.
//
//   node --test scripts/checks/scenario_expectation_drift.test.mjs
import { SUPABASE_TOKEN_FILE } from '../../lib/supabase_token.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const PROD = 'htdblwldjkcgjvmqkbeh';
// Same scoping as sql_files_match_live.test.mjs, for the same reason: this check has to READ
// PRODUCTION, and CI has no management token. Skipping loudly beats failing a build on a missing
// credential — the drift it looks for is created by a deliberate change and is caught the next time
// a session runs the sweep.
const LOCAL_TOKEN = SUPABASE_TOKEN_FILE;
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

const q = async (sql, attempt = 0) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  if (r.ok) return r.json();
  const body = (await r.text()).slice(0, 200);
  if ((r.status === 429 || r.status >= 500) && attempt < 8) {
    await new Promise((s) => setTimeout(s, 1200 * 2 ** attempt));
    return q(sql, attempt + 1);
  }
  throw new Error(`${r.status} ${body}`);
};

test('no scenario has drifted from its captured expectation', async (t) => {
  if (!token) {
    t.skip('no SUPABASE_ACCESS_TOKEN and no local access token, so production cannot be read. '
      + 'This check compares v_scenario_expectation_drift against zero; run it from a session that '
      + 'has the management token. It is not asserting anything here.');
    return;
  }

  const [counts] = await q(`select
      (select count(*) from public.scenario_expectation_baseline)  as baselined,
      (select count(*) from public.v_scenario_expectation_current) as current,
      (select count(*) from public.v_scenario_expectation_drift)   as drifted`);

  // A baseline that emptied is not a pass. If the table were truncated the drift view would also
  // return zero, and this check would go green over nothing at all — the exact failure mode of a
  // check that only ever asserts an absence.
  assert.ok(Number(counts.baselined) > 0,
    'scenario_expectation_baseline is EMPTY, so a drift count of zero means nothing was compared, '
    + 'not that nothing changed. Re-capture the baseline before trusting this check.');

  const drifted = Number(counts.drifted);
  if (drifted > 0) {
    const rows = await q(`select scenario_id from public.v_scenario_expectation_drift limit 10`);
    assert.fail(`${drifted} scenario(s) no longer match their captured expectation`
      + ` (baseline ${counts.baselined}, current ${counts.current}). First few: `
      + rows.map((r) => r.scenario_id).join(', ')
      + '. Either a change to the estate altered what these scenarios produce — in which case find'
      + ' out why before re-capturing — or the baseline is deliberately stale and should be'
      + ' re-captured on purpose.');
  }

  console.log(`scenario expectations: ${counts.baselined} baselined, ${counts.current} current, ${drifted} drifted`);
});
