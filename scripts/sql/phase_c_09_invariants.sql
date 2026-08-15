-- Phase C — the deterministic invariants, and the Phase C baseline drift function.
--
-- PHASE_C_INVARIANTS.md says "Phase C is ready only when every mandatory invariant returns zero
-- violations".  This file is that sentence made executable.  Two rules shaped it:
--
--   * A check that passes when the thing it checks is broken is worse than no check.  Several
--     of these are therefore HARDER than the obvious version — for example the binding checks
--     re-read the routine named in each binding row out of pg_proc, so a CSV that names a
--     function which was never deployed fails here instead of reading as connected.
--
--   * A count is not a measurement of the thing its name claims.  The founder-approval
--     invariant counts what is WAITING for him and is not a refund, not the historical record
--     of an approval he has already given; the boundary is stated in phase_c_02 §6 and the two
--     are deliberately not summed.
--
-- scripts/sql is append-only.  To change any of this, add a new file.

set lock_timeout = '8s';
set statement_timeout = '600s';

create or replace function public.fn_phase_c_invariants()
returns table (check_name text, expected text, actual text, ok boolean)
language plpgsql stable set search_path to 'public', 'pg_temp' as $$
declare
  v_deployed text[];
begin
  -- every routine any binding row names, so a binding cannot claim an undeployed function
  select array_agg(distinct p.proname) into v_deployed
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname like 'fn_phase_c%' or p.proname like 'fn_founder_command%';

  -- ---------------------------------------------------------------- frozen baseline
  check_name := 'phase_a_drift'; expected := '0';
  actual := (select count(*)::text from public.fn_phase_a_baseline_drift());
  ok := actual = expected; return next;

  check_name := 'phase_b_drift'; expected := '0';
  actual := (select count(*)::text from public.fn_phase_b_baseline_drift());
  ok := actual = expected; return next;

  check_name := 'phase_b_unresolved_errata'; expected := '0';
  actual := (select count(*)::text from public.fn_phase_b_effective_errata() where not resolved);
  ok := actual = expected; return next;

  check_name := 'active_departments'; expected := '10';
  actual := (select count(*)::text from public.org_departments where active);
  ok := actual = expected; return next;

  check_name := 'canonical_roles'; expected := '90';
  actual := (select count(*)::text from public.org_role where status='active' and runtime_mode <> 'knowledge_overlay');
  ok := actual = expected; return next;

  check_name := 'category_overlays'; expected := '86';
  actual := (select count(*)::text from public.org_role where status='active' and runtime_mode = 'knowledge_overlay');
  ok := actual = expected; return next;

  -- ---------------------------------------------------------------- binding coverage
  check_name := 'roles_bound'; expected := '90';
  actual := (select count(*)::text from public.phase_c_role_binding where connection_status = 'CONNECTED');
  ok := actual = expected; return next;

  check_name := 'roles_without_binding'; expected := '0';
  actual := (select count(*)::text from public.org_role r
             where r.status='active' and r.runtime_mode <> 'knowledge_overlay'
               and not exists (select 1 from public.phase_c_role_binding b
                               where b.canonical_role_id = r.role_id
                                  or b.canonical_role_id in (select alias from public.org_role_alias a where a.role_id = r.role_id)));
  ok := actual = expected; return next;

  check_name := 'overlays_bound'; expected := '86';
  actual := (select count(*)::text from public.phase_c_overlay_binding where connection_status = 'CONNECTED');
  ok := actual = expected; return next;

  check_name := 'overlay_bindings_resolve'; expected := '0';
  actual := (select count(*)::text from public.phase_c_overlay_binding b
             where not exists (select 1 from public.org_role r
                               where r.role_id = b.live_role_id and r.status='active'
                                 and r.runtime_mode='knowledge_overlay'));
  ok := actual = expected; return next;

  check_name := 'workflows_bound'; expected := '30';
  actual := (select count(*)::text from public.phase_c_workflow_binding);
  ok := actual = expected; return next;

  check_name := 'workflows_without_binding'; expected := '0';
  actual := (select count(*)::text from public.phase_b_workflow w
             where not exists (select 1 from public.phase_c_workflow_binding b where b.workflow_id = w.workflow_id));
  ok := actual = expected; return next;

  check_name := 'steps_bound_or_classified'; expected := '257';
  actual := (select count(*)::text from public.phase_c_step_binding);
  ok := actual = expected; return next;

  check_name := 'steps_without_binding'; expected := '0';
  actual := (select count(*)::text from public.phase_b_workflow_step s
             where not exists (select 1 from public.phase_c_step_binding b where b.step_id = s.step_id));
  ok := actual = expected; return next;

  -- A deferral is only acceptable with an owner, a safe entry boundary and the Phase D work.
  check_name := 'deferred_steps_without_owner_or_action'; expected := '0';
  actual := (select count(*)::text from public.phase_c_step_binding
             where connection_status = 'DEFERRED_RUNTIME_IMPLEMENTATION'
               and (accountable_role_id = '' or canonical_runtime_handler = '' or phase_d_action = ''));
  ok := actual = expected; return next;

  -- "Resolves" here means the FROZEN Phase B rule, not the narrower "is a standing employee":
  -- exactly one of the 257 steps (W14-S05, an analysis step in W14) is owned by the
  -- relevant_category_overlay placeholder, which master spec §12 permits for an analysis step in
  -- W05/W06/W07/W10/W14.  fn_phase_c_step_owner_valid encodes that and nothing wider; the
  -- absolute "an overlay may never own a TASK" guard is separate and unchanged.
  check_name := 'step_owners_resolve'; expected := '0';
  actual := (select count(*)::text from public.phase_c_step_binding b
             where not public.fn_phase_c_step_owner_valid(b.step_id, b.accountable_role_id));
  ok := actual = expected; return next;

  check_name := 'steps_owned_by_overlay_outside_declared_scope'; expected := '0';
  actual := (select count(*)::text from public.phase_c_step_binding b
             join public.phase_b_workflow_step s on s.step_id = b.step_id
             where not public.fn_phase_c_actor_may_own(b.accountable_role_id)
               and not (s.step_type = 'analysis' and s.workflow_id in ('W05','W06','W07','W10','W14')));
  ok := actual = expected; return next;

  check_name := 'handoffs_bound'; expected := '161';
  actual := (select count(*)::text from public.phase_c_handoff_binding);
  ok := actual = expected; return next;

  check_name := 'handoffs_without_binding'; expected := '0';
  actual := (select count(*)::text from public.phase_b_handoff h
             where not exists (select 1 from public.phase_c_handoff_binding b where b.handoff_id = h.handoff_id));
  ok := actual = expected; return next;

  check_name := 'events_classified'; expected := '347';
  actual := (select count(*)::text from public.phase_c_event_binding);
  ok := actual = expected; return next;

  check_name := 'events_without_producer_or_consumer'; expected := '0';
  actual := (select count(*)::text from public.phase_c_event_binding
             where outbox_writer = '' or delivery_worker = '' or dedupe_key = '');
  ok := actual = expected; return next;

  check_name := 'gates_classified'; expected := '32';
  actual := (select count(*)::text from public.phase_c_gate_binding);
  ok := actual = expected; return next;

  check_name := 'rules_classified'; expected := '54';
  actual := (select count(*)::text from public.phase_c_rule_binding);
  ok := actual = expected; return next;

  -- Every routine a binding names must actually be deployed.  This is the check that stops a
  -- binding CSV from being a document: it re-reads pg_proc.
  check_name := 'bindings_naming_undeployed_routines'; expected := '0';
  actual := (
    with named as (
      select distinct (regexp_match(x, 'public\.(fn_[a-z0-9_]+)'))[1] as fn
      from (
        select gate_enforcer x from public.phase_c_step_binding
        union all select authority_enforcer from public.phase_c_step_binding
        union all select review_enforcer from public.phase_c_step_binding
        union all select event_emitter from public.phase_c_step_binding
        union all select handoff_writer from public.phase_c_step_binding
        union all select canonical_runtime_handler from public.phase_c_step_binding
        union all select resolver_path from public.phase_c_role_binding
        union all select task_receiver_path from public.phase_c_role_binding
        union all select authority_binding_path from public.phase_c_role_binding
        union all select review_binding_path from public.phase_c_role_binding
        union all select knowledge_scope_path from public.phase_c_role_binding
        union all select tool_policy_path from public.phase_c_role_binding
        union all select invocation_entrypoint from public.phase_c_overlay_binding
        union all select runtime_entrypoint from public.phase_c_workflow_binding
        union all select event_outbox_writer from public.phase_c_workflow_binding
        union all select runtime_writer from public.phase_c_handoff_binding
        union all select runtime_receiver from public.phase_c_handoff_binding
        union all select packet_schema_validator from public.phase_c_handoff_binding
        union all select sla_timer_handler from public.phase_c_handoff_binding
        union all select enforcement_function from public.phase_c_gate_binding
        union all select enforcement_function from public.phase_c_rule_binding
      ) s where x is not null
    )
    select count(*)::text from named
    where fn is not null
      and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                      where n.nspname='public' and p.proname = named.fn));
  ok := actual = expected; return next;

  -- ---------------------------------------------------------------- runtime accountability
  check_name := 'components_inventoried'; expected := '>=1799';
  actual := (select count(*)::text from public.phase_c_component);
  ok := (select count(*) from public.phase_c_component) >= 1799; return next;

  check_name := 'active_state_changing_without_role'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component
             where mutates_state and activation_state not in ('inactive','disabled')
               and accountable_role_id = '');
  ok := actual = expected; return next;

  check_name := 'active_state_changing_without_system_actor'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component
             where mutates_state and activation_state not in ('inactive','disabled')
               and canonical_system_actor = '');
  ok := actual = expected; return next;

  check_name := 'active_state_changing_without_scope'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component
             where mutates_state and activation_state not in ('inactive','disabled')
               and workflow_id = '');
  ok := actual = expected; return next;

  check_name := 'unclassified_components'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component where classification = '');
  ok := actual = expected; return next;

  check_name := 'unclassified_edge_functions'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component
             where component_type = 'edge_function' and classification = '');
  ok := actual = expected; return next;

  check_name := 'unclassified_db_functions_and_triggers'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component
             where component_type in ('database_function','database_trigger') and classification = '');
  ok := actual = expected; return next;

  check_name := 'unclassified_cron_jobs'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component
             where component_type = 'cron_job' and classification = '');
  ok := actual = expected; return next;

  check_name := 'generic_owner_used'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component
             where accountable_role_id in ('Director','director','service_role','pg_cron','postgres','system','admin','code_runner','unknown',''));
  ok := actual = expected; return next;

  check_name := 'component_owners_resolve'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component c
             where not public.fn_phase_c_actor_may_own(c.accountable_role_id));
  ok := actual = expected; return next;

  -- ---------------------------------------------------------------- founder autonomy
  check_name := 'non_refund_founder_approvals'; expected := '0';
  actual := public.fn_phase_c_non_refund_founder_approvals()::text;
  ok := actual = expected; return next;

  check_name := 'action_classes_requiring_founder_approval'; expected := '1';
  actual := (select count(*)::text from public.phase_c_action_class where founder_approval_required);
  ok := actual = expected; return next;

  check_name := 'the_founder_approval_class_is_refund_decision'; expected := 'refund_decision';
  actual := coalesce((select action_class from public.phase_c_action_class where founder_approval_required), 'NONE');
  ok := actual = expected; return next;

  check_name := 'refund_executions_without_founder_decision'; expected := '0';
  actual := (select count(*)::text from public.phase_c_refund_decision
             where executed_at is not null and decision <> 'approved');
  ok := actual = expected; return next;

  check_name := 'refund_executor_equals_reconciler'; expected := '0';
  actual := (select count(*)::text from public.phase_c_refund_decision
             where executor_role_id = reconciler_role_id);
  ok := actual = expected; return next;

  -- ---------------------------------------------------------------- founder commands
  check_name := 'founder_messages_without_command'; expected := '0';
  actual := (select count(*)::text from public.founder_command_message m
             where not exists (select 1 from public.founder_command c where c.message_id = m.message_id));
  ok := actual = expected; return next;

  check_name := 'routed_commands_without_tasks'; expected := '0';
  actual := (select count(*)::text from public.founder_command c
             where c.state in ('tasks_created','in_progress','partially_blocked','completed')
               and c.intent_id not in ('CMD-STATUS','CMD-CANCEL','CMD-REPRIORITIZE','CMD-EXPLAIN')
               and c.outcome <> 'REFUND_APPROVAL'
               and not exists (select 1 from public.founder_command_task_link l where l.command_id = c.command_id));
  ok := actual = expected; return next;

  check_name := 'ambiguous_commands_that_created_tasks'; expected := '0';
  actual := (select count(*)::text from public.founder_command c
             where c.intent_id = 'AMBIGUOUS'
               and exists (select 1 from public.founder_command_task_link l where l.command_id = c.command_id));
  ok := actual = expected; return next;

  check_name := 'command_tasks_without_canonical_owner'; expected := '0';
  actual := (select count(*)::text from public.phase_c_task t
             where t.command_id is not null and not public.fn_phase_c_actor_may_own(t.accountable_role_id));
  ok := actual = expected; return next;

  check_name := 'command_plans_without_chief_of_staff_owner'; expected := '0';
  actual := (select count(*)::text from public.founder_command where command_owner_role_id <> 'chief_of_staff');
  ok := actual = expected; return next;

  check_name := 'duplicate_command_from_same_idempotency_key'; expected := '0';
  actual := (select coalesce(sum(n - 1), 0)::text from (
               select count(*) n from public.founder_command_message group by client_idempotency_key having count(*) > 1) s);
  ok := actual = expected; return next;

  -- ---------------------------------------------------------------- authority and review
  check_name := 'creator_reviewer_collisions'; expected := '0';
  actual := (select count(*)::text from public.phase_c_task
             where reviewer_required and not public.fn_phase_c_reviewer_independent(accountable_role_id, reviewer_role_id));
  ok := actual = expected; return next;

  check_name := 'step_bindings_with_self_review'; expected := '0';
  actual := (select count(*)::text from public.phase_c_step_binding
             where independent_reviewer_role_id <> ''
               and not public.fn_phase_c_reviewer_independent(accountable_role_id, independent_reviewer_role_id));
  ok := actual = expected; return next;

  check_name := 'overlay_owning_a_task'; expected := '0';
  actual := (select count(*)::text from public.phase_c_task t
             where (select kind from public.fn_phase_c_resolve_actor(t.accountable_role_id)) = 'overlay');
  ok := actual = expected; return next;

  -- ---------------------------------------------------------------- traces
  check_name := 'completed_commands_without_trace'; expected := '0';
  actual := (select count(*)::text from public.founder_command
             where state in ('tasks_created','in_progress','completed') and trace_id is null);
  ok := actual = expected; return next;

  check_name := 'closed_tasks_without_trace'; expected := '0';
  actual := (select count(*)::text from public.phase_c_task where closed_at is not null and trace_id is null);
  ok := actual = expected; return next;

  check_name := 'completed_step_runs_without_trace'; expected := '0';
  actual := (select count(*)::text from public.phase_c_workflow_step_run
             where state = 'completed' and trace_id is null);
  ok := actual = expected; return next;

  check_name := 'handoff_runs_without_trace'; expected := '0';
  actual := (select count(*)::text from public.phase_c_handoff_run where trace_id is null);
  ok := actual = expected; return next;

  -- ---------------------------------------------------------------- idempotency and delivery
  check_name := 'duplicate_outbox_dedupe_values'; expected := '0';
  actual := (select coalesce(sum(n - 1), 0)::text from (
               select count(*) n from public.phase_c_event_outbox group by event_id, dedupe_value having count(*) > 1) s);
  ok := actual = expected; return next;

  check_name := 'delivered_without_downstream_record'; expected := '0';
  actual := (select count(*)::text from public.phase_c_event_outbox o
             where o.status = 'delivered'
               and not exists (select 1 from public.phase_c_event_delivery_attempt a
                               where a.outbox_id = o.outbox_id and a.ok and a.downstream_ref <> ''));
  ok := actual = expected; return next;

  check_name := 'retry_erased_the_first_failure'; expected := '0';
  actual := (select count(*)::text from public.phase_c_event_outbox
             where attempts > 1 and status = 'delivered' and first_failure = ''
               and exists (select 1 from public.phase_c_event_delivery_attempt a
                           where a.outbox_id = phase_c_event_outbox.outbox_id and not a.ok));
  ok := actual = expected; return next;

  check_name := 'duplicate_task_idempotency_keys'; expected := '0';
  actual := (select coalesce(sum(n - 1), 0)::text from (
               select count(*) n from public.phase_c_task group by idempotency_key having count(*) > 1) s);
  ok := actual = expected; return next;

  -- ---------------------------------------------------------------- cost
  check_name := 'paid_inference_since_phase_c_started'; expected := '0';
  actual := (select count(*)::text from public.ai_cost_log
             where occurred_at > (select coalesce(max(recorded_at), now() - interval '1 day')
                                  from public.phase_c_package_erratum));
  ok := actual = expected; return next;

  check_name := 'openrouter_routes_open'; expected := '0';
  actual := (select count(*)::text from public.llm_route_health where open_until <= now());
  ok := actual = expected; return next;

  return;
end $$;
revoke all on function public.fn_phase_c_invariants() from public;
grant execute on function public.fn_phase_c_invariants() to service_role;

-- The Phase C equivalent of fn_phase_a_baseline_drift / fn_phase_b_baseline_drift: the one
-- query the end-of-session sweep runs.
create or replace function public.fn_phase_c_baseline_drift()
returns table (subject text, approved text, live text)
language sql stable set search_path to 'public', 'pg_temp' as $$
  select check_name, expected, actual from public.fn_phase_c_invariants() where not ok;
$$;
revoke all on function public.fn_phase_c_baseline_drift() from public;
grant execute on function public.fn_phase_c_baseline_drift() to service_role;
