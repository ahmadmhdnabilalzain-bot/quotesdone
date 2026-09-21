-- THE LIVENESS CHECK READS THE SCHEDULER, NOT THE DETECTOR.
--
-- Assigned: it_engineer. 21 Sep 2026.
--
-- ══ WHAT WAS MEASURED, 21 Sep 2026, against htdblwldjkcgjvmqkbeh (read-only) ═══════════════════
--
-- Four "[Attention] SCHEDULER DOWN — automation stalled" emails reached the founder in the window,
-- one a day (dedupe key cron_down holds it to one delivery a day):
--   18 Sep 03:47Z  "the previous heartbeat was 46.8 minutes ago"
--   19 Sep 04:15Z  "the previous heartbeat was 45.2 minutes ago"
--   20 Sep 04:16Z  "the previous heartbeat was 1276.1 minutes ago"
--   21 Sep 04:31Z  "the previous heartbeat was 2730.6 minutes ago"
-- The scheduler was running the whole time:
--   fn:resilience_ping rows in agent_runs since 19 Sep 07:31Z ...... 201, all status ok, every 15 min
-- What those minutes actually measure is it_watch_tick, the IT DETECTOR's own record:
--   max(ran_at) from it_watch_tick ................................. 2026-09-19 07:30:24Z
--   21 Sep 04:31Z minus 2730.6 minutes ............................. 2026-09-19 07:00Z (one tick before)
-- fn_cron_liveness reads `it_watch_tick … offset 1` as "the previous heartbeat". it_watch_tick has one
-- writer, fn_it_detect, which persists at its END; from 19 Sep 07:30Z that routine was cancelled every
-- tick at PostgREST's 8 s statement timeout (duty:heartbeat:itdetect, seen 112 times) and persisted
-- nothing — so the liveness check read a blind detector as a dead scheduler, at CRITICAL, to the
-- founder. The 46.8 and 45.2 readings on 18 and 19 Sep are the same defect at its edge: the detector
-- missed three of its own ticks behind a lock (fixed the same day) and the scheduler missed none.
--
-- This is the SAME wrong subject the detector's own D3 was corrected for on 18 Sep in
-- the_scheduler_was_never_down_and_the_queue_nobody_counted_was_fine.sql ("it was reading its OWN
-- heartbeat and calling it the scheduler's"). That correction fixed D3 and left this reader as it was.
--
-- ══ WHAT THIS FILE CHANGES ══════════════════════════════════════════════════════════════════
--
-- fn_cron_liveness measures the scheduler from the scheduler's own rows: agent_runs where
-- agent = 'fn:resilience_ping'. That row is written by the observe wrapper when a tick FINISHES
-- (measured: started_at 09:15:21, finished_at 09:17:01, note "slow run: 100146ms"), so the newest row
-- is the previous completed tick, never the one asking; the `< now() - 1 minute` guard makes that
-- true even if the wrapper ever wrote at the start. The pg_cron fallback and the "no evidence is not
-- healthy" branch are kept as they were. Threshold unchanged: 45 minutes, three missed ticks.
--
-- An empty read is NOT a clean bill: with 691 rows a week under that name, zero rows means the reader
-- lost its subject, and it says so in `source` and returns healthy=false rather than falling silent.
--
-- WHAT THIS DELIBERATELY DOES NOT CHANGE: resilience_ping's page (pageSchedulerDown), its dedupe
-- key, fn_it_detect's D3 and D3b, or it_watch_tick itself. A hole in it_watch_tick stays a finding —
-- the detector's own, under it_detector_ticks_missed — which is exactly where it belongs.
--
--   node scripts/apply_sql.mjs scripts/sql/the_liveness_check_reads_the_scheduler_not_the_detector.sql --apply --ddl

create or replace function public.fn_cron_liveness()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_catalog', 'cron', 'pg_temp'
as $function$
declare
  v_tick  timestamptz;
  v_cron  timestamptz;
  v_last  timestamptz;
  v_src   text;
  v_age   numeric;
begin
  -- The scheduler's own record: the newest COMPLETED resilience_ping tick. Written at the end of a
  -- tick, so the caller's own run is not yet there; the guard keeps that true regardless.
  select max(started_at) into v_tick
    from public.agent_runs
   where agent = 'fn:resilience_ping'
     and started_at < now() - interval '1 minute';

  begin
    select max(start_time) into v_cron from cron.job_run_details;
  exception when others then
    v_cron := null;   -- pg_cron absent or unreadable is not an outage of the live scheduler
  end;

  -- greatest() IGNORES nulls in Postgres, which is what is wanted here: with only one source
  -- populated it returns that one, and with neither it returns null and is handled below.
  v_last := greatest(v_tick, v_cron);
  v_src  := case
              when v_last is null then null
              when v_tick is not null and v_last = v_tick then 'resilience tick (agent_runs fn:resilience_ping)'
              else 'pg_cron (cron.job_run_details)' end;

  if v_last is null then
    -- Said out loud rather than returned as a clean bill: with no scheduler row and no cron
    -- history there is nothing to measure, and "no evidence of a scheduler" is not "healthy".
    return jsonb_build_object(
      'healthy', false, 'newest_run_age_min', null, 'source', null, 'checked_at', now(),
      'note', 'no completed scheduler tick has ever been recorded, in agent_runs (fn:resilience_ping) or in cron.job_run_details');
  end if;

  v_age := extract(epoch from (now() - v_last))/60.0;
  return jsonb_build_object(
    'healthy',             v_age <= 45,     -- the live scheduler runs every 15 min; 45 = three missed ticks
    'newest_run_age_min',  round(v_age,1),
    'source',              v_src,
    'threshold_min',       45,
    'checked_at',          now());
exception when others then
  return jsonb_build_object('healthy', null, 'error', sqlerrm);
end $function$;

comment on function public.fn_cron_liveness() is
  'Is the scheduler alive. Measures the newest COMPLETED tick of the LIVE scheduler (Vercel cron -> /api/resilience-ping) from its own agent_runs rows (agent fn:resilience_ping), taking pg_cron as the later of the two sources if it is ever revived. Until 21 Sep 2026 it read it_watch_tick, which is the IT detector''s record and not the scheduler''s: when the detector was cancelled every tick for 50 hours (19-21 Sep) this reported the scheduler dead at 1,276 and then 2,730 minutes while resilience_ping ran every quarter hour, and the founder was paged both days.';

-- ══ PROBE ═══════════════════════════════════════════════════════════════════════════════════
-- DDL above, so the verdict is a ROW. The routine is run (it reads only) and its source is anchored
-- on statement text, never on prose.
with src as (
  select pg_get_functiondef(p.oid) d
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_cron_liveness' and p.prokind = 'f'
),
run as (select public.fn_cron_liveness() r),
chk as (
  select
    (select d like '%where agent = ''fn:resilience_ping''%' from src)          as reads_the_scheduler,
    (select d not like '%from public.it_watch_tick%' from src)                 as no_longer_reads_the_detector,
    (select r ->> 'source' from run)                                           as source_now,
    (select r ->> 'healthy' from run)                                          as healthy_now,
    (select r ->> 'newest_run_age_min' from run)                               as age_now,
    (select count(*) from public.agent_runs where agent = 'fn:resilience_ping'
                                             and started_at > now() - interval '7 days') as scheduler_rows_7d
)
select case when reads_the_scheduler and no_longer_reads_the_detector and scheduler_rows_7d > 0
             and source_now like 'resilience tick%'
       then 'PROBE OK: fn_cron_liveness reads agent_runs fn:resilience_ping (' || scheduler_rows_7d
            || ' rows in 7 days), source now "' || source_now || '", healthy=' || coalesce(healthy_now,'null')
            || ' at ' || coalesce(age_now,'?') || ' minutes; it_watch_tick is no longer read.'
       else 'PROBE FAILED: reads_the_scheduler=' || coalesce(reads_the_scheduler::text,'null')
            || ' no_longer_reads_the_detector=' || coalesce(no_longer_reads_the_detector::text,'null')
            || ' source_now=' || coalesce(source_now,'null')
            || ' scheduler_rows_7d=' || coalesce(scheduler_rows_7d::text,'null')
       end as verdict
from chk;
