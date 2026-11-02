# Is the sales agent qualified and running? Supplier journey audit, auditor C (28 Oct 2026)

**Asked:** founder ledger 1401, verbatim: *"audit the supplier journey from the moment they receive an email up to being
verified by the sales the agent. try 5 different scenarios at least, confirm that the sales agent is qualified and
running perfectly."* and *"the audit should cover journeys done through code and through the browser"*. Auditors A
(browser) and B (code) ran the journey scenarios. This part answers: **is the `sales_engineer` seat qualified, and is it
running?**

**Assigned: `it_engineer`** (auditor), auditing **`sales_engineer`**. The live seats on 28 Oct are `accountant`, `ceo`,
`customer_support`, `it_engineer`, `marketing` and `sales_engineer` (`org_role`, status active). The reply path
(`email_triage`) is `customer_support`'s pipe, carrying `sales_engineer`'s supplier facts.

**Measured** on production `htdblwldjkcgjvmqkbeh`, 28 Oct 2026, 07:27Z to 08:45Z (11:27 to 12:45 Dubai), read-only
except:
- nine conversation probes, which were reverted by clean-up;
- three rolled-back proofs.

The invitations went live at 07:01Z (Google only), so the "last 7 days" windows are almost entirely pre-launch.

**Boundaries.** Measured:
- the routines, schedules, queues, logs, `ai_cost_log`, the knowledge texts and the signed legal texts in `src/content/legal.json`;
- 8 + 1 replies sent through the real e-mail reply path;
- one rolled-back decision table of the verification routine.

Not measured:
- WhatsApp: there are 0 supplier opt-ins, so nothing can reach a supplier there;
- the browser journey (auditor A) and the scripted registration journeys (auditor B);
- any real supplier conversation: none exists yet, and 0 `invite.reply` handoffs have ever been filed.

## Verdict

| | verdict | in one line |
|---|---|---|
| **Qualified** | **NO** | Its facts and judgement have gaps a real supplier would meet. Before today's fixes, 5 of 8 answers omitted two of the six mandatory items and 5 of 8 promised a set-up nobody performs. One answer told a supplier the licence is the only mandatory document. One draft believed a supplier's "we are already registered" over the facts. Verification approves a licence whose issuing authority is foreign or was never read, contrary to Supplier Agreement v16 clause 13. The learning loop is not closing. |
| **Running** | **NO** | The seat's 26 duties and the journey routines are on their clocks and fail nothing. But "ok" is mostly a no-op before launch, and the journey has parts with **no actor**: `invite.reply` only waits, `doc_trades_held` and `vision_trades_confirm` have no consumer, and held registrations end at a CEO report nobody decides. The nudge list would re-ask suppliers who already answered (fixed in #1713, pending). Answers took 82 to 195 s against the founder's "under a minute", and 1 of 9 was lost mid-answer. |

What changed during the audit:
- **#1714** (auditor A; my **#1716** was closed as its duplicate) made the triage classify each mail on its own.
- **#1715** (mine) made every answer name the six mandatory items and stop offering a set-up.
- Both are **live and verified** by a re-run of the "yes" case. See case c9 in `CONVERSATION_ANSWERS_28_OCT.md`.
- **#1713** (the nudge re-ask) is open, pending apply at merge, and must land before **Mon 2 Nov, 09:00 Dubai**.

## Per-area results

| # | area | result | evidence (sections below) |
|---|---|---|---|
| 1 | Running | **FAIL** | Every routine has a caller and a clock, but there are queues with no actor (`invite.reply`, `doc_trades_held`, `vision_trades_confirm`, `spec.not_sure`, `held_question` 327). The nudge list would re-ask answered suppliers. 0 real rows were acted on in 7 days apart from today's 20 invitations. |
| 2 | Errors and capacity | **FAIL** | `license_extract` failed 38 of 99 runs (#1707 fixes it). `supplier_api` has 94.18% 30-day availability (IT SLO). `ai_gateway` hit 76 CPU-time kills in 24 h. 179 statement timeouts in 24 h on the invitation candidates (stopped after #1705). One reply lost to a worker retirement. |
| 3 | Qualified: facts | **FAIL** (partly fixed by #1715, live) | Two of the six items were missing from answers; a set-up was promised that nobody performs; "the only mandatory document is the trade licence". The brief says "No supplier is approved automatically" while the signed agreement discloses automated approval and production auto-approves. `invite_preheader` still holds banned offer wording (dormant). |
| 4 | Qualified: judgement | **FAIL** | Rolled-back decision table: the seat approves a licence with a non-UAE or unread issuing authority. Expired and unread licence fields are handled correctly. 0 real decisions exist. The escalation path has never been used. The self-review is stale, accuracy has been flat at 41.3% and 0 lessons were approved. |
| 5 | Conversation quality | **FAIL** (1 of 8 before the fixes; the re-run passes) | Grading table below; full answers in `CONVERSATION_ANSWERS_28_OCT.md`. |
| 6 | SLAs | **FAIL** | Reply to answer: 82 to 195 s, 0 of 9 under the founder's minute, 1 lost. Verification "within 3 working days" (SA cl. 13) is met at once for a complete, readable registration. A held one has no decider after the 24-hour CEO report. |

## Findings, ranked

### High

**H1. A supplier who answered the invitation would be asked the same question again.** Fixed in **#1713**, which is open and pending apply.
- `fn_supplier_invite_nudges_due` (the day-3, day-7 and day-14 list) excludes clicked, claimed, registered, bounced, unsubscribed and suppressed leads, but **not a lead that replied**.
- A reply changes nothing on the lead.
- `send_outbox` sends every nudge as the **same** variant A e-mail (`campaignMail` rewrites the stored body), with the trade from `invite_trades` in the subject.
- So the "steel, not tiles" supplier in case c4, told "We will not send you tiling requests", would get "A question about your tiling work" on day 3.
- Proved with a rolled-back replay: `PROBE FAILED` on the live definition, `PROBE OK` with the fix; the real nudge list was unchanged (0 before, 0 after).
- Prevented by `scripts/checks/a_supplier_who_answered_the_invitation_is_not_asked_the_same_question_again.test.mjs`.
- Related, merged today by another auditor: **#1717**, under which a "stop" now also stops a nudge already queued at the outbox. It redefines `fn_opt_out_types()`, not the nudge list, so it does not conflict with #1713.

**H2. The offer "reply with your trades and our team will set up your page" has no actor.**
- The offer was founder-approved in the old invitation copy (ledger 1298). The WhatsApp draft keeps it (`marketing_send_gate.ts`), and `email_triage`'s facts repeated it.
- `invite.reply` is answered by `fn_sales_engineer_takes_invite_reply`, which is STABLE and only returns `{"waiting": …}`.
- `fn_seat_handoff_act` then stamps `replied_at`, so the handoff counts as answered and no SLA watcher can see it.
- Nothing else reads `invite.reply`: `fn_marketing_files_invite_reply` and `fn_marketing_files_wa_invite_reply` only file it.
- 0 `invite.reply` handoffs have ever been filed, so no supplier has been failed yet.
- **#1715 (live)** removed the promise from e-mail answers.
- **Still open:**
  - the handler itself;
  - the WhatsApp draft's offer, which must not go live until something acts;
  - since #1713, a replied lead that does not register gets neither a nudge nor a reminder. `fn_supplier_registration_reminders_due` has no "replied" stage.
- Recommended:
  - a `replied` reminder stage carrying the claim link;
  - either a real set-up step in the `sales_engineer` function, which runs the existing `services_rewrite` over the reply text into `supplier_capabilities.proposed_trades` and is shown pre-filled on claim, or withdrawing the offer everywhere.

**H3. Verification approves a licence whose issuing authority is foreign or unread.** This is contrary to Supplier Agreement v16 clause 13 ("valid UAE trade licence … the trade licence number, **issuing authority** and expiry date are checked").
- Rolled-back decision table (`verification_decision_table_28_oct.json`):
  - S7: *Ministry of Commerce, Kingdom of Saudi Arabia* was **approved**, and the approval notice was queued;
  - S8: an authority never read was **approved**.
- `fn_sales_engineer_verifies_supplier` never reads `leads.license_authority`, although the value is read and stored for 5 of the 6 licences on file.
- Answers c5 and c8 told suppliers "We check the licence number, issuing authority and expiry date".
- **Not fixed here, on purpose.** Holding on the authority would send real suppliers into the held path, and that path has no decider (H5). A wrong approval would become a stuck registration during the first campaign days.
- Recommended, in one change:
  - an unread authority → `pending` / `licence_authority_unread` (needs review);
  - an authority outside the UAE list (DET/DED per emirate and the free zones) → `action_required`;
  - **and** a decider for held registrations.
- Customers are told suppliers are licence-verified, so this belongs with the CEO and the founder's T&C.

**H4. The inbox triage was classifying every mail from a semantic cache.** Fixed by **#1714** (auditor A), live and verified.
- All 9 `email_triage` classifications in 14 days were `semantic cache hit`s; `intent_detection` has a 1,440-minute TTL.
- The gateway's semantic key is only `(sys).slice(0,400) + convo.slice(0,800)`.
- "Yes", "How much does it cost?" and "Is this a scam?" were all stored with one summary taken from an earlier probe.
- `spam` skips the answer, so a cached spam verdict would have silenced replies for a day.
- Verified live (c9): `intent_detection` made a real call (3,602 in / 643 out tokens, not cached), and the stored summary matches the mail.
- **Still open for IT:** the gateway's semantic key is dominated by fixed prefixes. `json_extraction` and `internal_judgement` also hold `llm_cache` rows.

### Medium

- **M1. Answers named four of the six items.** They left out the company profile and acceptance of the supplier terms, in every answer that explained registration before #1715. Fixed by **#1715** (live; c9 names all six, numbered).
- **M2. 3 of 8 answers gave no way in.**
  - Which answers: c2 ("how much does it cost?") and c8 ("what documents?") through the **reasoned** path, and c5 (Arabic) through the direct path.
  - Each answered the question with no claim link and no next step.
  - The reasoned path is checked by a second model but never for the link.
  - Recommended: pass the claim link as `aiReply`'s `must` for an unregistered lead, and fall to the direct path when a reasoned answer lacks it.
  - Not fixed here because auditors A and B are both working in `email_triage` today.
- **M3. 1 of 9 answers was lost.**
  - In c7 ("we are already registered"), the `email_triage` worker booted at 08:10:44 and was retired at 08:12:36 (`EarlyDrop`, cpu 88 ms). No response was logged and its `agent_runs` row never finished. The model calls had already been paid for ($0.07).
  - `resend_inbound` wakes `email_triage` with a **55 s** abort, while answers take 82 to 195 s.
  - **Likely mechanism, not proven:** the dropped caller connection lets the runtime retire the worker. `EarlyDrop` is also the normal retirement reason, at thousands a day, and 8 of 9 answers survived the abort.
  - Safety net: `customer_support.unanswered_inbound` opens a support case after 2 hours.
  - Recommended: `email_triage` acknowledges at once and answers inside `EdgeRuntime.waitUntil`.
- **M4. The answer takes 1.5 to 3 minutes.** Times to the queued answer were 132.6, 108.9, 119.3, 151.3, 168.9, 93.1 and 82.4 s, then 194.7 s after the fix; median 126 s. The founder's rule for e-mail (28 Sep, the `email_triage` header) is "a reply in under a minute". 0 of 9 met it.
- **M5. Knowledge contradicts production and the signed agreement.**
  - `knowledge/brief/company.md` says "No supplier is approved automatically", compiled 3 times into `brief.generated.ts`.
  - `knowledge/COMPANY_CANON.md` says "Today approval is manual; an auto-approve flag … switched off" and "The trade licence is the only required document".
  - In fact `pricing_config.auto_approve_suppliers = true`, SA v16 discloses automated approval, and the company profile is a mandatory upload (`reg_profile` needs the document in storage).
  - This reached suppliers: c8 said "The only mandatory document to upload is your valid UAE trade licence"; the reasoned drafts of c5 and c7 said "approval is not automatic".
  - The brief also describes the profile as "company profile (trades and emirates)", which reads as fields, not an upload.
- **M6. A supplier's claim was believed over the facts.** In c7 the reasoned draft read "Thanks for confirming your company is registered. You do not need to register again." The facts said "THEY HAVE NOT REGISTERED YET: never call them registered" (confidence 0.5; the worker was retired before anything was sent).
- **M7. Queues with no actor.**
  - `doc_trades_held`: 18 pending. All 18 point at deleted ZZ DEMO leads from last night's registration walks (teardown leak), and no routine consumes the kind.
  - `vision_trades_confirm`: 0 pending. Its decider `fn_sales_engineer_decides_vision_trades` has **no caller** anywhere (DB, edge, app).
  - `spec.not_sure`: 5, the oldest 15.7 days. The handler waits.
  - `held_question`: 327, the oldest 32.7 days, plus `held_question_expired` 10. These are internal surfaces; 6 `supplier_documents.subject` items are from 25 Sep.
- **M8. The seat is not learning.**
  - `seat_self_review`: "no qualification exam on file" in **both** September and October. Improvement 20010 is open since 1 Oct with no evidence. The 27 Oct seat audit graded an exam at 41.0%, so the self-review is stale.
  - `seat_learning_daily`: accuracy 41.3% (19 of 46 outcomes), flat for 7 days, **0 lessons approved**.
  - Open improvements on the seat include the `supplier_portal` error budget (since 1 Oct) and a weekly review of 27 open findings, escalated twice.
  - `win_loss_review` (Sep) and `weekly_quality_review` (W43) found 0 requests to review: pre-launch, customer-side.
- **M9. Capacity on the journey.**
  - `license_extract` failed 38 of 99 runs in 14 days ("Invalid image data URL … not base64"), fixed by #1707, which is deploying. Today it has a latency alarm: 11.1 s against a 3.3 s baseline.
  - `supplier_api` has 30-day availability of 94.18% (error budget at 51×) and `supplier_portal` 97.91% (IT SLO findings open since 29 to 30 Sep).
  - Resource kills in the last 24 h: `ai_gateway` CPU 76×; `supplier_portal` CPU 7×; `supplier_api` CPU 3× and Memory 2× (08:10Z today).
- **M10. Over-escalation.** "Is this a scam? How did you get our email address?" was judged `needs_a_person` and filed for a human, the founder's Inbox. The founder's rule is that no person is brought in unless one is explicitly asked for.

### Low

- **L1.** `app_secrets.invite_preheader` = "Free for the first 1,000 suppliers, permanently. No commission, ever. Register in minutes."
  - It is never rendered: both lanes send `campaignMail` plain text for campaign rows.
  - It is offer wording the 27 Oct rules removed, and "ever" overstates SA cl. 7 (commission possible on 30 days' notice).
  - Retire the key.
- **L2.** A nudge row stores a body that is never sent, because `campaignMail` substitutes variant A. The record does not show what was delivered.
- **L3.** `invite_ramp` logged an `error` ("STALLED … the previous run was already a restart") after a day held by the placement gate. That raised a high-severity watch (`watch:run_failure:invite_ramp`) although today's batch queued fine.
- **L4.** The rehearsal-window cap is soft by one call. The gate estimates the next call as the average of the tag's earlier calls (~$0.01), so my case 1's $0.60 cold-cache call ran inside a $0.50 window.
- **L5.** `scripts/e2e/invitation_reply_probe.mjs` does not clean `seat_judgement`. 6 orphans remain from last night's three runs, surfaces `email_triage.reply` and `email_triage.needs_a_person`. My runner deletes them; the repository probe should too.
- **L6.** The registration-walk teardown misses `agent_actions` `doc_trades_held`, which caused the 18 rows in M7.
- **L7.** Real invitation queue at 08:39Z: 2 of 20 sent (07:01, 07:47) and 18 `queued`, with `not_before` passed and no error. That is slower than the documented 5 per run. Campaign caps and brakes were not touched (hard limit); measured only.
- **L8.** Answers c3 and c6 send suppliers to call or WhatsApp **+971 50 931 9355**. That is the published company line (`company.json`) and also the founder's own mobile.
- **L9.** The approval notice says "message us on WhatsApp" with no number.

## Area 1: running

### The journey's routines: who calls them, how often, last real run, effect in 7 days

| routine | called by | cadence | last run | effect in 7 days |
|---|---|---|---|---|
| `fn_sales_engineer_supplier_outreach_tick` | seat duty `sales_engineer.supplier_outreach`, own pg_cron job 639 (`*/5`, 60 s) since #1705 | daily batch after 09:00 Dubai | 28 Oct 06:45Z | 20 invitations queued today (2 sent, 18 queued at 08:39Z). Before today, held every day: placement gate or weekend. |
| `enqueue_supplier_invites` | the outreach tick | daily | 28 Oct 06:45Z | as above |
| `fn_sales_engineer_raises_undecided_submissions` | the outreach tick, step 3 | **once per Dubai day**, so a submission can wait up to ~48 h before it is raised | 28 Oct 06:45Z | 0 raised in 7 days; 0 `supplier_submission_undecided` reports ever |
| `fn_sales_engineer_sends_registration_reminder` | the outreach tick (`fn_supplier_registration_reminders_due`, days 2 and 6) | once per Dubai day, open weekdays only | 28 Oct 06:45Z | 0 due, 0 sent (real) |
| `fn_sales_engineer_supplier_onboarding` | seat duty, daily | daily | 27 Oct 21:00Z | nudged 0; nudges held (campaign closed then) |
| `fn_sales_engineer_nudges_invited_suppliers` | the onboarding duty and `enqueue_supplier_invites` | daily | 27 Oct 21:00Z | 0; first real due Mon 2 Nov (see H1) |
| `fn_sales_engineer_supplier_documents_tick` | `resilience_ping` step `supplier_docs`, gated by `it_duty_schedule.supplier_docs` (1 day) | daily | 27 Oct 17:16Z | 9 approved re-checked, 0 closed, 0 notices |
| `fn_sales_engineer_licence_expiry_watch` | seat duty, daily | daily | 27 Oct 21:30Z | 0 licences within 30 days, 0 asks |
| `fn_sales_engineer_verifies_supplier` | `supplier_api` save (RPC), `supplier_portal`, `_shared/supplier_docs_later`, trigger `z20` on `leads`, the documents tick, the 24-hour clock, `fn_supplier_doc_reading_escalate` | on each save or event | today, fixtures only | 5 decisions, all ZZ DEMO; **0 real decisions ever** |
| `fn_sales_engineer_tells_the_supplier_he_is_approved` | trigger `trg_sales_engineer_tells_the_supplier_he_is_approved` on `leads` | on approval | today, fixture | 1, skipped (fixture); 0 real |
| `fn_sales_engineer_takes_invite_reply` | handler of `invite.reply` (`seat_handoff_kind`, via `fn_seat_handoff_act`) | on a reply | never | **no actor: returns `waiting` only** (H2) |
| `fn_sales_engineer_acts_on_handoff` | handler of 17 money and backup kinds, plus `fn_delivery_result_acts` | on a handoff | n/a | 0 supplier-facing money events (pre-launch); `backup.refile` and `backup.remediate` answered, waiting for their senders since 12–13 Oct |
| `fn_sales_engineer_decides_vision_trades` | **nothing** (orphan) | none | never | its queue is empty |

**The 26 seat duties** are all enabled, show 0 failures and are on their clocks. Their last results show 0 rows acted on for every duty except:
- `supplier_performance`: 2 scored, 20,285 score rows refreshed;
- `supply_gap` and `supply_gap_recruitment`: 77 recruit, 150 deferred, 77 briefs open;
- `supplier_outreach`.

The rest serve customers, quotes, reveals or internal reporting, and have nothing to act on before launch. **"ok" here means "nothing to do", not "did it".**

### What is waiting for sales_engineer (pending `agent_actions`, measured 07:40Z)

| type | n | answered by the seat | oldest | actor |
|---|---:|---:|---|---|
| `held_question` | 327 | 0 | 25 Sep (785 h) | **none**: "A question held after 5 failed reasonings … needs you" |
| `it.finding` | 66 | 66 | 29 Sep (703 h) | answered, waiting for IT to close |
| `knowledge.request` | 19 | 19 | 27 Oct (11 h) | answered, waiting for customer_support to close |
| `doc_trades_held` | 18 | 0 | 27 Oct (22 h) | **none** (and all leaked fixtures) |
| `held_question_expired` | 10 | 0 | 6 Oct (533 h) | **none** |
| `spec.not_sure` | 5 | 5 (`waiting`) | 12 Oct (376 h) | **none**: the handler waits |
| `ceo.root_cause` / `ceo.revise` / `ceo.month_directive` / `ceo.directive` | 3 / 1 / 1 / 1 | all | 29 Sep (700 h) | answered, waiting for the CEO to close |
| `backup.remediate` / `backup.refile` | 1 / 1 | both | 12–13 Oct | answered, waiting for the CEO and IT to close |
| `invite.reply` | 0 (ever) | n/a | n/a | **none** (H2) |

## Area 2: errors and capacity (14 days, logs 24 h)

**Observed runs** (`agent_runs`, `fn:<slug>`), 14 days:

| function | runs | errors | other non-ok | p95 | notes |
|---|---:|---:|---:|---:|---|
| `license_extract` | 99 | **38** | 5 | 15.8 s | "Invalid image data URL … not base64"; #1707 |
| `supplier_api` | 8,400 | 6 | 36 | 2.0 s | IT SLO: 30-day availability 94.18%, budget burn 51× (open since 29 Sep) |
| `supplier_portal` | 5,736 | 0 | 410 | 0.9 s | 327 `unauthorized`, 83 `no_company`; SLO 97.91% |
| `claim_lookup` | 2,506 | 0 | 331 | 0.1 s | 325 `invalid_link` (mostly harness), 6 `not_found` |
| `login_otp` | 1,240 | 0 | 601 | 1.9 s | guard refusals (phone not linked, fixture numbers, attempts) |
| `email_triage` | 697 | 0 | 7 | 5.5 s | max 182 s; 1 answer lost today (M3) |
| `ai_gateway` | 29,704 | 369 | 239 | 31.9 s | 1.2% errors; **CPU-time kills 76 in 24 h** |

`ai_cost_log`, `ok = false` over 14 days:

| function | failed / calls | rate |
|---|---:|---:|
| `license_extract` | 38 / 142 | 26.8% |
| `supplier_api` | 5 / 804 | 0.6% |
| `email_triage` | 1 / 163 | 0.6% |
| `sales_engineer` | 7 / 1,357 | 0.5% |
| `supplier_doc_trades` | 8 / 2,258 | 0.4% |
| `site_assistant` | 6 / 1,636 | 0.4% |

**Statement timeouts.** 179 `canceling statement due to statement timeout` in 24 h, all through PostgREST (8 s). All were the invitation candidate query ("ONE COMPANY, ONE INVITATION"), from `resilience_ping`'s old step, about every 30 minutes. None after 06:15Z, when #1705 moved the batch to its own 60 s job.

Other journey routines measured in `pg_stat_statements`:

| routine | mean | max | how it is called |
|---|---:|---:|---|
| documents tick | 27 ms | 103 ms | PostgREST |
| verification | — | ≤ 2.4 s | portal and API path |
| outreach tick, held path | 88 ms | 6.0 s | the old PostgREST path |

The 19.9 s verification batch is `demo_factory`, the harness. `fn_seat_duty_run` peaked at 57.7 s against a 60 s job limit (duty not identified).

## Area 3: qualified on facts

**What a supplier is told, checked against the source of truth** (Supplier Agreement v16 in `src/content/legal.json`, the founder's rulings):

| claim | where | verdict |
|---|---|---|
| Registration free for the first 1,000 suppliers, permanently; AED 1,000 a year from the 1,001st | reply facts, answers c1 to c9, reminder, nudge (stored only) | **true**: SA cl. 6; 0 registered so far |
| No commission on won work | answers, reminder | **true**: SA cl. 7 (under this version) |
| "No commission, **ever**" | `invite_preheader` (dormant) | **overstated**: cl. 7 allows one on 30 days' notice (L1) |
| "Nothing is charged to receive requests, and you never pay to be contacted" | c3 | **too absolute**: true for the first 1,000 only |
| Verification within 3 working days of complete documents | c1, c9, brief | **true**: SA cl. 13 |
| "We check the licence number, issuing authority and expiry date" | c5, c8, brief, SA | **false in practice** for the authority (H3) |
| "No supplier is approved automatically" / "approval is manual" | brief (×3), canon; drafts c5, c7 | **false**: SA v16 discloses automated approval; production auto-approves (M5) |
| "The only mandatory document to upload is your trade licence" | c8; canon | **false**: the company profile is a mandatory upload (M5) |
| Registration steps without the profile and the terms | facts before #1715; c1, c3, c4, c6 | **incomplete**: fixed by #1715 |
| "Reply with your trades … our team will set up the page" | facts before #1715; c1, c3, c4, c6 | **nobody performs it**: removed by #1715 (H2) |
| "We will not send you tiling requests" | c4 | true today (unregistered); the nudge would have contradicted it (H1) |
| Response time: e-mail answered "within the minute" | `email_triage` design, founder 28 Sep | **not met**: 82 to 195 s (M4) |
| Objection reply "within 10 working days" | triage draft only (never sent) | n/a |
| Approval notice: tab and button names ("Services", "Remove this trade", "Confirm my services") | `fn_supplier_approved_notice_compose` | **true**: present in the portal |
| Reminder (stages clicked, started, incomplete) and closing notice | `fn_supplier_registration_reminder_compose`, the documents tick | **consistent**: free, no commission, the six, the 14-day close |
| Invitation (variant A) | `m365_lane.ts`, `app_secrets.invite_body` | no offer, no link, the stop line: consistent with the 27 Oct rules |

**Arabic.**
- Suppliers are always written to in English (founder, 28 Sep).
- The Arabic branches in the reminder and closing composers are unreachable (`v_ar := false`); where present they say the same things (free, no commission, the six).
- An Arabic question (c5) was answered in English, as ruled. That answer listed the six correctly, gave no link, and repeated the authority claim.

## Area 4: qualified on judgement

**Decision table**, rolled back, `auto_approve_suppliers = true`, 0 rows left (`verification_decision_table_28_oct.json`):

| situation | decision | right? |
|---|---|---|
| S1 complete, every licence field read, in date | approved (notice queued) | yes |
| S2 licence expired yesterday | action_required (`licence_expired`) | yes |
| S3 expiry not read | pending (`licence_expiry_unread`), needs_review | yes |
| S4 licence name not read | pending (`licence_unreadable`), needs_review | yes |
| S5 licence number not read | pending (`licence_number_unread`), needs_review | yes |
| S6 company profile missing | action_required (`reg_profile`) | yes |
| S7 issuing authority Saudi Ministry of Commerce | **approved** | **no** (H3) |
| S8 issuing authority never read | **approved** | **no** (H3) |

**Has it ever approved an expired or unread licence?**
- Real suppliers: none was ever decided, so no.
- History: a handful of `supplier_verification` rows survive (4 at 07:50Z, 5 at 08:39Z, as other auditors' fixtures came and went), all ZZ DEMO; the harnesses delete their own.
- One standing fixture (lead 126512, `demo_factory`) was approved on 18 Sep with an **unread licence name**, before the 7 Oct rule (#1285). Today's rules hold that case.

**Decisions are explainable.** Each one writes `agent_actions` `supplier_verification` with a title carrying the reason, a recommendation, and the full input set (missing items, expiry, unread flags, `auto_approve`, source).

**The escalation path exists and has never been used.**
- needs_review rows, then `fn_sales_engineer_raises_undecided_submissions` at 24 h (once a day), then `support_ceo_report`: 0 `supplier_submission_undecided` reports ever.
- A person-review request goes to `review.requested`, handled by `fn_review_request_waits` and `decision_review_request`: 0 rows ever.
- No routine decides a held supplier after the CEO report, so the SA's 3 working days is unproven for held cases (H3, area 6).

**The last 30 real verification decisions:** none exist. Approval rate, hold reasons and time-to-decision cannot be measured on real suppliers.

**Is it learning?** No (M8).

## Area 5: conversation quality

Eight replies were sent once each through the real path. The full answers are in `CONVERSATION_ANSWERS_28_OCT.md`.
- Tags `ac1…` to `ac8…`; the re-run after the fix is `ac9…`.
- Each tag had its own rehearsal window with `cap_usd` 0.50.
- **Spend:** $1.20 was tagged. $1.44 if every untagged `email_triage` call in the same minutes is counted, which may include other auditors' runs. The cap was $1.50.

| # | supplier wrote | path | time | accurate | tone | correct link | no false claim | next step | grade |
|---|---|---|---:|---|---|---|---|---|---|
| c1 | "Yes" | direct | 132.6 s | ✗ (4 of 6) | ✓ | ✓ | ✗ (set-up offer) | ✓ | **FAIL** |
| c2 | "How much does it cost?" | reasoned | 108.9 s | ✓ (cl. 6, 7) | ~ ("can't confirm which tier") | ✗ none | ✓ | ✗ | **PARTIAL** |
| c3 | "Is this a scam? How did you get our email?" | person | 119.3 s | ~ ("nothing is charged to receive requests") | ✓ honest | ✓ | ✗ (set-up offer) | ✓ | **PARTIAL** (over-escalated, M10) |
| c4 | "We only do steel, not tiles." | direct | 151.3 s | ✗ (4 of 6) | ✓ apologises, adapts | ✓ | ✗ (set-up offer) | ✓ asks scope | **PARTIAL** |
| c5 | Arabic: free? which papers? | direct | 168.9 s | ✓ six | ✓ English (ruled) | ✗ none | ✗ (authority checked) | ✗ | **PARTIAL** |
| c6 | "Please call me on +971 50 000 0042" | person | 93.1 s | ✗ (4 of 6) | ✓ | ✓ | ✗ (set-up offer) | ✓ (team will reply; phone) | **PARTIAL** |
| c7 | "We are already registered with you." | none | lost | ✗ (draft believed the claim) | n/a | n/a | ✗ ("approval is not automatic") | ✗ | **FAIL** (M3, M6) |
| c8 | "What documents do you need?" | reasoned | 82.4 s | ✗ ("only mandatory document is the licence") | ✓ | ✗ none | ✗ (authority checked) | ✗ | **FAIL** |
| c9 | "Yes" again, **after #1714 and #1715** | direct | 194.7 s | ✓ six, numbered | ✓ | ✓ | ✓ no offer | ✓ | **PASS** (time ✗) |

## Area 6: SLAs

| step | promised | where promised | measured | met? |
|---|---|---|---|---|
| a supplier's e-mail reply → the answer | "a reply in under a minute" | founder, 28 Sep 2026 (`email_triage` header) | 82.4 to 194.7 s, median 126 s; 1 of 9 lost (safety net: a support case after 2 h) | **no** |
| complete registration → decision | within 3 Working Days of complete documents | Supplier Agreement v16 cl. 13 | instant on save when every licence field is read (decision table S1; the 28 Oct registration walk: "terms + Save → approved") | yes |
| held registration → decision | same | same | 24-hour clock runs once a day, then a CEO report; no routine decides after it; 0 ever raised | **unproven** |
| an undecided submission → raised | 24 h | `fn_sales_engineer_raises_undecided_submissions` | runs once per Dubai day, so up to ~48 h | partly |
| a supplier who replied → follow-up | none promised | — | none after #1713 (H2) | gap |

## Fix PRs

| PR | what | state |
|---|---|---|
| **#1713** | `sales_engineer`: a supplier who answered the invitation is not asked the same question again | open; pending apply at merge; **before Mon 2 Nov 09:00 Dubai** |
| **#1715** | `sales_engineer`: an invited supplier is told the six, and is never offered a set-up nobody performs | merged and deployed by the coordinator; verified live (c9) |
| #1716 | `it_engineer`: the inbox triage classifies each mail on its own | closed as a duplicate of #1714 (auditor A), which is live and verified (c9) |

## Clean-up

**Zero rows left**, measured after the last run on every surface the probes write:

| surface | left |
|---|---:|
| leads | 0 |
| notifications | 0 |
| inbound_messages | 0 |
| seat_judgement | 0 |
| reasoning_held_question | 0 |
| agent_actions | 0 |
| support_customer_profile | 0 |
| assistant_logs | 0 |
| sales_decision_log | 0 |
| support_reply_readability | 0 |
| storage objects | 0 |
| suppressions | 0 |

The nine rehearsal windows are kept **closed** as the spend record. The rolled-back proofs (#1713's probe and the decision table) left nothing; `safe_replay` fingerprints were unchanged.

Not mine, and left in place on purpose, reported in L5 and L6:
- 6 orphaned `seat_judgement` rows from last night's reply probes;
- the 18 `doc_trades_held` rows from the registration walks.
