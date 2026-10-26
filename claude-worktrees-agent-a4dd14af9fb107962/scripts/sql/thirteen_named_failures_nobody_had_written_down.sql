-- SPEC #7 §3 NAMES 16 FAILURES. THIRTEEN OF THEM HAD NO SCENARIO AT ALL.
--
-- "Every one of these scenarios needs a predefined recovery strategy." (spec #7 L1353)
--
-- scenario_library held 19 rows, which reads as generous coverage. Measured against the contract on
-- 2026-08-11: 17 of the 19 are scenarios spec #7 never named, and only THREE of the contract's 16
-- were covered - openrouter_outage (which answers both "OpenAI unavailable" and "Anthropic
-- unavailable", since this company reaches every model through OpenRouter) and the two
-- agent-disagreement scenarios rfq_classified_differently and marketing_legal_disagree.
--
-- The other thirteen were not weakly covered. They were absent.
--
-- WHAT THIS FILE IS AND IS NOT. It writes down the recovery strategy for each, and every
-- expected_behaviour below NAMES THE MECHANISM THAT ACTUALLY EXISTS, verified in this session, or
-- says plainly that none exists. Four of the thirteen have no recovery path at all and say so in
-- their own text. A scenario library full of confident prose about recoveries that were never built
-- is worse than an empty one: it is the same defect as a staffing check being read as
-- disaster-recovery coverage.
--
-- fn_scenario_run is NOT changed. A previous session already made it honest - it reports
-- 'staffed' rather than 'ready', writes last_staffing_check rather than last_run, returns
-- is_rehearsal:false, and its own result text says "THIS IS A STAFFING CHECK, NOT A REHEARSAL".
-- That is correct and is left exactly as it is.

insert into public.scenario_library (scenario_key, name, category, situation, expected_behaviour, departments)
values

-- ---- INFRASTRUCTURE -------------------------------------------------------------------------
('vector_db_failure', 'The vector index fails or returns nothing', 'continuity',
 'kb_match / the gte-small embedding index becomes unavailable, times out, or returns zero rows for queries that should match.',
 'RECOVERY EXISTS AND IS AUTOMATIC. kb_search is hybrid: it runs the semantic vector search AND a full-text search and merges them with reciprocal rank fusion. If the vector half returns nothing, full-text still answers and retrieval degrades rather than stops. VERIFY BY: forcing the vector half to return zero and confirming kb_search still returns rows. WATCH FOR: silent quality loss - the call still succeeds, so nothing alerts. The measurable signal is a fall in the share of results marked via=semantic.',
 array['ai_dept','knowledge_eng','engineering']),

('email_delivery_stops', 'Email delivery stops', 'continuity',
 'Resend rejects, throttles or silently drops outbound mail. Every supplier notice, customer notice and founder alert goes through it.',
 'RECOVERY IS PARTIAL AND QUEUE-BASED. notifications rows are written with status=queued and carry attempts and last_error, and send_outbox drains them, so a message is never lost at the point of composing - it stays queued and is retried. WHAT IS MISSING: nothing escalates when the queue stops draining, so a multi-hour outage looks identical to a quiet day. BUILD ORDER: an alert on queued-and-ageing notifications, which is a count over notifications and needs no new table.',
 array['comms','it','engineering']),

('whatsapp_api_down', 'The WhatsApp API is down', 'continuity',
 'Twilio cannot deliver outbound WhatsApp, or stops delivering inbound webhooks to wa_inbound.',
 'RECOVERY EXISTS FOR OUTBOUND, NOT INBOUND. Outbound: wa_inbound records sent=false with the Twilio error, raises a wa_send_failed founder_alert and queues an email to the admin, so a failed send is never silent. Inbound: since 11 Aug wa_inbound_seen makes redelivery safe, so Twilio retrying after an outage cannot double-handle a message. WHAT IS MISSING: if Twilio stops calling the webhook entirely there is nothing to notice - the endpoint is correctly marked on_demand, so silence is not an alarm. That is the right trade for a webhook and the residual risk is accepted and stated.',
 array['comms','it','engineering']),

('payment_gateway_unavailable', 'The payment gateway is unavailable', 'financial',
 'Stripe cannot take the reveal fee, or a payment succeeds and the confirmation never arrives.',
 'THE MONEY-SAFE HALF EXISTS. A reveal is only recorded once a transactions row is written, so a failed payment cannot reveal supplier contact details - the customer simply does not get the reveal. The dangerous case is the reverse: Stripe charges and the confirmation is lost, leaving a customer billed with no reveal. transactions carries payment_ref and refund_status and the refund path exists, but reconciliation is manual and a refund requires the founder by standing rule. BUILD ORDER: a reconciliation sweep comparing Stripe charges against transactions rows.',
 array['payments','finance','exec']),

('database_record_locked', 'A database record is locked', 'continuity',
 'Two writers contend for the same row - typically an inquiry or a quote - and one blocks.',
 'RECOVERY IS A TIMEOUT, NOT A STRATEGY. PostgREST runs as authenticator with statement_timeout=8s, so a blocked write fails rather than hanging forever, and the caller sees an error. Nothing retries it. For the paths that matter this is survivable because they are single-writer, but there is no advisory-lock discipline and no retry-with-backoff anywhere. Treat a spike in 8-second timeouts as this scenario occurring.',
 array['engineering','it']),

-- ---- DOCUMENT INTELLIGENCE ------------------------------------------------------------------
('ocr_fails', 'OCR fails to read an uploaded drawing', 'operations',
 'drawing_boq cannot read the drawing - it is a photograph of a screen, a scan at unusable resolution, or a format the vision model cannot interpret.',
 'RECOVERY EXISTS AND IS HONEST BY DESIGN. drawing_boq is instructed to return confidence "low", an empty boq array and an explanation in missing_info rather than inventing quantities, and its prompt says so explicitly: "Never invent quantities you cannot see." So a failed read produces a flagged empty result, not a fabricated bill of quantities. WHAT IS MISSING: nothing routes that low-confidence result to a human or asks the customer for a better file. BUILD ORDER: a low-confidence branch that requests a re-upload.',
 array['doc_intelligence','rfq_intelligence','customer_success']),

('pdf_corrupted', 'A customer uploads a corrupted PDF', 'operations',
 'The file is truncated, password-protected or not valid PDF at all.',
 'NO RECOVERY PATH EXISTS. Measured 11 Aug 2026: there is no file-integrity or MIME validation on the intake path. The failure surfaces as an exception inside whichever function opens the file, and the customer is not told their upload is unusable. BUILD ORDER, and it is the same one as the ZIP scenario: validate the file at intake, reject it with a message the customer can act on, and never let an unreadable upload become a silent dead end.',
 array['doc_intelligence','engineering','customer_success']),

('zip_instead_of_pdf', 'A customer uploads a ZIP instead of a PDF', 'operations',
 'The customer attaches a ZIP, RAR or DWG bundle where the system expects a document or image.',
 'NO RECOVERY PATH EXISTS. Measured 11 Aug 2026: intake performs no MIME-type check, so the file is accepted and then fails downstream where the error means nothing to the customer. This is the most likely of the sixteen to actually happen - sending a zipped drawing set is normal practice in UAE construction. BUILD ORDER: accept the ZIP deliberately and expand it, or reject it at upload with a clear instruction. Failing silently in the middle is the only unacceptable option.',
 array['doc_intelligence','engineering','customer_success']),

-- ---- SUPPLIER BEHAVIOUR ---------------------------------------------------------------------
('supplier_website_offline', 'A supplier website is offline', 'operations',
 'Enrichment or verification cannot reach a supplier domain.',
 'RECOVERY EXISTS AT THE DATA LEVEL. leads carries website_status and permanently_closed, so an unreachable site is recorded rather than treated as a missing company, and enrichment can proceed from the other signals held on the row (phone, licence, maps presence, catalogue documents). A dead website alone must never block approval, because a working UAE trading company frequently has none.',
 array['supplier_knowledge','procurement']),

('supplier_no_reply_24h', 'A supplier does not reply within 24 hours', 'operations',
 'An invited supplier neither quotes nor declines inside the SLA.',
 'RECOVERY EXISTS AND IS THE STRONGEST OF THE SIXTEEN. transactions carries nudged_24_at and nudged_48_at, fn_notify_supplier issues a formal notice copying the customer and the admin, fn_refund_state gates what the customer may do next, the refund deadline is extended by working days so the customer is never timed out by our own chase, and an agent_actions row is raised to customer_success. leads.rv_response_rate and rv_nonresponse_refunds record the pattern per supplier.',
 array['procurement','customer_success','supplier_success']),

('supplier_wrong_quotation', 'A supplier uploads the wrong quotation', 'operations',
 'The document attached belongs to a different project, a different customer, or is an old revision.',
 'RECOVERY IS PARTIAL. The quote review chain exists - quotes carries review_id and review_status and the 7-stage review chain has real rejections and revision requests - so a wrong document CAN be caught and returned. quotes.quality and trg_quote_quality score the submission. WHAT IS MISSING: nothing compares the uploaded quotation against the inquiry it answers, so catching it depends on a reviewer noticing. A cross-check of the quote against the inquiry spec is the build order, and it is the same shape as the requirements-change check.',
 array['procurement','qa','trust_safety']),

('supplier_replies_in_arabic', 'A supplier responds in Arabic', 'operations',
 'Inbound WhatsApp or email arrives in Arabic, possibly mixed with English technical terms.',
 'RECOVERY EXISTS AND IS BUILT IN. wa_inbound instructs the model to reply in the same language as the incoming message, requires Modern Standard Arabic for Arabic input, and wraps LTR runs in U+2066/U+2069 BIDI isolates so phone numbers, emails and links stay readable in right-to-left text. Arabic tokens are included in the FAQ tokeniser. This is a supported path, not an exception - most of this supplier base is Arabic-speaking.',
 array['comms','customer_success','knowledge']),

-- ---- CUSTOMER BEHAVIOUR ---------------------------------------------------------------------
('requirements_change_after_quotes', 'A customer changes requirements after quotations are received', 'operations',
 'The customer edits the BOQ, budget, scope, trades or emirate of an inquiry that already has submitted quotes.',
 'RECOVERY EXISTS AS OF 11 AUG 2026 AND IS TESTED. fn_edit_inquiry now decides whether the change is MATERIAL (spec, boq, budget, scope_type, emirate, trades - the fields a price is computed from; editing summary or keywords stales nothing). On a material change it stales every live quote, reverts it to draft so it cannot be compared or revealed, emails each affected supplier asking for a re-quote, tells the customer their prices are being refreshed, and raises a procurement action to watch that the re-quotes arrive. Proved by two aborted-transaction probes on production: material change staled 1 of 1 and notified 1 supplier; a cosmetic edit staled 0 and left the quote submitted.',
 array['procurement','customer_success','doc_intelligence'])

on conflict (scenario_key) do nothing;
