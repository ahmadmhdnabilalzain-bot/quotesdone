// Runnable checks for the only non-trivial logic in the Orders module: the two figures about
// someone's money that this surface is allowed to compute. (The approval-chain checks left with the
// Approvals tab on 14 Sep 2026 — see ./index.ts.) Node 24 strips the types, so this runs with no
// framework and no build:
//
//   node --test src/components/portal/approvals/model.test.mjs
//   npm test        (the repository runner discovers *.test.mjs anywhere in the tree)
import test from 'node:test';
import assert from 'node:assert/strict';
import { orderValue, receivedPct } from './model.ts';

const line = (o) => ({ line_no: 1, description: null, qty: null, unit_price: null, qty_received: null, ...o });
const order = (o) => ({ id: 'o', po_no: null, status: null, order_date: null, expected_date: null, currency: 'AED', subtotal: null, memo: null, inquiry_id: null, quote_id: null, project_id: null, approved_at: null, lines: [], ...o });

/* ── the two money figures ─────────────────────────────────────────────────────────────────── */

test('subtotal is the authority, including a real zero', () => {
  assert.equal(orderValue(order({ subtotal: 12500 })), 12500);
  assert.equal(orderValue(order({ subtotal: 0, lines: [line({ qty: 2, unit_price: 50 })] })), 0);
});

test('lines are summed only when subtotal is absent AND every line is priced', () => {
  assert.equal(orderValue(order({ lines: [line({ qty: 2, unit_price: 50 }), line({ qty: 1, unit_price: 25 })] })), 125);
  // A partial sum presented as a total is a smaller number than the order. Refuse it.
  assert.equal(orderValue(order({ lines: [line({ qty: 2, unit_price: 50 }), line({ qty: 1 })] })), null);
  assert.equal(orderValue(order({ lines: [] })), null);
  assert.equal(orderValue(order({})), null);
});

test('"nothing was recorded" is not "nothing arrived"', () => {
  // Every line unreceived-but-unrecorded: null, so the surface says so instead of showing 0%.
  assert.equal(receivedPct([line({ qty: 10 }), line({ qty: 5 })]), null);
  assert.equal(receivedPct([]), null);
  assert.equal(receivedPct(null), null);
  // One recorded zero IS a measurement: 0% delivered is now true and must be shown.
  assert.equal(receivedPct([line({ qty: 10, qty_received: 0 })]), 0);
  assert.equal(receivedPct([line({ qty: 10, qty_received: 5 })]), 50);
  assert.equal(receivedPct([line({ qty: 10, qty_received: 5 }), line({ qty: 10, qty_received: 10 })]), 75);
  // Over-receipt is reported, not clamped — a clamped number hides a real discrepancy.
  assert.equal(receivedPct([line({ qty: 10, qty_received: 12 })]), 120);
  // A zero-quantity line cannot be a denominator.
  assert.equal(receivedPct([line({ qty: 0, qty_received: 3 })]), null);
});
