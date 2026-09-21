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
  const call = outbox.indexOf("fetch('https://api.resend.com/emails'");
  assert.ok(hold > 0 && call > 0 && hold < call, 'the no-unsubscribe hold must run before the Resend call');
});

test('send_outbox sends a text/plain part', () => {
  assert.match(outbox, /text: plainTextPart\(/, 'the Resend payload lost its text/plain part');
});

test('a hard bounce reaches the lead whatever the case of its stored email', () => {
  assert.match(webhook, /from\('leads'\)\.update\(\{ invite_status: 'bounced' \}\)\.ilike\('email', /,
    'resend_webhook marks the bounced lead by an exact-case match again, so capitalised lead emails are never marked bounced');
});

// THE ARABIC INVITATION IS CORRESPONDENCE, NOT A TRANSLATION (founder instruction 586, 21 Sep 2026:
// "it feels like a pure translation only. it should feel much more professional").
test('the Arabic invitation keeps the formal register, its link and no stray English', () => {
  const sql = readFileSync('scripts/sql/the_supplier_invitation_goes_once_in_the_suppliers_language_and_never_to_a_demo_or_sanctioned_lead.sql', 'utf8');
  const m = sql.match(/'invite_body_ar', \$ar\$([\s\S]*?)\$ar\$/);
  assert.ok(m, 'the Arabic invitation body is missing from the campaign file');
  const body = m[1];
  for (const phrase of ['السادة/ {{company}} المحترمين', 'تحية طيبة وبعد', 'وتفضلوا بقبول فائق الاحترام والتقدير', '{{link}}']) {
    assert.ok(body.includes(phrase), `the Arabic invitation lost "${phrase}"`);
  }
  const latin = (body.replace(/\{\{[a-z]+\}\}/g, '').match(/[A-Za-z]{2,}/g) || []).filter((w) => w !== 'QuotesDone');
  assert.deepEqual(latin, [], 'English words inside the Arabic invitation');
  assert.match(outbox, /arMail \? sigNameAr : sigName/, 'Arabic mail is signed with a Latin-script name again');
});
