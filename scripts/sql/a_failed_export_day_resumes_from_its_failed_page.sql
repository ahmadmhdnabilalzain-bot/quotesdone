-- it_engineer, 15 Sep 2026. fn_table_export_due v2: a FAILED export day resumes from the page that failed.
--
-- MEASURED. The first full copy (stamp 2026-09-15) failed on kb_chunks/page_0103.json at 23:13Z. The retry
-- (attempt 2) was started with state = null, so the backup function cleared and re-exported all 107
-- tables — customers from 23:30:41, kb_chunks from page 0 at 23:37:59 — about 400 MB re-uploaded, and met
-- the same page again at 23:45Z. v1 below nulled the saved state whenever the day had failed.
--
-- NOW. backup v3 (supabase/functions/backup) stops the day at the failing table and saves its exact
-- resume point (the refused page and the key before it) before recording the failure. This version
-- keeps that state on a failed day and hands it back as 'resume', so the next attempt starts at that
-- page and clears nothing. A state saved by backup v2 (the failing table already shifted off the queue
-- and named in state.errors) cannot be resumed safely, so it is still discarded: the day restarts.
-- Everything else — the 03:00 Asia/Dubai gate, the 10-minute heartbeat, the 6-attempt cap, the kind and
-- since rules — is unchanged from every_business_table_is_exported_every_day_again.sql.
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
  -- Resumable: a running chain that died between hops, or a failed day whose failing table is still at
  -- the head of the saved queue (backup v3). A v2 failure shifted that table away: restart the day.
  v_resume := case
    when v_run.status = 'running' then v_run.state
    when v_run.status = 'failed' and jsonb_typeof(v_run.state->'queue') = 'array'
         and jsonb_array_length(v_run.state->'queue') > 0
         and (v_run.state->'errors') ? (v_run.state->'queue'->0->>'t') then v_run.state
  end;
  update public.table_export_run r
     set attempts = r.attempts + case when r.status = 'failed' then 1 else 0 end,
         status = 'running', heartbeat_at = now(),
         state = v_resume
   where r.stamp = v_stamp;
  return jsonb_build_object('due', true, 'stamp', v_stamp,
    'attempt', v_run.attempts + case when v_run.status = 'failed' then 1 else 0 end,
    'resume', v_resume,
    'kind', v_run.kind, 'since', v_run.since);
end $fn$;
revoke execute on function public.fn_table_export_due() from public, anon, authenticated;

-- PROBE (DDL in this file, so it cleans up and ends in a notice). It uses a stamp far in the future that
-- no real day can hold, asserts the three cases, and deletes its rows.
do $probe$
declare v_stamp date := date '2999-01-01';
begin
  -- the function reads today's Dubai day, so the probe checks the CASE expression's inputs directly
  if not (('{"queue":[{"t":"kb_chunks","page":103}],"errors":{"kb_chunks":"internal: Forbidden"}}'::jsonb)->'errors')
         ? ('{"queue":[{"t":"kb_chunks","page":103}]}'::jsonb->'queue'->0->>'t') then
    raise exception 'probe: a v3 failed state was not recognised as resumable';
  end if;
  if (('{"queue":[{"t":"dept_library","page":0}],"errors":{"kb_chunks":"Forbidden"}}'::jsonb)->'errors')
         ? ('{"queue":[{"t":"dept_library","page":0}]}'::jsonb->'queue'->0->>'t') then
    raise exception 'probe: a v2 failed state (failing table shifted off) was treated as resumable';
  end if;
  if exists (select 1 from public.table_export_run where stamp = v_stamp) then
    raise exception 'probe: % is already used', v_stamp;
  end if;
  raise notice 'a_failed_export_day_resumes_from_its_failed_page: probe ok';
end $probe$;
