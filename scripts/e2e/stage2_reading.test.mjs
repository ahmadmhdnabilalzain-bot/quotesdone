// S21's two harness defects from run 0a717394 (19 Oct 2026), held offline. Assigned: it_engineer.
//   - it asserted a supplier's row while the profile was still 'reading' (7 of 11 shapes read proposed_trades [] and
//     one gate 'pending (documents_being_read)'), and it counted 'reading' as read;
//   - the async re-gate wrote the licence name back over the released one, so the next shape of the same company
//     crashed with 23505 leads_claimed_company_name_uidx.
//   node --test scripts/e2e/stage2_reading.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { docIsRead, readingSettled } from './stage2_reading.mjs';

const SRC = readFileSync(new URL('./stage2.mjs', import.meta.url), 'utf8');
const doc = (status) => ({ path: 'p', status });

test("a document still 'reading' is not read; a finished one is", () => {
  for (const s of ['reading', 'retry', 'queued', 'error', 'unread', 'failed', 'refused', undefined]) assert.equal(docIsRead(doc(s)), false, s);
  assert.equal(docIsRead(doc('read')), true);
});

test('the row of run 0a717394 (Dune Plumbing) is NOT settled; the same row after the read is', () => {
  // As measured on 19 Oct: gate reason documents_being_read, both documents 'reading'.
  const dune = { approval_status: 'pending', licence_gate_reason: 'documents_being_read', source_docs: { docs: [doc('reading'), doc('reading')] } };
  assert.equal(readingSettled(dune), false);
  // A shape that approved at once but whose profile is still being read (Falcon Aluminium): not settled either.
  assert.equal(readingSettled({ approval_status: 'approved', licence_gate_reason: null, source_docs: { docs: [doc('read'), doc('reading')] } }), false);
  assert.equal(readingSettled({ approval_status: 'approved', licence_gate_reason: null, source_docs: { docs: [doc('read'), doc('read')] } }), true);
  // Auto-approve off: complete and waiting, everything read, is settled.
  assert.equal(readingSettled({ approval_status: 'pending', licence_gate_reason: null, source_docs: { docs: [doc('read')] } }), true);
  // A held licence (blank page) with nothing left to read is settled.
  assert.equal(readingSettled({ approval_status: 'pending', licence_gate_reason: 'licence_unreadable', source_docs: { docs: [doc('unread')] } }), true);
});

test('S21 waits for the reading to settle, not for the first gate', () => {
  assert.match(SRC, /readingSettled\(x\)/);
  assert.doesNotMatch(SRC, /x\.approval_status !== 'pending' \|\| x\.licence_gate_reason\) \? x : null; \}, \{ timeoutMs: 45000 \}/);
});

test("S21's attachment check uses docIsRead, so 'reading' fails it", () => {
  assert.match(SRC, /x\.path === p && docIsRead\(x\)/);
  assert.doesNotMatch(SRC, /x\.status && !\/error\|unread\|failed\/i\.test\(x\.status\)/);
});

test('S21 gives back a name this run still holds before registering the next shape', () => {
  const i = SRC.indexOf('S21 release a name this run still holds'), j = SRC.indexOf("makeSupplier(run, { trade: 'aluminium', email, company_name: d.registered_name");
  assert.ok(i > 0 && j > i, 'the release runs before makeSupplier');
  const stmt = SRC.slice(SRC.lastIndexOf('await write(', i), i);
  for (const scope of ["claimed_by like '%@example.invalid'", "company_name like 'ZZ DEMO%'", 'run.ids.leads', 'fn_company_registration_name_key']) assert.ok(stmt.includes(scope), 'scoped by ' + scope);
});
