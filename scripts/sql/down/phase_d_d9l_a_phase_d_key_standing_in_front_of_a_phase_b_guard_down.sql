-- =================================================================================================
-- PHASE D DOWN — reverses the constraint change in
-- scripts/sql/phase_d_d9l_a_phase_d_key_standing_in_front_of_a_phase_b_guard.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the block below, accepts it, and runs it.
--
-- OBJECT REVERTED, by name (never `cascade`):
--   constraint public.phase_d_handoff_contract_handoff_id_fkey, from ON DELETE CASCADE (installed
--   by d9l:37-42) back to ON DELETE RESTRICT.
--
-- THE PREDECESSOR IS IN THE REPO. It is the inline constraint of the CREATE TABLE at
-- scripts/sql/phase_d_d9_one_hundred_and_fifty_nine_contracts_not_one.sql:44-45, quoted verbatim:
--
--     constraint phase_d_handoff_contract_handoff_id_fkey
--       foreign key (handoff_id) references public.phase_b_handoff(handoff_id) on delete restrict,
--
-- The current definition on htdblwldjkcgjvmqkbeh, for comparison:
--     FOREIGN KEY (handoff_id) REFERENCES phase_b_handoff(handoff_id) ON DELETE CASCADE
--
-- WHAT REVERTING COSTS. d9l exists because the RESTRICT key stood in front of a Phase B guard: a
-- delete one table up was refused by this Phase D foreign key before the Phase B guard it was
-- supposed to reach ever ran, so the guard suite could not fire. Restoring RESTRICT restores that
-- behaviour. That is what a rollback is; it is stated here so nobody runs this file expecting the
-- guard suite to keep passing afterwards. d9l records 20/20 guards firing after its change.
--
-- NOT TOUCHED: phase_d_handoff_acceptance_handoff_id_fkey. It has no ON DELETE clause at all and
-- must keep none — an audit trail is not derived from anything. The control block below asserts it
-- is still clean, because a rollback that quietly changed the ledger key would be worse than the
-- defect.
--
-- ROW COUNT AT RISK: none. 159 rows in public.phase_d_handoff_contract are untouched; 0 rows in
-- public.phase_d_handoff_acceptance are untouched. This file changes one constraint definition and
-- no data.
-- =================================================================================================


do $pre$
begin
  if to_regclass('public.phase_d_handoff_contract') is null then
    raise exception 'D9l down: public.phase_d_handoff_contract does not exist. The d9 down has already run; there is no key to revert.';
  end if;
end $pre$;

alter table public.phase_d_handoff_contract
  drop constraint if exists phase_d_handoff_contract_handoff_id_fkey;

alter table public.phase_d_handoff_contract
  add constraint phase_d_handoff_contract_handoff_id_fkey
  foreign key (handoff_id) references public.phase_b_handoff(handoff_id) on delete restrict;

do $ctl$
declare v_def text;
begin
  select pg_get_constraintdef(oid) into v_def
    from pg_constraint
   where conname = 'phase_d_handoff_contract_handoff_id_fkey'
     and conrelid = 'public.phase_d_handoff_contract'::regclass;

  if v_def is null then
    raise exception 'D9l down did not take: phase_d_handoff_contract_handoff_id_fkey is absent, so the contract table now has no key onto phase_b_handoff at all.';
  end if;
  if position('ON DELETE RESTRICT' in v_def) = 0 then
    raise exception 'D9l down did not take: the contract key reads %, not ON DELETE RESTRICT', v_def;
  end if;

  -- The acceptance ledger key must still not cascade. This file does not touch it; assert it anyway.
  if to_regclass('public.phase_d_handoff_acceptance') is not null then
    select pg_get_constraintdef(oid) into v_def
      from pg_constraint
     where conname = 'phase_d_handoff_acceptance_handoff_id_fkey'
       and conrelid = 'public.phase_d_handoff_acceptance'::regclass;
    if v_def is not null and position('ON DELETE' in v_def) > 0 then
      raise exception 'D9l down: the acceptance ledger key now reads %, and it must not cascade.', v_def;
    end if;
  end if;

  raise notice 'D9l down: phase_d_handoff_contract_handoff_id_fkey is back to ON DELETE RESTRICT, as at d9:44-45. The Phase B guard is behind it again.';
end $ctl$;

