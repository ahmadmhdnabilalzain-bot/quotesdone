// it_engineer — proves the launch load test cannot reach production or a real person.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { assertFixture, assertTarget, makeIdentity, summarise } from './launch_load_test.mjs';

const script = fileURLToPath(new URL('./launch_load_test.mjs', import.meta.url));
const sandbox = { QD_LOADTEST: '1', QD_LOADTEST_BASE_URL: 'https://sandboxref.supabase.co' };

test('--run refuses without QD_LOADTEST=1 (prevented by:)', () => {
  const env = { ...process.env, QD_LOADTEST: '', QD_LOADTEST_BASE_URL: sandbox.QD_LOADTEST_BASE_URL };
  const r = spawnSync(process.execPath, [script, '--run'], { env, encoding: 'utf8' });
  assert.equal(r.status, 2);
  assert.match(r.stderr, /prevented by: QD_LOADTEST is not 1/);
  assert.throws(() => assertTarget({ QD_LOADTEST_BASE_URL: 'x' }), /prevented by: QD_LOADTEST is not 1/);
});

test('refuses a non-example.invalid address (prevented by:)', () => {
  assert.throws(() => assertFixture({ name: 'ZZ DEMO — x', email: 'buyer@gmail.com' }), /prevented by: address "buyer@gmail.com" is not @example.invalid/);
  assert.throws(() => assertFixture({ name: 'ZZ DEMO — x', email: 'a@example.invalid.com' }), /prevented by:/);
  assert.throws(() => assertFixture({ name: 'Real Co', email: 'a@example.invalid' }), /prevented by: name "Real Co"/);
});

test('refuses the production project even with the flag', () => {
  assert.throws(() => assertTarget({ QD_LOADTEST: '1', QD_LOADTEST_BASE_URL: 'https://htdblwldjkcgjvmqkbeh.supabase.co' }), /prevented by: base URL is production/);
  assert.equal(assertTarget(sandbox), sandbox.QD_LOADTEST_BASE_URL);
});

test('every generated identity is a fixture', () => {
  for (const s of ['inquiry_intake', 'quote_submit', 'portal_read']) assert.doesNotThrow(() => makeIdentity(s, 7));
});

test('default is a dry run that sends nothing', () => {
  const out = execFileSync(process.execPath, [script], { env: { ...process.env, QD_LOADTEST: '' }, encoding: 'utf8' });
  assert.match(out, /dry run — nothing sent/);
});

test('summary reports p50/p95/error rate against the SLO', () => {
  const r = summarise('x', [{ ms: 100, ok: true }, { ms: 200, ok: true }, { ms: 900, ok: false }], 1000);
  assert.equal(r.p50, 200);
  assert.equal(r.p95, 900);
  assert.equal(r.pass, false); // 33% errors
});
