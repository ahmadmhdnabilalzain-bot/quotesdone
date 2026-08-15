// Current-estate artefact -> canonical Phase B workflow.
//
// Every entry was assigned from what the artefact DOES (its name, its command, the table it
// writes), not from what a similarly-named canonical workflow would like to own.  Artefacts
// that serve every workflow equally are 'ALL'; artefacts unrelated to the 30 business
// workflows are 'OUT_OF_SCOPE' and are classified as such rather than force-fitted.

/** cron job name -> workflow_id | 'ALL' | 'OUT_OF_SCOPE' */
export const CRON_TO_WORKFLOW = {
  // W01 founder mandate to company objectives
  goal_decompose_weekly: 'W01', goal_period_refresh_daily: 'W01', ceo_questions_weekly: 'W01',
  founder_brief_daily: 'W01', founder_habits_daily: 'W01', strategy_ai_daily: 'W01',
  dept_objective_measure_daily: 'W01', os_objective_measure_daily: 'W01', board_report_weekly: 'W01',
  exec_meeting_weekly: 'W01', 'exec-agents-weekly': 'W01', day_conductor_daily: 'W01',
  dept_plan_daily: 'W01', company_selfknowledge_refresh: 'W01',
  // W02 target miss and corrective management
  kpi_review_weekly: 'W02', employee_kpi_measure_daily: 'W02', emit_metric_alerts: 'W02',
  os_review_weekly: 'W02', self_review_weekly: 'W02', company_indices_daily: 'W02',
  outcome_evaluate_daily: 'W02', decision_conflict_scan_weekly: 'W02', reallocate_monthly: 'W02',
  opportunity_scan_daily: 'W02', evolution_scan_weekly: 'W02', improvement_plan_daily: 'W02',
  improvement_handover_hourly: 'W02', os_improve_weekly: 'W02', scenario_rehearsal_weekly: 'W02',
  scenario_staffing_weekly: 'W02', ops_scenarios_hourly: 'W02', company_reflect_nightly: 'W02',
  os_health_brief_weekly: 'W02', delete_proposer_weekly: 'W02',
  // W03 customer acquisition
  lead_lifecycle_refresh_daily: 'W03', invite_ramp_daily: 'W03', boost_recommend_weekly: 'W03',
  category_sales_daily: 'W03', founding_rank_daily: 'W03', backfill_invite_trades: 'W03',
  // W04 customer registration and onboarding
  customer_success_daily: 'W04', dues_ban_overdue_daily: 'W04',
  // W05 inquiry intake and qualification
  rfq_clarify_6h: 'W05', no_quote_nudges: 'W05',
  // W06 category routing
  scan_new_supplier_categories: 'W06', v3_category_readiness_daily: 'W06',
  // W07 document/BOQ/drawing processing
  doc_process: 'W07', doc_reminders_daily: 'W07', doc_expiry_daily: 'W07',
  doc_final_notice_daily: 'W07', document_controller_daily: 'W07', boq_fixture_check_weekly: 'W07',
  // W09 supplier onboarding
  supplier_invites_daily: 'W09', supplier_registration_state_resync_daily: 'W09',
  pending_suppliers_digest: 'W09',
  // W10 supplier verification
  capability_verify_daily: 'W10', capability_backfill_daily: 'W10',
  capability_enrich_retry_6h: 'W10', supplier_capability_chase_daily: 'W10',
  licence_block_reconcile_daily: 'W10',
  // W11 supplier coverage and acquisition gaps
  supply_gap_scan_daily: 'W11', embed_suppliers_daily: 'W11',
  // W12 supplier matching and dispatch
  rfq_redispatch_6h: 'W12', match_eval_weekly: 'W12',
  // W13 supplier notification delivery
  email_cron_2min: 'W13', sms_flush: 'W13', wa_flush: 'W13', email_triage_hourly: 'W13',
  // W15 customer comparison and reveal
  'reveal-nudges': 'W15',
  // W16 payment, billing and reconciliation
  subscription_billing_daily: 'W16', gl_sync_nightly: 'W16', money_tests_daily: 'W16',
  dues_interest_daily: 'W16', collections_legal_daily: 'W16', finance_reminders_daily: 'W16',
  finance_ai_daily: 'W16',
  // W17 refund, dispute and fraud
  fraud_scan_daily: 'W17', supplier_risk_complaints: 'W17',
  // W18 customer support and retention
  retention_purge_weekly: 'W18',
  // W19 supplier retention
  supplier_success_daily: 'W19', supplier_score_refresh_daily: 'W19',
  supplier_risk_performance_drops: 'W19', supplier_risk_response_delays: 'W19',
  supplier_exception_sweep_daily: 'W19', agent_supply_health_daily: 'W19',
  // W20 marketing content lifecycle
  content_revise_hourly: 'W20', social_stage_hourly: 'W20', meta_sync_daily: 'W20',
  blog_weekly_mon: 'W20', seo_gen_weekly: 'W20', agent_marketing_weekly: 'W20',
  marketing_ai_daily: 'W20', reputation_weekly: 'W20',
  // W22 product discovery to delivery
  auto_deploy: 'W22', site_autodeploy: 'W22',
  // W23 AI/model/prompt change
  model_autoswitch_daily: 'W23', model_benchmark_daily: 'W23', model_catalog_drift_daily: 'W23',
  llm_drift_watch_daily: 'W23', ai_quality_watch_daily: 'W23', ai_health_15min: 'W23',
  ai_spend_guard_hourly: 'W23', ai_trainer_daily: 'W23', eval_weekly: 'W23', canon_eval_weekly: 'W23',
  // W24 release and production approval
  qa_suite_daily: 'W24', smoke_test_30min: 'W24', approval_trace_audit_weekly: 'W24',
  autonomy_audit_weekly: 'W24', autonomy_dispose_hourly: 'W24',
  // W25 data reporting and forecasting
  bi_snapshot_6h: 'W25', company_snapshot_daily: 'W25', monthly_report: 'W25',
  quarterly_report: 'W25', reporting_ai_daily: 'W25', cost_snapshot_weekly: 'W25',
  cost_snapshot_balance_daily: 'W25', 'response-recompute': 'W25', spend_concentration_weekly: 'W25',
  // W26 knowledge creation and validation
  kb_autofill_gaps_weekly: 'W26', kb_corpus_integrity_daily: 'W26', kb_deepen_loop: 'W26',
  kb_embed_backfill: 'W26', kb_embed_backfill_boost: 'W26', kb_embed_priority_kinds: 'W26',
  kb_ingest_queue: 'W26', kb_reconcile_daily: 'W26', kb_route_tests_hourly: 'W26',
  kb_sync_daily: 'W26', knowledge_curator_daily: 'W26', knowledge_decay_daily: 'W26',
  knowledge_exam_loop: 'W26', learn_gaps_weekly: 'W26', gen_category_knowledge_daily: 'W26',
  gen_category_personas_daily: 'W26', sop_update_weekly: 'W26', memory_promotion_weekly: 'W26',
  graph_rebuild_daily: 'W26', agent_context_head_refresh: 'W26', v3_knowledge_freshness_daily: 'W26',
  v3_context_retrieval_prune_daily: 'W26',
  // W27 financial planning and accounting close
  budget_rollup_daily: 'W27', agent_finance_weekly: 'W27',
  // W28 legal, compliance and risk review
  legal_ai_daily: 'W28', regulation_watch_weekly: 'W28', agent_compliance_weekly: 'W28',
  policy_consistency_weekly: 'W28', vt_scan_daily: 'W28',
  // W29 security incident and reliability recovery
  security_ai_daily: 'W29', security_selfaudit_daily: 'W29', agent_security_hourly: 'W29',
  agent_it_health_hourly: 'W29', uptime_check_15min: 'W29', resilience_watch_10min: 'W29',
  edge_health_scan_15min: 'W29', watch_health_daily: 'W29', watch_failed_runs_hourly: 'W29',
  backup_daily: 'W29', backup_watch_daily: 'W29', dr_drill_monthly: 'W29',
  index_slowdown_watch_daily: 'W29', ops_watch_hourly: 'W29', health_check: 'W29',
  operations_ai_daily: 'W29',
  // W30 agent performance, remediation and organization design
  agent_autogen_daily: 'W30', agent_reflect_weekly: 'W30', agent_silence_watch_daily: 'W30',
  agent_learnings_weekly: 'W30', runner_silence_watch_daily: 'W30', tool_readiness_daily: 'W30',
  v3_role_readiness_daily: 'W30', learning_loop_sweep_hourly: 'W30',
  experience_promote_weekly: 'W30', agent_onboarding_hourly: 'W30', agent_followup_daily: 'W30',
  ea_assistant_daily: 'W30', cos_execute_hourly: 'W30', dept_learn_daily: 'W01',
  // cross-cutting workflow engine: serves every canonical workflow
  action_invoke_collect_5min: 'ALL', action_invoke_dispatch_5min: 'ALL', action_invoke_rpc_5min: 'ALL',
  action_queue_sweep_hourly: 'ALL', agent_action_work_sweep_hourly: 'ALL',
  org_task_assign_hourly: 'ALL', org_task_execute_sweep_hourly: 'ALL',
  execution_run_hourly: 'ALL', execution_sweep_hourly: 'ALL', task_approve_hourly: 'ALL',
  workflow_dispatch_10min: 'ALL', workflow_start_due: 'ALL', workflow_step_sweep_10min: 'ALL',
  emit_task_assigned: 'ALL', event_dispatch_15min: 'ALL', event_consolidate: 'ALL',
  sla_watch_hourly: 'ALL', exception_alerts_hourly: 'ALL', dead_letter_drain_held: 'ALL',
  control_mode_sweep_5min: 'ALL',
  // platform housekeeping: not one of the 30 business workflows
  cron_history_prune: 'OUT_OF_SCOPE', audit_prune_weekly: 'OUT_OF_SCOPE',
  archive_completed_daily: 'OUT_OF_SCOPE', github_org_sync_nightly: 'OUT_OF_SCOPE',
  dropbox_backup_scan: 'OUT_OF_SCOPE', dropbox_sync_daily: 'OUT_OF_SCOPE',
  assets_ingest_6h: 'OUT_OF_SCOPE',
};

/** Runtime workflow row (public.workflow.workflow_key) -> canonical workflow(s). */
export const RUNTIME_WORKFLOW_TO_CANONICAL = {
  budget_cycle: ['W27'],
  campaign_publishing: ['W20'],
  change_deployment: ['W24'],
  complaint: ['W18'],
  contract_review: ['W28'],
  customer_registration: ['W04'],
  employee_task: ['ALL'],
  improvement_lifecycle: ['W02', 'W30'],
  incident_response: ['W29'],
  invoice_approval: ['W16'],
  knowledge_lifecycle: ['W26'],
  lead_to_customer: ['W03'],
  metric_lifecycle: ['W25'],
  payment: ['W16'],
  refund: ['W17'],
  rfq_handling: ['W05', 'W06', 'W08', 'W12', 'W14', 'W15'],
  strategic_review: ['W01', 'W02'],
  supplier_onboarding: ['W09', 'W10'],
  supplier_suspension: ['W19'],
};

/** Edge function slug -> canonical workflow. Unlisted slugs fall through to OUT_OF_SCOPE. */
export const EDGE_TO_WORKFLOW = {
  // W01/W02 leadership
  ceo_brief: 'W01', founder_brief: 'W01', exec_meeting: 'W01', day_conductor: 'W01',
  goal_decompose: 'W01', dept_plan: 'W01', dept_learn: 'W01', strategy_agent: 'W01',
  os_api: 'W02', evolution_scan: 'W02', improvement_plan: 'W02', opportunity_scan: 'W02',
  ea_meeting_summary: 'W01', secretary_act: 'W01', copilot: 'W02',
  // W03 acquisition
  export_leads_csv: 'W03', lead_api: 'W03', boost_recommend: 'W03', analytics_recommend: 'W03',
  // W04 customer registration
  auth_api: 'W04', customer_api: 'W04', mobile_otp: 'W04', voice_otp: 'W04',
  voice_otp_capture: 'W04', qa_login: 'W04', dev_login: 'W04', qa_mint: 'W04', profile_ai: 'W04',
  // W05/W06 inquiry
  inquiry_ai: 'W05', inquiry_parse: 'W05', inquiry_dedup_check: 'W05', dispatch_inquiry: 'W05',
  route_inquiry: 'W06', intent_router: 'W06', category_reqs: 'W06', project_consultant: 'W05',
  // W07 documents
  extract_text: 'W07', cad_convert: 'W07', pdf_native: 'W07', doc_render: 'W07',
  quote_extract: 'W07', attach_photos: 'W07', make_pdf: 'W07', make_xlsx: 'W07',
  dir_ingest: 'W07', rate_dims: 'W07',
  // W09/W10 supplier
  supplier_api: 'W09', sup_dob: 'W09', supplier_review: 'W10', reg_fetch: 'W10',
  licence_reminder: 'W10', capability_agent: 'W10',
  // W11 coverage
  apify_scrape: 'W11', yello_scrape: 'W11',
  // W12 dispatch / W14 quotation / W15 reveal
  match: 'W12', quote_quality: 'W14', quote_review: 'W14', quote_pdf: 'W14',
  quote_compare: 'W15', reveal_invoice: 'W15',
  // W13 notification delivery
  inbound_email: 'W13', resend_inbound: 'W13', resend_webhook: 'W13', wa_inbound: 'W13',
  wa_template_setup: 'W13', wa_templates_watch: 'W13', unsubscribe: 'W13', email_fix: 'W13',
  // W16/W17 money
  stripe_setup: 'W16', stripe_setup_page: 'W16', refund_flow: 'W17', refunds_api: 'W17',
  // W18 support
  support_ai: 'W18', site_assistant: 'W18', contact_submit: 'W18', faq: 'W18',
  // W20 marketing
  marketing_draft: 'W20', marketing_image: 'W20', postiz_publish: 'W20', meta_ads: 'W20',
  video_produce: 'W20', brand_upload: 'W20', designer: 'W20', asset_delete: 'W20',
  // W22 product delivery
  deploy_next_preview: 'W22', push_src_to_github: 'W22', sync_src_from_github: 'W22',
  put_src: 'W22', src_io: 'W22', vercel_status: 'W22',
  // W23 AI change
  agent_brain: 'W23', agent_train: 'W23', prompt_gate: 'W23', ai_gateway: 'W23',
  kb_research_test: 'W23', orchestrate: 'W23',
  // W24 release
  qa_api: 'W24', artifact_review: 'W24',
  // W25 reporting
  public_stats: 'W25',
  // W26 knowledge
  kb_import: 'W26', kb_corpus_import: 'W26', kb_ingest_text: 'W26', kb_retrieve: 'W26',
  kb_search: 'W26', kb_embed: 'W26', export_all_knowledge: 'W26', export_cat_knowledge: 'W26',
  // W28 legal
  legal: 'W28', legal_ingest: 'W28', legal_review: 'W28', pdpl_request: 'W28', pdpl_erase: 'W28',
  // W29 reliability
  health: 'W29', edge_health: 'W29',
  // W30 workforce
  agent_act: 'W30', action_worker: 'ALL',
  // ---- second pass: the 90 slugs the first pass left unmapped ----
  // W01 / W02 leadership and the operating system surfaces
  exec_agents: 'W01', alert_founder: 'W01', os_automation: 'W02', os_catalog: 'W02',
  os_ops: 'W02', os_pages: 'W02', os_settings: 'W02', report_body: 'W25',
  // W03 acquisition
  embed_leads: 'W03',
  // W04 registration
  login_otp: 'W04',
  // W05 / W06 inquiry
  inquiry_intake: 'W05', project_api: 'W05', archive_rfq: 'W05', rfq_flag: 'W05',
  category_provision: 'W06',
  // W07 documents, W08 supplier-safe package
  doc_extract: 'W07', doc_reminder: 'W07', drawing_boq: 'W07', transcribe: 'W07',
  customer_documents: 'W07', boq_fixture_check: 'W07', drawing_redact: 'W08',
  // W09 / W10 supplier
  supplier_onboard: 'W09', supplier_portal: 'W09', pending_digest: 'W09', claim_lookup: 'W09',
  kyc: 'W10', enrich_capability: 'W10', supplier_catalog_ingest: 'W10', license_extract: 'W10',
  // W12 dispatch, W14 quotation, W15 reveal
  procurement_api: 'W12', supplier_ack: 'W12', match_eval: 'W12',
  negotiation_assistant: 'W14', customer_portal: 'W15',
  // W13 notification delivery
  email_cron: 'W13', email_triage: 'W13', send_outbox: 'W13', send_sms: 'W13',
  send_whatsapp: 'W13', messages_api: 'W13', wa_optin_set: 'W13',
  // W16 money
  stripe_checkout: 'W16', stripe_confirm: 'W16', stripe_webhook: 'W16', supplier_pay: 'W16',
  finance_doc: 'W16', finance_ingest: 'W16', collections_legal: 'W16', money_tests: 'W16',
  // W20 marketing
  blog_weekly: 'W20', seo_gen: 'W20', content_revise: 'W20', social_stage: 'W20',
  meta_sync: 'W20',
  // W22 product delivery
  site_deploy: 'W22', github_sync: 'W22',
  // W23 AI change, W24 release
  ai_health: 'W23', prompt_improve: 'W23', canon_eval: 'W23', qa_suite: 'W24',
  // W25 reporting
  cost_snapshot: 'W25', customer_intelligence: 'W25',
  // W26 knowledge
  gen_category_knowledge: 'W26', gen_category_personas: 'W26', kb_autofill_gaps: 'W26',
  kb_deepen: 'W26', kb_fill_gap: 'W26', kb_ingest: 'W26', knowledge_exam: 'W26',
  learn_gaps: 'W26',
  // W28 legal and compliance
  compliance_archive: 'W28', retention_purge: 'W28', vt_scan: 'W28',
  // W29 reliability
  backup: 'W29', dr_drill: 'W29', uptime_check: 'W29', resilience_ping: 'W29',
  os_health: 'W29', os_incidents: 'W29',
  // W30 workforce
  agents: 'W30', agent_autogen: 'W30', agent_learnings_report: 'W30', reflect: 'W30',
  cos_execute: 'W30',
  // cross-cutting workflow engine
  workflow_dispatch: 'ALL', role_guard: 'ALL',
  // public marketing/content surfaces and platform plumbing: not one of the 30 workflows
  about: 'OUT_OF_SCOPE', home: 'OUT_OF_SCOPE', 'home-ar': 'OUT_OF_SCOPE',
  portal: 'OUT_OF_SCOPE', i18n_get: 'OUT_OF_SCOPE', translate_html: 'OUT_OF_SCOPE',
  translate_page: 'OUT_OF_SCOPE', dropbox_oauth: 'OUT_OF_SCOPE',
  assets_ingest: 'OUT_OF_SCOPE', dropbox_backup: 'OUT_OF_SCOPE', dropbox_sync: 'OUT_OF_SCOPE',
};

/** Frontend route -> canonical workflow. */
export const ROUTE_TO_WORKFLOW = {
  '/[locale]': 'W03', '/[locale]/about': 'OUT_OF_SCOPE', '/[locale]/blog': 'W20',
  '/[locale]/blog/[slug]': 'W20', '/[locale]/complaints': 'W18', '/[locale]/console': 'W02',
  '/[locale]/contact': 'W18', '/[locale]/faq': 'W18', '/[locale]/me': 'W04',
  '/[locale]/os': 'W02', '/[locale]/portal': 'W15', '/[locale]/services': 'W03',
  '/[locale]/services/[slug]': 'W05', '/[locale]/supplier': 'W09',
  '/[locale]/acceptable-use': 'W28', '/[locale]/cookie-policy': 'W28',
  '/[locale]/disclaimer': 'W28', '/[locale]/privacy': 'W28', '/[locale]/refund-policy': 'W28',
  '/[locale]/supplier-agreement': 'W28', '/[locale]/terms': 'W28',
  '/api/resilience-ping': 'W29', '/robots.txt': 'OUT_OF_SCOPE', '/sitemap.xml': 'OUT_OF_SCOPE',
};
