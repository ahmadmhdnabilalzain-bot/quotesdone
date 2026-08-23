-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of
-- scripts/sql/phase_d_d29_a_durable_external_adapter_that_never_sends.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the row counts below, accepts them, and runs it.
--
-- OBJECTS DROPPED, by name (never `cascade`):
--   1. table public.phase_d_external_attempt — 22 columns, attempt_id bigint primary key from
--      sequence phase_d_external_attempt_attempt_id_seq, with
--      phase_d_external_attempt_once_per_try UNIQUE (idempotency_key, attempt_no),
--      _mock_only (provider_mode = 'mock'), _outcome_check (7 values), _retry_class_check,
--      _reconciliation_check, _delivered_has_result
--   2. table public.phase_d_external_message_contract — 7 columns, contract_key text primary key
--
-- No FK runs between them, so the order is only "the ledger before the contract it cites".
--
-- WHAT THE _mock_only CONSTRAINT MEANS FOR A ROLLBACK. phase_d_external_attempt is the durable
-- record of an external send that is held at provider_mode = 'mock' by a CHECK constraint — the
-- adapter is built and deliberately cannot send. Dropping the table does not release the hold (the
-- hold is elsewhere) but it does remove the constraint that made "cannot send" a schema fact rather
-- than a convention. If the table is ever recreated without _mock_only, nothing else in the estate
-- restores it.
--
-- ROW COUNT AT RISK (measured on htdblwldjkcgjvmqkbeh; WORKLIST D.1 item 17):
--   public.phase_d_external_attempt            0 rows — nothing has ever been attempted through it
--   public.phase_d_external_message_contract   4 rows — the message contracts the adapter honours
--
-- ALSO IN d29 AND NOT UNDONE HERE: two of the nine `delete from` statements recorded in
-- scripts/sql/down/README.md as non-additive changes with no down. A delete has no down.
--
-- NOT TOUCHED: the four CREATE OR REPLACE FUNCTION bodies in d29. A create-or-replace has no down —
-- see scripts/sql/down/README.md.
-- =================================================================================================

begin;

drop table if exists public.phase_d_external_attempt;
drop table if exists public.phase_d_external_message_contract;

do $ctl$
declare v_left text := '';
begin
  if to_regclass('public.phase_d_external_attempt')          is not null then v_left := v_left || 'public.phase_d_external_attempt ';          end if;
  if to_regclass('public.phase_d_external_message_contract') is not null then v_left := v_left || 'public.phase_d_external_message_contract '; end if;

  if v_left <> '' then
    raise exception 'D29 down did not take: still present -> %', v_left;
  end if;

  raise notice 'D29 down: phase_d_external_attempt and phase_d_external_message_contract are gone.';
end $ctl$;


-- ---- ROUTINES THIS FILE INTRODUCED ------------------------------------------------------
-- Added 23 Aug 2026. Every routine below is defined by no other file under scripts/sql/, so
-- re-applying a predecessor cannot restore it and dropping it is the whole of its reversal.
-- Anything still calling one of them will raise on a missing function after this rollback.
drop function if exists public.fn_phase_d_external_field_state();
drop function if exists public.fn_phase_d_external_state();
commit;
