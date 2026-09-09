-- fn_cron_liveness WAS PAGING THE FOUNDER EVERY THIRTY MINUTES ABOUT NOTHING.
--
-- Measured on production, 9 Sep 2026 07:04 UTC:
--   fn_cron_liveness()                        -> {"healthy": false, "newest_run_age_min": 2233.8}
--   select count(*) from cron.job              -> 1
--   select count(*) from cron.job where active -> 0
--   app_secrets.cron_down_last_alert           -> 2026-09-09T06:45:26Z
--
-- The routine judged scheduler health by the newest row in cron.job_run_details. The founder
-- deleted 234 pg_cron jobs on 7 Sep 2026 — "i said remove the kernel gates ... i dont want any
-- pre programmed workflow" — and the one job left is inactive. So that table stopped growing on
-- 7 Sep, its newest row has been ageing ever since, and the check has returned healthy=false on
-- every single call for 37 hours. resilience_ping takes its "SCHEDULER DOWN" branch on that
-- verdict and pages the founder over WhatsApp, deduped to once per 30 minutes. It has been doing
-- so continuously while the scheduler it is really protecting — Vercel cron -> /api/resilience-ping
-- -> resilience_ping — has been running perfectly, which is how we know: the page itself only
-- reaches him because that tick keeps firing.
--
-- This is the estate's own lens, "a guard that fires when the system works", in its purest form:
-- the check is measuring a subject that was deliberately removed, so it can now report exactly one
-- thing, forever. A permanent alarm is not a strict alarm. It is an alarm nobody can hear, and it
-- trains the founder to ignore the channel that is supposed to reach him in a real outage.
--
-- THE FIX IS NOT TO WEAKEN THE CHECK — the threshold is not the problem and is not touched here.
-- It is to point the check at the scheduler that actually exists. The routine keeps its name, its
-- signature and its return shape, because resilience_ping reads `healthy` and `newest_run_age_min`
-- and one other file names it; only the SUBJECT changes.
--
-- WHY THE SECOND-NEWEST TICK AND NOT THE NEWEST. resilience_ping's own tick writes a row into
-- it_watch_tick moments before it calls this function. Reading the newest row would therefore
-- measure the age of a row this very request just inserted, and the answer would be "healthy"
-- always — a check that cannot fail, swapped for one that cannot pass, which is no improvement at
-- all. The second-newest row is the last tick BEFORE this one, so the number returned is the gap
-- the scheduler actually achieved. In steady state that is ~15 minutes; after an outage it is the
-- length of the hole, and the check fails on exactly the tick that discovers it.
--
-- pg_cron is still consulted, as the LATER of the two sources rather than the only one, so that
-- if the founder ever revives it the check picks it up with no further edit. Today it contributes
-- a 37-hour-old timestamp and is simply not the winner.
--
-- Threshold 45 minutes: the live scheduler runs every 15, so this fails on the third missed tick.
-- The old 20 was tuned for pg_cron jobs that ran every few minutes and would fail this scheduler
-- on its first late beat.
create or replace function public.fn_cron_liveness()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_catalog', 'cron'
as $function$
declare
  v_tick  timestamptz;
  v_cron  timestamptz;
  v_last  timestamptz;
  v_src   text;
  v_age   numeric;
begin
  -- The last tick BEFORE this request's own. See the note above: reading the newest row would
  -- measure a row resilience_ping inserted seconds ago and could never report an outage.
  select ran_at into v_tick
  from public.it_watch_tick
  order by ran_at desc
  offset 1 limit 1;

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
              when v_tick is not null and v_last = v_tick then 'resilience tick (it_watch_tick)'
              else 'pg_cron (cron.job_run_details)' end;

  if v_last is null then
    -- Said out loud rather than returned as a clean bill: with no tick history and no cron
    -- history there is nothing to measure, and "no evidence of a scheduler" is not "healthy".
    return jsonb_build_object(
      'healthy', false, 'newest_run_age_min', null, 'source', null, 'checked_at', now(),
      'note', 'no completed scheduler tick has ever been recorded, in it_watch_tick or in cron.job_run_details');
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
  'Is the scheduler alive. Measures the last completed tick of the LIVE scheduler (Vercel cron -> /api/resilience-ping, recorded in it_watch_tick), taking pg_cron as the later of the two sources if it is ever revived. It read cron.job_run_details alone until 9 Sep 2026, which the founder emptied on 7 Sep, so it had returned healthy=false on every call for 37 hours and was paging him every 30 minutes about a scheduler that no longer exists.';
