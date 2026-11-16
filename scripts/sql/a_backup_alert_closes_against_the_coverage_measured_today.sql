-- A BACKUP ALERT CLOSES AGAINST THE COVERAGE MEASURED TODAY (16 Nov 2026). Seat: it_engineer. Agent: OPS_LOOPS
-- (it_engineer + ceo builder, wave 2 of the real-company holes, founder ledgers 1711-1713; hole H9 of the COO hunt).
--
-- MEASURED (production, read-only SELECT, 16 Nov 2026 ~10:00 UTC):
--   * agent_actions pending to it_engineer: 44 backup_coverage (14 Sep -> 15 Nov) and 2 backup_alert (14 Sep, 5 Nov).
--     fn_backup_watch files a new one each day the condition holds (one per 20 hours) and NOTHING ever closes one: no
--     routine updates a backup_coverage or backup_alert row (READ, grep of scripts/sql and the mirror).
--   * The mirror itself recovered on 14 Nov: 60 dropbox_backup runs 'ok' in 3 days, the last at 00:30 today.
--   * Coverage has NOT recovered: 344 doc_backups rows are not done 48 hours after they were queued (fn_backup_coverage's
--     own predicate). All are entity 'company', status waiting_source, queued 13-15 Nov: the daily table export pages
--     ("storage holds no object at backups/<day>/<table>/page_<n>.json"), three days x ~115 tables. So one alert is
--     still true; the other 45 are copies of it or of a stale-mirror alarm that is no longer true.
--
-- WHAT THIS ADDS
--   fn_it_backup_alerts_settle(p_cov jsonb default null): measures the coverage now (fn_backup_coverage, the same reading
--   fn_backup_watch raises on) and the mirror's last run, then closes every pending alert against that measurement:
--     backup_alert    (the mirror is stale): closed 'done' when the mirror has run ok inside 26 hours, with the run it
--                     read; while still stale the newest stays open and every older copy is closed as superseded by it.
--     backup_coverage (something is not in Dropbox after 48 h): all closed 'done' when coverage reads ok; while it fails
--                     the newest stays open, its title and recommendation are rewritten to TODAY's measurement (what is
--                     failing, how many rows, which kind, oldest), and every older copy is closed as superseded by it.
--   Every close carries the measurement it was judged on in evidence (verdict, measured_at, the coverage object), so
--   the queue holds one live alert per live condition and its numbers are today's, not those of the day it was filed.
--   The duty it_engineer.backup_alerts_settle runs it every 6 hours.
-- WHAT IT DOES NOT CHANGE: fn_backup_watch, fn_backup_coverage, the refile handoffs (they have their own closer and the
-- only-it_engineer-closes trigger), any doc_backups row. It does not make the export pages exist: the alert it keeps
-- open says what is missing.
--
-- Probe: scripts/sql/a_backup_alert_closes_against_the_coverage_measured_today_probe.sql (local Postgres 16, run twice).
-- Pending: scripts/sql/pending/a_backup_alert_closes_against_the_coverage_measured_today.txt
-- prevented by: scripts/checks/the_ops_loops_close_against_what_they_measure.test.mjs (this file's shape) and the probe.
--   node scripts/apply_sql.mjs scripts/sql/a_backup_alert_closes_against_the_coverage_measured_today.sql --apply --ddl

create or replace function public.fn_it_backup_alerts_settle(p_cov jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_cov jsonb := coalesce(p_cov, public.fn_backup_coverage());
  v_cov_ok boolean := coalesce((v_cov->>'ok')::boolean, false);
  v_last timestamptz; v_status text; v_stale boolean;
  v_keep bigint; n_done int := 0; n_superseded int := 0; v_superseded_cov int := 0; v_why text; v_oldest date;
  c_agents constant text[] := array['dropbox_backup', 'fn:dropbox_backup'];
begin
  select r.started_at, r.status into v_last, v_status
    from public.agent_runs r where r.agent = any(c_agents) order by r.started_at desc limit 1;
  -- the same reading fn_backup_watch raises a backup_alert on
  v_stale := v_last is null or v_last < now() - interval '26 hours' or coalesce(v_status, '') = 'error';

  -- 1. the mirror alarm
  if not v_stale then
    update public.agent_actions a
       set status = 'done', decided_at = now(), decided_by = 'it_engineer:fn_it_backup_alerts_settle',
           evidence = coalesce(a.evidence, '{}'::jsonb) || jsonb_build_object(
             'verdict', 'the Dropbox mirror ran ' || coalesce(v_status, '?') || ' at ' || to_char(v_last at time zone 'Asia/Dubai', 'DD Mon HH24:MI')
                        || ' (Dubai), inside 26 hours: the condition this alert reported is no longer true',
             'measured_at', now(), 'last_run', v_last, 'last_status', v_status)
     where a.kind = 'backup_alert' and a.agent = 'it_engineer' and coalesce(a.status, '') in ('pending', 'needs_review');
    get diagnostics n_done = row_count;
  else
    select max(a.id) into v_keep from public.agent_actions a
     where a.kind = 'backup_alert' and a.agent = 'it_engineer' and coalesce(a.status, '') in ('pending', 'needs_review');
    if v_keep is not null then
      update public.agent_actions a
         set status = 'dismissed', decided_at = now(), decided_by = 'it_engineer:fn_it_backup_alerts_settle',
             evidence = coalesce(a.evidence, '{}'::jsonb) || jsonb_build_object(
               'verdict', 'superseded by backup alert ' || v_keep || ', which carries today''s measurement of the same condition',
               'measured_at', now(), 'superseded_by', v_keep)
       where a.kind = 'backup_alert' and a.agent = 'it_engineer' and coalesce(a.status, '') in ('pending', 'needs_review') and a.id <> v_keep;
      get diagnostics n_superseded = row_count;
      update public.agent_actions set detail = coalesce(detail, '{}'::jsonb) || jsonb_build_object(
               'measured', jsonb_build_object('at', now(), 'last_run', v_last, 'last_status', v_status))
       where id = v_keep;
    end if;
  end if;

  -- 2. the coverage alarm
  if v_cov_ok then
    update public.agent_actions a
       set status = 'done', decided_at = now(), decided_by = 'it_engineer:fn_it_backup_alerts_settle',
           evidence = coalesce(a.evidence, '{}'::jsonb) || jsonb_build_object(
             'verdict', 'coverage measured ok: nothing queued is past 48 hours, every source has a row, no refile is open past 48 hours',
             'measured_at', now(), 'coverage', v_cov)
     where a.kind = 'backup_coverage' and a.agent = 'it_engineer' and coalesce(a.status, '') in ('pending', 'needs_review');
    get diagnostics v_superseded_cov = row_count;
    n_done := n_done + v_superseded_cov;
  else
    select max(a.id) into v_keep from public.agent_actions a
     where a.kind = 'backup_coverage' and a.agent = 'it_engineer' and coalesce(a.status, '') in ('pending', 'needs_review');
    if v_keep is not null then
      select min(coalesce(d.requeued_at, d.created_at))::date into v_oldest from public.doc_backups d
       where d.status <> 'done' and d.entity <> 'zz_demo' and d.status not in ('prune_pending', 'pruning', 'pruned')
         and not (d.status = 'abandoned' and coalesce(d.error, '') like 'abandoned:%')
         and coalesce(d.requeued_at, d.created_at) < now() - interval '48 hours';
      v_why := 'Measured ' || to_char(now() at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' (Dubai): '
        || coalesce(v_cov->>'not_done_after_48h', '?') || ' queued row(s) not done after 48 hours'
        || coalesce(' (oldest queued ' || to_char(v_oldest, 'DD Mon') || ')', '') || ', '
        || coalesce(v_cov->>'sources_without_a_row', 'unknown') || ' source(s) with no row, '
        || coalesce(v_cov->>'refiles_open_past_48h', '?') || ' refile(s) not verified. Failing: '
        || coalesce((select string_agg(x, ', ') from jsonb_array_elements_text(coalesce(v_cov->'failing', '[]'::jsonb)) x), 'unknown')
        || '. First rows: ' || coalesce(v_cov->>'not_done_ids', '[]') || '.';
      update public.agent_actions a
         set status = 'dismissed', decided_at = now(), decided_by = 'it_engineer:fn_it_backup_alerts_settle',
             evidence = coalesce(a.evidence, '{}'::jsonb) || jsonb_build_object(
               'verdict', 'superseded by backup coverage alert ' || v_keep || ', which carries today''s measurement',
               'measured_at', now(), 'superseded_by', v_keep)
       where a.kind = 'backup_coverage' and a.agent = 'it_engineer' and coalesce(a.status, '') in ('pending', 'needs_review') and a.id <> v_keep;
      get diagnostics v_superseded_cov = row_count;
      n_superseded := n_superseded + v_superseded_cov;
      update public.agent_actions
         set title = left('Dropbox backup coverage failing: ' || coalesce(v_cov->>'failing', '?') || ' (measured '
                          || to_char(now() at time zone 'Asia/Dubai', 'DD Mon') || ')', 200),
             recommendation = v_why,
             detail = coalesce(detail, '{}'::jsonb) || jsonb_build_object('measured', v_cov, 'measured_at', now())
       where id = v_keep;
    end if;
  end if;

  return jsonb_build_object('mirror_stale', v_stale, 'last_run', v_last, 'coverage_ok', v_cov_ok,
    'closed_done', n_done, 'closed_superseded', n_superseded, 'kept_open', v_keep,
    'open_now', (select count(*) from public.agent_actions a
                  where a.kind in ('backup_coverage', 'backup_alert') and a.agent = 'it_engineer'
                    and coalesce(a.status, '') in ('pending', 'needs_review')));
end $fn$;
revoke execute on function public.fn_it_backup_alerts_settle(jsonb) from public, anon, authenticated;

create or replace function public.fn_it_backup_alerts_settle_now()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_it_backup_alerts_settle(null) $fn$;
revoke execute on function public.fn_it_backup_alerts_settle_now() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file)
values ('it_engineer.backup_alerts_settle', 'it_engineer', interval '6 hours', 'fn_it_backup_alerts_settle_now',
        'Every pending backup_alert and backup_coverage alert is judged against the coverage and the mirror run measured now: closed when its condition no longer holds, otherwise one stays open with today''s numbers and its older copies are closed as superseded.',
        'scripts/sql/a_backup_alert_closes_against_the_coverage_measured_today.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

-- VERDICT (this file defines routines, so it never raises to report)
select case
  when to_regprocedure('public.fn_it_backup_alerts_settle(jsonb)') is null then 'PROBE FAILED: no fn_it_backup_alerts_settle'
  when has_function_privilege('anon', 'public.fn_it_backup_alerts_settle(jsonb)', 'execute')
    or has_function_privilege('anon', 'public.fn_it_backup_alerts_settle_now()', 'execute')
    then 'PROBE FAILED: anon can execute a backup settle routine'
  when not exists (select 1 from public.seat_duty where duty = 'it_engineer.backup_alerts_settle' and enabled)
    then 'PROBE FAILED: the settle duty is not registered'
  else 'PROBE OK' end as verdict;
