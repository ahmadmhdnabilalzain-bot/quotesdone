// THE HOMEPAGE CHAT ANSWERS FAST UNDER THE HOLD (customer_support, E2E stage 1 D5, 30 Sep 2026).
// Measured before: 7.1-8.8 s (13.7 s in the E2E) for answers no model writes. Measured after, on a temporary
// copy of the function on production: 0.9-1.6 s server, 1.1-1.8 s at the client. Offline, over the source: fails
// if a held request goes back through ai_gateway, the held price reasoning, the recall, or one read per limit.
//   node --test scripts/checks/the_homepage_chat_answers_fast_under_the_hold.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const s = readFileSync(fileURLToPath(new URL('../../supabase/functions/site_assistant/index.ts', import.meta.url)), 'utf8');

test('a held visitor question is answered from the FAQ in this worker, not through the gateway', () => {
  const local = s.indexOf('if (!reasoningOpen && !live && !priceCtx) {');
  const gw = s.indexOf('const r = await fetch(GATEWAY');
  assert.ok(local > 0 && gw > local, 'the level-0 lookup no longer precedes the gateway call');
  assert.match(s.slice(local, gw), /admin\.rpc\('fn_faq_answer', \{ p_text: message, p_min_rank: 0\.15, p_embedding: [^}]+p_min_similarity: 0\.86 \}\)/);
  assert.match(s.slice(local, gw), /\} else \{\s*$/, 'the gateway is not the else branch of the held path');
});

test('nothing that only feeds a model runs under the hold, and the reads run together', () => {
  assert.match(s, /if \(reasoningOpen \|\| who\) try \{/, 'held price reasoning runs for an anonymous visitor');
  assert.match(s, /const memory = reasoningOpen\s*\n\s*\? await recallCases\(/, 'the recall runs under the hold');
  assert.match(s, /await Promise\.all\(reads\)/, 'the independent reads are awaited one by one');
  assert.ok(!/await secNum\(/.test(s), 'a limit is read with its own round trip again');
  // The refusal still comes before anything is written or answered.
  const refuse = s.indexOf('return J({ reply: RL_REPLY, rate_limited: true });');
  assert.ok(refuse > 0 && refuse < s.indexOf('const reasoningOpen'), 'the rate-limit refusal moved after the answer');
});
