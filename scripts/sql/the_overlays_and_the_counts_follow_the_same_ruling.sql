-- THE OVERLAYS AND THE COUNTS FOLLOW THE SAME RULING
--
-- Founder ruling, 7 September 2026: "what is more recent is right."
--
-- Re-recording the reporting map took drift from 167 rows to 68. The remaining 68 are four things and
-- every one is the same question the ruling already answered.
--
--   51  OVERLAY ESCALATION. Each overlay's recorded broad-domain escalation is checked against the
--       live role's escalation_targets. Measured: the map names supplier_matching_dispatch_operator;
--       live the targets are spec_construction (on_demand_specialist), marketplace_director
--       (scheduled_manager) and inquiry_router (event_driven_operator). The recorded owner is set to
--       the MANAGER among them, because escalation goes up: a specialist and an operator are peers to
--       escalate FROM, not to.
--
--    3  GOVERNANCE OWNERS. The arm hardcodes category_curator, taxonomy_manager and
--       knowledge_validator and requires each to be an active role. Measured: all three are RETIRED,
--       and knowledge_director is active and holds that ground. The three names are the stale thing.
--       Replaced with a table, so the next reorganisation edits a row instead of a function body.
--
--   13  DUPLICATE ACTIVE IDENTITY. Thirteen live roles each stand in for several canonical roles.
--       That IS the consolidation, which the ruling makes correct. Reporting it as drift says the
--       approved structure disagrees with itself.
--
--    1  THE COUNT. The arm asserts 90 standing roles; the table holds 75 and has held 75 throughout -
--       the re-recording inserted and deleted nothing. The 90 describes a shape that no longer exists.
--
-- WHAT THIS DELIBERATELY DOES NOT DO. It does not delete the duplicate guard: a guard that stops
-- noticing consolidations would miss the NEXT one, which may be nobody's decision. The thirteen
-- ruled-on consolidations are RECORDED and exempted by name; any duplicate outside that set still
-- fires. And the count guard is not removed, only corrected to 75, so it still fires the moment the
-- table is emptied - the failure it exists to catch.

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. The consolidations this ruling approves, recorded by name.
-- ---------------------------------------------------------------------------------------------

create table if not exists public.phase_c_approved_consolidation (
  live_role_id     text primary key,
  canonical_count  int  not null check (canonical_count > 1),
  canonical_roles  text not null,
  approved_by      text not null,
  approved_at      timestamptz not null default now(),
  note             text
);

comment on table public.phase_c_approved_consolidation is
  'Live roles that legitimately stand in for several canonical roles. Recorded so the duplicate-identity guard can tell a ruled-on consolidation from a new, unexplained one.';

insert into public.phase_c_approved_consolidation
  (live_role_id, canonical_count, canonical_roles, approved_by, note)
select a.live_role_id, count(*)::int,
       string_agg(a.canonical_role_id, ', ' order by a.canonical_role_id),
       'Founder ruling 2026-09-07: what is more recent is right.',
       'Present in the live organisation on 7 Sep 2026 and approved by that ruling.'
  from public.phase_c_reporting_authority a
 group by a.live_role_id
having count(*) > 1
on conflict (live_role_id) do update set
  canonical_count = excluded.canonical_count,
  canonical_roles = excluded.canonical_roles,
  approved_by     = excluded.approved_by,
  approved_at     = now();

-- ---------------------------------------------------------------------------------------------
-- 2. The governance owners, as data rather than three names inside a function.
-- ---------------------------------------------------------------------------------------------

create table if not exists public.phase_c_governance_owner (
  responsibility text primary key,
  owner_role_id  text not null,
  recorded_by    text not null,
  recorded_at    timestamptz not null default now(),
  note           text
);

comment on table public.phase_c_governance_owner is
  'Who owns each category-governance responsibility. Was three hardcoded role names in fn_phase_c_reporting_map_drift; all three retired and the check kept failing on a list nobody could edit without changing a function.';

insert into public.phase_c_governance_owner (responsibility, owner_role_id, recorded_by, note) values
  ('category_curation',   'knowledge_director', 'Founder ruling 2026-09-07',
   'Was category_curator, now retired. knowledge_director is the active role holding this ground.'),
  ('taxonomy_management', 'knowledge_director', 'Founder ruling 2026-09-07',
   'Was taxonomy_manager, now retired.'),
  ('knowledge_validation','knowledge_director', 'Founder ruling 2026-09-07',
   'Was knowledge_validator, now retired.')
on conflict (responsibility) do update set
  owner_role_id = excluded.owner_role_id, recorded_by = excluded.recorded_by,
  recorded_at = now(), note = excluded.note;

-- ---------------------------------------------------------------------------------------------
-- 3. The overlay escalation, re-recorded to the MANAGER among the live targets.
-- ---------------------------------------------------------------------------------------------

update public.phase_c_overlay_binding o
   set broad_domain_escalation_role_id = pick.role_id
  from (
    select b.overlay_id,
           (select t
              from unnest(r.escalation_targets) t
              join public.org_role m on m.role_id = t and m.status = 'active'
             -- escalation goes UP: prefer a manager, then an operator, then anything present
             order by case m.runtime_mode
                        when 'scheduled_manager'    then 1
                        when 'event_driven_operator' then 2
                        else 3 end, t
             limit 1) as role_id
      from public.phase_c_overlay_binding b
      join public.org_role r on r.role_id = b.live_role_id
  ) pick
 where pick.overlay_id = o.overlay_id
   and pick.role_id is not null
   and pick.role_id is distinct from o.broad_domain_escalation_role_id;

commit;

-- ---------------------------------------------------------------------------------------------
-- 4. The three arms that hardcoded a shape which no longer exists.
--    Extracted from the LIVE definition and patched in place, so none of the other 21 arms can be
--    lost the way they were when I rewrote this function from a partial reading an hour ago.
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_phase_c_reporting_map_drift()
 RETURNS TABLE(subject text, role_id text, approved text, live text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- FIRST, THE SUBJECT ITSELF. Every other branch below reads phase_c_reporting_authority, so an
  -- empty table would make all of them return nothing and the check would report perfect agreement
  -- with an authority that is no longer there. Absent input must not score as satisfied: the row
  -- count is asserted against the founder-approved shape before anything is compared to it.
  select 'authority_not_recorded', 'phase_c_reporting_authority',
         '75 standing roles', count(*)::text
    from public.phase_c_reporting_authority having count(*) <> 75
  union all
  select 'overlay_authority_not_recorded', 'phase_c_overlay_binding',
         '86 category overlays', count(*)::text
    from public.phase_c_overlay_binding having count(*) <> 86
  union all
  -- a standing role the map names that the organisation cannot resolve
  select 'unresolved_role', a.canonical_role_id, a.live_role_id, '(no active org_role)'
    from public.phase_c_reporting_authority a
   where not exists (select 1 from public.org_role r
                      where r.role_id = a.live_role_id and r.status = 'active')
  union all
  select 'primary_manager', a.canonical_role_id, a.manager_role_id, coalesce(r.manager_role_id,'founder')
    from public.phase_c_reporting_authority a
    join public.org_role r on r.role_id = a.live_role_id
   where coalesce(r.manager_role_id,'founder') is distinct from a.manager_role_id
  union all
  select 'primary_department', a.canonical_role_id, a.department_id, r.primary_department_id
    from public.phase_c_reporting_authority a
    join public.org_role r on r.role_id = a.live_role_id
   where r.primary_department_id is distinct from a.department_id
  union all
  select 'role_class', a.canonical_role_id, a.role_class||'/'||a.runtime_mode, r.runtime_mode
    from public.phase_c_reporting_authority a
    join public.org_role r on r.role_id = a.live_role_id
    join (select live_role_id, count(*) canonical_count
            from public.phase_c_reporting_authority group by 1) f
      on f.live_role_id = a.live_role_id
   where r.runtime_mode is distinct from a.runtime_mode
     -- COMPARED ONLY WHERE THE COMPARISON MEANS SOMETHING. Thirteen live roles absorbed 34 canonical
     -- ones; comparing an absorbed specialist's approved class against the absorbing director's
     -- runtime_mode reported 18 mismatches, every one of them a false positive.
     and f.canonical_count = 1

  union all
  -- and the absorbed ones stay VISIBLE under their own subject rather than vanishing
  select 'role_class_not_comparable', a.canonical_role_id, a.role_class||'/'||a.runtime_mode,
         format('absorbed into %s, which carries %s canonical roles', a.live_role_id, f.canonical_count)
    from public.phase_c_reporting_authority a
    join public.org_role r on r.role_id = a.live_role_id
    join (select live_role_id, count(*) canonical_count
            from public.phase_c_reporting_authority group by 1) f
      on f.live_role_id = a.live_role_id
   where r.runtime_mode is distinct from a.runtime_mode
     and f.canonical_count > 1
  union all
  -- the department head the map names must be the head the department records
  select 'department_head', a.canonical_role_id, a.department_head_role_id, coalesce(d.lead_agent,'(none)')
    from public.phase_c_reporting_authority a
    join public.org_departments d on d.dept_key = a.department_id
    left join public.org_role h on h.role_id = a.department_head_role_id
   where d.lead_agent is distinct from h.runtime_agent_key
  union all
  -- the path to the founder, WALKED in the live graph rather than assumed, and compared with the
  -- approved path. This is also the cycle check: a chain that loops never reaches the founder, so
  -- the walk returns null and the row is reported.
  select 'reporting_path', a.canonical_role_id, a.reporting_path, coalesce(w.walked,'(never reaches the founder)')
    from public.phase_c_reporting_authority a
    left join lateral (
      with recursive up(cur, depth, path) as (
        select a.live_role_id, 0, a.live_role_id
        union all
        select coalesce(r.manager_role_id,'founder'), u.depth+1,
               u.path||' > '||coalesce(r.manager_role_id,'founder')
          from up u join public.org_role r on r.role_id = u.cur and r.status='active'
         where u.depth < 20 and u.cur <> 'founder')
      select path as walked from up where cur = 'founder' order by depth limit 1
    ) w on true
   where w.walked is distinct from a.reporting_path
  union all
  -- one live role standing in for two canonical roles
  select 'duplicate_active_identity', x.live_role_id, 'one canonical role', x.n::text
    from (select live_role_id, count(*) n from public.phase_c_reporting_authority
           group by 1 having count(*) > 1) x
   where not exists (select 1 from public.phase_c_approved_consolidation c
                      where c.live_role_id = x.live_role_id and c.canonical_count = x.n)
  union all
  select 'self_management', a.canonical_role_id, a.manager_role_id, r.manager_role_id
    from public.phase_c_reporting_authority a
    join public.org_role r on r.role_id = a.live_role_id
   where r.manager_role_id = r.role_id
  union all
  -- An identity that cannot act, or one that acts as an employee nobody models.
  --
  -- runtime_enabled=false is treated separately from the rest, and deliberately so. Phase A
  -- deferred product_ux_designer's tools, knowledge, KPI and authority to a later phase with the
  -- founder's approval, and switching the role OFF is the correct consequence of that deferral —
  -- a role left enabled with no tools is the worse state, not the better one. So a disabled role
  -- is reported unless fn_phase_a_deferred_items() is currently carrying it. That exemption is not
  -- a hole: it is checked against the live deferral list on every call, so the moment the deferral
  -- is closed — or the moment any OTHER role is switched off — this fires. A missing agent key, an
  -- agent absent from org_agents, or an inactive agent are never exempt.
  select 'identity_cannot_act', a.canonical_role_id, 'an active runtime identity',
         coalesce(r.runtime_agent_key,'(none)')
           || case when r.runtime_enabled then '' else ' runtime_enabled=false' end
           || case when g.agent_key is null then ' not in org_agents'
                   when g.active is not true then ' agent inactive' else '' end
    from public.phase_c_reporting_authority a
    join public.org_role r on r.role_id = a.live_role_id
    left join public.org_agents g on g.agent_key = r.runtime_agent_key
   where r.runtime_agent_key is null
      or g.agent_key is null
      or g.active is not true
      or (r.runtime_enabled is not true
          and not exists (select 1 from public.fn_phase_a_deferred_items() d
                           where d.role_id = r.role_id))
  union all
  -- OVERLAYS: the governance facts the founder's instruction lists, one row per failing overlay
  select 'overlay_unbound', o.overlay_id, 'a live category overlay', coalesce(o.live_role_id,'(none)')
    from public.phase_c_overlay_binding o
   where not exists (select 1 from public.org_role r
                      where r.role_id = o.live_role_id and r.status='active'
                        and r.runtime_mode='knowledge_overlay')
  union all
  select 'overlay_department', o.overlay_id, 'marketplace', r.primary_department_id
    from public.phase_c_overlay_binding o join public.org_role r on r.role_id = o.live_role_id
   where r.primary_department_id is distinct from 'marketplace'
  union all
  select 'overlay_accountable_manager', o.overlay_id, 'marketplace_director reachable',
         array_to_string(r.escalation_targets,'+')
    from public.phase_c_overlay_binding o join public.org_role r on r.role_id = o.live_role_id
   where not ('marketplace_director' = any(r.escalation_targets))
  union all
  select 'overlay_invocation_role', o.overlay_id, 'inquiry_router', coalesce(o.invocation_role_id,'(none)')
    from public.phase_c_overlay_binding o
   where o.invocation_role_id is distinct from 'inquiry_router'
  union all
  select 'overlay_result_returns_to', o.overlay_id, 'rfq_qualification_manager',
         coalesce(o.result_returns_to_role_id,'(none)')
    from public.phase_c_overlay_binding o
   where o.result_returns_to_role_id is distinct from 'rfq_qualification_manager'
  union all
  select 'overlay_returns_unreachable', o.overlay_id, 'rfq_qualification_manager in handoff_targets',
         array_to_string(r.handoff_targets,'+')
    from public.phase_c_overlay_binding o join public.org_role r on r.role_id = o.live_role_id
   where not ('rfq_qualification_manager' = any(r.handoff_targets))
  union all
  select 'overlay_broad_domain_escalation', o.overlay_id,
         coalesce(o.broad_domain_escalation_role_id,'(unrecorded)'), array_to_string(r.escalation_targets,'+')
    from public.phase_c_overlay_binding o join public.org_role r on r.role_id = o.live_role_id
   where o.broad_domain_escalation_role_id is null
      or not (o.broad_domain_escalation_role_id = any(r.escalation_targets))
  union all
  -- the three governance owners the map names must exist and be able to act
  select 'overlay_governance_owner', g.responsibility, g.owner_role_id, 'missing or not active'
    from public.phase_c_governance_owner g
   where not exists (select 1 from public.org_role r
                      where r.role_id = g.owner_role_id and r.status='active')
  union all
  -- an overlay that could decide something the map forbids it
  select 'overlay_authority', o.overlay_id, 'advisory, holding no runtime employee',
         r.authority_level||coalesce(' as '||r.runtime_agent_key,'')
    from public.phase_c_overlay_binding o join public.org_role r on r.role_id = o.live_role_id
   where r.authority_level <> 'advisory' or r.runtime_agent_key is not null
  union all
  select 'overlay_states_no_money_limit', o.overlay_id, 'cannot move money or decide a refund',
         'no such forbidden_decision'
    from public.phase_c_overlay_binding o join public.org_role r on r.role_id = o.live_role_id
   where not exists (select 1 from unnest(r.forbidden_decisions) f where f ilike '%money%')
  union all
  -- THE CHAIN OF COMMAND. Normal autonomous work may not route through the founder or the Chief of
  -- Staff. The two founder-facing workflows are the declared exception — W01 founder mandate to
  -- company objectives, W02 company target miss and corrective management — and they are named
  -- rather than pattern-matched, so a new workflow cannot quietly join them.
  select 'autonomous_work_routes_through_chief_of_staff', s.step_id,
         'an accountable department role', s.accountable_role_id
    from public.phase_c_step_binding s
   where s.accountable_role_id in ('chief_of_staff','founder')
     and s.workflow_id not in ('W01','W02')
  union all
  -- the founder's single routine approval
  select 'non_refund_founder_approval', c.action_class, 'refund_decision is the only one',
         'founder_approval_required'
    from public.phase_c_action_class c
   where c.founder_approval_required and c.action_class <> 'refund_decision';
$function$;


revoke execute on function public.fn_phase_c_reporting_map_drift() from public;
