-- PROBE: the sweeper closes only windows past their run time, and leaves windows inside it open.
-- Seat: it_engineer. Pure probe, never applied: run after a_rehearsal_window_past_its_run_time_is_closed.sql
-- in ONE request (scripts/lib/safe_replay.mjs); it always raises, so every row and the DDL roll back.
-- Plants four ZZ windows (tags zzprobe*), runs fn_rehearsal_window_sweep(), reads them back:
--   a  smoke  (scripts/e2e/run.mjs), started 50 min ago          -> closed (45 min ceiling)
--   b  smoke  (scripts/e2e/run.mjs), started 10 min ago          -> open
--   c  stage2 (run.mjs + models_allowed), 50 min ago, expires +70 -> open
--   d  demo_factory.withRun, 100 min ago, expires +20 min        -> closed (45 min ceiling)
-- and every closure has its it_watch_finding row.
do $probe$
declare
  v jsonb; v_fail text := ''; r record;
begin
  insert into public.rehearsal_window (run_tag, opened_by, started_at, expires_at, models_allowed, note) values
    ('qd_run:zzprobea', 'scripts/e2e/run.mjs',  now() - interval '50 minutes',  now() + interval '70 minutes', false, 'ZZ DEMO probe'),
    ('qd_run:zzprobeb', 'scripts/e2e/run.mjs',  now() - interval '10 minutes',  now() + interval '110 minutes', false, 'ZZ DEMO probe'),
    ('qd_run:zzprobec', 'scripts/e2e/run.mjs',  now() - interval '50 minutes',  now() + interval '70 minutes', true,  'ZZ DEMO probe'),
    ('qd_run:zzprobed', 'demo_factory.withRun', now() - interval '100 minutes', now() + interval '20 minutes', false, 'ZZ DEMO probe');
  perform public.fn_rehearsal_window_sweep();
  for r in select w.id, w.run_tag, w.ended_at is not null closed,
                  exists (select 1 from public.it_watch_finding f where f.detector_key = 'rehearsal_window_sweep:' || w.id) logged
             from public.rehearsal_window w where w.run_tag like 'qd_run:zzprobe_' loop
    if r.closed <> (r.run_tag in ('qd_run:zzprobea', 'qd_run:zzprobed')) then
      v_fail := v_fail || r.run_tag || ' closed=' || r.closed || '; ';
    end if;
    if r.closed <> r.logged then v_fail := v_fail || r.run_tag || ' logged=' || r.logged || '; '; end if;
  end loop;
  v := jsonb_build_object('failures', v_fail);
  raise exception 'CHK<<%>>', v::text;
end $probe$;
