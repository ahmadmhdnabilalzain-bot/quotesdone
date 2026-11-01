# The whole picture: what would stop or embarrass a real supplier or customer (2 Nov 2026)

**Seat:** `it_engineer`. **Read-only:** nothing was changed in production and nothing was sent.
**Measured at:** 2 Nov 00:11 Dubai (1 Nov 20:11Z), production `htdblwldjkcgjvmqkbeh`, code at `origin/main` 0d57a7c5.
**Asked by:** founder ledger 1447, 1436, 1438, 1448.
M = measured here. I = inferred from measurements, and the reasoning is given.

## The answer

No real supplier has finished sign-up. 72 invitations have gone out since 28 Oct (52 confirmed sent, 18 still queued, 2 more counted on 28 Oct). One supplier replied and started. **0 have submitted, 0 are approved.**
The email machinery at its legal maximum delivers about 1,800 invitations by 31 Dec, which at the measured rate gives about 35 sign-up starts against a target of 300-400. The CEO seat holds the target and reports the miss every day, but no CEO routine can change anything that would close the gap.

## Ranked: everything that would stop or embarrass a real person

| # | Item | Evidence | Owner | Fix size | Code or founder |
|---|---|---|---|---|---|
| 1 | **The target cannot be reached on this machinery, and the CEO cannot change that** | M: 0 of the `fn_ceo_*` routines write a cap, a lead or a channel switch. Daily "Supplier target behind" tasks stay open. E: at most ~1,800 delivered. Section F | ceo | L | Code, plus the access list in F |
| 2 | **The bounce brake will stop the campaign, and 82% of the list is unchecked** | M: limit 3% (`invite_max_bounce_rate`), measured 7 of 52 (13.5%). `enqueue_supplier_invites` sets `invite_enabled=false` when over the limit on 15+ sends in 3 days. 14,202 of 17,330 eligible leads have no email check; 43 eligible are marked `not_found`; 71 have typo domains (`yahoo.coin`). I: the pause fires on the next run whose window holds a batch with a bounce: Mon 2 Nov or Tue 3 Nov. Nothing resumes it except a hand setting the flag | it_engineer + customer_support | M | Code (cheque-free checks), verifier needs a key |
| 3 | **A supplier who replies to our answer writes to a mailbox nobody reads** | M: code reads only `supplier@` (`resilience_ping` → `m365_reply_inbox`, every 15 min) and `*@mail.`. The answers go out from `info@quotesdone.com` by default. 0 inbound rows ever to `info@quotesdone.com` or `management@quotesdone.com`, yet those two are the addresses published on the site, portals and error messages. I: this is where Al Gouri's subsidiary reply went (ledger 1436). The stored 30 Oct reply has no subsidiary text, and our answer left at 12:04Z the same day from the unread address. `email_reply_info` was not read; the code default was | customer_support | S-M | Code. Mail read permission on those mailboxes may need access (F) |
| 4 | **Replies to invitations wait with no actor** | M: `invite.reply` for Al Gouri pending since 30 Oct. `mailbox.supplier_reply` for 666realestate (reply 28 Oct, filed 1 Nov) pending. `fn_sales_engineer_takes_invite_reply` is still STABLE: it changes nothing. `fn_supplier_mailbox_mail_gets_its_owner` files and nothing reads. Audit H2 open | sales_engineer | S | Code |
| 5 | **A started sign-up is not chased** | M: Al Gouri verified email and mobile on 30 Oct and stopped before the licence. Its only messages in 3 days are the invitation and one answer. No reminder was sent | sales_engineer | S | Code |
| 6 | **A foreign or unread licence authority is approved automatically** | M: `fn_sales_engineer_verifies_supplier` and `fn_supplier_mandatory_six` never test `license_authority`; `auto_approve_suppliers=true`. Contradicts Supplier Agreement v16 cl. 13. Audit H3 open. Audit reason not to fix alone still stands: the held path has no decider (H5) | sales_engineer | M | Code |
| 7 | **The real document reading has never been proved in production** | M: 0 of 14,755 `supplier_capabilities` rows hold a document record. All 12 demo approvals used fixture licence fields ("Dubai DET (fixture)") with `doc_extracted_at` null. So 1 Nov's green rehearsals approved without reading a licence or a profile through the path a real supplier uses | sales_engineer | M | Code: a real-file walk |
| 8 | **The public phone number is the founder's mobile; voice on our line hangs up** | M: `src/content/marketing.json` publishes the mobile ending 9355 (the number on `admin_mfa_phone` per memory). `voice_otp` answers calls with "WhatsApp only" and hangs up. 0 rows ever in `customer_calls`, `supplier_voice_note`, `sms_messages`. Conflicts with ledger 1438 | customer_support | S to replace, L for a voice seat | Code; voice per F |
| 9 | **The founder is paged by our own rehearsals** | M: `rfq_no_supplier` fired 55 times, 30 in 14 days, 6 on 1 Nov 18:46-19:46Z, the same hour as the demo approvals. Of 55, only 3 name an inquiry still existing. All 6 inquiries belong to `example.invalid` customers. **They are probes, not customers.** Fix: no page for a probe | it_engineer | S | Code |
| 10 | **Any real customer today would reach nobody** | M: 0 suppliers verified, 0 real rows in `inquiry_matches`. Customers open January by ruling, but the site takes requests now. I: the seat that answers has nothing to send. What they are told was not walked | sales_engineer | S check | Code |
| 11 | **An invited lead is reported as sent when it was not** | M: 18 of the 28 Oct batch are still `queued` (not before 4 Nov), yet `invite_schedule` and `v_invite_deliverability_daily` count 20 sent that day. Bounce rate there reads 7/70, not 7/52. See memory `a-status-column-is-not-a-delivery-record` | customer_support | S | Code |
| 12 | **Replies counted by founder tests sit in review** | M: 5 of 6 `supplier@` rows are `needs_review`; 3 are the founder's own test replies. Only harm: real ones are hidden among them | sales_engineer | S | Code |

Audit of 28 Oct (PR #1725), re-measured:
- H1 nudging a supplier who replied: closed (M: nudge list now reads replies).
- H2 no actor for `invite.reply`: **open** (item 4). H3 authority: **open** (item 6). H5 no decider on a held registration: **open**, re-read of the function shows no route after the 24 h report.
- H4 triage cache: closed by #1714.
- Queues in that audit: `spec.not_sure` 5 still pending and no routine reads the type. `reasoning_held_question` no longer holds 327: 1 open, because the rest expired (M: `sales_engineer` 586 expired). **An expired question was never answered** and is not a clean queue.

## A. Every way in

| Channel | Read by | How often | Seat | Proof in 30 days | Verdict |
|---|---|---|---|---|---|
| `supplier@quotesdone.com` (invitations) | `resilience_ping` → `m365_reply_inbox` → `resend_inbound` → `email_triage` | 15 min | customer_support answers; sales_engineer owns | 6 rows; last 30 Oct; 1 real answered, 1 real unanswered | Works, thin |
| `info@quotesdone.com` (site, portals, From of our answers) | **nothing** | - | none | 0 rows ever | **NOBODY READS** |
| `management@quotesdone.com` (contact page, chat, error messages; 8 source files) | only `inbox_placement`, for folders, not content | - | none | 0 rows ever | **NOBODY READS** |
| `info@mail.`, `expenses@mail.` | `resend_inbound` | webhook | triage, accountant | Last `@mail.` row 10 Oct; 14 expenses rows in review since Sep | Alive, unproved since 10 Oct |
| `docs@mail.`, `suppliers@mail.`, `support@`, `help@quotesdone.ae`, `docs@`, `no-reply@` (code only) | not traced beyond `resend_inbound` | - | none | 0 rows | Not published on the site. Remove or route |
| Contact form | `contact_submit` → `contact_messages` | on send | none found | 4 rows, all ZZ DEMO, all `new` | **No reader seen**; no real use yet |
| Homepage widget | `site_assistant` | live | customer_support | 49 open cases, last 27 Oct | I: rehearsals. Not separated from real |
| Portal chat | `messages_api`, `agent_chats` | live | sales_engineer | `agent_chats` last 7 Sep | Not proved on the live path |
| WhatsApp in | `wa_inbound` → model answer | live | customer_support | 46 rows, **all fixture numbers**, `sent` false. Last real row is the founder, 22 Sep | Never run with a stranger |
| SMS in | `sms_inbound` | live | none | 0 rows ever | Unused |
| Phone | `voice_otp` plays and hangs up | - | none | 0 calls | **Nobody answers** |
| Published mobile (founder) | the founder | - | - | not measurable | **Should not be the way in** |
| Social | `marketing_social_inbox` | daily | marketing | 19 rows, last 12 Oct | Quiet |

## B. Every dead end

1,118 pending handoffs (1,094 when asked). Oldest is 22 Sep, not 4 Oct. Ranked by a person waiting.

| Type | n | Seat | Age | Consumer | Closes? | Person waiting? |
|---|---|---|---|---|---|---|
| `invite.reply` | 1 | sales_engineer | 3 d | STABLE handler only | Stamps as answered, does nothing | **Yes: Al Gouri** |
| `mailbox.supplier_reply` | 1 | sales_engineer | 1 d | none | No | **Yes, possibly: 666realestate** ("Definitely but later") |
| `spec.not_sure` | 5 | sales_engineer | 15-21 d | **none** | No | I: fixture intakes (no customer linked). Would strand a real one |
| `support.case_open` | 39 | customer_support | 5 d | closed when the case closes | Case rarely closes: 21 WhatsApp + 14 widget + 5 email open | I: rehearsals; 1 real supplier thread is waiting on him |
| `knowledge.request` | 56 | ceo 37, sales_engineer 19 | 1-6 d | deadline tick only | Nobody writes the answer | Next answer to the same question is weak |
| `ceo.directive` | 2 | sales_engineer | 5 d | followup | Directive 326480 asks SE for 140 invitations; **customer_support sends them** | Target only |
| `ceo.revise`, `ceo.root_cause`, `deliberation.review`, `ceo.month_directive` | 37 | various | up to 36 d | refile | Partly | No |
| `it.finding` | 970 | support 754, ceo 105, sales 67, marketing 22, accountant 22 | up to 41 d | chase and closure | 4,199 closed in 60 d, 346 new in 7 d on support | No: mostly `delivery_health` noise. Hides real items |

Other queues:
- Notifications: 18 `supplier_invite` queued (item 11). `suppressed` rows are all demo. No real person lost.
- `inbound_messages.needs_review`: 19 open. 14 accountant, oldest 23 Sep; 5 in `supplier@` (item 12).
- Alerts with no owner: `founder_alerts` is a log with no owner column. 58 `alert_tick_partial` to 19 Oct, 48 `inquiry_contact_masked`, 30 `rfq_no_supplier` in 14 days.
- `ceo_task`: 66 of 133 opened in 7 days still open.

## C. The real sign-up, invitation to first RFQ

Real = only Al Gouri (lead 19398) ever got past invited. "Demo last" is a fixture run.

| Step | Code path | Owner | Proof | Last real | Last demo | If it fails |
|---|---|---|---|---|---|---|
| Invite | `enqueue_supplier_invites`, `send_outbox/m365_lane` | customer_support | notification sent | 30 Oct | - | Brake pauses, no resume owner |
| Reply | `m365_reply_inbox`, `email_triage` | customer_support | inbound row | 30 Oct | - | Item 3 |
| Link | **none**: invitation carries no link by ruling; supplier goes to quotesdone.com or is sent there | - | `invite_clicked_at` | 30 Oct (1) | - | No owner |
| Account, email code | `login_otp`, `supplier_portal` | sales_engineer | `owner_email_verified` | 30 Oct | 1 Nov | Portal error |
| Mobile code | `mobile_otp` | sales_engineer | `owner_phone_verified` | 30 Oct | 1 Nov | Portal error |
| Company details, trades | `supplier_portal` | sales_engineer | `portal_updated_at` | 30 Oct | 1 Nov | **No owner** (item 5) |
| Licence upload + read | `supplier_portal` code read; `license_extract` behind flag | sales_engineer | `licence_legal_name`, `doc_extracted_at` | **never** | fixture only | Held; **no decider** |
| Profile upload + read | `doc_extract`, `supplier_capabilities.source_docs` | sales_engineer | `source_docs.docs` | **never** | **never (0 rows)** | Stuck-read path unproved |
| Terms | `supplier_portal` | sales_engineer | `signed_terms_at` | **never** | 1 Nov | - |
| Submission | `supplier_portal` | sales_engineer | `registration_submitted_at` | **never** | fixture | - |
| Decision | `fn_sales_engineer_verifies_supplier` | sales_engineer | `supplier_verification` | **never** (the 1 non-demo row is a ZZ DEMO probe) | 1 Nov | Held, **no decider** |
| Notice | `fn_sales_engineer_writes` | sales_engineer | `supplier_approved` | **never** | suppressed | - |
| First RFQ | matching, `inquiry_matches` | sales_engineer | match row | **never** | 1 Nov | Founder paged |

**Never run for a real supplier:** licence read, profile read, terms, submission, decision, notice, first RFQ.
**Never run for anyone:** profile read recorded in `source_docs`.
**No owner when failing:** link step, started-and-stopped, held decision.
**Authority check:** still absent (item 6). Measured from the live function, not from the rollback replay.

## D. The buyer side

| Step | Proof | Last real | Last demo | Note |
|---|---|---|---|---|
| Request | `inquiries` 6, all `example.invalid` | never | 1 Nov | 2 customers not flagged demo; neither has an inquiry |
| Matching | `inquiry_matches` 9 | never | 1 Nov | 0 real suppliers matchable |
| Quote | `quotes` 11, all demo | never | 1 Nov | |
| Comparison | `quote_compare` | never | 1 Nov (I) | Not re-walked |
| Reveal | `reveal_invoices` 0-1 | never | 18 Sep | |
| Payment | Stripe path; `reveal.paid` handoffs 40 | never | 27 Oct | `refund.*` ran on probes |

Customers open January by ruling. Harm today is item 10 only.

## E. The target: what the machinery can deliver at most

| Input | Value |
|---|---|
| Registered real, verified real | **0, 0** (`fn_ceo_supplier_target_status`) |
| Eligible never-invited pool | 17,330 |
| Of which checked | 3,085 (`verified` 2,083, `true` 661, `maps` 321, `social` 20) |
| Of which unchecked | 14,202; 6,186 of the pool on `emirates.net.ae` and `eim.ae` |
| Bounce | 7 of 52 (13.5%); limit 3%; ramp grows only under 2% |
| Cap | `invite_daily_cap` 30, `fn_invite_founder_cap` 40 this week then 50; weekdays only |
| WhatsApp | `wa_supplier_invite_golive` false; opt-ins **0 of 2,863**; `wa_sender_quality_reading` 0 rows (a gate that needs a reading no routine writes) |
| Phone | No outbound routine |
| Ads | `meta_autospend_golive` false; cap AED 30/day; 0 campaigns; ledger 1004 keeps paid closed until every category has 10 verified, which needs the suppliers ads would bring |

Maximum by 31 Dec, assuming no pause:
- Sends: 5 days × 40 + 37-39 days × 50 = **2,050-2,150**. (I: the cap stays where the ramp lets it; at 13.5% the ramp halves, not grows.)
- Delivered at 86.5%: **~1,800**.
- Starts at the measured 1 of 52 (n = 1, so weak): **~35**. Submitted so far: 0.
- For 300 you need 16.7% of delivered, or ~18,000 sends at the measured rate: more than the whole pool and 8× the cap.

**Verdict (I): email alone gives tens, not hundreds.** Reaching 300-400 needs a checked list, more sending capacity, a human-voice channel and the sign-up proved. Nothing here says it is achievable even then; the first real conversion numbers will say. Risk: ledger 1449 forbids risking the email being blocked, so volume comes only after the list is clean.

## F. Who can act (founder ruling 1438, 2 Nov)

**Does the CEO hold the target? Partly.**
- `fn_ceo_supplier_target_status` hard-codes 50 / 200 / 300 by 31 Dec, in **verified**, not registered. 400 is nowhere. Ledger 1436 and 1438 are recorded in `founder_instruction`, open and standing, and no routine reads them.
- `ceo_plan.month_target` for November says 75 verified, 100 registered, 2,440 invites. It was written 28 Sep, assumes 125 from October (actual 0), and 2,440 exceeds the cap (~1,000 in November).
- `ceo_constraint_lever` for invitations begins "While the campaign switch is the founder's". The CEO's plan routine is written to defer to him.

**What the CEO actually does in a week (M, last 7 days):**
- Reads and reports: 32 duties. 7 five-number reports, digests, 507 `delivery.request` (messages through support).
- Paper: 87 `ceo.improvement`, 32 decisions closed, 8 `ceo.revise`, 7 `ceo.root_cause`, 133 tasks (66 open), 5 month directives.
- Real effect outside the seats: **none found.** The plan of 30 Oct, 31 Oct and 1 Nov was decided by `plan_c_code`, "already open" directive 326480 each day. A new "Supplier target behind" task every day, opened and left.
- The only `fn_ceo_*` routines touching an invitation setting only read it.

**What each seat can execute today (M from code and live settings):**

| Action | ceo | sales_engineer | marketing | customer_support | it_engineer |
|---|---|---|---|---|---|
| Email a supplier | no | via support | via support | **yes, the sender** | no |
| Change caps | **no** | no | no | no | no (ramp only lowers/grows inside a code literal) |
| Pause campaign | no | no | no | no | **yes** (brake) |
| Resume campaign | **no** | no | no | no | no: a hand |
| WhatsApp message to a stranger | no | no | gated, 0 eligible | answers only | no |
| Phone call | no | no | no | no | no |
| Run ads | no | no | switch off | no | no |
| Buy or use a tool | **no** | no | no | no | no |
| Clean a list | no | no | no | no | MX/`mx_ok` only, no paid check |
| Connect a mailbox | no | no | no | no | M365 app exists; Exchange role unproved |
| Reassign work | **yes** (handoff, directive) | files | files | files | files |

**Gated on the founder or a switch only a human flips:**
- `fn_invite_founder_cap`: a dated literal in code (ruling 1231).
- `invite_enabled` after any pause, and `founder_hold.supplier_campaign` ("until you say").
- `wa_supplier_invite_golive`, `meta_autospend_golive`, `bd_outreach_enabled`.
- Marketing calendar: "the founder's one-step approval" in the November directive. Conflicts with 1438.
- `auto_approve_suppliers`, ledger 1004 (paid closed).

### What the target needs

Founder's only part below is the last column. "None" means none.

| Capability | Exists? | Build | Access needed from the founder |
|---|---|---|---|
| Target held as 300-400 registered | Partly | Target row read by plan and status; rebased path | None |
| CEO owns caps, resume, channels inside limits | No | CEO policy routine replacing dated literal, with its brakes; sender seat re-pointed; 1438 recorded as superseding 1231 and the holds | None |
| Answers and sign-up proved with a real file | No | Walk with a real-format licence and profile; fix what breaks; decider for held | None |
| Replies owned (items 3, 4, 5) | Partly | Read `info@`, `management@` through the M365 app; act on `invite.reply`; reminders | None if the existing app's Mail.Read covers those mailboxes (scope not measured, 18 Oct saw Mail.Read). If scoped: Entra admin sign-in to consent |
| Clean list | Partly | Free: syntax, typos, MX, drop `not_found`. Paid: batch check before each send | One API key for an email-verification vendor, on a card the company pays. Cost quoted first, per memory |
| More sending capacity, safely | No | Warm additional mailboxes under a subdomain, rotation in the lane | Sign-in to the DNS host for `quotesdone.com` (records for SPF, DKIM, DMARC) and to the M365 admin to add mailboxes, or Exchange Administrator for the app (unproved in `exo_transport_rule.ts`) |
| WhatsApp from opt-in | Built, 0 fuel | Consent question inside email reply and portal; sender-quality reading | Sign-in or token for Meta Business/Twilio that reads the WABA, only if the current Twilio key lacks it (not measured) |
| Outbound voice | No | Twilio voice line + model, call log, consent and calling rules checked first (not researched here) | Twilio console sign-in if a UAE number needs the regulatory bundle (licence is on file); a company number that is not his mobile |
| Ads for supplier recruitment | Built, off | Lift ledger 1004 for recruitment under 1438; CEO budget rule; landing | Meta ad account payment method confirmed, and re-grant only if `marketing_connection_check` shows the token refused (not read here) |
| New leads | Paused | Apify until ~Feb 2027 per memory; own-channel posts only | None for now |
| Tool buying | No | Spend rule under the accountant with ceiling | A company card usable by the agents, or vendor keys issued one by one as above |

## Not measured

- Whether Monday's or Tuesday's run pauses first: not replayed, to avoid touching the live gate.
- Whether Al Gouri's second reply sits in `info@`: the mailbox was not opened.
- `email_reply_info` live value, Meta and Twilio token scopes, M365 mailbox scopes.
- Widget and portal chat conversations were not read one by one; "rehearsal" there is inferred from dates and no real party.
- Conversion rate rests on one supplier. It is a floor for planning, not a forecast.
