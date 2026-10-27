-- THE NON-RESPONSE CHARGE FOLLOWS THE VERSION THE SUPPLIER SIGNED, AND THE PRICING TABLE STATES THE CURRENT ONE
-- (19 Oct 2026, accountant). Assigned: accountant.
--
-- Settled by the coordinator from the founder ledger: row 1086 (the contractual 12% applies; 9% is only the statutory
-- default where no rate is agreed) and row 990 (charge the maximum that is lawful).
--
-- WHAT THE SIGNED TEXT SAYS (legal_documents 'supplier-agreement' v15, effective 2026-10-06, read 19 Oct 2026):
--   clause 33: (a) the exact amount refunded to the Customer; (b) the processor fee QuotesDone paid on it and could
--   not recover; (c) an administrative fee of AED 500; (d) simple interest at the clause 31 rate of 12% a year (or the
--   legal maximum if lower) from the due date, never compounded (Art. 88). Clause 31: 12% simple is the only rate;
--   an amount due under an earlier accepted version carries that version's rate.
--   Legacy (src/content/company_facts.json): AED 250 for v12 or earlier (or v13 accepted after the reveal); 9% for v13
--   or earlier (or v14 accepted after the reveal).
--
-- MEASURED BEFORE: public.pricing_config row 1 held supplier_nonresponse_admin_fee_aed = 250 and
-- supplier_nonresponse_interest_apr = 0.09 - the v12 / v13 figures, stored in the table every reader takes as the
-- current price list. fn_accountant_nonresponse_charge read the 250 from that row for its legacy branch (and as the
-- fallback for v13+), so the row could not be corrected without retro-charging legacy suppliers.
--
-- THE FIX: the legacy AED 250 becomes a literal in the routine (the 9% already was); the v13+ fallback becomes 500;
-- then pricing_config states the current v15 terms (AED 500, 0.12). The no-agreed-rate branch still reads the
-- config rate but is HARD-capped at 9% by its literal, so 0.12 there still charges 9%.
-- Prevented by: scripts/checks/the_nonresponse_charge_follows_the_signed_version.test.mjs

CREATE OR REPLACE FUNCTION public.fn_accountant_nonresponse_charge(p_transaction_id uuid, p_as_of date DEFAULT NULL::date)
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
  v_out numeric; v_from date; v_acc_int numeric; v_on_pr numeric; v_overpay numeric := 0; v_paid numeric := 0; v_pay record;
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
    v_fee := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'supplier_nonresponse_admin_fee_from_v13_aed'), 500);
    v_fee_basis := 'Supplier Agreement ' || v_ver || ' clause 33(b), accepted ' || v_acc || ' before the reveal';
  else
    -- 19 OCT 2026 (accountant): the AED 250 of clauses v6-v12 is a LITERAL, as the 9% below is. It used to be read from
    -- pricing_config, which made the pricing table state AED 250 as if it were the current fee (marketing's fact
    -- register found it against the FAQ's AED 500), and raising that row to the current figure would have charged a
    -- v12 signer the v13 fee. pricing_config now carries the CURRENT terms (v15: AED 500, 12%); a legacy supplier keeps
    -- the fee it signed, whatever that row says. Never retroactive.
    v_fee := 250;
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
  -- 30 SEP 2026 (accountant): A PAYMENT REDUCES THE PRINCIPAL FROM ITS OWN DATE. Before this, interest ran on the whole
  -- principal to the as-of date even after a part payment. Now the same day-by-day ledger as supplier_charge.ts
  -- computeCharge(): interest on each period's outstanding principal, from the due date (or the later payment date)
  -- to the next payment or the as-of date; a payment beyond the principal settles accrued interest. Simple: the
  -- accrued interest is never added to the principal. Payments: public.supplier_due_payments.
  v_out := v_base + v_proc + v_fee; v_from := v_due; v_acc_int := 0;
  if v_due_id is not null then
    for v_pay in select p.paid_on, p.amount_aed from public.supplier_due_payments p
                  where p.due_id = v_due_id and p.paid_on <= v_as_of and p.amount_aed > 0 order by p.paid_on, p.id loop
      if greatest(v_due, v_pay.paid_on) > v_from then
        v_acc_int := v_acc_int + v_out * v_apr * (greatest(v_due, v_pay.paid_on) - v_from) / 365.0;
        v_from    := greatest(v_due, v_pay.paid_on);
      end if;
      v_on_pr   := least(v_out, v_pay.amount_aed);
      v_out     := v_out - v_on_pr; v_overpay := v_overpay + v_pay.amount_aed - v_on_pr; v_paid := v_paid + v_pay.amount_aed;
    end loop;
  end if;
  if v_as_of > v_from then v_acc_int := v_acc_int + v_out * v_apr * (v_as_of - v_from) / 365.0; end if;
  v_int      := greatest(0, round(v_acc_int, 2) - v_overpay);

  return jsonb_build_object(
    'ok', true, 'transaction_id', t.id, 'supplier_id', t.supplier_id,
    'refunded_aed', v_base, 'processor_fee_aed', v_proc, 'charge_aed', v_base + v_proc, 'signed_version', v_signed, 'actually_refunded_aed', v_refunded, 'approved_aed', v_approved, 'refund_source', v_src,
    'admin_fee_aed', v_fee, 'admin_fee_basis', v_fee_basis,
    'interest_apr', v_apr, 'interest_apr_basis', v_apr_basis, 'interest_apr_configured', c.supplier_nonresponse_interest_apr, 'interest_apr_lawful_max', v_cap,
    'due_date', v_due, 'due_basis', v_due_basis, 'as_of', v_as_of, 'interest_days', v_days, 'interest_aed', v_int,
    'paid_aed', v_paid, 'unpaid_principal_aed', v_out,
    'total_aed', round(v_out + v_int, 2),
    'basis', 'base = the amount refunded to the customer, read from the refund record and capped at the amount the CEO approved; '
          || '+ from v14, the processor fee QuotesDone could not recover (transactions.stripe_fee_fils); + the administration fee of the agreement version the supplier had signed at the reveal; '
          || '+ simple interest on (base + processor fee + admin fee) at that version''s rate (v14: the agreed 12%; v9 to v13: the agreed 9%; no agreed rate: the policy rate, never above 9% a year; always simple, never compounded), from the due date (' || v_due_days || ' days after the notice was delivered, clause 33) to the as-of date, each payment (supplier_due_payments) reducing the principal from its own date. Nothing is typed.');
end $function$;
revoke execute on function public.fn_accountant_nonresponse_charge(uuid, date) from public, anon, authenticated;

-- The pricing table states the CURRENT signed terms (Supplier Agreement v15 clause 33(c) and clause 31).
update public.pricing_config set supplier_nonresponse_admin_fee_aed = 500, supplier_nonresponse_interest_apr = 0.12
 where supplier_nonresponse_admin_fee_aed is distinct from 500 or supplier_nonresponse_interest_apr is distinct from 0.12;
