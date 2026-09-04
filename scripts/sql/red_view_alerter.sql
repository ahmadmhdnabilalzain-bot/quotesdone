-- THE RED VIEW REACHES THE FOUNDER (4 Sep 2026). MASTER_PLAN §3 net-new #4 / §5.2 P0, STAFF_ORG seat 40.
--
-- "Detection is not wired to response": policy_consistency_weekly failed on 31 Aug 2026 06:30 and
-- nothing told anyone; ten kernel-board checks were red this morning and nothing told anyone. Every
-- red signal source in the estate is read here, deterministically, and a NEW red episode is raised to
-- the founder through the channel the company already uses — the alert_founder edge function
-- (WhatsApp for high, branded email otherwise, dedupe_key stored on the row since 3 Sep) — via the same
-- net.http_post + cred_db_internal pattern fn_watch_failed_runs and fn_resilience_watch use. No second
-- channel is built.
--
-- SOURCES (measured 4 Sep 2026; each is read, never asserted):
--   board        fn_kernel_all_boards() rows with ok=false           (41 boards, ~54 s per sweep)
--   cron         an ACTIVE cron.job whose LATEST run failed (cron.job_run_details, last 8 days) OR whose
--                latest kernel trace failed (phase_c_system_execution — the wrapper swallows failures, so
--                job_run_details alone reads "succeeded" for a run whose work failed)
--   health       the LATEST health_checks row per (check_kind,target) in 24 h has ok=false (it_health
--                page-down, agent-run failure rate over threshold)
--   connectivity fn_company_connectivity_register() rows (a non-empty register is red by definition)
--   department   v_department_health status='at risk' for an ACTIVE department (the dept health board)
--   watcher      alert_signature rows fn_watch_failed_runs already PAGED in the last 24 h — recorded as
--                open episodes so the register is complete, marked paged_by='failed_runs' and never paged
--                a second time by this routine
--
-- ONE EPISODE PER RED, ONE PAGE PER NEW SET. red_episode holds one open row per check_key (partial
-- unique index). A pass opens episodes for reds it has not seen, resolves episodes whose key is green
-- again, and then posts ONE alert_founder call carrying every open episode that has not been alerted
-- (a burst of ten reds is one message, not ten; the 3 Sep morning of three emails is the reason).
-- dedupe_key = 'red_view:' || md5 of the sorted keys in that message. A key that goes green and red
-- again is a NEW episode and pages again. Inside a declared rehearsal_window nothing is posted; the
-- pending episodes are posted by the first pass after the window closes.
--
-- LATENCY. opened_at is the source's own timestamp where it has one (the failed cron run's start, the
-- failing health row's created_at, the watcher signature's first_seen_at) and first observation
-- otherwise; alerted_at is when the post was queued. red-to-alert latency = alerted_at - opened_at,
-- the number seat 40 is graded on. Schedule is every 15 minutes (7,22,37,52): a full board sweep is
-- ~54 s against the 2-minute cron statement timeout, so 5 minutes was not honest.
--
-- Probe: node scripts/checks/red_view_alerter_pages_once_per_episode.mjs (aborted transaction; the
-- founder is not paged by the probe).
--   node scripts/apply_sql.mjs scripts/sql/red_view_alerter.sql --apply --ddl

create table if not exists public.red_episode (
  id               bigint generated always as identity primary key,
  source           text        not null,
  check_key        text        not null,
  detail           text,
  opened_at        timestamptz not null,
  observed_at      timestamptz not null default now(),
  last_seen_at     timestamptz not null default now(),
  alerted_at       timestamptz,
  alert_dedupe_key text,
  paged_by         text,
  resolved_at      timestamptz
);
create unique index if not exists red_episode_one_open_per_key on public.red_episode (check_key) where resolved_at is null;
create index if not exists red_episode_open on public.red_episode (resolved_at) where resolved_at is null;
alter table public.red_episode enable row level security;
revoke all on public.red_episode from anon, authenticated;
comment on table public.red_episode is
  'One row per red episode of a monitored signal (kernel board check, failed cron, failing health check, '
  'connectivity gap, at-risk department, watcher signature). Opened by fn_red_view_alert when the key '
  'goes red, resolved when it is green again, alerted_at when the founder was paged. alerted_at - opened_at '
  'is the red-to-alert latency.';

create or replace function public.fn_red_view_alert(p_boards boolean default true)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
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
     and s.last_seen_at > v_now - interval '24 hours';

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
end $fn$;

revoke execute on function public.fn_red_view_alert(boolean) from public;
grant  execute on function public.fn_red_view_alert(boolean) to service_role;

comment on function public.fn_red_view_alert(boolean) is
  'Red-view alerter (seat 40). Reads every red signal source (kernel boards, failed crons, failing health '
  'checks, connectivity register, at-risk departments, watcher signatures), keeps one red_episode per red, '
  'and posts ONE alert_founder call per pass for the episodes not yet alerted. Nothing is posted inside a '
  'declared rehearsal_window. p_boards=false skips the 54-second board sweep (the probe uses it).';

begin;
do $$
declare v_job bigint;
begin
  select jobid into v_job from cron.job where jobname = 'red_view_alert_15min';
  if v_job is null then
    v_job := cron.schedule('red_view_alert_15min', '7,22,37,52 * * * *', 'select public.fn_red_view_alert();');
  end if;
  -- Platform & Reliability owns it: it_operations_engineer sits in product_eng (org_role, verified).
  perform public.fn_kernel_wrap_and_enable_cron(v_job, 'it_operations_engineer', 'product_eng', 'routine_operational_decision');

  insert into public.cron_registry (jobname, human_name, category, purpose) values
    ('red_view_alert_15min', 'Red view alerter', 'resilience',
     'Every 15 min: reads every red signal source (kernel boards, failed crons, failing health checks, connectivity register, at-risk departments, watcher signatures), opens one red_episode per red, resolves it when green, and pages the founder once per new set through alert_founder.')
  on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;

  insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine) values
    (v_job, 'red_view_alert_15min',
     'INSERTs/UPDATEs public.red_episode; posts to the alert_founder edge function (net.http_request_queue), which INSERTs public.founder_alerts and public.notifications. Reads agent_runs-derived health_checks and alert_signature; never writes agent_runs, leads, inquiries or notifications directly.',
     'Every 15 min in its own transaction on a scheduled tick. It measures the real estate''s boards, crons and health rows; a committed scenario''s ZZ DEMO fixtures are not a monitored signal. Inside a declared rehearsal_window it posts nothing. close() asserts scenario rows by id/marker; red_episode is not a scenario relation.')
  on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;
end $$;
commit;

do $ctl$
declare v_job bigint; v_role text;
begin
  select j.jobid into v_job from cron.job j where j.jobname = 'red_view_alert_15min' and j.active and j.command ilike '%fn_kernel_cron_exec%';
  if v_job is null then raise exception 'red_view_alert_15min is not active and wrapped'; end if;
  select c.accountable_role_id into v_role from public.phase_c_component c where c.component_id = 'cron:red_view_alert_15min';
  if not exists (select 1 from public.org_role r where r.role_id = v_role and r.status = 'active') then
    raise exception 'cron:red_view_alert_15min accountable role % does not resolve to an active org_role', v_role;
  end if;
  if not exists (select 1 from public.phase_d_committed_scenario_cron where jobid = v_job) then
    raise exception 'red_view_alert_15min is not registered for the Phase D scenario door';
  end if;
  -- scoped to THIS job: six agents share the estate today and another's undocumented cron is not this file's finding
  if not exists (select 1 from public.cron_registry r where r.jobname = 'red_view_alert_15min') then
    raise exception 'red_view_alert_15min is undocumented in cron_registry';
  end if;
end $ctl$;
