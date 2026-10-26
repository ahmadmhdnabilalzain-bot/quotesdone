// WhatsAppChoice.test.mjs — the WhatsApp question says the same thing in both languages, maps every
// refusal to words, decides its steps correctly, and is actually placed where the founder asked.
// node --test src/components/portal/WhatsAppChoice.test.mjs
// Founder, 14 Sep 2026: "what if the customer has whatsapp on another phone number, maybe we should
// confirm this point through the sign up". The .tsx cannot be imported by node (JSX), so the copy and
// the rules live in whatsappChoiceText.ts and the placements are checked in the source.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { WA_TEXT, WA_ERROR_CODES, waErrorKey, waErrorText, waUnavailable, waSignupSettled, waNeedsPrompt, waSentBySms, waCurrentKey } from './whatsappChoiceText.ts';

const HERE = import.meta.dirname;

test('English and Arabic have exactly the same keys, none empty', () => {
  assert.deepEqual(Object.keys(WA_TEXT.ar).sort(), Object.keys(WA_TEXT.en).sort());
  for (const lang of ['en', 'ar']) for (const [k, v] of Object.entries(WA_TEXT[lang])) assert.ok(String(v).trim(), lang + '.' + k + ' is empty');
});

test('the Arabic carries no English word; only QuotesDone and WhatsApp stay in Latin script', () => {
  for (const [k, v] of Object.entries(WA_TEXT.ar)) {
    const rest = v.replace(/QuotesDone|WhatsApp/g, '');
    assert.doesNotMatch(rest, /[A-Za-z]/, 'ar.' + k + ': ' + v);
  }
});

test('every refusal code in the contract reads as its own words, in both languages', () => {
  for (const c of WA_ERROR_CODES) {
    for (const j of [{ code: c }, { error: c }]) assert.equal(waErrorKey(j), 'err_' + c);
    for (const lang of ['en', 'ar']) {
      const s = waErrorText(lang, { code: c });
      assert.ok(s && s !== WA_TEXT[lang].err_generic, lang + ' ' + c);
      assert.doesNotMatch(s, /_/, 'a raw code leaked: ' + s);
    }
  }
  assert.equal(waErrorKey({ error: 'something_new' }), 'err_generic');
  assert.equal(waErrorKey(null), 'err_generic');
});

test('whatsapp_unavailable is recognised in error or code, and nothing else is', () => {
  assert.equal(waUnavailable({ ok: false, error: 'whatsapp_unavailable' }), true);
  assert.equal(waUnavailable({ code: 'whatsapp_unavailable' }), true);
  assert.equal(waUnavailable({ error: 'bad_phone', code: 'bad_phone' }), false);
  assert.equal(waUnavailable(null), false);
});

// Founder, 15 Sep 2026: "whenever there's a new sign up this should be in the sign up form ... we do it in
// advance. It's in the sign up." Sign-up has no skip: only a stored answer ends the step.
test('sign-up is settled only by a stored answer — no skip, no unavailable path, no missing field', () => {
  const unanswered = { opt: null, phone: null, verified: false, asked: false };
  assert.equal(waSignupSettled(unanswered), false);
  assert.equal(waSignupSettled({ ...unanswered, asked: true }), false, 'a code sent is not an answer');
  for (const opt of ['same', 'other', 'none']) assert.equal(waSignupSettled({ ...unanswered, opt }), true);
  assert.equal(waSignupSettled(undefined), false);
  assert.equal(waSignupSettled(null), false);
});

test('the dashboard card is only for accounts that finished sign-up before the question was in it', () => {
  const never = { opt: null, phone: null, verified: false, asked: false };
  assert.equal(waNeedsPrompt({ terms_signed: true, whatsapp: never }), true, 'an old account that never answered');
  assert.equal(waNeedsPrompt({ terms_signed: false, whatsapp: never }), false, 'still in sign-up: the sign-up step asks, not the card');
  assert.equal(waNeedsPrompt({ terms_signed: true, whatsapp: { ...never, asked: true } }), false);
  assert.equal(waNeedsPrompt({ terms_signed: true, whatsapp: { ...never, opt: 'same', asked: true } }), false, 'a new sign-up answered in the form');
  assert.equal(waNeedsPrompt(undefined), false);
});

test('the code screen says SMS whenever WhatsApp did not carry it', () => {
  assert.equal(waSentBySms({ ok: true, channel: 'sms' }), true);
  assert.equal(waSentBySms({ ok: true, channel: 'whatsapp' }), false);
  assert.equal(waSentBySms({ ok: true }), false);
  for (const lang of ['en', 'ar']) assert.notEqual(WA_TEXT[lang].code_sent_sms, WA_TEXT[lang].code_sent);
});

test('the question names the verified number in both languages', () => {
  assert.match(WA_TEXT.en.q_mobile_pre + '+971500000001' + WA_TEXT.en.q_mobile_post, /^Is \+971500000001 also your WhatsApp number\?$/);
  assert.ok(WA_TEXT.ar.q_mobile_post.includes('WhatsApp'));
});

test('Settings never presents an unverified number as the WhatsApp number', () => {
  assert.equal(waCurrentKey({ opt: 'other', phone: '+971501234567', verified: true, asked: true }), 'cur_other');
  assert.equal(waCurrentKey({ opt: 'other', phone: '+971501234567', verified: false, asked: true }), 'cur_pending');
  assert.equal(waCurrentKey({ opt: 'same', phone: null, verified: true, asked: true }), 'cur_same');
  assert.equal(waCurrentKey({ opt: 'none', phone: null, verified: false, asked: true }), 'cur_none');
  assert.equal(waCurrentKey({ opt: null, phone: null, verified: false, asked: false }), 'cur_unset');
});

test('all six placements render WhatsAppChoice with the right mode', () => {
  const src = (p) => readFileSync(join(HERE, p), 'utf8');
  const modes = (s) => [...s.matchAll(/<WhatsAppChoice\b[^>]*\bmode="(\w+)"/g)].map((m) => m[1]).sort();
  assert.deepEqual(modes(src('../me/CustomerPortal.tsx')), ['prompt', 'settings', 'signup']);
  assert.deepEqual(modes(src('SupplierPortal.tsx')), ['prompt', 'signup']);
  assert.deepEqual(modes(src('supplier/SupplierSettings.tsx')), ['settings']);
});


// Founder, 14 Sep 2026: "for suppliers whatsapp, if they said they are using a different number from the
// normal calling number and they mentioned it, then an otp verification is needed. and that applies to
// customer sign up as well." Supplier registration, supplier Settings and the customer screens all render
// this one component, and kyc serves both parties with the same actions, so these hold for both.
test('a different number is never stored without its WhatsApp code (suppliers and customers)', () => {
  const ui = readFileSync(join(HERE, 'WhatsAppChoice.tsx'), 'utf8');
  const choose = ui.slice(ui.indexOf('const choose = async'), ui.indexOf('const sendCode = async'));
  assert.match(choose, /if \(opt === 'other'\) return;[\s\S]*action: 'whatsapp_choose'/, "'different number' must never be saved by whatsapp_choose");
  assert.doesNotMatch(ui, /whatsapp_choose'[^}]*'other'/, 'no path saves a different number without a code');
  assert.equal((ui.match(/action: 'whatsapp_verify'/g) || []).length, 1, 'the only way to a different number is whatsapp_verify');

  const kyc = readFileSync(join(HERE, '..', '..', '..', 'supabase', 'functions', 'kyc', 'index.ts'), 'utf8');
  const branch = (name) => { const s = kyc.indexOf("action === '" + name + "'"); const e = kyc.indexOf("if (action === '", s + 20); return kyc.slice(s, e < 0 ? undefined : e); };
  const send = branch('whatsapp_send_code');
  assert.ok(send.length > 0, 'kyc has a whatsapp_send_code action');
  assert.match(send, /writeWa\(askedPatch\(/, 'sending a code records only that the question was asked');
  assert.doesNotMatch(send, /verifiedPatch\(|whatsapp_phone/, 'sending a code must not store the entered number');
  const verify = branch('whatsapp_verify');
  assert.ok(verify.indexOf('verifyCheck(') > -1 && verify.indexOf('verifyCheck(') < verify.indexOf('verifiedPatch('), 'the number is stored only after Twilio approves the code');
  assert.doesNotMatch(branch('whatsapp_choose'), /verifiedPatch\(/, 'choosing never stores a different number');

  // 15 Sep 2026: registration cannot complete without the answer, for suppliers AND customers — on screen
  // and on the server (supplier_api save_profile reg_whatsapp; kyc accept_terms whatsapp_unanswered).
  const sup = readFileSync(join(HERE, 'SupplierPortal.tsx'), 'utf8');
  assert.match(sup, /mode="signup"/);
  assert.match(sup, /missing\.push\('reg_whatsapp'\)/, 'the supplier form lists the WhatsApp answer as missing');
  const api = readFileSync(join(HERE, '..', '..', '..', 'supabase', 'functions', 'supplier_api', 'index.ts'), 'utf8');
  assert.match(api, /missing\.push\('reg_whatsapp'\)/, 'save_profile refuses a registration without the answer');
  assert.match(branch('accept_terms'), /whatsapp_unanswered/, 'a customer\'s first acceptance waits for the answer');
  // The code goes WhatsApp first, falls back only through the shared rule, and records the channel.
  assert.match(send, /sendWhatsAppFirst\(/);
  assert.match(send, /'twilio:'/);
  assert.doesNotMatch(ui, /mode !== 'settings' && <Button[^>]*onClick=\{later\}/, 'sign-up has no skip button');
});

// Audit 21 Sep 2026, finding 31: a refusal code kyc can send that this list does not know hides the
// server's reason behind "Something went wrong". Read every code the WhatsApp path can answer.
test('every refusal code kyc and the fixture guard can answer on the WhatsApp path has its own words', () => {
  const kyc = readFileSync(join(HERE, '../../../supabase/functions/kyc/index.ts'), 'utf8');
  const demo = readFileSync(join(HERE, '../../../supabase/functions/_shared/demo_identity.ts'), 'utf8');
  const codes = new Set([...kyc.matchAll(/code: '([a-z_]+)'/g), ...demo.matchAll(/code: '([a-z_]+)'/g)].map((m) => m[1]));
  // Not refusals a supplier can meet on this screen: 'twilio' is a stored marker, 'no_terms_version' a
  // server misconfiguration (500), 'whatsapp_unanswered' is the terms gate on the customer side.
  for (const c of ['twilio', 'no_terms_version', 'whatsapp_unanswered']) codes.delete(c);
  const missing = [...codes].filter((c) => !WA_ERROR_CODES.includes(c));
  assert.deepEqual(missing, [], 'codes kyc can answer with no words on screen: ' + missing.join(', '));
  assert.equal(waErrorKey({ ok: false, code: 'fixture_number', error: 'This is a reserved test number.' }), 'err_fixture_number');
});
