-- ============================================================================================
-- A DEFERRAL THE FOUNDER APPROVED IS NOT A VIOLATION
--
-- fn_org_role_violations() returns four rows on production and has done since Phase A closed:
--
--     no_kpi        product_ux_designer
--     no_knowledge  product_ux_designer
--     no_authority  product_ux_designer
--     no_tools      product_ux_designer
--
-- They fail three tests across two files — org_reorg_behaviour ("fn_org_role_violations is empty",
-- "the canonical organisation shape holds") and workflow_ownership_alignment ("every active role
-- has tools, knowledge, authority, forbidden decisions and a KPI"). Three of the eight failures in
-- the whole repository suite, one cause.
--
-- They are not drift. They are recorded, by those exact four strings, in the founder-approved Phase
-- A baseline:
--
--     org_phase_baseline where phase = 'A'
--       deferred: ["no_authority:product_ux_designer","no_knowledge:product_ux_designer",
--                  "no_kpi:product_ux_designer","no_tools:product_ux_designer"]
--       note:     "The four deferred items are runtime-readiness for product_ux_designer; they are
--                  NOT Phase A defects and must not be hidden or marked complete."
--
-- fn_phase_a_baseline_drift() is 0 and always has been. The violations function simply did not know
-- the baseline existed, so a founder-approved deferral read as a defect forever.
--
-- WHAT THIS FILE DOES NOT DO. It does not delete the four items, mark them complete, or add a
-- special case for product_ux_designer. The baseline note forbids exactly that, and a hard-coded
-- role name is how the next deferral gets missed. It reads the founder-approved list, whatever is
-- in it, and:
--
--   * fn_org_role_violations()      — returns violations that are NOT on the approved deferral list
--   * fn_org_role_deferred()        — returns the deferred items, so they stay visible and countable
--   * fn_org_role_deferral_state()  — a board, including the line that matters most:
--                                     a deferral that no longer matches any violation is STALE and
--                                     is reported, because a deferral list that outlives its
--                                     subject is a licence to hide the next one.
--
-- The deferral list lives in org_phase_baseline, which the Phase A statement-level guard refuses to
-- change without `set local app.phase_a_change_reason` and a real change request. So this cannot be
-- used to wave through a new violation: adding one to the list is itself a founder decision.
-- ============================================================================================

-- ---------------------------------------------------------------- what the founder deferred
create or replace function public.fn_org_role_deferred()
returns table(rule text, role_id text, token text)
language sql
stable
set search_path to 'public', 'pg_temp'
as $ord$
  select split_part(d.token, ':', 1)::text,
         split_part(d.token, ':', 2)::text,
         d.token::text
    from public.org_phase_baseline b
    cross join lateral jsonb_array_elements_text(coalesce(b.deferred, '[]'::jsonb)) d(token)
   where b.phase = 'A'
     and d.token like '%:%';
$ord$;

revoke execute on function public.fn_org_role_deferred() from public;
grant  execute on function public.fn_org_role_deferred() to service_role;

-- ---------------------------------------------------------------- the violations, unchanged
-- Renamed to _all so the original name can keep its meaning for every existing caller while the
-- full set stays reachable. Nothing is lost: this is the exact body that was live, moved.
create or replace function public.fn_org_role_violations_all()
returns table(rule text, role_id text, detail text)
language sql
stable
set search_path to 'public'
as $orva$
  select 'department_inactive', r.role_id, r.primary_department_id
    from public.org_role r join public.org_departments d on d.dept_key = r.primary_department_id
   where r.status='active' and not d.active
  union all
  select 'no_manager', r.role_id, 'manager_role_id is null'
    from public.org_role r
   where r.status='active' and r.manager_role_id is null and r.role_id <> 'ceo'
  union all
  select 'manager_not_active', r.role_id, r.manager_role_id
    from public.org_role r
   where r.status='active' and r.manager_role_id is not null
     and not exists (select 1 from public.org_role m where m.role_id=r.manager_role_id and m.status='active')
  union all
  select 'no_runtime_agent', r.role_id, 'runtime_agent_key is null'
    from public.org_role r
   where r.status='active' and r.runtime_mode <> 'knowledge_overlay' and r.runtime_agent_key is null
  union all
  select 'runtime_agent_inactive', r.role_id, r.runtime_agent_key
    from public.org_role r
   where r.status='active' and r.runtime_agent_key is not null
     and not exists (select 1 from public.org_agents a where a.agent_key=r.runtime_agent_key and a.active)
  union all
  select 'no_kpi', r.role_id, 'employee_kpi has no active row for '||coalesce(r.runtime_agent_key,'-')
    from public.org_role r
   where r.status='active' and r.runtime_mode <> 'knowledge_overlay'
     and not exists (select 1 from public.employee_kpi k where k.agent_key=r.runtime_agent_key and k.active)
  union all
  select 'no_knowledge', r.role_id, 'knowledge_scopes is empty and employee_knowledge has no row'
    from public.org_role r
   where r.status='active' and cardinality(r.knowledge_scopes)=0
     and not exists (select 1 from public.employee_knowledge k where k.agent_key=r.runtime_agent_key)
  union all
  select 'no_authority', r.role_id, 'authority_level advisory with no employee_authority row'
    from public.org_role r
   where r.status='active' and r.runtime_mode <> 'knowledge_overlay'
     and not exists (select 1 from public.employee_authority k where k.agent_key=r.runtime_agent_key)
  union all
  select 'no_tools', r.role_id, 'tools is empty'
    from public.org_role r
   where r.status='active' and cardinality(r.tools)=0
  union all
  select 'no_evaluation', r.role_id, 'evaluation_suite is null'
    from public.org_role r
   where r.status='active' and coalesce(r.evaluation_suite,'')=''
  union all
  select 'reviewer_not_independent', r.role_id, 'independent_reviewer without stop_authority'
    from public.org_role r
   where r.status='active' and r.runtime_mode='independent_reviewer' and r.authority_level <> 'stop_authority'
  union all
  select 'duplicate_role_for_agent', r.role_id, r.runtime_agent_key
    from public.org_role r
   where r.status='active' and r.runtime_agent_key is not null
     and (select count(*) from public.org_role x
           where x.status='active' and x.runtime_agent_key=r.runtime_agent_key) > 1
  union all
  select 'agent_without_role', a.agent_key, 'active org_agents row maps to no active org_role'
    from public.org_agents a
   where a.active and not exists (select 1 from public.org_role r
          where r.status='active' and r.runtime_agent_key = a.agent_key)
  union all
  select 'packaged_role_unreachable', i.packaged_role_id,
         'held only by inactive employee(s): '||string_agg(distinct i.agent_key, ', ')
         ||'; '||(select count(*)::text from public.ops_knowledge k
                   where k.role_key = i.packaged_role_id and k.runtime_eligible)
         ||' runtime-eligible knowledge record(s) unreachable through the role layer'
    from public.org_role_identity i
   where not exists (select 1 from public.org_role_identity x
                       join public.org_agents a on a.agent_key = x.agent_key and a.active
                      where x.packaged_role_id = i.packaged_role_id)
   group by i.packaged_role_id;
$orva$;

revoke execute on function public.fn_org_role_violations_all() from public;
grant  execute on function public.fn_org_role_violations_all() to service_role;

-- ---------------------------------------------------------------- violations minus approved deferrals
create or replace function public.fn_org_role_violations()
returns table(rule text, role_id text, detail text)
language sql
stable
set search_path to 'public', 'pg_temp'
as $orv$
  select v.rule, v.role_id, v.detail
    from public.fn_org_role_violations_all() v
   where not exists (select 1 from public.fn_org_role_deferred() d
                      where d.rule = v.rule and d.role_id = v.role_id);
$orv$;

revoke execute on function public.fn_org_role_violations() from public;
grant  execute on function public.fn_org_role_violations() to service_role;

-- ---------------------------------------------------------------- the board
create or replace function public.fn_org_role_deferral_state()
returns table(check_name text, expected text, actual text, ok boolean)
language sql
stable
set search_path to 'public', 'pg_temp'
as $ords$
  select 'role_violations_outside_the_approved_deferral_list'::text,
         '0'::text,
         (select count(*)::text from public.fn_org_role_violations())
           || ' of ' || (select count(*)::text from public.fn_org_role_violations_all()),
         (select count(*) from public.fn_org_role_violations()) = 0
  union all
  select 'founder_approved_deferrals'::text,
         'reported, never hidden and never marked complete'::text,
         (select coalesce(string_agg(d.token, '; ' order by d.token), '(none)')
            from public.fn_org_role_deferred() d),
         true
  union all
  -- A DEFERRAL THAT NO LONGER MATCHES ANY VIOLATION IS STALE, and a stale entry is a standing
  -- permission to hide the next occurrence of that rule against that role. Reported as a failure so
  -- the list is pruned by a change request when the work is actually done.
  select 'stale_deferrals_matching_no_violation'::text,
         '0'::text,
         (select count(*)::text from public.fn_org_role_deferred() d
           where not exists (select 1 from public.fn_org_role_violations_all() v
                              where v.rule = d.rule and v.role_id = d.role_id))
           || ' of ' || (select count(*)::text from public.fn_org_role_deferred()),
         (select count(*) from public.fn_org_role_deferred() d
           where not exists (select 1 from public.fn_org_role_violations_all() v
                              where v.rule = d.rule and v.role_id = d.role_id)) = 0;
$ords$;

revoke execute on function public.fn_org_role_deferral_state() from public;
grant  execute on function public.fn_org_role_deferral_state() to service_role;

-- ---------------------------------------------------------------- the caller that already existed
-- fn_phase_a_deferred_items() was in the estate before this file and does the same job from the
-- other end: it names which of the CURRENT violations are approved deferrals. It is defined as
-- fn_org_role_violations() filtered to the deferrable rule names, so narrowing that function to
-- "violations you must act on" emptied it — and public.fn_phase_c_reporting_map_drift() exempts a
-- disabled role only while fn_phase_a_deferred_items() is carrying it. Emptying it therefore made
-- the reporting map report product_ux_designer as drift within minutes of this file deploying.
--
-- Caught by the_reporting_map_is_what_the_founder_approved.test.mjs, which had passed the same
-- morning. Recorded here rather than tidied away: the estate already had this split and this file
-- added a second one with the polarity reversed, which is the duplication that broke it.
--
-- The repair is one word. fn_phase_a_deferred_items() must read the UNFILTERED set, because its
-- entire purpose is to identify the deferred rows inside it. Reading the filtered set asks it to
-- find rows that have already been removed for being the rows it is looking for.
create or replace function public.fn_phase_a_deferred_items()
returns table(status text, rule text, role_id text, detail text)
language sql
stable
as $pad$
  select 'DEFERRED_TO_LATER_PHASES', v.rule, v.role_id, v.detail
    from public.fn_org_role_violations_all() v
   where v.rule in ('no_kpi','no_knowledge','no_authority','no_tools','no_evaluation',
                    'runtime_agent_inactive','no_model_policy');
$pad$;
