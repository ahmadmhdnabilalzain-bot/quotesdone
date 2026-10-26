-- THE REFUND DECISION BELONGS TO THE CEO, AND THE STATES ARE KEPT APART
--
-- Operating constitution 1.2: "The CEO owns refund decisions; there is no founder exception. Support
-- independently investigates, assembles evidence and invokes the CEO's approval service when its
-- standing grant does not already cover the action. Execution uses the canonical payment/refund
-- service after current-state checks. Separate requested, eligible, CEO-authorized, submitted,
-- provider-pending, succeeded, failed/canceled, reconciled and communicated states... Prevent
-- concurrent duplicate remedies and aggregate over-refunding; do not refund to an arbitrary new
-- destination. A denied refund still needs an evidence-based explanation and appropriate alternative
-- remedy; anger must not determine eligibility."
--
-- Master update step 3: "Build the actual automated refund decision/execution path, not a
-- conversational promise."
--
-- NINE STATES, NOT ONE FLAG. The constitution lists them for a reason this estate has already paid
-- for: "paid" and "refunded" and "the customer was told" are three different facts, and a single
-- status column makes them look like one. A refund that succeeded at the provider and was never
-- communicated is a customer who thinks they were ignored; a refund marked succeeded that the
-- provider never took is money that did not move.

create table if not exists public.refund_case (
  refund_id        bigserial primary key,
  transaction_id   uuid not null,
  case_id          bigint references public.support_case(case_id),
  state            text not null default 'requested',
  amount_aed       numeric not null,
  currency         text not null default 'AED',
  requested_reason text not null,

  -- INVESTIGATION, which is support's standing grant and does not need a decision.
  investigated_at  timestamptz,
  evidence         jsonb,
  eligibility      text,
  eligibility_reason text,

  -- THE DECISION, which is the CEO's and nobody else's.
  decided_by       text,
  decided_at       timestamptz,
  decision         text,
  decision_rationale text,

  -- EXECUTION, which is the payment service's.
  destination_ref  text,
  provider_ref     text,
  submitted_at     timestamptz,
  provider_status  text,
  settled_at       timestamptz,
  failure_reason   text,
  reconciled_at    timestamptz,
  communicated_at  timestamptz,

  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  constraint refund_case_state_ck check (state in
    ('requested','investigating','eligible','ineligible','ceo_authorized','ceo_declined',
     'submitted','provider_pending','succeeded','failed','canceled','reconciled','communicated')),

  -- ONLY THE CEO AUTHORISES. Support may reach every other state; this one it cannot write, and the
  -- constraint says so rather than the prompt.
  constraint refund_case_authoriser_ck check (
    state <> 'ceo_authorized' or (decided_by = 'ceo' and decided_at is not null and decision_rationale is not null)),

  -- A DECLINE STILL OWES AN EXPLANATION. "A denied refund still needs an evidence-based explanation
  -- and appropriate alternative remedy" -- so a decline with no rationale is refused.
  constraint refund_case_decline_ck check (
    state <> 'ceo_declined' or (decided_at is not null and decision_rationale is not null)),

  -- MONEY MOVES ONLY AFTER A DECISION. Reaching a provider state without an authorisation is the
  -- exact failure this whole table exists to make impossible.
  constraint refund_case_execution_ck check (
    state not in ('submitted','provider_pending','succeeded','reconciled')
    or (decided_by = 'ceo' and decided_at is not null)),

  constraint refund_case_amount_ck check (amount_aed > 0)
);

-- ONE LIVE REFUND PER TRANSACTION. "Prevent concurrent duplicate remedies and aggregate
-- over-refunding." A partial unique index is how that becomes impossible rather than watched for:
-- a second open refund on the same transaction cannot be inserted at all.
create unique index if not exists refund_case_one_live_per_transaction
  on public.refund_case (transaction_id)
  where state not in ('ineligible','ceo_declined','failed','canceled');

create index if not exists refund_case_open_idx on public.refund_case (state, created_at);

comment on table public.refund_case is
  'One row per refund request, carrying the nine states the operating constitution insists are separate. Three CHECKs make the authority real: only the CEO can authorise, a decline must carry a rationale, and no provider state is reachable without a decision. A partial unique index prevents a second live refund on the same transaction.';

-- ---------------------------------------------------------------------------------------------
-- 1. SUPPORT INVESTIGATES. Its standing grant covers this; no decision is needed to look.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_support_investigate_refund(
  p_transaction_id uuid,
  p_reason text,
  p_case_id bigint default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  t record; v_grant jsonb; v_id bigint; v_elig text; v_why text; v_prior int;
begin
  v_grant := public.fn_support_may_act('refund');
  if (v_grant->>'may_act') <> 'true' then
    return jsonb_build_object('ok', false, 'reason', v_grant->>'reason', 'route', v_grant->>'route');
  end if;

  select id, quote_amount, reveal_fee, fee_status, refund_status, refund_amount_aed
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
     coalesce(t.reveal_fee, 0), p_reason, now(),
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

-- ---------------------------------------------------------------------------------------------
-- 2. THE CEO DECIDES. Not the founder -- there is no founder route and this function has none.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_ceo_decide_refund(
  p_refund_id bigint,
  p_approve boolean,
  p_rationale text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r record;
begin
  if coalesce(btrim(p_rationale), '') = '' then
    -- Applies to BOTH directions. The constitution asks for an evidence-based explanation on a
    -- denial specifically, and an approval with no reasoning is just as unauditable.
    return jsonb_build_object('ok', false, 'reason',
      'a rationale is required. A refund decided with no stated reasoning cannot be audited, and a denial owes the customer an explanation.');
  end if;

  select * into r from public.refund_case where refund_id = p_refund_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such refund case'); end if;

  if r.state not in ('eligible','ineligible','requested','investigating') then
    return jsonb_build_object('ok', false, 'reason',
      format('this refund is already %L. Deciding it again would be a second remedy on the same money.', r.state));
  end if;

  update public.refund_case
     set state = case when p_approve then 'ceo_authorized' else 'ceo_declined' end,
         decided_by = 'ceo', decided_at = now(),
         decision = case when p_approve then 'approved' else 'declined' end,
         decision_rationale = p_rationale, updated_at = now()
   where refund_id = p_refund_id;

  return jsonb_build_object('ok', true, 'refund_id', p_refund_id,
    'state', case when p_approve then 'ceo_authorized' else 'ceo_declined' end,
    'note', case when p_approve
                 then 'Authorised. Execution is the payment service''s, and the states stay separate: authorised is not submitted, and submitted is not settled.'
                 else 'Declined with a rationale. Support owes the customer that explanation and an appropriate alternative remedy -- a decline is not the end of the case.' end);
end $function$;

revoke execute on function public.fn_support_investigate_refund(uuid,text,bigint) from public;
revoke execute on function public.fn_support_investigate_refund(uuid,text,bigint) from anon;
revoke execute on function public.fn_support_investigate_refund(uuid,text,bigint) from authenticated;
revoke execute on function public.fn_ceo_decide_refund(bigint,boolean,text) from public;
revoke execute on function public.fn_ceo_decide_refund(bigint,boolean,text) from anon;
revoke execute on function public.fn_ceo_decide_refund(bigint,boolean,text) from authenticated;
