// Runnable checks for the only non-trivial logic in the Approvals/Orders module: the two figures
// about someone's money that this surface is allowed to compute, and the rule that decides whether
// an Approve button appears. Node 24 strips the types, so this runs with no framework and no build:
//
//   node --test src/components/portal/approvals/model.test.mjs
//   npm test        (the repository runner discovers *.test.mjs anywhere in the tree)
import test from 'node:test';
import assert from 'node:assert/strict';
import { canDecide, chainProgress, orderValue, receivedPct } from './model.ts';

const step = (o) => ({ step: 1, key: null, label: 'Step', role: null, status: 'waiting', decided_by: null, decided_at: null, note: null, ...o });
const line = (o) => ({ line_no: 1, description: null, qty: null, unit_price: null, qty_received: null, ...o });
const order = (o) => ({ id: 'o', po_no: null, status: null, order_date: null, expected_date: null, currency: 'AED', subtotal: null, memo: null, inquiry_id: null, quote_id: null, project_id: null, approved_at: null, lines: [], ...o });

/* ── the chain, i.e. the spec's own worked example ─────────────────────────────────────────── */

test("the spec's example projects as written: 2 approved, Finance pending, CEO waiting", () => {
  const steps = [
    step({ step: 1, label: 'Engineer', status: 'approved' }),
    step({ step: 2, label: 'Project Manager', status: 'approved' }),
    step({ step: 3, label: 'Finance', status: 'pending' }),
    step({ step: 4, label: 'CEO', status: 'waiting' }),
  ];
  const p = chainProgress(steps);
  assert.equal(p.total, 4);
  assert.equal(p.approved, 2);
  assert.equal(p.rejected, 0);
  assert.equal(p.pending.label, 'Finance');
});

test('an empty or missing chain is zeros with no pending step, never a crash', () => {
  assert.deepEqual(chainProgress([]), { total: 0, approved: 0, rejected: 0, pending: null });
  assert.deepEqual(chainProgress(null), { total: 0, approved: 0, rejected: 0, pending: null });
});

test('a decide control appears ONLY on the live step of a live request', () => {
  const live = step({ step: 3, status: 'pending' });
  const pending = { status: 'pending', current_step: 3 };
  assert.equal(canDecide(pending, live), true);
  // A finished request must never offer a control the database would refuse.
  assert.equal(canDecide({ status: 'approved', current_step: 3 }, live), false);
  assert.equal(canDecide({ status: 'rejected', current_step: 3 }, live), false);
  // Nor a step that is not the one the chain is on.
  assert.equal(canDecide(pending, step({ step: 4, status: 'waiting' })), false);
  assert.equal(canDecide(pending, step({ step: 1, status: 'approved' })), false);
  // Nor a step whose number drifted from current_step, whatever the view called it.
  assert.equal(canDecide({ status: 'pending', current_step: 2 }, live), false);
});

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
