// THE SUPPLIER CAMPAIGN HONOURS UNSUBSCRIBE AND BOUNCES WHATEVER THE CASE OF THE ADDRESS
// (21 Sep 2026, customer_support). The pure rules are tested in
// supabase/functions/send_outbox/supplier_mail.test.ts; this file asserts they are still WIRED IN,
// which needs file reads that CI's deno test run does not grant.
//
// Measured causes: 47 lead emails carry a capital letter while email_suppressions is stored
// lower-case, so an exact-match suppression lookup and an exact-match bounce update both missed them;
// and supplier marketing could leave with no unsubscribe link when the signing key did not read back.
//   node --test scripts/checks/the_supplier_campaign_honours_unsubscribe.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const outbox = readFileSync('supabase/functions/send_outbox/index.ts', 'utf8');
const webhook = readFileSync('supabase/functions/resend_webhook/index.ts', 'utf8');

test('send_outbox folds case on the suppression lookup', () => {
  // 22 Sep 2026: the set became a reason map (an unsubscribe stops only invitations); the fold is unchanged.
  assert.match(outbox, /supReason\.has\(foldEmail\(n\.to_email\)\)/, 'suppression lookup is no longer case-folded');
  assert.match(outbox, /supReason\.set\(foldEmail\(s\.email\)/, 'stored suppressions are no longer case-folded');
});

test('send_outbox holds supplier marketing with no unsubscribe link, before the provider call', () => {
  const hold = outbox.indexOf('holdForNoUnsubscribe(supplierSide, docReq, unsub)');
  // THE PROVIDER CALL IS FOUND BY ITS URL, NOT BY WHO CALLS IT (22 Sep 2026). This read
  // `fetch('https://api.resend.com/emails'` and stopped matching the moment CONN-04 wrapped that call
  // in timedFetch(): `call` became -1, the ordering could no longer be evaluated, and the assertion
  // would have gone red for a reason that has nothing to do with unsubscribe. The URL is the thing
  // that identifies the hop; the function that makes the request is an implementation detail.
  const call = outbox.search(/https:\/\/api\.resend\.com\/emails/);
  assert.ok(call > 0, 'the Resend send could not be found in send_outbox at all — this ordering check cannot be evaluated');
  assert.ok(hold > 0 && hold < call, 'the no-unsubscribe hold must run before the Resend call');
});

test('send_outbox sends a text/plain part', () => {
  assert.match(outbox, /text: plainTextPart\(/, 'the Resend payload lost its text/plain part');
});

test('a hard bounce reaches the lead whatever the case of its stored email', () => {
  // 22 Sep 2026: the status comes from inviteStatusFor (a complaint is 'complained', not 'bounced');
  // the case-insensitive match is what this test guards.
  assert.match(webhook, /from\('leads'\)\.update\(\{ invite_status: inviteStatusFor\(isComplaint, isHardBounce\) \}\)\.ilike\('email', /,
    'resend_webhook marks the bounced lead by an exact-case match again, so capitalised lead emails are never marked bounced');
});

// THERE IS NO ARABIC INVITATION (founder, 28 Sep 2026: suppliers always get English; E2E stage 1 D3, 30 Sep).
// This asserted the 21 Sep Arabic invitation's register. It now asserts no Arabic copy can reach a supplier:
// the stored Arabic copy is removed, the test send is English, and send_outbox holds a supplier row in Arabic.
test('no Arabic invitation copy is stored or chosen, and send_outbox holds any supplier row in Arabic', () => {
  const sql = readFileSync('scripts/sql/no_arabic_copy_path_reaches_a_supplier.sql', 'utf8');
  assert.match(sql, /delete from public\.app_secrets where key in \('invite_subject_ar', 'invite_body_ar'\);/, 'the Arabic invitation copy is kept');
  assert.match(sql, /declare v_lang text := 'en';/, 'the test send can choose a language again');
  assert.match(outbox, /holdArabicInvitation\(n\.type, n\.lang, supplierSide\)/, 'send_outbox no longer holds supplier rows queued in Arabic');
  assert.match(outbox, /const arMail = !internal && !supplierSide && n\.lang === 'ar';/, 'a supplier mail can be framed in Arabic again');
});
