-- THE POSTMORTEMS THE IT DIGEST ASKED FOR ON 29 SEPTEMBER: ROOT CAUSE AND REGRESSION CHECK, BY INCIDENT ID.
-- Seat: it_engineer, 29 Sep 2026. Answers duty:postmortem:incomplete (notification 78216): 7 closed incidents with
-- no root cause or no regression check 72 hours after closing. fn_it_engineer_postmortem decides "complete" as
-- cause AND regression_check non-blank on public.it_incident, so this writes those two columns (and recorded_by),
-- by exact id, only where still blank. Each cause below was measured on production, read-only, 29 Sep 2026.
--
-- NOT WRITTEN: incident 508 (watch:refusal_rate:supplier_portal, 25 Sep). Measured: 24 of its 26 refusals in the
-- 24 h window were ONE unauthenticated POST an hour from ap-southeast-1 (HTTP 401), and the same hourly 401 still
-- arrives today (29 Sep 11:30-15:46Z). Its caller is not identified: nothing in cron.job, no routine and no
-- workflow in the repository posts to supplier_portal hourly, and the edge logs that would name the user agent
-- were not readable from this session. Without the caller the cause is a guess, so 508 stays incomplete and the
-- duty keeps it open. What is missing: the user agent / x-client-info of that hourly POST.
--
-- Applied at merge, together with the two routine fixes it names:
--   node scripts/apply_sql.mjs scripts/sql/the_postmortems_the_digest_asked_for_on_29_september.sql --apply

with pm(id, cause, regression_check) as (values
  (437::bigint,
   'ai_gateway answered harness traffic in a rehearsal window with its designed 503 fixture_no_spend (our own test traffic never reaches a paid model, #828), and observe() logged every 5xx as agent_runs status error. On 24 Sep 12:51-13:53Z all 12 of its runs were these refusals, so fn_it_detect run_failure read "failed every attempt". Nothing failed. Recurred 28 and 29 Sep (13 and 10 rows) until the fix.',
   'supabase/functions/_shared/observe.test.ts (a 5xx the handler annotated held is held); ai_gateway annotates fixture_no_spend held; scripts/checks/our_own_test_traffic_never_reaches_a_paid_model.test.mjs'),
  (484,
   'Two clocks for one rule. Handoff 80605 (it_new_bug for duty:handoff_sla:it.finding:ceo:unclosed) was created 23 Sep 12:31Z and held for the IT digest. The digest ages an item by its finding''s started_at, which restarted when the finding re-opened 24 Sep 07:00Z, so the 24 Sep digest held it as young; fn_it_duties timed it from the handoff and raised it late at 29 h. The 25 Sep digest delivered it (notification 67171). Nothing was lost.',
   'scripts/checks/a_held_digest_item_is_late_by_the_digests_clock.test.mjs; scripts/sql/a_held_digest_item_is_late_by_the_digests_clock.sql (probe verdict)'),
  (495,
   'fn_it_detect queue_not_draining raised a drain of zero whatever the age of the pending rows. doc_backups is filled by a daily batch (~23:12Z) and drained within ~20 minutes; the arm fired minutes after the batch landed (527 rows) and cleared on its own. The backup consumer was never down.',
   'scripts/checks/a_queue_filled_this_hour_is_not_a_stopped_queue.test.mjs; scripts/sql/a_queue_filled_this_hour_is_not_a_stopped_queue.sql (probe verdict)'),
  (554,
   'Same cause as incident 495: the daily doc_backups batch (258 rows, oldest 23:12Z) was raised as not draining by fn_it_detect before one drain cycle could run, and cleared by 23:31Z. Also recurred 27 Sep.',
   'scripts/checks/a_queue_filled_this_hour_is_not_a_stopped_queue.test.mjs; scripts/sql/a_queue_filled_this_hour_is_not_a_stopped_queue.sql (probe verdict)'),
  (503,
   'Twilio applies a WhatsApp sender profile update asynchronously: the POST answered 202 and the read-back in the same run still showed the old text (sender ONLINE, no alert 63115). The next marketing_duties run read the new text and the finding closed. An external propagation delay, not a defect; failing loudly on a 202 that does not read back is the intended behaviour.',
   'supabase/functions/marketing/profile_text.test.ts (whatsapp: a 202 that does not read back is a failure, not a success); duty marketing_duties profile_text re-reads the sender every run'),
  (518,
   'The trend feeds are Google News and Google Trends RSS. On 25 Sep news.google.com answered HTTP 503 to both feeds due that run and no active feed was clear of last_error, so trend_watch raised "every trend feed failed". An external outage; the next runs read the feeds and the finding closed at 14:00Z.',
   'duty marketing_duties trend_watch (only every active feed failing is a finding; each feed''s last_error is recorded on marketing_trend_source)')
)
update public.it_incident i
   set cause            = coalesce(nullif(btrim(i.cause), ''), pm.cause),
       regression_check = coalesce(nullif(btrim(i.regression_check), ''), pm.regression_check),
       recorded_by      = coalesce(i.recorded_by, 'it_engineer (scripts/sql/the_postmortems_the_digest_asked_for_on_29_september.sql)'),
       updated_at       = now()
  from pm
 where i.id = pm.id
   and (coalesce(btrim(i.cause), '') = '' or coalesce(btrim(i.regression_check), '') = '');

select case when (select count(*) from public.it_incident
                   where id in (437, 484, 495, 503, 518, 554)
                     and coalesce(btrim(cause), '') <> '' and coalesce(btrim(regression_check), '') <> '') = 6
            then 'PROBE OK :: six postmortems carry a cause and a regression check; 508 is left open on purpose'
            else 'PROBE FAILED :: a postmortem is still missing its cause or its regression check' end as verdict;
