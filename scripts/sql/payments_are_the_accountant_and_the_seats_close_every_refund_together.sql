-- PAYMENTS ARE THE ACCOUNTANT'S, AND THE SEATS CLOSE EVERY REFUND TOGETHER.
--
-- Assigned: accountant (every payment path), with sales_engineer (the voice customers and suppliers
-- hear), customer_support (the only seat that sends email or WhatsApp) and ceo (the refund checklist,
-- the review loop and the mismatch playbook). Carried out for the ceo.
--
-- ONE FILE, THREE PARTS, BECAUSE THE WIRING IS ONE LOOP. A handoff (PART A) is acted on by the seat that
-- receives it, which may compute the supplier's charge (PART B) or advance the CEO's review (PART C),
-- which hands work back through PART A. plpgsql resolves callees at run time and scripts/apply_sql.mjs
-- refuses a routine whose callee production does not have yet, so three files calling each other in a
-- circle could never be applied one after another. The parts are kept as the three subjects they are:
--
--   PART A  the conversation: fn_seat_handoff and the three seats' handlers, the event stream, the
--           producers (a paid reveal, a refund request, the yearly fee), run attribution, the timeline.
--   PART B  the money: a refund returns total_charged; the one routine that computes the supplier's
--           charge; what follows a settled, declined or failed refund; the ledger; the circuit breaker.
--   PART C  the CEO: the checklist before approval and after payment, the review loop with the
--           accountant and the sales engineer, the delivery loop inside it, the mismatch playbook.
--
--   node scripts/apply_sql.mjs scripts/sql/payments_are_the_accountant_and_the_seats_close_every_refund_together.sql --apply --ddl


-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- PART A. THE CONVERSATION
-- ════════════════════════════════════════════════════════════════════════════════════════════════
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

-- ── 0. HIS WORDS, IN THE REGISTER ─────────────────────────────────────────────────────────────────
insert into public.founder_instruction (said_at, instruction, subject, status, evidence)
select '2026-09-14T00:00:00Z', x.i, x.s, 'done',
       'scripts/sql/payments_are_the_accountant_and_the_seats_close_every_refund_together.sql; scripts/checks/payments_are_the_accountant.test.mjs'
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
    v_res := public.fn_notify_founder(p_event => d->>'event', p_detail => d->>'detail', p_level => coalesce(d->>'level', 'high'),
                                      p_kind => d->>'kind', p_dedupe_key => d->>'dedupe_key', p_owner_agent => 'customer_support');
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

-- fn_contact_timeline, with the seat handoffs in it. The live definition
-- (customer_support_is_the_only_sender_on_email_and_whatsapp.sql) plus one union: support reads every handoff
-- about a party before it answers them (founder, 14 Sep 2026: support "should be always up to date").
CREATE OR REPLACE FUNCTION public.fn_contact_timeline(p_contact text, p_limit integer DEFAULT 60)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_raw text := btrim(coalesce(p_contact, ''));
  v_email text; v_tail text;
  v_cust uuid[]; v_lead bigint[]; v_inq uuid[]; v_txn uuid[]; v_ref bigint[];
  v_events jsonb; v_counts jsonb;
begin
  v_raw := regexp_replace(v_raw, '^whatsapp:', '', 'i');
  if position('@' in v_raw) > 0 then
    v_email := lower(v_raw);
  elsif length(regexp_replace(v_raw, '[^0-9]', '', 'g')) >= 7 then
    v_tail := right(regexp_replace(v_raw, '[^0-9]', '', 'g'), 9);   -- +9715..., 05..., 5...
  else
    return jsonb_build_object('contact', v_raw, 'known', false, 'event_count', 0, 'events', '[]'::jsonb);
  end if;

  select coalesce(array_agg(c.id), '{}') into v_cust from public.customers c
   where (v_email is not null and lower(c.email) = v_email)
      or (v_tail is not null and right(regexp_replace(coalesce(c.phone, ''), '[^0-9]', '', 'g'), 9) = v_tail);
  select coalesce(array_agg(l.id), '{}') into v_lead from public.leads l
   where (v_email is not null and (lower(l.email) = v_email or lower(l.claimed_by) = v_email))
      or (v_tail is not null and v_tail in (right(regexp_replace(coalesce(l.phone_e164, ''), '[^0-9]', '', 'g'), 9),
                                            right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 9),
                                            right(regexp_replace(coalesce(l.whatsapp, ''), '[^0-9]', '', 'g'), 9)));
  select coalesce(array_agg(i.id), '{}') into v_inq from public.inquiries i where i.customer_id = any (v_cust);
  select coalesce(array_agg(t.id), '{}') into v_txn from public.transactions t
   where t.customer_id = any (v_cust) or t.supplier_id = any (v_lead);
  select coalesce(array_agg(r.id), '{}') into v_ref from public.refunds r
   where r.customer_id = any (v_cust) or r.supplier_lead_id = any (v_lead) or r.transaction_id = any (v_txn);

  with ev(at, kind, channel, direction, seat, ref, summary) as (
    -- what they asked for
    select i.created_at, 'request', 'portal', 'in', 'sales_engineer', i.id::text,
           coalesce(i.status, '') || ': ' || left(coalesce(i.summary_masked, i.summary, i.category, ''), 140)
      from public.inquiries i where i.id = any (v_inq)
    -- quotes on their requests: state only, never a supplier or an amount (the pre-reveal rule)
    union all
    select q.created_at, 'quote', 'portal', 'in', 'sales_engineer', q.id::text,
           case when exists (select 1 from public.transactions t where t.quote_id = q.id and t.revealed_at is not null)
                then 'released (revealed)' else 'held (' || coalesce(q.status, 'received') || ')' end
      from public.quotes q where q.inquiry_id = any (v_inq)
    -- quotes they submitted, when the contact is a supplier
    union all
    select q.created_at, 'quote_submitted', 'portal', 'out', 'sales_engineer', q.id::text, coalesce(q.status, 'submitted')
      from public.quotes q where q.supplier_id = any (v_lead)
    -- reveals and what was paid
    union all
    select t.revealed_at, 'reveal', 'portal', 'out', 'accountant', t.id::text, 'fee ' || coalesce(t.fee_status, 'unknown')
      from public.transactions t where t.id = any (v_txn) and t.revealed_at is not null
    union all
    select ri.created_at, 'invoice', 'portal', 'out', 'accountant', ri.invoice_no, 'reveal invoice issued'
      from public.reveal_invoices ri where ri.transaction_id = any (v_txn)
    -- refunds, and the CEO's decision on each (the refund loop)
    union all
    select coalesce(r.updated_at, r.created_at), 'refund', 'portal', 'out', 'accountant', r.id::text,
           coalesce(r.status, '') || coalesce(' — ' || r.reason_code, '')
      from public.refunds r where r.id = any (v_ref)
    union all
    select coalesce(rc.updated_at, rc.created_at), 'refund_case', 'internal', 'internal', 'accountant', rc.case_id::text,
           coalesce(rc.state, '') || coalesce(' — ' || rc.decision, '')
      from public.refund_case rc where rc.refund_id = any (v_ref)
    union all
    select a.decided_at, 'ceo_decision', 'internal', 'internal', 'ceo', a.decision_id::text,
           coalesce(a.subject_kind, '') || ': ' || coalesce(a.decision, '')
      from public.ceo_approval a where a.subject_kind ilike 'refund%' and a.subject_id = any (v_ref::text[])
    -- support cases
    union all
    select coalesce(s.last_activity_at, s.opened_at), 'support_case', 'internal', 'internal',
           coalesce(s.owner_role_id, 'customer_support'), s.case_ref, coalesce(s.state, '') || ': ' || left(coalesce(s.subject, ''), 120)
      from public.support_case s
     where (s.party_kind = 'customer' and s.party_id = any (v_cust::text[]))
        or (s.party_kind = 'supplier' and s.party_id = any (v_lead::text[]))
    -- every message the company sent them, and the seat that asked for it
    union all
    select n.created_at, 'message', coalesce(n.channel, 'email'), 'out', coalesce(n.requested_by, 'customer_support'),
           n.id::text, coalesce(n.status, 'queued') || ': ' || left(coalesce(n.subject, n.type, ''), 140)
      from public.notifications n
     where (v_email is not null and lower(n.to_email) = v_email)
        or (v_tail is not null and right(regexp_replace(coalesce(n.to_phone, ''), '[^0-9]', '', 'g'), 9) = v_tail)
        or n.lead_id = any (v_lead) or n.inquiry_id = any (v_inq)
    -- every message they sent the company
    union all
    select m.created_at, 'message', 'email', 'in', 'customer_support', m.id::text, left(coalesce(m.subject, ''), 140)
      from public.inbound_messages m
     where (v_email is not null and lower(m.from_email) = v_email) or m.lead_id = any (v_lead)
    union all
    select w.at, 'message', 'whatsapp', w.direction, 'customer_support', w.id::text, left(coalesce(w.transcript, w.body, ''), 140)
      from public.wa_turn w join public.wa_conversation c on c.id = w.conversation_id
     where (v_tail is not null and right(regexp_replace(coalesce(c.phone_e164, ''), '[^0-9]', '', 'g'), 9) = v_tail)
        or (c.party_kind = 'customer' and c.party_id = any (v_cust::text[]))
        or (c.party_kind = 'supplier' and c.party_id = any (v_lead::text[]))
    union all
    select pm.created_at, 'message', 'portal_chat', case when pm.customer_id = any (v_cust) and pm.sender = 'customer' then 'in' else 'out' end,
           'sales_engineer', pm.id::text, left(coalesce(pm.redacted_body, ''), 140)
      from public.messages pm where pm.customer_id = any (v_cust) or pm.supplier_id = any (v_lead)
    -- every handoff between the seats about this party (payments_are_the_accountant_and_it_talks_to_the_
    -- sales_engineer.sql): who handed what to whom, and where it stands, so support reads the money and
    -- the refund loops before it answers
    union all
    select a.created_at, 'handoff', 'internal', 'internal', a.agent, a.id::text,
           coalesce(a.detail->>'type', a.kind) || ' from ' || coalesce(a.detail->>'from', '?') || ' to ' || a.agent || ': ' || a.status
      from public.agent_actions a
     where a.kind = 'handoff'
       and ((a.detail->>'customer_id') = any (v_cust::text[]) or (a.detail->>'supplier_id') = any (v_lead::text[])
            or (a.detail->>'transaction_id') = any (v_txn::text[]) or (a.detail->>'refund_id') = any (v_ref::text[]))
    union all
    select cm.created_at, 'message', 'contact_form', 'in', 'customer_support', cm.id::text, left(coalesce(cm.message, ''), 140)
      from public.contact_messages cm
     where (v_email is not null and lower(cm.email) = v_email)
        or (v_tail is not null and right(regexp_replace(coalesce(cm.phone, ''), '[^0-9]', '', 'g'), 9) = v_tail)
  )
  select coalesce(jsonb_agg(jsonb_build_object('at', e.at, 'kind', e.kind, 'channel', e.channel, 'direction', e.direction,
                                               'seat', e.seat, 'ref', e.ref, 'summary', e.summary) order by e.at desc), '[]'::jsonb)
    into v_events
    from (select * from ev where at is not null order by at desc limit greatest(1, least(coalesce(p_limit, 60), 500))) e;

  select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) into v_counts
    from (select x ->> 'kind' k, count(*) n from jsonb_array_elements(v_events) x group by 1) z;

  return jsonb_build_object(
    'contact', coalesce(v_email, v_tail),
    'known', cardinality(v_cust) + cardinality(v_lead) > 0,
    'customer_ids', to_jsonb(v_cust), 'supplier_lead_ids', to_jsonb(v_lead),
    'event_count', jsonb_array_length(v_events), 'counts', v_counts,
    'events', v_events,
    'assembled_by', 'fn_contact_timeline (deterministic; no model)');
end $function$;


-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- PART B. THE MONEY
-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- A REFUND RETURNS EVERYTHING THE CUSTOMER PAID, AND THE SUPPLIER REPAYS EXACTLY THAT.
--
-- Assigned: accountant. Carried out for the ceo.
--
-- The founder, 14 Sep 2026:
--   the reveal charge is 3% of the chosen quote plus Stripe's processing fee, grossed up so QuotesDone
--   nets 3%; there is no VAT. When a reveal is refunded the customer gets back the full amount they
--   paid, the 3% and the processing part together, and QuotesDone absorbs Stripe's fee.
--   "the exact amount that was refunded with the processing fees from stripe will be charged to the
--    supplier along with 250 AED admin fees and 9% yearly interest as per UAE law."
--
-- MEASURED BEFORE WRITING (14 Sep 2026, production):
--   * transactions.total_charged, processing_fee and stripe_fee_fils exist (the_accountant_files_the_reveal_
--     invoice_and_the_sales_engineer_tells_the_customer.sql) and stripe_webhook writes them. Nothing READ them:
--   * a00_refund_amount_is_the_fee_paid required refunds.amount_fils = reveal_fee, so a refund of the
--     full charge would have been REFUSED by the database. fn_refund_open_from_customer,
--     fn_refund_ladder_sweep and fn_support_investigate_refund all computed the refund from reveal_fee.
--   * qd_on_refund_resolved -- the routine that raised the supplier's charge -- is bound to NO
--     trigger (pg_trigger, 0 rows). refunds_api's own comment says "'refunded' fires the DB trigger:
--     creates the 3% non-response due"; nothing fires. A refunded customer produced no supplier charge.
--   * fn_supplier_nonresponse_penalty computed the charge as 3% of the JOB VALUE with interest from the
--     refund date. It has no caller (pg_proc prosrc scan, repository scan) and contradicts the rule above.
--   * fn_gl_sync_business posted a refund only for refund_status 'refunded'/'refund_approved'; the
--     refunds-table path writes 'succeeded', so a refund settled through Stripe never reached the ledger.
--
-- WHAT THIS FILE MAKES TRUE
--   * a refund's amount is transactions.total_charged (everything the customer paid), still cited
--     against the exact Stripe payment_ref, still strict.
--   * ONE routine computes the supplier's charge, from the refund record itself, never recomputed from
--     a rate: fn_accountant_nonresponse_charge. Base = the amount actually refunded, capped at the
--     amount the CEO approved (an over-refund is the company's loss, never the supplier's); + the admin
--     fee from pricing_config; + simple interest on (base + admin) at min(pricing_config APR, the lawful
--     maximum in decision_policy) from the charge's due date. Interest is recomputed absolutely, so
--     running the accrual twice changes nothing.
--   * When a refund settles, the accountant raises that charge (once), hands the supplier's message and
--     the customer's message to the sales engineer, and the CEO re-verifies the whole thing.
--   * The absorbed Stripe fee is a cost in the books (6100): stripe_fee_fils when Stripe reported it,
--     else processing_fee, else the gl_settings estimate the ledger already used.
--   * A circuit breaker (decision_policy.refunds_and_supplier_charges_paused) that every refund and
--     charge path reads. Only the CEO's mismatch playbook sets it.
--

insert into public.founder_instruction (said_at, instruction, subject, status, evidence)
select '2026-09-14T00:00:00Z', x.i, x.s, 'done', 'scripts/sql/payments_are_the_accountant_and_the_seats_close_every_refund_together.sql'
  from (values
    ('the exact amount that was refunded with the processing fees from stripe will be charged to the supplier along with 250 AED admin fees and 9% yearly interest as per UAE law.', 'supplier non-response charge'),
    ('when a reveal is refunded, the customer gets back the full amount they paid: the 3% and the processing part together. QuotesDone absorbs Stripe''s fee.', 'refund returns total charged')) x(i, s)
 where not exists (select 1 from public.founder_instruction f where f.instruction = x.i);

-- ── 1. WHAT STRIPE TOOK ──────────────────────────────────────────────────────────────────────────
-- transactions.total_charged (everything the customer paid), processing_fee (the card line on top of the
-- 3%) and stripe_fee_fils (what Stripe actually kept) are the_accountant_files_the_reveal_invoice_and_the_
-- sales_engineer_tells_the_customer.sql's columns, written by stripe_webhook. This file only reads them.

-- ── 2. THE TERMS THAT ARE NOT IN pricing_config ──────────────────────────────────────────────────
insert into public.decision_policy (key, value, description) values
  ('supplier_charge_due_days', '7'::jsonb, 'Days after the customer''s refund settles that the supplier''s non-response charge falls due; interest runs from that date. The value the estate''s charges already used (supplier_dues.due_date = raised + 7).'),
  ('supplier_charge_max_lawful_apr', '0.09'::jsonb, 'The ceiling on the supplier charge''s simple annual interest. The founder, 14 Sep 2026: "9% yearly interest as per UAE law". fn_accountant_nonresponse_charge applies min(pricing_config APR, this).'),
  ('refunds_and_supplier_charges_paused', 'false'::jsonb, 'The CEO''s circuit breaker. true while a post-payment mismatch is open: no automated refund is executed and no supplier charge is raised. Set and lifted only by fn_ceo_refund_mismatch_playbook / fn_ceo_incident_advance.'),
  ('refund_final_call_watch_working_days', '1'::jsonb, 'Working days customer_support watches for a reply after the day-5 final call before it may confirm no response.')
on conflict (key) do nothing;

create or replace function public.fn_refunds_paused()
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce((select (d.value #>> '{}')::boolean from public.decision_policy d
                    where d.key = 'refunds_and_supplier_charges_paused'), false);
$fn$;
revoke execute on function public.fn_refunds_paused() from public, anon, authenticated;

-- ── 3. THE ONE ROUTINE THAT COMPUTES THE SUPPLIER'S CHARGE ───────────────────────────────────────
create or replace function public.fn_accountant_nonresponse_charge(p_transaction_id uuid, p_as_of date default null)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  t public.transactions; c public.pricing_config; v_n int; v_sum bigint;
  v_refunded numeric; v_approved numeric; v_base numeric; v_settled timestamptz; v_src text;
  v_cap numeric; v_apr numeric; v_due_days int; v_due date; v_as_of date; v_days int; v_int numeric;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such transaction'); end if;

  -- THE REFUND RECORD: every refund Stripe settled against this payment, summed (a top-up the CEO's
  -- playbook issued is part of what the customer got back), dated from the FIRST settlement so a
  -- top-up does not move the due date. The approved amount caps it, so a duplicate or an over-refund
  -- is the company's loss and never a larger charge on the supplier.
  select count(*), sum(x.amount_fils), min(coalesce(x.settled_at, x.updated_at)),
         string_agg(coalesce(x.stripe_refund_id, 'refunds #' || x.id), ', ' order by x.id)
    into v_n, v_sum, v_settled, v_src
    from public.refunds x
   where x.status = 'succeeded' and x.amount_fils is not null
     and (x.transaction_id = p_transaction_id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref));
  select a.amount_aed into v_approved
    from public.refunds x join public.ceo_approval a on a.decision_id = x.refund_decision_id
   where x.transaction_id = p_transaction_id and a.decision = 'approved' order by x.id desc limit 1;
  if v_n > 0 then
    v_refunded := round(v_sum / 100.0, 2);
    v_src      := v_n || ' settled refund(s): ' || v_src;
  elsif t.refund_amount_aed is not null and coalesce(t.refund_status, '') in ('refunded', 'succeeded') then
    v_refunded := round(t.refund_amount_aed, 2);
    v_settled  := coalesce(t.refund_confirmed_at, t.refund_resolved_at);
    v_src      := 'transactions.refund_amount_aed (Stripe ' || coalesce(t.refund_stripe_id, 'reference not recorded') || ')';
  else
    return jsonb_build_object('ok', false, 'reason', 'no settled refund on this transaction, so there is nothing to recover from the supplier');
  end if;
  if v_settled is null then
    return jsonb_build_object('ok', false, 'reason', 'the refund carries no settlement time, so the charge''s due date cannot be set');
  end if;

  v_approved := coalesce(v_approved, t.total_charged, t.reveal_fee, v_refunded);
  v_base     := least(v_refunded, v_approved);

  select * into c from public.pricing_config order by id limit 1;
  v_cap      := (select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'supplier_charge_max_lawful_apr');
  v_apr      := least(c.supplier_nonresponse_interest_apr, coalesce(v_cap, c.supplier_nonresponse_interest_apr));
  v_due_days := coalesce((select (d.value #>> '{}')::int from public.decision_policy d where d.key = 'supplier_charge_due_days'), 7);
  v_due      := (v_settled at time zone 'Asia/Dubai')::date + v_due_days;
  v_as_of    := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  v_days     := greatest(v_as_of - v_due, 0);
  v_int      := round((v_base + c.supplier_nonresponse_admin_fee_aed) * v_apr * v_days / 365.0, 2);

  return jsonb_build_object(
    'ok', true, 'transaction_id', t.id, 'supplier_id', t.supplier_id,
    'refunded_aed', v_base, 'actually_refunded_aed', v_refunded, 'approved_aed', v_approved, 'refund_source', v_src,
    'admin_fee_aed', c.supplier_nonresponse_admin_fee_aed,
    'interest_apr', v_apr, 'interest_apr_configured', c.supplier_nonresponse_interest_apr, 'interest_apr_lawful_max', v_cap,
    'due_date', v_due, 'as_of', v_as_of, 'interest_days', v_days, 'interest_aed', v_int,
    'total_aed', round(v_base + c.supplier_nonresponse_admin_fee_aed + v_int, 2),
    'basis', 'base = the amount refunded to the customer, read from the refund record and capped at the amount the CEO approved; '
          || '+ the administration fee from pricing_config; + simple interest on (base + admin fee) at the lower of pricing_config''s APR and '
          || 'the lawful maximum, from the due date (' || v_due_days || ' days after the refund settled) to the as-of date. Nothing is typed.');
end $fn$;
revoke execute on function public.fn_accountant_nonresponse_charge(uuid, date) from public, anon, authenticated;

-- Absolute, so a second run the same day changes nothing.
create or replace function public.fn_supplier_dues_accrue_interest(p_as_of date default null)
returns int language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare x record; v jsonb; n int := 0;
begin
  for x in select id, transaction_id from public.supplier_dues
            where paid_at is null and transaction_id is not null
              and coalesce(status, '') not in ('paid', 'settled', 'waived', 'cancelled') loop
    v := public.fn_accountant_nonresponse_charge(x.transaction_id, p_as_of);
    continue when not coalesce((v->>'ok')::boolean, false);
    update public.supplier_dues
       set interest_amount = (v->>'interest_aed')::numeric, total_claim = amount_due + coalesce(admin_fee, 0) + (v->>'interest_aed')::numeric
     where id = x.id
       and (interest_amount is distinct from (v->>'interest_aed')::numeric
            or total_claim is distinct from amount_due + coalesce(admin_fee, 0) + (v->>'interest_aed')::numeric);
    if found then n := n + 1; end if;
  end loop;
  return n;
end $fn$;
revoke execute on function public.fn_supplier_dues_accrue_interest(date) from public, anon, authenticated;

-- Raises the charge ONCE per transaction (supplier_dues allows one row per transaction; the CEO's
-- playbook corrects a wrong one in place), blocks matching, and hands the supplier's message to the
-- sales engineer.
create or replace function public.fn_accountant_raise_nonresponse_charge(p_transaction_id uuid, p_notify boolean default true)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v jsonb; t public.transactions; v_due bigint; v_new boolean := false;
begin
  if public.fn_refunds_paused() and coalesce(current_setting('app.qd_incident_fix', true), '') <> 'on' then
    return jsonb_build_object('ok', false, 'held', true,
      'reason', 'refunds and supplier charges are paused by the CEO''s circuit breaker; fn_ceo_refund_loop_sweep raises this charge when it lifts');
  end if;
  v := public.fn_accountant_nonresponse_charge(p_transaction_id, null);
  if not coalesce((v->>'ok')::boolean, false) then return v; end if;
  select * into t from public.transactions where id = p_transaction_id;

  select id into v_due from public.supplier_dues
   where transaction_id = p_transaction_id and coalesce(status, '') <> 'cancelled' order by id limit 1;
  if v_due is null then
    insert into public.supplier_dues (transaction_id, supplier_id, quote_id, quote_amount, commission_pct,
                                      amount_due, admin_fee, interest_amount, total_claim, currency,
                                      reveal_date, due_date, due_date_30, status)
    values (t.id, t.supplier_id, t.quote_id, t.quote_amount, null,
            (v->>'refunded_aed')::numeric, (v->>'admin_fee_aed')::numeric, (v->>'interest_aed')::numeric, (v->>'total_aed')::numeric, 'AED',
            (t.revealed_at at time zone 'Asia/Dubai')::date, (v->>'due_date')::date, (v->>'due_date')::date + 23, 'due')
    returning id into v_due;
    update public.leads
       set matching_blocked = true,
           matching_block_reason = 'Unsettled non-response charge (the customer was refunded because the supplier did not respond)',
           rv_nonresponse_refunds = coalesce(rv_nonresponse_refunds, 0) + 1
     where id = t.supplier_id;
    v_new := true;
  end if;

  if p_notify then
    perform public.fn_seat_handoff('accountant', 'sales_engineer', 'nonresponse.charge_raised', 'supplier_dues', v_due::text,
      v || jsonb_build_object('due_id', v_due, 'transaction_id', t.id, 'supplier_id', t.supplier_id,
                              'inquiry_id', t.inquiry_id, 'quote_id', t.quote_id));
  end if;
  return v || jsonb_build_object('due_id', v_due, 'created', v_new);
end $fn$;
revoke execute on function public.fn_accountant_raise_nonresponse_charge(uuid, boolean) from public, anon, authenticated;

-- ── 4. WHEN A REFUND SETTLES, OR IS DECLINED, OR FAILS ───────────────────────────────────────────
create or replace function public.fn_accountant_refund_settled(p_transaction_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare t public.transactions; v_reason text; v_charge jsonb; v_verify jsonb;
begin
  select * into t from public.transactions where id = p_transaction_id;
  select coalesce((select r.reason_code from public.refunds r where r.transaction_id = t.id order by r.id desc limit 1),
                  t.refund_reason, 'supplier_unresponsive') into v_reason;
  if v_reason = 'supplier_unresponsive' then
    v_charge := public.fn_accountant_raise_nonresponse_charge(t.id, true);
  end if;
  perform public.fn_seat_handoff('accountant', 'sales_engineer', 'refund.paid', 'transactions', t.id::text,
    jsonb_build_object('transaction_id', t.id, 'customer_id', t.customer_id, 'supplier_id', t.supplier_id,
                       'inquiry_id', t.inquiry_id, 'quote_id', t.quote_id, 'revealed_at', t.revealed_at,
                       'amount_aed', round(t.refund_amount_aed, 2)));
  v_verify := public.fn_ceo_refund_verify(t.id);
  return jsonb_build_object('charge', v_charge, 'verify', v_verify);
end $fn$;
revoke execute on function public.fn_accountant_refund_settled(uuid) from public, anon, authenticated;

create or replace function public.fn_transaction_refund_outcome_follows_through()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if NEW.refund_status in ('succeeded', 'refunded') and NEW.refund_amount_aed is not null
     and (OLD.refund_status is distinct from NEW.refund_status or OLD.refund_amount_aed is distinct from NEW.refund_amount_aed) then
    begin
      perform public.fn_accountant_refund_settled(NEW.id);
    exception when others then
      insert into public.ceo_task (title, detail)
      values (left('Refund on reveal ' || left(NEW.id::text, 8) || ' settled but its follow-through failed', 200),
              'fn_accountant_refund_settled raised: ' || sqlerrm || '. The refund itself is recorded; the supplier charge, the customer''s message or the re-verification did not complete.');
    end;
  elsif NEW.refund_status = 'failed' and OLD.refund_status is distinct from 'failed' then
    perform public.fn_ceo_refund_verify(NEW.id);
  elsif NEW.refund_status = 'rejected' and OLD.refund_status is distinct from 'rejected' then
    perform public.fn_seat_handoff('accountant', 'sales_engineer', 'refund.declined', 'transactions', NEW.id::text,
      jsonb_build_object('transaction_id', NEW.id, 'customer_id', NEW.customer_id, 'inquiry_id', NEW.inquiry_id,
                         'quote_id', NEW.quote_id, 'note', NEW.refund_note));
  end if;
  return NEW;
end $fn$;
revoke execute on function public.fn_transaction_refund_outcome_follows_through() from public, anon, authenticated;
drop trigger if exists z40_refund_outcome_follows_through on public.transactions;
create trigger z40_refund_outcome_follows_through
  after update of refund_status, refund_amount_aed on public.transactions
  for each row execute function public.fn_transaction_refund_outcome_follows_through();

-- The accountant's side of a CEO rejection: the one pre-approval check it owns is the amount.
create or replace function public.fn_accountant_remediates(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare d jsonb; v_fils bigint; v_n int;
begin
  select detail into d from public.agent_actions where id = p_id;
  if d->'checks' ? 'amount_equals_total_charged' then
    update public.refunds r
       set amount_fils = round(coalesce(t.total_charged, t.reveal_fee) * 100)::bigint
      from public.transactions t
     where r.id = (d->>'refund_id')::bigint and t.id = r.transaction_id and r.status = 'requested'
    returning r.amount_fils into v_fils;
    get diagnostics v_n = row_count;
    return jsonb_build_object('fixed', v_n = 1, 'amount_fils', v_fils,
      'basis', 'refunds.amount_fils set to the payment''s total_charged; a00_refund_amount_is_the_fee_paid re-checked it against the Stripe reference on write');
  end if;
  return jsonb_build_object('waiting', 'no automatic remedy for ' || coalesce(d->>'checks', '?') || '; the accountant runtime or a person must act');
end $fn$;
revoke execute on function public.fn_accountant_remediates(bigint) from public, anon, authenticated;

-- ── 5. RETIRED: two routines that computed the charge the wrong way ─────────────────────────────
drop function if exists public.qd_on_refund_resolved();
drop function if exists public.fn_supplier_nonresponse_penalty(numeric, date, date);

-- ── 6. THE FOUR ROUTINES THAT READ THE REFUND FROM reveal_fee, now reading total_charged ──────────
-- Each is the live definition with only the amount changed (the edits are listed in the PR).
CREATE OR REPLACE FUNCTION public.fn_refund_amount_is_the_fee_paid()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t public.transactions%rowtype;
  v_expected bigint;
  -- A refund Stripe already issued is a fact to be recorded, not a request to be approved.
  v_external constant text[] := array['stripe_webhook','stripe_dashboard','stripe'];
begin
  if lower(coalesce(NEW.requested_by,'')) = any(v_external) then
    return NEW;
  end if;

  if NEW.transaction_id is null then
    raise exception 'refunds: a refund must name the transaction it reverses. transaction_id is null, so this row asserts money is owed without saying which payment it came from. (refund_names_no_payment)'
      using errcode = '23514',
            hint = 'Set transaction_id to the public.transactions row whose reveal_fee is being returned. A refund this platform did not issue is recorded through fn_refund_settle with requested_by stripe_webhook, and that path is exempt.';
  end if;

  select * into t from public.transactions where id = NEW.transaction_id;
  if not found then
    raise exception 'refunds: transaction % does not exist. (refund_transaction_absent)',
      NEW.transaction_id using errcode = '23503';
  end if;

  if coalesce(t.total_charged, t.reveal_fee) is null or coalesce(t.total_charged, t.reveal_fee) <= 0 then
    raise exception 'refunds: transaction % records no reveal fee (reveal_fee %), so there is nothing to give back. A refund of an unpaid reveal is a payment, not a refund. (refund_no_fee_was_paid)',
      NEW.transaction_id, coalesce(t.reveal_fee::text,'null') using errcode = '23514';
  end if;

  if t.refund_deadline is null then
    raise exception 'refunds: transaction % has no refund window. trg_reveal_window opens one at reveal, so a transaction without it was never revealed and no refund can be due yet. (refund_window_not_open)',
      NEW.transaction_id using errcode = '23514';
  end if;
  if now() < t.refund_deadline then
    raise exception 'refunds: the refund window on transaction % opens at % and it is now %. The customer waits the founder-set period of working days after the reveal before a refund can be claimed. (refund_window_not_yet_open)',
      NEW.transaction_id, t.refund_deadline, now() using errcode = '23514';
  end if;

  -- ── THE STRIPE REFERENCE, ADDED 9 SEP 2026 ───────────────────────────────────────────────────
  -- The founder: "it's issued against that exact invoice reference... It has an ID." The reference
  -- Stripe gave us when the customer paid is transactions.payment_ref (stripe_webhook writes the
  -- payment_intent, falling back to the checkout session id). Until now stripe_payment_intent on a
  -- refund was a nullable text column nothing checked, so a refund could name transaction A and
  -- cite the payment of transaction B -- or name no payment at all -- and still move money.
  if coalesce(btrim(t.payment_ref), '') = '' then
    raise exception 'refunds: transaction % carries no Stripe payment reference, so there is no payment of record to reverse. (refund_payment_has_no_reference)',
      NEW.transaction_id using errcode = '23514',
            hint = 'transactions.payment_ref is written by stripe_webhook when the reveal fee settles. A transaction without one was never paid through Stripe, and money must not be returned against a payment nobody can point at.';
  end if;
  if coalesce(btrim(NEW.stripe_payment_intent), '') = '' then
    raise exception 'refunds: this refund names no Stripe payment. Transaction % was paid under reference %, and a refund is issued against that exact reference. (refund_names_no_stripe_reference)',
      NEW.transaction_id, t.payment_ref using errcode = '23514',
            hint = 'Set stripe_payment_intent to the payment_ref of the transaction being reversed. Founder ruling, 9 Sep 2026.';
  end if;
  if btrim(NEW.stripe_payment_intent) <> btrim(t.payment_ref) then
    raise exception 'refunds: this refund cites Stripe payment %, but transaction % was paid under %. A refund is issued against the exact reference of the payment it reverses, never another one. (refund_cites_the_wrong_stripe_payment)',
      NEW.stripe_payment_intent, NEW.transaction_id, t.payment_ref using errcode = '23514';
  end if;

  -- AND THE AMOUNT IS READ OFF THAT PAYMENT. Equality, not a ceiling: the reveal fee is refunded
  -- whole or not at all, so "cannot exceed what the payment took" is enforced by the stricter rule
  -- that it must EQUAL it. A platform refund with no amount is refused outright -- an unstated
  -- figure is not a smaller figure, it is an unbounded one.
  v_expected := round(coalesce(t.total_charged, t.reveal_fee) * 100)::bigint;
  if NEW.amount_fils is null then
    raise exception 'refunds: a platform refund must state its amount. Transaction % took % fils (AED %), and that is the only figure this refund may carry. (refund_states_no_amount)',
      NEW.transaction_id, v_expected, round(coalesce(t.total_charged, t.reveal_fee),2) using errcode = '23514';
  end if;
  if NEW.amount_fils <> v_expected then
    raise exception 'refunds: the amount must equal what the customer actually paid, the 3%% and the processing part together (total_charged), on transaction % — expected % fils (AED %), got % fils (AED %). A refund figure is read off the payment, never typed. (refund_amount_is_not_the_fee_paid)',
      NEW.transaction_id, v_expected, round(coalesce(t.total_charged, t.reveal_fee),2), NEW.amount_fils, round(NEW.amount_fils/100.0,2)
      using errcode = '23514';
  end if;

  return NEW;
end
$function$;

CREATE OR REPLACE FUNCTION public.fn_refund_open_from_customer(p_transaction_id uuid, p_requested_by text, p_reason_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t record; v_id bigint; v_existing bigint;
begin
  select tr.*, q.supplier_id
    into t
    from public.transactions tr
    left join public.quotes q on q.id = tr.quote_id
   where tr.id = p_transaction_id;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no such transaction');
  end if;

  -- A sale that never took money cannot be refunded. Checked here rather than left to Stripe,
  -- because the customer is told something either way and it must be the truth.
  if coalesce(t.payment_ref, '') = '' then
    return jsonb_build_object('ok', false, 'reason',
      'this reveal has no recorded payment, so there is nothing to refund');
  end if;
  if t.revealed_at is null then
    return jsonb_build_object('ok', false, 'reason', 'this reveal has not completed');
  end if;

  -- ONE CLAIM PER PAYMENT. A customer pressing the button twice, or a retry, must not open a
  -- second case — two cases on one payment is how one refund gets paid twice.
  select id into v_existing from public.refunds
   where transaction_id = p_transaction_id
     and status not in ('rejected', 'failed', 'cancelled')
   order by id limit 1;
  if v_existing is not null then
    return jsonb_build_object('ok', true, 'duplicate', true, 'refund_id', v_existing,
      'note', 'A refund request already exists for this reveal and is being reviewed.');
  end if;

  insert into public.refunds
    (transaction_id, quote_id, inquiry_id, customer_id, supplier_lead_id,
     stripe_payment_intent, amount_fils, currency, reason_code, reason_note,
     status, requested_by, requested_at, amount_source)
  values
    (p_transaction_id, t.quote_id, t.inquiry_id, t.customer_id, t.supplier_id,
     t.payment_ref,
     round(coalesce(t.total_charged, t.reveal_fee, 0) * 100)::bigint, 'AED',
     'supplier_unresponsive',
     coalesce(p_reason_note, 'The customer reported that the revealed supplier has not responded.'),
     'requested', coalesce(p_requested_by, 'customer'), now(), 'in_platform_request')
  returning id into v_id;

  return jsonb_build_object('ok', true, 'refund_id', v_id,
    'status', 'requested',
    'next', 'customer_support checks whether the supplier ever answered; the CEO decides on that '
         || 'record; the accountant pays and raises the supplier penalty. The customer asking is '
         || 'the trigger, not the verdict.');
end $function$;

CREATE OR REPLACE FUNCTION public.fn_support_investigate_refund(p_transaction_id uuid, p_reason text, p_case_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t record; v_grant jsonb; v_id bigint; v_elig text; v_why text; v_prior int;
begin
  v_grant := public.fn_support_may_act('refund');
  if (v_grant->>'may_act') <> 'true' then
    return jsonb_build_object('ok', false, 'reason', v_grant->>'reason', 'route', v_grant->>'route');
  end if;

  select id, quote_amount, reveal_fee, total_charged, fee_status, refund_status, refund_amount_aed
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
     coalesce(t.total_charged, t.reveal_fee, 0), p_reason, now(),
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

CREATE OR REPLACE FUNCTION public.fn_gl_sync_business()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; n int := 0; acct text;
        fee_pct numeric; fee_fixed numeric; fee numeric(18,2); gross numeric(18,2); net numeric(18,2);
        fx numeric; amt_aed numeric(18,2); diff numeric(18,2); extra numeric(18,2); lines jsonb;
begin
  select num_value into fee_pct   from public.gl_settings where key='stripe_fee_pct';
  select num_value into fee_fixed from public.gl_settings where key='stripe_fee_fixed';
  select num_value into fx        from public.gl_settings where key='usd_to_aed';
  fee_pct   := coalesce(fee_pct,0);
  fee_fixed := coalesce(fee_fixed,0);
  fx        := coalesce(fx, 3.6725);

  -- 1) Reveal-fee revenue with Stripe fee split (refunded transactions excluded)
  for r in
    select id, reveal_fee, total_charged, processing_fee, stripe_fee_fils, coalesce(revealed_at::date, current_date) as d
    from public.transactions
    where fee_status='paid' and coalesce(reveal_fee,0) > 0
      and coalesce(refund_status,'') not in ('refunded','refund_approved','succeeded')
      and not exists (select 1 from public.gl_journal g where g.source='reveal_fee' and g.source_ref=transactions.id::text)
  loop
    gross := round(coalesce(r.total_charged, r.reveal_fee),2);
    fee   := coalesce(round(r.stripe_fee_fils / 100.0, 2), r.processing_fee, round(gross*fee_pct/100 + fee_fixed, 2));
    if fee >= gross then fee := 0; end if;
    net   := gross - fee;
    perform public.fn_gl_entry(r.d, 'Reveal fee (net of Stripe fee)', 'reveal_fee', r.id::text,
      case when fee > 0 then
        jsonb_build_array(
          jsonb_build_object('account','1050','debit',net),
          jsonb_build_object('account','6100','debit',fee),
          jsonb_build_object('account','4000','credit',gross))
      else
        jsonb_build_array(
          jsonb_build_object('account','1050','debit',gross),
          jsonb_build_object('account','4000','credit',gross))
      end, 'gl_sync');
    n := n + 1;
  end loop;

  -- 1b) REFUND PAID OUT: everything the customer paid (total_charged) goes back. Stripe keeps its
  --     processing fee and QuotesDone absorbs it (founder, 14 Sep 2026). 'succeeded' is the status the
  --     refunds-table path writes, and it was missing here, so a Stripe-settled refund never posted.
  --     If the sale was booked, the refund reverses it through 6900 and the fee booked at sale stays in
  --     6100 as the absorbed cost. If it was not, the only real movement is the fee: 6100 / 1050.
  for r in
    select t.id, coalesce(t.total_charged, t.reveal_fee, t.app_fee, 0) as amt,
           coalesce(round(t.stripe_fee_fils / 100.0, 2), t.processing_fee, round(coalesce(t.total_charged, t.reveal_fee, t.app_fee, 0)*fee_pct/100 + fee_fixed, 2)) as fee_absorbed,
           exists (select 1 from public.gl_journal g where g.source='reveal_fee' and g.source_ref=t.id::text) as sale_booked,
           coalesce(t.refund_resolved_at::date, t.revealed_at::date, current_date) as d
    from public.transactions t
    where coalesce(t.refund_status,'') in ('refunded','refund_approved','succeeded')
      and coalesce(t.total_charged, t.reveal_fee, t.app_fee, 0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='refund_paid' and g.source_ref=t.id::text)
  loop
    gross := round(r.amt,2);
    if r.sale_booked then
      perform public.fn_gl_entry(r.d, 'Reveal charge refunded in full to the customer; the Stripe fee booked at sale stays in 6100, absorbed',
        'refund_paid', r.id::text,
        jsonb_build_array(jsonb_build_object('account','6900','debit',gross),
                          jsonb_build_object('account','1050','credit',gross)), 'gl_sync');
      n := n + 1;
    else
      fee := least(round(coalesce(r.fee_absorbed,0),2), gross);
      if fee > 0 then
        perform public.fn_gl_entry(r.d, 'Stripe processing fee absorbed on a reveal refunded in full before its sale was booked',
          'refund_paid', r.id::text,
          jsonb_build_array(jsonb_build_object('account','6100','debit',fee),
                            jsonb_build_object('account','1050','credit',fee)), 'gl_sync');
        n := n + 1;
      end if;
    end if;
  end loop;

  -- 2) Clawback RAISED on the supplier. Credits 6900 (recovering the refund), NOT 4100.
  --    Any admin fee / interest assessed at the same time is genuine income -> 4400.
  for r in
    select id, amount_due,
           coalesce(admin_fee,0) + coalesce(interest_amount,0) as extra_owed,
           coalesce(reveal_date, created_at::date, current_date) as d
    from public.supplier_dues
    where coalesce(amount_due,0) > 0
      and coalesce(status,'') not in ('waived','cancelled','reversed')
      and not exists (select 1 from public.gl_journal g where g.source='commission_accrue' and g.source_ref=supplier_dues.id::text)
  loop
    extra := round(coalesce(r.extra_owed,0),2);
    lines := jsonb_build_array(
      jsonb_build_object('account','1110','debit', round(r.amount_due,2) + extra),
      jsonb_build_object('account','6900','credit', round(r.amount_due,2)));
    if extra > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','4400','credit', extra)); end if;
    perform public.fn_gl_entry(r.d,
      'Refund clawback raised on supplier' || case when extra > 0 then ' (incl. ' || extra || ' admin fee/interest)' else '' end,
      'commission_accrue', r.id::text, lines, 'gl_sync');
    n := n + 1;
  end loop;

  -- 2b) Supplier SETTLES via Stripe.
  for r in
    select id, amount_due,
           coalesce(fine_amount,0) + coalesce(interest_amount,0) + coalesce(admin_fee,0) as extra_owed,
           paid_at::date as d
    from public.supplier_dues
    where status in ('paid','settled') and paid_at is not null and coalesce(amount_due,0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='commission_collect' and g.source_ref=supplier_dues.id::text)
  loop
    extra := round(coalesce(r.extra_owed,0),2);
    gross := round(r.amount_due,2) + extra;
    fee   := round(gross*fee_pct/100 + fee_fixed, 2);
    if fee >= gross then fee := 0; end if;
    net   := gross - fee;

    lines := jsonb_build_array(jsonb_build_object('account','1050','debit',net));
    if fee > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','6100','debit',fee)); end if;
    lines := lines || jsonb_build_array(jsonb_build_object('account','1110','credit', gross));

    perform public.fn_gl_entry(r.d,
      'Refund clawback settled by supplier via Stripe' || case when extra > 0 then ' (incl. ' || extra || ' admin fee/interest)' else '' end,
      'commission_collect', r.id::text, lines, 'gl_sync');
    n := n + 1;
  end loop;

  -- 2c) SUBSCRIPTION revenue (RULE 1). Previously never posted - 4200 sat unused.
  for r in
    select l.id, l.registration_fee_due, l.registration_paid_at::date as d
    from public.leads l
    where l.registration_status = 'paid'
      and l.registration_paid_at is not null
      and coalesce(l.registration_fee_due,0) >= 0
      and coalesce(l.subscription_exempt,false) = false
      and not exists (select 1 from public.gl_journal g
                      where g.source='subscription' and g.source_ref = l.id::text || ':' || l.registration_paid_at::date)
  loop
    gross := round(coalesce(r.registration_fee_due,0),2);
    if gross <= 0 then continue; end if;
    fee := round(gross*fee_pct/100 + fee_fixed, 2);
    if fee >= gross then fee := 0; end if;
    net := gross - fee;
    lines := jsonb_build_array(jsonb_build_object('account','1050','debit',net));
    if fee > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','6100','debit',fee)); end if;
    lines := lines || jsonb_build_array(jsonb_build_object('account','4200','credit',gross));
    perform public.fn_gl_entry(r.d, 'Annual supplier subscription', 'subscription',
      r.id::text || ':' || r.d::text, lines, 'gl_sync');
    n := n + 1;
  end loop;

  -- 3) Expense charges, converted to AED (the ledger currency)
  for r in
    select e.id, e.amount, upper(coalesce(e.currency,'AED')) as cur, e.category, e.vendor,
           coalesce(e.charged_on, e.created_at::date) as d
    from public.expense_entries e
    where coalesce(e.amount,0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='expense' and g.source_ref=e.id::text)
  loop
    if r.cur not in ('AED','USD') then
      begin
        insert into public.founder_alerts(level, event, detail, channel)
        values ('warn', 'gl_unconvertible_currency',
                'Expense #'||r.id||' from '||coalesce(r.vendor,'?')||' is in '||r.cur||
                ', which has no rate in gl_settings, so it was NOT posted. Expenses are understated by '||
                r.amount||' '||r.cur||' until a rate is added. Skipped rather than booked at 1:1.', 'system');
      exception when others then null; end;
      continue;
    end if;
    amt_aed := round(r.amount * case when r.cur='USD' then fx else 1 end, 2);
    acct := coalesce((select account_code from public.gl_expense_map m where m.category=r.category), '6300');
    perform public.fn_gl_entry(r.d,
      'Expense: '||coalesce(r.category,'G&A')||case when r.cur='USD' then ' ('||r.amount||' USD @ '||fx||')' else '' end,
      'expense', r.id::text,
      jsonb_build_array(jsonb_build_object('account',acct,'debit',amt_aed),
                        jsonb_build_object('account','1000','credit',amt_aed)), 'gl_sync');
    n := n + 1;
  end loop;

  -- 3b) One-off FX correction for USD expenses posted at 1:1 before the 19 Jul 2026 fix.
  for r in
    select e.id, e.amount, e.category, e.vendor,
           coalesce(e.charged_on, e.created_at::date) as d,
           (select sum(jl.debit) from public.gl_journal g
              join public.gl_journal_lines jl on jl.journal_id = g.id
             where g.source='expense' and g.source_ref = e.id::text and jl.debit > 0) as posted_aed
    from public.expense_entries e
    where upper(coalesce(e.currency,'AED')) = 'USD'
      and coalesce(e.amount,0) > 0
      and exists (select 1 from public.gl_journal g where g.source='expense' and g.source_ref=e.id::text)
      and not exists (select 1 from public.gl_journal g where g.source='expense_fx_adj' and g.source_ref=e.id::text)
  loop
    diff := round(r.amount * fx, 2) - coalesce(r.posted_aed, 0);
    if diff is null or diff = 0 then continue; end if;
    acct := coalesce((select account_code from public.gl_expense_map m where m.category=r.category), '6300');
    perform public.fn_gl_entry(r.d,
      'FX correction: expense #'||r.id||' ('||coalesce(r.vendor,'?')||') was booked at 1:1; restated at USD/AED '||fx,
      'expense_fx_adj', r.id::text,
      jsonb_build_array(jsonb_build_object('account',acct,'debit',diff),
                        jsonb_build_object('account','1000','credit',diff)), 'gl_fx_fix');
    n := n + 1;
  end loop;

  return n;
end
$function$;


-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- PART C. THE CEO
-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- THE CEO CHECKS EVERY STEP OF A REFUND, SENDS BACK WHAT IS WRONG, AND FIXES WHAT DID NOT MATCH.
--
-- Assigned: ceo (the checklist, the review loop, the mismatch playbook), with sales_engineer (the
-- ladder's words and the case evidence), customer_support (delivery and the watch for a reply) and
-- accountant (the money). Carried out for the ceo.
--
-- The founder, 14 Sep 2026:
--   "ceo approval on refund was made so that the CEO make sure that the process was fully done
--    correctly. he is my eyes in the company basically. so the wiring need to be 100% correct"
--   "the CEO is also able to communicate with accountant and sales agent to mention why he rejected.
--    and those would act accordingly and once they are done, the CEO checks again if all good to approve."
--   "the sales engineer is connected properly to the customer support agent to deliver the messages and
--    communicate with the supplier to confirm he is not responding? and then he gets back with either a
--    proof or no response confirmation. thats another loop within that bigger loop."
--   and approved a playbook for a post-payment mismatch: pause, open an incident, fix by type, re-run
--   the checklist, resume only when green, and send him one short WhatsApp summary.
--
-- MEASURED BEFORE WRITING (14 Sep 2026, production):
--   * nothing calls fn_refund_ladder_sweep. pg_cron went on 7 Sep; no edge function, no tick. The day-3
--     chase and the day-5 filing have not run since. (resilience_ping now calls it.)
--   * the ladder wrote its chase straight into notifications, opened org_tasks for a seat that no longer
--     exists ('followup'), and paged the founder through fn_notify_founder for the day-5 call.
--   * a CEO approval (ceo_approval, or refund_case -> ceo_authorized) was checked for identity and for
--     naming the refund. Nothing checked the PROCESS: no complaint window, no chase, no final call,
--     no exclusions, no amount. fn_refund_nonresponse_needs_silence read supplier_response_watch,
--     which nothing writes (0 rows).
--   * fn_refund_decide is reachable (service_role) and called only by scripts/rehearsal; it no longer
--     named the founder register (that went on 9 Sep) but approved on any non-'policy:' actor. It now
--     records only a CEO approval that already passed the checklist.
--     fn_refund_founder_decision_only is bound to no trigger and called by nothing: dropped.
--
-- THE THREE NESTED LOOPS
--   support ⇄ supplier   fn_customer_support_delivery_watch: deliver, watch every channel, return
--                        PROOF OF RESPONSE or NO-RESPONSE CONFIRMATION (with delivery evidence).
--   sales ⇄ support      fn_sales_engineer_ladder_step asks; fn_sales_engineer_attaches_delivery_result
--                        files the answer on the case (refund_ladder_evidence), which is what the CEO reads.
--   CEO ⇄ accountant/sales  fn_ceo_refund_review: every check passes -> approve; a check that cannot be
--                        fixed -> decline; otherwise reject with one remediation handoff per owning seat,
--                        re-review when the last one closes, escalate after three cycles or a missed deadline.
--

insert into public.founder_instruction (said_at, instruction, subject, status, evidence)
select '2026-09-14T00:00:00Z', x.i, x.s, 'done', 'scripts/sql/payments_are_the_accountant_and_the_seats_close_every_refund_together.sql'
  from (values
    ('ceo approval on refund was made so that the CEO make sure that the process was fully done correctly. he is my eyes in the company basically. so the wiring need to be 100% correct', 'the CEO verifies the refund process'),
    ('the CEO is also able to communicate with accountant and sales agent to mention why he rejected. and those would act accordingly and once they are done, the CEO checks again if all good to approve.', 'the CEO rejection loop'),
    ('the sales engineer is connected properly to the customer support agent to deliver the messages and communicate with the supplier to confirm he is not responding? and then he gets back with either a proof or no response confirmation. thats another loop within that bigger loop.', 'the delivery loop inside the refund loop'),
    ('when the post-execution re-verification finds a mismatch the CEO pauses refunds and supplier charges, opens an incident, fixes by type, re-runs the checklist, resumes only when green, and sends the founder a short WhatsApp summary.', 'the refund mismatch playbook')) x(i, s)
 where not exists (select 1 from public.founder_instruction f where f.instruction = x.i);

-- ── 1. THE RECORDS ───────────────────────────────────────────────────────────────────────────────
create table if not exists public.refund_ladder_evidence (
  id                 bigserial primary key,
  transaction_id     uuid        not null,
  refund_id          bigint,
  step               text        not null check (step in ('chase', 'final_call', 'customer_notice', 'customer_proof', 'unknown')),
  result             text        not null check (result in ('proof_of_response', 'no_response_confirmation')),
  delivered          boolean     not null,
  evidence           jsonb       not null default '{}'::jsonb,
  request_handoff_id bigint,
  result_handoff_id  bigint,
  attached_at        timestamptz not null default now()
);
comment on table public.refund_ladder_evidence is
  'What customer_support found at each outreach step of a refund, filed on the case by the sales engineer: proof the supplier responded, or confirmation that nothing came back (with the delivery evidence). The CEO checklist reads this and nothing else for the chase, the final call and the supplier''s silence.';
create index if not exists refund_ladder_evidence_tx_idx on public.refund_ladder_evidence (transaction_id, step, id desc);

create table if not exists public.refund_ceo_check (
  id             bigserial primary key,
  transaction_id uuid        not null,
  refund_id      bigint,
  phase          text        not null check (phase in ('approve', 'verify')),
  item           text        not null,
  passed         boolean     not null,
  reason         text,
  evidence       jsonb       not null default '{}'::jsonb,
  checked_at     timestamptz not null default now()
);
comment on table public.refund_ceo_check is
  'Every check the CEO ran on a refund, pass or fail, with the evidence it read. phase approve runs before any money moves and blocks approval on a single failure; phase verify runs after it moved.';
create index if not exists refund_ceo_check_tx_idx on public.refund_ceo_check (transaction_id, phase, checked_at desc);

create table if not exists public.refund_ceo_review (
  id             bigserial primary key,
  refund_id      bigint      not null,
  transaction_id uuid,
  cycle          int         not null,
  outcome        text        not null check (outcome in ('approved', 'rejected', 'declined', 'escalated')),
  failed         jsonb       not null default '[]'::jsonb,
  tasks          jsonb       not null default '[]'::jsonb,
  decision_id    bigint,
  trigger        text,
  sealed         boolean     not null default false,
  rechecked_at   timestamptz,
  created_at     timestamptz not null default now(),
  constraint refund_ceo_review_one_per_cycle unique (refund_id, cycle)
);
comment on table public.refund_ceo_review is
  'The CEO''s review loop on one refund: each cycle''s outcome, the failed checks with reason and remedy, and the remediation handoffs it sent. The loop counter is cycle; after three the loop escalates to the founder''s summary.';

create table if not exists public.refund_incident (
  id             bigserial primary key,
  transaction_id uuid        not null,
  refund_id      bigint,
  kinds          text[]      not null default '{}',
  approved_aed   numeric(12,2),
  actual_aed     numeric(12,2),
  difference_aed numeric(12,2),
  status         text        not null default 'open' check (status in ('open', 'paused', 'fixed')),
  sealed         boolean     not null default false,
  fixes          jsonb       not null default '[]'::jsonb,
  evidence       jsonb       not null default '{}'::jsonb,
  opened_at      timestamptz not null default now(),
  closed_at      timestamptz
);
comment on table public.refund_incident is
  'A post-payment mismatch the CEO found: approved vs actual vs difference, the kinds, the fixes applied, and whether refunds and supplier charges are still paused because of it.';

do $rls$
declare t text;
begin
  foreach t in array array['refund_ladder_evidence', 'refund_ceo_check', 'refund_ceo_review', 'refund_incident'] loop
    execute format('alter table public.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = t and policyname = t || '_service_role_only') then
      execute format('create policy %I on public.%I as permissive for all to public using (false) with check (false)', t || '_service_role_only', t);
    end if;
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $rls$;

-- ── 2. THE FOUNDER HEARS ONE THING FROM THE REFUND FLOW ─────────────────────────────────────────
insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role) values
  ('refund_ceo_summary', true,
   'The CEO''s short summary when a refund or supplier charge did not match what was approved, or a refund approval loop is stuck. The only founder notification in the refund flow (founder, 14 Sep 2026). Delivered by customer_support.',
   'ceo')
on conflict (kind) do update set allowed_to_email = excluded.allowed_to_email, reason = excluded.reason, owner_role = excluded.owner_role, updated_at = now();
update public.founder_mail_policy
   set allowed_to_email = false, owner_role = 'ceo', updated_at = now(),
       reason = 'Retired 14 Sep 2026: the day-5 final call is made by the sales engineer through customer_support and the CEO decides on its result. The only founder notification in the refund flow is refund_ceo_summary.'
 where kind = 'refund_final_call';

create or replace function public.fn_ceo_founder_summary(p_event text, p_detail text, p_dedupe text)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  return public.fn_seat_handoff('ceo', 'customer_support', 'delivery.request', 'founder', p_dedupe,
    jsonb_build_object('recipient_role', 'founder', 'kind', 'refund_ceo_summary', 'level', 'high',
                       'event', left(p_event, 200), 'detail', left(p_detail, 1500), 'dedupe_key', p_dedupe));
end $fn$;
revoke execute on function public.fn_ceo_founder_summary(text, text, text) from public, anon, authenticated;

-- ── 3. THE REFUND STATE READS THE FINAL CALL WHERE IT NOW HAPPENS ───────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_refund_state(p_transaction uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t record; v_window int; v_chase int; v_notify_days int; v_min int; v_max int;
        v_responded boolean; v_chase_at timestamptz; v_final_at timestamptz; v_notify_at timestamptz;
        v_chased_at timestamptz; v_final_sent_at timestamptz; v_state text;
begin
  select * into t from transactions where id = p_transaction;
  if not found then return jsonb_build_object('error','transaction_not_found'); end if;

  -- THE LADDER (founder, 6 Sep 2026): the clock starts when the customer PAYS (revealed_at), never at
  -- a nudge or a notice. Day 3 without a supplier response: the owning employee chases. Day 5: the
  -- founder is notified for the final call and the refund becomes approvable. All from pricing_config.
  select refund_window_working_days, chase_after_working_days,
         bank_settlement_working_days_min, bank_settlement_working_days_max
    into v_window, v_chase, v_min, v_max from pricing_config order by id limit 1;
  v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3);
  v_notify_days := coalesce((select value::text::int from decision_policy where key='refund_notify_after_working_days'),1);

  v_responded := t.supplier_ack_at is not null
    or exists (select 1 from messages m
               where m.inquiry_id = t.inquiry_id and m.supplier_id = t.supplier_id
                 and m.sender = 'supplier' and coalesce(m.blocked,false) = false
                 and m.created_at > t.revealed_at);

  v_chase_at  := case when t.revealed_at is null then null else public.fn_add_working_days(t.revealed_at, v_chase) end;
  v_final_at  := case when t.revealed_at is null then null
                      else coalesce(t.refund_deadline, public.fn_add_working_days(t.revealed_at, v_window)) end;
  v_notify_at := case when t.revealed_at is null then null else public.fn_add_working_days(t.revealed_at, v_notify_days) end;

  select min(n.created_at) into v_chased_at from notifications n
   where n.type = 'supplier_no_response_chase' and n.channel = 'email'
     and n.inquiry_id = t.inquiry_id and n.lead_id = t.supplier_id
     and t.revealed_at is not null and n.created_at > t.revealed_at;
  -- The day-5 final call is the sales engineer's notice delivered by support (type refund_final_notice).
  -- The founder_alerts marker the ladder wrote before 14 Sep is still honoured for cases already on it.
  select least((select min(n.created_at) from notifications n
                 where n.type = 'refund_final_notice' and n.inquiry_id = t.inquiry_id and n.lead_id = t.supplier_id
                   and t.revealed_at is not null and n.created_at > t.revealed_at),
               (select min(f.created_at) from founder_alerts f where f.dedupe_key = 'refund_final_call:' || t.id::text))
    into v_final_sent_at;

  v_state := case
    when t.revealed_at is null                                                          then 'not_revealed'
    when v_responded                                                                    then 'supplier_responded'
    when coalesce(t.refund_status,'') in ('approved','refunded','processing','succeeded') then 'refunded'
    when coalesce(t.refund_status,'') = 'rejected'                                      then 'refund_rejected'
    when now() < v_chase_at                                                             then 'waiting'
    when now() < v_final_at then case when v_chased_at is null then 'chase_due' else 'chased' end
    else case when v_final_sent_at is null then 'final_call_due' else 'final_call_sent' end end;

  return jsonb_build_object(
    'transaction_id', t.id,
    'state', v_state,
    'revealed_at', t.revealed_at,
    'supplier_responded', v_responded,
    'refund_window_working_days', v_window,
    'chase_after_working_days', v_chase,
    'chase_due_at', v_chase_at,
    'chased_at', v_chased_at,
    'founder_call_due_at', v_final_at,
    'final_call_sent_at', v_final_sent_at,
    'refund_deadline', t.refund_deadline,
    'notify_available_at', v_notify_at,
    'can_notify', (t.revealed_at is not null and not v_responded and t.customer_notified_at is null
                   and now() >= v_notify_at and v_state not in ('refunded','refund_rejected')),
    'notified_at', t.customer_notified_at,
    'auto_nudged_at', t.nudged_24_at,
    'refund_approvable', v_state in ('final_call_due','final_call_sent'),
    'refund_status', t.refund_status,
    'working_days_since_reveal', case when t.revealed_at is null then 0
                                      else public.fn_working_days_between(t.revealed_at, now()) end,
    'working_days_since_notice', case when t.customer_notified_at is null then 0
                                      else public.fn_working_days_between(t.customer_notified_at, now()) end,
    'bank_settlement_working_days', coalesce(v_min,7)::text || '-' || coalesce(v_max,14)::text
  );
end $function$;

-- ── 4. THE SALES ENGINEER'S LADDER STEPS, DELIVERED BY SUPPORT ───────────────────────────────────
create or replace function public.fn_sales_engineer_ladder_step(
  p_transaction_id uuid, p_step text, p_refund_id bigint default null, p_remediation_id bigint default null)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  t public.transactions; sup record; cust record; st jsonb; v_window int; v_chase int;
  v_final timestamptz; v_watch timestamptz; v_amt numeric; v_key text; v_days int; v_when text; v_extra jsonb;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found then raise exception 'no transaction %', p_transaction_id; end if;
  select id, company_name, coalesce(claimed_by, email) as email into sup from public.leads where id = t.supplier_id;
  select id, email, full_name into cust from public.customers where id = t.customer_id;
  select refund_window_working_days, chase_after_working_days into v_window, v_chase from public.pricing_config order by id limit 1;
  v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3);
  st := public.fn_refund_state(t.id);
  v_final := (st->>'founder_call_due_at')::timestamptz;
  v_amt := round(coalesce(t.total_charged, t.reveal_fee, 0), 2);
  v_key := p_step || ':' || t.id || coalesce(':r' || p_remediation_id, '');
  v_days := coalesce((select (d.value #>> '{}')::int from public.decision_policy d where d.key = 'refund_final_call_watch_working_days'), 1);
  v_when := to_char(t.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY');
  v_extra := jsonb_build_object('step', p_step, 'transaction_id', t.id, 'refund_id', p_refund_id, 'remediation_id', p_remediation_id);

  if p_step = 'chase' then
    v_watch := case when p_remediation_id is not null then public.fn_add_working_days(now(), 1)
                    else coalesce(v_final, public.fn_add_working_days(now(), greatest(v_window - v_chase, 1))) end;
    return public.fn_sales_engineer_writes('supplier_no_response_chase', 'supplier', sup.email, t.supplier_id, null, t.inquiry_id, t.quote_id,
      'Action needed: a customer is waiting for your response — QuotesDone reveal #' || left(t.id::text, 8),
      'Hello ' || coalesce(sup.company_name, '') || E',\n\n'
        || 'A customer paid to reveal your contact details on QuotesDone on ' || v_when || ' and has not heard from you. ' || v_chase
        || ' working days have passed. The customer is copied on this email so you can reply to all and pick it up here.' || E'\n\n'
        || 'Under the Supplier Agreement you must respond within ' || v_window || ' working days of the reveal, that is by '
        || coalesce(to_char(v_final at time zone 'Asia/Dubai', 'DD Mon YYYY'), 'the deadline')
        || '. If there is no response by then, our chief executive decides the case and the customer is refunded everything they paid (AED ' || v_amt
        || '). Under the supplier terms that amount is then recovered from your account with an administrative fee of AED 250 and interest at 9% a year until settled, and matching is paused until it is paid.' || E'\n\n'
        || 'If you have already been in touch with this customer, reply here and we will close this off.',
      'مطلوب إجراء: عميل ينتظر ردّك — QuotesDone',
      'دفع عميل للكشف عن بيانات التواصل معك في ' || v_when || ' ولم يتلقَّ ردًّا منك بعد مرور ' || v_chase || ' أيام عمل، والعميل في نسخة هذه الرسالة. '
        || 'بموجب اتفاقية المورّد يجب الرد خلال ' || v_window || ' أيام عمل من الكشف، وإلا يُردّ للعميل كامل ما دفعه (' || v_amt
        || ' درهم) ويُسترد من حسابك مع رسوم إدارية 250 درهمًا وفائدة 9% سنويًا حتى السداد. إن كنت قد تواصلت مع العميل فردّ على هذه الرسالة.',
      array_remove(array[cust.email], null), v_key, v_watch, v_extra);

  elsif p_step = 'final_call' then
    v_watch := public.fn_add_working_days(now(), v_days);
    return public.fn_sales_engineer_writes('refund_final_notice', 'supplier', sup.email, t.supplier_id, null, t.inquiry_id, t.quote_id,
      'Final call: a customer is still waiting — QuotesDone reveal #' || left(t.id::text, 8),
      'Hello ' || coalesce(sup.company_name, '') || E',\n\n'
        || 'This is our final call about the customer who paid to reveal your contact details on ' || v_when
        || '. The ' || v_window || ' working days the Supplier Agreement allows have passed with no response from you, to the customer or to our reminder.' || E'\n\n'
        || 'If we do not hear from you by ' || to_char(v_watch at time zone 'Asia/Dubai', 'DD Mon YYYY')
        || ', the customer is refunded everything they paid (AED ' || v_amt || ') and that amount is recovered from your account with an administrative fee of AED 250 and interest at 9% a year. '
        || 'Reply to this email, message the customer in your portal, or answer us on WhatsApp — any of them stops this.',
      'النداء الأخير: عميل ما زال ينتظر — QuotesDone',
      'هذا نداؤنا الأخير بخصوص العميل الذي كشف عن بيانات التواصل معك في ' || v_when || '. انقضت أيام العمل المسموح بها دون ردّ منك. '
        || 'إن لم نسمع منك حتى ' || to_char(v_watch at time zone 'Asia/Dubai', 'DD Mon YYYY') || ' يُردّ للعميل كامل ما دفعه (' || v_amt
        || ' درهم) ويُسترد من حسابك مع رسوم إدارية 250 درهمًا وفائدة 9% سنويًا. أي ردّ منك عبر البريد أو البوابة أو واتساب يوقف ذلك.',
      array_remove(array[cust.email], null), v_key, v_watch, v_extra);

  elsif p_step = 'customer_proof' then
    return public.fn_sales_engineer_writes('refund_proof_request', 'customer', cust.email, null, t.customer_id, t.inquiry_id, t.quote_id,
      'One thing we need for your refund',
      'Hello ' || coalesce(nullif(btrim(cust.full_name), ''), 'there') || E',\n\n'
        || 'To decide your refund our chief executive needs the proof that you contacted the supplier within 7 days of the reveal. '
        || 'Please forward the email you sent the supplier to supplier@mail.quotesdone.com, or reply to that email with supplier@mail.quotesdone.com in copy. '
        || 'If you sent your notice through the portal''s "Notify supplier" button, there is nothing to do.',
      'ما نحتاجه لإتمام استردادك',
      'ليقرّر رئيسنا التنفيذي في استردادك نحتاج ما يثبت أنك تواصلت مع المورّد خلال 7 أيام من الكشف. يُرجى إعادة توجيه رسالتك إلى المورّد إلى supplier@mail.quotesdone.com أو الرد عليها مع إضافة هذا العنوان في النسخة.',
      '{}', v_key, null, v_extra);
  end if;
  raise exception 'no such ladder step %', p_step;
end $fn$;
revoke execute on function public.fn_sales_engineer_ladder_step(uuid, text, bigint, bigint) from public, anon, authenticated;

-- The sales engineer files support's answer on the case. A proof of response is recorded where every
-- reader of silence looks (supplier_response_watch) and stops the non-response path.
create or replace function public.fn_sales_engineer_attaches_delivery_result(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare d jsonb; v_tx uuid; v_ev bigint; v_ref bigint; v_delivered boolean; v_rev jsonb; v_rem bigint;
begin
  select detail into d from public.agent_actions where id = p_id;
  v_tx := (d->>'transaction_id')::uuid;
  if v_tx is null then return jsonb_build_object('attached', false, 'reason', 'this delivery was not about a refund'); end if;
  v_delivered := case when d->>'result' = 'proof_of_response' then true
                      else coalesce((d->'evidence'->>'delivered')::boolean, false) end;
  insert into public.refund_ladder_evidence (transaction_id, refund_id, step, result, delivered, evidence, request_handoff_id, result_handoff_id)
  values (v_tx, (d->>'refund_id')::bigint,
          case when d->>'step' in ('chase', 'final_call', 'customer_notice', 'customer_proof') then d->>'step' else 'unknown' end,
          d->>'result', v_delivered, coalesce(d->'evidence', '{}'::jsonb), (d->>'request_id')::bigint, p_id)
  returning id into v_ev;

  if d->>'result' = 'proof_of_response' then
    insert into public.supplier_response_watch (transaction_id, lead_id, first_response_at, response_channel, response_ref)
    select v_tx, t.supplier_id, coalesce((d->'evidence'->'reply'->>'at')::timestamptz, now()),
           d->'evidence'->'reply'->>'channel', d->'evidence'->'reply'->>'ref'
      from public.transactions t where t.id = v_tx
    on conflict (transaction_id) do update
      set first_response_at = coalesce(public.supplier_response_watch.first_response_at, excluded.first_response_at),
          response_channel  = coalesce(public.supplier_response_watch.response_channel, excluded.response_channel),
          response_ref      = coalesce(public.supplier_response_watch.response_ref, excluded.response_ref);
  end if;

  v_rem := (d->>'remediation_id')::bigint;
  if v_rem is not null then
    perform public.fn_seat_handoff_complete(v_rem, jsonb_build_object('ladder_evidence_id', v_ev, 'result', d->>'result', 'delivered', v_delivered));
  elsif d->>'step' = 'final_call' then
    select id into v_ref from public.refunds where transaction_id = v_tx and status = 'requested' order by id desc limit 1;
    if v_ref is not null then v_rev := public.fn_ceo_refund_review(v_ref, 'final_call_result'); end if;
  end if;
  return jsonb_build_object('attached', true, 'ladder_evidence_id', v_ev, 'result', d->>'result', 'delivered', v_delivered, 'ceo_review', v_rev);
end $fn$;
revoke execute on function public.fn_sales_engineer_attaches_delivery_result(bigint) from public, anon, authenticated;

-- The sales engineer's side of a CEO rejection: run the inner loop again for the step that failed.
create or replace function public.fn_sales_engineer_remediates(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare d jsonb; v_tx uuid; v_req bigint; v_step text;
begin
  select detail into d from public.agent_actions where id = p_id;
  v_tx := (d->>'transaction_id')::uuid;
  v_step := case d->>'remedy_key' when 'final_call' then 'final_call' when 'chase' then 'chase' when 'customer_proof' then 'customer_proof' end;
  if v_step is null then
    return jsonb_build_object('waiting', 'no automatic remedy for ' || coalesce(d->>'remedy_key', '?'));
  end if;
  v_req := public.fn_sales_engineer_ladder_step(v_tx, v_step, (d->>'refund_id')::bigint, p_id);
  return jsonb_build_object('delivery_request', v_req,
    'waiting', case v_step when 'customer_proof' then 'the customer: the proof is requested and this closes when it arrives'
                           else 'the supplier: support is delivering the ' || replace(v_step, '_', ' ') || ' and watching every channel for a reply' end);
end $fn$;
revoke execute on function public.fn_sales_engineer_remediates(bigint) from public, anon, authenticated;

-- ── 5. THE CUSTOMER'S FORMAL NOTICE AND THE LADDER, THROUGH THE SAME TWO SEATS ──────────────────
create or replace function public.fn_notify_supplier(p_transaction uuid, p_actor text default 'customer')
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare t record; st jsonb; sup record; cust_email text; v_window int; v_final_at timestamptz; v_amt numeric; v_req bigint;
begin
  st := public.fn_refund_state(p_transaction);
  if st ? 'error' then return st; end if;
  if (st->>'can_notify') <> 'true' then
    return jsonb_build_object('ok', false, 'error', 'not_available', 'state', st->>'state', 'notify_available_at', st->>'notify_available_at');
  end if;
  select * into t from public.transactions where id = p_transaction;
  select company_name, coalesce(claimed_by, email) as email into sup from public.leads where id = t.supplier_id;
  select email into cust_email from public.customers where id = t.customer_id;
  v_window   := coalesce((st->>'refund_window_working_days')::int, 5);
  v_final_at := (st->>'founder_call_due_at')::timestamptz;
  v_amt      := round(coalesce(t.total_charged, t.reveal_fee, 0), 2);

  -- The customer's own formal notice, in the sales engineer's voice, delivered by support. It does
  -- NOT move the ladder: the window is fixed from payment (founder, 6 Sep 2026).
  v_req := public.fn_sales_engineer_writes('reveal_no_response_notice', 'supplier', sup.email, t.supplier_id, null, t.inquiry_id, t.quote_id,
    'Awaiting your response — QuotesDone reveal #' || left(t.id::text, 8),
    'Hello,' || E'\n\n'
      || 'A customer paid to reveal your contact details on QuotesDone on ' || to_char(t.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY')
      || ' and has not yet heard from you. The customer is copied on this email so you can simply reply to all and pick it up here.' || E'\n\n'
      || 'Under the Supplier Agreement you must respond within ' || v_window || ' working days of the reveal, that is by '
      || to_char(v_final_at at time zone 'Asia/Dubai', 'DD Mon YYYY') || '. If we have not seen a response by then, our chief executive decides the case and the customer is refunded everything they paid (AED '
      || v_amt || '). Under the supplier terms that amount is then recovered from your account, with an administrative fee of AED 250 and interest at 9% per annum until it is settled, and matching is paused until it is paid.' || E'\n\n'
      || 'If you have already been in touch with this customer, reply here and we will close this off.',
    'بانتظار ردّك — QuotesDone',
    'دفع عميل للكشف عن بيانات التواصل معك ولم يتلقَّ ردًّا بعد، والعميل في نسخة هذه الرسالة. يجب الرد خلال ' || v_window
      || ' أيام عمل من الكشف، وإلا يُردّ للعميل كامل ما دفعه (' || v_amt || ' درهم) ويُسترد من حسابك مع رسوم إدارية 250 درهمًا وفائدة 9% سنويًا.',
    array_remove(array[cust_email], null), 'customer_notice:' || t.id, null,
    jsonb_build_object('step', 'customer_notice', 'transaction_id', t.id));

  update public.transactions
     set customer_notified_at = now(), refund_deadline = coalesce(refund_deadline, v_final_at)
   where id = p_transaction;

  return jsonb_build_object('ok', true, 'notified_at', now(), 'recipients', jsonb_build_array(sup.email, cust_email),
                            'founder_call_due_at', v_final_at, 'delivery_request', v_req,
                            'state', public.fn_refund_state(p_transaction));
end $fn$;

create or replace function public.fn_refund_ladder_sweep()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  t record; st jsonb; v_window int; v_chase int; v_refund bigint;
  n_seen int := 0; n_chased int := 0; n_final int := 0; v_ids jsonb := '[]'::jsonb; v_watch jsonb; v_loop jsonb;
begin
  select refund_window_working_days, chase_after_working_days into v_window, v_chase from public.pricing_config order by id limit 1;
  v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3);

  for t in
    select x.* from public.transactions x
     where x.revealed_at is not null and coalesce(x.total_charged, x.reveal_fee, 0) > 0
       and coalesce(x.refund_status, '') not in ('approved', 'refunded', 'processing', 'succeeded', 'rejected', 'cancelled', 'failed')
       and x.revealed_at > now() - interval '120 days'
     order by x.revealed_at
  loop
    n_seen := n_seen + 1;
    st := public.fn_refund_state(t.id);
    continue when st ? 'error' or coalesce((st->>'supplier_responded')::boolean, false);
    continue when st->>'state' not in ('chase_due', 'final_call_due');

    if st->>'state' = 'chase_due' then
      perform public.fn_sales_engineer_ladder_step(t.id, 'chase', null, null);
      n_chased := n_chased + 1;
      v_ids := v_ids || jsonb_build_object('transaction_id', t.id, 'step', 'chase');
    else
      -- DAY 5: the refund is filed through the one door (fn_refund_request; the CEO decides, the guards
      -- on refunds refuse money moving any other way) and the sales engineer makes the final call.
      if not exists (select 1 from public.refunds r where r.transaction_id = t.id) then
        perform public.fn_refund_request(
          round(coalesce(t.total_charged, t.reveal_fee) * 100)::bigint, 'supplier_unresponsive', 'refund_ladder_sweep',
          t.inquiry_id, t.customer_id, t.supplier_id, t.quote_id, t.payment_ref, null,
          'Day ' || v_window || ' of the refund ladder: the supplier responded neither to the customer nor to the day-' || v_chase
            || ' chase. Filed by the ladder; the sales engineer makes the final call through support and the CEO decides on what comes back.',
          t.id);
      end if;
      select r.id into v_refund from public.refunds r where r.transaction_id = t.id order by r.id desc limit 1;
      perform public.fn_sales_engineer_ladder_step(t.id, 'final_call', v_refund, null);
      n_final := n_final + 1;
      v_ids := v_ids || jsonb_build_object('transaction_id', t.id, 'step', 'final_call', 'refund_id', v_refund);
    end if;
  end loop;

  v_watch := public.fn_customer_support_delivery_watch(null);
  v_loop  := public.fn_ceo_refund_loop_sweep();
  return jsonb_build_object('ok', true, 'seen', n_seen, 'chased', n_chased, 'final_calls', n_final,
                            'window_working_days', v_window, 'chase_after_working_days', v_chase,
                            'owner_agent', 'sales_engineer writes, customer_support delivers, ceo decides',
                            'cases', v_ids, 'support_watch', v_watch, 'ceo_loop', v_loop, 'ran_at', now());
end $fn$;

-- ── 6. THE CHECKLIST ─────────────────────────────────────────────────────────────────────────────
-- approve: before any money moves. One failure refuses the approval.
-- verify:  after it moved. One failure opens the mismatch playbook.
-- Each item: {item, passed, evidence, reason, remedy, owner, remedy_key, remediable, kind}.
create or replace function public.fn_ceo_refund_checklist(p_transaction_id uuid, p_phase text, p_record boolean default true)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  t public.transactions; r public.refunds; rs public.refunds; ap public.ceo_approval; du public.supplier_dues;
  e_chase public.refund_ladder_evidence; e_final public.refund_ladder_evidence;
  v_items jsonb := '[]'::jsonb; v_failed jsonb; v_ok boolean; v_cust text; v_total numeric; v_reason text; v_unresp boolean;
  v_complaint timestamptz; v_in_time boolean; v_cc boolean; v_attached boolean; v_proofs int; v_live boolean; v_proof_ev jsonb;
  v_prior boolean; v_hired boolean; v_rated boolean; v_offp boolean; v_excl text[] := '{}'; v_exp bigint;
  v_succ int; v_succ_fils bigint; v_extra int; v_actual numeric; v_approved numeric; v_loss numeric; v_charge jsonb; v_sent boolean;
  v_told boolean; v_sup_told boolean; v_kind text; v_rid bigint;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found then
    return jsonb_build_object('ok', false, 'phase', p_phase, 'transaction_id', p_transaction_id,
      'failed', jsonb_build_array(jsonb_build_object('item', 'transaction_exists', 'passed', false, 'reason', 'no such transaction', 'remediable', false)));
  end if;
  select * into r from public.refunds where transaction_id = t.id and status not in ('rejected', 'cancelled', 'failed')
     and lower(coalesce(requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe') order by id desc limit 1;
  select lower(email) into v_cust from public.customers where id = t.customer_id;
  v_total := coalesce(t.total_charged, t.reveal_fee);
  v_reason := coalesce(r.reason_code, t.refund_reason, 'supplier_unresponsive');
  v_unresp := v_reason = 'supplier_unresponsive';
  select * into e_chase from public.refund_ladder_evidence e where e.transaction_id = t.id and e.step = 'chase' order by e.id desc limit 1;
  select * into e_final from public.refund_ladder_evidence e where e.transaction_id = t.id and e.step = 'final_call' order by e.id desc limit 1;

  if p_phase = 'approve' then
    v_rid := r.id;
    -- 1. The complaint, within 7 days, with proof.
    v_complaint := least(t.customer_notified_at,
                         (select min(x.requested_at) from public.refunds x where x.transaction_id = t.id and lower(coalesce(x.requested_by, '')) = 'customer'));
    v_in_time := v_complaint is not null and v_complaint <= t.revealed_at + interval '7 days';
    v_cc := exists (select 1 from public.inbound_messages im
                     where v_cust is not null and lower(im.from_email) = v_cust and im.created_at > t.revealed_at
                       and (im.to_email ilike 'supplier@%' or im.raw::text ilike '%supplier@mail.quotesdone.com%'));
    v_attached := exists (select 1 from public.refund_ladder_evidence e where e.transaction_id = t.id and e.step = 'customer_proof');
    v_items := v_items || jsonb_build_object('item', 'complaint_within_7_days_with_proof',
      'passed', v_in_time and (v_cc or t.customer_notified_at is not null or v_attached),
      'evidence', jsonb_build_object('revealed_at', t.revealed_at, 'complaint_at', v_complaint,
        'customer_emailed_supplier_with_supplier_at_in_copy', v_cc, 'formal_notice_through_portal_at', t.customer_notified_at,
        'proof_attached_by_sales_engineer', v_attached),
      'reason', case when v_complaint is null then 'no complaint from the customer is recorded (no portal notice and no refund request of their own)'
                     when not v_in_time then 'the complaint came ' || round(extract(epoch from (v_complaint - t.revealed_at)) / 86400.0, 1) || ' days after the reveal, beyond the 7 days the terms allow'
                     else 'no proof: no email from the customer reached supplier@ in copy and no formal notice went through the portal' end,
      'remedy', 'the sales engineer asks the customer to forward their email to the supplier with supplier@mail.quotesdone.com in copy',
      'owner', 'sales_engineer', 'remedy_key', 'customer_proof', 'remediable', v_in_time, 'kind', 'process');

    -- 2 and 3. The day-3 chase and the day-5 final call, as support reported them.
    v_items := v_items || jsonb_build_object('item', 'day3_chase_happened',
      'passed', e_chase.id is not null and e_chase.delivered,
      'evidence', case when e_chase.id is null then '{}'::jsonb
                       else jsonb_build_object('ladder_evidence_id', e_chase.id, 'result', e_chase.result, 'delivered', e_chase.delivered, 'delivery', e_chase.evidence) end,
      'reason', case when e_chase.id is null then 'support has returned no result for a day-3 chase' else 'the day-3 chase was not delivered' end,
      'remedy', 'the sales engineer has support deliver the chase again and watch every channel for a reply',
      'owner', 'sales_engineer', 'remedy_key', 'chase', 'remediable', true, 'kind', 'process');
    v_items := v_items || jsonb_build_object('item', 'day5_final_call_happened',
      'passed', e_final.id is not null and e_final.delivered,
      'evidence', case when e_final.id is null then '{}'::jsonb
                       else jsonb_build_object('ladder_evidence_id', e_final.id, 'result', e_final.result, 'delivered', e_final.delivered, 'delivery', e_final.evidence) end,
      'reason', case when e_final.id is null then 'support has returned no result for the day-5 final call' else 'the day-5 final call was not delivered' end,
      'remedy', 'the sales engineer has support deliver the final call again and watch every channel for a reply',
      'owner', 'sales_engineer', 'remedy_key', 'final_call', 'remediable', true, 'kind', 'process');

    -- 4. The supplier did not respond to either party, on any channel.
    select count(*), (array_agg(e.evidence order by e.id desc))[1] into v_proofs, v_proof_ev
      from public.refund_ladder_evidence e where e.transaction_id = t.id and e.result = 'proof_of_response';
    v_live := coalesce((public.fn_refund_state(t.id)->>'supplier_responded')::boolean, false)
              or exists (select 1 from public.supplier_response_watch w where w.transaction_id = t.id and w.first_response_at is not null);
    v_items := v_items || jsonb_build_object('item', 'supplier_never_responded',
      'passed', v_proofs = 0 and not v_live
                and coalesce(e_chase.result, '') = 'no_response_confirmation' and coalesce(e_chase.delivered, false)
                and coalesce(e_final.result, '') = 'no_response_confirmation' and coalesce(e_final.delivered, false),
      'evidence', jsonb_build_object('proofs_of_response', v_proofs, 'latest_proof', v_proof_ev, 'responded_by_live_record', v_live,
                                     'chase_result', e_chase.result, 'final_call_result', e_final.result),
      'reason', case when v_proofs > 0 or v_live then 'the supplier responded' || coalesce(': ' || (v_proof_ev->'reply')::text, '')
                     else 'silence is not confirmed on both steps: a result is missing, or the delivery behind it failed' end,
      'remedy', 'the sales engineer has support make the final call again and return proof or a confirmed no-response',
      'owner', 'sales_engineer', 'remedy_key', 'final_call', 'remediable', v_proofs = 0 and not v_live, 'kind', 'process');

    -- 5. None of the exclusions in the signed terms applies.
    v_prior := exists (select 1 from public.transactions x where x.customer_id = t.customer_id and x.supplier_id = t.supplier_id
                         and x.id <> t.id and x.revealed_at < t.revealed_at);
    v_hired := exists (select 1 from public.inquiries i where i.id = t.inquiry_id and i.status in ('completed', 'closed') and i.hired_supplier_id = t.supplier_id);
    v_rated := exists (select 1 from public.reviews v where v.transaction_id = t.id);
    v_offp := coalesce(r.reason_note, '') ~* 'off.?platform'
              or exists (select 1 from public.supplier_response_watch w where w.transaction_id = t.id and coalesce(w.close_reason, '') ~* 'off.?platform');
    if not v_unresp then v_excl := v_excl || ('the reason is ' || v_reason || ', not supplier non-response (price dissatisfaction and a change of mind are not refundable)'); end if;
    if v_prior then v_excl := v_excl || 'the customer revealed this same supplier before'::text; end if;
    if v_hired then v_excl := v_excl || 'the customer completed the job with this supplier'::text; end if;
    if v_rated then v_excl := v_excl || 'the customer already rated this supplier'::text; end if;
    if v_offp then v_excl := v_excl || 'the customer engaged the supplier off the platform'::text; end if;
    v_items := v_items || jsonb_build_object('item', 'no_refund_exclusion_applies',
      'passed', cardinality(v_excl) = 0,
      'evidence', jsonb_build_object('reason_code', v_reason, 'same_supplier_revealed_before', v_prior, 'job_completed_with_supplier', v_hired,
                                     'supplier_rated', v_rated, 'off_platform_engagement_recorded', v_offp,
                                     'supplier_responded', 'checked by supplier_never_responded'),
      'reason', array_to_string(v_excl, '; '), 'remedy', 'none: an exclusion in the signed terms means the refund is declined',
      'owner', 'sales_engineer', 'remedy_key', 'decline', 'remediable', false, 'kind', 'process');

    -- 6. The amount is exactly what the customer paid.
    v_exp := round(coalesce(v_total, 0) * 100)::bigint;
    v_items := v_items || jsonb_build_object('item', 'amount_equals_total_charged',
      'passed', r.id is not null and r.amount_fils = v_exp and v_exp > 0,
      'evidence', jsonb_build_object('refund_id', r.id, 'refund_fils', r.amount_fils, 'total_charged_fils', v_exp,
                                     'total_charged_recorded', t.total_charged is not null, 'stripe_reference', t.payment_ref),
      'reason', case when r.id is null then 'there is no open refund request on this payment' else 'the refund amount is not what the customer paid' end,
      'remedy', 'the accountant sets the refund to the payment''s total_charged',
      'owner', 'accountant', 'remedy_key', 'amount', 'remediable', r.id is not null, 'kind', 'money');

  elsif p_phase = 'verify' then
    select count(*), coalesce(sum(x.amount_fils), 0) into v_succ, v_succ_fils
      from public.refunds x
     where x.status = 'succeeded' and (x.transaction_id = t.id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref));
    -- A top-up the playbook issued is not a duplicate: its Stripe id is on the incident fix.
    select count(*) into v_extra
      from public.refunds x
     where x.status = 'succeeded' and (x.transaction_id = t.id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref))
       and not exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'incident.fix'
                        and a.evidence->>'stripe_refund_id' = x.stripe_refund_id);
    -- The platform refund the CEO approved, whatever state it reached. An external row Stripe reported
    -- (a top-up, a dashboard refund) is never it.
    select * into rs from public.refunds x where x.transaction_id = t.id
       and lower(coalesce(x.requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe') order by x.id desc limit 1;
    v_rid := rs.id;
    select * into ap from public.ceo_approval a where a.decision_id = rs.refund_decision_id;
    v_actual := case when v_succ > 0 then round(v_succ_fils / 100.0, 2)
                     when t.refund_status in ('refunded', 'succeeded') then t.refund_amount_aed end;
    v_approved := coalesce(ap.amount_aed, v_total);
    v_loss := coalesce((select sum(l.debit) from public.gl_journal g join public.gl_journal_lines l on l.journal_id = g.id
                         where g.source = 'refund_over_loss' and g.source_ref like t.id::text || ':%' and l.account_code = '6900'), 0);

    v_items := v_items || jsonb_build_object('item', 'ceo_approved_this_refund',
      'passed', ap.decision_id is not null and ap.decision = 'approved' and ap.subject_id = v_rid::text and ap.superseded_by is null,
      'evidence', jsonb_build_object('decision_id', ap.decision_id, 'decision', ap.decision, 'subject_id', ap.subject_id, 'refund_id', v_rid),
      'reason', 'money moved without a CEO approval naming this refund', 'kind', 'moved_without_ceo_approval', 'remediable', false);

    v_items := v_items || jsonb_build_object('item', 'stripe_refund_succeeded',
      'passed', (v_succ > 0 and exists (select 1 from public.refunds x
                                         where (x.transaction_id = t.id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref))
                                           and x.status = 'succeeded' and x.stripe_refund_id is not null))
                or (v_succ = 0 and t.refund_stripe_id is not null and t.refund_status in ('refunded', 'succeeded')),
      'evidence', jsonb_build_object('refund_status', rs.status, 'stripe_refund_id', coalesce(rs.stripe_refund_id, t.refund_stripe_id), 'failure_reason', rs.failure_reason),
      'reason', 'Stripe has not settled the refund (' || coalesce(rs.status, t.refund_status, 'unknown') || ')', 'kind', 'stripe_failed_or_pending', 'remediable', true);

    v_kind := case when coalesce(v_actual, 0) = 0 then 'stripe_failed_or_pending'
                   when v_approved is distinct from v_total then 'approved_amount_is_not_total_charged'
                   when v_actual < v_approved then 'under_refund'
                   when v_actual > v_approved then 'over_refund' end;
    v_items := v_items || jsonb_build_object('item', 'money_moved_as_approved',
      'passed', v_actual is not null and v_approved = v_total
                and (v_actual = v_approved or (v_actual > v_approved and v_loss >= v_actual - v_approved)),
      'evidence', jsonb_build_object('approved_aed', v_approved, 'actual_aed', v_actual, 'total_charged_aed', v_total,
                                     'difference_aed', v_actual - v_approved, 'over_refund_loss_booked_aed', v_loss, 'settled_refunds', v_succ),
      'reason', 'approved AED ' || coalesce(v_approved::text, '?') || ', refunded AED ' || coalesce(v_actual::text, 'nothing') || ', total charged AED ' || coalesce(v_total::text, '?'),
      'kind', v_kind, 'remediable', true);

    v_items := v_items || jsonb_build_object('item', 'no_duplicate_refund',
      'passed', v_extra <= 1 or v_loss >= coalesce(v_actual - v_approved, 0),
      'evidence', jsonb_build_object('settled_refunds_not_issued_by_a_fix', v_extra),
      'reason', v_extra || ' refunds settled on one payment', 'kind', 'duplicate_refund', 'remediable', true);

    -- What follows the money (the supplier's charge, the two messages) is checked only once money
    -- actually moved; a refund Stripe has not settled is the retry's business, not a missed message.
    if coalesce(v_actual, 0) > 0 and v_unresp then
      select * into du from public.supplier_dues where transaction_id = t.id and coalesce(status, '') <> 'cancelled' order by id limit 1;
      v_charge := public.fn_accountant_nonresponse_charge(t.id, null);
      v_sent := du.id is not null and exists (
        select 1 from public.agent_actions a join public.notifications n on n.id = (a.evidence->>'notification_id')::bigint
         where a.kind = 'handoff' and a.agent = 'customer_support' and a.target_id = 'delivery.request:nonresponse_charge:' || du.id
           and (n.status = 'sent' or n.sent_at is not null));
      v_items := v_items || jsonb_build_object('item', 'supplier_charge_raised_correctly',
        'passed', du.id is not null and coalesce((v_charge->>'ok')::boolean, false)
                  and du.amount_due = (v_charge->>'refunded_aed')::numeric and du.admin_fee = (v_charge->>'admin_fee_aed')::numeric
                  and du.due_date = (v_charge->>'due_date')::date,
        'evidence', jsonb_build_object('due_id', du.id, 'charged', jsonb_build_object('amount_due', du.amount_due, 'admin_fee', du.admin_fee, 'due_date', du.due_date),
                                       'expected', v_charge, 'charge_message_sent', v_sent),
        'reason', case when du.id is null then 'no supplier charge was raised' else 'the supplier charge does not match the refund record' end,
        'kind', case when du.id is null then 'charge_missing' when v_sent then 'wrong_charge_sent' else 'wrong_charge_unsent' end, 'remediable', true);
    end if;

    if coalesce(v_actual, 0) > 0 then
    v_told := exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'sales_engineer'
                        and a.target_id = 'refund.paid:' || t.id and a.status = 'done')
              and exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'customer_support'
                            and a.target_id = 'delivery.request:refund_issued:' || t.id and a.status = 'done'
                            and coalesce((a.evidence->>'delivered')::boolean, false));
    v_items := v_items || jsonb_build_object('item', 'customer_told',
      'passed', v_told, 'evidence', jsonb_build_object('handoff', 'refund.paid:' || t.id, 'delivery', 'delivery.request:refund_issued:' || t.id),
      'reason', 'the customer''s refund message was not handed off and delivered', 'kind', 'missed_handoff', 'remediable', true);
    if v_unresp and du.id is not null then
      v_sup_told := exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'sales_engineer'
                              and a.target_id in ('nonresponse.charge_raised:' || du.id, 'charge.corrected:' || du.id) and a.status = 'done')
                    and exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'customer_support'
                                  and a.target_id in ('delivery.request:nonresponse_charge:' || du.id, 'delivery.request:charge_corrected:' || du.id)
                                  and a.status = 'done' and coalesce((a.evidence->>'delivered')::boolean, false));
      v_items := v_items || jsonb_build_object('item', 'supplier_told',
        'passed', v_sup_told, 'evidence', jsonb_build_object('handoff', 'nonresponse.charge_raised:' || du.id),
        'reason', 'the supplier''s charge message was not handed off and delivered', 'kind', 'missed_handoff', 'remediable', true);
    end if;
    end if;
  else
    raise exception 'phase is approve or verify, not %', p_phase;
  end if;

  select coalesce(jsonb_agg(i), '[]'::jsonb) into v_failed from jsonb_array_elements(v_items) i where not coalesce((i->>'passed')::boolean, false);
  v_ok := jsonb_array_length(v_failed) = 0;
  if p_record then
    insert into public.refund_ceo_check (transaction_id, refund_id, phase, item, passed, reason, evidence)
    select t.id, v_rid, p_phase, i->>'item', coalesce((i->>'passed')::boolean, false),
           case when coalesce((i->>'passed')::boolean, false) then null else i->>'reason' end, coalesce(i->'evidence', '{}'::jsonb)
      from jsonb_array_elements(v_items) i;
  end if;
  return jsonb_build_object('ok', v_ok, 'phase', p_phase, 'transaction_id', t.id, 'refund_id', v_rid, 'items', v_items, 'failed', v_failed);
end $fn$;
revoke execute on function public.fn_ceo_refund_checklist(uuid, text, boolean) from public, anon, authenticated;

-- ── 7. THE GATES: no CEO approval of a refund unless the whole process checks out ───────────────
create or replace function public.fn_ceo_refund_approval_checks_the_process()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_tx uuid; v jsonb;
begin
  if TG_TABLE_NAME = 'ceo_approval' then
    if NEW.subject_kind <> 'refund' or NEW.decision <> 'approved' then return NEW; end if;
    if coalesce(NEW.subject_id, '') !~ '^[0-9]+$' then
      raise exception 'a refund approval names the refund by its id; % is not one', coalesce(NEW.subject_id, '(nothing)') using errcode = '23514';
    end if;
    select transaction_id into v_tx from public.refunds where id = NEW.subject_id::bigint;
  else
    if NEW.state <> 'ceo_authorized' or (TG_OP = 'UPDATE' and OLD.state = 'ceo_authorized') then return NEW; end if;
    v_tx := NEW.transaction_id;
  end if;
  if v_tx is null then
    raise exception 'the CEO may not approve a refund that names no payment' using errcode = '23514';
  end if;
  v := public.fn_ceo_refund_checklist(v_tx, 'approve', false);
  if not (v->>'ok')::boolean then
    raise exception 'the CEO may not approve this refund: % check(s) failed — %', jsonb_array_length(v->'failed'),
      (select string_agg((i->>'item') || ': ' || coalesce(i->>'reason', ''), ' | ') from jsonb_array_elements(v->'failed') i)
      using errcode = '23514',
            hint = 'Founder, 14 Sep 2026: the CEO''s approval exists to make sure the process was done correctly. fn_ceo_refund_review runs the checklist, records the evidence and sends each failure to the seat that owns it.';
  end if;
  return NEW;
end $fn$;
revoke execute on function public.fn_ceo_refund_approval_checks_the_process() from public, anon, authenticated;
drop trigger if exists a05_ceo_refund_approval_checks_the_process on public.ceo_approval;
create trigger a05_ceo_refund_approval_checks_the_process before insert on public.ceo_approval
  for each row execute function public.fn_ceo_refund_approval_checks_the_process();
drop trigger if exists z20_refund_case_approval_checks_the_process on public.refund_case;
create trigger z20_refund_case_approval_checks_the_process before insert or update on public.refund_case
  for each row execute function public.fn_ceo_refund_approval_checks_the_process();

-- fn_refund_decide: the one routine that moves refunds.status to approved/rejected. It now records
-- only a CEO approval that already passed the checklist; it cannot make one.
create or replace function public.fn_refund_decide(p_refund_id bigint, p_approve boolean, p_decided_by text, p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.refunds; v_app public.ceo_approval; v_new text;
begin
  select * into r from public.refunds where id = p_refund_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.status <> 'requested' then return jsonb_build_object('ok', false, 'error', 'not_decidable', 'status', r.status); end if;
  if coalesce(btrim(p_decided_by), '') = '' then return jsonb_build_object('ok', false, 'error', 'decider_required'); end if;
  if lower(btrim(p_decided_by)) like 'policy:%' then
    return jsonb_build_object('ok', false, 'error', 'automatic_decider_refused',
      'hint', 'A refund is decided by an actor, not by a rule. Approvals are the CEO''s.');
  end if;

  if p_approve then
    select * into v_app from public.ceo_approval a
     where a.subject_kind = 'refund' and a.subject_id = p_refund_id::text and a.decision = 'approved' and a.superseded_by is null
     order by a.decision_id desc limit 1;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'no_ceo_approval',
        'hint', 'A refund is approved only by a CEO approval that passed the process checklist (fn_ceo_refund_review, or ceo_agent decide). This routine records that decision; it cannot make one.');
    end if;
    update public.refunds set status = 'approved', decided_by = v_app.decided_by, decided_at = now(),
           decision_note = coalesce(p_note, v_app.rationale), refund_decision_id = v_app.decision_id
     where id = p_refund_id;
    v_new := 'approved';
  else
    update public.refunds set status = 'rejected', decided_by = p_decided_by, decided_at = now(), decision_note = p_note where id = p_refund_id;
    v_new := 'rejected';
  end if;
  if r.transaction_id is not null then
    update public.transactions set refund_status = v_new, refund_resolved_at = now(), refund_note = coalesce(p_note, refund_note)
     where id = r.transaction_id;
  end if;
  return jsonb_build_object('ok', true, 'refund_id', p_refund_id, 'status', v_new, 'decided_by', coalesce(v_app.decided_by, p_decided_by));
end $fn$;
drop function if exists public.fn_refund_founder_decision_only();

-- ── 8. THE REVIEW LOOP ───────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_refund_review(p_refund_id bigint, p_trigger text default 'manual')
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  r public.refunds; v jsonb; v_cycle int; v_nonrem jsonb; v_rev bigint; v_dec bigint; x record; v_task bigint;
  v_tasks jsonb := '[]'::jsonb; v_rat text; v_deadline timestamptz; v_chase int; v_adv jsonb;
begin
  select * into r from public.refunds where id = p_refund_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such refund'); end if;
  if r.status <> 'requested' then return jsonb_build_object('ok', false, 'reason', 'refund is ' || r.status || '; the CEO reviews only an open request'); end if;
  if r.refund_decision_id is not null then return jsonb_build_object('ok', true, 'outcome', 'already_approved', 'decision_id', r.refund_decision_id); end if;
  if exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'refund.remediate'
               and a.detail->>'refund_id' = r.id::text and a.status = 'pending') then
    return jsonb_build_object('ok', false, 'outcome', 'waiting_on_remediation');
  end if;

  select coalesce(max(cycle), 0) + 1 into v_cycle from public.refund_ceo_review where refund_id = r.id;
  v := public.fn_ceo_refund_checklist(r.transaction_id, 'approve', true);

  if (v->>'ok')::boolean then
    v_rat := 'Cycle ' || v_cycle || ': every pre-approval check passed ('
          || (select string_agg(i->>'item', ', ') from jsonb_array_elements(v->'items') i) || '). Evidence: refund_ceo_check for this transaction.';
    insert into public.ceo_approval (subject_kind, subject_id, decision, decided_by, amount_aed, rationale)
    values ('refund', r.id::text, 'approved', 'ceo', round(r.amount_fils / 100.0, 2), v_rat) returning decision_id into v_dec;
    update public.refunds set refund_decision_id = v_dec, decided_by = 'ceo', decided_at = now(), decision_note = v_rat where id = r.id;
    insert into public.refund_ceo_review (refund_id, transaction_id, cycle, outcome, decision_id, trigger, sealed)
    values (r.id, r.transaction_id, v_cycle, 'approved', v_dec, p_trigger, true);
    return jsonb_build_object('ok', true, 'outcome', 'approved', 'cycle', v_cycle, 'decision_id', v_dec);
  end if;

  select coalesce(jsonb_agg(i), '[]'::jsonb) into v_nonrem from jsonb_array_elements(v->'failed') i where not coalesce((i->>'remediable')::boolean, false);
  if jsonb_array_length(v_nonrem) > 0 then
    v_rat := 'Declined: ' || (select string_agg((i->>'item') || ' — ' || coalesce(i->>'reason', ''), '; ') from jsonb_array_elements(v_nonrem) i);
    insert into public.ceo_approval (subject_kind, subject_id, decision, decided_by, amount_aed, rationale)
    values ('refund', r.id::text, 'refused', 'ceo', round(r.amount_fils / 100.0, 2), left(v_rat, 2000)) returning decision_id into v_dec;
    insert into public.refund_ceo_review (refund_id, transaction_id, cycle, outcome, failed, decision_id, trigger, sealed)
    values (r.id, r.transaction_id, v_cycle, 'declined', v->'failed', v_dec, p_trigger, true);
    perform public.fn_refund_decide(r.id, false, 'ceo', left(v_rat, 900));
    return jsonb_build_object('ok', true, 'outcome', 'declined', 'cycle', v_cycle, 'reason', v_rat);
  end if;

  if v_cycle > 3 then
    insert into public.refund_ceo_review (refund_id, transaction_id, cycle, outcome, failed, trigger, sealed)
    values (r.id, r.transaction_id, v_cycle, 'escalated', v->'failed', p_trigger, true);
    perform public.fn_ceo_founder_summary('Refund approval loop stuck: refund #' || r.id,
      'The CEO rejected refund #' || r.id || ' three times and these checks still fail: '
        || (select string_agg((i->>'item') || ' (' || coalesce(i->>'reason', '') || ')', '; ') from jsonb_array_elements(v->'failed') i)
        || '. No money moves until they pass. Refunds and supplier charges are ' || case when public.fn_refunds_paused() then 'PAUSED' else 'running' end || '.',
      'refund_loop_stuck:' || r.id);
    return jsonb_build_object('ok', false, 'outcome', 'escalated', 'cycle', v_cycle);
  end if;

  insert into public.refund_ceo_review (refund_id, transaction_id, cycle, outcome, failed, trigger)
  values (r.id, r.transaction_id, v_cycle, 'rejected', v->'failed', p_trigger) returning id into v_rev;
  select chase_after_working_days into v_chase from public.pricing_config order by id limit 1;
  v_deadline := public.fn_add_working_days(now(), coalesce(v_chase, 3));
  for x in
    select i->>'owner' as owner, i->>'remedy_key' as rk, jsonb_agg(i->>'item') as checks, jsonb_agg(i) as items
      from jsonb_array_elements(v->'failed') i group by 1, 2 order by 1, 2
  loop
    v_task := public.fn_seat_handoff('ceo', x.owner, 'refund.remediate', 'refunds', r.id || ':c' || v_cycle || ':' || x.rk,
      jsonb_build_object('refund_id', r.id, 'transaction_id', r.transaction_id, 'cycle', v_cycle, 'review_id', v_rev,
                         'remedy_key', x.rk, 'checks', x.checks, 'items', x.items, 'deadline', v_deadline));
    v_tasks := v_tasks || jsonb_build_object('handoff_id', v_task, 'owner', x.owner, 'checks', x.checks);
  end loop;
  update public.refund_ceo_review set sealed = true, tasks = v_tasks where id = v_rev;
  v_adv := public.fn_ceo_refund_loop_advance(r.id);
  return jsonb_build_object('ok', false, 'outcome', 'rejected', 'cycle', v_cycle, 'tasks', v_tasks, 'advance', v_adv);
end $fn$;
revoke execute on function public.fn_ceo_refund_review(bigint, text) from public, anon, authenticated;

create or replace function public.fn_ceo_refund_loop_advance(p_refund_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v public.refund_ceo_review;
begin
  select * into v from public.refund_ceo_review where refund_id = p_refund_id and outcome = 'rejected' order by cycle desc limit 1;
  if not found or not v.sealed or v.rechecked_at is not null then return jsonb_build_object('moved', false); end if;
  if exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'refund.remediate'
               and a.detail->>'refund_id' = p_refund_id::text and (a.detail->>'cycle')::int = v.cycle and a.status <> 'done') then
    return jsonb_build_object('moved', false, 'waiting', true, 'cycle', v.cycle);
  end if;
  if exists (select 1 from public.refund_ceo_review x where x.refund_id = p_refund_id and x.cycle > v.cycle) then
    return jsonb_build_object('moved', false);
  end if;
  update public.refund_ceo_review set rechecked_at = now() where id = v.id;
  return jsonb_build_object('moved', true, 'review', public.fn_ceo_refund_review(p_refund_id, 'remediation_closed'));
end $fn$;
revoke execute on function public.fn_ceo_refund_loop_advance(bigint) from public, anon, authenticated;

-- What a tick does for the loop: re-measure tasks waiting on the outside world, surface the overdue
-- ones, and raise supplier charges that were held while the breaker was on.
create or replace function public.fn_ceo_refund_loop_sweep()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a record; v jsonb; n_closed int := 0; n_overdue int := 0; n_raised int := 0; x record;
begin
  for a in select * from public.agent_actions
            where kind = 'handoff' and detail->>'type' = 'refund.remediate' and status = 'pending' order by id loop
    v := public.fn_ceo_refund_checklist((a.detail->>'transaction_id')::uuid, 'approve', false);
    if not exists (select 1 from jsonb_array_elements(v->'items') i
                    where (a.detail->'checks') ? (i->>'item') and not coalesce((i->>'passed')::boolean, false)) then
      perform public.fn_seat_handoff_complete(a.id, jsonb_build_object('resolved_by', 're-measured', 'checks', a.detail->'checks'));
      n_closed := n_closed + 1;
    elsif now() > (a.detail->>'deadline')::timestamptz and not (a.detail ? 'escalated_at') then
      update public.agent_actions set detail = detail || jsonb_build_object('escalated_at', now()) where id = a.id;
      perform public.fn_ceo_founder_summary('Refund task overdue: refund #' || (a.detail->>'refund_id'),
        'The ' || a.agent || ' has not closed the CEO''s task on refund #' || (a.detail->>'refund_id') || ' (' || (a.detail->>'checks')
          || ') by its deadline ' || to_char((a.detail->>'deadline')::timestamptz at time zone 'Asia/Dubai', 'DD Mon YYYY')
          || '. The refund stays blocked. Refunds and supplier charges are ' || case when public.fn_refunds_paused() then 'PAUSED' else 'running' end || '.',
        'refund_task_overdue:' || a.id);
      n_overdue := n_overdue + 1;
    end if;
  end loop;

  if not public.fn_refunds_paused() then
    for x in select t.id from public.transactions t
              where t.refund_status in ('refunded', 'succeeded') and t.refund_amount_aed is not null
                and coalesce(t.refund_reason, 'supplier_unresponsive') = 'supplier_unresponsive'
                and not exists (select 1 from public.supplier_dues d where d.transaction_id = t.id and coalesce(d.status, '') <> 'cancelled') loop
      v := public.fn_accountant_raise_nonresponse_charge(x.id, true);
      if coalesce((v->>'created')::boolean, false) then n_raised := n_raised + 1; end if;
    end loop;
  end if;
  return jsonb_build_object('remediation_closed', n_closed, 'remediation_overdue', n_overdue, 'held_charges_raised', n_raised);
end $fn$;
revoke execute on function public.fn_ceo_refund_loop_sweep() from public, anon, authenticated;

-- ── 9. AFTER THE MONEY MOVED: RE-VERIFY, AND THE PLAYBOOK WHEN IT DID NOT MATCH ─────────────────
create or replace function public.fn_ceo_refund_verify(p_transaction_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v jsonb; v_inc bigint;
begin
  -- An incident already open on this payment owns the re-verification: it re-runs the checklist and
  -- either closes (and resumes) or stays paused. A second incident on the same money is never opened.
  select id into v_inc from public.refund_incident i
   where i.transaction_id = p_transaction_id and i.status in ('open', 'paused') order by id desc limit 1;
  if v_inc is not null then
    return jsonb_build_object('incident', v_inc, 'advance', public.fn_ceo_incident_advance(v_inc, 0));
  end if;
  v := public.fn_ceo_refund_checklist(p_transaction_id, 'verify', true);
  if (v->>'ok')::boolean then return v; end if;
  return v || jsonb_build_object('incident', public.fn_ceo_refund_mismatch_playbook(p_transaction_id, v));
end $fn$;
revoke execute on function public.fn_ceo_refund_verify(uuid) from public, anon, authenticated;

-- (c) FIX BY TYPE. Each fix is a handoff whose subject is (incident, fix), so a fix is applied once per
-- incident; returns how many NEW fixes this round started.
create or replace function public.fn_ceo_incident_fix_round(p_incident_id bigint, p_verify jsonb)
returns int language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  i public.refund_incident; t public.transactions; v_kinds text[]; v_kind text; v_fix text; v_subject text; v_payload jsonb;
  v_money jsonb; v_app numeric; v_act numeric; du public.supplier_dues; y record; v_new int := 0; v_fixes jsonb := '[]'::jsonb;
begin
  select * into i from public.refund_incident where id = p_incident_id;
  select * into t from public.transactions where id = i.transaction_id;
  select x->'evidence' into v_money from jsonb_array_elements(p_verify->'items') x where x->>'item' = 'money_moved_as_approved';
  v_app := (v_money->>'approved_aed')::numeric; v_act := (v_money->>'actual_aed')::numeric;
  select coalesce(array_agg(distinct x->>'kind'), '{}') into v_kinds from jsonb_array_elements(p_verify->'failed') x;
  -- A refund that never settled is retried, never also topped up; a duplicate is cancelled first, and
  -- only booked as a loss if Stripe will not cancel it.
  if 'stripe_failed_or_pending' = any(v_kinds) then v_kinds := array_remove(v_kinds, 'under_refund'); end if;
  if 'duplicate_refund' = any(v_kinds) then v_kinds := array_remove(v_kinds, 'over_refund'); end if;

  foreach v_kind in array v_kinds loop
    v_fix := case v_kind when 'under_refund' then 'refund_difference' when 'over_refund' then 'book_over_refund_loss'
                         when 'stripe_failed_or_pending' then 'retry_refund' when 'duplicate_refund' then 'cancel_duplicate'
                         when 'charge_missing' then 'raise_charge' when 'wrong_charge_unsent' then 'reissue_charge'
                         when 'wrong_charge_sent' then 'reissue_charge' end;
    if v_fix is not null then
      v_subject := p_incident_id || ':' || v_fix || case when v_fix = 'reissue_charge' then ':' || v_kind else '' end;
      continue when exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'accountant'
                              and a.target_id = 'incident.fix:' || v_subject);
      v_payload := jsonb_build_object('incident_id', p_incident_id, 'transaction_id', t.id, 'refund_id', i.refund_id, 'fix', v_fix,
                                      'payment_ref', t.payment_ref, 'sent', v_kind = 'wrong_charge_sent');
      if v_fix = 'refund_difference' then v_payload := v_payload || jsonb_build_object('amount_fils', round((v_app - v_act) * 100)::bigint); end if;
      if v_fix = 'book_over_refund_loss' then v_payload := v_payload || jsonb_build_object('amount_aed', v_act - v_app); end if;
      if v_fix = 'cancel_duplicate' then
        v_payload := v_payload || jsonb_build_object('excess_aed', v_act - v_app,
          'refund_ids', (select jsonb_agg(x.stripe_refund_id order by x.id) from public.refunds x
                          where x.status = 'succeeded' and (x.transaction_id = t.id or x.stripe_payment_intent = t.payment_ref)));
      end if;
      perform public.fn_seat_handoff('ceo', 'accountant', 'incident.fix', 'refund_incident', v_subject, v_payload);
      v_fixes := v_fixes || jsonb_build_object('kind', v_kind, 'fix', v_fix);
      v_new := v_new + 1;

    elsif v_kind = 'missed_handoff' then
      -- THE CEO RE-TRIGGERS WHAT DID NOT HAPPEN. A sales-engineer handoff that finished without a
      -- delivery behind it is superseded and sent again; a failed one never blocks a new one.
      select * into du from public.supplier_dues where transaction_id = t.id and coalesce(status, '') <> 'cancelled' order by id limit 1;
      for y in
        select a.id from public.agent_actions a
         where a.kind = 'handoff' and a.agent = 'sales_engineer' and a.status = 'done'
           and ((a.target_id = 'refund.paid:' || t.id
                 and not exists (select 1 from public.agent_actions b where b.kind = 'handoff' and b.agent = 'customer_support'
                                   and b.target_id = 'delivery.request:refund_issued:' || t.id and b.status = 'done'
                                   and coalesce((b.evidence->>'delivered')::boolean, false)))
             or (du.id is not null and a.target_id = 'nonresponse.charge_raised:' || du.id
                 and not exists (select 1 from public.agent_actions b where b.kind = 'handoff' and b.agent = 'customer_support'
                                   and b.target_id = 'delivery.request:nonresponse_charge:' || du.id and b.status = 'done'
                                   and coalesce((b.evidence->>'delivered')::boolean, false))))
      loop
        update public.agent_actions set status = 'failed', detail = detail || jsonb_build_object('superseded_by_incident', p_incident_id) where id = y.id;
        -- its delivery request, if any, goes with it, so the new one is not deduplicated into the old
        update public.agent_actions b set status = 'failed', detail = b.detail || jsonb_build_object('superseded_by_incident', p_incident_id)
         where b.kind = 'handoff' and b.agent = 'customer_support' and b.status = 'done'
           and b.target_id in ('delivery.request:refund_issued:' || t.id, 'delivery.request:nonresponse_charge:' || coalesce(du.id::text, '-'))
           and not coalesce((b.evidence->>'delivered')::boolean, false);
        v_new := v_new + 1;
      end loop;
      if not exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'sales_engineer'
                       and a.target_id = 'refund.paid:' || t.id and a.status <> 'failed') then
        perform public.fn_seat_handoff('accountant', 'sales_engineer', 'refund.paid', 'transactions', t.id::text,
          jsonb_build_object('transaction_id', t.id, 'customer_id', t.customer_id, 'supplier_id', t.supplier_id, 'inquiry_id', t.inquiry_id,
                             'quote_id', t.quote_id, 'revealed_at', t.revealed_at, 'amount_aed', coalesce(round(t.refund_amount_aed, 2), v_act)));
        v_new := v_new + 1;
      end if;
      if du.id is not null
         and not exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'sales_engineer'
                           and a.target_id = 'nonresponse.charge_raised:' || du.id and a.status <> 'failed') then
        perform public.fn_seat_handoff('accountant', 'sales_engineer', 'nonresponse.charge_raised', 'supplier_dues', du.id::text,
          public.fn_accountant_nonresponse_charge(t.id, null)
            || jsonb_build_object('due_id', du.id, 'transaction_id', t.id, 'supplier_id', t.supplier_id, 'inquiry_id', t.inquiry_id, 'quote_id', t.quote_id));
        v_new := v_new + 1;
      end if;
      v_fixes := v_fixes || jsonb_build_object('kind', v_kind, 'fix', 'retriggered the handoffs that had no delivery behind them');
    else
      v_fixes := v_fixes || jsonb_build_object('kind', v_kind, 'fix', 'none automatic: stays paused for the CEO');
    end if;
  end loop;

  update public.refund_incident
     set fixes = fixes || v_fixes, kinds = (select array_agg(distinct k) from unnest(kinds || v_kinds) k)
   where id = p_incident_id;
  return v_new;
end $fn$;
revoke execute on function public.fn_ceo_incident_fix_round(bigint, jsonb) from public, anon, authenticated;

create or replace function public.fn_ceo_refund_mismatch_playbook(p_transaction_id uuid, p_verify jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_inc bigint; v_money jsonb; v_app numeric; v_act numeric;
begin
  -- (a) PAUSE. Every refund and charge path reads this.
  update public.decision_policy set value = 'true'::jsonb, updated_at = now() where key = 'refunds_and_supplier_charges_paused';
  -- (b) THE INCIDENT: approved vs actual vs difference.
  select x->'evidence' into v_money from jsonb_array_elements(p_verify->'items') x where x->>'item' = 'money_moved_as_approved';
  v_app := (v_money->>'approved_aed')::numeric; v_act := (v_money->>'actual_aed')::numeric;
  insert into public.refund_incident (transaction_id, refund_id, approved_aed, actual_aed, difference_aed, status, evidence)
  values (p_transaction_id, (p_verify->>'refund_id')::bigint, v_app, v_act, v_act - v_app, 'open', p_verify)
  returning id into v_inc;
  -- (c) FIX BY TYPE, then seal so no fix can close the incident before every fix exists.
  perform public.fn_ceo_incident_fix_round(v_inc, p_verify);
  update public.refund_incident set sealed = true where id = v_inc;
  -- (d) and (e): re-run the checklist; resume only when green; tell the founder.
  return jsonb_build_object('incident_id', v_inc, 'advance', public.fn_ceo_incident_advance(v_inc, 0));
end $fn$;
revoke execute on function public.fn_ceo_refund_mismatch_playbook(uuid, jsonb) from public, anon, authenticated;

drop function if exists public.fn_ceo_incident_advance(bigint);
create or replace function public.fn_ceo_incident_advance(p_incident_id bigint, p_depth int default 0)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare i public.refund_incident; v jsonb; v_paused boolean; v_what text; v_fixed text; t public.transactions; v_new int;
begin
  select * into i from public.refund_incident where id = p_incident_id for update;
  if not found or not i.sealed or i.status = 'fixed' then return jsonb_build_object('moved', false); end if;
  if exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'incident.fix'
               and a.detail->>'incident_id' = p_incident_id::text and a.status = 'pending') then
    return jsonb_build_object('moved', false, 'waiting', true);
  end if;
  select * into t from public.transactions where id = i.transaction_id;
  v := public.fn_ceo_refund_checklist(i.transaction_id, 'verify', true);

  if not (v->>'ok')::boolean and p_depth < 1 then
    -- A fix can surface the next thing to fix (a top-up changes what the supplier owes). One more
    -- round, bounded: each fix is applied once per incident.
    v_new := public.fn_ceo_incident_fix_round(i.id, v);
    if v_new > 0 then return public.fn_ceo_incident_advance(i.id, p_depth + 1); end if;
  end if;

  select * into i from public.refund_incident where id = p_incident_id;
  v_what := 'Refund mismatch on reveal #' || left(i.transaction_id::text, 8) || ' (' || array_to_string(i.kinds, ', ')
         || '): approved AED ' || coalesce(i.approved_aed::text, '?') || ', refunded AED ' || coalesce(i.actual_aed::text, '?') || '.';
  v_fixed := (select string_agg(f->>'fix', '; ') from jsonb_array_elements(i.fixes) f);

  if (v->>'ok')::boolean then
    update public.refund_incident set status = 'fixed', closed_at = now() where id = i.id;
    if not exists (select 1 from public.refund_incident x where x.status in ('open', 'paused') and x.id <> i.id) then
      update public.decision_policy set value = 'false'::jsonb, updated_at = now() where key = 'refunds_and_supplier_charges_paused';
    end if;
    v_paused := public.fn_refunds_paused();
    perform public.fn_ceo_founder_summary('Refund mismatch fixed: reveal #' || left(i.transaction_id::text, 8),
      v_what || ' Fixed: ' || coalesce(v_fixed, 'nothing needed') || '. Every check passes again. Refunds and supplier charges are '
        || case when v_paused then 'still PAUSED by another open incident' else 'running again' end || '.',
      'refund_incident:' || i.id || ':fixed');
    return jsonb_build_object('moved', true, 'status', 'fixed', 'paused', v_paused);
  end if;

  update public.refund_incident set status = 'paused' where id = i.id;
  -- A refund the retry could not settle: the customer is told it is in progress, nothing more.
  if exists (select 1 from jsonb_array_elements(v->'failed') f where f->>'kind' = 'stripe_failed_or_pending')
     and exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'incident.fix'
                   and a.detail->>'incident_id' = i.id::text and a.detail->>'fix' = 'retry_refund' and a.status in ('done', 'failed')) then
    perform public.fn_seat_handoff('accountant', 'sales_engineer', 'refund.in_progress', 'transactions', t.id::text,
      jsonb_build_object('transaction_id', t.id, 'customer_id', t.customer_id, 'inquiry_id', t.inquiry_id, 'quote_id', t.quote_id,
                         'amount_aed', coalesce(t.total_charged, t.reveal_fee)));
  end if;
  perform public.fn_ceo_founder_summary('Refund mismatch still open: reveal #' || left(i.transaction_id::text, 8),
    v_what || ' Tried: ' || coalesce(v_fixed, 'nothing automatic') || '. Still failing: '
      || (select string_agg((f->>'item') || ' (' || coalesce(f->>'reason', '') || ')', '; ') from jsonb_array_elements(v->'failed') f)
      || '. Refunds and supplier charges stay PAUSED.',
    'refund_incident:' || i.id || ':paused');
  return jsonb_build_object('moved', true, 'status', 'paused', 'failed', v->'failed');
end $fn$;
revoke execute on function public.fn_ceo_incident_advance(bigint, int) from public, anon, authenticated;

-- The accountant applies a fix. The three that touch Stripe wait for the accountant runtime
-- (accountant action execute_refunds), which calls Stripe and reports back with
-- fn_seat_handoff_complete or fn_accountant_incident_fix_failed.
create or replace function public.fn_accountant_applies_incident_fix(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare d jsonb; v_fix text; v_tx uuid; v_old bigint; v_orig bigint; v jsonb; v_j bigint; v_amt numeric; v_res jsonb; v_du public.supplier_dues;
begin
  select detail into d from public.agent_actions where id = p_id;
  v_fix := d->>'fix'; v_tx := (d->>'transaction_id')::uuid;
  if v_fix in ('refund_difference', 'retry_refund', 'cancel_duplicate') then
    return jsonb_build_object('waiting', 'stripe: the accountant runtime executes ' || v_fix || ' (accountant action execute_refunds)');
  end if;

  perform set_config('app.qd_incident_fix', 'on', true);
  if v_fix = 'book_over_refund_loss' then
    v_amt := round((d->>'amount_aed')::numeric, 2);
    select g.id into v_j from public.gl_journal g where g.source = 'refund_over_loss' and g.source_ref = v_tx || ':' || (d->>'incident_id');
    if v_j is null and v_amt > 0 then
      v_j := public.fn_gl_entry(current_date,
        'Over-refund on reveal ' || left(v_tx::text, 8) || ' booked as company loss (incident #' || (d->>'incident_id') || '); the supplier charge stays at the approved amount',
        'refund_over_loss', v_tx || ':' || (d->>'incident_id'),
        jsonb_build_array(jsonb_build_object('account', '6900', 'debit', v_amt), jsonb_build_object('account', '1050', 'credit', v_amt)), 'accountant');
    end if;
    v_res := jsonb_build_object('journal_id', v_j, 'amount_aed', v_amt);
  elsif v_fix = 'reissue_charge' then
    -- supplier_dues holds ONE row per transaction (supplier_dues_transaction_id_key), so the charge is
    -- reissued IN PLACE: the figures become the routine's, and the old ones are kept in the evidence.
    select * into v_du from public.supplier_dues where transaction_id = v_tx order by id limit 1;
    v_old := v_du.id;
    select (a.evidence->>'notification_id')::bigint into v_orig from public.agent_actions a
     where a.kind = 'handoff' and a.agent = 'customer_support' and a.target_id = 'delivery.request:nonresponse_charge:' || v_old
     order by a.id desc limit 1;
    v := public.fn_accountant_nonresponse_charge(v_tx, null);
    if not coalesce((v->>'ok')::boolean, false) then
      perform set_config('app.qd_incident_fix', '', true);
      return jsonb_build_object('waiting', 'the charge cannot be recomputed: ' || coalesce(v->>'reason', '?'));
    end if;
    update public.supplier_dues
       set amount_due = (v->>'refunded_aed')::numeric, admin_fee = (v->>'admin_fee_aed')::numeric,
           interest_amount = (v->>'interest_aed')::numeric, total_claim = (v->>'total_aed')::numeric,
           due_date = (v->>'due_date')::date, due_date_30 = (v->>'due_date')::date + 23,
           status = case when status = 'cancelled' then 'due' else status end
     where id = v_old;
    v := v || jsonb_build_object('due_id', v_old, 'transaction_id', v_tx, 'supplier_id', v_du.supplier_id,
                                 'inquiry_id', (select inquiry_id from public.transactions where id = v_tx),
                                 'quote_id', (select quote_id from public.transactions where id = v_tx));
    if coalesce((d->>'sent')::boolean, false) then
      -- Already in the supplier's hands: a correction that supersedes it, to whoever got the original.
      perform public.fn_seat_handoff('accountant', 'sales_engineer', 'charge.corrected', 'supplier_dues', v_old::text,
        v || jsonb_build_object('original_notification_id', v_orig));
    else
      -- Not sent yet: withdraw it from the outbox and send the right one instead.
      update public.notifications set status = 'cancelled', last_error = 'withdrawn before sending: the charge was reissued with the correct figures'
       where id = v_orig and status in ('queued', 'pending', 'held');
      update public.agent_actions set status = 'failed', detail = detail || jsonb_build_object('superseded_by_incident', d->>'incident_id')
       where kind = 'handoff' and status = 'done'
         and target_id in ('nonresponse.charge_raised:' || v_old, 'delivery.request:nonresponse_charge:' || v_old);
      perform public.fn_seat_handoff('accountant', 'sales_engineer', 'nonresponse.charge_raised', 'supplier_dues', v_old::text, v);
    end if;
    v_res := jsonb_build_object('reissued_due', v_old,
      'was', jsonb_build_object('amount_due', v_du.amount_due, 'admin_fee', v_du.admin_fee, 'due_date', v_du.due_date),
      'now', v, 'correction_sent_to_original_recipients', coalesce((d->>'sent')::boolean, false));
  elsif v_fix = 'raise_charge' then
    v_res := public.fn_accountant_raise_nonresponse_charge(v_tx, true);
  else
    v_res := jsonb_build_object('waiting', 'no handler for fix ' || coalesce(v_fix, '?'));
  end if;
  perform set_config('app.qd_incident_fix', '', true);
  return v_res;
end $fn$;
revoke execute on function public.fn_accountant_applies_incident_fix(bigint) from public, anon, authenticated;

create or replace function public.fn_accountant_incident_fix_failed(p_id bigint, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions;
begin
  update public.agent_actions
     set status = 'failed', decided_at = now(), detail = detail || jsonb_build_object('error', left(p_reason, 500), 'failed_at', now())
   where id = p_id and kind = 'handoff' and detail->>'type' = 'incident.fix' and status = 'pending'
  returning * into a;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no pending incident fix ' || p_id); end if;
  perform public.fn_seat_handoff_event(p_id, 'failed');
  -- A duplicate Stripe will not cancel is money gone: book it as the company's loss.
  if a.detail->>'fix' = 'cancel_duplicate' then
    perform public.fn_seat_handoff('ceo', 'accountant', 'incident.fix', 'refund_incident', (a.detail->>'incident_id') || ':book_over_refund_loss',
      jsonb_build_object('incident_id', a.detail->>'incident_id', 'transaction_id', a.detail->>'transaction_id',
                         'fix', 'book_over_refund_loss', 'amount_aed', a.detail->>'excess_aed'));
  end if;
  return jsonb_build_object('ok', true, 'advance', public.fn_ceo_incident_advance((a.detail->>'incident_id')::bigint));
end $fn$;
revoke execute on function public.fn_accountant_incident_fix_failed(bigint, text) from public, anon, authenticated;

-- ── 10. A REFUND STRIPE REPORTS THAT NOBODY HERE ASKED FOR IS VERIFIED TOO ─────────────────────
-- fn_refund_settle records a refund issued outside the platform (the Stripe dashboard, a duplicate,
-- a playbook top-up) as a refunds row with requested_by 'stripe_webhook'. Such a row never touches
-- transactions, so without this the CEO would never see it: money leaving on a payment he approved a
-- different amount for, or did not approve at all.
create or replace function public.fn_external_refund_is_verified()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_tx uuid;
begin
  if NEW.status <> 'succeeded' or (TG_OP = 'UPDATE' and OLD.status = 'succeeded') then return NEW; end if;
  if lower(coalesce(NEW.requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe') then return NEW; end if;
  v_tx := coalesce(NEW.transaction_id,
                   (select t.id from public.transactions t
                     where coalesce(NEW.stripe_payment_intent, '') <> '' and t.payment_ref = NEW.stripe_payment_intent limit 1));
  if v_tx is not null then
    begin
      perform public.fn_ceo_refund_verify(v_tx);
    exception when others then
      insert into public.ceo_task (title, detail)
      values (left('A refund Stripe reported on reveal ' || left(v_tx::text, 8) || ' could not be verified', 200),
              'fn_ceo_refund_verify raised: ' || sqlerrm || '. Stripe refund ' || coalesce(NEW.stripe_refund_id, '?') || ' is recorded.');
    end;
  end if;
  return NEW;
end $fn$;
revoke execute on function public.fn_external_refund_is_verified() from public, anon, authenticated;
drop trigger if exists z50_external_refund_is_verified on public.refunds;
create trigger z50_external_refund_is_verified after insert or update of status on public.refunds
  for each row execute function public.fn_external_refund_is_verified();
