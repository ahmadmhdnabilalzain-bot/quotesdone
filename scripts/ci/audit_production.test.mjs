// node --test scripts/ci/audit_production.test.mjs  (offline: no npm call)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { auditFindings, coversNewest } from './audit_production.mjs';

const adv = (id, severity, range = '<=4.0.7') => ({ url: `https://github.com/advisories/${id}`, severity, range, title: 't' });
const EX = [{ advisory: 'GHSA-fc5q-39xc-vjpf', package: 'picomatch', expires: '2026-12-01', via: ['@parcel/watcher'] }];
const report = (vulns) => ({ vulnerabilities: vulns });
const newest = (v) => () => v;

test('the named advisory with no fix yet passes, until it expires', () => {
  const r = report({ picomatch: { via: [adv('GHSA-fc5q-39xc-vjpf', 'high')], nodes: ['node_modules/@parcel/watcher/node_modules/picomatch'] }, '@parcel/watcher': { via: ['picomatch'] } });
  assert.deepEqual(auditFindings(r, EX, '2026-11-17', newest('4.0.7')), []);
  assert.match(auditFindings(r, EX, '2026-12-02', newest('4.0.7')).join(), /expired/);
});

test('a published fix ends the exception', () => {
  const r = report({ picomatch: { via: [adv('GHSA-fc5q-39xc-vjpf', 'high')], nodes: ['node_modules/@parcel/watcher/node_modules/picomatch'] } });
  assert.match(auditFindings(r, EX, '2026-11-17', newest('4.0.8')).join(), /a fix exists/);
});

test('any other HIGH or CRITICAL advisory fails, even on the same package; a moderate one does not', () => {
  const r = report({ picomatch: { via: [adv('GHSA-fc5q-39xc-vjpf', 'high'), adv('GHSA-other', 'critical')], nodes: ['node_modules/@parcel/watcher/node_modules/picomatch'] }, lodash: { via: [adv('GHSA-x', 'high')] }, minimist: { via: [adv('GHSA-m', 'moderate')] } });
  const f = auditFindings(r, EX, '2026-11-17', newest('4.0.7'));
  assert.equal(f.length, 2);
  assert.match(f.join(), /GHSA-other/); assert.match(f.join(), /GHSA-x/);
});

test('an exception that is no longer reported must be deleted', () => {
  assert.match(auditFindings(report({}), EX, '2026-11-17', newest('4.0.7')).join(), /no longer reported/);
});

test('ranges', () => {
  assert.equal(coversNewest('<=4.0.7', '4.0.7'), true);
  assert.equal(coversNewest('<=4.0.7', '4.0.8'), false);
  assert.equal(coversNewest('<4.0.7', '4.0.7'), false);
  assert.equal(coversNewest('4.0.0 - 4.0.7', '4.1.0'), false);
  assert.equal(coversNewest('*', '9.9.9'), true);
});

test('the excused advisory reached by any other route fails', () => {
  const r = report({ picomatch: { via: [adv('GHSA-fc5q-39xc-vjpf', 'high')], nodes: ['node_modules/@parcel/watcher/node_modules/picomatch', 'node_modules/picomatch'] } });
  assert.match(auditFindings(r, EX, '2026-11-17', newest('4.0.7')).join(), /outside the excused route/);
});

test('a failed audit is never a pass (the script exits 1 on no report)', async () => {
  const src = (await import('node:fs')).readFileSync(new URL('./audit_production.mjs', import.meta.url), 'utf8');
  assert.match(src, /if \(!report \|\| report\.error \|\| !report\.metadata\)/);
});
