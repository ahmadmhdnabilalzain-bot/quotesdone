-- P2-C1 STAGE B - ROLLBACK.
--
-- Stage B is NOT purely additive: unlike Stage A it also modified Stage A objects (the view chain,
-- fn_inquiry_workstream_activate, fn_p2c1_fixture_satisfy, inquiry_gate, field_definition) and
-- repointed field_definition_source away from the five *.brand_policy identities. So rolling back
-- Stage B is a TWO-STEP procedure, and step 2 is not optional:
--
--   1. Run this script. It removes every object Stage B created and every column it added.
--   2. Re-apply, in order:
--        supabase/migrations/20260802165328_p2_c1_stage_a_mep_model.sql
--        supabase/migrations/20260802165447_p2_c1_stage_a_mep_functions_and_views.sql
--        supabase/migrations/20260802165657_p2_c1_stage_a_mep_trades_and_field_identities.sql
--        supabase/migrations/20260802165742_p2_c1_stage_a_flag_consistency_split_fields_for_review.sql
--        supabase/migrations/20260802165847_p2_c1_stage_a_teardown_gate.sql
--        supabase/migrations/20260802165953_p2_c1_stage_a_selftest.sql
--        supabase/migrations/20260802170028_p2_c1_stage_a_fix_supersede_ordering.sql
--        supabase/migrations/20260802170101_p2_c1_stage_a_setter_uses_supersede_helper.sql
--        supabase/migrations/20260802170233_p2_c1_stage_a_selftest_fix_corroboration_case.sql
--        supabase/migrations/20260802170345_p2_c1_stage_a_selftest_fix_test12_measurement.sql
--        supabase/migrations/20260802170530_p2_c1_stage_a_mep_subcategory_review_matrix.sql
--      All are idempotent (create or replace / create if not exists / on conflict do nothing).
--      Step 2 restores the Stage A view bodies, the Stage A activation function, and the five
--      *.brand_policy field identities with their field_definition_source mappings - which this
--      script removes by cascade when it drops shared.brand_acceptance_policy.
--
-- CORRECTED 3 Aug 2026 (independent audit finding 8.3, severity critical).
-- Step 2 previously named five files under supabase/migrations/ with a 2026080219xx prefix:
--   20260802190000_p2_c1_stage_a_mep_model.sql and four siblings.
-- NONE OF THOSE PATHS EXIST. They were moved to supabase/migrations-superseded-consolidated/.
-- Because step 1 below drops shared.brand_acceptance_policy with cascade BEFORE step 2 runs, an
-- operator following the documented procedure was left with the Stage A objects dropped and no
-- file at the path given to restore them.
--
-- The audit stopped at "the paths do not exist". The deeper problem is that pointing step 2 at
-- migrations-superseded-consolidated/ would have been wrong even if the files had been there:
-- that directory holds the SUPERSEDED authoring set, not the migrations that were actually applied
-- to production. Re-applying it would have restored a DIFFERENT Stage A from the one being rolled
-- back to. The eleven files above are the applied set, verified against
-- supabase_migrations.schema_migrations versions 20260802165328 through 20260802170530.
--
-- PRE-FLIGHT. Before running step 1, confirm every step 2 file is actually present, or you will
-- discover the gap after the cascade rather than before it:
--
--   Get-ChildItem supabase\migrations -Filter '*p2_c1_stage_a*' | Measure-Object    # expect 11
--
-- and on a POSIX shell:
--
--   ls supabase/migrations/*p2_c1_stage_a* | wc -l                                  # expect 11
--
-- REHEARSED, not assumed. On 2 August 2026 this script ran inside a transaction that was then
-- deliberately aborted:
--
--   STAGE B ROLLBACK REHEARSAL OK | stage B relations 10 -> 0 | stage B functions 12 -> 0
--   | gate_state type remaining 0 | Stage A neighbours surviving 7/7 | aborting
--
-- The seven Stage A objects checked as surviving are inquiry_answer, inquiry_workstream,
-- field_definition, field_definition_source, inquiry_answer_conflict, inquiry_state_audit and
-- mep_subcategory_review. Immediately afterwards Stage A returned 14/14 and Stage B 14/14 + 2/2,
-- confirming nothing had actually been dropped.
--
-- To rehearse again without committing, wrap the body below in:
--   do $reh$ begin <body> raise exception 'rehearsal only'; end $reh$;

drop view if exists public.v_inquiry_trade_status cascade;
drop view if exists public.v_workstream_brand_policy cascade;

drop function if exists public.fn_p2c1_stage_b_regression() cascade;
drop function if exists public.fn_p2c1_stage_b_selftest() cascade;
drop function if exists public.fn_group_dispatch_report(bigint) cascade;
drop function if exists public.fn_trade_identify(bigint,text,jsonb,jsonb,text) cascade;
drop function if exists public.fn_trade_confirm(bigint,text,text,text) cascade;
drop function if exists public.fn_trade_reject(bigint,text,text,text) cascade;
drop function if exists public.fn_trade_remove(bigint,text,text,text) cascade;
drop function if exists public.fn_text_matches_pattern(text,text) cascade;

drop table if exists public.inquiry_trade_candidate_evidence cascade;
drop table if exists public.inquiry_trade_clarification cascade;
drop table if exists public.inquiry_trade_candidate cascade;
drop table if exists public.mep_trade_pattern cascade;
drop table if exists public.field_definition_reference cascade;
drop table if exists public.subcategory_trade_contribution cascade;
drop table if exists public.field_question_variant cascade;
drop table if exists public.brand_acceptance_policy_value cascade;

drop trigger if exists inquiry_answer_value_domain on public.inquiry_answer;
drop function if exists public.trg_inquiry_answer_value_domain() cascade;
drop function if exists public.fn_field_value_allowed(text,text) cascade;

drop trigger if exists inquiry_gate_state_sync on public.inquiry_gate;
drop function if exists public.trg_inquiry_gate_state_sync() cascade;
alter table public.inquiry_gate drop column if exists state;
alter table public.inquiry_gate drop column if exists state_reason;
drop function if exists public.fn_gate_state_satisfies(public.gate_state) cascade;
drop type if exists public.gate_state cascade;

alter table public.field_definition drop column if exists allowed_values;
alter table public.field_definition drop column if exists supersedes_field_ids;
alter table public.mep_trade drop column if exists is_core;

-- Removes shared.brand_acceptance_policy and the five *.brand_acceptance_policy_override rows.
-- Their field_definition_source mappings go with them by cascade, which is why step 2 above must
-- run: it is what restores the *.brand_policy identities the Stage B migration retired.
delete from public.field_definition where field_id like '%.brand_acceptance_policy%';
