-- Seat: sales_engineer. Assigned: sales_engineer (company-workflow fix round W2, 13 Nov 2026; founder_instruction 1685, 1688;
-- revised after the independent review "WORKFLOW W2 SALES 1" and the coordinator's decisions A, B, C of 13 Nov 2026).
--
-- THE FOUNDER (1685): "Is the sales engineer aware that the customer paid and now he closed this project totally?"
--
-- MEASURED on origin/main 2cef71f27 (workflow audit of 13 Nov 2026 and the production mirror):
--   * reveal.paid (accountant -> sales_engineer, fn_sales_engineer_acts_on_handoff) sent the receipt and the chosen supplier's
--     notice and nothing else: outcome, pipeline_stage, completed_at stayed NULL (production: 3 inquiries, NULL x3).
--   * fn_sales_engineer_tells_losing_suppliers runs only on a hire: the suppliers not chosen heard nothing at the payment,
--     and nothing ever if the customer never hires.
--   * a paid request still took NEW quotations (supplier_api submit_quote refuses only completed/closed/cancelled).
--   * refund.paid told the customer and left the request as it was.
--   * production constraint quotes_vat_treatment_known allowed exclusive/inclusive/not_registered/not_stated/
--     confirmed_on_portal only, so a zero-rated or exempt quotation could not be stored.
--
-- WHAT A PAID REQUEST IS NOW (decision A): its STATUS stays 'revealed' (the customer and the revealed supplier keep their
-- clarifying questions, notes, WhatsApp files and e-mailed documents; reveal_guard.ts keeps a second reveal possible;
-- 'closed' already means a split parent whose parts ended). The sales engineer's closure is the request's OUTCOME and
-- STAGE: outcome 'revealed' (a hire writes 'hired'), pipeline_stage 'revealed' (crm_stages), one row per paid reveal in
-- public.request_reveal_outcome, company_event 'request.reveal_outcome' / 'request.reveal_period_ended' / 'request.reopened'.
--   * From the first paid reveal the request takes NO NEW quotations (trigger a05 on quotes, and supplier_api submit_quote
--     says so in a sentence); a supplier who already quoted may still revise or add an option.
--   * THE REVEAL PERIOD (decision B): the customer may reveal another quotation while the quotations are valid.
--     inquiries.reveal_open_until = the latest expiry (quotes.expires_at: the stated validity, else trg_quote_expiry's
--     default of 14 days) among the remaining live quotations, a quotation in the 24-hour quality hold counted as live,
--     capped at 30 days after the first paid reveal; recomputed when a quotation is withdrawn or its expiry moves;
--     reveal_guard.ts canReveal refuses once it has passed. The hourly duty ends the period when reveal_open_until <= now()
--     (never from an earlier record's date), records the end and tells the remaining suppliers once.
--   * THE OTHER SUPPLIERS are told, once per event, in English, with platform values only (request number, a date; no
--     customer text, no name, no price): at the first paid reveal (neutral), at the end of the period, and, if a refund
--     re-opens a period that had ended, that it is open again.
--   * NO MODEL CALL (decision C): nothing at this step needs judgement. The period is a fact of the quotations' validity;
--     who is told, what and when follow from it. The founder pays for judgement where one exists (the accountant's and the
--     CEO's exceptions, agent W1). An earlier draft asked the model "close now or keep open"; its only possible effect was to
--     take the customer's option to open another quotation away, so it was removed.
--   * THE LOOP BACK: the outcome is in the reveal.paid answer the accountant (the sender) reads (evidence.request), in
--     request_reveal_outcome and company_event for the CEO. refund.paid re-opens the reveal period only when a period was
--     recorded for that reveal AND a live quotation remains; reveals paid before this file are never touched. Terms of
--     Service v11 clause 5 and Refund Policy v1.9 section 3 do not say the customer's access ends on a refund, so the
--     supplier is not told that.
--   * THE RECEIPT prints the refund window's end date when the accountant's hand-over carries refund_window_sentence_en/_ar
--     (W1's branch); fn_sales_engineer_acts_on_handoff is redefined from the LIVE body (pg_get_functiondef, 13 Nov 2026)
--     with only that, the two request steps (after the reveal.paid messages; on refund.paid BEFORE the customer's message,
--     whose last sentence now says what the re-open made true) and a finding when a step fails. W1 does not redefine it.
--   * NO FOLLOW-UP TABLE: the day-1/3/14/review rows an earlier draft added only mirrored duties that already run and reached
--     nobody; the supplier_response_watch (non-response ladder, CEO decision on day 5), customer_followup (day 3 / 14) and
--     the rating request are the follow-up, each with its owner and escalation.
-- Prevented by: scripts/checks/a_paid_reveal_ends_its_reveal_period_and_tells_everyone.test.mjs, this file's _probe.sql,
-- scripts/it/a_paid_reveal_is_known_to_every_seat_with_a_step.gaps.mjs GAP 8-10 on a rehearsal.
-- Pending until the release applies it: scripts/sql/pending/<this name>.txt

-- ── 0. the record, the column, the constraint ──────────────────────────────────────────────────────────────────────────────
alter table public.inquiries add column if not exists reveal_open_until timestamptz;
comment on column public.inquiries.reveal_open_until is
  'sales_engineer: after a paid reveal, until when the customer may reveal another quotation on this request (the latest expiry of the remaining live quotations, capped at 30 days after the first paid reveal). NULL: no reveal period. In the past: the period has ended (canReveal refuses).';

create table if not exists public.request_reveal_outcome (
  transaction_id uuid primary key references public.transactions(id) on delete cascade,
  inquiry_id uuid not null references public.inquiries(id) on delete cascade,
  quote_id uuid not null,
  supplier_id bigint,
  revealed_at timestamptz not null,
  quotes_received integer not null default 0,
  other_live_quotes integer not null default 0,
  chosen_was_recommended boolean,
  state text not null check (state in ('reveal_open', 'ended', 'reopened')),
  open_until timestamptz,
  note text not null,
  suppliers_told jsonb not null default '[]'::jsonb,
  ended_at timestamptz,
  ended_reason text,
  reopened_at timestamptz,
  reopen_reason text,
  handoff_id bigint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists request_reveal_outcome_inquiry_idx on public.request_reveal_outcome (inquiry_id);
alter table public.request_reveal_outcome enable row level security;
drop policy if exists request_reveal_outcome_service_role_only on public.request_reveal_outcome;
create policy request_reveal_outcome_service_role_only on public.request_reveal_outcome
  as permissive for all to public using (false) with check (false);
revoke all on public.request_reveal_outcome from anon, authenticated;
comment on table public.request_reveal_outcome is
  'sales_engineer: one row per paid reveal: the request''s reveal period (open, ended, re-opened after a refund), its date, what the other suppliers were told and why it ended. Read by the accountant (the reveal.paid sender), the CEO and the portals.';

-- zero-rated and exempt are stated VAT answers (line_specs/vat.ts): the constraint names them
alter table public.quotes drop constraint if exists quotes_vat_treatment_known;
alter table public.quotes add constraint quotes_vat_treatment_known check (vat_treatment is null or vat_treatment = any (array[
  'exclusive', 'inclusive', 'not_registered', 'zero_rated', 'exempt', 'not_stated', 'confirmed_on_portal']));

-- ── 1. the reveal period (code) ────────────────────────────────────────────────────────────────────────────────────────────
-- A live remaining quotation: not withdrawn/expired/revealed/rejected/cancelled, not yet expired, not paid for; a 'draft'
-- counts only while it is in the 24-hour quality hold (a supplier's unsent draft is not a quotation).
create or replace function public.fn_sales_engineer_reveal_period_until(p_inquiry uuid, p_cap timestamptz)
 returns timestamptz
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
  select least(p_cap, coalesce(max(coalesce(q.expires_at, q.created_at + interval '14 days')), now()))
    from public.quotes q
   where q.inquiry_id = p_inquiry
     and coalesce(q.status, '') not in ('withdrawn', 'expired', 'revealed', 'rejected', 'cancelled')
     and (coalesce(q.status, '') <> 'draft'
          or exists (select 1 from public.quote_quality_hold h where h.quote_id = q.id and h.released_at is null))
     and coalesce(q.expires_at, q.created_at + interval '14 days') > now()
     and not exists (select 1 from public.transactions x where x.quote_id = q.id and x.fee_status = 'paid')
$fn$;
revoke execute on function public.fn_sales_engineer_reveal_period_until(uuid, timestamptz) from public, anon, authenticated;

create or replace function public.fn_sales_engineer_live_quotes_left(p_inquiry uuid)
 returns integer
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
  select count(*)::int from public.quotes q
   where q.inquiry_id = p_inquiry
     and coalesce(q.status, '') not in ('withdrawn', 'expired', 'revealed', 'rejected', 'cancelled')
     and (coalesce(q.status, '') <> 'draft'
          or exists (select 1 from public.quote_quality_hold h where h.quote_id = q.id and h.released_at is null))
     and coalesce(q.expires_at, q.created_at + interval '14 days') > now()
     and not exists (select 1 from public.transactions x where x.quote_id = q.id and x.fee_status = 'paid')
$fn$;
revoke execute on function public.fn_sales_engineer_live_quotes_left(uuid) from public, anon, authenticated;

-- ── 2. the other suppliers are told (code) ────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_sales_engineer_tells_unchosen_suppliers(p_inquiry uuid, p_event text, p_until timestamptz)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare i public.inquiries; c public.customers; v_fx boolean; l record; v_why text; v_d jsonb; v_key text; v_round int;
  v_type text; v_subject text; v_body text; v_no text; v_out jsonb := '[]'::jsonb;
begin
  if p_event not in ('reveal_open', 'ended', 'reopened') then raise exception 'event is reveal_open, ended or reopened, not %', p_event; end if;
  select * into i from public.inquiries where id = p_inquiry;
  if not found then return v_out; end if;
  select * into c from public.customers where id = i.customer_id;
  v_fx := coalesce(public.fn_seat_clock_customer_is_fixture(c), false);
  v_no := coalesce(i.rfq_no::text, '-');
  -- an ending after a re-opening is a new event: the round is the number of re-openings so far
  select count(*) into v_round from public.company_event e where e.event_type = 'request.reopened' and e.payload->>'inquiry_id' = p_inquiry::text;
  v_type := case p_event when 'reveal_open' then 'quote_not_selected' when 'ended' then 'request_ended' else 'request_reopened' end;
  for l in select le.id, coalesce(public.fn_supplier_address(le.claimed_by, le.email), '') as to_email
             from (select distinct q.supplier_id from public.quotes q
                    where q.inquiry_id = p_inquiry and q.supplier_id is not null
                      and coalesce(q.status, '') not in ('withdrawn')
                      and (coalesce(q.status, '') <> 'draft'
                           or exists (select 1 from public.quote_quality_hold h where h.quote_id = q.id and h.released_at is null))
                      -- a supplier the customer paid to reveal on this request is not one of "the others"
                      and not exists (select 1 from public.transactions t
                                       where t.inquiry_id = p_inquiry and t.supplier_id = q.supplier_id and t.fee_status = 'paid')) x
             join public.leads le on le.id = x.supplier_id
            where not coalesce(le.banned, false) and not public.fn_is_sanctioned_lead(le.id) loop
    v_key := case p_event when 'reveal_open' then v_type || ':' || p_inquiry || ':' || l.id
                          else v_type || ':' || p_inquiry || ':' || l.id || ':r' || v_round end;
    -- ONE MESSAGE PER SUPPLIER PER EVENT: a second paid reveal on the request tells nobody again
    if exists (select 1 from public.notifications n where n.dedupe_key = v_key)
       or exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'customer_support'
                   and a.target_id = 'delivery.request:' || v_key) then
      continue;
    end if;
    -- the hire already told this supplier (job_awarded_other): the end of the period is not a second message
    if p_event = 'ended' and exists (select 1 from public.notifications n where n.inquiry_id = p_inquiry and n.lead_id = l.id and n.type = 'job_awarded_other') then
      continue;
    end if;
    -- "open again" only to a supplier who was told it had ended
    if p_event = 'reopened' and not exists (select 1 from public.notifications n where n.inquiry_id = p_inquiry and n.lead_id = l.id and n.type = 'request_ended') then
      continue;
    end if;
    -- "remains available" is said only to a supplier whose quotation IS still live, and with no date: the date moves
    -- (a withdrawal, a moved expiry, a second reveal) and a supplier is never told again (coordinator's ruling, 13 Nov 2026)
    if p_event in ('reveal_open', 'reopened') and not exists (
         select 1 from public.quotes q where q.inquiry_id = p_inquiry and q.supplier_id = l.id
            and coalesce(q.status, '') not in ('withdrawn', 'expired', 'revealed', 'rejected', 'cancelled')
            and (coalesce(q.status, '') <> 'draft'
                 or exists (select 1 from public.quote_quality_hold h where h.quote_id = q.id and h.released_at is null))
            and coalesce(q.expires_at, q.created_at + interval '14 days') > now()) then
      continue;
    end if;
    if p_event = 'reveal_open' then
      v_subject := 'Update on request ' || v_no || ' — QuotesDone';
      v_body := 'The customer has opened one quotation on request ' || v_no
        || '. Your quotation remains available to the customer while it is valid. Nothing is needed from you now.';
    elsif p_event = 'ended' then
      v_subject := 'Request ' || v_no || ' has ended — QuotesDone';
      v_body := 'Request ' || v_no || ' has ended.'
        || case when i.hired_supplier_id is not null and i.hired_supplier_id <> l.id then ' The customer went ahead with another supplier.' else '' end
        || ' Nothing is needed from you. Thank you for your quotation.';
    else
      v_subject := 'Request ' || v_no || ' is open again — QuotesDone';
      v_body := 'Request ' || v_no || ' is open again. Your quotation is available to the customer while it is valid. Nothing is needed from you now.';
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

-- ── 3. ending a request's reveal period (code; the duty, or at once when nothing is left to reveal) ─────────────────────────
create or replace function public.fn_sales_engineer_ends_reveal_period(p_inquiry uuid, p_reason text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare v_told jsonb;
begin
  update public.inquiries set reveal_open_until = least(coalesce(reveal_open_until, now()), now()) where id = p_inquiry;
  v_told := public.fn_sales_engineer_tells_unchosen_suppliers(p_inquiry, 'ended', null);
  update public.request_reveal_outcome
     set state = 'ended', ended_at = now(), ended_reason = left(p_reason, 500), suppliers_told = suppliers_told || v_told, updated_at = now()
   where inquiry_id = p_inquiry and state in ('reveal_open', 'reopened');
  insert into public.company_event (event_type, entity_type, entity_id, actor, payload, dedupe_key)
  select 'request.reveal_period_ended', 'inquiry', p_inquiry::text, 'sales_engineer',
         jsonb_build_object('inquiry_id', p_inquiry, 'reason', left(p_reason, 500), 'suppliers_told', jsonb_array_length(v_told),
                            'outcome', (select outcome from public.inquiries where id = p_inquiry)),
         'request.reveal_period_ended:' || p_inquiry || ':' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS')
  where not exists (select 1 from public.company_event e where e.dedupe_key = 'request.reveal_period_ended:' || p_inquiry || ':' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS'));
  return jsonb_build_object('ended', true, 'reason', p_reason, 'suppliers_told', v_told);
end $fn$;
revoke execute on function public.fn_sales_engineer_ends_reveal_period(uuid, text) from public, anon, authenticated;

-- ── 4. what the sales engineer records when it learns a customer paid (code: nothing here needs judgement) ───────────────
create or replace function public.fn_sales_engineer_records_reveal(p_id bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare a public.agent_actions; d jsonb; t public.transactions; i public.inquiries; v_paid timestamptz; v_first timestamptz;
  v_total int; v_left int; v_cmp jsonb; v_rec boolean; v_until timestamptz; v_note text; v_told jsonb := '[]'::jsonb;
  v_end jsonb; r public.request_reveal_outcome;
begin
  select * into a from public.agent_actions where id = p_id;
  d := a.detail;
  select * into t from public.transactions where id = nullif(d->>'transaction_id', '')::uuid;
  if not found or t.inquiry_id is null then return jsonb_build_object('acted', false, 'reason', 'no paid transaction with a request'); end if;
  select * into r from public.request_reveal_outcome where transaction_id = t.id;
  if found then return jsonb_build_object('acted', false, 'already', true, 'state', r.state, 'open_until', r.open_until); end if;
  select * into i from public.inquiries where id = t.inquiry_id for update;
  -- Stripe's paid time when the accountant's hand-over carries it (W1 adds paid_at), else the sale's own time
  v_paid := coalesce(nullif(d->>'paid_at', '')::timestamptz, t.revealed_at, now());
  select least(v_paid, coalesce(min(o.revealed_at), v_paid)) into v_first from public.request_reveal_outcome o where o.inquiry_id = i.id;
  select count(*) into v_total from public.quotes q where q.inquiry_id = i.id and coalesce(q.status, '') not in ('draft', 'withdrawn');
  v_left := public.fn_sales_engineer_live_quotes_left(i.id);
  select qc.analysis into v_cmp from public.quote_comparisons qc where qc.inquiry_id = i.id order by qc.created_at desc limit 1;
  v_rec := case when v_cmp is null or nullif(v_cmp->>'best_value_label', '') is null or jsonb_typeof(v_cmp->'quotes') is distinct from 'array' then null
                else exists (select 1 from jsonb_array_elements(v_cmp->'quotes') x
                              where x->>'quote_id' = t.quote_id::text and x->>'label_en' = v_cmp->>'best_value_label') end;
  v_until := public.fn_sales_engineer_reveal_period_until(i.id, v_first + interval '30 days');
  v_note := case when v_left = 0 then 'no other live quotation is left to reveal, so the reveal period ends at the payment'
                 else v_left || ' other live quotation' || case when v_left = 1 then ' remains' else 's remain' end
                      || ' revealable until ' || to_char(v_until at time zone 'Asia/Dubai', 'DD Mon YYYY')
                      || ' (their latest validity, at most 30 days after the first paid reveal)' end;

  update public.inquiries
     set outcome = coalesce(outcome, 'revealed'),
         stage_changed_at = case when coalesce(pipeline_stage, '') in ('revealed', 'won') then stage_changed_at else v_paid end,
         pipeline_stage = case when pipeline_stage = 'won' then pipeline_stage else 'revealed' end,
         deal_owner = coalesce(deal_owner, 'sales_engineer'),
         reveal_open_until = v_until
   where id = i.id;

  insert into public.request_reveal_outcome (transaction_id, inquiry_id, quote_id, supplier_id, revealed_at, quotes_received,
         other_live_quotes, chosen_was_recommended, state, open_until, note, handoff_id)
  values (t.id, i.id, t.quote_id, t.supplier_id, v_paid, v_total, v_left, v_rec, 'reveal_open', v_until, v_note, p_id);
  -- a second paid reveal on the request: the earlier records follow the request's one period
  update public.request_reveal_outcome set open_until = v_until, updated_at = now()
   where inquiry_id = i.id and state in ('reveal_open', 'reopened');

  if v_left = 0 then
    v_end := public.fn_sales_engineer_ends_reveal_period(i.id, v_note);
    v_told := coalesce(v_end->'suppliers_told', '[]'::jsonb);
  else
    v_told := public.fn_sales_engineer_tells_unchosen_suppliers(i.id, 'reveal_open', v_until);
    update public.request_reveal_outcome set suppliers_told = suppliers_told || v_told where transaction_id = t.id;
  end if;

  insert into public.company_event (event_type, entity_type, entity_id, actor, payload, dedupe_key)
  select 'request.reveal_outcome', 'transaction', t.id::text, 'sales_engineer',
         jsonb_build_object('inquiry_id', i.id, 'state', case when v_left = 0 then 'ended' else 'reveal_open' end,
                            'reveal_open_until', v_until, 'note', v_note, 'suppliers_told', jsonb_array_length(v_told)),
         'request.reveal_outcome:' || t.id
  where not exists (select 1 from public.company_event e where e.dedupe_key = 'request.reveal_outcome:' || t.id);

  return jsonb_build_object('acted', true, 'state', case when v_left = 0 then 'ended' else 'reveal_open' end,
    'reveal_open_until', v_until, 'note', v_note, 'quotes_received', v_total, 'other_live_quotes', v_left,
    'chosen_was_recommended', v_rec, 'suppliers_told', v_told, 'decided_by', 'code: nothing at this step needs judgement',
    'inquiry', (select jsonb_build_object('status', x.status, 'outcome', x.outcome, 'pipeline_stage', x.pipeline_stage,
                                          'reveal_open_until', x.reveal_open_until) from public.inquiries x where x.id = i.id));
end $fn$;
revoke execute on function public.fn_sales_engineer_records_reveal(bigint) from public, anon, authenticated;

-- ── 5. the loop back: a refund re-opens the period only where one was recorded and a quotation is left (code) ────────────
create or replace function public.fn_sales_engineer_reopens_after_refund(p_id bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare a public.agent_actions; d jsonb; t public.transactions; i public.inquiries; r public.request_reveal_outcome;
  v_until timestamptz; v_was_ended boolean; v_told jsonb := '[]'::jsonb;
  v_why constant text := 'refund paid: the revealed supplier did not respond (Terms of Service v11 clause 5; Refund Policy v1.9 section 3). '
    || 'Neither says the customer''s access ends when the refund is paid, so the supplier is not told so.';
begin
  select * into a from public.agent_actions where id = p_id;
  d := a.detail;
  select * into t from public.transactions
   where id = case when coalesce(d->>'transaction_id', '') ~ '^[0-9a-f-]{36}$' then (d->>'transaction_id')::uuid end
      or (d->>'transaction_id' is null and quote_id::text = d->>'quote_id')
   limit 1;
  if not found or t.inquiry_id is null then return jsonb_build_object('reopened', false, 'reason', 'no transaction on this refund'); end if;
  -- a reveal paid before this file has no record: it is never touched
  select * into r from public.request_reveal_outcome where transaction_id = t.id;
  if not found then return jsonb_build_object('reopened', false, 'reason', 'no reveal period was recorded for this reveal'); end if;
  select * into i from public.inquiries where id = t.inquiry_id for update;
  if coalesce(i.status, '') in ('completed', 'cancelled') or i.hired_supplier_id is not null then
    return jsonb_build_object('reopened', false, 'reason', 'the request is ' || coalesce(i.status, '-'));
  end if;
  if public.fn_sales_engineer_live_quotes_left(i.id) = 0 then
    update public.request_reveal_outcome set reopen_reason = 'refund paid; not re-opened: no live quotation is left', updated_at = now()
     where transaction_id = t.id;
    return jsonb_build_object('reopened', false, 'reason', 'no live quotation is left');
  end if;
  v_until := public.fn_sales_engineer_reveal_period_until(i.id, now() + interval '30 days');
  v_was_ended := coalesce(i.reveal_open_until <= now(), false);
  -- the refunded sale is no longer the request's outcome unless another paid reveal still stands
  update public.inquiries
     set reveal_open_until = greatest(coalesce(reveal_open_until, v_until), v_until),
         outcome = case when outcome = 'revealed' and not exists (
                          select 1 from public.transactions x where x.inquiry_id = i.id and x.id <> t.id and x.fee_status = 'paid'
                            and coalesce(x.refund_status, '') not in ('refunded', 'succeeded')) then null else outcome end
   where id = i.id;
  update public.request_reveal_outcome
     set state = 'reopened', open_until = v_until, reopened_at = now(), reopen_reason = v_why, updated_at = now()
   where transaction_id = t.id;
  insert into public.company_event (event_type, entity_type, entity_id, actor, payload, dedupe_key)
  select 'request.reopened', 'transaction', t.id::text, 'sales_engineer',
         jsonb_build_object('inquiry_id', i.id, 'reveal_open_until', v_until, 'why', v_why, 'was_ended', v_was_ended),
         'request.reopened:' || t.id
  where not exists (select 1 from public.company_event e where e.dedupe_key = 'request.reopened:' || t.id);
  if v_was_ended then
    v_told := public.fn_sales_engineer_tells_unchosen_suppliers(i.id, 'reopened', v_until);
    update public.request_reveal_outcome set suppliers_told = suppliers_told || v_told where transaction_id = t.id;
  end if;
  return jsonb_build_object('reopened', true, 'reveal_open_until', v_until, 'why', v_why, 'suppliers_told', v_told);
end $fn$;
revoke execute on function public.fn_sales_engineer_reopens_after_refund(bigint) from public, anon, authenticated;

-- ── 6. the period follows the quotations: a withdrawal or a moved expiry recomputes it (code) ─────────────────────────────
create or replace function public.trg_a_quote_moves_its_requests_reveal_period()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare v_first timestamptz;
begin
  if exists (select 1 from public.request_reveal_outcome o where o.inquiry_id = NEW.inquiry_id and o.state in ('reveal_open', 'reopened')) then
    select coalesce(max(o.reopened_at), min(o.revealed_at)) into v_first
      from public.request_reveal_outcome o where o.inquiry_id = NEW.inquiry_id;
    update public.inquiries set reveal_open_until = public.fn_sales_engineer_reveal_period_until(NEW.inquiry_id, v_first + interval '30 days')
     where id = NEW.inquiry_id;
  end if;
  return NEW;
end $fn$;
revoke execute on function public.trg_a_quote_moves_its_requests_reveal_period() from public, anon, authenticated;
drop trigger if exists z33_a_quote_moves_its_requests_reveal_period on public.quotes;
create trigger z33_a_quote_moves_its_requests_reveal_period after update of status, expires_at on public.quotes
  for each row when (OLD.status is distinct from NEW.status or OLD.expires_at is distinct from NEW.expires_at)
  execute function public.trg_a_quote_moves_its_requests_reveal_period();

-- ── 7. from the first paid reveal, no NEW quotations (code) ────────────────────────────────────────────────────────────────
-- A supplier who already quoted may revise or add an option; a supplier new to the request is refused. supplier_api
-- submit_quote says it first in a sentence (code 'inquiry_revealed'); this trigger holds every other door (e-mail, WhatsApp).
create or replace function public.trg_a_paid_request_takes_no_new_quotations()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
begin
  if NEW.inquiry_id is not null and NEW.supplier_id is not null
     and exists (select 1 from public.transactions t where t.inquiry_id = NEW.inquiry_id and t.fee_status = 'paid'
                   and coalesce(t.refund_status, '') not in ('refunded', 'succeeded'))
     and not exists (select 1 from public.quotes q where q.inquiry_id = NEW.inquiry_id and q.supplier_id = NEW.supplier_id) then
    raise exception 'REQUEST_REVEALED: the customer has already opened a quotation on this request, so it takes no new quotations'
      using errcode = 'P0001';
  end if;
  return NEW;
end $fn$;
revoke execute on function public.trg_a_paid_request_takes_no_new_quotations() from public, anon, authenticated;
drop trigger if exists a05_a_paid_request_takes_no_new_quotations on public.quotes;
create trigger a05_a_paid_request_takes_no_new_quotations before insert on public.quotes
  for each row execute function public.trg_a_paid_request_takes_no_new_quotations();

-- ── 8. the hourly duty: a period whose date has passed ends (code) ─────────────────────────────────────────────────────────
create or replace function public.fn_sales_engineer_reveal_period_tick()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on'; r record; v_n int := 0;
begin
  -- THE REQUEST'S date (inquiries.reveal_open_until), never an earlier record's: a second reveal or a refund moves it
  for r in select distinct i.id, i.reveal_open_until
             from public.inquiries i
             join public.request_reveal_outcome o on o.inquiry_id = i.id and o.state in ('reveal_open', 'reopened')
             left join public.customers c on c.id = i.customer_id
            where i.reveal_open_until <= now()
              and coalesce(public.fn_seat_clock_customer_is_fixture(c), false) = v_fx
            order by i.reveal_open_until limit 100 loop
    perform public.fn_sales_engineer_ends_reveal_period(r.id,
      'the reveal period ended on ' || to_char(r.reveal_open_until at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI'));
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ended', v_n, 'fixtures', v_fx);
end $fn$;
revoke execute on function public.fn_sales_engineer_reveal_period_tick() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file)
values ('sales_engineer.reveal_period', 'sales_engineer', interval '1 hour', 'fn_sales_engineer_reveal_period_tick',
        'After a paid reveal: end the request''s reveal period once its date (inquiries.reveal_open_until) has passed, record it, and tell the other suppliers once that the request has ended.',
        'scripts/sql/a_paid_reveal_closes_the_request_and_everyone_on_it_is_told.sql')
on conflict (duty) do update set routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file, every = excluded.every;

-- ── 9. a held quotation stores no fee base until its VAT basis is settled (build list item 10) ────────────────────────────
-- quote_amount is what every charge path reads and what the generated app_fee / customer_price are computed from. A
-- quotation held for its VAT basis now stores NULL (its stated total stays in amount_as_stated) until the supplier's answer
-- settles the ex-VAT figure (line_specs/workflow.ts). Apply this BEFORE deploying supplier_api.
alter table public.quotes alter column quote_amount drop not null;
update public.quotes
   set amount_as_stated = coalesce(amount_as_stated, quote_amount), quote_amount = null
 where price_ex_vat is null and coalesce(vat_treatment, '') in ('not_stated', 'inclusive')
   and coalesce(status, '') not in ('revealed')
   and not exists (select 1 from public.transactions t where t.quote_id = quotes.id);

-- ── 9b. a request step that fails is a finding the it_engineer reads, and an event in the stream (code) ─────────────────────
create or replace function public.fn_sales_engineer_request_step_failed(p_id bigint, p_type text, p_error text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
begin
  begin
    perform public.fn_it_engineer_finding_upsert('reveal_request_step:' || p_id,
      'The sales engineer could not record the request after ' || p_type || ' (hand-over ' || p_id || ')',
      'public.fn_sales_engineer_acts_on_handoff -> ' || case when p_type = 'refund.paid' then 'fn_sales_engineer_reopens_after_refund' else 'fn_sales_engineer_records_reveal' end,
      'agent_facing', 1,
      jsonb_build_object('handoff_id', p_id, 'type', p_type, 'error', left(p_error, 500), 'owner_seat', 'sales_engineer',
                         'fix', 'read the error, fix the routine, then run the step again for this hand-over'),
      '{}'::text[], array['why the step raised'], 'sales_engineer');
    insert into public.company_event (event_type, entity_type, entity_id, actor, payload, dedupe_key)
    select 'request.step_failed', 'handoff', p_id::text, 'sales_engineer',
           jsonb_build_object('handoff_id', p_id, 'type', p_type, 'error', left(p_error, 500)), 'request.step_failed:' || p_id
    where not exists (select 1 from public.company_event e where e.dedupe_key = 'request.step_failed:' || p_id);
  exception when others then
    null;   -- telling must never undo the messages the hand-over already sent
  end;
end $fn$;
revoke execute on function public.fn_sales_engineer_request_step_failed(bigint, text, text) from public, anon, authenticated;

-- ── 10. the sales engineer's reveal.paid / refund.paid handler: the LIVE body (pg_get_functiondef, 13 Nov 2026) with the
-- receipt's refund-window sentence and the two request steps added; nothing else changed ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_sales_engineer_acts_on_handoff(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  a public.agent_actions; d jsonb; t text;
  v_cust record; v_sup record; v_inq text; v_window int; v_chase int; v_min int; v_max int;
  v_tx public.transactions; v_amt text; v_req bigint; v_lines text; v_orig public.notifications;
  v_revealed text; v_rid text; v_request jsonb;
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
          || '. You can now message them directly in the app.'
          -- the refund window's end date, early in the receipt, when the accountant's hand-over carries it (W1, 13 Nov 2026)
          || coalesce(' ' || nullif(btrim(d->>'refund_window_sentence_en'), ''), '')
          || ' We track this reveal from the moment you paid: if the supplier has not responded within '
          || v_chase::text || ' working days we chase them for you and copy you; if there is still no response by working day '
          || v_window::text || ' the case is decided by our chief executive, and if the supplier never responded everything you paid is refunded in full. '
          || 'Banks usually take ' || v_min || '-' || v_max || ' working days to show a refund. You can also open the request and Report an issue at any time.',
        'اكتمل الكشف — ' || coalesce(v_sup.company_name, 'المورّد'),
        'أصبحت بيانات التواصل مع ' || coalesce(v_sup.company_name, 'المورّد') || ' متاحة لكم الآن، ويمكنكم مراسلته مباشرة من التطبيق. '
          || coalesce(nullif(btrim(d->>'refund_window_sentence_ar'), '') || ' ', '')
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
    -- THE REQUEST, after the messages (a_paid_reveal_closes_the_request_and_everyone_on_it_is_told.sql). Code, not a model:
    -- nothing at this step needs judgement. A failure is written into the answer the accountant reads and never un-sends
    -- the receipt or the chosen supplier's notice.
    begin
      v_request := public.fn_sales_engineer_records_reveal(p_id);
    exception when others then
      v_request := jsonb_build_object('acted', false, 'error', left(sqlerrm, 300));
      perform public.fn_sales_engineer_request_step_failed(p_id, 'reveal.paid', sqlerrm);
    end;
    return jsonb_build_object('customer_reachable', v_cust.email is not null,
                              'supplier_reachable', coalesce(v_sup.email, '') like '%@%',
                              'delivery_request', v_req, 'request', v_request);

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
    -- the request this refund belongs to (re-opened only where a reveal period was recorded and a live quotation remains)
    begin
      v_request := public.fn_sales_engineer_reopens_after_refund(p_id);
    exception when others then
      v_request := jsonb_build_object('reopened', false, 'error', left(sqlerrm, 300));
      perform public.fn_sales_engineer_request_step_failed(p_id, 'refund.paid', sqlerrm);
    end;
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false, 'request', v_request); end if;
    v_req := public.fn_sales_engineer_writes('refund_issued', 'customer', v_cust.email, (d->>'supplier_id')::bigint, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'Your QuotesDone refund of AED ' || (d->>'amount_aed') || ' has been issued',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'We have issued a refund of AED ' || (d->>'amount_aed') || ' — everything you paid on ' || v_revealed
        || ', the reveal fee and the card processing part together — to your original payment method, because the supplier did not respond within '
        || v_window::text || ' working days. Nothing is deducted.' || E'\n\n'
        || 'Banks and card issuers usually take ' || v_min || '–' || v_max || ' working days to show it on your statement. If it has not appeared after '
        || v_max || ' working days, reply to this email and we will trace it with the payment processor.' || E'\n\n'
        -- what the customer can do next follows what the request now is (re-opened above, or not)
        || case when coalesce((v_request->>'reopened')::boolean, false)
                then 'You can still open another of the quotations you received on this request while they remain valid.'
                else 'You are welcome to post the request again; we will introduce you to another supplier.' end,
      'أصدرنا استردادًا بقيمة ' || (d->>'amount_aed') || ' درهم',
      'أصدرنا لكم استردادًا بقيمة ' || (d->>'amount_aed') || ' درهم، أي كامل المبلغ المدفوع، إلى وسيلة الدفع الأصلية، إذ لم يردّ المورّد خلال '
        || v_window::text || ' أيام عمل. وقد يستغرق ظهوره في كشف حسابكم ' || v_min || '–' || v_max || ' يوم عمل.'
          || case when coalesce((v_request->>'reopened')::boolean, false)
                  then ' وما زال بإمكانكم فتح عرض آخر من العروض التي وصلتكم في هذا الطلب ما دامت سارية.' else '' end,
      '{}', 'refund_issued:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req, 'amount_aed', d->'amount_aed', 'request', v_request);

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
revoke execute on function public.fn_sales_engineer_acts_on_handoff(bigint) from public, anon, authenticated;
