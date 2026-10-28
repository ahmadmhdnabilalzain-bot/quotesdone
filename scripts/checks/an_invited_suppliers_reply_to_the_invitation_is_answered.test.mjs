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

test('email_triage lifts the internal skip only for a lead writing to the invitation mailbox, then re-applies every other rule', () => {
  assert.match(src, /let skip = noAutoReply\(m, founder\)/);
  assert.match(src, /if \(skip === 'internal'\)\s*\{[\s\S]{0,300}fn_mail_sender_known[\s\S]{0,200}invitationReplyAnswerable\(m, rel\)\)\s*skip = noAutoReply\(\{ \.\.\.m, to_email: '' \}, founder\)/);
});

test('an unclaimed lead is answered from the not-registered facts with its own link', () => {
  assert.match(facts, /if \(!sup\.claimed\) return unregisteredSupplierFacts\(/);
  assert.match(facts, /\/portal\?t=\$\{sup\.claim_token\}/);
});
