-- A REFUND AMOUNT WAS A NUMBER SOMEBODY TYPED.
--
-- NO TRANSACTION CONTROL. Two CREATE OR REPLACE, two triggers, one assertion block; rehearsable.
--
-- ================================================================================================
-- THE FOUNDER'S RULE, IN HIS WORDS, 26 AUG 2026
-- ================================================================================================
--
--   "how could you issue a random refund figure? it should be exactly equal to the amount of the 3%
--    the customer paid. and currently we have none, so the system shouldnt even allow it"
--
-- He said it after reading the evidence from the PCCR-007 probe, which had created a refund request
-- for "AED 10.00" against nothing at all. He was right, and the figure was not the point — the point
-- is that nothing anywhere required it to be any particular figure.
--
-- ================================================================================================
-- WHAT WAS MEASURED, BEFORE THE RULE WAS WRITTEN
-- ================================================================================================
--
--   public.refunds.transaction_id     nullable, FOREIGN KEY ... ON DELETE SET NULL
--   refunds_amount_fils_check         CHECK (amount_fils IS NULL OR amount_fils > 0)
--   fn_kernel_refund_decision_record  never reads an amount at all — the string 'amount' does not
--                                     appear in its body
--   public.transactions               0 rows
--
-- So: a refund could name no payment, carry any positive number, and be approved by a service that
-- never looked at the money. And with zero transactions in the estate there was no payment any
-- refund could correspond to, yet a refund request was still creatable — which is exactly the third
-- thing he said.
--
-- ================================================================================================
-- THE RULE, ENFORCED WHERE THE MONEY IS
-- ================================================================================================
--
-- public.transactions.reveal_fee is what the customer actually paid. It is the only figure in the
-- estate that is a fact about a payment rather than an intention, so it is the one a refund must
-- equal. Two guards, both BEFORE triggers on the tables themselves, so no service can route around
-- them:
--
--   1. a00_refund_amount_is_the_fee_paid on public.refunds
--        · transaction_id is REQUIRED. A refund reverses a payment; a refund that names no payment
--          is not a refund.
--        · the transaction must be revealed and its reveal_fee must be set — an unpaid reveal has
--          nothing to give back.
--        · amount_fils, when given, must EQUAL round(reveal_fee * 100). Not less, not more.
--        · Consequence, and it is the founder's third sentence made true: with public.transactions
--          empty, no refund row can be created at all.
--
--   2. a00_founder_approval_names_a_real_refund on public.founder_approval_request
--        · a refund_decision request must name a refunds row that exists, as
--          'refund:<id>'. The OS inbox is where he decides; an item in it that points at no refund
--          is a decision about nothing. The PCCR-007 probe put 'refund:zz-audit-probe' there and it
--          was accepted.
--
-- WHAT THIS DELIBERATELY DOES NOT DO. It does not compute 3% of anything. The percentage is his to
-- set and it is applied when the reveal fee is charged; by the time a refund exists the amount has
-- already been decided and recorded on the transaction. A guard that recomputed the percentage here
-- would be a second opinion about a number that is already a fact, and the two would drift.
--
-- NOTHING IS GRANDFATHERED, because there is nothing to grandfather: public.refunds holds 0 rows and
-- public.phase_c_refund_decision holds 0 rows. Measured immediately before this file was written.

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

  -- THE THREE WORKING DAYS, ENFORCED WHERE THE MONEY IS.
  -- His words, 26 Aug 2026: "only the option of refund is clickable after the period of 3 working
  -- days". That period already exists and is already correct: trg_reveal_window sets
  -- refund_deadline := fn_add_working_days(revealed_at, decision_policy 'refund_call_after_working_days'
  -- default 3) and opens the window at reveal. What was missing is that nothing refused a refund
  -- raised before it — fn_refund_request RECORDS whether the request arrived in window and does not
  -- act on it, so the rule lived in a column and in the UI rather than at the boundary.
  -- A UI that hides a button is a courtesy; this is the rule.
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

drop trigger if exists a00_refund_amount_is_the_fee_paid on public.refunds;
create trigger a00_refund_amount_is_the_fee_paid
  before insert or update on public.refunds
  for each row execute function public.fn_refund_amount_is_the_fee_paid();

create or replace function public.fn_founder_approval_names_a_real_refund()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare v_id bigint;
begin
  if NEW.action_class is distinct from 'refund_decision' then
    return NEW;
  end if;
  v_id := nullif(regexp_replace(coalesce(NEW.subject_ref,''), '^refund:', ''), '')::bigint;
  if v_id is null or not exists (select 1 from public.refunds r where r.id = v_id) then
    raise exception 'founder_approval_request: subject_ref % names no refund. A refund decision he is asked to make must point at a refund that exists, as refund:<id>. An inbox item that points at nothing is a decision about nothing. (founder_approval_subject_absent)',
      coalesce(NEW.subject_ref,'(null)') using errcode = '23503';
  end if;
  return NEW;
exception when invalid_text_representation then
  raise exception 'founder_approval_request: subject_ref % is not of the form refund:<id>. (founder_approval_subject_malformed)',
    coalesce(NEW.subject_ref,'(null)') using errcode = '22023';
end
$function$;

drop trigger if exists a00_founder_approval_names_a_real_refund on public.founder_approval_request;
create trigger a00_founder_approval_names_a_real_refund
  before insert or update on public.founder_approval_request
  for each row execute function public.fn_founder_approval_names_a_real_refund();

revoke execute on function public.fn_refund_amount_is_the_fee_paid() from public;
revoke execute on function public.fn_founder_approval_names_a_real_refund() from public;

-- ================================================================================================
-- SELF-VERIFICATION. Each case is its own subtransaction; the file raises only when a case behaves
-- wrongly, because an abort would take the DDL with it.
-- ================================================================================================
do $verify$
declare log text := ''; ok boolean := true; v bigint;
begin
  -- 1. The founder's third sentence: with no transactions, no refund may be created.
  begin
    insert into public.refunds (currency, reason_code, status, requested_by, requested_at,
                                within_auto_window, amount_fils)
    values ('AED','goodwill','requested','zz-verify@example.invalid', now(), false, 1000)
    returning id into v;
    log := log || 'REFUND_WITH_NO_TRANSACTION=ACCEPTED(WRONG) '; ok := false;
  exception when others then
    log := log || 'REFUND_WITH_NO_TRANSACTION=REFUSED(' || sqlstate || ') ';
  end;

  -- 2. A refund naming a transaction that does not exist.
  begin
    insert into public.refunds (currency, reason_code, status, requested_by, requested_at,
                                within_auto_window, amount_fils, transaction_id)
    values ('AED','goodwill','requested','zz-verify@example.invalid', now(), false, 1000,
            '00000000-0000-4000-8000-00000000dead')
    returning id into v;
    log := log || 'REFUND_WITH_UNKNOWN_TRANSACTION=ACCEPTED(WRONG) '; ok := false;
  exception when others then
    log := log || 'REFUND_WITH_UNKNOWN_TRANSACTION=REFUSED(' || sqlstate || ') ';
  end;

  -- 3. The OS inbox may not carry a refund decision that points at nothing.
  begin
    insert into public.founder_approval_request
      (action_class, subject_ref, prepared_by_role_id, amount_note, evidence, state, decision_note, created_at)
    values ('refund_decision','refund:zz-not-a-refund','payments_and_billing_manager','AED 10.00',
            '{}'::jsonb,'pending','self-verification', now());
    log := log || 'INBOX_ITEM_POINTING_AT_NOTHING=ACCEPTED(WRONG) '; ok := false;
  exception when others then
    log := log || 'INBOX_ITEM_POINTING_AT_NOTHING=REFUSED(' || sqlstate || ') ';
  end;

  log := log || '| refunds=' || (select count(*) from public.refunds)
             || ' approval_requests=' || (select count(*) from public.founder_approval_request)
             || ' transactions=' || (select count(*) from public.transactions) || ' ';

  if not ok then
    raise exception 'REFUND_AMOUNT_GUARD_FAILED | %', log using errcode = '23514';
  end if;
  raise notice 'REFUND_AMOUNT_GUARD_VERIFIED | %', log;
end
$verify$;
