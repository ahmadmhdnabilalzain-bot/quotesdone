// The stage-2 sandbox run (scripts/e2e/stage2.mjs, ledger 1119) spends real model money on production
// with the hold lifted. These are the fences that keep it from costing more than the founder allowed,
// from reaching a real person, from taking a live card, and from leaving anything a seat could learn from.
//   node --test scripts/checks/the_stage2_sandbox_run_is_fenced.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { classify, TESTED, JUSTIFIED } from '../e2e/stage2_coverage.mjs';

const src = readFileSync(new URL('../e2e/stage2.mjs', import.meta.url), 'utf8');
const dry = src.slice(src.indexOf("if (MODE === '--dry-run')"), src.indexOf('// --run'));

test('the script cap defaults to USD 4, never above 15, and is checked before and after every scenario', () => {
  assert.match(src, /Number\(val\('--cap-usd'\) \|\| 4\)/);
  assert.match(src, /CAP_USD > 15\)/);
  assert.match(src, /spentUsd \+ est > CAP_USD/);
  assert.match(src, /spentUsd > CAP_USD\) \{ aborted = `HARD ABORT/);
});

test('the dry run calls no edge function and so no model', () => {
  assert.doesNotMatch(dry, /\bcall\(/);
  assert.doesNotMatch(dry, /realRun\(/);
});

test('the real run refuses while a precondition fails, and refuses a live Stripe key', () => {
  assert.match(src, /if \(!pre\.ok\) \{ console\.error\('\\nREFUSED/);
  assert.match(src, /startsWith\('sk_test_'\)\) throw new Error\('REFUSED/);
});

test('cleanup is scoped by the run tag and never purges the founder demo account', () => {
  assert.match(src, /tag === 'founderdemo'/);
  assert.match(src, /\^\[a-z0-9\]\{4,16\}\$/);
  // ai_cost_log: exactly the run's rows, by the tag the trigger stamps, never a time window.
  assert.match(src, /delete from public\.ai_cost_log where e2e_run_tag = /);
  assert.doesNotMatch(src, /delete from public\.ai_cost_log where id/);
  // the spend the cap counts is the run's own, never real traffic in the same minutes
  assert.match(src, /and e2e_run_tag = \$\{q\(RUN_TAG\)\}/);
});

test('a duty probe can never commit: it raises after measuring', () => {
  const d = readFileSync(new URL('../e2e/stage2_duties.mjs', import.meta.url), 'utf8');
  assert.match(d, /raise exception 'CHK<<%>>'/);
  assert.match(d, /the probe did not raise: it may have COMMITTED/);
});

const sql = readFileSync(new URL('../sql/a_sandbox_run_is_tagged_capped_and_let_through_only_inside_its_window.sql', import.meta.url), 'utf8');
const gate = sql.slice(sql.indexOf('CREATE OR REPLACE FUNCTION public.fn_kernel_paid_provider_gate'), sql.indexOf('end $function$;'));

test('a sandbox tag counts only for an open, unexpired, model-enabled window', () => {
  assert.match(sql, /w\.run_tag = 'qd_run:' \|\| p_tag and w\.ended_at is null and w\.models_allowed and w\.expires_at > now\(\)/);
  assert.match(sql, /check \(expires_at <= started_at \+ interval '2 hours 1 minute'\)/);
  assert.match(sql, /check \(cap_usd > 0 and cap_usd <= 15\)/);
  assert.match(sql, /add column if not exists models_allowed boolean not null default false/);
  for (const f of ['fn_e2e_run_tag_open(text)', 'fn_e2e_run_tag_current()', 'fn_ai_cost_log_e2e_run_tag()']) {
    assert.ok(sql.includes(`revoke execute on function public.${f} from public, anon, authenticated`), f);
  }
});

test('the gate: untagged traffic is untouched, tagged traffic is capped and passes only the hold', () => {
  // block 0 runs only for a tag; untagged calls never reach the cap or the window
  assert.match(gate, /if v_tag is not null then\s+if not coalesce\(public\.fn_e2e_run_tag_open\(v_tag\), false\)/);
  assert.match(gate, /'rule', 'rehearsal_cap'/);
  // the founder's hold still refuses everything that is not this run
  assert.match(gate, /if v_held > 0 and not v_rehearsal then/);
  // the no_paid_ai switch and a real (short) breaker still refuse a tagged call
  assert.doesNotMatch(gate.slice(gate.indexOf('-- 1. the explicit switch'), gate.indexOf('-- 2.')), /v_rehearsal/);
  assert.match(gate, /and not \(v_rehearsal and v_open > now\(\) \+ interval '365 days'\)/);
  // the file proves all four answers and must print PROBE OK at apply
  assert.match(sql, /PROBE OK: untagged=/);
});

test('the harness enables models for its own tag only, and always turns them off', () => {
  assert.match(src, /set models_allowed = true, cap_usd = \$\{Number\(CAP_USD\)\}, expires_at = now\(\) \+ interval '2 hours'/);
  assert.match(src, /finally \{\s+\/\/ ALWAYS: models off/);
  assert.match(src, /set models_allowed = false where run_tag/);
  // the script never touches the founder's hold
  assert.doesNotMatch(src, /update public\.llm_route_health/);
});

test('the coverage classifier never calls an unknown feature tested', () => {
  const out = classify([{ kind: 'action', id: 'no_such_function.no_such_action' }, { kind: 'notice', id: 'no_such_notice' }]);
  assert.deepEqual(out.map((o) => o.status), ['uncovered', 'uncovered']);
  for (const [, , reason] of JUSTIFIED) assert.ok(reason.length > 40, 'every justification is a written reason');
  assert.ok(TESTED.every(([, , s]) => /^S\d\d$/.test(s)));
});
