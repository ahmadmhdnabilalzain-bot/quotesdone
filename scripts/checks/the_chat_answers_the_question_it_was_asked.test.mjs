// Recurrence gate for the customer audit of 21 Sep 2026, findings 6, 7, 13 (docs/audits/CHAT_ANSWERS_21_SEP_2026.md).
// The behaviour itself is replayed by supabase/functions/_shared/chat_answers.test.ts; this file fails if
// the ORDER that makes it reach a customer is undone:
//   13  the public widget routes count / cost / timeline (REASONED since 23 Sep 2026: siteQuestion, never lexemes)
//       BEFORE the model key and the gateway,
//       so a held ai_gateway (circuit_open) can never again refuse "what does it cost?";
//    7  the portal chat reads the customer's own quote BEFORE the corpora, drops off-topic passages (a reasoned choice since 23 Sep 2026), and
//       never prints the raw "[corpus · provenance]" tag;
//    6  a revealed conversation that has not been opened yet reads "Ready to message", not "No chat open",
//       and its row is a keyboard-reachable button.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');

// 12 Oct 2026 (founder rulings 1195/1196): the widget's deterministic route (pickFaq before the gateway) and the portal's
// assembled-passage reply were REMOVED — every conversation reply is written by a model. These two tests now assert that.
test('site_assistant has no stored-answer route: the reply is one model call from the company brief', () => {
  const s = read('supabase/functions/site_assistant/index.ts');
  for (const gone of ['pickFaq(', 'capabilityStatement(', 'cachedReply(']) assert.ok(!s.includes(gone), 'a stored-answer road is back: ' + gone);
  assert.ok(s.includes('await answerFromBrief({'), 'the reply must be the model call');
});

test('sales_engineer gives the own quote to the model as a fact, prints no assembled passages, no raw tags', () => {
  const s = read('supabase/functions/sales_engineer/index.ts');
  const own = s.indexOf('answerFromOwnQuotes(caller.customerId');
  const rpc = s.indexOf("rpc('fn_sales_assist'");
  assert.ok(own > 0 && rpc > 0 && own < rpc, 'own-quote fact must precede fn_sales_assist');
  assert.ok(s.includes("facts: ownQuote ? 'THEIR OWN REQUESTS AND QUOTES"), 'the own quote is a fact for the composed reply');
  assert.ok(!s.includes('notYet(') && !s.includes('const recs = pick'), 'a code-written reply (notYet / assembled passages) is back');
  assert.doesNotMatch(s, /'\[' \+ String\(x\.corpus\)/, 'the raw [corpus · provenance] tag is back in the reply');
  assert.match(s, /setTimeout\(\(\) => r\(null\), 1500\)/, 'the gte-small embed must stay bounded');
});

test('Messages: a revealed, unopened chat is ready to message and the row is a button', () => {
  const s = read('src/components/portal/comms/CommunicationCenter.tsx');
  assert.match(s, /: w\.st_ready;\n/, "statusWord must fall through to st_ready, not st_none");
  assert.match(s, /role="button" tabIndex=\{0\}/);
  assert.match(s, /st_ready: 'جاهزة للمراسلة'/);
});
