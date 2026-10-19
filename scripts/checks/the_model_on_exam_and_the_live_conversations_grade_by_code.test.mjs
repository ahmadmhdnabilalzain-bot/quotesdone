// THE MODEL-ON EXAM AND THE LIVE CONVERSATIONS GRADE BY CODE (ledgers 1084 and 1200, 19 Oct 2026). it_engineer.
// Offline: no token, no database, no model.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * the exam grader (scripts/eval/seat_exam_llm_on.mjs) passes an answer missing an expected fact, or fails one that
//     states it with other punctuation or case;
//   * the scripted customer (scripts/e2e/live_seat_conversations.mjs) volunteers a fact it was not asked for, or gives
//     the same fact twice; the code gates miss an "I don't know", a yes/no-only reply, or a reply in the wrong language;
//   * the suite falls below 30 scenarios, or loses Arabic or either seat;
//   * the weekly audit (scripts/e2e/knowledge_gap_audit.mjs) proposes a real knowledge question as 'not a gap'.
//
//   node --test scripts/checks/the_model_on_exam_and_the_live_conversations_grade_by_code.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { missingFacts } from '../eval/seat_exam_llm_on.mjs';
import { S, customerTurn, codeGates } from '../e2e/live_seat_conversations.mjs';
import { proposeNotAGap } from '../e2e/knowledge_gap_audit.mjs';

test('the exam grader needs every expected fact, in any case or hyphenation', () => {
  assert.deepEqual(missingFacts('Check the Title-Block and the latest REVISION first.', ['title block', 'revision']), []);
  assert.deepEqual(missingFacts('Check the title block first.', ['title block', 'revision']), ['revision']);
  assert.deepEqual(missingFacts('', ['3%']), ['3%']);
});

test('the scripted customer answers only what was asked, once', () => {
  const w = S.find((s) => s.id === 'wardrobe_photo');
  const given = new Set();
  assert.equal(customerTurn(w, 'Thanks for the photo, it helps.', given), null);
  assert.match(customerTurn(w, 'How wide is the wall?', given), /2\.4 m wide/);
  assert.equal(customerTurn(w, 'And how wide again?', given), null);
  assert.match(customerTurn(w, 'Here is the summary: a 2.4 m wardrobe. Is that correct?', given), /correct/);
  assert.equal(customerTurn(w, 'The depth is to confirm at the site visit. Anything else on the wall?', given), null);
});

test('the code gates catch a hedge, a yes/no-only reply and the wrong language', () => {
  const en = S.find((s) => s.lang === 'en'), ar = S.find((s) => s.lang === 'ar');
  assert.equal(codeGates(en, ['Great, what size is the wall?']).pass, true);
  assert.equal(codeGates(en, ["Good question. I don't know, what size is it?"]).no_idk, false);
  assert.equal(codeGates(en, ['Yes.']).no_yesno_only, false);
  assert.equal(codeGates(ar, ['What size is the room?']).language, false);
  assert.equal(codeGates(ar, ['ما هي مساحة الغرفة؟']).pass, true);
  assert.equal(codeGates(en, ['Thanks, we will arrange it.']).asks_first, false);
});

test('the suite holds at least 30 scenarios, both seats, both languages', () => {
  assert.ok(S.length >= 30, `${S.length} scenarios`);
  assert.ok(S.some((s) => s.lang === 'ar' && s.seat === 'sales') && S.some((s) => s.lang === 'ar' && s.seat === 'support'));
  assert.ok(S.some((s) => s.lang === 'en' && s.seat === 'sales') && S.some((s) => s.lang === 'en' && s.seat === 'support'));
  assert.equal(new Set(S.map((s) => s.id)).size, S.length);
});

test('the weekly audit never proposes a real question as not a gap', () => {
  assert.equal(proposeNotAGap({ question: 'how do I specify a fire alarm system so suppliers can quote it properly', refusal: 'not_corroborated_lexically' }), null);
  assert.ok(proposeNotAGap({ question: 'what does it cost?', refusal: 'circuit_open' }));
  assert.ok(proposeNotAGap({ question: 'ZZ DEMO - turn 2: what about the back panel?', refusal: 'below_similarity_floor' }));
});
