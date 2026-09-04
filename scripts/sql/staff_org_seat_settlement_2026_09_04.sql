-- STAFF_ORG SEATING — SETTLEMENT (4 Sep 2026).
--
-- Three seams the behaviour suites measured after staff_org_seat_at_plan_size_2026_09_04.sql:
--   1. The red-view -> founder alerter mechanism landed from a sibling packet while the seat was
--      being created: public.fn_red_view_alert() on cron red_view_alert_15min (jobid 324), filed
--      under the SRE. It is the alerter seat's own decision; it moves to red_view_alerter.
--   2. The Supply lead was carved out on 3 Sep as an event-driven operator with execute_low
--      authority, so a medium-risk supply action (supplier_verify, now filed under Supply)
--      escalated straight to the CEO — "supply head lacks authority for a medium-risk action".
--      Every other department head is a scheduled_manager with execute_medium; the Supply lead
--      becomes one too, and its reporting row says so.
--   3. Parking strategy_director handed its 14 open tasks (priority.updated, kpi.missed) to the
--      scorecard officer, which put that seat over its max_open_tasks (57/50). Open work beyond a
--      seat's capacity goes back to the department's proposed backlog, where the assignment sweep
--      places it within capacity — the capacity rule the sweep enforces is not bypassed by a move.
--
--   node scripts/apply_sql.mjs scripts/sql/staff_org_seat_settlement_2026_09_04.sql --apply --ddl
begin;
set local app.change_reason = 'STAFF_ORG 4 Sep 2026 settlement: alerter mechanism to its seat; Supply lead holds medium authority; moved work respects capacity';

-- 1. The alerter mechanism belongs to the alerter seat.
update public.phase_c_component c
   set accountable_role_id = 'red_view_alerter', department_id = 'product_eng',
       repair_or_keep_action = left(coalesce(nullif(c.repair_or_keep_action, ''), '')
         || case when coalesce(c.repair_or_keep_action, '') = '' then '' else ' | ' end
         || 'STAFF_ORG 4 Sep 2026: the red-view alerter seat owns the red-view -> founder-alert decision', 2000)
 where (c.component_id = 'cron:red_view_alert_15min' or c.component_id like 'dbfn:fn_red_view_alert(%' or c.component_id like 'table:red_episode')
   and c.accountable_role_id <> 'red_view_alerter';

-- 1b. A component registered under a retired role after the seating (a sibling packet filed
--     dbfn:fn_agent_decision under agent_workforce_capability_director minutes after it was parked)
--     resolves to the seat that inherited that role — the same rule the alias registry states.
update public.phase_c_component c
   set accountable_role_id = a.role_id,
       department_id = r.primary_department_id
  from public.org_role old
  join public.org_role_alias a on a.alias = old.role_id and a.kind = 'merged_role'
  join public.org_role r on r.role_id = a.role_id and r.status = 'active'
 where c.accountable_role_id = old.role_id and old.status = 'retired';

-- 2. The Supply lead is a department head like the other nine.
update public.org_role
   set runtime_mode = 'scheduled_manager', authority_level = 'execute_medium', necessity_status = 'REQUIRED_MANAGER', updated_at = now()
 where role_id = 'business_development' and status = 'active'
   and (runtime_mode <> 'scheduled_manager' or authority_level <> 'execute_medium');
update public.phase_c_reporting_authority
   set role_class = 'H', runtime_mode = 'scheduled_manager', department_head_role_id = 'business_development'
 where canonical_role_id = 'business_development' and (role_class <> 'H' or runtime_mode <> 'scheduled_manager');
insert into public.phase_c_reporting_authority (canonical_role_id, live_role_id, department_id, manager_role_id, role_class, runtime_mode, department_head_role_id, reporting_path, source_package)
select 'business_development', 'business_development', 'supply', 'ceo', 'H', 'scheduled_manager', 'business_development', 'business_development > ceo > founder', 'STAFF_ORG_2026_09_04'
 where not exists (select 1 from public.phase_c_reporting_authority where canonical_role_id = 'business_development');

-- 3. Moved work respects the seat's capacity: the newest 'assigned' rows beyond it return to the
--    department backlog (in_progress work is never pulled back).
with over as (
  select a.agent_key, a.max_open_tasks,
         (select count(*) from public.org_tasks o where o.assigned_agent = a.agent_key and o.status in ('assigned', 'in_progress')) open_n
    from public.org_agents a where a.active),
excess as (
  select t.id
    from over o
    join lateral (select t.id from public.org_tasks t
                   where t.assigned_agent = o.agent_key and t.status = 'assigned'
                   order by t.created_at desc, t.id desc
                   limit greatest(o.open_n - o.max_open_tasks, 0)) t on true
   where o.open_n > o.max_open_tasks)
update public.org_tasks t
   set status = 'proposed', assigned_agent = null, updated_at = now(),
       detail = left(coalesce(t.detail, '') || case when coalesce(t.detail, '') = '' then '' else chr(10) end
                || 'Returned to the backlog 4 Sep 2026: the seat that inherited it was over capacity; the assignment sweep places it.', 8000)
  from excess e where e.id = t.id;

do $proof$
declare v_cron text; v_appr text; v_over int; v_rule int; v_gaps int; v_viol int; v_retired_owner int;
begin
  select count(*) into v_retired_owner from public.phase_c_component c join public.org_role r on r.role_id = c.accountable_role_id where r.status <> 'active';
  if v_retired_owner > 0 then raise exception 'settlement: % components are accountable to a retired role', v_retired_owner; end if;
  select accountable_role_id into v_cron from public.phase_c_component where component_id = 'cron:red_view_alert_15min';
  v_appr := public.fn_action_resolve_approver('supply', 'medium')->>'approver';
  select count(*) into v_over from public.org_agents a where a.active
     and (select count(*) from public.org_tasks o where o.assigned_agent = a.agent_key and o.status in ('assigned', 'in_progress')) > a.max_open_tasks;
  select count(*) into v_rule from public.fn_agent_binding_rule() where not passes;
  select count(*) into v_gaps from public.fn_company_connectivity_register();
  select count(*) into v_viol from public.fn_org_role_violations();
  if v_cron is distinct from 'red_view_alerter' then raise exception 'settlement: red_view_alert_15min is accountable to %, not the alerter seat', v_cron; end if;
  if v_appr is distinct from 'bd' then raise exception 'settlement: the medium-risk approver for supply is %, not the Supply lead', v_appr; end if;
  if v_over > 0 then raise exception 'settlement: % seats still over capacity', v_over; end if;
  if v_rule > 0 then raise exception 'settlement: % active personas fail the binding rule', v_rule; end if;
  if v_gaps > 0 then raise exception 'settlement: connectivity register reports % gaps', v_gaps; end if;
  if v_viol > 0 then raise exception 'settlement: fn_org_role_violations reports % rows', v_viol; end if;
  raise notice 'settlement proof: alerter cron owned by the seat, supply medium approver = bd, 0 over capacity, binding rule all pass, register 0, violations 0';
end $proof$;
commit;
