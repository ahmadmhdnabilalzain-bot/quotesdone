# Phase D — rollback classification

Required by §0 of the D9 brief, and an extension of `PHASE_D_PRODUCTION_DEPLOYMENT_LEDGER.md` rather
than a replacement for it.

The filename still ends `_D9` because two committed documents reference it by that name
(`PHASE_D_BUILDER_CLOSURE.md`, `PHASE_D_BUILDER_CLOSURE_D9.md`). The **content** is no longer D9-only:
in the D37–D43 remediation increment it was promoted to cover every deployed Phase D migration, and
extended again to `d51` when the concurrent D44–D51 increment landed.

**A previous function body is not an adequate rollback for a new table, column, constraint, trigger,
index, grant, RLS policy, enum or registry row.** So every additive DDL operation below is listed
with its own reversal and with the data consequence of taking it.

---

## What this covers, and where the measurement stops

Population: **all 85** files matching `scripts/sql/phase_d_*.sql`, every one of them applied to
`htdblwldjkcgjvmqkbeh` under `PHASE_D_PRODUCTION_DIRECT_PROTOCOL.md`. The main table below covers 73
and the section "Twelve more, classified 2026-08-20" covers `d45`, `d52`–`d56` and `e4`–`e9`. **The 73
figure and the sentence "There is no `d45`" were both true when written and are both wrong now**;
they are corrected in place rather than deleted, because a count asserted once and never re-read is
the defect this document exists to prevent.

The first revision of this document covered 66 — `phase_d_d0..d43*.sql` — and said so:
`ls scripts/sql/phase_d_*.sql | wc -l` returned **67** at 2026-08-20 00:00:04Z and **71** at
00:10:34Z, the corpus was growing while it was being written, and rather than write a file list that
would be stale within the hour it stated the gap as a rule: *every `phase_d_d44*.sql` and higher is
outside this document's scope and unclassified, and must be classified before Phase D closes*.

**That is now done.** The concurrent increments landed. The seven files the rule pointed at —
`d44`, `d46`, `d47`, `d48`, `d49`, `d50`, `d51` — are classified in the table below alongside the
original 66.

This paragraph then said `ls` and `git ls-files` "both return **73**" and that "there is no `d45`".
Both were true at 2026-08-20 00:10Z and neither is now: `d45` was applied and committed later the
same session, `d52`–`d56` after it, and `e4`–`e9` on 2026-08-20. Both commands now return **85**, so
nothing is untracked, and 66 + 7 + 12 = 85. The twelve are classified in their own section below.

**Production-direct applies leave no row in `supabase_migrations.schema_migrations`.** Measured:
`select max(version) from supabase_migrations.schema_migrations` = `20260811081746`, and 0 rows at or
after `20260817`. So no apply instant in this document is read from the database. Dates come from the
repository — file mtime and commit date — and the only thing production can confirm is that the
object exists **now**. That is the boundary of every "deployed" claim below.

---

## The classes

| class | meaning | reversal |
|---|---|---|
| `EXPLICIT_DOWN_REQUIRED` | creates a table, column, index, trigger, or a constraint on a pre-existing object | a written down script at `scripts/sql/down/<stem>_down.sql` |
| `ROUTINE_RESTORE` | `create or replace function` only | re-apply the predecessor file **and every later file in the chain, in order** — see the deployment defect at the end |
| `ADDITIVE_SURVIVAL_SAFE` | registry-row `insert`/`update` only, no DDL | the named `update`/`delete` that puts the row back |
| `GRANT_RESTORE` | `revoke`/`grant` only, no DDL and no body | re-grant. Must be **applied**, never promoted: `apply_sql --promote` sends only a routine body, so a grant in a promoted file lands nowhere and still prints success |
| `DATA_PURGE_NOT_REVERSIBLE` | deletes rows from a business table | none — the rows are re-created by the fixture builder, not by a rollback |
| `IRREVERSIBLE_WITH_FOUNDER_APPROVAL` | destroys data, drops a column, narrows a type, or removes a row not reproducible from the frozen registries | **0 files carry this class** |

---

## Classification — all 73 deployed Phase D migrations

`routines` counts `create or replace function` statements at column 0. `additive DDL` counts
statements at column 0 only; DDL emitted from inside a routine body would not be seen by that
measurement, and none was found by inspection of the files that create tables. The column reports
DDL — row writes into a table the same file creates are not listed, because re-running the file
restores them; `insert`/`update`/`delete` against a table an **earlier** file created is listed.

| file (`scripts/sql/`) | routines | additive DDL | class |
|---|---|---|---|
| `phase_d_d0_auth_debt_discharged.sql` | 0 | none — 2 `update`s to `phase_d_preflight_requirement` | ADDITIVE_SURVIVAL_SAFE |
| `phase_d_d1_handler_registry_and_executor.sql` | 4 | 2 tables | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d2_business_object_map.sql` | 4 | 2 tables, 1 index, 2 triggers, 30 `v_obj_*` views | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d3_rule_enforcement.sql` | 3 | 1 table; a `drop`/`add constraint` pair on `_enforcement_kind_check` | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d4_remaining_rules.sql` | 2 | 1 table; **2 `drop function`**, one a `bigint`→`text` signature change | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d5_gate_predicates.sql` | 3 | 1 table | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d6_handler_status_is_measured.sql` | 1 | 1 column on `phase_d_handler_binding` | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d7_effect_contract_and_business_writes.sql` | 4 | 3 tables, 2 indexes | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d7b_three_derivation_defects_found_by_the_board.sql` | 1 | constraint widening `phase_d_step_effect_resolution_ck` 4 → 5 values | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d7c_regprocedure_hides_the_schema.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d7d_the_lexicon_matched_nouns.sql` | 0 | none — 1 `insert` into `phase_d_step_effect`, 1 `update` to `phase_d_handler_binding` | ADDITIVE_SURVIVAL_SAFE |
| `phase_d_d8_workflow_driver.sql` | 2 | none | ROUTINE_RESTORE |
| `phase_d_d8b_the_driver_reads_what_each_rule_declares_it_needs.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d8c_a_fixture_that_names_a_state_must_name_a_declared_one.sql` | 2 | none | ROUTINE_RESTORE |
| `phase_d_d8d_no_transition_is_not_an_undeclared_transition.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d8e_a_named_reviewer_needs_a_recorded_verdict.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d8f_the_fixture_reads_the_check_constraint.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d8g_the_closure_gate_counted_its_own_step_run.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d8h_the_file_says_what_the_database_says.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d9_a_run_with_no_open_step_is_waiting_for_acceptance.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d9_one_hundred_and_fifty_nine_contracts_not_one.sql` | 5 | 2 tables, 10 constraints, 1 index, RLS on both; 1 `delete from` | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d9b_a_run_in_waiting_handoff_is_not_a_stopped_run.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d9c_a_scenario_built_in_the_order_reality_builds_it.sql` | 3 | 1 table, 3 constraints, RLS; 1 registry-row `update` | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d9d_a_canonical_write_that_emails_a_supplier.sql` | 3 | 1 registry-row `update` | ADDITIVE_SURVIVAL_SAFE |
| `phase_d_d9e_the_lineage_is_quiet_only_because_it_has_no_address.sql` | 2 | none | ROUTINE_RESTORE |
| `phase_d_d9f_the_writer_covers_two_of_the_six_fields_its_scorer_reads.sql` | 2 | 2 registry-row `update`s | ADDITIVE_SURVIVAL_SAFE |
| `phase_d_d9g_a_generated_fixture_beat_the_real_reference.sql` | 2 | none | ROUTINE_RESTORE |
| `phase_d_d9h_the_owner_of_a_customer_scoped_object_is_a_customer.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d9i_a_harness_that_seeds_the_row_the_step_creates.sql` | 2 | none | ROUTINE_RESTORE |
| `phase_d_d9j_a_run_that_cannot_see_what_it_just_created.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d9k_the_kernel_has_no_rejection_door.sql` | 4 | none | ROUTINE_RESTORE |
| `phase_d_d9l_a_phase_d_key_standing_in_front_of_a_phase_b_guard.sql` | 0 | `drop`/`add constraint` on `phase_d_handoff_contract_handoff_id_fkey` — `restrict` → `cascade` | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d10_seven_cases_for_every_one_of_the_257_steps.sql` | 3 | 1 table, RLS; 1 `delete from` | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d11_two_hundred_and_seventy_three_events_that_have_never_happened.sql` | 1 | 1 table, RLS; 1 `delete from` | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d12_ready_disabled_was_claiming_a_contract_that_is_not_built.sql` | 1 | 1 table, RLS; `phase_d_step_effect_depth_ck` 8 → 6 values | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d13_a_refund_gate_that_fired_before_the_case_was_opened.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d14_a_state_the_target_does_not_declare.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d15_a_reviewer_keyed_on_the_effect_not_the_step.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d16_a_rule_applied_to_the_workflow_that_produces_it.sql` | 2 | none — 1 `insert` into `phase_d_fixture_stage` (`:152`), the 25th stage | ROUTINE_RESTORE |
| `phase_d_d17_the_fixture_had_a_second_door_and_it_was_http.sql` | 3 | 1 table; 2 `delete from` | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d18_an_upsert_that_could_not_find_the_row_it_wrote.sql` | 2 | none | ROUTINE_RESTORE |
| `phase_d_d19_a_generated_payload_rearmed_the_door.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d20_created_open_and_asked_the_gate.sql` | 2 | 3 columns + 1 check constraint + 1 trigger on `phase_d_fixture_stage` | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d21_the_run_renamed_its_own_inquiry.sql` | 2 | none | ROUTINE_RESTORE |
| `phase_d_d22_a_company_scoped_owner_is_still_a_foreign_key.sql` | 2 | none | ROUTINE_RESTORE |
| `phase_d_d23_a_state_can_require_a_companion_column.sql` | 1 | 2 columns on `phase_d_fixture_stage` | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d24_a_new_enforcing_table_with_no_truncate_guard.sql` | 0 | 1 trigger on `phase_d_fixture_stage`; 2 `revoke truncate` | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d25_the_key_was_thrown_away_one_statement_later.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d26_the_step_that_decides_had_nowhere_to_record_it.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d27_move_its_state_said_the_refusal_that_offered_no_way.sql` | 2 | none | ROUTINE_RESTORE |
| `phase_d_d28_a_gate_that_refused_the_workflow_for_doing_its_job.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d29_a_durable_external_adapter_that_never_sends.sql` | 4 | 2 tables; 2 `delete from` | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d30_the_twelve_steps_may_say_ready_disabled_again.sql` | 0 | none — 1 `update` to `phase_d_step_effect` | ADDITIVE_SURVIVAL_SAFE |
| `phase_d_d31_seventy_five_injected_defects.sql` | 1 | 1 table | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d32_the_control_that_left_its_own_rows_behind.sql` | 1 | none; 1 `delete from` | ROUTINE_RESTORE |
| `phase_d_d33_the_cleanup_that_only_cleaned_one_table.sql` | 0 | none; `delete from public.customers` scoped to `full_name like 'ZZ DEMO — %' and email is null` | DATA_PURGE_NOT_REVERSIBLE |
| `phase_d_d34_the_seven_probes_that_were_never_run.sql` | 1 | 2 tables | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d35_a_mention_is_not_a_call.sql` | 0 | none; 7 `revoke execute` | GRANT_RESTORE |
| `phase_d_d36_the_kernel_opens_the_step_and_now_runs_it.sql` | 5 | 1 table, 3 indexes, RLS | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d37_the_rules_read_real_rows_or_they_refuse.sql` | 2 | none | ROUTINE_RESTORE |
| `phase_d_d38_the_authority_the_kernel_acted_under_is_a_recorded_fact.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d39_two_ordering_defects_the_first_real_inquiry_found.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d40_the_arrival_is_known_by_the_inbox_id_already_passed.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d41_inquiry_owner_is_a_role_not_a_customer.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d42_route_state_was_my_own_placeholder.sql` | 3 | 3 columns + 1 check constraint on `phase_d_handler_binding` | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d43_a_signed_in_caller_may_not_name_the_owner.sql` | 0 | none; 1 `revoke execute` + 1 `grant execute` on `fn_phase_d_object_read(jsonb)` | GRANT_RESTORE |
| `phase_d_d44_an_endpoint_that_ignores_an_id_has_not_refused.sql` | 0 | `drop`/`add constraint` ×2 on **pre-existing** tables: `phase_d_section8_probe_result_verdict_check` and `phase_d_injected_defect_status_check`, each 3 → 4 values; 5 `update`s | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d46_a_contract_that_records_intent_but_checks_presence.sql` | 2 | 6 columns + 6 `set not null` + 2 constraints on `phase_d_handler_schema`; 1 `update` to the same table | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d47_nineteen_rules_that_had_never_refused_anything.sql` | 2 | none; 1 `revoke`/`grant` pair on the routine it creates | ROUTINE_RESTORE |
| `phase_d_d48_a_two_context_probe_cannot_find_a_withheld_authority.sql` | 1 | none; **1 `drop function`** — a return-type change on `fn_phase_d_rule_can_refuse()`, re-created 2 lines later | ROUTINE_RESTORE |
| `phase_d_d49_a_freeze_with_no_way_to_record_an_amendment.sql` | 1 | 1 table `phase_c_freeze_amendment` (+ identity sequence, unique index, 4 constraints), RLS | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d50_a_rule_that_could_not_fail_made_one_that_could_not_not_fire.sql` | 2 | none; 2 `update`s to `phase_d_rule_enforcement`, an earlier file's table | ROUTINE_RESTORE |
| `phase_d_d51_callable_is_not_answerable_yet.sql` | 1 | none; 1 `update` to `phase_d_rule_enforcement` | ROUTINE_RESTORE |

Totals: **EXPLICIT_DOWN_REQUIRED 26** · ROUTINE_RESTORE 39 · ADDITIVE_SURVIVAL_SAFE 5 ·
GRANT_RESTORE 2 · DATA_PURGE_NOT_REVERSIBLE 1 · IRREVERSIBLE_WITH_FOUNDER_APPROVAL **0**. 26 + 39 + 5
+ 2 + 1 = 73.

### The four post-`d43` files that changed the arithmetic

**`d44` is `EXPLICIT_DOWN_REQUIRED` and `d48` is not, and the difference is worth stating.** `d44`
alters constraints on tables `d31` and `d34` created — a constraint on a pre-existing object, which
is the class definition. `d48`'s `drop function` looks like DDL to a scan but creates and destroys
nothing: it is `create or replace` written in two statements because the return type moved, and a
replaced body has no down. Its class is `ROUTINE_RESTORE`, with the same caveat `d4:78` carries — the
predecessor in `d47` declares a **different** return type, so restoring it means dropping `d48`'s
signature first, not just re-applying `d47`.

**`d49` creates a `phase_c_*`-named table and it is still a Phase D object.** The only `CREATE TABLE`
for `public.phase_c_freeze_amendment` is `phase_d_d49_…sql:47-60`. That is the mirror of
`public.phase_d_preflight_requirement`, which is named `phase_d_*` and is a Phase **C** object
because `scripts/sql/phase_c_baseline_row_and_d0_preflight.sql:98` creates it and `d0` only
`update`s it. The test is which file creates the object, never which phase the name mentions —
`d49`'s down may drop its table, and no Phase D down may drop `phase_d_preflight_requirement`.

Because `phase_c_freeze_amendment` matches neither `phase_d_%` prefix, the estate inventory in this
document is unchanged by it: `phase_d_*` base tables are still **24** and `phase_d_*` sequences still
**5**, both re-measured 2026-08-20. Any count written as `like 'phase\_d\_%'` will not see the new
table, and that is a reason to say so here rather than a reason to change the query.

**`d47`, `d50` and `d51` closed the 20-rule ratchet.** `select status, count(*) from
public.phase_d_rule_enforcement group by 1` returns `ENFORCED 54`, `OUTSTANDING 0` on 2026-08-20 —
against the 20 `OUTSTANDING` that `PHASE_D_PRODUCTION_DEPLOYMENT_LEDGER.md` records under `d3` as a
ratcheted red in `scripts/checks/kernel-boards.json`. None of the three carries DDL, so none changes
the class arithmetic; the measurement is recorded here because a `ROUTINE_RESTORE` of any of them
re-opens rules that are currently enforced.

---

## Twelve more, classified 2026-08-20 — `d45`, `d52`–`d56`, `e4`–`e9`

The table above covered 73 and asserted **"There is no `d45`"**. `phase_d_d45_a_self_loop_is_a_step_
that_hands_to_itself.sql` had been written and applied hours after that sentence, and `d52`–`d56`
after it; `e4`–`e7` landed on 2026-08-20. `ls scripts/sql/phase_d_*.sql | wc -l` and
`git ls-files scripts/sql/phase_d_*.sql | wc -l` both now return **83**. 66 + 7 + 10 = 83.

Classified by the same comment-stripped scan (`sed 's/--.*$//'`, then `CREATE TABLE`, `ADD COLUMN`,
`ADD CONSTRAINT`, `DROP CONSTRAINT`, `CREATE INDEX`, `CREATE TRIGGER`, `CREATE VIEW`,
`CREATE SEQUENCE`, `CREATE TYPE`, `SET NOT NULL`, `DROP FUNCTION`). **Not one of the ten creates a
new object** — `e7` drops and immediately recreates one, which is a return-type change, not a new object —, so `EXPLICIT_DOWN_REQUIRED` stays at the 26 it was, plus one `GRANT_RESTORE` down that
is written because a grant IS reversible by name.

| file | class | reversal |
|---|---|---|
| `d45_a_self_loop_is_a_step_that_hands_to_itself` | `ROUTINE_RESTORE` | 1 body, `fn_phase_d_event_state()`. Re-apply the predecessor **and every later file replacing it**, in order |
| `d52_a_bound_that_is_visible_in_the_value` | `ROUTINE_RESTORE` + `DATA_PURGE_NOT_REVERSIBLE` | 1 body (`fn_phase_d_bounded`), 1 `revoke`/`grant` pair on the routine it creates, and 2 `delete from` on its own probe tables — the deleted rows have no reversal, by the rule at the head of this file |
| `d53_a_fixture_may_be_opaque_not_the_wrong_type` | `ROUTINE_RESTORE` | 1 body, `fn_phase_d_fixture_context` |
| `d54_the_driver_defaulted_to_the_one_mode_that_refuses_nothing` | `ROUTINE_RESTORE` | 1 body, `fn_phase_d_drive_workflow` — the routine already replaced 20 times, so this is the weakest restore in the estate |
| `d55_the_evidence_stated_the_predicates_own_premise` | `ROUTINE_RESTORE` | 1 body, `fn_os_portals_gates()` |
| `d56_the_ledger_named_the_file_the_routine_used_to_live_in` | `ADDITIVE_SURVIVAL_SAFE` | 2 `update`s to `kernel_routine_ownership`; the reversal is the named `update` back |
| `e4_the_door_was_never_a_browser` | **`GRANT_RESTORE`** | 57 `revoke execute`, no body and no DDL. `scripts/sql/down/phase_d_e4_the_door_was_never_a_browser_down.sql` restores the **exact prior shape** rather than a uniform one — 55 held EXECUTE through PUBLIC, `fn_os_open_access` held an explicit anon + authenticated grant, `fn_goal_attainment` an explicit authenticated one. It must be **applied**, never promoted: `--promote` sends only a routine body, and this file has none |
| `e5_a_red_that_does_not_say_what_is_holding_it` | `ROUTINE_RESTORE` | 2 bodies (`fn_phase_d_effect_reachability` created, `fn_phase_d_effect_state` replaced) and 1 `revoke` on the created routine. Dropping the created routine alone breaks the replaced one that calls it — the pair reverts together or not at all |
| `e6_the_record_still_claimed_the_door_e4_closed` | `ADDITIVE_SURVIVAL_SAFE` | 2 `update`s to `public.phase_c_component` (3 rows) and 1 `insert` into `public.phase_c_freeze_amendment`. **Both halves revert together.** Removing the amendment row without reverting the three component rows makes `fn_phase_c_freeze_drift()` report drift it cannot explain, and reverting the components without removing the amendment leaves an amendment whose `new_digest` matches nothing |
| `e9_four_inputs_the_resolver_said_no_table_held` | `ROUTINE_RESTORE` | 1 body, `fn_phase_d_step_inputs(bigint)`, spliced from the live definition with the `else` branch replaced. Reverting means re-applying its predecessor and every later file that replaces the same routine, in order |
| `e7_the_classifier_read_the_binding_not_the_branch` | `ROUTINE_RESTORE` + `GRANT_RESTORE` | 2 bodies, and the only **`DROP FUNCTION`** in the nine — a return-type change on `fn_phase_d_effect_reachability()`, immediately recreated, not a removed object. Two consequences for a rollback: a dropped body is not recoverable from SQL, so reverting means re-applying `e5` and dropping the `e7` signature first; and the drop discarded `e5`'s ACL, so the file's own `revoke` is load-bearing and its control block asserts the ACL rather than trusting the statement. Whoever restores it must re-revoke |

`e4` is the first `GRANT_RESTORE` in this document with a written down script. The class already
existed — `d43` carries it — and its entry says a re-grant "must be applied, never promoted". That is
the same rule, and it is why the `e4` down is a file rather than a sentence: 57 statements restoring
three different prior shapes is not something to reconstruct from memory at the moment it is needed.

---

## The two files the D9-only classification never saw

### `phase_d_d9l_a_phase_d_key_standing_in_front_of_a_phase_b_guard.sql` — unclassified

Added in commit `a8dfb84`, merged with the rest of #450. It is the twelfth D9 file and the eleven-row
table above it stopped at `d9k`, so nothing ever asked what its reversal was. It carries no routine
and no new object: it drops and re-adds `phase_d_handoff_contract_handoff_id_fkey`, changing
`on delete restrict` to `on delete cascade`.

Down: restore the predecessor, which **is** in the repo at
`scripts/sql/phase_d_d9_one_hundred_and_fifty_nine_contracts_not_one.sql:44-45`.

Live definition read back 2026-08-20:
`FOREIGN KEY (handoff_id) REFERENCES phase_b_handoff(handoff_id) ON DELETE CASCADE`.

### `phase_d_d36_the_kernel_opens_the_step_and_now_runs_it.sql` — unclassified, and untracked when found

Written and applied to production on **2026-08-20** (file mtime `2026-08-20 03:18:01` Asia/Dubai =
`2026-08-19 23:18:01Z`; the timezone matters, the calendar date differs between the two). It was
**untracked** at the start of this increment — `git ls-files scripts/sql/phase_d_*.sql` returned 58
while `ls` returned 59 — absent from `scripts/sql/MANIFEST.txt`, and live on production. It was
committed in this increment as `7090016`.

It creates `public.phase_d_dispatch` (`dispatch_id bigint generated always as identity primary key`,
`:80-81`), three indexes, and enables RLS. Production read-back 2026-08-20 00:00:41Z:
`phase_d_dispatch` exists, RLS on, 0 policies, **0 rows**; sequence
`phase_d_dispatch_dispatch_id_seq` exists.

That is why the live inventory in this document reads **24** `phase_d_*` tables and **5** sequences,
not 23 and 4. One of the 24, `public.phase_d_preflight_requirement`, was created by
`scripts/sql/phase_c_baseline_row_and_d0_preflight.sql:98` and **must not be dropped by any Phase D
down** — `d0` only `update`s two of its rows.

---

## Operations no rollback class had accounted for

**Three `drop function`** — re-measured over all 73 files by
`grep -n -iE '^[[:space:]]*drop function' scripts/sql/phase_d_*.sql`, which returns exactly three:
two in `phase_d_d4_remaining_rules.sql` and one in
`phase_d_d48_a_two_context_probe_cannot_find_a_withheld_authority.sql:36`. The first revision of this
document said "the whole corpus contains exactly two", which was true of the 66 it measured and is
not true of the 73. `d48`'s is
`drop function if exists public.fn_phase_d_rule_can_refuse();`, immediately followed at `:38` by a
`create or replace` of the same identity signature with a **different return type**
(`refusing_context` is a new return column) — the same shape as `d4:78`, a signature change rather
than a body edit, and the reason `d48`'s down is "re-apply `d47` after dropping `d48`'s signature",
not "re-apply `d47`".

In `d4`: `:78` `drop function if exists public.fn_phase_d_reveal_permitted(bigint);` is immediately
followed at `:79` by `create or replace function public.fn_phase_d_reveal_permitted(p_transaction_id
text)`: a `bigint` → `text` signature change, not a body replacement. A `ROUTINE_RESTORE` of the
predecessor file would leave **both** signatures live unless the `text` one is dropped first.
`:149` drops `public.fn_phase_d_rule_check(text, jsonb)` before recreating it.

**Nine `delete from` statements**, none of them in any earlier classification:
`phase_d_d9_one_hundred_and_fifty_nine_contracts_not_one.sql` 1 · `d10` 1 · `d11` 1 · `d17` 2 ·
`d29` 2 · `d32` 1 · `d33` 1.

**Thirty `v_obj_*` views**, which a `drop table … cascade` in a `d2` down takes silently:
`v_obj_ai_change, capability_case, content_campaign, customer_case, customer_selection,
customer_terms_acceptance, dispatch_batch, document_extraction, exception_record, financial_close,
growth_program, inquiry_route_set, inquiry_version, intelligence_product, knowledge_change,
notification_attempt, organization_change_request, performance_recovery_case, product_change,
quotation_evaluation, quotation_revision, reconciliation_case, release_candidate,
supplier_correction_case, supplier_coverage_case, supplier_retention_case, supplier_safe_package,
supplier_terms_acceptance, supplier_verification_case, ux_specification`. Live count 30, and
`select count(*) from public.phase_d_business_object_binding where relation_kind =
'PHASE_D_OBJECT_VIEW'` is also 30. A `d2` down must name them.

**Down order in `d1`:** `drop table public.phase_d_handler_binding;` before
`drop table public.phase_d_handler_schema;` — the binding carries `_input_schema_id_fkey` and
`_output_schema_id_fkey` into the schema table. **`d6` down:**
`alter table public.phase_d_handler_binding drop column business_write_wired;`.

### The five constraint changes, and what restoring each predecessor costs

Three when this document was first written; `d44` added two more. All five are re-measured below on
`htdblwldjkcgjvmqkbeh`, and `d20`/`d42`/`d46` are excluded because their constraints sit on columns
the same file created — the column drop **is** the revert, and there is no predecessor to restore.

| file | change | predecessor | measured consequence of restoring it |
|---|---|---|---|
| `d7b` | `phase_d_step_effect_resolution_ck` 4 → 5 values (adds `MATCHED_ALL_TOKENS`) | `phase_d_d7_effect_contract_and_business_writes.sql:83-84` | **fails.** 18 of the 257 `phase_d_step_effect` rows carry `MATCHED_ALL_TOKENS`. Delete or re-derive those rows first. |
| `d12` | `phase_d_step_effect_depth_ck` 8 → 6 values — a **narrowing plus one addition**, not a widening: it removes `SERVICE_EXISTS_NO_CALLER`, `COMPLETE`, `BLOCKED_DEFECT` and adds `EXTERNAL_ADAPTER_CONTRACT_NOT_BUILT` | `phase_d_d7_effect_contract_and_business_writes.sql:80-82` | **succeeds today.** The live 257 rows are `BUSINESS_EFFECT_CONNECTED` 224, `CAPABILITY_BOUNDARY_READY` 21, `EXTERNAL_ADAPTER_READY_DISABLED` 12 — 0 rows carry `EXTERNAL_ADAPTER_CONTRACT_NOT_BUILT`, so the 8-value predecessor admits every one of them. |
| `d3:65-70` | **not a widening.** It restates the same 7-value `_enforcement_kind_check` list already in the `create table` at `:47-49`; live carries 7 values | — | defensive idempotency reconcile; the down is a no-op |
| `d44:104-108` | `phase_d_section8_probe_result_verdict_check` 3 → 4 values (adds `NOT_DISCRIMINATED`) | `phase_d_d34_the_seven_probes_that_were_never_run.sql:32` — an **unnamed** inline column check, so the name on production is the one Postgres generated | **fails.** 2 of the 23 `phase_d_section8_probe_result` rows carry `NOT_DISCRIMINATED` — the two `d44` reclassified after an HTTP 200 could not separate a refusal from an ignored parameter. Re-run `scripts/phase_d/run_section8_security_probes.mjs` first; do not retype the verdicts. |
| `d44:110-114` | `phase_d_injected_defect_status_check` 3 → 4 values (adds `NOT_DISCRIMINATED`) | `phase_d_d31_seventy_five_injected_defects.sql:39-40`, a named table constraint | **succeeds today.** `phase_d_injected_defect_result` holds **0 rows**, so nothing can violate the 3-value predecessor. |

`d20`'s `phase_d_fixture_stage_contributes_kind_check` has **no** predecessor to restore — the column
`contributes_kind` is created in the same file at `:86`, so the down drops the column and the
constraint goes with it. That drop loses one row's declaration: live `contributes_kind` is
`RESULT_KEY` on 24 stages and `STATE` on 1.

---

## The eleven D9 files, in detail

| file | routines | additive DDL | rollback class |
|---|---|---|---|
| `phase_d_d9_one_hundred_and_fifty_nine_contracts_not_one.sql` | 5 | 2 tables, 10 constraints, 1 index, RLS on both | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d9b_a_run_in_waiting_handoff_is_not_a_stopped_run.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d9c_a_scenario_built_in_the_order_reality_builds_it.sql` | 3 | 1 table, 3 constraints, RLS; 1 registry-row UPDATE | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d9d_a_canonical_write_that_emails_a_supplier.sql` | 3 | 1 registry-row UPDATE | ADDITIVE_SURVIVAL_SAFE |
| `phase_d_d9e_the_lineage_is_quiet_only_because_it_has_no_address.sql` | 2 | none | ROUTINE_RESTORE |
| `phase_d_d9f_the_writer_covers_two_of_the_six_fields_its_scorer_reads.sql` | 2 | 2 registry-row UPDATEs | ADDITIVE_SURVIVAL_SAFE |
| `phase_d_d9g_a_generated_fixture_beat_the_real_reference.sql` | 2 | none | ROUTINE_RESTORE |
| `phase_d_d9h_the_owner_of_a_customer_scoped_object_is_a_customer.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d9i_a_harness_that_seeds_the_row_the_step_creates.sql` | 2 | none | ROUTINE_RESTORE |
| `phase_d_d9j_a_run_that_cannot_see_what_it_just_created.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d9k_the_kernel_has_no_rejection_door.sql` | 4 | none | ROUTINE_RESTORE |

**IRREVERSIBLE_WITH_FOUNDER_APPROVAL: 0.** Nothing in D9 destroys data, drops a column, narrows a
type, or removes a row that cannot be recreated from the frozen registries.

### 1. `public.phase_d_handoff_contract` — created

| | |
|---|---|
| reason | one acceptance contract per effective handoff. `fn_phase_c_handoff_packet_valid` checks a fixed five-key list for all 159 and never reads a handoff's own `required_packet`. |
| can data exist | yes — 159 rows, every column **derived** from `public.phase_b_handoff` |
| rollback SQL | `drop table public.phase_d_handoff_contract cascade;` |
| rollback data consequence | **none that is not reproducible.** Re-running the file regenerates all 159 rows, and `required_packet_sha256` is how that is proved rather than assumed. `cascade` is needed because `phase_d_handoff_acceptance.handoff_id` references it — drop the acceptance ledger first if its rows are to be kept. |
| survival-safe | **yes** — nothing outside Phase D reads it and no frozen object references it |

### 2. `public.phase_d_handoff_acceptance` — created

| | |
|---|---|
| reason | one decision per handoff run. `UNIQUE (handoff_run_id)` is the idempotency guarantee, as a constraint rather than a convention. |
| can data exist | yes — one row per accepted or rejected handoff run. **Zero rows survive this session**: every drive ran in an aborted transaction. Read back 2026-08-20: still 0. |
| rollback SQL | `drop table public.phase_d_handoff_acceptance;` |
| rollback data consequence | **the audit trail of Phase D handoff decisions is lost, and it is not reconstructible.** `phase_c_handoff_run` records the kernel's status but not the packet digest, the SLA due time and breach flag, the rejection code, the missing item, or the accountability pair either side of acceptance. If any row exists at rollback time, export it first. |
| survival-safe | **yes** — no frozen object references it |

### 3. `public.phase_d_fixture_stage` — created

| | |
|---|---|
| reason | the scenario stages in foreign-key order, each naming the canonical object service that produces it and the reference it contributes |
| can data exist | yes — 24 declared rows in the file (`:70`); **25 live**, the 25th inserted by `phase_d_d16_…sql:152` |
| rollback SQL | `drop table public.phase_d_fixture_stage cascade;` |
| rollback data consequence | none — re-running the file restores the declared rows. Note the driver reads `contributes_ref` from this table, so dropping it makes `fn_phase_d_drive_workflow` unable to fold produced references back into the rule context. `cascade` also takes the `d20` and `d24` triggers. |
| survival-safe | **yes** |

### 4. Constraints created (13)

`phase_d_handoff_contract_pkey`, `phase_d_handoff_contract_handoff_id_fkey`,
`phase_d_handoff_contract_keys_ck`, `phase_d_handoff_contract_owner_ck`,
`phase_d_handoff_acceptance_pkey`, `phase_d_handoff_acceptance_handoff_id_fkey`,
`phase_d_handoff_acceptance_outcome_ck`, `phase_d_handoff_acceptance_reject_ck`,
`phase_d_handoff_acceptance_accept_ck`, `phase_d_handoff_acceptance_one_per_run`,
`phase_d_fixture_stage_pkey`, `phase_d_fixture_stage_stage_key_key`,
`phase_d_fixture_stage_object_id_fkey`.

Each is dropped with its own table, so **no rollback touches an object that existed before D9**. None
was added to a pre-existing table. `phase_d_handoff_contract_handoff_id_fkey` was later altered by
`d9l` — see above.

The two foreign keys are declared explicitly in the files, using the identity Postgres itself
generates, because the canonical routine engine can only derive an auto-generated constraint name
when `references` sits on the same source line as its column — a clause wrapped for readability
reads to it as uncommitted DDL. The instrument is not wrong, so the files were made explicit rather
than the check taught to accept a shape it cannot attribute.

### 5. Index created (1)

`phase_d_handoff_acceptance_run_idx` on `(run_id, outcome)`.
Rollback: `drop index if exists public.phase_d_handoff_acceptance_run_idx;` — dropped with the table
in any case. No data consequence.

### 6. RLS enabled (3 tables)

Reversal: `alter table <t> disable row level security;`

All three are revoked from `anon` and `authenticated` and granted only to `service_role`, so RLS here
is defence in depth and not the control. **No policy was added to any of the 536 RLS-on /
zero-policy tables**, deliberately: most internal workflow, kernel and agent tables should remain
server-only deny-all. Measured across the whole Phase D estate on 2026-08-20: all 24 `phase_d_*`
tables carry `relrowsecurity = true` with **0 policies each**.

### 7. Registry-row UPDATEs to `public.phase_d_object_write_map` (3)

| object | change | rollback SQL | rollback data consequence |
|---|---|---|---|
| `supplier_account` | `+ verified` | `update public.phase_d_object_write_map set column_map = column_map - 'verified' where object_id = 'supplier_account';` | the object's own `approved` state becomes unreachable through its canonical writer again, because `public.leads` carries `CHECK (approval_status <> 'approved' OR verified = true)`. BR-015 becomes unsatisfiable by any canonical path — which is exactly the state D9 found. |
| `inquiry` | `+ rfq_ready` (D9d) then `- rfq_ready` (D9f) | net zero, nothing to reverse | none. `rfq_ready` is derived by `trg_rfq_complete` and was never writable; D9d's repair was wrong and D9f removed it. |
| `inquiry` | `+ emirate, scope_type, budget, trades` | `update public.phase_d_object_write_map set column_map = column_map - 'emirate' - 'scope_type' - 'budget' - 'trades' where object_id = 'inquiry';` | the canonical writer drops back to **45 of the 100 points** `fn_rfq_score` measures against a 70 bar. No Phase D path can then produce a quote-ready inquiry, `trg_gate_incomplete_match` silently drops any supplier assignment referencing it, and W12 with everything downstream of a dispatch becomes undrivable. |

**No column was removed from any target table. No enum was altered. No trigger was created, altered
or dropped. No RLS policy was created on a pre-existing table. No grant was widened.** All four
sentences are about the eleven D9 files and remain true of them; `d20`, `d23`, `d24` and `d42` added
columns and triggers later and are classified above.

Every SECURITY DEFINER routine created here is revoked from PUBLIC in the same file and granted only
to `service_role` — `revoke … from anon` alone is a silent no-op when the grant is held through
PUBLIC.

---

## Required results

| required | result |
|---|---|
| deployed Phase D migrations with no rollback classification | **52 of 66 before the first revision; 0 of 66 after it; 0 of 73 now** |
| additive changes requiring an explicit down but having none | **23 of 23 had none before the first increment; 0 of 23 at 2026-08-20 00:14:36Z; 0 of 26 now** — but see the note below: the 26 exist on disk and `git ls-files scripts/sql/down` returns **0** |
| production ahead of main | **true, and expected** — five commits on `feat/phase-d-remediation-to-acceptance` are unmerged: `7090016` (d36–d42), `9dd1927` (d43, d46, d47, d48), `f9415ab` (d49), `5c7152a` (d50, d51), `a7a37a8` (d44). **Nothing is untracked** — `git ls-files scripts/sql/phase_d_*.sql` and `ls` both return 73 |

**What the first row counts.** Deployed Phase D migration files carrying no rollback class in any
Phase D document. The denominator was `scripts/sql/phase_d_d0..d43*.sql`, 66 of them, and is now the
full glob `scripts/sql/phase_d_*.sql`, 73. Before the first revision the only
classifications anywhere were the eleven D9 rows in this file plus three files recorded in
`PHASE_D_PRODUCTION_DEPLOYMENT_LEDGER.md` (`d0`, `d1`, `d3`): 14 classified, 52 not. The first
revision then read 0 over 66 while explicitly refusing to claim 0 over the full glob, because every
file numbered `d44` and above was unclassified. **That caveat is now discharged rather than
inherited**: the seven post-`d43` files are in the table, so the reading over the full glob
`scripts/sql/phase_d_*.sql` is 0 of 73 — and 73 is what both `ls` and `git ls-files` return.

**What the second row counts.** Files whose additive DDL creates a table, column, index, trigger, or
a constraint on a pre-existing object, and for which no down script exists at
`scripts/sql/down/<stem>_down.sql`. **26** of the 73 need one; before the first increment none of the
then-23 had one. At 2026-08-20 00:14:36Z `ls scripts/sql/down/*.sql | wc -l` returned 23; re-measured
after `d44`, `d46` and `d49` landed it returns **26**, every one of the 26 names in this table
resolves to a file, no down script is left over, and no down script names a source file that does not
exist. The check is one loop, so re-measure rather than trust the literal:

```sh
# 26 distinct files. A bare grep -c returns 33 — the class name also appears in prose.
sed -n 's/^| `\(phase_d_[a-z0-9_]*\)\.sql`.*EXPLICIT_DOWN_REQUIRED.*/\1/p' \
    docs/phase-d/PHASE_D_ROLLBACK_CLASSIFICATION_D9.md | sort -u | wc -l

for f in $(sed -n 's/^| `\(phase_d_[a-z0-9_]*\)\.sql`.*EXPLICIT_DOWN_REQUIRED.*/\1/p' \
             docs/phase-d/PHASE_D_ROLLBACK_CLASSIFICATION_D9.md | sort -u); do
  [ -f "scripts/sql/down/${f}_down.sql" ] || echo "$f"
done

# and the other direction — a down whose source file is gone
for d in scripts/sql/down/*_down.sql; do
  b=$(basename "$d" _down.sql)
  [ -f "scripts/sql/${b}.sql" ] || echo "orphan: $b"
done
```

**Both rows read 0 before this revision, and both read 0 again after it. The reason is not the same
one, and that is the whole point of correcting them.**

- The **old** 0 on row 1 came from a denominator of eleven. The question "is this migration
  classified?" was asked of the eleven D9 files and of nobody else; 52 files it was never asked of
  scored as satisfied by being outside the table. A number that reaches 0 by shrinking its own
  population is not a measurement.
- The **new** 0 on row 1 comes from a table that names all 73 and assigns each a class — and it is
  arithmetic over a complete list, not evidence that any reversal has been rehearsed. The 66-file
  version of that table still had a shrinking population hiding in it, just a smaller one: it read 0
  by excluding the seven files being written next to it. Naming the exclusion in prose is better than
  hiding it, and closing it is better still.
- The **old** 0 on row 2 was prose: D9 created three tables of its own and the file said dropping them
  is the reversal. True, and it says nothing about `d20`'s columns, `d24`'s trigger, `d9l`'s foreign
  key or `d42`'s constraint.
- The **new** 0 on row 2 means **26** written down scripts under `scripts/sql/down/`, one per file
  that needs one. **Written is not rehearsed.** `scripts/sql/down/README.md` states that no file in
  that directory has been executed, and nothing in this document contradicts it: a down that has
  never run is a guard nobody has watched fire. Two of the 26 would refuse today by design —
  `phase_d_d7b`'s on 18 `MATCHED_ALL_TOKENS` rows and `phase_d_d44`'s on 2 `NOT_DISCRIMINATED` rows,
  both re-measured 2026-08-20 — and a third, `phase_d_d46`'s, would leave
  `fn_phase_d_schema_validate` raising on a missing column. The row is 0 for the existence of a
  reversal, not for the proof of one.

- **Nor is written the same as committed.** `git ls-files scripts/sql/down | wc -l` returns **0**
  against `ls scripts/sql/down | wc -l` **27** on 2026-08-20: the entire directory is unstaged. That
  is a repository gap, not a production one — nothing has ever been applied from it — but a rollback
  that exists on one machine is not a rollback the company has. Stage it by path
  (`git add scripts/sql/down`), never with a broad `git add -A`; this working tree permanently
  carries session debris.

- **A down script can also be wrong in prose while being right in SQL.** Every object count and
  object name asserted in every header under `scripts/sql/down/` was re-read from `pg_class`,
  `pg_attribute`, `pg_constraint`, `pg_index` and `pg_trigger` on 2026-08-20: 26 files, **3
  corrections**, all in comments and none in an executable statement. `d36`'s header said
  `phase_d_dispatch` has 18 columns and it has 17; `d31`'s named a constraint
  (`phase_d_injected_defect_result_status_check`) that has never existed under that name and gave a
  stale value count; `d34`'s value count was stale for the same reason — `d44` widened both. The
  corrections and the method are recorded in `scripts/sql/down/README.md`.

---

## One deployment defect found and corrected in this session

Re-applying `phase_d_d9c` to name a constraint explicitly **silently reverted**
`fn_phase_d_fixture_scenario` and `fn_phase_d_fixture_state` to that file's older bodies, discarding
four later increments.

`apply_sql.mjs` printed `read back and identical to the file` both times and was correct: the
read-back covers the file it was given, not the increments applied after it. Only
`canonical_routines.test.mjs` caught it, as `repository -> production drift: 2`. All eleven files
were re-applied in dependency order and drift returned to **0 in both directions**.

**The rule this leaves behind:** re-applying an earlier file in a chain is not idempotent with
respect to later files that replace the same routine. Re-apply the whole chain, in order, and let
the canonical routine engine — not the apply tool — be the judge.

That rule is what makes `ROUTINE_RESTORE` the weakest class in the table above. Counting
`create or replace function` at column 0, case-insensitively, over all 73 files:
`fn_phase_d_drive_workflow` is replaced by **20**, `fn_phase_d_step_context` by **7**
(`d37`–`d42`, and `d50`), `fn_phase_d_rule_check` by **4** (`d3`, `d4`, `d47`, `d51`) and
`fn_phase_d_rule_applies` by **3** (`d3`, `d16`, `d50`). The count of 6 for
`fn_phase_d_step_context` in the first revision was correct over the 66 it measured and is stale over
73 — `d50` replaces it too. Restoring any of them means re-applying every later file that replaces
the same routine, in order, not just the predecessor.
