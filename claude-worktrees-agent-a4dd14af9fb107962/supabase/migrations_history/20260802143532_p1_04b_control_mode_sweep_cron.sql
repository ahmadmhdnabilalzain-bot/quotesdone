select cron.unschedule('control_mode_sweep_5min')
where exists (select 1 from cron.job where jobname='control_mode_sweep_5min');
select cron.schedule('control_mode_sweep_5min','*/5 * * * *', $$select public.fn_control_mode_sweep()$$);
