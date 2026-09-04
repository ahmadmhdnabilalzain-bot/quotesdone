-- PHASE E (7b): RETIRE THE NO-CALLER FUNCTIONS — measured on every axis, refused if any axis moves.
--
-- MASTER_PLAN §5.1 / §6: "Retire the 66 no-caller functions — but audit the ERP / A-B framework first."
-- Measured 4 Sep 2026 over the 168 phase_c_component rows classified DEFERRED_RUNTIME_IMPLEMENTATION:
-- 91 are pg_trgm / pgvector extension members (pg_depend deptype 'e' — extension-owned, never the
-- estate's to drop; left as they are), 77 are application routines. The audit and the wiring of the
-- families that are intended substrate is scripts/sql/phase_e_wire_the_ledger_collections_and_
-- experiments.sql (GL nightly sync, collections, the A/B concluder, one retention chore). Of the 77:
--
--   WIRED (6 + the GL family)  fn_collections, fn_experiment_assign/_record/_results, fn_agent_decision,
--                              fn_blueprint_result_prune — each now has a cron or a caller, an owner seat,
--                              a component row and a trace policy.
--   KEPT, entry point measured (13)  bound to an active org_action_executor: fn_ap_duplicate_scan,
--                              fn_brand_scan, fn_dispute_open (also a critical_capability probe),
--                              fn_org_exec_knowledge_fill, fn_supplier_autoapprove_clean,
--                              fn_supplier_capability_derive; called by an edge function: fn_quote_score_json
--                              (quote_compare/deterministic.ts), fn_select_model (_shared/llm.ts, also a
--                              critical_capability probe), fn_handoff_open (agent_brain); registered
--                              agent tools: fn_task_commercial_effect, fn_handoff_stalled; driven by the
--                              org connectivity CI checks: fn_handoff_close, fn_handoff_respond.
--   KEPT, no caller, with a reason (16)  fn_refund_amount_resolve (money path, refund family is
--                              DO-NOT-TOUCH); fn_pdpl_export / fn_pdpl_erase_plan (PDPL subject-access and
--                              erasure, legal obligation, operator-driven); fn_terms_integrity (T&C hash
--                              integrity, the only hard rules); fn_undo and fn_supersede_lesson (§5.2 #8/#9
--                              are FIX orders, not drops); fn_knowledge_rollback (the only reverse path for a
--                              knowledge ingestion run); fn_internal_credential_retire (the only audited
--                              credential-retirement door); fn_ai_gate and fn_company_situation (Row #3 OS
--                              blueprint components the scorer asserts); fn_supplier_matchable and
--                              fn_supplier_quality (spec-row canonical readers, Row #5); fn_split_inquiry
--                              (specialist-per-trade RFQ split, a product capability awaiting its customer_api
--                              action); fn_check_licence_activity / fn_check_licence_expiry (the Supply
--                              Verification agent's licence checks — the plan's #1 net-new agent);
--                              fn_role_manager_chain (the §4.5 approval-chain resolver).
--   DROPPED (42, below)  no caller on any axis, no business object behind them, or a duplicate
--                              of a live path. Reason per routine is in the component evidence.
--
-- MEASURED for each dropped routine, 4 Sep 2026, and RE-MEASURED at apply time by the block below
-- (six sibling agents write to this database now; a caller added in the window refuses the drop):
-- 0 callers in any public routine body (word-boundary regex over prosrc), 0 cron commands, 0 execution
-- wrappers, 0 triggers (pg_trigger.tgfoid), 0 view or other pg_depend dependents, 0 RLS policies,
-- 0 org_action_executor targets, 0 agent_tool targets, 0 critical_capability probes, not in
-- kernel_write_authority, not a board by fn_kernel_all_boards() signature, and 0 references from
-- supabase/functions, src, scripts (outside scripts/sql) or .github.
--
-- Reversibility is git (each routine's canonical file stays in scripts/sql); scripts/sql/DROPPED.txt
-- records every absence; the component / ledger edits are reversed by
-- scripts/sql/down/phase_e_retire_the_no_caller_functions_down.sql. No CASCADE; every drop names its
-- exact signature. RE-APPLY: a standalone re-apply after the drops is refused by apply_sql's reference
-- guard (names absent routines) by design; a manifest-order rebuild applies it.
--
--   node scripts/apply_sql.mjs scripts/sql/phase_e_retire_the_no_caller_functions.sql --apply --ddl

begin;

do $census$
declare v_live text;
begin
  with names(name) as (select unnest(array['fn_ap_pay', 'fn_po_bill', 'fn_po_create', 'fn_po_receive', 'fn_inv_adjust', 'fn_inv_issue', 'fn_inv_receive', 'fn_fa_acquire', 'fn_fa_dispose', 'fn_fa_run_depreciation', 'fn_budget_create', 'fn_budget_set_annual', 'fn_autonomy_check', 'fn_chief_of_staff', 'fn_control_mode_identity_active', 'fn_dept_can_plan', 'fn_doc_control', 'fn_doc_diff', 'fn_doc_history', 'fn_employee_kpi_trend', 'fn_employee_responsibilities_backfill', 'fn_employee_scorecard', 'fn_external_authority', 'fn_flag', 'fn_kb_submit_revision', 'fn_lint_outbound', 'fn_policy_lint_kb_chunks', 'fn_llm_cache_get', 'fn_llm_cache_put', 'fn_management_decision_review', 'fn_p2c1_rollback_stage_b6', 'fn_p2c1_rollback_stage_b7', 'fn_phase1_rollback_rehearse', 'fn_phase1_status', 'fn_prompt_publish', 'fn_quote_category_score_text', 'fn_quote_coach_text', 'fn_rules_eval', 'fn_scenario_verdict', 'fn_unsafe_liveness_probe', 'mdm_normalize', 'run_reveal_nudges']))
  select string_agg(distinct axis || ':' || name, ', ') into v_live from (
    select 'routine_caller' axis, n.name from names n join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname <> n.name and p.prosrc ~ ('\m' || n.name || '\M')
    union all select 'cron', n.name from names n join cron.job j on j.command ~ ('\m' || n.name || '\M')
    union all select 'wrapper', n.name from names n join public.phase_c_system_execution_wrapper w on w.original_command ~ ('\m' || n.name || '\M')
    union all select 'trigger', n.name from names n join pg_proc p on p.proname = n.name and p.pronamespace = 'public'::regnamespace join pg_trigger t on t.tgfoid = p.oid
    union all select 'pg_depend', n.name from names n join pg_proc p on p.proname = n.name and p.pronamespace = 'public'::regnamespace join pg_depend d on d.refobjid = p.oid and d.deptype not in ('i', 'e')
    union all select 'policy', n.name from names n join pg_policy pol on coalesce(pg_get_expr(pol.polqual, pol.polrelid), '') ~ ('\m' || n.name || '\M') or coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), '') ~ ('\m' || n.name || '\M')
    union all select 'executor', n.name from names n join public.org_action_executor x on x.target ~ ('\m' || n.name || '\M')
    union all select 'agent_tool', n.name from names n join public.agent_tool a on a.impl_target ~ ('\m' || n.name || '\M')
    union all select 'critical_capability', n.name from names n join public.critical_capability c on c.probe_sql ~ ('\m' || n.name || '\M')
    union all select 'write_authority', n.name from names n join public.kernel_write_authority a on a.routine_name = n.name
    union all select 'board', n.name from names n join (select distinct board from public.fn_kernel_all_boards()) b on b.board = n.name
  ) s;
  if v_live is not null then
    raise exception 'phase_e_retire_the_no_caller_functions: a routine gained a caller since the census — refusing to drop: %', v_live;
  end if;
end $census$;

drop function if exists public.fn_ap_pay(p_bill bigint, p_date date, p_amount numeric, p_from_account text, p_by text);
drop function if exists public.fn_po_bill(p_po bigint, p_bill_no text, p_bill_date date, p_due date, p_vat numeric, p_by text);
drop function if exists public.fn_po_create(p_vendor bigint, p_order_date date, p_expected date, p_memo text, p_lines jsonb, p_created_by text);
drop function if exists public.fn_po_receive(p_po bigint, p_recv jsonb, p_date date, p_by text);
drop function if exists public.fn_inv_adjust(p_item bigint, p_qty_delta numeric, p_unit_cost numeric, p_offset_account text, p_date date, p_memo text, p_by text);
drop function if exists public.fn_inv_issue(p_item bigint, p_qty numeric, p_date date, p_ref_type text, p_ref_id text, p_by text);
drop function if exists public.fn_inv_receive(p_item bigint, p_qty numeric, p_unit_cost numeric, p_date date, p_ref_type text, p_ref_id text, p_post_gl boolean, p_by text);
drop function if exists public.fn_fa_acquire(p_name text, p_category text, p_acquire_date date, p_cost numeric, p_salvage numeric, p_life_months integer, p_in_service date, p_fund_account text, p_post_gl boolean, p_by text);
drop function if exists public.fn_fa_dispose(p_asset bigint, p_date date, p_proceeds numeric, p_proceeds_account text, p_by text);
drop function if exists public.fn_fa_run_depreciation(p_period date);
drop function if exists public.fn_budget_create(p_name text, p_year integer, p_by text);
drop function if exists public.fn_budget_set_annual(p_budget bigint, p_account text, p_amount numeric);
drop function if exists public.fn_autonomy_check(p_kind text, p_target_table text, p_recommendation text);
drop function if exists public.fn_chief_of_staff();
drop function if exists public.fn_control_mode_identity_active(p_email text);
drop function if exists public.fn_dept_can_plan(p_dept_key text);
drop function if exists public.fn_doc_control();
drop function if exists public.fn_doc_diff(p_type text, p_id text, p_va integer, p_vb integer);
drop function if exists public.fn_doc_history(p_type text, p_id text);
drop function if exists public.fn_employee_kpi_trend(p_agent_key text, p_days integer);
drop function if exists public.fn_employee_responsibilities_backfill();
drop function if exists public.fn_employee_scorecard(p_agent_key text, p_max_chars integer);
drop function if exists public.fn_external_authority(p_query text, p_max_chars integer);
drop function if exists public.fn_flag(p_key text, p_ctx jsonb);
drop function if exists public.fn_kb_submit_revision(p_kind text, p_ref text, p_content text, p_author text);
drop function if exists public.fn_lint_outbound(p_hours integer);
drop function if exists public.fn_policy_lint_kb_chunks();
drop function if exists public.fn_llm_cache_get(p_key text);
drop function if exists public.fn_llm_cache_put(p_key text, p_fn text, p_task_class text, p_model text, p_response text, p_ttl_minutes integer);
drop function if exists public.fn_management_decision_review(p_department text, p_days integer, p_limit integer);
drop function if exists public.fn_p2c1_rollback_stage_b6(p_mode text, p_actor text);
drop function if exists public.fn_p2c1_rollback_stage_b7(p_mode text, p_actor text);
drop function if exists public.fn_phase1_rollback_rehearse(p_actor text);
drop function if exists public.fn_phase1_status();
drop function if exists public.fn_prompt_publish(p_key text, p_content text, p_owner text, p_rollout integer);
drop function if exists public.fn_quote_category_score_text(p_category text, p_text text);
drop function if exists public.fn_quote_coach_text(p_quote text);
drop function if exists public.fn_rules_eval(p_ctx jsonb);
drop function if exists public.fn_scenario_verdict(p_scenario_id text, p_actual text);
drop function if exists public.fn_unsafe_liveness_probe();
drop function if exists public.mdm_normalize(p_kind text, p_raw text);
drop function if exists public.run_reveal_nudges();

do $ctl$
declare v_left int;
begin
  select count(*) into v_left from pg_proc
   where pronamespace = 'public'::regnamespace and proname in ('fn_ap_pay', 'fn_po_bill', 'fn_po_create', 'fn_po_receive', 'fn_inv_adjust', 'fn_inv_issue', 'fn_inv_receive', 'fn_fa_acquire', 'fn_fa_dispose', 'fn_fa_run_depreciation', 'fn_budget_create', 'fn_budget_set_annual', 'fn_autonomy_check', 'fn_chief_of_staff', 'fn_control_mode_identity_active', 'fn_dept_can_plan', 'fn_doc_control', 'fn_doc_diff', 'fn_doc_history', 'fn_employee_kpi_trend', 'fn_employee_responsibilities_backfill', 'fn_employee_scorecard', 'fn_external_authority', 'fn_flag', 'fn_kb_submit_revision', 'fn_lint_outbound', 'fn_policy_lint_kb_chunks', 'fn_llm_cache_get', 'fn_llm_cache_put', 'fn_management_decision_review', 'fn_p2c1_rollback_stage_b6', 'fn_p2c1_rollback_stage_b7', 'fn_phase1_rollback_rehearse', 'fn_phase1_status', 'fn_prompt_publish', 'fn_quote_category_score_text', 'fn_quote_coach_text', 'fn_rules_eval', 'fn_scenario_verdict', 'fn_unsafe_liveness_probe', 'mdm_normalize', 'run_reveal_nudges');
  if v_left > 0 then raise exception 'phase_e_retire_the_no_caller_functions: % of 42 routines still present', v_left; end if;
end $ctl$;

-- component retirement in lockstep (the rows outlive the routine and carry the signature)
update public.phase_c_component c
   set activation_state = 'inactive', classification = 'INTENTIONALLY_RETIRED', external_entry = 'no',
       gap = 'routine dropped 4 Sep 2026; no object remains', repair_or_keep_action = 'retired',
       evidence = 'phase_e_retire_the_no_caller_functions.sql 2026-09-04: ' || o.why || '; measured 0 callers/cron/trigger/view/RLS/executor/tool/probe/repo refs before removal and re-measured at apply; function dropped'
  from (values
      ('dbfn:fn_ap_pay(p_bill bigint, p_date date, p_amount numeric, p_from_account text, p_by text)', 'AP sub-ledger; ap_bills 0 rows; expenses reach the company through the expenses mailbox and the invoice_approval workflow'),
      ('dbfn:fn_po_bill(p_po bigint, p_bill_no text, p_bill_date date, p_due date, p_vat numeric, p_by text)', 'PO sub-ledger; po_orders 0 rows; the company raises no purchase orders'),
      ('dbfn:fn_po_create(p_vendor bigint, p_order_date date, p_expected date, p_memo text, p_lines jsonb, p_created_by text)', 'PO sub-ledger; po_orders 0 rows'),
      ('dbfn:fn_po_receive(p_po bigint, p_recv jsonb, p_date date, p_by text)', 'PO sub-ledger; po_orders 0 rows'),
      ('dbfn:fn_inv_adjust(p_item bigint, p_qty_delta numeric, p_unit_cost numeric, p_offset_account text, p_date date, p_memo text, p_by text)', 'inventory sub-ledger; inv_items / inv_stock_moves 0 rows; a marketplace holds no stock'),
      ('dbfn:fn_inv_issue(p_item bigint, p_qty numeric, p_date date, p_ref_type text, p_ref_id text, p_by text)', 'inventory sub-ledger; 0 rows'),
      ('dbfn:fn_inv_receive(p_item bigint, p_qty numeric, p_unit_cost numeric, p_date date, p_ref_type text, p_ref_id text, p_post_gl boolean, p_by text)', 'inventory sub-ledger; 0 rows'),
      ('dbfn:fn_fa_acquire(p_name text, p_category text, p_acquire_date date, p_cost numeric, p_salvage numeric, p_life_months integer, p_in_service date, p_fund_account text, p_post_gl boolean, p_by text)', 'fixed-asset sub-ledger; fa_assets 0 rows'),
      ('dbfn:fn_fa_dispose(p_asset bigint, p_date date, p_proceeds numeric, p_proceeds_account text, p_by text)', 'fixed-asset sub-ledger; fa_assets 0 rows'),
      ('dbfn:fn_fa_run_depreciation(p_period date)', 'fixed-asset sub-ledger; fa_assets 0 rows (fn_fa_depreciate loses its only caller with it)'),
      ('dbfn:fn_budget_create(p_name text, p_year integer, p_by text)', 'fiscal-year GL budget; budgets 0 rows; the live budget mechanism is department_budget / fn_budget_available'),
      ('dbfn:fn_budget_set_annual(p_budget bigint, p_account text, p_amount numeric)', 'fiscal-year GL budget; budgets 0 rows (fn_budget_set loses its only caller with it)'),
      ('dbfn:fn_autonomy_check(p_kind text, p_target_table text, p_recommendation text)', 'V3-era autonomy classifier superseded by org_authority / fn_autonomy_control_guard'),
      ('dbfn:fn_chief_of_staff()', 'V3-era chief-of-staff routine superseded by the Founder Command Center and secretary_act'),
      ('dbfn:fn_control_mode_identity_active(p_email text)', 'reader over control_mode_identity nothing calls; the OS door is fn_os_open_access'),
      ('dbfn:fn_dept_can_plan(p_dept_key text)', 'planning-cap reader nothing calls; dept_plan carries its own cap'),
      ('dbfn:fn_doc_control()', 'licence-expiry reminder loop duplicating the running agents.security licence_expiring job'),
      ('dbfn:fn_doc_diff(p_type text, p_id text, p_va integer, p_vb integer)', 'reader over doc_versions with no surface'),
      ('dbfn:fn_doc_history(p_type text, p_id text)', 'reader over doc_versions with no surface'),
      ('dbfn:fn_employee_kpi_trend(p_agent_key text, p_days integer)', 'KPI reader with no consumer; fn_employee_kpi_measure is the live KPI path'),
      ('dbfn:fn_employee_responsibilities_backfill()', 'one-off backfill over org_agents (seating is owned elsewhere)'),
      ('dbfn:fn_employee_scorecard(p_agent_key text, p_max_chars integer)', 'prompt-context builder no context assembler calls'),
      ('dbfn:fn_external_authority(p_query text, p_max_chars integer)', 'prompt-context reader no context assembler calls'),
      ('dbfn:fn_flag(p_key text, p_ctx jsonb)', 'feature-flag evaluator; feature_flags 4 rows nothing reads through it'),
      ('dbfn:fn_kb_submit_revision(p_kind text, p_ref text, p_content text, p_author text)', 'kb_revisions writer nothing calls; the table (10,826 rows) is written by another path'),
      ('dbfn:fn_lint_outbound(p_hours integer)', 'policy lint reader with no consumer'),
      ('dbfn:fn_policy_lint_kb_chunks()', 'policy lint reader with no consumer'),
      ('dbfn:fn_llm_cache_get(p_key text)', 'LLM cache nothing reads; ai_gateway carries its own caching'),
      ('dbfn:fn_llm_cache_put(p_key text, p_fn text, p_task_class text, p_model text, p_response text, p_ttl_minutes integer)', 'LLM cache nothing writes'),
      ('dbfn:fn_management_decision_review(p_department text, p_days integer, p_limit integer)', 'decision_trace reader with no consumer (a test comment mentions it; nothing calls it)'),
      ('dbfn:fn_p2c1_rollback_stage_b6(p_mode text, p_actor text)', 'operator rollback for a finished stage; recovery is git'),
      ('dbfn:fn_p2c1_rollback_stage_b7(p_mode text, p_actor text)', 'operator rollback for a finished stage; recovery is git'),
      ('dbfn:fn_phase1_rollback_rehearse(p_actor text)', 'mutating rehearsal of the Phase 1 tier-0 rollback; nothing runs it'),
      ('dbfn:fn_phase1_status()', 'Phase 1 status reader with no surface'),
      ('dbfn:fn_prompt_publish(p_key text, p_content text, p_owner text, p_rollout integer)', 'prompt registry publisher; prompts 3 rows, published by SQL'),
      ('dbfn:fn_quote_category_score_text(p_category text, p_text text)', 'text-shaped quote scorer; fn_quote_score_json (called by quote_compare) and fn_quote_structured_score are the live scorers'),
      ('dbfn:fn_quote_coach_text(p_quote text)', 'text-shaped quote coach with no caller'),
      ('dbfn:fn_rules_eval(p_ctx jsonb)', 'business_rules evaluator (4 rows); the live rule substrate is ops_knowledge decision_rule'),
      ('dbfn:fn_scenario_verdict(p_scenario_id text, p_actual text)', 'Phase D scenario-verdict helper no builder or check calls'),
      ('dbfn:fn_unsafe_liveness_probe()', 'mutating probe (writes refunds, leads, org_authority …) nothing runs; an unrun mutating probe is a liability'),
      ('dbfn:mdm_normalize(p_kind text, p_raw text)', 'MDM normaliser nothing calls'),
      ('dbfn:run_reveal_nudges()', 'duplicate of qd_reveal_nudges (the reveal-nudges cron names the latter)')
    ) o(component_id, why)
 where c.component_id = o.component_id;

delete from public.phase_c_component_exposure_scope
 where component_id in ('dbfn:fn_ap_pay(p_bill bigint, p_date date, p_amount numeric, p_from_account text, p_by text)',
         'dbfn:fn_po_bill(p_po bigint, p_bill_no text, p_bill_date date, p_due date, p_vat numeric, p_by text)',
         'dbfn:fn_po_create(p_vendor bigint, p_order_date date, p_expected date, p_memo text, p_lines jsonb, p_created_by text)',
         'dbfn:fn_po_receive(p_po bigint, p_recv jsonb, p_date date, p_by text)',
         'dbfn:fn_inv_adjust(p_item bigint, p_qty_delta numeric, p_unit_cost numeric, p_offset_account text, p_date date, p_memo text, p_by text)',
         'dbfn:fn_inv_issue(p_item bigint, p_qty numeric, p_date date, p_ref_type text, p_ref_id text, p_by text)',
         'dbfn:fn_inv_receive(p_item bigint, p_qty numeric, p_unit_cost numeric, p_date date, p_ref_type text, p_ref_id text, p_post_gl boolean, p_by text)',
         'dbfn:fn_fa_acquire(p_name text, p_category text, p_acquire_date date, p_cost numeric, p_salvage numeric, p_life_months integer, p_in_service date, p_fund_account text, p_post_gl boolean, p_by text)',
         'dbfn:fn_fa_dispose(p_asset bigint, p_date date, p_proceeds numeric, p_proceeds_account text, p_by text)',
         'dbfn:fn_fa_run_depreciation(p_period date)',
         'dbfn:fn_budget_create(p_name text, p_year integer, p_by text)',
         'dbfn:fn_budget_set_annual(p_budget bigint, p_account text, p_amount numeric)',
         'dbfn:fn_autonomy_check(p_kind text, p_target_table text, p_recommendation text)',
         'dbfn:fn_chief_of_staff()',
         'dbfn:fn_control_mode_identity_active(p_email text)',
         'dbfn:fn_dept_can_plan(p_dept_key text)',
         'dbfn:fn_doc_control()',
         'dbfn:fn_doc_diff(p_type text, p_id text, p_va integer, p_vb integer)',
         'dbfn:fn_doc_history(p_type text, p_id text)',
         'dbfn:fn_employee_kpi_trend(p_agent_key text, p_days integer)',
         'dbfn:fn_employee_responsibilities_backfill()',
         'dbfn:fn_employee_scorecard(p_agent_key text, p_max_chars integer)',
         'dbfn:fn_external_authority(p_query text, p_max_chars integer)',
         'dbfn:fn_flag(p_key text, p_ctx jsonb)',
         'dbfn:fn_kb_submit_revision(p_kind text, p_ref text, p_content text, p_author text)',
         'dbfn:fn_lint_outbound(p_hours integer)',
         'dbfn:fn_policy_lint_kb_chunks()',
         'dbfn:fn_llm_cache_get(p_key text)',
         'dbfn:fn_llm_cache_put(p_key text, p_fn text, p_task_class text, p_model text, p_response text, p_ttl_minutes integer)',
         'dbfn:fn_management_decision_review(p_department text, p_days integer, p_limit integer)',
         'dbfn:fn_p2c1_rollback_stage_b6(p_mode text, p_actor text)',
         'dbfn:fn_p2c1_rollback_stage_b7(p_mode text, p_actor text)',
         'dbfn:fn_phase1_rollback_rehearse(p_actor text)',
         'dbfn:fn_phase1_status()',
         'dbfn:fn_prompt_publish(p_key text, p_content text, p_owner text, p_rollout integer)',
         'dbfn:fn_quote_category_score_text(p_category text, p_text text)',
         'dbfn:fn_quote_coach_text(p_quote text)',
         'dbfn:fn_rules_eval(p_ctx jsonb)',
         'dbfn:fn_scenario_verdict(p_scenario_id text, p_actual text)',
         'dbfn:fn_unsafe_liveness_probe()',
         'dbfn:mdm_normalize(p_kind text, p_raw text)',
         'dbfn:run_reveal_nudges()');

-- the ownership ledger follows the manifest: a row for a routine that no longer exists is a claim
-- the repository denies (application_source_of_truth line 6). The two frozen-baseline drift routines
-- dropped by phase_e_retire_the_frozen_baseline_boards.sql are included.
delete from public.kernel_routine_ownership
 where schema_name = 'public'
   and routine_name in ('fn_ap_pay', 'fn_po_bill', 'fn_po_create', 'fn_po_receive', 'fn_inv_adjust', 'fn_inv_issue', 'fn_inv_receive', 'fn_fa_acquire', 'fn_fa_dispose', 'fn_fa_run_depreciation', 'fn_budget_create', 'fn_budget_set_annual', 'fn_autonomy_check', 'fn_chief_of_staff', 'fn_control_mode_identity_active', 'fn_dept_can_plan', 'fn_doc_control', 'fn_doc_diff', 'fn_doc_history', 'fn_employee_kpi_trend', 'fn_employee_responsibilities_backfill', 'fn_employee_scorecard', 'fn_external_authority', 'fn_flag', 'fn_kb_submit_revision', 'fn_lint_outbound', 'fn_policy_lint_kb_chunks', 'fn_llm_cache_get', 'fn_llm_cache_put', 'fn_management_decision_review', 'fn_p2c1_rollback_stage_b6', 'fn_p2c1_rollback_stage_b7', 'fn_phase1_rollback_rehearse', 'fn_phase1_status', 'fn_prompt_publish', 'fn_quote_category_score_text', 'fn_quote_coach_text', 'fn_rules_eval', 'fn_scenario_verdict', 'fn_unsafe_liveness_probe', 'mdm_normalize', 'run_reveal_nudges', 'fn_phase_a_baseline_drift', 'fn_phase_b_baseline_drift')
   and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.proname = kernel_routine_ownership.routine_name);

do $proof$
declare v_comp int; v_led int;
begin
  select count(*) into v_comp from public.phase_c_component
   where component_id in ('dbfn:fn_ap_pay(p_bill bigint, p_date date, p_amount numeric, p_from_account text, p_by text)',
         'dbfn:fn_po_bill(p_po bigint, p_bill_no text, p_bill_date date, p_due date, p_vat numeric, p_by text)',
         'dbfn:fn_po_create(p_vendor bigint, p_order_date date, p_expected date, p_memo text, p_lines jsonb, p_created_by text)',
         'dbfn:fn_po_receive(p_po bigint, p_recv jsonb, p_date date, p_by text)',
         'dbfn:fn_inv_adjust(p_item bigint, p_qty_delta numeric, p_unit_cost numeric, p_offset_account text, p_date date, p_memo text, p_by text)',
         'dbfn:fn_inv_issue(p_item bigint, p_qty numeric, p_date date, p_ref_type text, p_ref_id text, p_by text)',
         'dbfn:fn_inv_receive(p_item bigint, p_qty numeric, p_unit_cost numeric, p_date date, p_ref_type text, p_ref_id text, p_post_gl boolean, p_by text)',
         'dbfn:fn_fa_acquire(p_name text, p_category text, p_acquire_date date, p_cost numeric, p_salvage numeric, p_life_months integer, p_in_service date, p_fund_account text, p_post_gl boolean, p_by text)',
         'dbfn:fn_fa_dispose(p_asset bigint, p_date date, p_proceeds numeric, p_proceeds_account text, p_by text)',
         'dbfn:fn_fa_run_depreciation(p_period date)',
         'dbfn:fn_budget_create(p_name text, p_year integer, p_by text)',
         'dbfn:fn_budget_set_annual(p_budget bigint, p_account text, p_amount numeric)',
         'dbfn:fn_autonomy_check(p_kind text, p_target_table text, p_recommendation text)',
         'dbfn:fn_chief_of_staff()',
         'dbfn:fn_control_mode_identity_active(p_email text)',
         'dbfn:fn_dept_can_plan(p_dept_key text)',
         'dbfn:fn_doc_control()',
         'dbfn:fn_doc_diff(p_type text, p_id text, p_va integer, p_vb integer)',
         'dbfn:fn_doc_history(p_type text, p_id text)',
         'dbfn:fn_employee_kpi_trend(p_agent_key text, p_days integer)',
         'dbfn:fn_employee_responsibilities_backfill()',
         'dbfn:fn_employee_scorecard(p_agent_key text, p_max_chars integer)',
         'dbfn:fn_external_authority(p_query text, p_max_chars integer)',
         'dbfn:fn_flag(p_key text, p_ctx jsonb)',
         'dbfn:fn_kb_submit_revision(p_kind text, p_ref text, p_content text, p_author text)',
         'dbfn:fn_lint_outbound(p_hours integer)',
         'dbfn:fn_policy_lint_kb_chunks()',
         'dbfn:fn_llm_cache_get(p_key text)',
         'dbfn:fn_llm_cache_put(p_key text, p_fn text, p_task_class text, p_model text, p_response text, p_ttl_minutes integer)',
         'dbfn:fn_management_decision_review(p_department text, p_days integer, p_limit integer)',
         'dbfn:fn_p2c1_rollback_stage_b6(p_mode text, p_actor text)',
         'dbfn:fn_p2c1_rollback_stage_b7(p_mode text, p_actor text)',
         'dbfn:fn_phase1_rollback_rehearse(p_actor text)',
         'dbfn:fn_phase1_status()',
         'dbfn:fn_prompt_publish(p_key text, p_content text, p_owner text, p_rollout integer)',
         'dbfn:fn_quote_category_score_text(p_category text, p_text text)',
         'dbfn:fn_quote_coach_text(p_quote text)',
         'dbfn:fn_rules_eval(p_ctx jsonb)',
         'dbfn:fn_scenario_verdict(p_scenario_id text, p_actual text)',
         'dbfn:fn_unsafe_liveness_probe()',
         'dbfn:mdm_normalize(p_kind text, p_raw text)',
         'dbfn:run_reveal_nudges()') and not (activation_state = 'inactive' and classification = 'INTENTIONALLY_RETIRED');
  if v_comp > 0 then raise exception '% component row(s) not retired', v_comp; end if;
  select count(*) into v_led from public.kernel_routine_ownership where routine_name in ('fn_ap_pay', 'fn_po_bill', 'fn_po_create', 'fn_po_receive', 'fn_inv_adjust', 'fn_inv_issue', 'fn_inv_receive', 'fn_fa_acquire', 'fn_fa_dispose', 'fn_fa_run_depreciation', 'fn_budget_create', 'fn_budget_set_annual', 'fn_autonomy_check', 'fn_chief_of_staff', 'fn_control_mode_identity_active', 'fn_dept_can_plan', 'fn_doc_control', 'fn_doc_diff', 'fn_doc_history', 'fn_employee_kpi_trend', 'fn_employee_responsibilities_backfill', 'fn_employee_scorecard', 'fn_external_authority', 'fn_flag', 'fn_kb_submit_revision', 'fn_lint_outbound', 'fn_policy_lint_kb_chunks', 'fn_llm_cache_get', 'fn_llm_cache_put', 'fn_management_decision_review', 'fn_p2c1_rollback_stage_b6', 'fn_p2c1_rollback_stage_b7', 'fn_phase1_rollback_rehearse', 'fn_phase1_status', 'fn_prompt_publish', 'fn_quote_category_score_text', 'fn_quote_coach_text', 'fn_rules_eval', 'fn_scenario_verdict', 'fn_unsafe_liveness_probe', 'mdm_normalize', 'run_reveal_nudges', 'fn_phase_a_baseline_drift', 'fn_phase_b_baseline_drift');
  if v_led > 0 then raise exception '% ledger row(s) still name a dropped routine', v_led; end if;
  raise notice 'proof: 42 routines dropped, 42 component rows retired, ledger rows removed';
end $proof$;

commit;
