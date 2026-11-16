# scripts/archive/ — one-shot scripts that have already run

Measured 22 September 2026 (it_engineer). `scripts/` held **95 files at its root**. Of those, **36
are named by nothing else in the tracked tree** — not by another script, not by a workflow, not by
a check, not by a SQL file's header, not by a document. They are here.

Nothing is deleted. Every file below did a job once — a migration recovery, a Row-3 generator, a
codemod, a probe — and the job is done. They stay because they record HOW something was measured
and repaired, which is the same reason `scripts/checks/retired/` exists. They are not run, not
maintained, and not on any path.

**The measurement, repeatable:** for each `scripts/<file>`, search every other tracked file
(excluding `graphify-out/`) for the basename. Zero hits anywhere = archived. A file referenced only
by a *document* was left in `scripts/`; the bar for moving was "nothing at all names it".

**If one of these is needed again**, move it back with `git mv` and say in the commit what names it
now. A script in `scripts/` root is one something calls.

**Their imports were repaired, not left to rot.** Moving these files down one level broke the
relative specifiers in them. Measured 23 Sep 2026 — and stated as what it counts, because the first
version of this paragraph said "38 repointed, the remaining 4" and then described three files:

- **42** relative path literals (`'./…'` or `'../…'` ending `.mjs`/`.js`/`.ts`) across the 21 files;
- **39** resolve to a file on disk. 38 of them had to be repointed to get there —
  `./staging/qd_guard.mjs` → `../lib/qd_guard.mjs`, `./staging/demo_factory.mjs` →
  `../lib/demo_factory.mjs`, and `dwg_takeoff.ts`'s reach into
  `supabase/functions/_shared/doc_read/dwg.ts`, which needed one more `../`;
- **3** do not resolve, and are right not to.

The 3 are `migrate_internal_auth_gates.mjs:15`, `_pass2.mjs:20` and `_pass3.mjs:22`, each holding
`'../_shared/internal_auth.ts'` inside the import line the codemod WRITES INTO an edge function. It
is correct relative to its destination and was never resolvable from `scripts/`. A path in a string
is not an import — repointing it would have broken the codemod while making a checker happy.

| file | what it did |
|---|---|
| `apply_demo_fixture.mjs` | applied one demo-fixture `.sql` to staging and then production with identical text |
| `b6_touchpoints.mjs` | listed which routines the Stage B.6 migrations created vs. replaced, so a rollback restored rather than dropped |
| `b7_ci.ps1` | a PowerShell wrapper that ran `npm test` and printed the last 25 lines; hard-coded the founder's checkout path |
| `backfill_production_embeddings.mjs` | filled the 1,496 of 4,956 production knowledge chunks that had no embedding vector |
| `delete_functions.mjs` | the counterpart to `deploy_functions.mjs`, written after 137 functions were removed by hand on 8 Sep 2026 |
| `dwg_takeoff.ts` | ran the edge DWG reader off-edge, where there is no 2 s CPU cap, to measure a large drawing |
| `gen_actions_explain_policies.mjs` | Row 3: generated the SQL making every surfaced action name the rule it was decided under |
| `gen_challenge_reason_from_prior_outcomes.mjs` | Row 3: made `fn_challenge` say why it refused a proposal |
| `gen_company_map_places_suppliers_and_knowledge.mjs` | Row 3: put suppliers and knowledge on the company map (3 of 6 classes were present) |
| `gen_console_six_boards.mjs` | Row 3 layer 13: the command centre showed 2 of its 6 boards |
| `gen_escalate_on_prior_failure.mjs` | Row 3 s28: made decision paths consult the 287 recorded lessons |
| `gen_evolution_asks_structural_questions.mjs` | Row 3 s35: the Evolution OS had never asked a structural question |
| `gen_health_note_names_its_cause.mjs` | Row 3 layer 3: the lobby's prose insight slot rendered null |
| `gen_manual_documents_policies_rules_departments.mjs` | Row 3 s38: the operating manual documented 1 of 4 categories |
| `gen_opportunity_scan_five_questions.mjs` | Row 3 s29: the opportunity scan asked 2 of its 5 questions |
| `gen_os_flow_reaches_the_map.mjs` | Row 3: the ten OSes talked 932 times a week and no surface drew a connection |
| `gen_period_report_competitive_section.mjs` | Row 3 s37: 27 competitors tracked, none ever named in a board report |
| `gen_replay_six_tracks.mjs` | Row 3 s33: the replay held twelve days and could show one track of six |
| `gen_snapshot_carries_customers.mjs` | Row 3: the daily snapshot recorded everything except customers |
| `gen_spend_respects_reputation.mjs` | Row 3 s32: reputation was computed for 66 employees and consulted by no authority routine |
| `match_recovered_migration_versions.mjs` | derived the applied version of each reconstructed `20260724_*` migration and renamed the files |
| `measure_sales_engineer_estate_retrieval.mjs` | measured what share of portal questions the Sales Engineer answered from retrieval alone |
| `migrate_internal_auth_gates.mjs` | audit 9.5 codemod: moved cron-reached functions onto `requireInternal()` |
| `migrate_internal_auth_gates_pass2.mjs` | the 16 gates pass 1 refused, in two families |
| `migrate_internal_auth_gates_pass3.mjs` | the three remaining gate shapes; anything else was refused rather than guessed |
| `probe_rating_request_three_weeks_after_reveal.mjs` | proved `fn_support_request_ratings_due` on synthetic reveals inside an aborted transaction |
| `probe_sales_engineer_assist_and_report.mjs` | proved the assist floor refuses a nonsense question (a vector search always finds a neighbour) |
| `qd-graph-peek.js` | printed the top-level keys of `graphify-out/graph.json`; `graphify query` replaced it |
| `qd-inventory.js` | a dependency-free file-count inventory of the checkout |
| `record_migration.mjs` | recorded an already-executed statement in `supabase_migrations.schema_migrations` |
| `recover_containment_migrations.mjs` | recovered the applied `p1c_*` containment migrations out of production, byte for byte |
| `seed_category_domain_map.mjs` | linked the 66 catalogue families to the 84-item UAE supplier-category list |
| `seed_category_knowledge_resolver.mjs` | built `fn_category_knowledge`, the first reader the category knowledge base had |
| `seed_executor_governance.mjs` | reclassified the 55 executors that were all stamped "high risk, irreversible, idempotency unknown" |
| `sync_routines_from_production.mjs` | brought staging up to the three routines whose real fixes only ever reached production |
| `verify_deployed_bundles.ps1` | verified a deploy against the deployed bundles rather than the CLI exit code |

## Moved here on 9 Nov 2026 (scripts/ root tidy)

Measured 9 Nov 2026: the root held **59 files**; **7** were live (a workflow, `local_gate`,
`release_train` or an import runs them) and **12** are documented as manual commands. The other
**40** were only cited by archived documents, audit reports, or the header comments of SQL and
migration files that were already applied. 39 of them are below (including 3 `.ps1`); `gen_baseline_migration.mjs`, `check_migration_order.mjs` and `promote_rows_to_production.mjs` stay at the root
until `supabase/migrations_history/README.md`, which tells a person to run the first two, is
reworked. The "95 files at its root" figure in the opening paragraph is the 22 Sep measurement; the root now holds 20 files.

Repairs made to each moved file: `'./lib/…'` became `'../lib/…'`; `new URL('../supabase/…', import.meta.url)`
gained one `../`; `path.join(__dirname, '..', …)` gained one `'..'`; the `node scripts/<name>` usage lines
and `usage:` messages name `scripts/archive/<name>`. Live references were repointed:
`scripts/checks/schema_dump_not_replayable.test.mjs`, `scripts/staging/apply_taxonomy_fix.mjs`,
`scripts/deploy_functions.mjs`, `src/lib/supaEnv.ts`, `docs/agents/RETIRED_PHASE_DRIVES.md`,
`docs/audit/*` and the three `supabase/migrations_history/*.md` manifests.

**Stale headers on applied files are expected and are not fixed.** Applied SQL is immutable:
`scripts/sql/**`, `supabase/migrations/**` and `supabase/migrations_history/*.sql` say
`GENERATED by scripts/gen_<x>.mjs`, `Recovered by scripts/recover_<x>.mjs` or `Recovered from production's
migration ledger by scripts/recover_missing_migrations.mjs` (about 500 files). Those paths no longer
exist at the root; the file is in this folder under the same basename, and the table below is the
index that resolves them. The generators also still print the old path in the header they write, because
that string reproduces the applied file byte for byte.

| old path | what it did | why archived | archived |
|---|---|---|---|
| `scripts/recover_missing_migrations.mjs` | recovered the migration files the repository never had from production's own ledger (header says `Recovered ... by`; 445 `supabase/migrations_history/*.sql` cite it) | migration recovery finished Aug 2026; nothing runs it | 9 Nov 2026 |
| `scripts/recover_one.mjs` | recovered one applied migration verbatim, checked against a committed SHA-256 manifest (8 migration headers cite it) | recovery done | 9 Nov 2026 |
| `scripts/recover_stage_a_b_b5.mjs` | recovered the Stage A/B/B.5 migrations verbatim from `schema_migrations` (32 migration headers + 1 `scripts/sql` header cite it) | recovery done | 9 Nov 2026 |
| `scripts/recover_stage_b6.mjs` | recovered the Stage B.6 migrations verbatim and verified each against its manifest (14 migration headers + 1 `scripts/sql` header cite it) | recovery done | 9 Nov 2026 |
| `scripts/rename_recovered_to_applied_version.mjs` | renamed the recovered files from a repository sequence number to their applied 14-digit version | recovery done | 9 Nov 2026 |
| `scripts/inventory_recovered.mjs` | listed every object the recovered P2-C1 migrations create or alter, to build an exact teardown set | replay verification done | 9 Nov 2026 |
| `scripts/verify_migrations_in_repo.mjs` | confirmed every applied migration has a file in the repository, matched by name | recovery done | 9 Nov 2026 |
| `scripts/verify_repo_production_parity.mjs` | two-directional check of `supabase/migrations` against the applied record (SHA-256, duplicate versions) | superseded by `scripts/verify_deploy_parity.mjs` | 9 Nov 2026 |
| `scripts/sync_migrations_from_prod.js` | pulled migrations applied through the management API back into the repository, via the kb-import token | the one-ledger workflow replaced it; `__dirname` path repaired | 9 Nov 2026 |
| `scripts/sync_knowledge_delta_to_staging.mjs` | re-levelled `agent_knowledge` / `kb_chunks` from production to staging | staging project was deleted 15 Aug 2026 | 9 Nov 2026 |
| `scripts/sync_org_config_to_staging.mjs` | copied eleven founder-authored org-config tables from production to staging | staging project deleted | 9 Nov 2026 |
| `scripts/verify_prod_parity.mjs` | asked whether anything was still staging-only, comparing content rather than counts | staging project deleted | 9 Nov 2026 |
| `scripts/verify_prod_readiness.mjs` | read-only measurement of which part of the section 8 production deployment sequence was outstanding | one-time deployment sequence; done | 9 Nov 2026 |
| `scripts/gen_ai_route_cache_ttl.mjs` | generated `fn_ai_route` handing back the response-cache TTL by one exact string replacement (Row 8) | generated SQL applied | 9 Nov 2026 |
| `scripts/gen_customer_360_reader.mjs` | generated `fn_ws_customer_360` remembering a customer's preferences (`scripts/sql/fn_ws_customer_360.sql`) | generated SQL applied | 9 Nov 2026 |
| `scripts/gen_exec_meeting_agenda_debate_priorities.mjs` | Row 3 layer 5: gave the weekly executive meeting an agenda, a debate and ranked priorities | generated SQL applied | 9 Nov 2026 |
| `scripts/gen_graph_category_agent_edge.mjs` | Row 6: fixed the `fn_graph_rebuild` category-to-agent edge | generated SQL applied | 9 Nov 2026 |
| `scripts/gen_knowledge_workspace_shows_what_was_used.mjs` | gave `kb_usage_log` a reader (`scripts/sql/knowledge_workspace_shows_what_was_used.sql`) | generated SQL applied | 9 Nov 2026 |
| `scripts/gen_os_health_reaches_the_exec_meeting.mjs` | Row 2: carried per-OS health into the executive meeting | generated SQL applied | 9 Nov 2026 |
| `scripts/gen_pdpl_customer_preference.mjs` | added `customer_preference` to the PDPL export and erasure path | generated SQL applied | 9 Nov 2026 |
| `scripts/gen_simulation_action_carries_its_evidence.mjs` | made a simulation's approval cite the simulation as its evidence | generated SQL applied | 9 Nov 2026 |
| `scripts/gen_simulation_offers_the_action.mjs` | made a simulation that produced a projection leave an approval the founder can act on | generated SQL applied | 9 Nov 2026 |
| `scripts/gen_surfaces_carry_alternatives.mjs` | made four action surfaces project `decision_log.alternatives` | generated SQL applied | 9 Nov 2026 |
| `scripts/gen_what_if_measures_the_cache.mjs` | made `fn_what_if` measure the cache instead of quoting a hard-coded figure | generated SQL applied | 9 Nov 2026 |
| `scripts/gen_what_if_result_carries_confidence.mjs` | put the simulation's confidence in the result the caller reads | generated SQL applied | 9 Nov 2026 |
| `scripts/probe_it_engineer_seat_and_runtime.mjs` | probed the IT Engineer seat and its deployed runtime against production (9 Sep 2026) | one-shot probe | 9 Nov 2026 |
| `scripts/probe_spend_report_links.mjs` | opened the spend report PDF to prove its links are clickable (reads `scripts/checks/read_pdf_links.ts`) | one-shot probe | 9 Nov 2026 |
| `scripts/diff_drifted_objects.mjs` | character-level diff of objects that differed between staging and production | staging project deleted | 9 Nov 2026 |
| `scripts/diff_schema_shape.mjs` | listed which columns and views differ in shape between staging and production | staging project deleted | 9 Nov 2026 |
| `scripts/audit-screenshots.mjs` | captured every major route at desktop and mobile size for the Phase 0 audit | one-shot audit capture | 9 Nov 2026 |
| `scripts/inventory_internal_auth_gates.mjs` | audit 9.5: inventoried inbound credential comparisons in edge functions | audit done | 9 Nov 2026 |
| `scripts/inventory_outbound_hops.mjs` | audit 9.5: inventoried outbound function-to-function hops with the callee resolved | audit done | 9 Nov 2026 |
| `scripts/pull_asset.js` | pulled one named file out of the private `kb-import-assets` bucket into the repo | corpus import done | 9 Nov 2026 |
| `scripts/pull_kb_import_assets.js` | pulled the knowledge-corpus importer and its reports out of `kb-import-assets` into `knowledge-import/` | corpus import done | 9 Nov 2026 |
| `scripts/seed_agent_library_reader.mjs` | gave the 1,456-row `dept_library` its first reader | seed applied | 9 Nov 2026 |
| `scripts/seed_category_bridge.mjs` | bridged the 56-slug intake taxonomy to the 84 UAE supplier categories | seed applied | 9 Nov 2026 |
| `scripts/deploy_functions.ps1` | Windows PowerShell predecessor of `deploy_functions.mjs` (decision D1, 3 Aug 2026); the `.mjs` and `deploy-functions.yml` replaced it | the workflow runs the `.mjs`; nothing names the `.ps1` as a thing to run | 9 Nov 2026 |
| `scripts/qd-env-check.ps1` | laptop-only check that `SUPABASE_ACCESS_TOKEN` was set at user scope (6 lines) | references none; laptop-only | 9 Nov 2026 |
| `scripts/qd-sb-check.ps1` | laptop-only check for the Supabase CLI token file under `%APPDATA%` (7 lines) | references none; laptop-only | 9 Nov 2026 |

## Moved here on 11 Nov 2026 (technical due-diligence pass)

Each of these worked against the rule the repository now runs on: git is the source of truth for code, and
`scripts/deploy_functions.mjs` is the one deploy path (`docs/reports/2026-11-11-technical-due-diligence.md`). Their
relative paths were repointed one level deeper so they still resolve if anyone reads or runs them.

| old path | what it did | why archived | archived |
|---|---|---|---|
| `scripts/edge-functions.sh` | `pull` downloaded every deployed function over the repository copy; `deploy` deployed one function with its own `NO_JWT` list and `--no-verify-jwt` flag | a second deploy path that passes `verify_jwt` flags, which `deploy_functions.mjs` rule 3 forbids (`supabase/config.toml` is the one source); and pulling production over git reverses the source of truth | 11 Nov 2026 |
| `scripts/qd-pull-functions.ps1` | the Windows twin of `edge-functions.sh pull` | same; laptop-only | 11 Nov 2026 |
| `scripts/promote_rows_to_production.mjs` | copied config rows from staging to production and compared md5 on both | the staging project was deleted 15 Aug 2026; `REF` from `demo_factory.mjs` now resolves to production itself, so it would compare production with production | 11 Nov 2026 |

`supabase/functions/SYNCED_FROM_PRODUCTION.md` (the 27 Jul 2026 record of the last production-to-git sync) moved to
`docs/archive/SYNCED_FROM_PRODUCTION_27_JUL_2026.md` the same day: inside `supabase/functions/` it told a reader that
production, not the repository, was the source of truth.

## Moved here on 16 Nov 2026 (simplification wave B, it_engineer; SITE-05/06)

**scripts/staging/ → scripts/archive/staging/** (121 files, 113 code files, the fixtures and blueprints with them). Measured 16 Nov 2026:
`git grep` for `scripts/staging/`, `../staging/` and `./staging/` outside the folder found no import and no caller in
package.json, scripts/ci/local_gate.mjs, a runbook or a workflow, only comments (applied SQL headers, three edge-function
comments, `scripts/lib/qd_guard.mjs`, `demo_pdf.mjs`), docs, memory notes and the session skill. The staging project was
deleted on 15 Aug 2026, and `scripts/lib/demo_factory.mjs` resolves `REF` to production when `QD_STAGING_REF` is unset, so
every `rehearse_*`, `prove_*` and `verify_*` here now aimed at production. The Row #3 scorer (`verify_os2_blueprint.mjs` and
its blueprints) names 107 routines, of which 54 are gone from production, including `fn_os_portals_gates` (SELECT pg_proc,
16 Nov 2026). `sql_split.test.mjs` tested a splitter only these scripts import: it is `sql_split.test.RETIRED.mjs` here, so
the runner no longer collects a test of archived code. Every relative import was repointed one level deeper, and every
`scripts/staging/` path inside the files now names `scripts/archive/staging/`. Before the move 233 relative specifiers
resolved; after it, 238 did (none lost).

**32 one-shot scripts**, each named by nothing outside applied SQL headers (`git grep -F <stem>`, 16 Nov 2026; the headers
are immutable and this table resolves them). Two candidates of the audit stay live: `scripts/marketing/ingest_chat_leads.mjs`
is the monthly ingest door of founder ruling 1205, and `scripts/seats/export_playbooks.mjs` is the auditor export of
instruction 1013 item 9. Both are manual tools, not one-shots.

| old path | what it did (its header) | archived |
|---|---|---|
| `scripts/mx_sweep.mjs` | MX sweep — ask DNS whether each lead e-mail domain can receive mail at all. This is most of what a paid list verifier does, at zero cost. Current bounce is 5/62 = 8.06% | 16 Nov 2026 |
| `scripts/agents/run_training_retest.mjs` | Drive an open remediation through a real retest. fn_remediation_step only closes a remediation as `passed` on a score that an actual retest produced: the score is read out of agent_train's response, never supplied by thi | 16 Nov 2026 |
| `scripts/codemods/px_to_scale.mjs` | px_to_scale — rewrite arbitrary Tailwind literals onto the named brand scale (the @theme block in src/app/globals.css). Why: the website audit (14 Sep 2026) measured 749 [Npx] font sizes, 30 [var(--line)] brackets and | 16 Nov 2026 |
| `scripts/e2e/a_review_request_is_decided_by_another_model_family.ts` | a_review_request_is_decided_by_another_model_family — ledger 1152, seat ceo. The sandbox proof that a request to review an automated decision is DECIDED, with a real model call, by a model family other than the original  | 16 Nov 2026 |
| `scripts/e2e/conversation_replies_rehearsal.ts` | conversation_replies_rehearsal — measures the model-written conversation replies (rulings 1195/1196/1197) LIVE, on ZZ DEMO subjects only, inside a tagged rehearsal window capped at USD 2. Seat: customer_support (WhatsApp | 16 Nov 2026 |
| `scripts/e2e/wait_for_no_open_window.mjs` | scripts/archive/e2e/wait_for_no_open_window.mjs — wait until no rehearsal window is open, so a run that refuses to start beside another harness run (stage2.mjs, "no other harness run is open") waits for its quiet moment  | 16 Nov 2026 |
| `scripts/eval/case_recall_floor_calibration.mjs` | WHERE DOES "THE SAME CASE" END, FOR EACH EMBEDDER? The measurement behind fn_case_recall's floor. Seat: it_engineer. 23 Sep 2026. fn_case_recall's floor (0.84) was measured for gte-small: paraphrases of one case 0.847-0. | 16 Nov 2026 |
| `scripts/eval/customer_followup_and_reengagement_proof.mjs` | DOES CUSTOMER SUPPORT ASK WHETHER THE CUSTOMER HIRED, RECORD THE ANSWER AS AN OUTCOME, AND NUDGE A QUIET CUSTOMER ABOUT THEIR OWN TRADES, IN THE INQUIRY'S LANGUAGE, NEVER TO A SUPPRESSED ADDRESS? | 16 Nov 2026 |
| `scripts/eval/learning_loop_recall_proof.mjs` | DOES A SEAT REMEMBER A CASE BY MEANING AND USE IT? The learning-loop recall proof. Seat: it_engineer (shared platform). 28 Sep 2026, founder_instruction 887. | 16 Nov 2026 |
| `scripts/eval/supplier_scorecard_proof.mjs` | DOES A SUPPLIER GET A TRUE MONTHLY SCORECARD AGAINST HIS TRADE, IN ENGLISH, WITH THE AVERAGE HIDDEN BELOW THREE SUPPLIERS, ONE TIP BY RULE, "NOT ENOUGH DATA YET" WITH NO DATA, AND ONE E-MAIL A MONTH? | 16 Nov 2026 |
| `scripts/it/add_depends_on.mjs` | Writes the "Depends-on: #N" line the release train honours into the PRs that were opened as a chain before the train existed (it_engineer, 29 Sep 2026). Idempotent: a PR whose body already | 16 Nov 2026 |
| `scripts/it/dropbox_space_reading.ts` | One read-only reading of how full the company Dropbox is (it_engineer, 15 Sep 2026). Uses dropbox_backup's own DropboxClient and refresh. Calls only users/get_space_usage and | 16 Nov 2026 |
| `scripts/kb/can_the_product_still_write.mjs` | CAN THE PRODUCT STILL WRITE? The 7 September deletion removed 461 routines. plpgsql resolves a called routine at RUN time, so every trigger that called one kept existing and its table silently became unwritable -- discov | 16 Nov 2026 |
| `scripts/kb/ceo_knowledge_retrieval_eval.mjs` | DOES THE CEO'S RETRIEVAL FIND THE RIGHT GUIDANCE? The founder's requirement: "Compare performance with and without the added knowledge and playbooks. Keep changes that measurably improve results." | 16 Nov 2026 |
| `scripts/kb/classify_for_the_new_structure.mjs` | WHAT BELONGS TO THE NEW STRUCTURE, AND WHAT DOES NOT Founder, 7 September 2026: "anything that doesnt belong to the current new structure need to be deleted. by new structure i mean today from the time i told you to remo | 16 Nov 2026 |
| `scripts/kb/excise_dropped_routine_definitions.mjs` | CUT THE DROPPED ROUTINES OUT OF THE FILES THAT ALSO DEFINE LIVE ONES 229 files defined nothing but dropped routines and were removed whole. 122 define a MIX: some | 16 Nov 2026 |
| `scripts/kb/import_native_rules_as_records.mjs` | The last 2,537 records of the 86-category corpus. Packages 002-007 ship 13_decision_rules.jsonl in a NATIVE rule shape — {rule_id, category_slug, subcategory_slug, priority, rule_type, when, then, source_ids, confidence, | 16 Nov 2026 |
| `scripts/kb/import_pack3_csvs.mjs` | import_pack3_csvs.mjs — the AI autonomy pack's four CSVs. The scorecard put AI_AUTONOMY_MODEL_ROUTING_AND_TOOLS at 28.6% because only its 32 task classes had a table. The tool matrix (22), the recommended model catalogue | 16 Nov 2026 |
| `scripts/kb/neutralise_inbody_cron.mjs` | NEUTRALISE THE cron.schedule CALLS THAT LIVE INSIDE FUNCTION BODIES The 110 top-level schedule statements were removed by strip_cron_schedules.mjs. Eleven files still | 16 Nov 2026 |
| `scripts/kb/probe_change_deployment_playbooks.mjs` | Prove that every step of the change_deployment workflow now has a company playbook the DETERMINISTIC applier will apply — on production, with no model call (MASTER_PLAN A1 / §4.2). | 16 Nov 2026 |
| `scripts/kb/probe_metric_lifecycle_playbooks.mjs` | Prove, on production and with NO model call, that every metric_lifecycle step the deterministic applier has to work retrieves its OWN authored playbook — cosine at or above the 0.85 floor AND | 16 Nov 2026 |
| `scripts/kb/probe_multilingual_space.mjs` | PROBE: replay the multilingual-space SQL file and exercise its routines inside ONE aborted transaction. Seat: it_engineer. 23 Sep 2026. Nothing commits: the probe raises CHK<<...>> with its counts, which rolls | 16 Nov 2026 |
| `scripts/kb/probe_ops_knowledge_match.mjs` | Prove that fn_ops_knowledge_match returns a decision_playbook / decision_rule / exception_playbook BY MEANING for a department's real need, on production, with no model (MASTER_PLAN §4.2 / A4). | 16 Nov 2026 |
| `scripts/kb/probe_org_task_lane.mjs` | Prove the ORG_TASK LANE retrieves by meaning, on production, with no model (MASTER_PLAN A1 / §4.3). This is the dispatcher's own retrieval, run read-only: for a sample of open org_tasks per cluster it | 16 Nov 2026 |
| `scripts/kb/probe_strategic_review_playbooks.mjs` | Prove, on production and with no model, that every step of the `strategic_review` workflow now has a company playbook the DETERMINISTIC applier will apply: cosine >= 0.85 AND keyword corroboration | 16 Nov 2026 |
| `scripts/kb/recover_functions_triggers_still_call.mjs` | RECOVER THE FUNCTIONS THAT LIVE TRIGGERS STILL CALL Measured, not inferred: a real insert driven at each product table inside an aborted transaction. public.customers refused every row with "function is_disposable_email( | 16 Nov 2026 |
| `scripts/kb/remove_files_for_dropped_routines.mjs` | REMOVE THE SQL FILES WHOSE ROUTINES NO LONGER EXIST Dropping 673 routines from the database leaves their canonical files in scripts/sql, and the routine manifest reports every one as "canonical body not deployed". That i | 16 Nov 2026 |
| `scripts/kb/remove_founder_escalations_from_whatsapp.mjs` | NOTHING ON WHATSAPP REACHES THE FOUNDER ANY MORE Operating constitution 1.2: "Neither agent sends unsolicited operational alerts or approval requests to him." And on the public-contact rule specifically: sharing his numb | 16 Nov 2026 |
| `scripts/kb/reunite_the_quote_leak_guard.mjs` | REUNITE THE QUOTE LEAK GUARD WITH ITS IMPLEMENTATION public.quotes carries trg_mask_quote_contact, which strips contact details out of a quotation's free text so a supplier cannot put a phone number in the scope and reac | 16 Nov 2026 |
| `scripts/kb/set_twilio_auth_token.mjs` | THE TOKEN PROVES ITSELF ON ARRIVAL Sets app_secrets.twilio_auth_token, and then proves the thing the token was wanted FOR — that wa_inbound can now validate a Twilio webhook signature — instead of reporting that a row wa | 16 Nov 2026 |
| `scripts/kb/support_capability_inventory.mjs` | WHAT THE SUPPORT AGENT CAN ACTUALLY STAND ON The build spec is explicit: "Record each capability as verified_ready, exists_but_unverified, missing, disabled or incompatible. Do not infer readiness from a historical repor | 16 Nov 2026 |
| `scripts/wf/connectivity_audit.js` | Read-only DB recipe every agent uses (SUPABASE_ACCESS_TOKEN, or the supabase CLI login file). | 16 Nov 2026 |

The staging folder, file by file (`scripts/archive/staging/<same name>`):

| old path | what it did (its header) |
|---|---|
| `scripts/staging/ai_router/channels.mjs` | SPEC FILE #8, parts B-E — the WhatsApp agent, the email agent, the website widget, and the one customer brain behind all three. B WhatsApp Agent        (43)   D Website Chat Widget (23) |
| `scripts/staging/ai_router/os_cache_and_reuse.mjs` | SPEC FILE #8, part A — paying once for the same answer, and knowing which model earned it. §7  Cache Everything          (2)   §32 Semantic Cache            (1) |
| `scripts/staging/ai_router/os_governance.mjs` | SPEC FILE #8, part A — who is allowed to spend what, and who notices when it goes wrong. §13 AI Profiles          (3)   §37 Internal AI Credits    (4) §14 Monitoring Dashboard (6)   §41 The AI Accountant      (5) |
| `scripts/staging/ai_router/os_router_and_levels.mjs` | SPEC FILE #8, part A §1-§4 — the router layer, the five levels, the decision engine, cascading. §1 The Router Layer          (9) §2 Five AI Levels + the expected distribution (9) |
| `scripts/staging/ai_router/os_runtime.mjs` | SPEC FILE #8, part A — the runtime disciplines: how a call is made, retried, avoided or refused. §8  Streaming            (2)   §29 Smart Image Routing    (2) |
| `scripts/staging/ai_router/os_tokens_and_context.mjs` | SPEC FILE #8, part A — everything about NOT sending tokens you do not need to send. §5  Token Management        (2)   §22 Response Length Controller (4) |
| `scripts/staging/apply_missing_objects.mjs` | apply_missing_objects.mjs — close the gap between staging and production, without a full rebuild. A full baseline replay takes ~50 minutes and drops the public schema to do it. When staging is |
| `scripts/staging/apply_taxonomy_fix.mjs` | apply_taxonomy_fix.mjs — close the three taxonomy gaps verify_taxonomy has been PINNING. These are PRODUCTION REFERENCE DATA, mirrored byte-identically into staging (lead_trade_map is |
| `scripts/staging/audit_demo_fence.mjs` | Audit the production demo fence. Every number here is a count of ROWS THAT BREACH the fence, so a healthy estate reads zero on every line and the file needs no interpretation. |
| `scripts/staging/audit_session_parity.mjs` | IS ANYTHING FROM THIS SESSION STAGING-ONLY? The founder's standing rule is "nothing is for staging. all for deploy." A routine promoted but not deployed, an edge function deployed to one project, a cron scheduled on one  |
| `scripts/staging/blueprint_history.mjs` | Persist one row per blueprint check, so "which check moved" is a query and not a memory. 14 Aug 2026: Row #3 read 136/152 at the start of a session and 135/152 at the end. Both |
| `scripts/staging/browser_fixture.mjs` | browser_fixture.mjs — stand up (and tear down) real staging data for a BROWSER-driven run. §3.6: "Nothing has yet run against the deployed Vercel preview URL. The frontend was verified by |
| `scripts/staging/category_agents/agent_mechanism.mjs` | SPEC FILE #6, section 12 — the agent mechanism. The spec's closing line is "Each agent should implement the same modules". That is a claim about a SYSTEM, not about a corpus: knowledge nobody can reach is not knowledge t |
| `scripts/staging/category_agents/knowledge_domains.mjs` | SPEC FILE #6, sections 3-10 — the eight knowledge domains every category agent must implement. §3 Industry Knowledge        (9)   §7  Quotation Knowledge     ⭐   (8) |
| `scripts/staging/category_agents/optional_modules.mjs` | SPEC FILE #6, section 11 — the Optional Knowledge Modules. Pricing (3) · Brand (4) · Standards (9) · Drawing (7) · Attachment Analysis (7) · FAQ (5) ── WHY THESE ARE SCORED ACROSS THE CORPUS, NOT INSIDE ONE TOPIC ─────── |
| `scripts/staging/category_agents/taxonomy.mjs` | SPEC FILE #6, sections 1-2 — the domain taxonomy and the realistic supplier categories. §1 Domain Taxonomy            (66) — the spec's 66 numbered group headings |
| `scripts/staging/fixtures/licence_pdf.mjs` | licence_pdf.mjs — generate a synthetic UAE trade licence as a real PDF. The other two fixtures in this directory are PNGs generated once with System.Drawing and checked |
| `scripts/staging/gate_decision_chain.mjs` | gate_decision_chain.mjs — runs the ten-step decision chain END TO END on PRODUCTION and reads the effect back. Deploying fn_decide is not evidence that the chain runs; this is. |
| `scripts/staging/journey_test.mjs` | journey_test.mjs — drive the real customer-to-quotation journey against deployed staging. Phase 2's standard is that each step is proven through the deployed application, not that a |
| `scripts/staging/make_fixture_licence_pdf.mjs` | A one-page UAE trade licence for a ZZ DEMO fixture company, built by hand so the media-in path can be exercised end to end without a real supplier's document and without a dependency. |
| `scripts/staging/os2_blueprint/layers_1_8.mjs` | LAYERS 1-8 of OS 2.txt — Executive Lobby, Company Digital Twin, Executive Intelligence, Living Organization, Executive Meeting Room, Company Brain, Time Machine, Future Simulator. |
| `scripts/staging/os2_blueprint/layers_9_15.mjs` | OS 2.txt — Layers 9-15, scored against PRODUCTION. 9 Company Genome            — eleven attributes stored, and inherited by every employee. 10 Company Consciousness     — nine questions asked every night, by nobody's han |
| `scripts/staging/os2_blueprint/screens_10_17.mjs` | SPEC FILE #3, part 2 of the seventeen screens — Executive Reports .. Voice, plus the three explicit design principles. 32 requirements, scored against PRODUCTION. |
| `scripts/staging/os2_blueprint/screens_1_9.mjs` | OS 2.txt — screens 1-9: Executive Home, AI Conversation, Live Company, Organization, Employee View, Company Timeline, Mission Control, Digital Twin, Approval Center. 40 requirements. |
| `scripts/staging/os2_blueprint/sections_21_40.mjs` | SPEC FILE #3, sections 21-40 — Enterprise Event Nervous System .. Company Maturity Index. 42 requirements, scored against PRODUCTION. These twenty sections are where the spec's defining defect is thickest. Almost everyth |
| `scripts/staging/os2_blueprint/ui_closure.mjs` | ui_closure.mjs — the two things spec file #3 needs that pg_proc alone cannot answer. This spec file scores an EXECUTIVE UI. Its defining defect is BUILT_BUT_UNREAD: graph_nodes is |
| `scripts/staging/os_blueprint/component_10.mjs` | Component 10 — the Decision Engine, scored against PRODUCTION. The blueprint names ten steps: Problem, Gather Data, Knowledge Retrieval, Analysis, Risk, |
| `scripts/staging/os_blueprint/components_11_13.mjs` | Spec file #2, components 11-13 — the KPI Engine, the Memory System, the Learning Loop. 21 requirements. Every one of them asks the same three questions in the same order, because |
| `scripts/staging/os_blueprint/components_14_17.mjs` | Components 14-17 of the Universal OS Blueprint, scored against PRODUCTION. 14 Governance      — Can I decide? Can I spend? Can I approve? Should I escalate? Who reviews? |
| `scripts/staging/os_blueprint/components_1_9.mjs` | SPEC FILE #2, components 1-9 — Purpose, Mission, Objectives, Responsibilities, the Employee Object, Knowledge, Inputs, Outputs, Workflows. 30 requirements. |
| `scripts/staging/os_blueprint/cross_os.mjs` | SPEC FILE #2 — the cross-OS contract (15 requirements, ids xos-01 .. xos-15). The eleven links of the cross-OS chain: an event is created, the bus carries it, the relevant |
| `scripts/staging/os_blueprint/the_ten_oses.mjs` | SPEC FILE #2 — "The Ten Operating Systems". 12 requirements. Ten per-OS requirements of identical shape ("<name> OS: row, purpose, mission, owner, responsibilities, objectives, staff"), plus the two rules that bind the s |
| `scripts/staging/portal_blueprint/documents_and_comms.mjs` | SPEC FILE #4, sections 14-18 — Document Vault, Communication Center, AI Memory, Mobile App. 21 requirements, scored against PRODUCTION (section 15, Negotiation AI, retired 21 Sep 2026). |
| `scripts/staging/portal_blueprint/entry_and_twin.mjs` | SPEC FILE #4, sections 1-4 — Entry Experience, Digital Twin, AI Procurement Assistant, Command Center UI. 30 requirements, scored against PRODUCTION. THE CONSTRAINT THAT SHAPES EVERY CHECK HERE. Production carries 20,464 |
| `scripts/staging/portal_blueprint/projects_and_rfq.mjs` | Sections 5-8 of the CUSTOMER PORTAL spec, scored against PRODUCTION. 5  Project Intelligence Workspace — the project entity that groups RFQs, and what it shows |
| `scripts/staging/portal_blueprint/spatial_and_structure.mjs` | SPEC FILE #4, sections 19-22 — 3D/Spatial, Predictive Intelligence, UI Style, Final Structure. 19. 3D / Spatial Features      (4)  — project room, supply chain map, animation, live shipments |
| `scripts/staging/portal_blueprint/suppliers_and_quotes.mjs` | SPEC FILE #4, sections 9-13 — Supplier Discovery, Quote Comparison, Data Visualization, Purchase Approvals, Customer-Supplier Relationships. 30 requirements, scored against PRODUCTION. |
| `scripts/staging/portal_surface.mjs` | WHAT "THE CUSTOMER'S SCREEN" IS, COMPUTED ONCE, FOR EVERY SECTION MODULE OF ROW #4. ── THE DEFECT THIS FILE EXISTS TO REMOVE ──────────────────────────────────────────────────────── |
| `scripts/staging/prove_a01_remediation.mjs` | prove_a01_remediation.mjs — Batch 0 step 3, done as a proof rather than an assertion. The brief's plan was: seed staging with the corrected importer, then delete the duplicates there. |
| `scripts/staging/prove_boq_real_drawing.mjs` | prove_boq_real_drawing.mjs — drive customer_api analyze_drawing with a REAL construction drawing. WHY. The BoQ path had only synthetic fixtures. boq_fixture_check grades drawing_boq against |
| `scripts/staging/prove_catalog_ingest.mjs` | PROVE §7 BY EXECUTION: a price list goes in, product RECORDS come out. The claim §7 makes is a CONVERSION, and the scorer's own note is emphatic that a reader of the |
| `scripts/staging/prove_quote_builder.mjs` | PROVE §11, §14 AND §24 OVER HTTPS: the builder proposes terms, the market reads its demand half, and the settings screen round-trips a preference. ── WHAT THIS IS ACTUALLY TESTING, AS OPPOSED TO WHAT IT LOOKS LIKE IT IS  |
| `scripts/staging/prove_rating_schedule.mjs` | PROVE THE RATING CLOCK: the parser, and the selector, without back-dating anything. The schedule is `revealed_at + the revealed quote's own lead_time`, so the two things worth |
| `scripts/staging/prove_redaction_retry.mjs` | prove_redaction_retry.mjs — does a REFUSED drawing page get a second, targeted attempt? WHAT THIS EXISTS TO ANSWER. drawing_redact runs an adversarial verifier over every rendered page |
| `scripts/staging/prove_supplier_negotiation.RETIRED.mjs` | RETIRED 21 SEP 2026 — prove_supplier_negotiation.mjs WHAT IT PROVED. §12 of the supplier blueprint, the supplier negotiation assistant, executed over HTTPS: it signed in as the demo supplier, POSTed supplier_portal{actio |
| `scripts/staging/prove_supplier_onboard.mjs` | PROVE §2 BY EXECUTION: a sentence in, a structured supplier profile out, on a REAL project. It stands up a throwaway auth user, calls supplier_onboard over HTTPS with a paragraph a real |
| `scripts/staging/prove_supplier_opportunities.mjs` | PROVE §10 OVER HTTPS: the ranked-opportunities action answers, and answers RANKED. supplier_portal resolves the supplier from the caller's e-mail via leads.claimed_by, so this |
| `scripts/staging/rebuild_staging.mjs` | rebuild_staging.mjs — build a usable staging database from the committed baseline. WHY THIS EXISTS The Supabase branch replay failed after 31 of 712 migrations: the repo holds 285 migration |
| `scripts/staging/rehearse_ad_spend.mjs` | AD SPEND AUTOPILOT — the sandbox rehearsal (3 Sep 2026). Proves, on the production database and with the Meta token ABSENT, that the paid-media manager |
| `scripts/staging/rehearse_change_deployment_loop.mjs` | rehearse_change_deployment_loop.mjs — ONE deploy.completed, ONE change_deployment run, START TO DONE WITH THE PAID MODEL HELD, EVERY STEP PERFORMED BY AN EXECUTOR (MASTER_PLAN A1 / §4.2). |
| `scripts/staging/rehearse_drawing_to_suppliers.ts` | rehearse_drawing_to_suppliers — ONE ZZ DEMO drawing, end to end, to the suppliers it is routed to (28 Sep 2026, sales_engineer; founder ledger 30, 31, 32, 580, 703). The SANDBOX rehearsal: fixture rows on the |
| `scripts/staging/rehearse_full_funnel.mjs` | rehearse_full_funnel.mjs — THE WHOLE FUNNEL, PERFECT IN THE SANDBOX (3 Sep 2026). The founder's bar: "nothing needs to be proved with real data. everything should be perfect in the |
| `scripts/staging/rehearse_revenue_loop.mjs` | rehearse_revenue_loop.mjs — the SANDBOX REVENUE-LOOP REHEARSAL, on committed data, torn down after. demo_factory's selftest proves the funnel through quotes. This drives the links after it — the ones |
| `scripts/staging/rehearse_stripe_test_payment.mjs` | rehearse_stripe_test_payment.mjs — A REAL STRIPE TEST-MODE PAYMENT, END TO END (3 Sep 2026). rehearse_full_funnel.mjs proves the reveal with a SYNTHETIC completion event. This closes the last |
| `scripts/staging/rehearse_supplier_loops.RETIRED.mjs` | RETIRED 18 September 2026 — it_engineer. A rehearsal is retired WITH its subject, and every one of this file's five loops has lost its subject. It is kept, not deleted, because the sanctions screen it |
| `scripts/staging/release_held_handoffs.mjs` | release_held_handoffs.mjs — put the held handoffs back THROUGH the gate, not around it. WHY THIS EXISTS AND WHY IT IS NOT AN UPDATE. public.zzz_action_gate is a BEFORE INSERT trigger — |
| `scripts/staging/replay_parity.mjs` | REPLAY A MIGRATION ON STAGING AND ASSERT IT STILL MATCHES PRODUCTION. The repo file is the claim; production is the fact. Replaying the migration on staging and then |
| `scripts/staging/seed_cost_config.mjs` | seed_cost_config.mjs — make the AI cost meter actually meter. Applied DIRECTLY, never as a migration: verify_phase1.mjs asserts the migration ledger matches |
| `scripts/staging/seed_staging_secrets.mjs` | seed_staging_secrets.mjs — give staging the configuration it needs, minus the power to act. WHY THIS EXISTS Third-party credentials in QuotesDone are not Vercel env vars and not Supabase Edge Function |
| `scripts/staging/smoke_staging.mjs` | smoke_staging.mjs — does the staging application actually respond? Phase 1's completion standard is "staging is runnable": schemas exist, Auth works, Storage |
| `scripts/staging/sprobe.mjs` | Execute a statement against STAGING and print whatever comes back, including the error text. Used to exercise a branch no production data reaches: a DO block that mutates, reads the result |
| `scripts/staging/sql_split.mjs` | sql_split.mjs — statement splitter that understands dollar-quoting. full_schema.sql is 32,861 lines and ~700 of them are PL/pgSQL function bodies whose |
| `scripts/staging/sql_split.test.mjs` | Behavioural test for the splitter. Runs standalone: node sql_split.test.mjs |
| `scripts/staging/ssql.mjs` | Read STAGING via the management API. Mirror of scripts/qsql.mjs, which reads production only. |
| `scripts/staging/stg_read.mjs` | Read-only probe against STAGING. Mirrors scripts/qsql.mjs (which is production-only) so a change can be shape-checked on staging before it is applied there. |
| `scripts/staging/supplier_blueprint/collab_map_mobile_ui.mjs` | SPEC FILE #5, sections 18-24 — Collaboration, Network Map, Gamification, Mobile, UI, Tech, Structure. 18. Supplier Collaboration Workspace (8)  — a workspace per customer relationship |
| `scripts/staging/supplier_blueprint/command_and_environment.mjs` | SPEC FILE #5, sections 4-6 — Command Center, 3D Supplier Environment, Supplier Profile Page. 4. Supplier Command Center UI (10) — the home screen, and the spec insists it is NOT a dashboard |
| `scripts/staging/supplier_blueprint/entry_and_onboarding.mjs` | SPEC FILE #5, sections 1-3 — Entry Experience, AI Onboarding, Supplier Digital Twin. 1. Supplier Entry Experience  (9)  — the landing screen, its two CTAs, its animated background |
| `scripts/staging/supplier_blueprint/performance_and_risk.mjs` | SPEC FILE #5, sections 13-17 — Performance, Market, AI Employee, Documents, Risk. 13. Supplier Performance Intelligence (9) — "a LIVING score": five bars and an overall |
| `scripts/staging/supplier_blueprint/product_intelligence.mjs` | SPEC FILE #5, sections 7-8 — Product Intelligence System, AI Product Cards. 7. Product Intelligence (14) — seven upload formats, AI conversion, three counts, searchable |
| `scripts/staging/supplier_blueprint/rfq_and_quoting.mjs` | SPEC FILE #5, sections 9-11 — RFQ Intelligence Center, AI Ranking, Quote Builder. 9. RFQ Intelligence Center (9) — "this is where suppliers make money": the opportunity feed |
| `scripts/staging/supplier_checks.mjs` | THE SHARED MEASUREMENT CONTRACT FOR ROW #5's SECTION MODULES. ── WHY THIS FILE EXISTS ───────────────────────────────────────────────────────────────────────── |
| `scripts/staging/sync_staging_assets.mjs` | sync_staging_assets.mjs — copy the RENDERING assets production depends on into staging. Phase 1 verified "15 / 15 storage buckets" and that measurement was true and useless: it counted |
| `scripts/staging/sync_staging_grants.mjs` | sync_staging_grants.mjs — restore the table privileges that dropping schema public destroys. WHY THIS EXISTS rebuild_staging drops and recreates schema public. That also destroys the schema's DEFAULT |
| `scripts/staging/sync_staging_reference.mjs` | sync_staging_reference.mjs — copy the taxonomy staging needs to route and match. WHY THIS EXISTS route_inquiry reads taxonomy_trade, subcategory_agent_map, lead_trade_map, decision_policy and |
| `scripts/staging/verify_agent_knowledge.mjs` | verify_agent_knowledge.mjs — the department library, and whether an employee can actually see it. dept_library held 1,456 rows in BOTH projects with a tsvector column and a working search |
| `scripts/staging/verify_ai_router.mjs` | SPEC FILE #8 — OPENROUTER COST OPTIMIZATION, scored against PRODUCTION. 226 requirements across five parts, enumerated in docs/archive/sessions/ROW8_REQUIREMENTS.md. |
| `scripts/staging/verify_approval_path.mjs` | THE APPROVAL PATH — 129 advisory tasks had no way to reach 'done', and now they do. The checks that matter here are the NEGATIVE ones. "Tasks got promoted" is trivially satisfied by |
| `scripts/staging/verify_bus_contract.mjs` | Fixture gate for the cross-OS contract: everything bus_contract_close.sql claims to enforce, EXECUTED against real production rows and read back, never inferred from a function body. |
| `scripts/staging/verify_category_agents.mjs` | SPEC FILE #6 — SUPPLIER CATEGORIES AND THEIR AI AGENTS, scored against PRODUCTION. 283 requirements across 12 sections, enumerated in docs/archive/sessions/ROW6_REQUIREMENTS.md. |
| `scripts/staging/verify_company_goals.mjs` | COMPANY GOALS — the seven the architecture spec names, and whether they measure what they claim. revenue_annual's measure was `select count(*) from inquiries where created_at > now()-'30 days'` |
| `scripts/staging/verify_constraints.mjs` | verify_constraints.mjs — the parity dimension nothing measured. §9: "apply_missing_objects.mjs — catalogue diff: enums, sequences, columns, tables, views, |
| `scripts/staging/verify_cost.mjs` | verify_cost.mjs — the AI cost and routing gate. Phase 6's real defect is not that cost is unrecorded. fn_llm_log DOES write ai_cost_log and it works. The defect is that `cost_aed` is 0.00 on every staging row and on 238  |
| `scripts/staging/verify_customer_documents.mjs` | verify_customer_documents.mjs — SPEC §14, the Document Intelligence Vault, proven by EXECUTION. It builds TWO real customers on staging with real auth users, gives each documents that only |
| `scripts/staging/verify_customer_preference.mjs` | CUSTOMER PREFERENCES — spec file #1's "Company Memory", the last requirement in that file. The table held 0 rows and 0 readers. What it was NOT is blocked on the customer portal: |
| `scripts/staging/verify_doc_extract.mjs` | verify_doc_extract.mjs — run the document queue that has never run. doc_extract is a queue drainer over public.documents, pulled by the `doc_process` cron. Staging |
| `scripts/staging/verify_employee_authority.mjs` | employee_authority's 285 ROWS HAD FIRED AT MOST 3 TIMES EVER. Not because the limit was never computed — fn_check_spend reads employee_authority, derives |
| `scripts/staging/verify_employee_object.mjs` | THE EMPLOYEE OBJECT — spec file #1 line 372. "define each one as an employee object with structured attributes such as role, manager, direct reports, KPIs, authority limits, current workload, goals, performance history,  |
| `scripts/staging/verify_event_contract.mjs` | THE CROSS-OS EVENT CONTRACT — links 2, 3, 4, 5 and 14, exercised rather than read. Everything asserted here is reachable ONLY at call time. The precedent is exact: a previous |
| `scripts/staging/verify_exception_window.mjs` | verify_exception_window.mjs — the 14-day licence exception, start to finish. A supplier whose trade licence cannot be read is not rejected. The licence gate puts them in |
| `scripts/staging/verify_fraud_hash.mjs` | verify_fraud_hash.mjs — the copied_quote fraud rule, which could never fire. fn_fraud_scan carries a `copied_quote` rule: group `quotes` by committed_hash having more than |
| `scripts/staging/verify_intake_routing.mjs` | THE INTAKE PATH IN ARABIC, AND THE KNOWLEDGE THAT REACHES IT. Two things this pins, both of which were true and invisible until 6 Aug 2026: 1. An Arabic request could not be classified AT ALL. inquiry_intake's detectCat  |
| `scripts/staging/verify_license_extract.mjs` | verify_license_extract.mjs — the licence reader, and the ceiling the brief called "the next suspect". license_extract passes `max: 1500` to ai_gateway. doc_extract passed `max: 2000` the same way and |
| `scripts/staging/verify_match_similarity.mjs` | verify_match_similarity.mjs — the match percentage survives the write. Both writer sites (dispatch_inquiry, customer_api matchAndNotify) used to pass the literal null |
| `scripts/staging/verify_matching.mjs` | verify_matching.mjs — what a supplier corpus is actually for. Phase 8's corpus is not a scale test. It exists to answer questions that one supplier cannot: |
| `scripts/staging/verify_memory_cluster.mjs` | Fixture gate for spec file #2, components 11-13 (the memory cluster). Everything this proves is BEHAVIOUR AT CALL TIME, against real rows, on STAGING. A DO block that |
| `scripts/staging/verify_os2_blueprint.mjs` | SPEC FILE #3 — the EXECUTIVE UI (OS 2.txt), scored against PRODUCTION, symmetrically. 152 requirements. This spec file is not about whether the company computes something; it is about |
| `scripts/staging/verify_os_blueprint.mjs` | SPEC FILE #2 — the Universal OS Blueprint (OS.txt), scored against PRODUCTION, symmetrically. 110 requirements. The rule that governs every check here is the one that inflated the previous |
| `scripts/staging/verify_os_health_brief.mjs` | Fixture gate for fn_os_health_brief — the reader that closes comp-16's seven dimensions. The claim being tested is not "a function exists". It is: every one of the seven figures |
| `scripts/staging/verify_os_knowledge_cluster.mjs` | THE KNOWLEDGE CLUSTER OF SPEC FILE #2 — objectives that measure, knowledge that routes, workflows that run. One executable gate for four requirements that were all the same failure: |
| `scripts/staging/verify_phase1.mjs` | verify_phase1.mjs — is staging actually deployed, isolated, and in sync with the repo? Phase 1's completion standard is not "the work was done", it is that the claims survive being |
| `scripts/staging/verify_portal.mjs` | verify_portal.mjs — what the customer portal is actually served. §3.3 called this the section that most needs demo data, and it is right: the journey produces |
| `scripts/staging/verify_portal_blueprint.mjs` | SPEC FILE #4 — the CUSTOMER PORTAL, scored against PRODUCTION. 147 requirements across 22 sections. The runner is row #2's (verify_os_blueprint.mjs) with two |
| `scripts/staging/verify_portal_entry.mjs` | PROOF BY EXECUTION for the §1/§2/§20/§21 entry payload — customer_portal action=overview. The scorer reads source; this calls the DEPLOYED function with a real customer JWT and asserts |
| `scripts/staging/verify_portal_inbox.mjs` | PROOF BY EXECUTION for §14 the vault, §16 the unified inbox, and the §3 pre-send brief. |
| `scripts/staging/verify_portal_rfq.mjs` | PROOF BY EXECUTION for the customer_api half of row #4 — §3, §7, §8, §9, §13, §17. Every assertion below was a MISSING verdict on 7 Aug 2026 whose cause was that the routine |
| `scripts/staging/verify_review_chain.mjs` | THE REVIEW CHAIN — built, correct, and called by nothing until now. Every assertion here is reachable only AT CALL TIME. The last patch of this shape reported |
| `scripts/staging/verify_rfq_trace.mjs` | verify_rfq_trace.mjs — the Observability requirement, measured against a real RFQ. AGENTS_AND_KNOWLEDGE_BLUEPRINT.txt asks for one thing under Observability and gives a worked |
| `scripts/staging/verify_row4_intelligence.mjs` | PROVE THE ROW #4 INTELLIGENCE BACKEND BY EXECUTING IT — against STAGING, on fixture data this script creates and then deletes. WHY IT HAS TO CREATE DATA. Production and staging both hold zero customers, zero inquiries an |
| `scripts/staging/verify_spec_architecture.mjs` | SPEC FILE #1 — quotesdone architecture, scored against PRODUCTION, symmetrically. The re-audit's 56 requirements come from the file's five explicit capability lists (12 employee |
| `scripts/staging/verify_supplier_blueprint.mjs` | SPEC FILE #5 — the SUPPLIER PORTAL, scored against PRODUCTION. 234 requirements across 24 sections, enumerated in docs/archive/sessions/ROW5_REQUIREMENTS.md. The count |
| `scripts/staging/verify_supplier_docs.mjs` | verify_supplier_docs.mjs — supplier_api process_docs, end to end, and what the mandatory six decide. §3.1(a): "nothing writes to `supplier-docs` yet (0 objects) — the fixtures go through |
| `scripts/staging/verify_taxonomy.mjs` | verify_taxonomy.mjs — the operational router, and the crosswalk that has to hold for it to matter. Until session 9 staging held NONE of fn_kb_route_decide's inputs: kb_operational_alias was 0 rows |

Data files moved with them: `fixtures/README.md`, `fixtures/drawing_watermarked.png`, `fixtures/drawing_windows.png`, `fixtures/metadata/supplier_drawing_clean.pdf`, `fixtures/metadata/supplier_drawing_dirty.pdf`, `fixtures/metadata/supplier_photo_clean.png`, `fixtures/metadata/supplier_photo_dirty.png`, `fixtures/quotation_supplier.png`.
