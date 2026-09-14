-- THE ACCOUNTANT ANSWERS EVERY CARD DISPUTE BEFORE STRIPE CLOSES IT.
--
-- Assigned: accountant (duty 7 of the eight, founder 14 Sep 2026: "yea add them all").
--
-- WHAT WAS MEASURED (14 Sep 2026, production htdblwldjkcgjvmqkbeh and the repository):
--   * stripe_webhook handled no charge.dispute.* event and HANDLED_STRIPE_EVENTS
--     (supabase/functions/_shared/stripe_events.ts) listed none, so a chargeback would have been
--     decided against the company by default: Stripe closes an unanswered dispute as lost at due_by.
--   * Everything the evidence needs is already on record: the sale (transactions: quote, total charged,
--     Stripe invoice number and PDF in finance-docs), the reveal and the customer (customers), the
--     conversation after the reveal (messages), the supplier's first response (supplier_response_watch),
--     and proof the receipt was delivered (notifications with the provider's message id).
--
-- WHAT THIS BUILDS: public.stripe_dispute, written by stripe_webhook on every charge.dispute.* event
-- (DISPUTE_EVENTS joins HANDLED_STRIPE_EVENTS, so stripe_setup registers them) and by the accountant
-- runtime's daily read of GET /v1/disputes as a backstop. fn_accountant_dispute_evidence assembles the
-- evidence from those records; the runtime uploads the invoice PDF and submits at once. The CEO is told
-- at T-72h and T-24h if anything is still unsubmitted, and an unsubmitted dispute inside 72 hours, a
-- failed submission, or a dispute on a charge the books cannot find is a finding round the IT loop.
-- A TEST-mode dispute is recorded only when it is about a ZZ DEMO customer's payment.
--
--   node scripts/apply_sql.mjs scripts/sql/the_accountant_answers_every_card_dispute_before_stripe_closes_it.sql --apply --ddl

create table if not exists public.stripe_dispute (
  id                    text primary key,
  livemode              boolean     not null,
  charge_id             text,
  payment_intent        text,
  transaction_id        uuid references public.transactions(id),
  amount_fils           bigint      not null,
  currency              text        not null,
  reason                text,
  status                text        not null,
  evidence_due_by       timestamptz,
  evidence_submitted_at timestamptz,
  submission            jsonb,
  submit_error          text,
  alerted_72h_at        timestamptz,
  alerted_24h_at        timestamptz,
  outcome               text,
  closed_at             timestamptz,
  first_seen_at         timestamptz not null default now(),
  last_seen_at          timestamptz not null default now()
);
comment on table public.stripe_dispute is
  'Every Stripe dispute (chargeback) on a QuotesDone payment: recorded by stripe_webhook and the accountant runtime, answered by the accountant with evidence assembled from the sale, the reveal, the messages and the delivery records, before evidence_due_by.';
alter table public.stripe_dispute enable row level security;
drop policy if exists stripe_dispute_service_role_only on public.stripe_dispute;
create policy stripe_dispute_service_role_only on public.stripe_dispute as permissive for all to public using (false) with check (false);
revoke all on public.stripe_dispute from anon, authenticated;

-- ── 1. RECORDING A DISPUTE ───────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_dispute_record(p_dispute jsonb, p_livemode boolean)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_tx uuid; v_demo boolean; v_status text := p_dispute->>'status'; v_rep jsonb;
begin
  if coalesce(p_dispute->>'id', '') !~ '^(dp|du)_' or (p_dispute->>'amount') is null then
    raise exception 'fn_accountant_dispute_record: % is not a Stripe dispute object', left(p_dispute::text, 200);
  end if;
  select t.id, coalesce(c.is_demo, false) into v_tx, v_demo
    from public.transactions t left join public.customers c on c.id = t.customer_id
   where t.payment_ref = p_dispute->>'payment_intent' limit 1;
  -- A TEST-MODE DISPUTE MAY ONLY EVER TOUCH DEMO DATA (the rule stripe_webhook applies to every test event).
  if not p_livemode and not coalesce(v_demo, false) then
    return jsonb_build_object('ok', true, 'ignored', 'test-mode dispute not on a ZZ DEMO payment');
  end if;
  insert into public.stripe_dispute (id, livemode, charge_id, payment_intent, transaction_id, amount_fils, currency, reason, status,
                                     evidence_due_by, outcome, closed_at)
  values (p_dispute->>'id', p_livemode, p_dispute->>'charge', p_dispute->>'payment_intent', v_tx, (p_dispute->>'amount')::bigint,
          lower(p_dispute->>'currency'), p_dispute->>'reason', v_status,
          to_timestamp(nullif(p_dispute#>>'{evidence_details,due_by}', '')::bigint),
          case when v_status in ('won', 'lost', 'warning_closed') then v_status end,
          case when v_status in ('won', 'lost', 'warning_closed') then now() end)
  on conflict (id) do update
     set status = excluded.status, reason = excluded.reason, last_seen_at = now(),
         transaction_id = coalesce(stripe_dispute.transaction_id, excluded.transaction_id),
         evidence_due_by = coalesce(excluded.evidence_due_by, stripe_dispute.evidence_due_by),
         outcome = coalesce(excluded.outcome, stripe_dispute.outcome),
         closed_at = coalesce(stripe_dispute.closed_at, excluded.closed_at),
         -- Stripe says it has the evidence; keep our record of submitting it
         evidence_submitted_at = coalesce(stripe_dispute.evidence_submitted_at,
           case when (p_dispute#>>'{evidence_details,has_evidence}')::boolean and excluded.status = 'under_review' then now() end);
  if v_status in ('won', 'lost', 'warning_closed') then
    v_rep := public.fn_support_report_to_ceo('dispute_closed:' || (p_dispute->>'id'),
      case when v_status = 'lost' then 'elevated' else 'routine' end,
      'Card dispute ' || (p_dispute->>'id') || ' on AED ' || round((p_dispute->>'amount')::numeric / 100, 2) || ' closed: ' || v_status,
      jsonb_build_object('dispute', p_dispute->>'id', 'status', v_status, 'transaction_id', v_tx, 'reason', p_dispute->>'reason',
                         'livemode', p_livemode),
      '[]'::jsonb, 'Acknowledge. A lost dispute is money Stripe took back; the accountant has recorded the outcome.',
      p_review_in => interval '3 days', p_source_agent => 'accountant');
  end if;
  return jsonb_build_object('ok', true, 'dispute', p_dispute->>'id', 'transaction_id', v_tx, 'status', v_status);
end $fn$;
revoke execute on function public.fn_accountant_dispute_record(jsonb, boolean) from public, anon, authenticated;

-- ── 2. THE EVIDENCE, ASSEMBLED FROM THE RECORDS ──────────────────────────────────────────────────
-- Returns Stripe's evidence text fields (evidence[<field>]) and the stored invoice PDF the runtime
-- uploads as evidence[receipt]. Every sentence is built from a row; nothing is asserted without one.
create or replace function public.fn_accountant_dispute_evidence(p_id text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  d public.stripe_dispute; t public.transactions; c record; v_inq text; v_sup text; v_window int;
  v_msgs int; v_sup_msgs int; v_first timestamptz; v_deliv text; v_log text;
begin
  select * into d from public.stripe_dispute where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no dispute ' || p_id); end if;
  select * into t from public.transactions where id = d.transaction_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'dispute ' || p_id || ' names payment ' || coalesce(d.payment_intent, '?') || ', which no transaction records'); end if;
  select full_name, email into c from public.customers where id = t.customer_id;
  select summary into v_inq from public.inquiries where id = t.inquiry_id;
  select company_name into v_sup from public.leads where id = t.supplier_id;
  select refund_window_working_days into v_window from public.pricing_config order by id limit 1;
  select count(*), count(*) filter (where sender = 'supplier') into v_msgs, v_sup_msgs
    from public.messages where inquiry_id = t.inquiry_id and supplier_id = t.supplier_id and created_at >= t.revealed_at;
  select min(first_response_at) into v_first from public.supplier_response_watch where transaction_id = t.id;
  select string_agg(n.type || ' email to ' || n.to_role || ' sent ' || to_char(n.sent_at at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI')
                    || ' (provider id ' || n.provider_message_id || ')', '; ' order by n.sent_at)
    into v_deliv from public.notifications n
   where n.quote_id = t.quote_id and n.status = 'sent' and coalesce(n.provider_message_id, '') <> '';
  v_log := 'Reveal paid ' || to_char(t.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' (Dubai), payment ' || t.payment_ref
        || '. The supplier''s contact details were released in the customer''s QuotesDone portal at that moment. '
        || v_msgs || ' portal message(s) exchanged after the reveal, ' || v_sup_msgs || ' from the supplier'
        || coalesce('; supplier first responded ' || to_char(v_first at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI'), '') || '.';
  return jsonb_build_object('ok', true, 'dispute', d.id, 'livemode', d.livemode, 'transaction_id', t.id,
    'fields', jsonb_strip_nulls(jsonb_build_object(
      'customer_name', c.full_name,
      'customer_email_address', c.email,
      'service_date', to_char(t.revealed_at at time zone 'Asia/Dubai', 'YYYY-MM-DD'),
      'product_description', 'A paid reveal on QuotesDone, a UAE procurement marketplace: the customer paid to release the contact details of '
        || coalesce(v_sup, 'a supplier') || ', whose quote they chose for their request "' || left(coalesce(v_inq, 'a procurement request'), 200)
        || '". The charge is the 3% reveal fee plus card processing, AED ' || coalesce(t.total_charged, t.reveal_fee)
        || ', and is a digital service delivered at the moment of payment.',
      'access_activity_log', v_log,
      'refund_policy_disclosure', 'The customer''s receipt and the terms state that if the supplier does not respond within '
        || coalesce(v_window, 5) || ' working days the customer is refunded everything they paid. Refund status of this payment: '
        || coalesce(t.refund_status, 'none requested') || '.',
      'uncategorized_text', 'Stripe invoice ' || coalesce(t.stripe_invoice_number, t.stripe_invoice_id, 'not recorded')
        || ' for AED ' || coalesce(t.total_charged, t.reveal_fee) || ' (reveal fee AED ' || t.reveal_fee
        || coalesce(', card processing AED ' || t.processing_fee, '') || '). Delivery records: '
        || coalesce(v_deliv, 'no provider-confirmed delivery on record') || '.')),
    'receipt', case when coalesce(t.doc_path, '') <> '' then jsonb_build_object('bucket', 'finance-docs', 'path', t.doc_path,
                                                                                'name', coalesce(t.doc_name, 'invoice.pdf')) end);
end $fn$;
revoke execute on function public.fn_accountant_dispute_evidence(text) from public, anon, authenticated;

create or replace function public.fn_accountant_disputes_to_submit()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(jsonb_agg(public.fn_accountant_dispute_evidence(d.id) order by d.evidence_due_by), '[]'::jsonb)
    from public.stripe_dispute d
   where d.status in ('needs_response', 'warning_needs_response') and d.evidence_submitted_at is null
     and (d.evidence_due_by is null or d.evidence_due_by > now()) and d.transaction_id is not null;
$fn$;
revoke execute on function public.fn_accountant_disputes_to_submit() from public, anon, authenticated;

create or replace function public.fn_accountant_dispute_submitted(p_id text, p_ok boolean, p_response jsonb, p_error text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  update public.stripe_dispute
     set evidence_submitted_at = case when p_ok then now() else evidence_submitted_at end,
         submission = p_response, submit_error = case when p_ok then null else left(p_error, 600) end,
         status = coalesce(case when p_ok then p_response->>'status' end, status), last_seen_at = now()
   where id = p_id;
  if not found then raise exception 'no dispute %', p_id; end if;
  return jsonb_build_object('ok', true, 'dispute', p_id, 'submitted', p_ok);
end $fn$;
revoke execute on function public.fn_accountant_dispute_submitted(text, boolean, jsonb, text) from public, anon, authenticated;

-- ── 3. THE DUTY: the clock, the CEO, and the loop ────────────────────────────────────────────────
create or replace function public.fn_accountant_disputes_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare d record; v_items jsonb := '[]'::jsonb; v_left interval; n_alert int := 0; v_rep jsonb; v_demo boolean;
begin
  for d in select s.*, coalesce(c.is_demo, false) demo from public.stripe_dispute s
             left join public.transactions t on t.id = s.transaction_id left join public.customers c on c.id = t.customer_id
            where s.closed_at is null loop
    v_demo := d.demo or not d.livemode;
    v_left := d.evidence_due_by - now();
    if d.evidence_submitted_at is null and d.status in ('needs_response', 'warning_needs_response') and d.evidence_due_by is not null then
      if v_left <= interval '24 hours' and d.alerted_24h_at is null then
        v_rep := public.fn_support_report_to_ceo('dispute:' || d.id || ':t24', 'critical',
          'Card dispute ' || d.id || ' (AED ' || round(d.amount_fils / 100.0, 2) || ') is unanswered and Stripe closes it in under 24 hours',
          to_jsonb(d) - 'demo', '[]'::jsonb,
          'Decide now: the accountant submits the evidence it holds, or record why the dispute is accepted. Unanswered, Stripe decides it against us at ' || d.evidence_due_by || '.',
          p_review_in => interval '4 hours', p_source_agent => 'accountant');
        update public.stripe_dispute set alerted_24h_at = now() where id = d.id;
        n_alert := n_alert + 1;
      elsif v_left <= interval '72 hours' and d.alerted_72h_at is null then
        v_rep := public.fn_support_report_to_ceo('dispute:' || d.id || ':t72', 'serious',
          'Card dispute ' || d.id || ' (AED ' || round(d.amount_fils / 100.0, 2) || ') is unanswered with under 72 hours left',
          to_jsonb(d) - 'demo', '[]'::jsonb,
          'The accountant is submitting the evidence; this is the 72-hour warning. Stripe''s deadline is ' || d.evidence_due_by || '.',
          p_review_in => interval '12 hours', p_source_agent => 'accountant');
        update public.stripe_dispute set alerted_72h_at = now() where id = d.id;
        n_alert := n_alert + 1;
      end if;
      if v_left <= interval '72 hours' or d.submit_error is not null or d.transaction_id is null then
        v_items := v_items || jsonb_build_object('item', d.id, 'owner_seat', 'accountant', 'subject', 'stripe_dispute',
          'title', 'Card dispute ' || d.id || ' on AED ' || round(d.amount_fils / 100.0, 2) || ' is not answered'
                   || case when d.transaction_id is null then ': the books have no sale for payment ' || coalesce(d.payment_intent, '?')
                           when d.submit_error is not null then ': Stripe refused the evidence (' || left(d.submit_error, 120) || ')'
                           else '' end || '; Stripe closes it at ' || to_char(d.evidence_due_by at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai',
          'blast', 'customer_facing', 'affected', 0, 'demo', v_demo, 'evidence', to_jsonb(d) - 'demo');
      end if;
    end if;
  end loop;
  return jsonb_build_object('open', (select count(*) from public.stripe_dispute where closed_at is null),
    'ceo_alerts', n_alert, 'findings', public.fn_accountant_duty_settle('disputes', v_items));
end $fn$;
revoke execute on function public.fn_accountant_disputes_tick() from public, anon, authenticated;
