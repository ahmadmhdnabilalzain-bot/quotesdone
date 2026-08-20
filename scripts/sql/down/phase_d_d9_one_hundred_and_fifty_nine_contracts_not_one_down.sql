-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of
-- scripts/sql/phase_d_d9_one_hundred_and_fifty_nine_contracts_not_one.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the row counts below, accepts them, and runs it.
--
-- OBJECTS DROPPED, by name, in FK-safe order (never `cascade`):
--   1. index public.phase_d_handoff_acceptance_run_idx (run_id, outcome)
--   2. table public.phase_d_handoff_acceptance — with phase_d_handoff_acceptance_pkey
--      (acceptance_id bigint GENERATED ALWAYS AS IDENTITY, sequence
--      phase_d_handoff_acceptance_acceptance_id_seq), phase_d_handoff_acceptance_one_per_run UNIQUE
--      (handoff_run_id), _outcome_ck, _accept_ck, _reject_ck, and
--      phase_d_handoff_acceptance_handoff_id_fkey -> phase_d_handoff_contract(handoff_id)
--   3. table public.phase_d_handoff_contract — with phase_d_handoff_contract_pkey,
--      phase_d_handoff_contract_keys_ck, _owner_ck, and
--      phase_d_handoff_contract_handoff_id_fkey -> public.phase_b_handoff(handoff_id)
--
-- Order is not cosmetic: the acceptance ledger's handoff_id is a foreign key onto the contract
-- table and deliberately does NOT cascade (an audit trail is not derived from anything), so the
-- contract table cannot be dropped first without `cascade`.
--
-- CONSTRAINT NOTE. phase_d_handoff_contract_handoff_id_fkey as it stands on production is NOT d9's
-- definition: d9 wrote ON DELETE RESTRICT at :44-45 and d9l changed it to ON DELETE CASCADE.
-- Dropping the table takes whichever is current. To undo only that change and keep the table, run
-- scripts/sql/down/phase_d_d9l_a_phase_d_key_standing_in_front_of_a_phase_b_guard_down.sql instead.
--
-- ROW COUNT AT RISK (measured on htdblwldjkcgjvmqkbeh; WORKLIST D.3 "Data at risk on a drop" and
-- D.1 item 17):
--   public.phase_d_handoff_contract     159 rows — one per frozen Phase B handoff. The handoff ids
--                                       survive in public.phase_b_handoff; the 24 columns of
--                                       contract detail per handoff do not.
--   public.phase_d_handoff_acceptance     0 rows — no run has ever been accepted or rejected
--                                       through it.
--
-- KNOWN CONSUMER: scripts/phase_d/build_handoff_event_result.mjs reads phase_d_handoff_contract for
-- the 159 handoff rows of docs/phase-d/PHASE_D_HANDOFF_EVENT_RESULT.csv. After this rollback that
-- builder fails its count guard. Expected.
--
-- NOT TOUCHED: the five CREATE OR REPLACE FUNCTION bodies in d9. A create-or-replace has no down —
-- see scripts/sql/down/README.md.
-- =================================================================================================

begin;

drop index if exists public.phase_d_handoff_acceptance_run_idx;
drop table if exists public.phase_d_handoff_acceptance;
drop table if exists public.phase_d_handoff_contract;

do $ctl$
declare v_left text := '';
begin
  if to_regclass('public.phase_d_handoff_acceptance')         is not null then v_left := v_left || 'public.phase_d_handoff_acceptance ';         end if;
  if to_regclass('public.phase_d_handoff_contract')           is not null then v_left := v_left || 'public.phase_d_handoff_contract ';           end if;
  if to_regclass('public.phase_d_handoff_acceptance_run_idx') is not null then v_left := v_left || 'public.phase_d_handoff_acceptance_run_idx '; end if;

  if v_left <> '' then
    raise exception 'D9 down did not take: still present -> %', v_left;
  end if;

  raise notice 'D9 down: phase_d_handoff_acceptance, its index, and phase_d_handoff_contract are gone.';
end $ctl$;

commit;
