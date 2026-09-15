-- it_engineer, 15 Sep 2026. fn_table_export_due v3: a STALLED export day is never silent.
--
-- MEASURED. At 00:14:39Z a hop of backup v9 was killed by the edge runtime ("CPU Time exceeded", 546).
-- A hop killed that way runs no code after the kill: it does not fail the day, does not call
-- fn_it_duty_settle, and does not chain the next hop. The day stayed 'running' at kb_chunks page 69 with a
-- stale heartbeat, and the only thing that ever looks at it again is this function, which resumed it
-- without a word (v2, a_failed_export_day_resumes_from_its_failed_page.sql). A resumed 'running' day does
-- not count an attempt either, so a chain that dies the same way every time would never reach the
-- 6-attempt cap, never fail, and never be reported.
--
-- NOW. Whenever this function resumes a 'running' day whose heartbeat is stale (the only way that happens
-- is a hop that died without saving: CPU or memory kill, a crash, a deploy killing an in-flight worker),
-- it raises the it_engineer finding duty:table_export:chain_stalled, naming the table, the page, how long
-- the heartbeat was silent and the attempt. seen_count counts the stalls. It is written with
-- fn_it_engineer_finding_upsert under the exact key shape fn_it_duty_settle uses, NOT through
-- fn_it_duty_settle itself: settle closes every open duty:table_export:* item missing from its list, so
-- calling it with only this item would close an open duty:table_export:day_failed finding. backup v3+
-- calls fn_it_duty_settle('table_export', []) when a day finishes, which closes this finding with the rest.
--
-- The finding must not stop the resume it reports: if the upsert itself fails, the resume still happens
-- and the failure is raised as a WARNING into the Postgres log. Everything else is v2 unchanged.
create or replace function public.fn_table_export_due()
returns jsonb
language plpgsql volatile security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_local timestamp := now() at time zone 'Asia/Dubai';
  v_stamp date := (now() at time zone 'Asia/Dubai')::date;
  v_run public.table_export_run;
  v_kind text; v_since timestamptz;
  v_resume jsonb;
begin
  if v_local::time < time '03:00' then
    return jsonb_build_object('due', false, 'stamp', v_stamp, 'reason', 'before 03:00 Asia/Dubai');
  end if;
  select * into v_run from public.table_export_run r where r.stamp = v_stamp for update;
  if not found then
    select r.started_at - interval '6 hours' into v_since
      from public.table_export_run r where r.status = 'done' and r.stamp < v_stamp order by r.stamp desc limit 1;
    v_kind := case when extract(isodow from v_local) = 5 or v_since is null
                     or not exists (select 1 from public.table_export_run r
                                     where r.status = 'done' and r.kind = 'full' and r.stamp >= v_stamp - 7 and r.stamp < v_stamp)
                   then 'full' else 'incremental' end;
    if v_kind = 'full' then v_since := null; end if;
    insert into public.table_export_run (stamp, kind, since) values (v_stamp, v_kind, v_since) on conflict (stamp) do nothing;
    if not found then return jsonb_build_object('due', false, 'stamp', v_stamp, 'reason', 'claimed concurrently'); end if;
    return jsonb_build_object('due', true, 'stamp', v_stamp, 'attempt', 1, 'resume', null, 'kind', v_kind, 'since', v_since);
  end if;
  if v_run.status = 'done' then
    return jsonb_build_object('due', false, 'stamp', v_stamp, 'status', 'done', 'kind', v_run.kind);
  end if;
  if v_run.heartbeat_at > now() - interval '10 minutes' then
    return jsonb_build_object('due', false, 'stamp', v_stamp, 'status', v_run.status, 'reason', 'in progress or waiting to retry');
  end if;
  if v_run.attempts >= 6 then
    return jsonb_build_object('due', false, 'stamp', v_stamp, 'status', v_run.status, 'attempts', v_run.attempts, 'reason', 'gave up after 6 attempts');
  end if;
  v_resume := case
    when v_run.status = 'running' then v_run.state
    when v_run.status = 'failed' and jsonb_typeof(v_run.state->'queue') = 'array'
         and jsonb_array_length(v_run.state->'queue') > 0
         and (v_run.state->'errors') ? (v_run.state->'queue'->0->>'t') then v_run.state
  end;

  -- A 'running' day past the heartbeat window is a chain that died without saving. Say so, loudly.
  if v_run.status = 'running' then
    begin
      perform public.fn_it_engineer_finding_upsert(
        'duty:table_export:chain_stalled',
        left(format('The daily table export %s stalled on %s at page %s: no heartbeat for %s min, resumed as attempt %s',
                    v_stamp, coalesce(v_run.state->'queue'->0->>'t', '(no table saved)'),
                    coalesce(v_run.state->'queue'->0->>'page', '?'),
                    floor(extract(epoch from now() - v_run.heartbeat_at) / 60), v_run.attempts), 300),
        'IT engineer duty: table_export', 'agent_facing', 1,
        jsonb_build_object('duty', 'table_export', 'owner_seat', 'it_engineer', 'subject', 'table_backup', 'demo', false,
                           'stamp', v_stamp, 'cause', 'internal',
                           'table', v_run.state->'queue'->0->>'t', 'page', v_run.state->'queue'->0->'page',
                           'after', v_run.state->'queue'->0->'after', 'hop', v_run.state->'hop',
                           'heartbeat_at', v_run.heartbeat_at, 'attempt', v_run.attempts,
                           'why', 'a hop died without saving (CPU or memory kill, crash, or a deploy killing the worker); no code in the hop could report it'),
        '{}'::text[], '{}'::text[], 'it_engineer.table_export');
    exception when others then
      raise warning 'fn_table_export_due: could not raise duty:table_export:chain_stalled: %', sqlerrm;
    end;
  end if;

  update public.table_export_run r
     set attempts = r.attempts + case when r.status = 'failed' then 1 else 0 end,
         status = 'running', heartbeat_at = now(),
         state = v_resume
   where r.stamp = v_stamp;
  return jsonb_build_object('due', true, 'stamp', v_stamp,
    'attempt', v_run.attempts + case when v_run.status = 'failed' then 1 else 0 end,
    'resume', v_resume, 'stalled', v_run.status = 'running',
    'kind', v_run.kind, 'since', v_run.since);
end $fn$;
revoke execute on function public.fn_table_export_due() from public, anon, authenticated;

-- PROBE (DDL in this file, so it writes nothing and ends in a notice). The function reads today's Dubai
-- day, so a call cannot be isolated from the real run; the probe checks the pieces instead.
do $probe$
begin
  -- the key is one fn_it_duty_settle('table_export', []) closes on a finished day
  if not ('duty:table_export:chain_stalled' like 'duty:' || 'table_export' || ':%') then
    raise exception 'probe: the stalled finding key would not be closed by the table_export duty';
  end if;
  -- the upsert it calls exists with the signature used above
  if to_regprocedure('public.fn_it_engineer_finding_upsert(text,text,text,text,integer,jsonb,text[],text[],text)') is null then
    raise exception 'probe: fn_it_engineer_finding_upsert(text,text,text,text,integer,jsonb,text[],text[],text) is missing';
  end if;
  -- the blast used is one the finding table accepts
  if not exists (select 1 from pg_constraint c where c.conrelid = 'public.it_engineer_finding'::regclass
                  and pg_get_constraintdef(c.oid) like '%''agent_facing''%') then
    raise exception 'probe: blast agent_facing is not accepted by it_engineer_finding';
  end if;
  -- the new body is the live one
  if pg_get_functiondef('public.fn_table_export_due()'::regprocedure) not like '%duty:table_export:chain_stalled%' then
    raise exception 'probe: fn_table_export_due does not carry the stalled finding';
  end if;
  raise notice 'a_stalled_export_day_is_never_silent: probe ok';
end $probe$;
