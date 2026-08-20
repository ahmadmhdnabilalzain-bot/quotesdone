-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of
-- scripts/sql/phase_d_d34_the_seven_probes_that_were_never_run.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the row counts below, accepts them, and runs it.
--
-- OBJECTS DROPPED, by name (never `cascade`):
--   1. table public.phase_d_section8_defect_map  — defect_id text primary key, probe_id text,
--      justification text
--   2. table public.phase_d_section8_probe_result — 6 columns, probe_id text primary key, with
--      phase_d_section8_probe_result_verdict_check (4 values)
--
-- FOUR, not the three this file said when it was written. d34:32 created the check inline with
-- REFUSED_AS_REQUIRED / NOT_REFUSED / NOT_RUN, and
-- scripts/sql/phase_d_d44_an_endpoint_that_ignores_an_id_has_not_refused.sql:104-108 added
-- NOT_DISCRIMINATED. Read back from pg_constraint on htdblwldjkcgjvmqkbeh:
--     CHECK (verdict = ANY (ARRAY['REFUSED_AS_REQUIRED','NOT_REFUSED','NOT_RUN','NOT_DISCRIMINATED']))
-- Dropping the table takes whichever definition is current. To undo only d44's widening and keep
-- the table, run scripts/sql/down/phase_d_d44_an_endpoint_that_ignores_an_id_has_not_refused_down.sql
-- instead — and note that two of the 23 rows below carry NOT_DISCRIMINATED, so that file refuses
-- until they are re-run.
--
-- No FK runs between them on production, so the order is only "the map that cites a probe before
-- the probe results it cites".
--
-- ROW COUNT AT RISK (measured on htdblwldjkcgjvmqkbeh; WORKLIST D.1 item 17):
--   public.phase_d_section8_probe_result   23 rows — the recorded verdicts of the section 8
--                                          security probes. These are OUTCOMES of runs that
--                                          happened, not a registry: re-running d34 does not
--                                          reproduce them, only re-running the probes does
--                                          (scripts/phase_d/run_section8_security_probes.mjs).
--   public.phase_d_section8_defect_map     11 rows — which injected defect each probe answers, and
--                                          the justification for the mapping. Hand-authored.
--
-- KNOWN CONSUMER: public.fn_phase_d_injected_defect_report() is the only routine in the database
-- whose body references phase_d_section8_probe_result. After this rollback it raises on a missing
-- relation. Expected.
--
-- NOT TOUCHED: the one CREATE OR REPLACE FUNCTION body in d34. A create-or-replace has no down —
-- see scripts/sql/down/README.md.
-- =================================================================================================

begin;

drop table if exists public.phase_d_section8_defect_map;
drop table if exists public.phase_d_section8_probe_result;

do $ctl$
declare v_left text := '';
begin
  if to_regclass('public.phase_d_section8_defect_map')   is not null then v_left := v_left || 'public.phase_d_section8_defect_map ';   end if;
  if to_regclass('public.phase_d_section8_probe_result') is not null then v_left := v_left || 'public.phase_d_section8_probe_result '; end if;

  if v_left <> '' then
    raise exception 'D34 down did not take: still present -> %', v_left;
  end if;

  raise notice 'D34 down: phase_d_section8_defect_map and phase_d_section8_probe_result are gone, and with them 23 recorded probe verdicts.';
end $ctl$;

commit;
