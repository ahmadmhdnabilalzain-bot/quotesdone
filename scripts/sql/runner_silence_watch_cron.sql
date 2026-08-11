-- A watchdog nobody schedules is a watchdog nobody has. fn_runner_silence_watch goes on the same
-- daily cadence as fn_agent_silence_watch, half an hour after it, so the two reports arrive
-- together: one says whether the SCHEDULE fired, the other says whether the runner DID anything.
-- Registered in cron_registry as well, because the OS manual's own check counts an active cron with
-- no registry row as undocumented.
select cron.schedule('runner_silence_watch_daily', '10 7 * * *', $$select public.fn_runner_silence_watch();$$);

insert into public.cron_registry (jobname, human_name, category, purpose)
values ('runner_silence_watch_daily',
        'Runner silence watch',
        'monitoring',
        'Learns each runner''s own cadence from agent_runs and alerts when a regular runner goes quiet, whatever its cron reports. Catches the failure fn_agent_silence_watch structurally cannot: a scheduled job that keeps succeeding while the work inside it stops, which is what happened to cos_execute on 10 Aug 2026.')
on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
