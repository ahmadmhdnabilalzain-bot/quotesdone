// The one-question-at-a-time spec helper: multiple choice, "Other" typed, "not sure" never sent.
//   node --test src/components/me/specSteps.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { choicesFor, answerOf, stepDone, collectAnswers, NOT_SURE, OTHER } from './specSteps.ts';

const product = { key: 'product', ask: 'What are you after?', options: ['Sign/letters', 'Display/stand', 'Other'] };
const area = { key: 'area_m2', ask: 'How big?', type: 'number', options: [] };

test('options become choices; Other is typed; not sure always last', () => {
  assert.deepEqual(choicesFor(product), ['Sign/letters', 'Display/stand', OTHER, NOT_SURE]);
  assert.deepEqual(choicesFor(area), [NOT_SURE]);
});

test('a chosen option is the answer; Other takes the typed words', () => {
  assert.equal(answerOf(product, 'Display/stand', ''), 'Display/stand');
  assert.equal(answerOf(product, OTHER, '  neon box '), 'neon box');
  assert.equal(answerOf(product, 'made-up', ''), null);
  assert.equal(answerOf(area, undefined, '40'), '40');
});

test('not sure finishes the step but is never sent', () => {
  assert.equal(stepDone(product, NOT_SURE, ''), true);
  assert.equal(stepDone(product, undefined, ''), false);
  assert.equal(stepDone(area, undefined, ''), false);
  assert.deepEqual(collectAnswers([product, area], { product: NOT_SURE }, { area_m2: '40' }), { area_m2: '40' });
  assert.deepEqual(collectAnswers([product, area], { product: NOT_SURE, area_m2: NOT_SURE }, {}), {});
});
