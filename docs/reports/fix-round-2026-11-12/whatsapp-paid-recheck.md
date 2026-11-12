# WhatsApp re-check after the fix round, 12 Nov 2026 (seat: customer_support, auditor)

Run tag `9b9460cb` (rehearsal window `qd_run:9b9460cb`, opened 05:33:55Z, closed 05:55:35Z).
Driven: the DEPLOYED `wa_inbound` version 440 (deployed 05:25:00Z, main b2990006b), real models through `ai_gateway`, real database, region ap-southeast-1 (pinned as Twilio's webhook is). Twilio-signed posts from four reserved fixture numbers: C1 +971 50 000 00 04 (customer, English, not in our records: the fix author's seven-message script), S ...01 (registered supplier), A ...03 (customer, Arabic, not in our records), K ...02 (registered customer). Harness: the audit's driver, adapted (`wa_recheck.mjs`, `spec1-4.json`). Every reply was captured on `wa_messages`; nothing was handed to Twilio. I fixed nothing, deployed nothing, applied nothing.

## VERDICT: GO WITH FIXES, and WhatsApp is still not at the founder's bar

Inviting by e-mail does not depend on this. Do not point a senior supplier or customer at the WhatsApp number until R1 is fixed, and the founder should know R2 is unchanged:

- **R1 (new, BLOCKER):** on every turn where the holding line went (3 of 3), the reply was delivered and the handler STILL filed the turn as "no reply after the holding line". A minute later a second answer was written by the larger model and handed to the send. A real person would get two answers to one message. Root cause proved by execution.
- **R2 (unchanged, BLOCKER):** no ordinary reply was fast. 17 ordinary typed messages: p50 27.7 s, p95 44.6 s, none under 15 s. The audit measured p50 30.2 s.
- Improved and proved: the holding line is recorded and goes once per person; cases now get summaries (17 versions from 19 exchanges; the script gave 2 cases and 6 versions); the promise ledger is written; no reply gave our own number (0 of 23); suppliers were answered in English, the Arabic customer in natural Arabic.

## What I did not run, and the budget

**The complaint tests, the two-photo test with a model, and the last 5 ordinary messages were NOT RUN.** The run reached its spend cap after 21 messages. This is my sequencing error as well as a product cost finding (R9): I ran the ordinary conversations first and forecast USD 0.0115 a turn from the first four stage-2 turns; one Arabic customer turn then cost USD 0.29 in a single minute (two parallel 35k-token cache writes on Sonnet 5.5).

**The hard cap of USD 0.80 was exceeded.** Tagged spend stopped at USD 0.7681 (the window cap of 0.78 refused everything after 05:46:34Z). But the product's re-ask job answered 8 of this run's turns again with UNTAGGED calls that no rehearsal cap sees: USD 0.4126 (16 calls). Total caused by this workstream: **USD 1.18**. Of the untagged part, USD 0.24 is defect R1 (3 re-asks of turns that had been answered), USD 0.03 is the two turns my cap refused, and USD 0.14 is mine alone: after the cap I sent three messages on K believing "no model allowed" meant "no spend"; the re-ask answered all three on Sonnet 5.5 at high effort. I removed the run's held questions at 05:53Z; no untagged re-ask call was logged after 05:52:28Z.

## What was tested

| # | Test | Bar | Measured on production | Result |
|---|---|---|---|---|
| 1 | Ordinary typed message, end to end | fast: p50 under 15 s | n=17 (C1 6, S 7, A 4): p50 27.7 s, p95 44.6 s, min 19.8 s, max 53.5 s; 0 under 15 s, 6 over 30 s, 3 over 40 s. Server clock (`timings.reply_written`, n=16): p50 26.9 s, p95 43.0 s | **FAIL** |
| 1 | Greeting ("Hi", "السلام عليكم": welcome + menu) | fast | 12.8 s and 12.7 s from arrival (16.5 s and 13.6 s on the harness clock; the first post waited 3.7 s for a cold start) | under 15 s, n=2 |
| 1 | Reviewer's prediction, ordinary reply | about 24 s | 26.9 s: burst wait + identify 4.2, reading 10.5, writing 11.1 (p50 each) | 3 s worse |
| 1 | Complaint / dispute (3 planned) | 30-40 s, ONE holding line first | not sent: the run was at its cap | **NOT RUN** |
| 1 | 24 ordinary messages | 24 | 19 answered by the model (17 ordinary + 2 greetings); 2 more were refused by my cap; 3 never sent | PARTIAL |
| 2 | Holding line only on a turn that passes 15 s | yes | 3 rows, written 15.06, 15.06 and 15.05 s after arrival; on turns whose reply came at 26.0, 34.8 and 27.5 s | PASS |
| 2 | One `wa_holding_notice` row per person per 30 minutes | exactly 1 | C1 1, S 1, A 1 (ids 143143, 143146, 143147; status `suppressed` = fixture capture; requester `platform`; key `wa_holding:<last9>:996923`). 0 `holding_unrecorded` findings | PASS |
| 2 | Never on a fast reply | none | the 2 replies ready before 15 s from arrival had no row | PASS (n=2) |
| 2 | Second slow turn inside the window | `already_held` | 14 of 14 later slow turns: `timings.holding` = `already_held`, no row | PASS |
| 2 | Wording professional and varied across people | varied | professional. NOT varied across people: both English people got wording 1 word for word, the Arabic person Arabic wording 1. By code a person's first line is always wording 1; it varies only for the same person after 30 minutes (not exercised) | **FAIL as specified** |
| 2 | Two photos together = one line | 1 row | sent only after the cap: with no model both turns ended in 5-6 s, so no line was due | **NOT PROVEN** |
| 2 | The real reply always follows | yes, once | it followed 3 of 3; then a SECOND answer was written 44-87 s later on 3 of 3 (R1) | **FAIL** |
| 3 | The seven-message script: cases | 2 | 2 (QD-S-NGSP89, QD-S-86P5LY) | PASS |
| 3 | Summary versions | at least 5 | 6 (5 + 1), read back 2 minutes after the last message. The summary of message 6 failed every try at its 47 s wall and was folded into the version written after message 7 | PASS |
| 3 | Catch-up beat writes a missing summary | yes | cannot be shown from fixture numbers: `fn_support_case_summaries_owed` returned `[]`; it skips ZZ DEMO numbers unless `decision_policy.demo_rehearsal_active` is true, and that read `false` with my window open. I may not change a switch | **NOT RUN** |
| 3 | Trade sentence at most once | 1 | the verbatim paragraph is in 2 of 7 replies (aluminium in reply 4; CLEANING in reply 6, wrongly: R4), plus a paraphrase in reply 6. Audit: every reply | **FAIL**, improved |
| 3 | No reply gives our own number | 0 | 0 of 23 replies carry any phone number | PASS |
| 3 | A promise we make lands in the ledger | row | 7 rows from 19 exchanges, all with an assumed 48-hour due. None is a commitment a person could keep (R8) | PASS mechanically |
| 3 | A promise the customer claims does not | no row | the message was sent (A7) and my cap refused the model | **NOT RUN** |
| 3 | Reply about the FIRST matter after the second opened | right context | right matter (windows), then a wrong paragraph about cleaning requests and "capped" (R4, R5) | PARTIAL |
| 3 | One open case per matter, other numbers | 1 per matter | S: 3 cases for 7 general questions in 5 minutes. A: 2 cases for one air-conditioning job. 7 cases for 3 people in 13 minutes (audit: 17 for 7 in 25) | **FAIL** (R7) |
| 3 | Dropbox case file | exists or reason | 0 `doc_backups` case rows, ever. The enqueue returns false for a person known only by a phone (no folder), and a ZZ DEMO supplier's row is dropped. Real-person path not proven, as in the audit | NOT PROVEN |
| 4 | Arabic customer answered in natural Arabic | yes | 5 of 5, formal and natural | PASS |
| 4 | Supplier answered in English only | yes | 7 of 7, including the supplier's Arabic question | PASS |
| 4 | No identity, no invented price | none | 0 names, e-mails or numbers of a counterpart; figures only AED 1,000 and 3%, both the database's | PASS |
| 4 | "Talk to a person" ("6") | honest | "Your message has been passed to our team." No hand-off, no CEO report, no hold exists for that number (R3) | **FAIL** |
| 5 | Effort recorded per call | readable | yes, every provider call ends `| effort sent: <v>` (table below) | PASS |
| 5 | Cost per reply | audit USD 0.032 | USD 0.040 (0.7681 / 19 model-written replies) | worse (R9) |
| 6 | Teardown, leftovers 0 | 0 | 32 checks all 0, incl. cases, versions, promises, holding rows; old audit cases 2221/2235/2236 gone; window closed | PASS (with hand steps: R12) |
| - | Memory across 5 turns; "which other suppliers quoted" | as audit | the two messages (S8, S9) were never sent | NOT RUN |
| - | Loop cap, typing indicator, voice note | - | not in this run | NOT RUN |

## Latency (seconds)

| kind | n | p50 | p95 | min | max | under 15 | over 30 | over 40 |
|---|---|---|---|---|---|---|---|---|
| ordinary typed message, harness clock | 17 | 27.7 | 44.6 | 19.8 | 53.5 | 0 | 6 | 3 |
| ordinary, server `reply_written` | 16 | 26.9 | 43.0 | 18.0 | 51.9 | 0 | 5 | 2 |
| greeting (welcome + menu), harness clock | 2 | 15.0 | 16.4 | 13.6 | 16.5 | 1 | 0 | 0 |
| all model-written replies | 19 | 27.4 | 43.5 | 13.6 | 53.5 | 1 | 6 | 3 |
| ordinary, customer English (C1) | 6 | 26.8 | 50.1 | 19.8 | 53.5 | 0 | 2 | 2 |
| ordinary, supplier (S) | 7 | 27.4 | 35.4 | 19.8 | 36.5 | 0 | 2 | 0 |
| ordinary, customer Arabic (A) | 4 | 30.7 | 40.8 | 24.7 | 42.4 | 0 | 2 | 1 |
| complaint / dispute | 0 | NOT RUN | | | | | | |

Harness clock = post to reply row visible (700 ms poll, about 1.6 s later than `reply_written`). `replied_at` is not set for a fixture reply, so "reply recorded" is this clock. The per-turn table and the call-by-call timeline of the seven script turns are in `latency.md`.

**Where the time goes** (16 ordinary turns that carry `timings`):

| phase | p50 | p95 | max |
|---|---|---|---|
| burst wait (4.0 s, by setting) + identify | 4.2 | 4.3 | 4.3 |
| the reading: intent + needs-a-person, one call at medium effort | 10.5 | 15.4 | 16.1 |
| route + facts | 0.1 | 0.1 | 0.1 |
| writing the reply (incl. lane declines and rewrites) | 11.1 | 24.7 | 31.4 |
| send + record + harness poll | 1.6 | 2.3 | 2.4 |
| total, server | 26.9 | 43.0 | 51.9 |

**What the next engineer should cut, in order of seconds:**
1. **The reply is asked only after the reading ends, every time.** `timings.speculative` = 0 on 16 of 16 turns (audit: 0 of 26). A draft IS started at 4.5 s and is ready at 10-14 s (script turn 5: ready at 11.2 s), then discarded; the reply is asked again at 14-20 s. Adopting it would end a one-draft turn at about 15 s instead of 26.
2. **The reading takes 10.5 s (p95 15.4 s) on a 20k-30k token prompt** for an intent and a yes/no. Medium effort (as #1952 set it) did not bring it under 10 s on production.
3. **A second pass on 5 of 16 turns: total p50 38.7 s against 26.3 s for one draft.** Three were lane declines (the status or app lane answers "can't confirm", then the full path is asked: +11 to +20 s). Three were rewrites to put a must-carry sentence back (+8 to +10 s).
4. The 4 s burst wait is the founder's setting. `conversation_reply` carries an 80k-token prompt (p50 9.2 s a call).

## Findings

### R1 - BLOCKER (new) - after a holding line, the person is answered twice
Evidence: `reasoning_held_question` 43213 (C1), 43214 (S), 43215 (A): surface `wa_inbound.unwritten_reply`, reason `no_reply_after_holding`, facts "The holding line was sent, then this turn stopped before a reply was sent. Answer their message now." Each was filed in the same second the turn's reply was recorded (05:35:34.8, 05:42:46.1, 05:43:19.0). The re-ask job then wrote a second answer on anthropic/claude-sonnet-5.5 at high effort 87, 76 and 44 s later and handed it to the WhatsApp send (`result.reask_delivery.via = whatsapp_text`). The fixture guard captured it, so it then counted as failed, a model-written notice was tried and the turn was escalated to customer_support. For a real number the send succeeds. `_shared/reask.ts` and `fn_reask_due` do not ask whether the turn was answered. Not observed on a real number: none may be messaged.
Root cause (verified by execution, `proof_reask_after_delivered_reply.mjs` against main's own module): `say.ts:151` settles the holding line through the REGISTERED wrapper when the reply is ready; that wrapper's `settle()` forgets the registration (`holding_notice.ts` `registerHolding`). `replies.ts` `sendWa` then calls `answeredHoldingFor`, finds nothing, and `answered` stays false, so `noSilenceAfterHolding` (index.ts:110) files the re-ask. Output: `answered:false, re_ask_filed_at_turn_end:true`; without the settle at adopt, `answered:true`.
Smallest fix: `settle()` on the registered wrapper must not forget (forget only in `answer()` and at the turn's end), or `noSilenceAfterHolding` reads the turn's own delivered reply. Add a test that runs the real order: fire, adopt, send, end. Each such re-ask also costs USD 0.01-0.15 untagged.

### R2 - BLOCKER (unchanged) - no ordinary reply is fast
Evidence and cuts: the latency section. p50 27.7 s against a 15 s target; 0 of 17 under 15 s. Complaints not measured.

### R3 - HIGH - "6" (Talk to a person) says it was passed on; nothing was
Script message 7, typed after the menu was no longer awaited, 24.8 s: "Your message has been passed to our team. ... For a member of the team to reply to you here, send MENU and choose "Talk to a person"." Read back: no `support.human_requested` hand-off, no `support_ceo_report`, `wa_conversation.thread_state` = open, `asked_for_a_person` = false, intent null. The person chose "Talk to a person" and is told to choose it again; the first sentence is false. Our own number is no longer given (audit F5 fixed). Fix: a bare menu digit after a recent menu is the menu's choice (file `fn_wa_human_request`); the reply may say "passed" only when the hand-off returned.

### R4 - HIGH - "not open yet" still contradicts the first reply, and now names the wrong trade
- Reply 2: "To request quotes, describe the job here ... Posting a request and comparing quotes is free", with two spec questions. Reply 3 gives a turnaround. Reply 4: "requests in this trade are not open yet. Register here..." Arabic the same in consecutive replies (A4 "يمكنكم تقديم طلب مجاني", A5 "لم نفتح الطلبات فيه بعد").
- Reply 6, to "How many quotes will I see for my windows?": "...For your cousin's cleaning company: Thank you. We are onboarding verified suppliers for Cleaning & facility services right now, so requests in this trade are not open yet. Register here and we will let you know the moment it opens". The cousin wants to register as a SUPPLIER. Reply 5 had said "Cleaning is one of our trades". The number was also put on the customer waiting list for cleaning (`customer_trade_waitlist` 32), so it would later be told "cleaning is open".
- The fixed paragraph begins "Thank you." and sits mid-reply (4, 6) or leads the reply (A5) before the answer.
Root cause (read): the "said once" mark is per trade (`inquiry_state.asked` held `said:trade_not_open:aluminium,glazing` and `said:trade_not_open:cleaning`), and a message about someone else's company set the number's trade.
Fix: the first job reply asks the trade door before inviting a request; one mark per conversation; a trade is set only by the person's own job; drop the leading "Thank you." from the database sentence.

### R5 - MEDIUM - "usually a handful, with the number capped" is now said twice
Replies 3 and 6. The audit (F11) recorded that the 24 Sep ruling says any number may quote and FAQ 13/43/67 say "capped". I did not re-read the ruling. The lane fix (a lane that "can't confirm" goes to the full path) now surfaces those FAQ rows. "3-5 working days is a realistic guide" is said for a trade that is not open. Fix: correct the FAQ rows.

### R6 - MEDIUM - the case summary slows as the case grows and hits its wall
`case_summary` at high effort: 6.5, 18.8, 15.7, 22.5, 28.0, 43.1 s over the six script summaries (output 523 to 4,835 tokens). 4 of 22 calls failed at the 47 s wall; message 6 lost its own version. It raised IT finding `support_case:summary_not_written` at 05:42:20Z. By the eighth exchange of one case the summary will not finish. Fix: cap the output, or medium effort.

### R7 - MEDIUM - still more than one case per matter
S: QD-S-AE4HNG, QD-S-3SRJT6, QD-S-PRJ8ND with overlapping titles ("Supplier registration, fees, and job inquiries" / "Supplier account, fees, and profile updates" / "Supplier charges, profile setup, and customer identity before quoting"). A: "عروض أسعار لصيانة مكيفات فيلا بالشارقة" and "طلب شركة لصيانة مكيفات فيلا بالشارقة" are one job. In the script both cases' titles name both matters. Every case read `waiting_on_us`, outbound 0, after we had answered; a fixture reply is not "sent", so I cannot say whether a real number shows the same.

### R8 - MEDIUM - the promise ledger records boilerplate, each due in 48 hours
7 rows, `due_basis` assumed: "I will answer it straight away." and its Arabic twin (the welcome menu, 2 of 2 new people); "we will let you know the moment it opens" twice; "I will send him the link." (conditional on a keyword that does not exist); "سنوضح لكم ما يحدث بعد ذلك"; "ننبهكم فور وصول كل عرض". On real people each comes due on day 2 and its seat is told. Fix: no promise from a fixed text; a conditional or event-bound sentence is not a dated promise.

### R9 - MEDIUM - cost per reply rose; one model class is 78% of it
USD 0.040 a model-written reply (audit 0.032; ledger 1405 expects about 0.006). `inquiry_qualification_conversation` on Sonnet 5.5: 22 calls, USD 0.5985. The supplier path costs about USD 0.009 a reply; the English customer script USD 0.034; the Arabic customer's first job turn USD 0.293 for two parallel calls that each wrote the same 34-36k token cache (ai_cost_log 103841, 103842). The discarded draft of cut 1 above is a Sonnet call on every customer turn.

### R10 - MEDIUM - while replies take 20-50 s, "once per 30 minutes" means most waits are silent
14 of 17 slow replies had no line, including the 53.5 s wait one minute after the line. This is the rule as built and is right once replies are fast; today the person sees one line, then silence on every later message.

### R11 - MEDIUM - a re-ask of a fixture turn runs outside the rehearsal tag and cap
16 untagged calls, USD 0.4126 (`evidence/ai_cost_log_untagged_reasks.json`): `sales_engineer` conversation_reply on Sonnet 5.5 at high effort, then a `reasoned_delivery` notice. Any capped harness run leaks this way whenever a fixture turn ends unanswered. Fix: carry the run tag on the held question, or do not re-ask a ZZ DEMO number outside its window.

### R12 - LOW - teardown still needs hand steps
- A fixture number with no account is not demo to `fn_support_case_is_demo` (promises carried `is_demo=false`), so the purge refuses its cases. I gave profiles 1128 and 1129 the reserved address `qd-9b9460cb-wa<tail>@example.invalid` (the same step the main session's own SQL took for profile 1034); the repo teardown then purged all 8 cases.
- The repo teardown does not reach: wa_turn, wa_conversation, wa_messages, wa_inbound_seen, wa_answer_log, customer_trade_waitlist, inquiry_state, support_ceo_report, holding rows, seat_case_memory, held questions and their agent_actions, the factory notices' `delivery.request` rows, the IT finding.

### R13 - LOW - smaller things
- The request reading that fills the state (`json_extraction`, high effort, off the reply path) failed 6 of 25 at its 27 s wall.
- "Reply REGISTER and I will send him the link." No such keyword exists (audit F11, unchanged).
- S4: "The portal guide doesn't specify a separate control for updating profile photos": internal wording.
- A2 calls QuotesDone a marketplace for "أعمال البناء والتشطيبات"; the welcome one message earlier said every trade except food and beverage.
- "ok good, thanks" took 19.8 s to answer "You're welcome."
- With no model, two photos sent together got the same held notice twice, one second apart.

## Against the audit's transcripts
- **Better:** "I can't confirm" is gone (audit: "I don't have a confirmed number of quotes"; now an answer, though see R5). The trade paragraph is in 2 of 7 script replies, not all. No reply prints +1 218 316 6814 (audit: 7 replies). Summaries exist. The holding line is recorded and not repeated.
- **Same:** speed (27.7 s against 30.2 s). First reply invites the request, a later one says not open. "Reply REGISTER". Supplier answers are as good as before and correct on the fee (free for the first 1,000, then AED 1,000 a year, no commission) and on identity ("No. Before you quote, you'll see the anonymised job details...").
- **Worse:** a second answer after the holding line (R1); "passed to our team" when nothing was (R3); the cleaning paragraph (R4); cost per reply (R9).

## Effort actually sent (ai_cost_log `model_selected_because`, tag 9b9460cb; 130 provider calls, 10 failed)

| step | task_class | model | effort sent | calls | p50 s | USD |
|---|---|---|---|---|---|---|
| the reading (intent + needs-a-person) and the after-reply same-matter decision | customer_communication | gpt-6-luna-pro | medium | 22 | 10.2 | 0.0216 |
| the same, supplier | supplier_communication | gpt-6-luna-pro | medium | 11 | 8.2 | 0.0097 |
| the reply | conversation_reply | gpt-6-luna-pro | medium | 24 | 9.2 | 0.0934 |
| status / app lane reply | status_reply | gpt-6-luna-pro | medium | 4 | 10.3 | 0.0044 |
| customer job reply and its discarded draft | inquiry_qualification_conversation | claude-sonnet-5.5 | medium 16, high 6 | 22 | 4.4 / 6.4 | 0.5985 |
| case summary (after the reply) | case_summary | gpt-6-luna-pro | high | 22 (4 failed) | 19.0 | 0.0243 |
| request reading into the state (off the reply path) | json_extraction | gpt-6-luna-pro | high | 25 (6 failed) | 15.5 | 0.0162 |
| re-ask (untagged) | conversation_reply | claude-sonnet-5.5 | high | 8 | - | 0.3907 |

## Spend
- Tag `9b9460cb`: **USD 0.7681** (157 rows: 130 provider calls, 27 refused by the cap at USD 0). Stage 1, the script: 0.2397. Stage 2, S and A: 0.5284. The no-model probes on K: 0.
- Untagged re-asks caused by this run: **USD 0.4126** (16 calls, ids 103760-103970 in the evidence file).
- **Total USD 1.1807 against a hard cap of USD 0.80.**

## Teardown
Window `qd_run:9b9460cb` closed 05:55:35Z, models_allowed false. Removed: wa_turn 25, wa_conversation 4, wa_messages 26, wa_inbound_seen 24, wa_answer_log 19, customer_trade_waitlist 4, inquiry_state 3, support_ceo_report 1, holding rows 3, seat_case_memory 8, held questions 9 with 8 agent_actions, 2 `delivery.request` rows; then the repo's factory teardown: **support_case through `fn_demo_support_case_purge` 8** (with their 17 summary versions and 7 promises), profiles 4, lead, customer, inquiry, quote, 2 auth users, 11 storage objects, refused `[]`.
Read back after (`evidence/leftovers_after_teardown.json`, 32 checks, re-read 06:10Z): **all 0**, including support cases, summary versions, promises, holding rows, storage objects and open windows. The audit's cases 2221, 2235, 2236, their versions and profiles 1034, 1036, 1037: 0. In all of production after teardown: 0 summary versions, 0 promises, 0 holding rows.
One thing I changed that is not a fixture row: IT finding `support_case:summary_not_written` (raised twice by this run, never alerted) was closed at 06:06:47Z through `fn_it_engineer_finding_close` with a note pointing here. It is closed as a fixture leftover, not as fixed (R6); reopen it if you disagree. I also lowered my own window's cap to 0.50 at 05:49Z so nothing further could be spent under the tag.
Kept as records: the ai_cost_log rows, the closed window.
My worktree `/tmp/claude-0/recheck-whatsapp` (detached at b2990006b, read-only use) is removed; the harness and the proof script need a checkout of b2990006b at that path to run again.

## Files
All under `/tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/recheck/whatsapp/`:
- `TRANSCRIPTS.md`: every message and reply
- `latency.md`: per-turn table, phase table, call timeline
- `out_1_script_C1.json`, `out_2_ordinary_S_A.json`, `out_3_two_photos_K_no_model.json`, `out_4_text_K_no_model.json`: raw records with timings
- `wa_recheck.mjs`, `spec1.json` to `spec4.json`, `analyse.mjs`, `proof_reask_after_delivered_reply.mjs`
- `evidence/`: wa_messages, tagged and untagged ai_cost_log rows, cases, summary versions, promises, notifications, held questions, inventory before teardown, leftovers after
- `teardown.log`, `capdown.mjs`, `stopheld.mjs`, `clean2.mjs`, `closefinding.mjs`
