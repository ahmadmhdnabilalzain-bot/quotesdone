> **Archived 16 Nov 2026** (simplification wave B, it_engineer): a census of which decisions were code and which went to a model, taken before the 7-8 Sep 2026 deletions. 201 of the 320 routines it names are gone from production (SELECT pg_proc, 16 Nov 2026). History, not the build today.

# Determinations census — what reasons deterministically, what still routes to a model

**Measured 5 Sep 2026 (18:36–19:10 UTC) on the one project `htdblwldjkcgjvmqkbeh`.** MASTER_PLAN §5.3 says
"~200 deterministic functions must encode the reasoning that today wrongly routes to the model"; that
number was never measured against the estate. This is the measurement. Every count below comes from a
query that ran; the boundary of each query is stated beside it.

## 1. The executor estate (org_action_executor)

| measure | value | how measured |
|---|---|---|
| executor rows | 89 (88 active; `growth_simulate` inactive) | `select * from org_action_executor` |
| kind `rpc` (pure SQL) | 46 rows, 45 active | same |
| kind `edge` | 43 rows, all active | same |
| edge targets that import `_shared/llm.ts` or POST `/functions/v1/ai_gateway` | **22 of 43** | grep of `supabase/functions/<target>/index.ts` for `_shared/llm`, `ai_gateway`, `openrouter`; every hit read (the profile_ai / inquiry_ai / route_inquiry hits are real fetches, not comments) |
| edge targets with no model path | 21 of 43 | same grep, zero hits |
| `fn_task_class` rows (the kernel's own "needs the model" list) | 22, the same 22 targets | `fn_executor_needs_model` reads it |

The 22 model-backed executors, with the doctrine's verdict for each (MUST = the doctrine reserves it
to a model: reading ONLINE ad data, GENERATING content, confirming an external fact; SHOULD = the
doctrine says deterministic code):

| action_class | edge target | task_class | workflow steps | steps hit since 1 Sep (model held) | doctrine |
|---|---|---|---|---|---|
| recommend | analytics_recommend | procurement_reasoning | 40 | **138** (109 advisory + 14 held + 3 cancelled + 12 failed) | SHOULD — **substituted 5 Sep: `fn_recommend_deterministic`** |
| exec_review | exec_agents | agent_reasoning | 3 | **9** | SHOULD — **substituted: `fn_exec_review_deterministic`** |
| knowledge_fill_gap | kb_fill_gap | knowledge_research | 2 | **5** | SHOULD for both steps (date comparison, coverage counts) — **substituted: `fn_knowledge_gap_deterministic`**; MUST only for writing text into a category with 0 chunks (0 such categories today) |
| knowledge_acquire | kb_deepen | knowledge_research | 10 | 3 (+2 failed, +2 ready) | MUST — "acquire from a cited external source" is the external-edge case |
| coordinate | cos_execute | agent_reasoning | 46 | 116 advisory + 418 skipped + 53 ready | SHOULD — the sibling's §4.2 applier owns it |
| capability_exam | knowledge_exam | json_extraction | 2 | 31 done (closes without the model: the sweep queues it, the function has a non-model path) | SHOULD |
| qualify_inquiry | inquiry_ai | procurement_reasoning | 3 | 0 | SHOULD (keyword fallback), MUST for document extraction |
| route_category | route_inquiry | rfq_routing | 1 | 0 | SHOULD — keyword lexicon path exists inside the function |
| compare_quotes | quote_compare | quote_comparison | 1 | 0 | SHOULD — best-3-vs-rest is a sort |
| capability_enrich | enrich_capability | json_extraction | 0 (cron 52-row rehearsal) | 0 | MUST (extraction from supplier text) |
| content_draft | marketing_draft | content_drafting | 3 | 0 | MUST (generates content) |
| content_revise | content_revise | content_drafting | 0 | 0 | MUST |
| seo_produce | seo_gen | content_drafting | 0 | 0 | MUST |
| video.produce | video_produce | — (gateway) | 0 | 0 | MUST |
| artifact.review | artifact_review | — (gateway) | 1 | 0 | SHOULD (review against brand rules is a checklist) |
| boost_recommend | boost_recommend | procurement_reasoning | 0 | 0 | MUST only for reading live Meta insights; SHOULD for the arithmetic |
| agent_action_work | action_worker | agent_reasoning | 0 | 0 | SHOULD |
| agent.train | agent_train | — (gateway) | 1 | 0 | MUST (rewrites a prompt) |
| role_define | agent_autogen | content_drafting | 1 | 0 | MUST (writes a persona) |
| invoice_review | finance_doc | json_extraction | 0 | 0 | MUST (extraction from a PDF) |
| legal_review | legal_review | contract_analysis | 5 | 0 | MUST for the judgement call; SHOULD for the pre-screen |
| outreach_draft | profile_ai | json_extraction | 1 | 0 | MUST (extraction) |

"Steps hit" = `workflow_step_run` rows since 2026-09-01 by action_class; a step closed advisory with
`stranded_reason = 'executor runs on the held paid model; not queued'` or `left status=held/cancelled`
was documented, not worked (memory: the-deterministic-close-documents-rather-than-performs).

## 2. The seven categories — routines that exist, and their live callers

Method: every `public` function (1,653 incl. overloads; 1,040 named `fn_*`) was joined against
(a) `phase_c_system_execution_wrapper.original_command` + `cron.job` for an active cron that names it,
(b) `pg_trigger` for a trigger that fires it, (c) `org_action_executor` for an active rpc executor whose
target it is, and (d) one hop: any routine whose body names it and is itself live by (a)–(c). A routine
with none of the four is "no live caller found by this method" — a second hop, PostgREST `.rpc()` calls
from edge functions and portals, and dynamic `execute format()` calls are NOT covered, so that column
under-reports. Category membership is by name pattern (the regexes are in the appendix's generator);
737 `fn_*` routines matched no pattern and are not in the tables. Counts are of routines, not of
distinct reasoning functions; overloads count once per signature.

| category (§5.3) | fn_* routines by name | with a live caller found | body reaches HTTP / ai_gateway | what still routes to a model |
|---|---|---|---|---|
| Match & routing determinations | 42 | 16 | 3 | route_category → route_inquiry (model with lexicon fallback); qualify_inquiry → inquiry_ai; match_inquiry → `match` edge is model-free |
| Quote-quality & completeness scoring | 13 | 6 | 0 | compare_quotes → quote_compare (model for the narrative; the ranking is SQL-able) |
| Playbook / rule appliers | 5 | 1 (`fn_apply_playbook` via workflow_dispatch) | 0 | coordinate → cos_execute when the hold lifts |
| Finance determinations | 81 | 47 | 1 | invoice_review → finance_doc (PDF extraction, MUST); forecast → cost_snapshot is model-free |
| Compliance & trust determinations | 29 | 19 | 0 | legal_review → legal_review (judgement call, MUST; pre-screen SHOULD) |
| KPI / self-review / evolution | 57 | 35 | 1 | **recommend → analytics_recommend (substituted 5 Sep)**; agent.train, role_define (MUST) |
| Approval-tier resolvers | 76 | 36 | 1 | **exec_review → exec_agents (substituted 5 Sep)** |
| **total classified** | **303** | **160** | **6** | |

So the estate already holds 303 name-classifiable deterministic routines across the seven categories,
160 of them provably on a live path by this method — the plan's "~200 new" was a guess made without
this table. What routes to a model is not 200 functions; it is 22 edge executors, of which 3 carried
152 of the 155 model-parked workflow steps since 1 Sep, and those 3 are now SQL.

The per-routine tables (routine, language, live caller, http) are in the appendix.

## 3. The substitutes (built, applied, proven 5 Sep 2026)

All three are `kind = 'rpc'` executors run by `fn_action_invoke_rpc` (cron 266) after
`fn_workflow_step_sweep` (cron 247) queues the step; `fn_workflow_step_claim` (cron 255 →
workflow_dispatch) now recognises an rpc owner (`scripts/sql/fn_workflow_step_claim_owns_rpc_executors.sql`)
instead of racing the sweep for the step. Each has a zero-argument form for the invoker and a
`p_step_run_id` form for a direct call; each returns distinct shapes for a determination, for no data,
and for no scope. None calls a model: `llm_attempt` and `ai_cost_log` gained 0 rows between 18:50 and
19:10 UTC while the proofs ran.

### fn_recommend_deterministic (action_class `recommend`)
Inputs: `employee_kpi` (actual/target as measured 03:30 UTC daily), `employee_kpi_history` (previous
point, 14-day miss count), `v_bi_scorecard` + `metric_snapshot` (company metrics, owner_dept mapped
through `org_departments.merged_into`), `meta_insights` (growth scope only). Framing follows the step's
words: variance / root cause / revise-or-retire / options / grade / baseline / define.

Three inputs, three outputs (direct calls, `p_record = false`):

| step_run | workflow / step | employee → department | framing | inputs read | top determination |
|---|---|---|---|---|---|
| 18066 | metric_lifecycle #1 "Define the metric and why it matters" | intel_director → data_intel | define | 14 KPIs (14 measured, 10 missed, 4 met), 0 scorecard | MISSED: categories differing from the spec at 2 against target 0 (0.0%), owner intel_director |
| 18043 | change_deployment #1 "Change proposed … baseline captured" | optimisation_eng → growth | baseline | 18 KPIs (13 measured, 12 missed, 1 met), 1 scorecard (1 off target), 2 ad-insight rows | baseline captured: Inquiries attributed to marketing channels = 0 (per_month), target 60 |
| 18080 | strategic_review #2 "Generate options with cost and risk" | cpo → exec | options | 10 KPIs (9 measured, 3 missed, 6 met), 2 scorecard (2 off target) | option: close the gap on Categories with real liquidity (actual 0, target 10, gap 10); risk high |
| 18069 | metric_lifecycle #4 "Detect variance against target" | cpo → exec | variance | same exec numbers | variance: Categories with real liquidity at 0 against target 10 (0.0%); Calls a cheaper model could have served worsened by 3.82 |

### fn_exec_review_deterministic (action_class `exec_review`)
Inputs: the run's prior `workflow_step_run` outputs (evidence), `org_role.authority_level` of the
officer, `fn_dept_authority(dept, 'exec_review')`, `fn_should_escalate` over `decision_policy`, the
step gate. Shapes: approved_within_authority / escalate (reasons + addressee) / nothing_to_review /
no_scope.

| step_run | workflow / step | officer | result |
|---|---|---|---|
| 18082 | strategic_review #4 "Decide and record rationale" | ceo (execute_high) | approved_within_authority: 3 prior done, 2 with deliverables, escalate=false, gate authority, officer tier covers department tier advisory |
| 1884 | improvement_lifecycle #4 "Approve within authority or escalate" (Aug run) | cpo (execute_medium) | nothing_to_review: 3 prior steps done, none carries a deliverable or outcome |
| loop run 6c59df8e #4 | strategic_review #4 | ceo | approved_within_authority (closed by the real invoker, see §4) |

### fn_knowledge_gap_deterministic (action_class `knowledge_fill_gap`)
Inputs: `ops_knowledge.review_after` / `source_freshness` (decay step: ACTS by marking
`review_required`, count stated); `kb_chunks` per active `category_agents` row (coverage step). Shapes:
decayed / coverage_gaps / coverage_ok / no_scope.

| step_run | step | result |
|---|---|---|
| 14633 | knowledge_lifecycle #6 "Decay confidence past the review date" | decayed 0 of 0 rows past review (5,164 without a review date; next review due 2027-01-31) — 0 rows written, honestly |
| 14635 | knowledge_lifecycle #8 "Category module coverage" | coverage_gaps: 75 of 88 active categories stale (every chunk undated), 0 missing, 0 thin (below 15 chunks), 13 ok |
| (null, nothing queued) | direct call | coverage_gaps company-wide with `located_by = 'nothing queued'` |

Finding from the coverage run: 75 of 88 roster categories carry only undated chunks (15 each), so
"stale" is the correct verdict for them until `effective_date` is populated.

## 4. Through the real loop

Two fixture runs (context `fixture:true`, `ZZ DEMO` title, inside `rehearsal_window`
`qd_run:det53_loop_202609051904`) were started with `fn_workflow_start` and driven only by
`fn_kernel_cron_exec(255)` (workflow_dispatch), `(247)` (step sweep), `(266)` (rpc invoker), `(230)`
(edge dispatcher) and `(231)` (edge collector), four iterations, 19:04–19:06 UTC. Both runs reached
`done`.

| run | step | action_class | closed by | determination |
|---|---|---|---|---|
| metric_lifecycle 9d0911f8 | 1 | recommend | executor:fn_recommend_deterministic | recommendation (data_intel, 14/14 measured) |
| | 2 | health_report | executor:ai_health | — |
| | 3 | forecast | workflow_dispatch (cost_snapshot notifies a human; dispatcher's row) | determined |
| | **4** | **recommend** | **executor:fn_recommend_deterministic** | **variance: exec, 9/10 measured, 3 missed, 2/2 scorecard off target** |
| | 5 | recommend | executor:fn_recommend_deterministic | root cause: "the WORK …" |
| | 6 | recommend | executor:fn_recommend_deterministic | revise-or-retire: "KEEP …" |
| | 7 | bi_snapshot | executor:fn_bi_snapshot | — |
| strategic_review 6c59df8e | 1 | health_report | executor:ai_health | — |
| | 2 | recommend | executor:fn_recommend_deterministic | options (exec) |
| | 3 | coordinate | workflow_dispatch | advisory_held_model (sibling's applier) |
| | **4** | **exec_review** | **executor:fn_exec_review_deterministic** | **approved_within_authority by ceo** |
| | 5 | coordinate | workflow_dispatch | advisory_held_model |
| | 6 | recommend | executor:fn_recommend_deterministic | baseline (exec) |

`action_execution` holds 10 rows for the two runs, every one `status = succeeded`,
`response.invoker = succeeded`; the 7 substitute rows carry `kind = rpc` and the determination in
`response.result[0]`. `used_llm = false` on every closed step comes from the sweep's settle path and is
corroborated by the empty provider ledgers above, not by the flag alone.

Note on the packet's wording: strategic_review **step 3** is `coordinate` (the dispatcher's, not
substituted); the `recommend` steps of that workflow are **2 and 6**, and `exec_review` is **4**.

## 5. Not done, and why

- `coordinate` (46 steps, the largest model-routed class) is the sibling's §4.2 applier; not touched.
- `knowledge_acquire` (kb_deepen, 3 hits) is the doctrine's external-edge case; not substituted.
- The remaining 16 model-backed executors were hit 0 times by the loop since 1 Sep; no substitute
  was built for a class the loop has not reached, and 11 of them are MUST-model by doctrine.
- Category membership in §2 is by routine NAME; a routine named outside the patterns is uncounted.
- Live-caller detection is one hop deep and does not see PostgREST `.rpc()` callers from edge/portal
  code; "no live caller found" is not "dead".

## Appendix — per-routine tables (generated from the live-caller dump, 5 Sep 2026)

### match_routing: 42 fn_* routines by name, 16 with a live caller (cron/trigger/executor/one-hop), 3 whose body reaches HTTP/ai_gateway

| routine | language | live caller | http |
|---|---|---|---|
| fn_ai_route(p_task_class text, p_dept_key text, p_confidence numeric, p_fn text, p_escalate boolean, p_require_caps text[], p_agent_key text) | plpgsql | — |  |
| fn_ai_route_tier_rank(p_tier text) | sql | — |  |
| fn_approval_policy_match(p_org uuid, p_entity_type text, p_amount numeric, p_category text, p_emirate text) | sql | called_by:fn_approval_raise_on_award |  |
| fn_capability_enrich_sweep(p_limit integer) | plpgsql | — | yes |
| fn_capability_verify() | plpgsql | called_by:fn_dr_drill |  |
| fn_category_classify(p_text text) | sql | called_by:fn_supplier_discovery_promote |  |
| fn_classify_llm_failure(p_err text, p_http_status integer, p_finish_reason text, p_model text, p_latency_ms integer) | plpgsql | — | yes |
| fn_emit_rfq_classified() | plpgsql | trigger:inquiries |  |
| fn_founder_command_classify(p_text text) | plpgsql | — |  |
| fn_is_matchable(p_verified boolean, p_banned boolean, p_matching_blocked boolean, p_approval_status text, p_permanently_closed boolean, p_chat_strikes integer) | sql | — |  |
| fn_kb_route(p_text text, p_limit integer) | sql | — |  |
| fn_kb_route_activation_blocked(p_catalog_num integer) | plpgsql | — |  |
| fn_kb_route_decide(p_text text) | plpgsql | called_by:fn_kb_route_test_run |  |
| fn_kb_route_test_run(p_limit integer) | plpgsql | cron:kb_route_tests_hourly |  |
| fn_kernel_founder_routing_is_refund_only() | plpgsql | trigger:org_tasks |  |
| fn_kernel_trigger_type_routing_guard() | plpgsql | trigger:kernel_trigger_type |  |
| fn_match_capability(p_trades text[], p_need text, p_products text[], p_brands text[], p_project_type text, p_value numeric, p_emirate text, p_limit integer) | sql | — |  |
| fn_matching_strike_limit() | sql | — |  |
| fn_norm_emirate(p_text text) | sql | called_by:fn_supplier_discovery_promote,called_by:fn_supply_gap_scan |  |
| fn_notify_matched_supplier() | plpgsql | trigger:inquiry_matches |  |
| fn_ops_knowledge_match(p_query_embedding vector, p_agent_key text, p_match_count integer, p_record_types text[]) | plpgsql | — |  |
| fn_phase_c_component_classification_guard() | plpgsql | trigger:phase_c_component |  |
| fn_phase_d_capability_answer(p_step_run_id bigint) | sql | — |  |
| fn_phase_d_capability_request_open(p_input jsonb) | plpgsql | — |  |
| fn_phase_d_capability_result_accept(p_input jsonb) | plpgsql | — |  |
| fn_phase_d_capability_state() | sql | — |  |
| fn_rfq_board(p_search text, p_limit integer, p_offset integer) | plpgsql | — |  |
| fn_rfq_redispatch_sweep(p_limit integer) | plpgsql | cron:rfq_redispatch_6h | yes |
| fn_rfq_required_check(i inquiries) | plpgsql | — |  |
| fn_rfq_score(i inquiries) | plpgsql | called_by:trg_rfq_complete |  |
| fn_route_party(p_name text) | sql | — |  |
| fn_routing_tier_model(p_agent_key text) | sql | — |  |
| fn_supplier_capability_chase(p_days integer, p_max_chases integer) | plpgsql | — |  |
| fn_supplier_capability_derive(p_limit integer) | plpgsql | executor:supplier_capability_derive |  |
| fn_supplier_capability_score(l leads) | plpgsql | called_by:trg_supplier_capability |  |
| fn_supplier_matchable(p_lead_id bigint) | sql | — |  |
| fn_supplier_product_match(p_inquiry_id uuid, p_lead_id bigint) | sql | — |  |
| fn_term_matches(p_text_norm text, p_pattern_norm text, p_lang text) | sql | — |  |
| fn_text_matches_pattern(p_text text, p_pattern text) | sql | — |  |
| fn_unsafe_check_ineligible_match(p_since timestamp with time zone) | sql | — |  |
| fn_unsafe_escalation_route(p_class_key text, p_actor text) | plpgsql | — |  |
| fn_unsafe_match_eligibility_guard() | plpgsql | trigger:inquiry_matches |  |

### quote_quality: 13 fn_* routines by name, 6 with a live caller (cron/trigger/executor/one-hop), 0 whose body reaches HTTP/ai_gateway

| routine | language | live caller | http |
|---|---|---|---|
| fn_boq_fixture_score(p_fixture_id bigint, p_actual jsonb) | plpgsql | — |  |
| fn_category_quote_ready(p_category text, p_spec jsonb, p_label text) | plpgsql | — |  |
| fn_phase_d_comparison_visible(p_comparison_id text, p_caller_customer_id text, p_caller_kind text) | plpgsql | — |  |
| fn_phase_d_quote_original_intact(p_revision_ref text) | plpgsql | — |  |
| fn_quote_category_score(p_quote text) | plpgsql | called_by:fn_quote_recompute_submittable |  |
| fn_quote_coach(p_quote uuid) | plpgsql | — |  |
| fn_quote_comparison_publication_stamp() | plpgsql | trigger:quote_comparisons |  |
| fn_quote_recompute_submittable() | plpgsql | trigger:quote_items |  |
| fn_quote_score_json(p_quote jsonb, p_items jsonb) | plpgsql | — |  |
| fn_quote_spec_group(p_category text) | sql | called_by:trg_quote_quality |  |
| fn_quote_structured_score(p_quote text) | plpgsql | called_by:fn_quote_recompute_submittable,called_by:trg_quote_items_roll |  |
| fn_quote_supplier_is_immutable() | plpgsql | trigger:quotes |  |
| fn_supplier_quote_recommend(p_lead_id bigint, p_inquiry_id uuid) | sql | — |  |

### playbook_rule: 5 fn_* routines by name, 1 with a live caller (cron/trigger/executor/one-hop), 0 whose body reaches HTTP/ai_gateway

| routine | language | live caller | http |
|---|---|---|---|
| fn_apply_playbook(p_agent_key text, p_query_embedding vector, p_query_text text, p_min_similarity real, p_k integer) | plpgsql | — |  |
| fn_org_task_deterministic_done(p_task_id bigint, p_step_run_id bigint, p_output jsonb) | plpgsql | — |  |
| fn_phase_d_rule_applies(p_rule_id text, p_step_id text) | plpgsql | — |  |
| fn_sop_update() | plpgsql | cron:sop_update_weekly |  |
| fn_workflow_step_deterministic_done(p_step_run_id bigint, p_output jsonb) | plpgsql | — |  |

### finance: 81 fn_* routines by name, 47 with a live caller (cron/trigger/executor/one-hop), 1 whose body reaches HTTP/ai_gateway

| routine | language | live caller | http |
|---|---|---|---|
| fn_accrue_dues_interest() | plpgsql | — |  |
| fn_action_invoke_collect() | plpgsql | cron:action_invoke_collect_5min |  |
| fn_ad_spend_ceiling_guard() | plpgsql | trigger:ad_decision |  |
| fn_ad_spend_daily_ceiling() | sql | called_by:fn_ad_spend_ceiling_guard,called_by:fn_company_snapshot |  |
| fn_ad_spend_daily_ceiling(p_demo boolean) | sql | called_by:fn_ad_spend_ceiling_guard,called_by:fn_company_snapshot |  |
| fn_ad_spend_daily_ceiling(p_demo boolean) | sql | called_by:fn_ad_spend_ceiling_guard,called_by:fn_company_snapshot |  |
| fn_ad_spend_daily_ceiling() | sql | called_by:fn_ad_spend_ceiling_guard,called_by:fn_company_snapshot |  |
| fn_ad_spend_daily_ceiling() | sql | called_by:fn_ad_spend_ceiling_guard,called_by:fn_company_snapshot |  |
| fn_ad_spend_daily_ceiling(p_demo boolean) | sql | called_by:fn_ad_spend_ceiling_guard,called_by:fn_company_snapshot |  |
| fn_ad_spend_daily_ceiling(p_demo boolean) | sql | called_by:fn_ad_spend_ceiling_guard,called_by:fn_company_snapshot |  |
| fn_ad_spend_daily_ceiling() | sql | called_by:fn_ad_spend_ceiling_guard,called_by:fn_company_snapshot |  |
| fn_ads_autospend_state() | sql | called_by:fn_ad_spend_ceiling_guard,called_by:fn_ads_autopilot_tick |  |
| fn_ai_spend_guard() | plpgsql | cron:ai_spend_guard_hourly | yes |
| fn_ap_bill_dupe_guard() | plpgsql | trigger:ap_bills |  |
| fn_ap_duplicate_scan() | plpgsql | executor:ap_duplicate_scan |  |
| fn_ap_pay_block_held() | plpgsql | trigger:ap_bills |  |
| fn_ban_overdue_dues() | plpgsql | — |  |
| fn_budget_available(p_dept text) | sql | called_by:fn_check_spend |  |
| fn_budget_rollup() | plpgsql | — |  |
| fn_budget_set(p_budget bigint, p_account text, p_month date, p_amount numeric) | plpgsql | — |  |
| fn_check_spend(p_dept text, p_amount numeric, p_agent text) | plpgsql | executor:spend_check; called_by:fn_action_invoke_dispatch |  |
| fn_collections() | plpgsql | cron:collections_reminders_daily |  |
| fn_cost_per_os(p_days integer) | plpgsql | executor:cost_attribution |  |
| fn_customer_forecast(p_customer uuid, p_horizon_days integer) | plpgsql | — |  |
| fn_dues_to_escalate(p_days integer) | sql | — |  |
| fn_emit_budget_exceeded(p_dept text, p_amount numeric, p_requested_by text, p_purpose text) | plpgsql | called_by:fn_decision_gate |  |
| fn_emit_invoice_received() | plpgsql | trigger:ap_bills |  |
| fn_emit_invoice_received_from_expense() | plpgsql | trigger:expense_entries |  |
| fn_emit_refund_requested() | plpgsql | trigger:refunds |  |
| fn_emit_refund_requested_from_transaction() | plpgsql | trigger:transactions |  |
| fn_finance_ai() | plpgsql | — |  |
| fn_finance_forecast() | sql | executor:cashflow_forecast; called_by:fn_ws_finance |  |
| fn_founder_approval_names_a_real_refund() | plpgsql | trigger:founder_approval_request |  |
| fn_founder_approval_refund_only() | plpgsql | trigger:founder_approval_request |  |
| fn_gl_entry(p_date date, p_memo text, p_source text, p_ref text, p_lines jsonb, p_created_by text) | plpgsql | called_by:fn_gl_sync_business |  |
| fn_gl_journal_immutable() | plpgsql | trigger:gl_journal |  |
| fn_gl_lines_immutable() | plpgsql | trigger:gl_journal_lines |  |
| fn_gl_net_income() | sql | — |  |
| fn_gl_post(p_journal bigint) | plpgsql | — |  |
| fn_gl_reverse(p_journal bigint, p_date date, p_memo text) | plpgsql | — |  |
| fn_gl_sync_business() | plpgsql | cron:gl_sync_nightly |  |
| fn_inquiry_workstream_activate(p_group_id bigint, p_trade_key text, p_actor text) | plpgsql | — |  |
| fn_inquiry_workstream_deactivate(p_group_id bigint, p_trade_key text, p_actor text) | plpgsql | — |  |
| fn_invite_week_activate() | plpgsql | trigger:agent_actions |  |
| fn_kb_reconcile() | plpgsql | executor:kb_reconcile; called_by:fn_org_exec_knowledge_fill |  |
| fn_kernel_refund_decision_record(p_input jsonb) | plpgsql | — |  |
| fn_kernel_refund_ledger_state() | sql | — |  |
| fn_kernel_signal_type_activation_guard() | plpgsql | trigger:kernel_signal_type |  |
| fn_kernel_wrap_and_enable_cron(p_jobid bigint, p_role text, p_dept text, p_authority text) | plpgsql | — |  |
| fn_model_cost_usd(p_model text, p_in_tokens integer, p_out_tokens integer, p_cached_in_tokens integer) | sql | — |  |
| fn_os_reconcile() | plpgsql | — |  |
| fn_phase_c_event_runtime_observation(p_event_id text) | sql | — |  |
| fn_phase_c_non_refund_founder_approvals() | sql | — |  |
| fn_phase_c_refund_decision_guard() | plpgsql | trigger:phase_c_refund_decision |  |
| fn_phase_c_refund_decision_immutable() | plpgsql | trigger:phase_c_refund_decision |  |
| fn_phase_c_refund_execution_requires_decision() | plpgsql | trigger:refunds |  |
| fn_phase_c_reporting_map_drift() | sql | — |  |
| fn_phase_d_catalogue_payment_state_declared() | plpgsql | trigger:phase_d_fixture_catalogue |  |
| fn_phase_d_stage_payment_state_declared() | plpgsql | trigger:phase_d_fixture_stage |  |
| fn_reconcile_doc_blocks(p_grace_days integer) | plpgsql | — |  |
| fn_reconcile_licence_blocks(p_grace_days integer) | plpgsql | called_by:fn_doc_expiry_scan |  |
| fn_refund_amount_is_the_fee_paid() | plpgsql | trigger:refunds |  |
| fn_refund_amount_resolve(p_stripe_refund_id text, p_amount_fils bigint, p_by text, p_source text, p_note text) | plpgsql | — |  |
| fn_refund_decide(p_refund_id bigint, p_approve boolean, p_decided_by text, p_note text) | plpgsql | — |  |
| fn_refund_founder_decision_only() | plpgsql | trigger:refunds |  |
| fn_refund_quarantine(p_stripe_refund_id text, p_event_type text, p_reason text, p_payload jsonb, p_stripe_event_id text) | sql | — |  |
| fn_refund_request(p_amount_fils bigint, p_reason_code text, p_requested_by text, p_inquiry_id uuid, p_customer_id uuid, p_supplier_lead_id bigint, p_quote_id uuid, p_payment_intent text, p_charge_id text, p_note text, p_transaction_id uuid) | plpgsql | — |  |
| fn_refund_settle(p_stripe_refund_id text, p_status text, p_amount_fils bigint, p_payment_intent text, p_charge_id text, p_failure_reason text, p_amount_source text, p_stripe_event_id text) | plpgsql | — |  |
| fn_refund_state(p_transaction uuid) | plpgsql | — |  |
| fn_refund_transition_allowed(p_from text, p_to text) | sql | — |  |
| fn_refunds_settled_at() | plpgsql | trigger:refunds |  |
| fn_revenue_cascade(p_dept text, p_role text) | plpgsql | — |  |
| fn_revenue_trajectory() | plpgsql | executor:revenue_trajectory |  |
| fn_spend_concentration_check() | plpgsql | — |  |
| fn_stripe_event_seen(p_event_id text, p_type text, p_status text) | sql | — |  |
| fn_subscription_billing_run(p_dry_run boolean) | plpgsql | — |  |
| fn_supply_gap_scan() | plpgsql | cron:supply_gap_scan_daily |  |
| fn_transactions_refund_needs_the_founder_gate() | plpgsql | trigger:transactions |  |
| fn_unsafe_check_double_refund(p_since timestamp with time zone) | sql | — |  |
| fn_ws_finance() | plpgsql | executor:finance_snapshot; called_by:fn_exec_meeting |  |
| fn_ws_refunds() | sql | — |  |

### compliance_trust: 29 fn_* routines by name, 19 with a live caller (cron/trigger/executor/one-hop), 0 whose body reaches HTTP/ai_gateway

| routine | language | live caller | http |
|---|---|---|---|
| fn_brand_scan() | plpgsql | executor:brand_scan |  |
| fn_check_licence_activity(p_subject_id text, p_content text) | plpgsql | — |  |
| fn_check_licence_expiry(p_subject_id text, p_content text) | plpgsql | — |  |
| fn_emit_regulation_changed() | plpgsql | trigger:compliance_sources |  |
| fn_emit_supplier_suspension_proposed(p_lookback_minutes integer) | plpgsql | cron:supplier_suspension_proposed_daily |  |
| fn_fraud_resolve(p_subject_type text, p_subject_id text, p_action text, p_by text) | plpgsql | — |  |
| fn_fraud_scan() | plpgsql | — |  |
| fn_it_security_knowledge_upsert(p_rid text, p_dept text, p_module text, p_rtype text, p_subdomain text, p_title text, p_content text, p_kw text[], p_risk text, p_source text) | sql | called_by:fn_it_security_live_posture |  |
| fn_it_security_live_posture() | plpgsql | cron:it_security_live_posture_hourly |  |
| fn_it_security_slice(p_dept text, p_q tsquery, p_budget integer) | sql | — |  |
| fn_leads_licence_gate_rerun() | plpgsql | trigger:leads |  |
| fn_legal_ai() | plpgsql | cron:legal_ai_daily; executor:legal_health_scan |  |
| fn_pdpl_erase_plan(p_email text) | sql | — |  |
| fn_pdpl_export(p_email text) | sql | — |  |
| fn_pdpl_redact(p_request_id uuid) | plpgsql | — |  |
| fn_phase_d_legal_assertion_source_is_current() | plpgsql | trigger:phase_d_legal_assertion |  |
| fn_phase_d_legal_source_current(p_source_id text, p_require_authoritative boolean, p_as_of date) | plpgsql | called_by:fn_phase_d_legal_assertion_source_is_current |  |
| fn_regulation_propagate() | plpgsql | trigger:regulations |  |
| fn_regulation_watch() | plpgsql | cron:regulation_watch_weekly |  |
| fn_secops_close_build_mode_door(p_reason text) | plpgsql | — |  |
| fn_secops_test(sample text) | sql | executor:secops_pattern_test |  |
| fn_secops_watch() | plpgsql | called_by:fn_it_security_live_posture |  |
| fn_security_ai() | plpgsql | cron:security_ai_daily |  |
| fn_security_audit() | plpgsql | trigger:app_secrets,trigger:collections_config,trigger:data_owner_registry,trigger:feature_flags,trigger:gl_settings,trigger:pricing_config,trigger:role_permiss |  |
| fn_security_audit_immutable() | plpgsql | trigger:security_audit_log |  |
| fn_security_scan() | plpgsql | cron:agent_security_hourly; executor:security_scan |  |
| fn_security_selfaudit() | plpgsql | cron:security_selfaudit_daily |  |
| fn_supplier_licence_gate(p_license_doc_path text, p_trade_license_no text, p_license_expiry date) | sql | called_by:fn_leads_licence_gate_rerun |  |
| fn_ws_fraud() | sql | — |  |

### kpi_self_review_evolution: 57 fn_* routines by name, 35 with a live caller (cron/trigger/executor/one-hop), 1 whose body reaches HTTP/ai_gateway

| routine | language | live caller | http |
|---|---|---|---|
| fn_agent_remediation_escalate_consume() | plpgsql | cron:remediation_escalate_consume_daily |  |
| fn_assign_training(p_agent_key text, p_competency text, p_purpose text, p_n integer) | plpgsql | called_by:fn_kpi_review |  |
| fn_bi_snapshot() | plpgsql | cron:bi_snapshot_6h; executor:bi_snapshot; called_by:fn_emit_metric_alerts |  |
| fn_bump_exam_question(p_id bigint) | sql | — |  |
| fn_category_specialist_scorecard(p_days integer) | plpgsql | — |  |
| fn_context_retrieval_prune() | sql | — |  |
| fn_customer_preference_learn(p_customer_id uuid, p_stated jsonb) | plpgsql | called_by:trg_learn_customer_preference |  |
| fn_data_metrics() | plpgsql | — |  |
| fn_dept_objective_measure() | plpgsql | cron:dept_objective_measure_daily |  |
| fn_edge_health_scan() | plpgsql | cron:edge_health_scan_15min; executor:edge_health_scan |  |
| fn_emit_health_degraded() | plpgsql | trigger:company_event |  |
| fn_emit_metric_alerts() | plpgsql | cron:emit_metric_alerts; executor:metric_alerts |  |
| fn_employee_kpi_assign() | plpgsql | cron:employee_kpi_assign_daily; executor:kpi_assign |  |
| fn_employee_kpi_measure() | plpgsql | cron:employee_kpi_measure_daily |  |
| fn_eval_run() | plpgsql | executor:eval_run |  |
| fn_eval_snapshot(p_days integer) | plpgsql | called_by:fn_board_report,called_by:fn_eval_run |  |
| fn_evolution_scan() | plpgsql | cron:evolution_scan_weekly; executor:evolution_scan |  |
| fn_exam_pick_agent() | sql | — |  |
| fn_exam_revert(p_agent_key text) | plpgsql | — |  |
| fn_founder_habits_learn() | plpgsql | — |  |
| fn_goal_attainment(p_horizon text) | sql | called_by:fn_founder_brief |  |
| fn_goal_decompose() | plpgsql | — |  |
| fn_goal_pace() | sql | — |  |
| fn_goal_period_refresh() | plpgsql | cron:goal_period_refresh_daily |  |
| fn_health_index() | plpgsql | called_by:fn_board_report,called_by:fn_founder_brief,called_by:fn_period_report |  |
| fn_improvement_handover(p_limit integer) | plpgsql | cron:improvement_handover_hourly |  |
| fn_improvement_plan_refresh() | plpgsql | cron:improvement_plan_daily; executor:improvement_plan_refresh |  |
| fn_knowledge_exam_retrieval() | plpgsql | cron:knowledge_exam_retrieval_daily |  |
| fn_knowledge_exam_sit(p_agent text, p_questions integer) | plpgsql | called_by:fn_knowledge_exam_retrieval |  |
| fn_knowledge_exam_summary() | sql | executor:exam_summary |  |
| fn_kpi_review() | plpgsql | cron:kpi_review_weekly; executor:performance_review |  |
| fn_kpi_scoreboard() | plpgsql | executor:kpi_scoreboard; called_by:fn_employee_kpi_measure,called_by:fn_kpi_review |  |
| fn_learning_loop_sweep(p_limit integer) | plpgsql | cron:learning_loop_sweep_hourly |  |
| fn_metric_class(p_label text, p_metric text, p_unit text) | sql | — |  |
| fn_objective_cascade() | sql | — |  |
| fn_objective_review() | plpgsql | cron:objective_review_weekly; executor:initiative_create |  |
| fn_open_remediation(p_agent_key text, p_failure_class text, p_competency text, p_detail jsonb) | sql | called_by:fn_kpi_review |  |
| fn_ops_metrics() | plpgsql | — |  |
| fn_org_scorecard() | sql | executor:org_scorecard |  |
| fn_os_health() | plpgsql | called_by:fn_exception_alerts |  |
| fn_os_health_brief() | plpgsql | — |  |
| fn_os_objective_measure() | plpgsql | cron:os_objective_measure_daily |  |
| fn_outcome_evaluate() | plpgsql | cron:outcome_evaluate_daily |  |
| fn_phase_c_gate_evaluate(p_gate_id text, p_evidence jsonb) | plpgsql | — |  |
| fn_phase_d_gate_evaluate(p_gate_id text, p_evidence jsonb) | plpgsql | — |  |
| fn_quality_metrics() | plpgsql | — |  |
| fn_remediation_step(p_id bigint, p_score numeric, p_cost_aed numeric) | plpgsql | — |  |
| fn_reputation_hold_state() | sql | — |  |
| fn_reputation_recompute() | plpgsql | cron:reputation_weekly |  |
| fn_retrieval_leak_check(p_agent_key text, p_task_text text) | plpgsql | — |  |
| fn_retrieval_probe(p_agent_key text, p_task_text text, p_category_key text) | plpgsql | — |  |
| fn_self_review() | plpgsql | cron:self_review_weekly; executor:self_review |  |
| fn_strategy_metrics() | plpgsql | called_by:fn_strategy_scan |  |
| fn_supply_health() | plpgsql | — |  |
| fn_verify_objectives_superseded() | plpgsql | executor:verify |  |
| fn_voice_metrics() | plpgsql | — |  |
| fn_watch_health() | plpgsql | cron:watch_health_daily | yes |

### approval_tier: 76 fn_* routines by name, 36 with a live caller (cron/trigger/executor/one-hop), 1 whose body reaches HTTP/ai_gateway

| routine | language | live caller | http |
|---|---|---|---|
| fn_action_authority_rank(p_level text) | sql | — |  |
| fn_action_head_approve(p_action_execution_id uuid, p_decision text, p_reason text, p_approver text) | plpgsql | — |  |
| fn_action_resolve_approver(p_department text, p_risk_tier text) | plpgsql | called_by:fn_action_invoke_dispatch |  |
| fn_agent_autonomy_blocked(p_agent_key text) | sql | called_by:fn_action_invoke_dispatch |  |
| fn_ai_gate(p_answer text, p_sources jsonb, p_confidence numeric, p_action text, p_actor text, p_attrs jsonb) | plpgsql | — |  |
| fn_approval_decide(p_request uuid, p_actor uuid, p_decision text, p_note text) | plpgsql | — |  |
| fn_approval_list(p_customer uuid) | sql | — |  |
| fn_approval_raise_on_award() | plpgsql | trigger:inquiries |  |
| fn_approval_trace_audit() | plpgsql | cron:approval_trace_audit_weekly |  |
| fn_archetype_tier(p_archetype text) | sql | — |  |
| fn_authority_rank(p text) | sql | called_by:fn_org_authority_guard,called_by:fn_task_approve |  |
| fn_autonomy_audit() | sql | called_by:fn_autonomy_audit_run |  |
| fn_autonomy_audit_run() | plpgsql | cron:autonomy_audit_weekly |  |
| fn_autonomy_class(p_kind text, p_target_table text, p_recommendation text) | plpgsql | called_by:fn_autonomy_dispose |  |
| fn_autonomy_control_guard() | plpgsql | trigger:app_secrets |  |
| fn_autonomy_dispose() | plpgsql | cron:autonomy_dispose_hourly |  |
| fn_autonomy_status() | plpgsql | called_by:fn_org_task_autonomy_brake |  |
| fn_cos_work_gate() | plpgsql | — |  |
| fn_decision_gate() | plpgsql | trigger:decision_record |  |
| fn_dept_authority(p_dept text, p_action_class text, p_amount_aed numeric) | plpgsql | called_by:fn_event_dispatch,called_by:fn_task_approve |  |
| fn_emit_supplier_approved() | plpgsql | trigger:leads |  |
| fn_founder_apply_setting(p_key text, p_value text, p_inbound text, p_actor text, p_channel text) | plpgsql | — |  |
| fn_founder_brief() | plpgsql | cron:founder_brief_daily |  |
| fn_founder_command_clarification_answer_is_sealed() | plpgsql | trigger:founder_command_clarification |  |
| fn_founder_command_clarify(p_command_id bigint, p_answer text, p_actor text) | plpgsql | — |  |
| fn_founder_command_control(p_command_id bigint, p_op text, p_target text, p_value text, p_actor text) | plpgsql | — |  |
| fn_founder_command_duplicate_result(p_command_id bigint, p_key text) | sql | — |  |
| fn_founder_command_inbox(p_limit integer) | sql | — |  |
| fn_founder_command_message_immutable() | plpgsql | trigger:founder_command_message |  |
| fn_founder_command_progress_add(p_command_id bigint, p_task_id bigint, p_author text, p_note text, p_evidence jsonb) | plpgsql | — |  |
| fn_founder_command_rollup(p_command_id bigint) | plpgsql | — |  |
| fn_founder_command_state_guard() | plpgsql | trigger:founder_command |  |
| fn_founder_command_status(p_ref text) | plpgsql | — |  |
| fn_founder_command_submit(p_founder_identity text, p_text text, p_idempotency_key text, p_ctx jsonb) | plpgsql | — |  |
| fn_founder_command_thread(p_command_id bigint) | sql | — |  |
| fn_founder_command_trace_guard() | plpgsql | trigger:founder_command |  |
| fn_founder_habits() | sql | — |  |
| fn_founder_queue(p_limit integer) | sql | called_by:fn_founder_brief |  |
| fn_founder_settings() | sql | — |  |
| fn_gate_state_satisfies(s gate_state) | sql | called_by:trg_inquiry_gate_state_sync |  |
| fn_kb_approve(p_revision bigint, p_reviewer text, p_notes text, p_publish boolean) | plpgsql | — |  |
| fn_kb_gov_approve(p_kind text, p_id text, p_by text) | plpgsql | — |  |
| fn_kernel_founder_approval_state() | sql | — |  |
| fn_kernel_paid_provider_gate(p_model text) | plpgsql | called_by:fn_workflow_step_sweep |  |
| fn_normalize_founder_alert_level() | plpgsql | trigger:founder_alerts |  |
| fn_onboarding_gate(p_agent text) | sql | — |  |
| fn_ops_authority_check(p_dept_key text, p_action_class text, p_amount_aed numeric, p_risk text) | plpgsql | — |  |
| fn_org_authority_guard() | plpgsql | trigger:org_authority |  |
| fn_org_task_autonomy_brake() | plpgsql | trigger:org_tasks |  |
| fn_os_catalog_test_gate(p_category text, p_sample text) | plpgsql | — |  |
| fn_os_portals_gates() | sql | — | yes |
| fn_phase_b_gate_attachment() | sql | — |  |
| fn_phase_c_authority_check(p_action_class text, p_actor text, p_reviewer text) | plpgsql | — |  |
| fn_phase_c_change_request_approval_is_derived() | plpgsql | trigger:phase_c_change_request |  |
| fn_phase_c_change_request_disposition_follows_approval() | plpgsql | trigger:phase_c_change_request |  |
| fn_phase_c_founder_approval_immutable() | plpgsql | trigger:phase_c_founder_approval,trigger:phase_c_frozen_subject |  |
| fn_phase_c_founder_approver_guard() | plpgsql | trigger:phase_c_change_request,trigger:phase_c_freeze_amendment |  |
| fn_phase_c_founder_auth_event_is_server_minted() | plpgsql | trigger:phase_c_founder_auth_event |  |
| fn_phase_c_founder_auth_state() | sql | — |  |
| fn_phase_c_founder_identity_human_only() | plpgsql | trigger:phase_c_founder_identity |  |
| fn_phase_c_founder_subject_bind(p_subject uuid) | plpgsql | — |  |
| fn_phase_c_freeze_amendment_approve(p_input jsonb) | plpgsql | — |  |
| fn_phase_c_gates_for_step(p_step_id text) | sql | — |  |
| fn_phase_c_no_new_founder_approval_path() | plpgsql | trigger:founder_release_approval,trigger:procurement_approval_request |  |
| fn_phase_d_founder_authority(p_run_id bigint, p_step_id text) | plpgsql | — |  |
| fn_phase_d_founder_authority_fixture(p_input jsonb) | plpgsql | — |  |
| fn_phase_d_gate_applies(p_gate_id text, p_step_id text) | plpgsql | — |  |
| fn_phase_d_gate_state() | plpgsql | — |  |
| fn_po_approve(p_po bigint, p_by text) | plpgsql | — |  |
| fn_prompt_approve_draft(p_key text, p_version integer, p_by text) | plpgsql | — |  |
| fn_protect_gate_secrets() | plpgsql | trigger:app_secrets |  |
| fn_report_recommendation_approve(p_report_id bigint, p_index integer, p_by text, p_source text) | plpgsql | — |  |
| fn_should_escalate(ctx jsonb) | plpgsql | called_by:trg_action_gate |  |
| fn_supplier_autoapprove_clean(p_limit integer) | plpgsql | executor:supplier_approve_clean |  |
| fn_supplier_tier(p_lead_id bigint) | sql | — |  |
| fn_task_approve(p_dry_run boolean) | plpgsql | cron:task_approve_hourly |  |

Unclassified fn_* routines (not matched by any category pattern): 737; total fn_* routines 1040; total public functions 1653; with any live caller 516.
