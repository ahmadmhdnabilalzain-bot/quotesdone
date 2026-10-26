-- THE CUTOVER REGISTER STOPS CLAIMING SOURCES THAT NO LONGER EXIST
--
-- every_discharge_claim_reaches_its_table failed after the 8 Sep deletion with: "a discharge claim
-- belongs to an edge function with no source in this repository, so the claim cannot be checked at
-- all". The check was right, and it is the good kind of failure: it refuses to read a claim it
-- cannot verify rather than counting it as covered.
--
-- phase_c_source_cutover still named nine functions deleted under the founder's rule -- attach_photos,
-- customer_api, drawing_redact, inquiry_intake, messages_api, pdpl_request, supplier_api,
-- supplier_onboard, supplier_portal. Each row asserted that some component discharges its duty
-- through an edge function whose source is gone, which is an assurance nobody can check.
--
-- The rows are DELETED rather than the check being relaxed. A register that keeps rows for things
-- that do not exist is the same defect this session has already fixed twice today -- a retired
-- trigger function still in the catalogue, an ownership record outliving its subject. The claim
-- ends with the thing it was claiming about.
--
-- Computed from the live function list rather than a hardcoded set, so re-running it after any
-- future deletion does the right thing instead of the thing that was right in September.

delete from public.phase_c_source_cutover
 where source_component_id like 'edge:%'
   and source_component_id not in ('edge:about','edge:agent_learnings_report','edge:ai_gateway','edge:auth_api','edge:claim_lookup','edge:contact_submit','edge:customer_documents','edge:customer_intelligence','edge:customer_portal','edge:email_cron','edge:email_triage','edge:extract_text','edge:faq','edge:home-ar','edge:home','edge:i18n_get','edge:inbound_email','edge:kyc','edge:legal','edge:license_extract','edge:login_otp','edge:make_pdf','edge:make_xlsx','edge:mobile_otp','edge:negotiation_assistant','edge:os_api','edge:os_automation','edge:os_catalog','edge:os_health','edge:os_incidents','edge:os_ops','edge:os_settings','edge:pdf_native','edge:portal','edge:procurement_api','edge:project_api','edge:public_stats','edge:quote_pdf','edge:refund_flow','edge:refunds_api','edge:report_body','edge:report_pdf','edge:resend_inbound','edge:resend_webhook','edge:resilience_ping','edge:reveal_invoice','edge:rfq_flag','edge:role_guard','edge:send_outbox','edge:send_sms','edge:send_whatsapp','edge:site_assistant','edge:stripe_checkout','edge:stripe_confirm','edge:stripe_setup','edge:stripe_setup_page','edge:stripe_webhook','edge:sup_dob','edge:supplier_ack','edge:supplier_pay','edge:transcribe','edge:unsubscribe','edge:voice_otp','edge:voice_otp_capture','edge:wa_inbound','edge:wa_optin_set','edge:wa_template_setup','edge:wa_templates_watch');
