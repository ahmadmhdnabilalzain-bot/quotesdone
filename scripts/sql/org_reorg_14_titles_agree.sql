-- REORGANISING THE AGENT COMPANY — the title an employee shows and the title it answers to.
--
-- fn_org_agent_resolve has a TITLE arm: 30 of the 66 workflow actor_role values are job titles, so
-- "Marketplace Director" ought to reach `procurement`. It did not, because org_agents.title still
-- said "Procurement Director" — the display name moved to org_role.display_name and the runtime
-- row was left behind. So the canonical name resolved and the canonical TITLE did not, which is
-- the same identifier disagreeing with itself depending on which layer you ask.
--
-- Both directions are made true rather than one: the runtime title becomes the canonical display
-- name, and every title it previously answered to is recorded as an alias, so nothing that already
-- addressed an employee by its old title stops working.

begin;

-- 1. Preserve the old titles as aliases FIRST, while org_agents still holds them.
insert into public.org_agent_alias (alias, agent_key, reason)
select a.title, a.agent_key,
       'previous job title, kept addressable by the 14 Aug 2026 reorganisation'
  from public.org_agents a
  join public.org_role r on r.runtime_agent_key = a.agent_key and r.status = 'active'
 where a.active and coalesce(a.title,'') <> '' and a.title <> r.display_name
   and not exists (select 1 from public.org_agent_alias x where x.alias = a.title)
   and not exists (select 1 from public.org_agents g where g.agent_key = a.title)
on conflict (alias) do nothing;

-- 2. The runtime title becomes the canonical display name.
update public.org_agents a set title = r.display_name
  from public.org_role r
 where r.runtime_agent_key = a.agent_key and r.status = 'active'
   and a.active and a.title is distinct from r.display_name;

commit;
