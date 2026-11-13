-- Seat: sales_engineer. Assigned: sales_engineer (company-workflow fix round W2, 13 Nov 2026; founder_instruction 1685, 1688).
--
-- THE FOUNDER (1685): "Is the sales engineer aware that the customer paid and now he closed this project totally?"
-- (1688): "It's never like this agent is done with this task, he just sends an output and he doesn't know what happens after
-- that. ... we need the judgment, the logic, the reasonability."
--
-- MEASURED on origin/main 2cef71f27 (workflow audit of 13 Nov 2026, scratchpad REPORT.md, and the production mirror):
--   * reveal.paid (accountant -> sales_engineer, handler fn_sales_engineer_acts_on_handoff) sends the receipt and the chosen
--     supplier's notice, and nothing else. inquiries.status becomes 'revealed' (reveal_sale.ts markRevealed); outcome,
--     pipeline_stage and completed_at stay NULL (production: 3 inquiries, outcome NULL x3, pipeline_stage NULL x3).
--   * fn_sales_engineer_tells_losing_suppliers runs only on a hire, so the suppliers who were not chosen hear nothing at the
--     payment and nothing ever if the customer never presses Hire or answers "yes".
--   * nobody owns "did the two parties connect"; the day-3 / day-14 "did you hire?" (fn_customer_support_followup_tick) and
--     the review ask exist, but no row says who owns each, when it is due, or how it ended.
--   * refund.paid reaches the sales engineer as a customer message only: the request it belongs to is never re-opened.
--
-- WHAT THIS FILE BUILDS (each step says whether it is CODE or the seat's MODEL judgement):
--   1. CODE, instant, inside the payment's own transaction: the reveal.paid handler becomes
--      fn_sales_engineer_acts_on_money_handoff, which runs fn_sales_engineer_acts_on_handoff UNCHANGED (the receipt and the
--      chosen supplier's notice are agent W1's; this file does not touch them) and then fn_sales_engineer_closes_on_reveal:
--        - the request records the sale with the existing vocabulary (crm_stages 'revealed'; outcome 'revealed' until a
--          hire writes 'hired'; status 'closed' = no further reveal, which _shared/reveal_guard.ts canReveal already refuses);
--        - the code default: no other live quotation -> CLOSED now; otherwise OPEN FOR MORE until the refund window ends
--          (transactions.refund_deadline: one date the customer is already given), then closed by the hourly duty;
--        - every supplier who quoted and was not revealed is told once per event, in English (suppliers always English),
--          anonymously (platform values only: trade, emirate, request number, a date; no customer text, no name, no price);
--        - the follow-up rows: connect_check (day 1, sales_engineer), hire_check (day 3 / day 14, customer_support),
--          and at a hire review_request (customer_support), each with due and escalation times and an outcome written back;
--        - public.request_reveal_outcome: the one record the accountant (sender), the CEO and the portals read;
--          company_event 'request.reveal_outcome' / 'request.closed' carry the same facts into the stream.
--   2. MODEL (the seat's existing path: fn_reason_hold -> resilience_ping replayHeld -> think() -> fn_reason_held_resolve ->
--      fn_reason_apply_sales_engineer__reveal_paid): when the request stayed open for more, the sales engineer is asked ONE
--      lean question with the whole request in front of it (quotes received, which was chosen, whether the comparison
--      recommended it, how many are still live, the open-until date): close now, or keep open. One decide call (lean, no
--      plan call, no verify), on the seat's easy route. Demo traffic is never sent to a model (fn_reason_subject_is_fixture);
--      a question the model never answers is marked so by the duty and the code default stands, saying why.
--   3. CODE, the loop back: refund.paid re-opens the request (status back to 'revealed', open for 14 days) and records it.
--      Terms of Service v11 clause 5 and Refund Policy v1.9 section 3 say nothing about the customer's access ending when a
--      non-response refund is paid, so the supplier is NOT told that the customer's access ended (see the record's reason).
--   4. A guard: a repeat delivery of the same sale (reveal_sale.ts sameOrSecond -> markRevealed, agent W1's file) writes
--      status 'revealed' over any status it does not list; trg_a_closed_request_stays_closed keeps a closed request closed
--      unless this file's own reopen asks (qd.reopen_request). W1 is asked to add 'closed' to markRevealed's list as well.
--
-- NOT CHANGED: fn_sales_engineer_acts_on_handoff, fn_sales_engineer_tells_losing_suppliers (the hire's notice), the receipt
-- wording, the refund ladder, the books. Prevented by: scripts/it/a_paid_reveal_is_known_to_every_seat_with_a_step.gaps.mjs
-- (GAP 8, 9, 10 judged on a rehearsal of this file), scripts/checks/a_paid_reveal_closes_the_request.test.mjs and
-- this file's _probe.sql. Pending until the release applies it: scripts/sql/pending/<this name>.txt

-- ── 0. the record and the follow-up rows ───────────────────────────────────────────────────────────────────────────────────
alter table public.inquiries add column if not exists reveal_open_until timestamptz;
comment on column public.inquiries.reveal_open_until is
  'sales_engineer: after a paid reveal, the date until which the customer may still reveal another quotation on this request; NULL when closed or never revealed (a_paid_reveal_closes_the_request_and_everyone_on_it_is_told.sql)';

create table if not exists public.request_reveal_outcome (
  transaction_id uuid primary key references public.transactions(id) on delete cascade,
  inquiry_id uuid not null references public.inquiries(id) on delete cascade,
  quote_id uuid not null,
  supplier_id bigint,
  revealed_at timestamptz not null,
  quotes_received integer not null default 0,
  other_live_quotes integer not null default 0,
  chosen_was_recommended boolean,
  state text not null check (state in ('open_for_more', 'closed', 'reopened')),
  open_until timestamptz,
  decided_by text not null check (decided_by in ('code_default', 'model')),
  decision_note text not null,
  held_question_id bigint,
  model text,
  model_status text not null,
  unchosen_told jsonb not null default '[]'::jsonb,
  closed_at timestamptz,
  closed_by text,
  closed_reason text,
  reopened_at timestamptz,
  reopen_reason text,
  handoff_id bigint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists request_reveal_outcome_inquiry_idx on public.request_reveal_outcome (inquiry_id);
create index if not exists request_reveal_outcome_open_idx on public.request_reveal_outcome (open_until) where state = 'open_for_more';
alter table public.request_reveal_outcome enable row level security;
drop policy if exists request_reveal_outcome_service_role_only on public.request_reveal_outcome;
create policy request_reveal_outcome_service_role_only on public.request_reveal_outcome
  as permissive for all to public using (false) with check (false);
revoke all on public.request_reveal_outcome from anon, authenticated;
comment on table public.request_reveal_outcome is
  'sales_engineer: one row per paid reveal: whether the request closed or stayed open for more (and until when), who decided (code default or the model), what the unchosen suppliers were told, and the close or re-open. Read by the accountant (the reveal.paid sender), the CEO and the portals.';

create table if not exists public.reveal_followup (
  id bigint generated always as identity primary key,
  transaction_id uuid not null references public.transactions(id) on delete cascade,
  kind text not null check (kind in ('connect_check', 'hire_check', 'review_request')),
  owner_seat text not null check (owner_seat in ('sales_engineer', 'customer_support')),
  due_at timestamptz not null,
  escalate_at timestamptz not null,
  closed_at timestamptz,
  outcome text,
  escalated_at timestamptz,
  escalation jsonb,
  created_at timestamptz not null default now(),
  unique (transaction_id, kind)
);
create index if not exists reveal_followup_open_idx on public.reveal_followup (due_at) where closed_at is null;
alter table public.reveal_followup enable row level security;
drop policy if exists reveal_followup_service_role_only on public.reveal_followup;
create policy reveal_followup_service_role_only on public.reveal_followup
  as permissive for all to public using (false) with check (false);
revoke all on public.reveal_followup from anon, authenticated;
comment on table public.reveal_followup is
  'sales_engineer: who owns each step after a paid reveal (connect_check day 1, hire_check day 3/14, review_request after a hire), when it is due, when it escalates, and how it ended.';

-- ── 1. the unchosen suppliers are told (CODE) ──────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_sales_engineer_tells_unchosen_suppliers(p_inquiry uuid, p_event text, p_open_until timestamptz)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare i public.inquiries; c public.customers; v_fx boolean; l record; v_job text; v_why text; v_d jsonb; v_key text;
  v_type text; v_subject text; v_body text; v_until text; v_out jsonb := '[]'::jsonb;
begin
  if p_event not in ('reveal_open', 'closed') then raise exception 'event is reveal_open or closed, not %', p_event; end if;
  select * into i from public.inquiries where id = p_inquiry;
  if not found then return v_out; end if;
  select * into c from public.customers where id = i.customer_id;
  v_fx := coalesce(public.fn_seat_clock_customer_is_fixture(c), false);
  -- platform values only: SQL has no identity scrubber, so nothing the customer wrote goes in (as fn_sales_engineer_tells_losing_suppliers)
  v_job := 'the ' || coalesce(public.fn_trade_label(i.category, 'en'), 'job') || coalesce(' job in ' || nullif(btrim(i.emirate), ''), ' job')
           || ' (request ' || coalesce(i.rfq_no::text, '-') || ')';
  v_until := to_char(p_open_until at time zone 'Asia/Dubai', 'DD Mon YYYY');
  if p_event = 'reveal_open' then
    v_type := 'quote_not_selected';
    v_subject := 'Update on a request you quoted (request ' || coalesce(i.rfq_no::text, '-') || ') — QuotesDone';
    v_body := 'Thank you for your quotation on ' || v_job || '. The customer has chosen to open another supplier''s quotation. '
      || 'Your quotation stays visible to the customer' || coalesce(' until ' || v_until, '')
      || ', and the customer may still choose to reveal it until then. Nothing further is needed from you. '
      || 'We will write again when the request closes.';
  else
    v_type := 'request_closed';
    v_subject := 'A request you quoted is closed (request ' || coalesce(i.rfq_no::text, '-') || ') — QuotesDone';
    v_body := 'Thank you for your quotation on ' || v_job || '. The request is now closed: the customer went ahead with another '
      || 'supplier''s quotation, so yours will not be revealed on this request. Nothing further is needed from you. '
      || 'We will keep matching you to requests in your trade.';
  end if;
  for l in select le.id, coalesce(public.fn_supplier_address(le.claimed_by, le.email), '') as to_email
             from (select distinct q.supplier_id from public.quotes q
                    where q.inquiry_id = p_inquiry and q.supplier_id is not null
                      and coalesce(q.status, '') not in ('draft', 'withdrawn')
                      -- a supplier the customer paid to reveal on this request is not "unchosen"
                      and not exists (select 1 from public.transactions t
                                       where t.inquiry_id = p_inquiry and t.supplier_id = q.supplier_id and t.fee_status = 'paid')) x
             join public.leads le on le.id = x.supplier_id
            where not coalesce(le.banned, false) and not public.fn_is_sanctioned_lead(le.id) loop
    -- ONE MESSAGE PER SUPPLIER PER EVENT, keyed on the request (a second reveal on the same request tells nobody twice)
    v_key := v_type || ':' || p_inquiry || ':' || l.id;
    if exists (select 1 from public.notifications n where n.dedupe_key = v_key)
       or exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'customer_support'
                   and a.target_id = 'delivery.request:' || v_key) then
      v_out := v_out || jsonb_build_array(jsonb_build_object('lead_id', l.id, 'event', p_event, 'status', 'already_told'));
      continue;
    end if;
    v_why := public.fn_seat_clock_refusal(v_fx, l.to_email, v_type);
    if v_why is not null then
      v_out := v_out || jsonb_build_array(jsonb_build_object('lead_id', l.id, 'event', p_event, 'status', 'not_told', 'why', v_why));
      continue;
    end if;
    v_d := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', v_type, 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', l.to_email, 'to_role', 'supplier',
      'lead_id', l.id, 'inquiry_id', p_inquiry, 'lang', 'en', 'subject', v_subject, 'body', v_body, 'dedupe_key', v_key)));
    v_out := v_out || jsonb_build_array(jsonb_build_object('lead_id', l.id, 'event', p_event,
      'status', coalesce(v_d->0->>'status', 'unknown'), 'handoff_id', v_d->0->'handoff_id', 'notification_id', v_d->0->'notification_id'));
  end loop;
  return v_out;
end $fn$;
revoke execute on function public.fn_sales_engineer_tells_unchosen_suppliers(uuid, text, timestamptz) from public, anon, authenticated;

-- ── 2. closing a request (CODE; called by the reveal, the model's answer and the hourly duty) ─────────────────────────────
create or replace function public.fn_sales_engineer_closes_request(p_inquiry uuid, p_by text, p_reason text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare i public.inquiries; v_told jsonb := '[]'::jsonb; v_tx text;
begin
  select * into i from public.inquiries where id = p_inquiry for update;
  if not found then return jsonb_build_object('closed', false, 'reason', 'no such request'); end if;
  if coalesce(i.status, '') in ('cancelled') then return jsonb_build_object('closed', false, 'reason', 'the request was cancelled'); end if;
  -- a hire already completed it: the hire told the other suppliers (job_awarded_other); nothing more is sent
  if coalesce(i.status, '') <> 'completed' then
    update public.inquiries set status = 'closed', reveal_open_until = null where id = p_inquiry;
    v_told := public.fn_sales_engineer_tells_unchosen_suppliers(p_inquiry, 'closed', null);
  else
    update public.inquiries set reveal_open_until = null where id = p_inquiry;
  end if;
  update public.request_reveal_outcome
     set state = 'closed', open_until = null, closed_at = coalesce(closed_at, now()), closed_by = p_by, closed_reason = left(p_reason, 500),
         unchosen_told = unchosen_told || v_told, updated_at = now()
   where inquiry_id = p_inquiry and state in ('open_for_more', 'reopened');
  select string_agg(transaction_id::text, ',') into v_tx from public.request_reveal_outcome where inquiry_id = p_inquiry;
  insert into public.company_event (event_type, entity_type, entity_id, actor, payload, dedupe_key)
  select 'request.closed', 'inquiry', p_inquiry::text, 'sales_engineer',
         jsonb_build_object('by', p_by, 'reason', left(p_reason, 500), 'transactions', v_tx, 'unchosen_told', v_told,
                            'status', case when coalesce(i.status, '') = 'completed' then 'completed' else 'closed' end),
         'request.closed:' || p_inquiry || ':' || to_char(now(), 'YYYYMMDDHH24MISS')
  where not exists (select 1 from public.company_event e where e.dedupe_key = 'request.closed:' || p_inquiry || ':' || to_char(now(), 'YYYYMMDDHH24MISS'));
  return jsonb_build_object('closed', true, 'by', p_by, 'unchosen_told', v_told);
end $fn$;
revoke execute on function public.fn_sales_engineer_closes_request(uuid, text, text) from public, anon, authenticated;

-- A repeat delivery of the same sale must not re-open a closed request (see 4. above).
create or replace function public.trg_a_closed_request_stays_closed()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
begin
  if OLD.status = 'closed' and NEW.status = 'revealed' and coalesce(current_setting('qd.reopen_request', true), '') <> 'on'
     and exists (select 1 from public.request_reveal_outcome r where r.inquiry_id = NEW.id and r.state = 'closed') then
    NEW.status := 'closed';
  end if;
  return NEW;
end $fn$;
revoke execute on function public.trg_a_closed_request_stays_closed() from public, anon, authenticated;
drop trigger if exists a20_a_closed_request_stays_closed on public.inquiries;
create trigger a20_a_closed_request_stays_closed before update of status on public.inquiries
  for each row execute function public.trg_a_closed_request_stays_closed();

-- ── 3. what the sales engineer does when it learns a customer paid (CODE, then the MODEL is asked) ────────────────────────
create or replace function public.fn_sales_engineer_closes_on_reveal(p_id bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare a public.agent_actions; d jsonb; t public.transactions; i public.inquiries; c public.customers; v_fx boolean;
  v_paid timestamptz; v_total int; v_other int; v_cmp jsonb; v_rec boolean; v_until timestamptz; v_state text; v_note text;
  v_told jsonb := '[]'::jsonb; v_q bigint; v_mstatus text; v_case jsonb; v_chase int; v_close jsonb; r public.request_reveal_outcome;
begin
  select * into a from public.agent_actions where id = p_id;
  d := a.detail;
  select * into t from public.transactions where id = nullif(d->>'transaction_id', '')::uuid;
  if not found or t.inquiry_id is null then return jsonb_build_object('acted', false, 'reason', 'no paid transaction with a request'); end if;
  select * into r from public.request_reveal_outcome where transaction_id = t.id;
  if found then return jsonb_build_object('acted', false, 'already', true, 'state', r.state, 'open_until', r.open_until); end if;
  select * into i from public.inquiries where id = t.inquiry_id for update;
  select * into c from public.customers where id = i.customer_id;
  v_fx := coalesce(public.fn_seat_clock_customer_is_fixture(c), false);
  -- Stripe's paid time when the accountant's hand-over carries it (agent W1 may add paid_at), else the sale's own time
  v_paid := coalesce(nullif(d->>'paid_at', '')::timestamptz, t.revealed_at, now());
  select coalesce(chase_after_working_days, 3) into v_chase from public.pricing_config order by id limit 1;
  v_chase := coalesce(v_chase, 3);

  -- THE WHOLE REQUEST AT THIS MOMENT
  select count(*) into v_total from public.quotes q where q.inquiry_id = i.id and coalesce(q.status, '') not in ('draft', 'withdrawn');
  select count(*) into v_other from public.quotes q
   where q.inquiry_id = i.id and coalesce(q.status, '') not in ('draft', 'withdrawn', 'revealed', 'expired')
     and (q.expires_at is null or q.expires_at > now())
     and not exists (select 1 from public.transactions x where x.quote_id = q.id and x.fee_status = 'paid');
  select qc.analysis into v_cmp from public.quote_comparisons qc where qc.inquiry_id = i.id order by qc.created_at desc limit 1;
  v_rec := case when v_cmp is null or nullif(v_cmp->>'best_value_label', '') is null or jsonb_typeof(v_cmp->'quotes') is distinct from 'array' then null
                else exists (select 1 from jsonb_array_elements(v_cmp->'quotes') x
                              where x->>'quote_id' = t.quote_id::text and x->>'label_en' = v_cmp->>'best_value_label') end;
  v_until := coalesce(t.refund_deadline, public.fn_add_working_days(v_paid, 5));

  -- THE CODE DEFAULT (instant): nothing left to reveal -> closed; otherwise open for more until the refund window ends
  if v_other = 0 then
    v_state := 'closed';
    v_note := 'code: no other live quotation is left on the request, so it is closed at the payment';
  else
    v_state := 'open_for_more';
    v_note := 'code default: ' || v_other || ' other live quotation' || case when v_other = 1 then ' is' else 's are' end
      || ' still on the request, so the customer may reveal another until the refund window ends ('
      || to_char(v_until at time zone 'Asia/Dubai', 'DD Mon YYYY') || '); the request then closes';
  end if;

  update public.inquiries
     set outcome = coalesce(outcome, 'revealed'),
         stage_changed_at = case when coalesce(pipeline_stage, '') in ('revealed', 'won') then stage_changed_at else v_paid end,
         pipeline_stage = case when pipeline_stage = 'won' then pipeline_stage else 'revealed' end,
         deal_owner = coalesce(deal_owner, 'sales_engineer'),
         reveal_open_until = case when v_state = 'open_for_more' then greatest(coalesce(reveal_open_until, v_until), v_until) else null end
   where id = i.id;

  -- THE MODEL IS ASKED only when there is something to judge (the request stayed open). One lean decide call.
  if v_state = 'open_for_more' then
    v_case := jsonb_build_object('request', jsonb_build_object('rfq_no', i.rfq_no, 'trade', i.category, 'emirate', i.emirate,
                                   'created_at', i.created_at, 'required_by', i.required_by),
      'paid_at', v_paid, 'quotes_received', v_total, 'other_live_quotes', v_other,
      'chosen_was_the_comparison_recommendation', v_rec, 'open_until_if_kept_open', v_until,
      'earlier_reveals_on_this_request', (select count(*) from public.transactions x where x.inquiry_id = i.id and x.fee_status = 'paid' and x.id <> t.id));
    v_q := public.fn_reason_hold('sales_engineer', 'sales_engineer.reveal_paid',
      'A customer has just paid to reveal one supplier on a request. Should the request close now, or stay open so the customer can still reveal another of the quotations until the open-until date?',
      jsonb_build_object('seat', 'sales_engineer', 'surface', 'sales_engineer.reveal_paid',
        'question', 'A customer has just paid to reveal one supplier on a request. Should the request close now, or stay open so the customer can still reveal another of the quotations until the open-until date?',
        'context', jsonb_build_object('audience', 'internal', 'case', v_case),
        'decision', jsonb_build_object('name', 'reveal_paid', 'options', jsonb_build_array(
          jsonb_build_object('id', 'keep_open', 'meaning', 'a second reveal is plausible (several comparable quotations, the chosen one was not the recommendation, a large or multi-part job): keep the request open until the open-until date'),
          jsonb_build_object('id', 'close_now', 'meaning', 'the customer has what the request was for (the recommended or clearly best quotation was revealed): close the request now and tell the other suppliers it is closed'))),
        'stakes', 'normal', 'research', false, 'lean', true, 'easy', true, 'effort', 'low', 'plan', jsonb_build_object('steps', '[]'::jsonb),
        'subject', jsonb_build_object('transaction_id', t.id, 'inquiry_id', i.id, 'quote_id', t.quote_id, 'fixture', v_fx),
        'dedupeKey', 'reveal_paid:' || t.id),
      jsonb_build_object('filed_by', 'fn_sales_engineer_closes_on_reveal', 'pending', jsonb_build_array('decide')),
      jsonb_build_object('transaction_id', t.id, 'inquiry_id', i.id, 'quote_id', t.quote_id, 'fixture', v_fx),
      'reveal_paid', 'reveal_paid:' || t.id);
    v_mstatus := case when v_q is not null then 'asked'
                      when v_fx then 'not asked: demo traffic is never sent to a model (fn_reason_subject_is_fixture); the code default stands'
                      else 'not asked: the question could not be filed; the code default stands' end;
  else
    v_mstatus := 'not asked: nothing to judge (no other live quotation)';
  end if;

  insert into public.request_reveal_outcome (transaction_id, inquiry_id, quote_id, supplier_id, revealed_at, quotes_received,
         other_live_quotes, chosen_was_recommended, state, open_until, decided_by, decision_note, held_question_id, model_status, handoff_id)
  values (t.id, i.id, t.quote_id, t.supplier_id, v_paid, v_total, v_other, v_rec, v_state,
          case when v_state = 'open_for_more' then v_until end, 'code_default', v_note, v_q, v_mstatus, p_id);

  -- the unchosen suppliers, told at the payment
  if v_state = 'closed' then
    v_close := public.fn_sales_engineer_closes_request(i.id, 'code', v_note);
    v_told := coalesce(v_close->'unchosen_told', '[]'::jsonb);
    update public.request_reveal_outcome set unchosen_told = v_told, closed_at = now(), closed_by = 'code', closed_reason = v_note
     where transaction_id = t.id;
  else
    v_told := public.fn_sales_engineer_tells_unchosen_suppliers(i.id, 'reveal_open', v_until);
    update public.request_reveal_outcome set unchosen_told = v_told where transaction_id = t.id;
  end if;

  -- the follow-up, owned
  insert into public.reveal_followup (transaction_id, kind, owner_seat, due_at, escalate_at) values
    (t.id, 'connect_check', 'sales_engineer', public.fn_add_working_days(v_paid, 1), public.fn_add_working_days(v_paid, v_chase)),
    (t.id, 'hire_check', 'customer_support', v_paid + interval '3 days', v_paid + interval '16 days')
  on conflict (transaction_id, kind) do nothing;

  insert into public.company_event (event_type, entity_type, entity_id, actor, payload, dedupe_key)
  select 'request.reveal_outcome', 'transaction', t.id::text, 'sales_engineer',
         jsonb_build_object('inquiry_id', i.id, 'state', v_state, 'open_until', case when v_state = 'open_for_more' then v_until end,
                            'decided_by', 'code_default', 'note', v_note, 'model', v_mstatus, 'unchosen_told', jsonb_array_length(v_told)),
         'request.reveal_outcome:' || t.id
  where not exists (select 1 from public.company_event e where e.dedupe_key = 'request.reveal_outcome:' || t.id);

  return jsonb_build_object('acted', true, 'state', v_state, 'open_until', case when v_state = 'open_for_more' then v_until end,
    'decided_by', 'code_default', 'note', v_note, 'model', jsonb_build_object('held_question_id', v_q, 'status', v_mstatus),
    'quotes_received', v_total, 'other_live_quotes', v_other, 'chosen_was_recommended', v_rec,
    'unchosen_told', v_told, 'follow_ups', jsonb_build_array('connect_check', 'hire_check'),
    'inquiry', (select jsonb_build_object('status', x.status, 'outcome', x.outcome, 'pipeline_stage', x.pipeline_stage,
                                          'reveal_open_until', x.reveal_open_until) from public.inquiries x where x.id = i.id));
end $fn$;
revoke execute on function public.fn_sales_engineer_closes_on_reveal(bigint) from public, anon, authenticated;

-- ── 4. the loop back: a refund paid re-opens the request (CODE) ───────────────────────────────────────────────────────────
create or replace function public.fn_sales_engineer_reopens_after_refund(p_id bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare a public.agent_actions; d jsonb; t public.transactions; i public.inquiries; v_until timestamptz := now() + interval '14 days';
  v_why constant text := 'refund paid: the revealed supplier did not respond (Terms of Service v11 clause 5; Refund Policy v1.9 section 3). '
    || 'Neither document says the customer''s access ends when the refund is paid, so the supplier is not told so; the request is re-opened so the customer can reveal another supplier.';
begin
  select * into a from public.agent_actions where id = p_id;
  d := a.detail;
  select * into t from public.transactions
   where id = case when coalesce(d->>'transaction_id', '') ~ '^[0-9a-f-]{36}$' then (d->>'transaction_id')::uuid end
      or (quote_id::text = d->>'quote_id' and d->>'transaction_id' is null)
   limit 1;
  if not found or t.inquiry_id is null then return jsonb_build_object('reopened', false, 'reason', 'no transaction on this refund'); end if;
  select * into i from public.inquiries where id = t.inquiry_id for update;
  if coalesce(i.status, '') in ('completed', 'cancelled') then
    return jsonb_build_object('reopened', false, 'reason', 'the request is ' || i.status);
  end if;
  perform set_config('qd.reopen_request', 'on', true);
  update public.inquiries set status = 'revealed', reveal_open_until = v_until where id = i.id;
  perform set_config('qd.reopen_request', '', true);
  update public.request_reveal_outcome
     set state = 'reopened', open_until = v_until, reopened_at = now(), reopen_reason = v_why, updated_at = now()
   where transaction_id = t.id;
  insert into public.company_event (event_type, entity_type, entity_id, actor, payload, dedupe_key)
  select 'request.reopened', 'transaction', t.id::text, 'sales_engineer', jsonb_build_object('inquiry_id', i.id, 'open_until', v_until, 'why', v_why),
         'request.reopened:' || t.id
  where not exists (select 1 from public.company_event e where e.dedupe_key = 'request.reopened:' || t.id);
  return jsonb_build_object('reopened', true, 'open_until', v_until, 'why', v_why);
end $fn$;
revoke execute on function public.fn_sales_engineer_reopens_after_refund(bigint) from public, anon, authenticated;

-- ── 5. the handler the money hand-overs reach the sales engineer through ──────────────────────────────────────────────────
create or replace function public.fn_sales_engineer_acts_on_money_handoff(p_id bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare a public.agent_actions; v jsonb; v_more jsonb := null;
begin
  select * into a from public.agent_actions where id = p_id;
  -- the messages first, exactly as before (the receipt, the chosen supplier's notice, the refund notice)
  v := public.fn_sales_engineer_acts_on_handoff(p_id);
  -- then the request. Its failure is written into the answer the accountant reads and never un-sends the messages.
  begin
    if a.detail->>'type' = 'reveal.paid' then v_more := public.fn_sales_engineer_closes_on_reveal(p_id);
    elsif a.detail->>'type' = 'refund.paid' then v_more := public.fn_sales_engineer_reopens_after_refund(p_id);
    end if;
  exception when others then
    v_more := jsonb_build_object('acted', false, 'error', left(sqlerrm, 300));
  end;
  return case when v_more is null then v else v || jsonb_build_object('request', v_more) end;
end $fn$;
revoke execute on function public.fn_sales_engineer_acts_on_money_handoff(bigint) from public, anon, authenticated;

update public.seat_handoff_kind
   set handler = 'fn_sales_engineer_acts_on_money_handoff',
       owner_file = 'scripts/sql/a_paid_reveal_closes_the_request_and_everyone_on_it_is_told.sql'
 where from_seat = 'accountant' and to_seat = 'sales_engineer' and type in ('reveal.paid', 'refund.paid');

-- ── 6. the model's answer, applied (MODEL -> CODE) ─────────────────────────────────────────────────────────────────────────
create or replace function public.fn_reason_apply_sales_engineer__reveal_paid(p_id bigint, p_result jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare h public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; r public.request_reveal_outcome; v_close jsonb;
  v_why text := left(coalesce(nullif(btrim(p_result->>'answer'), ''), 'no reason given'), 2000);
begin
  if v_choice is null or v_choice not in ('close_now', 'keep_open') then
    -- fn_reason_held_resolve marks a row applied whenever its apply returns, so a non-answer RAISES and is reasoned again
    raise exception 'CHOICE_NOT_AN_OPTION: % (held question %)', coalesce(v_choice, 'no choice'), p_id;
  end if;
  select * into h from public.reasoning_held_question where id = p_id;
  select * into r from public.request_reveal_outcome where transaction_id = nullif(h.subject->>'transaction_id', '')::uuid for update;
  if not found then return jsonb_build_object('applied', false, 'reason', 'no reveal record for this question'); end if;
  if r.state <> 'open_for_more' then
    update public.request_reveal_outcome set model = p_result->>'model', updated_at = now(),
           model_status = 'answered ' || v_choice || ' after the request had moved on (' || r.state || '); nothing changed'
     where transaction_id = r.transaction_id;
    return jsonb_build_object('applied', false, 'reason', 'the request is ' || r.state);
  end if;
  update public.request_reveal_outcome
     set decided_by = 'model', model = p_result->>'model', model_status = 'answered: ' || v_choice,
         decision_note = 'sales_engineer (model): ' || v_choice || ': ' || v_why, updated_at = now()
   where transaction_id = r.transaction_id;
  if v_choice = 'close_now' then
    v_close := public.fn_sales_engineer_closes_request(r.inquiry_id, 'model', 'the sales engineer judged the request complete: ' || left(v_why, 400));
  end if;
  return jsonb_build_object('applied', true, 'transaction_id', r.transaction_id, 'choice', v_choice, 'close', v_close);
end $fn$;
revoke execute on function public.fn_reason_apply_sales_engineer__reveal_paid(bigint, jsonb) from public, anon, authenticated;

-- ── 7. the hourly duty: close what is due, own every follow-up, note an unanswered model (CODE) ───────────────────────────
create or replace function public.fn_sales_engineer_reveal_aftercare_tick()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on'; r record; f record;
  v_closed int := 0; v_model int := 0; v_fu_closed int := 0; v_fu_esc int := 0; v_review int := 0; v_days int;
begin
  -- 1. a request open for more whose date has passed, or that a hire completed, is closed
  for r in select o.inquiry_id, o.open_until, i.status
             from public.request_reveal_outcome o join public.inquiries i on i.id = o.inquiry_id
             left join public.customers c on c.id = i.customer_id
            where o.state in ('open_for_more', 'reopened') and (o.open_until <= now() or i.status = 'completed')
              and coalesce(public.fn_seat_clock_customer_is_fixture(c), false) = v_fx
            order by o.open_until limit 100 loop
    perform public.fn_sales_engineer_closes_request(r.inquiry_id,
      case when r.status = 'completed' then 'hire' else 'code' end,
      case when r.status = 'completed' then 'the customer hired a supplier, which completed the request'
           else 'the open period ended on ' || to_char(r.open_until at time zone 'Asia/Dubai', 'DD Mon YYYY') end);
    v_closed := v_closed + 1;
  end loop;

  -- 2. a question the model never answered: the code default stands, and the record says so
  update public.request_reveal_outcome o
     set model_status = 'not answered (' || h.status || '): the code default stands', updated_at = now()
    from public.reasoning_held_question h
   where h.id = o.held_question_id and o.model_status = 'asked' and h.status in ('failed', 'expired');
  get diagnostics v_model = row_count;

  -- 3. the follow-ups
  select coalesce(nullif(value, '')::int, 21) into v_days from public.app_secrets where key = 'rating_request_days_after_reveal';
  v_days := coalesce(v_days, 21);
  for f in select fu.*, t.inquiry_id, t.supplier_id, t.revealed_at, i.hired_supplier_id, i.outcome as inq_outcome,
                  w.first_response_at, w.response_channel, w.closed_at as watch_closed, w.close_reason
             from public.reveal_followup fu
             join public.transactions t on t.id = fu.transaction_id
             join public.inquiries i on i.id = t.inquiry_id
             left join public.customers c on c.id = i.customer_id
             left join public.supplier_response_watch w on w.transaction_id = t.id
            where fu.closed_at is null and coalesce(public.fn_seat_clock_customer_is_fixture(c), false) = v_fx
            order by fu.due_at limit 500 loop
    if f.kind = 'connect_check' then
      if f.first_response_at is not null then
        update public.reveal_followup set closed_at = now(),
               outcome = 'connected: the supplier responded ' || to_char(f.first_response_at at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || coalesce(' by ' || f.response_channel, '')
         where id = f.id;
        v_fu_closed := v_fu_closed + 1;
      elsif f.watch_closed is not null then
        update public.reveal_followup set closed_at = now(), outcome = 'the response watch closed: ' || coalesce(f.close_reason, 'no reason') where id = f.id;
        v_fu_closed := v_fu_closed + 1;
      elsif now() >= f.escalate_at then
        -- the existing chase rules own it from here: the refund ladder chases on working day 3 and the CEO decides on day 5
        update public.reveal_followup set closed_at = now(), escalated_at = now(),
               outcome = 'no response by the chase day: handed to the non-response ladder (chase, then the CEO''s day-5 decision)',
               escalation = jsonb_build_object('to', 'refund ladder', 'rule', 'pricing_config.chase_after_working_days / refund_window_working_days')
         where id = f.id;
        v_fu_esc := v_fu_esc + 1;
      end if;
    elsif f.kind = 'hire_check' then
      if f.hired_supplier_id is not null or f.inq_outcome in ('hired', 'not_hired') then
        update public.reveal_followup set closed_at = now(),
               outcome = case when f.hired_supplier_id = f.supplier_id then 'hired the revealed supplier'
                              when f.hired_supplier_id is not null then 'hired another supplier'
                              else 'did not hire the revealed supplier' end
         where id = f.id;
        v_fu_closed := v_fu_closed + 1;
      elsif exists (select 1 from public.customer_followup cf where cf.transaction_id = f.transaction_id and cf.hired = 'not_yet') and now() < f.escalate_at then
        null;   -- "not yet": the day-14 ask comes
      elsif now() >= f.escalate_at then
        update public.reveal_followup set closed_at = now(), escalated_at = now(),
               outcome = 'unanswered after the day-3 and day-14 asks',
               escalation = jsonb_build_object('rule', 'fn_customer_support_followup_tick asks on day 3 and day 14; no further ask')
         where id = f.id;
        v_fu_esc := v_fu_esc + 1;
      end if;
    elsif f.kind = 'review_request' then
      if exists (select 1 from public.reviews rv where rv.transaction_id = f.transaction_id) then
        update public.reveal_followup set closed_at = now(), outcome = 'reviewed' where id = f.id;
        v_fu_closed := v_fu_closed + 1;
      elsif now() >= f.escalate_at then
        update public.reveal_followup set closed_at = now(), escalated_at = now(), outcome = 'no review after the rating request' where id = f.id;
        v_fu_esc := v_fu_esc + 1;
      end if;
    end if;
    -- a hire of the revealed supplier opens the review request (customer_support sends it rating_request_days_after_reveal after the reveal)
    if f.hired_supplier_id is not null and f.hired_supplier_id = f.supplier_id then
      insert into public.reveal_followup (transaction_id, kind, owner_seat, due_at, escalate_at)
      values (f.transaction_id, 'review_request', 'customer_support', f.revealed_at + make_interval(days => v_days), f.revealed_at + make_interval(days => v_days + 14))
      on conflict (transaction_id, kind) do nothing;
      if found then v_review := v_review + 1; end if;
    end if;
  end loop;
  return jsonb_build_object('closed', v_closed, 'model_unanswered', v_model, 'follow_ups_closed', v_fu_closed,
                            'follow_ups_escalated', v_fu_esc, 'review_requests_opened', v_review, 'fixtures', v_fx);
end $fn$;
revoke execute on function public.fn_sales_engineer_reveal_aftercare_tick() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file)
values ('sales_engineer.reveal_aftercare', 'sales_engineer', interval '1 hour', 'fn_sales_engineer_reveal_aftercare_tick',
        'After a paid reveal: close a request whose open period ended or that a hire completed (telling the other suppliers once), close or escalate each follow-up (connect day 1, hire day 3/14, review after a hire), and note a reveal question the model never answered.',
        'scripts/sql/a_paid_reveal_closes_the_request_and_everyone_on_it_is_told.sql')
on conflict (duty) do update set routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file, every = excluded.every;

-- ── 8. a held quotation stores no fee base until its VAT basis is settled (build list item 10) ────────────────────────────
-- quotes.quote_amount is what every charge path reads and what the generated app_fee / customer_price are computed from. A
-- quotation held for its VAT basis stored the VAT-inclusive total there (stated_price.ts storedPrice fallback), so app_fee
-- was 3% of a gross figure. From now on a held quotation stores NULL (its stated total stays in amount_as_stated) and the
-- ex-VAT figure is written once the supplier's answer settles it (line_specs/workflow.ts). Deploy order: apply this BEFORE
-- deploying supplier_api, whose insert may now carry a NULL quote_amount.
alter table public.quotes alter column quote_amount drop not null;
update public.quotes
   set amount_as_stated = coalesce(amount_as_stated, quote_amount), quote_amount = null
 where price_ex_vat is null and coalesce(vat_treatment, '') in ('not_stated', 'inclusive')
   and coalesce(status, '') not in ('revealed')
   and not exists (select 1 from public.transactions t where t.quote_id = quotes.id);
