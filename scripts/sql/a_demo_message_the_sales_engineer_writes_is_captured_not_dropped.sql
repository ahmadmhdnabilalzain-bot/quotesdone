-- A DEMO MESSAGE THE SALES ENGINEER WRITES IS CAPTURED, NOT DROPPED.
-- 27 Oct 2026. Seat: sales_engineer (the writer); found by the accountant's fixer proving the reveal path.
--
-- MEASURED 27 Oct 2026 (production, rolled-back replay of scripts/checks/language_follows_registration.mjs):
-- the walk's reveal_receipt (Arabic and English ZZ DEMO customers) and billing_answer were never produced, and
-- nothing raised. fn_sales_engineer_writes hands every message to customer_support through fn_seat_handoff, and
-- since ruling 1199 fn_seat_handoff files nothing for demo work and returns NULL - so the message was silently
-- dropped, and the sandbox could no longer prove that a customer hears the reveal in their language.
--
-- The same defect, at customer_support's door, was fixed in a_demo_delivery_request_is_captured_not_refused.sql:
-- when no handoff is filed (demo), the row is written directly and CAPTURED (status suppressed, never sent). This
-- does the same at the sales engineer's door, with the words customer_support would have chosen
-- (fn_customer_support_acts_on_handoff: Arabic when the locale is ar and an Arabic body exists, else English).
-- Real (non-demo) messages take the unchanged handoff path; the return value is unchanged (NULL for demo).
--
-- Prevented by: scripts/checks/language_follows_registration.mjs (the walk asserts reveal_receipt for both
-- customers and billing_answer for the Arabic one, in the registered language, captured).
-- Pending: scripts/sql/pending/a_demo_message_the_sales_engineer_writes_is_captured_not_dropped.txt

create or replace function public.fn_sales_engineer_writes(p_msg_type text, p_role text, p_email text, p_lead bigint, p_customer uuid, p_inquiry uuid, p_quote uuid, p_subject_en text, p_body_en text, p_subject_ar text DEFAULT NULL::text, p_body_ar text DEFAULT NULL::text, p_cc text[] DEFAULT '{}'::text[], p_subject_id text DEFAULT NULL::text, p_watch_until timestamp with time zone DEFAULT NULL::timestamp with time zone, p_extra jsonb DEFAULT '{}'::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_locale text; v_h bigint; v_ar boolean;
begin
  -- A supplier: always English (fn_registered_locale answers 'en'). A customer: fn_customer_notice_locale
  -- (the inquiry's language, else the registered one, else English).
  v_locale := case when p_role = 'customer' then public.fn_customer_notice_locale(p_inquiry, p_customer)
                   else coalesce(public.fn_registered_locale(p_role, p_customer, p_lead, p_email), 'en') end;
  v_h := public.fn_seat_handoff('sales_engineer', 'customer_support', 'delivery.request', 'notifications',
    coalesce(p_subject_id, p_msg_type || ':' || coalesce(p_quote::text, p_inquiry::text, p_lead::text, p_customer::text, 'x')),
    coalesce(p_extra, '{}'::jsonb) || jsonb_build_object(
      'msg_type', p_msg_type, 'recipient_role', p_role, 'to_email', p_email, 'cc', to_jsonb(coalesce(p_cc, '{}'::text[])),
      'supplier_id', p_lead, 'customer_id', p_customer, 'inquiry_id', p_inquiry, 'quote_id', p_quote,
      'locale', v_locale,
      'subject_en', p_subject_en, 'body_en', p_body_en || E'\n\nQuotesDone sales engineer',
      'subject_ar', p_subject_ar,
      'body_ar', case when p_body_ar is null then null else p_body_ar || E'\n\nمهندس المبيعات في QuotesDone' end,
      'watch_until', p_watch_until));

  -- demo work (ruling 1199): no handoff was filed; the message is written for the record and captured, never sent
  if v_h is null and coalesce(p_email, '') ~ '@' then
    v_ar := v_locale = 'ar' and p_body_ar is not null;
    insert into public.notifications (type, kind, to_email, cc_emails, to_role, lead_id, inquiry_id, quote_id, channel,
                                      subject, body, status, last_error, requested_by)
    values (p_msg_type, p_msg_type, p_email, coalesce(p_cc, '{}'::text[]), p_role, p_lead, p_inquiry, p_quote, 'email',
            case when v_ar then coalesce(p_subject_ar, p_subject_en) else p_subject_en end,
            case when v_ar then p_body_ar || E'\n\nمهندس المبيعات في QuotesDone' else p_body_en || E'\n\nQuotesDone sales engineer' end,
            'suppressed', 'demo work (ruling 1199): written for the record, never sent', 'sales_engineer');
  end if;
  return v_h;
end $function$;

-- CREATE OR REPLACE keeps the routine's ACL; repeated so the file stands alone.
revoke execute on function public.fn_sales_engineer_writes(text, text, text, bigint, uuid, uuid, uuid, text, text, text, text, text[], text, timestamp with time zone, jsonb) from public, anon, authenticated;
