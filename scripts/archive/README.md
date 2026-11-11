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
