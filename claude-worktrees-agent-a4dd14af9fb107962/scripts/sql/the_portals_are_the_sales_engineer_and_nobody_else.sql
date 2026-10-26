-- THE PORTALS ARE THE SALES ENGINEER, AND NOBODY ELSE.
--
-- Assigned: sales_engineer (the seat whose wiring this is), carried out for the ceo.
--
-- The founder, 14 Sep 2026, verbatim: "its always the sales agent. no other agent is involved in
-- customer or supplier portal. make sure the wiring is made this way."
--
-- MEASURED BEFORE WRITING (14 Sep 2026, production htdblwldjkcgjvmqkbeh):
--
--   function_owner  every slug the /me and /portal UI calls is sales_engineer EXCEPT the platform
--                   services below, and four document functions the portal functions call on the
--                   customer's and supplier's behalf were still 'website':
--                     cad_convert     <- customer_api, supplier_catalog_ingest (drawing / catalogue upload)
--                     drawing_redact  <- customer_api (the buyer's drawing, before suppliers see it)
--                     drawing_boq     <- customer_api (the BOQ shown back in the buyer's chat)
--                     quote_extract   <- supplier_api (the supplier's quotation upload)
--                   five_document_functions_come_back_with_owners.sql gave them 'website' because
--                   their callers were 'website' functions on 9 Sep. Those callers moved to
--                   sales_engineer the same day (the_sales_engineer_owns_both_portals_end_to_end.sql);
--                   these four were left behind. They move now.
--
--   llm_seat_binding  fn_llm_log attributes model spend to the seat bound here when the caller
--                   declares none. Two portal functions were bound to customer_support:
--                     messages_api    the inquiry-scoped chat the /me and /portal UI calls
--                     supplier_ack    the supplier's acknowledgement, reached from customer_api/supplier_api
--                   function_owner already said sales_engineer for both; the binding contradicted it.
--
-- WHAT DOES NOT MOVE, BY THE STANDING GUARD (the_sales_engineer_owns_both_portals_end_to_end.sql):
-- payments, OTP and channel slugs never land on sales_engineer. The portal reaches some of them, and
-- they are PLATFORM SERVICES the portal calls, not an agent acting in it:
--   payments  stripe_checkout, stripe_confirm, supplier_pay           (accountant — founder, 9 Sep)
--   sign-in   login_otp, send_sms, role_guard                         (website  — "otp will go to another agent")
--   channels  transcribe, wa_optin_set                                (customer_support — the pipe, not the voice)
-- scripts/checks/the_portals_are_the_sales_engineer.test.mjs names the same list and fails on anything else.
--
--   node scripts/apply_sql.mjs scripts/sql/the_portals_are_the_sales_engineer_and_nobody_else.sql --apply --ddl

begin;

update public.function_owner
   set owner = 'sales_engineer',
       note  = case function_slug
         when 'cad_convert'    then 'Rasteriser for DWG/DXF via CloudConvert, called by customer_api and supplier_catalog_ingest on the portal upload paths. Portal work is the sales engineer''s (founder, 14 Sep 2026).'
         when 'drawing_redact' then 'Blacks out identifying regions on the buyer''s drawing before competing suppliers see it; called by customer_api only. Fails closed. Portal work is the sales engineer''s (founder, 14 Sep 2026).'
         when 'drawing_boq'    then 'Draft bill of quantities read off the buyer''s drawing, shown back in customer_api''s chat. An estimate, never a certified take-off. Portal work is the sales engineer''s (founder, 14 Sep 2026).'
         when 'quote_extract'  then 'Reads and anonymises a supplier''s uploaded quotation for supplier_api. Portal work is the sales engineer''s (founder, 14 Sep 2026).'
       end
 where function_slug in ('cad_convert','drawing_redact','drawing_boq','quote_extract');

update public.llm_seat_binding
   set seat = 'sales_engineer',
       note = case fn
         when 'messages_api' then 'Inquiry-scoped chat in both portals. Founder 14 Sep: "its always the sales agent" in either portal.'
         when 'supplier_ack' then 'Supplier acknowledgement on a live inquiry. Founder 14 Sep: "its always the sales agent" in either portal.'
       end
 where fn in ('messages_api','supplier_ack');

-- His words, in the register the moment they are acted on.
insert into public.founder_instruction (said_at, instruction, subject, status, evidence)
select '2026-09-14T00:00:00Z',
       'its always the sales agent. no other agent is involved in customer or supplier portal. make sure the wiring is made this way.',
       'portals are the sales engineer',
       'closed',
       'scripts/sql/the_portals_are_the_sales_engineer_and_nobody_else.sql; scripts/checks/the_portals_are_the_sales_engineer.test.mjs'
 where not exists (select 1 from public.founder_instruction
                    where instruction like 'its always the sales agent. no other agent is involved%');

do $check$
declare v_bad text; v_guard int; v_bind text;
begin
  select string_agg(function_slug || '=' || owner, ', ') into v_bad
    from public.function_owner
   where function_slug in ('cad_convert','drawing_redact','drawing_boq','quote_extract',
                           'customer_api','customer_portal','customer_documents','customer_intelligence',
                           'inquiry_intake','kyc','messages_api','negotiation_assistant','procurement_api',
                           'project_api','quote_compare','supplier_api','supplier_catalog_ingest',
                           'supplier_onboard','supplier_portal','claim_lookup','rfq_flag','supplier_ack',
                           'sales_engineer','pdf_native')
     and owner <> 'sales_engineer';
  if v_bad is not null then raise exception 'A PORTAL FUNCTION IS OWNED BY ANOTHER SEAT: %', v_bad; end if;

  -- The standing guard, re-asserted: no payment, OTP or channel slug on sales_engineer.
  select count(*) into v_guard from public.function_owner
   where owner = 'sales_engineer' and function_slug in
     ('stripe_checkout','stripe_confirm','stripe_webhook','stripe_setup','stripe_setup_page','supplier_pay',
      'refunds_api','refund_flow','reveal_invoice','quote_pdf',
      'auth_api','login_otp','mobile_otp','voice_otp','voice_otp_capture','sup_dob','send_sms',
      'ai_gateway','send_outbox','send_whatsapp','site_assistant','wa_inbound','wa_optin_set','resend_inbound',
      'inbound_email','email_cron','email_triage','transcribe','license_extract','extract_text','doc_extract');
  if v_guard > 0 then raise exception 'THE GUARD WAS BROKEN: % payment/OTP/channel slug(s) on sales_engineer', v_guard; end if;

  select string_agg(fn || '=' || seat, ', ') into v_bind from public.llm_seat_binding
   where fn in ('messages_api','supplier_ack') and seat <> 'sales_engineer';
  if v_bind is not null then raise exception 'SEAT BINDING DID NOT LAND: %', v_bind; end if;

  raise notice 'portals: every portal function owned by sales_engineer; guard intact; bindings moved';
end
$check$;

commit;
