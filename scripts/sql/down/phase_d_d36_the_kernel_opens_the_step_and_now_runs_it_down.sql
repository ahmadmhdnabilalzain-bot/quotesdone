-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of
-- scripts/sql/phase_d_d36_the_kernel_opens_the_step_and_now_runs_it.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the row count below, accepts it, and runs it.
--
-- WHY THIS FILE EXISTS SEPARATELY FROM THE OTHER TWENTY-ONE. d36 was applied to production before
-- it was committed, was absent from scripts/sql/MANIFEST.txt, and was unclassified for rollback.
-- Its table is the 24th public.phase_d_* table on htdblwldjkcgjvmqkbeh — the one an inventory that
-- said "23 tables, 4 sequences" was missing. It is tracked now; the manifest entry is a separate
-- job (WORKLIST D.1 items 1, 2 and 12).
--
-- OBJECTS DROPPED, by name (never `cascade`):
--   1. index public.phase_d_dispatch_step_idx    (step_id, dispatched_at desc)
--   2. index public.phase_d_dispatch_run_idx     (run_id, dispatched_at desc)
--   3. index public.phase_d_dispatch_outcome_idx (outcome, dispatched_at desc)
--   4. table public.phase_d_dispatch — 17 columns, with phase_d_dispatch_pkey (dispatch_id bigint
--      GENERATED ALWAYS AS IDENTITY, sequence phase_d_dispatch_dispatch_id_seq) and
--      phase_d_dispatch_outcome_check (EXECUTED / REFUSED / INPUTS_UNRESOLVED / DEPTH_LIMIT /
--      DISPATCH_OFF). Row-level security is on with 0 policies; the grants d36 makes
--      (`grant select, insert … to service_role`) go with the table.
--
-- The indexes are named before the table so the operator sees all four objects listed rather than
-- three of them disappearing implicitly.
--
-- ROW COUNT AT RISK (measured on htdblwldjkcgjvmqkbeh by `select count(*) from
-- public.phase_d_dispatch` at the time of writing, and independently at recon):
--   public.phase_d_dispatch   0 rows
--
-- Zero is worth stating carefully. This table is the durable record of every dispatch a kernel
-- opener attempts, including the refusals — d36 exists because "21 handlers refuse at the
-- capability boundary" is only a measurement if the 21 refusals are written down somewhere. A zero
-- here means no dispatch has been attempted yet, not that the table is disposable. Re-measure
-- before running this file; the count moves the moment the opener runs.
--
-- NOT TOUCHED: the five CREATE OR REPLACE FUNCTION bodies in d36. A create-or-replace has no down —
-- see scripts/sql/down/README.md. The opener routines survive this file with nowhere to record what
-- they dispatch, so they will raise on a missing relation. Expected.
-- =================================================================================================

begin;

drop index if exists public.phase_d_dispatch_step_idx;
drop index if exists public.phase_d_dispatch_run_idx;
drop index if exists public.phase_d_dispatch_outcome_idx;
drop table if exists public.phase_d_dispatch;

do $ctl$
declare v_left text := '';
begin
  if to_regclass('public.phase_d_dispatch')             is not null then v_left := v_left || 'public.phase_d_dispatch ';             end if;
  if to_regclass('public.phase_d_dispatch_step_idx')    is not null then v_left := v_left || 'public.phase_d_dispatch_step_idx ';    end if;
  if to_regclass('public.phase_d_dispatch_run_idx')     is not null then v_left := v_left || 'public.phase_d_dispatch_run_idx ';     end if;
  if to_regclass('public.phase_d_dispatch_outcome_idx') is not null then v_left := v_left || 'public.phase_d_dispatch_outcome_idx '; end if;

  if exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
              where n.nspname = 'public' and c.relkind = 'S'
                and c.relname = 'phase_d_dispatch_dispatch_id_seq') then
    v_left := v_left || 'sequence public.phase_d_dispatch_dispatch_id_seq ';
  end if;

  if v_left <> '' then
    raise exception 'D36 down did not take: still present -> %', v_left;
  end if;

  raise notice 'D36 down: phase_d_dispatch, its three indexes and its identity sequence are gone. Production is back to 23 phase_d_* tables and 4 sequences.';
end $ctl$;


-- ---- ROUTINES THIS FILE INTRODUCED ------------------------------------------------------
-- Added 23 Aug 2026. Every routine below is defined by no other file under scripts/sql/, so
-- re-applying a predecessor cannot restore it and dropping it is the whole of its reversal.
-- Anything still calling one of them will raise on a missing function after this rollback.
drop function if exists public.fn_phase_d_dispatch_state();
commit;
