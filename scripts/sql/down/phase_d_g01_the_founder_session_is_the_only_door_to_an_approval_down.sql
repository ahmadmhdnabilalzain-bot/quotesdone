-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of
-- scripts/sql/phase_d_g01_the_founder_session_is_the_only_door_to_an_approval.sql
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
--   column public.phase_c_freeze_amendment.deployed_before_approval
--   column public.phase_c_freeze_amendment.original_deployment_at
--   column public.phase_c_freeze_amendment.approval_route
--   column public.phase_c_freeze_amendment.approval_auth_subject
--   column public.phase_c_freeze_amendment.approved_amendment_table_digest
--   constraint phase_c_freeze_amendment_approval_route_values on public.phase_c_freeze_amendment
--   constraint phase_c_freeze_amendment_session_approval_names_its_route on public.phase_c_freeze_amendment
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
  if to_regclass('public.phase_c_freeze_amendment') is null then
    raise exception 'phase_d_g01_the_founder_session_is_the_only_door_to_an_approval down: public.phase_c_freeze_amendment does not exist; there is nothing here to revert.';
  end if;
end $pre$;

alter table public.phase_c_freeze_amendment drop constraint if exists phase_c_freeze_amendment_session_approval_names_its_route;
alter table public.phase_c_freeze_amendment drop constraint if exists phase_c_freeze_amendment_approval_route_values;
alter table public.phase_c_freeze_amendment drop column if exists approved_amendment_table_digest;
alter table public.phase_c_freeze_amendment drop column if exists approval_auth_subject;
alter table public.phase_c_freeze_amendment drop column if exists approval_route;
alter table public.phase_c_freeze_amendment drop column if exists original_deployment_at;
alter table public.phase_c_freeze_amendment drop column if exists deployed_before_approval;

commit;
