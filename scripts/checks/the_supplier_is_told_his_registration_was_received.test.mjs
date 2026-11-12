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
import { readFileSync, readdirSync } from 'node:fs';
import * as RR from '../../src/components/portal/supplier/registrationReceived.ts';

const R = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const DASH = R('src/components/portal/supplier/core/Dashboard.tsx');
const GM = R('src/components/portal/supplier/GetMatched.tsx');
const SCORE = R('src/components/portal/supplier/profileScore.ts');
const COPY = R('src/components/portal/supplier/serverCopy.ts');
const BADGES = R('supabase/functions/_shared/verified_badges.ts');

test('a submitted registration gets one calm card with one button to the step left', () => {
  assert.match(DASH, /\{receivedCard \? <RegistrationReceived card=\{receivedCard\} onServices=\{tab === 'services' \? null : \(\) => go\('services'\)\} \/> : null\}/);
  const card = DASH.slice(DASH.indexOf('function RegistrationReceived'), DASH.indexOf('function WorkspaceOutline'));
  assert.doesNotMatch(card, /destructive|danger|text-red/, 'the received card is coloured as an error');
  assert.equal((card.match(/<Button/g) || []).length, 1, 'one button, to the one step');
});

// EVERY HOLD REASON THE GATE WRITES (review of 12 Nov 2026: the first version told a supplier held for an unread licence expiry
// "Nothing is needed from you" under the line asking for a clearer copy). The reasons are read from the gate routine itself
// (fn_sales_engineer_verifies_supplier in supabase/schema/full_schema: every `v_reason := '...'`), never listed by hand here.
const SCHEMA = readdirSync(new URL('../../supabase/schema/full_schema/', import.meta.url)).filter((f) => f.endsWith('.sql'))
  .map((f) => R('supabase/schema/full_schema/' + f)).join('\n');
const GATE = (() => { const i = SCHEMA.indexOf('FUNCTION public.fn_sales_engineer_verifies_supplier('); return SCHEMA.slice(i, SCHEMA.indexOf('$function$;', SCHEMA.indexOf('$function$', i) + 10)); })();
const REASONS = [...new Set([...GATE.matchAll(/v_reason := '([a-z_]+)'/g)].map((m) => m[1]))];
const NOTHING = new Set(['licence_being_read', 'documents_being_read']);
const GATE_ALL = GATE;

test('the gate routine was found and writes the reasons this check reads', () => {
  assert.ok(GATE.length > 1000, 'fn_sales_engineer_verifies_supplier not found in the schema dump');
  assert.ok(REASONS.length >= 10 && REASONS.includes('services_unconfirmed') && REASONS.includes('licence_expiry_unread'), REASONS.join(','));
});

test('for every reason the gate writes, the card says nothing is needed only when nothing is', () => {
  const base = { approvalStatus: 'pending', submitted: true, signingOnly: false, scopeOpen: false };
  for (const reason of REASONS) {
    const c = RR.registrationReceived({ ...base, reason });
    assert.ok(c, reason + ': no card for a pending submitted registration');
    const text = c.text(false);
    if (reason === 'services_unconfirmed') assert.equal(text, RR.ONE_STEP, reason);
    else if (NOTHING.has(reason)) assert.equal(text, RR.NOTHING_NEEDED, reason);
    else assert.equal(text, RR.ONE_THING_NEEDED, reason + ' asks the supplier for something; the card must not say nothing is needed');
  }
  assert.equal(RR.registrationReceived({ ...base, reason: null }).text(false), RR.NOTHING_NEEDED, 'no reason');
  assert.equal(RR.registrationReceived({ ...base, reason: 'reg_terms', signingOnly: true }).text(false), RR.NOTHING_NEEDED, 'signing only');
  assert.equal(RR.registrationReceived({ ...base, reason: 'reg_terms', signingOnly: true, scopeOpen: true }).text(true), RR.ONE_STEP_HERE);
});

test('the card is shown only to a submitted registration that is pending: never approved, rejected or action_required', () => {
  for (const st of ['approved', 'rejected', 'action_required', 'suspended']) assert.equal(RR.registrationReceived({ approvalStatus: st, submitted: true, reason: null, signingOnly: false, scopeOpen: false }), null, st);
  assert.equal(RR.registrationReceived({ approvalStatus: 'pending', submitted: false, reason: null, signingOnly: false, scopeOpen: false }), null, 'not submitted');
  assert.ok(RR.registrationReceived({ approvalStatus: null, submitted: true, reason: null, signingOnly: false, scopeOpen: false }), 'null status');
});

test('the services step is no longer a red hold line; only action_required is red', () => {
  assert.match(DASH, /\)\) && !servicesLeft && ov\.supplier\.licence_gate_reason/, 'the services step is printed as a hold line again');
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

// A REJECTED REGISTRATION IS NEVER A DEAD END (round-2 review, 12 Nov 2026). The card says it was not approved, the reason in words
// when the dashboard carries one (never the code), and where to write. The codes are read from the gate and from the six-item
// routine it reads the missing items from, never listed by hand.
const SIX = (() => { const i = SCHEMA.indexOf('FUNCTION public.fn_supplier_mandatory_six('); return SCHEMA.slice(i, SCHEMA.indexOf('CREATE OR REPLACE FUNCTION', i + 10)); })();
const MISSING_CODES = [...new Set([...SIX.matchAll(/'(reg_[a-z_]+)'/g)].map((m) => m[1]))];
const english = (code) => { const m = new RegExp('^\\s*' + code + ": s\\((?:'([^']*)'|([A-Z_]+))", 'm').exec(COPY); return m ? (m[1] ?? m[2]) : null; };

test('every reason a rejected registration can carry has English words in serverCopy, so its code is never shown', () => {
  assert.ok(MISSING_CODES.length >= 5, 'fn_supplier_mandatory_six not read: ' + MISSING_CODES.join(','));
  for (const code of [...REASONS, ...MISSING_CODES, 'no_licence', 'licence_expired']) assert.ok(english(code), code + ' has no English wording in serverCopy.ts');
});

test('the rejected card: not approved, every missing item, how to reopen only when it reopens, and where to write', () => {
  assert.match(DASH, /<RegistrationNotApproved lines=\{rejectedLines\(\{ missing: ov\.supplier\.rejected_missing, reason: ov\.supplier\.licence_gate_reason \}, \(c\) => srvText\(lang, c, \{\}, ''\)\)\} \/>/);
  const card = DASH.slice(DASH.indexOf('function RegistrationNotApproved'), DASH.indexOf('// M15: the workspace'));
  assert.match(card, /NOT_APPROVED/); assert.match(card, /mailto:/);
  assert.match(card, /-my-3 inline-block py-3/, 'the mailto link lost its 44 px tap height (review note b)');
  assert.match(RR.REJECTED_NEXT, /management@quotesdone\.com/);
  // The reopen sentence is true only for a registration closed for being incomplete, and only by saving the profile: the gate's own
  // rule, read from the schema, must still say so.
  assert.match(GATE_ALL, /p_source = 'save_profile' and coalesce\(l\.rejection_reason, ''\) like 'registration incomplete after %'/);
  assert.match(RR.REOPEN, /Save changes/);
  const say = (c) => ({ reg_profile: 'Company profile', reg_terms: 'Signed supplier terms', reg_mobile: 'Verified mobile number', licence_expired: 'the trade licence on file has expired' })[c] || '';
  assert.deepEqual(RR.rejectedLines({ missing: ['reg_profile', 'reg_terms', 'reg_mobile'], reason: 'reg_profile' }, say),
    ['Missing: Company profile, signed supplier terms and verified mobile number.', RR.REOPEN, RR.REJECTED_NEXT], 'every missing item is named');
  assert.deepEqual(RR.rejectedLines({ missing: null, reason: 'reg_profile' }, say), ['Missing, starting with: Company profile.', RR.REJECTED_NEXT], 'one carried item is not the only one; no reopen promise');
  assert.deepEqual(RR.rejectedLines({ missing: null, reason: 'licence_expired' }, say), ['Reason: The trade licence on file has expired.', RR.REJECTED_NEXT]);
  for (const r of [null, '', 'some_internal_code']) assert.deepEqual(RR.rejectedLines({ missing: null, reason: r }, say), [RR.REJECTED_NEXT], String(r));
  assert.deepEqual(RR.rejectedLines({ missing: ['x_code'], reason: null }, () => 'x_code'), [RR.REOPEN, RR.REJECTED_NEXT], 'a map that echoes the code must not print it');
  assert.equal(RR.registrationReceived({ approvalStatus: 'rejected', submitted: true, reason: null, signingOnly: false, scopeOpen: false }), null, 'never both cards');
});
