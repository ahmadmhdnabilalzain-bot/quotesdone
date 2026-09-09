-- THE SALES ENGINEER OWNS BOTH PORTALS, END TO END.
--
-- The founder, 9 Sep 2026: "make sure that all website related registration to suppliers and
-- customers are now linked to this agent. he is the one to follow up on everything. he does the
-- comparison reports, he basically fill the reports for suppliers and customers about jobs
-- won/supplier ratings/customer total spend literally everything related to both portals."
--
-- WHAT function_owner ACTUALLY IS, because moving 19 rows deserves the reason. It is not routing --
-- no request is dispatched by it. It is the REGISTRY OF RESPONSIBILITY, and it is what a sweep reads
-- before deleting. On 8 Sep a sweep read an incomplete registry and took the eight portal functions
-- with it, and PR #532 had to put them back. So an owner column that says 'website' for the
-- supplier registration flow is not a cosmetic mislabel: it is the thing that decides whether a
-- future cleanup treats these as marketing pages nobody owns.
--
-- WHAT MOVES (19), and each belongs to one of the three duties he named:
--
--   REGISTRATION      supplier_onboard, supplier_api, supplier_portal, claim_lookup, kyc,
--                     customer_api, customer_portal
--   FOLLOW-UP         inquiry_intake, procurement_api, project_api, rfq_flag, supplier_ack,
--                     messages_api, customer_documents, supplier_catalog_ingest
--   REPORTS           quote_compare (the comparison report he names explicitly),
--                     customer_intelligence (spend, forecast, supplier performance),
--                     negotiation_assistant, pdf_native (the report writer)
--
-- WHAT DELIBERATELY DOES NOT MOVE, and why each is a decision rather than an oversight:
--
--   Marketing surfaces stay 'website': about, faq, home, home-ar, i18n_get, legal, portal,
--   public_stats, contact_submit, role_guard, resilience_ping. A page that renders copy is not a
--   portal duty.
--
--   PAYMENTS stay put -- stripe_checkout, stripe_confirm, stripe_webhook, stripe_setup,
--   stripe_setup_page, supplier_pay, refunds_api, refund_flow, reveal_invoice, quote_pdf. The
--   founder's 9 Sep ruling holds these for a future accountant agent: "fine leave payments stuff so
--   we link them later to the new accountant". Reveal invoicing is money, not a portal report.
--
--   OTP stays put -- auth_api, login_otp, mobile_otp, voice_otp, voice_otp_capture, sup_dob,
--   send_sms. Same ruling: "otp will go to another agent also later". Signing in is not registering.
--
--   The CHANNELS stay with customer_support -- ai_gateway, email_*, send_outbox, send_whatsapp,
--   site_assistant, wa_*, resend_inbound, inbound_email, transcribe, license_extract, extract_text,
--   doc_extract. The build prompt is explicit: "Customer Support is the communication bridge... Sales
--   determines the technical questions and validates responses; Support owns channel delivery and
--   conversation continuity." Sales must never own the pipe it speaks through.
--
--   The four recovered DOCUMENT functions (cad_convert, drawing_boq, drawing_redact, quote_extract)
--   are being restored in a separate change that assigns their owners in its own file. They are left
--   alone here rather than raced for -- two files claiming the same slug is exactly the conflict this
--   registry exists to prevent.
--
-- Measured before writing: website 53, customer_support 16, ceo 1, sales_engineer 1.
-- After this file: website 34, customer_support 16, ceo 1, sales_engineer 20.
--
--   node scripts/apply_sql.mjs scripts/sql/the_sales_engineer_owns_both_portals_end_to_end.sql --apply

begin;

update public.function_owner
   set owner = 'sales_engineer',
       note  = case function_slug
         when 'supplier_onboard'        then 'Supplier registration interview. Sales conducts intake on both sides.'
         when 'supplier_api'            then 'The supplier write path: claim, profile, documents, capability. Sales owns supplier identity and capability truth.'
         when 'supplier_portal'         then 'The supplier''s own view of its state: documents, expiries, jobs. Sales fills it.'
         when 'claim_lookup'            then 'Supplier account claiming -- the first step of registration.'
         when 'kyc'                     then 'Identity verification at registration.'
         when 'customer_api'            then 'The customer write path: registration, inquiries, reveal. Sales owns customer intake.'
         when 'customer_portal'         then 'The customer''s own view: inquiries, quotes, spend. Sales fills it.'
         when 'inquiry_intake'          then 'Technical intake conversation. Sales determines the questions.'
         when 'procurement_api'         then 'Customer-side purchase approvals and orders -- follow-up on a live inquiry.'
         when 'project_api'             then 'Customer projects: the frame the follow-up hangs on.'
         when 'rfq_flag'                then 'A supplier says the brief is unclear. That is a Sales question, answered by Sales.'
         when 'supplier_ack'            then 'Supplier confirms contact with the customer. Follow-up evidence.'
         when 'messages_api'            then 'Inquiry-scoped messages between the parties, which Sales follows up on.'
         when 'customer_documents'      then 'Customer document access. Sales owns document interpretation.'
         when 'supplier_catalog_ingest' then 'Supplier catalogues into structured product claims. Sales owns capability evidence.'
         when 'quote_compare'           then 'THE COMPARISON REPORT the founder names explicitly. Reused, not rebuilt.'
         when 'customer_intelligence'   then 'Customer spend, forecast and supplier performance -- the customer-facing report.'
         when 'negotiation_assistant'   then 'Quote guidance and market context on a live inquiry.'
         when 'pdf_native'              then 'The report writer. Sales fills the reports, so Sales owns the thing that renders them.'
         else note end
 where function_slug in (
   'supplier_onboard','supplier_api','supplier_portal','claim_lookup','kyc',
   'customer_api','customer_portal','inquiry_intake','procurement_api','project_api',
   'rfq_flag','supplier_ack','messages_api','customer_documents','supplier_catalog_ingest',
   'quote_compare','customer_intelligence','negotiation_assistant','pdf_native'
 );

-- THE CLOSING ASSERTION. A file that was supposed to move ownership and moved none of it, or moved
-- something it should not have, must say so rather than commit quietly.
do $check$
declare
  v_sales int; v_website int; v_support int; v_payments_moved int; v_otp_moved int; v_channels_moved int;
begin
  select count(*) into v_sales   from public.function_owner where owner = 'sales_engineer';
  select count(*) into v_website from public.function_owner where owner = 'website';
  select count(*) into v_support from public.function_owner where owner = 'customer_support';

  -- The three sets that must NOT have moved, checked by name rather than by count.
  select count(*) into v_payments_moved from public.function_owner
   where owner = 'sales_engineer' and function_slug in
     ('stripe_checkout','stripe_confirm','stripe_webhook','stripe_setup','stripe_setup_page',
      'supplier_pay','refunds_api','refund_flow','reveal_invoice','quote_pdf');

  select count(*) into v_otp_moved from public.function_owner
   where owner = 'sales_engineer' and function_slug in
     ('auth_api','login_otp','mobile_otp','voice_otp','voice_otp_capture','sup_dob','send_sms');

  select count(*) into v_channels_moved from public.function_owner
   where owner = 'sales_engineer' and function_slug in
     ('ai_gateway','send_outbox','send_whatsapp','site_assistant','wa_inbound','resend_inbound',
      'inbound_email','email_cron','email_triage','transcribe','license_extract','extract_text','doc_extract');

  if v_sales <> 20 then
    raise exception 'OWNERSHIP DID NOT LAND: sales_engineer owns % function(s), expected 20 (19 moved + its own runtime)', v_sales;
  end if;

  if v_payments_moved > 0 then
    raise exception 'PAYMENTS MOVED (% slug(s)) -- they are held for the future accountant agent', v_payments_moved;
  end if;
  if v_otp_moved > 0 then
    raise exception 'OTP MOVED (% slug(s)) -- it is held for a future seat', v_otp_moved;
  end if;
  if v_channels_moved > 0 then
    raise exception 'A CHANNEL MOVED (% slug(s)) -- Support owns delivery; Sales must never own the pipe it speaks through', v_channels_moved;
  end if;

  raise notice 'ownership: sales_engineer % · website % · customer_support % · payments/otp/channels all unmoved',
    v_sales, v_website, v_support;
end
$check$;

commit;
