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

-- WHO AND WHEN (2 Oct 2026, review of #1173). Every payment row says who entered it and when: 'service' for a
-- settlement the trigger records, 'accountant' for a transfer the accountant records. Any other value is refused.
alter table public.supplier_due_payments add column if not exists entered_by text not null default 'service';
alter table public.supplier_due_payments add column if not exists created_at timestamptz not null default now();
alter table public.supplier_due_payments drop constraint if exists supplier_due_payments_entered_by_check;
alter table public.supplier_due_payments add constraint supplier_due_payments_entered_by_check check (entered_by in ('accountant', 'service'));

-- WHAT STRIPE ACTUALLY CHARGED (2 Oct 2026, review of #1173). The settlement row recomputed the owed figure at
-- paid_at; a checkout opened before midnight and paid after it was recorded at a day's more interest than Stripe took.
-- supplier_pay now stores, per due, the exact amount it put on the session (the line items sum to the session's
-- amount_total), and stripe_webhook writes the session id onto the due it settles; the settlement row reads this.
create table if not exists public.supplier_due_checkouts (
  session_id  text not null check (btrim(session_id) <> ''),
  due_id      bigint not null references public.supplier_dues(id),
  amount_aed  numeric(12,2) not null check (amount_aed > 0),
  created_at  timestamptz not null default now(),
  primary key (session_id, due_id)
);
comment on table public.supplier_due_checkouts is
  'Per due, the amount supplier_pay put on each Stripe Checkout session; a Stripe settlement records exactly this. Seat: accountant.';
alter table public.supplier_due_checkouts enable row level security;
drop policy if exists supplier_due_checkouts_service_role_only on public.supplier_due_checkouts;
create policy supplier_due_checkouts_service_role_only on public.supplier_due_checkouts
  as permissive for all to public using (false) with check (false);
revoke all on public.supplier_due_checkouts from anon, authenticated;
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('supplier_due_checkouts', true, 'payment', 'per due, the amount each supplier_dues Stripe checkout charged; the settlement row records it', 'accountant')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

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
-- WHAT IS STILL OWED, LIVE (30 Sep 2026, checkout review of #1173). supplier_pay billed amount_due + admin_fee +
-- interest_amount + fine_amount from the stored columns, so a supplier who part-paid by bank was asked for the whole
-- figure again. This is the one figure the checkout, the portal and the settlement row now read: per due, the charge's
-- total (unpaid principal after every payment from its own date + simple interest to p_as_of) + any legacy fine
-- (0 on every due at 30 Sep 2026). A due with no transaction (no charge to compute) falls back to the stored columns
-- less every recorded payment, never below 0.
create or replace function public.fn_supplier_dues_outstanding(p_due_ids bigint[], p_as_of date default null)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare d public.supplier_dues; v jsonb; out jsonb := '{}'; v_paid numeric;
begin
  for d in select * from public.supplier_dues where id = any(p_due_ids) loop
    v_paid := coalesce((select sum(p.amount_aed) from public.supplier_due_payments p where p.due_id = d.id), 0);
    v := case when d.transaction_id is not null then public.fn_accountant_nonresponse_charge(d.transaction_id, p_as_of) end;
    if coalesce((v->>'ok')::boolean, false) then
      out := out || jsonb_build_object(d.id::text, jsonb_build_object(
        'owed_aed', round(greatest(0, (v->>'total_aed')::numeric + coalesce(d.fine_amount, 0)), 2),
        'unpaid_principal_aed', (v->>'unpaid_principal_aed')::numeric, 'interest_aed', (v->>'interest_aed')::numeric,
        'paid_aed', (v->>'paid_aed')::numeric, 'source', 'fn_accountant_nonresponse_charge'));
    else
      out := out || jsonb_build_object(d.id::text, jsonb_build_object(
        'owed_aed', round(greatest(0, coalesce(d.amount_due, 0) + coalesce(d.admin_fee, 0) + coalesce(d.interest_amount, 0) + coalesce(d.fine_amount, 0) - v_paid), 2),
        'unpaid_principal_aed', null, 'interest_aed', coalesce(d.interest_amount, 0), 'paid_aed', v_paid, 'source', 'stored columns less payments'));
    end if;
  end loop;
  return out;
end $function$;
revoke execute on function public.fn_supplier_dues_outstanding(bigint[], date) from public, anon, authenticated;

create or replace function public.fn_supplier_due_record_settlement(p_due_id bigint)
 returns bigint
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare d public.supplier_dues; v_rest numeric; v_id bigint; v_on date;
begin
  select * into d from public.supplier_dues where id = p_due_id;
  if not found or d.paid_at is null or coalesce(d.status, '') in ('reversed', 'refunded', 'cancelled') then return null; end if;
  v_on := (d.paid_at at time zone 'Asia/Dubai')::date;
  if nullif(btrim(d.stripe_session_id), '') is not null or d.payment_ref ~ '^(pi|cs)_' then
    -- a Stripe settlement records what the session charged for this due, stored at checkout; never a figure
    -- recomputed at paid_at (a day's interest apart when the checkout and the payment straddle midnight)
    select c.amount_aed into v_rest from public.supplier_due_checkouts c
     where c.session_id = d.stripe_session_id and c.due_id = d.id;
    if v_rest is null then
      perform public.fn_it_engineer_finding_upsert('acct:stripe_settlement_without_checkout_amount:' || d.id,
        'A Stripe settlement of supplier due ' || d.id || ' has no stored checkout amount, so no payment row was recorded',
        'public.fn_supplier_due_record_settlement', 'agent_facing', 1,
        jsonb_build_object('due_id', d.id, 'stripe_session_id', d.stripe_session_id, 'payment_ref', d.payment_ref,
                           'owner_seat', 'accountant', 'raised_by_seat', 'accountant'),
        '{}'::text[], '{}'::text[], 'accountant');
      return null;
    end if;
  else
    -- any other writer of paid_at: what was still owed on the settlement date, before this settlement
    v_rest := (public.fn_supplier_dues_outstanding(array[d.id], v_on) -> d.id::text ->> 'owed_aed')::numeric;
    if v_rest is null or v_rest <= 0 then return null; end if;
  end if;
  insert into public.supplier_due_payments (due_id, paid_on, amount_aed, reference, entered_by)
  values (d.id, v_on, v_rest, coalesce(nullif(btrim(d.payment_ref), ''), 'supplier_dues.paid_at #' || d.id), 'service')
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

-- THE BANK-PAYMENT ROUTINE REFUSES WHAT IS NOT OWED (2 Oct 2026, review of #1173). It accepted any amount on any due:
-- a typo of 5,500 for 550 drove the principal negative, and a payment could land on a due already paid or reversed.
-- Now: never above what is still owed (unpaid principal + interest to paid_on + fees, and never above today's figure,
-- so a back-dated entry cannot count a later payment twice); never on a due paid, settled, waived, reversed, refunded
-- or cancelled. An overpayment attempt raises an accountant finding. Only the service role may call it: the
-- accountant seat runs as the service role, and EXECUTE is revoked from public, anon and authenticated.
drop function if exists public.fn_accountant_record_supplier_payment(bigint, numeric, date, text);
create or replace function public.fn_accountant_record_supplier_payment(p_due_id bigint, p_amount numeric, p_paid_on date, p_reference text,
                                                                        p_entered_by text default 'accountant')
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare d public.supplier_dues; v_id bigint; v jsonb; v_owed numeric; v_today date := (now() at time zone 'Asia/Dubai')::date;
begin
  if coalesce(p_entered_by, '') not in ('accountant', 'service') then
    return jsonb_build_object('ok', false, 'reason', 'entered_by must be accountant or service');
  end if;
  if p_amount is null or p_amount <= 0 then return jsonb_build_object('ok', false, 'reason', 'the amount must be above zero'); end if;
  if p_paid_on is null or p_paid_on > v_today then
    return jsonb_build_object('ok', false, 'reason', 'the payment date is missing or in the future');
  end if;
  if nullif(btrim(p_reference), '') is null then return jsonb_build_object('ok', false, 'reason', 'a bank or Stripe reference is required'); end if;
  select * into d from public.supplier_dues where id = p_due_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such due'); end if;
  if d.paid_at is not null or coalesce(d.status, '') in ('paid', 'settled', 'waived', 'reversed', 'refunded', 'cancelled', 'void') then
    return jsonb_build_object('ok', false, 'reason', 'this due is ' || coalesce(nullif(d.status, ''), 'paid') || ', so nothing is owed on it');
  end if;
  v_owed := least((public.fn_supplier_dues_outstanding(array[d.id], p_paid_on) -> d.id::text ->> 'owed_aed')::numeric,
                  (public.fn_supplier_dues_outstanding(array[d.id], v_today)   -> d.id::text ->> 'owed_aed')::numeric);
  if v_owed is null or round(p_amount, 2) > v_owed then
    perform public.fn_it_engineer_finding_upsert('acct:supplier_overpayment:' || d.id || ':' || btrim(p_reference),
      'An attempt to record AED ' || round(p_amount, 2) || ' against supplier due ' || d.id || ' exceeds the AED ' || coalesce(v_owed, 0) || ' still owed',
      'public.fn_accountant_record_supplier_payment', 'agent_facing', 1,
      jsonb_build_object('due_id', d.id, 'amount_aed', round(p_amount, 2), 'owed_aed', v_owed, 'paid_on', p_paid_on,
                         'reference', btrim(p_reference), 'entered_by', p_entered_by, 'owner_seat', 'accountant', 'raised_by_seat', 'accountant'),
      '{}'::text[], '{}'::text[], 'accountant');
    return jsonb_build_object('ok', false, 'reason', 'the amount is above the AED ' || coalesce(v_owed, 0) || ' still owed on this due; nothing was recorded', 'owed_aed', v_owed);
  end if;
  insert into public.supplier_due_payments (due_id, paid_on, amount_aed, reference, entered_by)
  values (p_due_id, p_paid_on, round(p_amount, 2), btrim(p_reference), p_entered_by)
  on conflict (due_id, reference) do nothing returning id into v_id;
  if v_id is null then
    return jsonb_build_object('ok', false, 'reason', 'this reference is already recorded against this due, so the payment is not counted twice');
  end if;
  v := public.fn_accountant_nonresponse_charge(d.transaction_id, null);
  -- settled only when nothing is outstanding: no unpaid principal and no interest
  if coalesce((v->>'ok')::boolean, false) and (v->>'total_aed')::numeric <= 0 then
    update public.supplier_dues set paid_at = now(), status = 'paid', payment_ref = btrim(p_reference) where id = p_due_id;
  end if;
  return jsonb_build_object('ok', true, 'payment_id', v_id, 'due_id', p_due_id, 'settled', coalesce((v->>'total_aed')::numeric, 1) <= 0,
                            'paid_aed', v->'paid_aed', 'unpaid_principal_aed', v->'unpaid_principal_aed', 'interest_aed', v->'interest_aed', 'total_aed', v->'total_aed');
end $function$;
revoke execute on function public.fn_accountant_record_supplier_payment(bigint, numeric, date, text, text) from public, anon, authenticated;

-- backfill: every due already paid, through the same routine (idempotent: it records only what is not yet recorded)
select public.fn_supplier_due_record_settlement(d.id) from public.supplier_dues d where d.paid_at is not null order by d.id;

-- THE STORED FIGURE THE PORTAL AND THE LEDGER VIEWS READ (total_claim) REFLECTS RECORDED PAYMENTS. Production's body
-- (pg_get_functiondef, 30 Sep 2026) set total_claim = amount_due + admin_fee + interest, whatever had been paid; it is
-- now fn_supplier_dues_outstanding's owed figure (unpaid principal + interest to date + legacy fine). Changed only there.
create or replace function public.fn_supplier_dues_accrue_interest(p_as_of date DEFAULT NULL::date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare x record; v jsonb; n int := 0; v_owed numeric;
begin
  for x in select id, transaction_id from public.supplier_dues
            where public.fn_supplier_due_is_owed(status, paid_at) and transaction_id is not null loop
    v := public.fn_accountant_nonresponse_charge(x.transaction_id, p_as_of);
    continue when not coalesce((v->>'ok')::boolean, false);
    -- 30 SEP 2026 (accountant): what is still owed, after every recorded payment
    v_owed := (public.fn_supplier_dues_outstanding(array[x.id], p_as_of) -> x.id::text ->> 'owed_aed')::numeric;
    update public.supplier_dues
       set interest_amount = (v->>'interest_aed')::numeric, total_claim = v_owed,
           due_date = (v->>'due_date')::date, due_date_30 = (v->>'due_date')::date + 23
     where id = x.id
       and (interest_amount is distinct from (v->>'interest_aed')::numeric
            or total_claim is distinct from v_owed
            or due_date is distinct from (v->>'due_date')::date);
    if found then n := n + 1; end if;
  end loop;
  return n;
end $function$;
