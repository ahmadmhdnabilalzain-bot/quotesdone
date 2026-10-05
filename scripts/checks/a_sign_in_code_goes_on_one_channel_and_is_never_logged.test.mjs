// A SIGN-IN CODE GOES ON ONE CHANNEL AND IS NEVER LOGGED — owner: it_engineer
//
//   node --test scripts/checks/a_sign_in_code_goes_on_one_channel_and_is_never_logged.test.mjs
//
// WHY THIS EXISTS. On 18 Sep 2026 the founder authorised the AUTHENTICATION WhatsApp template, and
// login_otp's sign-in code may now be carried by WhatsApp instead of SMS. That turns a delivery
// choice into a credential path, and three properties of it are invisible to `deno check`:
//
//   1. ONE CHANNEL PER REQUEST. _shared/whatsapp_choice.ts falls back to SMS only on the three Twilio
//      codes that mean Verify never attempted WhatsApp delivery at all. 60410 (Fraud Guard) is
//      deliberately excluded — retrying a fraud block on the second channel hands the attacker the
//      second channel. A fourth code added to that set would silently allow two live codes.
//   2. THE CODE IS TWILIO'S. login_otp never generates, stores or compares the phone-channel code;
//      Twilio Verify holds it on both channels. phone_verifications.code carries a channel MARKER
//      ('twilio:sms' / 'twilio:whatsapp'), and if a real code were ever written there instead, this
//      table would become a credential store with no encryption and a rate-limit ledger's ACL.
//   3. THE ANSWER DOES NOT NAME THE CHANNEL. This endpoint takes no session. Returning
//      'whatsapp' vs 'sms' would tell an anonymous caller holding a number that resolves to one
//      account whether THAT account has a confirmed WhatsApp number — somebody else's account state.
//
// It also holds the two guards the security review of the same day asked for: the code generator is
// the CSPRNG, not Math.random(), and the stored-token comparison is constant time.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const R = (p) => readFileSync(fileURLToPath(new URL('../../' + p, import.meta.url)), 'utf8');
// A CHECK THAT GREPS SOURCE MATCHES ITS OWN COMMENTS (apply-discipline, 9 Sep 2026). Every rule below
// is about CODE, so the comments — which name the very things being forbidden, e.g. "Math.random() is
// not a credential generator" — are removed before matching. Without this the guard fires on the
// sentence that explains it.
const strip = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^[ \t]*\/\/.*$/gm, '').replace(/\s\/\/.*$/gm, '');
const OTP = R('supabase/functions/login_otp/index.ts');
const CHOICE = R('supabase/functions/_shared/whatsapp_choice.ts');

test('the SMS fallback fires only on the three "WhatsApp was never attempted" codes', () => {
  const m = CHOICE.match(/const REFUSED_CODES = new Set\(\[([^\]]*)\]\)/);
  assert.ok(m, 'REFUSED_CODES is no longer a literal Set in _shared/whatsapp_choice.ts');
  const codes = m[1].split(',').map((s) => Number(s.trim())).filter((n) => Number.isFinite(n));
  assert.deepEqual(codes.sort((a, b) => a - b), [63008, 63118, 68008]);
  assert.ok(!codes.includes(60410), 'Fraud Guard (60410) must never fall back to the second channel');
});

test('login_otp asks for WhatsApp only for a number the account itself confirmed', () => {
  const start = OTP.indexOf('async function confirmedWhatsApp');
  assert.ok(start > 0, 'confirmedWhatsApp is gone');
  // The gate reads stored proof (whatsapp_verified_at) and nothing from the request.
  const gate = OTP.slice(start, OTP.indexOf('Deno.serve(', start));
  assert.match(gate, /whatsapp_verified_at/, 'the gate must require a verified WhatsApp number');
  assert.ok(!/\bbody\.|\breq\./.test(strip(gate)), 'the gate must not read anything from the request');
});

test('the WhatsApp branch runs after every existing refusal and rate limit', () => {
  const at = (s) => { const i = OTP.indexOf(s); assert.ok(i > 0, `missing: ${s}`); return i; };
  const wa = at('const wantsWa = await confirmedWhatsApp');
  for (const guard of [
    "if (owner && 'ambiguous' in owner)",   // a shared number may not select a person
    'if (!acctEmail) {',                    // no account -> no paid send
    'if (isDemoPhone(e164))',               // a fixture number is never texted
    'const pb = await prefixBlocked',       // an OTP-pumping prefix
    "await rl('login_otp_sms_ip:'",         // per-caller ceiling
  ]) assert.ok(at(guard) < wa, `the WhatsApp branch must come AFTER: ${guard}`);
});

test('no sign-in code reaches a log, a row or the response', () => {
  // phone_verifications.code carries the channel marker, never a code.
  assert.match(OTP, /code: 'twilio:' \+ res\.channel/);
  assert.ok(!/code: c\b/.test(OTP), 'a code must never be written to phone_verifications');
  // Every logRun/logThrottled argument is static text or a count. `c` is the issued email code.
  for (const call of OTP.match(/logRun\([^;]*?\);/gs) || [])
    assert.ok(!/\bc\b(?!haracter)/.test(call.replace(/'[^']*'/g, '')), 'a log call references the code variable: ' + call.slice(0, 120));
  // The phone `send` answer must not disclose which channel carried it.
  const answer = OTP.slice(OTP.indexOf("const smsOnly"), OTP.indexOf("if (action === 'verify')"));
  assert.ok(!/channel: res\.channel/.test(answer), 'the response must not name the delivered channel');
});

test('the code generator is the CSPRNG and the code is checked in one locked statement', () => {
  assert.match(OTP, /function code6\(\)[^\n]*crypto\.getRandomValues/);
  assert.ok(!/Math\.random/.test(strip(OTP)), 'Math.random must not generate a credential');
  // 6 Oct 2026 (H1): the compare moved into public.fn_login_otp_email_verify, which counts, compares and
  // spends under a row lock. The function hands it the HMAC and never reads the code row to compare itself.
  assert.match(OTP, /rpc\("fn_login_otp_email_verify", \{ p_email: email, p_hash: await otpHash\(code\)/);
  assert.ok(!/from\('email_verifications'\)\.select\('\*'\)/.test(OTP), 'the verify must not read the code row and compare it outside the locked routine');
});
