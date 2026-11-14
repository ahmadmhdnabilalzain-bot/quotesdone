-- ===== TRIGGERS =====
CREATE TRIGGER a00_append_only BEFORE DELETE OR UPDATE ON public.accountant_issued_document FOR EACH ROW EXECUTE FUNCTION trg_accountant_issued_document_is_append_only();
CREATE TRIGGER a10_accountant_knowledge_search_vector BEFORE INSERT OR UPDATE OF title, tags, content ON public.accountant_knowledge FOR EACH ROW EXECUTE FUNCTION fn_accountant_knowledge_search_vector();
CREATE TRIGGER z_ml_vectors_stale AFTER UPDATE OF title, content ON public.accountant_knowledge FOR EACH ROW WHEN (((old.title IS DISTINCT FROM new.title) OR (old.content IS DISTINCT FROM new.content))) EXECUTE FUNCTION fn_ml_vectors_stale('accountant_knowledge', 'record_id');
CREATE TRIGGER z_ml_vectors_stale_del AFTER DELETE ON public.accountant_knowledge FOR EACH ROW EXECUTE FUNCTION fn_ml_vectors_stale('accountant_knowledge', 'record_id');
CREATE TRIGGER zz_knowledge_library_mirror AFTER INSERT OR DELETE OR UPDATE OF record_id, title, content, tags, pack_id, source_ids, epistemic_status, runtime_index_eligible, embedding_gte ON public.accountant_knowledge FOR EACH ROW EXECUTE FUNCTION fn_knowledge_library_mirror();
CREATE TRIGGER t10_action_execution_set_author BEFORE INSERT ON public.action_execution FOR EACH ROW EXECUTE FUNCTION fn_action_execution_set_author();
CREATE TRIGGER a00_ad_spend_ceiling_guard BEFORE INSERT ON public.ad_decision FOR EACH ROW EXECUTE FUNCTION fn_ad_spend_ceiling_guard();
CREATE TRIGGER a00_agent_action_resolve_addressee BEFORE INSERT ON public.agent_actions FOR EACH ROW EXECUTE FUNCTION fn_agent_action_resolve_addressee();
CREATE TRIGGER a01_handoff_carries_its_note BEFORE INSERT OR UPDATE ON public.agent_actions FOR EACH ROW WHEN (((new.kind = 'handoff'::text) AND (NOT (COALESCE((new.detail -> 'summary'::text), '{}'::jsonb) ?& ARRAY['known'::text, 'tried'::text, 'needed'::text, 'evidence'::text, 'context'::text, 'decision'::text, 'open_asks'::text, 'deadline'::text])))) EXECUTE FUNCTION trg_handoff_carries_its_note();
CREATE TRIGGER a02_handoff_close_cites_its_note BEFORE INSERT OR UPDATE OF status, evidence ON public.agent_actions FOR EACH ROW WHEN (((new.kind = 'handoff'::text) AND (new.status = 'done'::text))) EXECUTE FUNCTION trg_handoff_close_cites_its_note();
CREATE TRIGGER trg_category_knowledge_promote AFTER UPDATE ON public.agent_actions FOR EACH ROW WHEN ((new.kind = 'category_knowledge'::text)) EXECUTE FUNCTION fn_category_knowledge_promote();
CREATE TRIGGER trg_dedupe_it_incident BEFORE INSERT ON public.agent_actions FOR EACH ROW EXECUTE FUNCTION dedupe_it_incident();
CREATE TRIGGER trg_governance_stamp BEFORE INSERT ON public.agent_actions FOR EACH ROW EXECUTE FUNCTION fn_governance_stamp();
CREATE TRIGGER trg_invite_week_activate AFTER UPDATE ON public.agent_actions FOR EACH ROW EXECUTE FUNCTION fn_invite_week_activate();
CREATE TRIGGER trg_sales_engineer_tells_customer_invoice_ready AFTER INSERT ON public.agent_actions FOR EACH ROW EXECUTE FUNCTION fn_sales_engineer_tells_customer_invoice_ready();
CREATE TRIGGER z60_backup_refile_only_it_engineer_closes BEFORE UPDATE OF status ON public.agent_actions FOR EACH ROW EXECUTE FUNCTION trg_backup_refile_only_it_engineer_closes();
CREATE TRIGGER z61_handoff_only_originator_closes BEFORE UPDATE OF status ON public.agent_actions FOR EACH ROW EXECUTE FUNCTION trg_handoff_only_originator_closes();
CREATE TRIGGER z62_new_bug_closes_with_learning BEFORE UPDATE OF status ON public.agent_actions FOR EACH ROW EXECUTE FUNCTION trg_new_bug_closes_with_learning();
CREATE TRIGGER z90_agent_actions_export_change_del AFTER DELETE ON public.agent_actions REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION trg_table_export_change('id', 'id,agent,kind,status,risk,title,recommendation,detail,target_table,target_id,created_at,decided_at,decided_by,confidence,evidence,escalated,escalation_reason,decision_log_id,alternatives,assumptions,expected_impact,cost');
CREATE TRIGGER z90_agent_actions_export_change_ins AFTER INSERT ON public.agent_actions REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION trg_table_export_change('id', 'id,agent,kind,status,risk,title,recommendation,detail,target_table,target_id,created_at,decided_at,decided_by,confidence,evidence,escalated,escalation_reason,decision_log_id,alternatives,assumptions,expected_impact,cost');
CREATE TRIGGER z90_agent_actions_export_change_trunc AFTER TRUNCATE ON public.agent_actions FOR EACH STATEMENT EXECUTE FUNCTION trg_table_export_change('id', 'id,agent,kind,status,risk,title,recommendation,detail,target_table,target_id,created_at,decided_at,decided_by,confidence,evidence,escalated,escalation_reason,decision_log_id,alternatives,assumptions,expected_impact,cost');
CREATE TRIGGER z90_agent_actions_export_change_upd AFTER UPDATE ON public.agent_actions REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION trg_table_export_change('id', 'id,agent,kind,status,risk,title,recommendation,detail,target_table,target_id,created_at,decided_at,decided_by,confidence,evidence,escalated,escalation_reason,decision_log_id,alternatives,assumptions,expected_impact,cost');
CREATE TRIGGER zzz_zz_agent_action_fill_fields BEFORE INSERT OR UPDATE ON public.agent_actions FOR EACH ROW EXECUTE FUNCTION fn_agent_actions_fill_alternatives();
CREATE TRIGGER trg_knowledge_provenance_stamp BEFORE INSERT ON public.agent_knowledge FOR EACH ROW EXECUTE FUNCTION fn_knowledge_provenance_stamp();
CREATE TRIGGER trg_undo_agent_knowledge BEFORE DELETE OR UPDATE ON public.agent_knowledge FOR EACH ROW EXECUTE FUNCTION trg_undo_capture('id');
CREATE TRIGGER z_ml_vectors_stale AFTER UPDATE OF topic, content ON public.agent_knowledge FOR EACH ROW WHEN (((old.topic IS DISTINCT FROM new.topic) OR (old.content IS DISTINCT FROM new.content))) EXECUTE FUNCTION fn_ml_vectors_stale('agent_knowledge', 'id');
CREATE TRIGGER z_ml_vectors_stale_del AFTER DELETE ON public.agent_knowledge FOR EACH ROW EXECUTE FUNCTION fn_ml_vectors_stale('agent_knowledge', 'id');
CREATE TRIGGER zz_knowledge_library_mirror AFTER INSERT OR DELETE OR UPDATE OF id, topic, content, agent_key, source_ref, validation_status, embedding_gte ON public.agent_knowledge FOR EACH ROW EXECUTE FUNCTION fn_knowledge_library_mirror();
CREATE TRIGGER trg_audit_agent_run AFTER INSERT ON public.agent_runs FOR EACH ROW EXECUTE FUNCTION trg_audit_agent_run();
CREATE TRIGGER trg_emit_test_failed_ins AFTER INSERT ON public.agent_runs FOR EACH ROW EXECUTE FUNCTION fn_emit_test_failed_ins();
CREATE TRIGGER trg_emit_test_failed_upd AFTER UPDATE ON public.agent_runs FOR EACH ROW EXECUTE FUNCTION fn_emit_test_failed();
CREATE TRIGGER trg_ai_cost_attribute BEFORE INSERT ON public.ai_cost_log FOR EACH ROW EXECUTE FUNCTION trg_ai_cost_attribute();
CREATE TRIGGER trg_ai_cost_log_e2e_run_tag BEFORE INSERT ON public.ai_cost_log FOR EACH ROW EXECUTE FUNCTION fn_ai_cost_log_e2e_run_tag();
CREATE TRIGGER trg_ai_cost_log_review_family BEFORE INSERT ON public.ai_cost_log FOR EACH ROW EXECUTE FUNCTION trg_ai_cost_log_review_family();
CREATE TRIGGER trg_ai_cost_log_reviewer_tier BEFORE INSERT ON public.ai_cost_log FOR EACH ROW EXECUTE FUNCTION trg_ai_cost_log_reviewer_tier();
CREATE TRIGGER z_ai_cost_log_releases_rehearsal_reservation AFTER INSERT ON public.ai_cost_log FOR EACH ROW EXECUTE FUNCTION fn_ai_cost_log_releases_rehearsal_reservation();
CREATE TRIGGER trg_quality_snapshot_resolve_agent BEFORE INSERT ON public.ai_quality_snapshots FOR EACH ROW EXECUTE FUNCTION fn_quality_snapshot_resolve_agent();
CREATE TRIGGER trg_ap_bill_dupe_guard BEFORE INSERT OR UPDATE ON public.ap_bills FOR EACH ROW EXECUTE FUNCTION fn_ap_bill_dupe_guard();
CREATE TRIGGER trg_ap_pay_block_held BEFORE UPDATE ON public.ap_bills FOR EACH ROW EXECUTE FUNCTION fn_ap_pay_block_held();
CREATE TRIGGER trg_emit_invoice_received AFTER INSERT ON public.ap_bills FOR EACH ROW EXECUTE FUNCTION fn_emit_invoice_received();
CREATE TRIGGER a50_invite_cap_allocation AFTER UPDATE ON public.app_secrets FOR EACH ROW WHEN ((old.value IS DISTINCT FROM new.value)) EXECUTE FUNCTION trg_invite_cap_allocation();
CREATE TRIGGER a60_invite_lane_since AFTER INSERT OR UPDATE ON public.app_secrets FOR EACH ROW WHEN ((new.key = 'invite_lane_enabled'::text)) EXECUTE FUNCTION trg_invite_lane_since();
CREATE TRIGGER trg_app_secrets_no_paid_ai_founder_switch BEFORE DELETE OR UPDATE ON public.app_secrets FOR EACH ROW EXECUTE FUNCTION fn_app_secrets_no_paid_ai_guard();
CREATE TRIGGER trg_app_secrets_no_paid_ai_stays_off BEFORE INSERT OR UPDATE ON public.app_secrets FOR EACH ROW EXECUTE FUNCTION fn_app_secrets_no_paid_ai_stays_off();
CREATE TRIGGER trg_audit_app_secrets AFTER INSERT OR DELETE OR UPDATE ON public.app_secrets FOR EACH ROW EXECUTE FUNCTION fn_security_audit();
CREATE TRIGGER trg_autonomy_control_guard BEFORE INSERT OR DELETE OR UPDATE ON public.app_secrets FOR EACH ROW EXECUTE FUNCTION fn_autonomy_control_guard();
CREATE TRIGGER trg_protect_app_secret BEFORE INSERT OR DELETE OR UPDATE ON public.app_secrets FOR EACH ROW EXECUTE FUNCTION fn_protect_app_secret();
CREATE TRIGGER a00_artifact_review_author_is_not_reviewer BEFORE INSERT OR UPDATE ON public.artifact_review FOR EACH ROW EXECUTE FUNCTION fn_artifact_review_valid();
CREATE TRIGGER a00_assistant_logs_e2e_run_tag BEFORE INSERT ON public.assistant_logs FOR EACH ROW EXECUTE FUNCTION fn_ai_cost_log_e2e_run_tag();
CREATE TRIGGER z50_support_wire_widget AFTER INSERT ON public.assistant_logs FOR EACH ROW EXECUTE FUNCTION fn_support_wire_widget();
CREATE TRIGGER z51_support_classify_widget AFTER INSERT OR UPDATE OF answered, matched_ids ON public.assistant_logs FOR EACH ROW EXECUTE FUNCTION fn_support_classify_widget();
CREATE TRIGGER a06_names_no_supplier BEFORE INSERT OR UPDATE OF title, excerpt, meta_desc, body_html ON public.blog_posts FOR EACH ROW EXECUTE FUNCTION trg_published_text_names_no_supplier();
CREATE TRIGGER trg_undo_business_rules BEFORE DELETE OR UPDATE ON public.business_rules FOR EACH ROW EXECUTE FUNCTION trg_undo_capture('id');
CREATE TRIGGER category_key_asked AFTER INSERT ON public.category_specs FOR EACH ROW EXECUTE FUNCTION trg_category_key_asked();
CREATE TRIGGER a04_ceo_approval_carries_its_reasons BEFORE INSERT ON public.ceo_approval FOR EACH ROW EXECUTE FUNCTION trg_ceo_approval_carries_its_reasons();
CREATE TRIGGER a05_ceo_refund_approval_checks_the_process BEFORE INSERT ON public.ceo_approval FOR EACH ROW EXECUTE FUNCTION fn_ceo_refund_approval_checks_the_process();
CREATE TRIGGER z00_ceo_approval_append_only BEFORE UPDATE ON public.ceo_approval FOR EACH ROW EXECUTE FUNCTION fn_ceo_approval_append_only();
CREATE TRIGGER z90_case_memory AFTER INSERT ON public.ceo_approval FOR EACH ROW EXECUTE FUNCTION trg_case_memory_ceo_approval();
CREATE TRIGGER z20_ceo_command_state_guard BEFORE UPDATE ON public.ceo_command FOR EACH ROW EXECUTE FUNCTION fn_ceo_command_state_guard();
CREATE TRIGGER z90_case_memory AFTER INSERT OR UPDATE OF outcome, reading_after, founder_answer ON public.ceo_decision_log FOR EACH ROW EXECUTE FUNCTION trg_case_memory_ceo_decision_log();
CREATE TRIGGER a00_ceo_decision_round_rules BEFORE INSERT ON public.ceo_decision_round FOR EACH ROW EXECUTE FUNCTION trg_ceo_decision_round_rules();
CREATE TRIGGER a01_ceo_decision_round_append_only BEFORE DELETE OR UPDATE ON public.ceo_decision_round FOR EACH ROW EXECUTE FUNCTION trg_ceo_decision_round_append_only();
CREATE TRIGGER z50_ceo_decision_round_follows_through AFTER INSERT ON public.ceo_decision_round FOR EACH ROW EXECUTE FUNCTION trg_ceo_decision_round_follows_through();
CREATE TRIGGER a04_ceo_experiment_carries_its_reasons BEFORE UPDATE ON public.ceo_experiment FOR EACH ROW EXECUTE FUNCTION trg_ceo_experiment_carries_its_reasons();
CREATE TRIGGER a04_ceo_improvement_carries_its_reasons BEFORE INSERT OR UPDATE ON public.ceo_improvement FOR EACH ROW EXECUTE FUNCTION trg_ceo_improvement_carries_its_reasons();
CREATE TRIGGER a10_ceo_knowledge_search_vector BEFORE INSERT OR UPDATE OF title, tags, body ON public.ceo_knowledge FOR EACH ROW EXECUTE FUNCTION fn_ceo_knowledge_search_vector();
CREATE TRIGGER trg_ceo_knowledge_text_change_clears_embedding BEFORE UPDATE OF title, body ON public.ceo_knowledge FOR EACH ROW EXECUTE FUNCTION fn_knowledge_text_change_clears_embedding();
CREATE TRIGGER z_ml_vectors_stale AFTER UPDATE OF title, body ON public.ceo_knowledge FOR EACH ROW WHEN (((old.title IS DISTINCT FROM new.title) OR (old.body IS DISTINCT FROM new.body))) EXECUTE FUNCTION fn_ml_vectors_stale('ceo_knowledge', 'record_id');
CREATE TRIGGER z_ml_vectors_stale_del AFTER DELETE ON public.ceo_knowledge FOR EACH ROW EXECUTE FUNCTION fn_ml_vectors_stale('ceo_knowledge', 'record_id');
CREATE TRIGGER zz_knowledge_library_mirror AFTER INSERT OR DELETE OR UPDATE OF record_id, title, body, tags, language, source_path, pack_fingerprint, source_ids, review_status, runtime_index_eligible, embedding_gte ON public.ceo_knowledge FOR EACH ROW EXECUTE FUNCTION fn_knowledge_library_mirror();
CREATE TRIGGER ceo_weekly_report_carries_the_cash_forecast BEFORE INSERT OR UPDATE OF body ON public.ceo_weekly_report FOR EACH ROW EXECUTE FUNCTION fn_ceo_weekly_report_carries_the_cash_forecast();
CREATE TRIGGER ceo_weekly_report_carries_the_plan BEFORE INSERT OR UPDATE OF body ON public.ceo_weekly_report FOR EACH ROW EXECUTE FUNCTION fn_ceo_weekly_report_carries_the_plan();
CREATE TRIGGER z50_learning_section BEFORE INSERT OR UPDATE OF body ON public.ceo_weekly_report FOR EACH ROW EXECUTE FUNCTION trg_ceo_weekly_report_learning();
CREATE TRIGGER trg_audit_collections_config AFTER INSERT OR DELETE OR UPDATE ON public.collections_config FOR EACH ROW EXECUTE FUNCTION fn_security_audit();
CREATE TRIGGER trg_company_event_dispatch AFTER INSERT ON public.company_event FOR EACH STATEMENT EXECUTE FUNCTION trg_company_event_dispatch();
CREATE TRIGGER trg_emit_health_degraded AFTER INSERT ON public.company_event FOR EACH ROW WHEN (((new.event_type = 'os.health_changed'::text) AND (new.payload ? 'previous_score'::text) AND (new.payload ? 'score'::text) AND ((new.payload ->> 'score'::text) ~ '^[0-9.]+$'::text) AND ((new.payload ->> 'previous_score'::text) ~ '^[0-9.]+$'::text) AND (((new.payload ->> 'score'::text))::numeric < ((new.payload ->> 'previous_score'::text))::numeric))) EXECUTE FUNCTION fn_emit_health_degraded();
CREATE TRIGGER trg_priority_backlog_reorder AFTER INSERT ON public.company_event FOR EACH ROW WHEN ((new.event_type = 'priority.updated'::text)) EXECUTE FUNCTION fn_priority_backlog_reorder();
CREATE TRIGGER trg_company_faq_text_change_clears_embedding BEFORE UPDATE OF question, answer ON public.company_faq FOR EACH ROW EXECUTE FUNCTION fn_company_faq_text_change_clears_embedding();
CREATE TRIGGER z60_support_faq_records_its_root_cause AFTER INSERT OR UPDATE OF tags ON public.company_faq FOR EACH ROW EXECUTE FUNCTION fn_support_faq_records_its_root_cause();
CREATE TRIGGER z_ml_vectors_stale AFTER UPDATE OF question, answer ON public.company_faq FOR EACH ROW WHEN (((old.question IS DISTINCT FROM new.question) OR (old.answer IS DISTINCT FROM new.answer))) EXECUTE FUNCTION fn_ml_vectors_stale('company_faq', 'id');
CREATE TRIGGER z_ml_vectors_stale_del AFTER DELETE ON public.company_faq FOR EACH ROW EXECUTE FUNCTION fn_ml_vectors_stale('company_faq', 'id');
CREATE TRIGGER trg_goal_cascade AFTER INSERT OR UPDATE ON public.company_goals FOR EACH ROW EXECUTE FUNCTION trg_goal_cascade();
CREATE TRIGGER trg_undo_company_goals BEFORE DELETE OR UPDATE ON public.company_goals FOR EACH ROW EXECUTE FUNCTION trg_undo_capture('key');
CREATE TRIGGER trg_emit_competitor_pricing_changed AFTER UPDATE ON public.competitor FOR EACH ROW WHEN ((((COALESCE(old.business_model, ''::text) IS DISTINCT FROM COALESCE(new.business_model, ''::text)) OR (COALESCE(old.what_they_do, ''::text) IS DISTINCT FROM COALESCE(new.what_they_do, ''::text))) AND ((COALESCE(new.business_model, ''::text) || COALESCE(new.what_they_do, ''::text)) ~* '(price|pricing|fee|commission|%|subscription|free)'::text))) EXECUTE FUNCTION fn_emit_competitor_pricing_changed();
CREATE TRIGGER z90_case_memory AFTER INSERT OR UPDATE OF status, final_response, final_response_at ON public.complaint_tickets FOR EACH ROW EXECUTE FUNCTION trg_case_memory_complaint();
CREATE TRIGGER z91_judgement_outcome AFTER UPDATE OF final_response_at ON public.complaint_tickets FOR EACH ROW EXECUTE FUNCTION trg_judgement_outcome();
CREATE TRIGGER z92_outcome_learning AFTER INSERT ON public.complaint_tickets FOR EACH ROW EXECUTE FUNCTION trg_outcome_learning();
CREATE TRIGGER trg_emit_regulation_changed AFTER UPDATE OF last_changed_at ON public.compliance_sources FOR EACH ROW WHEN (((new.last_changed_at IS NOT NULL) AND (COALESCE(old.last_changed_at, '-infinity'::timestamp with time zone) IS DISTINCT FROM new.last_changed_at))) EXECUTE FUNCTION fn_emit_regulation_changed();
CREATE TRIGGER contact_merge_audit_append_only BEFORE DELETE OR UPDATE ON public.contact_merge_audit FOR EACH ROW EXECUTE FUNCTION fn_contact_merge_audit_is_append_only();
CREATE TRIGGER contact_merge_audit_no_truncate BEFORE TRUNCATE ON public.contact_merge_audit FOR EACH STATEMENT EXECUTE FUNCTION fn_contact_merge_audit_is_append_only();
CREATE TRIGGER z55_contact_message_reaches_customer_support AFTER INSERT ON public.contact_messages FOR EACH ROW EXECUTE FUNCTION trg_z55_contact_message_reaches_customer_support();
CREATE TRIGGER t_emit_content_drafted AFTER INSERT ON public.content_drafts FOR EACH ROW EXECUTE FUNCTION fn_emit_content_drafted();
CREATE TRIGGER trg_emit_campaign_published_content AFTER INSERT OR UPDATE OF status ON public.content_drafts FOR EACH ROW WHEN ((new.status = 'posted'::text)) EXECUTE FUNCTION fn_emit_campaign_published_from_content();
CREATE TRIGGER trg_control_mode_session_mfa_is_real BEFORE INSERT ON public.control_mode_session FOR EACH ROW EXECUTE FUNCTION fn_control_mode_session_mfa_is_real();
CREATE TRIGGER t_emit_churn_signal AFTER INSERT OR UPDATE ON public.customer_score FOR EACH ROW EXECUTE FUNCTION fn_emit_churn_signal();
CREATE TRIGGER trg_block_disposable_customers BEFORE INSERT ON public.customers FOR EACH ROW EXECUTE FUNCTION block_disposable_signup();
CREATE TRIGGER trg_emit_customer_registered AFTER INSERT ON public.customers FOR EACH ROW EXECUTE FUNCTION fn_emit_customer_registered();
CREATE TRIGGER trg_sign_customer AFTER UPDATE ON public.customers FOR EACH ROW WHEN (((new.email_verified IS TRUE) AND (old.email_verified IS DISTINCT FROM new.email_verified) AND (new.signed_terms_url IS NULL))) EXECUTE FUNCTION qd_sign_customer();
CREATE TRIGGER z40_customer_account_active_notice AFTER UPDATE OF tos_accepted_at ON public.customers FOR EACH ROW WHEN (((old.tos_accepted_at IS NULL) AND (new.tos_accepted_at IS NOT NULL))) EXECUTE FUNCTION fn_customer_account_active_notice();
CREATE TRIGGER z70_document_landed_kicks_backup AFTER INSERT OR UPDATE OF signed_terms_path ON public.customers FOR EACH STATEMENT EXECUTE FUNCTION trg_document_landed_kicks_backup();
CREATE TRIGGER declog_immutable BEFORE DELETE OR UPDATE ON public.decision_log FOR EACH ROW EXECUTE FUNCTION trg_declog_immutable();
CREATE TRIGGER trg_undo_decision_policy BEFORE DELETE OR UPDATE ON public.decision_policy FOR EACH ROW EXECUTE FUNCTION trg_undo_capture('key');
CREATE TRIGGER z90_case_memory AFTER INSERT OR UPDATE OF status, actual_outcome, recommendation ON public.decision_record FOR EACH ROW EXECUTE FUNCTION trg_case_memory_decision_record();
CREATE TRIGGER a00_decision_trace_immutable BEFORE UPDATE ON public.decision_trace FOR EACH ROW EXECUTE FUNCTION fn_decision_trace_immutable();
CREATE TRIGGER trg_department_budget_keeps_a_ceiling_per_caller BEFORE DELETE ON public.department_budget FOR EACH ROW EXECUTE FUNCTION trg_department_budget_keeps_a_ceiling_per_caller();
CREATE TRIGGER trg_department_budget_no_truncate BEFORE TRUNCATE ON public.department_budget FOR EACH STATEMENT EXECUTE FUNCTION trg_department_budget_keeps_a_ceiling_per_caller();
CREATE TRIGGER trg_undo_department_objective BEFORE DELETE OR UPDATE ON public.department_objective FOR EACH ROW EXECUTE FUNCTION trg_undo_capture('id');
CREATE TRIGGER a10_doc_backups_admit BEFORE INSERT ON public.doc_backups FOR EACH ROW EXECUTE FUNCTION trg_doc_backups_admit();
CREATE TRIGGER supplier_document_subject_asked AFTER INSERT OR UPDATE OF file_name, status ON public.documents FOR EACH ROW EXECUTE FUNCTION trg_supplier_document_subject_asked();
CREATE TRIGGER version_document AFTER INSERT OR UPDATE OF extracted ON public.documents FOR EACH ROW EXECUTE FUNCTION trg_version_document();
CREATE TRIGGER z50_unsubscribe_withdraws_promotional_consent AFTER INSERT OR UPDATE OF reason ON public.email_suppressions FOR EACH ROW EXECUTE FUNCTION fn_unsubscribe_withdraws_promotional_consent();
CREATE TRIGGER z92_outcome_learning AFTER INSERT ON public.email_suppressions FOR EACH ROW EXECUTE FUNCTION trg_outcome_learning();
CREATE TRIGGER trg_undo_employee_authority BEFORE DELETE OR UPDATE ON public.employee_authority FOR EACH ROW EXECUTE FUNCTION trg_undo_capture('agent_key');
CREATE TRIGGER trg_undo_employee_kpi BEFORE DELETE OR UPDATE ON public.employee_kpi FOR EACH ROW EXECUTE FUNCTION trg_undo_capture('id');
CREATE TRIGGER trg_emit_invoice_received_expense AFTER INSERT ON public.expense_entries FOR EACH ROW EXECUTE FUNCTION fn_emit_invoice_received_from_expense();
CREATE TRIGGER z90_case_memory AFTER INSERT OR UPDATE OF category, vendor, note ON public.expense_entries FOR EACH ROW EXECUTE FUNCTION trg_case_memory_expense();
CREATE TRIGGER z91_judgement_outcome AFTER UPDATE OF category ON public.expense_entries FOR EACH ROW EXECUTE FUNCTION trg_judgement_outcome();
CREATE TRIGGER t_emit_customer_complaint AFTER INSERT ON public.feedback FOR EACH ROW WHEN ((((new.rating IS NOT NULL) AND (new.rating <= (2)::numeric)) OR ((new.source IS NOT NULL) AND (lower(new.source) ~~ '%complaint%'::text)))) EXECUTE FUNCTION fn_emit_customer_complaint();
CREATE TRIGGER t_support_low_csat_opens_recovery AFTER INSERT ON public.feedback FOR EACH ROW WHEN (((new.kind = 'csat'::text) AND (new.rating <= (2)::numeric) AND (new.case_id IS NOT NULL))) EXECUTE FUNCTION fn_support_low_csat_opens_recovery();
CREATE TRIGGER z90_security_detect AFTER INSERT ON public.file_scan FOR EACH ROW WHEN ((new.verdict = ANY (ARRAY['malicious'::text, 'suspicious'::text]))) EXECUTE FUNCTION fn_security_detect_on_evidence();
CREATE TRIGGER trg_normalize_founder_alert_level BEFORE INSERT OR UPDATE ON public.founder_alerts FOR EACH ROW EXECUTE FUNCTION fn_normalize_founder_alert_level();
CREATE TRIGGER trg_founder_hold_is_lifted_only_by_its_flag BEFORE DELETE OR UPDATE ON public.founder_hold FOR EACH ROW EXECUTE FUNCTION fn_founder_hold_is_lifted_only_by_its_flag();
CREATE TRIGGER a10_founder_instruction_needs_evidence BEFORE INSERT OR UPDATE ON public.founder_instruction FOR EACH ROW EXECUTE FUNCTION fn_founder_instruction_needs_evidence();
CREATE TRIGGER trg_founder_mail_policy_history AFTER INSERT OR DELETE OR UPDATE ON public.founder_mail_policy FOR EACH ROW EXECUTE FUNCTION fn_founder_mail_policy_history_write();
CREATE TRIGGER a05_gl_period_lock BEFORE INSERT OR UPDATE ON public.gl_journal FOR EACH ROW EXECUTE FUNCTION fn_gl_period_lock();
CREATE TRIGGER trg_gl_journal_immutable BEFORE DELETE OR UPDATE ON public.gl_journal FOR EACH ROW EXECUTE FUNCTION fn_gl_journal_immutable();
CREATE TRIGGER trg_gl_journal_memo_masked BEFORE INSERT OR UPDATE OF memo ON public.gl_journal FOR EACH ROW EXECUTE FUNCTION fn_gl_journal_memo_masked();
CREATE TRIGGER trg_gl_lines_immutable BEFORE INSERT OR DELETE OR UPDATE ON public.gl_journal_lines FOR EACH ROW EXECUTE FUNCTION fn_gl_lines_immutable();
CREATE TRIGGER trg_audit_gl_settings AFTER INSERT OR DELETE OR UPDATE ON public.gl_settings FOR EACH ROW EXECUTE FUNCTION fn_security_audit();
CREATE TRIGGER a00_handoff_contract_guard BEFORE INSERT OR UPDATE ON public.handoff_contract FOR EACH ROW EXECUTE FUNCTION fn_handoff_contract_guard();
CREATE TRIGGER health_checks_agent_threshold BEFORE INSERT ON public.health_checks FOR EACH ROW EXECUTE FUNCTION trg_health_check_agent_threshold();
CREATE TRIGGER trg_event_idea AFTER INSERT ON public.idea FOR EACH ROW EXECUTE FUNCTION fn_emit_event('idea', 'idea.submitted');
CREATE TRIGGER a05_test_reply_leaves_review BEFORE UPDATE ON public.inbound_messages FOR EACH ROW WHEN ((new.owner_role = 'it_engineer'::text)) EXECUTE FUNCTION trg_a05_test_reply_leaves_review();
CREATE TRIGGER trg_inbound_supplier_reply BEFORE INSERT ON public.inbound_messages FOR EACH ROW EXECUTE FUNCTION trg_inbound_supplier_reply();
CREATE TRIGGER z50_support_wire_email AFTER UPDATE OF triaged_at, replied_at ON public.inbound_messages FOR EACH ROW EXECUTE FUNCTION fn_support_wire_email();
CREATE TRIGGER z51_support_classify_email AFTER UPDATE OF triaged_at ON public.inbound_messages FOR EACH ROW EXECUTE FUNCTION fn_support_classify_email();
CREATE TRIGGER z52_invite_reply_reaches_sales_engineer AFTER INSERT ON public.inbound_messages FOR EACH ROW EXECUTE FUNCTION trg_invite_reply_reaches_sales_engineer();
CREATE TRIGGER z53_supplier_mailbox_mail_gets_its_owner AFTER UPDATE OF triaged_at ON public.inbound_messages FOR EACH ROW WHEN (((new.triaged_at IS NOT NULL) AND (old.triaged_at IS NULL) AND (new.ai_category = 'no_auto_reply'::text) AND (new.ai_summary ~~ 'Not answered automatically:%'::text) AND (new.owner_role IS NULL) AND (new.replied_at IS NULL))) EXECUTE FUNCTION trg_supplier_mailbox_mail_gets_its_owner();
CREATE TRIGGER a00_inquiries_lang_default BEFORE INSERT ON public.inquiries FOR EACH ROW EXECUTE FUNCTION fn_inquiries_lang_default();
CREATE TRIGGER a03_inquiry_split_needs_the_customers_choice BEFORE INSERT OR UPDATE OF parent_inquiry_id, scope_type ON public.inquiries FOR EACH ROW EXECUTE FUNCTION trg_inquiry_split_needs_the_customers_choice();
CREATE TRIGGER block_banned_inquiry BEFORE INSERT ON public.inquiries FOR EACH ROW EXECUTE FUNCTION trg_block_banned_inquiry();
CREATE TRIGGER enrich_inquiry BEFORE INSERT ON public.inquiries FOR EACH ROW EXECUTE FUNCTION trg_inquiry_enrich();
CREATE TRIGGER learn_customer_preference AFTER INSERT ON public.inquiries FOR EACH ROW EXECUTE FUNCTION trg_learn_customer_preference();
CREATE TRIGGER reg_inquiry_doc AFTER INSERT OR UPDATE OF drawing_file_path ON public.inquiries FOR EACH ROW EXECUTE FUNCTION trg_reg_inquiry_doc();
CREATE TRIGGER rfq_complete BEFORE INSERT OR UPDATE ON public.inquiries FOR EACH ROW EXECUTE FUNCTION trg_rfq_complete();
CREATE TRIGGER trg_emit_rfq_classified AFTER INSERT OR UPDATE OF category ON public.inquiries FOR EACH ROW EXECUTE FUNCTION fn_emit_rfq_classified();
CREATE TRIGGER trg_event_inquiry AFTER INSERT ON public.inquiries FOR EACH ROW EXECUTE FUNCTION fn_emit_event('inquiry', 'rfq.created');
CREATE TRIGGER trg_mask_inquiry_contact BEFORE INSERT OR UPDATE ON public.inquiries FOR EACH ROW EXECUTE FUNCTION scrub_inquiry_contacts();
CREATE TRIGGER version_rfq AFTER INSERT OR UPDATE ON public.inquiries FOR EACH ROW EXECUTE FUNCTION trg_version_rfq();
CREATE TRIGGER z20_routine_repeat_request_enqueue AFTER INSERT ON public.inquiries FOR EACH ROW EXECUTE FUNCTION trg_routine_repeat_request_enqueue();
CREATE TRIGGER z31_request_end_closes_its_holds AFTER UPDATE OF status ON public.inquiries FOR EACH ROW EXECUTE FUNCTION trg_request_end_closes_its_holds();
CREATE TRIGGER z32_request_end_counts_unanswered_suppliers AFTER UPDATE OF status ON public.inquiries FOR EACH ROW EXECUTE FUNCTION trg_request_end_counts_unanswered_suppliers();
CREATE TRIGGER z70_document_landed_kicks_backup AFTER INSERT OR UPDATE OF drawing_file_path ON public.inquiries FOR EACH STATEMENT EXECUTE FUNCTION trg_document_landed_kicks_backup();
CREATE TRIGGER z90_case_memory AFTER INSERT OR UPDATE OF status, outcome, lost_reason, completed_at, pipeline_stage, hired_supplier_id, summary_masked ON public.inquiries FOR EACH ROW EXECUTE FUNCTION trg_case_memory_inquiry();
CREATE TRIGGER z91_judgement_outcome AFTER UPDATE OF status ON public.inquiries FOR EACH ROW EXECUTE FUNCTION trg_judgement_outcome();
CREATE TRIGGER inquiry_answer_value_immutable BEFORE DELETE OR UPDATE ON public.inquiry_answer FOR EACH ROW EXECUTE FUNCTION trg_inquiry_answer_value_immutable();
CREATE TRIGGER conflict_value_append_only BEFORE DELETE OR UPDATE ON public.inquiry_answer_conflict_value FOR EACH ROW EXECUTE FUNCTION trg_p2c1_append_only();
CREATE TRIGGER corroboration_append_only BEFORE DELETE OR UPDATE ON public.inquiry_answer_corroboration FOR EACH ROW EXECUTE FUNCTION trg_p2c1_append_only();
CREATE TRIGGER answer_document_append_only BEFORE DELETE OR UPDATE ON public.inquiry_answer_document FOR EACH ROW EXECUTE FUNCTION trg_p2c1_append_only();
CREATE TRIGGER a01_inquiry_match_demo_and_real_never_pair BEFORE INSERT OR UPDATE OF inquiry_id, supplier_id ON public.inquiry_matches FOR EACH ROW EXECUTE FUNCTION fn_demo_and_real_never_pair();
CREATE TRIGGER inquiry_scope_disposition_append_only BEFORE DELETE OR UPDATE ON public.inquiry_scope_disposition FOR EACH ROW EXECUTE FUNCTION trg_p2c1_append_only();
CREATE TRIGGER inquiry_state_audit_append_only BEFORE DELETE OR UPDATE ON public.inquiry_state_audit FOR EACH ROW EXECUTE FUNCTION trg_p2c1_append_only();
CREATE TRIGGER supplier_brief_immutable BEFORE UPDATE ON public.inquiry_supplier_brief FOR EACH ROW EXECUTE FUNCTION trg_supplier_brief_immutable();
CREATE TRIGGER trade_candidate_evidence_append_only BEFORE DELETE OR UPDATE ON public.inquiry_trade_candidate_evidence FOR EACH ROW EXECUTE FUNCTION trg_p2c1_append_only();
CREATE TRIGGER trg_internal_credential_audit_immutable BEFORE DELETE OR UPDATE ON public.internal_credential_audit FOR EACH ROW EXECUTE FUNCTION fn_internal_credential_audit_immutable();
CREATE TRIGGER z90_security_detect AFTER INSERT ON public.internal_credential_audit FOR EACH ROW WHEN ((new.allowed = false)) EXECUTE FUNCTION fn_security_detect_on_evidence();
CREATE TRIGGER z90_case_memory AFTER INSERT OR UPDATE OF closed_at, close_note, title ON public.it_engineer_finding FOR EACH ROW EXECUTE FUNCTION trg_case_memory_it_finding();
CREATE TRIGGER z91_judgement_outcome AFTER UPDATE OF closed_at ON public.it_engineer_finding FOR EACH ROW EXECUTE FUNCTION trg_judgement_outcome();
CREATE TRIGGER a10_it_engineer_knowledge_search_vector BEFORE INSERT OR UPDATE OF title, tags, content ON public.it_engineer_knowledge FOR EACH ROW EXECUTE FUNCTION fn_it_engineer_knowledge_search_vector();
CREATE TRIGGER z_ml_vectors_stale AFTER UPDATE OF title, content ON public.it_engineer_knowledge FOR EACH ROW WHEN (((old.title IS DISTINCT FROM new.title) OR (old.content IS DISTINCT FROM new.content))) EXECUTE FUNCTION fn_ml_vectors_stale('it_engineer_knowledge', 'record_id');
CREATE TRIGGER z_ml_vectors_stale_del AFTER DELETE ON public.it_engineer_knowledge FOR EACH ROW EXECUTE FUNCTION fn_ml_vectors_stale('it_engineer_knowledge', 'record_id');
CREATE TRIGGER zz_knowledge_library_mirror AFTER INSERT OR DELETE OR UPDATE OF record_id, title, content, tags, pack_id, source_ids, epistemic_status, runtime_index_eligible, embedding_gte ON public.it_engineer_knowledge FOR EACH ROW EXECUTE FUNCTION fn_knowledge_library_mirror();
CREATE TRIGGER z90_kb_chunks_export_change_del AFTER DELETE ON public.kb_chunks REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION trg_table_export_change('id', 'id,source_kind,source_id,category,title,content,citation,effective_date,fts,created_at,category_norm,embed_claimed_at');
CREATE TRIGGER z90_kb_chunks_export_change_ins AFTER INSERT ON public.kb_chunks REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION trg_table_export_change('id', 'id,source_kind,source_id,category,title,content,citation,effective_date,fts,created_at,category_norm,embed_claimed_at');
CREATE TRIGGER z90_kb_chunks_export_change_trunc AFTER TRUNCATE ON public.kb_chunks FOR EACH STATEMENT EXECUTE FUNCTION trg_table_export_change('id', 'id,source_kind,source_id,category,title,content,citation,effective_date,fts,created_at,category_norm,embed_claimed_at');
CREATE TRIGGER z90_kb_chunks_export_change_upd AFTER UPDATE ON public.kb_chunks REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION trg_table_export_change('id', 'id,source_kind,source_id,category,title,content,citation,effective_date,fts,created_at,category_norm,embed_claimed_at');
CREATE TRIGGER z_ml_vectors_stale AFTER UPDATE OF title, content ON public.kb_chunks FOR EACH ROW WHEN (((old.title IS DISTINCT FROM new.title) OR (old.content IS DISTINCT FROM new.content))) EXECUTE FUNCTION fn_ml_vectors_stale('kb_chunks', 'id');
CREATE TRIGGER z_ml_vectors_stale_del AFTER DELETE ON public.kb_chunks FOR EACH ROW EXECUTE FUNCTION fn_ml_vectors_stale('kb_chunks', 'id');
CREATE TRIGGER zz_knowledge_library_mirror AFTER INSERT OR DELETE OR UPDATE OF id, title, content, citation, category_norm, source_kind, embedding_gte ON public.kb_chunks FOR EACH ROW EXECUTE FUNCTION fn_knowledge_library_mirror();
CREATE TRIGGER zz_knowledge_library_mirror_ml AFTER INSERT OR UPDATE OF src, row_id, embedding ON public.knowledge_vector_ml FOR EACH ROW WHEN ((new.src = ANY (ARRAY['kb_chunks'::text, 'ops_knowledge'::text, 'agent_knowledge'::text, 'sales_knowledge'::text, 'accountant_knowledge'::text, 'it_engineer_knowledge'::text, 'marketing_knowledge'::text, 'ceo_knowledge'::text, 'support_knowledge'::text]))) EXECUTE FUNCTION fn_knowledge_library_mirror_ml();
CREATE TRIGGER zz_knowledge_library_mirror_ml_delete AFTER DELETE ON public.knowledge_vector_ml FOR EACH ROW WHEN ((old.src = ANY (ARRAY['kb_chunks'::text, 'ops_knowledge'::text, 'agent_knowledge'::text, 'sales_knowledge'::text, 'accountant_knowledge'::text, 'it_engineer_knowledge'::text, 'marketing_knowledge'::text, 'ceo_knowledge'::text, 'support_knowledge'::text]))) EXECUTE FUNCTION fn_knowledge_library_mirror_ml();
CREATE TRIGGER a00_leads_sanctioned_row_is_never_deleted BEFORE DELETE ON public.leads FOR EACH ROW EXECUTE FUNCTION fn_leads_sanctioned_row_is_permanent();
CREATE TRIGGER a01_leads_sanctioned_identity_cannot_re_register BEFORE INSERT OR UPDATE OF company_name, trade_license_no, claimed_by, email ON public.leads FOR EACH ROW EXECUTE FUNCTION fn_leads_sanctioned_identity_cannot_re_register();
CREATE TRIGGER a05_leads_licence_read_clock BEFORE INSERT OR UPDATE OF licence_read_state, license_doc_path ON public.leads FOR EACH ROW EXECUTE FUNCTION fn_leads_licence_read_clock();
CREATE TRIGGER quote_reviews_follow_owner AFTER UPDATE OF claimed_by ON public.leads FOR EACH ROW WHEN ((old.claimed_by IS DISTINCT FROM new.claimed_by)) EXECUTE FUNCTION fn_quote_reviews_follow_owner();
CREATE TRIGGER reg_lead_docs AFTER INSERT OR UPDATE OF license_doc_path, company_profile_doc_path, egr_doc_path, catalog_doc_paths ON public.leads FOR EACH ROW EXECUTE FUNCTION trg_reg_lead_docs();
CREATE TRIGGER trg_assign_founding_rank BEFORE INSERT OR UPDATE ON public.leads FOR EACH ROW EXECUTE FUNCTION fn_assign_founding_rank();
CREATE TRIGGER trg_block_disposable_leads BEFORE INSERT ON public.leads FOR EACH ROW EXECUTE FUNCTION block_disposable_signup();
CREATE TRIGGER trg_bz_supplier_registration_state BEFORE INSERT OR UPDATE ON public.leads FOR EACH ROW EXECUTE FUNCTION fn_derive_supplier_registration_state();
CREATE TRIGGER trg_emit_supplier_applied AFTER UPDATE ON public.leads FOR EACH ROW EXECUTE FUNCTION fn_emit_supplier_applied();
CREATE TRIGGER trg_emit_supplier_approved AFTER INSERT OR UPDATE OF approval_status ON public.leads FOR EACH ROW EXECUTE FUNCTION fn_emit_supplier_approved();
CREATE TRIGGER trg_leads_derive_owner_email_verified BEFORE INSERT OR UPDATE OF claimed_by ON public.leads FOR EACH ROW EXECUTE FUNCTION fn_leads_derive_owner_email_verified();
CREATE TRIGGER trg_leads_e0_mandatory_six_gate BEFORE INSERT OR UPDATE ON public.leads FOR EACH ROW WHEN (((new.approval_status = 'approved'::text) OR new.verified)) EXECUTE FUNCTION fn_leads_mandatory_six_gate();
CREATE TRIGGER trg_leads_exception_invariant BEFORE INSERT OR UPDATE ON public.leads FOR EACH ROW EXECUTE FUNCTION fn_leads_exception_invariant();
CREATE TRIGGER trg_leads_z90_verification_status_follows_verified BEFORE INSERT OR UPDATE ON public.leads FOR EACH ROW EXECUTE FUNCTION fn_leads_verification_status_follows_verified();
CREATE TRIGGER trg_sales_engineer_tells_the_supplier_he_is_approved AFTER INSERT OR UPDATE OF approval_status ON public.leads FOR EACH ROW WHEN ((new.approval_status = 'approved'::text)) EXECUTE FUNCTION fn_sales_engineer_tells_the_supplier_he_is_approved();
CREATE TRIGGER trg_sign_supplier AFTER UPDATE ON public.leads FOR EACH ROW WHEN (((new.owner_email_verified IS TRUE) AND (old.owner_email_verified IS DISTINCT FROM new.owner_email_verified) AND (new.signed_terms_url IS NULL) AND (new.claimed_by IS NOT NULL))) EXECUTE FUNCTION qd_sign_supplier();
CREATE TRIGGER z20_leads_mandatory_item_landed_reverifies AFTER UPDATE OF company_name, phone, phone_e164, owner_phone_verified, owner_email_verified, license_doc_path, license_expiry, company_profile_doc_path, signed_terms_path, licence_legal_name ON public.leads FOR EACH ROW WHEN (((pg_trigger_depth() < 1) AND ((new.approval_status = ANY (ARRAY['action_required'::text, 'pending'::text])) OR ((new.approval_status = 'approved'::text) AND ((old.license_doc_path IS DISTINCT FROM new.license_doc_path) OR (old.licence_legal_name IS DISTINCT FROM new.licence_legal_name)))))) EXECUTE FUNCTION fn_leads_mandatory_item_landed_reverifies();
CREATE TRIGGER z21_sign_supplier_on_acceptance AFTER UPDATE OF accepted_terms_at ON public.leads FOR EACH ROW WHEN (((new.accepted_terms_at IS NOT NULL) AND (new.accepted_terms_at IS DISTINCT FROM old.accepted_terms_at) AND (new.claimed_by IS NOT NULL) AND (NOT ((new.owner_email_verified IS TRUE) AND (old.owner_email_verified IS DISTINCT FROM new.owner_email_verified) AND (new.signed_terms_url IS NULL))))) EXECUTE FUNCTION qd_sign_supplier();
CREATE TRIGGER z22_sign_supplier_again_when_his_licence_is_read AFTER UPDATE OF licence_legal_name, trade_license_no ON public.leads FOR EACH ROW WHEN (((new.accepted_terms_at IS NOT NULL) AND (new.signed_terms_path IS NOT NULL) AND (new.claimed_by IS NOT NULL) AND (COALESCE(new.approval_status, ''::text) <> 'approved'::text) AND ((new.registration_submitted_at IS NULL) OR (COALESCE(btrim(old.company_name), ''::text) = ''::text)) AND (((new.licence_legal_name IS NOT NULL) AND (old.licence_legal_name IS DISTINCT FROM new.licence_legal_name)) OR ((new.trade_license_no IS NOT NULL) AND (old.trade_license_no IS DISTINCT FROM new.trade_license_no))))) EXECUTE FUNCTION fn_sign_supplier_again_when_his_licence_is_read();
CREATE TRIGGER z40_leads_keep_the_public_name AFTER INSERT OR UPDATE OF company_name ON public.leads FOR EACH ROW EXECUTE FUNCTION trg_leads_keep_the_public_name();
CREATE TRIGGER z70_document_landed_kicks_backup AFTER INSERT OR UPDATE OF license_doc_path, egr_doc_path, insurance_doc_path, vat_doc_path, iso_doc_path, manufacturer_auth_doc_path, company_profile_doc_path, catalog_doc_paths, signed_terms_path ON public.leads FOR EACH STATEMENT EXECUTE FUNCTION trg_document_landed_kicks_backup();
CREATE TRIGGER z80_invite_same_day_brake AFTER UPDATE OF invite_status ON public.leads FOR EACH ROW WHEN (((new.invite_status = ANY (ARRAY['bounced'::text, 'complained'::text])) AND (old.invite_status IS DISTINCT FROM new.invite_status))) EXECUTE FUNCTION fn_invite_same_day_brake();
CREATE TRIGGER z90_leads_gone_closes_its_pending_actions AFTER DELETE ON public.leads REFERENCING OLD TABLE AS gone FOR EACH STATEMENT EXECUTE FUNCTION fn_leads_gone_closes_its_pending_actions();
CREATE TRIGGER zzz_collaboration_hold_guard BEFORE UPDATE ON public.leads FOR EACH ROW EXECUTE FUNCTION fn_leads_collaboration_hold_guard();
CREATE TRIGGER zzz_leads_sanctioned_ban_is_permanent BEFORE UPDATE ON public.leads FOR EACH ROW EXECUTE FUNCTION fn_leads_sanctioned_row_is_permanent();
CREATE TRIGGER a00_llm_attempt_immutable BEFORE DELETE OR UPDATE ON public.llm_attempt FOR EACH ROW EXECUTE FUNCTION a00_llm_attempt_immutable();
CREATE TRIGGER trg_llm_route_health_founder_hold BEFORE DELETE OR UPDATE ON public.llm_route_health FOR EACH ROW EXECUTE FUNCTION fn_llm_route_health_founder_hold_guard();
CREATE TRIGGER trg_llm_route_health_no_new_founder_hold BEFORE INSERT OR UPDATE ON public.llm_route_health FOR EACH ROW EXECUTE FUNCTION fn_llm_route_health_no_new_founder_hold();
CREATE TRIGGER a06_names_no_supplier BEFORE INSERT OR UPDATE OF title_en, title_ar, excerpt_en, excerpt_ar, meta_desc_en, meta_desc_ar, body_html_en, body_html_ar ON public.marketing_article FOR EACH ROW EXECUTE FUNCTION trg_published_text_names_no_supplier();
CREATE TRIGGER a10_marketing_article_round_guard BEFORE INSERT OR DELETE OR UPDATE ON public.marketing_article_round FOR EACH ROW EXECUTE FUNCTION fn_marketing_article_round_guard();
CREATE TRIGGER z90_case_memory AFTER INSERT OR UPDATE OF approved_at, theme, title ON public.marketing_campaign FOR EACH ROW EXECUTE FUNCTION trg_case_memory_campaign();
CREATE TRIGGER z93_high_stakes_campaign_approved AFTER UPDATE OF approved_at ON public.marketing_campaign FOR EACH ROW EXECUTE FUNCTION trg_high_stakes_campaign_approved();
CREATE TRIGGER z92_outcome_learning AFTER INSERT ON public.marketing_first_touch FOR EACH ROW EXECUTE FUNCTION trg_outcome_learning();
CREATE TRIGGER z_ml_vectors_stale AFTER UPDATE OF title, content ON public.marketing_knowledge FOR EACH ROW WHEN (((old.title IS DISTINCT FROM new.title) OR (old.content IS DISTINCT FROM new.content))) EXECUTE FUNCTION fn_ml_vectors_stale('marketing_knowledge', 'record_id');
CREATE TRIGGER z_ml_vectors_stale_del AFTER DELETE ON public.marketing_knowledge FOR EACH ROW EXECUTE FUNCTION fn_ml_vectors_stale('marketing_knowledge', 'record_id');
CREATE TRIGGER zz_knowledge_library_mirror AFTER INSERT OR DELETE OR UPDATE OF record_id, title, content, tags, pack_id, source_ids, epistemic_status, runtime_index_eligible, embedding_gte ON public.marketing_knowledge FOR EACH ROW EXECUTE FUNCTION fn_knowledge_library_mirror();
CREATE TRIGGER a05_marketing_post_on_a_working_day BEFORE INSERT OR UPDATE OF scheduled_at, status ON public.marketing_post FOR EACH ROW EXECUTE FUNCTION fn_marketing_post_on_a_working_day();
CREATE TRIGGER a06_names_no_supplier BEFORE INSERT OR UPDATE OF title, text_en, text_ar ON public.marketing_post FOR EACH ROW EXECUTE FUNCTION trg_published_text_names_no_supplier();
CREATE TRIGGER marketing_post_guard_publish BEFORE INSERT OR UPDATE OF status ON public.marketing_post FOR EACH ROW EXECUTE FUNCTION fn_marketing_post_guard_publish();
CREATE TRIGGER z95_marketing_post_content_edited_at BEFORE INSERT OR UPDATE ON public.marketing_post FOR EACH ROW EXECUTE FUNCTION fn_marketing_post_content_edited_at();
CREATE TRIGGER z91_judgement_outcome AFTER INSERT ON public.marketing_post_metric FOR EACH ROW EXECUTE FUNCTION trg_judgement_outcome();
CREATE TRIGGER z92_outcome_learning AFTER INSERT ON public.marketing_post_metric FOR EACH ROW EXECUTE FUNCTION trg_outcome_learning();
CREATE TRIGGER a06_names_no_supplier BEFORE INSERT OR UPDATE OF title, caption, body, first_comment, alt_text ON public.marketing_post_variant FOR EACH ROW EXECUTE FUNCTION trg_published_text_names_no_supplier();
CREATE TRIGGER z50_wa_template_registry_follows AFTER INSERT OR UPDATE OF status, last_checked_at ON public.messaging_template FOR EACH ROW EXECUTE FUNCTION fn_wa_template_registry_follows_messaging_template();
CREATE TRIGGER trg_emit_campaign_launched AFTER INSERT OR UPDATE ON public.meta_insights FOR EACH ROW WHEN ((new.effective_status ~* '^active$'::text)) EXECUTE FUNCTION fn_emit_campaign_launched();
CREATE TRIGGER trg_model_policy_names_a_known_route BEFORE INSERT OR UPDATE ON public.model_policy FOR EACH ROW EXECUTE FUNCTION trg_model_policy_names_a_known_route();
CREATE TRIGGER trg_undo_model_policy BEFORE DELETE OR UPDATE ON public.model_policy FOR EACH ROW EXECUTE FUNCTION trg_undo_capture('id');
CREATE TRIGGER trg_identity_policy_is_a_live_seat_and_a_known_model BEFORE INSERT OR UPDATE ON public.model_policy_by_identity FOR EACH ROW EXECUTE FUNCTION fn_identity_policy_is_a_live_seat_and_a_known_model();
CREATE TRIGGER a00_notifications_the_same_message_is_sent_once BEFORE INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION fn_notifications_the_same_message_is_sent_once();
CREATE TRIGGER a01_notifications_no_test_mail_to_the_founder BEFORE INSERT OR UPDATE OF to_email, cc_emails, type, kind ON public.notifications FOR EACH ROW WHEN (((new.type = 'supplier_invite_seed'::text) OR (new.kind = ANY (ARRAY['invite_m365_seed'::text, 'supplier_invite_seed'::text])))) EXECUTE FUNCTION fn_notifications_no_test_mail_to_the_founder();
CREATE TRIGGER a02_notifications_never_reach_a_sanctioned_party BEFORE INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION fn_notifications_never_reach_a_sanctioned_party();
CREATE TRIGGER a03_notifications_whatsapp_goes_to_a_confirmed_number BEFORE INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION fn_notifications_whatsapp_goes_to_a_confirmed_number();
CREATE TRIGGER a04_notifications_speak_the_recipients_language BEFORE INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION fn_notifications_speak_the_recipients_language();
CREATE TRIGGER a05_notifications_sender_of_record BEFORE INSERT OR UPDATE OF sender, requested_by ON public.notifications FOR EACH ROW EXECUTE FUNCTION fn_notifications_sender_of_record();
CREATE TRIGGER a06_notifications_supplier_notice_follows_the_accepted_agreemen BEFORE INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION fn_notifications_supplier_notice_follows_the_accepted_agreement();
CREATE TRIGGER a07_notifications_supplier_invite_is_whole BEFORE INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION fn_notifications_supplier_invite_is_whole();
CREATE TRIGGER a08_invoice_ready_waits_for_its_invoice BEFORE INSERT ON public.notifications FOR EACH ROW WHEN (((new.type = 'invoice_ready'::text) AND (new.to_role = 'customer'::text) AND (new.quote_id IS NOT NULL) AND (new.attachments IS NULL))) EXECUTE FUNCTION fn_invoice_ready_waits_for_its_invoice();
CREATE TRIGGER a10_notifications_founder_mail_policy BEFORE INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION fn_notifications_founder_mail_policy();
CREATE TRIGGER a20_notifications_attachment_policy BEFORE INSERT OR UPDATE OF attachments ON public.notifications FOR EACH ROW EXECUTE FUNCTION fn_notification_attachment_policy();
CREATE TRIGGER a20_notifications_promotional_consent_gate BEFORE INSERT OR UPDATE OF status ON public.notifications FOR EACH ROW EXECUTE FUNCTION fn_notifications_promotional_consent_gate();
CREATE TRIGGER trg_notifications_digest BEFORE INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION fn_notifications_digest();
CREATE TRIGGER trg_wa_fanout AFTER INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION fn_wa_fanout();
CREATE TRIGGER z05_notifications_supplier_is_english BEFORE INSERT OR UPDATE OF lang, subject, body, to_role ON public.notifications FOR EACH ROW EXECUTE FUNCTION fn_notifications_supplier_is_english();
CREATE TRIGGER z06_supplier_notice_whatsapp_twin_under_v11 AFTER INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION fn_supplier_notice_whatsapp_twin_under_v11();
CREATE TRIGGER z30_invoice_ready_asks_for_its_invoice AFTER INSERT ON public.notifications FOR EACH ROW WHEN (((new.type = 'invoice_ready'::text) AND (new.to_role = 'customer'::text) AND (COALESCE(new.channel, 'email'::text) = 'email'::text) AND (new.status = ANY (ARRAY['queued'::text, 'pending'::text])) AND (new.quote_id IS NOT NULL) AND (new.attachments IS NULL))) EXECUTE FUNCTION fn_invoice_ready_asks_for_its_invoice();
CREATE TRIGGER z51_support_notification_sync_state AFTER UPDATE ON public.notifications FOR EACH ROW EXECUTE FUNCTION fn_support_notification_sync_state();
CREATE TRIGGER z81_invite_schedule_counts_a_real_send AFTER UPDATE OF sent_at ON public.notifications FOR EACH ROW WHEN (((new.type = 'supplier_invite'::text) AND (new.sent_at IS NOT NULL) AND (old.sent_at IS NULL))) EXECUTE FUNCTION trg_invite_schedule_counts_a_real_send();
CREATE TRIGGER z90_every_send_is_tracked AFTER INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION fn_customer_support_adopts_untracked_send();
CREATE TRIGGER z91_judgement_outcome AFTER UPDATE OF status, provider_status ON public.notifications FOR EACH ROW EXECUTE FUNCTION trg_judgement_outcome();
CREATE TRIGGER zzz_notifications_demo_guard BEFORE INSERT OR UPDATE OF status, to_email, to_phone ON public.notifications FOR EACH ROW EXECUTE FUNCTION zzz_fn_notifications_demo_guard();
CREATE TRIGGER zzzz_notifications_demo_capture BEFORE INSERT OR UPDATE OF status, to_email, to_phone ON public.notifications FOR EACH ROW EXECUTE FUNCTION fn_notifications_demo_capture();
CREATE TRIGGER a05_knowledge_internal_figures_withheld BEFORE INSERT OR UPDATE ON public.ops_knowledge FOR EACH ROW EXECUTE FUNCTION fn_knowledge_internal_figures_withheld();
CREATE TRIGGER a10_ops_knowledge_embedding_status BEFORE INSERT OR UPDATE ON public.ops_knowledge FOR EACH ROW EXECUTE FUNCTION fn_ops_knowledge_embedding_status();
CREATE TRIGGER z90_ops_knowledge_export_change_del AFTER DELETE ON public.ops_knowledge REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION trg_table_export_change('record_id', 'record_id,scope_type,scope_key,dept_key,module,record_type,title,content,structured_data,source_ids,implementation_status,validation_status,authority_tier,risk_level,version,effective_date,review_after,keywords,dependencies,escalation_rule,tsv,package,package_version,generation,layer,role_key,category_key,jurisdiction,source_type,source_authority,source_freshness,confidentiality,runtime_eligible,deterministic,supersedes_id,supersession_state,checksum,ingestion_run_id,embedding_status,source_path');
CREATE TRIGGER z90_ops_knowledge_export_change_ins AFTER INSERT ON public.ops_knowledge REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION trg_table_export_change('record_id', 'record_id,scope_type,scope_key,dept_key,module,record_type,title,content,structured_data,source_ids,implementation_status,validation_status,authority_tier,risk_level,version,effective_date,review_after,keywords,dependencies,escalation_rule,tsv,package,package_version,generation,layer,role_key,category_key,jurisdiction,source_type,source_authority,source_freshness,confidentiality,runtime_eligible,deterministic,supersedes_id,supersession_state,checksum,ingestion_run_id,embedding_status,source_path');
CREATE TRIGGER z90_ops_knowledge_export_change_trunc AFTER TRUNCATE ON public.ops_knowledge FOR EACH STATEMENT EXECUTE FUNCTION trg_table_export_change('record_id', 'record_id,scope_type,scope_key,dept_key,module,record_type,title,content,structured_data,source_ids,implementation_status,validation_status,authority_tier,risk_level,version,effective_date,review_after,keywords,dependencies,escalation_rule,tsv,package,package_version,generation,layer,role_key,category_key,jurisdiction,source_type,source_authority,source_freshness,confidentiality,runtime_eligible,deterministic,supersedes_id,supersession_state,checksum,ingestion_run_id,embedding_status,source_path');
CREATE TRIGGER z90_ops_knowledge_export_change_upd AFTER UPDATE ON public.ops_knowledge REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION trg_table_export_change('record_id', 'record_id,scope_type,scope_key,dept_key,module,record_type,title,content,structured_data,source_ids,implementation_status,validation_status,authority_tier,risk_level,version,effective_date,review_after,keywords,dependencies,escalation_rule,tsv,package,package_version,generation,layer,role_key,category_key,jurisdiction,source_type,source_authority,source_freshness,confidentiality,runtime_eligible,deterministic,supersedes_id,supersession_state,checksum,ingestion_run_id,embedding_status,source_path');
CREATE TRIGGER z_ml_vectors_stale AFTER UPDATE OF title, content ON public.ops_knowledge FOR EACH ROW WHEN (((old.title IS DISTINCT FROM new.title) OR (old.content IS DISTINCT FROM new.content))) EXECUTE FUNCTION fn_ml_vectors_stale('ops_knowledge', 'record_id');
CREATE TRIGGER z_ml_vectors_stale_del AFTER DELETE ON public.ops_knowledge FOR EACH ROW EXECUTE FUNCTION fn_ml_vectors_stale('ops_knowledge', 'record_id');
CREATE TRIGGER zz_knowledge_library_mirror AFTER INSERT OR DELETE OR UPDATE OF record_id, title, content, category_key, source_path, source_ids, validation_status, runtime_eligible, supersession_state, scope_type, embedding_gte ON public.ops_knowledge FOR EACH ROW EXECUTE FUNCTION fn_knowledge_library_mirror();
CREATE TRIGGER trg_org_action_executor_guard BEFORE INSERT OR UPDATE OF kind, target ON public.org_action_executor FOR EACH ROW EXECUTE FUNCTION fn_org_action_executor_guard();
CREATE TRIGGER a00_org_phase_baseline_append_only BEFORE DELETE OR UPDATE ON public.org_phase_baseline FOR EACH ROW EXECUTE FUNCTION fn_org_phase_baseline_append_only();
CREATE TRIGGER a10_org_role_no_cycle BEFORE INSERT OR UPDATE OF manager_role_id ON public.org_role FOR EACH ROW EXECUTE FUNCTION trg_org_role_no_cycle();
CREATE TRIGGER a20_org_role_touch BEFORE UPDATE ON public.org_role FOR EACH ROW EXECUTE FUNCTION trg_org_role_touch();
CREATE TRIGGER a00_role_identity_isolation_guard BEFORE INSERT OR UPDATE OF agent_key, packaged_role_id, packaged_department, archetype ON public.org_role_identity FOR EACH ROW EXECUTE FUNCTION fn_role_identity_isolation_guard();
CREATE TRIGGER a000_org_task_demo_files_nothing BEFORE INSERT ON public.org_tasks FOR EACH ROW EXECUTE FUNCTION fn_org_task_demo_files_nothing();
CREATE TRIGGER a05_org_task_fill_ownership BEFORE INSERT ON public.org_tasks FOR EACH ROW EXECUTE FUNCTION fn_org_task_fill_ownership();
CREATE TRIGGER a06_org_task_goes_to_its_kinds_owner BEFORE INSERT ON public.org_tasks FOR EACH ROW EXECUTE FUNCTION fn_org_task_goes_to_its_kinds_owner();
CREATE TRIGGER a10_org_task_done_needs_a_determination BEFORE INSERT OR UPDATE OF status ON public.org_tasks FOR EACH ROW EXECUTE FUNCTION fn_org_task_done_needs_a_determination();
CREATE TRIGGER t40_org_task_incident_sync AFTER UPDATE OF status ON public.org_tasks FOR EACH ROW WHEN ((new.action_class = 'incident'::text)) EXECUTE FUNCTION fn_org_task_incident_sync();
CREATE TRIGGER trg_org_task_autonomy_brake BEFORE UPDATE OF status ON public.org_tasks FOR EACH ROW EXECUTE FUNCTION fn_org_task_autonomy_brake();
CREATE TRIGGER trg_org_task_cross_os_guard BEFORE INSERT ON public.org_tasks FOR EACH ROW EXECUTE FUNCTION fn_org_task_cross_os_guard();
CREATE TRIGGER trg_org_task_root_cause BEFORE UPDATE ON public.org_tasks FOR EACH ROW EXECUTE FUNCTION fn_org_task_root_cause_guard();
CREATE TRIGGER trg_undo_org_tasks BEFORE DELETE OR UPDATE ON public.org_tasks FOR EACH ROW EXECUTE FUNCTION trg_undo_capture('id');
CREATE TRIGGER trg_workflow_run_follow_task AFTER UPDATE OF status ON public.org_tasks FOR EACH ROW EXECUTE FUNCTION fn_workflow_run_follow_task();
CREATE TRIGGER z50_task_close_needs_an_act BEFORE UPDATE ON public.org_tasks FOR EACH ROW EXECUTE FUNCTION fn_org_task_close_needs_an_act();
CREATE TRIGGER t10_os_incident_set_owner BEFORE INSERT ON public.os_incidents FOR EACH ROW EXECUTE FUNCTION fn_os_incident_set_owner_and_due();
CREATE TRIGGER t20_os_incident_open_task AFTER INSERT ON public.os_incidents FOR EACH ROW EXECUTE FUNCTION fn_os_incident_open_task();
CREATE TRIGGER t30_os_incident_close_task AFTER UPDATE OF status ON public.os_incidents FOR EACH ROW EXECUTE FUNCTION fn_os_incident_close_task();
CREATE TRIGGER trg_event_incident AFTER INSERT ON public.os_incidents FOR EACH ROW EXECUTE FUNCTION fn_emit_event('incident', 'security.event');
CREATE TRIGGER otp_served_country_lifts_blocks AFTER INSERT OR UPDATE OF prefix ON public.otp_served_country FOR EACH ROW EXECUTE FUNCTION trg_otp_served_country_lifts_blocks();
CREATE TRIGGER trg_pages_dirty_a AFTER INSERT OR UPDATE ON public.pages FOR EACH ROW EXECUTE FUNCTION trg_pages_dirty();
CREATE TRIGGER trg_pages_legal_sync_a AFTER INSERT OR UPDATE OF html ON public.pages FOR EACH ROW EXECUTE FUNCTION trg_pages_legal_sync();
CREATE TRIGGER trg_phase1_rollback_log_immutable BEFORE DELETE OR UPDATE ON public.phase1_rollback_log FOR EACH ROW EXECUTE FUNCTION fn_phase1_rollback_log_immutable();
CREATE TRIGGER trg_po_orders_link BEFORE INSERT OR UPDATE OF quote_id, inquiry_id, customer_id, project_id ON public.po_orders FOR EACH ROW EXECUTE FUNCTION fn_po_orders_link();
CREATE TRIGGER trg_audit_pricing_config AFTER INSERT OR DELETE OR UPDATE ON public.pricing_config FOR EACH ROW EXECUTE FUNCTION fn_security_audit();
CREATE TRIGGER public_holidays_move_the_posts AFTER INSERT OR UPDATE OF holiday_date ON public.public_holidays FOR EACH ROW EXECUTE FUNCTION fn_public_holiday_moves_the_posts();
CREATE TRIGGER a20_quote_comparison_publication_stamp BEFORE INSERT OR UPDATE ON public.quote_comparisons FOR EACH ROW EXECUTE FUNCTION fn_quote_comparison_publication_stamp();
CREATE TRIGGER quote_items_rescore AFTER INSERT OR DELETE OR UPDATE ON public.quote_items FOR EACH ROW EXECUTE FUNCTION trg_quote_items_rescore();
CREATE TRIGGER z30_quote_pdf_cache_register AFTER INSERT OR UPDATE OF path ON public.quote_pdf_cache FOR EACH ROW EXECUTE FUNCTION trg_quote_pdf_cache_register();
CREATE TRIGGER z10_hold_answered_resets_the_run AFTER UPDATE OF state ON public.quote_spec_hold FOR EACH ROW EXECUTE FUNCTION trg_hold_answered_resets_the_run();
CREATE TRIGGER a01_quote_demo_and_real_never_pair BEFORE INSERT ON public.quotes FOR EACH ROW EXECUTE FUNCTION fn_demo_and_real_never_pair();
CREATE TRIGGER a30_quote_supplier_is_immutable BEFORE UPDATE ON public.quotes FOR EACH ROW EXECUTE FUNCTION fn_quote_supplier_is_immutable();
CREATE TRIGGER mask_quote_contact BEFORE INSERT OR UPDATE ON public.quotes FOR EACH ROW EXECUTE FUNCTION trg_mask_quote_contact();
CREATE TRIGGER quote_committed_hash BEFORE INSERT OR UPDATE OF scope, notes, payment_terms, warranty, committed_items ON public.quotes FOR EACH ROW EXECUTE FUNCTION trg_quote_committed_hash();
CREATE TRIGGER quotes_quality BEFORE INSERT OR UPDATE ON public.quotes FOR EACH ROW EXECUTE FUNCTION trg_quote_quality();
CREATE TRIGGER reg_quote_doc AFTER INSERT OR UPDATE OF original_file_path ON public.quotes FOR EACH ROW EXECUTE FUNCTION trg_reg_quote_doc();
CREATE TRIGGER trg_event_quote AFTER INSERT ON public.quotes FOR EACH ROW EXECUTE FUNCTION fn_emit_event('quote', 'quote.received');
CREATE TRIGGER trg_quote_expiry_b BEFORE INSERT ON public.quotes FOR EACH ROW EXECUTE FUNCTION trg_quote_expiry();
CREATE TRIGGER trg_scrub_quote_contacts BEFORE INSERT OR UPDATE ON public.quotes FOR EACH ROW EXECUTE FUNCTION scrub_quote_contacts();
CREATE TRIGGER version_quote AFTER INSERT OR UPDATE ON public.quotes FOR EACH ROW EXECUTE FUNCTION trg_version_quote();
CREATE TRIGGER z31_withdrawn_quote_closes_its_holds AFTER UPDATE OF status ON public.quotes FOR EACH ROW EXECUTE FUNCTION trg_withdrawn_quote_closes_its_holds();
CREATE TRIGGER z32_a_quote_clears_the_strike_run AFTER INSERT ON public.quotes FOR EACH ROW WHEN ((new.supplier_id IS NOT NULL)) EXECUTE FUNCTION trg_a_quote_clears_the_strike_run();
CREATE TRIGGER z40_quote_quality_gate BEFORE INSERT OR UPDATE OF status ON public.quotes FOR EACH ROW EXECUTE FUNCTION fn_quote_quality_gate();
CREATE TRIGGER z91_judgement_outcome AFTER UPDATE OF status ON public.quotes FOR EACH ROW EXECUTE FUNCTION trg_judgement_outcome();
CREATE TRIGGER lesson_reapproval_lapse_escalates AFTER UPDATE OF status ON public.reasoning_held_question FOR EACH ROW WHEN (((new.surface = 'ceo.lesson_reapproval'::text) AND (old.status IS DISTINCT FROM new.status) AND ((new.status = ANY (ARRAY['expired'::text, 'failed'::text, 'applied'::text])) OR ((new.status = 'reasoned'::text) AND (new.result ? 'apply_error'::text))))) EXECUTE FUNCTION fn_lesson_reapproval_lapse_escalates();
CREATE TRIGGER z70_seat_playbook_learns AFTER INSERT OR UPDATE OF status ON public.reasoning_knowledge_candidate FOR EACH ROW WHEN ((new.status = ANY (ARRAY['approved'::text, 'rejected'::text]))) EXECUTE FUNCTION trg_seat_playbook_learns();
CREATE TRIGGER z_ml_vectors_stale AFTER UPDATE OF question, finding ON public.reasoning_knowledge_candidate FOR EACH ROW WHEN (((old.question IS DISTINCT FROM new.question) OR (old.finding IS DISTINCT FROM new.finding))) EXECUTE FUNCTION fn_ml_vectors_stale('reasoning_knowledge_candidate', 'id');
CREATE TRIGGER z_ml_vectors_stale_del AFTER DELETE ON public.reasoning_knowledge_candidate FOR EACH ROW EXECUTE FUNCTION fn_ml_vectors_stale('reasoning_knowledge_candidate', 'id');
CREATE TRIGGER a00_refund_case_authorisation_is_the_one_decision BEFORE INSERT OR UPDATE ON public.refund_case FOR EACH ROW EXECUTE FUNCTION fn_refund_case_authorisation_is_the_one_decision();
CREATE TRIGGER z10_refund_nonresponse_needs_silence BEFORE INSERT OR UPDATE ON public.refund_case FOR EACH ROW EXECUTE FUNCTION fn_refund_nonresponse_needs_silence();
CREATE TRIGGER z20_refund_case_approval_checks_the_process BEFORE INSERT OR UPDATE ON public.refund_case FOR EACH ROW EXECUTE FUNCTION fn_ceo_refund_approval_checks_the_process();
CREATE TRIGGER z90_case_memory AFTER INSERT OR UPDATE OF state, decision, decision_rationale ON public.refund_case FOR EACH ROW EXECUTE FUNCTION trg_case_memory_refund_case();
CREATE TRIGGER a00_refund_amount_is_the_fee_paid BEFORE INSERT OR UPDATE ON public.refunds FOR EACH ROW EXECUTE FUNCTION fn_refund_amount_is_the_fee_paid();
CREATE TRIGGER a01_refunds_never_return_more_than_was_paid BEFORE INSERT OR UPDATE ON public.refunds FOR EACH ROW EXECUTE FUNCTION fn_refunds_never_return_more_than_was_paid();
CREATE TRIGGER refunds_touch BEFORE UPDATE ON public.refunds FOR EACH ROW EXECUTE FUNCTION trg_refunds_touch();
CREATE TRIGGER trg_emit_refund_requested AFTER INSERT ON public.refunds FOR EACH ROW EXECUTE FUNCTION fn_emit_refund_requested();
CREATE TRIGGER trg_refunds_settled_at BEFORE INSERT OR UPDATE ON public.refunds FOR EACH ROW EXECUTE FUNCTION fn_refunds_settled_at();
CREATE TRIGGER z00_refund_ceo_approval_only BEFORE INSERT OR UPDATE ON public.refunds FOR EACH ROW EXECUTE FUNCTION fn_refund_ceo_approval_only();
CREATE TRIGGER z04_refund_approval_is_the_one_decision BEFORE INSERT OR UPDATE ON public.refunds FOR EACH ROW EXECUTE FUNCTION fn_refund_approval_is_the_one_decision();
CREATE TRIGGER z05_refund_execution_requires_ceo_approval BEFORE INSERT OR UPDATE ON public.refunds FOR EACH ROW EXECUTE FUNCTION fn_refund_execution_requires_ceo_approval();
CREATE TRIGGER z30_refund_request_hands_to_accountant AFTER INSERT ON public.refunds FOR EACH ROW EXECUTE FUNCTION fn_refund_request_hands_to_accountant();
CREATE TRIGGER z50_external_refund_is_verified AFTER INSERT OR UPDATE OF status ON public.refunds FOR EACH ROW EXECUTE FUNCTION fn_external_refund_is_verified();
CREATE TRIGGER trg_reg_gov BEFORE INSERT OR UPDATE ON public.regulations FOR EACH ROW EXECUTE FUNCTION trg_reg_gov_fn();
CREATE TRIGGER a00_review_chain_no_self_review BEFORE INSERT OR UPDATE ON public.review_chain FOR EACH ROW EXECUTE FUNCTION trg_review_chain_no_self_review();
CREATE TRIGGER t60_sales_rating_landed AFTER INSERT OR UPDATE ON public.reviews FOR EACH ROW EXECUTE FUNCTION fn_sales_rating_landed();
CREATE TRIGGER trg_emit_customer_complaint_review AFTER INSERT OR UPDATE OF rating ON public.reviews FOR EACH ROW WHEN (((new.rating IS NOT NULL) AND (new.rating <= 2))) EXECUTE FUNCTION fn_emit_customer_complaint_from_review();
CREATE TRIGGER z92_outcome_learning AFTER INSERT ON public.reviews FOR EACH ROW EXECUTE FUNCTION trg_outcome_learning();
CREATE TRIGGER ingest_case_lessons AFTER INSERT OR UPDATE OF ai_summary ON public.rfq_archives FOR EACH ROW EXECUTE FUNCTION trg_ingest_case_lessons();
CREATE TRIGGER trg_audit_roles AFTER INSERT OR DELETE OR UPDATE ON public.roles FOR EACH ROW EXECUTE FUNCTION fn_security_audit();
CREATE TRIGGER z10_it_judge_routine_change AFTER INSERT ON public.routine_change_log FOR EACH ROW EXECUTE FUNCTION trg_it_judge_routine_change();
CREATE TRIGGER a00_sales_decision_log_e2e_run_tag BEFORE INSERT ON public.sales_decision_log FOR EACH ROW EXECUTE FUNCTION fn_ai_cost_log_e2e_run_tag();
CREATE TRIGGER zz_knowledge_library_mirror_citation AFTER INSERT OR DELETE OR UPDATE OF cited ON public.sales_decision_log FOR EACH ROW EXECUTE FUNCTION fn_knowledge_library_mirror_citation();
CREATE TRIGGER a10_sales_knowledge_search_vector BEFORE INSERT OR UPDATE OF title, tags, content ON public.sales_knowledge FOR EACH ROW EXECUTE FUNCTION fn_sales_knowledge_search_vector();
CREATE TRIGGER z90_sales_knowledge_export_change_del AFTER DELETE ON public.sales_knowledge REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION trg_table_export_change('record_id', 'record_id,record_type,domain,title,content,structured_data,source_ids,epistemic_status,jurisdiction,pack_id,pack_version,record_version,body_sha256,content_sha256,runtime_index_eligible,authority_effect,tags,updated_at,ingested_at,search');
CREATE TRIGGER z90_sales_knowledge_export_change_ins AFTER INSERT ON public.sales_knowledge REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION trg_table_export_change('record_id', 'record_id,record_type,domain,title,content,structured_data,source_ids,epistemic_status,jurisdiction,pack_id,pack_version,record_version,body_sha256,content_sha256,runtime_index_eligible,authority_effect,tags,updated_at,ingested_at,search');
CREATE TRIGGER z90_sales_knowledge_export_change_trunc AFTER TRUNCATE ON public.sales_knowledge FOR EACH STATEMENT EXECUTE FUNCTION trg_table_export_change('record_id', 'record_id,record_type,domain,title,content,structured_data,source_ids,epistemic_status,jurisdiction,pack_id,pack_version,record_version,body_sha256,content_sha256,runtime_index_eligible,authority_effect,tags,updated_at,ingested_at,search');
CREATE TRIGGER z90_sales_knowledge_export_change_upd AFTER UPDATE ON public.sales_knowledge REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION trg_table_export_change('record_id', 'record_id,record_type,domain,title,content,structured_data,source_ids,epistemic_status,jurisdiction,pack_id,pack_version,record_version,body_sha256,content_sha256,runtime_index_eligible,authority_effect,tags,updated_at,ingested_at,search');
CREATE TRIGGER z_ml_vectors_stale AFTER UPDATE OF title, content ON public.sales_knowledge FOR EACH ROW WHEN (((old.title IS DISTINCT FROM new.title) OR (old.content IS DISTINCT FROM new.content))) EXECUTE FUNCTION fn_ml_vectors_stale('sales_knowledge', 'record_id');
CREATE TRIGGER z_ml_vectors_stale_del AFTER DELETE ON public.sales_knowledge FOR EACH ROW EXECUTE FUNCTION fn_ml_vectors_stale('sales_knowledge', 'record_id');
CREATE TRIGGER zz_knowledge_library_mirror AFTER INSERT OR DELETE OR UPDATE OF record_id, title, content, tags, pack_id, source_ids, epistemic_status, runtime_index_eligible, embedding_gte ON public.sales_knowledge FOR EACH ROW EXECUTE FUNCTION fn_knowledge_library_mirror();
CREATE TRIGGER a00_sanctions_ban_is_append_only BEFORE DELETE OR UPDATE ON public.sanctions_ban FOR EACH ROW EXECUTE FUNCTION fn_sanctions_ban_is_append_only();
CREATE TRIGGER a00_sanctions_ban_no_truncate BEFORE TRUNCATE ON public.sanctions_ban FOR EACH STATEMENT EXECUTE FUNCTION fn_sanctions_ban_is_append_only();
CREATE TRIGGER a00_entry_cited_is_kept BEFORE DELETE ON public.screening_entry FOR EACH ROW EXECUTE FUNCTION fn_screening_record_is_never_deleted();
CREATE TRIGGER a00_screening_entry_normalise BEFORE INSERT OR UPDATE OF name ON public.screening_entry FOR EACH ROW EXECUTE FUNCTION trg_screening_entry_normalise();
CREATE TRIGGER a00_run_is_never_deleted BEFORE DELETE ON public.screening_run FOR EACH ROW EXECUTE FUNCTION fn_screening_record_is_never_deleted();
CREATE TRIGGER z70_seat_playbook_learns AFTER INSERT OR UPDATE OF lessons ON public.seat_case_memory FOR EACH ROW WHEN ((cardinality(new.lessons) > 0)) EXECUTE FUNCTION trg_seat_playbook_learns();
CREATE TRIGGER z_ml_vectors_stale AFTER UPDATE OF situation ON public.seat_case_memory FOR EACH ROW WHEN ((old.situation IS DISTINCT FROM new.situation)) EXECUTE FUNCTION fn_ml_vectors_stale('seat_case_memory', 'id');
CREATE TRIGGER z_ml_vectors_stale_del AFTER DELETE ON public.seat_case_memory FOR EACH ROW EXECUTE FUNCTION fn_ml_vectors_stale('seat_case_memory', 'id');
CREATE TRIGGER trg_seat_deliberation_guard BEFORE INSERT OR UPDATE ON public.seat_deliberation FOR EACH ROW EXECUTE FUNCTION trg_seat_deliberation_guard();
CREATE TRIGGER a04_ceo_turn_carries_its_reasons BEFORE INSERT OR UPDATE ON public.seat_deliberation_turn FOR EACH ROW EXECUTE FUNCTION trg_ceo_turn_carries_its_reasons();
CREATE TRIGGER trg_seat_deliberation_turn_guard BEFORE INSERT OR UPDATE ON public.seat_deliberation_turn FOR EACH ROW EXECUTE FUNCTION trg_seat_deliberation_turn_guard();
CREATE TRIGGER z93_high_stakes_review AFTER INSERT ON public.seat_deliberation_turn FOR EACH ROW EXECUTE FUNCTION trg_high_stakes_review();
CREATE TRIGGER z70_seat_playbook_follows_duties AFTER INSERT OR DELETE OR UPDATE OF duty, owner_seat, every, routine, what, enabled ON public.seat_duty FOR EACH STATEMENT EXECUTE FUNCTION trg_seat_playbook_learns();
CREATE TRIGGER z70_seat_playbook_follows_kinds AFTER INSERT OR DELETE OR UPDATE ON public.seat_handoff_kind FOR EACH STATEMENT EXECUTE FUNCTION trg_seat_playbook_learns();
CREATE TRIGGER trg_sec_audit_immutable BEFORE DELETE OR UPDATE ON public.security_audit_log FOR EACH ROW EXECUTE FUNCTION fn_security_audit_immutable();
CREATE TRIGGER trg_event_selfreview AFTER INSERT ON public.self_review FOR EACH ROW EXECUTE FUNCTION fn_emit_event('self_review', 'process.repeated_failure');
CREATE TRIGGER trg_ensure_category_agent AFTER INSERT ON public.seo_categories FOR EACH ROW EXECUTE FUNCTION ensure_category_agent();
CREATE TRIGGER a06_names_no_supplier BEFORE INSERT OR UPDATE OF body, direction, author ON public.social_message FOR EACH ROW EXECUTE FUNCTION trg_published_text_names_no_supplier();
CREATE TRIGGER z90_case_memory AFTER INSERT OR UPDATE OF outcome, body ON public.social_message FOR EACH ROW EXECUTE FUNCTION trg_case_memory_social_reply();
CREATE TRIGGER a06_names_no_supplier BEFORE INSERT OR UPDATE OF content ON public.social_posts FOR EACH ROW EXECUTE FUNCTION trg_published_text_names_no_supplier();
CREATE TRIGGER a06_names_no_supplier BEFORE INSERT OR UPDATE OF reply_en, reply_ar ON public.social_reply_library FOR EACH ROW EXECUTE FUNCTION trg_published_text_names_no_supplier();
CREATE TRIGGER z90_case_memory AFTER INSERT OR UPDATE OF state, accepted_value ON public.spec_alternative_offer FOR EACH ROW EXECUTE FUNCTION trg_case_memory_spec_offer();
CREATE TRIGGER trg_stripe_dispute_counts_the_customer AFTER INSERT OR UPDATE OF transaction_id ON public.stripe_dispute FOR EACH ROW EXECUTE FUNCTION fn_stripe_dispute_counts_the_customer();
CREATE TRIGGER z91_judgement_outcome AFTER UPDATE OF status ON public.stripe_dispute FOR EACH ROW EXECUTE FUNCTION trg_judgement_outcome();
CREATE TRIGGER supplier_capabilities_source_docs_moves_v BEFORE UPDATE OF source_docs ON public.supplier_capabilities FOR EACH ROW EXECUTE FUNCTION fn_supplier_source_docs_moves_v();
CREATE TRIGGER a10_supplier_collaboration_event_append_only BEFORE DELETE OR UPDATE ON public.supplier_collaboration_event FOR EACH ROW EXECUTE FUNCTION fn_supplier_collaboration_event_append_only();
CREATE TRIGGER trg_supplier_due_paid_records_payment AFTER INSERT OR UPDATE OF paid_at ON public.supplier_dues FOR EACH ROW EXECUTE FUNCTION fn_supplier_due_paid_records_payment();
CREATE TRIGGER z91_judgement_outcome AFTER UPDATE OF first_response_at, closed_at ON public.supplier_response_watch FOR EACH ROW EXECUTE FUNCTION trg_judgement_outcome();
CREATE TRIGGER a00_hit_is_never_deleted BEFORE DELETE ON public.supplier_screening_hit FOR EACH ROW EXECUTE FUNCTION fn_screening_record_is_never_deleted();
CREATE TRIGGER a00_hit_is_never_truncated BEFORE TRUNCATE ON public.supplier_screening_hit FOR EACH STATEMENT EXECUTE FUNCTION fn_screening_record_is_never_deleted();
CREATE TRIGGER a10_supplier_strike_event_append_only BEFORE DELETE OR UPDATE ON public.supplier_strike_event FOR EACH ROW EXECUTE FUNCTION fn_supplier_strike_event_append_only();
CREATE TRIGGER a00_supplier_whatsapp_optin_obeys_the_rule BEFORE INSERT OR UPDATE ON public.supplier_whatsapp_optin FOR EACH ROW EXECUTE FUNCTION fn_supplier_whatsapp_optin_obeys_the_rule();
CREATE TRIGGER a10_support_case_lifecycle BEFORE INSERT OR UPDATE OF state ON public.support_case FOR EACH ROW EXECUTE FUNCTION fn_support_case_lifecycle();
CREATE TRIGGER a11_support_case_kind_category BEFORE INSERT ON public.support_case FOR EACH ROW EXECUTE FUNCTION fn_support_case_kind_category();
CREATE TRIGGER trg_support_case_closed_asks_for_the_rating AFTER UPDATE OF state ON public.support_case FOR EACH ROW EXECUTE FUNCTION fn_support_case_closed_asks_for_the_rating();
CREATE TRIGGER trg_support_case_closed_tells_the_reporter AFTER UPDATE OF state ON public.support_case FOR EACH ROW EXECUTE FUNCTION fn_support_case_closed_tells_the_reporter();
CREATE TRIGGER z90_case_memory AFTER INSERT OR UPDATE OF state, closed_at, close_reason ON public.support_case FOR EACH ROW EXECUTE FUNCTION trg_case_memory_support_case();
CREATE TRIGGER a00_support_case_summary_version_append_only BEFORE DELETE OR UPDATE ON public.support_case_summary_version FOR EACH ROW EXECUTE FUNCTION fn_support_case_summary_version_is_append_only();
CREATE TRIGGER a10_support_knowledge_search_vector BEFORE INSERT OR UPDATE OF title, tags, body ON public.support_knowledge FOR EACH ROW EXECUTE FUNCTION fn_support_knowledge_search_vector();
CREATE TRIGGER trg_support_knowledge_text_change_clears_embedding BEFORE UPDATE OF title, body ON public.support_knowledge FOR EACH ROW EXECUTE FUNCTION fn_knowledge_text_change_clears_embedding();
CREATE TRIGGER z_ml_vectors_stale AFTER UPDATE OF title, body ON public.support_knowledge FOR EACH ROW WHEN (((old.title IS DISTINCT FROM new.title) OR (old.body IS DISTINCT FROM new.body))) EXECUTE FUNCTION fn_ml_vectors_stale('support_knowledge', 'record_id');
CREATE TRIGGER z_ml_vectors_stale_del AFTER DELETE ON public.support_knowledge FOR EACH ROW EXECUTE FUNCTION fn_ml_vectors_stale('support_knowledge', 'record_id');
CREATE TRIGGER zz_knowledge_library_mirror AFTER INSERT OR DELETE OR UPDATE OF record_id, title, body, tags, language, source_path, pack_id, source_ids, review_status, runtime_index_eligible, embedding_gte ON public.support_knowledge FOR EACH ROW EXECUTE FUNCTION fn_knowledge_library_mirror();
CREATE TRIGGER z50_support_notification_to_outbox BEFORE INSERT ON public.support_notification FOR EACH ROW EXECUTE FUNCTION fn_support_notification_to_outbox();
CREATE TRIGGER a00_support_reply_readability_e2e_run_tag BEFORE INSERT ON public.support_reply_readability FOR EACH ROW EXECUTE FUNCTION fn_ai_cost_log_e2e_run_tag();
CREATE TRIGGER z91_judgement_outcome AFTER INSERT ON public.target_verdict FOR EACH ROW EXECUTE FUNCTION trg_judgement_outcome();
CREATE TRIGGER z20_routine_trade_words_enqueue AFTER INSERT ON public.taxonomy_trade_proposal FOR EACH ROW EXECUTE FUNCTION trg_routine_trade_words_enqueue();
CREATE TRIGGER trg_accountant_files_reveal_invoice AFTER INSERT OR UPDATE OF doc_path ON public.transactions FOR EACH ROW EXECUTE FUNCTION fn_accountant_files_reveal_invoice();
CREATE TRIGGER trg_emit_refund_requested_tx AFTER UPDATE OF refund_status ON public.transactions FOR EACH ROW WHEN (((new.refund_status = 'requested'::text) AND (old.refund_status IS DISTINCT FROM new.refund_status))) EXECUTE FUNCTION fn_emit_refund_requested_from_transaction();
CREATE TRIGGER trg_event_transaction AFTER INSERT ON public.transactions FOR EACH ROW EXECUTE FUNCTION fn_emit_event('transaction', 'payment.received');
CREATE TRIGGER trg_reveal_window_b BEFORE INSERT OR UPDATE ON public.transactions FOR EACH ROW EXECUTE FUNCTION trg_reveal_window();
CREATE TRIGGER z20_reveal_receipt AFTER INSERT OR UPDATE OF revealed_at ON public.transactions FOR EACH ROW EXECUTE FUNCTION trg_reveal_receipt();
CREATE TRIGGER z25_reveal_opens_response_watch AFTER INSERT OR UPDATE OF revealed_at, fee_status ON public.transactions FOR EACH ROW EXECUTE FUNCTION trg_reveal_opens_response_watch();
CREATE TRIGGER z30_decision_closes_unanswered_holds AFTER INSERT OR UPDATE OF revealed_at ON public.transactions FOR EACH ROW EXECUTE FUNCTION trg_decision_closes_unanswered_holds();
CREATE TRIGGER z40_refund_outcome_follows_through AFTER UPDATE OF refund_status, refund_amount_aed ON public.transactions FOR EACH ROW EXECUTE FUNCTION fn_transaction_refund_outcome_follows_through();
CREATE TRIGGER z70_document_landed_kicks_backup AFTER INSERT OR UPDATE OF doc_path ON public.transactions FOR EACH STATEMENT EXECUTE FUNCTION trg_document_landed_kicks_backup();
CREATE TRIGGER a00_unsubscribe_refusal_throttle BEFORE INSERT ON public.unsubscribe_refusal FOR EACH ROW EXECUTE FUNCTION fn_unsubscribe_refusal_throttle();
CREATE TRIGGER trg_audit_user_roles AFTER INSERT OR DELETE OR UPDATE ON public.user_roles FOR EACH ROW EXECUTE FUNCTION fn_security_audit();
CREATE TRIGGER trg_wa_signature_watch AFTER INSERT ON public.wa_messages FOR EACH ROW EXECUTE FUNCTION fn_wa_signature_watch();
CREATE TRIGGER z50_support_wire_whatsapp AFTER INSERT OR UPDATE OF sent ON public.wa_messages FOR EACH ROW EXECUTE FUNCTION fn_support_wire_whatsapp();
CREATE TRIGGER z51_support_classify_whatsapp AFTER INSERT OR UPDATE OF meta ON public.wa_messages FOR EACH ROW EXECUTE FUNCTION fn_support_classify_whatsapp();
CREATE TRIGGER a00_step_run_actor_is_a_real_employee BEFORE INSERT OR UPDATE OF actor, status ON public.workflow_step_run FOR EACH ROW EXECUTE FUNCTION trg_step_run_actor_is_a_real_employee();

-- ===== ROW LEVEL SECURITY (enable) =====
ALTER TABLE public.accountant_ad_spend_month ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accountant_budget_variance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accountant_cash_forecast_week ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accountant_founder_close_pack ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accountant_issued_document ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accountant_knowledge ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accountant_mailbox_check ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accountant_month_close ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accountant_month_scan ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accountant_owner_ruled_subscription ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accountant_renewal_budget ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accountant_reveal_reconcile_item ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accountant_reveal_reconcile_run ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accountant_spend_report ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accountant_subscription_paid_from_change ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accountant_ubo_seen ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accountant_vat_threshold_check ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accountant_weekly_report ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accountant_year_end_pack ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.action_class_demand ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.action_class_gate ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.action_execution ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ad_campaign_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ad_decision ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ad_spend_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ad_spend_reported ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_mfa_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_action_kind_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_command_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_context_head ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_context_retrieval ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_evals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_expectations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_governance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_knowledge ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_memory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_pending_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_remediation ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_reputation ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_tool ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_tool_call ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_training_attempt ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_training_case ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_constitution ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_cost_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_model_register ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_qa_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_quality_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_rate_limit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_trainer_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alert_signature ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alert_watermark ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.allocation_change ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ap_bills ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_blocked_domains ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_secrets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arabic_compare_waiter ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arabic_document_waiter ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arabic_outbound_hold ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arabic_translation ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.artifact_platform_spec ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.artifact_review ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assistant_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.autonomy_control_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.autonomy_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.backup_prune_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bank_line_owner_ruling ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bank_reference_code ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bank_statement_intake ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bank_statement_line ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.blog_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.board_advisor ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.board_opinion ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.board_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.boq_fixture ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.boq_fixture_run ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.boq_section_reading ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.brand_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.break_even_basis ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.break_even_cost_line ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.budget_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.budgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.business_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cad_read_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.canon_eval_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.canon_eval_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalog_category_domain ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalog_domains ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalog_subcategories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalog_supplier_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.category_agent_map ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.category_agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.category_keyword ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.category_quote_specs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.category_route_map ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.category_specs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_approval ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_break_even_month ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_break_even_replan ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_brief_line ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_command ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_command_intent ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_command_rule ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_command_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_command_transition ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_company_stage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_company_stage_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_constraint_lever ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_daily_digest ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_day ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_decision ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_decision_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_decision_round ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_directive ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_experiment ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_experiment_verdict ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_growth_action ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_identity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_improvement ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_invite_trade_priority ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_knowledge ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_launch_gate ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_mandate ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_market_report ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_month_close ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_month_report ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_plan ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_plan_action ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_plan_month ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_pricing_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_refund_decision_metric ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_review ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_seat_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_seat_directive ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_seat_month_target ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_standing_grant ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_strategy_memo ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_supplier_channel ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_supplier_funnel_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_supplier_goal ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_task ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_task_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_weekly_report ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_weekly_review ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_year_plan ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_year_plan_archive ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ceo_year_plan_milestone ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.challenge_heuristic ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.challenge_record ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_directive ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.charge_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_threads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_violations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.collaboration_rule ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.collections_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_brand ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_calendar ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_charter ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_constitution ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_faq ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_faq_embed_inflight ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_financial_stance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_index ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_policy_decision ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_reflection ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_registration ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_reputation_snapshot ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_review_ask ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_snapshot ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_stand_down ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_vision ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comparison_run_v2 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.competitive_position ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.competitor ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.competitor_scan ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.complaint_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.compliance_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contact_duplicate_group ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contact_merge_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contact_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.content_drafts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.continuity_plan ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.control_mode_action ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.control_mode_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.control_mode_challenge ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.control_mode_identity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.control_mode_session ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_archive ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_archive_attempt ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_retention_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_retention_pdf ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_retention_plan_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.critical_capability ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_stages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cron_job_seen ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cron_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_calls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_followup ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_kpi_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_layout ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_phone_otps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_preference ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_score ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_spec_guide ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_support_case_review ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_support_data_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_support_duty_message ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_support_inbound_drive ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_support_monthly_review ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_support_reply_quality_week ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_support_voc_month ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_support_voice_owed ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_trade_waitlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dead_letter ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.decision_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.decision_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.decision_record ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.decision_review_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.decision_trace ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delegation_rule ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deliverability_test ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deliverability_test_provider ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.demand_forecast ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.demand_search ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.department_budget ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.department_objective ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deploy_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dept_knowledge_alias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dept_library ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.doc_backups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.doc_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.doc_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_kpi_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drawing_redaction_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dropbox_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.duty_pause ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ea_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ea_meetings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ea_reminders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.edge_expectation ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.edge_health_probe ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_block_pattern ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_domain_mx ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_open_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_open_token ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_platform_domain ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_suppressions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_verifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employee_authority ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employee_knowledge ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employee_knowledge_standard ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employee_kpi ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employee_kpi_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employee_workflow ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.entity_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.error_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_assessment ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_delivery ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_rollup ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_subscription ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.evolution_proposal ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exec_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_bank_match ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_billing_mailbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_sender_reading ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_vendor_billing_mailbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.field_definition ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.field_definition_reference ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.field_definition_trade ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.file_scan ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.finance_kpi_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.finance_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.finance_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fn_task_class ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.founder_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.founder_directive ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.founder_habit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.founder_hold ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.founder_instruction ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.founder_mail_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.founder_mail_policy_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fraud_flags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.free_email_domain ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.function_owner ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gl_account_funnel_stage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gl_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gl_expense_map ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gl_journal ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gl_journal_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gl_prior_period_adjustment ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gl_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.goal_period ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.governance_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.governance_sensitive ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.graph_edges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.graph_nodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.handoff_contract ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.health_checks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.health_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.idea ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inbound_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_answer ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_answer_conflict ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_answer_conflict_value ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_answer_corroboration ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_answer_document ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_answer_scope ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_cancellations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_conversation_summary ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_gate ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_gate_required ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_intake ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_requirement ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_scope_disposition ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_state_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_supplier_brief ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_trade_candidate ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_trade_candidate_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_trade_clarification ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_workstream ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_workstream_group ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_workstream_requirement ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.institutional_memory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.intake_trade_taxonomy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_matrix ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.internal_credential ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.internal_credential_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inv_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invite_brake ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invite_placement_bar ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invite_placement_check ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invite_schedule ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_access_known ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_change_acceptance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_change_revision ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_change_source ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_cost_watch_week ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_credential_class ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_credential_rotation ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_duty_schedule ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_engineer_finding ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_engineer_knowledge ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_engineer_scanner ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_expected_table_growth ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_expiry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_finding_closure ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_founder_decision_class ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_game_day_run ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_hold_signature ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_incident ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_integration_external_cause ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_load_test_run ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_model_consumer ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_playbook ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_postmaster_reading ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_query_stat_snapshot ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_refusal_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_restore_drill_result ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_restore_drill_table ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_safe_fix_family ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_safe_fix_run ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_security_baseline ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_sender_health_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_session_fix_day ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_spend_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_table_size_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_threshold ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_watch_finding ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_watch_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_watch_subject ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_watch_tick ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kb_category_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kb_category_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kb_chunk_quarantine ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kb_chunks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kb_chunks_swap_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kb_citation_jurisdiction ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kb_embed_inflight ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kb_embed_priority ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kb_operational_alias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kb_operational_route ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kb_operational_route_map ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kb_operational_route_test ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kb_purge_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kb_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kb_route_scope_trigger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kb_trim_hash ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kb_trim_plan ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kb_usage_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.knowledge_domain ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.knowledge_exam_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.knowledge_exam_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.knowledge_ingestion_run ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.knowledge_ingestion_undo ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.knowledge_internal_figure_record ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.knowledge_kpi_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.knowledge_library ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.knowledge_library_origin ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.knowledge_library_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.knowledge_ml_claim ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.knowledge_ml_status ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.knowledge_module_standard ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.knowledge_vector_ml ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_category ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_email_check ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_prospect ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_sourcing_run ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_subcategory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_trade_class ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_trade_map ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.legal_checklist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.legal_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.legal_kpi_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.legal_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.licence_renewal_ask ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.line_spec_reading ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.llm_attempt ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.llm_cache ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.llm_calls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.llm_failure_class ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.llm_route_health ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.llm_seat_binding ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mailbox_reply_decision ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.market_intel ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_ad_spend_day ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_article ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_article_round ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_asset_feature ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_asset_perception ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_asset_review ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_blog_topic ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_calendar_resend_decision ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_campaign ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_connection_check ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_duty_record ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_duty_run ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_fact_watch ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_first_touch ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_founder_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_gap_recruitment_plan ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_geo_check ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_geo_fix ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_geo_question ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_goal ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_insight_day ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_insight_note ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_knowledge ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_library ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_meta_page ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_model_run ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_month_plan ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_outreach_message ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_plan_doc ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_plan_review_turn ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_platform_spec ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_platform_spec_source ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_post ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_post_channel_result ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_post_metric ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_post_platform ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_post_variant ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_prospect ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_recruitment_source ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_report ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_review ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_scorecard_report ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_step_release ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_trend ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_trend_source ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_video_idea ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.match_eval_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mdm_brands ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mdm_manufacturers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mdm_standards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mep_evidence_weight ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mep_trade ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messaging_template ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meta_insights ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.metric_definition ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.metric_snapshot ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.model_catalogue_change ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.model_fallback_chain ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.model_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.model_policy_by_identity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.model_rate ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.model_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.money_move_hold ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notice_plain_language ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notice_plain_language_cause ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_copy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_type_severity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.openrouter_day ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.openrouter_meter ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.operating_system ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.opportunity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ops_knowledge ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ops_kpi_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_action_executor ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_agent_alias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_authority ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_category_identity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_committee ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_memory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_objectives ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_onboarding ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_phase_baseline ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_reporting_edge ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_role ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_role_alias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_role_committee ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_role_identity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_task_kind_handler ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_task_question_reading ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_workflow_ownership ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_workflow_step ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.originator_close_record ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.os_audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.os_department ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.os_fresh_start ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.os_incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.os_interface ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.os_knowledge_domain ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.os_objective ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.os_open_access_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.os_responsibility ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.os_review ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.os_runbooks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.os_settings_meta ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.otp_blocked_prefix ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.otp_prefix_allowed ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.otp_served_country ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outcome_record ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outreach ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outreach_channel_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.paid_route_exception ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdpl_erase_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdpl_lead_erase_vault ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdpl_operator_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdpl_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.phase1_rollback_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.phone_code ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.phone_verifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.po_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.po_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.po_vendors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.policy_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_reveal_dispute ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.price_benchmark ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.price_trade_term ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pricing_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prompt_benchmarks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prompt_eval_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prompt_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prompts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.public_holidays ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qa_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qd_compare_cache ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qd_deploy_src ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qd_i18n ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qd_i18n_chunks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qualification_playbooks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quality_standard ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_aspect_reading ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_committed_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_comparisons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_extraction_model ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_pdf_cache ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_quality_hold ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_requirements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_review_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_review_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_spec_hold ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quotes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reasoning_held_question ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reasoning_knowledge_candidate ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.red_episode ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refund_case ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refund_ceo_check ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refund_ceo_review ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refund_event_quarantine ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refund_incident ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refund_ladder_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refund_status_transition ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reg_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regulations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rehearsal_spend_reservation ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rehearsal_window ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.removed_trigger_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.resilience_step ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.resource_pool ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.response_template ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.retention_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reveal_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.review_chain ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.review_hold ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.review_pool ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.review_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.review_route ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rfq_archives ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rfq_clarification ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.risk_register ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rl_hits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routine_change_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routine_judgement ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_decision_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_engineer_comparison_report ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_engineer_framework_proposal ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_engineer_negotiation_round ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_engineer_onboarding_week ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_engineer_win_loss_month ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_knowledge ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_knowledge_gap ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_qualification_field ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_sector ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sanctions_ban ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scenario_library ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scope_component ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scope_disposition_kind ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scrape_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.screening_entry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.screening_run ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_case_memory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_case_memory_miss ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_deliberation ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_deliberation_ceiling ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_deliberation_turn ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_duty ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_duty_skip ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_exam_asked ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_exam_fix ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_exam_item ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_handoff_kind ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_judgement ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_knowledge_eval_question ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_knowledge_exam ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_knowledge_recall ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_knowledge_recall_answer ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_knowledge_recall_floor ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_knowledge_refresh ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_knowledge_stale ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_learning_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_lesson_cluster ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_playbook ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_self_review ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_senior_contribution ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_senior_exam ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seat_senior_verdict ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.security_advisor_baseline ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.security_audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.security_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.security_gap ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.security_kpi_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.self_review ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seo_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_alias_proposal ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_implication ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.signup_purge ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.signup_purge_dropbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.signup_purge_object ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.simulations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.site_uptime_check ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.skills_matrix ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sms_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.social_connect_link ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.social_conversation ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.social_message ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.social_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.social_reply_library ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.spec_alternative_offer ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.spec_backlog ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stalled_inquiry_rescue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.strategy_risks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stripe_dispute ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stripe_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stripe_payout ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stripe_setting_reading ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subcategory_agent_map ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_availability ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_beneficial_owner ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_campaign_daily_list ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_capabilities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_capability_confirmation ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_capability_reading ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_collaboration ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_collaboration_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_document_cache ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_due_checkouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_due_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_dues ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_kpi_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_lead_intake ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_onboarding ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_opportunity_score ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_own_word_reading ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_performance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_product ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_product_variant ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_public_name ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_quote_template ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_recruitment_funnel ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_reply_followup ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_response_watch ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_score ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_scorecard ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_screening_hit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_service_question ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_strike_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_voice_note ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_whatsapp_consent_ask ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_whatsapp_optin ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supply_gap ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supply_health_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supply_recruitment_brief ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_artifact ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_case ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_case_promise ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_case_summary_version ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_category ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_cause_week ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_ceo_report ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_customer_profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_document_intake ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_identity_challenge ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_knowledge ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_notification ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_public_override ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_reply_readability ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_root_cause ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_root_cause_fix ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_signal_category ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.table_export_change ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.table_export_change_tracked ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.table_export_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.table_export_run ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.target_contract ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.target_daily_verdict ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.target_driver ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.target_label ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.target_path ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.target_verdict ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.taxonomy_role ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.taxonomy_trade ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.taxonomy_trade_adjacent ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.taxonomy_trade_code ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.taxonomy_trade_group ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.taxonomy_trade_proposal ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.taxonomy_trade_service ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trade_customer_opening ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trade_opening_rule ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trade_spec_checklist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ui_label ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.undo_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.unsubscribe_refusal ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendor_billing_ended ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vision_horizon ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vt_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wa_answer_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wa_conversation ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wa_document_intake ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wa_inbound_seen ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wa_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wa_reply_intent ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wa_sender_quality_reading ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wa_template_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wa_turn ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.web_search_day ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_run ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_step ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_step_run ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.writer_seat ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.yello_staging ENABLE ROW LEVEL SECURITY;

-- ===== POLICIES =====
CREATE POLICY accountant_ad_spend_month_service_role_only ON public.accountant_ad_spend_month AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY accountant_budget_variance_service_role_only ON public.accountant_budget_variance AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY accountant_cash_forecast_week_service_role_only ON public.accountant_cash_forecast_week AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY accountant_founder_close_pack_service_role_only ON public.accountant_founder_close_pack AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY accountant_issued_document_service_role_only ON public.accountant_issued_document AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY accountant_mailbox_check_service_role_only ON public.accountant_mailbox_check AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY accountant_month_close_service_role_only ON public.accountant_month_close AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY accountant_month_scan_service_role_only ON public.accountant_month_scan AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY accountant_owner_ruled_subscription_service_role_only ON public.accountant_owner_ruled_subscription AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY accountant_renewal_budget_service_role_only ON public.accountant_renewal_budget AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY accountant_reveal_reconcile_item_service_role_only ON public.accountant_reveal_reconcile_item AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY accountant_reveal_reconcile_run_service_role_only ON public.accountant_reveal_reconcile_run AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY accountant_subscription_paid_from_change_service_role_only ON public.accountant_subscription_paid_from_change AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY accountant_ubo_seen_service_role_only ON public.accountant_ubo_seen AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY accountant_vat_threshold_check_service_role_only ON public.accountant_vat_threshold_check AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY accountant_year_end_pack_service_role_only ON public.accountant_year_end_pack AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY action_class_demand_service_role_only ON public.action_class_demand AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ad_spend_reported_service_role_only ON public.ad_spend_reported AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY os_owner_admin_read ON public.ai_cost_log AS PERMISSIVE FOR SELECT TO authenticated USING ((fn_role_of((auth.jwt() ->> 'email'::text)) = ANY (ARRAY['owner'::text, 'admin'::text])));
CREATE POLICY arabic_compare_waiter_service_role_only ON public.arabic_compare_waiter AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY arabic_document_waiter_service_role_only ON public.arabic_document_waiter AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY arabic_outbound_hold_service_role_only ON public.arabic_outbound_hold AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY arabic_translation_service_role_only ON public.arabic_translation AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY backup_prune_log_service_role_only ON public.backup_prune_log AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY bank_line_owner_ruling_service_role_only ON public.bank_line_owner_ruling AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY bank_reference_code_service_role_only ON public.bank_reference_code AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY bank_statement_intake_service_role_only ON public.bank_statement_intake AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY bank_statement_line_service_role_only ON public.bank_statement_line AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY blog_posts_public_read ON public.blog_posts AS PERMISSIVE FOR SELECT TO anon USING ((published = true));
CREATE POLICY boq_section_reading_service_role_only ON public.boq_section_reading AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY brand_assets_public_read ON public.brand_assets AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY break_even_basis_service_role_only ON public.break_even_basis AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY break_even_cost_line_service_role_only ON public.break_even_cost_line AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY cad_read_jobs_service_role_only ON public.cad_read_jobs AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY "specs readable" ON public.category_specs AS PERMISSIVE FOR SELECT TO anon USING (true);
CREATE POLICY ceo_break_even_month_service_role_only ON public.ceo_break_even_month AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_break_even_replan_service_role_only ON public.ceo_break_even_replan AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_brief_line_service_role_only ON public.ceo_brief_line AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_company_stage_service_role_only ON public.ceo_company_stage AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_company_stage_log_service_role_only ON public.ceo_company_stage_log AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_constraint_lever_service_role_only ON public.ceo_constraint_lever AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_day_service_role_only ON public.ceo_day AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_decision_log_service_role_only ON public.ceo_decision_log AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_decision_round_service_role_only ON public.ceo_decision_round AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_directive_service_role_only ON public.ceo_directive AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_experiment_service_role_only ON public.ceo_experiment AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_experiment_verdict_service_role_only ON public.ceo_experiment_verdict AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_growth_action_service_role_only ON public.ceo_growth_action AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_improvement_service_role_only ON public.ceo_improvement AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_invite_trade_priority_service_role_only ON public.ceo_invite_trade_priority AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_launch_gate_service_role_only ON public.ceo_launch_gate AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_mandate_service_role_only ON public.ceo_mandate AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_market_report_service_role_only ON public.ceo_market_report AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_month_close_service_role_only ON public.ceo_month_close AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_month_report_service_role_only ON public.ceo_month_report AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_plan_service_role_only ON public.ceo_plan AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_plan_action_service_role_only ON public.ceo_plan_action AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_plan_month_service_role_only ON public.ceo_plan_month AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_pricing_evidence_service_role_only ON public.ceo_pricing_evidence AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_refund_decision_metric_service_role_only ON public.ceo_refund_decision_metric AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_review_service_role_only ON public.ceo_review AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_seat_audit_service_role_only ON public.ceo_seat_audit AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_seat_directive_service_role_only ON public.ceo_seat_directive AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_seat_month_target_service_role_only ON public.ceo_seat_month_target AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_strategy_memo_service_role_only ON public.ceo_strategy_memo AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_supplier_channel_service_role_only ON public.ceo_supplier_channel AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_supplier_funnel_daily_service_role_only ON public.ceo_supplier_funnel_daily AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_supplier_goal_service_role_only ON public.ceo_supplier_goal AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_weekly_report_service_role_only ON public.ceo_weekly_report AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_weekly_review_service_role_only ON public.ceo_weekly_review AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_year_plan_service_role_only ON public.ceo_year_plan AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_year_plan_archive_service_role_only ON public.ceo_year_plan_archive AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY ceo_year_plan_milestone_service ON public.ceo_year_plan_milestone AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY charge_audit_service_role_only ON public.charge_audit AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY company_faq_embed_inflight_service_role_only ON public.company_faq_embed_inflight AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY company_reputation_snapshot_service_role_only ON public.company_reputation_snapshot AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY company_review_ask_service_role_only ON public.company_review_ask AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY competitor_scan_service_role_only ON public.competitor_scan AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY complaint_tickets_service_role_only ON public.complaint_tickets AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY contact_duplicate_group_service_role_only ON public.contact_duplicate_group AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY contact_merge_audit_service_role_only ON public.contact_merge_audit AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY conversation_archive_service_role_only ON public.conversation_archive AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY conversation_archive_attempt_service_role_only ON public.conversation_archive_attempt AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY conversation_retention_log_service_only ON public.conversation_retention_log AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY conversation_retention_pdf_service_only ON public.conversation_retention_pdf AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY conversation_retention_plan_log_service_only ON public.conversation_retention_plan_log AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY customer_followup_service_role_only ON public.customer_followup AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY customer_spec_guide_public_reads_published ON public.customer_spec_guide AS PERMISSIVE FOR SELECT TO authenticated USING ((status = 'published'::text));
CREATE POLICY customer_support_case_review_service_role_only ON public.customer_support_case_review AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY customer_support_data_request_service_role_only ON public.customer_support_data_request AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY customer_support_duty_message_service_role_only ON public.customer_support_duty_message AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY customer_support_inbound_drive_service_role_only ON public.customer_support_inbound_drive AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY customer_support_monthly_review_service_role_only ON public.customer_support_monthly_review AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY customer_support_reply_quality_week_service_role_only ON public.customer_support_reply_quality_week AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY customer_support_voc_month_service_role_only ON public.customer_support_voc_month AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY customer_support_voice_owed_service_role_only ON public.customer_support_voice_owed AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY customer_trade_waitlist_service_role_only ON public.customer_trade_waitlist AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY os_owner_admin_read ON public.customers AS PERMISSIVE FOR SELECT TO authenticated USING ((fn_role_of((auth.jwt() ->> 'email'::text)) = ANY (ARRAY['owner'::text, 'admin'::text])));
CREATE POLICY decision_review_request_service_role_only ON public.decision_review_request AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY deliverability_test_service_role_only ON public.deliverability_test AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY deliverability_test_provider_service_role_only ON public.deliverability_test_provider AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY demand_forecast_service_role_only ON public.demand_forecast AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY demand_search_service_role_only ON public.demand_search AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY documents_customer_select ON public.documents AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM fn_customer_document_refs() r(ref_table, ref_id, source, supplier_id, supplier_name, revealed)
  WHERE ((r.ref_table = documents.ref_table) AND (r.ref_id = documents.ref_id)))));
CREATE POLICY duty_pause_service_role_only ON public.duty_pause AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY os_owner_admin_read ON public.edge_health_probe AS PERMISSIVE FOR SELECT TO authenticated USING ((fn_role_of((auth.jwt() ->> 'email'::text)) = ANY (ARRAY['owner'::text, 'admin'::text])));
CREATE POLICY email_open_event_service_role_only ON public.email_open_event AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY email_open_token_service_role_only ON public.email_open_token AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY email_platform_domain_service_role_only ON public.email_platform_domain AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY error_events_service_role_only ON public.error_events AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY expense_bank_match_service_role ON public.expense_bank_match AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY expense_sender_reading_service_role_only ON public.expense_sender_reading AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY os_owner_admin_read ON public.expenses AS PERMISSIVE FOR SELECT TO authenticated USING ((fn_role_of((auth.jwt() ->> 'email'::text)) = ANY (ARRAY['owner'::text, 'admin'::text])));
CREATE POLICY founder_hold_service_role_only ON public.founder_hold AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY founder_instruction_service_role_only ON public.founder_instruction AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY founder_mail_policy_history_service_role_only ON public.founder_mail_policy_history AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY free_email_domain_service_role_only ON public.free_email_domain AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY gl_account_funnel_stage_service_role_only ON public.gl_account_funnel_stage AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY os_owner_admin_read ON public.gl_journal AS PERMISSIVE FOR SELECT TO authenticated USING ((fn_role_of((auth.jwt() ->> 'email'::text)) = ANY (ARRAY['owner'::text, 'admin'::text])));
CREATE POLICY gl_prior_period_adjustment_service_role_only ON public.gl_prior_period_adjustment AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY governance_sensitive_service_role_only ON public.governance_sensitive AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY os_owner_admin_read ON public.inquiries AS PERMISSIVE FOR SELECT TO authenticated USING ((fn_role_of((auth.jwt() ->> 'email'::text)) = ANY (ARRAY['owner'::text, 'admin'::text])));
CREATE POLICY inquiry_conversation_summary_service_only ON public.inquiry_conversation_summary AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY inquiry_state_service_role_only ON public.inquiry_state AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY intake_trade_taxonomy_service_role_only ON public.intake_trade_taxonomy AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY invite_brake_service_role_only ON public.invite_brake AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY invite_placement_bar_service_role_only ON public.invite_placement_bar AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY invite_placement_check_service_role_only ON public.invite_placement_check AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_access_known_service_role_only ON public.it_access_known AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_change_acceptance_service_role_only ON public.it_change_acceptance AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_change_revision_service_role_only ON public.it_change_revision AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_change_source_service_role_only ON public.it_change_source AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_cost_watch_week_service_role_only ON public.it_cost_watch_week AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_credential_class_service_role_only ON public.it_credential_class AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_credential_rotation_service_role_only ON public.it_credential_rotation AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_duty_schedule_service_role_only ON public.it_duty_schedule AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_expected_table_growth_service_role_only ON public.it_expected_table_growth AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_expiry_service_role_only ON public.it_expiry AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_finding_closure_service_role_only ON public.it_finding_closure AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_founder_decision_class_service_role_only ON public.it_founder_decision_class AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_game_day_run_service_role_only ON public.it_game_day_run AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_hold_signature_service_role_only ON public.it_hold_signature AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_incident_service_role_only ON public.it_incident AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_integration_external_cause_service_role_only ON public.it_integration_external_cause AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_load_test_run_service_role_only ON public.it_load_test_run AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_model_consumer_service_role_only ON public.it_model_consumer AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_playbook_service_role_only ON public.it_playbook AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_postmaster_reading_service_role_only ON public.it_postmaster_reading AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_query_stat_snapshot_service_role_only ON public.it_query_stat_snapshot AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_refusal_policy_service_role_only ON public.it_refusal_policy AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_restore_drill_result_service_role_only ON public.it_restore_drill_result AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_restore_drill_table_service_role_only ON public.it_restore_drill_table AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_safe_fix_family_service_role_only ON public.it_safe_fix_family AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_safe_fix_run_service_role_only ON public.it_safe_fix_run AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_security_baseline_service_role_only ON public.it_security_baseline AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_sender_health_daily_service_role_only ON public.it_sender_health_daily AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_session_fix_day_service_role_only ON public.it_session_fix_day AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_spend_daily_service_role_only ON public.it_spend_daily AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_table_size_daily_service_role_only ON public.it_table_size_daily AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY it_threshold_service_role_only ON public.it_threshold AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY kb_chunk_quarantine_service_role_only ON public.kb_chunk_quarantine AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY os_owner_admin_read ON public.kb_chunks AS PERMISSIVE FOR SELECT TO authenticated USING ((fn_role_of((auth.jwt() ->> 'email'::text)) = ANY (ARRAY['owner'::text, 'admin'::text])));
CREATE POLICY kb_chunks_swap_log_service_role_only ON public.kb_chunks_swap_log AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY kb_citation_jurisdiction_service_role_only ON public.kb_citation_jurisdiction AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY kb_embed_inflight_service_role_only ON public.kb_embed_inflight AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY kb_embed_priority_service_role_only ON public.kb_embed_priority AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY kb_purge_ledger_service_role_only ON public.kb_purge_ledger AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY kb_trim_hash_service_role_only ON public.kb_trim_hash AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY kb_trim_plan_service_role_only ON public.kb_trim_plan AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY knowledge_internal_figure_record_service_role_only ON public.knowledge_internal_figure_record AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY knowledge_library_service_role_only ON public.knowledge_library AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY knowledge_library_origin_service_role_only ON public.knowledge_library_origin AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY knowledge_library_state_service_role_only ON public.knowledge_library_state AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY knowledge_ml_claim_service_role_only ON public.knowledge_ml_claim AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY knowledge_ml_status_service_role_only ON public.knowledge_ml_status AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY knowledge_vector_ml_service_role_only ON public.knowledge_vector_ml AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY lead_email_check_service_role_only ON public.lead_email_check AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY lead_prospect_service_role_only ON public.lead_prospect AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY lead_sourcing_run_service_role_only ON public.lead_sourcing_run AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY lead_trade_class_service_role_only ON public.lead_trade_class AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY os_owner_admin_read ON public.leads AS PERMISSIVE FOR SELECT TO authenticated USING ((fn_role_of((auth.jwt() ->> 'email'::text)) = ANY (ARRAY['owner'::text, 'admin'::text])));
CREATE POLICY line_spec_reading_service_role_only ON public.line_spec_reading AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY mailbox_reply_decision_service_role_only ON public.mailbox_reply_decision AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY market_intel_service_role_only ON public.market_intel AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_ad_spend_day_service_role_only ON public.marketing_ad_spend_day AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_article_service_role_only ON public.marketing_article AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_article_round_service_role_only ON public.marketing_article_round AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_asset_feature_service_role_only ON public.marketing_asset_feature AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_asset_perception_service_role_only ON public.marketing_asset_perception AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_asset_review_service_role_only ON public.marketing_asset_review AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_blog_topic_service_role_only ON public.marketing_blog_topic AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_calendar_resend_decision_service_role_only ON public.marketing_calendar_resend_decision AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_campaign_service_role_only ON public.marketing_campaign AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_connection_check_service_role_only ON public.marketing_connection_check AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_duty_record_service_role_only ON public.marketing_duty_record AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_duty_run_service_role_only ON public.marketing_duty_run AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_fact_watch_service_role_only ON public.marketing_fact_watch AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_first_touch_service_role_only ON public.marketing_first_touch AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_founder_request_service_role_only ON public.marketing_founder_request AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_gap_recruitment_plan_service_role_only ON public.marketing_gap_recruitment_plan AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_geo_check_service_role_only ON public.marketing_geo_check AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_geo_fix_service_role_only ON public.marketing_geo_fix AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_geo_question_service_role_only ON public.marketing_geo_question AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_goal_service_role_only ON public.marketing_goal AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_insight_day_service_role_only ON public.marketing_insight_day AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_insight_note_service_role_only ON public.marketing_insight_note AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_knowledge_service_role_only ON public.marketing_knowledge AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_meta_page_service_role_only ON public.marketing_meta_page AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_model_run_service_role_only ON public.marketing_model_run AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_month_plan_service_role_only ON public.marketing_month_plan AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_outreach_message_service_role_only ON public.marketing_outreach_message AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_plan_doc_service_role_only ON public.marketing_plan_doc AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_plan_review_turn_service_role_only ON public.marketing_plan_review_turn AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_platform_spec_service_role_only ON public.marketing_platform_spec AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_platform_spec_source_service_role_only ON public.marketing_platform_spec_source AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_post_service_role_only ON public.marketing_post AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_post_channel_result_service_role_only ON public.marketing_post_channel_result AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_post_metric_service_role_only ON public.marketing_post_metric AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_post_platform_service_role_only ON public.marketing_post_platform AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_post_variant_service_role_only ON public.marketing_post_variant AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_prospect_service_role_only ON public.marketing_prospect AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_recruitment_source_service_role_only ON public.marketing_recruitment_source AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_report_service_role_only ON public.marketing_report AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_review_service_role_only ON public.marketing_review AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_scorecard_report_service_role_only ON public.marketing_scorecard_report AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_step_release_service_role_only ON public.marketing_step_release AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_trend_service_role_only ON public.marketing_trend AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_trend_source_service_role_only ON public.marketing_trend_source AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY marketing_video_idea_service_role_only ON public.marketing_video_idea AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY model_catalogue_change_service_role_only ON public.model_catalogue_change AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY money_move_hold_service_role_only ON public.money_move_hold AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY notice_plain_language_service_role_only ON public.notice_plain_language AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY notice_plain_language_cause_service_role_only ON public.notice_plain_language_cause AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY notification_copy_service_role_only ON public.notification_copy AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY notification_type_severity_service_role_only ON public.notification_type_severity AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY os_owner_admin_read ON public.org_agents AS PERMISSIVE FOR SELECT TO authenticated USING ((fn_role_of((auth.jwt() ->> 'email'::text)) = ANY (ARRAY['owner'::text, 'admin'::text])));
CREATE POLICY org_task_kind_handler_service_role_only ON public.org_task_kind_handler AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY org_task_question_reading_service_role_only ON public.org_task_question_reading AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY originator_close_record_service_role_only ON public.originator_close_record AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY otp_blocked_prefix_service_role_only ON public.otp_blocked_prefix AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY otp_prefix_allowed_service_role_only ON public.otp_prefix_allowed AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY otp_served_country_service_role_only ON public.otp_served_country AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY paid_route_exception_service_role_only ON public.paid_route_exception AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY pdpl_lead_erase_vault_service_only ON public.pdpl_lead_erase_vault AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY pdpl_operator_log_service_only ON public.pdpl_operator_log AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY phone_code_service_role_only ON public.phone_code AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY post_reveal_dispute_service_role_only ON public.post_reveal_dispute AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY price_benchmark_service_role_only ON public.price_benchmark AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY price_trade_term_service_role_only ON public.price_trade_term AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY quote_aspect_reading_service_role_only ON public.quote_aspect_reading AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY quote_extraction_model_service_role_only ON public.quote_extraction_model AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY quote_quality_hold_service_role_only ON public.quote_quality_hold AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY quote_review_messages_supplier_reads_own ON public.quote_review_messages AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM quote_reviews r
  WHERE ((r.id = quote_review_messages.review_id) AND (r.owner_email IS NOT NULL) AND (r.owner_email = lower(COALESCE((( SELECT auth.jwt() AS jwt) ->> 'email'::text), ''::text)))))));
CREATE POLICY quote_review_request_supplier_reads_own ON public.quote_review_request AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM quote_reviews r
  WHERE ((r.id = quote_review_request.review_id) AND (r.owner_email IS NOT NULL) AND (r.owner_email = lower(COALESCE((( SELECT auth.jwt() AS jwt) ->> 'email'::text), ''::text)))))));
CREATE POLICY quote_reviews_supplier_reads_own ON public.quote_reviews AS PERMISSIVE FOR SELECT TO authenticated USING (((owner_email IS NOT NULL) AND (owner_email = lower(COALESCE((( SELECT auth.jwt() AS jwt) ->> 'email'::text), ''::text)))));
CREATE POLICY quote_spec_hold_service_role_only ON public.quote_spec_hold AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY reasoning_held_question_service_role_only ON public.reasoning_held_question AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY reasoning_knowledge_candidate_service_role_only ON public.reasoning_knowledge_candidate AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY refund_ceo_check_service_role_only ON public.refund_ceo_check AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY refund_ceo_review_service_role_only ON public.refund_ceo_review AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY refund_incident_service_role_only ON public.refund_incident AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY refund_ladder_evidence_service_role_only ON public.refund_ladder_evidence AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY rehearsal_spend_reservation_service_role_only ON public.rehearsal_spend_reservation AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY resilience_step_service_role_only ON public.resilience_step AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY review_hold_service_role_only ON public.review_hold AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY review_pool_service_role_only ON public.review_pool AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY review_route_service_role_only ON public.review_route AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY rfq_clarification_service_role_only ON public.rfq_clarification AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY os_owner_admin_read ON public.risk_register AS PERMISSIVE FOR SELECT TO authenticated USING ((fn_role_of((auth.jwt() ->> 'email'::text)) = ANY (ARRAY['owner'::text, 'admin'::text])));
CREATE POLICY routine_change_log_service_role_only ON public.routine_change_log AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY routine_judgement_service_role_only ON public.routine_judgement AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY sales_engineer_comparison_report_service_role_only ON public.sales_engineer_comparison_report AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY sales_engineer_framework_proposal_service_role_only ON public.sales_engineer_framework_proposal AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY sales_engineer_negotiation_round_service_role_only ON public.sales_engineer_negotiation_round AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY sales_engineer_onboarding_week_service_role_only ON public.sales_engineer_onboarding_week AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY sales_engineer_win_loss_month_service_role_only ON public.sales_engineer_win_loss_month AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY sanctions_ban_service_role_only ON public.sanctions_ban AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_case_memory_service_role_only ON public.seat_case_memory AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_case_memory_miss_service_role_only ON public.seat_case_memory_miss AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_deliberation_service_role_only ON public.seat_deliberation AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_deliberation_ceiling_service_role_only ON public.seat_deliberation_ceiling AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_deliberation_turn_service_role_only ON public.seat_deliberation_turn AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_duty_service_role_only ON public.seat_duty AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_duty_skip_service_role_only ON public.seat_duty_skip AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_exam_asked_service_role_only ON public.seat_exam_asked AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_exam_fix_service_role_only ON public.seat_exam_fix AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_exam_item_service_role_only ON public.seat_exam_item AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_handoff_kind_service_role_only ON public.seat_handoff_kind AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_judgement_service_role_only ON public.seat_judgement AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_knowledge_eval_question_service_role_only ON public.seat_knowledge_eval_question AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_knowledge_exam_service_role_only ON public.seat_knowledge_exam AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_knowledge_recall_service_role_only ON public.seat_knowledge_recall AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_knowledge_recall_answer_service_role_only ON public.seat_knowledge_recall_answer AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_knowledge_recall_floor_service_role_only ON public.seat_knowledge_recall_floor AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_knowledge_refresh_service_role_only ON public.seat_knowledge_refresh AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_knowledge_stale_service_role_only ON public.seat_knowledge_stale AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_learning_daily_service_role_only ON public.seat_learning_daily AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_lesson_cluster_service_role_only ON public.seat_lesson_cluster AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_playbook_service_role_only ON public.seat_playbook AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_self_review_service_role_only ON public.seat_self_review AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_senior_contribution_service_role_only ON public.seat_senior_contribution AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_senior_exam_service_role_only ON public.seat_senior_exam AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY seat_senior_verdict_service_role_only ON public.seat_senior_verdict AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY service_alias_proposal_service_role_only ON public.service_alias_proposal AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY service_implication_service_role_only ON public.service_implication AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY signup_purge_service_role_only ON public.signup_purge AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY signup_purge_dropbox_service_role_only ON public.signup_purge_dropbox AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY signup_purge_object_service_role_only ON public.signup_purge_object AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY site_uptime_check_service_role_only ON public.site_uptime_check AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY sms_messages_service_role_only ON public.sms_messages AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY social_connect_link_service_role_only ON public.social_connect_link AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY social_conversation_service_role_only ON public.social_conversation AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY social_message_service_role_only ON public.social_message AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY social_reply_library_service_role_only ON public.social_reply_library AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY spec_alternative_offer_service_role_only ON public.spec_alternative_offer AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY stalled_inquiry_rescue_service_role_only ON public.stalled_inquiry_rescue AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY stripe_dispute_service_role_only ON public.stripe_dispute AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY stripe_payout_service_role_only ON public.stripe_payout AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY stripe_setting_reading_service_role_only ON public.stripe_setting_reading AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supplier_availability_service_role_only ON public.supplier_availability AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supplier_beneficial_owner_service_role_only ON public.supplier_beneficial_owner AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supplier_campaign_daily_list_service_role_only ON public.supplier_campaign_daily_list AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supplier_capability_reading_service_role_only ON public.supplier_capability_reading AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supplier_collaboration_service_role_only ON public.supplier_collaboration AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supplier_collaboration_event_service_role_only ON public.supplier_collaboration_event AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supplier_document_cache_service_role_only ON public.supplier_document_cache AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supplier_due_checkouts_service_role_only ON public.supplier_due_checkouts AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supplier_due_payments_service_role_only ON public.supplier_due_payments AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supplier_onboarding_service_role_only ON public.supplier_onboarding AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supplier_own_word_reading_service_role_only ON public.supplier_own_word_reading AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supplier_performance_service_role_only ON public.supplier_performance AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supplier_public_name_service_role_only ON public.supplier_public_name AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supplier_quote_template_service_role_only ON public.supplier_quote_template AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supplier_recruitment_funnel_service_role_only ON public.supplier_recruitment_funnel AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supplier_reply_followup_service_role_only ON public.supplier_reply_followup AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supplier_response_watch_service_role_only ON public.supplier_response_watch AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supplier_scorecard_service_role_only ON public.supplier_scorecard AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supplier_service_question_service_role_only ON public.supplier_service_question AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supplier_strike_event_service_role_only ON public.supplier_strike_event AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supplier_voice_note_service_role_only ON public.supplier_voice_note AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supplier_whatsapp_consent_ask_service_role_only ON public.supplier_whatsapp_consent_ask AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supplier_whatsapp_optin_service_role_only ON public.supplier_whatsapp_optin AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supply_gap_service_role_only ON public.supply_gap AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY supply_recruitment_brief_service_role_only ON public.supply_recruitment_brief AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY support_case_promise_service_role_only ON public.support_case_promise AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY support_case_summary_version_service_role_only ON public.support_case_summary_version AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY support_category_service_role_only ON public.support_category AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY support_cause_week_service_role_only ON public.support_cause_week AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY support_customer_profile_service_role_only ON public.support_customer_profile AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY support_reply_readability_service_role_only ON public.support_reply_readability AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY support_root_cause_service_role_only ON public.support_root_cause AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY support_root_cause_fix_service_role_only ON public.support_root_cause_fix AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY support_signal_category_service_role_only ON public.support_signal_category AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY table_export_change_service_role_only ON public.table_export_change AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY table_export_change_tracked_service_role_only ON public.table_export_change_tracked AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY table_export_registry_service_role_only ON public.table_export_registry AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY table_export_run_service_role_only ON public.table_export_run AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY target_daily_verdict_service_role_only ON public.target_daily_verdict AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY target_label_service_role_only ON public.target_label AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY target_path_service_role_only ON public.target_path AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY taxonomy_trade_adjacent_service_role_only ON public.taxonomy_trade_adjacent AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY taxonomy_trade_code_service_role_only ON public.taxonomy_trade_code AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY taxonomy_trade_group_service_role_only ON public.taxonomy_trade_group AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY taxonomy_trade_proposal_service_role_only ON public.taxonomy_trade_proposal AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY taxonomy_trade_service_service_role_only ON public.taxonomy_trade_service AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY trade_customer_opening_service_role_only ON public.trade_customer_opening AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY trade_opening_rule_service_role_only ON public.trade_opening_rule AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY trade_spec_checklist_service_role_only ON public.trade_spec_checklist AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY os_owner_admin_read ON public.transactions AS PERMISSIVE FOR SELECT TO authenticated USING ((fn_role_of((auth.jwt() ->> 'email'::text)) = ANY (ARRAY['owner'::text, 'admin'::text])));
CREATE POLICY unsubscribe_refusal_service_role_only ON public.unsubscribe_refusal AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY os_owner_admin_read ON public.vision_horizon AS PERMISSIVE FOR SELECT TO authenticated USING ((fn_role_of((auth.jwt() ->> 'email'::text)) = ANY (ARRAY['owner'::text, 'admin'::text])));
CREATE POLICY wa_sender_quality_reading_service_role_only ON public.wa_sender_quality_reading AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY web_search_day_service_role_only ON public.web_search_day AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);
CREATE POLICY os_owner_admin_read ON public.workflow AS PERMISSIVE FOR SELECT TO authenticated USING ((fn_role_of((auth.jwt() ->> 'email'::text)) = ANY (ARRAY['owner'::text, 'admin'::text])));
CREATE POLICY writer_seat_service_role_only ON public.writer_seat AS PERMISSIVE FOR ALL TO public USING (false) WITH CHECK (false);

-- ===== CRON JOBS =====
select cron.schedule('inquiry_conversation_summary_daily','40 23 * * *',$CRON$select public.fn_inquiry_conversation_summary_run(50);$CRON$);
select cron.schedule('conversation_retention_daily','20 23 * * *',$CRON$select public.fn_conversation_retention_purge(500);$CRON$);
select cron.schedule('pdpl_erasure_daily','50 23 * * *',$CRON$select public.fn_pdpl_tick();$CRON$);
select cron.schedule('unfinished_signup_purge','*/5 * * * *',$CRON$select public.fn_unfinished_signup_purge(true)$CRON$);
select cron.schedule('lead_sourcing_batch','*/10 * * * *',$CRON$select public.fn_lead_sourcing_kick();$CRON$);
select cron.schedule('seat_duty:accountant.fraud_watch','1-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('accountant.fraud_watch');$CRON$);
select cron.schedule('seat_duty:ceo.improvement','1-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.improvement');$CRON$);
select cron.schedule('seat_duty:ceo.improvement_review','4-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.improvement_review');$CRON$);
select cron.schedule('seat_duty:ceo.report_answer','2-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.report_answer');$CRON$);
select cron.schedule('seat_duty:it_engineer.finding_chase','2-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('it_engineer.finding_chase');$CRON$);
select cron.schedule('seat_duty:it_engineer.game_day','1-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('it_engineer.game_day');$CRON$);
select cron.schedule('seat_duty:it_engineer.knowledge_recall','3-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('it_engineer.knowledge_recall');$CRON$);
select cron.schedule('cs_held_question_route','*/5 * * * *',$CRON$select public.fn_cs_held_question_route(); select public.fn_ceo_support_handover_duty();$CRON$);
select cron.schedule('seat_duty:ceo.queue_work','1-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.queue_work');$CRON$);
select cron.schedule('rehearsal_window_sweep','*/10 * * * *',$CRON$select public.fn_rehearsal_window_sweep();$CRON$);
select cron.schedule('seat_duty:customer_support.decision_objection_escalate','3-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('customer_support.decision_objection_escalate');$CRON$);
select cron.schedule('seat_duty:accountant.receipt_intake','3-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('accountant.receipt_intake');$CRON$);
select cron.schedule('seat_duty:accountant.charge_recovery','4-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('accountant.charge_recovery');$CRON$);
select cron.schedule('seat_duty:accountant.cash_forecast_weekly','3-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('accountant.cash_forecast_weekly');$CRON$);
select cron.schedule('seat_duty:accountant.budget_variance','1-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('accountant.budget_variance');$CRON$);
select cron.schedule('seat_duty:accountant.vat_threshold','2-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('accountant.vat_threshold');$CRON$);
select cron.schedule('seat_duty:accountant.finance_week','2-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('accountant.finance_week');$CRON$);
select cron.schedule('seat_duty:accountant.year_end','1-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('accountant.year_end');$CRON$);
select cron.schedule('seat_duty:ceo.directive_review','1-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.directive_review');$CRON$);
select cron.schedule('seat_duty:ceo.month_close','1-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.month_close');$CRON$);
select cron.schedule('seat_duty:ceo.forecast_counter_action','2-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.forecast_counter_action');$CRON$);
select cron.schedule('seat_duty:ceo.improvement_burn_down','3-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.improvement_burn_down');$CRON$);
select cron.schedule('seat_duty:ceo.pricing_evidence','2-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.pricing_evidence');$CRON$);
select cron.schedule('seat_duty:ceo.experiment_month','3-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.experiment_month');$CRON$);
select cron.schedule('seat_duty:ceo.refund_decision_metric','3-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.refund_decision_metric');$CRON$);
select cron.schedule('seat_duty:ceo.register_review','4-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.register_review');$CRON$);
select cron.schedule('seat_duty:it_engineer.latency_closure','4-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('it_engineer.latency_closure');$CRON$);
select cron.schedule('seat_duty:it_engineer.model_spend_closure','4-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('it_engineer.model_spend_closure');$CRON$);
select cron.schedule('seat_duty:it_engineer.perimeter_freshness','3-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('it_engineer.perimeter_freshness');$CRON$);
select cron.schedule('seat_duty:it_engineer.advisory_triage','3-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('it_engineer.advisory_triage');$CRON$);
select cron.schedule('seat_duty:it_engineer.load_test','1-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('it_engineer.load_test');$CRON$);
select cron.schedule('seat_duty:sales_engineer.comparison_report','0-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('sales_engineer.comparison_report');$CRON$);
select cron.schedule('seat_duty:sales_engineer.onboarding_conversion','0-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('sales_engineer.onboarding_conversion');$CRON$);
select cron.schedule('seat_duty:sales_engineer.supply_gap_recruitment','0-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('sales_engineer.supply_gap_recruitment');$CRON$);
select cron.schedule('seat_duty:sales_engineer.negotiation_round','0-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('sales_engineer.negotiation_round');$CRON$);
select cron.schedule('seat_duty:sales_engineer.win_loss_review','0-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('sales_engineer.win_loss_review');$CRON$);
select cron.schedule('seat_duty:sales_engineer.framework_proposal','0-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('sales_engineer.framework_proposal');$CRON$);
select cron.schedule('seat_duty:ceo.market_report','2-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.market_report');$CRON$);
select cron.schedule('seat_duty:sales_engineer.reveal_followup','0-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('sales_engineer.reveal_followup');$CRON$);
select cron.schedule('seat_duty:it_engineer.contact_dedup','4-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('it_engineer.contact_dedup');$CRON$);
select cron.schedule('seat_duty:ceo.five_number_report','4-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.five_number_report');$CRON$);
select cron.schedule('seat_duty:it_engineer.model_spend','3-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('it_engineer.model_spend');$CRON$);
select cron.schedule('seat_duty:customer_support.case_idle_close','3-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('customer_support.case_idle_close');$CRON$);
select cron.schedule('dropbox_backup_second_scheduler','41 */6 * * *',$CRON$select public.fn_backup_kick('pg_cron_second_scheduler', 'enqueue');$CRON$);
select cron.schedule('seat_duty:ceo.revision_refile','1-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.revision_refile');$CRON$);
select cron.schedule('seat_duty:it_engineer.latency_slo','2-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('it_engineer.latency_slo');$CRON$);
select cron.schedule('seat_duty:sales_engineer.demand_forecast','0-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('sales_engineer.demand_forecast');$CRON$);
select cron.schedule('seat_duty:customer_support.notice_plain_language','4-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('customer_support.notice_plain_language');$CRON$);
select cron.schedule('seat_duty:it_engineer.run_clusters','2-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('it_engineer.run_clusters');$CRON$);
select cron.schedule('seat_duty:ceo.senior_verdict','3-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.senior_verdict');$CRON$);
select cron.schedule('seat_duty:it_engineer.mystery_shopper_heartbeat','2-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('it_engineer.mystery_shopper_heartbeat');$CRON$);
select cron.schedule('reask_refused_turns','* * * * *',$CRON$select public.fn_reask_kick();$CRON$);
select cron.schedule('seat_duty:customer_support.knowledge_request_deadline','3-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('customer_support.knowledge_request_deadline');$CRON$);
select cron.schedule('seat_duty:customer_support.unanswered_inbound','2-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('customer_support.unanswered_inbound');$CRON$);
select cron.schedule('seat_duty:customer_support.data_requests','2-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('customer_support.data_requests');$CRON$);
select cron.schedule('seat_duty:customer_support.voice_of_customer','1-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('customer_support.voice_of_customer');$CRON$);
select cron.schedule('seat_duty:customer_support.delivery_outcome_return','2-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('customer_support.delivery_outcome_return');$CRON$);
select cron.schedule('seat_duty:marketing.whatsapp_supplier_invites','0-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('marketing.whatsapp_supplier_invites');$CRON$);
select cron.schedule('seat_duty:marketing.manual_outreach_targets','1-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('marketing.manual_outreach_targets');$CRON$);
select cron.schedule('seat_duty:customer_support.reply_quality_week','3-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('customer_support.reply_quality_week');$CRON$);
select cron.schedule('seat_duty:customer_support.public_complaints','1-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('customer_support.public_complaints');$CRON$);
select cron.schedule('seat_duty:customer_support.delivery_health','4-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('customer_support.delivery_health');$CRON$);
select cron.schedule('seat_duty:customer_support.complaint_deadlines','4-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('customer_support.complaint_deadlines');$CRON$);
select cron.schedule('seat_duty:customer_support.incident_notices','1-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('customer_support.incident_notices');$CRON$);
select cron.schedule('seat_duty:sales_engineer.supplier_outreach','0-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('sales_engineer.supplier_outreach');$CRON$);
select cron.schedule('seat_duty:sales_engineer.lead_email_check','0-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('sales_engineer.lead_email_check');$CRON$);
select cron.schedule('seat_duty:sales_engineer.invite_restart','0-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('sales_engineer.invite_restart');$CRON$);
select cron.schedule('seat_duty:sales_engineer.supplier_reply_followups','0-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('sales_engineer.supplier_reply_followups');$CRON$);
select cron.schedule('seat_duty:customer_support.dead_answer_rescue','1-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('customer_support.dead_answer_rescue');$CRON$);
select cron.schedule('seat_duty:ceo.supplier_growth','4-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.supplier_growth');$CRON$);
select cron.schedule('seat_duty:ceo.daily_number','2-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.daily_number');$CRON$);
select cron.schedule('seat_duty:sales_engineer.supplier_onboarding','0-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('sales_engineer.supplier_onboarding');$CRON$);
select cron.schedule('company_faq_embed','*/10 * * * *',$CRON$select public.fn_company_faq_embed_tick();$CRON$);
select cron.schedule('kb_embed','*/10 * * * *',$CRON$set statement_timeout = '120s'; select public.fn_kb_embed_scheduled_run();$CRON$);
select cron.schedule('seat_duty:marketing.geo_fix','4-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('marketing.geo_fix');$CRON$);
select cron.schedule('seat_duty:marketing.social_publish','2-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('marketing.social_publish');$CRON$);
select cron.schedule('seat_duty:marketing.social_inbox','4-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('marketing.social_inbox');$CRON$);
select cron.schedule('seat_duty:marketing.trend_decision','0-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('marketing.trend_decision');$CRON$);
select cron.schedule('seat_duty:marketing.kpi_scorecard','2-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('marketing.kpi_scorecard');$CRON$);
select cron.schedule('seat_duty:marketing.fact_register','3-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('marketing.fact_register');$CRON$);
select cron.schedule('seat_duty:marketing.paid_spend_report','3-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('marketing.paid_spend_report');$CRON$);
select cron.schedule('seat_duty:it_engineer.openrouter_unattributed','1-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('it_engineer.openrouter_unattributed');$CRON$);
select cron.schedule('seat_duty:it_engineer.postmortem','4-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('it_engineer.postmortem');$CRON$);
select cron.schedule('seat_duty:customer_support.status_chase_close','4-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('customer_support.status_chase_close');$CRON$);
select cron.schedule('seat_duty:customer_support.person_followup_email','2-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('customer_support.person_followup_email');$CRON$);
select cron.schedule('seat_duty:accountant.reveal_reconcile','4-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('accountant.reveal_reconcile');$CRON$);
select cron.schedule('cron_history_purge_hourly','37 * * * *',$CRON$select public.fn_cron_history_purge();$CRON$);
select cron.schedule('site_uptime_5min','2-59/5 * * * *',$CRON$set statement_timeout = '30s'; select public.fn_site_uptime_tick();$CRON$);
select cron.schedule('openrouter_low_balance_hourly','23 * * * *',$CRON$select public.fn_openrouter_low_balance_tick();$CRON$);
select cron.schedule('seat_duty:ceo.close_answered_handoffs','4-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.close_answered_handoffs');$CRON$);
select cron.schedule('seat_duty:ceo.org_task_handlers','4-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.org_task_handlers');$CRON$);
select cron.schedule('seat_duty:it_engineer.safe_fix','1-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('it_engineer.safe_fix');$CRON$);
select cron.schedule('sales_engineer_verification_rerun','* * * * *',$CRON$set statement_timeout = '50s'; select public.fn_sales_engineer_reruns_held_verifications();$CRON$);
select cron.schedule('sales_engineer_agreement_resign','* * * * *',$CRON$set statement_timeout = '50s'; select public.fn_sales_engineer_resigns_unsigned_agreements();$CRON$);
select cron.schedule('seat_duty:sales_engineer.request_outcomes','0-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('sales_engineer.request_outcomes');$CRON$);
select cron.schedule('seat_duty:sales_engineer.abandoned_intakes','0-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('sales_engineer.abandoned_intakes');$CRON$);
select cron.schedule('seat_duty:ceo.trade_opening','2-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.trade_opening');$CRON$);
select cron.schedule('seat_duty:ceo.trade_opening_tune','1-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.trade_opening_tune');$CRON$);
select cron.schedule('seat_duty:ceo.break_even','3-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.break_even');$CRON$);
select cron.schedule('seat_duty:ceo.month_plan_settle','3-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('ceo.month_plan_settle');$CRON$);
select cron.schedule('seat_duty:customer_support.promise_watch','0-59/5 * * * *',$CRON$set statement_timeout = '60s'; select public.fn_seat_duty_run('customer_support.promise_watch');$CRON$);
select cron.schedule('supplier_doc_reread_5min','4-59/5 * * * *',$CRON$set statement_timeout = '20s'; select public.fn_supplier_doc_reread_kick();$CRON$);
select cron.schedule('it_engineer_duties','3-59/5 * * * *',$CRON$set statement_timeout = '120s'; select public.fn_it_duties_stored_run();$CRON$);
select cron.schedule('outbox_person_mail_kick','* * * * *',$CRON$set statement_timeout = '20s'; select public.fn_outbox_person_mail_kick(); select public.fn_notice_without_a_route_sweep() where extract(minute from now()) = 17;$CRON$);
select cron.schedule('claude_routine_outcomes','47 * * * *',$CRON$set statement_timeout = '30s'; select public.fn_claude_routine_outcomes();$CRON$);

-- ===== APP_SECRETS KEY NAMES (values intentionally excluded) =====
--   accountant_weekly_report_local_dow
--   accountant_weekly_report_local_time
--   admin_emails
--   admin_mfa_phone
--   agent_autonomy_enabled
--   agent_autonomy_from
--   agent_failure_rate_limit
--   ai_health_fails
--   ai_spend_spike_multiple
--   anon_key
--   apify_token
--   backup_prune_mode
--   bd_daily_cap
--   bd_outreach_enabled
--   bd_source_mode
--   brand_avatar_url
--   brand_logo_on_navy_url
--   brand_logo_on_white_url
--   brand_mark_transparent_url
--   ceo_daily_number_golive
--   ceo_digest_local_time
--   ceo_growth_act_golive
--   ceo_weekly_report_local_dow
--   ceo_weekly_report_local_time
--   cloudconvert_api_key
--   company_trn
--   compliance_ref
--   containment_maintenance
--   content_secret
--   conversation_retention_mode
--   cos_frozen
--   cred_action_invoker
--   cred_cron_agents
--   cred_cron_backup
--   cred_cron_compliance
--   cred_cron_content
--   cred_cron_documents
--   cred_cron_finance
--   cred_cron_knowledge
--   cred_cron_marketing
--   cred_cron_marketplace
--   cred_cron_monitoring
--   cred_cron_notifications
--   cred_db_internal
--   cred_fn_accountant
--   cred_fn_action_worker
--   cred_fn_agent_act
--   cred_fn_agent_brain
--   cred_fn_agents
--   cred_fn_ai
--   cred_fn_alert_founder
--   cred_fn_analytics_recommend
--   cred_fn_archive_rfq
--   cred_fn_attach_photos
--   cred_fn_backup_kick
--   cred_fn_blog_weekly
--   cred_fn_boost_recommend
--   cred_fn_canon_eval
--   cred_fn_category_provision
--   cred_fn_category_reqs
--   cred_fn_ceo_agent
--   cred_fn_content_revise
--   cred_fn_copilot
--   cred_fn_cos_execute
--   cred_fn_customer_api
--   cred_fn_dept_learn
--   cred_fn_dept_plan
--   cred_fn_doc_render
--   cred_fn_dropbox_backup
--   cred_fn_dropbox_oauth
--   cred_fn_ea_meeting_summary
--   cred_fn_email_cron
--   cred_fn_email_triage
--   cred_fn_enrich_capability
--   cred_fn_exec_agents
--   cred_fn_finance_doc
--   cred_fn_founder_channel
--   cred_fn_gen_category_knowledge
--   cred_fn_gen_category_personas
--   cred_fn_inbound_email
--   cred_fn_inquiry_intake
--   cred_fn_intent_router
--   cred_fn_it_engineer
--   cred_fn_kb_autofill_gaps
--   cred_fn_kb_deepen
--   cred_fn_kb_research_test
--   cred_fn_knowledge_exam
--   cred_fn_kyc
--   cred_fn_learn_gaps
--   cred_fn_marketing
--   cred_fn_marketing_channels
--   cred_fn_marketing_draft
--   cred_fn_marketing_outreach
--   cred_fn_marketing_social_inbox
--   cred_fn_messages_api
--   cred_fn_os_api
--   cred_fn_os_pages
--   cred_fn_pdpl_request
--   cred_fn_project_consultant
--   cred_fn_prompt_gate
--   cred_fn_public_site
--   cred_fn_quote_extract
--   cred_fn_reasoned_delivery
--   cred_fn_reflect
--   cred_fn_reg_fetch
--   cred_fn_resend_inbound
--   cred_fn_resilience_ping
--   cred_fn_reveal_invoice
--   cred_fn_route_inquiry
--   cred_fn_sales_engineer
--   cred_fn_secretary_act
--   cred_fn_site_assistant
--   cred_fn_social_stage
--   cred_fn_supplier_api
--   cred_fn_supplier_portal
--   cred_fn_to_agent_brain
--   cred_fn_to_alert_founder
--   cred_fn_to_make_pdf
--   cred_fn_to_pdf_native
--   cred_fn_to_route_inquiry
--   cred_fn_wa_docs
--   cred_fn_wa_drawings
--   cred_fn_wa_inbound
--   cred_fn_wa_pdf
--   cred_fn_workflow_dispatch
--   cred_ops_doc_render
--   cred_ops_phone_diag
--   cred_ops_wa_replay
--   cred_ops_wa_template_setup
--   cred_site_error_ingest
--   cron_down_last_alert
--   customer_terms_label
--   customer_terms_version
--   daily_send_cap
--   default_post_image
--   deploy_secret
--   dispatch_force_key
--   document_expiry_ai
--   drawing_vision_count_enabled
--   dropbox_access_token
--   dropbox_app_key
--   dropbox_app_secret
--   dropbox_oauth_key
--   dropbox_refresh_token
--   dropbox_roots
--   email_asset_public_base
--   email_enabled
--   email_from_info
--   email_from_supplier
--   email_logo_url
--   email_open_ip_salt
--   email_reply_info
--   email_reply_supplier
--   email_reply_supplier_docs
--   email_signature_name
--   email_signature_name_ar
--   email_signature_title
--   email_triage_enabled
--   excluded_job_scopes
--   expense_forwarders
--   founder_email
--   founder_mobile
--   founder_name
--   founder_public_name
--   founder_public_phone
--   founding_free_limit
--   github_token
--   gmail_seed_refresh_token
--   google_oauth_client_id
--   google_oauth_client_secret
--   inbound_secret
--   inbound_webhook_secret
--   internal_credential_hmac_key
--   invite_body
--   invite_ceo_ceiling
--   invite_daily_cap
--   invite_enabled
--   invite_lane_enabled
--   invite_lane_from
--   invite_lane_since
--   invite_m365_enabled
--   invite_m365_mailbox
--   invite_max_bounce_rate
--   invite_open_tracking
--   invite_preheader
--   invite_reachable_only
--   invite_subject
--   invite_target_per_category
--   invite_target_per_trade
--   invite_warmup
--   job_eligibility_note
--   lead_reclassify_cost_estimate
--   lead_reclassify_daily_cap
--   lead_sourcing_daily_llm_usd
--   lead_sourcing_daily_quota
--   lead_sourcing_daily_serper_usd
--   lead_sourcing_usd_per_credit
--   marketing_golive
--   marketing_publishing_enabled
--   meta_access_token
--   meta_ad_account_id
--   meta_app_id
--   meta_app_secret
--   meta_autospend_golive
--   meta_daily_budget_cap_aed
--   meta_webhook_verify_token
--   min_job_value_aed
--   ml_embed_daily_cap
--   ml_embed_golive
--   ml_embed_read
--   openrouter_api_key
--   openrouter_min_usd
--   otp_hmac_key
--   postiz_api_key
--   postiz_integrations
--   postiz_publish_key
--   project_ref
--   public_site_url
--   publishable_key
--   qa_customer_email
--   qa_mint_enabled
--   rating_request_days_after_reveal
--   require_structured_quotes
--   resend_api_key
--   resend_domain_id
--   resend_inbound_signing_secret
--   resend_inbound_token
--   resend_webhook_key
--   resend_webhook_signing_secret
--   sanctions_screen_enabled
--   site_assistant_global_day
--   site_assistant_ip_hour
--   site_assistant_worker_turns
--   sla_quote_hours
--   social_model_enabled
--   social_posts_per_week
--   social_send_enabled
--   stripe_live_hold
--   stripe_publishable_key
--   stripe_publishable_key_test
--   stripe_secret_key
--   stripe_secret_key_test
--   stripe_setup_token
--   stripe_webhook_secret
--   stripe_webhook_secret_test
--   subscription_honour_12m
--   supplier_emails_enabled
--   supplier_exception_days
--   supplier_outreach_golive
--   supplier_subscription_aed
--   supplier_subscription_start
--   supplier_subscription_term
--   supplier_terms_carries_from
--   supplier_terms_html
--   supplier_terms_label
--   supplier_terms_version
--   terms_sha256_customer
--   terms_sha256_customer_version
--   terms_sha256_supplier
--   terms_sha256_supplier_version
--   terms_version
--   twilio_account_sid
--   twilio_api_key_secret
--   twilio_api_key_sid
--   twilio_auth_token
--   twilio_from
--   twilio_verify_service_sid
--   twilio_wa_from
--   unsubscribe_public_base
--   unsubscribe_signing_key
--   unsubscribe_signing_key_legacy
--   uptime_last_autoheal
--   vercel_project
--   vercel_project_id
--   vercel_team_id
--   vercel_token
--   virustotal_api_key
--   voice_capture_token
--   voice_otp_last
--   wa_autoreply_enabled
--   wa_daily_cap
--   wa_menu_content_sids
--   wa_per_recipient_24h
--   wa_stale_hours
--   wa_supplier_invite_golive
--   wa_template_sids
--   wa_templates_ready
--   youtube_channel_id
--   youtube_oauth
