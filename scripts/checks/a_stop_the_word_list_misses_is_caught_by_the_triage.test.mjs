// A STOP THE WORD LIST MISSES IS CAUGHT BY THE TRIAGE, AND NEVER ANSWERED (28 Oct 2026, sales_engineer; founder ledger
// 1401, the supplier-journey audit).
//
// MEASURED on production 28 Oct 2026 (auditor A, run 490a318b, inbound_messages 1449): "Please remove me / stop" to
// supplier@ matched no word rule, so resend_inbound did not suppress it and email_triage ANSWERED it ("Understood. We will
// not contact you again...") while the address stayed sendable. The independent review of #1724 measured 20 realistic
// declines the widened word rule still misses (0/20). So email_triage's model is offered opt_out, and
// email_triage/opt_out_backstop.ts applies it on an invited supplier's reply to supplier@ behind resend_inbound's gates
// (opt_out_backstop.test.ts). This check fails when the WIRING goes:
//   * SYS stops offering opt_out, or stops leaving the draft empty for it;
//   * the backstop no longer runs after the classification is recorded and before the mail can be answered, or no
//     longer ends the mail's turn (a stop that is also answered is the 28 Oct failure);
//   * its scope stops being the invitation reply that invitationReplyAnswerable let through;
//   * resend_inbound stops reading the word rule first.
//   node --test scripts/checks/a_stop_the_word_list_misses_is_caught_by_the_triage.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const noComments = (t) => t.split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n');
const TRIAGE = noComments(read('supabase/functions/email_triage/index.ts'));

test('the triage model is offered opt_out, with an empty draft', () => {
  const at = TRIAGE.indexOf('const SYS = `');
  const sys = TRIAGE.slice(at, TRIAGE.indexOf('`;', at));
  assert.match(sys, /"category":"[a-z_|]*\|opt_out\|[a-z_|]*"/, 'SYS no longer lists opt_out among its categories');
  assert.match(sys, /Use opt_out when the sender asks us to stop e-mailing them/, 'SYS no longer says when a mail is opt_out');
  assert.match(sys, /for opt_out set reply to an empty string/, 'SYS no longer keeps the draft empty for an opt_out');
});

test('the scope is the invitation reply invitationReplyAnswerable let through, and nothing else', () => {
  assert.match(TRIAGE, /invitationReplyAnswerable\(m, rel, !!\(sup && sup\.length\)\)\) skip = noAutoReply\(\{ \.\.\.m, to_email: '' \}, founder\);\s*invitationReply = !skip;/);
  assert.equal((TRIAGE.match(/invitationReply = /g) || []).length, 2, 'invitationReply is set only where the internal skip is lifted');
});

test('the backstop runs after the classification is recorded, before spam and the answer, and ends the turn', () => {
  const marked = TRIAGE.indexOf('update({ ai_category: category, ai_summary: summary');
  const branch = TRIAGE.indexOf('if (backstopApplies(category, invitationReply)) {');
  const spam = TRIAGE.indexOf("if (category === 'spam')");
  const answer = TRIAGE.indexOf('await reply1(m, audienceOf(relation)');
  assert.ok(marked > 0 && branch > marked, 'the backstop must read the category the model gave, after it is recorded');
  assert.ok(spam > branch && answer > branch, 'the backstop must come before the spam rule and before the answer');
  const block = TRIAGE.slice(branch, spam);
  assert.match(block, /await applyBackstop\(admin, m, \[\.\.\.founder, \.\.\.fwd, EXPENSE_MAILBOX\]\)/, 'the backstop must be applied with the protected addresses');
  assert.match(block, /continue;\s*\}\s*$/, 'a mail the backstop handled must never reach the answer');
});

test('the word rule still runs first, in resend_inbound, before anything is stored for the triage', () => {
  const inbound = noComments(read('supabase/functions/resend_inbound/index.ts'));
  const words = inbound.indexOf('isUnsubscribeRequest({ to, subject, text: fullText })');
  const stored = inbound.indexOf('const rawFacts = {');
  assert.ok(words > 0 && stored > words, 'resend_inbound must read the word rule before it stores a mail for email_triage');
});
