// AN INVITED SUPPLIER IS GUIDED THROUGH THE REGISTRATION FORM (11 Nov 2026, customer_support). Supplier registration certification
// (founder ruling 1620), free round, finding 7: Verify on an invitation claims the listed company, so the dashboard never answered
// no_company and the supplier landed in the workspace ("Pending", profile score 0/100). He had to finish in three places: the
// Documents tab, then Profile inside the Account menu, then Services, with nothing on screen saying what was left to register.
// No founder ruling names the invitation's screens (public.founder_instruction searched 11 Nov 2026), so the invitation door now
// leads through the SAME guided registration as the public door: the registration form, then Submit, then the workspace.
//
// What fails if the cause returns:
//   * Dashboard opens the registration only for an account with no company again (the invited listing skips it);
//   * the decision stops reading whether the registration was SUBMITTED (registration_submitted / registration_submitted_at);
//   * the public door's Onboarding reads `me` again after the dashboard answered (finding 9: three calls in series);
//   * the dashboard card stops carrying registration_submitted, or supplier_portal stops selecting the column.
// It reads source only (no network, no secret).
//   node --test scripts/checks/an_invited_supplier_is_guided_through_the_registration_form.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const R = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const code = (s) => s.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, ' ');   // a comment naming the shape must not satisfy the check
const DASH = code(R('src/components/portal/supplier/core/Dashboard.tsx'));
const ONB = code(R('src/components/portal/supplier/core/Onboarding.tsx'));
const SESSION = code(R('src/components/portal/supplier/core/session.ts'));

test('a company that has not submitted its registration is shown the registration form, invited or not', () => {
  assert.match(DASH, /const fromOv = ov && ov\.supplier && typeof ov\.supplier\.registration_submitted === 'boolean' \? \(ov\.supplier\.approval_status !== 'approved' && !ov\.supplier\.registration_submitted\) : null;/);
  assert.match(DASH, /const fromMe = me \? \(me\.approval_status !== 'approved' && !me\.registration_submitted_at\) : null;/);
  assert.match(DASH, /if \(registering && !needsReaccept\(me\)\) return <Onboarding [^\n]*?\binvited\b[^\n]*?onDone=\{registered\} \/>;/, 'the guided form');
  // it is decided BEFORE the workspace renders, so the workspace never flashes first
  assert.ok(DASH.indexOf('if (registering &&') < DASH.indexOf("const unread = (ov.notifications"), 'the guided form must be decided before the workspace');
  // and Submit leads to the workspace: the dashboard is read again and the stale card dropped
  assert.match(DASH, /const registered = \(\) => \{ setErr\(''\); setOv\(null\); setMe\(undefined\); load\(\); \};/);
});

test('the guided form is the registration form, with what we hold about the invited company', () => {
  assert.match(ONB, /invited && me \? t\(lang, 'finish_title'\) \+ ' ' \+ me\.company_name/);
  // 12 Nov 2026 (review of #1984, c1): the form also tells the dashboard when the mobile is verified (onVerified), so its checklist re-reads
  assert.match(ONB, /<ProfileForm token=\{token\} me=\{me\} onSaved=\{onDone\} lang=\{lang\} onVerified=\{onVerified\} \/>/, 'register mode: the licence, profile, mobile, agreement and Submit');
  assert.match(R('src/components/portal/supplier/core/copy.ts'), /finish_title:'Finish registering'/);
});

test('the public door does not read me again after the dashboard answered (finding 9)', () => {
  assert.match(ONB, /useEffect\(\(\) => \{ if \(initial === undefined\) load\(\); \}, \[\]\);/, 'Onboarding reads its own me only when none was handed to it');
  assert.match(DASH, /if \(err === 'no_company'\) return <Onboarding [^\n]*?initial=\{meRead === false \? undefined : meRead\}/, 'the dashboard\'s no_company hands over the me already read');
  assert.match(DASH, /if \(meRead === null\) return <Onboarding [^\n]*?initial=\{null\}/, 'no company is known from whichever of the two answers lands first');
  // 11 Nov 2026 (free round 6): except when sign-in said there is no company yet, whose `me` would only say so again
  // (src/lib/supplierRegistrationReads.test.mjs holds that exception).
  assert.match(SESSION, /const warmSupplier = \(tk: string, withMe = true\) => \{ warm\(tk, DASH_KEY, \(\) => fetchDashboard\(tk\)\); if \(withMe\) warm\(tk, ME_KEY, \(\) => fetchMe\(tk\)\); \};/, 'me starts with the token, beside the dashboard');
  assert.match(DASH, /take\(token, ME_KEY, \(\) => fetchMe\(token\)\)/, 'the first me read takes the warmed one');
});

test('the dashboard card says whether the registration was submitted', () => {
  const ov = code(R('supabase/functions/supplier_portal/overview.ts'));
  assert.match(ov, /registration_submitted: !!sup\.registration_submitted_at/);
  const idx = R('supabase/functions/supplier_portal/index.ts');
  const sel = /from\('leads'\)\.select\('([^']*)'\)\.eq\('claimed_by', email\)/.exec(idx);
  assert.ok(sel && sel[1].split(',').includes('registration_submitted_at'), 'supplier_portal must select registration_submitted_at');
});
