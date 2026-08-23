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
//
// WHAT IT DID NOT ASSERT AND SHOULD HAVE, ADDED 2026-08-20: that nobody ELSE can sign it. The
// independent acceptance cleared all four amendments with `approved_by = 'zz-r5-audit-not-the-
// founder'` in one statement and watched the whole freeze board go green — the table carried seven
// constraints and not one was about who the approver is. E36 added the trigger; the last two tests
// in this file drive it three ways, including the arm that proves it is not refuse-everything.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

// A CHECK THAT CANNOT RUN MUST SAY SO, AND MUST NOT THROW. This file needs the Supabase management
// credential. The tokenless `checks` workflow runs `npm test` with no env block, and reading the
// token file unconditionally made this an ENOENT hard failure there rather than a declared skip.
//
// node:test's own skip, never a top-level process.exit(0) — a file that registers zero tests reads
// as success to a runner, which is how a check goes quiet without anyone noticing.
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
// The exact string .github/workflows/project-parity.yml greps for. node:test prints a skip as
// `﹣ name # SKIPPED: reason`, which that grep does not match, so a file that skipped inside the one
// CI job holding the credential would read as a pass. Printing this makes the skip visible to the
// gate as well as to a human.
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

// qd_guard reads the credential at module load, so importing it eagerly would throw before the
// skip below could take effect. It is loaded on first use instead.
const PROD_REF = 'htdblwldjkcgjvmqkbeh';
const mgmtRead = async (ref, sql) =>
  (await import('../staging/qd_guard.mjs')).mgmtRead(ref, sql);

// The aborted-transaction door. The management endpoint has no transaction handle, so the abort is
// expressed the only way it can be: the drive lives inside a block that always raises, and the
// result travels out in the exception message. Returns the raw body; a run that did NOT raise
// returns null and the caller fails on it, because a probe that did not abort must never pass.
const token = () => (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync(join(homedir(), '.supabase', 'access-token'), 'utf8')).trim();
async function drive(sql) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  return r.text();
}

// Lazy: shelling out at import time throws before the skip below can take effect.
let _tracked;
const tracked = () => (_tracked ??= new Set(
  execFileSync('git', ['ls-files', 'docs/phase-c'], { encoding: 'utf8' })
    .split('\n').map(s => s.trim()).filter(Boolean)));

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

test('every freeze amendment names a change request that exists, is tracked, and lists it', { skip: SKIP }, async () => {
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
    assert.ok(tracked().has(path),
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

test('the drift board refuses to excuse an amendment that names no change request', { skip: SKIP }, async () => {
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

// THE APPROVER COLUMN ANYBODY COULD FILL. This file's header used to say, correctly, that it
// deliberately does not assert approval — approval is the founder's act and no test can perform it.
// What it also did not assert, and should have, is that nobody ELSE can perform it.
//
// The 2026-08-20 independent acceptance cleared all four amendments to frozen Phase C contracts
// with `approved_by = 'zz-r5-audit-not-the-founder'` in one statement and watched the whole freeze
// board go green. `phase_c_freeze_amendment` carried seven constraints and not one was about who
// the approver is. E36 added a10_freeze_amendment_approver_is_the_founder, which requires an ACTIVE
// identity in `public.phase_c_founder_identity`; this drives it rather than trusting the comment.
//
// Three arms, and the third matters as much as the first two: a guard that refuses everything would
// mean the row can never go green even when he does sign.
test('only a registered founder identity can approve an amendment to a frozen contract',
  { skip: SKIP }, async () => {
    // mgmtRead refuses a `do` block — "read is not read-only" — and it is right to: it is the
    // read door. An aborted-transaction probe is a different door, and it is the one
    // phase_d_dispatch_reaches_executed.test.mjs already uses for exactly this shape. The whole
    // drive lives inside a block that always raises, and the result travels out in the message.
    const out = await drive(`
do $probe$
declare v_founder text; v_red_before int; v_red_after int; v_rows int;
        v_free text := 'not-run'; v_inactive text := 'not-run';
begin
  -- 23 Aug 2026: THIS PROBE USED TO DEPEND ON AN UNAPPROVED ROW EXISTING. Once all five
  -- amendments carried a verified founder-session approval, every "where approved_by is null" below
  -- matched nothing, all three arms wrote 0 rows, and the test failed for want of a subject rather
  -- than for a defect. Zero cannot tell a dead guard from an idle system: the probe now CREATES the
  -- condition it tests. The transaction always aborts, so no approval is really cleared.
  update public.phase_c_freeze_amendment
     set approved_by = null, approved_at = null, approval_basis = null,
         approval_route = null, approval_auth_subject = null, approved_amendment_table_digest = null;

  select count(*) into v_red_before from public.fn_phase_c_freeze_drift()
   where not ok and check_name = 'amendments_awaiting_founder_approval';

  begin
    update public.phase_c_freeze_amendment
       set approved_by = 'zz-ci-not-the-founder', approved_at = now(),
           approval_basis = 'AUTHENTICATED_FOUNDER_SESSION',
           approval_route = 'auth.uid()',
           approval_auth_subject = (select fi.auth_user_id from public.phase_c_founder_identity fi
                                     where fi.active and fi.kind = 'email' order by fi.identity limit 1),
           approved_amendment_table_digest = repeat('0', 64) where approved_by is null;
    v_free := 'ACCEPTED';
  exception when others then
    v_free := coalesce((regexp_match(SQLERRM, '[(](pccr_[a-z_]+)[)]'))[1], 'refused:' || SQLSTATE);
  end;

  -- A registered row that is NOT a person. active=false, and its own note says so.
  begin
    update public.phase_c_freeze_amendment
       set approved_by = 'build-mode@quotesdone.local', approved_at = now(),
           approval_basis = 'AUTHENTICATED_FOUNDER_SESSION',
           approval_route = 'auth.uid()',
           approval_auth_subject = (select fi.auth_user_id from public.phase_c_founder_identity fi
                                     where fi.active and fi.kind = 'email' order by fi.identity limit 1),
           approved_amendment_table_digest = repeat('0', 64) where approved_by is null;
    v_inactive := 'ACCEPTED';
  exception when others then
    v_inactive := coalesce((regexp_match(SQLERRM, '[(](pccr_[a-z_]+)[)]'))[1], 'refused:' || SQLSTATE);
  end;

  select fi.identity into v_founder from public.phase_c_founder_identity fi
   where fi.active and fi.kind = 'email' order by fi.identity limit 1;
  update public.phase_c_freeze_amendment set approved_by = v_founder, approved_at = now(), approval_basis = 'AUTHENTICATED_FOUNDER_SESSION',
           approval_route = 'auth.uid()',
           approval_auth_subject = (select fi.auth_user_id from public.phase_c_founder_identity fi
                                     where fi.active and fi.kind = 'email' order by fi.identity limit 1),
           approved_amendment_table_digest = repeat('0', 64)
   where approved_by is null;
  get diagnostics v_rows = ROW_COUNT;
  select count(*) into v_red_after from public.fn_phase_c_freeze_drift()
   where not ok and check_name = 'amendments_awaiting_founder_approval';

  raise exception 'APPROVER_PROBE %', jsonb_build_object(
    'free_text', v_free, 'inactive_identity', v_inactive,
    'founder_identity', v_founder, 'founder_rows', v_rows,
    'red_before', v_red_before, 'red_after', v_red_after,
    'triggers', (select count(*) from pg_trigger
                  where tgrelid = 'public.phase_c_freeze_amendment'::regclass and not tgisinternal));
end $probe$;`);

    assert.ok(out, 'the probe did not raise — it must abort its own transaction');
    // The transport throws the raw response body, so what arrives here is JSON source: quotes are
    // backslash-escaped and Postgres appends a CONTEXT trailer after an escaped newline. Cut there,
    // un-escape the quotes, then parse.
    const m = out.match(/APPROVER_PROBE (\{[\s\S]*?\})/);
    assert.ok(m, `the probe did not reach its report:\n${out.slice(0, 800)}`);
    const r = JSON.parse(m[1].split('\\n')[0].replace(/\\"/g, '"'));

    assert.equal(r.free_text, 'pccr_approver_not_the_founder',
      `a free-text name was ${r.free_text} as an approval of an amendment to a FROZEN Phase C ` +
      'contract. That is how an acceptance auditor turned the whole freeze board green in one ' +
      'statement.');
    assert.equal(r.inactive_identity, 'pccr_approver_not_the_founder',
      `the INACTIVE build_mode identity was ${r.inactive_identity}. It is registered but it is ` +
      'not a person — its own note says so — and it must never stand as a founder approval.');
    assert.ok(Number(r.founder_rows) > 0,
      'the founder\'s own registered identity was not accepted on any row — the guard refuses ' +
      'everything, so this row could never go green even when he signs');
    assert.ok(Number(r.red_before) >= 1 && Number(r.red_after) === 0,
      `the freeze board read ${r.red_before} red before his approval and ${r.red_after} after; it ` +
      'must be red while amendments await him and green once they do not');
    assert.ok(Number(r.triggers) >= 1, 'no user trigger is on phase_c_freeze_amendment');
  });

// Nothing above survives: every branch is inside one transaction that ends in `raise exception`.
// This asserts that, rather than assuming it.
// THE ONE CHANGE REQUEST THE FOUNDER HAS SIGNED, NAMED. Until 21 Aug 2026 this test asserted that
// NO amendment carried an approval, and its own failure message said what to do if one ever did:
// "If the founder has signed, this test should be updated by a person who has read why."
//
// He signed one, in writing, in his ruling of 21 Aug 2026 section E and again in section F:
// "For the founder-authentication amendment, use the approved JWT-subject design above." The
// change request is docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-003.md and it quotes the instruction
// in full.
//
// The assertion is a SET, not a count, so it still catches an aborted probe that committed and it
// still catches a change request being signed that the founder has not seen the tables for.
//
// 23 AUG 2026: PCCR-001 AND PCCR-002 JOIN IT, and the reason the list grows is the reason it exists.
// The founder's brief of 23 Aug 2026 approves amendments 1, 2 and 4 (PCCR-001) and 5 (PCCR-002)
// individually, "based on the exact amendment tables committed in PHASE_D_PCCR_AMENDMENT_TABLES.md"
// — the tables the previous note said had to be seen first. All five were then recorded through
// fn_phase_c_freeze_amendment_approve inside a session where auth.uid() resolved to the founder's
// own subject, and the same call refuses a service_role connection with 403.
//
// This list is the repository's copy of that fact and nothing more. What binds an approval to the
// document it was given against is the sha256 stored on each row, checked against the committed
// file by scripts/checks/pccr_approval_matches_committed_tables.test.mjs — which is the check to
// read if you are asking whether these three were properly signed.
const APPROVED_BY_THE_FOUNDER_IN_WRITING = ['PCCR-001', 'PCCR-002', 'PCCR-003'];

test('only the change request the founder signed in writing carries an approval',
  { skip: SKIP }, async () => {
    const rows = await mgmtRead(PROD_REF,
      'select change_request_ref, count(*) filter (where approved_by is null) as awaiting, ' +
      'count(*) as total from public.phase_c_freeze_amendment group by change_request_ref ' +
      'order by change_request_ref');
    const signed = rows.filter(r => Number(r.awaiting) < Number(r.total))
                       .map(r => r.change_request_ref).sort();
    assert.deepEqual(signed, [...APPROVED_BY_THE_FOUNDER_IN_WRITING].sort(),
      'the set of change requests carrying an approval has changed.' +
      `
  expected: ${APPROVED_BY_THE_FOUNDER_IN_WRITING.join(', ')}` +
      `
  actual:   ${signed.join(', ') || '(none)'}
` +
      'A NEW name here means either the founder signed and this list was not updated by someone who ' +
      'read why, or an aborted probe committed. A name that DISAPPEARED means an approval was ' +
      'cleared.');
    for (const r of rows.filter(r => !APPROVED_BY_THE_FOUNDER_IN_WRITING.includes(r.change_request_ref))) {
      assert.equal(Number(r.awaiting), Number(r.total),
        `${r.change_request_ref}: ${Number(r.total) - Number(r.awaiting)} of ${r.total} amendment(s) ` +
        'carry an approval, and the founder has not signed that change request.');
    }
  });

// THE REGISTER THE GUARD TRUSTS MUST NOT BE WRITABLE BY THE ROLE IT GUARDS AGAINST, AND AN
// APPROVAL MUST STILL RESOLVE.
//
// E36's trigger refused every literal vector. The re-audit then asked the question I had not: who
// can write `public.phase_c_founder_identity`? service_role held INSERT/UPDATE/DELETE, so it could
// add itself as an email identity, approve all four amendments with it, delete the row again, and
// leave the freeze board green with four approvals naming a string that resolves to nobody.
//
// That register also gates fn_refund_founder_decision_only and fn_founder_command_submit, so the
// same hole reached refunds — and the founder's standing rule is that every refund needs him.
//
// E38 closed both halves and this drives both: the grant, and the derivation that must re-redden
// when an approver stops resolving.
test('the founder register is not writable by service_role, and an approval must still resolve',
  { skip: SKIP }, async () => {
    const out = await drive(`
do $probe$
declare v_out jsonb := '{}'::jsonb; v_founder text; v_rows int; v_red int;
begin
  -- 23 Aug 2026: THE PROBE MAKES ITS OWN SUBJECT. See the note on the first probe in this file:
  -- once every amendment carried a verified founder-session approval, "where approved_by is null"
  -- matched nothing and this arm silently wrote 0 rows. The transaction always aborts.
  update public.phase_c_freeze_amendment
     set approved_by = null, approved_at = null, approval_basis = null,
         approval_route = null, approval_auth_subject = null, approved_amendment_table_digest = null;

  select count(*) into v_red from public.fn_phase_c_freeze_drift()
   where not ok and check_name = 'amendments_awaiting_founder_approval';
  v_out := v_out || jsonb_build_object('red_at_open', v_red);

  begin
    set local role service_role;
    insert into public.phase_c_founder_identity(identity, kind, active, note)
      values ('zz-ci-not-the-founder','email',true,'ci probe');
    v_out := v_out || jsonb_build_object('plant', 'ACCEPTED');
  exception when others then
    v_out := v_out || jsonb_build_object('plant', 'REFUSED ' || SQLSTATE);
  end;
  reset role;

  select fi.identity into v_founder from public.phase_c_founder_identity fi
   where fi.active and fi.kind = 'email' order by fi.identity limit 1;
  update public.phase_c_freeze_amendment set approved_by = v_founder, approved_at = now(), approval_basis = 'AUTHENTICATED_FOUNDER_SESSION',
           approval_route = 'auth.uid()',
           approval_auth_subject = (select fi.auth_user_id from public.phase_c_founder_identity fi
                                     where fi.active and fi.kind = 'email' order by fi.identity limit 1),
           approved_amendment_table_digest = repeat('0', 64)
   where approved_by is null;
  get diagnostics v_rows = ROW_COUNT;
  select count(*) into v_red from public.fn_phase_c_freeze_drift()
   where not ok and check_name = 'amendments_awaiting_founder_approval';
  v_out := v_out || jsonb_build_object('approved_rows', v_rows, 'red_after_approval', v_red);

  delete from public.phase_c_founder_identity where identity = v_founder;
  select count(*) into v_red from public.fn_phase_c_freeze_drift()
   where not ok and check_name = 'amendments_awaiting_founder_approval';
  v_out := v_out || jsonb_build_object('red_after_approver_deleted', v_red);

  raise exception 'REGISTER_PROBE %', v_out;
end $probe$;`);

    const m = out.match(/REGISTER_PROBE (\{[\s\S]*?\})/);
    assert.ok(m, `the probe did not reach its report:\n${out.slice(0, 800)}`);
    const r = JSON.parse(m[1].split('\n')[0].replace(/\\"/g, '"'));

    assert.match(String(r.plant), /^REFUSED/,
      `service_role ${r.plant} an INSERT into public.phase_c_founder_identity. A register its own ` +
      'subject can write is not a register: an acceptance auditor added itself, approved four ' +
      'amendments to frozen Phase C contracts, and deleted the row again. That register also gates ' +
      'refunds.');
    assert.ok(Number(r.approved_rows) > 0 && Number(r.red_after_approval) === 0,
      `a real founder identity approved ${r.approved_rows} row(s) and the board read ` +
      `${r.red_after_approval} red — it must go green when he actually signs`);
    assert.ok(Number(r.red_after_approver_deleted) >= 1,
      'deleting the approver from the register left the board GREEN. The check is reading a stored ' +
      'string instead of resolving it, which is the half of this defect that survives a trigger ' +
      'being disabled.');
  });

// THE THIRD ATTACK, AND THE ONE THAT MATTERED MOST: no fake identity, no DDL, no owner rights.
// `service_role` simply typed the founder's registered email — which is also a plaintext literal in
// E36's committed header — and all four amendments were approved, permanently and undetectably,
// because the approval genuinely resolves. E36 and E38 authenticated the STRING, never the ACTOR.
//
// E39 revoked service_role's write access to the table. Measured first: no routine in the estate
// writes it; every row was written by a migration applied as the owner.
//
// What this does NOT establish is that the person at the keyboard was the founder.
// `fn_phase_c_require_founder` takes a caller-supplied string and also gates `fn_refund_decide` —
// that binding is an open item for the founder and is recorded, not papered over.
test('service_role cannot approve, mint or delete an amendment to a frozen contract',
  { skip: SKIP }, async () => {
    const out = await drive(`
do $probe$
declare v_out jsonb := '{}'::jsonb; v_red int;
begin
  -- 23 Aug 2026: THE PROBE MAKES ITS OWN SUBJECT. See the note on the first probe in this file:
  -- once every amendment carried a verified founder-session approval, "where approved_by is null"
  -- matched nothing and this arm silently wrote 0 rows. The transaction always aborts.
  update public.phase_c_freeze_amendment
     set approved_by = null, approved_at = null, approval_basis = null,
         approval_route = null, approval_auth_subject = null, approved_amendment_table_digest = null;

  begin
    set local role service_role;
    update public.phase_c_freeze_amendment
       set approval_basis = 'AUTHENTICATED_FOUNDER_SESSION',
           approval_route = 'auth.uid()',
           approval_auth_subject = (select fi.auth_user_id from public.phase_c_founder_identity fi
                                     where fi.active and fi.kind = 'email' order by fi.identity limit 1),
           approved_amendment_table_digest = repeat('0', 64), approved_by = (select fi.identity from public.phase_c_founder_identity fi
                           where fi.active and fi.kind='email' order by fi.identity limit 1),
           approved_at = now()
     where approved_by is null;
    v_out := v_out || jsonb_build_object('approve_as_founder','ACCEPTED');
  exception when others then
    v_out := v_out || jsonb_build_object('approve_as_founder','REFUSED ' || SQLSTATE);
  end;
  reset role;

  begin
    set local role service_role;
    insert into public.phase_c_freeze_amendment
      (subject, object_identity, prior_digest, new_digest, reason, evidence, change_request_ref,
       approved_by, approved_at)
    values ('zz-ci','zz-ci', repeat('a',64), repeat('b',64), repeat('r',90), repeat('e',50),
            'PCCR-001', 'management@quotesdone.com', now());
    v_out := v_out || jsonb_build_object('insert_preapproved','ACCEPTED');
  exception when others then
    v_out := v_out || jsonb_build_object('insert_preapproved','REFUSED ' || SQLSTATE);
  end;
  reset role;

  begin
    set local role service_role;
    delete from public.phase_c_freeze_amendment;
    v_out := v_out || jsonb_build_object('delete_all','ACCEPTED');
  exception when others then
    v_out := v_out || jsonb_build_object('delete_all','REFUSED ' || SQLSTATE);
  end;
  reset role;

  update public.phase_c_freeze_amendment
     set approval_basis = 'AUTHENTICATED_FOUNDER_SESSION',
           approval_route = 'auth.uid()',
           approval_auth_subject = (select fi.auth_user_id from public.phase_c_founder_identity fi
                                     where fi.active and fi.kind = 'email' order by fi.identity limit 1),
           approved_amendment_table_digest = repeat('0', 64), approved_by = (select fi.identity from public.phase_c_founder_identity fi
                         where fi.active and fi.kind='email' order by fi.identity limit 1),
         approved_at = now()
   where approved_by is null;
  select count(*) into v_red from public.fn_phase_c_freeze_drift()
   where not ok and check_name = 'amendments_awaiting_founder_approval';
  v_out := v_out || jsonb_build_object('owner_approval_red_after', v_red);

  raise exception 'GRANT_PROBE %', v_out;
end $probe$;`);

    const m = out.match(/GRANT_PROBE (\{[\s\S]*?\})/);
    assert.ok(m, `the probe did not reach its report:\n${out.slice(0, 800)}`);
    const r = JSON.parse(m[1].split('\n')[0].replace(/\\"/g, '"'));

    for (const [k, what] of [
      ['approve_as_founder', 'approve four amendments by typing the founder\'s registered email'],
      ['insert_preapproved', 'mint an amendment born already approved'],
      ['delete_all', 'delete every amendment, turning the row green at "0 of 0"'],
    ]) {
      assert.match(String(r[k]), /^REFUSED/,
        `service_role could ${what} — it got ${r[k]}. No routine in this estate writes ` +
        'phase_c_freeze_amendment; every row was written by a migration applied as the owner, so ' +
        'service_role has no business holding INSERT, UPDATE or DELETE on it.');
    }
    assert.equal(Number(r.owner_approval_red_after), 0,
      'an owner-applied approval by a registered founder identity did NOT clear the row — the ' +
      'revoke went too far and approval is now impossible');
  });

// THE SAME DEFECT ONE TABLE OVER. E36 guarded `phase_c_freeze_amendment.approved_by`; the R7
// acceptance found `public.phase_c_change_request` — the FK target that makes a PCCR reference
// resolve — carrying the SAME approved_by/approved_at pair with no trigger at all and full
// service_role write, and signed both rows in the founder's name. It also found service_role could
// INSERT into `public.phase_c_frozen_subject`, whose only guard is a DELETE|UPDATE trigger, taking
// `frozen_subjects_drifted` from 0 of 25 to 1 of 26.
//
// Closing a defect on the table you were looking at is not closing the class. E40 revoked both and
// put one shared guard on both approver columns; this drives all of it, including the arm proving
// the guard is not refuse-everything.
test('neither governance register is writable by service_role, and both approvers must be the founder',
  { skip: SKIP }, async () => {
    const out = await drive(`
do $probe$
declare o jsonb := '{}'::jsonb;
begin
  begin
    set local role service_role;
    update public.phase_c_change_request set approved_by='zz-ci-not-the-founder', approved_at=now();
    o := o || jsonb_build_object('cr_service_role','ACCEPTED');
  exception when others then o := o || jsonb_build_object('cr_service_role','REFUSED ' || SQLSTATE); end;
  reset role;

  begin
    set local role service_role;
    insert into public.phase_c_frozen_subject(subject, object_kind, object_identity, digest)
      values ('zz-ci','routine','zz(x)', repeat('f',64));
    o := o || jsonb_build_object('fs_service_role','ACCEPTED');
  exception when others then o := o || jsonb_build_object('fs_service_role','REFUSED ' || SQLSTATE); end;
  reset role;

  begin
    update public.phase_c_change_request set approved_by='zz-ci-owner-not-the-founder', approved_at=now();
    o := o || jsonb_build_object('cr_owner_junk','ACCEPTED');
  exception when others then
    o := o || jsonb_build_object('cr_owner_junk',
      coalesce((regexp_match(SQLERRM,'[(](pccr_[a-z_]+)[)]'))[1], 'REFUSED ' || SQLSTATE)); end;

  begin
    update public.phase_c_change_request
       set approved_by = (select identity from public.phase_c_founder_identity
                           where active and kind='email' order by identity limit 1),
           approved_at = now();
    o := o || jsonb_build_object('cr_owner_founder','ACCEPTED');
  exception when others then o := o || jsonb_build_object('cr_owner_founder','REFUSED ' || SQLSTATE); end;

  raise exception 'REGISTERS_PROBE %', o;
end $probe$;`);

    const m = out.match(/REGISTERS_PROBE (\{[\s\S]*?\})/);
    assert.ok(m, `the probe did not reach its report:\n${out.slice(0, 800)}`);
    const r = JSON.parse(m[1].split('\n')[0].replace(/\\"/g, '"'));

    assert.match(String(r.cr_service_role), /^REFUSED/,
      `service_role ${r.cr_service_role} an approval on public.phase_c_change_request — the registry ` +
      'that makes a PCCR reference resolve. An acceptance auditor signed both rows in the founder\'s name.');
    assert.match(String(r.fs_service_role), /^REFUSED/,
      `service_role ${r.fs_service_role} an INSERT into public.phase_c_frozen_subject, the register ` +
      'of WHAT IS FROZEN. Its immutability trigger covers DELETE and UPDATE only.');
    assert.equal(r.cr_owner_junk, 'pccr_approver_not_the_founder',
      `an owner-applied junk approver on phase_c_change_request got ${r.cr_owner_junk} — the shared ` +
      'founder approver guard is not attached to that table');
    assert.equal(r.cr_owner_founder, 'ACCEPTED',
      'the founder\'s own registered identity was refused on phase_c_change_request — the guard ' +
      'refuses everything and approval is impossible');
  });
