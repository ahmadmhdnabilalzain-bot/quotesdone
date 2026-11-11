-- model_policy_states_the_effort_of_every_task_class.sql
-- Assigned: it_engineer. Founder ruling 1630 (11 Nov 2026): reasoning effort is set by consequence. HIGH for anything that
-- decides, reads documents, prices, matches, or writes on the company's behalf; MEDIUM for conversations (deepened per turn
-- for a complaint, a dispute, a refund, a price challenge or a multi-part question); LOW only for simple sorting, and only
-- where a side-by-side on identical inputs shows low answers as high does (ruling 1618).
--
-- MEASURED (11 Nov 2026): model_policy had 100 rows and no effort anywhere in the database. Effort lived in six literal
-- 'low' call sites, one 'high' (reask.ts), and otherwise the model's own default. The one map is now
-- supabase/functions/_shared/effort_policy.ts EFFORT_BY_CLASS, which the gateway applies to every call that names no effort.
-- This file puts the same map on the policy row, so the routing table states the effort beside the model it picks.
-- scripts/checks/the_effort_policy_is_one_map.test.mjs fails if this list and the code map differ by one class or one value.
-- WHAT IT DOES NOT CHANGE: no model, tier or fallback; the gateway still reads the code map (switching it to read this
-- column is a one-line change once this is applied). No row is low.
-- Pending: scripts/sql/pending/model_policy_states_the_effort_of_every_task_class.txt
-- prevented by: scripts/checks/the_effort_policy_is_one_map.test.mjs

alter table public.model_policy add column if not exists effort text;
alter table public.model_policy drop constraint if exists model_policy_effort_ck;
alter table public.model_policy add constraint model_policy_effort_ck check (effort is null or effort in ('low', 'medium', 'high'));
comment on column public.model_policy.effort is
  'Reasoning effort by consequence (founder ruling 1630). Mirrors supabase/functions/_shared/effort_policy.ts EFFORT_BY_CLASS.';

update public.model_policy p set effort = v.effort
  from (values
  ('accountant_expense_classification', 'high'),
  ('accountant_receipt_extraction', 'high'),
  ('accountant_weekly_report', 'high'),
  ('agent_reasoning', 'high'),
  ('approval_threshold', 'high'),
  ('brand_rule_check', 'high'),
  ('calendar_scheduling', 'high'),
  ('category_classification', 'high'),
  ('ceo__internal_judgement', 'high'),
  ('ceo__knowledge_validation', 'high'),
  ('ceo_approval_decision', 'high'),
  ('ceo_article_review', 'high'),
  ('ceo_judgement', 'high'),
  ('ceo_strategic_planning', 'high'),
  ('chief_of_staff_decision', 'high'),
  ('content_drafting', 'high'),
  ('contract_analysis', 'high'),
  ('conversation_reply', 'medium'),
  ('currency_conversion', 'high'),
  ('customer_communication', 'medium'),
  ('customer_portal_assistant', 'medium'),
  ('date_calculation', 'high'),
  ('department_planning', 'high'),
  ('document_extraction', 'high'),
  ('document_extraction_multimodal', 'high'),
  ('drawing_and_boq_analysis', 'high'),
  ('drawing_boq_confirm', 'high'),
  ('drawing_vision_count', 'high'),
  ('duplicate_detection', 'high'),
  ('edge_case_escalation', 'high'),
  ('email_triage', 'medium'),
  ('engineering_reasoning', 'high'),
  ('executive_report', 'high'),
  ('file_operations', 'high'),
  ('finance_analysis', 'high'),
  ('general_drafting', 'high'),
  ('health_ping', 'medium'),
  ('identity_redaction_verify', 'high'),
  ('inbound_email', 'medium'),
  ('inquiry_qualification_conversation', 'medium'),
  ('intent_detection', 'medium'),
  ('internal_judgement', 'high'),
  ('json_extraction', 'high'),
  ('json_extraction_text', 'high'),
  ('knowledge_ingestion', 'high'),
  ('knowledge_research', 'high'),
  ('knowledge_validation', 'high'),
  ('kpi_calculation', 'high'),
  ('kpi_measurement', 'high'),
  ('legal_analysis', 'high'),
  ('marketing_article_draft', 'high'),
  ('marketing_article_revise', 'high'),
  ('marketing_copy', 'high'),
  ('marketing_evaluate', 'high'),
  ('marketing_geo_online', 'high'),
  ('marketing_geo_search', 'high'),
  ('marketing_image', 'high'),
  ('marketing_plan', 'high'),
  ('marketing_plan_defend', 'high'),
  ('marketing_quality_review', 'high'),
  ('marketing_research', 'high'),
  ('marketing_watch', 'high'),
  ('memory_retrieval', 'high'),
  ('missing_fields_detection', 'high'),
  ('money_state_change', 'high'),
  ('note_capture', 'high'),
  ('ocr', 'high'),
  ('ocr_cleanup', 'high'),
  ('procurement_reasoning', 'high'),
  ('quote_comparison', 'high'),
  ('redaction_detection', 'high'),
  ('reflection_and_learning', 'high'),
  ('resend_inbound', 'medium'),
  ('rfq_routing', 'high'),
  ('routine_employee_reasoning', 'high'),
  ('sales_engineer__document_extraction', 'high'),
  ('sales_engineer__json_extraction', 'high'),
  ('sales_engineer__knowledge_validation', 'high'),
  ('sales_engineer__procurement_reasoning', 'high'),
  ('sales_engineer_reasoning', 'high'),
  ('seat_deliberation_blind', 'high'),
  ('seat_deliberation_compare', 'high'),
  ('security_incident_analysis', 'high'),
  ('speech_transcription', 'high'),
  ('status_reply', 'medium'),
  ('summarization', 'high'),
  ('supplier_communication', 'medium'),
  ('supplier_matching', 'high'),
  ('supplier_scoring', 'high'),
  ('supplier_trade_choice', 'high'),
  ('support_ai', 'medium'),
  ('translation', 'high'),
  ('translation_general', 'high'),
  ('vat_calculation', 'high'),
  ('vision', 'high'),
  ('visitor_chat', 'medium'),
  ('voice_draft', 'medium'),
  ('wa_inbound', 'medium'),
  ('workflow_routing', 'high'),
  ('workflow_state_and_permissions', 'high')
  ) as v(task_class, effort)
 where p.task_class = v.task_class and p.effort is distinct from v.effort;

-- verdict: every policy row states an effort, and none is low
select case
  when exists (select 1 from public.model_policy where effort is null)
    then 'PROBE FAILED: a model_policy row has no effort: ' || (select string_agg(task_class, ', ') from public.model_policy where effort is null)
  when exists (select 1 from public.model_policy where effort = 'low')
    then 'PROBE FAILED: a row is low without a side-by-side'
  else 'PROBE OK' end as verdict;
