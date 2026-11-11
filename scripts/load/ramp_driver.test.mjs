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

// A LIMITED ANSWER IS NOT AN ERROR (round 3, 11 Nov 2026): the 03:46 run stopped on 2 timeouts + 4 limited turns (3.3%).
test('limited answers stay out of the 2% error rule, are counted by bucket, and stop a run only past 5%', async () => {
  const { abortReason, summarise, LIMITED_ABORT_RATE } = await import('./ramp_driver.mjs');
  const turn = (cls, extra = {}) => ({ name: 'site_assistant turn', cls, ms: 10, status: 200, ...extra });
  const run3 = [...Array.from({ length: 175 }, () => turn('ok')), ...Array.from({ length: 4 }, () => turn('limited', { bucket: 'ip_new_conversation' })),
    turn('error', { status: null, err: 'TimeoutError' }), turn('error', { status: null, err: 'TimeoutError' })];
  assertEq(abortReason(run3), null, 'the 03:46 run: 2 errors in 181 is 1.1%, and 4 limited is 2.2%, under 5%');
  const s = summarise(run3)['site_assistant turn'];
  assertEq(s.limitedBy, { ip_new_conversation: 4 });
  const many = [...Array.from({ length: 90 }, () => turn('ok')), ...Array.from({ length: 10 }, () => turn('limited', { bucket: 'ip_hard' }))];
  assert.match(String(abortReason(many)), /limited share over 5%/);
  assert.equal(LIMITED_ABORT_RATE, 0.05);
  const errs = [...Array.from({ length: 95 }, () => turn('ok')), ...Array.from({ length: 3 }, () => turn('error'))];
  assert.match(String(abortReason(errs)), /error rate over 2%/);
});
function assertEq(a, b, m) { assert.deepEqual(a, b, m); }

test('the abort message names every rule that fired and the counts it saw (04:28 run, stage 100)', async () => {
  const { abortReason, vuLabel } = await import('./ramp_driver.mjs');
  const turn = (cls) => ({ name: 'site_assistant turn', cls, ms: 1, status: 200 });
  const at = [...Array.from({ length: 53 }, () => turn('ok')), ...Array.from({ length: 3 }, () => turn('error')), ...Array.from({ length: 25 }, () => turn('limited'))];
  const m = String(abortReason(at));
  assert.match(m, /^error rate over 2% and limited share over 5%/);
  assert.match(m, /3 errors \(3\.7%\) and 25 limited \(30\.9%\) of 81 turns when it fired/);
  assert.equal(vuLabel(100, 7), 's100-v7');
  assert.match(vuLabel(100, 7), /^[a-z0-9-]{1,32}$/, 'site_assistant accepts the label');
  const src = (await import('node:fs')).readFileSync(new URL('./chat_load_run.mjs', import.meta.url), 'utf8');
  assert.equal((src.match(/rl_hits where k like '\$\{loadLimiterKeys\(tag\)\}'/g) || []).length, 2, 'the teardown and its count use one pattern');
});
