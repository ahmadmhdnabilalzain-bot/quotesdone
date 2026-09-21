// Runnable check for the project-room cost (customer audit 21 Sep 2026, finding 19).
//
//   node --test src/components/portal/spatial/model.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { buildModel } from './model.ts';

const rfq = (o) => ({ id: 'r1', category: 'gypsum', emirate: 'Abu Dhabi', summary: null, status: 'quoted', pipeline_stage: null, budget: null, expected_value: null, hired_supplier_id: null, created_at: '2026-09-18T00:00:00Z', ...o });

test('a revealed quote is the package cost when expected_value is unset', () => {
  const m = buildModel(null, [rfq({})], [], [{ id: 'r1', quotes: [{ id: 'q1', price: 25920, revealed: true, supplier_name: 'ZZ DEMO Interiors' }] }]);
  assert.equal(m.levels[0].packages[0].value, 25920);
});

test('an unrevealed quote is not a cost; budget still is', () => {
  assert.equal(buildModel(null, [rfq({})], [], [{ id: 'r1', quotes: [{ id: 'q1', price: 25920, revealed: false }] }]).levels[0].packages[0].value, null);
  assert.equal(buildModel(null, [rfq({ budget: 900 })], [], []).levels[0].packages[0].value, 900);
});
