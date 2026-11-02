-- A WARNED OR SKIPPED RUN IS NOT A FAILED RUN (it_engineer, 27 Oct 2026; IT-C14, ledger 1003 stage 2).
--
-- Assigned: it_engineer. Redefines fn_it_engineer_run_clusters (canonical until now:
-- the_it_engineer_turns_every_failing_run_label_into_an_owned_finding.sql). The body below is the LIVE body read with
-- pg_get_functiondef on 27 Oct 2026 (prosrc md5 739cd4c2356e723082121175bdcc76b9, equal to that file), changed only
-- where a run is counted as failed.
--
-- ══ MEASURED, 27 Oct 2026, htdblwldjkcgjvmqkbeh (read-only) ═════════════════════════════════════════════════════════
--   agent_runs, last 7 days: 38,822 ok, 999 warn, 281 skipped, 151 error. The routine counted every status but 'ok' as a
--   failure, so its 17:05 UTC run opened three findings and two of them are a healthy day:
--     duty:run_cluster:fn:unsubscribe     "failed 18 of 18 runs (warn 18)"  - HTTP 400 "Invalid" page for a bad
--                                          unsubscribe link, the function answering correctly;
--     duty:run_cluster:fn:quote_compare   "failed 17 of 17 runs (warn 17)"  - HTTP 409 need_two, "Comparison needs at
--                                          least two complete quotes", the guard answering correctly;
--     duty:run_cluster:fn:license_extract "failed 10 of 10 runs (error 10)" - a real failure, which stays.
--   Over the same 7 days without the fixture filter: compliance_archive 196/196 skipped (refusing a Terms certificate
--   for an @example.invalid customer) and login_otp 68/68 skipped; fn:login_otp 288/571 warn (HTTP 404/409 to a mobile
--   number with no single account). Each is a guard or a 4xx doing its job.
--
-- ══ WHAT CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════════
--   A run is FAILED unless it is ok, skipped, or a warn whose note starts 'HTTP 4' plus two digits (the edge functions' own
--   log of a 4xx answer). Review of #1679 (27 Oct): internal agents record real degradation as warn - dropbox_backup 18
--   ("The Dropbox token endpoint did not answer usefully"), it_engineer 19 ("HELD: the inbox placement seed ... was not
--   found") - so excusing every warn would let a backup that warns on every run never form a cluster. A warn with any
--   other note, or a NULL note (coalesce), still counts. A missing status ('none') and any status not
--   named here (error today; held and refused, seen in the history, are not in the last 7 days) still count, so a new
--   status fails closed. The cluster rule, the 7 days, the fixture split, the owner, the unowned flag and the close
--   loop are unchanged. The evidence key non_ok_7d becomes failed_7d (no reader: grep of scripts/, supabase/, src/).
--   After apply, the daily run closes the unsubscribe and quote_compare findings with the reading that cleared them.
--   CREATE OR REPLACE keeps the ACL (live: postgres and service_role only); the revoke below is the file's own guard.
--
-- Prevented by: scripts/checks/the_it_engineer_turns_every_failing_run_label_into_an_owned_finding.test.mjs (static)
-- and scripts/sql/a_warned_or_skipped_run_is_not_a_failed_run_probe.sql (red on the live body, green with this file).
-- Pending: scripts/sql/pending/a_warned_or_skipped_run_is_not_a_failed_run.txt
--   node scripts/apply_sql.mjs scripts/sql/a_warned_or_skipped_run_is_not_a_failed_run.sql --apply --ddl

create or replace function public.fn_it_engineer_run_clusters()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_prefix text := case when coalesce(current_setting('qd.duty_fixtures', true), '') = 'on' then 'duty:run_cluster:fixture:' else 'duty:run_cluster:' end;
  r record; v_owner text; v_subject text; v_key text; v_res jsonb;
  v_labels text[] := '{}'; n_found int := 0; n_new int := 0; n_unowned int := 0; n_closed int := 0; f record;
begin
  for r in
    with runs as (
      select ar.agent as label, coalesce(ar.status, 'none') as status, ar.note
        from public.agent_runs ar
       where ar.started_at > now() - interval '7 days'
         and (coalesce(ar.counts->>'fixture', '0') in ('1', 'true')
              or coalesce(ar.counts->>'caller', '') = 'fixture'
              or coalesce(ar.note, '') ilike '%example.invalid%'
              or coalesce(ar.note, '') like '%ZZ DEMO%') = v_fx)
    -- A FAILED RUN is any run but an ok, a skipped (a guard refusing correctly) or a warn whose note starts 'HTTP 4xx'
    -- (a request correctly answered 4xx). A warn with any other note - or none - is an outage reported softly
    -- (dropbox_backup, it_engineer) and counts; so does a missing status ('none'). 'not ok' was the old rule.
    select label, count(*) as runs, count(*) filter (where status not in ('ok', 'skipped') and not (status = 'warn' and coalesce(note, '') ~ '^HTTP 4[0-9][0-9]')) as non_ok,
           (select jsonb_object_agg(s, n) from (select status s, count(*) n from runs r2 where r2.label = runs.label group by 1) z) as statuses,
           (select jsonb_agg(x) from (select distinct left(r3.note, 200) x from runs r3
              where r3.label = runs.label and r3.status not in ('ok', 'skipped') and not (r3.status = 'warn' and coalesce(r3.note, '') ~ '^HTTP 4[0-9][0-9]') and r3.note is not null limit 3) z) as notes
      from runs
     group by label
    having count(*) > 5 and count(*) filter (where status not in ('ok', 'skipped') and not (status = 'warn' and coalesce(note, '') ~ '^HTTP 4[0-9][0-9]')) * 2 > count(*)
     order by count(*) filter (where status not in ('ok', 'skipped') and not (status = 'warn' and coalesce(note, '') ~ '^HTTP 4[0-9][0-9]')) desc
  loop
    n_found := n_found + 1;
    v_labels := v_labels || r.label;
    v_subject := regexp_replace(r.label, '^fn:', '');
    v_owner := coalesce(
      (select o.owner from public.function_owner o join public.org_role s on s.role_id = o.owner and s.status = 'active'
        where o.function_slug = v_subject),
      (select d.owner_seat from public.seat_duty d join public.org_role s on s.role_id = d.owner_seat and s.status = 'active'
        where d.routine = v_subject or d.routine = 'fn_' || v_subject limit 1));
    if v_owner is null then n_unowned := n_unowned + 1; end if;
    v_key := v_prefix || r.label;
    v_res := public.fn_it_engineer_finding_upsert(
      v_key,
      format('%s%s failed %s of %s runs in 7 days (%s)%s', case when v_fx then 'ZZ DEMO ' else '' end, r.label, r.non_ok, r.runs,
             (select string_agg(k || ' ' || v, ', ' order by k) from jsonb_each_text(r.statuses) e(k, v)),
             case when v_owner is null then ' - no seat owns this run label' else '' end),
      'agent_runs label ' || r.label,
      'internal',
      r.non_ok::int,
      jsonb_strip_nulls(jsonb_build_object(
        'duty', 'it_engineer.run_clusters', 'subject', v_subject, 'owner_seat', v_owner, 'unowned', v_owner is null,
        'runs_7d', r.runs, 'failed_7d', r.non_ok, 'statuses', r.statuses, 'sample_notes', r.notes,
        'rule', 'more than 5 runs and more than half failed in 7 days; ok, skipped and a warn noted HTTP 4xx are not failures (IT-C14)', 'demo', v_fx)),
      array['fixture runs counted apart'],
      case when v_owner is null then array['which seat owns this run label'] else '{}'::text[] end,
      'it_engineer');
    if (v_res->>'seen_count')::int = 1 or coalesce((v_res->>'reopened')::boolean, false) then n_new := n_new + 1; end if;
  end loop;

  -- a label that is no longer a cluster: its finding is closed with the reading that cleared it
  for f in select e.issue_key, substr(e.issue_key, length(v_prefix) + 1) as label from public.it_engineer_finding e
            where e.closed_at is null and e.issue_key like v_prefix || '%'
              and (v_fx or e.issue_key not like 'duty:run_cluster:fixture:%') loop
    continue when f.label = any (v_labels);
    perform public.fn_it_engineer_finding_close(f.issue_key, format('cleared: %s now has %s failed of %s runs in 7 days (rule: more than 5 runs and more than half failed; ok, skipped and a warn noted HTTP 4xx are not failures)',
      f.label,
      (select count(*) filter (where coalesce(status, 'none') not in ('ok', 'skipped') and not (coalesce(status, 'none') = 'warn' and coalesce(note, '') ~ '^HTTP 4[0-9][0-9]')) from public.agent_runs where agent = f.label and started_at > now() - interval '7 days'),
      (select count(*) from public.agent_runs where agent = f.label and started_at > now() - interval '7 days')));
    n_closed := n_closed + 1;
  end loop;

  return jsonb_build_object('clusters', n_found, 'new_or_reopened', n_new, 'unowned', n_unowned, 'closed', n_closed,
                            'labels', to_jsonb(v_labels), 'fixture', v_fx);
end $fn$;

revoke execute on function public.fn_it_engineer_run_clusters() from public, anon, authenticated;

update public.seat_duty
   set what = 'IT-C14: every run label with more than 5 runs and more than half failed in 7 days (anything but ok, skipped or a warn noted HTTP 4xx; fixture runs apart) is one owned finding, handed to its owner by the IT loop; a label no seat owns says so; a cleared label''s finding is closed with its reading.',
       owner_file = 'scripts/sql/a_warned_or_skipped_run_is_not_a_failed_run.sql'
 where duty = 'it_engineer.run_clusters';
