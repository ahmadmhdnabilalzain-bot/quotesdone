-- THE GITHUB SCHEDULES THAT CAN MOVE RUN ON PG_CRON WHILE ACTIONS ARE OFF.
-- Seat: it_engineer, 26 Oct 2026.
--
-- FOUNDER ORDER, 26 Oct 2026: Ubicloud is stopped; no paid service runs CI, GitHub-hosted Actions minutes
-- included, until the bugs are cleared; Claude sessions do the checks, deploys and scheduled work. Every
-- workflow in .github/workflows is now workflow_dispatch only (docs/runbooks/release-without-ci.md).
--
-- Two of the eleven scheduled GitHub jobs are one SQL call each, so they move onto pg_cron (Supabase is
-- already paid). The others need a runner (Playwright, ffmpeg, OCR, npm, git) and are run by Claude sessions
-- from the runbook.
--
--   dropbox-backup-second-scheduler.yml (every 6 h) -> cron 'dropbox_backup_second_scheduler', same minute.
--     It called fn_backup_kick('github_actions', 'enqueue') through the management API. The cron calls the
--     same routine with reason 'pg_cron_second_scheduler', so agent_runs says truthfully where the kick came
--     from. LOST: the job was the one kick path outside Supabase AND Vercel; on pg_cron it is outside Vercel
--     only. The per-document pg_net kick and resilience_ping's 15-minute tick (Vercel Cron) are unchanged.
--   kb-embed-backfill.yml (daily 02:20 UTC) -> cron 'kb_embed_daily', same minute, fn_kb_embed_scheduled_run.
--     Measured 26 Oct 18:47 UTC: kb_chunks with embedding_gte null = 0, so there is no backlog to drain;
--     resilience_ping's fn_kb_embed_tick embeds new rows every 15 minutes. The daily run is a tick that
--     beats duty:kb_embed only when its dispatch was not refused (the rule run_embed_backfill.mjs kept:
--     a run that was broken must not beat).
--
-- fn_backup_kick: the debounce branch records the pg_cron caller as it records the GitHub one (the 7 Oct
--   heartbeat fix). Body otherwise copied from the canonical a_debounced_backup_kick_is_still_a_heartbeat.sql.
-- fn_it_workflow_heartbeats: dropbox_kick counts either scheduler; the kb_embed and dropbox_kick rows name the
--   cron job. Body otherwise copied from the canonical nothing_watched_five_of_the_eight_scheduled_workflows.sql.
--   dependency, platform, smoke and parity are unchanged: the runbook's local runs write the same rows.
-- Both cron jobs carry a writer_seat row and a cron_registry row in this file.
-- prevented by: scripts/checks/the_schedules_moved_off_github_stay_on_pg_cron.test.mjs
--
--   node scripts/apply_sql.mjs scripts/sql/the_github_schedules_that_can_move_run_on_pg_cron_while_actions_are_off.sql --apply --ddl

create or replace function public.fn_backup_kick(p_reason text, p_mode text default 'process_only')
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_ref text; v_secret text; v_req bigint;
begin
  if p_mode not in ('process_only', 'enqueue') then
    raise exception 'fn_backup_kick: mode must be process_only or enqueue, got %', p_mode;
  end if;
  -- the lock makes check-then-act atomic: two kicks in the same instant cannot both pass
  if not pg_try_advisory_xact_lock(hashtext('fn_backup_kick'))
     or exists (select 1 from public.agent_runs where agent = 'backup_kick' and status = 'ok'
                and started_at > now() - interval '60 seconds') then
    -- 7 Oct 2026: the scheduler's call is recorded, so its heartbeat sees that it ran (dropbox_kick, handoff
    -- 130872). Only the two second schedulers (GitHub until 26 Oct 2026, pg_cron from then): the per-document
    -- trigger kicks debounce in bursts and nothing reads them.
    if p_reason in ('github_actions', 'pg_cron_second_scheduler') then
      insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
      values ('backup_kick', 'skipped', jsonb_build_object('reason', p_reason, 'mode', p_mode, 'debounced', true),
              left('dropbox_backup not kicked (' || p_mode || '): debounced, a kick in the last 60 seconds is still draining: ' || p_reason, 500),
              now(), now());
    end if;
    return jsonb_build_object('kicked', false, 'reason', 'debounced: a kick in the last 60 seconds is still draining');
  end if;
  select value into v_ref from public.app_secrets where key = 'project_ref';
  select value into v_secret from public.app_secrets where key = 'cred_fn_backup_kick';
  if coalesce(v_ref, '') = '' or coalesce(v_secret, '') = '' then
    insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
    values ('backup_kick', 'error', jsonb_build_object('reason', p_reason, 'mode', p_mode),
            'Could not kick dropbox_backup: app_secrets project_ref or cred_fn_backup_kick is missing. The daily pass still runs.', now(), now());
    return jsonb_build_object('kicked', false, 'reason', 'missing project_ref or cred_fn_backup_kick');
  end if;
  select net.http_post(
           url := 'https://' || v_ref || '.supabase.co/functions/v1/dropbox_backup',
           headers := '{"Content-Type":"application/json"}'::jsonb,
           body := jsonb_build_object('__secret', v_secret, 'mode', p_mode, 'reason', left(coalesce(p_reason, ''), 120), 'chain', 0),
           timeout_milliseconds := 150000) into v_req;
  insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
  values ('backup_kick', 'ok', jsonb_build_object('reason', p_reason, 'mode', p_mode, 'request_id', v_req),
          left('dropbox_backup kicked (' || p_mode || '): ' || coalesce(p_reason, ''), 500), now(), now());
  return jsonb_build_object('kicked', true, 'request_id', v_req, 'mode', p_mode);
end $fn$;
revoke execute on function public.fn_backup_kick(text, text) from public, anon, authenticated;

-- ── THE DAILY KB EMBED RUN, ON PG_CRON ────────────────────────────────────────────────────────────
-- One fn_kb_embed_tick (harvest what the last tick's pg_net calls returned, dispatch up to 400 more). Beats
-- duty:kb_embed only when the dispatch answered ok: a refused dispatch (missing secret) leaves no row, so
-- fn_it_workflow_heartbeats raises it within 36 h.
create or replace function public.fn_kb_embed_scheduled_run()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_t jsonb;
begin
  v_t := public.fn_kb_embed_tick(400);
  if coalesce((v_t->'dispatch'->>'ok')::boolean, false) then
    perform public.fn_it_duty_ran('kb_embed', jsonb_build_object('scheduler', 'pg_cron kb_embed_daily', 'tick', v_t));
  end if;
  return v_t;
end $fn$;
revoke execute on function public.fn_kb_embed_scheduled_run() from public, anon, authenticated;

-- ── THE HEARTBEATS FOR EVERY SCHEDULED READING ────────────────────────────────────────────────────
create or replace function public.fn_it_workflow_heartbeats()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_items jsonb := '[]'::jsonb; x record; v_running interval;
begin
  -- How long the scheduled duties have been running at all. The original guard asked this as an
  -- EXISTS per subject over the same set, so asking it once is the same test, and it now reads as
  -- what it is. Note what it is NOT: it is global, not per subject. A subject added today borrows
  -- its grace period from the oldest duty row of any kind — months — so it is judged from the first
  -- tick rather than after its own interval. That is why every key above was read out of production
  -- before it was added, and why kb_embed's "never beaten" is documented as expected rather than
  -- discovered in the finding ledger.
  select now() - min(started_at) into v_running
    from public.agent_runs where agent = 'it_engineer' and counts->>'job' like 'duty:%';
  if v_running is null then return public.fn_it_duty_settle('workflow_heartbeat', '[]'::jsonb); end if;

  for x in
    select 'dependency'::text job, interval '8 days' every,
           '.github/workflows/it-weekly-readings.yml'::text wf,
           (select max(started_at) from public.agent_runs
             where agent = 'it_engineer' and counts->>'job' = 'duty:dependency') last
    union all
    select 'platform', interval '8 days', '.github/workflows/it-weekly-readings.yml',
           (select max(started_at) from public.agent_runs
             where agent = 'it_engineer' and counts->>'job' = 'duty:platform')
    union all
    select 'smoke', interval '7 days', '.github/workflows/it-post-deploy-smoke.yml',
           (select max(started_at) from public.agent_runs
             where agent = 'it_engineer' and counts->>'job' = 'duty:smoke')
    union all
    -- 26 Oct 2026: pg_cron 'kb_embed_daily' (fn_kb_embed_scheduled_run) beats it; the workflow is dispatch only.
    select 'kb_embed', interval '36 hours', 'pg_cron kb_embed_daily (was .github/workflows/kb-embed-backfill.yml)',
           (select max(started_at) from public.agent_runs
             where agent = 'it_engineer' and counts->>'job' = 'duty:kb_embed')
    union all
    -- The second scheduler kicks every 6 hours; 12 h is two missed kicks, not one late one.
    -- 26 Oct 2026: pg_cron 'dropbox_backup_second_scheduler' kicks it; a dispatched GitHub run still counts.
    select 'dropbox_kick', interval '12 hours', 'pg_cron dropbox_backup_second_scheduler (was .github/workflows/dropbox-backup-second-scheduler.yml)',
           (select max(started_at) from public.agent_runs
             where agent = 'backup_kick' and counts->>'reason' in ('github_actions', 'pg_cron_second_scheduler'))
    union all
    -- project-parity.yml runs daily AND on every pull request, and the advisor refresh step stamps
    -- last_seen_at on each of the 563 baseline rows.
    -- SAY WHAT THIS DOES NOT CATCH. The key cannot tell a scheduled run from a pull-request run, and
    -- this repository merges most days, so a permanently broken `schedule:` trigger — a cron run has
    -- no PR context and a different token scope, so it can fail on its own — would stay hidden behind
    -- the PR runs indefinitely. What this subject DOES catch is the whole workflow going quiet: no
    -- parity run of any kind for 36 hours, which is the weekend, the quiet day, and a deleted or
    -- disabled workflow. It is deliberately not claimed as coverage of the schedule itself; closing
    -- that would need the refresh step to record which trigger it ran under, and it does not.
    -- 26 Oct 2026: `npm run gate` runs the same refresh, so a session's gate run beats it too.
    select 'parity', interval '36 hours', '.github/workflows/project-parity.yml',
           (select max(last_seen_at) from public.security_advisor_baseline)
  loop
    continue when v_running <= x.every;   -- the schedule has not had time to come round yet
    if x.last is null then
      -- NEVER BEAT. Zero cannot tell a dead guard from an idle system, so this is said in its own
      -- words rather than reported as "late": nothing has ever written the row this reads.
      v_items := v_items || jsonb_build_object('item', x.job, 'owner_seat', 'ceo', 'subject', 'github',
        'title', 'Nothing has ever reported a ' || x.job || ' run, so its workflow cannot be seen to fail',
        'blast', 'agent_facing', 'affected', 1,
        'evidence', jsonb_build_object('workflow', x.wf, 'every', x.every::text, 'last', null,
          'look_at', 'the workflow''s runs in GitHub Actions, then whether the step that reports back is present and reached'));
    elsif x.last < now() - x.every then
      v_items := v_items || jsonb_build_object('item', x.job, 'owner_seat', 'ceo', 'subject', 'github',
        'title', 'The ' || x.job || ' readings from GitHub have not arrived for ' || x.every,
        'blast', 'agent_facing', 'affected', 1,
        'evidence', jsonb_build_object('workflow', x.wf, 'every', x.every::text, 'last', x.last,
          'look_at', 'the workflow''s runs in GitHub Actions: not triggered, failed, or failed to report'));
    end if;
  end loop;
  return public.fn_it_duty_settle('workflow_heartbeat', v_items);
end $fn$;
revoke execute on function public.fn_it_workflow_heartbeats() from public, anon, authenticated;

-- ── THE TWO CRON JOBS, WITH THEIR SEAT AND REGISTRY ROWS ──────────────────────────────────────────
select cron.schedule('dropbox_backup_second_scheduler', '41 */6 * * *',
  $cron$select public.fn_backup_kick('pg_cron_second_scheduler', 'enqueue');$cron$);
select cron.schedule('kb_embed_daily', '20 2 * * *',
  $cron$set statement_timeout = '120s'; select public.fn_kb_embed_scheduled_run();$cron$);

insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('cron_job', 'dropbox_backup_second_scheduler', 'sales_engineer',
   'fn_backup_kick(pg_cron_second_scheduler, enqueue) every 6 h at :41: the Dropbox backup''s second scheduler, moved off GitHub Actions 26 Oct 2026.',
   'scripts/sql/the_github_schedules_that_can_move_run_on_pg_cron_while_actions_are_off.sql'),
  ('cron_job', 'kb_embed_daily', 'it_engineer',
   'fn_kb_embed_scheduled_run() daily 02:20 UTC: one kb embed tick that beats duty:kb_embed, moved off GitHub Actions 26 Oct 2026.',
   'scripts/sql/the_github_schedules_that_can_move_run_on_pg_cron_while_actions_are_off.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;

insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('dropbox_backup_second_scheduler', 'Dropbox backup second scheduler', 'Backup & retention',
   'Asks the database to kick dropbox_backup every six hours, so a document still reaches Dropbox if the '
   || 'per-document pg_net kick is lost and resilience_ping''s Vercel Cron stops. Was a GitHub schedule until 26 Oct 2026.'),
  ('kb_embed_daily', 'Daily knowledge embedding run', 'knowledge',
   'One embedding tick a day that records duty:kb_embed, so a broken embedder is a finding within 36 hours. '
   || 'Was the kb-embed-backfill GitHub schedule until 26 Oct 2026.')
on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;

select case
  when (select count(*) from cron.job where jobname in ('dropbox_backup_second_scheduler', 'kb_embed_daily') and active) <> 2
    then 'PROBE FAILED: the two moved cron jobs are not both scheduled and active'
  when position('pg_cron_second_scheduler' in (select prosrc from pg_proc where oid = 'public.fn_it_workflow_heartbeats()'::regprocedure)) = 0
    then 'PROBE FAILED: the dropbox_kick heartbeat does not count the pg_cron scheduler'
  when exists (select 1 from public.fn_writers_without_a_seat(7))
    then 'PROBE FAILED: writers without a seat: '
         || (select string_agg(kind || ':' || name, ', ') from public.fn_writers_without_a_seat(7))
  else 'PROBE OK' end as verdict;
