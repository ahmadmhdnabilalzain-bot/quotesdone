// THE HOMEPAGE CHAT ANSWERS FAST (customer_support, E2E stage 1 D5, 30 Sep 2026; rewritten 12 Oct 2026).
//
// 30 Sep 2026: the held widget answered from the FAQ in its own worker (fn_faq_answer, level 0) instead of a round trip
// through ai_gateway, and skipped the held price reasoning and the recall (7.1-8.8 s -> 0.9-1.6 s). That held road no
// longer exists: founder ruling 1196 (12 Oct 2026) — "every reply to a customer, supplier or visitor is written by the
// AI in that moment; remove every code-written or canned reply path (FAQ text returned as-is ...)". The two tests that
// pinned the level-0 FAQ road and the held price reasoning are RETIRED with their subject; what they protected — a
// fast answer, no wasted work before it, the refusal before anything else — is pinned below against the new design:
// one streamed model call from the company brief (_shared/brief_answer.ts).
//   node --test scripts/checks/the_homepage_chat_answers_fast_under_the_hold.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const s = readFileSync(fileURLToPath(new URL('../../supabase/functions/site_assistant/index.ts', import.meta.url)), 'utf8');

test('ruling 1196: no stored answer is returned as-is, and the reply is one model call from the brief', () => {
  assert.ok(!s.includes("admin.rpc('fn_faq_answer'"), 'the level-0 FAQ answer is back (ruling 1196 removed it)');
  assert.ok(!s.includes('priceGuidanceFor('), 'a second reasoning chain (the price reasoning) runs before the reply again');
  assert.equal((s.match(/await answerFromBrief\(\{/g) || []).length, 1, 'the reply is not exactly one model call');
});

test('nothing slow runs before the answer, and the refusal still comes first', () => {
  assert.match(s, /await Promise\.all\(reads\)/, 'the independent reads are awaited one by one');
  assert.ok(!/await secNum\(/.test(s), 'a limit is read with its own round trip again');
  // the brief and the recall are read together, not one after the other
  // 19 Oct 2026: the given trade knowledge joins the same parallel read, bounded by its own timeout (given_trade_knowledge.ts).
  assert.match(s, /const \[brief, memory(, given)?\] = await Promise\.all\(\[/, 'the brief and the recall are read in series');
  if (/givenTradeKnowledge\(/.test(s)) assert.match(readFileSync(new URL('../../supabase/functions/_shared/given_trade_knowledge.ts', import.meta.url), 'utf8'), /withTimeout\(fetchGiven\(/, 'the given trade knowledge read lost its timeout');
  // the refusal names its bucket since 11 Nov 2026 (site_assistant/limit_chain.ts refusedBucket); it must still come first
  const refuse = s.search(/return J\(\{ reply: RL_REPLY, rate_limited: true(, bucket)? \}\);/);
  assert.ok(refuse > 0 && refuse < s.indexOf('await answerFromBrief({'), 'the rate-limit refusal moved after the answer');
});
