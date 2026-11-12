# Final audit, 11 Nov 2026 — WHATSAPP workstream (seat: customer_support)

Run tag `71366940` (rehearsal window `qd_run:71366940`, opened 22:41:58Z, closed 23:08:03Z, cap USD 1.30).
What was driven: the DEPLOYED `wa_inbound` (version 436, deployed 11 Nov 12:59:54Z; no later commit touches a file it
imports), real models through `ai_gateway`, real database. 40 messages from 7 reserved fixture numbers
(+971 50 000 00 01/02/03/05/07/08/09): 33 Twilio-signed texts and 7 files through the authenticated internal path (the
only one that takes an inline file). 36 replies, all captured on `wa_messages`, none handed to Twilio. The first 6
messages were posted without the region pin (us-east-1); the other 34 with it (ap-southeast-1), as Twilio's are.
Driver and evidence: this folder (`wa_live.mjs`, `spec*.json`, `out_*.json` = every transcript with timings).

## VERDICT: GO WITH FIXES

Safe: in 36 replies nothing revealed a supplier or customer before reveal, no price was invented, the fee and
commission facts were right, Arabic was answered in Arabic, a trade licence was read and filed, a 5-turn memory held.
Not at the founder's bar: no reply was fast, the same holding sentence precedes every reply, and three things built
today (case summaries, the promise ledger from WhatsApp, the returning-person question) do not work on production.
F1 and F2 should be fixed before a senior supplier or customer is pointed at the WhatsApp number. Inviting by e-mail
does not depend on any of this.

## What was tested

| # | Test | Pass bar | Measured (production, region ap-southeast-1 unless said) | Result |
|---|---|---|---|---|
| 1 | Reply time, ordinary text turn | fast (founder) | n=19: p50 30.2 s, p95 51.2 s, min 15.7 s, max 51.2 s (`timings.reply_written`) | FAIL |
| 1 | Reply time, complaint | 30-40 s, holding first | 47.7 s, 49.5 s, 72.0 s (n=3) | FAIL |
| 1 | Reply time, "Hi" (welcome + menu) | fast | 16.6 s, 19.8 s (n=2, seen by poll, ±1.5 s) | FAIL |
| 1 | Reply time, file / voice turn | — | n=7: 13.7, 14.5, 15.5, 15.7, 24.2, 24.7, 43.7 s | slow |
| 1 | All 31 pinned replies | — | p50 29.0 s, p95 51.2 s, max 72.0 s; 0 under 9 s, 2 under 15 s, 6 over 40 s | FAIL |
| 1 | Supplier question / fee / commission | correct | approved, no fixed start date; first 1,000 free, then AED 1,000/yr; no commission | PASS |
| 1 | Supplier writes Arabic | English (ruling 1008) | English, correct fee | PASS |
| 1 | Memory (fact on turn 1, asked on turn 5) | recalled | "curtain walling in Fujairah, and your contact is Mr Zaid" | PASS (5 turns, not 10: budget) |
| 1 | "How many quotes do I see" (conversation lane) | per ruling of 24 Sep | "no guaranteed number … strongest three are levelled in a comparison report, and the others are listed too" | PASS |
| 1 | "Am I talking to a robot?" | honest, never "AI" | "I'm not a person. I'm QuotesDone's Smart Engine, an automated assistant" | PASS |
| 1 | Photo, licence PDF, bad PDF, stranger's drawing, customer's photo | right handling | photo "did not read as a trade licence"; licence read (no ZZ-DEMO-000123, expiry 2028-03-14); bad file refused; drawing described; photo attached to the open request | PASS |
| 2a | Holding line goes when the reply is slow | once, ~9 s, professional | fired on 29 of 29 text turns at 9.06-9.11 s after the last message (9.7-10.3 s unpinned), once per turn; 4 of 7 file turns | PASS (fires) |
| 2a | Holding line recorded and deduplicated | a `notifications` row each | 0 rows ever; 33 inserts refused by the database (Postgres log) | FAIL |
| 2a | Not sent on a fast reply | — | NOT SHOWN: no reply was faster than 9 s | NOT RUN |
| 2b | Burst of 3 messages = one reply | one reply | pinned: 1 reply, 2 merged (gaps 1.8 s); 2 messages 3.5 s apart: 1 reply. Unpinned (us-east-1): "Hi" answered on its own, then a second reply | PASS pinned / FAIL unpinned |
| 2b | The one reply answers all three | yes | windows + link answered; "how long / how many" answered "I can't confirm" | PARTIAL |
| 2c | Case opened with a number | yes | yes, on the first message (e.g. QD-S-DXPP44) | PASS |
| 2c | Summary written after each exchange | yes | 0 summaries from 29 text replies; `case_summary` model calls from WhatsApp: 0 | FAIL |
| 2c | Follow-up uses the summary | yes | never (no summary exists; the case read gives up after 4 s) | FAIL |
| 2c | Unrelated question opens a new case | yes | yes (QD-S-UZ6SW7); but also a new case for the SAME matter, and 8 cases for one supplier in 12 minutes | FAIL |
| 2c | Dropbox `<person>/cases/<case>.md` | exists or reason | no row queued (0 `doc_backups` with key CASE:%, measured after the direct summary call). Reasons: WhatsApp writes no summary; the SQL file's header says a ZZ DEMO person's row is dropped. Real-person path not proven | NOT PROVEN |
| 2d | Promise lands in the ledger | yes | from WhatsApp: 0 rows. Writer called directly on a fixture case: 2 rows (quotes "by Thursday" due 12 Nov 14:00Z stated; second due +48 h assumed) | FAIL on WhatsApp / writer PASS |
| 2e | Same reply never sent twice | yes | Twilio redelivery of a MessageSid: no second row, no second reply (PASS). The "trade not open yet" paragraph: in 7 replies to 4 people, word for word within a conversation (FAIL) | MIXED |
| 2e | Notification not repeated | trigger blocks | trigger `a00_notifications_the_same_message_is_sent_once` is live (read); not exercised (needs a write probe); 0 rows cancelled as duplicate since deploy | NOT RUN |
| 2f | Complaint escalated to high effort | recorded high | effort is recorded nowhere (no column). Inferred: the only 4 failed reply calls of 45 are the 2 complaint turns on the primary model, each hitting the 25 s call clock | NOT MEASURABLE |
| 2g | Voice note | heard, or honest | provider NOT set (`voice_transcription_provider` absent, no `hf_inference_token`). Reply in ~15 s, in the person's language: "we can't listen to voice notes on WhatsApp yet … Please type your message" | honest; product gap |
| 2h | Arabic and English | each in its language | Arabic customer answered in Gulf Arabic twice + Arabic voice reply; English in English | PASS |
| 2i | No identity before reveal, no invented price | none | 0 of 36 replies carry a counterpart's name, e-mail or number; only figure quoted is the AED 1,000 fee | PASS |
| — | Returning person after 7 quiet days gets "is this about … QD-…?" | asked | not asked; the old case was closed on arrival and a new one opened | FAIL |
| — | Auto-reply loop cap | stops at 3 | cannot be shown with fixture numbers (their replies are stored `sent=false`, the cap counts sent replies) | NOT RUN |
| — | Typing indicator | shown | fixtures are captured; needs one real message | NOT RUN |
| — | `scripts/e2e/wa_exchange_real.mjs` as written | — | not used: it runs the handler inside this container (a database round trip is ~0.8 s from here) and posts unpinned, so its times are not production's; the same turns were posted to the deployed function instead. Not run: old/lean parity (a module flag), the forged-signature control (it writes a founder alert), the bad-image control, turns 6-10 of the memory test, the 21st-message-per-hour limit | NOT RUN |

## Findings

### F1 — BLOCKER — no reply is fast; complaints take 48-72 s
Evidence: table above (31 pinned replies). Where the time goes on 22 pinned text turns: burst wait + identify p50 4.1 s;
classification p50 13.0 s (p95 31.5 s, max 38.1 s); writing the reply p50 10.7 s (p95 35.3 s). The last real WhatsApp
message before today's changes (wa_messages 2003, 10 Nov 23:25Z) was classified at 5.4 s and answered in 12.1 s.
Root causes (measured):
- the intent reading now runs at HIGH effort (`_shared/effort_policy.ts` SURFACES `wa_inbound.intent_table`): its call
  takes p50 12.0 s, p95 20.4 s (n=32, ai_cost_log, tag 71366940);
- every text waits 4 s for a possible burst (ruling; by design);
- the speculative draft was adopted on 0 of 26 turns, so the reply is always asked after the classification;
- a complaint's reply runs at high effort on the primary model and does not finish inside `PER_CALL_MS` 25 s
  (`_shared/ai_reply.ts:67`): ai_cost_log 102339/102340 and 102614/102615 failed at 26.6-27.1 s (`gateway_deadline`),
  then the other model family answered: 49.5 s and 72.0 s.
Smallest fix: run `scripts/eval/effort_low_vs_high.mjs` (prepared, never run) and take the intent reading back to medium
if it answers the same, keeping high only for the needs-a-person decision; give a high-effort reply a clock it can meet
(or send complaints straight to the family that answers in 8 s); find why no speculative draft is ever adopted.

### F2 — HIGH — the same holding sentence goes before every reply, and it is never recorded
Evidence: `timings.holding` set on 29 of 29 text turns; Postgres log 22:42-23:07Z: 33 × "notifications.requested_by
wa_inbound is not an active seat"; `notifications` rows of type `wa_holding_notice`: 0, ever. A person who writes
"ok good" gets "Thank you for your message. I'm reviewing it now and will reply here shortly." and, 7 s later,
"You're welcome." The same before "Hi", before "6", before every question.
Root cause (verified): `wa_inbound/holding.ts:45` writes `requested_by: 'wa_inbound'`; trigger
`a05_notifications_sender_of_record` refuses any requester that is not an active seat; the error is swallowed
(`.then(() => null, () => null)`). By reading, not measured (a fixture is never sent to): for a real number the line is
sent first and the record then fails, so the duplicate guard, which reads those rows, never finds an earlier one; and
with the requester fixed, trigger `a03` would rewrite the row of a known customer or supplier to `skipped`.
Smallest fix: `requested_by: 'customer_support'`, surface a failed insert as an it_engineer finding, pass the person
(lead or e-mail) or a role a03 does not judge. Decide the repeat rule with F1: once it records, the 10-minute guard
silences every later slow turn, and the person then waits ~30 s with nothing.

### F3 — HIGH — cases (ruling 1635) do not work on WhatsApp
Evidence: 17 cases for 7 people in 25 minutes (ids 2217-2233), none with a title or summary; one supplier got 8 cases in
12 minutes (a new one for "Which emirate did I tell you we work in?"); one customer got 3, the third for the same
windows matter; `support_case_summary_version` in all of production: 2 rows, both from this audit's direct call;
`support_case_promise` from WhatsApp: 0. No reply ever states a case number (0 of 36).
Root cause (verified): `wa_inbound/case_memory.ts:13,22-23` races the case read against 4,000 ms and memoises the
result from its FIRST caller. The same-matter decision is a model call: the 37 small decision calls of this run took min 4.77 s, p50 8.2 s (0 inside 4 s), and a case already exists when the first message is read (the arrival trigger opens it), so the
decision is always needed. The read loses, the turn gets null, the reply never has the case and
`recordWaExchange(null)` writes nothing; the routing still completes in the background (cases opened 0.5 s after that
call ended) and, with no summaries to read, it opens new cases. Status and app-lane turns skip the case entirely
(`say.ts:88`).
The writer itself works: called directly on a fixture case it wrote versions 1 and 2, a title, and two ledger rows.
Smallest fix: memoise the un-raced read; let the reply race it and let the record step await it; start it when the
turn starts; continue by code when the only open case was opened by this very message; record lane turns too.
Also: the returning-person question cannot fire. `fn_support_touch` closes a case idle past 7 days on arrival, before
the router reads the open cases. Measured: aged fixture case QD-S-S68HGF (an escalated refund complaint) was closed
"resolved — no further contact in 7 days", a rating request was generated (notification 140609, suppressed), a new case
opened, and the reply was "Hello, of course. What would you like to ask?". (The case was made 8 days old by a
fixture update; the closing rule is in the function's text.)

### F4 — HIGH — "this trade is not open yet" is repeated in every reply, after a first reply that says the opposite
Evidence: first reply (2 of 2 runs): "You can post your request … then send it to matched suppliers. Posting a request
is free." Next reply: "Thank you. We are onboarding verified suppliers for Aluminium & cladding, Glass & glazing right
now, so requests in this trade are not open yet. Register here and we will let you know the moment it opens". That
paragraph is then in every later reply: 7 replies to 4 people, including a question about a cousin's cleaning company,
a reply to "2", and an Arabic refund complaint.
Root cause (verified): `say.ts:85` adds the sentence to `must` on every non-lane turn while the number's state holds
that trade; the app-lane first reply does not ask whether the trade is open. The model leaves it out, so 7 of 26 turns
paid for a rewrite to put it back.
Smallest fix: carry it once per conversation (mark it said on `inquiry_state`); the app lane checks the trade before it
promises matched suppliers.

### F5 — MEDIUM — "Talk to a person" points at the number the person is already writing to
"6" (menu: Talk to a person) took 39.5 s and answered "You can speak with a person on WhatsApp … +1 218 316 6814". The
same number is given in 7 replies (both complaints, the Arabic one, "who is the customer"). Fix: on WhatsApp say it has
been passed on and give the e-mail; never print the number they are on.

### F6 — MEDIUM — a policy question inside a new-request or status message gets "I can't confirm"
"How long until I get the quotes and how many will I see?" → "I can't confirm how long quotes will take or how many
you'll receive" (2 of 2); "How many quotes will I see for my windows?" → "I don't have a confirmed number". The
conversation lane answers the same question correctly. The app and status lanes run without the company brief.
Fix: a message that also asks a policy question takes the conversation lane.

### F7 — MEDIUM — a burst splits when the function runs away from the database
Unpinned (us-east-1), messages 1.8 s apart: "Hi" was answered alone with the welcome menu, the other two together.
Cause: the arrival row is stamped at receipt but written 1.1-1.6 s later from there, and the leader reads at exactly
+4 s. Pinned it merged (2 of 2). The only evidence that Twilio's webhook is pinned is one real message (10 Nov 23:25Z,
region ap-southeast-1); I cannot read Twilio's configuration. Fix: the leader re-reads once after a short grace.

### F8 — MEDIUM — voice notes are not heard
No provider is set. The reply is honest and in the person's language, but it ends "I'll answer straight away", which the
channel does not do. Needs the Hugging Face token (founder-held) and the live check in `_shared/speech_to_text.ts`.

### F9 — MEDIUM — cost per reply
USD 1.16 for 36 replies (USD 0.032 each; ledger 1405 expects ~0.006). 29 customer-job calls on the larger model cost
USD 0.754 (65%): the first costs USD 0.058-0.15 (cache write), each later one ~0.015, and F4's rewrites multiply them.
Four turns of two complaints and two menu digits cost USD 0.40.

### F10 — MEDIUM — the effort a call ran at is recorded nowhere
`ai_cost_log` and `llm_attempt` have no effort column, so ruling 1630 cannot be audited per turn. Fix: log it.

### F11 — LOW — harness and teardown
- The repo teardown deletes `support_case` but not its append-only `support_case_summary_version` rows: it threw and
  stopped (this run). Once summaries work, every harness run will leak its fixtures.
- `seat_case_memory` keeps a row per deleted demo case: 270 orphans in production (oldest 6 Oct), after this run's own 17 were removed.
- `wa_exchange_real.mjs` cleanup leaves the stranger numbers' profiles and cases (numbers 94/95/97 held open cases from
  1-2 Nov), `wa_answer_log`, `customer_trade_waitlist`, `inquiry_state`, `support_ceo_report`; it uses
  `--node-modules-dir=auto` in a shared tree and measures latency from the container.
- 3 of 7 file turns (refused file, voice notes, 14.5-15.7 s) sent no holding line.
- FAQ 13/43/67 say suppliers are "capped … a handful"; the ruling of 24 Sep says any number may quote.
- Wording: "Reply REGISTER and I will send him the link" (no such keyword exists); "Your mobile number also still needs
  to be verified" to a customer writing from a confirmed WhatsApp number; the supplier's own quote amount was refused
  by the guard as an invented figure (one rewrite, ~20 s).

## Spend (ai_cost_log, e2e_run_tag 71366940)
USD 1.1605 (198 calls, 14 failed), under the USD 1.50 cap. By stage: A unpinned burst/case 0.2686; B pinned new
behaviours 0.2591; C standard exchange + 2 direct summary calls 0.1320; D files + returning person 0.1043; E complaints
+ menu 0.3964. Last call 23:07:29Z. Five untagged `wa_inbound` calls (USD 0.0097, 22:47-22:49Z) fell in the window while
no turn of mine was running; not this run's.

## Teardown
Window closed 23:08:03Z (0 open for this tag). Read back after teardown: leads 0, customers 0, auth users 0, inquiries 0,
quotes 0, wa_messages 0, wa_conversation 0, wa_inbound_seen 0, profiles by fixture phone 0, promises 0, notifications 0,
storage objects 0, trade waitlist 0, held questions 0. Removed beyond the factory teardown (37 rows + 11 objects):
wa_turn 32, wa_conversation 7, wa_messages 48, wa_inbound_seen 40, wa_answer_log 26, wa_document_intake 1, trade
waitlist 6, inquiry_state 6, support_ceo_report 5, support cases 16, profiles 7, file_scan 3, seat_case_memory 17,
agent_actions 4.
**Leftovers: 4 rows, not 0.** Fixture case QD-S-QHDQW6 (case_id 2221, closed, ZZ DEMO), its 2 rows in
`support_case_summary_version` (append-only: the trigger refuses every delete, ruling 1634) and the stand-alone ZZ DEMO
profile 1034 it was moved to so the customer could be removed. Removing them needs the main session (a delete that the
append-only trigger allows for a demo case). Kept as records: 198 ai_cost_log rows, the closed rehearsal window,
agent_runs log rows.
