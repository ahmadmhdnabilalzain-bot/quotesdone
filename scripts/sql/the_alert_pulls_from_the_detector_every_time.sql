-- THE ALERT PULLS FROM THE DETECTOR, RATHER THAN WAITING TO BE PUSHED TO.
--
-- fn_it_engineer_ingest_watch_findings exists and is proven, and nothing called it. Installing a
-- bridge and leaving it uncalled reproduces the exact defect it was written to fix, one layer up —
-- so the tick that decides what the founder hears now READS THE DETECTOR FIRST, every time, as its
-- own first act.
--
-- WHY HERE AND NOT IN resilience_ping. Putting the call in the scheduler would mean the bridge runs
-- only down one path: anyone invoking the alert tick directly — a probe, a session, a future seat —
-- would silently get a tick that had not looked at the detectors, and it would look healthy. The
-- alert owns the question "has he been told", and it cannot answer that without first asking "what
-- is there to tell". Making it the tick's own first statement means there is no way to run the
-- alert without the pull.
--
-- IT CANNOT TAKE THE TICK DOWN. The ingest is wrapped: if it raises, the failure is recorded in the
-- returned JSON and in founder_alerts, and the tick continues with whatever is already in the
-- ledger. An alerting system that dies because its intake failed is worse than one that reports a
-- partial view and says so — but it must SAY so, which is why the count and any error are returned
-- rather than swallowed.
--
-- Everything else in this definition is byte-identical to what was live; only the ingest block and
-- its two variables were added.
--
-- 14 SEP 2026: sections C and D (email every finding to the founder, email him again when it
-- clears) are replaced by one call to fn_it_loop_tick. Apply the_it_engineer_closes_every_loop_it_opens.sql
-- first. The founder_mail_policy kind it_engineer_handover is left in place; nothing in this tick
-- writes it any more.

CREATE OR REPLACE FUNCTION public.fn_it_engineer_alert_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_gap_min numeric; v_last_beat timestamptz; r record;
  v_monitor int := 0; v_errors jsonb := '[]'::jsonb; v_ingest jsonb := '{}'::jsonb; v_loop jsonb := '{}'::jsonb;
begin
  ---------------------------------------------------------------------------------------------
  -- 0. PULL FROM THE DETECTORS FIRST. The detection engine writes to it_watch_finding; this ledger
  --    holds only what the founder has been told. Without this call the tick reports
  --    monitor_findings: 0 — true of the table it reads, and false about the estate.
  --    Wrapped: a failed intake must not take the alerting down, but it must be VISIBLE, because a
  --    tick that quietly saw nothing looks exactly like a tick with nothing to see.
  ---------------------------------------------------------------------------------------------
  begin
    v_ingest := public.fn_it_engineer_ingest_watch_findings();
  exception when others then
    v_ingest := jsonb_build_object('ok', false, 'error', sqlerrm);
    v_errors := v_errors || to_jsonb('ingest failed: ' || sqlerrm);
    begin
      insert into public.founder_alerts (level, event, detail, channel)
      values ('high','it_engineer:ingest_failed',
              'fn_it_engineer_ingest_watch_findings raised (' || sqlerrm || '), so this tick decided '
              || 'what to send you from a ledger that may be missing newly detected faults.','os');
    exception when others then null; end;
  end;

  ---------------------------------------------------------------------------------------------
  -- A. THE MONITOR WATCHES ITSELF FIRST. A blind detection engine is an alert, not a quiet night.
  --    The gap is read BEFORE this tick's own beat is stamped, or it would always read zero.
  --    (What this cannot catch is the tick never running again at all. That is not left uncovered:
  --    it is the platform_down / uptime_alert path -- resilience_ping via Vercel cron every 15 min
  --    and the once-a-day GitHub Action outside both Supabase and Vercel -- which already emails
  --    him under kinds that are already allowed. This does not duplicate that.)
  ---------------------------------------------------------------------------------------------
  begin
    select last_beat_at into v_last_beat from public.it_engineer_scanner where scanner = 'it_engineer_alert_tick';
    if v_last_beat is not null then
      v_gap_min := extract(epoch from (now() - v_last_beat)) / 60.0;
      if v_gap_min > 60 then
        perform public.fn_it_engineer_finding_upsert(
          'monitor:alert_tick_blind',
          'The IT engineer''s alert tick did not run for ' || round(v_gap_min) || ' minutes',
          'public.fn_it_engineer_alert_tick, called from supabase/functions/resilience_ping',
          'monitor', 1,
          jsonb_build_object('gap_minutes', round(v_gap_min), 'last_beat_at', v_last_beat,
                             'expected_every', '15 minutes (Vercel cron -> /api/resilience-ping)'),
          array['the tick is running now, so the routine itself still executes'],
          array['whether any finding was raised and missed during the gap',
                'whether the 15-minute Vercel cron or the whole edge function was the part that stopped'],
          'fn_it_engineer_alert_tick');
      else
        perform public.fn_it_engineer_finding_close('monitor:alert_tick_blind', 'the tick is running on cadence again');
      end if;
    end if;
    perform public.fn_it_engineer_scanner_beat('it_engineer_alert_tick', null, 60);
  exception when others then
    v_errors := v_errors || jsonb_build_object('section','self_watch','error', sqlerrm);
  end;

  ---------------------------------------------------------------------------------------------
  -- B. EVERY REGISTERED SCANNER. Stale beat OR a recorded error becomes a finding of its own.
  ---------------------------------------------------------------------------------------------
  begin
    for r in select * from public.it_engineer_scanner where scanner <> 'it_engineer_alert_tick' loop
      if r.last_error is not null then
        perform public.fn_it_engineer_finding_upsert(
          'monitor:' || r.scanner,
          'Detector ' || r.scanner || ' is failing, so its silence proves nothing',
          'IT engineer scanner ' || r.scanner, 'monitor', 1,
          jsonb_build_object('last_error', r.last_error, 'last_beat_at', r.last_beat_at, 'last_ok_at', r.last_ok_at),
          array['the scanner is still being invoked -- it beat at ' || to_char(r.last_beat_at at time zone 'UTC','YYYY-MM-DD HH24:MI') || ' UTC'],
          array['what this detector would have found while it was erroring'],
          'fn_it_engineer_alert_tick');
        v_monitor := v_monitor + 1;
      elsif now() - r.last_beat_at > make_interval(mins => r.max_gap_minutes) then
        perform public.fn_it_engineer_finding_upsert(
          'monitor:' || r.scanner,
          'Detector ' || r.scanner || ' has not reported for ' || round(extract(epoch from (now() - r.last_beat_at))/60.0) || ' minutes',
          'IT engineer scanner ' || r.scanner, 'monitor', 1,
          jsonb_build_object('gap_minutes', round(extract(epoch from (now() - r.last_beat_at))/60.0),
                             'max_gap_minutes', r.max_gap_minutes, 'last_beat_at', r.last_beat_at),
          array['nothing -- this detector has reported nothing to rule anything out with'],
          array['everything this detector covers is currently unwatched'],
          'fn_it_engineer_alert_tick');
        v_monitor := v_monitor + 1;
      else
        perform public.fn_it_engineer_finding_close('monitor:' || r.scanner, 'the detector is reporting on cadence and without error');
      end if;
    end loop;
  exception when others then
    v_errors := v_errors || jsonb_build_object('section','scanner_watch','error', sqlerrm);
  end;

  ---------------------------------------------------------------------------------------------
  -- C. EVERY ACTIONABLE FINDING GOES ROUND THE LOOP. Until 14 Sep 2026 this section emailed each
  --    high/critical finding straight to the founder and emailed him again when it cleared, with no
  --    seat asked to act and no reply awaited. The owning seat now answers, the IT engineer
  --    re-verifies and closes, and the founder hears only of a new bug nobody could fix
  --    (the_it_engineer_closes_every_loop_it_opens.sql). fn_it_loop_tick reports its own failures.
  ---------------------------------------------------------------------------------------------
  begin
    v_loop := public.fn_it_loop_tick();
    if not coalesce((v_loop->>'ok')::boolean, false) then
      v_errors := v_errors || jsonb_build_object('section','loop','errors', v_loop->'errors');
    end if;
  exception when others then
    v_errors := v_errors || jsonb_build_object('section','loop','error', sqlerrm);
  end;

  -- A tick that half-failed must SAY so rather than returning a clean-looking zero.
  if jsonb_array_length(v_errors) > 0 then
    insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
    values ('high', 'it_engineer:alert_tick_partial', v_errors::text, 'os', 'it_tick_partial');
  end if;

  return jsonb_build_object('ok', jsonb_array_length(v_errors) = 0,
                            'loop', v_loop,
                            'monitor_findings', v_monitor, 'ingested_from_detectors', v_ingest,
                            'errors', v_errors);
end $function$
;
