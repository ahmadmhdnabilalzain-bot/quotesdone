// SUPPLIER PROFILE SCORE (T3, sales_engineer). Fails if the score stops adding to 100 when complete,
// stops ranking the fixes by value, points a fix at a tab that does not exist, or the panel leaves the portal.
//   node --test scripts/checks/supplier_profile_score.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { profileScore } from '../../src/components/portal/supplier/profileScore.ts';
import { readSupplierPortal } from '../lib/portal_sources.mjs';

const FULL = {
  license_doc_path: 'x.pdf', trade_license_no: '1', license_expiry: '2027-06-24', company_profile_doc_path: 'p.pdf',
  description: 'ZZ DEMO '.repeat(12), products: ['steel'], catalog_doc_paths: ['c.pdf'], certifications: ['ISO 9001'], service_emirates: ['Dubai'],
};
const OK = { blocking: [] };

test('a complete, current profile scores 100 with nothing to fix', () => {
  const r = profileScore(FULL, OK, '2026-10-04');
  assert.equal(r.score, 100);
  assert.equal(r.todo.length, 0);
  assert.equal(r.items.reduce((s, i) => s + i.points, 0), 100);
});

test('an empty profile scores 0 and the fixes are ranked by value', () => {
  const r = profileScore({}, { blocking: [{ code: 'scope_unconfirmed' }] }, '2026-10-04');
  assert.equal(r.score, 0);
  for (let i = 1; i < r.todo.length; i++) assert.ok(r.todo[i - 1].points >= r.todo[i].points);
  assert.equal(r.todo[0].key, 'licence');
});

test('an expired licence costs its points and links to Documents', () => {
  const r = profileScore({ ...FULL, license_expiry: '2026-01-01' }, OK, '2026-10-04');
  assert.equal(r.score, 85);
  assert.deepEqual(r.todo.map((i) => [i.key, i.tab]), [['licence_current', 'documents']]);
});

test('an unconfirmed scope links to Services; no eligibility read does not count as confirmed', () => {
  assert.equal(profileScore(FULL, { blocking: [{ code: 'scope_unconfirmed' }] }, '2026-10-04').todo[0].tab, 'services');
  assert.equal(profileScore(FULL, null, '2026-10-04').score, 85);
});

test('every fix names a real portal tab, labels are English only, and the panel is on the portal', () => {
  const portal = readSupplierPortal();
  const tabs = portal.match(/const MAIN_TABS = \[([^\]]*)\]/)[1] + portal.match(/const ACCOUNT_TABS = \[([^\]]*)\]/)[1];
  for (const i of profileScore({}, null).items) {
    assert.ok(tabs.includes(`'${i.tab}'`), i.tab);
    assert.ok(!/[؀-ۿ]/.test(i.label), i.key);
  }
  assert.match(portal, /<ProfileScore me=\{me\} eligibility=\{ov\.eligibility/);
  assert.ok(!/[؀-ۿ]/.test(readFileSync(new URL('../../src/components/portal/supplier/ProfileScore.tsx', import.meta.url), 'utf8')));
});

// Walk of 12 Nov 2026, B1: where he works is one list, set on Services; the fix points there, in Services' words.
test('the emirates fix points at Services, where the list is set', () => {
  const r = profileScore({ ...FULL, service_emirates: [] }, OK, '2026-10-04');
  assert.deepEqual(r.todo.map((i) => [i.key, i.tab, i.label]), [['emirates', 'services', 'Choose where you work']]);
});
