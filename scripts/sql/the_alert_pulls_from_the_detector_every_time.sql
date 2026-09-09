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

CREATE OR REPLACE FUNCTION public.fn_it_engineer_alert_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_admin text; v_gap_min numeric; v_last_beat timestamptz;
  r record; v_sev text; v_reason text; v_body text; v_subject text; v_id bigint;
  v_sent int := 0; v_silent int := 0; v_resolved int := 0; v_refused int := 0;
  v_monitor int := 0; v_errors jsonb := '[]'::jsonb; v_ingest jsonb := '{}'::jsonb;
begin
  select lower(nullif(split_part(coalesce(value,''), ',', 1), '')) into v_admin
    from public.app_secrets where key = 'admin_emails';
  if v_admin is null then
    insert into public.founder_alerts (level, event, detail, channel)
    values ('high','it_engineer:no_admin_address',
            'fn_it_engineer_alert_tick cannot address the founder: app_secrets.admin_emails is empty.','os');
    return jsonb_build_object('ok', false, 'reason', 'no admin address');
  end if;

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
  -- C. OPEN FINDINGS -> the dedupe/escalation rule of section 3.
  ---------------------------------------------------------------------------------------------
  begin
    for r in select * from public.it_engineer_finding where closed_at is null order by started_at loop
      v_sev := public.fn_it_engineer_severity(r.blast, r.affected, r.started_at);
      v_reason := null;
      if v_sev = 'warn' then
        null;                                                        -- never emails. Recorded only.
      elsif r.alerted_at is null then
        v_reason := case when r.alert_count > 0 then 'recurred' else 'first' end;
      elsif array_position(array['warn','high','critical'], v_sev)
          > array_position(array['warn','high','critical'], coalesce(r.alerted_severity,'warn')) then
        v_reason := 'severity_rose';                                  -- no floor: this is new information
      elsif r.affected > coalesce(r.alerted_affected, 0)
        and r.affected >= 2 * greatest(coalesce(r.alerted_affected,0), 1)
        and now() - r.alerted_at >= interval '30 minutes' then
        v_reason := 'blast_grew';
      end if;

      if v_reason is null then v_silent := v_silent + 1; continue; end if;

      v_body    := public.fn_it_engineer_handover_body(r.issue_key, v_reason);
      v_subject := '[' || upper(v_sev) || '] QuotesDone IT: ' || r.title
                   || case when v_reason = 'severity_rose' then ' (escalated)'
                           when v_reason = 'blast_grew'    then ' (now ' || r.affected || ' affected)'
                           when v_reason = 'recurred'      then ' (recurred)' else '' end;

      v_id := null;
      insert into public.notifications (type, kind, to_email, to_role, channel, subject, body)
      values ('it_engineer_handover', 'it_engineer_handover', v_admin, 'admin', 'email',
              left(v_subject, 200), v_body)
      returning id into v_id;

      if v_id is null then
        -- the a10 gate refused the row. It does NOT raise, so without this the alert would vanish.
        v_refused := v_refused + 1;
        insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
        values ('critical', 'it_engineer:handover_refused_by_gate',
                'a10_notifications_founder_mail_policy dropped an it_engineer_handover for issue '
                || r.issue_key || ' (severity ' || v_sev || '). Check founder_mail_policy.it_engineer_handover.',
                'os', 'it_handover_refused');
      else
        update public.it_engineer_finding
           set alerted_at = now(), alerted_severity = v_sev, alerted_affected = r.affected,
               alert_count = alert_count + 1, notification_id = v_id
         where issue_key = r.issue_key;
        v_sent := v_sent + 1;
      end if;
    end loop;
  exception when others then
    v_errors := v_errors || jsonb_build_object('section','open_findings','error', sqlerrm);
  end;

  ---------------------------------------------------------------------------------------------
  -- D. CLOSED FINDINGS HE WAS TOLD ABOUT -> one RESOLVED note, so silence is not ambiguous.
  ---------------------------------------------------------------------------------------------
  begin
    for r in select * from public.it_engineer_finding
              where closed_at is not null and alert_count > 0 and close_notified_at is null loop
      v_body := public.fn_it_engineer_handover_body(r.issue_key, 'resolved');
      v_id := null;
      insert into public.notifications (type, kind, to_email, to_role, channel, subject, body)
      values ('it_engineer_handover', 'it_engineer_handover', v_admin, 'admin', 'email',
              left('[RESOLVED] QuotesDone IT: ' || r.title, 200), v_body)
      returning id into v_id;
      if v_id is null then
        v_refused := v_refused + 1;
      else
        update public.it_engineer_finding set close_notified_at = now() where issue_key = r.issue_key;
        v_resolved := v_resolved + 1;
      end if;
    end loop;
  exception when others then
    v_errors := v_errors || jsonb_build_object('section','resolved','error', sqlerrm);
  end;

  -- A tick that half-failed must SAY so rather than returning a clean-looking zero.
  if jsonb_array_length(v_errors) > 0 then
    insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
    values ('high', 'it_engineer:alert_tick_partial', v_errors::text, 'os', 'it_tick_partial');
  end if;

  return jsonb_build_object('ok', jsonb_array_length(v_errors) = 0,
                            'sent', v_sent, 'resolved', v_resolved, 'silent', v_silent,
                            'monitor_findings', v_monitor, 'ingested_from_detectors', v_ingest, 'refused_by_gate', v_refused,
                            'errors', v_errors);
end $function$
;
