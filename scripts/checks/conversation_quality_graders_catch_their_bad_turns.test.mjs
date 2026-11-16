// THE CONVERSATION-QUALITY GRADERS CATCH THEIR BAD TURNS, AND THE CANON AGREES WITH THE PRODUCT (customer_support, 3 Nov 2026).
// Offline: no token, no database, no model.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * a grader in scripts/eval/conversation_quality.mjs passes a hallucinated fee, timeline, refund promise, invented address
//     or premises, a named supplier, a wrong-language reply, a superseded quantity, or fails a correct answer (selfTest);
//   * the independent judge's calibration set loses its balance (half hallucinated, half clean) or its 16 items;
//   * the brief the customer-facing models are given (knowledge/brief/company.md, compiled into brief.generated.ts) states
//     an inquiry edit window other than the one the product enforces (customer_api EDIT_WINDOW_MS, fn_edit_inquiry): the
//     live run of 3 Nov 2026 found company.md saying 24 hours while the product and the FAQ say 1 hour;
//   * the brief stops stating the refund method the published Refund Policy states (the original payment method), or
//     stops saying a drawing that cannot be covered is described no further (the judge's findings, 3 Nov 2026).
//
//   node --test scripts/checks/conversation_quality_graders_catch_their_bad_turns.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { selfTest, LABELLED, SCENARIOS, gradeConversation } from '../eval/conversation_quality.mjs';
import { BRIEF_TEXT } from '../../supabase/functions/_shared/brief.generated.ts';
import { functionSource } from '../lib/function_sources.mjs';

test('every grader catches its known-bad turn and passes its known-good one', () => {
  const r = selfTest();
  assert.deepEqual(r.fails, [], r.fails.join('\n'));
});

test('the judge is calibrated on a balanced labelled set', () => {
  assert.equal(LABELLED.length, 16);
  assert.equal(LABELLED.filter((l) => l.hallucinated).length, 8);
});

test('a superseded quantity in a restatement is caught across a whole scripted conversation', () => {
  const sc = SCENARIOS.find((s) => s.id === 'villa_windows_sharjah');
  const transcript = sc.turns.flatMap((t, i) => [{ role: 'customer', text: t.say },
    { role: 'agent', text: t.kind === 'ask_restate' ? 'You asked for 12 windows with 6mm glass in Sharjah.' : i === 1 ? 'Posting is free; the reveal fee is 3%.' : 'Thanks, please sign up at /me to continue. WhatsApp +1 218 316 6814 or management@quotesdone.com, sorry for the trouble.' }]);
  const g = gradeConversation(sc, 'portal', transcript);
  assert.equal(g.restated_wrong, 3,   // 12 for 14 windows, 6 for 8 mm, the sliding doors left out
    JSON.stringify(g.turns.filter((t) => t.restated_wrong)));
  assert.equal(g.hallucinated_facts, 0);
});

test('the brief states that a request is revised until a supplier is revealed, as the product does (16 Nov 2026)', () => {
  const api = functionSource('customer_api');
  // no edit window any more: fn_edit_inquiry revises a request until it is revealed, paid or closed
  assert.doesNotMatch(api, /const EDIT_WINDOW_MS = /, 'customer_api still carries an edit window');
  assert.match(BRIEF_TEXT, /\*\*until he reveals a supplier\*\*/, 'the brief states the request is changed until a reveal');
  assert.doesNotMatch(BRIEF_TEXT, /edit an inquiry within \*\*(1 hour|24 hours)\*\*/);
});

test('the brief states the refund method the Refund Policy states, and no fallback for an uncovered drawing', () => {
  const legal = JSON.parse(readFileSync(new URL('../../src/content/legal.json', import.meta.url), 'utf8'));
  assert.match(JSON.stringify(legal['refund-policy']), /issued to the original payment method/);
  assert.match(BRIEF_TEXT, /issued \*\*to the original payment method\*\* through Stripe/);
  assert.match(BRIEF_TEXT, /a drawing that cannot be covered is not shared\. \(FAQ "Is my identity hidden\?"\) Say only that/);
});
