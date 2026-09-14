-- A REFUND RETURNS EVERYTHING THE CUSTOMER PAID, AND THE SUPPLIER REPAYS EXACTLY THAT.
--
-- Assigned: accountant. Carried out for the ceo.
--
-- The founder, 14 Sep 2026:
--   the reveal charge is 3% of the chosen quote plus Stripe's processing fee, grossed up so QuotesDone
--   nets 3%; there is no VAT. When a reveal is refunded the customer gets back the full amount they
--   paid, the 3% and the processing part together, and QuotesDone absorbs Stripe's fee.
--   "the exact amount that was refunded with the processing fees from stripe will be charged to the
--    supplier along with 250 AED admin fees and 9% yearly interest as per UAE law."
--
-- MEASURED BEFORE WRITING (14 Sep 2026, production):
--   * transactions.total_charged, processing_fee and stripe_fee_fils exist (the_accountant_files_the_reveal_
--     invoice_and_the_sales_engineer_tells_the_customer.sql) and stripe_webhook writes them. Nothing READ them:
--   * a00_refund_amount_is_the_fee_paid required refunds.amount_fils = reveal_fee, so a refund of the
--     full charge would have been REFUSED by the database. fn_refund_open_from_customer,
--     fn_refund_ladder_sweep and fn_support_investigate_refund all computed the refund from reveal_fee.
--   * qd_on_refund_resolved -- the routine that raised the supplier's charge -- is bound to NO
--     trigger (pg_trigger, 0 rows). refunds_api's own comment says "'refunded' fires the DB trigger:
--     creates the 3% non-response due"; nothing fires. A refunded customer produced no supplier charge.
--   * fn_supplier_nonresponse_penalty computed the charge as 3% of the JOB VALUE with interest from the
--     refund date. It has no caller (pg_proc prosrc scan, repository scan) and contradicts the rule above.
--   * fn_gl_sync_business posted a refund only for refund_status 'refunded'/'refund_approved'; the
--     refunds-table path writes 'succeeded', so a refund settled through Stripe never reached the ledger.
--
-- WHAT THIS FILE MAKES TRUE
--   * a refund's amount is transactions.total_charged (everything the customer paid), still cited
--     against the exact Stripe payment_ref, still strict.
--   * ONE routine computes the supplier's charge, from the refund record itself, never recomputed from
--     a rate: fn_accountant_nonresponse_charge. Base = the amount actually refunded, capped at the
--     amount the CEO approved (an over-refund is the company's loss, never the supplier's); + the admin
--     fee from pricing_config; + simple interest on (base + admin) at min(pricing_config APR, the lawful
--     maximum in decision_policy) from the charge's due date. Interest is recomputed absolutely, so
--     running the accrual twice changes nothing.
--   * When a refund settles, the accountant raises that charge (once), hands the supplier's message and
--     the customer's message to the sales engineer, and the CEO re-verifies the whole thing.
--   * The absorbed Stripe fee is a cost in the books (6100): stripe_fee_fils when Stripe reported it,
--     else processing_fee, else the gl_settings estimate the ledger already used.
--   * A circuit breaker (decision_policy.refunds_and_supplier_charges_paused) that every refund and
--     charge path reads. Only the CEO's mismatch playbook sets it.
--
--   node scripts/apply_sql.mjs scripts/sql/a_refund_returns_everything_the_customer_paid.sql --apply --ddl

insert into public.founder_instruction (said_at, instruction, subject, status, evidence)
select '2026-09-14T00:00:00Z', x.i, x.s, 'done', 'scripts/sql/a_refund_returns_everything_the_customer_paid.sql'
  from (values
    ('the exact amount that was refunded with the processing fees from stripe will be charged to the supplier along with 250 AED admin fees and 9% yearly interest as per UAE law.', 'supplier non-response charge'),
    ('when a reveal is refunded, the customer gets back the full amount they paid: the 3% and the processing part together. QuotesDone absorbs Stripe''s fee.', 'refund returns total charged')) x(i, s)
 where not exists (select 1 from public.founder_instruction f where f.instruction = x.i);

-- ── 1. WHAT STRIPE TOOK ──────────────────────────────────────────────────────────────────────────
-- transactions.total_charged (everything the customer paid), processing_fee (the card line on top of the
-- 3%) and stripe_fee_fils (what Stripe actually kept) are the_accountant_files_the_reveal_invoice_and_the_
-- sales_engineer_tells_the_customer.sql's columns, written by stripe_webhook. This file only reads them.

-- ── 2. THE TERMS THAT ARE NOT IN pricing_config ──────────────────────────────────────────────────
insert into public.decision_policy (key, value, description) values
  ('supplier_charge_due_days', '7'::jsonb, 'Days after the customer''s refund settles that the supplier''s non-response charge falls due; interest runs from that date. The value the estate''s charges already used (supplier_dues.due_date = raised + 7).'),
  ('supplier_charge_max_lawful_apr', '0.09'::jsonb, 'The ceiling on the supplier charge''s simple annual interest. The founder, 14 Sep 2026: "9% yearly interest as per UAE law". fn_accountant_nonresponse_charge applies min(pricing_config APR, this).'),
  ('refunds_and_supplier_charges_paused', 'false'::jsonb, 'The CEO''s circuit breaker. true while a post-payment mismatch is open: no automated refund is executed and no supplier charge is raised. Set and lifted only by fn_ceo_refund_mismatch_playbook / fn_ceo_incident_advance.'),
  ('refund_final_call_watch_working_days', '1'::jsonb, 'Working days customer_support watches for a reply after the day-5 final call before it may confirm no response.')
on conflict (key) do nothing;

create or replace function public.fn_refunds_paused()
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce((select (d.value #>> '{}')::boolean from public.decision_policy d
                    where d.key = 'refunds_and_supplier_charges_paused'), false);
$fn$;
revoke execute on function public.fn_refunds_paused() from public, anon, authenticated;

-- ── 3. THE ONE ROUTINE THAT COMPUTES THE SUPPLIER'S CHARGE ───────────────────────────────────────
create or replace function public.fn_accountant_nonresponse_charge(p_transaction_id uuid, p_as_of date default null)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  t public.transactions; c public.pricing_config; v_n int; v_sum bigint;
  v_refunded numeric; v_approved numeric; v_base numeric; v_settled timestamptz; v_src text;
  v_cap numeric; v_apr numeric; v_due_days int; v_due date; v_as_of date; v_days int; v_int numeric;
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
  v_int      := round((v_base + c.supplier_nonresponse_admin_fee_aed) * v_apr * v_days / 365.0, 2);

  return jsonb_build_object(
    'ok', true, 'transaction_id', t.id, 'supplier_id', t.supplier_id,
    'refunded_aed', v_base, 'actually_refunded_aed', v_refunded, 'approved_aed', v_approved, 'refund_source', v_src,
    'admin_fee_aed', c.supplier_nonresponse_admin_fee_aed,
    'interest_apr', v_apr, 'interest_apr_configured', c.supplier_nonresponse_interest_apr, 'interest_apr_lawful_max', v_cap,
    'due_date', v_due, 'as_of', v_as_of, 'interest_days', v_days, 'interest_aed', v_int,
    'total_aed', round(v_base + c.supplier_nonresponse_admin_fee_aed + v_int, 2),
    'basis', 'base = the amount refunded to the customer, read from the refund record and capped at the amount the CEO approved; '
          || '+ the administration fee from pricing_config; + simple interest on (base + admin fee) at the lower of pricing_config''s APR and '
          || 'the lawful maximum, from the due date (' || v_due_days || ' days after the refund settled) to the as-of date. Nothing is typed.');
end $fn$;
revoke execute on function public.fn_accountant_nonresponse_charge(uuid, date) from public, anon, authenticated;

-- Absolute, so a second run the same day changes nothing.
create or replace function public.fn_supplier_dues_accrue_interest(p_as_of date default null)
returns int language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare x record; v jsonb; n int := 0;
begin
  for x in select id, transaction_id from public.supplier_dues
            where paid_at is null and transaction_id is not null
              and coalesce(status, '') not in ('paid', 'settled', 'waived', 'cancelled') loop
    v := public.fn_accountant_nonresponse_charge(x.transaction_id, p_as_of);
    continue when not coalesce((v->>'ok')::boolean, false);
    update public.supplier_dues
       set interest_amount = (v->>'interest_aed')::numeric, total_claim = amount_due + coalesce(admin_fee, 0) + (v->>'interest_aed')::numeric
     where id = x.id
       and (interest_amount is distinct from (v->>'interest_aed')::numeric
            or total_claim is distinct from amount_due + coalesce(admin_fee, 0) + (v->>'interest_aed')::numeric);
    if found then n := n + 1; end if;
  end loop;
  return n;
end $fn$;
revoke execute on function public.fn_supplier_dues_accrue_interest(date) from public, anon, authenticated;

-- Raises the charge ONCE per transaction (supplier_dues allows one row per transaction; the CEO's
-- playbook corrects a wrong one in place), blocks matching, and hands the supplier's message to the
-- sales engineer.
create or replace function public.fn_accountant_raise_nonresponse_charge(p_transaction_id uuid, p_notify boolean default true)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
            (v->>'refunded_aed')::numeric, (v->>'admin_fee_aed')::numeric, (v->>'interest_aed')::numeric, (v->>'total_aed')::numeric, 'AED',
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
end $fn$;
revoke execute on function public.fn_accountant_raise_nonresponse_charge(uuid, boolean) from public, anon, authenticated;

-- ── 4. WHEN A REFUND SETTLES, OR IS DECLINED, OR FAILS ───────────────────────────────────────────
create or replace function public.fn_accountant_refund_settled(p_transaction_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare t public.transactions; v_reason text; v_charge jsonb; v_verify jsonb;
begin
  select * into t from public.transactions where id = p_transaction_id;
  select coalesce((select r.reason_code from public.refunds r where r.transaction_id = t.id order by r.id desc limit 1),
                  t.refund_reason, 'supplier_unresponsive') into v_reason;
  if v_reason = 'supplier_unresponsive' then
    v_charge := public.fn_accountant_raise_nonresponse_charge(t.id, true);
  end if;
  perform public.fn_seat_handoff('accountant', 'sales_engineer', 'refund.paid', 'transactions', t.id::text,
    jsonb_build_object('transaction_id', t.id, 'customer_id', t.customer_id, 'supplier_id', t.supplier_id,
                       'inquiry_id', t.inquiry_id, 'quote_id', t.quote_id, 'revealed_at', t.revealed_at,
                       'amount_aed', round(t.refund_amount_aed, 2)));
  v_verify := public.fn_ceo_refund_verify(t.id);
  return jsonb_build_object('charge', v_charge, 'verify', v_verify);
end $fn$;
revoke execute on function public.fn_accountant_refund_settled(uuid) from public, anon, authenticated;

create or replace function public.fn_transaction_refund_outcome_follows_through()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if NEW.refund_status in ('succeeded', 'refunded') and NEW.refund_amount_aed is not null
     and (OLD.refund_status is distinct from NEW.refund_status or OLD.refund_amount_aed is distinct from NEW.refund_amount_aed) then
    begin
      perform public.fn_accountant_refund_settled(NEW.id);
    exception when others then
      insert into public.ceo_task (title, detail)
      values (left('Refund on reveal ' || left(NEW.id::text, 8) || ' settled but its follow-through failed', 200),
              'fn_accountant_refund_settled raised: ' || sqlerrm || '. The refund itself is recorded; the supplier charge, the customer''s message or the re-verification did not complete.');
    end;
  elsif NEW.refund_status = 'failed' and OLD.refund_status is distinct from 'failed' then
    perform public.fn_ceo_refund_verify(NEW.id);
  elsif NEW.refund_status = 'rejected' and OLD.refund_status is distinct from 'rejected' then
    perform public.fn_seat_handoff('accountant', 'sales_engineer', 'refund.declined', 'transactions', NEW.id::text,
      jsonb_build_object('transaction_id', NEW.id, 'customer_id', NEW.customer_id, 'inquiry_id', NEW.inquiry_id,
                         'quote_id', NEW.quote_id, 'note', NEW.refund_note));
  end if;
  return NEW;
end $fn$;
revoke execute on function public.fn_transaction_refund_outcome_follows_through() from public, anon, authenticated;
drop trigger if exists z40_refund_outcome_follows_through on public.transactions;
create trigger z40_refund_outcome_follows_through
  after update of refund_status, refund_amount_aed on public.transactions
  for each row execute function public.fn_transaction_refund_outcome_follows_through();

-- The accountant's side of a CEO rejection: the one pre-approval check it owns is the amount.
create or replace function public.fn_accountant_remediates(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare d jsonb; v_fils bigint; v_n int;
begin
  select detail into d from public.agent_actions where id = p_id;
  if d->'checks' ? 'amount_equals_total_charged' then
    update public.refunds r
       set amount_fils = round(coalesce(t.total_charged, t.reveal_fee) * 100)::bigint
      from public.transactions t
     where r.id = (d->>'refund_id')::bigint and t.id = r.transaction_id and r.status = 'requested'
    returning r.amount_fils into v_fils;
    get diagnostics v_n = row_count;
    return jsonb_build_object('fixed', v_n = 1, 'amount_fils', v_fils,
      'basis', 'refunds.amount_fils set to the payment''s total_charged; a00_refund_amount_is_the_fee_paid re-checked it against the Stripe reference on write');
  end if;
  return jsonb_build_object('waiting', 'no automatic remedy for ' || coalesce(d->>'checks', '?') || '; the accountant runtime or a person must act');
end $fn$;
revoke execute on function public.fn_accountant_remediates(bigint) from public, anon, authenticated;

-- ── 5. RETIRED: two routines that computed the charge the wrong way ─────────────────────────────
drop function if exists public.qd_on_refund_resolved();
drop function if exists public.fn_supplier_nonresponse_penalty(numeric, date, date);

-- ── 6. THE FOUR ROUTINES THAT READ THE REFUND FROM reveal_fee, now reading total_charged ──────────
-- Each is the live definition with only the amount changed (the edits are listed in the PR).
CREATE OR REPLACE FUNCTION public.fn_refund_amount_is_the_fee_paid()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t public.transactions%rowtype;
  v_expected bigint;
  -- A refund Stripe already issued is a fact to be recorded, not a request to be approved.
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

  if coalesce(t.total_charged, t.reveal_fee) is null or coalesce(t.total_charged, t.reveal_fee) <= 0 then
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

  -- ── THE STRIPE REFERENCE, ADDED 9 SEP 2026 ───────────────────────────────────────────────────
  -- The founder: "it's issued against that exact invoice reference... It has an ID." The reference
  -- Stripe gave us when the customer paid is transactions.payment_ref (stripe_webhook writes the
  -- payment_intent, falling back to the checkout session id). Until now stripe_payment_intent on a
  -- refund was a nullable text column nothing checked, so a refund could name transaction A and
  -- cite the payment of transaction B -- or name no payment at all -- and still move money.
  if coalesce(btrim(t.payment_ref), '') = '' then
    raise exception 'refunds: transaction % carries no Stripe payment reference, so there is no payment of record to reverse. (refund_payment_has_no_reference)',
      NEW.transaction_id using errcode = '23514',
            hint = 'transactions.payment_ref is written by stripe_webhook when the reveal fee settles. A transaction without one was never paid through Stripe, and money must not be returned against a payment nobody can point at.';
  end if;
  if coalesce(btrim(NEW.stripe_payment_intent), '') = '' then
    raise exception 'refunds: this refund names no Stripe payment. Transaction % was paid under reference %, and a refund is issued against that exact reference. (refund_names_no_stripe_reference)',
      NEW.transaction_id, t.payment_ref using errcode = '23514',
            hint = 'Set stripe_payment_intent to the payment_ref of the transaction being reversed. Founder ruling, 9 Sep 2026.';
  end if;
  if btrim(NEW.stripe_payment_intent) <> btrim(t.payment_ref) then
    raise exception 'refunds: this refund cites Stripe payment %, but transaction % was paid under %. A refund is issued against the exact reference of the payment it reverses, never another one. (refund_cites_the_wrong_stripe_payment)',
      NEW.stripe_payment_intent, NEW.transaction_id, t.payment_ref using errcode = '23514';
  end if;

  -- AND THE AMOUNT IS READ OFF THAT PAYMENT. Equality, not a ceiling: the reveal fee is refunded
  -- whole or not at all, so "cannot exceed what the payment took" is enforced by the stricter rule
  -- that it must EQUAL it. A platform refund with no amount is refused outright -- an unstated
  -- figure is not a smaller figure, it is an unbounded one.
  v_expected := round(coalesce(t.total_charged, t.reveal_fee) * 100)::bigint;
  if NEW.amount_fils is null then
    raise exception 'refunds: a platform refund must state its amount. Transaction % took % fils (AED %), and that is the only figure this refund may carry. (refund_states_no_amount)',
      NEW.transaction_id, v_expected, round(coalesce(t.total_charged, t.reveal_fee),2) using errcode = '23514';
  end if;
  if NEW.amount_fils <> v_expected then
    raise exception 'refunds: the amount must equal what the customer actually paid, the 3%% and the processing part together (total_charged), on transaction % — expected % fils (AED %), got % fils (AED %). A refund figure is read off the payment, never typed. (refund_amount_is_not_the_fee_paid)',
      NEW.transaction_id, v_expected, round(coalesce(t.total_charged, t.reveal_fee),2), NEW.amount_fils, round(NEW.amount_fils/100.0,2)
      using errcode = '23514';
  end if;

  return NEW;
end
$function$;

CREATE OR REPLACE FUNCTION public.fn_refund_open_from_customer(p_transaction_id uuid, p_requested_by text, p_reason_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
     round(coalesce(t.total_charged, t.reveal_fee, 0) * 100)::bigint, 'AED',
     'supplier_unresponsive',
     coalesce(p_reason_note, 'The customer reported that the revealed supplier has not responded.'),
     'requested', coalesce(p_requested_by, 'customer'), now(), 'in_platform_request')
  returning id into v_id;

  return jsonb_build_object('ok', true, 'refund_id', v_id,
    'status', 'requested',
    'next', 'customer_support checks whether the supplier ever answered; the CEO decides on that '
         || 'record; the accountant pays and raises the supplier penalty. The customer asking is '
         || 'the trigger, not the verdict.');
end $function$;

CREATE OR REPLACE FUNCTION public.fn_support_investigate_refund(p_transaction_id uuid, p_reason text, p_case_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t record; v_grant jsonb; v_id bigint; v_elig text; v_why text; v_prior int;
begin
  v_grant := public.fn_support_may_act('refund');
  if (v_grant->>'may_act') <> 'true' then
    return jsonb_build_object('ok', false, 'reason', v_grant->>'reason', 'route', v_grant->>'route');
  end if;

  select id, quote_amount, reveal_fee, total_charged, fee_status, refund_status, refund_amount_aed
    into t from public.transactions where id = p_transaction_id;
  if not found then
    -- "A tool error means cannot verify now, not no inquiry." A missing transaction is a real answer;
    -- it is reported as one and not as an ineligibility.
    return jsonb_build_object('ok', false, 'reason',
      'no such transaction. This is not an eligibility finding -- nothing was assessed.');
  end if;

  -- AGGREGATE OVER-REFUNDING. Everything already refunded on this transaction, counted before
  -- anything new is proposed.
  select count(*) into v_prior from public.refund_case
   where transaction_id = p_transaction_id and state in ('succeeded','reconciled','communicated');

  if coalesce(t.fee_status,'') not in ('paid','collected','succeeded') then
    v_elig := 'ineligible';
    v_why := format('the reveal fee is %L, so nothing has settled. There is no payment to refund; this is a settlement question, not a refund one.', coalesce(t.fee_status,'(none)'));
  elsif v_prior > 0 then
    v_elig := 'ineligible';
    v_why := format('%s refund(s) already succeeded on this transaction. A second would be an aggregate over-refund.', v_prior);
  else
    v_elig := 'eligible';
    v_why := 'the reveal fee settled and no prior refund has succeeded on this transaction.';
  end if;

  insert into public.refund_case
    (transaction_id, case_id, state, amount_aed, requested_reason, investigated_at,
     evidence, eligibility, eligibility_reason)
  values
    (p_transaction_id, p_case_id,
     case when v_elig = 'eligible' then 'eligible' else 'ineligible' end,
     coalesce(t.total_charged, t.reveal_fee, 0), p_reason, now(),
     jsonb_build_object('fee_status', t.fee_status, 'reveal_fee', t.reveal_fee,
                        'prior_successful_refunds', v_prior, 'read_at', now()),
     v_elig, v_why)
  on conflict do nothing
  returning refund_id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', false, 'duplicate', true, 'reason',
      'a live refund already exists on this transaction. Concurrent remedies are prevented by index, not by hoping.');
  end if;

  return jsonb_build_object('ok', true, 'refund_id', v_id, 'eligibility', v_elig, 'why', v_why,
    'next', case when v_elig = 'eligible'
                 then 'Put it to the CEO. Support investigated; it does not decide.'
                 else 'No decision is needed: the investigation found it ineligible, with the reason recorded.' end);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_gl_sync_business()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; n int := 0; acct text;
        fee_pct numeric; fee_fixed numeric; fee numeric(18,2); gross numeric(18,2); net numeric(18,2);
        fx numeric; amt_aed numeric(18,2); diff numeric(18,2); extra numeric(18,2); lines jsonb;
begin
  select num_value into fee_pct   from public.gl_settings where key='stripe_fee_pct';
  select num_value into fee_fixed from public.gl_settings where key='stripe_fee_fixed';
  select num_value into fx        from public.gl_settings where key='usd_to_aed';
  fee_pct   := coalesce(fee_pct,0);
  fee_fixed := coalesce(fee_fixed,0);
  fx        := coalesce(fx, 3.6725);

  -- 1) Reveal-fee revenue with Stripe fee split (refunded transactions excluded)
  for r in
    select id, reveal_fee, total_charged, processing_fee, stripe_fee_fils, coalesce(revealed_at::date, current_date) as d
    from public.transactions
    where fee_status='paid' and coalesce(reveal_fee,0) > 0
      and coalesce(refund_status,'') not in ('refunded','refund_approved','succeeded')
      and not exists (select 1 from public.gl_journal g where g.source='reveal_fee' and g.source_ref=transactions.id::text)
  loop
    gross := round(coalesce(r.total_charged, r.reveal_fee),2);
    fee   := coalesce(round(r.stripe_fee_fils / 100.0, 2), r.processing_fee, round(gross*fee_pct/100 + fee_fixed, 2));
    if fee >= gross then fee := 0; end if;
    net   := gross - fee;
    perform public.fn_gl_entry(r.d, 'Reveal fee (net of Stripe fee)', 'reveal_fee', r.id::text,
      case when fee > 0 then
        jsonb_build_array(
          jsonb_build_object('account','1050','debit',net),
          jsonb_build_object('account','6100','debit',fee),
          jsonb_build_object('account','4000','credit',gross))
      else
        jsonb_build_array(
          jsonb_build_object('account','1050','debit',gross),
          jsonb_build_object('account','4000','credit',gross))
      end, 'gl_sync');
    n := n + 1;
  end loop;

  -- 1b) REFUND PAID OUT: everything the customer paid (total_charged) goes back. Stripe keeps its
  --     processing fee and QuotesDone absorbs it (founder, 14 Sep 2026). 'succeeded' is the status the
  --     refunds-table path writes, and it was missing here, so a Stripe-settled refund never posted.
  --     If the sale was booked, the refund reverses it through 6900 and the fee booked at sale stays in
  --     6100 as the absorbed cost. If it was not, the only real movement is the fee: 6100 / 1050.
  for r in
    select t.id, coalesce(t.total_charged, t.reveal_fee, t.app_fee, 0) as amt,
           coalesce(round(t.stripe_fee_fils / 100.0, 2), t.processing_fee, round(coalesce(t.total_charged, t.reveal_fee, t.app_fee, 0)*fee_pct/100 + fee_fixed, 2)) as fee_absorbed,
           exists (select 1 from public.gl_journal g where g.source='reveal_fee' and g.source_ref=t.id::text) as sale_booked,
           coalesce(t.refund_resolved_at::date, t.revealed_at::date, current_date) as d
    from public.transactions t
    where coalesce(t.refund_status,'') in ('refunded','refund_approved','succeeded')
      and coalesce(t.total_charged, t.reveal_fee, t.app_fee, 0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='refund_paid' and g.source_ref=t.id::text)
  loop
    gross := round(r.amt,2);
    if r.sale_booked then
      perform public.fn_gl_entry(r.d, 'Reveal charge refunded in full to the customer; the Stripe fee booked at sale stays in 6100, absorbed',
        'refund_paid', r.id::text,
        jsonb_build_array(jsonb_build_object('account','6900','debit',gross),
                          jsonb_build_object('account','1050','credit',gross)), 'gl_sync');
      n := n + 1;
    else
      fee := least(round(coalesce(r.fee_absorbed,0),2), gross);
      if fee > 0 then
        perform public.fn_gl_entry(r.d, 'Stripe processing fee absorbed on a reveal refunded in full before its sale was booked',
          'refund_paid', r.id::text,
          jsonb_build_array(jsonb_build_object('account','6100','debit',fee),
                            jsonb_build_object('account','1050','credit',fee)), 'gl_sync');
        n := n + 1;
      end if;
    end if;
  end loop;

  -- 2) Clawback RAISED on the supplier. Credits 6900 (recovering the refund), NOT 4100.
  --    Any admin fee / interest assessed at the same time is genuine income -> 4400.
  for r in
    select id, amount_due,
           coalesce(admin_fee,0) + coalesce(interest_amount,0) as extra_owed,
           coalesce(reveal_date, created_at::date, current_date) as d
    from public.supplier_dues
    where coalesce(amount_due,0) > 0
      and coalesce(status,'') not in ('waived','cancelled','reversed')
      and not exists (select 1 from public.gl_journal g where g.source='commission_accrue' and g.source_ref=supplier_dues.id::text)
  loop
    extra := round(coalesce(r.extra_owed,0),2);
    lines := jsonb_build_array(
      jsonb_build_object('account','1110','debit', round(r.amount_due,2) + extra),
      jsonb_build_object('account','6900','credit', round(r.amount_due,2)));
    if extra > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','4400','credit', extra)); end if;
    perform public.fn_gl_entry(r.d,
      'Refund clawback raised on supplier' || case when extra > 0 then ' (incl. ' || extra || ' admin fee/interest)' else '' end,
      'commission_accrue', r.id::text, lines, 'gl_sync');
    n := n + 1;
  end loop;

  -- 2b) Supplier SETTLES via Stripe.
  for r in
    select id, amount_due,
           coalesce(fine_amount,0) + coalesce(interest_amount,0) + coalesce(admin_fee,0) as extra_owed,
           paid_at::date as d
    from public.supplier_dues
    where status in ('paid','settled') and paid_at is not null and coalesce(amount_due,0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='commission_collect' and g.source_ref=supplier_dues.id::text)
  loop
    extra := round(coalesce(r.extra_owed,0),2);
    gross := round(r.amount_due,2) + extra;
    fee   := round(gross*fee_pct/100 + fee_fixed, 2);
    if fee >= gross then fee := 0; end if;
    net   := gross - fee;

    lines := jsonb_build_array(jsonb_build_object('account','1050','debit',net));
    if fee > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','6100','debit',fee)); end if;
    lines := lines || jsonb_build_array(jsonb_build_object('account','1110','credit', gross));

    perform public.fn_gl_entry(r.d,
      'Refund clawback settled by supplier via Stripe' || case when extra > 0 then ' (incl. ' || extra || ' admin fee/interest)' else '' end,
      'commission_collect', r.id::text, lines, 'gl_sync');
    n := n + 1;
  end loop;

  -- 2c) SUBSCRIPTION revenue (RULE 1). Previously never posted - 4200 sat unused.
  for r in
    select l.id, l.registration_fee_due, l.registration_paid_at::date as d
    from public.leads l
    where l.registration_status = 'paid'
      and l.registration_paid_at is not null
      and coalesce(l.registration_fee_due,0) >= 0
      and coalesce(l.subscription_exempt,false) = false
      and not exists (select 1 from public.gl_journal g
                      where g.source='subscription' and g.source_ref = l.id::text || ':' || l.registration_paid_at::date)
  loop
    gross := round(coalesce(r.registration_fee_due,0),2);
    if gross <= 0 then continue; end if;
    fee := round(gross*fee_pct/100 + fee_fixed, 2);
    if fee >= gross then fee := 0; end if;
    net := gross - fee;
    lines := jsonb_build_array(jsonb_build_object('account','1050','debit',net));
    if fee > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','6100','debit',fee)); end if;
    lines := lines || jsonb_build_array(jsonb_build_object('account','4200','credit',gross));
    perform public.fn_gl_entry(r.d, 'Annual supplier subscription', 'subscription',
      r.id::text || ':' || r.d::text, lines, 'gl_sync');
    n := n + 1;
  end loop;

  -- 3) Expense charges, converted to AED (the ledger currency)
  for r in
    select e.id, e.amount, upper(coalesce(e.currency,'AED')) as cur, e.category, e.vendor,
           coalesce(e.charged_on, e.created_at::date) as d
    from public.expense_entries e
    where coalesce(e.amount,0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='expense' and g.source_ref=e.id::text)
  loop
    if r.cur not in ('AED','USD') then
      begin
        insert into public.founder_alerts(level, event, detail, channel)
        values ('warn', 'gl_unconvertible_currency',
                'Expense #'||r.id||' from '||coalesce(r.vendor,'?')||' is in '||r.cur||
                ', which has no rate in gl_settings, so it was NOT posted. Expenses are understated by '||
                r.amount||' '||r.cur||' until a rate is added. Skipped rather than booked at 1:1.', 'system');
      exception when others then null; end;
      continue;
    end if;
    amt_aed := round(r.amount * case when r.cur='USD' then fx else 1 end, 2);
    acct := coalesce((select account_code from public.gl_expense_map m where m.category=r.category), '6300');
    perform public.fn_gl_entry(r.d,
      'Expense: '||coalesce(r.category,'G&A')||case when r.cur='USD' then ' ('||r.amount||' USD @ '||fx||')' else '' end,
      'expense', r.id::text,
      jsonb_build_array(jsonb_build_object('account',acct,'debit',amt_aed),
                        jsonb_build_object('account','1000','credit',amt_aed)), 'gl_sync');
    n := n + 1;
  end loop;

  -- 3b) One-off FX correction for USD expenses posted at 1:1 before the 19 Jul 2026 fix.
  for r in
    select e.id, e.amount, e.category, e.vendor,
           coalesce(e.charged_on, e.created_at::date) as d,
           (select sum(jl.debit) from public.gl_journal g
              join public.gl_journal_lines jl on jl.journal_id = g.id
             where g.source='expense' and g.source_ref = e.id::text and jl.debit > 0) as posted_aed
    from public.expense_entries e
    where upper(coalesce(e.currency,'AED')) = 'USD'
      and coalesce(e.amount,0) > 0
      and exists (select 1 from public.gl_journal g where g.source='expense' and g.source_ref=e.id::text)
      and not exists (select 1 from public.gl_journal g where g.source='expense_fx_adj' and g.source_ref=e.id::text)
  loop
    diff := round(r.amount * fx, 2) - coalesce(r.posted_aed, 0);
    if diff is null or diff = 0 then continue; end if;
    acct := coalesce((select account_code from public.gl_expense_map m where m.category=r.category), '6300');
    perform public.fn_gl_entry(r.d,
      'FX correction: expense #'||r.id||' ('||coalesce(r.vendor,'?')||') was booked at 1:1; restated at USD/AED '||fx,
      'expense_fx_adj', r.id::text,
      jsonb_build_array(jsonb_build_object('account',acct,'debit',diff),
                        jsonb_build_object('account','1000','credit',diff)), 'gl_fx_fix');
    n := n + 1;
  end loop;

  return n;
end
$function$;
