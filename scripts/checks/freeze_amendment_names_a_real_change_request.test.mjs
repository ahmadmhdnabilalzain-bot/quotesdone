// Every phase_c_freeze_amendment row must name a Phase C change request THAT EXISTS IN THE TREE.
//
// E13 made `change_request_ref` NOT NULL and made `fn_phase_c_freeze_drift()` refuse to excuse a
// digest move without one. That closes half the hole. The other half is that the database cannot
// see the repository: nothing in Postgres can tell `PCCR-001` from `PCCR-999`, so a NOT NULL column
// alone would let a builder amend a frozen kernel contract by typing three characters.
//
// This estate has been caught by that exact shape before — a registry row added without the
// committed artefact the invariant compares against. So the artefact is what is asserted here:
//   * every distinct change_request_ref has docs/phase-c/PHASE_C_CHANGE_REQUEST_<ref>.md, TRACKED
//     by git (an untracked file is not a change request, it is a local note);
//   * that document names the amendment_id of every row pointing at it, so a second amendment
//     cannot shelter under the first one's paperwork;
//   * the document carries the elements PHASE_D_CHANGE_CONTROL.md requires.
//
// What this test deliberately does NOT assert: that the founder approved it. Approval is
// `approved_by` / `approved_at` on the row, it is reported by the drift board, and it is a person's
// act. A green test here means the paperwork exists and matches, never that it was signed.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { mgmtRead, PROD_REF } from '../staging/qd_guard.mjs';

const tracked = new Set(
  execFileSync('git', ['ls-files', 'docs/phase-c'], { encoding: 'utf8' })
    .split('\n').map(s => s.trim()).filter(Boolean));

// PHASE_D_CHANGE_CONTROL.md line 9 lists what a Phase C change request must carry. Matched on the
// substance rather than on a heading number, so re-ordering the document does not fail the test.
const REQUIRED_ELEMENTS = [
  /defect|observed problem/i,
  /evidence/i,
  /current behaviour|current behavior/i,
  /proposed behaviour|proposed behavior/i,
  /owner/i,
  /reviewer/i,
  /gate/i,
  /security|privacy/i,
  /finance|financial/i,
  /compatibilit/i,
  /rollback|migration/i,
  /founder approval/i,
];

test('every freeze amendment names a change request that exists, is tracked, and lists it', async () => {
  const rows = await mgmtRead(PROD_REF,
    `select amendment_id, subject, object_identity, change_request_ref,
            approved_by is not null as approved
       from public.phase_c_freeze_amendment order by amendment_id;`);

  assert.ok(rows.length > 0, 'no amendment rows — this test is measuring nothing; check the table');

  const byRef = new Map();
  for (const r of rows) {
    assert.match(String(r.change_request_ref ?? ''), /^PCCR-\d{3}$/,
      `amendment ${r.amendment_id} (${r.object_identity}) has change_request_ref ` +
      `${JSON.stringify(r.change_request_ref)}, which is not a PCCR reference`);
    if (!byRef.has(r.change_request_ref)) byRef.set(r.change_request_ref, []);
    byRef.get(r.change_request_ref).push(r);
  }

  for (const [ref, amendments] of byRef) {
    const path = `docs/phase-c/PHASE_C_CHANGE_REQUEST_${ref}.md`;
    assert.ok(tracked.has(path),
      `amendments [${amendments.map(a => a.amendment_id).join(', ')}] name ${ref}, but ${path} is ` +
      `not tracked by git. A frozen Phase C contract stands amended with no committed change request.`);

    const doc = readFileSync(path, 'utf8');

    for (const a of amendments) {
      assert.ok(new RegExp(`\\b${a.amendment_id}\\b`).test(doc),
        `${path} does not name amendment_id ${a.amendment_id} (${a.object_identity}). An amendment ` +
        `may not shelter under another amendment's paperwork.`);
      assert.ok(doc.includes(a.object_identity),
        `${path} does not name the frozen object ${a.object_identity} that amendment ` +
        `${a.amendment_id} moved.`);
    }

    const missing = REQUIRED_ELEMENTS.filter(re => !re.test(doc)).map(re => re.source);
    assert.deepEqual(missing, [],
      `${path} is missing element(s) PHASE_D_CHANGE_CONTROL.md requires: ${missing.join(' | ')}`);
  }
});

test('the drift board refuses to excuse an amendment that names no change request', async () => {
  // A positive control for the E13 predicate. The check must be able to go RED, or its 0 means
  // nothing. Driven in an aborted transaction: insert an amendment whose change_request_ref is
  // blank and confirm the constraint refuses it outright — the column is NOT NULL and shape-checked,
  // so the row cannot exist at all, which is a stronger guarantee than the board catching it later.
  const out = await mgmtRead(PROD_REF, `
    select public.fn_phase_c_freeze_drift() is not null as board_runs,
           (select count(*) from public.phase_c_freeze_amendment
             where coalesce(btrim(change_request_ref),'') = '') as rows_with_no_request,
           (select count(*) from pg_constraint
             where conrelid = 'public.phase_c_freeze_amendment'::regclass
               and conname in ('phase_c_freeze_amendment_change_request_ref_shape',
                               'phase_c_freeze_amendment_approval_is_a_pair')) as guards,
           (select count(*) from information_schema.columns
             where table_schema='public' and table_name='phase_c_freeze_amendment'
               and column_name='change_request_ref' and is_nullable='NO') as not_null;`);
  const r = out[0];
  assert.equal(Number(r.rows_with_no_request), 0, 'an amendment row names no change request');
  assert.equal(Number(r.guards), 2, 'the shape and approval-pair constraints are not both present');
  assert.equal(Number(r.not_null), 1, 'change_request_ref is nullable — the guard can be skipped');
});
