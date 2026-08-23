-- G06 — a committed monetary state that names no rung of the ladder it is judged against
--
-- G04 moved BR-033 off the generic object-record vocabulary and onto public.phase_d_payment_state,
-- the six-rung ladder that public.transactions.fee_status actually holds. Re-measured immediately
-- afterwards, W17 and W27 fell from 4 and 5 business effects to 0, both refusing at S01 with:
--
--   "BR-033: monetary state reconciled matches 0 reconciled rung(s) of the payment ladder
--    public.phase_d_payment_state (2 of its 6 rungs are reconciled: payment_reconciled,
--    reveal_authorized)"
--
-- THE RULE IS RIGHT AND THE FIXTURE IS WRONG, which is why this file corrects the fixture rather
-- than relaxing the rule. `reconciled` is a word from the generic TRANSACTION_RECORD family
-- lifecycle. It is not a rung. No transaction in this estate has ever carried it as a fee_status,
-- and BR-020 — the other rule about the same transaction — would refuse it as "not a declared
-- payment state. Refusing rather than guessing which rung it means."
--
-- So PDF-0009 was a committed constant that passed the old BR-033 for the same reason the old
-- BR-033 was wrong: both were reading the register that does not model money. The value becomes
-- payment_reconciled, which is what the fixture scenario's own transaction is written at (stage 190,
-- working_state payment_reconciled, itself enforced by trg on phase_d_fixture_stage), and what
-- rung 5 of the ladder describes as "the founder-approved bar in BR-020".
--
-- AND THE REASON IT COULD DRIFT IS THAT NOTHING WAS KEEPING THE TWO IN STEP. public.phase_d_fixture_stage
-- has carried a11_phase_d_stage_payment_state_declared since D9 — a stage may not declare a
-- working_state that is not a rung. The CATALOGUE, which supplies the same key to the same rule
-- when the run's own object is not a transaction, had no such guard. It has one now, in the same
-- shape and with the same message, so a monetary state committed in either place is a rung or it
-- is refused at write time rather than discovered by a workflow that stops producing effects.
--
-- ROLLBACK: `update public.phase_d_fixture_catalogue set value = '"reconciled"'::jsonb where
-- fixture_id = 'PDF-0009'` plus `drop trigger a11_phase_d_catalogue_payment_state_declared on
-- public.phase_d_fixture_catalogue`. The checksum column recomputes itself from the content on
-- every write, so no digest has to be restored by hand.

CREATE OR REPLACE FUNCTION public.fn_phase_d_catalogue_payment_state_declared()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- Only the key that names a monetary state. Every other fixture is untouched.
  if NEW.field_key = 'monetary_state'
     and not exists (select 1 from public.phase_d_payment_state s
                      where s.state_key = (NEW.value #>> '{}')) then
    raise exception 'phase_d_fixture_catalogue: % commits monetary_state %, which is not a rung of public.phase_d_payment_state. BR-020 and BR-033 both read that ladder; a money state outside it is not a state. (pd_catalogue_payment_state_undeclared)',
      NEW.fixture_id, coalesce(NEW.value #>> '{}', '(null)') using errcode = '23514';
  end if;
  return NEW;
end
$function$;

drop trigger if exists a11_phase_d_catalogue_payment_state_declared on public.phase_d_fixture_catalogue;
create trigger a11_phase_d_catalogue_payment_state_declared
  before insert or update on public.phase_d_fixture_catalogue
  for each row execute function public.fn_phase_d_catalogue_payment_state_declared();

update public.phase_d_fixture_catalogue
   set value = '"payment_reconciled"'::jsonb,
       expected_schema = 'a state_key present in public.phase_d_payment_state whose authorizes_reveal is true',
       expected_result = 'BR-033 passes: the monetary state is a declared rung of the payment ladder and it is a reconciled one, so it is neither unknown nor unreconciled',
       marker_exemption = 'BR-020 and BR-033 both resolve this value against public.phase_d_payment_state.state_key. An embedded marker resolves to no rung, so the rules would fail for the marker rather than for the money.'
 where fixture_id = 'PDF-0009' and field_key = 'monetary_state';
