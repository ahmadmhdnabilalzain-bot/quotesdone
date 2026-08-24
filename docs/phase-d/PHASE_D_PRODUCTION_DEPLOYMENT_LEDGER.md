# Phase D — production deployment ledger

Required deliverable 14 of 15. Every Phase D write to `htdblwldjkcgjvmqkbeh`, in order, with the
file that produced it, how it was verified, and how to reverse it.

There is **one** project. Staging `pglpqrhvozwepymcuunn` was deleted on 15 Aug 2026 at the
founder's instruction and nothing here reads it.

## How each increment was applied

Every increment followed `PHASE_D_PRODUCTION_DIRECT_PROTOCOL.md`: read-only inspection → file
written and committed → dry run → rehearsal → apply → **read the definition back out of the
database and compare it to the file** → verify by execution.

`node scripts/apply_sql.mjs <file>` with no flag is a **dry run**. `--apply --ddl` writes and then
reads back; it prints `read back and identical to the file` only when the live definition matches
the committed bytes, so the exit code means something.

## What "deployed" can and cannot be read back

**Production-direct applies leave no row in `supabase_migrations.schema_migrations`.** Measured
2026-08-20 00:00:41Z: `select max(version) from supabase_migrations.schema_migrations` returns
`20260811081746`, and the count of rows at or after `20260817` is **0**. Nothing in the database
records *when* any file in this ledger was applied.

So dates in this ledger come from the repository — commit date, and file mtime for a file applied
before it was committed — and the database can only confirm the **present** state. The read-back
column below is exactly that: does the object this file creates exist in production now.

Two queries produced every read-back value, both run 2026-08-20 00:00:41Z:

```sql
select c.relkind, c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relname like 'phase\_d\_%';

select p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and (p.proname like 'fn\_phase\_d\_%' or p.proname in ('fn_kernel_open_step','fn_kernel_workflow_start'));
```

Row counts are `count(*)`, **not** `reltuples` — a third of these tables have never been analysed and
report `reltuples = -1`, so the planner estimate would read some of them as unknown and others as
zero without distinguishing the two. Constraint and ACL read-backs use `pg_get_constraintdef(oid)`
and `pg_proc.proacl` and are quoted verbatim where they appear.

One measurement covers the whole estate: of the 24 `phase_d_*` base tables live in `public`, **24
have `relrowsecurity = true` and the total policy count across all of them is 0**. RLS on these
tables is defence in depth behind a `service_role`-only grant, not the control.

**Existence is not parity.** For a file whose only content is `create or replace function`, the
routine existing proves nothing about whose body is live — a later file in the same chain may have
replaced it. Repository↔production parity is measured by the canonical routine engine
(`scripts/checks/canonical_routines.test.mjs`), not by this ledger, and no hash appears in this
document that was not computed by a query printed in it.

## The five pull requests

| PR | branch | merge commit | merged (UTC) | Phase D files |
|---|---|---|---|---|
| [#446](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/446) | `feat/phase-d-d1-d3-handler-registry-and-rules` | `bc20365` | 2026-08-18 15:20:06 | d0, d1, d3 |
| [#447](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/447) | `feat/phase-d-d2-business-objects` | `e896ef5` | 2026-08-18 16:31:44 | d2, d4, d5, d6 |
| [#448](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/448) | `feat/phase-d-d7-every-handler-produces-an-effect` | `38bcc17` | 2026-08-18 18:59:10 | d7, d7b, d7c, d7d, d8, d8b–d8h |
| [#449](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/449) | `feat/phase-d-d9-handoff-acceptance` | `a977ed2` | 2026-08-19 11:55:41 | d9_a_run_with_no_open_step |
| [#450](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/450) | `feat/phase-d-d9-the-handoff-is-159-contracts` | `e59d36b` | 2026-08-19 11:55:39 | d9(159 contracts) … d35, and d9l |

Three details that matter when reading the "merge commit" column:

- **#446 and #447 were squashed onto `main`.** `bc20365` and `e896ef5` are ordinary commits with a
  single parent; there is no merge commit distinct from the file's introducing commit.
- **#449's `a977ed2` is not a merge commit.** `git log -1 --format=%p a977ed2` returns one parent,
  `13e42ff`. It is the tip of the #449 branch. #450's branch was built **on top of** #449's
  (`git merge-base --is-ancestor a977ed2 fd8c64f` succeeds), so #449's two commits reached `main`
  inside `e59d36b`, and GitHub then recorded the branch tip as #449's merge commit. That is why
  #449 shows a *later* `mergedAt` (11:55:41Z) than #450 (11:55:39Z) while its commits are *older*.
- **d36–d51 are on no PR yet.** They are five commits on `feat/phase-d-remediation-to-acceptance` —
  `7090016`, `9dd1927`, `f9415ab`, `5c7152a`, `a7a37a8` — and every one of them is tracked. The
  earlier statement here that `phase_d_d43_…sql` was applied and untracked was true when written and
  is not true now: `git log --diff-filter=A -- scripts/sql/phase_d_d43_…sql` returns `9dd1927`,
  2026-08-20T04:02:49+04:00. See the last two sections.

## Every Phase D file, with its commit, PR and production read-back

Scope: **all 87** files matching `scripts/sql/phase_d_*.sql`. The table first covered `d0..d43`, 66
files, while concurrent increments of the same session were still adding files numbered `d44` and
above — `ls scripts/sql/phase_d_*.sql | wc -l` returned 67 at 00:00:04Z and 71 at 00:10:34Z. Seven
were appended then (`d44`, `d46`, `d47`, `d48`, `d49`, `d50`, `d51`) and **fourteen more on 2026-08-20**:
`d45`, `d52`–`d56`, `e4`–`e11`. 66 + 7 + 14 = **87**, which is what both
`ls` and `git ls-files scripts/sql/phase_d_*.sql` return.

> **This paragraph used to say "There is no `d45` — the numbering skips it", and it was wrong within
> hours of being written.** `phase_d_d45_a_self_loop_is_a_step_that_hands_to_itself.sql` was applied
> and committed later in the same session and the sentence was never re-measured; the identical claim
> in `scripts/sql/down/README.md` was wrong for the same reason. Corrected 2026-08-20 by counting
> again rather than by deleting the sentence — a number asserted once and never re-read is exactly
> what this ledger exists to catch, and the correction is more useful on the record than a clean file.

Rollback class for each of the 87 is in `PHASE_D_ROLLBACK_CLASSIFICATION_D9.md` and, for the fourteen
that post-date its main table, in `scripts/sql/down/README.md`.

Read-back key: a table name with a number is `count(*)`; `routine present` means the identity
signature was returned by the second query above.

| file (`phase_d_…sql`) | introducing commit | PR | merge commit | production read-back, 2026-08-20 00:00:41Z |
|---|---|---|---|---|
| `d0_auth_debt_discharged` | `bc20365` | #446 | `bc20365` (squash) | `phase_d_preflight_requirement` 2 rows — table created by Phase C, this file only `update`s it |
| `d1_handler_registry_and_executor` | `bc20365` | #446 | `bc20365` (squash) | `phase_d_handler_schema` 514, `phase_d_handler_binding` 257; `fn_phase_d_slug`, `_schema_validate`, `_handler_execute`, `_handler_state` present |
| `d3_rule_enforcement` | `bc20365` | #446 | `bc20365` (squash) | `phase_d_rule_enforcement` 54; `fn_phase_d_rule_applies`, `_rule_check`, `_rule_state` present |
| `d2_business_object_map` | `e896ef5` | #447 | `e896ef5` (squash) | `phase_d_business_object_binding` 56, `phase_d_object_record` 0, 30 `v_obj_*` views; triggers `a00_phase_d_object_policy_guard` and `z00_kernel_truncate_guard` enabled on `phase_d_object_record` |
| `d4_remaining_rules` | `e896ef5` | #447 | `e896ef5` (squash) | `phase_d_payment_state` 6; `fn_phase_d_reveal_permitted(p_transaction_id text)` present — the `bigint` signature this file dropped is **not** present |
| `d5_gate_predicates` | `e896ef5` | #447 | `e896ef5` (squash) | `phase_d_gate_contract` 32; `fn_phase_d_gate_applies`, `_gate_evaluate`, `_gate_state` present |
| `d6_handler_status_is_measured` | `e896ef5` | #447 | `e896ef5` (squash) | column `phase_d_handler_binding.business_write_wired boolean` present |
| `d7_effect_contract_and_business_writes` | `d813e2c` | #448 | `38bcc17` | `phase_d_step_effect` 257, `phase_d_object_write_map` 22, `phase_d_effect_ledger` 0 |
| `d7b_three_derivation_defects_found_by_the_board` | `d813e2c` | #448 | `38bcc17` | `phase_d_step_effect_resolution_ck` = `CHECK (object_resolution = ANY (ARRAY['MATCHED_STEP_TEXT','MATCHED_ALL_TOKENS','SOLE_OBJECT_OF_WORKFLOW','WORKFLOW_PRIMARY_OBJECT','NO_DOMAIN_OBJECT']))` — 5 values |
| `d7c_regprocedure_hides_the_schema` | `d813e2c` | #448 | `38bcc17` | `fn_phase_d_effect_state()` present |
| `d7d_the_lexicon_matched_nouns` | `d813e2c` | #448 | `38bcc17` | rows only — no object of its own |
| `d8_workflow_driver` | `d813e2c` | #448 | `38bcc17` | `fn_phase_d_drive_workflow(jsonb)`, `fn_phase_d_fixture_value(text,text,text)` present |
| `d8b_the_driver_reads_what_each_rule_declares_it_needs` | `d813e2c` | #448 | `38bcc17` | `fn_phase_d_drive_workflow(jsonb)` present |
| `d8c_a_fixture_that_names_a_state_must_name_a_declared_one` | `d813e2c` | #448 | `38bcc17` | `fn_phase_d_fixture_context(bigint,text)` present |
| `d8d_no_transition_is_not_an_undeclared_transition` | `d813e2c` | #448 | `38bcc17` | `fn_phase_d_gate_evaluate(text,jsonb)` present |
| `d8e_a_named_reviewer_needs_a_recorded_verdict` | `0937fc1` | #448 | `38bcc17` | `fn_phase_d_drive_workflow(jsonb)` present |
| `d8f_the_fixture_reads_the_check_constraint` | `0937fc1` | #448 | `38bcc17` | `fn_phase_d_fixture_for_column(text,text,text)` present |
| `d8g_the_closure_gate_counted_its_own_step_run` | `0937fc1` | #448 | `38bcc17` | `fn_phase_d_gate_evaluate(text,jsonb)` present |
| `d8h_the_file_says_what_the_database_says` | `279e1ac` | #448 | `38bcc17` | `fn_phase_d_handler_execute(jsonb)` present |
| `d9_a_run_with_no_open_step_is_waiting_for_acceptance` | `13e42ff` | #449 | via `e59d36b` | `fn_phase_d_drive_workflow(jsonb)` present |
| `d9_one_hundred_and_fifty_nine_contracts_not_one` | `cca51ce` | #450 | `e59d36b` | `phase_d_handoff_contract` 159, `phase_d_handoff_acceptance` 0; `fn_phase_d_handoff_packet_valid`, `_handoff_accept`, `_handoff_reject`, `_handoff_cancel`, `_handoff_state` present |
| `d9b_a_run_in_waiting_handoff_is_not_a_stopped_run` | `cca51ce` | #450 | `e59d36b` | `fn_phase_d_drive_workflow(jsonb)` present |
| `d9c_a_scenario_built_in_the_order_reality_builds_it` | `cca51ce` | #450 | `e59d36b` | `phase_d_fixture_stage` 25; `fn_phase_d_fixture_scenario`, `_fixture_state`, `_fixture_residue` present |
| `d9d_a_canonical_write_that_emails_a_supplier` | `cca51ce` | #450 | `e59d36b` | `fn_phase_d_outbound_exposure()` present; `phase_d_object_write_map` 22 rows |
| `d9e_the_lineage_is_quiet_only_because_it_has_no_address` | `cca51ce` | #450 | `e59d36b` | `fn_phase_d_fixture_scenario(jsonb)` present |
| `d9f_the_writer_covers_two_of_the_six_fields_its_scorer_reads` | `cca51ce` | #450 | `e59d36b` | `fn_phase_d_fixture_inquiry_payload(text)` present |
| `d9g_a_generated_fixture_beat_the_real_reference` | `cca51ce` | #450 | `e59d36b` | `fn_phase_d_drive_workflow(jsonb)` present |
| `d9h_the_owner_of_a_customer_scoped_object_is_a_customer` | `cca51ce` | #450 | `e59d36b` | `fn_phase_d_drive_workflow(jsonb)` present |
| `d9i_a_harness_that_seeds_the_row_the_step_creates` | `cca51ce` | #450 | `e59d36b` | `fn_phase_d_drive_workflow(jsonb)` present |
| `d9j_a_run_that_cannot_see_what_it_just_created` | `cca51ce` | #450 | `e59d36b` | `fn_phase_d_drive_workflow(jsonb)` present |
| `d9k_the_kernel_has_no_rejection_door` | `cca51ce` | #450 | `e59d36b` | `fn_phase_d_handoff_reject`, `_handoff_cancel`, `_handoff_state`, `_fixture_state` present |
| `d9l_a_phase_d_key_standing_in_front_of_a_phase_b_guard` | `a8dfb84` | #450 | `e59d36b` | `phase_d_handoff_contract_handoff_id_fkey` = `FOREIGN KEY (handoff_id) REFERENCES phase_b_handoff(handoff_id) ON DELETE CASCADE` |
| `d10_seven_cases_for_every_one_of_the_257_steps` | `54b2549` | #450 | `e59d36b` | `phase_d_step_case_result` **1,799**; `fn_phase_d_step_cases`, `_run_step_cases`, `_case_state` present |
| `d11_two_hundred_and_seventy_three_events_that_have_never_happened` | `73c73fa` | #450 | `e59d36b` | `phase_d_event_reconciliation` 347; `fn_phase_d_event_state()` present |
| `d12_ready_disabled_was_claiming_a_contract_that_is_not_built` | `c8e789c` | #450 | `e59d36b` | `phase_d_external_adapter_field` 14; `phase_d_step_effect_depth_ck` now 6 values |
| `d13_a_refund_gate_that_fired_before_the_case_was_opened` | `a86d033` | #450 | `e59d36b` | `fn_phase_d_gate_applies(text,text)` present |
| `d14_a_state_the_target_does_not_declare` | `a86d033` | #450 | `e59d36b` | `fn_phase_d_drive_workflow(jsonb)` present |
| `d15_a_reviewer_keyed_on_the_effect_not_the_step` | `a86d033` | #450 | `e59d36b` | `fn_phase_d_drive_workflow(jsonb)` present |
| `d16_a_rule_applied_to_the_workflow_that_produces_it` | `669d3cb` | #450 | `e59d36b` | `fn_phase_d_rule_applies(text,text)` present; the 25th `phase_d_fixture_stage` row is this file's |
| `d17_the_fixture_had_a_second_door_and_it_was_http` | `1a23d9c` | #450 | `e59d36b` | `phase_d_outbound_door` 4; `fn_phase_d_outbound_state()` present |
| `d18_an_upsert_that_could_not_find_the_row_it_wrote` | `4b93ac7` | #450 | `e59d36b` | `fn_phase_d_object_identity_state()` present |
| `d19_a_generated_payload_rearmed_the_door` | `4b93ac7` | #450 | `e59d36b` | `fn_phase_d_object_write(jsonb)` present |
| `d20_created_open_and_asked_the_gate` | `5300b6d` | #450 | `e59d36b` | columns `working_state`, `working_state_evidence`, `contributes_kind` present on `phase_d_fixture_stage`; `phase_d_fixture_stage_contributes_kind_check` = `CHECK (contributes_kind = ANY (ARRAY['RESULT_KEY','STATE']))`; trigger `a00_phase_d_stage_payment_state` enabled |
| `d21_the_run_renamed_its_own_inquiry` | `5300b6d` | #450 | `e59d36b` | `fn_phase_d_reference_fold_state()` present |
| `d22_a_company_scoped_owner_is_still_a_foreign_key` | `8ba4cd6` | #450 | `e59d36b` | `fn_phase_d_drive_workflow(jsonb)`, `_fixture_scenario(jsonb)` present |
| `d23_a_state_can_require_a_companion_column` | `8ba4cd6` | #450 | `e59d36b` | columns `working_payload jsonb`, `working_payload_evidence text` present on `phase_d_fixture_stage` |
| `d24_a_new_enforcing_table_with_no_truncate_guard` | `35ca71d` | #450 | `e59d36b` | trigger `z00_kernel_truncate_guard` enabled on `phase_d_fixture_stage` |
| `d25_the_key_was_thrown_away_one_statement_later` | `97b716f` | #450 | `e59d36b` | `fn_phase_d_drive_workflow(jsonb)` present |
| `d26_the_step_that_decides_had_nowhere_to_record_it` | `9c4e4e0` | #450 | `e59d36b` | `fn_phase_d_drive_workflow(jsonb)` present |
| `d27_move_its_state_said_the_refusal_that_offered_no_way` | `9c4e4e0` | #450 | `e59d36b` | `fn_phase_d_object_write(jsonb)` present |
| `d28_a_gate_that_refused_the_workflow_for_doing_its_job` | `9c4e4e0` | #450 | `e59d36b` | `fn_phase_d_gate_applies(text,text)` present |
| `d29_a_durable_external_adapter_that_never_sends` | `8b44c62` | #450 | `e59d36b` | `phase_d_external_attempt` 0, `phase_d_external_message_contract` 4; `fn_phase_d_external_deliver`, `_external_state`, `_external_field_state`, `_run_external_cases` present |
| `d30_the_twelve_steps_may_say_ready_disabled_again` | `8b44c62` | #450 | `e59d36b` | rows only — 12 of the 257 `phase_d_step_effect` rows carry `EXTERNAL_ADAPTER_READY_DISABLED` |
| `d31_seventy_five_injected_defects` | `09cb4a5` | #450 | `e59d36b` | `phase_d_injected_defect_result` **0 rows**; `fn_phase_d_run_injected_defects()` present |
| `d32_the_control_that_left_its_own_rows_behind` | `09cb4a5` | #450 | `e59d36b` | `fn_phase_d_external_residue()` present |
| `d33_the_cleanup_that_only_cleaned_one_table` | `d8bef8e` | #450 | `e59d36b` | not read back here — the file deletes fixture rows from `public.customers`; a `count(*)` today cannot distinguish a successful purge from a table that was always empty |
| `d34_the_seven_probes_that_were_never_run` | `b2f43e4` | #450 | `e59d36b` | `phase_d_section8_probe_result` 23, `phase_d_section8_defect_map` 11; `fn_phase_d_injected_defect_report()` present |
| `d35_a_mention_is_not_a_call` | `b2f43e4` | #450 | `e59d36b` | all 7 revoked routines read back `postgres=X/postgres service_role=X/postgres` — no `anon`, no `authenticated`, no bare PUBLIC |
| `d36_the_kernel_opens_the_step_and_now_runs_it` | `7090016` | none yet | unmerged | `phase_d_dispatch` **0 rows**, RLS on, 0 policies, sequence `phase_d_dispatch_dispatch_id_seq` present; `fn_phase_d_step_inputs`, `_dispatch_step`, `_dispatch_state`, and the replaced `fn_kernel_open_step(jsonb)`, `fn_kernel_workflow_start(jsonb)` present |
| `d37_the_rules_read_real_rows_or_they_refuse` | `7090016` | none yet | unmerged | `fn_phase_d_step_context(bigint)` present, SECURITY DEFINER |
| `d38_the_authority_the_kernel_acted_under_is_a_recorded_fact` | `7090016` | none yet | unmerged | `fn_phase_d_step_context(bigint)` present |
| `d39_two_ordering_defects_the_first_real_inquiry_found` | `7090016` | none yet | unmerged | `fn_phase_d_step_context(bigint)` present |
| `d40_the_arrival_is_known_by_the_inbox_id_already_passed` | `7090016` | none yet | unmerged | `fn_phase_d_step_context(bigint)` present |
| `d41_inquiry_owner_is_a_role_not_a_customer` | `7090016` | none yet | unmerged | `fn_phase_d_step_context(bigint)` present |
| `d42_route_state_was_my_own_placeholder` | `7090016` | none yet | unmerged | column `phase_d_handler_binding.application_connection text` present; constraint `phase_d_handler_binding_app_conn_ck` present; `fn_phase_d_application_connection_measure()`, `_actual_caller_measure()` present |
| `d43_a_signed_in_caller_may_not_name_the_owner` | `9dd1927` | none yet | unmerged | `fn_phase_d_object_read(jsonb)` ACL = `postgres=X/postgres service_role=X/postgres` — the `authenticated` grant is gone and no bare PUBLIC entry survives |
| `d44_an_endpoint_that_ignores_an_id_has_not_refused` | `a7a37a8` | none yet | unmerged | `phase_d_section8_probe_result_verdict_check` and `phase_d_injected_defect_status_check` both = `CHECK (… = ANY (ARRAY['REFUSED_AS_REQUIRED','NOT_REFUSED','NOT_RUN','NOT_DISCRIMINATED']))` — 4 values each, up from 3; `phase_d_section8_probe_result` 23 rows = 21 `REFUSED_AS_REQUIRED` + **2 `NOT_DISCRIMINATED`**, the two rows the file reclassified |
| `d46_a_contract_that_records_intent_but_checks_presence` | `9dd1927` | none yet | unmerged | six columns present on `phase_d_handler_schema` at attnums 10–15 — `schema_version`, `field_types`, `enum_domains`, `optional_keys`, `additional_properties`, `type_source`; constraints `phase_d_handler_schema_field_types_ck` and `_version_ck` present; `type_source` non-null on all **514** rows, two distinct sentences at 257 each; `fn_phase_d_schema_validate(text,jsonb)`, `fn_phase_d_contract_state()` present |
| `d47_nineteen_rules_that_had_never_refused_anything` | `9dd1927` | none yet | unmerged | `fn_phase_d_rule_check(text,jsonb)`, `fn_phase_d_rule_can_refuse()` present; ACL on `fn_phase_d_rule_can_refuse` = `postgres=X/postgres service_role=X/postgres` |
| `d48_a_two_context_probe_cannot_find_a_withheld_authority` | `9dd1927` | none yet | unmerged | `fn_phase_d_rule_can_refuse()` present, exactly one row in `pg_proc` — the `drop function` at `d48:36` is a **return-type** change, not a new overload, so the identity signature is unchanged and existence alone would prove nothing. The live body is `d48`'s: `pg_proc.prosrc` contains `refusing_context`, a return column only `d48` declares |
| `d49_a_freeze_with_no_way_to_record_an_amendment` | `f9415ab` | none yet | unmerged | `phase_c_freeze_amendment` **2 rows**, RLS on, 0 policies, sequence `phase_c_freeze_amendment_amendment_id_seq` and unique index `phase_c_freeze_amendment_once` present; `fn_phase_c_freeze_drift()` present and its body reads the new table |
| `d50_a_rule_that_could_not_fail_made_one_that_could_not_not_fire` | `5c7152a` | none yet | unmerged | `fn_phase_d_rule_applies(text,text)`, `fn_phase_d_step_context(bigint)` present; `phase_d_rule_enforcement` 54 rows, **54 `ENFORCED` / 0 `OUTSTANDING`** |
| `d51_callable_is_not_answerable_yet` | `5c7152a` | none yet | unmerged | `fn_phase_d_rule_check(text,jsonb)` present; `phase_d_rule_enforcement` still 54/54 `ENFORCED` |

**Nine more rows, added 2026-08-20 03:1xZ.** The table above stopped at `d51` and the paragraph
above it said "there is no `d45`" — `d45` had been written and applied hours later, and `d52`–`d56`
after it, and neither claim was re-measured. All read-backs in these nine rows were taken at
**2026-08-20 03:14Z**, not at the 00:00:41Z of the rows above; the timestamps are different on
purpose rather than restated as one.

| file (`phase_d_…sql`) | introducing commit | PR | merge commit | production read-back, 2026-08-20 03:14Z |
|---|---|---|---|---|
| `d45_a_self_loop_is_a_step_that_hands_to_itself` | `dd3dd23` | [#451](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/451) | `dd3dd23` (squash) | `fn_phase_d_event_state()` present |
| `d52_a_bound_that_is_visible_in_the_value` | `dd3dd23` | [#451](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/451) | `dd3dd23` (squash) | `fn_phase_d_bounded(text,int)` present |
| `d53_a_fixture_may_be_opaque_not_the_wrong_type` | `dd3dd23` | [#451](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/451) | `dd3dd23` (squash) | `fn_phase_d_fixture_context(...)` present |
| `d54_the_driver_defaulted_to_the_one_mode_that_refuses_nothing` | `dd3dd23` | [#451](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/451) | `dd3dd23` (squash) | `fn_phase_d_drive_workflow(jsonb)` present, and its `execution_context` default reads `production` |
| `d55_the_evidence_stated_the_predicates_own_premise` | `dd3dd23` | [#451](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/451) | `dd3dd23` (squash) | `fn_os_portals_gates()` present |
| `d56_the_ledger_named_the_file_the_routine_used_to_live_in` | `dd3dd23` | [#451](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/451) | `dd3dd23` (squash) | `kernel_routine_ownership` 1,225 rows — two `update`s, no DDL |
| `e4_the_door_was_never_a_browser` | `691d432` | [#452](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/452) | unmerged | **0** SECURITY DEFINER routines in `public` are anon-executable, **2** authenticated-executable (`fn_customer_documents`, `fn_customer_document_refs`), of 791. Verified as the roles themselves: `set local role anon` → `insufficient_privilege`; `service_role` still executes |
| `e5_a_red_that_does_not_say_what_is_holding_it` | `691d432` | [#452](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/452) | unmerged | `fn_phase_d_effect_reachability()` present and revoked from `public, anon, authenticated`; `fn_phase_d_effect_state()` returns the three new disclosure rows (21 / 51 / 185) beside an unchanged `steps_with_no_effect_ever_produced = 257` |
| `e6_the_record_still_claimed_the_door_e4_closed` | `691d432` | [#452](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/452) | unmerged | 3 `phase_c_component` rows on `external_entry = 'no'`; `phase_c_freeze_amendment` **3** rows; `fn_phase_c_freeze_drift()` 0 of 25 drifted |
| `e7_the_classifier_read_the_binding_not_the_branch` | `691d432`+ | [#452](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/452) | unmerged | `fn_phase_d_effect_reachability()` **dropped and recreated** for a changed OUT row type, and re-revoked — `proacl` reads `postgres=X/postgres \| service_role=X/postgres`, so `anon` and `authenticated` are false. `reachability_class_distribution` reads `REFUSAL_IS_THE_DECLARED_EFFECT=21 WRITES_A_ZERO_RESIDUE_TABLE=14 WRITES_AN_EXISTING_TABLE_NOT_UNDER_THE_RULE=78 WRITES_ONLY_THE_PHASE_D_LEDGER=70 WRITES_ONLY_THE_PHASE_D_OBJECT_STORE=74`, summing to 257, with `steps_whose_written_relation_does_not_resolve` 0 |

| `e8_the_view_handed_back_what_the_table_withheld` | `691d432`+ | [#452](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/452) | unmerged | **0 of the 30 `v_obj_*` views** are selectable by anon or authenticated, and **30 of 30** still by `service_role`. `phase_d_business_object_binding` and `fn_phase_d_object_state()` likewise closed to client roles. Probed as the roles: `authenticated` gets `insufficient_privilege` on `v_obj_financial_close` and on the binding table; `service_role` reads the view (0 rows). Estate-wide after it: anon can SELECT **2 of 574** relations in `public` and **0** views; authenticated **0** views |

| `e9_four_inputs_the_resolver_said_no_table_held` | `691d432`+ | [#452](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/452) | unmerged | `fn_phase_d_step_inputs(bigint)` present, md5 `2a628d112a9f0f6fd44d4d9a0697c9b1`. Driving W01 in `production` inside an aborted transaction: before, **6 of 6** dispatched steps `INPUTS_UNRESOLVED`; after, **S04, S05 and S06 resolve** and are `REFUSED` by a named rule or gate — `BR-003 requires [founder_authority_ref]`, `GATE-006 (Valid workflow transition) requires [to_state]`. S01–S03 stay unresolved on `founder_instruction`/`founder_mandate`, which need a real founder command the driver does not create. Residue 0, business tables 0/0/0/0, runs unchanged at 18 |

| `e10_a_mechanism_count_read_as_a_refusal_count` | `691d432`+ | [#452](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/452) | unmerged | `fn_phase_d_rule_state()` md5 `3e1f72815596ad402b3cb4720e0970eb` and `fn_phase_d_handler_state()` md5 `04367b527b4b35adbd482743195a84f9`. Rule board now carries `rules_whose_predicate_can_actually_refuse` **40 of 54**, plus 11 delegated / 2 provider-held / 1 at the executor, and `every_registered_rule_carries_a_refusal_class` **54 = 54**. Handler board carries `handlers_that_have_actually_produced_an_effect` **0 of 257** beside the unchanged green `handlers_not_writing_a_business_object` **0**. Read back by listing the rows, not by the apply tool: a first apply emitted one check twice and lost another, and the board is what showed it |

| `e11_six_keys_it_was_already_holding` | `691d432`+ | [#452](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/452) | unmerged | `fn_phase_d_step_context(bigint)` md5 `f860aa8f9baecf1f938a79d2d1511fe0`. Driving W01 in `production` in an aborted transaction, the unresolved set on the three refused steps went from eight keys to four; `run_id`, `actor_role_id`, `step_id` and `step_run_id` are gone. **0 EXECUTED before and after** — the remaining four are real absences, not resolver gaps. Residue 0 |

`e8` is the finding this session did not go looking for. `d2:722` revokes `public.phase_d_object_record`
from `public, anon, authenticated` with the comment *"The store is written only through the service"* —
and `d2:474` grants SELECT on each of the thirty views **over that same store** to
`service_role, authenticated`. A view without `security_invoker = true` reads as its owner, so the
view returned exactly the rows the table revoke withheld, past an RLS policy set that is deny-all,
through PostgREST, to any signed-in JWT. It also defeated `d43`, which had revoked the *function*
door to the same data for precisely that reason. Nothing leaked because the store holds 0 rows —
which is the D35 finding word for word, not an argument for leaving it.

`e7` is the one file here that **drops** a routine, and it is the reason the grant needed re-taking:
a plain `CREATE` grants EXECUTE to PUBLIC and only `CREATE OR REPLACE` preserves an ACL, so `e5`'s
revoke did not survive `e7`. Its control block asserts the ACL rather than trusting the statement —
in the same session that closed 57 such grants, a drop-and-recreate reopening one would have been
the whole of E4 undone by the increment that came after it.

Seven rows read `fn_phase_d_step_context(bigint) present` and say nothing else, because they are the
same routine replaced seven times — `d37`–`d42`, and `d50`. Measured over all 73 files by counting
`create or replace function public.fn_phase_d_step_context` at column 0; the earlier figure of six
was correct over the 66 files this ledger then covered. The read-back tells you it is live; it does
not tell you whose body is live. See
"Existence is not parity" above. `fn_phase_d_rule_check` is in the same position — `d4`, `d47` and
`d51` all replace it — and `d48`'s row is the exception that shows what a real parity read-back looks
like: it names a string only the newer body contains.

**The 20-rule ratchet is spent.** The `d3` entry below records `fn_phase_d_rule_state()` as 3/4, the
fourth red by disclosure with 20 rules `OUTSTANDING`, and a ratchet entry in
`scripts/checks/kernel-boards.json` carrying it. Measured 2026-08-20:
`select status, count(*) from public.phase_d_rule_enforcement group by 1` returns
`ENFORCED 54`, `OUTSTANDING 0`. `d47`, `d50` and `d51` closed them. That ratchet entry says to delete
itself at 0; deleting it is not this ledger's job, and it is not deleted here.

## The first three increments, in detail

These three predate the per-file table and keep their original entries.

### 1. `scripts/sql/phase_d_d1_handler_registry_and_executor.sql`

| | |
|---|---|
| commit | `fb86840`, corrected in `ef1a9db`; squashed to `bc20365` |
| routines | `fn_phase_d_slug`, `fn_phase_d_schema_validate`, `fn_phase_d_handler_execute`, `fn_phase_d_handler_state` |
| tables | `phase_d_handler_schema` (514 rows), `phase_d_handler_binding` (257 rows) |
| schema shape | `51d663a1e17cff35…` → `a614b87656ac929e…` |
| dry run | guards passed; 4 routines defined, 5 called and all present |
| rehearsal | read-only derivation on production before writing: 257 steps → 257 input schemas, 0 with no parseable input, keys 1–4 per step, 21 capability-dependent, 0 duplicate handler ids |
| verified | read back identical; board `fn_phase_d_handler_state()` 6/6; **executed** end to end in an aborted transaction (W01 run 5151, step run 5195) |
| rollback | `scripts/sql/down/phase_d_d1_handler_registry_and_executor_down.sql`. Order matters: `drop table public.phase_d_handler_binding;` before `public.phase_d_handler_schema;` — the binding carries `_input_schema_id_fkey` and `_output_schema_id_fkey` into the schema table. Nothing outside Phase D reads either, and no frozen object references them |

Applied more than once: the executor was corrected twice after apply (rule applicability, then the
retired-path literal in the board). Each re-apply was `--apply --ddl` and each read back identical.

### 2. `scripts/sql/phase_d_d3_rule_enforcement.sql`

| | |
|---|---|
| commit | `fb86840`; squashed to `bc20365` |
| routines | `fn_phase_d_rule_applies`, `fn_phase_d_rule_check`, `fn_phase_d_rule_state` |
| tables | `phase_d_rule_enforcement` (54 rows) |
| schema shape | `a614b87656ac929e…` → `7c9c8a089e52808c…` |
| verified | read back identical; board `fn_phase_d_rule_state()` 3/4, the fourth red **by disclosure** (20 rules `OUTSTANDING`) and ratcheted in `kernel-boards.json` |
| rollback | `scripts/sql/down/phase_d_d3_rule_enforcement_down.sql`, then remove the ratchet entry. `fn_phase_c_rule_check` is **untouched and still live**, so dropping these restores the prior behaviour exactly |

One re-apply widened the `enforcement_kind` check constraint. `create table if not exists` does not
reconcile a constraint on an existing table, so the file carries an explicit
`drop constraint if exists` / `add constraint` pair; without it the second run failed on the first
widened row. The pair at `:65-70` restates the same 7-value list already in the `create table` at
`:47-49`, so its down is a no-op.

### 3. `scripts/sql/phase_d_d0_auth_debt_discharged.sql`

| | |
|---|---|
| commit | `195cfb4`; squashed to `bc20365` |
| routines | none |
| data | 2 `update`s to `public.phase_d_preflight_requirement` |
| schema shape | unchanged |
| verified | the file ends in a `do $assert$` that raises unless both rows reached `SATISFIED` with evidence, so it cannot commit having done nothing; read back after apply: both `SATISFIED` at `2026-08-18 14:56:00+00` |
| rollback | `update public.phase_d_preflight_requirement set status='OUTSTANDING', satisfied_at=null, evidence=null where requirement_id in ('D0-AUTH-001','D0-AUTH-002');` — **not** a `drop table`: `public.phase_d_preflight_requirement` was created by `scripts/sql/phase_c_baseline_row_and_d0_preflight.sql:98` and no Phase D down may drop it |

## The D36–D43 increment

`d36` was written and applied on **2026-08-20** (file mtime `03:18:01` Asia/Dubai = `2026-08-19
23:18:01Z`; the calendar date differs between the two clocks). When this increment began it was
**untracked** — `git ls-files scripts/sql/phase_d_*.sql` returned 58 against `ls` 59 — absent from
`scripts/sql/MANIFEST.txt`, live on production, and in no rollback classification. It was committed
here as `7090016`.

Seven more files were then written and applied in this increment. mtimes, all UTC on 2026-08-19:

| file | written | bytes |
|---|---|---|
| `d37_the_rules_read_real_rows_or_they_refuse` | 23:21:39Z | 22,992 |
| `d38_the_authority_the_kernel_acted_under_is_a_recorded_fact` | 23:27:00Z | 17,601 |
| `d39_two_ordering_defects_the_first_real_inquiry_found` | 23:30:55Z | 17,130 |
| `d40_the_arrival_is_known_by_the_inbox_id_already_passed` | 23:34:38Z | 16,349 |
| `d41_inquiry_owner_is_a_role_not_a_customer` | 23:37:11Z | 20,368 |
| `d42_route_state_was_my_own_placeholder` | 23:39:52Z | 25,367 |
| `d43_a_signed_in_caller_may_not_name_the_owner` | 23:51:52Z | 6,444 |

`d37`–`d42` are on `7090016`. **`d43` was applied to production and untracked at the time of
writing** — its read-back (the `authenticated` grant gone from `fn_phase_d_object_read`) proved the
apply landed, and `git status --porcelain scripts/sql` showed it as `??`.

**That gap is closed.** `git log --diff-filter=A --format='%h %ad' -- scripts/sql/phase_d_d43_a_signed_in_caller_may_not_name_the_owner.sql`
returns `9dd1927 2026-08-20T04:02:49+04:00`, on the same branch. `git ls-files scripts/sql/phase_d_*.sql | wc -l`
and `ls scripts/sql/phase_d_*.sql | wc -l` both return **73**: nothing under `scripts/sql/` matching
`phase_d_*` is untracked any more.

`d43` also demonstrates why `apply_sql --promote` is not an option for a grant: promote sends only a
routine body, so a `revoke` in a promoted file lands nowhere and the tool still prints success. The
file carries no body at all and had to be applied.

## The D44–D51 increment

Four further commits on `feat/phase-d-remediation-to-acceptance`, all after `7090016`, in
`git log --oneline` order (newest first):

| commit | date (branch, +04:00) | Phase D files added |
|---|---|---|
| `a7a37a8` | 2026-08-20T04:32:09 | `d44_an_endpoint_that_ignores_an_id_has_not_refused` |
| `5c7152a` | 2026-08-20T04:22:57 | `d50_a_rule_that_could_not_fail_made_one_that_could_not_not_fire`, `d51_callable_is_not_answerable_yet` |
| `f9415ab` | 2026-08-20T04:06:47 | `d49_a_freeze_with_no_way_to_record_an_amendment` |
| `9dd1927` | 2026-08-20T04:02:49 | `d43_…`, `d46_a_contract_that_records_intent_but_checks_presence`, `d47_nineteen_rules_that_had_never_refused_anything`, `d48_a_two_context_probe_cannot_find_a_withheld_authority` |

The numbering skips `d45`; no file of that name exists in the tree or in the history of this branch.

**Two of the seven carry additive DDL, and both were measured rather than assumed.**

- `d46` adds six columns to `public.phase_d_handler_schema` — `schema_version int`,
  `field_types jsonb`, `enum_domains jsonb`, `optional_keys text[]`,
  `additional_properties boolean`, `type_source text` — at `:54-59`, makes all six `not null` at
  `:107-113`, and adds `phase_d_handler_schema_field_types_ck` and
  `phase_d_handler_schema_version_ck` at `:119-124` inside an `if not exists` guard. All eight
  objects read back from `pg_attribute` (attnums 10–15) and `pg_constraint`. The table keeps its 514
  rows; the column count moves 9 → 15.
- `d49` creates `public.phase_c_freeze_amendment` at `:47-60` — 8 columns, `amendment_id` a
  `generated always as identity` primary key, `_moves` / `_reason_ck` / `_evidence_ck` checks and
  `_once` UNIQUE `(object_identity, prior_digest, new_digest)`; RLS on at `:62`, revoked from
  `public, anon, authenticated` and granted `select, insert` to `service_role` at `:63-64`. Read
  back: the table, the sequence `phase_c_freeze_amendment_amendment_id_seq`, the unique index
  `phase_c_freeze_amendment_once`, RLS on with 0 policies, and **2 rows** — the amendments for
  `fn_kernel_open_step(p_input jsonb)` and `fn_kernel_workflow_start(p_input jsonb)`, the two kernel
  routines `d36` replaced.

  It is named `phase_c_*` and is nonetheless a Phase D object: the only `CREATE TABLE` for it is in
  `d49`. That is the opposite of `public.phase_d_preflight_requirement`, which is named `phase_d_*`
  and is a Phase **C** object because `scripts/sql/phase_c_baseline_row_and_d0_preflight.sql:98`
  creates it. The test is which file creates it, never which phase the name mentions.

  Consequence for the estate inventory: `phase_d_*` base tables are still **24** and `phase_d_*`
  sequences still **5** — `phase_c_freeze_amendment` matches neither prefix. Any count that reads
  `like 'phase\_d\_%'` will not see it.

`d44` changes two existing CHECK constraints (`:104-108`, `:110-114`), widening each from three
values to four. `d47`, `d48`, `d50` and `d51` carry routine bodies and row updates only.

## Repository artefacts changed alongside the database

| file | why |
|---|---|
| `scripts/sql/MANIFEST.txt` | every applied file appended — a `scripts/sql` file the manifest does not list is a MANIFEST GAP and its live routines are production→repository drift |
| `docs/phase-c-final-kernel/CANONICAL_ROUTINE_MANIFEST.csv` | re-emitted from the engine (`--emit`), not hand-edited |
| `supabase/schema/full_schema.sql` | regenerated — the mirror said 550 tables and production holds 553 |
| `scripts/checks/kernel-boards.json` | one ratchet entry for the 20 outstanding rules, with owner, rule ids, and an instruction to **delete** it at 0 |
| `scripts/sql/down/` | **27** files, one `<stem>_down.sql` per file classified `EXPLICIT_DOWN_REQUIRED` in `PHASE_D_ROLLBACK_CLASSIFICATION_D9.md`. 23 at the first revision, plus `d44`, `d46` and `d49` once those landed and their objects could be read out of the catalogue, plus `e4` on 2026-08-20 — a grant revert IS reversible by name. Written, **not** rehearsed: `scripts/sql/down/README.md` records that no file there has been executed. **Now committed** — this row previously read "not yet committed: `git ls-files scripts/sql/down` returns 0 against 27 files on disk", which was true before #451 merged and is not now: `git ls-files scripts/sql/down` returns **28** (27 `.sql` + the README) |

`scripts/checks/canonical_routine_manifest.mjs` is a **frozen Phase C subject** and was not edited.
To read a finding it counts but does not print, a copy was taken to the scratchpad and instrumented
there.

## Production must never be ahead of main

`main` is at **`dd3dd23`**, which contains #446 through **#451** — every file from `d0` to `d56`,
`d45` included. This section previously said `main` was at `e59d36b` with `d36`–`d51` unmerged; #451
merged on 2026-08-20 and closed that window.

Ahead of `main` right now:

| what | state |
|---|---|
| `e4`–`e11` | committed on `feat/phase-d-e4-the-door-was-never-a-browser`, open as [#452](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/452), **not merged** |

**Until #452 merges, `main` legitimately does not contain the `e4`–`e11` definitions**, and a parity
gate run against `main` reports drift for that reason alone — that window is expected,
self-resolving on merge, and must not be "fixed" by re-applying anything. `e4` is the one to be
careful with: it carries no routine body at all, only 57 `revoke execute` statements, so a parity
check that compares **bodies** cannot see it either way. Grants are read with
`has_function_privilege` and `pg_proc.proacl`, not with a definition read-back, and
`scripts/checks/anon_cannot_execute_security_definer.test.mjs` is what watches them.

The earlier row for `d43` — "applied to production, **not committed**" — was different in kind: an
applied file with no commit is not a merge window, it is an untracked production change. It closed
the way it had to, by committing the file (`9dd1927`). **No applied file is untracked now**: every
file under `scripts/sql/` matching `phase_d_*` is tracked, 73 of 73 by both `ls` and `git ls-files`.

One repository gap does remain, and it is the opposite kind — repository behind the working tree,
not production ahead of the repository. Measured 2026-08-20: `git ls-files scripts/sql/down | wc -l`
returns **0** against `ls scripts/sql/down | wc -l` **27**. The whole rollback directory — 26 down
scripts and its README — is written and unstaged. Nothing has been applied from it and nothing reads
it, so no production state depends on it; but until it is committed, the reversal for every
`EXPLICIT_DOWN_REQUIRED` file exists on one machine only. Staging it is a `git add scripts/sql/down`
of that path and nothing wider — this working tree permanently carries session debris and a broad
`git add -A` has put hundreds of unrelated files into a PR before.

## Nothing was left behind

| | |
|---|---|
| workflow runs from probes | **0** (`business_object_id like 'PD-PROBE%'`) |
| canary auth identities | **0** (`auth.users` where email like `zz-phase-d-canary%`) |
| business rows created | **0** |

Every write probe ended in `raise exception`. The one identity created was deleted in the same run
and its removal proved by read-back, not inferred from the delete status.

The tables that could have accumulated rows read back empty on 2026-08-20 00:00:41Z:
`phase_d_effect_ledger` 0, `phase_d_handoff_acceptance` 0, `phase_d_object_record` 0,
`phase_d_external_attempt` 0, `phase_d_injected_defect_result` 0, `phase_d_dispatch` 0.

**`e4`–`e6` added nothing to any of them, and `e5` deliberately did not.** `e5` proved the effect
path by producing the declared effect for step runs 255 and 256 inside an aborted transaction and
reading `pg_stat_xact_user_tables` — which reports what the TRANSACTION wrote rather than what a
chosen list of tables says — and got `public.phase_d_effect_ledger ins=2 upd=0 del=0` and nothing
else, with `fn_phase_d_fixture_residue()` returning 0 rows. **Those two rows were not kept.** Writing
a ledger row for a step run that completed before the recording path was built would put a fact in
the ledger that the ledger's own `produced_by` column would then misattribute.

## Frozen state, before and after

| | before | after |
|---|---|---|
| | before | after | re-measured 2026-08-20 03:14Z |
|---|---|---|---|
| Phase A baseline drift | 0 | **0** | **0 rows** |
| Phase B baseline drift | 0 | **0** | **0 rows** |
| `fn_phase_c_freeze_drift()` drifted | 0 of 3 | 0 of 3 | **0 of 25**, with **3** recorded amendments |
| `fn_phase_c_invariants()` red | 0 | **0** | not re-run in this pass — the check suite runs it |

The fourth column is new. The "before/after" pair was recorded for the first three increments and
says `0 of 3`, which is the number of frozen subjects that existed then; `public.phase_c_frozen_subject`
now holds **25**, so `0 of 3` was a true statement about a population three subjects wide and is not a
statement about the programme. Quoting it as one is the error this column removes.

No frozen Phase A, Phase B or Phase C object was edited by any increment in this ledger without a
recorded amendment. There are three, all pinned to the exact prior digest and none written by
overwriting `phase_c_frozen_subject.digest`:

| amendment | subject | file | what changed |
|---|---|---|---|
| 1 | `canonical_step_engine` → `fn_kernel_open_step(p_input jsonb)` | `d36` | one declared local and one call, to put the Phase D dispatch on the kernel's own open path |
| 2 | `canonical_workflow_start_service` → `fn_kernel_workflow_start(p_input jsonb)` | `d36` | the same, for the opener that starts a run's FIRST step inline |
| 3 | `component_crosswalk` → `public.phase_c_component` | `e6` | three rows whose `external_entry` said `unauthenticated_only` because a PUBLIC EXECUTE grant made them reachable, and `e4` revoked it. `classification` and `activation_state` move with it because `a00_phase_c_component_classification_guard` refuses the write otherwise |

### The authority these three rest on, and the document that disagrees — OPEN, FOR THE FOUNDER

Two independent acceptance audits have now raised this, and the second could not find the authority
at all. It is recorded here so a third does not have to look.

**Where the mechanism comes from.** `public.phase_c_freeze_amendment` is created by
`scripts/sql/phase_d_d49_a_freeze_with_no_way_to_record_an_amendment.sql` — written by the builder,
after `fn_phase_c_freeze_drift()` caught the builder's own edit to two kernel routines. The table has
no approver column. Every mention of it in this repository is builder- or auditor-authored.

**Where the authority comes from.** The founder's session brief of 2026-08-20 states it directly, in
its non-negotiables:

> "Phase A, B and C stay FROZEN. A change to a Phase C kernel routine body is allowed but trips
> `fn_phase_c_freeze_drift()`; record it in `public.phase_c_freeze_amendment` pinned to the exact
> prior digest. NEVER overwrite `phase_c_frozen_subject.digest` — that is a rubber stamp and the
> amendment table exists so it does not have to happen."

That instruction is in a session brief, not in this repository, which is why an auditor reading only
the tree cannot find it. **Quoting it here does not make it a change request** — it records where the
builder's authority came from and leaves the question open.

**The document that disagrees.** `PHASE_D_CHANGE_CONTROL.md` requires a **Phase C change request**
for a change to a frozen Phase C object. No such request exists in the tree; only Phase B change
request templates do. So two instructions govern the same act and say different things:

| | says |
|---|---|
| `PHASE_D_CHANGE_CONTROL.md` | a Phase C change request is required |
| the founder's 2026-08-20 session brief | record it in `phase_c_freeze_amendment`, pinned to the prior digest |

**PCCR-001 now exists.** The control document required a Phase C change request and none had been
written; `docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-001.md` is that document, covering all three
amendments with every one of the nine required elements measured — except section 11, founder
approval, which is **required and unsigned**. Writing it does not resolve the conflict and does not
need to: both instructions are now satisfied, the amendments are in the table as the brief requires
and the change request is on file as the control document requires.

**What remains the founder's to settle** — and it is not settled here. The second auditor's view is that the
written change control governs and Gate 0 is therefore not satisfied. That is a reasonable reading of
the documents in the tree. It turns entirely on a fact only the founder holds — which instruction he
means to stand — and it flips with no code change either way. Three amendments are affected: the two
`d36` kernel edits and `e6`'s component correction. Nothing has been written to
`phase_c_frozen_subject.digest` under either reading.

**`d49` is the file that made that declared exception recordable rather than merely declared.** It
creates `public.phase_c_freeze_amendment` and replaces `fn_phase_c_freeze_drift()` to read it, so
the two kernel replacements above are now two rows pinned to the digest each one excuses — read back
2026-08-20 as `canonical_step_engine -> fn_kernel_open_step(p_input jsonb)` and
`canonical_workflow_start_service -> fn_kernel_workflow_start(p_input jsonb)`. Neither digest is a
literal in the file: `prior_digest` comes from `public.phase_c_frozen_subject` and `new_digest` from
`encode(sha256(convert_to(pg_get_functiondef(p.oid),'UTF8')),'hex')` over the live definition. That
is what stops an amendment being a rubber stamp — and it also means a later edit on top of either
body reads as drift again, which is the point.

---

## 2026-08-24 — the `phase_d_o01`–`phase_d_o10` sequence

Branch `finish/phase-d-nine-product-controls`, commit `f9d2f6f`, PR [#465](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/465).
Cut from `main` at `2c9e3f2` immediately after
PR [#464](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/464) merged at
`2026-08-24T08:48:33Z`. Every file below was applied with
`node scripts/apply_sql.mjs <file> --apply --ddl`, which reads each routine's definition back out of
`htdblwldjkcgjvmqkbeh` and refuses unless it is byte-identical to the file, and prints the public
schema shape digest before and after.

Applied in this order. Nothing was applied twice with a different body; the `SHAPE` column is the
public-schema digest `apply_sql.mjs` printed after the write.

| # | file | what it wrote | read-back | SHAPE after |
|---|---|---|---|---|
| O01 | `phase_d_o01_two_identity_controls_whose_refusals_had_no_machine_name.sql` | `fn_phase_d_owner_admissibility`, `fn_phase_c_step_run_owner_admissible`, `fn_phase_c_overlay_may_not_dispatch`, `fn_phase_c_task_state_guard`; trigger `a02_phase_c_step_run_owner_admissible` | 4 routines identical | `41a05d69…` (unchanged — the trigger is not in the shape digest) |
| O02 | `phase_d_o02_an_append_only_ledger_with_no_writer_and_a_refund_that_never_read_it.sql` | `fn_kernel_refund_decision_record`, `fn_phase_c_refund_execution_requires_decision`, `fn_kernel_refund_ledger_state`; `refunds.refund_decision_id` + FK; trigger `z05_refund_execution_requires_decision`; one `kernel_write_authority` row | 3 routines identical | `ac2c1cf4…` |
| O03 | `phase_d_o03_a_legal_authority_nothing_could_call_stale.sql` | `phase_d_legal_source` (+RLS, +grants); `fn_phase_d_legal_source_current`; 5 committed ZZ DEMO source rows | 1 routine identical | `c56aa1d2…` |
| O04 | `phase_d_o04_a_supplier_facing_revision_with_no_redaction_state_and_no_scanner.sql` | `phase_d_personal_identifier_class` (10 rows), `phase_d_file_revision`, `phase_d_metadata_scan`; `fn_phase_d_file_revision_reviewer_independent` + trigger `a10_…`; `fn_phase_d_file_revision_dispatchable`; `fn_phase_d_package_revisions_dispatchable` | 3 routines identical | `6fcf2bf5…` |
| O05 | `phase_d_o05_four_committed_revisions_that_differ_in_one_respect.sql` | 6 committed file revisions | data only | unchanged |
| O06 | `phase_d_o06_a_quotation_that_could_change_hands_be_read_unpublished_and_be_normalised_in_place.sql` | `fn_phase_d_object_owner_is_stable` + `a30_…`; `fn_quote_supplier_is_immutable` + `a30_…`; `quote_comparisons.publication_state`/`published_at`/`superseded_by_comparison_id` + 2 CHECKs; `fn_phase_d_comparison_visible`; `phase_d_quote_normalisation`; `phase_d_supplier_authored_field` (8 rows); `fn_phase_d_normalisation_does_not_restate_the_original` + `a10_…`; `fn_phase_d_quote_original_intact` | 5 routines identical | `1e038461…` → `b14675ab…` after the `superseded_by_comparison_id` type correction |
| O07 | `phase_d_o07_seven_predicates_that_named_a_control_and_tested_something_else.sql` | `phase_d_legal_assertion` + `fn_phase_d_legal_assertion_source_is_current` + `a10_…`; 4 `phase_d_gate_contract.evidence_source` corrections; **`fn_phase_d_rule_check` and `fn_phase_d_gate_evaluate` replaced** | 3 routines identical | `fbaf3c1e…` |
| O08 | `phase_d_o08_the_nine_that_remained_executed.sql` | `fn_phase_d_run_injected_defects` replaced — the nine `NOT_RUN` emissions become nine driven branches | 1 routine identical | unchanged |
| O09 | `phase_d_o09_the_register_becomes_history_and_two_change_requests_are_deferred.sql` | `phase_d_injected_defect_disposition_history`; the 9 disposition rows moved and the live register emptied; `document_author_field` identifier class; `phase_c_change_request.disposition`/`disposition_reason`/`disposition_recorded_at` + 3 CHECKs; PCCR-004 and PCCR-005 registered as deferred | data + DDL | `6bc0b501…` |
| O10 | `phase_d_o10_the_new_file_set_leg_reddened_an_older_case_that_had_no_file_set.sql` | one committed file revision, so PD-DISP-003's control package satisfies the file-set leg O07 gave BR-012 | data only | unchanged |


### O11–O14 — four files the first ten made necessary

The file-set leg O07 gave BR-012 and GATE-013 is correct and it made three things visible that had
been true and unmeasured. Each of these four files is that correction, not a retreat from it.

| # | file | what it wrote | read-back | SHAPE after |
|---|---|---|---|---|
| O11 | `phase_d_o11_a_scan_is_a_fact_about_bytes_and_a_fixture_package_had_no_files.sql` | `fn_phase_d_file_revision_dispatchable` (scan looked up by **digest**, worst outcome wins), `fn_phase_d_fixture_file_revision`, `fn_phase_d_fixture_scenario` | 3 routines identical | unchanged |
| O12 | `phase_d_o12_a_new_fixture_table_the_committed_scenario_was_not_watching.sql` | one row on `phase_d_committed_scenario_watch` | data only | unchanged |
| O13 | `phase_d_o13_a_package_identified_two_ways_and_a_comparison_nobody_published.sql` | `fn_phase_d_package_revisions_dispatchable` (resolves record id, business key and prefixed key), `fn_quote_comparison_publication_stamp` + `a20_…`, one write-map column, `fn_phase_d_fixture_scenario` | 3 routines identical | unchanged |
| O14 | `phase_d_o14_the_package_the_drive_produces_and_a_key_in_two_shapes.sql` | `fn_phase_d_quote_original_intact` (same two-shape resolution), `fn_phase_d_effect_produce` (a supplier-safe package arrives with its file set **inside a test context only**) | 2 routines identical | unchanged |

**What each one was, in one line.**

* **O11.** A metadata scan was keyed on `(revision_ref, scanned_sha256)`, so the same bytes scanned
  once became unscanned the moment a second revision claimed them. A scanner reads a digest and
  reports on a digest; the lookup is now by digest, and where two scanners disagree about one file
  the **worst** outcome wins so a clean re-scan cannot bury a dirty one. And the fixture factory's
  supplier-safe package named no file at all, which is what turned 41 step-contract cases red.
* **O12.** O11's fixture revision is a row `phase_d_committed_scenario_watch` did not name. Measured
  first: a committed scenario does not reach that stage today (`fxrev` 0 after open and after
  close), so a DELETE in `close()` would have been a cleanup that has never removed anything and
  that nobody could prove works — and the only key linking a revision to a scenario runs through a
  table `close()` does not delete. It is **watched** instead, so a future committed scenario that
  does create one makes the close refuse rather than leaving rows for a later reader to find.
* **O13.** Two more instances of one key written in two shapes. `fn_phase_d_step_context` resolves an
  IDENTIFIES key from the scenario record's canonical identity — the **record id** — and the new
  predicates looked the same row up by **business key**. GATE-013 reported "package 550491 names no
  registered file revision" while BR-012, which already resolved both shapes, passed on the same
  package in the same drive. Also: `publication_state` defaults to `DRAFT` on purpose, so the
  fixture had to say what the workflow actually models, and a publication now stamps its own moment.
* **O14.** The package W08 judges is produced by the **drive**, not the fixture — measured, a W08
  scenario creates no `supplier_safe_package` at all. So the file set arrives with the package
  wherever it is created, guarded on `fn_phase_d_fixture_context()` being non-null, which is an
  hmac over `txid_current()` and not a GUC a caller can set. **In production a package that names no
  file is still refused**, because this estate has no file-production path and that absence must
  stay visible rather than be defaulted away.

Down scripts: O12 and O13 carry theirs; O11 and O14 are `ROUTINE_RESTORE` for their replacements
plus one dropped routine, and both state the restore path and what to expect after it — the red
cases they corrected come back, which is the state they corrected and not a new fault.
`node scripts/phase_d/build_migration_rollback_classification.mjs` classifies **252 of 252** Phase D
migrations with **0 down scripts required and missing**.

### How each is reversed

Every file has a `scripts/sql/down/<name>_down.sql` except O08, which is a pure routine replacement
(`ROUTINE_RESTORE` — `create or replace` has no DDL to reverse and the file creates no object; the
restore is to re-apply the last file before it that defines the routine, chosen by
`scripts/sql/MANIFEST.txt` position). `node scripts/phase_d/build_missing_down_scripts.mjs` reports
**0 files with no down script**, and
`node scripts/phase_d/build_migration_rollback_classification.mjs` classifies **245 of 245** Phase D
migrations with **0 down scripts required and missing**.

O07's down deliberately does **not** reproduce the two ~1,200-line routine bodies it replaced. A
hand-copied duplicate of a routine body is the shape that has already put a wrong body live in this
estate; the restore is stated as "re-apply the last file before O07 that defines each routine, by
MANIFEST position" with the verification that reproduces the pre-O07 behaviour (BR-018 returning
`ENFORCED_PASS` for `{quote_revision_ref:'x', platform_edited:'false'}`, which is the defect).

O09's down is written to restore the live disposition register **from the history table before
dropping it**, because after O09 the history table is the only surviving copy of those nine rows.

### Parity after the sequence

`node scripts/checks/canonical_routine_manifest.mjs --all`:
conflicting current definitions **0**, ambiguous winners **0**, manifest gaps **0**,
repository → production drift **0**, production → repository drift **0**.

Two things had to be fixed before that read clean, and both are worth recording because they are
tool-shaped rather than code-shaped:

* `scripts/sql/MANIFEST.txt` had `phase_d_o08…` listed **twice** (an appended line repeated during
  an assembly retry) and carried four lines of hook output —
  `[INFO] Recording command outcome: printf` — written into the file by a `PostToolUse` hook that
  landed inside a `>>` redirect. Both were removed. A manifest whose position decides canon cannot
  carry a duplicate or a log line.
* `refunds_refund_decision_id_fkey` showed as **uncommitted application DDL** until
  `supabase/schema/full_schema.sql` was regenerated, which is done as the last act of the session
  rather than mid-sequence — a mirror captured mid-chain is not a mirror.
