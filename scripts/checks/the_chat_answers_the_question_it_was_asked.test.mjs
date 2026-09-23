// Recurrence gate for the customer audit of 21 Sep 2026, findings 6, 7, 13 (docs/audits/CHAT_ANSWERS_21_SEP_2026.md).
// The behaviour itself is replayed by supabase/functions/_shared/chat_answers.test.ts; this file fails if
// the ORDER that makes it reach a customer is undone:
//   13  the public widget routes count / cost / timeline (REASONED since 23 Sep 2026: siteQuestion, never lexemes)
//       BEFORE the model key and the gateway,
//       so a held ai_gateway (circuit_open) can never again refuse "what does it cost?";
//    7  the portal chat reads the customer's own quote BEFORE the corpora, drops off-topic passages, and
//       never prints the raw "[corpus · provenance]" tag;
//    6  a revealed conversation that has not been opened yet reads "Ready to message", not "No chat open",
//       and its row is a keyboard-reachable button.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');

test('site_assistant answers the routed questions before it reads the model key or calls the gateway', () => {
  const s = read('supabase/functions/site_assistant/index.ts');
  const route = s.indexOf('pickFaq(qType');
  const key = s.indexOf("sec('cred_fn_ai')");
  const gw = s.indexOf('fetch(GATEWAY');
  assert.ok(route > 0 && key > 0 && gw > 0, 'markers missing');
  assert.ok(route < key, 'the deterministic route must come before the model key is read');
  assert.ok(route < gw, 'the deterministic route must come before the gateway call');
});

test('sales_engineer answers from the own quote first, filters off-topic passages, prints no raw tags', () => {
  const s = read('supabase/functions/sales_engineer/index.ts');
  const own = s.indexOf('answerFromOwnQuotes(caller.customerId');
  const rpc = s.indexOf("rpc('fn_sales_assist'");
  assert.ok(own > 0 && rpc > 0 && own < rpc, 'own-quote answer must precede fn_sales_assist');
  assert.match(s, /\.filter\(\(x\) => onTopic\(message/, 'retrieved passages must be filtered by onTopic');
  assert.doesNotMatch(s, /'\[' \+ String\(x\.corpus\)/, 'the raw [corpus · provenance] tag is back in the reply');
  assert.match(s, /setTimeout\(\(\) => r\(null\), 1500\)/, 'the gte-small embed must stay bounded');
});

test('Messages: a revealed, unopened chat is ready to message and the row is a button', () => {
  const s = read('src/components/portal/comms/CommunicationCenter.tsx');
  assert.match(s, /: w\.st_ready;\n/, "statusWord must fall through to st_ready, not st_none");
  assert.match(s, /role="button" tabIndex=\{0\}/);
  assert.match(s, /st_ready: 'جاهزة للمراسلة'/);
});
