-- Seed the watchdog with the capabilities that must not go dark during the
-- supplier-only launch window (30 Jul 2026 → ~Oct 2026, data collection phase).
-- Heartbeats measure EFFECT, not logs. Thresholds are ~3x the schedule interval so a
-- single missed run is tolerated and a genuine outage is not.

insert into edge_expectation (fn_key, cron_jobname, purpose, heartbeat_sql, max_silence_minutes, blast_radius, dept_key, severity)
values
-- knowledge: the whole point of the 2-3 month data collection phase
('kb_embed','kb_embed_backfill','Embed knowledge-base chunks so they are reachable by semantic search.',
 $q$select case when (select count(*) from kb_chunks where embedding_gte is null) = 0 then now()
                else (select max(started_at) from agent_runs where agent='kb_embed' and status in ('ok','success','completed')) end$q$,
 180,'New category knowledge is written but invisible to RAG. Every agent answering a supplier or category question silently falls back to whatever was indexed before the stall.','knowledge','high'),

('gen_category_knowledge','gen_category_knowledge_daily','Generate per-category procurement knowledge for the 86 supplier categories.',
 $q$select max(started_at) from agent_runs where agent='gen_category_knowledge' and status in ('ok','success','completed')$q$,
 1800,'Category coverage stops deepening. The supply-gap work that the whole launch window exists to complete quietly stalls.','knowledge','high'),

('gen_category_personas','gen_category_personas_daily','Generate buyer/supplier personas per category.',
 $q$select max(started_at) from agent_runs where agent='gen_category_personas' and status in ('ok','success','completed')$q$,
 1800,'Matching and outreach lose the persona context they use to qualify suppliers.','knowledge','medium'),

('kb_autofill_gaps','kb_autofill_gaps_weekly','Detect and fill holes in the knowledge base.',
 $q$select max(started_at) from agent_runs where agent='kb_autofill_gaps' and status in ('ok','success','completed')$q$,
 1800,'Known knowledge gaps stop being closed; the KB stops self-repairing.','knowledge','medium'),

('knowledge_exam','knowledge_exam_loop','Examine agents against their required knowledge modules.',
 $q$select max(started_at) from agent_runs where agent='knowledge_exam' and status in ('ok','success','completed')$q$,
 600,'Agents keep operating with unverified knowledge; competence drift goes undetected.','knowledge','medium'),

-- reliability: the signals that would tell us anything else is broken
('ai_health','ai_health_15min','Check LLM provider health and the model fallback ladder.',
 $q$select max(started_at) from agent_runs where agent='ai_health' and status in ('ok','success','completed')$q$,
 60,'A dead or degraded model provider is not noticed. Every AI-dependent workflow degrades with no alarm.','technology','high'),

('uptime_check','uptime_check_15min','HTTP availability probe of the public site and portals.',
 $q$select max(started_at) from agent_runs where agent='uptime' and status in ('ok','success','completed')$q$,
 60,'The platform can be down and nobody is told. This is the only true availability signal.','technology','high'),

('fn_smoke','smoke_test_30min','End-to-end smoke test of the core flows.',
 $q$select max(started_at) from agent_runs where agent='smoke' and status in ('ok','success','completed')$q$,
 120,'Breaking regressions reach production undetected.','technology','high'),

('fn_resilience_watch','resilience_watch_10min','Watch continuity and failover posture.',
 $q$select max(started_at) from agent_runs where agent='resilience_watch' and status in ('ok','success','completed')$q$,
 45,'Continuity degradation is invisible; the 13 continuity plans lose their only live check.','technology','high'),

('fn_security_scan','agent_security_hourly','Hourly security scan.',
 $q$select max(started_at) from agent_runs where agent='security' and status in ('ok','success','completed')$q$,
 180,'Security regressions and exposed surfaces go unreported for as long as the scan is dark.','technology','high'),

('it_health','agent_it_health_hourly','Infrastructure and integration health.',
 $q$select max(started_at) from agent_runs where agent='it_health' and status in ('ok','success','completed')$q$,
 180,'Broken integrations (payments, mail, storage) are not surfaced.','technology','medium'),

('fn_ops_watch','ops_watch_hourly','Operational exception watch.',
 $q$select max(started_at) from agent_runs where agent='ops_watch' and status in ('ok','success','completed')$q$,
 180,'Stuck RFQs, SLA breaches and operational exceptions stop being raised.','operations','high'),

('qa_suite','qa_suite_daily','Daily QA suite.',
 $q$select max(started_at) from agent_runs where agent='qa_suite' and status in ('ok','success','completed')$q$,
 1800,'Regression coverage stops. Defects ship unnoticed during the launch window.','technology','high'),

('money_tests','money_tests_daily','Daily correctness tests over money paths.',
 $q$select max(started_at) from agent_runs where agent='money_tests' and status in ('ok','success','completed')$q$,
 1800,'Billing, fee and refund arithmetic stops being verified. Financial defects reach suppliers.','finance','high'),

('backup','backup_daily','Daily database backup.',
 $q$select max(started_at) from agent_runs where agent='backup' and status in ('ok','success','completed')$q$,
 1800,'No recoverable copy of the company. This is the single highest-consequence silent failure on the list.','technology','high'),

-- commercial / marketplace during supplier onboarding
('onboarding','agent_onboarding_hourly','Drive supplier onboarding steps.',
 $q$select max(started_at) from agent_runs where agent='onboarding' and status in ('ok','success','completed')$q$,
 180,'Suppliers who sign up stall mid-onboarding with nobody chasing them. Directly harms the one metric the launch window exists to move.','marketplace','high'),

('email_triage','email_triage_hourly','Triage inbound email into the right workflow.',
 $q$select max(started_at) from agent_runs where agent='email_triage' and status in ('ok','success','completed')$q$,
 180,'Inbound supplier replies are never routed. From the supplier side the company looks unresponsive.','operations','high'),

('enrich_capability','capability_backfill_daily','Backfill supplier capability data.',
 $q$select max(started_at) from agent_runs where agent='enrich_capability' and status in ('ok','success','completed')$q$,
 1800,'Supplier records stay thin, so matching quality degrades as the roster grows.','marketplace','medium'),

('archive_rfq','archive_completed_daily','Archive completed RFQs.',
 $q$select max(started_at) from agent_runs where agent='archive_rfq' and status in ('ok','success','completed')$q$,
 1800,'Live tables grow unbounded; dashboards and queries slow down.','operations','low'),

('assets_ingest','assets_ingest_6h','Ingest uploaded assets.',
 $q$select max(started_at) from agent_runs where agent='assets_ingest' and status in ('ok','success','completed')$q$,
 900,'Supplier-uploaded documents are never processed, so licence and trade-document checks cannot complete.','operations','medium'),

('dropbox_sync','dropbox_sync_daily','Sync the document store.',
 $q$select max(started_at) from agent_runs where agent='dropbox_sync' and status in ('ok','success','completed')$q$,
 1800,'Document store drifts from the database; the off-platform backup copy goes stale.','operations','medium'),

-- leadership cadence added this session; if these go dark the company stops governing itself
('fn_day_conductor','day_conductor_daily','Run the daily operating cadence.',
 $q$select max(started_at) from agent_runs where agent='day_conductor' and status in ('ok','success','completed')$q$,
 1800,'The company stops setting its own daily priorities. Every downstream department cadence loses its trigger.','leadership','high'),

('fn_company_snapshot','company_snapshot_daily','Take the daily company state snapshot.',
 $q$select max(started_at) from agent_runs where agent='company_snapshot' and status in ('ok','success','completed')$q$,
 1800,'The time machine stops recording. Any later question about what changed and when becomes unanswerable.','intelligence','medium'),

('fn_outcome_evaluate','outcome_evaluate_daily','Evaluate open outcome records and promote or roll back decisions.',
 $q$select max(started_at) from agent_runs where agent='outcome_evaluate' and status in ('ok','success','completed')$q$,
 1800,'The improvement loop opens but never closes: decisions are never measured, bad changes are never rolled back, no lessons reach memory.','evolution','high'),

('fn_supply_gap_scan','supply_gap_scan_daily','Measure supplier coverage against the 10-per-category target.',
 $q$select max(started_at) from agent_runs where agent='supply_gap_scan' and status in ('ok','success','completed')$q$,
 1800,'The company loses sight of the single number the launch window is being spent on.','marketplace','high'),

('fn_founder_brief','founder_brief_daily','Produce the daily founder brief.',
 $q$select max(started_at) from agent_runs where agent='brief' and status in ('ok','success','completed')$q$,
 1800,'The founder stops receiving the daily brief and has no visibility while working supplier acquisition off-platform.','leadership','high')

on conflict (fn_key) do update set
  cron_jobname = excluded.cron_jobname,
  purpose = excluded.purpose,
  heartbeat_sql = excluded.heartbeat_sql,
  max_silence_minutes = excluded.max_silence_minutes,
  blast_radius = excluded.blast_radius,
  dept_key = excluded.dept_key,
  severity = excluded.severity,
  active = true;