-- ---------------------------------------------------------------------------
-- Edge heartbeat watchdog
--
-- Why this exists: on 28 Jul 2026 kb_embed returned 546 WORKER_RESOURCE_LIMIT on
-- every scheduled run for hours. The platform kills the worker BEFORE the function's
-- own logging can fire, so agent_runs showed nothing, no task was opened, and the
-- knowledge base quietly stopped becoming searchable. In-function logging is
-- structurally incapable of reporting this class of failure.
--
-- The fix is to watch EFFECTS, not logs. Each critical scheduled capability declares
-- a heartbeat: a SQL expression returning the timestamp of its last real-world effect.
-- If that timestamp goes stale, the company opens an incident on itself.
-- ---------------------------------------------------------------------------

create table if not exists edge_expectation (
  fn_key              text primary key,
  cron_jobname        text,
  purpose             text not null,
  heartbeat_sql       text not null,          -- must return exactly one timestamptz
  max_silence_minutes integer not null default 60,
  blast_radius        text not null,          -- what breaks, in plain language, for the incident body
  dept_key            text,
  severity            text not null default 'medium',
  active              boolean not null default true,
  created_at          timestamptz not null default now()
);

-- heartbeat_sql is executed by a SECURITY DEFINER function, so write access to this
-- table is write access to the database. Lock it to service_role only.
alter table edge_expectation enable row level security;
revoke all on edge_expectation from public, anon, authenticated;

create table if not exists edge_health_probe (
  id            bigint generated always as identity primary key,
  fn_key        text not null,
  checked_at    timestamptz not null default now(),
  last_beat_at  timestamptz,
  silent_minutes numeric,
  verdict       text not null,                -- ALIVE / STALE / PROBE FAILED
  note          text
);
create index if not exists edge_health_probe_fn_idx on edge_health_probe (fn_key, checked_at desc);
alter table edge_health_probe enable row level security;
revoke all on edge_health_probe from public, anon, authenticated;

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
  -- The platform's own verdict on recent outbound calls. No function name is available
  -- in net._http_response, but the error-code mix tells an operator what kind of failure
  -- they are looking at, so it is attached to every incident raised in this pass.
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

      -- one open incident per capability; do not spam
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
          E'\nPlatform error codes in the last 30 minutes: ' || v_platform::text ||
          E'\n\nNote: this was detected by watching the capability''s EFFECT, not its logs. ' ||
          'A function killed by the platform (546 WORKER_RESOURCE_LIMIT, OOM, timeout) never ' ||
          'reaches its own error handler, so agent_runs will look clean. Check ' ||
          'net._http_response and the edge function logs directly.',
          'proposed', 'reliability', 'investigate', false);
      end if;
    else
      -- self-heal: close the incident once the capability is producing effects again
      update os_incidents
         set status = 'resolved', resolved_at = now(), resolved_by = 'edge_health_watchdog',
             resolution = 'Capability resumed producing effects; last beat ' || coalesce(v_beat::text,'?')
       where status = 'open' and detail->>'fn_key' = r.fn_key;
    end if;

    fn_key := r.fn_key; verdict := v_verdict; silent_minutes := v_silent; opened_incident := v_open;
    return next;
  end loop;
end $$;

revoke execute on function fn_edge_health_scan() from public, anon, authenticated;

comment on function fn_edge_health_scan() is
  'Watches the EFFECT of each critical scheduled capability rather than its logs, because a function killed by the edge platform never reaches its own error handler. Opens and auto-resolves os_incidents + org_tasks. Added 28 Jul 2026 after kb_embed failed silently for hours.';