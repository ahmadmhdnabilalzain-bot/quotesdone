// node --test src/lib/supplierRegistrationReads.test.mjs
// "Create company" opens the registration form on create_company's own answer, and sign-in with no company warms no `me`
// (customer_support, 11 Nov 2026; supplier registration certification free round 6, run 2 J1 desktop: 3,907 ms against
// 3,000, the step meeting create_company 1,810 ms then `me` 1,671 ms and `me` 1,581 ms).
// Known-bad controls: Onboarding calling `load` after create_company again (test 4 fails), onAuth warming `me` whatever
// has_company said (test 4), a Dashboard that reads `me` before the dashboard answers under the hint (test 2 and 4).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { readsMeNow, supplierFromCreate, warmsMe } from './supplierRegistrationReads.ts';

const ROOT = join(import.meta.dirname, '..', '..');
const src = (p) => readFileSync(join(ROOT, p), 'utf8').replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, ' ');

test('sign-in warms `me` unless the code answer said no company and no invitation is being claimed', () => {
  assert.equal(warmsMe({ hasCompany: false, claimPending: false }), false, 'its answer ("no company") is already known');
  assert.equal(warmsMe({ hasCompany: false, claimPending: true }), true, 'a claim gives him a company: `me` is needed');
  assert.equal(warmsMe({ hasCompany: true, claimPending: false }), true);
  assert.equal(warmsMe({ hasCompany: undefined, claimPending: false }), true, 'no hint (a refresh, a stored token): read as before');
});

test('under the "no company yet" hint the Dashboard reads `me` only once the dashboard has answered', () => {
  assert.equal(readsMeNow({ noCompanyYet: true, dashboardAnswered: false }), false);
  assert.equal(readsMeNow({ noCompanyYet: true, dashboardAnswered: true }), true, 'a wrong hint is corrected by the dashboard naming a supplier');
  assert.equal(readsMeNow({ noCompanyYet: false, dashboardAnswered: false }), true, 'without the hint `me` is read beside the dashboard, as before');
});

test('create_company\'s answer opens the form when it carries the supplier it wrote, and only then', () => {
  const s = { id: 900001, company_name: 'ZZ DEMO Reads LLC', terms_current: 'v17', terms_stands: false };
  assert.deepEqual(supplierFromCreate({ ok: true, id: 900001, registration: {}, supplier: s }), s);
  assert.equal(supplierFromCreate({ ok: true, id: 900001, registration: {} }), null, 'an older deployment: ask `me`');
  assert.equal(supplierFromCreate({ ok: true, id: 900001, supplier: { ...s, id: 5 } }), null, 'another row is never taken for his');
  assert.equal(supplierFromCreate({ ok: false, supplier: s }), null);
  assert.equal(supplierFromCreate(null), null);
  assert.equal(supplierFromCreate({ ok: true, id: 1, supplier: 'x' }), null);
});

test('the portal is wired to them: no `me` after create_company, none warmed at a no-company sign-in', () => {
  const onboarding = src('src/components/portal/supplier/core/Onboarding.tsx');
  assert.match(onboarding, /onReady=\{\(j\) => \{ const s = supplierFromCreate\(j\); if \(s\) setMe\(s\); else load\(\); \}\}/, 'Onboarding must open the form on create_company\'s supplier');
  assert.match(onboarding, /if \(j && j\.ok\) onReady\(j\)/, 'NewCompany must hand create_company\'s answer to onReady');
  assert.doesNotMatch(onboarding, /onReady=\{load\}/, 'Onboarding asks `me` again after create_company answered');
  const portal = src('src/components/portal/SupplierPortal.tsx');
  assert.match(portal, /warmSupplier\(access, warmsMe\(\{ hasCompany, claimPending \}\)\)/, 'onAuth must not warm `me` when sign-in said there is no company');
  const session = src('src/components/portal/supplier/core/session.ts');
  assert.match(session, /if \(withMe\) warm\(tk, ME_KEY/, 'warmSupplier must be able to leave `me` out');
  const dash = src('src/components/portal/supplier/core/Dashboard.tsx');
  assert.match(dash, /if \(readsMeNow\(\{ noCompanyYet, dashboardAnswered: !!ov \}\)\) loadMe\(\)/, 'Dashboard reads `me` before the dashboard answers under the hint');
});
