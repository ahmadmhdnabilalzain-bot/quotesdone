// it_engineer — the load tools of 11 Nov 2026 (ruling 1622) cannot spend, cannot reach a person, and stop on errors.
//   node --test scripts/load/ramp_driver.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ABORT_MIN_SAMPLES, assertRunnable, classify, pct, preflightVerdict, shouldAbort, spendVerdict, summarise, vuAddress } from './ramp_driver.mjs';
import { assertNothingLeft, parseProbe, probeSql } from './db_write_burst.mjs';

const FULL = { QD_LOAD_RUN_TAG: 'zzload1', QD_LOAD_RUN_SECRET: 'x', SUPABASE_ACCESS_TOKEN: 'x', QD_LOAD_GATEWAY_SECRET: 'x' };

test('nothing is sent without --run (prevented by:)', () => {
  assert.equal(assertRunnable('website', {}, []).dry, true);
  assert.equal(assertRunnable('chat', {}, []).dry, true);
});

test('the chat mix refuses without each of its proofs (prevented by:)', () => {
  for (const missing of Object.keys(FULL)) {
    const env = { ...FULL, [missing]: '' };
    assert.throws(() => assertRunnable('chat', env, ['--run']), /prevented by:/, missing);
  }
  assert.throws(() => assertRunnable('chat', { ...FULL, QD_LOAD_RUN_TAG: 'Bad Tag!' }, ['--run']), /QD_LOAD_RUN_TAG/);
  assert.equal(assertRunnable('chat', FULL, ['--run']).dry, false);
  assert.throws(() => assertRunnable('embed', {}, ['--run']), /QD_LOAD_EMBED_SECRET/);
  assert.throws(() => assertRunnable('nope', {}, ['--run']), /unknown mix/);
});

test('the chat mix runs only when the DEPLOYED gateway answers with the load stub', () => {
  // what the gateway deployed on 11 Nov 2026 answered (measured, no stub yet): refused
  assert.equal(preflightVerdict(503, { outcome: 'fixture_no_spend', cost_usd: 0 }).ok, false);
  assert.equal(preflightVerdict(503, { outcome: 'rehearsal_tag_unproven' }).ok, false);
  assert.equal(preflightVerdict(200, { outcome: 'generated', cost_usd: 0.002 }).ok, false, 'a real model answer is never accepted');
  assert.equal(preflightVerdict(200, { outcome: 'load_stub', cost_usd: 0 }).ok, true);
});

test('the spend guard aborts on any paid model or any cost', () => {
  assert.equal(spendVerdict([]).ok, true);
  assert.equal(spendVerdict([{ model_used: 'load_stub', cost_aed: '0' }, { model_used: 'none', cost_aed: 0 }]).ok, true);
  assert.equal(spendVerdict([{ model_used: 'anthropic/claude-sonnet-5.5', cost_aed: 0 }]).ok, false);
  assert.equal(spendVerdict([{ model_used: 'load_stub', cost_aed: '0.01' }]).ok, false);
  assert.equal(spendVerdict([{ model_used: 'none', cost_usd_reported: 0.001 }]).ok, false);
});

test('the abort rule: over 2% non-ok after 50 samples, 429 included', () => {
  const ok = (n) => Array.from({ length: n }, () => ({ cls: 'ok' }));
  assert.equal(shouldAbort([...ok(10), { cls: 'error' }]), false, 'too few samples to judge');
  assert.equal(shouldAbort([...ok(ABORT_MIN_SAMPLES - 1), { cls: 'error' }]), false, '1 in 50 is 2%, not over');
  assert.equal(shouldAbort([...ok(47), { cls: 'error' }, { cls: 'error' }, { cls: 'limited' }]), true);
  assert.equal(classify(429, null), 'limited');
  assert.equal(classify(546, null), 'error');
  assert.equal(classify(null, 'TimeoutError'), 'error');
  assert.equal(classify(404, null), 'ok', 'an answer the platform gave is served');
});

test('percentiles and the summary', () => {
  assert.equal(pct([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0.5), 5);
  assert.equal(pct([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0.95), 10);
  assert.equal(pct([], 0.5), null);
  const s = summarise([{ name: 'a', ms: 10, status: 200, cls: 'ok' }, { name: 'a', ms: 30, status: 546, cls: 'error' }]);
  assert.equal(s.a.errorRate, 0.5);
  assert.deepEqual(s.a.statuses, { 200: 1, 546: 1 });
});

test('a VU address is in the benchmarking block 198.18.0.0/15, never a real one', () => {
  for (const vu of [0, 1, 255, 256, 499]) assert.match(vuAddress(vu), /^198\.18\.\d{1,3}\.\d{1,3}$/);
});

test('every DB probe is a fixture that raises: it can only roll back', () => {
  const sql = probeSql(7, 'zzloadabc123');
  assert.match(sql, /raise exception 'CHK<<%>>'/);
  assert.match(sql, /qd-zzloadabc123-c7@example\.invalid/);
  assert.match(sql, /ZZ DEMO — load probe/);
  assert.doesNotMatch(sql, /\bcommit\b/i);
  assert.throws(() => probeSql(1, 'realrun'), /prevented by: the probe address is not a load fixture/);
  assert.deepEqual(parseProbe(JSON.stringify({ message: 'ERROR: P0001: CHK<<{"total_ms":90,"matches":0}>>' })), { total_ms: 90, matches: 0 });
  assert.equal(parseProbe('{"message":"ThrottlerException: Too Many Requests"}'), null);
  assert.equal(assertNothingLeft({ a: 1 }, { a: 1 }), true);
  assert.throws(() => assertNothingLeft({ load_customers: 0 }, { load_customers: 1 }), /left something behind/);
});

// THE WIDGET'S BUSY RETRY (11 Nov 2026): a shed attempt is retried, so it is neither an error nor a turn in the abort rule.
test('a shed attempt never trips the 2% rule; a turn that stays busy after every try does', () => {
  const ok = Array.from({ length: 60 }, () => ({ name: 'site_assistant turn', cls: 'ok', ms: 10, status: 200 }));
  const shed = Array.from({ length: 40 }, () => ({ name: 'site_assistant shed', cls: 'shed', ms: 5, status: 200 }));
  assert.equal(shouldAbort([...ok, ...shed]), false);
  const failed = Array.from({ length: 3 }, () => ({ name: 'site_assistant turn', cls: 'error', ms: 5, status: 200, err: 'busy after 4 tries' }));
  assert.equal(shouldAbort([...ok, ...shed, ...failed]), true, '3 of 63 turns is over 2%');
  const s = summarise([...ok, ...shed]);
  assert.equal(s['site_assistant shed'].shed, 40);
  assert.equal(s['site_assistant turn'].errorRate, 0);
});
