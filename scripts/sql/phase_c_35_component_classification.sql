-- Phase C correction 8 — the 99 components that were labelled "unclassified" and counted as clean.
--
-- phase_c_component held 286 rows reading NO_CALLER_UNCLASSIFIED, 99 of them state-changing and
-- not inactive — exactly the population gate 4 names. The invariant `unclassified_components`
-- reported 0 because its test was `classification = ''`, the empty string, and no row has ever
-- held one. The name of the check and the thing it measured were different subjects.
--
-- Every classification below is DERIVED from evidence, not assigned: pg_trigger for triggers,
-- cron.job (active vs deactivated) for schedules, pg_proc.prosrc for routine-to-routine calls, and
-- the repository's own supabase/functions and src trees for edge and frontend entry points.
-- scripts/phase_c/classify_components.mjs regenerates this file from the same sources.
--
-- Result: 39 have a real internal caller; 60 have none anywhere and therefore may not stay active.
-- Setting activation_state='inactive' changes the REGISTRY's claim about them, not their
-- deployment: the functions remain deployed and callable, and Phase D decides what happens next.

alter table public.phase_c_component drop constraint if exists phase_c_component_classification_ck;
alter table public.phase_c_component add constraint phase_c_component_classification_ck
  check (classification in (
    'ACTIVE_FRONTEND_ENTRY','ACTIVE_EXTERNAL_API','ACTIVE_WEBHOOK_ENTRY','ACTIVE_CRON',
    'ACTIVE_INTERNAL_CALLER','ACTIVE_DATABASE_TRIGGER','ACTIVE_QUEUE_CONSUMER',
    'DEFERRED_RUNTIME_IMPLEMENTATION','INTENTIONALLY_INACTIVE','HISTORICAL_ONLY',
    'INTENTIONALLY_RETIRED',
    -- the vocabulary already in use elsewhere in the table, left intact
    'CANONICAL_KEEP','CANONICAL_BETTER_KEEP','WIRE_TO_CANONICAL','REPAIR_BEFORE_REACTIVATION',
    'INACTIVE_HISTORICAL','NO_CALLER_UNCLASSIFIED'));

with decided (component_id, classification, evidence, new_activation) as (values
  ('dbfn:fn_agent_decision(p_agent text, p_kind text, p_title text, p_recommendation text, p_confidence numeric, p_evidence jsonb, p_risk text, p_detail jsonb)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_ai_gate(p_answer text, p_sources jsonb, p_confidence numeric, p_action text, p_actor text, p_attrs jsonb)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_ap_duplicate_scan()', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_ap_pay(p_bill bigint, p_date date, p_amount numeric, p_from_account text, p_by text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_blueprint_result_prune()', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_brand_scan()', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_budget_create(p_name text, p_year integer, p_by text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_chief_of_staff()', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_collections()', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_decide(p_kind text, p_ctx jsonb, p_actor text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_dispute_open(p_stripe_dispute_id text, p_stripe_charge_id text, p_payment_ref text, p_amount_aed numeric, p_reason text, p_evidence_due_by timestamp with time zone)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_doc_control()', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_employee_responsibilities_backfill()', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_enforce_rls_on_new_tables()', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_experiment_assign(p_key text, p_subject text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_experiment_record(p_key text, p_subject text, p_event text, p_value numeric)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_fa_acquire(p_name text, p_category text, p_acquire_date date, p_cost numeric, p_salvage numeric, p_life_months integer, p_in_service date, p_fund_account text, p_post_gl boolean, p_by text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_fa_dispose(p_asset bigint, p_date date, p_proceeds numeric, p_proceeds_account text, p_by text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_handoff_close(p_id bigint, p_agent_key text, p_closure_evidence jsonb)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_handoff_open(p jsonb)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_handoff_respond(p_id bigint, p_agent_key text, p_decision text, p_reason text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_internal_credential_retire(p_id bigint, p_reason text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_inv_adjust(p_item bigint, p_qty_delta numeric, p_unit_cost numeric, p_offset_account text, p_date date, p_memo text, p_by text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_inv_issue(p_item bigint, p_qty numeric, p_date date, p_ref_type text, p_ref_id text, p_by text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_inv_receive(p_item bigint, p_qty numeric, p_unit_cost numeric, p_date date, p_ref_type text, p_ref_id text, p_post_gl boolean, p_by text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_kb_submit_revision(p_kind text, p_ref text, p_content text, p_author text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_knowledge_rollback(p_run uuid)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_llm_cache_get(p_key text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_llm_cache_put(p_key text, p_fn text, p_task_class text, p_model text, p_response text, p_ttl_minutes integer)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_open_remediation(p_agent_key text, p_failure_class text, p_competency text, p_detail jsonb)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_p2c1_rollback_stage_b6(p_mode text, p_actor text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_p2c1_rollback_stage_b7(p_mode text, p_actor text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_phase1_rollback_rehearse(p_actor text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_po_bill(p_po bigint, p_bill_no text, p_bill_date date, p_due date, p_vat numeric, p_by text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_po_create(p_vendor bigint, p_order_date date, p_expected date, p_memo text, p_lines jsonb, p_created_by text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_po_receive(p_po bigint, p_recv jsonb, p_date date, p_by text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_prompt_publish(p_key text, p_content text, p_owner text, p_rollout integer)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_propose_lesson(p_agent_key text, p_topic text, p_statement text, p_evidence jsonb, p_confidence numeric, p_valid_until date)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_reconcile_licence_blocks(p_grace_days integer)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_refund_amount_resolve(p_stripe_refund_id text, p_amount_fils bigint, p_by text, p_source text, p_note text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_refund_decide(p_refund_id bigint, p_approve boolean, p_decided_by text, p_note text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_specialist_invoke(p_manager text, p_specialist text, p_subject_type text, p_subject_id text, p_reason text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_split_inquiry(p_parent uuid, p_trades text[])', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_supersede_lesson(p_old bigint, p_new bigint, p_reason text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_supplier_autoapprove_clean(p_limit integer)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_supplier_capability_derive(p_limit integer)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_task_commercial_effect(p jsonb)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_trace_edit_is_blocked(p_id uuid)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_undo(p_undo_id uuid, p_reason text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_unsafe_liveness_probe()', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_validate_lesson(p_lesson_id bigint, p_validator text, p_verdict text, p_reason text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:hook_password_verification_attempt(event jsonb)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:run_reveal_nudges()', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('edge:action_worker', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/action_worker', null),
  ('edge:agent_act', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/agent_act', null),
  ('edge:agent_brain', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/agent_brain', null),
  ('edge:agent_train', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/agent_train', null),
  ('edge:analytics_recommend', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/analytics_recommend', null),
  ('edge:apify_scrape', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/apify_scrape', null),
  ('edge:artifact_review', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/artifact_review', null),
  ('edge:category_reqs', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/category_reqs', null),
  ('edge:contact_submit', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/contact_submit', null),
  ('edge:copilot', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/copilot', null),
  ('edge:deploy_next_preview', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/deploy_next_preview', null),
  ('edge:designer', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/designer', null),
  ('edge:dir_ingest', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/dir_ingest', null),
  ('edge:ea_meeting_summary', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/ea_meeting_summary', null),
  ('edge:email_fix', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/email_fix', null),
  ('edge:inquiry_ai', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/inquiry_ai', null),
  ('edge:inquiry_dedup_check', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no cron, no repo caller, not a webhook target', 'inactive'),
  ('edge:kb_corpus_import', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no cron, no repo caller, not a webhook target', 'inactive'),
  ('edge:kb_import', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/kb_import', null),
  ('edge:kb_ingest_text', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/kb_ingest_text', null),
  ('edge:legal_ingest', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/legal_ingest', null),
  ('edge:legal_review', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/legal_review', null),
  ('edge:marketing_draft', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/marketing_draft', null),
  ('edge:match', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/match', null),
  ('edge:mobile_otp', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/mobile_otp', null),
  ('edge:pdpl_erase', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/pdpl_erase', null),
  ('edge:pdpl_request', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no cron, no repo caller, not a webhook target', 'inactive'),
  ('edge:project_consultant', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/project_consultant', null),
  ('edge:prompt_gate', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/prompt_gate', null),
  ('edge:push_src_to_github', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/push_src_to_github', null),
  ('edge:put_src', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/put_src', null),
  ('edge:qa_api', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no cron, no repo caller, not a webhook target', 'inactive'),
  ('edge:rate_dims', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no cron, no repo caller, not a webhook target', 'inactive'),
  ('edge:refund_flow', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no cron, no repo caller, not a webhook target', 'inactive'),
  ('edge:refunds_api', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/refunds_api', null),
  ('edge:reg_fetch', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/reg_fetch', null),
  ('edge:reveal_invoice', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/reveal_invoice', null),
  ('edge:secretary_act', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/secretary_act', null),
  ('edge:site_assistant', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/site_assistant', null),
  ('edge:sup_dob', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no cron, no repo caller, not a webhook target', 'inactive'),
  ('edge:sync_src_from_github', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/sync_src_from_github', null),
  ('edge:translate_page', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/translate_page', null),
  ('edge:video_produce', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/video_produce', null),
  ('edge:voice_otp_capture', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/voice_otp_capture', null),
  ('edge:wa_templates_watch', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/wa_templates_watch', null),
  ('edge:yello_scrape', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/yello_scrape', null))
update public.phase_c_component c
   set classification  = d.classification,
       evidence        = d.evidence,
       activation_state = coalesce(d.new_activation, c.activation_state),
       repair_or_keep_action = case
         when d.classification = 'DEFERRED_RUNTIME_IMPLEMENTATION'
           then 'Phase D: give it a caller and an entry point, or retire it. It is deployed and unreachable.'
         else 'Keep. A caller was found and recorded in evidence.' end,
       measured_at = now()
  from decided d
 where c.component_id = d.component_id;

-- No component may be left carrying the placeholder while it is active and changes state.
do $assert$
declare n int;
begin
  select count(*) into n from public.phase_c_component
   where mutates_state and activation_state not in ('inactive','disabled')
     and classification = 'NO_CALLER_UNCLASSIFIED';
  if n <> 0 then
    raise exception 'phase_c_component: % active state-changing rows are still NO_CALLER_UNCLASSIFIED', n
      using errcode = '23514';
  end if;
end $assert$;
