-- PCCR-009 — re-enable the audit-confirmed dormant DETERMINISTIC capabilities as traced components.
--
-- The 2 Sep connectivity audit (37 agents) confirmed 4 live gaps whose fix re-drifts the frozen
-- phase_c_component registry. Three are dormant deterministic crons the stand-down held; the audit
-- proved each is NOT inference-bound (verified again here by aborted-tx probe, all clean):
--   ASSUR-01 (high)  cron 123 resilience_watch_10min -> fn_resilience_watch: platform-continuity
--                    self-heal (email-outbox flush, missing-critical-credential + Stripe key checks,
--                    lost-receipt + stuck-match detection). It only READS the AI heartbeat and CHECKS
--                    the openrouter key's presence; it makes no inference call. It was collaterally
--                    swept into the OpenRouter hold on a misdiagnosis. No other active monitor covers
--                    outbox/receipt/resilience.
--   LEGAL-01 (high)  cron 76  legal_ai_daily -> fn_legal_ai (deterministic SQL): refreshes the legal
--                    checklist, writes the daily legal_health KPI snapshot, and raises founder-visible
--                    legal_flag escalations for missing core docs / regulatory changes. Dead since
--                    16 Aug; legal_kpi_snapshots stale. Its siblings run via the kernel dispatcher.
--   PO-1     (med)   cron 290 employee_kpi_assign_daily -> fn_employee_kpi_assign: the producer that
--                    assigns KPIs to active agents that have none (closes objective #43).
--
-- Each is wrapped as a traced kernel component (fn_kernel_cron_exec) exactly like PCCR-008's crons.
-- All critical credentials are present (stripe/resend/hmac/openrouter), so resilience_watch will not
-- spuriously alert the founder on first run.
--
-- This re-drifts component_crosswalk; the freeze amendment is recorded in
-- scripts/sql/pccr009_component_registry_amendment.sql and is UNAPPROVED until the founder ratifies
-- PCCR-009 in the Command Center (same as PCCR-008). Deterministic; OpenRouter untouched.
--
--   node scripts/apply_sql.mjs scripts/sql/pccr009_reenable_the_audit_confirmed_deterministic_monitors.sql --apply --ddl

begin;

select public.fn_kernel_wrap_and_enable_cron(123, 'it_operations_engineer', 'assurance');
select public.fn_kernel_wrap_and_enable_cron(76,  'general_counsel',        'legal');
select public.fn_kernel_wrap_and_enable_cron(290, 'chief_operating_officer','people_ops');

-- Re-activate resilience_watch's executor (deactivated on the misdiagnosis) and its health expectation
-- (my dormant-function sweep had deactivated it; it now runs, so it is monitored again).
update public.org_action_executor
   set active = true,
       note = 'Re-activated 2 Sep 2026 (PCCR-009, audit ASSUR-01). Deterministic: reads the AI heartbeat age and checks the openrouter key presence, makes no inference call. Flushes the email outbox, checks critical credentials, detects lost receipts / stuck matches, and alerts the founder only when it cannot auto-heal a platform-continuity failure.'
 where action_class = 'resilience_watch';

update public.edge_expectation set active = true,
       purpose = coalesce(purpose,'') || ' [2 Sep 2026: RE-ACTIVATED (PCCR-009) — resilience_watch runs again as a traced kernel component.]'
 where fn_key = 'fn_resilience_watch';

commit;
