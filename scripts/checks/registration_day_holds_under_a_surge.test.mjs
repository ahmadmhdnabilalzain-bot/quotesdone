// REGISTRATION DAY HOLDS UNDER A SURGE (21 Sep 2026, it_engineer).
//
// A supplier email campaign sends many suppliers to sign up in the same hour. The review measured
// what breaks first (live auth config, edge logs, a rolled-back 50-registration replay) and fixed
// what was ours to fix. Each test below fails if one of those causes comes back.
//
//   node --test scripts/checks/registration_day_holds_under_a_surge.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { pendingNotes } from '../lib/pending_sql.mjs';
import { readSource, readSupplierPortal } from '../lib/portal_sources.mjs';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '../..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');
// Statements only, so a comment describing the old shape can never satisfy or fail an assertion.
const code = (s) => s.split('\n').filter((l) => !/^\s*(\/\/|\*|--)/.test(l)).join('\n');
const between = (s, a, b) => { const i = s.indexOf(a); assert.ok(i >= 0, 'anchor not found: ' + a); const j = s.indexOf(b, i); assert.ok(j > i, 'end anchor not found: ' + b); return s.slice(i, j); };

const kyc = code(read('supabase/functions/kyc/index.ts'));
const login = code(read('supabase/functions/login_otp/index.ts'));

test('a sign-in code that Resend refused is not answered as sent (login_otp)', () => {
  const branch = between(login, "codeEmail('signin'", "channel: 'email', identifier: email");
  // 15 Nov 2026 (06881a2d6): the mail carries its text/plain part too
  assert.match(branch, /if \(!\(await sendEmail\(email, mail\.subject, mail\.html(?:, mail\.text)?\)\)\)/,
    'login_otp must check the send result before answering ok:true');
  assert.match(branch, /code: 'email_not_sent' \}, 502\)/);
});

test('a verification email that did not leave is not answered as sent (kyc send_email)', () => {
  const branch = between(kyc, "action === 'send_email'", "action === 'verify_email'");
  const fail = branch.indexOf("code: 'email_not_sent' }, 502)");
  assert.ok(fail > 0 && fail < branch.indexOf('return J({ ok: true })'), 'the failure return must come before the ok:true return');
  assert.match(branch, /from\('email_verifications'\)[^\n]*count: 'exact'[^\n]*\.eq\('email', email\)/, 'kyc send_email needs its per-address ceiling');
});

test('both code senders retry a busy second through the one shared helper', () => {
  for (const [name, s] of [['kyc', kyc], ['login_otp', login]]) {
    assert.match(s, /return await resendWithRetry\(key, \{ from, to, subject, html, (?:\.\.\.\(text \? \{ text \} : \{\}\), )?reply_to \}\)/, name + ' sendEmail must use resendWithRetry');
    assert.doesNotMatch(s, /fetch\('https:\/\/api\.resend\.com\/emails'/, name + ' must not POST to Resend directly');
  }
  const helper = code(read('supabase/functions/_shared/resend_send.ts'));
  assert.match(helper, /if \(r\.status === 429\)/);
});

test('one signed-in account cannot walk a list of numbers (kyc per-account send cap)', () => {
  const fn = between(kyc, 'async function phoneRateLimited(', '\n}');
  assert.match(fn, /\.eq\('email', email\)/, 'the per-account count is gone');
  const calls = kyc.match(/phoneRateLimited\([^)]*\)/g).filter((c) => !c.includes(':'));
  assert.ok(calls.length >= 2 && calls.every((c) => c === 'phoneRateLimited(phone, email)'), 'every caller passes the account: ' + calls.join(', '));
});

test('supplier and customer sign-up never ask Supabase Auth to send mail', () => {
  // The project's auth mailer is capped at rate_limit_email_sent = 30 per hour (read 21 Sep 2026 via
  // the management API). The portals create users confirmed and send their own codes; a signUp or
  // signInWithOtp call would put every campaign sign-up behind that 30.
  const files = ['src/components/portal/SupplierPortal.tsx', 'src/components/me/CustomerPortal.tsx'];
  for (const f of files) {
    assert.doesNotMatch(code(readSource(f)), /\.auth\.(signUp|signInWithOtp|resetPasswordForEmail)\(/, f + ' calls the rate-limited auth mailer');
  }
});

test('the portal shows the email-not-sent refusal in the reader\'s language', () => {
  assert.match(readSupplierPortal(), /\[\/could not send the \(sms\|email\)\/i, 'err_code_send'\]/);
});

test('a served country\'s OTP burst is judged by codes never used, not by volume', () => {
  const file = 'scripts/sql/a_registration_day_is_not_an_otp_pumping_attack.sql';
  const listed = read('scripts/sql/MANIFEST.txt').split('\n').some((l) => l.startsWith(file)) || pendingNotes().has(file);
  assert.ok(listed, file + ' is neither in MANIFEST.txt nor pending (scripts/sql/pending/)');
  const sql = code(read(file));
  assert.match(sql, /count\(\*\) filter \(where not used and expires_at < now\(\)\) n_dead/);
  assert.match(sql, /elsif x\.n_dead > v_max and x\.n_dead \* 2 >= x\.n then/);
  // and an unserved country is still blocked on volume
  assert.match(sql, /insert into public\.otp_blocked_prefix/);
  // No later file may redefine the routine without the rule.
  const manifest = read('scripts/sql/MANIFEST.txt').split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
  const at = manifest.indexOf(file);
  for (const later of manifest.slice(at < 0 ? manifest.length : at + 1)) {
    if (!fs.existsSync(path.join(ROOT, later))) continue;
    const s = code(read(later));
    if (/create or replace function public\.fn_it_duties_scheduled\(/i.test(s)) {
      assert.match(s, /x\.n_dead > v_max/, later + ' redefines fn_it_duties_scheduled without the registration-day rule');
    }
  }
});
