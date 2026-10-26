-- Stop edge_health_scan flagging INTENTIONALLY-DORMANT functions as silent failures.
--
-- Re-enabling the failure-detection tier (PCCR-008) turned edge_health_scan back on. It watches
-- edge_expectation rows and opens an os_incident (+ a security.event analysis org_task) for every
-- function that has "produced no effect" past its threshold. But 19 of the 28 active expectations
-- point at functions whose cron is INACTIVE — held by the 16 Aug stand-down and not yet re-enabled
-- (re-enabling each drifts the frozen phase_c_component registry and needs the founder's PCCR
-- governance signature). An intentionally-off function is not a silent failure; expecting a heartbeat
-- from it is a false positive, and the burst of unowned assurance analysis/incident tasks it produced
-- broke org_connectivity_signal_path ("the sweep gives every unowned task a real owner").
--
-- FIX: deactivate the expectation for every function whose heartbeat is stale AND whose cron is
-- inactive (we do not monitor an off function), and resolve the open silent-failure incidents those
-- expectations produced. Re-enabling the deterministic ones is tracked as ONE founder-signature item.
-- This mirrors scripts/sql/triage_standdown_silent_failure_incidents.sql, applied systematically.
--
--   node scripts/apply_sql.mjs scripts/sql/stop_the_dormant_function_silent_failure_whackamole.sql --apply --ddl

begin;

-- 1. Deactivate the expectation for a function that is stale AND has no active cron. dropbox_backup is
--    excluded: its heartbeat was re-pointed to the live agent dropbox_sync (earlier triage), so it is
--    ALIVE and stays monitored. A function that revives (cron re-enabled) gets its expectation
--    re-activated at that time.
update public.edge_expectation e
   set active = false,
       purpose = coalesce(purpose,'') || ' [2 Sep 2026: DEACTIVATED — its cron is inactive (held by the 16 Aug stand-down / OpenRouter), so no heartbeat is expected. edge_health_scan was raising false silent-failure incidents for it. Re-activate when the cron is re-enabled (a founder-signed PCCR amendment, since re-enabling a cron drifts the frozen phase_c_component registry).]'
 where e.active
   and e.fn_key <> 'dropbox_backup'
   and not coalesce((select bool_or(j.active) from cron.job j
                      where j.jobname = e.cron_jobname or j.command ilike '%'||e.fn_key||'%'), false);

-- 2. Resolve the open silent-failure incidents for functions whose expectation is now inactive (so
--    edge_health_scan will not re-open them, and t30_os_incident_close_task closes their org_tasks).
update public.os_incidents i
   set status = 'resolved', resolved_by = 'security', resolved_at = now(),
       resolution = 'Dormant function (' || (i.detail->>'fn_key') || '): its cron is intentionally inactive (16 Aug stand-down / OpenRouter hold), so "produced no effect" is expected, not a defect. Its edge_expectation is deactivated; re-monitored when the cron is re-enabled via a founder-signed PCCR amendment.'
 where i.status = 'open' and i.kind = 'silent_failure'
   and exists (select 1 from public.edge_expectation e
                where e.fn_key = i.detail->>'fn_key' and not e.active);

-- 3. Close the orphaned security.event analysis tasks that reference a now-resolved incident.
update public.org_tasks t
   set status = 'done', updated_at = now()
 where t.status in ('assigned','in_progress') and t.assigned_agent is null
   and t.dept_key = 'assurance' and t.action_class = 'analysis'
   and t.title ~ '^security\.event on incident '
   and not exists (select 1 from public.os_incidents i
                    where i.id = (regexp_replace(t.title,'\D','','g'))::bigint and i.status = 'open');

-- 4. Track the re-enablement of the deterministic dormant crons as ONE founder-signature item.
insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
select 'exec', 'Re-enable the deterministic dormant crons the stand-down held (founder PCCR signature)',
       'edge_health_scan surfaced ~19 functions whose crons are inactive since the 16 Aug stand-down. '
       || 'The inference-bound ones (day_conductor, gen_category_personas, knowledge_exam, outcome_evaluate) '
       || 'wait on OpenRouter. The deterministic ones (it_health, onboarding, money_tests, qa_suite, '
       || 'supply_gap_scan, resilience_watch, kb_embed, archive_rfq, assets_ingest, email_triage, '
       || 'enrich_capability, company_snapshot, kb_autofill_gaps, supplier_invites) should be re-enabled '
       || 'as traced kernel components — but each re-enable drifts the frozen phase_c_component registry, '
       || 'so it needs a founder-signed PCCR amendment (like PCCR-008). Consolidate into one PCCR-009. '
       || 'Re-activate each function''s edge_expectation when its cron is re-enabled.',
       'proposed', 'gated', false, 'incident_fix'
 where not exists (select 1 from public.org_tasks
                    where title = 'Re-enable the deterministic dormant crons the stand-down held (founder PCCR signature)'
                      and status <> 'done');

commit;
