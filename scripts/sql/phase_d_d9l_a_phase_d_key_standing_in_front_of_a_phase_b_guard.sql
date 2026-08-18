-- =================================================================================================
-- Phase D — D9l. A Phase D foreign key standing in front of a frozen Phase B guard.
--
-- `phase_b_guards_reject_injected_defects.test.mjs` went from 20/20 to 19/20 on this session's work,
-- and its message is exactly right:
--
--   FAIL  owner change with no handoff contract: refused, but not for the expected reason.
--     got: ERROR: 23503: update or delete on table "phase_b_handoff" violates foreign key constraint
--          "phase_d_handoff_contract_handoff_id_fkey" on table "phase_d_handoff_contract"
--
-- The guard test injects a defect by deleting a `phase_b_handoff` row, and asserts that the FROZEN
-- PHASE B GUARD refuses it — for the Phase B reason. `phase_d_handoff_contract.handoff_id` was
-- declared `on delete restrict`, so a Phase D table now refuses it FIRST, and the Phase B guard
-- never runs.
--
-- The operation was still refused, so nothing was unsafe. But "refused" is not the assertion; the
-- test asserts WHICH guard refused and why, and it is right to. A Phase D artefact that intercepts a
-- frozen guard has quietly replaced it — and the next time that guard is weakened or removed,
-- nothing would notice, because a Phase D foreign key would keep the outcome looking correct.
--
-- THE FIX IS CASCADE, NOT REMOVAL OF THE KEY. The contract is DERIVED — every column comes from
-- `phase_b_handoff` and re-running the D9 file regenerates all 159 rows — so a contract for a
-- handoff that no longer exists is meaningless and deleting it alongside costs nothing. Referential
-- integrity is kept, `contracts_with_no_live_handoff` on the board stays meaningful, and the Phase B
-- guard gets to speak first.
--
-- `phase_d_handoff_acceptance.handoff_id` is deliberately LEFT as-is. If a handoff is ever deleted
-- while Phase D decisions are recorded against it, the cascade fails there — which is correct: an
-- acceptance ledger is an audit trail and is not derived from anything, so it may not be swept away
-- by a delete one table up. In the guard test no acceptance rows exist, so the Phase B guard runs.
--
-- Verified by re-running the guard suite, not by reading this file: 20/20 guards fire again.
-- =================================================================================================

begin;

alter table public.phase_d_handoff_contract
  drop constraint if exists phase_d_handoff_contract_handoff_id_fkey;

alter table public.phase_d_handoff_contract
  add constraint phase_d_handoff_contract_handoff_id_fkey
  foreign key (handoff_id) references public.phase_b_handoff(handoff_id) on delete cascade;

do $ctl$
declare v_def text;
begin
  select pg_get_constraintdef(oid) into v_def from pg_constraint
   where conname = 'phase_d_handoff_contract_handoff_id_fkey'
     and conrelid = 'public.phase_d_handoff_contract'::regclass;
  if v_def is null or position('ON DELETE CASCADE' in v_def) = 0 then
    raise exception 'D9l: the contract key is still %, so it still stands in front of the Phase B guard',
      coalesce(v_def, '(absent)');
  end if;

  -- And the acceptance ledger must NOT cascade: an audit trail is not derived from anything.
  select pg_get_constraintdef(oid) into v_def from pg_constraint
   where conname = 'phase_d_handoff_acceptance_handoff_id_fkey'
     and conrelid = 'public.phase_d_handoff_acceptance'::regclass;
  if v_def is null or position('ON DELETE' in v_def) > 0 then
    raise exception 'D9l: the acceptance ledger key is %, and it must not cascade', coalesce(v_def,'(absent)');
  end if;

  if (select count(*) from public.phase_d_handoff_contract) <> 159 then
    raise exception 'D9l: % contracts after the key change; the effective denominator is 159',
      (select count(*) from public.phase_d_handoff_contract);
  end if;
end $ctl$;

commit;
