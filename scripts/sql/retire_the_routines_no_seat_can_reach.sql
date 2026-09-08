-- RETIRE 149 ROUTINES NOTHING CAN REACH — the estate the two-seat company left behind.
--
-- The founder, 8 September 2026: "i dont want any old routines. delete them." The rule behind it is
-- the one that removed 137 edge functions the day before — what belongs to neither the CEO, the
-- customer-support agent nor the website does not exist — and this applies it to the database.
--
-- HOW THE SET WAS CHOSEN, because "old" is not a property of a name.
--
-- A reachability closure was computed over all 830 application routines (149 pgvector routines
-- excluded by pg_depend deptype='e'; they are not this company's code). The roots are the only ways
-- control enters this database from outside it:
--
--     a trigger function                         (a write to the table runs it)
--     a routine named by an ACTIVE cron job      (the scheduler runs it)
--     a routine in a view, default or check      (a read or a write runs it)
--     a routine called by a surviving edge function   (70 remain of 207)
--     a routine called by the Next.js app        (the website, which the founder kept)
--     a routine named by agent_tool.impl_target  (an agent tool dispatches it)
--
-- Then everything those call, transitively, to fixpoint: 372 roots closing over 612 routines.
-- 218 routines fall outside the closure. Nothing in this estate can invoke them.
--
-- MENTIONS WERE NOT COUNTED AS REFERENCES, and that distinction is the whole measurement. An earlier
-- pass called 799 of 830 "reached" because it counted any appearance of a name in any data column.
-- phase_c_component is a CATALOGUE that lists 291 routine names; agent_chats are transcripts;
-- kernel_retired_path is a record of things already retired; agent_knowledge is prose about the
-- estate. Being written down in a register is not being callable — if it were, every register would
-- immortalise whatever it documented.
--
-- WHAT IS DELIBERATELY NOT IN HERE. 68 of the 218 were built on 6-8 September for the two seats the
-- founder kept: fn_ceo_request_decision, fn_refund_execute_authorized, fn_support_receive_document,
-- fn_support_deliver_artifact, fn_document_classify and the rest of the v1.2 toolkit. They are
-- unreachable for the OPPOSITE reason to the old estate — not because their caller was deleted, but
-- because their caller has not been built yet. The founder's own words, 8 Sep: "in the prompt of
-- build up i gave you and the files and folders for the CEO today should remain", and "we dint
-- finish the testing of the customer support agent... once done we will start testing the CEO we
-- build today". They stay, and the gap they sit in is stated in the commit rather than hidden by
-- deleting the evidence.
--
-- Ages come from the git ADD date of each defining file, not its last-touch date. Last-touch dated
-- kernel_k11_component_exposure (17 Aug) as 8 September, because the sweep the night before rewrote
-- the MANIFEST and re-emitted the schema mirror across the whole directory.
--
-- THE PRE-CHECK IS pg_depend, NOT A TEXT SCAN. retire_orphaned_phase_governance_routines.sql records
-- why in its own header: a view used fn_phase_c_event_runtime_observation and a text scan of view
-- bodies missed it. Asked properly, pg_depend returned exactly one edge into the 150 candidates —
--
--     fn_enforce_rls_on_new_tables  <-  pg_event_trigger
--
-- an EVENT trigger, which is not in pg_trigger at all, so the closure's trigger roots could never
-- have seen it. It enforces row-level security on every new table. It is not in this file. The text
-- scan would have dropped it and RLS would have quietly stopped being applied to new tables.
--
-- Also checked and clear: 0 RLS policy expressions reference any of them, and 0 are discovered as a
-- board by fn_kernel_all_boards(), which finds boards BY SIGNATURE and therefore has no textual
-- caller anywhere.
--
-- REVERSIBILITY IS GIT. Every routine's canonical file stays in scripts/sql — 66 files define only
-- retired routines and 37 define a mix, and none is edited, because those files are the record of
-- what was built and when. scripts/sql/DROPPED.txt records the absence so the canonical engine reads
-- these as retired rather than as failed-to-deploy. No CASCADE anywhere; every drop names its exact
-- signature, so a drop that would take something with it fails instead of succeeding quietly.
--
-- RE-APPLY SEMANTICS. Applied once on 8 Sep 2026. apply_sql's reference guard refuses a file whose
-- DROP lines name routines that are no longer on production, so a standalone re-apply is refused by
-- design. In a manifest-order rebuild the defining files run first and this one then applies.
--   node scripts/apply_sql.mjs scripts/sql/retire_the_routines_no_seat_can_reach.sql --apply --ddl

begin;

-- PHASE MACHINERY (14)
drop function if exists public.fn_phase_b_change_request_append_only();
drop function if exists public.fn_phase_b_effective_errata();
drop function if exists public.fn_phase_b_gate_attachment();
drop function if exists public.fn_phase_c_baseline_drift();
drop function if exists public.fn_phase_c_component_classification_guard();
drop function if exists public.fn_phase_c_event_runtime_observation(p_event_id text);
drop function if exists public.fn_phase_c_founder_approval_immutable();
drop function if exists public.fn_phase_c_freeze_amendment_session_claim_is_verified();
drop function if exists public.fn_phase_c_historical_repair_append_only();
drop function if exists public.fn_phase_c_step_owner_valid(p_step_id text, p_owner text);
drop function if exists public.fn_phase_c_step_run_owner_admissible();
drop function if exists public.fn_phase_c_task_state_guard();
drop function if exists public.fn_phase_c_workflow_state_guard();
drop function if exists public.fn_phase_d_fixture_catalogue_checksum();

-- UNATTACHED TRIGGER FUNCTIONS (23)
drop function if exists public.trg_assistant_log_to_kernel();
drop function if exists public.trg_company_faq_sync();
drop function if exists public.trg_contact_message_to_kernel();
drop function if exists public.trg_customer_abandon_ban();
drop function if exists public.trg_customer_registered_kernel();
drop function if exists public.trg_document_to_kernel();
drop function if exists public.trg_expectation_ledger_append_only();
drop function if exists public.trg_expectation_work_item_real();
drop function if exists public.trg_holdout_expectations_immutable();
drop function if exists public.trg_holdout_record_immutable();
drop function if exists public.trg_inbound_message_to_kernel();
drop function if exists public.trg_inquiry_answer_value_domain();
drop function if exists public.trg_inquiry_received();
drop function if exists public.trg_kb_version();
drop function if exists public.trg_lead_dob_to_kernel();
drop function if exists public.trg_leads_lifecycle_stage();
drop function if exists public.trg_mep_pattern_norm();
drop function if exists public.trg_pdpl_request_to_kernel();
drop function if exists public.trg_quote_items_roll();
drop function if exists public.trg_scope_marker_norm();
drop function if exists public.trg_self_reg_category();
drop function if exists public.trg_supplier_capability();
drop function if exists public.trg_wa_message_to_kernel();

-- MARKETPLACE SURFACES WHOSE CALLERS WERE DELETED (23)
drop function if exists public.fn_edit_inquiry(p_inquiry uuid, p_customer uuid, p_patch jsonb);
drop function if exists public.fn_freeze_supplier_brief(p_inquiry_id uuid, p_reason text);
drop function if exists public.fn_inquiry_dispatch_eligible(p_inquiry_id uuid);
drop function if exists public.fn_notify_matched_supplier();
drop function if exists public.fn_quote_recompute_submittable();
drop function if exists public.fn_quote_score_json(p_quote jsonb, p_items jsonb);
drop function if exists public.fn_rfq_redispatch_sweep(p_limit integer);
drop function if exists public.fn_supplier_advisor(p_lead_id bigint);
drop function if exists public.fn_supplier_certifications(p_lead_id bigint);
drop function if exists public.fn_supplier_exception_close(p_lead_id bigint, p_outcome text);
drop function if exists public.fn_supplier_exception_open(p_lead_id bigint, p_reason text);
drop function if exists public.fn_supplier_negotiation(p_quote_id uuid);
drop function if exists public.fn_supplier_network_map();
drop function if exists public.fn_supplier_product_match(p_inquiry_id uuid, p_lead_id bigint);
drop function if exists public.fn_supplier_products(p_lead_id bigint, p_query text);
drop function if exists public.fn_supplier_tier(p_lead_id bigint);
drop function if exists public.fn_supplier_workspaces(p_lead_id bigint);
drop function if exists public.match_suppliers(query_embedding vector, match_count integer, p_emirate text, p_role text, p_product text, p_min_rating numeric);
drop function if exists public.notify_new_quote_sms();
drop function if exists public.qd_norm_supplier_ver();
drop function if exists public.quote_gate(p_category text, p_quote jsonb);
drop function if exists public.recent_duplicate_inquiry(p_customer uuid, p_summary text, p_window interval);
drop function if exists public.recompute_supplier_rating(p_supplier bigint);

-- THE ORGANISATION THAT WAS REMOVED ON 7 SEPTEMBER (14)
drop function if exists public.fn_board_review(p_subject text, p_subject_ref text);
drop function if exists public.fn_bump_exam_question(p_id bigint);
drop function if exists public.fn_exam_pick_agent();
drop function if exists public.fn_handoff_answer(p_id bigint, p_agent_key text, p_answer text);
drop function if exists public.fn_handoff_criteria(p jsonb);
drop function if exists public.fn_handoff_open(p jsonb);
drop function if exists public.fn_kernel_all_boards();
drop function if exists public.fn_kernel_workflow_run_parent_exists();
drop function if exists public.fn_org_exec_invite(p_cap integer);
drop function if exists public.fn_org_export();
drop function if exists public.fn_org_scorecard();
drop function if exists public.fn_org_task_execute_sweep(p_limit integer);
drop function if exists public.fn_workflow_actor_coverage();
drop function if exists public.fn_workflow_step_release(p_step_run_id bigint, p_reason text);

-- THE OLD AGENT AND KNOWLEDGE PLUMBING (20)
drop function if exists public.fn_agent_action_trace();
drop function if exists public.fn_agent_action_trace_ins();
drop function if exists public.fn_agent_context_capped(p_agent_key text, p_max_chars integer, p_query text);
drop function if exists public.fn_company_knowledge_search(p_question text, p_limit integer);
drop function if exists public.fn_context_slice(p_dept text, p_role_ids text[], p_category text, p_layer text, p_q tsquery, p_budget integer);
drop function if exists public.fn_kb_route(p_text text, p_limit integer);
drop function if exists public.fn_kb_route_decide(p_text text);
drop function if exists public.fn_ops_department_context(p_dept_key text, p_topic text, p_limit integer);
drop function if exists public.fn_os_knowledge_query(p_os_key text, p_topic text);
drop function if exists public.fn_prompt_draft(p_key text, p_content text, p_by text);
drop function if exists public.fn_prompt_get(p_key text);
drop function if exists public.fn_record_context_retrieval(p_agent_key text, p_task_class text, p_category text, p_ids text[], p_budget integer, p_chars integer);
drop function if exists public.kb_begin_run(p_package_id text, p_version text, p_sha text);
drop function if exists public.kb_dump_migrations(p_since text);
drop function if exists public.kb_finish_run(p_run_id uuid, p_status text, p_inserted bigint, p_updated bigint, p_rejected bigint, p_report jsonb);
drop function if exists public.kb_get_hashes(p_package_id text);
drop function if exists public.kb_norm(p text);
drop function if exists public.kb_query(p_query text, p_category text, p_limit integer);
drop function if exists public.kb_stage_upsert(p_target text, p_rows jsonb);
drop function if exists public.run_agent(p_job text);

-- EVERYTHING ELSE (55)
drop function if exists public.add_working_days(d date, n integer);
drop function if exists public.doc_rec(p_sig text, p_cond boolean, p_risk text, p_title text, p_reco text, p_assumptions jsonb, p_impact text, p_cost text);
drop function if exists public.fn_action_invoke_rpc(p_limit integer);
drop function if exists public.fn_archetype_tier(p_archetype text);
drop function if exists public.fn_artifact_publish_blocked(p_subject_type text, p_subject_id text, p_sha256 text);
drop function if exists public.fn_boq_fixture_score(p_fixture_id bigint, p_actual jsonb);
drop function if exists public.fn_category_checklist(p_category text, p_label text, p_text text);
drop function if exists public.fn_category_expert_ref(p_category text);
drop function if exists public.fn_category_questions(p_category text, p_lang text, p_limit integer);
drop function if exists public.fn_change_deployment_execute(p jsonb);
drop function if exists public.fn_cos_work_gate();
drop function if exists public.fn_data_metrics();
drop function if exists public.fn_dbx_category(p_lead_id bigint);
drop function if exists public.fn_dbx_safe(x text);
drop function if exists public.fn_decision_gate();
drop function if exists public.fn_decision_outcomes(p_kind text, p_days integer);
drop function if exists public.fn_dr_restore_clear(p_before timestamp with time zone, p_run_id uuid, p_limit integer);
drop function if exists public.fn_dues_to_escalate(p_days integer);
drop function if exists public.fn_edge_health_scan();
drop function if exists public.fn_email_sendable(p_email text);
drop function if exists public.fn_emit_budget_exceeded(p_dept text, p_amount numeric, p_requested_by text, p_purpose text);
drop function if exists public.fn_enable_dropbox_sync();
drop function if exists public.fn_enqueue_doc_backups();
drop function if exists public.fn_execution_run(p_limit integer);
drop function if exists public.fn_idea_rescore();
drop function if exists public.fn_intake_slug_for_catalog(p_catalog_slug text);
drop function if exists public.fn_invite_status_on_send();
drop function if exists public.fn_it_security_slice(p_dept text, p_q tsquery, p_budget integer);
drop function if exists public.fn_learning_loop_sweep(p_limit integer);
drop function if exists public.fn_marketing_library_search(p_query text, p_limit integer);
drop function if exists public.fn_model_autoswitch();
drop function if exists public.fn_opportunity_scan();
drop function if exists public.fn_os_paid_ai_allowed();
drop function if exists public.fn_os_provider_state_cached();
drop function if exists public.fn_pdpl_redact(p_request_id uuid);
drop function if exists public.fn_quality_metrics();
drop function if exists public.fn_remediation_step(p_id bigint, p_score numeric, p_cost_aed numeric);
drop function if exists public.fn_run_vt();
drop function if exists public.fn_schema_export();
drop function if exists public.fn_seal_decision_trace(p_id uuid);
drop function if exists public.fn_security_scan();
drop function if exists public.fn_task_tsquery(p_text text);
drop function if exists public.fn_unsafe_match_eligibility_guard();
drop function if exists public.fn_voice_metrics();
drop function if exists public.fn_write_decision_trace(p jsonb);
drop function if exists public.ops_begin_run(p_package text, p_version text, p_sha text);
drop function if exists public.ops_finish_run(p_run_id uuid, p_status text, p_ins bigint, p_upd bigint, p_skip bigint, p_rej bigint, p_detail jsonb);
drop function if exists public.ops_get_files(p_run_id uuid);
drop function if exists public.ops_rollback_run(p_run_id uuid);
drop function if exists public.ops_stage_upsert(p_target text, p_rows jsonb);
drop function if exists public.qd_on_due_paid();
drop function if exists public.qd_recompute_response();
drop function if exists public.rollback_ingestion_run(p_run_id uuid);
drop function if exists public.run_doc_reminders();
drop function if exists public.run_health_check();

commit;
