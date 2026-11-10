// A SUPPLIER AGREEMENT THAT DID NOT LAND IS SIGNED AGAIN, AND THE PORTAL SAYS "SIGNING" (10 Nov 2026, seat: sales_engineer).
//
// Measured 10 Nov 2026 (docs/reports/2026-11-10-launch-verification.md, should-fix 4): the signed agreement is rendered by ONE
// pg_net post from z21_sign_supplier_on_acceptance; in 1 of 13 fixtures it had not landed after 60 s, and nothing posted again,
// so a supplier with nothing left to do sat "Action required: Signed supplier terms". What fails if that comes back:
//   * the minute sweep loses its schedule, its owner, its 5-minute wait, its 3-attempt cap or its per-acceptance count
//     (the first draft compared detail->>'accepted_terms_at' to timestamptz::text, which never matched: unlimited re-signs);
//   * the supplier card stops sending agreement_signing, or the header shows the red badge while it is signing.
// The rolled-back production proof is the probe a_supplier_agreement_that_did_not_land_is_signed_again_probe.sql.
//   node --test scripts/checks/a_supplier_agreement_that_did_not_land_is_signed_again.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const SQL = R('scripts/sql/a_supplier_agreement_that_did_not_land_is_signed_again.sql');
const body = SQL.slice(SQL.indexOf('create or replace function public.fn_sales_engineer_resigns_unsigned_agreements'), SQL.indexOf('$fn$;'));

test('the sweep re-signs an acceptance with no certificate after 5 minutes, at most 3 times, 5 minutes apart', () => {
  assert.match(body, /l\.accepted_terms_at < now\(\) - interval '5 minutes'/);
  assert.match(body, /signed_terms_path is null or l\.signed_terms_at is null or l\.signed_terms_at < l\.accepted_terms_at/,
    'a certificate of an earlier acceptance must not count as signing this one');
  assert.match(body, /if v_prior >= 3 then/);
  assert.match(body, /v_last > now\(\) - interval '5 minutes'/);
  assert.match(body, /'action', 'sign', 'kind', 'supplier', 'email', r\.claimed_by/, 'the same request qd_sign_supplier posts');
  // the per-acceptance count compares timestamps, never a timestamp's text to JSON's ISO text
  assert.match(body, /\(a\.detail ->> 'accepted_terms_at'\)::timestamptz = r\.accepted_terms_at/);
  assert.doesNotMatch(body, /'accepted_terms_at' = r\.accepted_terms_at::text/);
});

test('the sweep is scheduled every minute, owned by the sales engineer, and closed to anon and authenticated', () => {
  assert.match(SQL, /cron\.schedule\('sales_engineer_agreement_resign', '\* \* \* \* \*'/);
  assert.match(SQL, /\('cron_job', 'sales_engineer_agreement_resign', 'sales_engineer'/);
  assert.match(SQL, /revoke execute on function public\.fn_sales_engineer_resigns_unsigned_agreements\(bigint\) from public, anon, authenticated;/);
  assert.match(SQL, /set search_path to 'public', 'pg_temp'/);
});

test('the portal is told the agreement is signing, and says so instead of "Action required"', () => {
  const idx = R('supabase/functions/supplier_portal/index.ts');
  const ov = R('supabase/functions/supplier_portal/overview.ts');
  const dash = R('src/components/portal/supplier/core/Dashboard.tsx');
  const copy = R('src/components/portal/supplier/core/copy.ts');
  assert.match(idx, /select\('id,company_name,approval_status,[^']*accepted_terms_at,signed_terms_at'\)/);
  assert.match(ov, /agreement_signing: agreementSigning\(sup\)/);
  assert.match(dash, /if \(signingOnly\) return <Badge variant="warn">\{t\(lang, 'agreement_signing'\)\}<\/Badge>;/);
  assert.match(dash, /\{!signingOnly && \(ov\.supplier\.approval_status === 'action_required'/, 'the red "Why" line must not show while signing');
  assert.match(dash, /setInterval\(\(\) => \{ if \(\+\+n > 40\) clearInterval\(id\); else load\(\); \}, 15000\)/, 'the header refreshes itself while signing');
  assert.equal((copy.match(/agreement_signing:'/g) || []).length, 2, 'English and Arabic');
});
