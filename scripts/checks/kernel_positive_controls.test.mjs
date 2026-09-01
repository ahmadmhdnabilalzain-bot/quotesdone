// GENUINE POSITIVE CONTROLS — one per canonical kernel entry door.
//
//   node scripts/checks/kernel_positive_controls.test.mjs
//
// WHY THIS FILE EXISTS. The Phase C closure reported "positive cases accepted 20/20 (Phase B
// suite, both directions)". The final re-acceptance counted that suite: it is 18 injected defects
// that must be REFUSED and 2 cases where an allowed operation must succeed. A suite of negatives
// described as positive controls is an instrument reporting on the wrong subject — and the number
// 20 appears in no Phase C specification. There is no approved denominator of 20 to meet.
//
// THE DENOMINATOR IS DERIVED, NOT TYPED. A positive control is owed for every CANONICAL KERNEL
// ENTRY DOOR: a routine that holds write authority over a business table, whose name is
// fn_kernel_* or fn_founder_command_*, and which is not recorded in public.kernel_retired_path.
// That set is read from production here and compared to the controls implemented below, so a new
// door cannot be opened without a positive control and a retired one cannot leave a stale case
// behind. Today it is 13.
//
// A guard that only refuses is an outage. Each control proves the door OPENS for the legitimate
// call, and proves it with a measured state effect and a trace, not with an absence of an error.
//
// Every control runs inside a transaction that always ends in `raise exception`, so production
// carries nothing away from this file. The residue assertions at the end measure that.
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'))
  || existsSync('C:/Users/Opera/.supabase/access-token');
if (!hasToken) {
  console.log('SKIP kernel_positive_controls: no Supabase management token here.');
  process.exit(0);
}
const { sql } = await import('../phase_c/lib/db.mjs');

const ORDER = 'Draft one short internal note for the marketing team summarising how QuotesDone '
  + 'shortens supplier sourcing by 3 days. Keep it internal only, finish by 30 August 2026. Do not '
  + 'publish it, do not send it to anyone outside the company, do not spend money, and do not use '
  + 'any paid AI provider. Report progress and the final result through this Command Center thread.';
const VAGUE = 'Make marketing better.';
const FOUNDER = 'management@quotesdone.com';
// PCCR-003, 21 Aug 2026. fn_phase_c_require_founder no longer resolves a caller-supplied email --
// it resolves a VERIFIED auth subject, from auth.uid() or from one os_api verified and bound. These
// probes typed the founder's address and were believed, which is precisely the vector E39 recorded,
// so three doors went red the moment the amendment applied. That red was the guard working.
//
// BIND_FOUNDER does what os_api does: it resolves his auth subject from the register and binds it
// transaction-locally. The bind refuses any subject that is not an enabled founder identity, so this
// cannot authenticate anyone the routine would not, and the whole probe runs in a transaction that
// always aborts. FOUNDER stays in the calls below because p_actor is still checked -- it is now an
// ASSERTION that must MATCH the verified identity, which is a thing worth exercising too.

const lit = s => `'${String(s).replace(/'/g, "''")}'`;
const BIND_FOUNDER = `
  perform public.fn_phase_c_founder_subject_bind(
    (select f.auth_user_id from public.phase_c_founder_identity f
      where f.identity = ${lit(FOUNDER)} and f.active and f.kind = 'email'));`;

// A W20 command in one call gives a run, an active step run, a queued task and a pending event —
// the precondition most of the doors below need.
const SEED = (key) => `
  v := public.fn_founder_command_submit(${lit(FOUNDER)}, ${lit(ORDER)}, ${lit(key)}, '{}'::jsonb);
  cmd := (v->>'command_id')::bigint;
  run := (v->>'workflow_run_id')::bigint;
  sr  := (v->>'step_run_id')::bigint;
  tsk := (v->'task_ids'->>0)::bigint;
  ob  := (v->>'outbox_id')::bigint;
  select step_id, accountable_role_id into stp, owner
    from public.phase_c_workflow_step_run where step_run_id = sr;`;

const OUTPUT = `jsonb_build_object('status','ok','output','positive control output for ' || stp)`;
const INPUTS = `jsonb_build_object('workflow_record','run ' || run, 'prior_outputs','positive control')`;

/** door -> the SQL that exercises it and the facts it must produce. */
const CONTROLS = {
  // 27 AUG 2026. fn_phase_c_governance_decide joined kernel_write_authority when it was registered as
  // the writer of public.phase_c_founder_auth_event — until then it had never operated at all,
  // because the kernel write guard refused its every mint with 42501 and public.
  // phase_c_governance_decision therefore held 0 rows from the day PCCR-006 created it.
  //
  // A door on the canonical list needs a control here, and this one is GATED for exactly the reason
  // the five below are: the routine's first statement refuses any connection whose session_user is
  // not `authenticator`, so no connection this file has can drive it. Measured, not assumed —
  // the same refusal is recorded as case D7 in docs/phase-c/PCCR-006_GOVERNANCE_DOOR_CANARY.md.
  //
  // WHAT DOES DRIVE IT, and it is not a claim that it cannot be driven:
  //   node scripts/phase_d/prove_governance_door.mjs --record
  // mints a real founder session, calls /rest/v1/rpc/fn_phase_c_governance_decide over HTTPS with
  // that bearer, and records 22 of 22 authorization cases in
  // docs/phase-d/PHASE_D_GOVERNANCE_DOOR_CANARY.csv — including the positive case (decision 6,
  // PCCR-007) and the replay returning ALREADY_DECIDED with no second row.
  fn_phase_c_governance_decide: `
    ${BIND_FOUNDER}
    res := public.fn_phase_c_governance_decide(jsonb_build_object(
      'change_request_ref','PCCR-007', 'decision','APPROVED',
      'approved_amendment_digest',
        (select lower((regexp_match(m.raw_text, '[0-9a-fA-F]{64}'))[1])
           from public.founder_command_message m
          where position('pccr-007' in lower(m.raw_text)) > 0 order by m.received_at limit 1),
      'amendment_table_path','docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-007.md',
      'reason','kernel positive control: the governance door recorded a decision in a verified founder session'));`,

  fn_founder_command_submit: `
    ${SEED('positive-control-submit')}
    res := jsonb_build_object(
      'accepted', (v->>'status') = 'tasks_created',
      'effect', jsonb_build_object(
        'runs',  (select count(*) from public.phase_c_workflow_run where command_id = cmd),
        'tasks', (select count(*) from public.phase_c_task where command_id = cmd),
        'events',(select count(*) from public.phase_c_event_outbox where command_id = cmd)),
      'trace', (select count(*) from public.phase_c_trace where command_id = cmd));`,

  fn_founder_command_clarify: `
    ${BIND_FOUNDER}
    v := public.fn_founder_command_submit(${lit(FOUNDER)}, ${lit(VAGUE)}, 'positive-control-clarify', '{}'::jsonb);
    cmd := (v->>'command_id')::bigint;
    v2 := public.fn_founder_command_clarify(cmd,
            'Publish two extra posts this week for the UAE market, by 30 August 2026.', ${lit(FOUNDER)});
    res := jsonb_build_object(
      'accepted', coalesce((v2->>'ok')::boolean, false),
      'effect', jsonb_build_object(
        'state_before', v->>'status',
        'state_after', (select state from public.founder_command where command_id = cmd),
        'tasks', (select count(*) from public.phase_c_task where command_id = cmd)),
      'trace', (select count(*) from public.phase_c_trace where command_id = cmd));`,

  fn_founder_command_control: `
    ${BIND_FOUNDER}
    ${SEED('positive-control-control')}
    v2 := public.fn_founder_command_control(cmd, 'reprioritize', cmd::text, 'P0', ${lit(FOUNDER)});
    res := jsonb_build_object(
      'accepted', coalesce((v2->>'ok')::boolean, false),
      'effect', jsonb_build_object(
        'command_priority', (select priority from public.founder_command where command_id = cmd),
        'tasks_updated', v2->>'tasks_updated'),
      'trace', (select count(*) from public.phase_c_trace where command_id = cmd));`,

  fn_kernel_cancel: `
    ${BIND_FOUNDER}
    ${SEED('positive-control-cancel')}
    v2 := public.fn_kernel_cancel(jsonb_build_object(
      'subject_kind','founder_command', 'subject_ref', cmd::text, 'op','cancel',
      'actor', ${lit(FOUNDER)}, 'reason','positive control: the canonical canceller must accept'));
    res := jsonb_build_object(
      'accepted', coalesce((v2->>'ok')::boolean, false),
      'effect', jsonb_build_object(
        'command', (select state from public.founder_command where command_id = cmd),
        'run', (select state from public.phase_c_workflow_run where run_id = run),
        'task', (select state from public.phase_c_task where task_id = tsk),
        'outbox', (select status from public.phase_c_event_outbox where outbox_id = ob)),
      'trace', (select count(*) from public.phase_c_trace where command_id = cmd and status = 'sealed'));`,

  // ---- THE SIX DOORS THE PHASE D F-SERIES ADDED --------------------------------------------
  // This file's whole argument is that a guard proved only by its refusals is a guard nobody has
  // shown to work. Each of these accepts something, and each control asserts the EFFECT, not the
  // return value.

  fn_phase_c_founder_subject_bind: `
    ${BIND_FOUNDER}
    res := jsonb_build_object(
      'accepted', public.fn_phase_c_require_founder(null) = ${lit(FOUNDER)},
      'effect', jsonb_build_object(
        'auth_events_for_this_txid',
          (select count(*) from public.phase_c_founder_auth_event where txid = txid_current()),
        'identity_resolved', public.fn_phase_c_require_founder(null),
        'route', 'server_verified_subject'),
      'trace', (select count(*) from public.phase_c_founder_auth_event where txid = txid_current()));`,

  // O02 registered the first writer public.phase_c_refund_decision has ever had. Before it,
  // kernel_write_authority held ZERO rows for that table, so Door 1 of fn_kernel_write_guard could
  // never open and no routine anywhere could create the row the append-only trigger protects — the
  // table sat at 0 and the guard had never been asked a question.
  //
  // The control proves the door ACCEPTS: a decision recorded through the canonical service, with
  // decided_by written from the identity fn_phase_c_require_founder VERIFIED rather than from the
  // call, and the sanctioned supersession accepted on top of it. The refusals that matter to
  // PD-FIN-004 are asserted in protected_table_guards_actually_fire.test.mjs; this file's job is
  // the other half — that an authority nobody proves accepts anything is an authority nobody has
  // tested.
  fn_kernel_refund_decision_record: `
    ${BIND_FOUNDER}
    insert into public.founder_approval_request(action_class, subject_ref, prepared_by_role_id)
    values ('refund_decision','positive-control','payments_and_billing_manager')
    returning request_id into v_req;
    v := public.fn_kernel_refund_decision_record(jsonb_build_object(
           'op','record','request_id',v_req,'decision','approved',
           'reason','positive control for the canonical founder refund decision service'));
    v2 := public.fn_kernel_refund_decision_record(jsonb_build_object(
           'op','record','request_id',v_req,'decision','rejected','reason','superseding',
           'supersedes_decision_id',(v->>'decision_id')::bigint,
           'supersession_reason','positive control supersession'));
    res := jsonb_build_object(
      'accepted', coalesce((v->>'ok')::boolean,false) and coalesce((v2->>'ok')::boolean,false)
                  and v->>'decided_by' = ${lit(FOUNDER)},
      'effect', jsonb_build_object(
        'decision_id', v->>'decision_id',
        'decided_by_is_the_verified_identity_not_the_call', v->>'decided_by' = ${lit(FOUNDER)},
        'superseding_decision_id', v2->>'decision_id',
        'rows_for_this_request', (select count(*) from public.phase_c_refund_decision
                                   where request_id = v_req)),
      'trace', (select count(*) from public.phase_c_refund_decision where request_id = v_req));`,

  fn_phase_d_test_context_open: `
    v := public.fn_phase_d_test_context_open(jsonb_build_object(
           'operation_key','pdop_acceptance_probe', 'label','positive-control-context'));
    res := jsonb_build_object(
      'accepted', coalesce((v->>'ok')::boolean, false)
                  and public.fn_phase_d_fixture_context() = (v->>'fixture_run_id')::bigint,
      'effect', jsonb_build_object(
        'fixture_run_id', v->>'fixture_run_id',
        'operation', public.fn_phase_d_fixture_operation(),
        'grants_for_this_txid',
          (select count(*) from public.phase_d_test_context_grant where txid = txid_current())),
      'trace', (select count(*) from public.phase_d_test_context_grant where txid = txid_current()));`,

  // A ROW ADDED TO kernel_write_authority WITHOUT ITS ARTEFACT. M10 registered
  // fn_phase_d_committed_scenario_close as an authorised writer of six protected kernel tables,
  // and this file discovers its doors FROM that register — so the row alone turned the check red
  // with "NO POSITIVE CONTROL IMPLEMENTED for this door". That is the check working: an authority
  // nobody proves accepts anything is an authority nobody has tested.
  //
  // The control opens a committed scenario and closes it in the SAME aborted transaction, which is
  // how the operation was rehearsed before it was ever run for real. open() refuses unless every
  // guard is green, and close() refuses to record success while one watched relation is above its
  // watermark — so "accepted" here means both halves ran and the reversal proved itself.
  fn_phase_d_committed_scenario_close: `
    v := public.fn_phase_d_committed_scenario_open(jsonb_build_object(
      'label','positive-control-committed-scenario'));
    v2 := public.fn_phase_d_committed_scenario_close((v->>'scenario_id')::bigint);
    res := jsonb_build_object(
      'accepted', coalesce((v2->>'ok')::boolean, false)
                  and (select state from public.phase_d_committed_scenario
                        where scenario_id = (v->>'scenario_id')::bigint) = 'CLOSED',
      'effect', jsonb_build_object(
        'scenario_id', v->>'scenario_id',
        'created', v->'created',
        'removed', v2->'removed',
        'every_watched_relation_back_at_its_watermark',
          (select assertions->'every_watched_relation_back_at_its_watermark'
             from public.phase_d_committed_scenario
            where scenario_id = (v->>'scenario_id')::bigint),
        'fixture_residue', (select count(*) from public.fn_phase_d_fixture_residue())),
      'trace', (select count(*) from public.phase_d_committed_scenario
                 where scenario_id = (v->>'scenario_id')::bigint and state = 'CLOSED'));`,

  fn_phase_d_scenario_record_write: `
    perform public.fn_phase_d_test_context_open(jsonb_build_object(
      'operation_key','pdop_scenario_factory', 'label','positive-control-manifest'));
    v := public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label','positive-control-manifest', 'execution_context','test', 'up_to_stage', 30));
    res := jsonb_build_object(
      'accepted', (select count(*) from public.phase_d_scenario_record
                    where fixture_run_id = public.fn_phase_d_fixture_context()) > 0,
      'effect', jsonb_build_object(
        'manifest_rows', (select count(*) from public.phase_d_scenario_record
                           where fixture_run_id = public.fn_phase_d_fixture_context()),
        'stages_created', v->>'stages_created',
        'every_row_names_its_canonical_service',
          not exists (select 1 from public.phase_d_scenario_record
                       where fixture_run_id = public.fn_phase_d_fixture_context()
                         and coalesce(btrim(canonical_service),'') = '')),
      'trace', (select count(*) from public.phase_d_scenario_record
                 where fixture_run_id = public.fn_phase_d_fixture_context()));`,

  fn_phase_d_founder_authority_fixture: `
    perform public.fn_phase_d_test_context_open(jsonb_build_object(
      'operation_key','pdop_scenario_factory', 'label','positive-control-authority'));
    v := public.fn_phase_d_founder_authority_fixture(jsonb_build_object('label','positive-control-authority'));
    res := jsonb_build_object(
      'accepted', coalesce((v->>'ok')::boolean, false)
                  and exists (select 1 from public.founder_command fc
                               where fc.command_id = (v->>'command_id')::bigint),
      'effect', jsonb_build_object(
        'command_id', v->>'command_id',
        'founder_initiated_only',
          (select fc.founder_initiated_only from public.founder_command fc
            where fc.command_id = (v->>'command_id')::bigint),
        'refund_semantics',
          (select fc.refund_semantics from public.founder_command fc
            where fc.command_id = (v->>'command_id')::bigint),
        'br003_now_resolves_it',
          (select ok from public.fn_phase_d_rule_check('BR-003',
             jsonb_build_object('founder_authority_ref', v->>'founder_authority_ref')))),
      'trace', (select count(*) from public.phase_d_scenario_record
                 where fixture_run_id = public.fn_phase_d_fixture_context()
                   and contributes_ref = 'founder_authority_ref'));`,

  fn_phase_d_capability_request_open: `
    perform public.fn_phase_d_test_context_open(jsonb_build_object(
      'operation_key','pdop_capability_fixture', 'label','positive-control-caprequest'));
    v := public.fn_kernel_workflow_start(jsonb_build_object(
      'workflow_id','W25', 'business_object_id','ZZ-POSITIVE-CONTROL-CAPREQ',
      'source_kind','autonomous', 'source_ref','zz-positive-control-capreq',
      'requested_by', (select accountable_role_id from public.phase_b_workflow where workflow_id='W25'),
      'trigger_ctx', jsonb_build_object('probe','kernel_positive_controls')));
    run := (v->>'run_id')::bigint;
    select sr4.step_run_id into sr from public.phase_c_workflow_step_run sr4
     where sr4.run_id = run and sr4.step_id = 'W25-S01' limit 1;
    if sr is null then
      select sr4.step_run_id into sr from public.phase_c_workflow_step_run sr4
       where sr4.run_id = run order by sr4.step_run_id limit 1;
    end if;
    v2 := public.fn_phase_d_capability_request_open(jsonb_build_object(
      'step_run_id', sr, 'requested_by','positive_control'));
    res := jsonb_build_object(
      'accepted', coalesce((v2->>'ok')::boolean, false),
      'effect', jsonb_build_object(
        'request_id', v2->>'request_id',
        'state', (select q.state from public.phase_d_capability_request q
                   where q.request_id = (v2->>'request_id')::bigint),
        'capability', v2->>'capability'),
      'trace', (select count(*) from public.phase_d_capability_request
                 where step_run_id = sr));`,

  fn_phase_d_capability_result_accept: `
    perform public.fn_phase_d_test_context_open(jsonb_build_object(
      'operation_key','pdop_capability_fixture', 'label','positive-control-capresult'));
    v := public.fn_kernel_workflow_start(jsonb_build_object(
      'workflow_id','W25', 'business_object_id','ZZ-POSITIVE-CONTROL-CAPRES',
      'source_kind','autonomous', 'source_ref','zz-positive-control-capres',
      'requested_by', (select accountable_role_id from public.phase_b_workflow where workflow_id='W25'),
      'trigger_ctx', jsonb_build_object('probe','kernel_positive_controls')));
    run := (v->>'run_id')::bigint;
    select sr4.step_run_id into sr from public.phase_c_workflow_step_run sr4
     where sr4.run_id = run and sr4.step_id = 'W25-S01' limit 1;
    v2 := public.fn_phase_d_capability_request_open(jsonb_build_object(
      'step_run_id', sr, 'requested_by','positive_control'));
    v2 := public.fn_phase_d_capability_result_accept(jsonb_build_object(
      'request_id', (v2->>'request_id')::bigint, 'provider_mode','fixture',
      'fixture_id', (select c.fixture_id from public.phase_d_fixture_catalogue c
                      where c.scope='CAPABILITY_RESULT' and c.step_id='W25-S01' limit 1),
      'accepted_by','positive_control'));
    res := jsonb_build_object(
      'accepted', coalesce((v2->>'ok')::boolean, false)
                  and public.fn_phase_d_capability_answer(sr) is not null,
      'effect', jsonb_build_object(
        'result_id', v2->>'result_id',
        'provider_mode', v2->>'provider_mode',
        'fixture_id', v2->>'fixture_id',
        'request_state', (select q.state from public.phase_d_capability_request q
                           where q.request_id = (v2->>'request_id')::bigint),
        'paid_provider_results',
          (select count(*) from public.phase_d_capability_result where provider_mode = 'provider')),
      'trace', (select count(*) from public.phase_d_capability_result r
                 join public.phase_d_capability_request q on q.request_id = r.request_id
                where q.step_run_id = sr));`,

  fn_kernel_workflow_start: `
    v := public.fn_kernel_workflow_start(jsonb_build_object(
      'workflow_id','W14', 'business_object_id','ZZ-POSITIVE-CONTROL-W14',
      'source_kind','autonomous', 'source_ref','positive-control',
      'requested_by','positive-control'));
    run := (v->>'run_id')::bigint;
    res := jsonb_build_object(
      'accepted', coalesce((v->>'ok')::boolean, false),
      'effect', jsonb_build_object(
        'run', run,
        'step_runs', (select count(*) from public.phase_c_workflow_step_run where run_id = run),
        'tasks', (select count(*) from public.phase_c_task where run_id = run),
        'events', (select count(*) from public.phase_c_event_outbox where workflow_run_id = run)),
      'trace', (select count(*) from public.phase_c_trace where run_id = run));`,

  fn_kernel_open_step: `
    ${SEED('positive-control-open-step')}
    -- complete the first step so a successor exists, then open it through the door under test
    v2 := public.fn_kernel_step_complete(jsonb_build_object(
      'step_run_id', sr, 'actor_role_id', owner, 'outcome','pass',
      'idempotency_key','positive-control-open-step-' || stp,
      'inputs', ${INPUTS}, 'output', ${OUTPUT},
      'evidence_refs', jsonb_build_array(jsonb_build_object('positive_control', true)),
      'requested_action','proceed', 'acceptance_criteria','positive control', 'object_version', 1));
    select h.handoff_run_id, h.receiving_role_id into hnd, recv
      from public.phase_c_handoff_run h where h.run_id = run and h.status = 'open' limit 1;
    if hnd is not null then
      perform public.fn_kernel_handoff_accept(jsonb_build_object(
        'handoff_run_id', hnd, 'actor_role_id', recv, 'decision','accept', 'outcome','accept',
        'reason','positive control', 'packet', jsonb_build_object(
          'object_version', 1, 'output','positive control', 'business_object_id','positive-control',
          'acceptance_evidence','positive control', 'unresolved_blockers','none',
          'requested_action','proceed',
          'evidence_refs', jsonb_build_array(jsonb_build_object('positive_control', true)))));
    end if;
    select sr2.step_run_id, sr2.step_id into sr2_id, stp2
      from public.phase_c_workflow_step_run sr2 where sr2.run_id = run and sr2.state = 'active'
      order by sr2.step_run_id desc limit 1;
    res := jsonb_build_object(
      'accepted', sr2_id is not null and sr2_id <> sr,
      'effect', jsonb_build_object('first_step', stp, 'opened_step', stp2, 'step_runs',
        (select count(*) from public.phase_c_workflow_step_run where run_id = run)),
      'trace', (select count(*) from public.phase_c_trace where run_id = run));`,

  fn_kernel_step_complete: `
    ${SEED('positive-control-step-complete')}
    v2 := public.fn_kernel_step_complete(jsonb_build_object(
      'step_run_id', sr, 'actor_role_id', owner, 'outcome','pass',
      'idempotency_key','positive-control-complete-' || stp,
      'inputs', ${INPUTS}, 'output', ${OUTPUT},
      'evidence_refs', jsonb_build_array(jsonb_build_object('positive_control', true)),
      'requested_action','proceed', 'acceptance_criteria','positive control', 'object_version', 1));
    res := jsonb_build_object(
      'accepted', coalesce((v2->>'ok')::boolean, false),
      'effect', jsonb_build_object(
        'step_state', (select state from public.phase_c_workflow_step_run where step_run_id = sr),
        'run_state', v2->>'run_state', 'output_hash', left(coalesce(v2->>'output_hash',''), 16)),
      'trace', (select count(*) from public.phase_c_trace where step_run_id = sr));`,

  fn_kernel_handoff_accept: `
    ${SEED('positive-control-handoff')}
    perform public.fn_kernel_step_complete(jsonb_build_object(
      'step_run_id', sr, 'actor_role_id', owner, 'outcome','pass',
      'idempotency_key','positive-control-handoff-' || stp,
      'inputs', ${INPUTS}, 'output', ${OUTPUT},
      'evidence_refs', jsonb_build_array(jsonb_build_object('positive_control', true)),
      'requested_action','proceed', 'acceptance_criteria','positive control', 'object_version', 1));
    select h.handoff_run_id, h.receiving_role_id, h.sending_role_id into hnd, recv, sender
      from public.phase_c_handoff_run h where h.run_id = run and h.status = 'open' limit 1;
    v2 := public.fn_kernel_handoff_accept(jsonb_build_object(
      'handoff_run_id', hnd, 'actor_role_id', recv, 'decision','accept', 'outcome','accept',
      'reason','positive control', 'packet', jsonb_build_object(
        'object_version', 1, 'output','positive control', 'business_object_id','positive-control',
        'acceptance_evidence','positive control', 'unresolved_blockers','none',
        'requested_action','proceed',
        'evidence_refs', jsonb_build_array(jsonb_build_object('positive_control', true)))));
    res := jsonb_build_object(
      'accepted', coalesce((v2->>'ok')::boolean, false),
      'effect', jsonb_build_object(
        'handoff_status', (select status from public.phase_c_handoff_run where handoff_run_id = hnd),
        'sender', sender, 'receiver', recv),
      'trace', (select count(*) from public.phase_c_trace where run_id = run));`,

  fn_kernel_handoff_reject: `
    ${SEED('positive-control-handoff-reject')}
    perform public.fn_kernel_step_complete(jsonb_build_object(
      'step_run_id', sr, 'actor_role_id', owner, 'outcome','pass',
      'idempotency_key','positive-control-handoff-reject-' || stp,
      'inputs', ${INPUTS}, 'output', ${OUTPUT},
      'evidence_refs', jsonb_build_array(jsonb_build_object('positive_control', true)),
      'requested_action','proceed', 'acceptance_criteria','positive control', 'object_version', 1));
    select h.handoff_run_id, h.receiving_role_id, h.sending_role_id into hnd, recv, sender
      from public.phase_c_handoff_run h where h.run_id = run and h.status = 'open' limit 1;
    v2 := public.fn_kernel_handoff_reject(jsonb_build_object(
      'handoff_run_id', hnd, 'actor_role_id', recv,
      'reason','positive control rejection', 'missing','the positive-control packet item'));
    res := jsonb_build_object(
      'accepted', coalesce((v2->>'ok')::boolean, false)
                  and (select status from public.phase_c_handoff_run where handoff_run_id = hnd) = 'rejected',
      'effect', jsonb_build_object(
        'handoff_status', (select status from public.phase_c_handoff_run where handoff_run_id = hnd),
        'sender', sender, 'receiver', recv, 'run_state', v2->>'run_state'),
      'trace', (select count(*) from public.phase_c_trace where run_id = run));`,

  fn_kernel_review_decide: `
    v := public.fn_kernel_workflow_start(jsonb_build_object(
      'workflow_id','W14', 'business_object_id','ZZ-POSITIVE-CONTROL-REVIEW',
      'source_kind','autonomous', 'source_ref','positive-control', 'requested_by','positive-control'));
    run := (v->>'run_id')::bigint;
    -- drive to the one W14 step that declares an independent reviewer
    loop
      select sr3.step_run_id, sr3.step_id, sr3.accountable_role_id into sr, stp, owner
        from public.phase_c_workflow_step_run sr3 where sr3.run_id = run and sr3.state='active'
        order by sr3.step_run_id limit 1;
      exit when sr is null;
      select s.independent_reviewer_role_id into recv from public.phase_b_workflow_step s where s.step_id = stp;
      select t.task_id into tsk from public.phase_c_task t where t.run_id = run and t.step_id = stp
        order by t.task_id desc limit 1;
      if coalesce(btrim(recv),'') <> '' then exit; end if;
      perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', sr, 'actor_role_id', owner, 'outcome','pass',
        'idempotency_key','positive-control-review-' || stp,
        'inputs', ${INPUTS}, 'output', ${OUTPUT},
        'evidence_refs', jsonb_build_array(jsonb_build_object('positive_control', true)),
        'requested_action','proceed', 'acceptance_criteria','positive control', 'object_version', 1));
      perform public.fn_kernel_handoff_accept(jsonb_build_object(
          'handoff_run_id', h.handoff_run_id, 'actor_role_id', h.receiving_role_id,
          'decision','accept', 'outcome','accept', 'reason','positive control',
          'packet', jsonb_build_object('object_version',1,'output','positive control',
            'business_object_id','positive-control','acceptance_evidence','positive control',
            'unresolved_blockers','none','requested_action','proceed',
            'evidence_refs', jsonb_build_array(jsonb_build_object('positive_control', true)))))
        from public.phase_c_handoff_run h where h.run_id = run and h.status = 'open';
      sr := null;
    end loop;
    v2 := public.fn_kernel_review_decide(jsonb_build_object(
      'task_id', tsk, 'reviewer_role_id', recv, 'decision','approved',
      'reason','positive control: an independent reviewer approves'));
    res := jsonb_build_object(
      'accepted', coalesce((v2->>'ok')::boolean, false),
      'effect', jsonb_build_object('step', stp, 'reviewer', recv, 'task', tsk),
      'trace', (select count(*) from public.phase_c_trace where task_id = tsk));`,

  fn_kernel_signal_submit: `
    ${SEED('positive-control-signal')}
    v2 := public.fn_kernel_signal_submit(jsonb_build_object(
      'source_type','positive_control', 'source_id','pc-signal', 'requested_by','positive-control',
      'signal_type','document.arrived_for_run', 'workflow_run_id', run,
      'payload', jsonb_build_object('note','positive control')));
    res := jsonb_build_object(
      'accepted', coalesce((v2->>'ok')::boolean, false),
      'effect', jsonb_build_object('status', v2->>'status', 'attached_step', v2->>'active_step_id',
        'inbox', (select count(*) from public.kernel_signal_inbox where workflow_run_id = run)),
      'trace', (select count(*) from public.phase_c_trace where trace_id = (v2->>'trace_id')::bigint));`,

  // 27 AUG 2026 — THE CONTROL WAS MANUFACTURING ITS OWN SUBJECT, and a10_kernel_workflow_run_parent_
  // exists is what said so. `incident_ref` used to be the literal 'ZZ-POSITIVE-CONTROL-TRIGGER', so
  // the run this control opened named business object `incident:ZZ-POSITIVE-CONTROL-TRIGGER` — an
  // identity that resolves to no row in public.os_incidents and never could. The new guard refuses
  // it 23503, and the guard is right: an identity is never a fixture.
  //
  // The reference now takes the shape THIS SOURCE ACTUALLY EMITS IN PRODUCTION. Run 352, opened
  // 2026-08-17 by trg_page_high_agent_action and still active, carries
  // `incident:agent_action:3833` — the trigger keys the subject by the agent_actions row that
  // raised it, not by an os_incidents id. Driving the shape production drives is the whole point of
  // a positive control; driving a shape nothing produces proved only that the fixture ran.
  //
  // (That the W29 producer and phase_d_business_object_binding disagree about how an `incident`
  // subject is keyed is a real, separate finding — recorded in
  // docs/phase-d/PHASE_D_ORPHAN_WORK_REPAIR.md §5, not papered over here.)
  fn_kernel_trigger_submit: `
    v2 := public.fn_kernel_source_emit('dbtrigger:public.agent_actions:trg_page_high_agent_action',
      jsonb_build_object('source_ref','ZZ-POSITIVE-CONTROL-TRIGGER', 'requested_by','positive-control',
        'raw_payload', jsonb_build_object('incident_ref',
          'agent_action:' || (select max(a.id)::text from public.agent_actions a))));
    run := (v2->>'run_id')::bigint;
    res := jsonb_build_object(
      'accepted', coalesce((v2->>'ok')::boolean, false),
      'effect', jsonb_build_object('run', run, 'created', v2->'created',
        'inbox', (select count(*) from public.kernel_trigger_inbox where run_id = run)),
      'trace', (select count(*) from public.phase_c_trace where run_id = run));`,

  fn_kernel_outbox_emit: `
    ${SEED('positive-control-emit')}
    v2 := public.fn_kernel_outbox_emit(jsonb_build_object(
      'event_id', public.fn_phase_c_lifecycle_event('W20','completed'),
      'workflow_id','W20', 'workflow_run_id', run, 'step_run_id', sr, 'task_id', tsk,
      'command_id', cmd, 'producer','kernel:positive_control',
      'correlation_id','positive-control:' || cmd::text, 'causation_id','positive-control',
      'source_id','positive-control', 'accountable_role_id', owner,
      'payload', jsonb_build_object('fact','positive control'),
      'dedupe_value','positive-control:' || cmd::text));
    res := jsonb_build_object(
      'accepted', v2 is not null,
      'effect', jsonb_build_object('events_for_run',
        (select count(*) from public.phase_c_event_outbox where workflow_run_id = run)),
      'trace', (select count(*) from public.phase_c_trace where run_id = run));`,

  fn_kernel_outbox_deliver: `
    ${SEED('positive-control-deliver')}
    v2 := (select to_jsonb(x) from public.fn_kernel_outbox_deliver(5, 'positive-control') x);
    res := jsonb_build_object(
      'accepted', coalesce((v2->>'delivered')::int, 0) >= 1,
      'effect', jsonb_build_object('claimed', v2->>'claimed', 'delivered', v2->>'delivered',
        'row_status', (select status from public.phase_c_event_outbox where outbox_id = ob)),
      'trace', (select count(*) from public.phase_c_event_delivery_attempt where outbox_id = ob));`,
};

// ---------------------------------------------------------------- the derived denominator
//
// 17 AUG 2026 — THE NAME PREFIX IS GONE, AND THAT IS THE WHOLE POINT.
//   This read `where (routine_name like 'fn\_kernel\_%' or like 'fn\_founder\_command\_%') and not
//   retired`. The stated rule is "active write authorities MINUS retired paths"; the prefix was a
//   third term nobody had written down, and it silently removed SIX rows that were active and
//   unretired: fn_phase_c_outbox_emit, fn_phase_c_handoff_open, fn_phase_c_handoff_decide,
//   fn_phase_c_task_transition and the two z90_* trace-subject trigger helpers.
//
//   That was not cosmetic. The independent acceptance called fn_phase_c_outbox_emit as service_role
//   and it WROTE a deliverable outbox row with trace_id NULL, while this check printed
//   "13 door(s), 13 accepted" — because the door it had just walked through was filtered out
//   before the "every door has a control" loop ever ran.
//
//   kernel_s4 gave all six the disposition their kernel_write_authority.why already claimed, so the
//   honest derivation and the prefix now agree on 13. They agree because the register says so, not
//   because a LIKE pattern happens to match. If a future entry door is called anything else, this
//   query sees it and demands a control; the old one did not.
const doors = (await sql(`
  select distinct a.routine_name
    from public.kernel_write_authority a
   where not exists (select 1 from public.kernel_retired_path p where p.path_name = a.routine_name)
   order by 1`)).map(r => r.routine_name);

// FIVE DOORS STOPPED BEING DRIVEABLE FROM HERE ON 25 AUG 2026, AND THAT IS PCCR-006 WORKING.
//
// Each of these needs a VERIFIED FOUNDER SESSION before it will accept anything. Until PCCR-006
// this file got one by calling fn_phase_c_founder_subject_bind, which refused only
// `current_user in ('anon','authenticated')` -- and the management API connects as `postgres`,
// which is neither. So CI could mint a founder session with no bearer token in existence.
//
// That was FINDING D of PCCR-006, the deepest one in the change request. PCCR-006 closed it: the
// bind door now requires `session_user = 'authenticator'`, the one connection a founder JWT can
// arrive on. Applied to production on the founder's approval, Command Center command 39505.
//
// So these five can no longer be DRIVEN from any connection this check has. The wrong response is
// to re-open the door so the tests keep passing; a guard a test can talk round is not a guard.
// The right one is to say precisely what is and is not proved:
//
//   proved instead : the bind door refuses this connection with 28000 -- a STRONGER property than
//                    the drive ever established, and the one that would go red if D re-opened
//   not proved     : that each door ACCEPTS a genuine founder call. That needs a founder JWT
//                    through PostgREST, which only the founder can produce
//
// They are counted separately and printed by name. A run of this file is not to be read as full
// coverage of 21 doors any more, and the summary line says so.
const NEEDS_A_FOUNDER_SESSION = new Set([
  // 27 Aug 2026. Its own first statement refuses session_user <> 'authenticator', so it is gated for
  // the same reason and by the same mechanism. It IS driven, over real HTTPS, by
  // scripts/phase_d/prove_governance_door.mjs --record.
  'fn_phase_c_governance_decide',
  'fn_phase_c_founder_subject_bind',
  'fn_founder_command_clarify',
  'fn_founder_command_control',
  'fn_kernel_cancel',
  'fn_kernel_refund_decision_record',
]);

// Measured once, not assumed per door. If this ever comes back ACCEPTED, finding D is re-opened
// and that is a hard failure regardless of anything else in this file.
let bindDoor = '';
try {
  await sql(`do $bd$ begin perform public.fn_phase_c_founder_subject_bind(
    (select f.auth_user_id from public.phase_c_founder_identity f
      where f.active and f.kind='email' and f.auth_user_id is not null order by f.identity limit 1));
    raise exception 'BINDDOOR ACCEPTED'; end $bd$;`);
  bindDoor = 'NO_RAISE';
} catch (e) { bindDoor = /28000/.test(String(e.message)) ? 'REFUSED:28000'
            : /BINDDOOR ACCEPTED/.test(String(e.message)) ? 'ACCEPTED' : String(e.message).slice(0, 120); }

let pass = 0, fail = 0;
let gated = 0;
const line = (ok, name, detail) => {
  if (ok) pass++; else fail++;
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${name.padEnd(30)}${detail ? '  ' + String(detail).slice(0, 150) : ''}`);
};

console.log(`canonical kernel entry doors (derived from kernel_write_authority minus kernel_retired_path): ${doors.length}`);
const implemented = Object.keys(CONTROLS);
for (const d of doors) if (!implemented.includes(d)) line(false, d, 'NO POSITIVE CONTROL IMPLEMENTED for this door');
for (const d of implemented) if (!doors.includes(d)) line(false, d, 'a control exists for a door that is not canonical any more');
console.log('');

const before = (await sql(`select
  (select count(*) from public.founder_command) cmds,
  (select count(*) from public.phase_c_workflow_run) runs,
  (select count(*) from public.phase_c_task) tasks,
  (select count(*) from public.phase_c_event_outbox) outbox,
  -- excluding scheduled kernel infrastructure: cron 278 writes a TRACE-SYSTEM-EXECUTION
  -- trace every minute, so a total here moves on its own and says an aborted control survived
  (select count(*) from public.phase_c_trace where trace_policy_id <> 'TRACE-SYSTEM-EXECUTION') traces,
  (select count(*) from public.kernel_signal_inbox) signals,
  (select count(*) from public.kernel_trigger_inbox) triggers`))[0];

for (const door of doors) {
  const body = CONTROLS[door];
  if (!body) continue;
  if (NEEDS_A_FOUNDER_SESSION.has(door) && bindDoor !== 'ACCEPTED') {
    gated++;
    console.log(`gate  ${door.padEnd(30)}  NOT DRIVEABLE — needs a verified founder session, and `
      + `fn_phase_c_founder_subject_bind refuses this connection (${bindDoor}). PCCR-006 finding D.`);
    continue;
  }
  const probe = `do $pc$
declare v jsonb; v2 jsonb; res jsonb;
        cmd bigint; run bigint; sr bigint; sr2_id bigint; tsk bigint; ob bigint; hnd bigint;
        stp text; stp2 text; owner text; recv text; sender text;
        v_req bigint;   -- O02: the founder_approval_request a refund decision answers
begin
${body}
  raise exception 'PC %', res::text;
end $pc$;`;
  let msg = '';
  try { await sql(probe); msg = 'NO_RAISE'; } catch (e) { msg = String(e.message); }
  const s = msg.indexOf('{', msg.indexOf('PC '));
  let depth = 0, end = -1, inStr = false, esc = false;
  for (let i = s; i >= 0 && i < msg.length; i++) {
    const ch = msg[i];
    if (esc) { esc = false; continue; }
    if (ch === '\\') { esc = true; continue; }
    if (ch === '"') { inStr = !inStr; continue; }
    if (inStr) continue;
    if (ch === '{') depth++; else if (ch === '}') { depth--; if (!depth) { end = i; break; } }
  }
  let r = null;
  if (end > 0) { try { r = JSON.parse(msg.slice(s, end + 1).replace(/\\"/g, '"').replace(/\\\\/g, '\\')); } catch { /* */ } }
  if (!r) { line(false, door, 'the control produced no payload: ' + msg.replace(/\s+/g, ' ').slice(0, 200)); continue; }
  const ok = r.accepted === true && Number(r.trace) >= 1;
  line(ok, door, `accepted=${r.accepted} trace=${r.trace} effect=${JSON.stringify(r.effect)}`);
}

const after = (await sql(`select
  (select count(*) from public.founder_command) cmds,
  (select count(*) from public.phase_c_workflow_run) runs,
  (select count(*) from public.phase_c_task) tasks,
  (select count(*) from public.phase_c_event_outbox) outbox,
  -- excluding scheduled kernel infrastructure: cron 278 writes a TRACE-SYSTEM-EXECUTION
  -- trace every minute, so a total here moves on its own and says an aborted control survived
  (select count(*) from public.phase_c_trace where trace_policy_id <> 'TRACE-SYSTEM-EXECUTION') traces,
  (select count(*) from public.kernel_signal_inbox) signals,
  (select count(*) from public.kernel_trigger_inbox) triggers`))[0];
console.log('\nrow counts before/after every aborted positive control:');
for (const k of Object.keys(before)) {
  const same = String(before[k]) === String(after[k]);
  if (!same) fail++;
  console.log(`  ${same ? 'ok  ' : 'FAIL'} ${k.padEnd(10)} ${before[k]} -> ${after[k]}`);
}

if (bindDoor === 'ACCEPTED') {
  fail++;
  console.log('\nFAIL  fn_phase_c_founder_subject_bind accepted a bind from the management '
    + 'connection. PCCR-006 finding D is re-opened: a migration can mint a verified founder session '
    + 'with no bearer token, and every founder-gated door downstream then behaves as it would for a '
    + 'real one.');
}

console.log(`\ngenuine positive controls: ${doors.length} door(s), ${pass} accepted, ${fail} failed, `
  + `${gated} not driveable from this connection`);
if (gated) {
  console.log(`  the ${gated} need a verified founder session. fn_phase_c_founder_subject_bind: `
    + `${bindDoor}. Driving them needs a founder JWT through PostgREST, which only the founder can `
    + 'produce. This run does NOT establish that those doors accept a genuine call.');
}
process.exit(fail === 0 ? 0 : 1);
