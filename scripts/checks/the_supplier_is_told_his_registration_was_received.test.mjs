// THE SUPPLIER IS TOLD HIS REGISTRATION WAS RECEIVED, AND THE STEP LEFT HAS ONE NAME (12 Nov 2026, customer_support; founder ruling
// 1645, browser perfection walk of supplier registration, findings H9 and M12). After Submit nothing said "received"; a nine-line red
// paragraph ("Why: your registration is complete except one step: …") headed every tab; the step was called "Confirm your scope",
// "Confirm my scope", "Confirm the services you offer" and "confirmed what your company does"; Documents said "Your trade licence is on
// hold - see the notice on your overview" beside a licence marked Valid, and "Not eligible yet" in red.
// Local render after the fix: the card reads "Registration received. One step left: confirm your services." (16.7:1 and 8.9:1), no
// red line on any tab, and the checklist "1 step left", "Next step: Confirm your services.", button "Confirm your services →".
//   node --test scripts/checks/the_supplier_is_told_his_registration_was_received.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const R = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const DASH = R('src/components/portal/supplier/core/Dashboard.tsx');
const GM = R('src/components/portal/supplier/GetMatched.tsx');
const SCORE = R('src/components/portal/supplier/profileScore.ts');
const COPY = R('src/components/portal/supplier/serverCopy.ts');
const BADGES = R('supabase/functions/_shared/verified_badges.ts');

test('a submitted registration gets one calm card with one button to the step left', () => {
  assert.match(DASH, /const RECEIVED = 'Registration received\.';/);
  assert.match(DASH, /const ONE_STEP = 'One step left: confirm your services\.';/);
  assert.match(DASH, /\{received \? <RegistrationReceived servicesLeft=\{servicesLeft\} onServices=\{tab === 'services' \? null : \(\) => go\('services'\)\} \/> : null\}/);
  const card = DASH.slice(DASH.indexOf('function RegistrationReceived'), DASH.indexOf('function WorkspaceOutline'));
  assert.doesNotMatch(card, /destructive|danger|text-red/, 'the received card is coloured as an error');
  assert.equal((card.match(/<Button/g) || []).length, 1, 'one button, to the one step');
});

test('the services step is no longer a red hold line; only action_required is red', () => {
  assert.match(DASH, /\{!signingOnly && !servicesLeft && \(/);
  assert.match(DASH, /ov\.supplier\.approval_status === 'action_required' \? 'text-destructive' : 'text-warn'/);
  assert.doesNotMatch(DASH, /<span className="text-\[13px\] text-destructive font-medium basis-full">/);
});

test('the step left has one name everywhere a supplier reads it: "Confirm your services"', () => {
  assert.match(GM, /const SERVICES_STEP = 'Confirm your services';/);
  assert.match(GM, /\{ code: 'scope', label: SERVICES_STEP, done: !scopeOpen, fix: 'services' \}/);
  assert.match(SCORE, /label: 'Confirm your services'/);
  assert.match(COPY, /scope_unconfirmed_title: s\('Confirm your services'/);
  assert.match(BADGES, /services_unconfirmed: 'Confirm your services on the Services tab'/);
  for (const [name, src] of [['GetMatched', GM], ['profileScore', SCORE], ['serverCopy', COPY]]) {
    assert.doesNotMatch(src, /'Confirm (your|my) scope'|'Confirm the services you offer'|'Not eligible yet'/, `${name} still uses another name`);
  }
  assert.doesNotMatch(BADGES, /see the notice on your overview/, 'a hold points at an overview the portal does not have');
});

test('a company renamed from its licence is told so under its name (M13)', () => {
  assert.match(DASH, /ov\.supplier\.name_from_licence \? <p data-testid="name-from-licence"/);
  assert.match(DASH, /const NAME_FROM_LICENCE = 'Your company name is shown as it is printed on your trade licence\.';/);
});
