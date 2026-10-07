-- THE 29 IT HANDOFFS PARKED AT THE LEARNING GATE, 23 SEP - 5 OCT 2026, CLOSE BY EXACT ID WITH WHAT WAS LEARNED.
--
-- Seat: it_engineer. 7 Oct 2026. Data only: no routine, no table. Wiring audit (PR #1278), item 1.
--
-- MEASURED, read-only, 7 Oct 2026 01:40Z: 29 it.finding handoffs pending with awaiting_learning. Every one's
-- finding has cleared; every one's it_incident lacks a cause, a fix or a regression check (99514 lacked only the
-- fix), so trigger z62 keeps them open and fn_it_loop_reverify parks them. Most parked because their failure
-- class had no playbook entry until #1242 (6 Oct), and a class with no typical_cause cannot fill an incident.
--
-- Each row below was investigated on 7 Oct from the finding's evidence, it_incident, agent_runs, routine_change_log,
-- it_integration_external_cause, it_restore_drill_result, GitHub Actions run logs (gh run view) and git history.
-- Where a cause could not be established it says "NOT established" and which evidence is missing -- the edge logs
-- that would name a caller keep about a day and had expired. Every regression check named is a file present on
-- origin/main on 7 Oct, or the live duty / detector that re-raises the key.
--
-- HOW: the 22 Sep pattern (every_parked_it_handoff_of_22_september_is_closed_by_its_exact_id.sql). For each id it
-- re-checks, at apply time, that the handoff is still pending, is an it.finding, carries EXACTLY the listed issue
-- key, that its occurrence cleared, and that its incident exists. Only then fn_it_attach_learning (the gate's own
-- door; z62 is not bypassed) records the learning and closes it as it_engineer, and the handoff's 'it_loop:<id>'
-- CEO report is completed by exact key. A row failing any check is skipped and says why. Re-applying is safe.
-- A field the incident already carries is kept (99514's cause and regression check of 29 Sep).
--
-- OPEN GAPS FOUND ON THE WAY (not closed by this file; named so they are not lost):
--   claim_lookup's hourly launch_path probe still answers 400 without a probe credential (100487); a debounced
--   GitHub backup kick writes no agent_runs row, so dropbox_kick's heartbeat can miss (130872); run_silent keeps a
--   subject's old rhythm for 7 days after an intended cadence change, and qualifies bursty demand-driven functions
--   (the eight wa_templates_watch rows, 124134, 126399, 100470).
--
--   node scripts/apply_sql.mjs scripts/sql/the_29_parked_it_handoffs_of_23_september_to_5_october_close_with_what_was_learned.sql --apply --ddl

create temp table if not exists _qd_resolution (subject text, outcome text, evidence jsonb) on commit drop;

do $res$
declare
  v record; h public.agent_actions; f public.it_engineer_finding; i public.it_incident;
  v_cleared boolean; v_reopened boolean; r jsonb; n_rep int;
  c_by constant text := 'it_engineer (the_29_parked_it_handoffs_of_23_september_to_5_october_close_with_what_was_learned.sql, 7 Oct 2026)';
  c_wa constant text := 'Detector false positive after an intended cadence change. resilience_ping''s orphan step runs wa_templates_watch only when fn_resilience_orphan_steps_due() says a template is undecided or unchecked for 20 h. Until 29 Sep 09:16Z it ran every ~30 min (27 and 28 Sep: 70 and 81 runs, max gap 31 min) because the watcher was refused and read only wa_template_sids, so its gate never closed; #1049 (cfe28d9, merged 29 Sep 09:10Z) made it poll what its gate reads, and from 30 Sep it ran 3 times a day with gaps of 1,170-1,200 min, as designed. run_silent still held the old 7-day rhythm (p50 29.65 min) and raised silence about 2 h after each daily run. It stopped on 5 Oct 21:01Z when enough 30-minute gaps had aged out of the 7-day window that the subject no longer qualified. The watcher never stopped.';
  c_wa_fix constant text := 'No change for the silence: the cadence change was intended (#1049, cfe28d9, with the 28 Sep scoped-credential fix to resilience_ping). The detector''s old-rhythm false positive is an open gap.';
  c_wa_rc constant text := 'scripts/checks/the_template_watcher_polls_what_its_gate_reads.test.mjs; scripts/checks/resilience_orphan_jobs_present_a_scoped_credential.test.mjs; fn_it_detect run_silent re-raises the key';
  c_un constant text := 'Detector false positive on a demand-driven public surface. unsubscribe runs only when someone opens an unsubscribe link; since 27 Sep its traffic was almost entirely GET requests answered 400 "Invalid link" from us-east-1 every 15-45 min (29 Sep: 78 warn, 2 ok), which gave it a 17.75-min rhythm, and when that traffic paused run_silent raised silence. The function answered every request it received. Who sends the invalid-link requests is NOT established: agent_runs records no caller or user agent and the edge logs had expired.';
begin
  for v in select * from (values
    (78384::bigint, 'duty:unsigned_change:tx12736419',
     'Applied before merge. fn_seat_deliberation_norm(text) was created at 23 Sep 11:02Z through the management API as postgres from the branch of #877, whose merge (fe193b6) landed at 11:09Z, 7 minutes later. That breaks "apply at merge, never before"; routine_change_log recorded the change with no reviewed revision.',
     '#877 (fe193b6) merged and the routine was re-applied from the reviewed revision (finding closed 24 Sep 02:30Z). scripts/lib/release_guard.mjs now refuses --apply for a file whose pull request is not merged or green.',
     'duty it_engineer.unsigned_change (fn_it_change_watch over routine_change_log); scripts/checks/it_engineer_duties_19_to_24.test.mjs',
     'unsigned_routine_change'),
    (78385, 'duty:unsigned_change:tx12737074',
     'Applied before merge, a second time: fn_seat_deliberation_norm(text) re-created at 23 Sep 11:04Z through the management API as postgres, 5 minutes before #877 (fe193b6) merged at 11:09Z.',
     '#877 (fe193b6) merged and the routine was re-applied from the reviewed revision (finding closed 24 Sep 02:30Z). release_guard.mjs now refuses a pre-merge apply.',
     'duty it_engineer.unsigned_change (fn_it_change_watch over routine_change_log); scripts/checks/it_engineer_duties_19_to_24.test.mjs',
     'unsigned_routine_change'),
    (79728, 'duty:unsigned_change:tx12784513',
     'Applied before merge. fn_marketing_step_request(text,text) was created at 23 Sep 11:44Z through the management API as postgres; its only commit is 69306a3 (#876), merged at 12:03Z, 19 minutes later.',
     '#876 (69306a3) merged and the routine was re-applied from the reviewed revision (finding closed 24 Sep 02:30Z). release_guard.mjs now refuses a pre-merge apply.',
     'duty it_engineer.unsigned_change (fn_it_change_watch over routine_change_log); scripts/checks/it_engineer_duties_19_to_24.test.mjs',
     'unsigned_routine_change'),
    (99514, 'duty:delivery:request:80605',
     null,
     '#1135 (01121e5, merged 29 Sep, applied in 3c306e2): fn_it_duties holds a digest item until the later of the handoff''s created_at and its open finding''s started_at.',
     null, 'delivery_request_unconfirmed'),
    (100813, 'duty:delivery:request:100464',
     'Request 100464 (25 Sep 06:46Z, ceo to customer_support) carried an it_new_bug for the founder: "resilience_ping step orphans.wa_templates_watch failed: HTTP 403". customer_support answered it as routed, not delivered (emailed false, no notification row, sent_at null), and no outcome came back until delivery.result 100914 on 27 Sep 15:16Z, so the delivery duty raised it at 35 h; it cleared at 15:45Z. Same family as 80605 (a founder item held or routed rather than sent). Partly established: why this item was routed rather than put in a digest is NOT established; the routing record of fn_notify_founder / founder_mail_policy for 25 Sep 06:46Z was not found.',
     'No change for this occurrence: it cleared when customer_support recorded the routed result (100914). The digest-clock half of the family is fixed by #1135 (01121e5).',
     'the IT delivery duty (it_engineer.delivery); scripts/checks/a_held_digest_item_is_late_by_the_digests_clock.test.mjs',
     'delivery_request_unconfirmed'),
    (100653, 'seat_duty:sales_engineer.supplier_performance',
     'supplier_performance.lead_id references leads(id) but supplier_score has no such key, and fn_sales_engineer_supplier_performance read supplier_score without joining leads. Score rows naming deleted leads (12 measured on 7 Oct, for example lead_id 5, 13, 15, 19) made one insert violate supplier_performance_lead_id_fkey and abort the whole run: 4 failures, last success 24 Sep 00:01Z.',
     'Release batch #973 (a6ffd5b, 28 Sep) applied scripts/sql/a_supplier_is_scored_only_while_its_lead_exists.sql, which scores only rows whose lead exists; the duty ran clean on its next clock (finding closed 28 Sep 12:04Z).',
     'scripts/checks/supplier_performance_reads_only_live_leads.test.mjs; fn_seat_duties_tick re-raises the duty if it fails again',
     'seat_duty_failing'),
    (100467, 'duty:db_health:growth:os_audit_log',
     'os_audit_log grew from 62.9 MB to 168.1 MB in 7 days. Almost all of the growth is rows mirrored from agent_runs with actor fn:ai_gateway: about 6.2k a day on 18-20 Sep, then 13.2k on 21 Sep, 39.2k on 22 Sep, 27.5k on 23 Sep, 4.9k on 24 Sep and 14 on 25 Sep. Nothing was purged; the finding cleared on 29 Sep when the burst left the 7-day comparison. What drove the 22-23 Sep ai_gateway burst is NOT established (agent_runs carries no caller; the edge logs had expired).',
     'No change: the burst stopped and left the 7-day window. No retention change was made.',
     'the db_health duty (growth) re-raises the key; scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
     'table_growth'),
    (100470, 'watch:run_silent:ai_gateway',
     'Detector false positive on a demand-driven function. fn:ai_gateway runs only when a seat calls it, in bursts: 39,211 rows on 22 Sep, 27,500 on 23 Sep, 4,905 on 24 Sep, 14 on 25 Sep (last 07:57:30Z), then none until 28 Sep 12:00Z. run_silent qualified it on that burst rhythm (p50 = p90 = 0.01 min) and raised silence at 08:31Z. Why its callers stopped on 25 Sep is NOT established: agent_runs has no caller field, llm_calls holds no rows for those days (the OpenRouter hold did not change in that window) and the edge logs had expired.',
     'No change: it cleared when calls resumed on 28 Sep 12:00Z.',
     'fn_it_detect run_silent re-raises the key',
     'run_silent'),
    (100487, 'watch:refusal_rate:claim_lookup',
     'Our own monitoring traffic, the same origin as incident 508. All 24 refusals from 24 Sep 14:31Z to 25 Sep 14:00Z were hourly POSTs answered 400 invalid_link to the launch_path probe api:claim_lookup (supabase/functions/_shared/launch_path.ts), which is refused on purpose. Unlike supplier_portal''s probe it presents no x-qd-probe credential, so its refusals still count as real traffic. It cleared on 28 Sep 12:31Z only because harness traffic answering 200 diluted the share below half.',
     'No change for claim_lookup: #1139 marked supplier_portal''s probe as fixture traffic but not claim_lookup''s. Open gap: the probe still runs hourly (7 Oct 01:16Z, 400) and will re-raise when real traffic is low.',
     'fn_it_detect refusal_rate re-raises the key',
     'refusal_rate'),
    (100488, 'watch:refusal_rate:supplier_portal',
     'Our own monitoring traffic (incident 508, proven from the edge logs on 29 Sep): resilience_ping''s launch-path probe sent an unauthenticated POST {"action":"dashboard"} to supplier_portal every hour; 20 of the 20 logged calls in the 24 h were those refusals.',
     '#1139 (86b9ee7): the probe presents cred_fn_resilience_ping in x-qd-probe and supplier_portal marks those calls as fixture traffic, which refusal_rate excludes.',
     'fn_it_detect refusal_rate (excludes counts.fixture) re-raises the key',
     'refusal_rate'),
    (96965, 'duty:integration:twilio_whatsapp_sender',
     'Twilio lost the link between our WhatsApp sender +12183166814 and its WhatsApp Business account on Twilio''s side: Twilio ticket 29665983, opened 22 Sep (it_integration_external_cause id 1); Twilio wrote on 24 Sep 09:52Z that its engineering was actively reviewing. Not our probe (a 3 s retry still read OFFLINE) and not a profile update (no sender update in agent_runs that morning).',
     'No change on our side: Twilio restored the link; the finding and the external-cause row closed in the same second, 24 Sep 17:45:45Z.',
     'the integration duty (twilio_wa_sender probe in supabase/functions/_shared/integration_registry.json) with the it_integration_external_cause register',
     'integration_down'),
    (98498, 'duty:marketing_duties:geo_audit',
     'The GEO audit scraped DuckDuckGo from the edge function''s datacenter address; DuckDuckGo answered both GET and POST with HTTP 202 bot-check pages, so no results came back. Seen 202 times, 24 Sep 16:30Z to 29 Sep 09:15Z.',
     '#1039 (8d4cf3d, merged 29 Sep 09:42Z) replaced the scrape with answer engines through ai_gateway; the finding closed at 10:16Z. #1226 (dce20d0) later moved seat search to Serper.',
     'scripts/checks/marketing_duties_are_on_a_clock.test.mjs; the marketing_duties duty re-raises the key',
     'marketing_duty_failing'),
    (110256, 'duty:backup_objectives:drill_stale',
     'A new rule judging an old drill, not a broken scheduler. The restore drill was monthly (it_duty_schedule.restore_table 30 days) and drill 70 on 15 Sep satisfied September. #998 made it weekly and added the backup_objectives duty; applied 29 Sep 03:46Z (c4e41e0), its first run at 04:00:40Z judged the 15 Sep drill against the new limit. The weekly drill then ran at 04:02:12Z (drill 841, ok).',
     '#998 (621b865, applied by c4e41e0); the finding closed at the next daily pass, 30 Sep 04:15Z.',
     'scripts/checks/the_backups_are_held_to_a_stated_rpo_and_rto.test.mjs; the backup_objectives duty re-raises the key',
     'backup_objective_unproven'),
    (110257, 'duty:backup_objectives:rto_unproven',
     'The same trigger as 110256 (#998 applied 29 Sep 03:46Z). No drill had ever restored rows: drill 3 (14 Sep) failed with 0 restored and drill 70 (15 Sep) restored 0. Drill 841 (29 Sep 04:02Z) rebuilt 100 kb_chunks rows with 0 lost, which proved the RTO.',
     '#998 (621b865); the monthly retry-until-pass rule in fn_it_restore_table_due came in #1038 (a0f8d8d). Closed 30 Sep 04:15Z.',
     'scripts/checks/the_backups_are_held_to_a_stated_rpo_and_rto.test.mjs; the backup_objectives duty re-raises the key',
     'backup_objective_unproven'),
    (120562, 'duty:workflow_heartbeat:kb_embed',
     'GitHub Actions run 36544186787 (29 Sep 08:40Z) of .github/workflows/kb-embed-backfill.yml failed on its first Management API query with 429 ThrottlerException, so no duty:kb_embed reading was written; the last reading was 28 Sep 08:47Z and the 36 h window ran out on 29 Sep 21:15Z.',
     '#1141 (b34ddf3, 30 Sep): the backfill retries a 429 up to 6 times with backoff. Run 36691216890 (30 Sep 08:40Z) carried it and succeeded; the finding closed at 08:45Z.',
     'scripts/kb/run_embed_backfill.mjs (the retry loop); the workflow_heartbeat duty (kb_embed, 36 h) re-raises the key',
     'workflow_heartbeat_missing'),
    (130872, 'duty:workflow_heartbeat:dropbox_kick',
     'Two causes together. GitHub ran the 41 */6 schedule late (runs at 4 Oct 12:49Z and 21:54Z and 5 Oct 06:11Z, on GitHub-hosted runners, before the 6 Oct Ubicloud move); and the 21:54Z run printed kicked false, "debounced: a kick in the last 60 seconds is still draining". fn_backup_kick returns on a debounce without writing agent_runs, and the heartbeat counts only agent_runs rows with agent backup_kick and reason github_actions, so the last counted reading stayed at 12:50Z.',
     'No change: the 06:11Z run kicked for real and the finding closed at 06:16Z. Open gap: a debounced GitHub kick still counts as no heartbeat.',
     'the workflow_heartbeat duty (dropbox_kick, 12 h) re-raises the key',
     'workflow_heartbeat_missing'),
    (127563, 'duty:db_health:growth:knowledge_vector_ml',
     'Real, intended volume: the multilingual embedding backfill (.github/workflows/ml-embed-backfill.yml; the multilingual path came in #907, 76cd1cb) wrote about 8,500 rows a day (42,519 of 148,326 kb_chunks by 4 Oct), and the table went from 25.4 MB to 172.1 MB in 7 days. The close note''s reference to #1115 is wrong: #1115 is "services are named by exact name or by meaning".',
     'No defect to fix: the table is registered in it_expected_table_growth until 31 Oct (close note, 5 Oct 00:58Z).',
     'the db_health duty (growth) re-raises the key after 31 Oct; scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
     'table_growth'),
    (132371, 'knowledge_recall:no_ml_vectors',
     '#1203 (83ffcee, merged 5 Oct 09:05Z) made the knowledge exam score through fn_reason_retrieve_ml, which needs embedding_ml on every exam question and raises knowledge_recall:no_ml_vectors until then; 25 minutes later 744 questions had none.',
     'The vectors were loaded with scripts/kb/load_knowledge_eval_questions.mjs (no workflow runs it, so it was a manual run; who ran it is not established); the finding closed 5 Oct 17:15Z. #1216 (fb9d52b) followed up the exam.',
     'scripts/checks/the_knowledge_exam_scores_the_bilingual_path.test.mjs; the knowledge_recall exam re-raises the key',
     'knowledge_recall_gap'),
    (124134, 'watch:run_silent:unsubscribe', 'un',
     'No change: the requests paused and resumed; nothing in unsubscribe stopped.', 'fn_it_detect run_silent re-raises the key', 'run_silent'),
    (126399, 'watch:run_silent:unsubscribe', 'un',
     'No change: the requests paused and resumed; nothing in unsubscribe stopped.', 'fn_it_detect run_silent re-raises the key', 'run_silent'),
    (124444, 'watch:refusal_rate:unsubscribe',
     'In the 24 h before 30 Sep 10:46Z the refusals were tokenless or bad-token GETs answered 400 "Invalid link" from us-east-1, against 2 OK calls (29 Sep: 78 warn, 2 ok). No caller in the repository (resilience_ping, launch_path, workflows) requests unsubscribe without a token. Whether they are mail-scanner prefetches or an outside probe is NOT established: no user agent is recorded and the edge logs had expired. It cleared at 18:00Z when that traffic dropped.',
     'No change: the traffic stopped; a 400 for a bad link is the correct answer.',
     'fn_it_detect refusal_rate re-raises the key',
     'refusal_rate'),
    (113776, 'watch:run_silent:wa_templates_watch', 'wa', null, null, 'run_silent'),
    (124155, 'watch:run_silent:wa_templates_watch', 'wa', null, null, 'run_silent'),
    (126665, 'watch:run_silent:wa_templates_watch', 'wa', null, null, 'run_silent'),
    (126895, 'watch:run_silent:wa_templates_watch', 'wa', null, null, 'run_silent'),
    (127260, 'watch:run_silent:wa_templates_watch', 'wa', null, null, 'run_silent'),
    (127620, 'watch:run_silent:wa_templates_watch', 'wa', null, null, 'run_silent'),
    (127909, 'watch:run_silent:wa_templates_watch', 'wa', null, null, 'run_silent'),
    (132372, 'watch:run_silent:wa_templates_watch', 'wa', null, null, 'run_silent')
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
        insert into _qd_resolution values ('handoff ' || v.id, 'SKIPPED: no incident; fn_it_loop_reverify closes it on its next tick', null); continue;
      end if;

      r := public.fn_it_attach_learning(v.id,
        coalesce(nullif(btrim(i.cause), ''), case v.cause when 'wa' then c_wa when 'un' then c_un else v.cause end),
        coalesce(nullif(btrim(i.fix), ''), case when v.cause = 'wa' then c_wa_fix else v.fix end),
        coalesce(nullif(btrim(i.regression_check), ''), case when v.cause = 'wa' then c_wa_rc else v.regression_check end),
        v.playbook_class, null, c_by);

      -- The CEO report completes only when the handoff really closed (review of #1281).
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
                 and count(*) = 29
            then 'PROBE OK' else 'PROBE FAILED' end,
       jsonb_build_object('rows', count(*), 'closed', count(*) filter (where outcome = 'CLOSED'),
                          'already_closed', count(*) filter (where outcome = 'ALREADY CLOSED'))
  from _qd_resolution;
