-- THE ADMINISTRATIVE FEE IS THE ONE THE SUPPLIER SIGNED (23 Sep 2026, ceo).
--
-- Founder, 23 Sep 2026 (instruction B): set penalties and fines at the maximum the law safely allows. Supplier
-- Agreement v13 clause 33(b) raises the non-response administrative fee from AED 250 to the value in
-- src/content/company_facts.json (nonresponse_admin_fee_aed), as compensation agreed in advance under the Civil
-- Transactions Law, Federal Decree-Law 25/2025 Art. 340(1).
--
-- MEASURED before this file (full_schema.sql, 23 Sep 2026): fn_accountant_nonresponse_charge charged every supplier
-- pricing_config.supplier_nonresponse_admin_fee_aed (AED 250) whatever version it had accepted. Raising that column
-- would have charged a v12 supplier a fee it never signed: a retroactive term, unenforceable and unfair.
--
-- WHAT THIS CHANGES: fn_accountant_nonresponse_charge picks the fee by the version the supplier had accepted AT THE
-- REVEAL (leads.accepted_terms_version / accepted_terms_at against transactions.revealed_at). v13+ accepted at or
-- before the reveal -> decision_policy.supplier_nonresponse_admin_fee_from_v13_aed; otherwise the AED 250 in
-- pricing_config. The result names the basis ('admin_fee_basis'). Everything else in the body is the live definition
-- (last written by payments_are_the_accountant_and_the_seats_close_every_refund_together.sql) word for word.
-- WHAT THIS DOES NOT CHANGE: pricing_config (stays 250, the legacy fee); the interest rule; supplier_dues already raised.
-- The policy key is written by the_terms_of_23_september_2026_reach_every_place.sql, applied FIRST; until then the
-- coalesce falls back to AED 250, so applying this file alone never charges more than a supplier signed.
--
--   node scripts/apply_sql.mjs scripts/sql/the_administrative_fee_is_the_one_the_supplier_signed.sql --apply --ddl

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
  v_ver text; v_acc timestamptz; v_fee numeric; v_fee_basis text;
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
  v_due      := (v_settled at time zone 'Asia/Dubai')::date + v_due_days;
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
    'due_date', v_due, 'as_of', v_as_of, 'interest_days', v_days, 'interest_aed', v_int,
    'total_aed', round(v_base + v_fee + v_int, 2),
    'basis', 'base = the amount refunded to the customer, read from the refund record and capped at the amount the CEO approved; '
          || '+ the administration fee of the agreement version the supplier had signed at the reveal; + simple interest on (base + admin fee) at the lower of pricing_config''s APR and '
          || 'the lawful maximum, from the due date (' || v_due_days || ' days after the refund settled) to the as-of date. Nothing is typed.');
end $function$;

-- PROBE (no write): a supplier id that cannot exist has no version, so the rule gives the legacy fee branch; the
-- routine must still compile and name its basis. Verdict row, read by apply_sql.mjs.
select case
  when to_regprocedure('public.fn_accountant_nonresponse_charge(uuid, date)') is null then 'PROBE FAILED: routine missing'
  when (public.fn_accountant_nonresponse_charge('00000000-0000-0000-0000-000000000000'::uuid, null)->>'ok')::boolean then 'PROBE FAILED: a transaction that does not exist was charged'
  when pg_get_functiondef('public.fn_accountant_nonresponse_charge(uuid, date)'::regprocedure) !~ 'supplier_nonresponse_admin_fee_from_v13_aed' then 'PROBE FAILED: the version rule is not in the live body'
  else 'PROBE OK' end as verdict;
