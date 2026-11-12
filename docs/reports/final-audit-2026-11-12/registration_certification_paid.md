# Supplier registration certification - PAID round (readers on)

Site https://quotesdone.ae. 2 run(s): f5b09c50 (2026-11-11T22:30Z), 2777f7ae (2026-11-11T22:52Z). Phone profile: iPhone 13, 9 Mbit/s down, 1.5 Mbit/s up, 60 ms added round trip, CPU slowed 2x (Chrome DevTools Protocol emulation). Desktop: 1440x900, the container's own network.

## Verdict per criterion

| criterion | verdict | measured |
|---|---|---|
| speed | **FAIL** | {"steps":192,"slow":["J1 desktop approved and verified 60494 ms > 60000"]} |
| licence_fields | **PASS** | {"per_run":[{"judged":8,"correct":8,"not_run":0,"wrong":[]},{"judged":8,"correct":7,"not_run":0,"wrong":["J1"]}],"bar":">= 7 of 8 licences per run, all five fields"} |
| expired_flagged | **PASS** | {} |
| proposals | **PASS** | {"judged":12,"absurd":[]} |
| no_error_no_dead_end | **PASS** | {"dead_ends":[],"errors":[],"environment_faults":[]} |
| no_arabic | **PASS** | {"rule":"ruling 1008: no Arabic in a message to a supplier; no Arabic on an English supplier page except the agreement's legal text (ruling 342) or Arabic the supplier chose","seen":[],"in_messages":[],"allowed":["agreement page: كوتس دن للتكنولوجيا"],"messages_read":28,"language_switch_seen":["supplier page","agreement page"]} |
| plain_polite | **PASS** | {"faults":[]} |
| supplier_minutes | **FAIL** | {"max_minutes":10,"measured_min":["J1 3.5","J2 3.0","J3 2.7","J4 3.1","J5 3.3","J6 3.0","J2 2.7","J3 2.6","J4 3.0","J5 3.2","J6 3.1"],"not_finished":["J1"]} |
| reproducible | **FAIL** | {"signatures":["J1:V:5:electrical+hvac+mep_general+plumbing:/J2:V:5:joinery:/J3:V:5:building_materials:/J4:V:5:hvac:/J5:V:5:corrugated_packaging+rigid_plastic_packaging:/J6:V:5:staff_transport:/J7:-:5::/J8:-:5::","J1:-:4:electrical+hvac+mep_general+plumbing:/J2:V:5:joinery:/J3:V:5:building_materials:/J4:V:5:hvac:/J5:V:5:corrugated_packaging+rigid_plastic_packaging:/J6:V:5:staff_transport:/J7:-:5::/J8:-:5::"],"extras":["J1:/J2:/J3:/J4:/J5:/J6:/J7:/J8:","J1:/J2:/J3:/J4:/J5:/J6:/J7:/J8:"],"compares":"verified, licence fields read, the expected trades found and the absurd ones; acceptable extras a |

## Run 1 (tag f5b09c50)

Spend by tag: USD 0.0316 (21 calls). Untagged reader spend in the window: USD 0. Notifications before teardown: [{"status":"suppressed","channel":"email","n":7},{"status":"suppressed","channel":"whatsapp","n":7}]; dispatched 0. Teardown: {"leftovers":{"auth_users":0,"customers":0,"leads":0,"inquiries":0,"quotes":0,"quote_spec_hold":0,"quote_reviews":0,"notifications":0,"transactions":0,"refunds":0,"supplier_dues":0,"refund_case":0,"inquiry_intake":0,"email_verifications":0,"storage_objects":0,"assistant_logs":0,"support_customer_profile":0,"support_case":0,"assistant_logs_run_tag":0,"sales_decision_log":0,"support_reply_readability":0,"total":0,"knowledge_gaps_filed":0,"org_tasks_filed":0},"sink":[{"auth_users":0,"email_verifications":0,"notifications":0,"leads":0},{"auth_users":0,"email_verifications":0,"notifications":0,"leads":0},{"auth_users":0,"email_verifications":0,"notifications":0,"leads":0},{"auth_users":0,"email_verifications":0,"notifications":0,"leads":0},{"auth_users":0,"email_verifications":0,"notifications":0,"leads":0},{"auth_users":0,"email_verifications":0,"notifications":0,"leads":0},{"auth_users":0,"email_verifications":0,"notifications":0,"leads":0},{"auth_users":0,"email_verifications":0,"notifications":0,"leads":0}],"fixture_licences_still_held":0}

### J1 desktop (direct): L1_dubai_det_bilingual.pdf + P1_mep_contractor.pdf

| step | result | ms | budget |
|---|---|---:|---:|
| the supplier page is interactive | PASS | 948 | 3000 |
| the sign-up form opens | PASS | 1364 | 3000 |
| "Create my account" sends the code and opens the code box | PASS | 2641 | 10000 |
| the code e-mail arrives | PASS |  |  |
| the code verifies and "Register your company" opens | PASS | 1404 | 3000 |
| "Create company" opens the registration form | PASS | 1892 | 3000 |
| the mobile: refused before any SMS, recorded verified, the form shows "Mobile verified" (harness path) | PASS |  |  |
| the licence is read and the screen answers | PASS | 15135 | 45000 |
| what was read is shown back: number and authority on screen | PASS |  |  |
| the company profile is attached | PASS |  |  |
| the Supplier Agreement page opens | PASS | 648 | 3000 |
| "Submit for approval" ends in the supplier workspace | PASS | 8114 | 20000 |
| the Services tab opens | PASS | 95 | 3000 |
| services are proposed from his documents | PASS | 69409 | 120000 |
| the proposals are his trades, nothing absurd | PASS |  |  |
| proposed services start unticked | PASS |  |  |
| "Tick all proposed services" ticks every one | PASS | 49 | 3000 |
| licence fields read correctly (number, legal name, authority, expiry, activities) | PASS |  |  |
| his own trade's services ticked from the checklist | PASS |  |  |
| "Confirm my services" confirms them | PASS | 2348 | 20000 |
| approved and verified | PASS | 2232 | 60000 |
| the portal home opens | PASS | 2177 | 3000 |

Licence read (row): {"trade_license_no":"ZZ-1290417","licence_legal_name":"ZZ DEMO Saker Electromechanical Contracting LLC","license_authority":"Dubai Department of Economy and Tourism","license_expiry":"2027-02-15","licence_read_state":"read","company_name":"ZZ DEMO Saker Electromechanical Contracting LLC"}
Shown back: {"note":"Read your licence — ZZ-1290417, expires 2027-02-15.","licence_no":"ZZ-1290417","authority":"Dubai Department of Economy and Tourism"}
Proposals: {"trades":["electrical","hvac","mep_general","plumbing"],"right":["electrical","hvac","mep_general","plumbing"],"acceptable":[],"absurd":[],"ok":true}
Final: {"approval_status":"approved","verified":true,"licence_gate_reason":null,"licence_read_state":"read","company_name":"ZZ DEMO Saker Electromechanical Contracting LLC","missing_of_six":"{}"}
Arabic seen: [{"where":"agreement page","text":"كوتس دن للتكنولوجيا"}]
Message faults: []
Errors: []
Environment faults (an answer not from the site, see the HTTP line): []
HTTP 4xx/5xx met by the page: ["400 https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/supplier_portal"]
Language switch shown: [{"where":"supplier page","text":"العربية"},{"where":"agreement page","text":"العربية"}]
Dead end: none
Messages read: ["Supplier portal — QuotesDone","html[data-qd-portal=\"mounted\"] #qd-portal-boot{display:none}#qd-portal-boot{max-width:420px;margin:18vh auto 0;padding:0 16px;text-align:center;font-size:15px;l","Read your licence — ZZ-1290417, expires 2027-02-15.","To be verified, confirm what your company does. Below is the summary and the keywords our sales engineer prepared from your company profile. Check them, correct","Voice input is coming soon. Please type your services for now.","Saved. Your services are confirmed. Your registration is approved. Matching inquiries now reach you in the Inquiries tab."]

### J2 mobile (invite): L2_abu_dhabi_added.pdf + P2_joinery.pdf

| step | result | ms | budget |
|---|---|---:|---:|
| the invitation link opens the sign-up | PASS | 1599 | 5000 |
| "Claim my listing" is offered on the invitation | PASS |  |  |
| "Create my account" sends the code and opens the code box | PASS | 2370 | 15000 |
| the code e-mail arrives | PASS |  |  |
| the code verifies and the invited company's registration form opens, claimed | PASS | 3430 | 5000 |
| the form says whose listing it is ("Finish registering") | PASS |  |  |
| the mobile: refused before any SMS, recorded verified, the form shows "Mobile verified" (harness path) | PASS |  |  |
| the licence is read and the screen answers | PASS | 18059 | 45000 |
| what was read is shown back: number and authority on screen | PASS |  |  |
| the company profile is attached | PASS |  |  |
| the Supplier Agreement page opens | PASS | 614 | 5000 |
| "Submit for approval" ends in the supplier workspace | PASS | 7563 | 30000 |
| the Services tab opens | PASS | 159 | 5000 |
| services are proposed from his documents | PASS | 19415 | 120000 |
| the proposals are his trades, nothing absurd | PASS |  |  |
| proposed services start unticked | PASS |  |  |
| "Tick all proposed services" ticks every one | PASS | 69 | 5000 |
| licence fields read correctly (number, legal name, authority, expiry, activities) | PASS |  |  |
| his own trade's services ticked from the checklist | PASS |  |  |
| "Confirm my services" confirms them | PASS | 2394 | 30000 |
| approved and verified | PASS | 2214 | 60000 |
| the portal home opens | PASS | 2135 | 5000 |

Licence read (row): {"trade_license_no":"CN-ZZ482137","licence_legal_name":"ZZ DEMO Ghaf Joinery and Carpentry LLC","license_authority":"Abu Dhabi Department of Economic Development","license_expiry":"2027-05-03","licence_read_state":"read","company_name":"ZZ DEMO Ghaf Joinery and Carpentry LLC"}
Shown back: {"note":"Read your licence — CN-ZZ482137, expires 2027-05-03.","licence_no":"CN-ZZ482137","authority":"Abu Dhabi Department of Economic Development"}
Proposals: {"trades":["joinery"],"right":["joinery"],"acceptable":[],"absurd":[],"ok":true}
Final: {"approval_status":"approved","verified":true,"licence_gate_reason":null,"licence_read_state":"read","company_name":"ZZ DEMO Ghaf Joinery and Carpentry LLC","missing_of_six":"{}"}
Arabic seen: [{"where":"agreement page","text":"كوتس دن للتكنولوجيا"}]
Message faults: []
Errors: []
Environment faults (an answer not from the site, see the HTTP line): []
HTTP 4xx/5xx met by the page: []
Language switch shown: [{"where":"agreement page","text":"العربية"}]
Dead end: none
Messages read: ["html[data-qd-portal=\"mounted\"] #qd-portal-boot{display:none}#qd-portal-boot{max-width:420px;margin:18vh auto 0;padding:0 16px;text-align:center;font-size:15px;l","Read your licence — CN-ZZ482137, expires 2027-05-03.","To be verified, confirm what your company does. Below is the summary and the keywords our sales engineer prepared from your company profile. Check them, correct","Voice input is coming soon. Please type your services for now.","Saved. Your services are confirmed. Your registration is approved. Matching inquiries now reach you in the Inquiries tab."]

### J3 desktop (direct): L3_jafza.pdf + P3_building_materials_trader.docx

| step | result | ms | budget |
|---|---|---:|---:|
| the supplier page is interactive | PASS | 284 | 3000 |
| the sign-up form opens | PASS | 1158 | 3000 |
| "Create my account" sends the code and opens the code box | PASS | 1527 | 10000 |
| the code e-mail arrives | PASS |  |  |
| the code verifies and "Register your company" opens | PASS | 1894 | 3000 |
| "Create company" opens the registration form | PASS | 870 | 3000 |
| the mobile: refused before any SMS, recorded verified, the form shows "Mobile verified" (harness path) | PASS |  |  |
| the licence is read and the screen answers | PASS | 14728 | 45000 |
| what was read is shown back: number and authority on screen | PASS |  |  |
| the company profile is attached | PASS |  |  |
| the Supplier Agreement page opens | PASS | 316 | 3000 |
| "Submit for approval" ends in the supplier workspace | PASS | 7954 | 20000 |
| the Services tab opens | PASS | 96 | 3000 |
| services are proposed from his documents | PASS | 24530 | 120000 |
| the proposals are his trades, nothing absurd | PASS |  |  |
| proposed services start unticked | PASS |  |  |
| "Tick all proposed services" ticks every one | PASS | 46 | 3000 |
| licence fields read correctly (number, legal name, authority, expiry, activities) | PASS |  |  |
| his own trade's services ticked from the checklist | PASS |  |  |
| "Confirm my services" confirms them | PASS | 2677 | 20000 |
| approved and verified | PASS | 2015 | 60000 |
| the portal home opens | PASS | 1577 | 3000 |

Licence read (row): {"trade_license_no":"ZZ-719044","licence_legal_name":"ZZ DEMO Dune Building Materials Trading FZE","license_authority":"Jebel Ali Free Zone Authority","license_expiry":"2027-09-20","licence_read_state":"read","company_name":"ZZ DEMO Dune Building Materials Trading FZE"}
Shown back: {"note":"Read your licence — ZZ-719044, expires 2027-09-20.","licence_no":"ZZ-719044","authority":"Jebel Ali Free Zone Authority"}
Proposals: {"trades":["building_materials"],"right":["building_materials"],"acceptable":[],"absurd":[],"ok":true}
Final: {"approval_status":"approved","verified":true,"licence_gate_reason":null,"licence_read_state":"read","company_name":"ZZ DEMO Dune Building Materials Trading FZE","missing_of_six":"{}"}
Arabic seen: [{"where":"agreement page","text":"كوتس دن للتكنولوجيا"}]
Message faults: []
Errors: []
Environment faults (an answer not from the site, see the HTTP line): []
HTTP 4xx/5xx met by the page: ["400 https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/supplier_portal"]
Language switch shown: [{"where":"supplier page","text":"العربية"},{"where":"agreement page","text":"العربية"}]
Dead end: none
Messages read: ["Supplier portal — QuotesDone","html[data-qd-portal=\"mounted\"] #qd-portal-boot{display:none}#qd-portal-boot{max-width:420px;margin:18vh auto 0;padding:0 16px;text-align:center;font-size:15px;l","Read your licence — ZZ-719044, expires 2027-09-20.","To be verified, confirm what your company does. Below is the summary and the keywords our sales engineer prepared from your company profile. Check them, correct","Voice input is coming soon. Please type your services for now.","Saved. Your services are confirmed. Your registration is approved. Matching inquiries now reach you in the Inquiries tab."]

### J4 mobile (direct): L4_ajman_phone_photo.jpg + P4_hvac.pdf

| step | result | ms | budget |
|---|---|---:|---:|
| the supplier page is interactive | PASS | 318 | 5000 |
| the sign-up form opens | PASS | 1416 | 5000 |
| "Create my account" sends the code and opens the code box | PASS | 1369 | 15000 |
| the code e-mail arrives | PASS |  |  |
| the code verifies and "Register your company" opens | PASS | 1371 | 5000 |
| "Create company" opens the registration form | PASS | 1368 | 5000 |
| the mobile: refused before any SMS, recorded verified, the form shows "Mobile verified" (harness path) | PASS |  |  |
| the licence is read and the screen answers | PASS | 14445 | 45000 |
| what was read is shown back: number and authority on screen | FAIL |  |  |
| the company profile is attached | PASS |  |  |
| the Supplier Agreement page opens | PASS | 334 | 5000 |
| "Submit for approval" ends in the supplier workspace | PASS | 8051 | 30000 |
| the Services tab opens | PASS | 94 | 5000 |
| services are proposed from his documents | PASS | 37145 | 120000 |
| the proposals are his trades, nothing absurd | PASS |  |  |
| proposed services start unticked | PASS |  |  |
| "Tick all proposed services" ticks every one | PASS | 79 | 5000 |
| licence fields read correctly (number, legal name, authority, expiry, activities) | PASS |  |  |
| his own trade's services ticked from the checklist | PASS |  |  |
| "Confirm my services" confirms them | PASS | 1381 | 30000 |
| approved and verified | PASS | 2131 | 60000 |
| the portal home opens | PASS | 1644 | 5000 |

Licence read (row): {"trade_license_no":"ZZ-307721","licence_legal_name":"ZZ DEMO Pearl Air Conditioning Contracting Est","license_authority":"Ajman Department of Economic Development","license_expiry":"2027-03-10","licence_read_state":"read","company_name":"ZZ DEMO Pearl Air Conditioning Contracting Est"}
Shown back: {"note":"Our document reader has not finished reading your trade licence yet. That is on our side, not yours: we read it again automatically and tell you if anything is needed. Nothing was guessed.","licence_no":"","authority":""}
Proposals: {"trades":["hvac"],"right":["hvac"],"acceptable":[],"absurd":[],"ok":true}
Final: {"approval_status":"approved","verified":true,"licence_gate_reason":null,"licence_read_state":"read","company_name":"ZZ DEMO Pearl Air Conditioning Contracting Est","missing_of_six":"{}"}
Arabic seen: [{"where":"agreement page","text":"كوتس دن للتكنولوجيا"}]
Message faults: []
Errors: []
Environment faults (an answer not from the site, see the HTTP line): []
HTTP 4xx/5xx met by the page: ["400 https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/supplier_portal"]
Language switch shown: [{"where":"supplier page","text":"العربية"},{"where":"agreement page","text":"العربية"}]
Dead end: none
Messages read: ["Supplier portal — QuotesDone","html[data-qd-portal=\"mounted\"] #qd-portal-boot{display:none}#qd-portal-boot{max-width:420px;margin:18vh auto 0;padding:0 16px;text-align:center;font-size:15px;l","Our document reader has not finished reading your trade licence yet. That is on our side, not yours: we read it again automatically and tell you if anything is ","To be verified, confirm what your company does. Below is the summary and the keywords our sales engineer prepared from your company profile. Check them, correct","Voice input is coming soon. Please type your services for now.","Saved. Your services are confirmed. Your registration is approved. Matching inquiries now reach you in the Inquiries tab."]

### J5 desktop (direct): L5_rakez_scan.pdf + P5_packaging_brochure_image_only.pdf

| step | result | ms | budget |
|---|---|---:|---:|
| the supplier page is interactive | PASS | 697 | 3000 |
| the sign-up form opens | PASS | 1458 | 3000 |
| "Create my account" sends the code and opens the code box | PASS | 1713 | 10000 |
| the code e-mail arrives | PASS |  |  |
| the code verifies and "Register your company" opens | PASS | 1838 | 3000 |
| "Create company" opens the registration form | PASS | 1398 | 3000 |
| the mobile: refused before any SMS, recorded verified, the form shows "Mobile verified" (harness path) | PASS |  |  |
| the licence is read and the screen answers | PASS | 12075 | 45000 |
| what was read is shown back: number and authority on screen | PASS |  |  |
| the company profile is attached | PASS |  |  |
| the Supplier Agreement page opens | PASS | 488 | 3000 |
| "Submit for approval" ends in the supplier workspace | PASS | 7522 | 20000 |
| the Services tab opens | PASS | 87 | 3000 |
| services are proposed from his documents | PASS | 58679 | 120000 |
| the proposals are his trades, nothing absurd | PASS |  |  |
| proposed services start unticked | PASS |  |  |
| "Tick all proposed services" ticks every one | PASS | 69 | 3000 |
| licence fields read correctly (number, legal name, authority, expiry, activities) | PASS |  |  |
| his own trade's services ticked from the checklist | PASS |  |  |
| "Confirm my services" confirms them | PASS | 2354 | 20000 |
| approved and verified | PASS | 2018 | 60000 |
| the portal home opens | PASS | 1629 | 3000 |

Licence read (row): {"trade_license_no":"ZZ-5047219","licence_legal_name":"ZZ DEMO Najm Packaging Industries FZ-LLC","license_authority":"Ras Al Khaimah Economic Zone Authority","license_expiry":"2027-06-29","licence_read_state":"read","company_name":"ZZ DEMO Najm Packaging Industries FZ-LLC"}
Shown back: {"note":"Read your licence — ZZ-5047219, expires 2027-06-29.","licence_no":"ZZ-5047219","authority":"Ras Al Khaimah Economic Zone Authority"}
Proposals: {"trades":["corrugated_packaging","rigid_plastic_packaging"],"right":["corrugated_packaging","rigid_plastic_packaging"],"acceptable":[],"absurd":[],"ok":true}
Final: {"approval_status":"approved","verified":true,"licence_gate_reason":null,"licence_read_state":"read","company_name":"ZZ DEMO Najm Packaging Industries FZ-LLC","missing_of_six":"{}"}
Arabic seen: [{"where":"agreement page","text":"كوتس دن للتكنولوجيا"}]
Message faults: []
Errors: []
Environment faults (an answer not from the site, see the HTTP line): []
HTTP 4xx/5xx met by the page: ["400 https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/supplier_portal"]
Language switch shown: [{"where":"supplier page","text":"العربية"},{"where":"agreement page","text":"العربية"}]
Dead end: none
Messages read: ["Supplier portal — QuotesDone","html[data-qd-portal=\"mounted\"] #qd-portal-boot{display:none}#qd-portal-boot{max-width:420px;margin:18vh auto 0;padding:0 16px;text-align:center;font-size:15px;l","Read your licence — ZZ-5047219, expires 2027-06-29.","To be verified, confirm what your company does. Below is the summary and the keywords our sales engineer prepared from your company profile. Check them, correct","Voice input is coming soon. Please type your services for now.","Saved. Your services are confirmed. Your registration is approved. Matching inquiries now reach you in the Inquiries tab."]

### J6 mobile (direct): L6_sharjah_sedd.pdf + P6_bus_rental_bilingual.pdf

| step | result | ms | budget |
|---|---|---:|---:|
| the supplier page is interactive | PASS | 1369 | 5000 |
| the sign-up form opens | PASS | 1454 | 5000 |
| "Create my account" sends the code and opens the code box | PASS | 2537 | 15000 |
| the code e-mail arrives | PASS |  |  |
| the code verifies and "Register your company" opens | PASS | 1365 | 5000 |
| "Create company" opens the registration form | PASS | 1367 | 5000 |
| the mobile: refused before any SMS, recorded verified, the form shows "Mobile verified" (harness path) | PASS |  |  |
| the licence is read and the screen answers | PASS | 13443 | 45000 |
| what was read is shown back: number and authority on screen | PASS |  |  |
| the company profile is attached | PASS |  |  |
| the Supplier Agreement page opens | PASS | 222 | 5000 |
| "Submit for approval" ends in the supplier workspace | PASS | 9547 | 30000 |
| the Services tab opens | PASS | 129 | 5000 |
| services are proposed from his documents | PASS | 27873 | 120000 |
| the proposals are his trades, nothing absurd | PASS |  |  |
| proposed services start unticked | PASS |  |  |
| "Tick all proposed services" ticks every one | PASS | 65 | 5000 |
| licence fields read correctly (number, legal name, authority, expiry, activities) | PASS |  |  |
| his own trade's services ticked from the checklist | PASS |  |  |
| "Confirm my services" confirms them | PASS | 1872 | 30000 |
| approved and verified | PASS | 2253 | 60000 |
| the portal home opens | PASS | 3698 | 5000 |

Licence read (row): {"trade_license_no":"ZZ-748113","licence_legal_name":"ZZ DEMO Corniche Passenger Transport LLC","license_authority":"Sharjah Economic Development Department","license_expiry":"2027-01-07","licence_read_state":"read","company_name":"ZZ DEMO Corniche Passenger Transport LLC"}
Shown back: {"note":"Read your licence — ZZ-748113, expires 2027-01-07.","licence_no":"ZZ-748113","authority":"Sharjah Economic Development Department"}
Proposals: {"trades":["staff_transport"],"right":["staff_transport"],"acceptable":[],"absurd":[],"ok":true}
Final: {"approval_status":"approved","verified":true,"licence_gate_reason":null,"licence_read_state":"read","company_name":"ZZ DEMO Corniche Passenger Transport LLC","missing_of_six":"{}"}
Arabic seen: [{"where":"agreement page","text":"كوتس دن للتكنولوجيا"}]
Message faults: []
Errors: []
Environment faults (an answer not from the site, see the HTTP line): []
HTTP 4xx/5xx met by the page: ["400 https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/supplier_portal"]
Language switch shown: [{"where":"supplier page","text":"العربية"},{"where":"agreement page","text":"العربية"}]
Dead end: none
Messages read: ["Supplier portal — QuotesDone","html[data-qd-portal=\"mounted\"] #qd-portal-boot{display:none}#qd-portal-boot{max-width:420px;margin:18vh auto 0;padding:0 16px;text-align:center;font-size:15px;l","Read your licence — ZZ-748113, expires 2027-01-07.","To be verified, confirm what your company does. Below is the summary and the keywords our sales engineer prepared from your company profile. Check them, correct","Voice input is coming soon. Please type your services for now.","Saved. Your services are confirmed. Your registration is approved. Matching inquiries now reach you in the Inquiries tab."]

### J7 desktop (direct): L7_dmcc.pdf

| step | result | ms | budget |
|---|---|---:|---:|
| the supplier page is interactive | PASS | 470 | 3000 |
| the sign-up form opens | PASS | 1152 | 3000 |
| "Create my account" sends the code and opens the code box | PASS | 1660 | 10000 |
| the code e-mail arrives | PASS |  |  |
| the code verifies and "Register your company" opens | PASS | 1360 | 3000 |
| "Create company" opens the registration form | PASS | 1376 | 3000 |
| the mobile: refused before any SMS, recorded verified, the form shows "Mobile verified" (harness path) | PASS |  |  |
| the licence is read and the screen answers | PASS | 11147 | 45000 |
| what was read is shown back: number and authority on screen | PASS |  |  |
| licence fields read correctly (number, legal name, authority, expiry, activities) | PASS |  |  |

Licence read (row): {"trade_license_no":"DMCC-ZZ8401","licence_legal_name":"ZZ DEMO Marina Steel Trading DMCC","license_authority":"Dubai Multi Commodities Centre Authority","license_expiry":"2027-04-13","licence_read_state":"read","company_name":"ZZ DEMO Marina Steel Trading DMCC"}
Shown back: {"note":"Read your licence — DMCC-ZZ8401, expires 2027-04-13.","licence_no":"DMCC-ZZ8401","authority":"Dubai Multi Commodities Centre Authority"}
Proposals: {}
Final: {}
Arabic seen: []
Message faults: []
Errors: []
Environment faults (an answer not from the site, see the HTTP line): []
HTTP 4xx/5xx met by the page: ["400 https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/supplier_portal"]
Language switch shown: [{"where":"supplier page","text":"العربية"}]
Dead end: none
Messages read: ["Supplier portal — QuotesDone","html[data-qd-portal=\"mounted\"] #qd-portal-boot{display:none}#qd-portal-boot{max-width:420px;margin:18vh auto 0;padding:0 16px;text-align:center;font-size:15px;l","Read your licence — DMCC-ZZ8401, expires 2027-04-13."]

### J8 mobile (direct): L8_rak_ded_expired.pdf + P1_mep_contractor.pdf

| step | result | ms | budget |
|---|---|---:|---:|
| the supplier page is interactive | PASS | 355 | 5000 |
| the sign-up form opens | PASS | 905 | 5000 |
| "Create my account" sends the code and opens the code box | PASS | 1381 | 15000 |
| the code e-mail arrives | PASS |  |  |
| the code verifies and "Register your company" opens | PASS | 1366 | 5000 |
| "Create company" opens the registration form | PASS | 1362 | 5000 |
| the mobile: refused before any SMS, recorded verified, the form shows "Mobile verified" (harness path) | PASS |  |  |
| the licence is read and the screen answers | PASS | 28608 | 45000 |
| what was read is shown back: number and authority on screen | PASS |  |  |
| the company profile is attached | PASS |  |  |
| the Supplier Agreement page opens | PASS | 303 | 5000 |
| licence fields read correctly (number, legal name, authority, expiry, activities) | PASS |  |  |
| Submit answers at once and says what is wrong | PASS | 224 | 30000 |
| the expired licence is flagged honestly and never approved | PASS |  |  |
| the licence step itself says the licence has expired (before Submit) | PASS |  |  |

Licence read (row): {"trade_license_no":"ZZ-261150","licence_legal_name":"ZZ DEMO Wadi Painting Contracting LLC","license_authority":"Ras Al Khaimah Department of Economic Development","license_expiry":"2026-08-31","licence_read_state":"read","company_name":"ZZ DEMO Wadi Painting Contracting LLC"}
Shown back: {"note":"This trade licence (ZZ-261150) expired on 31 Aug 2026, so we cannot register it. Please upload your renewed trade licence here. If the renewal is still with the licensing authority, you can save your other details now and upload the renewed licence as soon as it is issued.","licence_no":"ZZ-261150","authority":"Ras Al Khaimah Department of Economic Development"}
Proposals: {}
Final: {"approval_status":"action_required","licence_gate_reason":"reg_terms"}
Arabic seen: [{"where":"agreement page","text":"كوتس دن للتكنولوجيا"}]
Message faults: []
Errors: []
Environment faults (an answer not from the site, see the HTTP line): []
HTTP 4xx/5xx met by the page: ["400 https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/supplier_portal","400 https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/supplier_api"]
Language switch shown: [{"where":"supplier page","text":"العربية"},{"where":"agreement page","text":"العربية"}]
Dead end: none
Messages read: ["Supplier portal — QuotesDone","html[data-qd-portal=\"mounted\"] #qd-portal-boot{display:none}#qd-portal-boot{max-width:420px;margin:18vh auto 0;padding:0 16px;text-align:center;font-size:15px;l","This trade licence (ZZ-261150) expired on 31 Aug 2026, so we cannot register it. Please upload your renewed trade licence here. If the renewal is still with the"]

## Run 2 (tag 2777f7ae)

Spend by tag: USD 0.0218 (21 calls). Untagged reader spend in the window: USD 0. Notifications before teardown: [{"status":"suppressed","channel":"email","n":7},{"status":"suppressed","channel":"whatsapp","n":7}]; dispatched 0. Teardown: {"leftovers":{"auth_users":0,"customers":0,"leads":0,"inquiries":0,"quotes":0,"quote_spec_hold":0,"quote_reviews":0,"notifications":0,"transactions":0,"refunds":0,"supplier_dues":0,"refund_case":0,"inquiry_intake":0,"email_verifications":0,"storage_objects":0,"assistant_logs":0,"support_customer_profile":0,"support_case":0,"assistant_logs_run_tag":0,"sales_decision_log":0,"support_reply_readability":0,"total":0,"knowledge_gaps_filed":0,"org_tasks_filed":0},"sink":[{"auth_users":0,"email_verifications":0,"notifications":0,"leads":0},{"auth_users":0,"email_verifications":0,"notifications":0,"leads":0},{"auth_users":0,"email_verifications":0,"notifications":0,"leads":0},{"auth_users":0,"email_verifications":0,"notifications":0,"leads":0},{"auth_users":0,"email_verifications":0,"notifications":0,"leads":0},{"auth_users":0,"email_verifications":0,"notifications":0,"leads":0},{"auth_users":0,"email_verifications":0,"notifications":0,"leads":0},{"auth_users":0,"email_verifications":0,"notifications":0,"leads":0}],"fixture_licences_still_held":0}

### J1 desktop (direct): L1_dubai_det_bilingual.pdf + P1_mep_contractor.pdf

| step | result | ms | budget |
|---|---|---:|---:|
| the supplier page is interactive | PASS | 289 | 3000 |
| the sign-up form opens | PASS | 1113 | 3000 |
| "Create my account" sends the code and opens the code box | PASS | 1441 | 10000 |
| the code e-mail arrives | PASS |  |  |
| the code verifies and "Register your company" opens | PASS | 939 | 3000 |
| "Create company" opens the registration form | PASS | 1413 | 3000 |
| the mobile: refused before any SMS, recorded verified, the form shows "Mobile verified" (harness path) | PASS |  |  |
| the licence is read and the screen answers | PASS | 14092 | 45000 |
| what was read is shown back: number and authority on screen | PASS |  |  |
| the company profile is attached | PASS |  |  |
| the Supplier Agreement page opens | PASS | 333 | 3000 |
| "Submit for approval" ends in the supplier workspace | PASS | 7147 | 20000 |
| the Services tab opens | PASS | 90 | 3000 |
| services are proposed from his documents | PASS | 47036 | 120000 |
| the proposals are his trades, nothing absurd | PASS |  |  |
| proposed services start unticked | PASS |  |  |
| "Tick all proposed services" ticks every one | PASS | 101 | 3000 |
| licence fields read correctly (number, legal name, authority, expiry, activities) | FAIL |  |  |
| his own trade's services ticked from the checklist | PASS |  |  |
| "Confirm my services" confirms them | PASS | 1773 | 20000 |
| approved and verified | FAIL | 60494 | 60000 |
| the portal home opens | PASS | 1609 | 3000 |

Licence read (row): {"trade_license_no":"ZZ-1290417","licence_legal_name":"ZZ DEMO Saker Electromechanical Contracting LLC","license_authority":"Dubai Department of Economy and Tourism","license_expiry":"2027-02-15","licence_read_state":"read","company_name":"ZZ DEMO Saker Electromechanical Contracting LLC"}
Shown back: {"note":"Read your licence — ZZ-1290417, expires 2027-02-15.","licence_no":"ZZ-1290417","authority":"Dubai Department of Economy and Tourism"}
Proposals: {"trades":["electrical","hvac","mep_general","plumbing"],"right":["electrical","hvac","mep_general","plumbing"],"acceptable":[],"absurd":[],"ok":true}
Final: {"approval_status":"pending","verified":false,"licence_gate_reason":"documents_being_read","licence_read_state":"read","company_name":"ZZ DEMO Saker Electromechanical Contracting LLC","missing_of_six":"{}"}
Arabic seen: [{"where":"agreement page","text":"كوتس دن للتكنولوجيا"}]
Message faults: []
Errors: []
Environment faults (an answer not from the site, see the HTTP line): []
HTTP 4xx/5xx met by the page: ["400 https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/supplier_portal"]
Language switch shown: [{"where":"supplier page","text":"العربية"},{"where":"agreement page","text":"العربية"}]
Dead end: none
Messages read: ["Supplier portal — QuotesDone","html[data-qd-portal=\"mounted\"] #qd-portal-boot{display:none}#qd-portal-boot{max-width:420px;margin:18vh auto 0;padding:0 16px;text-align:center;font-size:15px;l","Read your licence — ZZ-1290417, expires 2027-02-15.","To be verified, confirm what your company does. Below is the summary and the keywords our sales engineer prepared from your company profile. Check them, correct","Voice input is coming soon. Please type your services for now.","Saved. Your services are confirmed."]

### J2 mobile (invite): L2_abu_dhabi_added.pdf + P2_joinery.pdf

| step | result | ms | budget |
|---|---|---:|---:|
| the invitation link opens the sign-up | PASS | 1625 | 5000 |
| "Claim my listing" is offered on the invitation | PASS |  |  |
| "Create my account" sends the code and opens the code box | PASS | 1355 | 15000 |
| the code e-mail arrives | PASS |  |  |
| the code verifies and the invited company's registration form opens, claimed | PASS | 3902 | 5000 |
| the form says whose listing it is ("Finish registering") | PASS |  |  |
| the mobile: refused before any SMS, recorded verified, the form shows "Mobile verified" (harness path) | PASS |  |  |
| the licence is read and the screen answers | PASS | 14463 | 45000 |
| what was read is shown back: number and authority on screen | PASS |  |  |
| the company profile is attached | PASS |  |  |
| the Supplier Agreement page opens | PASS | 296 | 5000 |
| "Submit for approval" ends in the supplier workspace | PASS | 6523 | 30000 |
| the Services tab opens | PASS | 127 | 5000 |
| services are proposed from his documents | PASS | 19672 | 120000 |
| the proposals are his trades, nothing absurd | PASS |  |  |
| proposed services start unticked | PASS |  |  |
| "Tick all proposed services" ticks every one | PASS | 76 | 5000 |
| licence fields read correctly (number, legal name, authority, expiry, activities) | PASS |  |  |
| his own trade's services ticked from the checklist | PASS |  |  |
| "Confirm my services" confirms them | PASS | 2376 | 30000 |
| approved and verified | PASS | 2321 | 60000 |
| the portal home opens | PASS | 2262 | 5000 |

Licence read (row): {"trade_license_no":"CN-ZZ482137","licence_legal_name":"ZZ DEMO Ghaf Joinery and Carpentry LLC","license_authority":"Abu Dhabi Department of Economic Development","license_expiry":"2027-05-03","licence_read_state":"read","company_name":"ZZ DEMO Ghaf Joinery and Carpentry LLC"}
Shown back: {"note":"Read your licence — CN-ZZ482137, expires 2027-05-03.","licence_no":"CN-ZZ482137","authority":"Abu Dhabi Department of Economic Development"}
Proposals: {"trades":["joinery"],"right":["joinery"],"acceptable":[],"absurd":[],"ok":true}
Final: {"approval_status":"approved","verified":true,"licence_gate_reason":null,"licence_read_state":"read","company_name":"ZZ DEMO Ghaf Joinery and Carpentry LLC","missing_of_six":"{}"}
Arabic seen: [{"where":"agreement page","text":"كوتس دن للتكنولوجيا"}]
Message faults: []
Errors: []
Environment faults (an answer not from the site, see the HTTP line): []
HTTP 4xx/5xx met by the page: ["400 https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/supplier_portal"]
Language switch shown: [{"where":"agreement page","text":"العربية"}]
Dead end: none
Messages read: ["html[data-qd-portal=\"mounted\"] #qd-portal-boot{display:none}#qd-portal-boot{max-width:420px;margin:18vh auto 0;padding:0 16px;text-align:center;font-size:15px;l","Read your licence — CN-ZZ482137, expires 2027-05-03.","To be verified, confirm what your company does. Below is the summary and the keywords our sales engineer prepared from your company profile. Check them, correct","Voice input is coming soon. Please type your services for now.","Saved. Your services are confirmed. Your registration is approved. Matching inquiries now reach you in the Inquiries tab."]

### J3 desktop (direct): L3_jafza.pdf + P3_building_materials_trader.docx

| step | result | ms | budget |
|---|---|---:|---:|
| the supplier page is interactive | PASS | 281 | 3000 |
| the sign-up form opens | PASS | 1317 | 3000 |
| "Create my account" sends the code and opens the code box | PASS | 2159 | 10000 |
| the code e-mail arrives | PASS |  |  |
| the code verifies and "Register your company" opens | PASS | 1599 | 3000 |
| "Create company" opens the registration form | PASS | 1392 | 3000 |
| the mobile: refused before any SMS, recorded verified, the form shows "Mobile verified" (harness path) | PASS |  |  |
| the licence is read and the screen answers | PASS | 13781 | 45000 |
| what was read is shown back: number and authority on screen | PASS |  |  |
| the company profile is attached | PASS |  |  |
| the Supplier Agreement page opens | PASS | 300 | 3000 |
| "Submit for approval" ends in the supplier workspace | PASS | 5940 | 20000 |
| the Services tab opens | PASS | 71 | 3000 |
| services are proposed from his documents | PASS | 23771 | 120000 |
| the proposals are his trades, nothing absurd | PASS |  |  |
| proposed services start unticked | PASS |  |  |
| "Tick all proposed services" ticks every one | PASS | 64 | 3000 |
| licence fields read correctly (number, legal name, authority, expiry, activities) | PASS |  |  |
| his own trade's services ticked from the checklist | PASS |  |  |
| "Confirm my services" confirms them | PASS | 1854 | 20000 |
| approved and verified | PASS | 2301 | 60000 |
| the portal home opens | PASS | 1603 | 3000 |

Licence read (row): {"trade_license_no":"ZZ-719044","licence_legal_name":"ZZ DEMO Dune Building Materials Trading FZE","license_authority":"Jebel Ali Free Zone Authority","license_expiry":"2027-09-20","licence_read_state":"read","company_name":"ZZ DEMO Dune Building Materials Trading FZE"}
Shown back: {"note":"Read your licence — ZZ-719044, expires 2027-09-20.","licence_no":"ZZ-719044","authority":"Jebel Ali Free Zone Authority"}
Proposals: {"trades":["building_materials"],"right":["building_materials"],"acceptable":[],"absurd":[],"ok":true}
Final: {"approval_status":"approved","verified":true,"licence_gate_reason":null,"licence_read_state":"read","company_name":"ZZ DEMO Dune Building Materials Trading FZE","missing_of_six":"{}"}
Arabic seen: [{"where":"agreement page","text":"كوتس دن للتكنولوجيا"}]
Message faults: []
Errors: []
Environment faults (an answer not from the site, see the HTTP line): []
HTTP 4xx/5xx met by the page: ["400 https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/supplier_portal"]
Language switch shown: [{"where":"supplier page","text":"العربية"},{"where":"agreement page","text":"العربية"}]
Dead end: none
Messages read: ["Supplier portal — QuotesDone","html[data-qd-portal=\"mounted\"] #qd-portal-boot{display:none}#qd-portal-boot{max-width:420px;margin:18vh auto 0;padding:0 16px;text-align:center;font-size:15px;l","Read your licence — ZZ-719044, expires 2027-09-20.","To be verified, confirm what your company does. Below is the summary and the keywords our sales engineer prepared from your company profile. Check them, correct","Voice input is coming soon. Please type your services for now.","Saved. Your services are confirmed. Your registration is approved. Matching inquiries now reach you in the Inquiries tab."]

### J4 mobile (direct): L4_ajman_phone_photo.jpg + P4_hvac.pdf

| step | result | ms | budget |
|---|---|---:|---:|
| the supplier page is interactive | PASS | 353 | 5000 |
| the sign-up form opens | PASS | 1372 | 5000 |
| "Create my account" sends the code and opens the code box | PASS | 1395 | 15000 |
| the code e-mail arrives | PASS |  |  |
| the code verifies and "Register your company" opens | PASS | 1364 | 5000 |
| "Create company" opens the registration form | PASS | 1371 | 5000 |
| the mobile: refused before any SMS, recorded verified, the form shows "Mobile verified" (harness path) | PASS |  |  |
| the licence is read and the screen answers | PASS | 11426 | 45000 |
| what was read is shown back: number and authority on screen | PASS |  |  |
| the company profile is attached | PASS |  |  |
| the Supplier Agreement page opens | PASS | 317 | 5000 |
| "Submit for approval" ends in the supplier workspace | PASS | 15584 | 30000 |
| the Services tab opens | PASS | 97 | 5000 |
| services are proposed from his documents | PASS | 26790 | 120000 |
| the proposals are his trades, nothing absurd | PASS |  |  |
| proposed services start unticked | PASS |  |  |
| "Tick all proposed services" ticks every one | PASS | 51 | 5000 |
| licence fields read correctly (number, legal name, authority, expiry, activities) | PASS |  |  |
| his own trade's services ticked from the checklist | PASS |  |  |
| "Confirm my services" confirms them | PASS | 1363 | 30000 |
| approved and verified | PASS | 2437 | 60000 |
| the portal home opens | PASS | 2716 | 5000 |

Licence read (row): {"trade_license_no":"ZZ-307721","licence_legal_name":"ZZ DEMO Pearl Air Conditioning Contracting Est","license_authority":"Ajman Department of Economic Development","license_expiry":"2027-03-10","licence_read_state":"read","company_name":"ZZ DEMO Pearl Air Conditioning Contracting Est"}
Shown back: {"note":"Read your licence — ZZ-307721, expires 2027-03-10.","licence_no":"ZZ-307721","authority":"Ajman Department of Economic Development"}
Proposals: {"trades":["hvac"],"right":["hvac"],"acceptable":[],"absurd":[],"ok":true}
Final: {"approval_status":"approved","verified":true,"licence_gate_reason":null,"licence_read_state":"read","company_name":"ZZ DEMO Pearl Air Conditioning Contracting Est","missing_of_six":"{}"}
Arabic seen: [{"where":"agreement page","text":"كوتس دن للتكنولوجيا"}]
Message faults: []
Errors: []
Environment faults (an answer not from the site, see the HTTP line): []
HTTP 4xx/5xx met by the page: ["400 https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/supplier_portal"]
Language switch shown: [{"where":"supplier page","text":"العربية"},{"where":"agreement page","text":"العربية"}]
Dead end: none
Messages read: ["Supplier portal — QuotesDone","html[data-qd-portal=\"mounted\"] #qd-portal-boot{display:none}#qd-portal-boot{max-width:420px;margin:18vh auto 0;padding:0 16px;text-align:center;font-size:15px;l","Read your licence — ZZ-307721, expires 2027-03-10.","To be verified, confirm what your company does. Below is the summary and the keywords our sales engineer prepared from your company profile. Check them, correct","Voice input is coming soon. Please type your services for now.","Saved. Your services are confirmed. Your registration is approved. Matching inquiries now reach you in the Inquiries tab."]

### J5 desktop (direct): L5_rakez_scan.pdf + P5_packaging_brochure_image_only.pdf

| step | result | ms | budget |
|---|---|---:|---:|
| the supplier page is interactive | PASS | 216 | 3000 |
| the sign-up form opens | PASS | 1242 | 3000 |
| "Create my account" sends the code and opens the code box | PASS | 2039 | 10000 |
| the code e-mail arrives | PASS |  |  |
| the code verifies and "Register your company" opens | PASS | 858 | 3000 |
| "Create company" opens the registration form | PASS | 1363 | 3000 |
| the mobile: refused before any SMS, recorded verified, the form shows "Mobile verified" (harness path) | PASS |  |  |
| the licence is read and the screen answers | PASS | 14554 | 45000 |
| what was read is shown back: number and authority on screen | PASS |  |  |
| the company profile is attached | PASS |  |  |
| the Supplier Agreement page opens | PASS | 309 | 3000 |
| "Submit for approval" ends in the supplier workspace | PASS | 7423 | 20000 |
| the Services tab opens | PASS | 68 | 3000 |
| services are proposed from his documents | PASS | 51994 | 120000 |
| the proposals are his trades, nothing absurd | PASS |  |  |
| proposed services start unticked | PASS |  |  |
| "Tick all proposed services" ticks every one | PASS | 87 | 3000 |
| licence fields read correctly (number, legal name, authority, expiry, activities) | PASS |  |  |
| his own trade's services ticked from the checklist | PASS |  |  |
| "Confirm my services" confirms them | PASS | 1883 | 20000 |
| approved and verified | PASS | 2391 | 60000 |
| the portal home opens | PASS | 1625 | 3000 |

Licence read (row): {"trade_license_no":"ZZ-5047219","licence_legal_name":"ZZ DEMO Najm Packaging Industries FZ-LLC","license_authority":"Ras Al Khaimah Economic Zone Authority","license_expiry":"2027-06-29","licence_read_state":"read","company_name":"ZZ DEMO Najm Packaging Industries FZ-LLC"}
Shown back: {"note":"Read your licence — ZZ-5047219, expires 2027-06-29.","licence_no":"ZZ-5047219","authority":"Ras Al Khaimah Economic Zone Authority"}
Proposals: {"trades":["corrugated_packaging","rigid_plastic_packaging"],"right":["corrugated_packaging","rigid_plastic_packaging"],"acceptable":[],"absurd":[],"ok":true}
Final: {"approval_status":"approved","verified":true,"licence_gate_reason":null,"licence_read_state":"read","company_name":"ZZ DEMO Najm Packaging Industries FZ-LLC","missing_of_six":"{}"}
Arabic seen: [{"where":"agreement page","text":"كوتس دن للتكنولوجيا"}]
Message faults: []
Errors: []
Environment faults (an answer not from the site, see the HTTP line): []
HTTP 4xx/5xx met by the page: ["400 https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/supplier_portal"]
Language switch shown: [{"where":"supplier page","text":"العربية"},{"where":"agreement page","text":"العربية"}]
Dead end: none
Messages read: ["Supplier portal — QuotesDone","html[data-qd-portal=\"mounted\"] #qd-portal-boot{display:none}#qd-portal-boot{max-width:420px;margin:18vh auto 0;padding:0 16px;text-align:center;font-size:15px;l","Read your licence — ZZ-5047219, expires 2027-06-29.","To be verified, confirm what your company does. Below is the summary and the keywords our sales engineer prepared from your company profile. Check them, correct","Voice input is coming soon. Please type your services for now.","Saved. Your services are confirmed. Your registration is approved. Matching inquiries now reach you in the Inquiries tab."]

### J6 mobile (direct): L6_sharjah_sedd.pdf + P6_bus_rental_bilingual.pdf

| step | result | ms | budget |
|---|---|---:|---:|
| the supplier page is interactive | PASS | 527 | 5000 |
| the sign-up form opens | PASS | 917 | 5000 |
| "Create my account" sends the code and opens the code box | PASS | 1894 | 15000 |
| the code e-mail arrives | PASS |  |  |
| the code verifies and "Register your company" opens | PASS | 1362 | 5000 |
| "Create company" opens the registration form | PASS | 1374 | 5000 |
| the mobile: refused before any SMS, recorded verified, the form shows "Mobile verified" (harness path) | PASS |  |  |
| the licence is read and the screen answers | PASS | 14439 | 45000 |
| what was read is shown back: number and authority on screen | PASS |  |  |
| the company profile is attached | PASS |  |  |
| the Supplier Agreement page opens | PASS | 301 | 5000 |
| "Submit for approval" ends in the supplier workspace | PASS | 7018 | 30000 |
| the Services tab opens | PASS | 136 | 5000 |
| services are proposed from his documents | PASS | 35706 | 120000 |
| the proposals are his trades, nothing absurd | PASS |  |  |
| proposed services start unticked | PASS |  |  |
| "Tick all proposed services" ticks every one | PASS | 56 | 5000 |
| licence fields read correctly (number, legal name, authority, expiry, activities) | PASS |  |  |
| his own trade's services ticked from the checklist | PASS |  |  |
| "Confirm my services" confirms them | PASS | 1881 | 30000 |
| approved and verified | PASS | 2275 | 60000 |
| the portal home opens | PASS | 2113 | 5000 |

Licence read (row): {"trade_license_no":"ZZ-748113","licence_legal_name":"ZZ DEMO Corniche Passenger Transport LLC","license_authority":"Sharjah Economic Development Department","license_expiry":"2027-01-07","licence_read_state":"read","company_name":"ZZ DEMO Corniche Passenger Transport LLC"}
Shown back: {"note":"Read your licence — ZZ-748113, expires 2027-01-07.","licence_no":"ZZ-748113","authority":"Sharjah Economic Development Department"}
Proposals: {"trades":["staff_transport"],"right":["staff_transport"],"acceptable":[],"absurd":[],"ok":true}
Final: {"approval_status":"approved","verified":true,"licence_gate_reason":null,"licence_read_state":"read","company_name":"ZZ DEMO Corniche Passenger Transport LLC","missing_of_six":"{}"}
Arabic seen: [{"where":"agreement page","text":"كوتس دن للتكنولوجيا"}]
Message faults: []
Errors: []
Environment faults (an answer not from the site, see the HTTP line): []
HTTP 4xx/5xx met by the page: ["400 https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/supplier_portal"]
Language switch shown: [{"where":"supplier page","text":"العربية"},{"where":"agreement page","text":"العربية"}]
Dead end: none
Messages read: ["Supplier portal — QuotesDone","html[data-qd-portal=\"mounted\"] #qd-portal-boot{display:none}#qd-portal-boot{max-width:420px;margin:18vh auto 0;padding:0 16px;text-align:center;font-size:15px;l","Read your licence — ZZ-748113, expires 2027-01-07.","To be verified, confirm what your company does. Below is the summary and the keywords our sales engineer prepared from your company profile. Check them, correct","Voice input is coming soon. Please type your services for now.","Saved. Your services are confirmed. Your registration is approved. Matching inquiries now reach you in the Inquiries tab."]

### J7 desktop (direct): L7_dmcc.pdf

| step | result | ms | budget |
|---|---|---:|---:|
| the supplier page is interactive | PASS | 300 | 3000 |
| the sign-up form opens | PASS | 1210 | 3000 |
| "Create my account" sends the code and opens the code box | PASS | 1550 | 10000 |
| the code e-mail arrives | PASS |  |  |
| the code verifies and "Register your company" opens | PASS | 1409 | 3000 |
| "Create company" opens the registration form | PASS | 1896 | 3000 |
| the mobile: refused before any SMS, recorded verified, the form shows "Mobile verified" (harness path) | PASS |  |  |
| the licence is read and the screen answers | PASS | 13623 | 45000 |
| what was read is shown back: number and authority on screen | PASS |  |  |
| licence fields read correctly (number, legal name, authority, expiry, activities) | PASS |  |  |

Licence read (row): {"trade_license_no":"DMCC-ZZ8401","licence_legal_name":"ZZ DEMO Marina Steel Trading DMCC","license_authority":"Dubai Multi Commodities Centre Authority","license_expiry":"2027-04-13","licence_read_state":"read","company_name":"ZZ DEMO Marina Steel Trading DMCC"}
Shown back: {"note":"Read your licence — DMCC-ZZ8401, expires 2027-04-13.","licence_no":"DMCC-ZZ8401","authority":"Dubai Multi Commodities Centre Authority"}
Proposals: {}
Final: {}
Arabic seen: []
Message faults: []
Errors: []
Environment faults (an answer not from the site, see the HTTP line): []
HTTP 4xx/5xx met by the page: ["400 https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/supplier_portal"]
Language switch shown: [{"where":"supplier page","text":"العربية"}]
Dead end: none
Messages read: ["Supplier portal — QuotesDone","html[data-qd-portal=\"mounted\"] #qd-portal-boot{display:none}#qd-portal-boot{max-width:420px;margin:18vh auto 0;padding:0 16px;text-align:center;font-size:15px;l","Read your licence — DMCC-ZZ8401, expires 2027-04-13."]

### J8 mobile (direct): L8_rak_ded_expired.pdf + P1_mep_contractor.pdf

| step | result | ms | budget |
|---|---|---:|---:|
| the supplier page is interactive | PASS | 347 | 5000 |
| the sign-up form opens | PASS | 932 | 5000 |
| "Create my account" sends the code and opens the code box | PASS | 1383 | 15000 |
| the code e-mail arrives | PASS |  |  |
| the code verifies and "Register your company" opens | PASS | 1365 | 5000 |
| "Create company" opens the registration form | PASS | 1369 | 5000 |
| the mobile: refused before any SMS, recorded verified, the form shows "Mobile verified" (harness path) | PASS |  |  |
| the licence is read and the screen answers | PASS | 15926 | 45000 |
| what was read is shown back: number and authority on screen | PASS |  |  |
| the company profile is attached | PASS |  |  |
| the Supplier Agreement page opens | PASS | 251 | 5000 |
| licence fields read correctly (number, legal name, authority, expiry, activities) | PASS |  |  |
| Submit answers at once and says what is wrong | PASS | 140 | 30000 |
| the expired licence is flagged honestly and never approved | PASS |  |  |
| the licence step itself says the licence has expired (before Submit) | PASS |  |  |

Licence read (row): {"trade_license_no":"ZZ-261150","licence_legal_name":"ZZ DEMO Wadi Painting Contracting LLC","license_authority":"Ras Al Khaimah Department of Economic Development","license_expiry":"2026-08-31","licence_read_state":"read","company_name":"ZZ DEMO Wadi Painting Contracting LLC"}
Shown back: {"note":"This trade licence (ZZ-261150) expired on 31 Aug 2026, so we cannot register it. Please upload your renewed trade licence here. If the renewal is still with the licensing authority, you can save your other details now and upload the renewed licence as soon as it is issued.","licence_no":"ZZ-261150","authority":"Ras Al Khaimah Department of Economic Development"}
Proposals: {}
Final: {"approval_status":"action_required","licence_gate_reason":"reg_terms"}
Arabic seen: [{"where":"agreement page","text":"كوتس دن للتكنولوجيا"}]
Message faults: []
Errors: []
Environment faults (an answer not from the site, see the HTTP line): []
HTTP 4xx/5xx met by the page: ["400 https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/supplier_portal","400 https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/supplier_api"]
Language switch shown: [{"where":"supplier page","text":"العربية"},{"where":"agreement page","text":"العربية"}]
Dead end: none
Messages read: ["Supplier portal — QuotesDone","html[data-qd-portal=\"mounted\"] #qd-portal-boot{display:none}#qd-portal-boot{max-width:420px;margin:18vh auto 0;padding:0 16px;text-align:center;font-size:15px;l","This trade licence (ZZ-261150) expired on 31 Aug 2026, so we cannot register it. Please upload your renewed trade licence here. If the renewal is still with the"]

## The paid round

```
node scripts/e2e/supplier_registration_certification.mjs --paid --runs 2 --cap-usd 1.5
```

Expected: {"documents_read":14,"runs":2,"per_run_p50_usd":0.2785,"per_run_p90_usd":0.8875,"total_p50_usd":0.5571,"total_p90_usd":1.7749,"cap_usd_total":1.5,"cap_usd_per_run":0.75,"parts_p90":{"licence_reads":0.0215,"profile_and_trade_reads":0.6675,"registration_turns":0.1984},"basis":"ai_cost_log, last 30 days, per (fn, task_class): p50 and p90 cost per call x the calls one certification run makes; the cap is enforced per run by fn_kernel_paid_provider_gate"}
