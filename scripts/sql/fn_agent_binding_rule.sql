-- THE BINDING RULE THAT SIZES THE ROSTER (MASTER_PLAN §3, 4 Sep 2026).
--
--   An agent exists only if it OWNS a decision that fires: one event it consumes, one action it can
--   execute, and one playbook/rule it applies. No owned firing decision -> park the persona.
--
-- One STABLE instrument, measured on production, the same every run (the connectivity register's
-- shape). Three questions per active persona, each answered from the table that makes it true:
--   has_event     an ACTIVE row in event_subscription for the agent key — the dispatcher delivers
--                 only through that table, so nothing else counts as "consumes an event".
--   has_executor  the persona is the actor of a live runtime workflow step whose action_class has an
--                 active org_action_executor (the queue can perform it), OR its canonical role is
--                 accountable for a runtime component that fires on its own — a cron job, an edge
--                 function, a database trigger or a runtime workflow definition. A component of any
--                 other kind (a table, a plain function, a route) does not fire and is not counted.
--   has_playbook  a runtime-eligible ops_knowledge record scoped to one of the packaged roles the
--                 persona holds in org_role_identity (scope_type role/agent). Department knowledge
--                 is shared and is deliberately NOT counted: the rule asks what THIS seat applies.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_agent_binding_rule.sql --apply --ddl
create or replace function public.fn_agent_binding_rule()
returns table (agent_key text, department text, has_event boolean, has_executor boolean,
               has_playbook boolean, passes boolean, event_types text, executor_evidence text)
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  with a as (
    select ag.agent_key, ag.department,
           (select r.role_id from public.org_role r
             where r.runtime_agent_key = ag.agent_key and r.status = 'active'
             order by r.role_id limit 1) role_id
      from public.org_agents ag
     where ag.active
  ),
  ev as (
    select s.agent_key, string_agg(s.event_type, ', ' order by s.event_type) types
      from public.event_subscription s where s.active group by s.agent_key
  ),
  steps as (
    select coalesce(public.fn_org_agent_resolve(s.actor_role),
                    public.fn_org_role_agent(public.fn_org_role_resolve(s.actor_role))) agent_key,
           string_agg(distinct s.workflow_key || '#' || s.step_no || ':' || s.action_class, ', ') ev
      from public.workflow_step s
      join public.workflow w on w.workflow_key = s.workflow_key and w.active
      join public.org_action_executor x on x.action_class = s.action_class and x.active
     where s.actor_role is not null and s.actor_role not in ('owner', 'Director')
     group by 1
  ),
  comps as (
    select c.accountable_role_id role_id,
           string_agg(c.component_id, ', ' order by c.component_id) ev
      from public.phase_c_component c
     where c.activation_state in ('active', 'deployed')
       and c.component_type in ('cron_job', 'edge_function', 'database_trigger', 'runtime_workflow_definition')
     group by 1
  ),
  pb as (
    select i.agent_key
      from public.org_role_identity i
     where exists (select 1 from public.ops_knowledge k
                    where k.runtime_eligible and k.scope_type in ('role', 'agent')
                      and k.scope_key = i.packaged_role_id)
     group by i.agent_key
  )
  select a.agent_key, a.department,
         ev.agent_key is not null                                   as has_event,
         (steps.agent_key is not null or comps.role_id is not null) as has_executor,
         pb.agent_key is not null                                   as has_playbook,
         (ev.agent_key is not null and (steps.agent_key is not null or comps.role_id is not null)
          and pb.agent_key is not null)                             as passes,
         ev.types                                                   as event_types,
         concat_ws(' | ', steps.ev, comps.ev)                       as executor_evidence
    from a
    left join ev    on ev.agent_key = a.agent_key
    left join steps on steps.agent_key = a.agent_key
    left join comps on comps.role_id = a.role_id
    left join pb    on pb.agent_key = a.agent_key
   order by a.department, a.agent_key;
$function$;

revoke execute on function public.fn_agent_binding_rule() from public, anon;
