// THE PRE-LAUNCH DOORS STAY SHUT (it_engineer, pre-launch security pass, 6 Oct 2026).
// Each test fails if the cause of one finding returns. The sign-in code race (H1) has its own check
// against a real Postgres: supabase/functions/login_otp/verify_race.check.ts.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const strip = (s) => s.replace(/^\s*\/\/.*$/gm, '');

test('M1: the sign-in limiter refuses when it cannot answer', () => {
  const src = strip(read('supabase/functions/login_otp/index.ts'));
  const rl = src.slice(src.indexOf('async function rl('), src.indexOf('const LIMITER_DOWN'));
  assert.ok(!/return true/.test(rl), 'rl() must never answer "allowed" on a limiter error');
  assert.match(rl, /return 'down'/);
  assert.equal((src.match(/=== ["']down["']/g) || []).length >= 3, true, 'every rl() caller must refuse on down');
  assert.match(src, /return J\(LIMITER_DOWN, 503\)/);
});

test('M3: role_guard looks nothing up and gives one answer', () => {
  const src = strip(read('supabase/functions/role_guard/index.ts'));
  assert.ok(!/from\('(leads|customers)'\)/.test(src), 'role_guard must not read an account table');
  assert.ok(!/conflict: (?!null)/.test(src), 'role_guard must only ever answer conflict: null');
  assert.match(read('supabase/functions/login_otp/index.ts'), /const conflict = await roleConflict\(kind, email\);/);
});

test('L6: every endpoint that returns personal data answers only the site origins', () => {
  const fns = ['login_otp', 'mobile_otp', 'kyc', 'customer_api', 'customer_portal', 'customer_documents', 'customer_intelligence',
    'reveal_invoice', 'refund_flow', 'refunds_api', 'supplier_api', 'supplier_portal', 'supplier_pay', 'messages_api', 'procurement_api',
    'project_api', 'quote_compare', 'stripe_checkout', 'stripe_confirm', 'claim_lookup', 'complaint_status', 'role_guard',
    'supplier_onboard', 'supplier_catalog_ingest', 'transcribe', 'inquiry_intake'];
  for (const f of fns) assert.match(read(`supabase/functions/${f}/index.ts`), /Deno\.serve\(siteCors\(/, f + ' is not wrapped in siteCors');
  const so = read('supabase/functions/_shared/site_origins.ts');
  assert.match(so, /headers\.delete\('Access-Control-Allow-Origin'\)/);
});
