// node --test src/components/portal/supplier/serviceQuestions.test.mjs
// THE QUESTION CARDS (12 Nov 2026, slice 4; founder rulings 1647 and 1645). A tap answers at once and the write happens behind it;
// Back shows his answer; a reload resumes at the first card he has not answered; a failed write keeps his taps and is retried;
// what reaches the check screen is only what he tapped. Each case fails if the cards wait on the server, lose a tap, or put a
// key on his list he did not choose.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { liveQuestions, advance, back, canSend, cardsOf, failedIds, finalAnswer, goTo, openCards, outcome, progress, readFlow, resumeIndex, selection, settled, splitPrompt, TAP_GUARD_MS, tapAllowed, togglePick, unsavedIds, writeFlow } from './serviceQuestions.ts';

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
  assert.deepEqual(o.partnerWords, []);
  assert.deepEqual(o.declined.sort(), ['landscaping.hardscape', 'landscaping.irrigation', 'swimming_pools.water_features']);
  assert.ok(!o.own.includes('labour_supply.general'), 'an option he did not tap is not his');
  const lic = { id: 15, kind: 'licence', options: [opt(null, 'What my profile says'), opt(null, 'Both'), opt(null, 'What my licence says')], multi: false, status: 'open', answer: null };
  assert.deepEqual(outcome([lic], { 15: { picked: [1] } }).ownWords, [], 'a licence answer is not a service');
});

// Review of slice 4 (12 Nov 2026), finding 1, replayed: the decoration company ticks "3D visualisation" (Please check) and "Hardscape" (From
// your projects) on screen 1, and the pools card says "Partner" for construction. Only the pools are partner work.
const ROWS = [
  { key: 'interior_fitout.decoration', delivery: 'own', basis: 'stated' },
  { key: 'design_consultancy.visualisation_3d', delivery: 'own', basis: 'stated', check: true },
  { key: 'landscaping.hardscape', delivery: 'own', basis: 'shown' },
  { key: 'swimming_pools.pool_maintenance', delivery: 'partner', basis: 'partner' },
];
test('finding 1: a "Please check" or project row he ticks is his own work; only a partner row or a partner answer is partner work', () => {
  const ticked = new Set(['interior_fitout.decoration', 'design_consultancy.visualisation_3d', 'landscaping.hardscape', 'swimming_pools.pool_maintenance']);
  const sel = selection({ rows: ROWS, ticked, readWords: [], wordsTicked: new Set(), questions: [POOLS], answers: { 12: { per: { 0: 'partner', 1: 'own', 2: 'no' } } } });
  assert.deepEqual(sel.partner.sort(), ['swimming_pools.pool_construction']);
  assert.ok(sel.own.includes('design_consultancy.visualisation_3d') && sel.own.includes('landscaping.hardscape'), 'his ticks are his own team');
  assert.ok(sel.own.includes('swimming_pools.pool_maintenance'), 'the card said own team: that answer wins over the partner row');
  // known-bad: the tab's old rule (every ticked row of the "other" list is partner) would have filed both as partner
  const old = ROWS.filter((r) => (r.delivery === 'partner' || r.basis === 'shown' || r.check) && ticked.has(r.key)).map((r) => r.key);
  assert.ok(old.includes('design_consultancy.visualisation_3d') && !sel.partner.includes('design_consultancy.visualisation_3d'));
});

test('finding 12: his words for work through a partner are confirmed with that basis, and listed with the partner work', () => {
  const card = { id: 21, kind: 'partner', prompt_en: '', multi: true, status: 'open', answer: null, options: [opt(null, 'Jacuzzi'), opt(null, 'Sauna')] };
  const sel = selection({ rows: [], ticked: new Set(), readWords: [{ words: 'Garden lighting', basis: 'stated' }], wordsTicked: new Set(['Garden lighting']),
    questions: [card], answers: { 21: { per: { 0: 'partner', 1: 'own' } } } });
  assert.deepEqual(sel.partnerWords, ['Jacuzzi']);
  assert.deepEqual(sel.ownWords.sort(), ['Garden lighting', 'Sauna']);
  assert.deepEqual(sel.words.sort(), ['Garden lighting', 'Jacuzzi', 'Sauna'], 'all of them are sent as his words');
});

test('what he confirms is only what he ticked or answered, minus what he struck out; a stored partner key stays partner unless he says own', () => {
  const sel = selection({ rows: ROWS, ticked: new Set(), readWords: [], wordsTicked: new Set(), questions: [], answers: {},
    more: ['gypsum.false_ceiling', 'painting.interior'], storedPartner: ['gypsum.false_ceiling', 'not.stated'], dropped: new Set(['painting.interior']) });
  assert.deepEqual(sel.stated, ['gypsum.false_ceiling']);
  assert.deepEqual(sel.partner, ['gypsum.false_ceiling'], 'a stored partner key not stated now is not sent');
});

test('finding 7: the prompt splits at his own sentence, even when it holds an inch mark', () => {
  const quote = 'We do 24" ducts and   chiller   lines.';
  const prompt = 'Your profile says: "We do 24" ducts and chiller lines." Which of these do you do?';
  assert.deepEqual(splitPrompt(prompt, quote), { quote: 'We do 24" ducts and chiller lines.', ask: 'Which of these do you do?' });
  assert.deepEqual(splitPrompt('Your profile says these are delivered "through our partner". How do you deliver them?', 'through our partner'), { quote: 'through our partner', ask: 'How do you deliver them?' });
  assert.deepEqual(splitPrompt('Companies like yours often also do these.', null), { quote: null, ask: 'Companies like yours often also do these.' });
});

test('finding 6: a second tap within the guard after a card changes is ignored; a tap after it is taken', () => {
  assert.equal(tapAllowed(1000, 1000 + 120), false, 'the double tap');
  assert.equal(tapAllowed(1000, 1000 + TAP_GUARD_MS), true);
  assert.ok(TAP_GUARD_MS >= 300 && TAP_GUARD_MS <= 400);
});

test('finding 2: screen 1\'s ticks are kept with the step for the same reading, and a new reading starts clean', () => {
  const store = new Map();
  globalThis.localStorage = { getItem: (k) => store.get(k) ?? null, setItem: (k, v) => store.set(k, v), removeItem: (k) => store.delete(k) };
  try {
    writeFlow({ at: '2026-11-12T10:00:00Z', step: 'questions', ticked: ['interior_fitout.decoration'], words: ['Gazebos'] });
    assert.deepEqual(readFlow('2026-11-12T10:00:00Z'), { at: '2026-11-12T10:00:00Z', step: 'questions', ticked: ['interior_fitout.decoration'], words: ['Gazebos'] });
    assert.equal(readFlow('2026-11-13T09:00:00Z'), null, 'another reading');
  } finally { delete globalThis.localStorage; }
});

// Round-2 review of slice 4, finding A: "Carpet" picked by mistake on the last card could not be taken out.
test('finding A: a key from a card answer or a screen-1 tick can be removed, is reported as removed, and stays out after a confirm', () => {
  const answers = { 13: { picked: [0, 1] } };   // Hardscape and Irrigation picked on the "companies like yours" card
  const base = { rows: ROWS, ticked: new Set(['interior_fitout.decoration']), readWords: [], wordsTicked: new Set(), questions: [UMB], answers };
  const kept = selection(base);
  assert.ok(kept.stated.includes('landscaping.irrigation') && kept.stated.includes('interior_fitout.decoration'));
  const out = selection({ ...base, dropped: new Set(['landscaping.irrigation', 'interior_fitout.decoration']) });
  assert.ok(!out.stated.includes('landscaping.irrigation') && !out.stated.includes('interior_fitout.decoration'), 'both removed');
  assert.deepEqual(out.removed.sort(), ['interior_fitout.decoration', 'landscaping.irrigation'], 'reported, so the save subtracts them and the screen offers them back');
  // after his confirm (which no longer held Irrigation) the old answer does not bring it back on a reload
  const answered = { ...UMB, status: 'answered', answer: { picked: [0, 1] }, answered_at: '2026-11-12T10:00:00Z' };
  assert.deepEqual(liveQuestions([answered], { 13: { picked: [0, 1] } }, '2026-11-12T11:00:00Z'), [], 'answered before the confirm: the confirm is the record');
  assert.equal(liveQuestions([answered], { 13: { picked: [0] } }, '2026-11-12T11:00:00Z').length, 1, 'answered again now: it counts');
  assert.equal(liveQuestions([answered], {}, null).length, 1, 'before any confirm: every answer counts');
});

// Round-3 review of slice 4, finding 5: his own words taken out before his first confirm are offered back too.
test('finding 5: a saved phrase, a reading phrase and a partner phrase he took out are reported as removedWords, once each', () => {
  const readWords = [{ words: 'Jacuzzi installation', basis: 'partner' }, { words: 'Garden lighting', basis: 'stated' }];
  const base = { rows: ROWS, ticked: new Set(), readWords, wordsTicked: new Set(['Jacuzzi installation', 'Garden lighting']), questions: [], answers: {}, savedWords: ['Pergolas', 'pergolas'] };
  const kept = selection(base);
  assert.deepEqual(kept.removedWords, []);
  assert.deepEqual(kept.partnerWords, ['Jacuzzi installation']);
  const out = selection({ ...base, dropped: new Set(['word:Pergolas', 'word:Jacuzzi installation']) });
  assert.deepEqual(out.removedWords, ['Pergolas', 'Jacuzzi installation'], 'offered back, the same phrase once');
  assert.deepEqual(out.words, ['Garden lighting']);
  assert.deepEqual(out.removed, [], 'a word is not a service key: the save does not subtract it as one');
});
