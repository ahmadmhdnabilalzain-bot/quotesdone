# QuotesDone e2e run 2026-10-19T00-16-39

Site https://quotesdone.com · project htdblwldjkcgjvmqkbeh · run tag `39514e1e` · 1635s · journeys a,b,c,d,e,h,f,g

**25 passed · 12 failed · 0 held by the model hold · 9 skipped**

| # | journey | step | result | detail | ms |
|---|---|---|---|---|---|
| 1 | fixtures | fixtures of runs that are over are removed before this run starts | FAIL | management API 400: {"message":"Failed to run sql query: ERROR:  23503: update or delete on table \"leads\" violates foreign key constraint \"inbound_messages_lead_id_fkey\" on table \"inbound_message |  |
| 2 | fixtures | demo customer complete (name, 18+ DOB, email+mobile verified, current terms signed) | PASS | is_demo=true dob=1990-01-15 email_verified=true phone_verified=true terms=v10/v10 signed=false |  |
| 3 | fixtures | demo supplier A has the mandatory six | PASS | is_demo=true approval=approved missing=[] licence=uploaded profile=uploaded agreement=v15/v15 signed=true |  |
| 4 | fixtures | demo supplier B has the mandatory six | PASS | is_demo=true approval=approved missing=[] licence=uploaded profile=uploaded agreement=v15/v15 signed=true |  |
| 5 | fixtures | demo supplier C has the mandatory six | PASS | is_demo=true approval=approved missing=[] licence=uploaded profile=uploaded agreement=v15/v15 signed=true |  |
| 6 | a customer | signed in without an OTP (en-desktop) | PASS | nav visible=true, dir=ltr |  |
| 7 | a customer | overview data under 2.5 s (en-desktop) | FAIL | data settled in 4127 ms (shell 1666 ms, 7 function call(s): kyc:state @723 +462, customer_api:my_inquiries @723 +672, customer_portal:overview @742 +676, project_api:dashboard @743 +553, messages_api:threads @743 +588, customer_portal:decision_support @743 +598, sales_engineer:support_rating_due @10 | 4127 |
| 8 | a customer | signed in without an OTP (ar-desktop) | PASS | nav visible=true, dir=rtl |  |
| 9 | a customer | overview data under 2.5 s (ar-desktop) | PASS | data settled in 1731 ms (shell 1296 ms, 7 function call(s): kyc:state @795 +293, customer_api:my_inquiries @795 +550, project_api:dashboard @796 +570, customer_portal:overview @796 +654, messages_api:threads @796 +734, customer_portal:decision_support @797 +502, sales_engineer:support_rating_due @11 | 1731 |
| 10 | a customer | Arabic renders right-to-left (ar-desktop) | PASS | document dir=rtl |  |
| 11 | a customer | signed in without an OTP (en-mobile) | PASS | nav visible=true, dir=ltr |  |
| 12 | a customer | overview data under 2.5 s (en-mobile) | PASS | data settled in 1109 ms (shell 1334 ms, 7 function call(s): kyc:state @332 +564, customer_api:my_inquiries @337 +565, project_api:dashboard @337 +575, customer_portal:overview @337 +787, customer_portal:decision_support @338 +594, messages_api:threads @338 +729, sales_engineer:support_rating_due @61 | 1109 |
| 13 | a customer | signed in without an OTP (ar-mobile) | PASS | nav visible=true, dir=rtl |  |
| 14 | a customer | overview data under 2.5 s (ar-mobile) | PASS | data settled in 1206 ms (shell 1240 ms, 7 function call(s): kyc:state @304 +458, customer_api:my_inquiries @305 +562, project_api:dashboard @307 +506, messages_api:threads @307 +670, customer_portal:overview @307 +902, customer_portal:decision_support @310 +524, sales_engineer:support_rating_due @61 | 1206 |
| 15 | a customer | Arabic renders right-to-left (ar-mobile) | PASS | document dir=rtl |  |
| 16 | a customer | every Arabic page in the sitemap renders right-to-left | PASS | 79/79 Arabic pages rtl |  |
| 17 | a customer | the sales engineer interview reaches ready | FAIL | 8 turn(s), status=held, readiness=0 |  |
| 18 | a customer | fallback request written for the rest of the funnel | SKIP | inquiry cd7b7f70-e4a3-4644-a0fa-2a5e72415347 written by demo_factory.makeInquiry because the portal did not post one |  |
| 19 | a customer | database: the request belongs to the customer and is demo | PASS | owner match=true, demo=true, category=aluminium, status=sent, rfq_ready=true |  |
| 20 | a customer | database: the sales-engineer answers are on the request (installation, warranty, materials, date) | SKIP | answered: installation, warranty, date (fallback request) |  |
| 21 | b supplier | routing invited the demo suppliers | FAIL | 0/3 matched by the product; 3 invited directly by the harness |  |
| 22 | b supplier | sees the invitation (en-desktop) | PASS | RFQ visible in the "Inquiries received" tab |  |
| 23 | b supplier | invitation is anonymised (en-desktop) | PASS | none of 4 customer identifiers on screen |  |
| 24 | b supplier | sees the invitation (ar-desktop) | FAIL | the "الاستفسارات الواردة" tab could not be opened in 15 s |  |
| 25 | b supplier | invitation is anonymised (ar-desktop) | PASS | none of 4 customer identifiers on screen |  |
| 26 | b supplier | sees the invitation (en-mobile) | PASS | RFQ visible in the "Inquiries received" tab |  |
| 27 | b supplier | invitation is anonymised (en-mobile) | PASS | none of 4 customer identifiers on screen |  |
| 28 | b supplier | sees the invitation (ar-mobile) | FAIL | the "الاستفسارات الواردة" tab could not be opened in 15 s |  |
| 29 | b supplier | invitation is anonymised (ar-mobile) | PASS | none of 4 customer identifiers on screen |  |
| 30 | b supplier | API: the inbox carries no customer identity | PASS | HTTP 200, 1 RFQ(s), customer_id field present=false |  |
| 31 | b supplier | an incomplete quote is HELD | FAIL | HTTP 500 held=undefined missing= |  |
| 32 | b supplier | database: the hold is open and owned by the sales engineer | FAIL | {} |  |
| 33 | b supplier | the hold notice was written and CAPTURED, never sent | FAIL | no notification row |  |
| 34 | b supplier | the hold notice reaches WhatsApp too | SKIP | the hold desk queues e-mail only (workflow.ts gate); WhatsApp fan-out needs the supplier's wa_optin, which a demo supplier does not give |  |
| 35 | b supplier | two options become two quotations | FAIL | HTTP 500 code=undefined rows=#1:draft held=0 |  |
| 36 | b supplier | preflight: the complete quote states every required detail | FAIL | would_hold=true missing=glass_type,glass_thickness,profile_system,installation_included,warranty_coverage,glass_type,glass_thickness,profile_system,installation_included,warranty_coverage would_accept=false |  |
| 37 | b supplier | a complete quote is accepted | PASS | HTTP 200 held=undefined accepted=true code= |  |
| 38 | b supplier | a held quote is not ranked | FAIL | HTTP 409 ok=false on_hold=0 held quote in ranking=? |  |
| 39 | c | journey not started | SKIP | the 20-minute harness deadline passed before this journey; teardown and the report run so the heartbeat still reaches the IT engineer |  |
| 40 | d | journey not started | SKIP | the 20-minute harness deadline passed before this journey; teardown and the report run so the heartbeat still reaches the IT engineer |  |
| 41 | e | journey not started | SKIP | the 20-minute harness deadline passed before this journey; teardown and the report run so the heartbeat still reaches the IT engineer |  |
| 42 | h | journey not started | SKIP | the 20-minute harness deadline passed before this journey; teardown and the report run so the heartbeat still reaches the IT engineer |  |
| 43 | f | journey not started | SKIP | the 20-minute harness deadline passed before this journey; teardown and the report run so the heartbeat still reaches the IT engineer |  |
| 44 | g | journey not started | SKIP | the 20-minute harness deadline passed before this journey; teardown and the report run so the heartbeat still reaches the IT engineer |  |
| 45 | safety | nothing the run caused was dispatched | PASS | email/suppressed: 3, whatsapp/suppressed: 3 |  |
| 46 | cleanup | zero leftovers | PASS | removed: notifications 6, comparison_candidate_v2 (table no longer exists) 0, agent_actions 9, doc_versions 11, doc_versions (rfq) 2, quote_items 3, documents 6, company_event (quote) 3, quotes 3, inquiry_matches 3, company_event (lead) 3, company_event (inquiry) 2, inquiries 1, supplier_capability_ |  |

## Console errors

none

## Screenshots

- signed in without an OTP (en-desktop): a_overview_en-desktop.png
- signed in without an OTP (ar-desktop): a_overview_ar-desktop.png
- signed in without an OTP (en-mobile): a_overview_en-mobile.png
- signed in without an OTP (ar-mobile): a_overview_ar-mobile.png
- the sales engineer interview reaches ready: a_intake.png
- sees the invitation (en-desktop): b_invitation_en-desktop.png
- sees the invitation (ar-desktop): b_invitation_ar-desktop.png
- sees the invitation (en-mobile): b_invitation_en-mobile.png
- sees the invitation (ar-mobile): b_invitation_ar-mobile.png