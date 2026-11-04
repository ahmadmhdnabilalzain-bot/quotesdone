// pdf_facts.test.mjs — the nightly's money verdict on the two quotation languages. Seat: sales_engineer.
// Replays the 24 Sep 2026 night: the English quotation read 6 amounts, the Arabic request was HELD
// (HTTP 202 arabic_held, no url), and the step reported "no amounts read: 6 and 0" as different money.
// Run: node --test scripts/e2e/pdf_facts.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { moneyVerdict } from './pdf_facts.mjs';

const doc = (text) => ({ ok: true, text, arabicShare: 0 });
const en = doc('95.00 17,100.00 42.00 8,820.00 25,920.00 25,920.00');

test('a held Arabic document is not a money disagreement', () => {
  const v = moneyVerdict(en, { ok: false, why: 'no url' });
  assert.equal(v.status, 'SKIP');
  assert.match(v.why, /ar: no url/);
});

test('the same figures pass; other figures, or none, still fail', () => {
  assert.equal(moneyVerdict(en, doc('95.00 17,100.00 42.00 8,820.00 25,920.00 25,920.00')).status, 'PASS');
  assert.equal(moneyVerdict(en, doc('95.00 17,100.00 42.00 8,820.00 25,920.00 25,902.00')).status, 'FAIL');
  assert.equal(moneyVerdict(en, doc('no figures at all')).status, 'FAIL');
});

// 3 Nov 2026. pdfjs joins one Arabic line into ONE text item whose string is already in logical order
// (first-written figure first) and whose x is the item's left edge, dir 'rtl'. The reader placed figures by
// character index and then read the Arabic line right to left, so it returned the SECOND figure first.
// Replays the nightly of 20 Oct - 3 Nov: the note "the line amounts add up to 118,520.00; the quoted total is
// 118,500.00" read [118,520.00 118,500.00] in English and [118,500.00 118,520.00] in Arabic.
import { amountsInReadingOrder } from './pdf_facts.mjs';
test('an rtl item pdfjs already put in logical order is read first-written figure first', () => {
  const ar = [{ text: 'ﻣﺠﻤﻮﻉ 118,520.00 ﺩﺭﻫﻢ ﺑﻴﻨﻤﺎ 118,500.00 ﺩﺭﻫﻢ', page: 1, x: 160, y: -148, w: 390, dir: 'rtl' }];
  assert.deepEqual(amountsInReadingOrder(ar, true), ['118,520.00', '118,500.00']);
});
test('a swapped sum and total still fail (nothing is sorted by value)', () => {
  const ar = [{ text: 'ﻣﺠﻤﻮﻉ 118,500.00 ﺩﺭﻫﻢ ﺑﻴﻨﻤﺎ 118,520.00 ﺩﺭﻫﻢ', page: 1, x: 160, y: -148, w: 390, dir: 'rtl' }];
  assert.notDeepEqual(amountsInReadingOrder(ar, true), ['118,520.00', '118,500.00']);
});
test('separate runs on one Arabic line are still read right to left, and English left to right', () => {
  const right = { text: '118,520.00', page: 1, x: 400, y: -10, w: 40, dir: 'ltr' }, left = { text: '118,500.00', page: 1, x: 100, y: -10, w: 40, dir: 'ltr' };
  assert.deepEqual(amountsInReadingOrder([left, right], true), ['118,520.00', '118,500.00']);
  assert.deepEqual(amountsInReadingOrder([right, left], false), ['118,500.00', '118,520.00']);
});
