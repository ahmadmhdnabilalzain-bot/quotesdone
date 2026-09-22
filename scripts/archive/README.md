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
