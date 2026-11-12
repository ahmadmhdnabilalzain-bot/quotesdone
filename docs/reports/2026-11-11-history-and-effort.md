# History before every send, cases with summaries, and effort by consequence (it_engineer, 11 Nov 2026)

Assigned: `it_engineer`. The case model belongs to `customer_support`, which owns the case record.
Founder rulings covered:

- **1630**: effort by consequence.
- **1631**: read the history before every reply or send, economically.
- **1634**: keep everything.
- **1635**: every conversation is a case, with a summary after each exchange.
- **1636**: a holding message (hooks only, listed in section 5).

Branch: `it_engineer-history-and-effort`.

**What this pass did not do:** no deploy, no SQL applied, no merge, no message sent. Production was read with SELECT only.
"Measured" means read from production over the 30 days to 11 Nov 2026, excluding ZZ DEMO, example.invalid and synthetic
traffic. "Estimated" marks an assumption, and each one is named.

## 1. The audit

### Path by path

**Website widget (`site_assistant`)**
- **Reads history?** Yes. The whole conversation comes from `assistant_logs` by `conv_id`: `v-<uuid>` for a visitor,
  `a-c-<id>` for a signed-in person.
- **How much:** every turn. The history is cached as the third cache breakpoint. A signed-in person also gets 30 events
  from `fn_contact_timeline`.
- **Across channels?** Only when signed in, through the timeline. An anonymous visitor is not linked to anyone.
- **Cost per turn (measured):** `visitor_chat` on Sonnet averaged 44.8k tokens in, 39.4k of them cache reads, about
  AED 0.10 a turn.
- **Gaps:**
  - The timeline rides uncached with the facts.
  - The timeline does not include `assistant_logs` chats.
  - There was no case summary.
  - The 1,971 load-test rows of 11 Nov carry no `e2e_run_tag`, with user agent `node`. They had to be excluded by hand.

**Customer portal chat (`sales_engineer` assist)**
- **Reads history?** Yes. The whole account conversation (`a-c-<id>`) plus the customer's own quotes.
- **How much:** every turn.
- **Across channels?** No. It never reads the timeline, so WhatsApp and email are invisible to it.
- **Cost per turn (measured):** `customer_portal_assistant` on Luna Pro averaged 77.5k tokens in, 69.4k of them cached.
- **Gaps:**
  - It does not see the person's other channels.
  - **1 double send was answered twice** (`assistant_logs` 4875: the same message 1 s apart). **Fixed.**

**Supplier quote review (`supplier_api`)**
- **Reads history?** Yes. The thread view's conversation goes to aiReply.
- **How much:** the thread.
- **Across channels?** No timeline.
- **Cost per turn (measured):** `supplier_communication` on Luna Pro averaged 48.5k tokens in, 31.4k of them cached.
- **Gaps:** no case summary. Not wired in this branch; the seam is aiReply's `caseMemory`.

**WhatsApp (`wa_inbound`)**
- **Reads history?** Yes. `waConversation` reads up to 500 rows by number, plus `fn_contact_timeline` (40 events).
- **How much:** the whole conversation.
- **Across channels?** Yes, through the timeline: email, notifications, WhatsApp turns and portal messages.
- **Cost per turn (measured):** `conversation_reply` on Sonnet averaged 38.8k tokens in, 18.4k cached.
- **Measured in 30 days:** 37 turns from 25 numbers, at most 7 turns per number. 1 identical repeat reply, never sent.
  0 duplicate inbound messages.
- **Gaps:**
  - The timeline does not include widget or portal chats.
  - There was no case summary. **Now built (section 3).**

**Email (`email_triage`, `inbound_email`, `resend_inbound`)**
- **Reads history?** `email_triage` reads `fn_contact_timeline` (30 events). The other two read no thread.
- **How much:** event summaries of 140 characters each, not the mails themselves.
- **Across channels?** Through the timeline.
- **Cost per turn:** 1 to 2 calls a week (measured).
- **Gaps:**
  - No verbatim thread.
  - No case summary.
  - **Left alone on purpose:** the reply decision and the `supplier_mailbox_reply` gate belong to the
    customer_support branch `customer_support-supplier-mailbox-thinks-first`. This branch touches no email file.

**Intake (`inquiry_intake`)**
- **Reads history?** Yes. `loadTranscript` of the account.
- **How much:** the whole conversation, capped at 100 messages per inquiry.
- **Across channels?** No.
- **Cost per turn:** intake uses think() decisions.
- **Gaps:** two of its decisions ran at low effort, but they decide. **Fixed: now high.**

**Customer support case**
- **Reads history?** `support_case` (28 cases) links one person across channels through `support_customer_profile`.
- **How much:** before this branch, nothing: no summary existed.
- **Across channels?** Yes.
- **Gaps:** no summary, no same-matter decision. **Built.**

**`send_outbox` / `send_whatsapp`**
- **Reads history?** No.
- **How much:** nothing.
- **Across channels?** Not applicable.
- **Measured in 30 days:**
  - 731 notifications, **0 with a dedupe_key**.
  - **129 repeated an earlier row (same recipient, subject and body) within 10 minutes.** All of them were the seed list,
    queued twice 42 s apart on 10 Nov. 123 were cancelled by hand and **6 were sent twice**.
  - Outside that: 0 repeats, and 0 sign-in codes repeated within 2 minutes.
- **Gaps:** nothing compared a row with what had just been sent. **Fixed.**

**Seat duties that message people**
- They go through notifications, so the same guard covers them.

## 2. What was fixed (each fix has a test that fails without it)

**The same message to the same person is sent once.**
- Code: `_shared/outbox_duplicate_guard.ts`, used in `send_outbox` and `send_whatsapp`. The window is the setting
  `outbox_duplicate_window_min`, default 10 minutes.
- A repeat is cancelled with the earlier row named, and an it_engineer finding is raised. Nothing is deleted.
- Its insert-time twin is the a00 trigger (pending SQL). Its probe passed on a local Postgres stub and fails when the
  trigger is dropped.

**A message sent twice in a row is answered once.**
- Code: `_shared/turn_replay.ts` in the portal.
- No second model call is made.

## 3. The case model (ruling 1635)

The SQL and code below build on what already exists (`support_case`, `support_customer_profile`, `fn_support_touch`).

**The SQL** (`every_support_case_keeps_a_summary_and_the_reply_reads_it.sql`) adds:
- the summary, title, version and linked references on each case;
- `status_plain`, which reads the existing states as waiting on us, waiting on them or closed;
- `support_case_summary_version`, append-only;
- the writer, which refuses a stale version;
- `fn_support_open_cases` and `fn_support_case_route`;
- the `case_summary` class: Luna Pro at high effort;
- the Dropbox seam: a `doc_backups` row with `gen_kind case_summary`, written into the person's existing folder under
  `Cases/`. It is off until `pdf_native` can render it.

**The code** (`_shared/support_case_memory.ts`) does three things:
1. **Picks the case.** Code decides first: no open case means a new one, and a message that names a case number continues
   that case. Otherwise one lean decision at medium effort, given only the open cases.
2. **Gives the reply its case.** The reply gets the summary inside the cached system prompt, plus the last 6 turns
   verbatim.
3. **Updates the summary.** After the reply, one cheap call rewrites the summary. Code then drops any promise or date
   that our reply and the earlier summary never stated.

**Where it runs:** wired into WhatsApp (`wa_inbound/case_memory.ts`, `say.ts`). Until the SQL is applied, every step
returns null and the reply reads the whole chat, as before.

## 4. Effort (ruling 1630)

`_shared/effort_policy.ts` is the one map. The SQL file that mirrors it onto `model_policy.effort` is checked equal to it.

**The map:**
- **High:** 86 classes that decide, read documents, price, match or write for the company.
- **Medium:** 13 conversation classes and 2 sorting classes (`health_ping`, `intent_detection`).
- **Unknown classes:** high.

**Conversations:** medium by default. A turn is raised to high when any of these is true:
- the code rule matches a complaint, dispute, refund, price challenge or multi-part question;
- a draft failed the reply checks;
- a classifier flagged the turn.

**The six literal-low call sites:**
- **Now high:** the WhatsApp reading (it also decides whether a person is needed), the intake trade and the spec reader.
- **Now medium:** the menu and the status lane.
- **None is low** until `scripts/eval/effort_low_vs_high.mjs` passes.
  - Expected cost: about **USD 0.13** for 96 calls.
  - **Not run in this pass:** this session had no gateway credential (the management token answered 401).
  - **Run later the same day by the final audit: section 6.** No surface passed, so none is low.

**Projected weekly cost:** about **+AED 4-6** on about AED 42, roughly +12%.
- **Estimated:** the multiplier from medium to high reasoning tokens. It was not measured.
- **Measured:** the output share of the internal answer (18%), of the plan (30%) and of Opus deliberation (63%).

**Projected latency (estimated):**
- Internal duties: +5-10 s each. They run in the background.
- A WhatsApp turn's reading: +3-8 s.
- A hard conversation turn: +5-15 s, which fits the 30-40 s the founder accepts.
- Intake decisions run inside a 30 s turn clock, so they are at risk of being held.
  **Measured in section 6: they are held.** At high the two intake readings do not finish inside the turn.

**Per-turn history cost:**
- Today conversations are short (at most 7 turns), and the history is mostly cache reads.
- With a case, a long chat sends the summary (about 300 tokens) plus 6 turns instead of the whole transcript.
- The summary step adds about AED 0.002 per exchange. The decision adds about AED 0.004 per turn, and only when the
  person has an open case.

## 5. Holding message (ruling 1636): where the hook goes

| Channel | File | Where |
|---|---|---|
| WhatsApp | `wa_inbound/say.ts` | before `await modelSays(...)`: a timer on `budgetLeft(receivedAt)` that calls `sendWa` |
| Portal | `sales_engineer/actions/portal.ts` | before `answerFromBrief`; `EMITTERS` already streams |
| Widget | `site_assistant/index.ts` | before `answerFromBrief`; or in `brief_answer.ts`, on the first byte |
| Intake | `inquiry_intake/turn_clock.ts` | the turn's clock |
| Email | none | asynchronous; not applicable |

## 6. The side-by-side, run (it_engineer, final audit, 11 Nov 2026)

Section 4 left the low-against-high test prepared and not run. The final audit built its paid replay,
`scripts/eval/effort_low_vs_high/replay.ts`, and ran it the same evening. Every number in this section was measured on
11 Nov 2026 between 22:47 and 23:43 UTC. The run files are in `docs/reports/effort-low-vs-high-2026-11-11/`.

### What ran

- **The real routines, once per arm, on the same input:** `whatsappReadings`, `menuMeaning`, `needsAPerson`, `tradeOf`,
  `statedSpecs` and the status lane's `modelSays`. Every call went through the production gateway to GPT-6 Luna Pro.
- **The arms:** low and high. A surface that runs at medium today (the menu, the status lane) also ran medium on its
  first 8 cases. The order of the arms rotated by case.
- **Nothing was sent to a person and nothing was written to production state.** The routines' own writes were answered by
  a stub: 167 judgement rows across the runs. No fixture was created, so there was nothing to tear down.
- **What was written:** 6 rehearsal windows (all closed) and the cost rows of the calls.

**Spend: USD 0.2201 in all** (cap USD 0.50), from `ai_cost_log`:

| Run | What | Calls' cost rows | USD |
|---|---|---:|---:|
| `qd_run:evalefffe3428a49` | the six surfaces | 147 | 0.1307 |
| `qd_run:evalefff2f6e4c90` | the spec reader again, with a medium arm | 28 | 0.0452 |
| `qd_run:evaleff0db35eb5c` | the trade choice again, 4 conversations, with a medium arm | 15 | 0.0190 |
| `qd_run:evaleff8f08ecc31` | one menu message asked five times per arm | 15 | 0.0138 |
| `qd_run:evaleff86c475004` | a smoke run, one status case | 3 | 0.0017 |
| no tag (the harness's fault, below) | the first smoke run | 5 | 0.0097 |

**The first smoke run went out untagged.** The replay imported `_shared/e2e_run.ts` before `SUPABASE_URL` was set, so the
forwarder that carries the run tag was never installed. Five calls reached the gateway as ordinary `wa_inbound` traffic
(`ai_cost_log` 102237, 102244, 102255, 102265, 102277) and the spend guard read USD 0. Fixed before any further call:
the functions tree is imported after the connection, the forwarder is asserted before the window opens, and a paid call
that leaves no tagged cost row stops the run. Those five rows still carry no tag.

### The inputs

- **WhatsApp, the two readings that decide:** the 8 messages of the last 30 days from numbers that are not fixtures. They
  come from 2 numbers: one supplier's registration thread and one "STOP". Each rode with the turns its sender had
  already exchanged.
- **WhatsApp, the menu:** 8 messages cannot exercise a menu, so the menu read every distinct message on record: 26 texts
  from 4 numbers over 120 days.
- **Intake:** the 8 newest recorded portal conversations with distinct openings. They are our own scripted test customers
  of 27 Oct. No real customer has used the portal yet.
- **Status lane:** no status question from a real number is on record. Eval A's fixed ZZ DEMO turns were used: 8 of them.
- **Not replayed, because no recorded input exists:**
  - `wa_inbound.problem_state`: no typed message from a real number has followed "Report a problem".
  - `support.case_match`: 0 of 28 cases held a summary when the cases were sampled. The case model went live that day.

**Anonymisation was read by the auditor before any paid call, and two defects were fixed first:**
- The script replaced the two words after any "I am". "I am not sure, what do you recommend?" became
  "I am ZZ DEMO Person, what do you recommend?". That is 8 of the 83 recorded portal messages.
- The script knew no company name. 5 of the 8 WhatsApp messages, and our own replies in that thread, named a real
  supplier's two companies. Names with a legal form are now replaced by rule, the operator passes the names no rule can
  know, and a cases file that still carries one is refused.

### Results

Times are what the caller waited for the model, per case, p50 / p95, in seconds, measured by the replay's own client.
The gateway's own latency is 0.7 to 2.0 s lower. "Over the clock" counts the calls production would have cut: 20 s for a
WhatsApp classification, 21.5 s for an intake reading, 25 s for a reply call.

| Surface | Consequence | Cases | Low chose as high | Low | Medium | High | High calls over the clock |
|---|---|---:|---:|---:|---:|---:|---:|
| `wa_inbound.greeting_state` (the menu) | sorting | 26 | 23 | 10.3 / 18.5 | 13.0 / 19.3 (8 cases) | 14.6 / 29.4 | 8 |
| `wa_inbound.intent_table` (the reading) | decides | 8 | 7 | 5.3 / 9.5 | not run | 11.9 / 27.3 | 1 |
| `wa_inbound.needs_a_person` | decides | 8 | 8 | 6.7 / 11.6 | not run | 18.5 / 27.3 | 4 |
| `inquiry_intake.trade` | decides | 8 | 3 | 13.2 / 15.4 | 31.9 / 37.2 (4 cases) | 48.0 / 48.9 | 8 |
| `inquiry_intake.exact_spec` | decides | 7 | 1 | 17.9 / 18.9 | 37.9 / 48.5 | 48.0 / 49.0 | 7 |
| `wa_inbound.status_lane` | conversation | 8 | 8 | 4.7 / 5.5 | 7.4 / 10.7 | 8.2 / 11.7 | 0 |

Which file each row is from:
- The spec reader's row is its own run with the medium arm (`intake_spec_reader_low_medium_high.json`). The eighth
  conversation chose a trade with no required spec, so there was nothing to read there. In the six-surface run the reader
  ran only on the 3 conversations whose trade the high arm had answered: low chose as high on 0 of 3.
- The trade choice's medium column is `intake_trade_low_medium_high.json`. In that run high answered 1 of 4.
- Every other figure is `effort_low_vs_high.json`.

USD per case, low / medium / high:

| Surface | Low | Medium | High |
|---|---:|---:|---:|
| the menu | 0.00060 | 0.00104 | 0.00117 |
| the reading | 0.00108 | not run | 0.00112 |
| needs a person | 0.00071 | not run | 0.00127 |
| the trade choice | 0.00119 | 0.00242 | 0.00271 when it answered |
| the spec reader | 0.00199 | 0.00387 when it answered | 0.00336, the one time it answered |
| the status lane | 0.00036 | 0.00053 | 0.00061 |

What the table hides:
- **The menu.** High read a menu option in 5 of the 26 messages. Low agreed on 2 of those 5 and called the other 3
  "other". Low agreed on all 19 that high called "other" and on both greetings.
- **One message, asked five more times.** "Supplier" on its own was one of the three misses. Asked five more times, low
  chose the supplier option 1 time in 5 and high 1 time in 5. The first run had low 0 and high 1. Each arm disagrees with
  itself on that message, so one run per arm cannot separate effort from chance there.
- **The reading.** The one miss: "the licence is issued by a free zone", mid-thread. High read it as registration, as
  production had. Low read it as nothing.
- **The trade choice.** At high, 5 of 8 calls were cut at the gateway's own 47 s wall with nothing written. The 3 that
  answered took 32.8, 38.5 and 45.8 s and chose as low did. Low answered all 8 in 10.9 to 15.4 s.
- **Low against itself.** The same wardrobe conversation was run twice at low. It chose `custom-furniture` once and
  `carpentry-joinery` once.
- **The spec reader.** At high, 6 of 7 calls were cut at the 47 s wall. At medium, 6 of 7 answered, in 32.9 to 46.3 s.
  Low answered all 7 in 16.0 to 18.9 s. Low proved 5 fields across the 7 conversations, medium 2, high none. Every proven
  field passed the evidence guard: the value is inside the customer's own words.
- **The status lane.** All 24 replies went out on the first draft, carried every reference and stated no figure the facts
  do not state. The auditor read the 8 triples: the same facts in each.

### Verdict per surface: nothing is marked proven low

| Surface | Verdict | Why |
|---|---|---|
| `wa_inbound.greeting_state` | **stays medium** | 23 of 26 is 88%; the bar is 95%. The three misses are the menu picks. |
| `wa_inbound.problem_state` | **stays medium** | Not run: no recorded input exists. |
| `support.case_match` | **stays medium** | Not run: no recorded input existed when the cases were sampled. |
| `wa_inbound.intent_table` | **stays high** | It decides. Low also missed 1 of 8. |
| `wa_inbound.needs_a_person` | **stays high** | It decides, whatever the 8 of 8. |
| `marketing_social.needs_a_person` | **stays high** | It decides. Not run: it shares the options above. |
| `inquiry_intake.trade` | **see the finding below** | It decides, and at high it does not finish inside the turn. |
| `inquiry_intake.exact_spec` | **see the finding below** | It decides, and at high it does not finish inside the turn. |
| `wa_inbound.status_lane` | **stays medium** | It is a conversation. The map does not read `provenLow` for one. |

`_shared/effort_policy.ts` is unchanged by this pass. There is no `provenLow` line to flip.

**Lowering the menu would change nothing today.** `menuMeaning` is not called on its own in production. The menu reading
rides inside the one WhatsApp readings call. `seat_judgement` holds 0 rows for `wa_inbound.greeting_state` and
`wa_inbound.problem_state`, in the 7 days before the map went live and since.

### Finding: at high, the intake's two readings do not finish inside the turn

An intake turn has 24 s, and a reading inside it must end 2.5 s before that (`inquiry_intake/turn_clock.ts`). A reading
that is cut fills nothing. The spec it would have read is asked of the customer again.

**In the replay:** not one high call of either reading finished inside 21.5 s. Low finished every time.

**In production, since the map went live** (the traffic is the audit's own fixture customers; no real customer yet):

| What | 7 days before | Since 11 Nov 11:10 UTC |
|---|---:|---:|
| Spec readings (`seat_judgement`) | 55 | 18 |
| ... of which held, nothing read | 4 | 10 |
| ... time of the ones that answered, p50 / p95 | 11.0 / 16.3 s | 16.7 / 22.0 s |
| Spec-reader calls (`ai_cost_log`) | 59 | 28 |
| ... of which failed | 8 | 20 |
| Intake turns with a recorded time | 82 | 20 |
| ... turn time, p50 / p95 / max | 11.0 / 25.8 / 29.1 s | 17.1 / 28.5 / 29.1 s |
| ... turns over the 24 s budget | 7 | 5 |
| ... turns over the portal's 30 s wait | 0 | 0 |

The clock held: no turn passed the portal's 30 s wait. The price is that most readings are now cut, and the median
turn is 6 s slower.

**The trade choice** runs only when the interview call fails. It did not run in production in either period.

**Medium does not fit either:** 29.3 to 46.3 s across the 10 medium calls of the two readings that answered.

What would fix it is not decided here, because both honest options touch ruling 1630:
- run these two readings at low while they are on the turn's clock, as before 11 Nov. That puts two calls that decide
  below high;
- or keep them at high and take them off the turn's clock, so the reply goes first and the reading lands after.

### What ruling 1630 costs in production

From `ai_cost_log`: provider calls only, the 7 days before #1938 merged against the time since its deploy finished
(11 Nov 11:10 UTC to 23:43 UTC, 12.5 hours). The eval harnesses' own rows are left out. Most of the traffic in both
periods is tagged test traffic through the real functions. Classes with fewer than 20 calls since are not shown.

| Class | Effort now | Calls before / since | p50 before / since | p95 before / since | USD per call before / since |
|---|---|---:|---:|---:|---:|
| `supplier_trade_choice` | high | 231 / 34 | 10.3 / 15.9 s | 24.7 / 41.7 s | 0.00097 / 0.00215 |
| `json_extraction` | high | 87 / 29 | 7.6 / 6.1 s | 12.8 / 26.7 s | 0.00024 / 0.00051 |
| `sales_engineer__document_extraction` | high | 83 / 21 | 8.9 / 8.4 s | 17.6 / 24.6 s | 0.00093 / 0.00082 |
| `customer_communication` | medium | 289 / 67 | 12.2 / 14.7 s | 22.5 / 25.7 s | 0.00174 / 0.00124 |
| `conversation_reply` | medium | 362 / 55 | 8.8 / 9.5 s | 17.4 / 22.1 s | 0.01472 / 0.00503 |
| `inquiry_qualification_conversation` | medium | 124 / 49 | 7.6 / 6.8 s | 10.5 / 10.9 s | 0.03028 / 0.03227 |
| `supplier_communication` | medium | 210 / 44 | 18.7 / 11.3 s | 34.6 / 29.7 s | 0.00193 / 0.00147 |

- **The supplier's document reading (`supplier_trade_choice`) moved most.** 3 of 34 calls ran over 40 s, the longest
  60.0 s. Before, 1 of 231 did. It writes 2,031 tokens a call where it wrote 834. It runs behind the portal, not inside a
  request.
- **The cost per call fell on three conversation classes.** That is not an effect of effort: the two periods are not the
  same traffic, and two of these classes ran on two models. The replay above is the like-for-like measure.
- **The WhatsApp reading in production:** 125 decisions before, p50 10.2 s and p95 13.9 s, 16 held. 29 since, p50 11.8 s
  and p95 19.1 s, the longest 22.1 s, 2 held.

**Is any customer-facing turn slower than the 30 to 40 s the founder accepts?**
- **WhatsApp turns:** 10 since, p50 15.0 s, p95 33.7 s. One took 42.1 s. On 10 Nov, 19 turns ran p50 25.9 s and the
  longest took 46.4 s.
- **Intake turns:** none over 30 s, the longest 29.1 s (table above).
- **`sales_engineer` requests, the portal chat among them:** 74 since, the longest 19.8 s.
- **Calls on the conversation classes:** 4 of 227 since took over 30 s, the longest 34.9 s. None took over 40 s.

### Not measured

- **The website widget:** no turn since the map went live.
- **A real customer or supplier:** every turn since the map went live is the audit's own fixture traffic.
- **The internal duties:** 4 `internal_judgement` and 7 `routine_employee_reasoning` calls since. Too few to compare.
- **Whether a low status answer reads as well as a high one to a customer.** Code checked the references and figures and
  the auditor read the 8. No judge model scored them.
- **The weekly cost of the map.** 12.5 hours of test traffic is not a week of production.

## 7. Effort fits the wait (it_engineer, fix round, 12 Nov 2026; founder ledger 1642)

The ruling, amending 1630: a step a person is waiting on uses the highest effort that finishes inside that wait, measured;
thinking that needs longer moves off the live reply, or its wait is lengthened where the person is shown progress.
Background work stays high with a limit that fits it. A surface put below high for its clock is recorded as such
(`effort_policy.ts` `SURFACES[...].clock`), never as "proven low": `provenLow` is false everywhere.

### The extra measurement

Run `qd_run:evaleff1292fbdc2` (replay.ts, 8 recorded WhatsApp messages, arms low, medium and high), USD 0.0581. Window
closed. Seconds, p50 / p95 (max):

| Surface | Low | Medium | High | Same choice as high |
|---|---:|---:|---:|---|
| `wa_inbound.intent_table` | 5.8 / 13.8 | 9.1 / 16.5 (16.5) | 10.2 / 30.4, 3 of 8 over 20 s | low 7 of 8, medium 8 of 8 |
| `wa_inbound.needs_a_person` | 7.9 / 10.3 | 14.0 / 18.0 (18.0) | 16.6 / 24.6, 2 of 8 over 20 s | 8 of 8 each |

### What each clock now asks

| Surface or call | The wait | Effort | Why (measured) |
|---|---|---|---|
| intake spec reader | 21.5 s of the chat turn | low | low 7 of 7 inside (16.0-18.9 s); medium 32.9-46.3 s; high 0 of 22 |
| intake trade choice | 21.5 s of the chat turn | low | low 12 of 12, p95 15.4 s; medium p95 37.2 s; high 4 of 12 answered |
| WhatsApp reading | 20 s (`CLASSIFY_MS`, unchanged) | medium | the table above |
| WhatsApp needs-a-person check | 20 s | medium | the table above |
| customer comparison | 150 s with a "still working" line | high, unchanged | 42-74 s; it waited 30 s |
| supplier check before sending | 90 s with a "still checking" line | high, unchanged | up to 66.6 s; it waited 20 s |
| drawing read | what is left of a 115 s read budget less 10 s for the code reading; customer_api answers inside 140 s; the portal waits 150 s | high, unchanged | 1 of 9 answered (46.9 s), 8 cut at the 55 s wall |
| background think() calls | 100 s each, inside a 130 s run (`INTERNAL_RUN_DEADLINE_MS`); marketing's beat 130 s | high, unchanged | answers p95 83.5 s, reviewer p50 54.9 s, p95 142.1 s |
| intake held reply | 15 s, never past the turn's 25 s end | low | medium 0 of 8 inside 15 s, low 8 of 8 (p95 14.5 s) |
| intake voice | 15 s, never past the turn's 25 s end | low | low p95 6.6 s, medium up to 15.7 s |
| supplier document reading | 112 s wall (115 s declared) | high, unchanged | max 60.0 s: margin, no change |

### Also fixed
- A spec the request's state recorded on an earlier turn is no longer asked again when the model's brief leaves it out or
  the reader is cut (`inquiry_intake/handle.ts`, ruling 1631).
- The drawing's code reading reached the customer as 0 lines: its summary (the customer's own note) shared words with the
  title strip and the identity gate held the whole take-off. The summary is now removed whole, as `cross_check.ts` does.
- The effort sent to the provider is on every `ai_cost_log` row: `model_selected_because` ends `| effort sent: <value>`.

### Not measured
- High's drawing read past 55 s: no call ran longer. Every read now records `boq.model_read` (finished / cut_at_budget / failed) for the paid journey to read.
- The WhatsApp reply end to end after this change, and a high complaint reply against its 25 s call clock (owned by the
  WhatsApp fix group).

### Review round (12 Nov 2026)

Run `qd_run:evalheldb26f2d3d` (`scripts/eval/effort_low_vs_high/held_reply.ts`): the held reply and the voice on 8 recorded portal
conversations, each with the 15 s deadline the turn gives it. USD 0.0493. A first run with no deadline
(`qd_run:evalhelde28857d4`, USD 0.1089) let a high held reply run to the 47 s wall and its Sonnet fallback cost USD 0.096; it
was stopped and its window closed by hand.

| Step | Low | Medium |
|---|---|---|
| held reply (model call) | 8 of 8 answered, p50 11.5 s, p95 14.5 s | 0 of 8 inside 15 s |
| voice (model call) | 8 of 8, p50 3.4 s, p95 6.6 s | 5.4-15.7 s |

The turn, as it runs (agent_runs inquiry_intake, 10-12 Nov): the reads (about 0.1 s, side by side); the interview call
(p50 8.4 s, p95 11.4 s, max 16.4 s), with the spec reading started beside it; the trade reasoning only when no trade is
held; then ONE of the held reply or the voice, and rarely a guard rewrite; the ready reads side by side; the save (under
0.1 s). The reply steps depend on what the interview call settled, so they cannot start beside it: a held reply started
earlier could ask what this very message answered (ruling 1631). Every model step now ends by `turn_clock.ts` REPLY_END_MS
(25 s from the request; a cut call returns about 2 s later): the response leaves by about 27 s whatever ran. Typical, expected: the interview call
alone (about half the turns, 8-10 s), the interview and the voice at low (about 12 s), a held turn about 20 s.
