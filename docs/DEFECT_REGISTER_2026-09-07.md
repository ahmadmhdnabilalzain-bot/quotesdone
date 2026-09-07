# Structural defect register — opened 7 September 2026

Every entry here was measured against the one production project on the date shown. Nothing in this
file is inferred, quoted from a session brief, or carried over from an earlier document. Where a
measurement was bounded, the boundary is stated in the entry.

**Status vocabulary.** `OPEN` measured and unfixed. `RULED` the founder has decided the answer and it
is not yet in code. `FIXED` deployed and re-measured. `WITHDRAWN` I asserted it and it was wrong.

**Lifecycle vocabulary**, because these five are routinely confused and each has a different fix:
does not exist / exists, scheduled nowhere / scheduled but inactive / active, never ran / ran,
changed nothing.

---

## A. Identity and verification

### D-01 A supplier becomes verified with no identity check at all — CRITICAL — OPEN

`fn_supplier_licence_gate` checks exactly three things: the licence document path is non-empty, the
licence number is non-empty, and the expiry, when one was read, is not in the past. It consults no
email, no OTP, no mobile, and no human or agent review. The trigger then sets `verified := true`, and
`fn_is_matchable` reads `verified`. So an uploaded PDF with a readable number is currently sufficient
to become an approved supplier that the matching path will return to customers.

**Consequence when the campaign runs.** Anyone who uploads any PDF becomes a quoting supplier.

**Fix shape.** Approval requires the founder's six: name, UAE mobile, email, trade licence, company
profile, signed terms. Identity proven by OTP on the email, with the mobile confirming, never selecting.

### D-02 A record is marked email-verified while holding no email — CRITICAL — OPEN

Lead 30466 carries `email_verified = 'verified'` with `email` null. Measured across the table, one row
is in that state today. The flag is therefore not derived from the email it claims to verify.

### D-03 Two columns encode verification and disagree — HIGH — OPEN

`leads.verified` is a boolean and `leads.verification_status` is text. Lead 30466 has `verified` true
and `verification_status` 'unverified' simultaneously. All 22,265 rows carry 'unverified', so nothing
writes that column and it is dead. Code reads `verified`; a reader looking at `verification_status`
would conclude the opposite.

### D-04 No agent review exists between upload and approval — CRITICAL — OPEN

The seat `supplier_verification`, Supplier Verification Reviewer, supply department, reporting to the
Business Development Manager, exists with the brief "verifies trade licences, certifications and
capability claims before a supplier is allowed to quote". It has **zero recorded runs, ever**.
`doc_reviews` holds 7 rows in total and none for the approved lead. The review step exists in the job
description and nowhere in code.

### D-05 A UAE landline passes where a UAE mobile is required — HIGH — RULED

Founder ruling, 7 Sep: the mandatory contact number is a **UAE mobile**. Lead 30466 holds
+971 4 258 7734, a Dubai landline, and `phone_e164` is null. Nothing in the approval path checks the
number's form or its country prefix.

---

## B. Documents

### D-06 Approval is not gated on documents — CRITICAL — OPEN

The view `v_supplier_doc_score` grades every lead. **No routine in the public schema reads it**,
measured by searching every function body. Approval is therefore decided without reference to the
document score. Across the estate 22,264 leads grade F and one grades D; the D is the approved one.

### D-07 The document score enforces a list the founder did not set — MEDIUM — RULED

The view scores against ten document types and annotates only the trade licence as mandatory. The
founder ruled on 7 Sep that exactly six things are mandatory: name, UAE mobile, email, trade licence,
company profile, signed terms and conditions, and that everything else is extra. The view's grade is
not the founder's bar and must not be used to decide approval or to report readiness.

I previously described the ten as mandatory. That was an overstatement and is withdrawn: see D-16.

### D-08 Stub documents satisfy the licence and profile requirements — HIGH — OPEN

The approved lead's trade licence PDF is 2,187 bytes and its company profile is 2,522 bytes. In the
same bucket a genuine trade licence is 226,938 bytes and a genuine company profile is 4,882,701 bytes.
Files of 186 bytes exist for another lead. Nothing checks that a document is plausibly a document.

### D-09 The whole document control loop is switched off — CRITICAL — OPEN

Five cron jobs, all inactive, all last run on **16 August 2026**.

| Job | Schedule | Last ran |
|---|---|---|
| `fn_document_controller()` | 04:25 daily | 16 Aug 2026 |
| `run_doc_reminders()` | 05:00 daily | 16 Aug 2026 |
| `fn_reconcile_doc_blocks(0)` | 03:15 daily | 16 Aug 2026 |
| `fn_doc_final_notice(7)` | 05:10 daily | 16 Aug 2026 |
| 5-minute document dispatcher | every 5 min | 16 Aug 2026 |

### D-10 Document ownership is split across two departments and the verifying half never runs — HIGH — OPEN

`doc_intel_manager`, Document Intelligence Manager, sits in **marketplace** under procurement and owns
classification, extraction and validation, with 10 runs, last on 5 Sep. `supplier_verification` sits in
**supply** under business development and owns the licence check before quoting, with zero runs ever.
A document is understood by one department and is supposed to be verified by another that has never
executed.

---

## C. The company's own machinery

### D-11 Fifty-three scheduled jobs stopped on one day — CRITICAL — OPEN

101 of 235 cron jobs are inactive. Of those, **53 last ran on 16 August 2026**, 11 on 10 August, 11 on
2 August, 7 on 15 August, and 8 have never run at all. Among the switched-off: the weekly compliance,
finance and marketing agents, the daily supply health check, the no-quote nudges, the auto-deploy and
the site auto-deploy. Whether this was one deliberate act or a failure is **not yet established**.

### D-12 KPI-missed tasks close without acting — CRITICAL — OPEN

`fn_kpi_review` opens a task for every missed KPI, correctly assigned. Of 134 such tasks ever opened,
113 are done and 21 cancelled; none was ever left open. The live scoreboard reads 45 MISSED, 35 NO
DATA, 8 NEAR, 32 MET. Task 576318, "Registered suppliers this calendar month, target 300, actual 0",
was created at 04:00 on 7 Sep and marked done at 07:51 the same morning in mode `determined`, with no
decision, no next step and no events recorded. **The close documents the miss instead of acting on it.**

### D-13 No variance ever travels the reporting line — HIGH — OPEN

`bd` reports to `ceo`; the manager chain exists in `org_agents.manager_key`. Zero notifications sent on
7 Sep mention a supplier or a KPI. The internal escalation queue holds zero rows for any of the six
supply seats and zero mentioning invitations or suppliers, ever.

### D-14 A computed number with no consumer — HIGH — OPEN

`v_deliverability` computes three-day and seven-day bounce percentages and a PAUSED state. No routine
reads it. The bounce sensor is wired correctly and the sender's own brake works, but nothing reports
the number to anyone.

---

## D. Channels

### D-15 WhatsApp has no owner and has never delivered a message — HIGH — OPEN

No active seat names whatsapp, twilio or sms in its responsibilities. The nearest owner is
`channel_specialist`, Lifecycle Channel Operations Specialist in customer experience, whose brief is
channel-agnostic and never names WhatsApp. Measured traffic: email 842 sent with the last on 7 Sep;
WhatsApp 13 rows, **`sent_at` null on all of them**, all status 'skipped', all type 'founder_alert',
between 31 Aug and 6 Sep. Zero cron jobs schedule anything WhatsApp, Twilio or SMS. `fn_wa_fanout`,
`fn_wa_context` and `fn_wa_lead_id` exist and are scheduled nowhere.

### D-15b The refund chase ladder is written and scheduled nowhere — HIGH — OPEN

`fn_refund_ladder_sweep` implements the founder's ladder and its own comment correctly names the
Customer Success Director as owner rather than creating a new agent. It sits on no cron schedule.

---

## E. Data integrity

### D-17 A path probe became the company's only approved supplier — CRITICAL — OPEN

Lead 30466, MERIDIAN MEP CONTRACTING LLC, carries `source = 'qd_probe_contact_removed_15aug2026'`. Its
Dropbox folder is "QuotesDone Backup / Suppliers / QD PATH PROBE - Meridian MEP Contracting LLC
registration walk-through not a tra..." and its signed-terms file is named
`QD_PATH_PROBE_-_Meridian_MEP_Contracting_LLC_registration_wa.pdf`. Its contact and signatory name is
the founder's own. It was never invited and never claimed. It is approved and verified, and it is
counted in `employee_kpi` as the company's total approved suppliers.

**The defect is not that the probe exists.** It is that neither the naming convention (ZZ DEMO) nor the
email convention (@example.invalid) caught it, because it used neither, and no marker is enforced at
write time. A fixture is currently indistinguishable from real business.

### D-18 Unauthorised supplier invitations reached real businesses — HIGH — OPEN

The sending provider's own log shows 110 emails with the subject "Invitation: become a founding
supplier on QuotesDone" to real outside addresses: 98 delivered, 11 bounced, 1 suppressed, between
12 Aug and the provider's retention limit. The bounce rate on that campaign is 10%, against a 2%
industry danger threshold, on the same domain that carries sign-in codes and receipts. The founder
states he never activated the campaign. The database corroborates the sends: 171 leads carry
`invited_at`, 10 carry `invite_status = 'bounced'`.

**Bounded:** the provider list reaches back only to 9 August, so July sends can be neither confirmed
nor denied from it.

---

## F. My own errors, recorded so they are not repeated

### D-16 I called ten documents mandatory when nobody had ruled it — WITHDRAWN

I read the ten-item missing array from `v_supplier_doc_score` and reported it as the mandatory set.
Only the trade licence is annotated mandatory in the view; the other nine were never ruled on. The
founder's actual list is six.

**Lesson: a view's own labels are a previous author's opinion, not a policy.**

### D-19 I reported one approved supplier as a genuine correction — WITHDRAWN

Having said zero suppliers registered, I corrected myself to one on the strength of an approved flag.
The founder doubted it and was right: it is a path probe. The true count of genuine verified suppliers
is zero.

**Lesson: an approval flag is a claim made by code, and code that was never gated makes claims that
mean nothing. Check what set the flag before repeating it.**

---

## What is not yet established

- Whether the 16 August mass switch-off was deliberate or a failure, and by what.
- Whether the July invitation sends happened, which the provider's retention cannot answer.
- Whether the customer-side path from request to paid reveal works end to end on real data.
- Whether any other business table carries fixtures that survive the naming conventions.

An eight-dimension adversarial audit covering these is running as of 7 Sep and its confirmed findings
will be added here with their verification verdicts.
