-- THE CUSTOMER ASKS, AND THE CHAIN ACTUALLY STARTS.
--
-- The founder, 9 September 2026: "yea of course the customer always initiate the refund request...
-- and that is through the customer portal. which i know is not functioning at the moment but thats
-- the workflow."
--
-- I BUILT THE CHAIN FROM THE WRONG END. Earlier today I built supplier_response_watch, the
-- eligibility arithmetic and the CEO's approval gate as though the PLATFORM notices a silent
-- supplier and decides to refund. It does not, and never should: the customer is the one who knows
-- they have been left waiting, and only they can say so. The founder's correction is the whole
-- shape of the workflow, not a detail in it.
--
-- WHAT ACTUALLY EXISTS, MEASURED. The customer-facing entry point is already there and already
-- wired: CustomerPortal.tsx has a button, it calls customer_api {action:'request_refund'}, and that
-- action sets `transactions.refund_status = 'requested'`.
--
-- AND THAT IS WHERE IT STOPS. `transactions.refund_status` is a column on the sale. The chain built
-- today — eligibility, CEO approval, accountant execution, supplier penalty — operates on
-- `public.refunds` and `public.refund_case`. Nothing joins the two. So a customer could press the
-- button, the platform would say "your refund request has been received and will be reviewed", and
-- no case would exist for anyone to review. The promise in that sentence had no mechanism behind it.
--
-- This is the estate's two-parallel-refund-models defect showing up exactly where it costs most:
-- at the point a real customer asks for their money back.
--
-- WHAT THIS FILE DOES. One routine, called by customer_api at the moment the customer asks, that
-- opens the real case:
--
--   1. it refuses to open a case for a sale that was never paid, or is already refunded, or already
--      has a case open — a customer pressing twice must not create two claims on one payment
--   2. it carries the Stripe payment reference across, because fn_refund_amount_is_the_fee_paid
--      and fn_refund_execution_requires_ceo_approval both require it and would otherwise refuse
--      the refund later, after the customer had been told it was under review
--   3. it records WHO asked and WHEN, because the working-day clock the CEO decides on runs from
--      the reveal, and the request is the event that starts anyone looking
--   NOTE ON VOCABULARY: the table already has its own words, enforced by CHECK constraints, and
--   three of my first guesses were refused by them — amount_source must be one of five values
--   (in_platform_request, not reveal_fee), reason_code is supplier_unresponsive (not
--   supplier_nonresponse), and status is requested. The constraints are the schema telling me the
--   vocabulary rather than letting me invent a parallel one.
--
--   4. it opens the case at `requested` — NOT approved. Eligibility is still measured from
--      supplier_response_watch and the decision is still the CEO's. The customer asking is the
--      trigger, never the verdict.
--
-- WHAT IS STILL NOT TRUE, said plainly: the customer portal does not work today, so this path
-- cannot be exercised by a real person. The founder knows and said so. This makes the workflow
-- correct behind the button, so that fixing the portal is all that remains rather than fixing the
-- portal AND discovering the request went nowhere.

create or replace function public.fn_refund_open_from_customer(
  p_transaction_id uuid, p_requested_by text, p_reason_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare t record; v_id bigint; v_existing bigint;
begin
  select tr.*, q.supplier_id
    into t
    from public.transactions tr
    left join public.quotes q on q.id = tr.quote_id
   where tr.id = p_transaction_id;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no such transaction');
  end if;

  -- A sale that never took money cannot be refunded. Checked here rather than left to Stripe,
  -- because the customer is told something either way and it must be the truth.
  if coalesce(t.payment_ref, '') = '' then
    return jsonb_build_object('ok', false, 'reason',
      'this reveal has no recorded payment, so there is nothing to refund');
  end if;
  if t.revealed_at is null then
    return jsonb_build_object('ok', false, 'reason', 'this reveal has not completed');
  end if;

  -- ONE CLAIM PER PAYMENT. A customer pressing the button twice, or a retry, must not open a
  -- second case — two cases on one payment is how one refund gets paid twice.
  select id into v_existing from public.refunds
   where transaction_id = p_transaction_id
     and status not in ('rejected', 'failed', 'cancelled')
   order by id limit 1;
  if v_existing is not null then
    return jsonb_build_object('ok', true, 'duplicate', true, 'refund_id', v_existing,
      'note', 'A refund request already exists for this reveal and is being reviewed.');
  end if;

  insert into public.refunds
    (transaction_id, quote_id, inquiry_id, customer_id, supplier_lead_id,
     stripe_payment_intent, amount_fils, currency, reason_code, reason_note,
     status, requested_by, requested_at, amount_source)
  values
    (p_transaction_id, t.quote_id, t.inquiry_id, t.customer_id, t.supplier_id,
     t.payment_ref,
     round(coalesce(t.reveal_fee, 0) * 100)::bigint, 'AED',
     'supplier_unresponsive',
     coalesce(p_reason_note, 'The customer reported that the revealed supplier has not responded.'),
     'requested', coalesce(p_requested_by, 'customer'), now(), 'in_platform_request')
  returning id into v_id;

  return jsonb_build_object('ok', true, 'refund_id', v_id,
    'status', 'requested',
    'next', 'customer_support checks whether the supplier ever answered; the CEO decides on that '
         || 'record; the accountant pays and raises the supplier penalty. The customer asking is '
         || 'the trigger, not the verdict.');
end $fn$;
revoke execute on function public.fn_refund_open_from_customer(uuid, text, text) from public, anon, authenticated;

do $do$
declare
  v_cust uuid; v_lead bigint; v_tx uuid; v jsonb; v2 jsonb; v_id bigint;
begin
  select id into v_lead from public.leads limit 1;
  if v_lead is null then raise exception 'POSITIVE CONTROL FAILED: no lead to stand in as the supplier'; end if;

  -- REFUSALS FIRST, on things that cannot exist.
  v := public.fn_refund_open_from_customer(gen_random_uuid(), 'customer');
  if (v->>'ok')::boolean then raise exception 'opened a case for a transaction that does not exist'; end if;

  insert into public.customers (id, email, email_verified, full_name)
  values (gen_random_uuid(), 'zz-demo-refund-probe@example.invalid', true, 'ZZ DEMO refund probe')
  returning id into v_cust;

  -- A sale with no payment reference must be refused.
  -- REVEALED THREE WEEKS AGO, not now. An existing CHECK on public.refunds refuses a claim before
  -- the supplier's response window has run — it caught the first version of this probe with
  -- "the refund window on transaction ... opens at 2026-09-16 and it is now 2026-09-09". That guard
  -- is the founder's own policy already enforced at the table, and it is worth recording that it
  -- exists: a customer cannot claim before the supplier has had the days the terms give them.
  v_tx := gen_random_uuid();
  insert into public.transactions (id, customer_id, supplier_id, revealed_at, reveal_fee)
  values (v_tx, v_cust, v_lead, now() - interval '21 days', 300);
  v := public.fn_refund_open_from_customer(v_tx, 'customer');
  if (v->>'ok')::boolean then raise exception 'opened a case on a reveal with no recorded payment'; end if;

  -- Now give it a payment and it must open exactly one case.
  update public.transactions set payment_ref = 'pi_ZZDEMO_probe' where id = v_tx;
  v := public.fn_refund_open_from_customer(v_tx, 'customer', 'ZZ DEMO probe');
  if not (v->>'ok')::boolean then raise exception 'refused a legitimate request: %', v->>'reason'; end if;
  v_id := (v->>'refund_id')::bigint;

  -- It must open at REQUESTED, never approved. The customer asking is not the decision.
  if (select status from public.refunds where id = v_id) <> 'requested' then
    raise exception 'the case did not open at requested';
  end if;
  -- And it must carry the Stripe reference, or the guards refuse it later — after the customer has
  -- been told it is under review.
  if (select stripe_payment_intent from public.refunds where id = v_id) is distinct from 'pi_ZZDEMO_probe' then
    raise exception 'the Stripe payment reference did not carry across';
  end if;

  -- PRESSING TWICE must not open a second claim on one payment.
  v2 := public.fn_refund_open_from_customer(v_tx, 'customer');
  if (v2->>'refund_id')::bigint <> v_id then
    raise exception 'a second request opened case % as well as %', v2->>'refund_id', v_id;
  end if;
  if (select count(*) from public.refunds where transaction_id = v_tx) <> 1 then
    raise exception 'two refund rows exist for one payment';
  end if;

  delete from public.refunds where transaction_id = v_tx;
  delete from public.notifications where to_email = 'zz-demo-refund-probe@example.invalid';
  delete from public.transactions where id = v_tx;
  delete from public.customers where id = v_cust;
  if exists (select 1 from public.refunds where transaction_id = v_tx) then
    raise exception 'the probe left a refund behind';
  end if;

  raise notice 'THE CUSTOMER CAN NOW START IT. Refused: unknown sale, and a reveal with no payment. Opened exactly one case at status=requested carrying the Stripe reference, and a second press returned the same case rather than a second claim. Probe removed. The portal button still needs the portal to work.';
end
$do$;
