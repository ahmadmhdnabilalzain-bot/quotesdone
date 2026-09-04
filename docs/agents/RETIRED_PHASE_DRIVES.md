# The Phase C/D acceptance drives are retired — the properties stay (4 Sep 2026, Phase E)

MASTER_PLAN §5.1 / §6 Phase E, steps 3–7, done in the plan's order after PR #495 retired the mirror
gates (docs/agents/RETIRED_MIRROR_GATES.md). The rule that decided every line below:

> A check may compare production to a **property** (a guard refuses, a door opens, a board is
> green, an owner exists, a failed run has a reader). A check that **drives** production to
> reproduce a deliverable, or compares a document to a document, is an acceptance ritual for a
> phase whose freezes the founder removed on 2 Sep 2026.

## Step 3 — the Phase A/B frozen-baseline drift boards

`fn_phase_a_baseline_drift()` and `fn_phase_b_baseline_drift()` compared the live organisation and
the Phase B structure to a digest kept in `org_phase_baseline`. Measured 4 Sep: drift 0 and 0, but
three LIVE routines still consulted them — which is why "retire" meant retargeting, not deleting:

| Caller | Before | After |
|---|---|---|
| `fn_phase_c_invariants` (a kernel board) | rows `phase_a_drift`, `phase_b_drift`, `active_departments`, `canonical_roles`, `category_overlays` — five copies of production | one property row `organization_structural_violations` = `fn_phase_a_organization_violations()` = 0; `phase_b_unresolved_errata` kept |
| `fn_phase_b_invariants` (a kernel board) | row `phase_a.baseline_drift_rows` and fifteen `count.*` rows equal to the frozen counts | gone; `phase_a.organization_violations` and every property block (ownership, coverage, graph, handoffs, authority, integrity) unchanged |
| `fn_phase_d_gate_evaluate` GATE-001 ("Phase A baseline frozen", **hard, workflow_scope ALL**) | refused every step the moment a department was re-carved — a freeze inside the live handler path | "Organisation structurally valid": `fn_phase_a_organization_violations()` = 0. `phase_b_gate`, `phase_c_gate_binding`, `phase_d_gate_contract` updated; GATE-001 evaluates PASSED with empty evidence today |

Then both drift routines were dropped (`scripts/sql/phase_e_retire_the_frozen_baseline_boards.sql`,
recorded in `scripts/sql/DROPPED.txt`). `fn_phase_b_structure_digest` stays — `fn_phase_d_founder_authority`
reads its `founder_boundaries` subject. Repo callers edited in the same commit: `org_connectivity_scenarios`
(the one assertion now reads the violations routine), `phase_c/final_measurements.mjs`, `phase_c/rehearse.mjs`,
`phase_d/run_section8_security_probes.mjs` (the probe list names the replacement routine). Both boards were
fully green after the retarget.

## Step 4 — the acceptance drives in the two "against production" CI jobs

| Check (file now `*.RETIRED.mjs`) | Why it left |
|---|---|
| `phase_c_founder_chain` | drives the whole founder-command chain end to end in one aborted transaction — a reproduction of the Phase C closure, not a property. The doors it walks are each proven by `kernel_positive_controls`; the cancel path by `cancellation_reaches_the_kernel`. |
| `phase_c_command_acceptance` | drives every row of `PHASE_C_COMMAND_ROUTING_ACCEPTANCE_CASES.csv` — the Phase C acceptance deliverable re-run on every PR. |
| `phase_c_command_center_entry_point` | an HTTP drive through `os_api` that **commits** a founder command and then deletes its rows — the only check that left committed rows, and the shape that contended with the live loop. |
| `phase_c_invariants` | a wrapper over the `fn_phase_c_invariants` board, which `kernel_boards_are_green` already reads by signature; its other lines (errata resolved, bindings name deployed routines, routes held, zero paid inference) are rows of that same board. A duplicate reader, not a lost property. |
| `freeze_amendment_names_a_real_change_request` | asserted every `phase_c_freeze_amendment` row names a PCCR document in the tree; the founder removed the freeze-amendment ritual on 2 Sep. |
| `phase_d_documents_do_not_contradict_each_other` | two committed Markdown verdicts and a CSV of NOT_RUN blockers compared to each other — prose against prose. |
| `phase_d_deliverables_match_production` | re-ran the Phase D deliverable builders (which drive production) and diffed the committed CSVs byte for byte — a mirror, and the check that forced the `needs: phase-c` serialisation. |

**Kept, and why** (each read by CI in the one token-holding job):

| Kept | It is a property of production |
|---|---|
| `kernel_invariants` | six numerator/denominator zeros over full tables |
| `kernel_positive_controls` | every canonical kernel door OPENS for the legitimate call (denominator derived from `kernel_write_authority`); found the scenario door on 4 Sep |
| `phase_c_guards_reject_injected_defects` | every guard REFUSES the defect injected at it (a guard that has never refused is no guard) — this is what proves the §5.1 DO-NOT-TOUCH guards fire |
| `kernel_write_guard_both_directions` | §5.1 CI keeper |
| `cancellation_reaches_the_kernel` | nothing survives beneath a cancelled command |
| `active_signal_types_are_executable` | every active signal type is accepted / deduplicated / refused as declared |
| `company_is_fully_wired` | `fn_company_connectivity_register()` is empty |
| `kernel_boards_are_green` | every board by signature is green, ratchets may not grow |
| `every_discharge_claim_reaches_its_table` | a cutover claim names a table its source writes |
| `application_source_of_truth` | now the routine **ownership-ledger** gate (step 5) |
| `anon_cannot_execute_security_definer` | §5.1 CI keeper |
| `a_failed_scheduled_run_has_a_reader` | found `dr_drill` on 4 Sep |
| `phase_d_dispatch_reaches_executed` | kept by name in the plan: a handler reaches EXECUTED with an effect-ledger row, in an aborted transaction |
| `phase_d_input_schemas_are_typed_and_closed` | read-only negative controls: an input contract cannot silently reopen |
| `phase_d_object_record_has_a_contract` | kept by name in the plan: the object store refuses what its contract forbids, both directions |

## Step 5 — one PROD→REPO check for routines

Four files answered "is production running the repository's routines". Now:

| File | Role |
|---|---|
| `scripts/checks/canonical_routine_manifest.mjs` | **the** routine source-of-truth engine — canonical file per routine by explicit sequence, drift both ways, conflicts, manifest gaps, uncommitted DDL. Parity job, every PR. |
| `scripts/checks/canonical_routines.test.mjs` | the `npm test` wrapper proving the engine can refuse (forced counterexample); no parser of its own |
| `scripts/checks/export_from_either_source_is_identical.mjs` | the SCHEMA mirror and the edge-function parity — not routine checks, kept as their own properties |
| `scripts/checks/application_source_of_truth.test.mjs` | counts only what the engine does not own: **1b** a routine the apply order retired that is still deployed, **6** an ownership-ledger row the repository denies. Its lines 1–5 are printed as information; its line 7 (re-running the engine inside itself) is gone. |

## Step 6 — CI parallelism

The `phase-d` job and its `needs: phase-c` are gone; the three Phase D keepers run at the end of the
single serial `kernel-gate` job. The list stays serial on purpose: `kernel_positive_controls` and
`phase_d_dispatch_reaches_executed` both open a committed Phase D scenario against the one database
and `fn_phase_d_committed_scenario_open` refuses a second concurrent OPEN by design. The `parity` job runs
in parallel with it (nothing there opens a scenario). Two pieces of scaffolding stay, each for a cause
that is not the retired contention: `--test-concurrency=1` in `scripts/checks/run.mjs` (the management
API's 429 budget), and the narrow scenario-contention retry in `kernel_positive_controls` (the
workflow's concurrency group is per pull request, so two PRs' runs can drive the door at once —
measured 4 Sep: no routine or cron opens a scenario; only checks do).

## Step 7 — the "66 no-caller functions"

Measured today as the 168 `phase_c_component` rows classified `DEFERRED_RUNTIME_IMPLEMENTATION`:
**91 are pg_trgm / pgvector extension members** (pg_depend deptype `e`; not the estate's to drop, left as
they are) and **77 are application routines**. Census per routine, live: callers in every public
routine body, cron commands and execution wrappers, triggers by `tgfoid`, views and other `pg_depend`
dependents, RLS policies, `org_action_executor` targets, `agent_tool` targets, `critical_capability` probes,
`kernel_write_authority`, boards by signature; and in the repository: `supabase/functions`, `src`,
`scripts` (outside `scripts/sql`), `.github`. The drop file re-measures every axis at apply time and
refuses if a routine gained a caller in the window (six sibling agents write to this database).

### The GL / ERP family — audited first

The GL proper (`fn_gl_post`, `fn_gl_entry`, `fn_gl_reverse`, `fn_gl_sync_business`, `fn_gl_net_income`) was
never orphaned: `fn_gl_sync_business` posts reveal-fee revenue net of the Stripe fee, and refunds, from
`transactions` into `gl_journal` (73 rows), and cron `gl_sync_nightly` (jobid 62) calls it — stood down
16 Aug. **Wired**: re-enabled through the kernel wrap under `financial_controller` / finance. The
sub-ledgers (AP/PO/inventory/fixed assets/fiscal budget) have no business object in a marketplace and
0 rows in every table; expenses reach the company through the expenses mailbox and `invoice_approval`,
and the live budget mechanism is `department_budget` — **dropped** (13).

### The A/B framework — audited first

`experiments` (2 running since 6 Jul), 1 assignment, 0 events. Assignment and recording are the product
surface's calls at exposure and conversion; **concluding** is the deterministic act nothing performed.
**Wired**: `fn_experiment_conclude()` (new) concludes every running experiment once its smallest variant
reaches the sample floor (default 100 per variant), picks the winner by conversion rate and files it
through `fn_agent_decision` (which gains its first caller); cron `experiment_conclude_daily` under
`data_intelligence_director`. Proven by an aborted drive in the apply: with one ZZ-DEMO subject per
variant and a floor of 1, `homepage_cta` concluded and one `agent_actions` row was filed; at the real
floor nothing concludes today; residue 0.

### The table

| Function | Verdict | Wired to / kept why / dropped why |
|---|---|---|
| `fn_gl_sync_business` (+ `fn_gl_entry`, `fn_gl_post`, `fn_gl_reverse`) | wired | cron `gl_sync_nightly` re-enabled through `fn_kernel_cron_exec`, owner `financial_controller` / finance |
| `fn_collections` | wired | new cron `collections_reminders_daily` (portal-channel reminders of outstanding non-response charges; no dues created, no commission, no email), owner `collections_and_revenue_assurance` / finance |
| `fn_experiment_results` | wired | read by `fn_experiment_conclude` for every running experiment |
| `fn_experiment_assign`, `fn_experiment_record` | wired (substrate) | the A/B substrate the concluder reads; assignment/recording are the product surface's calls at exposure/conversion; owner `data_intelligence_director` |
| `fn_agent_decision` | wired | called by `fn_experiment_conclude` to file each verdict; owner `data_intelligence_director` |
| `fn_blueprint_result_prune` | wired | new cron `blueprint_result_prune_weekly` (os_blueprint_result rows > 90 days), owner `it_operations_engineer` / product_eng |
| `fn_ap_duplicate_scan`, `fn_brand_scan`, `fn_dispute_open`, `fn_org_exec_knowledge_fill`, `fn_supplier_autoapprove_clean`, `fn_supplier_capability_derive` | kept | bound to an active `org_action_executor` (brand_scan, supplier_approve_clean and knowledge_fill also reached from workflow steps); `fn_dispute_open` is also an hourly `critical_capability` probe |
| `fn_quote_score_json` | kept | called by `supabase/functions/quote_compare/deterministic.ts` |
| `fn_select_model` | kept | called by `supabase/functions/_shared/llm.ts`; hourly `critical_capability` probe |
| `fn_handoff_open` | kept | called by `agent_brain`; driven by the org connectivity CI checks |
| `fn_handoff_close`, `fn_handoff_respond` | kept | driven by `org_connectivity_signal_path` / `_scenarios` (CI, every PR) |
| `fn_handoff_stalled`, `fn_task_commercial_effect` | kept | registered `agent_tool` targets |
| `fn_refund_amount_resolve` | kept | money path (resolves a quarantined Stripe refund amount); the refund family is DO-NOT-TOUCH |
| `fn_pdpl_export`, `fn_pdpl_erase_plan` | kept | PDPL subject-access and erasure — a legal obligation, operator-driven (`scripts/gen_pdpl_customer_preference.mjs`) |
| `fn_terms_integrity` | kept | T&C hash integrity — the only hard rules |
| `fn_undo`, `fn_supersede_lesson` | kept | MASTER_PLAN §5.2 #8 / #9 are FIX orders, not drops |
| `fn_knowledge_rollback` | kept | the only reverse path for a knowledge ingestion run |
| `fn_internal_credential_retire` | kept | the only audited credential-retirement door |
| `fn_ai_gate`, `fn_company_situation` | kept | Row #3 OS blueprint components the scorer asserts (`scripts/staging/os_blueprint`) |
| `fn_supplier_matchable`, `fn_supplier_quality` | kept | spec-row canonical readers (Row #5) |
| `fn_split_inquiry` | kept | specialist-per-trade RFQ split — a product capability awaiting its `customer_api` action |
| `fn_check_licence_activity`, `fn_check_licence_expiry` | kept | the Supply Verification agent's licence checks (the plan's #1 net-new agent) |
| `fn_role_manager_chain` | kept | the §4.5 approval-chain resolver; 0 callers today |
| `fn_ap_pay` | dropped | AP sub-ledger; ap_bills 0 rows; expenses reach the company through the expenses mailbox and the invoice_approval workflow |
| `fn_po_bill` | dropped | PO sub-ledger; po_orders 0 rows; the company raises no purchase orders |
| `fn_po_create` | dropped | PO sub-ledger; po_orders 0 rows |
| `fn_po_receive` | dropped | PO sub-ledger; po_orders 0 rows |
| `fn_inv_adjust` | dropped | inventory sub-ledger; inv_items / inv_stock_moves 0 rows; a marketplace holds no stock |
| `fn_inv_issue` | dropped | inventory sub-ledger; 0 rows |
| `fn_inv_receive` | dropped | inventory sub-ledger; 0 rows |
| `fn_fa_acquire` | dropped | fixed-asset sub-ledger; fa_assets 0 rows |
| `fn_fa_dispose` | dropped | fixed-asset sub-ledger; fa_assets 0 rows |
| `fn_fa_run_depreciation` | dropped | fixed-asset sub-ledger; fa_assets 0 rows (fn_fa_depreciate loses its only caller with it) |
| `fn_budget_create` | dropped | fiscal-year GL budget; budgets 0 rows; the live budget mechanism is department_budget / fn_budget_available |
| `fn_budget_set_annual` | dropped | fiscal-year GL budget; budgets 0 rows (fn_budget_set loses its only caller with it) |
| `fn_autonomy_check` | dropped | V3-era autonomy classifier superseded by org_authority / fn_autonomy_control_guard |
| `fn_chief_of_staff` | dropped | V3-era chief-of-staff routine superseded by the Founder Command Center and secretary_act |
| `fn_control_mode_identity_active` | dropped | reader over control_mode_identity nothing calls; the OS door is fn_os_open_access |
| `fn_dept_can_plan` | dropped | planning-cap reader nothing calls; dept_plan carries its own cap |
| `fn_doc_control` | dropped | licence-expiry reminder loop duplicating the running agents.security licence_expiring job |
| `fn_doc_diff` | dropped | reader over doc_versions with no surface |
| `fn_doc_history` | dropped | reader over doc_versions with no surface |
| `fn_employee_kpi_trend` | dropped | KPI reader with no consumer; fn_employee_kpi_measure is the live KPI path |
| `fn_employee_responsibilities_backfill` | dropped | one-off backfill over org_agents (seating is owned elsewhere) |
| `fn_employee_scorecard` | dropped | prompt-context builder no context assembler calls |
| `fn_external_authority` | dropped | prompt-context reader no context assembler calls |
| `fn_flag` | dropped | feature-flag evaluator; feature_flags 4 rows nothing reads through it |
| `fn_kb_submit_revision` | dropped | kb_revisions writer nothing calls; the table (10,826 rows) is written by another path |
| `fn_lint_outbound` | dropped | policy lint reader with no consumer |
| `fn_policy_lint_kb_chunks` | dropped | policy lint reader with no consumer |
| `fn_llm_cache_get` | dropped | LLM cache nothing reads; ai_gateway carries its own caching |
| `fn_llm_cache_put` | dropped | LLM cache nothing writes |
| `fn_management_decision_review` | dropped | decision_trace reader with no consumer (a test comment mentions it; nothing calls it) |
| `fn_p2c1_rollback_stage_b6` | dropped | operator rollback for a finished stage; recovery is git |
| `fn_p2c1_rollback_stage_b7` | dropped | operator rollback for a finished stage; recovery is git |
| `fn_phase1_rollback_rehearse` | dropped | mutating rehearsal of the Phase 1 tier-0 rollback; nothing runs it |
| `fn_phase1_status` | dropped | Phase 1 status reader with no surface |
| `fn_prompt_publish` | dropped | prompt registry publisher; prompts 3 rows, published by SQL |
| `fn_quote_category_score_text` | dropped | text-shaped quote scorer; fn_quote_score_json (called by quote_compare) and fn_quote_structured_score are the live scorers |
| `fn_quote_coach_text` | dropped | text-shaped quote coach with no caller |
| `fn_rules_eval` | dropped | business_rules evaluator (4 rows); the live rule substrate is ops_knowledge decision_rule |
| `fn_scenario_verdict` | dropped | Phase D scenario-verdict helper no builder or check calls |
| `fn_unsafe_liveness_probe` | dropped | mutating probe (writes refunds, leads, org_authority …) nothing runs; an unrun mutating probe is a liability |
| `mdm_normalize` | dropped | MDM normaliser nothing calls |
| `run_reveal_nudges` | dropped | duplicate of qd_reveal_nudges (the reveal-nudges cron names the latter) |

Every "kept, no caller" row above is a claim only about today's callers; none of them is an entry
point, and the binding rule (an agent exists only if it owns a decision that fires) still owes each
one a caller or a drop in a later pass.

Files: `scripts/sql/phase_e_retire_the_frozen_baseline_boards.sql`,
`scripts/sql/phase_e_wire_the_ledger_collections_and_experiments.sql`,
`scripts/sql/phase_e_retire_the_no_caller_functions.sql`, their downs under `scripts/sql/down/`,
`scripts/sql/DROPPED.txt` (44 new lines), `.github/workflows/project-parity.yml`.
