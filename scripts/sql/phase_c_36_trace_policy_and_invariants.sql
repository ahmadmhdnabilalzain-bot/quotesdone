-- Phase C correction 6 — trace policy that means something, and invariants that can fail.
--
-- The audit found 12 of 12 tasks, 3 of 3 workflow runs and 3 of 3 outbox rows with no trace, while
-- the invariant board reported 58/58 green. Four of the trace checks were computed over tables
-- holding ZERO rows: closed_tasks_without_trace (no task had ever closed),
-- completed_step_runs_without_trace, handoff_runs_without_trace and completed_commands_without_trace.
-- A zero numerator over a zero denominator is not coverage, and it is indistinguishable from a dead
-- guard.
--
-- Every coverage check below now reports "<missing> of <required>" and is ok ONLY when the
-- denominator is greater than zero. Eleven further checks are added, one for each thing the audit
-- found that no existing check could see.

-- ---------------------------------------------------------------- infrastructure exemption
-- "Infrastructure-only objects may be trace_not_required only with a documented reason." One
-- policy, one reason, written down where the exemption is granted rather than assumed.
insert into public.phase_c_trace_policy
  (trace_policy_id, scope, trace_required, minimum_fields, completed_without_trace_allowed)
values ('TRACE-INFRASTRUCTURE',
        'Infrastructure-only execution that changes no business state and produces no official '
        'output: schema/DDL helpers, read-only exports, cache primers and health probes whose '
        'result is already aggregated into TRACE-MONITORING.',
        'NOT_REQUIRED',
        'component_id; reason_for_exemption',
        'YES_WITH_DOCUMENTED_REASON')
on conflict (trace_policy_id) do update set
  scope = excluded.scope, trace_required = excluded.trace_required,
  minimum_fields = excluded.minimum_fields,
  completed_without_trace_allowed = excluded.completed_without_trace_allowed;

-- ---------------------------------------------------------------- coverage, by subject
-- One place that answers "required / complete / incomplete / missing", so a report and a test can
-- never disagree about the denominator.
-- ROUTINE REMOVED 7 September 2026. public.fn_phase_c_trace_coverage was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

revoke all on function public.fn_phase_c_trace_coverage() from public;
grant execute on function public.fn_phase_c_trace_coverage() to service_role;

-- ---------------------------------------------------------------- the invariants
CREATE OR REPLACE FUNCTION public.fn_phase_c_invariants()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_bad bigint; v_pop bigint;
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

  -- WAS: where classification = '' — the empty string, which no row has ever held, while 286 rows
  -- carried the literal 'NO_CALLER_UNCLASSIFIED' and 99 of those were active and state-changing.
  -- The check now measures the population gate 4 actually names.
  check_name := 'unclassified_components'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component
             where mutates_state and activation_state not in ('inactive','disabled')
               and classification in ('', 'NO_CALLER_UNCLASSIFIED'));
  ok := actual = expected; return next;

  check_name := 'unclassified_edge_functions'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component
             where component_type = 'edge_function'
               and activation_state not in ('inactive','disabled')
               and classification in ('', 'NO_CALLER_UNCLASSIFIED'));
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
  -- DENOMINATOR-AWARE. This reported 0 over a table that held 0 rows, which is not coverage.
  check_name := 'completed_commands_without_trace'; expected := '0 of >0';
  select count(*) filter (where trace_id is null), count(*) into v_bad, v_pop from public.founder_command where state in ('completed','cancelled','failed','refused','superseded');
  actual := v_bad::text || ' of ' || v_pop::text;
  ok := (v_bad = 0 and v_pop > 0); return next;
  -- (the shared tail below is skipped for this check)

  -- DENOMINATOR-AWARE. This reported 0 over a table that held 0 rows, which is not coverage.
  check_name := 'closed_tasks_without_trace'; expected := '0 of >0';
  select count(*) filter (where trace_id is null), count(*) into v_bad, v_pop from public.phase_c_task where closed_at is not null;
  actual := v_bad::text || ' of ' || v_pop::text;
  ok := (v_bad = 0 and v_pop > 0); return next;
  -- (the shared tail below is skipped for this check)

  -- DENOMINATOR-AWARE. This reported 0 over a table that held 0 rows, which is not coverage.
  check_name := 'completed_step_runs_without_trace'; expected := '0 of >0';
  select count(*) filter (where trace_id is null), count(*) into v_bad, v_pop from public.phase_c_workflow_step_run where state = 'completed';
  actual := v_bad::text || ' of ' || v_pop::text;
  ok := (v_bad = 0 and v_pop > 0); return next;
  -- (the shared tail below is skipped for this check)

  -- DENOMINATOR-AWARE. This reported 0 over a table that held 0 rows, which is not coverage.
  check_name := 'handoff_runs_without_trace'; expected := '0 of >0';
  select count(*) filter (where trace_id is null), count(*) into v_bad, v_pop from public.phase_c_handoff_run;
  actual := v_bad::text || ' of ' || v_pop::text;
  ok := (v_bad = 0 and v_pop > 0); return next;
  -- (the shared tail below is skipped for this check)

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
  -- WAS anchored to max(recorded_at) from phase_c_package_erratum: recording any new erratum moved
  -- the window forward and the check went green over whatever spend it had just stepped over, and
  -- emptying that table moved the anchor to now()-1 day. The start of Phase C is a fixed instant,
  -- and BOTH cost ledgers are counted, not one.
  actual := ((select count(*) from public.ai_cost_log where occurred_at > timestamptz '2026-08-15 02:51:36+00')
           + (select count(*) from public.llm_attempt where created_at  > timestamptz '2026-08-15 02:51:36+00'))::text;
  ok := actual = expected; return next;

  check_name := 'openrouter_routes_open'; expected := '0';
  actual := (select count(*)::text from public.llm_route_health where open_until <= now());
  ok := actual = expected; return next;

  -- ---------------------------------------------------------------- correction 2026-08-16
  -- Every one of these exists because the audit found the thing it measures, and found no check
  -- that could have seen it.

  check_name := 'tasks_without_trace'; expected := '0 of >0';
  select count(*) filter (where trace_id is null), count(*) into v_bad, v_pop from public.phase_c_task;
  actual := v_bad::text || ' of ' || v_pop::text;
  ok := (v_bad = 0 and v_pop > 0); return next;

  check_name := 'workflow_runs_without_trace'; expected := '0 of >0';
  select count(*) filter (where trace_id is null), count(*) into v_bad, v_pop
    from public.phase_c_workflow_run;
  actual := v_bad::text || ' of ' || v_pop::text;
  ok := (v_bad = 0 and v_pop > 0); return next;

  check_name := 'outbox_rows_without_trace'; expected := '0 of >0';
  select count(*) filter (where trace_id is null), count(*) into v_bad, v_pop
    from public.phase_c_event_outbox;
  actual := v_bad::text || ' of ' || v_pop::text;
  ok := (v_bad = 0 and v_pop > 0); return next;

  -- A command whose root trace describes a different moment than the command itself.
  check_name := 'commands_ahead_of_their_trace'; expected := '0';
  actual := (select count(*)::text from public.founder_command c
             join public.phase_c_trace t on t.trace_id = c.trace_id
             where t.state_after is distinct from c.state);
  ok := actual = expected; return next;

  -- The founder-command event must name the workflow the command actually selected.
  -- `superseded` rows are excluded because that status IS the finding: three rows emitted before
  -- the fix are quarantined there, unreachable by the claim (which takes only pending/retry_wait)
  -- and carrying the reason on the row. The companion check below makes that quarantine cost
  -- something, so this exclusion cannot become a hiding place.
  check_name := 'outbox_events_naming_another_workflow'; expected := '0';
  actual := (select count(*)::text from public.phase_c_event_outbox o
             where o.payload ? 'command_id' and o.status <> 'superseded'
               and not exists (select 1 from public.founder_command_workflow_link l2
                               where l2.command_id = (o.payload->>'command_id')::bigint
                                 and l2.workflow_id = o.workflow_id));
  ok := actual = expected; return next;

  check_name := 'outbox_superseded_without_a_stated_reason'; expected := '0';
  actual := (select count(*)::text from public.phase_c_event_outbox
             where status = 'superseded' and coalesce(btrim(last_error),'') = '');
  ok := actual = expected; return next;

  -- The queue has to have been drained by something, at least once.
  check_name := 'outbox_delivery_attempts_exist'; expected := '>0 when the outbox is non-empty';
  select count(*) into v_pop from public.phase_c_event_outbox;
  select count(*) into v_bad from public.phase_c_event_delivery_attempt;
  actual := v_bad::text || ' attempt(s) for ' || v_pop::text || ' outbox row(s)';
  ok := (v_pop = 0 or v_bad > 0); return next;

  check_name := 'outbox_rows_stuck_pending_over_an_hour'; expected := '0';
  actual := (select count(*)::text from public.phase_c_event_outbox
             where status = 'pending' and created_at < now() - interval '1 hour');
  ok := actual = expected; return next;

  check_name := 'outbox_dead_letter'; expected := '0';
  actual := (select count(*)::text from public.phase_c_event_outbox where status = 'dead_letter');
  ok := actual = expected; return next;

  -- An event binding may only claim CONNECTED when the derivation agrees.
  check_name := 'event_bindings_claiming_more_than_the_legs_support'; expected := '0';
  actual := (select count(*)::text from public.phase_c_event_binding b
             where b.connection_status
                   is distinct from (select status from public.fn_phase_c_event_binding_status(b.event_id)));
  ok := actual = expected; return next;

  check_name := 'active_state_changing_without_authority'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component
             where mutates_state and activation_state not in ('inactive','disabled')
               and coalesce(authority_class,'') = '');
  ok := actual = expected; return next;

  check_name := 'active_state_changing_without_trace_policy'; expected := '0';
  actual := (select count(*)::text from public.phase_c_component
             where mutates_state and activation_state not in ('inactive','disabled')
               and coalesce(trace_policy_id,'') = '');
  ok := actual = expected; return next;

  -- A clarification the founder can never close was the seventh audit failure.
  check_name := 'clarification_required_has_an_exit'; expected := '2';
  actual := (select count(*)::text from public.phase_c_command_transition
             where from_state = 'clarification_required');
  ok := actual = expected; return next;

  return;
end $function$;
revoke all on function public.fn_phase_c_invariants() from public;
grant execute on function public.fn_phase_c_invariants() to service_role;
