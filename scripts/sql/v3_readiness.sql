-- Stage 13 — operational readiness, derived from evidence rather than declared.
--
-- Each rung is a fact that can be checked, and a role sits at the highest rung whose
-- evidence exists. No rung is awarded because the stage above it was built: an agent that
-- has never been given a training case cannot be `training_passed`, and nothing in a builder
-- session may reach `certified_for_defined_role_scope` — that word belongs to the independent
-- evaluator and to nobody else.

create or replace function fn_role_readiness_recompute() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_counts jsonb;
begin
  with fact as (
    select
      i.agent_key, i.packaged_role_id, a.active, a.department,
      exists (select 1 from ops_knowledge k
               where k.role_key = i.packaged_role_id and k.runtime_eligible
                 and k.supersession_state = 'current')                         as has_knowledge,
      -- an entry point: a cron'd runner, a department lead, or a brain agent
      exists (select 1 from org_departments d
               where d.lead_agent = i.agent_key or d.brain_agent = i.agent_key) as is_named_runner,
      exists (select 1 from agent_runs r where r.agent = i.agent_key)           as has_run,
      exists (select 1 from org_action_executor e
               where e.active and (e.department = a.department or e.target = i.agent_key)) as has_tools,
      exists (select 1 from ops_knowledge k
               where k.record_type = 'live_data_binding'
                 and (k.scope_type = 'company' or k.dept_key = a.department))   as has_live_data,
      exists (select 1 from agent_context_retrieval c where c.agent_key = i.agent_key)
        or exists (select 1 from agent_actions x where x.agent = i.agent_key)   as traceable,
      exists (select 1 from agent_remediation m
               where m.agent_key = i.agent_key and m.status = 'passed')         as trained,
      exists (select 1 from agent_remediation m
               where m.agent_key = i.agent_key and m.blocks_autonomy and m.status <> 'passed') as blocked,
      exists (select 1 from org_action_executor e
               where e.active and e.department = a.department
                 and (e.risk_tier in ('high','medium') or e.notifies_human))    as consequential
    from org_role_identity i
    join org_agents a on a.agent_key = i.agent_key
  ), rung as (
    select agent_key, packaged_role_id,
      case
        when not active                       then 'blocked'
        when blocked                          then 'restricted_to_advisory'
        when not has_knowledge                then 'blocked'
        when trained and not blocked          then 'independent_certification_pending'
        when consequential and not trained    then 'restricted_to_advisory'
        when traceable and has_live_data and has_tools then 'decision_trace_connected'
        when has_live_data and has_tools      then 'live_data_connected'
        when has_tools                        then 'tools_connected'
        when is_named_runner or has_run       then 'runtime_mapped'
        else 'knowledge_imported'
      end as readiness
    from fact
  )
  update org_role_identity i set readiness = r.readiness, updated_at = now()
    from rung r
   where i.agent_key = r.agent_key and i.packaged_role_id = r.packaged_role_id
     and i.readiness is distinct from r.readiness;

  select jsonb_object_agg(readiness, n) into v_counts
    from (select readiness, count(*) n from org_role_identity group by 1) s;

  -- The one status a builder session may never assign.
  if exists (select 1 from org_role_identity where readiness = 'certified_for_defined_role_scope') then
    raise exception 'certified_for_defined_role_scope was assigned without an independent evaluator';
  end if;

  return jsonb_build_object('recomputed_at', now(), 'counts', v_counts,
    'ceiling', 'independent_certification_pending');
end $$;

revoke all on function fn_role_readiness_recompute() from public;

-- Category identities follow the same rule, one rung simpler: they are on-demand overlays,
-- so the question is whether their route resolves and their corpus is retrievable.
create or replace function fn_category_readiness_recompute() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  update org_category_identity c
     set readiness = case
       when not exists (select 1 from ops_knowledge k where k.category_key = c.category_key
                          and k.runtime_eligible and k.supersession_state = 'current') then 'blocked'
       when (select (fn_category_checklist(r.expected_catalog_slug, r.catalog_name, null)->>'route_resolved')::boolean
               from kb_operational_route r where r.catalog_num = c.catalog_num) then 'decision_trace_connected'
       else 'knowledge_imported' end,
         updated_at = now();
  select jsonb_object_agg(readiness, n) into v
    from (select readiness, count(*) n from org_category_identity group by 1) s;
  return jsonb_build_object('counts', v);
end $$;

revoke all on function fn_category_readiness_recompute() from public;
