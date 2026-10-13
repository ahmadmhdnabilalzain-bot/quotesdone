-- PROBE: the sweeper closes only windows past their run time (expires_at), and leaves windows inside it open.
-- Seat: it_engineer. Pure probe, never applied: run after a_rehearsal_window_past_its_run_time_is_closed.sql
-- in ONE request (scripts/lib/safe_replay.mjs); it always raises, so every row and the DDL roll back.
-- Plants five ZZ windows (tags zzprobe*), runs fn_rehearsal_window_sweep(), reads them back:
--   a  smoke   (run.mjs, 33 min window), started 40 min ago            -> closed
--   b  smoke   (run.mjs, 33 min window), started 10 min ago            -> open
--   n  nightly (run.mjs, 120 min window), 60 min in, no model calls     -> open
--   c  stage2  (run.mjs + models_allowed), 50 min in, expires +70       -> open
--   d  demo_factory.withRun (2 h default), started 125 min ago          -> closed
-- and every closure has its it_watch_finding row, and the cron job is registered to it_engineer.
do $probe$
declare
  v_fail text := ''; r record;
begin
  insert into public.rehearsal_window (run_tag, opened_by, started_at, expires_at, models_allowed, note) values
    ('qd_run:zzprobea', 'scripts/e2e/run.mjs',  now() - interval '40 minutes',  now() - interval '7 minutes',   false, 'ZZ DEMO probe'),
    ('qd_run:zzprobeb', 'scripts/e2e/run.mjs',  now() - interval '10 minutes',  now() + interval '23 minutes',  false, 'ZZ DEMO probe'),
    ('qd_run:zzproben', 'scripts/e2e/run.mjs',  now() - interval '60 minutes',  now() + interval '60 minutes',  false, 'ZZ DEMO probe'),
    ('qd_run:zzprobec', 'scripts/e2e/run.mjs',  now() - interval '50 minutes',  now() + interval '70 minutes',  true,  'ZZ DEMO probe'),
    ('qd_run:zzprobed', 'demo_factory.withRun', now() - interval '125 minutes', now() - interval '5 minutes',   false, 'ZZ DEMO probe');
  perform public.fn_rehearsal_window_sweep();
  for r in select w.run_tag, w.ended_at is not null closed,
                  exists (select 1 from public.it_watch_finding f where f.detector_key = 'rehearsal_window_sweep:' || w.id) logged
             from public.rehearsal_window w where w.run_tag like 'qd_run:zzprobe_' loop
    if r.closed <> (r.run_tag in ('qd_run:zzprobea', 'qd_run:zzprobed')) then
      v_fail := v_fail || r.run_tag || ' closed=' || r.closed || '; ';
    end if;
    if r.closed <> r.logged then v_fail := v_fail || r.run_tag || ' logged=' || r.logged || '; '; end if;
  end loop;
  if not exists (select 1 from cron.job where jobname = 'rehearsal_window_sweep') then v_fail := v_fail || 'cron job missing; '; end if;
  if not exists (select 1 from public.writer_seat where kind = 'cron_job' and name = 'rehearsal_window_sweep' and owner_seat = 'it_engineer') then
    v_fail := v_fail || 'cron job not registered to it_engineer; ';
  end if;
  raise exception 'CHK<<%>>', jsonb_build_object('failures', v_fail)::text;
end $probe$;
