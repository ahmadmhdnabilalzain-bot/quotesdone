-- THE ROLE RESOLVED AND THE EMPLOYEE DID NOT.
--
-- Phase A merged partnerships + government_relations and stood gov_relations_mgr down. It aliased
-- the two ROLE ids to the merged role in org_role_alias — and stopped there. org_agent_alias, which
-- is what fn_org_agent_resolve reads, got nothing.
--
-- The consequence, found by scripts/checks/org_reorg_behaviour.test.mjs and not by any failure:
-- fn_org_agent_resolve('gov_relations_mgr') returns NULL, so the employee resolves to itself, and
-- fn_agent_context_v3('gov_relations_mgr') still assembles a full context. A context is what lets
-- an employee act. An employee that was merged away four minutes earlier could still have been
-- addressed by its physical key and would have answered.
--
-- This is the estate's own recurring lesson, and I walked into it: role_id is the clear name,
-- agent_key is the physical one, AND BOTH MUST RESOLVE. Aliasing one of the two is not aliasing.
--
-- Note which direction this goes. The role alias points at the merged ROLE
-- (strategic_partnerships_government_relations_manager); the agent alias points at the surviving
-- runtime EMPLOYEE (partnerships_mgr). They are different vocabularies for the same merge, which is
-- exactly why doing one and not the other left no visible error.
insert into public.org_agent_alias (alias, agent_key, reason)
values ('gov_relations_mgr', 'partnerships_mgr',
        'Phase A merge, 15 Aug 2026: Government & Enterprise Relations merged into Strategic Partnerships & Government Relations. The physical employee that survived is partnerships_mgr.')
on conflict (alias) do update set agent_key = excluded.agent_key, reason = excluded.reason;

do $$
declare v int; v_who text;
begin
  -- the merged employee now resolves to the survivor rather than to itself
  if coalesce(public.fn_org_agent_resolve('gov_relations_mgr'), 'gov_relations_mgr') <> 'partnerships_mgr'
    then raise exception 'FOLLOW-UP: gov_relations_mgr does not resolve to partnerships_mgr'; end if;

  -- and no inactive employee anywhere assembles a context under its own key
  select count(*), string_agg(a.agent_key, ', ') into v, v_who from public.org_agents a
   where not a.active
     and coalesce(public.fn_org_agent_resolve(a.agent_key), a.agent_key) = a.agent_key
     and (public.fn_agent_context_v3(a.agent_key)->>'error') is null;
  if v <> 0 then raise exception 'FOLLOW-UP: % inactive employee(s) still assemble a context: %', v, v_who; end if;

  -- an ACTIVE employee must still get one; a fix that silences the first check by breaking
  -- context assembly for everybody would pass the line above and be far worse.
  select count(*) into v from public.org_agents a
   where a.active and (public.fn_agent_context_v3(a.agent_key)->>'error') is not null;
  if v <> 0 then raise exception 'FOLLOW-UP: % ACTIVE employee(s) were refused a context', v; end if;

  raise notice 'PHASE A FOLLOW-UP: the merged employee resolves; no inactive employee assembles a context.';
end $$;
