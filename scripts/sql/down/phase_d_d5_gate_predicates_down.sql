-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of scripts/sql/phase_d_d5_gate_predicates.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the row count below, accepts it, and runs it.
--
-- OBJECTS DROPPED, by name (never `cascade`):
--   public.phase_d_gate_contract — gate_id text primary key, evidence_keys text[], predicate_kind
--   with phase_d_gate_contract_predicate_kind_check, refusal_code, correction_owner,
--   evidence_source, recorded_at; and phase_d_gate_contract_gate_id_fkey -> public.phase_b_gate
--
-- ROW COUNT AT RISK (measured on htdblwldjkcgjvmqkbeh; WORKLIST D.1 item 17):
--   public.phase_d_gate_contract   32 rows — one per frozen Phase B gate. The gate ids survive in
--   public.phase_b_gate; what is destroyed is each gate's evidence_keys, predicate_kind,
--   refusal_code, correction_owner and evidence_source.
--
-- KNOWN CONSUMER: scripts/phase_d/build_rule_gate_result.mjs reads this table for the 32 GATE rows
-- of docs/phase-d/PHASE_D_RULE_GATE_RESULT.csv. After this rollback that builder produces 54 rows,
-- not 86, or fails its count guard. That is the expected post-rollback state.
--
-- NOT TOUCHED: the three CREATE OR REPLACE FUNCTION bodies in d5 (fn_phase_d_gate_evaluate,
-- fn_phase_d_gate_applies and one more). A create-or-replace has no down — see
-- scripts/sql/down/README.md.
-- =================================================================================================


drop table if exists public.phase_d_gate_contract;

do $ctl$
begin
  if to_regclass('public.phase_d_gate_contract') is not null then
    raise exception 'D5 down did not take: public.phase_d_gate_contract is still present.';
  end if;

  raise notice 'D5 down: phase_d_gate_contract is gone.';
end $ctl$;


-- ---- ROUTINES THIS FILE INTRODUCED ------------------------------------------------------
-- Added 23 Aug 2026. Every routine below is defined by no other file under scripts/sql/, so
-- re-applying a predecessor cannot restore it and dropping it is the whole of its reversal.
-- Anything still calling one of them will raise on a missing function after this rollback.
drop function if exists public.fn_phase_d_gate_state();
