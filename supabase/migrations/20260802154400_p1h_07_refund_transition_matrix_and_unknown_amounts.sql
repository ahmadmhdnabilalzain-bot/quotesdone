-- FINAL ACTIONS 2 AND 3 - AN EXPLICIT TRANSITION MATRIX, AND NO INVENTED MONEY
--
-- (3) WHY THE RANK WAS THE WRONG SHAPE. A numeric rank encodes "later beats earlier" and nothing
-- else. It cannot express that a failed refund does not later succeed (Stripe issues a NEW refund
-- id for a retry), nor that cancelled is terminal, and every future reader has to reverse-engineer
-- the policy from four integers. The permitted transitions are now data: one row per pair, with the
-- reason written down. Anything not listed as allowed is refused and recorded - which is the same
-- fail-closed rule the action classifier uses, applied to money.
--
-- (2) WHY THE 1-FILS PLACEHOLDER WAS INDEFENSIBLE. It put a fabricated financial amount into the
-- ledger. A note beside it does not undo that: totals summed it, the GL would post it, and any
-- report that did not happen to read the note was wrong by a real number. Unknown is now
-- represented as unknown - NULL - and excluded from every total. The webhook first tries to answer
-- the question properly by asking Stripe for the refund by id; only if that fails does the row stay
-- unknown, and it stays in the reconciliation queue until a human or a later event resolves it.

-- ---------------------------------------------------------------------------------------------
-- 2a. amount_fils may be unknown, and says where it came from.
-- ---------------------------------------------------------------------------------------------
alter table public.refunds drop constraint if exists refunds_amount_fils_check;
alter table public.refunds add constraint refunds_amount_fils_check
  check (amount_fils is null or amount_fils > 0);

alter table public.refunds add column if not exists amount_source text;
alter table public.refunds drop constraint if exists refunds_amount_source_check;
alter table public.refunds add constraint refunds_amount_source_check
  check (amount_source is null or amount_source in ('in_platform_request','webhook_event','stripe_api','manual','unknown'));

-- A settled refund with no amount is not a valid financial record. It is allowed to exist - losing
-- it would be worse - but it can never be silently complete.
alter table public.refunds drop constraint if exists refunds_settled_needs_amount;
alter table public.refunds add constraint refunds_settled_needs_amount
  check (status <> 'succeeded' or amount_fils is not null or reconciliation_note is not null);

update public.refunds set amount_source = 'in_platform_request' where amount_source is null and amount_fils is not null;

-- ---------------------------------------------------------------------------------------------
-- 2b. Quarantine, for events that cannot be turned into a refund row at all.
-- ---------------------------------------------------------------------------------------------
create table if not exists public.refund_event_quarantine (
  id                bigserial primary key,
  stripe_refund_id  text,
  stripe_event_id   text,
  event_type        text,
  reason            text not null,
  payload           jsonb,
  created_at        timestamptz not null default now(),
  resolved_at       timestamptz,
  resolved_by       text,
  resolution_note   text
);
create index if not exists refund_event_quarantine_open_idx
  on public.refund_event_quarantine (resolved_at, created_at);
alter table public.refund_event_quarantine enable row level security;
comment on table public.refund_event_quarantine is
  'Refund events that could not be recorded as a refund - no id, an illegal status transition, or an amount that could not be established. Nothing is ever dropped; it waits here to be resolved.';

create or replace function public.fn_refund_quarantine(
  p_stripe_refund_id text, p_event_type text, p_reason text, p_payload jsonb default null,
  p_stripe_event_id text default null)
returns bigint language sql security definer set search_path to 'public' as $fn$
  insert into public.refund_event_quarantine (stripe_refund_id, stripe_event_id, event_type, reason, payload)
  values (nullif(btrim(coalesce(p_stripe_refund_id,'')),''), nullif(btrim(coalesce(p_stripe_event_id,'')),''),
          p_event_type, p_reason, p_payload)
  returning id;
$fn$;

-- ---------------------------------------------------------------------------------------------
-- 3. The transition matrix.
-- ---------------------------------------------------------------------------------------------
create table if not exists public.refund_status_transition (
  from_status text not null,
  to_status   text not null,
  allowed     boolean not null,
  note        text,
  primary key (from_status, to_status)
);
alter table public.refund_status_transition enable row level security;

delete from public.refund_status_transition;
insert into public.refund_status_transition (from_status, to_status, allowed, note) values
  -- In-platform states, before Stripe has said anything.
  ('requested','processing',true ,'Stripe accepted the refund.'),
  ('requested','succeeded' ,true ,'Fast settlement; Stripe confirmed before we saw the pending event.'),
  ('requested','failed'    ,true ,'Stripe refused it outright.'),
  ('requested','cancelled' ,true ,'Withdrawn before Stripe acted.'),
  ('approved' ,'processing',true ,'Normal path: approved here, now in flight at Stripe.'),
  ('approved' ,'succeeded' ,true ,'Fast settlement, or refund.updated arrived before refund.created.'),
  ('approved' ,'failed'    ,true ,'Stripe refused it.'),
  ('approved' ,'cancelled' ,true ,'Cancelled before Stripe settled.'),
  -- In flight.
  ('processing','succeeded',true ,'The money moved.'),
  ('processing','failed'   ,true ,'Stripe could not complete it.'),
  ('processing','cancelled',true ,'Cancelled while in flight.'),
  ('processing','requested',false,'Backwards. A late refund.created after we already knew it was in flight.'),
  ('processing','approved' ,false,'Backwards.'),
  -- Terminal states. These are the whole point of the matrix.
  ('succeeded','processing',false,'OUT OF ORDER. A late refund.created after settlement. Money that has moved does not go back in flight.'),
  ('succeeded','requested' ,false,'Out of order.'),
  ('succeeded','approved'  ,false,'Out of order.'),
  ('succeeded','failed'    ,false,'CONTRADICTORY. Stripe does not fail a refund it has already settled. Quarantine and investigate.'),
  ('succeeded','cancelled' ,false,'Contradictory: a settled refund cannot be cancelled.'),
  ('failed','processing'   ,false,'Out of order. Stripe issues a NEW refund id to retry; the failed one stays failed.'),
  ('failed','requested'    ,false,'Out of order.'),
  ('failed','approved'     ,false,'Out of order.'),
  ('failed','succeeded'    ,false,'Stripe issues a new refund id for a retry, so this should never arrive. If it does, quarantine it rather than quietly booking a refund twice.'),
  ('failed','cancelled'    ,false,'Terminal.'),
  ('cancelled','processing',false,'Terminal.'),
  ('cancelled','succeeded' ,false,'A cancelled refund that settles means two systems disagree. Quarantine it.'),
  ('cancelled','failed'    ,false,'Terminal.'),
  ('cancelled','requested' ,false,'Out of order.'),
  ('cancelled','approved'  ,false,'Out of order.'),
  -- Nothing moves out of rejected via a webhook: rejection is a decision made here, and Stripe was
  -- never asked. A Stripe event for a rejected refund means someone refunded it outside the
  -- platform after we said no - which is exactly the case worth quarantining rather than absorbing.
  ('rejected','processing' ,false,'Refunded outside the platform after an in-platform rejection.'),
  ('rejected','succeeded'  ,false,'Refunded outside the platform after an in-platform rejection. Investigate.'),
  ('rejected','failed'     ,false,'Unexpected.'),
  ('rejected','cancelled'  ,false,'Unexpected.');

comment on table public.refund_status_transition is
  'Every permitted refund status change, with its reason. A transition absent from this table, or present with allowed=false, is refused by fn_refund_settle and the event is quarantined. succeeded, failed and cancelled are terminal.';

create or replace function public.fn_refund_transition_allowed(p_from text, p_to text)
returns boolean language sql stable security definer set search_path to 'public' as $fn$
  select coalesce((select allowed from public.refund_status_transition
                    where from_status = p_from and to_status = p_to), false);
$fn$;

-- ---------------------------------------------------------------------------------------------
-- The settlement function, rebuilt on both.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_refund_settle(
  p_stripe_refund_id text, p_status text, p_amount_fils bigint default null,
  p_payment_intent text default null, p_charge_id text default null, p_failure_reason text default null,
  p_amount_source text default 'webhook_event', p_stripe_event_id text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare r public.refunds; v_status text; v_amount bigint; v_src text; v_q bigint;
begin
  if coalesce(btrim(p_stripe_refund_id),'') = '' then
    v_q := public.fn_refund_quarantine(null, 'refund', 'event carried no refund id',
             jsonb_build_object('status', p_status, 'payment_intent', p_payment_intent), p_stripe_event_id);
    return jsonb_build_object('ok', false, 'error', 'stripe_refund_id_required', 'quarantined', v_q);
  end if;

  v_status := case lower(coalesce(p_status,''))
                when 'succeeded' then 'succeeded' when 'failed' then 'failed'
                when 'canceled' then 'cancelled'  when 'cancelled' then 'cancelled'
                else 'processing' end;
  v_amount := nullif(coalesce(p_amount_fils, 0), 0);
  v_src    := case when v_amount is null then null else coalesce(p_amount_source, 'webhook_event') end;

  select * into r from public.refunds where stripe_refund_id = p_stripe_refund_id for update;

  if not found then
    select * into r from public.refunds
     where stripe_refund_id is null and p_payment_intent is not null
       and stripe_payment_intent = p_payment_intent and status in ('approved','processing','requested')
     order by created_at limit 1 for update;

    if found then
      update public.refunds set stripe_refund_id = p_stripe_refund_id,
             stripe_charge_id = coalesce(p_charge_id, stripe_charge_id) where id = r.id;
    else
      -- Issued outside the platform. Recorded with whatever is actually known, and NOTHING invented:
      -- if the amount is unknown it stays NULL and the row is marked unreconciled.
      insert into public.refunds (stripe_refund_id, stripe_payment_intent, stripe_charge_id,
                                  amount_fils, amount_source, reason_code, reason_note, requested_by, status,
                                  decided_by, decided_at, decision_note, reconciliation_note)
      values (p_stripe_refund_id, p_payment_intent, p_charge_id, v_amount,
              coalesce(v_src, 'unknown'), 'other',
              'Issued outside QuotesDone (Stripe dashboard or API). Recorded by the webhook.',
              'stripe_webhook', 'processing', 'stripe_dashboard', now(),
              'No in-platform request existed for this refund.',
              case when v_amount is null
                   then 'AMOUNT UNKNOWN - the event carried none and Stripe could not be read. Excluded from all financial totals until resolved.'
                   else null end)
      returning * into r;

      if v_amount is null then
        perform public.fn_refund_quarantine(p_stripe_refund_id, 'refund',
          'amount unknown: absent from the event and not retrievable from Stripe',
          jsonb_build_object('status', v_status, 'payment_intent', p_payment_intent, 'refund_row', r.id),
          p_stripe_event_id);
      end if;

      return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', r.status, 'applied', true,
                                'created', true, 'amount_known', v_amount is not null);
    end if;
  end if;

  -- Duplicate delivery: same state twice. Cheap, silent, correct - but still take the chance to fill
  -- in an amount we did not have before.
  if r.status = v_status then
    if r.amount_fils is null and v_amount is not null then
      update public.refunds
         set amount_fils = v_amount, amount_source = v_src,
             reconciliation_note = 'amount resolved from a later ' || coalesce(p_amount_source,'event'),
             updated_at = now()
       where id = r.id;
      return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', r.status,
                                'idempotent', true, 'applied', false, 'amount_resolved', true);
    end if;
    return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', r.status,
                              'idempotent', true, 'applied', false);
  end if;

  -- The matrix decides. Not a rank, not an ordering heuristic - a declared policy with a reason
  -- attached to every refusal.
  if not public.fn_refund_transition_allowed(r.status, v_status) then
    v_q := public.fn_refund_quarantine(p_stripe_refund_id, 'refund',
      'transition not permitted: ' || r.status || ' -> ' || v_status || '. '
      || coalesce((select note from public.refund_status_transition
                    where from_status = r.status and to_status = v_status), 'no rule declared for this pair'),
      jsonb_build_object('refund_row', r.id, 'from', r.status, 'to', v_status,
                         'amount_fils', p_amount_fils, 'payment_intent', p_payment_intent),
      p_stripe_event_id);
    update public.refunds
       set reconciliation_note = left(coalesce(reconciliation_note || ' | ', '')
           || 'refused ' || r.status || '->' || v_status || ' at ' || to_char(now(),'YYYY-MM-DD HH24:MI'), 500),
           updated_at = now()
     where id = r.id;
    return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', r.status, 'applied', false,
                              'refused_transition', r.status || '->' || v_status, 'quarantined', v_q);
  end if;

  update public.refunds
     set status = v_status,
         amount_fils   = coalesce(v_amount, amount_fils),
         amount_source = case when v_amount is not null then v_src else amount_source end,
         stripe_charge_id = coalesce(p_charge_id, stripe_charge_id),
         stripe_payment_intent = coalesce(p_payment_intent, stripe_payment_intent),
         settled_at = case when v_status = 'succeeded' then coalesce(settled_at, now()) else settled_at end,
         failure_reason = case when v_status = 'failed' then p_failure_reason else failure_reason end,
         reconciliation_note = case
             when v_status = 'succeeded' and coalesce(v_amount, amount_fils) is null
             then 'AMOUNT UNKNOWN on a settled refund - excluded from all financial totals until resolved.'
             else reconciliation_note end,
         updated_at = now()
   where id = r.id;

  if r.transaction_id is not null then
    update public.transactions
       set refund_status = v_status, refund_stripe_id = p_stripe_refund_id,
           refund_amount_aed = case when v_amount is not null then round(v_amount/100.0, 2) else refund_amount_aed end,
           refund_confirmed_at = case when v_status = 'succeeded' then coalesce(refund_confirmed_at, now())
                                      else refund_confirmed_at end
     where id = r.transaction_id;
  end if;

  return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', v_status, 'applied', true,
                            'amount_known', coalesce(v_amount, r.amount_fils) is not null);
end $fn$;

drop function if exists public.fn_refund_status_rank(text);

revoke all on function public.fn_refund_settle(text, text, bigint, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.fn_refund_transition_allowed(text, text) from public, anon, authenticated;
revoke all on function public.fn_refund_quarantine(text, text, text, jsonb, text) from public, anon, authenticated;
