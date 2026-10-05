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

test('the hard spend cap defaults to USD 15 and is checked before and after every scenario', () => {
  assert.match(src, /Number\(val\('--cap-usd'\) \|\| 15\)/);
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

test('the sandbox tag on a cost row is kept only for an open harness run', () => {
  const sql = readFileSync(new URL('../sql/a_sandbox_run_tags_its_own_model_cost.sql', import.meta.url), 'utf8');
  assert.match(sql, /w\.run_tag = 'qd_run:' \|\| v_tag and w\.ended_at is null/);
  assert.match(sql, /revoke execute on function public\.fn_ai_cost_log_e2e_run_tag\(\) from public, anon, authenticated/);
});

test('the coverage classifier never calls an unknown feature tested', () => {
  const out = classify([{ kind: 'action', id: 'no_such_function.no_such_action' }, { kind: 'notice', id: 'no_such_notice' }]);
  assert.deepEqual(out.map((o) => o.status), ['uncovered', 'uncovered']);
  for (const [, , reason] of JUSTIFIED) assert.ok(reason.length > 40, 'every justification is a written reason');
  assert.ok(TESTED.every(([, , s]) => /^S\d\d$/.test(s)));
});
