-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of
-- scripts/sql/phase_d_e40_the_same_defect_one_table_over_and_a_third_notation.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the block below, accepts it, and runs it.
--
-- GENERATED 23 Aug 2026 by scripts/phase_d/build_missing_down_scripts.mjs, because the rollback
-- classification reported this file as EXPLICIT_DOWN_REQUIRED with no down script. It reverses the
-- named objects below and nothing else; read it before running it.
--
-- OBJECTS DROPPED, by name (never `cascade`):
--   trigger a10_change_request_approver_is_the_founder on public.phase_c_change_request
--   trigger a10_freeze_amendment_approver_is_the_founder on public.phase_c_freeze_amendment
--   trigger z00_kernel_truncate_guard on public.phase_c_change_request
--
-- ROW COUNT AT RISK: dropping a column discards that column's values on every row of the table and
-- dropping a table discards all of its rows. Neither is measured here -- count them on
-- htdblwldjkcgjvmqkbeh immediately before running this file, and do not run it if the count
-- surprises you.
--
-- NOT TOUCHED: every `create or replace function` in the source file. A create-or-replace has no
-- down -- see scripts/sql/down/README.md; the predecessor body is restored by re-applying the file
-- that defined it, and every later file in that routine's chain, in order.

-- =================================================================================================

begin;

do $pre$
begin
  if to_regclass('public.phase_c_change_request') is null then
    raise exception 'phase_d_e40_the_same_defect_one_table_over_and_a_third_notation down: public.phase_c_change_request does not exist; there is nothing here to revert.';
  end if;
end $pre$;

drop trigger if exists z00_kernel_truncate_guard on public.phase_c_change_request;
drop trigger if exists a10_freeze_amendment_approver_is_the_founder on public.phase_c_freeze_amendment;
drop trigger if exists a10_change_request_approver_is_the_founder on public.phase_c_change_request;

commit;
