-- =================================================================================================
-- PHASE D DOWN — reverses the constraint widening in
-- scripts/sql/phase_d_d7b_three_derivation_defects_found_by_the_board.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the block below, accepts it, and runs it.
--
-- OBJECT REVERTED, by name (never `cascade`):
--   constraint public.phase_d_step_effect_resolution_ck, from the 5-value definition d7b:114-115
--   installed back to the 4-value predecessor.
--
-- THE PREDECESSOR IS IN THE REPO. It is the inline constraint of the CREATE TABLE at
-- scripts/sql/phase_d_d7_effect_contract_and_business_writes.sql:83-84, quoted verbatim:
--
--     constraint phase_d_step_effect_resolution_ck check (object_resolution in (
--       'MATCHED_STEP_TEXT','SOLE_OBJECT_OF_WORKFLOW','WORKFLOW_PRIMARY_OBJECT','NO_DOMAIN_OBJECT'))
--
-- The current definition on htdblwldjkcgjvmqkbeh, for comparison:
--     CHECK (object_resolution = ANY (ARRAY['MATCHED_STEP_TEXT','MATCHED_ALL_TOKENS',
--            'SOLE_OBJECT_OF_WORKFLOW','WORKFLOW_PRIMARY_OBJECT','NO_DOMAIN_OBJECT']))
-- MATCHED_ALL_TOKENS is the one value d7b added.
--
-- THIS DOWN IS BLOCKED BY DATA TODAY, AND THAT IS THE POINT. Measured on htdblwldjkcgjvmqkbeh at
-- the time of writing, by `select object_resolution, count(*) from public.phase_d_step_effect
-- group by 1`: WORKFLOW_PRIMARY_OBJECT 74 · NO_DOMAIN_OBJECT 72 · SOLE_OBJECT_OF_WORKFLOW 60 ·
-- MATCHED_STEP_TEXT 33 · MATCHED_ALL_TOKENS 18. Eighteen rows carry the value the predecessor
-- constraint does not allow. d7b widened the constraint because the derivation genuinely produced
-- that resolution for those eighteen steps; narrowing the constraint back without re-deriving them
-- would mean rewriting eighteen measured rows so that a DDL statement succeeds. This file will not
-- do that. It refuses first, names the count, and leaves the operator to re-derive the eighteen
-- steps (re-run d7's derivation) before narrowing the constraint.
--
-- ROW COUNT AT RISK: none deleted. 257 rows in public.phase_d_step_effect are read, 0 written. The
-- 18 MATCHED_ALL_TOKENS rows are the reason this file can refuse; they are never modified here.
--
-- NOT TOUCHED: the one CREATE OR REPLACE FUNCTION body in d7b. A create-or-replace has no down —
-- see scripts/sql/down/README.md. Reverting the constraint does not revert the derivation routine
-- that produces MATCHED_ALL_TOKENS, so a re-run of that routine would violate the restored
-- constraint. Reverting d7b properly means reverting both, and only the constraint half is DDL.
-- =================================================================================================


do $pre$
declare v_bad int;
begin
  if to_regclass('public.phase_d_step_effect') is null then
    raise exception 'D7b down: public.phase_d_step_effect does not exist. The d7 down has already run; there is no constraint to revert.';
  end if;

  select count(*) into v_bad
    from public.phase_d_step_effect
   where object_resolution = 'MATCHED_ALL_TOKENS';

  if v_bad > 0 then
    raise exception 'D7b down refuses: % rows in public.phase_d_step_effect carry object_resolution = MATCHED_ALL_TOKENS, which the d7:83-84 predecessor constraint does not allow. Re-derive those steps first. This file will not rewrite measured rows to make a DDL statement succeed.', v_bad;
  end if;
end $pre$;

alter table public.phase_d_step_effect
  drop constraint if exists phase_d_step_effect_resolution_ck;

alter table public.phase_d_step_effect
  add constraint phase_d_step_effect_resolution_ck check (object_resolution in (
    'MATCHED_STEP_TEXT','SOLE_OBJECT_OF_WORKFLOW','WORKFLOW_PRIMARY_OBJECT','NO_DOMAIN_OBJECT'));

do $ctl$
declare v_def text;
begin
  select pg_get_constraintdef(oid) into v_def
    from pg_constraint
   where conname = 'phase_d_step_effect_resolution_ck'
     and conrelid = 'public.phase_d_step_effect'::regclass;

  if v_def is null then
    raise exception 'D7b down did not take: phase_d_step_effect_resolution_ck is absent, so the table now has no resolution constraint at all.';
  end if;
  if position('MATCHED_ALL_TOKENS' in v_def) > 0 then
    raise exception 'D7b down did not take: the constraint still allows MATCHED_ALL_TOKENS -> %', v_def;
  end if;

  raise notice 'D7b down: phase_d_step_effect_resolution_ck is back to the four values of d7:83-84.';
end $ctl$;

