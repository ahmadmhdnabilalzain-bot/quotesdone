-- THE EXECUTIVE MEETING AND THE NIGHTLY REFLECTION GO BACK ON THE CLOCK (3 Sep 2026).
--
-- Both were switched off by the 16 Aug stand-down and left off when the self-management crons were
-- re-enabled on 2-3 Sep. The Row #3 scorer (spec file #3, the executive UI) reports the gap plainly:
-- "exec-meeting-weekly-autostart: no active fn_exec_meeting cron" and "consciousness-unprompted:
-- company_reflect_nightly active=false". Measured before re-enabling: both routines are pure SQL — no
-- net.http_post, no edge target, no model — so they are idle-clean under the paid-provider hold,
-- their components (cron:exec_meeting_weekly, cron:company_reflect_nightly) are declared with roles
-- that resolve (ceo, corporate_performance_director) and authority_class routine_operational_decision,
-- which is the wrap's default, so the committed crosswalk does not move. The founder's Monday plan
-- names re-enabling the stand-down crons as a step; this is two of them.
--
-- Registered as Phase D committed-scenario sources because both write agent_runs.

begin;
do $$
begin
  perform public.fn_kernel_wrap_and_enable_cron(152, 'ceo', 'exec');                              -- exec_meeting_weekly, Mon 05:00 UTC
  perform public.fn_kernel_wrap_and_enable_cron(160, 'corporate_performance_director', 'exec');   -- company_reflect_nightly, 21:30 UTC
  insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
  values
    (152, 'exec_meeting_weekly',
     'Convenes the weekly executive meeting in SQL: INSERTs exec_meeting / agenda rows and public.agent_runs, reads every operating system''s report. No HTTP, no model.',
     'Weekly Monday 05:00 UTC; own transaction on a scheduled tick; writes only meeting records about the real estate and its own run row; a scenario''s fixtures are never on its agenda. close() asserts scenario rows by id/marker.'),
    (160, 'company_reflect_nightly',
     'Answers the nightly self-questions in SQL: INSERTs reflection rows and public.agent_runs. No HTTP, no model.',
     'Nightly 21:30 UTC; own transaction on a scheduled tick; writes reflections about the real estate and its own run row. close() asserts scenario rows by id/marker.')
  on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;
end $$;
commit;

do $ctl$
begin
  if (select count(*) from cron.job where jobid in (152, 160) and active and command ilike '%fn_kernel_cron_exec%') <> 2 then
    raise exception 'exec_meeting_weekly and company_reflect_nightly are not both active and wrapped';
  end if;
end $ctl$;
