-- THE ALERTER READS CREDENTIAL EXPIRY (6 Sep 2026).
--
-- credentials_expire_and_rotate_themselves.sql gave every rotatable internal credential a 1-year
-- expiry and a daily rotation 30 days ahead of it. fn_internal_auth refuses an expired credential,
-- so a rotation that silently fails for three weeks becomes an outage on the day. The red-view
-- alerter now lists any active credential within 7 days of expiry as a red (source 'credential'),
-- which opens a red_episode and pages through the same door as every other red. Every other line
-- is the live definition.
--
--   node scripts/apply_sql.mjs scripts/sql/the_alerter_reads_credential_expiry.sql --apply --ddl
CREATE OR REPLACE FUNCTION public.fn_red_view_alert(p_boards boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_now        timestamptz := clock_timestamp();
  v_t0         timestamptz := clock_timestamp();
  v_red        int;
  v_opened     int := 0;
  v_resolved   int := 0;
  v_pending    int := 0;
  v_shown      int;
  v_open_total int;
  v_level      text;
  v_high       boolean;
  v_detail     text;
  v_keys       text;
  v_dedupe     text;
  v_url        text;
  v_secret     text;
  v_req        bigint;
  v_suppressed int := 0;
begin
  create temp table if not exists red_now (source text, check_key text, detail text, opened_at timestamptz) on commit drop;
  delete from red_now;

  -- 1. kernel boards
  if p_boards then
    insert into red_now
    select 'board', 'board:' || b.board || ':' || b.check_name,
           left('expected ' || coalesce(b.expected,'') || ' | actual ' || coalesce(b.actual,''), 300), v_now
      from public.fn_kernel_all_boards() b
     where not b.ok;
  end if;

  -- 2. crons: latest run failed (pg_cron's own record) ...
  insert into red_now
  select 'cron', 'cron:' || j.jobname, left(coalesce(d.return_message,''), 300), d.start_time
    from cron.job j
    join (select distinct on (jobid) jobid, status, start_time, return_message
            from cron.job_run_details
           where start_time > v_now - interval '8 days'
           order by jobid, start_time desc, runid desc) d on d.jobid = j.jobid
   where j.active and d.status = 'failed';
  -- ... or latest kernel trace failed (the wrapper records the failure and returns normally)
  insert into red_now
  select 'cron', 'cron:' || j.jobname, left(coalesce(e.failure,''), 300), e.finished_at
    from cron.job j
    join public.phase_c_system_execution_wrapper w on w.jobid = j.jobid
    join (select distinct on (component_id) component_id, result, failure, finished_at
            from public.phase_c_system_execution
           where finished_at > v_now - interval '8 days'
           order by component_id, finished_at desc, trace_id desc) e on e.component_id = w.component_id
   where j.active and e.result = 'failed';

  -- 2b. credentials: an internal credential within 7 days of expiry. credential_rotate_daily
  -- renews every fn.<edge> credential 30 days ahead, so a row still here at 7 days means the
  -- rotation has been failing for three weeks -- and fn_internal_auth refuses it on the day.
  insert into red_now
  select 'credential', 'credential:' || c.context,
         left('expires ' || to_char(c.expires_at, 'YYYY-MM-DD HH24:MI') || ' UTC and no rotation has replaced it (credential_rotate_daily)', 300),
         c.expires_at - interval '7 days'
    from public.internal_credential c
   where c.active and c.retired_at is null and c.expires_at is not null and c.expires_at <= v_now + interval '7 days';
  -- 3. health checks: the latest row per target is failing
  insert into red_now
  select 'health', 'health:' || h.check_kind || ':' || h.target,
         left(coalesce(h.detail,'') || case when h.status_code is not null then ' (http ' || h.status_code || ')' else '' end, 300),
         h.created_at
    from (select distinct on (check_kind, target) *
            from public.health_checks
           where created_at > v_now - interval '24 hours'
           order by check_kind, target, created_at desc, id desc) h
   where h.ok = false;

  -- 4. connectivity register
  insert into red_now
  select 'connectivity', 'connectivity:' || r.gap_class || ':' || left(r.subject, 120), left(r.detail, 300), v_now
    from public.fn_company_connectivity_register() r;

  -- 5. department health board
  insert into red_now
  select 'department', 'department:' || v.dept_key,
         left(v.department || ' score ' || v.score::text || ' — ' || v.basis, 300), v_now
    from public.v_department_health v
    join public.org_departments d on d.dept_key = v.dept_key and d.active
   where v.status = 'at risk';

  -- 6. what the failed-runs watcher already paged (kept in the register, never paged twice)
  insert into red_now
  select 'watcher', 'watcher:' || left(s.signature, 150), left(s.signature, 300), s.first_seen_at
    from public.alert_signature s
   where s.watcher = 'failed_runs' and s.last_alerted_at is not null
     and s.last_seen_at > v_now - interval '24 hours'
     -- 5 Sep 2026: a signature the watcher has resolved on merit (its subject succeeded since) is green
     and s.resolved_at is null;

  select count(distinct check_key) into v_red from red_now;

  -- open what is new
  insert into public.red_episode (source, check_key, detail, opened_at, observed_at, last_seen_at, alerted_at, paged_by)
  select r.source, r.check_key, r.detail, r.opened_at, v_now, v_now,
         case when r.source = 'watcher' then v_now end,
         case when r.source = 'watcher' then 'failed_runs' end
    from (select distinct on (check_key) * from red_now order by check_key, opened_at) r
   where not exists (select 1 from public.red_episode e where e.check_key = r.check_key and e.resolved_at is null);
  get diagnostics v_opened = row_count;

  -- keep what is still red current
  update public.red_episode e
     set last_seen_at = v_now, detail = r.detail
    from (select distinct on (check_key) * from red_now order by check_key, opened_at) r
   where r.check_key = e.check_key and e.resolved_at is null;

  -- resolve what is green again (board episodes only on a pass that read the boards)
  update public.red_episode e
     set resolved_at = v_now
   where e.resolved_at is null
     and (p_boards or e.source <> 'board')
     and not exists (select 1 from red_now r where r.check_key = e.check_key);
  get diagnostics v_resolved = row_count;

  -- page the founder once for everything open and not yet alerted
  select count(*) into v_pending from public.red_episode where resolved_at is null and alerted_at is null;
  if v_pending > 0 then
    if public.fn_rehearsal_window_covers(v_now) then
      v_suppressed := v_pending;      -- a declared rehearsal: posted by the first pass after it closes
    else
      select count(*) into v_open_total from public.red_episode where resolved_at is null;
      -- the EPISODE ids are in the hash, not just the keys: the same key going red a second time is a
      -- new episode and must not be held by alert_founder's 24 h dedupe on the previous message's key
      -- (the probe caught exactly that before this line carried the id)
      select string_agg(check_key || '#' || id, ',' order by check_key, id),
             bool_or(source = 'health')
        into v_keys, v_high
        from public.red_episode where resolved_at is null and alerted_at is null;
      -- a page down is 'high' (alert_founder sends WhatsApp for high); everything else is 'error' (email)
      v_level  := case when v_high then 'high' else 'error' end;
      v_dedupe := 'red_view:' || md5(v_keys);
      select string_agg(left(check_key, 70) || ' — ' || left(coalesce(detail,''), 90), E'\n' order by opened_at), count(*)
        into v_detail, v_shown
        from (select check_key, detail, opened_at from public.red_episode
               where resolved_at is null and alerted_at is null
               order by opened_at limit 12) x;
      v_detail := v_pending || ' signal(s) went red and had not been alerted; ' || v_open_total
               || ' red in total right now.' || E'\n\n' || v_detail
               || case when v_pending > v_shown then E'\n… and ' || (v_pending - v_shown) || ' more (public.red_episode)' else '' end;

      select 'https://' || value || '.supabase.co/functions/v1/alert_founder' into v_url
        from public.app_secrets where key = 'project_ref';
      select value into v_secret from public.app_secrets where key = 'cred_db_internal';
      if v_url is null or v_secret is null then
        raise exception 'fn_red_view_alert: % red episode(s) are waiting but % is missing from app_secrets',
          v_pending, case when v_url is null then 'project_ref' else 'cred_db_internal' end;
      end if;
      select net.http_post(
        url     := v_url,
        headers := '{"Content-Type":"application/json"}'::jsonb,
        body    := jsonb_build_object(
          '__secret',   v_secret,
          'event',      'Red view: ' || v_pending || ' new red signal(s)',
          'detail',     left(v_detail, 1000),
          'level',      v_level,
          'dedupe_key', v_dedupe),
        timeout_milliseconds := 20000) into v_req;
      update public.red_episode
         set alerted_at = clock_timestamp(), alert_dedupe_key = v_dedupe, paged_by = 'red_view'
       where resolved_at is null and alerted_at is null;
    end if;
  end if;

  return jsonb_build_object(
    'red_now', v_red, 'opened', v_opened, 'resolved', v_resolved,
    'paged', case when v_suppressed = 0 then v_pending else 0 end,
    'pending_in_rehearsal', v_suppressed,
    'level', v_level, 'dedupe_key', v_dedupe, 'request_id', v_req,
    'boards_read', p_boards,
    'elapsed_ms', round(extract(epoch from (clock_timestamp() - v_t0)) * 1000));
end $function$
