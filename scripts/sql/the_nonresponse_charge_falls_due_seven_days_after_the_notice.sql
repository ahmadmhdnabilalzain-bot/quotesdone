-- THE NON-RESPONSE CHARGE FALLS DUE SEVEN DAYS AFTER THE NOTICE (24 Sep 2026, accountant).
--
-- Supplier Agreement clause 33 (v10 to v13, unchanged): the charge is "payable within seven (7) days of QuotesDone's
-- notice (the due date)". supplier_charge.ts (the invoice, reminders, demand and court claim) already counts from
-- the notice. fn_accountant_nonresponse_charge counted from the REFUND SETTLING, and fn_accountant_raise_nonresponse_charge
-- wrote that date into supplier_dues.due_date, so the books, the chase and the court papers could disagree and
-- interest could run before the supplier had been told anything.
--
-- DECISION: the code follows the clause, not the other way round. Counting from the notice is the safer reading for
-- the supplier (it is never in default before it is told) and the more enforceable one for QuotesDone (a demand
-- for a debt the debtor was not notified of is the first thing the supplier's lawyer attacks, and the notice is the
-- evidence the payment-order claim relies on). Changing the clause to "from the refund" would have needed another
-- signed version and made a supplier liable for interest on a debt it could not have known about.
--
-- WHAT THIS CHANGES
--   fn_accountant_nonresponse_charge   due date = Dubai date the notice was DELIVERED (customer_support's delivery of
--                                       nonresponse_charge or charge_corrected for this due, done, delivered) + the
--                                       policy's 7 days; before delivery, today + 7 (provisional, no interest). Names
--                                       its basis in 'due_basis'. Otherwise the body of
--                                       the_administrative_fee_is_the_one_the_supplier_signed.sql, applied BEFORE this.
--   fn_supplier_dues_accrue_interest   also moves supplier_dues.due_date / due_date_30 to the computed date, so the
--                                       chase follows the notice. Otherwise the live body (a_reversed_supplier_charge_is_never_owed.sql).
-- Both are CREATE OR REPLACE of existing routines, so their ACLs (already closed to the browser roles) are kept.
--
--   node scripts/apply_sql.mjs scripts/sql/the_nonresponse_charge_falls_due_seven_days_after_the_notice.sql --apply --ddl

create or replace function public.fn_accountant_nonresponse_charge(p_transaction_id uuid, p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t public.transactions; c public.pricing_config; v_n int; v_sum bigint;
  v_refunded numeric; v_approved numeric; v_base numeric; v_settled timestamptz; v_src text;
  v_cap numeric; v_apr numeric; v_due_days int; v_due date; v_as_of date; v_days int; v_int numeric;
  v_ver text; v_acc timestamptz; v_fee numeric; v_fee_basis text; v_due_id bigint; v_notice timestamptz; v_due_basis text;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such transaction'); end if;

  -- THE REFUND RECORD: every refund Stripe settled against this payment, summed (a top-up the CEO's
  -- playbook issued is part of what the customer got back), dated from the FIRST settlement so a
  -- top-up does not move the due date. The approved amount caps it, so a duplicate or an over-refund
  -- is the company's loss and never a larger charge on the supplier.
  select count(*), sum(x.amount_fils), min(coalesce(x.settled_at, x.updated_at)),
         string_agg(coalesce(x.stripe_refund_id, 'refunds #' || x.id), ', ' order by x.id)
    into v_n, v_sum, v_settled, v_src
    from public.refunds x
   where x.status = 'succeeded' and x.amount_fils is not null
     and (x.transaction_id = p_transaction_id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref));
  select a.amount_aed into v_approved
    from public.refunds x join public.ceo_approval a on a.decision_id = x.refund_decision_id
   where x.transaction_id = p_transaction_id and a.decision = 'approved' order by x.id desc limit 1;
  if v_n > 0 then
    v_refunded := round(v_sum / 100.0, 2);
    v_src      := v_n || ' settled refund(s): ' || v_src;
  elsif t.refund_amount_aed is not null and coalesce(t.refund_status, '') in ('refunded', 'succeeded') then
    v_refunded := round(t.refund_amount_aed, 2);
    v_settled  := coalesce(t.refund_confirmed_at, t.refund_resolved_at);
    v_src      := 'transactions.refund_amount_aed (Stripe ' || coalesce(t.refund_stripe_id, 'reference not recorded') || ')';
  else
    return jsonb_build_object('ok', false, 'reason', 'no settled refund on this transaction, so there is nothing to recover from the supplier');
  end if;
  if v_settled is null then
    return jsonb_build_object('ok', false, 'reason', 'the refund carries no settlement time, so the charge''s due date cannot be set');
  end if;

  v_approved := coalesce(v_approved, t.total_charged, t.reveal_fee, v_refunded);
  v_base     := least(v_refunded, v_approved);

  select * into c from public.pricing_config order by id limit 1;
  v_cap      := (select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'supplier_charge_max_lawful_apr');
  v_apr      := least(c.supplier_nonresponse_interest_apr, coalesce(v_cap, c.supplier_nonresponse_interest_apr));
  v_due_days := coalesce((select (d.value #>> '{}')::int from public.decision_policy d where d.key = 'supplier_charge_due_days'), 7);
  -- 24 SEP 2026 (accountant): CLAUSE 33 SAYS THE CHARGE IS PAYABLE "within seven (7) days of QuotesDone's notice".
  -- This used to count from the refund settling, which could put a supplier in default before it was ever told:
  -- unfair to the supplier and the weak point of any claim (no notice, no default). The due date is now seven
  -- days after the notice was DELIVERED (customer_support's delivery of nonresponse_charge for this due, status done,
  -- evidence delivered). Until it is delivered the due date is seven days from today, so no interest can accrue.
  select d.id into v_due_id from public.supplier_dues d
   where d.transaction_id = p_transaction_id and coalesce(d.status, '') <> 'cancelled' order by d.id limit 1;
  if v_due_id is not null then
    select min(a.decided_at) into v_notice from public.agent_actions a
     where a.kind = 'handoff' and a.agent = 'customer_support' and a.status = 'done'
       and a.target_id in ('delivery.request:nonresponse_charge:' || v_due_id, 'delivery.request:charge_corrected:' || v_due_id)
       and coalesce((a.evidence->>'delivered')::boolean, false);
  end if;
  if v_notice is not null then
    v_due       := (greatest(v_notice, v_settled) at time zone 'Asia/Dubai')::date + v_due_days;
    v_due_basis := 'notice delivered ' || to_char(v_notice at time zone 'Asia/Dubai', 'YYYY-MM-DD') || ' (Dubai) + ' || v_due_days || ' days, clause 33';
  else
    v_due       := greatest((v_settled at time zone 'Asia/Dubai')::date, (now() at time zone 'Asia/Dubai')::date) + v_due_days;
    v_due_basis := 'notice not yet delivered: provisional, today + ' || v_due_days || ' days; it moves to the delivery date + ' || v_due_days || ' when the notice is delivered';
  end if;
  v_as_of    := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  v_days     := greatest(v_as_of - v_due, 0);
  -- 23 SEP 2026 (ceo): Supplier Agreement v13 clause 33(b) raised the administrative fee (company_facts.json
  -- nonresponse_admin_fee_aed). The fee is the one the supplier had SIGNED when the customer revealed it: v13 or
  -- later accepted at or before the reveal -> decision_policy.supplier_nonresponse_admin_fee_from_v13_aed; anything
  -- else (v12 or earlier, v13 accepted after the reveal, unknown dates) -> pricing_config's AED 250 of clauses v6-v12.
  -- Never retroactive. supplier_charge.ts adminFeeAed() is the same rule for the documents.
  select l.accepted_terms_version, l.accepted_terms_at into v_ver, v_acc from public.leads l where l.id = t.supplier_id;
  if coalesce(nullif(regexp_replace(coalesce(v_ver, ''), '\D', '', 'g'), '')::int, 0) >= 13
     and v_acc is not null and t.revealed_at is not null and v_acc <= t.revealed_at then
    v_fee := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'supplier_nonresponse_admin_fee_from_v13_aed'), c.supplier_nonresponse_admin_fee_aed);
    v_fee_basis := 'Supplier Agreement ' || v_ver || ' clause 33(b), accepted ' || v_acc || ' before the reveal';
  else
    v_fee := c.supplier_nonresponse_admin_fee_aed;
    v_fee_basis := 'Supplier Agreement ' || coalesce(v_ver, '(no version recorded)') || ' clause 33(b) as signed before this reveal';
  end if;
  v_int      := round((v_base + v_fee) * v_apr * v_days / 365.0, 2);

  return jsonb_build_object(
    'ok', true, 'transaction_id', t.id, 'supplier_id', t.supplier_id,
    'refunded_aed', v_base, 'actually_refunded_aed', v_refunded, 'approved_aed', v_approved, 'refund_source', v_src,
    'admin_fee_aed', v_fee, 'admin_fee_basis', v_fee_basis,
    'interest_apr', v_apr, 'interest_apr_configured', c.supplier_nonresponse_interest_apr, 'interest_apr_lawful_max', v_cap,
    'due_date', v_due, 'due_basis', v_due_basis, 'as_of', v_as_of, 'interest_days', v_days, 'interest_aed', v_int,
    'total_aed', round(v_base + v_fee + v_int, 2),
    'basis', 'base = the amount refunded to the customer, read from the refund record and capped at the amount the CEO approved; '
          || '+ the administration fee of the agreement version the supplier had signed at the reveal; + simple interest on (base + admin fee) at the lower of pricing_config''s APR and '
          || 'the lawful maximum, from the due date (' || v_due_days || ' days after the notice was delivered, clause 33) to the as-of date. Nothing is typed.');
end $function$;

create or replace function public.fn_supplier_dues_accrue_interest(p_as_of date DEFAULT NULL::date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare x record; v jsonb; n int := 0;
begin
  for x in select id, transaction_id from public.supplier_dues
            where public.fn_supplier_due_is_owed(status, paid_at) and transaction_id is not null loop
    v := public.fn_accountant_nonresponse_charge(x.transaction_id, p_as_of);
    continue when not coalesce((v->>'ok')::boolean, false);
    update public.supplier_dues
       set interest_amount = (v->>'interest_aed')::numeric, total_claim = amount_due + coalesce(admin_fee, 0) + (v->>'interest_aed')::numeric,
           due_date = (v->>'due_date')::date, due_date_30 = (v->>'due_date')::date + 23
     where id = x.id
       and (interest_amount is distinct from (v->>'interest_aed')::numeric
            or total_claim is distinct from amount_due + coalesce(admin_fee, 0) + (v->>'interest_aed')::numeric
            or due_date is distinct from (v->>'due_date')::date);
    if found then n := n + 1; end if;
  end loop;
  return n;
end $function$;


-- PROBE (no write): both bodies carry the notice rule; a transaction that cannot exist is never charged. Verdict row.
select case
  when pg_get_functiondef('public.fn_accountant_nonresponse_charge(uuid, date)'::regprocedure) !~ 'delivery.request:nonresponse_charge:' then 'PROBE FAILED: the due date does not read the notice'
  when pg_get_functiondef('public.fn_supplier_dues_accrue_interest(date)'::regprocedure) !~ 'due_date = \(v->>''due_date''\)::date' then 'PROBE FAILED: the dues row does not follow the notice'
  when (public.fn_accountant_nonresponse_charge('00000000-0000-0000-0000-000000000000'::uuid, null)->>'ok')::boolean then 'PROBE FAILED: a transaction that does not exist was charged'
  else 'PROBE OK' end as verdict;
