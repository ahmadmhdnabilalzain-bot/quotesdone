// AN INVITED SUPPLIER'S REPLY TO THE INVITATION IS ANSWERED (28 Oct 2026, sales_engineer, ledger 1375). The invitation
// leaves from supplier@quotesdone.com with no Reply-To, so a "yes" lands in supplier@, and noAutoReply calls every mail
// to supplier@ 'internal': on 27 Oct all three replies (inbound_messages 653-655) went unanswered. The rule itself is
// tested in supabase/functions/_shared/customer_mail.test.ts; this fails if email_triage stops USING it, or if the facts
// it answers from call an unclaimed lead "registered" again (email_triage/account_facts.test.ts).
// Source only: runs offline in the checks job.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const src = readFileSync(new URL('../../supabase/functions/email_triage/index.ts', import.meta.url), 'utf8')
  .replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, ' ');
const facts = readFileSync(new URL('../../supabase/functions/email_triage/account_facts.ts', import.meta.url), 'utf8')
  .replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, ' ');

test('email_triage lifts the internal skip only for a lead writing to the invitation mailbox or mail to management@ or docs@, then re-applies every other rule', () => {
  assert.match(src, /let skip = noAutoReply\(m, founder\)/);
  // review of #1699: a lead in email_suppressions is passed as `suppressed`, so a lead who opted out is never answered
  // (#1728: the lift may sit in a block that also records `invitationReply = !skip`, the opt_out backstop's scope)
  assert.match(src, /if \(skip === 'internal'\)\s*\{[\s\S]{0,300}fn_mail_sender_known[\s\S]{0,400}from\('email_suppressions'\)[\s\S]{0,300}invitationReplyAnswerable\(m, rel, !!\(sup && sup\.length\)\)\)\s*\{?\s*skip = noAutoReply\(\{ \.\.\.m, to_email: '' \}, founder\)/);
  // widened on purpose (2 Nov 2026, the founder: every mailbox is with the agents): the second lift is exactly this rule,
  // inside the same block, re-applying every other rule, and a suppressed sender is still passed
  assert.match(src, /else if \(tenantMailAnswerable\(m, !!\(sup && sup\.length\)\)\) skip = noAutoReply\(\{ \.\.\.m, to_email: '' \}, founder\)/);
  // the third lift, and the last (11 Nov 2026, customer_support, founder ruling 1633): a supplier-mailbox mail whose READING
  // allowed an answer (email_triage/supplier_mailbox_reading.ts: a supplier or a customer, read by the model with the
  // correspondence; every other reading leaves the loop before this point). Pinned to that condition, the suppression and
  // the identity rules (answerableOnceRead), and re-applying every other noAutoReply rule.
  assert.match(src, /else if \(reading\?\.may_reply === true && answerableOnceRead\(m, !!\(sup && sup\.length\)\)\) skip = noAutoReply\(\{ \.\.\.m, to_email: '' \}, founder\)/);
  assert.match(src, /if \(reading && !reading\.may_reply\) \{[\s\S]{0,600}continue;\s*\}/, 'a reading that says no answer must leave the loop before any lift');
  // no fourth way out of the skip
  const block = src.slice(src.indexOf("if (skip === 'internal')"), src.indexOf('if (skip) {'));
  assert.equal((block.match(/skip = noAutoReply/g) || []).length, 3, 'another lift of the internal skip');
});

test('an unclaimed lead is answered from the not-registered facts with its own link', () => {
  assert.match(facts, /if \(!sup\.claimed\) return unregisteredSupplierFacts\(/);
  assert.match(facts, /\/portal\?t=\$\{sup\.claim_token\}/);
});
