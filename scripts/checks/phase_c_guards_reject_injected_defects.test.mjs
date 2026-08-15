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
import { existsSync } from 'node:fs';
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
   'does not resolve to an active canonical role'],

  ['an INACTIVE role may not own a task',
   `insert into public.phase_c_task (source_kind, source_ref, accountable_role_id, objective,
      acceptance_criteria, closure_criteria, authority_class, idempotency_key)
    select 'probe','probe', r.role_id, 'x','x','x','routine_operational_decision','probe:2'
    from public.org_role r where r.status <> 'active' limit 1;`,
   'does not resolve to an active canonical role'],

  ['a category overlay may not own a task',
   `insert into public.phase_c_task (source_kind, source_ref, accountable_role_id, objective,
      acceptance_criteria, closure_criteria, authority_class, idempotency_key)
    select 'probe','probe', r.role_id, 'x','x','x','routine_operational_decision','probe:3'
    from public.org_role r where r.status='active' and r.runtime_mode='knowledge_overlay' limit 1;`,
   'may advise but may never own a task'],

  ['a generic name may not be a component owner',
   `insert into public.phase_c_component (component_id, component_type, source_path_or_db_object,
      mutates_state, canonical_system_actor, accountable_role_id, workflow_id, authority_class,
      trace_policy_id, idempotency_strategy, retry_policy, activation_state, classification)
    values ('probe:generic','edge_function','probe', true, 'system.task_engine','Director','W01',
            'routine_operational_decision','TRACE-SYSTEM-EXECUTION','x','x','deployed','CANONICAL_KEEP');`,
   'phase_c_component_no_generic_owner_ck'],

  ['an active state-changing component may not be unowned',
   `alter table public.phase_c_component drop constraint if exists probe_noop;
    insert into public.phase_c_component (component_id, component_type, source_path_or_db_object,
      mutates_state, canonical_system_actor, accountable_role_id, workflow_id, authority_class,
      trace_policy_id, idempotency_strategy, retry_policy, activation_state, classification)
    values ('probe:unowned','edge_function','probe', true, 'system.task_engine','ceo','',
            'routine_operational_decision','TRACE-SYSTEM-EXECUTION','x','x','deployed','CANONICAL_KEEP');`,
   'phase_c_component_accountable_ck'],

  ['an unknown classification is refused',
   `insert into public.phase_c_component (component_id, component_type, source_path_or_db_object,
      mutates_state, canonical_system_actor, accountable_role_id, workflow_id, authority_class,
      trace_policy_id, idempotency_strategy, retry_policy, activation_state, classification)
    values ('probe:cls','edge_function','probe', true, 'system.task_engine','ceo','W01',
            'routine_operational_decision','TRACE-SYSTEM-EXECUTION','x','x','deployed','PROBABLY_FINE');`,
   'phase_c_component_classification_ck'],

  // ---------------------------------------------------------------- founder autonomy
  ['a NON-REFUND founder approval request is refused',
   `insert into public.founder_approval_request (action_class, subject_ref, prepared_by_role_id)
    values ('production_release','probe','ceo');`,
   'founder_approval_request'],

  ['a second founder-approval action class is refused',
   `update public.phase_c_action_class set founder_approval_required = true
     where action_class = 'production_release';`,
   'phase_c_action_class_single_founder_approval_uk'],

  ['a NEW founder release approval is refused',
   `insert into public.founder_release_approval (approved_by, release_ref, scope, evidence)
    values ('management@quotesdone.com','probe','probe','probe');`,
   'is not an approval path any more'],

  ['a NEW procurement approval request is refused',
   `insert into public.procurement_approval_request (entity_type, entity_id, status)
    values ('probe','probe','pending');`,
   'is not an approval path any more'],

  ['a refund decided by someone other than the founder is refused',
   `insert into public.founder_approval_request (action_class, subject_ref, prepared_by_role_id)
      values ('refund_decision','TX-PROBE','payments_and_billing_manager');
    insert into public.phase_c_refund_decision (request_id, decided_by, decision)
      select request_id, 'chief_of_staff', 'approved' from public.founder_approval_request
      where subject_ref = 'TX-PROBE';`,
   'is not the registered founder identity'],

  ['a refund executed against a REJECTED decision is refused',
   `insert into public.founder_approval_request (action_class, subject_ref, prepared_by_role_id)
      values ('refund_decision','TX-PROBE2','payments_and_billing_manager');
    insert into public.phase_c_refund_decision (request_id, decided_by, decision, executed_at)
      select request_id, 'management@quotesdone.com', 'rejected', now()
      from public.founder_approval_request where subject_ref = 'TX-PROBE2';`,
   'execution recorded against a rejected decision'],

  ['a refund whose executor is also its reconciler is refused',
   `insert into public.founder_approval_request (action_class, subject_ref, prepared_by_role_id)
      values ('refund_decision','TX-PROBE3','payments_and_billing_manager');
    insert into public.phase_c_refund_decision (request_id, decided_by, decision,
      executor_role_id, reconciler_role_id)
      select request_id, 'management@quotesdone.com', 'approved',
             'payments_and_billing_manager','payments_and_billing_manager'
      from public.founder_approval_request where subject_ref = 'TX-PROBE3';`,
   'phase_c_refund_decision_ck'],

  // ---------------------------------------------------------------- review independence
  ['a task whose reviewer is its own owner is refused',
   `insert into public.phase_c_task (source_kind, source_ref, accountable_role_id, objective,
      acceptance_criteria, closure_criteria, authority_class, idempotency_key,
      reviewer_required, reviewer_role_id)
    values ('probe','probe','ceo','x','x','x','routine_operational_decision','probe:4', true, 'ceo');`,
   'is not independent of owner'],

  ['a task reviewed by an ALIAS of its own owner is refused',
   `insert into public.phase_c_task (source_kind, source_ref, accountable_role_id, objective,
      acceptance_criteria, closure_criteria, authority_class, idempotency_key,
      reviewer_required, reviewer_role_id)
    select 'probe','probe', a.role_id, 'x','x','x','routine_operational_decision','probe:5', true, a.alias
    from public.org_role_alias a
    join public.org_role r on r.role_id = a.role_id
    where r.status='active' and r.runtime_mode <> 'knowledge_overlay' limit 1;`,
   'is not independent of owner'],

  // ---------------------------------------------------------------- state models
  ['an invalid workflow transition is refused',
   `insert into public.phase_c_workflow_run (workflow_id, business_object_id, start_event,
      accountable_role_id, state, dedupe_key)
      values ('W01','probe','probe','ceo','queued','probe:wf:1');
    update public.phase_c_workflow_run set state = 'completed' where dedupe_key = 'probe:wf:1';`,
   'is not in the frozen Phase B state model'],

  ['an invalid task transition is refused',
   `insert into public.phase_c_task (source_kind, source_ref, accountable_role_id, objective,
      acceptance_criteria, closure_criteria, authority_class, idempotency_key)
      values ('probe','probe','ceo','x','x','x','routine_operational_decision','probe:6');
    update public.phase_c_task set state = 'completed' where idempotency_key = 'probe:6';`,
   'is not in the Phase C task state model'],

  ['a founder command may not jump states',
   `do $inner$
    declare v jsonb;
    begin
      v := public.fn_founder_command_submit('management@quotesdone.com',
             'Prepare the next 90-day cash forecast by Friday.','probe:cmdstate','{}'::jsonb);
      update public.founder_command set state = 'received' where command_id = (v->>'command_id')::bigint;
    end $inner$;`,
   'is not in the Phase C command state model'],

  // ---------------------------------------------------------------- handoffs
  ['a handoff that flips ownership before acceptance is refused',
   `insert into public.phase_c_handoff_run (handoff_id, sending_role_id, receiving_role_id,
      packet_hash, accountable_until_accept_role_id)
    select h.handoff_id, h.sending_role_id, h.receiving_role_id, 'probe', h.receiving_role_id
    from public.phase_b_handoff h limit 1;`,
   'sender retains accountability until acceptance'],

  ['a rejected handoff with no reason is refused',
   `insert into public.phase_c_handoff_run (handoff_id, sending_role_id, receiving_role_id,
      packet_hash, accountable_until_accept_role_id, status)
    select h.handoff_id, h.sending_role_id, h.receiving_role_id, 'probe', h.sending_role_id, 'rejected'
    from public.phase_b_handoff h limit 1;`,
   'phase_c_handoff_run_reject_ck'],

  // ---------------------------------------------------------------- traces
  ['a sealed trace cannot be edited',
   `insert into public.phase_c_trace (trace_policy_id, subject_kind, subject_ref, status, sealed_at)
      values ('TRACE-TASK','probe','probe','sealed', now());
    update public.phase_c_trace set status = 'rewritten'
      where subject_ref = 'probe' and subject_kind = 'probe';`,
   'sealed trace evidence is append-only'],

  ['a trace under an unknown policy is refused',
   `select public.fn_phase_c_trace_write('TRACE-INVENTED', '{"subject_kind":"probe"}'::jsonb);`,
   'unknown trace policy'],

  // ---------------------------------------------------------------- idempotency
  ['a duplicate task idempotency key is refused',
   `insert into public.phase_c_task (source_kind, source_ref, accountable_role_id, objective,
      acceptance_criteria, closure_criteria, authority_class, idempotency_key)
      values ('probe','probe','ceo','x','x','x','routine_operational_decision','probe:dup');
    insert into public.phase_c_task (source_kind, source_ref, accountable_role_id, objective,
      acceptance_criteria, closure_criteria, authority_class, idempotency_key)
      values ('probe','probe','cfo','x','x','x','routine_operational_decision','probe:dup');`,
   'phase_c_task_idem_uk'],

  ['a duplicate founder message idempotency key is refused',
   `insert into public.founder_command_message (founder_identity, raw_text, raw_text_hash, client_idempotency_key)
      values ('management@quotesdone.com','probe','h','probe:msgdup');
    insert into public.founder_command_message (founder_identity, raw_text, raw_text_hash, client_idempotency_key)
      values ('management@quotesdone.com','probe again','h','probe:msgdup');`,
   'founder_command_message_idem_uk'],

  ["the founder's own words cannot be edited",
   `insert into public.founder_command_message (founder_identity, raw_text, raw_text_hash, client_idempotency_key)
      values ('management@quotesdone.com','probe','h','probe:immutable');
    update public.founder_command_message set raw_text = 'something else'
      where client_idempotency_key = 'probe:immutable';`,
   'append-only'],

  ['an unknown canonical event cannot be emitted',
   `select public.fn_phase_c_outbox_emit('EV-INVENTED','probe','{}'::jsonb,'probe');`,
   'unknown canonical event'],

  ['an unknown workflow cannot be started',
   `select public.fn_phase_c_workflow_start('W99','probe','{}'::jsonb);`,
   'unknown workflow'],
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
   'retry_wait'],
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
  ['the wrong employee cannot advance a frozen step',
   `select public.fn_phase_c_step_advance(
      public.fn_phase_c_workflow_start('W01','probe-step','{}'::jsonb),
      'W01-S02','chief_of_staff','{}'::jsonb)->>'error'`,
   'not_the_accountable_owner'],
  ['an overlay outside its declared scope cannot own a step',
   `select public.fn_phase_c_step_owner_valid('W01-S01','category_overlay_004_formwork-and-scaffolding-suppliers')::text`,
   'false'],
  ['the ONE frozen overlay-owned analysis step is permitted',
   `select public.fn_phase_c_step_owner_valid('W14-S05','relevant_category_overlay')::text`,
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
   'true|1|tasks=3'],

  ['a founder command creates its tasks BEFORE it answers, in one transaction',
   `declare a jsonb; n bigint;`,
   `a := public.fn_founder_command_submit('management@quotesdone.com',
          'Prepare the next 90-day cash forecast and tell me whether current funding is sufficient.',
          'probe:atomic','{}'::jsonb);
    select count(*) into n from public.phase_c_task where command_id = (a->>'command_id')::bigint;
    v := (a->>'status') || '|db_tasks=' || n::text
      || '|returned=' || jsonb_array_length(a->'task_ids')::text
      || '|trace=' || (a->>'trace_id' is not null)::text;`,
   'tasks_created|db_tasks=3|returned=3|trace=true'],

  ['a retry opens a NEW step run and preserves the first attempt',
   `declare r bigint; a jsonb; b jsonb;`,
   `r := public.fn_phase_c_workflow_start('W01','probe-retry','{}'::jsonb);
    a := public.fn_phase_c_step_advance(r, 'W01-S01', 'chief_of_staff', '{}'::jsonb);
    b := public.fn_phase_c_step_advance(r, 'W01-S01', 'chief_of_staff', '{}'::jsonb);
    v := 'attempts=' || (a->>'attempt') || ',' || (b->>'attempt')
      || '|first_preserved=' || ((b->>'first_attempt_id') = (a->>'step_run_id'))::text
      || '|rows=' || (select count(*)::text from public.phase_c_workflow_step_run
                      where run_id = r and step_id = 'W01-S01');`,
   'attempts=1,2|first_preserved=true|rows=2'],

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
   'delivered|delivered|attempts=0|delivered_rows=2'],

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

// The baseline every injection is measured against. Taken BEFORE the first probe so a real
// founder command sitting in the table is simply part of the baseline, not a failure.
const before = await (async () => (await sql(`select
  (select count(*) from public.phase_c_task) tasks,
  (select count(*) from public.founder_command) cmds,
  (select count(*) from public.founder_command_message) msgs,
  (select count(*) from public.founder_approval_request) appr,
  (select count(*) from public.phase_c_workflow_run) runs,
  (select count(*) from public.phase_c_event_outbox) outbox,
  (select count(*) from public.phase_c_trace) traces,
  (select count(*) from public.phase_c_handoff_run) handoffs,
  (select count(*) from public.founder_release_approval) release_appr,
  (select count(*) from public.phase_c_component where component_id like 'probe:%') probe_components`))[0])();

for (const [name, body, expect] of CASES) {
  // The injection runs, then the transaction is aborted by a RAISE either way.  If the guard
  // fired we see its message; if it did NOT fire we see INJECTION_SURVIVED, which is a failure.
  const probe = `do $probe$ begin
    ${body}
    raise exception 'INJECTION_SURVIVED';
  end $probe$;`;
  let msg = '';
  try { await sql(probe); msg = 'NO_RAISE_AT_ALL'; }
  catch (e) { msg = String(e.message); }
  const survived = /INJECTION_SURVIVED|NO_RAISE_AT_ALL/.test(msg);
  const matched = !survived && msg.includes(expect);
  if (matched) { pass++; console.log(`ok    ${name}`); }
  else {
    fail++;
    console.log(`FAIL  ${name}\n        ${survived ? 'THE GUARD DID NOT FIRE — the defect was accepted' : 'raised, but not for the expected reason'}`);
    console.log(`        expected to contain: ${expect}`);
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
  const matched = m && got.startsWith(expect);
  if (matched) { pass++; console.log(`ok    ${name}`); }
  else {
    fail++;
    console.log(`FAIL  ${name}\n        expected to start with: ${expect}\n        got: ${got.slice(0, 300)}`);
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
  const matched = m && got.startsWith(expect);
  if (matched) { pass++; console.log(`ok    ${name}   [${got.slice(0, 110)}]`); }
  else { fail++; console.log(`FAIL  ${name}\n        expected to start with: ${expect}\n        got: ${got.slice(0, 300)}`); }
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
  (select count(*) from public.phase_c_trace) traces,
  (select count(*) from public.phase_c_handoff_run) handoffs,
  (select count(*) from public.founder_release_approval) release_appr,
  (select count(*) from public.phase_c_component where component_id like 'probe:%') probe_components`))[0];

const after = await countsNow();
console.log('\nrow counts before/after every aborted injection:');
for (const [k, v] of Object.entries(after)) {
  const b = Number(before[k]), a = Number(v);
  if (a !== b) { console.error(`FAIL: ${k} moved ${b} -> ${a}; an injection was not rolled back`); fail++; }
  else console.log(`  ok   ${k.padEnd(18)} ${a} (unchanged)`);
}
// Probe components must be absent outright — they are named, so their presence is unambiguous
// rather than a delta.
if (Number(after.probe_components) !== 0) {
  console.error(`FAIL: ${after.probe_components} probe component(s) persisted`); fail++;
}

console.log(`\n${pass}/${pass + fail} injected defects refused`);
process.exit(fail === 0 ? 0 : 1);
