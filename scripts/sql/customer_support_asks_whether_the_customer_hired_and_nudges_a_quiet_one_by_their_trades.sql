-- CUSTOMER SUPPORT ASKS WHETHER THE CUSTOMER HIRED, AND NUDGES A QUIET CUSTOMER ABOUT THEIR OWN TRADES.
-- Seat: customer_support. 29 Sep 2026, founder_instruction 1013 item 1:
--   "On day 3 and day 14 after a reveal, ask the customer whether they hired and how the supplier was. Record the
--    answer as an outcome. A customer inactive for 60 days gets one relevant nudge, based on their past categories.
--    Messages use the customer's chosen inquiry language. Respect opt-out and suppression. Plain code, no LLM."
--
-- DEPENDS ON (both open, both pending, apply them first):
--   * PR #1065 suppliers_are_always_written_in_english_and_customers_in_their_inquirys_language.sql:
--     inquiries.lang and fn_inquiry_locale(uuid), the language the customer chose for the request.
--   * PR #1064 every_real_outcome_lands_on_the_seat_that_decided_it_with_its_reason.sql: fn_outcome_record, which
--     lays an outcome on the seat that decided and turns a wrong one into a lesson; its z92 trigger on reviews turns
--     a rating into an outcome on the inquiry, the quote and the supplier.
--
-- WHAT WAS MEASURED (29 Sep 2026, schema mirror and production, read-only):
--   * No routine asks a customer after a reveal whether they hired: pg_proc has the supplier's reveal nudges
--     (transactions.nudged_24_at/nudged_48_at, supplier_ack) and the public-review ask three weeks after the reveal,
--     nothing that asks the customer about the hire itself. inquiries.hired_supplier_id is set by nobody from the
--     customer's side.
--   * fn_customer_support_winback_tick (customer_support_activates_wins_back_and_settles_disputes.sql) already
--     owns "a quiet customer": one message per dormant spell, 60-90 days after a REVEAL, generic copy in
--     customers.locale. A customer who posted requests but never revealed was never written to, and the copy named
--     none of their trades. This file REPLACES that routine rather than adding a second one.
--
-- WHAT THIS ADDS
--   1. public.customer_followup: one row per (reveal, stage) actually sent, with the one-tap token and the answer.
--   2. fn_customer_support_followup_tick (duty customer_support.followup, every 6 hours): a reveal 3-7 days old is
--      asked once (stage day_three); a reveal 14-30 days old is asked once more (day_fourteen) unless the customer
--      already answered hired or not hired. A refunded or disputed reveal is not asked.
--   3. fn_customer_followup_view / fn_customer_followup_answer: the one-tap page (edge function customer_followup,
--      served on quotesdone.ae/u/followup) reads the question by token and records the answer:
--        hired yes     -> fn_outcome_record(inquiry and quote, 'hired', correct) and inquiries.hired_supplier_id when
--                         empty;
--        hired no      -> fn_outcome_record(inquiry and quote, 'not_hired', wrong, with the customer's words);
--        not yet       -> nothing recorded; day 14 asks again;
--        stars (1-5)   -> one public.reviews row for the reveal (reviews_transaction_id_key keeps it to one); the
--                         z92 trigger of #1064 makes it an outcome on the inquiry, the quote and the supplier.
--   4. fn_customer_support_winback_tick, rewritten: "inactive" is no request and no reveal for 60 days (a customer
--      who only ever posted counts too); one message per quiet spell, keyed on the date of the last activity, as
--      before; the copy names the customer's own trades (their most frequent request categories, taxonomy labels)
--      and how many verified suppliers quote for the first of them today.
--   Language: every message is in the language of the customer's inquiry (fn_inquiry_locale); the customer's
--   registered language only when the inquiry has none.
--   Suppression and opt-out: every message goes through fn_customer_support_duty_send, which records each (stage,
--   subject) once and sends only to an address fn_email_sendable accepts (email_suppressions, which is where an
--   unsubscribe or a "stop" lands, dead domains, block patterns). Banned customers are never selected. A fixture run
--   (set local qd.duty_fixtures = 'on') selects ONLY demo rows, so a probe cannot reach a real person.
--   No model is called anywhere in this file: every choice is a rule.
--
-- Pending: scripts/sql/pending/customer_support_asks_whether_the_customer_hired_and_nudges_a_quiet_one_by_their_trades.txt
-- Proved by: scripts/eval/customer_followup_and_reengagement_proof.mjs (one aborted transaction, ZZ DEMO rows).
-- Prevented by: scripts/checks/customer_followup_asks_in_the_inquiry_language_and_records_the_outcome.test.mjs

-- ── 1. what was asked, and what the customer answered ────────────────────────────────────────────
create table if not exists public.customer_followup (
  id             bigint generated always as identity primary key,
  transaction_id uuid not null references public.transactions (id) on delete cascade,
  stage          text not null check (stage in ('day_three', 'day_fourteen')),
  token          uuid not null default gen_random_uuid() unique,
  lang           text not null check (lang in ('en', 'ar')),
  asked_at       timestamptz not null default now(),
  answered_at    timestamptz,
  hired          text check (hired in ('yes', 'no', 'not_yet')),
  stars          smallint check (stars between 1 and 5),
  comment        text,
  outcome        jsonb,
  unique (transaction_id, stage)
);
comment on table public.customer_followup is
  'Day-3 and day-14 questions after a reveal (did you hire, how was the supplier) and the answers. customer_support, founder_instruction 1013.';
alter table public.customer_followup enable row level security;
drop policy if exists customer_followup_service_role_only on public.customer_followup;
create policy customer_followup_service_role_only on public.customer_followup
  as permissive for all to public using (false) with check (false);
revoke all on public.customer_followup from anon, authenticated;

-- ── 2. the language a customer is written in about a request ─────────────────────────────────────
create or replace function public.fn_customer_message_lang(p_inquiry uuid, p_customer_locale text)
returns text language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v text;
begin
  -- the language chosen for the request; the registered one only when the request carries none.
  -- ponytail: fn_inquiry_locale is looked up at run time so this file can be replayed (seat-duty probes) before
  -- #1065 is applied; once #1065 is live the lookup always succeeds and this is a plain call.
  if to_regprocedure('public.fn_inquiry_locale(uuid)') is not null then
    execute 'select public.fn_inquiry_locale($1)' into v using p_inquiry;
  end if;
  return coalesce(v, case when p_customer_locale = 'ar' then 'ar' else 'en' end);
end $fn$;
revoke execute on function public.fn_customer_message_lang(uuid, text) from public, anon, authenticated;

-- ── 3. the follow-up copy (a rule, testable on its own) ──────────────────────────────────────────
create or replace function public.fn_customer_followup_copy(p_stage text, p_lang text, p_name text, p_company text,
  p_rfq_no integer, p_trade text, p_link text)
returns jsonb language plpgsql immutable set search_path to 'public', 'pg_temp' as $fn$
declare v_ar boolean := p_lang = 'ar'; v_name text; v_co text; v_when_en text; v_when_ar text;
begin
  v_name := coalesce(nullif(btrim(p_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
  v_co := coalesce(nullif(btrim(p_company), ''), case when v_ar then 'المورّد' else 'the supplier' end);
  v_when_en := case when p_stage = 'day_three' then 'A few days ago' else 'Two weeks ago' end;
  v_when_ar := case when p_stage = 'day_three' then 'قبل أيام' else 'قبل أسبوعين' end;
  if v_ar then
    return jsonb_build_object('lang', 'ar',
      'subject', 'هل تعاقدتم مع ' || v_co || '؟',
      'body', 'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || v_when_ar || ' كشفتم بيانات ' || v_co || ' لطلبكم رقم ' || coalesce(p_rfq_no::text, '-')
        || coalesce(' (' || nullif(btrim(p_trade), '') || ')', '') || '. هل تعاقدتم معه، وكيف كانت تجربتكم مع المورّد؟' || chr(10) || chr(10)
        || 'أخبرونا بنقرة واحدة: ' || p_link || chr(10) || chr(10)
        || 'تساعدنا إجابتكم على مطابقتكم، ومطابقة كل عميل بعدكم، مع موردين أفضل.' || chr(10) || chr(10)
        || 'وإن كنتم لا ترغبون في تلقّي مثل هذه الرسائل، فيكفي أن تردّوا على هذه الرسالة لنتوقف عن إرسالها.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،');
  end if;
  return jsonb_build_object('lang', 'en',
    'subject', 'Did you hire ' || v_co || '?',
    'body', 'Dear ' || v_name || ',' || chr(10) || chr(10)
      || v_when_en || ' you revealed ' || v_co || ' for your request RFQ-' || coalesce(p_rfq_no::text, '-')
      || coalesce(' (' || nullif(btrim(p_trade), '') || ')', '') || '. Did you hire them, and how was the supplier?' || chr(10) || chr(10)
      || 'Tell us with one tap: ' || p_link || chr(10) || chr(10)
      || 'Your answer helps us match you, and every customer after you, with better suppliers.' || chr(10) || chr(10)
      || 'If you would rather not hear from us like this, reply to this e-mail and we will stop.');
end $fn$;
revoke execute on function public.fn_customer_followup_copy(text, text, text, text, integer, text, text) from public, anon, authenticated;

create or replace function public.fn_trade_label(p_code text, p_lang text)
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce((select case when p_lang = 'ar' then coalesce(t.label_ar, t.label) else t.label end
                     from public.taxonomy_trade t where t.code = lower(btrim(p_code))),
                  nullif(initcap(replace(btrim(coalesce(p_code, '')), '_', ' ')), ''))
$fn$;
revoke execute on function public.fn_trade_label(text, text) from public, anon, authenticated;

-- ── 4. the clock: ask on day 3, ask again on day 14 ──────────────────────────────────────────────
create or replace function public.fn_customer_support_followup_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on'; r record; v jsonb; m jsonb;
  v_stage text; v_lang text; v_tok uuid; v_seen int := 0; v_sent int := 0;
begin
  for r in select t.id as tx, t.inquiry_id, t.revealed_at, c.id as cid, c.full_name, c.email, c.locale,
                  l.company_name, i.rfq_no, coalesce(i.category, i.trades[1]) as trade,
                  case when t.revealed_at <= now() - interval '14 days' then 'day_fourteen' else 'day_three' end as stage
             from public.transactions t
             join public.customers c on c.id = t.customer_id
             left join public.leads l on l.id = t.supplier_id
             left join public.inquiries i on i.id = t.inquiry_id
            where t.revealed_at is not null
              and ((t.revealed_at <= now() - interval '3 days' and t.revealed_at > now() - interval '7 days')
                or (t.revealed_at <= now() - interval '14 days' and t.revealed_at > now() - interval '30 days'))
              -- a refund or a dispute is its own conversation. refund_status is 'window_open' on every reveal
              -- (trg_reveal_window), so a refund in play is named, not "any status".
              and t.refund_requested_at is null
              and coalesce(t.refund_status, '') not in ('requested', 'pending', 'approved', 'processing', 'refunded', 'succeeded')
              and not exists (select 1 from public.post_reveal_dispute d where d.transaction_id = t.id)
              and not coalesce(c.banned, false)
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
              -- a definite answer (hired or not) closes the question; "not yet" leaves day 14 to ask again
              and not exists (select 1 from public.customer_followup f where f.transaction_id = t.id and f.hired in ('yes', 'no'))
              and not exists (select 1 from public.customer_followup f where f.transaction_id = t.id
                                 and f.stage = case when t.revealed_at <= now() - interval '14 days' then 'day_fourteen' else 'day_three' end)
            order by t.revealed_at limit 200 loop
    v_seen := v_seen + 1;
    v_stage := r.stage;
    v_lang := public.fn_customer_message_lang(r.inquiry_id, r.locale);
    v_tok := gen_random_uuid();
    m := public.fn_customer_followup_copy(v_stage, v_lang, r.full_name, r.company_name, r.rfq_no,
           public.fn_trade_label(r.trade, v_lang), 'https://quotesdone.ae/u/followup?t=' || v_tok);
    v := public.fn_customer_support_duty_send('followup.' || v_stage, r.tx::text, 'customer', r.email, v_lang,
           m->>'subject', m->>'body', r.cid, null, r.inquiry_id);
    -- a question counts as asked only when it went out; a suppressed address is recorded by duty_send, not here
    if coalesce((v->>'sent')::boolean, false) then
      insert into public.customer_followup (transaction_id, stage, token, lang) values (r.tx, v_stage, v_tok, v_lang)
      on conflict (transaction_id, stage) do nothing;
      v_sent := v_sent + 1;
    end if;
  end loop;
  return jsonb_build_object('due', v_seen, 'asked', v_sent);
end $fn$;
revoke execute on function public.fn_customer_support_followup_tick() from public, anon, authenticated;
grant execute on function public.fn_customer_support_followup_tick() to service_role;

-- ── 5. the one-tap page: read the question, record the answer ────────────────────────────────────
create or replace function public.fn_customer_followup_view(p_token uuid)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce((
    select jsonb_build_object('ok', true, 'lang', f.lang, 'stage', f.stage, 'company', l.company_name,
             'rfq_no', i.rfq_no, 'trade', public.fn_trade_label(coalesce(i.category, i.trades[1]), f.lang),
             'answered', f.answered_at is not null, 'hired', f.hired, 'stars', f.stars)
      from public.customer_followup f
      join public.transactions t on t.id = f.transaction_id
      left join public.leads l on l.id = t.supplier_id
      left join public.inquiries i on i.id = t.inquiry_id
     where f.token = p_token), jsonb_build_object('ok', false, 'reason', 'not_found'))
$fn$;
revoke execute on function public.fn_customer_followup_view(uuid) from public, anon, authenticated;
grant execute on function public.fn_customer_followup_view(uuid) to service_role;

create or replace function public.fn_customer_followup_answer(p_token uuid, p_hired text, p_stars integer default null,
  p_comment text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare f public.customer_followup; t public.transactions; v_comment text; v_reason text; v_out jsonb := '{}'::jsonb;
begin
  if p_hired is null or p_hired not in ('yes', 'no', 'not_yet') then
    raise exception 'hired is yes, no or not_yet' using errcode = '22023';
  end if;
  if p_stars is not null and p_stars not between 1 and 5 then
    raise exception 'stars are 1 to 5' using errcode = '22023';
  end if;
  select * into f from public.customer_followup where token = p_token for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  -- the first definite answer stands; a second tap on an old e-mail changes nothing
  if f.hired in ('yes', 'no') then return jsonb_build_object('ok', true, 'already', true, 'hired', f.hired); end if;
  select * into t from public.transactions where id = f.transaction_id;
  v_comment := nullif(left(btrim(coalesce(p_comment, '')), 1000), '');

  if p_hired in ('yes', 'no') then
    v_reason := 'customer answered on ' || replace(f.stage, '_', ' ') || ': '
      || case when p_hired = 'yes' then 'hired the revealed supplier' else 'did not hire the revealed supplier' end
      || coalesce(', rated ' || p_stars || '/5', '') || coalesce(': ' || left(v_comment, 300), '');
    if t.inquiry_id is not null then
      v_out := v_out || jsonb_build_object('inquiry', public.fn_outcome_record('inquiries', t.inquiry_id::text,
        case when p_hired = 'yes' then 'hired' else 'not_hired' end, p_hired = 'yes', v_reason, 'sales_engineer', 'inquiry', null));
    end if;
    if t.quote_id is not null then
      v_out := v_out || jsonb_build_object('quote', public.fn_outcome_record('quotes', t.quote_id::text,
        case when p_hired = 'yes' then 'hired' else 'not_hired' end, p_hired = 'yes', v_reason, 'sales_engineer', 'quote', null));
    end if;
    if p_hired = 'yes' and t.inquiry_id is not null then
      update public.inquiries set hired_supplier_id = t.supplier_id where id = t.inquiry_id and hired_supplier_id is null;
    end if;
  end if;

  -- HOW WAS THE SUPPLIER: one rating per reveal. reviews_reason_required wants ten characters or no comment.
  if p_stars is not null and not exists (select 1 from public.reviews r where r.transaction_id = t.id) then
    insert into public.reviews (supplier_id, customer_id, inquiry_id, transaction_id, rating, comment)
    values (t.supplier_id, t.customer_id, t.inquiry_id, t.id, p_stars, case when length(v_comment) >= 10 then v_comment end);
    v_out := v_out || jsonb_build_object('review', true);
  end if;

  update public.customer_followup
     set answered_at = now(), hired = p_hired, stars = coalesce(p_stars, stars), comment = coalesce(v_comment, comment), outcome = v_out
   where id = f.id;
  return jsonb_build_object('ok', true, 'hired', p_hired, 'recorded', v_out);
end $fn$;
revoke execute on function public.fn_customer_followup_answer(uuid, text, integer, text) from public, anon, authenticated;
grant execute on function public.fn_customer_followup_answer(uuid, text, integer, text) to service_role;

-- ── 6. a quiet customer: one nudge per spell, about their own trades ─────────────────────────────
create or replace function public.fn_customer_support_winback_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on'; r record; v jsonb;
  v_lang text; v_ar boolean; v_name text; v_labels text; v_first text; v_n int; v_sent int := 0; v_seen int := 0;
begin
  -- 29 Sep 2026 (founder_instruction 1013): "inactive" is no request and no reveal for 60 days, and the message is
  -- about the trades the customer actually asked for, in the language of their last request. Until this date it
  -- was 60-90 days after a reveal only, generic copy, customers.locale.
  for r in select c.id, c.full_name, c.email, c.locale, x.last_at, x.last_inquiry, x.trades
             from public.customers c
             cross join lateral (
               select greatest((select max(i.created_at) from public.inquiries i where i.customer_id = c.id),
                               (select max(t.revealed_at) from public.transactions t where t.customer_id = c.id)) as last_at,
                      (select i.id from public.inquiries i where i.customer_id = c.id order by i.created_at desc limit 1) as last_inquiry,
                      -- their trades: the most frequent request categories, most recent first on a tie, at most three
                      array(select k from (select lower(btrim(coalesce(i.category, i.trades[1]))) as k, count(*) as n, max(i.created_at) as at
                                             from public.inquiries i where i.customer_id = c.id
                                              and coalesce(i.category, i.trades[1]) is not null group by 1) g
                             order by n desc, at desc limit 3) as trades) x
            where x.last_at between now() - interval '90 days' and now() - interval '60 days'
              and x.last_inquiry is not null
              and not coalesce(c.banned, false)
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
            order by x.last_at limit 200 loop
    v_seen := v_seen + 1;
    v_lang := public.fn_customer_message_lang(r.last_inquiry, r.locale);
    v_ar := v_lang = 'ar';
    v_name := coalesce(nullif(btrim(r.full_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
    select string_agg(public.fn_trade_label(k, v_lang), case when v_ar then '، ' else ', ' end order by o)
      into v_labels from unnest(r.trades) with ordinality as u(k, o);
    v_first := public.fn_trade_label(r.trades[1], v_lang);
    -- how many verified suppliers quote for their first trade today (the rule supply_gap counts by)
    select count(*) into v_n from public.supplier_capabilities sc join public.leads l on l.id = sc.supplier_id
     where sc.confirmed_at is not null and r.trades[1] = any (sc.trades) and not coalesce(l.is_demo, false)
       and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes);
    v := public.fn_customer_support_duty_send('winback.dormant', r.id || ':' || to_char(r.last_at, 'YYYYMMDD'), 'customer',
      r.email, v_lang,
      case when v_ar then 'مشروعكم القادم في ' || coalesce(v_first, 'QuotesDone') else 'Your next ' || coalesce(v_first, 'project') || ' job on QuotesDone' end,
      case when v_ar then
        'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'مضى بعض الوقت على آخر طلب لكم معنا' || coalesce(' في ' || v_labels, '') || '.'
        || case when v_n > 0 then ' ويقدّم اليوم ' || v_n || ' من الموردين الموثّقين في الإمارات عروضهم في ' || v_first || '.' else '' end
        || ' وحين يحين مشروعكم القادم، يكفي أن تنشروه مرة واحدة، فنقارن العروض ونوصي بأفضل ثلاثة منها من حيث القيمة. ولا تكشفون إلا بيانات المورّد الذي تختارونه، ولا تدفعون 3% إلا حينها: https://quotesdone.ae/ar/me' || chr(10) || chr(10)
        || 'وإن كنتم لا ترغبون في تلقّي مثل هذه الرسائل، فيكفي أن تردّوا على هذه الرسالة لنتوقف عن إرسالها.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Dear ' || v_name || ',' || chr(10) || chr(10)
        || 'It has been a while since your last request with us' || coalesce(' for ' || v_labels, '') || '.'
        || case when v_n > 0 then ' Today ' || v_n || ' verified UAE supplier' || case when v_n = 1 then ' quotes' else 's quote' end || ' for ' || v_first || '.' else '' end
        || ' When the next job comes up, post it once; we compare the quotes and recommend the top three by value. You reveal only the one you choose, and pay 3% only then: https://quotesdone.ae/me' || chr(10) || chr(10)
        || 'If you would rather not hear from us like this, reply to this e-mail and we will stop.' end,
      r.id, null, r.last_inquiry);
    if coalesce((v->>'sent')::boolean, false) then v_sent := v_sent + 1; end if;
  end loop;
  return jsonb_build_object('dormant', v_seen, 'written', v_sent);
end $fn$;
-- CREATE OR REPLACE keeps the existing ACL; restated so this file alone says who may run it (the duty checks read it).
revoke execute on function public.fn_customer_support_winback_tick() from public, anon, authenticated;
grant execute on function public.fn_customer_support_winback_tick() to service_role;

-- ── 7. the clock ─────────────────────────────────────────────────────────────────────────────────
insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('customer_support.followup', 'customer_support', interval '6 hours', 'fn_customer_support_followup_tick',
   'ask the customer on day 3 and day 14 after a reveal whether they hired and how the supplier was; the answer is an outcome',
   'scripts/sql/customer_support_asks_whether_the_customer_hired_and_nudges_a_quiet_one_by_their_trades.sql'),
  ('customer_support.winback', 'customer_support', interval '1 day', 'fn_customer_support_winback_tick',
   'one nudge about their own trades to a customer with no request and no reveal for 60 days',
   'scripts/sql/customer_support_asks_whether_the_customer_hired_and_nudges_a_quiet_one_by_their_trades.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;
