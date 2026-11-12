// node --test src/components/portal/supplier/serviceQuestions.test.mjs
// THE QUESTION CARDS (12 Nov 2026, slice 4; founder rulings 1647 and 1645). A tap answers at once and the write happens behind it;
// Back shows his answer; a reload resumes at the first card he has not answered; a failed write keeps his taps and is retried;
// what reaches the check screen is only what he tapped. Each case fails if the cards wait on the server, lose a tap, or put a
// key on his list he did not choose.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { advance, back, canSend, cardsOf, failedIds, finalAnswer, goTo, openCards, outcome, progress, resumeIndex, settled, togglePick, unsavedIds } from './serviceQuestions.ts';

const opt = (key, label_en) => ({ key, label_en, own_words: !key });
const STAFF = { id: 11, kind: 'vague', prompt_en: 'Your profile says: "We supply staff and similar services." What sort of staff do you supply?', multi: true, status: 'open', answer: null,
  options: [opt('labour_supply.general', 'General labour'), opt('labour_supply.drivers_operators', 'Drivers & equipment operators'), opt(null, 'Freelancers')] };
const POOLS = { id: 12, kind: 'partner', prompt_en: 'How do you deliver them?', multi: true, status: 'open', answer: null,
  options: [opt('swimming_pools.pool_construction', 'Pool construction'), opt('swimming_pools.pool_maintenance', 'Pool maintenance'), opt('swimming_pools.water_features', 'Fountains & water features')] };
const UMB = { id: 13, kind: 'umbrella', prompt_en: 'Companies like yours often also do these. Tap any you do.', multi: true, status: 'open', answer: null,
  options: [opt('landscaping.hardscape', 'Hardscape'), opt('landscaping.irrigation', 'Irrigation')] };
const LATER = { id: 14, kind: 'shown', prompt_en: 'later', multi: true, status: 'later', answer: null, options: [opt('a.b', 'B')] };

test('a tap advances at once: the next card is on screen before the write lands, and the write is pending', () => {
  let c = openCards([STAFF, POOLS, UMB, LATER]);
  assert.deepEqual(c.ids, [11, 12, 13], 'a card kept for later is not in this sitting');
  assert.equal(progress(c), '1 of 3');
  c = advance(c, 11, togglePick(STAFF, undefined, 1));
  assert.equal(c.index, 1, 'the second card is shown without waiting');
  assert.equal(c.saving[11], 'pending');
  assert.equal(progress(c), '2 of 3');
  assert.deepEqual(c.answers[11], { picked: [1] });
});

test('Back shows the card he answered, with his answer; answering it again moves on from there', () => {
  let c = advance(openCards([STAFF, POOLS, UMB]), 11, { picked: [0] });
  c = back(c);
  assert.equal(c.index, 0);
  assert.deepEqual(c.answers[11], { picked: [0] }, 'his answer is still there');
  c = advance(c, 11, togglePick(STAFF, c.answers[11], 2));
  assert.deepEqual(c.answers[11], { picked: [0, 2] });
  assert.equal(c.index, 1);
  assert.equal(back(back(back(c))).index, 0, 'never before the first card');
  assert.equal(goTo(c, 13).index, 2);
});

test('a reload resumes at the first card he has not answered; with all answered, past the last', () => {
  const answered = { ...STAFF, status: 'answered', answer: { picked: [1] } };
  const c = openCards([answered, POOLS, UMB]);
  assert.equal(c.index, 1);
  assert.equal(c.saving[11], 'saved');
  assert.equal(resumeIndex(cardsOf([answered, { ...POOLS, status: 'answered', answer: { per: { 0: 'own', 1: 'own', 2: 'no' } } }]), {}), 2);
});

test('a failed write says so, keeps his taps, and a retry sends the same answer; a reload brings the kept taps back', () => {
  let c = advance(openCards([STAFF, POOLS]), 11, { picked: [0, 1] });
  c = settled(c, 11, false);
  assert.deepEqual(failedIds(c), [11]);
  assert.deepEqual(c.answers[11], { picked: [0, 1] }, 'nothing lost');
  assert.deepEqual(unsavedIds(c), [11]);
  c = settled(c, 11, true);
  assert.deepEqual(failedIds(c), []);
  // the page was reloaded while the write had failed: the browser kept the taps, the server has none
  const r = openCards([STAFF, POOLS], { 11: { picked: [0, 1] } });
  assert.deepEqual(r.answers[11], { picked: [0, 1] });
  assert.equal(r.saving[11], 'failed', 'shown as not saved, to be sent again');
  assert.equal(r.index, 1);
});

test('Next waits for a whole answer: every service of a partner card, his words on the nothing card', () => {
  assert.equal(canSend(POOLS, { per: { 0: 'partner', 1: 'partner' } }), false);
  assert.equal(canSend(POOLS, { per: { 0: 'partner', 1: 'partner', 2: 'no' } }), true);
  assert.equal(canSend({ kind: 'nothing', options: [] }, { other: ' ' }), false);
  assert.equal(canSend({ kind: 'nothing', options: [] }, { other: 'We supply drivers' }), true);
  assert.equal(canSend(STAFF, { picked: [] }), false);
  assert.equal(canSend(STAFF, { none: true }), true);
  assert.deepEqual(togglePick(STAFF, { none: true }, 0), { picked: [0] }, 'a chip after None of these replaces it');
  assert.deepEqual(togglePick({ multi: false }, { picked: [0] }, 1), { picked: [1] }, 'one only on a single-choice card');
  assert.deepEqual(finalAnswer({ picked: [], other: '  ' , none: true }), { none: true });
});

test('what reaches the check screen is only what he tapped', () => {
  const answers = {
    11: { picked: [1, 2], other: 'dispatch riders' },
    12: { per: { 0: 'partner', 1: 'own', 2: 'no' } },
    13: { none: true },
  };
  const o = outcome([STAFF, POOLS, UMB], answers);
  assert.deepEqual(o.own.sort(), ['labour_supply.drivers_operators', 'swimming_pools.pool_maintenance']);
  assert.deepEqual(o.partner, ['swimming_pools.pool_construction']);
  assert.deepEqual(o.ownWords, ['Freelancers', 'dispatch riders'], 'a picked option with no key and his own words, as written');
  assert.deepEqual(o.declined.sort(), ['landscaping.hardscape', 'landscaping.irrigation', 'swimming_pools.water_features']);
  assert.ok(!o.own.includes('labour_supply.general'), 'an option he did not tap is not his');
  const lic = { id: 15, kind: 'licence', options: [opt(null, 'What my profile says'), opt(null, 'Both'), opt(null, 'What my licence says')], multi: false, status: 'open', answer: null };
  assert.deepEqual(outcome([lic], { 15: { picked: [1] } }).ownWords, [], 'a licence answer is not a service');
});
