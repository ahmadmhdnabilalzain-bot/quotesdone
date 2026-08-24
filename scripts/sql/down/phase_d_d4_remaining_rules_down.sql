-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of scripts/sql/phase_d_d4_remaining_rules.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the row count below, accepts it, and runs it.
--
-- OBJECTS DROPPED, by name (never `cascade`):
--   public.phase_d_payment_state — state_key text primary key, rung int with
--   phase_d_payment_state_rung_key UNIQUE, meaning, authorizes_reveal boolean, why
--
-- ROW COUNT AT RISK (measured on htdblwldjkcgjvmqkbeh; WORKLIST D.1 item 17):
--   public.phase_d_payment_state   6 rows — the payment ladder BR-020 reads. Two other Phase D
--   objects consult it: the trigger fn_phase_d_stage_payment_state_declared() added by d20 raises
--   on any working_state that is not a rung here, and d20's own control block resolves
--   payment_transaction/reveal_transaction states from rungs 5 and 6. Dropping this table leaves
--   that trigger reading a table that does not exist, so it will raise on the next insert or
--   update of phase_d_fixture_stage.working_state. Run the d20 down first if that matters.
--
-- TWO DROP FUNCTIONs IN d4 ARE RECORDED HERE AND HAVE NO DOWN:
--   d4:78  drop function if exists public.fn_phase_d_reveal_permitted(bigint);
--          immediately followed at :79 by
--          create or replace function public.fn_phase_d_reveal_permitted(p_transaction_id text)
--          — a bigint -> text signature change, not a body edit. Measured: the bigint overload is
--          created by no file under scripts/sql/ (grep over the whole directory returns only this
--          drop line), so there is no predecessor definition to restore and the `if exists` was
--          defensive. Nothing to undo.
--   d4:149 drop function if exists public.fn_phase_d_rule_check(text, jsonb);
--          immediately followed by the create at :151. Same signature, so this is a body replace
--          in two statements. A replaced body has no down — see scripts/sql/down/README.md.
--   These were the only two DROP FUNCTION statements in the Phase D corpus when this file was
--   written. Re-measured over all 73 files on 2026-08-20 there are THREE: these two, plus
--   scripts/sql/phase_d_d48_a_two_context_probe_cannot_find_a_withheld_authority.sql:36, which is
--   the same shape as :78 above — a return-type change on public.fn_phase_d_rule_can_refuse(),
--   re-created at :38. It is d48's to record, not d4's, and it has no down either.
--
-- NOT TOUCHED: the two CREATE OR REPLACE FUNCTION bodies in d4.
-- =================================================================================================


drop table if exists public.phase_d_payment_state;

do $ctl$
begin
  if to_regclass('public.phase_d_payment_state') is not null then
    raise exception 'D4 down did not take: public.phase_d_payment_state is still present.';
  end if;

  raise notice 'D4 down: phase_d_payment_state is gone. The two DROP FUNCTIONs in d4 have no down and need none.';
end $ctl$;

