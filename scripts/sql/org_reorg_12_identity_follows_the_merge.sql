-- REORGANISING THE AGENT COMPANY — a merged employee's packaged IDENTITY must follow it, not just
-- its address.
--
-- The merge transferred addressing (org_agent_alias, so every caller still reaches the survivor)
-- and it transferred the work (tasks, KPIs, tools). It did not transfer org_role_identity, which is
-- how the V3 knowledge package addresses a role.
--
-- fn_agent_context_v3 collects v_role_ids from org_role_identity for the agent, then retrieves
-- role-scoped knowledge with `role_key = any(v_role_ids)`. A packaged role held ONLY by an agent
-- that is now inactive is therefore addressed by nobody, and its records are unreachable through
-- the role layer. Measured on production, three of the 96 packaged roles and 80 runtime-eligible
-- knowledge records:
--
--   supplier-knowledge-analyst-controller                 26 records  (supplier_intel_analyst)
--   data-analytics-and-intelligence-operations-specialist 27 records  (analytics_director)
--   data-analytics-and-intelligence-reviewer-auditor      27 records  (analytics_director)
--
-- Nothing failed. The retrieval simply returned fewer rows, which is the failure mode this whole
-- reorganisation keeps finding: an absent input that looks like a quiet system.
--
-- WHERE EACH IDENTITY GOES IS DECIDED BY ITS ARCHETYPE, NOT BY THE ALIAS ALONE.
--
-- The first version of this file sent every orphaned identity to whichever agent org_agent_alias
-- names as the survivor. fn_role_identity_isolation_guard refused it, and it was right:
-- analytics_director's survivor is intel_director, which already holds the data_analytics DIRECTOR
-- and OPERATIONS-SPECIALIST identities, so handing it the REVIEWER-AUDITOR one would have made a
-- single agent both producer and independent reviewer of the same packaged department — the exact
-- separation this reorganisation spent the day building into review, release and incident fixing.
--
-- So a reviewer-auditor identity goes to an agent whose canonical runtime_mode is
-- `independent_reviewer` in the surviving department; everything else goes to the alias survivor.
-- That is the guard's `isolate` outcome, reached by routing rather than by signing a waiver.
--
-- (The guard itself is not on production yet — it lives on another session's branch and only on
-- staging. This file is written to satisfy it on both, so the two do not disagree when that lands.)

begin;

with orphan as (
  select distinct i.packaged_role_id, i.packaged_department, i.archetype, i.readiness,
         i.package_version, i.agent_key as dead_agent
    from public.org_role_identity i
    join public.org_agents dead on dead.agent_key = i.agent_key and not dead.active
   where not exists (select 1 from public.org_role_identity x
                       join public.org_agents a on a.agent_key = x.agent_key and a.active
                      where x.packaged_role_id = i.packaged_role_id)
),
survivor as (
  select o.*, al.agent_key as alias_agent, live.department as dept
    from orphan o
    join public.org_agent_alias al on al.alias = o.dead_agent
    join public.org_agents live on live.agent_key = al.agent_key and live.active
),
routed as (
  select s.*,
         case when s.archetype = 'reviewer-auditor'
              then (select r.runtime_agent_key from public.org_role r
                     where r.status = 'active' and r.runtime_mode = 'independent_reviewer'
                       and r.primary_department_id = s.dept
                       and r.runtime_agent_key is not null
                     order by r.role_id limit 1)
              else s.alias_agent end as target
    from survivor s
)
insert into public.org_role_identity
  (agent_key, packaged_role_id, packaged_department, archetype, mapping_type, readiness,
   package_version, updated_at)
select r.target, r.packaged_role_id, r.packaged_department, r.archetype,
       -- The receiver carries it as a SECOND HAT, which is what runtime_composite already means
       -- here: an archetype with no separate employee, held by one that has room for it.
       'runtime_composite', r.readiness, r.package_version, now()
  from routed r
 where r.target is not null
on conflict (agent_key, packaged_role_id) do nothing;

commit;
