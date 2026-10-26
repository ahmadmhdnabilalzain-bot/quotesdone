# Non-web channels: QA run on production, 19 Oct 2026 (00:08-00:40 UTC)

Real models throughout (ruling 1260). The model calls were Sonnet 5.5 for conversation_reply and GPT-6 Luna for routing. Only ZZ DEMO identities were used: fixture mobiles +971500000056/57/07/19/81, plus qd-founderdemo-cust1@ and qd-0af178e3-sup1@example.invalid.

WhatsApp tests went through the authenticated internal JSON path (cred_ops_wa_replay). Email tests used a Svix-signed POST to resend_inbound.

| # | Scenario | Result | Evidence / root cause |
|---|---|---|---|
| 1 | WA customer question, English | PASS (content) | Sonnet answered correctly: 3-5 working days, free, 3% reveal fee. |
| 2 | WA customer question, Arabic | PASS (content) | Answered in Arabic with the same facts. |
| 3 | WA voice note | INCONCLUSIVE | The synthetic OGG was not a real recording. The reply said it could not open the file and asked for a resend or a typed summary. Voice notes are not transcribed: route `media_in` sends them to the document reader. |
| 4 | WA photo inquiry | PASS (handling) | The 1x1 PNG was read as unreadable, and the reply asked for a clearer copy and for material, size and emirate. |
| 5 | Talk to a person (menu `qd_person`) | **FAIL** | The handoff to customer_support was correct. But a fixture number **paged the founder**: founder_alert 103774 went to him by email and 103775 by WhatsApp. Root cause: `fn_wa_human_request` calls `fn_notify_founder` without checking `fn_is_demo_phone`. The demo capture trigger cannot see it, because a founder alert has no lead, inquiry or quote id. Fix: PR #1494. |
| 6 | Slow model turn gives the held notice and escalates | **FAIL** | Turns took 54-55 s (5 in parallel) and 111-155 s (single turn under load). None of them sent a held notice. |
| 7 | Reply within 45 s, and it is the model's answer | **FAIL** | Same runs as #6. ai_cost_log shows about 8 serial routing calls (routine_employee_reasoning and customer_communication, 4-32 s each) before the conversation_reply starts. Root cause: the 45 s deadline (WA_REPLY_BUDGET_MS) is counted from the start of `modelSays`, not from arrival. Fix: PR #1488 counts the clock from arrival, so a slow turn gets the held notice inside 45 s and is filed for escalation. Not fixed: the serial routing calls themselves. |
| 8 | Email: customer reply | PASS (partial) | The model answered within about 10 s. It said it "cannot see your request's live status" even though the sender is a registered customer (inquiry_id is null on the reply). |
| 9 | Email: supplier quotation | **FAIL** | The quotation was triaged `customer_question` and answered **as a customer**, explaining the 3% reveal fee (notification 103801). Root cause: `email_triage` hard-codes `audience: 'customer'`. Fix: PR #1490 uses the supplier relation from `fn_mail_sender_known` and answers suppliers in English. |
| 10 | Outbound notices: language | PASS for EN; **NOT MEASURED for AR** | 30 days of demo outbox: every customer and supplier notice is English, and every inquiry is `lang='en'`. No Arabic inquiry exists among demo or real rows in 60 days, so "a customer gets their inquiry's language" has no evidence either way. Suppliers: all English (correct). |
| 11 | Outbound: links | PASS | quotesdone.com/me and /portal both return 200. |
| 12 | Outbound: unsubscribe headers | PASS | send_outbox has 50/50 unit tests (List-Unsubscribe and One-Click Post, In-Reply-To threading, Arabic RTL). The live /u/unsubscribe answers 400 to a bad token on GET and POST, through a 308 from www to the apex domain. |
| 13 | Leak test (WA, every reply plus an explicit probe; email) | PASS | The probe asked for the supplier's phone and email and for other customers' names and prices. Both answers refused and explained the reveal fee. No other party's identifiers appeared in any reply. |
| 14 | Fixture send noise | **FAIL (minor)** | Each captured fixture WA send filed a support_ceo_report saying "A WhatsApp reply could not be delivered" (13811, 13812, 13887, 13890). Fix: on PR #1494, `!isDemoPhone(From)` guards the report. |

Also seen: one turn (ZZDEMOQB6) stayed at `stage: received` for about 2 min while the 00:30 function deploy ran, then completed.

## Clean-up (exact ids, one transaction, verified at 0 remaining)
- wa_messages 564-572, 576, 577; wa_inbound_seen ZZDEMOQB1-7; wa_conversation 86, 89, 90
- inbound_messages 483, 484; notifications 103774, 103775, 103800, 103801; founder_alerts 146f8d4a-…
- support_case 1241-1245; support_customer_profile 250-254; support_ceo_report 13811, 13812, 13887, 13890
- agent_actions 258882, 258990, 258991; company_event 1057118, 1057119; file_scan 745
- Left in place: log rows only (agent_runs, os_audit_log, ai_cost_log).
