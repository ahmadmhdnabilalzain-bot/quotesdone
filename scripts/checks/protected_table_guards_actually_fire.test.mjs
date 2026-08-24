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

test('a00_phase_c_refund_decision_immutable refuses UPDATE and DELETE and permits a supersession',
  { skip: SKIP }, async () => {
  const out = await drive(`
do $p$
declare v_sub uuid; v_req bigint; v_d1 bigint; v_res jsonb; v_before jsonb;
        v_row public.phase_c_refund_decision%rowtype; v_u text; v_d text; v_s text; v_same text;
begin
  select f.auth_user_id into v_sub from public.phase_c_founder_identity f
   where f.active and f.kind='email' and f.auth_user_id is not null order by f.identity limit 1;
  perform public.fn_phase_c_founder_subject_bind(v_sub);
  insert into public.founder_approval_request(action_class, subject_ref, prepared_by_role_id)
  values ('refund_decision','guard-probe','payments_and_billing_manager') returning request_id into v_req;
  v_res := public.fn_kernel_refund_decision_record(jsonb_build_object(
    'op','record','request_id',v_req,'decision','approved','reason','guard probe, aborted'));
  v_d1 := (v_res->>'decision_id')::bigint;
  select * into v_row from public.phase_c_refund_decision where decision_id = v_d1;
  v_before := to_jsonb(v_row);

  perform set_config('kernel.maintenance_reason','guard probe: reach the append-only trigger', true);
  begin
    update public.phase_c_refund_decision set decision='rejected' where decision_id=v_d1;
    v_u := 'ACCEPTED';
  exception when others then v_u := 'REFUSED:' || SQLSTATE; end;
  perform set_config('kernel.maintenance_reason','guard probe: reach the append-only trigger', true);
  begin
    delete from public.phase_c_refund_decision where decision_id=v_d1;
    v_d := 'ACCEPTED';
  exception when others then v_d := 'REFUSED:' || SQLSTATE; end;
  perform set_config('kernel.maintenance_reason','', true);

  select * into v_row from public.phase_c_refund_decision where decision_id = v_d1;
  v_same := case when to_jsonb(v_row) = v_before then 'UNCHANGED' else 'CHANGED' end;
  begin
    perform public.fn_kernel_refund_decision_record(jsonb_build_object(
      'op','record','request_id',v_req,'decision','rejected','reason','superseding',
      'supersedes_decision_id', v_d1, 'supersession_reason','guard probe supersession'));
    v_s := 'ACCEPTED';
  exception when others then v_s := 'REFUSED:' || SQLSTATE; end;

  raise exception '%', 'GUARDPROBE' || v_u || '|' || v_d || '|' || v_same || '|' || v_s;
end $p$;`);
  assert.ok(out, 'the probe did not abort — nothing may be concluded from a run that committed');
  const [u, d, same, s] = out.split('|');
  assert.equal(u, 'REFUSED:23514', 'UPDATE of a founder refund decision was not refused');
  assert.equal(d, 'REFUSED:23514', 'DELETE of a founder refund decision was not refused');
  assert.equal(same, 'UNCHANGED', 'the original decision row moved');
  assert.equal(s, 'ACCEPTED',
    'the sanctioned supersession was refused too — the ledger would then be unamendable, not append-only');
});

test('nothing this check drove survives it', { skip: SKIP }, async () => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: `select
      (select count(*) from public.phase_c_refund_decision) as decisions,
      (select count(*) from public.founder_approval_request) as requests,
      (select count(*) from public.phase_c_founder_auth_event) as auth_events;` }),
  });
  const [row] = JSON.parse(await r.text());
  assert.equal(Number(row.decisions), 0, 'a refund decision survived an aborted probe');
  assert.equal(Number(row.requests), 0, 'a founder approval request survived an aborted probe');
  assert.equal(Number(row.auth_events), 0, 'a founder auth event survived an aborted probe');
});
