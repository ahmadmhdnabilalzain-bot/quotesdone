// Runnable check for the only non-trivial logic in this module — the derivations that decide what
// colour a customer's procurement package is and how far along the chain a shipment is drawn. If
// these break, a customer is told something untrue about their own money on a 3D block, which is
// the defect class this whole module was written to avoid repeating.
//
//   node --experimental-strip-types src/components/portal/spatial/selfcheck.mjs
//
// No framework, no fixtures. ./model.ts imports nothing, so this runs straight off the repo. It is
// .mjs so tsconfig (which type-checks only src/**/*.ts[x]) never sees a file importing a .ts path.
import assert from 'node:assert/strict';
import {
  buildModel, chainLegs, docsForRfq, levelsFromMeta, receivedFraction, stageOf,
} from './model.ts';

const rfq = (o) => ({
  id: 'r1', category: 'hvac', emirate: 'Dubai', summary: null, status: 'open', pipeline_stage: null,
  budget: null, expected_value: null, hired_supplier_id: null, created_at: '2026-01-01T00:00:00Z', ...o,
});
const order = (o) => ({
  id: 1, po_no: 'PO-1', status: 'draft', order_date: '2026-02-01', expected_date: '2026-03-01',
  currency: 'AED', subtotal: 1000, memo: null, inquiry_id: 'r1', quote_id: null, project_id: 'p1',
  approved_at: null, lines: [], ...o,
});

// ── receivedFraction: unknown must never be reported as zero ──────────────────────────────────
// A bar at 0% says "nothing has arrived". A bar that cannot be computed says nothing at all. An
// order with no line quantities is the second, and conflating them would put a confident 0% next
// to an order that may well be fully delivered.
assert.equal(receivedFraction(order({ lines: [] })), null, 'no lines is unknown, not zero');
assert.equal(receivedFraction(order({ lines: [{ qty: 0, qty_received: 0 }] })), null, 'zero ordered is unknown');
assert.equal(receivedFraction(order({ lines: [{ qty: 10, qty_received: 0 }] })), 0);
assert.equal(receivedFraction(order({ lines: [{ qty: 10, qty_received: 5 }] })), 0.5);
assert.equal(receivedFraction(order({ lines: [{ qty: 4, qty_received: 2 }, { qty: 6, qty_received: 6 }] })), 0.8);
assert.equal(receivedFraction(order({ lines: [{ qty: 10, qty_received: 99 }] })), 1, 'over-receipt clamps to 1');
assert.equal(receivedFraction(order({ lines: [{ qty: 10, qty_received: null }] })), 0, 'a null receipt is zero received');

// ── stageOf: the four states, and nothing between them ────────────────────────────────────────
assert.equal(stageOf(rfq(), [], 0), 'requested', 'sent to suppliers with no answer is REQUESTED, not quotation');
assert.equal(stageOf(rfq(), [], 3), 'quotation');
assert.equal(stageOf(rfq({ hired_supplier_id: 's1' }), [], 3), 'ordered', 'hiring is this product’s order');
assert.equal(stageOf(rfq(), [order({ status: 'approved' })], 0), 'ordered');
assert.equal(stageOf(rfq(), [order({ status: 'received' })], 0), 'delivered');
assert.equal(stageOf(rfq(), [order({ status: 'billed' })], 0), 'delivered');
assert.equal(stageOf(rfq(), [order({ status: 'closed' })], 0), 'delivered');
assert.equal(
  stageOf(rfq(), [order({ status: 'partial', lines: [{ qty: 10, qty_received: 10 }] })], 0), 'delivered',
  'fully received lines beat a stale partial status',
);
assert.equal(stageOf(rfq(), [order({ status: 'partial', lines: [{ qty: 10, qty_received: 4 }] })], 0), 'ordered');
// A cancelled order is not progress. Without this a cancelled PO would leave a package showing
// ORDERED for ever, and the customer would never re-raise it.
assert.equal(stageOf(rfq(), [order({ status: 'cancelled' })], 2), 'quotation');
// Another customer's order, or another RFQ's, must not colour this block.
assert.equal(stageOf(rfq(), [order({ inquiry_id: 'other', status: 'received' })], 0), 'requested');

// ── chainLegs: position comes from the order, never from the clock ─────────────────────────────
const legs = chainLegs([
  order({ id: 1, status: 'draft' }),
  order({ id: 2, status: 'approved' }),
  order({ id: 3, status: 'partial', lines: [{ qty: 10, qty_received: 5 }] }),
  order({ id: 4, status: 'received' }),
  order({ id: 5, status: 'cancelled' }),
]);
assert.deepEqual(legs.map((l) => l.stage), ['placed', 'approved', 'in_transit', 'arrived', 'cancelled']);
assert.equal(legs[0].progress, 0);
assert.equal(legs[1].progress, 0.25);
// A position on a track, so it is compared with a tolerance rather than by float equality.
assert.ok(Math.abs(legs[2].progress - 0.65) < 1e-9, 'partial interpolates on real received quantity');
assert.equal(legs[3].progress, 1);
assert.equal(legs[4].progress, 0, 'a cancelled order is marked, never shown as arrived');
assert.equal(legs[2].received, 0.5);
assert.equal(legs[0].received, null, 'no quantities is unknown, and the surface says so');
assert.deepEqual(chainLegs([]), [], 'no orders draws no chain');
// A partial with no quantities must sit BETWEEN approved and arrived rather than claim either.
const noQty = chainLegs([order({ status: 'partial', lines: [] })])[0];
assert.ok(noQty.progress > 0.25 && noQty.progress < 1);

// ── levelsFromMeta: the one documented path for real geometry ──────────────────────────────────
assert.equal(levelsFromMeta(null), null);
assert.equal(levelsFromMeta({}), null);
assert.equal(levelsFromMeta({ levels: [] }), null, 'an empty array is no storey model');
assert.deepEqual(levelsFromMeta({ levels: ['Ground', 'L1'] }), [{ label: 'Ground', rfqs: [] }, { label: 'L1', rfqs: [] }]);
assert.deepEqual(levelsFromMeta({ levels: [{ label: 'L25', rfqs: ['a'] }, { rfqs: ['b'] }] }), [{ label: 'L25', rfqs: ['a'] }],
  'a level with no label is not a level');

// ── buildModel: every block is one real linked RFQ ─────────────────────────────────────────────
const empty = buildModel(null, [], [], []);
assert.equal(empty.packageCount, 0);
assert.deepEqual(empty.levels, [], 'nothing linked must draw nothing — not a placeholder building');

const proj = (meta) => ({
  id: 'p1', name: 'Tower', description: null, status: 'active', target_open_date: null,
  budget_total: null, meta: meta || null, created_at: '2026-01-01T00:00:00Z',
});

const trades = buildModel(proj(null), [
  rfq({ id: 'a', category: 'HVAC' }),
  rfq({ id: 'b', category: 'lighting' }),
  rfq({ id: 'c', category: 'HVAC' }),
  rfq({ id: 'd', category: null }),
], [], []);
assert.equal(trades.source, 'trade_packages', 'no storey model means trade bands, and the UI says so');
assert.equal(trades.packageCount, 4, 'one block per linked RFQ, none invented and none dropped');
assert.deepEqual(trades.levels.map((l) => l.label), ['HVAC', 'Lighting', 'Unspecified']);
assert.deepEqual(trades.levels.map((l) => l.packages.length), [2, 1, 1]);
// Deterministic: the same project must not draw two different buildings on two loads.
assert.deepEqual(
  buildModel(proj(null), [rfq({ id: 'b', category: 'lighting' }), rfq({ id: 'a', category: 'HVAC' })], [], []).levels.map((l) => l.label),
  ['HVAC', 'Lighting'],
);

const storeys = buildModel(proj({ levels: [{ label: 'L1', rfqs: ['a'] }, 'L2'] }), [
  rfq({ id: 'a' }), rfq({ id: 'z' }),
], [], []);
assert.equal(storeys.source, 'project_meta_levels');
assert.deepEqual(storeys.levels.map((l) => l.label), ['L1', 'L2', 'Unassigned']);
assert.deepEqual(storeys.levels.map((l) => l.packages.length), [1, 0, 1],
  'an RFQ no level claims goes to a named band — never silently dropped, never silently spread');

// Stage and quote counts must survive the join by inquiry id.
const joined = buildModel(proj(null), [rfq({ id: 'a' }), rfq({ id: 'b' })],
  [order({ inquiry_id: 'a', status: 'received' })], [{ id: 'b', quotes: [{ id: 'q1' }] }]);
const flat = joined.levels.flatMap((l) => l.packages);
assert.equal(flat.find((p) => p.rfqId === 'a').stage, 'delivered');
assert.equal(flat.find((p) => p.rfqId === 'b').stage, 'quotation');
assert.equal(flat.find((p) => p.rfqId === 'a').orders.length, 1);
assert.equal(flat.find((p) => p.rfqId === 'b').orders.length, 0);
// value falls back budget-wards but never fabricates a zero.
assert.equal(buildModel(proj(null), [rfq({ expected_value: null, budget: 500 })], [], []).levels[0].packages[0].value, 500);
assert.equal(buildModel(proj(null), [rfq({})], [], []).levels[0].packages[0].value, null);

// ── docsForRfq: ownership is (ref_table, ref_id), and a quote document is not an inquiry document ─
const docs = [
  { id: 1, ref_table: 'inquiries', ref_id: 'a' },
  { id: 2, ref_table: 'quotes', ref_id: 'a' },
  { id: 3, ref_table: 'inquiries', ref_id: 'b' },
];
assert.deepEqual(docsForRfq(docs, 'a').map((d) => d.id), [1]);
assert.deepEqual(docsForRfq(docs, 'zzz'), []);

console.log('spatial selfcheck OK');
