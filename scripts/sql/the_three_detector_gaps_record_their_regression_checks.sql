-- THE THREE DETECTOR GAPS RECORD THEIR FIX AND REGRESSION CHECK ON THE INCIDENTS THAT SHOWED THEM.
-- Seat: it_engineer, 7 Oct 2026. Data only. Apply AFTER
--   scripts/sql/the_29_parked_it_handoffs_of_23_september_to_5_october_close_with_what_was_learned.sql (PR #1281),
-- which records each incident's investigated cause; this file keeps that cause and replaces only the fix and the
-- regression check, through fn_it_attach_learning (the learning gate's own door), by exact handoff id and issue key.
-- A row whose incident has no cause yet is SKIPPED and says so: the cause is never written here.
--
-- Rolled-back proof of each fix, 7 Oct 2026, is in the three files it names and in the PR body.
--
--   node scripts/apply_sql.mjs scripts/sql/the_three_detector_gaps_record_their_regression_checks.sql --apply --ddl

create temp table if not exists _qd_gap (subject text, outcome text, evidence jsonb) on commit drop;

do $gap$
declare
  v record; h public.agent_actions; i public.it_incident; r jsonb;
  c_by constant text := 'it_engineer (the_three_detector_gaps_record_their_regression_checks.sql, 7 Oct 2026)';
  c_test constant text := 'scripts/checks/the_three_detector_gaps_of_the_learning_audit_stay_closed.test.mjs';
  c_silent_fix constant text := 'scripts/sql/a_silence_is_judged_against_the_rhythm_a_subject_still_keeps.sql: run_silent builds a rhythm from served (not refused) runs, ignores a sub-minute burst median, and does not judge a subject whose last completed gap already left the old rhythm. Replayed on the incident times: the old rule raised at every one, the new rule at none; a 3-hour stop of send_outbox, wa_status or resilience_ping is still raised.';
begin
  for v in select * from (values
    (100487::bigint, 'watch:refusal_rate:claim_lookup',
     'scripts/sql/our_own_claim_lookup_probe_proves_itself.sql with supabase/functions/claim_lookup/index.ts and _shared/launch_path.ts: the hourly probe presents cred_fn_resilience_ping in x-qd-probe and its invalid-link refusal is marked fixture, which refusal_rate excludes.',
     'refusal_rate'),
    (130872, 'duty:workflow_heartbeat:dropbox_kick',
     'scripts/sql/a_debounced_backup_kick_is_still_a_heartbeat.sql: a debounced scheduler kick (reason github_actions) is recorded in agent_runs, which the dropbox_kick heartbeat reads. Rolled back on 7 Oct: heartbeat rows from a debounced call 0 before, 1 after; per-document trigger kicks still record nothing.',
     'workflow_heartbeat_missing'),
    (100470, 'watch:run_silent:ai_gateway', null, 'run_silent'),
    (124134, 'watch:run_silent:unsubscribe', null, 'run_silent'),
    (126399, 'watch:run_silent:unsubscribe', null, 'run_silent'),
    (113776, 'watch:run_silent:wa_templates_watch', null, 'run_silent'),
    (124155, 'watch:run_silent:wa_templates_watch', null, 'run_silent'),
    (126665, 'watch:run_silent:wa_templates_watch', null, 'run_silent'),
    (126895, 'watch:run_silent:wa_templates_watch', null, 'run_silent'),
    (127260, 'watch:run_silent:wa_templates_watch', null, 'run_silent'),
    (127620, 'watch:run_silent:wa_templates_watch', null, 'run_silent'),
    (127909, 'watch:run_silent:wa_templates_watch', null, 'run_silent'),
    (132372, 'watch:run_silent:wa_templates_watch', null, 'run_silent')
  ) as t(id, issue_key, fix, playbook_class) loop
    begin
      select * into h from public.agent_actions where id = v.id;
      if h.id is null or h.detail->>'type' <> 'it.finding' or h.detail->>'issue_key' is distinct from v.issue_key then
        insert into _qd_gap values ('handoff ' || v.id, 'SKIPPED: not the listed it.finding handoff', null); continue;
      end if;
      select * into i from public.it_incident where handoff_id = v.id;
      if i.id is null or coalesce(btrim(i.cause), '') = '' then
        insert into _qd_gap values ('handoff ' || v.id, 'SKIPPED: no recorded cause yet; apply the #1281 file first', null); continue;
      end if;
      r := public.fn_it_attach_learning(v.id, i.cause, coalesce(v.fix, c_silent_fix),
             c_test || case when v.playbook_class = 'run_silent' then '; fn_it_detect run_silent re-raises the key'
                            when v.playbook_class = 'refusal_rate' then '; fn_it_detect refusal_rate re-raises the key'
                            else '; the workflow_heartbeat duty (dropbox_kick, 12 h) re-raises the key' end,
             v.playbook_class, null, c_by);
      insert into _qd_gap values ('handoff ' || v.id, 'RECORDED', jsonb_build_object('incident_id', i.id, 'attach', r));
    exception when others then
      insert into _qd_gap values ('handoff ' || v.id, 'ERROR: ' || left(sqlerrm, 300), null);
    end;
  end loop;
end
$gap$;

select subject, outcome, evidence from _qd_gap
union all
select 'VERDICT',
       case when count(*) filter (where outcome <> 'RECORDED') = 0 and count(*) = 13 then 'PROBE OK' else 'PROBE FAILED' end,
       jsonb_build_object('rows', count(*), 'recorded', count(*) filter (where outcome = 'RECORDED'))
  from _qd_gap;
