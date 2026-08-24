-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of scripts/sql/phase_d_d31_seventy_five_injected_defects.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the row count below, accepts it, and runs it.
--
-- OBJECT DROPPED, by name (never `cascade`):
--   public.phase_d_injected_defect_result — 8 columns, defect_id text primary key, with
--   phase_d_injected_defect_status_check (4 values)
--
-- Both of those were wrong when this file was written and are corrected here from pg_constraint on
-- htdblwldjkcgjvmqkbeh rather than from the source file. (a) The constraint is named
-- phase_d_injected_defect_status_check — no `_result` in the middle — because d31:39 names it
-- explicitly at :39-40, and no constraint called phase_d_injected_defect_result_status_check has
-- ever existed on this table. (b) It carries FOUR values, not three: d31:40 wrote
-- REFUSED_AS_REQUIRED / NOT_REFUSED / NOT_RUN and
-- scripts/sql/phase_d_d44_an_endpoint_that_ignores_an_id_has_not_refused.sql:110-114 added
-- NOT_DISCRIMINATED. Live definition, read back:
--     CHECK (status = ANY (ARRAY['REFUSED_AS_REQUIRED','NOT_REFUSED','NOT_RUN','NOT_DISCRIMINATED']))
-- Dropping the table takes whichever definition is current. To undo only d44's widening and keep
-- the table, run scripts/sql/down/phase_d_d44_an_endpoint_that_ignores_an_id_has_not_refused_down.sql
-- instead.
--
-- ROW COUNT AT RISK (measured on htdblwldjkcgjvmqkbeh; WORKLIST D.1 item 17):
--   public.phase_d_injected_defect_result   0 rows
--
-- Zero rows is the whole point of reading the row count rather than assuming it. The deliverable
-- docs/phase-d/PHASE_D_INJECTED_DEFECT_RESULT.csv holds 75 result rows and this table holds none,
-- so the CSV is not built from this table today — the builder
-- scripts/phase_d/build_injected_defect_result.mjs reads the catalogue CSV under
-- QuotesDone_PHASE_D_DETERMINISTIC_BUSINESS_HANDLER_IMPLEMENTATION_PRODUCTION_DIRECT_v2026.08.17/
-- registries/. Dropping this table therefore destroys no recorded verdict. It removes the place a
-- verdict was meant to be recorded, which is a different loss and a smaller one.
--
-- NOT TOUCHED: the one CREATE OR REPLACE FUNCTION body in d31. A create-or-replace has no down —
-- see scripts/sql/down/README.md.
-- =================================================================================================


drop table if exists public.phase_d_injected_defect_result;

do $ctl$
begin
  if to_regclass('public.phase_d_injected_defect_result') is not null then
    raise exception 'D31 down did not take: public.phase_d_injected_defect_result is still present.';
  end if;

  raise notice 'D31 down: phase_d_injected_defect_result is gone.';
end $ctl$;

