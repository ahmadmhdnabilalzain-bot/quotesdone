// The document walk must follow founder ledger 1469 (2 Nov 2026): terms + Save hold a clean registration at pending / services_unconfirmed and
// only the supplier's own capability_confirm approves it, as scripts/e2e/supplier_document_read_walk.mjs does (#1772). Prevented: a walk that
// waits for 'approved' straight after Save and reports a held supplier as a failure, or that confirms nothing.
// Source only: runs offline.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const afterSave = (s) => s.slice(s.indexOf("{ name: /^Save changes$/ }"));
// the walk is in order when the held state is asserted before the confirm and the approval after it
const inOrder = (s) => { const t = afterSave(s); const a = t.indexOf('services_unconfirmed'), b = t.indexOf("action: 'capability_confirm'"), c = t.search(/approval_status === 'approved' && !reg\.licence_gate_reason/);
  return a > 0 && b > a && c > b; };

test('known-bad control: the walk as first written (approved straight after Save, no confirm) is caught', () => {
  const old = "await M.getByRole('button', { name: /^Save changes$/ }).click();\n  for (;;) { reg = await rowOf(lead.id); if (reg.approval_status === 'approved') break; }\n"
    + "  step(m, 'approved, no licence hold', reg.approval_status === 'approved' && !reg.licence_gate_reason);";
  assert.equal(inOrder(old), false);
});

test('the document walk is held after Save, confirms its services, and is approved after the confirm', () => {
  assert.ok(inOrder(read('scripts/e2e/supplier_document_walk.mjs')));
});
