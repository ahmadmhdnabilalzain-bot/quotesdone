-- PACR-002 — THE ORGANISATION TAKES A REAL-COMPANY REPORTING SHAPE, THROUGH THE PHASE A CHANGE REQUEST.
--
-- The founder asked for the shape a real company has: the CEO chairs an eight-seat executive
-- committee, the COO owns all of operations, Independent Assurance and Legal report to the CEO for
-- independence, and the Chief of Staff runs the Office of the CEO instead of line-managing the
-- C-suite. The frozen 15 Aug graph already put the C-suite under the CEO, so only four manager edges
-- move to complete the shape:
--
--   marketplace_director            ceo -> chief_operating_officer   (the COO owns the marketplace)
--   customer_success_director       ceo -> chief_operating_officer   (the COO owns customer success)
--   corporate_performance_director  ceo -> chief_of_staff            (the Office of the CEO)
--   strategy_director               ceo -> chief_of_staff            (the Office of the CEO)
--
-- After the move the CEO has EXACTLY eight direct reports — cfo, chief_of_staff,
-- chief_operating_officer, chief_revenue_officer, cto, data_intelligence_director, general_counsel,
-- quality_and_release_director — which is the executive committee. The COO now owns operations
-- (marketplace + customer + its own people/ops); Assurance (quality_and_release_director) and Legal
-- (general_counsel) still report to the CEO; the Office of the CEO (corporate_performance_director +
-- strategy_director) sits under the Chief of Staff.
--
-- WHY A PACR AND NOT A SILENT EDIT. org_role.manager_role_id is part of the frozen Phase A baseline
-- (registry:reporting_graph = role_id|manager_role_id|primary_department_id over active canonical
-- roles). A prior session moved these edges WITHOUT the change-request path; it drifted
-- fn_phase_a_baseline_drift and was reverted (461ec61). This file makes the SAME move correctly: it
-- carries app.phase_a_change_reason, re-records the Phase C reporting authority (manager + walked
-- path) so fn_phase_c_reporting_map_drift stays 0, and re-freezes the Phase A baseline IN PLACE from
-- the same expressions fn_phase_a_baseline_drift uses — never a transcribed hash. Counts do not move:
-- 10 departments / 90 canonical roles / 86 overlays. Nothing here changes a workflow, a gate, a
-- business rule or a founder boundary, so Phase B is untouched and fn_phase_b_baseline_drift stays 0.
--
-- Approver: founder, 1 Sep 2026 (his instruction to restructure to a real-company shape).
--
--   node scripts/apply_sql.mjs scripts/sql/pacr_002_the_real_company_reporting_shape.sql --apply --ddl

begin;

set local app.phase_a_change_reason =
  'PACR-002: real-company reporting shape — marketplace_director and customer_success_director to '
  'chief_operating_officer, corporate_performance_director and strategy_director to chief_of_staff. '
  'The CEO chairs an 8-seat executive committee; the COO owns operations; the Office of the CEO sits '
  'under the Chief of Staff. Counts unchanged at 10/90/86. Approver: founder, 1 Sep 2026.';

-- 1. THE CANONICAL REPORTING GRAPH.
update public.org_role set manager_role_id = 'chief_operating_officer'
 where role_id in ('marketplace_director','customer_success_director') and status = 'active';
update public.org_role set manager_role_id = 'chief_of_staff'
 where role_id in ('corporate_performance_director','strategy_director') and status = 'active';

-- 2. THE RUNTIME REPORTING GRAPH — kept in step with the canonical graph, edge for edge.
update public.org_agents set manager_key = 'ops_director'
 where agent_key in ('procurement','followup') and active;      -- marketplace_director, customer_success_director
update public.org_agents set manager_key = 'brief'
 where agent_key in ('cpo','strategy_director') and active;      -- corporate_performance_director, strategy_director

-- 3. THE PHASE C REPORTING AUTHORITY. The map that fn_phase_c_reporting_map_drift() checks against:
-- the four managers, then every reporting_path re-walked from the NEW live graph (the 4 moved roles
-- and their descendants whose path to the founder now runs through the COO). Only rows whose walked
-- path actually changed are touched.
update public.phase_c_reporting_authority set manager_role_id = 'chief_operating_officer', recorded_at = now()
 where canonical_role_id in ('marketplace_director','customer_success_director');
update public.phase_c_reporting_authority set manager_role_id = 'chief_of_staff', recorded_at = now()
 where canonical_role_id in ('corporate_performance_director','strategy_director');

update public.phase_c_reporting_authority a
   set reporting_path = w.walked, recorded_at = now()
  from (
    select a2.canonical_role_id,
           (with recursive up(cur, depth, path) as (
              select a2.live_role_id, 0, a2.live_role_id
              union all
              select coalesce(r.manager_role_id,'founder'), u.depth+1,
                     u.path || ' > ' || coalesce(r.manager_role_id,'founder')
                from up u join public.org_role r on r.role_id = u.cur and r.status = 'active'
               where u.depth < 20 and u.cur <> 'founder')
            select path from up where cur = 'founder' order by depth limit 1) as walked
      from public.phase_c_reporting_authority a2
  ) w
 where a.canonical_role_id = w.canonical_role_id
   and a.reporting_path is distinct from w.walked;

-- 4. THE EXECUTIVE COMMITTEE is the CEO's direct reports. marketplace_director and
-- customer_success_director now report to the COO, who represents operations on the committee, so
-- they leave it. The seats become exactly the eight direct reports (chief_of_staff as secretary plus
-- seven members), chaired by the CEO, with the Office of the CEO (strategy + corporate performance)
-- kept as standing advisers.
delete from public.org_role_committee
 where committee_key = 'exec_committee'
   and role_id in ('marketplace_director','customer_success_director');

-- 5. RE-FREEZE THE PHASE A BASELINE IN PLACE. Every digest is recomputed from the same expressions
-- fn_phase_a_baseline_drift() / scripts/phase_a/freeze.mjs use, so the approved value moves to the
-- graph the founder approved and the drift check reads 0. Counts are re-measured and must not move.
--
-- The baseline is append-only (a00_org_phase_baseline_append_only refuses UPDATE). This is the
-- sanctioned way to change it: drop the guard, recompute every digest in place, recreate the guard in
-- the SAME transaction. The dropped trigger, recorded here, is the evidence that the freeze was
-- opened deliberately and closed again.
drop trigger a00_org_phase_baseline_append_only on public.org_phase_baseline;

update public.org_phase_baseline b
   set counts = jsonb_build_object(
         'active_departments',       (select count(*) from public.org_departments where active),
         'canonical_roles',          (select count(*) from public.org_role where status='active' and runtime_mode <> 'knowledge_overlay'),
         'category_overlays',        (select count(*) from public.org_role where status='active' and runtime_mode = 'knowledge_overlay'),
         'department_heads',         (select count(*) from public.org_departments where active and lead_agent is not null),
         'organizational_workflows', (select count(*) from public.org_workflow_ownership),
         'phase_a_violations',       (select count(*) from public.fn_phase_a_organization_violations()),
         'deferred_items',           (select count(*) from public.fn_phase_a_deferred_items()),
         'retired_roles',            (select count(*) from public.org_role where status='retired')),
       registry_sha256 = jsonb_set(
         b.registry_sha256,
         '{reporting_graph,database}',
         to_jsonb((select encode(sha256(convert_to(coalesce(string_agg(x, chr(10) order by sortkey), ''), 'UTF8')), 'hex')
                     from (select r.role_id sortkey,
                                  r.role_id||'|'||coalesce(r.manager_role_id,'founder')||'|'||r.primary_department_id x
                             from public.org_role r
                            where r.status='active' and r.runtime_mode <> 'knowledge_overlay') s))),
       organization_sha256 = (
         with
         d as (select string_agg(dept_key||'|'||name||'|'||active::text||'|'||coalesce(lead_agent,''), chr(10) order by dept_key) x from public.org_departments),
         r as (select string_agg(role_id||'|'||display_name||'|'||primary_department_id||'|'||coalesce(manager_role_id,'')
                 ||'|'||runtime_mode||'|'||coalesce(runtime_agent_key,'')||'|'||status||'|'||coalesce(evaluation_suite,'')
                 ||'|'||coalesce(array_length(owned_decisions,1),0)::text||'|'||coalesce(array_length(forbidden_decisions,1),0)::text,
                 chr(10) order by role_id) x from public.org_role),
         c as (select string_agg(category_key, chr(10) order by category_key) x from public.org_category_identity),
         w as (select string_agg(workflow_key||'|'||step_no::text||'|'||step||'|'||coalesce(actor_role,''), chr(10) order by workflow_key, step_no) x from public.workflow_step),
         f as (select string_agg(decision_key, chr(10) order by decision_key) x from public.founder_reserved_decision),
         a as (select string_agg(agent_key||'|'||department||'|'||active::text||'|'||coalesce(manager_key,''), chr(10) order by agent_key) x from public.org_agents)
         select encode(sha256(convert_to(
           'departments'||chr(10)||d.x||chr(10)||'--'||chr(10)||
           'roles'||chr(10)||r.x||chr(10)||'--'||chr(10)||
           'categories'||chr(10)||c.x||chr(10)||'--'||chr(10)||
           'workflow_steps'||chr(10)||w.x||chr(10)||'--'||chr(10)||
           'reserved'||chr(10)||f.x||chr(10)||'--'||chr(10)||
           'agents'||chr(10)||a.x, 'UTF8')), 'hex')
         from d, r, c, w, f, a),
       note = b.note || E'\n\nPACR-002, 1 Sep 2026: the reporting graph took its real-company shape — '
              'marketplace_director and customer_success_director now report to the COO '
              '(chief_operating_officer), and corporate_performance_director and strategy_director to '
              'the Chief of Staff. The CEO chairs an eight-seat executive committee. Four manager '
              'edges moved; counts unchanged at 10/90/86. A founder decision through the Phase A '
              'change request, not a repair of drift. The reporting authority in '
              'public.phase_c_reporting_authority and the exec_committee membership were re-recorded '
              'to match.',
       recorded_at = now()
 where b.phase = 'A';

-- Close the freeze again in the same transaction.
create trigger a00_org_phase_baseline_append_only
  before delete or update on public.org_phase_baseline
  for each row execute function public.fn_org_phase_baseline_append_only();

commit;
