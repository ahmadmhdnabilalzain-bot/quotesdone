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
