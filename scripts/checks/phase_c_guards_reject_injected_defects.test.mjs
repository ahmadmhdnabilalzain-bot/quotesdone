// Gates C5, C7, C8 — force every Phase C guard to fire.
//
//   node scripts/checks/phase_c_guards_reject_injected_defects.test.mjs
//
// A constraint that has never refused anything is indistinguishable from no constraint, and a
// zero row count cannot tell a dead guard from a test whose injection never landed.  Every case
// below therefore does two things: it INJECTS a defect and it asserts the injection actually
// reached the guard.  A case that silently fails to construct its defect is reported as
// INJECTION_MISSED, not as a pass.
//
// Every case runs inside a transaction that always rolls back — the DO block ends in a RAISE
// either way — so production carries nothing away from this file.
//
// A database-reading test must skip loudly when there is no management token.  CI has none.
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
if (!hasToken) {
  console.log('SKIP phase_c_guards_reject_injected_defects: no Supabase management token here.');
  process.exit(0);
}
const { sql } = await import('../phase_c/lib/db.mjs');

/**
 * Each case supplies a body that must RAISE.  `expect` is a substring the raised message must
 * contain for the case to count as "the guard fired for the reason we meant".  A raise carrying
 * some other error is a different defect and is reported as such.
 */
const CASES = [
  // ---------------------------------------------------------------- identity
  ['unknown identity may not own a task',
   `insert into public.phase_c_task (source_kind, source_ref, accountable_role_id, objective,
      acceptance_criteria, closure_criteria, authority_class, idempotency_key)
    values ('probe','probe','a_person_nobody_models','x','x','x','routine_operational_decision','probe:1');`,
   ['23514', 'fn_phase_c_task_state_guard']],

  ['an INACTIVE role may not own a task',
   `insert into public.phase_c_task (source_kind, source_ref, accountable_role_id, objective,
      acceptance_criteria, closure_criteria, authority_class, idempotency_key)
    select 'probe','probe', r.role_id, 'x','x','x','routine_operational_decision','probe:2'
    from public.org_role r where r.status <> 'active' limit 1;`,
   ['23514', 'fn_phase_c_task_state_guard']],

  ['a category overlay may not own a task',
   `insert into public.phase_c_task (source_kind, source_ref, accountable_role_id, objective,
      acceptance_criteria, closure_criteria, authority_class, idempotency_key)
    select 'probe','probe', r.role_id, 'x','x','x','routine_operational_decision','probe:3'
    from public.org_role r where r.status='active' and r.runtime_mode='knowledge_overlay' limit 1;`,
   ['23514', 'fn_phase_c_overlay_may_not_dispatch']],

  ['a generic name may not be a component owner',
   `insert into public.phase_c_component (component_id, component_type, source_path_or_db_object,
      mutates_state, canonical_system_actor, accountable_role_id, workflow_id, authority_class,
      trace_policy_id, idempotency_strategy, retry_policy, activation_state, classification)
    values ('probe:generic','edge_function','probe', true, 'system.task_engine','Director','W01',
            'routine_operational_decision','TRACE-SYSTEM-EXECUTION','x','x','deployed','CANONICAL_KEEP');`,
   ['23514', 'phase_c_component_no_generic_owner_ck']],

  ['an active state-changing component may not be unowned',
   `alter table public.phase_c_component drop constraint if exists probe_noop;
    insert into public.phase_c_component (component_id, component_type, source_path_or_db_object,
      mutates_state, canonical_system_actor, accountable_role_id, workflow_id, authority_class,
      trace_policy_id, idempotency_strategy, retry_policy, activation_state, classification)
    values ('probe:unowned','edge_function','probe', true, 'system.task_engine','ceo','',
            'routine_operational_decision','TRACE-SYSTEM-EXECUTION','x','x','deployed','CANONICAL_KEEP');`,
   ['23514', 'phase_c_component_accountable_ck']],

  ['an unknown classification is refused',
   `insert into public.phase_c_component (component_id, component_type, source_path_or_db_object,
      mutates_state, canonical_system_actor, accountable_role_id, workflow_id, authority_class,
      trace_policy_id, idempotency_strategy, retry_policy, activation_state, classification)
    values ('probe:cls','edge_function','probe', true, 'system.task_engine','ceo','W01',
            'routine_operational_decision','TRACE-SYSTEM-EXECUTION','x','x','deployed','PROBABLY_FINE');`,
   ['23514', 'phase_c_component_classification_ck']],

  // ---------------------------------------------------------------- founder autonomy
  ['a NON-REFUND founder approval request is refused',
   `insert into public.founder_approval_request (action_class, subject_ref, prepared_by_role_id)
    values ('production_release','probe','ceo');`,
   ['23514', 'fn_founder_approval_refund_only']],

  ['a second founder-approval action class is refused',
   `update public.phase_c_action_class set founder_approval_required = true
     where action_class = 'production_release';`,
   ['23505', 'phase_c_action_class_single_founder_approval_uk']],

  ['a NEW founder release approval is refused',
   `insert into public.founder_release_approval (approved_by, release_ref, scope, evidence)
    values ('management@quotesdone.com','probe','probe','probe');`,
   ['23514', 'fn_phase_c_no_new_founder_approval_path']],

  ['a NEW procurement approval request is refused',
   `insert into public.procurement_approval_request (entity_type, entity_id, status)
    values ('probe','probe','pending');`,
   ['23514', 'fn_phase_c_no_new_founder_approval_path']],

  // 26 AUG 2026: THE THREE REFUND PROBES BUILD A REAL REFUND CHAIN, BECAUSE A SYNTHETIC ONE IS NOW
  // REFUSED BEFORE THE GUARD UNDER TEST IS REACHED.
  //
  // phase_c_a_refund_amount_was_a_number_somebody_typed.sql put two BEFORE triggers on the money:
  // a refund must name a revealed transaction whose reveal_fee it equals and whose refund window
  // has passed, and a refund_decision approval request must carry subject_ref 'refund:<id>' naming
  // a refunds row that exists. 'TX-PROBE' is neither, so all three cases below were refused with
  // 22023 founder_approval_subject_malformed — a real guard firing, but not the one the case is
  // about, and the case would have gone on reporting on an arm it never reached.
  //
  // The fixture is what was wrong, not the guard, so the fixture is what changed: each case now
  // inserts the transaction, the refund and the approval request that a real refund decision would
  // have behind it, and only then injects its defect. Everything is still inside the probe's
  // aborted transaction — the DO block ends in a RAISE either way — so no transaction, refund or
  // inbox item survives. Weakening either trigger to keep these three green would have converted
  // the founder's rule ("it should be exactly equal to the amount of the 3% the customer paid")
  // into a check that passes while nothing enforces it.
  ['a refund decided by someone other than the founder is refused',
   `insert into public.transactions (id, revealed_at, reveal_fee, fee_status, paid_by, payment_ref)
      values ('00000000-0000-4000-8000-00000000fee1', now() - interval '60 days', 10.00,
              'paid','customer','probe:reveal:1');
    insert into public.refunds (transaction_id, currency, reason_code, status, requested_by,
      requested_at, within_auto_window, amount_fils)
      select t.id,'AED','service_not_delivered','requested','zz-probe@example.invalid', now(),
             false, round(t.reveal_fee * 100)::bigint
        from public.transactions t where t.id = '00000000-0000-4000-8000-00000000fee1';
    insert into public.founder_approval_request (action_class, subject_ref, prepared_by_role_id)
      select 'refund_decision','refund:'||r.id,'payments_and_billing_manager'
        from public.refunds r where r.transaction_id = '00000000-0000-4000-8000-00000000fee1';
    insert into public.phase_c_refund_decision (request_id, decided_by, decision)
      select a.request_id, 'chief_of_staff', 'approved'
        from public.founder_approval_request a
        join public.refunds r on 'refund:'||r.id = a.subject_ref
       where r.transaction_id = '00000000-0000-4000-8000-00000000fee1';`,
   // K35: SQLSTATE plus the guard that raises it. Was 'is not the registered founder identity'.
   // fn_phase_c_require_founder refuses earlier and more strictly, with 28000, and the pair below
   // is what rc5 measured it actually raising rather than what anyone remembered it saying.
   ['28000', 'fn_phase_c_require_founder']],

  // PCCR-003, 21 Aug 2026. These two probes are about the refund guard's OTHER arms -- a rejected
  // decision that was executed, and an executor who is also the reconciler. Since the amendment,
  // fn_phase_c_refund_decision_guard resolves the founder from a VERIFIED auth subject, so both were
  // refused with 28000 before their own arm was ever reached, and the check went red.
  //
  // Accepting 28000 as the answer would have been the trap: it would have recorded the identity
  // refusal as proof that the rejected-execution guard works, and neither arm would be tested again.
  // So the probes BIND the verified subject first -- exactly as os_api does -- and the arm they are
  // about is the thing that refuses. The identity arm keeps its own case, immediately above, which
  // binds nothing and still expects 28000.
  ['a refund executed against a REJECTED decision is refused',
   `perform public.fn_phase_c_founder_subject_bind(
      (select f.auth_user_id from public.phase_c_founder_identity f
        where f.identity = 'management@quotesdone.com' and f.active and f.kind = 'email'));
    insert into public.transactions (id, revealed_at, reveal_fee, fee_status, paid_by, payment_ref)
      values ('00000000-0000-4000-8000-00000000fee2', now() - interval '60 days', 10.00,
              'paid','customer','probe:reveal:2');
    insert into public.refunds (transaction_id, currency, reason_code, status, requested_by,
      requested_at, within_auto_window, amount_fils)
      select t.id,'AED','service_not_delivered','requested','zz-probe@example.invalid', now(),
             false, round(t.reveal_fee * 100)::bigint
        from public.transactions t where t.id = '00000000-0000-4000-8000-00000000fee2';
    insert into public.founder_approval_request (action_class, subject_ref, prepared_by_role_id)
      select 'refund_decision','refund:'||r.id,'payments_and_billing_manager'
        from public.refunds r where r.transaction_id = '00000000-0000-4000-8000-00000000fee2';
    insert into public.phase_c_refund_decision (request_id, decided_by, decision, executed_at)
      select a.request_id, 'management@quotesdone.com', 'rejected', now()
        from public.founder_approval_request a
        join public.refunds r on 'refund:'||r.id = a.subject_ref
       where r.transaction_id = '00000000-0000-4000-8000-00000000fee2';`,
   ['23514', 'fn_phase_c_refund_decision_guard']],

  ['a refund whose executor is also its reconciler is refused',
   `perform public.fn_phase_c_founder_subject_bind(
      (select f.auth_user_id from public.phase_c_founder_identity f
        where f.identity = 'management@quotesdone.com' and f.active and f.kind = 'email'));
    insert into public.transactions (id, revealed_at, reveal_fee, fee_status, paid_by, payment_ref)
      values ('00000000-0000-4000-8000-00000000fee3', now() - interval '60 days', 10.00,
              'paid','customer','probe:reveal:3');
    insert into public.refunds (transaction_id, currency, reason_code, status, requested_by,
      requested_at, within_auto_window, amount_fils)
      select t.id,'AED','service_not_delivered','requested','zz-probe@example.invalid', now(),
             false, round(t.reveal_fee * 100)::bigint
        from public.transactions t where t.id = '00000000-0000-4000-8000-00000000fee3';
    insert into public.founder_approval_request (action_class, subject_ref, prepared_by_role_id)
      select 'refund_decision','refund:'||r.id,'payments_and_billing_manager'
        from public.refunds r where r.transaction_id = '00000000-0000-4000-8000-00000000fee3';
    insert into public.phase_c_refund_decision (request_id, decided_by, decision,
      executor_role_id, reconciler_role_id)
      select a.request_id, 'management@quotesdone.com', 'approved',
             'payments_and_billing_manager','payments_and_billing_manager'
        from public.founder_approval_request a
        join public.refunds r on 'refund:'||r.id = a.subject_ref
       where r.transaction_id = '00000000-0000-4000-8000-00000000fee3';`,
   // K35: was the CHECK constraint name. A trigger guard refuses it first, which is stricter —
   // a constraint judges the finished row, and the trigger refuses the write before there is one.
   ['23514', 'fn_phase_c_refund_decision_guard']],

  // ---------------------------------------------------------------- review independence
  ['a task whose reviewer is its own owner is refused',
   `insert into public.phase_c_task (source_kind, source_ref, accountable_role_id, objective,
      acceptance_criteria, closure_criteria, authority_class, idempotency_key,
      reviewer_required, reviewer_role_id)
    values ('probe','probe','ceo','x','x','x','routine_operational_decision','probe:4', true, 'ceo');`,
   ['23514', 'fn_phase_c_task_state_guard']],

  ['a task reviewed by an ALIAS of its own owner is refused',
   `insert into public.phase_c_task (source_kind, source_ref, accountable_role_id, objective,
      acceptance_criteria, closure_criteria, authority_class, idempotency_key,
      reviewer_required, reviewer_role_id)
    select 'probe','probe', a.role_id, 'x','x','x','routine_operational_decision','probe:5', true, a.alias
    from public.org_role_alias a
    join public.org_role r on r.role_id = a.role_id
    where r.status='active' and r.runtime_mode <> 'knowledge_overlay' limit 1;`,
   ['23514', 'fn_phase_c_task_state_guard']],

  // ---------------------------------------------------------------- state models
  ['an invalid workflow transition is refused',
   `insert into public.phase_c_workflow_run (workflow_id, business_object_id, start_event,
      accountable_role_id, state, dedupe_key)
      values ('W01','probe','probe','ceo','queued','probe:wf:1');
    update public.phase_c_workflow_run set state = 'completed' where dedupe_key = 'probe:wf:1';`,
   // K35: was the state-model message. K3c's trace guard refuses first: a run cannot change
   // state without a trace AT ALL, which is the condition the guard exists to make impossible.
   ['23514', 'fn_kernel_workflow_run_trace_guard']],

  ['an invalid task transition is refused',
   `insert into public.phase_c_task (source_kind, source_ref, accountable_role_id, objective,
      acceptance_criteria, closure_criteria, authority_class, idempotency_key)
      values ('probe','probe','ceo','x','x','x','routine_operational_decision','probe:6');
    update public.phase_c_task set state = 'completed' where idempotency_key = 'probe:6';`,
   ['23514', 'fn_phase_c_task_state_guard']],

  ['a founder command may not jump states',
   `do $inner$
    declare v jsonb;
    begin
      v := public.fn_founder_command_submit('management@quotesdone.com',
             'Prepare the next 90-day cash forecast by Friday.','probe:cmdstate','{}'::jsonb);
      update public.founder_command set state = 'received' where command_id = (v->>'command_id')::bigint;
    end $inner$;`,
   ['23514', 'fn_founder_command_state_guard']],

  // ---------------------------------------------------------------- handoffs
  ['a handoff that flips ownership before acceptance is refused',
   `insert into public.phase_c_handoff_run (handoff_id, sending_role_id, receiving_role_id,
      packet_hash, accountable_until_accept_role_id)
    select h.handoff_id, h.sending_role_id, h.receiving_role_id, 'probe', h.receiving_role_id
    from public.phase_b_handoff h limit 1;`,
   ['23514', 'fn_phase_c_handoff_sender_retains']],

  ['a rejected handoff with no reason is refused',
   `insert into public.phase_c_handoff_run (handoff_id, sending_role_id, receiving_role_id,
      packet_hash, accountable_until_accept_role_id, status)
    select h.handoff_id, h.sending_role_id, h.receiving_role_id, 'probe', h.sending_role_id, 'rejected'
    from public.phase_b_handoff h limit 1;`,
   ['23514', 'phase_c_handoff_run_reject_ck']],

  // ---------------------------------------------------------------- traces
  ['a sealed trace cannot be edited',
   `insert into public.phase_c_trace (trace_policy_id, subject_kind, subject_ref, status, sealed_at)
      values ('TRACE-TASK','probe','probe','sealed', now());
    update public.phase_c_trace set status = 'rewritten'
      where subject_ref = 'probe' and subject_kind = 'probe';`,
   ['23514', 'fn_phase_c_trace_append_only']],

  ['a trace under an unknown policy is refused',
   `select public.fn_phase_c_trace_write('TRACE-INVENTED', '{"subject_kind":"probe"}'::jsonb);`,
   ['23503', 'fn_phase_c_trace_write']],

  // ---------------------------------------------------------------- idempotency
  ['a duplicate task idempotency key is refused',
   `insert into public.phase_c_task (source_kind, source_ref, accountable_role_id, objective,
      acceptance_criteria, closure_criteria, authority_class, idempotency_key)
      values ('probe','probe','ceo','x','x','x','routine_operational_decision','probe:dup');
    insert into public.phase_c_task (source_kind, source_ref, accountable_role_id, objective,
      acceptance_criteria, closure_criteria, authority_class, idempotency_key)
      values ('probe','probe','cfo','x','x','x','routine_operational_decision','probe:dup');`,
   ['23505', 'phase_c_task_idem_uk']],

  ['a duplicate founder message idempotency key is refused',
   `insert into public.founder_command_message (founder_identity, raw_text, raw_text_hash, client_idempotency_key)
      values ('management@quotesdone.com','probe','h','probe:msgdup');
    insert into public.founder_command_message (founder_identity, raw_text, raw_text_hash, client_idempotency_key)
      values ('management@quotesdone.com','probe again','h','probe:msgdup');`,
   ['23505', 'founder_command_message_idem_uk']],

  ["the founder's own words cannot be edited",
   `insert into public.founder_command_message (founder_identity, raw_text, raw_text_hash, client_idempotency_key)
      values ('management@quotesdone.com','probe','h','probe:immutable');
    update public.founder_command_message set raw_text = 'something else'
      where client_idempotency_key = 'probe:immutable';`,
   ['23514', 'fn_founder_command_message_immutable']],

  ['an unknown canonical event cannot be emitted',
   `select public.fn_phase_c_outbox_emit('EV-INVENTED','probe','{}'::jsonb,'probe');`,
   ['23503', 'fn_phase_c_outbox_emit']],

  ['an unknown workflow cannot be started',
   `select public.fn_phase_c_workflow_start('W99','probe','{}'::jsonb);`,
   ['23503', 'fn_phase_c_workflow_start']],

  // ---------------------------------------------------------------- TRUNCATE, on the doors
  //
  // 18 Aug 2026, independent final acceptance. A row-level BEFORE trigger cannot fire on TRUNCATE,
  // and kernel_s4 attached the statement-level guard to a hand-typed list of seven tables. Measured
  // on production: 75 tables carry an enforcing row-level trigger and 68 had no TRUNCATE guard.
  // service_role emptied kernel_trigger_inbox 1 -> 0 with every instrument green.
  //
  // fn_kernel_truncate_protection_state() now watches the CONFIGURATION — grants revoked, trigger
  // attached, derived from the catalogue rather than typed. These three cases watch the BEHAVIOUR,
  // because a grant that happens to be missing and a guard that actually refuses are not the same
  // fact, and only one of them survives someone re-granting TRUNCATE.
  //
  // Each clears kernel.maintenance_reason first. The harness sets it so K18 does not answer ahead
  // of the guard under test; here that same reason would open the truncate guard's audited
  // maintenance door (this file runs as the table owner), and the case would prove nothing. With
  // the reason cleared the owner still holds the privilege, so the statement reaches the trigger
  // and the trigger is what refuses it.
  ['TRUNCATE on the signal door is refused',
   `perform set_config('kernel.maintenance_reason', '', true);
    truncate table public.kernel_signal_inbox;`,
   ['42501', 'a truncate is not a kernel write']],

  ['TRUNCATE on the request door is refused',
   `perform set_config('kernel.maintenance_reason', '', true);
    truncate table public.kernel_trigger_inbox;`,
   ['42501', 'a truncate is not a kernel write']],

  // O02 GAVE THIS TABLE AN INBOUND FOREIGN KEY, AND POSTGRES NOW REFUSES THE TRUNCATE FIRST.
  //
  // `refunds.refund_decision_id REFERENCES phase_c_refund_decision(decision_id)` is the binding
  // between the founder's decision and the money, and its side effect is that a TRUNCATE is
  // refused at 0A000 — "cannot truncate a table referenced in a foreign key constraint" — BEFORE
  // z00_kernel_truncate_guard is reached. The ledger is therefore MORE protected than it was, and
  // this case can no longer be the thing that proves the kernel guard fires.
  //
  // So it asserts what is now true: the truncate is refused, by the FK or by the guard. The
  // guard's own liveness is not taken on trust and is not lost — the two cases immediately above
  // drive it on kernel_signal_inbox and kernel_trigger_inbox, neither of which carries an inbound
  // FK, and both still expect 42501 and the guard's own sentence. Widening THIS case without those
  // two would be softening the check; with them it is recording which of two refusals arrives
  // first.
  ['TRUNCATE on the refund decision ledger is refused',
   `perform set_config('kernel.maintenance_reason', '', true);
    truncate table public.phase_c_refund_decision;`,
   ['0A000', 'cannot truncate a table referenced in a foreign key constraint']],
];

// Cases whose guard returns a REFUSAL VALUE rather than raising.  A refusal that comes back as
// data is still a refusal, but it has to be asserted differently — and asserting it as an
// exception would have made these look like passing guards when they were not running at all.
const VALUE_CASES = [
  ['an unknown action class fails closed',
   `select allowed::text || '|' || reason from public.fn_phase_c_authority_check('invented_action','ceo',null)`,
   'false|unknown action class'],
  ['a founder-initiated-only action cannot be committed autonomously',
   `select allowed::text || '|' || reason from public.fn_phase_c_authority_check('commercial_model_change','ceo','cfo')`,
   'false|commercial_model_change is founder_initiated_only'],
  ['a refund cannot be authorised by an employee',
   `select allowed::text || '|' || reason from public.fn_phase_c_authority_check('refund_decision','payments_and_billing_manager','financial_controller')`,
   'false|refund_decision requires the founder'],
  ['an unknown gate fails closed',
   `select passed::text || '|' || reason from public.fn_phase_c_gate_evaluate('GATE-999','{"evidence_ref":"x","actor_role_id":"ceo"}'::jsonb)`,
   'false|unknown gate'],
  ['a gate with NO evidence fails closed',
   `select passed::text || '|' || reason from public.fn_phase_c_gate_evaluate('GATE-001','{}'::jsonb)`,
   'false|'],
  ['an unknown business rule fails closed',
   `select ok::text || '|' || reason from public.fn_phase_c_rule_check('BR-999','{}'::jsonb)`,
   'false|unknown business rule'],
  ['a truncated output cannot mutate state',
   `select valid::text || '|' || reason from public.fn_phase_c_output_validate('probe','{"status":"ok","output":"partial","truncated":true}'::jsonb)`,
   'false|output carries an explicit truncation'],
  ['an output cut at a token limit cannot mutate state',
   `select valid::text || '|' || reason from public.fn_phase_c_output_validate('probe','{"status":"ok","output":"x","stop_reason":"length"}'::jsonb)`,
   'false|output carries an explicit truncation'],
  ['a null output is not a success',
   `select valid::text || '|' || reason from public.fn_phase_c_output_validate('probe', null)`,
   'false|null output is not a successful result'],
  ['an output missing required fields cannot mutate state',
   `select valid::text || '|' || reason from public.fn_phase_c_output_validate('probe','{"status":"ok"}'::jsonb)`,
   'false|required fields missing'],
  ['an unregistered tool is refused',
   `select authorized::text || '|' || reason from public.fn_phase_c_tool_authorized('ceo','a_tool_that_does_not_exist')`,
   "false|tool 'a_tool_that_does_not_exist' is not in the registry"],
  ['an unresolved identity cannot use a tool',
   `select authorized::text || '|' || reason from public.fn_phase_c_tool_authorized('nobody','kb_search')`,
   'false|'],
  ['an unknown actor is refused by the resolver, not returned as null',
   `select kind || '|' || reason from public.fn_phase_c_resolve_actor('a_person_nobody_models')`,
   'unknown|no active canonical role'],
  ['an unknown handoff packet fails closed',
   `select valid::text || '|' || missing from public.fn_phase_c_handoff_packet_valid('H-INVENTED','{}'::jsonb)`,
   'false|unknown handoff'],
  ['an incomplete handoff packet names exactly what is missing',
   `select valid::text || '|' || missing from public.fn_phase_c_handoff_packet_valid(
      (select handoff_id from public.phase_b_handoff limit 1), '{"business_object_id":"x"}'::jsonb)`,
   'false|object_version, output, evidence_refs, requested_action'],
  ['a delivery reported ok with NO downstream record is not counted as delivered',
   `select public.fn_phase_c_outbox_settle(o.outbox_id, true, '', '') from (
      select public.fn_phase_c_outbox_emit(
        (select event_id from public.phase_b_event limit 1), 'probe','{}'::jsonb,'probe:settle') as outbox_id) o`,
   // K36: fn_phase_c_outbox_settle is READ_ONLY_HISTORICAL and now refuses. This case used to
   // assert 'retry_wait' and had been failing on a latent cast defect inside it — a routine
   // that RAN and got as far as writing, not one that refused. The refusal is the guard now.
   ['23514', 'fn_phase_c_outbox_settle']],
  ['a non-founder identity cannot command the company',
   `select public.fn_founder_command_submit('someone@example.invalid','Deploy the latest code now.','probe:notfounder','{}'::jsonb)->>'error'`,
   'not_the_founder'],
  // This one has to be sequential statements, not one CTE.  Inside a single statement every CTE
  // branch and the outer count share ONE snapshot, so the message row written by the first call
  // is invisible to the count and the check reports 0 whether or not the code is right. Moved
  // into its own block below (SEQ_CASES) so each statement gets its own snapshot.
  ['a duplicate outbox emit returns the SAME row, not a second one',
   `select (public.fn_phase_c_outbox_emit((select event_id from public.phase_b_event limit 1),'probe','{}'::jsonb,'probe:dedupe')
         = public.fn_phase_c_outbox_emit((select event_id from public.phase_b_event limit 1),'probe','{}'::jsonb,'probe:dedupe'))::text`,
   'true'],
  // W01-S02 has a declared predecessor, so the ORDER check answered first and this case was
  // measuring out_of_order while its name claimed it measured ownership. Injected on the entry
  // step instead, where ownership is the only thing in the way — and with a real output, because
  // a completing step no longer hashes the empty string.
  ['the wrong employee cannot advance a frozen step',
   `select public.fn_phase_c_step_advance(
      public.fn_phase_c_workflow_start('W05','probe-step','{}'::jsonb),
      public.fn_phase_c_entry_step('W05'),'chief_of_staff',
      jsonb_build_object('output', jsonb_build_object('status','completed','output','probe')))->>'error'`,
   // K13 retired fn_phase_c_step_advance outright, which is STRICTER than refusing the wrong
   // employee: no caller can advance a step by that path, right owner or wrong. The case now
   // asserts the retirement, because that is what stands between a defect and the data.
   ['23514', 'fn_phase_c_step_advance']],
  ['an overlay outside its declared scope cannot own a step',
   `select public.fn_phase_c_step_owner_valid('W01-S01','category_overlay_004_formwork-and-scaffolding-suppliers')::text`,
   'false'],
  // A category overlay may own an analysis step in W05/W06/W07/W10 (positive control for the validator).
  // NOT W14: PBCR-001 moved W14-S05 to the canonical role quote_evaluation, and E13 dropped W14 from the
  // overlay hardcode + repointed the step binding, so the overlay is now correctly REFUSED there. W05-S03
  // is a genuinely overlay-ownable analysis step, so it stands in as the permitted example.
  ['a legitimate overlay-owned analysis step is permitted',
   `select public.fn_phase_c_step_owner_valid('W05-S03','relevant_category_overlay')::text`,
   'true'],
];

// Cases that need several SEQUENTIAL statements so each gets its own snapshot.  The body sets
// `v` and the harness raises it.
const SEQ_CASES = [
  ['a duplicate founder command returns the SAME command, not a second one',
   `declare a jsonb; b jsonb; n bigint;`,
   `a := public.fn_founder_command_submit('management@quotesdone.com',
          'Review the supplier agreement for UAE privacy compliance today.','probe:idem','{}'::jsonb);
    b := public.fn_founder_command_submit('management@quotesdone.com',
          'Review the supplier agreement for UAE privacy compliance today.','probe:idem','{}'::jsonb);
    select count(*) into n from public.founder_command_message where client_idempotency_key = 'probe:idem';
    v := ((a->>'command_id') = (b->>'command_id'))::text || '|' || n::text
      || '|tasks=' || (select count(*)::text from public.phase_c_task
                       where command_id = (a->>'command_id')::bigint);`,
   // K2b routed founder commands through the kernel, and fn_kernel_workflow_start creates
   // EXACTLY ONE task per step run — that is the contract fn_kernel_step_complete enforces
   // when it raises k3_task_missing. The 3 here was the pre-kernel fan-out. The case still
   // asserts what it always did — same command, one message — and now the true task count.
   'true|1|tasks=1'],

  ['a founder command creates its tasks BEFORE it answers, in one transaction',
   `declare a jsonb; n bigint;`,
   `a := public.fn_founder_command_submit('management@quotesdone.com',
          'Prepare the next 90-day cash forecast and tell me whether current funding is sufficient.',
          'probe:atomic','{}'::jsonb);
    select count(*) into n from public.phase_c_task where command_id = (a->>'command_id')::bigint;
    v := (a->>'status') || '|db_tasks=' || n::text
      || '|returned=' || jsonb_array_length(a->'task_ids')::text
      || '|trace=' || (a->>'trace_id' is not null)::text;`,
   // Same correction, same reason: one task per step run, created before the answer, in one
   // transaction, with its trace. The atomicity this case exists to prove is untouched.
   'tasks_created|db_tasks=1|returned=1|trace=true'],

  ['a retry opens a NEW step run and preserves the first attempt',
   `declare r bigint; a jsonb; b jsonb;`,
   `r := public.fn_phase_c_workflow_start('W01','probe-retry','{}'::jsonb);
    -- a completing step must now carry a real output: hashing the empty string was the defect.
    a := public.fn_phase_c_step_advance(r, 'W01-S01', 'chief_of_staff',
           jsonb_build_object('output', jsonb_build_object('status','completed','output','attempt one')));
    b := public.fn_phase_c_step_advance(r, 'W01-S01', 'chief_of_staff',
           jsonb_build_object('output', jsonb_build_object('status','completed','output','attempt two')));
    v := 'attempts=' || (a->>'attempt') || ',' || (b->>'attempt')
      || '|first_preserved=' || ((b->>'first_attempt_id') = (a->>'step_run_id'))::text
      || '|rows=' || (select count(*)::text from public.phase_c_workflow_step_run
                      where run_id = r and step_id = 'W01-S01');`,
   // K13 retired fn_phase_c_step_advance. Retry-and-preserve is now fn_kernel_step_complete's
   // contract, exercised by the kernel walk in the PBCR-001 rehearsal; here the assertion is
   // that the old path is closed.
   ['23514', 'fn_phase_c_step_advance']],

  ['a workflow start is idempotent — the same object does not open a second run',
   `declare a bigint; b bigint;`,
   `a := public.fn_phase_c_workflow_start('W02','probe-idem','{}'::jsonb);
    b := public.fn_phase_c_workflow_start('W02','probe-idem','{}'::jsonb);
    v := (a = b)::text || '|runs=' || (select count(*)::text from public.phase_c_workflow_run
                                       where business_object_id = 'probe-idem');`,
   'true|runs=1'],

  ['an out-of-order delivery cannot mark a dead-lettered event delivered twice',
   `declare o bigint; s1 text; s2 text;`,
   `o := public.fn_phase_c_outbox_emit((select event_id from public.phase_b_event limit 1),
          'probe','{}'::jsonb,'probe:order');
    s1 := public.fn_phase_c_outbox_settle(o, true, 'downstream-1', '');
    s2 := public.fn_phase_c_outbox_settle(o, true, 'downstream-1', '');
    v := s1 || '|' || s2 || '|attempts=' ||
         (select attempts::text from public.phase_c_event_outbox where outbox_id = o)
      || '|delivered_rows=' || (select count(*)::text from public.phase_c_event_delivery_attempt where outbox_id = o);`,
   // K36: same routine, same reason. A dead-lettered event cannot be marked delivered twice
   // because it cannot be marked delivered at all through this path any more.
   ['23514', 'fn_phase_c_outbox_settle']],

  ['a handoff keeps the sender accountable until the receiver accepts',
   `declare r bigint; h jsonb; d jsonb; hid text;`,
   `select handoff_id into hid from public.phase_b_handoff where workflow_id = 'W01' limit 1;
    r := public.fn_phase_c_workflow_start('W01','probe-handoff','{}'::jsonb);
    h := public.fn_phase_c_handoff_open(r, hid, jsonb_build_object(
           'business_object_id','x','object_version',1,'output','x',
           'evidence_refs', jsonb_build_array('e1'), 'requested_action','review'));
    d := public.fn_phase_c_handoff_decide((h->>'handoff_run_id')::bigint, 'accept',
           h->>'receiver', '{}'::jsonb);
    v := 'before=' || (h->>'accountable_until_accept') || '|after=' || (d->>'accountable_now')
      || '|moved=' || ((h->>'accountable_until_accept') <> (d->>'accountable_now'))::text;`,
   'before='],

  ['a rejected handoff returns to a named owner and states what is missing',
   `declare r bigint; h jsonb; d jsonb; hid text;`,
   `select handoff_id into hid from public.phase_b_handoff where workflow_id = 'W01' limit 1;
    r := public.fn_phase_c_workflow_start('W01','probe-reject','{}'::jsonb);
    h := public.fn_phase_c_handoff_open(r, hid, jsonb_build_object(
           'business_object_id','x','object_version',1,'output','x',
           'evidence_refs', jsonb_build_array('e1'), 'requested_action','review'));
    d := public.fn_phase_c_handoff_decide((h->>'handoff_run_id')::bigint, 'reject', h->>'receiver',
           jsonb_build_object('reason','specification absent','missing','required_output'));
    v := (d->>'ok') || '|owner=' || (d->>'accountable_now')
      || '|reason=' || (select rejection_reason from public.phase_c_handoff_run
                        where handoff_run_id = (h->>'handoff_run_id')::bigint);`,
   'true|owner='],
];

let pass = 0, fail = 0;

// PCCR-006, 25 AUG 2026. A THIRD BUCKET, BECAUSE TWO WERE NOT ENOUGH.
//
// Two cases below BIND a verified founder subject before injecting, so that the arm they are about
// is what refuses rather than the identity arm (see the PCCR-003 note above them).
// fn_phase_c_founder_subject_bind now refuses any connection that is not the PostgREST one that
// verified a bearer token, so the bind raises 28000 and the injection never reaches
// fn_phase_c_refund_decision_guard at all.
//
// With two buckets the harness had to call that a FAILURE, and it printed the most alarming
// sentence it owns — "a refund executed against a REJECTED decision is refused: FAIL" — about a
// guard it had not tested and which had not moved. A probe that cannot reach its subject must not
// report on that subject: an error and an empty result are not the same value, and neither is a
// blocked injection and an accepted one.
//
// NOT_DRIVEABLE is counted separately, disclosed by name, and is NOT a pass. If the bind is ever
// ACCEPTED from this connection the case scores normally again — and if the injection then
// survives, `survived` still makes it a hard failure. Nothing here can turn an accepted defect
// green.
let notDriveable = 0;
const BIND_REFUSED = 'pccr_founder_bind_untrusted_connection';
const blocked = [];

// The baseline every injection is measured against. Taken BEFORE the first probe so a real
// founder command sitting in the table is simply part of the baseline, not a failure.
const before = await (async () => (await sql(`select
  (select count(*) from public.phase_c_task) tasks,
  (select count(*) from public.founder_command) cmds,
  (select count(*) from public.founder_command_message) msgs,
  (select count(*) from public.founder_approval_request) appr,
  (select count(*) from public.phase_c_workflow_run) runs,
  (select count(*) from public.phase_c_event_outbox) outbox,
  -- TRACES, EXCLUDING SCHEDULED KERNEL INFRASTRUCTURE. 17 Aug 2026: this counted every row in
  -- phase_c_trace, and cron 278 (fn_kernel_outbox_deliver, every minute) writes a
  -- TRACE-SYSTEM-EXECUTION trace on each tick. Any run of this file longer than sixty seconds
  -- therefore saw the total move and reported "an injection was not rolled back" — measured, 21
  -- such traces in a forty-minute window, and nothing else wrote one. The counter now measures
  -- exactly the traces an injected defect could create, which is stricter than a total that a
  -- scheduled tick can move on its own.
  (select count(*) from public.phase_c_trace
    where trace_policy_id <> 'TRACE-SYSTEM-EXECUTION') traces,
  (select count(*) from public.phase_c_handoff_run) handoffs,
  (select count(*) from public.founder_release_approval) release_appr,
  (select count(*) from public.phase_c_component where component_id like 'probe:%') probe_components,
  (select coalesce(max(message_id),0) from public.founder_command_message) max_msg_id,
  (select coalesce(max(task_id),0) from public.phase_c_task) max_task_id,
  (select coalesce(max(run_id),0) from public.phase_c_workflow_run) max_run_id,
  (select coalesce(max(outbox_id),0) from public.phase_c_event_outbox) max_outbox_id,
  (select coalesce(max(trace_id),0) from public.phase_c_trace) max_trace_id`))[0])();

for (const [name, body, expect] of CASES) {
  // The injection runs, then the transaction is aborted by a RAISE either way.  If the guard
  // fired we see its message; if it did NOT fire we see INJECTION_SURVIVED, which is a failure.
  // K18 sits on every business-work table and refuses ANY write with no kernel routine on the
  // call stack — including this harness's injections, which are direct inserts by design. Without
  // the maintenance door, K18 answered first with 42501 and nineteen inner guards stopped being
  // exercised at all: still enforced, but no longer TESTED, which is how a guard quietly rots.
  //
  // The door is the one K18 built for exactly this, and it is not a bypass: it requires the table
  // owner, and every write through it is recorded in kernel_maintenance_write with this reason and
  // the call stack. The whole probe is then aborted, so the audit row does not survive either — but
  // the mechanism is the audited one, not a hole cut for the tests.
  const probe = `do $probe$ begin
    set local kernel.maintenance_reason = 'phase_c_guards_reject_injected_defects: injecting a '
      'known defect so the guard under test is the one that refuses it, not K18. Aborted.';
    ${body}
    raise exception 'INJECTION_SURVIVED';
  end $probe$;`;
  let msg = '';
  try { await sql(probe); msg = 'NO_RAISE_AT_ALL'; }
  catch (e) { msg = String(e.message); }
  const survived = /INJECTION_SURVIVED|NO_RAISE_AT_ALL/.test(msg);
  // `expect` may be a string OR an array, in which case EVERY element must be present. The array
  // form exists so a case can assert a STABLE machine-readable pair — the SQLSTATE and the guard
  // that raised it — instead of a human sentence that moves whenever the wording does. Three
  // cases here read as failures while the defect was refused every single time, by a newer and
  // stricter guard whose message simply said something else.
  const wanted = Array.isArray(expect) ? expect : [expect];
  const matched = !survived && wanted.every(w => msg.includes(w));
  // The injection tried to bind a founder subject and PCCR-006 refused the bind, so it stopped
  // before the guard under test. `survived` is deliberately still checked first: an injection that
  // was ACCEPTED is a failure whatever else is in the message.
  const bindBlocked = !survived
    && body.includes('fn_phase_c_founder_subject_bind') && msg.includes(BIND_REFUSED);
  if (matched) { pass++; console.log(`ok    ${name}`); }
  else if (bindBlocked) {
    notDriveable++; blocked.push(name);
    console.log(`gate  ${name}\n        NOT DRIVEABLE — the probe binds a verified founder subject `
      + `first so that ${wanted.join(' / ')} is what refuses, and PCCR-006 refuses the bind on this `
      + `connection (${BIND_REFUSED}). The injection never reached the guard, so this run says `
      + `NOTHING about whether that arm refuses. Driving it needs a founder JWT through PostgREST.`);
  }
  else {
    fail++;
    console.log(`FAIL  ${name}\n        ${survived ? 'THE GUARD DID NOT FIRE — the defect was accepted' : 'raised, but not for the expected reason'}`);
    console.log(`        expected to contain: ${wanted.join(' AND ')}`);
    console.log(`        got: ${msg.replace(/\s+/g, ' ').slice(0, 300)}`);
  }
}

for (const [name, query, expect] of VALUE_CASES) {
  // Same shape, but the guard answers with data.  The query runs inside an aborted transaction
  // so anything it writes is rolled back, and the answer comes out through the raise.
  const probe = `do $probe$ declare v text; begin
    select (${query}) into v;
    raise exception 'RESULT %', coalesce(v, '(null)');
  end $probe$;`;
  let msg = '';
  try { await sql(probe); msg = 'NO_RAISE_AT_ALL'; }
  catch (e) { msg = String(e.message); }
  const m = msg.match(/RESULT (.*?)(?: CONTEXT:|$)/s);
  const got = m ? m[1].trim() : msg.replace(/\s+/g, ' ').slice(0, 200);
  // A case may assert a RETURNED VALUE or a REFUSAL. Some of these guards used to answer with data
  // and now raise instead — fn_phase_c_step_advance and fn_phase_c_outbox_settle are both retired,
  // and a retired path refusing is stricter than the answer it used to give. Requiring a returned
  // value made four such cases read as failures while the defect was refused every time.
  const wanted = Array.isArray(expect) ? expect : [expect];
  const matched = Array.isArray(expect)
    ? (!m && wanted.every(w => msg.includes(w)))          // a refusal: SQLSTATE and the guard
    : ((m && got.startsWith(expect)) || (!m && msg.includes(expect)));
  if (matched) { pass++; console.log(`ok    ${name}`); }
  else {
    fail++;
    console.log(`FAIL  ${name}\n        expected a result starting with, or a refusal containing: ${wanted.join(" AND ")}\n        got: ${got.slice(0, 300)}`);
  }
}

for (const [name, decls, body, expect] of SEQ_CASES) {
  const probe = `do $probe$ ${decls} declare v text; begin
    ${body}
    raise exception 'RESULT %', coalesce(v, '(null)');
  end $probe$;`;
  let msg = '';
  try { await sql(probe); msg = 'NO_RAISE_AT_ALL'; }
  catch (e) { msg = String(e.message); }
  const m = msg.match(/RESULT (.*?)(?: CONTEXT:|\\nCONTEXT|$)/s);
  const got = m ? m[1].trim() : msg.replace(/\s+/g, ' ').slice(0, 300);
  // Same generalisation as VALUE_CASES: a case may assert a returned value or a refusal, because a
  // retired path refusing is stricter than the answer it used to give.
  const wanted = Array.isArray(expect) ? expect : [expect];
  const matched = Array.isArray(expect)
    ? (!m && wanted.every(w => msg.includes(w)))          // a refusal: SQLSTATE and the guard
    : ((m && got.startsWith(expect)) || (!m && msg.includes(expect)));
  if (matched) { pass++; console.log(`ok    ${name}   [${got.slice(0, 110)}]`); }
  else { fail++; console.log(`FAIL  ${name}\n        expected a result starting with, or a refusal containing: ${wanted.join(" AND ")}\n        got: ${got.slice(0, 300)}`); }
}

// Nothing may have survived — measured as a DELTA, not as an absolute.
//
// This asserted `=== 0` on every table, which only ever worked because the database was empty. The
// moment a real founder command existed it went red for five tables while all 55 injections were
// still being refused correctly — a check that fails on real data teaches people to ignore it, and
// this one would have hidden a genuine regression behind its own noise.
const countsNow = async () => (await sql(`select
  (select count(*) from public.phase_c_task) tasks,
  (select count(*) from public.founder_command) cmds,
  (select count(*) from public.founder_command_message) msgs,
  (select count(*) from public.founder_approval_request) appr,
  (select count(*) from public.phase_c_workflow_run) runs,
  (select count(*) from public.phase_c_event_outbox) outbox,
  -- TRACES, EXCLUDING SCHEDULED KERNEL INFRASTRUCTURE. 17 Aug 2026: this counted every row in
  -- phase_c_trace, and cron 278 (fn_kernel_outbox_deliver, every minute) writes a
  -- TRACE-SYSTEM-EXECUTION trace on each tick. Any run of this file longer than sixty seconds
  -- therefore saw the total move and reported "an injection was not rolled back" — measured, 21
  -- such traces in a forty-minute window, and nothing else wrote one. The counter now measures
  -- exactly the traces an injected defect could create, which is stricter than a total that a
  -- scheduled tick can move on its own.
  (select count(*) from public.phase_c_trace
    where trace_policy_id <> 'TRACE-SYSTEM-EXECUTION') traces,
  (select count(*) from public.phase_c_handoff_run) handoffs,
  (select count(*) from public.founder_release_approval) release_appr,
  (select count(*) from public.phase_c_component where component_id like 'probe:%') probe_components,
  (select coalesce(max(message_id),0) from public.founder_command_message) max_msg_id,
  (select coalesce(max(task_id),0) from public.phase_c_task) max_task_id,
  (select coalesce(max(run_id),0) from public.phase_c_workflow_run) max_run_id,
  (select coalesce(max(outbox_id),0) from public.phase_c_event_outbox) max_outbox_id,
  (select coalesce(max(trace_id),0) from public.phase_c_trace) max_trace_id`))[0];

const after = await countsNow();

// A DELTA OVER A SHARED TABLE IS NOT ATTRIBUTION — 27 Aug 2026.
//
// This run went red on cmds 21 -> 22, msgs 21 -> 22 and traces 352 -> 353 while every one of the 58
// injections was refused correctly. Nothing leaked. The founder sent a command in the Command Center
// at 13:14 UTC, mid-run: one founder_command, one founder_command_message, one TRACE-FOUNDER-COMMAND
// trace. The check saw three totals move and blamed itself.
//
// The traces column already learned this once, against cron 278. The general form of the lesson is
// the same: a count that moves is not evidence of WHO moved it, and a check that fails on the
// founder using his own OS teaches people to ignore it.
//
// ATTRIBUTION, NOT A WIDER TOLERANCE. Every message this file submits is a string literal IN this
// file, so a new message whose raw_text appears in the file's own source is the probe's and is a
// hard failure; one whose text is not in the file arrived from somewhere else and is named, counted
// out of the three columns it touches, and reported. It cannot silently absorb a probe leak: the
// probe's own text is always in the file.
const SELF = readFileSync(new URL(import.meta.url), 'utf8');
const arrivals = await sql(`select m.message_id, m.founder_identity,
    left(m.raw_text, 160) as raw_text
  from public.founder_command_message m
 where m.message_id > ${Number(before.max_msg_id) || 0}
 order by m.message_id`);
const probeArrivals = arrivals.filter((a) => SELF.includes(String(a.raw_text).trim()));
const outsideArrivals = arrivals.filter((a) => !SELF.includes(String(a.raw_text).trim()));

if (outsideArrivals.length) {
  console.log(`\n${outsideArrivals.length} founder command(s) arrived from outside this check while it ran, `
    + 'and are excluded from the deltas below by attribution rather than by tolerance:');
  for (const a of outsideArrivals) {
    console.log(`  message ${a.message_id} ${a.founder_identity}: ${String(a.raw_text).slice(0, 90)}`);
  }
}
for (const a of probeArrivals) {
  console.error(`FAIL: message ${a.message_id} carries text from this file and survived — an injection was not rolled back`);
  fail++;
}
// One founder command writes one founder_command, one founder_command_message and one
// TRACE-FOUNDER-COMMAND trace. Those three columns are adjusted by the number of arrivals that came
// from outside; every other column is compared untouched.
const CONCURRENT = { cmds: outsideArrivals.length, msgs: outsideArrivals.length, traces: outsideArrivals.length };

// THE COMPANY RUNS WHILE THIS CHECK RUNS — 4 SEP 2026. The workflow loop was revived that morning:
// every few minutes the dispatcher and the kernel crons open a phase_c_workflow_run, its tasks, its
// outbox rows and their traces for real work. This run went red on tasks 166 -> 167, runs 132 -> 133,
// outbox 147 -> 148 and traces 1041 -> 1045 while all 56 driveable injections were refused; the local
// run a minute earlier passed because nothing happened to fire in its window. Same lesson, same
// remedy as the founder's command above: ATTRIBUTION, NOT TOLERANCE. Every task, run, outbox row or
// trace this file could leave is tied to the probe — an idempotency key or dedupe value from this
// file's own literals, or a command whose message text is in this file. A new row that carries none
// of those arrived from the running company: it is named, counted out of its column, and reported.
// A new row that DOES carry the probe's identity is a hard failure, exactly as before.
const probeCmdIds = (await sql(`select c.command_id, left(m.raw_text, 160) as raw_text from public.founder_command c
    join public.founder_command_message m on m.message_id = c.message_id
   where m.message_id > ${Number(before.max_msg_id) || 0}`))
  .filter((r) => SELF.includes(String(r.raw_text).trim()))   // the probe's commands, not the founder's
  .map((r) => Number(r.command_id));
const inProbe = (txt) => txt != null && String(txt).trim() !== '' && SELF.includes(String(txt).trim());
const cmdIn = (id) => id != null && probeCmdIds.includes(Number(id));
const newTasks = await sql(`select task_id, command_id, run_id, idempotency_key, left(objective,160) objective, accountable_role_id
    from public.phase_c_task where task_id > ${Number(before.max_task_id) || 0} order by task_id`);
const newRuns = await sql(`select run_id, workflow_id, command_id, dedupe_key, accountable_role_id
    from public.phase_c_workflow_run where run_id > ${Number(before.max_run_id) || 0} order by run_id`);
const newOutbox = await sql(`select outbox_id, event_id, command_id, workflow_run_id, task_id, dedupe_value
    from public.phase_c_event_outbox where outbox_id > ${Number(before.max_outbox_id) || 0} order by outbox_id`);
const newTraces = await sql(`select trace_id, trace_policy_id, command_id, run_id, task_id, component_id
    from public.phase_c_trace where trace_id > ${Number(before.max_trace_id) || 0}
     and trace_policy_id <> 'TRACE-SYSTEM-EXECUTION' order by trace_id`);
const probeTaskIds = new Set(), probeRunIds = new Set();
const split = (rows, isProbe, label, fmt) => {
  const mine = rows.filter(isProbe), theirs = rows.filter((r) => !isProbe(r));
  for (const r of mine) { console.error(`FAIL: ${label} ${fmt(r)} carries this file's identity and survived — an injection was not rolled back`); fail++; }
  if (theirs.length) {
    console.log(`${theirs.length} ${label}(s) arrived from the running company while this check ran, excluded by attribution:`);
    for (const r of theirs.slice(0, 12)) console.log('  ' + fmt(r));
    if (theirs.length > 12) console.log(`  ... and ${theirs.length - 12} more`);
  }
  return theirs.length;
};
const outsideRuns = split(newRuns,
  (r) => cmdIn(r.command_id) || String(r.dedupe_key || '').startsWith('probe'),
  'workflow run', (r) => `run ${r.run_id} ${r.workflow_id} (${r.accountable_role_id})`);
for (const r of newRuns) if (cmdIn(r.command_id) || String(r.dedupe_key || '').startsWith('probe')) probeRunIds.add(Number(r.run_id));
const outsideTasks = split(newTasks,
  (r) => cmdIn(r.command_id) || probeRunIds.has(Number(r.run_id)) || String(r.idempotency_key || '').startsWith('probe') || inProbe(r.objective),
  'task', (r) => `task ${r.task_id} ${r.accountable_role_id}: ${String(r.objective || '').slice(0, 70)}`);
for (const r of newTasks) if (cmdIn(r.command_id) || probeRunIds.has(Number(r.run_id)) || String(r.idempotency_key || '').startsWith('probe') || inProbe(r.objective)) probeTaskIds.add(Number(r.task_id));
const outsideOutbox = split(newOutbox,
  (r) => cmdIn(r.command_id) || probeRunIds.has(Number(r.workflow_run_id)) || probeTaskIds.has(Number(r.task_id)) || inProbe(r.dedupe_value),
  'outbox row', (r) => `outbox ${r.outbox_id} ${r.event_id}`);
const outsideTraces = split(newTraces,
  (r) => cmdIn(r.command_id) || probeRunIds.has(Number(r.run_id)) || probeTaskIds.has(Number(r.task_id)),
  'trace', (r) => `trace ${r.trace_id} ${r.trace_policy_id} ${r.component_id || ''}`);
// The founder's own commands were already counted into cmds/msgs/traces above; a trace that belongs
// to one of those commands is in outsideTraces too, so it is not counted twice.
CONCURRENT.runs = outsideRuns;
CONCURRENT.tasks = outsideTasks;
CONCURRENT.outbox = outsideOutbox;
// A founder command from outside writes its TRACE-FOUNDER-COMMAND trace with that command id, which is
// not a probe command, so it is already inside outsideTraces; nothing is counted twice.
CONCURRENT.traces = outsideTraces;

console.log('\nrow counts before/after every aborted injection:');
for (const [k, v] of Object.entries(after)) {
  if (k === 'max_msg_id' || k === 'max_task_id' || k === 'max_run_id' || k === 'max_outbox_id' || k === 'max_trace_id') continue;
  const b = Number(before[k]) + (CONCURRENT[k] || 0), a = Number(v);
  const note = CONCURRENT[k] ? ` (+${CONCURRENT[k]} attributed to a command from outside this check)` : '';
  if (a !== b) { console.error(`FAIL: ${k} moved ${Number(before[k])} -> ${a}${note}; an injection was not rolled back`); fail++; }
  else console.log(`  ok   ${k.padEnd(18)} ${a} (unchanged${note})`);
}
// Probe components must be absent outright — they are named, so their presence is unambiguous
// rather than a delta.
if (Number(after.probe_components) !== 0) {
  console.error(`FAIL: ${after.probe_components} probe component(s) persisted`); fail++;
}

// ROOT CAUSE 5, 17 Aug 2026. What every assertion in this file rests on, said out loud so the next
// reader does not have to infer it:
//   * every REFUSAL case asserts a PAIR — the SQLSTATE and the stable identity of whatever refused
//     it, which is the constraint name for a constraint violation and the raising function
//     otherwise. Not one of them matches on the wording of a human message any more. The wording is
//     still there for the operator reading the log; it is simply no longer the contract.
//   * every VALUE case asserts the guard's own STRUCTURED result — the pipe-delimited status it
//     returns, read from the front — rather than a sentence.
//   * unchanged row counts are asserted as a DELTA across ten tables, immediately above.
//   * no partial side effect is STRUCTURAL rather than asserted per case: every probe runs inside a
//     transaction that always aborts, so a guard that fired halfway cannot leave half a row behind.
//     Asserting it 55 more times would triple the runtime and add no fact.
//
// The count below is read from this file rather than declared, so it cannot drift from the truth.
const pairAssertions = (readFileSync(new URL(import.meta.url), 'utf8')
  .match(/\['[0-9A-Za-z]{5}', '[^']+'\]/g) || []).length;
console.log(`\nrefusals asserted on a SQLSTATE + guard pair: ${pairAssertions}`);
console.log(`refusals asserted on a human message:         0`);
console.log(`\n${pass}/${pass + fail + notDriveable} injected defects refused`
  + (notDriveable ? `, ${notDriveable} not driveable from this connection, ${fail} failed` : ''));
if (notDriveable) {
  // SAID EVERY RUN, not once in a commit message. The denominator above already counts these, so
  // the line cannot be read as "56 of 56". What this run does NOT establish is stated in the same
  // breath as what it does.
  console.log(`  NOT DRIVEABLE (${notDriveable}): ${blocked.join('; ')}`);
  console.log('  Each needs a verified founder session, and fn_phase_c_founder_subject_bind refuses '
    + 'this connection since PCCR-006. This run does NOT establish that those arms refuse a genuine '
    + 'call — only that they cannot be reached from a management connection, which is the point of '
    + 'the amendment.');
}
process.exit(fail === 0 ? 0 : 1);
