# `scripts/sql/down/` — explicit rollback scripts for Phase D

**Nothing runs these.** No npm script, no check under `scripts/checks/`, no GitHub workflow, no
`apply_sql` or `--promote` path references this directory. Every file here is hand-run, by a person
who has read its header, read the row count it destroys, and decided to accept it. That is a
deliberate property, not an omission: an automated rollback of a table holding 1,799 measured
outcomes is a worse failure mode than having no rollback at all.

Each file is named `phase_d_<source-file-stem>_down.sql` and reverses exactly one source file under
`scripts/sql/`. Each drops or reverts objects **by name** — no `cascade` anywhere in the directory —
and ends with a `do $ctl$ … end $ctl$;` block that raises if the change did not take.

## What a "down" covers, and what it cannot

| change kind | has a down? | why |
|---|---|---|
| `CREATE TABLE` / `ADD COLUMN` / `CREATE INDEX` / `CREATE TRIGGER` / `CREATE VIEW` | yes | the object has a name; it can be dropped by that name |
| `ADD CONSTRAINT` widening an earlier one | yes, when the predecessor is in the repo | five of the seven do — `d3`, `d7b`, `d9l`, `d12` and both halves of `d44`; `d20`'s and `d42`'s and `d46`'s constraints were created over columns the same file added, so the drop **is** the revert. See the two tables below |
| `CREATE OR REPLACE FUNCTION` | **no** | the replaced body is not stored anywhere after the replace. Recovering it means finding the previous version of the file in git and re-applying that file, which is a git operation, not a SQL one |
| `DROP FUNCTION` | **no** | same reason, in the other direction |
| `delete from` / `update` | **no** | the prior rows are gone. A down that re-inserted plausible rows would be fabricating data to make a rollback look clean |

## Classification of all Phase D files

The A / B / neither classification below is over the **58 `scripts/sql/phase_d_*.sql` files tracked
at the Phase D remediation recon** (repo HEAD `e59d36b`). Files that landed after that are listed
separately at the end, classified by the same test but measured here rather than taken from the
worklist.

Test used: a comment-stripped scan (`sed 's/--.*$//'`) of each file for `CREATE TABLE`,
`ADD COLUMN`, `ADD CONSTRAINT`, `DROP CONSTRAINT`, `CREATE INDEX`, `CREATE TRIGGER`, `CREATE VIEW`,
`CREATE SEQUENCE`, `CREATE TYPE`, `SET NOT NULL`, `DROP FUNCTION`, cross-checked against
`CREATE OR REPLACE FUNCTION` counts. Object names were then read from `pg_class`, `pg_constraint`,
`pg_index`, `pg_attribute` and `pg_trigger` on `htdblwldjkcgjvmqkbeh` — from the database, not from
the files.

### A — additive DDL: 21 files, 21 down scripts

Every one has a down script in this directory.

| # | source file | what it adds | down script |
|---|---|---|---|
| 1 | `phase_d_d1_handler_registry_and_executor.sql` | tables `phase_d_handler_schema`, `phase_d_handler_binding` | `phase_d_d1_handler_registry_and_executor_down.sql` |
| 2 | `phase_d_d2_business_object_map.sql` | tables `phase_d_business_object_binding`, `phase_d_object_record`; 1 index; 2 triggers; **30** `v_obj_*` views | `phase_d_d2_business_object_map_down.sql` |
| 3 | `phase_d_d3_rule_enforcement.sql` | table `phase_d_rule_enforcement` (+ a constraint restatement that is a no-op) | `phase_d_d3_rule_enforcement_down.sql` |
| 4 | `phase_d_d4_remaining_rules.sql` | table `phase_d_payment_state` (+ 2 `DROP FUNCTION`, see below) | `phase_d_d4_remaining_rules_down.sql` |
| 5 | `phase_d_d5_gate_predicates.sql` | table `phase_d_gate_contract` | `phase_d_d5_gate_predicates_down.sql` |
| 6 | `phase_d_d6_handler_status_is_measured.sql` | column `phase_d_handler_binding.business_write_wired` | `phase_d_d6_handler_status_is_measured_down.sql` |
| 7 | `phase_d_d7_effect_contract_and_business_writes.sql` | tables `phase_d_step_effect`, `phase_d_object_write_map`, `phase_d_effect_ledger`; 2 indexes | `phase_d_d7_effect_contract_and_business_writes_down.sql` |
| 8 | `phase_d_d7b_three_derivation_defects_found_by_the_board.sql` | widens `phase_d_step_effect_resolution_ck` to 5 values | `phase_d_d7b_three_derivation_defects_found_by_the_board_down.sql` |
| 9 | `phase_d_d9_one_hundred_and_fifty_nine_contracts_not_one.sql` | tables `phase_d_handoff_contract`, `phase_d_handoff_acceptance`; 1 index | `phase_d_d9_one_hundred_and_fifty_nine_contracts_not_one_down.sql` |
| 10 | `phase_d_d9c_a_scenario_built_in_the_order_reality_builds_it.sql` | table `phase_d_fixture_stage` | `phase_d_d9c_a_scenario_built_in_the_order_reality_builds_it_down.sql` |
| 11 | `phase_d_d9l_a_phase_d_key_standing_in_front_of_a_phase_b_guard.sql` | `phase_d_handoff_contract_handoff_id_fkey` → `ON DELETE CASCADE` | `phase_d_d9l_a_phase_d_key_standing_in_front_of_a_phase_b_guard_down.sql` |
| 12 | `phase_d_d10_seven_cases_for_every_one_of_the_257_steps.sql` | table `phase_d_step_case_result` | `phase_d_d10_seven_cases_for_every_one_of_the_257_steps_down.sql` |
| 13 | `phase_d_d11_two_hundred_and_seventy_three_events_that_have_never_happened.sql` | table `phase_d_event_reconciliation` | `phase_d_d11_two_hundred_and_seventy_three_events_that_have_never_happened_down.sql` |
| 14 | `phase_d_d12_ready_disabled_was_claiming_a_contract_that_is_not_built.sql` | table `phase_d_external_adapter_field`; narrows `phase_d_step_effect_depth_ck` to 6 values | `phase_d_d12_ready_disabled_was_claiming_a_contract_that_is_not_built_down.sql` |
| 15 | `phase_d_d17_the_fixture_had_a_second_door_and_it_was_http.sql` | table `phase_d_outbound_door` | `phase_d_d17_the_fixture_had_a_second_door_and_it_was_http_down.sql` |
| 16 | `phase_d_d20_created_open_and_asked_the_gate.sql` | 3 columns + 1 constraint + 1 trigger on `phase_d_fixture_stage` | `phase_d_d20_created_open_and_asked_the_gate_down.sql` |
| 17 | `phase_d_d23_a_state_can_require_a_companion_column.sql` | 2 columns on `phase_d_fixture_stage` | `phase_d_d23_a_state_can_require_a_companion_column_down.sql` |
| 18 | `phase_d_d24_a_new_enforcing_table_with_no_truncate_guard.sql` | trigger `z00_kernel_truncate_guard` on `phase_d_fixture_stage` | `phase_d_d24_a_new_enforcing_table_with_no_truncate_guard_down.sql` |
| 19 | `phase_d_d29_a_durable_external_adapter_that_never_sends.sql` | tables `phase_d_external_attempt`, `phase_d_external_message_contract` | `phase_d_d29_a_durable_external_adapter_that_never_sends_down.sql` |
| 20 | `phase_d_d31_seventy_five_injected_defects.sql` | table `phase_d_injected_defect_result` | `phase_d_d31_seventy_five_injected_defects_down.sql` |
| 21 | `phase_d_d34_the_seven_probes_that_were_never_run.sql` | tables `phase_d_section8_probe_result`, `phase_d_section8_defect_map` | `phase_d_d34_the_seven_probes_that_were_never_run_down.sql` |

### B — `CREATE OR REPLACE FUNCTION` only: 32 files, no down scripts

These 32 files contain no DDL at all — only routine bodies. A replaced body has no down (see the
table at the top). Rolling one of these back means checking out the previous version of the file
from git and re-applying it, not running anything from this directory.

`phase_d_d7c_regprocedure_hides_the_schema.sql` ·
`phase_d_d8_workflow_driver.sql` ·
`phase_d_d8b_the_driver_reads_what_each_rule_declares_it_needs.sql` ·
`phase_d_d8c_a_fixture_that_names_a_state_must_name_a_declared_one.sql` ·
`phase_d_d8d_no_transition_is_not_an_undeclared_transition.sql` ·
`phase_d_d8e_a_named_reviewer_needs_a_recorded_verdict.sql` ·
`phase_d_d8f_the_fixture_reads_the_check_constraint.sql` ·
`phase_d_d8g_the_closure_gate_counted_its_own_step_run.sql` ·
`phase_d_d8h_the_file_says_what_the_database_says.sql` ·
`phase_d_d9_a_run_with_no_open_step_is_waiting_for_acceptance.sql` ·
`phase_d_d9b_a_run_in_waiting_handoff_is_not_a_stopped_run.sql` ·
`phase_d_d9d_a_canonical_write_that_emails_a_supplier.sql` ·
`phase_d_d9e_the_lineage_is_quiet_only_because_it_has_no_address.sql` ·
`phase_d_d9f_the_writer_covers_two_of_the_six_fields_its_scorer_reads.sql` ·
`phase_d_d9g_a_generated_fixture_beat_the_real_reference.sql` ·
`phase_d_d9h_the_owner_of_a_customer_scoped_object_is_a_customer.sql` ·
`phase_d_d9i_a_harness_that_seeds_the_row_the_step_creates.sql` ·
`phase_d_d9j_a_run_that_cannot_see_what_it_just_created.sql` ·
`phase_d_d9k_the_kernel_has_no_rejection_door.sql` ·
`phase_d_d13_a_refund_gate_that_fired_before_the_case_was_opened.sql` ·
`phase_d_d14_a_state_the_target_does_not_declare.sql` ·
`phase_d_d15_a_reviewer_keyed_on_the_effect_not_the_step.sql` ·
`phase_d_d16_a_rule_applied_to_the_workflow_that_produces_it.sql` ·
`phase_d_d18_an_upsert_that_could_not_find_the_row_it_wrote.sql` ·
`phase_d_d19_a_generated_payload_rearmed_the_door.sql` ·
`phase_d_d21_the_run_renamed_its_own_inquiry.sql` ·
`phase_d_d22_a_company_scoped_owner_is_still_a_foreign_key.sql` ·
`phase_d_d25_the_key_was_thrown_away_one_statement_later.sql` ·
`phase_d_d26_the_step_that_decides_had_nowhere_to_record_it.sql` ·
`phase_d_d27_move_its_state_said_the_refusal_that_offered_no_way.sql` ·
`phase_d_d28_a_gate_that_refused_the_workflow_for_doing_its_job.sql` ·
`phase_d_d32_the_control_that_left_its_own_rows_behind.sql`

### Neither — 5 files, no down scripts

Zero `CREATE OR REPLACE FUNCTION` and zero DDL. They change data, grants, or nothing at all.

| source file | what it actually does |
|---|---|
| `phase_d_d0_auth_debt_discharged.sql` | `update`s `public.phase_d_preflight_requirement` only — see the warning below |
| `phase_d_d7d_the_lexicon_matched_nouns.sql` | data only; was in no bucket in the pre-recon arithmetic |
| `phase_d_d30_the_twelve_steps_may_say_ready_disabled_again.sql` | data only — it is what set the twelve `EXTERNAL_ADAPTER_CONTRACT_NOT_BUILT` rows back to `EXTERNAL_ADAPTER_READY_DISABLED` |
| `phase_d_d33_the_cleanup_that_only_cleaned_one_table.sql` | one `delete from public.customers` (below); was double-counted in the pre-recon arithmetic |
| `phase_d_d35_a_mention_is_not_a_call.sql` | `revoke` only, on seven SECURITY DEFINER routines |

**21 + 32 + 5 = 58, and the 58 are distinct.** The earlier arithmetic of 21 + 33 + 4 was wrong in
two places at once: `d33` was counted in two buckets and `d7d` in none.

## `public.phase_d_preflight_requirement` is never dropped

No file in this directory drops it, and none should. It is created at
`scripts/sql/phase_c_baseline_row_and_d0_preflight.sql:98` — a Phase **C** file. `phase_d_d0` only
`update`s rows in it. A Phase D rollback that dropped it would take a Phase C object with it.

## The three `DROP FUNCTION`s — recorded, no down

`grep -n -iE '^[[:space:]]*drop function' scripts/sql/phase_d_*.sql` over all 73 files returns
exactly three: the two in `d4` below, and one in `d48`. The heading here used to say "the two, both
in d4", which was true of the 58 files this directory was classified over and is not true now.

`phase_d_d48_a_two_context_probe_cannot_find_a_withheld_authority.sql:36`
`drop function if exists public.fn_phase_d_rule_can_refuse();` is a **return-type** change — `:38`
re-creates the same identity signature with `refusing_context` added to the returned columns. Same
shape as `d4:78`: a signature change written as drop-then-create, not a new object. No down, and none
possible from SQL; reverting it means dropping `d48`'s signature and re-applying `d47`.

The two in `d4`:

| line | statement | what it is | down |
|---|---|---|---|
| `phase_d_d4_remaining_rules.sql:78` | `drop function if exists public.fn_phase_d_reveal_permitted(bigint);` | a **signature change**, not a body edit: `:79` immediately creates `fn_phase_d_reveal_permitted(p_transaction_id text)` | none, and none needed — the `bigint` overload is created by no file under `scripts/sql/`, so the `if exists` was defensive and there is no predecessor to restore |
| `phase_d_d4_remaining_rules.sql:149` | `drop function if exists public.fn_phase_d_rule_check(text, jsonb);` | a body replace written as drop-then-create; `:151` re-creates the same signature | none — a replaced body is not recoverable from SQL |

## The nine `delete from` statements — recorded, no down

Non-additive changes. The rows are gone; a down that re-inserted plausible replacements would be
fabricating data to make a rollback look clean. Located by
`grep -n -iE '^[[:space:]]*delete[[:space:]]+from' scripts/sql/phase_d_*.sql`, which returns exactly
these nine.

| # | file:line | statement |
|---|---|---|
| 1 | `phase_d_d9_one_hundred_and_fifty_nine_contracts_not_one.sql:160` | `delete from public.phase_d_handoff_contract c …` |
| 2 | `phase_d_d10_seven_cases_for_every_one_of_the_257_steps.sql:213` | `delete from public.phase_d_step_case_result;` |
| 3 | `phase_d_d11_two_hundred_and_seventy_three_events_that_have_never_happened.sql:135` | `delete from public.phase_d_event_reconciliation r …` |
| 4 | `phase_d_d17_the_fixture_had_a_second_door_and_it_was_http.sql:127` | `delete from public.phase_d_outbound_door;` |
| 5 | `phase_d_d17_the_fixture_had_a_second_door_and_it_was_http.sql:1023` | `delete from public.phase_d_outbound_door;` |
| 6 | `phase_d_d29_a_durable_external_adapter_that_never_sends.sql:125` | `delete from public.phase_d_external_message_contract;` |
| 7 | `phase_d_d29_a_durable_external_adapter_that_never_sends.sql:474` | `delete from public.phase_d_external_adapter_field;` |
| 8 | `phase_d_d32_the_control_that_left_its_own_rows_behind.sql:31` | `delete from public.phase_d_external_attempt where idempotency_key like 'zz-%';` |
| 9 | `phase_d_d33_the_cleanup_that_only_cleaned_one_table.sql:30` | `delete from public.customers where full_name like 'ZZ DEMO — %' and email is null;` |

Eight of the nine are re-seed deletes inside a Phase D registry table — the file empties its own
table and rewrites it, so the delete is undone by the insert three lines later and the only real
loss would be a hand-edit somebody made to that registry between applies. **Number 9 is different**:
it deletes from `public.customers`, a real business table. It is scoped to the `ZZ DEMO — ` fixture
convention and a null email, and d33's own comment records the table as holding 0 rows before that
session and 1 after. That row is not recoverable from this directory.

## Run order when rolling several files back

Only two orderings are forced, and both are foreign keys, not preference:

1. **Inside d1** — `phase_d_handler_binding` before `phase_d_handler_schema`
   (`input_schema_id` / `output_schema_id` point at it). The d1 down does this itself.
2. **d9c before d2** — `phase_d_fixture_stage.object_id` is
   `-> phase_d_business_object_binding(object_id) ON DELETE RESTRICT`. Running the d2 down first
   fails, correctly. Both files say so in their headers.

Beyond those, several downs are subsumed by a bigger one and become unnecessary rather than wrong:
the d1 down takes the d6 and d42 columns and the d46 columns and constraints with the tables; the
d9c down takes the d20, d23 and d24 additions with the table; the d7 down takes the d7b and d12
constraints with the table; the d9 down takes the d9l key with the table; the d34 and d31 downs each
take one half of the d44 constraint pair with their tables.

## Files that post-date the classification

The A/B/neither table above is frozen at the 58 files tracked at recon. These are **every** Phase D
file present in the tree afterwards, classified here by the same comment-stripped scan.

> **The line that used to stand here said "There is no `d45`", and it has been WRONG since the same
> session wrote one.** `phase_d_d45_a_self_loop_is_a_step_that_hands_to_itself.sql` was applied and
> committed hours after this paragraph was written, and the paragraph was never re-measured. It is
> corrected on 2026-08-20, and `d45` is classified in the second table below with the eight other
> files that post-date this one. A count asserted once and never re-read is the defect this whole
> directory exists to avoid; it is recorded here rather than quietly deleted.

Every object named in a down script below was read out of `pg_class`, `pg_constraint`, `pg_index`,
`pg_attribute` or `pg_trigger` on `htdblwldjkcgjvmqkbeh` before it was named — from the database,
not from the file.

| source file | class | down |
|---|---|---|
| `phase_d_d36_the_kernel_opens_the_step_and_now_runs_it.sql` | A — table `phase_d_dispatch` (17 columns) + 3 indexes + identity sequence, all confirmed live | `phase_d_d36_the_kernel_opens_the_step_and_now_runs_it_down.sql` |
| `phase_d_d37_the_rules_read_real_rows_or_they_refuse.sql` | B — 2 routine bodies, 0 DDL | none needed |
| `phase_d_d38_the_authority_the_kernel_acted_under_is_a_recorded_fact.sql` | B — 1 routine body, 0 DDL | none needed |
| `phase_d_d39_two_ordering_defects_the_first_real_inquiry_found.sql` | B — 1 routine body, 0 DDL | none needed |
| `phase_d_d40_the_arrival_is_known_by_the_inbox_id_already_passed.sql` | B — 1 routine body, 0 DDL | none needed |
| `phase_d_d41_inquiry_owner_is_a_role_not_a_customer.sql` | B — 1 routine body, 0 DDL | none needed |
| `phase_d_d42_route_state_was_my_own_placeholder.sql` | A — 3 columns + 1 constraint on `phase_d_handler_binding`, all confirmed live | `phase_d_d42_route_state_was_my_own_placeholder_down.sql` |
| `phase_d_d43_a_signed_in_caller_may_not_name_the_owner.sql` | neither — 0 routine bodies, 0 DDL; 1 `revoke execute` + 1 `grant execute` on `fn_phase_d_object_read(jsonb)` | none needed — re-grant, and it must be **applied**, never promoted |
| `phase_d_d44_an_endpoint_that_ignores_an_id_has_not_refused.sql` | A — `drop`/`add constraint` on `phase_d_section8_probe_result_verdict_check` and `phase_d_injected_defect_status_check`, both 3 → 4 values; plus 5 `update`s with no down | `phase_d_d44_an_endpoint_that_ignores_an_id_has_not_refused_down.sql` |
| `phase_d_d46_a_contract_that_records_intent_but_checks_presence.sql` | A — 6 `add column` (attnums 10–15) + 6 `set not null` + 2 `add constraint` on `phase_d_handler_schema`, all confirmed live | `phase_d_d46_a_contract_that_records_intent_but_checks_presence_down.sql` |
| `phase_d_d47_nineteen_rules_that_had_never_refused_anything.sql` | B — 2 routine bodies, 0 DDL; 1 `revoke`/`grant` pair on the routine it creates | none needed |
| `phase_d_d48_a_two_context_probe_cannot_find_a_withheld_authority.sql` | B — 1 routine body, 0 DDL. The DDL-shaped hit is `drop function if exists public.fn_phase_d_rule_can_refuse();` at `:36`, a **return-type change** immediately re-created at `:38`, not a new object | none — and none possible: a dropped body is not recoverable from SQL, so reverting means re-applying `d47` and dropping the `d48` signature first |
| `phase_d_d49_a_freeze_with_no_way_to_record_an_amendment.sql` | A — table `phase_c_freeze_amendment` (8 columns) + identity sequence + unique index, all confirmed live | `phase_d_d49_a_freeze_with_no_way_to_record_an_amendment_down.sql` |
| `phase_d_d50_a_rule_that_could_not_fail_made_one_that_could_not_not_fire.sql` | B — 2 routine bodies, 0 DDL; 2 `update`s to `phase_d_rule_enforcement`, an earlier file's table | none needed |
| `phase_d_d51_callable_is_not_answerable_yet.sql` | B — 1 routine body, 0 DDL; 1 `update` to `phase_d_rule_enforcement` | none needed |

**Three more down scripts, so twenty-six in the directory.** `d44`, `d46` and `d49` were in the
working tree while this directory was first written, from concurrent work on another arm of the same
remediation, and their objects had not been confirmed against `htdblwldjkcgjvmqkbeh` — so the first
revision of this README declined to guess at them. They have since been applied and committed, the
object names have been read out of the catalogue, and the three downs are written. `d48` still has
none and never will: its only change is a routine, and a `drop function` has no down.

The `d44` down is the one to read before running: it **refuses** today. Two of the 23 rows in
`public.phase_d_section8_probe_result` carry `NOT_DISCRIMINATED`, which the `d34:32` predecessor
constraint does not admit, so that file raises rather than rewriting two measured rows to make a DDL
statement succeed. Same shape as the `d7b` down, same reason.

## The fourteen files that post-date *that* table too — `d45`, `d52`–`d56`, `e4`–`e11`

Classified 2026-08-20 by the same comment-stripped scan (`sed 's/--.*$//'` then a search for
`CREATE TABLE`, `ADD COLUMN`, `ADD CONSTRAINT`, `DROP CONSTRAINT`, `CREATE INDEX`, `CREATE TRIGGER`,
`CREATE VIEW`, `CREATE SEQUENCE`, `CREATE TYPE`, `SET NOT NULL`, `DROP FUNCTION`). **Not one of the
fourteen creates a new object** — `e7` drops and immediately recreates one, which is a return-type
change, not a new object. `ls scripts/sql/phase_d_*.sql` returns **87** files; 58 at recon + 15 in
the first table + these 14 = 87, and `git ls-files` returns the same 87.

| source file | class | down |
|---|---|---|
| `phase_d_d45_a_self_loop_is_a_step_that_hands_to_itself.sql` | B — 1 routine body, 0 DDL | none needed |
| `phase_d_d52_a_bound_that_is_visible_in_the_value.sql` | B — 1 routine body, 0 DDL; 2 `delete from` on its own probe tables and 1 `revoke`/`grant` pair on the routine it creates | none needed — and the deletes have none, by the rule at the top of this file |
| `phase_d_d53_a_fixture_may_be_opaque_not_the_wrong_type.sql` | B — 1 routine body, 0 DDL | none needed |
| `phase_d_d54_the_driver_defaulted_to_the_one_mode_that_refuses_nothing.sql` | B — 1 routine body, 0 DDL | none needed |
| `phase_d_d55_the_evidence_stated_the_predicates_own_premise.sql` | B — 1 routine body, 0 DDL | none needed |
| `phase_d_d56_the_ledger_named_the_file_the_routine_used_to_live_in.sql` | neither — 0 routine bodies, 0 DDL; 2 `update`s to the deployment ledger | none needed — an `update` has no down |
| `phase_d_e4_the_door_was_never_a_browser.sql` | neither — 0 routine bodies, 0 DDL; **57 `revoke execute`** | **`phase_d_e4_the_door_was_never_a_browser_down.sql`** — a grant IS reversible by name, and this one restores the exact prior shape rather than a uniform one: 55 of the 57 held EXECUTE through PUBLIC, `fn_os_open_access` held an explicit anon + authenticated grant and `fn_goal_attainment` an explicit authenticated grant. Running it re-opens 56 routines to unauthenticated callers and turns `anon_cannot_execute_security_definer.test.mjs` red, which is the point of reading a header first. |
| `phase_d_e5_a_red_that_does_not_say_what_is_holding_it.sql` | B — 2 routine bodies, 0 DDL; 1 `revoke` on the routine it creates | none — and none possible for the replaced body of `fn_phase_d_effect_state`; `drop function public.fn_phase_d_effect_reachability()` alone would break the caller that replaces it |
| `phase_d_e6_the_record_still_claimed_the_door_e4_closed.sql` | neither — 0 routine bodies, 0 DDL; 2 `update`s to `public.phase_c_component` (3 rows) and 1 `insert` into `public.phase_c_freeze_amendment` | none needed. Reverting the amendment row without reverting the three component rows would make `fn_phase_c_freeze_drift()` report drift it cannot explain — the two are one change and must be undone together, by hand, by someone who has re-read both |

| `phase_d_e7_the_classifier_read_the_binding_not_the_branch.sql` | B — 2 routine bodies, plus the only `DROP FUNCTION` in the ten: a return-type change on `fn_phase_d_effect_reachability()`, immediately recreated. The drop discarded E5's ACL, so the file's own `revoke` is load-bearing and its control block asserts the ACL rather than trusting the statement | none — and none possible: a dropped body is not recoverable from SQL. Reverting means re-applying `e5` and dropping the `e7` signature first, **and re-revoking**, because a plain CREATE grants EXECUTE to PUBLIC |
| `phase_d_e8_the_view_handed_back_what_the_table_withheld.sql` | neither — 0 routine bodies, 0 DDL; **32 `revoke`**: SELECT on the 30 `v_obj_*` views and on `phase_d_business_object_binding`, EXECUTE on `fn_phase_d_object_state()` | **`phase_d_e8_the_view_handed_back_what_the_table_withheld_down.sql`** — the prior grants were EXPLICIT role grants, never held through PUBLIC, so the down re-grants to `authenticated` only and never names PUBLIC. Running it re-opens thirty SECURITY DEFINER views over `phase_d_object_record` to any signed-in JWT and re-defeats `d43` |
| `phase_d_e10_a_mechanism_count_read_as_a_refusal_count.sql` | B — 2 routine bodies, 0 DDL | none needed — a replaced body has no down |
| `phase_d_e11_six_keys_it_was_already_holding.sql` | B — 1 routine body, 0 DDL | none needed — a replaced body has no down |
| `phase_d_e9_four_inputs_the_resolver_said_no_table_held.sql` | B — 1 routine body, 0 DDL. `fn_phase_d_step_inputs` gains four resolver branches; every other line is byte-identical to the definition it was spliced from | none needed — a replaced body has no down |

**Twenty-eight down scripts in the directory**, up from 26. Both additions are `GRANT_RESTORE`: `e4`'s
for 57 function grants and `e8`'s for 32 relation and routine grants. A grant is the one change kind
in this directory that IS reversible by name, which is why these two have a down and the nine
routine-body files do not.

## Scope boundary of everything above

Every row count in every header was measured on `htdblwldjkcgjvmqkbeh` — the one Supabase project —
by read-only query, and the six largest are the ones the Phase D remediation worklist recorded under
"Data at risk on a drop": `phase_d_step_case_result` 1,799 · `phase_d_handler_schema` 514 ·
`phase_d_event_reconciliation` 347 · `phase_d_handler_binding` 257 · `phase_d_step_effect` 257 ·
`phase_d_handoff_contract` 159. Counts move. Re-measure before running anything here; a header is a
record of what was true when it was written, not a live reading.

No file in this directory has been executed. They are written, not tested — which for a file whose
whole purpose is to drop production tables is the only responsible state to leave them in. What has
been verified is that every object each one names exists on production under exactly that name.

### The re-verification pass, and the three things it found

Every object count and object name asserted in every header here was re-read from `pg_class`,
`pg_attribute`, `pg_constraint`, `pg_index` and `pg_trigger` on `htdblwldjkcgjvmqkbeh` on
2026-08-20. **26 down scripts, 3 corrections.** All three were in prose, none in an executable
statement — every `drop` and `alter` in the directory already named an object that exists:

- `phase_d_d36_…_down.sql` said `public.phase_d_dispatch` has **18 columns**. `pg_attribute` returns
  **17**, and the `CREATE TABLE` at `phase_d_d36_…sql` declares 17. Corrected to 17.
- `phase_d_d31_…_down.sql` named the constraint
  `phase_d_injected_defect_result_status_check`. No constraint of that name has ever existed:
  `phase_d_d31_…sql:39` names it `phase_d_injected_defect_status_check`, and that is what
  `pg_constraint` holds. The header also said **3 values**; it carries **4** since `d44`. Both
  corrected.
- `phase_d_d34_…_down.sql` said `phase_d_section8_probe_result_verdict_check` carries **3 values**.
  It carries **4** since `d44`. Corrected.

Two headers were also extended rather than corrected: the `d1` down now lists the six `d46` columns
and two `d46` constraints it takes with `phase_d_handler_schema`, and the `d31`/`d34` downs now point
at the `d44` down for anyone who wants to undo only the widening.

Everything else read back exactly as written, including the four largest and most quotable: 1,799 ·
514 · 347 · 159, the 30 `v_obj_*` views against 30 `PHASE_D_OBJECT_VIEW` rows, the 18
`MATCHED_ALL_TOKENS` rows that make the `d7b` down refuse, and the three depth values (224 / 21 / 12)
that let the `d12` down proceed.

---

## Rehearsing a rollback — the only sanctioned way

```
node scripts/phase_c/rehearse_one.mjs scripts/sql/down/<file>_down.sql <assert>.sql
```

It strips any `begin;`/`commit;` wrapper it finds before sending, and it **refuses to report success
unless the run raised**.

**Do not hand-wrap a down script as `begin; <file> rollback;`.** On 24 Aug 2026 the final independent
acceptance audit did exactly that to seven of these files. Four carried their own `begin; … commit;`,
so their COMMIT ran inside the audit's block and the trailing rollback had nothing to undo:
`phase_d_d10`, `phase_d_d18`, `phase_d_d32` and `phase_d_k09` were **deployed** against production by
a rehearsal. Re-measured afterwards, **67 of the 97** down scripts had the same property — the audit
hit four because it sampled seven.

All 98 are transaction-neutral now, and three things keep them that way:

- `scripts/phase_d/build_missing_down_scripts.mjs` no longer emits a wrapper;
- the classification CSV carries a `down_script_transaction_control` column;
- `scripts/checks/phase_d_migrations_are_classified.test.mjs` fails on any `SELF_COMMITTING` value.

**Why removing the wrapper does not cost atomicity.** Every transport in this repository sends a file
as ONE simple-query batch to the management API, and a multi-statement batch with no explicit BEGIN
is a single implicit transaction in Postgres. The file is still all-or-nothing; it is now also
rehearsable.

A file that genuinely **cannot** run inside a transaction — `CREATE INDEX CONCURRENTLY`, `VACUUM`,
`ALTER TYPE … ADD VALUE` — is classified `NON_TRANSACTIONAL_BY_REQUIREMENT` and must say so in its
own header. Measured 24 Aug 2026: there are none.
