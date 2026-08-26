-- ROLLBACK for scripts/sql/phase_c_the_refund_guard_could_not_record_stripes_own_refund.sql
--
-- NO TRANSACTION CONTROL. One CREATE OR REPLACE, one DELETE, one assertion; rehearsable.
--
-- WHAT APPLYING THIS REOPENS, named rather than left to be discovered:
--
--   1. public.fn_refund_settle -- the Stripe webhook path -- can no longer record a refund this
--      platform did not issue. It inserts with no transaction_id and the restored guard refuses that
--      row with 23514 refund_names_no_payment, so our only record of real money leaving is dropped.
--      fn_phase_c_refund_execution_requires_decision keeps its own exemption for the same three
--      originators, so the two guards go back to disagreeing about what an external refund is.
--
--   2. The W17 refund effect loses transaction_id from its payload population, and
--      fn_phase_d_handler_execute writes a refund naming no payment again -- refused at W17-S01 with
--      pd_effect_check_violated, dispatches_executed 11 -> 5 in
--      PHASE_D_WORKFLOW_IMPLEMENTATION_RESULT.csv.
--
-- After applying this, run: node scripts/phase_d/build_fixture_catalogue.mjs
-- so the committed CSV stops naming a row that no longer exists.

create or replace function public.fn_refund_amount_is_the_fee_paid()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare t public.transactions%rowtype; v_expected bigint;
begin
  if NEW.transaction_id is null then
    raise exception 'refunds: a refund must name the transaction it reverses. transaction_id is null, so this row asserts money is owed without saying which payment it came from. (refund_names_no_payment)'
      using errcode = '23514',
            hint = 'Set transaction_id to the public.transactions row whose reveal_fee is being returned.';
  end if;

  select * into t from public.transactions where id = NEW.transaction_id;
  if not found then
    raise exception 'refunds: transaction % does not exist. (refund_transaction_absent)',
      NEW.transaction_id using errcode = '23503';
  end if;

  if t.reveal_fee is null or t.reveal_fee <= 0 then
    raise exception 'refunds: transaction % records no reveal fee (reveal_fee %), so there is nothing to give back. A refund of an unpaid reveal is a payment, not a refund. (refund_no_fee_was_paid)',
      NEW.transaction_id, coalesce(t.reveal_fee::text,'null') using errcode = '23514';
  end if;

  if t.refund_deadline is null then
    raise exception 'refunds: transaction % has no refund window. trg_reveal_window opens one at reveal, so a transaction without it was never revealed and no refund can be due yet. (refund_window_not_open)',
      NEW.transaction_id using errcode = '23514';
  end if;
  if now() < t.refund_deadline then
    raise exception 'refunds: the refund window on transaction % opens at % and it is now %. The customer waits the founder-set period of working days after the reveal before a refund can be claimed. (refund_window_not_yet_open)',
      NEW.transaction_id, t.refund_deadline, now() using errcode = '23514';
  end if;

  v_expected := round(t.reveal_fee * 100)::bigint;
  if NEW.amount_fils is not null and NEW.amount_fils <> v_expected then
    raise exception 'refunds: the amount must equal the reveal fee the customer actually paid on transaction % — expected % fils (AED %), got % fils (AED %). A refund figure is read off the payment, never typed. (refund_amount_is_not_the_fee_paid)',
      NEW.transaction_id, v_expected, round(t.reveal_fee,2), NEW.amount_fils, round(NEW.amount_fils/100.0,2)
      using errcode = '23514';
  end if;

  return NEW;
end
$function$;

delete from public.phase_d_fixture_catalogue where fixture_id = 'PDF-5003';

DO $assert$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.phase_d_fixture_catalogue WHERE fixture_id = 'PDF-5003';
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'PDF-5003 is still in the catalogue' USING errcode = '23514';
  END IF;
  RAISE NOTICE 'external-originator arm removed and PDF-5003 deleted';
END $assert$;
