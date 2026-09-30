-- EVERY SETTLEMENT OF A NON-RESPONSE DUE IS A PAYMENT ROW (30 Sep 2026). Seat: accountant.
--
-- #1167 (nonresponse_interest_is_the_agreed_rate_or_nine_percent.sql, applied) made fn_accountant_nonresponse_charge
-- reduce the principal from each row of public.supplier_due_payments. The review measured that nothing writes that
-- table: stripe_webhook settles whole dues only through supplier_dues.paid_at, supplier_pay only opens the checkout,
-- supplier_api only reads, and no routine records a bank transfer. Production at 30 Sep 2026: 0 payment rows,
-- 1 due (status reversed, never paid), so the backfill below inserts nothing today and stays for any replay.
--
-- The table as #1167 created it had a nullable reference with no key; it holds 0 rows, so the reference becomes
-- required and unique per due here (a Stripe delivery or a transfer can never count twice).
--
-- prevented by: scripts/checks/nonresponse_interest_is_the_agreed_rate_or_nine_percent_simple.test.mjs

alter table public.supplier_due_payments alter column reference set not null;
alter table public.supplier_due_payments drop constraint if exists supplier_due_payments_reference_check;
alter table public.supplier_due_payments add constraint supplier_due_payments_reference_check check (btrim(reference) <> '');
alter table public.supplier_due_payments drop constraint if exists supplier_due_payments_due_reference_key;
alter table public.supplier_due_payments add constraint supplier_due_payments_due_reference_key unique (due_id, reference);

-- ===================================================================================================================
-- EVERY SETTLEMENT IS A PAYMENT ROW (30 Sep 2026, accountant; review of #1167: nothing wrote supplier_due_payments).
-- Measured: stripe_webhook is the one writer of supplier_dues.paid_at (its own comment and a grep of every function);
-- supplier_pay only opens the checkout and supplier_api only reads; no routine recorded a bank transfer.
--  (1) A trigger on supplier_dues: whenever paid_at goes from empty to set, by ANY writer, the full payment is
--      recorded as one row: amount = amount_due + admin_fee + interest_amount + fine_amount (what supplier_pay
--      charges), date = paid_at (Dubai), reference = payment_ref (the Stripe payment intent or session). A path that
--      already recorded its payment (the routine below) writes the same reference, so the unique key skips it.
--  (2) fn_accountant_record_supplier_payment: the accountant records a bank transfer or a part payment. paid_at is set
--      only when the charge shows nothing outstanding (principal and interest).
--  (3) Backfill: every due already paid gets its full-payment row, idempotently (on conflict do nothing).
-- ===================================================================================================================

-- The settlement row records only what is NOT already recorded against the due (the full charge minus the rows the
-- accountant or an earlier settlement wrote), so a part payment followed by a Stripe settlement is never counted twice.
-- A due whose money went back (status reversed / refunded / cancelled) gets no row.
create or replace function public.fn_supplier_due_record_settlement(p_due_id bigint)
 returns bigint
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare d public.supplier_dues; v_rest numeric; v_id bigint;
begin
  select * into d from public.supplier_dues where id = p_due_id;
  if not found or d.paid_at is null or coalesce(d.status, '') in ('reversed', 'refunded', 'cancelled') then return null; end if;
  v_rest := round(coalesce(d.amount_due, 0) + coalesce(d.admin_fee, 0) + coalesce(d.interest_amount, 0) + coalesce(d.fine_amount, 0)
                  - coalesce((select sum(p.amount_aed) from public.supplier_due_payments p where p.due_id = d.id), 0), 2);
  if v_rest <= 0 then return null; end if;
  insert into public.supplier_due_payments (due_id, paid_on, amount_aed, reference)
  values (d.id, (d.paid_at at time zone 'Asia/Dubai')::date, v_rest, coalesce(nullif(btrim(d.payment_ref), ''), 'supplier_dues.paid_at #' || d.id))
  on conflict (due_id, reference) do nothing returning id into v_id;
  return v_id;
end $function$;
revoke execute on function public.fn_supplier_due_record_settlement(bigint) from public, anon, authenticated;

create or replace function public.fn_supplier_due_paid_records_payment()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  -- any writer, insert or update: paid_at going from empty to set is a settlement
  if new.paid_at is not null and (tg_op = 'INSERT' or old.paid_at is null) then
    perform public.fn_supplier_due_record_settlement(new.id);
  end if;
  return new;
end $function$;
revoke execute on function public.fn_supplier_due_paid_records_payment() from public, anon, authenticated;

drop trigger if exists trg_supplier_due_paid_records_payment on public.supplier_dues;
create trigger trg_supplier_due_paid_records_payment
  after insert or update of paid_at on public.supplier_dues
  for each row execute function public.fn_supplier_due_paid_records_payment();

create or replace function public.fn_accountant_record_supplier_payment(p_due_id bigint, p_amount numeric, p_paid_on date, p_reference text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare d public.supplier_dues; v_id bigint; v jsonb;
begin
  if p_amount is null or p_amount <= 0 then return jsonb_build_object('ok', false, 'reason', 'the amount must be above zero'); end if;
  if p_paid_on is null or p_paid_on > (now() at time zone 'Asia/Dubai')::date then
    return jsonb_build_object('ok', false, 'reason', 'the payment date is missing or in the future');
  end if;
  if nullif(btrim(p_reference), '') is null then return jsonb_build_object('ok', false, 'reason', 'a bank or Stripe reference is required'); end if;
  select * into d from public.supplier_dues where id = p_due_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such due'); end if;
  insert into public.supplier_due_payments (due_id, paid_on, amount_aed, reference)
  values (p_due_id, p_paid_on, round(p_amount, 2), btrim(p_reference))
  on conflict (due_id, reference) do nothing returning id into v_id;
  if v_id is null then
    return jsonb_build_object('ok', false, 'reason', 'this reference is already recorded against this due, so the payment is not counted twice');
  end if;
  v := public.fn_accountant_nonresponse_charge(d.transaction_id, null);
  -- settled only when nothing is outstanding: no unpaid principal and no interest
  if d.paid_at is null and coalesce((v->>'ok')::boolean, false) and (v->>'total_aed')::numeric <= 0 then
    update public.supplier_dues set paid_at = now(), status = 'paid', payment_ref = btrim(p_reference) where id = p_due_id;
  end if;
  return jsonb_build_object('ok', true, 'payment_id', v_id, 'due_id', p_due_id, 'settled', d.paid_at is null and coalesce((v->>'total_aed')::numeric, 1) <= 0,
                            'paid_aed', v->'paid_aed', 'unpaid_principal_aed', v->'unpaid_principal_aed', 'interest_aed', v->'interest_aed', 'total_aed', v->'total_aed');
end $function$;
revoke execute on function public.fn_accountant_record_supplier_payment(bigint, numeric, date, text) from public, anon, authenticated;

-- backfill: every due already paid, through the same routine (idempotent: it records only what is not yet recorded)
select public.fn_supplier_due_record_settlement(d.id) from public.supplier_dues d where d.paid_at is not null order by d.id;
