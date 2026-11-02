// THE MODEL-ON EXAM AND THE LIVE CONVERSATIONS GRADE BY CODE (ledgers 1084 and 1200, 19 Oct 2026). it_engineer.
// Offline: no token, no database, no model.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * the exam grader (scripts/eval/seat_exam_llm_on.mjs) passes an answer missing an expected fact, or fails one that
//     states it with other punctuation or case;
//   * the scripted customer (scripts/e2e/live_seat_conversations.mjs) volunteers a fact it was not asked for, or gives
//     the same fact twice; the code gates miss an "I don't know", a yes/no-only reply, or a reply in the wrong language;
//   * the gates miss a question about what the opening already said, a must-have never asked, a wrong spec accepted,
//     or a reply after the 150 s request limit (27 Oct 2026, customer_support);
//   * the bank (scripts/e2e/adaptive_conversation_bank.mjs) falls below 40 scenarios, loses a top trade, Arabic, a
//     wrong-spec trap or the changed-mind scenario, or a scenario loses its expert follow-ups or its must-have;
//   * the seven daily slices stop covering the whole bank exactly once;
//   * the weekly audit (scripts/e2e/knowledge_gap_audit.mjs) proposes a real knowledge question as 'not a gap'.
//
//   node --test scripts/checks/the_model_on_exam_and_the_live_conversations_grade_by_code.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { missingFacts } from '../eval/seat_exam_llm_on.mjs';
import { S, customerTurn, codeGates, pick, turnLatency, outcomes } from '../e2e/live_seat_conversations.mjs';
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
  const en = S.find((s) => s.id === 'wardrobe_photo'), ar = S.find((s) => s.id === 'painting_ar');
  assert.equal(codeGates(en, ['Great, what size is the wall?']).no_idk, true);
  assert.equal(codeGates(en, ["Good question. I don't know, what size is it?"]).no_idk, false);
  assert.equal(codeGates(en, ['Yes.']).no_yesno_only, false);
  assert.equal(codeGates(ar, ['What size is the room?']).language, false);
  assert.equal(codeGates(ar, ['ما هي مساحة الغرفة؟']).language, true);
  assert.equal(codeGates(en, ['Thanks, we will arrange it.']).asks_first, false);
});

// 27 Oct 2026, the failure modes of ledger 1200 that the gates did not see: a question about what the customer already
// said, a must-have never asked, and a wrong spec accepted.
test('the code gates catch a told fact asked again, a must-have never asked and a wrong spec accepted', () => {
  const k = S.find((s) => s.id === 'kitchen_photo_en');
  assert.equal(codeGates(k, ['Nice photo. How long is the kitchen run?']).no_reask_told, false);
  assert.equal(codeGates(k, ['A 3.6 m run gives room for a hob and sink. Which worktop material do you want?']).no_reask_told, true);
  const w = S.find((s) => s.id === 'wardrobe_photo');
  assert.equal(codeGates(w, ['What colour would you like?']).must_asked, false);
  assert.equal(codeGates(w, ['What are the wall width and ceiling height?', 'Hanging or shelves inside?', 'Sliding or hinged doors?']).must_asked, true);
  const fa = S.find((s) => s.id === 'fire_alarm_office');
  assert.equal(codeGates(fa, ['Sure, normal cable works. How big is the office?']).trap_corrected, false);
  assert.equal(codeGates(fa, ['Fire alarm circuits need fire-rated cable such as FP200; normal cable is not accepted. How big is the office?']).trap_corrected, true);
  const full = codeGates(w, ['What are the wall width and ceiling height?', 'Hanging, shelves or drawers inside?', 'Sliding or hinged doors, with handles?']);
  assert.equal(full.pass, true, JSON.stringify(full));
});

test('a reply after the 150 s request limit fails on time, whatever it says', () => {
  const w = S.find((s) => s.id === 'wardrobe_photo');
  const turns = ['What are the wall width and ceiling height?', 'Hanging, shelves or drawers inside?', 'Sliding or hinged doors, with handles?'];
  assert.equal(codeGates(w, turns, null, [40000, 151000, 30000]).in_time, false);
  assert.equal(codeGates(w, turns, null, [40000, 150000, 30000]).pass, true);
  assert.equal(codeGates(w, turns).in_time, true, 'a stored run without timings is graded on content only');
});

test('a fact asked again after it was given is flagged for the judge, never failed by code alone', () => {
  const w = S.find((s) => s.id === 'wardrobe_photo');
  const g = codeGates(w, ['What are the wall width and ceiling height?', 'Hanging or shelves inside, and sliding or hinged doors?', 'And what is the width of the wall?'], new Map([[0, 0]]));
  assert.equal(g.reask_flagged.length, 1);
  assert.equal(g.pass, true);
});

test('the bank holds at least 40 scenarios across the top trades, both languages, all in the portal (ruling 1249)', () => {
  assert.ok(S.length >= 40, `${S.length} scenarios`);
  assert.ok(S.filter((s) => s.lang === 'ar').length >= 15 && S.filter((s) => s.lang === 'en').length >= 15);
  assert.equal(new Set(S.map((s) => s.id)).size, S.length);
  for (const t of ['carpentry-joinery', 'kitchens', 'hvac', 'fire-safety', 'security', 'flooring', 'glass', 'aluminium', 'painting', 'mep-maintenance'])
    assert.ok(S.some((s) => s.trade === t), `no scenario for ${t}`);
  assert.ok(S.some((s) => s.image === 'studio' && s.trade === 'carpentry-joinery'), "the founder's wardrobe from a photo");
  assert.ok(S.filter((s) => s.trap).length >= 4 && S.some((s) => s.trap && s.lang === 'ar'), 'wrong-spec traps in both languages');
  assert.ok(S.some((s) => s.keeps), 'a changed mind the summary must keep');
});

test('seven daily slices cover the whole bank exactly once', () => {
  const seen = [];
  for (let i = 0; i < 7; i++) seen.push(...pick(S, [], `${i}/7`).map((s) => s.id));
  assert.equal(seen.length, S.length);
  assert.equal(new Set(seen).size, S.length);
  assert.deepEqual(pick(S, ['cctv_shop'], 'today').map((s) => s.id), ['cctv_shop'], '--only wins over --slice');
  assert.equal(pick(S, [], 'today', new Date(Date.UTC(2026, 9, 27))).length, pick(S, [], `${300 % 7}/7`).length);
  assert.throws(() => pick(S, [], '7/7'));
});

test('every scenario is gradable: expert follow-ups, a must-have, and a trap its own opening does not satisfy', () => {
  for (const s of S) {
    assert.ok(Array.isArray(s.expert) && s.expert.length >= 3, `${s.id}: expert follow-ups`);
    assert.ok(s.facts.some((x) => x[2]?.must), `${s.id}: at least one must-have`);
    assert.ok(Array.isArray(s.told), `${s.id}: told`);
    if (s.trap) {
      assert.ok(s.trap.expect instanceof RegExp && s.trap.why, `${s.id}: trap`);
      assert.ok(!s.trap.expect.test(s.open), `${s.id}: the opening itself must not satisfy its own trap`);
    }
  }
});

test('the weekly audit never proposes a real question as not a gap', () => {
  assert.equal(proposeNotAGap({ question: 'how do I specify a fire alarm system so suppliers can quote it properly', refusal: 'not_corroborated_lexically' }), null);
  assert.ok(proposeNotAGap({ question: 'what does it cost?', refusal: 'circuit_open' }));
  assert.ok(proposeNotAGap({ question: 'ZZ DEMO - turn 2: what about the back panel?', refusal: 'below_similarity_floor' }));
});

// 27 Oct 2026: every run records per-turn latency (the portal turn's 150 s wall), and a turn with no answer is counted
test('every run records per-turn latency: p50, p95 and the turns that got no answer', () => {
  const r = turnLatency([{ transcript: [{ role: 'customer', text: 'x' }, ...[4000, 9000, 12000, 30000].map((ms) => ({ role: 'agent', text: 'ok', ms })), { role: 'agent', text: '(NO ANSWER: 503 no_answer)', ms: 70000 }] }]);
  assert.deepEqual(r, { turns: 5, p50_s: 12, p95_s: 70, max_s: 70, no_answer: 1 });
});

// 27 Oct 2026, evening: the three point losses (stalls before the summary, the timeline never asked, re-asks) are counted
// from the transcript, the same way for a run before a change and after it
test('every run counts the conversations that stalled before the summary, the timeline asked, and the re-ask flags', () => {
  const w = S.find((s) => s.id === 'wardrobe_photo');
  const whenIdx = w.facts.findIndex(([k]) => k === 'when');
  const done = { id: 'wardrobe_photo', released: [[whenIdx, 3]], gates: { reask_flagged: [{ turn: 4 }] },
    transcript: [{ role: 'customer', text: w.open }, { role: 'agent', text: 'Here is your request. Is this correct?' }, { role: 'customer', text: 'Yes, that is correct.' }] };
  const stalled = { id: 'wardrobe_photo', released: [], gates: { reask_flagged: [] },
    transcript: [{ role: 'customer', text: w.open }, { role: 'agent', text: 'Anything else?' }] };
  const o = outcomes([done, stalled]);
  assert.equal(o.confirmed_summary, 1);
  assert.deepEqual(o.stalled_before_summary, ['wardrobe_photo']);
  assert.equal(o.timeline_asked, 1);
  assert.equal(o.timeline_scenarios, 2);
  assert.equal(o.reask_flags, 1);
});
