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
  - **Not run:** this session has no gateway credential (the management token answered 401).

**Projected weekly cost:** about **+AED 4-6** on about AED 42, roughly +12%.
- **Estimated:** the multiplier from medium to high reasoning tokens. It was not measured.
- **Measured:** the output share of the internal answer (18%), of the plan (30%) and of Opus deliberation (63%).

**Projected latency (estimated):**
- Internal duties: +5-10 s each. They run in the background.
- A WhatsApp turn's reading: +3-8 s.
- A hard conversation turn: +5-15 s, which fits the 30-40 s the founder accepts.
- Intake decisions run inside a 30 s turn clock, so they are at risk of being held.

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
