-- ================================================================================================
-- QuotesDone — FULL SCHEMA EXPORT
-- Captured 2026-11-03T02:01:04.582Z from public.fn_schema_export() on htdblwldjkcgjvmqkbeh.
--
-- This is a REFERENCE MIRROR of the live database, not a restore procedure. To rebuild, use
-- Supabase managed backups / PITR. Replaying this file is not a supported recovery path and
-- replaying scripts/sql in order is not one either — those files are records of changes that
-- were applied, not a schema.
--
-- Regenerate with: node scripts/checks/export_from_either_source_is_identical.mjs --write
-- Verify with the same command and no flag: it fails if the database and this file disagree.
-- ================================================================================================
-- ===== END BANNER — the schema export begins below, and IS compared byte for byte =====
-- QuotesDone — FULL SCHEMA EXPORT (generated from the live database)
-- Excludes: secret VALUES (key names listed below), and table ROW DATA (PII).
-- Order is best-effort; this is a faithful reference mirror, not a guaranteed one-click restore.

-- ===== EXTENSIONS =====
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;

-- ===== SEQUENCES =====
CREATE SEQUENCE IF NOT EXISTS public.accountant_issued_document_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.accountant_spend_report_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.accountant_weekly_report_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.agent_actions_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.agent_command_log_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.agent_context_retrieval_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.agent_evals_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.agent_knowledge_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.agent_memory_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.agent_remediation_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.agent_runs_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.agent_training_attempt_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.ai_constitution_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.ai_cost_log_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.ai_model_register_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.allocation_change_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.artifact_review_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.autonomy_control_audit_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.backup_prune_log_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.bank_statement_line_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.board_opinion_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.board_reports_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.boq_fixture_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.boq_fixture_run_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.brand_assets_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.business_rules_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.canon_eval_questions_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.canon_eval_runs_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.category_keyword_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.category_quote_specs_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.ceo_company_stage_log_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.ceo_daily_digest_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.ceo_decision_log_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.ceo_experiment_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.ceo_improvement_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.ceo_plan_action_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.ceo_plan_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.ceo_weekly_report_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.challenge_heuristic_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.challenge_record_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.channel_directive_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.collaboration_rule_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.company_calendar_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.company_charter_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.company_event_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.company_index_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.company_reflection_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.company_stand_down_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.competitive_position_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.competitor_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.competitor_scan_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.compliance_sources_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.contact_merge_audit_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.control_mode_audit_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.customer_calls_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.dead_letter_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.decision_log_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.decision_record_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.delegation_rule_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.demand_search_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.department_objective_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.dept_library_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.doc_backups_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.doc_versions_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.documents_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.email_block_pattern_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.employee_kpi_history_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.employee_kpi_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.entity_comments_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.error_events_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.event_assessment_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.event_delivery_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.evolution_proposal_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.expense_entries_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.expense_vendor_billing_mailbox_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.expenses_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.feedback_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.finance_reports_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.finance_snapshots_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.founder_directive_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.founder_instruction_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.founder_mail_policy_history_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.goal_period_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.governance_policy_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.handoff_contract_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.idea_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.inquiries_rfq_no_seq;
CREATE SEQUENCE IF NOT EXISTS public.inquiry_answer_conflict_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.inquiry_answer_conflict_value_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.inquiry_answer_corroboration_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.inquiry_answer_document_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.inquiry_answer_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.inquiry_gate_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.inquiry_scope_disposition_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.inquiry_state_audit_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.inquiry_supplier_brief_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.inquiry_trade_candidate_evidence_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.inquiry_trade_candidate_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.inquiry_trade_clarification_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.inquiry_workstream_group_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.inquiry_workstream_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.inquiry_workstream_requirement_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.institutional_memory_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.internal_credential_audit_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.internal_credential_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.invite_brake_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.it_game_day_run_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.it_integration_external_cause_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.it_load_test_run_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.it_restore_drill_result_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.kb_revisions_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.knowledge_exam_questions_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.knowledge_exam_results_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.lead_prospect_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.lead_sourcing_run_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.licence_renewal_ask_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.llm_calls_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.marketing_asset_perception_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.marketing_asset_review_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.marketing_library_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.marketing_model_run_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.marketing_plan_review_turn_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.mdm_brands_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.mdm_manufacturers_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.mdm_standards_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.metric_snapshot_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.notice_plain_language_cause_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.openrouter_meter_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.opportunity_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.os_fresh_start_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.os_interface_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.os_objective_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.os_review_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.outcome_record_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.pdpl_erase_files_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.phase1_rollback_log_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.phone_code_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.policy_rules_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.price_benchmark_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.prompt_versions_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.quote_comparisons_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.quote_items_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.refund_case_refund_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.refund_ceo_check_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.refund_ceo_review_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.refund_event_quarantine_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.refund_incident_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.refund_ladder_evidence_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.refunds_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.removed_trigger_log_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.resource_pool_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.review_chain_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.review_hold_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.review_queue_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.rfq_archives_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.risk_register_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.sales_decision_log_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.sales_knowledge_gap_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.sanctions_ban_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.screening_entry_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.screening_run_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.seat_case_memory_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.seat_case_memory_miss_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.seat_knowledge_eval_question_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.seat_knowledge_exam_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.self_review_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.signup_purge_dropbox_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.signup_purge_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.signup_purge_object_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.simulations_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.spec_alternative_offer_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.spec_backlog_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.supplier_reply_followup_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.supplier_response_watch_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.supplier_screening_hit_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.supply_health_snapshots_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.supply_recruitment_brief_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.support_artifact_artifact_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.support_case_case_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.support_ceo_report_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.support_document_intake_intake_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.support_identity_challenge_challenge_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.support_notification_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.support_reply_readability_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.table_export_change_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.target_contract_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.target_driver_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.target_verdict_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.taxonomy_trade_proposal_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.wa_answer_log_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.wa_conversation_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.wa_document_intake_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.wa_messages_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.wa_turn_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.workflow_step_run_id_seq;

-- ===== TABLES (777) =====
CREATE TABLE IF NOT EXISTS public.accountant_ad_spend_month (
  month date NOT NULL,
  reported_spend_aed numeric(14,2),
  reported_at timestamp with time zone,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.accountant_budget_variance (
  month date NOT NULL,
  account_code text NOT NULL,
  budget_aed numeric(18,2) NOT NULL,
  actual_aed numeric(18,2) NOT NULL,
  variance_aed numeric(18,2) NOT NULL,
  variance_pct numeric,
  explanation text NOT NULL,
  drivers jsonb DEFAULT '[]'::jsonb NOT NULL,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.accountant_cash_forecast_week (
  week date NOT NULL,
  forecast jsonb NOT NULL,
  ceo_report_id bigint,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.accountant_founder_close_pack (
  month date NOT NULL,
  figures jsonb NOT NULL,
  built_at timestamp with time zone DEFAULT now() NOT NULL,
  pdf_bucket text,
  pdf_path text,
  rendered_at timestamp with time zone,
  render_error text,
  sent_at timestamp with time zone,
  notification_id bigint,
  send_result jsonb
);

CREATE TABLE IF NOT EXISTS public.accountant_issued_document (
  id bigint DEFAULT nextval('accountant_issued_document_id_seq'::regclass) NOT NULL,
  document_kind text NOT NULL,
  template_key text,
  template_version text NOT NULL,
  content_sha256 text NOT NULL,
  recipient text NOT NULL,
  supplier_id bigint,
  due_id bigint,
  handoff_id bigint,
  file_path text,
  signed_as text DEFAULT 'founder'::text NOT NULL,
  stamp_required boolean DEFAULT true NOT NULL,
  signature_required boolean DEFAULT true NOT NULL,
  issued_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.accountant_knowledge (
  record_id text NOT NULL,
  record_type text NOT NULL,
  domain text,
  title text NOT NULL,
  content text NOT NULL,
  structured_data jsonb DEFAULT '{}'::jsonb NOT NULL,
  source_ids text[] DEFAULT '{}'::text[] NOT NULL,
  epistemic_status text NOT NULL,
  jurisdiction text,
  pack_id text NOT NULL,
  pack_version text NOT NULL,
  body_sha256 text NOT NULL,
  runtime_index_eligible boolean DEFAULT true NOT NULL,
  authority_effect text DEFAULT 'none'::text NOT NULL,
  tags text[] DEFAULT '{}'::text[] NOT NULL,
  updated_at timestamp with time zone,
  ingested_at timestamp with time zone DEFAULT now() NOT NULL,
  embedding_gte vector(384),
  search tsvector
);

CREATE TABLE IF NOT EXISTS public.accountant_mailbox_check (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  checked_at timestamp with time zone DEFAULT now() NOT NULL,
  listed integer NOT NULL,
  not_taken_in integer NOT NULL,
  held_over_24h integer NOT NULL,
  last_received_at timestamp with time zone,
  verdict text NOT NULL,
  detail jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS public.accountant_month_close (
  month date NOT NULL,
  figures jsonb NOT NULL,
  ceo_report_id bigint,
  pdf_bucket text,
  pdf_path text,
  csv_path text,
  closed_at timestamp with time zone DEFAULT now() NOT NULL,
  rendered_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.accountant_owner_ruled_subscription (
  vendor text NOT NULL,
  vendor_pattern text NOT NULL,
  bank_value_aed numeric(18,2) NOT NULL,
  cadence text DEFAULT 'monthly'::text NOT NULL,
  usual_day integer NOT NULL,
  expected_from date NOT NULL,
  paid_from text DEFAULT 'owner_card'::text NOT NULL,
  bank_pattern text,
  receipt_emailed boolean NOT NULL,
  basis text NOT NULL,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.accountant_renewal_budget (
  item text NOT NULL,
  kind text NOT NULL,
  expires_on date,
  pay_by date,
  budget_aed numeric(14,2),
  basis text NOT NULL,
  last_expense_id bigint,
  handoff_id bigint,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.accountant_spend_report (
  id bigint DEFAULT nextval('accountant_spend_report_id_seq'::regclass) NOT NULL,
  company_key text DEFAULT 'quotesdone'::text NOT NULL,
  as_of date NOT NULL,
  period_start date,
  period_end date,
  local_timezone text DEFAULT 'Asia/Dubai'::text NOT NULL,
  entries integer,
  total_aed numeric(18,2),
  vat_stated_aed numeric(18,2),
  usd_to_aed numeric(18,6),
  complete boolean,
  shortfalls jsonb,
  figures jsonb DEFAULT '{}'::jsonb NOT NULL,
  coverage jsonb,
  subject text,
  body text,
  pdf_bucket text,
  pdf_path text,
  pdf_url text,
  pdf_bytes bigint,
  notification_id bigint,
  generated_at timestamp with time zone DEFAULT now() NOT NULL,
  delivered_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.accountant_subscription_paid_from_change (
  vendor text NOT NULL,
  effective_from date NOT NULL,
  paid_from text NOT NULL,
  basis text NOT NULL,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.accountant_ubo_seen (
  lead_id bigint NOT NULL,
  owner_name text NOT NULL,
  owner_norm text NOT NULL,
  first_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  changed_at timestamp with time zone,
  previous_owner_name text
);

CREATE TABLE IF NOT EXISTS public.accountant_vat_threshold_check (
  checked_on date NOT NULL,
  taxable_12m_aed numeric(18,2) NOT NULL,
  last_30d_aed numeric(18,2) NOT NULL,
  projected_aed numeric(18,2) NOT NULL,
  status text NOT NULL,
  register_by date,
  ceo_report_id bigint,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.accountant_weekly_report (
  id bigint DEFAULT nextval('accountant_weekly_report_id_seq'::regclass) NOT NULL,
  company_key text DEFAULT 'quotesdone'::text NOT NULL,
  iso_year integer NOT NULL,
  iso_week integer NOT NULL,
  week_start date NOT NULL,
  week_end date NOT NULL,
  local_timezone text DEFAULT 'Asia/Dubai'::text NOT NULL,
  report_key text NOT NULL,
  revision integer DEFAULT 1 NOT NULL,
  revision_note text,
  subject text,
  body text,
  figures jsonb DEFAULT '{}'::jsonb NOT NULL,
  pdf_blocks jsonb,
  pdf_bucket text,
  pdf_path text,
  pdf_url text,
  pdf_bytes integer,
  pdf_generated_at timestamp with time zone,
  pdf_error text,
  status text DEFAULT 'generated'::text NOT NULL,
  generated_at timestamp with time zone DEFAULT now() NOT NULL,
  founder_submitted_at timestamp with time zone,
  ceo_submitted_at timestamp with time zone,
  delivered_at timestamp with time zone,
  notification_id bigint,
  ceo_report_id bigint,
  delivery_attempts integer DEFAULT 0 NOT NULL,
  last_delivery_error text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.accountant_year_end_pack (
  year integer NOT NULL,
  files jsonb DEFAULT '[]'::jsonb NOT NULL,
  rendered_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.action_class_demand (
  action_class text NOT NULL,
  on_revenue_path boolean NOT NULL,
  reason text NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.action_class_gate (
  action_class text NOT NULL,
  gate_action_class text,
  rationale text NOT NULL,
  reviewed_on date DEFAULT CURRENT_DATE NOT NULL,
  reviewed_by text DEFAULT 'founder'::text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.action_execution (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  correlation_id uuid NOT NULL,
  workflow_step_run_id bigint,
  action_class text NOT NULL,
  executor text NOT NULL,
  idempotency_key text NOT NULL,
  risk_tier text NOT NULL,
  reversible boolean DEFAULT false NOT NULL,
  request jsonb NOT NULL,
  response jsonb,
  status text DEFAULT 'queued'::text NOT NULL,
  attempts integer DEFAULT 0 NOT NULL,
  compensation_action_class text,
  compensated_at timestamp with time zone,
  started_at timestamp with time zone,
  finished_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  author text
);

CREATE TABLE IF NOT EXISTS public.ad_campaign_state (
  campaign_id text NOT NULL,
  campaign_name text,
  adset_id text,
  status text DEFAULT 'PAUSED'::text NOT NULL,
  daily_budget_aed numeric DEFAULT 0 NOT NULL,
  started_at timestamp with time zone,
  is_demo boolean DEFAULT false NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ad_decision (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  decided_at timestamp with time zone DEFAULT now() NOT NULL,
  campaign_id text NOT NULL,
  action text NOT NULL,
  amount_aed numeric,
  rule_key text NOT NULL,
  reason text NOT NULL,
  evidence jsonb DEFAULT '{}'::jsonb NOT NULL,
  executed_at timestamp with time zone,
  execution_mode text,
  api_response jsonb,
  run_tag text
);

CREATE TABLE IF NOT EXISTS public.ad_spend_policy (
  policy_key text DEFAULT 'default'::text NOT NULL,
  daily_cap_aed numeric DEFAULT 200 NOT NULL,
  target_cpl_aed numeric,
  kill_multiplier numeric DEFAULT 3 NOT NULL,
  learning_phase_days integer DEFAULT 3 NOT NULL,
  learning_min_spend_aed numeric DEFAULT 100 NOT NULL,
  scale_step_pct numeric DEFAULT 20 NOT NULL,
  max_daily_per_campaign_aed numeric DEFAULT 100 NOT NULL,
  min_daily_per_campaign_aed numeric DEFAULT 20 NOT NULL,
  auto_activate boolean DEFAULT true NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  monthly_cap_aed numeric,
  month_spent_aed numeric DEFAULT 0 NOT NULL,
  month_label text DEFAULT to_char(now(), 'YYYY-MM'::text) NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ad_spend_reported (
  source_ref text NOT NULL,
  platform text NOT NULL,
  spend_date date NOT NULL,
  currency text NOT NULL,
  amount numeric(14,2) NOT NULL,
  amount_aed numeric(14,2),
  campaign_ref text,
  handoff_id bigint NOT NULL,
  revisions integer DEFAULT 1 NOT NULL,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.admin_mfa_sessions (
  session_id text NOT NULL,
  email text,
  verified_at timestamp with time zone DEFAULT now(),
  expires_at timestamp with time zone NOT NULL,
  ip text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.agent_action_kind_policy (
  kind text NOT NULL,
  policy text NOT NULL,
  note text,
  decided_at timestamp with time zone DEFAULT now() NOT NULL,
  authority_role text
);

CREATE TABLE IF NOT EXISTS public.agent_actions (
  id bigint DEFAULT nextval('agent_actions_id_seq'::regclass) NOT NULL,
  agent text NOT NULL,
  kind text NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  risk text DEFAULT 'low'::text NOT NULL,
  title text,
  recommendation text,
  detail jsonb DEFAULT '{}'::jsonb NOT NULL,
  target_table text,
  target_id text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  decided_at timestamp with time zone,
  decided_by text,
  confidence numeric,
  evidence jsonb,
  escalated boolean DEFAULT false NOT NULL,
  escalation_reason text,
  decision_log_id bigint,
  alternatives jsonb,
  assumptions jsonb,
  expected_impact text,
  cost text
);

CREATE TABLE IF NOT EXISTS public.agent_chats (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  agent_key text NOT NULL,
  role text NOT NULL,
  content text NOT NULL,
  created_by text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.agent_command_log (
  id bigint DEFAULT nextval('agent_command_log_id_seq'::regclass) NOT NULL,
  agent text,
  actor text,
  command text,
  did jsonb,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.agent_context_head (
  agent_key text NOT NULL,
  head text NOT NULL,
  head_md5 text NOT NULL,
  head_chars integer NOT NULL,
  built_at timestamp with time zone DEFAULT now() NOT NULL,
  changed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.agent_context_retrieval (
  id bigint DEFAULT nextval('agent_context_retrieval_id_seq'::regclass) NOT NULL,
  agent_key text NOT NULL,
  task_class text,
  category_key text,
  knowledge_ids text[] DEFAULT '{}'::text[] NOT NULL,
  knowledge_count integer DEFAULT 0 NOT NULL,
  budget_chars integer,
  chars_returned integer,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.agent_evals (
  id bigint DEFAULT nextval('agent_evals_id_seq'::regclass) NOT NULL,
  snapshot_at timestamp with time zone DEFAULT now(),
  window_days integer DEFAULT 30,
  kpis jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS public.agent_expectations (
  agent text NOT NULL,
  max_silence_hours numeric NOT NULL,
  on_demand boolean DEFAULT false NOT NULL,
  median_gap_hours numeric,
  runs_observed integer,
  note text,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  kind text,
  last_seen timestamp with time zone,
  silent boolean DEFAULT false NOT NULL
);

CREATE TABLE IF NOT EXISTS public.agent_governance (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  version integer NOT NULL,
  universal_rules jsonb NOT NULL,
  response_structure jsonb NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.agent_knowledge (
  id bigint DEFAULT nextval('agent_knowledge_id_seq'::regclass) NOT NULL,
  agent_key text NOT NULL,
  topic text,
  content text NOT NULL,
  priority integer DEFAULT 5,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  layer text DEFAULT 'profession'::text,
  source_ref text,
  owner_agent text,
  version integer DEFAULT 1 NOT NULL,
  confidence numeric,
  validation_status text DEFAULT 'unvalidated'::text NOT NULL,
  review_due date,
  supersedes_id bigint,
  valid_until date,
  supporting_evidence text,
  embedding_gte vector(384),
  search tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, ((((COALESCE(topic, ''::text) || ' '::text) || COALESCE(content, ''::text)) || ' '::text) || COALESCE(agent_key, ''::text)))) STORED
);

CREATE TABLE IF NOT EXISTS public.agent_memory (
  id bigint DEFAULT nextval('agent_memory_id_seq'::regclass) NOT NULL,
  agent_key text NOT NULL,
  kind text DEFAULT 'learning'::text,
  content text NOT NULL,
  source text,
  importance integer DEFAULT 5,
  created_at timestamp with time zone DEFAULT now(),
  horizon text DEFAULT 'short'::text
);

CREATE TABLE IF NOT EXISTS public.agent_pending_actions (
  token uuid DEFAULT gen_random_uuid() NOT NULL,
  created_by text,
  created_at timestamp with time zone DEFAULT now(),
  status text DEFAULT 'pending'::text,
  summary text,
  actions jsonb
);

CREATE TABLE IF NOT EXISTS public.agent_remediation (
  id bigint DEFAULT nextval('agent_remediation_id_seq'::regclass) NOT NULL,
  agent_key text NOT NULL,
  failure_class text NOT NULL,
  competency text NOT NULL,
  opened_at timestamp with time zone DEFAULT now() NOT NULL,
  closed_at timestamp with time zone,
  status text DEFAULT 'open'::text NOT NULL,
  attempts integer DEFAULT 0 NOT NULL,
  max_attempts integer DEFAULT 3 NOT NULL,
  cost_aed numeric DEFAULT 0 NOT NULL,
  max_cost_aed numeric DEFAULT 5 NOT NULL,
  baseline_score numeric,
  latest_score numeric,
  blocks_autonomy boolean DEFAULT true NOT NULL,
  detail jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS public.agent_reputation (
  agent_key text NOT NULL,
  correctness numeric,
  reliability numeric,
  cost_efficiency numeric,
  learning_speed numeric,
  collaboration numeric,
  score numeric,
  tier text,
  computed_at timestamp with time zone DEFAULT now() NOT NULL,
  decision_quality numeric,
  evidence jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS public.agent_runs (
  id bigint DEFAULT nextval('agent_runs_id_seq'::regclass) NOT NULL,
  agent text NOT NULL,
  started_at timestamp with time zone DEFAULT now() NOT NULL,
  finished_at timestamp with time zone,
  status text DEFAULT 'ok'::text,
  counts jsonb DEFAULT '{}'::jsonb,
  note text
);

CREATE TABLE IF NOT EXISTS public.agent_tool (
  tool_id text NOT NULL,
  purpose text NOT NULL,
  kind text DEFAULT 'read'::text NOT NULL,
  action_class text,
  impl_kind text DEFAULT 'rpc'::text NOT NULL,
  impl_target text NOT NULL,
  authorised_roles text[] DEFAULT '{}'::text[] NOT NULL,
  authorised_departments text[] DEFAULT '{}'::text[] NOT NULL,
  min_authority text DEFAULT 'advisory'::text NOT NULL,
  required_credential text,
  staging_available boolean DEFAULT true NOT NULL,
  production_available boolean DEFAULT false NOT NULL,
  input_schema jsonb DEFAULT '{"type": "object", "properties": {}, "additionalProperties": false}'::jsonb NOT NULL,
  output_schema jsonb DEFAULT '{"type": "object"}'::jsonb NOT NULL,
  timeout_seconds integer DEFAULT 15 NOT NULL,
  max_attempts integer DEFAULT 2 NOT NULL,
  backoff text DEFAULT 'exponential_2s'::text NOT NULL,
  failure_behaviour text DEFAULT 'fail_closed'::text NOT NULL,
  audit_behaviour text DEFAULT 'trace'::text NOT NULL,
  requires_current_data boolean DEFAULT true NOT NULL,
  stub_permitted boolean DEFAULT false NOT NULL,
  active boolean DEFAULT true NOT NULL,
  note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.agent_tool_call (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  correlation_id uuid NOT NULL,
  agent_key text NOT NULL,
  role_id text,
  tool_id text NOT NULL,
  args jsonb DEFAULT '{}'::jsonb NOT NULL,
  status text NOT NULL,
  result_hash text,
  result_rows integer,
  result_bytes integer,
  error text,
  attempt integer DEFAULT 1 NOT NULL,
  latency_ms integer,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.agent_training_attempt (
  id bigint DEFAULT nextval('agent_training_attempt_id_seq'::regclass) NOT NULL,
  agent_key text NOT NULL,
  case_id text NOT NULL,
  purpose text NOT NULL,
  failure_class text,
  competency text,
  score numeric,
  passed boolean,
  model text,
  input_tokens integer,
  output_tokens integer,
  cost_aed numeric,
  detail jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.agent_training_case (
  case_id text NOT NULL,
  generation text NOT NULL,
  package text NOT NULL,
  package_version text NOT NULL,
  scope_type text NOT NULL,
  scope_key text NOT NULL,
  case_family text NOT NULL,
  competency text,
  company_stage text,
  payload jsonb NOT NULL,
  checksum text NOT NULL,
  ingestion_run_id uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ai_constitution (
  id bigint DEFAULT nextval('ai_constitution_id_seq'::regclass) NOT NULL,
  version integer NOT NULL,
  body text NOT NULL,
  principles jsonb DEFAULT '[]'::jsonb NOT NULL,
  active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ai_cost_log (
  id bigint DEFAULT nextval('ai_cost_log_id_seq'::regclass) NOT NULL,
  occurred_at timestamp with time zone DEFAULT now() NOT NULL,
  fn text,
  dept_key text,
  agent_key text,
  task_class text,
  model_used text NOT NULL,
  model_selected_because text,
  tier text,
  prompt_tokens integer DEFAULT 0,
  output_tokens integer DEFAULT 0,
  cached boolean DEFAULT false NOT NULL,
  cache_hit_key text,
  latency_ms integer,
  cost_aed numeric,
  confidence numeric,
  could_be_cheaper boolean,
  cheaper_reason text,
  ok boolean DEFAULT true NOT NULL,
  cached_in_tokens integer DEFAULT 0,
  cache_write_tokens integer DEFAULT 0,
  generation_id text,
  cost_usd_reported numeric,
  seat text,
  seat_basis text,
  counterpart_model text,
  review_violation text,
  reviewer_tier text,
  prompt_hash text,
  e2e_run_tag text
);

CREATE TABLE IF NOT EXISTS public.ai_model_register (
  id bigint DEFAULT nextval('ai_model_register_id_seq'::regclass) NOT NULL,
  model text NOT NULL,
  provider text NOT NULL,
  approved boolean DEFAULT false NOT NULL,
  approved_for text[],
  forbidden_for text[],
  approved_by text,
  approved_at timestamp with time zone,
  review_due date,
  note text
);

CREATE TABLE IF NOT EXISTS public.ai_qa_log (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  email text,
  kind text,
  model text,
  input jsonb,
  output jsonb,
  flags jsonb
);

CREATE TABLE IF NOT EXISTS public.ai_quality_snapshots (
  at timestamp with time zone DEFAULT now() NOT NULL,
  agent text,
  override_pct numeric,
  actions_30d integer,
  id bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ai_rate_limit (
  bucket text NOT NULL,
  window_start timestamp with time zone DEFAULT now() NOT NULL,
  count integer DEFAULT 0 NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ai_trainer_snapshots (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
  kpis jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ai_usage (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  email text,
  kind text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.alert_signature (
  watcher text NOT NULL,
  signature text NOT NULL,
  first_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  last_alerted_at timestamp with time zone,
  seen_count bigint DEFAULT 1 NOT NULL,
  resolved_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.alert_watermark (
  watcher text NOT NULL,
  last_run_at timestamp with time zone DEFAULT now() NOT NULL,
  last_alert_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.allocation_change (
  id bigint DEFAULT nextval('allocation_change_id_seq'::regclass) NOT NULL,
  resource text NOT NULL,
  subject text NOT NULL,
  from_value numeric,
  to_value numeric,
  reason text NOT NULL,
  policy text NOT NULL,
  reverted boolean DEFAULT false NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ap_bills (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  bill_no text,
  vendor_id bigint NOT NULL,
  po_id bigint,
  bill_date date DEFAULT CURRENT_DATE NOT NULL,
  due_date date,
  currency text DEFAULT 'AED'::text NOT NULL,
  subtotal numeric(18,2) DEFAULT 0 NOT NULL,
  vat_amount numeric(18,2) DEFAULT 0 NOT NULL,
  total numeric(18,2) DEFAULT 0 NOT NULL,
  amount_paid numeric(18,2) DEFAULT 0 NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  gl_journal_id bigint,
  pay_journal_id bigint,
  created_by text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.app_blocked_domains (
  domain text NOT NULL,
  reason text DEFAULT 'disposable'::text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.app_secrets (
  key text NOT NULL,
  value text NOT NULL,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.arabic_compare_waiter (
  inquiry_id text NOT NULL,
  texts text[] NOT NULL,
  attempts integer DEFAULT 0 NOT NULL,
  last_tried_at timestamp with time zone,
  last_offered_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.arabic_document_waiter (
  quote_id text NOT NULL,
  texts text[] NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  attempts integer DEFAULT 0 NOT NULL,
  last_tried_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.arabic_outbound_hold (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  texts text[] NOT NULL,
  delivery jsonb NOT NULL,
  status text DEFAULT 'held'::text NOT NULL,
  result jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  sent_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.arabic_translation (
  source_md5 text NOT NULL,
  source text NOT NULL,
  arabic text NOT NULL,
  held_id bigint,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.artifact_platform_spec (
  platform text NOT NULL,
  kind text NOT NULL,
  min_width integer,
  min_height integer,
  aspect_min numeric,
  aspect_max numeric,
  max_bytes integer,
  allowed_mime text[] DEFAULT '{image/png,image/jpeg}'::text[] NOT NULL,
  safe_zone_pct numeric DEFAULT 0.05 NOT NULL,
  min_duration_s numeric,
  max_duration_s numeric
);

CREATE TABLE IF NOT EXISTS public.artifact_review (
  id bigint DEFAULT nextval('artifact_review_id_seq'::regclass) NOT NULL,
  subject_type text NOT NULL,
  subject_id text NOT NULL,
  artifact_url text NOT NULL,
  artifact_sha256 text NOT NULL,
  revision integer DEFAULT 1 NOT NULL,
  bytes integer,
  mime text,
  width integer,
  height integer,
  aspect_ratio numeric,
  author_agent text,
  reviewer_agent text NOT NULL,
  deterministic jsonb DEFAULT '{}'::jsonb NOT NULL,
  vision jsonb DEFAULT '{}'::jsonb NOT NULL,
  verdict text NOT NULL,
  failures text[] DEFAULT '{}'::text[] NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.assistant_logs (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  message text,
  reply text,
  matched_ids bigint[],
  user_agent text,
  created_at timestamp with time zone DEFAULT now(),
  audience text,
  path text,
  seat text,
  answered boolean,
  gap_task_id bigint,
  reply_attempts jsonb,
  conv_id text,
  e2e_run_tag text
);

CREATE TABLE IF NOT EXISTS public.autonomy_control_audit (
  id bigint DEFAULT nextval('autonomy_control_audit_id_seq'::regclass) NOT NULL,
  at timestamp with time zone DEFAULT now() NOT NULL,
  object text NOT NULL,
  op text NOT NULL,
  direction text NOT NULL,
  old_value text,
  new_value text,
  reason text,
  db_user text DEFAULT CURRENT_USER NOT NULL
);

CREATE TABLE IF NOT EXISTS public.autonomy_policy (
  id integer DEFAULT 1 NOT NULL,
  revision text NOT NULL,
  final_internal_authority text NOT NULL,
  founder_approval_required boolean NOT NULL,
  founder_escalation_allowed boolean NOT NULL,
  constitution_note text NOT NULL,
  effective_from timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.backup_prune_log (
  id bigint DEFAULT nextval('backup_prune_log_id_seq'::regclass) NOT NULL,
  decided_at timestamp with time zone DEFAULT now() NOT NULL,
  decided_for date NOT NULL,
  mode text NOT NULL,
  day date NOT NULL,
  origin text NOT NULL,
  kind text NOT NULL,
  day_status text,
  reason text NOT NULL,
  objects integer,
  bytes bigint,
  dropbox_files integer,
  objects_removed integer DEFAULT 0 NOT NULL,
  storage_attempts integer DEFAULT 0 NOT NULL,
  storage_error text,
  storage_deleted_at timestamp with time zone,
  dropbox_done_at timestamp with time zone,
  cancelled_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.bank_line_owner_ruling (
  line_id bigint NOT NULL,
  ruling text NOT NULL,
  founder_instruction_id bigint,
  noted_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.bank_reference_code (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  bank text NOT NULL,
  code_prefix text NOT NULL,
  code_suffix text,
  sign smallint NOT NULL,
  kind text,
  gl_account text,
  meaning text NOT NULL,
  added_by text DEFAULT 'accountant'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.bank_statement_intake (
  source_ref text NOT NULL,
  account text DEFAULT 'mashreq'::text NOT NULL,
  statement_month date,
  state text NOT NULL,
  lines integer DEFAULT 0 NOT NULL,
  doc_path text,
  note text,
  received_at timestamp with time zone DEFAULT now() NOT NULL,
  closing_balance_aed numeric(14,2),
  balance_on date
);

CREATE TABLE IF NOT EXISTS public.bank_statement_line (
  id bigint DEFAULT nextval('bank_statement_line_id_seq'::regclass) NOT NULL,
  account text DEFAULT 'mashreq'::text NOT NULL,
  source_ref text NOT NULL,
  value_date date NOT NULL,
  description text NOT NULL,
  amount_aed numeric(14,2) NOT NULL,
  reference text,
  line_hash text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  kind text,
  kind_by text,
  kind_at timestamp with time zone,
  kind_tried_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.blog_posts (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  slug text NOT NULL,
  title text NOT NULL,
  excerpt text,
  meta_desc text,
  body_html text NOT NULL,
  author text DEFAULT 'QuotesDone'::text,
  category text,
  published boolean DEFAULT true,
  published_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  sort integer DEFAULT 0
);

CREATE TABLE IF NOT EXISTS public.board_advisor (
  advisor_key text NOT NULL,
  name text NOT NULL,
  lens text NOT NULL,
  asks text NOT NULL,
  weight numeric DEFAULT 1.0 NOT NULL,
  active boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.board_opinion (
  id bigint DEFAULT nextval('board_opinion_id_seq'::regclass) NOT NULL,
  subject text NOT NULL,
  subject_ref text,
  advisor_key text NOT NULL,
  recommendation text NOT NULL,
  rationale text NOT NULL,
  confidence numeric,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.board_reports (
  id bigint DEFAULT nextval('board_reports_id_seq'::regclass) NOT NULL,
  week_start date,
  title text,
  body text,
  kpis jsonb,
  created_at timestamp with time zone DEFAULT now(),
  report_type text DEFAULT 'weekly'::text,
  pdf_path text,
  pdf_generated_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.boq_fixture (
  id bigint DEFAULT nextval('boq_fixture_id_seq'::regclass) NOT NULL,
  document_id bigint NOT NULL,
  label text NOT NULL,
  expect_doors integer,
  expect_windows integer,
  expect_rooms_sqm numeric,
  expect_total_sqm numeric,
  tolerance_pct numeric DEFAULT 10 NOT NULL,
  source_note text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.boq_fixture_run (
  id bigint DEFAULT nextval('boq_fixture_run_id_seq'::regclass) NOT NULL,
  fixture_id bigint NOT NULL,
  ran_at timestamp with time zone DEFAULT now() NOT NULL,
  ok boolean NOT NULL,
  checked integer DEFAULT 0 NOT NULL,
  matched integer DEFAULT 0 NOT NULL,
  score_pct numeric,
  actual jsonb,
  detail jsonb,
  error text
);

CREATE TABLE IF NOT EXISTS public.boq_section_reading (
  section_key text NOT NULL,
  section text NOT NULL,
  reading text NOT NULL,
  reasoned_by text DEFAULT 'reasoning'::text NOT NULL,
  held_id bigint,
  reasoned_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.brand_assets (
  id bigint DEFAULT nextval('brand_assets_id_seq'::regclass) NOT NULL,
  kind text NOT NULL,
  platform text,
  filename text NOT NULL,
  url text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  bucket text,
  path text,
  folder text,
  bytes integer,
  sha256 text,
  width integer,
  height integer,
  usage text
);

CREATE TABLE IF NOT EXISTS public.budget_lines (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  budget_id bigint NOT NULL,
  account_code text NOT NULL,
  period_month date NOT NULL,
  amount numeric(18,2) DEFAULT 0 NOT NULL
);

CREATE TABLE IF NOT EXISTS public.budgets (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  name text NOT NULL,
  fiscal_year integer NOT NULL,
  status text DEFAULT 'active'::text NOT NULL,
  created_by text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.business_rules (
  id bigint DEFAULT nextval('business_rules_id_seq'::regclass) NOT NULL,
  name text,
  category text,
  priority integer DEFAULT 100,
  when_json jsonb NOT NULL,
  then_json jsonb NOT NULL,
  active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.cad_read_jobs (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  customer_id uuid,
  owner_email text,
  source_path text NOT NULL,
  file_name text DEFAULT ''::text NOT NULL,
  mime text DEFAULT ''::text NOT NULL,
  bytes integer,
  why text NOT NULL,
  boq_in jsonb,
  status text DEFAULT 'queued'::text NOT NULL,
  attempts integer DEFAULT 0 NOT NULL,
  claimed_at timestamp with time zone,
  finished_at timestamp with time zone,
  result jsonb,
  error text
);

CREATE TABLE IF NOT EXISTS public.canon_eval_questions (
  id bigint DEFAULT nextval('canon_eval_questions_id_seq'::regclass) NOT NULL,
  category text,
  question text NOT NULL,
  reference text,
  active boolean DEFAULT true,
  layer text DEFAULT 'company'::text,
  agent_key text
);

CREATE TABLE IF NOT EXISTS public.canon_eval_runs (
  id bigint DEFAULT nextval('canon_eval_runs_id_seq'::regclass) NOT NULL,
  run_at timestamp with time zone DEFAULT now(),
  agent text,
  asked integer,
  passed integer,
  score_pct numeric,
  gaps jsonb
);

CREATE TABLE IF NOT EXISTS public.catalog_category_domain (
  catalog_slug text NOT NULL,
  domain_slug text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.catalog_domains (
  slug text NOT NULL,
  num integer,
  name text NOT NULL,
  sort integer,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.catalog_subcategories (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  domain_slug text,
  name text NOT NULL,
  slug text,
  agent_slug text,
  sort integer
);

CREATE TABLE IF NOT EXISTS public.catalog_supplier_categories (
  slug text NOT NULL,
  num integer,
  name text NOT NULL,
  regulated boolean DEFAULT false,
  sort integer,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.category_agent_map (
  catalog_slug text NOT NULL,
  agent_slug text,
  status text DEFAULT 'needs_agent'::text NOT NULL,
  confidence text DEFAULT 'high'::text NOT NULL,
  note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.category_agents (
  slug text NOT NULL,
  name text NOT NULL,
  emoji text DEFAULT '🛠️'::text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  persona text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  requires_regulation boolean DEFAULT false NOT NULL,
  agent_class text,
  folded_into text,
  folded_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.category_keyword (
  id bigint DEFAULT nextval('category_keyword_id_seq'::regclass) NOT NULL,
  slug text NOT NULL,
  pattern text NOT NULL,
  weight integer DEFAULT 2 NOT NULL,
  negative boolean DEFAULT false NOT NULL,
  note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.category_quote_specs (
  id bigint DEFAULT nextval('category_quote_specs_id_seq'::regclass) NOT NULL,
  spec_group text NOT NULL,
  aspect text NOT NULL,
  label text NOT NULL,
  match_regex text NOT NULL,
  mandatory boolean DEFAULT true NOT NULL,
  note text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.category_route_map (
  category text NOT NULL,
  catalog_num integer NOT NULL,
  note text,
  decided_by text DEFAULT 'v3_runtime_build'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.category_specs (
  category text NOT NULL,
  label text,
  fields jsonb NOT NULL,
  updated_at timestamp with time zone DEFAULT now(),
  supplier_requirements jsonb,
  compliance_checklist jsonb,
  reqs_updated_at timestamp with time zone,
  quote_spec_group text
);

CREATE TABLE IF NOT EXISTS public.ceo_approval (
  decision_id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  subject_kind text NOT NULL,
  subject_id text NOT NULL,
  decision text NOT NULL,
  decided_by text NOT NULL,
  amount_aed numeric(12,2),
  rationale text NOT NULL,
  decided_at timestamp with time zone DEFAULT now() NOT NULL,
  superseded_by bigint
);

CREATE TABLE IF NOT EXISTS public.ceo_command (
  command_id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  received_at timestamp with time zone DEFAULT now() NOT NULL,
  channel text NOT NULL,
  from_identity text NOT NULL,
  body text NOT NULL,
  intent_id text DEFAULT 'ambiguous'::text NOT NULL,
  matched_rule bigint,
  state text DEFAULT 'received'::text NOT NULL,
  outcome text,
  closed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.ceo_command_intent (
  intent_id text NOT NULL,
  meaning text NOT NULL,
  needs_work boolean DEFAULT true NOT NULL,
  added_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_command_rule (
  rule_id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  pattern text NOT NULL,
  intent_id text NOT NULL,
  rank integer DEFAULT 100 NOT NULL,
  note text
);

CREATE TABLE IF NOT EXISTS public.ceo_command_state (
  state text NOT NULL,
  is_terminal boolean DEFAULT false NOT NULL,
  meaning text NOT NULL,
  added_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_command_transition (
  from_state text NOT NULL,
  to_state text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_company_stage (
  stage text NOT NULL,
  stage_order integer NOT NULL,
  meaning text NOT NULL,
  exit_measure text,
  exit_threshold numeric,
  exit_meaning text,
  constraint_scope text[] NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_company_stage_log (
  id bigint DEFAULT nextval('ceo_company_stage_log_id_seq'::regclass) NOT NULL,
  stage text NOT NULL,
  entered_at timestamp with time zone DEFAULT now() NOT NULL,
  left_at timestamp with time zone,
  exit_reading jsonb
);

CREATE TABLE IF NOT EXISTS public.ceo_constraint_lever (
  stage text NOT NULL,
  owner_seat text NOT NULL,
  proposal text NOT NULL,
  measure text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_daily_digest (
  id bigint DEFAULT nextval('ceo_daily_digest_id_seq'::regclass) NOT NULL,
  company_key text DEFAULT 'quotesdone'::text NOT NULL,
  local_date date NOT NULL,
  local_timezone text DEFAULT 'Asia/Dubai'::text NOT NULL,
  report_key text NOT NULL,
  revision integer DEFAULT 1 NOT NULL,
  revision_note text,
  subject text,
  body text,
  figures jsonb DEFAULT '{}'::jsonb NOT NULL,
  status text DEFAULT 'generated'::text NOT NULL,
  generated_at timestamp with time zone DEFAULT now() NOT NULL,
  submitted_at timestamp with time zone,
  delivered_at timestamp with time zone,
  notification_id bigint,
  command_center_id uuid,
  delivery_attempts integer DEFAULT 0 NOT NULL,
  last_delivery_error text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  pdf_bucket text,
  pdf_path text
);

CREATE TABLE IF NOT EXISTS public.ceo_day (
  day date NOT NULL,
  facts jsonb NOT NULL,
  priorities jsonb NOT NULL,
  matters text[] DEFAULT '{}'::text[] NOT NULL,
  note_handoff_id bigint,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_decision (
  decision_key text NOT NULL,
  domain text NOT NULL,
  decision text NOT NULL,
  trigger_condition text NOT NULL,
  measure text NOT NULL,
  measure_sql text,
  authority text NOT NULL,
  evidence_required text NOT NULL,
  cadence text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_decision_log (
  id bigint DEFAULT nextval('ceo_decision_log_id_seq'::regclass) NOT NULL,
  decision_key text NOT NULL,
  decided_at timestamp with time zone DEFAULT now() NOT NULL,
  the_decision text NOT NULL,
  evidence jsonb NOT NULL,
  reading_before text,
  reading_after text,
  escalated_to_founder boolean DEFAULT false NOT NULL,
  founder_answer text,
  outcome text DEFAULT 'decided'::text NOT NULL,
  dedupe_key text
);

CREATE TABLE IF NOT EXISTS public.ceo_decision_round (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  path text NOT NULL,
  item_key text NOT NULL,
  originator_seat text NOT NULL,
  generation integer DEFAULT 1 NOT NULL,
  round integer DEFAULT 1 NOT NULL,
  decision text NOT NULL,
  reasons text NOT NULL,
  version jsonb DEFAULT '{}'::jsonb NOT NULL,
  source_table text,
  source_id text,
  revise_handoff_ids bigint[] DEFAULT '{}'::bigint[] NOT NULL,
  decided_by text DEFAULT 'ceo'::text NOT NULL,
  decided_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_directive (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  seat text NOT NULL,
  source_kind text NOT NULL,
  source_ref text NOT NULL,
  instruction text NOT NULL,
  done_when text NOT NULL,
  done_sql text NOT NULL,
  deadline timestamp with time zone NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  escalated_from bigint,
  evidence jsonb DEFAULT '{}'::jsonb NOT NULL,
  issued_at timestamp with time zone DEFAULT now() NOT NULL,
  closed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.ceo_experiment (
  id bigint DEFAULT nextval('ceo_experiment_id_seq'::regclass) NOT NULL,
  key text NOT NULL,
  proposed_by text NOT NULL,
  owner_seat text,
  hypothesis text NOT NULL,
  metric_key text NOT NULL,
  metric_definition text NOT NULL,
  baseline numeric,
  baseline_note text NOT NULL,
  target numeric NOT NULL,
  direction text DEFAULT 'min'::text NOT NULL,
  approach text NOT NULL,
  starts_on date NOT NULL,
  days integer NOT NULL,
  ends_on date,
  status text DEFAULT 'proposed'::text NOT NULL,
  iteration integer DEFAULT 1 NOT NULL,
  approval_held_id bigint,
  approval jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  closed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.ceo_experiment_verdict (
  experiment_id bigint NOT NULL,
  week date NOT NULL,
  iteration integer NOT NULL,
  reading numeric,
  reading_from timestamp with time zone NOT NULL,
  reading_to timestamp with time zone NOT NULL,
  held_id bigint,
  decision text,
  fields jsonb,
  reasoning text,
  model text,
  decided_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_growth_action (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  decided_on date NOT NULL,
  power text NOT NULL,
  subject text NOT NULL,
  before_value text,
  after_value text,
  reason text NOT NULL,
  applied boolean DEFAULT false NOT NULL,
  baseline jsonb DEFAULT '{}'::jsonb NOT NULL,
  review_on date,
  effect jsonb,
  verdict text DEFAULT 'pending'::text NOT NULL,
  reviewed_at timestamp with time zone,
  dedupe_key text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_identity (
  identity text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  note text,
  added_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_improvement (
  id bigint DEFAULT nextval('ceo_improvement_id_seq'::regclass) NOT NULL,
  source_kind text NOT NULL,
  source_ref text NOT NULL,
  seat text NOT NULL,
  proposal text NOT NULL,
  evidence jsonb DEFAULT '{}'::jsonb NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  task_id bigint,
  handoff_id bigint,
  done_evidence text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  closed_at timestamp with time zone,
  due_on date,
  close_check text,
  escalations integer DEFAULT 0 NOT NULL,
  last_escalated_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.ceo_invite_trade_priority (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  trade text NOT NULL,
  reason text NOT NULL,
  set_at timestamp with time zone DEFAULT now() NOT NULL,
  cleared_at timestamp with time zone,
  cleared_why text
);

CREATE TABLE IF NOT EXISTS public.ceo_knowledge (
  record_id text NOT NULL,
  schema_version text NOT NULL,
  record_version text NOT NULL,
  record_kind text NOT NULL,
  parent_id text,
  title text NOT NULL,
  domain text NOT NULL,
  tags text[] DEFAULT '{}'::text[] NOT NULL,
  language text DEFAULT 'en'::text NOT NULL,
  company_scope text NOT NULL,
  audience text[] DEFAULT '{}'::text[] NOT NULL,
  created_on date,
  review_status text NOT NULL,
  content_origin text NOT NULL,
  authority_effect text NOT NULL,
  runtime_use text NOT NULL,
  runtime_index_eligible boolean NOT NULL,
  external_execution_enabled boolean NOT NULL,
  contains_synthetic_example boolean NOT NULL,
  requires_current_verification boolean NOT NULL,
  verification_note text,
  source_ids text[] DEFAULT '{}'::text[] NOT NULL,
  source_support text,
  related_modules text[] DEFAULT '{}'::text[] NOT NULL,
  source_path text,
  body text NOT NULL,
  body_sha256 text,
  extra jsonb DEFAULT '{}'::jsonb NOT NULL,
  pack_fingerprint text NOT NULL,
  imported_at timestamp with time zone DEFAULT now() NOT NULL,
  search tsvector,
  embedding_gte vector(384)
);

CREATE TABLE IF NOT EXISTS public.ceo_launch_gate (
  week date NOT NULL,
  trades_total integer NOT NULL,
  trades_ready integer NOT NULL,
  coverage_pct numeric NOT NULL,
  widest_gaps jsonb DEFAULT '[]'::jsonb NOT NULL,
  measured_at timestamp with time zone,
  verdict text NOT NULL,
  decision text,
  decided_on date,
  founder_notice bigint,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_mandate (
  clause_key text NOT NULL,
  kind text NOT NULL,
  statement text NOT NULL,
  value numeric,
  unit text,
  source text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_market_report (
  month date NOT NULL,
  audience text DEFAULT 'internal'::text NOT NULL,
  facts jsonb NOT NULL,
  binding jsonb,
  body text NOT NULL,
  named_check text,
  improvement_id bigint,
  closed_last jsonb,
  held_id bigint,
  notify jsonb,
  include_demo boolean DEFAULT false NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_month_close (
  month date NOT NULL,
  seat text NOT NULL,
  facts jsonb NOT NULL,
  verdict text NOT NULL,
  closed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_month_report (
  month date NOT NULL,
  facts jsonb NOT NULL,
  body text NOT NULL,
  handoff_id bigint,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_plan (
  id bigint DEFAULT nextval('ceo_plan_id_seq'::regclass) NOT NULL,
  plan_date date NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  funnel jsonb NOT NULL,
  month_target jsonb,
  stage text NOT NULL,
  constraint_since date NOT NULL,
  decision jsonb NOT NULL,
  directives jsonb DEFAULT '[]'::jsonb NOT NULL,
  founder_line text,
  judgement jsonb DEFAULT '{}'::jsonb NOT NULL,
  decided_by text DEFAULT 'plan_c_code'::text NOT NULL,
  company_stage text GENERATED ALWAYS AS (((funnel -> 'company_stage'::text) ->> 'stage'::text)) STORED
);

CREATE TABLE IF NOT EXISTS public.ceo_plan_action (
  id bigint DEFAULT nextval('ceo_plan_action_id_seq'::regclass) NOT NULL,
  seat text NOT NULL,
  from_month date NOT NULL,
  to_month date NOT NULL,
  action text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_plan_month (
  month date NOT NULL,
  invites integer NOT NULL,
  registered integer NOT NULL,
  verified integer NOT NULL,
  inquiries integer NOT NULL,
  reveals integer NOT NULL,
  fee_aed numeric(12,2) NOT NULL,
  basis text NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_pricing_evidence (
  week date NOT NULL,
  requests_90d integer NOT NULL,
  quoted_requests_90d integer NOT NULL,
  quotes_90d integer NOT NULL,
  reveals_90d integer NOT NULL,
  reveal_conversion_pct numeric,
  avg_quote_aed numeric,
  avg_reveal_fee_aed numeric,
  fee_pct_of_quote numeric,
  refunds_90d integer NOT NULL,
  refund_rate_pct numeric,
  supplier_fee_paying integer NOT NULL,
  ready boolean NOT NULL,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_refund_decision_metric (
  week date NOT NULL,
  decisions integer NOT NULL,
  approved integer NOT NULL,
  approval_rate_pct numeric,
  median_hours_to_decide numeric,
  overturned integer NOT NULL,
  overturn_rate_pct numeric,
  awaiting_ceo_over_2d integer NOT NULL,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_review (
  kind text NOT NULL,
  period date NOT NULL,
  facts jsonb DEFAULT '{}'::jsonb NOT NULL,
  held_id bigint,
  decision text,
  fields jsonb,
  reasoning text,
  model text,
  review jsonb,
  founder_notice jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  decided_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.ceo_seat_audit (
  quarter date NOT NULL,
  seat text NOT NULL,
  measures jsonb NOT NULL,
  shortfalls text[] DEFAULT '{}'::text[] NOT NULL,
  below_bar boolean NOT NULL,
  improvement_id bigint,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_seat_directive (
  month date NOT NULL,
  seat text NOT NULL,
  targets jsonb NOT NULL,
  actions text[] NOT NULL,
  handoff_id bigint,
  status text DEFAULT 'issued'::text NOT NULL,
  outcome jsonb,
  issued_at timestamp with time zone DEFAULT now() NOT NULL,
  closed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.ceo_standing_grant (
  grant_key text NOT NULL,
  grantee_role_id text NOT NULL,
  action_class text NOT NULL,
  scope_note text NOT NULL,
  limit_note text,
  max_amount_aed numeric,
  issued_by text DEFAULT 'ceo'::text NOT NULL,
  issued_at timestamp with time zone DEFAULT now() NOT NULL,
  expires_at timestamp with time zone,
  active boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_strategy_memo (
  month date NOT NULL,
  facts jsonb NOT NULL,
  bet jsonb NOT NULL,
  grading jsonb NOT NULL,
  wording_source text NOT NULL,
  body text NOT NULL,
  notify jsonb,
  include_demo boolean DEFAULT false NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_supplier_channel (
  channel text NOT NULL,
  owner_seat text NOT NULL,
  switch_key text,
  ceo_may_open boolean DEFAULT false NOT NULL,
  rule text NOT NULL,
  access_needed text,
  state text DEFAULT 'not_measured'::text NOT NULL,
  state_why text,
  measured jsonb DEFAULT '{}'::jsonb NOT NULL,
  measured_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.ceo_supplier_funnel_daily (
  day date NOT NULL,
  channel text NOT NULL,
  sent integer DEFAULT 0 NOT NULL,
  delivered integer DEFAULT 0 NOT NULL,
  replied integer DEFAULT 0 NOT NULL,
  started integer DEFAULT 0 NOT NULL,
  submitted integer DEFAULT 0 NOT NULL,
  approved integer DEFAULT 0 NOT NULL,
  measured_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_supplier_goal (
  goal text NOT NULL,
  target_low integer NOT NULL,
  target_high integer NOT NULL,
  due_on date NOT NULL,
  counts_as text NOT NULL,
  ruling text NOT NULL,
  set_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_task (
  task_id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  command_id bigint,
  title text NOT NULL,
  detail text,
  state text DEFAULT 'open'::text NOT NULL,
  blocked_reason text,
  evidence text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  closed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.ceo_task_state (
  state text NOT NULL,
  is_terminal boolean DEFAULT false NOT NULL,
  meaning text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_weekly_report (
  id bigint DEFAULT nextval('ceo_weekly_report_id_seq'::regclass) NOT NULL,
  company_key text DEFAULT 'quotesdone'::text NOT NULL,
  iso_year integer NOT NULL,
  iso_week integer NOT NULL,
  week_start date NOT NULL,
  week_end date NOT NULL,
  report_key text NOT NULL,
  revision integer DEFAULT 1 NOT NULL,
  subject text,
  body text,
  figures jsonb DEFAULT '{}'::jsonb NOT NULL,
  constraint_now jsonb,
  proposals jsonb DEFAULT '[]'::jsonb NOT NULL,
  status text DEFAULT 'generated'::text NOT NULL,
  generated_at timestamp with time zone DEFAULT now() NOT NULL,
  founder_submitted_at timestamp with time zone,
  notification_id bigint,
  delivery_attempts integer DEFAULT 0 NOT NULL,
  last_delivery_error text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  pdf_blocks jsonb,
  pdf_bucket text,
  pdf_path text,
  pdf_url text,
  pdf_bytes integer,
  pdf_error text,
  pdf_generated_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.ceo_weekly_review (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  week date NOT NULL,
  targets jsonb NOT NULL,
  opened bigint[] DEFAULT '{}'::bigint[] NOT NULL,
  escalated bigint[] DEFAULT '{}'::bigint[] NOT NULL,
  closed bigint[] DEFAULT '{}'::bigint[] NOT NULL,
  pdf_blocks jsonb,
  pdf_bucket text,
  pdf_path text,
  pdf_url text,
  pdf_bytes integer,
  pdf_error text,
  notification_id bigint,
  notify jsonb,
  delivered_at timestamp with time zone,
  attempts integer DEFAULT 0 NOT NULL,
  last_error text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_year_plan (
  month date NOT NULL,
  verified integer NOT NULL,
  verified_added integer NOT NULL,
  paying integer DEFAULT 0 NOT NULL,
  subscription_aed numeric DEFAULT 0 NOT NULL,
  requests integer NOT NULL,
  quotes integer NOT NULL,
  reveals integer NOT NULL,
  fee_aed numeric NOT NULL,
  fee_cum_aed numeric NOT NULL,
  business_accounts integer NOT NULL,
  cost_ceiling_aed numeric NOT NULL,
  basis text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ceo_year_plan_milestone (
  due date NOT NULL,
  verified integer NOT NULL,
  basis text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.challenge_heuristic (
  id bigint DEFAULT nextval('challenge_heuristic_id_seq'::regclass) NOT NULL,
  pattern text NOT NULL,
  rank_touched integer NOT NULL,
  principle text NOT NULL,
  concern text NOT NULL,
  alternative text,
  active boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.challenge_record (
  id bigint DEFAULT nextval('challenge_record_id_seq'::regclass) NOT NULL,
  proposal text NOT NULL,
  proposed_by text DEFAULT 'founder'::text NOT NULL,
  challenged_by text NOT NULL,
  stance text NOT NULL,
  confidence numeric,
  reasoning text NOT NULL,
  violates_rank integer,
  violates_principle text,
  evidence jsonb DEFAULT '[]'::jsonb,
  alternatives jsonb DEFAULT '[]'::jsonb,
  founder_response text,
  responded_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.channel_directive (
  id bigint DEFAULT nextval('channel_directive_id_seq'::regclass) NOT NULL,
  actor_type text NOT NULL,
  actor_id bigint,
  actor_phone text,
  channel text DEFAULT 'whatsapp'::text NOT NULL,
  inbound text,
  field text,
  target_id text,
  old_value text,
  new_value text,
  applied boolean DEFAULT false NOT NULL,
  refusal text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.charge_audit (
  transaction_id uuid NOT NULL,
  audited_at timestamp with time zone DEFAULT now() NOT NULL,
  livemode boolean NOT NULL,
  basis text NOT NULL,
  quote_amount numeric(14,2) NOT NULL,
  rate numeric(8,5) NOT NULL,
  expected_total numeric(14,2) NOT NULL,
  expected_processing numeric(14,2) NOT NULL,
  actual_total numeric(14,2) NOT NULL,
  actual_fee_fils bigint,
  diff_aed numeric(14,2) NOT NULL,
  shortfall_aed numeric(14,2),
  evidence jsonb DEFAULT '{}'::jsonb NOT NULL,
  resolved_at timestamp with time zone,
  resolution text
);

CREATE TABLE IF NOT EXISTS public.chat_threads (
  inquiry_id text NOT NULL,
  supplier_id bigint NOT NULL,
  customer_id uuid,
  status text DEFAULT 'requested'::text NOT NULL,
  reason text,
  requested_by text,
  category text,
  strikes integer DEFAULT 0 NOT NULL,
  opened_at timestamp with time zone,
  closed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  project_id uuid
);

CREATE TABLE IF NOT EXISTS public.chat_violations (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  inquiry_id text,
  supplier_id bigint,
  sender_role text,
  sender_email text,
  matched text,
  body text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.collaboration_rule (
  id bigint DEFAULT nextval('collaboration_rule_id_seq'::regclass) NOT NULL,
  situation text NOT NULL,
  owner_dept text NOT NULL,
  must_involve text[] DEFAULT '{}'::text[] NOT NULL,
  must_review text[] DEFAULT '{}'::text[] NOT NULL,
  may_challenge text[] DEFAULT '{}'::text[] NOT NULL,
  reason text NOT NULL,
  blocking boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.collections_config (
  id integer DEFAULT 1 NOT NULL,
  interest_pa numeric DEFAULT 0.09 NOT NULL,
  admin_fee numeric DEFAULT 250 NOT NULL,
  escalate_working_days integer DEFAULT 30 NOT NULL,
  reminder_max integer DEFAULT 3 NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.company_brand (
  key text NOT NULL,
  "group" text NOT NULL,
  value text NOT NULL,
  note text,
  sort integer DEFAULT 100 NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.company_calendar (
  id bigint DEFAULT nextval('company_calendar_id_seq'::regclass) NOT NULL,
  event_name text NOT NULL,
  kind text NOT NULL,
  starts_on date,
  ends_on date,
  approximate boolean DEFAULT false NOT NULL,
  recurrence text,
  affects text NOT NULL,
  action text,
  owner_dept text,
  source_url text,
  verified_at date DEFAULT CURRENT_DATE
);

CREATE TABLE IF NOT EXISTS public.company_charter (
  id bigint DEFAULT nextval('company_charter_id_seq'::regclass) NOT NULL,
  version integer NOT NULL,
  active boolean DEFAULT true NOT NULL,
  superseded_by bigint,
  mission text NOT NULL,
  business_model text NOT NULL,
  customers text NOT NULL,
  value_proposition text NOT NULL,
  strategic_boundaries text NOT NULL,
  currency text DEFAULT 'AED'::text NOT NULL,
  timezone text DEFAULT 'Asia/Dubai'::text NOT NULL,
  monthly_spend_cap numeric,
  min_cash_reserve numeric,
  risk_restrictions text,
  reserved_matters text[] DEFAULT '{}'::text[] NOT NULL,
  escalation_rules text,
  operating_calendar jsonb DEFAULT '{}'::jsonb NOT NULL,
  reporting_preferences jsonb DEFAULT '{}'::jsonb NOT NULL,
  authored_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  note text
);

CREATE TABLE IF NOT EXISTS public.company_constitution (
  article_no integer NOT NULL,
  section text NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  binding text DEFAULT 'all_employees'::text NOT NULL,
  version text DEFAULT 'v1'::text NOT NULL,
  effective_from date DEFAULT CURRENT_DATE NOT NULL,
  supersedes integer
);

CREATE TABLE IF NOT EXISTS public.company_event (
  id bigint DEFAULT nextval('company_event_id_seq'::regclass) NOT NULL,
  event_type text NOT NULL,
  entity_type text,
  entity_id text,
  actor text,
  payload jsonb,
  occurred_at timestamp with time zone DEFAULT now() NOT NULL,
  correlation_id uuid DEFAULT COALESCE((NULLIF(current_setting('app.correlation_id'::text, true), ''::text))::uuid, gen_random_uuid()),
  causation_id bigint DEFAULT (NULLIF(current_setting('app.causation_event_id'::text, true), ''::text))::bigint,
  event_version integer DEFAULT 1 NOT NULL,
  dedupe_key text
);

CREATE TABLE IF NOT EXISTS public.company_faq (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  section text DEFAULT 'General'::text NOT NULL,
  sort integer DEFAULT 0 NOT NULL,
  question text NOT NULL,
  answer text,
  audience text DEFAULT 'all'::text NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  source_note text,
  tags text[] DEFAULT '{}'::text[],
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  approved_at timestamp with time zone,
  approved_by text,
  public boolean DEFAULT false NOT NULL,
  embedding_gte vector(384),
  language text DEFAULT 'en'::text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.company_faq_embed_inflight (
  request_id bigint NOT NULL,
  faq_id bigint NOT NULL,
  text_md5 text NOT NULL,
  queued_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.company_financial_stance (
  id integer DEFAULT 1 NOT NULL,
  is_profitable boolean DEFAULT false NOT NULL,
  budget_mode text DEFAULT 'unlimited_until_profitable'::text NOT NULL,
  policy_text text NOT NULL,
  decided_on date NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.company_goals (
  key text NOT NULL,
  goal text NOT NULL,
  metric text NOT NULL,
  target_value numeric,
  unit text,
  period text DEFAULT 'annual'::text NOT NULL,
  owner_dept text,
  measure_sql text,
  active boolean DEFAULT true NOT NULL,
  sort integer DEFAULT 0 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  category text,
  horizon text DEFAULT 'year_1'::text NOT NULL,
  direction text DEFAULT 'at_least'::text NOT NULL,
  no_measure_reason text,
  deadline date
);

CREATE TABLE IF NOT EXISTS public.company_index (
  id bigint DEFAULT nextval('company_index_id_seq'::regclass) NOT NULL,
  measured_on date NOT NULL,
  index_name text NOT NULL,
  dimensions jsonb NOT NULL,
  score numeric NOT NULL,
  band text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.company_policy_decision (
  decision_key text NOT NULL,
  decided_on date NOT NULL,
  decided_by text DEFAULT 'founder'::text NOT NULL,
  decision_text text NOT NULL,
  applies_to text[] DEFAULT '{}'::text[] NOT NULL,
  never_ask_again boolean DEFAULT true NOT NULL,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.company_reflection (
  id bigint DEFAULT nextval('company_reflection_id_seq'::regclass) NOT NULL,
  reflected_on date NOT NULL,
  answers jsonb NOT NULL,
  concerns integer DEFAULT 0 NOT NULL,
  actions integer DEFAULT 0 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.company_registration (
  recorded_at timestamp with time zone DEFAULT now() NOT NULL,
  authority text NOT NULL,
  license_type text NOT NULL,
  license_no text NOT NULL,
  trade_name text NOT NULL,
  issued_on date NOT NULL,
  expires_on date NOT NULL,
  owner_name text NOT NULL,
  owner_share text NOT NULL,
  activities text NOT NULL,
  registered_email text NOT NULL,
  registered_mobile text NOT NULL,
  e_stores text NOT NULL,
  license_class_note text NOT NULL,
  source_file text NOT NULL,
  vat_registered boolean DEFAULT false NOT NULL,
  trn text,
  vat_threshold_aed numeric DEFAULT 375000 NOT NULL,
  vat_ruling_on date,
  corporate_tax_note text,
  auditor text
);

CREATE TABLE IF NOT EXISTS public.company_reputation_snapshot (
  day date NOT NULL,
  reviews integer NOT NULL,
  avg_rating numeric,
  low_ratings_30d integer NOT NULL,
  asks_sent integer NOT NULL,
  asks_waiting integer NOT NULL
);

CREATE TABLE IF NOT EXISTS public.company_review_ask (
  customer_id uuid NOT NULL,
  status text NOT NULL,
  asked_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  transaction_id uuid
);

CREATE TABLE IF NOT EXISTS public.company_snapshot (
  snapshot_on date NOT NULL,
  state jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.company_stand_down (
  id bigint DEFAULT nextval('company_stand_down_id_seq'::regclass) NOT NULL,
  stood_down_at timestamp with time zone DEFAULT now() NOT NULL,
  actor text NOT NULL,
  reason text NOT NULL,
  paused_jobs jsonb DEFAULT '[]'::jsonb NOT NULL,
  cancelled jsonb DEFAULT '{}'::jsonb NOT NULL,
  resumed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.company_vision (
  id integer DEFAULT 1 NOT NULL,
  vision text NOT NULL,
  mission text NOT NULL,
  principles text,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.comparison_run_v2 (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  inquiry_id uuid NOT NULL,
  quote_signature text NOT NULL,
  algorithm_version text NOT NULL,
  corpus_version text,
  customer_priority jsonb DEFAULT '{}'::jsonb NOT NULL,
  status text DEFAULT 'processing'::text NOT NULL,
  deterministic_result jsonb,
  explanation_en jsonb,
  explanation_ar jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.competitive_position (
  id bigint DEFAULT nextval('competitive_position_id_seq'::regclass) NOT NULL,
  dimension text NOT NULL,
  quotesdone text NOT NULL,
  market_norm text NOT NULL,
  verdict text NOT NULL,
  evidence text
);

CREATE TABLE IF NOT EXISTS public.competitor (
  id bigint DEFAULT nextval('competitor_id_seq'::regclass) NOT NULL,
  name text NOT NULL,
  url text,
  kind text NOT NULL,
  what_they_do text NOT NULL,
  business_model text,
  overlap text,
  strength text,
  weakness text,
  offers_anonymity boolean,
  threat_level text,
  verified_at date DEFAULT CURRENT_DATE,
  source_url text,
  social_handles jsonb DEFAULT '{}'::jsonb NOT NULL,
  pricing_url text,
  watch jsonb,
  watched boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.competitor_scan (
  id bigint DEFAULT nextval('competitor_scan_id_seq'::regclass) NOT NULL,
  competitor_id bigint NOT NULL,
  page_kind text NOT NULL,
  url text NOT NULL,
  requested_at timestamp with time zone DEFAULT now() NOT NULL,
  request_id bigint,
  status text DEFAULT 'fetching'::text NOT NULL,
  http_status integer,
  content_hash text,
  page_text text,
  error text,
  held_id bigint,
  decision text,
  fields jsonb,
  reasoning text,
  model text,
  task_id bigint,
  decided_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.complaint_tickets (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  ticket_no text NOT NULL,
  email text NOT NULL,
  name text,
  message text NOT NULL,
  contact_message_id bigint,
  status text DEFAULT 'acknowledged'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  acknowledge_due timestamp with time zone NOT NULL,
  respond_due timestamp with time zone NOT NULL,
  acknowledged_at timestamp with time zone,
  in_review_at timestamp with time zone,
  final_response_at timestamp with time zone,
  final_response text,
  handled_by text DEFAULT 'customer_support'::text NOT NULL,
  decision_ref text GENERATED ALWAYS AS (
CASE
    WHEN (final_response_at IS NOT NULL) THEN (ticket_no || '-FR'::text)
    ELSE NULL::text
END) STORED
);

CREATE TABLE IF NOT EXISTS public.compliance_sources (
  id bigint DEFAULT nextval('compliance_sources_id_seq'::regclass) NOT NULL,
  authority text NOT NULL,
  topic text NOT NULL,
  url text NOT NULL,
  last_signature text,
  last_summary text,
  last_checked_at timestamp with time zone,
  last_changed_at timestamp with time zone,
  active boolean DEFAULT true NOT NULL,
  note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  doc_path text,
  doc_bytes bigint,
  doc_content_type text,
  doc_downloaded_at timestamp with time zone,
  fetch_mode text DEFAULT 'direct'::text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.contact_duplicate_group (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  run_on date DEFAULT CURRENT_DATE NOT NULL,
  identity_key text NOT NULL,
  kinds text[] NOT NULL,
  members jsonb NOT NULL,
  member_count integer NOT NULL,
  phone_confirms boolean DEFAULT false NOT NULL,
  all_demo boolean NOT NULL,
  status text DEFAULT 'reported'::text NOT NULL,
  handed_to_seat text,
  merged_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.contact_merge_audit (
  id bigint DEFAULT nextval('contact_merge_audit_id_seq'::regclass) NOT NULL,
  group_id uuid NOT NULL,
  kind text NOT NULL,
  winner_id text NOT NULL,
  loser_id text NOT NULL,
  reviewed_by_seat text NOT NULL,
  reason text NOT NULL,
  before_row jsonb NOT NULL,
  after_row jsonb NOT NULL,
  repointed jsonb NOT NULL,
  at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.contact_messages (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  name text,
  email text,
  phone text,
  message text,
  source text DEFAULT 'contact_page'::text,
  status text DEFAULT 'new'::text,
  user_agent text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.content_drafts (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  channel text DEFAULT 'social'::text NOT NULL,
  category text,
  title text,
  body text NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  source text DEFAULT 'marketing_agent'::text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  staged_at timestamp with time zone,
  image_url text,
  review_status text DEFAULT 'pending'::text,
  founder_comment text,
  reviewed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.continuity_plan (
  service text NOT NULL,
  criticality text DEFAULT 'high'::text NOT NULL,
  failure_mode text NOT NULL,
  detection text NOT NULL,
  fallback text NOT NULL,
  degraded_mode text NOT NULL,
  recovery text NOT NULL,
  rto_minutes integer,
  owner_agent text,
  last_tested date,
  probe_sql text,
  last_result text
);

CREATE TABLE IF NOT EXISTS public.control_mode_action (
  action text NOT NULL,
  description text NOT NULL,
  risk text DEFAULT 'medium'::text NOT NULL,
  classification text NOT NULL,
  requires_control boolean GENERATED ALWAYS AS ((classification = 'mutating'::text)) STORED
);

CREATE TABLE IF NOT EXISTS public.control_mode_audit (
  id bigint DEFAULT nextval('control_mode_audit_id_seq'::regclass) NOT NULL,
  at timestamp with time zone DEFAULT now() NOT NULL,
  actor_email text,
  event text NOT NULL,
  action text,
  session_id uuid,
  allowed boolean NOT NULL,
  reason text,
  detail jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS public.control_mode_challenge (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  admin_email text NOT NULL,
  purpose text DEFAULT 'control_mode'::text NOT NULL,
  nonce text NOT NULL,
  code_hash text NOT NULL,
  phone_tail text,
  expires_at timestamp with time zone NOT NULL,
  attempts integer DEFAULT 0 NOT NULL,
  max_attempts integer DEFAULT 5 NOT NULL,
  consumed_at timestamp with time zone,
  consumed_why text,
  ip text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.control_mode_identity (
  admin_email text NOT NULL,
  phone_secret_key text DEFAULT 'admin_mfa_phone'::text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.control_mode_session (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  user_id uuid,
  actor_email text NOT NULL,
  reason text NOT NULL,
  opened_at timestamp with time zone DEFAULT now() NOT NULL,
  expires_at timestamp with time zone NOT NULL,
  closed_at timestamp with time zone,
  closed_reason text,
  mfa_method text NOT NULL,
  mfa_ref uuid NOT NULL,
  ip text,
  user_agent text,
  actions_used integer DEFAULT 0 NOT NULL
);

CREATE TABLE IF NOT EXISTS public.conversation_archive (
  source_table text NOT NULL,
  source_id text NOT NULL,
  pdf_bucket text DEFAULT 'backups'::text NOT NULL,
  pdf_path text NOT NULL,
  bytes bigint,
  archived_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.conversation_archive_attempt (
  source_table text NOT NULL,
  source_id text NOT NULL,
  attempts integer DEFAULT 0 NOT NULL,
  first_at timestamp with time zone DEFAULT now() NOT NULL,
  last_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.conversation_retention_log (
  source_table text NOT NULL,
  source_id text NOT NULL,
  party_kind text,
  party_id text,
  occurred_at timestamp with time zone,
  last_activity timestamp with time zone,
  removed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.conversation_retention_pdf (
  source_table text NOT NULL,
  source_id text NOT NULL,
  pdf_bucket text,
  pdf_path text,
  queued_at timestamp with time zone DEFAULT now() NOT NULL,
  deleted_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.conversation_retention_plan_log (
  decided_for date NOT NULL,
  source_table text NOT NULL,
  source_id text NOT NULL,
  party_kind text,
  party_id text,
  occurred_at timestamp with time zone,
  last_activity timestamp with time zone,
  decided_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.critical_capability (
  capability_key text NOT NULL,
  capability text NOT NULL,
  why_critical text NOT NULL,
  owner_dept text,
  test_kind text,
  test_ref text,
  last_verdict text,
  last_checked timestamp with time zone,
  probe_sql text
);

CREATE TABLE IF NOT EXISTS public.crm_activities (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  entity text NOT NULL,
  entity_id text NOT NULL,
  type text NOT NULL,
  subject text,
  body text,
  actor text,
  due_at timestamp with time zone,
  done boolean DEFAULT false NOT NULL,
  done_at timestamp with time zone,
  meta jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.crm_notes (
  id bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
  entity text NOT NULL,
  entity_id text NOT NULL,
  body text NOT NULL,
  author text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.crm_stages (
  key text NOT NULL,
  label text NOT NULL,
  sort_order integer DEFAULT 0 NOT NULL,
  probability integer DEFAULT 0 NOT NULL,
  is_won boolean DEFAULT false NOT NULL,
  is_lost boolean DEFAULT false NOT NULL,
  active boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.crm_tasks (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  title text NOT NULL,
  detail text,
  status text DEFAULT 'open'::text NOT NULL,
  priority text DEFAULT 'normal'::text,
  source text DEFAULT 'admin'::text,
  entity text,
  entity_id text,
  due_date date,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  done_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.cron_job_seen (
  jobid bigint NOT NULL,
  jobname text NOT NULL,
  schedule text,
  first_seen timestamp with time zone DEFAULT now() NOT NULL,
  last_seen timestamp with time zone DEFAULT now() NOT NULL,
  last_success timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.cron_registry (
  jobname text NOT NULL,
  human_name text NOT NULL,
  category text DEFAULT 'Operations'::text NOT NULL,
  purpose text DEFAULT ''::text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customer_calls (
  id bigint DEFAULT nextval('customer_calls_id_seq'::regclass) NOT NULL,
  customer_id uuid,
  inquiry_id uuid,
  supplier_id bigint,
  project_id uuid,
  direction text DEFAULT 'outbound'::text NOT NULL,
  status text DEFAULT 'completed'::text NOT NULL,
  started_at timestamp with time zone DEFAULT now() NOT NULL,
  duration_s integer,
  summary text,
  recording_path text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customer_followup (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  transaction_id uuid NOT NULL,
  stage text NOT NULL,
  token uuid DEFAULT gen_random_uuid() NOT NULL,
  lang text NOT NULL,
  asked_at timestamp with time zone DEFAULT now() NOT NULL,
  answered_at timestamp with time zone,
  hired text,
  stars smallint,
  comment text,
  outcome jsonb
);

CREATE TABLE IF NOT EXISTS public.customer_kpi_snapshots (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
  kpis jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customer_layout (
  customer_id uuid NOT NULL,
  layout jsonb DEFAULT '[]'::jsonb NOT NULL,
  reason text,
  pinned jsonb DEFAULT '[]'::jsonb NOT NULL,
  computed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customer_phone_otps (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  customer_id uuid,
  phone text NOT NULL,
  code_hash text NOT NULL,
  expires_at timestamp with time zone NOT NULL,
  attempts integer DEFAULT 0,
  consumed boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.customer_preference (
  customer_id uuid NOT NULL,
  preferences jsonb DEFAULT '{}'::jsonb NOT NULL,
  consented_at timestamp with time zone,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customer_score (
  customer_id bigint NOT NULL,
  rfqs_posted integer DEFAULT 0 NOT NULL,
  rfqs_awarded integer DEFAULT 0 NOT NULL,
  avg_budget_aed numeric,
  preferred_categories text[],
  lifetime_value_aed numeric,
  churn_risk numeric,
  last_active timestamp with time zone,
  computed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customer_spec_guide (
  trade text NOT NULL,
  body_en text NOT NULL,
  body_ar text NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customer_support_case_review (
  week_ending date NOT NULL,
  metrics jsonb NOT NULL,
  knowledge_filed integer DEFAULT 0 NOT NULL,
  fixture boolean DEFAULT false NOT NULL,
  reviewed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customer_support_data_request (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  received_at timestamp with time zone DEFAULT now() NOT NULL,
  email text NOT NULL,
  kind text NOT NULL,
  source text NOT NULL,
  case_ref text,
  pdpl_request_id uuid,
  handoff_id bigint,
  identity_status text DEFAULT 'pending'::text NOT NULL,
  due_at timestamp with time zone NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  fulfilled_at timestamp with time zone,
  outcome jsonb DEFAULT '{}'::jsonb NOT NULL,
  warned_at timestamp with time zone,
  overdue_at timestamp with time zone,
  fixture boolean DEFAULT false NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customer_support_duty_message (
  stage text NOT NULL,
  subject_key text NOT NULL,
  customer_id uuid,
  lead_id bigint,
  to_email text,
  outcome text DEFAULT 'pending'::text NOT NULL,
  handoff_id bigint,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customer_support_inbound_drive (
  channel text NOT NULL,
  message_id bigint NOT NULL,
  case_ref text,
  acknowledged boolean DEFAULT false NOT NULL,
  handoff_id bigint,
  outcome text,
  acted_at timestamp with time zone DEFAULT now() NOT NULL,
  answered_at timestamp with time zone,
  fixture boolean DEFAULT false NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customer_support_monthly_review (
  month date NOT NULL,
  metrics jsonb NOT NULL,
  below_target text[] DEFAULT '{}'::text[] NOT NULL,
  fixture boolean DEFAULT false NOT NULL,
  reviewed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customer_support_reply_quality_week (
  week_ending date NOT NULL,
  metrics jsonb NOT NULL,
  below_target text[] DEFAULT '{}'::text[] NOT NULL,
  fixture boolean DEFAULT false NOT NULL,
  reviewed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customer_support_voc_month (
  month date NOT NULL,
  report jsonb NOT NULL,
  actions jsonb DEFAULT '[]'::jsonb NOT NULL,
  ceo_report jsonb,
  fixture boolean DEFAULT false NOT NULL,
  reported_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customer_support_voice_owed (
  stage text NOT NULL,
  subject_key text NOT NULL,
  voice_key text NOT NULL,
  to_role text NOT NULL,
  to_email text NOT NULL,
  lang text NOT NULL,
  subject text NOT NULL,
  draft text NOT NULL,
  situation text NOT NULL,
  facts text DEFAULT ''::text NOT NULL,
  must text[] DEFAULT '{}'::text[] NOT NULL,
  attempts integer DEFAULT 0 NOT NULL,
  last_error text,
  written_by text,
  written_at timestamp with time zone,
  result jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customers (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  full_name text,
  phone text,
  email text,
  created_at timestamp with time zone DEFAULT now(),
  phone_verified boolean DEFAULT false,
  banned boolean DEFAULT false,
  banned_reason text,
  chat_strikes integer DEFAULT 0,
  date_of_birth date,
  email_verified boolean DEFAULT false NOT NULL,
  tos_accepted_at timestamp with time zone,
  tos_version text,
  wa_optin boolean DEFAULT false,
  signed_terms_url text,
  signed_terms_path text,
  signed_terms_at timestamp with time zone,
  tos_ip text,
  locale text DEFAULT 'en'::text NOT NULL,
  industry text,
  is_demo boolean GENERATED ALWAYS AS ((fn_is_demo_email(email) OR fn_is_demo_phone(phone) OR fn_is_demo_phone(whatsapp_phone) OR (COALESCE(full_name, ''::text) ~* '^ZZ DEMO([^a-z]|$)'::text))) STORED,
  whatsapp_phone text,
  whatsapp_verified_at timestamp with time zone,
  whatsapp_opt text,
  whatsapp_asked_at timestamp with time zone,
  tos_sha256 text,
  merged_into uuid,
  merged_at timestamp with time zone,
  disputes_filed integer DEFAULT 0 NOT NULL,
  repeat_disputer boolean GENERATED ALWAYS AS ((disputes_filed >= 2)) STORED,
  marketing_consent boolean DEFAULT false NOT NULL,
  marketing_consent_at timestamp with time zone,
  marketing_consent_source text
);

CREATE TABLE IF NOT EXISTS public.dead_letter (
  id bigint DEFAULT nextval('dead_letter_id_seq'::regclass) NOT NULL,
  source text NOT NULL,
  source_id text,
  kind text,
  reason text NOT NULL,
  payload jsonb,
  first_failed_at timestamp with time zone DEFAULT now() NOT NULL,
  attempts integer DEFAULT 1 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  resolved_at timestamp with time zone,
  resolved_by text,
  resolution text
);

CREATE TABLE IF NOT EXISTS public.decision_log (
  id bigint DEFAULT nextval('decision_log_id_seq'::regclass) NOT NULL,
  actor text,
  kind text NOT NULL,
  ctx jsonb,
  decision text,
  confidence numeric,
  reasons jsonb,
  sources jsonb,
  route_to text,
  created_at timestamp with time zone DEFAULT now(),
  alternatives jsonb
);

CREATE TABLE IF NOT EXISTS public.decision_policy (
  key text NOT NULL,
  value jsonb NOT NULL,
  description text,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.decision_record (
  id bigint DEFAULT nextval('decision_record_id_seq'::regclass) NOT NULL,
  decided_by text NOT NULL,
  dept_key text,
  problem text NOT NULL,
  context text,
  options jsonb,
  risks text,
  benefits text,
  recommendation text NOT NULL,
  confidence numeric,
  expected_outcome text,
  rollback_plan text,
  serves_goal text,
  approved_by text,
  status text DEFAULT 'proposed'::text NOT NULL,
  actual_outcome text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  impact_business text,
  impact_financial text,
  financial_aed numeric,
  impact_legal text,
  impact_customer text,
  impact_supplier text,
  evidence jsonb DEFAULT '[]'::jsonb,
  reversible boolean,
  decided_at timestamp with time zone DEFAULT now(),
  gate_verdict text,
  gate_reason text,
  gate_checked_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.decision_review_request (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  decision_type text NOT NULL,
  owner_seat text NOT NULL,
  channel text NOT NULL,
  requester text NOT NULL,
  subject_table text,
  subject_id text,
  request_text text NOT NULL,
  original_seat text,
  original_model text,
  original_decision_log_id bigint,
  original_family text GENERATED ALWAYS AS (COALESCE(NULLIF(split_part(original_model, '/'::text, 1), ''::text), 'deterministic'::text)) STORED,
  status text DEFAULT 'open'::text NOT NULL,
  founder_notified jsonb,
  reviewer_seat text,
  reviewer_model text,
  reviewer_family text GENERATED ALWAYS AS (NULLIF(split_part(reviewer_model, '/'::text, 1), ''::text)) STORED,
  verdict text,
  verdict_reason text,
  handoff_id bigint,
  evidence jsonb DEFAULT '{}'::jsonb NOT NULL,
  attempts integer DEFAULT 0 NOT NULL,
  last_attempt_at timestamp with time zone,
  last_error text,
  reply_text text,
  reply_handoff_id bigint,
  seat_decision_log_id bigint,
  dedupe_key text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  decided_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.decision_trace (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  correlation_id uuid NOT NULL,
  causation_event_id bigint,
  entity_type text,
  entity_id text,
  decision_type text NOT NULL,
  proposed_by text,
  decided_by text,
  policy_keys text[] DEFAULT '{}'::text[] NOT NULL,
  knowledge_refs jsonb DEFAULT '[]'::jsonb NOT NULL,
  evidence_refs jsonb DEFAULT '[]'::jsonb NOT NULL,
  alternatives jsonb DEFAULT '[]'::jsonb NOT NULL,
  assumptions jsonb DEFAULT '[]'::jsonb NOT NULL,
  risk jsonb DEFAULT '{}'::jsonb NOT NULL,
  confidence numeric,
  authority_result jsonb DEFAULT '{}'::jsonb NOT NULL,
  decision jsonb NOT NULL,
  outcome_status text DEFAULT 'pending'::text NOT NULL,
  outcome jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  evaluated_at timestamp with time zone,
  task_id text,
  agent_key text,
  role_id text,
  department_id text,
  manager_id text,
  task_class text,
  company_objective text,
  department_objective text,
  relevant_kpi text,
  knowledge_versions jsonb DEFAULT '{}'::jsonb NOT NULL,
  source_freshness jsonb DEFAULT '{}'::jsonb NOT NULL,
  tools_requested text[] DEFAULT '{}'::text[] NOT NULL,
  tools_executed text[] DEFAULT '{}'::text[] NOT NULL,
  tool_result_refs jsonb DEFAULT '[]'::jsonb NOT NULL,
  uncertainty text,
  escalation_decision text,
  proposed_action text,
  expected_outcome text,
  review_date date,
  model text,
  provider text,
  input_tokens integer,
  output_tokens integer,
  estimated_cost_aed numeric(12,4),
  final_status text,
  sealed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.delegation_rule (
  id bigint DEFAULT nextval('delegation_rule_id_seq'::regclass) NOT NULL,
  dept_key text NOT NULL,
  when_agent text NOT NULL,
  delegate_to text NOT NULL,
  basis text NOT NULL,
  rank integer DEFAULT 1 NOT NULL,
  active boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.deliverability_test (
  test_id text NOT NULL,
  project_id text,
  provider text DEFAULT 'glockapps'::text NOT NULL,
  lane text DEFAULT 'm365'::text NOT NULL,
  from_address text,
  reason text NOT NULL,
  requested_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  marker text NOT NULL,
  seeds jsonb DEFAULT '[]'::jsonb NOT NULL,
  seeds_refused jsonb DEFAULT '[]'::jsonb NOT NULL,
  notification_ids bigint[] DEFAULT '{}'::bigint[] NOT NULL,
  status text DEFAULT 'seeds_queued'::text NOT NULL,
  polls integer DEFAULT 0 NOT NULL,
  last_polled_at timestamp with time zone,
  last_error text,
  stats jsonb,
  filters jsonb DEFAULT '{}'::jsonb NOT NULL,
  outlook jsonb,
  outlook_inbox_pct numeric,
  verdict text DEFAULT 'pending'::text NOT NULL,
  decided_at timestamp with time zone,
  summary text,
  reported_at timestamp with time zone,
  report_result jsonb,
  tested_at timestamp with time zone,
  recorded_by text,
  recorded_at timestamp with time zone,
  source text,
  class_rates jsonb,
  overall_inbox_pct numeric,
  overall_tabs_pct numeric,
  overall_spam_pct numeric,
  overall_missing_pct numeric
);

CREATE TABLE IF NOT EXISTS public.deliverability_test_provider (
  test_id text NOT NULL,
  provider text NOT NULL,
  provider_group_id text,
  is_outlook boolean DEFAULT false NOT NULL,
  seeds integer NOT NULL,
  inbox integer NOT NULL,
  spam integer NOT NULL,
  tabs integer NOT NULL,
  missing integer NOT NULL,
  inbox_pct numeric,
  raw_itypes jsonb DEFAULT '{}'::jsonb NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  provider_class text
);

CREATE TABLE IF NOT EXISTS public.demand_forecast (
  run_on date NOT NULL,
  trade text NOT NULL,
  emirate text NOT NULL,
  inquiries_30d integer NOT NULL,
  inquiries_90d integer NOT NULL,
  searches_30d integer NOT NULL,
  searches_90d integer NOT NULL,
  forecast_30d numeric NOT NULL,
  forecast_90d numeric NOT NULL,
  searches_forecast_30d numeric NOT NULL,
  searches_forecast_90d numeric NOT NULL,
  basis text DEFAULT 'estimate'::text NOT NULL,
  method text NOT NULL,
  sufficient_data boolean NOT NULL,
  matchable integer,
  target integer,
  acted text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.demand_search (
  id bigint DEFAULT nextval('demand_search_id_seq'::regclass) NOT NULL,
  category text NOT NULL,
  trades text[] DEFAULT '{}'::text[] NOT NULL,
  emirate text,
  source text DEFAULT 'route_brief'::text NOT NULL,
  searched_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.department_budget (
  dept_key text NOT NULL,
  monthly_aed numeric NOT NULL,
  spent_aed numeric DEFAULT 0 NOT NULL,
  period_label text NOT NULL,
  degrade_at_pct integer DEFAULT 70 NOT NULL,
  halt_at_pct integer DEFAULT 95 NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.department_objective (
  id bigint DEFAULT nextval('department_objective_id_seq'::regclass) NOT NULL,
  dept_key text NOT NULL,
  objective text NOT NULL,
  horizon text DEFAULT 'year_1'::text NOT NULL,
  sort integer DEFAULT 0 NOT NULL,
  active boolean DEFAULT true NOT NULL,
  goal_key text,
  status text DEFAULT 'active'::text NOT NULL,
  superseded_by bigint,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  target_value numeric,
  unit text,
  measure_sql text,
  actual_value numeric,
  measured_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.deploy_state (
  id integer NOT NULL,
  dirty boolean DEFAULT false,
  last_deploy timestamp with time zone,
  last_status text
);

CREATE TABLE IF NOT EXISTS public.dept_knowledge_alias (
  dept_key text NOT NULL,
  alias_kind text NOT NULL,
  alias_key text NOT NULL,
  reason text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.dept_library (
  id bigint DEFAULT nextval('dept_library_id_seq'::regclass) NOT NULL,
  department text NOT NULL,
  category text,
  domain text,
  title text NOT NULL,
  content text NOT NULL,
  tags text,
  source_file text,
  tsv tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, ((((COALESCE(title, ''::text) || ' '::text) || COALESCE(tags, ''::text)) || ' '::text) || COALESCE(content, ''::text)))) STORED,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.doc_backups (
  id bigint DEFAULT nextval('doc_backups_id_seq'::regclass) NOT NULL,
  entity text NOT NULL,
  entity_id text NOT NULL,
  doc_type text,
  bucket text,
  path text,
  file_name text,
  dropbox_path text,
  bytes bigint,
  status text DEFAULT 'pending'::text NOT NULL,
  error text,
  attempts integer DEFAULT 0 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  backed_up_at timestamp with time zone,
  source text DEFAULT 'storage'::text NOT NULL,
  gen_kind text,
  gen_ref text,
  dedupe_key text,
  dropbox_content_hash text,
  dropbox_size bigint,
  verified_at timestamp with time zone,
  requeued_at timestamp with time zone,
  upload_state jsonb,
  last_attempt_at timestamp with time zone,
  claimed_at timestamp with time zone,
  claimed_by text,
  prune_attempts integer DEFAULT 0 NOT NULL,
  status_before_prune text
);

CREATE TABLE IF NOT EXISTS public.doc_reviews (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  lead_id bigint,
  from_email text,
  subject text,
  file_name text,
  file_path text,
  mime text,
  ai_relevant boolean,
  ai_category text,
  ai_summary text,
  ai_suggested_field text,
  ai_confidence text,
  status text DEFAULT 'pending'::text NOT NULL,
  decided_by text,
  decided_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  auto_applied boolean DEFAULT false,
  extracted jsonb,
  owner_role text
);

CREATE TABLE IF NOT EXISTS public.doc_versions (
  id bigint DEFAULT nextval('doc_versions_id_seq'::regclass) NOT NULL,
  entity_type text NOT NULL,
  entity_id text NOT NULL,
  version integer NOT NULL,
  snapshot jsonb NOT NULL,
  checksum text,
  changed_fields text[] DEFAULT '{}'::text[],
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.document_kpi_snapshots (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
  kpis jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.documents (
  id bigint DEFAULT nextval('documents_id_seq'::regclass) NOT NULL,
  bucket text NOT NULL,
  path text NOT NULL,
  file_name text,
  kind text NOT NULL,
  ref_table text,
  ref_id text,
  mime text,
  status text DEFAULT 'pending'::text NOT NULL,
  extracted jsonb,
  indexed boolean DEFAULT false,
  error text,
  attempts integer DEFAULT 0,
  created_at timestamp with time zone DEFAULT now(),
  processed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.drawing_redaction_runs (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  customer_id uuid,
  owner_email text,
  caller_ref text,
  source_path text,
  output_paths text[] DEFAULT '{}'::text[] NOT NULL,
  pages_in integer DEFAULT 0 NOT NULL,
  pages_out integer DEFAULT 0 NOT NULL,
  skipped integer DEFAULT 0 NOT NULL,
  status text DEFAULT 'unknown'::text NOT NULL,
  pages_verified integer DEFAULT 0 NOT NULL,
  verify_failed integer DEFAULT 0 NOT NULL,
  verify_detail jsonb
);

CREATE TABLE IF NOT EXISTS public.dropbox_files (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  dropbox_id text,
  path text NOT NULL,
  name text,
  is_folder boolean DEFAULT false,
  size bigint DEFAULT 0,
  content_hash text,
  server_modified timestamp with time zone,
  synced_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.duty_pause (
  duty text NOT NULL,
  reason text NOT NULL,
  paused_by text NOT NULL,
  paused_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ea_events (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  kind text DEFAULT 'meeting'::text NOT NULL,
  title text NOT NULL,
  starts_at timestamp with time zone,
  ends_at timestamp with time zone,
  all_day boolean DEFAULT false,
  location text,
  attendees text[],
  notes text,
  source text DEFAULT 'manual'::text,
  external_id text,
  status text DEFAULT 'scheduled'::text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ea_meetings (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  title text,
  meeting_at timestamp with time zone DEFAULT now(),
  attendees text[],
  summary text,
  decisions jsonb DEFAULT '[]'::jsonb,
  action_items jsonb DEFAULT '[]'::jsonb,
  source text DEFAULT 'manual'::text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ea_reminders (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  title text NOT NULL,
  remind_at timestamp with time zone NOT NULL,
  notes text,
  done boolean DEFAULT false,
  done_at timestamp with time zone,
  notified_at timestamp with time zone,
  source text DEFAULT 'manual'::text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.edge_expectation (
  fn_key text NOT NULL,
  cron_jobname text,
  purpose text NOT NULL,
  heartbeat_sql text NOT NULL,
  max_silence_minutes integer DEFAULT 60 NOT NULL,
  blast_radius text NOT NULL,
  dept_key text,
  severity text DEFAULT 'medium'::text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.edge_health_probe (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  fn_key text NOT NULL,
  checked_at timestamp with time zone DEFAULT now() NOT NULL,
  last_beat_at timestamp with time zone,
  silent_minutes numeric,
  verdict text NOT NULL,
  note text
);

CREATE TABLE IF NOT EXISTS public.email_block_pattern (
  id bigint DEFAULT nextval('email_block_pattern_id_seq'::regclass) NOT NULL,
  pattern text NOT NULL,
  reason text NOT NULL,
  active boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.email_domain_mx (
  domain text NOT NULL,
  has_mx boolean NOT NULL,
  kind text DEFAULT 'unknown'::text NOT NULL,
  hosts text[],
  checked_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.email_platform_domain (
  domain text NOT NULL,
  kind text NOT NULL,
  reason text NOT NULL,
  added_by text DEFAULT 'marketing'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  generic boolean DEFAULT false NOT NULL
);

CREATE TABLE IF NOT EXISTS public.email_suppressions (
  email text NOT NULL,
  reason text DEFAULT 'unsubscribe'::text,
  source text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.email_verifications (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  email text NOT NULL,
  token text,
  purpose text DEFAULT 'signup'::text NOT NULL,
  user_kind text DEFAULT 'customer'::text NOT NULL,
  expires_at timestamp with time zone NOT NULL,
  used_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  attempts integer DEFAULT 0 NOT NULL,
  token_hash text
);

CREATE TABLE IF NOT EXISTS public.employee_authority (
  agent_key text NOT NULL,
  action_class text NOT NULL,
  max_tier text DEFAULT 'advisory'::text NOT NULL,
  threshold_aed numeric,
  note text
);

CREATE TABLE IF NOT EXISTS public.employee_knowledge (
  agent_key text NOT NULL,
  domain_key text NOT NULL,
  depth text DEFAULT 'working'::text NOT NULL,
  layer_no integer
);

CREATE TABLE IF NOT EXISTS public.employee_knowledge_standard (
  layer_no integer NOT NULL,
  layer text NOT NULL,
  intent text NOT NULL,
  binds_via text NOT NULL,
  required boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.employee_kpi (
  id bigint DEFAULT nextval('employee_kpi_id_seq'::regclass) NOT NULL,
  agent_key text NOT NULL,
  kpi text NOT NULL,
  metric text NOT NULL,
  target_value numeric,
  unit text,
  cadence text DEFAULT 'monthly'::text NOT NULL,
  serves_goal text,
  measure_sql text,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  serves_objective bigint,
  actual_value numeric,
  measured_at timestamp with time zone,
  no_measure_reason text,
  kpi_class text
);

CREATE TABLE IF NOT EXISTS public.employee_kpi_history (
  id bigint DEFAULT nextval('employee_kpi_history_id_seq'::regclass) NOT NULL,
  kpi_id bigint NOT NULL,
  agent_key text NOT NULL,
  actual_value numeric,
  target_value numeric,
  unit text,
  attainment numeric,
  verdict text,
  measured_at timestamp with time zone DEFAULT now() NOT NULL,
  measured_on date DEFAULT ((now() AT TIME ZONE 'utc'::text))::date NOT NULL
);

CREATE TABLE IF NOT EXISTS public.employee_workflow (
  agent_key text NOT NULL,
  workflow_key text NOT NULL,
  role_in_workflow text DEFAULT 'participant'::text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.entity_comments (
  id bigint DEFAULT nextval('entity_comments_id_seq'::regclass) NOT NULL,
  entity text NOT NULL,
  entity_id text NOT NULL,
  author text DEFAULT 'operator'::text NOT NULL,
  body text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.error_events (
  id bigint DEFAULT nextval('error_events_id_seq'::regclass) NOT NULL,
  source text NOT NULL,
  kind text,
  severity text DEFAULT 'error'::text,
  detail jsonb,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.event_assessment (
  id bigint DEFAULT nextval('event_assessment_id_seq'::regclass) NOT NULL,
  event_id bigint NOT NULL,
  os_key text NOT NULL,
  agent_key text,
  severity text NOT NULL,
  impact text NOT NULL,
  proposed_action text,
  assessed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.event_delivery (
  id bigint DEFAULT nextval('event_delivery_id_seq'::regclass) NOT NULL,
  event_id bigint NOT NULL,
  agent_key text NOT NULL,
  event_type text NOT NULL,
  delivered_at timestamp with time zone DEFAULT now() NOT NULL,
  task_id bigint,
  os_key text,
  unroutable_reason text,
  result text,
  closed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.event_rollup (
  correlation_id uuid NOT NULL,
  root_event_id bigint,
  event_type text,
  os_count integer DEFAULT 0 NOT NULL,
  tasks_total integer DEFAULT 0 NOT NULL,
  tasks_closed integer DEFAULT 0 NOT NULL,
  outcome text,
  priority_note text,
  consolidated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.event_subscription (
  agent_key text NOT NULL,
  event_type text NOT NULL,
  reason text,
  active boolean DEFAULT true NOT NULL,
  action_class text
);

CREATE TABLE IF NOT EXISTS public.evolution_proposal (
  id bigint DEFAULT nextval('evolution_proposal_id_seq'::regclass) NOT NULL,
  trigger_kind text NOT NULL,
  subject text NOT NULL,
  observation text NOT NULL,
  evidence jsonb DEFAULT '{}'::jsonb,
  proposal text NOT NULL,
  change_class text DEFAULT 'process'::text NOT NULL,
  status text DEFAULT 'proposed'::text NOT NULL,
  decided_by text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.exec_reports (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  officer text NOT NULL,
  period text,
  summary text,
  findings jsonb DEFAULT '[]'::jsonb,
  recommendations jsonb DEFAULT '[]'::jsonb,
  metrics jsonb DEFAULT '{}'::jsonb,
  status text DEFAULT 'new'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  pdf_path text,
  pdf_generated_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.expense_bank_match (
  expense_entry_id bigint NOT NULL,
  bank_line_id bigint NOT NULL,
  receipt_aed numeric NOT NULL,
  bank_aed numeric NOT NULL,
  day_gap integer NOT NULL,
  vendor_in_text boolean NOT NULL,
  matched_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.expense_billing_mailbox (
  mailbox text NOT NULL,
  description text NOT NULL,
  reachable_by text,
  is_swept boolean DEFAULT false NOT NULL,
  last_swept_on date,
  note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.expense_entries (
  id bigint DEFAULT nextval('expense_entries_id_seq'::regclass) NOT NULL,
  vendor text NOT NULL,
  category text,
  amount numeric NOT NULL,
  currency text DEFAULT 'USD'::text NOT NULL,
  charged_on date DEFAULT CURRENT_DATE NOT NULL,
  note text,
  source text DEFAULT 'manual'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  doc_path text,
  doc_name text,
  doc_content_type text,
  source_msg_id text,
  vat_amount numeric(18,2),
  vendor_trn text,
  doc_kind text,
  doc_note text,
  read_as text,
  renews_item text
);

CREATE TABLE IF NOT EXISTS public.expense_sender_reading (
  sender text NOT NULL,
  kind text,
  kind_times integer DEFAULT 0 NOT NULL,
  vendor text,
  vendor_times integer DEFAULT 0 NOT NULL,
  last_email_id text,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.expense_vendor_billing_mailbox (
  id bigint DEFAULT nextval('expense_vendor_billing_mailbox_id_seq'::regclass) NOT NULL,
  vendor text NOT NULL,
  mailbox text NOT NULL,
  in_ledger_scope boolean,
  first_seen date,
  last_seen date,
  evidence text NOT NULL,
  note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.expenses (
  id bigint DEFAULT nextval('expenses_id_seq'::regclass) NOT NULL,
  vendor text NOT NULL,
  category text NOT NULL,
  description text,
  amount numeric NOT NULL,
  currency text DEFAULT 'USD'::text NOT NULL,
  cadence text DEFAULT 'monthly'::text NOT NULL,
  expense_date date,
  active boolean DEFAULT true NOT NULL,
  source text DEFAULT 'seed'::text NOT NULL,
  confidence text DEFAULT 'estimate'::text NOT NULL,
  note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  next_due date,
  last_reminded_at timestamp with time zone,
  reminder_days integer DEFAULT 3 NOT NULL
);

CREATE TABLE IF NOT EXISTS public.feedback (
  id bigint DEFAULT nextval('feedback_id_seq'::regclass) NOT NULL,
  source text NOT NULL,
  subject_type text,
  subject_id text,
  rating numeric,
  comment text,
  actioned boolean DEFAULT false NOT NULL,
  action_taken text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  case_id bigint,
  kind text,
  channel text,
  profile_id bigint
);

CREATE TABLE IF NOT EXISTS public.field_definition (
  field_id text NOT NULL,
  scope text NOT NULL,
  trade_key text,
  label_en text NOT NULL,
  label_ar text,
  unit text,
  answer_type text,
  numeric_tolerance integer,
  validation_ref text,
  evidence_rule text,
  regulatory_interpretation text,
  applies_when jsonb,
  review_status text DEFAULT 'approved'::text NOT NULL,
  review_note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  allowed_values text[],
  supersedes_field_ids text[]
);

CREATE TABLE IF NOT EXISTS public.field_definition_reference (
  field_id text NOT NULL,
  referencing_trade_key text NOT NULL,
  reason text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.field_definition_trade (
  field_id text NOT NULL,
  trade_key text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.file_scan (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  sha256 text NOT NULL,
  verdict text NOT NULL,
  source text NOT NULL,
  subject text,
  filename text,
  mime text,
  size_bytes bigint,
  bucket text,
  path text,
  engines_malicious integer DEFAULT 0 NOT NULL,
  engines_suspicious integer DEFAULT 0 NOT NULL,
  engines_total integer DEFAULT 0 NOT NULL,
  vt_status integer,
  blocked boolean DEFAULT false NOT NULL,
  detail jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  rechecked_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.finance_kpi_snapshots (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
  kpis jsonb NOT NULL,
  forecast jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.finance_reports (
  id bigint DEFAULT nextval('finance_reports_id_seq'::regclass) NOT NULL,
  period_start date,
  period_end date,
  kind text DEFAULT 'weekly'::text,
  summary text,
  kpis jsonb,
  html_path text,
  xlsx_path text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  pdf_path text,
  pdf_generated_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.finance_snapshots (
  id bigint DEFAULT nextval('finance_snapshots_id_seq'::regclass) NOT NULL,
  period_start date,
  period_end date,
  revenue_aed numeric DEFAULT 0,
  fees_collected_aed numeric DEFAULT 0,
  fees_pending_aed numeric DEFAULT 0,
  refunds_aed numeric DEFAULT 0,
  supplier_sub_aed numeric DEFAULT 0,
  expenses_aed numeric DEFAULT 0,
  net_aed numeric DEFAULT 0,
  kpis jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.fn_task_class (
  fn text NOT NULL,
  task_class text NOT NULL,
  note text,
  active boolean DEFAULT true NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  dept_key text
);

CREATE TABLE IF NOT EXISTS public.founder_alerts (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  level text DEFAULT 'info'::text,
  event text NOT NULL,
  detail text,
  channel text,
  created_at timestamp with time zone DEFAULT now(),
  dedupe_key text
);

CREATE TABLE IF NOT EXISTS public.founder_directive (
  id bigint DEFAULT nextval('founder_directive_id_seq'::regclass) NOT NULL,
  received_at timestamp with time zone DEFAULT now() NOT NULL,
  actor text NOT NULL,
  channel text DEFAULT 'whatsapp'::text NOT NULL,
  inbound text NOT NULL,
  setting_key text,
  old_value text,
  new_value text,
  applied boolean DEFAULT false NOT NULL,
  refusal text,
  meta jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS public.founder_habit (
  founder text NOT NULL,
  habit_key text NOT NULL,
  habit_kind text NOT NULL,
  observed_value numeric,
  observed_text text NOT NULL,
  sample_n integer DEFAULT 0 NOT NULL,
  confident boolean DEFAULT false NOT NULL,
  evidence jsonb DEFAULT '{}'::jsonb NOT NULL,
  first_seen timestamp with time zone,
  last_seen timestamp with time zone,
  computed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.founder_hold (
  hold_key text NOT NULL,
  what_is_held text NOT NULL,
  until_when text NOT NULL,
  target_keys text[] DEFAULT '{}'::text[] NOT NULL,
  flag_key text NOT NULL,
  flag_released_value text NOT NULL,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL,
  note text
);

CREATE TABLE IF NOT EXISTS public.founder_instruction (
  id bigint DEFAULT nextval('founder_instruction_id_seq'::regclass) NOT NULL,
  said_at timestamp with time zone NOT NULL,
  instruction text NOT NULL,
  subject text,
  status text DEFAULT 'open'::text NOT NULL,
  evidence text,
  closed_at timestamp with time zone,
  note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.founder_mail_policy (
  kind text NOT NULL,
  allowed_to_email boolean DEFAULT false NOT NULL,
  reason text NOT NULL,
  owner_role text NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.founder_mail_policy_history (
  id bigint DEFAULT nextval('founder_mail_policy_history_id_seq'::regclass) NOT NULL,
  kind text NOT NULL,
  allowed_to_email boolean NOT NULL,
  valid_from timestamp with time zone NOT NULL,
  changed_by text DEFAULT CURRENT_USER NOT NULL,
  source text NOT NULL,
  reason text,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.fraud_flags (
  kind text NOT NULL,
  subject_type text NOT NULL,
  subject_id text NOT NULL,
  severity text DEFAULT 'medium'::text NOT NULL,
  detail jsonb DEFAULT '{}'::jsonb,
  status text DEFAULT 'open'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.free_email_domain (
  domain text NOT NULL,
  provider text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.function_owner (
  function_slug text NOT NULL,
  owner text NOT NULL,
  note text NOT NULL,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL,
  moves_to text,
  moves_to_note text
);

CREATE TABLE IF NOT EXISTS public.gl_account_funnel_stage (
  account_code text NOT NULL,
  stage text NOT NULL,
  reason text NOT NULL,
  decided_by text DEFAULT 'ceo'::text NOT NULL,
  decided_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.gl_accounts (
  code text NOT NULL,
  name text NOT NULL,
  type text NOT NULL,
  subtype text,
  normal_balance character(1) NOT NULL,
  parent_code text,
  is_active boolean DEFAULT true NOT NULL,
  description text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.gl_expense_map (
  category text NOT NULL,
  account_code text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.gl_journal (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  entry_no text,
  entry_date date DEFAULT ((now() AT TIME ZONE 'utc'::text))::date NOT NULL,
  memo text,
  source text DEFAULT 'manual'::text NOT NULL,
  source_ref text,
  currency text DEFAULT 'AED'::text NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  reverses bigint,
  created_by text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  posted_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.gl_journal_lines (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  journal_id bigint NOT NULL,
  line_no integer,
  account_code text NOT NULL,
  debit numeric(18,2) DEFAULT 0 NOT NULL,
  credit numeric(18,2) DEFAULT 0 NOT NULL,
  memo text
);

CREATE TABLE IF NOT EXISTS public.gl_prior_period_adjustment (
  journal_id bigint NOT NULL,
  original_date date NOT NULL,
  closed_month date NOT NULL,
  posted_on date NOT NULL,
  source text NOT NULL,
  source_ref text,
  statement_line_id bigint,
  amount_aed numeric(18,2) NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.gl_settings (
  key text NOT NULL,
  num_value numeric,
  txt_value text,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.goal_period (
  id bigint DEFAULT nextval('goal_period_id_seq'::regclass) NOT NULL,
  goal_key text,
  horizon text NOT NULL,
  period_label text NOT NULL,
  target_value numeric,
  actual_value numeric,
  owner_dept text,
  status text DEFAULT 'open'::text NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.governance_policy (
  id bigint DEFAULT nextval('governance_policy_id_seq'::regclass) NOT NULL,
  domain text NOT NULL,
  policy text NOT NULL,
  rule text NOT NULL,
  enforced_by text,
  enforcement text DEFAULT 'declared'::text NOT NULL,
  owner_dept text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.governance_sensitive (
  subject text NOT NULL,
  key text NOT NULL,
  reason text NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.graph_edges (
  src_kind text NOT NULL,
  src_ref text NOT NULL,
  rel text NOT NULL,
  dst_kind text NOT NULL,
  dst_ref text NOT NULL,
  props jsonb DEFAULT '{}'::jsonb,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.graph_nodes (
  kind text NOT NULL,
  ref_id text NOT NULL,
  label text,
  props jsonb DEFAULT '{}'::jsonb,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.handoff_contract (
  id bigint DEFAULT nextval('handoff_contract_id_seq'::regclass) NOT NULL,
  action_id bigint NOT NULL,
  idempotency_key text NOT NULL,
  from_dept text NOT NULL,
  accountable_owner text NOT NULL,
  to_dept text NOT NULL,
  to_role text NOT NULL,
  purpose text NOT NULL,
  evidence jsonb DEFAULT '[]'::jsonb NOT NULL,
  requested_action text NOT NULL,
  deadline timestamp with time zone NOT NULL,
  acceptance_criteria text[] DEFAULT '{}'::text[] NOT NULL,
  closure_criteria text[] NOT NULL,
  escalation_conditions text NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  return_status text,
  return_reason text,
  accepted_by text,
  accepted_at timestamp with time zone,
  closed_by text,
  closed_at timestamp with time zone,
  closure_evidence jsonb,
  returns_count integer DEFAULT 0 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.health_checks (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  check_kind text NOT NULL,
  target text,
  ok boolean,
  status_code integer,
  latency_ms integer,
  detail text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.health_state (
  id integer NOT NULL,
  last_run timestamp with time zone,
  last_status text,
  last_alert_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.idea (
  id bigint DEFAULT nextval('idea_id_seq'::regclass) NOT NULL,
  submitted_by text NOT NULL,
  dept_key text,
  title text NOT NULL,
  problem text NOT NULL,
  proposal text NOT NULL,
  category text,
  serves_goal text,
  effort text,
  expected_value_aed numeric,
  confidence numeric,
  score numeric,
  stage text DEFAULT 'submitted'::text NOT NULL,
  decided_by text,
  outcome text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.inbound_messages (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  lead_id bigint,
  from_email text,
  to_email text,
  subject text,
  body text,
  attachments_count integer DEFAULT 0,
  matched_existing boolean DEFAULT false,
  created_new_lead boolean DEFAULT false,
  ai_ok boolean DEFAULT false,
  ai_notes text,
  raw jsonb,
  created_at timestamp with time zone DEFAULT now(),
  needs_review boolean DEFAULT false,
  ai_category text,
  ai_draft_reply text,
  ai_summary text,
  triaged_at timestamp with time zone,
  replied_at timestamp with time zone,
  replied_by text,
  owner_role text,
  provider_email_id text,
  html text
);

CREATE TABLE IF NOT EXISTS public.inquiries (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  customer_id uuid,
  category text,
  emirate text,
  role_needed text,
  raw_input text,
  spec jsonb,
  summary text,
  keywords text[],
  status text DEFAULT 'open'::text,
  created_at timestamp with time zone DEFAULT now(),
  drawing_file_path text,
  drawing_file_name text,
  boq jsonb,
  boq_confidence text,
  budget text,
  scope_type text,
  trades text[],
  brief_source text,
  hired_supplier_id bigint,
  completed_at timestamp with time zone,
  outcome text,
  no_quote_notified boolean DEFAULT false,
  drawing_redacted_paths text[],
  routing jsonb,
  pipeline_stage text,
  deal_owner text,
  stage_changed_at timestamp with time zone,
  expected_value numeric,
  lost_reason text,
  project_id uuid,
  completeness jsonb,
  rfq_ready boolean DEFAULT false,
  urgency text,
  parent_inquiry_id uuid,
  provenance jsonb,
  plausibility jsonb,
  summary_masked text,
  raw_input_masked text,
  budget_masked text,
  spec_masked jsonb,
  boq_masked jsonb,
  completeness_masked jsonb,
  rfq_no integer DEFAULT nextval('inquiries_rfq_no_seq'::regclass) NOT NULL,
  floor text,
  required_by date,
  delivery_window text,
  compliance_checklist jsonb,
  accepted_alternatives jsonb DEFAULT '[]'::jsonb NOT NULL,
  spec_offer_checked_at timestamp with time zone,
  spec_offer_attempts integer DEFAULT 0 NOT NULL,
  spec_offer_next_attempt_at timestamp with time zone,
  service_keys text[],
  lang text,
  repeat_of uuid
);

CREATE TABLE IF NOT EXISTS public.inquiry_answer (
  id bigint DEFAULT nextval('inquiry_answer_id_seq'::regclass) NOT NULL,
  group_id bigint NOT NULL,
  field_id text NOT NULL,
  value text,
  unit text,
  scope text NOT NULL,
  precedence answer_precedence NOT NULL,
  source_kind text NOT NULL,
  confirmed_at timestamp with time zone,
  confirmed_by text,
  superseded_by bigint,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.inquiry_answer_conflict (
  id bigint DEFAULT nextval('inquiry_answer_conflict_id_seq'::regclass) NOT NULL,
  group_id bigint NOT NULL,
  field_id text NOT NULL,
  blocking_scope text NOT NULL,
  opened_at timestamp with time zone DEFAULT now() NOT NULL,
  resolved_at timestamp with time zone,
  resolved_by text,
  resolution_reason text
);

CREATE TABLE IF NOT EXISTS public.inquiry_answer_conflict_value (
  id bigint DEFAULT nextval('inquiry_answer_conflict_value_id_seq'::regclass) NOT NULL,
  conflict_id bigint NOT NULL,
  value text,
  precedence answer_precedence NOT NULL,
  source_kind text NOT NULL,
  document_id text,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.inquiry_answer_corroboration (
  id bigint DEFAULT nextval('inquiry_answer_corroboration_id_seq'::regclass) NOT NULL,
  answer_id bigint NOT NULL,
  value text,
  normalised_value text,
  precedence answer_precedence NOT NULL,
  source_kind text NOT NULL,
  document_id text,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.inquiry_answer_document (
  id bigint DEFAULT nextval('inquiry_answer_document_id_seq'::regclass) NOT NULL,
  answer_id bigint NOT NULL,
  document_id text NOT NULL,
  page_or_sheet text,
  extraction_confidence numeric,
  original_text text,
  assigned_scope text,
  extracted_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.inquiry_answer_scope (
  answer_id bigint NOT NULL,
  workstream_id bigint NOT NULL
);

CREATE TABLE IF NOT EXISTS public.inquiry_cancellations (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  inquiry_id uuid NOT NULL,
  customer_id uuid,
  reason text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.inquiry_conversation_summary (
  inquiry_id uuid NOT NULL,
  customer_id uuid,
  summary jsonb NOT NULL,
  last_activity timestamp with time zone NOT NULL,
  built_at timestamp with time zone DEFAULT now() NOT NULL,
  method text DEFAULT 'deterministic'::text NOT NULL,
  originals_kept boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.inquiry_gate (
  id bigint DEFAULT nextval('inquiry_gate_id_seq'::regclass) NOT NULL,
  group_id bigint NOT NULL,
  workstream_id bigint,
  gate_key text NOT NULL,
  passed boolean,
  asserted_by text,
  asserted_at timestamp with time zone DEFAULT now() NOT NULL,
  state gate_state NOT NULL,
  state_reason text
);

CREATE TABLE IF NOT EXISTS public.inquiry_gate_required (
  gate_key text NOT NULL,
  level text NOT NULL,
  note text
);

CREATE TABLE IF NOT EXISTS public.inquiry_intake (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  customer_id uuid,
  email text,
  category text,
  status text DEFAULT 'needs_info'::text NOT NULL,
  raw_input text,
  turns jsonb DEFAULT '[]'::jsonb NOT NULL,
  brief jsonb,
  readiness integer DEFAULT 0 NOT NULL,
  missing jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.inquiry_matches (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  inquiry_id uuid,
  supplier_id bigint,
  similarity numeric,
  sent_at timestamp with time zone DEFAULT now(),
  match_reason text
);

CREATE TABLE IF NOT EXISTS public.inquiry_requirement (
  inquiry_id uuid NOT NULL,
  trades_required text[] DEFAULT '{}'::text[] NOT NULL,
  role_required text,
  emirate text,
  authority_required text[] DEFAULT '{}'::text[] NOT NULL,
  products_norm text[] DEFAULT '{}'::text[] NOT NULL,
  brands_specified text[] DEFAULT '{}'::text[] NOT NULL,
  project_type text,
  value_band numeric,
  scope_type text,
  confidence jsonb DEFAULT '{}'::jsonb NOT NULL,
  missing_fields text[] DEFAULT '{}'::text[] NOT NULL,
  parsed_at timestamp with time zone DEFAULT now() NOT NULL,
  parser_version text
);

CREATE TABLE IF NOT EXISTS public.inquiry_scope_disposition (
  id bigint DEFAULT nextval('inquiry_scope_disposition_id_seq'::regclass) NOT NULL,
  group_id bigint NOT NULL,
  trade_key text,
  scope_component text DEFAULT 'complete_trade_scope'::text NOT NULL,
  disposition text NOT NULL,
  specificity integer NOT NULL,
  source_kind text NOT NULL,
  evidence_source text NOT NULL,
  evidence_score numeric(4,3) NOT NULL,
  score_basis text DEFAULT 'rule_weight_provisional'::text NOT NULL,
  clause_index integer,
  clause_text text,
  matched_marker text,
  reason text NOT NULL,
  confirmation_status text DEFAULT 'inferred'::text NOT NULL,
  confirmed_by text,
  confirmed_at timestamp with time zone,
  actor text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  classification_basis text,
  responsible_party text,
  party_class text,
  party_role text,
  party_clause_index integer,
  sentence_index integer
);

CREATE TABLE IF NOT EXISTS public.inquiry_state_audit (
  id bigint DEFAULT nextval('inquiry_state_audit_id_seq'::regclass) NOT NULL,
  group_id bigint,
  workstream_id bigint,
  event text NOT NULL,
  detail jsonb,
  actor text,
  at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.inquiry_supplier_brief (
  id bigint DEFAULT nextval('inquiry_supplier_brief_id_seq'::regclass) NOT NULL,
  inquiry_id uuid NOT NULL,
  version integer NOT NULL,
  frozen_at timestamp with time zone DEFAULT now() NOT NULL,
  frozen_reason text DEFAULT 'dispatch'::text NOT NULL,
  brief jsonb NOT NULL,
  brief_sha256 text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.inquiry_trade_candidate (
  id bigint DEFAULT nextval('inquiry_trade_candidate_id_seq'::regclass) NOT NULL,
  group_id bigint NOT NULL,
  trade_key text NOT NULL,
  status text DEFAULT 'proposed'::text NOT NULL,
  evidence_source text NOT NULL,
  match_reason text NOT NULL,
  evidence_score numeric(4,3) NOT NULL,
  requires_confirmation boolean DEFAULT true NOT NULL,
  proposed_at timestamp with time zone DEFAULT now() NOT NULL,
  confirmed_at timestamp with time zone,
  confirmed_by text,
  rejected_at timestamp with time zone,
  rejected_by text,
  rejection_reason text,
  inactivated_at timestamp with time zone,
  activated_at timestamp with time zone,
  workstream_id bigint,
  score_basis text DEFAULT 'rule_weight_provisional'::text NOT NULL,
  confirmation_factors jsonb
);

CREATE TABLE IF NOT EXISTS public.inquiry_trade_candidate_evidence (
  id bigint DEFAULT nextval('inquiry_trade_candidate_evidence_id_seq'::regclass) NOT NULL,
  candidate_id bigint NOT NULL,
  evidence_source text NOT NULL,
  matched_term text,
  subcategory_slug text,
  catalog_num integer,
  document_id text,
  document_approved boolean,
  evidence_score numeric(4,3),
  detail jsonb,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL,
  score_basis text DEFAULT 'rule_weight_provisional'::text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.inquiry_trade_clarification (
  id bigint DEFAULT nextval('inquiry_trade_clarification_id_seq'::regclass) NOT NULL,
  group_id bigint NOT NULL,
  question_en text NOT NULL,
  question_ar text,
  options text[] NOT NULL,
  reason text NOT NULL,
  asked_at timestamp with time zone DEFAULT now() NOT NULL,
  answered_at timestamp with time zone,
  answered_by text,
  answer text[]
);

CREATE TABLE IF NOT EXISTS public.inquiry_workstream (
  id bigint DEFAULT nextval('inquiry_workstream_id_seq'::regclass) NOT NULL,
  group_id bigint NOT NULL,
  trade_key text NOT NULL,
  route_catalog_num integer,
  active boolean DEFAULT true NOT NULL,
  activated_at timestamp with time zone DEFAULT now() NOT NULL,
  deactivated_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.inquiry_workstream_group (
  id bigint DEFAULT nextval('inquiry_workstream_group_id_seq'::regclass) NOT NULL,
  inquiry_id uuid NOT NULL,
  rfq_mode text DEFAULT 'coordinated'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.inquiry_workstream_requirement (
  id bigint DEFAULT nextval('inquiry_workstream_requirement_id_seq'::regclass) NOT NULL,
  workstream_id bigint NOT NULL,
  question_id text,
  field_id text NOT NULL,
  mandatory boolean DEFAULT false NOT NULL,
  applies_when jsonb
);

CREATE TABLE IF NOT EXISTS public.institutional_memory (
  id bigint DEFAULT nextval('institutional_memory_id_seq'::regclass) NOT NULL,
  kind text NOT NULL,
  subject_type text,
  subject_id text,
  category_slug text,
  headline text NOT NULL,
  detail text NOT NULL,
  outcome text,
  money_aed numeric,
  learned_by text,
  confidence numeric,
  evidence_ref text,
  visible_to text[] DEFAULT '{}'::text[],
  occurred_at timestamp with time zone DEFAULT now() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  os_key text
);

CREATE TABLE IF NOT EXISTS public.intake_trade_taxonomy (
  intake_slug text NOT NULL,
  trade_codes text[] NOT NULL,
  note text
);

CREATE TABLE IF NOT EXISTS public.integration_matrix (
  service text NOT NULL,
  purpose text NOT NULL,
  credential_keys text NOT NULL,
  used_by_fns text,
  owner_dept text,
  configured boolean DEFAULT true NOT NULL,
  notes text,
  monthly_cost_aed numeric,
  sla_uptime_pct numeric,
  renewal_date date,
  alternatives text,
  usage_limit_note text,
  last_reviewed date
);

CREATE TABLE IF NOT EXISTS public.internal_credential (
  id bigint DEFAULT nextval('internal_credential_id_seq'::regclass) NOT NULL,
  context text NOT NULL,
  label text,
  secret_hash text NOT NULL,
  scope text[] NOT NULL,
  is_legacy boolean DEFAULT false NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  rotated_at timestamp with time zone,
  expires_at timestamp with time zone,
  retired_at timestamp with time zone,
  last_used_at timestamp with time zone,
  last_function text,
  use_count bigint DEFAULT 0 NOT NULL
);

CREATE TABLE IF NOT EXISTS public.internal_credential_audit (
  id bigint DEFAULT nextval('internal_credential_audit_id_seq'::regclass) NOT NULL,
  at timestamp with time zone DEFAULT now() NOT NULL,
  credential_id bigint,
  context text,
  function_name text,
  allowed boolean NOT NULL,
  reason text NOT NULL,
  detail jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS public.inv_items (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  sku text,
  name text NOT NULL,
  uom text DEFAULT 'unit'::text NOT NULL,
  category text,
  inventory_account text DEFAULT '1500'::text NOT NULL,
  cogs_account text DEFAULT '5000'::text NOT NULL,
  reorder_point numeric(18,4) DEFAULT 0 NOT NULL,
  is_active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.invite_brake (
  id bigint DEFAULT nextval('invite_brake_id_seq'::regclass) NOT NULL,
  source text NOT NULL,
  why text NOT NULL,
  fired_at timestamp with time zone DEFAULT now() NOT NULL,
  resumed_at timestamp with time zone,
  resume_note text,
  restarted_by_seat boolean DEFAULT false NOT NULL,
  ceo_task_opened_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.invite_placement_bar (
  id boolean DEFAULT true NOT NULL,
  sender text DEFAULT 'supplier@quotesdone.com'::text NOT NULL,
  max_age interval DEFAULT '7 days'::interval NOT NULL,
  microsoft_min_inbox_pct numeric DEFAULT 80 NOT NULL,
  google_max_spam_pct numeric DEFAULT 20 NOT NULL,
  google_min_delivered_pct numeric DEFAULT 80 NOT NULL,
  yahoo_aol_min_inbox_pct numeric DEFAULT 80 NOT NULL,
  note text NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_by text DEFAULT 'it_engineer'::text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.invite_placement_check (
  dubai_day date NOT NULL,
  token text NOT NULL,
  from_address text NOT NULL,
  subject text NOT NULL,
  gmail_to text NOT NULL,
  outlook_to text NOT NULL,
  gmail_notification_id bigint,
  outlook_notification_id bigint,
  queued_at timestamp with time zone DEFAULT now() NOT NULL,
  gmail_folder text,
  outlook_folder text,
  gmail_detail jsonb DEFAULT '{}'::jsonb NOT NULL,
  outlook_detail jsonb DEFAULT '{}'::jsonb NOT NULL,
  reads integer DEFAULT 0 NOT NULL,
  last_read_at timestamp with time zone,
  verdict text DEFAULT 'pending'::text NOT NULL,
  decided_at timestamp with time zone,
  paused boolean DEFAULT false NOT NULL,
  note text
);

CREATE TABLE IF NOT EXISTS public.invite_schedule (
  day date NOT NULL,
  planned integer DEFAULT 0 NOT NULL,
  sent integer DEFAULT 0 NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  note text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.it_access_known (
  system text NOT NULL,
  principal text NOT NULL,
  reason text NOT NULL,
  accepted_by text NOT NULL,
  accepted_at timestamp with time zone DEFAULT now() NOT NULL,
  last_seen_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.it_change_acceptance (
  txid bigint NOT NULL,
  accepted_by text NOT NULL,
  reason text NOT NULL,
  accepted_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.it_change_revision (
  rev text NOT NULL,
  verdict text DEFAULT 'pending'::text NOT NULL,
  pr_number integer,
  first_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  checked_at timestamp with time zone,
  detail jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS public.it_change_source (
  match_on text NOT NULL,
  pattern text NOT NULL,
  meaning text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.it_cost_watch_week (
  week_ending date NOT NULL,
  provider text NOT NULL,
  basis text NOT NULL,
  period_days integer NOT NULL,
  this_aed numeric,
  prior_aed numeric,
  jumped boolean DEFAULT false NOT NULL,
  owner_seat text,
  cause text,
  detail jsonb DEFAULT '{}'::jsonb NOT NULL,
  measured_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.it_credential_class (
  credential text NOT NULL,
  rotation text NOT NULL,
  integrations text[] DEFAULT '{}'::text[] NOT NULL,
  expiry_item text,
  why text NOT NULL,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.it_credential_rotation (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  context text NOT NULL,
  old_id bigint,
  new_id bigint,
  secret_key text NOT NULL,
  rotated_at timestamp with time zone DEFAULT now() NOT NULL,
  overlap_until timestamp with time zone NOT NULL,
  status text DEFAULT 'overlap'::text NOT NULL,
  closed_at timestamp with time zone,
  note text,
  provider text,
  old_ref text,
  new_ref text
);

CREATE TABLE IF NOT EXISTS public.it_duty_schedule (
  duty text NOT NULL,
  every interval NOT NULL,
  note text NOT NULL,
  owner_seat text NOT NULL,
  last_ok_at timestamp with time zone,
  last_result jsonb
);

CREATE TABLE IF NOT EXISTS public.it_engineer_finding (
  issue_key text NOT NULL,
  title text NOT NULL,
  where_it_is text NOT NULL,
  blast text NOT NULL,
  affected integer DEFAULT 0 NOT NULL,
  evidence jsonb DEFAULT '{}'::jsonb NOT NULL,
  ruled_out text[] DEFAULT '{}'::text[] NOT NULL,
  undetermined text[] DEFAULT '{}'::text[] NOT NULL,
  raised_by text DEFAULT 'it_engineer'::text NOT NULL,
  started_at timestamp with time zone DEFAULT now() NOT NULL,
  last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  seen_count integer DEFAULT 1 NOT NULL,
  closed_at timestamp with time zone,
  close_note text,
  alerted_at timestamp with time zone,
  alerted_severity text,
  alerted_affected integer,
  alert_count integer DEFAULT 0 NOT NULL,
  close_notified_at timestamp with time zone,
  notification_id bigint
);

CREATE TABLE IF NOT EXISTS public.it_engineer_knowledge (
  record_id text NOT NULL,
  record_type text NOT NULL,
  domain text,
  title text NOT NULL,
  content text NOT NULL,
  structured_data jsonb DEFAULT '{}'::jsonb NOT NULL,
  source_ids text[] DEFAULT '{}'::text[] NOT NULL,
  epistemic_status text NOT NULL,
  jurisdiction text,
  pack_id text NOT NULL,
  pack_version text NOT NULL,
  body_sha256 text NOT NULL,
  runtime_index_eligible boolean DEFAULT true NOT NULL,
  authority_effect text DEFAULT 'none'::text NOT NULL,
  tags text[] DEFAULT '{}'::text[] NOT NULL,
  updated_at timestamp with time zone,
  ingested_at timestamp with time zone DEFAULT now() NOT NULL,
  embedding_gte vector(384),
  search tsvector
);

CREATE TABLE IF NOT EXISTS public.it_engineer_scanner (
  scanner text NOT NULL,
  last_beat_at timestamp with time zone DEFAULT now() NOT NULL,
  last_ok_at timestamp with time zone,
  last_error text,
  max_gap_minutes integer DEFAULT 60 NOT NULL,
  registered_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.it_expected_table_growth (
  relid text NOT NULL,
  cause text NOT NULL,
  writer text NOT NULL,
  until date NOT NULL,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.it_expiry (
  item text NOT NULL,
  kind text NOT NULL,
  expires_on date,
  owner_seat text NOT NULL,
  route text NOT NULL,
  source text NOT NULL,
  checked_at timestamp with time zone DEFAULT now() NOT NULL,
  warn_days integer[] DEFAULT '{60,30}'::integer[] NOT NULL,
  secret_fingerprint text,
  secret_seen_since timestamp with time zone,
  never_expires boolean DEFAULT false NOT NULL
);

CREATE TABLE IF NOT EXISTS public.it_finding_closure (
  issue_key text NOT NULL,
  duty text NOT NULL,
  owner_seat text NOT NULL,
  opened_at timestamp with time zone NOT NULL,
  deadline timestamp with time zone NOT NULL,
  reading_at_open jsonb DEFAULT '{}'::jsonb NOT NULL,
  last_reading jsonb DEFAULT '{}'::jsonb NOT NULL,
  last_measured_at timestamp with time zone,
  closed_at timestamp with time zone,
  reading_at_close jsonb,
  reopen_count integer DEFAULT 0 NOT NULL,
  overdue_handoff_id bigint
);

CREATE TABLE IF NOT EXISTS public.it_founder_decision_class (
  issue_key_like text NOT NULL,
  to_founder boolean NOT NULL,
  why text NOT NULL,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL,
  founder_category text
);

CREATE TABLE IF NOT EXISTS public.it_game_day_run (
  id bigint DEFAULT nextval('it_game_day_run_id_seq'::regclass) NOT NULL,
  run_month date NOT NULL,
  scenario text NOT NULL,
  ran_at timestamp with time zone DEFAULT now() NOT NULL,
  detected boolean NOT NULL,
  recovered boolean NOT NULL,
  passed boolean NOT NULL,
  detection_ms numeric,
  recovery_ms numeric,
  checks jsonb DEFAULT '{}'::jsonb NOT NULL,
  error text
);

CREATE TABLE IF NOT EXISTS public.it_hold_signature (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  subject text NOT NULL,
  counts_match jsonb DEFAULT '{}'::jsonb NOT NULL,
  note_like text,
  rule text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.it_incident (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  handoff_id bigint NOT NULL,
  issue_key text NOT NULL,
  title text NOT NULL,
  what text NOT NULL,
  impact text NOT NULL,
  started_at timestamp with time zone NOT NULL,
  ended_at timestamp with time zone,
  cause text,
  fix text,
  regression_check text,
  playbook_class text,
  not_automatable_reason text,
  recorded_by text,
  pdf_path text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  customer_impact text,
  customer_note_en text,
  customer_note_ar text
);

CREATE TABLE IF NOT EXISTS public.it_integration_external_cause (
  id bigint DEFAULT nextval('it_integration_external_cause_id_seq'::regclass) NOT NULL,
  integration text NOT NULL,
  external_party text NOT NULL,
  ticket_ref text NOT NULL,
  owner_seat text DEFAULT 'it_engineer'::text NOT NULL,
  opened_on date NOT NULL,
  thread_hint text,
  note text,
  last_checked_at timestamp with time zone,
  last_reply_at timestamp with time zone,
  last_reply_excerpt text,
  reply_needs_founder boolean DEFAULT false NOT NULL,
  founder_told_at timestamp with time zone,
  closed_at timestamp with time zone,
  close_note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.it_load_test_run (
  id bigint DEFAULT nextval('it_load_test_run_id_seq'::regclass) NOT NULL,
  run_at timestamp with time zone NOT NULL,
  journey text NOT NULL,
  step_ops integer NOT NULL,
  total_ms numeric NOT NULL,
  ops_per_sec numeric,
  p95_ms numeric,
  max_ms numeric,
  within_budget boolean NOT NULL,
  breakpoint boolean DEFAULT false NOT NULL,
  detail jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS public.it_model_consumer (
  consumer text NOT NULL,
  owner_seat text NOT NULL,
  why_a_model text NOT NULL,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL,
  expected_usd_day numeric
);

CREATE TABLE IF NOT EXISTS public.it_playbook (
  failure_class text NOT NULL,
  issue_prefix text NOT NULL,
  remedy text,
  remedy_routine text,
  not_automatable_reason text,
  regression_check text NOT NULL,
  added_by text NOT NULL,
  added_at timestamp with time zone DEFAULT now() NOT NULL,
  typical_cause text
);

CREATE TABLE IF NOT EXISTS public.it_postmaster_reading (
  domain text NOT NULL,
  read_on date NOT NULL,
  basis text NOT NULL,
  stats_day date,
  spam_ratio numeric,
  spam_lower numeric,
  spam_upper numeric,
  reputation text,
  spf_ratio numeric,
  dkim_ratio numeric,
  dmarc_ratio numeric,
  reason text,
  verdict jsonb DEFAULT '{}'::jsonb NOT NULL,
  line text NOT NULL,
  paused_at timestamp with time zone,
  read_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.it_query_stat_snapshot (
  queryid bigint NOT NULL,
  calls bigint NOT NULL,
  total_exec_time double precision NOT NULL,
  taken_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.it_refusal_policy (
  subject text NOT NULL,
  reason_key text NOT NULL,
  justification text NOT NULL,
  added_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.it_restore_drill_result (
  id bigint DEFAULT nextval('it_restore_drill_result_id_seq'::regclass) NOT NULL,
  ran_at timestamp with time zone DEFAULT now() NOT NULL,
  subject text NOT NULL,
  ok boolean NOT NULL,
  detail jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS public.it_restore_drill_table (
  table_name text NOT NULL,
  key_column text NOT NULL,
  note text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.it_security_baseline (
  object text NOT NULL,
  kind text NOT NULL,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL,
  reason text NOT NULL,
  accepted_by text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.it_sender_health_daily (
  day date NOT NULL,
  sent_7d integer NOT NULL,
  hard_bounces_7d integer NOT NULL,
  complaints_7d integer NOT NULL,
  bounce_rate numeric,
  complaint_rate numeric,
  whatsapp_quality text,
  blocklisted integer DEFAULT 0 NOT NULL,
  dmarc jsonb,
  breaches text[] DEFAULT '{}'::text[] NOT NULL,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.it_spend_daily (
  day date NOT NULL,
  source text NOT NULL,
  amount_minor bigint NOT NULL,
  currency text NOT NULL,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.it_table_size_daily (
  day date NOT NULL,
  relid text NOT NULL,
  bytes bigint NOT NULL
);

CREATE TABLE IF NOT EXISTS public.it_threshold (
  key text NOT NULL,
  value numeric,
  unit text NOT NULL,
  basis text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.it_watch_finding (
  detector_key text NOT NULL,
  detector text NOT NULL,
  subject text NOT NULL,
  state text NOT NULL,
  severity text NOT NULL,
  title text NOT NULL,
  evidence jsonb DEFAULT '{}'::jsonb NOT NULL,
  opened_at timestamp with time zone DEFAULT now() NOT NULL,
  last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  seen_count integer DEFAULT 1 NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  resolved_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.it_watch_queue (
  queue_key text NOT NULL,
  table_name text NOT NULL,
  pending_predicate text NOT NULL,
  ts_column text DEFAULT 'created_at'::text NOT NULL,
  stall_minutes integer NOT NULL,
  surface text DEFAULT 'internal'::text NOT NULL,
  enabled boolean DEFAULT true NOT NULL,
  note text,
  drain_column text
);

CREATE TABLE IF NOT EXISTS public.it_watch_subject (
  subject text NOT NULL,
  kind text DEFAULT 'edge_function'::text NOT NULL,
  public_surface boolean DEFAULT false NOT NULL,
  source text DEFAULT 'supabase/config.toml verify_jwt'::text NOT NULL,
  note text,
  verify_jwt boolean,
  secret_gated boolean
);

CREATE TABLE IF NOT EXISTS public.it_watch_tick (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  ran_at timestamp with time zone DEFAULT now() NOT NULL,
  findings integer DEFAULT 0 NOT NULL,
  worst text,
  site_ms integer,
  site_status integer,
  detail jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS public.kb_category_aliases (
  category text NOT NULL,
  maps_to text NOT NULL,
  rationale text
);

CREATE TABLE IF NOT EXISTS public.kb_category_stats (
  category text NOT NULL,
  source_kind text NOT NULL,
  chunks bigint NOT NULL,
  refreshed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.kb_chunk_quarantine (
  id bigint NOT NULL,
  source_kind text,
  source_id text,
  category text,
  title text,
  content text,
  citation text,
  effective_date date,
  created_at timestamp with time zone,
  category_norm text,
  reason text NOT NULL,
  quarantined_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.kb_chunks (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  source_kind text NOT NULL,
  source_id text,
  category text,
  title text,
  content text NOT NULL,
  citation text,
  effective_date date,
  fts tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, ((COALESCE(title, ''::text) || ' '::text) || COALESCE(content, ''::text)))) STORED,
  created_at timestamp with time zone DEFAULT now(),
  embedding_gte vector(384),
  category_norm text GENERATED ALWAYS AS (NULLIF(regexp_replace(lower(COALESCE(category, ''::text)), '^cat:'::text, ''::text), ''::text)) STORED,
  embed_claimed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.kb_chunks_old (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  source_kind text NOT NULL,
  source_id text,
  category text,
  title text,
  content text NOT NULL,
  citation text,
  effective_date date,
  fts tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, ((COALESCE(title, ''::text) || ' '::text) || COALESCE(content, ''::text)))) STORED,
  created_at timestamp with time zone DEFAULT now(),
  embedding_gte vector(384),
  category_norm text GENERATED ALWAYS AS (NULLIF(regexp_replace(lower(COALESCE(category, ''::text)), '^cat:'::text, ''::text), ''::text)) STORED,
  embed_claimed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.kb_chunks_swap_log (
  seq bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id bigint NOT NULL,
  logged_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.kb_citation_jurisdiction (
  citation_md5 text NOT NULL,
  citation text NOT NULL,
  jurisdiction text NOT NULL,
  held_id bigint,
  reasoned_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.kb_embed_inflight (
  request_id bigint NOT NULL,
  chunk_id bigint NOT NULL,
  queued_at timestamp with time zone DEFAULT now() NOT NULL,
  text_md5 text,
  failed_at timestamp with time zone,
  status_code integer
);

CREATE TABLE IF NOT EXISTS public.kb_embed_priority (
  category text NOT NULL,
  tier integer NOT NULL,
  reason text NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.kb_operational_alias (
  catalog_num integer NOT NULL,
  language text NOT NULL,
  alias text NOT NULL,
  alias_norm text NOT NULL,
  weight integer DEFAULT 2 NOT NULL,
  negative boolean DEFAULT false NOT NULL,
  source text
);

CREATE TABLE IF NOT EXISTS public.kb_operational_route (
  catalog_num integer NOT NULL,
  route_key text NOT NULL,
  expected_catalog_slug text,
  catalog_name text NOT NULL,
  route_type text NOT NULL,
  coverage_status text NOT NULL,
  version text NOT NULL,
  manifest jsonb NOT NULL,
  ingestion_run_id uuid,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  regulatory_coverage_status text DEFAULT 'requires_review'::text NOT NULL,
  regulatory_coverage_note text,
  regulatory_reviewed_by text,
  regulatory_reviewed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.kb_operational_route_map (
  catalog_num integer NOT NULL,
  package_slug text NOT NULL,
  subcategory_slug text NOT NULL,
  priority text DEFAULT 'primary'::text NOT NULL,
  package_zip text,
  package_number integer
);

CREATE TABLE IF NOT EXISTS public.kb_operational_route_test (
  test_id text NOT NULL,
  catalog_num integer,
  input text NOT NULL,
  expected_action text NOT NULL,
  expected jsonb,
  last_result jsonb,
  last_run_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.kb_purge_ledger (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  verdict text NOT NULL,
  clause smallint NOT NULL,
  source_kind text NOT NULL,
  category text,
  rows bigint,
  bytes bigint,
  batch_no integer,
  id_from bigint,
  id_to bigint,
  note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.kb_revisions (
  id bigint DEFAULT nextval('kb_revisions_id_seq'::regclass) NOT NULL,
  entry_kind text NOT NULL,
  entry_ref text NOT NULL,
  version integer NOT NULL,
  content text,
  status text DEFAULT 'published'::text NOT NULL,
  author text,
  reviewer text,
  review_notes text,
  ai_validation jsonb,
  created_at timestamp with time zone DEFAULT now(),
  decided_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.kb_route_scope_trigger (
  catalog_num integer NOT NULL,
  trigger_scope text NOT NULL,
  match_regex text NOT NULL,
  requires_escalation boolean DEFAULT true NOT NULL,
  rationale text NOT NULL,
  source_doc text DEFAULT 'docs/phases/PHASE2_WORKSTREAM_ORDER.md section 2'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.kb_trim_hash (
  id bigint NOT NULL,
  k text NOT NULL,
  pref smallint NOT NULL,
  is_qd boolean NOT NULL,
  clause smallint,
  keeper_id bigint
);

CREATE TABLE IF NOT EXISTS public.kb_trim_plan (
  id bigint NOT NULL,
  clause smallint NOT NULL,
  planned_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.kb_usage_log (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  query text,
  category text,
  agent text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.knowledge_domain (
  domain_key text NOT NULL,
  name text NOT NULL,
  kind text NOT NULL,
  description text,
  source text,
  active boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.knowledge_exam_questions (
  id bigint DEFAULT nextval('knowledge_exam_questions_id_seq'::regclass) NOT NULL,
  agent_key text NOT NULL,
  question text NOT NULL,
  reference_answer text,
  topic text,
  difficulty text DEFAULT 'core'::text,
  times_asked integer DEFAULT 0,
  last_asked timestamp with time zone,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.knowledge_exam_results (
  id bigint DEFAULT nextval('knowledge_exam_results_id_seq'::regclass) NOT NULL,
  agent_key text NOT NULL,
  question_id bigint,
  examinee_answer text,
  verdict text,
  grader_answer text,
  grader_confidence numeric,
  converged boolean DEFAULT false,
  gap_fact text,
  filled boolean DEFAULT false,
  knowledge_id bigint,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.knowledge_ingestion_run (
  run_id uuid DEFAULT gen_random_uuid() NOT NULL,
  package text NOT NULL,
  package_version text NOT NULL,
  generation text NOT NULL,
  started_at timestamp with time zone DEFAULT now() NOT NULL,
  finished_at timestamp with time zone,
  status text DEFAULT 'running'::text NOT NULL,
  counts jsonb DEFAULT '{}'::jsonb NOT NULL,
  note text
);

CREATE TABLE IF NOT EXISTS public.knowledge_ingestion_undo (
  run_id uuid NOT NULL,
  table_name text NOT NULL,
  key text NOT NULL,
  existed boolean NOT NULL,
  prev_row jsonb
);

CREATE TABLE IF NOT EXISTS public.knowledge_internal_figure_record (
  record_id text NOT NULL,
  why text NOT NULL,
  added_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.knowledge_kpi_snapshots (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
  kpis jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.knowledge_library (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  origin_store text NOT NULL,
  origin_id text NOT NULL,
  title text,
  content text NOT NULL,
  content_md5 text GENERATED ALWAYS AS (md5(content)) STORED,
  trade text,
  tags text[] DEFAULT '{}'::text[] NOT NULL,
  seats text[] NOT NULL,
  lang text DEFAULT 'en'::text NOT NULL,
  source_ref text,
  source_ids text[] DEFAULT '{}'::text[] NOT NULL,
  verified boolean DEFAULT false NOT NULL,
  runtime_eligible boolean DEFAULT true NOT NULL,
  embedding_gte vector(384),
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.knowledge_library_origin (
  origin_store text NOT NULL,
  origin_id text NOT NULL,
  library_id bigint NOT NULL,
  source_ref text,
  source_ids text[] DEFAULT '{}'::text[] NOT NULL
);

CREATE TABLE IF NOT EXISTS public.knowledge_library_state (
  id smallint DEFAULT 1 NOT NULL,
  reconciled boolean DEFAULT false NOT NULL,
  verdict jsonb DEFAULT '{}'::jsonb NOT NULL,
  checked_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.knowledge_ml_claim (
  src text NOT NULL,
  row_id text NOT NULL,
  claimed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.knowledge_ml_status (
  id boolean DEFAULT true NOT NULL,
  priority_complete_at timestamp with time zone,
  note text
);

CREATE TABLE IF NOT EXISTS public.knowledge_module_standard (
  module text NOT NULL,
  ord integer NOT NULL,
  spec_layers text NOT NULL,
  intent text NOT NULL,
  min_chars integer DEFAULT 600 NOT NULL,
  priority integer DEFAULT 4 NOT NULL,
  required boolean DEFAULT true NOT NULL,
  added_in text DEFAULT 'v2'::text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.knowledge_vector_ml (
  src text NOT NULL,
  row_id text NOT NULL,
  text_hash text NOT NULL,
  embedding vector(384) NOT NULL,
  embedded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.lead_category (
  lead_id bigint NOT NULL,
  slug text NOT NULL,
  score integer DEFAULT 0 NOT NULL,
  is_primary boolean DEFAULT false NOT NULL,
  method text DEFAULT 'keyword_v1'::text NOT NULL,
  evidence text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.lead_email_check (
  lead_id bigint NOT NULL,
  email_md5 text NOT NULL,
  verdict text NOT NULL,
  reason text NOT NULL,
  mailbox text,
  mx_kind text,
  checked_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.lead_prospect (
  id bigint DEFAULT nextval('lead_prospect_id_seq'::regclass) NOT NULL,
  run_id bigint NOT NULL,
  company_name text NOT NULL,
  trade_code text,
  emirate text,
  website text,
  domain text,
  phone_e164 text,
  phone_kind text,
  email text,
  email_status text,
  contact_name text,
  contact_title text,
  place_id text,
  query text,
  field_sources jsonb DEFAULT '{}'::jsonb NOT NULL,
  collected_at timestamp with time zone DEFAULT now() NOT NULL,
  status text NOT NULL,
  status_reason text,
  promoted_lead_id bigint,
  model_answer text
);

CREATE TABLE IF NOT EXISTS public.lead_sourcing_run (
  id bigint DEFAULT nextval('lead_sourcing_run_id_seq'::regclass) NOT NULL,
  kind text NOT NULL,
  status text DEFAULT 'done'::text NOT NULL,
  reserved_serper_credits numeric DEFAULT 0 NOT NULL,
  reserved_llm_usd numeric DEFAULT 0 NOT NULL,
  started_at timestamp with time zone DEFAULT now() NOT NULL,
  run_day date DEFAULT ((now() AT TIME ZONE 'Asia/Dubai'::text))::date NOT NULL,
  emirate text NOT NULL,
  trades text[] NOT NULL,
  queries integer DEFAULT 0 NOT NULL,
  serper_credits numeric DEFAULT 0 NOT NULL,
  usd_per_credit numeric DEFAULT 0.001 NOT NULL,
  places integer DEFAULT 0 NOT NULL,
  sites_crawled integer DEFAULT 0 NOT NULL,
  pages_fetched integer DEFAULT 0 NOT NULL,
  robots_refused integer DEFAULT 0 NOT NULL,
  prospects integer DEFAULT 0 NOT NULL,
  complete integer DEFAULT 0 NOT NULL,
  duplicates integer DEFAULT 0 NOT NULL,
  suppressed integer DEFAULT 0 NOT NULL,
  promoted integer DEFAULT 0 NOT NULL,
  model_calls integer DEFAULT 0 NOT NULL,
  linkedin_queries integer DEFAULT 0 NOT NULL,
  llm_cost_usd numeric DEFAULT 0 NOT NULL,
  by_trade jsonb DEFAULT '{}'::jsonb NOT NULL,
  errors jsonb DEFAULT '[]'::jsonb NOT NULL,
  handoff_id bigint,
  read_by_ceo_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.lead_subcategory (
  lead_id bigint NOT NULL,
  sub_slug text NOT NULL,
  domain_slug text NOT NULL,
  score integer DEFAULT 0 NOT NULL,
  is_primary boolean DEFAULT false NOT NULL,
  method text DEFAULT 'keyword_v2'::text NOT NULL,
  evidence text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.lead_trade_class (
  lead_id bigint NOT NULL,
  trade_code text,
  confidence numeric,
  evidence text NOT NULL,
  shortlist jsonb DEFAULT '[]'::jsonb NOT NULL,
  shortlist_agreed boolean,
  held_id bigint,
  decided_by text DEFAULT 'reasoning'::text NOT NULL,
  decided_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.lead_trade_map (
  trade_key text NOT NULL,
  catalog_slug text,
  confidence text DEFAULT 'high'::text NOT NULL,
  note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.leads (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  sector text,
  sub_type text,
  company_name text NOT NULL,
  phone text,
  phone_e164 text,
  website text,
  maps_website text,
  domain text,
  street text,
  city text,
  emirate text,
  rating numeric,
  reviews integer,
  rating_maps numeric,
  reviews_maps integer,
  categories text,
  maps_url text,
  place_id text,
  email text,
  email_domain text,
  email_verified text,
  instagram text,
  whatsapp text,
  facebook text,
  website_status text,
  permanently_closed boolean DEFAULT false,
  enrich_source text,
  source text,
  scraped_at date,
  contacted boolean DEFAULT false,
  signed boolean DEFAULT false,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  description text,
  founded_year integer,
  company_type text,
  company_size text,
  business_role text,
  products text,
  services text,
  certifications text,
  scale text,
  capability_summary text,
  embedding vector(256),
  embedding_gte vector(384),
  claimed boolean DEFAULT false,
  contact_name text,
  service_emirates text[],
  trade_license_no text,
  verified boolean DEFAULT false,
  portal_updated_at timestamp with time zone,
  trn text,
  license_authority text,
  license_expiry date,
  license_doc_name text,
  signatory_name text,
  emirates_id text,
  accepted_terms_at timestamp with time zone,
  accepted_terms_version text,
  claimed_by text,
  license_doc_path text,
  email_shared boolean DEFAULT false,
  linkedin text,
  employee_count integer,
  business_hours text,
  catalogue_pdfs text,
  registration_status text,
  registration_paid_at timestamp with time zone,
  registration_expires_at timestamp with time zone,
  registration_fee_due numeric,
  egr_doc_path text,
  egr_doc_name text,
  egr_number text,
  approval_status text,
  ai_review_notes text,
  ai_review_flags jsonb,
  ai_reviewed_at timestamp with time zone,
  registration_submitted_at timestamp with time zone,
  app_rating numeric,
  app_reviews integer DEFAULT 0,
  invite_status text,
  invited_at timestamp with time zone,
  lifecycle_stage text,
  banned boolean DEFAULT false,
  banned_reason text,
  chat_strikes integer DEFAULT 0,
  verification_status text DEFAULT 'unverified'::text,
  owner_dob date,
  owner_email_verified boolean DEFAULT false NOT NULL,
  license_city text,
  doc_extracted_at timestamp with time zone,
  name_corrected_from text,
  catalog_doc_paths text[],
  company_profile_doc_path text,
  approved_at timestamp with time zone,
  approval_decided_by text,
  rejection_reason text,
  tags text[],
  wa_optin boolean DEFAULT false,
  signed_terms_url text,
  signed_terms_path text,
  signed_terms_at timestamp with time zone,
  accepted_terms_ip text,
  matching_blocked boolean DEFAULT false NOT NULL,
  matching_block_reason text,
  rv_reveals integer DEFAULT 0 NOT NULL,
  rv_responded integer DEFAULT 0 NOT NULL,
  rv_response_rate numeric,
  rv_nonresponse_refunds integer DEFAULT 0 NOT NULL,
  vat_number text,
  vat_doc_path text,
  insurance_doc_path text,
  insurance_expiry date,
  manufacturer_authorizations jsonb,
  machinery jsonb,
  team_size integer,
  engineers_count integer,
  warehouse_area text,
  brands_carried jsonb,
  client_references jsonb,
  iso_certifications jsonb,
  capability_score integer,
  iso_expiry date,
  iso_doc_path text,
  manufacturer_auth_expiry date,
  manufacturer_auth_doc_path text,
  capability_enriched_at timestamp with time zone,
  locale text DEFAULT 'en'::text NOT NULL,
  owner_phone_verified boolean DEFAULT false,
  founding_rank integer,
  subscription_exempt boolean DEFAULT false NOT NULL,
  subscription_paid_until date,
  claim_token uuid DEFAULT gen_random_uuid() NOT NULL,
  invite_trades text[],
  license_activity text,
  licence_gate_reason text,
  exception_opened_at timestamp with time zone,
  exception_due_at timestamp with time zone,
  exception_reminders integer DEFAULT 0 NOT NULL,
  exception_last_reminder_at timestamp with time zone,
  exception_closed_at timestamp with time zone,
  exception_outcome text,
  enrich_retry jsonb,
  invite_followups integer DEFAULT 0 NOT NULL,
  invite_last_followup_at timestamp with time zone,
  accepted_terms_sha256 text,
  collaboration_hold_at timestamp with time zone,
  is_demo boolean GENERATED ALWAYS AS ((fn_is_demo_email(email) OR fn_is_demo_email(claimed_by) OR (fn_is_demo_phone(phone) AND (COALESCE(source, ''::text) <> 'marketing_sourcing'::text)) OR ('qd_demo'::text = ANY (COALESCE(tags, '{}'::text[]))) OR (COALESCE(company_name, ''::text) ~* '^ZZ DEMO([^a-z]|$)'::text) OR (COALESCE(company_name, ''::text) ~~ 'QD Demo %'::text) OR (COALESCE(source, ''::text) = ANY (ARRAY['demo_factory'::text, 'qd_demo_fixture'::text])))) STORED,
  whatsapp_phone text,
  whatsapp_verified_at timestamp with time zone,
  whatsapp_opt text,
  whatsapp_asked_at timestamp with time zone,
  invite_clicked_at timestamp with time zone,
  registration_payment_ref text,
  registration_amount_aed numeric(12,2),
  accepted_terms_user_agent text,
  licence_legal_name text,
  merged_into bigint,
  merged_at timestamp with time zone,
  marketing_consent boolean DEFAULT false NOT NULL,
  marketing_consent_at timestamp with time zone,
  marketing_consent_source text,
  license_issue_date date
);

CREATE TABLE IF NOT EXISTS public.legal_checklist (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  requirement text NOT NULL,
  category text NOT NULL,
  applies_to text,
  priority integer DEFAULT 2 NOT NULL,
  match_slug text,
  present boolean DEFAULT false NOT NULL,
  notes text,
  match_clause text
);

CREATE TABLE IF NOT EXISTS public.legal_documents (
  slug text NOT NULL,
  title text NOT NULL,
  category text DEFAULT 'public'::text NOT NULL,
  version text DEFAULT '1.0'::text,
  effective_date date DEFAULT CURRENT_DATE,
  summary text,
  body_html text,
  updated_at timestamp with time zone DEFAULT now(),
  content_sha256 text,
  source text
);

CREATE TABLE IF NOT EXISTS public.legal_kpi_snapshots (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
  kpis jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.legal_reviews (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  doc_kind text,
  title text,
  source text,
  summary text,
  risk_flags jsonb DEFAULT '[]'::jsonb,
  risk_level text,
  needs_licensed_review boolean DEFAULT true,
  reviewed_at timestamp with time zone DEFAULT now() NOT NULL,
  reviewed_by text DEFAULT 'legal_ai'::text
);

CREATE TABLE IF NOT EXISTS public.licence_renewal_ask (
  id bigint DEFAULT nextval('licence_renewal_ask_id_seq'::regclass) NOT NULL,
  lead_id bigint NOT NULL,
  asked_at timestamp with time zone DEFAULT now() NOT NULL,
  band text NOT NULL,
  expiry_date date NOT NULL,
  days_to_expiry integer NOT NULL,
  channel text NOT NULL,
  sent boolean DEFAULT false NOT NULL,
  blocked_reason text,
  notification_id bigint,
  answered_at timestamp with time zone,
  answered_by_intake bigint
);

CREATE TABLE IF NOT EXISTS public.line_spec_reading (
  reading_key text NOT NULL,
  found jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.llm_attempt (
  attempt_id uuid DEFAULT gen_random_uuid() NOT NULL,
  request_id uuid NOT NULL,
  attempt_no integer NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  fn text,
  agent_key text,
  task_class text,
  model_route text NOT NULL,
  tier text,
  ok boolean NOT NULL,
  class_key text,
  http_status integer,
  finish_reason text,
  err_excerpt text,
  evidence_truncated boolean DEFAULT false NOT NULL,
  latency_ms integer,
  prompt_tokens integer,
  output_tokens integer,
  cost_aed numeric,
  breaker_state text
);

CREATE TABLE IF NOT EXISTS public.llm_cache (
  cache_key text NOT NULL,
  task_class text,
  prompt_hash text NOT NULL,
  response text NOT NULL,
  model_used text,
  hits integer DEFAULT 0 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  last_hit_at timestamp with time zone,
  expires_at timestamp with time zone,
  fn text,
  embedding_gte vector(384),
  saved_usd numeric DEFAULT 0 NOT NULL
);

CREATE TABLE IF NOT EXISTS public.llm_calls (
  id bigint DEFAULT nextval('llm_calls_id_seq'::regclass) NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  fn text NOT NULL,
  purpose text,
  model_wanted text,
  model_used text,
  fell_back boolean GENERATED ALWAYS AS ((model_used IS DISTINCT FROM model_wanted)) STORED,
  ok boolean DEFAULT true NOT NULL,
  attempts integer DEFAULT 1 NOT NULL,
  cached boolean,
  prompt_tokens integer,
  output_tokens integer,
  cached_tokens integer,
  latency_ms integer,
  err text
);

CREATE TABLE IF NOT EXISTS public.llm_failure_class (
  class_key text NOT NULL,
  layer text NOT NULL,
  description text NOT NULL,
  retryable boolean NOT NULL,
  max_retries integer DEFAULT 0 NOT NULL,
  retry_backoff_ms integer DEFAULT 0 NOT NULL,
  trips_breaker boolean DEFAULT true NOT NULL,
  opens_on_first boolean DEFAULT false NOT NULL,
  operator_note text
);

CREATE TABLE IF NOT EXISTS public.llm_route_health (
  model_id text NOT NULL,
  consecutive_failures integer DEFAULT 0 NOT NULL,
  failure_threshold integer DEFAULT 5 NOT NULL,
  cooldown_seconds integer DEFAULT 900 NOT NULL,
  open_until timestamp with time zone,
  opened_reason text,
  opened_class text,
  last_ok_at timestamp with time zone,
  last_failure_at timestamp with time zone,
  total_attempts bigint DEFAULT 0 NOT NULL,
  total_ok bigint DEFAULT 0 NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.llm_seat_binding (
  fn text NOT NULL,
  seat text NOT NULL,
  note text,
  declared_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.market_intel (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  kind text NOT NULL,
  title text NOT NULL,
  detail text,
  source text,
  impact text DEFAULT 'medium'::text,
  status text DEFAULT 'open'::text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  source_url text,
  platform text,
  external_id text,
  competitor_id bigint,
  posted_at timestamp with time zone,
  metrics jsonb,
  fetched_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.marketing_ad_spend_day (
  account_id text NOT NULL,
  campaign_id text NOT NULL,
  day date NOT NULL,
  campaign_name text,
  spend numeric(14,2) NOT NULL,
  currency text NOT NULL,
  impressions bigint,
  clicks bigint,
  is_demo boolean DEFAULT false NOT NULL,
  pulled_at timestamp with time zone DEFAULT now() NOT NULL,
  handed_off_at timestamp with time zone,
  booked_ack_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.marketing_article (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  slug text NOT NULL,
  kind text NOT NULL,
  title_en text NOT NULL,
  excerpt_en text NOT NULL,
  meta_desc_en text NOT NULL,
  category_en text NOT NULL,
  body_html_en text NOT NULL,
  title_ar text NOT NULL,
  excerpt_ar text NOT NULL,
  meta_desc_ar text NOT NULL,
  category_ar text NOT NULL,
  body_html_ar text NOT NULL,
  sources jsonb NOT NULL,
  checks jsonb NOT NULL,
  ingested_by text NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  approved_by text,
  approved_at timestamp with time zone,
  released_at timestamp with time zone,
  live_at timestamp with time zone,
  linkedin_post_key text NOT NULL,
  is_demo boolean DEFAULT false NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  approval_token text,
  approval_sent_at timestamp with time zone,
  founder_change_request text,
  topic_id bigint,
  withdrawn_reason text,
  withdrawn_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.marketing_article_round (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  article_id bigint NOT NULL,
  topic_id bigint NOT NULL,
  round integer NOT NULL,
  version jsonb NOT NULL,
  fingerprint text NOT NULL,
  drafted_by_model text,
  changes jsonb,
  decision text,
  reasons jsonb,
  reviewed_by_model text,
  reviewed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_asset_feature (
  file_sha256 text NOT NULL,
  extractor_version text NOT NULL,
  asset_bucket text NOT NULL,
  asset_path text NOT NULL,
  bytes bigint NOT NULL,
  duration_s numeric(8,3) NOT NULL,
  width integer NOT NULL,
  height integer NOT NULL,
  aspect text NOT NULL,
  fps numeric(8,3) NOT NULL,
  scene_cuts integer NOT NULL,
  cuts_per_10s numeric(8,3) NOT NULL,
  hook_cuts_first_3s integer NOT NULL,
  hook_motion_first_3s numeric(10,4),
  audio_present boolean NOT NULL,
  loudness_lufs numeric(8,2),
  true_peak_db numeric(8,2),
  speech_band_ratio numeric(8,4),
  voiceover_suspected boolean,
  frames_with_text integer,
  frames_sampled integer,
  text_chars_per_frame numeric(8,2),
  keyframes jsonb DEFAULT '[]'::jsonb NOT NULL,
  music jsonb DEFAULT '{}'::jsonb NOT NULL,
  toolchain jsonb DEFAULT '{}'::jsonb NOT NULL,
  measured_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_asset_perception (
  id bigint DEFAULT nextval('marketing_asset_perception_id_seq'::regclass) NOT NULL,
  file_sha256 text NOT NULL,
  model text NOT NULL,
  prompt_version text NOT NULL,
  perception jsonb NOT NULL,
  disagreements jsonb DEFAULT '[]'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_asset_review (
  id bigint DEFAULT nextval('marketing_asset_review_id_seq'::regclass) NOT NULL,
  file_sha256 text NOT NULL,
  review jsonb NOT NULL,
  evidence jsonb NOT NULL,
  inputs jsonb NOT NULL,
  model text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_blog_topic (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  topic_key text NOT NULL,
  kind text NOT NULL,
  title text NOT NULL,
  trade text,
  score numeric NOT NULL,
  evidence jsonb NOT NULL,
  sources jsonb NOT NULL,
  considered jsonb DEFAULT '[]'::jsonb NOT NULL,
  lessons jsonb DEFAULT '[]'::jsonb NOT NULL,
  learned jsonb DEFAULT '[]'::jsonb NOT NULL,
  status text DEFAULT 'picked'::text NOT NULL,
  replaced_reason text,
  picked_at timestamp with time zone DEFAULT now() NOT NULL,
  closed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.marketing_calendar_resend_decision (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  campaign_id bigint NOT NULL,
  decided_at timestamp with time zone DEFAULT now() NOT NULL,
  decision text NOT NULL,
  current_hash text,
  last_edit_at timestamp with time zone,
  due_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.marketing_campaign (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  campaign_key text NOT NULL,
  theme text NOT NULL,
  title text,
  month date NOT NULL,
  spend_policy text DEFAULT 'organic_only'::text NOT NULL,
  is_demo boolean DEFAULT false NOT NULL,
  calendar_pdf_path text,
  calendar_xlsx_path text,
  calendar_hash text,
  calendar_token text,
  calendar_sent_at timestamp with time zone,
  calendar_notification_id bigint,
  approved_by text,
  approved_at timestamp with time zone,
  approved_hash text,
  approved_message_id text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_connection_check (
  check_key text NOT NULL,
  platform text NOT NULL,
  ok boolean NOT NULL,
  http_status integer,
  credential_keys text[] DEFAULT '{}'::text[] NOT NULL,
  detail jsonb DEFAULT '{}'::jsonb NOT NULL,
  needs text,
  measured_at timestamp with time zone NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_duty_run (
  duty text NOT NULL,
  last_started_at timestamp with time zone,
  last_ok_at timestamp with time zone,
  last_result jsonb
);

CREATE TABLE IF NOT EXISTS public.marketing_first_touch (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  lead_id bigint NOT NULL,
  utm_source text NOT NULL,
  utm_medium text,
  utm_campaign text,
  utm_content text,
  landing_path text,
  first_seen_at timestamp with time zone,
  post_id bigint,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_founder_request (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  kind text NOT NULL,
  campaign_id bigint,
  month date,
  founder_text text DEFAULT ''::text NOT NULL,
  attachments text[] DEFAULT '{}'::text[] NOT NULL,
  message_id text,
  status text DEFAULT 'open'::text NOT NULL,
  done_at timestamp with time zone,
  done_note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_gap_recruitment_plan (
  trade text NOT NULL,
  emirate text NOT NULL,
  rank integer NOT NULL,
  matchable integer NOT NULL,
  target integer NOT NULL,
  gap integer NOT NULL,
  demand_90d integer NOT NULL,
  uninvited_pool integer NOT NULL,
  gap_status text NOT NULL,
  sources jsonb DEFAULT '[]'::jsonb NOT NULL,
  invite_subject text NOT NULL,
  invite_body text NOT NULL,
  built_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_geo_check (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  month date NOT NULL,
  question_id bigint NOT NULL,
  engine text NOT NULL,
  cited boolean NOT NULL,
  rank integer,
  evidence text,
  model text,
  checked_at timestamp with time zone DEFAULT now() NOT NULL,
  competitors_cited text[] DEFAULT '{}'::text[] NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_geo_question (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  question text NOT NULL,
  audience text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  trade text,
  city text
);

CREATE TABLE IF NOT EXISTS public.marketing_goal (
  month text NOT NULL,
  platform text NOT NULL,
  metric text NOT NULL,
  target numeric NOT NULL,
  benchmark_source text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_insight_day (
  platform text NOT NULL,
  object_type text NOT NULL,
  object_id text NOT NULL,
  metric text NOT NULL,
  day date NOT NULL,
  value numeric NOT NULL,
  pulled_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_insight_note (
  week_start date NOT NULL,
  synthesis jsonb NOT NULL,
  intel_ids bigint[] NOT NULL,
  model text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_knowledge (
  record_id text NOT NULL,
  record_type text NOT NULL,
  domain text,
  title text NOT NULL,
  content text NOT NULL,
  structured_data jsonb DEFAULT '{}'::jsonb NOT NULL,
  source_ids text[] DEFAULT '{}'::text[] NOT NULL,
  epistemic_status text NOT NULL,
  jurisdiction text,
  pack_id text NOT NULL,
  pack_version text NOT NULL,
  body_sha256 text NOT NULL,
  runtime_index_eligible boolean DEFAULT true NOT NULL,
  authority_effect text DEFAULT 'none'::text NOT NULL,
  tags text[] DEFAULT '{}'::text[] NOT NULL,
  updated_at timestamp with time zone,
  ingested_at timestamp with time zone DEFAULT now() NOT NULL,
  embedding_gte vector(384)
);

CREATE TABLE IF NOT EXISTS public.marketing_library (
  id bigint DEFAULT nextval('marketing_library_id_seq'::regclass) NOT NULL,
  category text NOT NULL,
  domain text,
  title text NOT NULL,
  content text NOT NULL,
  tags text,
  source_file text,
  tsv tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, ((((COALESCE(title, ''::text) || ' '::text) || COALESCE(tags, ''::text)) || ' '::text) || COALESCE(content, ''::text)))) STORED,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.marketing_meta_page (
  page_id text NOT NULL,
  ig_id text,
  page_token text NOT NULL,
  fetched_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_model_run (
  id bigint DEFAULT nextval('marketing_model_run_id_seq'::regclass) NOT NULL,
  step text NOT NULL,
  subject text NOT NULL,
  seat text NOT NULL,
  task_class text NOT NULL,
  outcome text NOT NULL,
  reason text,
  model text,
  output_table text,
  output_ref text,
  run_day date DEFAULT ((now() AT TIME ZONE 'Asia/Dubai'::text))::date NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_month_plan (
  month date NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  verdict jsonb,
  plan jsonb,
  content_brief jsonb,
  rounds integer DEFAULT 0 NOT NULL,
  deliberation_id bigint,
  sent_turn_id bigint,
  brief_handoff_id bigint,
  founder_decided_at timestamp with time zone,
  founder_note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  plan_token text,
  plan_notification_id bigint,
  plan_sent_at timestamp with time zone,
  ceo_held_id bigint
);

CREATE TABLE IF NOT EXISTS public.marketing_outreach_message (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  prospect_id bigint NOT NULL,
  kind text NOT NULL,
  language text NOT NULL,
  body text NOT NULL,
  note text,
  lint jsonb DEFAULT '[]'::jsonb NOT NULL,
  reply_class text,
  listed_on date NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  mark_token uuid DEFAULT gen_random_uuid() NOT NULL,
  reply_text text,
  delivery jsonb,
  sent_at timestamp with time zone,
  replied_at timestamp with time zone,
  converted_at timestamp with time zone,
  is_demo boolean DEFAULT false NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_plan_doc (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  kind text NOT NULL,
  period date NOT NULL,
  body jsonb NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  approval_token text,
  sent_at timestamp with time zone,
  notification_id bigint,
  decided_at timestamp with time zone,
  founder_note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  sent_hash text,
  founder_changes jsonb DEFAULT '[]'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_plan_review_turn (
  id bigint DEFAULT nextval('marketing_plan_review_turn_id_seq'::regclass) NOT NULL,
  month date NOT NULL,
  round integer NOT NULL,
  seat text NOT NULL,
  move text NOT NULL,
  reasoning text NOT NULL,
  evidence jsonb NOT NULL,
  changes jsonb,
  answers jsonb,
  deliberation_turn_id bigint,
  criteria jsonb,
  plan jsonb,
  model text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_platform_spec (
  platform text NOT NULL,
  surface text NOT NULL,
  attribute text NOT NULL,
  value_num numeric,
  value_text text,
  unit text,
  counted_as text,
  source_kind text NOT NULL,
  source_url text NOT NULL,
  read_on date NOT NULL,
  confidence text NOT NULL,
  note text
);

CREATE TABLE IF NOT EXISTS public.marketing_platform_spec_source (
  source_url text NOT NULL,
  seen_hash text,
  verified_hash text,
  checked_at timestamp with time zone,
  verified_at timestamp with time zone,
  last_status integer,
  last_error text
);

CREATE TABLE IF NOT EXISTS public.marketing_post (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  ingest_key text NOT NULL,
  owner_seat text DEFAULT 'marketing'::text NOT NULL,
  ingested_by text NOT NULL,
  title text,
  text_en text NOT NULL,
  text_ar text,
  media_paths text[] DEFAULT '{}'::text[] NOT NULL,
  channels text[] NOT NULL,
  scheduled_at timestamp with time zone,
  status text DEFAULT 'draft'::text NOT NULL,
  is_demo boolean DEFAULT false NOT NULL,
  dry_run jsonb,
  postiz_result jsonb,
  permalinks jsonb,
  error text,
  attempts integer DEFAULT 0 NOT NULL,
  published_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  campaign_id bigint,
  scheduled_local timestamp without time zone,
  video_path text,
  video_sha256 text,
  cover_path text,
  cover_sha256 text,
  cta_url text,
  rationale text,
  music jsonb,
  publish_started_at timestamp with time zone,
  channel_outcome text,
  channel_checked_at timestamp with time zone,
  content_edited_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.marketing_post_channel_result (
  post_id bigint NOT NULL,
  channel text NOT NULL,
  state text NOT NULL,
  cause text,
  postiz_post_id text,
  postiz_state text,
  platform_message text,
  release_url text,
  first_checked_at timestamp with time zone DEFAULT now() NOT NULL,
  checked_at timestamp with time zone DEFAULT now() NOT NULL,
  state_changed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_post_metric (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  post_id bigint NOT NULL,
  platform text NOT NULL,
  platform_post_id text,
  checkpoint text NOT NULL,
  metric text NOT NULL,
  value numeric,
  unavailable_reason text,
  captured_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_post_platform (
  post_id bigint NOT NULL,
  platform text NOT NULL,
  postiz_post_id text,
  platform_post_id text,
  permalink text,
  tied_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_post_variant (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  post_id bigint NOT NULL,
  platform text NOT NULL,
  seq smallint DEFAULT 1 NOT NULL,
  language text NOT NULL,
  post_type text NOT NULL,
  caption text NOT NULL,
  hashtags text[] DEFAULT '{}'::text[] NOT NULL,
  body text GENERATED ALWAYS AS (fn_marketing_variant_text(caption, hashtags)) STORED,
  alt_text text,
  title text,
  first_comment text,
  cover_path text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_prospect (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  full_name text NOT NULL,
  role_title text NOT NULL,
  company text NOT NULL,
  segment text NOT NULL,
  emirate text,
  language text DEFAULT 'en'::text NOT NULL,
  linkedin_url text,
  opening_line text,
  opening_line_url text,
  source_urls text[] NOT NULL,
  researched_by text NOT NULL,
  status text DEFAULT 'new'::text NOT NULL,
  is_demo boolean DEFAULT false NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_recruitment_source (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  scope text NOT NULL,
  kind text NOT NULL,
  name text NOT NULL,
  url text NOT NULL,
  http_status integer NOT NULL,
  verified boolean NOT NULL,
  checked_at timestamp with time zone NOT NULL,
  evidence text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_report (
  report_date date NOT NULL,
  window_from timestamp with time zone NOT NULL,
  window_to timestamp with time zone NOT NULL,
  figures jsonb NOT NULL,
  no_data_yet boolean NOT NULL,
  handoff_id bigint,
  read_by_ceo_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_review (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  kind text NOT NULL,
  period date NOT NULL,
  body jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  handoff_id bigint,
  read_by_ceo_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.marketing_scorecard_report (
  period_key text NOT NULL,
  month text NOT NULL,
  kind text NOT NULL,
  rows integer NOT NULL,
  result jsonb NOT NULL,
  owner_seat text DEFAULT 'marketing'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_snapshots (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
  kpis jsonb NOT NULL,
  plan jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_trend (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  source_id bigint NOT NULL,
  url text NOT NULL,
  title text NOT NULL,
  published_at timestamp with time zone,
  seen_at timestamp with time zone DEFAULT now() NOT NULL,
  relevant boolean,
  why_it_matters text,
  judged_at timestamp with time zone,
  judged_by text
);

CREATE TABLE IF NOT EXISTS public.marketing_trend_source (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  name text NOT NULL,
  feed_url text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  last_read_at timestamp with time zone,
  last_error text,
  kind text DEFAULT 'news'::text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_video_idea (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  idea_key text NOT NULL,
  title text NOT NULL,
  hook text NOT NULL,
  film_plan text NOT NULL,
  cta text NOT NULL,
  audience text NOT NULL,
  enabled boolean DEFAULT true NOT NULL,
  last_planned_month date,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.match_eval_runs (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  ran_at timestamp with time zone DEFAULT now(),
  precision_pct numeric,
  recall_pct numeric,
  cases_total integer,
  detail jsonb
);

CREATE TABLE IF NOT EXISTS public.materials (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  category text NOT NULL,
  item text NOT NULL,
  properties jsonb DEFAULT '{}'::jsonb,
  standards text[] DEFAULT '{}'::text[],
  price_band text,
  alternatives jsonb DEFAULT '[]'::jsonb,
  pros text[] DEFAULT '{}'::text[],
  cons text[] DEFAULT '{}'::text[],
  source text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.mdm_brands (
  id bigint DEFAULT nextval('mdm_brands_id_seq'::regclass) NOT NULL,
  name text NOT NULL,
  category text,
  manufacturer text,
  aliases text[] DEFAULT '{}'::text[],
  active boolean DEFAULT true
);

CREATE TABLE IF NOT EXISTS public.mdm_manufacturers (
  id bigint DEFAULT nextval('mdm_manufacturers_id_seq'::regclass) NOT NULL,
  name text NOT NULL,
  country text,
  aliases text[] DEFAULT '{}'::text[],
  active boolean DEFAULT true
);

CREATE TABLE IF NOT EXISTS public.mdm_standards (
  id bigint DEFAULT nextval('mdm_standards_id_seq'::regclass) NOT NULL,
  code text NOT NULL,
  title text,
  authority text,
  domain text,
  aliases text[] DEFAULT '{}'::text[],
  active boolean DEFAULT true
);

CREATE TABLE IF NOT EXISTS public.mep_evidence_weight (
  weight_key text NOT NULL,
  evidence_source text NOT NULL,
  variant text,
  evidence_score numeric(4,3) NOT NULL,
  score_basis text DEFAULT 'rule_weight_provisional'::text NOT NULL,
  source_authority text NOT NULL,
  exactness text NOT NULL,
  auto_confirms boolean NOT NULL,
  rationale text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.mep_trade (
  trade_key text NOT NULL,
  label_en text NOT NULL,
  label_ar text,
  sort_order integer DEFAULT 0 NOT NULL,
  is_core boolean DEFAULT false NOT NULL
);

CREATE TABLE IF NOT EXISTS public.messages (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  inquiry_id uuid,
  supplier_id bigint,
  customer_id uuid,
  sender text NOT NULL,
  body text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  read_by_customer boolean DEFAULT false,
  read_by_supplier boolean DEFAULT false,
  flagged boolean DEFAULT false,
  blocked boolean DEFAULT false,
  redacted_body text,
  project_id uuid,
  attachment_path text,
  document_id bigint
);

CREATE TABLE IF NOT EXISTS public.messaging_template (
  sid text NOT NULL,
  channel text DEFAULT 'whatsapp'::text NOT NULL,
  template_key text NOT NULL,
  lang text DEFAULT 'en'::text NOT NULL,
  name text,
  category text,
  status text DEFAULT 'unknown'::text NOT NULL,
  submitted_at timestamp with time zone,
  approved_at timestamp with time zone,
  rejection_reason text,
  last_checked_at timestamp with time zone,
  note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  last_http_status integer
);

CREATE TABLE IF NOT EXISTS public.meta_insights (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  campaign_id text NOT NULL,
  campaign_name text,
  effective_status text,
  objective text,
  time_window text DEFAULT 'last_30d'::text NOT NULL,
  spend numeric(14,2) DEFAULT 0,
  impressions bigint DEFAULT 0,
  clicks bigint DEFAULT 0,
  reach bigint DEFAULT 0,
  ctr numeric(8,3),
  cpc numeric(10,3),
  results bigint DEFAULT 0,
  currency text DEFAULT 'AED'::text,
  synced_at timestamp with time zone DEFAULT now() NOT NULL,
  synced_via text DEFAULT 'meta_sync'::text
);

CREATE TABLE IF NOT EXISTS public.metric_definition (
  metric_key text NOT NULL,
  label text NOT NULL,
  domain text NOT NULL,
  definition text NOT NULL,
  measure_sql text NOT NULL,
  target numeric,
  direction text DEFAULT 'up'::text NOT NULL,
  owner_dept text,
  active boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.metric_snapshot (
  id bigint DEFAULT nextval('metric_snapshot_id_seq'::regclass) NOT NULL,
  metric_key text NOT NULL,
  value numeric,
  error text,
  taken_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.model_catalogue_change (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  model_id text NOT NULL,
  field text NOT NULL,
  old_value numeric,
  new_value numeric,
  drift_pct numeric,
  matrix boolean NOT NULL,
  outcome text,
  closed_at timestamp with time zone,
  first_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  last_seen_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.model_fallback_chain (
  purpose text NOT NULL,
  rung integer NOT NULL,
  model text NOT NULL,
  kind text NOT NULL,
  rationale text NOT NULL,
  authority text NOT NULL,
  active boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.model_policy (
  task_class text NOT NULL,
  tier text NOT NULL,
  model_primary text NOT NULL,
  model_fallback text,
  max_tokens integer DEFAULT 800 NOT NULL,
  rationale text,
  deterministic_alternative text,
  active boolean DEFAULT true NOT NULL,
  cache_ttl_min integer DEFAULT 0 NOT NULL,
  reviews_class text[]
);

CREATE TABLE IF NOT EXISTS public.model_policy_by_identity (
  identity_key text NOT NULL,
  scope text NOT NULL,
  department text,
  title text,
  deterministic_first text,
  primary_model text,
  fallback_model text,
  escalation_model text,
  max_output_tokens integer,
  reasoning_effort text,
  manager text,
  authority_tier text,
  note text,
  package_version text DEFAULT 'v2026.07.31'::text NOT NULL,
  imported_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.model_rate (
  model text NOT NULL,
  tier text NOT NULL,
  in_aed_per_mtok numeric NOT NULL,
  out_aed_per_mtok numeric NOT NULL,
  note text,
  usd_per_m_prompt numeric,
  usd_per_m_output numeric,
  id_verified boolean DEFAULT true NOT NULL,
  source_url text,
  verified_at date,
  cache_read_aed_per_mtok numeric,
  cache_write_aed_per_mtok numeric
);

CREATE TABLE IF NOT EXISTS public.model_registry (
  model_id text NOT NULL,
  provider text NOT NULL,
  tier text NOT NULL,
  in_per_mtok_usd numeric NOT NULL,
  out_per_mtok_usd numeric NOT NULL,
  cache_read_per_mtok_usd numeric,
  cache_write_per_mtok_usd numeric,
  supports_cache boolean DEFAULT false NOT NULL,
  supports_streaming boolean DEFAULT true NOT NULL,
  context_len integer,
  approved boolean DEFAULT true NOT NULL,
  active boolean DEFAULT true NOT NULL,
  quality_score numeric,
  note text,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  supports_vision boolean DEFAULT false NOT NULL,
  supports_audio boolean DEFAULT false NOT NULL,
  supports_tools boolean DEFAULT false NOT NULL
);

CREATE TABLE IF NOT EXISTS public.money_move_hold (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  move text NOT NULL,
  ref text NOT NULL,
  customer_id uuid,
  supplier_id bigint,
  status text NOT NULL,
  flag_keys text[] DEFAULT '{}'::text[] NOT NULL,
  flags jsonb DEFAULT '[]'::jsonb NOT NULL,
  opened_at timestamp with time zone DEFAULT now() NOT NULL,
  screened_at timestamp with time zone DEFAULT now() NOT NULL,
  released_at timestamp with time zone,
  released_by text,
  release_reason text
);

CREATE TABLE IF NOT EXISTS public.notice_plain_language (
  notification_id bigint NOT NULL,
  scored_at timestamp with time zone DEFAULT now() NOT NULL,
  sent_at timestamp with time zone,
  type text NOT NULL,
  to_role text NOT NULL,
  requested_by text,
  channel text,
  lang text NOT NULL,
  ok boolean NOT NULL,
  score smallint NOT NULL,
  tone smallint NOT NULL,
  issues text[] DEFAULT '{}'::text[] NOT NULL,
  demo boolean DEFAULT false NOT NULL
);

CREATE TABLE IF NOT EXISTS public.notice_plain_language_cause (
  id bigint DEFAULT nextval('notice_plain_language_cause_id_seq'::regclass) NOT NULL,
  type text NOT NULL,
  owner_seat text NOT NULL,
  opened_at timestamp with time zone DEFAULT now() NOT NULL,
  baseline jsonb NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  handoff_id bigint,
  measurements jsonb DEFAULT '[]'::jsonb NOT NULL,
  closed_at timestamp with time zone,
  fixture boolean DEFAULT false NOT NULL
);

CREATE TABLE IF NOT EXISTS public.notification_copy (
  type text NOT NULL,
  subject_en text NOT NULL,
  body_en text NOT NULL,
  subject_ar text NOT NULL,
  body_ar text NOT NULL,
  note text,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.notification_type_severity (
  type text NOT NULL,
  severity text NOT NULL,
  reason text NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.notifications (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  type text NOT NULL,
  to_email text,
  to_role text,
  lead_id bigint,
  inquiry_id uuid,
  quote_id uuid,
  subject text,
  body text,
  status text DEFAULT 'pending'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  sent_at timestamp with time zone,
  channel text DEFAULT 'email'::text,
  to_phone text,
  attempts integer DEFAULT 0 NOT NULL,
  last_error text,
  html text,
  cc_emails text[] DEFAULT '{}'::text[] NOT NULL,
  kind text,
  attachments jsonb,
  provider_message_id text,
  requested_by text,
  sender text DEFAULT 'customer_support'::text NOT NULL,
  lang text,
  not_before timestamp with time zone,
  provider_status text,
  provider_status_at timestamp with time zone,
  provider_error_code text,
  provider_status_checked_at timestamp with time zone,
  provider_poll_failures integer DEFAULT 0 NOT NULL,
  claimed_at timestamp with time zone,
  reply_to text,
  severity text,
  failover_of bigint,
  in_reply_to text,
  dedupe_key text
);

CREATE TABLE IF NOT EXISTS public.openrouter_day (
  day date NOT NULL,
  authoritative_usd numeric,
  authoritative_basis text NOT NULL,
  attributed_usd numeric DEFAULT 0 NOT NULL,
  unattributed_usd numeric,
  calls integer DEFAULT 0 NOT NULL,
  calls_priced integer DEFAULT 0 NOT NULL,
  calls_free integer DEFAULT 0 NOT NULL,
  calls_unpriced integer DEFAULT 0 NOT NULL,
  breakdown jsonb DEFAULT '{}'::jsonb NOT NULL,
  meter_open_id bigint,
  meter_close_id bigint,
  expense_entry_id bigint,
  note text,
  reconciled_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.openrouter_meter (
  id bigint DEFAULT nextval('openrouter_meter_id_seq'::regclass) NOT NULL,
  read_at timestamp with time zone DEFAULT now() NOT NULL,
  ok boolean NOT NULL,
  cumulative_usd numeric,
  credits_total_usd numeric,
  usage_daily_usd numeric,
  usage_monthly_usd numeric,
  limit_remaining_usd numeric,
  key_label text,
  err text
);

CREATE TABLE IF NOT EXISTS public.operating_system (
  os_key text NOT NULL,
  num integer NOT NULL,
  name text NOT NULL,
  charter text NOT NULL,
  mandate text NOT NULL,
  owner_agent text,
  adapts_by text,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  mission text,
  health_score numeric,
  last_health_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.opportunity (
  id bigint DEFAULT nextval('opportunity_id_seq'::regclass) NOT NULL,
  kind text NOT NULL,
  title text NOT NULL,
  detail text,
  evidence jsonb DEFAULT '{}'::jsonb,
  value_score numeric,
  effort text,
  confidence numeric,
  status text DEFAULT 'open'::text NOT NULL,
  detected_by text DEFAULT 'intel_director'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ops_knowledge (
  record_id text NOT NULL,
  scope_type text NOT NULL,
  scope_key text NOT NULL,
  dept_key text,
  module text NOT NULL,
  record_type text NOT NULL,
  title text NOT NULL,
  content text NOT NULL,
  structured_data jsonb DEFAULT '{}'::jsonb NOT NULL,
  source_ids text[] DEFAULT '{}'::text[] NOT NULL,
  implementation_status text NOT NULL,
  validation_status text NOT NULL,
  authority_tier text NOT NULL,
  risk_level text NOT NULL,
  version text NOT NULL,
  effective_date date,
  review_after date,
  keywords text[] DEFAULT '{}'::text[] NOT NULL,
  dependencies text[] DEFAULT '{}'::text[] NOT NULL,
  escalation_rule jsonb DEFAULT '{}'::jsonb NOT NULL,
  tsv tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, ((COALESCE(title, ''::text) || ' '::text) || COALESCE(content, ''::text)))) STORED,
  package text,
  package_version text,
  generation text,
  layer text,
  role_key text,
  category_key text,
  jurisdiction text DEFAULT 'AE'::text NOT NULL,
  source_type text,
  source_authority text,
  source_freshness text DEFAULT 'stable'::text NOT NULL,
  confidentiality text DEFAULT 'internal'::text NOT NULL,
  runtime_eligible boolean DEFAULT true NOT NULL,
  deterministic boolean DEFAULT false NOT NULL,
  supersedes_id text,
  supersession_state text DEFAULT 'current'::text NOT NULL,
  checksum text,
  ingestion_run_id uuid,
  embedding_status text DEFAULT 'not_required'::text NOT NULL,
  source_path text,
  embedding_gte vector(384)
);

CREATE TABLE IF NOT EXISTS public.ops_kpi_snapshots (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
  kpis jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.org_action_executor (
  action_class text NOT NULL,
  kind text NOT NULL,
  target text NOT NULL,
  params jsonb DEFAULT '{}'::jsonb NOT NULL,
  active boolean DEFAULT true NOT NULL,
  note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  advisory_safe boolean DEFAULT false NOT NULL,
  department text,
  owner_os text,
  risk_tier text DEFAULT 'high'::text NOT NULL,
  reversible boolean DEFAULT false NOT NULL,
  idempotency_strategy text,
  timeout_seconds integer DEFAULT 60 NOT NULL,
  max_attempts integer DEFAULT 1 NOT NULL,
  backoff text,
  required_authority text,
  compensation_action_class text,
  notifies_human boolean DEFAULT false NOT NULL,
  unattended_ok boolean DEFAULT false NOT NULL,
  second_authority text
);

CREATE TABLE IF NOT EXISTS public.org_agent_alias (
  alias text NOT NULL,
  agent_key text NOT NULL,
  reason text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.org_agents (
  agent_key text NOT NULL,
  department text,
  role text,
  kind text DEFAULT 'brain'::text NOT NULL,
  active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  title text,
  manager_key text,
  seniority text,
  responsibilities text,
  max_open_tasks integer DEFAULT 5 NOT NULL,
  improvement_plan text,
  hired_at timestamp with time zone DEFAULT now() NOT NULL,
  available boolean DEFAULT true NOT NULL,
  unavailable_until date,
  unavailable_reason text,
  routing_tier text
);

CREATE TABLE IF NOT EXISTS public.org_authority (
  dept_key text NOT NULL,
  action_class text NOT NULL,
  max_tier text NOT NULL,
  threshold_aed numeric,
  note text
);

CREATE TABLE IF NOT EXISTS public.org_category_identity (
  category_key text NOT NULL,
  catalog_num integer NOT NULL,
  route_key text NOT NULL,
  owner_agent text,
  package_version text DEFAULT '2026.08.14'::text NOT NULL,
  readiness text DEFAULT 'knowledge_imported'::text NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.org_committee (
  committee_key text NOT NULL,
  name text NOT NULL,
  purpose text NOT NULL,
  chair_role_id text,
  cadence text DEFAULT 'weekly'::text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.org_departments (
  dept_key text NOT NULL,
  name text NOT NULL,
  charter text NOT NULL,
  north_star text,
  health_fn text,
  lead_agent text,
  active boolean DEFAULT true NOT NULL,
  sort integer DEFAULT 100 NOT NULL,
  brain_agent text,
  merged_into text,
  merged_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.org_memory (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  scope text DEFAULT 'global'::text NOT NULL,
  kind text DEFAULT 'note'::text NOT NULL,
  content text NOT NULL,
  source text,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.org_objectives (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  objective text NOT NULL,
  raw_input text,
  created_by text DEFAULT 'founder'::text,
  status text DEFAULT 'open'::text NOT NULL,
  priority text DEFAULT 'normal'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  closed_at timestamp with time zone,
  outcome text
);

CREATE TABLE IF NOT EXISTS public.org_onboarding (
  agent_key text NOT NULL,
  department text,
  status text DEFAULT 'onboarding'::text NOT NULL,
  l1_score numeric,
  l1_at timestamp with time zone,
  l2_score numeric,
  l2_at timestamp with time zone,
  l3_score numeric,
  l3_at timestamp with time zone,
  l4_score numeric,
  l4_at timestamp with time zone,
  pass_threshold numeric DEFAULT 85 NOT NULL,
  probation_reviews_done integer DEFAULT 0 NOT NULL,
  probation_reviews_required integer DEFAULT 3 NOT NULL,
  certified_at timestamp with time zone,
  recert_due date,
  note text,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.org_phase_baseline (
  phase text NOT NULL,
  approved_by text NOT NULL,
  approved_at timestamp with time zone NOT NULL,
  project_ref text NOT NULL,
  final_commit text NOT NULL,
  counts jsonb NOT NULL,
  organization_sha256 text NOT NULL,
  registry_sha256 jsonb NOT NULL,
  migrations jsonb NOT NULL,
  rollbacks jsonb NOT NULL,
  deferred jsonb NOT NULL,
  note text,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.org_reporting_edge (
  child_role_id text NOT NULL,
  parent_role_id text NOT NULL,
  established_at timestamp with time zone DEFAULT now() NOT NULL,
  established_by text NOT NULL,
  reason text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.org_role (
  role_id text NOT NULL,
  display_name text NOT NULL,
  primary_department_id text,
  manager_role_id text,
  runtime_mode text NOT NULL,
  runtime_agent_key text,
  responsibilities text NOT NULL,
  owned_decisions text[] DEFAULT '{}'::text[] NOT NULL,
  forbidden_decisions text[] DEFAULT '{}'::text[] NOT NULL,
  activation_conditions text NOT NULL,
  required_inputs text[] DEFAULT '{}'::text[] NOT NULL,
  output_contracts text[] DEFAULT '{}'::text[] NOT NULL,
  tools text[] DEFAULT '{}'::text[] NOT NULL,
  knowledge_scopes text[] DEFAULT '{}'::text[] NOT NULL,
  authority_level text NOT NULL,
  budget_limit numeric,
  handoff_targets text[] DEFAULT '{}'::text[] NOT NULL,
  escalation_targets text[] DEFAULT '{}'::text[] NOT NULL,
  model_policy text,
  evaluation_suite text,
  status text DEFAULT 'active'::text NOT NULL,
  source_agent_keys text[] DEFAULT '{}'::text[] NOT NULL,
  rationale text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  necessity_status text,
  necessity_reason text,
  runtime_enabled boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.org_role_alias (
  alias text NOT NULL,
  role_id text NOT NULL,
  kind text DEFAULT 'legacy_agent_key'::text NOT NULL,
  reason text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.org_role_committee (
  role_id text NOT NULL,
  committee_key text NOT NULL,
  seat text DEFAULT 'member'::text NOT NULL,
  since date DEFAULT CURRENT_DATE NOT NULL,
  note text
);

CREATE TABLE IF NOT EXISTS public.org_role_identity (
  agent_key text NOT NULL,
  packaged_role_id text NOT NULL,
  packaged_department text NOT NULL,
  archetype text NOT NULL,
  mapping_type text NOT NULL,
  readiness text DEFAULT 'knowledge_imported'::text NOT NULL,
  package_version text DEFAULT '2026.08.14'::text NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.org_task_question_reading (
  task_id bigint NOT NULL,
  question_md5 text NOT NULL,
  trade text,
  faq_id bigint,
  status text NOT NULL,
  held_id bigint,
  reasoned_at timestamp with time zone,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.org_tasks (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  objective_id bigint,
  dept_key text,
  title text NOT NULL,
  detail text,
  status text DEFAULT 'proposed'::text NOT NULL,
  tier text,
  needs_founder boolean DEFAULT false NOT NULL,
  result jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  decided_by text,
  action_class text,
  attempts integer DEFAULT 0 NOT NULL,
  last_run_at timestamp with time zone,
  root_cause text,
  assigned_agent text,
  priority smallint DEFAULT 0 NOT NULL,
  requires_evidence boolean DEFAULT false NOT NULL
);

CREATE TABLE IF NOT EXISTS public.org_workflow_ownership (
  workflow_id text NOT NULL,
  workflow_name text NOT NULL,
  accountable_role_id text NOT NULL,
  contributors text[] DEFAULT '{}'::text[] NOT NULL,
  independent_reviewer text,
  start_event text NOT NULL,
  required_end_state text NOT NULL,
  founder_boundary text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.org_workflow_step (
  workflow_id text NOT NULL,
  step_no bigint NOT NULL,
  step text NOT NULL,
  accountable_role_id text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.os_audit_log (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  at timestamp with time zone DEFAULT now() NOT NULL,
  actor text,
  action text NOT NULL,
  entity text,
  entity_id text,
  detail jsonb,
  ok boolean,
  err text
);

CREATE TABLE IF NOT EXISTS public.os_department (
  os_key text NOT NULL,
  dept_key text NOT NULL,
  note text
);

CREATE TABLE IF NOT EXISTS public.os_fresh_start (
  id bigint DEFAULT nextval('os_fresh_start_id_seq'::regclass) NOT NULL,
  effective_from timestamp with time zone NOT NULL,
  actor text NOT NULL,
  reason text NOT NULL,
  carried_forward jsonb DEFAULT '[]'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.os_incidents (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  title text NOT NULL,
  kind text DEFAULT 'other'::text NOT NULL,
  severity text DEFAULT 'medium'::text NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  detail jsonb DEFAULT '{}'::jsonb NOT NULL,
  opened_by text,
  opened_at timestamp with time zone DEFAULT now() NOT NULL,
  resolved_by text,
  resolved_at timestamp with time zone,
  resolution text,
  owner text,
  acknowledged_at timestamp with time zone,
  due_at timestamp with time zone,
  org_task_id bigint,
  escalated_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.os_interface (
  id bigint DEFAULT nextval('os_interface_id_seq'::regclass) NOT NULL,
  os_key text NOT NULL,
  direction text NOT NULL,
  kind text NOT NULL,
  description text,
  event_type text,
  active boolean DEFAULT true NOT NULL,
  planned boolean DEFAULT false NOT NULL,
  planned_reason text,
  severity text,
  planned_since timestamp with time zone,
  planned_until timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.os_knowledge_domain (
  os_key text NOT NULL,
  domain_key text NOT NULL,
  ownership text DEFAULT 'owns'::text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.os_objective (
  id bigint DEFAULT nextval('os_objective_id_seq'::regclass) NOT NULL,
  os_key text NOT NULL,
  horizon text NOT NULL,
  objective text NOT NULL,
  measure text,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  measure_sql text,
  actual_value numeric,
  measured_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.os_open_access_log (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  at timestamp with time zone DEFAULT now() NOT NULL,
  actor text NOT NULL,
  state text NOT NULL,
  reason text NOT NULL,
  detail jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS public.os_responsibility (
  responsibility text NOT NULL,
  os_key text NOT NULL,
  note text
);

CREATE TABLE IF NOT EXISTS public.os_review (
  id bigint DEFAULT nextval('os_review_id_seq'::regclass) NOT NULL,
  os_key text NOT NULL,
  period text NOT NULL,
  owner_agent text,
  health text NOT NULL,
  metrics jsonb,
  findings jsonb,
  actions integer DEFAULT 0 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.os_runbooks (
  slug text NOT NULL,
  title text NOT NULL,
  category text DEFAULT 'General'::text NOT NULL,
  when_to_use text DEFAULT ''::text NOT NULL,
  steps text DEFAULT ''::text NOT NULL,
  sort integer DEFAULT 100 NOT NULL,
  os_key text
);

CREATE TABLE IF NOT EXISTS public.os_settings_meta (
  key text NOT NULL,
  grp text NOT NULL,
  type text NOT NULL,
  label text NOT NULL,
  help text,
  validation jsonb DEFAULT '{}'::jsonb NOT NULL,
  dangerous boolean DEFAULT false NOT NULL,
  sort integer DEFAULT 100 NOT NULL
);

CREATE TABLE IF NOT EXISTS public.otp_blocked_prefix (
  prefix text NOT NULL,
  reason text NOT NULL,
  blocked_by text NOT NULL,
  blocked_at timestamp with time zone DEFAULT now() NOT NULL,
  expires_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.otp_prefix_allowed (
  prefix text NOT NULL,
  reason text NOT NULL,
  allowed_by text NOT NULL,
  allowed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.otp_served_country (
  prefix text NOT NULL,
  country text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.outcome_record (
  id bigint DEFAULT nextval('outcome_record_id_seq'::regclass) NOT NULL,
  actor text NOT NULL,
  dept_key text,
  subject_type text NOT NULL,
  subject_id text,
  decision text NOT NULL,
  rationale text,
  evidence jsonb DEFAULT '[]'::jsonb,
  expected_kpi_id bigint,
  expected_metric text,
  expected_direction text DEFAULT 'up'::text NOT NULL,
  baseline_value numeric,
  baseline_at timestamp with time zone DEFAULT now() NOT NULL,
  measure_after interval DEFAULT '14 days'::interval NOT NULL,
  due_at timestamp with time zone DEFAULT (now() + '14 days'::interval) NOT NULL,
  observed_value numeric,
  observed_at timestamp with time zone,
  delta numeric,
  verdict text DEFAULT 'pending'::text NOT NULL,
  promoted boolean DEFAULT false NOT NULL,
  rolled_back boolean DEFAULT false NOT NULL,
  rollback_reason text,
  lesson text,
  closed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.outreach (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  lead_id bigint,
  source text DEFAULT 'database'::text NOT NULL,
  email text,
  company text,
  contact_name text,
  contact_title text,
  category text,
  emirate text,
  channel text DEFAULT 'email'::text NOT NULL,
  status text DEFAULT 'queued'::text NOT NULL,
  subject text,
  body text,
  batch_date date DEFAULT CURRENT_DATE,
  sent_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.outreach_channel_policy (
  channel_key text NOT NULL,
  channel_label text NOT NULL,
  status text DEFAULT 'blocked'::text NOT NULL,
  status_reason text NOT NULL,
  max_per_day numeric,
  max_per_week numeric,
  ramp_start_per_day numeric,
  ramp_weekly_growth numeric,
  halt_bounce_pct numeric,
  halt_complaint_pct numeric,
  shares_transactional_reputation boolean DEFAULT false NOT NULL,
  requires_opt_in boolean DEFAULT false NOT NULL,
  authority text NOT NULL,
  reviewed_at timestamp with time zone DEFAULT now() NOT NULL,
  note text,
  limit_basis text DEFAULT 'estimate'::text NOT NULL,
  limit_uncertainty text,
  ramp_monthly_increment numeric,
  ramp_ceiling_per_day numeric,
  operator_kind text,
  operator_identity text,
  precondition text
);

CREATE TABLE IF NOT EXISTS public.pages (
  slug text NOT NULL,
  html text NOT NULL,
  updated_at timestamp with time zone DEFAULT now(),
  html_gz text,
  _osb bytea
);

CREATE TABLE IF NOT EXISTS public.paid_route_exception (
  route text NOT NULL,
  enabled boolean DEFAULT false NOT NULL,
  model_id text NOT NULL,
  max_tokens_per_call integer NOT NULL,
  daily_cap_aed numeric(10,2) NOT NULL,
  authority_instruction_id bigint,
  note text,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.pdpl_erase_files (
  id bigint DEFAULT nextval('pdpl_erase_files_id_seq'::regclass) NOT NULL,
  request_id uuid NOT NULL,
  subject_email text NOT NULL,
  bucket text,
  storage_path text,
  dropbox_path text,
  origin text,
  status text DEFAULT 'pending'::text NOT NULL,
  error text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  erased_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.pdpl_lead_erase_vault (
  request_id uuid NOT NULL,
  lead_id bigint NOT NULL,
  snapshot jsonb NOT NULL,
  erased_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.pdpl_operator_log (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  at timestamp with time zone DEFAULT now() NOT NULL,
  db_user text DEFAULT SESSION_USER NOT NULL,
  actor text DEFAULT fn_pdpl_actor() NOT NULL,
  caller text,
  operator text,
  action text NOT NULL,
  email text,
  request_id uuid,
  result jsonb
);

CREATE TABLE IF NOT EXISTS public.pdpl_requests (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  kind text NOT NULL,
  email text NOT NULL,
  role text,
  details text,
  status text DEFAULT 'received'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  handled_at timestamp with time zone,
  handled_by text,
  verified_via text,
  verified_at timestamp with time zone,
  code_sha text,
  code_expires timestamp with time zone,
  confirm_after timestamp with time zone,
  completed_at timestamp with time zone,
  cancelled_at timestamp with time zone,
  outcome jsonb,
  attempts integer DEFAULT 0 NOT NULL
);

CREATE TABLE IF NOT EXISTS public.phase1_rollback_log (
  id bigint DEFAULT nextval('phase1_rollback_log_id_seq'::regclass) NOT NULL,
  at timestamp with time zone DEFAULT now() NOT NULL,
  actor text NOT NULL,
  tier text NOT NULL,
  reason text NOT NULL,
  detail jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS public.phone_code (
  id bigint DEFAULT nextval('phone_code_id_seq'::regclass) NOT NULL,
  phone text NOT NULL,
  purpose text NOT NULL,
  user_kind text,
  email text,
  code_hash text NOT NULL,
  message_sid text,
  attempts integer DEFAULT 0 NOT NULL,
  expires_at timestamp with time zone NOT NULL,
  used_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.phone_verifications (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  email text,
  phone text NOT NULL,
  code text NOT NULL,
  user_kind text DEFAULT 'customer'::text NOT NULL,
  expires_at timestamp with time zone NOT NULL,
  used_at timestamp with time zone,
  attempts integer DEFAULT 0 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.po_lines (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  po_id bigint NOT NULL,
  line_no integer NOT NULL,
  description text NOT NULL,
  account_code text NOT NULL,
  item_id bigint,
  qty numeric(18,4) NOT NULL,
  unit_price numeric(18,4) DEFAULT 0 NOT NULL,
  qty_received numeric(18,4) DEFAULT 0 NOT NULL,
  qty_billed numeric(18,4) DEFAULT 0 NOT NULL
);

CREATE TABLE IF NOT EXISTS public.po_orders (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  po_no text,
  vendor_id bigint NOT NULL,
  order_date date DEFAULT CURRENT_DATE NOT NULL,
  expected_date date,
  currency text DEFAULT 'AED'::text NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  memo text,
  subtotal numeric(18,2) DEFAULT 0 NOT NULL,
  created_by text,
  approved_by text,
  approved_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  customer_id uuid,
  inquiry_id uuid,
  quote_id uuid,
  project_id uuid
);

CREATE TABLE IF NOT EXISTS public.po_vendors (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  name text NOT NULL,
  email text,
  phone text,
  trn text,
  currency text DEFAULT 'AED'::text NOT NULL,
  is_active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.policy_rules (
  id bigint DEFAULT nextval('policy_rules_id_seq'::regclass) NOT NULL,
  name text NOT NULL,
  severity text DEFAULT 'high'::text NOT NULL,
  forbid_regex text NOT NULL,
  scope text DEFAULT 'all'::text NOT NULL,
  note text,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.post_reveal_dispute (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  transaction_id uuid NOT NULL,
  inquiry_id uuid,
  customer_id uuid,
  supplier_id bigint,
  raised_by text NOT NULL,
  statement text NOT NULL,
  stage text DEFAULT 'evidence'::text NOT NULL,
  evidence_due timestamp with time zone NOT NULL,
  customer_evidence jsonb,
  supplier_evidence jsonb,
  intake_question_id bigint,
  fault_question_id bigint,
  finding text,
  finding_reasoning text,
  finding_model text,
  review jsonb,
  decision_due timestamp with time zone,
  outcome text,
  outcome_note text,
  decided_by text,
  decided_at timestamp with time zone,
  opened_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.price_benchmark (
  id bigint DEFAULT nextval('price_benchmark_id_seq'::regclass) NOT NULL,
  category text NOT NULL,
  source_category text,
  item text,
  unit text NOT NULL,
  basis_kind text NOT NULL,
  currency text DEFAULT 'AED'::text NOT NULL,
  low numeric,
  typical numeric,
  high numeric,
  evidence text,
  source_kind text NOT NULL,
  source_ref text NOT NULL,
  as_of date,
  confidence text NOT NULL,
  gap_reason text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.price_trade_term (
  term text NOT NULL,
  category text NOT NULL,
  lang text DEFAULT 'ar'::text NOT NULL,
  item_hint text,
  note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.pricing_config (
  id integer DEFAULT 1 NOT NULL,
  promo_reveal_rate numeric DEFAULT 0.03 NOT NULL,
  promo_reveal_cap numeric DEFAULT 99999999 NOT NULL,
  standard_reveal_rate numeric DEFAULT 0.03 NOT NULL,
  standard_reveal_cap numeric DEFAULT 99999999 NOT NULL,
  promo_until timestamp with time zone,
  supplier_free_count integer DEFAULT 1000 NOT NULL,
  supplier_reg_fee numeric DEFAULT 1000 NOT NULL,
  supplier_reg_period text DEFAULT 'yearly'::text NOT NULL,
  refund_window_working_days integer DEFAULT 3 NOT NULL,
  updated_at timestamp with time zone DEFAULT now(),
  auto_approve_suppliers boolean DEFAULT false,
  supplier_reg_currency text DEFAULT 'AED'::text NOT NULL,
  reveal_currency text DEFAULT 'AED'::text NOT NULL,
  supplier_charging_starts date,
  category_open_min_suppliers integer DEFAULT 10 NOT NULL,
  chase_after_working_days integer DEFAULT 3 NOT NULL,
  bank_settlement_working_days_min integer DEFAULT 7 NOT NULL,
  bank_settlement_working_days_max integer DEFAULT 14 NOT NULL,
  supplier_nonresponse_admin_fee_aed numeric(12,2) DEFAULT 250.00 NOT NULL,
  supplier_nonresponse_interest_apr numeric(6,4) DEFAULT 0.0900 NOT NULL,
  supplier_nonresponse_min_attempts integer DEFAULT 2 NOT NULL,
  supplier_nonresponse_min_channels integer DEFAULT 2 NOT NULL
);

CREATE TABLE IF NOT EXISTS public.projects (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  customer_id uuid,
  name text NOT NULL,
  description text,
  status text DEFAULT 'active'::text NOT NULL,
  target_open_date date,
  budget_total numeric,
  meta jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.prompt_benchmarks (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  prompt_key text NOT NULL,
  name text NOT NULL,
  input text NOT NULL,
  rubric text NOT NULL,
  weight numeric DEFAULT 1 NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.prompt_eval_runs (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  prompt_key text NOT NULL,
  version integer,
  score numeric,
  cases_total integer,
  detail jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.prompt_versions (
  id bigint DEFAULT nextval('prompt_versions_id_seq'::regclass) NOT NULL,
  prompt_key text,
  version integer NOT NULL,
  content text NOT NULL,
  status text DEFAULT 'active'::text,
  rollout_pct integer DEFAULT 100,
  eval_score numeric,
  approved_by text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.prompts (
  key text NOT NULL,
  owner text,
  description text,
  active_version integer DEFAULT 1,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.public_holidays (
  holiday_date date NOT NULL,
  name text NOT NULL,
  confirmed boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.qa_results (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  run_at timestamp with time zone DEFAULT now(),
  passed boolean,
  total integer,
  failed integer,
  results jsonb
);

CREATE TABLE IF NOT EXISTS public.qd_compare_cache (
  inquiry_id text NOT NULL,
  quotes_hash text NOT NULL,
  lang text DEFAULT 'en'::text NOT NULL,
  analysis jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.qd_deploy_src (
  path text NOT NULL,
  data text
);

CREATE TABLE IF NOT EXISTS public.qd_i18n (
  source text NOT NULL,
  slug text NOT NULL,
  title text,
  html text,
  status text DEFAULT 'done'::text,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.qd_i18n_chunks (
  source text NOT NULL,
  slug text NOT NULL,
  idx integer NOT NULL,
  ar text
);

CREATE TABLE IF NOT EXISTS public.qualification_playbooks (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  category text NOT NULL,
  version integer DEFAULT 1 NOT NULL,
  status text DEFAULT 'active'::text NOT NULL,
  questions jsonb DEFAULT '[]'::jsonb NOT NULL,
  effective_date date DEFAULT CURRENT_DATE,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.quality_standard (
  work_type text NOT NULL,
  criteria jsonb NOT NULL,
  owner_dept text,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.questions (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  inquiry_id uuid,
  supplier_id bigint,
  customer_id uuid,
  question text NOT NULL,
  answer text,
  asked_at timestamp with time zone DEFAULT now(),
  answered_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.quote_aspect_reading (
  quote_id uuid NOT NULL,
  content_md5 text NOT NULL,
  present text[],
  status text NOT NULL,
  held_id bigint,
  reasoned_at timestamp with time zone,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.quote_committed_items (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  review_id uuid NOT NULL,
  seq integer DEFAULT 0,
  description text,
  brand text,
  model text,
  spec text,
  qty text,
  unit_price numeric,
  line_amount numeric,
  warranty text,
  source text DEFAULT 'own'::text,
  sub_quote_path text,
  sub_cost numeric,
  markup_pct numeric,
  customer_description text,
  hide_brand boolean DEFAULT false,
  confirmed boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.quote_comparisons (
  id bigint DEFAULT nextval('quote_comparisons_id_seq'::regclass) NOT NULL,
  inquiry_id uuid NOT NULL,
  customer_id uuid,
  lang text DEFAULT 'en'::text,
  quote_count integer,
  signature text,
  analysis jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  publication_state text DEFAULT 'DRAFT'::text NOT NULL,
  published_at timestamp with time zone,
  superseded_by_comparison_id bigint
);

CREATE TABLE IF NOT EXISTS public.quote_extraction_model (
  subject_key text NOT NULL,
  model text NOT NULL,
  extracted_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.quote_items (
  id bigint DEFAULT nextval('quote_items_id_seq'::regclass) NOT NULL,
  quote_id text NOT NULL,
  line_no integer,
  description text,
  brand text,
  model text,
  specification text,
  qty numeric,
  unit text,
  unit_price numeric,
  labour numeric,
  install numeric,
  commissioning numeric,
  amount numeric,
  country_of_origin text,
  datasheet_path text,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  spec jsonb DEFAULT '{}'::jsonb NOT NULL,
  spec_source jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS public.quote_pdf_cache (
  quote_id uuid NOT NULL,
  lang text NOT NULL,
  customer_id uuid,
  bucket text NOT NULL,
  path text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.quote_quality_hold (
  quote_id uuid NOT NULL,
  inquiry_id uuid,
  supplier_id bigint,
  fixture boolean DEFAULT false NOT NULL,
  flags jsonb DEFAULT '[]'::jsonb NOT NULL,
  fixes_en text,
  fixes_sent_md5 text,
  fixes_sent_at timestamp with time zone,
  fixes_delivery jsonb,
  held_at timestamp with time zone DEFAULT now() NOT NULL,
  release_due timestamp with time zone NOT NULL,
  released_at timestamp with time zone,
  release_reason text,
  corrected_at timestamp with time zone,
  accepted_md5 text NOT NULL,
  superseded_at timestamp with time zone,
  customer_notice jsonb,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.quote_requirements (
  category text NOT NULL,
  required_sections jsonb DEFAULT '[]'::jsonb NOT NULL,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.quote_review_messages (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  review_id uuid NOT NULL,
  role text NOT NULL,
  body text,
  attachments jsonb DEFAULT '[]'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  kind text DEFAULT 'text'::text NOT NULL,
  body_ar text,
  issues jsonb
);

CREATE TABLE IF NOT EXISTS public.quote_review_request (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  review_id uuid NOT NULL,
  key text NOT NULL,
  code text NOT NULL,
  kind text NOT NULL,
  line_no integer,
  boq_line integer,
  attr text,
  label_en text NOT NULL,
  label_ar text NOT NULL,
  state text DEFAULT 'open'::text NOT NULL,
  asked_message_id uuid,
  answered_message_id uuid,
  opened_at timestamp with time zone DEFAULT now() NOT NULL,
  answered_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.quote_reviews (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  inquiry_id uuid NOT NULL,
  supplier_id bigint NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  original_file_path text,
  original_file_name text,
  extracted jsonb,
  currency text DEFAULT 'AED'::text,
  total_amount numeric,
  completed_at timestamp with time zone,
  committed_hash text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  owner_email text,
  choice text,
  working jsonb,
  last_review jsonb,
  reviewing_since timestamp with time zone,
  submitted_quote_ids uuid[],
  owner_seat text DEFAULT 'sales_engineer'::text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.quote_spec_hold (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  quote_id uuid NOT NULL,
  inquiry_id uuid,
  supplier_id bigint,
  submission_id uuid,
  option_no integer DEFAULT 1 NOT NULL,
  state text NOT NULL,
  missing jsonb DEFAULT '[]'::jsonb NOT NULL,
  note_en text,
  note_ar text,
  original_snapshot jsonb NOT NULL,
  supplier_values jsonb DEFAULT '[]'::jsonb NOT NULL,
  regenerated jsonb,
  regenerated_at timestamp with time zone,
  pdf_bucket text,
  pdf_path text,
  approved_at timestamp with time zone,
  approved_by text,
  released_at timestamp with time zone,
  superseded_at timestamp with time zone,
  notified_at timestamp with time zone,
  notification_ids jsonb,
  owner_seat text DEFAULT 'sales_engineer'::text NOT NULL,
  opened_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  decided_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.quotes (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  inquiry_id uuid,
  supplier_id bigint,
  quote_amount numeric NOT NULL,
  notes text,
  margin_rate numeric GENERATED ALWAYS AS (margin_rate(quote_amount)) STORED,
  app_fee numeric GENERATED ALWAYS AS (round((quote_amount * margin_rate(quote_amount)), 2)) STORED,
  customer_price numeric GENERATED ALWAYS AS (round((quote_amount * ((1)::numeric + margin_rate(quote_amount))), 2)) STORED,
  status text DEFAULT 'submitted'::text,
  created_at timestamp with time zone DEFAULT now(),
  lead_time text,
  validity text,
  payment_terms text,
  warranty text,
  scope text,
  conditions text,
  exclusions text,
  anonymized boolean DEFAULT false,
  original_file_path text,
  original_file_name text,
  source text DEFAULT 'form'::text NOT NULL,
  masked_terms jsonb,
  extracted jsonb,
  expires_at timestamp with time zone,
  review_id uuid,
  review_status text,
  committed_at timestamp with time zone,
  committed_hash text,
  committed_items jsonb,
  quality jsonb,
  structured jsonb,
  submittable boolean DEFAULT false,
  stale_at timestamp with time zone,
  stale_reason text,
  option_no integer DEFAULT 1 NOT NULL,
  submission_id uuid,
  terms_spec jsonb,
  price_ex_vat numeric,
  vat_treatment text,
  vat_amount numeric,
  supplier_trn text,
  amount_as_stated numeric,
  extracted_by_model text,
  gross_amount numeric,
  discount_amount numeric,
  discount_label text
);

CREATE TABLE IF NOT EXISTS public.reasoning_held_question (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  seat text NOT NULL,
  surface text NOT NULL,
  question text NOT NULL,
  request jsonb NOT NULL,
  plan jsonb DEFAULT '{}'::jsonb NOT NULL,
  subject jsonb,
  reason text NOT NULL,
  status text DEFAULT 'held'::text NOT NULL,
  expires_at timestamp with time zone DEFAULT (now() + '14 days'::interval),
  attempts integer DEFAULT 0 NOT NULL,
  last_attempt_at timestamp with time zone,
  result jsonb,
  reasoned_at timestamp with time zone,
  applied_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  dedupe_key text,
  escalated_at timestamp with time zone,
  notice_attempts integer DEFAULT 0 NOT NULL,
  notice_last_at timestamp with time zone,
  notice_delivered_at timestamp with time zone,
  notice_detail jsonb,
  qhash text
);

CREATE TABLE IF NOT EXISTS public.reasoning_knowledge_candidate (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  seat text NOT NULL,
  question text NOT NULL,
  finding text NOT NULL,
  sources jsonb NOT NULL,
  embedding_gte vector(384),
  status text DEFAULT 'pending_review'::text NOT NULL,
  reviewed_by text,
  reviewed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  finding_sha text GENERATED ALWAYS AS (md5(lower(btrim(finding)))) STORED
);

CREATE TABLE IF NOT EXISTS public.red_episode (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  source text NOT NULL,
  check_key text NOT NULL,
  detail text,
  opened_at timestamp with time zone NOT NULL,
  observed_at timestamp with time zone DEFAULT now() NOT NULL,
  last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  alerted_at timestamp with time zone,
  alert_dedupe_key text,
  paged_by text,
  resolved_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.refund_case (
  refund_id bigint DEFAULT nextval('refund_case_refund_id_seq'::regclass) NOT NULL,
  transaction_id uuid NOT NULL,
  case_id bigint,
  state text DEFAULT 'requested'::text NOT NULL,
  amount_aed numeric NOT NULL,
  currency text DEFAULT 'AED'::text NOT NULL,
  requested_reason text NOT NULL,
  investigated_at timestamp with time zone,
  evidence jsonb,
  eligibility text,
  eligibility_reason text,
  decided_by text,
  decided_at timestamp with time zone,
  decision text,
  decision_rationale text,
  destination_ref text,
  provider_ref text,
  submitted_at timestamp with time zone,
  provider_status text,
  settled_at timestamp with time zone,
  failure_reason text,
  reconciled_at timestamp with time zone,
  communicated_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  destination_basis text,
  attempts integer DEFAULT 0 NOT NULL,
  last_attempt_at timestamp with time zone,
  status_reported_at timestamp with time zone,
  status_reported_state text
);

CREATE TABLE IF NOT EXISTS public.refund_ceo_check (
  id bigint DEFAULT nextval('refund_ceo_check_id_seq'::regclass) NOT NULL,
  transaction_id uuid NOT NULL,
  refund_id bigint,
  phase text NOT NULL,
  item text NOT NULL,
  passed boolean NOT NULL,
  reason text,
  evidence jsonb DEFAULT '{}'::jsonb NOT NULL,
  checked_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.refund_ceo_review (
  id bigint DEFAULT nextval('refund_ceo_review_id_seq'::regclass) NOT NULL,
  refund_id bigint NOT NULL,
  transaction_id uuid,
  cycle integer NOT NULL,
  outcome text NOT NULL,
  failed jsonb DEFAULT '[]'::jsonb NOT NULL,
  tasks jsonb DEFAULT '[]'::jsonb NOT NULL,
  decision_id bigint,
  trigger text,
  sealed boolean DEFAULT false NOT NULL,
  rechecked_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.refund_event_quarantine (
  id bigint DEFAULT nextval('refund_event_quarantine_id_seq'::regclass) NOT NULL,
  stripe_refund_id text,
  stripe_event_id text,
  event_type text,
  reason text NOT NULL,
  payload jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  resolved_at timestamp with time zone,
  resolved_by text,
  resolution_note text
);

CREATE TABLE IF NOT EXISTS public.refund_incident (
  id bigint DEFAULT nextval('refund_incident_id_seq'::regclass) NOT NULL,
  transaction_id uuid NOT NULL,
  refund_id bigint,
  kinds text[] DEFAULT '{}'::text[] NOT NULL,
  approved_aed numeric(12,2),
  actual_aed numeric(12,2),
  difference_aed numeric(12,2),
  status text DEFAULT 'open'::text NOT NULL,
  sealed boolean DEFAULT false NOT NULL,
  fixes jsonb DEFAULT '[]'::jsonb NOT NULL,
  evidence jsonb DEFAULT '{}'::jsonb NOT NULL,
  opened_at timestamp with time zone DEFAULT now() NOT NULL,
  closed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.refund_ladder_evidence (
  id bigint DEFAULT nextval('refund_ladder_evidence_id_seq'::regclass) NOT NULL,
  transaction_id uuid NOT NULL,
  refund_id bigint,
  step text NOT NULL,
  result text NOT NULL,
  delivered boolean NOT NULL,
  evidence jsonb DEFAULT '{}'::jsonb NOT NULL,
  request_handoff_id bigint,
  result_handoff_id bigint,
  attached_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.refund_status_transition (
  from_status text NOT NULL,
  to_status text NOT NULL,
  allowed boolean NOT NULL,
  note text
);

CREATE TABLE IF NOT EXISTS public.refunds (
  id bigint DEFAULT nextval('refunds_id_seq'::regclass) NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  inquiry_id uuid,
  customer_id uuid,
  supplier_lead_id bigint,
  original_txn_id bigint,
  stripe_payment_intent text,
  stripe_charge_id text,
  stripe_refund_id text,
  amount_fils bigint,
  currency text DEFAULT 'AED'::text NOT NULL,
  reason_code text NOT NULL,
  reason_note text,
  status text DEFAULT 'requested'::text NOT NULL,
  requested_by text NOT NULL,
  requested_at timestamp with time zone DEFAULT now() NOT NULL,
  decided_by text,
  decided_at timestamp with time zone,
  decision_note text,
  within_auto_window boolean DEFAULT false NOT NULL,
  settled_at timestamp with time zone,
  failure_reason text,
  gl_entry_id bigint,
  reconciled_at timestamp with time zone,
  reconciliation_note text,
  transaction_id uuid,
  quote_id uuid,
  amount_source text,
  refund_decision_id bigint,
  stripe_receipt_url text,
  doc_path text,
  doc_name text,
  doc_content_type text,
  doc_kind text,
  doc_note text,
  topup_of bigint
);

CREATE TABLE IF NOT EXISTS public.reg_catalog (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  jurisdiction text NOT NULL,
  authority text NOT NULL,
  code_name text NOT NULL,
  domain text NOT NULL,
  categories text[],
  priority integer DEFAULT 2 NOT NULL,
  copyright text DEFAULT 'free'::text NOT NULL,
  source_url text,
  compliance_source_id bigint,
  status text DEFAULT 'needs_source'::text NOT NULL,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.regulations (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  authority text NOT NULL,
  jurisdiction text,
  categories text[] DEFAULT '{}'::text[],
  title text NOT NULL,
  doc_ref text,
  summary text,
  key_requirements jsonb DEFAULT '[]'::jsonb,
  source_url text,
  effective_date date,
  version integer DEFAULT 1 NOT NULL,
  status text DEFAULT 'active'::text NOT NULL,
  body text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  approved_at timestamp with time zone,
  approved_by text,
  supersedes_id bigint
);

CREATE TABLE IF NOT EXISTS public.rehearsal_spend_reservation (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  e2e_run_tag text NOT NULL,
  reserved_usd numeric NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.rehearsal_window (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  run_tag text NOT NULL,
  opened_by text DEFAULT 'demo_factory.withRun'::text NOT NULL,
  started_at timestamp with time zone DEFAULT now() NOT NULL,
  ended_at timestamp with time zone,
  note text,
  models_allowed boolean DEFAULT true NOT NULL,
  cap_usd numeric DEFAULT 4 NOT NULL,
  expires_at timestamp with time zone DEFAULT (now() + '02:00:00'::interval) NOT NULL
);

CREATE TABLE IF NOT EXISTS public.removed_trigger_log (
  id bigint DEFAULT nextval('removed_trigger_log_id_seq'::regclass) NOT NULL,
  table_name text NOT NULL,
  trigger_name text NOT NULL,
  trigger_function text NOT NULL,
  missing_callees text[] NOT NULL,
  trigger_definition text NOT NULL,
  removed_at timestamp with time zone DEFAULT now() NOT NULL,
  reason text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.resilience_step (
  step text NOT NULL,
  every interval NOT NULL,
  budget_ms integer NOT NULL,
  place text DEFAULT 'plan'::text NOT NULL,
  rank integer DEFAULT 0 NOT NULL,
  note text NOT NULL,
  last_started_at timestamp with time zone,
  last_ok_at timestamp with time zone,
  last_ms integer,
  ewma_ms integer,
  deferrals integer DEFAULT 0 NOT NULL,
  deferred_since timestamp with time zone,
  owner_seat text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.resource_pool (
  id bigint DEFAULT nextval('resource_pool_id_seq'::regclass) NOT NULL,
  resource text NOT NULL,
  kind text NOT NULL,
  owner_dept text,
  unit text NOT NULL,
  capacity numeric NOT NULL,
  committed numeric DEFAULT 0 NOT NULL,
  window_label text,
  degrade_at_pct integer DEFAULT 80 NOT NULL,
  halt_at_pct integer DEFAULT 100 NOT NULL,
  source_ref text,
  note text,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  os_key text
);

CREATE TABLE IF NOT EXISTS public.response_template (
  key text NOT NULL,
  channel text DEFAULT 'any'::text NOT NULL,
  intent text NOT NULL,
  body text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  used_count integer DEFAULT 0 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  body_ar text
);

CREATE TABLE IF NOT EXISTS public.retention_policy (
  bucket text NOT NULL,
  retention_days integer,
  class text NOT NULL,
  notes text
);

CREATE TABLE IF NOT EXISTS public.reveal_invoices (
  transaction_id uuid NOT NULL,
  invoice_no text,
  bucket text,
  path text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.review_chain (
  id bigint DEFAULT nextval('review_chain_id_seq'::regclass) NOT NULL,
  subject_type text NOT NULL,
  subject_id text NOT NULL,
  dept_key text,
  author_agent text NOT NULL,
  reviewer_agent text,
  stage text NOT NULL,
  decision text,
  reason text,
  violated_rule text,
  confidence numeric,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  delegated_from text,
  delegation_basis text
);

CREATE TABLE IF NOT EXISTS public.review_hold (
  id bigint DEFAULT nextval('review_hold_id_seq'::regclass) NOT NULL,
  task_class text NOT NULL,
  fn text,
  agent_key text,
  counterpart_model text NOT NULL,
  why text NOT NULL,
  held_at timestamp with time zone DEFAULT now() NOT NULL,
  last_held_at timestamp with time zone DEFAULT now() NOT NULL,
  times_held integer DEFAULT 1 NOT NULL,
  closed_at timestamp with time zone,
  close_note text
);

CREATE TABLE IF NOT EXISTS public.review_pool (
  model_id text NOT NULL,
  rank integer NOT NULL,
  active boolean DEFAULT true NOT NULL,
  note text NOT NULL,
  added_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.review_queue (
  id bigint DEFAULT nextval('review_queue_id_seq'::regclass) NOT NULL,
  kind text NOT NULL,
  dept_key text,
  title text NOT NULL,
  summary text,
  payload jsonb,
  status text DEFAULT 'pending'::text NOT NULL,
  founder_comment text,
  created_at timestamp with time zone DEFAULT now(),
  decided_at timestamp with time zone,
  decided_by text
);

CREATE TABLE IF NOT EXISTS public.review_route (
  decision_type text NOT NULL,
  owner_seat text NOT NULL,
  meaning text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.reviews (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  supplier_id bigint,
  customer_id uuid,
  inquiry_id uuid,
  transaction_id uuid,
  rating integer NOT NULL,
  comment text,
  created_at timestamp with time zone DEFAULT now(),
  r_communication smallint,
  r_quality smallint,
  r_punctuality smallint,
  r_documentation smallint,
  r_after_sales smallint,
  r_compliance smallint,
  photo_paths text[] DEFAULT '{}'::text[] NOT NULL
);

CREATE TABLE IF NOT EXISTS public.rfq_archives (
  id bigint DEFAULT nextval('rfq_archives_id_seq'::regclass) NOT NULL,
  rfq_id text NOT NULL,
  customer_id text,
  supplier_ids text[] DEFAULT '{}'::text[],
  category text,
  status text,
  dates jsonb,
  bucket text DEFAULT 'backups'::text,
  archive_path text,
  checksum text,
  archive_version integer DEFAULT 1,
  ai_summary jsonb,
  size_bytes integer,
  created_at timestamp with time zone DEFAULT now(),
  restored_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.rfq_clarification (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  inquiry_id uuid NOT NULL,
  supplier_id bigint,
  kind text NOT NULL,
  question text,
  answer text,
  source text DEFAULT 'portal'::text NOT NULL,
  asked_at timestamp with time zone DEFAULT now() NOT NULL,
  answered_at timestamp with time zone,
  answer_as_written text,
  english_held_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.risk_register (
  id bigint DEFAULT nextval('risk_register_id_seq'::regclass) NOT NULL,
  dept_key text NOT NULL,
  risk text NOT NULL,
  category text,
  probability text DEFAULT 'medium'::text NOT NULL,
  impact text DEFAULT 'medium'::text NOT NULL,
  owner_agent text,
  mitigation text,
  status text DEFAULT 'open'::text NOT NULL,
  review_due date,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.rl_hits (
  k text NOT NULL,
  at timestamp with time zone DEFAULT now() NOT NULL,
  _pk bigint GENERATED ALWAYS AS IDENTITY NOT NULL
);

CREATE TABLE IF NOT EXISTS public.roles (
  name text NOT NULL,
  description text
);

CREATE TABLE IF NOT EXISTS public.routine_change_log (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  at timestamp with time zone DEFAULT now() NOT NULL,
  txid bigint DEFAULT txid_current() NOT NULL,
  session_user_name text DEFAULT SESSION_USER NOT NULL,
  application_name text,
  client_addr inet,
  backend_pid integer DEFAULT pg_backend_pid() NOT NULL,
  command_tag text NOT NULL,
  object_identity text NOT NULL,
  statement_head text
);

CREATE TABLE IF NOT EXISTS public.routine_judgement (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  kind text NOT NULL,
  subject_key text NOT NULL,
  input jsonb NOT NULL,
  status text DEFAULT 'queued'::text NOT NULL,
  result jsonb,
  model text,
  attempts integer DEFAULT 0 NOT NULL,
  last_error text,
  leased_until timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  decided_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.sales_decision_log (
  id bigint DEFAULT nextval('sales_decision_log_id_seq'::regclass) NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  actor text NOT NULL,
  action text NOT NULL,
  query text,
  min_similarity numeric,
  min_rank numeric,
  k integer,
  candidates jsonb DEFAULT '[]'::jsonb NOT NULL,
  cited text[] DEFAULT '{}'::text[] NOT NULL,
  answered boolean NOT NULL,
  refusal text,
  subject text,
  e2e_run_tag text
);

CREATE TABLE IF NOT EXISTS public.sales_engineer_comparison_report (
  inquiry_id uuid NOT NULL,
  quotes_hash text NOT NULL,
  quotes_n integer NOT NULL,
  complete_n integer NOT NULL,
  lines jsonb NOT NULL,
  recommended_quote_id uuid,
  recommendation text NOT NULL,
  hours_to_report numeric,
  delivered_at timestamp with time zone,
  delivery_handoff_id bigint,
  reported_at timestamp with time zone DEFAULT now() NOT NULL,
  refreshed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.sales_engineer_framework_proposal (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  customer_id uuid NOT NULL,
  trade text NOT NULL,
  requests_180d integer NOT NULL,
  quoted_total_aed numeric,
  draft text NOT NULL,
  status text DEFAULT 'drafted'::text NOT NULL,
  ceo_task_id bigint,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.sales_engineer_negotiation_round (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  inquiry_id uuid NOT NULL,
  quote_id uuid NOT NULL,
  round text NOT NULL,
  asked_for jsonb NOT NULL,
  handoff_id bigint,
  asked_at timestamp with time zone DEFAULT now() NOT NULL,
  answered_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.sales_engineer_onboarding_week (
  week date NOT NULL,
  stages jsonb NOT NULL,
  reached jsonb NOT NULL,
  conversion_pct jsonb NOT NULL,
  invites_sent_7d integer NOT NULL,
  invites_clicked_7d integer NOT NULL,
  bottleneck text,
  improvement_id bigint,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.sales_engineer_win_loss_month (
  month date NOT NULL,
  requests_quoted integer NOT NULL,
  revealed integer NOT NULL,
  hired integer NOT NULL,
  not_hired integer NOT NULL,
  no_decision integer NOT NULL,
  leakage_suspect integer NOT NULL,
  loss_reasons jsonb NOT NULL,
  improvement_id bigint,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.sales_knowledge (
  record_id text NOT NULL,
  record_type text NOT NULL,
  domain text,
  title text NOT NULL,
  content text NOT NULL,
  structured_data jsonb DEFAULT '{}'::jsonb NOT NULL,
  source_ids text[] DEFAULT '{}'::text[] NOT NULL,
  epistemic_status text NOT NULL,
  jurisdiction text,
  pack_id text NOT NULL,
  pack_version text NOT NULL,
  record_version text NOT NULL,
  body_sha256 text NOT NULL,
  content_sha256 text NOT NULL,
  runtime_index_eligible boolean DEFAULT true NOT NULL,
  authority_effect text DEFAULT 'none'::text NOT NULL,
  tags text[] DEFAULT '{}'::text[] NOT NULL,
  updated_at timestamp with time zone,
  ingested_at timestamp with time zone DEFAULT now() NOT NULL,
  embedding_gte vector(384),
  search tsvector
);

CREATE TABLE IF NOT EXISTS public.sales_knowledge_gap (
  id bigint DEFAULT nextval('sales_knowledge_gap_id_seq'::regclass) NOT NULL,
  question_norm text NOT NULL,
  question text NOT NULL,
  asks integer DEFAULT 1 NOT NULL,
  first_asked_at timestamp with time zone DEFAULT now() NOT NULL,
  last_asked_at timestamp with time zone DEFAULT now() NOT NULL,
  refusal text,
  best_similarity numeric,
  best_lexical_rank numeric,
  nearest_corpus text,
  task_id bigint,
  status text DEFAULT 'open'::text NOT NULL,
  closed_at timestamp with time zone,
  kind text DEFAULT 'refusal'::text NOT NULL,
  source text,
  source_ref text,
  excerpt text,
  detector text,
  owner_seat text,
  due_at timestamp with time zone,
  routed_at timestamp with time zone,
  handoff_id bigint,
  chase_count integer DEFAULT 0 NOT NULL,
  chased_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.sales_qualification_field (
  field_key text NOT NULL,
  sector_id text NOT NULL,
  question text NOT NULL,
  answer_type text,
  ask_only_if text,
  criticality text,
  unknown_handling text
);

CREATE TABLE IF NOT EXISTS public.sales_sector (
  sector_id text NOT NULL,
  group_key text,
  title text NOT NULL,
  scope text,
  maps_to_trades text[] DEFAULT '{}'::text[] NOT NULL
);

CREATE TABLE IF NOT EXISTS public.sanctions_ban (
  id bigint DEFAULT nextval('sanctions_ban_id_seq'::regclass) NOT NULL,
  lead_id bigint NOT NULL,
  hit_id bigint,
  entry_source text,
  entry_reference text,
  entry_name text,
  name_key text,
  licence_key text,
  account_email text,
  contact_email text,
  decided_by text NOT NULL,
  decided_at timestamp with time zone DEFAULT now() NOT NULL,
  note text
);

CREATE TABLE IF NOT EXISTS public.scenario_library (
  scenario_key text NOT NULL,
  name text NOT NULL,
  category text,
  situation text NOT NULL,
  expected_behaviour text NOT NULL,
  departments text[],
  last_run timestamp with time zone,
  last_result text,
  notes text,
  last_staffing_check timestamp with time zone,
  last_staffing_result text
);

CREATE TABLE IF NOT EXISTS public.scope_component (
  component text NOT NULL,
  label_en text NOT NULL,
  label_ar text,
  sort_order integer DEFAULT 0 NOT NULL
);

CREATE TABLE IF NOT EXISTS public.scope_disposition_kind (
  disposition text NOT NULL,
  contributes boolean NOT NULL,
  requires_clarification boolean DEFAULT false NOT NULL,
  is_conflict boolean DEFAULT false NOT NULL,
  label_en text NOT NULL,
  rationale text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.scrape_runs (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  run_id text,
  dataset_id text,
  actor text,
  sector text,
  emirate text,
  label text,
  status text DEFAULT 'RUNNING'::text,
  requested integer,
  fetched integer DEFAULT 0,
  inserted integer DEFAULT 0,
  created_at timestamp with time zone DEFAULT now(),
  collected_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.screening_entry (
  id bigint DEFAULT nextval('screening_entry_id_seq'::regclass) NOT NULL,
  run_id bigint NOT NULL,
  source text NOT NULL,
  entry_type text NOT NULL,
  reference text,
  name text NOT NULL,
  name_norm text,
  tokens text[]
);

CREATE TABLE IF NOT EXISTS public.screening_run (
  id bigint DEFAULT nextval('screening_run_id_seq'::regclass) NOT NULL,
  source text NOT NULL,
  source_url text,
  fetched_at timestamp with time zone DEFAULT now() NOT NULL,
  sha256 text,
  entries integer DEFAULT 0 NOT NULL,
  status text DEFAULT 'ok'::text NOT NULL,
  note text,
  run_tag text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.seat_case_memory (
  id bigint DEFAULT nextval('seat_case_memory_id_seq'::regclass) NOT NULL,
  seat text NOT NULL,
  case_kind text NOT NULL,
  source_table text NOT NULL,
  source_id text NOT NULL,
  trade text,
  situation text NOT NULL,
  decision text,
  reasoning text,
  outcome text,
  finalised boolean DEFAULT false NOT NULL,
  finalised_at timestamp with time zone,
  lessons text[] DEFAULT '{}'::text[] NOT NULL,
  corrected_by text,
  correction text,
  embedding vector(384),
  embedded_hash text,
  embed_claimed_at timestamp with time zone,
  opened_at timestamp with time zone DEFAULT now() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.seat_case_memory_miss (
  id bigint DEFAULT nextval('seat_case_memory_miss_id_seq'::regclass) NOT NULL,
  source_table text NOT NULL,
  source_id text,
  error text NOT NULL,
  at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.seat_deliberation (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  kind text NOT NULL,
  author_seat text NOT NULL,
  reviewer_seat text NOT NULL,
  question text NOT NULL,
  evidence jsonb NOT NULL,
  proposal jsonb NOT NULL,
  author_model text NOT NULL,
  author_provider text NOT NULL,
  max_rounds integer DEFAULT 2 NOT NULL,
  round integer DEFAULT 1 NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  outcome text,
  subject_table text,
  subject_id text,
  handoff_id bigint,
  demo boolean DEFAULT false NOT NULL,
  opened_at timestamp with time zone DEFAULT now() NOT NULL,
  closed_at timestamp with time zone,
  proceeded_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.seat_deliberation_ceiling (
  author_seat text NOT NULL,
  reviewer_seat text NOT NULL,
  dept_key text NOT NULL,
  cap_aed_month numeric NOT NULL,
  note text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.seat_deliberation_turn (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  deliberation_id bigint NOT NULL,
  round integer NOT NULL,
  phase text NOT NULL,
  seat text NOT NULL,
  status text NOT NULL,
  task_class text,
  model text,
  provider text,
  reviews_turn_id bigint,
  verdict text,
  steelman_against text,
  agreements text,
  disagreements text,
  output jsonb DEFAULT '{}'::jsonb NOT NULL,
  payload_sha256 text,
  why text,
  prompt_tokens integer,
  output_tokens integer,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.seat_duty (
  duty text NOT NULL,
  owner_seat text NOT NULL,
  every interval NOT NULL,
  routine text NOT NULL,
  what text NOT NULL,
  owner_file text NOT NULL,
  enabled boolean DEFAULT true NOT NULL,
  last_started_at timestamp with time zone,
  last_ok_at timestamp with time zone,
  last_result jsonb,
  last_error text,
  failures integer DEFAULT 0 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  avg_ms integer,
  own_job boolean DEFAULT false NOT NULL
);

CREATE TABLE IF NOT EXISTS public.seat_duty_skip (
  duty text NOT NULL,
  skips integer DEFAULT 0 NOT NULL,
  first_skipped_at timestamp with time zone DEFAULT now() NOT NULL,
  last_skipped_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.seat_exam_asked (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  run_tag text NOT NULL,
  asked_at timestamp with time zone DEFAULT now() NOT NULL,
  seat text NOT NULL,
  item_id text NOT NULL,
  wording text NOT NULL,
  answer text,
  model text,
  status text NOT NULL,
  pass boolean NOT NULL,
  graded_by text NOT NULL,
  missing text[] DEFAULT '{}'::text[] NOT NULL,
  fix_id bigint
);

CREATE TABLE IF NOT EXISTS public.seat_exam_fix (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  seat text NOT NULL,
  item_id text NOT NULL,
  opened_at timestamp with time zone DEFAULT now() NOT NULL,
  opened_run text NOT NULL,
  kind text,
  fix_ref text,
  status text DEFAULT 'open'::text NOT NULL,
  closed_at timestamp with time zone,
  closed_by_asked_id bigint
);

CREATE TABLE IF NOT EXISTS public.seat_exam_item (
  seat text NOT NULL,
  item_id text NOT NULL,
  checklist text NOT NULL,
  q_en text NOT NULL,
  expected_entry_ids text[] NOT NULL,
  expected_facts text[] NOT NULL,
  q_vec vector,
  source_file text NOT NULL,
  loaded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.seat_handoff_kind (
  type text NOT NULL,
  from_seat text NOT NULL,
  to_seat text NOT NULL,
  meaning text NOT NULL,
  handler text NOT NULL,
  reply_within interval,
  originator_closes boolean DEFAULT false NOT NULL,
  owner_file text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.seat_judgement (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  seat text NOT NULL,
  surface text NOT NULL,
  subject jsonb,
  subject_table text,
  subject_id text,
  question text,
  recall jsonb,
  status text DEFAULT 'recalled'::text NOT NULL,
  decision text,
  confidence numeric,
  model text,
  decided_at timestamp with time zone,
  outcome text,
  outcome_correct boolean,
  finalised boolean DEFAULT false NOT NULL,
  outcome_at timestamp with time zone,
  made_at timestamp with time zone DEFAULT now() NOT NULL,
  followed_case_ids bigint[],
  outcome_kind text,
  outcome_reason text
);

CREATE TABLE IF NOT EXISTS public.seat_knowledge_eval_question (
  id bigint DEFAULT nextval('seat_knowledge_eval_question_id_seq'::regclass) NOT NULL,
  seat text NOT NULL,
  pack text NOT NULL,
  lang text NOT NULL,
  question text NOT NULL,
  expected text[] NOT NULL,
  embedding vector(384) NOT NULL,
  loaded_at timestamp with time zone DEFAULT now() NOT NULL,
  embedding_ml vector(384)
);

CREATE TABLE IF NOT EXISTS public.seat_knowledge_exam (
  id bigint DEFAULT nextval('seat_knowledge_exam_id_seq'::regclass) NOT NULL,
  seat text NOT NULL,
  item_key text NOT NULL,
  question text NOT NULL,
  reference text NOT NULL,
  asked_held_id bigint,
  answer text,
  answer_model text,
  grade_held_id bigint,
  verdict text,
  grade_reason text,
  asked_at timestamp with time zone DEFAULT now() NOT NULL,
  answered_at timestamp with time zone,
  graded_at timestamp with time zone,
  refiled_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.seat_knowledge_recall (
  day date NOT NULL,
  seat text NOT NULL,
  questions integer NOT NULL,
  recall_en numeric,
  recall_ar numeric,
  measured_at timestamp with time zone DEFAULT now() NOT NULL,
  path text DEFAULT 'gte'::text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.seat_knowledge_recall_answer (
  day date NOT NULL,
  question_id bigint NOT NULL,
  seat text NOT NULL,
  lang text NOT NULL,
  recall numeric NOT NULL
);

CREATE TABLE IF NOT EXISTS public.seat_knowledge_recall_floor (
  seat text NOT NULL,
  lang text NOT NULL,
  floor numeric NOT NULL,
  set_on date NOT NULL,
  set_from numeric NOT NULL
);

CREATE TABLE IF NOT EXISTS public.seat_knowledge_refresh (
  seat text NOT NULL,
  quarter date NOT NULL,
  items jsonb DEFAULT '[]'::jsonb NOT NULL,
  opened_at timestamp with time zone DEFAULT now() NOT NULL,
  verified_at timestamp with time zone,
  recheck jsonb
);

CREATE TABLE IF NOT EXISTS public.seat_knowledge_stale (
  quarter date NOT NULL,
  item_key text NOT NULL,
  seat text NOT NULL,
  reasons text[] NOT NULL,
  prior_status text,
  held_id bigint,
  flagged_at timestamp with time zone DEFAULT now() NOT NULL,
  resolved_at timestamp with time zone,
  filed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.seat_learning_daily (
  seat text NOT NULL,
  day date NOT NULL,
  judgements_30d integer NOT NULL,
  outcomes_30d integer NOT NULL,
  correct_30d integer NOT NULL,
  accuracy_30d numeric,
  recall_available_30d integer NOT NULL,
  cases_total integer NOT NULL,
  cases_with_outcome integer NOT NULL,
  lessons_approved integer NOT NULL,
  measured_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.seat_lesson_cluster (
  cluster_key text NOT NULL,
  seat text NOT NULL,
  case_ids bigint[] NOT NULL,
  filed_at timestamp with time zone DEFAULT now() NOT NULL,
  candidate_id bigint,
  verdict text
);

CREATE TABLE IF NOT EXISTS public.seat_playbook (
  seat text NOT NULL,
  version integer DEFAULT 1 NOT NULL,
  playbook jsonb NOT NULL,
  markdown text NOT NULL,
  content_md5 text NOT NULL,
  rebuilt_reason text NOT NULL,
  rebuilt_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.seat_self_review (
  month date NOT NULL,
  seat text NOT NULL,
  items integer NOT NULL,
  passed integer NOT NULL,
  rate numeric,
  checklist_lines integer NOT NULL,
  checklist_passed integer NOT NULL,
  checklist_rate numeric,
  prev_rate numeric,
  prev_checklist_rate numeric,
  trend text NOT NULL,
  passed_items text[] DEFAULT '{}'::text[] NOT NULL,
  passed_lines text[] DEFAULT '{}'::text[] NOT NULL,
  failing jsonb DEFAULT '[]'::jsonb NOT NULL,
  slipped text[] DEFAULT '{}'::text[] NOT NULL,
  improvement_id bigint,
  closed_improvements bigint[] DEFAULT '{}'::bigint[] NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.seat_senior_contribution (
  seat text NOT NULL,
  contribution_id text NOT NULL,
  what text NOT NULL,
  duties text[] DEFAULT '{}'::text[] NOT NULL
);

CREATE TABLE IF NOT EXISTS public.seat_senior_exam (
  seat text NOT NULL,
  judged_on date NOT NULL,
  items integer NOT NULL,
  passed integer NOT NULL,
  source text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.seat_senior_verdict (
  week date NOT NULL,
  seat text NOT NULL,
  stage1 jsonb NOT NULL,
  stage2 jsonb NOT NULL,
  level text NOT NULL,
  shortfalls text[] DEFAULT '{}'::text[] NOT NULL,
  improvement_id bigint,
  measured_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.security_advisor_baseline (
  cache_key text NOT NULL,
  name text NOT NULL,
  level text NOT NULL,
  title text,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  first_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  in_baseline boolean DEFAULT true NOT NULL,
  cleared_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.security_audit_log (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  at timestamp with time zone DEFAULT now() NOT NULL,
  db_user text DEFAULT CURRENT_USER NOT NULL,
  action text NOT NULL,
  table_name text NOT NULL,
  row_pk text,
  old_data jsonb,
  new_data jsonb
);

CREATE TABLE IF NOT EXISTS public.security_events (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  kind text NOT NULL,
  severity text DEFAULT 'low'::text NOT NULL,
  source text,
  subject text,
  detail jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  fingerprint text
);

CREATE TABLE IF NOT EXISTS public.security_gap (
  name text NOT NULL,
  description text NOT NULL,
  what_would_close_it text NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  measured_at timestamp with time zone DEFAULT now() NOT NULL,
  detail jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS public.security_kpi_snapshots (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
  kpis jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.self_review (
  id bigint DEFAULT nextval('self_review_id_seq'::regclass) NOT NULL,
  review_type text NOT NULL,
  subject text NOT NULL,
  finding text NOT NULL,
  evidence text,
  proposal text,
  status text DEFAULT 'proposed'::text NOT NULL,
  impact text,
  reviewed_by text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.seo_categories (
  slug text NOT NULL,
  name text NOT NULL,
  search_term text,
  intro text,
  includes jsonb,
  faqs jsonb,
  sort integer DEFAULT 100,
  generated boolean DEFAULT false,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.service_implication (
  from_code text NOT NULL,
  implies_trade text NOT NULL,
  implies_code text NOT NULL,
  reason_en text NOT NULL,
  reason_ar text NOT NULL,
  active boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.signup_purge (
  id bigint DEFAULT nextval('signup_purge_id_seq'::regclass) NOT NULL,
  kind text NOT NULL,
  subject_ref text NOT NULL,
  started_at timestamp with time zone,
  purged_at timestamp with time zone DEFAULT now() NOT NULL,
  missing text[] NOT NULL,
  counts jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS public.signup_purge_dropbox (
  id bigint DEFAULT nextval('signup_purge_dropbox_id_seq'::regclass) NOT NULL,
  purge_id bigint NOT NULL,
  doc_backup_id bigint,
  dropbox_file text NOT NULL,
  listed_at timestamp with time zone DEFAULT now() NOT NULL,
  attempts integer DEFAULT 0 NOT NULL,
  done_at timestamp with time zone,
  error text
);

CREATE TABLE IF NOT EXISTS public.signup_purge_object (
  id bigint DEFAULT nextval('signup_purge_object_id_seq'::regclass) NOT NULL,
  purge_id bigint NOT NULL,
  bucket text NOT NULL,
  path text NOT NULL,
  done_at timestamp with time zone,
  error text
);

CREATE TABLE IF NOT EXISTS public.simulations (
  id bigint DEFAULT nextval('simulations_id_seq'::regclass) NOT NULL,
  scenario jsonb,
  result jsonb,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.skills_matrix (
  agent_key text NOT NULL,
  skill text NOT NULL,
  rating integer NOT NULL,
  evidence text,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.sms_messages (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  sms_from text NOT NULL,
  sms_to text NOT NULL,
  body text DEFAULT ''::text NOT NULL,
  message_sid text,
  verified boolean DEFAULT false NOT NULL,
  meta jsonb DEFAULT '{}'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.social_connect_link (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  platform text NOT NULL,
  token_hash text NOT NULL,
  expires_at timestamp with time zone NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  started_at timestamp with time zone,
  state_hash text,
  code_verifier text,
  completed_at timestamp with time zone,
  result text
);

CREATE TABLE IF NOT EXISTS public.social_conversation (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  platform text NOT NULL,
  user_id text NOT NULL,
  account_id text,
  handle text,
  owner_seat text DEFAULT 'marketing'::text NOT NULL,
  status text DEFAULT 'auto'::text NOT NULL,
  handed_at timestamp with time zone,
  handed_reason text,
  handoff_count integer DEFAULT 0 NOT NULL,
  resumed_at timestamp with time zone,
  resumed_by text,
  last_inbound_at timestamp with time zone,
  is_demo boolean GENERATED ALWAYS AS (((user_id ~* '^ZZDEMO([^a-z]|$)'::text) OR (COALESCE(handle, ''::text) ~* '^ZZ DEMO([^a-z]|$)'::text))) STORED,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.social_message (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  conversation_id bigint NOT NULL,
  platform text NOT NULL,
  channel text NOT NULL,
  direction text NOT NULL,
  author text NOT NULL,
  meta_message_id text,
  parent_id text,
  in_reply_to bigint,
  body text NOT NULL,
  reply_kind text,
  reply_key text,
  send_status text,
  send_error text,
  sent_at timestamp with time zone,
  outcome text,
  occurred_at timestamp with time zone DEFAULT now() NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  classification text,
  decided_by text,
  guard_failures text[] DEFAULT '{}'::text[] NOT NULL,
  handoff_id bigint,
  reply_attempts jsonb
);

CREATE TABLE IF NOT EXISTS public.social_posts (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  source text DEFAULT 'manual'::text,
  content jsonb,
  image_url text,
  channels text[] DEFAULT '{}'::text[],
  schedule_at timestamp with time zone,
  mode text DEFAULT 'draft'::text,
  status text DEFAULT 'pending'::text,
  postiz_ids jsonb,
  error text,
  permalinks jsonb,
  permalink_missing text,
  media_missing text,
  preview_url text
);

CREATE TABLE IF NOT EXISTS public.social_reply_library (
  key text NOT NULL,
  priority integer,
  match_words text[] DEFAULT '{}'::text[] NOT NULL,
  reply_en text NOT NULL,
  reply_ar text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_by text
);

CREATE TABLE IF NOT EXISTS public.spec_alternative_offer (
  id bigint DEFAULT nextval('spec_alternative_offer_id_seq'::regclass) NOT NULL,
  inquiry_id uuid NOT NULL,
  customer_id uuid,
  line_no integer NOT NULL,
  item text,
  attr text NOT NULL,
  label_en text NOT NULL,
  label_ar text NOT NULL,
  requested text NOT NULL,
  alternatives jsonb NOT NULL,
  state text DEFAULT 'open'::text NOT NULL,
  reminders_sent integer DEFAULT 0 NOT NULL,
  last_sent_at timestamp with time zone,
  reply_by timestamp with time zone NOT NULL,
  accepted_option text,
  accepted_value text,
  answered_at timestamp with time zone,
  answer_channel text,
  closed_reason text,
  notification_ids jsonb DEFAULT '[]'::jsonb NOT NULL,
  owner_seat text DEFAULT 'sales_engineer'::text NOT NULL,
  messenger_seat text DEFAULT 'customer_support'::text NOT NULL,
  opened_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.spec_backlog (
  id bigint DEFAULT nextval('spec_backlog_id_seq'::regclass) NOT NULL,
  source_doc text NOT NULL,
  area text NOT NULL,
  item text NOT NULL,
  spec_ref text,
  status text DEFAULT 'pending'::text NOT NULL,
  verdict_at_audit text,
  evidence text,
  priority integer DEFAULT 3 NOT NULL,
  notes text,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.stalled_inquiry_rescue (
  inquiry_id uuid NOT NULL,
  reason text NOT NULL,
  detail jsonb DEFAULT '{}'::jsonb NOT NULL,
  fixture boolean DEFAULT false NOT NULL,
  flagged_at timestamp with time zone DEFAULT now() NOT NULL,
  flagged_by text NOT NULL,
  cleared_at timestamp with time zone,
  cleared_why text,
  trades text[],
  emirate text,
  matched_at timestamp with time zone,
  stalled_hours numeric,
  uninvited_pool integer,
  plan_rank integer,
  finding_key text,
  customer_notice jsonb,
  enqueue_result jsonb,
  acted_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.strategy_risks (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  category text NOT NULL,
  title text NOT NULL,
  likelihood integer DEFAULT 3 NOT NULL,
  impact integer DEFAULT 3 NOT NULL,
  score integer GENERATED ALWAYS AS ((likelihood * impact)) STORED,
  mitigation text,
  source text DEFAULT 'internal_scan'::text,
  status text DEFAULT 'open'::text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.stripe_dispute (
  id text NOT NULL,
  livemode boolean NOT NULL,
  charge_id text,
  payment_intent text,
  transaction_id uuid,
  amount_fils bigint NOT NULL,
  currency text NOT NULL,
  reason text,
  status text NOT NULL,
  evidence_due_by timestamp with time zone,
  evidence_submitted_at timestamp with time zone,
  submission jsonb,
  submit_error text,
  alerted_72h_at timestamp with time zone,
  alerted_24h_at timestamp with time zone,
  outcome text,
  closed_at timestamp with time zone,
  first_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  draft_saved_at timestamp with time zone,
  review_report_id bigint,
  approved_by text,
  approved_at timestamp with time zone,
  submit_trigger text
);

CREATE TABLE IF NOT EXISTS public.stripe_events (
  event_id text NOT NULL,
  type text,
  payment_status text,
  first_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  delivery_count integer DEFAULT 1 NOT NULL,
  note text
);

CREATE TABLE IF NOT EXISTS public.stripe_payout (
  id text NOT NULL,
  livemode boolean NOT NULL,
  amount_fils bigint NOT NULL,
  currency text NOT NULL,
  status text NOT NULL,
  arrival_date date NOT NULL,
  created_at_stripe timestamp with time zone,
  method text,
  destination text,
  automatic boolean,
  failure_code text,
  failure_message text,
  txn_count integer,
  txn_net_fils bigint,
  first_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  bank_line_id bigint,
  matched_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.stripe_setting_reading (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  setting text NOT NULL,
  value text NOT NULL,
  read_at timestamp with time zone NOT NULL,
  read_by text NOT NULL,
  evidence text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.subcategory_agent_map (
  sub_slug text NOT NULL,
  agent_slug text NOT NULL,
  confidence text DEFAULT 'medium'::text NOT NULL,
  note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_availability (
  supplier_id bigint NOT NULL,
  state text DEFAULT 'available'::text NOT NULL,
  busy_until date,
  set_at timestamp with time zone DEFAULT now() NOT NULL,
  set_by text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_beneficial_owner (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  lead_id bigint NOT NULL,
  full_name text NOT NULL,
  nationality text,
  share_pct numeric,
  source text NOT NULL,
  declared_at timestamp with time zone DEFAULT now() NOT NULL,
  verified_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.supplier_campaign_daily_list (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  list_day date NOT NULL,
  send_day date NOT NULL,
  switch_on boolean NOT NULL,
  held_because text,
  planned integer NOT NULL,
  rows jsonb NOT NULL,
  counts jsonb NOT NULL,
  subject text NOT NULL,
  body text NOT NULL,
  pdf_blocks jsonb NOT NULL,
  pdf_path text,
  pdf_error text,
  attempts integer DEFAULT 0 NOT NULL,
  notification_id bigint,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_capabilities (
  supplier_id bigint NOT NULL,
  services text[] DEFAULT '{}'::text[],
  brands text[] DEFAULT '{}'::text[],
  authorized_distributor jsonb DEFAULT '[]'::jsonb,
  certifications text[] DEFAULT '{}'::text[],
  team_size integer,
  engineers integer,
  technicians integer,
  equipment text[] DEFAULT '{}'::text[],
  coverage_emirates text[] DEFAULT '{}'::text[],
  insurance jsonb DEFAULT '{}'::jsonb,
  warranty_policy text,
  emergency_support boolean,
  response_time_hours numeric,
  languages text[] DEFAULT '{}'::text[],
  fleet integer,
  warehouse text,
  min_project_value numeric,
  max_project_value numeric,
  annual_capacity text,
  years_in_business integer,
  updated_at timestamp with time zone DEFAULT now(),
  trades text[] DEFAULT '{}'::text[] NOT NULL,
  roles text[] DEFAULT '{}'::text[] NOT NULL,
  products_norm text[] DEFAULT '{}'::text[] NOT NULL,
  project_types text[] DEFAULT '{}'::text[] NOT NULL,
  exclusions text[] DEFAULT '{}'::text[] NOT NULL,
  authority_approvals jsonb DEFAULT '{}'::jsonb NOT NULL,
  source_docs jsonb DEFAULT '{}'::jsonb NOT NULL,
  confidence jsonb DEFAULT '{}'::jsonb NOT NULL,
  completeness numeric,
  extracted_at timestamp with time zone,
  extractor_version text,
  review_status text DEFAULT 'pending'::text NOT NULL,
  missing_fields text[] DEFAULT '{}'::text[] NOT NULL,
  confirmed_at timestamp with time zone,
  confirmed_version integer,
  excluded_trades text[] DEFAULT '{}'::text[] NOT NULL,
  proposed_trades text[] DEFAULT '{}'::text[] NOT NULL,
  services_raw_text text,
  services_implied text[] DEFAULT '{}'::text[] NOT NULL,
  services_removed text[] DEFAULT '{}'::text[] NOT NULL,
  services_rewritten_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.supplier_capability_confirmation (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  supplier_id bigint NOT NULL,
  version integer DEFAULT 1 NOT NULL,
  proposed jsonb DEFAULT '{}'::jsonb NOT NULL,
  confirmed jsonb DEFAULT '{}'::jsonb NOT NULL,
  supplier_added jsonb DEFAULT '{}'::jsonb NOT NULL,
  exclusions text[] DEFAULT '{}'::text[] NOT NULL,
  source_docs jsonb DEFAULT '{}'::jsonb NOT NULL,
  confirmed_at timestamp with time zone,
  confirmed_via text,
  agent_version text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_capability_reading (
  lead_id bigint NOT NULL,
  summary_md5 text NOT NULL,
  manufacturing boolean,
  installation boolean,
  maintenance boolean,
  design boolean,
  status text NOT NULL,
  held_id bigint,
  reasoned_at timestamp with time zone,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_catalog (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  supplier_id bigint NOT NULL,
  source_document_path text,
  source_hash text,
  version integer DEFAULT 1 NOT NULL,
  status text DEFAULT 'processing'::text NOT NULL,
  extracted_at timestamp with time zone,
  approved_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_collaboration (
  lead_id bigint NOT NULL,
  consecutive_ignored integer DEFAULT 0 NOT NULL,
  total_ignored integer DEFAULT 0 NOT NULL,
  last_incident_at timestamp with time zone,
  warned_at timestamp with time zone,
  held_at timestamp with time zone,
  lifted_at timestamp with time zone,
  owner_seat text DEFAULT 'sales_engineer'::text NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_collaboration_event (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  lead_id bigint NOT NULL,
  kind text NOT NULL,
  inquiry_id uuid,
  quote_id uuid,
  hold_id bigint,
  consecutive_after integer NOT NULL,
  founder_instruction_id bigint,
  detail jsonb DEFAULT '{}'::jsonb NOT NULL,
  actor text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_document_cache (
  kind text NOT NULL,
  subject_id uuid NOT NULL,
  supplier_id bigint NOT NULL,
  lang text NOT NULL,
  content_hash text NOT NULL,
  bucket text NOT NULL,
  path text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_due_checkouts (
  session_id text NOT NULL,
  due_id bigint NOT NULL,
  amount_aed numeric(12,2) NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_due_payments (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  due_id bigint NOT NULL,
  paid_on date NOT NULL,
  amount_aed numeric(12,2) NOT NULL,
  reference text NOT NULL,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL,
  entered_by text DEFAULT 'service'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_dues (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  transaction_id uuid,
  supplier_id bigint,
  quote_id uuid,
  quote_amount numeric,
  commission_pct numeric DEFAULT 2,
  amount_due numeric,
  currency text DEFAULT 'AED'::text,
  reveal_date date,
  due_date date,
  due_date_30 date,
  status text DEFAULT 'pending'::text,
  reminders integer DEFAULT 0,
  last_reminder_at timestamp with time zone,
  overdue_emailed_at timestamp with time zone,
  fine_pct numeric DEFAULT 0,
  fine_amount numeric DEFAULT 0,
  paid_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  interest_amount numeric,
  admin_fee numeric,
  total_claim numeric,
  legal_stage text,
  legal_escalated_at timestamp with time zone,
  demand_letter_path text,
  case_file_path text,
  evidence_terms_path text,
  payment_ref text,
  stripe_session_id text,
  payment_order_filed_on date,
  payment_order_issued_on date,
  payment_order_served_on date,
  grievance_filed_on date,
  court_reference text,
  status_reason text
);

CREATE TABLE IF NOT EXISTS public.supplier_kpi_snapshots (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
  kpis jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_lead_intake (
  inbound_id bigint NOT NULL,
  lead_id bigint,
  intent text NOT NULL,
  matched_by text,
  task_id bigint,
  suppressed boolean DEFAULT false NOT NULL,
  classified_at timestamp with time zone DEFAULT now() NOT NULL,
  run_tag text
);

CREATE TABLE IF NOT EXISTS public.supplier_onboarding (
  lead_id bigint NOT NULL,
  stage text NOT NULL,
  stage_since timestamp with time zone DEFAULT now() NOT NULL,
  first_match_at timestamp with time zone,
  first_quote_at timestamp with time zone,
  open_matches integer DEFAULT 0 NOT NULL,
  nudges integer DEFAULT 0 NOT NULL,
  last_nudge_at timestamp with time zone,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_opportunity_score (
  supplier_id bigint NOT NULL,
  inquiry_id uuid NOT NULL,
  score numeric NOT NULL,
  eligibility boolean NOT NULL,
  reasons jsonb DEFAULT '[]'::jsonb NOT NULL,
  risks jsonb DEFAULT '[]'::jsonb NOT NULL,
  calculated_at timestamp with time zone DEFAULT now() NOT NULL,
  algorithm_version text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_own_word_reading (
  supplier_id bigint NOT NULL,
  word text NOT NULL,
  service_key text,
  status text NOT NULL,
  held_id bigint,
  reasoned_at timestamp with time zone,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_performance (
  lead_id bigint NOT NULL,
  score numeric,
  components jsonb DEFAULT '{}'::jsonb NOT NULL,
  computed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_product (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  supplier_id bigint NOT NULL,
  catalog_id uuid,
  external_key text,
  name text NOT NULL,
  category_slug text,
  subcategory_slug text,
  brand text,
  model text,
  description text,
  attributes jsonb DEFAULT '{}'::jsonb NOT NULL,
  certifications jsonb DEFAULT '[]'::jsonb NOT NULL,
  documents jsonb DEFAULT '[]'::jsonb NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  evidence_refs jsonb DEFAULT '[]'::jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_product_variant (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  product_id uuid NOT NULL,
  sku text,
  attributes jsonb DEFAULT '{}'::jsonb NOT NULL,
  price_policy jsonb,
  lead_time_policy jsonb,
  active boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_public_name (
  lead_id bigint NOT NULL,
  norm text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_quote_template (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  supplier_id bigint NOT NULL,
  name text NOT NULL,
  line_headings text[] DEFAULT '{}'::text[] NOT NULL,
  terms text DEFAULT ''::text NOT NULL,
  warranty text DEFAULT ''::text NOT NULL,
  validity text DEFAULT ''::text NOT NULL,
  inclusions text DEFAULT ''::text NOT NULL,
  exclusions text DEFAULT ''::text NOT NULL,
  payment_terms text DEFAULT ''::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_recruitment_funnel (
  trade text NOT NULL,
  emirate text NOT NULL,
  day date NOT NULL,
  pool integer DEFAULT 0 NOT NULL,
  invited integer DEFAULT 0 NOT NULL,
  clicked integer DEFAULT 0 NOT NULL,
  registered integer DEFAULT 0 NOT NULL,
  approved integer DEFAULT 0 NOT NULL,
  quoting integer DEFAULT 0 NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_reply_followup (
  id bigint DEFAULT nextval('supplier_reply_followup_id_seq'::regclass) NOT NULL,
  inbound_message_id bigint NOT NULL,
  lead_id bigint,
  to_email text NOT NULL,
  intent text NOT NULL,
  due_at timestamp with time zone NOT NULL,
  state text DEFAULT 'due'::text NOT NULL,
  outcome text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  done_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.supplier_response_watch (
  id bigint DEFAULT nextval('supplier_response_watch_id_seq'::regclass) NOT NULL,
  transaction_id uuid NOT NULL,
  lead_id bigint NOT NULL,
  opened_at timestamp with time zone DEFAULT now() NOT NULL,
  attempts jsonb DEFAULT '[]'::jsonb NOT NULL,
  first_response_at timestamp with time zone,
  response_channel text,
  response_ref text,
  closed_at timestamp with time zone,
  close_reason text
);

CREATE TABLE IF NOT EXISTS public.supplier_score (
  lead_id bigint NOT NULL,
  response_rate numeric,
  avg_response_hours numeric,
  quotes_submitted integer DEFAULT 0 NOT NULL,
  quotes_won integer DEFAULT 0 NOT NULL,
  rejection_count integer DEFAULT 0 NOT NULL,
  price_index numeric,
  quality_rating numeric,
  reliability numeric,
  last_active timestamp with time zone,
  computed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_scorecard (
  lead_id bigint NOT NULL,
  month date NOT NULL,
  card jsonb NOT NULL,
  to_email text,
  outcome text NOT NULL,
  handoff_id bigint,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_screening_hit (
  id bigint DEFAULT nextval('supplier_screening_hit_id_seq'::regclass) NOT NULL,
  run_id bigint,
  lead_id bigint NOT NULL,
  field text NOT NULL,
  supplier_value text,
  entry_id bigint,
  entry_name text,
  entry_source text NOT NULL,
  entry_reference text DEFAULT ''::text NOT NULL,
  entry_type text,
  match_kind text NOT NULL,
  score numeric,
  status text DEFAULT 'open'::text NOT NULL,
  task_id bigint,
  bd_task_id bigint,
  decided_by text,
  decided_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_voice_note (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  supplier_id bigint NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  bytes integer DEFAULT 0 NOT NULL,
  duration_ms integer,
  mime text,
  outcome text NOT NULL,
  lang text,
  chars integer
);

CREATE TABLE IF NOT EXISTS public.supplier_whatsapp_consent_ask (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  phone text NOT NULL,
  question text NOT NULL,
  asked_by text NOT NULL,
  asked_at timestamp with time zone DEFAULT now() NOT NULL,
  answered_at timestamp with time zone,
  answer text
);

CREATE TABLE IF NOT EXISTS public.supplier_whatsapp_optin (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  lead_id bigint NOT NULL,
  phone text NOT NULL,
  source text NOT NULL,
  button_payload text,
  consent_question text,
  consent_answer text,
  evidence text NOT NULL,
  opted_in_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supply_gap (
  trade text NOT NULL,
  emirate text NOT NULL,
  matchable integer DEFAULT 0 NOT NULL,
  target integer NOT NULL,
  demand_90d integer DEFAULT 0 NOT NULL,
  short_open integer DEFAULT 0 NOT NULL,
  uninvited_pool integer DEFAULT 0 NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  decided_by text,
  decided_at timestamp with time zone,
  held_id bigint,
  review jsonb,
  measured_at timestamp with time zone DEFAULT now() NOT NULL,
  opened_at timestamp with time zone DEFAULT now() NOT NULL,
  closed_at timestamp with time zone,
  brief_id bigint
);

CREATE TABLE IF NOT EXISTS public.supply_health_snapshots (
  id bigint DEFAULT nextval('supply_health_snapshots_id_seq'::regclass) NOT NULL,
  period_end date,
  metrics jsonb,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.supply_recruitment_brief (
  id bigint DEFAULT nextval('supply_recruitment_brief_id_seq'::regclass) NOT NULL,
  trade text NOT NULL,
  emirate text NOT NULL,
  matchable integer NOT NULL,
  target integer NOT NULL,
  shortfall integer NOT NULL,
  invited integer DEFAULT 0 NOT NULL,
  registered integer DEFAULT 0 NOT NULL,
  demand_90d integer DEFAULT 0 NOT NULL,
  short_open integer DEFAULT 0 NOT NULL,
  uninvited_pool integer DEFAULT 0 NOT NULL,
  priority text NOT NULL,
  suggested_sourcing text NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  owner_seat text DEFAULT 'marketing'::text NOT NULL,
  listed_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  read_by_marketing_at timestamp with time zone,
  closed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.support_artifact (
  artifact_id bigint DEFAULT nextval('support_artifact_artifact_id_seq'::regclass) NOT NULL,
  artifact_kind text NOT NULL,
  subject_ref text NOT NULL,
  owner_party_id text,
  version text,
  checksum text,
  storage_path text,
  byte_size bigint,
  privacy_state text DEFAULT 'unchecked'::text NOT NULL,
  privacy_result jsonb,
  approved_at timestamp with time zone,
  obsolete_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.support_case (
  case_id bigint DEFAULT nextval('support_case_case_id_seq'::regclass) NOT NULL,
  case_ref text NOT NULL,
  party_kind text NOT NULL,
  party_id text,
  inquiry_ref text,
  subject text NOT NULL,
  state text DEFAULT 'open'::text NOT NULL,
  identity_verified boolean DEFAULT false NOT NULL,
  verified_how text,
  opened_at timestamp with time zone DEFAULT now() NOT NULL,
  last_activity_at timestamp with time zone DEFAULT now() NOT NULL,
  closed_at timestamp with time zone,
  close_reason text,
  owner_role_id text DEFAULT 'customer_support'::text NOT NULL,
  case_kind text DEFAULT 'support'::text NOT NULL,
  customer_profile_id bigint,
  channel text,
  channels text[] DEFAULT '{}'::text[] NOT NULL,
  last_channel text,
  lang text,
  first_customer_msg_at timestamp with time zone,
  last_inbound_at timestamp with time zone,
  first_reply_at timestamp with time zone,
  inbound_count integer DEFAULT 0 NOT NULL,
  outbound_count integer DEFAULT 0 NOT NULL,
  contact_count integer DEFAULT 0 NOT NULL,
  resolution text,
  resolved_at timestamp with time zone,
  reopen_count integer DEFAULT 0 NOT NULL,
  reopened_at timestamp with time zone,
  csat_requested_at timestamp with time zone,
  csat_request_error text,
  recovery_of_case_id bigint,
  first_reply_seconds numeric GENERATED ALWAYS AS (EXTRACT(epoch FROM (first_reply_at - COALESCE(first_customer_msg_at, opened_at)))) STORED,
  fcr boolean GENERATED ALWAYS AS (
CASE
    WHEN (state = 'closed'::text) THEN ((reopen_count = 0) AND (contact_count <= 1))
    ELSE NULL::boolean
END) STORED,
  category text,
  topic_tags text[] DEFAULT '{}'::text[] NOT NULL
);

CREATE TABLE IF NOT EXISTS public.support_category (
  category text NOT NULL,
  owner_seat text NOT NULL,
  support_fixes boolean NOT NULL,
  meaning text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.support_cause_week (
  week_ending date NOT NULL,
  cause_key text NOT NULL,
  category text NOT NULL,
  topic_tag text NOT NULL,
  owner_seat text NOT NULL,
  cases integer NOT NULL,
  reopened integer DEFAULT 0 NOT NULL,
  fixture boolean DEFAULT false NOT NULL
);

CREATE TABLE IF NOT EXISTS public.support_ceo_report (
  id bigint DEFAULT nextval('support_ceo_report_id_seq'::regclass) NOT NULL,
  idempotency_key text NOT NULL,
  source_agent text NOT NULL,
  case_ref text,
  task_ref text,
  severity text NOT NULL,
  subject text NOT NULL,
  verified_evidence jsonb NOT NULL,
  attempted_actions jsonb NOT NULL,
  requested_outcome text NOT NULL,
  owner_role_id text NOT NULL,
  next_review_at timestamp with time zone NOT NULL,
  status text DEFAULT 'sent'::text NOT NULL,
  accepted_at timestamp with time zone,
  acceptance_receipt text,
  completed_at timestamp with time zone,
  completion_note text,
  delivery_attempts integer DEFAULT 0 NOT NULL,
  last_delivery_error text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.support_customer_profile (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  party_kind text DEFAULT 'unknown'::text NOT NULL,
  customer_id uuid,
  lead_id bigint,
  email text,
  phone_tail text,
  display_name text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  last_seen_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.support_document_intake (
  intake_id bigint DEFAULT nextval('support_document_intake_intake_id_seq'::regclass) NOT NULL,
  received_at timestamp with time zone DEFAULT now() NOT NULL,
  channel text NOT NULL,
  sender_ref text NOT NULL,
  lead_id bigint,
  case_id bigint,
  storage_path text NOT NULL,
  media_kind text,
  caption text,
  classified_as text NOT NULL,
  classified_by text NOT NULL,
  confidence text NOT NULL,
  attached boolean DEFAULT false NOT NULL,
  attach_note text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.support_identity_challenge (
  challenge_id bigint DEFAULT nextval('support_identity_challenge_challenge_id_seq'::regclass) NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  channel text NOT NULL,
  sender_ref text NOT NULL,
  claimed_email text,
  lead_id bigint,
  sent_to text,
  code_hash text NOT NULL,
  expires_at timestamp with time zone NOT NULL,
  attempts integer DEFAULT 0 NOT NULL,
  consumed_at timestamp with time zone,
  outcome text
);

CREATE TABLE IF NOT EXISTS public.support_knowledge (
  record_id text NOT NULL,
  schema_version text,
  record_version text NOT NULL,
  record_kind text NOT NULL,
  parent_id text,
  title text NOT NULL,
  domain text,
  tags text[] DEFAULT '{}'::text[] NOT NULL,
  language text DEFAULT 'en'::text NOT NULL,
  review_status text NOT NULL,
  content_origin text,
  authority_effect text DEFAULT 'none'::text NOT NULL,
  runtime_use text,
  runtime_index_eligible boolean DEFAULT true NOT NULL,
  contains_synthetic_example boolean DEFAULT false NOT NULL,
  requires_current_verification boolean DEFAULT false NOT NULL,
  source_ids text[] DEFAULT '{}'::text[] NOT NULL,
  source_path text,
  structured_data jsonb DEFAULT '{}'::jsonb NOT NULL,
  body text NOT NULL,
  body_sha256 text,
  pack_id text NOT NULL,
  pack_version text NOT NULL,
  imported_at timestamp with time zone DEFAULT now() NOT NULL,
  search tsvector,
  embedding_gte vector(384)
);

CREATE TABLE IF NOT EXISTS public.support_notification (
  id bigint DEFAULT nextval('support_notification_id_seq'::regclass) NOT NULL,
  dedupe_key text NOT NULL,
  case_id bigint,
  purpose text NOT NULL,
  channel text NOT NULL,
  recipient text NOT NULL,
  inquiry_ref text,
  publication_version text,
  subject text,
  body text NOT NULL,
  attachment_ref text,
  state text DEFAULT 'queued'::text NOT NULL,
  provider_id text,
  provider_status text,
  failure_reason text,
  attempts integer DEFAULT 0 NOT NULL,
  anonymity_checked_at timestamp with time zone,
  anonymity_result jsonb,
  queued_at timestamp with time zone DEFAULT now() NOT NULL,
  sent_at timestamp with time zone,
  outbox_id bigint,
  bridged_at timestamp with time zone,
  bridge_note text
);

CREATE TABLE IF NOT EXISTS public.support_public_override (
  src text NOT NULL,
  src_id text NOT NULL,
  is_public boolean NOT NULL,
  decided_by text NOT NULL,
  rationale text NOT NULL,
  decided_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.support_reply_readability (
  id bigint DEFAULT nextval('support_reply_readability_id_seq'::regclass) NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  channel text NOT NULL,
  lang text NOT NULL,
  path text NOT NULL,
  rewritten boolean DEFAULT false NOT NULL,
  score smallint NOT NULL,
  tone smallint NOT NULL,
  issues text[] DEFAULT '{}'::text[] NOT NULL,
  reason text,
  demo boolean DEFAULT false NOT NULL,
  e2e_run_tag text
);

CREATE TABLE IF NOT EXISTS public.support_root_cause (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  cause_key text NOT NULL,
  category text NOT NULL,
  topic_tag text NOT NULL,
  owner_seat text NOT NULL,
  support_fixes boolean NOT NULL,
  opened_week date NOT NULL,
  baseline_per_week numeric NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  acted_at timestamp with time zone,
  handoff_id bigint,
  measurements jsonb DEFAULT '[]'::jsonb NOT NULL,
  fixture boolean DEFAULT false NOT NULL,
  opened_at timestamp with time zone DEFAULT now() NOT NULL,
  closed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.support_root_cause_fix (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  root_cause_id bigint NOT NULL,
  fix_kind text NOT NULL,
  target_table text NOT NULL,
  target_id text NOT NULL,
  note text,
  fixed_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.support_signal_category (
  source text NOT NULL,
  value text NOT NULL,
  category text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.table_export_change (
  id bigint DEFAULT nextval('table_export_change_id_seq'::regclass) NOT NULL,
  table_name text NOT NULL,
  row_key text NOT NULL,
  deleted boolean DEFAULT false NOT NULL,
  changed_at timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.table_export_change_tracked (
  table_name text NOT NULL,
  pk_column text NOT NULL,
  projection text DEFAULT ''::text NOT NULL,
  tracking_since timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
  bytes_at_registration bigint
);

CREATE TABLE IF NOT EXISTS public.table_export_registry (
  table_name text NOT NULL,
  exported boolean NOT NULL,
  category text NOT NULL,
  reason text NOT NULL,
  added_by text NOT NULL,
  added_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.table_export_run (
  stamp date NOT NULL,
  kind text DEFAULT 'full'::text NOT NULL,
  since timestamp with time zone,
  status text DEFAULT 'running'::text NOT NULL,
  attempts integer DEFAULT 1 NOT NULL,
  started_at timestamp with time zone DEFAULT now() NOT NULL,
  heartbeat_at timestamp with time zone DEFAULT now() NOT NULL,
  finished_at timestamp with time zone,
  state jsonb,
  manifest jsonb,
  error text,
  pruned_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.target_contract (
  id bigint DEFAULT nextval('target_contract_id_seq'::regclass) NOT NULL,
  contract_key text NOT NULL,
  version integer NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  superseded_by bigint,
  objective text NOT NULL,
  business_reason text NOT NULL,
  priority integer DEFAULT 100 NOT NULL,
  accountable_owner text NOT NULL,
  goal_key text,
  metric_key text,
  metric_definition text NOT NULL,
  metric_unit text NOT NULL,
  metric_population text NOT NULL,
  metric_exclusions text,
  authoritative_source text NOT NULL,
  measure_sql text,
  baseline_value numeric,
  baseline_state text DEFAULT 'unknown'::text NOT NULL,
  baseline_at timestamp with time zone,
  baseline_note text,
  desired_value numeric NOT NULL,
  desired_basis text DEFAULT 'cumulative'::text NOT NULL,
  deadline date NOT NULL,
  timezone text DEFAULT 'Asia/Dubai'::text NOT NULL,
  measurement_cadence text DEFAULT 'daily'::text NOT NULL,
  budget_amount numeric,
  budget_currency text DEFAULT 'AED'::text NOT NULL,
  capacity_note text,
  constraints_note text,
  guardrails jsonb DEFAULT '[]'::jsonb NOT NULL,
  assumptions jsonb DEFAULT '[]'::jsonb NOT NULL,
  confidence_note text,
  escalation_threshold text,
  success_definition text NOT NULL,
  evidence_required text NOT NULL,
  created_by text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  activated_at timestamp with time zone,
  closed_at timestamp with time zone,
  close_reason text
);

CREATE TABLE IF NOT EXISTS public.target_daily_verdict (
  day date NOT NULL,
  contract_id bigint NOT NULL,
  metric_key text NOT NULL,
  owner_seat text NOT NULL,
  expected numeric,
  actual numeric,
  gap_pct numeric,
  status text NOT NULL,
  task_id bigint,
  handoff_id bigint,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.target_driver (
  id bigint DEFAULT nextval('target_driver_id_seq'::regclass) NOT NULL,
  contract_id bigint NOT NULL,
  stage_order integer NOT NULL,
  stage_key text NOT NULL,
  stage_label text NOT NULL,
  from_stage_key text,
  rate numeric NOT NULL,
  rate_source text NOT NULL,
  rate_evidence text,
  rate_denominator numeric,
  rate_numerator numeric,
  lag_days integer DEFAULT 0 NOT NULL,
  capacity_per_day numeric,
  unit_cost numeric,
  measured_at timestamp with time zone,
  note text,
  channel_key text,
  owner_seat text
);

CREATE TABLE IF NOT EXISTS public.target_label (
  target_key text NOT NULL,
  words text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.target_path (
  contract_id bigint NOT NULL,
  month date NOT NULL,
  metric_key text NOT NULL,
  owner_seat text NOT NULL,
  kind text NOT NULL,
  value numeric NOT NULL,
  tolerance_pct numeric NOT NULL,
  source text NOT NULL,
  direction text DEFAULT 'min'::text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.target_verdict (
  id bigint DEFAULT nextval('target_verdict_id_seq'::regclass) NOT NULL,
  contract_id bigint NOT NULL,
  run_at timestamp with time zone DEFAULT now() NOT NULL,
  remaining_outcome numeric,
  days_remaining integer,
  current_run_rate numeric,
  required_run_rate numeric,
  expected_completion date,
  scenario_downside numeric,
  scenario_base numeric,
  scenario_upside numeric,
  binding_stage text,
  binding_reason text,
  required_top_of_funnel numeric,
  projected_cost numeric,
  budget_headroom numeric,
  verdict text NOT NULL,
  verdict_reason text NOT NULL,
  what_must_change text[],
  measured_rate_count integer,
  assumed_rate_count integer
);

CREATE TABLE IF NOT EXISTS public.taxonomy_role (
  code text NOT NULL,
  label text NOT NULL,
  aliases text[] DEFAULT '{}'::text[] NOT NULL,
  supplies boolean DEFAULT false NOT NULL,
  executes boolean DEFAULT false NOT NULL,
  whole_scope boolean DEFAULT false NOT NULL,
  sort integer DEFAULT 100 NOT NULL,
  active boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.taxonomy_trade (
  code text NOT NULL,
  label text NOT NULL,
  aliases text[] DEFAULT '{}'::text[] NOT NULL,
  authority_required text[] DEFAULT '{}'::text[] NOT NULL,
  sort integer DEFAULT 100 NOT NULL,
  active boolean DEFAULT true NOT NULL,
  label_ar text,
  group_code text,
  umbrella_code text
);

CREATE TABLE IF NOT EXISTS public.taxonomy_trade_code (
  trade_code text NOT NULL,
  scheme text NOT NULL,
  code text NOT NULL,
  source_urls text[] DEFAULT '{}'::text[] NOT NULL
);

CREATE TABLE IF NOT EXISTS public.taxonomy_trade_group (
  code text NOT NULL,
  label_en text NOT NULL,
  label_ar text NOT NULL,
  sort integer DEFAULT 100 NOT NULL
);

CREATE TABLE IF NOT EXISTS public.taxonomy_trade_proposal (
  id bigint DEFAULT nextval('taxonomy_trade_proposal_id_seq'::regclass) NOT NULL,
  supplier_id bigint NOT NULL,
  code text NOT NULL,
  label_en text,
  label_ar text,
  status text DEFAULT 'pending'::text NOT NULL,
  mapped_to text,
  owner_seat text DEFAULT 'sales_engineer'::text NOT NULL,
  note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  decided_at timestamp with time zone,
  decided_by text
);

CREATE TABLE IF NOT EXISTS public.taxonomy_trade_service (
  trade_code text NOT NULL,
  code text NOT NULL,
  label_en text NOT NULL,
  label_ar text NOT NULL,
  sort integer DEFAULT 100 NOT NULL,
  active boolean DEFAULT true NOT NULL,
  aliases text[] DEFAULT '{}'::text[] NOT NULL,
  embedding_gte vector(384),
  embedding_ml vector(384),
  embedding_gte_sha text,
  embedding_ml_sha text
);

CREATE TABLE IF NOT EXISTS public.templates (
  name text NOT NULL,
  content text,
  description text,
  updated_at timestamp with time zone DEFAULT now(),
  updated_by text
);

CREATE TABLE IF NOT EXISTS public.trade_spec_checklist (
  trade_code text NOT NULL,
  topic_id text NOT NULL,
  topic text NOT NULL,
  specs jsonb NOT NULL,
  source_pack text NOT NULL,
  loaded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.transactions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  quote_id uuid,
  inquiry_id uuid,
  supplier_id bigint,
  customer_id uuid,
  quote_amount numeric,
  app_fee numeric,
  customer_price numeric,
  fee_status text DEFAULT 'pending'::text,
  revealed_at timestamp with time zone DEFAULT now(),
  reveal_fee numeric,
  paid_by text DEFAULT 'customer'::text,
  payment_ref text,
  refund_deadline timestamp with time zone,
  refund_status text,
  refund_reason text,
  refund_requested_at timestamp with time zone,
  refund_resolved_at timestamp with time zone,
  refund_note text,
  supplier_ack_at timestamp with time zone,
  nudged_24_at timestamp with time zone,
  nudged_48_at timestamp with time zone,
  ack_token uuid DEFAULT gen_random_uuid(),
  customer_notified_at timestamp with time zone,
  refund_stripe_id text,
  refund_amount_aed numeric,
  refund_confirmed_at timestamp with time zone,
  stripe_invoice_id text,
  stripe_invoice_number text,
  stripe_invoice_status text,
  stripe_invoice_total_fils bigint,
  stripe_invoice_currency text,
  stripe_invoice_pdf_url text,
  stripe_invoice_hosted_url text,
  doc_path text,
  doc_name text,
  doc_content_type text,
  doc_kind text,
  doc_note text,
  processing_fee numeric(12,2),
  total_charged numeric(12,2),
  stripe_fee_fils bigint,
  stripe_fee_details jsonb
);

CREATE TABLE IF NOT EXISTS public.ui_label (
  domain text NOT NULL,
  key text NOT NULL,
  label text NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.undo_log (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  table_name text,
  row_id text,
  op text,
  before jsonb,
  actor text,
  reverted boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.unsubscribe_refusal (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  at timestamp with time zone DEFAULT now() NOT NULL,
  email text NOT NULL,
  method text,
  token_present boolean DEFAULT false NOT NULL,
  user_agent text,
  confirm_sent_at timestamp with time zone,
  recovered_at timestamp with time zone,
  outcome text
);

CREATE TABLE IF NOT EXISTS public.user_roles (
  email text NOT NULL,
  role text NOT NULL,
  added_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.vendor_billing_ended (
  vendor text NOT NULL,
  ended_after date NOT NULL,
  basis text NOT NULL,
  note text,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL,
  kind text DEFAULT 'ended'::text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.vision_horizon (
  year_no integer NOT NULL,
  label text NOT NULL,
  statement text NOT NULL,
  active boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.vt_results (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  sha256 text,
  bucket text,
  path text,
  status text,
  malicious_count integer DEFAULT 0,
  checked_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.wa_answer_log (
  id bigint DEFAULT nextval('wa_answer_log_id_seq'::regclass) NOT NULL,
  received_at timestamp with time zone DEFAULT now() NOT NULL,
  from_phone text NOT NULL,
  body text NOT NULL,
  identity_kind text,
  identity_id text,
  intent_key text,
  matched boolean NOT NULL,
  reply text,
  refusal_reason text,
  answered_by text DEFAULT 'deterministic'::text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.wa_conversation (
  id bigint DEFAULT nextval('wa_conversation_id_seq'::regclass) NOT NULL,
  phone_e164 text NOT NULL,
  party_kind text,
  party_id text,
  language text,
  thread_state text DEFAULT 'open'::text NOT NULL,
  topic text,
  last_intent text,
  window_opened_at timestamp with time zone,
  window_expires_at timestamp with time zone,
  message_count integer DEFAULT 0 NOT NULL,
  first_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  handed_to text
);

CREATE TABLE IF NOT EXISTS public.wa_document_intake (
  id bigint DEFAULT nextval('wa_document_intake_id_seq'::regclass) NOT NULL,
  received_at timestamp with time zone DEFAULT now() NOT NULL,
  phone_e164 text NOT NULL,
  lead_id bigint,
  turn_id bigint,
  media_url text,
  storage_path text,
  media_kind text,
  caption text,
  classified_as text,
  classified_by text,
  confidence text,
  attached boolean DEFAULT false NOT NULL,
  attach_note text
);

CREATE TABLE IF NOT EXISTS public.wa_inbound_seen (
  message_sid text NOT NULL,
  wa_from text,
  first_seen_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.wa_messages (
  id bigint DEFAULT nextval('wa_messages_id_seq'::regclass) NOT NULL,
  wa_from text,
  wa_to text,
  profile_name text,
  inbound text,
  reply text,
  lang text,
  escalated boolean DEFAULT false,
  sent boolean DEFAULT false,
  meta jsonb,
  created_at timestamp with time zone DEFAULT now(),
  replied_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.wa_reply_intent (
  intent_key text NOT NULL,
  label text NOT NULL,
  sort integer DEFAULT 100 NOT NULL,
  match_patterns text[] NOT NULL,
  requires_identity boolean DEFAULT false NOT NULL,
  scope text DEFAULT 'company'::text NOT NULL,
  answer_template text NOT NULL,
  resolver_note text,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  requires_number boolean DEFAULT false NOT NULL
);

CREATE TABLE IF NOT EXISTS public.wa_sender_quality_reading (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  read_at timestamp with time zone DEFAULT now() NOT NULL,
  rating text,
  status text NOT NULL,
  messaging_limit text,
  ok boolean NOT NULL,
  raw jsonb DEFAULT '{}'::jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS public.wa_template_registry (
  template_name text NOT NULL,
  language text NOT NULL,
  category text NOT NULL,
  status text NOT NULL,
  purpose text NOT NULL,
  approved_on date,
  rejection_cause text,
  checked_at timestamp with time zone DEFAULT now() NOT NULL,
  source text DEFAULT 'Twilio Content API'::text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.wa_turn (
  id bigint DEFAULT nextval('wa_turn_id_seq'::regclass) NOT NULL,
  conversation_id bigint NOT NULL,
  at timestamp with time zone DEFAULT now() NOT NULL,
  direction text NOT NULL,
  body text,
  media_url text,
  media_kind text,
  transcript text,
  transcript_source text,
  intent_key text,
  answered_by text,
  fact_pack jsonb,
  model_id text,
  cost_aed numeric
);

CREATE TABLE IF NOT EXISTS public.web_search_day (
  day date NOT NULL,
  used integer DEFAULT 0 NOT NULL,
  cap integer DEFAULT 50 NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.workflow (
  workflow_key text NOT NULL,
  name text NOT NULL,
  trigger_event text,
  description text,
  active boolean DEFAULT true NOT NULL,
  os_key text
);

CREATE TABLE IF NOT EXISTS public.workflow_run (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  workflow_key text NOT NULL,
  trigger_event_id bigint,
  correlation_id uuid NOT NULL,
  entity_type text,
  entity_id text,
  idempotency_key text NOT NULL,
  status text DEFAULT 'queued'::text NOT NULL,
  current_step integer DEFAULT 0 NOT NULL,
  context jsonb DEFAULT '{}'::jsonb NOT NULL,
  attempts integer DEFAULT 0 NOT NULL,
  next_attempt_at timestamp with time zone,
  lease_owner text,
  lease_expires_at timestamp with time zone,
  started_at timestamp with time zone,
  finished_at timestamp with time zone,
  error jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.workflow_step (
  workflow_key text NOT NULL,
  step_no integer NOT NULL,
  step text NOT NULL,
  actor_role text,
  action_class text,
  gate text
);

CREATE TABLE IF NOT EXISTS public.workflow_step_run (
  id bigint DEFAULT nextval('workflow_step_run_id_seq'::regclass) NOT NULL,
  workflow_run_id uuid NOT NULL,
  step_no integer NOT NULL,
  actor text,
  action_class text,
  status text DEFAULT 'queued'::text NOT NULL,
  input jsonb DEFAULT '{}'::jsonb NOT NULL,
  output jsonb,
  idempotency_key text NOT NULL,
  attempts integer DEFAULT 0 NOT NULL,
  started_at timestamp with time zone,
  finished_at timestamp with time zone,
  error jsonb
);

CREATE TABLE IF NOT EXISTS public.writer_seat (
  kind text NOT NULL,
  name text NOT NULL,
  owner_seat text NOT NULL,
  note text NOT NULL,
  owner_file text NOT NULL,
  recorded_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.yello_staging (
  company_id text NOT NULL,
  slug text,
  name text,
  city text,
  src_category text,
  profile_url text,
  website text,
  phone text,
  mobile text,
  whatsapp text,
  categories text[],
  manager text,
  established text,
  address text,
  email text,
  email_source text,
  sector text,
  stage text DEFAULT 'listed'::text NOT NULL,
  note text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

-- ===== CONSTRAINTS =====
ALTER TABLE public.accountant_ad_spend_month ADD CONSTRAINT accountant_ad_spend_month_pkey PRIMARY KEY (month);
ALTER TABLE public.accountant_budget_variance ADD CONSTRAINT accountant_budget_variance_pkey PRIMARY KEY (month, account_code);
ALTER TABLE public.accountant_cash_forecast_week ADD CONSTRAINT accountant_cash_forecast_week_pkey PRIMARY KEY (week);
ALTER TABLE public.accountant_founder_close_pack ADD CONSTRAINT accountant_founder_close_pack_pkey PRIMARY KEY (month);
ALTER TABLE public.accountant_issued_document ADD CONSTRAINT accountant_issued_document_pkey PRIMARY KEY (id);
ALTER TABLE public.accountant_knowledge ADD CONSTRAINT accountant_knowledge_pkey PRIMARY KEY (record_id);
ALTER TABLE public.accountant_mailbox_check ADD CONSTRAINT accountant_mailbox_check_pkey PRIMARY KEY (id);
ALTER TABLE public.accountant_month_close ADD CONSTRAINT accountant_month_close_pkey PRIMARY KEY (month);
ALTER TABLE public.accountant_owner_ruled_subscription ADD CONSTRAINT accountant_owner_ruled_subscription_pkey PRIMARY KEY (vendor);
ALTER TABLE public.accountant_renewal_budget ADD CONSTRAINT accountant_renewal_budget_pkey PRIMARY KEY (item);
ALTER TABLE public.accountant_spend_report ADD CONSTRAINT accountant_spend_report_pkey PRIMARY KEY (id);
ALTER TABLE public.accountant_subscription_paid_from_change ADD CONSTRAINT accountant_subscription_paid_from_change_pkey PRIMARY KEY (vendor, effective_from);
ALTER TABLE public.accountant_ubo_seen ADD CONSTRAINT accountant_ubo_seen_pkey PRIMARY KEY (lead_id);
ALTER TABLE public.accountant_vat_threshold_check ADD CONSTRAINT accountant_vat_threshold_check_pkey PRIMARY KEY (checked_on);
ALTER TABLE public.accountant_weekly_report ADD CONSTRAINT accountant_weekly_report_pkey PRIMARY KEY (id);
ALTER TABLE public.accountant_year_end_pack ADD CONSTRAINT accountant_year_end_pack_pkey PRIMARY KEY (year);
ALTER TABLE public.action_class_demand ADD CONSTRAINT action_class_demand_pkey PRIMARY KEY (action_class);
ALTER TABLE public.action_class_gate ADD CONSTRAINT action_class_gate_pkey PRIMARY KEY (action_class);
ALTER TABLE public.action_execution ADD CONSTRAINT action_execution_pkey PRIMARY KEY (id);
ALTER TABLE public.ad_campaign_state ADD CONSTRAINT ad_campaign_state_pkey PRIMARY KEY (campaign_id);
ALTER TABLE public.ad_decision ADD CONSTRAINT ad_decision_pkey PRIMARY KEY (id);
ALTER TABLE public.ad_spend_policy ADD CONSTRAINT ad_spend_policy_pkey PRIMARY KEY (policy_key);
ALTER TABLE public.ad_spend_reported ADD CONSTRAINT ad_spend_reported_pkey PRIMARY KEY (source_ref);
ALTER TABLE public.admin_mfa_sessions ADD CONSTRAINT admin_mfa_sessions_pkey PRIMARY KEY (session_id);
ALTER TABLE public.agent_action_kind_policy ADD CONSTRAINT agent_action_kind_policy_pkey PRIMARY KEY (kind);
ALTER TABLE public.agent_actions ADD CONSTRAINT agent_actions_pkey PRIMARY KEY (id);
ALTER TABLE public.agent_chats ADD CONSTRAINT agent_chats_pkey PRIMARY KEY (id);
ALTER TABLE public.agent_command_log ADD CONSTRAINT agent_command_log_pkey PRIMARY KEY (id);
ALTER TABLE public.agent_context_head ADD CONSTRAINT agent_context_head_pkey PRIMARY KEY (agent_key);
ALTER TABLE public.agent_context_retrieval ADD CONSTRAINT agent_context_retrieval_pkey PRIMARY KEY (id);
ALTER TABLE public.agent_evals ADD CONSTRAINT agent_evals_pkey PRIMARY KEY (id);
ALTER TABLE public.agent_expectations ADD CONSTRAINT agent_expectations_pkey PRIMARY KEY (agent);
ALTER TABLE public.agent_governance ADD CONSTRAINT agent_governance_pkey PRIMARY KEY (id);
ALTER TABLE public.agent_knowledge ADD CONSTRAINT agent_knowledge_pkey PRIMARY KEY (id);
ALTER TABLE public.agent_memory ADD CONSTRAINT agent_memory_pkey PRIMARY KEY (id);
ALTER TABLE public.agent_pending_actions ADD CONSTRAINT agent_pending_actions_pkey PRIMARY KEY (token);
ALTER TABLE public.agent_remediation ADD CONSTRAINT agent_remediation_pkey PRIMARY KEY (id);
ALTER TABLE public.agent_reputation ADD CONSTRAINT agent_reputation_pkey PRIMARY KEY (agent_key);
ALTER TABLE public.agent_runs ADD CONSTRAINT agent_runs_pkey PRIMARY KEY (id);
ALTER TABLE public.agent_tool ADD CONSTRAINT agent_tool_pkey PRIMARY KEY (tool_id);
ALTER TABLE public.agent_tool_call ADD CONSTRAINT agent_tool_call_pkey PRIMARY KEY (id);
ALTER TABLE public.agent_training_attempt ADD CONSTRAINT agent_training_attempt_pkey PRIMARY KEY (id);
ALTER TABLE public.agent_training_case ADD CONSTRAINT agent_training_case_pkey PRIMARY KEY (case_id);
ALTER TABLE public.ai_constitution ADD CONSTRAINT ai_constitution_pkey PRIMARY KEY (id);
ALTER TABLE public.ai_cost_log ADD CONSTRAINT ai_cost_log_pkey PRIMARY KEY (id);
ALTER TABLE public.ai_model_register ADD CONSTRAINT ai_model_register_pkey PRIMARY KEY (id);
ALTER TABLE public.ai_qa_log ADD CONSTRAINT ai_qa_log_pkey PRIMARY KEY (id);
ALTER TABLE public.ai_quality_snapshots ADD CONSTRAINT ai_quality_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.ai_rate_limit ADD CONSTRAINT ai_rate_limit_pkey PRIMARY KEY (bucket);
ALTER TABLE public.ai_trainer_snapshots ADD CONSTRAINT ai_trainer_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.ai_usage ADD CONSTRAINT ai_usage_pkey PRIMARY KEY (id);
ALTER TABLE public.alert_signature ADD CONSTRAINT alert_signature_pkey PRIMARY KEY (watcher, signature);
ALTER TABLE public.alert_watermark ADD CONSTRAINT alert_watermark_pkey PRIMARY KEY (watcher);
ALTER TABLE public.allocation_change ADD CONSTRAINT allocation_change_pkey PRIMARY KEY (id);
ALTER TABLE public.ap_bills ADD CONSTRAINT ap_bills_pkey PRIMARY KEY (id);
ALTER TABLE public.app_blocked_domains ADD CONSTRAINT app_blocked_domains_pkey PRIMARY KEY (domain);
ALTER TABLE public.app_secrets ADD CONSTRAINT app_secrets_pkey PRIMARY KEY (key);
ALTER TABLE public.arabic_compare_waiter ADD CONSTRAINT arabic_compare_waiter_pkey PRIMARY KEY (inquiry_id);
ALTER TABLE public.arabic_document_waiter ADD CONSTRAINT arabic_document_waiter_pkey PRIMARY KEY (quote_id);
ALTER TABLE public.arabic_outbound_hold ADD CONSTRAINT arabic_outbound_hold_pkey PRIMARY KEY (id);
ALTER TABLE public.arabic_translation ADD CONSTRAINT arabic_translation_pkey PRIMARY KEY (source_md5);
ALTER TABLE public.artifact_platform_spec ADD CONSTRAINT artifact_platform_spec_pkey PRIMARY KEY (platform, kind);
ALTER TABLE public.artifact_review ADD CONSTRAINT artifact_review_pkey PRIMARY KEY (id);
ALTER TABLE public.assistant_logs ADD CONSTRAINT assistant_logs_pkey PRIMARY KEY (id);
ALTER TABLE public.autonomy_control_audit ADD CONSTRAINT autonomy_control_audit_pkey PRIMARY KEY (id);
ALTER TABLE public.autonomy_policy ADD CONSTRAINT autonomy_policy_pkey PRIMARY KEY (id);
ALTER TABLE public.backup_prune_log ADD CONSTRAINT backup_prune_log_pkey PRIMARY KEY (id);
ALTER TABLE public.bank_line_owner_ruling ADD CONSTRAINT bank_line_owner_ruling_pkey PRIMARY KEY (line_id);
ALTER TABLE public.bank_reference_code ADD CONSTRAINT bank_reference_code_pkey PRIMARY KEY (id);
ALTER TABLE public.bank_statement_intake ADD CONSTRAINT bank_statement_intake_pkey PRIMARY KEY (source_ref);
ALTER TABLE public.bank_statement_line ADD CONSTRAINT bank_statement_line_pkey PRIMARY KEY (id);
ALTER TABLE public.blog_posts ADD CONSTRAINT blog_posts_pkey PRIMARY KEY (id);
ALTER TABLE public.board_advisor ADD CONSTRAINT board_advisor_pkey PRIMARY KEY (advisor_key);
ALTER TABLE public.board_opinion ADD CONSTRAINT board_opinion_pkey PRIMARY KEY (id);
ALTER TABLE public.board_reports ADD CONSTRAINT board_reports_pkey PRIMARY KEY (id);
ALTER TABLE public.boq_fixture ADD CONSTRAINT boq_fixture_pkey PRIMARY KEY (id);
ALTER TABLE public.boq_fixture_run ADD CONSTRAINT boq_fixture_run_pkey PRIMARY KEY (id);
ALTER TABLE public.boq_section_reading ADD CONSTRAINT boq_section_reading_pkey PRIMARY KEY (section_key);
ALTER TABLE public.brand_assets ADD CONSTRAINT brand_assets_pkey PRIMARY KEY (id);
ALTER TABLE public.budget_lines ADD CONSTRAINT budget_lines_pkey PRIMARY KEY (id);
ALTER TABLE public.budgets ADD CONSTRAINT budgets_pkey PRIMARY KEY (id);
ALTER TABLE public.business_rules ADD CONSTRAINT business_rules_pkey PRIMARY KEY (id);
ALTER TABLE public.cad_read_jobs ADD CONSTRAINT cad_read_jobs_pkey PRIMARY KEY (id);
ALTER TABLE public.canon_eval_questions ADD CONSTRAINT canon_eval_questions_pkey PRIMARY KEY (id);
ALTER TABLE public.canon_eval_runs ADD CONSTRAINT canon_eval_runs_pkey PRIMARY KEY (id);
ALTER TABLE public.catalog_category_domain ADD CONSTRAINT catalog_category_domain_pkey PRIMARY KEY (catalog_slug);
ALTER TABLE public.catalog_domains ADD CONSTRAINT catalog_domains_pkey PRIMARY KEY (slug);
ALTER TABLE public.catalog_subcategories ADD CONSTRAINT catalog_subcategories_pkey PRIMARY KEY (id);
ALTER TABLE public.catalog_supplier_categories ADD CONSTRAINT catalog_supplier_categories_pkey PRIMARY KEY (slug);
ALTER TABLE public.category_agent_map ADD CONSTRAINT category_agent_map_pkey PRIMARY KEY (catalog_slug);
ALTER TABLE public.category_agents ADD CONSTRAINT category_agents_pkey PRIMARY KEY (slug);
ALTER TABLE public.category_keyword ADD CONSTRAINT category_keyword_pkey PRIMARY KEY (id);
ALTER TABLE public.category_quote_specs ADD CONSTRAINT category_quote_specs_pkey PRIMARY KEY (id);
ALTER TABLE public.category_route_map ADD CONSTRAINT category_route_map_pkey PRIMARY KEY (category);
ALTER TABLE public.category_specs ADD CONSTRAINT category_specs_pkey PRIMARY KEY (category);
ALTER TABLE public.ceo_approval ADD CONSTRAINT ceo_approval_pkey PRIMARY KEY (decision_id);
ALTER TABLE public.ceo_command ADD CONSTRAINT ceo_command_pkey PRIMARY KEY (command_id);
ALTER TABLE public.ceo_command_intent ADD CONSTRAINT ceo_command_intent_pkey PRIMARY KEY (intent_id);
ALTER TABLE public.ceo_command_rule ADD CONSTRAINT ceo_command_rule_pkey PRIMARY KEY (rule_id);
ALTER TABLE public.ceo_command_state ADD CONSTRAINT ceo_command_state_pkey PRIMARY KEY (state);
ALTER TABLE public.ceo_command_transition ADD CONSTRAINT ceo_command_transition_pkey PRIMARY KEY (from_state, to_state);
ALTER TABLE public.ceo_company_stage ADD CONSTRAINT ceo_company_stage_pkey PRIMARY KEY (stage);
ALTER TABLE public.ceo_company_stage_log ADD CONSTRAINT ceo_company_stage_log_pkey PRIMARY KEY (id);
ALTER TABLE public.ceo_constraint_lever ADD CONSTRAINT ceo_constraint_lever_pkey PRIMARY KEY (stage);
ALTER TABLE public.ceo_daily_digest ADD CONSTRAINT ceo_daily_digest_pkey PRIMARY KEY (id);
ALTER TABLE public.ceo_day ADD CONSTRAINT ceo_day_pkey PRIMARY KEY (day);
ALTER TABLE public.ceo_decision ADD CONSTRAINT ceo_decision_pkey PRIMARY KEY (decision_key);
ALTER TABLE public.ceo_decision_log ADD CONSTRAINT ceo_decision_log_pkey PRIMARY KEY (id);
ALTER TABLE public.ceo_decision_round ADD CONSTRAINT ceo_decision_round_pkey PRIMARY KEY (id);
ALTER TABLE public.ceo_directive ADD CONSTRAINT ceo_directive_pkey PRIMARY KEY (id);
ALTER TABLE public.ceo_experiment ADD CONSTRAINT ceo_experiment_pkey PRIMARY KEY (id);
ALTER TABLE public.ceo_experiment_verdict ADD CONSTRAINT ceo_experiment_verdict_pkey PRIMARY KEY (experiment_id, week);
ALTER TABLE public.ceo_growth_action ADD CONSTRAINT ceo_growth_action_pkey PRIMARY KEY (id);
ALTER TABLE public.ceo_identity ADD CONSTRAINT ceo_identity_pkey PRIMARY KEY (identity);
ALTER TABLE public.ceo_improvement ADD CONSTRAINT ceo_improvement_pkey PRIMARY KEY (id);
ALTER TABLE public.ceo_invite_trade_priority ADD CONSTRAINT ceo_invite_trade_priority_pkey PRIMARY KEY (id);
ALTER TABLE public.ceo_knowledge ADD CONSTRAINT ceo_knowledge_pkey PRIMARY KEY (record_id);
ALTER TABLE public.ceo_launch_gate ADD CONSTRAINT ceo_launch_gate_pkey PRIMARY KEY (week);
ALTER TABLE public.ceo_mandate ADD CONSTRAINT ceo_mandate_pkey PRIMARY KEY (clause_key);
ALTER TABLE public.ceo_market_report ADD CONSTRAINT ceo_market_report_pkey PRIMARY KEY (month, include_demo);
ALTER TABLE public.ceo_month_close ADD CONSTRAINT ceo_month_close_pkey PRIMARY KEY (month, seat);
ALTER TABLE public.ceo_month_report ADD CONSTRAINT ceo_month_report_pkey PRIMARY KEY (month);
ALTER TABLE public.ceo_plan ADD CONSTRAINT ceo_plan_pkey PRIMARY KEY (id);
ALTER TABLE public.ceo_plan_action ADD CONSTRAINT ceo_plan_action_pkey PRIMARY KEY (id);
ALTER TABLE public.ceo_plan_month ADD CONSTRAINT ceo_plan_month_pkey PRIMARY KEY (month);
ALTER TABLE public.ceo_pricing_evidence ADD CONSTRAINT ceo_pricing_evidence_pkey PRIMARY KEY (week);
ALTER TABLE public.ceo_refund_decision_metric ADD CONSTRAINT ceo_refund_decision_metric_pkey PRIMARY KEY (week);
ALTER TABLE public.ceo_review ADD CONSTRAINT ceo_review_pkey PRIMARY KEY (kind, period);
ALTER TABLE public.ceo_seat_audit ADD CONSTRAINT ceo_seat_audit_pkey PRIMARY KEY (quarter, seat);
ALTER TABLE public.ceo_seat_directive ADD CONSTRAINT ceo_seat_directive_pkey PRIMARY KEY (month, seat);
ALTER TABLE public.ceo_standing_grant ADD CONSTRAINT ceo_standing_grant_pkey PRIMARY KEY (grant_key);
ALTER TABLE public.ceo_strategy_memo ADD CONSTRAINT ceo_strategy_memo_pkey PRIMARY KEY (month);
ALTER TABLE public.ceo_supplier_channel ADD CONSTRAINT ceo_supplier_channel_pkey PRIMARY KEY (channel);
ALTER TABLE public.ceo_supplier_funnel_daily ADD CONSTRAINT ceo_supplier_funnel_daily_pkey PRIMARY KEY (day, channel);
ALTER TABLE public.ceo_supplier_goal ADD CONSTRAINT ceo_supplier_goal_pkey PRIMARY KEY (goal);
ALTER TABLE public.ceo_task ADD CONSTRAINT ceo_task_pkey PRIMARY KEY (task_id);
ALTER TABLE public.ceo_task_state ADD CONSTRAINT ceo_task_state_pkey PRIMARY KEY (state);
ALTER TABLE public.ceo_weekly_report ADD CONSTRAINT ceo_weekly_report_pkey PRIMARY KEY (id);
ALTER TABLE public.ceo_weekly_review ADD CONSTRAINT ceo_weekly_review_pkey PRIMARY KEY (id);
ALTER TABLE public.ceo_year_plan ADD CONSTRAINT ceo_year_plan_pkey PRIMARY KEY (month);
ALTER TABLE public.ceo_year_plan_milestone ADD CONSTRAINT ceo_year_plan_milestone_pkey PRIMARY KEY (due);
ALTER TABLE public.challenge_heuristic ADD CONSTRAINT challenge_heuristic_pkey PRIMARY KEY (id);
ALTER TABLE public.challenge_record ADD CONSTRAINT challenge_record_pkey PRIMARY KEY (id);
ALTER TABLE public.channel_directive ADD CONSTRAINT channel_directive_pkey PRIMARY KEY (id);
ALTER TABLE public.charge_audit ADD CONSTRAINT charge_audit_pkey PRIMARY KEY (transaction_id);
ALTER TABLE public.chat_threads ADD CONSTRAINT chat_threads_pkey PRIMARY KEY (inquiry_id, supplier_id);
ALTER TABLE public.chat_violations ADD CONSTRAINT chat_violations_pkey PRIMARY KEY (id);
ALTER TABLE public.collaboration_rule ADD CONSTRAINT collaboration_rule_pkey PRIMARY KEY (id);
ALTER TABLE public.collections_config ADD CONSTRAINT collections_config_pkey PRIMARY KEY (id);
ALTER TABLE public.company_brand ADD CONSTRAINT company_brand_pkey PRIMARY KEY (key);
ALTER TABLE public.company_calendar ADD CONSTRAINT company_calendar_pkey PRIMARY KEY (id);
ALTER TABLE public.company_charter ADD CONSTRAINT company_charter_pkey PRIMARY KEY (id);
ALTER TABLE public.company_constitution ADD CONSTRAINT company_constitution_pkey PRIMARY KEY (article_no);
ALTER TABLE public.company_event ADD CONSTRAINT company_event_pkey PRIMARY KEY (id);
ALTER TABLE public.company_faq ADD CONSTRAINT company_faq_pkey PRIMARY KEY (id);
ALTER TABLE public.company_faq_embed_inflight ADD CONSTRAINT company_faq_embed_inflight_pkey PRIMARY KEY (request_id);
ALTER TABLE public.company_financial_stance ADD CONSTRAINT company_financial_stance_pkey PRIMARY KEY (id);
ALTER TABLE public.company_goals ADD CONSTRAINT company_goals_pkey PRIMARY KEY (key);
ALTER TABLE public.company_index ADD CONSTRAINT company_index_pkey PRIMARY KEY (id);
ALTER TABLE public.company_policy_decision ADD CONSTRAINT company_policy_decision_pkey PRIMARY KEY (decision_key);
ALTER TABLE public.company_reflection ADD CONSTRAINT company_reflection_pkey PRIMARY KEY (id);
ALTER TABLE public.company_registration ADD CONSTRAINT company_registration_pkey PRIMARY KEY (recorded_at);
ALTER TABLE public.company_reputation_snapshot ADD CONSTRAINT company_reputation_snapshot_pkey PRIMARY KEY (day);
ALTER TABLE public.company_review_ask ADD CONSTRAINT company_review_ask_pkey PRIMARY KEY (id);
ALTER TABLE public.company_snapshot ADD CONSTRAINT company_snapshot_pkey PRIMARY KEY (snapshot_on);
ALTER TABLE public.company_stand_down ADD CONSTRAINT company_stand_down_pkey PRIMARY KEY (id);
ALTER TABLE public.company_vision ADD CONSTRAINT company_vision_pkey PRIMARY KEY (id);
ALTER TABLE public.comparison_run_v2 ADD CONSTRAINT comparison_run_v2_pkey PRIMARY KEY (id);
ALTER TABLE public.competitive_position ADD CONSTRAINT competitive_position_pkey PRIMARY KEY (id);
ALTER TABLE public.competitor ADD CONSTRAINT competitor_pkey PRIMARY KEY (id);
ALTER TABLE public.competitor_scan ADD CONSTRAINT competitor_scan_pkey PRIMARY KEY (id);
ALTER TABLE public.complaint_tickets ADD CONSTRAINT complaint_tickets_pkey PRIMARY KEY (id);
ALTER TABLE public.compliance_sources ADD CONSTRAINT compliance_sources_pkey PRIMARY KEY (id);
ALTER TABLE public.contact_duplicate_group ADD CONSTRAINT contact_duplicate_group_pkey PRIMARY KEY (id);
ALTER TABLE public.contact_merge_audit ADD CONSTRAINT contact_merge_audit_pkey PRIMARY KEY (id);
ALTER TABLE public.contact_messages ADD CONSTRAINT contact_messages_pkey PRIMARY KEY (id);
ALTER TABLE public.content_drafts ADD CONSTRAINT content_drafts_pkey PRIMARY KEY (id);
ALTER TABLE public.continuity_plan ADD CONSTRAINT continuity_plan_pkey PRIMARY KEY (service);
ALTER TABLE public.control_mode_action ADD CONSTRAINT control_mode_action_pkey PRIMARY KEY (action);
ALTER TABLE public.control_mode_audit ADD CONSTRAINT control_mode_audit_pkey PRIMARY KEY (id);
ALTER TABLE public.control_mode_challenge ADD CONSTRAINT control_mode_challenge_pkey PRIMARY KEY (id);
ALTER TABLE public.control_mode_identity ADD CONSTRAINT control_mode_identity_pkey PRIMARY KEY (admin_email);
ALTER TABLE public.control_mode_session ADD CONSTRAINT control_mode_session_pkey PRIMARY KEY (id);
ALTER TABLE public.conversation_archive ADD CONSTRAINT conversation_archive_pkey PRIMARY KEY (source_table, source_id);
ALTER TABLE public.conversation_archive_attempt ADD CONSTRAINT conversation_archive_attempt_pkey PRIMARY KEY (source_table, source_id);
ALTER TABLE public.conversation_retention_log ADD CONSTRAINT conversation_retention_log_pkey PRIMARY KEY (source_table, source_id);
ALTER TABLE public.conversation_retention_pdf ADD CONSTRAINT conversation_retention_pdf_pkey PRIMARY KEY (source_table, source_id);
ALTER TABLE public.conversation_retention_plan_log ADD CONSTRAINT conversation_retention_plan_log_pkey PRIMARY KEY (decided_for, source_table, source_id);
ALTER TABLE public.critical_capability ADD CONSTRAINT critical_capability_pkey PRIMARY KEY (capability_key);
ALTER TABLE public.crm_activities ADD CONSTRAINT crm_activities_pkey PRIMARY KEY (id);
ALTER TABLE public.crm_notes ADD CONSTRAINT crm_notes_pkey PRIMARY KEY (id);
ALTER TABLE public.crm_stages ADD CONSTRAINT crm_stages_pkey PRIMARY KEY (key);
ALTER TABLE public.crm_tasks ADD CONSTRAINT crm_tasks_pkey PRIMARY KEY (id);
ALTER TABLE public.cron_job_seen ADD CONSTRAINT cron_job_seen_pkey PRIMARY KEY (jobid);
ALTER TABLE public.cron_registry ADD CONSTRAINT cron_registry_pkey PRIMARY KEY (jobname);
ALTER TABLE public.customer_calls ADD CONSTRAINT customer_calls_pkey PRIMARY KEY (id);
ALTER TABLE public.customer_followup ADD CONSTRAINT customer_followup_pkey PRIMARY KEY (id);
ALTER TABLE public.customer_kpi_snapshots ADD CONSTRAINT customer_kpi_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.customer_layout ADD CONSTRAINT customer_layout_pkey PRIMARY KEY (customer_id);
ALTER TABLE public.customer_phone_otps ADD CONSTRAINT customer_phone_otps_pkey PRIMARY KEY (id);
ALTER TABLE public.customer_preference ADD CONSTRAINT customer_preference_pkey PRIMARY KEY (customer_id);
ALTER TABLE public.customer_score ADD CONSTRAINT customer_score_pkey PRIMARY KEY (customer_id);
ALTER TABLE public.customer_spec_guide ADD CONSTRAINT customer_spec_guide_pkey PRIMARY KEY (trade);
ALTER TABLE public.customer_support_case_review ADD CONSTRAINT customer_support_case_review_pkey PRIMARY KEY (week_ending);
ALTER TABLE public.customer_support_data_request ADD CONSTRAINT customer_support_data_request_pkey PRIMARY KEY (id);
ALTER TABLE public.customer_support_duty_message ADD CONSTRAINT customer_support_duty_message_pkey PRIMARY KEY (stage, subject_key);
ALTER TABLE public.customer_support_inbound_drive ADD CONSTRAINT customer_support_inbound_drive_pkey PRIMARY KEY (channel, message_id);
ALTER TABLE public.customer_support_monthly_review ADD CONSTRAINT customer_support_monthly_review_pkey PRIMARY KEY (month);
ALTER TABLE public.customer_support_reply_quality_week ADD CONSTRAINT customer_support_reply_quality_week_pkey PRIMARY KEY (week_ending);
ALTER TABLE public.customer_support_voc_month ADD CONSTRAINT customer_support_voc_month_pkey PRIMARY KEY (month);
ALTER TABLE public.customer_support_voice_owed ADD CONSTRAINT customer_support_voice_owed_pkey PRIMARY KEY (stage, subject_key);
ALTER TABLE public.customers ADD CONSTRAINT customers_pkey PRIMARY KEY (id);
ALTER TABLE public.dead_letter ADD CONSTRAINT dead_letter_pkey PRIMARY KEY (id);
ALTER TABLE public.decision_log ADD CONSTRAINT decision_log_pkey PRIMARY KEY (id);
ALTER TABLE public.decision_policy ADD CONSTRAINT decision_policy_pkey PRIMARY KEY (key);
ALTER TABLE public.decision_record ADD CONSTRAINT decision_record_pkey PRIMARY KEY (id);
ALTER TABLE public.decision_review_request ADD CONSTRAINT decision_review_request_pkey PRIMARY KEY (id);
ALTER TABLE public.decision_trace ADD CONSTRAINT decision_trace_pkey PRIMARY KEY (id);
ALTER TABLE public.delegation_rule ADD CONSTRAINT delegation_rule_pkey PRIMARY KEY (id);
ALTER TABLE public.deliverability_test ADD CONSTRAINT deliverability_test_pkey PRIMARY KEY (test_id);
ALTER TABLE public.deliverability_test_provider ADD CONSTRAINT deliverability_test_provider_pkey PRIMARY KEY (test_id, provider);
ALTER TABLE public.demand_forecast ADD CONSTRAINT demand_forecast_pkey PRIMARY KEY (run_on, trade, emirate);
ALTER TABLE public.demand_search ADD CONSTRAINT demand_search_pkey PRIMARY KEY (id);
ALTER TABLE public.department_budget ADD CONSTRAINT department_budget_pkey PRIMARY KEY (dept_key);
ALTER TABLE public.department_objective ADD CONSTRAINT department_objective_pkey PRIMARY KEY (id);
ALTER TABLE public.deploy_state ADD CONSTRAINT deploy_state_pkey PRIMARY KEY (id);
ALTER TABLE public.dept_knowledge_alias ADD CONSTRAINT dept_knowledge_alias_pkey PRIMARY KEY (dept_key, alias_kind, alias_key);
ALTER TABLE public.dept_library ADD CONSTRAINT dept_library_pkey PRIMARY KEY (id);
ALTER TABLE public.doc_backups ADD CONSTRAINT doc_backups_pkey PRIMARY KEY (id);
ALTER TABLE public.doc_reviews ADD CONSTRAINT doc_reviews_pkey PRIMARY KEY (id);
ALTER TABLE public.doc_versions ADD CONSTRAINT doc_versions_pkey PRIMARY KEY (id);
ALTER TABLE public.document_kpi_snapshots ADD CONSTRAINT document_kpi_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.documents ADD CONSTRAINT documents_pkey PRIMARY KEY (id);
ALTER TABLE public.drawing_redaction_runs ADD CONSTRAINT drawing_redaction_runs_pkey PRIMARY KEY (id);
ALTER TABLE public.dropbox_files ADD CONSTRAINT dropbox_files_pkey PRIMARY KEY (id);
ALTER TABLE public.duty_pause ADD CONSTRAINT duty_pause_pkey PRIMARY KEY (duty);
ALTER TABLE public.ea_events ADD CONSTRAINT ea_events_pkey PRIMARY KEY (id);
ALTER TABLE public.ea_meetings ADD CONSTRAINT ea_meetings_pkey PRIMARY KEY (id);
ALTER TABLE public.ea_reminders ADD CONSTRAINT ea_reminders_pkey PRIMARY KEY (id);
ALTER TABLE public.edge_expectation ADD CONSTRAINT edge_expectation_pkey PRIMARY KEY (fn_key);
ALTER TABLE public.edge_health_probe ADD CONSTRAINT edge_health_probe_pkey PRIMARY KEY (id);
ALTER TABLE public.email_block_pattern ADD CONSTRAINT email_block_pattern_pkey PRIMARY KEY (id);
ALTER TABLE public.email_domain_mx ADD CONSTRAINT email_domain_mx_pkey PRIMARY KEY (domain);
ALTER TABLE public.email_platform_domain ADD CONSTRAINT email_platform_domain_pkey PRIMARY KEY (domain);
ALTER TABLE public.email_suppressions ADD CONSTRAINT email_suppressions_pkey PRIMARY KEY (email);
ALTER TABLE public.email_verifications ADD CONSTRAINT email_verifications_pkey PRIMARY KEY (id);
ALTER TABLE public.employee_authority ADD CONSTRAINT employee_authority_pkey PRIMARY KEY (agent_key, action_class);
ALTER TABLE public.employee_knowledge ADD CONSTRAINT employee_knowledge_pkey PRIMARY KEY (agent_key, domain_key);
ALTER TABLE public.employee_knowledge_standard ADD CONSTRAINT employee_knowledge_standard_pkey PRIMARY KEY (layer_no);
ALTER TABLE public.employee_kpi ADD CONSTRAINT employee_kpi_pkey PRIMARY KEY (id);
ALTER TABLE public.employee_kpi_history ADD CONSTRAINT employee_kpi_history_pkey PRIMARY KEY (id);
ALTER TABLE public.employee_workflow ADD CONSTRAINT employee_workflow_pkey PRIMARY KEY (agent_key, workflow_key);
ALTER TABLE public.entity_comments ADD CONSTRAINT entity_comments_pkey PRIMARY KEY (id);
ALTER TABLE public.error_events ADD CONSTRAINT error_events_pkey PRIMARY KEY (id);
ALTER TABLE public.event_assessment ADD CONSTRAINT event_assessment_pkey PRIMARY KEY (id);
ALTER TABLE public.event_delivery ADD CONSTRAINT event_delivery_pkey PRIMARY KEY (id);
ALTER TABLE public.event_rollup ADD CONSTRAINT event_rollup_pkey PRIMARY KEY (correlation_id);
ALTER TABLE public.event_subscription ADD CONSTRAINT event_subscription_pkey PRIMARY KEY (agent_key, event_type);
ALTER TABLE public.evolution_proposal ADD CONSTRAINT evolution_proposal_pkey PRIMARY KEY (id);
ALTER TABLE public.exec_reports ADD CONSTRAINT exec_reports_pkey PRIMARY KEY (id);
ALTER TABLE public.expense_bank_match ADD CONSTRAINT expense_bank_match_pkey PRIMARY KEY (expense_entry_id);
ALTER TABLE public.expense_billing_mailbox ADD CONSTRAINT expense_billing_mailbox_pkey PRIMARY KEY (mailbox);
ALTER TABLE public.expense_entries ADD CONSTRAINT expense_entries_pkey PRIMARY KEY (id);
ALTER TABLE public.expense_sender_reading ADD CONSTRAINT expense_sender_reading_pkey PRIMARY KEY (sender);
ALTER TABLE public.expense_vendor_billing_mailbox ADD CONSTRAINT expense_vendor_billing_mailbox_pkey PRIMARY KEY (id);
ALTER TABLE public.expenses ADD CONSTRAINT expenses_pkey PRIMARY KEY (id);
ALTER TABLE public.feedback ADD CONSTRAINT feedback_pkey PRIMARY KEY (id);
ALTER TABLE public.field_definition ADD CONSTRAINT field_definition_pkey PRIMARY KEY (field_id);
ALTER TABLE public.field_definition_reference ADD CONSTRAINT field_definition_reference_pkey PRIMARY KEY (field_id, referencing_trade_key);
ALTER TABLE public.field_definition_trade ADD CONSTRAINT field_definition_trade_pkey PRIMARY KEY (field_id, trade_key);
ALTER TABLE public.file_scan ADD CONSTRAINT file_scan_pkey PRIMARY KEY (id);
ALTER TABLE public.finance_kpi_snapshots ADD CONSTRAINT finance_kpi_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.finance_reports ADD CONSTRAINT finance_reports_pkey PRIMARY KEY (id);
ALTER TABLE public.finance_snapshots ADD CONSTRAINT finance_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.fn_task_class ADD CONSTRAINT fn_task_class_pkey PRIMARY KEY (fn);
ALTER TABLE public.founder_alerts ADD CONSTRAINT founder_alerts_pkey PRIMARY KEY (id);
ALTER TABLE public.founder_directive ADD CONSTRAINT founder_directive_pkey PRIMARY KEY (id);
ALTER TABLE public.founder_habit ADD CONSTRAINT founder_habit_pkey PRIMARY KEY (founder, habit_key);
ALTER TABLE public.founder_hold ADD CONSTRAINT founder_hold_pkey PRIMARY KEY (hold_key);
ALTER TABLE public.founder_instruction ADD CONSTRAINT founder_instruction_pkey PRIMARY KEY (id);
ALTER TABLE public.founder_mail_policy ADD CONSTRAINT founder_mail_policy_pkey PRIMARY KEY (kind);
ALTER TABLE public.founder_mail_policy_history ADD CONSTRAINT founder_mail_policy_history_pkey PRIMARY KEY (id);
ALTER TABLE public.fraud_flags ADD CONSTRAINT fraud_flags_pkey PRIMARY KEY (kind, subject_type, subject_id);
ALTER TABLE public.free_email_domain ADD CONSTRAINT free_email_domain_pkey PRIMARY KEY (domain);
ALTER TABLE public.function_owner ADD CONSTRAINT function_owner_pkey PRIMARY KEY (function_slug);
ALTER TABLE public.gl_account_funnel_stage ADD CONSTRAINT gl_account_funnel_stage_pkey PRIMARY KEY (account_code);
ALTER TABLE public.gl_accounts ADD CONSTRAINT gl_accounts_pkey PRIMARY KEY (code);
ALTER TABLE public.gl_expense_map ADD CONSTRAINT gl_expense_map_pkey PRIMARY KEY (category);
ALTER TABLE public.gl_journal ADD CONSTRAINT gl_journal_pkey PRIMARY KEY (id);
ALTER TABLE public.gl_journal_lines ADD CONSTRAINT gl_journal_lines_pkey PRIMARY KEY (id);
ALTER TABLE public.gl_prior_period_adjustment ADD CONSTRAINT gl_prior_period_adjustment_pkey PRIMARY KEY (journal_id);
ALTER TABLE public.gl_settings ADD CONSTRAINT gl_settings_pkey PRIMARY KEY (key);
ALTER TABLE public.goal_period ADD CONSTRAINT goal_period_pkey PRIMARY KEY (id);
ALTER TABLE public.governance_policy ADD CONSTRAINT governance_policy_pkey PRIMARY KEY (id);
ALTER TABLE public.governance_sensitive ADD CONSTRAINT governance_sensitive_pkey PRIMARY KEY (subject, key);
ALTER TABLE public.graph_edges ADD CONSTRAINT graph_edges_pkey PRIMARY KEY (src_kind, src_ref, rel, dst_kind, dst_ref);
ALTER TABLE public.graph_nodes ADD CONSTRAINT graph_nodes_pkey PRIMARY KEY (kind, ref_id);
ALTER TABLE public.handoff_contract ADD CONSTRAINT handoff_contract_pkey PRIMARY KEY (id);
ALTER TABLE public.health_checks ADD CONSTRAINT health_checks_pkey PRIMARY KEY (id);
ALTER TABLE public.health_state ADD CONSTRAINT health_state_pkey PRIMARY KEY (id);
ALTER TABLE public.idea ADD CONSTRAINT idea_pkey PRIMARY KEY (id);
ALTER TABLE public.inbound_messages ADD CONSTRAINT inbound_messages_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiries ADD CONSTRAINT inquiries_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiry_answer ADD CONSTRAINT inquiry_answer_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiry_answer_conflict ADD CONSTRAINT inquiry_answer_conflict_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiry_answer_conflict_value ADD CONSTRAINT inquiry_answer_conflict_value_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiry_answer_corroboration ADD CONSTRAINT inquiry_answer_corroboration_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiry_answer_document ADD CONSTRAINT inquiry_answer_document_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiry_answer_scope ADD CONSTRAINT inquiry_answer_scope_pkey PRIMARY KEY (answer_id, workstream_id);
ALTER TABLE public.inquiry_cancellations ADD CONSTRAINT inquiry_cancellations_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiry_conversation_summary ADD CONSTRAINT inquiry_conversation_summary_pkey PRIMARY KEY (inquiry_id);
ALTER TABLE public.inquiry_gate ADD CONSTRAINT inquiry_gate_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiry_gate_required ADD CONSTRAINT inquiry_gate_required_pkey PRIMARY KEY (gate_key);
ALTER TABLE public.inquiry_intake ADD CONSTRAINT inquiry_intake_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiry_matches ADD CONSTRAINT inquiry_matches_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiry_requirement ADD CONSTRAINT inquiry_requirement_pkey PRIMARY KEY (inquiry_id);
ALTER TABLE public.inquiry_scope_disposition ADD CONSTRAINT inquiry_scope_disposition_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiry_state_audit ADD CONSTRAINT inquiry_state_audit_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiry_supplier_brief ADD CONSTRAINT inquiry_supplier_brief_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiry_trade_candidate ADD CONSTRAINT inquiry_trade_candidate_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiry_trade_candidate_evidence ADD CONSTRAINT inquiry_trade_candidate_evidence_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiry_trade_clarification ADD CONSTRAINT inquiry_trade_clarification_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiry_workstream ADD CONSTRAINT inquiry_workstream_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiry_workstream_group ADD CONSTRAINT inquiry_workstream_group_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiry_workstream_requirement ADD CONSTRAINT inquiry_workstream_requirement_pkey PRIMARY KEY (id);
ALTER TABLE public.institutional_memory ADD CONSTRAINT institutional_memory_pkey PRIMARY KEY (id);
ALTER TABLE public.intake_trade_taxonomy ADD CONSTRAINT intake_trade_taxonomy_pkey PRIMARY KEY (intake_slug);
ALTER TABLE public.integration_matrix ADD CONSTRAINT integration_matrix_pkey PRIMARY KEY (service);
ALTER TABLE public.internal_credential ADD CONSTRAINT internal_credential_pkey PRIMARY KEY (id);
ALTER TABLE public.internal_credential_audit ADD CONSTRAINT internal_credential_audit_pkey PRIMARY KEY (id);
ALTER TABLE public.inv_items ADD CONSTRAINT inv_items_pkey PRIMARY KEY (id);
ALTER TABLE public.invite_brake ADD CONSTRAINT invite_brake_pkey PRIMARY KEY (id);
ALTER TABLE public.invite_placement_bar ADD CONSTRAINT invite_placement_bar_pkey PRIMARY KEY (id);
ALTER TABLE public.invite_placement_check ADD CONSTRAINT invite_placement_check_pkey PRIMARY KEY (dubai_day);
ALTER TABLE public.invite_schedule ADD CONSTRAINT invite_schedule_pkey PRIMARY KEY (day);
ALTER TABLE public.it_access_known ADD CONSTRAINT it_access_known_pkey PRIMARY KEY (system, principal);
ALTER TABLE public.it_change_acceptance ADD CONSTRAINT it_change_acceptance_pkey PRIMARY KEY (txid);
ALTER TABLE public.it_change_revision ADD CONSTRAINT it_change_revision_pkey PRIMARY KEY (rev);
ALTER TABLE public.it_change_source ADD CONSTRAINT it_change_source_pkey PRIMARY KEY (match_on, pattern);
ALTER TABLE public.it_cost_watch_week ADD CONSTRAINT it_cost_watch_week_pkey PRIMARY KEY (week_ending, provider);
ALTER TABLE public.it_credential_class ADD CONSTRAINT it_credential_class_pkey PRIMARY KEY (credential);
ALTER TABLE public.it_credential_rotation ADD CONSTRAINT it_credential_rotation_pkey PRIMARY KEY (id);
ALTER TABLE public.it_duty_schedule ADD CONSTRAINT it_duty_schedule_pkey PRIMARY KEY (duty);
ALTER TABLE public.it_engineer_finding ADD CONSTRAINT it_engineer_finding_pkey PRIMARY KEY (issue_key);
ALTER TABLE public.it_engineer_knowledge ADD CONSTRAINT it_engineer_knowledge_pkey PRIMARY KEY (record_id);
ALTER TABLE public.it_engineer_scanner ADD CONSTRAINT it_engineer_scanner_pkey PRIMARY KEY (scanner);
ALTER TABLE public.it_expected_table_growth ADD CONSTRAINT it_expected_table_growth_pkey PRIMARY KEY (relid);
ALTER TABLE public.it_expiry ADD CONSTRAINT it_expiry_pkey PRIMARY KEY (item);
ALTER TABLE public.it_finding_closure ADD CONSTRAINT it_finding_closure_pkey PRIMARY KEY (issue_key);
ALTER TABLE public.it_founder_decision_class ADD CONSTRAINT it_founder_decision_class_pkey PRIMARY KEY (issue_key_like);
ALTER TABLE public.it_game_day_run ADD CONSTRAINT it_game_day_run_pkey PRIMARY KEY (id);
ALTER TABLE public.it_hold_signature ADD CONSTRAINT it_hold_signature_pkey PRIMARY KEY (id);
ALTER TABLE public.it_incident ADD CONSTRAINT it_incident_pkey PRIMARY KEY (id);
ALTER TABLE public.it_integration_external_cause ADD CONSTRAINT it_integration_external_cause_pkey PRIMARY KEY (id);
ALTER TABLE public.it_load_test_run ADD CONSTRAINT it_load_test_run_pkey PRIMARY KEY (id);
ALTER TABLE public.it_model_consumer ADD CONSTRAINT it_model_consumer_pkey PRIMARY KEY (consumer);
ALTER TABLE public.it_playbook ADD CONSTRAINT it_playbook_pkey PRIMARY KEY (failure_class);
ALTER TABLE public.it_postmaster_reading ADD CONSTRAINT it_postmaster_reading_pkey PRIMARY KEY (domain, read_on);
ALTER TABLE public.it_query_stat_snapshot ADD CONSTRAINT it_query_stat_snapshot_pkey PRIMARY KEY (queryid);
ALTER TABLE public.it_refusal_policy ADD CONSTRAINT it_refusal_policy_pkey PRIMARY KEY (subject, reason_key);
ALTER TABLE public.it_restore_drill_result ADD CONSTRAINT it_restore_drill_result_pkey PRIMARY KEY (id);
ALTER TABLE public.it_restore_drill_table ADD CONSTRAINT it_restore_drill_table_pkey PRIMARY KEY (table_name);
ALTER TABLE public.it_security_baseline ADD CONSTRAINT it_security_baseline_pkey PRIMARY KEY (object, kind);
ALTER TABLE public.it_sender_health_daily ADD CONSTRAINT it_sender_health_daily_pkey PRIMARY KEY (day);
ALTER TABLE public.it_spend_daily ADD CONSTRAINT it_spend_daily_pkey PRIMARY KEY (day, source);
ALTER TABLE public.it_table_size_daily ADD CONSTRAINT it_table_size_daily_pkey PRIMARY KEY (day, relid);
ALTER TABLE public.it_threshold ADD CONSTRAINT it_threshold_pkey PRIMARY KEY (key);
ALTER TABLE public.it_watch_finding ADD CONSTRAINT it_watch_finding_pkey PRIMARY KEY (detector_key);
ALTER TABLE public.it_watch_queue ADD CONSTRAINT it_watch_queue_pkey PRIMARY KEY (queue_key);
ALTER TABLE public.it_watch_subject ADD CONSTRAINT it_watch_subject_pkey PRIMARY KEY (subject);
ALTER TABLE public.it_watch_tick ADD CONSTRAINT it_watch_tick_pkey PRIMARY KEY (id);
ALTER TABLE public.kb_category_aliases ADD CONSTRAINT kb_category_aliases_pkey PRIMARY KEY (category, maps_to);
ALTER TABLE public.kb_category_stats ADD CONSTRAINT kb_category_stats_pkey PRIMARY KEY (category, source_kind);
ALTER TABLE public.kb_chunk_quarantine ADD CONSTRAINT kb_chunk_quarantine_pkey PRIMARY KEY (id);
ALTER TABLE public.kb_chunks ADD CONSTRAINT kb_chunks_pkey PRIMARY KEY (id);
ALTER TABLE public.kb_chunks_old ADD CONSTRAINT kb_chunks_old_pkey PRIMARY KEY (id);
ALTER TABLE public.kb_chunks_swap_log ADD CONSTRAINT kb_chunks_swap_log_pkey PRIMARY KEY (seq);
ALTER TABLE public.kb_citation_jurisdiction ADD CONSTRAINT kb_citation_jurisdiction_pkey PRIMARY KEY (citation_md5);
ALTER TABLE public.kb_embed_inflight ADD CONSTRAINT kb_embed_inflight_pkey PRIMARY KEY (request_id);
ALTER TABLE public.kb_embed_priority ADD CONSTRAINT kb_embed_priority_pkey PRIMARY KEY (category);
ALTER TABLE public.kb_operational_alias ADD CONSTRAINT kb_operational_alias_pkey PRIMARY KEY (catalog_num, language, alias);
ALTER TABLE public.kb_operational_route ADD CONSTRAINT kb_operational_route_pkey PRIMARY KEY (catalog_num);
ALTER TABLE public.kb_operational_route_map ADD CONSTRAINT kb_operational_route_map_pkey PRIMARY KEY (catalog_num, package_slug, subcategory_slug);
ALTER TABLE public.kb_operational_route_test ADD CONSTRAINT kb_operational_route_test_pkey PRIMARY KEY (test_id);
ALTER TABLE public.kb_purge_ledger ADD CONSTRAINT kb_purge_ledger_pkey PRIMARY KEY (id);
ALTER TABLE public.kb_revisions ADD CONSTRAINT kb_revisions_pkey PRIMARY KEY (id);
ALTER TABLE public.kb_route_scope_trigger ADD CONSTRAINT kb_route_scope_trigger_pkey PRIMARY KEY (catalog_num, trigger_scope);
ALTER TABLE public.kb_trim_hash ADD CONSTRAINT kb_trim_hash_pkey PRIMARY KEY (id);
ALTER TABLE public.kb_trim_plan ADD CONSTRAINT kb_trim_plan_pkey PRIMARY KEY (id);
ALTER TABLE public.kb_usage_log ADD CONSTRAINT kb_usage_log_pkey PRIMARY KEY (id);
ALTER TABLE public.knowledge_domain ADD CONSTRAINT knowledge_domain_pkey PRIMARY KEY (domain_key);
ALTER TABLE public.knowledge_exam_questions ADD CONSTRAINT knowledge_exam_questions_pkey PRIMARY KEY (id);
ALTER TABLE public.knowledge_exam_results ADD CONSTRAINT knowledge_exam_results_pkey PRIMARY KEY (id);
ALTER TABLE public.knowledge_ingestion_run ADD CONSTRAINT knowledge_ingestion_run_pkey PRIMARY KEY (run_id);
ALTER TABLE public.knowledge_ingestion_undo ADD CONSTRAINT knowledge_ingestion_undo_pkey PRIMARY KEY (run_id, table_name, key);
ALTER TABLE public.knowledge_internal_figure_record ADD CONSTRAINT knowledge_internal_figure_record_pkey PRIMARY KEY (record_id);
ALTER TABLE public.knowledge_kpi_snapshots ADD CONSTRAINT knowledge_kpi_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.knowledge_library ADD CONSTRAINT knowledge_library_pkey PRIMARY KEY (id);
ALTER TABLE public.knowledge_library_origin ADD CONSTRAINT knowledge_library_origin_pkey PRIMARY KEY (origin_store, origin_id);
ALTER TABLE public.knowledge_library_state ADD CONSTRAINT knowledge_library_state_pkey PRIMARY KEY (id);
ALTER TABLE public.knowledge_ml_claim ADD CONSTRAINT knowledge_ml_claim_pkey PRIMARY KEY (src, row_id);
ALTER TABLE public.knowledge_ml_status ADD CONSTRAINT knowledge_ml_status_pkey PRIMARY KEY (id);
ALTER TABLE public.knowledge_module_standard ADD CONSTRAINT knowledge_module_standard_pkey PRIMARY KEY (module);
ALTER TABLE public.knowledge_vector_ml ADD CONSTRAINT knowledge_vector_ml_pkey PRIMARY KEY (src, row_id);
ALTER TABLE public.lead_category ADD CONSTRAINT lead_category_pkey PRIMARY KEY (lead_id, slug);
ALTER TABLE public.lead_email_check ADD CONSTRAINT lead_email_check_pkey PRIMARY KEY (lead_id);
ALTER TABLE public.lead_prospect ADD CONSTRAINT lead_prospect_pkey PRIMARY KEY (id);
ALTER TABLE public.lead_sourcing_run ADD CONSTRAINT lead_sourcing_run_pkey PRIMARY KEY (id);
ALTER TABLE public.lead_subcategory ADD CONSTRAINT lead_subcategory_pkey PRIMARY KEY (lead_id, sub_slug);
ALTER TABLE public.lead_trade_class ADD CONSTRAINT lead_trade_class_pkey PRIMARY KEY (lead_id);
ALTER TABLE public.lead_trade_map ADD CONSTRAINT lead_trade_map_pkey PRIMARY KEY (trade_key);
ALTER TABLE public.leads ADD CONSTRAINT leads_pkey PRIMARY KEY (id);
ALTER TABLE public.legal_checklist ADD CONSTRAINT legal_checklist_pkey PRIMARY KEY (id);
ALTER TABLE public.legal_documents ADD CONSTRAINT legal_documents_pkey PRIMARY KEY (slug);
ALTER TABLE public.legal_kpi_snapshots ADD CONSTRAINT legal_kpi_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.legal_reviews ADD CONSTRAINT legal_reviews_pkey PRIMARY KEY (id);
ALTER TABLE public.licence_renewal_ask ADD CONSTRAINT licence_renewal_ask_pkey PRIMARY KEY (id);
ALTER TABLE public.line_spec_reading ADD CONSTRAINT line_spec_reading_pkey PRIMARY KEY (reading_key);
ALTER TABLE public.llm_attempt ADD CONSTRAINT llm_attempt_pkey PRIMARY KEY (attempt_id);
ALTER TABLE public.llm_cache ADD CONSTRAINT llm_cache_pkey PRIMARY KEY (cache_key);
ALTER TABLE public.llm_calls ADD CONSTRAINT llm_calls_pkey PRIMARY KEY (id);
ALTER TABLE public.llm_failure_class ADD CONSTRAINT llm_failure_class_pkey PRIMARY KEY (class_key);
ALTER TABLE public.llm_route_health ADD CONSTRAINT llm_route_health_pkey PRIMARY KEY (model_id);
ALTER TABLE public.llm_seat_binding ADD CONSTRAINT llm_seat_binding_pkey PRIMARY KEY (fn);
ALTER TABLE public.market_intel ADD CONSTRAINT market_intel_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_ad_spend_day ADD CONSTRAINT marketing_ad_spend_day_pkey PRIMARY KEY (account_id, campaign_id, day);
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_article_round ADD CONSTRAINT marketing_article_round_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_asset_feature ADD CONSTRAINT marketing_asset_feature_pkey PRIMARY KEY (file_sha256, extractor_version);
ALTER TABLE public.marketing_asset_perception ADD CONSTRAINT marketing_asset_perception_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_asset_review ADD CONSTRAINT marketing_asset_review_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_blog_topic ADD CONSTRAINT marketing_blog_topic_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_calendar_resend_decision ADD CONSTRAINT marketing_calendar_resend_decision_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_campaign ADD CONSTRAINT marketing_campaign_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_connection_check ADD CONSTRAINT marketing_connection_check_pkey PRIMARY KEY (check_key);
ALTER TABLE public.marketing_duty_run ADD CONSTRAINT marketing_duty_run_pkey PRIMARY KEY (duty);
ALTER TABLE public.marketing_first_touch ADD CONSTRAINT marketing_first_touch_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_founder_request ADD CONSTRAINT marketing_founder_request_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_gap_recruitment_plan ADD CONSTRAINT marketing_gap_recruitment_plan_pkey PRIMARY KEY (trade, emirate);
ALTER TABLE public.marketing_geo_check ADD CONSTRAINT marketing_geo_check_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_geo_question ADD CONSTRAINT marketing_geo_question_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_goal ADD CONSTRAINT marketing_goal_pkey PRIMARY KEY (month, platform, metric);
ALTER TABLE public.marketing_insight_day ADD CONSTRAINT marketing_insight_day_pkey PRIMARY KEY (platform, object_id, metric, day);
ALTER TABLE public.marketing_insight_note ADD CONSTRAINT marketing_insight_note_pkey PRIMARY KEY (week_start);
ALTER TABLE public.marketing_knowledge ADD CONSTRAINT marketing_knowledge_pkey PRIMARY KEY (record_id);
ALTER TABLE public.marketing_library ADD CONSTRAINT marketing_library_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_meta_page ADD CONSTRAINT marketing_meta_page_pkey PRIMARY KEY (page_id);
ALTER TABLE public.marketing_model_run ADD CONSTRAINT marketing_model_run_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_month_plan ADD CONSTRAINT marketing_month_plan_pkey PRIMARY KEY (month);
ALTER TABLE public.marketing_outreach_message ADD CONSTRAINT marketing_outreach_message_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_plan_doc ADD CONSTRAINT marketing_plan_doc_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_plan_review_turn ADD CONSTRAINT marketing_plan_review_turn_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_platform_spec ADD CONSTRAINT marketing_platform_spec_pkey PRIMARY KEY (platform, surface, attribute);
ALTER TABLE public.marketing_platform_spec_source ADD CONSTRAINT marketing_platform_spec_source_pkey PRIMARY KEY (source_url);
ALTER TABLE public.marketing_post ADD CONSTRAINT marketing_post_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_post_channel_result ADD CONSTRAINT marketing_post_channel_result_pkey PRIMARY KEY (post_id, channel);
ALTER TABLE public.marketing_post_metric ADD CONSTRAINT marketing_post_metric_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_post_platform ADD CONSTRAINT marketing_post_platform_pkey PRIMARY KEY (post_id, platform);
ALTER TABLE public.marketing_post_variant ADD CONSTRAINT marketing_post_variant_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_prospect ADD CONSTRAINT marketing_prospect_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_recruitment_source ADD CONSTRAINT marketing_recruitment_source_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_report ADD CONSTRAINT marketing_report_pkey PRIMARY KEY (report_date);
ALTER TABLE public.marketing_review ADD CONSTRAINT marketing_review_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_scorecard_report ADD CONSTRAINT marketing_scorecard_report_pkey PRIMARY KEY (period_key);
ALTER TABLE public.marketing_snapshots ADD CONSTRAINT marketing_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_trend ADD CONSTRAINT marketing_trend_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_trend_source ADD CONSTRAINT marketing_trend_source_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_video_idea ADD CONSTRAINT marketing_video_idea_pkey PRIMARY KEY (id);
ALTER TABLE public.match_eval_runs ADD CONSTRAINT match_eval_runs_pkey PRIMARY KEY (id);
ALTER TABLE public.materials ADD CONSTRAINT materials_pkey PRIMARY KEY (id);
ALTER TABLE public.mdm_brands ADD CONSTRAINT mdm_brands_pkey PRIMARY KEY (id);
ALTER TABLE public.mdm_manufacturers ADD CONSTRAINT mdm_manufacturers_pkey PRIMARY KEY (id);
ALTER TABLE public.mdm_standards ADD CONSTRAINT mdm_standards_pkey PRIMARY KEY (id);
ALTER TABLE public.mep_evidence_weight ADD CONSTRAINT mep_evidence_weight_pkey PRIMARY KEY (weight_key);
ALTER TABLE public.mep_trade ADD CONSTRAINT mep_trade_pkey PRIMARY KEY (trade_key);
ALTER TABLE public.messages ADD CONSTRAINT messages_pkey PRIMARY KEY (id);
ALTER TABLE public.messaging_template ADD CONSTRAINT messaging_template_pkey PRIMARY KEY (sid);
ALTER TABLE public.meta_insights ADD CONSTRAINT meta_insights_pkey PRIMARY KEY (id);
ALTER TABLE public.metric_definition ADD CONSTRAINT metric_definition_pkey PRIMARY KEY (metric_key);
ALTER TABLE public.metric_snapshot ADD CONSTRAINT metric_snapshot_pkey PRIMARY KEY (id);
ALTER TABLE public.model_catalogue_change ADD CONSTRAINT model_catalogue_change_pkey PRIMARY KEY (id);
ALTER TABLE public.model_fallback_chain ADD CONSTRAINT model_fallback_chain_pkey PRIMARY KEY (purpose, rung);
ALTER TABLE public.model_policy ADD CONSTRAINT model_policy_pkey PRIMARY KEY (task_class);
ALTER TABLE public.model_policy_by_identity ADD CONSTRAINT model_policy_by_identity_pkey PRIMARY KEY (identity_key, scope);
ALTER TABLE public.model_rate ADD CONSTRAINT model_rate_pkey PRIMARY KEY (model);
ALTER TABLE public.model_registry ADD CONSTRAINT model_registry_pkey PRIMARY KEY (model_id);
ALTER TABLE public.money_move_hold ADD CONSTRAINT money_move_hold_pkey PRIMARY KEY (id);
ALTER TABLE public.notice_plain_language ADD CONSTRAINT notice_plain_language_pkey PRIMARY KEY (notification_id);
ALTER TABLE public.notice_plain_language_cause ADD CONSTRAINT notice_plain_language_cause_pkey PRIMARY KEY (id);
ALTER TABLE public.notification_copy ADD CONSTRAINT notification_copy_pkey PRIMARY KEY (type);
ALTER TABLE public.notification_type_severity ADD CONSTRAINT notification_type_severity_pkey PRIMARY KEY (type);
ALTER TABLE public.notifications ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);
ALTER TABLE public.openrouter_day ADD CONSTRAINT openrouter_day_pkey PRIMARY KEY (day);
ALTER TABLE public.openrouter_meter ADD CONSTRAINT openrouter_meter_pkey PRIMARY KEY (id);
ALTER TABLE public.operating_system ADD CONSTRAINT operating_system_pkey PRIMARY KEY (os_key);
ALTER TABLE public.opportunity ADD CONSTRAINT opportunity_pkey PRIMARY KEY (id);
ALTER TABLE public.ops_knowledge ADD CONSTRAINT ops_knowledge_pkey PRIMARY KEY (record_id);
ALTER TABLE public.ops_kpi_snapshots ADD CONSTRAINT ops_kpi_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.org_action_executor ADD CONSTRAINT org_action_executor_pkey PRIMARY KEY (action_class);
ALTER TABLE public.org_agent_alias ADD CONSTRAINT org_agent_alias_pkey PRIMARY KEY (alias);
ALTER TABLE public.org_agents ADD CONSTRAINT org_agents_pkey PRIMARY KEY (agent_key);
ALTER TABLE public.org_authority ADD CONSTRAINT org_authority_pkey PRIMARY KEY (dept_key, action_class);
ALTER TABLE public.org_category_identity ADD CONSTRAINT org_category_identity_pkey PRIMARY KEY (category_key);
ALTER TABLE public.org_committee ADD CONSTRAINT org_committee_pkey PRIMARY KEY (committee_key);
ALTER TABLE public.org_departments ADD CONSTRAINT org_departments_pkey PRIMARY KEY (dept_key);
ALTER TABLE public.org_memory ADD CONSTRAINT org_memory_pkey PRIMARY KEY (id);
ALTER TABLE public.org_objectives ADD CONSTRAINT org_objectives_pkey PRIMARY KEY (id);
ALTER TABLE public.org_onboarding ADD CONSTRAINT org_onboarding_pkey PRIMARY KEY (agent_key);
ALTER TABLE public.org_phase_baseline ADD CONSTRAINT org_phase_baseline_pkey PRIMARY KEY (phase);
ALTER TABLE public.org_reporting_edge ADD CONSTRAINT org_reporting_edge_pkey PRIMARY KEY (child_role_id);
ALTER TABLE public.org_role ADD CONSTRAINT org_role_pkey PRIMARY KEY (role_id);
ALTER TABLE public.org_role_alias ADD CONSTRAINT org_role_alias_pkey PRIMARY KEY (alias);
ALTER TABLE public.org_role_committee ADD CONSTRAINT org_role_committee_pkey PRIMARY KEY (role_id, committee_key);
ALTER TABLE public.org_role_identity ADD CONSTRAINT org_role_identity_pkey PRIMARY KEY (agent_key, packaged_role_id);
ALTER TABLE public.org_task_question_reading ADD CONSTRAINT org_task_question_reading_pkey PRIMARY KEY (task_id);
ALTER TABLE public.org_tasks ADD CONSTRAINT org_tasks_pkey PRIMARY KEY (id);
ALTER TABLE public.org_workflow_ownership ADD CONSTRAINT org_workflow_ownership_pkey PRIMARY KEY (workflow_id);
ALTER TABLE public.org_workflow_step ADD CONSTRAINT org_workflow_step_pkey PRIMARY KEY (workflow_id, step_no);
ALTER TABLE public.os_audit_log ADD CONSTRAINT os_audit_log_pkey PRIMARY KEY (id);
ALTER TABLE public.os_department ADD CONSTRAINT os_department_pkey PRIMARY KEY (os_key, dept_key);
ALTER TABLE public.os_fresh_start ADD CONSTRAINT os_fresh_start_pkey PRIMARY KEY (id);
ALTER TABLE public.os_incidents ADD CONSTRAINT os_incidents_pkey PRIMARY KEY (id);
ALTER TABLE public.os_interface ADD CONSTRAINT os_interface_pkey PRIMARY KEY (id);
ALTER TABLE public.os_knowledge_domain ADD CONSTRAINT os_knowledge_domain_pkey PRIMARY KEY (os_key, domain_key);
ALTER TABLE public.os_objective ADD CONSTRAINT os_objective_pkey PRIMARY KEY (id);
ALTER TABLE public.os_open_access_log ADD CONSTRAINT os_open_access_log_pkey PRIMARY KEY (id);
ALTER TABLE public.os_responsibility ADD CONSTRAINT os_responsibility_pkey PRIMARY KEY (responsibility);
ALTER TABLE public.os_review ADD CONSTRAINT os_review_pkey PRIMARY KEY (id);
ALTER TABLE public.os_runbooks ADD CONSTRAINT os_runbooks_pkey PRIMARY KEY (slug);
ALTER TABLE public.os_settings_meta ADD CONSTRAINT os_settings_meta_pkey PRIMARY KEY (key);
ALTER TABLE public.otp_blocked_prefix ADD CONSTRAINT otp_blocked_prefix_pkey PRIMARY KEY (prefix);
ALTER TABLE public.otp_prefix_allowed ADD CONSTRAINT otp_prefix_allowed_pkey PRIMARY KEY (prefix);
ALTER TABLE public.otp_served_country ADD CONSTRAINT otp_served_country_pkey PRIMARY KEY (prefix);
ALTER TABLE public.outcome_record ADD CONSTRAINT outcome_record_pkey PRIMARY KEY (id);
ALTER TABLE public.outreach ADD CONSTRAINT outreach_pkey PRIMARY KEY (id);
ALTER TABLE public.outreach_channel_policy ADD CONSTRAINT outreach_channel_policy_pkey PRIMARY KEY (channel_key);
ALTER TABLE public.pages ADD CONSTRAINT pages_pkey PRIMARY KEY (slug);
ALTER TABLE public.paid_route_exception ADD CONSTRAINT paid_route_exception_pkey PRIMARY KEY (route);
ALTER TABLE public.pdpl_erase_files ADD CONSTRAINT pdpl_erase_files_pkey PRIMARY KEY (id);
ALTER TABLE public.pdpl_lead_erase_vault ADD CONSTRAINT pdpl_lead_erase_vault_pkey PRIMARY KEY (request_id, lead_id);
ALTER TABLE public.pdpl_operator_log ADD CONSTRAINT pdpl_operator_log_pkey PRIMARY KEY (id);
ALTER TABLE public.pdpl_requests ADD CONSTRAINT pdpl_requests_pkey PRIMARY KEY (id);
ALTER TABLE public.phase1_rollback_log ADD CONSTRAINT phase1_rollback_log_pkey PRIMARY KEY (id);
ALTER TABLE public.phone_code ADD CONSTRAINT phone_code_pkey PRIMARY KEY (id);
ALTER TABLE public.phone_verifications ADD CONSTRAINT phone_verifications_pkey PRIMARY KEY (id);
ALTER TABLE public.po_lines ADD CONSTRAINT po_lines_pkey PRIMARY KEY (id);
ALTER TABLE public.po_orders ADD CONSTRAINT po_orders_pkey PRIMARY KEY (id);
ALTER TABLE public.po_vendors ADD CONSTRAINT po_vendors_pkey PRIMARY KEY (id);
ALTER TABLE public.policy_rules ADD CONSTRAINT policy_rules_pkey PRIMARY KEY (id);
ALTER TABLE public.post_reveal_dispute ADD CONSTRAINT post_reveal_dispute_pkey PRIMARY KEY (id);
ALTER TABLE public.price_benchmark ADD CONSTRAINT price_benchmark_pkey PRIMARY KEY (id);
ALTER TABLE public.price_trade_term ADD CONSTRAINT price_trade_term_pkey PRIMARY KEY (term);
ALTER TABLE public.pricing_config ADD CONSTRAINT pricing_config_pkey PRIMARY KEY (id);
ALTER TABLE public.projects ADD CONSTRAINT projects_pkey PRIMARY KEY (id);
ALTER TABLE public.prompt_benchmarks ADD CONSTRAINT prompt_benchmarks_pkey PRIMARY KEY (id);
ALTER TABLE public.prompt_eval_runs ADD CONSTRAINT prompt_eval_runs_pkey PRIMARY KEY (id);
ALTER TABLE public.prompt_versions ADD CONSTRAINT prompt_versions_pkey PRIMARY KEY (id);
ALTER TABLE public.prompts ADD CONSTRAINT prompts_pkey PRIMARY KEY (key);
ALTER TABLE public.public_holidays ADD CONSTRAINT public_holidays_pkey PRIMARY KEY (holiday_date);
ALTER TABLE public.qa_results ADD CONSTRAINT qa_results_pkey PRIMARY KEY (id);
ALTER TABLE public.qd_compare_cache ADD CONSTRAINT qd_compare_cache_pkey PRIMARY KEY (inquiry_id, quotes_hash, lang);
ALTER TABLE public.qd_deploy_src ADD CONSTRAINT qd_deploy_src_pkey PRIMARY KEY (path);
ALTER TABLE public.qd_i18n ADD CONSTRAINT qd_i18n_pkey PRIMARY KEY (source, slug);
ALTER TABLE public.qd_i18n_chunks ADD CONSTRAINT qd_i18n_chunks_pkey PRIMARY KEY (source, slug, idx);
ALTER TABLE public.qualification_playbooks ADD CONSTRAINT qualification_playbooks_pkey PRIMARY KEY (id);
ALTER TABLE public.quality_standard ADD CONSTRAINT quality_standard_pkey PRIMARY KEY (work_type);
ALTER TABLE public.questions ADD CONSTRAINT questions_pkey PRIMARY KEY (id);
ALTER TABLE public.quote_aspect_reading ADD CONSTRAINT quote_aspect_reading_pkey PRIMARY KEY (quote_id);
ALTER TABLE public.quote_committed_items ADD CONSTRAINT quote_committed_items_pkey PRIMARY KEY (id);
ALTER TABLE public.quote_comparisons ADD CONSTRAINT quote_comparisons_pkey PRIMARY KEY (id);
ALTER TABLE public.quote_extraction_model ADD CONSTRAINT quote_extraction_model_pkey PRIMARY KEY (subject_key);
ALTER TABLE public.quote_items ADD CONSTRAINT quote_items_pkey PRIMARY KEY (id);
ALTER TABLE public.quote_pdf_cache ADD CONSTRAINT quote_pdf_cache_pkey PRIMARY KEY (quote_id, lang);
ALTER TABLE public.quote_quality_hold ADD CONSTRAINT quote_quality_hold_pkey PRIMARY KEY (quote_id);
ALTER TABLE public.quote_requirements ADD CONSTRAINT quote_requirements_pkey PRIMARY KEY (category);
ALTER TABLE public.quote_review_messages ADD CONSTRAINT quote_review_messages_pkey PRIMARY KEY (id);
ALTER TABLE public.quote_review_request ADD CONSTRAINT quote_review_request_pkey PRIMARY KEY (id);
ALTER TABLE public.quote_reviews ADD CONSTRAINT quote_reviews_pkey PRIMARY KEY (id);
ALTER TABLE public.quote_spec_hold ADD CONSTRAINT quote_spec_hold_pkey PRIMARY KEY (id);
ALTER TABLE public.quotes ADD CONSTRAINT quotes_pkey PRIMARY KEY (id);
ALTER TABLE public.reasoning_held_question ADD CONSTRAINT reasoning_held_question_pkey PRIMARY KEY (id);
ALTER TABLE public.reasoning_knowledge_candidate ADD CONSTRAINT reasoning_knowledge_candidate_pkey PRIMARY KEY (id);
ALTER TABLE public.red_episode ADD CONSTRAINT red_episode_pkey PRIMARY KEY (id);
ALTER TABLE public.refund_case ADD CONSTRAINT refund_case_pkey PRIMARY KEY (refund_id);
ALTER TABLE public.refund_ceo_check ADD CONSTRAINT refund_ceo_check_pkey PRIMARY KEY (id);
ALTER TABLE public.refund_ceo_review ADD CONSTRAINT refund_ceo_review_pkey PRIMARY KEY (id);
ALTER TABLE public.refund_event_quarantine ADD CONSTRAINT refund_event_quarantine_pkey PRIMARY KEY (id);
ALTER TABLE public.refund_incident ADD CONSTRAINT refund_incident_pkey PRIMARY KEY (id);
ALTER TABLE public.refund_ladder_evidence ADD CONSTRAINT refund_ladder_evidence_pkey PRIMARY KEY (id);
ALTER TABLE public.refund_status_transition ADD CONSTRAINT refund_status_transition_pkey PRIMARY KEY (from_status, to_status);
ALTER TABLE public.refunds ADD CONSTRAINT refunds_pkey PRIMARY KEY (id);
ALTER TABLE public.reg_catalog ADD CONSTRAINT reg_catalog_pkey PRIMARY KEY (id);
ALTER TABLE public.regulations ADD CONSTRAINT regulations_pkey PRIMARY KEY (id);
ALTER TABLE public.rehearsal_spend_reservation ADD CONSTRAINT rehearsal_spend_reservation_pkey PRIMARY KEY (id);
ALTER TABLE public.rehearsal_window ADD CONSTRAINT rehearsal_window_pkey PRIMARY KEY (id);
ALTER TABLE public.removed_trigger_log ADD CONSTRAINT removed_trigger_log_pkey PRIMARY KEY (id);
ALTER TABLE public.resilience_step ADD CONSTRAINT resilience_step_pkey PRIMARY KEY (step);
ALTER TABLE public.resource_pool ADD CONSTRAINT resource_pool_pkey PRIMARY KEY (id);
ALTER TABLE public.response_template ADD CONSTRAINT response_template_pkey PRIMARY KEY (key);
ALTER TABLE public.retention_policy ADD CONSTRAINT retention_policy_pkey PRIMARY KEY (bucket);
ALTER TABLE public.reveal_invoices ADD CONSTRAINT reveal_invoices_pkey PRIMARY KEY (transaction_id);
ALTER TABLE public.review_chain ADD CONSTRAINT review_chain_pkey PRIMARY KEY (id);
ALTER TABLE public.review_hold ADD CONSTRAINT review_hold_pkey PRIMARY KEY (id);
ALTER TABLE public.review_pool ADD CONSTRAINT review_pool_pkey PRIMARY KEY (model_id);
ALTER TABLE public.review_queue ADD CONSTRAINT review_queue_pkey PRIMARY KEY (id);
ALTER TABLE public.review_route ADD CONSTRAINT review_route_pkey PRIMARY KEY (decision_type);
ALTER TABLE public.reviews ADD CONSTRAINT reviews_pkey PRIMARY KEY (id);
ALTER TABLE public.rfq_archives ADD CONSTRAINT rfq_archives_pkey PRIMARY KEY (id);
ALTER TABLE public.rfq_clarification ADD CONSTRAINT rfq_clarification_pkey PRIMARY KEY (id);
ALTER TABLE public.risk_register ADD CONSTRAINT risk_register_pkey PRIMARY KEY (id);
ALTER TABLE public.rl_hits ADD CONSTRAINT rl_hits_pkey PRIMARY KEY (_pk);
ALTER TABLE public.roles ADD CONSTRAINT roles_pkey PRIMARY KEY (name);
ALTER TABLE public.routine_change_log ADD CONSTRAINT routine_change_log_pkey PRIMARY KEY (id);
ALTER TABLE public.routine_judgement ADD CONSTRAINT routine_judgement_pkey PRIMARY KEY (id);
ALTER TABLE public.sales_decision_log ADD CONSTRAINT sales_decision_log_pkey PRIMARY KEY (id);
ALTER TABLE public.sales_engineer_comparison_report ADD CONSTRAINT sales_engineer_comparison_report_pkey PRIMARY KEY (inquiry_id);
ALTER TABLE public.sales_engineer_framework_proposal ADD CONSTRAINT sales_engineer_framework_proposal_pkey PRIMARY KEY (id);
ALTER TABLE public.sales_engineer_negotiation_round ADD CONSTRAINT sales_engineer_negotiation_round_pkey PRIMARY KEY (id);
ALTER TABLE public.sales_engineer_onboarding_week ADD CONSTRAINT sales_engineer_onboarding_week_pkey PRIMARY KEY (week);
ALTER TABLE public.sales_engineer_win_loss_month ADD CONSTRAINT sales_engineer_win_loss_month_pkey PRIMARY KEY (month);
ALTER TABLE public.sales_knowledge ADD CONSTRAINT sales_knowledge_pkey PRIMARY KEY (record_id);
ALTER TABLE public.sales_knowledge_gap ADD CONSTRAINT sales_knowledge_gap_pkey PRIMARY KEY (id);
ALTER TABLE public.sales_qualification_field ADD CONSTRAINT sales_qualification_field_pkey PRIMARY KEY (field_key);
ALTER TABLE public.sales_sector ADD CONSTRAINT sales_sector_pkey PRIMARY KEY (sector_id);
ALTER TABLE public.sanctions_ban ADD CONSTRAINT sanctions_ban_pkey PRIMARY KEY (id);
ALTER TABLE public.scenario_library ADD CONSTRAINT scenario_library_pkey PRIMARY KEY (scenario_key);
ALTER TABLE public.scope_component ADD CONSTRAINT scope_component_pkey PRIMARY KEY (component);
ALTER TABLE public.scope_disposition_kind ADD CONSTRAINT scope_disposition_kind_pkey PRIMARY KEY (disposition);
ALTER TABLE public.scrape_runs ADD CONSTRAINT scrape_runs_pkey PRIMARY KEY (id);
ALTER TABLE public.screening_entry ADD CONSTRAINT screening_entry_pkey PRIMARY KEY (id);
ALTER TABLE public.screening_run ADD CONSTRAINT screening_run_pkey PRIMARY KEY (id);
ALTER TABLE public.seat_case_memory ADD CONSTRAINT seat_case_memory_pkey PRIMARY KEY (id);
ALTER TABLE public.seat_case_memory_miss ADD CONSTRAINT seat_case_memory_miss_pkey PRIMARY KEY (id);
ALTER TABLE public.seat_deliberation ADD CONSTRAINT seat_deliberation_pkey PRIMARY KEY (id);
ALTER TABLE public.seat_deliberation_ceiling ADD CONSTRAINT seat_deliberation_ceiling_pkey PRIMARY KEY (author_seat, reviewer_seat);
ALTER TABLE public.seat_deliberation_turn ADD CONSTRAINT seat_deliberation_turn_pkey PRIMARY KEY (id);
ALTER TABLE public.seat_duty ADD CONSTRAINT seat_duty_pkey PRIMARY KEY (duty);
ALTER TABLE public.seat_duty_skip ADD CONSTRAINT seat_duty_skip_pkey PRIMARY KEY (duty);
ALTER TABLE public.seat_exam_asked ADD CONSTRAINT seat_exam_asked_pkey PRIMARY KEY (id);
ALTER TABLE public.seat_exam_fix ADD CONSTRAINT seat_exam_fix_pkey PRIMARY KEY (id);
ALTER TABLE public.seat_exam_item ADD CONSTRAINT seat_exam_item_pkey PRIMARY KEY (seat, item_id);
ALTER TABLE public.seat_handoff_kind ADD CONSTRAINT seat_handoff_kind_pkey PRIMARY KEY (type, from_seat, to_seat);
ALTER TABLE public.seat_judgement ADD CONSTRAINT seat_judgement_pkey PRIMARY KEY (id);
ALTER TABLE public.seat_knowledge_eval_question ADD CONSTRAINT seat_knowledge_eval_question_pkey PRIMARY KEY (id);
ALTER TABLE public.seat_knowledge_exam ADD CONSTRAINT seat_knowledge_exam_pkey PRIMARY KEY (id);
ALTER TABLE public.seat_knowledge_recall ADD CONSTRAINT seat_knowledge_recall_pkey PRIMARY KEY (day, seat);
ALTER TABLE public.seat_knowledge_recall_answer ADD CONSTRAINT seat_knowledge_recall_answer_pkey PRIMARY KEY (day, question_id);
ALTER TABLE public.seat_knowledge_recall_floor ADD CONSTRAINT seat_knowledge_recall_floor_pkey PRIMARY KEY (seat, lang);
ALTER TABLE public.seat_knowledge_refresh ADD CONSTRAINT seat_knowledge_refresh_pkey PRIMARY KEY (seat, quarter);
ALTER TABLE public.seat_knowledge_stale ADD CONSTRAINT seat_knowledge_stale_pkey PRIMARY KEY (quarter, item_key);
ALTER TABLE public.seat_learning_daily ADD CONSTRAINT seat_learning_daily_pkey PRIMARY KEY (seat, day);
ALTER TABLE public.seat_lesson_cluster ADD CONSTRAINT seat_lesson_cluster_pkey PRIMARY KEY (cluster_key);
ALTER TABLE public.seat_playbook ADD CONSTRAINT seat_playbook_pkey PRIMARY KEY (seat);
ALTER TABLE public.seat_self_review ADD CONSTRAINT seat_self_review_pkey PRIMARY KEY (month, seat);
ALTER TABLE public.seat_senior_contribution ADD CONSTRAINT seat_senior_contribution_pkey PRIMARY KEY (seat, contribution_id);
ALTER TABLE public.seat_senior_exam ADD CONSTRAINT seat_senior_exam_pkey PRIMARY KEY (seat, judged_on);
ALTER TABLE public.seat_senior_verdict ADD CONSTRAINT seat_senior_verdict_pkey PRIMARY KEY (week, seat);
ALTER TABLE public.security_advisor_baseline ADD CONSTRAINT security_advisor_baseline_pkey PRIMARY KEY (cache_key);
ALTER TABLE public.security_audit_log ADD CONSTRAINT security_audit_log_pkey PRIMARY KEY (id);
ALTER TABLE public.security_events ADD CONSTRAINT security_events_pkey PRIMARY KEY (id);
ALTER TABLE public.security_gap ADD CONSTRAINT security_gap_pkey PRIMARY KEY (name);
ALTER TABLE public.security_kpi_snapshots ADD CONSTRAINT security_kpi_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.self_review ADD CONSTRAINT self_review_pkey PRIMARY KEY (id);
ALTER TABLE public.seo_categories ADD CONSTRAINT seo_categories_pkey PRIMARY KEY (slug);
ALTER TABLE public.service_implication ADD CONSTRAINT service_implication_pkey PRIMARY KEY (from_code, implies_trade, implies_code);
ALTER TABLE public.signup_purge ADD CONSTRAINT signup_purge_pkey PRIMARY KEY (id);
ALTER TABLE public.signup_purge_dropbox ADD CONSTRAINT signup_purge_dropbox_pkey PRIMARY KEY (id);
ALTER TABLE public.signup_purge_object ADD CONSTRAINT signup_purge_object_pkey PRIMARY KEY (id);
ALTER TABLE public.simulations ADD CONSTRAINT simulations_pkey PRIMARY KEY (id);
ALTER TABLE public.skills_matrix ADD CONSTRAINT skills_matrix_pkey PRIMARY KEY (agent_key, skill);
ALTER TABLE public.sms_messages ADD CONSTRAINT sms_messages_pkey PRIMARY KEY (id);
ALTER TABLE public.social_connect_link ADD CONSTRAINT social_connect_link_pkey PRIMARY KEY (id);
ALTER TABLE public.social_conversation ADD CONSTRAINT social_conversation_pkey PRIMARY KEY (id);
ALTER TABLE public.social_message ADD CONSTRAINT social_message_pkey PRIMARY KEY (id);
ALTER TABLE public.social_posts ADD CONSTRAINT social_posts_pkey PRIMARY KEY (id);
ALTER TABLE public.social_reply_library ADD CONSTRAINT social_reply_library_pkey PRIMARY KEY (key);
ALTER TABLE public.spec_alternative_offer ADD CONSTRAINT spec_alternative_offer_pkey PRIMARY KEY (id);
ALTER TABLE public.spec_backlog ADD CONSTRAINT spec_backlog_pkey PRIMARY KEY (id);
ALTER TABLE public.stalled_inquiry_rescue ADD CONSTRAINT stalled_inquiry_rescue_pkey PRIMARY KEY (inquiry_id);
ALTER TABLE public.strategy_risks ADD CONSTRAINT strategy_risks_pkey PRIMARY KEY (id);
ALTER TABLE public.stripe_dispute ADD CONSTRAINT stripe_dispute_pkey PRIMARY KEY (id);
ALTER TABLE public.stripe_events ADD CONSTRAINT stripe_events_pkey PRIMARY KEY (event_id);
ALTER TABLE public.stripe_payout ADD CONSTRAINT stripe_payout_pkey PRIMARY KEY (id);
ALTER TABLE public.stripe_setting_reading ADD CONSTRAINT stripe_setting_reading_pkey PRIMARY KEY (id);
ALTER TABLE public.subcategory_agent_map ADD CONSTRAINT subcategory_agent_map_pkey PRIMARY KEY (sub_slug);
ALTER TABLE public.supplier_availability ADD CONSTRAINT supplier_availability_pkey PRIMARY KEY (supplier_id);
ALTER TABLE public.supplier_beneficial_owner ADD CONSTRAINT supplier_beneficial_owner_pkey PRIMARY KEY (id);
ALTER TABLE public.supplier_campaign_daily_list ADD CONSTRAINT supplier_campaign_daily_list_pkey PRIMARY KEY (id);
ALTER TABLE public.supplier_capabilities ADD CONSTRAINT supplier_capabilities_pkey PRIMARY KEY (supplier_id);
ALTER TABLE public.supplier_capability_confirmation ADD CONSTRAINT supplier_capability_confirmation_pkey PRIMARY KEY (id);
ALTER TABLE public.supplier_capability_reading ADD CONSTRAINT supplier_capability_reading_pkey PRIMARY KEY (lead_id);
ALTER TABLE public.supplier_catalog ADD CONSTRAINT supplier_catalog_pkey PRIMARY KEY (id);
ALTER TABLE public.supplier_collaboration ADD CONSTRAINT supplier_collaboration_pkey PRIMARY KEY (lead_id);
ALTER TABLE public.supplier_collaboration_event ADD CONSTRAINT supplier_collaboration_event_pkey PRIMARY KEY (id);
ALTER TABLE public.supplier_document_cache ADD CONSTRAINT supplier_document_cache_pkey PRIMARY KEY (kind, subject_id, supplier_id, lang);
ALTER TABLE public.supplier_due_checkouts ADD CONSTRAINT supplier_due_checkouts_pkey PRIMARY KEY (session_id, due_id);
ALTER TABLE public.supplier_due_payments ADD CONSTRAINT supplier_due_payments_pkey PRIMARY KEY (id);
ALTER TABLE public.supplier_dues ADD CONSTRAINT supplier_dues_pkey PRIMARY KEY (id);
ALTER TABLE public.supplier_kpi_snapshots ADD CONSTRAINT supplier_kpi_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.supplier_lead_intake ADD CONSTRAINT supplier_lead_intake_pkey PRIMARY KEY (inbound_id);
ALTER TABLE public.supplier_onboarding ADD CONSTRAINT supplier_onboarding_pkey PRIMARY KEY (lead_id);
ALTER TABLE public.supplier_opportunity_score ADD CONSTRAINT supplier_opportunity_score_pkey PRIMARY KEY (supplier_id, inquiry_id);
ALTER TABLE public.supplier_own_word_reading ADD CONSTRAINT supplier_own_word_reading_pkey PRIMARY KEY (supplier_id, word);
ALTER TABLE public.supplier_performance ADD CONSTRAINT supplier_performance_pkey PRIMARY KEY (lead_id);
ALTER TABLE public.supplier_product ADD CONSTRAINT supplier_product_pkey PRIMARY KEY (id);
ALTER TABLE public.supplier_product_variant ADD CONSTRAINT supplier_product_variant_pkey PRIMARY KEY (id);
ALTER TABLE public.supplier_public_name ADD CONSTRAINT supplier_public_name_pkey PRIMARY KEY (lead_id);
ALTER TABLE public.supplier_quote_template ADD CONSTRAINT supplier_quote_template_pkey PRIMARY KEY (id);
ALTER TABLE public.supplier_recruitment_funnel ADD CONSTRAINT supplier_recruitment_funnel_pkey PRIMARY KEY (trade, emirate, day);
ALTER TABLE public.supplier_reply_followup ADD CONSTRAINT supplier_reply_followup_pkey PRIMARY KEY (id);
ALTER TABLE public.supplier_response_watch ADD CONSTRAINT supplier_response_watch_pkey PRIMARY KEY (id);
ALTER TABLE public.supplier_score ADD CONSTRAINT supplier_score_pkey PRIMARY KEY (lead_id);
ALTER TABLE public.supplier_scorecard ADD CONSTRAINT supplier_scorecard_pkey PRIMARY KEY (lead_id, month);
ALTER TABLE public.supplier_screening_hit ADD CONSTRAINT supplier_screening_hit_pkey PRIMARY KEY (id);
ALTER TABLE public.supplier_voice_note ADD CONSTRAINT supplier_voice_note_pkey PRIMARY KEY (id);
ALTER TABLE public.supplier_whatsapp_consent_ask ADD CONSTRAINT supplier_whatsapp_consent_ask_pkey PRIMARY KEY (id);
ALTER TABLE public.supplier_whatsapp_optin ADD CONSTRAINT supplier_whatsapp_optin_pkey PRIMARY KEY (id);
ALTER TABLE public.supply_gap ADD CONSTRAINT supply_gap_pkey PRIMARY KEY (trade, emirate);
ALTER TABLE public.supply_health_snapshots ADD CONSTRAINT supply_health_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.supply_recruitment_brief ADD CONSTRAINT supply_recruitment_brief_pkey PRIMARY KEY (id);
ALTER TABLE public.support_artifact ADD CONSTRAINT support_artifact_pkey PRIMARY KEY (artifact_id);
ALTER TABLE public.support_case ADD CONSTRAINT support_case_pkey PRIMARY KEY (case_id);
ALTER TABLE public.support_category ADD CONSTRAINT support_category_pkey PRIMARY KEY (category);
ALTER TABLE public.support_cause_week ADD CONSTRAINT support_cause_week_pkey PRIMARY KEY (week_ending, cause_key, fixture);
ALTER TABLE public.support_ceo_report ADD CONSTRAINT support_ceo_report_pkey PRIMARY KEY (id);
ALTER TABLE public.support_customer_profile ADD CONSTRAINT support_customer_profile_pkey PRIMARY KEY (id);
ALTER TABLE public.support_document_intake ADD CONSTRAINT support_document_intake_pkey PRIMARY KEY (intake_id);
ALTER TABLE public.support_identity_challenge ADD CONSTRAINT support_identity_challenge_pkey PRIMARY KEY (challenge_id);
ALTER TABLE public.support_knowledge ADD CONSTRAINT support_knowledge_pkey PRIMARY KEY (record_id);
ALTER TABLE public.support_notification ADD CONSTRAINT support_notification_pkey PRIMARY KEY (id);
ALTER TABLE public.support_public_override ADD CONSTRAINT support_public_override_pkey PRIMARY KEY (src, src_id);
ALTER TABLE public.support_reply_readability ADD CONSTRAINT support_reply_readability_pkey PRIMARY KEY (id);
ALTER TABLE public.support_root_cause ADD CONSTRAINT support_root_cause_pkey PRIMARY KEY (id);
ALTER TABLE public.support_root_cause_fix ADD CONSTRAINT support_root_cause_fix_pkey PRIMARY KEY (id);
ALTER TABLE public.support_signal_category ADD CONSTRAINT support_signal_category_pkey PRIMARY KEY (source, value);
ALTER TABLE public.table_export_change ADD CONSTRAINT table_export_change_pkey PRIMARY KEY (id);
ALTER TABLE public.table_export_change_tracked ADD CONSTRAINT table_export_change_tracked_pkey PRIMARY KEY (table_name);
ALTER TABLE public.table_export_registry ADD CONSTRAINT table_export_registry_pkey PRIMARY KEY (table_name);
ALTER TABLE public.table_export_run ADD CONSTRAINT table_export_run_pkey PRIMARY KEY (stamp);
ALTER TABLE public.target_contract ADD CONSTRAINT target_contract_pkey PRIMARY KEY (id);
ALTER TABLE public.target_daily_verdict ADD CONSTRAINT target_daily_verdict_pkey PRIMARY KEY (day, contract_id, metric_key);
ALTER TABLE public.target_driver ADD CONSTRAINT target_driver_pkey PRIMARY KEY (id);
ALTER TABLE public.target_label ADD CONSTRAINT target_label_pkey PRIMARY KEY (target_key);
ALTER TABLE public.target_path ADD CONSTRAINT target_path_pkey PRIMARY KEY (contract_id, month, metric_key);
ALTER TABLE public.target_verdict ADD CONSTRAINT target_verdict_pkey PRIMARY KEY (id);
ALTER TABLE public.taxonomy_role ADD CONSTRAINT taxonomy_role_pkey PRIMARY KEY (code);
ALTER TABLE public.taxonomy_trade ADD CONSTRAINT taxonomy_trade_pkey PRIMARY KEY (code);
ALTER TABLE public.taxonomy_trade_code ADD CONSTRAINT taxonomy_trade_code_pkey PRIMARY KEY (trade_code, scheme, code);
ALTER TABLE public.taxonomy_trade_group ADD CONSTRAINT taxonomy_trade_group_pkey PRIMARY KEY (code);
ALTER TABLE public.taxonomy_trade_proposal ADD CONSTRAINT taxonomy_trade_proposal_pkey PRIMARY KEY (id);
ALTER TABLE public.taxonomy_trade_service ADD CONSTRAINT taxonomy_trade_service_pkey PRIMARY KEY (trade_code, code);
ALTER TABLE public.templates ADD CONSTRAINT templates_pkey PRIMARY KEY (name);
ALTER TABLE public.trade_spec_checklist ADD CONSTRAINT trade_spec_checklist_pkey PRIMARY KEY (trade_code, topic_id);
ALTER TABLE public.transactions ADD CONSTRAINT transactions_pkey PRIMARY KEY (id);
ALTER TABLE public.ui_label ADD CONSTRAINT ui_label_pkey PRIMARY KEY (domain, key);
ALTER TABLE public.undo_log ADD CONSTRAINT undo_log_pkey PRIMARY KEY (id);
ALTER TABLE public.unsubscribe_refusal ADD CONSTRAINT unsubscribe_refusal_pkey PRIMARY KEY (id);
ALTER TABLE public.user_roles ADD CONSTRAINT user_roles_pkey PRIMARY KEY (email, role);
ALTER TABLE public.vendor_billing_ended ADD CONSTRAINT vendor_billing_ended_pkey PRIMARY KEY (vendor);
ALTER TABLE public.vision_horizon ADD CONSTRAINT vision_horizon_pkey PRIMARY KEY (year_no);
ALTER TABLE public.vt_results ADD CONSTRAINT vt_results_pkey PRIMARY KEY (id);
ALTER TABLE public.wa_answer_log ADD CONSTRAINT wa_answer_log_pkey PRIMARY KEY (id);
ALTER TABLE public.wa_conversation ADD CONSTRAINT wa_conversation_pkey PRIMARY KEY (id);
ALTER TABLE public.wa_document_intake ADD CONSTRAINT wa_document_intake_pkey PRIMARY KEY (id);
ALTER TABLE public.wa_inbound_seen ADD CONSTRAINT wa_inbound_seen_pkey PRIMARY KEY (message_sid);
ALTER TABLE public.wa_messages ADD CONSTRAINT wa_messages_pkey PRIMARY KEY (id);
ALTER TABLE public.wa_reply_intent ADD CONSTRAINT wa_reply_intent_pkey PRIMARY KEY (intent_key);
ALTER TABLE public.wa_sender_quality_reading ADD CONSTRAINT wa_sender_quality_reading_pkey PRIMARY KEY (id);
ALTER TABLE public.wa_template_registry ADD CONSTRAINT wa_template_registry_pkey PRIMARY KEY (template_name);
ALTER TABLE public.wa_turn ADD CONSTRAINT wa_turn_pkey PRIMARY KEY (id);
ALTER TABLE public.web_search_day ADD CONSTRAINT web_search_day_pkey PRIMARY KEY (day);
ALTER TABLE public.workflow ADD CONSTRAINT workflow_pkey PRIMARY KEY (workflow_key);
ALTER TABLE public.workflow_run ADD CONSTRAINT workflow_run_pkey PRIMARY KEY (id);
ALTER TABLE public.workflow_step ADD CONSTRAINT workflow_step_pkey PRIMARY KEY (workflow_key, step_no);
ALTER TABLE public.workflow_step_run ADD CONSTRAINT workflow_step_run_pkey PRIMARY KEY (id);
ALTER TABLE public.writer_seat ADD CONSTRAINT writer_seat_pkey PRIMARY KEY (kind, name);
ALTER TABLE public.yello_staging ADD CONSTRAINT yello_staging_pkey PRIMARY KEY (company_id);
ALTER TABLE public.accountant_weekly_report ADD CONSTRAINT accountant_weekly_report_key_uniq UNIQUE (report_key);
ALTER TABLE public.action_execution ADD CONSTRAINT action_execution_idempotency_key_key UNIQUE (idempotency_key);
ALTER TABLE public.ai_model_register ADD CONSTRAINT ai_model_register_model_key UNIQUE (model);
ALTER TABLE public.bank_reference_code ADD CONSTRAINT bank_reference_code_bank_code_prefix_code_suffix_key UNIQUE NULLS NOT DISTINCT (bank, code_prefix, code_suffix);
ALTER TABLE public.bank_statement_line ADD CONSTRAINT bank_statement_line_line_hash_key UNIQUE (line_hash);
ALTER TABLE public.blog_posts ADD CONSTRAINT blog_posts_slug_key UNIQUE (slug);
ALTER TABLE public.boq_fixture ADD CONSTRAINT boq_fixture_document_id_key UNIQUE (document_id);
ALTER TABLE public.brand_assets ADD CONSTRAINT brand_assets_url_key UNIQUE (url);
ALTER TABLE public.budget_lines ADD CONSTRAINT budget_lines_budget_id_account_code_period_month_key UNIQUE (budget_id, account_code, period_month);
ALTER TABLE public.budgets ADD CONSTRAINT budgets_name_fiscal_year_key UNIQUE (name, fiscal_year);
ALTER TABLE public.catalog_subcategories ADD CONSTRAINT catalog_subcategories_slug_key UNIQUE (slug);
ALTER TABLE public.category_quote_specs ADD CONSTRAINT category_quote_specs_spec_group_aspect_key UNIQUE (spec_group, aspect);
ALTER TABLE public.ceo_command_rule ADD CONSTRAINT ceo_command_rule_pattern_key UNIQUE (pattern);
ALTER TABLE public.ceo_company_stage ADD CONSTRAINT ceo_company_stage_stage_order_key UNIQUE (stage_order);
ALTER TABLE public.ceo_daily_digest ADD CONSTRAINT ceo_daily_digest_report_key_uniq UNIQUE (report_key);
ALTER TABLE public.ceo_decision_round ADD CONSTRAINT ceo_decision_round_item_key_generation_round_key UNIQUE (item_key, generation, round);
ALTER TABLE public.ceo_experiment ADD CONSTRAINT ceo_experiment_key_key UNIQUE (key);
ALTER TABLE public.ceo_growth_action ADD CONSTRAINT ceo_growth_action_dedupe_key_key UNIQUE (dedupe_key);
ALTER TABLE public.ceo_improvement ADD CONSTRAINT ceo_improvement_source_kind_source_ref_key UNIQUE (source_kind, source_ref);
ALTER TABLE public.ceo_plan ADD CONSTRAINT ceo_plan_plan_date_key UNIQUE (plan_date);
ALTER TABLE public.ceo_plan_action ADD CONSTRAINT ceo_plan_action_seat_from_month_action_key UNIQUE (seat, from_month, action);
ALTER TABLE public.ceo_weekly_report ADD CONSTRAINT ceo_weekly_report_key_rev UNIQUE (report_key, revision);
ALTER TABLE public.ceo_weekly_review ADD CONSTRAINT ceo_weekly_review_week_key UNIQUE (week);
ALTER TABLE public.collaboration_rule ADD CONSTRAINT collaboration_rule_situation_key UNIQUE (situation);
ALTER TABLE public.company_index ADD CONSTRAINT company_index_measured_on_index_name_key UNIQUE (measured_on, index_name);
ALTER TABLE public.company_reflection ADD CONSTRAINT company_reflection_reflected_on_key UNIQUE (reflected_on);
ALTER TABLE public.comparison_run_v2 ADD CONSTRAINT comparison_run_v2_inquiry_id_quote_signature_algorithm_vers_key UNIQUE (inquiry_id, quote_signature, algorithm_version);
ALTER TABLE public.competitive_position ADD CONSTRAINT competitive_position_dimension_key UNIQUE (dimension);
ALTER TABLE public.competitor ADD CONSTRAINT competitor_name_key UNIQUE (name);
ALTER TABLE public.complaint_tickets ADD CONSTRAINT complaint_tickets_ticket_no_key UNIQUE (ticket_no);
ALTER TABLE public.contact_duplicate_group ADD CONSTRAINT contact_duplicate_group_run_on_identity_key_key UNIQUE (run_on, identity_key);
ALTER TABLE public.customer_followup ADD CONSTRAINT customer_followup_token_key UNIQUE (token);
ALTER TABLE public.customer_followup ADD CONSTRAINT customer_followup_transaction_id_stage_key UNIQUE (transaction_id, stage);
ALTER TABLE public.decision_review_request ADD CONSTRAINT decision_review_request_dedupe_key_key UNIQUE (dedupe_key);
ALTER TABLE public.delegation_rule ADD CONSTRAINT delegation_rule_dept_key_when_agent_delegate_to_key UNIQUE (dept_key, when_agent, delegate_to);
ALTER TABLE public.department_objective ADD CONSTRAINT department_objective_dept_key_objective_key UNIQUE (dept_key, objective);
ALTER TABLE public.doc_backups ADD CONSTRAINT doc_backups_bucket_path_key UNIQUE (bucket, path);
ALTER TABLE public.doc_versions ADD CONSTRAINT doc_versions_entity_type_entity_id_version_key UNIQUE (entity_type, entity_id, version);
ALTER TABLE public.documents ADD CONSTRAINT documents_bucket_path_key UNIQUE (bucket, path);
ALTER TABLE public.dropbox_files ADD CONSTRAINT dropbox_files_dropbox_id_key UNIQUE (dropbox_id);
ALTER TABLE public.email_block_pattern ADD CONSTRAINT email_block_pattern_pattern_key UNIQUE (pattern);
ALTER TABLE public.email_verifications ADD CONSTRAINT email_verifications_token_key UNIQUE (token);
ALTER TABLE public.employee_knowledge_standard ADD CONSTRAINT employee_knowledge_standard_layer_key UNIQUE (layer);
ALTER TABLE public.employee_kpi ADD CONSTRAINT employee_kpi_agent_key_kpi_key UNIQUE (agent_key, kpi);
ALTER TABLE public.event_assessment ADD CONSTRAINT event_assessment_event_id_os_key_key UNIQUE (event_id, os_key);
ALTER TABLE public.event_delivery ADD CONSTRAINT event_delivery_event_id_agent_key_key UNIQUE (event_id, agent_key);
ALTER TABLE public.expense_bank_match ADD CONSTRAINT expense_bank_match_bank_line_id_key UNIQUE (bank_line_id);
ALTER TABLE public.expense_vendor_billing_mailbox ADD CONSTRAINT expense_vendor_billing_mailbox_vendor_mailbox_key UNIQUE (vendor, mailbox);
ALTER TABLE public.gl_journal ADD CONSTRAINT gl_journal_entry_no_key UNIQUE (entry_no);
ALTER TABLE public.goal_period ADD CONSTRAINT goal_period_goal_key_horizon_period_label_key UNIQUE (goal_key, horizon, period_label);
ALTER TABLE public.governance_policy ADD CONSTRAINT governance_policy_domain_policy_key UNIQUE (domain, policy);
ALTER TABLE public.handoff_contract ADD CONSTRAINT handoff_contract_action_id_key UNIQUE (action_id);
ALTER TABLE public.inquiry_matches ADD CONSTRAINT inquiry_matches_inquiry_id_supplier_id_key UNIQUE (inquiry_id, supplier_id);
ALTER TABLE public.inquiry_supplier_brief ADD CONSTRAINT inquiry_supplier_brief_inquiry_id_version_key UNIQUE (inquiry_id, version);
ALTER TABLE public.inquiry_trade_candidate ADD CONSTRAINT inquiry_trade_candidate_group_id_trade_key_key UNIQUE (group_id, trade_key);
ALTER TABLE public.inquiry_workstream ADD CONSTRAINT inquiry_workstream_group_id_trade_key_key UNIQUE (group_id, trade_key);
ALTER TABLE public.inquiry_workstream_group ADD CONSTRAINT inquiry_workstream_group_inquiry_id_key UNIQUE (inquiry_id);
ALTER TABLE public.inquiry_workstream_requirement ADD CONSTRAINT inquiry_workstream_requirement_workstream_id_field_id_key UNIQUE (workstream_id, field_id);
ALTER TABLE public.inv_items ADD CONSTRAINT inv_items_sku_key UNIQUE (sku);
ALTER TABLE public.invite_placement_check ADD CONSTRAINT invite_placement_check_token_key UNIQUE (token);
ALTER TABLE public.it_game_day_run ADD CONSTRAINT it_game_day_run_run_month_scenario_key UNIQUE (run_month, scenario);
ALTER TABLE public.it_hold_signature ADD CONSTRAINT it_hold_signature_subject_counts_match_note_like_key UNIQUE NULLS NOT DISTINCT (subject, counts_match, note_like);
ALTER TABLE public.it_incident ADD CONSTRAINT it_incident_handoff_id_key UNIQUE (handoff_id);
ALTER TABLE public.kb_operational_route ADD CONSTRAINT kb_operational_route_route_key_key UNIQUE (route_key);
ALTER TABLE public.kb_revisions ADD CONSTRAINT kb_revisions_entry_kind_entry_ref_version_key UNIQUE (entry_kind, entry_ref, version);
ALTER TABLE public.knowledge_library ADD CONSTRAINT knowledge_library_origin_uq UNIQUE (origin_store, origin_id);
ALTER TABLE public.leads ADD CONSTRAINT leads_place_id_key UNIQUE (place_id);
ALTER TABLE public.legal_checklist ADD CONSTRAINT legal_checklist_requirement_key UNIQUE (requirement);
ALTER TABLE public.licence_renewal_ask ADD CONSTRAINT licence_renewal_ask_lead_id_expiry_date_band_channel_key UNIQUE (lead_id, expiry_date, band, channel);
ALTER TABLE public.llm_attempt ADD CONSTRAINT llm_attempt_one_row_per_attempt UNIQUE (request_id, attempt_no);
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_approval_token_key UNIQUE (approval_token);
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_slug_key UNIQUE (slug);
ALTER TABLE public.marketing_article_round ADD CONSTRAINT marketing_article_round_article_id_round_key UNIQUE (article_id, round);
ALTER TABLE public.marketing_asset_perception ADD CONSTRAINT marketing_asset_perception_file_sha256_model_prompt_version_key UNIQUE (file_sha256, model, prompt_version);
ALTER TABLE public.marketing_campaign ADD CONSTRAINT marketing_campaign_calendar_token_key UNIQUE (calendar_token);
ALTER TABLE public.marketing_campaign ADD CONSTRAINT marketing_campaign_campaign_key_key UNIQUE (campaign_key);
ALTER TABLE public.marketing_first_touch ADD CONSTRAINT marketing_first_touch_lead_id_key UNIQUE (lead_id);
ALTER TABLE public.marketing_geo_check ADD CONSTRAINT marketing_geo_check_month_question_id_engine_key UNIQUE (month, question_id, engine);
ALTER TABLE public.marketing_geo_question ADD CONSTRAINT marketing_geo_question_question_key UNIQUE (question);
ALTER TABLE public.marketing_meta_page ADD CONSTRAINT marketing_meta_page_ig_id_key UNIQUE (ig_id);
ALTER TABLE public.marketing_month_plan ADD CONSTRAINT marketing_month_plan_plan_token_key UNIQUE (plan_token);
ALTER TABLE public.marketing_outreach_message ADD CONSTRAINT marketing_outreach_message_mark_token_key UNIQUE (mark_token);
ALTER TABLE public.marketing_plan_doc ADD CONSTRAINT marketing_plan_doc_approval_token_key UNIQUE (approval_token);
ALTER TABLE public.marketing_plan_doc ADD CONSTRAINT marketing_plan_doc_kind_period_key UNIQUE (kind, period);
ALTER TABLE public.marketing_plan_review_turn ADD CONSTRAINT marketing_plan_review_turn_month_round_seat_key UNIQUE (month, round, seat);
ALTER TABLE public.marketing_post ADD CONSTRAINT marketing_post_ingest_key_key UNIQUE (ingest_key);
ALTER TABLE public.marketing_post_metric ADD CONSTRAINT marketing_post_metric_post_id_platform_checkpoint_metric_key UNIQUE (post_id, platform, checkpoint, metric);
ALTER TABLE public.marketing_post_variant ADD CONSTRAINT marketing_post_variant_post_id_platform_seq_key UNIQUE (post_id, platform, seq);
ALTER TABLE public.marketing_recruitment_source ADD CONSTRAINT marketing_recruitment_source_scope_url_key UNIQUE (scope, url);
ALTER TABLE public.marketing_review ADD CONSTRAINT marketing_review_kind_period_key UNIQUE (kind, period);
ALTER TABLE public.marketing_trend ADD CONSTRAINT marketing_trend_url_key UNIQUE (url);
ALTER TABLE public.marketing_trend_source ADD CONSTRAINT marketing_trend_source_feed_url_key UNIQUE (feed_url);
ALTER TABLE public.marketing_trend_source ADD CONSTRAINT marketing_trend_source_name_key UNIQUE (name);
ALTER TABLE public.marketing_video_idea ADD CONSTRAINT marketing_video_idea_idea_key_key UNIQUE (idea_key);
ALTER TABLE public.mdm_brands ADD CONSTRAINT mdm_brands_name_key UNIQUE (name);
ALTER TABLE public.mdm_manufacturers ADD CONSTRAINT mdm_manufacturers_name_key UNIQUE (name);
ALTER TABLE public.mdm_standards ADD CONSTRAINT mdm_standards_code_key UNIQUE (code);
ALTER TABLE public.meta_insights ADD CONSTRAINT meta_insights_campaign_id_time_window_key UNIQUE (campaign_id, time_window);
ALTER TABLE public.os_interface ADD CONSTRAINT os_interface_os_key_direction_kind_key UNIQUE (os_key, direction, kind);
ALTER TABLE public.os_objective ADD CONSTRAINT os_objective_os_key_horizon_objective_key UNIQUE (os_key, horizon, objective);
ALTER TABLE public.os_review ADD CONSTRAINT os_review_os_key_period_key UNIQUE (os_key, period);
ALTER TABLE public.po_lines ADD CONSTRAINT po_lines_po_id_line_no_key UNIQUE (po_id, line_no);
ALTER TABLE public.po_orders ADD CONSTRAINT po_orders_po_no_key UNIQUE (po_no);
ALTER TABLE public.prompt_benchmarks ADD CONSTRAINT prompt_benchmarks_prompt_key_name_key UNIQUE (prompt_key, name);
ALTER TABLE public.prompt_versions ADD CONSTRAINT prompt_versions_prompt_key_version_key UNIQUE (prompt_key, version);
ALTER TABLE public.qualification_playbooks ADD CONSTRAINT qualification_playbooks_category_version_key UNIQUE (category, version);
ALTER TABLE public.quote_reviews ADD CONSTRAINT quote_reviews_inquiry_id_supplier_id_key UNIQUE (inquiry_id, supplier_id);
ALTER TABLE public.reasoning_held_question ADD CONSTRAINT reasoning_held_question_dedupe_key_key UNIQUE (dedupe_key);
ALTER TABLE public.reasoning_knowledge_candidate ADD CONSTRAINT reasoning_knowledge_candidate_finding_sha_key UNIQUE (finding_sha);
ALTER TABLE public.refund_ceo_review ADD CONSTRAINT refund_ceo_review_one_per_cycle UNIQUE (refund_id, cycle);
ALTER TABLE public.refunds ADD CONSTRAINT refunds_stripe_refund_id_key UNIQUE (stripe_refund_id);
ALTER TABLE public.reg_catalog ADD CONSTRAINT reg_catalog_authority_code_name_key UNIQUE (authority, code_name);
ALTER TABLE public.resource_pool ADD CONSTRAINT resource_pool_resource_key UNIQUE (resource);
ALTER TABLE public.review_route ADD CONSTRAINT review_route_decision_type_owner_seat_key UNIQUE (decision_type, owner_seat);
ALTER TABLE public.reviews ADD CONSTRAINT reviews_transaction_id_key UNIQUE (transaction_id);
ALTER TABLE public.rfq_archives ADD CONSTRAINT rfq_archives_rfq_id_key UNIQUE (rfq_id);
ALTER TABLE public.routine_judgement ADD CONSTRAINT routine_judgement_kind_subject_key_key UNIQUE (kind, subject_key);
ALTER TABLE public.sales_engineer_framework_proposal ADD CONSTRAINT sales_engineer_framework_proposal_customer_id_trade_key UNIQUE (customer_id, trade);
ALTER TABLE public.sales_engineer_negotiation_round ADD CONSTRAINT sales_engineer_negotiation_round_quote_id_round_key UNIQUE (quote_id, round);
ALTER TABLE public.sales_knowledge_gap ADD CONSTRAINT sales_knowledge_gap_question_norm_key UNIQUE (question_norm);
ALTER TABLE public.seat_case_memory ADD CONSTRAINT seat_case_memory_source_uq UNIQUE (source_table, source_id);
ALTER TABLE public.seat_knowledge_eval_question ADD CONSTRAINT seat_knowledge_eval_question_seat_pack_lang_question_key UNIQUE (seat, pack, lang, question);
ALTER TABLE public.signup_purge_dropbox ADD CONSTRAINT signup_purge_dropbox_doc_backup_id_key UNIQUE (doc_backup_id);
ALTER TABLE public.signup_purge_object ADD CONSTRAINT signup_purge_object_bucket_path_key UNIQUE (bucket, path);
ALTER TABLE public.social_connect_link ADD CONSTRAINT social_connect_link_state_hash_key UNIQUE (state_hash);
ALTER TABLE public.social_connect_link ADD CONSTRAINT social_connect_link_token_hash_key UNIQUE (token_hash);
ALTER TABLE public.social_conversation ADD CONSTRAINT social_conversation_platform_user_id_key UNIQUE (platform, user_id);
ALTER TABLE public.social_message ADD CONSTRAINT social_message_platform_meta_message_id_key UNIQUE (platform, meta_message_id);
ALTER TABLE public.strategy_risks ADD CONSTRAINT strategy_risks_category_title_key UNIQUE (category, title);
ALTER TABLE public.supplier_campaign_daily_list ADD CONSTRAINT supplier_campaign_daily_list_list_day_key UNIQUE (list_day);
ALTER TABLE public.supplier_catalog ADD CONSTRAINT supplier_catalog_supplier_id_source_hash_key UNIQUE (supplier_id, source_hash);
ALTER TABLE public.supplier_due_payments ADD CONSTRAINT supplier_due_payments_due_reference_key UNIQUE (due_id, reference);
ALTER TABLE public.supplier_dues ADD CONSTRAINT supplier_dues_transaction_id_key UNIQUE (transaction_id);
ALTER TABLE public.supplier_product ADD CONSTRAINT supplier_product_supplier_id_external_key_key UNIQUE (supplier_id, external_key);
ALTER TABLE public.supplier_product_variant ADD CONSTRAINT supplier_product_variant_product_id_sku_key UNIQUE (product_id, sku);
ALTER TABLE public.supplier_quote_template ADD CONSTRAINT supplier_quote_template_supplier_id_name_key UNIQUE (supplier_id, name);
ALTER TABLE public.supplier_reply_followup ADD CONSTRAINT supplier_reply_followup_inbound_message_id_key UNIQUE (inbound_message_id);
ALTER TABLE public.supplier_response_watch ADD CONSTRAINT supplier_response_watch_one_per_tx UNIQUE (transaction_id);
ALTER TABLE public.supplier_screening_hit ADD CONSTRAINT supplier_screening_hit_lead_id_entry_source_entry_reference_key UNIQUE (lead_id, entry_source, entry_reference, field);
ALTER TABLE public.supplier_whatsapp_optin ADD CONSTRAINT supplier_whatsapp_optin_lead_id_phone_key UNIQUE (lead_id, phone);
ALTER TABLE public.supply_recruitment_brief ADD CONSTRAINT supply_recruitment_brief_trade_emirate_key UNIQUE (trade, emirate);
ALTER TABLE public.support_case ADD CONSTRAINT support_case_case_ref_key UNIQUE (case_ref);
ALTER TABLE public.support_ceo_report ADD CONSTRAINT support_ceo_report_idempotency_key_key UNIQUE (idempotency_key);
ALTER TABLE public.support_customer_profile ADD CONSTRAINT support_customer_profile_customer_id_key UNIQUE (customer_id);
ALTER TABLE public.support_customer_profile ADD CONSTRAINT support_customer_profile_lead_id_key UNIQUE (lead_id);
ALTER TABLE public.support_notification ADD CONSTRAINT support_notification_dedupe_key_key UNIQUE (dedupe_key);
ALTER TABLE public.support_root_cause_fix ADD CONSTRAINT support_root_cause_fix_root_cause_id_target_table_target_id_key UNIQUE (root_cause_id, target_table, target_id);
ALTER TABLE public.taxonomy_trade_proposal ADD CONSTRAINT taxonomy_trade_proposal_supplier_id_code_key UNIQUE (supplier_id, code);
ALTER TABLE public.vt_results ADD CONSTRAINT vt_results_path_key UNIQUE (path);
ALTER TABLE public.wa_conversation ADD CONSTRAINT wa_conversation_phone_e164_key UNIQUE (phone_e164);
ALTER TABLE public.workflow_run ADD CONSTRAINT workflow_run_idempotency_key_key UNIQUE (idempotency_key);
ALTER TABLE public.workflow_step_run ADD CONSTRAINT workflow_step_run_idempotency_key_key UNIQUE (idempotency_key);
ALTER TABLE public.workflow_step_run ADD CONSTRAINT workflow_step_run_workflow_run_id_step_no_key UNIQUE (workflow_run_id, step_no);
ALTER TABLE public.accountant_ad_spend_month ADD CONSTRAINT accountant_ad_spend_month_month_check CHECK ((month = (date_trunc('month'::text, (month)::timestamp with time zone))::date));
ALTER TABLE public.accountant_ad_spend_month ADD CONSTRAINT accountant_ad_spend_month_reported_spend_aed_check CHECK (((reported_spend_aed IS NULL) OR (reported_spend_aed > (0)::numeric)));
ALTER TABLE public.accountant_founder_close_pack ADD CONSTRAINT accountant_founder_close_pack_month_check CHECK ((month = (date_trunc('month'::text, (month)::timestamp with time zone))::date));
ALTER TABLE public.accountant_issued_document ADD CONSTRAINT accountant_issued_document_content_sha256_check CHECK ((content_sha256 ~ '^[0-9a-f]{64}$'::text));
ALTER TABLE public.accountant_issued_document ADD CONSTRAINT accountant_issued_document_document_kind_check CHECK ((document_kind = ANY (ARRAY['charge_reminder'::text, 'final_demand'::text, 'filing_pack'::text, 'invoice'::text])));
ALTER TABLE public.accountant_knowledge ADD CONSTRAINT accountant_knowledge_authority_ck CHECK ((authority_effect = 'none'::text));
ALTER TABLE public.accountant_knowledge ADD CONSTRAINT accountant_knowledge_epistemic_ck CHECK ((epistemic_status = ANY (ARRAY['method_general_accounting'::text, 'marketplace_policy_derived'::text, 'framework_shape_verify_current_text'::text, 'obligation_shape_no_figures'::text, 'resolve_from_authority'::text, 'company_record_generated'::text, 'company_governance_ruling'::text, 'authority_protocol'::text, 'verified_pack_sourced'::text])));
ALTER TABLE public.accountant_mailbox_check ADD CONSTRAINT accountant_mailbox_check_verdict_check CHECK ((verdict = ANY (ARRAY['unreadable'::text, 'intake_silent'::text, 'held_waiting'::text, 'mailbox_quiet'::text, 'current'::text])));
ALTER TABLE public.accountant_month_close ADD CONSTRAINT accountant_month_close_month_check CHECK ((month = (date_trunc('month'::text, (month)::timestamp with time zone))::date));
ALTER TABLE public.accountant_owner_ruled_subscription ADD CONSTRAINT accountant_owner_ruled_subscription_bank_value_aed_check CHECK ((bank_value_aed > (0)::numeric));
ALTER TABLE public.accountant_owner_ruled_subscription ADD CONSTRAINT accountant_owner_ruled_subscription_cadence_check CHECK ((cadence = 'monthly'::text));
ALTER TABLE public.accountant_owner_ruled_subscription ADD CONSTRAINT accountant_owner_ruled_subscription_paid_from_check CHECK ((paid_from = ANY (ARRAY['owner_card'::text, 'company_card'::text])));
ALTER TABLE public.accountant_owner_ruled_subscription ADD CONSTRAINT accountant_owner_ruled_subscription_usual_day_check CHECK (((usual_day >= 1) AND (usual_day <= 31)));
ALTER TABLE public.accountant_renewal_budget ADD CONSTRAINT accountant_renewal_budget_basis_check CHECK ((btrim(basis) <> ''::text));
ALTER TABLE public.accountant_renewal_budget ADD CONSTRAINT accountant_renewal_budget_budget_aed_check CHECK (((budget_aed IS NULL) OR (budget_aed > (0)::numeric)));
ALTER TABLE public.accountant_subscription_paid_from_change ADD CONSTRAINT accountant_subscription_paid_from_change_paid_from_check CHECK ((paid_from = ANY (ARRAY['owner_card'::text, 'company_card'::text])));
ALTER TABLE public.accountant_vat_threshold_check ADD CONSTRAINT accountant_vat_threshold_check_status_check CHECK ((status = ANY (ARRAY['below'::text, 'approaching'::text, 'voluntary_eligible'::text, 'mandatory'::text])));
ALTER TABLE public.accountant_weekly_report ADD CONSTRAINT accountant_weekly_report_status_ck CHECK ((status = ANY (ARRAY['generated'::text, 'pdf_failed'::text, 'partial'::text, 'delivered'::text, 'delivery_failed'::text])));
ALTER TABLE public.accountant_weekly_report ADD CONSTRAINT accountant_weekly_report_week_ck CHECK ((week_end > week_start));
ALTER TABLE public.accountant_year_end_pack ADD CONSTRAINT accountant_year_end_pack_files_check CHECK ((jsonb_typeof(files) = 'array'::text));
ALTER TABLE public.accountant_year_end_pack ADD CONSTRAINT accountant_year_end_pack_year_check CHECK ((year >= 2000));
ALTER TABLE public.action_class_demand ADD CONSTRAINT action_class_demand_action_class_check CHECK ((action_class ~ '^[a-z_]+$'::text));
ALTER TABLE public.action_class_demand ADD CONSTRAINT action_class_demand_reason_check CHECK ((btrim(reason) <> ''::text));
ALTER TABLE public.action_class_gate ADD CONSTRAINT action_class_gate_known_gate CHECK (((gate_action_class IS NULL) OR (gate_action_class = ANY (ARRAY['ad_spend'::text, 'authentication_identity'::text, 'autonomy_framework'::text, 'destructive_data'::text, 'legal_commitment'::text, 'money_move'::text, 'production_deploy'::text, 'public_claim_publish'::text, 'secrets_security'::text, 'supplier_enforcement'::text]))));
ALTER TABLE public.ad_campaign_state ADD CONSTRAINT ad_campaign_state_daily_budget_aed_check CHECK ((daily_budget_aed >= (0)::numeric));
ALTER TABLE public.ad_campaign_state ADD CONSTRAINT ad_campaign_state_status_check CHECK ((status = ANY (ARRAY['ACTIVE'::text, 'PAUSED'::text])));
ALTER TABLE public.ad_decision ADD CONSTRAINT ad_decision_action_check CHECK ((action = ANY (ARRAY['activate'::text, 'pause'::text, 'set_daily_budget'::text])));
ALTER TABLE public.ad_decision ADD CONSTRAINT ad_decision_amount_aed_check CHECK (((amount_aed IS NULL) OR (amount_aed >= (0)::numeric)));
ALTER TABLE public.ad_decision ADD CONSTRAINT ad_decision_check CHECK (((action = 'set_daily_budget'::text) = (amount_aed IS NOT NULL)));
ALTER TABLE public.ad_decision ADD CONSTRAINT ad_decision_execution_mode_check CHECK (((execution_mode IS NULL) OR (execution_mode = ANY (ARRAY['sandbox'::text, 'live'::text]))));
ALTER TABLE public.ad_spend_policy ADD CONSTRAINT ad_spend_policy_check CHECK ((min_daily_per_campaign_aed <= max_daily_per_campaign_aed));
ALTER TABLE public.ad_spend_policy ADD CONSTRAINT ad_spend_policy_daily_cap_aed_check CHECK ((daily_cap_aed >= (0)::numeric));
ALTER TABLE public.ad_spend_policy ADD CONSTRAINT ad_spend_policy_kill_multiplier_check CHECK ((kill_multiplier >= (1)::numeric));
ALTER TABLE public.ad_spend_policy ADD CONSTRAINT ad_spend_policy_learning_min_spend_aed_check CHECK ((learning_min_spend_aed >= (0)::numeric));
ALTER TABLE public.ad_spend_policy ADD CONSTRAINT ad_spend_policy_learning_phase_days_check CHECK ((learning_phase_days >= 0));
ALTER TABLE public.ad_spend_policy ADD CONSTRAINT ad_spend_policy_max_daily_per_campaign_aed_check CHECK ((max_daily_per_campaign_aed > (0)::numeric));
ALTER TABLE public.ad_spend_policy ADD CONSTRAINT ad_spend_policy_min_daily_per_campaign_aed_check CHECK ((min_daily_per_campaign_aed > (0)::numeric));
ALTER TABLE public.ad_spend_policy ADD CONSTRAINT ad_spend_policy_month_spent_aed_check CHECK ((month_spent_aed >= (0)::numeric));
ALTER TABLE public.ad_spend_policy ADD CONSTRAINT ad_spend_policy_monthly_cap_aed_check CHECK (((monthly_cap_aed IS NULL) OR (monthly_cap_aed >= (0)::numeric)));
ALTER TABLE public.ad_spend_policy ADD CONSTRAINT ad_spend_policy_scale_step_pct_check CHECK ((scale_step_pct >= (0)::numeric));
ALTER TABLE public.ad_spend_policy ADD CONSTRAINT ad_spend_policy_target_cpl_aed_check CHECK ((target_cpl_aed > (0)::numeric));
ALTER TABLE public.ad_spend_reported ADD CONSTRAINT ad_spend_reported_amount_check CHECK ((amount >= (0)::numeric));
ALTER TABLE public.ad_spend_reported ADD CONSTRAINT ad_spend_reported_currency_check CHECK ((currency ~ '^[A-Z]{3}$'::text));
ALTER TABLE public.ad_spend_reported ADD CONSTRAINT ad_spend_reported_platform_check CHECK ((platform ~ '^[a-z][a-z0-9_]*$'::text));
ALTER TABLE public.ad_spend_reported ADD CONSTRAINT ad_spend_reported_revisions_check CHECK ((revisions >= 1));
ALTER TABLE public.ad_spend_reported ADD CONSTRAINT ad_spend_reported_source_ref_check CHECK ((btrim(source_ref) <> ''::text));
ALTER TABLE public.agent_action_kind_policy ADD CONSTRAINT agent_action_kind_policy_policy_check CHECK ((policy = ANY (ARRAY['auto'::text, 'officer'::text, 'notify'::text])));
ALTER TABLE public.agent_actions ADD CONSTRAINT agent_actions_handoff_carries_its_note CHECK (((kind <> 'handoff'::text) OR (COALESCE((detail -> 'summary'::text), '{}'::jsonb) ?& ARRAY['known'::text, 'tried'::text, 'needed'::text, 'evidence'::text]))) NOT VALID;
ALTER TABLE public.agent_actions ADD CONSTRAINT agent_actions_handoff_note_states_four_fields CHECK (((kind <> 'handoff'::text) OR (COALESCE((detail -> 'summary'::text), '{}'::jsonb) ?& ARRAY['context'::text, 'decision'::text, 'open_asks'::text, 'deadline'::text]))) NOT VALID;
ALTER TABLE public.agent_chats ADD CONSTRAINT agent_chats_role_check CHECK ((role = ANY (ARRAY['user'::text, 'assistant'::text])));
ALTER TABLE public.agent_knowledge ADD CONSTRAINT agent_knowledge_layer_check CHECK ((layer = ANY (ARRAY['company'::text, 'profession'::text, 'state'::text, 'experience'::text])));
ALTER TABLE public.agent_memory ADD CONSTRAINT agent_memory_horizon_check CHECK ((horizon = ANY (ARRAY['short'::text, 'long'::text])));
ALTER TABLE public.agent_memory ADD CONSTRAINT agent_memory_horizon_chk CHECK ((horizon = ANY (ARRAY['short'::text, 'long'::text])));
ALTER TABLE public.agent_remediation ADD CONSTRAINT agent_remediation_status_check CHECK ((status = ANY (ARRAY['open'::text, 'training'::text, 'retesting'::text, 'passed'::text, 'escalated'::text, 'abandoned'::text])));
ALTER TABLE public.agent_reputation ADD CONSTRAINT agent_reputation_tier_check CHECK ((tier = ANY (ARRAY['probation'::text, 'standard'::text, 'trusted'::text, 'senior_trusted'::text, 'unmeasured'::text])));
ALTER TABLE public.agent_tool ADD CONSTRAINT agent_tool_audit_behaviour_check CHECK ((audit_behaviour = ANY (ARRAY['trace'::text, 'trace_and_notify'::text])));
ALTER TABLE public.agent_tool ADD CONSTRAINT agent_tool_backoff_check CHECK ((backoff = ANY (ARRAY['none'::text, 'fixed_1s'::text, 'exponential_2s'::text])));
ALTER TABLE public.agent_tool ADD CONSTRAINT agent_tool_failure_behaviour_check CHECK ((failure_behaviour = ANY (ARRAY['fail_closed'::text, 'escalate'::text, 'degrade_with_caveat'::text])));
ALTER TABLE public.agent_tool ADD CONSTRAINT agent_tool_impl_kind_check CHECK ((impl_kind = ANY (ARRAY['rpc'::text, 'edge_function'::text, 'executor'::text])));
ALTER TABLE public.agent_tool ADD CONSTRAINT agent_tool_kind_check CHECK ((kind = ANY (ARRAY['read'::text, 'write'::text])));
ALTER TABLE public.agent_tool ADD CONSTRAINT agent_tool_max_attempts_check CHECK (((max_attempts >= 1) AND (max_attempts <= 5)));
ALTER TABLE public.agent_tool ADD CONSTRAINT agent_tool_min_authority_check CHECK ((min_authority = ANY (ARRAY['advisory'::text, 'gated'::text, 'supervised'::text, 'autonomous'::text])));
ALTER TABLE public.agent_tool ADD CONSTRAINT agent_tool_timeout_seconds_check CHECK (((timeout_seconds >= 1) AND (timeout_seconds <= 120)));
ALTER TABLE public.agent_tool_call ADD CONSTRAINT agent_tool_call_status_check CHECK ((status = ANY (ARRAY['ok'::text, 'ok_empty'::text, 'error'::text, 'timeout'::text, 'unavailable'::text, 'unauthorised'::text])));
ALTER TABLE public.agent_training_attempt ADD CONSTRAINT agent_training_attempt_purpose_check CHECK ((purpose = ANY (ARRAY['practice'::text, 'retest'::text, 'drift_check'::text])));
ALTER TABLE public.agent_training_case ADD CONSTRAINT agent_training_case_generation_check CHECK ((generation = ANY (ARRAY['V1'::text, 'V2'::text, 'V3'::text])));
ALTER TABLE public.agent_training_case ADD CONSTRAINT agent_training_case_scope_type_check CHECK ((scope_type = ANY (ARRAY['role'::text, 'department'::text, 'category'::text, 'company'::text])));
ALTER TABLE public.ai_cost_log ADD CONSTRAINT ai_cost_log_seat_basis_check CHECK (((seat_basis IS NULL) OR (seat_basis = ANY (ARRAY['declared'::text, 'bound'::text, 'unattributed'::text]))));
ALTER TABLE public.ap_bills ADD CONSTRAINT ap_bills_amounts_money_ck CHECK (((subtotal >= (0)::numeric) AND (vat_amount >= (0)::numeric) AND (total >= (0)::numeric) AND (amount_paid >= (0)::numeric)));
ALTER TABLE public.ap_bills ADD CONSTRAINT ap_bills_status_check CHECK ((status = ANY (ARRAY['open'::text, 'partial'::text, 'paid'::text, 'void'::text, 'duplicate_hold'::text])));
ALTER TABLE public.arabic_compare_waiter ADD CONSTRAINT arabic_compare_waiter_inquiry_id_check CHECK ((btrim(inquiry_id) <> ''::text));
ALTER TABLE public.arabic_compare_waiter ADD CONSTRAINT arabic_compare_waiter_texts_check CHECK ((cardinality(texts) > 0));
ALTER TABLE public.arabic_document_waiter ADD CONSTRAINT arabic_document_waiter_quote_id_check CHECK ((btrim(quote_id) <> ''::text));
ALTER TABLE public.arabic_document_waiter ADD CONSTRAINT arabic_document_waiter_texts_check CHECK ((cardinality(texts) > 0));
ALTER TABLE public.arabic_outbound_hold ADD CONSTRAINT arabic_outbound_hold_delivery_check CHECK ((jsonb_typeof(delivery) = 'array'::text));
ALTER TABLE public.arabic_outbound_hold ADD CONSTRAINT arabic_outbound_hold_status_check CHECK ((status = ANY (ARRAY['held'::text, 'sent'::text, 'failed'::text])));
ALTER TABLE public.arabic_outbound_hold ADD CONSTRAINT arabic_outbound_hold_texts_check CHECK ((cardinality(texts) > 0));
ALTER TABLE public.arabic_translation ADD CONSTRAINT arabic_translation_is_arabic_or_kept CHECK (((arabic ~ '[؀-ۿ]'::text) OR (arabic = source)));
ALTER TABLE public.arabic_translation ADD CONSTRAINT arabic_translation_source_md5_check CHECK ((source_md5 ~ '^[0-9a-f]{32}$'::text));
ALTER TABLE public.artifact_review ADD CONSTRAINT artifact_review_verdict_check CHECK ((verdict = ANY (ARRAY['pass'::text, 'fail'::text, 'blocked'::text])));
ALTER TABLE public.autonomy_policy ADD CONSTRAINT autonomy_policy_no_founder_approval CHECK ((founder_approval_required = false));
ALTER TABLE public.autonomy_policy ADD CONSTRAINT autonomy_policy_no_founder_escalation CHECK ((founder_escalation_allowed = false));
ALTER TABLE public.autonomy_policy ADD CONSTRAINT autonomy_policy_single CHECK ((id = 1));
ALTER TABLE public.backup_prune_log ADD CONSTRAINT backup_prune_log_mode_check CHECK ((mode = ANY (ARRAY['dry_run'::text, 'delete'::text])));
ALTER TABLE public.backup_prune_log ADD CONSTRAINT backup_prune_log_origin_check CHECK ((origin = ANY (ARRAY['export'::text, 'legacy'::text])));
ALTER TABLE public.bank_line_owner_ruling ADD CONSTRAINT bank_line_owner_ruling_ruling_check CHECK ((ruling = ANY (ARRAY['capital'::text, 'loan'::text])));
ALTER TABLE public.bank_reference_code ADD CONSTRAINT bank_reference_code_check CHECK ((((kind IS NULL) AND (gl_account IS NULL)) OR ((kind = 'bank_charge'::text) AND (sign = '-1'::integer) AND (gl_account = '6300'::text)) OR ((kind = 'bank_interest'::text) AND (sign = 1) AND (gl_account = '7000'::text))));
ALTER TABLE public.bank_reference_code ADD CONSTRAINT bank_reference_code_kind_check CHECK ((kind = ANY (ARRAY['bank_charge'::text, 'bank_interest'::text])));
ALTER TABLE public.bank_reference_code ADD CONSTRAINT bank_reference_code_sign_check CHECK ((sign = ANY (ARRAY['-1'::integer, 1])));
ALTER TABLE public.bank_statement_intake ADD CONSTRAINT bank_statement_intake_state_check CHECK ((state = ANY (ARRAY['parsed'::text, 'unreadable'::text])));
ALTER TABLE public.bank_statement_line ADD CONSTRAINT bank_statement_line_kind_check CHECK (((kind IS NULL) OR (kind = ANY (ARRAY['bank_charge'::text, 'owner_transfer'::text, 'bank_interest'::text, 'stripe_payout'::text, 'other'::text]))));
ALTER TABLE public.board_opinion ADD CONSTRAINT board_opinion_recommendation_check CHECK ((recommendation = ANY (ARRAY['proceed'::text, 'proceed_with_conditions'::text, 'do_not_proceed'::text, 'abstain'::text])));
ALTER TABLE public.boq_section_reading ADD CONSTRAINT boq_section_reading_reading_check CHECK ((reading ~ '^[a-z_]+$'::text));
ALTER TABLE public.boq_section_reading ADD CONSTRAINT boq_section_reading_reasoned_by_check CHECK ((reasoned_by = ANY (ARRAY['reasoning'::text, 'replay'::text])));
ALTER TABLE public.boq_section_reading ADD CONSTRAINT boq_section_reading_section_check CHECK ((length(section) <= 200));
ALTER TABLE public.boq_section_reading ADD CONSTRAINT boq_section_reading_section_key_check CHECK (((btrim(section_key) <> ''::text) AND (length(section_key) <= 200)));
ALTER TABLE public.budget_lines ADD CONSTRAINT budget_lines_amount_money_ck CHECK ((amount >= (0)::numeric));
ALTER TABLE public.budgets ADD CONSTRAINT budgets_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'closed'::text])));
ALTER TABLE public.cad_read_jobs ADD CONSTRAINT cad_read_jobs_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'running'::text, 'done'::text, 'failed'::text])));
ALTER TABLE public.cad_read_jobs ADD CONSTRAINT cad_read_jobs_why_check CHECK ((why = ANY (ARRAY['over_edge_ceiling'::text, 'edge_worker_died'::text, 'edge_reader_failed'::text, 'pdf_lengths_worker_died'::text, 'scan_needs_ocr'::text])));
ALTER TABLE public.canon_eval_questions ADD CONSTRAINT canon_eval_questions_layer_check CHECK ((layer = ANY (ARRAY['company'::text, 'profession'::text, 'state'::text, 'experience'::text])));
ALTER TABLE public.ceo_approval ADD CONSTRAINT ceo_approval_decision_check CHECK ((decision = ANY (ARRAY['approved'::text, 'refused'::text])));
ALTER TABLE public.ceo_approval ADD CONSTRAINT ceo_approval_not_self_superseding CHECK ((superseded_by IS DISTINCT FROM decision_id));
ALTER TABLE public.ceo_approval ADD CONSTRAINT ceo_approval_subject_kind_check CHECK ((subject_kind = ANY (ARRAY['refund'::text, 'spend'::text, 'supplier'::text, 'publication'::text, 'other'::text])));
ALTER TABLE public.ceo_command ADD CONSTRAINT ceo_command_channel_check CHECK ((channel = ANY (ARRAY['whatsapp'::text, 'email'::text, 'api'::text, 'console'::text])));
ALTER TABLE public.ceo_constraint_lever ADD CONSTRAINT ceo_constraint_lever_measure_check CHECK ((btrim(measure) <> ''::text));
ALTER TABLE public.ceo_constraint_lever ADD CONSTRAINT ceo_constraint_lever_proposal_check CHECK ((btrim(proposal) <> ''::text));
ALTER TABLE public.ceo_daily_digest ADD CONSTRAINT ceo_daily_digest_status_ck CHECK ((status = ANY (ARRAY['generated'::text, 'submitted'::text, 'delivered'::text, 'delivery_failed'::text])));
ALTER TABLE public.ceo_decision ADD CONSTRAINT ceo_decision_authority_ck CHECK ((authority = ANY (ARRAY['ceo_alone'::text, 'ceo_case_decision'::text, 'founder_specified'::text])));
ALTER TABLE public.ceo_decision_log ADD CONSTRAINT ceo_decision_log_evidence_ck CHECK (((jsonb_typeof(evidence) = 'object'::text) AND (evidence <> '{}'::jsonb)));
ALTER TABLE public.ceo_decision_log ADD CONSTRAINT ceo_decision_log_outcome_ck CHECK ((outcome = ANY (ARRAY['decided'::text, 'needs_judgement'::text])));
ALTER TABLE public.ceo_decision_round ADD CONSTRAINT ceo_decision_round_decided_by_check CHECK ((decided_by = 'ceo'::text));
ALTER TABLE public.ceo_decision_round ADD CONSTRAINT ceo_decision_round_decision_check CHECK ((decision = ANY (ARRAY['approved'::text, 'rejected'::text, 'replaced'::text, 'withdrawn'::text])));
ALTER TABLE public.ceo_decision_round ADD CONSTRAINT ceo_decision_round_generation_check CHECK ((generation >= 1));
ALTER TABLE public.ceo_decision_round ADD CONSTRAINT ceo_decision_round_item_key_check CHECK ((btrim(item_key) <> ''::text));
ALTER TABLE public.ceo_decision_round ADD CONSTRAINT ceo_decision_round_path_check CHECK ((path = ANY (ARRAY['seat_deliberation'::text, 'refund'::text, 'ceo_experiment'::text, 'ceo_improvement'::text, 'marketing_month_plan'::text])));
ALTER TABLE public.ceo_decision_round ADD CONSTRAINT ceo_decision_round_round_check CHECK ((round >= 1));
ALTER TABLE public.ceo_decision_round ADD CONSTRAINT ceo_decision_round_version_check CHECK (((jsonb_typeof(version) = 'object'::text) AND (length((version)::text) <= 30000)));
ALTER TABLE public.ceo_directive ADD CONSTRAINT ceo_directive_done_sql_check CHECK ((btrim(done_sql) <> ''::text));
ALTER TABLE public.ceo_directive ADD CONSTRAINT ceo_directive_done_when_check CHECK ((btrim(done_when) <> ''::text));
ALTER TABLE public.ceo_directive ADD CONSTRAINT ceo_directive_instruction_check CHECK ((btrim(instruction) <> ''::text));
ALTER TABLE public.ceo_directive ADD CONSTRAINT ceo_directive_source_kind_check CHECK ((source_kind = ANY (ARRAY['target_miss'::text, 'late_deliverable'::text, 'stuck_handoff'::text, 'seat_audit'::text, 'forecast_at_risk'::text, 'improvement_backlog'::text, 'experiment'::text, 'register_review'::text])));
ALTER TABLE public.ceo_directive ADD CONSTRAINT ceo_directive_status_check CHECK ((status = ANY (ARRAY['open'::text, 'met'::text, 'escalated'::text, 'missed'::text, 'paused'::text])));
ALTER TABLE public.ceo_experiment ADD CONSTRAINT ceo_experiment_days_check CHECK (((days >= 7) AND (days <= 365)));
ALTER TABLE public.ceo_experiment ADD CONSTRAINT ceo_experiment_direction_check CHECK ((direction = ANY (ARRAY['min'::text, 'max'::text])));
ALTER TABLE public.ceo_experiment ADD CONSTRAINT ceo_experiment_hypothesis_check CHECK ((btrim(hypothesis) <> ''::text));
ALTER TABLE public.ceo_experiment ADD CONSTRAINT ceo_experiment_key_check CHECK ((key ~ '^[a-z0-9_]+$'::text));
ALTER TABLE public.ceo_experiment ADD CONSTRAINT ceo_experiment_status_check CHECK ((status = ANY (ARRAY['proposed'::text, 'approved'::text, 'running'::text, 'rejected'::text, 'kept'::text, 'killed'::text])));
ALTER TABLE public.ceo_experiment_verdict ADD CONSTRAINT ceo_experiment_verdict_decision_check CHECK ((decision = ANY (ARRAY['kept'::text, 'killed'::text, 'iterated'::text])));
ALTER TABLE public.ceo_growth_action ADD CONSTRAINT ceo_growth_action_power_check CHECK ((power = ANY (ARRAY['run'::text, 'cap'::text, 'ceiling'::text, 'reachable'::text, 'trade'::text, 'channel'::text, 'directive'::text])));
ALTER TABLE public.ceo_growth_action ADD CONSTRAINT ceo_growth_action_verdict_check CHECK ((verdict = ANY (ARRAY['pending'::text, 'not_applied'::text, 'worked'::text, 'failed'::text, 'rolled_back'::text, 'no_signal'::text, 'recorded'::text])));
ALTER TABLE public.ceo_improvement ADD CONSTRAINT ceo_improvement_proposal_check CHECK ((btrim(proposal) <> ''::text));
ALTER TABLE public.ceo_improvement ADD CONSTRAINT ceo_improvement_source_kind_check CHECK ((source_kind = ANY (ARRAY['recurring_miss'::text, 'month_miss'::text, 'lesson'::text, 'recurring_finding'::text, 'binding_constraint'::text, 'marketing_plan_late'::text, 'seat_audit'::text, 'funnel_stage_drop'::text, 'weekly_review'::text, 'self_review'::text, 'market_report'::text])));
ALTER TABLE public.ceo_improvement ADD CONSTRAINT ceo_improvement_status_check CHECK ((status = ANY (ARRAY['open'::text, 'assigned'::text, 'done'::text, 'dropped'::text])));
ALTER TABLE public.ceo_knowledge ADD CONSTRAINT ceo_knowledge_authority_ck CHECK ((authority_effect = 'none'::text));
ALTER TABLE public.ceo_knowledge ADD CONSTRAINT ceo_knowledge_exec_ck CHECK ((external_execution_enabled = false));
ALTER TABLE public.ceo_knowledge ADD CONSTRAINT ceo_knowledge_scope_ck CHECK ((company_scope = ANY (ARRAY['generic'::text, 'industry'::text])));
ALTER TABLE public.ceo_launch_gate ADD CONSTRAINT ceo_launch_gate_decision_check CHECK ((decision = ANY (ARRAY['january_holds'::text, 'launch_waits'::text])));
ALTER TABLE public.ceo_launch_gate ADD CONSTRAINT ceo_launch_gate_verdict_check CHECK ((verdict = ANY (ARRAY['ready'::text, 'not_ready'::text, 'not_measurable'::text])));
ALTER TABLE public.ceo_mandate ADD CONSTRAINT ceo_mandate_clause_key_check CHECK ((clause_key ~ '^[a-z0-9_]+$'::text));
ALTER TABLE public.ceo_mandate ADD CONSTRAINT ceo_mandate_kind_check CHECK ((kind = ANY (ARRAY['target'::text, 'cost_ceiling'::text, 'hard_rule'::text, 'decision_right'::text, 'reporting'::text])));
ALTER TABLE public.ceo_mandate ADD CONSTRAINT ceo_mandate_statement_check CHECK ((btrim(statement) <> ''::text));
ALTER TABLE public.ceo_market_report ADD CONSTRAINT ceo_market_report_audience_check CHECK ((audience = 'internal'::text));
ALTER TABLE public.ceo_month_close ADD CONSTRAINT ceo_month_close_verdict_check CHECK ((verdict = ANY (ARRAY['clean'::text, 'gaps'::text])));
ALTER TABLE public.ceo_month_report ADD CONSTRAINT ceo_month_report_month_check CHECK ((EXTRACT(day FROM month) = (1)::numeric));
ALTER TABLE public.ceo_plan ADD CONSTRAINT ceo_plan_decided_by_check CHECK ((decided_by = ANY (ARRAY['plan_c_code'::text, 'model'::text])));
ALTER TABLE public.ceo_plan_action ADD CONSTRAINT ceo_plan_action_action_check CHECK ((btrim(action) <> ''::text));
ALTER TABLE public.ceo_plan_action ADD CONSTRAINT ceo_plan_action_check CHECK ((to_month >= from_month));
ALTER TABLE public.ceo_plan_action ADD CONSTRAINT ceo_plan_action_from_month_check CHECK ((EXTRACT(day FROM from_month) = (1)::numeric));
ALTER TABLE public.ceo_plan_month ADD CONSTRAINT ceo_plan_month_fee_aed_check CHECK ((fee_aed >= (0)::numeric));
ALTER TABLE public.ceo_plan_month ADD CONSTRAINT ceo_plan_month_inquiries_check CHECK ((inquiries >= 0));
ALTER TABLE public.ceo_plan_month ADD CONSTRAINT ceo_plan_month_invites_check CHECK ((invites >= 0));
ALTER TABLE public.ceo_plan_month ADD CONSTRAINT ceo_plan_month_month_check CHECK ((EXTRACT(day FROM month) = (1)::numeric));
ALTER TABLE public.ceo_plan_month ADD CONSTRAINT ceo_plan_month_registered_check CHECK ((registered >= 0));
ALTER TABLE public.ceo_plan_month ADD CONSTRAINT ceo_plan_month_reveals_check CHECK ((reveals >= 0));
ALTER TABLE public.ceo_plan_month ADD CONSTRAINT ceo_plan_month_verified_check CHECK ((verified >= 0));
ALTER TABLE public.ceo_review ADD CONSTRAINT ceo_review_kind_check CHECK ((kind = ANY (ARRAY['management_review'::text, 'pricing_monitor'::text, 'target_forecast'::text])));
ALTER TABLE public.ceo_seat_directive ADD CONSTRAINT ceo_seat_directive_month_check CHECK ((EXTRACT(day FROM month) = (1)::numeric));
ALTER TABLE public.ceo_seat_directive ADD CONSTRAINT ceo_seat_directive_status_check CHECK ((status = ANY (ARRAY['issued'::text, 'met'::text, 'missed'::text, 'not_measurable'::text])));
ALTER TABLE public.ceo_standing_grant ADD CONSTRAINT ceo_standing_grant_issuer CHECK ((issued_by = 'ceo'::text));
ALTER TABLE public.ceo_strategy_memo ADD CONSTRAINT ceo_strategy_memo_month_check CHECK ((month = (date_trunc('month'::text, (month)::timestamp with time zone))::date));
ALTER TABLE public.ceo_supplier_channel ADD CONSTRAINT ceo_supplier_channel_state_check CHECK ((state = ANY (ARRAY['not_measured'::text, 'on'::text, 'paused'::text, 'ready'::text, 'blocked'::text, 'missing'::text])));
ALTER TABLE public.ceo_task ADD CONSTRAINT ceo_task_blocked_says_why CHECK (((state <> 'blocked'::text) OR (COALESCE(btrim(blocked_reason), ''::text) <> ''::text)));
ALTER TABLE public.ceo_task ADD CONSTRAINT ceo_task_done_shows_evidence CHECK (((state <> 'done'::text) OR (COALESCE(btrim(evidence), ''::text) <> ''::text)));
ALTER TABLE public.ceo_weekly_report ADD CONSTRAINT ceo_weekly_report_status_check CHECK ((status = ANY (ARRAY['generated'::text, 'partial'::text, 'delivered'::text, 'delivery_failed'::text])));
ALTER TABLE public.ceo_year_plan ADD CONSTRAINT ceo_year_plan_business_accounts_check CHECK ((business_accounts >= 0));
ALTER TABLE public.ceo_year_plan ADD CONSTRAINT ceo_year_plan_cost_ceiling_aed_check CHECK ((cost_ceiling_aed > (0)::numeric));
ALTER TABLE public.ceo_year_plan ADD CONSTRAINT ceo_year_plan_fee_aed_check CHECK ((fee_aed >= (0)::numeric));
ALTER TABLE public.ceo_year_plan ADD CONSTRAINT ceo_year_plan_fee_cum_aed_check CHECK ((fee_cum_aed >= (0)::numeric));
ALTER TABLE public.ceo_year_plan ADD CONSTRAINT ceo_year_plan_month_check CHECK ((EXTRACT(day FROM month) = (1)::numeric));
ALTER TABLE public.ceo_year_plan ADD CONSTRAINT ceo_year_plan_paying_check CHECK ((paying >= 0));
ALTER TABLE public.ceo_year_plan ADD CONSTRAINT ceo_year_plan_quotes_check CHECK ((quotes >= 0));
ALTER TABLE public.ceo_year_plan ADD CONSTRAINT ceo_year_plan_requests_check CHECK ((requests >= 0));
ALTER TABLE public.ceo_year_plan ADD CONSTRAINT ceo_year_plan_reveals_check CHECK ((reveals >= 0));
ALTER TABLE public.ceo_year_plan ADD CONSTRAINT ceo_year_plan_subscription_aed_check CHECK ((subscription_aed >= (0)::numeric));
ALTER TABLE public.ceo_year_plan ADD CONSTRAINT ceo_year_plan_verified_added_check CHECK ((verified_added >= 0));
ALTER TABLE public.ceo_year_plan ADD CONSTRAINT ceo_year_plan_verified_check CHECK ((verified >= 0));
ALTER TABLE public.ceo_year_plan_milestone ADD CONSTRAINT ceo_year_plan_milestone_verified_check CHECK ((verified >= 0));
ALTER TABLE public.challenge_record ADD CONSTRAINT challenge_record_founder_response_check CHECK ((founder_response = ANY (ARRAY['accepted'::text, 'overruled'::text, 'modified'::text, NULL::text])));
ALTER TABLE public.challenge_record ADD CONSTRAINT challenge_record_stance_check CHECK ((stance = ANY (ARRAY['support'::text, 'concern'::text, 'recommend_against'::text])));
ALTER TABLE public.channel_directive ADD CONSTRAINT channel_directive_actor_type_check CHECK ((actor_type = ANY (ARRAY['supplier'::text, 'customer'::text])));
ALTER TABLE public.charge_audit ADD CONSTRAINT charge_audit_check CHECK (((resolved_at IS NULL) OR (COALESCE(btrim(resolution), ''::text) <> ''::text)));
ALTER TABLE public.company_calendar ADD CONSTRAINT company_calendar_kind_check CHECK ((kind = ANY (ARRAY['public_holiday'::text, 'religious'::text, 'compliance'::text, 'seasonality'::text, 'industry_event'::text, 'internal_rhythm'::text])));
ALTER TABLE public.company_financial_stance ADD CONSTRAINT company_financial_stance_budget_mode_check CHECK ((budget_mode = ANY (ARRAY['unlimited_until_profitable'::text, 'budgeted'::text])));
ALTER TABLE public.company_financial_stance ADD CONSTRAINT company_financial_stance_id_check CHECK ((id = 1));
ALTER TABLE public.company_review_ask ADD CONSTRAINT company_review_ask_status_check CHECK ((status = ANY (ARRAY['asked'::text, 'waiting_link'::text])));
ALTER TABLE public.company_vision ADD CONSTRAINT company_vision_singleton CHECK ((id = 1));
ALTER TABLE public.competitor ADD CONSTRAINT competitor_kind_check CHECK ((kind = ANY (ARRAY['marketplace'::text, 'directory'::text, 'tender_portal'::text, 'global_platform'::text, 'incumbent_behaviour'::text, 'adjacent'::text])));
ALTER TABLE public.competitor ADD CONSTRAINT competitor_threat_level_check CHECK ((threat_level = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text])));
ALTER TABLE public.competitor_scan ADD CONSTRAINT competitor_scan_page_kind_check CHECK ((page_kind = ANY (ARRAY['home'::text, 'pricing'::text])));
ALTER TABLE public.competitor_scan ADD CONSTRAINT competitor_scan_status_check CHECK ((status = ANY (ARRAY['fetching'::text, 'failed'::text, 'unchanged'::text, 'fetched'::text, 'reasoned'::text])));
ALTER TABLE public.complaint_tickets ADD CONSTRAINT complaint_tickets_check CHECK (((status <> 'final_response'::text) OR ((final_response_at IS NOT NULL) AND (COALESCE(btrim(final_response), ''::text) <> ''::text))));
ALTER TABLE public.complaint_tickets ADD CONSTRAINT complaint_tickets_email_check CHECK (((email = lower(email)) AND (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'::text)));
ALTER TABLE public.complaint_tickets ADD CONSTRAINT complaint_tickets_handled_by_check CHECK ((handled_by = ANY (ARRAY['customer_support'::text, 'ceo'::text])));
ALTER TABLE public.complaint_tickets ADD CONSTRAINT complaint_tickets_status_check CHECK ((status = ANY (ARRAY['acknowledged'::text, 'in_review'::text, 'final_response'::text])));
ALTER TABLE public.complaint_tickets ADD CONSTRAINT complaint_tickets_ticket_no_check CHECK ((ticket_no ~ '^QD-C-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{6}$'::text));
ALTER TABLE public.contact_duplicate_group ADD CONSTRAINT contact_duplicate_group_status_check CHECK ((status = ANY (ARRAY['reported'::text, 'handed_to_seat'::text, 'merged'::text])));
ALTER TABLE public.contact_merge_audit ADD CONSTRAINT contact_merge_audit_kind_check CHECK ((kind = ANY (ARRAY['lead'::text, 'customer'::text])));
ALTER TABLE public.control_mode_action ADD CONSTRAINT control_mode_action_classification_chk CHECK ((classification = ANY (ARRAY['read_only'::text, 'mutating'::text, 'mode_control'::text, 'founder_gated'::text])));
ALTER TABLE public.control_mode_action ADD CONSTRAINT control_mode_action_founder_gated_pinned CHECK (((classification <> 'founder_gated'::text) OR (action = ANY (ARRAY['founder_command'::text, 'founder_command_control'::text, 'founder_command_clarify'::text]))));
ALTER TABLE public.control_mode_action ADD CONSTRAINT control_mode_action_mode_control_pinned CHECK (((classification <> 'mode_control'::text) OR (action = ANY (ARRAY['control_mode_status'::text, 'control_mode_open'::text, 'control_mode_close'::text, 'control_mode_challenge'::text]))));
ALTER TABLE public.control_mode_challenge ADD CONSTRAINT control_mode_challenge_purpose_chk CHECK ((purpose = 'control_mode'::text));
ALTER TABLE public.control_mode_session ADD CONSTRAINT control_mode_session_mfa_method_ck CHECK ((mfa_method = 'control_mode_challenge'::text));
ALTER TABLE public.critical_capability ADD CONSTRAINT critical_capability_test_kind_check CHECK ((test_kind = ANY (ARRAY['suite'::text, 'rpc_selftest'::text, 'scenario'::text, 'none'::text])));
ALTER TABLE public.crm_stages ADD CONSTRAINT crm_stages_probability_check CHECK (((probability >= 0) AND (probability <= 100)));
ALTER TABLE public.customer_calls ADD CONSTRAINT customer_calls_direction_check CHECK ((direction = ANY (ARRAY['inbound'::text, 'outbound'::text])));
ALTER TABLE public.customer_calls ADD CONSTRAINT customer_calls_status_check CHECK ((status = ANY (ARRAY['completed'::text, 'missed'::text, 'voicemail'::text, 'failed'::text, 'scheduled'::text])));
ALTER TABLE public.customer_followup ADD CONSTRAINT customer_followup_hired_check CHECK ((hired = ANY (ARRAY['yes'::text, 'no'::text, 'not_yet'::text])));
ALTER TABLE public.customer_followup ADD CONSTRAINT customer_followup_lang_check CHECK ((lang = ANY (ARRAY['en'::text, 'ar'::text])));
ALTER TABLE public.customer_followup ADD CONSTRAINT customer_followup_stage_check CHECK ((stage = ANY (ARRAY['day_three'::text, 'day_fourteen'::text])));
ALTER TABLE public.customer_followup ADD CONSTRAINT customer_followup_stars_check CHECK (((stars >= 1) AND (stars <= 5)));
ALTER TABLE public.customer_spec_guide ADD CONSTRAINT customer_spec_guide_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'published'::text])));
ALTER TABLE public.customer_support_case_review ADD CONSTRAINT customer_support_case_review_knowledge_filed_check CHECK ((knowledge_filed >= 0));
ALTER TABLE public.customer_support_data_request ADD CONSTRAINT customer_support_data_request_identity_status_check CHECK ((identity_status = ANY (ARRAY['pending'::text, 'verified'::text, 'failed'::text])));
ALTER TABLE public.customer_support_data_request ADD CONSTRAINT customer_support_data_request_kind_check CHECK ((kind = ANY (ARRAY['access'::text, 'correction'::text, 'erasure'::text, 'objection'::text])));
ALTER TABLE public.customer_support_data_request ADD CONSTRAINT customer_support_data_request_status_check CHECK ((status = ANY (ARRAY['open'::text, 'fulfilled'::text, 'refused'::text])));
ALTER TABLE public.customer_support_duty_message ADD CONSTRAINT customer_support_duty_message_stage_check CHECK ((stage ~ '^[a-z_]+\.[a-z_]+$'::text));
ALTER TABLE public.customer_support_duty_message ADD CONSTRAINT customer_support_duty_message_subject_key_check CHECK ((btrim(subject_key) <> ''::text));
ALTER TABLE public.customer_support_inbound_drive ADD CONSTRAINT customer_support_inbound_drive_channel_check CHECK ((channel = ANY (ARRAY['email'::text, 'whatsapp'::text])));
ALTER TABLE public.customer_support_monthly_review ADD CONSTRAINT customer_support_monthly_review_month_check CHECK ((month = (date_trunc('month'::text, (month)::timestamp with time zone))::date));
ALTER TABLE public.customer_support_voc_month ADD CONSTRAINT customer_support_voc_month_month_check CHECK ((month = (date_trunc('month'::text, (month)::timestamp with time zone))::date));
ALTER TABLE public.customer_support_voice_owed ADD CONSTRAINT customer_support_voice_owed_draft_check CHECK ((btrim(draft) <> ''::text));
ALTER TABLE public.customer_support_voice_owed ADD CONSTRAINT customer_support_voice_owed_lang_check CHECK ((lang = ANY (ARRAY['en'::text, 'ar'::text])));
ALTER TABLE public.customer_support_voice_owed ADD CONSTRAINT customer_support_voice_owed_situation_check CHECK ((btrim(situation) <> ''::text));
ALTER TABLE public.customer_support_voice_owed ADD CONSTRAINT customer_support_voice_owed_stage_check CHECK ((stage ~ '^[a-z_]+\.[a-z_]+$'::text));
ALTER TABLE public.customer_support_voice_owed ADD CONSTRAINT customer_support_voice_owed_subject_key_check CHECK ((btrim(subject_key) <> ''::text));
ALTER TABLE public.customer_support_voice_owed ADD CONSTRAINT customer_support_voice_owed_to_role_check CHECK ((to_role = ANY (ARRAY['customer'::text, 'supplier'::text])));
ALTER TABLE public.customer_support_voice_owed ADD CONSTRAINT customer_support_voice_owed_voice_key_check CHECK ((btrim(voice_key) <> ''::text));
ALTER TABLE public.customer_support_voice_owed ADD CONSTRAINT customer_support_voice_owed_written_by_check CHECK ((written_by = ANY (ARRAY['model'::text, 'outage_fallback'::text])));
ALTER TABLE public.customers ADD CONSTRAINT customers_locale_chk CHECK ((locale = ANY (ARRAY['en'::text, 'ar'::text]))) NOT VALID;
ALTER TABLE public.customers ADD CONSTRAINT customers_whatsapp_opt_known CHECK (((whatsapp_opt IS NULL) OR (whatsapp_opt = ANY (ARRAY['same'::text, 'other'::text, 'none'::text]))));
ALTER TABLE public.customers ADD CONSTRAINT customers_whatsapp_phone_is_verified CHECK (((whatsapp_phone IS NULL) OR (whatsapp_verified_at IS NOT NULL)));
ALTER TABLE public.decision_review_request ADD CONSTRAINT decision_review_a_person_request_is_never_decided_by_a_model CHECK (((decision_type <> 'person'::text) OR ((status <> 'decided'::text) AND (reviewer_model IS NULL))));
ALTER TABLE public.decision_review_request ADD CONSTRAINT decision_review_decided_has_its_verdict CHECK (((status <> 'decided'::text) OR ((verdict IS NOT NULL) AND (reviewer_model IS NOT NULL) AND (reviewer_seat IS NOT NULL) AND (btrim(COALESCE(verdict_reason, ''::text)) <> ''::text) AND (decided_at IS NOT NULL))));
ALTER TABLE public.decision_review_request ADD CONSTRAINT decision_review_founder_only_for_an_explicit_person_request CHECK ((((founder_notified IS NULL) AND (status <> 'with_founder'::text)) OR ((decision_type = 'person'::text) AND (channel = ANY (ARRAY['whatsapp'::text, 'site_chat'::text, 'email'::text])) AND (status = 'with_founder'::text))));
ALTER TABLE public.decision_review_request ADD CONSTRAINT decision_review_is_decided_by_a_different_model_family CHECK (((reviewer_model IS NULL) OR (split_part(reviewer_model, '/'::text, 1) IS DISTINCT FROM COALESCE(NULLIF(split_part(original_model, '/'::text, 1), ''::text), 'deterministic'::text))));
ALTER TABLE public.decision_review_request ADD CONSTRAINT decision_review_request_channel_check CHECK ((channel = ANY (ARRAY['whatsapp'::text, 'site_chat'::text, 'email'::text])));
ALTER TABLE public.decision_review_request ADD CONSTRAINT decision_review_request_request_text_check CHECK ((btrim(request_text) <> ''::text));
ALTER TABLE public.decision_review_request ADD CONSTRAINT decision_review_request_requester_check CHECK ((btrim(requester) <> ''::text));
ALTER TABLE public.decision_review_request ADD CONSTRAINT decision_review_request_status_check CHECK ((status = ANY (ARRAY['open'::text, 'decided'::text, 'with_founder'::text])));
ALTER TABLE public.decision_review_request ADD CONSTRAINT decision_review_request_verdict_check CHECK ((verdict = ANY (ARRAY['upheld'::text, 'overturned'::text, 'amended'::text])));
ALTER TABLE public.deliverability_test ADD CONSTRAINT deliverability_test_check CHECK ((marker = ('id:'::text || test_id)));
ALTER TABLE public.deliverability_test ADD CONSTRAINT deliverability_test_check1 CHECK (((verdict = 'pending'::text) OR (decided_at IS NOT NULL)));
ALTER TABLE public.deliverability_test ADD CONSTRAINT deliverability_test_lane_check CHECK ((lane = 'm365'::text));
ALTER TABLE public.deliverability_test ADD CONSTRAINT deliverability_test_provider_check CHECK ((provider = 'glockapps'::text));
ALTER TABLE public.deliverability_test ADD CONSTRAINT deliverability_test_recorded_is_complete CHECK (((recorded_at IS NULL) OR ((tested_at IS NOT NULL) AND (recorded_by IS NOT NULL) AND (from_address ~~ '%@%'::text) AND (source = ANY (ARRAY['glockapps_connector'::text, 'glockapps_api'::text])) AND (class_rates ?& ARRAY['microsoft'::text, 'google'::text, 'yahoo_aol'::text, 'other'::text, 'overall'::text]))));
ALTER TABLE public.deliverability_test ADD CONSTRAINT deliverability_test_status_check CHECK ((status = ANY (ARRAY['seeds_queued'::text, 'collecting'::text, 'complete'::text, 'incomplete'::text, 'failed'::text])));
ALTER TABLE public.deliverability_test ADD CONSTRAINT deliverability_test_test_id_check CHECK ((test_id ~ '^[0-9A-Za-z:_-]{6,64}$'::text));
ALTER TABLE public.deliverability_test ADD CONSTRAINT deliverability_test_verdict_check CHECK ((verdict = ANY (ARRAY['pending'::text, 'pass'::text, 'fail'::text, 'incomplete'::text])));
ALTER TABLE public.deliverability_test_provider ADD CONSTRAINT deliverability_test_provider_check1 CHECK ((seeds = (((inbox + spam) + tabs) + missing)));
ALTER TABLE public.deliverability_test_provider ADD CONSTRAINT deliverability_test_provider_class_known CHECK (((provider_class IS NULL) OR (provider_class = ANY (ARRAY['microsoft'::text, 'google'::text, 'yahoo_aol'::text, 'other'::text]))));
ALTER TABLE public.deliverability_test_provider ADD CONSTRAINT deliverability_test_provider_inbox_check CHECK ((inbox >= 0));
ALTER TABLE public.deliverability_test_provider ADD CONSTRAINT deliverability_test_provider_missing_check CHECK ((missing >= 0));
ALTER TABLE public.deliverability_test_provider ADD CONSTRAINT deliverability_test_provider_seeds_check CHECK ((seeds >= 0));
ALTER TABLE public.deliverability_test_provider ADD CONSTRAINT deliverability_test_provider_spam_check CHECK ((spam >= 0));
ALTER TABLE public.deliverability_test_provider ADD CONSTRAINT deliverability_test_provider_tabs_check CHECK ((tabs >= 0));
ALTER TABLE public.demand_forecast ADD CONSTRAINT demand_forecast_basis_check CHECK ((basis = 'estimate'::text));
ALTER TABLE public.demand_search ADD CONSTRAINT demand_search_source_check CHECK ((source = ANY (ARRAY['route_brief'::text, 'fixture'::text])));
ALTER TABLE public.department_objective ADD CONSTRAINT department_objective_status_check CHECK ((status = ANY (ARRAY['active'::text, 'superseded'::text, 'achieved'::text, 'dropped'::text])));
ALTER TABLE public.dept_knowledge_alias ADD CONSTRAINT dept_knowledge_alias_alias_kind_check CHECK ((alias_kind = ANY (ARRAY['dept'::text, 'module'::text])));
ALTER TABLE public.duty_pause ADD CONSTRAINT duty_pause_paused_by_check CHECK ((length(btrim(paused_by)) > 0));
ALTER TABLE public.duty_pause ADD CONSTRAINT duty_pause_reason_check CHECK ((length(btrim(reason)) > 0));
ALTER TABLE public.email_platform_domain ADD CONSTRAINT email_platform_domain_domain_check CHECK (((domain = lower(btrim(domain))) AND (domain ~~ '%.%'::text)));
ALTER TABLE public.email_platform_domain ADD CONSTRAINT email_platform_domain_kind_check CHECK ((kind = ANY (ARRAY['directory'::text, 'marketplace'::text, 'job_board'::text, 'publisher'::text, 'hosting'::text, 'site_builder'::text, 'template_vendor'::text, 'web_agency'::text, 'placeholder'::text, 'disposable'::text, 'typo'::text])));
ALTER TABLE public.employee_kpi ADD CONSTRAINT employee_kpi_class_check CHECK (((kpi_class IS NULL) OR (kpi_class = ANY (ARRAY['activity'::text, 'leading_indicator'::text, 'quality_metric'::text, 'conversion'::text, 'revenue'::text, 'cost'::text, 'risk'::text]))));
ALTER TABLE public.event_assessment ADD CONSTRAINT event_assessment_severity_check CHECK ((severity = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text])));
ALTER TABLE public.evolution_proposal ADD CONSTRAINT evolution_proposal_change_class_check CHECK ((change_class = ANY (ARRAY['knowledge'::text, 'process'::text, 'code'::text, 'policy'::text, 'model_routing'::text, 'org'::text, 'prompting'::text])));
ALTER TABLE public.evolution_proposal ADD CONSTRAINT evolution_proposal_status_check CHECK ((status = ANY (ARRAY['proposed'::text, 'accepted'::text, 'rejected'::text, 'implemented'::text])));
ALTER TABLE public.evolution_proposal ADD CONSTRAINT evolution_proposal_trigger_kind_check CHECK ((trigger_kind = ANY (ARRAY['repeated_failure'::text, 'metric_off_target'::text, 'cost_anomaly'::text, 'manual'::text, 'audit_gap'::text, 'review_rejection'::text, 'prompt_unmeasured'::text])));
ALTER TABLE public.expense_entries ADD CONSTRAINT expense_entries_amount_money_ck CHECK (((amount >= (0)::numeric) AND (amount = round(amount, 2))));
ALTER TABLE public.expense_entries ADD CONSTRAINT expense_entries_doc_kind_ck CHECK (((doc_kind IS NULL) OR (doc_kind = ANY (ARRAY['vendor_document'::text, 'email_print'::text, 'founder_statement'::text]))));
ALTER TABLE public.expense_entries ADD CONSTRAINT expense_entries_founder_statement_ck CHECK (((doc_kind IS DISTINCT FROM 'founder_statement'::text) OR ((source = 'founder_reported'::text) AND (COALESCE(btrim(doc_note), ''::text) <> ''::text))));
ALTER TABLE public.expense_entries ADD CONSTRAINT expense_entries_read_as_check CHECK (((read_as IS NULL) OR (read_as = ANY (ARRAY['receipt_monthly'::text, 'receipt_annual'::text, 'receipt_one_off'::text, 'meta_ads_invoice'::text, 'renewal'::text]))));
ALTER TABLE public.expense_sender_reading ADD CONSTRAINT expense_sender_reading_sender_check CHECK (((sender = lower(sender)) AND (sender ~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$'::text)));
ALTER TABLE public.expenses ADD CONSTRAINT expenses_amount_money_ck CHECK (((amount >= (0)::numeric) AND (amount = round(amount, 2))));
ALTER TABLE public.feedback ADD CONSTRAINT feedback_kind_scale_ck CHECK (((kind IS NULL) OR ((kind = 'csat'::text) AND ((rating >= (1)::numeric) AND (rating <= (5)::numeric))) OR ((kind = 'ces'::text) AND ((rating >= (1)::numeric) AND (rating <= (7)::numeric)))));
ALTER TABLE public.field_definition ADD CONSTRAINT fd_shared_carries_no_trade CHECK (((scope <> 'shared'::text) OR (trade_key IS NULL)));
ALTER TABLE public.field_definition ADD CONSTRAINT fd_subset_carries_no_trade CHECK (((scope <> 'trade_subset'::text) OR (trade_key IS NULL)));
ALTER TABLE public.field_definition ADD CONSTRAINT fd_trade_specific_has_trade CHECK (((scope <> 'trade_specific'::text) OR (trade_key IS NOT NULL)));
ALTER TABLE public.field_definition ADD CONSTRAINT field_definition_review_status_check CHECK ((review_status = ANY (ARRAY['approved'::text, 'question_for_founder'::text])));
ALTER TABLE public.field_definition ADD CONSTRAINT field_definition_scope_check CHECK ((scope = ANY (ARRAY['shared'::text, 'trade_specific'::text, 'trade_subset'::text])));
ALTER TABLE public.file_scan ADD CONSTRAINT file_scan_verdict_check CHECK ((verdict = ANY (ARRAY['clean'::text, 'malicious'::text, 'suspicious'::text, 'unknown'::text, 'unavailable'::text])));
ALTER TABLE public.founder_hold ADD CONSTRAINT founder_hold_until_when_check CHECK ((btrim(until_when) <> ''::text));
ALTER TABLE public.founder_hold ADD CONSTRAINT founder_hold_what_is_held_check CHECK ((btrim(what_is_held) <> ''::text));
ALTER TABLE public.founder_instruction ADD CONSTRAINT founder_instruction_status_check CHECK ((status = ANY (ARRAY['open'::text, 'done'::text, 'deferred_by_founder'::text, 'superseded'::text, 'refused'::text, 'standing'::text])));
ALTER TABLE public.free_email_domain ADD CONSTRAINT free_email_domain_domain_check CHECK (((domain = lower(btrim(domain))) AND (domain ~ '^[a-z0-9.-]+[.][a-z]{2,}$'::text)));
ALTER TABLE public.function_owner ADD CONSTRAINT function_owner_moves_elsewhere_ck CHECK (((moves_to IS NULL) OR (moves_to <> owner)));
ALTER TABLE public.function_owner ADD CONSTRAINT function_owner_moves_to_ck CHECK (((moves_to IS NULL) = (moves_to_note IS NULL)));
ALTER TABLE public.function_owner ADD CONSTRAINT function_owner_note_ck CHECK ((btrim(note) <> ''::text));
ALTER TABLE public.function_owner ADD CONSTRAINT function_owner_owner_ck CHECK ((owner = ANY (ARRAY['ceo'::text, 'customer_support'::text, 'sales_engineer'::text, 'accountant'::text, 'it_engineer'::text, 'marketing'::text, 'website'::text])));
ALTER TABLE public.gl_account_funnel_stage ADD CONSTRAINT gl_account_funnel_stage_stage_check CHECK ((stage ~ '^[a-z_]+$'::text));
ALTER TABLE public.gl_accounts ADD CONSTRAINT gl_accounts_normal_balance_check CHECK ((normal_balance = ANY (ARRAY['D'::bpchar, 'C'::bpchar])));
ALTER TABLE public.gl_accounts ADD CONSTRAINT gl_accounts_type_check CHECK ((type = ANY (ARRAY['asset'::text, 'liability'::text, 'equity'::text, 'revenue'::text, 'expense'::text, 'other_income'::text])));
ALTER TABLE public.gl_journal ADD CONSTRAINT gl_journal_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'posted'::text, 'void'::text])));
ALTER TABLE public.gl_journal_lines ADD CONSTRAINT gl_journal_lines_credit_check CHECK ((credit >= (0)::numeric));
ALTER TABLE public.gl_journal_lines ADD CONSTRAINT gl_journal_lines_debit_check CHECK ((debit >= (0)::numeric));
ALTER TABLE public.gl_journal_lines ADD CONSTRAINT gl_line_one_side CHECK (((debit = (0)::numeric) <> (credit = (0)::numeric)));
ALTER TABLE public.gl_prior_period_adjustment ADD CONSTRAINT gl_prior_period_adjustment_check CHECK ((posted_on > original_date));
ALTER TABLE public.gl_prior_period_adjustment ADD CONSTRAINT gl_prior_period_adjustment_closed_month_check CHECK ((closed_month = (date_trunc('month'::text, (closed_month)::timestamp with time zone))::date));
ALTER TABLE public.governance_policy ADD CONSTRAINT governance_policy_domain_check CHECK ((domain = ANY (ARRAY['ethics'::text, 'privacy'::text, 'audit'::text, 'retention'::text, 'approval'::text, 'security'::text, 'compliance'::text])));
ALTER TABLE public.governance_policy ADD CONSTRAINT governance_policy_enforcement_check CHECK ((enforcement = ANY (ARRAY['code'::text, 'database'::text, 'process'::text, 'declared'::text])));
ALTER TABLE public.governance_sensitive ADD CONSTRAINT governance_sensitive_key_check CHECK ((btrim(key) <> ''::text));
ALTER TABLE public.governance_sensitive ADD CONSTRAINT governance_sensitive_reason_check CHECK ((btrim(reason) <> ''::text));
ALTER TABLE public.governance_sensitive ADD CONSTRAINT governance_sensitive_subject_check CHECK ((subject = ANY (ARRAY['agent'::text, 'kind'::text])));
ALTER TABLE public.handoff_contract ADD CONSTRAINT handoff_contract_closure_criteria_check CHECK ((cardinality(closure_criteria) >= 1));
ALTER TABLE public.handoff_contract ADD CONSTRAINT handoff_contract_escalation_conditions_check CHECK ((btrim(escalation_conditions) <> ''::text));
ALTER TABLE public.handoff_contract ADD CONSTRAINT handoff_contract_evidence_check CHECK ((jsonb_typeof(evidence) = 'array'::text));
ALTER TABLE public.handoff_contract ADD CONSTRAINT handoff_contract_purpose_check CHECK ((length(btrim(purpose)) >= 10));
ALTER TABLE public.handoff_contract ADD CONSTRAINT handoff_contract_requested_action_check CHECK ((length(btrim(requested_action)) >= 10));
ALTER TABLE public.handoff_contract ADD CONSTRAINT handoff_contract_return_status_check CHECK ((return_status = ANY (ARRAY['accepted'::text, 'rejected'::text, 'rejected_incomplete'::text, 'returned_for_correction'::text, 'closed'::text])));
ALTER TABLE public.handoff_contract ADD CONSTRAINT handoff_contract_status_check CHECK ((status = ANY (ARRAY['open'::text, 'accepted'::text, 'rejected'::text, 'returned'::text, 'closed'::text])));
ALTER TABLE public.handoff_contract ADD CONSTRAINT handoff_contract_to_role_check CHECK ((btrim(to_role) <> ''::text));
ALTER TABLE public.inquiries ADD CONSTRAINT inquiries_lang_chk CHECK (((lang IS NULL) OR (lang = ANY (ARRAY['en'::text, 'ar'::text]))));
ALTER TABLE public.inquiry_answer ADD CONSTRAINT inquiry_answer_scope_check CHECK ((scope = ANY (ARRAY['inquiry_shared'::text, 'trade_specific'::text, 'trade_subset'::text])));
ALTER TABLE public.inquiry_answer ADD CONSTRAINT inquiry_answer_source_kind_check CHECK ((source_kind = ANY (ARRAY['customer'::text, 'document'::text, 'deterministic'::text, 'model'::text])));
ALTER TABLE public.inquiry_answer_conflict ADD CONSTRAINT iac_resolution_is_explained CHECK (((resolved_at IS NULL) OR ((COALESCE(btrim(resolved_by), ''::text) <> ''::text) AND (COALESCE(btrim(resolution_reason), ''::text) <> ''::text))));
ALTER TABLE public.inquiry_answer_conflict ADD CONSTRAINT inquiry_answer_conflict_blocking_scope_check CHECK ((blocking_scope = ANY (ARRAY['shared'::text, 'trade'::text])));
ALTER TABLE public.inquiry_gate_required ADD CONSTRAINT inquiry_gate_required_level_check CHECK ((level = ANY (ARRAY['group'::text, 'workstream'::text])));
ALTER TABLE public.inquiry_matches ADD CONSTRAINT inquiry_matches_similarity_fraction CHECK (((similarity IS NULL) OR ((similarity >= (0)::numeric) AND (similarity <= (1)::numeric))));
ALTER TABLE public.inquiry_scope_disposition ADD CONSTRAINT inquiry_scope_disposition_confirmation_status_check CHECK ((confirmation_status = ANY (ARRAY['inferred'::text, 'confirmed'::text, 'rejected'::text])));
ALTER TABLE public.inquiry_scope_disposition ADD CONSTRAINT inquiry_scope_disposition_source_kind_check CHECK ((source_kind = ANY (ARRAY['customer_text'::text, 'structured_answer'::text, 'document_extraction'::text])));
ALTER TABLE public.inquiry_trade_candidate ADD CONSTRAINT inquiry_trade_candidate_confidence_check CHECK (((evidence_score >= (0)::numeric) AND (evidence_score <= (1)::numeric)));
ALTER TABLE public.inquiry_trade_candidate ADD CONSTRAINT inquiry_trade_candidate_evidence_source_check CHECK ((evidence_source = ANY (ARRAY['structured_answer'::text, 'customer_text'::text, 'scope_rule'::text, 'alias'::text, 'document_extraction'::text])));
ALTER TABLE public.inquiry_trade_candidate ADD CONSTRAINT inquiry_trade_candidate_score_basis_check CHECK ((score_basis = ANY (ARRAY['rule_weight_provisional'::text, 'calibrated_frequency'::text, 'measured_probability'::text])));
ALTER TABLE public.inquiry_trade_candidate ADD CONSTRAINT inquiry_trade_candidate_status_check CHECK ((status = ANY (ARRAY['proposed'::text, 'confirmed'::text, 'rejected'::text, 'inactive'::text])));
ALTER TABLE public.inquiry_trade_candidate_evidence ADD CONSTRAINT inquiry_trade_candidate_evidence_score_basis_check CHECK ((score_basis = ANY (ARRAY['rule_weight_provisional'::text, 'calibrated_frequency'::text, 'measured_probability'::text])));
ALTER TABLE public.inquiry_workstream_group ADD CONSTRAINT inquiry_workstream_group_rfq_mode_check CHECK ((rfq_mode = ANY (ARRAY['coordinated'::text, 'linked'::text])));
ALTER TABLE public.intake_trade_taxonomy ADD CONSTRAINT intake_trade_taxonomy_trade_codes_check CHECK ((cardinality(trade_codes) > 0));
ALTER TABLE public.internal_credential ADD CONSTRAINT internal_credential_context_check CHECK ((length(btrim(context)) > 2));
ALTER TABLE public.internal_credential ADD CONSTRAINT internal_credential_scope_check CHECK ((array_length(scope, 1) >= 1));
ALTER TABLE public.invite_placement_bar ADD CONSTRAINT invite_placement_bar_google_max_spam_pct_check CHECK (((google_max_spam_pct >= (0)::numeric) AND (google_max_spam_pct <= (100)::numeric)));
ALTER TABLE public.invite_placement_bar ADD CONSTRAINT invite_placement_bar_google_min_delivered_pct_check CHECK (((google_min_delivered_pct >= (0)::numeric) AND (google_min_delivered_pct <= (100)::numeric)));
ALTER TABLE public.invite_placement_bar ADD CONSTRAINT invite_placement_bar_id_check CHECK (id);
ALTER TABLE public.invite_placement_bar ADD CONSTRAINT invite_placement_bar_max_age_check CHECK ((max_age > '00:00:00'::interval));
ALTER TABLE public.invite_placement_bar ADD CONSTRAINT invite_placement_bar_microsoft_min_inbox_pct_check CHECK (((microsoft_min_inbox_pct >= (0)::numeric) AND (microsoft_min_inbox_pct <= (100)::numeric)));
ALTER TABLE public.invite_placement_bar ADD CONSTRAINT invite_placement_bar_sender_check CHECK ((sender ~~ '%@%'::text));
ALTER TABLE public.invite_placement_bar ADD CONSTRAINT invite_placement_bar_yahoo_aol_min_inbox_pct_check CHECK (((yahoo_aol_min_inbox_pct >= (0)::numeric) AND (yahoo_aol_min_inbox_pct <= (100)::numeric)));
ALTER TABLE public.invite_placement_check ADD CONSTRAINT invite_placement_check_gmail_folder_check CHECK ((gmail_folder = ANY (ARRAY['inbox'::text, 'spam'::text, 'trash'::text, 'other'::text, 'not_found'::text])));
ALTER TABLE public.invite_placement_check ADD CONSTRAINT invite_placement_check_gmail_to_check CHECK ((gmail_to = 'ahmadmhdnabilalzain@gmail.com'::text));
ALTER TABLE public.invite_placement_check ADD CONSTRAINT invite_placement_check_outlook_folder_check CHECK ((outlook_folder = ANY (ARRAY['inbox'::text, 'spam'::text, 'trash'::text, 'other'::text, 'not_found'::text])));
ALTER TABLE public.invite_placement_check ADD CONSTRAINT invite_placement_check_outlook_to_check CHECK ((outlook_to = 'management@quotesdone.com'::text)) NOT VALID;
ALTER TABLE public.invite_placement_check ADD CONSTRAINT invite_placement_check_token_check CHECK ((token ~ '^QD[0-9A-F]{10}$'::text));
ALTER TABLE public.invite_placement_check ADD CONSTRAINT invite_placement_check_verdict_check CHECK ((verdict = ANY (ARRAY['pending'::text, 'inbox'::text, 'spam'::text, 'elsewhere'::text, 'not_found'::text, 'unread'::text, 'not_sent'::text])));
ALTER TABLE public.it_access_known ADD CONSTRAINT it_access_known_accepted_by_check CHECK ((btrim(accepted_by) <> ''::text));
ALTER TABLE public.it_access_known ADD CONSTRAINT it_access_known_reason_check CHECK ((btrim(reason) <> ''::text));
ALTER TABLE public.it_change_acceptance ADD CONSTRAINT it_change_acceptance_accepted_by_check CHECK ((accepted_by = ANY (ARRAY['ceo'::text, 'founder'::text])));
ALTER TABLE public.it_change_acceptance ADD CONSTRAINT it_change_acceptance_reason_check CHECK ((btrim(reason) <> ''::text));
ALTER TABLE public.it_change_revision ADD CONSTRAINT it_change_revision_rev_check CHECK ((rev ~ '^[0-9a-f]{7,40}$'::text));
ALTER TABLE public.it_change_revision ADD CONSTRAINT it_change_revision_verdict_check CHECK ((verdict = ANY (ARRAY['pending'::text, 'on_main'::text, 'merged_pr'::text, 'open_pr'::text, 'not_on_main'::text])));
ALTER TABLE public.it_change_source ADD CONSTRAINT it_change_source_match_on_check CHECK ((match_on = ANY (ARRAY['application_name'::text, 'session_user'::text])));
ALTER TABLE public.it_change_source ADD CONSTRAINT it_change_source_meaning_check CHECK ((btrim(meaning) <> ''::text));
ALTER TABLE public.it_change_source ADD CONSTRAINT it_change_source_pattern_check CHECK ((btrim(pattern) <> ''::text));
ALTER TABLE public.it_cost_watch_week ADD CONSTRAINT it_cost_watch_week_basis_check CHECK ((basis = ANY (ARRAY['usage_api'::text, 'ai_cost_log'::text, 'journals'::text, 'unavailable'::text])));
ALTER TABLE public.it_cost_watch_week ADD CONSTRAINT it_cost_watch_week_period_days_check CHECK ((period_days > 0));
ALTER TABLE public.it_cost_watch_week ADD CONSTRAINT it_cost_watch_week_provider_check CHECK ((provider = ANY (ARRAY['supabase'::text, 'vercel'::text, 'resend'::text, 'twilio'::text, 'openrouter'::text])));
ALTER TABLE public.it_credential_class ADD CONSTRAINT it_credential_class_rotation_check CHECK ((rotation = ANY (ARRAY['company_api'::text, 'founder_required'::text])));
ALTER TABLE public.it_credential_rotation ADD CONSTRAINT it_credential_rotation_kind_ck CHECK ((((provider IS NULL) AND (old_id IS NOT NULL) AND (new_id IS NOT NULL)) OR ((provider IS NOT NULL) AND (new_ref IS NOT NULL))));
ALTER TABLE public.it_credential_rotation ADD CONSTRAINT it_credential_rotation_status_check CHECK ((status = ANY (ARRAY['overlap'::text, 'retired'::text, 'held'::text, 'baseline'::text])));
ALTER TABLE public.it_duty_schedule ADD CONSTRAINT it_duty_schedule_every_check CHECK ((every > '00:00:00'::interval));
ALTER TABLE public.it_engineer_finding ADD CONSTRAINT it_engineer_finding_affected_ck CHECK ((affected >= 0));
ALTER TABLE public.it_engineer_finding ADD CONSTRAINT it_engineer_finding_blast_ck CHECK ((blast = ANY (ARRAY['customer_facing'::text, 'security'::text, 'agent_facing'::text, 'internal'::text, 'monitor'::text])));
ALTER TABLE public.it_engineer_knowledge ADD CONSTRAINT it_engineer_knowledge_authority_ck CHECK ((authority_effect = 'none'::text));
ALTER TABLE public.it_engineer_knowledge ADD CONSTRAINT it_engineer_knowledge_epistemic_ck CHECK ((epistemic_status = ANY (ARRAY['method_engineering'::text, 'diagnostic_lens'::text, 'estate_architecture_measured'::text, 'failure_signature'::text, 'security_posture_no_version_claim'::text, 'resolve_from_live_system'::text, 'company_governance_ruling'::text, 'company_record_generated'::text, 'verified_pack_sourced'::text])));
ALTER TABLE public.it_engineer_scanner ADD CONSTRAINT it_engineer_scanner_gap_ck CHECK (((max_gap_minutes >= 5) AND (max_gap_minutes <= 1440)));
ALTER TABLE public.it_expiry ADD CONSTRAINT it_expiry_kind_check CHECK ((kind = ANY (ARRAY['licence'::text, 'domain'::text, 'tls'::text, 'token'::text])));
ALTER TABLE public.it_expiry ADD CONSTRAINT it_expiry_never_expires_ck CHECK ((NOT (never_expires AND (expires_on IS NOT NULL))));
ALTER TABLE public.it_expiry ADD CONSTRAINT it_expiry_warn_days_ck CHECK (((cardinality(warn_days) > 0) AND (0 < ALL (warn_days))));
ALTER TABLE public.it_founder_decision_class ADD CONSTRAINT it_founder_decision_class_only_his_categories CHECK (((NOT to_founder) OR (founder_category = ANY (ARRAY['money'::text, 'destructive_production_change'::text, 'fact_only_he_holds'::text]))));
ALTER TABLE public.it_game_day_run ADD CONSTRAINT it_game_day_run_run_month_check CHECK ((run_month = (date_trunc('month'::text, (run_month)::timestamp with time zone))::date));
ALTER TABLE public.it_game_day_run ADD CONSTRAINT it_game_day_run_scenario_check CHECK ((scenario = ANY (ARRAY['email_provider_down'::text, 'whatsapp_down'::text, 'edge_function_slow'::text, 'db_connection'::text, 'credential_expired'::text])));
ALTER TABLE public.it_incident ADD CONSTRAINT it_incident_customer_impact_check CHECK (((customer_impact IS NULL) OR (customer_impact = ANY (ARRAY['customers'::text, 'suppliers'::text, 'everyone'::text]))));
ALTER TABLE public.it_model_consumer ADD CONSTRAINT it_model_consumer_consumer_check CHECK ((consumer ~ '^[a-z0-9_]+[:.][a-z0-9_]+$'::text));
ALTER TABLE public.it_model_consumer ADD CONSTRAINT it_model_consumer_why_a_model_check CHECK ((btrim(why_a_model) <> ''::text));
ALTER TABLE public.it_playbook ADD CONSTRAINT it_playbook_added_by_check CHECK ((btrim(added_by) <> ''::text));
ALTER TABLE public.it_playbook ADD CONSTRAINT it_playbook_check CHECK (((COALESCE(btrim(remedy), ''::text) <> ''::text) OR (COALESCE(btrim(not_automatable_reason), ''::text) <> ''::text)));
ALTER TABLE public.it_playbook ADD CONSTRAINT it_playbook_failure_class_check CHECK ((failure_class ~ '^[a-z0-9_]+$'::text));
ALTER TABLE public.it_playbook ADD CONSTRAINT it_playbook_issue_prefix_check CHECK ((btrim(issue_prefix) <> ''::text));
ALTER TABLE public.it_playbook ADD CONSTRAINT it_playbook_regression_check_check CHECK ((btrim(regression_check) <> ''::text));
ALTER TABLE public.it_playbook ADD CONSTRAINT it_playbook_remedy_routine_check CHECK ((remedy_routine ~ '^fn_[a-z0-9_]+$'::text));
ALTER TABLE public.it_postmaster_reading ADD CONSTRAINT it_postmaster_reading_basis_check CHECK ((basis = ANY (ARRAY['measured'::text, 'no_data'::text, 'unavailable'::text])));
ALTER TABLE public.it_postmaster_reading ADD CONSTRAINT it_postmaster_reading_dkim_ratio_check CHECK (((dkim_ratio >= (0)::numeric) AND (dkim_ratio <= (1)::numeric)));
ALTER TABLE public.it_postmaster_reading ADD CONSTRAINT it_postmaster_reading_dmarc_ratio_check CHECK (((dmarc_ratio >= (0)::numeric) AND (dmarc_ratio <= (1)::numeric)));
ALTER TABLE public.it_postmaster_reading ADD CONSTRAINT it_postmaster_reading_no_numbers_without_data CHECK (((basis = 'measured'::text) OR ((spam_ratio IS NULL) AND (reputation IS NULL) AND (spf_ratio IS NULL) AND (dkim_ratio IS NULL) AND (dmarc_ratio IS NULL))));
ALTER TABLE public.it_postmaster_reading ADD CONSTRAINT it_postmaster_reading_reputation_check CHECK ((reputation = ANY (ARRAY['HIGH'::text, 'MEDIUM'::text, 'LOW'::text, 'BAD'::text])));
ALTER TABLE public.it_postmaster_reading ADD CONSTRAINT it_postmaster_reading_spam_lower_check CHECK (((spam_lower >= (0)::numeric) AND (spam_lower <= (1)::numeric)));
ALTER TABLE public.it_postmaster_reading ADD CONSTRAINT it_postmaster_reading_spam_ratio_check CHECK (((spam_ratio >= (0)::numeric) AND (spam_ratio <= (1)::numeric)));
ALTER TABLE public.it_postmaster_reading ADD CONSTRAINT it_postmaster_reading_spam_upper_check CHECK (((spam_upper >= (0)::numeric) AND (spam_upper <= (1)::numeric)));
ALTER TABLE public.it_postmaster_reading ADD CONSTRAINT it_postmaster_reading_spf_ratio_check CHECK (((spf_ratio >= (0)::numeric) AND (spf_ratio <= (1)::numeric)));
ALTER TABLE public.it_restore_drill_table ADD CONSTRAINT it_restore_drill_table_key_column_check CHECK ((key_column ~ '^[a-z_][a-z0-9_]*$'::text));
ALTER TABLE public.it_restore_drill_table ADD CONSTRAINT it_restore_drill_table_note_check CHECK ((btrim(note) <> ''::text));
ALTER TABLE public.it_restore_drill_table ADD CONSTRAINT it_restore_drill_table_table_name_check CHECK ((table_name ~ '^[a-z_][a-z0-9_]*$'::text));
ALTER TABLE public.it_security_baseline ADD CONSTRAINT it_security_baseline_accepted_with_reason CHECK (((btrim(reason) <> ''::text) AND (btrim(accepted_by) <> ''::text)));
ALTER TABLE public.it_security_baseline ADD CONSTRAINT it_security_baseline_kind_check CHECK ((kind = ANY (ARRAY['anon_executable_definer'::text, 'authenticated_executable_definer'::text, 'rls_off'::text, 'rls_no_policy'::text])));
ALTER TABLE public.it_threshold ADD CONSTRAINT it_threshold_basis_check CHECK ((btrim(basis) <> ''::text));
ALTER TABLE public.kb_citation_jurisdiction ADD CONSTRAINT kb_citation_jurisdiction_citation_md5_check CHECK ((citation_md5 ~ '^[0-9a-f]{32}$'::text));
ALTER TABLE public.kb_citation_jurisdiction ADD CONSTRAINT kb_citation_jurisdiction_jurisdiction_check CHECK ((jurisdiction = ANY (ARRAY['quotesdone'::text, 'uae'::text, 'gcc'::text, 'international'::text, 'us'::text, 'other_foreign'::text])));
ALTER TABLE public.kb_embed_priority ADD CONSTRAINT kb_embed_priority_tier_check CHECK (((tier >= 1) AND (tier <= 4)));
ALTER TABLE public.kb_operational_route ADD CONSTRAINT kb_route_reg_coverage_chk CHECK ((regulatory_coverage_status = ANY (ARRAY['confirmed_none'::text, 'confirmed_covered'::text, 'incomplete'::text, 'requires_review'::text])));
ALTER TABLE public.kb_purge_ledger ADD CONSTRAINT kb_purge_ledger_clause_check CHECK (((clause >= 0) AND (clause <= 7)));
ALTER TABLE public.kb_purge_ledger ADD CONSTRAINT kb_purge_ledger_verdict_check CHECK ((verdict = ANY (ARRAY['KEEP'::text, 'UNSURE'::text, 'DELETE'::text, 'SIZE'::text, 'TRIM'::text])));
ALTER TABLE public.kb_trim_hash ADD CONSTRAINT kb_trim_hash_clause_check CHECK ((clause = ANY (ARRAY[6, 7])));
ALTER TABLE public.kb_trim_plan ADD CONSTRAINT kb_trim_plan_clause_check CHECK ((clause = ANY (ARRAY[6, 7])));
ALTER TABLE public.knowledge_ingestion_run ADD CONSTRAINT knowledge_ingestion_run_generation_check CHECK ((generation = ANY (ARRAY['V1'::text, 'V2'::text, 'V3'::text])));
ALTER TABLE public.knowledge_ingestion_run ADD CONSTRAINT knowledge_ingestion_run_status_check CHECK ((status = ANY (ARRAY['running'::text, 'ok'::text, 'failed'::text, 'rolled_back'::text])));
ALTER TABLE public.knowledge_ingestion_undo ADD CONSTRAINT knowledge_ingestion_undo_table_name_check CHECK ((table_name = ANY (ARRAY['ops_knowledge'::text, 'agent_training_case'::text])));
ALTER TABLE public.knowledge_library ADD CONSTRAINT knowledge_library_seats_ck CHECK ((cardinality(seats) > 0));
ALTER TABLE public.knowledge_library ADD CONSTRAINT knowledge_library_store_ck CHECK ((origin_store = ANY (ARRAY['kb_chunks'::text, 'ops_knowledge'::text, 'agent_knowledge'::text, 'sales_knowledge'::text, 'accountant_knowledge'::text, 'it_engineer_knowledge'::text, 'marketing_knowledge'::text, 'ceo_knowledge'::text, 'support_knowledge'::text])));
ALTER TABLE public.knowledge_library_state ADD CONSTRAINT knowledge_library_state_one_row_ck CHECK ((id = 1));
ALTER TABLE public.knowledge_ml_status ADD CONSTRAINT knowledge_ml_status_id_check CHECK (id);
ALTER TABLE public.knowledge_vector_ml ADD CONSTRAINT knowledge_vector_ml_src_check CHECK ((src = ANY (ARRAY['seat_case_memory'::text, 'ceo_knowledge'::text, 'support_knowledge'::text, 'accountant_knowledge'::text, 'it_engineer_knowledge'::text, 'marketing_knowledge'::text, 'sales_knowledge'::text, 'company_faq'::text, 'agent_knowledge'::text, 'ops_knowledge'::text, 'reasoning_knowledge_candidate'::text, 'kb_chunks'::text, 'knowledge_library'::text])));
ALTER TABLE public.lead_email_check ADD CONSTRAINT lead_email_check_mailbox_check CHECK ((mailbox = ANY (ARRAY['named'::text, 'role'::text, 'free'::text])));
ALTER TABLE public.lead_email_check ADD CONSTRAINT lead_email_check_verdict_check CHECK ((verdict = ANY (ARRAY['verified'::text, 'rejected'::text, 'retry'::text])));
ALTER TABLE public.lead_email_check ADD CONSTRAINT lead_email_check_verified_needs_mx CHECK (((verdict <> 'verified'::text) OR (mx_kind = 'mx'::text)));
ALTER TABLE public.lead_prospect ADD CONSTRAINT lead_prospect_field_sources_check CHECK ((jsonb_typeof(field_sources) = 'object'::text));
ALTER TABLE public.lead_prospect ADD CONSTRAINT lead_prospect_status_check CHECK ((status = ANY (ARRAY['complete'::text, 'incomplete'::text, 'duplicate'::text, 'suppressed'::text, 'promoted'::text])));
ALTER TABLE public.lead_sourcing_run ADD CONSTRAINT lead_sourcing_run_kind_check CHECK ((kind = ANY (ARRAY['batch'::text, 'pilot'::text, 'probe'::text])));
ALTER TABLE public.lead_sourcing_run ADD CONSTRAINT lead_sourcing_run_status_check CHECK ((status = ANY (ARRAY['reserved'::text, 'done'::text])));
ALTER TABLE public.lead_trade_class ADD CONSTRAINT lead_trade_class_confidence_check CHECK (((confidence IS NULL) OR ((confidence >= (0)::numeric) AND (confidence <= (1)::numeric))));
ALTER TABLE public.lead_trade_class ADD CONSTRAINT lead_trade_class_decided_by_check CHECK ((decided_by = 'reasoning'::text));
ALTER TABLE public.lead_trade_class ADD CONSTRAINT lead_trade_class_evidence_check CHECK ((btrim(evidence) <> ''::text));
ALTER TABLE public.leads ADD CONSTRAINT leads_accepted_terms_sha256_check CHECK (((accepted_terms_sha256 IS NULL) OR (accepted_terms_sha256 ~ '^[0-9a-f]{64}$'::text)));
ALTER TABLE public.leads ADD CONSTRAINT leads_approved_implies_verified CHECK (((COALESCE(approval_status, ''::text) <> 'approved'::text) OR (COALESCE(verified, false) = true)));
ALTER TABLE public.leads ADD CONSTRAINT leads_locale_chk CHECK ((locale = ANY (ARRAY['en'::text, 'ar'::text]))) NOT VALID;
ALTER TABLE public.leads ADD CONSTRAINT leads_registration_amount_aed_check CHECK (((registration_amount_aed IS NULL) OR (registration_amount_aed >= (0)::numeric)));
ALTER TABLE public.leads ADD CONSTRAINT leads_registration_fee_due_money_ck CHECK (((registration_fee_due >= (0)::numeric) AND (registration_fee_due = round(registration_fee_due, 2))));
ALTER TABLE public.leads ADD CONSTRAINT leads_registration_status_check CHECK (((registration_status IS NULL) OR (registration_status = ANY (ARRAY['exempt'::text, 'paid'::text, 'not_due'::text, 'due'::text]))));
ALTER TABLE public.leads ADD CONSTRAINT leads_whatsapp_opt_known CHECK (((whatsapp_opt IS NULL) OR (whatsapp_opt = ANY (ARRAY['same'::text, 'other'::text, 'none'::text]))));
ALTER TABLE public.leads ADD CONSTRAINT leads_whatsapp_phone_is_verified CHECK (((whatsapp_phone IS NULL) OR (whatsapp_verified_at IS NOT NULL)));
ALTER TABLE public.licence_renewal_ask ADD CONSTRAINT licence_renewal_ask_band_check CHECK ((band = ANY (ARRAY['t_minus_30'::text, 't_minus_14'::text, 't_minus_7'::text, 'expired'::text])));
ALTER TABLE public.licence_renewal_ask ADD CONSTRAINT licence_renewal_ask_channel_check CHECK ((channel = ANY (ARRAY['email'::text, 'whatsapp'::text])));
ALTER TABLE public.line_spec_reading ADD CONSTRAINT line_spec_reading_found_check CHECK ((jsonb_typeof(found) = 'object'::text));
ALTER TABLE public.line_spec_reading ADD CONSTRAINT line_spec_reading_reading_key_check CHECK ((reading_key ~ '^[0-9a-f]{64}$'::text));
ALTER TABLE public.llm_attempt ADD CONSTRAINT llm_attempt_attempt_no_check CHECK ((attempt_no >= 1));
ALTER TABLE public.llm_attempt ADD CONSTRAINT llm_attempt_class_matches_ok CHECK (((ok AND (class_key IS NULL)) OR ((NOT ok) AND (class_key IS NOT NULL))));
ALTER TABLE public.llm_failure_class ADD CONSTRAINT llm_failure_class_layer_check CHECK ((layer = ANY (ARRAY['provider'::text, 'transport'::text, 'contract'::text, 'tool'::text, 'retrieval'::text, 'database'::text, 'orchestration'::text, 'test_runner'::text, 'unknown'::text])));
ALTER TABLE public.llm_failure_class ADD CONSTRAINT llm_failure_class_max_retries_check CHECK (((max_retries >= 0) AND (max_retries <= 5)));
ALTER TABLE public.llm_failure_class ADD CONSTRAINT llm_failure_class_retry_backoff_ms_check CHECK ((retry_backoff_ms >= 0));
ALTER TABLE public.llm_route_health ADD CONSTRAINT llm_route_health_consecutive_failures_check CHECK ((consecutive_failures >= 0));
ALTER TABLE public.llm_route_health ADD CONSTRAINT llm_route_health_cooldown_seconds_check CHECK ((cooldown_seconds >= 30));
ALTER TABLE public.llm_route_health ADD CONSTRAINT llm_route_health_failure_threshold_check CHECK ((failure_threshold >= 1));
ALTER TABLE public.market_intel ADD CONSTRAINT market_intel_impact_check CHECK ((impact = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text])));
ALTER TABLE public.market_intel ADD CONSTRAINT market_intel_kind_check CHECK ((kind = ANY (ARRAY['competitor'::text, 'trend'::text, 'expansion'::text, 'regulatory'::text, 'other'::text])));
ALTER TABLE public.market_intel ADD CONSTRAINT market_intel_status_check CHECK ((status = ANY (ARRAY['open'::text, 'reviewed'::text, 'actioned'::text, 'dismissed'::text])));
ALTER TABLE public.marketing_ad_spend_day ADD CONSTRAINT marketing_ad_spend_day_account_id_check CHECK ((account_id ~ '^act_[0-9]+$'::text));
ALTER TABLE public.marketing_ad_spend_day ADD CONSTRAINT marketing_ad_spend_day_campaign_id_check CHECK ((btrim(campaign_id) <> ''::text));
ALTER TABLE public.marketing_ad_spend_day ADD CONSTRAINT marketing_ad_spend_day_currency_check CHECK ((currency ~ '^[A-Z]{3}$'::text));
ALTER TABLE public.marketing_ad_spend_day ADD CONSTRAINT marketing_ad_spend_day_demo_is_marked CHECK (((NOT is_demo) OR (campaign_name ~~ 'ZZ DEMO%'::text)));
ALTER TABLE public.marketing_ad_spend_day ADD CONSTRAINT marketing_ad_spend_day_spend_check CHECK ((spend >= (0)::numeric));
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_approved_by_check CHECK ((approved_by = ANY (ARRAY['founder'::text, 'claude'::text, 'ceo'::text])));
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_approved_says_who CHECK (((status = ANY (ARRAY['draft'::text, 'withdrawn'::text])) OR ((approved_by IS NOT NULL) AND (approved_at IS NOT NULL))));
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_body_html_ar_check CHECK ((body_html_ar ~ '[؀-ۿ]'::text));
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_body_html_en_check CHECK ((btrim(body_html_en) <> ''::text));
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_category_ar_check CHECK ((category_ar ~ '[؀-ۿ]'::text));
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_category_en_check CHECK ((btrim(category_en) <> ''::text));
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_checks_are_clean CHECK ((((checks -> 'lint'::text) = '[]'::jsonb) AND ((checks -> 'ungrounded'::text) = '[]'::jsonb)));
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_demo_is_marked CHECK (((NOT is_demo) OR (title_en ~~ 'ZZ DEMO%'::text)));
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_excerpt_ar_check CHECK ((excerpt_ar ~ '[؀-ۿ]'::text));
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_excerpt_en_check CHECK ((btrim(excerpt_en) <> ''::text));
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_ingested_by_check CHECK ((ingested_by = ANY (ARRAY['founder'::text, 'claude'::text])));
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_kind_check CHECK ((kind = ANY (ARRAY['how_it_works'::text, 'buyer_guide'::text, 'trade_explainer'::text, 'market_topic'::text])));
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_live_says_when CHECK (((status <> 'live'::text) OR (live_at IS NOT NULL)));
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_meta_desc_ar_check CHECK ((meta_desc_ar ~ '[؀-ۿ]'::text));
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_meta_desc_en_check CHECK ((btrim(meta_desc_en) <> ''::text));
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_released_says_when CHECK (((status <> ALL (ARRAY['released'::text, 'live'::text])) OR (released_at IS NOT NULL)));
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_slug_check CHECK (((slug ~ '^[a-z0-9]+(-[a-z0-9]+)+$'::text) AND (length(slug) <= 70)));
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_sources_check CHECK (((jsonb_typeof(sources) = 'array'::text) AND (jsonb_array_length(sources) > 0)));
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text, 'released'::text, 'live'::text, 'withdrawn'::text])));
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_title_ar_check CHECK ((title_ar ~ '[؀-ۿ]'::text));
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_title_en_check CHECK ((btrim(title_en) <> ''::text));
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_withdrawn_says_why CHECK (((status <> 'withdrawn'::text) OR (withdrawn_reason IS NOT NULL)));
ALTER TABLE public.marketing_article_round ADD CONSTRAINT marketing_article_round_changes_check CHECK (((changes IS NULL) OR (jsonb_typeof(changes) = 'array'::text)));
ALTER TABLE public.marketing_article_round ADD CONSTRAINT marketing_article_round_check CHECK (((round = 1) = (changes IS NULL)));
ALTER TABLE public.marketing_article_round ADD CONSTRAINT marketing_article_round_check1 CHECK (((decision IS NULL) = (reviewed_at IS NULL)));
ALTER TABLE public.marketing_article_round ADD CONSTRAINT marketing_article_round_decision_check CHECK ((decision = ANY (ARRAY['approve'::text, 'revise'::text, 'replace_topic'::text])));
ALTER TABLE public.marketing_article_round ADD CONSTRAINT marketing_article_round_decision_has_its_reasons CHECK (((decision IS NULL) OR fn_marketing_review_reasons_ok(decision, reasons)));
ALTER TABLE public.marketing_article_round ADD CONSTRAINT marketing_article_round_round_check CHECK ((round >= 1));
ALTER TABLE public.marketing_article_round ADD CONSTRAINT marketing_article_round_version_check CHECK (((jsonb_typeof((version -> 'en'::text)) = 'object'::text) AND (jsonb_typeof((version -> 'ar'::text)) = 'object'::text)));
ALTER TABLE public.marketing_asset_feature ADD CONSTRAINT marketing_asset_feature_bytes_check CHECK ((bytes > 0));
ALTER TABLE public.marketing_asset_feature ADD CONSTRAINT marketing_asset_feature_file_sha256_check CHECK ((file_sha256 ~ '^[0-9a-f]{64}$'::text));
ALTER TABLE public.marketing_asset_feature ADD CONSTRAINT marketing_asset_feature_keyframes_check CHECK ((jsonb_typeof(keyframes) = 'array'::text));
ALTER TABLE public.marketing_asset_perception ADD CONSTRAINT marketing_asset_perception_perception_check CHECK ((jsonb_typeof(perception) = 'object'::text));
ALTER TABLE public.marketing_asset_review ADD CONSTRAINT marketing_asset_review_evidence_check CHECK (((jsonb_typeof(evidence) = 'array'::text) AND (jsonb_array_length(evidence) > 0)));
ALTER TABLE public.marketing_asset_review ADD CONSTRAINT marketing_asset_review_review_check CHECK ((jsonb_typeof(review) = 'object'::text));
ALTER TABLE public.marketing_blog_topic ADD CONSTRAINT marketing_blog_topic_check CHECK (((status = 'replaced'::text) = (replaced_reason IS NOT NULL)));
ALTER TABLE public.marketing_blog_topic ADD CONSTRAINT marketing_blog_topic_check1 CHECK (((status = 'picked'::text) = (closed_at IS NULL)));
ALTER TABLE public.marketing_blog_topic ADD CONSTRAINT marketing_blog_topic_evidence_check CHECK (((jsonb_typeof(evidence) = 'array'::text) AND (jsonb_array_length(evidence) > 0)));
ALTER TABLE public.marketing_blog_topic ADD CONSTRAINT marketing_blog_topic_kind_check CHECK ((kind = ANY (ARRAY['search'::text, 'regulation'::text, 'news'::text, 'demand'::text])));
ALTER TABLE public.marketing_blog_topic ADD CONSTRAINT marketing_blog_topic_sources_check CHECK (((jsonb_typeof(sources) = 'array'::text) AND (jsonb_array_length(sources) > 0)));
ALTER TABLE public.marketing_blog_topic ADD CONSTRAINT marketing_blog_topic_status_check CHECK ((status = ANY (ARRAY['picked'::text, 'replaced'::text, 'published'::text])));
ALTER TABLE public.marketing_blog_topic ADD CONSTRAINT marketing_blog_topic_title_check CHECK ((btrim(title) <> ''::text));
ALTER TABLE public.marketing_calendar_resend_decision ADD CONSTRAINT marketing_calendar_resend_decision_decision_check CHECK ((decision = ANY (ARRAY['due'::text, 'quiet_period'::text, 'already_sent'::text, 'already_approved'::text, 'finished'::text])));
ALTER TABLE public.marketing_campaign ADD CONSTRAINT marketing_campaign_approval_is_whole CHECK ((((approved_by IS NULL) = (approved_at IS NULL)) AND ((approved_at IS NULL) = (approved_hash IS NULL)) AND ((approved_at IS NULL) = (approved_message_id IS NULL))));
ALTER TABLE public.marketing_campaign ADD CONSTRAINT marketing_campaign_approved_by_check CHECK ((approved_by = 'founder'::text));
ALTER TABLE public.marketing_campaign ADD CONSTRAINT marketing_campaign_approved_hash_check CHECK ((approved_hash ~ '^[0-9a-f]{64}$'::text));
ALTER TABLE public.marketing_campaign ADD CONSTRAINT marketing_campaign_approved_what_the_calendar_showed CHECK (((approved_hash IS NULL) OR (approved_hash = calendar_hash)));
ALTER TABLE public.marketing_campaign ADD CONSTRAINT marketing_campaign_calendar_hash_check CHECK ((calendar_hash ~ '^[0-9a-f]{64}$'::text));
ALTER TABLE public.marketing_campaign ADD CONSTRAINT marketing_campaign_calendar_token_check CHECK ((calendar_token ~ '^[0-9a-f]{32}$'::text));
ALTER TABLE public.marketing_campaign ADD CONSTRAINT marketing_campaign_campaign_key_check CHECK ((campaign_key ~ '^[a-z0-9][a-z0-9-]{2,80}$'::text));
ALTER TABLE public.marketing_campaign ADD CONSTRAINT marketing_campaign_demo_both_ways CHECK ((is_demo = (((((campaign_key || ' '::text) || theme) || ' '::text) || COALESCE(title, ''::text)) ~* 'zz[ _-]?demo'::text)));
ALTER TABLE public.marketing_campaign ADD CONSTRAINT marketing_campaign_month_check CHECK ((month = (date_trunc('month'::text, (month)::timestamp with time zone))::date));
ALTER TABLE public.marketing_campaign ADD CONSTRAINT marketing_campaign_spend_policy_check CHECK ((spend_policy = 'organic_only'::text));
ALTER TABLE public.marketing_campaign ADD CONSTRAINT marketing_campaign_theme_check CHECK ((btrim(theme) <> ''::text));
ALTER TABLE public.marketing_connection_check ADD CONSTRAINT marketing_connection_check_check_key_check CHECK ((check_key ~ '^[a-z]+(\.[a-z_]+)+$'::text));
ALTER TABLE public.marketing_connection_check ADD CONSTRAINT marketing_connection_check_failure_names_the_need CHECK ((ok OR (btrim(COALESCE(needs, ''::text)) <> ''::text)));
ALTER TABLE public.marketing_connection_check ADD CONSTRAINT marketing_connection_check_platform_check CHECK ((platform = ANY (ARRAY['postiz'::text, 'meta'::text, 'linkedin'::text])));
ALTER TABLE public.marketing_duty_run ADD CONSTRAINT marketing_duty_run_duty_check CHECK ((duty = ANY (ARRAY['access'::text, 'insights'::text, 'ad_spend'::text])));
ALTER TABLE public.marketing_first_touch ADD CONSTRAINT marketing_first_touch_landing_path_check CHECK ((landing_path ~ '^/\S{0,200}$'::text));
ALTER TABLE public.marketing_first_touch ADD CONSTRAINT marketing_first_touch_utm_campaign_check CHECK ((utm_campaign ~ '^[A-Za-z0-9._-]{1,100}$'::text));
ALTER TABLE public.marketing_first_touch ADD CONSTRAINT marketing_first_touch_utm_content_check CHECK ((utm_content ~ '^[A-Za-z0-9._-]{1,100}$'::text));
ALTER TABLE public.marketing_first_touch ADD CONSTRAINT marketing_first_touch_utm_medium_check CHECK ((utm_medium ~ '^[A-Za-z0-9._-]{1,100}$'::text));
ALTER TABLE public.marketing_first_touch ADD CONSTRAINT marketing_first_touch_utm_source_check CHECK ((utm_source ~ '^[A-Za-z0-9._-]{1,100}$'::text));
ALTER TABLE public.marketing_founder_request ADD CONSTRAINT marketing_founder_request_done_is_whole CHECK (((status = 'open'::text) = (done_at IS NULL)));
ALTER TABLE public.marketing_founder_request ADD CONSTRAINT marketing_founder_request_kind_check CHECK ((kind = ANY (ARRAY['calendar_change'::text, 'month_content'::text])));
ALTER TABLE public.marketing_founder_request ADD CONSTRAINT marketing_founder_request_month_check CHECK ((month = (date_trunc('month'::text, (month)::timestamp with time zone))::date));
ALTER TABLE public.marketing_founder_request ADD CONSTRAINT marketing_founder_request_names_its_subject CHECK (((campaign_id IS NOT NULL) OR (month IS NOT NULL)));
ALTER TABLE public.marketing_founder_request ADD CONSTRAINT marketing_founder_request_status_check CHECK ((status = ANY (ARRAY['open'::text, 'done'::text, 'superseded'::text])));
ALTER TABLE public.marketing_gap_recruitment_plan ADD CONSTRAINT marketing_gap_recruitment_plan_check CHECK (((invite_body !~* '(https?://|www\.|\{\{link\}\})'::text) AND (invite_body !~ '[؀-ۿ]'::text) AND (invite_subject !~ '[؀-ۿ]'::text)));
ALTER TABLE public.marketing_geo_check ADD CONSTRAINT marketing_geo_check_engine_check CHECK ((engine = ANY (ARRAY['web'::text, 'model'::text, 'answer_search'::text, 'answer_online'::text])));
ALTER TABLE public.marketing_geo_check ADD CONSTRAINT marketing_geo_check_month_check CHECK ((EXTRACT(day FROM month) = (1)::numeric));
ALTER TABLE public.marketing_geo_question ADD CONSTRAINT marketing_geo_question_audience_check CHECK ((audience = ANY (ARRAY['customer'::text, 'supplier'::text])));
ALTER TABLE public.marketing_goal ADD CONSTRAINT marketing_goal_benchmark_source_check CHECK ((length(btrim(benchmark_source)) >= 20));
ALTER TABLE public.marketing_goal ADD CONSTRAINT marketing_goal_metric_check CHECK ((metric ~ '^[a-z0-9_]+$'::text));
ALTER TABLE public.marketing_goal ADD CONSTRAINT marketing_goal_month_check CHECK ((month ~ '^\d{4}-(0[1-9]|1[0-2])$'::text));
ALTER TABLE public.marketing_goal ADD CONSTRAINT marketing_goal_platform_check CHECK ((platform = ANY (ARRAY['facebook'::text, 'instagram'::text, 'linkedin'::text, 'x'::text, 'youtube'::text, 'tiktok'::text])));
ALTER TABLE public.marketing_goal ADD CONSTRAINT marketing_goal_target_check CHECK ((target >= (0)::numeric));
ALTER TABLE public.marketing_insight_day ADD CONSTRAINT marketing_insight_day_metric_check CHECK ((metric ~ '^[a-z0-9_]+$'::text));
ALTER TABLE public.marketing_insight_day ADD CONSTRAINT marketing_insight_day_object_id_check CHECK ((btrim(object_id) <> ''::text));
ALTER TABLE public.marketing_insight_day ADD CONSTRAINT marketing_insight_day_object_type_check CHECK ((object_type = ANY (ARRAY['page'::text, 'account'::text, 'post'::text])));
ALTER TABLE public.marketing_insight_day ADD CONSTRAINT marketing_insight_day_platform_check CHECK ((platform = ANY (ARRAY['facebook'::text, 'instagram'::text, 'linkedin'::text, 'youtube'::text, 'tiktok'::text, 'x'::text])));
ALTER TABLE public.marketing_insight_note ADD CONSTRAINT marketing_insight_note_synthesis_check CHECK ((jsonb_typeof(synthesis) = 'object'::text));
ALTER TABLE public.marketing_insight_note ADD CONSTRAINT marketing_insight_note_week_start_check CHECK ((EXTRACT(isodow FROM week_start) = (1)::numeric));
ALTER TABLE public.marketing_knowledge ADD CONSTRAINT marketing_knowledge_authority_effect_check CHECK ((authority_effect = 'none'::text));
ALTER TABLE public.marketing_model_run ADD CONSTRAINT marketing_model_run_check CHECK (((outcome = 'written'::text) = (output_ref IS NOT NULL)));
ALTER TABLE public.marketing_model_run ADD CONSTRAINT marketing_model_run_outcome_check CHECK ((outcome = ANY (ARRAY['held_not_run'::text, 'written'::text, 'rejected'::text, 'failed'::text])));
ALTER TABLE public.marketing_model_run ADD CONSTRAINT marketing_model_run_seat_check CHECK ((seat = ANY (ARRAY['marketing'::text, 'ceo'::text])));
ALTER TABLE public.marketing_month_plan ADD CONSTRAINT marketing_month_plan_month_check CHECK ((EXTRACT(day FROM month) = (1)::numeric));
ALTER TABLE public.marketing_month_plan ADD CONSTRAINT marketing_month_plan_plan_token_check CHECK ((plan_token ~ '^[0-9a-f]{32}$'::text));
ALTER TABLE public.marketing_month_plan ADD CONSTRAINT marketing_month_plan_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'with_ceo'::text, 'agreed'::text, 'brief_requested'::text, 'sent_to_founder'::text, 'accepted'::text, 'rejected'::text, 'ceo_reviewing'::text, 'ceo_approved'::text])));
ALTER TABLE public.marketing_outreach_message ADD CONSTRAINT marketing_outreach_message_body_check CHECK (((btrim(body) <> ''::text) AND (length(body) <= 1900)));
ALTER TABLE public.marketing_outreach_message ADD CONSTRAINT marketing_outreach_message_first_has_a_note CHECK (((kind <> 'first'::text) OR (note IS NOT NULL)));
ALTER TABLE public.marketing_outreach_message ADD CONSTRAINT marketing_outreach_message_kind_check CHECK ((kind = ANY (ARRAY['first'::text, 'follow_up'::text])));
ALTER TABLE public.marketing_outreach_message ADD CONSTRAINT marketing_outreach_message_language_check CHECK ((language = ANY (ARRAY['en'::text, 'ar'::text])));
ALTER TABLE public.marketing_outreach_message ADD CONSTRAINT marketing_outreach_message_lint_check CHECK ((lint = '[]'::jsonb));
ALTER TABLE public.marketing_outreach_message ADD CONSTRAINT marketing_outreach_message_note_check CHECK (((note IS NULL) OR (length(note) <= 300)));
ALTER TABLE public.marketing_outreach_message ADD CONSTRAINT marketing_outreach_message_reply_class_check CHECK ((reply_class = ANY (ARRAY['decline'::text, 'later'::text, 'positive'::text, 'question'::text])));
ALTER TABLE public.marketing_outreach_message ADD CONSTRAINT marketing_outreach_message_reply_is_kept CHECK (((status <> 'replied'::text) OR (reply_text IS NOT NULL)));
ALTER TABLE public.marketing_outreach_message ADD CONSTRAINT marketing_outreach_message_reply_text_check CHECK (((reply_text IS NULL) OR (length(reply_text) <= 4000)));
ALTER TABLE public.marketing_outreach_message ADD CONSTRAINT marketing_outreach_message_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'listed'::text, 'sent'::text, 'replied'::text, 'converted'::text, 'declined'::text])));
ALTER TABLE public.marketing_plan_doc ADD CONSTRAINT marketing_plan_doc_kind_check CHECK ((kind = ANY (ARRAY['launch_plan'::text, 'competitor_intel'::text])));
ALTER TABLE public.marketing_plan_doc ADD CONSTRAINT marketing_plan_doc_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'sent_to_founder'::text, 'approved'::text, 'change_requested'::text])));
ALTER TABLE public.marketing_plan_review_turn ADD CONSTRAINT marketing_plan_review_turn_check CHECK (((seat = 'marketing'::text) = (move = ANY (ARRAY['propose'::text, 'adjust'::text, 'defend'::text]))));
ALTER TABLE public.marketing_plan_review_turn ADD CONSTRAINT marketing_plan_review_turn_check1 CHECK (((move <> ALL (ARRAY['request_changes'::text, 'reject'::text])) OR ((changes IS NOT NULL) AND (jsonb_array_length(changes) > 0))));
ALTER TABLE public.marketing_plan_review_turn ADD CONSTRAINT marketing_plan_review_turn_check2 CHECK (((seat <> 'ceo'::text) OR (criteria IS NOT NULL)));
ALTER TABLE public.marketing_plan_review_turn ADD CONSTRAINT marketing_plan_review_turn_evidence_check CHECK (((jsonb_typeof(evidence) = 'array'::text) AND (jsonb_array_length(evidence) > 0)));
ALTER TABLE public.marketing_plan_review_turn ADD CONSTRAINT marketing_plan_review_turn_move_check CHECK ((move = ANY (ARRAY['propose'::text, 'adjust'::text, 'defend'::text, 'accept'::text, 'request_changes'::text, 'reject'::text, 'decide'::text])));
ALTER TABLE public.marketing_plan_review_turn ADD CONSTRAINT marketing_plan_review_turn_reasoning_check CHECK ((length(btrim(reasoning)) >= 40));
ALTER TABLE public.marketing_plan_review_turn ADD CONSTRAINT marketing_plan_review_turn_round_check CHECK (((round >= 1) AND (round <= 3)));
ALTER TABLE public.marketing_plan_review_turn ADD CONSTRAINT marketing_plan_review_turn_seat_check CHECK ((seat = ANY (ARRAY['marketing'::text, 'ceo'::text])));
ALTER TABLE public.marketing_platform_spec ADD CONSTRAINT marketing_platform_spec_confidence_check CHECK ((confidence = ANY (ARRAY['high'::text, 'medium'::text, 'low'::text])));
ALTER TABLE public.marketing_platform_spec ADD CONSTRAINT marketing_platform_spec_counted_as_check CHECK ((counted_as = ANY (ARRAY['codepoints'::text, 'utf16_units'::text, 'x_weighted'::text, 'utf8_bytes'::text])));
ALTER TABLE public.marketing_platform_spec ADD CONSTRAINT marketing_platform_spec_platform_check CHECK ((platform = ANY (ARRAY['instagram'::text, 'facebook'::text, 'x'::text, 'youtube'::text, 'linkedin'::text, 'tiktok'::text])));
ALTER TABLE public.marketing_platform_spec ADD CONSTRAINT marketing_platform_spec_source_kind_check CHECK ((source_kind = ANY (ARRAY['official'::text, 'postiz'::text])));
ALTER TABLE public.marketing_platform_spec ADD CONSTRAINT marketing_platform_spec_source_url_check CHECK ((source_url ~ '^https://'::text));
ALTER TABLE public.marketing_platform_spec ADD CONSTRAINT marketing_platform_spec_surface_check CHECK ((surface = ANY (ARRAY['feed_image'::text, 'carousel'::text, 'reel'::text, 'feed_post'::text, 'post'::text, 'video'::text, 'short'::text, 'page_post'::text, 'photo'::text])));
ALTER TABLE public.marketing_platform_spec ADD CONSTRAINT marketing_platform_spec_value_or_silence CHECK (((value_num IS NOT NULL) OR (value_text IS NOT NULL) OR (btrim(COALESCE(note, ''::text)) <> ''::text)));
ALTER TABLE public.marketing_platform_spec_source ADD CONSTRAINT marketing_platform_spec_source_source_url_check CHECK ((source_url ~ '^https://'::text));
ALTER TABLE public.marketing_post ADD CONSTRAINT marketing_post_channel_outcome_check CHECK (((channel_outcome IS NULL) OR (channel_outcome = ANY (ARRAY['pending'::text, 'published'::text, 'partial'::text, 'failed'::text]))));
ALTER TABLE public.marketing_post ADD CONSTRAINT marketing_post_channels_check CHECK (((cardinality(channels) > 0) AND (channels <@ ARRAY['facebook'::text, 'instagram'::text, 'linkedin'::text, 'x'::text, 'youtube'::text, 'tiktok'::text])));
ALTER TABLE public.marketing_post ADD CONSTRAINT marketing_post_cover_sha256_check CHECK ((cover_sha256 ~ '^[0-9a-f]{64}$'::text));
ALTER TABLE public.marketing_post ADD CONSTRAINT marketing_post_cta_url_check CHECK ((cta_url ~ '^https://'::text));
ALTER TABLE public.marketing_post ADD CONSTRAINT marketing_post_demo_is_marked CHECK (((NOT is_demo) OR (text_en ~~ 'ZZ DEMO%'::text)));
ALTER TABLE public.marketing_post ADD CONSTRAINT marketing_post_demo_text_is_flagged CHECK ((is_demo OR (((((text_en || ' '::text) || COALESCE(text_ar, ''::text)) || ' '::text) || COALESCE(title, ''::text)) !~* 'zz[ _-]?demo'::text)));
ALTER TABLE public.marketing_post ADD CONSTRAINT marketing_post_failed_says_why CHECK (((status <> 'failed'::text) OR (error IS NOT NULL)));
ALTER TABLE public.marketing_post ADD CONSTRAINT marketing_post_ingest_key_check CHECK ((ingest_key ~ '^[a-z0-9][a-z0-9_-]{2,80}$'::text));
ALTER TABLE public.marketing_post ADD CONSTRAINT marketing_post_ingested_by_check CHECK ((ingested_by = ANY (ARRAY['founder'::text, 'claude'::text, 'marketing'::text])));
ALTER TABLE public.marketing_post ADD CONSTRAINT marketing_post_instagram_needs_media CHECK (((NOT ('instagram'::text = ANY (channels))) OR (cardinality(media_paths) > 0)));
ALTER TABLE public.marketing_post ADD CONSTRAINT marketing_post_local_time_is_dubai CHECK (((scheduled_local IS NULL) OR (scheduled_local = (scheduled_at AT TIME ZONE 'Asia/Dubai'::text))));
ALTER TABLE public.marketing_post ADD CONSTRAINT marketing_post_owner_seat_check CHECK ((owner_seat = 'marketing'::text));
ALTER TABLE public.marketing_post ADD CONSTRAINT marketing_post_published_says_when CHECK (((status <> 'published'::text) OR (published_at IS NOT NULL)));
ALTER TABLE public.marketing_post ADD CONSTRAINT marketing_post_scheduled_has_a_time CHECK (((status <> ALL (ARRAY['scheduled'::text, 'publishing'::text, 'published'::text])) OR (scheduled_at IS NOT NULL)));
ALTER TABLE public.marketing_post ADD CONSTRAINT marketing_post_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'scheduled'::text, 'publishing'::text, 'unconfirmed'::text, 'published'::text, 'failed'::text, 'cancelled'::text])));
ALTER TABLE public.marketing_post ADD CONSTRAINT marketing_post_text_ar_check CHECK (((text_ar IS NULL) OR (text_ar ~ '[؀-ۿ]'::text)));
ALTER TABLE public.marketing_post ADD CONSTRAINT marketing_post_text_en_check CHECK ((btrim(text_en) <> ''::text));
ALTER TABLE public.marketing_post ADD CONSTRAINT marketing_post_video_sha256_check CHECK ((video_sha256 ~ '^[0-9a-f]{64}$'::text));
ALTER TABLE public.marketing_post_channel_result ADD CONSTRAINT marketing_post_channel_result_cause_check CHECK (((cause IS NULL) OR (cause ~ '^[a-z_]+$'::text)));
ALTER TABLE public.marketing_post_channel_result ADD CONSTRAINT marketing_post_channel_result_channel_check CHECK ((channel = ANY (ARRAY['facebook'::text, 'instagram'::text, 'linkedin'::text, 'x'::text, 'youtube'::text, 'tiktok'::text])));
ALTER TABLE public.marketing_post_channel_result ADD CONSTRAINT marketing_post_channel_result_platform_message_check CHECK (((platform_message IS NULL) OR (length(platform_message) <= 1000)));
ALTER TABLE public.marketing_post_channel_result ADD CONSTRAINT marketing_post_channel_result_release_url_check CHECK (((release_url IS NULL) OR (release_url ~ '^https://'::text)));
ALTER TABLE public.marketing_post_channel_result ADD CONSTRAINT marketing_post_channel_result_says_why CHECK (((state <> ALL (ARRAY['partial'::text, 'failed'::text])) OR ((platform_message IS NOT NULL) AND (cause IS NOT NULL))));
ALTER TABLE public.marketing_post_channel_result ADD CONSTRAINT marketing_post_channel_result_state_check CHECK ((state = ANY (ARRAY['pending'::text, 'published'::text, 'partial'::text, 'failed'::text])));
ALTER TABLE public.marketing_post_metric ADD CONSTRAINT marketing_post_metric_checkpoint_check CHECK ((checkpoint = ANY (ARRAY['1d'::text, '3d'::text, '7d'::text, '28d'::text])));
ALTER TABLE public.marketing_post_metric ADD CONSTRAINT marketing_post_metric_metric_check CHECK ((metric ~ '^[a-z0-9_*]+$'::text));
ALTER TABLE public.marketing_post_metric ADD CONSTRAINT marketing_post_metric_platform_check CHECK ((platform = ANY (ARRAY['facebook'::text, 'instagram'::text, 'linkedin'::text, 'x'::text, 'youtube'::text, 'tiktok'::text])));
ALTER TABLE public.marketing_post_metric ADD CONSTRAINT marketing_post_metric_value_or_reason CHECK (((value IS NULL) <> (unavailable_reason IS NULL)));
ALTER TABLE public.marketing_post_platform ADD CONSTRAINT marketing_post_platform_has_an_id CHECK (((postiz_post_id IS NOT NULL) OR (platform_post_id IS NOT NULL)));
ALTER TABLE public.marketing_post_platform ADD CONSTRAINT marketing_post_platform_platform_check CHECK ((platform = ANY (ARRAY['facebook'::text, 'instagram'::text, 'linkedin'::text, 'x'::text, 'youtube'::text, 'tiktok'::text])));
ALTER TABLE public.marketing_post_variant ADD CONSTRAINT marketing_post_variant_arabic_is_arabic CHECK (((language = 'en'::text) OR (caption ~ '[؀-ۿ]'::text)));
ALTER TABLE public.marketing_post_variant ADD CONSTRAINT marketing_post_variant_caption_check CHECK ((btrim(caption) <> ''::text));
ALTER TABLE public.marketing_post_variant ADD CONSTRAINT marketing_post_variant_hashtags_check CHECK (fn_marketing_hashtags_ok(hashtags));
ALTER TABLE public.marketing_post_variant ADD CONSTRAINT marketing_post_variant_language_check CHECK ((language = ANY (ARRAY['en'::text, 'ar'::text, 'bi'::text])));
ALTER TABLE public.marketing_post_variant ADD CONSTRAINT marketing_post_variant_platform_check CHECK ((platform = ANY (ARRAY['facebook'::text, 'instagram'::text, 'linkedin'::text, 'x'::text, 'youtube'::text, 'tiktok'::text])));
ALTER TABLE public.marketing_post_variant ADD CONSTRAINT marketing_post_variant_post_type_check CHECK ((post_type = ANY (ARRAY['reel'::text, 'short'::text, 'post'::text, 'video'::text])));
ALTER TABLE public.marketing_post_variant ADD CONSTRAINT marketing_post_variant_seq_check CHECK (((seq >= 1) AND (seq <= 5)));
ALTER TABLE public.marketing_post_variant ADD CONSTRAINT marketing_post_variant_type_fits_platform CHECK ((((platform = 'instagram'::text) AND (post_type = ANY (ARRAY['reel'::text, 'post'::text]))) OR ((platform = 'youtube'::text) AND (post_type = ANY (ARRAY['short'::text, 'video'::text]))) OR ((platform = 'facebook'::text) AND (post_type = ANY (ARRAY['reel'::text, 'video'::text, 'post'::text]))) OR ((platform = ANY (ARRAY['linkedin'::text, 'x'::text])) AND (post_type = ANY (ARRAY['video'::text, 'post'::text]))) OR ((platform = 'tiktok'::text) AND (post_type = 'video'::text))));
ALTER TABLE public.marketing_post_variant ADD CONSTRAINT marketing_post_variant_youtube_has_a_title CHECK (((platform <> 'youtube'::text) OR (btrim(COALESCE(title, ''::text)) <> ''::text)));
ALTER TABLE public.marketing_prospect ADD CONSTRAINT marketing_prospect_company_check CHECK ((btrim(company) <> ''::text));
ALTER TABLE public.marketing_prospect ADD CONSTRAINT marketing_prospect_demo_is_marked CHECK (((NOT is_demo) OR (full_name ~~ 'ZZ DEMO%'::text)));
ALTER TABLE public.marketing_prospect ADD CONSTRAINT marketing_prospect_emirate_check CHECK ((emirate = ANY (ARRAY['abu_dhabi'::text, 'dubai'::text, 'sharjah'::text, 'ajman'::text, 'umm_al_quwain'::text, 'ras_al_khaimah'::text, 'fujairah'::text])));
ALTER TABLE public.marketing_prospect ADD CONSTRAINT marketing_prospect_full_name_check CHECK ((btrim(full_name) <> ''::text));
ALTER TABLE public.marketing_prospect ADD CONSTRAINT marketing_prospect_hook_is_cited CHECK (((opening_line IS NULL) OR (opening_line_url ~ '^https://'::text)));
ALTER TABLE public.marketing_prospect ADD CONSTRAINT marketing_prospect_language_check CHECK ((language = ANY (ARRAY['en'::text, 'ar'::text])));
ALTER TABLE public.marketing_prospect ADD CONSTRAINT marketing_prospect_linkedin_url_check CHECK ((linkedin_url ~ '^https://([a-z]{2,3}\.)?linkedin\.com/in/[A-Za-z0-9_%-]+/?$'::text));
ALTER TABLE public.marketing_prospect ADD CONSTRAINT marketing_prospect_opening_line_check CHECK (((opening_line IS NULL) OR (length(opening_line) <= 200)));
ALTER TABLE public.marketing_prospect ADD CONSTRAINT marketing_prospect_researched_by_check CHECK ((researched_by = ANY (ARRAY['founder'::text, 'claude'::text, 'marketing'::text])));
ALTER TABLE public.marketing_prospect ADD CONSTRAINT marketing_prospect_role_title_check CHECK ((btrim(role_title) <> ''::text));
ALTER TABLE public.marketing_prospect ADD CONSTRAINT marketing_prospect_segment_check CHECK ((segment = ANY (ARRAY['developer'::text, 'contractor_procurement'::text, 'consultant'::text, 'facility_manager'::text])));
ALTER TABLE public.marketing_prospect ADD CONSTRAINT marketing_prospect_source_urls_check CHECK ((cardinality(source_urls) > 0));
ALTER TABLE public.marketing_prospect ADD CONSTRAINT marketing_prospect_status_check CHECK ((status = ANY (ARRAY['new'::text, 'listed'::text, 'sent'::text, 'replied'::text, 'converted'::text, 'declined'::text])));
ALTER TABLE public.marketing_recruitment_source ADD CONSTRAINT marketing_recruitment_source_kind_check CHECK ((kind = ANY (ARRAY['directory'::text, 'association'::text, 'chamber'::text, 'linkedin_group'::text, 'trade_fair'::text])));
ALTER TABLE public.marketing_recruitment_source ADD CONSTRAINT marketing_recruitment_source_url_check CHECK ((url ~ '^https?://'::text));
ALTER TABLE public.marketing_report ADD CONSTRAINT marketing_report_check CHECK ((window_to > window_from));
ALTER TABLE public.marketing_report ADD CONSTRAINT marketing_report_figures_check CHECK ((jsonb_typeof(figures) = 'object'::text));
ALTER TABLE public.marketing_review ADD CONSTRAINT marketing_review_kind_check CHECK ((kind = ANY (ARRAY['geo_monthly'::text, 'brand_quarterly'::text])));
ALTER TABLE public.marketing_scorecard_report ADD CONSTRAINT marketing_scorecard_report_kind_check CHECK ((kind = ANY (ARRAY['weekly'::text, 'month_end'::text])));
ALTER TABLE public.marketing_scorecard_report ADD CONSTRAINT marketing_scorecard_report_month_check CHECK ((month ~ '^\d{4}-(0[1-9]|1[0-2])$'::text));
ALTER TABLE public.marketing_scorecard_report ADD CONSTRAINT marketing_scorecard_report_owner_seat_check CHECK ((owner_seat = 'marketing'::text));
ALTER TABLE public.marketing_scorecard_report ADD CONSTRAINT marketing_scorecard_report_period_key_check CHECK ((period_key ~ '^\d{4}-(W\d{2}|\d{2}-end)$'::text));
ALTER TABLE public.marketing_trend ADD CONSTRAINT marketing_trend_check CHECK (((relevant IS DISTINCT FROM true) OR (COALESCE(btrim(why_it_matters), ''::text) <> ''::text)));
ALTER TABLE public.marketing_trend_source ADD CONSTRAINT marketing_trend_source_feed_url_check CHECK ((feed_url ~ '^https://'::text));
ALTER TABLE public.marketing_trend_source ADD CONSTRAINT marketing_trend_source_kind_check CHECK ((kind = ANY (ARRAY['news'::text, 'search'::text, 'regulation'::text])));
ALTER TABLE public.marketing_video_idea ADD CONSTRAINT marketing_video_idea_audience_check CHECK ((audience = ANY (ARRAY['supplier'::text, 'customer'::text, 'both'::text])));
ALTER TABLE public.marketing_video_idea ADD CONSTRAINT marketing_video_idea_cta_check CHECK ((btrim(cta) <> ''::text));
ALTER TABLE public.marketing_video_idea ADD CONSTRAINT marketing_video_idea_film_plan_check CHECK ((btrim(film_plan) <> ''::text));
ALTER TABLE public.marketing_video_idea ADD CONSTRAINT marketing_video_idea_hook_check CHECK ((btrim(hook) <> ''::text));
ALTER TABLE public.marketing_video_idea ADD CONSTRAINT marketing_video_idea_idea_key_check CHECK ((idea_key ~ '^[a-z0-9][a-z0-9-]{2,60}$'::text));
ALTER TABLE public.marketing_video_idea ADD CONSTRAINT marketing_video_idea_title_check CHECK ((btrim(title) <> ''::text));
ALTER TABLE public.messages ADD CONSTRAINT messages_sender_check CHECK ((sender = ANY (ARRAY['customer'::text, 'supplier'::text])));
ALTER TABLE public.metric_definition ADD CONSTRAINT metric_definition_direction_check CHECK ((direction = ANY (ARRAY['up'::text, 'down'::text])));
ALTER TABLE public.metric_definition ADD CONSTRAINT metric_definition_domain_check CHECK ((domain = ANY (ARRAY['demand'::text, 'supply'::text, 'liquidity'::text, 'revenue'::text, 'quality'::text, 'cost'::text, 'ops'::text])));
ALTER TABLE public.model_catalogue_change ADD CONSTRAINT model_catalogue_change_field_check CHECK ((field = ANY (ARRAY['in'::text, 'out'::text, 'ctx'::text, 'absent'::text])));
ALTER TABLE public.model_catalogue_change ADD CONSTRAINT model_catalogue_change_outcome_check CHECK ((outcome = 'resolved'::text));
ALTER TABLE public.model_fallback_chain ADD CONSTRAINT model_fallback_chain_kind_check CHECK ((kind = ANY (ARRAY['model'::text, 'deterministic'::text])));
ALTER TABLE public.model_policy_by_identity ADD CONSTRAINT model_policy_by_identity_scope_check CHECK ((scope = ANY (ARRAY['target_employee'::text, 'current_agent'::text])));
ALTER TABLE public.model_registry ADD CONSTRAINT model_registry_tier_check CHECK ((tier = ANY (ARRAY['small'::text, 'medium'::text, 'large'::text, 'xlarge'::text])));
ALTER TABLE public.money_move_hold ADD CONSTRAINT money_move_hold_check CHECK (((status = 'released'::text) = (released_at IS NOT NULL)));
ALTER TABLE public.money_move_hold ADD CONSTRAINT money_move_hold_check1 CHECK (((status <> 'released'::text) OR (btrim(COALESCE(released_by, ''::text)) <> ''::text)));
ALTER TABLE public.money_move_hold ADD CONSTRAINT money_move_hold_move_check CHECK ((move = ANY (ARRAY['reveal'::text, 'refund'::text])));
ALTER TABLE public.money_move_hold ADD CONSTRAINT money_move_hold_ref_check CHECK ((btrim(ref) <> ''::text));
ALTER TABLE public.money_move_hold ADD CONSTRAINT money_move_hold_status_check CHECK ((status = ANY (ARRAY['noted'::text, 'held'::text, 'released'::text])));
ALTER TABLE public.notice_plain_language ADD CONSTRAINT notice_plain_language_lang_check CHECK ((lang = ANY (ARRAY['en'::text, 'ar'::text])));
ALTER TABLE public.notice_plain_language ADD CONSTRAINT notice_plain_language_score_check CHECK (((score >= 0) AND (score <= 100)));
ALTER TABLE public.notice_plain_language ADD CONSTRAINT notice_plain_language_tone_check CHECK (((tone >= 0) AND (tone <= 100)));
ALTER TABLE public.notice_plain_language_cause ADD CONSTRAINT notice_plain_language_cause_status_check CHECK ((status = ANY (ARRAY['open'::text, 'handed_off'::text, 'closed'::text])));
ALTER TABLE public.notification_type_severity ADD CONSTRAINT notification_type_severity_reason_check CHECK ((btrim(reason) <> ''::text));
ALTER TABLE public.notification_type_severity ADD CONSTRAINT notification_type_severity_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'warn'::text, 'high'::text, 'critical'::text])));
ALTER TABLE public.notification_type_severity ADD CONSTRAINT notification_type_severity_type_check CHECK ((btrim(type) <> ''::text));
ALTER TABLE public.notifications ADD CONSTRAINT notifications_lang_is_en_or_ar CHECK (((lang IS NULL) OR (lang = ANY (ARRAY['en'::text, 'ar'::text]))));
ALTER TABLE public.notifications ADD CONSTRAINT notifications_provider_status_known CHECK (((provider_status IS NULL) OR (provider_status = ANY (ARRAY['accepted'::text, 'scheduled'::text, 'queued'::text, 'sending'::text, 'sent'::text, 'delivered'::text, 'undelivered'::text, 'failed'::text, 'read'::text, 'unrecorded'::text, 'unreadable'::text]))));
ALTER TABLE public.notifications ADD CONSTRAINT notifications_reply_to_is_our_inbound CHECK (((reply_to IS NULL) OR (reply_to ~ '^[a-z0-9._+-]+@mail\.quotesdone\.com$'::text))) NOT VALID;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_sender_is_customer_support CHECK (((sender = 'customer_support'::text) OR ((sender = 'platform_otp'::text) AND (type = ANY (ARRAY['login_otp'::text, 'mobile_otp'::text, 'voice_otp'::text, 'email_confirmation_code'::text])))));
ALTER TABLE public.notifications ADD CONSTRAINT notifications_severity_check CHECK (((severity IS NULL) OR (severity = ANY (ARRAY['info'::text, 'warn'::text, 'high'::text, 'critical'::text]))));
ALTER TABLE public.openrouter_day ADD CONSTRAINT openrouter_day_basis_check CHECK ((authoritative_basis = ANY (ARRAY['measured'::text, 'true zero'::text, 'unknown'::text])));
ALTER TABLE public.opportunity ADD CONSTRAINT opportunity_effort_check CHECK ((effort = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text])));
ALTER TABLE public.opportunity ADD CONSTRAINT opportunity_status_check CHECK ((status = ANY (ARRAY['open'::text, 'pursuing'::text, 'won'::text, 'dismissed'::text])));
ALTER TABLE public.ops_knowledge ADD CONSTRAINT ops_knowledge_layer_ck CHECK (((layer IS NULL) OR (layer = ANY (ARRAY['company_core'::text, 'department_shared'::text, 'role_specific'::text, 'task_specific'::text, 'category_specialist'::text, 'validated_experience'::text, 'policy'::text, 'authority'::text, 'kpi'::text, 'decision_playbook'::text, 'case_training'::text, 'failure_mode'::text, 'remediation'::text, 'source_reference'::text, 'it_security_deep'::text]))));
ALTER TABLE public.ops_knowledge ADD CONSTRAINT ops_knowledge_supersession_ck CHECK ((supersession_state = ANY (ARRAY['current'::text, 'superseded'::text, 'withdrawn'::text])));
ALTER TABLE public.org_action_executor ADD CONSTRAINT org_action_executor_idem_chk CHECK (((idempotency_strategy IS NULL) OR (idempotency_strategy = ANY (ARRAY['natural_key'::text, 'request_hash'::text, 'external_id'::text, 'upsert_on_conflict'::text, 'none_read_only'::text]))));
ALTER TABLE public.org_action_executor ADD CONSTRAINT org_action_executor_kind_check CHECK ((kind = ANY (ARRAY['rpc'::text, 'edge'::text])));
ALTER TABLE public.org_action_executor ADD CONSTRAINT org_action_executor_money_legal_second CHECK (((NOT ((department = ANY (ARRAY['finance'::text, 'legal'::text])) AND (risk_tier = ANY (ARRAY['medium'::text, 'high'::text])))) OR (second_authority IS NOT NULL)));
ALTER TABLE public.org_action_executor ADD CONSTRAINT org_action_executor_risk_tier_chk CHECK ((risk_tier = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text])));
ALTER TABLE public.org_action_executor ADD CONSTRAINT org_action_executor_unattended_by_risk CHECK (((NOT COALESCE(unattended_ok, false)) OR (COALESCE(reversible, false) AND (risk_tier <> 'high'::text) AND ((risk_tier = 'low'::text) OR (COALESCE(NULLIF(required_authority, ''::text), ''::text) <> ''::text)))));
ALTER TABLE public.org_agents ADD CONSTRAINT org_agents_routing_tier_check CHECK (((routing_tier IS NULL) OR (routing_tier = ANY (ARRAY['director'::text, 'analyst_controller'::text, 'operations_specialist'::text, 'reviewer_auditor'::text]))));
ALTER TABLE public.org_authority ADD CONSTRAINT org_authority_max_tier_check CHECK ((max_tier = ANY (ARRAY['advisory'::text, 'gated'::text, 'supervised'::text, 'autonomous'::text])));
ALTER TABLE public.org_objectives ADD CONSTRAINT org_objectives_status_check CHECK ((status = ANY (ARRAY['open'::text, 'in_progress'::text, 'blocked'::text, 'done'::text, 'cancelled'::text])));
ALTER TABLE public.org_onboarding ADD CONSTRAINT org_onboarding_status_check CHECK ((status = ANY (ARRAY['onboarding'::text, 'probation'::text, 'certified'::text, 'recert_due'::text])));
ALTER TABLE public.org_reporting_edge ADD CONSTRAINT org_reporting_edge_not_self CHECK ((child_role_id <> parent_role_id));
ALTER TABLE public.org_role ADD CONSTRAINT org_role_authority_ck CHECK ((authority_level = ANY (ARRAY['advisory'::text, 'execute_low'::text, 'execute_medium'::text, 'execute_high'::text, 'stop_authority'::text])));
ALTER TABLE public.org_role ADD CONSTRAINT org_role_no_self_manage_ck CHECK ((manager_role_id IS DISTINCT FROM role_id));
ALTER TABLE public.org_role ADD CONSTRAINT org_role_runtime_mode_ck CHECK ((runtime_mode = ANY (ARRAY['persistent_manager'::text, 'scheduled_manager'::text, 'event_driven_operator'::text, 'on_demand_specialist'::text, 'knowledge_overlay'::text, 'independent_reviewer'::text])));
ALTER TABLE public.org_role ADD CONSTRAINT org_role_status_ck CHECK ((status = ANY (ARRAY['active'::text, 'deferred'::text, 'retired'::text])));
ALTER TABLE public.org_role_alias ADD CONSTRAINT org_role_alias_kind_ck CHECK ((kind = ANY (ARRAY['legacy_agent_key'::text, 'legacy_role_id'::text, 'packaged_role_id'::text, 'title'::text, 'merged_role'::text])));
ALTER TABLE public.org_role_committee ADD CONSTRAINT org_role_committee_seat_ck CHECK ((seat = ANY (ARRAY['chair'::text, 'member'::text, 'observer'::text, 'secretary'::text, 'standing_adviser'::text])));
ALTER TABLE public.org_role_identity ADD CONSTRAINT org_role_identity_archetype_check CHECK ((archetype = ANY (ARRAY['director'::text, 'operations-specialist'::text, 'analyst-controller'::text, 'reviewer-auditor'::text])));
ALTER TABLE public.org_role_identity ADD CONSTRAINT org_role_identity_mapping_type_check CHECK ((mapping_type = ANY (ARRAY['one_to_one'::text, 'runtime_composite'::text, 'package_composite'::text, 'duplicate_role'::text, 'missing_runtime_agent'::text, 'obsolete_runtime_agent'::text, 'on_demand_specialist'::text, 'requires_split'::text, 'requires_merge'::text])));
ALTER TABLE public.org_role_identity ADD CONSTRAINT org_role_identity_readiness_check CHECK ((readiness = ANY (ARRAY['knowledge_imported'::text, 'runtime_mapped'::text, 'tools_connected'::text, 'live_data_connected'::text, 'decision_trace_connected'::text, 'training_passed'::text, 'independent_certification_pending'::text, 'certified_for_defined_role_scope'::text, 'blocked'::text, 'restricted_to_advisory'::text])));
ALTER TABLE public.org_task_question_reading ADD CONSTRAINT org_task_question_reading_check CHECK (((status = 'reasoned'::text) OR ((trade IS NULL) AND (faq_id IS NULL))));
ALTER TABLE public.org_task_question_reading ADD CONSTRAINT org_task_question_reading_check1 CHECK (((trade IS NULL) OR (faq_id IS NULL)));
ALTER TABLE public.org_task_question_reading ADD CONSTRAINT org_task_question_reading_question_md5_check CHECK ((question_md5 ~ '^[0-9a-f]{32}$'::text));
ALTER TABLE public.org_task_question_reading ADD CONSTRAINT org_task_question_reading_status_check CHECK ((status = ANY (ARRAY['reasoned'::text, 'needs_reasoning'::text])));
ALTER TABLE public.org_tasks ADD CONSTRAINT org_tasks_status_check CHECK ((status = ANY (ARRAY['proposed'::text, 'assigned'::text, 'in_progress'::text, 'blocked'::text, 'done'::text, 'failed'::text, 'escalated'::text, 'cancelled'::text])));
ALTER TABLE public.org_tasks ADD CONSTRAINT org_tasks_tier_check CHECK ((tier = ANY (ARRAY['advisory'::text, 'gated'::text, 'supervised'::text, 'autonomous'::text])));
ALTER TABLE public.org_workflow_ownership ADD CONSTRAINT org_workflow_ownership_reviewer_is_independent_ck CHECK (((independent_reviewer IS NULL) OR (independent_reviewer <> accountable_role_id)));
ALTER TABLE public.os_interface ADD CONSTRAINT os_interface_direction_check CHECK ((direction = ANY (ARRAY['input'::text, 'output'::text])));
ALTER TABLE public.os_interface ADD CONSTRAINT os_interface_planned_dated CHECK (((NOT COALESCE(planned, false)) OR (planned_until IS NOT NULL)));
ALTER TABLE public.os_interface ADD CONSTRAINT os_interface_severity_check CHECK ((severity = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text])));
ALTER TABLE public.os_knowledge_domain ADD CONSTRAINT os_knowledge_domain_ownership_check CHECK ((ownership = ANY (ARRAY['owns'::text, 'queries'::text])));
ALTER TABLE public.os_objective ADD CONSTRAINT os_objective_horizon_check CHECK ((horizon = ANY (ARRAY['strategic'::text, 'annual'::text, 'quarterly'::text, 'weekly'::text, 'daily'::text])));
ALTER TABLE public.os_open_access_log ADD CONSTRAINT os_open_access_log_state_ck CHECK ((state = ANY (ARRAY['open'::text, 'closed'::text])));
ALTER TABLE public.os_review ADD CONSTRAINT os_review_health_check CHECK ((health = ANY (ARRAY['green'::text, 'amber'::text, 'red'::text])));
ALTER TABLE public.os_settings_meta ADD CONSTRAINT os_settings_meta_type_check CHECK ((type = ANY (ARRAY['money'::text, 'int'::text, 'number'::text, 'bool'::text, 'text'::text, 'textarea'::text, 'html'::text, 'email'::text, 'phone'::text, 'csv'::text])));
ALTER TABLE public.otp_blocked_prefix ADD CONSTRAINT otp_blocked_prefix_prefix_check CHECK ((prefix ~ '^[0-9]{3,8}$'::text));
ALTER TABLE public.otp_blocked_prefix ADD CONSTRAINT otp_blocked_prefix_reason_check CHECK ((btrim(reason) <> ''::text));
ALTER TABLE public.otp_prefix_allowed ADD CONSTRAINT otp_prefix_allowed_allowed_by_check CHECK ((allowed_by = ANY (ARRAY['ceo'::text, 'founder'::text, 'otp_served_country'::text])));
ALTER TABLE public.otp_prefix_allowed ADD CONSTRAINT otp_prefix_allowed_prefix_check CHECK ((prefix ~ '^[0-9]{3,8}$'::text));
ALTER TABLE public.otp_prefix_allowed ADD CONSTRAINT otp_prefix_allowed_reason_check CHECK ((btrim(reason) <> ''::text));
ALTER TABLE public.otp_served_country ADD CONSTRAINT otp_served_country_prefix_check CHECK ((prefix ~ '^[0-9]{1,4}$'::text));
ALTER TABLE public.outcome_record ADD CONSTRAINT outcome_record_expected_direction_check CHECK ((expected_direction = ANY (ARRAY['up'::text, 'down'::text])));
ALTER TABLE public.outcome_record ADD CONSTRAINT outcome_record_verdict_check CHECK ((verdict = ANY (ARRAY['pending'::text, 'improved'::text, 'no_change'::text, 'worse'::text, 'unmeasurable'::text])));
ALTER TABLE public.outreach_channel_policy ADD CONSTRAINT outreach_channel_limit_basis_ck CHECK ((limit_basis = ANY (ARRAY['founder_ruling'::text, 'provider_published'::text, 'measured_here'::text, 'practitioner_norm'::text, 'estimate'::text])));
ALTER TABLE public.outreach_channel_policy ADD CONSTRAINT outreach_channel_open_needs_a_limit CHECK (((status <> 'open'::text) OR (max_per_day IS NOT NULL)));
ALTER TABLE public.outreach_channel_policy ADD CONSTRAINT outreach_channel_operator_kind_ck CHECK (((operator_kind IS NULL) OR (operator_kind = ANY (ARRAY['founder'::text, 'agent'::text, 'human_hire'::text, 'none'::text]))));
ALTER TABLE public.outreach_channel_policy ADD CONSTRAINT outreach_channel_policy_status_check CHECK ((status = ANY (ARRAY['open'::text, 'warming'::text, 'blocked'::text])));
ALTER TABLE public.paid_route_exception ADD CONSTRAINT paid_route_exception_daily_cap_aed_check CHECK ((daily_cap_aed >= (0)::numeric));
ALTER TABLE public.paid_route_exception ADD CONSTRAINT paid_route_exception_max_tokens_per_call_check CHECK (((max_tokens_per_call >= 1) AND (max_tokens_per_call <= 4000)));
ALTER TABLE public.pdpl_requests ADD CONSTRAINT pdpl_requests_kind_check CHECK ((kind = ANY (ARRAY['export'::text, 'delete'::text])));
ALTER TABLE public.phase1_rollback_log ADD CONSTRAINT phase1_rollback_log_reason_check CHECK ((length(btrim(reason)) >= 8));
ALTER TABLE public.phase1_rollback_log ADD CONSTRAINT phase1_rollback_log_tier_check CHECK ((tier = ANY (ARRAY['disarm'::text, 'rearm'::text, 'revert'::text, 'teardown'::text, 'rehearse'::text])));
ALTER TABLE public.phone_code ADD CONSTRAINT phone_code_purpose_check CHECK ((purpose = ANY (ARRAY['login'::text, 'kyc_phone'::text, 'kyc_whatsapp'::text])));
ALTER TABLE public.po_lines ADD CONSTRAINT po_lines_qty_check CHECK ((qty > (0)::numeric));
ALTER TABLE public.po_lines ADD CONSTRAINT po_lines_unit_price_money_ck CHECK ((unit_price >= (0)::numeric));
ALTER TABLE public.po_orders ADD CONSTRAINT po_orders_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text, 'partial'::text, 'received'::text, 'billed'::text, 'closed'::text, 'cancelled'::text])));
ALTER TABLE public.post_reveal_dispute ADD CONSTRAINT post_reveal_dispute_check CHECK (((stage = 'decided'::text) = (outcome IS NOT NULL)));
ALTER TABLE public.post_reveal_dispute ADD CONSTRAINT post_reveal_dispute_decided_by_check CHECK ((decided_by = 'ceo'::text));
ALTER TABLE public.post_reveal_dispute ADD CONSTRAINT post_reveal_dispute_finding_check CHECK ((finding = ANY (ARRAY['customer_upheld'::text, 'supplier_upheld'::text, 'shared'::text, 'no_fault'::text])));
ALTER TABLE public.post_reveal_dispute ADD CONSTRAINT post_reveal_dispute_outcome_check CHECK ((outcome = ANY (ARRAY['customer_upheld'::text, 'supplier_upheld'::text, 'shared'::text, 'no_fault'::text])));
ALTER TABLE public.post_reveal_dispute ADD CONSTRAINT post_reveal_dispute_raised_by_check CHECK ((raised_by = ANY (ARRAY['customer'::text, 'supplier'::text])));
ALTER TABLE public.post_reveal_dispute ADD CONSTRAINT post_reveal_dispute_stage_check CHECK ((stage = ANY (ARRAY['evidence'::text, 'review'::text, 'ceo_decision'::text, 'decided'::text])));
ALTER TABLE public.post_reveal_dispute ADD CONSTRAINT post_reveal_dispute_statement_check CHECK ((btrim(statement) <> ''::text));
ALTER TABLE public.price_benchmark ADD CONSTRAINT price_benchmark_band_ordered CHECK (((low IS NULL) OR (high IS NULL) OR (high >= low)));
ALTER TABLE public.price_benchmark ADD CONSTRAINT price_benchmark_basis_kind_check CHECK ((basis_kind = ANY (ARRAY['per_unit'::text, 'job'::text, 'none'::text])));
ALTER TABLE public.price_benchmark ADD CONSTRAINT price_benchmark_confidence_check CHECK ((confidence = ANY (ARRAY['published'::text, 'machine_extracted'::text, 'none'::text])));
ALTER TABLE public.price_benchmark ADD CONSTRAINT price_benchmark_rate_or_gap CHECK ((((source_kind = 'gap'::text) AND (low IS NULL) AND (high IS NULL) AND (gap_reason IS NOT NULL)) OR ((source_kind <> 'gap'::text) AND (low IS NOT NULL) AND (high IS NOT NULL) AND (gap_reason IS NULL))));
ALTER TABLE public.price_benchmark ADD CONSTRAINT price_benchmark_source_kind_check CHECK ((source_kind = ANY (ARRAY['blog_post'::text, 'kb_chunk'::text, 'gap'::text])));
ALTER TABLE public.pricing_config ADD CONSTRAINT pricing_config_category_open_ck CHECK ((category_open_min_suppliers >= 1));
ALTER TABLE public.pricing_config ADD CONSTRAINT pricing_config_currency_ck CHECK (((supplier_reg_currency = 'AED'::text) AND (reveal_currency = 'AED'::text)));
ALTER TABLE public.pricing_config ADD CONSTRAINT pricing_config_fee_range_ck CHECK (((supplier_reg_fee IS NULL) OR ((supplier_reg_fee >= (500)::numeric) AND (supplier_reg_fee <= (5000)::numeric))));
ALTER TABLE public.pricing_config ADD CONSTRAINT pricing_config_no_discount_no_cap_ck CHECK (((promo_until IS NULL) AND (promo_reveal_rate = standard_reveal_rate) AND (promo_reveal_cap >= (99999999)::numeric) AND (standard_reveal_cap >= (99999999)::numeric)));
ALTER TABLE public.pricing_config ADD CONSTRAINT pricing_config_nonresponse_fee_money_ck CHECK ((supplier_nonresponse_admin_fee_aed >= (0)::numeric));
ALTER TABLE public.pricing_config ADD CONSTRAINT pricing_config_period_ck CHECK ((supplier_reg_period = ANY (ARRAY['yearly'::text, 'monthly'::text])));
ALTER TABLE public.pricing_config ADD CONSTRAINT pricing_config_refund_ladder_ck CHECK (((chase_after_working_days > 0) AND (chase_after_working_days < refund_window_working_days) AND (bank_settlement_working_days_min > 0) AND (bank_settlement_working_days_min <= bank_settlement_working_days_max)));
ALTER TABLE public.pricing_config ADD CONSTRAINT pricing_config_singleton CHECK ((id = 1));
ALTER TABLE public.projects ADD CONSTRAINT projects_budget_total_positive_bounded CHECK (((budget_total IS NULL) OR ((budget_total > (0)::numeric) AND (budget_total <= (1000000000)::numeric))));
ALTER TABLE public.quote_aspect_reading ADD CONSTRAINT quote_aspect_reading_check CHECK (((status = 'needs_reasoning'::text) OR (present IS NOT NULL)));
ALTER TABLE public.quote_aspect_reading ADD CONSTRAINT quote_aspect_reading_content_md5_check CHECK ((content_md5 ~ '^[0-9a-f]{32}$'::text));
ALTER TABLE public.quote_aspect_reading ADD CONSTRAINT quote_aspect_reading_status_check CHECK ((status = ANY (ARRAY['reasoned'::text, 'needs_reasoning'::text])));
ALTER TABLE public.quote_committed_items ADD CONSTRAINT quote_committed_items_line_amount_money_ck CHECK (((line_amount >= (0)::numeric) AND (line_amount = round(line_amount, 2))));
ALTER TABLE public.quote_committed_items ADD CONSTRAINT quote_committed_items_unit_price_money_ck CHECK (((unit_price >= (0)::numeric) AND (unit_price = round(unit_price, 4))));
ALTER TABLE public.quote_comparisons ADD CONSTRAINT quote_comparisons_publication_state_ck CHECK ((publication_state = ANY (ARRAY['DRAFT'::text, 'SUBMITTED'::text, 'UNDER_REVIEW'::text, 'REVISION_REQUIRED'::text, 'APPROVED'::text, 'PUBLISHED'::text, 'WITHDRAWN'::text, 'SUPERSEDED'::text])));
ALTER TABLE public.quote_comparisons ADD CONSTRAINT quote_comparisons_published_is_stamped CHECK (((publication_state <> 'PUBLISHED'::text) OR (published_at IS NOT NULL)));
ALTER TABLE public.quote_extraction_model ADD CONSTRAINT quote_extraction_model_model_check CHECK ((btrim(model) <> ''::text));
ALTER TABLE public.quote_items ADD CONSTRAINT quote_items_amount_money_ck CHECK (((amount >= (0)::numeric) AND (amount = round(amount, 2))));
ALTER TABLE public.quote_items ADD CONSTRAINT quote_items_unit_price_money_ck CHECK (((unit_price >= (0)::numeric) AND (unit_price = round(unit_price, 4))));
ALTER TABLE public.quote_quality_hold ADD CONSTRAINT quote_quality_hold_check CHECK (((released_at IS NULL) = (release_reason IS NULL)));
ALTER TABLE public.quote_quality_hold ADD CONSTRAINT quote_quality_hold_check1 CHECK (((released_at IS NULL) OR (superseded_at IS NULL)));
ALTER TABLE public.quote_quality_hold ADD CONSTRAINT quote_quality_hold_flags_check CHECK ((jsonb_typeof(flags) = 'array'::text));
ALTER TABLE public.quote_quality_hold ADD CONSTRAINT quote_quality_hold_release_reason_check CHECK (((release_reason IS NULL) OR (release_reason = ANY (ARRAY['corrected'::text, 'waited_24h'::text]))));
ALTER TABLE public.quote_review_messages ADD CONSTRAINT quote_review_messages_kind_known CHECK ((kind = ANY (ARRAY['text'::text, 'file'::text, 'review'::text, 'choice_prompt'::text, 'choice'::text, 'submitted'::text, 'notice'::text])));
ALTER TABLE public.quote_review_messages ADD CONSTRAINT quote_review_messages_role_known CHECK ((role = ANY (ARRAY['supplier'::text, 'sales_engineer'::text])));
ALTER TABLE public.quote_review_request ADD CONSTRAINT quote_review_request_check CHECK (((state = 'open'::text) = (answered_at IS NULL)));
ALTER TABLE public.quote_review_request ADD CONSTRAINT quote_review_request_kind_check CHECK ((kind = ANY (ARRAY['adjustment'::text, 'clarification'::text, 'choice'::text])));
ALTER TABLE public.quote_review_request ADD CONSTRAINT quote_review_request_state_check CHECK ((state = ANY (ARRAY['open'::text, 'answered'::text, 'superseded'::text])));
ALTER TABLE public.quote_reviews ADD CONSTRAINT quote_reviews_choice_known CHECK (((choice IS NULL) OR (choice = ANY (ARRAY['generate'::text, 'reupload'::text]))));
ALTER TABLE public.quote_reviews ADD CONSTRAINT quote_reviews_owner_seat CHECK ((owner_seat = 'sales_engineer'::text));
ALTER TABLE public.quote_reviews ADD CONSTRAINT quote_reviews_status_known CHECK ((status = ANY (ARRAY['open'::text, 'reviewing'::text, 'changes_requested'::text, 'awaiting_choice'::text, 'awaiting_upload'::text, 'ready_to_submit'::text, 'submitted'::text, 'closed'::text])));
ALTER TABLE public.quote_reviews ADD CONSTRAINT quote_reviews_submitted_has_quotes CHECK (((status <> 'submitted'::text) OR ((completed_at IS NOT NULL) AND (COALESCE(array_length(submitted_quote_ids, 1), 0) > 0))));
ALTER TABLE public.quote_spec_hold ADD CONSTRAINT quote_spec_hold_owner_seat_check CHECK ((owner_seat = 'sales_engineer'::text));
ALTER TABLE public.quote_spec_hold ADD CONSTRAINT quote_spec_hold_state_check CHECK ((state = ANY (ARRAY['open'::text, 'awaiting_approval'::text, 'released'::text, 'superseded'::text, 'unresolved_at_decision'::text])));
ALTER TABLE public.quotes ADD CONSTRAINT quotes_amount_as_stated_money_ck CHECK (((amount_as_stated >= (0)::numeric) AND (amount_as_stated = round(amount_as_stated, 2))));
ALTER TABLE public.quotes ADD CONSTRAINT quotes_app_fee_money_ck CHECK (((app_fee >= (0)::numeric) AND (app_fee = round(app_fee, 2))));
ALTER TABLE public.quotes ADD CONSTRAINT quotes_customer_price_money_ck CHECK (((customer_price >= (0)::numeric) AND (customer_price = round(customer_price, 2))));
ALTER TABLE public.quotes ADD CONSTRAINT quotes_option_no_range CHECK (((option_no >= 1) AND (option_no <= 20)));
ALTER TABLE public.quotes ADD CONSTRAINT quotes_price_ex_vat_positive CHECK (((price_ex_vat IS NULL) OR (price_ex_vat > (0)::numeric)));
ALTER TABLE public.quotes ADD CONSTRAINT quotes_quote_amount_check CHECK ((quote_amount > (0)::numeric));
ALTER TABLE public.quotes ADD CONSTRAINT quotes_quote_amount_scale_ck CHECK ((quote_amount = round(quote_amount, 2)));
ALTER TABLE public.quotes ADD CONSTRAINT quotes_supplier_trn_shape CHECK (((supplier_trn IS NULL) OR (supplier_trn ~ '^100[0-9]{12}$'::text)));
ALTER TABLE public.quotes ADD CONSTRAINT quotes_vat_amount_money_ck CHECK (((vat_amount >= (0)::numeric) AND (vat_amount = round(vat_amount, 2))));
ALTER TABLE public.quotes ADD CONSTRAINT quotes_vat_treatment_known CHECK (((vat_treatment IS NULL) OR (vat_treatment = ANY (ARRAY['exclusive'::text, 'inclusive'::text, 'not_registered'::text, 'not_stated'::text, 'confirmed_on_portal'::text]))));
ALTER TABLE public.reasoning_held_question ADD CONSTRAINT reasoning_held_question_plan_check CHECK (((jsonb_typeof(plan) = 'object'::text) AND (length((plan)::text) <= 60000)));
ALTER TABLE public.reasoning_held_question ADD CONSTRAINT reasoning_held_question_question_check CHECK (((btrim(question) <> ''::text) AND (length(question) <= 8000)));
ALTER TABLE public.reasoning_held_question ADD CONSTRAINT reasoning_held_question_reason_check CHECK ((btrim(reason) <> ''::text));
ALTER TABLE public.reasoning_held_question ADD CONSTRAINT reasoning_held_question_request_check CHECK (((jsonb_typeof(request) = 'object'::text) AND (length((request)::text) <= 60000)));
ALTER TABLE public.reasoning_held_question ADD CONSTRAINT reasoning_held_question_status_check CHECK ((status = ANY (ARRAY['held'::text, 'reasoned'::text, 'applied'::text, 'failed'::text, 'expired'::text])));
ALTER TABLE public.reasoning_held_question ADD CONSTRAINT reasoning_held_question_subject_check CHECK (((subject IS NULL) OR (jsonb_typeof(subject) = 'object'::text)));
ALTER TABLE public.reasoning_held_question ADD CONSTRAINT reasoning_held_question_surface_check CHECK ((surface ~ '^[a-z_]+(\.[a-z_]+)*$'::text));
ALTER TABLE public.reasoning_knowledge_candidate ADD CONSTRAINT reasoning_knowledge_candidate_check CHECK (((status = 'pending_review'::text) OR ((reviewed_by IS NOT NULL) AND (reviewed_at IS NOT NULL))));
ALTER TABLE public.reasoning_knowledge_candidate ADD CONSTRAINT reasoning_knowledge_candidate_finding_check CHECK (((btrim(finding) <> ''::text) AND (length(finding) <= 4000)));
ALTER TABLE public.reasoning_knowledge_candidate ADD CONSTRAINT reasoning_knowledge_candidate_question_check CHECK ((btrim(question) <> ''::text));
ALTER TABLE public.reasoning_knowledge_candidate ADD CONSTRAINT reasoning_knowledge_candidate_sources_check CHECK (((jsonb_typeof(sources) = 'array'::text) AND (jsonb_array_length(sources) > 0)));
ALTER TABLE public.reasoning_knowledge_candidate ADD CONSTRAINT reasoning_knowledge_candidate_status_check CHECK ((status = ANY (ARRAY['pending_review'::text, 'approved'::text, 'rejected'::text])));
ALTER TABLE public.refund_case ADD CONSTRAINT refund_case_amount_ck CHECK ((amount_aed > (0)::numeric));
ALTER TABLE public.refund_case ADD CONSTRAINT refund_case_attempts_ck CHECK (((attempts >= 0) AND (attempts <= 5)));
ALTER TABLE public.refund_case ADD CONSTRAINT refund_case_authoriser_ck CHECK (((state <> 'ceo_authorized'::text) OR ((decided_by = 'ceo'::text) AND (decided_at IS NOT NULL) AND (decision_rationale IS NOT NULL))));
ALTER TABLE public.refund_case ADD CONSTRAINT refund_case_decline_ck CHECK (((state <> 'ceo_declined'::text) OR ((decided_at IS NOT NULL) AND (decision_rationale IS NOT NULL))));
ALTER TABLE public.refund_case ADD CONSTRAINT refund_case_destination_basis_ck CHECK (((destination_ref IS NULL) OR (COALESCE(destination_basis, ''::text) <> ''::text)));
ALTER TABLE public.refund_case ADD CONSTRAINT refund_case_execution_ck CHECK (((state <> ALL (ARRAY['submitted'::text, 'provider_pending'::text, 'succeeded'::text, 'reconciled'::text])) OR ((decided_by = 'ceo'::text) AND (decided_at IS NOT NULL))));
ALTER TABLE public.refund_case ADD CONSTRAINT refund_case_state_ck CHECK ((state = ANY (ARRAY['requested'::text, 'investigating'::text, 'eligible'::text, 'ineligible'::text, 'ceo_authorized'::text, 'ceo_declined'::text, 'submitted'::text, 'provider_pending'::text, 'succeeded'::text, 'failed'::text, 'canceled'::text, 'reconciled'::text, 'communicated'::text])));
ALTER TABLE public.refund_ceo_check ADD CONSTRAINT refund_ceo_check_phase_check CHECK ((phase = ANY (ARRAY['approve'::text, 'verify'::text])));
ALTER TABLE public.refund_ceo_review ADD CONSTRAINT refund_ceo_review_outcome_check CHECK ((outcome = ANY (ARRAY['approved'::text, 'rejected'::text, 'declined'::text, 'escalated'::text])));
ALTER TABLE public.refund_incident ADD CONSTRAINT refund_incident_status_check CHECK ((status = ANY (ARRAY['open'::text, 'paused'::text, 'fixed'::text])));
ALTER TABLE public.refund_ladder_evidence ADD CONSTRAINT refund_ladder_evidence_result_check CHECK ((result = ANY (ARRAY['proof_of_response'::text, 'no_response_confirmation'::text])));
ALTER TABLE public.refund_ladder_evidence ADD CONSTRAINT refund_ladder_evidence_step_check CHECK ((step = ANY (ARRAY['chase'::text, 'final_call'::text, 'customer_notice'::text, 'customer_proof'::text, 'unknown'::text])));
ALTER TABLE public.refunds ADD CONSTRAINT refunds_amount_fils_check CHECK (((amount_fils IS NULL) OR (amount_fils > 0)));
ALTER TABLE public.refunds ADD CONSTRAINT refunds_amount_source_check CHECK (((amount_source IS NULL) OR (amount_source = ANY (ARRAY['in_platform_request'::text, 'webhook_event'::text, 'stripe_api'::text, 'manual'::text, 'unknown'::text]))));
ALTER TABLE public.refunds ADD CONSTRAINT refunds_currency_check CHECK ((currency = 'AED'::text));
ALTER TABLE public.refunds ADD CONSTRAINT refunds_reason_code_check CHECK ((reason_code = ANY (ARRAY['supplier_unresponsive'::text, 'supplier_withdrew'::text, 'duplicate_charge'::text, 'customer_cancelled_in_window'::text, 'service_not_delivered'::text, 'fraud_or_dispute'::text, 'goodwill'::text, 'other'::text])));
ALTER TABLE public.refunds ADD CONSTRAINT refunds_settled_needs_amount CHECK (((status <> 'succeeded'::text) OR (amount_fils IS NOT NULL) OR (reconciliation_note IS NOT NULL)));
ALTER TABLE public.refunds ADD CONSTRAINT refunds_status_check CHECK ((status = ANY (ARRAY['requested'::text, 'approved'::text, 'rejected'::text, 'processing'::text, 'succeeded'::text, 'failed'::text, 'cancelled'::text])));
ALTER TABLE public.rehearsal_spend_reservation ADD CONSTRAINT rehearsal_spend_reservation_reserved_usd_check CHECK ((reserved_usd > (0)::numeric));
ALTER TABLE public.rehearsal_window ADD CONSTRAINT rehearsal_window_at_most_two_hours CHECK ((expires_at <= (started_at + '02:01:00'::interval))) NOT VALID;
ALTER TABLE public.rehearsal_window ADD CONSTRAINT rehearsal_window_cap_is_small CHECK (((cap_usd > (0)::numeric) AND (cap_usd <= (15)::numeric))) NOT VALID;
ALTER TABLE public.resilience_step ADD CONSTRAINT resilience_step_budget_ms_check CHECK ((budget_ms > 0));
ALTER TABLE public.resilience_step ADD CONSTRAINT resilience_step_every_check CHECK ((every > '00:00:00'::interval));
ALTER TABLE public.resilience_step ADD CONSTRAINT resilience_step_place_check CHECK ((place = ANY (ARRAY['plan'::text, 'last'::text])));
ALTER TABLE public.resource_pool ADD CONSTRAINT resource_pool_kind_check CHECK ((kind = ANY (ARRAY['budget'::text, 'capacity'::text, 'rate_limit'::text, 'quota'::text, 'headcount'::text, 'storage'::text])));
ALTER TABLE public.review_chain ADD CONSTRAINT review_chain_no_self_approval_ck CHECK (((reviewer_agent IS NULL) OR (author_agent IS NULL) OR (reviewer_agent <> author_agent))) NOT VALID;
ALTER TABLE public.review_pool ADD CONSTRAINT review_pool_note_check CHECK ((btrim(note) <> ''::text));
ALTER TABLE public.review_route ADD CONSTRAINT review_route_decision_type_check CHECK ((decision_type ~ '^[a-z_]+$'::text));
ALTER TABLE public.review_route ADD CONSTRAINT review_route_meaning_check CHECK ((btrim(meaning) <> ''::text));
ALTER TABLE public.review_route ADD CONSTRAINT review_route_owner_seat_check CHECK ((owner_seat <> 'founder'::text));
ALTER TABLE public.reviews ADD CONSTRAINT reviews_photo_paths_max_five CHECK ((COALESCE(cardinality(photo_paths), 0) <= 5));
ALTER TABLE public.reviews ADD CONSTRAINT reviews_r_after_sales_check CHECK (((r_after_sales >= 1) AND (r_after_sales <= 5)));
ALTER TABLE public.reviews ADD CONSTRAINT reviews_r_communication_check CHECK (((r_communication >= 1) AND (r_communication <= 5)));
ALTER TABLE public.reviews ADD CONSTRAINT reviews_r_compliance_check CHECK (((r_compliance >= 1) AND (r_compliance <= 5)));
ALTER TABLE public.reviews ADD CONSTRAINT reviews_r_documentation_check CHECK (((r_documentation >= 1) AND (r_documentation <= 5)));
ALTER TABLE public.reviews ADD CONSTRAINT reviews_r_punctuality_check CHECK (((r_punctuality >= 1) AND (r_punctuality <= 5)));
ALTER TABLE public.reviews ADD CONSTRAINT reviews_r_quality_check CHECK (((r_quality >= 1) AND (r_quality <= 5)));
ALTER TABLE public.reviews ADD CONSTRAINT reviews_rating_check CHECK (((rating >= 1) AND (rating <= 5)));
ALTER TABLE public.reviews ADD CONSTRAINT reviews_rating_range CHECK (((rating >= 1) AND (rating <= 5))) NOT VALID;
ALTER TABLE public.reviews ADD CONSTRAINT reviews_reason_required CHECK (((comment IS NULL) OR (length(btrim(comment)) >= 10)));
ALTER TABLE public.rfq_clarification ADD CONSTRAINT rfq_clarification_held_keeps_its_text_ck CHECK (((english_held_at IS NULL) OR (answer_as_written IS NOT NULL)));
ALTER TABLE public.rfq_clarification ADD CONSTRAINT rfq_clarification_kind_check CHECK ((kind = ANY (ARRAY['question'::text, 'note'::text])));
ALTER TABLE public.rfq_clarification ADD CONSTRAINT rfq_clarification_shape_ck CHECK ((((kind = 'question'::text) AND (supplier_id IS NOT NULL) AND (question IS NOT NULL)) OR ((kind = 'note'::text) AND (supplier_id IS NULL) AND (answered_at IS NOT NULL) AND ((answer IS NOT NULL) OR ((english_held_at IS NOT NULL) AND (answer_as_written IS NOT NULL))))));
ALTER TABLE public.rfq_clarification ADD CONSTRAINT rfq_clarification_source_check CHECK ((source = ANY (ARRAY['portal'::text, 'rfq_flag'::text, 'rfq_note'::text, 'missing_specs'::text])));
ALTER TABLE public.routine_judgement ADD CONSTRAINT routine_judgement_kind_check CHECK ((kind = ANY (ARRAY['quote_spec_match'::text, 'repeat_request'::text, 'supplier_trade_words'::text, 'unknown_sender_mail'::text])));
ALTER TABLE public.routine_judgement ADD CONSTRAINT routine_judgement_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'done'::text, 'failed'::text, 'superseded'::text])));
ALTER TABLE public.routine_judgement ADD CONSTRAINT routine_judgement_subject_key_check CHECK ((btrim(subject_key) <> ''::text));
ALTER TABLE public.sales_engineer_framework_proposal ADD CONSTRAINT sales_engineer_framework_proposal_status_check CHECK ((status = ANY (ARRAY['drafted'::text, 'approved'::text, 'declined'::text, 'sent'::text, 'signed'::text])));
ALTER TABLE public.sales_engineer_negotiation_round ADD CONSTRAINT sales_engineer_negotiation_round_round_check CHECK ((round = ANY (ARRAY['clarify'::text, 'best_and_final'::text])));
ALTER TABLE public.sales_knowledge ADD CONSTRAINT sales_knowledge_authority_ck CHECK ((authority_effect = 'none'::text));
ALTER TABLE public.sales_knowledge_gap ADD CONSTRAINT sales_knowledge_gap_kind_chk CHECK ((kind = ANY (ARRAY['refusal'::text, 'hedge'::text, 'corrected'::text, 'guard_rewrite'::text, 'asked_known'::text])));
ALTER TABLE public.sales_knowledge_gap ADD CONSTRAINT sales_knowledge_gap_status_check CHECK ((status = ANY (ARRAY['open'::text, 'knowledge_added'::text, 'not_a_gap'::text])));
ALTER TABLE public.screening_entry ADD CONSTRAINT screening_entry_entry_type_check CHECK ((entry_type = ANY (ARRAY['individual'::text, 'entity'::text])));
ALTER TABLE public.screening_run ADD CONSTRAINT screening_run_status_check CHECK ((status = ANY (ARRAY['ok'::text, 'failed'::text, 'unparseable'::text])));
ALTER TABLE public.seat_case_memory ADD CONSTRAINT seat_case_memory_seat_check CHECK ((seat = ANY (ARRAY['ceo'::text, 'customer_support'::text, 'sales_engineer'::text, 'accountant'::text, 'it_engineer'::text, 'marketing'::text])));
ALTER TABLE public.seat_deliberation ADD CONSTRAINT seat_deliberation_check CHECK ((author_seat <> reviewer_seat));
ALTER TABLE public.seat_deliberation ADD CONSTRAINT seat_deliberation_check1 CHECK ((round <= max_rounds));
ALTER TABLE public.seat_deliberation ADD CONSTRAINT seat_deliberation_evidence_check CHECK (((jsonb_typeof(evidence) = 'object'::text) AND (length((evidence)::text) <= 60000)));
ALTER TABLE public.seat_deliberation ADD CONSTRAINT seat_deliberation_kind_check CHECK ((kind ~ '^[a-z_]+(\.[a-z_]+)*$'::text));
ALTER TABLE public.seat_deliberation ADD CONSTRAINT seat_deliberation_max_rounds_check CHECK (((max_rounds >= 1) AND (max_rounds <= 5)));
ALTER TABLE public.seat_deliberation ADD CONSTRAINT seat_deliberation_proposal_check CHECK (((jsonb_typeof(proposal) = 'object'::text) AND (proposal <> '{}'::jsonb) AND (length((proposal)::text) <= 30000)));
ALTER TABLE public.seat_deliberation ADD CONSTRAINT seat_deliberation_question_check CHECK ((btrim(question) <> ''::text));
ALTER TABLE public.seat_deliberation ADD CONSTRAINT seat_deliberation_round_check CHECK ((round >= 1));
ALTER TABLE public.seat_deliberation ADD CONSTRAINT seat_deliberation_status_check CHECK ((status = ANY (ARRAY['open'::text, 'reviewed'::text, 'no_independent_reviewer'::text, 'closed'::text])));
ALTER TABLE public.seat_deliberation_ceiling ADD CONSTRAINT seat_deliberation_ceiling_cap_aed_month_check CHECK ((cap_aed_month >= (0)::numeric));
ALTER TABLE public.seat_deliberation_ceiling ADD CONSTRAINT seat_deliberation_ceiling_note_check CHECK ((btrim(note) <> ''::text));
ALTER TABLE public.seat_deliberation_turn ADD CONSTRAINT seat_deliberation_turn_phase_check CHECK ((phase = ANY (ARRAY['proposal'::text, 'blind'::text, 'compare'::text])));
ALTER TABLE public.seat_deliberation_turn ADD CONSTRAINT seat_deliberation_turn_round_check CHECK ((round >= 1));
ALTER TABLE public.seat_deliberation_turn ADD CONSTRAINT seat_deliberation_turn_status_check CHECK ((status = ANY (ARRAY['recorded'::text, 'held_not_run'::text, 'no_independent_reviewer'::text, 'failed'::text])));
ALTER TABLE public.seat_deliberation_turn ADD CONSTRAINT seat_deliberation_turn_verdict_check CHECK ((verdict = ANY (ARRAY['approve'::text, 'reject'::text, 'revise'::text])));
ALTER TABLE public.seat_duty ADD CONSTRAINT seat_duty_check CHECK ((split_part(duty, '.'::text, 1) = owner_seat));
ALTER TABLE public.seat_duty ADD CONSTRAINT seat_duty_duty_check CHECK ((duty ~ '^[a-z_]+\.[a-z_]+$'::text));
ALTER TABLE public.seat_duty ADD CONSTRAINT seat_duty_every_check CHECK ((every >= '00:05:00'::interval));
ALTER TABLE public.seat_duty ADD CONSTRAINT seat_duty_owner_file_check CHECK ((owner_file ~ '^scripts/sql/[a-z0-9_]+\.sql$'::text));
ALTER TABLE public.seat_duty ADD CONSTRAINT seat_duty_routine_check CHECK ((routine ~ '^fn_[a-z0-9_]+$'::text));
ALTER TABLE public.seat_duty ADD CONSTRAINT seat_duty_what_check CHECK ((btrim(what) <> ''::text));
ALTER TABLE public.seat_exam_asked ADD CONSTRAINT seat_exam_asked_graded_by_check CHECK ((graded_by = ANY (ARRAY['code'::text, 'claude'::text])));
ALTER TABLE public.seat_exam_fix ADD CONSTRAINT seat_exam_fix_check CHECK (((status = 'closed'::text) = ((closed_at IS NOT NULL) AND (closed_by_asked_id IS NOT NULL) AND (fix_ref IS NOT NULL))));
ALTER TABLE public.seat_exam_fix ADD CONSTRAINT seat_exam_fix_kind_check CHECK ((kind = ANY (ARRAY['knowledge_ingest'::text, 'prompt'::text])));
ALTER TABLE public.seat_exam_fix ADD CONSTRAINT seat_exam_fix_status_check CHECK ((status = ANY (ARRAY['open'::text, 'closed'::text])));
ALTER TABLE public.seat_exam_item ADD CONSTRAINT seat_exam_item_expected_entry_ids_check CHECK ((cardinality(expected_entry_ids) > 0));
ALTER TABLE public.seat_exam_item ADD CONSTRAINT seat_exam_item_expected_facts_check CHECK ((cardinality(expected_facts) > 0));
ALTER TABLE public.seat_handoff_kind ADD CONSTRAINT seat_handoff_kind_handler_check CHECK ((handler ~ '^fn_[a-z0-9_]+$'::text));
ALTER TABLE public.seat_handoff_kind ADD CONSTRAINT seat_handoff_kind_meaning_check CHECK ((btrim(meaning) <> ''::text));
ALTER TABLE public.seat_handoff_kind ADD CONSTRAINT seat_handoff_kind_owner_file_check CHECK ((owner_file ~ '^scripts/sql/[a-z0-9_]+\.sql$'::text));
ALTER TABLE public.seat_handoff_kind ADD CONSTRAINT seat_handoff_kind_reply_within_check CHECK ((reply_within > '00:00:00'::interval));
ALTER TABLE public.seat_handoff_kind ADD CONSTRAINT seat_handoff_kind_type_check CHECK ((type ~ '^[a-z]+(\.[a-z_]+)+$'::text));
ALTER TABLE public.seat_judgement ADD CONSTRAINT seat_judgement_seat_check CHECK ((seat = ANY (ARRAY['ceo'::text, 'customer_support'::text, 'sales_engineer'::text, 'accountant'::text, 'it_engineer'::text, 'marketing'::text])));
ALTER TABLE public.seat_judgement ADD CONSTRAINT seat_judgement_status_check CHECK ((status = ANY (ARRAY['recalled'::text, 'answered'::text, 'held'::text])));
ALTER TABLE public.seat_judgement ADD CONSTRAINT seat_judgement_surface_check CHECK ((btrim(surface) <> ''::text));
ALTER TABLE public.seat_knowledge_eval_question ADD CONSTRAINT seat_knowledge_eval_question_expected_check CHECK ((cardinality(expected) > 0));
ALTER TABLE public.seat_knowledge_eval_question ADD CONSTRAINT seat_knowledge_eval_question_lang_check CHECK ((lang = ANY (ARRAY['en'::text, 'ar'::text])));
ALTER TABLE public.seat_knowledge_eval_question ADD CONSTRAINT seat_knowledge_eval_question_question_check CHECK ((btrim(question) <> ''::text));
ALTER TABLE public.seat_knowledge_exam ADD CONSTRAINT seat_knowledge_exam_question_check CHECK ((btrim(question) <> ''::text));
ALTER TABLE public.seat_knowledge_exam ADD CONSTRAINT seat_knowledge_exam_verdict_check CHECK ((verdict = ANY (ARRAY['correct'::text, 'partial'::text, 'wrong'::text, 'not_covered'::text])));
ALTER TABLE public.seat_knowledge_recall_floor ADD CONSTRAINT seat_knowledge_recall_floor_floor_check CHECK (((floor >= (0)::numeric) AND (floor <= (1)::numeric)));
ALTER TABLE public.seat_knowledge_recall_floor ADD CONSTRAINT seat_knowledge_recall_floor_lang_check CHECK ((lang = ANY (ARRAY['en'::text, 'ar'::text])));
ALTER TABLE public.seat_knowledge_refresh ADD CONSTRAINT seat_knowledge_refresh_quarter_check CHECK ((quarter = (date_trunc('quarter'::text, (quarter)::timestamp with time zone))::date));
ALTER TABLE public.seat_knowledge_stale ADD CONSTRAINT seat_knowledge_stale_quarter_check CHECK ((quarter = (date_trunc('quarter'::text, (quarter)::timestamp with time zone))::date));
ALTER TABLE public.seat_knowledge_stale ADD CONSTRAINT seat_knowledge_stale_reasons_check CHECK (((cardinality(reasons) > 0) AND (reasons <@ ARRAY['no_source'::text, 'review_overdue'::text, 'source_old'::text])));
ALTER TABLE public.seat_lesson_cluster ADD CONSTRAINT seat_lesson_cluster_case_ids_check CHECK ((cardinality(case_ids) >= 3));
ALTER TABLE public.seat_playbook ADD CONSTRAINT seat_playbook_seat_check CHECK ((seat = ANY (ARRAY['ceo'::text, 'customer_support'::text, 'sales_engineer'::text, 'accountant'::text, 'it_engineer'::text, 'marketing'::text])));
ALTER TABLE public.seat_self_review ADD CONSTRAINT seat_self_review_trend_check CHECK ((trend = ANY (ARRAY['first'::text, 'up'::text, 'flat'::text, 'down'::text, 'no_exam'::text])));
ALTER TABLE public.seat_senior_exam ADD CONSTRAINT seat_senior_exam_check CHECK (((passed >= 0) AND (passed <= items)));
ALTER TABLE public.seat_senior_exam ADD CONSTRAINT seat_senior_exam_items_check CHECK ((items > 0));
ALTER TABLE public.seat_senior_verdict ADD CONSTRAINT seat_senior_verdict_level_check CHECK ((level = ANY (ARRAY['junior'::text, 'mid'::text, 'senior'::text])));
ALTER TABLE public.security_gap ADD CONSTRAINT security_gap_status_check CHECK ((status = ANY (ARRAY['open'::text, 'closed'::text, 'partial'::text])));
ALTER TABLE public.service_implication ADD CONSTRAINT service_implication_from_code_check CHECK ((from_code ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)?$'::text));
ALTER TABLE public.service_implication ADD CONSTRAINT service_implication_not_itself CHECK ((from_code <> ((implies_trade || '.'::text) || implies_code)));
ALTER TABLE public.service_implication ADD CONSTRAINT service_implication_reason_ar_check CHECK ((reason_ar ~ '[ء-ي]'::text));
ALTER TABLE public.service_implication ADD CONSTRAINT service_implication_reason_en_check CHECK ((btrim(reason_en) <> ''::text));
ALTER TABLE public.signup_purge ADD CONSTRAINT signup_purge_kind_check CHECK ((kind = ANY (ARRAY['customer'::text, 'supplier_self_registered'::text, 'supplier_invited_lead'::text, 'demo_purge'::text])));
ALTER TABLE public.skills_matrix ADD CONSTRAINT skills_matrix_rating_check CHECK (((rating >= 1) AND (rating <= 5)));
ALTER TABLE public.social_connect_link ADD CONSTRAINT social_connect_link_order CHECK (((completed_at IS NULL) OR (started_at IS NOT NULL)));
ALTER TABLE public.social_connect_link ADD CONSTRAINT social_connect_link_platform_check CHECK ((platform = ANY (ARRAY['youtube'::text, 'linkedin'::text])));
ALTER TABLE public.social_connect_link ADD CONSTRAINT social_connect_link_state_hash_check CHECK (((state_hash IS NULL) OR (state_hash ~ '^[0-9a-f]{64}$'::text)));
ALTER TABLE public.social_connect_link ADD CONSTRAINT social_connect_link_token_hash_check CHECK ((token_hash ~ '^[0-9a-f]{64}$'::text));
ALTER TABLE public.social_conversation ADD CONSTRAINT social_conversation_platform_check CHECK ((platform = ANY (ARRAY['instagram'::text, 'facebook'::text, 'youtube'::text, 'linkedin'::text, 'tiktok'::text])));
ALTER TABLE public.social_conversation ADD CONSTRAINT social_conversation_status_check CHECK ((status = ANY (ARRAY['auto'::text, 'handed_to_human'::text])));
ALTER TABLE public.social_message ADD CONSTRAINT social_message_author_check CHECK ((author = ANY (ARRAY['person'::text, 'seat'::text, 'human'::text])));
ALTER TABLE public.social_message ADD CONSTRAINT social_message_channel_check CHECK ((channel = ANY (ARRAY['dm'::text, 'comment'::text])));
ALTER TABLE public.social_message ADD CONSTRAINT social_message_classification_check CHECK ((classification = ANY (ARRAY['question'::text, 'praise'::text, 'complaint'::text, 'spam_abuse'::text, 'sales_lead'::text, 'supplier_enquiry'::text, 'sensitive_legal'::text, 'off_topic'::text])));
ALTER TABLE public.social_message ADD CONSTRAINT social_message_decided_by_check CHECK ((decided_by = ANY (ARRAY['rule'::text, 'model'::text, 'guard_fallback'::text])));
ALTER TABLE public.social_message ADD CONSTRAINT social_message_direction_check CHECK ((direction = ANY (ARRAY['in'::text, 'out'::text])));
ALTER TABLE public.social_message ADD CONSTRAINT social_message_platform_check CHECK ((platform = ANY (ARRAY['instagram'::text, 'facebook'::text, 'youtube'::text, 'linkedin'::text, 'tiktok'::text])));
ALTER TABLE public.social_message ADD CONSTRAINT social_message_reply_kind_check CHECK ((reply_kind = ANY (ARRAY['handoff'::text, 'standard'::text, 'faq'::text, 'knowledge'::text, 'unknown'::text, 'model'::text, 'escalated'::text])));
ALTER TABLE public.social_message ADD CONSTRAINT social_message_send_status_check CHECK ((send_status = ANY (ARRAY['pending'::text, 'held_switch_off'::text, 'held_fixture'::text, 'sent'::text, 'failed'::text, 'held_model'::text, 'rate_limited'::text, 'not_sent'::text, 'hidden'::text])));
ALTER TABLE public.social_posts ADD CONSTRAINT social_posts_clickable CHECK ((((image_url IS NOT NULL) OR (media_missing IS NOT NULL)) AND ((NOT ((mode = 'now'::text) AND (status = ANY (ARRAY['sent'::text, 'published'::text])))) OR ((permalinks IS NOT NULL) AND (permalinks <> '{}'::jsonb)) OR (permalink_missing IS NOT NULL))));
ALTER TABLE public.spec_alternative_offer ADD CONSTRAINT spec_alternative_offer_alternatives_shape CHECK (((jsonb_typeof(alternatives) = 'array'::text) AND (jsonb_array_length(alternatives) >= 1) AND (NOT jsonb_path_exists(alternatives, '$[*]?(@.type() != "object")'::jsonpath)) AND (NOT jsonb_path_exists(alternatives, '$[*].keyvalue()?((@."key" != "option_id" && @."key" != "value") && @."key" != "suppliers")'::jsonpath)) AND (NOT jsonb_path_exists(alternatives, '$[*]."suppliers"?(@.type() != "number")'::jsonpath))));
ALTER TABLE public.spec_alternative_offer ADD CONSTRAINT spec_alternative_offer_channel_check CHECK (((answer_channel IS NULL) OR (answer_channel = ANY (ARRAY['portal'::text, 'whatsapp'::text, 'email'::text]))));
ALTER TABLE public.spec_alternative_offer ADD CONSTRAINT spec_alternative_offer_reason_check CHECK (((closed_reason IS NULL) OR (closed_reason = ANY (ARRAY['no_exact_spec_declined'::text, 'no_exact_spec_no_reply'::text]))));
ALTER TABLE public.spec_alternative_offer ADD CONSTRAINT spec_alternative_offer_seats_check CHECK (((owner_seat = 'sales_engineer'::text) AND (messenger_seat = 'customer_support'::text)));
ALTER TABLE public.spec_alternative_offer ADD CONSTRAINT spec_alternative_offer_state_check CHECK ((state = ANY (ARRAY['open'::text, 'accepted'::text, 'declined'::text, 'no_reply'::text, 'superseded'::text])));
ALTER TABLE public.stalled_inquiry_rescue ADD CONSTRAINT stalled_inquiry_rescue_pool_check CHECK (((uninvited_pool IS NULL) OR (uninvited_pool >= 0)));
ALTER TABLE public.stalled_inquiry_rescue ADD CONSTRAINT stalled_inquiry_rescue_reason_check CHECK ((reason = ANY (ARRAY['no_reachable_supplier'::text, 'no_quote_48h'::text])));
ALTER TABLE public.strategy_risks ADD CONSTRAINT strategy_risks_impact_check CHECK (((impact >= 1) AND (impact <= 5)));
ALTER TABLE public.strategy_risks ADD CONSTRAINT strategy_risks_likelihood_check CHECK (((likelihood >= 1) AND (likelihood <= 5)));
ALTER TABLE public.strategy_risks ADD CONSTRAINT strategy_risks_status_check CHECK ((status = ANY (ARRAY['open'::text, 'mitigating'::text, 'accepted'::text, 'closed'::text])));
ALTER TABLE public.stripe_payout ADD CONSTRAINT stripe_payout_amount_fils_money_ck CHECK ((amount_fils >= 0));
ALTER TABLE public.stripe_setting_reading ADD CONSTRAINT stripe_setting_reading_value_check CHECK ((value = ANY (ARRAY['on'::text, 'off'::text])));
ALTER TABLE public.supplier_availability ADD CONSTRAINT supplier_availability_busy_names_its_date CHECK (((state = 'busy'::text) = (busy_until IS NOT NULL)));
ALTER TABLE public.supplier_availability ADD CONSTRAINT supplier_availability_state_check CHECK ((state = ANY (ARRAY['available'::text, 'busy'::text, 'paused'::text])));
ALTER TABLE public.supplier_beneficial_owner ADD CONSTRAINT supplier_beneficial_owner_full_name_check CHECK ((btrim(full_name) <> ''::text));
ALTER TABLE public.supplier_beneficial_owner ADD CONSTRAINT supplier_beneficial_owner_share_pct_check CHECK (((share_pct IS NULL) OR ((share_pct > (0)::numeric) AND (share_pct <= (100)::numeric))));
ALTER TABLE public.supplier_beneficial_owner ADD CONSTRAINT supplier_beneficial_owner_source_check CHECK ((source = ANY (ARRAY['trade_licence'::text, 'supplier_declared'::text, 'registry'::text])));
ALTER TABLE public.supplier_capability_reading ADD CONSTRAINT supplier_capability_reading_check CHECK (((status = 'needs_reasoning'::text) OR ((manufacturing IS NOT NULL) AND (installation IS NOT NULL) AND (maintenance IS NOT NULL) AND (design IS NOT NULL))));
ALTER TABLE public.supplier_capability_reading ADD CONSTRAINT supplier_capability_reading_status_check CHECK ((status = ANY (ARRAY['reasoned'::text, 'needs_reasoning'::text])));
ALTER TABLE public.supplier_capability_reading ADD CONSTRAINT supplier_capability_reading_summary_md5_check CHECK ((summary_md5 ~ '^[0-9a-f]{32}$'::text));
ALTER TABLE public.supplier_collaboration ADD CONSTRAINT supplier_collaboration_consecutive_ignored_check CHECK ((consecutive_ignored >= 0));
ALTER TABLE public.supplier_collaboration ADD CONSTRAINT supplier_collaboration_owner_seat_check CHECK ((owner_seat = 'sales_engineer'::text));
ALTER TABLE public.supplier_collaboration ADD CONSTRAINT supplier_collaboration_total_ignored_check CHECK ((total_ignored >= 0));
ALTER TABLE public.supplier_collaboration_event ADD CONSTRAINT supplier_collaboration_event_actor_check CHECK ((actor = ANY (ARRAY['sales_engineer'::text, 'founder'::text])));
ALTER TABLE public.supplier_collaboration_event ADD CONSTRAINT supplier_collaboration_event_kind_check CHECK ((kind = ANY (ARRAY['ignored_hold'::text, 'cooperated'::text, 'warning_sent'::text, 'matching_hold'::text, 'hold_lifted'::text])));
ALTER TABLE public.supplier_document_cache ADD CONSTRAINT supplier_document_cache_kind_check CHECK ((kind = ANY (ARRAY['inquiry'::text, 'quotation'::text])));
ALTER TABLE public.supplier_document_cache ADD CONSTRAINT supplier_document_cache_lang_check CHECK ((lang = ANY (ARRAY['en'::text, 'ar'::text])));
ALTER TABLE public.supplier_due_checkouts ADD CONSTRAINT supplier_due_checkouts_amount_aed_check CHECK ((amount_aed > (0)::numeric));
ALTER TABLE public.supplier_due_checkouts ADD CONSTRAINT supplier_due_checkouts_session_id_check CHECK ((btrim(session_id) <> ''::text));
ALTER TABLE public.supplier_due_payments ADD CONSTRAINT supplier_due_payments_amount_aed_check CHECK ((amount_aed > (0)::numeric));
ALTER TABLE public.supplier_due_payments ADD CONSTRAINT supplier_due_payments_entered_by_check CHECK ((entered_by = ANY (ARRAY['accountant'::text, 'service'::text])));
ALTER TABLE public.supplier_due_payments ADD CONSTRAINT supplier_due_payments_reference_check CHECK ((btrim(reference) <> ''::text));
ALTER TABLE public.supplier_lead_intake ADD CONSTRAINT supplier_lead_intake_intent_check CHECK ((intent = ANY (ARRAY['register'::text, 'question'::text, 'document'::text, 'decline'::text, 'bounce'::text, 'other'::text])));
ALTER TABLE public.supplier_onboarding ADD CONSTRAINT supplier_onboarding_stage_check CHECK ((stage = ANY (ARRAY['invited'::text, 'clicked'::text, 'registering'::text, 'action_required'::text, 'approved'::text, 'matched'::text, 'quoting'::text, 'closed'::text])));
ALTER TABLE public.supplier_own_word_reading ADD CONSTRAINT supplier_own_word_reading_check CHECK (((status = 'reasoned'::text) OR (service_key IS NULL)));
ALTER TABLE public.supplier_own_word_reading ADD CONSTRAINT supplier_own_word_reading_status_check CHECK ((status = ANY (ARRAY['reasoned'::text, 'needs_reasoning'::text])));
ALTER TABLE public.supplier_own_word_reading ADD CONSTRAINT supplier_own_word_reading_word_check CHECK (((btrim(word) <> ''::text) AND (length(word) <= 200)));
ALTER TABLE public.supplier_performance ADD CONSTRAINT supplier_performance_score_check CHECK (((score IS NULL) OR ((score >= (0)::numeric) AND (score <= (1)::numeric))));
ALTER TABLE public.supplier_quote_template ADD CONSTRAINT supplier_quote_template_line_headings_check CHECK ((cardinality(line_headings) <= 100));
ALTER TABLE public.supplier_quote_template ADD CONSTRAINT supplier_quote_template_name_check CHECK (((char_length(name) >= 2) AND (char_length(name) <= 80)));
ALTER TABLE public.supplier_quote_template ADD CONSTRAINT supplier_quote_template_never_a_price CHECK ((NOT fn_text_states_a_price(concat_ws(' | '::text, name, array_to_string(line_headings, ' | '::text), terms, warranty, validity, inclusions, exclusions, payment_terms))));
ALTER TABLE public.supplier_reply_followup ADD CONSTRAINT supplier_reply_followup_intent_check CHECK ((intent = ANY (ARRAY['subsidiary'::text, 'later'::text, 'interested'::text])));
ALTER TABLE public.supplier_reply_followup ADD CONSTRAINT supplier_reply_followup_state_check CHECK ((state = ANY (ARRAY['due'::text, 'sent'::text, 'dropped'::text])));
ALTER TABLE public.supplier_scorecard ADD CONSTRAINT supplier_scorecard_month_check CHECK ((month = (date_trunc('month'::text, (month)::timestamp with time zone))::date));
ALTER TABLE public.supplier_screening_hit ADD CONSTRAINT supplier_screening_hit_match_kind_check CHECK ((match_kind = ANY (ARRAY['exact'::text, 'token_overlap'::text])));
ALTER TABLE public.supplier_screening_hit ADD CONSTRAINT supplier_screening_hit_status_check CHECK ((status = ANY (ARRAY['open'::text, 'confirmed'::text, 'false_positive'::text])));
ALTER TABLE public.supplier_voice_note ADD CONSTRAINT supplier_voice_note_bytes_check CHECK ((bytes >= 0));
ALTER TABLE public.supplier_voice_note ADD CONSTRAINT supplier_voice_note_chars_check CHECK (((chars IS NULL) OR (chars >= 0)));
ALTER TABLE public.supplier_voice_note ADD CONSTRAINT supplier_voice_note_duration_ms_check CHECK (((duration_ms IS NULL) OR (duration_ms >= 0)));
ALTER TABLE public.supplier_voice_note ADD CONSTRAINT supplier_voice_note_lang_check CHECK (((lang IS NULL) OR (lang = ANY (ARRAY['en'::text, 'ar'::text]))));
ALTER TABLE public.supplier_voice_note ADD CONSTRAINT supplier_voice_note_outcome_check CHECK ((outcome = ANY (ARRAY['pending'::text, 'flag_off'::text, 'rate_limited'::text, 'refused'::text, 'transcribed'::text, 'empty'::text, 'failed'::text])));
ALTER TABLE public.supplier_whatsapp_consent_ask ADD CONSTRAINT supplier_whatsapp_consent_ask_phone_check CHECK ((phone ~ '^\+[0-9]{8,15}$'::text));
ALTER TABLE public.supplier_whatsapp_optin ADD CONSTRAINT supplier_whatsapp_optin_evidence_check CHECK ((btrim(evidence) <> ''::text));
ALTER TABLE public.supplier_whatsapp_optin ADD CONSTRAINT supplier_whatsapp_optin_phone_check CHECK ((phone ~ '^\+[0-9]{8,15}$'::text));
ALTER TABLE public.supplier_whatsapp_optin ADD CONSTRAINT supplier_whatsapp_optin_source_check CHECK ((source = ANY (ARRAY['wa_button'::text, 'wa_consent_reply'::text, 'email_consent_reply'::text, 'call_consent_reply'::text])));
ALTER TABLE public.supply_gap ADD CONSTRAINT supply_gap_status_check CHECK ((status = ANY (ARRAY['open'::text, 'deciding'::text, 'recruit'::text, 'deferred'::text, 'closed'::text])));
ALTER TABLE public.supply_recruitment_brief ADD CONSTRAINT supply_recruitment_brief_priority_check CHECK ((priority = ANY (ARRAY['P1'::text, 'P2'::text, 'P3'::text])));
ALTER TABLE public.supply_recruitment_brief ADD CONSTRAINT supply_recruitment_brief_status_check CHECK ((status = ANY (ARRAY['open'::text, 'closed'::text])));
ALTER TABLE public.support_artifact ADD CONSTRAINT support_artifact_approved_ck CHECK (((privacy_state <> 'approved'::text) OR ((approved_at IS NOT NULL) AND (privacy_result IS NOT NULL) AND (checksum IS NOT NULL))));
ALTER TABLE public.support_artifact ADD CONSTRAINT support_artifact_kind_ck CHECK ((artifact_kind = ANY (ARRAY['comparison_report'::text, 'reveal_invoice'::text])));
ALTER TABLE public.support_artifact ADD CONSTRAINT support_artifact_privacy_ck CHECK ((privacy_state = ANY (ARRAY['unchecked'::text, 'approved'::text, 'refused'::text])));
ALTER TABLE public.support_case ADD CONSTRAINT support_case_channel_ck CHECK (((channel IS NULL) OR (channel = ANY (ARRAY['whatsapp'::text, 'email'::text, 'widget'::text, 'portal'::text, 'phone'::text, 'internal'::text, 'social'::text]))));
ALTER TABLE public.support_case ADD CONSTRAINT support_case_close_ck CHECK (((state <> 'closed'::text) OR ((closed_at IS NOT NULL) AND (close_reason IS NOT NULL))));
ALTER TABLE public.support_case ADD CONSTRAINT support_case_kind_ck CHECK ((case_kind = ANY (ARRAY['support'::text, 'service_recovery'::text])));
ALTER TABLE public.support_case ADD CONSTRAINT support_case_party_ck CHECK ((party_kind = ANY (ARRAY['customer'::text, 'supplier'::text, 'unknown'::text])));
ALTER TABLE public.support_case ADD CONSTRAINT support_case_state_ck CHECK ((state = ANY (ARRAY['open'::text, 'waiting_customer'::text, 'waiting_service'::text, 'blocked'::text, 'closed'::text])));
ALTER TABLE public.support_case ADD CONSTRAINT support_case_verified_ck CHECK (((NOT identity_verified) OR (verified_how IS NOT NULL)));
ALTER TABLE public.support_category ADD CONSTRAINT support_category_category_check CHECK ((category ~ '^[a-z_]+$'::text));
ALTER TABLE public.support_category ADD CONSTRAINT support_category_meaning_check CHECK ((btrim(meaning) <> ''::text));
ALTER TABLE public.support_category ADD CONSTRAINT support_category_owner_seat_check CHECK ((owner_seat = ANY (ARRAY['customer_support'::text, 'sales_engineer'::text, 'accountant'::text, 'it_engineer'::text, 'marketing'::text, 'ceo'::text])));
ALTER TABLE public.support_cause_week ADD CONSTRAINT support_cause_week_cases_check CHECK ((cases >= 0));
ALTER TABLE public.support_ceo_report ADD CONSTRAINT support_ceo_report_attempts_ck CHECK ((jsonb_typeof(attempted_actions) = 'array'::text));
ALTER TABLE public.support_ceo_report ADD CONSTRAINT support_ceo_report_complete_ck CHECK (((status <> 'completed'::text) OR (completed_at IS NOT NULL)));
ALTER TABLE public.support_ceo_report ADD CONSTRAINT support_ceo_report_evidence_ck CHECK (((jsonb_typeof(verified_evidence) = 'object'::text) AND (verified_evidence <> '{}'::jsonb)));
ALTER TABLE public.support_ceo_report ADD CONSTRAINT support_ceo_report_receipt_ck CHECK (((status <> 'accepted'::text) OR (acceptance_receipt IS NOT NULL)));
ALTER TABLE public.support_ceo_report ADD CONSTRAINT support_ceo_report_severity_ck CHECK ((severity = ANY (ARRAY['routine'::text, 'elevated'::text, 'serious'::text, 'critical'::text])));
ALTER TABLE public.support_ceo_report ADD CONSTRAINT support_ceo_report_status_ck CHECK ((status = ANY (ARRAY['sent'::text, 'accepted'::text, 'completed'::text, 'failed'::text, 'blocked'::text])));
ALTER TABLE public.support_customer_profile ADD CONSTRAINT support_customer_profile_email_check CHECK (((email IS NULL) OR (email = lower(btrim(email)))));
ALTER TABLE public.support_customer_profile ADD CONSTRAINT support_customer_profile_party_kind_check CHECK ((party_kind = ANY (ARRAY['customer'::text, 'supplier'::text, 'unknown'::text])));
ALTER TABLE public.support_customer_profile ADD CONSTRAINT support_customer_profile_phone_tail_check CHECK (((phone_tail IS NULL) OR (phone_tail ~ '^[0-9]{9}$'::text)));
ALTER TABLE public.support_document_intake ADD CONSTRAINT support_document_intake_attached_ck CHECK (((NOT attached) OR ((lead_id IS NOT NULL) AND (classified_as <> 'unknown'::text))));
ALTER TABLE public.support_document_intake ADD CONSTRAINT support_document_intake_by_ck CHECK ((classified_by = ANY (ARRAY['caption'::text, 'filename'::text, 'declared'::text, 'model'::text, 'human'::text])));
ALTER TABLE public.support_document_intake ADD CONSTRAINT support_document_intake_channel_ck CHECK ((channel = ANY (ARRAY['email'::text, 'portal'::text])));
ALTER TABLE public.support_document_intake ADD CONSTRAINT support_document_intake_class_ck CHECK ((classified_as = ANY (ARRAY['licence'::text, 'profile'::text, 'signed_terms'::text, 'unknown'::text])));
ALTER TABLE public.support_document_intake ADD CONSTRAINT support_document_intake_conf_ck CHECK ((confidence = ANY (ARRAY['high'::text, 'low'::text])));
ALTER TABLE public.support_identity_challenge ADD CONSTRAINT support_identity_challenge_attempts_ck CHECK (((attempts >= 0) AND (attempts <= 5)));
ALTER TABLE public.support_identity_challenge ADD CONSTRAINT support_identity_challenge_hash_ck CHECK ((code_hash ~ '^[0-9a-f]{64}$'::text));
ALTER TABLE public.support_identity_challenge ADD CONSTRAINT support_identity_challenge_outcome_ck CHECK (((outcome IS NULL) OR (outcome = ANY (ARRAY['verified'::text, 'expired'::text, 'exhausted'::text, 'abandoned'::text]))));
ALTER TABLE public.support_knowledge ADD CONSTRAINT support_knowledge_authority_ck CHECK ((authority_effect = 'none'::text));
ALTER TABLE public.support_knowledge ADD CONSTRAINT support_knowledge_version_ck CHECK (((pack_version = '1.2.0'::text) OR (pack_id ~~ 'verified:%'::text)));
ALTER TABLE public.support_notification ADD CONSTRAINT support_notification_attachment_ck CHECK (((body !~~* '%is attached%'::text) OR (attachment_ref IS NOT NULL)));
ALTER TABLE public.support_notification ADD CONSTRAINT support_notification_channel_ck CHECK ((channel = ANY (ARRAY['whatsapp'::text, 'email'::text])));
ALTER TABLE public.support_notification ADD CONSTRAINT support_notification_scanned_ck CHECK (((anonymity_checked_at IS NOT NULL) AND (anonymity_result IS NOT NULL) AND ((anonymity_result ->> 'safe'::text) = 'true'::text)));
ALTER TABLE public.support_notification ADD CONSTRAINT support_notification_state_ck CHECK ((state = ANY (ARRAY['queued'::text, 'sending'::text, 'sent'::text, 'delivered'::text, 'read'::text, 'failed'::text, 'suppressed'::text, 'unknown'::text])));
ALTER TABLE public.support_reply_readability ADD CONSTRAINT support_reply_readability_channel_check CHECK ((channel = ANY (ARRAY['widget'::text, 'whatsapp'::text, 'email'::text, 'portal'::text])));
ALTER TABLE public.support_reply_readability ADD CONSTRAINT support_reply_readability_lang_check CHECK ((lang = ANY (ARRAY['en'::text, 'ar'::text])));
ALTER TABLE public.support_reply_readability ADD CONSTRAINT support_reply_readability_path_check CHECK ((path = ANY (ARRAY['reasoned'::text, 'fallback'::text])));
ALTER TABLE public.support_reply_readability ADD CONSTRAINT support_reply_readability_score_check CHECK (((score >= 0) AND (score <= 100)));
ALTER TABLE public.support_reply_readability ADD CONSTRAINT support_reply_readability_tone_check CHECK (((tone >= 0) AND (tone <= 100)));
ALTER TABLE public.support_root_cause ADD CONSTRAINT support_root_cause_baseline_per_week_check CHECK ((baseline_per_week > (0)::numeric));
ALTER TABLE public.support_root_cause ADD CONSTRAINT support_root_cause_status_check CHECK ((status = ANY (ARRAY['open'::text, 'handed_off'::text, 'measuring'::text, 'fell'::text, 'not_fallen'::text])));
ALTER TABLE public.support_root_cause_fix ADD CONSTRAINT support_root_cause_fix_fix_kind_check CHECK ((fix_kind = ANY (ARRAY['faq'::text, 'knowledge_entry'::text, 'wording'::text])));
ALTER TABLE public.support_signal_category ADD CONSTRAINT support_signal_category_source_check CHECK ((source = ANY (ARRAY['wa_choice'::text, 'email_category'::text, 'case_kind'::text, 'faq_section'::text])));
ALTER TABLE public.table_export_change_tracked ADD CONSTRAINT table_export_change_tracked_pk_column_check CHECK ((pk_column ~ '^[a-z_][a-z0-9_]*$'::text));
ALTER TABLE public.table_export_change_tracked ADD CONSTRAINT table_export_change_tracked_table_name_check CHECK ((table_name ~ '^[a-z_][a-z0-9_]*$'::text));
ALTER TABLE public.table_export_registry ADD CONSTRAINT table_export_registry_category_check CHECK ((btrim(category) <> ''::text));
ALTER TABLE public.table_export_registry ADD CONSTRAINT table_export_registry_exclusion_has_a_known_reason CHECK ((exported OR (category = ANY (ARRAY['secret'::text, 'cache'::text, 'log'::text, 'measurement'::text, 'fixture'::text, 'no_writer'::text]))));
ALTER TABLE public.table_export_registry ADD CONSTRAINT table_export_registry_reason_check CHECK ((length(btrim(reason)) >= 10));
ALTER TABLE public.table_export_registry ADD CONSTRAINT table_export_registry_table_name_check CHECK ((table_name ~ '^[a-z0-9_]+$'::text));
ALTER TABLE public.table_export_run ADD CONSTRAINT table_export_run_check CHECK (((kind = 'full'::text) = (since IS NULL)));
ALTER TABLE public.table_export_run ADD CONSTRAINT table_export_run_kind_check CHECK ((kind = ANY (ARRAY['full'::text, 'incremental'::text])));
ALTER TABLE public.table_export_run ADD CONSTRAINT table_export_run_status_check CHECK ((status = ANY (ARRAY['running'::text, 'done'::text, 'failed'::text])));
ALTER TABLE public.target_contract ADD CONSTRAINT target_contract_baseline_state_check CHECK ((baseline_state = ANY (ARRAY['measured'::text, 'unknown'::text, 'not_instrumented'::text])));
ALTER TABLE public.target_contract ADD CONSTRAINT target_contract_desired_basis_check CHECK ((desired_basis = ANY (ARRAY['cumulative'::text, 'incremental'::text, 'gross'::text, 'net'::text, 'active'::text])));
ALTER TABLE public.target_contract ADD CONSTRAINT target_contract_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'superseded'::text, 'achieved'::text, 'failed'::text, 'abandoned'::text])));
ALTER TABLE public.target_daily_verdict ADD CONSTRAINT target_daily_verdict_status_check CHECK ((status = ANY (ARRAY['on_track'::text, 'within_tolerance'::text, 'miss'::text, 'not_measurable'::text, 'no_target'::text, 'too_early'::text, 'not_yet_due'::text, 'paused'::text])));
ALTER TABLE public.target_driver ADD CONSTRAINT target_driver_rate_check CHECK (((rate >= (0)::numeric) AND (rate <= (1)::numeric)));
ALTER TABLE public.target_driver ADD CONSTRAINT target_driver_rate_source_check CHECK ((rate_source = ANY (ARRAY['measured'::text, 'assumed'::text, 'industry_prior'::text, 'not_instrumented'::text])));
ALTER TABLE public.target_label ADD CONSTRAINT target_label_words_check CHECK ((btrim(words) <> ''::text));
ALTER TABLE public.target_path ADD CONSTRAINT target_path_direction_check CHECK ((direction = ANY (ARRAY['min'::text, 'max'::text])));
ALTER TABLE public.target_path ADD CONSTRAINT target_path_kind_check CHECK ((kind = ANY (ARRAY['month'::text, 'cumulative'::text, 'level'::text, 'rate'::text])));
ALTER TABLE public.target_path ADD CONSTRAINT target_path_month_check CHECK ((EXTRACT(day FROM month) = (1)::numeric));
ALTER TABLE public.target_path ADD CONSTRAINT target_path_tolerance_pct_check CHECK (((tolerance_pct > (0)::numeric) AND (tolerance_pct < (100)::numeric)));
ALTER TABLE public.target_path ADD CONSTRAINT target_path_value_check CHECK ((value >= (0)::numeric));
ALTER TABLE public.target_verdict ADD CONSTRAINT target_verdict_verdict_check CHECK ((verdict = ANY (ARRAY['ACHIEVABLE'::text, 'AT_RISK'::text, 'NOT_ACHIEVABLE'::text, 'CANNOT_ASSESS'::text])));
ALTER TABLE public.taxonomy_trade ADD CONSTRAINT taxonomy_trade_umbrella_is_another_trade CHECK ((umbrella_code IS DISTINCT FROM code));
ALTER TABLE public.taxonomy_trade_code ADD CONSTRAINT taxonomy_trade_code_code_check CHECK ((code ~ '^[0-9]{4,10}$'::text));
ALTER TABLE public.taxonomy_trade_code ADD CONSTRAINT taxonomy_trade_code_scheme_check CHECK ((scheme = ANY (ARRAY['isic4'::text, 'uae_activity'::text, 'unspsc'::text])));
ALTER TABLE public.taxonomy_trade_group ADD CONSTRAINT taxonomy_trade_group_code_check CHECK ((code ~ '^[a-z][a-z0-9_]*$'::text));
ALTER TABLE public.taxonomy_trade_group ADD CONSTRAINT taxonomy_trade_group_label_ar_check CHECK ((label_ar ~ '[ء-ي]'::text));
ALTER TABLE public.taxonomy_trade_group ADD CONSTRAINT taxonomy_trade_group_label_en_check CHECK ((btrim(label_en) <> ''::text));
ALTER TABLE public.taxonomy_trade_proposal ADD CONSTRAINT taxonomy_trade_proposal_check CHECK (((label_en IS NOT NULL) OR (label_ar IS NOT NULL)));
ALTER TABLE public.taxonomy_trade_proposal ADD CONSTRAINT taxonomy_trade_proposal_check1 CHECK (((status = ANY (ARRAY['map_offered'::text, 'mapped'::text])) = (mapped_to IS NOT NULL)));
ALTER TABLE public.taxonomy_trade_proposal ADD CONSTRAINT taxonomy_trade_proposal_code_check CHECK ((btrim(code) <> ''::text));
ALTER TABLE public.taxonomy_trade_proposal ADD CONSTRAINT taxonomy_trade_proposal_owner_seat_check CHECK ((owner_seat = 'sales_engineer'::text));
ALTER TABLE public.taxonomy_trade_proposal ADD CONSTRAINT taxonomy_trade_proposal_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'added'::text, 'map_offered'::text, 'mapped'::text, 'rejected'::text])));
ALTER TABLE public.taxonomy_trade_service ADD CONSTRAINT taxonomy_trade_service_code_check CHECK ((code ~ '^[a-z][a-z0-9_]*$'::text));
ALTER TABLE public.taxonomy_trade_service ADD CONSTRAINT taxonomy_trade_service_label_ar_check CHECK ((label_ar ~ '[ء-ي]'::text));
ALTER TABLE public.taxonomy_trade_service ADD CONSTRAINT taxonomy_trade_service_label_en_check CHECK ((btrim(label_en) <> ''::text));
ALTER TABLE public.trade_spec_checklist ADD CONSTRAINT trade_spec_checklist_specs_check CHECK (((jsonb_typeof(specs) = 'array'::text) AND (jsonb_array_length(specs) > 0)));
ALTER TABLE public.trade_spec_checklist ADD CONSTRAINT trade_spec_checklist_topic_check CHECK ((btrim(topic) <> ''::text));
ALTER TABLE public.trade_spec_checklist ADD CONSTRAINT trade_spec_checklist_topic_id_check CHECK ((btrim(topic_id) <> ''::text));
ALTER TABLE public.trade_spec_checklist ADD CONSTRAINT trade_spec_checklist_trade_code_check CHECK ((trade_code ~ '^[a-z0-9_-]+$'::text));
ALTER TABLE public.ui_label ADD CONSTRAINT ui_label_domain_check CHECK ((domain = ANY (ARRAY['action_kind'::text, 'notification_type'::text, 'customer_signal'::text])));
ALTER TABLE public.ui_label ADD CONSTRAINT ui_label_label_check CHECK ((btrim(label) <> ''::text));
ALTER TABLE public.vendor_billing_ended ADD CONSTRAINT vendor_billing_ended_kind_ck CHECK ((kind = ANY (ARRAY['ended'::text, 'annual'::text, 'one_off'::text, 'portal_only'::text])));
ALTER TABLE public.wa_conversation ADD CONSTRAINT wa_conversation_party_kind_check CHECK ((party_kind = ANY (ARRAY['lead'::text, 'customer'::text, 'unknown'::text])));
ALTER TABLE public.wa_conversation ADD CONSTRAINT wa_conversation_thread_state_check CHECK ((thread_state = ANY (ARRAY['open'::text, 'awaiting_reply'::text, 'awaiting_document'::text, 'resolved'::text, 'handed_to_human'::text])));
ALTER TABLE public.wa_document_intake ADD CONSTRAINT wa_document_intake_classified_as_check CHECK ((classified_as = ANY (ARRAY['licence'::text, 'profile'::text, 'signed_terms'::text, 'unknown'::text])));
ALTER TABLE public.wa_document_intake ADD CONSTRAINT wa_document_intake_classified_by_check CHECK ((classified_by = ANY (ARRAY['caption'::text, 'filename'::text, 'model'::text, 'human'::text])));
ALTER TABLE public.wa_document_intake ADD CONSTRAINT wa_document_intake_confidence_check CHECK ((confidence = ANY (ARRAY['high'::text, 'low'::text])));
ALTER TABLE public.wa_reply_intent ADD CONSTRAINT wa_reply_intent_scope_check CHECK ((scope = ANY (ARRAY['company'::text, 'own_records'::text, 'by_id'::text])));
ALTER TABLE public.wa_template_registry ADD CONSTRAINT wa_template_registry_status_check CHECK ((status = ANY (ARRAY['approved'::text, 'pending'::text, 'rejected'::text, 'unsubmitted'::text, 'missing'::text])));
ALTER TABLE public.wa_turn ADD CONSTRAINT wa_turn_answered_by_check CHECK ((answered_by = ANY (ARRAY['deterministic'::text, 'model'::text, 'human'::text, 'template'::text])));
ALTER TABLE public.wa_turn ADD CONSTRAINT wa_turn_direction_check CHECK ((direction = ANY (ARRAY['in'::text, 'out'::text])));
ALTER TABLE public.wa_turn ADD CONSTRAINT wa_turn_transcript_source_check CHECK ((transcript_source = ANY (ARRAY['twilio'::text, 'model'::text, 'none'::text])));
ALTER TABLE public.web_search_day ADD CONSTRAINT web_search_day_cap_check CHECK ((cap > 0));
ALTER TABLE public.web_search_day ADD CONSTRAINT web_search_day_used_check CHECK ((used >= 0));
ALTER TABLE public.writer_seat ADD CONSTRAINT writer_seat_kind_check CHECK ((kind = ANY (ARRAY['agent_runs_label'::text, 'cron_job'::text])));
ALTER TABLE public.accountant_subscription_paid_from_change ADD CONSTRAINT accountant_subscription_paid_from_change_vendor_fkey FOREIGN KEY (vendor) REFERENCES accountant_owner_ruled_subscription(vendor);
ALTER TABLE public.action_execution ADD CONSTRAINT action_execution_workflow_step_run_id_fkey FOREIGN KEY (workflow_step_run_id) REFERENCES workflow_step_run(id);
ALTER TABLE public.ad_decision ADD CONSTRAINT ad_decision_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES ad_campaign_state(campaign_id) ON DELETE CASCADE;
ALTER TABLE public.agent_actions ADD CONSTRAINT agent_actions_decision_log_id_fkey FOREIGN KEY (decision_log_id) REFERENCES decision_log(id);
ALTER TABLE public.agent_remediation ADD CONSTRAINT agent_remediation_agent_key_fkey FOREIGN KEY (agent_key) REFERENCES org_agents(agent_key) ON DELETE CASCADE;
ALTER TABLE public.agent_tool ADD CONSTRAINT agent_tool_action_class_fkey FOREIGN KEY (action_class) REFERENCES org_action_executor(action_class);
ALTER TABLE public.agent_training_attempt ADD CONSTRAINT agent_training_attempt_agent_key_fkey FOREIGN KEY (agent_key) REFERENCES org_agents(agent_key) ON DELETE CASCADE;
ALTER TABLE public.agent_training_attempt ADD CONSTRAINT agent_training_attempt_case_id_fkey FOREIGN KEY (case_id) REFERENCES agent_training_case(case_id) ON DELETE CASCADE;
ALTER TABLE public.ap_bills ADD CONSTRAINT ap_bills_gl_journal_id_fkey FOREIGN KEY (gl_journal_id) REFERENCES gl_journal(id);
ALTER TABLE public.ap_bills ADD CONSTRAINT ap_bills_pay_journal_id_fkey FOREIGN KEY (pay_journal_id) REFERENCES gl_journal(id);
ALTER TABLE public.ap_bills ADD CONSTRAINT ap_bills_po_id_fkey FOREIGN KEY (po_id) REFERENCES po_orders(id);
ALTER TABLE public.ap_bills ADD CONSTRAINT ap_bills_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES po_vendors(id);
ALTER TABLE public.bank_line_owner_ruling ADD CONSTRAINT bank_line_owner_ruling_line_id_fkey FOREIGN KEY (line_id) REFERENCES bank_statement_line(id);
ALTER TABLE public.bank_reference_code ADD CONSTRAINT bank_reference_code_gl_account_fkey FOREIGN KEY (gl_account) REFERENCES gl_accounts(code);
ALTER TABLE public.bank_statement_line ADD CONSTRAINT bank_statement_line_source_ref_fkey FOREIGN KEY (source_ref) REFERENCES bank_statement_intake(source_ref);
ALTER TABLE public.board_opinion ADD CONSTRAINT board_opinion_advisor_key_fkey FOREIGN KEY (advisor_key) REFERENCES board_advisor(advisor_key);
ALTER TABLE public.boq_fixture ADD CONSTRAINT boq_fixture_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE;
ALTER TABLE public.boq_fixture_run ADD CONSTRAINT boq_fixture_run_fixture_id_fkey FOREIGN KEY (fixture_id) REFERENCES boq_fixture(id) ON DELETE CASCADE;
ALTER TABLE public.budget_lines ADD CONSTRAINT budget_lines_account_code_fkey FOREIGN KEY (account_code) REFERENCES gl_accounts(code);
ALTER TABLE public.budget_lines ADD CONSTRAINT budget_lines_budget_id_fkey FOREIGN KEY (budget_id) REFERENCES budgets(id) ON DELETE CASCADE;
ALTER TABLE public.catalog_category_domain ADD CONSTRAINT catalog_category_domain_catalog_slug_fkey FOREIGN KEY (catalog_slug) REFERENCES catalog_supplier_categories(slug);
ALTER TABLE public.catalog_category_domain ADD CONSTRAINT catalog_category_domain_domain_slug_fkey FOREIGN KEY (domain_slug) REFERENCES catalog_domains(slug);
ALTER TABLE public.catalog_subcategories ADD CONSTRAINT catalog_subcategories_domain_slug_fkey FOREIGN KEY (domain_slug) REFERENCES catalog_domains(slug) ON DELETE CASCADE;
ALTER TABLE public.category_agent_map ADD CONSTRAINT category_agent_map_agent_slug_fkey FOREIGN KEY (agent_slug) REFERENCES category_agents(slug) ON DELETE SET NULL;
ALTER TABLE public.category_agent_map ADD CONSTRAINT category_agent_map_catalog_slug_fkey FOREIGN KEY (catalog_slug) REFERENCES catalog_supplier_categories(slug) ON DELETE CASCADE;
ALTER TABLE public.category_keyword ADD CONSTRAINT category_keyword_slug_fkey FOREIGN KEY (slug) REFERENCES catalog_supplier_categories(slug) ON DELETE CASCADE;
ALTER TABLE public.category_route_map ADD CONSTRAINT category_route_map_catalog_num_fkey FOREIGN KEY (catalog_num) REFERENCES kb_operational_route(catalog_num) ON DELETE CASCADE;
ALTER TABLE public.ceo_approval ADD CONSTRAINT ceo_approval_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES ceo_identity(identity);
ALTER TABLE public.ceo_approval ADD CONSTRAINT ceo_approval_superseded_by_fkey FOREIGN KEY (superseded_by) REFERENCES ceo_approval(decision_id);
ALTER TABLE public.ceo_command ADD CONSTRAINT ceo_command_intent_id_fkey FOREIGN KEY (intent_id) REFERENCES ceo_command_intent(intent_id);
ALTER TABLE public.ceo_command ADD CONSTRAINT ceo_command_matched_rule_fkey FOREIGN KEY (matched_rule) REFERENCES ceo_command_rule(rule_id);
ALTER TABLE public.ceo_command ADD CONSTRAINT ceo_command_state_fkey FOREIGN KEY (state) REFERENCES ceo_command_state(state);
ALTER TABLE public.ceo_command_rule ADD CONSTRAINT ceo_command_rule_intent_id_fkey FOREIGN KEY (intent_id) REFERENCES ceo_command_intent(intent_id);
ALTER TABLE public.ceo_command_transition ADD CONSTRAINT ceo_command_transition_from_state_fkey FOREIGN KEY (from_state) REFERENCES ceo_command_state(state);
ALTER TABLE public.ceo_command_transition ADD CONSTRAINT ceo_command_transition_to_state_fkey FOREIGN KEY (to_state) REFERENCES ceo_command_state(state);
ALTER TABLE public.ceo_company_stage_log ADD CONSTRAINT ceo_company_stage_log_stage_fkey FOREIGN KEY (stage) REFERENCES ceo_company_stage(stage);
ALTER TABLE public.ceo_constraint_lever ADD CONSTRAINT ceo_constraint_lever_owner_seat_fkey FOREIGN KEY (owner_seat) REFERENCES org_role(role_id);
ALTER TABLE public.ceo_decision_log ADD CONSTRAINT ceo_decision_log_decision_key_fkey FOREIGN KEY (decision_key) REFERENCES ceo_decision(decision_key);
ALTER TABLE public.ceo_decision_round ADD CONSTRAINT ceo_decision_round_originator_seat_fkey FOREIGN KEY (originator_seat) REFERENCES org_role(role_id);
ALTER TABLE public.ceo_directive ADD CONSTRAINT ceo_directive_escalated_from_fkey FOREIGN KEY (escalated_from) REFERENCES ceo_directive(id);
ALTER TABLE public.ceo_directive ADD CONSTRAINT ceo_directive_seat_fkey FOREIGN KEY (seat) REFERENCES org_role(role_id);
ALTER TABLE public.ceo_experiment ADD CONSTRAINT ceo_experiment_owner_seat_fkey FOREIGN KEY (owner_seat) REFERENCES org_role(role_id);
ALTER TABLE public.ceo_experiment ADD CONSTRAINT ceo_experiment_proposed_by_fkey FOREIGN KEY (proposed_by) REFERENCES org_role(role_id);
ALTER TABLE public.ceo_experiment_verdict ADD CONSTRAINT ceo_experiment_verdict_experiment_id_fkey FOREIGN KEY (experiment_id) REFERENCES ceo_experiment(id) ON DELETE CASCADE;
ALTER TABLE public.ceo_improvement ADD CONSTRAINT ceo_improvement_seat_fkey FOREIGN KEY (seat) REFERENCES org_role(role_id);
ALTER TABLE public.ceo_month_close ADD CONSTRAINT ceo_month_close_seat_fkey FOREIGN KEY (seat) REFERENCES org_role(role_id);
ALTER TABLE public.ceo_plan_action ADD CONSTRAINT ceo_plan_action_seat_fkey FOREIGN KEY (seat) REFERENCES org_role(role_id);
ALTER TABLE public.ceo_seat_audit ADD CONSTRAINT ceo_seat_audit_seat_fkey FOREIGN KEY (seat) REFERENCES org_role(role_id);
ALTER TABLE public.ceo_seat_directive ADD CONSTRAINT ceo_seat_directive_seat_fkey FOREIGN KEY (seat) REFERENCES org_role(role_id);
ALTER TABLE public.ceo_standing_grant ADD CONSTRAINT ceo_standing_grant_grantee_role_id_fkey FOREIGN KEY (grantee_role_id) REFERENCES org_role(role_id) ON DELETE CASCADE;
ALTER TABLE public.ceo_task ADD CONSTRAINT ceo_task_command_id_fkey FOREIGN KEY (command_id) REFERENCES ceo_command(command_id);
ALTER TABLE public.ceo_task ADD CONSTRAINT ceo_task_state_fkey FOREIGN KEY (state) REFERENCES ceo_task_state(state);
ALTER TABLE public.charge_audit ADD CONSTRAINT charge_audit_transaction_id_fkey FOREIGN KEY (transaction_id) REFERENCES transactions(id);
ALTER TABLE public.chat_threads ADD CONSTRAINT chat_threads_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id);
ALTER TABLE public.company_charter ADD CONSTRAINT company_charter_superseded_by_fkey FOREIGN KEY (superseded_by) REFERENCES company_charter(id);
ALTER TABLE public.company_goals ADD CONSTRAINT company_goals_owner_dept_fkey FOREIGN KEY (owner_dept) REFERENCES org_departments(dept_key);
ALTER TABLE public.company_review_ask ADD CONSTRAINT company_review_ask_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE;
ALTER TABLE public.company_review_ask ADD CONSTRAINT company_review_ask_transaction_id_fkey FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE CASCADE;
ALTER TABLE public.comparison_run_v2 ADD CONSTRAINT comparison_run_v2_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id);
ALTER TABLE public.competitor_scan ADD CONSTRAINT competitor_scan_competitor_id_fkey FOREIGN KEY (competitor_id) REFERENCES competitor(id) ON DELETE CASCADE;
ALTER TABLE public.complaint_tickets ADD CONSTRAINT complaint_tickets_contact_message_id_fkey FOREIGN KEY (contact_message_id) REFERENCES contact_messages(id) ON DELETE SET NULL;
ALTER TABLE public.contact_merge_audit ADD CONSTRAINT contact_merge_audit_group_id_fkey FOREIGN KEY (group_id) REFERENCES contact_duplicate_group(id);
ALTER TABLE public.continuity_plan ADD CONSTRAINT continuity_plan_service_fkey FOREIGN KEY (service) REFERENCES integration_matrix(service);
ALTER TABLE public.control_mode_challenge ADD CONSTRAINT control_mode_challenge_admin_email_fkey FOREIGN KEY (admin_email) REFERENCES control_mode_identity(admin_email) ON DELETE CASCADE;
ALTER TABLE public.control_mode_session ADD CONSTRAINT control_mode_session_mfa_ref_fk FOREIGN KEY (mfa_ref) REFERENCES control_mode_challenge(id) ON DELETE RESTRICT;
ALTER TABLE public.customer_calls ADD CONSTRAINT customer_calls_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE public.customer_calls ADD CONSTRAINT customer_calls_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id);
ALTER TABLE public.customer_calls ADD CONSTRAINT customer_calls_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id);
ALTER TABLE public.customer_followup ADD CONSTRAINT customer_followup_transaction_id_fkey FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE CASCADE;
ALTER TABLE public.customer_layout ADD CONSTRAINT customer_layout_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE public.customer_phone_otps ADD CONSTRAINT customer_phone_otps_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE;
ALTER TABLE public.customer_preference ADD CONSTRAINT customer_preference_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE public.customers ADD CONSTRAINT customers_merged_into_fkey FOREIGN KEY (merged_into) REFERENCES customers(id);
ALTER TABLE public.decision_record ADD CONSTRAINT decision_record_serves_goal_fkey FOREIGN KEY (serves_goal) REFERENCES company_goals(key);
ALTER TABLE public.decision_review_request ADD CONSTRAINT decision_review_request_decision_type_owner_seat_fkey FOREIGN KEY (decision_type, owner_seat) REFERENCES review_route(decision_type, owner_seat);
ALTER TABLE public.decision_review_request ADD CONSTRAINT decision_review_request_original_seat_fkey FOREIGN KEY (original_seat) REFERENCES org_role(role_id);
ALTER TABLE public.decision_review_request ADD CONSTRAINT decision_review_request_reviewer_seat_fkey FOREIGN KEY (reviewer_seat) REFERENCES org_role(role_id);
ALTER TABLE public.decision_trace ADD CONSTRAINT decision_trace_causation_event_id_fkey FOREIGN KEY (causation_event_id) REFERENCES company_event(id);
ALTER TABLE public.deliverability_test_provider ADD CONSTRAINT deliverability_test_provider_test_id_fkey FOREIGN KEY (test_id) REFERENCES deliverability_test(test_id) ON DELETE CASCADE;
ALTER TABLE public.department_objective ADD CONSTRAINT department_objective_goal_key_fkey FOREIGN KEY (goal_key) REFERENCES company_goals(key);
ALTER TABLE public.dept_knowledge_alias ADD CONSTRAINT dept_knowledge_alias_dept_key_fkey FOREIGN KEY (dept_key) REFERENCES org_departments(dept_key);
ALTER TABLE public.doc_reviews ADD CONSTRAINT doc_reviews_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id);
ALTER TABLE public.drawing_redaction_runs ADD CONSTRAINT drawing_redaction_runs_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL;
ALTER TABLE public.employee_knowledge ADD CONSTRAINT employee_knowledge_domain_key_fkey FOREIGN KEY (domain_key) REFERENCES knowledge_domain(domain_key) ON DELETE CASCADE;
ALTER TABLE public.employee_knowledge ADD CONSTRAINT employee_knowledge_layer_no_fkey FOREIGN KEY (layer_no) REFERENCES employee_knowledge_standard(layer_no);
ALTER TABLE public.employee_kpi ADD CONSTRAINT employee_kpi_serves_goal_fkey FOREIGN KEY (serves_goal) REFERENCES company_goals(key);
ALTER TABLE public.employee_kpi ADD CONSTRAINT employee_kpi_serves_objective_fkey FOREIGN KEY (serves_objective) REFERENCES os_objective(id);
ALTER TABLE public.employee_kpi_history ADD CONSTRAINT employee_kpi_history_kpi_id_fkey FOREIGN KEY (kpi_id) REFERENCES employee_kpi(id) ON DELETE CASCADE;
ALTER TABLE public.employee_workflow ADD CONSTRAINT employee_workflow_workflow_key_fkey FOREIGN KEY (workflow_key) REFERENCES workflow(workflow_key) ON DELETE CASCADE;
ALTER TABLE public.event_assessment ADD CONSTRAINT event_assessment_event_id_fkey FOREIGN KEY (event_id) REFERENCES company_event(id) ON DELETE CASCADE;
ALTER TABLE public.event_assessment ADD CONSTRAINT event_assessment_os_key_fkey FOREIGN KEY (os_key) REFERENCES operating_system(os_key);
ALTER TABLE public.event_delivery ADD CONSTRAINT event_delivery_event_id_fkey FOREIGN KEY (event_id) REFERENCES company_event(id) ON DELETE CASCADE;
ALTER TABLE public.event_rollup ADD CONSTRAINT event_rollup_root_event_id_fkey FOREIGN KEY (root_event_id) REFERENCES company_event(id) ON DELETE SET NULL;
ALTER TABLE public.expense_bank_match ADD CONSTRAINT expense_bank_match_bank_line_id_fkey FOREIGN KEY (bank_line_id) REFERENCES bank_statement_line(id) ON DELETE CASCADE;
ALTER TABLE public.expense_bank_match ADD CONSTRAINT expense_bank_match_expense_entry_id_fkey FOREIGN KEY (expense_entry_id) REFERENCES expense_entries(id) ON DELETE CASCADE;
ALTER TABLE public.expense_vendor_billing_mailbox ADD CONSTRAINT expense_vendor_billing_mailbox_mailbox_fkey FOREIGN KEY (mailbox) REFERENCES expense_billing_mailbox(mailbox);
ALTER TABLE public.feedback ADD CONSTRAINT feedback_case_id_fkey FOREIGN KEY (case_id) REFERENCES support_case(case_id);
ALTER TABLE public.feedback ADD CONSTRAINT feedback_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES support_customer_profile(id);
ALTER TABLE public.field_definition ADD CONSTRAINT field_definition_trade_key_fkey FOREIGN KEY (trade_key) REFERENCES mep_trade(trade_key);
ALTER TABLE public.field_definition_reference ADD CONSTRAINT field_definition_reference_field_id_fkey FOREIGN KEY (field_id) REFERENCES field_definition(field_id) ON DELETE CASCADE;
ALTER TABLE public.field_definition_reference ADD CONSTRAINT field_definition_reference_referencing_trade_key_fkey FOREIGN KEY (referencing_trade_key) REFERENCES mep_trade(trade_key);
ALTER TABLE public.field_definition_trade ADD CONSTRAINT field_definition_trade_field_id_fkey FOREIGN KEY (field_id) REFERENCES field_definition(field_id) ON DELETE CASCADE;
ALTER TABLE public.field_definition_trade ADD CONSTRAINT field_definition_trade_trade_key_fkey FOREIGN KEY (trade_key) REFERENCES mep_trade(trade_key) ON DELETE CASCADE;
ALTER TABLE public.gl_account_funnel_stage ADD CONSTRAINT gl_account_funnel_stage_account_code_fkey FOREIGN KEY (account_code) REFERENCES gl_accounts(code);
ALTER TABLE public.gl_accounts ADD CONSTRAINT gl_accounts_parent_code_fkey FOREIGN KEY (parent_code) REFERENCES gl_accounts(code);
ALTER TABLE public.gl_expense_map ADD CONSTRAINT gl_expense_map_account_code_fkey FOREIGN KEY (account_code) REFERENCES gl_accounts(code);
ALTER TABLE public.gl_journal ADD CONSTRAINT gl_journal_reverses_fkey FOREIGN KEY (reverses) REFERENCES gl_journal(id);
ALTER TABLE public.gl_journal_lines ADD CONSTRAINT gl_journal_lines_account_code_fkey FOREIGN KEY (account_code) REFERENCES gl_accounts(code);
ALTER TABLE public.gl_journal_lines ADD CONSTRAINT gl_journal_lines_journal_id_fkey FOREIGN KEY (journal_id) REFERENCES gl_journal(id) ON DELETE CASCADE;
ALTER TABLE public.gl_prior_period_adjustment ADD CONSTRAINT gl_prior_period_adjustment_journal_id_fkey FOREIGN KEY (journal_id) REFERENCES gl_journal(id);
ALTER TABLE public.gl_prior_period_adjustment ADD CONSTRAINT gl_prior_period_adjustment_statement_line_id_fkey FOREIGN KEY (statement_line_id) REFERENCES bank_statement_line(id);
ALTER TABLE public.goal_period ADD CONSTRAINT goal_period_goal_key_fkey FOREIGN KEY (goal_key) REFERENCES company_goals(key) ON DELETE CASCADE;
ALTER TABLE public.handoff_contract ADD CONSTRAINT handoff_contract_accepted_by_fkey FOREIGN KEY (accepted_by) REFERENCES org_agents(agent_key);
ALTER TABLE public.handoff_contract ADD CONSTRAINT handoff_contract_accountable_owner_fkey FOREIGN KEY (accountable_owner) REFERENCES org_agents(agent_key);
ALTER TABLE public.handoff_contract ADD CONSTRAINT handoff_contract_action_id_fkey FOREIGN KEY (action_id) REFERENCES agent_actions(id) ON DELETE CASCADE;
ALTER TABLE public.handoff_contract ADD CONSTRAINT handoff_contract_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES org_agents(agent_key);
ALTER TABLE public.handoff_contract ADD CONSTRAINT handoff_contract_from_dept_fkey FOREIGN KEY (from_dept) REFERENCES org_departments(dept_key);
ALTER TABLE public.handoff_contract ADD CONSTRAINT handoff_contract_to_dept_fkey FOREIGN KEY (to_dept) REFERENCES org_departments(dept_key);
ALTER TABLE public.idea ADD CONSTRAINT idea_serves_goal_fkey FOREIGN KEY (serves_goal) REFERENCES company_goals(key);
ALTER TABLE public.inbound_messages ADD CONSTRAINT inbound_messages_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id);
ALTER TABLE public.inquiries ADD CONSTRAINT inquiries_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE public.inquiries ADD CONSTRAINT inquiries_hired_supplier_id_fkey FOREIGN KEY (hired_supplier_id) REFERENCES leads(id);
ALTER TABLE public.inquiries ADD CONSTRAINT inquiries_parent_inquiry_id_fkey FOREIGN KEY (parent_inquiry_id) REFERENCES inquiries(id);
ALTER TABLE public.inquiries ADD CONSTRAINT inquiries_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL;
ALTER TABLE public.inquiries ADD CONSTRAINT inquiries_repeat_of_fkey FOREIGN KEY (repeat_of) REFERENCES inquiries(id) ON DELETE SET NULL;
ALTER TABLE public.inquiry_answer ADD CONSTRAINT inquiry_answer_field_id_fkey FOREIGN KEY (field_id) REFERENCES field_definition(field_id);
ALTER TABLE public.inquiry_answer ADD CONSTRAINT inquiry_answer_group_id_fkey FOREIGN KEY (group_id) REFERENCES inquiry_workstream_group(id) ON DELETE CASCADE;
ALTER TABLE public.inquiry_answer ADD CONSTRAINT inquiry_answer_superseded_by_fkey FOREIGN KEY (superseded_by) REFERENCES inquiry_answer(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE public.inquiry_answer_conflict ADD CONSTRAINT inquiry_answer_conflict_field_id_fkey FOREIGN KEY (field_id) REFERENCES field_definition(field_id);
ALTER TABLE public.inquiry_answer_conflict ADD CONSTRAINT inquiry_answer_conflict_group_id_fkey FOREIGN KEY (group_id) REFERENCES inquiry_workstream_group(id) ON DELETE CASCADE;
ALTER TABLE public.inquiry_answer_conflict_value ADD CONSTRAINT inquiry_answer_conflict_value_conflict_id_fkey FOREIGN KEY (conflict_id) REFERENCES inquiry_answer_conflict(id) ON DELETE CASCADE;
ALTER TABLE public.inquiry_answer_corroboration ADD CONSTRAINT inquiry_answer_corroboration_answer_id_fkey FOREIGN KEY (answer_id) REFERENCES inquiry_answer(id) ON DELETE CASCADE;
ALTER TABLE public.inquiry_answer_document ADD CONSTRAINT inquiry_answer_document_answer_id_fkey FOREIGN KEY (answer_id) REFERENCES inquiry_answer(id) ON DELETE CASCADE;
ALTER TABLE public.inquiry_answer_scope ADD CONSTRAINT inquiry_answer_scope_answer_id_fkey FOREIGN KEY (answer_id) REFERENCES inquiry_answer(id) ON DELETE CASCADE;
ALTER TABLE public.inquiry_answer_scope ADD CONSTRAINT inquiry_answer_scope_workstream_id_fkey FOREIGN KEY (workstream_id) REFERENCES inquiry_workstream(id) ON DELETE CASCADE;
ALTER TABLE public.inquiry_conversation_summary ADD CONSTRAINT inquiry_conversation_summary_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id);
ALTER TABLE public.inquiry_gate ADD CONSTRAINT inquiry_gate_gate_key_fkey FOREIGN KEY (gate_key) REFERENCES inquiry_gate_required(gate_key);
ALTER TABLE public.inquiry_gate ADD CONSTRAINT inquiry_gate_group_id_fkey FOREIGN KEY (group_id) REFERENCES inquiry_workstream_group(id) ON DELETE CASCADE;
ALTER TABLE public.inquiry_gate ADD CONSTRAINT inquiry_gate_workstream_id_fkey FOREIGN KEY (workstream_id) REFERENCES inquiry_workstream(id) ON DELETE CASCADE;
ALTER TABLE public.inquiry_matches ADD CONSTRAINT inquiry_matches_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id) ON DELETE CASCADE;
ALTER TABLE public.inquiry_matches ADD CONSTRAINT inquiry_matches_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES leads(id);
ALTER TABLE public.inquiry_requirement ADD CONSTRAINT inquiry_requirement_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id) ON DELETE CASCADE;
ALTER TABLE public.inquiry_scope_disposition ADD CONSTRAINT inquiry_scope_disposition_disposition_fkey FOREIGN KEY (disposition) REFERENCES scope_disposition_kind(disposition);
ALTER TABLE public.inquiry_scope_disposition ADD CONSTRAINT inquiry_scope_disposition_group_id_fkey FOREIGN KEY (group_id) REFERENCES inquiry_workstream_group(id) ON DELETE CASCADE;
ALTER TABLE public.inquiry_scope_disposition ADD CONSTRAINT inquiry_scope_disposition_scope_component_fkey FOREIGN KEY (scope_component) REFERENCES scope_component(component);
ALTER TABLE public.inquiry_scope_disposition ADD CONSTRAINT inquiry_scope_disposition_trade_key_fkey FOREIGN KEY (trade_key) REFERENCES mep_trade(trade_key);
ALTER TABLE public.inquiry_supplier_brief ADD CONSTRAINT inquiry_supplier_brief_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id) ON DELETE CASCADE;
ALTER TABLE public.inquiry_trade_candidate ADD CONSTRAINT inquiry_trade_candidate_group_id_fkey FOREIGN KEY (group_id) REFERENCES inquiry_workstream_group(id) ON DELETE CASCADE;
ALTER TABLE public.inquiry_trade_candidate ADD CONSTRAINT inquiry_trade_candidate_trade_key_fkey FOREIGN KEY (trade_key) REFERENCES mep_trade(trade_key);
ALTER TABLE public.inquiry_trade_candidate ADD CONSTRAINT inquiry_trade_candidate_workstream_id_fkey FOREIGN KEY (workstream_id) REFERENCES inquiry_workstream(id);
ALTER TABLE public.inquiry_trade_candidate_evidence ADD CONSTRAINT inquiry_trade_candidate_evidence_candidate_id_fkey FOREIGN KEY (candidate_id) REFERENCES inquiry_trade_candidate(id) ON DELETE CASCADE;
ALTER TABLE public.inquiry_trade_clarification ADD CONSTRAINT inquiry_trade_clarification_group_id_fkey FOREIGN KEY (group_id) REFERENCES inquiry_workstream_group(id) ON DELETE CASCADE;
ALTER TABLE public.inquiry_workstream ADD CONSTRAINT inquiry_workstream_group_id_fkey FOREIGN KEY (group_id) REFERENCES inquiry_workstream_group(id) ON DELETE CASCADE;
ALTER TABLE public.inquiry_workstream ADD CONSTRAINT inquiry_workstream_trade_key_fkey FOREIGN KEY (trade_key) REFERENCES mep_trade(trade_key);
ALTER TABLE public.inquiry_workstream_requirement ADD CONSTRAINT inquiry_workstream_requirement_field_id_fkey FOREIGN KEY (field_id) REFERENCES field_definition(field_id);
ALTER TABLE public.inquiry_workstream_requirement ADD CONSTRAINT inquiry_workstream_requirement_workstream_id_fkey FOREIGN KEY (workstream_id) REFERENCES inquiry_workstream(id) ON DELETE CASCADE;
ALTER TABLE public.institutional_memory ADD CONSTRAINT institutional_memory_os_key_fkey FOREIGN KEY (os_key) REFERENCES operating_system(os_key);
ALTER TABLE public.inv_items ADD CONSTRAINT inv_items_cogs_account_fkey FOREIGN KEY (cogs_account) REFERENCES gl_accounts(code);
ALTER TABLE public.inv_items ADD CONSTRAINT inv_items_inventory_account_fkey FOREIGN KEY (inventory_account) REFERENCES gl_accounts(code);
ALTER TABLE public.it_credential_rotation ADD CONSTRAINT it_credential_rotation_new_id_fkey FOREIGN KEY (new_id) REFERENCES internal_credential(id);
ALTER TABLE public.it_credential_rotation ADD CONSTRAINT it_credential_rotation_old_id_fkey FOREIGN KEY (old_id) REFERENCES internal_credential(id);
ALTER TABLE public.it_duty_schedule ADD CONSTRAINT it_duty_schedule_owner_seat_fk FOREIGN KEY (owner_seat) REFERENCES org_agents(agent_key);
ALTER TABLE public.it_incident ADD CONSTRAINT it_incident_handoff_id_fkey FOREIGN KEY (handoff_id) REFERENCES agent_actions(id);
ALTER TABLE public.it_incident ADD CONSTRAINT it_incident_playbook_class_fkey FOREIGN KEY (playbook_class) REFERENCES it_playbook(failure_class);
ALTER TABLE public.it_model_consumer ADD CONSTRAINT it_model_consumer_owner_seat_fkey FOREIGN KEY (owner_seat) REFERENCES org_role(role_id);
ALTER TABLE public.kb_operational_alias ADD CONSTRAINT kb_operational_alias_catalog_num_fkey FOREIGN KEY (catalog_num) REFERENCES kb_operational_route(catalog_num) ON DELETE CASCADE;
ALTER TABLE public.kb_operational_route_map ADD CONSTRAINT kb_operational_route_map_catalog_num_fkey FOREIGN KEY (catalog_num) REFERENCES kb_operational_route(catalog_num) ON DELETE CASCADE;
ALTER TABLE public.kb_route_scope_trigger ADD CONSTRAINT kb_route_scope_trigger_catalog_num_fkey FOREIGN KEY (catalog_num) REFERENCES kb_operational_route(catalog_num) ON DELETE CASCADE;
ALTER TABLE public.knowledge_exam_results ADD CONSTRAINT knowledge_exam_results_question_id_fkey FOREIGN KEY (question_id) REFERENCES knowledge_exam_questions(id) ON DELETE SET NULL;
ALTER TABLE public.knowledge_ingestion_undo ADD CONSTRAINT knowledge_ingestion_undo_run_id_fkey FOREIGN KEY (run_id) REFERENCES knowledge_ingestion_run(run_id) ON DELETE CASCADE;
ALTER TABLE public.knowledge_library_origin ADD CONSTRAINT knowledge_library_origin_library_id_fkey FOREIGN KEY (library_id) REFERENCES knowledge_library(id) ON DELETE CASCADE;
ALTER TABLE public.lead_category ADD CONSTRAINT lead_category_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id) ON DELETE CASCADE;
ALTER TABLE public.lead_category ADD CONSTRAINT lead_category_slug_fkey FOREIGN KEY (slug) REFERENCES catalog_supplier_categories(slug) ON DELETE CASCADE;
ALTER TABLE public.lead_email_check ADD CONSTRAINT lead_email_check_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id) ON DELETE CASCADE;
ALTER TABLE public.lead_prospect ADD CONSTRAINT lead_prospect_promoted_lead_id_fkey FOREIGN KEY (promoted_lead_id) REFERENCES leads(id) ON DELETE SET NULL;
ALTER TABLE public.lead_prospect ADD CONSTRAINT lead_prospect_run_id_fkey FOREIGN KEY (run_id) REFERENCES lead_sourcing_run(id) ON DELETE CASCADE;
ALTER TABLE public.lead_subcategory ADD CONSTRAINT lead_subcategory_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id) ON DELETE CASCADE;
ALTER TABLE public.lead_subcategory ADD CONSTRAINT lead_subcategory_sub_slug_fkey FOREIGN KEY (sub_slug) REFERENCES catalog_subcategories(slug) ON DELETE CASCADE;
ALTER TABLE public.lead_trade_class ADD CONSTRAINT lead_trade_class_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id) ON DELETE CASCADE;
ALTER TABLE public.lead_trade_map ADD CONSTRAINT lead_trade_map_catalog_slug_fkey FOREIGN KEY (catalog_slug) REFERENCES catalog_supplier_categories(slug);
ALTER TABLE public.leads ADD CONSTRAINT leads_merged_into_fkey FOREIGN KEY (merged_into) REFERENCES leads(id);
ALTER TABLE public.licence_renewal_ask ADD CONSTRAINT licence_renewal_ask_answered_by_intake_fkey FOREIGN KEY (answered_by_intake) REFERENCES wa_document_intake(id);
ALTER TABLE public.licence_renewal_ask ADD CONSTRAINT licence_renewal_ask_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id);
ALTER TABLE public.llm_attempt ADD CONSTRAINT llm_attempt_class_key_fkey FOREIGN KEY (class_key) REFERENCES llm_failure_class(class_key);
ALTER TABLE public.llm_route_health ADD CONSTRAINT llm_route_health_opened_class_fkey FOREIGN KEY (opened_class) REFERENCES llm_failure_class(class_key);
ALTER TABLE public.marketing_article ADD CONSTRAINT marketing_article_topic_id_fkey FOREIGN KEY (topic_id) REFERENCES marketing_blog_topic(id);
ALTER TABLE public.marketing_article_round ADD CONSTRAINT marketing_article_round_article_id_fkey FOREIGN KEY (article_id) REFERENCES marketing_article(id);
ALTER TABLE public.marketing_article_round ADD CONSTRAINT marketing_article_round_topic_id_fkey FOREIGN KEY (topic_id) REFERENCES marketing_blog_topic(id);
ALTER TABLE public.marketing_calendar_resend_decision ADD CONSTRAINT marketing_calendar_resend_decision_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES marketing_campaign(id) ON DELETE CASCADE;
ALTER TABLE public.marketing_first_touch ADD CONSTRAINT marketing_first_touch_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id) ON DELETE CASCADE;
ALTER TABLE public.marketing_first_touch ADD CONSTRAINT marketing_first_touch_post_id_fkey FOREIGN KEY (post_id) REFERENCES marketing_post(id) ON DELETE SET NULL;
ALTER TABLE public.marketing_founder_request ADD CONSTRAINT marketing_founder_request_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES marketing_campaign(id);
ALTER TABLE public.marketing_gap_recruitment_plan ADD CONSTRAINT marketing_gap_recruitment_plan_trade_emirate_fkey FOREIGN KEY (trade, emirate) REFERENCES supply_gap(trade, emirate) ON DELETE CASCADE;
ALTER TABLE public.marketing_geo_check ADD CONSTRAINT marketing_geo_check_question_id_fkey FOREIGN KEY (question_id) REFERENCES marketing_geo_question(id) ON DELETE CASCADE;
ALTER TABLE public.marketing_outreach_message ADD CONSTRAINT marketing_outreach_message_prospect_id_fkey FOREIGN KEY (prospect_id) REFERENCES marketing_prospect(id);
ALTER TABLE public.marketing_plan_review_turn ADD CONSTRAINT marketing_plan_review_turn_month_fkey FOREIGN KEY (month) REFERENCES marketing_month_plan(month);
ALTER TABLE public.marketing_post ADD CONSTRAINT marketing_post_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES marketing_campaign(id);
ALTER TABLE public.marketing_post_channel_result ADD CONSTRAINT marketing_post_channel_result_post_id_fkey FOREIGN KEY (post_id) REFERENCES marketing_post(id) ON DELETE CASCADE;
ALTER TABLE public.marketing_post_metric ADD CONSTRAINT marketing_post_metric_post_id_fkey FOREIGN KEY (post_id) REFERENCES marketing_post(id) ON DELETE CASCADE;
ALTER TABLE public.marketing_post_platform ADD CONSTRAINT marketing_post_platform_post_id_fkey FOREIGN KEY (post_id) REFERENCES marketing_post(id) ON DELETE CASCADE;
ALTER TABLE public.marketing_post_variant ADD CONSTRAINT marketing_post_variant_post_id_fkey FOREIGN KEY (post_id) REFERENCES marketing_post(id) ON DELETE CASCADE;
ALTER TABLE public.marketing_trend ADD CONSTRAINT marketing_trend_source_id_fkey FOREIGN KEY (source_id) REFERENCES marketing_trend_source(id) ON DELETE CASCADE;
ALTER TABLE public.messages ADD CONSTRAINT messages_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL;
ALTER TABLE public.messages ADD CONSTRAINT messages_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id);
ALTER TABLE public.messages ADD CONSTRAINT messages_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id) ON DELETE CASCADE;
ALTER TABLE public.messages ADD CONSTRAINT messages_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id);
ALTER TABLE public.messages ADD CONSTRAINT messages_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES leads(id) ON DELETE CASCADE;
ALTER TABLE public.metric_snapshot ADD CONSTRAINT metric_snapshot_metric_key_fkey FOREIGN KEY (metric_key) REFERENCES metric_definition(metric_key) ON DELETE CASCADE;
ALTER TABLE public.notice_plain_language_cause ADD CONSTRAINT notice_plain_language_cause_owner_seat_fkey FOREIGN KEY (owner_seat) REFERENCES org_role(role_id);
ALTER TABLE public.org_agent_alias ADD CONSTRAINT org_agent_alias_agent_key_fkey FOREIGN KEY (agent_key) REFERENCES org_agents(agent_key);
ALTER TABLE public.org_agents ADD CONSTRAINT org_agents_department_fkey FOREIGN KEY (department) REFERENCES org_departments(dept_key);
ALTER TABLE public.org_authority ADD CONSTRAINT org_authority_dept_key_fkey FOREIGN KEY (dept_key) REFERENCES org_departments(dept_key) ON DELETE CASCADE;
ALTER TABLE public.org_category_identity ADD CONSTRAINT org_category_identity_owner_agent_fkey FOREIGN KEY (owner_agent) REFERENCES org_agents(agent_key);
ALTER TABLE public.org_departments ADD CONSTRAINT org_departments_merged_into_fkey FOREIGN KEY (merged_into) REFERENCES org_departments(dept_key);
ALTER TABLE public.org_reporting_edge ADD CONSTRAINT org_reporting_edge_child_fk FOREIGN KEY (child_role_id) REFERENCES org_role(role_id) ON DELETE CASCADE;
ALTER TABLE public.org_reporting_edge ADD CONSTRAINT org_reporting_edge_parent_fk FOREIGN KEY (parent_role_id) REFERENCES org_role(role_id) ON DELETE RESTRICT;
ALTER TABLE public.org_role ADD CONSTRAINT org_role_manager_role_id_fkey FOREIGN KEY (manager_role_id) REFERENCES org_role(role_id);
ALTER TABLE public.org_role ADD CONSTRAINT org_role_primary_department_id_fkey FOREIGN KEY (primary_department_id) REFERENCES org_departments(dept_key);
ALTER TABLE public.org_role ADD CONSTRAINT org_role_runtime_agent_key_fkey FOREIGN KEY (runtime_agent_key) REFERENCES org_agents(agent_key);
ALTER TABLE public.org_role_alias ADD CONSTRAINT org_role_alias_role_id_fkey FOREIGN KEY (role_id) REFERENCES org_role(role_id) ON DELETE CASCADE;
ALTER TABLE public.org_role_committee ADD CONSTRAINT org_role_committee_committee_key_fkey FOREIGN KEY (committee_key) REFERENCES org_committee(committee_key) ON DELETE CASCADE;
ALTER TABLE public.org_role_committee ADD CONSTRAINT org_role_committee_role_id_fkey FOREIGN KEY (role_id) REFERENCES org_role(role_id) ON DELETE CASCADE;
ALTER TABLE public.org_role_identity ADD CONSTRAINT org_role_identity_agent_key_fkey FOREIGN KEY (agent_key) REFERENCES org_agents(agent_key) ON DELETE CASCADE;
ALTER TABLE public.org_tasks ADD CONSTRAINT org_tasks_assigned_agent_fkey FOREIGN KEY (assigned_agent) REFERENCES org_agents(agent_key);
ALTER TABLE public.org_tasks ADD CONSTRAINT org_tasks_objective_id_fkey FOREIGN KEY (objective_id) REFERENCES department_objective(id) ON DELETE SET NULL;
ALTER TABLE public.org_workflow_ownership ADD CONSTRAINT org_workflow_ownership_accountable_role_id_fkey FOREIGN KEY (accountable_role_id) REFERENCES org_role(role_id);
ALTER TABLE public.org_workflow_step ADD CONSTRAINT org_workflow_step_accountable_role_id_fkey FOREIGN KEY (accountable_role_id) REFERENCES org_role(role_id);
ALTER TABLE public.org_workflow_step ADD CONSTRAINT org_workflow_step_workflow_id_fkey FOREIGN KEY (workflow_id) REFERENCES org_workflow_ownership(workflow_id) ON DELETE CASCADE;
ALTER TABLE public.os_department ADD CONSTRAINT os_department_os_key_fkey FOREIGN KEY (os_key) REFERENCES operating_system(os_key);
ALTER TABLE public.os_interface ADD CONSTRAINT os_interface_os_key_fkey FOREIGN KEY (os_key) REFERENCES operating_system(os_key);
ALTER TABLE public.os_knowledge_domain ADD CONSTRAINT os_knowledge_domain_os_key_fkey FOREIGN KEY (os_key) REFERENCES operating_system(os_key);
ALTER TABLE public.os_objective ADD CONSTRAINT os_objective_os_key_fkey FOREIGN KEY (os_key) REFERENCES operating_system(os_key);
ALTER TABLE public.os_responsibility ADD CONSTRAINT os_responsibility_os_key_fkey FOREIGN KEY (os_key) REFERENCES operating_system(os_key);
ALTER TABLE public.os_review ADD CONSTRAINT os_review_os_key_fkey FOREIGN KEY (os_key) REFERENCES operating_system(os_key);
ALTER TABLE public.os_runbooks ADD CONSTRAINT os_runbooks_os_key_fkey FOREIGN KEY (os_key) REFERENCES operating_system(os_key);
ALTER TABLE public.outcome_record ADD CONSTRAINT outcome_record_expected_kpi_id_fkey FOREIGN KEY (expected_kpi_id) REFERENCES employee_kpi(id);
ALTER TABLE public.paid_route_exception ADD CONSTRAINT paid_route_exception_authority_instruction_id_fkey FOREIGN KEY (authority_instruction_id) REFERENCES founder_instruction(id);
ALTER TABLE public.pdpl_erase_files ADD CONSTRAINT pdpl_erase_files_request_id_fkey FOREIGN KEY (request_id) REFERENCES pdpl_requests(id) ON DELETE CASCADE;
ALTER TABLE public.pdpl_lead_erase_vault ADD CONSTRAINT pdpl_lead_erase_vault_request_id_fkey FOREIGN KEY (request_id) REFERENCES pdpl_requests(id);
ALTER TABLE public.po_lines ADD CONSTRAINT po_lines_account_code_fkey FOREIGN KEY (account_code) REFERENCES gl_accounts(code);
ALTER TABLE public.po_lines ADD CONSTRAINT po_lines_item_id_fkey FOREIGN KEY (item_id) REFERENCES inv_items(id);
ALTER TABLE public.po_lines ADD CONSTRAINT po_lines_po_id_fkey FOREIGN KEY (po_id) REFERENCES po_orders(id) ON DELETE CASCADE;
ALTER TABLE public.po_orders ADD CONSTRAINT po_orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE public.po_orders ADD CONSTRAINT po_orders_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id);
ALTER TABLE public.po_orders ADD CONSTRAINT po_orders_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id);
ALTER TABLE public.po_orders ADD CONSTRAINT po_orders_quote_id_fkey FOREIGN KEY (quote_id) REFERENCES quotes(id);
ALTER TABLE public.po_orders ADD CONSTRAINT po_orders_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES po_vendors(id);
ALTER TABLE public.post_reveal_dispute ADD CONSTRAINT post_reveal_dispute_transaction_id_fkey FOREIGN KEY (transaction_id) REFERENCES transactions(id);
ALTER TABLE public.projects ADD CONSTRAINT projects_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE;
ALTER TABLE public.prompt_versions ADD CONSTRAINT prompt_versions_prompt_key_fkey FOREIGN KEY (prompt_key) REFERENCES prompts(key);
ALTER TABLE public.questions ADD CONSTRAINT questions_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL;
ALTER TABLE public.questions ADD CONSTRAINT questions_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id) ON DELETE CASCADE;
ALTER TABLE public.questions ADD CONSTRAINT questions_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES leads(id) ON DELETE CASCADE;
ALTER TABLE public.quote_aspect_reading ADD CONSTRAINT quote_aspect_reading_quote_id_fkey FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE CASCADE;
ALTER TABLE public.quote_committed_items ADD CONSTRAINT quote_committed_items_review_id_fkey FOREIGN KEY (review_id) REFERENCES quote_reviews(id) ON DELETE CASCADE;
ALTER TABLE public.quote_quality_hold ADD CONSTRAINT quote_quality_hold_quote_id_fkey FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE public.quote_review_messages ADD CONSTRAINT quote_review_messages_review_id_fkey FOREIGN KEY (review_id) REFERENCES quote_reviews(id) ON DELETE CASCADE;
ALTER TABLE public.quote_review_request ADD CONSTRAINT quote_review_request_answered_message_id_fkey FOREIGN KEY (answered_message_id) REFERENCES quote_review_messages(id) ON DELETE SET NULL;
ALTER TABLE public.quote_review_request ADD CONSTRAINT quote_review_request_asked_message_id_fkey FOREIGN KEY (asked_message_id) REFERENCES quote_review_messages(id) ON DELETE SET NULL;
ALTER TABLE public.quote_review_request ADD CONSTRAINT quote_review_request_review_id_fkey FOREIGN KEY (review_id) REFERENCES quote_reviews(id) ON DELETE CASCADE;
ALTER TABLE public.quote_reviews ADD CONSTRAINT quote_reviews_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id);
ALTER TABLE public.quote_reviews ADD CONSTRAINT quote_reviews_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES leads(id);
ALTER TABLE public.quote_spec_hold ADD CONSTRAINT quote_spec_hold_quote_id_fkey FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE CASCADE;
ALTER TABLE public.quotes ADD CONSTRAINT quotes_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id) ON DELETE CASCADE;
ALTER TABLE public.quotes ADD CONSTRAINT quotes_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES leads(id);
ALTER TABLE public.reasoning_held_question ADD CONSTRAINT reasoning_held_question_seat_fkey FOREIGN KEY (seat) REFERENCES org_role(role_id);
ALTER TABLE public.reasoning_knowledge_candidate ADD CONSTRAINT reasoning_knowledge_candidate_seat_fkey FOREIGN KEY (seat) REFERENCES org_role(role_id);
ALTER TABLE public.refund_case ADD CONSTRAINT refund_case_case_id_fkey FOREIGN KEY (case_id) REFERENCES support_case(case_id);
ALTER TABLE public.refunds ADD CONSTRAINT refunds_refund_decision_id_fkey FOREIGN KEY (refund_decision_id) REFERENCES ceo_approval(decision_id);
ALTER TABLE public.refunds ADD CONSTRAINT refunds_topup_of_fkey FOREIGN KEY (topup_of) REFERENCES refunds(id);
ALTER TABLE public.refunds ADD CONSTRAINT refunds_transaction_id_fkey FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE SET NULL;
ALTER TABLE public.regulations ADD CONSTRAINT regulations_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES regulations(id);
ALTER TABLE public.resilience_step ADD CONSTRAINT resilience_step_owner_seat_fk FOREIGN KEY (owner_seat) REFERENCES org_agents(agent_key);
ALTER TABLE public.resource_pool ADD CONSTRAINT resource_pool_os_key_fkey FOREIGN KEY (os_key) REFERENCES operating_system(os_key);
ALTER TABLE public.reveal_invoices ADD CONSTRAINT reveal_invoices_transaction_id_fkey FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE CASCADE;
ALTER TABLE public.review_pool ADD CONSTRAINT review_pool_model_id_fkey FOREIGN KEY (model_id) REFERENCES model_registry(model_id);
ALTER TABLE public.review_route ADD CONSTRAINT review_route_owner_seat_fkey FOREIGN KEY (owner_seat) REFERENCES org_role(role_id);
ALTER TABLE public.reviews ADD CONSTRAINT reviews_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE public.reviews ADD CONSTRAINT reviews_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id);
ALTER TABLE public.reviews ADD CONSTRAINT reviews_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES leads(id);
ALTER TABLE public.reviews ADD CONSTRAINT reviews_transaction_id_fkey FOREIGN KEY (transaction_id) REFERENCES transactions(id);
ALTER TABLE public.rfq_clarification ADD CONSTRAINT rfq_clarification_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id) ON DELETE CASCADE;
ALTER TABLE public.sales_engineer_comparison_report ADD CONSTRAINT sales_engineer_comparison_report_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id) ON DELETE CASCADE;
ALTER TABLE public.sales_engineer_negotiation_round ADD CONSTRAINT sales_engineer_negotiation_round_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id) ON DELETE CASCADE;
ALTER TABLE public.sales_engineer_negotiation_round ADD CONSTRAINT sales_engineer_negotiation_round_quote_id_fkey FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE CASCADE;
ALTER TABLE public.sales_knowledge_gap ADD CONSTRAINT sales_knowledge_gap_task_id_fkey FOREIGN KEY (task_id) REFERENCES org_tasks(id);
ALTER TABLE public.sales_qualification_field ADD CONSTRAINT sales_qualification_field_sector_id_fkey FOREIGN KEY (sector_id) REFERENCES sales_sector(sector_id) ON DELETE CASCADE;
ALTER TABLE public.sanctions_ban ADD CONSTRAINT sanctions_ban_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id);
ALTER TABLE public.screening_entry ADD CONSTRAINT screening_entry_run_id_fkey FOREIGN KEY (run_id) REFERENCES screening_run(id) ON DELETE CASCADE;
ALTER TABLE public.seat_deliberation_turn ADD CONSTRAINT seat_deliberation_turn_deliberation_id_fkey FOREIGN KEY (deliberation_id) REFERENCES seat_deliberation(id) ON DELETE CASCADE;
ALTER TABLE public.seat_deliberation_turn ADD CONSTRAINT seat_deliberation_turn_reviews_turn_id_fkey FOREIGN KEY (reviews_turn_id) REFERENCES seat_deliberation_turn(id);
ALTER TABLE public.seat_duty ADD CONSTRAINT seat_duty_owner_seat_fkey FOREIGN KEY (owner_seat) REFERENCES org_role(role_id);
ALTER TABLE public.seat_duty_skip ADD CONSTRAINT seat_duty_skip_duty_fkey FOREIGN KEY (duty) REFERENCES seat_duty(duty) ON DELETE CASCADE;
ALTER TABLE public.seat_exam_asked ADD CONSTRAINT seat_exam_asked_fix_id_fkey FOREIGN KEY (fix_id) REFERENCES seat_exam_fix(id);
ALTER TABLE public.seat_exam_item ADD CONSTRAINT seat_exam_item_seat_fkey FOREIGN KEY (seat) REFERENCES org_role(role_id);
ALTER TABLE public.seat_knowledge_exam ADD CONSTRAINT seat_knowledge_exam_seat_fkey FOREIGN KEY (seat) REFERENCES org_role(role_id);
ALTER TABLE public.seat_knowledge_refresh ADD CONSTRAINT seat_knowledge_refresh_seat_fkey FOREIGN KEY (seat) REFERENCES org_role(role_id);
ALTER TABLE public.seat_knowledge_stale ADD CONSTRAINT seat_knowledge_stale_seat_fkey FOREIGN KEY (seat) REFERENCES org_role(role_id);
ALTER TABLE public.seat_lesson_cluster ADD CONSTRAINT seat_lesson_cluster_candidate_id_fkey FOREIGN KEY (candidate_id) REFERENCES reasoning_knowledge_candidate(id);
ALTER TABLE public.seat_self_review ADD CONSTRAINT seat_self_review_seat_fkey FOREIGN KEY (seat) REFERENCES org_role(role_id);
ALTER TABLE public.seat_senior_contribution ADD CONSTRAINT seat_senior_contribution_seat_fkey FOREIGN KEY (seat) REFERENCES org_role(role_id);
ALTER TABLE public.seat_senior_exam ADD CONSTRAINT seat_senior_exam_seat_fkey FOREIGN KEY (seat) REFERENCES org_role(role_id);
ALTER TABLE public.seat_senior_verdict ADD CONSTRAINT seat_senior_verdict_seat_fkey FOREIGN KEY (seat) REFERENCES org_role(role_id);
ALTER TABLE public.service_implication ADD CONSTRAINT service_implication_implies_trade_implies_code_fkey FOREIGN KEY (implies_trade, implies_code) REFERENCES taxonomy_trade_service(trade_code, code) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE public.signup_purge_dropbox ADD CONSTRAINT signup_purge_dropbox_purge_id_fkey FOREIGN KEY (purge_id) REFERENCES signup_purge(id) ON DELETE CASCADE;
ALTER TABLE public.signup_purge_object ADD CONSTRAINT signup_purge_object_purge_id_fkey FOREIGN KEY (purge_id) REFERENCES signup_purge(id) ON DELETE CASCADE;
ALTER TABLE public.social_message ADD CONSTRAINT social_message_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES social_conversation(id);
ALTER TABLE public.social_message ADD CONSTRAINT social_message_in_reply_to_fkey FOREIGN KEY (in_reply_to) REFERENCES social_message(id);
ALTER TABLE public.spec_alternative_offer ADD CONSTRAINT spec_alternative_offer_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL;
ALTER TABLE public.spec_alternative_offer ADD CONSTRAINT spec_alternative_offer_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id) ON DELETE CASCADE;
ALTER TABLE public.stalled_inquiry_rescue ADD CONSTRAINT stalled_inquiry_rescue_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id) ON DELETE CASCADE;
ALTER TABLE public.stripe_dispute ADD CONSTRAINT stripe_dispute_transaction_id_fkey FOREIGN KEY (transaction_id) REFERENCES transactions(id);
ALTER TABLE public.stripe_payout ADD CONSTRAINT stripe_payout_bank_line_fk FOREIGN KEY (bank_line_id) REFERENCES bank_statement_line(id);
ALTER TABLE public.subcategory_agent_map ADD CONSTRAINT subcategory_agent_map_sub_slug_fkey FOREIGN KEY (sub_slug) REFERENCES catalog_subcategories(slug) ON DELETE CASCADE;
ALTER TABLE public.supplier_availability ADD CONSTRAINT supplier_availability_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES leads(id) ON DELETE CASCADE;
ALTER TABLE public.supplier_beneficial_owner ADD CONSTRAINT supplier_beneficial_owner_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id);
ALTER TABLE public.supplier_capabilities ADD CONSTRAINT supplier_capabilities_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES leads(id) ON DELETE CASCADE;
ALTER TABLE public.supplier_capability_reading ADD CONSTRAINT supplier_capability_reading_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id) ON DELETE CASCADE;
ALTER TABLE public.supplier_catalog ADD CONSTRAINT supplier_catalog_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES leads(id);
ALTER TABLE public.supplier_collaboration ADD CONSTRAINT supplier_collaboration_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id) ON DELETE CASCADE;
ALTER TABLE public.supplier_collaboration_event ADD CONSTRAINT supplier_collaboration_event_founder_instruction_id_fkey FOREIGN KEY (founder_instruction_id) REFERENCES founder_instruction(id);
ALTER TABLE public.supplier_due_checkouts ADD CONSTRAINT supplier_due_checkouts_due_id_fkey FOREIGN KEY (due_id) REFERENCES supplier_dues(id);
ALTER TABLE public.supplier_due_payments ADD CONSTRAINT supplier_due_payments_due_id_fkey FOREIGN KEY (due_id) REFERENCES supplier_dues(id);
ALTER TABLE public.supplier_lead_intake ADD CONSTRAINT supplier_lead_intake_inbound_id_fkey FOREIGN KEY (inbound_id) REFERENCES inbound_messages(id) ON DELETE CASCADE;
ALTER TABLE public.supplier_lead_intake ADD CONSTRAINT supplier_lead_intake_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id) ON DELETE SET NULL;
ALTER TABLE public.supplier_onboarding ADD CONSTRAINT supplier_onboarding_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id) ON DELETE CASCADE;
ALTER TABLE public.supplier_opportunity_score ADD CONSTRAINT supplier_opportunity_score_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id);
ALTER TABLE public.supplier_opportunity_score ADD CONSTRAINT supplier_opportunity_score_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES leads(id);
ALTER TABLE public.supplier_own_word_reading ADD CONSTRAINT supplier_own_word_reading_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES leads(id) ON DELETE CASCADE;
ALTER TABLE public.supplier_performance ADD CONSTRAINT supplier_performance_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id) ON DELETE CASCADE;
ALTER TABLE public.supplier_product ADD CONSTRAINT supplier_product_catalog_id_fkey FOREIGN KEY (catalog_id) REFERENCES supplier_catalog(id);
ALTER TABLE public.supplier_product ADD CONSTRAINT supplier_product_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES leads(id);
ALTER TABLE public.supplier_product_variant ADD CONSTRAINT supplier_product_variant_product_id_fkey FOREIGN KEY (product_id) REFERENCES supplier_product(id) ON DELETE CASCADE;
ALTER TABLE public.supplier_public_name ADD CONSTRAINT supplier_public_name_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id) ON DELETE CASCADE;
ALTER TABLE public.supplier_quote_template ADD CONSTRAINT supplier_quote_template_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES leads(id) ON DELETE CASCADE;
ALTER TABLE public.supplier_reply_followup ADD CONSTRAINT supplier_reply_followup_inbound_message_id_fkey FOREIGN KEY (inbound_message_id) REFERENCES inbound_messages(id);
ALTER TABLE public.supplier_scorecard ADD CONSTRAINT supplier_scorecard_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id) ON DELETE CASCADE;
ALTER TABLE public.supplier_screening_hit ADD CONSTRAINT supplier_screening_hit_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id) ON DELETE CASCADE;
ALTER TABLE public.supplier_screening_hit ADD CONSTRAINT supplier_screening_hit_run_id_fkey FOREIGN KEY (run_id) REFERENCES screening_run(id) ON DELETE SET NULL;
ALTER TABLE public.supplier_whatsapp_optin ADD CONSTRAINT supplier_whatsapp_optin_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id) ON DELETE CASCADE;
ALTER TABLE public.supply_gap ADD CONSTRAINT supply_gap_brief_id_fkey FOREIGN KEY (brief_id) REFERENCES supply_recruitment_brief(id);
ALTER TABLE public.support_case ADD CONSTRAINT support_case_category_fkey FOREIGN KEY (category) REFERENCES support_category(category);
ALTER TABLE public.support_case ADD CONSTRAINT support_case_customer_profile_id_fkey FOREIGN KEY (customer_profile_id) REFERENCES support_customer_profile(id);
ALTER TABLE public.support_case ADD CONSTRAINT support_case_recovery_of_case_id_fkey FOREIGN KEY (recovery_of_case_id) REFERENCES support_case(case_id);
ALTER TABLE public.support_customer_profile ADD CONSTRAINT support_customer_profile_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL;
ALTER TABLE public.support_customer_profile ADD CONSTRAINT support_customer_profile_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id) ON DELETE SET NULL;
ALTER TABLE public.support_document_intake ADD CONSTRAINT support_document_intake_case_id_fkey FOREIGN KEY (case_id) REFERENCES support_case(case_id);
ALTER TABLE public.support_document_intake ADD CONSTRAINT support_document_intake_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id);
ALTER TABLE public.support_identity_challenge ADD CONSTRAINT support_identity_challenge_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id);
ALTER TABLE public.support_notification ADD CONSTRAINT support_notification_case_id_fkey FOREIGN KEY (case_id) REFERENCES support_case(case_id);
ALTER TABLE public.support_root_cause ADD CONSTRAINT support_root_cause_category_fkey FOREIGN KEY (category) REFERENCES support_category(category);
ALTER TABLE public.support_root_cause_fix ADD CONSTRAINT support_root_cause_fix_root_cause_id_fkey FOREIGN KEY (root_cause_id) REFERENCES support_root_cause(id);
ALTER TABLE public.support_signal_category ADD CONSTRAINT support_signal_category_category_fkey FOREIGN KEY (category) REFERENCES support_category(category);
ALTER TABLE public.target_contract ADD CONSTRAINT target_contract_accountable_owner_fkey FOREIGN KEY (accountable_owner) REFERENCES org_agents(agent_key);
ALTER TABLE public.target_contract ADD CONSTRAINT target_contract_goal_key_fkey FOREIGN KEY (goal_key) REFERENCES company_goals(key);
ALTER TABLE public.target_contract ADD CONSTRAINT target_contract_metric_key_fkey FOREIGN KEY (metric_key) REFERENCES metric_definition(metric_key);
ALTER TABLE public.target_contract ADD CONSTRAINT target_contract_superseded_by_fkey FOREIGN KEY (superseded_by) REFERENCES target_contract(id);
ALTER TABLE public.target_daily_verdict ADD CONSTRAINT target_daily_verdict_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES target_contract(id) ON DELETE CASCADE;
ALTER TABLE public.target_driver ADD CONSTRAINT target_driver_channel_key_fkey FOREIGN KEY (channel_key) REFERENCES outreach_channel_policy(channel_key);
ALTER TABLE public.target_driver ADD CONSTRAINT target_driver_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES target_contract(id) ON DELETE CASCADE;
ALTER TABLE public.target_driver ADD CONSTRAINT target_driver_owner_seat_fkey FOREIGN KEY (owner_seat) REFERENCES org_role(role_id);
ALTER TABLE public.target_path ADD CONSTRAINT target_path_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES target_contract(id) ON DELETE CASCADE;
ALTER TABLE public.target_path ADD CONSTRAINT target_path_owner_seat_fkey FOREIGN KEY (owner_seat) REFERENCES org_role(role_id);
ALTER TABLE public.target_verdict ADD CONSTRAINT target_verdict_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES target_contract(id) ON DELETE CASCADE;
ALTER TABLE public.taxonomy_trade ADD CONSTRAINT taxonomy_trade_group_code_fkey FOREIGN KEY (group_code) REFERENCES taxonomy_trade_group(code) ON UPDATE CASCADE;
ALTER TABLE public.taxonomy_trade ADD CONSTRAINT taxonomy_trade_umbrella_code_fkey FOREIGN KEY (umbrella_code) REFERENCES taxonomy_trade(code) ON UPDATE CASCADE;
ALTER TABLE public.taxonomy_trade_code ADD CONSTRAINT taxonomy_trade_code_trade_code_fkey FOREIGN KEY (trade_code) REFERENCES taxonomy_trade(code) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE public.taxonomy_trade_proposal ADD CONSTRAINT taxonomy_trade_proposal_mapped_to_fkey FOREIGN KEY (mapped_to) REFERENCES taxonomy_trade(code);
ALTER TABLE public.taxonomy_trade_proposal ADD CONSTRAINT taxonomy_trade_proposal_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES leads(id) ON DELETE CASCADE;
ALTER TABLE public.taxonomy_trade_service ADD CONSTRAINT taxonomy_trade_service_trade_code_fkey FOREIGN KEY (trade_code) REFERENCES taxonomy_trade(code) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE public.transactions ADD CONSTRAINT transactions_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE public.transactions ADD CONSTRAINT transactions_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id);
ALTER TABLE public.transactions ADD CONSTRAINT transactions_quote_id_fkey FOREIGN KEY (quote_id) REFERENCES quotes(id);
ALTER TABLE public.transactions ADD CONSTRAINT transactions_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES leads(id);
ALTER TABLE public.user_roles ADD CONSTRAINT user_roles_role_fkey FOREIGN KEY (role) REFERENCES roles(name);
ALTER TABLE public.wa_answer_log ADD CONSTRAINT wa_answer_log_intent_key_fkey FOREIGN KEY (intent_key) REFERENCES wa_reply_intent(intent_key);
ALTER TABLE public.wa_document_intake ADD CONSTRAINT wa_document_intake_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id);
ALTER TABLE public.wa_document_intake ADD CONSTRAINT wa_document_intake_turn_id_fkey FOREIGN KEY (turn_id) REFERENCES wa_turn(id);
ALTER TABLE public.wa_turn ADD CONSTRAINT wa_turn_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES wa_conversation(id) ON DELETE CASCADE;
ALTER TABLE public.workflow ADD CONSTRAINT workflow_os_key_fkey FOREIGN KEY (os_key) REFERENCES operating_system(os_key);
ALTER TABLE public.workflow_run ADD CONSTRAINT workflow_run_trigger_event_id_fkey FOREIGN KEY (trigger_event_id) REFERENCES company_event(id);
ALTER TABLE public.workflow_run ADD CONSTRAINT workflow_run_workflow_key_fkey FOREIGN KEY (workflow_key) REFERENCES workflow(workflow_key);
ALTER TABLE public.workflow_step ADD CONSTRAINT workflow_step_workflow_key_fkey FOREIGN KEY (workflow_key) REFERENCES workflow(workflow_key) ON DELETE CASCADE;
ALTER TABLE public.workflow_step_run ADD CONSTRAINT workflow_step_run_workflow_run_id_fkey FOREIGN KEY (workflow_run_id) REFERENCES workflow_run(id) ON DELETE CASCADE;
ALTER TABLE public.writer_seat ADD CONSTRAINT writer_seat_owner_seat_fkey FOREIGN KEY (owner_seat) REFERENCES org_role(role_id);

-- ===== INDEXES =====
CREATE INDEX accountant_knowledge_emb_hnsw ON public.accountant_knowledge USING hnsw (embedding_gte vector_cosine_ops);
CREATE INDEX accountant_knowledge_epi_idx ON public.accountant_knowledge USING btree (epistemic_status);
CREATE INDEX accountant_knowledge_search_idx ON public.accountant_knowledge USING gin (search);
CREATE INDEX accountant_knowledge_type_idx ON public.accountant_knowledge USING btree (record_type);
CREATE INDEX accountant_weekly_report_undelivered_idx ON public.accountant_weekly_report USING btree (week_start DESC) WHERE (delivered_at IS NULL);
CREATE INDEX accountant_weekly_report_week_idx ON public.accountant_weekly_report USING btree (week_start DESC);
CREATE INDEX acl_cheaper_idx ON public.ai_cost_log USING btree (could_be_cheaper) WHERE could_be_cheaper;
CREATE INDEX acl_dept_idx ON public.ai_cost_log USING btree (dept_key, occurred_at DESC);
CREATE INDEX ad_decision_campaign_idx ON public.ad_decision USING btree (campaign_id);
CREATE INDEX ad_decision_unexecuted_idx ON public.ad_decision USING btree (id) WHERE (executed_at IS NULL);
CREATE UNIQUE INDEX agent_actions_dedupe ON public.agent_actions USING btree (agent, kind, target_id) WHERE (status = 'pending'::text);
CREATE INDEX agent_actions_handoff_target_idx ON public.agent_actions USING btree (agent, kind, target_id);
CREATE INDEX agent_actions_kind_type_from_idx ON public.agent_actions USING btree (kind, ((detail ->> 'type'::text)), ((detail ->> 'from'::text)));
CREATE UNIQUE INDEX agent_actions_one_pending_vision_confirm ON public.agent_actions USING btree (target_id) WHERE ((kind = 'vision_trades_confirm'::text) AND (status = 'pending'::text));
CREATE INDEX agent_actions_open_delivery_request_idx ON public.agent_actions USING btree (id) WHERE ((kind = 'handoff'::text) AND (agent = 'customer_support'::text) AND ((detail ->> 'type'::text) = 'delivery.request'::text) AND ((detail ->> 'result_handoff_id'::text) IS NULL));
CREATE INDEX agent_actions_status_idx ON public.agent_actions USING btree (status, created_at DESC);
CREATE INDEX agent_chats_agent_idx ON public.agent_chats USING btree (agent_key, id);
CREATE INDEX agent_context_retrieval_agent ON public.agent_context_retrieval USING btree (agent_key, created_at DESC);
CREATE UNIQUE INDEX agent_knowledge_cat_topic_uidx ON public.agent_knowledge USING btree (agent_key, topic) WHERE (agent_key ~~ 'cat:%'::text);
CREATE INDEX agent_knowledge_review_due_idx ON public.agent_knowledge USING btree (review_due) WHERE (validation_status <> 'quarantined'::text);
CREATE INDEX agent_knowledge_search_idx ON public.agent_knowledge USING gin (search);
CREATE INDEX agent_remediation_open ON public.agent_remediation USING btree (agent_key) WHERE (status <> 'passed'::text);
CREATE INDEX agent_runs_agent_started_idx ON public.agent_runs USING btree (agent, started_at DESC);
CREATE INDEX agent_tool_call_agent_idx ON public.agent_tool_call USING btree (agent_key, created_at DESC);
CREATE INDEX agent_tool_call_corr_idx ON public.agent_tool_call USING btree (correlation_id);
CREATE INDEX agent_tool_call_tool_idx ON public.agent_tool_call USING btree (tool_id, created_at DESC);
CREATE INDEX agent_training_attempt_agent ON public.agent_training_attempt USING btree (agent_key, created_at DESC);
CREATE UNIQUE INDEX agent_training_attempt_unseen ON public.agent_training_attempt USING btree (agent_key, case_id, purpose);
CREATE INDEX agent_training_case_family ON public.agent_training_case USING btree (case_family);
CREATE INDEX agent_training_case_run ON public.agent_training_case USING btree (ingestion_run_id);
CREATE INDEX agent_training_case_scope ON public.agent_training_case USING btree (scope_type, scope_key, case_family);
CREATE INDEX ai_cost_log_confidence_prior_idx ON public.ai_cost_log USING btree (agent_key, task_class, occurred_at DESC) WHERE (confidence IS NOT NULL);
CREATE INDEX ai_cost_log_dubai_day_idx ON public.ai_cost_log USING btree ((((occurred_at AT TIME ZONE 'Asia/Dubai'::text))::date));
CREATE INDEX ai_cost_log_e2e_run_tag_idx ON public.ai_cost_log USING btree (e2e_run_tag) WHERE (e2e_run_tag IS NOT NULL);
CREATE UNIQUE INDEX ai_cost_log_generation_id_uidx ON public.ai_cost_log USING btree (generation_id) WHERE (generation_id IS NOT NULL);
CREATE INDEX ai_cost_log_prompt_hash_idx ON public.ai_cost_log USING btree (prompt_hash, occurred_at) WHERE (prompt_hash IS NOT NULL);
CREATE UNIQUE INDEX ai_trainer_snap_day ON public.ai_trainer_snapshots USING btree (snapshot_date);
CREATE INDEX ai_usage_email_time_idx ON public.ai_usage USING btree (email, created_at);
CREATE UNIQUE INDEX ap_bills_vendor_billno_uidx ON public.ap_bills USING btree (vendor_id, bill_no) WHERE ((bill_no IS NOT NULL) AND (status <> 'void'::text));
CREATE INDEX arabic_outbound_hold_held_idx ON public.arabic_outbound_hold USING btree (created_at) WHERE (status = 'held'::text);
CREATE UNIQUE INDEX artifact_review_bytes ON public.artifact_review USING btree (subject_type, subject_id, artifact_sha256, revision);
CREATE INDEX artifact_review_subject ON public.artifact_review USING btree (subject_type, subject_id, created_at DESC);
CREATE INDEX assistant_logs_conv_id_id ON public.assistant_logs USING btree (conv_id, id) WHERE (conv_id IS NOT NULL);
CREATE INDEX assistant_logs_e2e_run_tag_idx ON public.assistant_logs USING btree (e2e_run_tag) WHERE (e2e_run_tag IS NOT NULL);
CREATE UNIQUE INDEX backup_prune_log_open_uidx ON public.backup_prune_log USING btree (day) WHERE ((mode = 'delete'::text) AND (storage_deleted_at IS NULL) AND (cancelled_at IS NULL));
CREATE UNIQUE INDEX backup_prune_log_pass_uidx ON public.backup_prune_log USING btree (decided_for, day, mode);
CREATE INDEX bank_statement_line_match_idx ON public.bank_statement_line USING btree (account, amount_aed, value_date);
CREATE INDEX boq_fixture_run_recent_idx ON public.boq_fixture_run USING btree (fixture_id, ran_at DESC);
CREATE UNIQUE INDEX brand_assets_filename_key ON public.brand_assets USING btree (filename);
CREATE INDEX cad_read_jobs_customer ON public.cad_read_jobs USING btree (customer_id, created_at DESC);
CREATE INDEX cad_read_jobs_open ON public.cad_read_jobs USING btree (created_at) WHERE (status = ANY (ARRAY['queued'::text, 'running'::text]));
CREATE INDEX category_keyword_slug_idx ON public.category_keyword USING btree (slug);
CREATE UNIQUE INDEX category_keyword_uidx ON public.category_keyword USING btree (slug, pattern);
CREATE INDEX ce_type_idx ON public.company_event USING btree (event_type, occurred_at DESC);
CREATE INDEX ceo_approval_subject_idx ON public.ceo_approval USING btree (subject_kind, subject_id);
CREATE INDEX ceo_command_state_idx ON public.ceo_command USING btree (state, received_at DESC);
CREATE UNIQUE INDEX ceo_company_stage_log_one_current ON public.ceo_company_stage_log USING btree ((true)) WHERE (left_at IS NULL);
CREATE INDEX ceo_daily_digest_local_date_idx ON public.ceo_daily_digest USING btree (local_date DESC);
CREATE INDEX ceo_daily_digest_undelivered_idx ON public.ceo_daily_digest USING btree (local_date DESC) WHERE (delivered_at IS NULL);
CREATE UNIQUE INDEX ceo_decision_log_dedupe_uidx ON public.ceo_decision_log USING btree (dedupe_key) WHERE (dedupe_key IS NOT NULL);
CREATE INDEX ceo_decision_round_by_item ON public.ceo_decision_round USING btree (item_key, generation DESC, round DESC);
CREATE UNIQUE INDEX ceo_decision_round_one_per_source ON public.ceo_decision_round USING btree (item_key, source_table, source_id) WHERE (source_id IS NOT NULL);
CREATE UNIQUE INDEX ceo_directive_one_live_per_signal ON public.ceo_directive USING btree (seat, source_kind, source_ref) WHERE (status = 'open'::text);
CREATE INDEX ceo_growth_action_due ON public.ceo_growth_action USING btree (review_on) WHERE (verdict = 'pending'::text);
CREATE UNIQUE INDEX ceo_improvement_one_open_per_metric ON public.ceo_improvement USING btree (((evidence ->> 'metric'::text))) WHERE ((source_kind = 'recurring_miss'::text) AND (status = ANY (ARRAY['open'::text, 'assigned'::text])));
CREATE UNIQUE INDEX ceo_improvement_one_open_weekly_per_target ON public.ceo_improvement USING btree (seat, ((evidence ->> 'target'::text))) WHERE ((source_kind = 'weekly_review'::text) AND (status = ANY (ARRAY['open'::text, 'assigned'::text])));
CREATE UNIQUE INDEX ceo_invite_trade_priority_one_live ON public.ceo_invite_trade_priority USING btree (trade) WHERE (cleared_at IS NULL);
CREATE INDEX ceo_knowledge_emb_hnsw ON public.ceo_knowledge USING hnsw (embedding_gte vector_cosine_ops);
CREATE INDEX ceo_knowledge_kind_idx ON public.ceo_knowledge USING btree (record_kind, domain);
CREATE INDEX ceo_knowledge_search_idx ON public.ceo_knowledge USING gin (search);
CREATE INDEX ceo_task_open_idx ON public.ceo_task USING btree (state, created_at) WHERE (state = ANY (ARRAY['open'::text, 'working'::text, 'blocked'::text]));
CREATE INDEX channel_directive_actor_idx ON public.channel_directive USING btree (actor_type, actor_id, created_at DESC);
CREATE UNIQUE INDEX company_charter_one_active ON public.company_charter USING btree (active) WHERE active;
CREATE INDEX company_faq_embed_inflight_faq_idx ON public.company_faq_embed_inflight USING btree (faq_id);
CREATE INDEX company_review_ask_by_customer ON public.company_review_ask USING btree (customer_id);
CREATE UNIQUE INDEX company_review_ask_one_per_job ON public.company_review_ask USING btree (transaction_id);
CREATE INDEX competitor_scan_latest ON public.competitor_scan USING btree (competitor_id, page_kind, requested_at DESC);
CREATE INDEX complaint_tickets_open_idx ON public.complaint_tickets USING btree (respond_due) WHERE (status <> 'final_response'::text);
CREATE INDEX content_drafts_status_idx ON public.content_drafts USING btree (status, id DESC);
CREATE INDEX control_mode_active_idx ON public.control_mode_session USING btree (actor_email, expires_at DESC) WHERE (closed_at IS NULL);
CREATE INDEX control_mode_audit_idx ON public.control_mode_audit USING btree (at DESC, actor_email);
CREATE INDEX control_mode_challenge_open_idx ON public.control_mode_challenge USING btree (admin_email, consumed_at, expires_at);
CREATE UNIQUE INDEX control_mode_identity_one_active_per_phone ON public.control_mode_identity USING btree (phone_secret_key) WHERE active;
CREATE INDEX cpo_cust_idx ON public.customer_phone_otps USING btree (customer_id, created_at DESC);
CREATE INDEX customer_calls_customer_idx ON public.customer_calls USING btree (customer_id, started_at DESC);
CREATE INDEX customer_calls_inquiry_idx ON public.customer_calls USING btree (inquiry_id);
CREATE UNIQUE INDEX customer_kpi_snap_day ON public.customer_kpi_snapshots USING btree (snapshot_date);
CREATE UNIQUE INDEX customer_support_data_request_one_open ON public.customer_support_data_request USING btree (lower(email), kind) WHERE (status = 'open'::text);
CREATE UNIQUE INDEX customer_support_data_request_pdpl ON public.customer_support_data_request USING btree (pdpl_request_id) WHERE (pdpl_request_id IS NOT NULL);
CREATE INDEX customer_support_voice_owed_due ON public.customer_support_voice_owed USING btree (created_at) WHERE (written_at IS NULL);
CREATE UNIQUE INDEX customers_email_lower_uidx ON public.customers USING btree (lower(btrim(email))) WHERE ((email IS NOT NULL) AND (btrim(email) <> ''::text));
CREATE INDEX dead_letter_open_idx ON public.dead_letter USING btree (source, created_at DESC) WHERE (resolved_at IS NULL);
CREATE INDEX decision_review_request_open_idx ON public.decision_review_request USING btree (owner_seat) WHERE (status = 'open'::text);
CREATE INDEX deliverability_test_recorded_idx ON public.deliverability_test USING btree (tested_at DESC) WHERE (class_rates IS NOT NULL);
CREATE INDEX demand_search_at_idx ON public.demand_search USING btree (searched_at);
CREATE INDEX department_objective_goal_idx ON public.department_objective USING btree (goal_key);
CREATE INDEX doc_backups_gen_kind_ref_idx ON public.doc_backups USING btree (gen_kind, gen_ref);
CREATE INDEX doc_reviews_status_idx ON public.doc_reviews USING btree (status, created_at DESC);
CREATE UNIQUE INDEX document_kpi_snap_day ON public.document_kpi_snapshots USING btree (snapshot_date);
CREATE INDEX documents_drainable_idx ON public.documents USING btree (id) WHERE (status = ANY (ARRAY['pending'::text, 'error'::text]));
CREATE INDEX drawing_redaction_runs_caller_ref_idx ON public.drawing_redaction_runs USING btree (caller_ref text_pattern_ops);
CREATE INDEX drawing_redaction_runs_customer_idx ON public.drawing_redaction_runs USING btree (customer_id, created_at DESC);
CREATE INDEX drawing_redaction_runs_outputs_idx ON public.drawing_redaction_runs USING gin (output_paths);
CREATE INDEX dropbox_files_path ON public.dropbox_files USING btree (path);
CREATE INDEX ea_events_start ON public.ea_events USING btree (starts_at);
CREATE INDEX ea_reminders_at ON public.ea_reminders USING btree (remind_at) WHERE (NOT done);
CREATE INDEX edge_health_probe_checked_at_idx ON public.edge_health_probe USING btree (checked_at);
CREATE INDEX edge_health_probe_fn_idx ON public.edge_health_probe USING btree (fn_key, checked_at DESC);
CREATE INDEX email_domain_mx_undeliverable_idx ON public.email_domain_mx USING btree (domain) WHERE (has_mx = false);
CREATE INDEX email_verifications_lookup_idx ON public.email_verifications USING btree (email, purpose, used_at, created_at DESC);
CREATE INDEX employee_kpi_history_agent_idx ON public.employee_kpi_history USING btree (agent_key, measured_on DESC);
CREATE UNIQUE INDEX employee_kpi_history_one_per_day ON public.employee_kpi_history USING btree (kpi_id, measured_on);
CREATE INDEX event_delivery_agent_idx ON public.event_delivery USING btree (agent_key, delivered_at DESC);
CREATE UNIQUE INDEX evolution_proposal_dedupe_idx ON public.evolution_proposal USING btree (trigger_kind, subject, change_class) WHERE (status = 'proposed'::text);
CREATE INDEX exec_reports_officer ON public.exec_reports USING btree (officer, created_at DESC);
CREATE UNIQUE INDEX expense_entries_openrouter_day_uidx ON public.expense_entries USING btree (charged_on) WHERE (source = 'accountant:openrouter_daily'::text);
CREATE INDEX expenses_next_due_idx ON public.expenses USING btree (next_due) WHERE active;
CREATE UNIQUE INDEX feedback_one_per_case_kind ON public.feedback USING btree (case_id, kind) WHERE ((case_id IS NOT NULL) AND (kind IS NOT NULL));
CREATE UNIQUE INDEX field_definition_identity_uidx ON public.field_definition USING btree (scope, COALESCE(trade_key, ''::text), label_en);
CREATE INDEX file_scan_created_at_idx ON public.file_scan USING btree (created_at DESC);
CREATE INDEX file_scan_sha256_idx ON public.file_scan USING btree (sha256);
CREATE INDEX file_scan_verdict_idx ON public.file_scan USING btree (verdict, created_at DESC);
CREATE UNIQUE INDEX finance_kpi_snap_day ON public.finance_kpi_snapshots USING btree (snapshot_date);
CREATE INDEX founder_alerts_dedupe_idx ON public.founder_alerts USING btree (dedupe_key, created_at DESC) WHERE (dedupe_key IS NOT NULL);
CREATE INDEX founder_directive_received_idx ON public.founder_directive USING btree (received_at DESC);
CREATE INDEX founder_instruction_open_idx ON public.founder_instruction USING btree (said_at) WHERE (status = 'open'::text);
CREATE INDEX founder_mail_policy_history_kind_valid_from ON public.founder_mail_policy_history USING btree (kind, valid_from DESC);
CREATE UNIQUE INDEX gl_journal_one_live_entry_per_bank_or_fee_line ON public.gl_journal USING btree (source, source_ref) WHERE ((source = ANY (ARRAY['owner_capital'::text, 'bank_interest'::text, 'bank_charge'::text, 'stripe_fee_bt'::text, 'stripe_fee_bt_test'::text])) AND (source_ref IS NOT NULL) AND (status = ANY (ARRAY['draft'::text, 'posted'::text])));
CREATE INDEX gl_prior_period_adjustment_posted_on ON public.gl_prior_period_adjustment USING btree (posted_on);
CREATE INDEX graph_edges_dst ON public.graph_edges USING btree (dst_kind, dst_ref, rel);
CREATE INDEX graph_edges_rel ON public.graph_edges USING btree (rel);
CREATE UNIQUE INDEX handoff_contract_live_idem_idx ON public.handoff_contract USING btree (idempotency_key) WHERE (status = ANY (ARRAY['open'::text, 'accepted'::text, 'returned'::text]));
CREATE INDEX handoff_contract_owner_idx ON public.handoff_contract USING btree (accountable_owner, status);
CREATE INDEX handoff_contract_to_idx ON public.handoff_contract USING btree (to_dept, status, deadline);
CREATE INDEX idx_agent_knowledge_key ON public.agent_knowledge USING btree (agent_key);
CREATE INDEX idx_agent_memory_key ON public.agent_memory USING btree (agent_key, created_at DESC);
CREATE INDEX idx_ap_bills_status ON public.ap_bills USING btree (status);
CREATE INDEX idx_ap_bills_vendor ON public.ap_bills USING btree (vendor_id);
CREATE INDEX idx_budget_lines_budget ON public.budget_lines USING btree (budget_id);
CREATE INDEX idx_crm_activities_entity ON public.crm_activities USING btree (entity, entity_id, created_at DESC);
CREATE INDEX idx_crm_activities_tasks ON public.crm_activities USING btree (type, done, due_at) WHERE (type = 'task'::text);
CREATE INDEX idx_crm_notes_entity ON public.crm_notes USING btree (entity, entity_id, created_at DESC);
CREATE INDEX idx_crm_tasks_status ON public.crm_tasks USING btree (status, created_at DESC);
CREATE INDEX idx_declog ON public.decision_log USING btree (kind, created_at DESC);
CREATE INDEX idx_dept_library_dept ON public.dept_library USING btree (department);
CREATE INDEX idx_dept_library_tsv ON public.dept_library USING gin (tsv);
CREATE INDEX idx_doc_reviews_lead_id ON public.doc_reviews USING btree (lead_id);
CREATE INDEX idx_documents_status ON public.documents USING btree (status) WHERE (status = 'pending'::text);
CREATE INDEX idx_docver_entity ON public.doc_versions USING btree (entity_type, entity_id, version DESC);
CREATE INDEX idx_email_verif_email ON public.email_verifications USING btree (email);
CREATE INDEX idx_email_verif_token ON public.email_verifications USING btree (token);
CREATE INDEX idx_entity_comments_lookup ON public.entity_comments USING btree (entity, entity_id, created_at DESC);
CREATE INDEX idx_error_events_created ON public.error_events USING btree (created_at DESC);
CREATE INDEX idx_error_events_website_age ON public.error_events USING btree (created_at) WHERE (source = 'website'::text);
CREATE INDEX idx_gl_journal_date ON public.gl_journal USING btree (entry_date);
CREATE INDEX idx_gl_journal_source ON public.gl_journal USING btree (source, source_ref);
CREATE INDEX idx_gl_journal_status ON public.gl_journal USING btree (status);
CREATE INDEX idx_gl_lines_account ON public.gl_journal_lines USING btree (account_code);
CREATE INDEX idx_gl_lines_journal ON public.gl_journal_lines USING btree (journal_id);
CREATE INDEX idx_im_inquiry ON public.inquiry_matches USING btree (inquiry_id);
CREATE INDEX idx_inbound_messages_lead_id ON public.inbound_messages USING btree (lead_id);
CREATE INDEX idx_inq_category ON public.inquiries USING btree (category);
CREATE INDEX idx_inq_status ON public.inquiries USING btree (status);
CREATE INDEX idx_inqreq_trades ON public.inquiry_requirement USING gin (trades_required);
CREATE INDEX idx_inquiries_customer_id ON public.inquiries USING btree (customer_id);
CREATE INDEX idx_inquiries_hired_supplier_id ON public.inquiries USING btree (hired_supplier_id);
CREATE INDEX idx_inquiry_matches_supplier_id ON public.inquiry_matches USING btree (supplier_id);
CREATE INDEX idx_kbrev ON public.kb_revisions USING btree (entry_kind, entry_ref, version DESC);
CREATE INDEX idx_kexam_q_agent ON public.knowledge_exam_questions USING btree (agent_key, last_asked NULLS FIRST);
CREATE INDEX idx_kexam_r_agent ON public.knowledge_exam_results USING btree (agent_key, created_at DESC);
CREATE INDEX idx_leads_approval ON public.leads USING btree (approval_status);
CREATE INDEX idx_leads_claimedby ON public.leads USING btree (lower(claimed_by));
CREATE INDEX idx_leads_embedding_gte ON public.leads USING hnsw (embedding_gte vector_cosine_ops);
CREATE INDEX idx_leads_invite_trades ON public.leads USING gin (invite_trades);
CREATE INDEX idx_marketing_library_category ON public.marketing_library USING btree (category);
CREATE INDEX idx_marketing_library_tsv ON public.marketing_library USING gin (tsv);
CREATE INDEX idx_messages_customer_id ON public.messages USING btree (customer_id);
CREATE INDEX idx_messages_supplier_id ON public.messages USING btree (supplier_id);
CREATE INDEX idx_msg_inquiry ON public.messages USING btree (inquiry_id);
CREATE INDEX idx_notif_inquiry ON public.notifications USING btree (inquiry_id);
CREATE INDEX idx_notif_lead ON public.notifications USING btree (lead_id);
CREATE INDEX idx_notif_type ON public.notifications USING btree (type);
CREATE INDEX idx_org_agents_department ON public.org_agents USING btree (department);
CREATE INDEX idx_os_audit_action ON public.os_audit_log USING btree (action);
CREATE INDEX idx_os_audit_actor ON public.os_audit_log USING btree (actor);
CREATE INDEX idx_pdpl_erase_files_req ON public.pdpl_erase_files USING btree (request_id, status);
CREATE INDEX idx_phone_verif_phone ON public.phone_verifications USING btree (phone);
CREATE INDEX idx_po_lines_po ON public.po_lines USING btree (po_id);
CREATE INDEX idx_q_inquiry ON public.quotes USING btree (inquiry_id);
CREATE INDEX idx_q_status ON public.quotes USING btree (status);
CREATE INDEX idx_qcitems_review ON public.quote_committed_items USING btree (review_id, seq);
CREATE INDEX idx_qreviews_sup ON public.quote_reviews USING btree (supplier_id);
CREATE INDEX idx_qrmsg_review ON public.quote_review_messages USING btree (review_id, created_at);
CREATE INDEX idx_questions_customer_id ON public.questions USING btree (customer_id);
CREATE INDEX idx_quote_items_quote ON public.quote_items USING btree (quote_id);
CREATE INDEX idx_quote_pdf_cache_cust_time ON public.quote_pdf_cache USING btree (customer_id, created_at);
CREATE INDEX idx_quotes_supplier_id ON public.quotes USING btree (supplier_id);
CREATE INDEX idx_reviews_customer_id ON public.reviews USING btree (customer_id);
CREATE INDEX idx_reviews_inquiry_id ON public.reviews USING btree (inquiry_id);
CREATE INDEX idx_reviews_supplier_id ON public.reviews USING btree (supplier_id);
CREATE INDEX idx_rfq_arch_cat ON public.rfq_archives USING btree (category);
CREATE INDEX idx_rfq_arch_customer ON public.rfq_archives USING btree (customer_id);
CREATE INDEX idx_subcat_domain ON public.catalog_subcategories USING btree (domain_slug);
CREATE INDEX idx_supcap_emirates ON public.supplier_capabilities USING gin (coverage_emirates);
CREATE INDEX idx_supcap_excluded ON public.supplier_capabilities USING gin (excluded_trades);
CREATE INDEX idx_supcap_exclusions ON public.supplier_capabilities USING gin (exclusions);
CREATE INDEX idx_supcap_products ON public.supplier_capabilities USING gin (products_norm);
CREATE INDEX idx_supcap_roles ON public.supplier_capabilities USING gin (roles);
CREATE INDEX idx_supcap_trades ON public.supplier_capabilities USING gin (trades);
CREATE INDEX idx_supcapconf_supplier ON public.supplier_capability_confirmation USING btree (supplier_id, version DESC);
CREATE INDEX idx_taxonomy_role_aliases ON public.taxonomy_role USING gin (aliases);
CREATE INDEX idx_taxonomy_trade_aliases ON public.taxonomy_trade USING gin (aliases);
CREATE INDEX idx_transactions_customer_id ON public.transactions USING btree (customer_id);
CREATE INDEX idx_transactions_inquiry_id ON public.transactions USING btree (inquiry_id);
CREATE INDEX idx_transactions_quote_id ON public.transactions USING btree (quote_id);
CREATE INDEX idx_transactions_supplier_id ON public.transactions USING btree (supplier_id);
CREATE INDEX idx_user_roles_role ON public.user_roles USING btree (role);
CREATE INDEX im_category_idx ON public.institutional_memory USING btree (category_slug);
CREATE INDEX im_kind_idx ON public.institutional_memory USING btree (kind, occurred_at DESC);
CREATE INDEX im_subject_idx ON public.institutional_memory USING btree (subject_type, subject_id);
CREATE UNIQUE INDEX inbound_messages_provider_email_id_key ON public.inbound_messages USING btree (provider_email_id) WHERE (provider_email_id IS NOT NULL);
CREATE INDEX inquiries_project ON public.inquiries USING btree (project_id);
CREATE INDEX inquiries_repeat_of_idx ON public.inquiries USING btree (repeat_of) WHERE (repeat_of IS NOT NULL);
CREATE UNIQUE INDEX inquiries_rfq_no_key ON public.inquiries USING btree (rfq_no);
CREATE UNIQUE INDEX inquiry_answer_conflict_open_uidx ON public.inquiry_answer_conflict USING btree (group_id, field_id) WHERE (resolved_at IS NULL);
CREATE INDEX inquiry_answer_group_idx ON public.inquiry_answer USING btree (group_id, field_id);
CREATE UNIQUE INDEX inquiry_answer_live_uidx ON public.inquiry_answer USING btree (group_id, field_id) WHERE (superseded_by IS NULL);
CREATE UNIQUE INDEX inquiry_gate_group_uidx ON public.inquiry_gate USING btree (group_id, gate_key) WHERE (workstream_id IS NULL);
CREATE UNIQUE INDEX inquiry_gate_ws_uidx ON public.inquiry_gate USING btree (workstream_id, gate_key) WHERE (workstream_id IS NOT NULL);
CREATE INDEX inquiry_intake_customer_idx ON public.inquiry_intake USING btree (customer_id);
CREATE INDEX inquiry_intake_email_idx ON public.inquiry_intake USING btree (email);
CREATE UNIQUE INDEX inquiry_intake_one_open_repeat ON public.inquiry_intake USING btree (customer_id, ((brief ->> 'repeat_of'::text))) WHERE ((status = 'ready'::text) AND (brief ? 'repeat_of'::text));
CREATE INDEX inquiry_intake_status_idx ON public.inquiry_intake USING btree (status);
CREATE INDEX inquiry_scope_disposition_group_idx ON public.inquiry_scope_disposition USING btree (group_id, trade_key, scope_component);
CREATE INDEX inquiry_state_audit_group_idx ON public.inquiry_state_audit USING btree (group_id, at DESC);
CREATE INDEX inquiry_supplier_brief_inquiry_idx ON public.inquiry_supplier_brief USING btree (inquiry_id, version DESC);
CREATE UNIQUE INDEX inquiry_trade_clarification_open_uidx ON public.inquiry_trade_clarification USING btree (group_id) WHERE (answered_at IS NULL);
CREATE INDEX internal_credential_audit_at ON public.internal_credential_audit USING btree (at DESC);
CREATE INDEX internal_credential_ctx_active ON public.internal_credential USING btree (context) WHERE active;
CREATE UNIQUE INDEX internal_credential_hash_uq ON public.internal_credential USING btree (secret_hash);
CREATE UNIQUE INDEX invite_brake_one_open ON public.invite_brake USING btree ((true)) WHERE (resumed_at IS NULL);
CREATE INDEX it_engineer_finding_open_idx ON public.it_engineer_finding USING btree (closed_at, blast) WHERE (closed_at IS NULL);
CREATE INDEX it_engineer_knowledge_emb_hnsw ON public.it_engineer_knowledge USING hnsw (embedding_gte vector_cosine_ops);
CREATE INDEX it_engineer_knowledge_epi_idx ON public.it_engineer_knowledge USING btree (epistemic_status);
CREATE INDEX it_engineer_knowledge_search_idx ON public.it_engineer_knowledge USING gin (search);
CREATE INDEX it_engineer_knowledge_type_idx ON public.it_engineer_knowledge USING btree (record_type);
CREATE UNIQUE INDEX it_integration_external_cause_one_open ON public.it_integration_external_cause USING btree (integration) WHERE (closed_at IS NULL);
CREATE INDEX it_watch_finding_open_idx ON public.it_watch_finding USING btree (severity, last_seen_at DESC) WHERE (status = 'open'::text);
CREATE INDEX it_watch_tick_ran_at_idx ON public.it_watch_tick USING btree (ran_at DESC);
CREATE INDEX ix_accountant_spend_report_as_of ON public.accountant_spend_report USING btree (as_of DESC);
CREATE INDEX ix_action_execution_correlation ON public.action_execution USING btree (correlation_id);
CREATE INDEX ix_ap_bills_gl_journal_id ON public.ap_bills USING btree (gl_journal_id);
CREATE INDEX ix_ap_bills_pay_journal_id ON public.ap_bills USING btree (pay_journal_id);
CREATE INDEX ix_ap_bills_po_id ON public.ap_bills USING btree (po_id);
CREATE INDEX ix_budget_lines_account_code ON public.budget_lines USING btree (account_code);
CREATE INDEX ix_company_event_correlation ON public.company_event USING btree (correlation_id);
CREATE INDEX ix_decision_trace_agent ON public.decision_trace USING btree (agent_key, created_at DESC);
CREATE INDEX ix_decision_trace_correlation ON public.decision_trace USING btree (correlation_id);
CREATE INDEX ix_decision_trace_dept ON public.decision_trace USING btree (department_id, created_at DESC);
CREATE INDEX ix_decision_trace_role ON public.decision_trace USING btree (role_id, created_at DESC);
CREATE INDEX ix_decision_trace_status ON public.decision_trace USING btree (outcome_status, created_at DESC);
CREATE INDEX ix_doc_backups_backed_up_at ON public.doc_backups USING btree (backed_up_at) WHERE (backed_up_at IS NOT NULL);
CREATE INDEX ix_doc_backups_export_day ON public.doc_backups USING btree ("left"(dedupe_key, 18));
CREATE INDEX ix_doc_backups_live_status ON public.doc_backups USING btree (status, id) WHERE (status = ANY (ARRAY['processing'::text, 'waiting_source'::text, 'prune_pending'::text, 'pruning'::text]));
CREATE INDEX ix_doc_backups_status ON public.doc_backups USING btree (status) WHERE (status = ANY (ARRAY['pending'::text, 'error'::text]));
CREATE INDEX ix_event_assessment_event ON public.event_assessment USING btree (event_id);
CREATE INDEX ix_gl_accounts_parent_code ON public.gl_accounts USING btree (parent_code);
CREATE INDEX ix_gl_expense_map_account_code ON public.gl_expense_map USING btree (account_code);
CREATE INDEX ix_gl_journal_reverses ON public.gl_journal USING btree (reverses);
CREATE INDEX ix_inqcancel_cust ON public.inquiry_cancellations USING btree (customer_id, created_at DESC);
CREATE INDEX ix_inquiries_parent_inquiry ON public.inquiries USING btree (parent_inquiry_id);
CREATE INDEX ix_inv_items_cogs_account ON public.inv_items USING btree (cogs_account);
CREATE INDEX ix_inv_items_inventory_account ON public.inv_items USING btree (inventory_account);
CREATE INDEX ix_org_memory_scope ON public.org_memory USING btree (scope) WHERE active;
CREATE INDEX ix_org_tasks_dept_status ON public.org_tasks USING btree (dept_key, status);
CREATE INDEX ix_org_tasks_objective ON public.org_tasks USING btree (objective_id);
CREATE INDEX ix_po_lines_account_code ON public.po_lines USING btree (account_code);
CREATE INDEX ix_po_lines_item_id ON public.po_lines USING btree (item_id);
CREATE INDEX ix_po_orders_vendor_id ON public.po_orders USING btree (vendor_id);
CREATE INDEX ix_quote_comparisons_inq ON public.quote_comparisons USING btree (inquiry_id, created_at DESC);
CREATE INDEX ix_regulations_supersedes_id ON public.regulations USING btree (supersedes_id);
CREATE INDEX ix_sec_audit_at ON public.security_audit_log USING btree (at DESC);
CREATE INDEX ix_sec_audit_tbl ON public.security_audit_log USING btree (table_name, at DESC);
CREATE INDEX ix_workflow_run_correlation ON public.workflow_run USING btree (correlation_id);
CREATE INDEX ix_workflow_run_status ON public.workflow_run USING btree (status, next_attempt_at);
CREATE INDEX kb_chunks_cat_id_idx ON public.kb_chunks USING btree (category) INCLUDE (id);
CREATE INDEX kb_chunks_cat_id_idx_old ON public.kb_chunks_old USING btree (category) INCLUDE (id);
CREATE INDEX kb_chunks_category_norm_idx ON public.kb_chunks USING btree (category_norm);
CREATE INDEX kb_chunks_category_norm_idx_old ON public.kb_chunks_old USING btree (category_norm);
CREATE UNIQUE INDEX kb_chunks_company_faq_source_id ON public.kb_chunks USING btree (source_id) WHERE (source_kind = 'company_faq'::text);
CREATE UNIQUE INDEX kb_chunks_company_faq_source_id_old ON public.kb_chunks_old USING btree (source_id) WHERE (source_kind = 'company_faq'::text);
CREATE INDEX kb_chunks_created_at_desc_idx ON public.kb_chunks USING btree (created_at DESC);
CREATE INDEX kb_chunks_created_at_desc_idx_old ON public.kb_chunks_old USING btree (created_at DESC);
CREATE INDEX kb_chunks_emb_hnsw ON public.kb_chunks USING hnsw (embedding_gte vector_cosine_ops);
CREATE INDEX kb_chunks_emb_hnsw_old ON public.kb_chunks_old USING hnsw (embedding_gte vector_cosine_ops);
CREATE INDEX kb_chunks_fts ON public.kb_chunks USING gin (fts);
CREATE INDEX kb_chunks_fts_old ON public.kb_chunks_old USING gin (fts);
CREATE UNIQUE INDEX kb_chunks_qdkb_source_uidx ON public.kb_chunks USING btree (source_id) WHERE (source_kind = 'qd_kb_pack'::text);
CREATE UNIQUE INDEX kb_chunks_qdkb_source_uidx_old ON public.kb_chunks_old USING btree (source_id) WHERE (source_kind = 'qd_kb_pack'::text);
CREATE INDEX kb_chunks_source_id_idx ON public.kb_chunks USING btree (source_id);
CREATE INDEX kb_chunks_source_id_idx_old ON public.kb_chunks_old USING btree (source_id);
CREATE INDEX kb_chunks_source_kind_idx ON public.kb_chunks USING btree (source_kind);
CREATE INDEX kb_chunks_source_kind_idx_old ON public.kb_chunks_old USING btree (source_kind);
CREATE INDEX kb_chunks_unembedded_cat_created_idx ON public.kb_chunks USING btree (category, created_at) WHERE (embedding_gte IS NULL);
CREATE INDEX kb_chunks_unembedded_cat_created_idx_old ON public.kb_chunks_old USING btree (category, created_at) WHERE (embedding_gte IS NULL);
CREATE INDEX kb_chunks_unembedded_created_idx ON public.kb_chunks USING btree (created_at) WHERE (embedding_gte IS NULL);
CREATE INDEX kb_chunks_unembedded_created_idx_old ON public.kb_chunks_old USING btree (created_at) WHERE (embedding_gte IS NULL);
CREATE INDEX kb_chunks_unembedded_kind_created_idx ON public.kb_chunks USING btree (source_kind, created_at) WHERE (embedding_gte IS NULL);
CREATE INDEX kb_chunks_unembedded_kind_created_idx_old ON public.kb_chunks_old USING btree (source_kind, created_at) WHERE (embedding_gte IS NULL);
CREATE INDEX kb_embed_inflight_chunk_idx ON public.kb_embed_inflight USING btree (chunk_id);
CREATE INDEX kb_op_alias_lang_idx ON public.kb_operational_alias USING btree (language, negative);
CREATE INDEX kb_op_alias_norm_idx ON public.kb_operational_alias USING btree (alias_norm);
CREATE INDEX kb_op_route_map_pkg_idx ON public.kb_operational_route_map USING btree (package_slug, subcategory_slug);
CREATE INDEX kb_op_route_test_num_idx ON public.kb_operational_route_test USING btree (catalog_num);
CREATE INDEX kb_purge_ledger_batch_idx ON public.kb_purge_ledger USING btree (batch_no) WHERE (batch_no IS NOT NULL);
CREATE INDEX kb_usage_log_created ON public.kb_usage_log USING btree (created_at);
CREATE INDEX knowledge_ingestion_run_pkg ON public.knowledge_ingestion_run USING btree (package_version, generation);
CREATE INDEX knowledge_ingestion_undo_run ON public.knowledge_ingestion_undo USING btree (run_id);
CREATE UNIQUE INDEX knowledge_kpi_snap_day ON public.knowledge_kpi_snapshots USING btree (snapshot_date);
CREATE INDEX knowledge_library_kb_hnsw ON public.knowledge_library USING hnsw (embedding_gte vector_cosine_ops) WHERE (origin_store = 'kb_chunks'::text);
CREATE INDEX knowledge_library_md5_idx ON public.knowledge_library USING btree (content_md5) WHERE (origin_store = ANY (ARRAY['kb_chunks'::text, 'agent_knowledge'::text, 'ops_knowledge'::text]));
CREATE INDEX knowledge_library_ops_hnsw ON public.knowledge_library USING hnsw (embedding_gte vector_cosine_ops) WHERE (origin_store = 'ops_knowledge'::text);
CREATE INDEX knowledge_library_origin_lib_idx ON public.knowledge_library_origin USING btree (library_id);
CREATE INDEX knowledge_library_sales_hnsw ON public.knowledge_library USING hnsw (embedding_gte vector_cosine_ops) WHERE (origin_store = 'sales_knowledge'::text);
CREATE INDEX knowledge_library_seats_idx ON public.knowledge_library USING gin (seats);
CREATE INDEX knowledge_library_store_idx ON public.knowledge_library USING btree (origin_store);
CREATE INDEX knowledge_library_tags_idx ON public.knowledge_library USING gin (tags);
CREATE INDEX knowledge_vector_ml_day_idx ON public.knowledge_vector_ml USING btree (embedded_at);
CREATE INDEX knowledge_vector_ml_kb_hnsw ON public.knowledge_vector_ml USING hnsw (embedding vector_cosine_ops) WHERE (src = 'kb_chunks'::text);
CREATE INDEX knowledge_vector_ml_library_hnsw ON public.knowledge_vector_ml USING hnsw (embedding vector_cosine_ops) WHERE (src = 'knowledge_library'::text);
CREATE UNIQUE INDEX lead_category_primary_uidx ON public.lead_category USING btree (lead_id) WHERE is_primary;
CREATE INDEX lead_category_slug_idx ON public.lead_category USING btree (slug);
CREATE INDEX lead_prospect_domain_idx ON public.lead_prospect USING btree (domain);
CREATE INDEX lead_prospect_run_idx ON public.lead_prospect USING btree (run_id);
CREATE UNIQUE INDEX lead_sourcing_one_reservation ON public.lead_sourcing_run USING btree ((true)) WHERE (status = 'reserved'::text);
CREATE INDEX lead_subcategory_domain_idx ON public.lead_subcategory USING btree (domain_slug);
CREATE UNIQUE INDEX lead_subcategory_primary_uidx ON public.lead_subcategory USING btree (lead_id) WHERE is_primary;
CREATE INDEX lead_subcategory_sub_idx ON public.lead_subcategory USING btree (sub_slug);
CREATE INDEX lead_trade_class_trade_idx ON public.lead_trade_class USING btree (trade_code);
CREATE UNIQUE INDEX leads_claim_token_key ON public.leads USING btree (claim_token);
CREATE INDEX leads_claimed_by_idx ON public.leads USING btree (claimed_by);
CREATE UNIQUE INDEX leads_claimed_by_lower_uidx ON public.leads USING btree (lower(btrim(claimed_by))) WHERE ((claimed_by IS NOT NULL) AND (btrim(claimed_by) <> ''::text));
CREATE UNIQUE INDEX leads_claimed_company_name_uidx ON public.leads USING btree (fn_company_registration_name_key(company_name)) WHERE claimed;
CREATE UNIQUE INDEX leads_claimed_trade_licence_uidx ON public.leads USING btree (fn_trade_licence_key(trade_license_no)) WHERE claimed;
CREATE INDEX leads_email_idx ON public.leads USING btree (email);
CREATE INDEX leads_email_lower_idx ON public.leads USING btree (lower(email));
CREATE INDEX leads_embedding_idx ON public.leads USING hnsw (embedding vector_cosine_ops);
CREATE INDEX leads_emirate_idx ON public.leads USING btree (emirate);
CREATE INDEX leads_exception_due_idx ON public.leads USING btree (exception_due_at) WHERE (exception_closed_at IS NULL);
CREATE UNIQUE INDEX leads_founding_rank_uidx ON public.leads USING btree (founding_rank) WHERE (founding_rank IS NOT NULL);
CREATE INDEX leads_has_email_idx ON public.leads USING btree (((email IS NOT NULL)));
CREATE INDEX leads_invite_status_idx ON public.leads USING btree (invite_status);
CREATE INDEX leads_invited_at_idx ON public.leads USING btree (invited_at) WHERE (invited_at IS NOT NULL);
CREATE INDEX leads_lifecycle_stage_idx ON public.leads USING btree (lifecycle_stage);
CREATE INDEX leads_phone_tail9_idx ON public.leads USING btree ("right"(regexp_replace(COALESCE(phone, ''::text), '[^0-9]'::text, ''::text, 'g'::text), 9));
CREATE UNIQUE INDEX leads_place_id_uidx ON public.leads USING btree (place_id) WHERE (place_id IS NOT NULL);
CREATE INDEX leads_sector_idx ON public.leads USING btree (sector);
CREATE INDEX leads_whatsapp_phone_tail9_idx ON public.leads USING btree ("right"(regexp_replace(COALESCE(whatsapp_phone, ''::text), '[^0-9]'::text, ''::text, 'g'::text), 9));
CREATE UNIQUE INDEX legal_kpi_snap_day ON public.legal_kpi_snapshots USING btree (snapshot_date);
CREATE INDEX licence_renewal_ask_open ON public.licence_renewal_ask USING btree (lead_id, asked_at DESC) WHERE (answered_at IS NULL);
CREATE INDEX llm_attempt_agent_idx ON public.llm_attempt USING btree (agent_key, created_at DESC);
CREATE INDEX llm_attempt_first_idx ON public.llm_attempt USING btree (created_at DESC) WHERE (attempt_no = 1);
CREATE INDEX llm_attempt_route_idx ON public.llm_attempt USING btree (model_route, created_at DESC);
CREATE INDEX llm_cache_emb_idx ON public.llm_cache USING ivfflat (embedding_gte vector_cosine_ops) WITH (lists='50');
CREATE INDEX llm_cache_expiry_idx ON public.llm_cache USING btree (expires_at);
CREATE INDEX llm_calls_created_idx ON public.llm_calls USING btree (created_at DESC);
CREATE INDEX llm_calls_fn_idx ON public.llm_calls USING btree (fn, created_at DESC);
CREATE UNIQUE INDEX market_intel_one_row_per_post ON public.market_intel USING btree (platform, external_id) WHERE (external_id IS NOT NULL);
CREATE UNIQUE INDEX marketing_article_round_one_waiting ON public.marketing_article_round USING btree (article_id) WHERE (decision IS NULL);
CREATE INDEX marketing_asset_feature_path ON public.marketing_asset_feature USING btree (asset_bucket, asset_path);
CREATE INDEX marketing_asset_review_sha ON public.marketing_asset_review USING btree (file_sha256, created_at DESC);
CREATE INDEX marketing_blog_topic_key ON public.marketing_blog_topic USING btree (topic_key, picked_at DESC);
CREATE UNIQUE INDEX marketing_blog_topic_one_open ON public.marketing_blog_topic USING btree ((true)) WHERE (status = 'picked'::text);
CREATE INDEX marketing_calendar_resend_decision_campaign ON public.marketing_calendar_resend_decision USING btree (campaign_id, id DESC);
CREATE INDEX marketing_first_touch_post ON public.marketing_first_touch USING btree (post_id) WHERE (post_id IS NOT NULL);
CREATE UNIQUE INDEX marketing_founder_request_one_per_message ON public.marketing_founder_request USING btree (message_id) WHERE ((message_id IS NOT NULL) AND (message_id <> ''::text));
CREATE INDEX marketing_gap_recruitment_plan_trade_idx ON public.marketing_gap_recruitment_plan USING btree (trade, rank);
CREATE INDEX marketing_knowledge_emb_hnsw ON public.marketing_knowledge USING hnsw (embedding_gte vector_cosine_ops);
CREATE UNIQUE INDEX marketing_model_run_held_once_a_day ON public.marketing_model_run USING btree (step, subject, run_day) WHERE (outcome = 'held_not_run'::text);
CREATE INDEX marketing_outreach_message_day_idx ON public.marketing_outreach_message USING btree (listed_on);
CREATE UNIQUE INDEX marketing_outreach_message_one_first_idx ON public.marketing_outreach_message USING btree (prospect_id) WHERE (kind = 'first'::text);
CREATE INDEX marketing_post_campaign_idx ON public.marketing_post USING btree (campaign_id);
CREATE INDEX marketing_post_channel_result_open ON public.marketing_post_channel_result USING btree (state) WHERE (state = ANY (ARRAY['partial'::text, 'failed'::text]));
CREATE INDEX marketing_post_due_idx ON public.marketing_post USING btree (scheduled_at) WHERE (status = 'scheduled'::text);
CREATE INDEX marketing_post_metric_post ON public.marketing_post_metric USING btree (post_id, platform);
CREATE UNIQUE INDEX marketing_prospect_one_person_idx ON public.marketing_prospect USING btree (lower(full_name), lower(company));
CREATE UNIQUE INDEX marketing_snap_day ON public.marketing_snapshots USING btree (snapshot_date);
CREATE INDEX marketing_trend_unjudged ON public.marketing_trend USING btree (seen_at) WHERE (relevant IS NULL);
CREATE INDEX materials_cat ON public.materials USING btree (category);
CREATE INDEX messages_thread_idx ON public.messages USING btree (inquiry_id, supplier_id, created_at);
CREATE INDEX messaging_template_key_idx ON public.messaging_template USING btree (channel, template_key, lang);
CREATE INDEX metric_snapshot_key_time_idx ON public.metric_snapshot USING btree (metric_key, taken_at DESC);
CREATE UNIQUE INDEX model_catalogue_change_one_open ON public.model_catalogue_change USING btree (model_id, field) WHERE (closed_at IS NULL);
CREATE INDEX money_move_hold_held ON public.money_move_hold USING btree (opened_at) WHERE (status = 'held'::text);
CREATE UNIQUE INDEX money_move_hold_one_open_per_move ON public.money_move_hold USING btree (move, ref) WHERE (status <> 'released'::text);
CREATE UNIQUE INDEX notice_plain_language_cause_one_open ON public.notice_plain_language_cause USING btree (type, fixture) WHERE (status <> 'closed'::text);
CREATE INDEX notice_plain_language_type_scored ON public.notice_plain_language USING btree (type, scored_at);
CREATE UNIQUE INDEX notifications_dedupe_key_uidx ON public.notifications USING btree (dedupe_key) WHERE (dedupe_key IS NOT NULL);
CREATE UNIQUE INDEX notifications_one_sms_twin ON public.notifications USING btree (failover_of) WHERE (failover_of IS NOT NULL);
CREATE INDEX notifications_provider_message_id_idx ON public.notifications USING btree (provider_message_id) WHERE (provider_message_id IS NOT NULL);
CREATE UNIQUE INDEX notifications_rating_request_uidx ON public.notifications USING btree (quote_id) WHERE ((type = 'rating_request'::text) AND (COALESCE(channel, 'email'::text) = 'email'::text));
CREATE INDEX notifications_sending_claimed_at_idx ON public.notifications USING btree (claimed_at) WHERE (status = 'sending'::text);
CREATE INDEX notifications_status_idx ON public.notifications USING btree (status, created_at);
CREATE UNIQUE INDEX notifications_supplier_invite_once_uidx ON public.notifications USING btree (lower(btrim(to_email))) WHERE (type = 'supplier_invite'::text);
CREATE INDEX openrouter_meter_read_at_idx ON public.openrouter_meter USING btree (read_at DESC);
CREATE INDEX ops_knowledge_category ON public.ops_knowledge USING btree (category_key) WHERE (category_key IS NOT NULL);
CREATE INDEX ops_knowledge_dept_idx ON public.ops_knowledge USING btree (dept_key, record_type);
CREATE INDEX ops_knowledge_emb_hnsw ON public.ops_knowledge USING hnsw (embedding_gte vector_cosine_ops);
CREATE INDEX ops_knowledge_role ON public.ops_knowledge USING btree (role_key) WHERE (role_key IS NOT NULL);
CREATE INDEX ops_knowledge_run ON public.ops_knowledge USING btree (ingestion_run_id);
CREATE INDEX ops_knowledge_runtime_lookup ON public.ops_knowledge USING btree (runtime_eligible, layer, scope_type, scope_key) WHERE (supersession_state = 'current'::text);
CREATE INDEX ops_knowledge_scope_idx ON public.ops_knowledge USING btree (scope_key, module);
CREATE INDEX ops_knowledge_tsv_idx ON public.ops_knowledge USING gin (tsv);
CREATE INDEX ops_knowledge_unembedded ON public.ops_knowledge USING btree (record_id) WHERE (embedding_gte IS NULL);
CREATE UNIQUE INDEX ops_kpi_snap_day ON public.ops_kpi_snapshots USING btree (snapshot_date);
CREATE INDEX org_role_dept_ix ON public.org_role USING btree (primary_department_id) WHERE (status = 'active'::text);
CREATE INDEX org_role_identity_dept ON public.org_role_identity USING btree (packaged_department);
CREATE INDEX org_role_identity_role ON public.org_role_identity USING btree (packaged_role_id);
CREATE INDEX org_role_mgr_ix ON public.org_role USING btree (manager_role_id);
CREATE UNIQUE INDEX org_role_one_per_agent_ux ON public.org_role USING btree (runtime_agent_key) WHERE ((status = 'active'::text) AND (runtime_agent_key IS NOT NULL));
CREATE INDEX org_tasks_assigned_agent_idx ON public.org_tasks USING btree (assigned_agent) WHERE (assigned_agent IS NOT NULL);
CREATE INDEX org_tasks_assigned_queue_idx ON public.org_tasks USING btree (priority DESC, id) WHERE (status = 'assigned'::text);
CREATE INDEX os_audit_log_action_idx ON public.os_audit_log USING btree (action, at DESC);
CREATE INDEX os_audit_log_actor_idx ON public.os_audit_log USING btree (actor, at DESC);
CREATE INDEX os_audit_log_at_idx ON public.os_audit_log USING btree (at DESC);
CREATE UNIQUE INDEX os_department_dept_key_uniq ON public.os_department USING btree (dept_key);
CREATE UNIQUE INDEX os_knowledge_domain_owns_uniq ON public.os_knowledge_domain USING btree (domain_key) WHERE (ownership = 'owns'::text);
CREATE INDEX outcome_record_actor_idx ON public.outcome_record USING btree (actor);
CREATE INDEX outcome_record_due_idx ON public.outcome_record USING btree (due_at) WHERE (verdict = 'pending'::text);
CREATE INDEX outcome_record_subject_idx ON public.outcome_record USING btree (subject_type, subject_id);
CREATE UNIQUE INDEX outreach_lead_uq ON public.outreach USING btree (lead_id) WHERE (lead_id IS NOT NULL);
CREATE INDEX outreach_status_idx ON public.outreach USING btree (status, id DESC);
CREATE INDEX phone_code_live ON public.phone_code USING btree (phone, purpose, created_at DESC) WHERE (used_at IS NULL);
CREATE INDEX po_orders_customer_idx ON public.po_orders USING btree (customer_id) WHERE (customer_id IS NOT NULL);
CREATE UNIQUE INDEX post_reveal_dispute_one_open_per_transaction ON public.post_reveal_dispute USING btree (transaction_id) WHERE (stage <> 'decided'::text);
CREATE INDEX price_benchmark_category_idx ON public.price_benchmark USING btree (category) WHERE (source_kind <> 'gap'::text);
CREATE UNIQUE INDEX price_benchmark_natural_key ON public.price_benchmark USING btree (category, source_kind, source_ref, unit, COALESCE(item, ''::text), COALESCE(low, ('-1'::integer)::numeric), COALESCE(high, ('-1'::integer)::numeric));
CREATE INDEX projects_customer ON public.projects USING btree (customer_id);
CREATE INDEX q_inq_sup_idx ON public.questions USING btree (inquiry_id, supplier_id);
CREATE INDEX q_sup_idx ON public.questions USING btree (supplier_id, answered_at);
CREATE INDEX quote_pdf_cache_bucket_path_idx ON public.quote_pdf_cache USING btree (bucket, path);
CREATE INDEX quote_quality_hold_by_inquiry ON public.quote_quality_hold USING btree (inquiry_id);
CREATE INDEX quote_quality_hold_open ON public.quote_quality_hold USING btree (release_due) WHERE ((released_at IS NULL) AND (superseded_at IS NULL));
CREATE INDEX quote_review_messages_by_review_kind ON public.quote_review_messages USING btree (review_id, kind);
CREATE INDEX quote_review_request_by_answered_message ON public.quote_review_request USING btree (answered_message_id);
CREATE INDEX quote_review_request_by_asked_message ON public.quote_review_request USING btree (asked_message_id);
CREATE INDEX quote_review_request_by_review ON public.quote_review_request USING btree (review_id, state);
CREATE UNIQUE INDEX quote_review_request_one_open ON public.quote_review_request USING btree (review_id, key) WHERE (state = 'open'::text);
CREATE INDEX quote_reviews_by_owner_email ON public.quote_reviews USING btree (owner_email);
CREATE INDEX quote_spec_hold_by_inquiry ON public.quote_spec_hold USING btree (inquiry_id, state);
CREATE UNIQUE INDEX quote_spec_hold_one_live ON public.quote_spec_hold USING btree (quote_id) WHERE (state = ANY (ARRAY['open'::text, 'awaiting_approval'::text]));
CREATE UNIQUE INDEX quotes_inquiry_supplier_option_key ON public.quotes USING btree (inquiry_id, supplier_id, option_no);
CREATE INDEX quotes_original_file_path_idx ON public.quotes USING btree (original_file_path) WHERE (original_file_path IS NOT NULL);
CREATE INDEX quotes_stale_idx ON public.quotes USING btree (inquiry_id) WHERE (stale_at IS NOT NULL);
CREATE INDEX reasoning_held_question_due_idx ON public.reasoning_held_question USING btree (status, last_attempt_at NULLS FIRST, created_at) WHERE (status = 'held'::text);
CREATE INDEX reasoning_held_question_qhash_idx ON public.reasoning_held_question USING btree (surface, qhash, status);
CREATE UNIQUE INDEX red_episode_one_open_per_key ON public.red_episode USING btree (check_key) WHERE (resolved_at IS NULL);
CREATE INDEX red_episode_open ON public.red_episode USING btree (resolved_at) WHERE (resolved_at IS NULL);
CREATE UNIQUE INDEX refund_case_one_live_per_transaction ON public.refund_case USING btree (transaction_id) WHERE (state <> ALL (ARRAY['ineligible'::text, 'ceo_declined'::text, 'failed'::text, 'canceled'::text]));
CREATE INDEX refund_case_open_idx ON public.refund_case USING btree (state, created_at);
CREATE INDEX refund_ceo_check_tx_idx ON public.refund_ceo_check USING btree (transaction_id, phase, checked_at DESC);
CREATE INDEX refund_event_quarantine_open_idx ON public.refund_event_quarantine USING btree (resolved_at, created_at);
CREATE INDEX refund_ladder_evidence_tx_idx ON public.refund_ladder_evidence USING btree (transaction_id, step, id DESC);
CREATE INDEX refunds_customer_idx ON public.refunds USING btree (customer_id);
CREATE INDEX refunds_inquiry_idx ON public.refunds USING btree (inquiry_id);
CREATE UNIQUE INDEX refunds_one_live_platform_refund_per_payment ON public.refunds USING btree (transaction_id) WHERE ((transaction_id IS NOT NULL) AND (topup_of IS NULL) AND (status <> ALL (ARRAY['failed'::text, 'rejected'::text, 'cancelled'::text])) AND (lower(COALESCE(requested_by, ''::text)) <> ALL (ARRAY['stripe_webhook'::text, 'stripe_dashboard'::text, 'stripe'::text])));
CREATE INDEX refunds_status_idx ON public.refunds USING btree (status, created_at DESC);
CREATE INDEX refunds_stripe_pi_idx ON public.refunds USING btree (stripe_payment_intent);
CREATE INDEX refunds_transaction_idx ON public.refunds USING btree (transaction_id);
CREATE INDEX refunds_unreconciled_idx ON public.refunds USING btree (settled_at) WHERE ((reconciled_at IS NULL) AND (status = 'succeeded'::text));
CREATE INDEX regulations_cats ON public.regulations USING gin (categories);
CREATE INDEX rehearsal_spend_reservation_tag_idx ON public.rehearsal_spend_reservation USING btree (e2e_run_tag, created_at);
CREATE INDEX rehearsal_window_open_idx ON public.rehearsal_window USING btree (started_at, ended_at);
CREATE INDEX reveal_invoices_bucket_path_idx ON public.reveal_invoices USING btree (bucket, path);
CREATE INDEX review_chain_subject_idx ON public.review_chain USING btree (subject_type, subject_id, id);
CREATE UNIQUE INDEX review_hold_one_open ON public.review_hold USING btree (task_class, COALESCE(fn, ''::text), counterpart_model) WHERE (closed_at IS NULL);
CREATE UNIQUE INDEX reviews_one_per_job ON public.reviews USING btree (supplier_id, inquiry_id, customer_id);
CREATE INDEX rfq_clarification_inquiry_idx ON public.rfq_clarification USING btree (inquiry_id, asked_at);
CREATE INDEX rfq_clarification_supplier_idx ON public.rfq_clarification USING btree (supplier_id, asked_at) WHERE (supplier_id IS NOT NULL);
CREATE INDEX rl_hits_k_at ON public.rl_hits USING btree (k, at);
CREATE INDEX routine_change_log_object_at ON public.routine_change_log USING btree (object_identity, at DESC);
CREATE INDEX routine_judgement_due_idx ON public.routine_judgement USING btree (id) WHERE (status = 'queued'::text);
CREATE INDEX sales_decision_log_action_idx ON public.sales_decision_log USING btree (action, created_at DESC);
CREATE INDEX sales_decision_log_created_idx ON public.sales_decision_log USING btree (created_at DESC);
CREATE INDEX sales_decision_log_e2e_run_tag_idx ON public.sales_decision_log USING btree (e2e_run_tag) WHERE (e2e_run_tag IS NOT NULL);
CREATE INDEX sales_knowledge_emb_hnsw ON public.sales_knowledge USING hnsw (embedding_gte vector_cosine_ops);
CREATE INDEX sales_knowledge_gap_open_idx ON public.sales_knowledge_gap USING btree (asks DESC, last_asked_at DESC) WHERE (status = 'open'::text);
CREATE INDEX sales_knowledge_pack_idx ON public.sales_knowledge USING btree (pack_id);
CREATE INDEX sales_knowledge_search_idx ON public.sales_knowledge USING gin (search);
CREATE INDEX sales_knowledge_type_idx ON public.sales_knowledge USING btree (record_type);
CREATE INDEX sales_qualification_field_sector_idx ON public.sales_qualification_field USING btree (sector_id);
CREATE INDEX sanctions_ban_account_idx ON public.sanctions_ban USING btree (account_email) WHERE (account_email IS NOT NULL);
CREATE INDEX sanctions_ban_contact_idx ON public.sanctions_ban USING btree (contact_email) WHERE (contact_email IS NOT NULL);
CREATE UNIQUE INDEX sanctions_ban_lead_uidx ON public.sanctions_ban USING btree (lead_id);
CREATE INDEX sanctions_ban_licence_idx ON public.sanctions_ban USING btree (licence_key) WHERE (licence_key IS NOT NULL);
CREATE INDEX sanctions_ban_name_idx ON public.sanctions_ban USING btree (name_key) WHERE (name_key IS NOT NULL);
CREATE INDEX screening_entry_norm_idx ON public.screening_entry USING btree (name_norm);
CREATE INDEX screening_entry_run_idx ON public.screening_entry USING btree (run_id);
CREATE INDEX seat_case_memory_emb_hnsw ON public.seat_case_memory USING hnsw (embedding vector_cosine_ops);
CREATE INDEX seat_case_memory_pending_idx ON public.seat_case_memory USING btree (id) WHERE (embedding IS NULL);
CREATE INDEX seat_case_memory_seat_kind_idx ON public.seat_case_memory USING btree (seat, case_kind, finalised, opened_at DESC);
CREATE INDEX seat_deliberation_turn_by_deliberation ON public.seat_deliberation_turn USING btree (deliberation_id);
CREATE UNIQUE INDEX seat_deliberation_turn_one_recorded ON public.seat_deliberation_turn USING btree (deliberation_id, round, phase) WHERE (status = 'recorded'::text);
CREATE UNIQUE INDEX seat_deliberation_turn_one_waiting ON public.seat_deliberation_turn USING btree (deliberation_id, round, phase) WHERE (status = ANY (ARRAY['held_not_run'::text, 'no_independent_reviewer'::text]));
CREATE INDEX seat_exam_asked_item_time ON public.seat_exam_asked USING btree (item_id, asked_at DESC);
CREATE UNIQUE INDEX seat_exam_asked_wording_once ON public.seat_exam_asked USING btree (item_id, md5(lower(regexp_replace(wording, '\W+'::text, ''::text, 'g'::text))));
CREATE UNIQUE INDEX seat_exam_fix_one_open_per_item ON public.seat_exam_fix USING btree (item_id) WHERE (status = 'open'::text);
CREATE INDEX seat_judgement_seat_outcome_idx ON public.seat_judgement USING btree (seat, outcome_at);
CREATE INDEX seat_judgement_subject_idx ON public.seat_judgement USING btree (subject_table, subject_id) WHERE (subject_table IS NOT NULL);
CREATE INDEX seat_knowledge_exam_item ON public.seat_knowledge_exam USING btree (seat, item_key, asked_at);
CREATE INDEX seat_knowledge_exam_seat_graded ON public.seat_knowledge_exam USING btree (seat, graded_at);
CREATE INDEX seat_knowledge_stale_open ON public.seat_knowledge_stale USING btree (seat, quarter) WHERE (resolved_at IS NULL);
CREATE INDEX seat_knowledge_stale_unfiled ON public.seat_knowledge_stale USING btree (quarter, flagged_at, item_key) WHERE (held_id IS NULL);
CREATE INDEX security_advisor_baseline_new_idx ON public.security_advisor_baseline USING btree (in_baseline, cleared_at);
CREATE UNIQUE INDEX security_events_fingerprint_uq ON public.security_events USING btree (fingerprint);
CREATE INDEX security_events_idx ON public.security_events USING btree (created_at DESC);
CREATE UNIQUE INDEX security_kpi_snap_day ON public.security_kpi_snapshots USING btree (snapshot_date);
CREATE INDEX sms_messages_from_created_idx ON public.sms_messages USING btree (sms_from, created_at DESC);
CREATE UNIQUE INDEX sms_messages_message_sid_uk ON public.sms_messages USING btree (message_sid) WHERE (message_sid IS NOT NULL);
CREATE INDEX social_message_conversation_idx ON public.social_message USING btree (conversation_id, created_at DESC);
CREATE UNIQUE INDEX spec_alternative_offer_one_live_per_attr ON public.spec_alternative_offer USING btree (inquiry_id, line_no, attr) WHERE (state = ANY (ARRAY['open'::text, 'accepted'::text]));
CREATE INDEX spec_alternative_offer_open_idx ON public.spec_alternative_offer USING btree (state, reply_by) WHERE (state = 'open'::text);
CREATE UNIQUE INDEX spec_backlog_spec_ref_uidx ON public.spec_backlog USING btree (spec_ref) WHERE (spec_ref IS NOT NULL);
CREATE INDEX spec_backlog_status_idx ON public.spec_backlog USING btree (status, priority);
CREATE INDEX stalled_inquiry_rescue_open_idx ON public.stalled_inquiry_rescue USING btree (flagged_at) WHERE (cleared_at IS NULL);
CREATE INDEX subcategory_agent_map_agent_idx ON public.subcategory_agent_map USING btree (agent_slug);
CREATE UNIQUE INDEX supplier_beneficial_owner_once ON public.supplier_beneficial_owner USING btree (lead_id, lower(btrim(full_name)));
CREATE INDEX supplier_collaboration_event_by_lead ON public.supplier_collaboration_event USING btree (lead_id, created_at);
CREATE INDEX supplier_document_cache_supplier_time_idx ON public.supplier_document_cache USING btree (supplier_id, created_at);
CREATE INDEX supplier_due_payments_due_id_idx ON public.supplier_due_payments USING btree (due_id, paid_on);
CREATE UNIQUE INDEX supplier_dues_stripe_session_key ON public.supplier_dues USING btree (stripe_session_id) WHERE (stripe_session_id IS NOT NULL);
CREATE UNIQUE INDEX supplier_kpi_snap_day ON public.supplier_kpi_snapshots USING btree (snapshot_date);
CREATE INDEX supplier_public_name_norm ON public.supplier_public_name USING btree (norm);
CREATE INDEX supplier_response_watch_open_idx ON public.supplier_response_watch USING btree (opened_at) WHERE ((first_response_at IS NULL) AND (closed_at IS NULL));
CREATE INDEX supplier_voice_note_supplier_recent ON public.supplier_voice_note USING btree (supplier_id, created_at DESC);
CREATE INDEX supplier_whatsapp_consent_ask_phone_idx ON public.supplier_whatsapp_consent_ask USING btree (phone, asked_at DESC);
CREATE INDEX supplier_whatsapp_optin_phone_idx ON public.supplier_whatsapp_optin USING btree (phone);
CREATE INDEX support_case_category_opened_idx ON public.support_case USING btree (category, opened_at);
CREATE INDEX support_case_profile_open_idx ON public.support_case USING btree (customer_profile_id) WHERE (state <> 'closed'::text);
CREATE INDEX support_ceo_report_open_idx ON public.support_ceo_report USING btree (status, next_review_at) WHERE (status = ANY (ARRAY['sent'::text, 'failed'::text, 'blocked'::text]));
CREATE INDEX support_customer_profile_email_idx ON public.support_customer_profile USING btree (email);
CREATE INDEX support_customer_profile_phone_idx ON public.support_customer_profile USING btree (phone_tail);
CREATE INDEX support_document_intake_lead_idx ON public.support_document_intake USING btree (lead_id, received_at DESC);
CREATE INDEX support_document_intake_unattached_idx ON public.support_document_intake USING btree (received_at DESC) WHERE (NOT attached);
CREATE INDEX support_identity_challenge_open_idx ON public.support_identity_challenge USING btree (sender_ref, created_at DESC) WHERE (consumed_at IS NULL);
CREATE INDEX support_knowledge_emb_hnsw ON public.support_knowledge USING hnsw (embedding_gte vector_cosine_ops);
CREATE INDEX support_knowledge_kind_idx ON public.support_knowledge USING btree (record_kind);
CREATE INDEX support_knowledge_search_idx ON public.support_knowledge USING gin (search);
CREATE INDEX support_notification_pending_idx ON public.support_notification USING btree (state, queued_at) WHERE (state = ANY (ARRAY['queued'::text, 'failed'::text]));
CREATE INDEX support_notification_unbridged_idx ON public.support_notification USING btree (queued_at) WHERE (bridged_at IS NULL);
CREATE INDEX support_reply_readability_created_at ON public.support_reply_readability USING btree (created_at);
CREATE INDEX support_reply_readability_e2e_run_tag_idx ON public.support_reply_readability USING btree (e2e_run_tag) WHERE (e2e_run_tag IS NOT NULL);
CREATE UNIQUE INDEX support_root_cause_one_live_idx ON public.support_root_cause USING btree (cause_key, fixture) WHERE (status = ANY (ARRAY['open'::text, 'handed_off'::text, 'measuring'::text, 'not_fallen'::text]));
CREATE INDEX table_export_change_table_changed_idx ON public.table_export_change USING btree (table_name, changed_at, row_key);
CREATE UNIQUE INDEX target_contract_key_version ON public.target_contract USING btree (contract_key, version);
CREATE UNIQUE INDEX target_contract_one_active_per_key ON public.target_contract USING btree (contract_key) WHERE (status = 'active'::text);
CREATE INDEX target_contract_owner ON public.target_contract USING btree (accountable_owner);
CREATE UNIQUE INDEX target_driver_stage ON public.target_driver USING btree (contract_id, stage_order);
CREATE INDEX target_verdict_contract ON public.target_verdict USING btree (contract_id, run_at DESC);
CREATE INDEX taxonomy_trade_proposal_pending ON public.taxonomy_trade_proposal USING btree (created_at) WHERE (status = 'pending'::text);
CREATE UNIQUE INDEX transactions_quote_id_uidx ON public.transactions USING btree (quote_id) WHERE (quote_id IS NOT NULL);
CREATE UNIQUE INDEX transactions_refund_stripe_uidx ON public.transactions USING btree (refund_stripe_id) WHERE (refund_stripe_id IS NOT NULL);
CREATE INDEX undo_log_created_idx ON public.undo_log USING btree (created_at DESC);
CREATE INDEX unsubscribe_refusal_email_at ON public.unsubscribe_refusal USING btree (lower(email), at);
CREATE INDEX unsubscribe_refusal_open ON public.unsubscribe_refusal USING btree (at) WHERE (recovered_at IS NULL);
CREATE UNIQUE INDEX uq_accountant_spend_report_object ON public.accountant_spend_report USING btree (pdf_bucket, pdf_path);
CREATE UNIQUE INDEX uq_company_faq_q ON public.company_faq USING btree (question);
CREATE UNIQUE INDEX uq_doc_backups_dedupe ON public.doc_backups USING btree (dedupe_key);
CREATE UNIQUE INDEX uq_expense_entries_source_msg ON public.expense_entries USING btree (source_msg_id);
CREATE UNIQUE INDEX uq_leads_email_lower ON public.leads USING btree (lower(email)) WHERE ((email IS NOT NULL) AND (email <> ''::text));
CREATE UNIQUE INDEX ux_company_event_dedupe ON public.company_event USING btree (dedupe_key) WHERE (dedupe_key IS NOT NULL);
CREATE INDEX wa_answer_log_unmatched ON public.wa_answer_log USING btree (received_at DESC) WHERE (NOT matched);
CREATE INDEX wa_conversation_open ON public.wa_conversation USING btree (last_seen_at DESC) WHERE (thread_state <> 'resolved'::text);
CREATE INDEX wa_document_intake_lead ON public.wa_document_intake USING btree (lead_id, received_at DESC);
CREATE INDEX wa_inbound_seen_first_seen_idx ON public.wa_inbound_seen USING btree (first_seen_at DESC);
CREATE INDEX wa_sender_quality_reading_read_at_idx ON public.wa_sender_quality_reading USING btree (read_at DESC);
CREATE INDEX wa_turn_conv ON public.wa_turn USING btree (conversation_id, at DESC);
CREATE INDEX yello_email_idx ON public.yello_staging USING btree (email);

