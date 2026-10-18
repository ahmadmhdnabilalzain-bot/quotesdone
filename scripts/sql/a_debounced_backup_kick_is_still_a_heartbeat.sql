-- A DEBOUNCED BACKUP KICK IS STILL A HEARTBEAT.
-- Seat: it_engineer, 7 Oct 2026. Gap 2 of the learning-gate audit (PR #1281), handoff 130872.
--
-- MEASURED: duty:workflow_heartbeat:dropbox_kick opened 5 Oct 01:45Z. The second scheduler
-- (.github/workflows/dropbox-backup-second-scheduler.yml) DID run at 4 Oct 21:54Z and called fn_backup_kick, which
-- answered {"kicked":false,"reason":"debounced: a kick in the last 60 seconds is still draining"} (gh run log) and
-- wrote nothing. The heartbeat (fn_it_duties, workflow_heartbeat 'dropbox_kick', 12 h) reads only agent_runs rows
-- agent = 'backup_kick' and counts.reason = 'github_actions', so a scheduler that ran and was correctly debounced
-- read as a scheduler that never ran; only the 12:50Z row counted until 06:11Z.
-- CAUSE: the debounce branch returned before recording the call.
-- CHANGE: when the caller is the scheduler (p_reason 'github_actions'), the debounce branch records an agent_runs
-- row, status 'skipped', counts {reason, mode, debounced: true}. Per-document trigger kicks are not recorded:
-- they debounce in bursts and no heartbeat reads them. The debounce itself reads status = 'ok' rows only, so a skipped row never extends it. Body
-- otherwise copied from the canonical a_document_reaches_dropbox_when_it_lands_and_only_once_it_exists.sql.
-- prevented by: scripts/checks/the_three_detector_gaps_of_the_learning_audit_stay_closed.test.mjs
--
--   node scripts/apply_sql.mjs scripts/sql/a_debounced_backup_kick_is_still_a_heartbeat.sql --apply --ddl

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
    -- 130872). Only 'github_actions': the per-document trigger kicks debounce in bursts and nothing reads them.
    if p_reason = 'github_actions' then
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

select case when position('''debounced'', true' in (select prosrc from pg_proc where oid = 'public.fn_backup_kick(text,text)'::regprocedure)) > 0
            then 'PROBE OK :: a debounced kick is recorded for the heartbeat'
            else 'PROBE FAILED :: fn_backup_kick still returns on a debounce without a record' end as verdict;
