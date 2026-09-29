-- SUPPLIERS ARE ALWAYS WRITTEN IN ENGLISH; A CUSTOMER IN THE LANGUAGE OF THEIR INQUIRY
-- Seat: sales_engineer (the supplier side), with customer_support for the customer side. 28 Sep 2026.
--
-- Founder, 28 Sep 2026, after he received an Arabic supplier email sample (founder_instruction, this date):
--   "Every message to a SUPPLIER is always in English, never Arabic, on every channel: email, WhatsApp, SMS
--    and PDF, including invitations, nudges, inquiries sent to suppliers and supplier notifications.
--    Every message to a CUSTOMER uses the language the customer selected when they created the inquiry."
--
-- WHAT WAS MEASURED BEFORE THIS FILE (production, 28 Sep 2026 19:53 UTC): 0 leads with locale 'ar', yet 5
-- supplier-bound notifications with lang 'ar' - all supplier_invite_seed rows carrying the Arabic invitation.
-- The Arabic invitation was chosen by fn_supplier_invite_candidates from leads.locale OR an Arabic company
-- name (#916). Every other supplier path chose Arabic from leads.locale, directly or via fn_registered_locale.
--
-- WHAT CHANGES
--  1. inquiries.lang: the language the customer chose when creating the request (customer_api create_inquiry
--     writes it from the composer's page language; a row without one takes the customer's registered
--     language on insert). public.fn_inquiry_locale(inquiry) reads it.
--  2. fn_registered_locale answers 'en' for every supplier. Every caller (fn_supplier_notice,
--     fn_sales_engineer_writes, the delivery remediation, the edge functions through
--     _shared/registered_locale.ts, login codes) is English for a supplier from here.
--  3. a04_notifications_speak_the_recipients_language: a supplier-bound row is ALWAYS lang 'en', whatever the
--     caller wrote, and a supplier-bound row carrying any Arabic script is replaced by the English copy
--     (notification_copy) - the last net, so a new caller that forgets cannot reach a supplier in Arabic.
--     A customer row about an inquiry takes the inquiry's language.
--  4. z05_notifications_supplier_is_english: a trigger that refuses a supplier-bound row in any language but
--     English on insert, and on an update that changes its lang, subject, body or to_role. Not a CHECK: a
--     NOT VALID CHECK still runs on every update, and would have refused the delivery/bounce webhooks'
--     status update on the five historical seed rows, which stay unrewritten as the record of what was sent.
--  5. The routines that read leads.locale or the company name themselves now write English to a supplier:
--     fn_rfq_short_of_quotes_tick, fn_sales_engineer_supplier_documents_tick,
--     fn_sales_engineer_supplier_onboarding, fn_supplier_portfolio_reminder_compose,
--     fn_supplier_registration_reminder_compose, fn_ceo_decides_post_reveal_dispute,
--     fn_customer_support_dispute_open. fn_sales_engineer_writes and fn_rfq_short_of_quotes_tick write to a
--     customer in the inquiry's language.
--     fn_supplier_invite_candidates is made English by PR #964
--     (scripts/sql/the_supplier_invitation_ends_with_one_question_and_is_always_english.sql), which this file
--     follows and does not redefine.
-- leads.locale is KEPT: it is the language the supplier portal's own screens open in, which is not a message.
--
-- Prevented by: scripts/checks/suppliers_are_always_written_in_english.test.mjs (reads the schema mirror and
-- the sender sources; fails if any path can pick Arabic for a supplier again).
-- The routines below were copied from the live definitions and changed only where a comment carrying the
-- date 28 Sep 2026 says so.

-- ── 1. the inquiry's language ──────────────────────────────────────────────────────────────────────────
alter table public.inquiries add column if not exists lang text;
alter table public.inquiries drop constraint if exists inquiries_lang_chk;
alter table public.inquiries add constraint inquiries_lang_chk check (lang is null or lang in ('en', 'ar'));
comment on column public.inquiries.lang is
  'The language the customer chose when creating this request (en/ar). Every message to the customer about it uses this; suppliers are always written in English. Founder, 28 Sep 2026.';

update public.inquiries i set lang = case when c.locale = 'ar' then 'ar' else 'en' end
  from public.customers c where c.id = i.customer_id and i.lang is null;

create or replace function public.fn_inquiries_lang_default()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  -- a request created without a language (an import, a fixture, an older client) takes the customer's
  -- registered language; one created from the composer carries the page language it was written in.
  if new.lang is null or new.lang not in ('en', 'ar') then
    new.lang := coalesce(public.fn_registered_locale('customer', new.customer_id), 'en');
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_inquiries_lang_default() from public, anon, authenticated;
drop trigger if exists a00_inquiries_lang_default on public.inquiries;
create trigger a00_inquiries_lang_default before insert on public.inquiries
  for each row execute function public.fn_inquiries_lang_default();

create or replace function public.fn_inquiry_locale(p_inquiry uuid)
returns text
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  -- null when no inquiry is named or it has no language: the caller falls back to the registered one.
  select case when i.lang = 'ar' then 'ar' when i.lang = 'en' then 'en' end
    from public.inquiries i where i.id = p_inquiry
$fn$;
revoke execute on function public.fn_inquiry_locale(uuid) from public, anon, authenticated;

-- ── 2. the registered language: a supplier is English ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_registered_locale(p_role text, p_customer uuid DEFAULT NULL::uuid, p_lead bigint DEFAULT NULL::bigint, p_email text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- null ONLY when nobody is registered under these keys (a sign-up in progress): the caller then uses
  -- the language of the page the person is registering on. A registered customer answers en or ar.
  -- A SUPPLIER IS ALWAYS 'en' (founder, 28 Sep 2026): every message to a supplier is English, whatever
  -- leads.locale says; leads.locale now decides only the language the supplier portal's screens open in.
  select case when p_role = 'supplier' then 'en'
              when x is null then null when lower(x) like 'ar%' then 'ar' else 'en' end
    from (select case
      when p_role = 'customer' then coalesce(
        (select c.locale from public.customers c where c.id = p_customer),
        (select c.locale from public.customers c
          where p_email is not null and lower(c.email) = lower(btrim(p_email)) limit 1))
    end as x) s
$function$;

-- ── 3. the last net on every notification ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_notifications_speak_the_recipients_language()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_all text; v_ar boolean; v_latin boolean; c public.notification_copy; v_ref text; v_inq text;
        v_name text; v_sup_ar boolean;
begin
  if coalesce(new.to_role, '') not in ('customer', 'supplier') then return new; end if;
  -- 28 Sep 2026 (founder): a supplier is always written in English, whatever the caller set; a customer is
  -- written in the language they chose for the inquiry the message is about.
  if new.to_role = 'supplier' then
    new.lang := 'en';
  elsif new.inquiry_id is not null then
    v_inq := public.fn_inquiry_locale(new.inquiry_id);
    if v_inq is not null then new.lang := v_inq; end if;
  end if;
  if new.lang is null or new.lang not in ('en', 'ar') then
    new.lang := coalesce(public.fn_registered_locale(new.to_role, null, new.lead_id, new.to_email), 'en');
  end if;
  v_all := coalesce(new.subject, '') || ' ' || coalesce(new.body, '');
  v_ar := v_all ~ '[؀-ۿ]';
  -- coalesce: fn_language_mismatch answers null for pure Arabic, and a null here would make the
  -- pure-Arabic-to-an-English-recipient case below evaluate to null and never be corrected.
  v_latin := coalesce(public.fn_language_mismatch('ar', v_all) like 'English inside Arabic%', false)
             or (not v_ar and v_all ~ '[A-Za-z]{2,}');
  -- A supplier gets no Arabic at all, not even an Arabic half of a bilingual body (28 Sep 2026). The
  -- supplier's own company name is a name, not a language: an English invitation to a company registered
  -- under an Arabic name is English and is left alone (the name is removed before the test, nothing else).
  if new.to_role = 'supplier' and v_ar then
    select nullif(btrim(l.company_name), '') into v_name from public.leads l where l.id = new.lead_id;
    v_sup_ar := case when v_name is null then v_all else replace(v_all, v_name, '') end ~ '[؀-ۿ]';
  end if;
  if (new.lang = 'ar' and not v_ar) or (new.lang = 'en' and v_ar and not v_latin)
     or coalesce(v_sup_ar, false) then
    select * into c from public.notification_copy where type = new.type;
    if not found then select * into c from public.notification_copy where type = '*'; end if;
    if found then
      -- 21 Sep 2026: the reference is the job number (inquiries.rfq_no), the same one both portals print.
      v_ref := case when new.inquiry_id is not null
                    then 'QD-' || public.fn_job_no(new.inquiry_id) end;
      new.subject := case when new.lang = 'ar' then c.subject_ar else c.subject_en end;
      new.body := replace(case when new.lang = 'ar' then c.body_ar else c.body_en end,
                          ' {ref}', coalesce(' ' || v_ref, ''));
      new.html := null;   -- a pre-rendered html copy would still carry the old language
    end if;
  end if;
  return new;
end $function$;

-- ── 4. the rule in the schema ──────────────────────────────────────────────────────────────────────────
-- A trigger, not a CHECK (release review, 29 Sep 2026). A NOT VALID CHECK is still evaluated on EVERY
-- update of a row, so the delivery and bounce webhooks' status update on the five historical Arabic
-- seed rows (37425, 38444, 69940, 69976, 70174) would have failed with 23514 and the outbox would have
-- lost their delivery state. The rule is enforced when a row is written and whenever its language,
-- wording or recipient role changes; a status-only update of a historical row passes, and the five
-- rows' content is never rewritten. It runs after a04 (BEFORE triggers fire in name order), so on
-- insert it sees the language a04 settled on.
alter table public.notifications drop constraint if exists notifications_supplier_is_english;

create or replace function public.fn_notifications_supplier_is_english()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
begin
  if tg_op = 'UPDATE'
     and old.lang is not distinct from new.lang and old.subject is not distinct from new.subject
     and old.body is not distinct from new.body and old.to_role is not distinct from new.to_role then
    return new;
  end if;
  if coalesce(new.to_role, '') = 'supplier' and coalesce(new.lang, 'en') <> 'en' then
    raise exception 'notifications_supplier_is_english: a supplier is always written in English (notification %, lang %)',
      new.id, new.lang using errcode = '23514';
  end if;
  return new;
end $function$;
revoke execute on function public.fn_notifications_supplier_is_english() from public, anon, authenticated;

drop trigger if exists z05_notifications_supplier_is_english on public.notifications;
create trigger z05_notifications_supplier_is_english
  before insert or update of lang, subject, body, to_role on public.notifications
  for each row execute function public.fn_notifications_supplier_is_english();

-- ── 5. the routines that chose the supplier's language themselves ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_rfq_short_of_quotes_tick(p_include_fixtures boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  -- the top-3 rule: the comparison report is the top 3 (founder rule). A constant, not a setting.
  c_target constant int := 3;
  v_window numeric; v_lead numeric := public.fn_seat_clock_policy('rfq_short_sweep_hours_before_deadline', 8);
  v_fanout int := coalesce(public.fn_seat_clock_policy('match_max_fanout', 5), 5)::int;
  r record; s record; l public.leads; v jsonb; v_codes text[]; v_need text; v_value numeric; v_new int;
  v_swept int := 0; v_invited int := 0; v_reminded int := 0; v_told int := 0; v_skipped jsonb := '[]'::jsonb;
begin
  select nullif(regexp_replace(coalesce(value, ''), '[^0-9.]', '', 'g'), '')::numeric into v_window
    from public.app_secrets where key = 'sla_quote_hours';
  v_window := coalesce(v_window, 24);

  for r in
    with open_rfq as (
      select i.*, c.email as cemail, coalesce(i.lang, c.locale) as clocale,   -- the customer: the inquiry's own language (founder, 28 Sep 2026)
             c.full_name as cname,
             public.fn_seat_clock_customer_is_fixture(c) as fixture,
             (select min(m.sent_at) from public.inquiry_matches m where m.inquiry_id = i.id) as first_sent,
             (select count(*) from public.quotes q where q.inquiry_id = i.id
                and coalesce(q.status, '') not in ('draft', 'withdrawn', 'rejected', 'expired', 'held', 'cancelled')
                and q.stale_at is null)::int as live_quotes
        from public.inquiries i
        join public.customers c on c.id = i.customer_id
       where i.status in ('sent', 'quoted')
    )
    select o.*, o.first_sent + make_interval(secs => (v_window * 3600)::double precision) as deadline
      from open_rfq o
     where o.first_sent is not null
       and o.live_quotes < c_target
       and now() >= o.first_sent + make_interval(secs => ((v_window - v_lead) * 3600)::double precision)
       and now() <  o.first_sent + interval '14 days'
       and (p_include_fixtures or not o.fixture)
     order by o.first_sent
  loop
    v_swept := v_swept + 1;

    -- (a) widen ONCE, from the same matcher, same-kind suppliers only.
    if not coalesce(r.routing ? 'short_sweep', false) then
      v_new := 0;
      v_codes := public.fn_taxonomy_trades_for(case when coalesce(cardinality(r.trades), 0) > 0 then r.trades
                                                    else array[coalesce(r.category, '')] end);
      if coalesce(cardinality(v_codes), 0) > 0 then
        -- KEYED, NOT READ: scope_type is customer_api's own set (single | multi | turnkey) and role_needed is
        -- one of fn_match_capability's needs when the request carried one.
        v_need := case when r.scope_type = 'turnkey' then 'whole_scope'
                       when r.role_needed in ('whole_scope', 'supplies', 'executes') then r.role_needed
                       else 'executes' end;
        v_value := coalesce(r.expected_value, nullif(regexp_replace(coalesce(r.budget, ''), '[^0-9.]', '', 'g'), '')::numeric);
        if v_value is not null and v_value <= 0 then v_value := null; end if;
        for s in select m.supplier_id, m.score, m.why
                   from public.fn_match_capability(v_codes, v_need, '{}'::text[], '{}'::text[], r.scope_type, v_value, r.emirate, 60) m
                   join public.leads ld on ld.id = m.supplier_id
                  where not exists (select 1 from public.inquiry_matches x where x.inquiry_id = r.id and x.supplier_id = m.supplier_id)
                    and public.fn_seat_clock_lead_is_fixture(ld) = r.fixture
                  order by m.score desc
                  limit v_fanout loop
          insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, match_reason)
          values (r.id, s.supplier_id, least(1, greatest(0, round(s.score / 100, 3))),
                  left('short-of-quotes sweep (fn_rfq_short_of_quotes_tick): ' || coalesce(s.why, ''), 400))
          on conflict (inquiry_id, supplier_id) do nothing;
          if found then
            v_new := v_new + 1;
            select * into l from public.leads where id = s.supplier_id;
            v := public.fn_seat_clock_deliver('sales_engineer', 'supplier_rfq_widened_invite', 'supplier',
                   lower(btrim(coalesce(nullif(btrim(l.claimed_by), ''), l.email))), r.fixture, 'en', 'rfq_invite',   -- suppliers are always written in English (founder, 28 Sep 2026)
                  
                   jsonb_build_object('name', l.company_name, 'category', r.category, 'emirate', r.emirate),
                   'rfq_invite:' || r.id || ':' || l.id, r.id, null, l.id);
          end if;
        end loop;
      end if;
      update public.inquiries
         set routing = coalesce(routing, '{}'::jsonb) || jsonb_build_object('short_sweep', jsonb_build_object(
               'at', now(), 'quotes_then', r.live_quotes, 'invited', v_new, 'trades', to_jsonb(v_codes),
               'by', 'sales_engineer (fn_rfq_short_of_quotes_tick)'))
       where id = r.id;
      v_invited := v_invited + v_new;
    end if;

    -- (b) remind each invited supplier who has not quoted, once. Not one invited in the last 2 hours.
    for l in select ld.* from public.inquiry_matches m join public.leads ld on ld.id = m.supplier_id
              where m.inquiry_id = r.id and m.sent_at < now() - interval '2 hours'
                and not exists (select 1 from public.quotes q where q.inquiry_id = r.id and q.supplier_id = m.supplier_id)
                and public.fn_seat_clock_lead_is_fixture(ld) = r.fixture loop
      v := public.fn_seat_clock_deliver('sales_engineer', 'rfq_quote_reminder', 'supplier',
             lower(btrim(coalesce(nullif(btrim(l.claimed_by), ''), l.email))), r.fixture, 'en', 'rfq_quote_reminder',   -- suppliers are always written in English (founder, 28 Sep 2026)
             
             jsonb_build_object('name', l.company_name, 'category', r.category, 'emirate', r.emirate, 'deadline', r.deadline),
             'rfq_quote_reminder:' || r.id || ':' || l.id, r.id, null, l.id);
      if coalesce((v->>'ok')::boolean, false) and not coalesce((v->>'already')::boolean, false) then v_reminded := v_reminded + 1; end if;
    end loop;

    -- (c) at the deadline, tell the customer once.
    if now() >= r.deadline then
      v := public.fn_seat_clock_deliver('sales_engineer', 'rfq_short_of_quotes', 'customer', r.cemail, r.fixture, r.clocale,
             'rfq_short_of_quotes',
             jsonb_build_object('name', r.cname, 'category', r.category, 'emirate', r.emirate, 'quotes', r.live_quotes),
             'rfq_short_of_quotes:' || r.id, r.id);
      if coalesce((v->>'ok')::boolean, false) and not coalesce((v->>'already')::boolean, false) then v_told := v_told + 1;
      elsif not coalesce((v->>'ok')::boolean, false) then
        v_skipped := v_skipped || jsonb_build_array(jsonb_build_object('inquiry_id', r.id, 'reason', v->>'reason'));
      end if;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'swept', v_swept, 'invited', v_invited, 'reminded', v_reminded,
                            'customers_told', v_told, 'not_written', v_skipped,
                            'deadline_hours', v_window, 'sweep_from_hours_before', v_lead);
end
$function$;

CREATE OR REPLACE FUNCTION public.fn_sales_engineer_supplier_documents_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_reconcile json; v_final json; v_rechecked int := 0; v_closed int := 0; v_kept int := 0; r record; v jsonb;
  v_missing text[]; v_items_en text; v_items_ar text; v_ar boolean; v_to text; v_opened text; v_out jsonb;
  v_label jsonb := jsonb_build_object(
    'reg_name',        jsonb_build_array('company name', 'اسم الشركة'),
    'reg_mobile',      jsonb_build_array('a verified UAE mobile number', 'رقم جوال إماراتي موثَّق'),
    'reg_email',       jsonb_build_array('a verified e-mail address', 'بريد إلكتروني موثَّق'),
    'reg_licence',     jsonb_build_array('trade licence', 'الرخصة التجارية'),
    'reg_profile',     jsonb_build_array('company profile', 'الملف التعريفي للشركة'),
    'reg_terms',       jsonb_build_array('the signed supplier terms', 'الموافقة الموقّعة على شروط المورّد'),
    'licence_expired', jsonb_build_array('a trade licence that is in date', 'رخصة تجارية سارية المفعول'));
begin
  v_reconcile := public.fn_reconcile_doc_blocks(0);
  v_final := public.fn_doc_final_notice(7);

  for r in select l.id from public.leads l
            where l.approval_status = 'approved' and cardinality(public.fn_supplier_mandatory_six(l)) > 0 loop
    perform public.fn_sales_engineer_verifies_supplier(r.id, 'daily_recheck');
    v_rechecked := v_rechecked + 1;
  end loop;

  for r in select l.id, l.company_name, l.claimed_by, l.email, l.exception_opened_at
             from public.leads l
            where l.approval_status = 'action_required' and l.exception_closed_at is null
              and l.exception_due_at <= now()
            order by l.id loop
    v := public.fn_sales_engineer_verifies_supplier(r.id, 'deadline');
    if v->>'approval_status' is distinct from 'action_required' then v_kept := v_kept + 1; continue; end if;

    v_missing := array(select jsonb_array_elements_text(v->'missing'));
    if cardinality(v_missing) = 0 then v_missing := array['licence_expired']; end if;
    select string_agg(v_label->k->>0, ', ' order by o), string_agg(v_label->k->>1, '، ' order by o)
      into v_items_en, v_items_ar from unnest(v_missing) with ordinality u(k, o);

    -- trg_leads_exception_invariant closes the window with outcome closed_rejected.
    update public.leads
       set approval_status = 'rejected', verified = false, approval_decided_by = 'sales_engineer',
           rejection_reason = 'registration incomplete after ' || public.fn_supplier_exception_days() || ' days: ' || array_to_string(v_missing, ', ')
     where id = r.id;

    v_ar := false;   -- suppliers are always written in English (founder, 28 Sep 2026)
    v_to := lower(nullif(btrim(coalesce(r.claimed_by, r.email)), ''));
    v_opened := to_char(r.exception_opened_at at time zone 'Asia/Dubai', 'DD Mon YYYY');
    if v_to is not null then
      perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
        'type', 'registration_closed', 'requested_by', 'sales_engineer', 'channel', 'email',
        'to_email', v_to, 'to_role', 'supplier', 'lead_id', r.id, 'lang', case when v_ar then 'ar' else 'en' end,
        'dedupe_key', 'registration_closed:' || r.id || ':' || extract(epoch from r.exception_opened_at)::bigint,
        'subject', case when v_ar then 'إغلاق طلب تسجيلكم كمورّد في QuotesDone'
                        else 'Your QuotesDone supplier registration has closed' end,
        'body', case when v_ar then
            'السادة/ ' || coalesce(r.company_name, 'المورّد') || ' المحترمين،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
            || 'فُتح طلب تسجيلكم كمورّد بتاريخ ' || v_opened || '، ولا يزال ينقصه: ' || v_items_ar || '. '
            || 'أبلغناكم أننا سنبقي الطلب مفتوحًا ' || public.fn_ar_days(public.fn_supplier_exception_days()) || '، وقد انقضت هذه المدة، لذلك أُغلق طلب التسجيل.' || chr(10) || chr(10)
            || 'يمكنكم التسجيل من جديد في أي وقت عبر https://quotesdone.com/portal، ويُفعَّل حسابكم فور اكتمال البنود الستة: '
            || 'اسم الشركة، ورقم جوال موثَّق، وبريد إلكتروني موثَّق، والرخصة التجارية، والملف التعريفي للشركة، والموافقة الموقّعة على شروط المورّد.' || chr(10) || chr(10)
            || 'وإن رأيتم أن في ذلك خطأً، فيسعدنا أن تردّوا على هذه الرسالة.' || chr(10) || chr(10) || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
          else
            'Dear ' || coalesce(r.company_name, 'supplier') || ',' || chr(10) || chr(10)
            || 'Your supplier registration was opened on ' || v_opened || ' and still needs: ' || v_items_en || '. '
            || 'We said we would keep it open for ' || public.fn_supplier_exception_days() || ' days; that time has passed, so the registration is now closed.' || chr(10) || chr(10)
            || 'You are welcome to register again at any time at https://quotesdone.com/portal. Your account activates as soon as the six required items are complete: '
            || 'company name, a verified mobile number, a verified e-mail address, your trade licence, your company profile and the signed supplier terms.' || chr(10) || chr(10)
            || 'If you believe this is wrong, reply to this e-mail.' end)));
    end if;

    insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
    values ('sales_engineer', 'supplier_verification', 'auto_done', 'low',
            'Registration closed after the ' || public.fn_supplier_exception_days() || '-day window — ' || left(coalesce(r.company_name, 'supplier #' || r.id), 120),
            'No action required. The supplier was told in their language what was missing and that they may register again.',
            jsonb_build_object('supplier_id', r.id, 'decision', 'rejected', 'missing', v_missing, 'window_opened_at', r.exception_opened_at,
                               'notice', case when v_to is null then 'no e-mail on file' else 'queued through customer_support' end,
                               'source', 'fn_sales_engineer_supplier_documents_tick'),
            'leads', r.id::text);
    v_closed := v_closed + 1;
  end loop;

  v_out := jsonb_build_object('reconcile', v_reconcile, 'final_notice', v_final, 'approved_rechecked', v_rechecked,
                              'registrations_closed', v_closed, 'completed_at_deadline', v_kept);
  perform public.fn_it_duty_ran('supplier_docs', v_out);
  return v_out;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_sales_engineer_supplier_onboarding()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_nudged int := 0; v_to text; v_ar boolean; v_stages jsonb;
begin
  -- THE STAGE, from what the rows say happened (never from a status someone typed).
  with m as (
    select im.supplier_id, min(im.sent_at) as first_match_at,
           count(*) filter (where i.status not in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost')
                              and not exists (select 1 from public.quotes q where q.inquiry_id = im.inquiry_id and q.supplier_id = im.supplier_id)) as open_matches
      from public.inquiry_matches im join public.inquiries i on i.id = im.inquiry_id
     group by im.supplier_id
  ), q as (
    select supplier_id, min(created_at) as first_quote_at from public.quotes group by supplier_id
  ), s as (
    select l.id,
           case when coalesce(l.banned, false) or coalesce(l.permanently_closed, false) or l.approval_status = 'rejected' then 'closed'
                when q.first_quote_at is not null then 'quoting'
                when l.approval_status = 'approved' and m.first_match_at is not null then 'matched'
                when l.approval_status = 'approved' then 'approved'
                when l.approval_status = 'action_required' then 'action_required'
                when l.registration_submitted_at is not null or coalesce(l.claimed, false) then 'registering'
                when l.invite_clicked_at is not null then 'clicked'
                else 'invited' end as stage,
           m.first_match_at, q.first_quote_at, coalesce(m.open_matches, 0) as open_matches
      from public.leads l
      left join m on m.supplier_id = l.id
      left join q on q.supplier_id = l.id
     where l.invited_at is not null or coalesce(l.claimed, false) or l.approval_status is not null
  )
  insert into public.supplier_onboarding as o (lead_id, stage, first_match_at, first_quote_at, open_matches)
  select id, stage, first_match_at, first_quote_at, open_matches from s
  on conflict (lead_id) do update set
    stage_since    = case when o.stage is distinct from excluded.stage then now() else o.stage_since end,
    stage          = excluded.stage,
    first_match_at = excluded.first_match_at, first_quote_at = excluded.first_quote_at,
    open_matches   = excluded.open_matches, updated_at = now();

  -- THE NUDGE. Before approval the invitation reminders and the 14-day window already act; from approval to the
  -- first quote nothing did. Matched, requests open for him, not quoted 3 days after the first match: told, at
  -- most twice, a week apart, in his language, through customer_support.
  for r in
    select o.lead_id, o.open_matches, l.company_name, lower(nullif(btrim(coalesce(l.claimed_by, l.email)), '')) as to_email
      from public.supplier_onboarding o join public.leads l on l.id = o.lead_id
     where o.stage = 'matched' and o.open_matches > 0 and o.first_match_at < now() - interval '3 days'
       and o.nudges < 2 and (o.last_nudge_at is null or o.last_nudge_at < now() - interval '7 days')
     order by o.first_match_at
     limit 50
  loop
    continue when r.to_email is null;
    v_ar := false;   -- suppliers are always written in English (founder, 28 Sep 2026)
    perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'supplier_first_quote_nudge', 'requested_by', 'sales_engineer', 'channel', 'email',
      'to_email', r.to_email, 'to_role', 'supplier', 'lead_id', r.lead_id, 'lang', case when v_ar then 'ar' else 'en' end,
      'dedupe_key', 'first_quote_nudge:' || r.lead_id || ':' || (select nudges from public.supplier_onboarding where lead_id = r.lead_id),
      'subject', case when v_ar then 'طلبات عملاء بانتظار عروض أسعاركم في QuotesDone'
                      else 'Customer requests are waiting for your quotation' end,
      'body', case when v_ar then
          'السادة/ ' || coalesce(r.company_name, 'المورّد') || ' المحترمين،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
          || 'لديكم ' || r.open_matches || ' من طلبات العملاء المطابقة لتخصصكم لم تُقدَّم لها عروض أسعار حتى الآن. '
          || 'يمكنكم الاطلاع عليها وتقديم عروضكم من بوابة المورّدين: https://quotesdone.com/ar/portal' || chr(10) || chr(10)
          || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
        else
          'Dear ' || coalesce(r.company_name, 'supplier') || ',' || chr(10) || chr(10)
          || r.open_matches || ' customer request(s) matched to your trade are open and have no quotation from you yet. '
          || 'You can read them and quote in your supplier portal: https://quotesdone.com/portal' || chr(10) || chr(10)
          || 'QuotesDone' end)));
    update public.supplier_onboarding set nudges = nudges + 1, last_nudge_at = now() where lead_id = r.lead_id;
    v_nudged := v_nudged + 1;
  end loop;

  select coalesce(jsonb_object_agg(stage, n), '{}'::jsonb) into v_stages
    from (select stage, count(*) n from public.supplier_onboarding group by stage) x;
  return jsonb_build_object('stages', v_stages, 'nudged', v_nudged);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_supplier_portfolio_reminder_compose(p leads, p_gaps jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_ar boolean := false;   -- suppliers are always written in English (founder, 28 Sep 2026)
  v_lang text := 'en';
  v_name text := nullif(btrim(coalesce(p.company_name, '')), '');
  v_site text; v_link text; v_items text; v_subj text; v_body text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
  v_link := coalesce(v_site, 'https://quotesdone.com') || '/' || v_lang || '/portal';
  select string_agg('• ' || (g->>v_lang), E'\n' order by o) into v_items
    from jsonb_array_elements(coalesce(p_gaps, '[]'::jsonb)) with ordinality x(g, o);

  if v_ar then
    v_subj := 'خدماتكم لم تُستكمل بعد، وقد تفوتكم استفسارات العملاء';
    v_body := coalesce('السادة/ ' || v_name || ' المحترمين،', 'السادة الكرام،') || E'\n\nتحية طيبة وبعد،\n\n'
      || 'نشكركم على إتمام توثيق شركتكم لدى QuotesDone. وقد راجع مهندس المبيعات ملف أعمالكم، وتبيّن أن بعض بياناته لم تُستكمل بعد. '
      || 'وتعتمد مطابقة الاستفسارات على الخدمات التي أكّدتموها، لذا نرجو استكمال ما يلي:'
      || E'\n\n' || coalesce(v_items, '')
      || E'\n\nطريقة الاستكمال (تستغرق دقيقتين تقريبًا):'
      || E'\n1. سجّلوا الدخول إلى بوابة الموردين: ' || v_link
      || E'\n2. يظهر تبويب «الخدمات» أولًا. حدّدوا تحت كل تخصص جميع الخدمات التي تقدّمها شركتكم.'
      || E'\n3. إن ظهر تخصص لا تعمل فيه شركتكم، فاضغطوا «إزالة هذا التخصص».'
      || E'\n4. إن لم تجدوا في القائمة خدمة تقدّمونها، فاكتبوها في خانة «أضيفوا الخدمات التي تقدّمونها» ثم اضغطوا «إعادة صياغة خدماتي».'
      || E'\n5. اضغطوا «تأكيد خدماتي» لحفظ التغييرات، أو «تحديث خدماتي» إن سبق لكم الحفظ.'
      || E'\n\nالخيارات المتاحة لكم:'
      || E'\n• تحديد الخدمات التي تقدّمونها، فتصلكم الاستفسارات التي تذكرها.'
      || E'\n• إزالة التخصص الذي لا تعملون فيه، فلا تصلكم استفساراته بعد ذلك.'
      || E'\n• إن احتجتم إلى المساعدة، يكفي الرد على هذه الرسالة أو مراسلتنا عبر واتساب، وسيستكمل فريقنا البيانات معكم.'
      || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،\nفريق خدمة العملاء — QuotesDone';
  else
    v_subj := 'Your services are not complete yet, so you may miss inquiries';
    v_body := coalesce('Dear ' || v_name || ',', 'Dear Sir or Madam,') || E'\n\n'
      || 'Thank you for completing your verification with QuotesDone. Our sales engineer has reviewed your company''s portfolio, and some of it is still missing. '
      || 'Inquiries are matched against the services you have confirmed, so please complete the following:'
      || E'\n\n' || coalesce(v_items, '')
      || E'\n\nHow to complete it (about two minutes):'
      || E'\n1. Sign in to your supplier portal: ' || v_link
      || E'\n2. The Services tab opens first. Under each trade, tick every service your company provides.'
      || E'\n3. If a trade is listed that your company does not work in, press "Remove this trade".'
      || E'\n4. If a service you provide is not on the list, write it under "Add the services you provide" and press "Rewrite my services".'
      || E'\n5. Press "Confirm my services" to save, or "Update my services" if you have saved before.'
      || E'\n\nYour options:'
      || E'\n• Tick the services you provide: you will receive the inquiries that name them.'
      || E'\n• Remove a trade you do not work in: you will no longer receive inquiries for it.'
      || E'\n• Need help? Reply to this e-mail or message us on WhatsApp, and our team will complete it with you.'
      || E'\n\nKind regards,\nQuotesDone Customer Support';
  end if;
  return jsonb_build_object('lang', v_lang, 'subject', v_subj, 'body', v_body, 'link', v_link);
end
$function$;

CREATE OR REPLACE FUNCTION public.fn_supplier_registration_reminder_compose(p leads, p_stage text, p_step integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_ar boolean := false;   -- suppliers are always written in English (founder, 28 Sep 2026)
  v_lang text; v_site text; v_link text; v_name text := nullif(btrim(coalesce(p.company_name, '')), '');
  v_items_en text; v_items_ar text; v_due_en text; v_due_ar text; v_last boolean := p_step >= 2;
  v_greet text; v_subj text; v_body text;
  v_label jsonb := jsonb_build_object(
    'reg_name',        jsonb_build_array('company name', 'اسم الشركة'),
    'reg_mobile',      jsonb_build_array('a verified UAE mobile number', 'رقم جوال إماراتي موثَّق'),
    'reg_email',       jsonb_build_array('a verified e-mail address', 'بريد إلكتروني موثَّق'),
    'reg_licence',     jsonb_build_array('trade licence', 'الرخصة التجارية'),
    'reg_profile',     jsonb_build_array('company profile', 'الملف التعريفي للشركة'),
    'reg_terms',       jsonb_build_array('the signed supplier terms', 'الموافقة الموقّعة على شروط المورِّد'));
begin
  if p_stage not in ('clicked', 'started', 'incomplete') or p_step not in (1, 2) then
    raise exception 'fn_supplier_registration_reminder_compose: unknown stage % or step %', p_stage, p_step;
  end if;
  v_lang := case when v_ar then 'ar' else 'en' end;
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
  v_site := coalesce(v_site, 'https://quotesdone.com');
  v_link := v_site || '/' || v_lang || '/portal'
            || case when p_stage = 'clicked' and p.claim_token is not null then '?t=' || p.claim_token::text else '' end;

  if p_stage = 'incomplete' then
    select string_agg(coalesce(v_label->k->>0, k), ', ' order by o), string_agg(coalesce(v_label->k->>1, k), '، ' order by o)
      into v_items_en, v_items_ar from unnest(public.fn_supplier_mandatory_six(p)) with ordinality u(k, o);
    if p.license_expiry is not null and p.license_expiry < current_date then
      v_items_en := concat_ws(', ', v_items_en, 'a trade licence that is in date');
      v_items_ar := concat_ws('، ', v_items_ar, 'رخصة تجارية سارية المفعول');
    end if;
    v_items_en := coalesce(v_items_en, 'the items shown in your portal');
    v_items_ar := coalesce(v_items_ar, 'البنود الموضّحة في بوابتكم');
    v_due_en := to_char(coalesce(p.exception_due_at, now() + interval '14 days') at time zone 'Asia/Dubai', 'DD Mon YYYY');
    v_due_ar := to_char(coalesce(p.exception_due_at, now() + interval '14 days') at time zone 'Asia/Dubai', 'DD/MM/YYYY');
  end if;

  if v_ar then
    v_greet := case when v_name is null then 'السادة الكرام،' else 'السادة/ ' || v_name || ' المحترمين،' end;
    v_subj := case when v_last then 'تذكير أخير: ' else '' end
      || case p_stage when 'clicked' then 'دعوتكم للانضمام إلى الموردين المؤسِّسين في QuotesDone'
                      else 'استكمال تسجيلكم كمورِّد في QuotesDone' end;
    v_body := v_greet || E'\n\nتحية طيبة وبعد،\n\n'
      || case p_stage
           when 'clicked' then
             'نشكر لكم اطّلاعكم على دعوتنا للانضمام بصفة «مورِّد مؤسِّس» إلى QuotesDone، ونودّ إفادتكم بأن تسجيل شركتكم لم يبدأ بعد. '
             || 'ولا يستغرق التسجيل سوى دقائق معدودة، وهو مجاني دون أي عمولة على الأعمال التي تُرسى عليكم.'
             || E'\n\nللتسجيل، يُرجى الدخول إلى بوابة الموردين عبر الرابط التالي:\n\n' || v_link
           when 'started' then
             'نشكر لكم بدء تسجيل شركتكم مورِّدًا على منصة QuotesDone، ونودّ إفادتكم بأن طلب التسجيل لم يُستكمل بعد. '
             || 'ولا يستغرق استكماله سوى دقائق معدودة: بيانات الشركة، ورقم جوال وبريد إلكتروني موثَّقان، والرخصة التجارية، '
             || 'والملف التعريفي للشركة، والموافقة على شروط المورِّد.'
             || E'\n\nيمكنكم متابعة التسجيل من حيث توقفتم عبر الرابط التالي:\n\n' || v_link
           else
             'نفيدكم بأن طلب تسجيل شركتكم محفوظ لدينا، غير أنه ما زال ينقصه: ' || v_items_ar || '. '
             || 'ويُرجى استكماله في موعد أقصاه ' || v_due_ar || '، إذ يُغلق طلب التسجيل تلقائيًا بعد هذا التاريخ، ويمكنكم التسجيل من جديد في أي وقت.'
             || E'\n\nيمكنكم استكمال البنود المطلوبة عبر بوابة الموردين:\n\n' || v_link
         end
      || case when v_last then E'\n\nوهذا آخر تذكير نرسله إليكم بهذا الشأن.' else '' end
      || E'\n\nوفي حال عدم رغبتكم في تلقي هذه التذكيرات، يكفي الرد على هذه الرسالة لإزالة عنوانكم من القائمة.'
      || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،';
  else
    v_greet := case when v_name is null then 'Dear Sir or Madam,' else 'Dear ' || v_name || ',' end;
    v_subj := case when v_last then 'A last reminder: ' else '' end
      || case p_stage when 'clicked' then 'your invitation to join QuotesDone as a founding supplier'
                      else 'complete your QuotesDone supplier registration' end;
    v_body := v_greet || E'\n\n'
      || case p_stage
           when 'clicked' then
             'Thank you for opening our invitation to join QuotesDone as a founding supplier. Your company has not registered yet. '
             || 'It takes a few minutes, it is free, and there is no commission on the work you win.'
             || E'\n\nTo register, open your supplier portal here:\n\n' || v_link
           when 'started' then
             'Thank you for starting to register your company as a supplier on QuotesDone. The registration is not finished yet. '
             || 'It takes a few minutes: company details, a verified mobile number and e-mail address, your trade licence, '
             || 'your company profile and acceptance of the supplier terms.'
             || E'\n\nContinue where you left off:\n\n' || v_link
           else
             'Your registration is saved, but it still needs: ' || v_items_en || '. '
             || 'Please complete it by ' || v_due_en || '; after that date the registration closes automatically, and you are welcome to start again at any time.'
             || E'\n\nComplete the missing items in your supplier portal:\n\n' || v_link
         end
      || case when v_last then E'\n\nThis is the last reminder we will send about it.' else '' end
      || E'\n\nIf you would rather not receive these reminders, reply to this e-mail and we will remove your address.';
  end if;
  return jsonb_build_object('lang', v_lang, 'subject', v_subj, 'body', v_body, 'link', v_link);
end
$function$;

CREATE OR REPLACE FUNCTION public.fn_ceo_decides_post_reveal_dispute(p_id bigint, p_outcome text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  select coalesce(l.claimed_by, l.email) as email into s from public.leads l where l.id = d.supplier_id;
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
    from (values ('customer', c.email, coalesce(public.fn_inquiry_locale(d.inquiry_id), c.locale)),   -- the customer: the inquiry's language (28 Sep 2026)
          ('supplier', s.email, 'en')   -- suppliers are always written in English (founder, 28 Sep 2026)
         ) p(role, email, locale);
  return jsonb_build_object('dispute_id', d.id, 'outcome', p_outcome);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_customer_support_dispute_open(p_transaction_id uuid, p_raised_by text, p_statement text, p_intake_question_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  select coalesce(l.claimed_by, l.email) as email into s from public.leads l where l.id = t.supplier_id;
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
    from (values ('customer', c.email, coalesce(public.fn_inquiry_locale(t.inquiry_id), c.locale)),   -- the customer: the inquiry's language (28 Sep 2026)
          ('supplier', s.email, 'en')   -- suppliers are always written in English (founder, 28 Sep 2026)
         ) p(role, email, locale);
  return jsonb_build_object('dispute_id', d.id, 'opened', true, 'evidence_due', d.evidence_due);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_sales_engineer_writes(p_msg_type text, p_role text, p_email text, p_lead bigint, p_customer uuid, p_inquiry uuid, p_quote uuid, p_subject_en text, p_body_en text, p_subject_ar text DEFAULT NULL::text, p_body_ar text DEFAULT NULL::text, p_cc text[] DEFAULT '{}'::text[], p_subject_id text DEFAULT NULL::text, p_watch_until timestamp with time zone DEFAULT NULL::timestamp with time zone, p_extra jsonb DEFAULT '{}'::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_locale text;
begin
  -- A supplier: always English (fn_registered_locale answers 'en'). A customer: the language they chose
  -- when they created the inquiry this is about, else their registered one (founder, 28 Sep 2026).
  v_locale := coalesce(case when p_role = 'customer' then public.fn_inquiry_locale(p_inquiry) end,
                       public.fn_registered_locale(p_role, p_customer, p_lead, p_email), 'en');
  return public.fn_seat_handoff('sales_engineer', 'customer_support', 'delivery.request', 'notifications',
    coalesce(p_subject_id, p_msg_type || ':' || coalesce(p_quote::text, p_inquiry::text, p_lead::text, p_customer::text, 'x')),
    coalesce(p_extra, '{}'::jsonb) || jsonb_build_object(
      'msg_type', p_msg_type, 'recipient_role', p_role, 'to_email', p_email, 'cc', to_jsonb(coalesce(p_cc, '{}'::text[])),
      'supplier_id', p_lead, 'customer_id', p_customer, 'inquiry_id', p_inquiry, 'quote_id', p_quote,
      'locale', v_locale,
      'subject_en', p_subject_en, 'body_en', p_body_en || E'\n\nQuotesDone sales engineer',
      'subject_ar', p_subject_ar,
      'body_ar', case when p_body_ar is null then null else p_body_ar || E'\n\nمهندس المبيعات في QuotesDone' end,
      'watch_until', p_watch_until));
end $function$;
