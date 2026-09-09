-- THE BACKUP WATCHER WAS WATCHING A NAME NOTHING WRITES.
--
-- 9 September 2026. While sweeping the IT engineer's findings I ran `select public.fn_backup_watch()`
-- by hand. It alerted. It raised agent_action 10084 at risk `high`, a `backup_overdue` security
-- event, a WhatsApp to the founder (notification 21251, marked sent 08:00:36) and an email
-- (notification 21250, still queued) whose subject line reads:
--
--     "Backup failing after retry: no successful backup for as long as there are records"
--
-- and whose body says "This is past the point where one more day of silence is acceptable" at
-- severity `critical`. Every word of that is false, and it would have been false on any day.
--
-- WHY IT COULD ONLY EVER FIRE. Its first statement is:
--
--     select started_at, status from agent_runs where agent = 'backup' order by started_at desc limit 1
--
-- `agent = 'backup'` matches nothing and never has. agent_runs holds 757 rows written by 78 distinct
-- agent names, and the backup among them is `dropbox_backup` (and `fn:dropbox_backup`). There is no
-- agent called `backup`. So v_last came back NULL, NULL is treated as "overdue", and the copy has a
-- branch for exactly that case -- "for as long as there are records" -- which is the sentence a
-- reader gets when the lookup found nothing, not when a backup failed. A watcher whose subject does
-- not exist does not report "unknown". It reports catastrophe, forever, in confident language.
--
-- WHAT IS ACTUALLY TRUE, MEASURED TODAY:
--
--   dropbox_backup   ran 4 times in the last 24 hours; last run 2026-09-09 07:10:45 UTC, status
--                    `warn`. The document mirror has 177 completed rows, newest today 04:36.
--   Postgres         the Supabase management API reports SEVEN consecutive daily physical backups
--                    all COMPLETED, 2 Sep through 8 Sep 17:35 UTC, WAL-G enabled, PITR off.
--
-- So the company has restorable backups, and the alarm saying it may not have was produced by a
-- typo-grade subject mismatch that nothing has ever caught because zero looks the same as broken.
--
-- I CAUSED THE PAGE. The founder's standing note is that rehearsals and probes page him. I ran a
-- watcher directly to sweep it and it went straight out over WhatsApp. That is the second reason
-- this file exists: the fix has to make the watcher honest, and the false alert has to be withdrawn
-- rather than left in his queue looking like an unresolved critical.
--
-- THE FIX, AND THE GUARD THAT MAKES THIS CLASS LOUD.
--
--   1. It watches `dropbox_backup`, the subject that exists.
--   2. Before it can conclude anything, it asserts that the agent name it is looking for HAS been
--      written by something. If the name matches nothing in agent_runs, the function returns
--      `ok:false, reason:'subject_not_found'` and alerts NOBODY -- because a lookup that matches no
--      rows tells you about your query, not about your backups. That is the whole bug, refused at
--      the source, and it is deliberately not silent: the state is reported so a caller can see it.
--   3. The copy no longer says anything about Postgres restorability. This function reads
--      agent_runs; it cannot see managed physical backups, which live outside the database
--      entirely. It now says which backup it means and states plainly what it does not cover.
--
-- WHAT THIS DOES NOT FIX, STATED SO IT IS NOT MISTAKEN FOR COVERED. Nothing inside the estate
-- watches the managed Postgres backups. Their status is only readable through the management API.
-- Today they are COMPLETED seven days running -- I read them -- but no routine here would notice
-- if they stopped. That is a real gap, it is now named, and it is not what this file claims to fix.

create or replace function public.fn_backup_watch()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_last timestamptz; v_status text; v_stale boolean; v_open int; v_subject_rows int;
  -- The subject is the backup that this database can actually SEE. Managed physical backups are
  -- not in here and this function makes no claim about them.
  c_agents constant text[] := array['dropbox_backup','fn:dropbox_backup'];
begin
  -- POSITIVE CONTROL FIRST, AND IT IS THE ENTIRE POINT OF THIS REVISION. The previous definition
  -- looked for agent = 'backup', which nothing writes, got NULL, and read NULL as "no backup has
  -- ever succeeded". A name that matches no rows is a fact about the query. Refuse to conclude.
  select count(*) into v_subject_rows from agent_runs where agent = any(c_agents);
  if v_subject_rows = 0 then
    return jsonb_build_object(
      'ok', false,
      'reason', 'subject_not_found',
      'watched', c_agents,
      'detail', 'No run of any watched backup agent has ever been recorded, so this watcher cannot '
             || 'tell a stopped backup from a renamed one. It alerts nobody rather than reporting '
             || 'catastrophe from an empty lookup. Check the agent name before the backup.');
  end if;

  select started_at, status into v_last, v_status
    from agent_runs where agent = any(c_agents) order by started_at desc limit 1;

  v_stale := (v_last < now() - interval '26 hours') or (coalesce(v_status,'') = 'error');
  if not v_stale then
    return jsonb_build_object('ok', true, 'last', v_last, 'status', v_status, 'watched', c_agents);
  end if;

  -- A DEDUPE WINDOW THE SAME LENGTH AS THE CHECK INTERVAL SUPPRESSES ON A KNIFE EDGE (13 Aug 2026).
  -- The backup was broken from 10 to 12 August and this watcher produced exactly ONE alert:
  -- agent_action 2662 at 2026-08-11 08:00:00.63, one email, still pending. The watcher runs daily
  -- at 08:00, and the previous row was 24 hours old minus a fraction of a second, so it was still
  -- inside `created_at > now() - 24 hours` and the second day's alert was skipped. Twenty hours is
  -- strictly shorter than the cadence, so a daily check always re-alerts on a continuing outage
  -- while a ten-minute caller still cannot spam.
  select count(*) into v_open from agent_actions
   where kind = 'backup_alert' and coalesce(status,'') in ('pending','needs_review')
     and created_at > now() - interval '20 hours';

  if v_open = 0 then
    insert into agent_actions(agent, kind, status, risk, title, recommendation, target_table, detail)
    values('security','backup_alert','pending','high',
      'Document backup to Dropbox has failed or is overdue',
      'The Dropbox document mirror has not completed successfully in the last 26 hours (last: '
      || coalesce(v_last::text,'never') || ', status: ' || coalesce(v_status,'unknown')
      || '). Check the dropbox_backup function and its logs. This concerns stored DOCUMENTS only — '
      || 'the managed Postgres backups are outside this database and are not covered by this check.',
      'agent_runs', jsonb_build_object('last_backup', v_last, 'last_status', v_status, 'watched', c_agents));

    insert into security_events(kind, severity, source, subject, detail)
    values('backup_overdue','high','backup','dropbox document mirror',
      jsonb_build_object('last_backup', v_last, 'last_status', v_status, 'watched', c_agents));

    -- 6 SEP 2026: ONE page per event. The agent_action above is paged by trg_page_high_agent_action
    -- with the backup_alert kind, which founder_mail_policy routes as one org_task; the direct
    -- notifications row that used to sit here was the second of THREE emails for one missed backup.
    -- AN OUTAGE THAT LASTS MUST GET LOUDER, NOT REPEAT ITSELF. Past 48 hours this also pages the
    -- founder and states the age in hours. v_last cannot be NULL here — the positive control above
    -- returned early if the subject had no runs at all — so the "as long as there are records"
    -- branch that produced today's false critical is gone with it.
    if v_last < now() - interval '48 hours' then
      perform public.fn_notify_founder(
        'Document backup failing after retry: no successful Dropbox mirror for '
        || round(extract(epoch from (now() - v_last)) / 3600)::text || ' hours',
        'The Dropbox document mirror has now been failing for '
        || round(extract(epoch from (now() - v_last)) / 3600)::text || ' hours (last run: '
        || v_last::text || ', status: ' || coalesce(v_status,'unknown')
        || '). This covers stored DOCUMENTS — supplier files, quotes, drawings. The managed Postgres '
        || 'backups are a separate system outside this database and this alert says nothing about '
        || 'them either way. Verify the dropbox_backup function.',
        'critical', p_kind => 'backup_failed_after_retry', p_dedupe_key => 'backup_failed_after_retry');
    end if;
  end if;

  return jsonb_build_object('alerted', true, 'last', v_last, 'status', v_status,
                            'existing_open', v_open, 'watched', c_agents);
end
$function$;

do $do$
declare
  v jsonb; v_runs int; v_retracted int; v_closed int;
begin
  ---------------------------------------------------------------------------------------------
  -- PROVE THE FIX ON THE LIVE ESTATE, not on an argument.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_runs from public.agent_runs where agent in ('dropbox_backup','fn:dropbox_backup');
  if v_runs = 0 then
    raise exception 'POSITIVE CONTROL FAILED: no dropbox_backup runs exist either, so this revision has swapped one absent subject for another';
  end if;

  v := public.fn_backup_watch();
  if coalesce(v->>'ok','') <> 'true' then
    raise exception 'the watcher still does not read the estate as healthy: %', v::text;
  end if;
  if (v->>'last') is null then
    raise exception 'the watcher found the agent but no timestamp — that is the old failure in a new place';
  end if;

  ---------------------------------------------------------------------------------------------
  -- WITHDRAW THE FALSE ALARM. The WhatsApp (21251) already went at 08:00:36 and cannot be recalled;
  -- it is left in the ledger as the record that it was sent. The EMAIL is still queued and is
  -- retracted before the next 15-minute tick delivers a critical that is not true.
  ---------------------------------------------------------------------------------------------
  update public.notifications
     set status = 'cancelled',
         last_error = 'Retracted 9 Sep 2026: raised by fn_backup_watch reading agent=''backup'', a '
                   || 'name nothing writes. Measured at retraction: dropbox_backup last ran '
                   || '2026-09-09 07:10:45 UTC, and the managed Postgres backups show seven '
                   || 'consecutive COMPLETED dailies to 8 Sep. There was no backup outage.'
   where id = 21250 and status in ('pending','queued');
  get diagnostics v_retracted = row_count;

  update public.agent_actions
     set status = 'dismissed'
   where id = 10084 and kind = 'backup_alert' and status = 'pending';
  get diagnostics v_closed = row_count;

  raise notice 'fn_backup_watch now watches dropbox_backup (% run(s)) and reports %. Retracted % queued email(s), dismissed % false action(s). The WhatsApp already sent is left in the ledger as sent.',
    v_runs, v::text, v_retracted, v_closed;
end
$do$;
