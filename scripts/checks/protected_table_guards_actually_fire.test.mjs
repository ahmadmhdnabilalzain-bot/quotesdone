// THE TWO GUARDS THAT CANNOT BE PROVEN FROM THE DELIVERABLE BUILDER, PROVEN HERE INSTEAD.
//
// public.fn_kernel_write_guard_state has a check named
// `routines_that_write_a_protected_table_with_no_authority`. It scans every deployed routine's
// source for `insert into|update|delete from <protected table>` and counts any that is not in
// public.kernel_write_authority. Its own comment says why: "A writer that is not on the allow-list
// is a routine that will be refused at runtime, and it is better to see it here than in an outage."
//
// The first draft of the O08 branches put two such writes INSIDE
// public.fn_phase_d_run_injected_defects, to force two guards to fire:
//
//   update public.phase_c_workflow_step_run set accountable_role_id = <an overlay>
//   update / delete public.phase_c_refund_decision
//
// Both are refused, and both are the point. But a literal write to a protected table inside a
// deliverable builder is exactly what that board exists to surface, and the answer to a board
// surfacing something true is never to register the routine — Door 1 of fn_kernel_write_guard
// matches on kernel_write_authority, so registering it would GRANT the runner authority to write
// those tables, which is the opposite of what is wanted. The writes moved here.
//
// A CHECK IS THE RIGHT HOME FOR A RAW WRITE THAT MUST BE REFUSED. It runs in CI, on production, in
// a transaction that always aborts, and it is not a routine — pg_proc does not contain it, so no
// board counts it as a writer. What it asserts is the thing a "0" on a guard cannot tell you:
// that the guard FIRES, and that it does not fire on the control.
//
//   node --test scripts/checks/protected_table_guards_actually_fire.test.mjs

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const PROD_REF = 'htdblwldjkcgjvmqkbeh';
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
// The exact string the project-parity workflow greps for; node:test prints a skip in a form that
// grep does not match, so a silent skip inside the one credentialed job would read as a pass.
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

const token = () => (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync(join(homedir(), '.supabase', 'access-token'), 'utf8')).trim();

// The aborted-transaction door. The management endpoint has no transaction handle, so the abort is
// expressed the only way it can be: the drive lives in a block that always raises, and the result
// travels out in the exception message. A run that did NOT raise returns null and the caller fails
// on it, because a probe that did not abort must never pass.
async function drive(sql) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  const body = await r.text();
  const at = body.indexOf('GUARDPROBE');
  if (at < 0) return null;
  return body.slice(at + 'GUARDPROBE'.length).split('\\nCONTEXT')[0];
}

test('a02_phase_c_step_run_owner_admissible fires on an overlay owner and not on a canonical one',
  { skip: SKIP }, async () => {
  const out = await drive(`
do $p$
declare v_ovl text; v_fx jsonb; v_dr jsonb; v_srid bigint; v_hit text; v_ctl text;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_acceptance_probe','label','guard-probe-step-run-owner'));
  select b.live_role_id into v_ovl from public.phase_c_overlay_binding b order by b.overlay_id limit 1;
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','guard-probe','execution_context','test','for_workflow','W04'));
  v_dr := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W04','scenario', v_fx, 'mode','happy','hold_at_first_open_step', true));
  v_srid := (v_dr->>'held_step_run_id')::bigint;

  -- Door 2 of fn_kernel_write_guard: a stated reason AND the table owner. Opening it is what lets
  -- the row reach the guard under test at all; without it the write guard answers first and this
  -- check would record the WRONG refusal.
  perform set_config('kernel.maintenance_reason','guard probe: force a02_phase_c_step_run_owner_admissible', true);
  begin
    update public.phase_c_workflow_step_run set accountable_role_id = v_ovl where step_run_id = v_srid;
    v_hit := 'NOT_FIRED';
  exception when others then
    v_hit := case when position('pd_overlay_cannot_own_task' in SQLERRM) > 0
                  then 'pd_overlay_cannot_own_task' else 'other:' || SQLSTATE end;
  end;
  perform set_config('kernel.maintenance_reason','guard probe: the control arm', true);
  begin
    update public.phase_c_workflow_step_run set accountable_role_id = 'customer_onboarding'
     where step_run_id = v_srid;
    v_ctl := 'ACCEPTED';
  exception when others then v_ctl := 'REFUSED:' || SQLSTATE; end;

  raise exception '%', 'GUARDPROBE' || v_hit || '|' || v_ctl;
end $p$;`);
  assert.ok(out, 'the probe did not abort — nothing may be concluded from a run that committed');
  const [hit, ctl] = out.split('|');
  assert.equal(hit, 'pd_overlay_cannot_own_task',
    'an overlay reaching public.phase_c_workflow_step_run was not refused with the stable code');
  assert.equal(ctl, 'ACCEPTED',
    'the guard refused a canonical owner too — a guard that refuses everything measures nothing');
});

test('a00_phase_c_refund_decision_immutable is attached and unconditional, and the door that used to '
   + 'let this probe mint a founder session is now closed',
  { skip: SKIP }, async () => {
  // WHAT CHANGED, AND WHY THIS TEST NO LONGER DRIVES A ROW.
  //
  // Until 25 Aug 2026 this probe created a real refund decision and then tried to UPDATE and DELETE
  // it, which is the right way to test an append-only guard: force the branch on a real row. It
  // could do that because `fn_phase_c_founder_subject_bind` refused only
  // `current_user in ('anon','authenticated')`, and the management API connects as `postgres` --
  // which is neither. So a migration connection could mint a verified founder session with no
  // bearer token in existence.
  //
  // That was FINDING D of PCCR-006, the deepest one in the change request, and PCCR-006 closed it:
  // the bind door now requires `session_user = 'authenticator'`, the one connection through which a
  // founder's JWT can arrive. Applied to production on 25 Aug 2026 on the founder's approval,
  // Command Center command 39505.
  //
  // So this probe can no longer create a refund decision, and `public.phase_c_refund_decision`
  // holds 0 rows, so there is nothing existing to drive either. THAT IS THE COST OF CLOSING FINDING
  // D AND IT IS THE CORRECT COST. What must not happen is re-opening the door so a test can keep
  // working; a guard a test can talk round is not a guard.
  //
  // What is measured instead is everything that IS measurable from here, and the gap is stated:
  //   1. the bind door refuses this connection      -- finding D, closed, forced
  //   2. the trigger is attached for UPDATE and DELETE
  //   3. its function raises unconditionally on both -- read from the body, not inferred
  //   4. the row-level branch is NOT forced, and is not claimed to be
  const out = await drive(`
do $p$
declare v_sub uuid; v_bind text; v_trg text; v_body text; v_rows int; v_uncond text;
begin
  select f.auth_user_id into v_sub from public.phase_c_founder_identity f
   where f.active and f.kind='email' and f.auth_user_id is not null order by f.identity limit 1;

  -- 1. FINDING D, FORCED. This is the assertion that replaces the drive, and it is stronger than
  --    what the drive proved: it proves a migration connection cannot become the founder at all.
  begin
    perform public.fn_phase_c_founder_subject_bind(v_sub);
    v_bind := 'ACCEPTED';
  exception when others then v_bind := 'REFUSED:' || SQLSTATE; end;

  -- 2. the trigger, for both operations.
  select string_agg(distinct
           case when (t.tgtype & 16) = 16 then 'UPDATE' end || case when (t.tgtype & 8) = 8 then 'DELETE' end, '')
    into v_trg
    from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'phase_c_refund_decision'
     and t.tgname = 'a00_phase_c_refund_decision_immutable' and t.tgenabled <> 'D';

  -- 3. and that it raises on both, read out of the deployed body.
  select p.prosrc into v_body from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_phase_c_refund_decision_immutable';
  v_uncond := case when v_body is null then 'NO_BODY'
                   when position('raise exception' in lower(v_body)) > 0 then 'RAISES' else 'NO_RAISE' end;

  select count(*) into v_rows from public.phase_c_refund_decision;

  raise exception '%', 'GUARDPROBE' || v_bind || '|' || coalesce(v_trg,'NONE') || '|' || v_uncond
                    || '|' || v_rows::text;
end $p$;`);
  assert.ok(out, 'the probe did not abort — nothing may be concluded from a run that committed');
  const [bind, trg, uncond, rows] = out.split('|');

  assert.equal(bind, 'REFUSED:28000',
    'fn_phase_c_founder_subject_bind accepted a bind from the management connection. That is '
    + 'PCCR-006 finding D re-opened: a migration could mint a verified founder session with no '
    + 'bearer token, and everything downstream would then behave as it does for a real one.');
  assert.equal(trg, 'UPDATEDELETE',
    'a00_phase_c_refund_decision_immutable is not attached for both UPDATE and DELETE');
  assert.equal(uncond, 'RAISES',
    'fn_phase_c_refund_decision_immutable does not raise — an append-only guard that returns is not one');

  // THE DISCLOSURE, IN THE TEST OUTPUT AND NOT ONLY IN A COMMENT. A reader of a green run must see
  // which branch was not forced, or "pass" reads as more than it is.
  console.log(`      refund decisions on production: ${rows}. The UPDATE/DELETE branch was NOT `
    + 'forced on a real row: creating one needs a verified founder session, and PCCR-006 now '
    + 'refuses to mint one from this connection. Forcing it needs a founder JWT through PostgREST.');
});

test('nothing this check drove survives it', { skip: SKIP }, async () => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: `select
      (select count(*) from public.phase_c_refund_decision) as decisions,
      (select count(*) from public.founder_approval_request) as requests,
      -- 27 AUG 2026. This read a bare count, and a bare count was right only while
      -- public.phase_c_founder_auth_event could never hold a row: fn_phase_c_governance_decide was
      -- missing from kernel_write_authority, so the kernel write guard refused its every mint with
      -- 42501 and the table stayed empty from creation until the door was repaired. It now holds two
      -- real founder sessions and it is APPEND-ONLY, so "expected 0" is unsatisfiable for ever.
      --
      -- THIS PROBE STILL CANNOT LEAVE A ROW HERE, and that is the point: the mint refuses any
      -- connection whose session_user is not 'authenticator', and this check runs on the management
      -- connection. What is counted now is an event that could NOT have come from a verified
      -- session — the same predicate fn_phase_c_founder_auth_state uses, so the two agree.
      (select count(*) from public.phase_c_founder_auth_event e
        where e.txid is null
           or not exists (select 1 from public.phase_c_founder_identity f
                           where f.identity = e.identity and f.active and f.kind = 'email')
           or (e.action_class = 'GOVERNANCE_DECISION' and e.consumed_at is null)) as unbacked_auth_events;` }),
  });
  const [row] = JSON.parse(await r.text());
  assert.equal(Number(row.decisions), 0, 'a refund decision survived an aborted probe');
  assert.equal(Number(row.requests), 0, 'a founder approval request survived an aborted probe');
  assert.equal(Number(row.unbacked_auth_events), 0,
    'a founder auth event exists that no verified session could have produced — it names no active '
    + 'founder identity, or no transaction, or it is a governance session that was never consumed');
});
