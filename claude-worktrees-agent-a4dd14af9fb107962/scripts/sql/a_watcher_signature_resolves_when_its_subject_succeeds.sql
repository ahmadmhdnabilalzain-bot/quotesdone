-- A WATCHER SIGNATURE RESOLVES WHEN ITS SUBJECT SUCCEEDS (5 Sep 2026). MASTER_PLAN §5.2 / red view seat 40.
--
-- MEASURED on htdblwldjkcgjvmqkbeh, 5 Sep 2026 18:40 UTC:
--   watcher:kb_embed   last error 4 Sep 05:17, 83 'ok' runs since; episode stayed red until 5 Sep 06:22 (the clock)
--   watcher:dr_drill   last error 3 Sep 20:13, 4 'ok' runs since (23:26); episode red until 4 Sep 20:22 (the clock)
--   watcher:cron_stale:monthly_report  open since 3 Sep 07:15, seen 60 times, paged 5 Sep 08:15 -- the job ran
--                      on schedule on 1 Sep 07:00 ('0 7 1 * *'); v_cron_stale parsed a fixed day-of-month as daily.
--
-- Three changes, every other line the live definition:
--   alert_signature.resolved_at   -- new; set by fn_watch_failed_runs on merit, cleared when the signature is seen again
--   v_cron_stale                  -- a fixed day-of-month schedule is monthly (31 days), not daily
--   fn_watch_failed_runs          -- resolves failed-run signatures when the agent ran 'ok' after last_seen_at, and
--                                    cron_stale signatures when the job is no longer stale on this pass
--   fn_red_view_alert             -- source 6 (watcher) carries only unresolved signatures, so the episode resolves
--                                    on the alerter's next pass
--
--   node scripts/apply_sql.mjs scripts/sql/a_watcher_signature_resolves_when_its_subject_succeeds.sql --apply --ddl

alter table public.alert_signature add column if not exists resolved_at timestamptz;
comment on column public.alert_signature.resolved_at is
  'Set by fn_watch_failed_runs when the subject succeeded after the watcher last saw the failure (agent ran ok after last_seen_at; stale cron fired). Cleared when the signature is seen again.';

create or replace view public.v_cron_stale as
with j as (
  select jobid, jobname, schedule,
         split_part(schedule, ' ', 1) m, split_part(schedule, ' ', 2) h, split_part(schedule, ' ', 3) dom, split_part(schedule, ' ', 5) dow
  from cron.job
  where active
),
iv as (
  select j.*,
         case
           when m like '*/%' and m ~ '^\*/[0-9]+$' then (substr(m, 3)::int) * interval '1 minute'
           when m ~ '^[0-9]+$' and h = '*'          then interval '60 minutes'
           when h like '*/%' and h ~ '^\*/[0-9]+$' then (substr(h, 3)::int) * interval '1 hour'
           -- 5 Sep 2026: a fixed day-of-month is monthly. '0 7 1 * *' read as daily flagged monthly_report
           -- stale every hour from 3 Sep and paged the founder once a day for a job that ran on time on 1 Sep.
           when dom ~ '^[0-9]+$'                    then interval '31 days'
           when dow ~ '^[0-6]$'                     then interval '7 days'
           else interval '1 day'
         end as every
  from j
),
runs as (
  select jobid, max(start_time) last_any, min(start_time) first_any
  from cron.job_run_details
  group by jobid
),
act as (
  select iv.*, runs.last_any, coalesce(w.wrapped_at, runs.first_any) activated_at
  from iv
  left join runs on runs.jobid = iv.jobid
  left join public.phase_c_system_execution_wrapper w on w.jobid = iv.jobid
)
select jobid, jobname, schedule, every, activated_at, last_any,
       case when activated_at is null then 'active with no wrapper and no run ever recorded'
            else format('no run of any status since %s; schedule %s means one was due every %s',
                        coalesce(last_any::text, 'never'), schedule, every) end as why
from act
where (activated_at is null or activated_at < now() - 2 * every)
  and (last_any is null or last_any < now() - 2 * every);

create or replace function public.fn_watch_failed_runs()
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $fn$
declare
  v_stale record;
  v_stale_n int := 0;
  v_rehearsal int := 0;
  v_since    timestamptz;
  v_fail     record;
  v_alerts   int := 0;
  v_held     int := 0;
  v_real     int := 0;
  v_detail   text := '';
  v_secret   text;
  v_models_answering boolean;
  v_url      text;
begin
  -- The project ref is read, not written into the body. This function was one of the 48 places
  -- that embedded it as a literal, and an export that names the project it came from is not
  -- portable. Same pattern as fn_action_invoke_dispatch and fn_rfq_redispatch_sweep.
  select 'https://' || value || '.supabase.co/functions/v1/alert_founder' into v_url
    from app_secrets where key = 'project_ref';

  select coalesce(last_run_at, now() - interval '24 hours') into v_since
    from alert_watermark where watcher = 'failed_runs';
  if not found then
    insert into alert_watermark (watcher, last_run_at) values ('failed_runs', now() - interval '24 hours');
    v_since := now() - interval '24 hours';
  end if;

  -- IS A MODEL ANSWERING AT ALL? This one boolean is what separates "the AI is broken" from
  -- "the AI is switched off", and it is measured, not configured - nothing here reads a flag that
  -- someone could forget to clear. A single successful attempt in the last 24 hours is enough to
  -- put every model-unavailable error back on the failure side.
  select exists (select 1 from public.llm_attempt
                  where created_at > now() - interval '24 hours' and coalesce(ok, false))
    into v_models_answering;
  -- Rows inside a declared sandbox rehearsal window (demo_factory.withRun): counted, stated in the
  -- message if one goes out, never the reason one goes out. A rehearsal on the production database
  -- paged the founder twice on 3 Sep 2026 about the operator's own probes; this is the fix.
  select count(*) into v_rehearsal
    from agent_runs r
   where r.started_at > v_since and r.status = 'error'
     and public.fn_rehearsal_window_covers(r.started_at);

  for v_fail in
    select r.agent,
           count(*) as fails,
           max(r.started_at) as latest,
           left(coalesce(max(r.note), ''), 300) as sample_note,
           -- The signature is the agent plus the shape of the note, not the note itself: the same
           -- standing condition arrives with different numbers in it every pass ("3 step(s) are
           -- ready" one hour, "4" the next) and must still be recognised as the same condition.
           r.agent || ':' || left(regexp_replace(coalesce(max(r.note), ''), '[0-9]+', '#', 'g'), 120) as signature,
           bool_or(coalesce(r.note, '') ~* '(model returned nothing|returned no content|generation_failed|returned nothing for|model call failed|open-circuit|LLM call failed)') as model_shaped
      from agent_runs r
     where r.started_at > v_since and r.status = 'error'
       -- a row inside a DECLARED rehearsal window is counted below, not paged (3 Sep 2026)
       and not public.fn_rehearsal_window_covers(r.started_at)
     group by r.agent, left(regexp_replace(coalesce(r.note, ''), '[0-9]+', '#', 'g'), 120)
     order by count(*) desc
  loop
    -- HELD: a model did not answer, and no model has answered at all. Counted, recorded, not
    -- alerted. The moment v_models_answering flips true this branch stops being taken.
    if v_fail.model_shaped and not v_models_answering then
      v_held := v_held + v_fail.fails;
      insert into public.alert_signature (watcher, signature)
        values ('failed_runs', v_fail.signature)
        on conflict (watcher, signature) do update
          set last_seen_at = now(), seen_count = alert_signature.seen_count + 1, resolved_at = null;
      continue;
    end if;

    v_real := v_real + v_fail.fails;

    -- ONCE PER CONDITION. A signature alerted inside the last 24 hours is still recorded as seen,
    -- and does not interrupt him again.
    insert into public.alert_signature (watcher, signature)
      values ('failed_runs', v_fail.signature)
      on conflict (watcher, signature) do update
        set last_seen_at = now(), seen_count = alert_signature.seen_count + 1, resolved_at = null;

    if exists (select 1 from public.alert_signature s
                where s.watcher = 'failed_runs' and s.signature = v_fail.signature
                  and s.last_alerted_at > now() - interval '24 hours') then
      continue;
    end if;

    v_detail := v_detail || v_fail.agent || ': ' || v_fail.fails || ' failure(s). ' || v_fail.sample_note || E'\n';
    v_alerts := v_alerts + 1;
    update public.alert_signature set last_alerted_at = now()
      where watcher = 'failed_runs' and signature = v_fail.signature;
  end loop;

  -- The hold is stated once, in the same message, so it is never invisible: he should be able to
  -- see that the quiet is his own decision and not a working company.
  if v_held > 0 then
    v_detail := v_detail || E'\n' || v_held ||
      ' further run(s) could not reach a model. No model call has succeeded in 24 hours, so these ' ||
      'are counted as held by the paid-inference hold, not as failures. They will be reported as ' ||
      'failures again the moment a model answers.' || E'\n';
  end if;

  -- THE DEAD-GUARD BLIND SPOT (3 Sep 2026). A job that never fires produces no failure. v_cron_stale
  -- lists active jobs with no run of any status inside twice their schedule, measured from activation
  -- (scripts/sql/v_cron_stale_the_dead_guard_blind_spot.sql). Same ledger, same once-per-24h rule.
  for v_stale in select jobname, schedule, why from public.v_cron_stale order by jobname loop
    v_stale_n := v_stale_n + 1;
    insert into public.alert_signature (watcher, signature) values ('failed_runs', 'cron_stale:' || v_stale.jobname)
    on conflict (watcher, signature) do update set last_seen_at = now(), seen_count = alert_signature.seen_count + 1, resolved_at = null;
    if exists (select 1 from public.alert_signature s where s.watcher = 'failed_runs'
                 and s.signature = 'cron_stale:' || v_stale.jobname and s.last_alerted_at > now() - interval '24 hours') then
      continue;
    end if;
    v_detail := v_detail || 'cron ' || v_stale.jobname || ' has NOT FIRED: ' || v_stale.why || E'\n';
    v_alerts := v_alerts + 1;
    update public.alert_signature set last_alerted_at = now() where watcher = 'failed_runs' and signature = 'cron_stale:' || v_stale.jobname;
  end loop;

  -- A SIGNATURE RESOLVES ON MERIT, NOT ON THE CLOCK (5 Sep 2026). The red view carried a watcher
  -- episode for 24 h after the last sighting whatever the subject did next. kb_embed had run
  -- 'ok' 83 times after its last error and dr_drill 4 times, and both stayed red; monthly_report was
  -- listed stale every hour and paged every day because v_cron_stale read '0 7 1 * *' as daily.
  -- Two rules, both measured from the subject's own ledger:
  --   failed-run signature  -> resolved when the agent has a status='ok' run started AFTER the
  --                            watcher last saw the failure (last_seen_at). A later failure re-opens
  --                            it through the upsert above (resolved_at = null), which the red view
  --                            then treats as a NEW episode and pages again.
  --   cron_stale signature  -> resolved when the job is no longer listed by v_cron_stale on this
  --                            pass, i.e. a run of any status has been recorded since.
  update public.alert_signature s
     set resolved_at = now()
   where s.watcher = 'failed_runs' and s.resolved_at is null
     and s.signature not like 'cron_stale:%'
     and exists (select 1 from public.agent_runs ok
                  where ok.agent = split_part(s.signature, ':', 1)
                    and ok.status = 'ok' and ok.started_at > s.last_seen_at);
  update public.alert_signature s
     set resolved_at = now()
   where s.watcher = 'failed_runs' and s.resolved_at is null
     and s.signature like 'cron_stale:%'
     and not exists (select 1 from public.v_cron_stale c where 'cron_stale:' || c.jobname = s.signature);

  if v_rehearsal > 0 then
    v_detail := v_detail || E'\n' || v_rehearsal || ' further run(s) failed inside a declared sandbox rehearsal window and were not paged.' || E'\n';
  end if;

  if v_alerts > 0 then
    -- cred_db_internal, NOT the legacy shared inbound_secret. Rebuilding this function from its
    -- 26 Jul migration text carried the old shared-secret read back in with it, and
    -- schema_dump_not_replayable caught it: the live definition had already been migrated by
    -- audit 9.5 / WI-001 and the file I rebuilt from predated that. Same credential
    -- fn_resilience_watch uses to reach alert_founder. A guard refusing your own code is the
    -- guard working.
    select value into v_secret from app_secrets where key = 'cred_db_internal';
    perform net.http_post(
      url := v_url,
      headers := '{"Content-Type":"application/json"}'::jsonb,
      body := jsonb_build_object(
        '__secret', v_secret,
        'event', 'Scheduled runs failed (' || v_alerts || ' new condition(s))',
        'detail', v_detail,
        'level', 'error',
        -- Dedupe on the day, not the hour. The hour made the key change every pass, which is why
        -- a dedupe key existed for three weeks and never deduplicated anything.
        'dedupe_key', 'failed_runs:' || to_char(now(),'YYYY-MM-DD')
      ),
      timeout_milliseconds := 20000
    );
    update alert_watermark set last_alert_at = now() where watcher = 'failed_runs';
  end if;

  update alert_watermark set last_run_at = now() where watcher = 'failed_runs';
  return jsonb_build_object(
    'checked_since', v_since,
    'models_answering', v_models_answering,
    'runs_failed', v_real,
    'runs_held_by_ai_hold', v_held,
    'runs_in_declared_rehearsal', v_rehearsal,
    'crons_stale', v_stale_n,
    'new_conditions_alerted', v_alerts,
    'alerted', v_alerts > 0);
end;
$fn$;

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
end $fn$;
