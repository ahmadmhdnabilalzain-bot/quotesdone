-- A CARD DISPUTE CARRIES THE SIGNED TERMS, THE FEE BASIS AND THE CUSTOMER'S OWN WORDS.
--
-- Assigned: accountant. Founder approved 13 Oct 2026.
--
-- WHAT WAS MEASURED (13 Oct 2026, production htdblwldjkcgjvmqkbeh and the repository):
--   * fn_accountant_dispute_evidence (the_accountant_answers_every_card_dispute_before_stripe_closes_it.sql)
--     sent the sale, the reveal time, the invoice and the email deliveries, but NOT: the customer's signed
--     terms (customers.tos_version, tos_accepted_at, tos_ip, tos_sha256, and the certificate PDF at
--     customers.signed_terms_path in the 'signed-terms' bucket), the fee basis the customer saw before
--     paying ("3% of AED X", the Checkout line name), the refund policy's own text (legal_documents
--     'refund-policy', v1.8, 7,635 characters of HTML), WhatsApp deliveries by channel, or anything the
--     customer wrote. public.stripe_dispute held 0 rows.
--   * Nothing marked a customer who disputes again.
--
-- WHAT THIS CHANGES:
--   1. fn_accountant_dispute_evidence adds all of the above. The certificate PDF is returned as
--      'terms_certificate' and the runtime uploads it as evidence[customer_signature]. Two keys in
--      'fields' are for the CEO's review only (ceo_prior_disputes, ceo_summary): disputeEvidenceForm
--      sends only Stripe's own field names, so they never leave the estate.
--   2. customers.disputes_filed / customers.repeat_disputer (>= 2), kept by a trigger on stripe_dispute
--      whenever a dispute is recorded or matched to its sale.
--
--   node scripts/apply_sql.mjs scripts/sql/a_card_dispute_carries_the_signed_terms_the_fee_basis_and_the_customers_own_words.sql --apply --ddl

-- ── 2. THE REPEAT-DISPUTER FLAG ─────────────────────────────────────────────────────────────────
alter table public.customers add column if not exists disputes_filed integer not null default 0;
alter table public.customers add column if not exists repeat_disputer boolean generated always as (disputes_filed >= 2) stored;
comment on column public.customers.disputes_filed is
  'Card disputes (public.stripe_dispute) on this customer''s payments, kept by trg_stripe_dispute_counts_the_customer.';
comment on column public.customers.repeat_disputer is
  'True once a customer has disputed two or more payments. Shown to the CEO in every dispute review.';

create or replace function public.fn_stripe_dispute_counts_the_customer()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_c uuid;
begin
  select customer_id into v_c from public.transactions where id = new.transaction_id;
  if v_c is null then return new; end if;
  update public.customers c
     set disputes_filed = (select count(*) from public.stripe_dispute d join public.transactions t on t.id = d.transaction_id
                            where t.customer_id = v_c)
   where c.id = v_c;
  return new;
end $fn$;
revoke execute on function public.fn_stripe_dispute_counts_the_customer() from public, anon, authenticated;

drop trigger if exists trg_stripe_dispute_counts_the_customer on public.stripe_dispute;
create trigger trg_stripe_dispute_counts_the_customer
  after insert or update of transaction_id on public.stripe_dispute
  for each row execute function public.fn_stripe_dispute_counts_the_customer();

-- ── 1. THE EVIDENCE ──────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_dispute_evidence(p_id text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  d public.stripe_dispute; t public.transactions; c public.customers; v_inq text; v_job text; v_sup text; v_window int;
  v_msgs int; v_sup_msgs int; v_first timestamptz; v_deliv text; v_log text; v_terms text; v_basis text;
  v_policy text; v_policy_v text; v_words text; v_wa text; v_prior int;
begin
  select * into d from public.stripe_dispute where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no dispute ' || p_id); end if;
  select * into t from public.transactions where id = d.transaction_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'dispute ' || p_id || ' names payment ' || coalesce(d.payment_intent, '?') || ', which no transaction records'); end if;
  select * into c from public.customers where id = t.customer_id;
  select summary, coalesce(rfq_no::text, upper(left(id::text, 8))) into v_inq, v_job from public.inquiries where id = t.inquiry_id;
  select company_name into v_sup from public.leads where id = t.supplier_id;
  select refund_window_working_days into v_window from public.pricing_config order by id limit 1;
  select count(*), count(*) filter (where sender = 'supplier') into v_msgs, v_sup_msgs
    from public.messages where inquiry_id = t.inquiry_id and supplier_id = t.supplier_id and created_at >= t.revealed_at;
  select min(first_response_at) into v_first from public.supplier_response_watch where transaction_id = t.id;
  -- every provider-confirmed delivery about this sale, email and WhatsApp alike
  select string_agg(coalesce(n.channel, 'email') || ' ' || n.type || ' to ' || coalesce(n.to_role, '?') || ' sent '
                    || to_char(n.sent_at at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' (provider id ' || n.provider_message_id || ')',
                    '; ' order by n.sent_at)
    into v_deliv from public.notifications n
   where n.quote_id = t.quote_id and n.status = 'sent' and coalesce(n.provider_message_id, '') <> '';

  -- the fee the customer saw before paying: the Checkout line reads "Reveal fee (3% of AED <quote>)"
  v_basis := 'Fee shown to the customer before payment: AED ' || t.reveal_fee
    || case when coalesce(t.quote_amount, 0) > 0
            then ' = ' || regexp_replace(round(t.reveal_fee / t.quote_amount * 100, 2)::text, '\.?0+$', '') || '% of AED ' || t.quote_amount
                 || ', the supplier''s quoted price' else '' end
    || '. Total charged AED ' || coalesce(t.total_charged, t.reveal_fee) || '.';

  v_terms := case when c.tos_accepted_at is null then 'No terms acceptance is recorded for this customer.'
    else 'The customer accepted the QuotesDone customer terms ' || coalesce(c.tos_version, '(version not recorded)') || ' on '
      || to_char(c.tos_accepted_at at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' (Dubai)'
      || coalesce(' from IP ' || c.tos_ip, '') || coalesce(', document SHA-256 ' || c.tos_sha256, '')
      || case when coalesce(c.signed_terms_path, '') <> '' then '; the signed acceptance certificate is on record' else '' end
      || ', before paying for this reveal.' end;

  select version, left(btrim(regexp_replace(regexp_replace(replace(replace(body_html, '&amp;', '&'), '&nbsp;', ' '),
                                                           '<[^>]+>', ' ', 'g'), '\s+', ' ', 'g')), 15000)
    into v_policy_v, v_policy from public.legal_documents where slug = 'refund-policy';

  -- the customer's own words: portal messages on this request, and WhatsApp messages from their number
  select string_agg(to_char(m.created_at at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' portal: ' || left(m.body, 300), E'\n' order by m.created_at)
    into v_words
    from (select * from public.messages where inquiry_id = t.inquiry_id and sender = 'customer' order by created_at desc limit 20) m;
  select string_agg(to_char(w.created_at at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' WhatsApp: ' || left(w.inbound, 300), E'\n' order by w.created_at)
    into v_wa
    from (select * from public.wa_messages
           where coalesce(inbound, '') <> ''
             and right(regexp_replace(wa_from, '\D', '', 'g'), 9) <> ''
             and right(regexp_replace(wa_from, '\D', '', 'g'), 9) in (right(regexp_replace(coalesce(c.whatsapp_phone, ''), '\D', '', 'g'), 9),
                                                                      right(regexp_replace(coalesce(c.phone, ''), '\D', '', 'g'), 9))
           order by created_at desc limit 20) w;

  select count(*) into v_prior from public.stripe_dispute x join public.transactions y on y.id = x.transaction_id
   where y.customer_id = t.customer_id and x.id <> d.id;

  v_log := 'Reveal paid ' || to_char(t.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' (Dubai), payment ' || t.payment_ref
        || '. The supplier''s contact details were released in the customer''s QuotesDone portal at that moment. '
        || v_msgs || ' portal message(s) exchanged after the reveal, ' || v_sup_msgs || ' from the supplier'
        || coalesce('; supplier first responded ' || to_char(v_first at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI'), '') || '. '
        || v_terms;

  return jsonb_build_object('ok', true, 'dispute', d.id, 'livemode', d.livemode, 'transaction_id', t.id,
    'fields', jsonb_strip_nulls(jsonb_build_object(
      'customer_name', c.full_name,
      'customer_email_address', c.email,
      'service_date', to_char(t.revealed_at at time zone 'Asia/Dubai', 'YYYY-MM-DD'),
      'product_description', 'A paid reveal on QuotesDone, a UAE procurement marketplace' || coalesce(', job ' || v_job, '')
        || ': the customer paid to release the contact details of ' || coalesce(v_sup, 'a supplier')
        || ', whose quote they chose for their request "' || left(coalesce(v_inq, 'a procurement request'), 200)
        || '". ' || v_basis || ' It is a digital service delivered at the moment of payment.',
      'access_activity_log', v_log,
      'refund_policy_disclosure', 'The customer''s receipt and the terms state that if the supplier does not respond within '
        || coalesce(v_window, 5) || ' working days the customer is refunded everything they paid. Refund status of this payment: '
        || coalesce(t.refund_status, 'none requested') || '.'
        || coalesce(E'\n\nQuotesDone refund policy ' || v_policy_v || ', as published:\n' || v_policy, ''),
      'uncategorized_text', 'Checkout record: payment ' || coalesce(t.payment_ref, '?') || ', Stripe invoice '
        || coalesce(t.stripe_invoice_number, t.stripe_invoice_id, 'not recorded') || ', AED ' || coalesce(t.total_charged, t.reveal_fee)
        || ', paid ' || to_char(t.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' (Dubai). ' || v_basis
        || E'\nDelivery records: ' || coalesce(v_deliv, 'no provider-confirmed delivery on record') || '.'
        || E'\nTerms: ' || v_terms
        || E'\nThe customer''s own messages: ' || coalesce(nullif(concat_ws(E'\n', v_words, v_wa), ''), 'none on record') || '.',
      -- for the CEO's review only; disputeEvidenceForm never sends a field Stripe does not name
      'ceo_prior_disputes', v_prior,
      'ceo_summary', 'AED ' || round(d.amount_fils / 100.0, 2) || ', reason ' || coalesce(d.reason, '?') || ', due '
        || coalesce(to_char(d.evidence_due_by at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' Dubai', '?')
        || case when v_prior > 0 then '. REPEAT DISPUTER: ' || v_prior || ' earlier dispute(s) by this customer' else '' end
        || case when c.tos_accepted_at is null then '. No terms acceptance on record' else '' end || '.')),
    'receipt', case when coalesce(t.doc_path, '') <> '' then jsonb_build_object('bucket', 'finance-docs', 'path', t.doc_path,
                                                                                'name', coalesce(t.doc_name, 'invoice.pdf')) end,
    'terms_certificate', case when coalesce(c.signed_terms_path, '') <> '' then jsonb_build_object('bucket', 'signed-terms',
                                                                                'path', c.signed_terms_path, 'name', 'signed-terms-certificate.pdf') end);
end $fn$;
-- CREATE OR REPLACE keeps the closed ACL; revoked again so a fresh database is closed too.
revoke execute on function public.fn_accountant_dispute_evidence(text) from public, anon, authenticated;
