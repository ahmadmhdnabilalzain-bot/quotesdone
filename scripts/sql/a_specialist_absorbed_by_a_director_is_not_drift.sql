-- A SPECIALIST ABSORBED BY A DIRECTOR IS NOT DRIFT
--
-- fn_phase_c_reporting_map_drift reported 18 role_class mismatches. Measured 7 Sep 2026, every one
-- is a false positive: the approved map holds canonical roles that resolve to 54 live roles, of which
-- 41 are one-to-one and 13 have ABSORBED 34 canonical ones. supplier_matching_dispatch_operator
-- absorbed five including four domain specialists; chief_revenue_officer absorbed three.
--
-- The arm compared an absorbed specialist's approved class against the runtime_mode of the director
-- who absorbed them. Split by mapping the numbers are unambiguous: role_class is 18 out of 18 on
-- consolidated roles and 0 on one-to-one roles. Not one instance where the comparison is meaningful.
--
-- THIS IS A MINIMAL PATCH TO ONE ARM. My first attempt rewrote the function from a partial reading of
-- its source and silently dropped four arms including reporting_path and duplicate_active_identity.
-- That removed guards, which is worse than the false positive it fixed. This version is the canonical
-- 23-arm definition with a fanout join added to role_class and a new subject for the absorbed ones,
-- so nothing is dropped and nothing is hidden.
--
-- IT DOES NOT TOUCH THE REAL DRIFT: 19 reporting paths, 9 managers and 6 departments on one-to-one
-- roles where the map and the live organisation genuinely disagree. Those stay reported. Closing them
-- is a decision about what the approved organisation IS, and that is not an engineering call.

create or replace function public.fn_phase_c_reporting_map_drift()
returns table(subject text, role_id text, approved text, live text)
language sql stable
set search_path to 'public', 'pg_temp'
as $fn$
  -- FIRST, THE SUBJECT ITSELF. Every other branch below reads phase_c_reporting_authority, so an
  -- empty table would make all of them return nothing and the check would report perfect agreement
  -- with an authority that is no longer there. Absent input must not score as satisfied: the row
  -- count is asserted against the founder-approved shape before anything is compared to it.
  select 'authority_not_recorded', 'phase_c_reporting_authority',
         '90 standing roles', count(*)::text
    from public.phase_c_reporting_authority having count(*) <> 90
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
  select 'overlay_governance_owner', g.who, g.who, 'missing or not active'
    from (values ('category_curator'),('taxonomy_manager'),('knowledge_validator')) g(who)
   where not exists (select 1 from public.org_role r where r.role_id = g.who and r.status='active')
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
$fn$;

revoke execute on function public.fn_phase_c_reporting_map_drift() from public;
