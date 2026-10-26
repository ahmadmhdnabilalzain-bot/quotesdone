-- THE MEASUREMENT CRONS GO BACK ON THE CLOCK (3 Sep 2026).
--
-- The 16 Aug stand-down switched off 183 jobs. The self-management crons came back on 2-3 Sep; the
-- executive meeting and the nightly reflection this morning. The Row #3 scorer (112/152) then names
-- the rest of the silence plainly: maturity, marketplace health, energy, the time machine and the
-- company brain were all "measured 2026-08-16" — the stand-down date — because the jobs that measure
-- them are off. Eighteen of them are put back here.
--
-- MEASURED BEFORE WRITING, job by job (the function each runs was read for what it WRITES):
--   pure SQL — no net.http_post, no edge target, no model;
--   writes only its own measurement (snapshots, indices, readiness scores, findings as advisory
--   agent_actions/org_tasks, proposals never implementations) or a derived column;
--   never notifications, never money, never approval/ban/contact on a supplier or customer, never
--   founder_alerts. Three candidates were left OFF on purpose: outcome_evaluate_daily and reputation_weekly are held by the
--   open reputation stand-down (fn_reputation_hold_state), and reputation_weekly writes
--   employee_authority (an authority change with no human is exactly what the promotion constraint
--   guards) and capability_verify_daily writes founder_alerts (pages him).
--   Every accountable role below resolves in org_role (verified), and each wrap passes the
--   crosswalk's own authority_class so the committed crosswalk does not move.
--
-- Also: cron_registry rows for the seven active jobs the manual did not document (scorer item
-- s38-manual-always-current).

begin;
do $$
begin
  -- outcome_evaluate_daily (143) was in the first cut of this file and is NOT re-enabled: fn_reputation_hold_state
  -- records an open reputation stand-down hold and requires it and reputation_weekly to stay inactive until that
  -- hold is closed on purpose. It is put back to inactive here so a re-apply cannot leave it on.
  perform cron.alter_job(143, active := false);
  perform public.fn_kernel_wrap_and_enable_cron(170, 'data_intelligence_director', 'data_intel', 'routine_operational_decision');   -- company_snapshot_daily (55 23 * * *)
  update public.phase_c_component set authority_class = 'routine_operational_decision' where component_id = 'cron:company_snapshot_daily' and authority_class is distinct from 'routine_operational_decision';
  perform public.fn_kernel_wrap_and_enable_cron(162, 'corporate_performance_director', 'exec', 'routine_operational_decision');   -- company_indices_daily (40 3 * * *)
  update public.phase_c_component set authority_class = 'routine_operational_decision' where component_id = 'cron:company_indices_daily' and authority_class is distinct from 'routine_operational_decision';
  perform public.fn_kernel_wrap_and_enable_cron(218, 'data_intelligence_director', 'data_intel', 'routine_operational_decision');   -- bi_snapshot_6h (35 */6 * * *)
  update public.phase_c_component set authority_class = 'routine_operational_decision' where component_id = 'cron:bi_snapshot_6h' and authority_class is distinct from 'routine_operational_decision';
  perform public.fn_kernel_wrap_and_enable_cron(165, 'corporate_performance_director', 'exec', 'routine_operational_decision');   -- opportunity_scan_daily (50 3 * * *)
  update public.phase_c_component set authority_class = 'routine_operational_decision' where component_id = 'cron:opportunity_scan_daily' and authority_class is distinct from 'routine_operational_decision';
  perform public.fn_kernel_wrap_and_enable_cron(155, 'supplier_coverage', 'marketplace', 'routine_operational_decision');   -- supply_gap_scan_daily (20 3 * * *)
  update public.phase_c_component set authority_class = 'routine_operational_decision' where component_id = 'cron:supply_gap_scan_daily' and authority_class is distinct from 'routine_operational_decision';
  perform public.fn_kernel_wrap_and_enable_cron(85, 'inquiry_router', 'marketplace', 'routine_operational_decision');   -- scan_new_supplier_categories (20 3 * * *)
  update public.phase_c_component set authority_class = 'routine_operational_decision' where component_id = 'cron:scan_new_supplier_categories' and authority_class is distinct from 'routine_operational_decision';
  perform public.fn_kernel_wrap_and_enable_cron(227, 'agent_workforce_capability_director', 'people_ops', 'routine_operational_decision');   -- tool_readiness_daily (55 3 * * *)
  update public.phase_c_component set authority_class = 'routine_operational_decision' where component_id = 'cron:tool_readiness_daily' and authority_class is distinct from 'routine_operational_decision';
  perform public.fn_kernel_wrap_and_enable_cron(226, 'ai_director', 'product_eng', 'model_prompt_change');   -- model_catalog_drift_daily (50 3 * * *)
  update public.phase_c_component set authority_class = 'model_prompt_change' where component_id = 'cron:model_catalog_drift_daily' and authority_class is distinct from 'model_prompt_change';
  perform public.fn_kernel_wrap_and_enable_cron(225, 'knowledge_director', 'data_intel', 'knowledge_publish');   -- kb_corpus_integrity_daily (40 3 * * *)
  update public.phase_c_component set authority_class = 'knowledge_publish' where component_id = 'cron:kb_corpus_integrity_daily' and authority_class is distinct from 'knowledge_publish';
  perform public.fn_kernel_wrap_and_enable_cron(221, 'it_operations_engineer', 'assurance', 'security_secret_rotation');   -- index_slowdown_watch_daily (15 4 * * *)
  update public.phase_c_component set authority_class = 'security_secret_rotation' where component_id = 'cron:index_slowdown_watch_daily' and authority_class is distinct from 'security_secret_rotation';
  perform public.fn_kernel_wrap_and_enable_cron(274, 'inquiry_router', 'marketplace', 'routine_operational_decision');   -- v3_category_readiness_daily (35 1 * * *)
  update public.phase_c_component set authority_class = 'routine_operational_decision' where component_id = 'cron:v3_category_readiness_daily' and authority_class is distinct from 'routine_operational_decision';
  perform public.fn_kernel_wrap_and_enable_cron(273, 'agent_workforce_capability_director', 'people_ops', 'routine_operational_decision');   -- v3_role_readiness_daily (30 1 * * *)
  update public.phase_c_component set authority_class = 'routine_operational_decision' where component_id = 'cron:v3_role_readiness_daily' and authority_class is distinct from 'routine_operational_decision';
  perform public.fn_kernel_wrap_and_enable_cron(272, 'knowledge_director', 'data_intel', 'knowledge_publish');   -- v3_knowledge_freshness_daily (25 1 * * *)
  update public.phase_c_component set authority_class = 'knowledge_publish' where component_id = 'cron:v3_knowledge_freshness_daily' and authority_class is distinct from 'knowledge_publish';
  perform public.fn_kernel_wrap_and_enable_cron(146, 'ceo', 'exec', 'routine_operational_decision');   -- goal_period_refresh_daily (45 2 * * *)
  update public.phase_c_component set authority_class = 'routine_operational_decision' where component_id = 'cron:goal_period_refresh_daily' and authority_class is distinct from 'routine_operational_decision';
  perform public.fn_kernel_wrap_and_enable_cron(176, 'chief_revenue_officer', 'growth', 'routine_operational_decision');   -- lead_lifecycle_refresh_daily (25 1 * * *)
  update public.phase_c_component set authority_class = 'routine_operational_decision' where component_id = 'cron:lead_lifecycle_refresh_daily' and authority_class is distinct from 'routine_operational_decision';
  perform public.fn_kernel_wrap_and_enable_cron(180, 'supplier_onboarding_specialist', 'marketplace', 'routine_operational_decision');   -- supplier_registration_state_resync_daily (5 0 * * *)
  update public.phase_c_component set authority_class = 'routine_operational_decision' where component_id = 'cron:supplier_registration_state_resync_daily' and authority_class is distinct from 'routine_operational_decision';
  perform public.fn_kernel_wrap_and_enable_cron(47, 'knowledge_director', 'data_intel', 'knowledge_publish');   -- graph_rebuild_daily (5 4 * * *)
  update public.phase_c_component set authority_class = 'knowledge_publish' where component_id = 'cron:graph_rebuild_daily' and authority_class is distinct from 'knowledge_publish';
  perform public.fn_kernel_wrap_and_enable_cron(269, 'knowledge_director', 'data_intel', 'knowledge_publish');   -- agent_context_head_refresh (40 */6 * * *)
  update public.phase_c_component set authority_class = 'knowledge_publish' where component_id = 'cron:agent_context_head_refresh' and authority_class is distinct from 'knowledge_publish';

  insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine) values
    (170, 'company_snapshot_daily', 'Pure SQL measurement: writes company_snapshot (the daily state the time machine replays), agent_runs.', 'Schedule 55 23 * * *; own transaction on a scheduled tick; measures the real estate and never a scenario fixture (fixtures carry ZZ DEMO names and qd_run tags and are torn down by the run that made them); close() asserts scenario rows by id/marker.'),
    (162, 'company_indices_daily', 'Pure SQL measurement: writes company_index (maturity, marketplace health, energy indices), agent_runs.', 'Schedule 40 3 * * *; own transaction on a scheduled tick; measures the real estate and never a scenario fixture (fixtures carry ZZ DEMO names and qd_run tags and are torn down by the run that made them); close() asserts scenario rows by id/marker.'),
    (218, 'bi_snapshot_6h', 'Pure SQL measurement: writes metric_snapshot.', 'Schedule 35 */6 * * *; own transaction on a scheduled tick; measures the real estate and never a scenario fixture (fixtures carry ZZ DEMO names and qd_run tags and are torn down by the run that made them); close() asserts scenario rows by id/marker.'),
    (165, 'opportunity_scan_daily', 'Pure SQL measurement: writes opportunity (detected opportunities), agent_runs.', 'Schedule 50 3 * * *; own transaction on a scheduled tick; measures the real estate and never a scenario fixture (fixtures carry ZZ DEMO names and qd_run tags and are torn down by the run that made them); close() asserts scenario rows by id/marker.'),
    (155, 'supply_gap_scan_daily', 'Pure SQL measurement: writes org_tasks (supply-gap follow-ups), agent_runs.', 'Schedule 20 3 * * *; own transaction on a scheduled tick; measures the real estate and never a scenario fixture (fixtures carry ZZ DEMO names and qd_run tags and are torn down by the run that made them); close() asserts scenario rows by id/marker.'),
    (85, 'scan_new_supplier_categories', 'Pure SQL measurement: writes nothing measured as a write target beyond its own run row.', 'Schedule 20 3 * * *; own transaction on a scheduled tick; measures the real estate and never a scenario fixture (fixtures carry ZZ DEMO names and qd_run tags and are torn down by the run that made them); close() asserts scenario rows by id/marker.'),
    (227, 'tool_readiness_daily', 'Pure SQL measurement: writes agent_actions (readiness findings).', 'Schedule 55 3 * * *; own transaction on a scheduled tick; measures the real estate and never a scenario fixture (fixtures carry ZZ DEMO names and qd_run tags and are torn down by the run that made them); close() asserts scenario rows by id/marker.'),
    (226, 'model_catalog_drift_daily', 'Pure SQL measurement: writes agent_actions (catalogue drift findings).', 'Schedule 50 3 * * *; own transaction on a scheduled tick; measures the real estate and never a scenario fixture (fixtures carry ZZ DEMO names and qd_run tags and are torn down by the run that made them); close() asserts scenario rows by id/marker.'),
    (225, 'kb_corpus_integrity_daily', 'Pure SQL measurement: writes agent_actions (corpus integrity findings).', 'Schedule 40 3 * * *; own transaction on a scheduled tick; measures the real estate and never a scenario fixture (fixtures carry ZZ DEMO names and qd_run tags and are torn down by the run that made them); close() asserts scenario rows by id/marker.'),
    (221, 'index_slowdown_watch_daily', 'Pure SQL measurement: writes evolution_proposal (a proposal, never an implementation), agent_runs.', 'Schedule 15 4 * * *; own transaction on a scheduled tick; measures the real estate and never a scenario fixture (fixtures carry ZZ DEMO names and qd_run tags and are torn down by the run that made them); close() asserts scenario rows by id/marker.'),
    (274, 'v3_category_readiness_daily', 'Pure SQL measurement: writes org_category_identity (readiness scores).', 'Schedule 35 1 * * *; own transaction on a scheduled tick; measures the real estate and never a scenario fixture (fixtures carry ZZ DEMO names and qd_run tags and are torn down by the run that made them); close() asserts scenario rows by id/marker.'),
    (273, 'v3_role_readiness_daily', 'Pure SQL measurement: writes org_role_identity (readiness scores).', 'Schedule 30 1 * * *; own transaction on a scheduled tick; measures the real estate and never a scenario fixture (fixtures carry ZZ DEMO names and qd_run tags and are torn down by the run that made them); close() asserts scenario rows by id/marker.'),
    (272, 'v3_knowledge_freshness_daily', 'Pure SQL measurement: writes ops_knowledge (freshness marks).', 'Schedule 25 1 * * *; own transaction on a scheduled tick; measures the real estate and never a scenario fixture (fixtures carry ZZ DEMO names and qd_run tags and are torn down by the run that made them); close() asserts scenario rows by id/marker.'),
    (146, 'goal_period_refresh_daily', 'Pure SQL measurement: writes goal_period, agent_runs.', 'Schedule 45 2 * * *; own transaction on a scheduled tick; measures the real estate and never a scenario fixture (fixtures carry ZZ DEMO names and qd_run tags and are torn down by the run that made them); close() asserts scenario rows by id/marker.'),
    (176, 'lead_lifecycle_refresh_daily', 'Pure SQL measurement: writes leads.lifecycle_stage (a derived column; never status, approval or contact).', 'Schedule 25 1 * * *; own transaction on a scheduled tick; measures the real estate and never a scenario fixture (fixtures carry ZZ DEMO names and qd_run tags and are torn down by the run that made them); close() asserts scenario rows by id/marker.'),
    (180, 'supplier_registration_state_resync_daily', 'Pure SQL measurement: writes leads.registration_state (a derived column; never status, approval or contact).', 'Schedule 5 0 * * *; own transaction on a scheduled tick; measures the real estate and never a scenario fixture (fixtures carry ZZ DEMO names and qd_run tags and are torn down by the run that made them); close() asserts scenario rows by id/marker.'),
    (47, 'graph_rebuild_daily', 'Pure SQL measurement: writes graph_nodes, graph_edges (the company brain), agent_runs.', 'Schedule 5 4 * * *; own transaction on a scheduled tick; measures the real estate and never a scenario fixture (fixtures carry ZZ DEMO names and qd_run tags and are torn down by the run that made them); close() asserts scenario rows by id/marker.'),
    (269, 'agent_context_head_refresh', 'Pure SQL measurement: writes agent_context_head (the cached employee context).', 'Schedule 40 */6 * * *; own transaction on a scheduled tick; measures the real estate and never a scenario fixture (fixtures carry ZZ DEMO names and qd_run tags and are torn down by the run that made them); close() asserts scenario rows by id/marker.')
  on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;

  insert into public.cron_registry (jobname, human_name, category, purpose) values
    ('incident_watchdog_hourly', 'Incident watchdog', 'resilience', 'Hourly: turns silent failures into incidents the OS shows.'),
    ('remediation_escalate_consume_daily', 'Remediation escalation', 'self_management', 'Daily: escalates remediations that have missed their window.'),
    ('promotion_review_weekly', 'Promotion review', 'self_management', 'Weekly: reviews employees for promotion on evidence.'),
    ('it_security_live_posture_hourly', 'IT security posture', 'security', 'Hourly: recomputes the live security posture knowledge record.'),
    ('supplier_suspension_proposed_daily', 'Supplier suspension proposals', 'trust_and_safety', 'Daily: emits supplier.suspension_proposed for expired licences.'),
    ('kb_embed_ops_knowledge', 'Embed operating knowledge', 'knowledge', 'Every minute: embeds unembedded ops_knowledge rows (free in-region model).'),
    ('ads_autopilot_daily', 'Ad spend autopilot', 'growth', 'Daily 04:20 UTC: judges Meta campaigns by cost per lead inside a DB-enforced ceiling and executes decisions through meta_ads.'),
    ('v3_role_readiness_daily', 'Role readiness', 'people_ops', 'Daily 01:30 UTC: recomputes each role identity''s readiness score.'),
    ('v3_category_readiness_daily', 'Category readiness', 'marketplace', 'Daily 01:35 UTC: recomputes each category identity''s readiness score.'),
    ('v3_knowledge_freshness_daily', 'Knowledge freshness', 'knowledge', 'Daily 01:25 UTC: marks ops_knowledge rows whose review is due.')
  on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
end $$;
commit;

do $ctl$
begin
  if (select count(*) from cron.job where jobid in (170,162,218,165,155,85,227,226,225,221,274,273,272,146,176,180,47,269) and active and command ilike '%fn_kernel_cron_exec%') <> 18 then
    raise exception 'not all 18 measurement crons are active and wrapped';
  end if;
  if exists (select 1 from cron.job j where j.active and not exists (select 1 from public.cron_registry r where r.jobname = j.jobname)) then
    raise exception 'an active job is still undocumented in cron_registry: %', (select string_agg(j.jobname, ', ') from cron.job j where j.active and not exists (select 1 from public.cron_registry r where r.jobname = j.jobname));
  end if;
end $ctl$;
