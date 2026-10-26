-- ONE-TIME CORRECTION, 6 Aug 2026. Withdraws an announcement this session emitted in error.
--
-- fn_emit_task_assigned's first form keyed "newly assigned" on coalesce(updated_at, created_at).
-- org_tasks has NO assignment timestamp, and updated_at is a LAST-TOUCHED time: fn_task_approve and
-- the executor bump it on tasks that were assigned days earlier. Measured immediately after the
-- first catch-up on production: all 50 announced tasks were created before 30 July, none within the
-- 24-hour window the call claimed, and each event carried occurred_at = now() with a payload
-- assigned_at copied from that touch time. Every one of those 50 tasks IS assigned — but the events
-- dated an assignment made up to nine days ago as if it had just happened, which is manufactured
-- recency, and the file's own comment had promised not to back-date.
--
-- Nothing had consumed them: 0 event_delivery rows (nothing subscribes to task.assigned), 0
-- event_assessment rows, 0 workflow_run rows (production's employee_task still had a NULL trigger),
-- 0 events causally descended from them. So this withdraws a write of this session's own making
-- before anything downstream depended on it, and re-announces from created_at, which for a task
-- created already-assigned IS the moment it was assigned.
--
-- The workflow deletes are no-ops on production and clear the six runs the same defect produced on
-- staging. Deliberately keyed on the run's trigger event, so a run started by anything else stays.

delete from public.workflow_step_run s
 where exists (select 1 from public.workflow_run r
                join public.company_event e on e.id = r.trigger_event_id
               where r.id = s.workflow_run_id and e.event_type = 'task.assigned');

delete from public.workflow_run r
 using public.company_event e
 where e.id = r.trigger_event_id and e.event_type = 'task.assigned';

delete from public.company_event where event_type = 'task.assigned';
