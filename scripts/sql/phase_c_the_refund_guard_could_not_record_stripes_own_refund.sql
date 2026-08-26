-- THE REFUND GUARD COULD NOT RECORD STRIPE'S OWN REFUND.
--
-- NO TRANSACTION CONTROL. One CREATE OR REPLACE, one INSERT, one assertion block; rehearsable.
--
-- ================================================================================================
-- TWO THINGS THE AMOUNT GUARD BROKE, BOTH FOUND BY DRIVING IT
-- ================================================================================================
--
-- 1. THE WEBHOOK CANNOT RECORD MONEY THAT ALREADY LEFT.
--
-- public.fn_refund_settle is the Stripe webhook path. It records a refund issued outside this
-- platform -- from the Stripe dashboard or API -- and it inserts with NO transaction_id, because
-- there may not be one: the row exists to say "real money left, here is the Stripe id". Since
-- phase_c_a_refund_amount_was_a_number_somebody_typed.sql, a00_refund_amount_is_the_fee_paid
-- refuses exactly that row with 23514 refund_names_no_payment.
--
-- The estate already knew this distinction and had already written it down. Two files away,
-- fn_phase_c_refund_execution_requires_decision exempts the same three originators, with the reason
-- stated in its own body:
--
--   "A refund Stripe already issued is a FACT to be recorded, not a request to be approved;
--    refusing the row would delete our only record of real money leaving, which is worse than
--    admitting it."
--
-- The amount guard was written without that arm. It gets it now, with the SAME list read the same
-- way (lower(requested_by) against stripe_webhook, stripe_dashboard, stripe), so the two guards
-- cannot drift into disagreeing about what an external refund is.
--
-- NOTHING IS LOOSENED FOR A REFUND THIS PLATFORM ISSUES. For every other originator all four rules
-- stand: a transaction must be named, it must be revealed and carry a reveal_fee, the amount must
-- equal round(reveal_fee*100), and the founder's window of working days must have passed.
-- fn_kernel_refund_ledger_state counts externally-originated refunds separately and has never
-- counted them as founder-approved.
--
-- 2. THE W17 HANDLER WROTE A REFUND THAT NAMED NO PAYMENT, AND NOW SAYS SO.
--
-- Measured in the aborted-transaction drive of PHASE_D_WORKFLOW_IMPLEMENTATION_RESULT.csv:
--
--   W17-S01  pd_effect_check_violated
--            "refunds: a refund must name the transaction it reverses. transaction_id is null, so
--             this row asserts money is owed without saying which payment it came from."
--   dispatches_executed 11 -> 5
--
-- That is the guard catching real handler behaviour, not a fixture artefact: the effect payload for
-- a refund carried no transaction at all. fn_phase_d_fixture_effect_payload builds its population
-- from the columns the target relation DEMANDS -- mapped, NOT NULL, no default -- plus the keys the
-- committed catalogue names for that step or workflow. public.refunds.transaction_id is nullable at
-- the column level (it must stay nullable; see part 1), so it was in neither set and the handler
-- never had it to write.
--
-- The catalogue is the declared mechanism for exactly this: a key the relation needs that its NOT
-- NULL columns do not announce. One row is added, scoped to W17. THE VALUE IN IT CANNOT FABRICATE A
-- LINK: the resolver asks fn_phase_d_step_context first and public.phase_d_context_key_object
-- second, where transaction_id already IDENTIFIES payment_transaction, so a real drive resolves the
-- transaction the scenario actually created. The committed value is a uuid that names no row, so if
-- both of those ever fail to resolve, the write is refused by the foreign key rather than quietly
-- pointing a refund at something plausible. A constant may not be an identity, and this one cannot
-- become one.
--
-- ROLLBACK: scripts/sql/down/phase_c_the_refund_guard_could_not_record_stripes_own_refund_down.sql

create or replace function public.fn_refund_amount_is_the_fee_paid()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  t public.transactions%rowtype;
  v_expected bigint;
  -- The same three originators fn_phase_c_refund_execution_requires_decision names, read the same
  -- way. A refund Stripe already issued is a fact to be recorded, not a request to be approved.
  v_external constant text[] := array['stripe_webhook','stripe_dashboard','stripe'];
begin
  if lower(coalesce(NEW.requested_by,'')) = any(v_external) then
    return NEW;
  end if;

  if NEW.transaction_id is null then
    raise exception 'refunds: a refund must name the transaction it reverses. transaction_id is null, so this row asserts money is owed without saying which payment it came from. (refund_names_no_payment)'
      using errcode = '23514',
            hint = 'Set transaction_id to the public.transactions row whose reveal_fee is being returned. A refund this platform did not issue is recorded through fn_refund_settle with requested_by stripe_webhook, and that path is exempt.';
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

-- THE KEY THE RELATION NEEDS AND ITS COLUMNS DO NOT ANNOUNCE. Scoped to W17, because that is the
-- workflow whose steps write a refund. fixture_id is NOT NULL with no default and is assigned by
-- hand here, continuing the PDF-5xxx block this session's rows use.
insert into public.phase_d_fixture_catalogue
  (fixture_id, workflow_id, step_id, scope, field_key, value, value_kind, expected_schema,
   expected_result, prohibited_external_use, marker_exemption)
select 'PDF-5003', 'W17', null, 'EFFECT_PAYLOAD', 'transaction_id',
       to_jsonb('00000000-0000-4000-8000-000000000000'::text), 'text',
       'the payment a refund reverses; public.refunds.transaction_id is nullable at the column '
    || 'level so that fn_refund_settle can record a refund Stripe issued, but every '
    || 'platform-originated refund must name one (a00_refund_amount_is_the_fee_paid). RESOLVED, '
    || 'NOT READ: fn_phase_d_fixture_effect_payload asks fn_phase_d_step_context and then '
    || 'phase_d_context_key_object, where transaction_id IDENTIFIES payment_transaction. The value '
    || 'here is a uuid that names no row, so a drive that failed to resolve the real transaction is '
    || 'refused by the foreign key instead of pointing a refund at something plausible.',
       'the refund effect names the payment it reverses instead of writing transaction_id null, '
    || 'which a00_refund_amount_is_the_fee_paid refuses',
       'Never send to a customer, a supplier or Stripe. The refund is written inside a transaction '
    || 'that is aborted, and no money moves on any Phase D drive.',
       'transaction_id is a uuid foreign key; a text marker cannot be stored in it. The all-zero '
    || 'uuid is deliberately unresolvable, so the value can never stand in for a real payment.'
where not exists (
  select 1 from public.phase_d_fixture_catalogue c
   where c.scope = 'EFFECT_PAYLOAD' and c.field_key = 'transaction_id'
     and c.workflow_id = 'W17' and c.step_id is null);

-- ================================================================================================
-- SELF-VERIFICATION. Every case is its own subtransaction and the accepted ones end in a deliberate
-- raise, so nothing survives this file.
-- ================================================================================================
do $verify$
declare log text := ''; ok boolean := true; v_txn uuid; v_n int;
begin
  -- 1. THE WEBHOOK PATH. A refund Stripe already issued, naming no transaction, must be recorded.
  begin
    insert into public.refunds (stripe_refund_id, amount_fils, amount_source, reason_code,
                                reason_note, requested_by, status, decided_by, decided_at)
    values ('re_zz_verify_'||txid_current()::text, 700, 'webhook_event', 'other',
            'ZZ DEMO — verification of the external-originator arm', 'stripe_webhook', 'processing',
            'stripe_dashboard', now());
    log := log || 'STRIPE_ISSUED_REFUND=RECORDED ';
    raise exception 'ROLLBACK_THIS_CASE';
  exception when others then
    if sqlerrm <> 'ROLLBACK_THIS_CASE' then
      log := log || 'STRIPE_ISSUED_REFUND=REFUSED(' || sqlstate || ':' || left(sqlerrm,80) || ')(WRONG) ';
      ok := false;
    end if;
  end;

  -- 2. AND NOTHING ELSE IS LOOSENED. The same row from a platform originator is still refused.
  begin
    insert into public.refunds (amount_fils, reason_code, reason_note, requested_by, status)
    values (700, 'other', 'ZZ DEMO — verification', 'zz-verify@example.invalid', 'requested');
    log := log || 'PLATFORM_REFUND_WITH_NO_PAYMENT=ACCEPTED(WRONG) '; ok := false;
    raise exception 'ROLLBACK_THIS_CASE';
  exception when others then
    if sqlerrm = 'ROLLBACK_THIS_CASE' then null;
    else log := log || 'PLATFORM_REFUND_WITH_NO_PAYMENT=REFUSED(' || sqlstate || ') '; end if;
  end;

  -- 3. AND THE AMOUNT RULE STILL BITES ON A REAL PAYMENT.
  begin
    insert into public.transactions (id, revealed_at, reveal_fee, fee_status, paid_by, payment_ref)
    values (gen_random_uuid(), now() - interval '60 days', 10.00, 'paid','customer','verify:external')
    returning id into v_txn;
    insert into public.refunds (transaction_id, amount_fils, reason_code, requested_by, status,
                                requested_at, within_auto_window)
    values (v_txn, 999, 'other', 'zz-verify@example.invalid', 'requested', now(), false);
    log := log || 'WRONG_AMOUNT_ON_A_REAL_PAYMENT=ACCEPTED(WRONG) '; ok := false;
    raise exception 'ROLLBACK_THIS_CASE';
  exception when others then
    if sqlerrm = 'ROLLBACK_THIS_CASE' then null;
    else log := log || 'WRONG_AMOUNT_ON_A_REAL_PAYMENT=REFUSED(' || sqlstate || ') '; end if;
  end;

  -- 4. The catalogue key exists exactly once for W17 and is scoped, not global.
  select count(*) into v_n from public.phase_d_fixture_catalogue c
   where c.scope = 'EFFECT_PAYLOAD' and c.field_key = 'transaction_id'
     and c.workflow_id = 'W17' and c.step_id is null;
  log := log || format('W17_TRANSACTION_ID_KEY=%s ', v_n);
  if v_n <> 1 then ok := false; end if;

  if not ok then
    raise exception 'EXTERNAL_REFUND_ARM_FAILED | %', log using errcode = '23514';
  end if;
  raise notice 'EXTERNAL_REFUND_ARM_VERIFIED | %', log;
end
$verify$;
