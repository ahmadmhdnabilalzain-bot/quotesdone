// THE CODE ANSWER SAYS WHETHER THE SUPPLIER HAS A COMPANY (11 Nov 2026, customer_support). Supplier registration certification
// (ruling 1620), second free round on production (02:57-03:41 UTC), J5 desktop: "the code verifies -> Register your company" took
// 3,401 ms against 3,000. The calls in the step: login_otp verify 1,750 ms, then supplier_api me 1,393 ms (beside kyc state and
// supplier_portal dashboard). The portal could only learn "no company yet" from a second call after the code was checked.
// login_otp's supplier branch already UPDATEs the caller's own claimed lead; the rows it touched say whether one exists, so the
// answer carries has_company at no extra round trip, and the portal opens "Register your company" from it at once (unless an
// invitation is being claimed, which makes a company). The dashboard's own reads still land and correct a stale hint.
// What fails if the cause returns: the verify answer loses has_company, the sign-in stops passing it on, the portal uses it while
// an invitation is being claimed, or the dashboard stops starting from it. Source only, no network.
//   node --test scripts/checks/the_code_answer_says_whether_the_supplier_has_a_company.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const R = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const code = (s) => s.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, ' ');

test('login_otp: the supplier branch reads whether its own update touched a company, and says so', () => {
  const s = code(R('supabase/functions/login_otp/index.ts'));
  assert.match(s, /const owned = await admin\.from\('leads'\)\.update\(\{ owner_email_verified: true \}\)\.eq\('claimed_by', email\)\.select\('id'\);/);
  assert.match(s, /if \(!owned\.error\) hasCompany = \(owned\.data \|\| \[\]\)\.length > 0;/);
  assert.match(s, /if \(hasCompany !== undefined\) Object\.assign\(s, \{ has_company: hasCompany \}\);\s*return J\(\{ ok: true, \.\.\.s,/, 'sent with the session, and never when unknown');
});

test('the portal opens the registration from it, never while an invitation is being claimed', () => {
  const login = code(R('src/components/portal/supplier/core/Login.tsx'));
  assert.match(login, /onAuth\(j\.access_token, j\.refresh_token, j\.locale, typeof j\.has_company === 'boolean' \? j\.has_company : undefined\)/);
  const portal = code(R('src/components/portal/SupplierPortal.tsx'));
  assert.match(portal, /claimPending = UUID_RE\.test\(sessionStorage\.getItem\(CLAIM_KEY\) \|\| ''\)/);
  assert.match(portal, /setNoCompanyYet\(hasCompany === false && !claimPending\);/);
  assert.match(portal, /<Dashboard [^\n]*noCompanyYet=\{noCompanyYet\}/);
  const dash = code(R('src/components/portal/supplier/core/Dashboard.tsx'));
  assert.match(dash, /const \[meRead, setMe\] = useState\(noCompanyYet \? null : undefined\);/);
  assert.match(dash, /if \(meRead === null\) return <Onboarding /, 'no company known opens the registration');
});
