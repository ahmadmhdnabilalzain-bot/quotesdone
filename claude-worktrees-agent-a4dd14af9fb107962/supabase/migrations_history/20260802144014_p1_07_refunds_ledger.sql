-- PHASE 1.7 - a real refunds ledger.
--
-- WHY THIS IS A GAP AND NOT A NAMING PROBLEM. The company-operations corpus binds Payments & Revenue
-- to an object called `refunds`. There isn't one. Refunds today are implied by a stripe_transactions
-- row plus, sometimes, a decision_record - which means nobody can answer: how many refunds, at what
-- rate, for what reason, approved by whom, reconciled against which Stripe object, and did the money
-- actually leave. The reveal fee is the only revenue this business has; a refund is the only way it
-- goes backwards. Not being able to count that is not an accounting inconvenience.
--
-- Design notes:
--  * request and settlement are separate states, because a refund that Stripe rejected is a
--    different fact from one nobody has approved yet;
--  * amounts are stored in FILS (integer), not decimal AED - float money is how reconciliations end
--    up 0.01 apart forever;
--  * approver is required for anything outside the automatic window, and the automatic window is a
--    named policy rather than a hardcoded 3;
--  * every row carries the Stripe ids, so reconciliation is a join and not an investigation.

create table if not exists public.refunds (
  id                 bigserial primary key,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),

  inquiry_id         uuid,
  customer_id        uuid,
  supplier_lead_id   bigint,
  quote_id           bigint,

  -- what was originally taken
  original_txn_id    bigint,
  stripe_payment_intent text,
  stripe_charge_id   text,
  stripe_refund_id   text unique,

  amount_fils        bigint not null check (amount_fils > 0),
  currency           text not null default 'AED' check (currency = 'AED'),

  reason_code        text not null check (reason_code in (
                       'supplier_unresponsive','supplier_withdrew','duplicate_charge',
                       'customer_cancelled_in_window','service_not_delivered',
                       'fraud_or_dispute','goodwill','other')),
  reason_note        text,

  status             text not null default 'requested' check (status in (
                       'requested','approved','rejected','processing','succeeded','failed','cancelled')),
  requested_by       text not null,
  requested_at       timestamptz not null default now(),
  decided_by         text,
  decided_at         timestamptz,
  decision_note      text,
  within_auto_window boolean not null default false,

  settled_at         timestamptz,
  failure_reason     text,

  -- finance linkage
  gl_entry_id        bigint,
  reconciled_at      timestamptz,
  reconciliation_note text
);

create index if not exists refunds_status_idx    on public.refunds (status, created_at desc);
create index if not exists refunds_inquiry_idx   on public.refunds (inquiry_id);
create index if not exists refunds_customer_idx  on public.refunds (customer_id);
create index if not exists refunds_stripe_pi_idx on public.refunds (stripe_payment_intent);
create index if not exists refunds_unreconciled_idx on public.refunds (settled_at) where reconciled_at is null and status = 'succeeded';

alter table public.refunds enable row level security;
revoke all on public.refunds from anon, authenticated;
grant all on public.refunds to service_role;

comment on table public.refunds is
  'The refund ledger. One row per refund from request to settlement to reconciliation. Amounts in fils. Created 2 Aug 2026 (Phase 1.7) after the audit found refunds were only implied by stripe_transactions plus a decision_record, so refund rate, reason, approver and reconciliation were all unanswerable.';

create or replace function public.trg_refunds_touch() returns trigger language plpgsql as $$
begin NEW.updated_at := now(); return NEW; end $$;
drop trigger if exists refunds_touch on public.refunds;
create trigger refunds_touch before update on public.refunds for each row execute function public.trg_refunds_touch();

-- REQUEST. Anyone (customer flow, supplier non-response sweep, support) can raise one. Raising is
-- not approving: a request with no decision sits visible in the queue rather than moving money.
create or replace function public.fn_refund_request(
  p_amount_fils bigint, p_reason_code text, p_requested_by text,
  p_inquiry_id uuid default null, p_customer_id uuid default null,
  p_supplier_lead_id bigint default null, p_quote_id bigint default null,
  p_payment_intent text default null, p_charge_id text default null,
  p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_days int; v_auto boolean := false; v_paid timestamptz;
begin
  if p_amount_fils is null or p_amount_fils <= 0 then
    return jsonb_build_object('ok', false, 'error', 'amount_required');
  end if;

  select refund_window_working_days into v_days from public.pricing_config where id = 1;

  -- inside the published refund window a refund is a promise the company already made, so it does
  -- not need a human to agree to it again. Outside it, somebody owns the decision.
  select paid_at into v_paid from public.stripe_transactions
   where (p_payment_intent is not null and payment_intent = p_payment_intent) limit 1;
  if v_paid is not null and v_paid > now() - make_interval(days => coalesce(v_days,3)) then
    v_auto := true;
  end if;

  insert into public.refunds (inquiry_id, customer_id, supplier_lead_id, quote_id,
                              stripe_payment_intent, stripe_charge_id,
                              amount_fils, reason_code, reason_note, requested_by,
                              within_auto_window, status)
  values (p_inquiry_id, p_customer_id, p_supplier_lead_id, p_quote_id,
          p_payment_intent, p_charge_id, p_amount_fils, p_reason_code, p_note, p_requested_by,
          v_auto, case when v_auto then 'approved' else 'requested' end)
  returning id into v_id;

  if v_auto then
    update public.refunds set decided_by = 'policy:auto_window', decided_at = now(),
           decision_note = 'Inside the published ' || coalesce(v_days,3) || '-working-day refund window'
     where id = v_id;
  end if;

  return jsonb_build_object('ok', true, 'refund_id', v_id,
                            'status', case when v_auto then 'approved' else 'requested' end,
                            'within_auto_window', v_auto);
end $$;

-- DECIDE. Outside the automatic window a named human (or an authorised agent) approves or rejects.
create or replace function public.fn_refund_decide(
  p_refund_id bigint, p_approve boolean, p_decided_by text, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.refunds;
begin
  select * into r from public.refunds where id = p_refund_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.status not in ('requested') then
    return jsonb_build_object('ok', false, 'error', 'not_decidable', 'status', r.status);
  end if;
  if coalesce(btrim(p_decided_by),'') = '' then
    return jsonb_build_object('ok', false, 'error', 'decider_required');
  end if;

  update public.refunds
     set status = case when p_approve then 'approved' else 'rejected' end,
         decided_by = p_decided_by, decided_at = now(), decision_note = p_note
   where id = p_refund_id;

  return jsonb_build_object('ok', true, 'refund_id', p_refund_id,
                            'status', case when p_approve then 'approved' else 'rejected' end);
end $$;

-- SETTLE. Called by the Stripe webhook when charge.refunded / refund.updated arrives. Idempotent on
-- stripe_refund_id, because Stripe retries webhooks and a double-settled refund is a double refund.
create or replace function public.fn_refund_settle(
  p_stripe_refund_id text, p_status text, p_amount_fils bigint default null,
  p_payment_intent text default null, p_charge_id text default null,
  p_failure_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.refunds; v_status text;
begin
  v_status := case lower(coalesce(p_status,''))
                when 'succeeded' then 'succeeded'
                when 'failed'    then 'failed'
                when 'canceled'  then 'cancelled'
                when 'cancelled' then 'cancelled'
                else 'processing' end;

  select * into r from public.refunds where stripe_refund_id = p_stripe_refund_id;
  if found then
    if r.status = v_status then
      return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', r.status, 'idempotent', true);
    end if;
    update public.refunds
       set status = v_status,
           settled_at = case when v_status = 'succeeded' then coalesce(settled_at, now()) else settled_at end,
           failure_reason = case when v_status = 'failed' then p_failure_reason else failure_reason end
     where id = r.id;
    return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', v_status, 'idempotent', false);
  end if;

  -- Match an approved request that has no Stripe id yet, by payment intent.
  select * into r from public.refunds
   where stripe_refund_id is null and p_payment_intent is not null
     and stripe_payment_intent = p_payment_intent and status in ('approved','processing')
   order by created_at limit 1;

  if found then
    update public.refunds
       set stripe_refund_id = p_stripe_refund_id, stripe_charge_id = coalesce(p_charge_id, stripe_charge_id),
           status = v_status,
           settled_at = case when v_status = 'succeeded' then now() else settled_at end,
           failure_reason = case when v_status = 'failed' then p_failure_reason else null end
     where id = r.id;
    return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', v_status, 'matched_by', 'payment_intent');
  end if;

  -- A refund issued directly in the Stripe dashboard, with no request here. Record it rather than
  -- discard it: an unrecorded refund is exactly the money that never reconciles.
  insert into public.refunds (stripe_refund_id, stripe_payment_intent, stripe_charge_id,
                              amount_fils, reason_code, reason_note, requested_by,
                              status, settled_at, decided_by, decided_at, decision_note)
  values (p_stripe_refund_id, p_payment_intent, p_charge_id,
          coalesce(p_amount_fils, 1), 'other',
          'Issued outside QuotesDone (Stripe dashboard or API). Recorded by the webhook.',
          'stripe_webhook', v_status,
          case when v_status='succeeded' then now() end,
          'stripe_dashboard', now(), 'No in-platform request existed for this refund.')
  returning * into r;
  return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', v_status, 'matched_by', 'created_from_stripe');
end $$;

-- RECONCILIATION. What finance actually needs: settled refunds not yet tied to a ledger entry.
create or replace view public.v_refunds_unreconciled as
select r.id, r.settled_at, r.amount_fils, round(r.amount_fils/100.0, 2) as amount_aed,
       r.currency, r.reason_code, r.stripe_refund_id, r.stripe_payment_intent,
       r.inquiry_id, r.customer_id, r.decided_by
from public.refunds r
where r.status = 'succeeded' and r.reconciled_at is null
order by r.settled_at;

create or replace view public.v_refund_metrics as
select count(*) as refunds_total,
       count(*) filter (where status='requested')  as awaiting_decision,
       count(*) filter (where status='approved')   as approved_not_settled,
       count(*) filter (where status='succeeded')  as settled,
       count(*) filter (where status='failed')     as failed,
       count(*) filter (where status='rejected')   as rejected,
       count(*) filter (where within_auto_window)  as inside_auto_window,
       coalesce(round(sum(amount_fils) filter (where status='succeeded')/100.0, 2), 0) as refunded_aed,
       (select coalesce(round(sum(amount_fils)/100.0,2),0) from public.refunds where status='succeeded'
          and settled_at > now() - interval '30 days') as refunded_aed_30d,
       (select count(*) from public.v_refunds_unreconciled) as unreconciled,
       (select coalesce(jsonb_object_agg(reason_code, c), '{}'::jsonb)
          from (select reason_code, count(*) c from public.refunds where status='succeeded' group by 1) t) as by_reason
from public.refunds;

comment on view public.v_refund_metrics is
  'Payments & Revenue tile. refund rate, value, reason mix and how many settled refunds have not yet been reconciled to the ledger. unreconciled > 0 for more than a day is the signal worth alerting on.';

revoke all on function public.fn_refund_request(bigint,text,text,uuid,uuid,bigint,bigint,text,text,text) from public, anon, authenticated;
revoke all on function public.fn_refund_decide(bigint,boolean,text,text) from public, anon, authenticated;
revoke all on function public.fn_refund_settle(text,text,bigint,text,text,text) from public, anon, authenticated;
grant execute on function public.fn_refund_request(bigint,text,text,uuid,uuid,bigint,bigint,text,text,text) to service_role;
grant execute on function public.fn_refund_decide(bigint,boolean,text,text) to service_role;
grant execute on function public.fn_refund_settle(text,text,bigint,text,text,text) to service_role;
