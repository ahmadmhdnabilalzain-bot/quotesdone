-- THE REGISTERED LANGUAGE FOLLOWS EVERY MESSAGE UNTIL THE REVEAL (14 Sep 2026, agent: customer_support
-- - the outbox and every notice it carries are that seat's)
--
-- The founder, 14 Sep 2026 (founder_instruction #193): "are you making sure things are aligned in
-- terms of the language. so if someone registered while the language was arabic then arabic follows
-- through the whole workflow till the reveal. and if english then all english." The supplier side
-- follows the same rule with the supplier's own language; the two parties on one request can differ.
--
-- MEASURED BEFORE THIS FILE (production, 14 Sep 2026):
--   * No routine resolved a recipient's language. Five read customers.locale / leads.locale inline,
--     each its own way ('ar' exact in one, like 'ar%' in another, default 'en' everywhere).
--   * notifications had no language column, so the WhatsApp drainer could not choose the Arabic
--     template SID it already holds (wa_template_sids has ar+en for all five customer/supplier keys)
--     and always sent .en.
--   * At least 14 writers queue customer/supplier mail in English only, whatever the recipient
--     registered in: new_quote (the quote-ready notice), new_inquiry, rfq_addendum, job_awarded_other,
--     new_message, cancel_warning, quote_requirements_changed, quote_coaching, doc_final_notice,
--     doc_suspended, doc_received, and billing_answer (which passes no Arabic at all).
--
-- WHAT THIS CHANGES
--   1. fn_registered_locale(role, customer, lead, email) - THE resolver. 'ar' or 'en', read from the
--      registered row only. Edge functions reach it through _shared/registered_locale.ts (rpc), so
--      there is one definition, not one per language.
--   2. notifications.lang, stamped on insert by a04_notifications_speak_the_recipients_language from
--      that resolver for every customer/supplier row.
--   3. notification_copy - the Arabic and English wording per message type. When a writer queues a
--      message wholly in the other language (pure English to an Arabic recipient, or pure Arabic to an
--      English one), the trigger replaces it with the recipient's wording for that type, or with the
--      generic '*' row when the type has none. So no writer, present or future, can put a message in
--      the wrong language in front of a customer or supplier.
--   4. fn_language_mismatch(lang, text, allow[]) - what "in the wrong language" means, in one place:
--      the check (scripts/checks/language_follows_registration.mjs) reads it, and so can anything else.
--   5. fn_sales_engineer_writes, fn_supplier_notice and fn_sales_engineer_tells_customer_invoice_ready
--      read the resolver instead of their own inline lookups. These three definitions supersede the
--      ones in payments_are_the_accountant_and_the_seats_close_every_refund_together.sql,
--      a_supplier_who_leaves_holds_unanswered_is_warned_then_held.sql and
--      the_accountant_files_the_reveal_invoice_and_the_sales_engineer_tells_the_customer.sql; the
--      bodies are otherwise unchanged.
--
-- WHAT THIS DOES NOT CHANGE
--   * A MIXED message (Arabic with English sentences in it) is not rewritten here - there is no safe
--     automatic repair for it. The check finds it and fails; the writer is fixed at its source.
--   * Stripe's own invoice PDF: Stripe Invoicing has no Arabic (docs.stripe.com/invoicing/customize,
--     "Customer preferred languages"), so reveal_invoice gives an Arabic customer the QuotesDone
--     receipt in Arabic instead. That is in the edge function, not here.

-- ── 1. THE RESOLVER ─────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_registered_locale(p_role text, p_customer uuid default null,
                                                      p_lead bigint default null, p_email text default null)
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  -- null ONLY when nobody is registered under these keys (a sign-up in progress): the caller then uses
  -- the language of the page the person is registering on. A registered row always answers en or ar.
  select case when x is null then null when lower(x) like 'ar%' then 'ar' else 'en' end
    from (select case
      when p_role = 'customer' then coalesce(
        (select c.locale from public.customers c where c.id = p_customer),
        (select c.locale from public.customers c
          where p_email is not null and lower(c.email) = lower(btrim(p_email)) limit 1))
      when p_role = 'supplier' then coalesce(
        (select l.locale from public.leads l where l.id = p_lead),
        (select l.locale from public.leads l
          where p_email is not null
            and (lower(l.claimed_by) = lower(btrim(p_email)) or lower(l.email) = lower(btrim(p_email)))
          order by (lower(l.claimed_by) = lower(btrim(p_email))) desc nulls last, l.id limit 1))
    end as x) s
$fn$;
revoke execute on function public.fn_registered_locale(text, uuid, bigint, text) from public, anon, authenticated;
grant execute on function public.fn_registered_locale(text, uuid, bigint, text) to service_role;

-- ── 2. WHAT "THE WRONG LANGUAGE" MEANS ─────────────────────────────────────────────────────────
-- Returns null when p_text reads wholly in p_lang, otherwise the reason. Allowed inside Arabic: the
-- brand name, AED, PDF, Stripe, WhatsApp, links, e-mail addresses, request references (QD-…), and any
-- proper noun the caller passes in p_allow (a company or person name is not an English sentence).
create or replace function public.fn_language_mismatch(p_lang text, p_text text, p_allow text[] default '{}')
returns text language plpgsql immutable set search_path to 'public', 'pg_temp' as $fn$
declare t text := coalesce(p_text, ''); a text; w text;
begin
  foreach a in array coalesce(p_allow, '{}') loop
    if coalesce(btrim(a), '') <> '' then t := replace(t, a, ' '); end if;
  end loop;
  t := regexp_replace(t, 'https?://\S+', ' ', 'gi');
  t := regexp_replace(t, '\S+@\S+', ' ', 'g');
  t := regexp_replace(t, 'QD-[A-Za-z0-9-]+', ' ', 'g');
  t := regexp_replace(t, '\m(QuotesDone|AED|PDF|Stripe|WhatsApp|quotesdone\.com)\M', ' ', 'gi');
  -- An all-capitals code (SPC, BTU, CCTV, IP65, BS EN) is a standard or a product code, not English prose.
  t := regexp_replace(t, '\m[A-Z][A-Z0-9]{1,5}\M', ' ', 'g');
  if p_lang = 'ar' then
    if t !~ '[؀-ۿ]' then return 'no Arabic at all'; end if;
    w := substring(t from '[A-Za-z]{2,}(?:\s+[A-Za-z]{2,})*');
    if w is not null then return 'English inside Arabic: ' || left(w, 60); end if;
  else
    if t ~ '[؀-ۿ]' then return 'Arabic inside English: ' || left(substring(t from '[؀-ۿ][؀-ۿ\s]*'), 60); end if;
  end if;
  return null;
end $fn$;
revoke execute on function public.fn_language_mismatch(text, text, text[]) from public, anon, authenticated;
grant execute on function public.fn_language_mismatch(text, text, text[]) to service_role;

-- ── 3. THE LANGUAGE ON THE ROW, AND EACH TYPE'S WORDING IN BOTH ─────────────────────────────────
alter table public.notifications add column if not exists lang text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'notifications_lang_is_en_or_ar') then
    alter table public.notifications add constraint notifications_lang_is_en_or_ar check (lang is null or lang in ('en', 'ar'));
  end if;
end $$;
comment on column public.notifications.lang is
  'The recipient''s registered language (fn_registered_locale), stamped by a04_notifications_speak_the_recipients_language. Null for internal mail.';

create table if not exists public.notification_copy (
  type text primary key,
  subject_en text not null, body_en text not null,
  subject_ar text not null, body_ar text not null,
  note text,
  updated_at timestamptz not null default now());
alter table public.notification_copy enable row level security;
drop policy if exists notification_copy_service_role_only on public.notification_copy;
create policy notification_copy_service_role_only on public.notification_copy
  as permissive for all to public using (false) with check (false);
revoke all on public.notification_copy from anon, authenticated;
comment on table public.notification_copy is
  'Per-type wording in both languages. a04_notifications_speak_the_recipients_language uses it when a writer queued a customer/supplier message wholly in the other language. {ref} is the request reference. type ''*'' is the fallback.';

insert into public.notification_copy (type, subject_en, body_en, subject_ar, body_ar, note) values
('*', 'An update on QuotesDone',
      'You have a new update on QuotesDone {ref}. Sign in to your portal to see the details.',
      'تحديث جديد على QuotesDone',
      'لديك تحديث جديد على QuotesDone {ref}. سجّل الدخول إلى بوابتك للاطلاع على التفاصيل.',
      'fallback for any type without its own row'),
('new_quote', 'You have a new quote on QuotesDone',
      'A supplier submitted a quote for your request {ref}. Sign in to view the full quotation and compare.',
      'لديك عرض سعر جديد على QuotesDone',
      'قدّم أحد المورّدين عرض سعر لطلبك {ref}. سجّل الدخول لعرض عرض السعر كاملًا ومقارنته.',
      'supplier_api notifyNewQuote - the quote-ready notice'),
('new_message', 'New message on QuotesDone',
      'You have a new message on your project chat {ref}. Sign in to reply.',
      'رسالة جديدة على QuotesDone',
      'لديك رسالة جديدة في محادثة مشروعك {ref}. سجّل الدخول للرد.',
      'messages_api, both parties'),
('cancel_warning', 'A quick note about cancelled requests',
      'We noticed a few of your recent requests were cancelled. That is completely fine, but suppliers set aside real time to quote every request, so we kindly ask that you post requests you intend to proceed with. If you would like help scoping a job before posting, we are glad to assist.',
      'ملاحظة سريعة حول الطلبات الملغاة',
      'لاحظنا إلغاء عدد من طلباتك الأخيرة، ولا بأس في ذلك، لكن المورّدين يخصّصون وقتًا حقيقيًا لتسعير كل طلب، لذا نرجو نشر الطلبات التي تنوي المضي فيها. وإن أردت مساعدة في تحديد نطاق العمل قبل النشر فيسعدنا ذلك.',
      'fn_cancel_inquiry'),
('billing_answer', 'Your question about a charge',
      'We checked our records. The full detail of every amount is in the Billing section of your QuotesDone portal, and you can reply to this email with any question.',
      'بخصوص استفسارك عن رسوم',
      'راجعنا سجلاتنا. تجد التفاصيل الكاملة لكل مبلغ في قسم الفواتير في بوابتك على QuotesDone، ويمكنك الرد على هذه الرسالة بأي سؤال.',
      'fn_sales_engineer_acts_on_handoff passes no Arabic for this type'),
('new_inquiry', 'New job request on QuotesDone',
      'A customer is requesting quotes for work that matches your business {ref}. Sign in to your QuotesDone supplier portal to quote.',
      'طلب عمل جديد على QuotesDone',
      'يطلب أحد العملاء عروض أسعار لعمل يطابق نشاطك {ref}. سجّل الدخول إلى بوابة المورّد في QuotesDone لتقديم عرضك.',
      'customer_api matchAndNotify'),
('rfq_addendum', 'The customer added detail to a request you were invited to quote',
      'The customer added detail to the request {ref} you were invited to quote. Sign in to your QuotesDone supplier portal to see the full request and quote.',
      'أضاف العميل تفاصيل إلى طلب دُعيت لتسعيره',
      'أضاف العميل تفاصيل إلى الطلب {ref} الذي دُعيت لتسعيره. سجّل الدخول إلى بوابة المورّد في QuotesDone للاطلاع على الطلب كاملًا وتقديم عرضك.',
      'customer_api rfq_note'),
('job_awarded_other', 'Update on a job you quoted',
      'Thank you for quoting on {ref}. On this occasion the customer chose another supplier. New matching opportunities come through QuotesDone regularly - keep an eye on your supplier inbox.',
      'تحديث بخصوص عمل قدّمت عرضًا له',
      'شكرًا لتقديم عرضك على {ref}. اختار العميل هذه المرة مورّدًا آخر. تصلك فرص جديدة مطابقة عبر QuotesDone باستمرار، فتابع صندوق الوارد في بوابتك.',
      'customer_api notifyLosers'),
('quote_requirements_changed', 'The customer changed this request - please re-quote',
      'The customer changed the requirements of a request you had already quoted {ref}, so your quote was set back to draft. Open the request in your supplier portal, review what changed and submit an updated quote. Nothing has been deleted.',
      'غيّر العميل هذا الطلب - يُرجى إعادة التسعير',
      'غيّر العميل متطلبات طلب سبق أن سعّرته {ref}، فأُعيد عرضك إلى المسودة. افتح الطلب في بوابة المورّد وراجع ما تغيّر ثم قدّم عرضًا محدّثًا. لم يُحذف شيء.',
      'fn_edit_inquiry'),
('quote_coaching', 'Your quote needs a few more details before we can send it',
      'Thanks for your quote {ref}. To send it to the customer, please complete the missing details shown in your supplier portal. Detailed quotes with brands, specifications and an itemised breakdown win far more often.',
      'عرضك يحتاج إلى بعض التفاصيل قبل إرساله',
      'شكرًا على عرضك {ref}. لإرساله إلى العميل يُرجى استكمال التفاصيل الناقصة الظاهرة في بوابة المورّد. العروض المفصّلة بالعلامات التجارية والمواصفات وتفصيل البنود تفوز أكثر بكثير.',
      'fn_quote_coach'),
('doc_final_notice', 'Final reminder: a document on file is about to expire',
      'A document you hold on file with QuotesDone is about to expire. Upload the renewed copy in the Documents tab of your supplier portal, or reply to this email with it attached.',
      'تذكير أخير: مستند لديك على وشك الانتهاء',
      'أحد مستنداتك المسجّلة لدى QuotesDone على وشك الانتهاء. ارفع النسخة المجدّدة من تبويب المستندات في بوابة المورّد، أو ردّ على هذه الرسالة مرفقًا بها.',
      'fn_doc_final_notice'),
('doc_suspended', 'Your QuotesDone account is paused - a document has expired',
      'A document on file has expired, so your account is paused and you will not receive new customer requests until it is renewed. Upload the renewed copy in the Documents tab of your supplier portal, or reply to this email with it attached. Your account is restored automatically, with no fee.',
      'حسابك في QuotesDone متوقف مؤقتًا - انتهت صلاحية مستند',
      'انتهت صلاحية أحد مستنداتك المسجّلة، فأُوقف حسابك مؤقتًا ولن تصلك طلبات جديدة حتى تجديده. ارفع النسخة المجدّدة من تبويب المستندات في بوابة المورّد أو ردّ على هذه الرسالة مرفقًا بها. يُعاد تفعيل حسابك تلقائيًا ودون رسوم.',
      'fn_reconcile_doc_blocks'),
('doc_received', 'We received your document',
      'Thank you - we received your document and updated your records.',
      'استلمنا مستندك',
      'شكرًا لك، استلمنا مستندك وحدّثنا سجلاتك.',
      'resend_inbound')
on conflict (type) do update set subject_en = excluded.subject_en, body_en = excluded.body_en,
  subject_ar = excluded.subject_ar, body_ar = excluded.body_ar, note = excluded.note, updated_at = now();

-- ── 4. THE ROW SPEAKS THE RECIPIENT'S LANGUAGE ─────────────────────────────────────────────────
-- a04: before a05 (sender of record), a10 (founder mail policy), the demo guard and the demo capture,
-- so every one of them sees the final wording. trg_wa_fanout is AFTER INSERT and copies NEW, so the
-- WhatsApp twin inherits the corrected text and is stamped again by this same trigger.
create or replace function public.fn_notifications_speak_the_recipients_language()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_all text; v_ar boolean; v_latin boolean; c public.notification_copy; v_ref text;
begin
  if coalesce(new.to_role, '') not in ('customer', 'supplier') then return new; end if;
  if new.lang is null or new.lang not in ('en', 'ar') then
    new.lang := coalesce(public.fn_registered_locale(new.to_role, null, new.lead_id, new.to_email), 'en');
  end if;
  v_all := coalesce(new.subject, '') || ' ' || coalesce(new.body, '');
  v_ar := v_all ~ '[؀-ۿ]';
  -- coalesce: fn_language_mismatch answers null for pure Arabic, and a null here would make the
  -- pure-Arabic-to-an-English-recipient case below evaluate to null and never be corrected.
  v_latin := coalesce(public.fn_language_mismatch('ar', v_all) like 'English inside Arabic%', false)
             or (not v_ar and v_all ~ '[A-Za-z]{2,}');
  if (new.lang = 'ar' and not v_ar) or (new.lang = 'en' and v_ar and not v_latin) then
    select * into c from public.notification_copy where type = new.type;
    if not found then select * into c from public.notification_copy where type = '*'; end if;
    if found then
      v_ref := case when new.inquiry_id is not null
                    then 'QD-' || upper(left(replace(new.inquiry_id::text, '-', ''), 8)) end;
      new.subject := case when new.lang = 'ar' then c.subject_ar else c.subject_en end;
      new.body := replace(case when new.lang = 'ar' then c.body_ar else c.body_en end,
                          ' {ref}', coalesce(' ' || v_ref, ''));
      new.html := null;   -- a pre-rendered html copy would still carry the old language
    end if;
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_notifications_speak_the_recipients_language() from public, anon, authenticated;
drop trigger if exists a04_notifications_speak_the_recipients_language on public.notifications;
create trigger a04_notifications_speak_the_recipients_language before insert on public.notifications
  for each row execute function public.fn_notifications_speak_the_recipients_language();

-- ── 5. THE THREE LOCALE READERS NOW ASK THE RESOLVER ───────────────────────────────────────────
create or replace function public.fn_sales_engineer_writes(
  p_msg_type text, p_role text, p_email text, p_lead bigint, p_customer uuid, p_inquiry uuid, p_quote uuid,
  p_subject_en text, p_body_en text, p_subject_ar text default null, p_body_ar text default null,
  p_cc text[] default '{}', p_subject_id text default null, p_watch_until timestamptz default null,
  p_extra jsonb default '{}'::jsonb)
-- bigint: what production returns (the id fn_seat_handoff gives back). The canonical file above says
-- jsonb and was never what the database held; a rewrite to jsonb is refused by Postgres.
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_locale text;
begin
  v_locale := coalesce(public.fn_registered_locale(p_role, p_customer, p_lead, p_email), 'en');
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
end $fn$;

create or replace function public.fn_supplier_notice(p_lead bigint, p_type text, p_subject_en text, p_body_en text,
                                                     p_subject_ar text, p_body_ar text, p_inquiry uuid default null, p_quote uuid default null)
returns integer language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare l record; v_ar boolean; v_subject text; v_body text; n int := 0;
begin
  select id, company_name,
         coalesce(nullif(btrim(claimed_by), ''), nullif(btrim(email), '')) as mail,
         coalesce(nullif(btrim(whatsapp), ''), nullif(btrim(phone), ''))  as tel
    into l from public.leads where id = p_lead;
  if not found then return 0; end if;
  v_ar := public.fn_registered_locale('supplier', null, p_lead) = 'ar';
  v_subject := case when v_ar then p_subject_ar else p_subject_en end;
  v_body := replace(case when v_ar then p_body_ar else p_body_en end, '{company}',
                    coalesce(nullif(btrim(l.company_name), ''), case when v_ar then 'شريكنا' else 'partner' end));
  if l.mail is not null then
    insert into public.notifications (type, kind, to_email, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status, requested_by, sender, lang)
    values (p_type, 'sales_engineer_' || p_type, l.mail, 'supplier', p_lead, p_inquiry, p_quote, 'email', v_subject, v_body, 'queued', 'sales_engineer', 'customer_support',
            case when v_ar then 'ar' else 'en' end);
    n := n + 1;
  end if;
  -- trg_wa_fanout has already made a WhatsApp twin for a supplier who opted in; otherwise queue one.
  if l.tel is not null and not exists (select 1 from public.notifications
                                        where channel = 'whatsapp' and lead_id = p_lead and type = p_type and created_at = now()) then
    insert into public.notifications (type, kind, to_email, to_phone, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status, requested_by, sender, lang)
    values (p_type, 'sales_engineer_' || p_type, l.mail, l.tel, 'supplier', p_lead, p_inquiry, p_quote, 'whatsapp', v_subject, v_body, 'queued', 'sales_engineer', 'customer_support',
            case when v_ar then 'ar' else 'en' end);
    n := n + 1;
  end if;
  return n;
end $fn$;

create or replace function public.fn_sales_engineer_tells_customer_invoice_ready()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  c record;
  v_ar boolean;
begin
  if new.kind <> 'handoff' or coalesce(new.detail->>'subject', '') <> 'reveal_invoice' then return new; end if;
  select id, email into c from public.customers where id = (new.detail->>'customer_id')::uuid;
  if c.email is not null and c.email ~ '@' then
    v_ar := public.fn_registered_locale('customer', c.id) = 'ar';
    insert into public.notifications (type, to_email, to_role, inquiry_id, quote_id, subject, body, lang)
    values ('invoice_ready', c.email, 'customer',
            (new.detail->>'inquiry_id')::uuid, (new.detail->>'quote_id')::uuid,
            case when v_ar then 'فاتورتك جاهزة' else 'Your invoice is ready' end,
            case when v_ar
              then 'فاتورة رسوم الكشف التي دفعتها أصبحت في حسابك على QuotesDone. افتحها في أي وقت من زر «الفاتورة» على العرض الذي كشفته، أو من «المستندات» ضمن «الفواتير».'
              else 'The invoice for the reveal fee you paid is now in your QuotesDone account. Open it any time from the "Invoice (PDF)" button on the quote you revealed, or under Invoices in Documents.'
            end,
            case when v_ar then 'ar' else 'en' end);
  end if;
  update public.agent_actions
     set status = 'done', decided_at = now(), decided_by = 'sales_engineer'
   where id = new.id;
  return new;
end
$fn$;

-- ── 6. PROOF, CLEANED UP (this file defines things, so it must not raise) ───────────────────────
do $$
declare r text;
begin
  if public.fn_language_mismatch('ar', 'لديك عرض سعر جديد على QuotesDone QD-ABCD1234') is not null then raise exception 'mismatch: pure Arabic flagged'; end if;
  if public.fn_language_mismatch('ar', 'لديك عرض Log in to view') is null then raise exception 'mismatch: English fragment missed'; end if;
  if public.fn_language_mismatch('en', 'You have a new quote') is not null then raise exception 'mismatch: pure English flagged'; end if;
  if public.fn_language_mismatch('en', 'You have عرض') is null then raise exception 'mismatch: Arabic fragment missed'; end if;
  select public.fn_registered_locale('customer', null, null, 'nobody-at-all@example.invalid') into r;
  if r is not null then raise exception 'resolver: an unregistered address must read null, got %', r; end if;
  raise notice 'the_registered_language_follows_every_message_until_the_reveal: resolver and mismatch rules hold';
end $$;
