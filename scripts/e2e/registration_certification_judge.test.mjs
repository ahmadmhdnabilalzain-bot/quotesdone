// The supplier registration certification's bar and fixtures, offline (customer_support, founder ruling 1620, 10 Nov 2026).
// A rule that judged a cut licence name as read, Arabic as absent, or a code as a polite message would certify the
// registration the founder is about to send his own network to; each case below fails if that rule weakens.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { judgeLicence, judgeExpired, judgeProposals, arabicIn, messageFaults, stepTiming, certify, INTERACTIVE_MS, waitsOnTheModel, judgeArabic, failureOrigin, splitEnvironmentFaults } from './registration_certification_judge.mjs';
import { LICENCES, PROFILES, FIXTURE_DIR, expectedReading, licenceHtml, profileHtml, SYNTHETIC } from './registration_fixtures.mjs';

const EXP = JSON.parse(readFileSync(join(FIXTURE_DIR, 'expected.json'), 'utf8'));
const L1 = EXP.licences.find((l) => l.id === 'L1');

test('the fixtures are fictional: ZZ DEMO names, ZZ licence numbers, the synthetic notice, every file on disk', () => {
  assert.equal(LICENCES.length, 8); assert.equal(PROFILES.length, 6);
  for (const l of LICENCES) {
    assert.match(l.legal_name, /^ZZ DEMO /, l.id); assert.match(l.trade_name, /^ZZ DEMO /, l.id);
    assert.match(l.licence_no, /ZZ/, `${l.id}: a licence number without ZZ could be a real firm's`);
    assert.ok(existsSync(join(FIXTURE_DIR, l.file)), l.file);
  }
  for (const p of PROFILES) assert.ok(existsSync(join(FIXTURE_DIR, p.file)), p.file);
  for (const l of LICENCES) assert.ok(licenceHtml(l).includes(SYNTHETIC), `${l.id} prints the synthetic notice`);
  for (const p of PROFILES) assert.ok(profileHtml(p).includes(SYNTHETIC), `${p.id} prints the synthetic notice`);
  assert.equal(new Set(LICENCES.map((l) => l.licence_no)).size, 8, 'one number per licence');
  assert.deepEqual(EXP.licences, expectedReading().licences, 'expected.json is what the generator states (run --write)');
  assert.deepEqual(EXP.profiles, expectedReading().profiles);
});

test('the fixtures cover what the founder listed: the issuers, a photo, a scan, an expired licence, six trades, one bilingual profile', () => {
  for (const k of ['dubai_det', 'abu_dhabi_added', 'sharjah_sedd', 'ajman_ded', 'rak_ded', 'jafza', 'dmcc', 'rakez']) assert.ok(LICENCES.some((l) => l.key === k), k);
  assert.ok(LICENCES.some((l) => l.format === 'photo')); assert.ok(LICENCES.some((l) => l.format === 'scan'));
  assert.equal(LICENCES.filter((l) => l.expired).length, 1);
  assert.ok(LICENCES.find((l) => l.expired).expiry < '2026-11-10');
  assert.ok(PROFILES.some((p) => p.lang === 'bi'));
  for (const t of ['mep_general', 'joinery', 'building_materials', 'hvac', 'packaging', 'staff_transport']) assert.ok(PROFILES.some((p) => p.trade === t), t);
});

test('a licence read whole passes; a cut legal name, an Arabic-tailed authority or a lost activity fails', () => {
  const good = { licence_no: 'ZZ-1290417', legal_name: L1.legal_name, authority: L1.authority, expiry: '2027-02-15', activities: L1.activities };
  assert.equal(judgeLicence(L1, good).ok, true);
  assert.equal(judgeLicence(L1, { ...good, legal_name: 'ZZ DEMO Saker Electromechanical' }).fields.legal_name.ok, false);
  assert.equal(judgeLicence(L1, { ...good, authority: L1.authority + ' ارﺪﺻﻹا ﺔﻬﺟ' }).fields.authority.ok, false);
  assert.equal(judgeLicence(L1, { ...good, activities: L1.activities.slice(0, 2) }).fields.activities.ok, false);
  assert.equal(judgeLicence(L1, { ...good, expiry: '2027-02-16' }).ok, false);
  assert.equal(judgeLicence(L1, null).ok_count, 0);
});

test('the expired licence passes only when the supplier is told and it is not approved', () => {
  const L8 = EXP.licences.find((l) => l.expired);
  assert.equal(judgeExpired(L8, { screenText: 'Your trade licence has expired. Please upload the renewed licence.', approval: 'action_required' }).ok, true);
  assert.equal(judgeExpired(L8, { screenText: 'Licence read, expires 31 Aug 2026.', approval: 'action_required' }).ok, false, 'a date is not a flag');
  assert.equal(judgeExpired(L8, { screenText: 'Your licence has expired', approval: 'approved' }).ok, false);
  assert.equal(judgeExpired(L1, {}).applies, false);
});

test('proposals: a right trade and nothing absurd; one absurd trade fails the profile', () => {
  const P1 = EXP.profiles.find((p) => p.id === 'P1');
  assert.equal(judgeProposals(P1, ['electrical.lv_distribution', 'hvac.vrf', 'fire_fighting.sprinklers']).ok, true);
  assert.equal(judgeProposals(P1, ['electrical.lv_distribution', 'staff_transport.bus_rental']).ok, false);
  assert.deepEqual(judgeProposals(P1, ['cosmetics_wholesale.x']).absurd, ['cosmetics_wholesale']);
  assert.equal(judgeProposals(P1, []).ok, false, 'nothing proposed is not "understands what they do"');
});

test('Arabic is found, presentation forms included; English is not', () => {
  assert.deepEqual(arabicIn('Register your company'), []);
  assert.equal(arabicIn('Licensing authority العربية').length, 1);
  assert.equal(arabicIn('Dubai ﺔﻬﺟ').length, 1);
});

test('a message is plain and polite, or it names why not', () => {
  assert.deepEqual(messageFaults('We could not read an expiry date from your trade licence. Nothing was guessed.'), []);
  assert.deepEqual(messageFaults('Still needed to register: your company profile.'), []);
  assert.ok(messageFaults('missing_required: reg_profile').includes('a raw code (snake_case)'));
  assert.ok(messageFaults('HTTP 500').length);
  assert.ok(messageFaults('TypeError: Failed to fetch').length);
  assert.ok(messageFaults('Invalid licence').includes('not polite'));
});

test('speed: 3 s on desktop and 5 s on the phone; a heavy step acknowledges in that time and finishes in its ceiling', () => {
  assert.equal(INTERACTIVE_MS.desktop, 3000); assert.equal(INTERACTIVE_MS.mobile, 5000);
  assert.equal(stepTiming({ profile: 'desktop', ms: 2999 }).ok, true);
  assert.equal(stepTiming({ profile: 'desktop', ms: 3001 }).ok, false);
  assert.equal(stepTiming({ profile: 'mobile', ms: 4800 }).ok, true);
  assert.equal(stepTiming({ profile: 'desktop', kind: 'submit', ms: 12000, ackMs: 400 }).ok, true);
  assert.equal(stepTiming({ profile: 'desktop', kind: 'submit', ms: 12000, ackMs: 3400 }).ok, false, 'a late acknowledgement is lag');
  assert.throws(() => stepTiming({ profile: 'desktop', kind: 'nope', ms: 1 }));
});

test('a free run never certifies the reading: licence and services verdicts are NOT RUN, never PASS', () => {
  const j = { id: 'J1', profile: 'desktop', steps: [{ name: 's', journey: 'J1', profile: 'desktop', timing: { ok: true } }], licence: null, proposals: null,
    expired: { applies: false }, arabic: [], faults: [], errors: [], dead_end: null, expect_verified: true, verified: false, supplier_ms: null };
  const v = certify([{ journeys: [j] }, { journeys: [j] }], { paid: false });
  assert.equal(v.licence_fields.verdict, 'NOT RUN'); assert.equal(v.proposals.verdict, 'NOT RUN');
  assert.equal(v.speed.verdict, 'PASS'); assert.equal(v.reproducible.verdict, 'PASS');
  const paid = certify([{ journeys: [j] }], { paid: true });
  assert.equal(paid.licence_fields.verdict, 'FAIL', 'a paid run that read no licence fails, it is not skipped');
  assert.equal(paid.reproducible.verdict, 'NOT RUN');
});

test('the licence bar is per run: 7 of 8; a free run FAILS only once 7 is out of reach even if the unread ones were read', () => {
  const lic = (id, ok, deferred = false) => ({ id, profile: 'desktop', steps: [], licence: { ok, ok_count: ok ? 5 : 3 }, licence_deferred: deferred,
    expired: { applies: false }, arabic: [], faults: [], errors: [], dead_end: null, expect_verified: false, verified: false, supplier_ms: null });
  const eight = (bad) => Array.from({ length: 8 }, (_, i) => lic('J' + (i + 1), i >= bad));
  assert.equal(certify([{ journeys: eight(1) }, { journeys: eight(1) }], { paid: true }).licence_fields.verdict, 'PASS', '7 of 8 in each run');
  assert.equal(certify([{ journeys: eight(1) }, { journeys: eight(2) }], { paid: true }).licence_fields.verdict, 'FAIL', 'one run at 6 of 8');
  // free: 6 read (2 deferred). 5 correct + 2 unread could still reach 7 -> NOT RUN; 4 correct + 2 unread cannot -> FAIL
  const free = (okN) => [...Array.from({ length: 6 }, (_, i) => lic('J' + (i + 1), i < okN)), lic('J7', false, true), lic('J8', false, true)];
  assert.equal(certify([{ journeys: free(5) }], { paid: false }).licence_fields.verdict, 'NOT RUN');
  assert.equal(certify([{ journeys: free(4) }], { paid: false }).licence_fields.verdict, 'FAIL');
});

test('the supplier\'s minutes: one measured registration over the bar fails; unfinished ones in a free run are NOT RUN', () => {
  const j = (id, verified, ms) => ({ id, profile: 'mobile', steps: [], licence: null, expired: { applies: false }, arabic: [], faults: [], errors: [], dead_end: null, expect_verified: true, verified, supplier_ms: ms });
  assert.equal(certify([{ journeys: [j('J1', true, 3 * 60000), j('J2', false, null)] }], { paid: false }).supplier_minutes.verdict, 'NOT RUN');
  assert.equal(certify([{ journeys: [j('J1', true, 11 * 60000), j('J2', false, null)] }], { paid: false }).supplier_minutes.verdict, 'FAIL');
  assert.equal(certify([{ journeys: [j('J1', true, 3 * 60000), j('J2', false, null)] }], { paid: true }).supplier_minutes.verdict, 'FAIL', 'paid: every full registration must finish');
});

test('"correct anything wrong" is polite; "Wrong code." is curt', () => {
  assert.deepEqual(messageFaults('Check them, correct anything wrong, then press Confirm my services.'), []);
  assert.ok(messageFaults('Wrong code.').includes('not polite'));
});

// 11 Nov 2026, second free round on production: J4 (phone photo) and J5 (scan) stayed licence_being_read for 60 s in both runs and
// were judged FAIL. With the models off only the model can read those licences, so that wait is NOT RUN in a free run; but only
// when every part says so, and never in a paid run.
test('a free run defers "approved and verified" only when the licence waits on the model, and nothing else holds it', () => {
  const base = { paid: false, needsModel: true, gateReason: 'licence_being_read', readState: 'ours_failed' };
  assert.equal(waitsOnTheModel(base), true);
  assert.equal(waitsOnTheModel({ ...base, paid: true }), false, 'a paid run must read it');
  assert.equal(waitsOnTheModel({ ...base, needsModel: false }), false, 'a text licence code can read is never excused');
  assert.equal(waitsOnTheModel({ ...base, gateReason: 'licence_number_unread' }), false, 'a licence our reader read but found blank asks the supplier: judged');
  assert.equal(waitsOnTheModel({ ...base, readState: 'read' }), false);
  assert.equal(waitsOnTheModel({ ...base, gateReason: 'services_unconfirmed' }), false);
});

// Ruling 1008 is about messages; ruling 342 makes the agreement's Arabic text prevail (the main session's decision on finding 8).
test('no Arabic: a message or an English page fails; the agreement\'s legal text and Arabic the supplier chose do not', () => {
  const name = '\u0643\u0648\u062a\u0633 \u062f\u0646';   // QuotesDone's Arabic name, escaped so this file holds no Arabic letter
  assert.equal(judgeArabic({ screens: [{ where: 'agreement page', text: name }] }).ok, true, 'ruling 342');
  assert.equal(judgeArabic({ screens: [{ where: 'registration form', text: name, lang: 'ar' }] }).ok, true, 'his own choice');
  assert.equal(judgeArabic({ screens: [{ where: 'registration form', text: name }] }).ok, false, 'an English supplier page');
  const m = judgeArabic({ messages: [{ channel: 'whatsapp', where: 'notification 1', text: 'Welcome ' + name }] });
  assert.equal(m.ok, false, 'ruling 1008: a message'); assert.equal(m.in_messages[0].channel, 'whatsapp');
  const j = (arabic, code_mail = null) => ({ id: 'J1', profile: 'desktop', steps: [], licence: null, expired: { applies: false }, arabic, code_mail, faults: [], errors: [], dead_end: null, expect_verified: false, verified: false, supplier_ms: null });
  assert.equal(certify([{ journeys: [j([{ where: 'agreement page', text: name }])] }], { paid: false }).no_arabic.verdict, 'PASS');
  assert.equal(certify([{ journeys: [j([], { subject: 'Your code ' + name })] }], { paid: false }).no_arabic.verdict, 'FAIL', 'the code e-mail is a message');
  assert.equal(certify([{ journeys: [j([])], messages_sent: [{ channel: 'email', where: 'n', text: name }] }], { paid: false }).no_arabic.verdict, 'FAIL');
});

// Paid round, 11 Nov 2026 06:07: "Confirm my services" took 3.9-4.4 s on desktop against its 20 s ceiling and was judged FAIL, because
// the walk timed it without an acknowledgement locator, so the whole confirm counted as the 3 s acknowledgement. And run 2's J4 had
// 4 services proposed in services_state, none on screen at the last look (the tab still showed what it loaded before them).
test('the walk times "Confirm my services" with its acknowledgement, and looks again before judging an empty proposal', () => {
  const src = readFileSync(new URL('./supplier_registration_certification.mjs', import.meta.url), 'utf8');
  assert.match(src, /const r10 = await timed\(\(\) => confirm\.click\(\), [^\n]*, M\.getByRole\('button', \{ name: \/\^Saving…\$\/ \}\)\);/);
  assert.equal(stepTiming({ profile: 'desktop', kind: 'submit', ms: 3933, ackMs: 120 }).ok, true, 'a 3.9 s confirm acknowledged at once is inside its ceiling');
  assert.match(src, /if \(!hasProp\) \{[\s\S]{0,400}getByRole\('button', \{ name: \/\^Services\$\/ \}\)\.click\(\)[\s\S]{0,200}hasProp = await prop\.waitFor/);
});

test('reproducible compares the right set and the absurd ones, never an acceptable extra (J6, paid run of #1934)', () => {
  const j6 = (acceptable, absurd = []) => ({ id: 'J6', profile: 'mobile', steps: [], licence: { ok: true, ok_count: 5 }, expired: { applies: false }, arabic: [], faults: [], errors: [],
    dead_end: null, expect_verified: true, verified: true, supplier_ms: 1,
    proposals: { trades: ['staff_transport', ...acceptable, ...absurd], right: ['staff_transport'], acceptable, absurd, ok: absurd.length === 0 } });
  const same = certify([{ journeys: [j6(['vehicle_leasing'])] }, { journeys: [j6([])] }], { paid: true }).reproducible;
  assert.equal(same.verdict, 'PASS', JSON.stringify(same));
  assert.deepEqual(same.extras, ['J6:vehicle_leasing', 'J6:']);
  assert.equal(certify([{ journeys: [j6([])] }, { journeys: [j6([], ['musical_pro_audio'])] }], { paid: true }).reproducible.verdict, 'FAIL', 'an absurd trade in one run is a difference');
});

// WHO ANSWERED A FAILED CHUNK (11 Nov 2026, free round 6 run 1 J2 mobile: 339rcm1dz4b7r.js answered 502 text/plain and was
// refused). Vercel signs its answers (server: Vercel, x-vercel-id); an answer for our host without that signature came from
// between the browser and the site. Only that evidence moves a failure out of the verdict.
test('failureOrigin: our host with Vercel\'s signature is the site; without it, the environment; no evidence stays the site\'s', () => {
  const chunk = 'https://quotesdone.ae/_next/static/immutable/chunks/339rcm1dz4b7r.js';
  assert.equal(failureOrigin({ url: chunk, headers: { server: 'Vercel', 'x-vercel-id': 'iad1::abc', 'content-type': 'text/plain; charset=utf-8' } }), 'site');
  assert.equal(failureOrigin({ url: chunk, headers: { 'X-Vercel-Id': 'fra1::x' } }), 'site', 'header names in any case');
  assert.equal(failureOrigin({ url: chunk, headers: { 'content-type': 'text/plain' } }), 'environment', 'a 502 nobody at Vercel signed');
  assert.equal(failureOrigin({ url: chunk }), 'site', 'no headers recorded: never excused');
  assert.equal(failureOrigin({ url: 'https://www.quotesdone.com/portal', headers: {} }), 'environment');
  assert.equal(failureOrigin({ url: 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/supplier_api', headers: {} }), 'other');
  assert.equal(failureOrigin({ url: 'https://quotesdone.ae.evil.example/x.js', headers: {} }), 'other');
});

test('splitEnvironmentFaults moves only the console errors that name an environment-answered URL', () => {
  const u = 'https://quotesdone.ae/_next/static/immutable/chunks/339rcm1dz4b7r.js';
  const errors = ['Failed to load resource: the server responded with a status of 502 (Bad Gateway) @ ' + u,
    `Refused to execute script from '${u}' because its MIME type ('text/plain') is not executable`, 'pageerror: x is undefined'];
  const env = splitEnvironmentFaults(errors, [{ url: u, origin: 'environment' }]);
  assert.deepEqual([env.environment.length, env.site], [2, ['pageerror: x is undefined']]);
  const ours = splitEnvironmentFaults(errors, [{ url: u, origin: 'site' }]);
  assert.deepEqual([ours.environment, ours.site.length], [[], 3], 'Vercel answered the 502: it is the site\'s fault, counted');
});

test('certify shows environment faults beside the verdict and does not count them', () => {
  const j = { id: 'J2', profile: 'mobile', dead_end: null, errors: [], environment_faults: ['console: Refused to execute script ...'], steps: [], arabic: [], faults: [], messages: [] };
  const c = certify([{ journeys: [j] }], { paid: false });
  assert.equal(c.criteria?.no_error_no_dead_end?.environment_faults?.length ?? c.no_error_no_dead_end?.environment_faults?.length, 1);
});
