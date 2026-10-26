-- P2-C1 STAGE A - ROLLBACK. Reverses every object created by the Stage A migrations and nothing
-- else. Stage A is purely additive, so this restores the database to its pre-Stage-A shape.
--
-- REHEARSED, not assumed. On 2 August 2026 this exact script was run inside a transaction that was
-- then deliberately aborted:
--
--   ROLLBACK REHEARSAL OK | stage A relations 25 -> 0 | stage A functions 11 -> 0
--   | answer_precedence type remaining 0 | untouched neighbours present 7/7
--   | aborting so nothing is really dropped
--
-- The seven neighbours checked as untouched are scenario_expectation_change,
-- scenario_expectation_baseline, v_scenario_expectation_drift, kb_operational_route,
-- kb_operational_route_map, inquiry_intake and spec_backlog. Immediately afterwards the Stage A
-- self-test returned 14/14, confirming nothing had actually been dropped.
--
-- To rehearse again without committing, wrap the body below in:
--   do $reh$ begin <body> raise exception 'rehearsal only'; end $reh$;
--
-- Order matters: views before the tables they read, functions before the type they take as an
-- argument, tables child-before-parent. `cascade` is used deliberately so a partially applied
-- Stage A also rolls back cleanly.

drop view if exists public.v_group_dispatch cascade;
drop view if exists public.v_group_completeness cascade;
drop view if exists public.v_workstream_dispatch cascade;
drop view if exists public.v_workstream_completeness cascade;
drop view if exists public.v_workstream_conflict cascade;
drop view if exists public.v_workstream_answer cascade;
drop view if exists public.v_inquiry_workstream_identity cascade;

drop function if exists public.fn_p2c1_stage_a_selftest() cascade;
drop function if exists public.fn_p2c1_fixture_satisfy(bigint,bigint,text) cascade;
drop function if exists public.fn_inquiry_answer_confirm(bigint,text,text,text,text,bigint[]) cascade;
drop function if exists public.fn_inquiry_answer_set(bigint,text,text,public.answer_precedence,text,text,text,bigint[],jsonb) cascade;
drop function if exists public.fn_inquiry_answer_supersede(bigint,bigint,text,text,text,text,public.answer_precedence,text,text) cascade;
drop function if exists public.fn_inquiry_workstream_deactivate(bigint,text,text) cascade;
drop function if exists public.fn_inquiry_workstream_activate(bigint,text,text) cascade;
drop function if exists public.fn_field_normalise(text,text) cascade;
drop function if exists public.trg_inquiry_answer_value_immutable() cascade;
drop function if exists public.trg_p2c1_append_only() cascade;

drop table if exists public.mep_subcategory_review cascade;
drop table if exists public.inquiry_state_audit cascade;
drop table if exists public.inquiry_gate cascade;
drop table if exists public.inquiry_gate_required cascade;
drop table if exists public.inquiry_workstream_requirement cascade;
drop table if exists public.inquiry_answer_conflict_value cascade;
drop table if exists public.inquiry_answer_conflict cascade;
drop table if exists public.inquiry_answer_corroboration cascade;
drop table if exists public.inquiry_answer_document cascade;
drop table if exists public.inquiry_answer_scope cascade;
drop table if exists public.inquiry_answer cascade;
drop table if exists public.inquiry_workstream cascade;
drop table if exists public.inquiry_workstream_group cascade;
drop table if exists public.field_definition_source cascade;
drop table if exists public.field_definition_trade cascade;
drop table if exists public.field_definition cascade;
drop table if exists public.mep_trade_route cascade;
drop table if exists public.mep_trade cascade;

drop function if exists public.fn_answer_precedence_rank(public.answer_precedence) cascade;
drop type if exists public.answer_precedence cascade;
