// refund_ladder_probe.test.mjs — each refund rung passes on the production path and fails on the broken one.
// Seat: customer_support. The two walks are the ones measured on 2 Nov 2026 against the founderdemo reveal
// (refund_ladder_probe.mjs, rolled back): "shut" is the path a demo row takes (no handoff filed), "open" the
// production path. founderdemo's supplier HAD responded, so the CEO rightly declined: the ceo rung fails there.
// Run: node --test scripts/e2e/refund_ladder_probe.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ladderSteps, refundLadderProbeSql } from './refund_ladder_probe.mjs';

const C = 'qd-founderdemo-cust1@example.invalid', S = 'qd-founderdemo-sup0@example.invalid';
const told = { cc: [C], to: S, status: 'suppressed' };
const open = {
  customer_locale: 'en', customer_email: C, supplier_email: S,
  confirmation: { to: C, seat: 'customer_support', locale: 'en', status: 'done' },
  case: { from: 'sales_engineer', seat: 'accountant', status: 'pending' },
  checklist_before: { ok: false, failed: ['day3_chase_happened', 'day5_final_call_happened', 'supplier_never_responded'] },
  chase: { told, request: 342637, evidence: { id: 10033, result: 'no_response_confirmation', delivered: true } },
  final_call: { told, request: 342639, evidence: { id: 10034, result: 'no_response_confirmation', delivered: true } },
  ceo: { decision: null, decided_by: null, refund_status: 'rejected' }, ceo_failed: ['supplier_never_responded'],
};
const shut = {
  customer_locale: 'en', customer_email: C, supplier_email: S, confirmation: null, case: null,
  checklist_before: open.checklist_before, chase: { told: null, request: null, evidence: null },
  final_call: { told: null, request: null, evidence: null }, ceo: { decision: null, decided_by: null, refund_status: 'requested' }, ceo_failed: [],
};
const ok = (w) => Object.fromEntries(Object.entries(ladderSteps(w)).map(([k, v]) => [k, v[0]]));

test('the production path proves the four delivery rungs; the declined CEO rung fails', () => {
  assert.deepEqual(ok(open), { confirmation: true, case: true, chase: true, final_call: true, ceo: false });
});

test('the known-bad control (no handoff filed) fails every rung', () => {
  assert.deepEqual(ok(shut), { confirmation: false, case: false, chase: false, final_call: false, ceo: false });
});

test('an approval by the CEO on a refund that has not moved money passes; one by anyone else, or after money moved, fails', () => {
  const approved = { ...open, ceo: { decision: 'approved', decided_by: 'ceo', refund_status: 'approved' } };
  assert.equal(ok(approved).ceo, true);
  assert.equal(ok({ ...approved, ceo: { ...approved.ceo, decided_by: 'accountant' } }).ceo, false);
  assert.equal(ok({ ...approved, ceo: { ...approved.ceo, refund_status: 'succeeded' } }).ceo, false);
  assert.equal(ok({ ...approved, checklist_before: { ok: true, failed: [] } }).ceo, false);   // decided before the ladder ran
});

test('a chase that does not copy the customer, or a final call before the chase, fails', () => {
  assert.equal(ok({ ...open, chase: { ...open.chase, told: { ...told, cc: [] } } }).chase, false);
  assert.equal(ok({ ...open, final_call: { ...open.final_call, evidence: { ...open.final_call.evidence, id: 10000 } } }).final_call, false);
});

test('the probe always rolls back and walks shut before open', () => {
  const sql = refundLadderProbeSql('00000000-0000-0000-0000-000000000000');
  assert.match(sql, /array\[false, true\]/);
  assert.match(sql, /raise exception 'CHK<<%>>'/);
  assert.match(sql, /set_config\('qd\.probe_files_demo_handoff', case when f then 'on' else 'off' end, true\)/);
});
