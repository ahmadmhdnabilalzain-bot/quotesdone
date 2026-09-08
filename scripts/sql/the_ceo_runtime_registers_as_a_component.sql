-- ceo_agent REGISTERS AS A COMPONENT, because the gate that demands it is still live today.
--
-- phase_c_components_are_owned asserts that every deployed edge function in the repository has a row
-- in public.phase_c_component: nothing runs in this estate without an owner. Deploying ceo_agent
-- turned that check red with actual: 1 — exactly the defect it exists to catch, working correctly on
-- the very function that was built to replace the machinery it belongs to.
--
-- THE AWKWARDNESS IS WORTH STATING PLAINLY rather than working around. phase_c_component is part of
-- the Phase C programme the founder has ruled irrelevant, and it is on the drop list. Registering a
-- brand-new function in a registry that is about to be deleted looks like wasted motion.
--
-- It is not, for two reasons. The registry governs TODAY: while the check is live and green it is
-- telling the truth about the estate, and a gate that is red "because we are about to delete it
-- anyway" is a gate nobody reads for the week it stays red. And the alternative — softening or
-- skipping the check to let an unregistered function through — is the one move this estate has
-- learned never to make: a check that passes while the thing it checks is untrue converts an absence
-- into confidence.
--
-- When Phase C goes, this check retires WITH ITS SUBJECT and this row goes with it. What replaces it
-- is public.function_owner, which already records ceo_agent as owned by 'ceo' and is measured
-- against the LIVE deployment list by every_deployed_function_has_an_owner.
--
--   node scripts/apply_sql.mjs scripts/sql/the_ceo_runtime_registers_as_a_component.sql --apply --ddl

begin;

insert into public.phase_c_component (
  component_id, component_type, source_path_or_db_object, activation_state, classification,
  workflow_id, accountable_role_id,
  entry_method, external_entry, mutates_state, authority_class, trace_policy_id,
  canonical_system_actor, current_actor, idempotency_strategy, retry_policy,
  evidence, repair_or_keep_action, measured_at
) values (
  'edge:ceo_agent', 'edge_function', 'supabase/functions/ceo_agent/index.ts', 'deployed',
  'ACTIVE_INTERNAL_CALLER',
  -- workflow_id is NOT NULL and carries no foreign key. OUT_OF_SCOPE is already an established value
  -- in this column and it is the truthful one: this function belongs to no workflow, because there
  -- are no workflows. Inventing a plausible W-number to satisfy a constraint would put a fact into
  -- the registry that is not true.
  'OUT_OF_SCOPE',
  -- A CHECK on this table refuses any state-mutating active component with no accountable role, and
  -- it is right to: something that changes the world has to name who answers for it. The CEO does.
  'ceo',
  'POST with a scoped internal credential (fn.founder_channel) or the founder''s admin JWT; the '
    || 'gateway also requires a project JWT in front of that',
  'authenticated_only',
  true,
  'routine_operational_decision',
  'TRACE-SYSTEM-EXECUTION',
  'system.task_engine',
  'service_role',
  'request:slug:business_key',
  'caller_retry_with_same_key',
  'The CEO seat''s runtime. Actions: command (the founder submits an instruction), inbox (what the '
    || 'seat is carrying), task (close work with evidence), decide (record an approval). Replaces '
    || 'os_api''s secretary_chat and founder_command actions.',
  'Keep. It is the founder''s command channel and a precondition for deleting os_api.',
  now()
)
on conflict (component_id) do update
  set activation_state = excluded.activation_state,
      evidence         = excluded.evidence,
      measured_at      = excluded.measured_at;

commit;
