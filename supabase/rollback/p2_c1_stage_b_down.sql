-- P2-C1 STAGE B - ROLLBACK.
--
-- Stage B is NOT purely additive: unlike Stage A it also modified Stage A objects (the view chain,
-- fn_inquiry_workstream_activate, fn_p2c1_fixture_satisfy, inquiry_gate, field_definition) and
-- repointed field_definition_source away from the five *.brand_policy identities. So rolling back
-- Stage B is a TWO-STEP procedure, and step 2 is not optional:
--
--   1. Run this script. It removes every object Stage B created and every column it added.
--   2. Re-apply, in order:
--        supabase/migrations/20260802190000_p2_c1_stage_a_mep_model.sql
--        supabase/migrations/20260802190100_p2_c1_stage_a_field_identities.sql
--        supabase/migrations/20260802190200_p2_c1_stage_a_teardown_and_fixture.sql
--        supabase/migrations/20260802190300_p2_c1_stage_a_supersede_ordering_fix.sql
--        supabase/migrations/20260802190400_p2_c1_stage_a_selftest.sql
--      All five are idempotent (create or replace / create if not exists / on conflict do nothing).
--      Step 2 restores the Stage A view bodies, the Stage A activation function, and the five
--      *.brand_policy field identities with their field_definition_source mappings - which this
--      script removes by cascade when it drops shared.brand_acceptance_policy.
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
