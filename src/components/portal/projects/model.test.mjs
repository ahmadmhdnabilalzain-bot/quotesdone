// Runnable checks for the project money figure (customer audit 21 Sep 2026, finding 19: a project
// with a revealed AED 25,920 quote showed pipeline AED 0 and "no cost recorded").
//
//   node --test src/components/portal/projects/model.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { deriveStats, rfqValue } from './model.ts';

const rfq = (o) => ({ id: 'r', category: 'gypsum', emirate: null, summary: null, status: 'quoted', pipeline_stage: null, budget: null, expected_value: null, hired_supplier_id: null, created_at: '2026-09-18T00:00:00Z', ...o });

test('rfqValue: expected_value wins, else the revealed quote, else null', () => {
  assert.equal(rfqValue(rfq({ expected_value: 1000, revealed_value: 25920 })), 1000);
  assert.equal(rfqValue(rfq({ revealed_value: 25920 })), 25920);
  assert.equal(rfqValue(rfq({})), null);
  assert.equal(rfqValue(rfq({ expected_value: 0, revealed_value: 0 })), null);
});

test('pipeline counts the revealed quote when nothing set expected_value', () => {
  const s = deriveStats([rfq({ id: 'a', revealed_value: 25920 }), rfq({ id: 'b', expected_value: 500 }), rfq({ id: 'c' })]);
  assert.equal(s.pipeline, 26420);
  assert.equal(s.rfqCount, 3);
});
