// node --test src/components/portal/supplier/mobileState.test.mjs
// Free supplier registration certification, 11 Nov 2026, run 1, J4 mobile (customer_support): the form's one kyc 'state' read was
// lost at the portal's 20 s abort, the form kept "not verified, no WhatsApp answer", and Submit said "Still needed to register:
// Verified mobile number, Your answer on your WhatsApp number" while kyc 'state' answered phone_verified + whatsapp.opt. This fails
// if a lost read is applied as an answer, is not asked again, or if Submit lists the mobile, the e-mail or the WhatsApp answer as
// missing on the form's own copy without asking the server.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { kycAnswered, readKycState, localKycMissing, kycItemsMissing } from './mobileState.ts';

const noWait = () => Promise.resolve();
const LOST = { ok: false, code: 'timeout' };   // supplier/api.ts call(): the 20 s abort
// What kyc 'state' answered for J4's supplier from 16:01:08Z (function_edge_logs; the harness's own read).
const J4_SERVER = { ok: true, kind: 'supplier', phone: '+971500000043', email_verified: true, phone_verified: true, whatsapp: { opt: 'same' } };

test('only kyc\'s own answer is a state; a timeout, a network loss or a refusal is not', () => {
  assert.equal(kycAnswered(J4_SERVER), true);
  for (const k of [null, undefined, LOST, { ok: false, code: 'network' }, { ok: false, code: 'unauthorized' }, { phone_verified: true }]) assert.equal(kycAnswered(k), false, JSON.stringify(k));
});

test('J4 replayed: the form\'s copy says the mobile and the WhatsApp answer are missing, the server says neither is', async () => {
  const local = localKycMissing({ phoneVerified: false, emailVerified: true, wa: undefined });
  assert.deepEqual(local, ['reg_mobile', 'reg_whatsapp'], 'the form\'s copy after the lost read');
  let reads = 0;
  const k = await readKycState(async () => (++reads === 1 ? LOST : J4_SERVER), { sleep: noWait });
  assert.equal(reads, 2, 'a lost read is asked again');
  assert.deepEqual(kycItemsMissing(k), [], 'Submit lists nothing of the three: the server has all of them');
});

test('with no answer at all, Submit lists none of the three and lets save_profile decide on the row', async () => {
  let reads = 0;
  const k = await readKycState(async () => { reads++; return LOST; }, { tries: 3, sleep: noWait });
  assert.equal(k, null); assert.equal(reads, 3);
  assert.deepEqual(kycItemsMissing(k), []);
  const thrown = await readKycState(async () => { throw new Error('offline'); }, { tries: 2, sleep: noWait });
  assert.equal(thrown, null, 'a read that throws is a lost read');
});

test('our own refusal is not asked again, and an answer that says missing is listed as missing', async () => {
  let reads = 0;
  const k = await readKycState(async () => { reads++; return { ok: false, code: 'unauthorized' }; }, { sleep: noWait });
  assert.equal(k, null); assert.equal(reads, 1);
  assert.deepEqual(kycItemsMissing({ ok: true, phone_verified: false, email_verified: true, whatsapp: { opt: null } }), ['reg_mobile', 'reg_whatsapp']);
  assert.deepEqual(kycItemsMissing({ ok: true, phone_verified: true, email_verified: false, whatsapp: { opt: 'none' } }), ['reg_email']);
  assert.deepEqual(kycItemsMissing({ ok: true, phone_verified: true, email_verified: true, whatsapp: { opt: null, asked: true } }), ['reg_whatsapp'], 'a code sent is not an answer');
});

test('onLost is told after each lost try, so the form need not wait for the last one', async () => {
  let lost = 0;
  await readKycState(async () => LOST, { tries: 2, sleep: noWait, onLost: () => lost++ });
  assert.equal(lost, 2);
});

test('the registration form applies only kyc\'s answers, reads again when lost, and Submit asks the server first', () => {
  const src = readFileSync(new URL('./core/ProfileForm.tsx', import.meta.url), 'utf8');
  const apply = src.slice(src.indexOf('const applyKyc'), src.indexOf('const loadKyc'));
  assert.match(apply, /if \(!kycAnswered\(k\)\) return false;/, 'a lost answer must change nothing on the form');
  assert.doesNotMatch(src, /setWa\(k \? k\.whatsapp : undefined\)/, 'a lost read wiped the WhatsApp answer');
  assert.match(src, /const loadKyc = \(\) => readKycState\(readKyc,/, 'the form\'s read must be asked again when it is lost');
  const save = src.slice(src.indexOf('const save = async'), src.indexOf("missing.push('reg_profile')"));
  assert.doesNotMatch(save, /if \(!phoneVerified\) missing\.push\('reg_mobile'\)/, 'Submit judged the mobile on the form\'s own copy');
  assert.doesNotMatch(save, /if \(!waSignupSettled\(wa\)\) missing\.push\('reg_whatsapp'\)/, 'Submit judged the WhatsApp answer on the form\'s own copy');
  assert.match(save, /if \(kycMissing\.length\) \{[\s\S]*?await readKycState\(readKyc[\s\S]*?kycMissing = kycItemsMissing\(k\);/, 'Submit must ask kyc before it lists the three');
  assert.ok(save.indexOf('kycItemsMissing(k)') < save.indexOf('missing.push(...kycMissing)'));
  const verify = src.slice(src.indexOf('const verifySms'), src.indexOf('const sendMail'));
  assert.match(verify, /answerWasLost\(j\) \? await readKycState\(readKyc/, 'a lost verify answer must ask kyc before "wrong code"');
  assert.ok(verify.indexOf('readKycState') < verify.indexOf("t(lang, 'wrong_code')"));
});

// FOUNDER RULING 1670 (12 Nov 2026): "I just did the WhatsApp confirmation and WhatsApp is a phone, so how?" His one code (WhatsApp,
// accepted 19:53:56Z) set owner_phone_verified and whatsapp_verified_at for the same number, yet Settings' Account card said
// "Phone ... not verified": it drew the settings answer warmed before the code. This fails if the card can say "not verified" while
// kyc's own answer says verified, if it does not name the WhatsApp code, or if it is called "Phone" again.
test('Settings says the mobile is verified, by WhatsApp code, the moment kyc says so, whatever the warmed read said', async () => {
  const { mobileStatus } = await import('./mobileState.ts');
  const kyc = { ok: true, phone: '+971501234567', phone_verified: true, whatsapp: { opt: 'other', phone: '+971501234567', verified: true, asked: true } };
  assert.equal(mobileStatus({ settingsVerified: false, kyc, phone: '+971501234567' }), 'verified_wa', 'a stale settings answer must not win over kyc');
  assert.equal(mobileStatus({ settingsVerified: false, kyc, phone: '0501234567' }), 'verified_wa', 'the same number written locally');
  assert.equal(mobileStatus({ settingsVerified: true, kyc: { ...kyc, whatsapp: { opt: 'none', phone: null, verified: false } }, phone: '+971501234567' }), 'verified');
  assert.equal(mobileStatus({ settingsVerified: true, kyc: { ...kyc, whatsapp: { opt: 'other', phone: '+971509999999', verified: true } }, phone: '+971501234567' }), 'verified', 'a different WhatsApp number does not name the channel');
  assert.equal(mobileStatus({ settingsVerified: true, kyc: { ok: true, phone_verified: false }, phone: '+971501234567' }), 'unverified', "kyc's answer is the record");
  // review of #1984, c2: verified by SMS, then "Yes, same number" (choosePatch 'same': whatsapp_verified_at with no code) names no channel
  assert.equal(mobileStatus({ settingsVerified: true, kyc: { ...kyc, whatsapp: { opt: 'same', phone: '+971501234567', verified: true, asked: true } }, phone: '+971501234567' }), 'verified');
  assert.equal(mobileStatus({ settingsVerified: true, kyc: null, phone: '+971501234567' }), 'verified', 'no kyc answer yet: the settings read stands');
  assert.equal(mobileStatus({ settingsVerified: false, kyc: { ok: false, code: 'timeout' }, phone: '' }), 'unverified');
});

test('Settings reads kyc for the mobile line, calls it "Mobile number", and a verified code makes the warmed reads stale', () => {
  const settings = readFileSync(new URL('./SupplierSettings.tsx', import.meta.url), 'utf8');
  assert.match(settings, /mobileStatus\(\{ settingsVerified: s\.owner_phone_verified, kyc, phone: s\.phone \}\)/);
  assert.match(settings, /phone: 'Mobile number'/);
  assert.match(settings, /verifiedWa: 'verified by WhatsApp code'/);
  assert.doesNotMatch(settings, /yn\(s\.owner_phone_verified\)/, 'the mobile line must not read the warmed settings flag alone');
  const form = readFileSync(new URL('./core/ProfileForm.tsx', import.meta.url), 'utf8');
  // review of #1984: both ways verify_sms can succeed drop the warmed Settings answer only (c4) and re-read the workspace (c1)
  assert.match(form, /const verified = \(\) => \{ setPhoneVerified\(true\); forgetSettingsRead\(\); if \(onVerified\) onVerified\(\); \};/);
  assert.equal((form.match(/verified\(\); return; \}/g) || []).length, 2, 'both success paths call verified()');
  const dash = readFileSync(new URL('./core/Dashboard.tsx', import.meta.url), 'utf8');
  assert.equal((dash.match(/onVerified=\{\(\) => load\(false, true\)\}/g) || []).length, 2, 'the Profile tab and the registration form both re-read the dashboard');
  const onb = readFileSync(new URL('./core/Onboarding.tsx', import.meta.url), 'utf8');
  assert.equal((onb.match(/onVerified=\{onVerified\}/g) || []).length, 2);
  // c3: the line waits for kyc instead of changing under his eyes
  assert.match(settings, /\{kycDone\s*\n?\s*\? t\(lang, mobile === 'verified_wa'/);
});
