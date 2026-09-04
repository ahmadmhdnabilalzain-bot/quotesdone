-- A BROKEN PROBE IS NOT A SILENT CAPABILITY (4 Sep 2026). MASTER_PLAN §5.2 #12, the fn_edge_health_scan part.
--
-- fn_edge_health_scan EXECUTEs each edge_expectation.heartbeat_sql. When that statement itself fails
-- (a renamed column, a dropped table, a typo in the expectation row) the exception was caught, the
-- verdict set to 'PROBE FAILED' — and then the routine fell into the same branch as STALE: it opened an
-- os_incidents row of kind 'silent_failure' titled "Silent failure: <fn> has produced no effect for an
-- unknown period" and an investigate task saying the capability is dark. The instrument's own error was
-- reported as the subject's outage. Error and empty must not return the same value as failure any more
-- than as success: a probe failure now opens its own incident (kind 'probe_failed', title "Probe broken:
-- …", severity low) and its own task naming the statement that could not run, and the STALE branch is
-- reached only by a heartbeat that ran and came back late or null. Both kinds still auto-resolve on the
-- next ALIVE verdict (the resolve is keyed on fn_key, unchanged). Every other line is the live definition.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_edge_health_scan_probe_failure_is_not_silence.sql --apply --ddl
CREATE OR REPLACE FUNCTION public.fn_edge_health_scan()
 RETURNS TABLE(fn_key text, verdict text, silent_minutes numeric, opened_incident boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r            record;
  v_beat       timestamptz;
  v_silent     numeric;
  v_verdict    text;
  v_note       text;
  v_open       boolean;
  v_title      text;
  v_kind       text;
  v_severity   text;
  v_platform   jsonb;
begin
  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_platform
  from (
    select coalesce(headers->>'sb-error-code', 'status_' || coalesce(status_code::text,'null')) as code,
           count(*) as n
    from net._http_response
    where created > timezone('utc', now()) - interval '30 minutes'
      and (status_code is null or status_code < 200 or status_code >= 300)
    group by 1 order by 2 desc limit 10
  ) x;

  for r in select * from edge_expectation where active order by fn_key loop
    v_beat := null; v_note := null; v_open := false;
    begin
      execute r.heartbeat_sql into v_beat;
    exception when others then
      v_verdict := 'PROBE FAILED';
      v_note := 'heartbeat_sql could not be evaluated: ' || left(sqlerrm, 200);
    end;

    if v_note is null then
      v_silent := case when v_beat is null then null
                       else round(extract(epoch from (now() - v_beat)) / 60.0, 1) end;
      v_verdict := case
        when v_beat is null then 'STALE'
        when v_silent > r.max_silence_minutes then 'STALE'
        else 'ALIVE' end;
    else
      v_silent := null;
    end if;

    insert into edge_health_probe (fn_key, last_beat_at, silent_minutes, verdict, note)
    values (r.fn_key, v_beat, v_silent, v_verdict, v_note);

    if v_verdict <> 'ALIVE' then
      -- 4 SEP 2026: a probe that could not run is reported as a broken probe, never as the capability's
      -- silence. Distinct kind, distinct title, its own severity; the same fn_key-keyed resolve clears it.
      if v_verdict = 'PROBE FAILED' then
        v_kind := 'probe_failed'; v_severity := 'low';
        v_title := 'Probe broken: the heartbeat_sql for ' || r.fn_key || ' could not run — ' ||
                   coalesce(v_note, 'no detail') || ' (the capability was NOT measured)';
      else
        v_kind := 'silent_failure'; v_severity := r.severity;
        v_title := 'Silent failure: ' || r.fn_key || ' has produced no effect for ' ||
                   coalesce(v_silent::text || ' minutes', 'an unknown period') ||
                   ' (threshold ' || r.max_silence_minutes || ')';
      end if;

      if not exists (
        select 1 from os_incidents
        where status = 'open' and detail->>'fn_key' = r.fn_key
      ) then
        insert into os_incidents (title, kind, severity, status, detail, opened_by)
        values (
          left(v_title, 300), v_kind, v_severity, 'open',
          jsonb_build_object(
            'fn_key', r.fn_key,
            'cron_jobname', r.cron_jobname,
            'purpose', r.purpose,
            'blast_radius', r.blast_radius,
            'last_beat_at', v_beat,
            'silent_minutes', v_silent,
            'threshold_minutes', r.max_silence_minutes,
            'probe_note', v_note,
            'heartbeat_sql', case when v_kind = 'probe_failed' then r.heartbeat_sql end,
            'platform_errors_30m', v_platform,
            'detected_by', 'fn_edge_health_scan'),
          'edge_health_watchdog');
        v_open := true;

        insert into org_tasks (dept_key, title, detail, status, tier, action_class, needs_founder)
        values (
          coalesce(r.dept_key, 'product_eng'),  -- 4 Sep 2026: 'technology' is not an org_departments row (FK 23503); Platform & Reliability is
          left(v_title, 300),
          case when v_kind = 'probe_failed' then
            'The watchdog''s own probe for ' || r.fn_key || ' failed to run, so whether the capability is alive is UNKNOWN. ' ||
            E'\n\nStatement that failed: ' || coalesce(r.heartbeat_sql, '(none)') ||
            E'\nError: ' || coalesce(v_note, '') ||
            E'\n\nFix the edge_expectation row (heartbeat_sql) or the relation it reads; do not treat this as an outage of the capability itself.'
          else
            r.purpose || E'\n\nWhat breaks while this stays down: ' || r.blast_radius ||
            E'\n\nLast observed effect: ' || coalesce(v_beat::text, 'never') ||
            E'\nCron job: ' || coalesce(r.cron_jobname, 'unknown') ||
            E'\nSeverity: ' || r.severity ||
            E'\nPlatform error codes in the last 30 minutes: ' || v_platform::text ||
            E'\n\nNote: this was detected by watching the capability''s EFFECT, not its logs. ' ||
            'A function killed by the platform (546 WORKER_RESOURCE_LIMIT, OOM, timeout) never ' ||
            'reaches its own error handler, so agent_runs will look clean. Check ' ||
            'net._http_response and the edge function logs directly.'
          end,
          'proposed', 'supervised', 'investigate',
          -- IT owns technical failures: a dark capability is the technology department's to
          -- investigate and auto-heal, never the founder's to triage. Only refunds reach the founder
          -- (founder standing rule, 2 Sep 2026). The task carries dept_key so the owning department
          -- picks it up; needs_founder stays false. Audit AP-01.
          false);
      end if;
    else
      update os_incidents
         set status = 'resolved', resolved_at = now(), resolved_by = 'edge_health_watchdog',
             resolution = 'Capability resumed producing effects; last beat ' || coalesce(v_beat::text,'?')
       where status = 'open' and detail->>'fn_key' = r.fn_key;
      update org_tasks
         set status = 'done', updated_at = now(),
             result = coalesce(result,'{}'::jsonb) || jsonb_build_object('auto_closed','capability recovered','last_beat_at', v_beat)
       where status in ('proposed','assigned','in_progress')
         and action_class = 'investigate'
         and (title like 'Silent failure: ' || r.fn_key || ' %' or title like 'Probe broken: the heartbeat_sql for ' || r.fn_key || ' %');
    end if;

    fn_key := r.fn_key; verdict := v_verdict; silent_minutes := v_silent; opened_incident := v_open;
    return next;
  end loop;
end $function$;

-- Proof, in a subtransaction that is rolled back: an expectation whose heartbeat_sql cannot run must
-- open a 'probe_failed' incident titled "Probe broken", not a 'silent_failure'.
do $proof$
declare v_kind text; v_title text; v_verdict text;
begin
  begin
    insert into public.edge_expectation (fn_key, heartbeat_sql, max_silence_minutes, severity, active, purpose, blast_radius, cron_jobname, dept_key)
    values ('ZZ DEMO probe_failed', 'select max(no_such_column) from public.no_such_table_zz_demo', 60, 'high', true,
            'red_view probe', 'none', null, 'product_eng');
    select x.verdict into v_verdict from public.fn_edge_health_scan() x where x.fn_key = 'ZZ DEMO probe_failed';
    select kind, title into v_kind, v_title from public.os_incidents where status = 'open' and detail->>'fn_key' = 'ZZ DEMO probe_failed';
    raise exception 'ROLLBACK verdict=% kind=% title=%', v_verdict, v_kind, left(v_title, 60);
  exception when others then
    if sqlerrm not like 'ROLLBACK %' then raise; end if;
    if sqlerrm not like 'ROLLBACK verdict=PROBE FAILED kind=probe_failed title=Probe broken:%' then
      raise exception 'proof failed: %', sqlerrm;
    end if;
    raise notice 'proof: %', sqlerrm;
  end;
end $proof$;
