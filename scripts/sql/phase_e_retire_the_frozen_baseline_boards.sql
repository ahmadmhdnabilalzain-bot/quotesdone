-- PHASE E (3): RETIRE THE PHASE A/B FROZEN-BASELINE DRIFT BOARDS — measured, not assumed.
--
-- The founder removed every phase freeze on 2 Sep 2026. fn_phase_a_baseline_drift() and
-- fn_phase_b_baseline_drift() compared the live organisation and the Phase B structure to a digest
-- kept in org_phase_baseline; with no freeze, a board that goes red when the company legitimately
-- changes protects nothing (docs/agents/RETIRED_MIRROR_GATES.md, "a check may compare production to
-- a PROPERTY … not to a COPY of itself"). CI already printed their drift as information only
-- (phase_c_invariants.test.mjs, 3 Sep). Three LIVE routines still consulted them — that is what made
-- them alive, and that is what this file retargets:
--
--   fn_phase_c_invariants     rows phase_a_drift, phase_b_drift and three frozen counts
--                             (active_departments, canonical_roles, category_overlays) -> one property
--                             row, organization_structural_violations = 0; phase_b_unresolved_errata kept
--   fn_phase_b_invariants     row phase_a.baseline_drift_rows and the fifteen count.* mirror rows -> gone;
--                             phase_a.organization_violations and every property block kept
--   fn_phase_d_gate_evaluate  GATE-001 ("Phase A baseline frozen", hard, workflow_scope ALL — a freeze
--                             inside the live handler path) -> the organisation has no structural
--                             violation. phase_b_gate / phase_c_gate_binding / phase_d_gate_contract say so.
--
-- MEASURED before removal (4 Sep 2026): callers of the two drift routines in every public routine
-- body = exactly the three above (+ B calls A); 0 cron commands, 0 execution wrappers, 0 triggers
-- (pg_trigger.tgfoid), 0 views / other pg_depend, 0 RLS policies, 0 kernel_write_authority rows, not a
-- board by fn_kernel_all_boards() signature; repo callers = phase_c_invariants.test.mjs (informational
-- since 3 Sep), org_connectivity_scenarios.test.mjs (one assertion, removed in the same commit), and
-- the freeze-era operator scripts under scripts/phase_a|b|c (edited or historical). Current drift:
-- A=0, B=0, fn_phase_a_organization_violations()=0 — so no row's verdict changes today.
--
-- fn_phase_b_structure_digest is NOT retired: fn_phase_d_founder_authority reads its founder_boundaries
-- subject. org_phase_baseline stays (append-only history; three approved rows).
--
-- Reversibility: git holds the previous bodies (supabase/migrations/20260815070000_phase_a_frozen_
-- founder_approved.sql, scripts/sql/phase_b_11_baseline_functions.sql); the gate-row edits are
-- reversed by scripts/sql/down/phase_e_retire_the_frozen_baseline_boards_down.sql; DROP FUNCTION has no
-- SQL down (scripts/sql/down/README.md). scripts/sql/DROPPED.txt records the two absences.
--
--   node scripts/apply_sql.mjs scripts/sql/phase_e_retire_the_frozen_baseline_boards.sql --apply --ddl

begin;

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

  -- ---------------------------------------------------------------- organisation properties
  -- 4 SEP 2026 (Phase E): the five rows that stood here compared production to org_phase_baseline —
  -- fn_phase_a_baseline_drift(), fn_phase_b_baseline_drift() and three frozen counts. The founder
  -- removed every phase freeze on 2 Sep, so a board that reddens when the organisation legitimately
  -- changes protected nothing and reddened for bookkeeping. What those rows DEFENDED is a property,
  -- asserted here directly: the organisation has no structural violation (every active department
  -- has a head, every canonical role resolves, no cycle in the reporting graph — see
  -- fn_phase_a_organization_violations), and every effective Phase B erratum is resolved.
  check_name := 'organization_structural_violations'; expected := '0';
  actual := (select count(*)::text from public.fn_phase_a_organization_violations());
  ok := actual = expected; return next;

  check_name := 'phase_b_unresolved_errata'; expected := '0';
  actual := (select count(*)::text from public.fn_phase_b_effective_errata() where not resolved);
  ok := actual = expected; return next;

  -- ---------------------------------------------------------------- binding coverage
  check_name := 'roles_bound';
  expected := (select count(*)::text from public.org_role where status='active' and runtime_mode <> 'knowledge_overlay');
  actual := (select count(*)::text from public.phase_c_role_binding where connection_status = 'CONNECTED');
  ok := actual = expected; return next;

  check_name := 'roles_without_binding'; expected := '0';
  actual := (select count(*)::text from public.org_role r
             where r.status='active' and r.runtime_mode <> 'knowledge_overlay'
               and not exists (select 1 from public.phase_c_role_binding b
                               where b.canonical_role_id = r.role_id
                                  or b.canonical_role_id in (select alias from public.org_role_alias a where a.role_id = r.role_id)));
  ok := actual = expected; return next;

  check_name := 'overlays_bound';
  expected := (select count(*)::text from public.org_role where status='active' and runtime_mode = 'knowledge_overlay');
  actual := (select count(*)::text from public.phase_c_overlay_binding where connection_status = 'CONNECTED');
  ok := actual = expected; return next;

  check_name := 'overlay_bindings_resolve'; expected := '0';
  actual := (select count(*)::text from public.phase_c_overlay_binding b
             where not exists (select 1 from public.org_role r
                               where r.role_id = b.live_role_id and r.status='active'
                                 and r.runtime_mode='knowledge_overlay'));
  ok := actual = expected; return next;

  check_name := 'workflows_bound';
  expected := (select count(*)::text from public.phase_b_workflow);
  actual := (select count(*)::text from public.phase_c_workflow_binding);
  ok := actual = expected; return next;

  check_name := 'workflows_without_binding'; expected := '0';
  actual := (select count(*)::text from public.phase_b_workflow w
             where not exists (select 1 from public.phase_c_workflow_binding b where b.workflow_id = w.workflow_id));
  ok := actual = expected; return next;

  check_name := 'steps_bound_or_classified';
  expected := (select count(*)::text from public.phase_b_workflow_step);
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

  check_name := 'handoffs_bound';
  expected := (select count(*)::text from public.phase_b_handoff);
  actual := (select count(*)::text from public.phase_c_handoff_binding);
  ok := actual = expected; return next;

  check_name := 'handoffs_without_binding'; expected := '0';
  actual := (select count(*)::text from public.phase_b_handoff h
             where not exists (select 1 from public.phase_c_handoff_binding b where b.handoff_id = h.handoff_id));
  ok := actual = expected; return next;

  check_name := 'events_classified';
  expected := (select count(*)::text from public.phase_b_event);
  actual := (select count(*)::text from public.phase_c_event_binding);
  ok := actual = expected; return next;

  check_name := 'events_without_producer_or_consumer'; expected := '0';
  actual := (select count(*)::text from public.phase_c_event_binding
             where outbox_writer = '' or delivery_worker = '' or dedupe_key = '');
  ok := actual = expected; return next;

  check_name := 'gates_classified';
  expected := (select count(*)::text from public.phase_b_gate);
  actual := (select count(*)::text from public.phase_c_gate_binding);
  ok := actual = expected; return next;

  check_name := 'rules_classified';
  expected := (select count(*)::text from public.phase_b_business_rule);
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
  check_name := 'components_inventoried'; expected := '>=1794';
  actual := (select count(*)::text from public.phase_c_component);
  ok := (select count(*) from public.phase_c_component) >= 1794; return next;  -- re-baselined 2026-09-02: 13 phase-freeze trigger components removed by founder order

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
             where attempts > 1 and status = 'delivered' and first_failure is null
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
  -- 4 SEP 2026: a row in a cost ledger is not a paid call. Since the company loop restarted, a HELD
  -- call writes an ai_cost_log row with model_used = 'none', cost 0 and no provider round trip
  -- (the gate said so in model_selected_because), and this line counted it as paid inference.
  -- "Paid" means a provider was reached: tokens, cost or an HTTP status on the attempt.
  actual := ((select count(*) from public.ai_cost_log
               where occurred_at > timestamptz '2026-08-15 02:51:36+00'
                 and (coalesce(cost_aed, 0) > 0 or coalesce(prompt_tokens, 0) > 0 or coalesce(model_used, 'none') <> 'none'))
           + (select count(*) from public.llm_attempt
               where created_at > timestamptz '2026-08-15 02:51:36+00'
                 and (coalesce(cost_aed, 0) > 0 or coalesce(prompt_tokens, 0) > 0 or http_status is not null)))::text;
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
end $function$
;

-- ROUTINE REMOVED 7 September 2026. public.fn_phase_b_invariants was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


CREATE OR REPLACE FUNCTION public.fn_phase_d_gate_evaluate(p_gate_id text, p_evidence jsonb)
 RETURNS TABLE(state text, passed boolean, gate_type text, reason text, refusal_code text, evidence_absent boolean)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_g13_ok boolean; v_g13_code text; v_g13_why text;   -- O07
  g public.phase_b_gate%rowtype;
  c public.phase_d_gate_contract%rowtype;
  s public.phase_b_workflow_step%rowtype;
  v_missing text[]; v_n bigint; v_ok boolean; v_txt text;
  v_auth jsonb;   -- K01
begin
  evidence_absent := false;   -- E19, see fn_phase_d_rule_check
  select * into g from public.phase_b_gate where gate_id = p_gate_id;
  if not found then
    state := 'NOT_IMPLEMENTED'; passed := false; gate_type := 'unknown';
    reason := format('unknown gate %s — blocked, not defaulted', p_gate_id);
    refusal_code := 'gate_unknown'; return next; return;
  end if;
  gate_type := g.gate_type;

  select * into c from public.phase_d_gate_contract where gate_id = p_gate_id;
  if not found then
    state := 'NOT_IMPLEMENTED'; passed := false;
    reason := format('gate %s has no Phase D evidence contract — blocked', p_gate_id);
    refusal_code := 'gate_uncontracted'; return next; return;
  end if;
  refusal_code := c.refusal_code;

  if cardinality(c.evidence_keys) > 0 then
    select array_agg(k order by k) into v_missing
      from unnest(c.evidence_keys) k
     where p_evidence is null or not (p_evidence ? k)
        or jsonb_typeof(p_evidence->k) = 'null'
        or (jsonb_typeof(p_evidence->k) = 'string' and btrim(p_evidence->>k) = '');
    if v_missing is not null then
      -- E19. Same distinction as the rule side. The gate is BLOCKED either way; this column says
      -- which kind of blocked. Here the gate never saw its evidence -- it did not judge it.
      evidence_absent := true;
      state := 'BLOCKED'; passed := false;
      reason := format('gate %s (%s) requires [%s] and the call names none of it. Declared evidence: %s',
                       g.gate_id, g.gate_name, array_to_string(v_missing, ', '),
                       coalesce(g.required_evidence,'(none stated)'));
      return next; return;
    end if;
  end if;

  -- ============================ N06. READ FAILURE IS NOT REFUSAL ============================
  -- Until this block existed the routine carried ZERO exception handlers, so a read error inside a
  -- predicate -- permission denied, a relation renamed, a statement cancelled -- propagated and
  -- aborted the CALLER'S transaction. There was no state, refusal_code or evidence_absent value
  -- that said "the gate could not read", as distinct from the BLOCKED/false it returns when it
  -- read the evidence and judged it. Those are different facts with different remedies: one is
  -- fixed by correcting the evidence, the other by fixing the estate, and a caller that cannot
  -- tell them apart will retry the wrong one forever.
  --
  -- IT FAILS CLOSED. state BLOCKED, passed false, evidence_absent true -- the gate did not see its
  -- evidence, because it could not read it. A gate that answered PASSED on a read error would be
  -- the far worse defect.
  --
  -- THE FAULT HOOK. A read error cannot be provoked from inside an aborted transaction by revoking
  -- a grant -- the routine pins its own search_path and runs as the owner of every relation it
  -- reads, so nothing a caller sets reaches it. app.phase_d_gate_read_fault names one gate whose
  -- read is made to fail, and it is the ONLY way this branch can be reached deliberately. Said
  -- plainly: the fault is injected, not a revoked production grant. What the test proves is that
  -- the DISTINCTION exists and fails closed -- which is the whole of the defect -- and the control
  -- is the identical call with the hook unset.
  begin
    if coalesce(nullif(current_setting('app.phase_d_gate_read_fault', true),''), '') = p_gate_id then
      perform 1 / (case when true then 0 else 1 end);
    end if;

  if p_gate_id = 'GATE-001' then
    -- 4 SEP 2026 (Phase E). This gate read fn_phase_a_baseline_drift(): "the organisation still
    -- matches the frozen Phase A digest". The founder removed the phase freezes on 2 Sep, so a
    -- hard gate with workflow_scope ALL that refused every step the moment a department was
    -- re-carved was a freeze by another name. The property the gate is FOR — the organisation the
    -- step runs in is structurally valid — is measured directly.
    select count(*) into v_n from public.fn_phase_a_organization_violations();
    v_ok := (v_n = 0);
    reason := format('GATE-001: the organisation has %s structural violation(s) (fn_phase_a_organization_violations)', v_n);

  elsif p_gate_id = 'GATE-002' then
    v_ok := public.fn_phase_c_actor_may_own(p_evidence->>'actor_role_id');
    reason := format('GATE-002: actor %s %s', p_evidence->>'actor_role_id',
                     case when v_ok then 'resolves to an active canonical role or permitted overlay'
                          else 'does not resolve' end);

  elsif p_gate_id = 'GATE-003' then
    select count(*) into v_n from public.phase_b_workflow_step x
     where x.step_id = p_evidence->>'step_id' and coalesce(btrim(x.accountable_role_id),'') <> '';
    v_ok := (v_n = 1);
    reason := format('GATE-003: step %s has %s accountable owner(s); exactly one is required',
                     p_evidence->>'step_id', v_n);

  elsif p_gate_id = 'GATE-004' then
    select * into s from public.phase_b_workflow_step where step_id = p_evidence->>'step_id';
    v_ok := public.fn_kernel_reviewer_independent(s.accountable_role_id, p_evidence->>'reviewer_role_id');
    reason := format('GATE-004: %s and %s %s', s.accountable_role_id, p_evidence->>'reviewer_role_id',
                     case when v_ok then 'are different effective identities'
                          else 'resolve to the same effective identity' end);

  elsif p_gate_id = 'GATE-005' then
    -- K01. THIS WAS `v_ok := true`. The gate checked that a string was present and never that it
    -- meant anything, so any caller could have handed it any text and passed the founder boundary.
    -- It now resolves the authority for itself, from the founder command that instructed the run or
    -- from the founder-approved frozen boundary register, and requires the reference the call
    -- presents to be the one that resolves.
    select * into s from public.phase_b_workflow_step where step_id = p_evidence->>'step_id';
    v_auth := public.fn_phase_d_founder_authority(
                nullif(p_evidence->>'run_id','')::bigint, p_evidence->>'step_id');
    v_ok := coalesce((v_auth->>'valid')::boolean, false)
            and v_auth->>'ref' is not null
            and (p_evidence->>'founder_authority_ref') = (v_auth->>'ref');
    reason := format('GATE-005: step declares founder_gate %s; the call names authority %s; the '
                  || 'estate resolves %s (%s) -- %s',
                     left(coalesce(s.founder_gate,'none'),60),
                     coalesce(p_evidence->>'founder_authority_ref','(none)'),
                     coalesce(v_auth->>'ref','(none)'), coalesce(v_auth->>'kind','-'),
                     coalesce(v_auth->>'why','(no reason stated)'));

  elsif p_gate_id = 'GATE-006' then
    if p_evidence->>'from_state' = p_evidence->>'to_state' then
      v_ok := true;
      reason := format('GATE-006: the run stays in %s — this step applies no workflow-state '
                    || 'transition, so there is none to declare. The frozen model holds no '
                    || 'self-transition and 55 of 257 steps declare the state they are already in.',
                       p_evidence->>'from_state');
    else
      select count(*) into v_n from public.phase_b_workflow_transition t
       where t.from_state = p_evidence->>'from_state' and t.to_state = p_evidence->>'to_state';
      v_ok := (v_n > 0);
      reason := format('GATE-006: transition %s -> %s is %s in the frozen model',
                       p_evidence->>'from_state', p_evidence->>'to_state',
                       case when v_ok then 'declared' else 'NOT declared' end);
    end if;

  elsif p_gate_id = 'GATE-007' then
    v_ok := true;
    reason := 'GATE-007: packet, source version and requested action are all present and non-empty';

  elsif p_gate_id = 'GATE-008' then
    -- THE CLOSING STEP IS NOT AN OUTSTANDING PIECE OF WORK. It is necessarily open while it asks,
    -- so counting it made this gate unpassable for all 30 closure steps. Every other open step run
    -- still blocks.
    select count(*) into v_n from public.phase_c_workflow_step_run x
     where x.run_id = (p_evidence->>'run_id')::bigint
       and x.step_run_id is distinct from (p_evidence->>'step_run_id')::bigint
       and x.state not in ('completed','cancelled','failed','superseded','skipped');
    v_ok := (v_n = 0);
    reason := format('GATE-008: %s step run(s) still open on run %s, excluding the closing step run %s itself',
                     v_n, p_evidence->>'run_id', p_evidence->>'step_run_id');

  elsif p_gate_id = 'GATE-009' then
    v_ok := true;
    reason := format('GATE-009: acceptance %s names version %s at hash %s',
                     p_evidence->>'acceptance_ref', p_evidence->>'terms_version',
                     left(p_evidence->>'terms_hash',12));

  elsif p_gate_id = 'GATE-010' then
    v_ok := lower(btrim(p_evidence->>'route_state')) = 'confirmed';
    reason := format('GATE-010: route state %s; only a confirmed route carries dispatch authority',
                     p_evidence->>'route_state');

  elsif p_gate_id = 'GATE-011' then
    select count(*) into v_n from public.inquiries i
     where i.id::text = p_evidence->>'inquiry_id'
       and coalesce(i.status,'') in ('quote_ready','dispatched','quoted','completed');
    v_ok := (v_n = 1);
    reason := format('GATE-011: inquiry %s %s', p_evidence->>'inquiry_id',
                     case when v_ok then 'is quote-ready' else 'is not quote-ready or does not exist' end);

  elsif p_gate_id = 'GATE-012' then
    select count(*) into v_n from public.documents d
     where d.id::text = p_evidence->>'document_id'
       and coalesce(d.status,'') not in ('error','quarantined','rejected')
       and coalesce(d.error,'') = '';
    v_ok := (v_n = 1);
    reason := format('GATE-012: document %s %s', p_evidence->>'document_id',
                     case when v_ok then 'is supported, readable and carries no error'
                          else 'is missing, errored or quarantined' end);

  elsif p_gate_id = 'GATE-013' then
    -- O04/O07. THIS NEVER DEREFERENCED safe_package_ref. The value was required present by the
    -- generic evidence_keys loop and then used only inside format() for the reason string, so the
    -- gate could be satisfied by any package at all provided the approver was not the author.
    -- It now consults the same file-set verdict BR-012 does.
    select pr.dispatchable, pr.refusal_code, pr.reason into v_g13_ok, v_g13_code, v_g13_why
      from public.fn_phase_d_package_revisions_dispatchable(p_evidence->>'safe_package_ref') pr;
    v_ok := public.fn_kernel_reviewer_independent(
              coalesce(p_evidence->>'actor_role_id', 'unknown'),
              p_evidence->>'safe_package_approved_by')
            and v_g13_ok;
    if not v_g13_ok then refusal_code := v_g13_code; end if;
    reason := format('GATE-013: package %s approved by %s; independence %s; file set %s',
                     p_evidence->>'safe_package_ref', p_evidence->>'safe_package_approved_by',
                     case when public.fn_kernel_reviewer_independent(
                            coalesce(p_evidence->>'actor_role_id','unknown'),
                            p_evidence->>'safe_package_approved_by')
                          then 'holds' else 'FAILS — the approver is the author' end,
                     coalesce(v_g13_why,'(no verdict)'));

  elsif p_gate_id = 'GATE-014' then
    select count(*) into v_n from public.leads l
     where l.id::text = p_evidence->>'supplier_id'
       and coalesce(l.approval_status,'') = 'approved' and coalesce(l.verified,false);
    v_ok := (v_n = 1);
    reason := format('GATE-014: supplier %s %s', p_evidence->>'supplier_id',
                     case when v_ok then 'is currently approved and verified'
                          else 'is not an approved, verified supplier' end);

  elsif p_gate_id = 'GATE-015' then
    select count(*) into v_n from public.inquiry_matches m
     where m.inquiry_id::text = p_evidence->>'inquiry_id'
       and m.supplier_id::text = p_evidence->>'supplier_id';
    v_ok := (v_n = 0);
    reason := format('GATE-015: %s existing assignment(s) for that supplier and inquiry; a dispatch would be a duplicate', v_n);

  elsif p_gate_id = 'GATE-016' then
    select count(*) into v_n from public.email_suppressions e
     where lower(e.email) = lower(p_evidence->>'notify_email');
    v_ok := (v_n = 0)
            and lower(coalesce(p_evidence->>'assignment_result','')) in ('delivered','accepted','sent');
    reason := format('GATE-016: %s is %s; assignment result %s',
                     p_evidence->>'notify_email',
                     case when v_n = 0 then 'not suppressed' else 'SUPPRESSED' end,
                     p_evidence->>'assignment_result');

  elsif p_gate_id = 'GATE-017' then
    select count(*) into v_n from public.quotes q
     where q.id::text = p_evidence->>'quote_id'
       and q.quote_amount is not null and coalesce(btrim(q.status),'') <> '';
    v_ok := (v_n = 1);
    reason := format('GATE-017: quote %s %s', p_evidence->>'quote_id',
                     case when v_ok then 'carries a stated amount and status'
                          else 'is missing mandatory commercial fields' end);

  elsif p_gate_id = 'GATE-018' then
    -- O06/O07. The byte-identical ownership count BR-019 carried, with the same defect: its
    -- refusal_code is gate018_comparison_not_publishable and it never read publishability.
    -- Changed with the rule and not after it -- fixing only one leaves the gate green on the same
    -- unpublished comparison, which is how a pair of predicates disagrees in silence.
    select cv.visible, cv.refusal_code, cv.reason into v_g13_ok, v_g13_code, v_g13_why
      from public.fn_phase_d_comparison_visible(
             p_evidence->>'comparison_id', p_evidence->>'caller_customer_id',
             coalesce(nullif(btrim(p_evidence->>'caller_kind'),''), 'customer')) cv;
    v_ok := v_g13_ok;
    if not v_ok then refusal_code := v_g13_code; end if;
    reason := 'GATE-018: ' || coalesce(v_g13_why, 'no verdict returned by fn_phase_d_comparison_visible');

  elsif p_gate_id = 'GATE-019' then
    select rp.permitted, rp.reason into v_ok, v_txt
      from public.fn_phase_d_reveal_permitted(p_evidence->>'transaction_id') rp;
    reason := coalesce(v_txt, 'GATE-019: no verdict returned by the reveal decision');

  elsif p_gate_id = 'GATE-020' then
    select count(*) into v_n from public.refunds rf
     where rf.id::text = p_evidence->>'refund_id'
       and coalesce(btrim(rf.decided_by),'') <> '' and rf.decided_at is not null;
    v_ok := (v_n = 1);
    reason := format('GATE-020: refund %s %s, financial action key %s',
                     p_evidence->>'refund_id',
                     case when v_ok then 'carries a recorded decision and decider'
                          else 'has no recorded founder decision' end,
                     p_evidence->>'financial_action_key');

  elsif p_gate_id = 'GATE-021' then
    v_ok := public.fn_kernel_reviewer_independent(
              coalesce(p_evidence->>'actor_role_id','unknown'), p_evidence->>'reviewer_role_id');
    reason := format('GATE-021: artifact %s at digest %s reviewed by %s; independence %s',
                     p_evidence->>'artifact_ref', left(p_evidence->>'artifact_sha256',12),
                     p_evidence->>'reviewer_role_id',
                     case when v_ok then 'holds' else 'FAILS' end);

  elsif p_gate_id = 'GATE-031' then
    v_ok := not coalesce((public.fn_kernel_paid_provider_gate('openai/gpt-4o-mini')->>'allowed')::boolean, true);
    select count(*) into v_n from public.llm_attempt where created_at > now() - interval '24 hours';
    v_ok := v_ok and (v_n = 0);
    reason := format('GATE-031: paid-provider gate %s; %s llm_attempt row(s) in 24h',
                     case when v_ok then 'refuses every route' else 'ALLOWED a route' end, v_n);

  elsif p_gate_id = 'GATE-032' then
    -- Founder lifted the selective automation hold on 2 Sep 2026 ("lift all previous limits or frozen
    -- gates; the only thing that remains blocked is OpenRouter"), and on 3 Sep 2026 asked for these
    -- gates to be fixed permanently so they stop blocking authorized activation. The ceiling WAS the
    -- stand-down hold; it is now purely a runaway-explosion guard. It is sized ABOVE the whole authorized
    -- cron universe rather than at an arbitrary low number: the company DEFINES 221 cron jobs and the
    -- founder has authorized activating them, so any count up to that whole set is legitimate, not a
    -- runaway. The guard therefore fires only when active crons exceed the full defined set by a clear
    -- margin (a bug spawning brand-new jobs beyond the ~221 known) — 240 — which is what "runaway"
    -- actually means here. This stops the gate reddening on every legitimate cron the activation turns on
    -- (the recurring failure) while still catching an uncontrolled explosion. Recorded in
    -- public.company_stand_down (full resume, 2 Sep 2026).
    select count(*) into v_n from cron.job where active;
    v_ok := (v_n <= 240);
    reason := format('GATE-032: %s active cron job(s) of 221 defined; automation hold lifted by founder 2 Sep 2026, runaway guard 240 (above the full authorized cron set)', v_n);

  elsif p_gate_id in ('GATE-027','GATE-028') then
    -- O03/O07. THE LEGAL AND TAX CURRENCY LEG, AND WHAT IT DELIBERATELY DOES NOT DO.
    --
    -- GATE-027 binds 10 W27 steps and GATE-028 binds 9 W28 steps. Making a source reference a
    -- REQUIRED evidence key would block all 19 on every drive, because fn_phase_d_step_context
    -- resolves no such key -- so nineteen steps would stop for a control that is about the two
    -- steps whose frozen acceptance criteria actually demand it. That is the "tightening a guard
    -- reddens its own probes" shape, and the trade is not worth making here: the HARD boundary for
    -- this control is a10_phase_d_legal_assertion_source on public.phase_d_legal_assertion, where
    -- naming a source is mandatory and a stale one is refused outright.
    --
    -- What this leg does is judge a source WHEN ONE IS NAMED, which is strictly more than the
    -- v_ok := true it replaces, and it says so in the reason either way rather than implying it.
    v_g13_why := btrim(coalesce(p_evidence->>(case when p_gate_id = 'GATE-027'
                                                   then 'tax_source_ref' else 'legal_source_ref' end), ''));
    if v_g13_why <> '' then
      select ls.usable, ls.refusal_code, ls.reason into v_g13_ok, v_g13_code, v_g13_why
        from public.fn_phase_d_legal_source_current(v_g13_why, true) ls;
      v_ok := v_g13_ok;
      if not v_ok then refusal_code := v_g13_code; end if;
      reason := format('%s (%s): declared evidence present [%s], and the %s it cites -- %s',
                       g.gate_id, g.gate_name, array_to_string(c.evidence_keys, ', '),
                       case when p_gate_id = 'GATE-027' then 'tax authority' else 'legal source' end,
                       coalesce(v_g13_why,'(no verdict)'));
    else
      v_ok := true;
      reason := format('%s (%s): all declared evidence is present and non-empty [%s]. No %s was '
                    || 'cited, so no currency test was performed -- said rather than implied. A '
                    || 'legal or tax assertion itself is refused at public.phase_d_legal_assertion '
                    || 'unless it cites a current, authoritative, unsuperseded source.',
                       g.gate_id, g.gate_name, array_to_string(c.evidence_keys, ', '),
                       case when p_gate_id = 'GATE-027' then 'tax_source_ref' else 'legal_source_ref' end);
    end if;

  elsif p_gate_id in ('GATE-022','GATE-023','GATE-024','GATE-025','GATE-026',
                      'GATE-029','GATE-030') then
    v_ok := true;
    reason := format('%s (%s): all declared evidence is present and non-empty [%s]. '
                  || 'The keys are checked; the CONTENT behind them is not yet verifiable from '
                  || 'this database, which is stated rather than implied.',
                     g.gate_id, g.gate_name, array_to_string(c.evidence_keys, ', '));

  else
    state := 'NOT_IMPLEMENTED'; passed := false;
    reason := format('gate %s has no predicate in fn_phase_d_gate_evaluate — blocked', p_gate_id);
    return next; return;
  end if;

  exception when others then
    -- Anything the predicate chain could not READ. Not "anything that went wrong": a predicate
    -- that judges evidence and returns false never arrives here, because returning false is not
    -- an exception.
    state := 'BLOCKED'; passed := false; evidence_absent := true;
    refusal_code := 'gate_read_failed';
    reason := format('gate %s could not READ what it needed to judge: %s (%s). This is not a '
                  || 'refusal -- the gate reached no verdict on the evidence, and a caller must '
                  || 'fix the estate rather than the evidence.',
                     p_gate_id, left(SQLERRM, 160), SQLSTATE);
    return next; return;
  end;

  state := case when v_ok then 'PASSED' else 'BLOCKED' end;
  passed := coalesce(v_ok, false);
  return next;
end $function$
;

update public.phase_b_gate
   set gate_name = 'Organisation structurally valid',
       pass_result = 'Proceed: the organisation the step runs in has no structural violation.',
       fail_result = 'Stop: repair the organisation (fn_phase_a_organization_violations names the violation) before the step runs.',
       required_evidence = 'None from the caller: measured by fn_phase_a_organization_violations() on production.'
 where gate_id = 'GATE-001';

update public.phase_c_gate_binding
   set gate_name = 'Organisation structurally valid',
       evidence = 'phase_b_gate GATE-001 scope=ALL type=hard; predicate retargeted 4 Sep 2026 from the frozen Phase A digest to fn_phase_a_organization_violations() = 0 (phase_e_retire_the_frozen_baseline_boards.sql)'
 where gate_id = 'GATE-001';

update public.phase_d_gate_contract
   set refusal_code = 'gate001_organization_violations',
       evidence_source = 'public.fn_phase_a_organization_violations() — zero rows means the organisation is structurally valid'
 where gate_id = 'GATE-001';

drop function if exists public.fn_phase_b_baseline_drift();
drop function if exists public.fn_phase_a_baseline_drift();

update public.phase_c_component
   set activation_state = 'inactive', classification = 'INTENTIONALLY_RETIRED', external_entry = 'no',
       gap = 'routine dropped 4 Sep 2026; no object remains', repair_or_keep_action = 'retired',
       evidence = 'phase_e_retire_the_frozen_baseline_boards.sql 2026-09-04: frozen-baseline drift board; the phase freezes were removed 2 Sep 2026; its three routine callers retargeted to fn_phase_a_organization_violations; 0 cron/trigger/view/RLS/repo callers remain; function dropped'
 where component_id in ('dbfn:fn_phase_a_baseline_drift()', 'dbfn:fn_phase_b_baseline_drift()');
delete from public.phase_c_component_exposure_scope
 where component_id in ('dbfn:fn_phase_a_baseline_drift()', 'dbfn:fn_phase_b_baseline_drift()');

do $ctl$
declare v_left int; v_bad text; v_gate record;
begin
  select count(*) into v_left from pg_proc
   where pronamespace = 'public'::regnamespace
     and proname in ('fn_phase_a_baseline_drift', 'fn_phase_b_baseline_drift');
  if v_left > 0 then raise exception 'phase_e_retire_the_frozen_baseline_boards: % drift routine(s) still present', v_left; end if;

  select string_agg(check_name, ',') into v_bad from public.fn_phase_c_invariants()
   where check_name in ('phase_a_drift', 'phase_b_drift', 'active_departments', 'canonical_roles', 'category_overlays');
  if v_bad is not null then raise exception 'fn_phase_c_invariants still carries mirror rows: %', v_bad; end if;
  if not exists (select 1 from public.fn_phase_c_invariants() where check_name = 'organization_structural_violations' and ok) then
    raise exception 'fn_phase_c_invariants: organization_structural_violations is missing or red';
  end if;

  select string_agg(check_name, ',') into v_bad from public.fn_phase_b_invariants()
   where check_name like 'count.%' or check_name = 'phase_a.baseline_drift_rows';
  if v_bad is not null then raise exception 'fn_phase_b_invariants still carries mirror rows: %', v_bad; end if;
  if not exists (select 1 from public.fn_phase_b_invariants() where check_name = 'phase_a.organization_violations' and ok) then
    raise exception 'fn_phase_b_invariants: phase_a.organization_violations is missing or red';
  end if;

  select * into v_gate from public.fn_phase_d_gate_evaluate('GATE-001', '{}'::jsonb);
  if v_gate.passed is not true or v_gate.reason not like 'GATE-001: the organisation has 0 structural%' then
    raise exception 'GATE-001 after retarget: state=% passed=% reason=%', v_gate.state, v_gate.passed, v_gate.reason;
  end if;
  raise notice 'proof: drift routines gone; fn_phase_c_invariants and fn_phase_b_invariants carry no mirror row; GATE-001 = %', v_gate.reason;
end $ctl$;

commit;
