-- A REORDER SIGNAL IS NOT WORK FOR THE CPO (5 Sep 2026).
--
-- priority.updated was wired on 4 Sep as MASTER_PLAN 4.4 asked: "priority.updated -> planner backlog
-- reorder" -- org_tasks.priority plus trg_priority_backlog_reorder, so the backlog re-sorts itself
-- when a chain's priority moves. The old subscription cpo@priority.updated was left active beside it,
-- and it does what every subscription does: fn_event_dispatch mints an org_task per delivered event.
-- One sweep at 20:25 UTC on 5 Sep minted 25 exec tasks titled "priority.updated on event_chain ...",
-- action_class analysis, no deliverable, no run, no reason -- the adversarial audit of PR #515 found
-- them as 41% of the open backlog. They are not work; the reorder trigger already consumed the
-- signal. The subscription is retired with its reason, its component recorded inactive so the
-- entry-point check stays true, and the 25 minted rows are cancelled with the reason on the row.
--
--   node scripts/apply_sql.mjs scripts/sql/a_reorder_signal_is_not_work_for_the_cpo.sql --apply --ddl
begin;

update public.event_subscription
   set active = false,
       reason = coalesce(reason, '') || ' | retired 5 Sep 2026: priority.updated is consumed by trg_priority_backlog_reorder (the planner backlog re-sorts itself); a task per reorder signal was noise for the CPO, 25 minted in one sweep'
 where agent_key = 'cpo' and event_type = 'priority.updated' and active;

update public.phase_c_component
   set activation_state = 'inactive', classification = 'INACTIVE_HISTORICAL',
       repair_or_keep_action = 'recorded inactive 5 Sep 2026: the subscription this component described was retired (priority.updated is a reorder signal consumed by trg_priority_backlog_reorder, not work for the CPO)',
       evidence = coalesce(evidence, '') || ' | 5 Sep 2026: subscription retired'
 where component_id = 'evsub:cpo@priority.updated' and activation_state = 'active';

update public.org_tasks
   set status = 'cancelled', updated_at = now(),
       result = coalesce(result, '{}'::jsonb) || jsonb_build_object(
         'cancelled', jsonb_build_object('at', now(), 'by', 'a_reorder_signal_is_not_work_for_the_cpo.sql',
           'reason', 'minted from priority.updated, a reorder signal the backlog trigger already consumed; not work'))
 where dept_key = 'exec' and status in ('assigned', 'proposed')
   and title like 'priority.updated on %' and result is null;

do $proof$
declare v_sub int; v_comp int; v_open int;
begin
  select count(*) into v_sub from public.event_subscription where agent_key = 'cpo' and event_type = 'priority.updated' and active;
  select count(*) into v_comp from public.phase_c_component where component_id = 'evsub:cpo@priority.updated' and activation_state = 'active';
  select count(*) into v_open from public.org_tasks where dept_key = 'exec' and status in ('assigned','proposed') and title like 'priority.updated on %';
  if v_sub > 0 or v_comp > 0 or v_open > 0 then
    raise exception 'still open: subscription %, component %, tasks %', v_sub, v_comp, v_open;
  end if;
  raise notice 'proof: cpo@priority.updated retired, component inactive, 0 open reorder tasks';
end $proof$;
commit;
