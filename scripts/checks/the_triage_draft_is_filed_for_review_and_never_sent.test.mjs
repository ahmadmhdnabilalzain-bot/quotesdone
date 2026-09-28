// THE TRIAGE DRAFT IS FILED FOR REVIEW AND NEVER SENT (it_engineer, 23 Sep 2026).
//
// Recurrence guard for a MODEL-ROUTING decision, which is an unusual thing to guard in source, so the
// reason is worth stating precisely.
//
// founder_instruction 844 draws the line by audience: anything a customer reads, or that can emit
// Arabic to a person, goes on the customer-facing model (qwen/qwen3.8-max-0902 under 844, openai/gpt-5.6-sol since
// founder_instruction 854). email_triage's single call produces
// {category, summary, reply} where the reply is "a short, warm, professional reply ... signed 'The
// QuotesDone Team'", and the Arabic fixture in the_triage_answer_fits_its_route.test.mjs is exactly
// that. By the audience rule it should be on Qwen.
//
// It is on z-ai/glm-5.3-flash, the cheap internal model, for ONE reason: the draft is never sent by
// the machine. index.ts:1 says so, and the function files it into agent_actions as a pending
// inbound_review for a person to read, edit and send. THE HUMAN GATE IS THE WHOLE JUSTIFICATION.
//
// Before this check, that justification was a comment and one line of code, and NOTHING would have
// fired if someone later made email_triage send. The class would have quietly stayed on the cheap
// model while its output started reaching customers unreviewed - a routing decision invalidated by a
// change nobody would think to connect to it. That is rule 9: a fix is not finished until something
// fails when its cause returns.
//
// Repository only. No database, no token, no model.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const SRC = 'supabase/functions/email_triage/index.ts';
const POLICY_SQL = 'scripts/sql/every_seat_gets_the_model_its_own_work_needs.sql';
const src = readFileSync(join(REPO, SRC), 'utf8');

test('email_triage keeps the draft for the Inbox and never sends it', () => {
  // The gate itself: the draft is stored on the row and raised as a pending action.
  assert.match(src, /ai_draft_reply:/,
    `${SRC} no longer stores the drafted reply as ai_draft_reply. If the draft has stopped being a `
    + 'draft, the routing decision that keeps this class on the cheap internal model has lost its '
    + `only justification - see ${POLICY_SQL}, the email_triage rationale.`);

  assert.match(src, /agent_actions[\s\S]{0,400}?status:\s*'pending'/,
    `${SRC} no longer files the draft into agent_actions with status 'pending'. A person reviewing and `
    + 'sending it is the entire reason this class is routed to z-ai/glm-5.3-flash instead of '
    + 'the customer-facing model (openai/gpt-5.6-sol since founder_instruction 854). Either restore the review step, or move '
    + `the class to a customer-facing row in ${POLICY_SQL} and update its rationale.`);

  // And the absence of a send. These are the ways this estate actually sends mail; none may appear
  // in this function. Matched on the CODE with its comments stripped, because this check's own
  // sentences name the thing it forbids - the trap that has failed two checks on this repository.
  const code = src
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .split('\n')
    .filter((l) => !l.trimStart().startsWith('//'))
    .join('\n');

  // 28 Sep 2026 (customer_support, the founder: a customer is answered in under a minute). email_triage now
  // SENDS - but never this draft. Its one send is fn_inbox_send with a body built by composeMailReply from
  // think() on the customer-facing route, a reviewed knowledge passage, or a fixed receipt; and it wakes
  // send_outbox, which only sends what is already queued. So the draft's routing justification stands, and
  // this check now pins the thing that justification needs: the `reply` draft never reaches the send.
  assert.match(code, /rpc\('fn_inbox_send', \{ p_id: m\.id, p_body: text,/, `${SRC}: the send must carry the composed text`);
  assert.match(code, /text = composeMailReply\(/, `${SRC}: the sent text must be built by composeMailReply`);
  assert.doesNotMatch(code, /p_body:\s*reply\b|composeMailReply\(\{[^}]*answer:\s*reply\b/,
    `${SRC} sends the internal-model draft. Move the class to a customer-facing row in ${POLICY_SQL} in the same change.`);
  const senders = [
    ['notifications insert', /from\('notifications'\)\s*\n?\s*\.insert/],
    ['resend api', /api\.resend\.com/],
    ['fn_notify_founder', /fn_notify_founder/],
  ];
  const found = senders.filter(([, re]) => re.test(code)).map(([name]) => name);
  assert.deepEqual(found, [],
    `${SRC} now reaches a send path (${found.join(', ')}). The draft would leave the building without a `
    + 'person reading it, in either of two languages, from a model chosen because nobody outside the '
    + `company sees its output. Move the class to a customer-facing row in ${POLICY_SQL} in the same change.`);
});

test('the routing rationale still names the human gate as its reason', () => {
  const sql = readFileSync(join(REPO, POLICY_SQL), 'utf8');
  // If someone rewrites the rationale to drop the gate, the decision loses its recorded justification
  // and this check loses its subject. Both sides have to move together.
  assert.match(sql, /IF THAT GATE IS EVER REMOVED THIS CLASS MUST MOVE TO THE QWEN ROW/,
    `${POLICY_SQL} no longer records WHY email_triage is on the cheap internal model despite drafting `
    + 'customer-facing Arabic. That sentence is what this check enforces; without it the routing is an '
    + 'unexplained choice and the next session will read it as an oversight.');
});
