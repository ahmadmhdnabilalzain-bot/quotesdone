-- A REHEARSAL WINDOW PAST ITS RUN TIME, WITH NO LIVE OWNER, IS CLOSED AND THE CLOSURE IS LOGGED.
-- Seat: it_engineer. 13 Oct 2026, coordinator-approved defect fix.
--
-- Measured 12-13 Oct 2026: nine windows from post-deploy smokes (scripts/e2e/run.mjs) and
-- demo_factory.withRun stayed open for hours with no live workflow. scripts/e2e/stage2.mjs refuses to
-- start while any window is open, so they blocked sandbox runs. The callers now close their own window
-- on exit and on SIGTERM/SIGINT/crash; this routine is the safety net for a process killed hard (-9,
-- a cancelled runner) that no handler can catch.
--
-- RUN TIME is the window's own expires_at, for every opener. CHECK rehearsal_window_at_most_two_hours
-- bounds it at two hours. An opener that runs shorter sets its own: scripts/e2e/run.mjs takes
-- QD_E2E_WINDOW_MIN from its workflow's job wall plus 3 min teardown (post-deploy smoke 30 -> 33 min,
-- nightly journey 117 -> 120 min); stage2 sets now() + 2 h; anything else keeps the 2 h default.
-- A window before its expires_at is NEVER closed.
--
-- LIVE OWNER. A window past its run time is still left open while its tag has spent on a model in the
-- last 10 minutes (ai_cost_log.e2e_run_tag): that run is demonstrably alive.
--
-- LOG. Each closure writes one row to public.it_watch_finding (no triggers, no email), already resolved,
-- detector 'rehearsal_window_sweep', naming the window id, run_tag, opener and the reason.

create or replace function public.fn_rehearsal_window_sweep()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  x record;
  v_closed jsonb := '[]'::jsonb;
begin
  for x in
    select w.id, w.run_tag, w.opened_by, w.started_at, w.expires_at, d.deadline
      from public.rehearsal_window w
      cross join lateral (select w.expires_at as deadline) d
     where w.ended_at is null
       and d.deadline < now()
       and not exists (select 1 from public.ai_cost_log c
                        where c.e2e_run_tag = substring(w.run_tag from '^qd_run:([a-z0-9]{4,16})$')
                          and c.occurred_at > now() - interval '10 minutes')
     for update of w skip locked
  loop
    update public.rehearsal_window set ended_at = now() where id = x.id and ended_at is null;
    insert into public.it_watch_finding
      (detector_key, detector, subject, state, severity, title, evidence, opened_at, last_seen_at, seen_count, status, resolved_at)
    values ('rehearsal_window_sweep:' || x.id, 'rehearsal_window_sweep', 'e2e_harness', 'closed', 'info',
            'Rehearsal window ' || x.id || ' (' || x.run_tag || ', ' || x.opened_by || ') closed: past its run time with no live owner',
            jsonb_build_object('rehearsal_window_id', x.id, 'run_tag', x.run_tag, 'opened_by', x.opened_by,
                               'started_at', x.started_at, 'expires_at', x.expires_at, 'deadline', x.deadline,
                               'reason', 'past its run time (deadline ' || x.deadline || ') and no tagged model call in the last 10 minutes'),
            now(), now(), 1, 'resolved', now())
    on conflict (detector_key) do nothing;
    v_closed := v_closed || jsonb_build_object('id', x.id, 'run_tag', x.run_tag, 'opened_by', x.opened_by);
  end loop;
  return jsonb_build_object('closed', v_closed);
end $fn$;
revoke execute on function public.fn_rehearsal_window_sweep() from public, anon, authenticated;

do $cron$ begin
  if exists (select 1 from cron.job where jobname = 'rehearsal_window_sweep') then perform cron.unschedule('rehearsal_window_sweep'); end if;
  perform cron.schedule('rehearsal_window_sweep', '*/10 * * * *', 'select public.fn_rehearsal_window_sweep();');
end $cron$;

-- The owning seat, in the register every cron job is read against (every_run_label_and_cron_job_names_its_seat).
insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('cron_job', 'rehearsal_window_sweep', 'it_engineer',
   'fn_rehearsal_window_sweep() every 10 min: closes a rehearsal window past its expires_at with no tagged model call in 10 min, logged to it_watch_finding.',
   'scripts/sql/a_rehearsal_window_past_its_run_time_is_closed.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;
