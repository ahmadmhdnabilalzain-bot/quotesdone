// Runnable check for the only non-trivial logic in this module — the derivations the workspace
// shows as headline numbers. If any of these break, a customer is told something untrue about
// their own project, which is the exact defect class this module exists to stop repeating.
//
//   node --experimental-strip-types src/components/portal/projects/selfcheck.mjs
//
// No framework, no fixtures. ./model.ts imports nothing, so this runs straight off the repo.
// It is .mjs so tsconfig (which includes only src/**/*.ts[x]) never type-checks a file that has to
// import a .ts path at runtime.
import assert from 'node:assert/strict';
import { deriveStats, elapsedPct, isOpenRfq } from './model.ts';

const rfq = (o) => ({
  id: 'x', category: null, emirate: null, summary: null, status: 'open', pipeline_stage: null,
  budget: null, expected_value: null, hired_supplier_id: null, created_at: '2026-01-01T00:00:00Z', ...o,
});

// "Open" must mean exactly what project_summary.rfq_open means, or a project card and the project
// it opens show two different active counts for the same project.
assert.equal(isOpenRfq(rfq({ status: 'open' })), true);
assert.equal(isOpenRfq(rfq({ status: 'quoted' })), true);
assert.equal(isOpenRfq(rfq({ status: null })), true, 'the view counts a null status as open');
assert.equal(isOpenRfq(rfq({ status: 'completed' })), false);
assert.equal(isOpenRfq(rfq({ status: 'cancelled' })), false);
// 'closed'/'won'/'lost' close an inquiry elsewhere in the product but NOT in this view's filter.
assert.equal(isOpenRfq(rfq({ status: 'closed' })), true, 'must match the view, not another module');

// Zero RFQs must produce zeros the UI can recognise as "nothing to count" — never a figure it
// would render as a confident result.
assert.deepEqual(deriveStats([]), {
  rfqCount: 0, open: 0, awarded: 0, pipeline: 0, categories: [], awardedSupplierCount: 0,
});

const s = deriveStats([
  rfq({ id: 'a', status: 'open', category: 'Steel', expected_value: 1000 }),
  rfq({ id: 'b', status: 'completed', category: 'steel ', expected_value: 500, hired_supplier_id: 's1' }),
  rfq({ id: 'c', status: 'quoted', category: 'HVAC', expected_value: null, hired_supplier_id: 's1' }),
  rfq({ id: 'd', status: 'cancelled', category: null, expected_value: 250 }),
]);
assert.equal(s.rfqCount, 4);
assert.equal(s.open, 2, 'completed and cancelled are the only closed statuses');
assert.equal(s.awarded, 2, 'awarded counts RFQs, not suppliers');
assert.equal(s.awardedSupplierCount, 1, 'the same supplier hired twice is one supplier');
assert.equal(s.pipeline, 1750, 'a null expected_value contributes 0, it does not void the sum');
assert.deepEqual(s.categories, ['HVAC', 'Steel', 'steel'], 'categories are trimmed and de-duped verbatim');

// Timeline: no target date means there is nothing to show, not 0%.
assert.equal(elapsedPct('2026-01-01T00:00:00Z', null), null);
assert.equal(elapsedPct('2026-01-01T00:00:00Z', ''), null);
assert.equal(elapsedPct('2026-01-01T00:00:00Z', '2025-06-01'), null, 'a target before creation is not a window');
assert.equal(elapsedPct('2026-01-01T00:00:00Z', 'not-a-date'), null);
assert.equal(elapsedPct('2026-01-01T00:00:00Z', '2026-01-11', Date.parse('2026-01-06T00:00:00Z')), 50);
assert.equal(elapsedPct('2026-01-01T00:00:00Z', '2026-01-11', Date.parse('2025-12-01T00:00:00Z')), 0, 'clamped low');
assert.equal(elapsedPct('2026-01-01T00:00:00Z', '2026-01-11', Date.parse('2027-01-01T00:00:00Z')), 100, 'clamped high');

console.log('projects selfcheck: ok');
