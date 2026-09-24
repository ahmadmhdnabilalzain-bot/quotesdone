-- THE NON-RESPONSE CHARGE IS THE MAXIMUM UAE LAW SAFELY ALLOWS (24 Sep 2026, ceo).
--
-- Founder, 24 Sep 2026 (founder_instruction 990): "Supplier non-response charges: collect the maximum possible for damages
-- that UAE law safely allows (admin fee, interest, recovery costs). Any change stays in sync everywhere." With 965 (23 Sep):
-- maximum legally safe penalties under UAE law, no lawyer. Reasoning and citations: docs/legal/NONRESPONSE_MAX_V14.md.
--
-- MEASURED: Commercial Transactions Law 50/2022 read on the official u.ae text (24 Sep 2026). Art. 72 caps only the
-- NO-agreement rate at 9%; Arts. 73 and 84 run delay interest at the AGREED rate; Art. 88 bars compounding. v13 charged
-- 9% as if it were the legal ceiling. Stripe keeps its fee when a payment is refunded, so every refund a silent supplier
-- causes costs QuotesDone that fee on top of the refund, and v13 recovered none of it.
--
-- WHAT THIS CHANGES (Supplier Agreement v14, clause 33; only for a supplier who accepted v14 BEFORE the reveal):
--   fn_accountant_nonresponse_charge   + 'processor_fee_aed' (transactions.stripe_fee_fils, at cost), 'charge_aed'
--                                        (= refunded + processor fee, the (a)+(b) sum the notice fixes), 'signed_version',
--                                        'interest_apr_basis'; the rate is decision_policy.supplier_nonresponse_interest_apr_from_v14 (12%).
--                                        v13 and earlier: unchanged to the fils (charge_aed = refunded_aed, 9%).
--   fn_accountant_raise_nonresponse_charge, fn_accountant_applies_incident_fix
--                                      supplier_dues.amount_due = charge_aed, so every reader that sums
--                                        amount_due + admin_fee + interest (supplier_pay, the chase, the escalation) is right.
--   fn_accountant_acts_on_handoff, fn_ceo_refund_checklist
--                                      verify amount_due against charge_aed (was refunded_aed), so a v14 charge is not
--                                        reported as "does not match the refund record".
--   fn_sales_engineer_acts_on_handoff  the supplier's charge notice names the processor fee and, for v14, the recovery fees;
--                                        the reveal notice stops quoting the v12 figures (AED 250, 9%) and points to clause 33.
--   fn_company_hard_rules, fn_company_self_knowledge_sync, fn_refund_amount_aed, fn_company_facts_sync
--                                      what the seats know: the rate is AGREED (v14), not 'the UAE statutory maximum', the
--                                        9% of v13 and earlier is named, the hard-coded '9% per annum' is read from policy.
-- WHAT IT DOES NOT CHANGE: fn_supplier_dues_accrue_interest (it reads the charge function and sums the columns, both now
-- right); the AED 500 / AED 250 administrative fee; pricing_config (0.09, the rate of every version before v14).
-- Every routine here is CREATE OR REPLACE of an existing routine: the ACLs, already closed to the browser roles, are kept.
--
--   node scripts/apply_sql.mjs scripts/sql/the_nonresponse_charge_is_the_maximum_uae_law_safely_allows.sql --apply --ddl

insert into public.decision_policy (key, value, description) values ('supplier_nonresponse_interest_apr_from_v14', to_jsonb(0.12::numeric),
  $qd$Simple annual interest on a clause 33 non-response charge for a supplier who accepted Supplier Agreement v14 or later before the reveal: the rate agreed in clauses 31 and 33(d) (Commercial Transactions Law 50/2022 Arts. 72, 73, 84). Earlier versions: pricing_config.supplier_nonresponse_interest_apr capped by supplier_charge_max_lawful_apr (9%). Source: src/content/company_facts.json late_interest_pct_pa.$qd$)
on conflict (key) do update set value = excluded.value, description = excluded.description;

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
    v_apr       := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'supplier_nonresponse_interest_apr_from_v14'), v_apr);
    v_apr_basis := 'the agreed rate of Supplier Agreement ' || v_ver || ' clauses 31 and 33(d)';
  else
    v_apr_basis := 'the lower of pricing_config''s APR and the lawful maximum, clause 31 as signed before this reveal';
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
          || '+ simple interest on (base + processor fee + admin fee) at that version''s rate (v14: the agreed 12%; earlier: the lower of pricing_config''s APR and the lawful maximum), from the due date (' || v_due_days || ' days after the notice was delivered, clause 33) to the as-of date. Nothing is typed.');
end $function$;

create or replace function public.fn_accountant_raise_nonresponse_charge(p_transaction_id uuid, p_notify boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb; t public.transactions; v_due bigint; v_new boolean := false;
begin
  if public.fn_refunds_paused() and coalesce(current_setting('app.qd_incident_fix', true), '') <> 'on' then
    return jsonb_build_object('ok', false, 'held', true,
      'reason', 'refunds and supplier charges are paused by the CEO''s circuit breaker; fn_ceo_refund_loop_sweep raises this charge when it lifts');
  end if;
  v := public.fn_accountant_nonresponse_charge(p_transaction_id, null);
  if not coalesce((v->>'ok')::boolean, false) then return v; end if;
  select * into t from public.transactions where id = p_transaction_id;

  select id into v_due from public.supplier_dues
   where transaction_id = p_transaction_id and coalesce(status, '') <> 'cancelled' order by id limit 1;
  if v_due is null then
    insert into public.supplier_dues (transaction_id, supplier_id, quote_id, quote_amount, commission_pct,
                                      amount_due, admin_fee, interest_amount, total_claim, currency,
                                      reveal_date, due_date, due_date_30, status)
    values (t.id, t.supplier_id, t.quote_id, t.quote_amount, null,
            (v->>'charge_aed')::numeric, (v->>'admin_fee_aed')::numeric, (v->>'interest_aed')::numeric, (v->>'total_aed')::numeric, 'AED',
            (t.revealed_at at time zone 'Asia/Dubai')::date, (v->>'due_date')::date, (v->>'due_date')::date + 23, 'due')
    returning id into v_due;
    update public.leads
       set matching_blocked = true,
           matching_block_reason = 'Unsettled non-response charge (the customer was refunded because the supplier did not respond)',
           rv_nonresponse_refunds = coalesce(rv_nonresponse_refunds, 0) + 1
     where id = t.supplier_id;
    v_new := true;
  end if;

  if p_notify then
    perform public.fn_seat_handoff('accountant', 'sales_engineer', 'nonresponse.charge_raised', 'supplier_dues', v_due::text,
      v || jsonb_build_object('due_id', v_due, 'transaction_id', t.id, 'supplier_id', t.supplier_id,
                              'inquiry_id', t.inquiry_id, 'quote_id', t.quote_id));
  end if;
  return v || jsonb_build_object('due_id', v_due, 'created', v_new);
end $function$;

create or replace function public.fn_accountant_applies_incident_fix(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d jsonb; v_fix text; v_tx uuid; v_old bigint; v_orig bigint; v jsonb; v_j bigint; v_amt numeric; v_res jsonb; v_du public.supplier_dues;
        v_why text;
begin
  select detail into d from public.agent_actions where id = p_id;
  v_fix := d->>'fix'; v_tx := (d->>'transaction_id')::uuid;
  if v_fix in ('refund_difference', 'retry_refund', 'cancel_duplicate') then
    return jsonb_build_object('waiting', 'stripe: the accountant runtime executes ' || v_fix || ' (accountant action execute_refunds)');
  end if;

  perform set_config('app.qd_incident_fix', 'on', true);
  if v_fix = 'book_over_refund_loss' then
    -- test money never reaches the books: a fixture or orphaned transaction's loss is not the company's
    v_why := public.fn_gl_fixture_or_orphan(v_tx, null, null);
    if v_why is not null then
      perform set_config('app.qd_incident_fix', '', true);
      return jsonb_build_object('refused', 'not booked: ' || v_why);
    end if;
    v_amt := round((d->>'amount_aed')::numeric, 2);
    select g.id into v_j from public.gl_journal g where g.source = 'refund_over_loss' and g.source_ref = v_tx || ':' || (d->>'incident_id');
    if v_j is null and v_amt > 0 then
      v_j := public.fn_gl_entry(current_date,
        'Over-refund on reveal ' || left(v_tx::text, 8) || ' booked as company loss (incident #' || (d->>'incident_id') || '); the supplier charge stays at the approved amount',
        'refund_over_loss', v_tx || ':' || (d->>'incident_id'),
        jsonb_build_array(jsonb_build_object('account', '6900', 'debit', v_amt), jsonb_build_object('account', '1050', 'credit', v_amt)), 'accountant');
    end if;
    v_res := jsonb_build_object('journal_id', v_j, 'amount_aed', v_amt);
  elsif v_fix = 'reissue_charge' then
    -- supplier_dues holds ONE row per transaction (supplier_dues_transaction_id_key), so the charge is
    -- reissued IN PLACE: the figures become the routine's, and the old ones are kept in the evidence.
    select * into v_du from public.supplier_dues where transaction_id = v_tx order by id limit 1;
    v_old := v_du.id;
    select (a.evidence->>'notification_id')::bigint into v_orig from public.agent_actions a
     where a.kind = 'handoff' and a.agent = 'customer_support' and a.target_id = 'delivery.request:nonresponse_charge:' || v_old
     order by a.id desc limit 1;
    v := public.fn_accountant_nonresponse_charge(v_tx, null);
    if not coalesce((v->>'ok')::boolean, false) then
      perform set_config('app.qd_incident_fix', '', true);
      return jsonb_build_object('waiting', 'the charge cannot be recomputed: ' || coalesce(v->>'reason', '?'));
    end if;
    update public.supplier_dues
       set amount_due = (v->>'charge_aed')::numeric, admin_fee = (v->>'admin_fee_aed')::numeric,
           interest_amount = (v->>'interest_aed')::numeric, total_claim = (v->>'total_aed')::numeric,
           due_date = (v->>'due_date')::date, due_date_30 = (v->>'due_date')::date + 23,
           status = case when status = 'cancelled' then 'due' else status end
     where id = v_old;
    v := v || jsonb_build_object('due_id', v_old, 'transaction_id', v_tx, 'supplier_id', v_du.supplier_id,
                                 'inquiry_id', (select inquiry_id from public.transactions where id = v_tx),
                                 'quote_id', (select quote_id from public.transactions where id = v_tx));
    if coalesce((d->>'sent')::boolean, false) then
      -- Already in the supplier's hands: a correction that supersedes it, to whoever got the original.
      perform public.fn_seat_handoff('accountant', 'sales_engineer', 'charge.corrected', 'supplier_dues', v_old::text,
        v || jsonb_build_object('original_notification_id', v_orig));
    else
      -- Not sent yet: withdraw it from the outbox and send the right one instead.
      update public.notifications set status = 'cancelled', last_error = 'withdrawn before sending: the charge was reissued with the correct figures'
       where id = v_orig and status in ('queued', 'pending', 'held');
      update public.agent_actions set status = 'failed', detail = detail || jsonb_build_object('superseded_by_incident', d->>'incident_id')
       where kind = 'handoff' and status = 'done'
         and target_id in ('nonresponse.charge_raised:' || v_old, 'delivery.request:nonresponse_charge:' || v_old);
      perform public.fn_seat_handoff('accountant', 'sales_engineer', 'nonresponse.charge_raised', 'supplier_dues', v_old::text, v);
    end if;
    v_res := jsonb_build_object('reissued_due', v_old,
      'was', jsonb_build_object('amount_due', v_du.amount_due, 'admin_fee', v_du.admin_fee, 'due_date', v_du.due_date),
      'now', v, 'correction_sent_to_original_recipients', coalesce((d->>'sent')::boolean, false));
  elsif v_fix = 'raise_charge' then
    v_res := public.fn_accountant_raise_nonresponse_charge(v_tx, true);
  else
    v_res := jsonb_build_object('waiting', 'no handler for fix ' || coalesce(v_fix, '?'));
  end if;
  perform set_config('app.qd_incident_fix', '', true);
  return v_res;
end $function$;

create or replace function public.fn_accountant_acts_on_handoff(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  a public.agent_actions; d jsonb; t text; r public.refunds; tx public.transactions; du public.supplier_dues;
  v_expected bigint; v_ok boolean; v_checks jsonb; v jsonb; v_lines text[] := '{}'; v_match boolean; x record;
begin
  select * into a from public.agent_actions where id = p_id;
  d := a.detail; t := d->>'type';

  if t = 'refund.requested' then
    select * into r from public.refunds where id = (d->>'subject_id')::bigint;
    select * into tx from public.transactions where id = r.transaction_id;
    v_expected := round(coalesce(tx.total_charged, tx.reveal_fee, 0) * 100)::bigint;
    v_checks := jsonb_build_object(
      'transaction_found', tx.id is not null,
      'fee_settled', coalesce(tx.fee_status, '') = 'paid',
      'stripe_reference_matches', coalesce(btrim(tx.payment_ref), '') <> '' and btrim(tx.payment_ref) = btrim(coalesce(r.stripe_payment_intent, '')),
      'amount_is_total_charged', r.amount_fils = v_expected,
      'total_charged_recorded', tx.total_charged is not null,
      'expected_fils', v_expected, 'requested_fils', r.amount_fils);
    v_ok := (v_checks->>'transaction_found')::boolean and (v_checks->>'fee_settled')::boolean
            and (v_checks->>'stripe_reference_matches')::boolean and (v_checks->>'amount_is_total_charged')::boolean;
    perform public.fn_seat_handoff('accountant', 'sales_engineer', 'refund.request_checked', 'refunds', r.id::text,
      jsonb_build_object('refund_id', r.id, 'transaction_id', r.transaction_id, 'customer_id', r.customer_id,
                         'inquiry_id', r.inquiry_id, 'quote_id', r.quote_id, 'money_ok', v_ok,
                         'amount_aed', round(coalesce(r.amount_fils, 0) / 100.0, 2)));
    return v_checks || jsonb_build_object('money_ok', v_ok);

  elsif t = 'billing.question' then
    if d->>'party' = 'supplier' then
      perform public.fn_supplier_dues_accrue_interest(null);
      for x in select * from public.supplier_dues
                where supplier_id = (d->>'supplier_id')::bigint and coalesce(status, '') not in ('cancelled')
                order by id loop
        v_lines := v_lines || ('Charge #' || x.id || ' (reveal of ' || coalesce(x.reveal_date::text, '?') || '): AED '
          || coalesce(x.amount_due, 0) || ' non-response charge (the refund to the customer and, from v14, the processor fee not recovered) + AED ' || coalesce(x.admin_fee, 0) || ' administration + AED '
          || coalesce(x.interest_amount, 0) || ' interest = AED ' || coalesce(x.total_claim, coalesce(x.amount_due, 0) + coalesce(x.admin_fee, 0) + coalesce(x.interest_amount, 0))
          || ', due ' || coalesce(x.due_date::text, '?') || ', ' || case when x.paid_at is not null then 'paid' else coalesce(x.status, 'open') end || '.');
      end loop;
      v := public.fn_supplier_registration_state((d->>'supplier_id')::bigint);
      if v is not null then
        v_lines := v_lines || ('Registration: ' || coalesce(v->>'status', 'unknown') || coalesce(', fee due AED ' || nullif(v->>'fee_due', '0'), '') || '.');
      end if;
    else
      for x in select t2.*, i.summary from public.transactions t2 left join public.inquiries i on i.id = t2.inquiry_id
                where t2.customer_id = (d->>'customer_id')::uuid
                  and ((d->>'transaction_id') is null or t2.id = (d->>'transaction_id')::uuid)
                  and t2.revealed_at is not null
                order by t2.revealed_at desc limit 10 loop
        v_lines := v_lines || ('Reveal on ' || to_char(x.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY')
          || coalesce(' for "' || left(x.summary, 60) || '"', '') || ': you paid AED ' || coalesce(x.total_charged, x.reveal_fee)
          || case when x.total_charged is not null and x.total_charged > coalesce(x.reveal_fee, 0)
                  then ' (reveal fee AED ' || x.reveal_fee || ' + card processing AED ' || (x.total_charged - x.reveal_fee) || ')' else '' end
          || '. Invoice ' || coalesce(x.stripe_invoice_number, 'not yet issued')
          || ' (the invoice and the receipt, as QuotesDone PDFs in English and Arabic, are on the revealed quote in the customer portal)'
          || '. Refund: ' || case when x.refund_status in ('refunded', 'succeeded') then 'AED ' || coalesce(x.refund_amount_aed::text, '?') || ' returned'
                                  when x.refund_status = 'requested' then 'requested and under review'
                                  when x.refund_status = 'rejected' then 'declined'
                                  else 'none requested' end || '.');
      end loop;
    end if;
    perform public.fn_seat_handoff('accountant', 'sales_engineer', 'billing.answer', 'agent_actions', a.id::text,
      jsonb_build_object('party', d->>'party', 'customer_id', d->>'customer_id', 'supplier_id', d->>'supplier_id',
                         'question', d->>'question', 'facts', to_jsonb(v_lines)));
    return jsonb_build_object('facts', to_jsonb(v_lines));

  elsif t = 'charge.disputed' then
    select * into du from public.supplier_dues where id = coalesce((d->>'due_id')::bigint, (d->>'subject_id')::bigint);
    v := public.fn_accountant_nonresponse_charge(du.transaction_id, null);
    v_match := coalesce((v->>'ok')::boolean, false)
               and du.amount_due = (v->>'charge_aed')::numeric
               and du.admin_fee = (v->>'admin_fee_aed')::numeric
               and du.due_date = (v->>'due_date')::date;
    v_lines := array[
      'Charged: AED ' || coalesce(du.amount_due, 0) || ' + AED ' || coalesce(du.admin_fee, 0) || ' administration, due ' || coalesce(du.due_date::text, '?') || '.',
      'Payment record: ' || coalesce('AED ' || (v->>'refunded_aed') || ' refunded to the customer (' || (v->>'refund_source') || ')'
                                     || case when coalesce((v->>'processor_fee_aed')::numeric, 0) > 0 then ' + AED ' || (v->>'processor_fee_aed') || ' processor fee not recovered' else '' end || ' + AED '
                                     || (v->>'admin_fee_aed') || ' administration, due ' || (v->>'due_date') || '.', coalesce(v->>'reason', 'unreadable')),
      'Interest to date: AED ' || coalesce(v->>'interest_aed', '0') || ' at ' || coalesce(round((v->>'interest_apr')::numeric * 100, 2)::text, '?') || '% a year over '
        || coalesce(v->>'interest_days', '0') || ' day(s).'];
    if not v_match then
      insert into public.ceo_task (title, detail)
      values (left('Supplier disputed charge #' || du.id || ' and it does not match the refund record', 200),
              'The accountant recomputed charge #' || du.id || ' from the refund record and the figures differ. ' || array_to_string(v_lines, ' '));
    end if;
    perform public.fn_seat_handoff('accountant', 'sales_engineer', 'charge.dispute_answer', 'supplier_dues', du.id || ':' || a.id,
      jsonb_build_object('supplier_id', du.supplier_id, 'due_id', du.id, 'figures_match', v_match, 'lines', to_jsonb(v_lines), 'reason', d->>'reason'));
    return jsonb_build_object('figures_match', v_match, 'recomputed', v);

  elsif t = 'refund.remediate' then
    return public.fn_accountant_remediates(p_id);

  elsif t = 'incident.fix' then
    return public.fn_accountant_applies_incident_fix(p_id);
  end if;
  raise exception 'accountant has no handler for %', t;
end $function$;

create or replace function public.fn_ceo_refund_checklist(p_transaction_id uuid, p_phase text, p_record boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t public.transactions; r public.refunds; rs public.refunds; ap public.ceo_approval; du public.supplier_dues;
  e_chase public.refund_ladder_evidence; e_final public.refund_ladder_evidence;
  v_items jsonb := '[]'::jsonb; v_failed jsonb; v_ok boolean; v_cust text; v_total numeric; v_reason text; v_unresp boolean;
  v_complaint timestamptz; v_in_time boolean; v_cc boolean; v_attached boolean; v_proofs int; v_live boolean; v_proof_ev jsonb;
  v_prior boolean; v_hired boolean; v_rated boolean; v_offp boolean; v_excl text[] := '{}'; v_exp bigint;
  v_succ int; v_succ_fils bigint; v_extra int; v_actual numeric; v_approved numeric; v_loss numeric; v_charge jsonb; v_sent boolean;
  v_told boolean; v_sup_told boolean; v_kind text; v_rid bigint;
  v_offp_text text; v_offp_key text; v_offp_choice text; v_offp_held bigint;   -- item 5, reasoned (23 Sep 2026)
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found then
    return jsonb_build_object('ok', false, 'phase', p_phase, 'transaction_id', p_transaction_id,
      'failed', jsonb_build_array(jsonb_build_object('item', 'transaction_exists', 'passed', false, 'reason', 'no such transaction', 'remediable', false)));
  end if;
  select * into r from public.refunds where transaction_id = t.id and status not in ('rejected', 'cancelled', 'failed')
     and lower(coalesce(requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe') order by id desc limit 1;
  select lower(email) into v_cust from public.customers where id = t.customer_id;
  v_total := coalesce(t.total_charged, t.reveal_fee);
  v_reason := coalesce(r.reason_code, t.refund_reason, 'supplier_unresponsive');
  v_unresp := v_reason = 'supplier_unresponsive';
  select * into e_chase from public.refund_ladder_evidence e where e.transaction_id = t.id and e.step = 'chase' order by e.id desc limit 1;
  select * into e_final from public.refund_ladder_evidence e where e.transaction_id = t.id and e.step = 'final_call' order by e.id desc limit 1;

  if p_phase = 'approve' then
    v_rid := r.id;
    -- 1. THE CUSTOMER'S COMPLAINT, ON RECORD OR NOT -- NEVER A CONDITION (14 Sep 2026). This item was
    -- complaint_within_7_days_with_proof and refused every refund where the customer did not complain
    -- within 7 days with proof. Terms v7 §5 and Refund Policy v1.5 §3/§5 say the opposite: "you do not
    -- need to do anything for the clock to start", a complaint may come "at any time", and proof "is
    -- never a condition of the refund". So it now records the evidence and always passes; the conditions
    -- the terms DO set are items 2 to 6.
    v_complaint := least(t.customer_notified_at,
                         (select min(x.requested_at) from public.refunds x where x.transaction_id = t.id and lower(coalesce(x.requested_by, '')) = 'customer'));
    v_cc := exists (select 1 from public.inbound_messages im
                     where v_cust is not null and lower(im.from_email) = v_cust and im.created_at > t.revealed_at
                       and (im.to_email ilike 'supplier@%' or im.raw::text ilike '%supplier@mail.quotesdone.com%'));
    v_attached := exists (select 1 from public.refund_ladder_evidence e where e.transaction_id = t.id and e.step = 'customer_proof');
    v_items := v_items || jsonb_build_object('item', 'customer_complaint_on_record',
      'passed', true,
      'evidence', jsonb_build_object('revealed_at', t.revealed_at, 'complaint_at', v_complaint,
        'customer_emailed_supplier_with_supplier_at_in_copy', v_cc, 'formal_notice_through_portal_at', t.customer_notified_at,
        'proof_attached_by_sales_engineer', v_attached,
        'basis', 'Terms v7 section 5, Refund Policy v1.5 sections 3 and 5: no complaint or proof is required; the ladder runs from payment'),
      'reason', null, 'remedy', 'none needed', 'owner', 'sales_engineer', 'remedy_key', 'customer_proof', 'remediable', true, 'kind', 'information');

    -- 2 and 3. The day-3 chase and the day-5 final call, as support reported them.
    v_items := v_items || jsonb_build_object('item', 'day3_chase_happened',
      'passed', e_chase.id is not null and e_chase.delivered,
      'evidence', case when e_chase.id is null then '{}'::jsonb
                       else jsonb_build_object('ladder_evidence_id', e_chase.id, 'result', e_chase.result, 'delivered', e_chase.delivered, 'delivery', e_chase.evidence) end,
      'reason', case when e_chase.id is null then 'support has returned no result for a day-3 chase' else 'the day-3 chase was not delivered' end,
      'remedy', 'the sales engineer has support deliver the chase again and watch every channel for a reply',
      'owner', 'sales_engineer', 'remedy_key', 'chase', 'remediable', true, 'kind', 'process');
    v_items := v_items || jsonb_build_object('item', 'day5_final_call_happened',
      'passed', e_final.id is not null and e_final.delivered,
      'evidence', case when e_final.id is null then '{}'::jsonb
                       else jsonb_build_object('ladder_evidence_id', e_final.id, 'result', e_final.result, 'delivered', e_final.delivered, 'delivery', e_final.evidence) end,
      'reason', case when e_final.id is null then 'support has returned no result for the day-5 final call' else 'the day-5 final call was not delivered' end,
      'remedy', 'the sales engineer has support deliver the final call again and watch every channel for a reply',
      'owner', 'sales_engineer', 'remedy_key', 'final_call', 'remediable', true, 'kind', 'process');

    -- 4. The supplier did not respond to either party, on any channel.
    select count(*), (array_agg(e.evidence order by e.id desc))[1] into v_proofs, v_proof_ev
      from public.refund_ladder_evidence e where e.transaction_id = t.id and e.result = 'proof_of_response';
    v_live := coalesce((public.fn_refund_state(t.id)->>'supplier_responded')::boolean, false)
              or exists (select 1 from public.supplier_response_watch w where w.transaction_id = t.id and w.first_response_at is not null);
    v_items := v_items || jsonb_build_object('item', 'supplier_never_responded',
      'passed', v_proofs = 0 and not v_live
                and coalesce(e_chase.result, '') = 'no_response_confirmation' and coalesce(e_chase.delivered, false)
                and coalesce(e_final.result, '') = 'no_response_confirmation' and coalesce(e_final.delivered, false),
      'evidence', jsonb_build_object('proofs_of_response', v_proofs, 'latest_proof', v_proof_ev, 'responded_by_live_record', v_live,
                                     'chase_result', e_chase.result, 'final_call_result', e_final.result),
      'reason', case when v_proofs > 0 or v_live then 'the supplier responded' || coalesce(': ' || (v_proof_ev->'reply')::text, '')
                     else 'silence is not confirmed on both steps: a result is missing, or the delivery behind it failed' end,
      'remedy', 'the sales engineer has support make the final call again and return proof or a confirmed no-response',
      'owner', 'sales_engineer', 'remedy_key', 'final_call', 'remediable', v_proofs = 0 and not v_live, 'kind', 'process');

    -- 5. None of the exclusions in the signed terms applies.
    v_prior := exists (select 1 from public.transactions x where x.customer_id = t.customer_id and x.supplier_id = t.supplier_id
                         and x.id <> t.id and x.revealed_at < t.revealed_at);
    v_hired := exists (select 1 from public.inquiries i where i.id = t.inquiry_id and i.status in ('completed', 'closed') and i.hired_supplier_id = t.supplier_id);
    v_rated := exists (select 1 from public.reviews v where v.transaction_id = t.id);
    -- OFF-PLATFORM ENGAGEMENT IS REASONED FROM WHAT WAS WRITTEN, NEVER SPOTTED (23 Sep 2026,
    -- founder_instruction 886-903). A pattern on the note decided this exclusion, and an exclusion DECLINES
    -- the refund: "they did not use the platform" matched nothing, "not off-platform" matched. The notes are
    -- now read by the CEO seat's reasoning (ceo.refund_off_platform) and the answer is read back by its key.
    -- The platform's own default note is our text, not the customer's, so it asks nothing. Until the
    -- reasoning answers, v_offp stays null: no exclusion is assumed, and item 7 below keeps the refund
    -- waiting (fn_ceo_refund_review neither approves nor declines it, and pages nobody).
    v_offp_text := nullif(concat_ws(E'\n',
        case when btrim(coalesce(r.reason_note, '')) not in ('', 'The customer reported that the revealed supplier has not responded.')
             then 'Refund note: ' || btrim(r.reason_note) end,
        (select string_agg('Support note on the supplier''s response: ' || btrim(w.close_reason), E'\n' order by w.id)
           from public.supplier_response_watch w where w.transaction_id = t.id and btrim(coalesce(w.close_reason, '')) <> '')), '');
    if v_offp_text is null then
      v_offp := false;
    else
      v_offp_key := 'refund_offp:' || t.id || ':' || md5(v_offp_text);
      v_offp_choice := public.fn_reason_route_answer(v_offp_key);
      if v_offp_choice is null then
        v_offp := null;
        v_offp_held := public.fn_reason_route_ask('ceo', 'ceo.refund_off_platform', v_offp_text,
          jsonb_build_array(
            jsonb_build_object('id', 'engaged_off_platform', 'meaning', 'the note records that the customer dealt with or hired the supplier outside QuotesDone'),
            jsonb_build_object('id', 'not_off_platform', 'meaning', 'the note does not record any dealing with the supplier outside QuotesDone')),
          jsonb_build_object('transaction_id', t.id, 'refund_id', r.id), v_offp_key);
      else
        v_offp := v_offp_choice = 'engaged_off_platform';
      end if;
    end if;
    if not v_unresp then v_excl := v_excl || ('the reason is ' || v_reason || ', not supplier non-response (price dissatisfaction and a change of mind are not refundable)'); end if;
    if v_prior then v_excl := v_excl || 'the customer revealed this same supplier before'::text; end if;
    if v_hired then v_excl := v_excl || 'the customer completed the job with this supplier'::text; end if;
    if v_rated then v_excl := v_excl || 'the customer already rated this supplier'::text; end if;
    if coalesce(v_offp, false) then v_excl := v_excl || 'the customer engaged the supplier off the platform (reasoned by the CEO seat)'::text; end if;
    v_items := v_items || jsonb_build_object('item', 'no_refund_exclusion_applies',
      'passed', cardinality(v_excl) = 0,
      'evidence', jsonb_build_object('reason_code', v_reason, 'same_supplier_revealed_before', v_prior, 'job_completed_with_supplier', v_hired,
                                     'supplier_rated', v_rated, 'off_platform_engagement_recorded', v_offp,
                                     'supplier_responded', 'checked by supplier_never_responded'),
      'reason', array_to_string(v_excl, '; '), 'remedy', 'none: an exclusion in the signed terms means the refund is declined',
      'owner', 'sales_engineer', 'remedy_key', 'decline', 'remediable', false, 'kind', 'process');
    -- 7. The notes on record have been READ (reasoned), so item 5 is a finding and not an assumption.
    if v_offp is null then
      v_items := v_items || jsonb_build_object('item', 'off_platform_engagement_reasoned',
        'passed', false,
        'evidence', jsonb_build_object('held_question_id', v_offp_held, 'dedupe_key', v_offp_key),
        'reason', 'the CEO seat is still reasoning whether the notes on record say the customer dealt with the supplier off the platform',
        'remedy', 'none by hand: the answer arrives through the reasoning queue and the review re-runs itself',
        'owner', 'ceo', 'remedy_key', 'reasoning', 'remediable', true, 'kind', 'needs_reasoning');
    end if;

    -- 6. The amount is exactly what the customer paid.
    v_exp := round(coalesce(v_total, 0) * 100)::bigint;
    v_items := v_items || jsonb_build_object('item', 'amount_equals_total_charged',
      'passed', r.id is not null and r.amount_fils = v_exp and v_exp > 0,
      'evidence', jsonb_build_object('refund_id', r.id, 'refund_fils', r.amount_fils, 'total_charged_fils', v_exp,
                                     'total_charged_recorded', t.total_charged is not null, 'stripe_reference', t.payment_ref),
      'reason', case when r.id is null then 'there is no open refund request on this payment' else 'the refund amount is not what the customer paid' end,
      'remedy', 'the accountant sets the refund to the payment''s total_charged',
      'owner', 'accountant', 'remedy_key', 'amount', 'remediable', r.id is not null, 'kind', 'money');

  elsif p_phase = 'verify' then
    select count(*), coalesce(sum(x.amount_fils), 0) into v_succ, v_succ_fils
      from public.refunds x
     where x.status = 'succeeded' and (x.transaction_id = t.id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref));
    -- A top-up the playbook issued is not a duplicate: its Stripe id is on the incident fix.
    select count(*) into v_extra
      from public.refunds x
     where x.status = 'succeeded' and (x.transaction_id = t.id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref))
       and not exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'incident.fix'
                        and a.evidence->>'stripe_refund_id' = x.stripe_refund_id);
    -- The platform refund the CEO approved, whatever state it reached. An external row Stripe reported
    -- (a top-up, a dashboard refund) is never it.
    select * into rs from public.refunds x where x.transaction_id = t.id
       and lower(coalesce(x.requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe') order by x.id desc limit 1;
    v_rid := rs.id;
    select * into ap from public.ceo_approval a where a.decision_id = rs.refund_decision_id;
    v_actual := case when v_succ > 0 then round(v_succ_fils / 100.0, 2)
                     when t.refund_status in ('refunded', 'succeeded') then t.refund_amount_aed end;
    v_approved := coalesce(ap.amount_aed, v_total);
    v_loss := coalesce((select sum(l.debit) from public.gl_journal g join public.gl_journal_lines l on l.journal_id = g.id
                         where g.source = 'refund_over_loss' and g.source_ref like t.id::text || ':%' and l.account_code = '6900'), 0);

    v_items := v_items || jsonb_build_object('item', 'ceo_approved_this_refund',
      'passed', ap.decision_id is not null and ap.decision = 'approved' and ap.subject_id = v_rid::text and ap.superseded_by is null,
      'evidence', jsonb_build_object('decision_id', ap.decision_id, 'decision', ap.decision, 'subject_id', ap.subject_id, 'refund_id', v_rid),
      'reason', 'money moved without a CEO approval naming this refund', 'kind', 'moved_without_ceo_approval', 'remediable', false);

    v_items := v_items || jsonb_build_object('item', 'stripe_refund_succeeded',
      'passed', (v_succ > 0 and exists (select 1 from public.refunds x
                                         where (x.transaction_id = t.id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref))
                                           and x.status = 'succeeded' and x.stripe_refund_id is not null))
                or (v_succ = 0 and t.refund_stripe_id is not null and t.refund_status in ('refunded', 'succeeded')),
      'evidence', jsonb_build_object('refund_status', rs.status, 'stripe_refund_id', coalesce(rs.stripe_refund_id, t.refund_stripe_id), 'failure_reason', rs.failure_reason),
      'reason', 'Stripe has not settled the refund (' || coalesce(rs.status, t.refund_status, 'unknown') || ')', 'kind', 'stripe_failed_or_pending', 'remediable', true);

    v_kind := case when coalesce(v_actual, 0) = 0 then 'stripe_failed_or_pending'
                   when v_approved is distinct from v_total then 'approved_amount_is_not_total_charged'
                   when v_actual < v_approved then 'under_refund'
                   when v_actual > v_approved then 'over_refund' end;
    v_items := v_items || jsonb_build_object('item', 'money_moved_as_approved',
      'passed', v_actual is not null and v_approved = v_total
                and (v_actual = v_approved or (v_actual > v_approved and v_loss >= v_actual - v_approved)),
      'evidence', jsonb_build_object('approved_aed', v_approved, 'actual_aed', v_actual, 'total_charged_aed', v_total,
                                     'difference_aed', v_actual - v_approved, 'over_refund_loss_booked_aed', v_loss, 'settled_refunds', v_succ),
      'reason', 'approved AED ' || coalesce(v_approved::text, '?') || ', refunded AED ' || coalesce(v_actual::text, 'nothing') || ', total charged AED ' || coalesce(v_total::text, '?'),
      'kind', v_kind, 'remediable', true);

    v_items := v_items || jsonb_build_object('item', 'no_duplicate_refund',
      'passed', v_extra <= 1 or v_loss >= coalesce(v_actual - v_approved, 0),
      'evidence', jsonb_build_object('settled_refunds_not_issued_by_a_fix', v_extra),
      'reason', v_extra || ' refunds settled on one payment', 'kind', 'duplicate_refund', 'remediable', true);

    -- What follows the money (the supplier's charge, the two messages) is checked only once money
    -- actually moved; a refund Stripe has not settled is the retry's business, not a missed message.
    if coalesce(v_actual, 0) > 0 and v_unresp then
      select * into du from public.supplier_dues where transaction_id = t.id and coalesce(status, '') <> 'cancelled' order by id limit 1;
      v_charge := public.fn_accountant_nonresponse_charge(t.id, null);
      v_sent := du.id is not null and exists (
        select 1 from public.agent_actions a join public.notifications n on n.id = (a.evidence->>'notification_id')::bigint
         where a.kind = 'handoff' and a.agent = 'customer_support' and a.target_id = 'delivery.request:nonresponse_charge:' || du.id
           and (n.status = 'sent' or n.sent_at is not null));
      v_items := v_items || jsonb_build_object('item', 'supplier_charge_raised_correctly',
        'passed', du.id is not null and coalesce((v_charge->>'ok')::boolean, false)
                  and du.amount_due = (v_charge->>'charge_aed')::numeric and du.admin_fee = (v_charge->>'admin_fee_aed')::numeric
                  and du.due_date = (v_charge->>'due_date')::date,
        'evidence', jsonb_build_object('due_id', du.id, 'charged', jsonb_build_object('amount_due', du.amount_due, 'admin_fee', du.admin_fee, 'due_date', du.due_date),
                                       'expected', v_charge, 'charge_message_sent', v_sent),
        'reason', case when du.id is null then 'no supplier charge was raised' else 'the supplier charge does not match the refund record' end,
        'kind', case when du.id is null then 'charge_missing' when v_sent then 'wrong_charge_sent' else 'wrong_charge_unsent' end, 'remediable', true);
    end if;

    if coalesce(v_actual, 0) > 0 then
    v_told := exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'sales_engineer'
                        and a.target_id = 'refund.paid:' || t.id and a.status = 'done')
              and exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'customer_support'
                            and a.target_id = 'delivery.request:refund_issued:' || t.id and a.status = 'done'
                            and coalesce((a.evidence->>'delivered')::boolean, false));
    v_items := v_items || jsonb_build_object('item', 'customer_told',
      'passed', v_told, 'evidence', jsonb_build_object('handoff', 'refund.paid:' || t.id, 'delivery', 'delivery.request:refund_issued:' || t.id),
      'reason', 'the customer''s refund message was not handed off and delivered', 'kind', 'missed_handoff', 'remediable', true);
    if v_unresp and du.id is not null then
      v_sup_told := exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'sales_engineer'
                              and a.target_id in ('nonresponse.charge_raised:' || du.id, 'charge.corrected:' || du.id) and a.status = 'done')
                    and exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'customer_support'
                                  and a.target_id in ('delivery.request:nonresponse_charge:' || du.id, 'delivery.request:charge_corrected:' || du.id)
                                  and a.status = 'done' and coalesce((a.evidence->>'delivered')::boolean, false));
      v_items := v_items || jsonb_build_object('item', 'supplier_told',
        'passed', v_sup_told, 'evidence', jsonb_build_object('handoff', 'nonresponse.charge_raised:' || du.id),
        'reason', 'the supplier''s charge message was not handed off and delivered', 'kind', 'missed_handoff', 'remediable', true);
    end if;
    end if;
  else
    raise exception 'phase is approve or verify, not %', p_phase;
  end if;

  select coalesce(jsonb_agg(i), '[]'::jsonb) into v_failed from jsonb_array_elements(v_items) i where not coalesce((i->>'passed')::boolean, false);
  v_ok := jsonb_array_length(v_failed) = 0;
  if p_record then
    insert into public.refund_ceo_check (transaction_id, refund_id, phase, item, passed, reason, evidence)
    select t.id, v_rid, p_phase, i->>'item', coalesce((i->>'passed')::boolean, false),
           case when coalesce((i->>'passed')::boolean, false) then null else i->>'reason' end, coalesce(i->'evidence', '{}'::jsonb)
      from jsonb_array_elements(v_items) i;
  end if;
  return jsonb_build_object('ok', v_ok, 'phase', p_phase, 'transaction_id', t.id, 'refund_id', v_rid, 'items', v_items, 'failed', v_failed);
end $function$;

create or replace function public.fn_sales_engineer_acts_on_handoff(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  a public.agent_actions; d jsonb; t text;
  v_cust record; v_sup record; v_inq text; v_window int; v_chase int; v_min int; v_max int;
  v_tx public.transactions; v_amt text; v_req bigint; v_lines text; v_orig public.notifications;
  v_revealed text; v_rid text;
begin
  select * into a from public.agent_actions where id = p_id;
  d := a.detail; t := d->>'type';
  select refund_window_working_days, chase_after_working_days, bank_settlement_working_days_min, bank_settlement_working_days_max
    into v_window, v_chase, v_min, v_max from public.pricing_config order by id limit 1;
  v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3); v_min := coalesce(v_min, 7); v_max := coalesce(v_max, 14);

  select null::uuid as id, null::text as email, null::text as full_name into v_cust;
  select null::bigint as id, null::text as company_name, null::text as email into v_sup;
  if (d->>'customer_id') is not null then
    select id, email, full_name into v_cust from public.customers where id = (d->>'customer_id')::uuid;
  end if;
  if (d->>'supplier_id') is not null then
    select id, company_name, coalesce(claimed_by, email) as email into v_sup from public.leads where id = (d->>'supplier_id')::bigint;
  end if;
  if (d->>'inquiry_id') is not null then
    select summary into v_inq from public.inquiries where id = (d->>'inquiry_id')::uuid;
  end if;
  v_revealed := coalesce(to_char((d->>'revealed_at')::timestamptz at time zone 'Asia/Dubai', 'DD Mon YYYY'), 'the reveal date');
  v_rid := left(coalesce(d->>'transaction_id', d->>'subject_id', ''), 8);

  if t = 'reveal.paid' then
    -- The words trg_reveal_receipt used to write itself, unchanged, now composed by the seat whose
    -- voice the portal is and carried by the seat that owns the pipe.
    if v_cust.email is not null then
      v_req := public.fn_sales_engineer_writes('reveal_receipt', 'customer', v_cust.email, null, v_cust.id,
        (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
        'Reveal confirmed — ' || coalesce(v_sup.company_name, 'supplier'),
        'You have unlocked ' || coalesce(v_sup.company_name, 'the supplier') || '''s contact details'
          || coalesce(' for: ' || left(v_inq, 80), '')
          || '. You can now message them directly in the app. We track this reveal from the moment you paid: if the supplier has not responded within '
          || v_chase::text || ' working days we chase them for you and copy you; if there is still no response by working day '
          || v_window::text || ' the case is decided by our chief executive, and if the supplier never responded everything you paid is refunded in full. '
          || 'Banks usually take ' || v_min || '-' || v_max || ' working days to show a refund. You can also open the request and Report an issue at any time.',
        'اكتمل الكشف — ' || coalesce(v_sup.company_name, 'المورّد'),
        'أصبحت بيانات التواصل مع ' || coalesce(v_sup.company_name, 'المورّد') || ' متاحة لكم الآن، ويمكنكم مراسلته مباشرة من التطبيق. '
          || 'نتابع هذا الكشف منذ لحظة الدفع: إن لم يردّ المورّد خلال ' || v_chase::text || ' أيام عمل فسنتواصل معه نيابةً عنكم مع نسخة إليكم، '
          || 'وإن لم يردّ حتى يوم العمل ' || v_window::text || ' فسيبتّ رئيسنا التنفيذي في الحالة، وإن لم يردّ المورّد إطلاقًا فسنردّ إليكم كامل المبلغ المدفوع.',
        '{}', 'reveal_receipt:' || (d->>'subject_id'), null, jsonb_build_object('transaction_id', d->>'subject_id'));
    end if;
    if coalesce(v_sup.email, '') like '%@%' then
      perform public.fn_sales_engineer_writes('quote_accepted', 'supplier', v_sup.email, v_sup.id, null,
        (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
        'A customer revealed your quote on QuotesDone',
        'A customer paid to reveal your contact for: ' || coalesce(v_inq, '')
          || '. Please respond promptly — under the Supplier Agreement you must respond within ' || v_window::text
          || ' working days of the reveal. If you have not responded after ' || v_chase::text
          || ' working days we chase you with the customer copied; if there is still no response on working day ' || v_window::text
          || ' our chief executive decides the case, the customer is refunded, and the amount refunded, with the administrative fee, interest and other amounts set out in clause 33 of the Supplier Agreement you accepted, is recovered from your account.',
        'كشف أحد العملاء عن عرضكم على QuotesDone',
        'سدّد أحد العملاء رسوم الكشف عن بيانات التواصل معكم بشأن: ' || coalesce(v_inq, '') || '. نرجو المبادرة بالرد، إذ تُلزم اتفاقية المورّد بالرد خلال '
          || v_window::text || ' أيام عمل من تاريخ الكشف، وإلا فسيُردّ إلى العميل كامل ما دفعه، ويُسترد من حسابكم المبلغ المردود مع الرسم الإداري والفائدة وسائر المبالغ المبيّنة في البند 33 من اتفاقية المورّد التي قبلتموها.',
        '{}', 'quote_accepted:' || (d->>'subject_id'), null, jsonb_build_object('transaction_id', d->>'subject_id'));
    end if;
    return jsonb_build_object('customer_reachable', v_cust.email is not null,
                              'supplier_reachable', coalesce(v_sup.email, '') like '%@%',
                              'delivery_request', v_req);

  elsif t = 'payment.failed' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('reveal_payment_incomplete', 'customer', v_cust.email, null, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'Your reveal payment did not complete',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'Your payment to unlock the supplier''s contact details did not go through, and nothing was charged to your card.' || E'\n\n'
        || 'You can try again at any time: open the request in your QuotesDone portal and choose Reveal on the quote you picked. If the card was declined, your bank can tell you why, and a different card also works.',
      'لم يكتمل دفع رسوم الكشف',
      'تعذّر إتمام دفع رسوم الكشف عن بيانات المورّد، ولم يُخصم أي مبلغ من بطاقتكم. يمكنكم إعادة المحاولة في أي وقت من بوابتكم على QuotesDone.',
      '{}', 'payment_failed:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'payment.received' then
    if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes(coalesce(d->>'msg_type', 'dues_paid'), 'supplier', v_sup.email, v_sup.id, null, null, null,
      case when d->>'kind' = 'supplier_registration' then 'Registration confirmed - thank you' else 'Payment received - thank you' end,
      case when d->>'kind' = 'supplier_registration'
           then 'We have received your registration payment of AED ' || (d->>'amount_aed') || '. Your QuotesDone supplier account is registered for the next 12 months.'
           else 'We have received your payment of AED ' || (d->>'amount_aed') || ' settling ' || coalesce(d->>'items', '1') || ' outstanding charge(s). Your account is now up to date.' end,
      'استلمنا دفعتكم', 'استلمنا دفعتكم البالغة ' || (d->>'amount_aed') || ' درهم، ونشكركم على ذلك.',
      '{}', 'payment_received:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'refund.request_checked' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_amt := case when (d->>'money_ok')::boolean then ' — AED ' || (d->>'amount_aed') else '' end;
    v_req := public.fn_sales_engineer_writes('refund_request_received', 'customer', v_cust.email, null, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'We have your refund request',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'We have received your refund request for the reveal on ' || coalesce('"' || left(v_inq, 80) || '"', 'your request') || '.' || E'\n\n'
        || 'What happens next: we check whether the supplier ever replied to you, our chief executive decides on that record, and if the refund is due you get back everything you paid'
        || v_amt || ', the reveal fee and the card processing part together, to the card you paid with. Banks usually take ' || v_min || '–' || v_max || ' working days to show it.' || E'\n\n'
        || 'If you have an email thread with the supplier, keep it: it is the proof we rely on.',
      'استلمنا طلب الاسترداد',
      'استلمنا طلبكم استرداد رسوم الكشف. نتحقق أولًا من ردّ المورّد، ثم يبتّ رئيسنا التنفيذي في الطلب، فإن ثبت استحقاق الاسترداد فسيُعاد إليكم كامل المبلغ المدفوع إلى البطاقة نفسها خلال '
        || v_min || '–' || v_max || ' يوم عمل بحسب البنك.',
      '{}', 'refund_request_received:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req, 'money_ok', d->'money_ok');

  elsif t = 'refund.paid' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('refund_issued', 'customer', v_cust.email, (d->>'supplier_id')::bigint, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'Your QuotesDone refund of AED ' || (d->>'amount_aed') || ' has been issued',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'We have issued a refund of AED ' || (d->>'amount_aed') || ' — everything you paid on ' || v_revealed
        || ', the reveal fee and the card processing part together — to your original payment method, because the supplier did not respond within '
        || v_window::text || ' working days. Nothing is deducted.' || E'\n\n'
        || 'Banks and card issuers usually take ' || v_min || '–' || v_max || ' working days to show it on your statement. If it has not appeared after '
        || v_max || ' working days, reply to this email and we will trace it with the payment processor.' || E'\n\n'
        || 'You are welcome to post the request again; we will introduce you to another supplier.',
      'أصدرنا استردادًا بقيمة ' || (d->>'amount_aed') || ' درهم',
      'أصدرنا لكم استردادًا بقيمة ' || (d->>'amount_aed') || ' درهم، أي كامل المبلغ المدفوع، إلى وسيلة الدفع الأصلية، إذ لم يردّ المورّد خلال '
        || v_window::text || ' أيام عمل. وقد يستغرق ظهوره في كشف حسابكم ' || v_min || '–' || v_max || ' يوم عمل.',
      '{}', 'refund_issued:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req, 'amount_aed', d->'amount_aed');

  elsif t = 'refund.declined' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('refund_declined', 'customer', v_cust.email, null, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'About your refund request',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'We looked at your refund request for the reveal on ' || coalesce('"' || left(v_inq, 80) || '"', 'your request') || ' and it was not approved.' || E'\n\n'
        || 'The reason: ' || coalesce(nullif(btrim(d->>'note'), ''), 'the record shows the supplier did respond.') || E'\n\n'
        || 'If you think we have missed something, reply to this email with what you have — an email thread with the supplier, dates, anything — and we will look again.',
      'بشأن طلب الاسترداد',
      'راجعنا طلب الاسترداد وتعذّرت الموافقة عليه. السبب: ' || coalesce(nullif(btrim(d->>'note'), ''), 'يُظهر السجل أن المورّد قد ردّ.')
        || ' وإن كان لديكم ما يثبت خلاف ذلك، فيسعدنا أن تردّوا على هذه الرسالة لنعيد النظر في الطلب.',
      '{}', 'refund_declined:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'refund.in_progress' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('refund_in_progress', 'customer', v_cust.email, null, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'Your refund is being processed',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'Your refund of AED ' || coalesce(d->>'amount_aed', '') || ' has been approved and is being processed with the payment provider. It has not reached your card yet; we will write again the moment it has.',
      'استردادكم قيد المعالجة',
      'وافقنا على استردادكم، وهو الآن قيد المعالجة لدى مزوّد الدفع ولم يصل إلى بطاقتكم بعد. وسنُعلمكم فور وصوله.',
      '{}', 'refund_in_progress:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t in ('nonresponse.charge_raised', 'charge.corrected') then
    if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
    v_lines := '  Amount refunded to the customer: AED ' || (d->>'refunded_aed') || E'\n'
            || case when coalesce((d->>'processor_fee_aed')::numeric, 0) > 0
                    then '  Payment processor fee we could not recover (clause 33(b)): AED ' || (d->>'processor_fee_aed') || E'\n' else '' end
            || '  Administration fee: AED ' || (d->>'admin_fee_aed') || E'\n'
            || '  Interest: ' || round((d->>'interest_apr')::numeric * 100, 2) || '% a year, simple, on AED '
            || round(coalesce((d->>'charge_aed')::numeric, (d->>'refunded_aed')::numeric) + (d->>'admin_fee_aed')::numeric, 2) || ' from ' || (d->>'due_date') || ' until paid' || E'\n'
            || '  Due by: ' || (d->>'due_date')
            || case when coalesce((d->>'signed_version')::int, 0) >= 14
                    then E'\n  If it is not paid by then, the official fees of recovering it (court, payment-order, execution and notary fees) are added at cost (clause 33).' else '' end;
    if t = 'nonresponse.charge_raised' then
      v_req := public.fn_sales_engineer_writes('nonresponse_charge', 'supplier', v_sup.email, v_sup.id, null,
        (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
        'Charge under the Supplier Agreement — reveal #' || left(coalesce(d->>'transaction_id', ''), 8),
        'Hello ' || coalesce(v_sup.company_name, '') || E',\n\n'
          || 'A customer paid to reveal your contact details and did not hear from you within ' || v_window::text
          || ' working days, despite the reminders we sent. Under the Supplier Agreement the customer has been refunded in full, and that refund is recovered from your account:' || E'\n\n'
          || v_lines || E'\n\n'
          || 'Matching is paused until this is settled. You can pay it from the Billing section of your supplier portal. If you believe it is wrong, use "Dispute this charge" there or reply to this email and we will check the figures against the payment record.',
        'رسوم بموجب اتفاقية المورّد',
        'سدّد أحد العملاء رسوم الكشف عن بيانات التواصل معكم ولم يتلقَّ ردًّا خلال ' || v_window::text || ' أيام عمل رغم التذكيرات، فرُدّ إليه كامل ما دفعه بموجب اتفاقية المورّد، ويُسترد من حسابكم ما يلي: المبلغ المسترد '
          || (d->>'refunded_aed') || ' درهم، '
          || case when coalesce((d->>'processor_fee_aed')::numeric, 0) > 0 then 'ورسوم مزوّد خدمة الدفع التي لم نتمكن من استردادها ' || (d->>'processor_fee_aed') || ' درهم، ' else '' end
          || 'ورسوم إدارية ' || (d->>'admin_fee_aed') || ' درهم، وفائدة بسيطة ' || round((d->>'interest_apr')::numeric * 100, 2)
          || '% سنويًا من ' || (d->>'due_date') || ' حتى السداد.'
          || case when coalesce((d->>'signed_version')::int, 0) >= 14 then ' وإن لم يُسدَّد المبلغ في موعده، تُضاف بالتكلفة الرسوم الرسمية لتحصيله (رسوم المحكمة وأمر الأداء والتنفيذ والتوثيق) (البند 33).' else '' end
          || ' ويمكنكم السداد أو الاعتراض من قسم الفواتير في بوابتكم.',
        '{}', 'nonresponse_charge:' || (d->>'subject_id'));
    else
      -- THE CORRECTION MUST REACH WHOEVER GOT THE ORIGINAL: its To and every Cc, not today's address book.
      select * into v_orig from public.notifications where id = (d->>'original_notification_id')::bigint;
      v_req := public.fn_sales_engineer_writes('nonresponse_charge_correction', 'supplier',
        coalesce(v_orig.to_email, v_sup.email), v_sup.id, null, (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
        'Correction: ' || coalesce(v_orig.subject, 'your charge under the Supplier Agreement'),
        'This replaces our message of ' || coalesce(to_char(v_orig.created_at at time zone 'Asia/Dubai', 'DD Mon YYYY'), 'earlier')
          || ' about this charge, which carried the wrong figures. Please disregard it. The correct figures are:' || E'\n\n' || v_lines,
        'تصحيح: رسوم بموجب اتفاقية المورّد',
        'هذه الرسالة تحلّ محلّ رسالتنا السابقة التي تضمنت أرقامًا غير صحيحة. الأرقام الصحيحة: المبلغ المسترد ' || (d->>'refunded_aed')
          || ' درهم، ' || case when coalesce((d->>'processor_fee_aed')::numeric, 0) > 0 then 'ورسوم مزوّد خدمة الدفع ' || (d->>'processor_fee_aed') || ' درهم، ' else '' end || 'ورسوم إدارية ' || (d->>'admin_fee_aed') || ' درهم، مستحقة في ' || (d->>'due_date') || '.',
        coalesce(v_orig.cc_emails, '{}'), 'charge_corrected:' || (d->>'subject_id'));
    end if;
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'subscription.due' then
    if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('subscription_due', 'supplier', v_sup.email, v_sup.id, null, null, null,
      'Your QuotesDone annual subscription is due',
      'Dear ' || coalesce(v_sup.company_name, 'there') || E',\n\nYour QuotesDone annual supplier subscription of '
        || coalesce(d->>'currency', 'AED') || ' ' || (d->>'fee') || E' is now due.\n\nYou keep paying no commission on the jobs you win — this is the annual subscription only. You can settle it securely on the supplier portal: https://quotesdone.com/suppliers\n\nIf it is not settled, your profile is paused from receiving new customer requests until it is.\n\nThank you for being part of QuotesDone.',
      'اشتراككم السنوي في QuotesDone مستحق',
      'حان موعد سداد اشتراككم السنوي كمورّد بقيمة ' || (d->>'fee') || ' درهم، ويمكنكم السداد بأمان من بوابة المورّد.',
      '{}', 'subscription_due:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'billing.answer' then
    v_lines := (select string_agg('  ' || x, E'\n') from jsonb_array_elements_text(d->'facts') x);
    if d->>'party' = 'supplier' then
      if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
      v_req := public.fn_sales_engineer_writes('billing_answer', 'supplier', v_sup.email, v_sup.id, null, null, null,
        'Your question about a charge', E'Here is what our records show:\n\n' || coalesce(v_lines, '  Nothing is recorded against your account.'),
        null, null, '{}', 'billing_answer:' || (d->>'subject_id'));
    else
      if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
      v_req := public.fn_sales_engineer_writes('billing_answer', 'customer', v_cust.email, null, v_cust.id, null, null,
        'Your question about a charge', E'Here is what our records show:\n\n' || coalesce(v_lines, '  No payment is recorded on your account.'),
        null, null, '{}', 'billing_answer:' || (d->>'subject_id'));
    end if;
    return jsonb_build_object('delivery_request', v_req, 'facts', d->'facts');

  elsif t = 'charge.dispute_answer' then
    if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
    v_lines := (select string_agg('  ' || x, E'\n') from jsonb_array_elements_text(d->'lines') x);
    v_req := public.fn_sales_engineer_writes('charge_dispute_answer', 'supplier', v_sup.email, v_sup.id, null, null, null,
      'Your query about charge #' || coalesce(d->>'due_id', ''),
      case when (d->>'figures_match')::boolean
           then E'We checked the charge against the payment record and the figures stand:\n\n'
           else E'We checked the charge against the payment record and the figures do not match it. It is on hold while our chief executive reviews it; you do not need to pay it until we write again.\n\n' end
        || coalesce(v_lines, ''),
      null, null, '{}', 'charge_dispute_answer:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req, 'figures_match', d->'figures_match');

  elsif t = 'refund.remediate' then
    return public.fn_sales_engineer_remediates(p_id);

  elsif t = 'delivery.result' then
    return public.fn_sales_engineer_attaches_delivery_result(p_id);

  elsif t in ('backup.refile', 'backup.remediate') then
    return public.fn_sales_engineer_refiles_backup(p_id);
  end if;
  raise exception 'sales_engineer has no handler for %', t;
end $function$;

create or replace function public.fn_company_hard_rules()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_pct numeric; v_free date; v_fee numeric; v_win int; v_chase int; v_bmin int; v_bmax int; v_admin numeric; v_int numeric;
  v_free_n int; v_cat_min int;
  v_txt text; v_days text; v_aed text; v_mult text; v_src text;
begin
  select round(coalesce(standard_reveal_rate, 0.03) * 100, 2), supplier_charging_starts, supplier_reg_fee,
         refund_window_working_days, chase_after_working_days, bank_settlement_working_days_min, bank_settlement_working_days_max,
         coalesce(supplier_free_count, 1000), coalesce(category_open_min_suppliers, 10)
    into v_pct, v_free, v_fee, v_win, v_chase, v_bmin, v_bmax, v_free_n, v_cat_min
    from public.pricing_config order by id limit 1;
  v_pct := coalesce(v_pct, 3); v_win := coalesce(v_win, 5); v_chase := coalesce(v_chase, 3);
  v_free_n := coalesce(v_free_n, 1000); v_cat_min := coalesce(v_cat_min, 10);
  -- 6 Sep 2026: the money side of the ladder, from decision_policy (founder ruling, verbatim there)
  v_admin := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_admin_fee_aed'), 250);
  v_int   := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_late_fee_annual_pct'), 9);

  v_txt := regexp_replace(coalesce((select p.html from public.pages p where p.slug = 'legal_supplier_body'), ''),
                          '<[^>]+>', ' ', 'g');
  v_days := substring(v_txt from 'begin responding to the Customer within\s+([0-9]+)\s+working days');
  v_aed  := substring(v_txt from 'liquidated compensation of AED\s+([0-9,]+)\s+per incident');
  v_mult := substring(v_txt from 'per incident, or\s+([a-z]+ \([0-9]+\)|[0-9]+)\s+times the fee');
  v_src  := case when v_days is not null and v_aed is not null and v_mult is not null
                 then 'read from the published Supplier Agreement and pricing_config just now'
                 else 'pricing_config live; the Supplier Agreement text did not match the expected clause wording, so the last published figures are stated' end;

  return '# THE FOUR HARD RULES - the published Terms and Supplier Agreement; the founder''s ONLY rules ('||v_src||'). No employee may relax them.'||E'\n'
    ||'1. REVEAL FEE: the CUSTOMER pays '||v_pct||'% of the selected quotation value - NO cap, NO discount, NO promotional rate, NO coupon and NO free reveal (founder, 6 Sep 2026; pricing_config forbids them by constraint) - ex-VAT, once per reveal, to reveal a supplier. Comparing quotes is FREE. Suppliers pay NO commission, ever'
    ||case when v_free is not null
           then '; supplier registration is free until '||to_char(v_free - 1, 'DD Mon YYYY')||', then AED '||coalesce(v_fee::text,'1000')||'/year (first '||v_free_n||' registrants permanently exempt)'
           else '; supplier registration is FREE for the first '||v_free_n||' registrations (permanently exempt), then AED '||coalesce(v_fee::text,'1000')||'/year - there is NO calendar start date: charging begins with registration '||(v_free_n + 1)||', whenever that happens (founder, 6 Sep 2026)' end||'.'||E'\n'
    ||'2. TOP-3 COMPARISON REPORT: however many quotations arrive (3 or 100+), the report ranks them ALL and shows the best THREE on technical AND commercial merit - never cheapest-wins.'||E'\n'
    ||'3. SUPPLIER NON-RESPONSE: a revealed supplier must begin responding within '||coalesce(v_days, v_win::text)||' working days of the customer''s PAYMENT (UAE week: Mon-Fri, Sat+Sun off, public holidays excluded). '
    ||'THE LADDER (founder ruling 6 Sep 2026, final; pricing_config): the supplier has '||v_win||' working days from payment. No response by working day '||v_chase||' - the Customer Success Director chases the supplier, customer copied; still silent on working day '||v_win||' - the CEO is notified for the final call; no response to that - the refund is issued. '
    ||'Every refund of any amount is the CEO''s decision and never automatic (founder, 8 Sep 2026: "refunds belong to the CEO from now on" and "all approvals are from CEO. nothing goes to me" - this SUPERSEDES the 6 Sep ruling; public.refunds enforces it with triggers z00_refund_ceo_approval_only and z05_refund_execution_requires_ceo_approval, which refuse a refund with no matching ceo_approval row). The customer gets the FULL reveal fee back (the '||v_pct||'% paid, nothing deducted) and is told banks take '||coalesce(v_bmin,7)||'-'||coalesce(v_bmax,14)||' working days. '
    ||'The supplier then owes the exact amount refunded (the '||v_pct||'%) + from Supplier Agreement v14 the payment processor fee QuotesDone could not recover + AED '||v_admin||' administrative fee + '||v_int||'% per annum simple interest (the rate AGREED in v14 clauses 31 and 33, Commercial Transactions Law 50/2022 Arts. 73 and 84; a supplier charged under v13 or earlier pays 9%, under v12 or earlier AED 250) + if unpaid the official recovery fees, and is blocked from matching until it is paid. Never ask the founder about any of this again.'||E'\n'
    ||'4. ANTI-CIRCUMVENTION: identities stay anonymous until the reveal and there is no off-platform contact before it. A supplier that takes an introduced customer off-platform within 24 months owes AED '||coalesce(v_aed, '15,000')||' per incident OR '||coalesce(v_mult, 'three (3)')||' times the fee, whichever is higher, plus the unpaid fee.'||E'\n'
    ||'5. CATEGORY OPENING (founder''s standing decision, 6 Sep 2026): a category is OPEN once it has '||v_cat_min||' verified registered suppliers (public.v_category_open); matching an RFQ still needs at least one confirmed supplier. Never ask the founder about any figure in these five lines.'||E'\n';
end $function$;

create or replace function public.fn_company_self_knowledge_sync()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_state jsonb := public.fn_company_state();
  v_snap  jsonb := public.fn_company_snapshot();
  v_brief text  := public.fn_company_brief(6000);
  v_fee   numeric; v_sup_fee numeric; v_charge date; v_refund_wd int; v_cur text; v_free_n int; v_cat_min int;
  v_chase_wd int; v_bank_min int; v_bank_max int; v_admin numeric; v_pct numeric; v_founder_words text;
  v_target text; v_deadline text;
  v_social text; v_social_at text; v_blog text; v_blog_at text;
  v_founder text;
  v_tmpl text;
  v_rev numeric; v_exp numeric; v_pnl text;
  v_stance record; v_decisions text; v_cat_open text;
  v_records jsonb; r jsonb; v_rid text; v_n int := 0;
  reg public.company_registration%rowtype;
  -- 6 SEP 2026: the two supplier loops (acquisition, sanctions screening) — live values for the record below
  v_golive boolean; v_reg_target text; v_reg_month text; v_supply_owner text; v_co text; v_last_un text; v_last_uae text;
  v_hits_open int; v_invited int; v_registered int; v_followups int; v_intake int;
begin
  v_golive := public.fn_supplier_outreach_golive();
  select coalesce(target_value::text, '300') into v_reg_target from public.company_goals where key = 'suppliers_registered_monthly';
  select coalesce(actual_value::text, '0') || ' (measured ' || coalesce(to_char(measured_at, 'DD Mon YYYY HH24:MI'), 'not yet') || ' UTC)'
    into v_reg_month from public.employee_kpi where agent_key = 'sales_engineer' and kpi = 'Suppliers registered per month' and active;
  select display_name into v_supply_owner from public.org_role where role_id = 'sales_engineer';
  select display_name into v_co from public.org_role where role_id = 'ceo';
  select entries || ' entries, fetched ' || to_char(fetched_at, 'DD Mon YYYY HH24:MI') || ' UTC, sha256 ' || left(coalesce(sha256, '?'), 12) || ', ' || status
    into v_last_un from public.screening_run where source = 'un_consolidated' and run_tag is null order by id desc limit 1;
  select entries || ' entries, fetched ' || to_char(fetched_at, 'DD Mon YYYY HH24:MI') || ' UTC, sha256 ' || left(coalesce(sha256, '?'), 12) || ', ' || status
    into v_last_uae from public.screening_run where source = 'uae_local_terrorist_list' and run_tag is null order by id desc limit 1;
  select count(*) into v_hits_open from public.supplier_screening_hit where status = 'open';
  select count(*) filter (where invite_status is not null), count(*) filter (where lifecycle_stage = 'registered'), coalesce(sum(invite_followups), 0)
    into v_invited, v_registered, v_followups from public.leads where coalesce(email, '') not ilike '%@example.invalid';
  select count(*) into v_intake from public.supplier_lead_intake where run_tag is null;
  select * into reg from public.company_registration order by recorded_at desc limit 1;
  -- the founder identity (who leads the company). 9 SEP 2026 -- PHASE MACHINERY REMOVED: this read
  -- the founder-identity register, which is deleted in this sweep. It was never an authority
  -- check here, only the address printed in the "who we are" knowledge record, so it is read from
  -- app_secrets.founder_email -- the same place fn_page_high_agent_action already reads it -- and
  -- falls back to the same literal the record already carried.
  select value into v_founder from public.app_secrets where key = 'founder_email';
  -- the live P&L (financial state beyond headline revenue)
  select coalesce(sum(amount) filter (where type='revenue'),0), coalesce(sum(amount) filter (where type='expense'),0),
         string_agg(case when amount <> 0 then '  - '||type||': '||name||' = AED '||amount::text else null end, E'\n' order by type, code)
    into v_rev, v_exp, v_pnl from public.gl_pnl;
  select standard_reveal_rate, supplier_reg_fee, supplier_charging_starts, refund_window_working_days,
         coalesce(reveal_currency,'AED'), chase_after_working_days, bank_settlement_working_days_min, bank_settlement_working_days_max,
         coalesce(supplier_free_count,1000), coalesce(category_open_min_suppliers,10)
    into v_fee, v_sup_fee, v_charge, v_refund_wd, v_cur, v_chase_wd, v_bank_min, v_bank_max, v_free_n, v_cat_min
    from public.pricing_config order by id limit 1;
  -- 6 SEP 2026: the refund ladder's money side and the founder's own words, from decision_policy
  v_admin := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_admin_fee_aed'), 250);
  v_pct   := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_late_fee_annual_pct'), 9);
  v_founder_words := (select d.value #>> '{}' from public.decision_policy d where d.key = 'refund_policy_founder_decision_2026_09_06');
  -- 6 SEP 2026: the founder's budget stance and his decisions on record (company_financial_stance,
  -- company_policy_decision), and the category-open count (v_category_open)
  select * into v_stance from public.company_financial_stance where id = 1;
  select string_agg('- ' || upper(decision_key) || ' (decided ' || to_char(decided_on,'DD Mon YYYY') || ' by the ' || decided_by
                    || case when never_ask_again then '; NEVER ask about it again' else '' end || '): ' || decision_text
                    || case when cardinality(applies_to) > 0 then ' [applies to: ' || array_to_string(applies_to, ', ') || ']' else '' end,
                    E'\n' order by decision_key)
    into v_decisions from public.company_policy_decision;
  select count(*) filter (where is_open) || ' of ' || count(*) || ' categories are OPEN today (' ||
         coalesce(max(verified_registered_suppliers),0) || ' is the highest verified-registered count in any category)'
    into v_cat_open from public.v_category_open;

  select coalesce(target_value::text,'1000000'), coalesce(to_char(deadline,'DD Mon YYYY'),'31 Aug 2027')
    into v_target, v_deadline
    from public.company_goals
   where active and (lower(coalesce(key,'')) like '%revenue%' or lower(coalesce(goal,'')) like '%revenue%'
                     or category = 'Financial')
   order by sort nulls last limit 1;

  select left(coalesce(content->>'text', content->>'body', content::text), 240), to_char(created_at,'DD Mon YYYY')
    into v_social, v_social_at from public.social_posts order by created_at desc limit 1;
  select title, to_char(coalesce(published_at, updated_at),'DD Mon YYYY')
    into v_blog, v_blog_at from public.blog_posts where published order by published_at desc nulls last limit 1;

  -- 9 SEP 2026 -- PHASE MACHINERY REMOVED. v_funnel was a listing of W04..W18 read from
  -- the programme workflow registry, appended to the marketplace knowledge record as "The 30 workflows
  -- that run this". The workflow registry is deleted in this sweep and the company is two agents
  -- with no departments and no W-numbered programme, so the sentence is dropped rather than left
  -- describing an organisation that no longer exists. The prose above still explains the funnel in
  -- plain words, which is what an agent answering a question actually needs.

  -- 6 SEP 2026: the WhatsApp template ledger (messaging_template), one line per template, live.
  select coalesce(string_agg('  - ' || template_key || ' [' || lang || ']: ' || upper(status) || ' (' || sid
           || coalesce(', ' || category, '') || coalesce(', submitted ' || to_char(submitted_at, 'DD Mon YYYY'), '')
           || coalesce(', approved (first seen ' || to_char(approved_at, 'DD Mon YYYY') || ')', '')
           || coalesce(', reason: ' || left(rejection_reason, 90), '') || coalesce(', ' || note, '') || ')',
           E'\n' order by template_key, lang), '  (no templates recorded)')
    into v_tmpl from public.messaging_template where channel = 'whatsapp';

  v_records := jsonb_build_array(

    -- 6 SEP 2026: the company's registration and tax status, from company_registration (the founder
    -- supplied the trade licence and ruled on VAT, Corporate Tax and the auditor that day; all are
    -- closed facts, never questions).
    jsonb_build_object('rid','registration','module','company_registration',
      'title','QuotesDone — Trade licence, registration and tax status',
      'kw', to_jsonb(array['trade licence','trade license','licence number','license number','DET','department of economy and tourism',
        'issuing authority','licence expiry','renewal','activity code','portal','software design','trader licence','e-trader',
        'VAT','vat registered','TRN','tax registration number','FTA','federal tax authority','threshold','375,000','corporate tax',
        'corporate tax registration','CT registration','small business relief','auditor','external auditor','audit firm','who audits us',
        'are we vat registered','do we charge vat','company registration','legal entity','owner','who owns the licence']),
      'content',
        case when reg.license_no is null then 'REGISTRATION: not recorded.' else
        'TRADE LICENCE: ' || reg.authority || ' ' || reg.license_type || ' no. ' || reg.license_no || ', trade name "' || reg.trade_name || '"; issued ' ||
        to_char(reg.issued_on,'DD Mon YYYY') || ', expires ' || to_char(reg.expires_on,'DD Mon YYYY') || ' (renew before then; renewal is a company task, not a founder question).' || E'\n' ||
        'OWNER: ' || reg.owner_name || ' (' || reg.owner_share || '); licensed activities: ' || reg.activities || '.' || E'\n' ||
        'REGISTERED CONTACT: ' || reg.registered_email || ', ' || reg.registered_mobile || '; e-stores on the licence: ' || reg.e_stores || '.' || E'\n' ||
        'LICENCE CLASS: ' || reg.license_class_note || E'\n' ||
        'TAX STATUS: ' || case when reg.vat_registered then 'VAT-registered, TRN ' || coalesce(reg.trn,'?') else
          'NOT VAT-registered (founder ruling ' || to_char(reg.vat_ruling_on,'DD Mon YYYY') || '): no VAT is charged or shown on any QuotesDone invoice until taxable supplies reach the FTA mandatory registration threshold of AED ' ||
          to_char(reg.vat_threshold_aed,'FM999,999,999') || ' in a rolling 12 months. Do not ask the founder about VAT or the TRN; when revenue approaches the threshold the CFO opens a registration task.' end || E'\n' ||
        'CORPORATE TAX: ' || coalesce(reg.corporate_tax_note,'registration status not recorded.') || E'\n' ||
        'AUDITOR: ' || coalesce(reg.auditor,'not recorded.')
        end),

    jsonb_build_object('rid','identity','module','company_identity',
      'title','QuotesDone — Identity, Vision and Mission',
      'kw', to_jsonb(array['vision','mission','what is quotesdone','who are we','company','marketplace','target','revenue goal','anonymous','uae','b2b',
        'who is the founder','company founder','who owns quotesdone','founder name','ahmad alzain','the owner',
        'company target and deadline','revenue target','what is our goal','aed 1 million target','1000000 by 2027','when is the deadline']),
      'content',
        'WHO WE ARE. ' || coalesce(v_state->>'mission','') || E'\n' ||
        'VISION: ' || coalesce(v_state->>'vision','') || E'\n' ||
        'TARGET: AED ' || v_target || ' in revenue by ' || v_deadline ||
          ' — every department''s objectives trace to this one number.' || E'\n' ||
        'HOW IT WORKS IN ONE LINE: an anonymous UAE B2B quotation marketplace — buyers post an RFQ, verified UAE '
        'suppliers submit quotes, and the buyer pays a small reveal fee to unlock and contact a chosen supplier. '
        'Every department is an autonomous AI expert that plans and executes toward the vision.' || E'\n' ||
        'FOUNDER / OWNER: Ahmad Alzain (' || coalesce(v_founder,'management@quotesdone.com') || '). The company is '
        'founder-led: he sets the vision, the target and the boundaries, and he is the ONLY approver of refunds. '
        'The AI departments run everything else on their own.'),

    jsonb_build_object('rid','financials','module','financials',
      'title','QuotesDone — Our Financials (live P&L) and the Budget Policy',
      'kw', to_jsonb(array['financials','finance','p&l','profit and loss','expenses','costs','revenue','how much did we spend','what were our expenses','net','burn','money','accounting','are we profitable',
        'budget','budget limit','budget policy','do we have a budget','budget variance','over budget','spending limit','when do we set budgets','profitable']),
      'content',
        'LIVE FINANCIAL STATE (from the general ledger; refreshes):' || E'\n' ||
        '  Total revenue: AED ' || round(coalesce(v_rev,0),2)::text || '  ·  Total expenses: AED ' || round(coalesce(v_exp,0),2)::text ||
        '  ·  Net: AED ' || round(coalesce(v_rev,0)-coalesce(v_exp,0),2)::text || E'\n' ||
        'By account (non-zero lines):' || E'\n' || coalesce(v_pnl,'  (no posted amounts yet)') || E'\n' ||
        'Read it honestly: revenue is ' || case when coalesce(v_rev,0)=0 then 'AED 0 because the marketplace is pre-launch' else 'as above' end ||
        '; the spend so far is mostly software and AI infrastructure while the company is being built.' || E'\n' ||
        'BUDGET POLICY (founder, ' || coalesce(to_char(v_stance.decided_on,'DD Mon YYYY'),'6 Sep 2026') || '): ' ||
          coalesce(v_stance.policy_text, 'No budget limit while costs are subscriptions; budgets come with profitability.') ||
          ' Current stance: ' || case when coalesce(v_stance.is_profitable,false) then 'PROFITABLE - budgets apply and budget-variance alerts are live.'
                                     else 'NOT YET PROFITABLE - budget_mode ' || coalesce(v_stance.budget_mode,'unlimited_until_profitable') ||
                                          '; there is no budget limit, and budget-variance alerts and budget-limit checks are inert. Do not ask the founder for a budget.' end),

    jsonb_build_object('rid','operating-model','module','operating_model',
      'title','QuotesDone — How the Marketplace Works, End to End',
      'kw', to_jsonb(array['funnel','operating model','how it works','journey','inquiry','rfq','routing','packaging','dispatch','reveal','pipeline','workflow']),
      'content',
        'THE FUNNEL. A customer''s job travels the pipeline autonomously:' || E'\n' ||
        '  W04 register/onboard the customer → W05 intake and qualify the inquiry (RFQ) → W06 route it to the right '
        'category → W07 process any drawings/BOQ/documents → W08 build and approve a supplier-SAFE package (customer '
        'identity and any contact details stripped) → W09/W10 onboard and verify suppliers → W12 match and dispatch to '
        'enough confirmed suppliers → W13 notify them → W14 suppliers submit and we evaluate quotations → W15 build the '
        'top-3 comparison and reveal path → W16 the customer pays the reveal fee and gets supplier contact → W17 handles '
        'any refund/dispute, W18 support and retention.' || E'\n' ||
        'ANONYMITY: buyers and suppliers never see each other until the buyer pays to reveal. Quotes are anonymized/'
        'masked until then.' ),

    jsonb_build_object('rid','commercials','module','commercials',
      'title','QuotesDone — Fees, Pricing and Refund Terms (live)',
      'kw', to_jsonb(array['fee','reveal fee','review fee','pricing','how much','commission','refund','supplier fee','registration fee','late fee','cost','price','supplier charging','when does supplier charging start','how much do suppliers pay','are suppliers charged','supplier registration','supplier pays',
        'discount','promo','promotion','coupon','free reveal','cap','fee cap','maximum fee','first 1000','first 1,000','open category','category open','when is a category open','how many suppliers to open a category']),
      'content',
        'REVEAL FEE (what the customer pays to unlock a supplier): ' || round(v_fee*100,2) || '% of the deal, in ' || v_cur ||
          ' — read live from pricing_config, so this figure is always the current one. NO cap, NO discount, NO promotional rate, '
          'NO coupon and NO free reveal exist or may be offered (founder, 6 Sep 2026; pricing_config forbids them by constraint).' || E'\n' ||
        'SUPPLIERS: ' || case when v_charge is null
          then 'registration is FREE for the first ' || v_free_n || ' registrations (those suppliers are exempt permanently); every registration after them pays ' ||
               coalesce(v_sup_fee::text,'1000') || ' ' || v_cur || ' per year. There is NO calendar start date and never will be: charging begins with registration ' ||
               (v_free_n + 1) || ', whenever that happens (founder, 6 Sep 2026). Never state a date; never ask the founder for one.'
          else 'registration is FREE until ' || to_char(v_charge,'DD Mon YYYY') || ', then ' || coalesce(v_sup_fee::text,'1000') || ' ' || v_cur || ' per year.' end ||
          ' Suppliers are auto-approved on a verified file.' || E'\n' ||
        'CATEGORY OPENING: a category is OPEN once it has ' || v_cat_min || ' verified registered suppliers (public.v_category_open); ' ||
          coalesce(v_cat_open, '') || '. Matching an RFQ still needs at least one confirmed supplier.' || E'\n' ||
        'REFUNDS: the supplier has ' || coalesce(v_refund_wd::text,'5') || ' UAE working days from the customer''s payment (Mon-Fri; Sat+Sun off; public holidays excluded). '
        'No response by working day ' || coalesce(v_chase_wd::text,'3') || ': the Customer Success Director chases the supplier, customer copied. Still silent on working day ' || coalesce(v_refund_wd::text,'5') ||
        ': the founder is notified for his final call. No response to that: the customer is refunded the FULL reveal fee (the 3% paid, no deduction) - EVERY refund of any amount is the founder''s approval - and told banks take '
        || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days. The supplier then owes the exact amount refunded (the 3%) + from Supplier Agreement v14 the payment processor fee QuotesDone could not recover + AED ' || v_admin::text || ' administrative fee + '
        || v_pct::text || '% p.a. simple interest (the agreed rate of v14; 9% under v13 or earlier), per the Supplier Agreement version it had accepted at the reveal (fn_accountant_nonresponse_charge). Full record: qd-company:refunds.' || E'\n' ||
        'LATE FEE on overdue recoverables: ' || v_pct::text || '% per annum simple, the rate agreed in Supplier Agreement v14 clause 31 (Federal Decree-Law 50/2022 Arts. 73 and 84; 9% for amounts due under v13 or earlier).'),

    jsonb_build_object('rid','comparison-report','module','comparison_report',
      'title','QuotesDone — The Top-3 Comparison Report',
      'kw', to_jsonb(array['comparison report','compare','top 3','top three','quote comparison','ranking','shortlist','quote_compare','how do we compare','side by side']),
      'content',
        'THE COMPARISON REPORT IS ALWAYS THE TOP 3. However many quotations arrive — 3 or 100 — quote_compare ranks '
        'them ALL and returns the top three (ranks 1, 2, 3). It is NOT cheapest-wins: quotes are scored across multiple '
        'technical and commercial factors — price positioned across the range of offers, lead time, warranty, scope match, '
        'payment terms — so the strongest overall quote wins, not merely the lowest. The ranking is deterministic; the model '
        'writes the plain-language explanation of why the top three are the top three. The customer sees an anonymized '
        'side-by-side comparison table, saveable as a PDF, and only then decides whom to reveal.'),

    jsonb_build_object('rid','quotation-format','module','quotation_format',
      'title','QuotesDone — What a Supplier Quotation Contains',
      'kw', to_jsonb(array['quotation format','quote format','what is in a quote','quote fields','lead time','validity','payment terms','warranty','scope','exclusions','anonymized']),
      'content',
        'A supplier quotation carries: the quote amount, lead time, validity period, payment terms, warranty, scope of '
        'supply, conditions, exclusions, and notes. It may be typed or extracted from an uploaded file, then structured '
        'and committed (hashed) so it cannot be silently changed. BEFORE the customer sees it, the supplier''s identity '
        'and any contact details are anonymized/masked. The price the customer sees (customer_price) includes the '
        'platform margin/app fee on top of the supplier''s amount.'),

    jsonb_build_object('rid','terms','module','terms_and_conditions',
      'title','QuotesDone — Terms, Anonymity and Working Days',
      'kw', to_jsonb(array['terms','conditions','t&c','anonymous','reveal','working days','jurisdiction','policy','rules','uae']),
      'content',
        'QuotesDone is an ANONYMOUS UAE B2B marketplace. Suppliers are verified before they can quote. Buyer and supplier '
        'identities are hidden from each other until the buyer pays the reveal fee to contact a chosen supplier. All time '
        'windows use UAE working days (Asia/Dubai; Friday is a working day; the weekend is Saturday and Sunday; public '
        'holidays excluded). The reveal refund ladder is ' || coalesce(v_refund_wd::text,'5') || ' working days from payment: chase at '
        || coalesce(v_chase_wd::text,'3') || ', founder''s final call on day ' || coalesce(v_refund_wd::text,'5') || ', refund in full on no response, banks '
        || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days. Late fees '
        'follow UAE Federal Decree-Law 50/2022 (9% p.a.). The platform mediates disputes through a defined escalation ladder.'),

    jsonb_build_object('rid','governance','module','governance',
      'title','QuotesDone — How the Company Governs Itself',
      'kw', to_jsonb(array['governance','who approves','autonomy','refund approval','founder','escalation','boundaries','decisions','authority']),
      'content',
        'QuotesDone runs as ten autonomous AI departments (90 brain agents) that plan and execute toward the vision '
        'WITHOUT needing the founder''s approval for ordinary work. The founder is escalated to only for: money that '
        'leaves the company (every refund, any amount, needs his approval), destructive/irreversible production changes, '
        'and decisions only he holds (his intentions, external credentials, commercial direction). Everything else — '
        'routing, packaging, matching, pricing within policy, content — the agents decide and own. Colleagues hand work '
        'to one another through defined handoffs; nothing is left unowned.'),

    -- DYNAMIC: regenerated from the live org every run.
    jsonb_build_object('rid','organization','module','organization',
      'title','QuotesDone — The Organization: Departments, Colleagues and Roles',
      'kw', to_jsonb(array['organization','org chart','departments','how many agents','who works here','colleagues','roles','manager','line manager','team','north star','who does what','name the ten departments','list the departments','what are our departments','department names','the 10 departments']),
      'content', 'THE COMPANY YOU WORK IN (live roster — these are your colleagues; know who does what and who leads each team).' || E'\n' ||
        'THE TEN DEPARTMENTS: ' || coalesce((select string_agg(name, ', ' order by sort nulls last, dept_key) from public.org_departments where active),'') || E'\n' ||
        coalesce(v_brief,'')),

    -- DYNAMIC: the live snapshot every run.
    jsonb_build_object('rid','live-state','module','live_state',
      'title','QuotesDone — Live Company State (current)',
      'kw', to_jsonb(array['live','current','right now','revenue','last month revenue','how much revenue','customers','suppliers','open tasks','kpi','last social post','last blog','latest post','state','status','how are we doing']),
      'content',
        'LIVE STATE as of ' || to_char(now(),'DD Mon YYYY HH24:MI') || ' UTC (this refreshes; if a figure is 0 the company '
        'is pre-launch, not broken):' || E'\n' ||
        '  Revenue (last 30 days): ' || coalesce(v_snap->>'revenue_30d_aed','0') || ' AED' || E'\n' ||
        '  Customers: ' || coalesce(v_snap->>'customers','0') || ' (with an inquiry: ' || coalesce(v_snap->>'customers_with_inquiry','0') || ')' || E'\n' ||
        '  Approved suppliers: ' || coalesce(v_snap->>'approved_suppliers','0') || ' · Sendable supplier pool: ' || coalesce(v_snap->>'sendable_pool','0') || E'\n' ||
        '  Employees (brain agents): ' || coalesce(v_snap->>'employees','90') || ' · Departments: ' || coalesce(v_snap->>'departments','10') || E'\n' ||
        '  KPIs tracked: ' || coalesce(v_snap->>'kpis','0') || ' (open gaps: ' || coalesce(v_snap->>'kpi_gaps_open','0') || ')' || E'\n' ||
        '  Open tasks: ' || coalesce(v_snap->>'open_tasks','0') || ' · Items needing the founder: ' || coalesce(v_snap->>'needs_founder','0') || E'\n' ||
        '  AI spend (last 30 days): ' || coalesce(v_snap->>'ai_cost_30d_aed','0') || ' AED' || E'\n' ||
        '  Last social post: ' || coalesce(nullif(v_social,''),'(none yet)') || case when v_social_at is not null then ' [' || v_social_at || ']' else '' end || E'\n' ||
        '  Last blog post: ' || coalesce(nullif(v_blog,''),'(none yet)') || case when v_blog_at is not null then ' [' || v_blog_at || ']' else '' end),

    jsonb_build_object('rid','stage','module','company_stage',
      'title','QuotesDone — What Stage the Company Is At',
      'kw', to_jsonb(array['stage','pre-launch','have we launched','are we live','do we have customers','how many customers','are we operating','company status','how far along','launched yet','traction','are we making money']),
      'content',
        'COMPANY STAGE — READ THIS BEFORE ANSWERING ANYTHING ABOUT TRACTION. QuotesDone is PRE-LAUNCH. The '
        'platform and the AI organization are built and being readied; there are ' || coalesce(v_snap->>'customers','0') ||
        ' real customers and AED ' || coalesce(v_snap->>'revenue_30d_aed','0') || ' revenue so far. What is already in place: '
        '10 departments and ' || coalesce(v_snap->>'employees','90') || ' AI agents, 30 workflows, 86 supplier categories, '
        'the knowledge base and ' || coalesce(v_snap->>'approved_suppliers','1') || ' approved supplier(s). What is still pending before real '
        'operation: the marketplace go-live, real customer inquiries arriving, and funded AI inference so the agents can reason. '
        'NEVER claim customers, revenue, or results the numbers above do not show — we are building toward AED 1,000,000 by 31 Aug 2027, not there yet.'),

    -- 6 SEP 2026 (added at the END: sibling files restate this function; keep this the last element): the
    -- refund ladder, from pricing_config + decision_policy, the founder's ruling verbatim. Never re-ask him.
    jsonb_build_object('rid','refunds','module','refunds',
      'title','QuotesDone — The Refund Ladder (live): 5 working days, chase at 3, founder''s final call at 5',
      'kw', to_jsonb(array['refund','refund ladder','refund policy','refund window','non-response','supplier not responding','not responding','no response',
        'chase','chase the supplier','final call','founder final call','working days','5 working days','five working days','3 working days',
        'bank','7-14 working days','how long does a refund take','admin fee','administrative fee','250','9%','interest','9% per annum',
        'who chases','who owns refunds','refund amount','how much is refunded','supplier charge','non-response charge','fn_refund_amount_aed','fn_refund_state','refund_ladder_sweep']),
      'content',
        'THE REFUND LADDER (founder ruling 6 Sep 2026, final; read live from pricing_config and decision_policy):' || E'\n' ||
        '  Day 0: the customer pays the reveal fee (' || round(v_fee*100,2) || '% of the quotation, no cap). The clock starts at PAYMENT; nothing the customer does or does not do moves it.' || E'\n' ||
        '  Working day ' || coalesce(v_chase_wd::text,'3') || ' with no supplier response: the Customer Success Director (runtime agent followup, customer_experience) chases the supplier by email, customer copied, WhatsApp when opted in, and holds an org_task until the supplier responds. Deterministic: fn_refund_ladder_sweep, cron refund_ladder_sweep_hourly.' || E'\n' ||
        '  Working day ' || coalesce(v_refund_wd::text,'5') || ' with still no response: the refund request is filed through fn_refund_request (the ONE door) and the founder is notified for his FINAL CALL (founder_mail_policy kind refund_final_call - one of only two refund signals that reach his inbox; the other is the approval itself).' || E'\n' ||
        '  No response to his call: he approves the refund in the OS (fn_refund_decide; every refund, any amount, is his decision, never automatic).' || E'\n' ||
        '  The customer is refunded the FULL fee paid - no deduction - and told that banks take ' || coalesce(v_bank_min::text,'7') || '-' || coalesce(v_bank_max::text,'14') || ' working days to show it.' || E'\n' ||
        '  The supplier whose silence caused it owes: the exact amount refunded (the 3%) + from Supplier Agreement v14 the payment processor fee QuotesDone could not recover + AED ' || v_admin::text || ' administrative fee + ' || v_pct::text || '% per annum simple interest (the rate agreed in v14; 9% under v13 or earlier), and is blocked from matching until settled. One function states the arithmetic: fn_refund_amount_aed(paid, paid_at, refund_at).' || E'\n' ||
        '  Working days are Monday to Friday, UAE public holidays excluded (fn_is_working_day). fn_refund_state(transaction) says where any case stands.' || E'\n' ||
        'WHO OWNS WHAT: chase = Customer Success Director (existing owner of supplier follow-up); final call + approval = the founder; execution on Stripe = Payments & Billing Manager; reconciliation = Financial Controller; recovery from the supplier = Accounts Receivable via collections_legal. No new employee was created for this.' || E'\n' ||
        'THE FOUNDER''S WORDS (verbatim, 6 Sep 2026 - never ask him about refunds again): "' || coalesce(v_founder_words, '(decision_policy.refund_policy_founder_decision_2026_09_06)') || '"'),

    -- 6 SEP 2026: the brand kit, from company_brand (the founder attached the kit that day: "make sure it's
    -- in company knowledge so you never ask me about it again"). Appended LAST on purpose: sibling files add
    -- qd-company:decisions and qd-company:refunds to this same array; they merge ahead of this record.
    jsonb_build_object('rid','brand','module','brand',
      'title','QuotesDone — Brand Kit: colours, typography, logo rules, voice and asset files',
      'kw', to_jsonb(array['brand','brand kit','brand guide','brand guidelines','logo','logo files','lockup','wordmark','mark','favicon','app icon',
        'colour','color','colours','colors','hex','palette','teal','gold','navy','ink','brand colours','what are our colours','primary colour','primary color',
        'font','typeface','typography','poppins','plus jakarta sans','tajawal','arabic font','type scale',
        'tagline','clear space','minimum size','logo usage','social image size','cover size','avatar','banner','post template',
        'tone of voice','voice','wording','bilingual','arabic','rtl','email template','pdf header','letterhead','business card','trademark','ip filing','vector','svg',
        'where is the logo','which logo file','brand assets','brand bucket','contrast','wcag','accessibility','button colour','link colour']),
      'content',
        'THE BRAND KIT IS ON FILE (the founder attached QuotesDone_Brand_Kit.zip on 6 Sep 2026 and ruled it company knowledge: never ask him for a logo, a colour or a font again). '
        || 'Files: ' || (select count(*) from public.brand_assets where bucket = 'brand')::text
        || ' assets in the public brand bucket under kit/ (public.brand_assets holds kind, platform, path, size and usage per file; WHERE_TO_USE.txt is the kit index). '
        || 'The full guide is docs/brand/QUOTESDONE_BRAND_GUIDE.md and the "QuotesDone Brand Guide" PDF in the OS Reports panel.' || E'\n'
        || coalesce((select string_agg(g.block, E'\n' order by g.grp_sort)
                       from (select cb."group", min(cb.sort) as grp_sort,
                                    upper(cb."group") || ':' || E'\n'
                                    || string_agg('  - ' || cb.key || ': ' || cb.value || coalesce(' — ' || cb.note, ''), E'\n' order by cb.sort) as block
                               from public.company_brand cb group by cb."group") g),
                    '  (company_brand is empty)')),

    -- 6 SEP 2026: the founder's decisions, verbatim in substance, from company_policy_decision. Added at the
    -- END on purpose: the renderer is code-driven and sibling packets (the refund ladder and the brand kit
    -- above, messaging) add their records before it. Whichever packet lands last keeps its record last;
    -- order carries no meaning here.
    jsonb_build_object('rid','decisions','module','founder_decisions',
      'title','QuotesDone — The Founder''s Standing Decisions (never ask about these again)',
      'kw', to_jsonb(array['founder decision','founder decisions','standing decision','ruling','policy decision','what did the founder decide','never ask again',
        'corporate tax','auditor','meta token','daily budget cap','30 aed','cost per lead target','cpl target','openrouter','open router credit','recharge','receipts','expenses email',
        'discount','no discounts','reveal cap','category open','10 suppliers','finance budget','budget limit','profitable','supplier registration fee','first 1000','1000 aed per year','no deadline','no date']),
      'content',
        'THE FOUNDER''S STANDING DECISIONS. Each line is final. None is a question; none is asked again; every table, document and agent head is kept in sync with them.' || E'\n' ||
        coalesce(v_decisions, '(none recorded)'))
,

    -- 6 SEP 2026 (appended at the END, code-driven): the two supplier loops the founder decided on that day.
    jsonb_build_object('rid','supplier-loops','module','supplier_loops',
      'title','QuotesDone — Supplier acquisition loop and weekly sanctions screening (owners, cadence, switch)',
      'kw', to_jsonb(array['supplier acquisition','invite campaign','supplier invites','follow-up','follow up','300 suppliers','suppliers per month',
        'registered suppliers target','lead intake','inbound email','new leads','lead sourcing','supplier_outreach_golive','outreach switch','is outreach on',
        'sanctions','sanctions screening','UN consolidated list','UAE terrorist list','local terrorist list','screening hit','banned supplier',
        'who owns supplier acquisition','who screens suppliers','compliance officer','business development manager','weekly screening','when do we screen']),
      'content',
        'SUPPLIER ACQUISITION LOOP (founder decision 6 Sep 2026). Owner: ' || coalesce(v_supply_owner, 'Sales Engineer') || ' (org_agents.sales_engineer; there are no departments) — '
        'no new employee was created; this is that role''s existing responsibility. Target: at least ' || v_reg_target || ' suppliers registered every month '
        '(company_goals.suppliers_registered_monthly; the BD scorecard KPI "Suppliers registered per month", measured from leads registration timestamps). '
        'This month so far: ' || coalesce(v_reg_month, '0 (not measured yet)') || '. Sources: the leads we already hold (' || v_invited || ' invited to date, '
        || v_registered || ' registered), inbound e-mail (senders on business domains become leads; supplier-intent replies are classified by keyword — no model — into '
        'register / question / document / decline / bounce and become ONE reply task on the sales engineer; ' || v_intake || ' classified so far), and the staged directory '
        'promoted daily by supplier_discovery_daily. No scraping (Apify paused) and no paid inference anywhere in the loop. Cadence: supplier_invites_daily 09:00 UTC '
        '(the invitation batch, capped, deliverability-guarded) and supplier_outreach_daily 05:30 UTC (follow-ups at +3 and +7 WORKING days after a delivered '
        'invitation, at most two, never to a lead that replied, registered, bounced or is suppressed; ' || v_followups || ' follow-ups sent to date; inbox intake; lead sourcing). '
        'THE SWITCH: app_secrets.supplier_outreach_golive is ' || case when v_golive then 'TRUE — outreach is LIVE.' else 'FALSE — every part of the loop is HELD and records "held" on each run; the founder flips it when the app is ready ("none of this will run till the app is perfect").' end
        || ' Both it and invite_enabled must be true before an invitation is written.' || E'\n\n' ||
        'WEEKLY SANCTIONS SCREENING (founder decision 6 Sep 2026). Owner: ' || coalesce(v_co, 'Chief Executive (AI)') || ' (org_agents.ceo — a confirmed hit removes a supplier and every approval is the CEO''s; '
        'the sales engineer holds the outreach while the decision is open). Cadence: sanctions_screen_weekly, Mondays 03:00 UTC (07:00 Dubai). '
        'Sources: the UN Security Council consolidated list (XML; last: ' || coalesce(v_last_un, 'not fetched yet') || ') and the UAE Local Terrorist List from the Executive Office '
        'for Control & Non-Proliferation (published as PDF and legacy Excel only — the Excel is parsed, the PDF is not; last: ' || coalesce(v_last_uae, 'not fetched yet') || '). '
        'Every registered supplier is screened on legal name, licence name, owner, contact and e-mail domain by normalised exact match and conservative token overlap. '
        'A hit opens ONE decision task on the ceo with the evidence and ONE hold on the sales engineer — the team is updated, never the founder — and NOBODY is removed automatically: '
        'the ceo decides (fn_supplier_screening_decide), and a CONFIRMED hit moves the supplier through the existing status path (banned, matching blocked, approval withdrawn). '
        'Open hits right now: ' || v_hits_open || '. Records: screening_run (source, entries, fetched_at, sha256), screening_entry, supplier_screening_hit.'),

    -- 6 SEP 2026 (LAST on purpose — every sibling file of the day restates this function and the last record
    -- is the one a later restatement can carry forward without touching the others): the WhatsApp templates
    -- and their Meta approval status, live from messaging_template (the founder said "fix the template
    -- yourself"; the status is company knowledge, never his question).
    jsonb_build_object('rid','messaging-templates','module','messaging_templates',
      'title','QuotesDone — WhatsApp templates and their Meta approval status (live)',
      'kw', to_jsonb(array['whatsapp template','whatsapp templates','template approval','meta approval','twilio','content sid','contentsid',
        'founder alert whatsapp','whatsapp alert','whatsapp alerts to the founder','is the whatsapp template approved','pending template',
        'template pending','template rejected','63016','utility template','messaging template','messaging_template','wa_template_sids',
        'can we send whatsapp','why did the whatsapp not arrive','send_whatsapp','wa_template_setup','business-initiated message','24-hour session']),
      'content',
        'WHATSAPP TEMPLATES (Twilio Content API, approved by Meta; live from messaging_template):' || E'\n' || v_tmpl || E'\n' ||
        'THE RULES. A business-initiated WhatsApp (an alert to the founder, a job / quote / reveal / document notice to a supplier or '
        'customer) is deliverable ONLY through a Meta-APPROVED template sent by ContentSid; a freeform body is delivered only inside the '
        '24-hour session the recipient opened by messaging us first (Twilio error 63016 otherwise). A template still pending approval is a '
        'HELD message, never a failed one: send_whatsapp keeps supplier and customer rows queued until the template lands, marks founder-alert '
        'rows skipped with the reason (the email already carried the alert), and refuses a direct send with the reason instead of erroring. '
        'Templates are created and submitted by the wa_template_setup function (category UTILITY, language en/ar, the body opens AND closes '
        'with literal text because Meta rejects a variable at the start or end); the sender refreshes each pending status from Twilio at most '
        'every ten minutes and only ever sends with a status of APPROVED. The sender number is registered with Meta as "QuotesDone" '
        '(quality rating and messaging tier are read from Twilio, not assumed). Nobody asks the founder about WhatsApp templates: the '
        'status above is the answer, and a pending line means Meta has not answered yet.')
  );

  for r in select * from jsonb_array_elements(v_records) loop
    v_rid := 'qd-company:' || (r->>'rid');
    insert into public.ops_knowledge(
      record_id, scope_type, scope_key, layer, module, record_type, title, content,
      structured_data, source_ids, implementation_status, validation_status, authority_tier,
      risk_level, version, keywords, dependencies, escalation_rule, jurisdiction, source_freshness,
      confidentiality, runtime_eligible, deterministic, supersession_state, embedding_status,
      effective_date)
    values (
      v_rid, 'company', 'company_core', 'company_core', r->>'module', 'md', r->>'title',
      -- fold the keyword vocabulary into the content so the generated tsv (title+content) indexes the
      -- phrasings agents actually ask in, not only the prose. This is what makes deep questions match.
      (r->>'content') || E'\n\nYou can answer questions about: ' ||
        array_to_string(array(select jsonb_array_elements_text(r->'kw')), ', ') || '.',
      '{}'::jsonb, array['fn_company_self_knowledge_sync'], 'active', 'validated', 'autonomous',
      'low', '1', array(select jsonb_array_elements_text(r->'kw')), '{}'::text[], '{}'::jsonb, 'UAE', 'current',
      'internal', true, true, 'current', 'pending', current_date)
    on conflict (record_id) do update set
      module = excluded.module, title = excluded.title, content = excluded.content,
      keywords = excluded.keywords, effective_date = excluded.effective_date,
      supersession_state = 'current', embedding_status = 'pending';
    v_n := v_n + 1;
  end loop;

  -- The org directory (everyone knows everyone: role, line manager, KPI, live rating) and the
  -- published content (FAQ, social, blog, website) are recomposed in the same refresh.
  perform public.fn_company_org_directory_sync();

  return jsonb_build_object('ok', true, 'records', v_n, 'ran_at', now(),
    'revenue_30d_aed', v_snap->>'revenue_30d_aed', 'reveal_fee_pct', round(v_fee*100,2),
    'employees', v_snap->>'employees');
end $function$;

create or replace function public.fn_refund_amount_aed(p_paid_aed numeric, p_paid_at timestamp with time zone, p_refund_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_paid numeric; v_admin numeric; v_pct numeric; v_days integer; v_interest numeric;
  v_min integer; v_max integer;
begin
  -- The customer's refund is the fee actually paid, in full: the published Refund Policy promises no
  -- administrative deduction and fn_refund_amount_is_the_fee_paid enforces it on the refunds row.
  v_paid  := round(coalesce(p_paid_aed, 0), 2);
  -- 24 SEP 2026 (ceo): REFERENCE figures for the knowledge texts only; the charge a supplier actually owes is
  -- fn_accountant_nonresponse_charge, by the Supplier Agreement version it had signed (v14: + processor fee, agreed 12%).
  -- The administrative fee and the annual rate (decision_policy) are what the SUPPLIER whose
  -- silence caused the refund owes on top of the fee: founder decision 6 Sep 2026, verbatim in
  -- decision_policy.refund_policy_founder_decision_2026_09_06.
  v_admin := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_admin_fee_aed'), 250);
  v_pct   := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_late_fee_annual_pct'), 9);
  select bank_settlement_working_days_min, bank_settlement_working_days_max
    into v_min, v_max from public.pricing_config order by id limit 1;
  -- simple interest, pro-rated by CALENDAR days (Dubai dates) between the two instants
  v_days := greatest(0, (coalesce(p_refund_at, now()) at time zone 'Asia/Dubai')::date
                      - (coalesce(p_paid_at, coalesce(p_refund_at, now())) at time zone 'Asia/Dubai')::date);
  v_interest := round(v_paid * v_pct / 100.0 * v_days / 365.0, 2);
  return jsonb_build_object(
    'paid_aed', v_paid,
    'customer_refund_aed', v_paid,
    'admin_fee_aed', v_admin,
    'interest_pct_pa', v_pct,
    'interest_days', v_days,
    'interest_aed', v_interest,
    'supplier_charge_aed', round(v_paid + v_admin + v_interest, 2),
    'bank_settlement_working_days', coalesce(v_min, 7)::text || '-' || coalesce(v_max, 14)::text,
    'basis', 'customer: the reveal fee paid, refunded in full, no deduction; supplier (reference, current version; the exact charge is fn_accountant_nonresponse_charge): that fee + from v14 the processor fee not recovered + AED '
             || v_admin::text || ' administrative fee + ' || v_pct::text
             || '% p.a. simple interest for ' || v_days::text || ' calendar day(s)');
end $function$;

create or replace function public.fn_company_facts_sync()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c record; pct text; capnote text; txt text; regline text;
begin
  select * into c from pricing_config where id=1; if c is null then return; end if;

  pct := trim(to_char(coalesce(c.standard_reveal_rate,0)*100,'FM990.##'))||'%';
  capnote := 'NO cap, NO discount, NO promotional rate, NO coupon and NO free reveal - the founder''s decision of 6 Sep 2026, enforced by a pricing_config constraint';

  -- The registration sentence is DERIVED. 6 Sep 2026 (founder): "dont use a deadline with dates" -
  -- a NULL start date is the rule itself, never a gap to ask him about.
  if c.supplier_charging_starts is null then
    regline := 'Supplier registration is FREE for the first ' || c.supplier_free_count || ' verified registrations, and those '
            || c.supplier_free_count || ' suppliers are exempt PERMANENTLY. Every registration after them pays a '
            || coalesce(c.supplier_reg_period,'yearly') || ' subscription of ' || coalesce(c.supplier_reg_currency,'AED') || ' '
            || trim(to_char(c.supplier_reg_fee,'FM999,999,990.##')) || '. There is NO calendar start date and there will not be one: '
            || 'charging begins with registration number ' || (c.supplier_free_count + 1) || ', whenever that happens. '
            || 'Never state a date, never ask the founder for one. ';
  else
    regline := 'Supplier registration is FREE for EVERY supplier until '
            || to_char(c.supplier_charging_starts - 1, 'FMDD FMMonth YYYY') || '. '
            || 'From ' || to_char(c.supplier_charging_starts, 'FMDD FMMonth YYYY') || ' a '
            || coalesce(c.supplier_reg_period,'yearly') || ' subscription of '
            || coalesce(c.supplier_reg_currency,'AED') || ' '
            || trim(to_char(c.supplier_reg_fee,'FM999,999,990.##')) || ' applies, and it is NOT charged '
            || 'before that date. The first ' || c.supplier_free_count || ' businesses to register are '
            || 'exempt PERMANENTLY and never pay it - that exemption does not expire. ';
  end if;

  txt := 'PRICING & FEES - LIVE, AUTO-SYNCED FROM pricing_config (authoritative; OVERRIDES any pricing figure stated elsewhere). '
    ||'Customer REVEAL FEE: '||pct||' of the accepted quotation value ('||capnote||'), paid by the customer to unlock their chosen supplier. '
    ||'On top of it the customer pays the CARD PROCESSING FEE (the Stripe fee, grossed up so QuotesDone receives the full '||pct||'); both are shown in full before payment. '
    ||'QuotesDone is NOT VAT registered: NO VAT is charged on the reveal fee - never say the fee is VAT-inclusive or that VAT is added. '
    ||'Suppliers pay NO commission on won jobs. '
    ||regline
    ||'CATEGORY OPENING: a category is OPEN once it has '||coalesce(c.category_open_min_suppliers,10)||' verified registered suppliers (public.v_category_open); matching an RFQ still needs at least one confirmed supplier. '
    ||'Non-response window: '||c.refund_window_working_days||' working days from the customer''s payment - if a revealed supplier stays silent through the chase and the CEO''s final call, EVERYTHING the customer paid (the reveal fee) is refunded; the supplier is charged under the Supplier Agreement version it had accepted at the reveal (fn_accountant_nonresponse_charge): under v14 the exact amount refunded + the payment processor fee QuotesDone could not recover + an AED 500 administrative fee + simple interest at 12% a year (the agreed rate) from the due date + if unpaid the official recovery fees; under v13 the refund + AED 500 + 9%; under v12 or earlier the refund + AED 250 + 9%. It is blocked from matching until paid. '
    ||'There is NO 2% fee and NO supplier commission - never quote those. (Auto-updated '||to_char(now(),'YYYY-MM-DD HH24:MI')||' UTC.)';

  update agent_knowledge set content=txt, priority=100, updated_at=now()
    where agent_key='_global' and topic='Pricing & fees (LIVE — auto-synced)';
  if not found then
    insert into agent_knowledge(agent_key,topic,content,priority,updated_at)
      values ('_global','Pricing & fees (LIVE — auto-synced)',txt,100,now());
  end if;
end $function$;

-- PROBE (no write): each body carries the v14 rule; a transaction that cannot exist is never charged. Verdict row.
select case
  when pg_get_functiondef('public.fn_accountant_nonresponse_charge(uuid, date)'::regprocedure) !~ 'supplier_nonresponse_interest_apr_from_v14' then 'PROBE FAILED: the charge does not read the v14 rate'
  when pg_get_functiondef('public.fn_accountant_nonresponse_charge(uuid, date)'::regprocedure) !~ 'stripe_fee_fils' then 'PROBE FAILED: the charge does not read the processor fee'
  when pg_get_functiondef('public.fn_accountant_raise_nonresponse_charge(uuid, boolean)'::regprocedure) !~ 'charge_aed' then 'PROBE FAILED: the due does not record (a)+(b)'
  when pg_get_functiondef('public.fn_ceo_refund_checklist(uuid, text, boolean)'::regprocedure) !~ 'du.amount_due = \(v_charge->>''charge_aed''\)' then 'PROBE FAILED: the CEO checklist still compares the refund alone'
  when pg_get_functiondef('public.fn_accountant_acts_on_handoff(bigint)'::regprocedure) !~ 'du.amount_due = \(v->>''charge_aed''\)' then 'PROBE FAILED: the accountant still compares the refund alone'
  when (select (value #>> '{}')::numeric from public.decision_policy where key = 'supplier_nonresponse_interest_apr_from_v14') is distinct from 0.12 then 'PROBE FAILED: the v14 rate is not 12%'
  when (public.fn_accountant_nonresponse_charge('00000000-0000-0000-0000-000000000000'::uuid, null)->>'ok')::boolean then 'PROBE FAILED: a transaction that does not exist was charged'
  else 'PROBE OK' end as verdict;
