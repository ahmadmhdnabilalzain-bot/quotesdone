-- A REFUND IS PROVED BY SILENCE, APPROVED BY THE CEO, AND PAID BY THE ACCOUNTANT.
--
-- The founder's procedure, 9 September 2026, in his words:
--
--   "the customer support agent is already connected to the channels on email and WhatsApp. So he
--    will be contacting the supplier. And if there's no response, then it's very easy because it's
--    two way communication, then as per our rules, when the amount of days, like, the limit for the
--    refund is there, he sends that to the CEO, and then the CEO checks those records and confirm.
--    So no communication means the refund is approved. And accordingly the CEO is supposed to
--    communicate with the accountant because he's responsible about all the financial stuff, and
--    the accountant would issue the refund eventually. So approval from CEO, execution from the
--    accountant always whenever it's related to money. So the accountant wouldn't be able to
--    proceed with the refund unless the CEO is aware, and he approved and confirmed that as per the
--    customer support agent, there was no response. And at the same time, the accountant is supposed
--    to generate the penalty that we have for the supplier, which should be already the terms and
--    condition where we get the three percent back from the supplier along with two fifty AED as a
--    management fee or admin fee plus nine percent annual interest on the amount."
--
-- THREE SEATS, THREE DISTINCT JOBS, AND NONE OF THEM MAY DO ANOTHER'S.
--
--   customer_support  contacts the supplier and OWNS THE RECORD OF SILENCE. It does not decide.
--   ceo               reads that record and decides. It does not move money.
--   accountant        moves the money and raises the supplier's penalty. It does not decide.
--
-- WHAT ALREADY EXISTED, AND WHAT DID NOT. `refunds`, `refund_case` and the two CEO-approval
-- triggers were already here and are good: money cannot reach 'approved' without a matching
-- `ceo_approval` row, and approvals are append-only. What did NOT exist is the thing the founder's
-- procedure actually turns on — **the evidence of silence**. There was no record anywhere that
-- support had contacted a supplier about a specific transaction, on which channel, how many times,
-- or whether anything came back. So the CEO had nothing to "check those records" against, and
-- "no communication means the refund is approved" was unenforceable: an approval could be granted
-- against a supplier who had replied twice.
--
-- THE EVIDENCE IS THE POINT, SO IT IS A TABLE AND NOT A JUDGEMENT.
-- public.supplier_response_watch holds one row per (transaction, supplier). Support appends each
-- contact attempt and stamps any inbound reply. Eligibility is then arithmetic over that row --
-- working days elapsed, attempts made, channels used, replies received -- rather than an opinion,
-- which is what lets the CEO's approval be checkable after the fact and what stops a refund being
-- approved on a supplier who did answer.
--
-- WHY WORKING DAYS AND NOT DAYS. pricing_config.refund_window_working_days is 5. A supplier who
-- goes quiet over a Friday-Saturday UAE weekend has not gone silent, and refunding against a
-- weekend would be the platform's error, not the supplier's failure.
--
-- THE PENALTY IS COMPUTED, NEVER TYPED. 3% of the job value recovered from the supplier, plus an
-- AED 250 administration fee, plus 9% simple annual interest accruing daily from the day the
-- customer was refunded until the supplier settles. Every rate is read from pricing_config so that
-- changing a business term never means editing a routine.

-- ── 1. THE BUSINESS TERMS, IN THE TABLE THAT HOLDS BUSINESS TERMS ───────────────────────────────
alter table public.pricing_config
  add column if not exists supplier_nonresponse_admin_fee_aed numeric(12,2) not null default 250.00,
  add column if not exists supplier_nonresponse_interest_apr  numeric(6,4)  not null default 0.0900,
  add column if not exists supplier_nonresponse_min_attempts  int           not null default 2,
  add column if not exists supplier_nonresponse_min_channels  int           not null default 2;

comment on column public.pricing_config.supplier_nonresponse_admin_fee_aed is
  'AED 250 administration fee charged to a supplier who never answered a customer who had paid to reveal them. Founder, 9 Sep 2026.';
comment on column public.pricing_config.supplier_nonresponse_interest_apr is
  '9% simple annual interest on the recovered amount, accruing daily from the date the customer was refunded. Founder, 9 Sep 2026.';
comment on column public.pricing_config.supplier_nonresponse_min_attempts is
  'How many contact attempts support must have made before silence counts as silence. Two, so one undelivered message is never mistaken for a refusal to answer.';
comment on column public.pricing_config.supplier_nonresponse_min_channels is
  'How many DISTINCT channels support must have tried. Two, because a supplier whose email bounces has not ignored us — WhatsApp is the second door and the founder has both connected.';

-- ── 2. THE RECORD OF SILENCE ────────────────────────────────────────────────────────────────────
create table if not exists public.supplier_response_watch (
  id                bigserial primary key,
  transaction_id    uuid        not null,
  lead_id           bigint      not null,
  opened_at         timestamptz not null default now(),
  -- every attempt support makes, appended: {at, channel, notification_id, note}
  attempts          jsonb       not null default '[]'::jsonb,
  -- the moment anything came back from the supplier, on any channel. NULL is the whole point.
  first_response_at timestamptz,
  response_channel  text,
  response_ref      text,
  closed_at         timestamptz,
  close_reason      text,
  constraint supplier_response_watch_one_per_tx unique (transaction_id)
);
comment on table public.supplier_response_watch is
  'The evidence a refund rests on: did the supplier ever answer a customer who paid to reveal them. customer_support appends attempts and stamps first_response_at; the CEO reads it and decides; the accountant pays. One row per transaction.';

create index if not exists supplier_response_watch_open_idx
  on public.supplier_response_watch (opened_at) where first_response_at is null and closed_at is null;

alter table public.supplier_response_watch enable row level security;
revoke all on public.supplier_response_watch from anon, authenticated;

-- ── 3. SUPPORT RECORDS A CONTACT ATTEMPT ────────────────────────────────────────────────────────
create or replace function public.fn_support_record_supplier_contact(
  p_transaction_id uuid, p_lead_id bigint, p_channel text,
  p_notification_id bigint default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_id bigint; v_n int;
begin
  if p_channel is null or p_channel not in ('email','whatsapp','sms','phone') then
    raise exception 'channel must be one of email, whatsapp, sms, phone (got %)', coalesce(p_channel,'null');
  end if;

  insert into public.supplier_response_watch (transaction_id, lead_id, attempts)
  values (p_transaction_id, p_lead_id, '[]'::jsonb)
  on conflict (transaction_id) do nothing;

  update public.supplier_response_watch
     set attempts = attempts || jsonb_build_object(
           'at', now(), 'channel', p_channel,
           'notification_id', p_notification_id, 'note', p_note)
   where transaction_id = p_transaction_id
   returning id, jsonb_array_length(attempts) into v_id, v_n;

  return jsonb_build_object('ok', true, 'watch_id', v_id, 'attempts', v_n, 'channel', p_channel);
end $fn$;
revoke execute on function public.fn_support_record_supplier_contact(uuid,bigint,text,bigint,text) from public;

-- ── 4. SUPPORT STAMPS A REPLY — THE ONE THING THAT STOPS A REFUND ───────────────────────────────
create or replace function public.fn_support_record_supplier_response(
  p_transaction_id uuid, p_channel text, p_ref text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_row public.supplier_response_watch;
begin
  update public.supplier_response_watch
     set first_response_at = coalesce(first_response_at, now()),
         response_channel  = coalesce(response_channel, p_channel),
         response_ref      = coalesce(response_ref, p_ref)
   where transaction_id = p_transaction_id
   returning * into v_row;

  if v_row.id is null then
    return jsonb_build_object('ok', false, 'reason', 'no watch is open for this transaction');
  end if;
  return jsonb_build_object('ok', true, 'watch_id', v_row.id,
    'first_response_at', v_row.first_response_at,
    'note', 'This transaction can no longer produce a non-response refund. The supplier answered.');
end $fn$;
revoke execute on function public.fn_support_record_supplier_response(uuid,text,text) from public;

-- ── 5. ELIGIBILITY IS ARITHMETIC, NOT AN OPINION ────────────────────────────────────────────────
-- Returns the same verdict to whoever asks: support before it escalates, the CEO before it decides,
-- the accountant before it pays. One rule, three readers, no room for three answers.
create or replace function public.fn_refund_nonresponse_eligibility(p_transaction_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare
  w public.supplier_response_watch; c public.pricing_config;
  v_wd int; v_att int; v_ch int; v_reasons text[] := '{}';
begin
  select * into w from public.supplier_response_watch where transaction_id = p_transaction_id;
  select * into c from public.pricing_config limit 1;

  if w.id is null then
    return jsonb_build_object('eligible', false, 'basis', 'no_watch',
      'detail', 'Support has not recorded contacting this supplier at all, so there is no evidence of silence to decide on.');
  end if;

  -- WORKING days between the first attempt and now: Friday and Saturday are the UAE weekend.
  select count(*) into v_wd
    from generate_series((w.opened_at at time zone 'Asia/Dubai')::date,
                         (now()      at time zone 'Asia/Dubai')::date, interval '1 day') d
   where extract(isodow from d) not in (5, 6);
  v_wd := greatest(v_wd - 1, 0);   -- the opening day itself is not an elapsed day

  select count(*), count(distinct a->>'channel')
    into v_att, v_ch
    from jsonb_array_elements(w.attempts) a;

  if w.first_response_at is not null then
    v_reasons := v_reasons || ('the supplier replied on ' || w.first_response_at::text || ' via ' || coalesce(w.response_channel,'?'));
  end if;
  if v_wd < c.refund_window_working_days then
    v_reasons := v_reasons || (v_wd || ' working day(s) have passed of the ' || c.refund_window_working_days || ' the terms allow');
  end if;
  if v_att < c.supplier_nonresponse_min_attempts then
    v_reasons := v_reasons || ('support made ' || v_att || ' attempt(s), fewer than the ' || c.supplier_nonresponse_min_attempts || ' required');
  end if;
  if v_ch < c.supplier_nonresponse_min_channels then
    v_reasons := v_reasons || ('support used ' || v_ch || ' channel(s), fewer than the ' || c.supplier_nonresponse_min_channels || ' required');
  end if;

  return jsonb_build_object(
    'eligible', array_length(v_reasons,1) is null,
    'basis', 'measured',
    'transaction_id', p_transaction_id,
    'working_days_elapsed', v_wd,
    'working_days_required', c.refund_window_working_days,
    'attempts', v_att, 'attempts_required', c.supplier_nonresponse_min_attempts,
    'channels', v_ch, 'channels_required', c.supplier_nonresponse_min_channels,
    'supplier_replied', w.first_response_at is not null,
    'first_response_at', w.first_response_at,
    'blocking_reasons', coalesce(to_jsonb(v_reasons), '[]'::jsonb),
    'evidence', w.attempts);
end $fn$;
revoke execute on function public.fn_refund_nonresponse_eligibility(uuid) from public;

-- ── 6. THE ACCOUNTANT'S PENALTY, COMPUTED FROM THE TERMS ────────────────────────────────────────
-- 3% of the job value back from the supplier + AED 250 admin + 9% simple annual interest accruing
-- daily from the refund date. Interest is returned as both the rate and the accrued figure so an
-- invoice can state how it was reached rather than asserting a total.
create or replace function public.fn_supplier_nonresponse_penalty(
  p_job_value_aed numeric, p_refunded_on date, p_as_of date default current_date)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare c public.pricing_config; v_recover numeric; v_days int; v_interest numeric;
begin
  select * into c from public.pricing_config limit 1;
  if p_job_value_aed is null or p_job_value_aed <= 0 then
    raise exception 'a penalty cannot be computed from a job value of %', coalesce(p_job_value_aed::text,'null');
  end if;

  v_recover  := round(p_job_value_aed * c.standard_reveal_rate, 2);
  v_days     := greatest((p_as_of - p_refunded_on), 0);
  v_interest := round((v_recover + c.supplier_nonresponse_admin_fee_aed)
                      * c.supplier_nonresponse_interest_apr * v_days / 365.0, 2);

  return jsonb_build_object(
    'job_value_aed', p_job_value_aed,
    'reveal_fee_recovered_aed', v_recover,
    'reveal_rate', c.standard_reveal_rate,
    'admin_fee_aed', c.supplier_nonresponse_admin_fee_aed,
    'interest_apr', c.supplier_nonresponse_interest_apr,
    'interest_days', v_days,
    'interest_aed', v_interest,
    'total_due_aed', round(v_recover + c.supplier_nonresponse_admin_fee_aed + v_interest, 2),
    'basis', 'pricing_config: reveal rate, admin fee and APR are read, never typed; interest is simple, daily, from the refund date');
end $fn$;
revoke execute on function public.fn_supplier_nonresponse_penalty(numeric,date,date) from public;

-- ── 7. THE GATE: THE CEO MAY NOT APPROVE A NON-RESPONSE REFUND AGAINST A SUPPLIER WHO ANSWERED ──
create or replace function public.fn_refund_nonresponse_needs_silence()
returns trigger language plpgsql security definer set search_path to 'public' as $fn$
declare v jsonb;
begin
  if new.decision is distinct from 'approved' then return new; end if;
  if coalesce(new.eligibility,'') is distinct from 'supplier_nonresponse' then return new; end if;

  v := public.fn_refund_nonresponse_eligibility(new.transaction_id);
  if (v->>'eligible')::boolean is not true then
    raise exception 'this refund is approved on supplier non-response, and the record does not show non-response: %',
      coalesce(v->>'blocking_reasons', v->>'detail');
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_refund_nonresponse_needs_silence() from public;

drop trigger if exists z10_refund_nonresponse_needs_silence on public.refund_case;
create trigger z10_refund_nonresponse_needs_silence
  before insert or update on public.refund_case
  for each row execute function public.fn_refund_nonresponse_needs_silence();

-- ── 8. PROVE THE WHOLE CHAIN, INSIDE A TRANSACTION THAT ABORTS ──────────────────────────────────
do $do$
declare
  v_tx uuid := gen_random_uuid(); v_lead bigint;
  e0 jsonb; e1 jsonb; e2 jsonb; e3 jsonb; p jsonb; v_blocked text := 'NOT BLOCKED';
begin
  select id into v_lead from public.leads limit 1;
  if v_lead is null then raise exception 'POSITIVE CONTROL FAILED: no lead exists to stand in as a supplier'; end if;

  -- (a) no watch at all -> not eligible, and it says why rather than returning a bare false
  e0 := public.fn_refund_nonresponse_eligibility(v_tx);
  if (e0->>'eligible')::boolean then raise exception 'eligible with no evidence at all'; end if;

  -- (b) one attempt, one channel, today -> still not eligible, three reasons
  perform public.fn_support_record_supplier_contact(v_tx, v_lead, 'email', null, 'first contact');
  e1 := public.fn_refund_nonresponse_eligibility(v_tx);
  if (e1->>'eligible')::boolean then raise exception 'eligible after a single email on day zero'; end if;

  -- (c) backdate the watch past the window and add a second channel -> eligible
  perform public.fn_support_record_supplier_contact(v_tx, v_lead, 'whatsapp', null, 'second contact');
  update public.supplier_response_watch set opened_at = now() - interval '21 days' where transaction_id = v_tx;
  e2 := public.fn_refund_nonresponse_eligibility(v_tx);
  if not (e2->>'eligible')::boolean then
    raise exception 'NOT eligible after 2 channels and 21 days: %', e2->>'blocking_reasons';
  end if;

  -- (d) THE NEGATIVE CONTROL THAT MATTERS: the supplier answers, and eligibility must flip back
  perform public.fn_support_record_supplier_response(v_tx, 'whatsapp', 'SM123');
  e3 := public.fn_refund_nonresponse_eligibility(v_tx);
  if (e3->>'eligible')::boolean then
    raise exception 'STILL eligible after the supplier replied — silence is not being checked';
  end if;

  -- (e) and the trigger must refuse a CEO approval built on that answered case
  begin
    insert into public.refund_case (transaction_id, state, eligibility, decision, decided_by, amount_aed, currency)
    values (v_tx, 'ceo_authorized', 'supplier_nonresponse', 'approved', 'ceo', 100, 'AED');
  exception when others then v_blocked := sqlerrm;
  end;
  if v_blocked = 'NOT BLOCKED' then
    raise exception 'the CEO was allowed to approve a non-response refund against a supplier who replied';
  end if;

  -- (f) the penalty arithmetic
  p := public.fn_supplier_nonresponse_penalty(100000, current_date - 30);

  -- THE PROOF CLEANS UP AFTER ITSELF rather than aborting the transaction. The first version ended
  -- in `raise exception`, which is the estate's usual way to probe a write without leaving one --
  -- and here it rolled the DDL back with it, so the file proved a chain it had just un-built. The
  -- subject is a synthetic uuid that matches no real transaction, so deleting it removes exactly
  -- what this block created and nothing else.
  delete from public.refund_case where transaction_id = v_tx;
  delete from public.supplier_response_watch where transaction_id = v_tx;
  if exists (select 1 from public.supplier_response_watch where transaction_id = v_tx) then
    raise exception 'the proof left its own test row behind';
  end if;

  raise notice 'CHAIN PROVED. no evidence -> %, one email on day zero -> %, two channels after 21 days -> %, after the supplier replied -> %. The CEO was refused: %. Penalty on an AED 100,000 job refunded 30 days ago: recover % + admin % + interest % over % days = TOTAL % AED.',
    e0->>'eligible', e1->>'eligible', e2->>'eligible', e3->>'eligible', left(v_blocked, 120),
    p->>'reveal_fee_recovered_aed', p->>'admin_fee_aed', p->>'interest_aed', p->>'interest_days', p->>'total_due_aed';
end
$do$;
