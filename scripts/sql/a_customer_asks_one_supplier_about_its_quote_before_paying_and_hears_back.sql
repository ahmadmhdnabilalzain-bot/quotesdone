-- A CUSTOMER ASKS ONE SUPPLIER ABOUT ITS QUOTE BEFORE PAYING, AND HEARS BACK: FROM THE QUOTE ITSELF WHEN IT ALREADY SAYS, ELSE
-- FROM THE SUPPLIER BY A DATE, ANONYMOUS BOTH WAYS.
-- Seat: sales_engineer. Agent: CUSTOMER_W2 (wave 2 of the real-company hole hunt, 16 Nov 2026; scratchpad holes/CUSTOMER.md item 6).
--
-- MEASURED on origin/main 27969740b: the pre-reveal Q&A (messages_api clarify_*) lets a SUPPLIER ask (clarify_ask) and the
-- customer only answer or broadcast a note to every supplier. "Does Supplier B's price include scaffolding? Can he start
-- Sunday?" could be asked only by paying the reveal fee first. sales_engineer, site_assistant and wa_inbound held 0 references
-- to rfq_clarification, so no colleague could relay such a question.
--
-- WHAT THIS CHANGES (the same table, rfq_clarification, so a supplier reads one list and the customer one thread per quote)
--   1. rfq_clarification gains asked_by ('supplier' as before, or 'customer'), quote_id, question_as_written (his own words),
--      answered_by ('customer', 'supplier' or 'sales_engineer'), relayed_at, reply_by, overdue_told_at and held_id. A customer
--      question is kind 'question' with the quoted supplier's id, so the shape check holds unchanged; its `question` is the
--      supplier copy (customer_api writes it through the supplier gate; the relay replaces it with the sales engineer's English).
--   2. THE SALES ENGINEER ANSWERS FROM THE QUOTE FIRST. fn_sales_engineer_customer_question_file files one reasoning question,
--      sales_engineer.customer_question, with the quote's own words as the customer may read them (fn_quote_text_for_customer:
--      the supplier's name, its own brand and model, e-mails, links and phone-length digit runs removed). The model decides
--      'answered_from_quote' (and writes the answer in the customer's language from those words only) or 'relay_to_supplier'
--      (and writes the question in English for the supplier, naming nobody). Code checks only that the choice is an option and
--      the texts are not empty, and passes both through the identity rules on the way out.
--   3. A RELAYED QUESTION HAS A DATE. reply_by = relay + decision_policy customer_question_reply_hours (24). The supplier is
--      written in English through customer_support's door; he answers in his portal (messages_api clarify_reply) and the
--      customer is told. The duty sales_engineer.customer_questions (hourly) tells the customer, in his language, when a
--      supplier has not answered by the date and reminds the supplier once, and hands a question the model could not read
--      (failed or expired reasoning) to the sales engineer's queue.
--   4. THE ANSWER REACHES THE CUSTOMER'S FACTS. fn_customer_quote_thread gives, per quote, who asked, who answered, the answer
--      and the date it is due by; fn_customer_inquiry_facts reads it (its body from production, md5
--      344f79a38ec9869386a8561df4067b4e, equal to main's canonical body, with three changes: the thread, the request's revision
--      and each quote's priced revision, and the list of revisions). Every channel that reads the facts (WhatsApp, the widget, the
--      portal chat, e-mail) now knows "you asked B about scaffolding; the sales engineer answered from B's quote: included".
-- Anonymity (ruling 1683): the supplier never receives the customer's name, contacts or site (fn_scrub_customer_identity and,
-- in customer_api, the supplier gate); the customer never receives the supplier's name, brand, phone or site before the reveal.
-- Every new routine: SECURITY DEFINER, search_path pinned, EXECUTE revoked from public, anon and authenticated.
-- Needs a_change_to_a_sent_request_is_a_revision_every_quote_names_and_every_supplier_is_told.sql applied first (the facts
-- read inquiries.revision, quotes.priced_revision and inquiry_revision).
-- Probe: a_customer_asks_one_supplier_about_its_quote_before_paying_and_hears_back_probe.sql (local Postgres 16).
-- Deploy order: apply this file, then deploy messages_api and customer_api.

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. THE SAME TABLE, ONE MORE DIRECTION
alter table public.rfq_clarification
  add column if not exists asked_by text not null default 'supplier',
  add column if not exists quote_id uuid,
  add column if not exists question_as_written text,
  add column if not exists answered_by text,
  add column if not exists relayed_at timestamptz,
  add column if not exists reply_by timestamptz,
  add column if not exists overdue_told_at timestamptz,
  add column if not exists held_id bigint;
alter table public.rfq_clarification drop constraint if exists rfq_clarification_asked_by_ck;
alter table public.rfq_clarification add constraint rfq_clarification_asked_by_ck check (asked_by in ('supplier', 'customer'));
alter table public.rfq_clarification drop constraint if exists rfq_clarification_answered_by_ck;
alter table public.rfq_clarification add constraint rfq_clarification_answered_by_ck check (answered_by is null or answered_by in ('customer', 'supplier', 'sales_engineer'));
alter table public.rfq_clarification drop constraint if exists rfq_clarification_customer_question_ck;
alter table public.rfq_clarification add constraint rfq_clarification_customer_question_ck
  check (asked_by <> 'customer' or (kind = 'question' and quote_id is not null and question_as_written is not null));
create index if not exists rfq_clarification_customer_open_idx on public.rfq_clarification (reply_by)
  where asked_by = 'customer' and answered_at is null;
comment on column public.rfq_clarification.asked_by is
  'Who asked: supplier (a question to the customer, answered to every matched supplier) or customer (a question about ONE supplier''s quote, answered only to him). Sales engineer, 16 Nov 2026.';

insert into public.decision_policy (key, value, description) values
  ('customer_question_reply_hours', '24'::jsonb, 'Hours a supplier has to answer a customer''s question about its quote once the sales engineer relays it (rfq_clarification.reply_by). Sales engineer, 16 Nov 2026.')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. A QUOTE'S WORDS AS THE CUSTOMER MAY READ THEM BEFORE THE REVEAL, AT ANY LENGTH. The rules are those of
-- fn_quote_words_for_customer (a_customer_is_answered_from_his_whole_request_on_every_channel.sql), which cuts at 160 characters
-- for the short fields; a scope, a note or an answer is longer.
create or replace function public.fn_quote_text_for_customer(p_text text, p_quote uuid, p_max integer default 1200)
returns text language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v text := left(btrim(coalesce(p_text, '')), greatest(coalesce(p_max, 1200), 1) + 200); v_name text; r record;
begin
  if v = '' then return null; end if;
  select nullif(btrim(l.company_name), '') into v_name from public.quotes q join public.leads l on l.id = q.supplier_id where q.id = p_quote;
  if v_name is not null and length(v_name) >= 3 then
    v := regexp_replace(v, regexp_replace(v_name, '([.^$*+?()\[\]{}|\\])', '\\\1', 'g'), 'the supplier', 'gi');
  end if;
  for r in
    select distinct x.val, x.kind from public.quote_items qi
      cross join lateral (values (btrim(qi.brand), 'brand'), (btrim(qi.model), 'model')) x(val, kind)
     where qi.quote_id = p_quote::text and length(coalesce(x.val, '')) >= 2
  loop
    v := regexp_replace(v, '\m' || regexp_replace(r.val, '([.^$*+?()\[\]{}|\\])', '\\\1', 'g') || '\M',
                        case r.kind when 'brand' then 'a brand (shown after reveal)' else 'model stated (shown after reveal)' end, 'gi');
  end loop;
  v := regexp_replace(v, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[removed]', 'g');
  v := regexp_replace(v, '(https?://|www\.)\S+', '[removed]', 'gi');
  v := regexp_replace(v, '\+?[0-9](?:[ ()-]?[0-9]){8,}', '[removed]', 'g');
  return left(v, greatest(coalesce(p_max, 1200), 1));
end $fn$;
revoke execute on function public.fn_quote_text_for_customer(text, uuid, integer) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. THE SALES ENGINEER READS THE QUESTION AGAINST THE QUOTE
create or replace function public.fn_sales_engineer_customer_question_file(p_id bigint)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.rfq_clarification; q public.quotes; i public.inquiries; v_lang text; v_letter text; v_items text; v_q text;
        v_subject jsonb; v_held bigint;
begin
  select * into r from public.rfq_clarification where id = p_id for update;
  if not found or r.asked_by <> 'customer' or r.answered_at is not null or r.relayed_at is not null then return null; end if;
  select * into q from public.quotes where id = r.quote_id;
  select * into i from public.inquiries where id = r.inquiry_id;
  if q.id is null or i.id is null then return null; end if;
  select case when coalesce(i.lang, c.locale) = 'ar' then 'ar' else 'en' end into v_lang from public.customers c where c.id = i.customer_id;
  select lt.letter into v_letter from public.fn_customer_quote_letters(i.id) lt where lt.quote_id = q.id;
  select string_agg('- ' || coalesce(public.fn_quote_text_for_customer(concat_ws(', ', qi.description, qi.specification), q.id, 300), '')
                    || coalesce(' | qty ' || qi.qty::text, '') || coalesce(' ' || qi.unit, ''), chr(10) order by qi.line_no)
    into v_items from (select * from public.quote_items x where x.quote_id = q.id::text order by x.line_no limit 30) qi;
  v_q := 'A customer comparing quotes asks about ONE supplier''s quote (Supplier ' || coalesce(v_letter, '?') || ') before deciding whether '
      || 'to pay to reveal it. You are the sales engineer. If the quote''s own words below already answer the question, answer him from '
      || 'them only, in ' || case when v_lang = 'ar' then 'Gulf business Arabic' else 'plain UAE English' end || ', quoting what the quote says; '
      || 'never guess, never name the supplier, a brand, a phone, a website or an address. If the quote does not answer it, the supplier '
      || 'must: write the question in clear English for the supplier, naming no person, phone, e-mail, villa, building or company.'
      || chr(10) || chr(10) || 'THE QUOTE (as the customer may read it before the reveal):' || chr(10)
      || 'Price: AED ' || coalesce(to_char(coalesce(nullif(q.quote_amount, 0), q.price_ex_vat), 'FM999,999,990.00'), 'not stated')
      || coalesce(' (VAT: ' || q.vat_treatment || ')', '') || chr(10)
      || 'Scope: ' || coalesce(public.fn_quote_text_for_customer(q.scope, q.id, 1200), 'not stated') || chr(10)
      || 'Exclusions: ' || coalesce(public.fn_quote_text_for_customer(q.exclusions, q.id, 800), 'not stated') || chr(10)
      || 'Conditions: ' || coalesce(public.fn_quote_text_for_customer(q.conditions, q.id, 800), 'not stated') || chr(10)
      || 'Notes: ' || coalesce(public.fn_quote_text_for_customer(q.notes, q.id, 800), 'not stated') || chr(10)
      || 'Lead time: ' || coalesce(public.fn_quote_text_for_customer(q.lead_time, q.id, 200), 'not stated') || chr(10)
      || 'Validity: ' || coalesce(public.fn_quote_text_for_customer(q.validity, q.id, 200), 'not stated') || chr(10)
      || 'Payment terms: ' || coalesce(public.fn_quote_text_for_customer(q.payment_terms, q.id, 300), 'not stated') || chr(10)
      || 'Warranty: ' || coalesce(public.fn_quote_text_for_customer(q.warranty, q.id, 300), 'not stated') || chr(10)
      || 'Lines:' || chr(10) || coalesce(v_items, '(none itemised)') || chr(10) || chr(10)
      || 'HIS QUESTION:' || chr(10) || left(coalesce(r.question_as_written, r.question), 1500);
  v_subject := jsonb_build_object('inquiry_id', i.id, 'quote_id', q.id, 'clarification_id', r.id, 'customer_id', i.customer_id)
            || case when exists (select 1 from public.customers c where c.id = i.customer_id and c.is_demo) then '{"fixture": true}'::jsonb else '{}'::jsonb end;
  v_held := public.fn_reason_hold('sales_engineer', 'sales_engineer.customer_question', left(v_q, 8000),
    jsonb_build_object('seat', 'sales_engineer', 'surface', 'sales_engineer.customer_question', 'question', v_q, 'research', false,
      'context', jsonb_build_object('audience', 'internal', 'language', 'en'),
      'decision', jsonb_build_object('name', 'customer_question', 'authored', true,
        'options', jsonb_build_array(
          jsonb_build_object('id', 'answered_from_quote', 'meaning', 'The quote''s own words answer the question; the answer is written for the customer.'),
          jsonb_build_object('id', 'relay_to_supplier', 'meaning', 'The quote does not answer it; only the supplier can, so it is relayed to him.')),
        'fields', jsonb_build_array(
          jsonb_build_object('key', 'answer', 'question', 'For answered_from_quote: the answer to the customer, in his language, from the quote''s words only.'),
          jsonb_build_object('key', 'question_en', 'question', 'For relay_to_supplier: the question in clear English for the supplier, naming nobody.'))),
      'subject', v_subject, 'dedupeKey', 'customer_question:' || r.id),
    '{}'::jsonb, v_subject, 'a_customer_question_about_one_quote', 'customer_question:' || r.id);
  update public.rfq_clarification set held_id = v_held where id = r.id;
  return v_held;
end $fn$;
revoke execute on function public.fn_sales_engineer_customer_question_file(bigint) from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_customer_question_file(bigint) to service_role;

-- The answer reaches the customer in his language: by the letter his portal knows the quote by, never the supplier's name.
create or replace function public.fn_customer_question_answered_tell(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.rfq_clarification; i public.inquiries; c public.customers; v_ar boolean; v_letter text; v_by text; v_d jsonb;
begin
  select * into r from public.rfq_clarification where id = p_id;
  if not found or r.asked_by <> 'customer' or r.answered_at is null then return null; end if;
  select * into i from public.inquiries where id = r.inquiry_id;
  select * into c from public.customers where id = i.customer_id;
  if c.email is null or position('@' in c.email) < 2 then return jsonb_build_object('told', false, 'why', 'no e-mail'); end if;
  v_ar := coalesce(i.lang, c.locale) = 'ar';
  select lt.letter into v_letter from public.fn_customer_quote_letters(i.id) lt where lt.quote_id = r.quote_id;
  v_by := case r.answered_by when 'sales_engineer' then case when v_ar then 'أجاب مهندس المبيعات من عرض المورّد نفسه' else 'Your sales engineer answered from the quote itself' end
               else case when v_ar then 'أجاب المورّد' else 'The supplier answered' end end;
  v_d := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
    'type', 'clarification_requested', 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', c.email, 'to_role', 'customer',
    'inquiry_id', i.id, 'quote_id', r.quote_id, 'lang', case when v_ar then 'ar' else 'en' end,
    'subject', case when v_ar then 'جواب سؤالكم عن عرض المورّد ' || coalesce(v_letter, '') else 'The answer to your question about Supplier ' || coalesce(v_letter, '') || '''s quote' end,
    'body', case when v_ar
      then 'سألتم عن عرض المورّد ' || coalesce(v_letter, '') || ' على طلبكم رقم ' || coalesce(i.rfq_no::text, '') || ':' || chr(10) || '«' || left(coalesce(r.question_as_written, r.question), 600) || '»'
           || chr(10) || chr(10) || v_by || ':' || chr(10) || '«' || left(r.answer, 1500) || '»' || chr(10) || chr(10)
           || 'تجدون السؤال وجوابه تحت العرض على طلبكم في QuotesDone.'
      else 'You asked about Supplier ' || coalesce(v_letter, '') || '''s quote on your request ' || coalesce(i.rfq_no::text, '') || ':' || chr(10) || '"' || left(coalesce(r.question_as_written, r.question), 600) || '"'
           || chr(10) || chr(10) || v_by || ':' || chr(10) || '"' || left(r.answer, 1500) || '"' || chr(10) || chr(10)
           || 'The question and its answer are under that quote on your request in QuotesDone.' end,
    'dedupe_key', 'customer_question_answered:' || r.id)));
  return jsonb_build_object('told', coalesce(v_d->0->>'status', '') in ('done', 'demo_captured', 'pending', 'needs_review'), 'delivery', v_d);
end $fn$;
revoke execute on function public.fn_customer_question_answered_tell(bigint) from public, anon, authenticated;
grant execute on function public.fn_customer_question_answered_tell(bigint) to service_role;

-- A relay: the supplier copy in English, a date to answer by, the supplier written through customer_support's door.
create or replace function public.fn_customer_question_relay(p_id bigint, p_question_en text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.rfq_clarification; i public.inquiries; q public.quotes; l public.leads; v_text text; v_hours int; v_by timestamptz; v_d jsonb;
begin
  select * into r from public.rfq_clarification where id = p_id for update;
  if not found or r.asked_by <> 'customer' or r.answered_at is not null then return jsonb_build_object('relayed', false, 'why', 'not an open customer question'); end if;
  if r.relayed_at is not null then return jsonb_build_object('relayed', true, 'already', true); end if;
  select * into i from public.inquiries where id = r.inquiry_id;
  select * into q from public.quotes where id = r.quote_id;
  select * into l from public.leads where id = r.supplier_id;
  v_text := public.fn_scrub_customer_identity(left(btrim(coalesce(p_question_en, '')), 1500), i.customer_id);
  -- never the held placeholder customer_api stores when his words could not be proved clean for a supplier, never Arabic
  if length(btrim(regexp_replace(coalesce(v_text, ''), '\[(removed|hidden)\]', '', 'g'))) < 3 or v_text ~ '[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻾]'
     or v_text like 'A question from the customer, held for the sales engineer%' then
    return jsonb_build_object('relayed', false, 'why', 'no English supplier copy');
  end if;
  v_hours := public.fn_seat_clock_policy('customer_question_reply_hours', 24)::int;
  v_by := now() + make_interval(hours => v_hours);
  update public.rfq_clarification set question = v_text, relayed_at = now(), reply_by = v_by where id = r.id;
  if coalesce(nullif(btrim(l.claimed_by), ''), l.email, '') like '%@%' and not coalesce(l.banned, false) then
    v_d := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'clarification_requested', 'requested_by', 'sales_engineer', 'channel', 'email',
      'to_email', coalesce(nullif(btrim(l.claimed_by), ''), l.email), 'to_role', 'supplier', 'lead_id', l.id,
      'inquiry_id', i.id, 'quote_id', q.id, 'lang', 'en',
      'subject', 'A customer has a question about your quote on request ' || coalesce(i.rfq_no::text, ''),
      'body', 'Hello ' || coalesce(l.company_name, '') || ',' || chr(10) || chr(10)
        || 'A customer comparing quotes on the ' || coalesce(i.category, '') || coalesce(' job in ' || nullif(i.emirate, ''), ' job')
        || ' (request ' || coalesce(i.rfq_no::text, '') || ') asks about YOUR quote of AED '
        || coalesce(to_char(coalesce(nullif(q.quote_amount, 0), q.price_ex_vat), 'FM999,999,990'), '') || ':' || chr(10) || chr(10)
        || '"' || v_text || '"' || chr(10) || chr(10)
        || 'Please answer by ' || to_char(v_by at time zone 'Asia/Dubai', 'Dy DD Mon, HH24:MI') || ' (UAE time) in your QuotesDone supplier portal, '
        || 'on the request''s questions. Your answer goes to this customer only, without your company name or contact details, '
        || 'and helps him decide whether to choose your quote.' || chr(10) || chr(10) || 'QuotesDone',
      'dedupe_key', 'customer_question_relay:' || r.id)));
  end if;
  return jsonb_build_object('relayed', true, 'reply_by', v_by, 'delivery', v_d);
end $fn$;
revoke execute on function public.fn_customer_question_relay(bigint, text) from public, anon, authenticated;
grant execute on function public.fn_customer_question_relay(bigint, text) to service_role;

create or replace function public.fn_reason_apply_sales_engineer__customer_question(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare h public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; f jsonb := coalesce(p_result->'decision'->'fields', '{}'::jsonb);
        r public.rfq_clarification; v_ans text; v_res jsonb;
begin
  select * into h from public.reasoning_held_question where id = p_id;
  if not found then raise exception 'no held question %', p_id using errcode = 'P0002'; end if;
  if v_choice is null or v_choice not in ('answered_from_quote', 'relay_to_supplier') then
    raise exception 'CHOICE_NOT_AN_OPTION: % (held question %)', coalesce(v_choice, 'no choice'), p_id;
  end if;
  select * into r from public.rfq_clarification where id::text = h.subject->>'clarification_id' for update;
  if not found or r.answered_at is not null then return jsonb_build_object('applied', true, 'changed', false, 'why', 'already answered or gone'); end if;
  if v_choice = 'answered_from_quote' then
    -- what reaches him before the reveal names no supplier, brand, phone or site (the same rules as his facts)
    v_ans := public.fn_quote_text_for_customer(f->'answer'->>'value', r.quote_id, 1500);
    if v_ans is not null and length(btrim(v_ans)) >= 2 then
      update public.rfq_clarification set answer = v_ans, answer_as_written = v_ans, answered_at = now(), answered_by = 'sales_engineer'
       where id = r.id;
      return jsonb_build_object('applied', true, 'answered', true, 'by', 'sales_engineer', 'told', public.fn_customer_question_answered_tell(r.id));
    end if;
    -- an empty answer is no answer: the supplier is asked instead (the question's own supplier copy)
  end if;
  v_res := public.fn_customer_question_relay(r.id, coalesce(nullif(btrim(coalesce(f->'question_en'->>'value', '')), ''), r.question));
  if not coalesce((v_res->>'relayed')::boolean, false) then
    insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
    values ('sales_engineer', 'customer_question_waiting', 'needs_review', 'medium',
            'A customer''s question about one quote could not be relayed in English',
            'Write the supplier copy in English and relay it (fn_customer_question_relay), or answer it from the quote.',
            jsonb_build_object('clarification_id', r.id, 'inquiry_id', r.inquiry_id, 'quote_id', r.quote_id, 'why', v_res->>'why'),
            'rfq_clarification', r.id::text);
  end if;
  return jsonb_build_object('applied', true, 'answered', false, 'relay', v_res);
end $fn$;
revoke execute on function public.fn_reason_apply_sales_engineer__customer_question(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_sales_engineer__customer_question(bigint, jsonb) to service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. THE DATE IS KEPT: an unanswered relay is said to the customer and reminded to the supplier once; an unread question is relayed
create or replace function public.fn_sales_engineer_customer_questions(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  x record; n_over int := 0; n_hand int := 0; v_d jsonb; v_ar boolean;
begin
  for x in
    select r.*, i.rfq_no, i.lang ilang, c.email cemail, c.locale clocale, lt.letter,
           coalesce(nullif(btrim(l.claimed_by), ''), l.email) semail, l.company_name
      from public.rfq_clarification r
      join public.inquiries i on i.id = r.inquiry_id join public.customers c on c.id = i.customer_id
      join public.leads l on l.id = r.supplier_id
      left join lateral (select f.letter from public.fn_customer_quote_letters(i.id) f where f.quote_id = r.quote_id) lt on true
     where r.asked_by = 'customer' and r.answered_at is null and r.relayed_at is not null and r.reply_by <= p_at and r.overdue_told_at is null
       and coalesce(c.is_demo, false) = v_fx
     order by r.reply_by limit 100
  loop
    v_ar := coalesce(x.ilang, x.clocale) = 'ar';
    if x.cemail like '%@%' then
      v_d := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
        'type', 'clarification_requested', 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', x.cemail, 'to_role', 'customer',
        'inquiry_id', x.inquiry_id, 'quote_id', x.quote_id, 'lang', case when v_ar then 'ar' else 'en' end,
        'subject', case when v_ar then 'لم يجب المورّد ' || coalesce(x.letter, '') || ' عن سؤالكم بعد' else 'Supplier ' || coalesce(x.letter, '') || ' has not answered your question yet' end,
        'body', case when v_ar
          then 'لم يجب المورّد ' || coalesce(x.letter, '') || ' حتى الآن عن سؤالكم على طلبكم رقم ' || coalesce(x.rfq_no::text, '') || ':' || chr(10) || '«' || left(coalesce(x.question_as_written, x.question), 600) || '»' || chr(10) || chr(10)
               || 'ذكّرناه اليوم، وسنرسل إليكم الجواب فور وصوله. ويمكنكم في الأثناء المقارنة بين العروض الأخرى أو سؤال مورّد آخر عن عرضه.'
          else 'Supplier ' || coalesce(x.letter, '') || ' has not yet answered your question on request ' || coalesce(x.rfq_no::text, '') || ':' || chr(10) || '"' || left(coalesce(x.question_as_written, x.question), 600) || '"' || chr(10) || chr(10)
               || 'We have reminded them today and will send you the answer the moment it arrives. Meanwhile you can compare the other quotes or ask another supplier about theirs.' end,
        'dedupe_key', 'customer_question_overdue:' || x.id)));
    end if;
    if x.semail like '%@%' then
      perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
        'type', 'clarification_requested', 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', x.semail, 'to_role', 'supplier',
        'lead_id', x.supplier_id, 'inquiry_id', x.inquiry_id, 'quote_id', x.quote_id, 'lang', 'en',
        'subject', 'Reminder: a customer is waiting for your answer on request ' || coalesce(x.rfq_no::text, ''),
        'body', 'Hello ' || coalesce(x.company_name, '') || ',' || chr(10) || chr(10) || 'A customer asked about your quote on request ' || coalesce(x.rfq_no::text, '')
             || ' and is still waiting for your answer:' || chr(10) || chr(10) || '"' || x.question || '"' || chr(10) || chr(10)
             || 'Please answer it in your QuotesDone supplier portal, on the request''s questions. He is deciding which quote to choose.' || chr(10) || chr(10) || 'QuotesDone',
        'dedupe_key', 'customer_question_reminder:' || x.id)));
    end if;
    update public.rfq_clarification set overdue_told_at = now() where id = x.id;
    n_over := n_over + 1;
  end loop;

  -- A question the model could not read (its reasoning failed or expired, or none was filed) is not left unanswered: it goes to
  -- the sales engineer's queue, once, to answer from the quote or relay with an English supplier copy.
  for x in
    select r.id from public.rfq_clarification r
      join public.inquiries i on i.id = r.inquiry_id join public.customers c on c.id = i.customer_id
      left join public.reasoning_held_question h on h.id = r.held_id
     where r.asked_by = 'customer' and r.answered_at is null and r.relayed_at is null
       and r.asked_at <= p_at - interval '2 hours' and (h.id is null or h.status in ('failed', 'expired'))
       and coalesce(c.is_demo, false) = v_fx
     order by r.asked_at limit 50
  loop
    if not exists (select 1 from public.agent_actions a where a.kind = 'customer_question_waiting' and a.target_id = x.id::text) then
      insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
      values ('sales_engineer', 'customer_question_waiting', 'needs_review', 'medium',
              'A customer''s question about one quote was not read by the model',
              'Answer it from the quote, or write the supplier copy in English and relay it (fn_customer_question_relay).',
              jsonb_build_object('clarification_id', x.id, 'why', 'the reasoning failed, expired or was never filed'), 'rfq_clarification', x.id::text);
      n_hand := n_hand + 1;
    end if;
  end loop;
  return jsonb_build_object('overdue_told', n_over, 'handed_to_seat', n_hand, 'fixtures', v_fx);
end $fn$;
revoke execute on function public.fn_sales_engineer_customer_questions(timestamptz) from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('sales_engineer.customer_questions', 'sales_engineer', interval '1 hour', 'fn_sales_engineer_customer_questions',
   'A customer''s question about one supplier''s quote that the supplier has not answered by its date: the customer is told and the supplier reminded once; a question the model could not read is handed to the sales engineer.',
   'scripts/sql/a_customer_asks_one_supplier_about_its_quote_before_paying_and_hears_back.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. THE THREAD WITH ONE SUPPLIER, AS THE CUSTOMER'S FACTS CARRY IT
create or replace function public.fn_customer_quote_thread(p_inquiry uuid, p_supplier bigint)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'asked_at', c.asked_at,
           'asked_by', case c.asked_by when 'customer' then 'you (the customer), about this quote' else 'the supplier' end,
           'question', left(case when c.asked_by = 'customer' then coalesce(c.question_as_written, c.question) else c.question end, 400),
           'answered_by', case when c.answered_at is null then null
                               when c.answered_by = 'sales_engineer' then 'your sales engineer, from the quote itself'
                               when c.answered_by = 'supplier' or c.asked_by = 'customer' then 'the supplier'
                               else 'you (the customer)' end,
           'answer', left(coalesce(c.answer_as_written, c.answer), 400), 'answered_at', c.answered_at,
           'state', case when c.answered_at is not null then 'answered'
                         when c.asked_by = 'customer' and c.relayed_at is not null then 'asked of the supplier, answer due by ' || to_char(c.reply_by at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' UAE time'
                         when c.asked_by = 'customer' then 'with your sales engineer, who answers from the quote or asks the supplier'
                         else 'waiting for your answer' end)) order by c.asked_at)
    from (select * from public.rfq_clarification c0
           where c0.inquiry_id = p_inquiry and c0.kind = 'question' and c0.supplier_id = p_supplier
           order by c0.asked_at desc limit 8) c
$fn$;
revoke execute on function public.fn_customer_quote_thread(uuid, bigint) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. fn_customer_inquiry_facts: production's body with the thread, the revisions and each quote's priced revision
CREATE OR REPLACE FUNCTION public.fn_customer_inquiry_facts(p_customer uuid, p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with cfg as (
    select coalesce((select nullif(regexp_replace(coalesce(value, ''), '[^0-9.]', '', 'g'), '')::numeric
                       from public.app_secrets where key = 'sla_quote_hours'), 24) as sla_h,
           coalesce((select case when c.locale = 'ar' then 'ar' else 'en' end from public.customers c where c.id = p_customer), 'en') as lang,
           -- BEING CHECKED (wave C release, 16 Nov 2026; REVIEW_CASEFACTS item 7): the requests whose quotes his portal holds while a
           -- customer_matches_supplier flag is open on him (fn_customer_quotes_being_checked, every_flag_and_sanctions_hit_...sql,
           -- applied before this file). A held quote is never priced on any channel.
           coalesce(public.fn_customer_quotes_being_checked(p_customer) -> 'inquiry_ids', '[]'::jsonb) as chk),
  inq as (
    select i.*, row_number() over (order by i.created_at desc) as rn from public.inquiries i where i.customer_id = p_customer
     order by i.created_at desc limit greatest(coalesce(p_limit, 10), 1)),
  -- a LIVE quote, as fn_rfq_short_of_quotes_tick and the portal count it; a revealed quote is live
  q as (
    select q.id, q.inquiry_id, q.supplier_id, q.quote_amount, q.price_ex_vat, q.vat_treatment, q.vat_amount, q.amount_as_stated,
           q.gross_amount, q.discount_amount, q.expires_at, q.created_at, q.lead_time, q.warranty, q.validity, q.review_notes,
           q.option_no, q.priced_revision,
           -- REVIEW 16 Nov: the price base exactly as _shared/stated_price.ts feeBaseOf (the portal's figure): none while the
           -- VAT basis is unsettled (not stated, or VAT-inclusive with no ex-VAT figure), else quote_amount, else price_ex_vat
           case when coalesce(q.price_ex_vat, 0) <= 0 and q.vat_treatment in ('not_stated', 'inclusive') then null
                else coalesce(nullif(greatest(q.quote_amount, 0), 0), nullif(greatest(q.price_ex_vat, 0), 0)) end as fee_base,
           (select min(t.revealed_at) from public.transactions t where t.quote_id = q.id and t.revealed_at is not null) as revealed_at,
           -- founder instruction 516: a sanctioned party is never shown to a customer (customer_api refuses it too)
           exists (select 1 from public.sanctions_ban sb where sb.lead_id = q.supplier_id) as sanctioned
      from public.quotes q join inq on inq.id = q.inquiry_id
     where coalesce(q.status, '') not in ('draft', 'withdrawn', 'rejected', 'expired', 'held', 'cancelled') and q.stale_at is null
       -- 16 Nov: a sanctioned supplier's SEALED quote is not counted, listed or averaged, as the portal leaves it out
       -- (customer_api my_inquiries); one already revealed stays, unnamed
       and (not exists (select 1 from public.sanctions_ban sb where sb.lead_id = q.supplier_id)
            or exists (select 1 from public.transactions t where t.quote_id = q.id and t.revealed_at is not null))
       -- wave C: a quote on a request being checked is left out (counted under quotes_being_checked) unless he has a transaction
       -- on that very quote, as the portal cards hold it (customer_api inquiry_lifecycle.ts, paidQuoteIds)
       and not ((select chk from cfg) ? q.inquiry_id::text
                and not exists (select 1 from public.transactions t where t.quote_id = q.id and t.customer_id = p_customer)))
  select coalesce(jsonb_agg(x.j order by x.created_at desc), '[]'::jsonb) from (
    select i.created_at, jsonb_build_object(
      'id', i.id, 'ref', i.rfq_no, 'category', i.category, 'emirate', i.emirate, 'status', i.status,
      'status_meaning', case i.status
          when 'open' then 'being prepared, not yet sent to suppliers'
          when 'sent' then 'sent to suppliers, waiting for quotes'
          when 'quoted' then 'quotes are coming in'
          when 'split' then 'split into one request per trade (each is listed on its own)'
          when 'revealed' then 'you revealed a supplier'
          when 'completed' then 'completed'
          when 'cancelled' then 'cancelled'
          else 'closed' end,
      'open', coalesce(i.status, '') in ('open', 'sent', 'quoted', 'split'),
      'created_at', i.created_at,
      'suppliers_received', m.n, 'first_sent_at', m.first_sent,
      'quotes_due_by', m.first_sent + make_interval(secs => (cfg.sla_h * 3600)::double precision),
      'quotes_received', coalesce(qq.live, 0), 'quotes_wanted', 3,
      'late', coalesce(i.status, '') in ('sent', 'quoted') and m.first_sent is not null and coalesce(qq.live, 0) < 3
              and not (cfg.chk ? i.id::text)   -- wave C: quotes held while he is checked are not late
              and now() >= m.first_sent + make_interval(secs => (cfg.sla_h * 3600)::double precision),
      'revealed', coalesce(qq.revealed, '[]'::jsonb) <> '[]'::jsonb,
      'revealed_quotes', coalesce(qq.revealed, '[]'::jsonb),
      'sealed_quotes', coalesce(qq.sealed, 0),
      -- unchanged from 3 Nov: the rounded average of the unrevealed quotes, from two (fn_wa_customer_request_answer reads it)
      'price_band', case when coalesce(qq.sealed, 0) < 2 or qq.sealed_avg is null then null
                         else jsonb_build_object(
                                'average_rounded_to_nearest_1000', case when qq.sealed_avg < 1000 then null else round(qq.sealed_avg / 1000) * 1000 end,
                                'average_label', case when qq.sealed_avg < 1000 then 'under AED 1,000'
                                                      else 'about AED ' || to_char(round(qq.sealed_avg / 1000) * 1000, 'FM999,999,999,990') end,
                                'note', 'rounded average of the quotes not yet revealed; each quote''s own price is under quotes') end,
      'chase', ch.j,
      -- wave C: how many of his quotes on this request are held while he is checked (never their prices)
      'quotes_being_checked', case when cfg.chk ? i.id::text then
          (select count(*) from public.quotes q0
            where q0.inquiry_id = i.id and coalesce(q0.status, '') not in ('draft', 'withdrawn', 'rejected', 'expired', 'held', 'cancelled')
              and q0.stale_at is null
              and not exists (select 1 from public.sanctions_ban sb where sb.lead_id = q0.supplier_id)
              and not exists (select 1 from public.transactions t where t.quote_id = q0.id and t.customer_id = p_customer)) else 0 end)
      -- WHAT HE ASKED, AND WHAT HIS PORTAL SHOWS HIM: every open or revealed request (a revealed one is still being worked:
      -- the supplier's contact, the other quotes, the refund window) and the three newest
      || case when not (coalesce(i.status, '') in ('open', 'sent', 'quoted', 'split', 'revealed') or i.rn <= 3) then '{}'::jsonb else jsonb_build_object(
      'asked', jsonb_strip_nulls(jsonb_build_object(
          'summary', left(i.summary, 600),
          -- his own words, exactly as stored; never parsed here
          'budget_as_he_stated_it', nullif(btrim(coalesce(i.budget, '')), ''),
          'required_by', i.required_by,
          -- 16 Nov 2026: the request's revision (1 at posting; each later change he made is one more, inquiry_revision)
          'revision', coalesce(i.revision, 1),
          'when_as_he_stated_it', nullif(btrim(coalesce(i.delivery_window, '')), ''),
          'emirate', i.emirate,
          -- his own site as he gave it; it is his, and a supplier never receives it before a reveal (_shared/site_location.ts)
          'site_as_he_gave_it', nullif(btrim(coalesce(i.spec ->> 'site_location', '')), ''),
          'floor', nullif(btrim(coalesce(i.floor, '')), ''),
          'urgency', i.urgency,
          'trades', to_jsonb(i.trades),
          -- the sales engineer's record of the materials and brands he asked for, installation, warranty and date
          'what_he_asked', case when jsonb_typeof(i.spec -> 'customer_requirements' -> 'display' -> cfg.lang) = 'array'
                                then i.spec -> 'customer_requirements' -> 'display' -> cfg.lang
                                when jsonb_typeof(i.spec -> 'customer_requirements' -> 'display' -> 'en') = 'array'
                                then i.spec -> 'customer_requirements' -> 'display' -> 'en' end,
          'quantity', i.spec -> 'quantity',
          'items', (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('item', left(b ->> 'description', 160), 'qty', b -> 'qty', 'unit', b ->> 'unit')) order by o)
                      from jsonb_array_elements(case when jsonb_typeof(i.boq -> 'boq') = 'array' then i.boq -> 'boq' else '[]'::jsonb end) with ordinality e(b, o)
                     where o <= 15),
          'items_total', case when jsonb_typeof(i.boq -> 'boq') = 'array' then jsonb_array_length(i.boq -> 'boq') end,
          'alternatives_he_accepted', case when jsonb_typeof(i.accepted_alternatives) = 'array' and jsonb_array_length(i.accepted_alternatives) > 0
                                           then i.accepted_alternatives end)),
      -- what he sent after the request went out (portal notes and WhatsApp changes, fn_inquiry_change_from_customer), newest last
      'changes_he_sent_after', coalesce((select jsonb_agg(jsonb_build_object('at', n.at, 'text', n.txt) order by n.at)
                                           from (select coalesce(r.answered_at, r.asked_at) as at, left(coalesce(r.answer_as_written, r.answer), 400) as txt
                                                   from public.rfq_clarification r
                                                  where r.inquiry_id = i.id and r.kind = 'note' and r.supplier_id is null
                                                    and coalesce(r.answer_as_written, r.answer) is not null
                                                  order by r.id desc limit 5) n), '[]'::jsonb),
      -- EVERY REVISION OF THE REQUEST (16 Nov 2026, inquiry_revision): what changed, old -> new, and who recorded it
      'revisions', coalesce((select jsonb_agg(jsonb_build_object('revision', rv.revision, 'at', rv.created_at, 'changed', rv.changes,
                                                'recorded', case rv.source when 'portal_edit' then 'he edited the request himself'
                                                                 else 'the sales engineer recorded it from his message' end) order by rv.revision)
                               from (select * from public.inquiry_revision r1 where r1.inquiry_id = i.id order by r1.revision desc limit 5) rv), '[]'::jsonb),
      -- EACH LIVE QUOTE AS HIS PORTAL SHOWS IT (customer_api my_inquiries; the anonymity decision in this file's header)
      'quotes', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                    'letter', lt.letter, 'label', case when cfg.lang = 'ar' then lt.label_ar else lt.label_en end,
                    -- said only when it is not the portal's own derivation (stored, or not yet shown in the portal)
                    'letter_source', nullif(lt.letter_source, 'stored'),
                    'price_ex_vat_aed', z.fee_base,
                    'price_as_shown', case when z.fee_base is null then 'price being confirmed with the supplier (its VAT basis is not settled)' else public.fn_aed_words(z.fee_base) || ' before VAT'
                       || case when z.vat_treatment in ('exclusive', 'confirmed_on_portal', 'inclusive') and z.vat_amount is not null
                               then ', ' || public.fn_aed_words(z.vat_amount) || ' VAT, ' || public.fn_aed_words(z.fee_base + z.vat_amount) || ' with VAT'
                               when z.vat_treatment in ('not_registered', 'zero_rated', 'exempt') then ', no VAT: ' || public.fn_aed_words(z.fee_base) || ' in total'
                               else ', VAT not stated' end
                       || case when z.discount_amount > 0 and z.gross_amount is not null
                               then ' (after a discount of ' || public.fn_aed_words(z.discount_amount) || ' from ' || public.fn_aed_words(z.gross_amount) || ')' else '' end end,
                    'vat_as_stated', case z.vat_treatment when 'exclusive' then 'VAT added on top of the price' when 'confirmed_on_portal' then 'VAT added on top of the price'
                                                          when 'inclusive' then 'the supplier''s total includes VAT'
                                                          when 'not_registered' then 'supplier not VAT registered: no VAT'
                                                          when 'zero_rated' then 'zero-rated: no VAT'
                                                          when 'exempt' then 'exempt: no VAT'
                                                          else 'VAT not stated' end,
                    'vat_aed', case when z.vat_treatment in ('exclusive', 'confirmed_on_portal', 'inclusive') then z.vat_amount end,
                    'total_with_vat_aed', case when z.vat_treatment in ('exclusive', 'confirmed_on_portal', 'inclusive') and z.vat_amount is not null
                                                 then z.fee_base + z.vat_amount
                                               when z.vat_treatment in ('not_registered', 'zero_rated', 'exempt')
                                                 then z.fee_base end,
                    'total_as_stated_aed', z.amount_as_stated,
                    'before_discount_aed', case when z.discount_amount > 0 then z.gross_amount end,
                    'discount_aed', case when z.discount_amount > 0 then z.discount_amount end,
                    'valid_until', z.expires_at, 'expired', case when z.expires_at is not null then z.expires_at < now() end,
                    'validity_as_stated', public.fn_quote_words_for_customer(z.validity, z.id, z.revealed_at is not null),
                    'lead_time_as_stated', public.fn_quote_words_for_customer(z.lead_time, z.id, z.revealed_at is not null),
                    'warranty_as_stated', public.fn_quote_words_for_customer(z.warranty, z.id, z.revealed_at is not null),
                    -- the sales engineer's checks of this quote against his request, stored when it went live (ledger 1588);
                    -- brand-free by construction (_shared/quote_review_notes.ts)
                    'notes_against_your_request', (select jsonb_agg(coalesce(case when cfg.lang = 'ar' then rn.n ->> 'ar' end, rn.n ->> 'en'))
                                                     from jsonb_array_elements(case when jsonb_typeof(z.review_notes) = 'array' then z.review_notes else '[]'::jsonb end) rn(n)
                                                    where coalesce(rn.n ->> 'en', rn.n ->> 'ar') is not null),
                    -- the request thread with THIS supplier (rfq_clarification, kind question: the supplier asks, he answers), so
                    -- "did B ask about the tiles, what did I tell them?" is answered by the quote's own letter. The question was
                    -- stripped of contacts and brands when it was asked (messages_api clarify_ask, stripSupplierQuestion) and is
                    -- what his portal thread shows; the code generaliser runs over it again before a model reads it.
                    -- THE THREAD WITH THIS SUPPLIER BEFORE THE REVEAL (16 Nov 2026, fn_customer_quote_thread): the supplier's questions
                    -- and his answers, and his own questions about this quote with the sales engineer's or the supplier's answer and
                    -- the date it is due by. Who asked and who answered are said, so a model never reads his question as the supplier's.
                    'questions_and_answers', public.fn_customer_quote_thread(i.id, z.supplier_id),
                    -- the request revision this price answers (inquiries.revision, quotes.priced_revision; null reads as 1)
                    'priced_revision', coalesce(z.priced_revision, 1),
                    'priced_before_the_request_last_changed', coalesce(z.priced_revision, 1) < coalesce(i.revision, 1),
                    'revealed', z.revealed_at is not null,
                    'supplier', case when z.revealed_at is null then null
                                     when z.sanctioned then 'a supplier no longer on QuotesDone'
                                     else coalesce((select l.company_name from public.leads l where l.id = z.supplier_id), 'the supplier') end))
                    order by z.fee_base, z.created_at)
                  from q z left join public.fn_customer_quote_letters(i.id) lt on lt.quote_id = z.id
                 where z.inquiry_id = i.id and (lt.letter is not null or z.revealed_at is not null)), '[]'::jsonb),
      -- REVIEW 16 Nov: a live quote his portal has not shown (held for missing details by code, or not yet opened) is counted, not priced
      'quotes_not_yet_on_his_portal', (select count(*) from q z left join public.fn_customer_quote_letters(i.id) lt on lt.quote_id = z.id
                                         where z.inquiry_id = i.id and lt.letter is null and z.revealed_at is null),
      -- REVIEW 16 Nov: no 'comparison' here. qd_compare_cache holds quote_compare's RAW model output (index.ts:582 writes `parsed`);
      -- the brand/name gate (generaliseDeep, hideBrandPhrases) and the stored letters are applied only when it is served, and a
      -- cache row is not tied to the current quotes. The portal remains the comparison's one door.
      'price_rule', 'Each quote''s price is given under its letter, exactly as his portal shows it. The supplier''s name, contacts and brand unlock only when he reveals that quote.')
      end as j
      from inq i cross join cfg
      left join lateral (select count(*)::int as n, min(x.sent_at) as first_sent
                           from public.inquiry_matches x where x.inquiry_id = i.id) m on true
      left join lateral (select count(*)::int as live, (count(*) filter (where q.revealed_at is null))::int as sealed,
                                avg(q.quote_amount) filter (where q.revealed_at is null) as sealed_avg,
                                jsonb_agg(jsonb_build_object('supplier', case when q.sanctioned then 'a supplier no longer on QuotesDone' else coalesce(l.company_name, 'the supplier') end,
                                          'amount_aed', q.quote_amount, 'revealed_at', q.revealed_at) order by q.revealed_at)
                                  filter (where q.revealed_at is not null) as revealed
                           from q left join public.leads l on l.id = q.supplier_id where q.inquiry_id = i.id) qq on true
      -- the open chase, read by equality on agent_actions_kind_type_from_idx exactly as on 3 Nov
      left join lateral (select jsonb_build_object('asked_at', a.created_at, 'state', a.status,
                                  'suppliers_reminded', a.evidence -> 'chased', 'next_update_by', a.detail ->> 'next_update_by',
                                  'outcome', a.evidence ->> 'verdict') as j
                           from public.agent_actions a
                          where m.first_sent is not null
                            and a.kind = 'handoff' and a.detail ->> 'type' = 'inquiry.status_chase' and a.detail ->> 'from' = 'customer_support'
                            and a.detail ->> 'inquiry_id' = i.id::text
                          order by a.id desc limit 1) ch on true) x
$function$;
revoke execute on function public.fn_customer_inquiry_facts(uuid, integer) from public, anon, authenticated;

select case
  when to_regprocedure('public.fn_reason_apply_sales_engineer__customer_question(bigint,jsonb)') is null then 'PROBE FAILED: the apply routine is missing'
  when not exists (select 1 from public.seat_duty where duty = 'sales_engineer.customer_questions') then 'PROBE FAILED: the duty is not registered'
  when position('fn_customer_quote_thread' in pg_get_functiondef('public.fn_customer_inquiry_facts(uuid, integer)'::regprocedure)) = 0 then 'PROBE FAILED: the facts do not read the thread'
  when has_function_privilege('anon', 'public.fn_customer_question_relay(bigint, text)', 'execute')
    or has_function_privilege('authenticated', 'public.fn_customer_quote_thread(uuid, bigint)', 'execute') then 'PROBE FAILED: a client can run them'
  else 'PROBE OK' end as verdict;
