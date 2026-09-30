-- NON-RESPONSE INTEREST: THE AGREED RATE, OR 9% WHERE NONE WAS AGREED (30 Sep 2026). Seat: accountant.
--
-- THE RULING (founder, ledger 1086, 30 Sep 2026; Federal Decree-Law 50/2022): the rate agreed in the supplier's signed
-- version applies; where that version agrees no rate, the default is capped at 9%; interest is always simple.
-- (Supersedes the closed PR #1161, which capped v14 signers at 9% too.)
--
-- WHAT EACH SIGNED VERSION AGREES (read from every committed text of supabase/functions/_shared/supplier_agreement.ts):
--   v14        clause 31 / 33(d): "twelve percent (12%) per annum ... simple ... never compounded"  -> 12%
--   v9 - v13   clause 31: "simple interest at nine percent (9%) per annum"                         ->  9%
--   v8 or earlier, no version, or accepted after the reveal: no interest clause                     -> no agreed rate
--
-- MEASURED ON PRODUCTION BEFORE THIS FILE (body of the_nonresponse_charge_is_the_maximum_uae_law_safely_allows.sql):
-- for every supplier below v14 the rate was least(pricing_config.supplier_nonresponse_interest_apr,
-- coalesce(decision_policy.supplier_charge_max_lawful_apr, the same pricing_config value)): no literal ceiling, so
-- raising either row (or deleting the cap row) raised a no-agreed-rate supplier above 9%. The v14 branch read its
-- policy row with no ceiling either. Live today: pricing_config 0.09, cap row 0.09, v14 row 0.12, so nobody is
-- overcharged at this moment; the ceiling simply did not exist in code.
--
-- THE FIX: one branch per agreement, each with a literal: v14 = least(v14 row, 0.12); v9-v13 = 0.09;
-- no agreed rate = least(pricing_config, cap row, 0.09). Interest stays simple: (base + processor fee + admin fee)
-- x rate x days / 365, recomputed from the refund record on every call (fn_supplier_dues_accrue_interest overwrites
-- interest_amount, it never adds interest to the base). supplier_charge.ts already refuses any rate but 0.09 / 0.12.
-- The body below is production's (pg_get_functiondef, 30 Sep 2026), changed only in the marked 30 SEP branch.
-- CREATE OR REPLACE keeps the ACL and the pinned search_path.
--
-- prevented by: scripts/checks/nonresponse_interest_is_the_agreed_rate_or_nine_percent_simple.test.mjs

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
  v_ver text; v_acc timestamptz; v_fee numeric; v_fee_basis text; v_signed int; v_proc numeric := 0; v_apr_basis text; v_due_id bigint; v_notice timestamptz; v_due_basis text;
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
  -- 30 SEP 2026: v_apr is set once, by the version branch below (the agreed rate, or 9% where none was agreed).
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
  -- 24 SEP 2026 (ceo): the version the supplier had SIGNED at the reveal, 0 when either date is unknown. One number, so
  -- every head below reads the same version (supplier_charge.ts termsAt() is the same rule for the documents).
  v_signed := case when v_acc is not null and t.revealed_at is not null and v_acc <= t.revealed_at
                   then coalesce(nullif(regexp_replace(coalesce(v_ver, ''), '\D', '', 'g'), '')::int, 0) else 0 end;
  if v_signed >= 13 then
    v_fee := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'supplier_nonresponse_admin_fee_from_v13_aed'), c.supplier_nonresponse_admin_fee_aed);
    v_fee_basis := 'Supplier Agreement ' || v_ver || ' clause 33(b), accepted ' || v_acc || ' before the reveal';
  else
    v_fee := c.supplier_nonresponse_admin_fee_aed;
    v_fee_basis := 'Supplier Agreement ' || coalesce(v_ver, '(no version recorded)') || ' clause 33(b) as signed before this reveal';
  end if;
  -- 24 SEP 2026 (ceo): SUPPLIER AGREEMENT v14 (founder instruction 990: the maximum UAE law safely allows).
  -- For a supplier who had accepted v14 or later before the reveal:
  --   33(b) the processor fee QuotesDone paid on the refunded reveal and could not recover. Stripe keeps its fee on a
  --         refund; transactions.stripe_fee_fils is that fee as Stripe reported it. An ACTUAL loss, charged at cost,
  --         so Civil Transactions Law 25/2025 Art. 340(2) ("the estimate was excessive") does not reach it.
  --   33(d) interest at the AGREED 12% (Commercial Transactions Law 50/2022 Arts. 72, 73, 84: 9% is only the ceiling
  --         where no rate is agreed), decision_policy.supplier_nonresponse_interest_apr_from_v14.
  -- Everyone else keeps the 9% and no processor-fee head (never retroactive). docs/legal/NONRESPONSE_MAX_V14.md.
  if v_signed >= 14 then
    v_proc      := round(coalesce(t.stripe_fee_fils, 0) / 100.0, 2);
    -- 30 SEP 2026 (accountant): the AGREED rate is what v14 writes, 12%. The policy row may lower it, never raise it.
    v_apr       := least(coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'supplier_nonresponse_interest_apr_from_v14'), 0.12), 0.12);
    v_apr_basis := 'the agreed rate of Supplier Agreement ' || v_ver || ' clauses 31 and 33(d)';
  elsif v_signed >= 9 then
    -- 30 SEP 2026 (accountant): Supplier Agreement v9 to v13 clause 31 AGREE nine percent (9%) per annum. Literal.
    v_apr       := 0.09;
    v_apr_basis := 'Supplier Agreement ' || v_ver || ' clause 31 as signed before this reveal: the agreed 9% a year, simple';
  else
    -- 30 SEP 2026 (accountant; founder ruling ledger 1086, Federal Decree-Law 50/2022): NO AGREED RATE (v8 or earlier,
    -- no version, or accepted after the reveal). The rate is the policy rate, HARD-capped at 9% by a literal so no
    -- pricing_config value and no decision_policy row can raise it.
    v_apr       := least(coalesce(c.supplier_nonresponse_interest_apr, 0.09), coalesce(v_cap, 0.09), 0.09);
    v_apr_basis := 'no interest rate agreed in the version signed before this reveal: the policy rate, never above 9% a year (Federal Decree-Law 50/2022)';
  end if;
  v_int      := round((v_base + v_proc + v_fee) * v_apr * v_days / 365.0, 2);

  return jsonb_build_object(
    'ok', true, 'transaction_id', t.id, 'supplier_id', t.supplier_id,
    'refunded_aed', v_base, 'processor_fee_aed', v_proc, 'charge_aed', v_base + v_proc, 'signed_version', v_signed, 'actually_refunded_aed', v_refunded, 'approved_aed', v_approved, 'refund_source', v_src,
    'admin_fee_aed', v_fee, 'admin_fee_basis', v_fee_basis,
    'interest_apr', v_apr, 'interest_apr_basis', v_apr_basis, 'interest_apr_configured', c.supplier_nonresponse_interest_apr, 'interest_apr_lawful_max', v_cap,
    'due_date', v_due, 'due_basis', v_due_basis, 'as_of', v_as_of, 'interest_days', v_days, 'interest_aed', v_int,
    'total_aed', round(v_base + v_proc + v_fee + v_int, 2),
    'basis', 'base = the amount refunded to the customer, read from the refund record and capped at the amount the CEO approved; '
          || '+ from v14, the processor fee QuotesDone could not recover (transactions.stripe_fee_fils); + the administration fee of the agreement version the supplier had signed at the reveal; '
          || '+ simple interest on (base + processor fee + admin fee) at that version''s rate (v14: the agreed 12%; v9 to v13: the agreed 9%; no agreed rate: the policy rate, never above 9% a year; always simple, never compounded), from the due date (' || v_due_days || ' days after the notice was delivered, clause 33) to the as-of date. Nothing is typed.');
end $function$;
