-- THE CLEARED IT FINDINGS IN THE CEO QUEUE CLOSE BY EXACT ID WITH WHAT WAS LEARNED (19 OCT 2026).
--
-- Seat: it_engineer. Data only: playbook rows, learning on existing incidents, closes by exact key. No routine.
--
-- MEASURED, read-only, 19 Oct 2026 ~01:40 Dubai: 149 support_ceo_report rows from it_engineer to the CEO are
-- 'accepted' (135 distinct issue keys; 137 carry an it.finding handoff, 12 are dropbox_backup_escalation:<day>).
-- 25 of the handoffs have a cleared occurrence (the gate's own test: finding closed, or restarted after the
-- handoff's occurrence) and an it_incident lacking cause, fix or regression check, so trigger z62 keeps them
-- open. This file closes 21 of them. The other 4 (watch:run_failure:llm_gateway_auth, handoffs 148364, 149825,
-- 152386, 159735) are NOT closed: the finding flaps open/closed with traffic and its cause is live (callers
-- public_site, inquiry_intake, marketing_social_inbox, marketing_lead_sourcing have no cred_fn_<name>, fall back
-- to the inactive legacy.shared credential, and ai_gateway answers 403: 71 + 8 refusals in 14 days, last
-- 18 Oct 20:09Z). Closing them with a fix that has not happened would be false.
--
-- Also closed by exact key, release-train findings whose subject is gone (coordinator ruling, 19 Oct):
--   #1007 its probe file is no longer on main (superseded by #1149's probe);
--   #1149 its pure probe, run alone on production 19 Oct in an aborted transaction, returned PROBE OK
--         (fn_sales_engineer_nudges_invited_suppliers(timestamptz,int,boolean) and fn_supplier_invite_nudges_due
--         exist; the refusal was the apply guard reading the zero-argument call before #1149's definitions landed);
--   #1258 its file is in MANIFEST.txt, i.e. applied after the seat-less refusal.
-- #1007 carries handoff 124156 in the CEO queue; it closes through the same learning gate.
--
-- Evidence for each row: it_engineer_finding.evidence and close_note, it_incident, agent_runs, backup_prune_log,
-- reasoning_held_question, gl_journal, git history (e28a344 #1305, 912fc78). Where a cause could not be
-- established the row says "NOT established" and what is missing. Every regression check named is a file on
-- origin/main on 19 Oct or the live duty that re-raises the key.
--
-- HOW: the 7 Oct pattern (the_29_parked_it_handoffs_..._close_with_what_was_learned.sql). Per id, at apply time:
-- still pending, an it.finding, EXACTLY the listed issue key, occurrence cleared, incident exists. Only then
-- fn_it_attach_learning (z62 not bypassed) closes it, and the 'it_loop:<id>' CEO report is completed by exact
-- key only if the handoff really closed. A field the incident already carries is kept. Re-applying is safe.
--
--   node scripts/apply_sql.mjs scripts/sql/the_cleared_it_findings_in_the_ceo_queue_close_with_what_was_learned_19_october.sql --apply --ddl

-- ── 1. PLAYBOOK ENTRIES FOR THE FAILURE CLASSES THAT HAD NONE ──────────────────────────────────────
insert into public.it_playbook (failure_class, issue_prefix, typical_cause, remedy, not_automatable_reason, regression_check, added_by, added_at)
values
  ('books_stale', 'acct:books:',
   'Nothing reached the expenses mailbox for days, so the accountant had nothing to post and the books aged past 2 days.',
   null, 'The remedy is mail arriving (or the founder forwarding receipts); no routine can create it.',
   'fn_accountant_books_duty (scripts/sql/the_accountant_runs_its_duties_every_hour.sql) re-raises the key',
   'it_engineer (19 Oct 2026)', now()),
  ('marketing_plan_review_stalled', 'ceo:marketing_plan_review_stalled:',
   'The CEO''s review of a marketing plan waited on a reasoning question under the model hold.',
   null, 'The review is the CEO''s judgement through the model; it runs when the question is reasoned.',
   'fn_ceo_marketing_plan_watch (scripts/sql/a_month_an_approved_calendar_already_covers_is_not_a_late_plan.sql) re-raises the key',
   'it_engineer (19 Oct 2026)', now()),
  ('backup_prune_lag', 'duty:backup_prune:',
   'Retention flags every delete-mode day older than 2 days that storage has not removed yet; the worker removes a batch per pass, so a long queue is flagged before its turn. If it persists, the tick itself is failing (see duty:heartbeat:backupPrune).',
   null, 'Lag clears as the worker drains; a stuck tick is a heartbeat_step fault with its own remedy.',
   'fn_backup_prune_tick settles duty:backup_prune and re-raises the key',
   'it_engineer (19 Oct 2026)', now()),
  ('media_below_recommended', 'duty:marketing_media_below_recommended:',
   'Informational: a published video is below the platform''s recommended bitrate. Never a refusal; the duty looks at the last 7 days only, so it clears by age.',
   null, 'Information, not a fault: nothing to remediate.',
   'supplier-facing settle in supabase/functions/marketing_channels/index.ts (7-day window) re-raises the key',
   'it_engineer (19 Oct 2026)', now()),
  ('review_independence', 'duty:review_independence:',
   'A review row named no author model, or a review was held for want of an independent reviewer; seen when a rehearsal outlived its window or a drill judged a turn no model answered.',
   null, 'Each occurrence needs reading which author/reviewer was missing; fixed in code when it is a harness or gateway defect.',
   'scripts/checks/a_technical_item_is_never_a_decision_for_the_founder.test.mjs; the review_independence duty re-raises the key',
   'it_engineer (19 Oct 2026)', now())
  ,('release_train_apply_refused', 'release_train:',
   'The release train''s apply of a merged file was refused by a guard (a callee not yet on the database, or no seat named), so the file did not reach production.',
   null, 'Each refusal names its own fix (apply the defining file first, or name the seat); the operator re-applies.',
   'scripts/apply_sql.mjs guards; the release train re-raises release_train:#<pr>:<file> on any failed apply',
   'it_engineer (19 Oct 2026)', now())
on conflict do nothing;

-- ── 2. CLOSE BY EXACT KEY: RELEASE-TRAIN FINDINGS WHOSE SUBJECT IS GONE ─────────────────────────────
create temp table if not exists _qd_resolution (subject text, outcome text, evidence jsonb) on commit drop;

do $rt$
declare v record;
begin
  for v in select * from (values
    ('release_train:#1007:scripts/sql/an_invited_supplier_who_never_opened_the_invitation_is_nudged_on_day_3_7_and_14_probe.sql',
     'Closed by exact key (it_engineer, 19 Oct 2026): the probe file is no longer on main; #1149''s probe superseded it and returns PROBE OK.'),
    ('release_train:#1149:scripts/sql/an_unopened_supplier_invitation_is_nudged_on_day_3_7_and_14_under_the_same_switch_cap_and_brakes_probe.sql',
     'Closed by exact key (it_engineer, 19 Oct 2026): the pure probe, run alone on production in an aborted transaction on 19 Oct, returned PROBE OK; both routines it calls exist.'),
    ('release_train:#1258:scripts/sql/the_seat_that_owed_the_ceo_a_decision_closes_it_once_the_decision_comes_back.sql',
     'Closed by exact key (it_engineer, 19 Oct 2026): the file was refused for want of a seat, then applied; it is in MANIFEST.txt.')
  ) t(issue_key, note) loop
    if exists (select 1 from public.it_engineer_finding where issue_key = v.issue_key and closed_at is null) then
      perform public.fn_it_engineer_finding_close(v.issue_key, v.note);
      insert into _qd_resolution values (v.issue_key, 'CLOSED', null);
    else
      insert into _qd_resolution values (v.issue_key, 'ALREADY CLOSED', null);
    end if;
  end loop;
end
$rt$;

-- ── 3. THE CLEARED HANDOFFS CLOSE THROUGH THE LEARNING GATE ────────────────────────────────────────
do $res$
declare
  v record; h public.agent_actions; f public.it_engineer_finding; i public.it_incident;
  v_cleared boolean; v_reopened boolean; r jsonb; n_rep int;
  c_by constant text := 'it_engineer (the_cleared_it_findings_in_the_ceo_queue_close_with_what_was_learned_19_october.sql)';
  c_bp_fix constant text := 'No code: the queue drained. backup_prune_log rows for this day have storage_deleted_at 10 Oct 00:01Z, and the 23:31Z settle closed the key. The later days (08-24 onward) stayed open because fn_backup_prune_tick has since timed out on every run (duty:heartbeat:backupPrune), fixed in a separate PR.';
  c_bp_rc constant text := 'fn_backup_prune_tick settles duty:backup_prune and re-raises the key; duty:heartbeat:backupPrune catches a failing tick';
  c_media constant text := 'Informational, not a fault: the published YouTube video is below the platform''s recommended bitrate (for example m1-11 at 694 kbps video, 152 kbps mono audio, against 12,000 kbps and 384 kbps stereo recommended). Nothing was refused.';
  c_media_fix constant text := 'No change, intended: the duty reads posts published in the last 7 days only (supabase/functions/marketing_channels/index.ts), so each key cleared about 7 days after it opened. Escalating an affected=0 info finding to the CEO is a detector defect, named open.';
  c_media_rc constant text := 'The settle in supabase/functions/marketing_channels/index.ts re-raises the key for any post in its 7-day window';
begin
  for v in select * from (values
    (93625::bigint, 'acct:books:books_stale',
     'No mail reached the expenses mailbox from 24 Sep to 5 Oct, so the books had nothing to post (last journal 19 Sep) and aged past the 2-day limit.',
     'Data, no code: mail arrived 5 Oct and was posted (journal dated 1 Oct); a gl_journal row created 7 Oct 21:45:41Z is the second the finding closed.',
     'fn_accountant_books_duty (scripts/sql/the_accountant_runs_its_duties_every_hour.sql) re-raises the key', 'books_stale'),
    (127629, 'ceo:marketing_plan_review_stalled:2026-11-01',
     'The CEO''s review of the November plan waited on reasoning_held_question 10579 under the model hold (escalated 2 Oct, 3 attempts); the review could not run while the hold was on.',
     'No code: 10579 was reasoned and applied 12 Oct 22:32Z (verdict: rejected for revision); the next watch pass closed the key 13 Oct 20:31Z. Open gap, not closed here: the plan still reads ceo_reviewing.',
     'fn_ceo_marketing_plan_watch (scripts/sql/a_month_an_approved_calendar_already_covers_is_not_a_late_plan.sql) re-raises the key', 'marketing_plan_review_stalled'),
    (150241, 'duty:backup_prune:storage:2026-08-15', null, 'bp', 'bp', 'backup_prune_lag'),
    (150242, 'duty:backup_prune:storage:2026-08-16', null, 'bp', 'bp', 'backup_prune_lag'),
    (150243, 'duty:backup_prune:storage:2026-08-17', null, 'bp', 'bp', 'backup_prune_lag'),
    (150244, 'duty:backup_prune:storage:2026-08-18', null, 'bp', 'bp', 'backup_prune_lag'),
    (150245, 'duty:backup_prune:storage:2026-08-19', null, 'bp', 'bp', 'backup_prune_lag'),
    (150246, 'duty:backup_prune:storage:2026-08-20', null, 'bp', 'bp', 'backup_prune_lag'),
    (150247, 'duty:backup_prune:storage:2026-08-21', null, 'bp', 'bp', 'backup_prune_lag'),
    (150248, 'duty:backup_prune:storage:2026-08-22', null, 'bp', 'bp', 'backup_prune_lag'),
    (150249, 'duty:backup_prune:storage:2026-08-23', null, 'bp', 'bp', 'backup_prune_lag'),
    (126390, 'duty:marketing_duties:reviews',
     'fn_marketing_reviews_tick filed the CEO handoff inside the UPDATE that stores its id, and filing writes back to the same marketing_review row: SQLSTATE 27000, tuple already modified (336 sightings).',
     'Commit e28a344 (#1305, 12 Oct 11:52Z): the handoff id is filed into a variable first, then stored. The key closed 12 Oct 12:01Z.',
     'scripts/checks/no_routine_files_a_handoff_inside_the_update_that_stores_its_id.test.mjs', 'marketing_duty_failing'),
    (134400, 'duty:marketing_media_below_recommended:m1-03-youtube', 'media', 'media', 'media', 'media_below_recommended'),
    (126869, 'duty:marketing_media_below_recommended:m1-04-youtube', 'media', 'media', 'media', 'media_below_recommended'),
    (149452, 'duty:marketing_media_below_recommended:m1-05-youtube', 'media', 'media', 'media', 'media_below_recommended'),
    (149928, 'duty:marketing_media_below_recommended:m1-07-youtube', 'media', 'media', 'media', 'media_below_recommended'),
    (126356, 'duty:marketing_media_below_recommended:m1-11-youtube', 'media', 'media', 'media', 'media_below_recommended'),
    (159904, 'duty:review_independence:review_author_unknown:sales_engineer_conversation_drill',
     'E2E drill 2d02a7bd judged a turn the agent never answered, so the review recorded its author as unknown (ai_cost_log 19198).',
     'Commit 912fc78 (on main 18 Oct 19:25Z): the drill skips the judge when no agent model answered, and the unknown-author watch ignores rehearsal rows. The key closed 18 Oct 20:24Z.',
     'scripts/checks/a_technical_item_is_never_a_decision_for_the_founder.test.mjs', 'review_independence'),
    (159192, 'duty:review_independence:review_held:visitor_chat', null,
     'Commit 912fc78: ai_gateway no longer records a rehearsal_window_closed refusal as a review hold. Hold 71 closed 18 Oct 20:24Z.',
     'scripts/checks/a_technical_item_is_never_a_decision_for_the_founder.test.mjs', 'review_independence'),
    (150144, 'duty:workflow_heartbeat:parity',
     'No parity reading for 36 h: the scheduled project-parity runs failed 8-11 Oct, so no reading arrived. The 9 Oct occurrence cleared after the successful runs of 12 Oct. What produced the later 18 Oct 17:46Z close of the re-opened key is NOT established (no successful parity run shows at that time).',
     'No code for the heartbeat: readings resumed when the parity workflow succeeded on 12 Oct. The scheduled run has been red again since 13 Oct (canonical_routine_manifest, every_alarm_is_quiet_on_a_healthy_day) and the key will re-open on its own if readings stop.',
     'fn_it_workflow_heartbeats() (the workflow_heartbeat duty, 36 h) re-raises the key', 'workflow_heartbeat_missing'),
    (144532, 'knowledge_recall:sales_engineer',
     'Arabic recall@5 sat at 0.548-0.549 against the 0.55 floor from 7 to 11 Oct (English about 0.70), then fell to AR 0.050 / EN 0.473 on 13 Oct and recovered to AR 0.588 / EN 0.679 on 14 Oct. The cause of the 13 Oct fall is NOT established: per-pack recall for that run and the kb vector counts at that time were not kept. Candidates in the window, untested: #1259 and #1297 (12 Oct).',
     'NOT established which change restored it; the exam passed on 14 Oct 12:31Z and the key closed.',
     'fn_it_engineer_knowledge_recall_exam() (scripts/sql/the_knowledge_exam_scores_the_bilingual_path_and_holds_an_arabic_floor.sql) re-raises the key below the floor', 'knowledge_recall_gap'),
    (124156, 'release_train:#1007:scripts/sql/an_invited_supplier_who_never_opened_the_invitation_is_nudged_on_day_3_7_and_14_probe.sql',
     'The release train applied a pure probe before the routines it calls were on the database (the apply guard refused: fn_sales_engineer_nudges_invited_suppliers, fn_supplier_invite_nudges_due missing on 29 Sep).',
     'The routines landed with #1149; #1149''s probe superseded this file, which is no longer on main, and returns PROBE OK on production (19 Oct, aborted transaction). Key closed by exact key in section 2.',
     'scripts/apply_sql.mjs refuses a file whose callees are missing; the release train re-raises release_train:#<pr>:<file> on any failed apply', 'release_train_apply_refused')
  ) as t(id, issue_key, cause, fix, regression_check, playbook_class) loop
    begin
      select * into h from public.agent_actions where id = v.id;
      if h.id is null or h.kind <> 'handoff' or h.detail->>'type' <> 'it.finding' then
        insert into _qd_resolution values ('handoff ' || v.id, 'SKIPPED: not an it.finding handoff', null); continue;
      end if;
      if h.status = 'done' then
        insert into _qd_resolution values ('handoff ' || v.id, 'ALREADY CLOSED', jsonb_build_object('decided_at', h.decided_at)); continue;
      end if;
      if h.status <> 'pending' or h.detail->>'issue_key' is distinct from v.issue_key then
        insert into _qd_resolution values ('handoff ' || v.id, 'SKIPPED: status or issue key differs from the list',
          jsonb_build_object('status', h.status, 'issue_key', h.detail->>'issue_key', 'listed', v.issue_key)); continue;
      end if;
      select * into f from public.it_engineer_finding where issue_key = v.issue_key;
      v_reopened := f.issue_key is not null and f.started_at > (h.detail->>'occurrence_started_at')::timestamptz;
      v_cleared := f.issue_key is null or f.closed_at is not null or v_reopened;
      if not v_cleared then
        insert into _qd_resolution values ('handoff ' || v.id, 'SKIPPED: the occurrence is still open',
          jsonb_build_object('issue_key', v.issue_key, 'started_at', f.started_at)); continue;
      end if;
      select * into i from public.it_incident where handoff_id = v.id;
      if i.id is null then
        insert into _qd_resolution values ('handoff ' || v.id, 'SKIPPED: no incident', null); continue;
      end if;

      r := public.fn_it_attach_learning(v.id,
        coalesce(nullif(btrim(i.cause), ''), case v.cause when 'media' then c_media else v.cause end),
        coalesce(nullif(btrim(i.fix), ''), case v.fix when 'bp' then c_bp_fix when 'media' then c_media_fix else v.fix end),
        coalesce(nullif(btrim(i.regression_check), ''), case v.regression_check when 'bp' then c_bp_rc when 'media' then c_media_rc else v.regression_check end),
        v.playbook_class, null, c_by);

      n_rep := 0;
      if coalesce((r->>'closed')::boolean, false) then
        update public.support_ceo_report
           set status = 'completed', completed_at = now(),
               completion_note = 'IT engineer re-verified: handoff ' || v.id || ' is closed with its learning recorded (' || c_by || ').'
         where idempotency_key = 'it_loop:' || v.id and status = 'accepted';
        get diagnostics n_rep = row_count;
      end if;
      insert into _qd_resolution values ('handoff ' || v.id,
        case when coalesce((r->>'closed')::boolean, false) then 'CLOSED' else 'LEARNING RECORDED, NOT CLOSED' end,
        jsonb_build_object('issue_key', v.issue_key, 'incident_id', i.id, 'finding_closed_at', f.closed_at,
                           'reopened_later', v_reopened, 'report_completed', n_rep, 'attach', r));
    exception when others then
      insert into _qd_resolution values ('handoff ' || v.id, 'ERROR: ' || left(sqlerrm, 300), null);
    end;
  end loop;
end
$res$;

select subject, outcome, evidence from _qd_resolution
union all
select 'VERDICT',
       case when count(*) filter (where outcome like 'SKIPPED%' or outcome like 'ERROR%' or outcome like 'LEARNING RECORDED, NOT%') = 0
                 and count(*) = 25
            then 'PROBE OK' else 'PROBE FAILED' end,
       jsonb_build_object('rows', count(*), 'closed', count(*) filter (where outcome = 'CLOSED'),
                          'already_closed', count(*) filter (where outcome = 'ALREADY CLOSED'))
  from _qd_resolution;
