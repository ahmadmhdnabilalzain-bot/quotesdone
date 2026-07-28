-- org_tasks.tier is an autonomy tier (advisory/gated/supervised/autonomous), not a
-- severity label. A watchdog finding is diagnostic work an agent may perform without
-- approval but whose remedy is a code or infrastructure change, so it is 'supervised'.
create or replace function fn_edge_health_scan()
returns table (fn_key text, verdict text, silent_minutes numeric, opened_incident boolean)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r            record;
  v_beat       timestamptz;
  v_silent     numeric;
  v_verdict    text;
  v_note       text;
  v_open       boolean;
  v_title      text;
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
      v_title := 'Silent failure: ' || r.fn_key || ' has produced no effect for ' ||
                 coalesce(v_silent::text || ' minutes', 'an unknown period') ||
                 ' (threshold ' || r.max_silence_minutes || ')';

      if not exists (
        select 1 from os_incidents
        where status = 'open' and detail->>'fn_key' = r.fn_key
      ) then
        insert into os_incidents (title, kind, severity, status, detail, opened_by)
        values (
          left(v_title, 300), 'silent_failure', r.severity, 'open',
          jsonb_build_object(
            'fn_key', r.fn_key,
            'cron_jobname', r.cron_jobname,
            'purpose', r.purpose,
            'blast_radius', r.blast_radius,
            'last_beat_at', v_beat,
            'silent_minutes', v_silent,
            'threshold_minutes', r.max_silence_minutes,
            'probe_note', v_note,
            'platform_errors_30m', v_platform,
            'detected_by', 'fn_edge_health_scan'),
          'edge_health_watchdog');
        v_open := true;

        insert into org_tasks (dept_key, title, detail, status, tier, action_class, needs_founder)
        values (
          coalesce(r.dept_key, 'technology'),
          left(v_title, 300),
          r.purpose || E'\n\nWhat breaks while this stays down: ' || r.blast_radius ||
          E'\n\nLast observed effect: ' || coalesce(v_beat::text, 'never') ||
          E'\nCron job: ' || coalesce(r.cron_jobname, 'unknown') ||
          E'\nSeverity: ' || r.severity ||
          E'\nPlatform error codes in the last 30 minutes: ' || v_platform::text ||
          E'\n\nNote: this was detected by watching the capability''s EFFECT, not its logs. ' ||
          'A function killed by the platform (546 WORKER_RESOURCE_LIMIT, OOM, timeout) never ' ||
          'reaches its own error handler, so agent_runs will look clean. Check ' ||
          'net._http_response and the edge function logs directly.',
          'proposed', 'supervised', 'investigate',
          -- a dark backup or a dark availability probe is founder-visible, not just a ticket
          (r.severity = 'high'));
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
         and title like 'Silent failure: ' || r.fn_key || ' %';
    end if;

    fn_key := r.fn_key; verdict := v_verdict; silent_minutes := v_silent; opened_incident := v_open;
    return next;
  end loop;
end $$;

revoke execute on function fn_edge_health_scan() from public, anon, authenticated;