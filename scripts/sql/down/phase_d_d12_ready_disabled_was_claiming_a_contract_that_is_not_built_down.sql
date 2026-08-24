-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of
-- scripts/sql/phase_d_d12_ready_disabled_was_claiming_a_contract_that_is_not_built.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the block below, accepts it, and runs it.
--
-- TWO CHANGES, TWO DOWNS, IN THIS ORDER:
--   1. constraint public.phase_d_step_effect_depth_ck, reverted from the 6-value definition
--      d12:46-51 back to its 8-value predecessor.
--   2. table public.phase_d_external_adapter_field, dropped by name — with
--      phase_d_external_adapter_field_pkey (field_no int), _field_name_key UNIQUE (field_name) and
--      phase_d_external_adapter_field_state_ck (PRESENT / PARTIAL / ABSENT).
--
-- THE PREDECESSOR IS IN THE REPO. It is the inline constraint of the CREATE TABLE at
-- scripts/sql/phase_d_d7_effect_contract_and_business_writes.sql:80-82, quoted verbatim:
--
--     constraint phase_d_step_effect_depth_ck check (implementation_depth in (
--       'SCHEMA_ONLY','VALIDATION_ONLY','SERVICE_EXISTS_NO_CALLER','BUSINESS_EFFECT_CONNECTED',
--       'CAPABILITY_BOUNDARY_READY','EXTERNAL_ADAPTER_READY_DISABLED','COMPLETE','BLOCKED_DEFECT')),
--
-- The definition d12 installed, for comparison — six values, three of d7's eight dropped
-- (SERVICE_EXISTS_NO_CALLER, COMPLETE, BLOCKED_DEFECT) and one added
-- (EXTERNAL_ADAPTER_CONTRACT_NOT_BUILT):
--
--     check (implementation_depth in (
--       'SCHEMA_ONLY', 'VALIDATION_ONLY',
--       'BUSINESS_EFFECT_CONNECTED', 'CAPABILITY_BOUNDARY_READY',
--       'EXTERNAL_ADAPTER_READY_DISABLED', 'EXTERNAL_ADAPTER_CONTRACT_NOT_BUILT'))
--
-- THE DATA ALLOWS THE REVERT TODAY, AND THAT WAS MEASURED, NOT ASSUMED. `select
-- implementation_depth, count(*) from public.phase_d_step_effect group by 1` on
-- htdblwldjkcgjvmqkbeh returns BUSINESS_EFFECT_CONNECTED 224 · CAPABILITY_BOUNDARY_READY 21 ·
-- EXTERNAL_ADAPTER_READY_DISABLED 12, and all three are members of the 8-value predecessor. Zero
-- rows carry EXTERNAL_ADAPTER_CONTRACT_NOT_BUILT — d12's own UPDATE set twelve rows to it and d30
-- ("the twelve steps may say ready_disabled again") set them back. The pre-flight block below
-- re-measures rather than trusting this paragraph, because the population can change.
--
-- ROW COUNT AT RISK (measured on htdblwldjkcgjvmqkbeh; WORKLIST D.1 item 17):
--   public.phase_d_external_adapter_field   14 rows — the field-by-field reconciliation of the
--   external adapter contract, hand-authored as data. Not re-derivable except by re-running d12.
--   public.phase_d_step_effect              257 rows read, 0 written. The constraint revert changes
--   no data; if it cannot hold, this file refuses instead of rewriting rows.
--
-- NOT TOUCHED: the one CREATE OR REPLACE FUNCTION body in d12. A create-or-replace has no down —
-- see scripts/sql/down/README.md.
-- =================================================================================================


do $pre$
declare v_bad text;
begin
  if to_regclass('public.phase_d_step_effect') is null then
    raise exception 'D12 down: public.phase_d_step_effect does not exist. The d7 down has already run; there is no constraint to revert.';
  end if;

  select string_agg(distinct implementation_depth, ', ')
    into v_bad
    from public.phase_d_step_effect
   where implementation_depth not in (
           'SCHEMA_ONLY','VALIDATION_ONLY','SERVICE_EXISTS_NO_CALLER','BUSINESS_EFFECT_CONNECTED',
           'CAPABILITY_BOUNDARY_READY','EXTERNAL_ADAPTER_READY_DISABLED','COMPLETE','BLOCKED_DEFECT');

  if v_bad is not null then
    raise exception 'D12 down refuses: public.phase_d_step_effect carries implementation_depth values the d7:80-82 predecessor does not allow -> %. Re-derive those rows first. This file will not rewrite measured rows to make a DDL statement succeed.', v_bad;
  end if;
end $pre$;

-- ---- 1. the depth constraint, back to d7:80-82 --------------------------------------------------
alter table public.phase_d_step_effect
  drop constraint if exists phase_d_step_effect_depth_ck;

alter table public.phase_d_step_effect
  add constraint phase_d_step_effect_depth_ck check (implementation_depth in (
    'SCHEMA_ONLY','VALIDATION_ONLY','SERVICE_EXISTS_NO_CALLER','BUSINESS_EFFECT_CONNECTED',
    'CAPABILITY_BOUNDARY_READY','EXTERNAL_ADAPTER_READY_DISABLED','COMPLETE','BLOCKED_DEFECT'));

-- ---- 2. the adapter field register ---------------------------------------------------------------
drop table if exists public.phase_d_external_adapter_field;

do $ctl$
declare v_def text;
begin
  select pg_get_constraintdef(oid) into v_def
    from pg_constraint
   where conname = 'phase_d_step_effect_depth_ck'
     and conrelid = 'public.phase_d_step_effect'::regclass;

  if v_def is null then
    raise exception 'D12 down did not take: phase_d_step_effect_depth_ck is absent, so the table now has no depth constraint at all.';
  end if;
  if position('EXTERNAL_ADAPTER_CONTRACT_NOT_BUILT' in v_def) > 0 then
    raise exception 'D12 down did not take: the depth constraint still allows EXTERNAL_ADAPTER_CONTRACT_NOT_BUILT -> %', v_def;
  end if;
  if position('SERVICE_EXISTS_NO_CALLER' in v_def) = 0
     or position('COMPLETE' in v_def) = 0
     or position('BLOCKED_DEFECT' in v_def) = 0 then
    raise exception 'D12 down did not take: the depth constraint is missing one of the three values d12 removed -> %', v_def;
  end if;

  if to_regclass('public.phase_d_external_adapter_field') is not null then
    raise exception 'D12 down did not take: public.phase_d_external_adapter_field is still present.';
  end if;

  raise notice 'D12 down: phase_d_step_effect_depth_ck is back to the eight values of d7:80-82, and phase_d_external_adapter_field is gone.';
end $ctl$;


-- ---- ROUTINES THIS FILE INTRODUCED ------------------------------------------------------
-- Added 23 Aug 2026. Every routine below is defined by no other file under scripts/sql/, so
-- re-applying a predecessor cannot restore it and dropping it is the whole of its reversal.
-- Anything still calling one of them will raise on a missing function after this rollback.
drop function if exists public.fn_phase_d_adapter_state();
