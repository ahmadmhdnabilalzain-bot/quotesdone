-- CUSTOMER SUPPORT ACTIVATES NEW CUSTOMERS, WINS BACK DORMANT ONES AND SETTLES POST-REVEAL DISPUTES.
-- Seat: customer_support (and the ceo, who decides a dispute). 23 Sep 2026, founder_instruction 898 ("no new
-- agents": these are extra duties of the seats that exist). Builds on
-- every_seat_duty_has_an_owner_a_clock_and_a_check.sql (#901), which must be applied first.
--
-- WHAT WAS MEASURED (23 Sep 2026, production, read-only):
--   * 4 customers, 3 inquiries, 3 quotes, 1 transaction. No routine nudges a customer who signed up and never
--     posted, a request that has no quote, or a customer who has gone quiet after a revealed job: searched pg_proc
--     for activation / dormant / winback / nudge and found only fn_kb_route_activation_blocked (a knowledge
--     route, unrelated). inquiries.no_quote_notified exists and nothing reads it for a customer message.
--   * Disputes: fn_accountant_dispute_* and stripe_dispute are CARD CHARGEBACKS (the bank's process, owned by the
--     accountant); complaint_tickets / fn_complaint_open is a complaint about QuotesDone itself, one e-mail, one
--     ticket, no transaction and no second party. Neither holds a customer-versus-supplier case after a reveal, so
--     this file adds one. What it REUSES: fn_add_working_days (the complaint clock's calendar),
--     fn_customer_support_takes_delivery (the one door to customers and suppliers), fn_email_sendable (which
--     already refuses a suppressed, malformed or dead address), fn_seat_duty_reason / fn_seat_duty_cross_review.
--
-- WHAT THIS ADDS
--   1. customer_support.activation (every 6 hours, fn_customer_support_activation_tick): a customer with no request
--      3 days after sign-up is written to once; a request with no quote after 5 days is written to once; a request
--      still with no quote after 10 days is a JUDGEMENT (what to tell this customer) filed with
--      fn_seat_duty_reason and applied by fn_reason_apply_customer_support__stalled_request.
--   2. customer_support.winback (daily, fn_customer_support_winback_tick): a customer whose last activity is a
--      revealed job 60 to 90 days ago gets ONE win-back message per dormant spell.
--   3. customer_support.disputes (every 30 minutes, fn_customer_support_disputes_tick): the case file
--      public.post_reveal_dispute with its stages and clocks — evidence from both parties (5 working days), then
--      the seat's reasoned finding on fault, then the CEO's decision (3 working days, an overdue decision is a
--      finding owned by the ceo). Whether a party's message IS a dispute, and who is at fault, are reasoned
--      (surfaces customer_support.dispute_intake and customer_support.dispute_fault); the finding goes to the
--      CEO with a cross-family review (deliberation.review customer_support -> ceo, registered here).
--   Suppression: every message goes through fn_customer_support_duty_send, which records each (stage, subject)
--   once and sends only to an address fn_email_sendable accepts (email_suppressions, dead domains, block
--   patterns); banned and demo customers are never selected. A fixture run is opted into with
--   set local qd.duty_fixtures = 'on' and then selects ONLY demo rows, so a probe cannot reach a real person.
--
-- WHAT THIS DOES NOT DO: it sends no WhatsApp (e-mail only; the WhatsApp opt-in path is its own build); it does
-- not move money on a dispute (a refund stays the accountant's, approved by the CEO); it does not give a party a
-- portal screen for evidence (support records what arrives by e-mail with fn_customer_support_dispute_evidence).

-- ── the record of every message a duty sent: once per stage and subject, never twice ───────────────
create table if not exists public.customer_support_duty_message (
  stage        text not null check (stage ~ '^[a-z_]+\.[a-z_]+$'),
  subject_key  text not null check (btrim(subject_key) <> ''),
  customer_id  uuid,
  lead_id      bigint,
  to_email     text,
  outcome      text not null default 'pending',
  handoff_id   bigint,
  created_at   timestamptz not null default now(),
  primary key (stage, subject_key)
);
alter table public.customer_support_duty_message enable row level security;
drop policy if exists customer_support_duty_message_service_role_only on public.customer_support_duty_message;
create policy customer_support_duty_message_service_role_only on public.customer_support_duty_message
  as permissive for all to public using (false) with check (false);
revoke all on public.customer_support_duty_message from anon, authenticated;

create or replace function public.fn_customer_support_duty_send(p_stage text, p_key text, p_to_role text, p_email text,
  p_lang text, p_subject text, p_body text, p_customer uuid default null, p_lead bigint default null, p_inquiry uuid default null)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_to text := lower(nullif(btrim(coalesce(p_email, '')), '')); v_ok jsonb; v_res jsonb; v_h bigint;
begin
  insert into public.customer_support_duty_message (stage, subject_key, customer_id, lead_id, to_email)
  values (p_stage, p_key, p_customer, p_lead, v_to)
  on conflict (stage, subject_key) do nothing;
  if not found then return jsonb_build_object('sent', false, 'reason', 'already written at this stage'); end if;
  v_ok := public.fn_email_sendable(v_to);
  if not coalesce((v_ok->>'ok')::boolean, false) then
    update public.customer_support_duty_message set outcome = 'not_sendable: ' || (v_ok->>'reason')
     where stage = p_stage and subject_key = p_key;
    return jsonb_build_object('sent', false, 'reason', v_ok->>'reason');
  end if;
  v_res := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
    'type', 'duty_' || replace(p_stage, '.', '_'), 'requested_by', 'customer_support', 'channel', 'email',
    'to_email', v_to, 'to_role', p_to_role, 'lead_id', p_lead, 'inquiry_id', p_inquiry,
    'lang', case when p_lang = 'ar' then 'ar' else 'en' end,
    'dedupe_key', 'duty:' || p_stage || ':' || p_key, 'subject', p_subject, 'body', p_body)));
  v_h := (v_res->0->>'handoff_id')::bigint;
  update public.customer_support_duty_message set outcome = 'queued', handoff_id = v_h
   where stage = p_stage and subject_key = p_key;
  return jsonb_build_object('sent', true, 'handoff_id', v_h);
end $fn$;
revoke execute on function public.fn_customer_support_duty_send(text, text, text, text, text, text, text, uuid, bigint, uuid) from public, anon, authenticated;
grant execute on function public.fn_customer_support_duty_send(text, text, text, text, text, text, text, uuid, bigint, uuid) to service_role;

-- ── 1. activation ────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_customer_support_activation_tick()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  r record; v jsonb; v_ar boolean; v_name text; v_signup int := 0; v_noquote int := 0; v_stalled int := 0;
begin
  -- a) signed up three days ago or more, never posted a request
  for r in select c.id, c.full_name, c.email, c.locale from public.customers c
            where c.created_at < now() - interval '3 days' and not coalesce(c.banned, false)
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
              and not exists (select 1 from public.inquiries i where i.customer_id = c.id)
            order by c.created_at limit 200 loop
    v_ar := r.locale = 'ar'; v_name := coalesce(nullif(btrim(r.full_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
    v := public.fn_customer_support_duty_send('activation.first_request', r.id::text, 'customer', r.email,
      case when v_ar then 'ar' else 'en' end,
      case when v_ar then 'طلبكم الأول على QuotesDone' else 'Your first request on QuotesDone' end,
      case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'شكرًا لانضمامكم إلى QuotesDone. لم تنشروا طلبكم الأول بعد، ويكفي أن تصفوا ما تحتاجون إليه، وأن ترفقوا المخطط أو جدول الكميات إن توفّر، لتصلكم عروض أسعار من موردين مؤهلين في الإمارات، حتى ثلاثة عروض. ولا تدفعون شيئًا إلا إذا اخترتم الاطلاع على بيانات مورّد.' || chr(10) || chr(10)
        || 'ابدؤوا من هنا: https://quotesdone.com/portal' || chr(10) || chr(10)
        || 'وإن واجهتم ما يمنعكم من البدء، يسعدنا أن تردّوا على هذه الرسالة لنساعدكم.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'Thank you for joining QuotesDone. You have not posted a request yet. Describe what you need, attach a drawing or a bill of quantities if you have one, and up to three qualified UAE suppliers will quote. You pay only if you choose to see a supplier''s details.' || chr(10) || chr(10)
        || 'Start here: https://quotesdone.com/portal' || chr(10) || chr(10)
        || 'If something stopped you, reply to this e-mail and we will help.' end,
      r.id);
    if (v->>'sent')::boolean then v_signup := v_signup + 1; end if;
  end loop;

  -- b) a request five days old with no quote, and c) ten days old with none: the second is a judgement
  for r in select i.id, i.rfq_no, i.created_at, i.category, i.emirate, i.trades, i.rfq_ready, i.completeness,
                  i.summary_masked, c.id as cid, c.full_name, c.email, c.locale
             from public.inquiries i join public.customers c on c.id = i.customer_id
            where i.created_at < now() - interval '5 days' and i.created_at > now() - interval '60 days'
              and i.completed_at is null and i.hired_supplier_id is null and not coalesce(c.banned, false)
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
              and not exists (select 1 from public.quotes q where q.inquiry_id = i.id)
            order by i.created_at limit 200 loop
    v_ar := r.locale = 'ar'; v_name := coalesce(nullif(btrim(r.full_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
    v := public.fn_customer_support_duty_send('activation.no_quote', r.id::text, 'customer', r.email,
      case when v_ar then 'ar' else 'en' end,
      case when v_ar then 'طلبكم لم يصله عرض سعر بعد' else 'Your request has no quote yet' end,
      case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'لم يصل بعدُ أي عرض سعر على طلبكم المنشور بتاريخ ' || to_char(r.created_at at time zone 'Asia/Dubai', 'DD/MM/YYYY')
        || '، وما زلنا ندعو الموردين العاملين في هذا المجال. ويساعد الموردين على التسعير بسرعة أن يتضمّن الطلب نطاق العمل والكميات والمخطط، ويمكنكم إضافتها من حسابكم: https://quotesdone.com/portal' || chr(10) || chr(10)
        || 'ولأي مساعدة، يسعدنا أن تردّوا على هذه الرسالة.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'Your request posted on ' || to_char(r.created_at at time zone 'Asia/Dubai', 'DD Mon YYYY')
        || ' has not received a quote yet, and we are still inviting suppliers who work in this trade. A clear scope, quantities and a drawing help suppliers price quickly; you can add them from your portal: https://quotesdone.com/portal' || chr(10) || chr(10)
        || 'Reply to this e-mail if you would like help.' end,
      r.cid, null, r.id);
    if (v->>'sent')::boolean then v_noquote := v_noquote + 1; end if;

    if r.created_at < now() - interval '10 days'
       and not exists (select 1 from public.customer_support_duty_message m where m.stage = 'activation.stalled' and m.subject_key = r.id::text)
       and not exists (select 1 from public.reasoning_held_question h where h.dedupe_key = 'stalled_request:' || r.id) then
      perform public.fn_seat_duty_reason('customer_support', 'customer_support.stalled_request',
        case when v_fx then 'ZZ DEMO ' else '' end
        || 'A customer''s request has had no quote for ' || extract(day from now() - r.created_at)::int
        || ' days. From the facts of the request, which message should customer support send the customer?',
        jsonb_build_array(
          jsonb_build_object('id', 'add_details', 'meaning', 'the request lacks what a supplier needs to price it; ask the customer for the missing scope, quantities or drawing'),
          jsonb_build_object('id', 'widen_scope', 'meaning', 'the request is priceable but too narrow for the suppliers available; suggest widening the emirate, the trade or the delivery window'),
          jsonb_build_object('id', 'keep_waiting', 'meaning', 'the request is sound; tell the customer it is still with suppliers and when to expect news')),
        jsonb_build_object('inquiry_id', r.id, 'rfq_no', r.rfq_no, 'posted_at', r.created_at, 'category', r.category,
          'emirate', r.emirate, 'trades', to_jsonb(r.trades), 'rfq_ready', r.rfq_ready, 'completeness', r.completeness,
          'summary', r.summary_masked, 'quotes', 0),
        jsonb_build_object('inquiry_id', r.id), 'stalled_request:' || r.id);
      v_stalled := v_stalled + 1;
    end if;
  end loop;
  return jsonb_build_object('first_request', v_signup, 'no_quote', v_noquote, 'stalled_filed', v_stalled);
end $fn$;
revoke execute on function public.fn_customer_support_activation_tick() from public, anon, authenticated;
grant execute on function public.fn_customer_support_activation_tick() to service_role;

create or replace function public.fn_reason_apply_customer_support__stalled_request(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare h public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; r record; v_ar boolean; v_name text;
  v_en text; v_arb text;
begin
  select * into h from public.reasoning_held_question where id = p_id;
  if not exists (select 1 from jsonb_array_elements(h.request->'decision'->'options') o where o->>'id' = v_choice) then
    -- fn_reason_held_resolve marks a row applied whenever its apply returns, so a non-answer RAISES and is reasoned again.
    raise exception 'CHOICE_NOT_AN_OPTION: % (held question %)', coalesce(v_choice, 'no choice'), p_id;
  end if;
  select i.id, i.created_at, c.id as cid, c.full_name, c.email, c.locale into r
    from public.inquiries i join public.customers c on c.id = i.customer_id where i.id::text = h.subject->>'inquiry_id';
  if not found then return jsonb_build_object('applied', false, 'reason', 'the request no longer exists'); end if;
  if exists (select 1 from public.quotes q where q.inquiry_id = r.id) then
    return jsonb_build_object('applied', true, 'sent', false, 'reason', 'a quote arrived while the question was held');
  end if;
  v_ar := r.locale = 'ar'; v_name := coalesce(nullif(btrim(r.full_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
  v_en := case v_choice
    when 'add_details' then 'Suppliers have looked at your request but need more to price it. Please add the scope of work, the quantities and, if you have one, a drawing or bill of quantities from your portal: https://quotesdone.com/portal'
    when 'widen_scope' then 'Few suppliers cover this request exactly as it stands. Widening it, for example to a neighbouring emirate, a related trade or a later delivery date, usually brings quotes in. You can change it from your portal: https://quotesdone.com/portal'
    else 'Your request is complete and is still with suppliers in this trade. We will write as soon as the first quote arrives; nothing is needed from you now.' end;
  v_arb := case v_choice
    when 'add_details' then 'اطّلع الموردون على طلبكم، ويحتاجون إلى تفاصيل أكثر لتسعيره. نرجو إضافة نطاق العمل والكميات، والمخطط أو جدول الكميات إن توفّر، من حسابكم: https://quotesdone.com/portal'
    when 'widen_scope' then 'عدد الموردين الذين يغطّون طلبكم بصيغته الحالية محدود، وتوسيعه عادةً يجلب العروض، كأن يشمل إمارة مجاورة أو تخصصًا قريبًا أو موعد تسليم لاحقًا. ويمكنكم تعديله من حسابكم: https://quotesdone.com/portal'
    else 'طلبكم مكتمل، وما زال لدى الموردين العاملين في هذا المجال. سنبلغكم فور وصول أول عرض سعر، ولا يلزمكم أي إجراء الآن.' end;
  return jsonb_build_object('applied', true, 'choice', v_choice, 'send',
    public.fn_customer_support_duty_send('activation.stalled', r.id::text, 'customer', r.email, case when v_ar then 'ar' else 'en' end,
      case when v_ar then 'مستجدات طلبكم على QuotesDone' else 'An update on your QuotesDone request' end,
      case when v_ar then 'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10) || v_arb
                          || chr(10) || chr(10) || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
           else 'Dear ' || v_name || ',' || chr(10) || chr(10) || v_en end,
      r.cid, null, r.id));
end $fn$;
revoke execute on function public.fn_reason_apply_customer_support__stalled_request(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_customer_support__stalled_request(bigint, jsonb) to service_role;

-- ── 2. win-back ──────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_customer_support_winback_tick()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on'; r record; v jsonb; v_ar boolean;
  v_name text; v_sent int := 0; v_seen int := 0;
begin
  for r in select c.id, c.full_name, c.email, c.locale, x.last_reveal
             from public.customers c
             cross join lateral (select max(t.revealed_at) as last_reveal from public.transactions t
                                  where t.customer_id = c.id and t.revealed_at is not null) x
            where x.last_reveal between now() - interval '90 days' and now() - interval '60 days'
              and not coalesce(c.banned, false)
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
              -- dormant: nothing posted since the last reveal
              and not exists (select 1 from public.inquiries i where i.customer_id = c.id and i.created_at > x.last_reveal)
            order by x.last_reveal limit 200 loop
    v_seen := v_seen + 1;
    v_ar := r.locale = 'ar'; v_name := coalesce(nullif(btrim(r.full_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
    -- one message per dormant spell: the key carries the reveal that started it
    v := public.fn_customer_support_duty_send('winback.dormant', r.id || ':' || to_char(r.last_reveal, 'YYYYMMDD'), 'customer',
      r.email, case when v_ar then 'ar' else 'en' end,
      case when v_ar then 'مشروعكم القادم على QuotesDone' else 'Your next project on QuotesDone' end,
      case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'مضى بعض الوقت على مشروعكم الأخير معنا. وحين يحين مشروعكم القادم، يكفي أن تنشروه في دقائق لتصلكم عروض أسعار من موردين مؤهلين في الإمارات، حتى ثلاثة عروض: https://quotesdone.com/portal' || chr(10) || chr(10)
        || 'وإن كنتم لا ترغبون في تلقّي مثل هذه الرسائل، فيكفي أن تردّوا على هذه الرسالة لنتوقف عن إرسالها.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'It has been a while since your last project with us. When the next one comes up, post it in a few minutes and receive up to three quotes from qualified UAE suppliers: https://quotesdone.com/portal' || chr(10) || chr(10)
        || 'If you would rather not hear from us like this, reply to this e-mail and we will stop.' end,
      r.id);
    if (v->>'sent')::boolean then v_sent := v_sent + 1; end if;
  end loop;
  return jsonb_build_object('dormant', v_seen, 'written', v_sent);
end $fn$;
revoke execute on function public.fn_customer_support_winback_tick() from public, anon, authenticated;
grant execute on function public.fn_customer_support_winback_tick() to service_role;

-- ── 3. post-reveal disputes ──────────────────────────────────────────────────────────────────────
create table if not exists public.post_reveal_dispute (
  id                  bigint generated always as identity primary key,
  transaction_id      uuid not null references public.transactions (id),
  inquiry_id          uuid,
  customer_id         uuid,
  supplier_id         bigint,
  raised_by           text not null check (raised_by in ('customer', 'supplier')),
  statement           text not null check (btrim(statement) <> ''),
  stage               text not null default 'evidence' check (stage in ('evidence', 'review', 'ceo_decision', 'decided')),
  evidence_due        timestamptz not null,
  customer_evidence   jsonb,
  supplier_evidence   jsonb,
  intake_question_id  bigint,
  fault_question_id   bigint,
  finding             text check (finding in ('customer_upheld', 'supplier_upheld', 'shared', 'no_fault')),
  finding_reasoning   text,
  finding_model       text,
  review              jsonb,
  decision_due        timestamptz,
  outcome             text check (outcome in ('customer_upheld', 'supplier_upheld', 'shared', 'no_fault')),
  outcome_note        text,
  decided_by          text check (decided_by = 'ceo'),
  decided_at          timestamptz,
  opened_at           timestamptz not null default now(),
  check ((stage = 'decided') = (outcome is not null))
);
create unique index if not exists post_reveal_dispute_one_open_per_transaction
  on public.post_reveal_dispute (transaction_id) where stage <> 'decided';
alter table public.post_reveal_dispute enable row level security;
drop policy if exists post_reveal_dispute_service_role_only on public.post_reveal_dispute;
create policy post_reveal_dispute_service_role_only on public.post_reveal_dispute
  as permissive for all to public using (false) with check (false);
revoke all on public.post_reveal_dispute from anon, authenticated;

-- A party wrote to support after a reveal. Whether that IS a dispute is reasoned, never matched.
create or replace function public.fn_customer_support_dispute_consider(p_transaction_id uuid, p_party text, p_message text)
returns bigint
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare t public.transactions; v_demo boolean;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found or t.revealed_at is null then raise exception 'a dispute is about a revealed job; % is not one', p_transaction_id; end if;
  if p_party not in ('customer', 'supplier') then raise exception 'the party is the customer or the supplier, not %', p_party; end if;
  select coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email) into v_demo from public.customers c where c.id = t.customer_id;
  return public.fn_seat_duty_reason('customer_support', 'customer_support.dispute_intake',
    case when v_demo then 'ZZ DEMO ' else '' end
    || 'A party to a revealed job wrote to customer support. Does the message raise a dispute with the other party that needs a case, or is it something support answers directly?',
    jsonb_build_array(
      jsonb_build_object('id', 'dispute', 'meaning', 'the party complains about the other party''s conduct or work on this job and wants it put right'),
      jsonb_build_object('id', 'not_dispute', 'meaning', 'a question, feedback or a request support can answer without involving the other party')),
    jsonb_build_object('party', p_party, 'message', left(p_message, 4000), 'revealed_at', t.revealed_at,
                       'transaction_id', t.id, 'inquiry_id', t.inquiry_id),
    jsonb_build_object('transaction_id', t.id, 'party', p_party, 'statement', left(p_message, 4000)),
    'dispute_intake:' || t.id || ':' || md5(p_party || coalesce(p_message, '')));
end $fn$;
revoke execute on function public.fn_customer_support_dispute_consider(uuid, text, text) from public, anon, authenticated;
grant execute on function public.fn_customer_support_dispute_consider(uuid, text, text) to service_role;

create or replace function public.fn_customer_support_dispute_open(p_transaction_id uuid, p_raised_by text, p_statement text,
  p_intake_question_id bigint default null)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare t public.transactions; d public.post_reveal_dispute; c record; s record; v_ref text; v_rfq text; v_due text;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found or t.revealed_at is null then raise exception 'a dispute is about a revealed job; % is not one', p_transaction_id; end if;
  select * into d from public.post_reveal_dispute where transaction_id = t.id and stage <> 'decided';
  if found then return jsonb_build_object('dispute_id', d.id, 'opened', false, 'reason', 'a case is already open on this job'); end if;
  insert into public.post_reveal_dispute (transaction_id, inquiry_id, customer_id, supplier_id, raised_by, statement,
                                          evidence_due, intake_question_id)
  values (t.id, t.inquiry_id, t.customer_id, t.supplier_id, p_raised_by, left(p_statement, 4000),
          public.fn_add_working_days(now(), 5), p_intake_question_id)
  returning * into d;
  if p_raised_by = 'customer' then d.customer_evidence := jsonb_build_object('statement', d.statement, 'at', now());
  else d.supplier_evidence := jsonb_build_object('statement', d.statement, 'at', now()); end if;
  update public.post_reveal_dispute set customer_evidence = d.customer_evidence, supplier_evidence = d.supplier_evidence where id = d.id;

  v_ref := 'QD-D-' || lpad(d.id::text, 5, '0');
  select coalesce(i.rfq_no::text, left(i.id::text, 8)) into v_rfq from public.inquiries i where i.id = t.inquiry_id;
  v_due := to_char(d.evidence_due at time zone 'Asia/Dubai', 'DD/MM/YYYY HH24:MI');
  select c2.email, c2.locale into c from public.customers c2 where c2.id = t.customer_id;
  select coalesce(l.claimed_by, l.email) as email, l.locale into s from public.leads l where l.id = t.supplier_id;
  perform public.fn_customer_support_duty_send('dispute.opened', d.id || ':' || role, role, email,
      case when locale = 'ar' then 'ar' else 'en' end,
      case when locale = 'ar' then 'فُتحت القضية ' || v_ref || ' بشأن مشروعكم على QuotesDone'
           else 'Dispute ' || v_ref || ' opened on your QuotesDone job' end,
      case when locale = 'ar' then
        'السادة المحترمين،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'فُتحت القضية ' || v_ref || ' بشأن المشروع المرتبط بالطلب رقم ' || coalesce(v_rfq, '') || '، ولن يُتخذ أي قرار قبل الاستماع إلى الطرفين. '
        || 'نرجو الرد على هذه الرسالة بروايتكم لما حدث، مع ما يدعمها من مستندات أو صور أو مراسلات، في موعد أقصاه ' || v_due || ' بتوقيت دبي. '
        || 'وإن لم يصلنا شيء حتى ذلك الموعد، فستُراجَع القضية بناءً على ما لدينا.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Hello,' || chr(10) || chr(10)
        || 'Dispute ' || v_ref || ' has been opened about the job for request ' || coalesce(v_rfq, '') || '. Nothing will be decided before both sides are heard. '
        || 'Please reply to this e-mail with your account of what happened and any documents, photos or messages that support it by ' || v_due || ' Dubai time. '
        || 'If nothing arrives by then, the case is reviewed on what we already have.' end,
      case when role = 'customer' then t.customer_id end, case when role = 'supplier' then t.supplier_id end, t.inquiry_id)
    from (values ('customer', c.email, c.locale), ('supplier', s.email, s.locale)) p(role, email, locale);
  return jsonb_build_object('dispute_id', d.id, 'opened', true, 'evidence_due', d.evidence_due);
end $fn$;
revoke execute on function public.fn_customer_support_dispute_open(uuid, text, text, bigint) from public, anon, authenticated;
grant execute on function public.fn_customer_support_dispute_open(uuid, text, text, bigint) to service_role;

create or replace function public.fn_reason_apply_customer_support__dispute_intake(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare h public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice';
begin
  select * into h from public.reasoning_held_question where id = p_id;
  if v_choice is null or v_choice not in ('dispute', 'not_dispute') then
    -- fn_reason_held_resolve marks a row applied whenever its apply returns, so a non-answer RAISES and is reasoned again.
    raise exception 'CHOICE_NOT_AN_OPTION: % (held question %)', coalesce(v_choice, 'no choice'), p_id;
  end if;
  if v_choice = 'not_dispute' then return jsonb_build_object('applied', true, 'opened', false); end if;
  return public.fn_customer_support_dispute_open((h.subject->>'transaction_id')::uuid, h.subject->>'party',
                                                 h.subject->>'statement', p_id);
end $fn$;
revoke execute on function public.fn_reason_apply_customer_support__dispute_intake(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_customer_support__dispute_intake(bigint, jsonb) to service_role;

-- Support records what a party sent in (by e-mail or chat) against the open case.
create or replace function public.fn_customer_support_dispute_evidence(p_id bigint, p_party text, p_evidence jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if p_party not in ('customer', 'supplier') then raise exception 'the party is the customer or the supplier, not %', p_party; end if;
  update public.post_reveal_dispute
     set customer_evidence = case when p_party = 'customer' then coalesce(customer_evidence, '{}'::jsonb) || jsonb_build_object('reply', p_evidence, 'at', now()) else customer_evidence end,
         supplier_evidence = case when p_party = 'supplier' then coalesce(supplier_evidence, '{}'::jsonb) || jsonb_build_object('reply', p_evidence, 'at', now()) else supplier_evidence end
   where id = p_id and stage = 'evidence';
  if not found then raise exception 'dispute % is not taking evidence', p_id; end if;
  return jsonb_build_object('dispute_id', p_id, 'recorded', p_party);
end $fn$;
revoke execute on function public.fn_customer_support_dispute_evidence(bigint, text, jsonb) from public, anon, authenticated;
grant execute on function public.fn_customer_support_dispute_evidence(bigint, text, jsonb) to service_role;

-- The clock: evidence closes when both parties answered or the date passed, then fault is reasoned;
-- a CEO decision past its date is a finding the CEO owns.
create or replace function public.fn_customer_support_disputes_tick()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on'; d record; v_q bigint;
  v_review int := 0; v_overdue int := 0;
begin
  for d in select p.*, (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) as demo
             from public.post_reveal_dispute p left join public.customers c on c.id = p.customer_id
            where p.stage = 'evidence'
              and ((p.customer_evidence is not null and p.supplier_evidence is not null) or now() > p.evidence_due)
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
            order by p.id for update of p skip locked loop
    v_q := public.fn_seat_duty_reason('customer_support', 'customer_support.dispute_fault',
      case when d.demo then 'ZZ DEMO ' else '' end
      || 'A customer and a supplier disagree about a job after the supplier''s details were revealed. On the statements and evidence of both parties, which finding does the evidence support?',
      jsonb_build_array(
        jsonb_build_object('id', 'customer_upheld', 'meaning', 'the customer''s complaint is supported: the supplier fell short of what was agreed'),
        jsonb_build_object('id', 'supplier_upheld', 'meaning', 'the supplier''s position is supported: the supplier did what was agreed'),
        jsonb_build_object('id', 'shared', 'meaning', 'both parties contributed to the problem'),
        jsonb_build_object('id', 'no_fault', 'meaning', 'the evidence shows no fault by either party, or is too thin to find one')),
      jsonb_build_object('raised_by', d.raised_by, 'opened_at', d.opened_at, 'evidence_due', d.evidence_due,
                         'customer', d.customer_evidence, 'supplier', d.supplier_evidence),
      jsonb_build_object('dispute_id', d.id), 'dispute_fault:' || d.id);
    update public.post_reveal_dispute set stage = 'review', fault_question_id = v_q where id = d.id;
    v_review := v_review + 1;
  end loop;

  for d in select p.id, p.decision_due, p.finding from public.post_reveal_dispute p
             left join public.customers c on c.id = p.customer_id
            where p.stage = 'ceo_decision' and now() > p.decision_due
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx loop
    perform public.fn_it_engineer_finding_upsert('dispute_decision_overdue:' || d.id,
      'Post-reveal dispute QD-D-' || lpad(d.id::text, 5, '0') || ' is past its decision date',
      'public.post_reveal_dispute / fn_ceo_decides_post_reveal_dispute', 'agent_facing', 1,
      jsonb_build_object('dispute_id', d.id, 'decision_due', d.decision_due, 'owner_seat', 'ceo'),
      '{}'::text[], array['the CEO''s decision: select public.fn_ceo_decides_post_reveal_dispute(<id>, <outcome>, <note>)'],
      'customer_support');
    v_overdue := v_overdue + 1;
  end loop;
  return jsonb_build_object('to_review', v_review, 'decision_overdue', v_overdue);
end $fn$;
revoke execute on function public.fn_customer_support_disputes_tick() from public, anon, authenticated;
grant execute on function public.fn_customer_support_disputes_tick() to service_role;

-- Support's reasoned finding goes to the CEO, reviewed by a model of another family.
create or replace function public.fn_reason_apply_customer_support__dispute_fault(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare h public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; d public.post_reveal_dispute; v_rev jsonb;
begin
  select * into h from public.reasoning_held_question where id = p_id;
  if v_choice is null or v_choice not in ('customer_upheld', 'supplier_upheld', 'shared', 'no_fault') then
    -- fn_reason_held_resolve marks a row applied whenever its apply returns, so a non-answer RAISES and is reasoned again.
    raise exception 'CHOICE_NOT_AN_OPTION: % (held question %)', coalesce(v_choice, 'no choice'), p_id;
  end if;
  select * into d from public.post_reveal_dispute where id = (h.subject->>'dispute_id')::bigint and stage = 'review' for update;
  if not found then return jsonb_build_object('applied', false, 'reason', 'the dispute is not awaiting a finding'); end if;
  update public.post_reveal_dispute
     set stage = 'ceo_decision', finding = v_choice, finding_reasoning = left(p_result->>'answer', 8000),
         finding_model = p_result->>'model', decision_due = public.fn_add_working_days(now(), 3)
   where id = d.id;
  -- the question and evidence are abstract and factual; the finding travels only in the proposal
  v_rev := public.fn_seat_duty_cross_review('post_reveal_dispute', 'customer_support', 'ceo',
    case when h.question like 'ZZ DEMO%' then 'ZZ DEMO ' else '' end
      || 'Review a finding on a post-reveal dispute between a customer and a supplier.',
    jsonb_build_object('dispute_id', d.id, 'raised_by', d.raised_by, 'customer', d.customer_evidence, 'supplier', d.supplier_evidence),
    jsonb_build_object('finding', v_choice), p_result, 'post_reveal_dispute', d.id::text);
  update public.post_reveal_dispute set review = v_rev where id = d.id;
  return jsonb_build_object('applied', true, 'dispute_id', d.id, 'finding', v_choice, 'review', v_rev);
end $fn$;
revoke execute on function public.fn_reason_apply_customer_support__dispute_fault(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_customer_support__dispute_fault(bigint, jsonb) to service_role;

-- The CEO decides; both parties are told in their language.
create or replace function public.fn_ceo_decides_post_reveal_dispute(p_id bigint, p_outcome text, p_note text)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare d public.post_reveal_dispute; c record; s record; v_ref text; v_en text; v_ar text;
begin
  if p_outcome is null or p_outcome not in ('customer_upheld', 'supplier_upheld', 'shared', 'no_fault') then
    raise exception 'the outcome is customer_upheld, supplier_upheld, shared or no_fault, not %', p_outcome;
  end if;
  update public.post_reveal_dispute set stage = 'decided', outcome = p_outcome, outcome_note = p_note,
         decided_by = 'ceo', decided_at = now()
   where id = p_id and stage in ('review', 'ceo_decision') returning * into d;
  if not found then raise exception 'dispute % is not awaiting a decision', p_id; end if;
  update public.it_engineer_finding set closed_at = now(), close_note = 'the CEO decided the dispute'
   where issue_key = 'dispute_decision_overdue:' || p_id and closed_at is null;
  v_ref := 'QD-D-' || lpad(d.id::text, 5, '0');
  v_en := case p_outcome when 'customer_upheld' then 'the customer''s complaint is upheld'
    when 'supplier_upheld' then 'the supplier''s position is upheld' when 'shared' then 'responsibility is shared by both parties'
    else 'no fault was found on either side' end;
  v_ar := case p_outcome when 'customer_upheld' then 'قُبلت شكوى العميل'
    when 'supplier_upheld' then 'ثبت موقف المورّد' when 'shared' then 'المسؤولية مشتركة بين الطرفين'
    else 'لم يثبت تقصير على أي من الطرفين' end;
  select c2.email, c2.locale into c from public.customers c2 where c2.id = d.customer_id;
  select coalesce(l.claimed_by, l.email) as email, l.locale into s from public.leads l where l.id = d.supplier_id;
  perform public.fn_customer_support_duty_send('dispute.decided', d.id || ':' || role, role, email,
      case when locale = 'ar' then 'ar' else 'en' end,
      case when locale = 'ar' then 'القرار في القضية ' || v_ref else 'Dispute ' || v_ref || ': the decision' end,
      case when locale = 'ar' then
        'السادة المحترمين،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'راجعنا القضية ' || v_ref || ' بعد الاطلاع على أقوال الطرفين ومستنداتهما، وانتهت المراجعة إلى أنه ' || v_ar || '. '
        || 'وإن كان لديكم اعتراض على القرار، فيسعدنا أن تردّوا على هذه الرسالة خلال عشرة أيام عمل.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Hello,' || chr(10) || chr(10)
        || 'We have reviewed dispute ' || v_ref || ' on the statements and evidence of both parties. The outcome: ' || v_en || '. '
        || 'If you disagree with the decision, reply to this e-mail within 10 working days.' end,
      case when role = 'customer' then d.customer_id end, case when role = 'supplier' then d.supplier_id end, d.inquiry_id)
    from (values ('customer', c.email, c.locale), ('supplier', s.email, s.locale)) p(role, email, locale);
  return jsonb_build_object('dispute_id', d.id, 'outcome', p_outcome);
end $fn$;
revoke execute on function public.fn_ceo_decides_post_reveal_dispute(bigint, text, text) from public, anon, authenticated;
grant execute on function public.fn_ceo_decides_post_reveal_dispute(bigint, text, text) to service_role;

-- ── the clocks and the cross-family review pair ──────────────────────────────────────────────────
insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('customer_support.activation', 'customer_support', interval '6 hours', 'fn_customer_support_activation_tick',
   'a customer with no request after 3 days, a request with no quote after 5, and a reasoned message after 10',
   'scripts/sql/customer_support_activates_wins_back_and_settles_disputes.sql'),
  ('customer_support.winback', 'customer_support', interval '1 day', 'fn_customer_support_winback_tick',
   'one win-back message to a customer dormant 60 to 90 days after a revealed job',
   'scripts/sql/customer_support_activates_wins_back_and_settles_disputes.sql'),
  ('customer_support.disputes', 'customer_support', interval '30 minutes', 'fn_customer_support_disputes_tick',
   'post-reveal disputes: close evidence on time, reason the finding, flag an overdue CEO decision',
   'scripts/sql/customer_support_activates_wins_back_and_settles_disputes.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, owner_file)
values ('deliberation.review', 'customer_support', 'ceo',
        'the CEO reviews customer support''s reasoned finding on a post-reveal dispute on a model of another family',
        'fn_seat_deliberation_acts_on_handoff', interval '2 days',
        'scripts/sql/customer_support_activates_wins_back_and_settles_disputes.sql')
on conflict do nothing;
