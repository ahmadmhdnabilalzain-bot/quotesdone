-- A CUSTOMER HEARS THE REVEAL AND ITS INVOICE IN THE INQUIRY'S LANGUAGE (19 Oct 2026, agent: sales_engineer).
--
-- Ruling (founder, 28 Sep 2026): a customer is written in the language of the inquiry the message is
-- about, else their registered one; a supplier is always English (ruling 1008).
--
-- MEASURED 19 Oct 2026. Every reveal_receipt on production (2 email rows) is English, on English
-- inquiries: an Arabic customer has never been sent an Arabic reveal notice. fn_sales_engineer_writes
-- (reveal_receipt) already chose by the inquiry, but fn_sales_engineer_tells_customer_invoice_ready
-- (invoice_ready) chose by the REGISTERED locale only, so an English-registered customer who asked in
-- Arabic got the invoice email in English, then the language trigger swapped in the generic copy.
--
-- The choice now lives in ONE routine, fn_customer_notice_locale, used by both writers:
--   inquiry language (en|ar) -> registered customer locale -> 'en'.
-- The Arabic wording of both notices is unchanged (already in scripts/checks/arabic_reviewed_strings.json).
--
-- Prevented by: scripts/checks/a_customer_hears_the_reveal_and_its_invoice_in_the_inquiry_language.test.mjs

create or replace function public.fn_customer_notice_locale(p_inquiry uuid, p_customer uuid)
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(public.fn_inquiry_locale(p_inquiry),
                  public.fn_registered_locale('customer', p_customer, null, null),
                  'en')
$fn$;
revoke execute on function public.fn_customer_notice_locale(uuid, uuid) from public, anon, authenticated;

create or replace function public.fn_sales_engineer_writes(p_msg_type text, p_role text, p_email text, p_lead bigint, p_customer uuid, p_inquiry uuid, p_quote uuid, p_subject_en text, p_body_en text, p_subject_ar text DEFAULT NULL::text, p_body_ar text DEFAULT NULL::text, p_cc text[] DEFAULT '{}'::text[], p_subject_id text DEFAULT NULL::text, p_watch_until timestamp with time zone DEFAULT NULL::timestamp with time zone, p_extra jsonb DEFAULT '{}'::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_locale text;
begin
  -- A supplier: always English (fn_registered_locale answers 'en'). A customer: fn_customer_notice_locale
  -- (the inquiry's language, else the registered one, else English).
  v_locale := case when p_role = 'customer' then public.fn_customer_notice_locale(p_inquiry, p_customer)
                   else coalesce(public.fn_registered_locale(p_role, p_customer, p_lead, p_email), 'en') end;
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

create or replace function public.fn_sales_engineer_tells_customer_invoice_ready()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c record;
  v_ar boolean;
begin
  if new.kind <> 'handoff' or coalesce(new.detail->>'subject', '') <> 'reveal_invoice' then return new; end if;
  select id, email into c from public.customers where id = (new.detail->>'customer_id')::uuid;
  if c.email is not null and c.email ~ '@' then
    v_ar := public.fn_customer_notice_locale((new.detail->>'inquiry_id')::uuid, c.id) = 'ar';
    insert into public.notifications (type, to_email, to_role, inquiry_id, quote_id, subject, body, lang)
    values ('invoice_ready', c.email, 'customer',
            (new.detail->>'inquiry_id')::uuid, (new.detail->>'quote_id')::uuid,
            case when v_ar then 'فاتورتكم جاهزة' else 'Your invoice is ready' end,
            case when v_ar
              then 'أصبحت فاتورة رسوم الكشف التي سددتموها متاحة في حسابكم على QuotesDone، ويمكنكم فتحها في أي وقت من زر «الفاتورة» على العرض الذي كشفتموه، أو من «المستندات» ضمن «الفواتير».'
              else 'The invoice for the reveal fee you paid is now in your QuotesDone account. Open it any time from the "Invoice (PDF)" button on the quote you revealed, or under Invoices in Documents.'
            end,
            case when v_ar then 'ar' else 'en' end);
  end if;
  update public.agent_actions
     set status = 'done', decided_at = now(), decided_by = 'sales_engineer'
   where id = new.id;
  return new;
end
$function$;

select case
  when public.fn_customer_notice_locale(null, null) <> 'en' then 'PROBE FAILED: no inquiry and no customer must fall back to en'
  when exists (select 1 from public.inquiries where lang = 'ar')
       and public.fn_customer_notice_locale((select id from public.inquiries where lang = 'ar' limit 1), null) <> 'ar'
    then 'PROBE FAILED: an Arabic inquiry must give ar'
  when exists (select 1 from public.inquiries where lang = 'en')
       and public.fn_customer_notice_locale((select id from public.inquiries where lang = 'en' limit 1),
             (select id from public.customers where locale like 'ar%' limit 1)) <> 'en'
    then 'PROBE FAILED: an English inquiry must give en even to an Arabic-registered customer'
  else 'PROBE OK' end as verdict;
