-- Phase C correction 8b and 1b — the remaining unclassified components, and the historical
-- evidence the corrections above cannot reach on their own.
--
-- 8b. phase_c_35 classified the 99 ACTIVE STATE-CHANGING components gate 4 names. The corrected
--     invariant then found 32 more: deployed edge-function components that change no state, still
--     carrying the placeholder. "Zero unclassified active components" does not have a mutates_state
--     clause in it, so these are in scope too. Same script, same evidence sources, wider selection.
--
-- 1b. "Repair the existing canary evidence without deleting history." Nothing below deletes a row.
--     Traces are WRITTEN for tasks that never had one, root traces are ADVANCED to the state their
--     command actually reached, and the three outbox rows carrying the wrong event are SUPERSEDED
--     with the reason recorded on the row — quarantined where they can be read, not erased.

with decided (component_id, classification, evidence, new_activation) as (values
  ('dbfn:canary_scan(haystack text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_agent_autonomy_blocked(p_agent_key text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_agent_tool_allowed(p_agent_key text, p_tool_id text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_archetype_tier(p_archetype text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_autonomy_check(p_kind text, p_target_table text, p_recommendation text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_blueprint_regressions(p_spec text, p_ref text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_budget_set_annual(p_budget bigint, p_account text, p_amount numeric)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_category_quote_ready(p_category text, p_spec jsonb, p_label text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_category_specialist_scorecard(p_days integer)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_check_licence_activity(p_subject_id text, p_content text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_check_licence_expiry(p_subject_id text, p_content text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_company_situation()', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_control_mode_identity_active(p_email text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_dept_can_plan(p_dept_key text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_doc_diff(p_type text, p_id text, p_va integer, p_vb integer)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_doc_history(p_type text, p_id text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_employee_kpi_trend(p_agent_key text, p_days integer)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_employee_scorecard(p_agent_key text, p_max_chars integer)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_experiment_results(p_key text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_external_authority(p_query text, p_max_chars integer)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_fa_run_depreciation(p_period date)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_flag(p_key text, p_ctx jsonb)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_gl_net_income()', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_handoff_stalled(p_dept text, p_limit integer)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_jsonb_text_array(j jsonb)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_kb_next_question(p_catalog_num integer, p_answered jsonb)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_lint_outbound(p_hours integer)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_management_decision_review(p_department text, p_days integer, p_limit integer)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_norm_roles(p_text text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_objective_cascade()', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_onboarding_gate(p_agent text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_org_exec_knowledge_fill(p_limit integer)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_os_portals_gates()', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_os_selftest()', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_overlay_for_category(p_category_key text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_pdpl_erase_plan(p_email text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_pdpl_export(p_email text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_phase_a_deferred_items()', 'ACTIVE_INTERNAL_CALLER', 'another deployed routine calls fn_phase_a_deferred_items', null),
  ('dbfn:fn_phase_b_baseline_drift()', 'ACTIVE_INTERNAL_CALLER', 'another deployed routine calls fn_phase_b_baseline_drift', null),
  ('dbfn:fn_phase_b_closure_blockers(p_workflow_id text, p_completed_steps text[], p_open_blockers bigint, p_open_handoffs bigint)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_phase_b_invariants()', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_phase_b_step_transition_allowed(p_from text, p_to text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_phase_b_transition_allowed(p_from text, p_to text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_phase1_status()', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_policy_lint_kb_chunks()', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_quote_category_score_text(p_category text, p_text text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_quote_coach_text(p_quote text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_quote_score_json(p_quote jsonb, p_items jsonb)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_rating_due(p_now timestamp with time zone)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_reliability_report(p_days integer)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_retrieval_leak_check(p_agent_key text, p_task_text text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_retrieval_probe(p_agent_key text, p_task_text text, p_category_key text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_role_isolation_status()', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_role_manager_chain(p_role text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_rules_eval(p_ctx jsonb)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_scenario_verdict(p_scenario_id text, p_actual text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_secops_test(sample text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_select_model(p_task_class text, p_dept_key text, p_confidence numeric)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_supplier_matchable(p_lead_id bigint)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_supplier_quality(p_lead_id bigint)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_terms_integrity()', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:fn_unsafe_guard_status()', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:gin_extract_query_trgm(text, internal, smallint, internal, internal, internal, internal)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:gin_extract_value_trgm(text, internal)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:gin_trgm_consistent(internal, smallint, text, integer, internal, internal, internal, internal)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:gin_trgm_triconsistent(internal, smallint, text, integer, internal, internal, internal)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:gtrgm_compress(internal)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:gtrgm_consistent(internal, text, smallint, oid, internal)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:gtrgm_decompress(internal)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:gtrgm_distance(internal, text, smallint, oid, internal)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:gtrgm_in(cstring)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:gtrgm_options(internal)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:gtrgm_out(gtrgm)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:gtrgm_penalty(internal, internal, internal)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:gtrgm_picksplit(internal, internal)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:gtrgm_same(gtrgm, gtrgm, internal)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:gtrgm_union(internal, internal)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:halfvec_accum(double precision[], halfvec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:halfvec_add(halfvec, halfvec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:halfvec_avg(double precision[])', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:halfvec_cmp(halfvec, halfvec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:halfvec_combine(double precision[], double precision[])', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:halfvec_concat(halfvec, halfvec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:halfvec_eq(halfvec, halfvec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:halfvec_ge(halfvec, halfvec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:halfvec_gt(halfvec, halfvec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:halfvec_l2_squared_distance(halfvec, halfvec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:halfvec_le(halfvec, halfvec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:halfvec_lt(halfvec, halfvec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:halfvec_mul(halfvec, halfvec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:halfvec_negative_inner_product(halfvec, halfvec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:halfvec_out(halfvec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:halfvec_recv(internal, oid, integer)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:halfvec_send(halfvec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:halfvec_spherical_distance(halfvec, halfvec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:halfvec_to_float4(halfvec, integer, boolean)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:halfvec_to_sparsevec(halfvec, integer, boolean)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:halfvec_to_vector(halfvec, integer, boolean)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:halfvec_typmod_in(cstring[])', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:hamming_distance(bit, bit)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:hnsw_bit_support(internal)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:hnsw_halfvec_support(internal)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:hnsw_sparsevec_support(internal)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:hnswhandler(internal)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:ivfflat_bit_support(internal)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:ivfflat_halfvec_support(internal)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:ivfflathandler(internal)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:jaccard_distance(bit, bit)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:mdm_normalize(p_kind text, p_raw text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:playbook_for(p_category text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:set_limit(real)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:show_limit()', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:show_trgm(text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:sparsevec_cmp(sparsevec, sparsevec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:sparsevec_eq(sparsevec, sparsevec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:sparsevec_ge(sparsevec, sparsevec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:sparsevec_gt(sparsevec, sparsevec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:sparsevec_l2_squared_distance(sparsevec, sparsevec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:sparsevec_le(sparsevec, sparsevec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:sparsevec_lt(sparsevec, sparsevec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:sparsevec_negative_inner_product(sparsevec, sparsevec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:sparsevec_out(sparsevec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:sparsevec_recv(internal, oid, integer)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:sparsevec_send(sparsevec)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:sparsevec_to_halfvec(sparsevec, integer, boolean)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:sparsevec_to_vector(sparsevec, integer, boolean)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:sparsevec_typmod_in(cstring[])', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:strict_word_similarity_commutator_op(text, text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:strict_word_similarity_dist_commutator_op(text, text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:strict_word_similarity_dist_op(text, text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:strict_word_similarity_op(text, text)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_accum(double precision[], vector)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_add(vector, vector)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_avg(double precision[])', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_cmp(vector, vector)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_concat(vector, vector)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_eq(vector, vector)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_ge(vector, vector)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_gt(vector, vector)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_in(cstring, oid, integer)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_l2_squared_distance(vector, vector)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_le(vector, vector)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_lt(vector, vector)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_mul(vector, vector)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_negative_inner_product(vector, vector)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_norm(vector)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_out(vector)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_recv(internal, oid, integer)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_send(vector)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_spherical_distance(vector, vector)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_sub(vector, vector)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_to_float4(vector, integer, boolean)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_to_halfvec(vector, integer, boolean)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_to_sparsevec(vector, integer, boolean)', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('dbfn:vector_typmod_in(cstring[])', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no trigger, no cron, no caller in any deployed routine or in the repo', 'inactive'),
  ('edge:about', 'ACTIVE_FRONTEND_ENTRY', 'src/ calls functions/v1/about', null),
  ('edge:asset_delete', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/asset_delete', null),
  ('edge:attach_photos', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no cron, no repo caller, not a webhook target', 'inactive'),
  ('edge:auth_api', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/auth_api', null),
  ('edge:brand_upload', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no cron, no repo caller, not a webhook target', 'inactive'),
  ('edge:dev_login', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/dev_login', null),
  ('edge:doc_render', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/doc_render', null),
  ('edge:export_all_knowledge', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/export_all_knowledge', null),
  ('edge:export_cat_knowledge', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/export_cat_knowledge', null),
  ('edge:export_leads_csv', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/export_leads_csv', null),
  ('edge:extract_text', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/extract_text', null),
  ('edge:faq', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/faq', null),
  ('edge:home', 'ACTIVE_FRONTEND_ENTRY', 'src/ calls functions/v1/home', null),
  ('edge:home-ar', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/home-ar', null),
  ('edge:i18n_get', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/i18n_get', null),
  ('edge:kb_research_test', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/kb_research_test', null),
  ('edge:kb_retrieve', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no cron, no repo caller, not a webhook target', 'inactive'),
  ('edge:legal', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/legal', null),
  ('edge:licence_reminder', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no cron, no repo caller, not a webhook target', 'inactive'),
  ('edge:marketing_image', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/marketing_image', null),
  ('edge:orchestrate', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no cron, no repo caller, not a webhook target', 'inactive'),
  ('edge:portal', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/portal', null),
  ('edge:qa_login', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/qa_login', null),
  ('edge:qa_mint', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/qa_mint', null),
  ('edge:quote_pdf', 'ACTIVE_FRONTEND_ENTRY', 'src/ calls functions/v1/quote_pdf', null),
  ('edge:quote_quality', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no cron, no repo caller, not a webhook target', 'inactive'),
  ('edge:quote_review', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/quote_review', null),
  ('edge:src_io', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/src_io', null),
  ('edge:support_ai', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no cron, no repo caller, not a webhook target', 'inactive'),
  ('edge:translate_html', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/translate_html', null),
  ('edge:vercel_status', 'ACTIVE_INTERNAL_CALLER', 'another edge function calls functions/v1/vercel_status', null),
  ('edge:voice_otp', 'DEFERRED_RUNTIME_IMPLEMENTATION', 'deployed, no cron, no repo caller, not a webhook target', 'inactive'))
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

-- ================================================================ the historical repair
do $repair$
declare r record; v_trace bigint; v_tasks int := 0; v_cmds int := 0; v_box int := 0;
begin
  -- (a) tasks created before the trigger existed. One trace each, parented to the command's root,
  --     and labelled for what it is: retro-fitted from the row, not invented evidence of work.
  for r in select t.*, c.trace_id root from public.phase_c_task t
             left join public.founder_command c on c.command_id = t.command_id
            where t.trace_id is null order by t.task_id loop
    v_trace := public.fn_phase_c_trace_write('TRACE-TASK', jsonb_build_object(
      'subject_kind','task', 'subject_ref', r.task_id::text, 'task_id', r.task_id,
      'command_id', r.command_id, 'run_id', r.run_id,
      'actor_role_id', r.accountable_role_id, 'manager_role_id', r.manager_role_id,
      'system_actor_id', case when r.command_id is not null then 'system.command_router'
                              else 'system.workflow_engine' end,
      'authority_result', coalesce(r.authority_class,''),
      'input_hash', encode(sha256(convert_to(coalesce(r.objective,''), 'UTF8')), 'hex'),
      'state_before','', 'state_after', r.state,
      'evidence_refs', jsonb_build_array(jsonb_build_object(
        'retrofitted', true, 'reason',
        'created before phase_c_30 made a task trace mandatory; reconstructed from the task row, '
        'which is the only record of it that exists',
        'created_at', r.created_at, 'closed_at', r.closed_at)),
      'status', case when r.closed_at is not null then 'sealed' else 'open' end));
    if r.root is not null then
      update public.phase_c_trace set parent_trace_id = r.root where trace_id = v_trace;
    end if;
    update public.phase_c_task set trace_id = v_trace where task_id = r.task_id;
    v_tasks := v_tasks + 1;
  end loop;

  -- (b) root traces left behind by their own command. Advanced, not rewritten: an unsealed trace is
  --     still live evidence, and a sealed one is superseded by fn_phase_c_trace_advance.
  for r in select c.command_id, c.state, c.trace_id from public.founder_command c
             join public.phase_c_trace t on t.trace_id = c.trace_id
            where t.state_after is distinct from c.state order by c.command_id loop
    perform public.fn_phase_c_trace_advance(r.trace_id, r.state,
      r.state in ('completed','failed','cancelled','refused','superseded'),
      jsonb_build_object('evidence_refs', jsonb_build_array(jsonb_build_object(
        'retrofitted', true,
        'reason','the command reached this state before phase_c_30 kept the root trace in step'))));
    v_cmds := v_cmds + 1;
  end loop;

  -- (c) the three outbox rows that announced EV-W01-STARTED for W20 commands. They are pending, so
  --     the new delivery worker WOULD pick them up and hand three marketing commands to the CEO.
  --     Superseded with the reason on the row. Not deleted: they are the evidence for the finding.
  update public.phase_c_event_outbox o
     set status = 'superseded',
         last_error = 'SUPERSEDED 2026-08-16: emitted as ' || o.event_id || ' / workflow '
                      || o.workflow_id || ' by the hard-coded literal in fn_founder_command_submit, '
                      || 'while command ' || (o.payload->>'command_id')
                      || ' had selected a different workflow. Retained as the evidence for that '
                      || 'finding; not delivered, because delivering it would hand the work to the '
                      || 'wrong consumer.',
         trace_id = coalesce(o.trace_id, (select c.trace_id from public.founder_command c
                                          where c.command_id = (o.payload->>'command_id')::bigint))
   where o.status in ('pending','retry_wait')
     and o.payload ? 'command_id'
     and not exists (select 1 from public.founder_command_workflow_link l
                     where l.command_id = (o.payload->>'command_id')::bigint
                       and l.workflow_id = o.workflow_id);
  get diagnostics v_box = row_count;

  -- any remaining outbox row with no trace at all gets the one its command or run already carries
  update public.phase_c_event_outbox o
     set trace_id = coalesce(
           (select c.trace_id from public.founder_command c
             where c.command_id = (o.payload->>'command_id')::bigint),
           (select r2.trace_id from public.phase_c_workflow_run r2
             where r2.run_id = (o.payload->>'run_id')::bigint))
   where o.trace_id is null;

  raise notice 'repair: % task trace(s), % command trace(s) advanced, % outbox row(s) superseded',
    v_tasks, v_cmds, v_box;
end $repair$;
