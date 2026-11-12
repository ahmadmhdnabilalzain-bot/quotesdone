# Code integration review (it_engineer reviewer), 11 Nov 2026

Scope: the ~30 PRs merged on 11 Nov (#1915 to #1949) read TOGETHER. main = 2cc9d1017. Free workstream: no model call was made by
this review, nothing was written to production, no message was sent. Production was read with SELECTs only.
All paths below are under `supabase/functions/` unless they start with `src/` or `scripts/`.

## VERDICT: GO WITH FIXES

Four fixes should land before real people are invited (F1, F3, F4, F5). None is large. No security regression was found in today's diff.

## What was tested

| What | Pass bar | Measured | Result |
|---|---|---|---|
| Existing Deno tests: wa_inbound, send_outbox, send_whatsapp, site_assistant, login_otp, email_triage, inquiry_intake, ai_gateway, dropbox_backup | 0 failed | 679 passed, 0 failed | PASS |
| Existing Deno tests: _shared, supplier_api, supplier_portal, sales_engineer, customer_api | 0 failed | 2,515 passed, 1 failed (`_shared/read_ceiling.test.ts:26`) | FAIL (F10) |
| WhatsApp holding line is sent once per 10 min and recorded | a notifications row per holding line | 9 fixture turns reached the record step, 0 rows of type `wa_holding_notice` exist | FAIL (F1) |
| Case memory reaches the reply, a summary is written after an exchange | summaries > 0 | 15 case decisions, 0 inside the 4 s wait (min 5.3, p50 8.7, max 17.3 s); 0 summaries, 0 promises, 0 summary calls | FAIL (F2) |
| A late licence read cannot write onto another file | row fields belong to the file the row names | offline proof: row names file B, carries A's number, authority, expiry, name | FAIL (F3) |
| A second, different notice with the same wording is not dropped | not a duplicate | offline proof on the guard's own key: dropped | FAIL (F4) |
| High effort stays inside each call's own timeout | 0 timeouts | marketing internal_judgement 4 of 4 failed at 46.7 to 47.2 s after the change (143 of 143 ok on 5 to 11 Nov before it); WhatsApp job reader 2 of 10 rows failed at ~27 s; WhatsApp reading max 19.2 s of a 20 s cap (n 14) | FAIL (F5) |
| WhatsApp reply time, live fixture turns 22:42 to 22:52 UTC (another workstream's run) | founder: 30 to 40 s acceptable for a complicated question | 10 typed turns: min 27.9, p50 32.9, max 49.5 s (the complaint) | measured, see F5 |
| Burst merging on production | one reply per burst | run 1: "Hi" answered alone, the other two merged; run 2: all three merged | PASS with a note (F7) |
| New tables under RLS, routines revoked and search_path pinned | all | mailbox_reply_decision, support_case_promise, support_case_summary_version: RLS on, deny-all policy, no anon/authenticated grant; 21 new routines: anon and authenticated cannot execute, search_path pinned | PASS |
| Load stub reachable by a real visitor | never | tag is per request (AsyncLocalStorage), honoured only with the service key or internal secret, window must be opened by load_test with models_allowed false | PASS (code read) |
| Registration hedge (4 s) can double a write or a model call | never | only `state`, `me`, `dashboard` are hedged; all five server handlers behind those names only select | PASS (code read) |
| Sign-in speed-ups weaken a check | no | limiters still in series, code spent in one statement, sanctions still refused before a user, link or session exists | PASS (code read) |
| Portal chat, widget, intake, e-mail triage, supplier mailbox gate, promise watch, Dropbox case files after today's changes | exercised on production | 0 model calls from inquiry_intake, site_assistant, sales_engineer, email_triage, supplier_api since 11:05 UTC; 0 mailbox_reply_decision rows | NOT RUN (free workstream; nothing ran them) |

## Findings

### F1. BLOCKER. The WhatsApp holding line is never recorded, so the same line goes out on every message
- Where: `wa_inbound/holding.ts:45` writes the notifications row with `requested_by: 'wa_inbound'`.
- Root cause (verified): production trigger `a05_notifications_sender_of_record` (`fn_notifications_sender_of_record`) raises
  check_violation unless requested_by is 'platform' or an active `org_role` seat. `org_role` has no 'wa_inbound'. The insert's
  error is discarded (`.then(() => null, () => null)`), and `holding.test.ts`'s fake table accepts any row.
- Evidence: 9 fixture turns on production carry `timings.holding = 'fixture_captured'` (the branch that awaits the insert);
  `select count(*) from notifications where type='wa_holding_notice'` is 0, all time.
- Scenario: a customer sends three questions two minutes apart. Each reply takes 28 to 50 s (measured), so the 9 s timer fires
  each time. The duplicate guard reads notifications for an earlier holding line, finds none, and sends it again. The person
  reads "Thank you for your message. I'm reviewing it now and will reply here shortly." before every answer. Ruling 1631 is the
  rule this breaks. Nothing in the history or the outbox counts shows the line was sent.
- Proof: `proofs/p4_holding_and_summary.test.ts` (F-HOLDING: three turns, three sends, zero rows).
- Fix: `requested_by: 'customer_support'`; raise an it_engineer finding when the insert errors; make the test's table apply a05.

### F2. HIGH. The case model never reaches a reply and writes nothing
- Where: `wa_inbound/case_memory.ts:13` and `_shared/case_context.ts:25` (CASE_READ_MS 4,000) race `caseMemoryFor`, which asks a
  model (`support.case_match`) whenever the person has an open case. `fn_support_touch` opens one on the first message, so the
  model is asked on every turn.
- Evidence (seat_judgement, 11 Nov after 22:42 UTC): 15 decisions, 0 within 4 s, min 5.3, p50 8.7, max 17.3 s. After 10 answered
  typed turns: 0 rows in support_case_summary_version, 0 in support_case_promise, 0 `case_summary` calls. 9 cases were opened
  for 7 numbers; one five-message chat about windows became 3 cases.
- Effect: ruling 1635 (summary after each exchange), the promise ledger and the Dropbox case file do nothing. Each turn pays one
  extra model call. On the portal, the signed-in widget and e-mail the turn awaits the same 4 s first (`loadCaseContext`), so
  those replies are 4 s slower for no gain (NOT MEASURED there: no traffic).
- Also in this path, all latent until the above is fixed: (a) the writer refuses a stale version and nothing retries, so two
  quick exchanges lose the second summary (`fn_support_case_summary_write`, SQL line 106); (b) a WhatsApp reply adopted from the
  speculative draft is never summarised (`wa_inbound/say.ts:107`, `!signal`); (c) F12.
- Fix: decide by code when the newest open case moved in the last N minutes (continue it, no model); ask the model only after a
  gap, and never on the reply's path.

### F3. HIGH. A slow licence read writes its fields onto a newer licence file
- Where: `supplier_api/actions/documents.ts:334` (`askLicenceModel`, added by #1947) updates `leads` by supplier id only.
- Scenario: a supplier uploads licence A (a scan). The model has not answered in 10 s, the form says it is being read. He
  uploads licence B. B is read and the row is right. A's read then finishes and writes its number, authority, expiry, legal
  name and read state 'read' onto the row that names file B. The sweep does not read it again. Verification then judges file B
  on A's details (an expired A marks a valid B expired, or the reverse).
- Proof: `proofs/p3_licence_race.test.ts`, the repo's own process_docs harness; the late PATCH filter is `?id=eq.990001`.
- Fix: the late write (and the issue-date write) carry `.eq('license_doc_path', <the path this read was for>)`.

### F4. HIGH. The duplicate guard drops different notices that share wording
- Where: `_shared/outbox_duplicate_guard.ts:43` and the a00 trigger (`scripts/sql/notifications_refuse_the_same_message_...sql`).
  The key is channel, type, recipient, subject, body. It ignores inquiry_id, quote_id, lead_id, html and attachments.
- Scenarios: (1) `supplier_api/lib/quote_acceptance.ts:52` writes the same subject and body for every quote on a request; a
  second supplier's quote inside 10 minutes cancels the customer's notice. (2) `messages_api/index.ts:429` writes a fixed
  sentence; two customers messaging one supplier about two requests inside 10 minutes gives one notice.
- Proof: `proofs/p1_messages.test.ts` (F-DEDUPE-1, F-DEDUPE-2). Production has cancelled 0 rows so far (there are no quotes yet).
- Fix: add inquiry_id, quote_id and lead_id to the key in both twins.

### F5. HIGH. Higher effort runs into timeouts that were not changed
- Where: `_shared/effort_policy.ts:83,88,89` raise the WhatsApp reading, the intake trade and the intake spec reader from low to
  high; the gateway gives every unnamed call its class effort. Unchanged: `_shared/think/deps.ts:93` (45 s default),
  `wa_inbound/classification.ts:21` (20 s), `wa_inbound/say.ts:78` (25 s), the intake's 24 s turn clock.
- Measured: marketing `internal_judgement` 4 of 4 failed at 46.7 to 47.2 s since 22:17 UTC, against 143 of 143 ok from 5 to 11
  Nov before the change (max 41.2 s); its plan call now writes 4,036 output tokens against about 1,800. WhatsApp job reader
  (`json_extraction`): 2 of 10 rows failed at ~27 s (0 of 27 before, max 18.2 s). WhatsApp reading: max 19.2 s of 20 s, n 14.
- NOT MEASURED: the intake chat (0 turns since the change). #1938's own report calls it "at risk" and its side-by-side was not run.
- Fix: keep the three capped surfaces at their earlier effort until `scripts/eval/effort_low_vs_high.mjs` has run, or raise each
  cap with the effort; give think() a longer default for high.

### F6. MEDIUM. The portal assistant swallows a repeated short answer for 60 s
- Where: `_shared/turn_replay.ts:11`, used at `sales_engineer/actions/portal.ts:106`. The stored row is written when our reply ends.
- Scenario: "Do you need delivery?" "yes". "Do you need installation?" "yes" 20 s later. The second yes returns the stored
  reply again and is not read or stored. Proof: `proofs/p1_messages.test.ts` (F-REPLAY). Fix: a 5 s window, or a client turn id.

### F7. MEDIUM. A burst whose leading turn dies loses the other messages
- Where: `wa_inbound/burst.ts:61-73`. Merged rows are marked 'merged'; the leader's row keeps only its own text until the turn ends.
- If the leader's worker dies, `fn_wa_arrival_sweep` hands customer_support only "hi", and `_shared/wa_history.ts` skips merged
  rows for good. Proof: `proofs/p2_burst.test.ts`. Fix: write the combined text to the leader's row when it claims the others.
- Note: on the first live run "Hi" was answered alone (the next message's row was not yet stored when the leader decided).

### F8. MEDIUM. The loop cap silences a person who repeats one message
- Where: `_shared/auto_reply_loop.ts:33`; the gate runs before the founder is identified (`wa_inbound/index.ts`, turnGate).
- The same 20+ character message four times in an hour gets no fourth reply, from anyone including the founder's own number.
  Proof: `proofs/p1_messages.test.ts` (F-LOOP). Fix: count only auto-reply phrases, and exempt the founder's number.

### F9. MEDIUM. Supplier mailbox rules that will meet invited suppliers (stated in #1939; consequence not measured: 0 decisions exist)
- SQL line 185: once the founder has replied by hand to an address, no later mail from it to supplier@ is answered automatically, in any thread.
- SQL line 186: a second question in the same thread on the same day is not answered.

### F10. MEDIUM. main fails its own test suite since #1947
- `_shared/read_ceiling.test.ts:26` looks for `readLicenceName(licBytes.bytes`, which #1947 renamed. The ceiling itself is intact
  (`supplier_api/actions/documents.ts:115` stands before the read at line 124). `npm test` runs this file, so #1947 to #1949 merged red.

### F11. LOW
- The a00 trigger skips rows inserted with the column default 'pending' (SQL line 36); 9 database routines insert that way,
  `fn_inbox_send` among them. The send-time guard still covers them.
- Two outbox runs each holding one of two identical rows cancel both (`send_outbox/index.ts`, recentSends keeps other runs' 'sending' rows). Proof: F-DEDUPE-3.
- `_shared/licence_read_state.ts:73` (10 s): 31 of 93 licence reads in 7 days took longer, so the Documents tab aborts a paid read about one time in three and the sweep pays again.

### F12. MEDIUM, latent. A promise the customer claimed can be recorded as ours
- `_shared/support_case_memory.ts:84` accepts a promise whose words appear anywhere in the previous summary, including its ASKED line. Proof: `proofs/p4_holding_and_summary.test.ts` (F-PROMISE). Fix: compare with our reply and the recorded promises only.

## Spend and teardown
Spend: USD 0 (no model call, no run tag). Production writes: 0. Nothing to tear down. Proof tests live only in this folder.
