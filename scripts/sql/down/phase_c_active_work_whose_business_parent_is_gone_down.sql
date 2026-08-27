-- DOWN for phase_c_active_work_whose_business_parent_is_gone.sql.
--
-- It removes the two guards and restores the six-row orphan board exactly as it stood before
-- 2026-08-27. It does NOT resurrect the eight cancelled W04 runs: fn_kernel_cancel wrote sealed
-- traces and closure evidence for each, phase_c_trace is append-only once sealed, and a cancellation
-- that could be undone by a migration is not a cancellation. Reversing the CODE does not reverse the
-- HISTORY, and that asymmetry is deliberate.
--
-- Applying this file reopens two shapes: a workflow run may again be opened for a business object
-- that does not exist, and a canonical parent may again be deleted while its work is live — which is
-- how the eight orphaned runs of 26 Aug 2026 were produced.

drop trigger if exists a10_kernel_workflow_run_parent_exists on public.phase_c_workflow_run;

do $detach$
declare t text;
begin
  foreach t in array array['public.customers','public.inquiries','public.quotes','public.transactions',
                           'public.leads','public.refunds','public.os_incidents']
  loop
    if to_regclass(t) is not null then
      execute format('drop trigger if exists a00_kernel_parent_delete_guard on %s', t);
    end if;
  end loop;
end $detach$;

drop function if exists public.fn_kernel_workflow_run_parent_exists();
drop function if exists public.fn_kernel_business_parent_delete_guard();

create or replace function public.fn_kernel_orphaned_work()
returns TABLE(check_name text, expected text, actual text, ok boolean)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with dead as (
    select c.command_id from public.founder_command c where c.state in ('cancelled','superseded')
  ), dead_runs as (
    select r.run_id from public.phase_c_workflow_run r
     where r.command_id in (select command_id from dead)
        or r.state in ('cancelled','superseded')
  )
  select 'live_tasks_of_cancelled_commands',  '0',
         count(*) filter (where t.state in ('queued','assigned','accepted','in_progress','blocked'))::text
           || ' of ' || count(*)::text,
         count(*) filter (where t.state in ('queued','assigned','accepted','in_progress','blocked')) = 0
    from public.phase_c_task t
   where t.command_id in (select command_id from dead) or t.run_id in (select run_id from dead_runs)
  union all
  select 'live_runs_of_cancelled_commands', '0',
         count(*) filter (where r.state not in ('cancelled','superseded','completed','failed'))::text
           || ' of ' || count(*)::text,
         count(*) filter (where r.state not in ('cancelled','superseded','completed','failed')) = 0
    from public.phase_c_workflow_run r where r.command_id in (select command_id from dead)
  union all
  select 'live_step_runs_of_cancelled_runs', '0',
         count(*) filter (where s.state not in ('cancelled','completed','failed','superseded'))::text
           || ' of ' || count(*)::text,
         count(*) filter (where s.state not in ('cancelled','completed','failed','superseded')) = 0
    from public.phase_c_workflow_step_run s where s.run_id in (select run_id from dead_runs)
  union all
  select 'open_handoffs_of_cancelled_runs', '0',
         count(*) filter (where h.status = 'open')::text || ' of ' || count(*)::text,
         count(*) filter (where h.status = 'open') = 0
    from public.phase_c_handoff_run h where h.run_id in (select run_id from dead_runs)
  union all
  select 'undelivered_outbox_of_cancelled_commands', '0',
         count(*) filter (where o.status in ('pending','claimed','retry_wait'))::text
           || ' of ' || count(*)::text,
         count(*) filter (where o.status in ('pending','claimed','retry_wait')) = 0
    from public.phase_c_event_outbox o
   where (o.payload->>'command_id') in (select command_id::text from dead)
  union all
  select 'open_traces_of_cancelled_subjects', '0',
         count(*) filter (where tr.sealed_at is null)::text || ' of ' || count(*)::text,
         count(*) filter (where tr.sealed_at is null) = 0
    from public.phase_c_trace tr
   where tr.command_id in (select command_id from dead) or tr.run_id in (select run_id from dead_runs);
$function$;

drop function if exists public.fn_kernel_business_parent_missing();
drop function if exists public.fn_kernel_business_subject_resolve(text);
