-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of
-- scripts/sql/phase_d_d7_effect_contract_and_business_writes.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the row counts below, accepts them, and runs it.
--
-- OBJECTS DROPPED, by name (never `cascade`):
--   1. index public.phase_d_effect_ledger_step_idx (step_id)
--   2. index public.phase_d_effect_ledger_run_idx  (run_id)
--   3. table public.phase_d_effect_ledger — with phase_d_effect_ledger_pkey,
--      phase_d_effect_ledger_one_per_step_run UNIQUE (step_run_id, effect_type),
--      phase_d_effect_ledger_mode_ck (none/mock/disabled), and sequence
--      phase_d_effect_ledger_effect_id_seq
--   4. table public.phase_d_object_write_map — with phase_d_object_write_map_pkey,
--      phase_d_object_write_map_op_ck, phase_d_object_write_map_cols_ck
--   5. table public.phase_d_step_effect — with phase_d_step_effect_pkey,
--      phase_d_step_effect_type_ck, phase_d_step_effect_depth_ck, phase_d_step_effect_resolution_ck
--
-- No FK runs between these three tables, so the order above is only "index before its table" and
-- "smallest blast radius last". phase_d_step_effect is dropped last because it is the one holding
-- 257 rows and an operator who stops halfway should stop before that, not after it.
--
-- CONSTRAINT NOTE. phase_d_step_effect_depth_ck and phase_d_step_effect_resolution_ck as they stand
-- on production are NOT d7's definitions any more — d12 widened depth_ck to 6 values and d7b
-- widened resolution_ck to 5. Dropping the table takes whichever definition is current. If the
-- intent is to undo only those widenings and keep the table, do not run this file: run
-- scripts/sql/down/phase_d_d12_ready_disabled_was_claiming_a_contract_that_is_not_built_down.sql
-- and scripts/sql/down/phase_d_d7b_three_derivation_defects_found_by_the_board_down.sql instead.
--
-- ROW COUNT AT RISK (measured on htdblwldjkcgjvmqkbeh; WORKLIST D.3 "Data at risk on a drop" and
-- D.1 item 17):
--   public.phase_d_step_effect        257 rows — one per frozen Phase B step; expected_effect_type
--                                     and effect_object_id are DERIVED from the frozen registry,
--                                     so they are re-derivable by re-running d7, not retypable
--   public.phase_d_object_write_map    22 rows
--   public.phase_d_effect_ledger        0 rows — nothing has ever produced an effect through it
--   279 rows destroyed.
--
-- NOT TOUCHED: the four CREATE OR REPLACE FUNCTION bodies in d7 (fn_phase_d_effect_produce and
-- family). A create-or-replace has no down — see scripts/sql/down/README.md.
-- =================================================================================================

begin;

drop index if exists public.phase_d_effect_ledger_step_idx;
drop index if exists public.phase_d_effect_ledger_run_idx;
drop table if exists public.phase_d_effect_ledger;
drop table if exists public.phase_d_object_write_map;
drop table if exists public.phase_d_step_effect;

do $ctl$
declare v_left text := '';
begin
  if to_regclass('public.phase_d_effect_ledger')          is not null then v_left := v_left || 'public.phase_d_effect_ledger ';          end if;
  if to_regclass('public.phase_d_object_write_map')       is not null then v_left := v_left || 'public.phase_d_object_write_map ';       end if;
  if to_regclass('public.phase_d_step_effect')            is not null then v_left := v_left || 'public.phase_d_step_effect ';            end if;
  if to_regclass('public.phase_d_effect_ledger_step_idx') is not null then v_left := v_left || 'public.phase_d_effect_ledger_step_idx '; end if;
  if to_regclass('public.phase_d_effect_ledger_run_idx')  is not null then v_left := v_left || 'public.phase_d_effect_ledger_run_idx ';  end if;

  if v_left <> '' then
    raise exception 'D7 down did not take: still present -> %', v_left;
  end if;

  raise notice 'D7 down: phase_d_step_effect, phase_d_object_write_map, phase_d_effect_ledger and its two indexes are gone.';
end $ctl$;

commit;
