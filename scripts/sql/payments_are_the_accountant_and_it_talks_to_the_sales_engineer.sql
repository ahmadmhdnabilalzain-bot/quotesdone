-- PAYMENTS ARE THE ACCOUNTANT'S, AND THE SEATS TALK TO EACH OTHER ABOUT MONEY.
--
-- Assigned: accountant (every payment path), with sales_engineer (the voice to customers and
-- suppliers) and customer_support (the only seat that sends email or WhatsApp). Carried out for the ceo.
--
-- The founder, 14 Sep 2026, verbatim:
--   "anything related to payment is under the accountant agent. and the accountant need to be in
--    communication back and forth with the sales agent. its one company eventually."
--   "the only agent who uses the whatsapp and email is the customer support agent. so he should be
--    always up to date with that is going on."
--
-- MEASURED BEFORE WRITING (14 Sep 2026, production htdblwldjkcgjvmqkbeh):
--   function_owner   all eleven payment slugs already read 'accountant' (stripe_checkout,
--                    stripe_confirm, stripe_webhook, stripe_setup, stripe_setup_page, supplier_pay,
--                    reveal_invoice, quote_pdf, refunds_api, refund_flow, accountant). No payment slug
--                    has an llm_seat_binding. What was NOT the accountant's: supplier_api's
--                    pay_registration (a Stripe checkout inside a sales-engineer portal function) --
--                    moved to supplier_pay in the same change -- and every agent_runs row a payment
--                    function writes, which lands under its own slug ('stripe_webhook', 'fn:refunds_api')
--                    and so never reached the accountant's line on fn_ceo_seat_board.
--   the bus          company_event exists (the estate's one event stream) and event_subscription
--                    holds 0 rows; fn_event_dispatch delivers only through org_agents.department and
--                    mints org_tasks, and both were removed on 7 Sep, so it cannot carry a seat-to-seat
--                    handoff. agent_actions already carries kind 'handoff' in fn_agent_handoff_inbox
--                    and fn_agent_inbox_closable_kinds, with 0 rows. That is the existing mechanism,
--                    and it is the one used here: no new queue table.
--   handoffs         0. Nothing connected a payment to the seat that must tell someone about it.
--
-- THE SHAPE. A handoff is one agent_actions row: agent = the receiving seat, kind = 'handoff',
-- detail = {type, from, to, subject_table, subject_id, ...payload ids}, status pending -> done (or
-- failed, or pending with detail.awaiting while the seat waits on the outside world). The receiving
-- seat ACTS inside fn_seat_handoff_act: the accountant reads and checks the money, the sales engineer
-- writes the customer- or supplier-facing words, customer_support delivers them through the outbox
-- (public.notifications) and watches for the reply. Every state change is also written to
-- public.company_event as event_type 'handoff.<type>.<status>', so the one event stream the estate
-- already has is the timeline support reads to stay up to date.
--
--   node scripts/apply_sql.mjs scripts/sql/payments_are_the_accountant_and_it_talks_to_the_sales_engineer.sql --apply --ddl

-- ── 0. HIS WORDS, IN THE REGISTER ─────────────────────────────────────────────────────────────────
insert into public.founder_instruction (said_at, instruction, subject, status, evidence)
select '2026-09-14T00:00:00Z', x.i, x.s, 'done',
       'scripts/sql/payments_are_the_accountant_and_it_talks_to_the_sales_engineer.sql; scripts/checks/payments_are_the_accountant.test.mjs'
  from (values
    ('anything related to payment is under the accountant agent. and the accountant need to be in communication back and forth with the sales agent. its one company eventually.', 'payments are the accountant'),
    ('the only agent who uses the whatsapp and email is the customer support agent. so he should be always up to date with that is going on.', 'support is the only sender')) x(i, s)
 where not exists (select 1 from public.founder_instruction f where f.instruction = x.i);

-- ── 1. POSITIVE CONTROL: every payment slug is the accountant's ──────────────────────────────────
do $pc$
declare v_bad text;
begin
  select string_agg(s || '=' || coalesce(fo.owner, '(none)'), ', ') into v_bad
    from unnest(array['stripe_checkout','stripe_confirm','stripe_webhook','stripe_setup','stripe_setup_page',
                      'supplier_pay','reveal_invoice','quote_pdf','refunds_api','refund_flow','accountant']) s
    left join public.function_owner fo on fo.function_slug = s
   where coalesce(fo.owner, '') <> 'accountant';
  if v_bad is not null then raise exception 'A PAYMENT SLUG IS NOT THE ACCOUNTANT''S: %', v_bad; end if;
end $pc$;

update public.function_owner
   set note = 'Stripe checkout sessions for every amount a supplier pays: outstanding charges (supplier_dues) and, since 14 Sep 2026, the yearly registration fee (moved here from supplier_api.pay_registration). Creates sessions only; stripe_webhook alone marks anything paid. Payments are the accountant''s (founder, 14 Sep 2026).'
 where function_slug = 'supplier_pay';

-- ── 2. THE LIST OF CONVERSATIONS ─────────────────────────────────────────────────────────────────
-- Mirrored in supabase/functions/_shared/payment_handoffs.ts; the check fails if they differ.
create or replace function public.fn_seat_handoff_types()
returns table(type text, from_seat text, to_seat text, meaning text)
language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  values
    ('reveal.paid',              'accountant',       'sales_engineer',   'A reveal charge settled at Stripe: tell the customer the contact is released and the supplier that they were revealed.'),
    ('payment.failed',           'accountant',       'sales_engineer',   'A reveal checkout expired or failed: tell the customer nothing was charged and how to try again.'),
    ('payment.received',         'accountant',       'sales_engineer',   'A supplier paid an outstanding charge or the registration fee: confirm it to them.'),
    ('refund.request_checked',   'accountant',       'sales_engineer',   'The books checked a refund request: acknowledge it to the customer.'),
    ('refund.paid',              'accountant',       'sales_engineer',   'A refund settled: tell the customer what came back and when the bank shows it.'),
    ('refund.declined',          'accountant',       'sales_engineer',   'A refund was declined: tell the customer why.'),
    ('refund.in_progress',       'accountant',       'sales_engineer',   'A refund is approved but not settled after a retry: tell the customer it is in progress.'),
    ('nonresponse.charge_raised','accountant',       'sales_engineer',   'The non-response charge was raised: tell the supplier the figures.'),
    ('charge.corrected',         'accountant',       'sales_engineer',   'A charge already sent was wrong: send a correction to whoever got the original.'),
    ('subscription.due',         'accountant',       'sales_engineer',   'The yearly registration fee fell due: tell the supplier.'),
    ('billing.answer',           'accountant',       'sales_engineer',   'The books answered a billing question: relay it.'),
    ('charge.dispute_answer',    'accountant',       'sales_engineer',   'The books checked a disputed charge: relay the result to the supplier.'),
    ('refund.requested',         'sales_engineer',   'accountant',       'A customer asked for a refund in the portal: check the money behind it.'),
    ('billing.question',         'sales_engineer',   'accountant',       'A customer or supplier asked about a charge, an invoice or a refund: read the books.'),
    ('charge.disputed',          'sales_engineer',   'accountant',       'A supplier disputed a charge: recompute it from the refund record.'),
    ('refund.remediate',         'ceo',              'accountant',       'The CEO refused approval on a money check the accountant owns: fix it and report back.'),
    ('refund.remediate',         'ceo',              'sales_engineer',   'The CEO refused approval on a ladder check the sales engineer owns: fix it and report back.'),
    ('incident.fix',             'ceo',              'accountant',       'Post-payment re-verification found a mismatch: apply the fix the playbook names.'),
    ('delivery.request',         'sales_engineer',   'customer_support', 'Deliver these words to a customer or supplier through the outbox, and watch for the reply when asked.'),
    ('delivery.request',         'ceo',              'customer_support', 'Deliver this summary to the founder on his command channel.'),
    ('delivery.request',         'accountant',       'customer_support', 'Deliver this money exception to the founder on his command channel.'),
    ('delivery.result',          'customer_support', 'sales_engineer',   'What came back: proof the supplier responded, or confirmation that nothing did.')
$fn$;
revoke execute on function public.fn_seat_handoff_types() from public, anon, authenticated;

-- ── 3. THE EVENT STREAM SUPPORT READS ────────────────────────────────────────────────────────────
create or replace function public.fn_seat_handoff_event(p_id bigint, p_status text)
returns void language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions where id = p_id;
  if not found then return; end if;
  insert into public.company_event (event_type, entity_type, entity_id, actor, payload)
  values ('handoff.' || coalesce(a.detail->>'type', '?') || '.' || p_status, 'agent_actions', a.id::text,
          coalesce(a.detail->>'from', 'system'),
          jsonb_build_object('handoff_id', a.id, 'type', a.detail->>'type', 'from', a.detail->>'from',
                             'to', a.agent, 'status', p_status, 'subject_table', a.detail->>'subject_table',
                             'subject_id', a.detail->>'subject_id', 'refund_id', a.detail->>'refund_id',
                             'transaction_id', a.detail->>'transaction_id', 'awaiting', a.detail->>'awaiting'));
end $fn$;
revoke execute on function public.fn_seat_handoff_event(bigint, text) from public, anon, authenticated;

-- ── 4. SENDING A HANDOFF ─────────────────────────────────────────────────────────────────────────
-- Idempotent on (receiving seat, type, subject): a re-fired trigger or a retried Stripe webhook must
-- not tell a customer twice. A FAILED handoff does not block a new one -- that is the retry path.
create or replace function public.fn_seat_handoff(
  p_from text, p_to text, p_type text, p_subject_table text, p_subject_id text, p_payload jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint; v_key text := p_type || ':' || p_subject_id;
begin
  if not exists (select 1 from public.fn_seat_handoff_types() h
                  where h.type = p_type and h.from_seat = p_from and h.to_seat = p_to) then
    raise exception 'no such handoff: % from % to % (fn_seat_handoff_types lists every conversation the seats have)', p_type, p_from, p_to;
  end if;
  if coalesce(btrim(p_subject_id), '') = '' then raise exception 'a handoff must name its subject'; end if;

  select id into v_id from public.agent_actions
   where kind = 'handoff' and agent = p_to and target_id = v_key and status <> 'failed'
   order by id limit 1;
  if v_id is not null then return v_id; end if;

  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values (p_to, 'handoff', 'pending', 'low',
          left(p_type || ' from ' || p_from || ' about ' || p_subject_table || ' ' || p_subject_id, 200),
          coalesce(p_payload, '{}'::jsonb) || jsonb_build_object(
            'type', p_type, 'from', p_from, 'from_name', p_from, 'to', p_to,
            'subject_table', p_subject_table, 'subject_id', p_subject_id),
          p_subject_table, v_key)
  returning id into v_id;
  perform public.fn_seat_handoff_event(v_id, 'sent');

  -- THE RECEIVING SEAT ACTS NOW. A failure is recorded on the row and in the stream and never
  -- rolls back the money event that raised it: a refund that settled stays settled.
  begin
    perform public.fn_seat_handoff_act(v_id);
  exception when others then
    update public.agent_actions
       set status = 'failed', decided_at = now(),
           detail = detail || jsonb_build_object('error', left(sqlerrm, 500))
     where id = v_id;
    perform public.fn_seat_handoff_event(v_id, 'failed');
  end;
  return v_id;
end $fn$;
revoke execute on function public.fn_seat_handoff(text, text, text, text, text, jsonb) from public, anon, authenticated;

create or replace function public.fn_seat_handoff_act(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; v jsonb;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff' for update;
  if not found then raise exception 'no handoff %', p_id; end if;
  if a.status = 'done' then return a.evidence; end if;

  v := case a.agent
         when 'sales_engineer'   then public.fn_sales_engineer_acts_on_handoff(p_id)
         when 'accountant'       then public.fn_accountant_acts_on_handoff(p_id)
         when 'customer_support' then public.fn_customer_support_acts_on_handoff(p_id)
         else null end;
  if v is null then raise exception 'seat % has no handler for %', a.agent, a.detail->>'type'; end if;

  if v ? 'waiting' then
    update public.agent_actions
       set detail = detail || jsonb_build_object('awaiting', v->>'waiting'), evidence = v
     where id = p_id;
    perform public.fn_seat_handoff_event(p_id, 'waiting');
    return v;
  end if;
  perform public.fn_seat_handoff_complete(p_id, v);
  return v;
end $fn$;
revoke execute on function public.fn_seat_handoff_act(bigint) from public, anon, authenticated;

-- A seat reports back: evidence attached, row done, and the loop that was waiting on it moves.
create or replace function public.fn_seat_handoff_complete(p_id bigint, p_evidence jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions;
begin
  update public.agent_actions
     set status = 'done', decided_at = now(), decided_by = agent,
         evidence = coalesce(p_evidence, '{}'::jsonb),
         detail = detail - 'awaiting'
   where id = p_id and kind = 'handoff' and status <> 'done'
  returning * into a;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no open handoff ' || p_id); end if;
  perform public.fn_seat_handoff_event(p_id, 'done');

  if a.detail->>'type' = 'refund.remediate' and (a.detail->>'refund_id') is not null then
    perform public.fn_ceo_refund_loop_advance((a.detail->>'refund_id')::bigint);
  elsif a.detail->>'type' = 'incident.fix' and (a.detail->>'incident_id') is not null then
    perform public.fn_ceo_incident_advance((a.detail->>'incident_id')::bigint);
  end if;
  return jsonb_build_object('ok', true, 'handoff_id', p_id, 'type', a.detail->>'type');
end $fn$;
revoke execute on function public.fn_seat_handoff_complete(bigint, jsonb) from public, anon, authenticated;

-- ── 5. THE SALES ENGINEER WRITES; SUPPORT CARRIES ────────────────────────────────────────────────
-- Every customer- or supplier-facing word is composed here in the sales engineer's voice and handed
-- to customer_support as a delivery request. The accountant is never named to a customer or supplier.
create or replace function public.fn_sales_engineer_writes(
  p_msg_type text, p_role text, p_email text, p_lead bigint, p_customer uuid, p_inquiry uuid, p_quote uuid,
  p_subject_en text, p_body_en text, p_subject_ar text default null, p_body_ar text default null,
  p_cc text[] default '{}', p_subject_id text default null, p_watch_until timestamptz default null,
  p_extra jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_locale text;
begin
  if p_role = 'customer' and p_customer is not null then
    select locale into v_locale from public.customers where id = p_customer;
  elsif p_role = 'supplier' and p_lead is not null then
    select locale into v_locale from public.leads where id = p_lead;
  end if;
  return public.fn_seat_handoff('sales_engineer', 'customer_support', 'delivery.request', 'notifications',
    coalesce(p_subject_id, p_msg_type || ':' || coalesce(p_quote::text, p_inquiry::text, p_lead::text, p_customer::text, 'x')),
    coalesce(p_extra, '{}'::jsonb) || jsonb_build_object(
      'msg_type', p_msg_type, 'recipient_role', p_role, 'to_email', p_email, 'cc', to_jsonb(coalesce(p_cc, '{}'::text[])),
      'supplier_id', p_lead, 'customer_id', p_customer, 'inquiry_id', p_inquiry, 'quote_id', p_quote,
      'locale', coalesce(v_locale, 'en'),
      'subject_en', p_subject_en, 'body_en', p_body_en || E'\n\nQuotesDone sales engineer',
      'subject_ar', p_subject_ar,
      'body_ar', case when p_body_ar is null then null else p_body_ar || E'\n\nمهندس المبيعات في QuotesDone' end,
      'watch_until', p_watch_until));
end $fn$;
revoke execute on function public.fn_sales_engineer_writes(text, text, text, bigint, uuid, uuid, uuid, text, text, text, text, text[], text, timestamptz, jsonb) from public, anon, authenticated;

create or replace function public.fn_sales_engineer_acts_on_handoff(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  a public.agent_actions; d jsonb; t text;
  v_cust record; v_sup record; v_inq text; v_window int; v_chase int; v_min int; v_max int;
  v_tx public.transactions; v_amt text; v_req bigint; v_lines text; v_orig public.notifications;
  v_revealed text; v_rid text;
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
          || '. You can now message them directly in the app. We track this reveal from the moment you paid: if the supplier has not responded within '
          || v_chase::text || ' working days we chase them for you and copy you; if there is still no response by working day '
          || v_window::text || ' the case is decided by our chief executive, and if the supplier never responded everything you paid is refunded in full. '
          || 'Banks usually take ' || v_min || '-' || v_max || ' working days to show a refund. You can also open the request and Report an issue at any time.',
        'تم تأكيد الكشف — ' || coalesce(v_sup.company_name, 'المورّد'),
        'أصبحت بيانات التواصل مع ' || coalesce(v_sup.company_name, 'المورّد') || ' متاحة لك الآن، ويمكنك مراسلته مباشرة من التطبيق. '
          || 'نتابع هذا الكشف منذ لحظة الدفع: إن لم يردّ المورّد خلال ' || v_chase::text || ' أيام عمل نتواصل معه نيابةً عنك مع نسخة لك، '
          || 'وإن لم يردّ حتى يوم العمل ' || v_window::text || ' يقرّر رئيسنا التنفيذي في الحالة، وإن لم يردّ المورّد إطلاقًا نردّ إليك كامل ما دفعته.',
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
          || ' our chief executive decides the case, the customer is refunded, and the amount refunded plus an AED 250 administrative fee and 9% p.a. interest is recovered from your account.',
        'كشف عميل عن عرضك على QuotesDone',
        'دفع عميل للكشف عن بيانات التواصل معك بخصوص: ' || coalesce(v_inq, '') || '. يُرجى الرد سريعًا — بموجب اتفاقية المورّد يجب الرد خلال '
          || v_window::text || ' أيام عمل من الكشف، وإلا يُردّ للعميل ما دفعه ويُسترد المبلغ من حسابك مع رسوم إدارية 250 درهمًا وفائدة 9% سنويًا.',
        '{}', 'quote_accepted:' || (d->>'subject_id'), null, jsonb_build_object('transaction_id', d->>'subject_id'));
    end if;
    return jsonb_build_object('customer_reachable', v_cust.email is not null,
                              'supplier_reachable', coalesce(v_sup.email, '') like '%@%',
                              'delivery_request', v_req);

  elsif t = 'payment.failed' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('reveal_payment_incomplete', 'customer', v_cust.email, null, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'Your reveal payment did not complete',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'Your payment to unlock the supplier''s contact details did not go through, and nothing was charged to your card.' || E'\n\n'
        || 'You can try again at any time: open the request in your QuotesDone portal and choose Reveal on the quote you picked. If the card was declined, your bank can tell you why, and a different card also works.',
      'لم تكتمل عملية الدفع للكشف',
      'لم تنجح عملية الدفع للكشف عن بيانات المورّد، ولم يُخصم أي مبلغ من بطاقتك. يمكنك المحاولة مجددًا في أي وقت من بوابتك في QuotesDone.',
      '{}', 'payment_failed:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'payment.received' then
    if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes(coalesce(d->>'msg_type', 'dues_paid'), 'supplier', v_sup.email, v_sup.id, null, null, null,
      case when d->>'kind' = 'supplier_registration' then 'Registration confirmed - thank you' else 'Payment received - thank you' end,
      case when d->>'kind' = 'supplier_registration'
           then 'We have received your registration payment of AED ' || (d->>'amount_aed') || '. Your QuotesDone supplier account is registered for the next 12 months.'
           else 'We have received your payment of AED ' || (d->>'amount_aed') || ' settling ' || coalesce(d->>'items', '1') || ' outstanding charge(s). Your account is now up to date.' end,
      'تم استلام دفعتك', 'استلمنا دفعتك بقيمة ' || (d->>'amount_aed') || ' درهم. شكرًا لك.',
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
      'استلمنا طلب استرداد مبلغ الكشف. نتحقق أولًا من ردّ المورّد، ثم يقرّر رئيسنا التنفيذي، وإن كان الاسترداد مستحقًا يعود إليك كامل ما دفعته إلى البطاقة نفسها خلال '
        || v_min || '–' || v_max || ' يوم عمل بحسب البنك.',
      '{}', 'refund_request_received:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req, 'money_ok', d->'money_ok');

  elsif t = 'refund.paid' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('refund_issued', 'customer', v_cust.email, (d->>'supplier_id')::bigint, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'Your QuotesDone refund of AED ' || (d->>'amount_aed') || ' has been issued',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'We have issued a refund of AED ' || (d->>'amount_aed') || ' — everything you paid on ' || v_revealed
        || ', the reveal fee and the card processing part together — to your original payment method, because the supplier did not respond within '
        || v_window::text || ' working days. Nothing is deducted.' || E'\n\n'
        || 'Banks and card issuers usually take ' || v_min || '–' || v_max || ' working days to show it on your statement. If it has not appeared after '
        || v_max || ' working days, reply to this email and we will trace it with the payment processor.' || E'\n\n'
        || 'You are welcome to post the request again; we will introduce you to another supplier.',
      'تم إصدار استرداد بقيمة ' || (d->>'amount_aed') || ' درهم',
      'أصدرنا لك استردادًا بقيمة ' || (d->>'amount_aed') || ' درهم، وهو كامل ما دفعته، إلى وسيلة الدفع الأصلية لأن المورّد لم يردّ خلال '
        || v_window::text || ' أيام عمل. قد يستغرق ظهوره في كشف حسابك ' || v_min || '–' || v_max || ' يوم عمل.',
      '{}', 'refund_issued:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req, 'amount_aed', d->'amount_aed');

  elsif t = 'refund.declined' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('refund_declined', 'customer', v_cust.email, null, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'About your refund request',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'We looked at your refund request for the reveal on ' || coalesce('"' || left(v_inq, 80) || '"', 'your request') || ' and it was not approved.' || E'\n\n'
        || 'The reason: ' || coalesce(nullif(btrim(d->>'note'), ''), 'the record shows the supplier did respond.') || E'\n\n'
        || 'If you think we have missed something, reply to this email with what you have — an email thread with the supplier, dates, anything — and we will look again.',
      'بخصوص طلب الاسترداد',
      'راجعنا طلب الاسترداد ولم تتم الموافقة عليه. السبب: ' || coalesce(nullif(btrim(d->>'note'), ''), 'السجل يُظهر أن المورّد قد ردّ.')
        || ' إن كان لديك ما يثبت خلاف ذلك فردّ على هذه الرسالة وسنراجع الطلب مجددًا.',
      '{}', 'refund_declined:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'refund.in_progress' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('refund_in_progress', 'customer', v_cust.email, null, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'Your refund is being processed',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'Your refund of AED ' || coalesce(d->>'amount_aed', '') || ' has been approved and is being processed with the payment provider. It has not reached your card yet; we will write again the moment it has.',
      'استردادك قيد المعالجة',
      'تمت الموافقة على استردادك وهو قيد المعالجة لدى مزوّد الدفع، ولم يصل إلى بطاقتك بعد. سنراسلك فور وصوله.',
      '{}', 'refund_in_progress:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t in ('nonresponse.charge_raised', 'charge.corrected') then
    if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
    v_lines := '  Amount refunded to the customer: AED ' || (d->>'refunded_aed') || E'\n'
            || '  Administration fee: AED ' || (d->>'admin_fee_aed') || E'\n'
            || '  Interest: ' || round((d->>'interest_apr')::numeric * 100, 2) || '% a year, simple, on AED '
            || round((d->>'refunded_aed')::numeric + (d->>'admin_fee_aed')::numeric, 2) || ' from ' || (d->>'due_date') || ' until paid' || E'\n'
            || '  Due by: ' || (d->>'due_date');
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
        'دفع عميل للكشف عن بيانات التواصل معك ولم يتلقَّ ردًّا خلال ' || v_window::text || ' أيام عمل رغم التذكيرات. بموجب اتفاقية المورّد رُدّ للعميل كامل ما دفعه ويُسترد من حسابك: المبلغ المسترد '
          || (d->>'refunded_aed') || ' درهم، ورسوم إدارية ' || (d->>'admin_fee_aed') || ' درهم، وفائدة بسيطة ' || round((d->>'interest_apr')::numeric * 100, 2)
          || '% سنويًا من ' || (d->>'due_date') || ' حتى السداد. يمكنك السداد أو الاعتراض من قسم الفواتير في بوابتك.',
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
          || ' درهم، ورسوم إدارية ' || (d->>'admin_fee_aed') || ' درهم، مستحقة في ' || (d->>'due_date') || '.',
        coalesce(v_orig.cc_emails, '{}'), 'charge_corrected:' || (d->>'subject_id'));
    end if;
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'subscription.due' then
    if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('subscription_due', 'supplier', v_sup.email, v_sup.id, null, null, null,
      'Your QuotesDone annual subscription is due',
      'Dear ' || coalesce(v_sup.company_name, 'there') || E',\n\nYour QuotesDone annual supplier subscription of '
        || coalesce(d->>'currency', 'AED') || ' ' || (d->>'fee') || E' is now due.\n\nYou keep paying no commission on the jobs you win — this is the annual subscription only. You can settle it securely on the supplier portal: https://quotesdone.com/suppliers\n\nIf it is not settled, your profile is paused from receiving new customer requests until it is.\n\nThank you for being part of QuotesDone.',
      'اشتراكك السنوي في QuotesDone مستحق',
      'اشتراكك السنوي كمورّد بقيمة ' || (d->>'fee') || ' درهم مستحق الآن. يمكنك السداد بأمان من بوابة المورّد.',
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
  end if;
  raise exception 'sales_engineer has no handler for %', t;
end $fn$;
revoke execute on function public.fn_sales_engineer_acts_on_handoff(bigint) from public, anon, authenticated;

-- ── 6. THE ACCOUNTANT READS THE BOOKS ────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_acts_on_handoff(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  a public.agent_actions; d jsonb; t text; r public.refunds; tx public.transactions; du public.supplier_dues;
  v_expected bigint; v_ok boolean; v_checks jsonb; v jsonb; v_lines text[] := '{}'; v_match boolean; x record;
begin
  select * into a from public.agent_actions where id = p_id;
  d := a.detail; t := d->>'type';

  if t = 'refund.requested' then
    select * into r from public.refunds where id = (d->>'subject_id')::bigint;
    select * into tx from public.transactions where id = r.transaction_id;
    v_expected := round(coalesce(tx.total_charged, tx.reveal_fee, 0) * 100)::bigint;
    v_checks := jsonb_build_object(
      'transaction_found', tx.id is not null,
      'fee_settled', coalesce(tx.fee_status, '') = 'paid',
      'stripe_reference_matches', coalesce(btrim(tx.payment_ref), '') <> '' and btrim(tx.payment_ref) = btrim(coalesce(r.stripe_payment_intent, '')),
      'amount_is_total_charged', r.amount_fils = v_expected,
      'total_charged_recorded', tx.total_charged is not null,
      'expected_fils', v_expected, 'requested_fils', r.amount_fils);
    v_ok := (v_checks->>'transaction_found')::boolean and (v_checks->>'fee_settled')::boolean
            and (v_checks->>'stripe_reference_matches')::boolean and (v_checks->>'amount_is_total_charged')::boolean;
    perform public.fn_seat_handoff('accountant', 'sales_engineer', 'refund.request_checked', 'refunds', r.id::text,
      jsonb_build_object('refund_id', r.id, 'transaction_id', r.transaction_id, 'customer_id', r.customer_id,
                         'inquiry_id', r.inquiry_id, 'quote_id', r.quote_id, 'money_ok', v_ok,
                         'amount_aed', round(coalesce(r.amount_fils, 0) / 100.0, 2)));
    return v_checks || jsonb_build_object('money_ok', v_ok);

  elsif t = 'billing.question' then
    if d->>'party' = 'supplier' then
      perform public.fn_supplier_dues_accrue_interest(null);
      for x in select * from public.supplier_dues
                where supplier_id = (d->>'supplier_id')::bigint and coalesce(status, '') not in ('cancelled')
                order by id loop
        v_lines := v_lines || ('Charge #' || x.id || ' (reveal of ' || coalesce(x.reveal_date::text, '?') || '): AED '
          || coalesce(x.amount_due, 0) || ' refunded to the customer + AED ' || coalesce(x.admin_fee, 0) || ' administration + AED '
          || coalesce(x.interest_amount, 0) || ' interest = AED ' || coalesce(x.total_claim, coalesce(x.amount_due, 0) + coalesce(x.admin_fee, 0) + coalesce(x.interest_amount, 0))
          || ', due ' || coalesce(x.due_date::text, '?') || ', ' || case when x.paid_at is not null then 'paid' else coalesce(x.status, 'open') end || '.');
      end loop;
      v := public.fn_supplier_registration_state((d->>'supplier_id')::bigint);
      if v is not null then
        v_lines := v_lines || ('Registration: ' || coalesce(v->>'status', 'unknown') || coalesce(', fee due AED ' || nullif(v->>'fee_due', '0'), '') || '.');
      end if;
    else
      for x in select t2.*, i.summary from public.transactions t2 left join public.inquiries i on i.id = t2.inquiry_id
                where t2.customer_id = (d->>'customer_id')::uuid
                  and ((d->>'transaction_id') is null or t2.id = (d->>'transaction_id')::uuid)
                  and t2.revealed_at is not null
                order by t2.revealed_at desc limit 10 loop
        v_lines := v_lines || ('Reveal on ' || to_char(x.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY')
          || coalesce(' for "' || left(x.summary, 60) || '"', '') || ': you paid AED ' || coalesce(x.total_charged, x.reveal_fee)
          || case when x.total_charged is not null and x.total_charged > coalesce(x.reveal_fee, 0)
                  then ' (reveal fee AED ' || x.reveal_fee || ' + card processing AED ' || (x.total_charged - x.reveal_fee) || ')' else '' end
          || '. Invoice ' || coalesce(x.stripe_invoice_number, 'not yet issued') || coalesce(' — ' || x.stripe_invoice_hosted_url, '')
          || '. Refund: ' || case when x.refund_status in ('refunded', 'succeeded') then 'AED ' || coalesce(x.refund_amount_aed::text, '?') || ' returned'
                                  when x.refund_status = 'requested' then 'requested and under review'
                                  when x.refund_status = 'rejected' then 'declined'
                                  else 'none requested' end || '.');
      end loop;
    end if;
    perform public.fn_seat_handoff('accountant', 'sales_engineer', 'billing.answer', 'agent_actions', a.id::text,
      jsonb_build_object('party', d->>'party', 'customer_id', d->>'customer_id', 'supplier_id', d->>'supplier_id',
                         'question', d->>'question', 'facts', to_jsonb(v_lines)));
    return jsonb_build_object('facts', to_jsonb(v_lines));

  elsif t = 'charge.disputed' then
    select * into du from public.supplier_dues where id = coalesce((d->>'due_id')::bigint, (d->>'subject_id')::bigint);
    v := public.fn_accountant_nonresponse_charge(du.transaction_id, null);
    v_match := coalesce((v->>'ok')::boolean, false)
               and du.amount_due = (v->>'refunded_aed')::numeric
               and du.admin_fee = (v->>'admin_fee_aed')::numeric
               and du.due_date = (v->>'due_date')::date;
    v_lines := array[
      'Charged: AED ' || coalesce(du.amount_due, 0) || ' + AED ' || coalesce(du.admin_fee, 0) || ' administration, due ' || coalesce(du.due_date::text, '?') || '.',
      'Payment record: ' || coalesce('AED ' || (v->>'refunded_aed') || ' refunded to the customer (' || (v->>'refund_source') || ') + AED '
                                     || (v->>'admin_fee_aed') || ' administration, due ' || (v->>'due_date') || '.', coalesce(v->>'reason', 'unreadable')),
      'Interest to date: AED ' || coalesce(v->>'interest_aed', '0') || ' at ' || coalesce(round((v->>'interest_apr')::numeric * 100, 2)::text, '?') || '% a year over '
        || coalesce(v->>'interest_days', '0') || ' day(s).'];
    if not v_match then
      insert into public.ceo_task (title, detail)
      values (left('Supplier disputed charge #' || du.id || ' and it does not match the refund record', 200),
              'The accountant recomputed charge #' || du.id || ' from the refund record and the figures differ. ' || array_to_string(v_lines, ' '));
    end if;
    perform public.fn_seat_handoff('accountant', 'sales_engineer', 'charge.dispute_answer', 'supplier_dues', du.id || ':' || a.id,
      jsonb_build_object('supplier_id', du.supplier_id, 'due_id', du.id, 'figures_match', v_match, 'lines', to_jsonb(v_lines), 'reason', d->>'reason'));
    return jsonb_build_object('figures_match', v_match, 'recomputed', v);

  elsif t = 'refund.remediate' then
    return public.fn_accountant_remediates(p_id);

  elsif t = 'incident.fix' then
    return public.fn_accountant_applies_incident_fix(p_id);
  end if;
  raise exception 'accountant has no handler for %', t;
end $fn$;
revoke execute on function public.fn_accountant_acts_on_handoff(bigint) from public, anon, authenticated;

-- ── 7. CUSTOMER SUPPORT DELIVERS, AND WATCHES FOR THE REPLY ──────────────────────────────────────
-- The only seat that puts anything on email or WhatsApp. It never sends directly: it queues the
-- outbox (public.notifications), which send_outbox and send_whatsapp drain; trg_wa_fanout adds the
-- WhatsApp copy for an opted-in recipient. The founder is reached only through fn_notify_founder
-- and founder_mail_policy.
create or replace function public.fn_customer_support_acts_on_handoff(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  a public.agent_actions; d jsonb; v_ar boolean; v_subject text; v_body text; v_nid bigint; v_fan jsonb; v_cc text[]; v_res jsonb;
begin
  select * into a from public.agent_actions where id = p_id;
  d := a.detail;
  if d->>'type' <> 'delivery.request' then raise exception 'customer_support has no handler for %', d->>'type'; end if;

  if d->>'recipient_role' = 'founder' then
    -- A TEST NEVER REACHES HIM. The fixture ladder sets app.qd_stub_founder_notify; the probe also
    -- aborts its transaction, so even the queued rows are never committed.
    if coalesce(current_setting('app.qd_stub_founder_notify', true), '') = 'on' then
      return jsonb_build_object('channel', 'founder', 'stubbed', true, 'event', d->>'event');
    end if;
    v_res := public.fn_notify_founder(d->>'event', d->>'detail', coalesce(d->>'level', 'high'), d->>'kind', d->>'dedupe_key', 'customer_support');
    return jsonb_build_object('channel', 'founder', 'notify', v_res);
  end if;

  if a.detail->>'from' <> 'sales_engineer' then
    raise exception 'only the sales engineer addresses customers and suppliers; % may address the founder only', a.detail->>'from';
  end if;
  if coalesce(d->>'to_email', '') !~ '@' then
    return jsonb_build_object('delivered', false, 'reason', 'no email address on file for the ' || coalesce(d->>'recipient_role', 'recipient'));
  end if;

  v_ar := d->>'locale' = 'ar' and d->>'body_ar' is not null;
  v_subject := case when v_ar then coalesce(d->>'subject_ar', d->>'subject_en') else d->>'subject_en' end;
  v_body    := case when v_ar then d->>'body_ar' else d->>'body_en' end;
  select coalesce(array_agg(x), '{}') into v_cc from jsonb_array_elements_text(coalesce(d->'cc', '[]'::jsonb)) x;

  -- requested_by names the seat that asked (customer_support_is_the_only_sender_on_email_and_whatsapp.sql);
  -- sender stays customer_support by that file's default and check.
  insert into public.notifications (type, kind, to_email, cc_emails, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status, requested_by)
  values (d->>'msg_type', d->>'msg_type', d->>'to_email', v_cc, d->>'recipient_role',
          (d->>'supplier_id')::bigint, (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid, 'email', v_subject, v_body, 'queued',
          a.detail->>'from')
  returning id into v_nid;
  select coalesce(jsonb_agg(n.id), '[]'::jsonb) into v_fan from public.notifications n
   where n.channel = 'whatsapp' and n.type = d->>'msg_type' and n.id > v_nid
     and n.to_email = d->>'to_email' and n.created_at >= now() - interval '1 minute';

  return jsonb_build_object('delivered', true, 'queued_at', now(), 'notification_id', v_nid, 'whatsapp_ids', v_fan,
                            'language', case when v_ar then 'ar' else 'en' end,
                            'watch_until', d->'watch_until', 'watching', (d->>'watch_until') is not null);
end $fn$;
revoke execute on function public.fn_customer_support_acts_on_handoff(bigint) from public, anon, authenticated;

-- THE WATCH. For every delivery that asked to be watched, support returns exactly one result to the
-- sales engineer: PROOF OF RESPONSE (the supplier replied on any channel -- portal message,
-- supplier_ack, a recorded reply, an email from their address, a WhatsApp from their number) or
-- NO-RESPONSE CONFIRMATION (the working-day window closed with nothing, carrying the delivery
-- evidence and the channels checked). A delivery that failed is retried once; if it fails again the
-- confirmation says delivered=false, which the CEO's checklist reads as ambiguous and refuses.
create or replace function public.fn_customer_support_delivery_watch(p_request_id bigint default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  q record; n public.notifications; tx public.transactions; sup record; v_since timestamptz;
  v_reply jsonb; v_result text; v_evidence jsonb; v_retries int; v_nid bigint; v_done int := 0; v_waiting int := 0; v_retried int := 0;
begin
  for q in
    select a.* from public.agent_actions a
     where a.kind = 'handoff' and a.agent = 'customer_support' and a.status = 'done'
       and a.detail->>'type' = 'delivery.request' and (a.detail->>'watch_until') is not null
       and (a.detail->>'result_handoff_id') is null
       and (p_request_id is null or a.id = p_request_id)
     order by a.id
  loop
    v_nid := coalesce((q.detail->>'retry_notification_id')::bigint, (q.evidence->>'notification_id')::bigint);
    select * into n from public.notifications where id = v_nid;
    select * into tx from public.transactions where id = (q.detail->>'transaction_id')::uuid;
    select l.id, lower(coalesce(l.claimed_by, l.email)) as email,
           regexp_replace(coalesce(nullif(btrim(l.whatsapp), ''), l.phone_e164, l.phone, ''), '[^0-9]', '', 'g') as phone
      into sup from public.leads l where l.id = (q.detail->>'supplier_id')::bigint;
    v_since := coalesce(tx.revealed_at, q.created_at);
    v_retries := coalesce((q.detail->>'retries')::int, 0);

    -- ANY CHANNEL, EVERY TIME. The first thing that came back wins.
    select jsonb_build_object('channel', ch, 'at', at, 'ref', ref) into v_reply from (
      select 'portal' ch, m.created_at at, 'messages#' || m.id ref from public.messages m
       where tx.id is not null and m.inquiry_id = tx.inquiry_id and m.supplier_id = tx.supplier_id
         and m.sender = 'supplier' and coalesce(m.blocked, false) = false and m.created_at > v_since
      union all
      select 'supplier_ack', tx.supplier_ack_at, 'transactions.supplier_ack_at' where tx.supplier_ack_at > v_since
      union all
      select coalesce(w.response_channel, 'recorded'), w.first_response_at, coalesce(w.response_ref, 'supplier_response_watch#' || w.id)
        from public.supplier_response_watch w where tx.id is not null and w.transaction_id = tx.id and w.first_response_at > v_since
      union all
      select 'email', im.created_at, 'inbound_messages#' || im.id from public.inbound_messages im
       where sup.email is not null and lower(im.from_email) = sup.email and im.created_at > v_since
      union all
      select 'whatsapp', wm.created_at, 'wa_messages#' || wm.id from public.wa_messages wm
       where length(coalesce(sup.phone, '')) >= 8 and regexp_replace(coalesce(wm.wa_from, ''), '[^0-9]', '', 'g') = sup.phone
         and wm.created_at > v_since
      order by 2 limit 1) z;

    if v_reply is not null and q.detail->>'recipient_role' = 'supplier' then
      v_result := 'proof_of_response';
      v_evidence := jsonb_build_object('reply', v_reply);
    elsif n.id is null or n.status in ('failed', 'bounced', 'error') then
      if v_retries < 1 and n.id is not null then
        insert into public.notifications (type, kind, to_email, cc_emails, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status, requested_by)
        values (n.type, n.kind, n.to_email, n.cc_emails, n.to_role, n.lead_id, n.inquiry_id, n.quote_id, 'email', n.subject, n.body, 'queued', n.requested_by)
        returning id into v_nid;
        update public.agent_actions
           set detail = detail || jsonb_build_object('retries', v_retries + 1, 'retry_notification_id', v_nid,
                                                     'first_failure', jsonb_build_object('notification_id', n.id, 'status', n.status, 'error', n.last_error))
         where id = q.id;
        perform public.fn_seat_handoff_event(q.id, 'retried');
        v_retried := v_retried + 1;
        continue;
      end if;
      v_result := 'no_response_confirmation';
      v_evidence := jsonb_build_object('delivered', false, 'retries', v_retries,
        'delivery', jsonb_build_object('notification_id', n.id, 'status', n.status, 'error', n.last_error),
        'first_failure', q.detail->'first_failure');
    elsif now() >= (q.detail->>'watch_until')::timestamptz then
      v_result := 'no_response_confirmation';
      v_evidence := jsonb_build_object('delivered', n.status = 'sent' or n.sent_at is not null,
        'delivery', jsonb_build_object('notification_id', n.id, 'status', n.status, 'sent_at', n.sent_at,
                                       'provider_message_id', n.provider_message_id, 'attempts', n.attempts),
        'whatsapp', (select coalesce(jsonb_agg(jsonb_build_object('notification_id', w.id, 'status', w.status, 'sent_at', w.sent_at,
                                                                  'provider_message_id', w.provider_message_id)), '[]'::jsonb)
                       from public.notifications w
                      where w.id in (select (x)::bigint from jsonb_array_elements_text(coalesce(q.evidence->'whatsapp_ids', '[]'::jsonb)) x)),
        'window_closed_at', q.detail->'watch_until',
        'channels_checked', jsonb_build_array('portal', 'supplier_ack', 'recorded_reply', 'email', 'whatsapp'));
    else
      v_waiting := v_waiting + 1;
      continue;
    end if;

    update public.agent_actions set detail = detail || jsonb_build_object('result', v_result) where id = q.id;
    update public.agent_actions
       set detail = detail || jsonb_build_object('result_handoff_id',
             public.fn_seat_handoff('customer_support', 'sales_engineer', 'delivery.result', 'agent_actions', q.id::text,
               jsonb_build_object('request_id', q.id, 'result', v_result, 'evidence', v_evidence,
                                  'step', q.detail->>'step', 'refund_id', q.detail->>'refund_id',
                                  'transaction_id', q.detail->>'transaction_id', 'supplier_id', q.detail->>'supplier_id',
                                  'remediation_id', q.detail->>'remediation_id')))
     where id = q.id;
    v_done := v_done + 1;
  end loop;
  return jsonb_build_object('results_returned', v_done, 'still_watching', v_waiting, 'retried', v_retried);
end $fn$;
revoke execute on function public.fn_customer_support_delivery_watch(bigint) from public, anon, authenticated;

-- ── 8. PRODUCERS: the payment events that start a conversation ───────────────────────────────────
-- Every reveal goes through transactions.revealed_at (z20_reveal_receipt), so this is still the one
-- door. It no longer writes the messages itself: the accountant hands the settled payment to the
-- sales engineer, who writes them, and support delivers them.
create or replace function public.trg_reveal_receipt()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if NEW.revealed_at is not null and (TG_OP = 'INSERT' or OLD.revealed_at is null) then
    perform public.fn_seat_handoff('accountant', 'sales_engineer', 'reveal.paid', 'transactions', NEW.id::text,
      jsonb_build_object('transaction_id', NEW.id, 'customer_id', NEW.customer_id, 'supplier_id', NEW.supplier_id,
                         'inquiry_id', NEW.inquiry_id, 'quote_id', NEW.quote_id, 'revealed_at', NEW.revealed_at));
  end if;
  return NEW;
end $fn$;

-- A customer asking for a refund in the portal is the sales engineer's conversation; the money
-- behind it is the accountant's to check.
create or replace function public.fn_refund_request_hands_to_accountant()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if NEW.transaction_id is not null and NEW.status = 'requested'
     and lower(coalesce(NEW.requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe') then
    perform public.fn_seat_handoff('sales_engineer', 'accountant', 'refund.requested', 'refunds', NEW.id::text,
      jsonb_build_object('refund_id', NEW.id, 'transaction_id', NEW.transaction_id, 'customer_id', NEW.customer_id,
                         'inquiry_id', NEW.inquiry_id, 'quote_id', NEW.quote_id));
  end if;
  return NEW;
end $fn$;
revoke execute on function public.fn_refund_request_hands_to_accountant() from public, anon, authenticated;
drop trigger if exists z30_refund_request_hands_to_accountant on public.refunds;
create trigger z30_refund_request_hands_to_accountant after insert on public.refunds
  for each row execute function public.fn_refund_request_hands_to_accountant();

-- The yearly fee: the accountant marks it due (money state) and hands the telling to the sales engineer.
create or replace function public.fn_subscription_billing_run(p_dry_run boolean default false)
returns json language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; v_flagged int := 0; v_cfg record;
begin
  select * into v_cfg from public.fn_supplier_subscription();
  for r in
    select b.* from public.v_supplier_billing b
     where b.billing_status in ('due', 'past_due')
       and coalesce(b.email, '') <> ''
       and not exists (select 1 from public.notifications n
                        where n.type = 'subscription_due' and n.lead_id = b.supplier_id
                          and n.created_at > now() - interval '30 days')
  loop
    if not p_dry_run then
      update public.leads set registration_fee_due = v_cfg.fee, registration_status = 'due' where id = r.supplier_id;
      perform public.fn_seat_handoff('accountant', 'sales_engineer', 'subscription.due', 'leads',
        r.supplier_id || ':' || to_char(current_date, 'YYYY-MM'),
        jsonb_build_object('supplier_id', r.supplier_id, 'fee', v_cfg.fee, 'currency', v_cfg.currency));
    end if;
    v_flagged := v_flagged + 1;
  end loop;

  if v_flagged > 0 and not p_dry_run then
    perform public.fn_seat_handoff('accountant', 'customer_support', 'delivery.request', 'founder',
      'subscription_billing_summary:' || current_date,
      jsonb_build_object('recipient_role', 'founder', 'kind', 'finance_reminder', 'level', 'info',
        'event', 'Supplier subscriptions invoiced',
        'detail', v_flagged || ' supplier(s) were invoiced ' || v_cfg.currency || ' ' || v_cfg.fee
                  || ' for their annual subscription. Founding suppliers (first ' || v_cfg.free_limit || ') are exempt and were not billed.',
        'dedupe_key', 'subscription_billing_summary:' || current_date));
  end if;

  return json_build_object('billing_starts', v_cfg.start_date, 'fee', v_cfg.fee, 'currency', v_cfg.currency,
    'free_limit', v_cfg.free_limit, 'invoiced', v_flagged, 'dry_run', p_dry_run, 'ran_at', now());
end $fn$;

-- ── 9. THE CEO SEES THE PAYMENT PATHS AS THE ACCOUNTANT'S WORK ───────────────────────────────────
-- A run row names the FUNCTION that wrote it ('stripe_webhook', 'fn:refunds_api'). function_owner
-- names the seat that owns that function. Reading through it attributes every payment run to the
-- accountant without touching eleven writers, and does the same for every other seat.
create or replace function public.fn_run_seat(p_agent text)
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce((select fo.owner from public.function_owner fo
                    where fo.function_slug = regexp_replace(coalesce(p_agent, ''), '^fn:', '')),
                  regexp_replace(coalesce(p_agent, ''), '^fn:', ''));
$fn$;
revoke execute on function public.fn_run_seat(text) from public, anon, authenticated;

-- fn_ceo_seat_board, unchanged except that a run is attributed through fn_run_seat.
CREATE OR REPLACE FUNCTION public.fn_ceo_seat_board(p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_from timestamptz := now() - make_interval(days => greatest(1, coalesce(p_days, 7)));
  j jsonb;
begin
  select jsonb_build_object(
    'window_days', greatest(1, coalesce(p_days, 7)),
    'since', v_from,
    'seats', (
      select jsonb_object_agg(s.seat, jsonb_build_object(

        -- WHAT IT DID: every run, and every run that failed. Same source for all five, so the
        -- comparison between seats is honest.
        'runs',        (select count(*) from agent_runs r
                         where public.fn_run_seat(r.agent) = s.seat and r.started_at >= v_from),
        'errors',      (select count(*) from agent_runs r
                         where public.fn_run_seat(r.agent) = s.seat
                           and r.status = 'error' and r.started_at >= v_from),
        'last_seen',   (select max(r.started_at) from agent_runs r
                         where public.fn_run_seat(r.agent) = s.seat),

        -- WHAT IS WAITING ON IT: work assigned and not finished. This is the half the CEO had no
        -- sight of at all.
        'open_tasks',  (select count(*) from org_tasks t
                         where t.assigned_agent = s.seat and t.status in ('assigned','in_progress')),
        'oldest_open_task_days', (select round(extract(epoch from (now() - min(t.created_at)))/86400)
                         from org_tasks t
                        where t.assigned_agent = s.seat and t.status in ('assigned','in_progress')),

        -- WHAT IT FILED TO THE CEO, and whether the CEO has picked it up. An unread report is the
        -- CEO's own backlog, not the seat's.
        --
        -- THE NAME OF THIS FIGURE WAS WRONG AND THE FOUNDER CAUGHT IT. It read
        -- 'awaiting_my_acceptance', and on 9 September he read the board and asked "wait is the CEO
        -- basically waiting to approve the accountant report" -- a fair reading of that phrase, and
        -- not what the number means. Measured: three routines read accepted_at
        -- (fn_ceo_weekly_figures, fn_ceo_seat_board, fn_customer_mandatory_check) and all three only
        -- COUNT it for display. Nothing gates on it. Both accountant reports say in their own
        -- requested_outcome field "NOTHING IS REQUESTED", and one had already reached the founder.
        -- It is a read receipt, not an approval queue, and the label now says which. A number whose
        -- name implies work is blocked, on a board built so the chief executive knows what is
        -- waiting on whom, is worse than no number.
        'filed_to_ceo',    (select count(*) from support_ceo_report c where c.source_agent = s.seat),
        'filed_but_not_yet_read_by_ceo', (select count(*) from support_ceo_report c
                                    where c.source_agent = s.seat and c.accepted_at is null),

        -- WHAT IT ACHIEVED: the question this seat's own job answers.
        'achievement', case s.seat
          when 'accountant' then jsonb_build_object(
            'expense_records_with_a_document', (select count(*) from expense_entries where doc_path is not null),
            'journals_posted',                 (select count(*) from gl_journal where status = 'posted'),
            'weekly_reports_delivered',        (select count(*) from accountant_weekly_report where founder_submitted_at is not null))
          when 'customer_support' then jsonb_build_object(
            'conversations_answered',          (select count(*) from assistant_logs where created_at >= v_from),
            'questions_it_could_not_answer',   (select count(*) from sales_knowledge_gap where status = 'open'),
            'supplier_contacts_logged',        (select count(*) from supplier_response_watch))
          when 'sales_engineer' then jsonb_build_object(
            'assists_given',                   (select count(*) from sales_decision_log where created_at >= v_from),
            'quotes',                          (select count(*) from quotes),
            'comparisons',                     (select count(*) from quote_comparisons))
          when 'it_engineer' then jsonb_build_object(
            'findings_open',                   (select count(*) from it_watch_finding where status = 'open'),
            'findings_closed',                 (select count(*) from it_watch_finding where status = 'resolved'),
            'alerts_delivered',                (select count(*) from notifications
                                                 where kind like 'it_%' and status = 'sent'))
          when 'ceo' then jsonb_build_object(
            'approvals_decided',               (select count(*) from ceo_approval),
            'reports_accepted',                (select count(*) from support_ceo_report where accepted_at is not null),
            'weekly_reports_delivered',        (select count(*) from ceo_weekly_report where founder_submitted_at is not null))
          else '{}'::jsonb end))
      from (select unnest(array['ceo','customer_support','sales_engineer','accountant','it_engineer']) as seat) s),

    'basis', 'Every figure is a count of rows that exist, over the window for activity and lifetime '
          || 'for achievement. Nothing here is scored or rated. A zero means the thing has not '
          || 'happened, not that nobody counted it — the seats were created 7-9 September 2026 and '
          || 'the company has taken no revenue yet.'
  ) into j;
  return j;
end $function$;
