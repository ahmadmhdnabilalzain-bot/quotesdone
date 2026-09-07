# Company brain — Customer Experience

Plan for the founder's approval. Nothing here has been applied to production.

**Hard constraint carried through every line:** no position in this department may depend on a language
model at run time. Every resolver below is data, arithmetic, stored decision procedure, or retrieval over
records the estate already holds (lexical match plus the free in-region `gte` embedding). With OpenRouter
switched off, every seat still answers or refuses honestly. Section 9 of each seat lists what genuinely
cannot be done without a model — those items are proposals to *drop or degrade*, not to build.

## What was measured before writing this (production, `htdblwldjkcgjvmqkbeh`, 2026-09-07 08:02 UTC)

**The seats.** `public.org_agents where department='customer_experience'` holds 7 rows, 5 active:
`followup` (Customer Success Director, director, reports to `ceo`), and four specialists reporting to it —
`cs_onboarding`, `cs_support`, `cs_retention`, `channel_specialist`. Two are inactive: `comms_manager`
("Parked 3 Sep 2026 (PACR-004 STAFF_ORG re-carve)… Live accountability moved to followup") and
`notification_ops` ("merged into channel_specialist (Lifecycle Channel Operations) 14 Aug 2026").
`public.org_role` holds 6 matching rows; `communications_manager` is `status='retired'`,
`runtime_enabled=false`.

**The demand this department serves.** `customers` = 1. `inquiries` = 0. `quotes` = 0. `transactions` = 0.
`messages` = 0. `reviews` = 0. `feedback` = 0. `refunds` = 0. `phase_c_refund_decision` = 0.
`refund_event_quarantine` = 0. `payment_dispute` = 0. `customer_score` = 0. `contact_messages` = 0.
`leads` = 22,265 (161 `invite_status='sent'`, 10 `'bounced'`, 22,094 null). `inbound_messages` = 4.
`wa_messages` = 12, all founder command traffic, none `escalated`.

**The one real customer.** `customers` id `e0dee407-…`, created **2026-09-06 07:38:12 UTC**,
`email_verified=true`, `phone_verified=false`, `wa_optin=false`, `tos_accepted_at=null`,
`tos_version=null`, `locale='en'`, `industry=null`, `banned=false`. The `customer_health` view scores it
`health 46.8`, `risk_tier 'medium'`, `engagement 5`, `satisfaction 70`, `progress 50`, `service 60`,
`total_inq 0`, `last_activity null`. Its welcome email (`notifications` id 20610, `kind='customer_welcome'`)
was **created 2026-09-06 19:00:32 UTC and sent 19:02:02 UTC** — 11 h 22 min after registration, then
1 min 30 s in the outbox. (The only other two `customer_welcome` rows are rehearsal fixtures at
`@example.invalid`, both `status='skipped'`, "reserved test domain (RFC 2606): never deliverable".)

**The refund ladder — already coded, already deterministic, already on cron.**
`pricing_config` (id 1, updated 2026-09-06 14:22:03 UTC): `refund_window_working_days=5`,
`chase_after_working_days=3`, `bank_settlement_working_days_min=7`, `_max=14`,
`standard_reveal_rate=0.03`, `promo_reveal_rate=0.03`, `supplier_reg_fee=1000` AED yearly,
`supplier_free_count=1000`, `supplier_charging_starts=null`, `auto_approve_suppliers=true`,
`category_open_min_suppliers=10`.
`decision_policy`: `refund_admin_fee_aed=250`, `refund_late_fee_annual_pct=9`,
`refund_notify_after_working_days=1`, `refund_call_after_working_days=5`,
`refund_claim_after_call_working_days` marked RETIRED 6 Sep 2026,
`founder_review_gates=['refund_decision','refund_outside_policy']`, and the founder's ruling stored
verbatim under `refund_policy_founder_decision_2026_09_06`.
`fn_refund_state(uuid)` is a pure state machine returning one of
`not_revealed | supplier_responded | refunded | refund_rejected | waiting | chase_due | chased |
final_call_due | final_call_sent`, with `chase_due_at`, `founder_call_due_at`, `chased_at`,
`final_call_sent_at`, `can_notify`, `refund_approvable` and `working_days_since_reveal`.
`fn_refund_ladder_sweep()` runs on `cron.job` **343, `35 * * * *`, active** (`refund_ladder_sweep_hourly`);
it queues the day-3 chase email (supplier addressed, customer cc'd), opens an `org_tasks` row on the
owning agent, and on day 5 files the refund through `fn_refund_request` and pages the founder via
`fn_notify_founder(p_kind='refund_final_call')`.
`fn_refund_amount_aed(paid_aed, paid_at, refund_at)` returns customer refund = the fee in full, no
deduction; supplier charge = fee + AED 250 + 9 % p.a. simple interest pro-rated by calendar days in
Asia/Dubai; and the `7-14` bank settlement string.

**Only refunds reach the founder.** `founder_mail_policy` allows email to him for `refund_approval`,
`refund_decision` and `refund_final_call` (plus the finance, security and platform-outage kinds owned by
other departments). It explicitly **denies** him `customer_escalation` (owner `customer_success_director`),
`refund_complaint` (owner `customer_success_director`, reason: "only the day-5 final call and the refund
approval reach the founder (6 Sep 2026)") and `customer_welcome` (owner `customer_onboarding`).
`decision_policy.action_autonomy` routes `customer_escalation` to `customer_success_director`.

**Authority.** `employee_authority` for this department: `followup` is `autonomous` on `nudge` and
`resolve_within_policy` up to AED 10,000, and `advisory` only on `refund_within_window` ("execution is the
founder's decision — ruling 17 Aug 2026, restated 6 Sep 2026"). `cs_onboarding`, `cs_support` and
`cs_retention` are `advisory` at threshold 0 on all three classes. `channel_specialist` has one row:
`analysis`, `supervised`.

**KPIs.** `employee_kpi` holds 7 active rows for these seats. Five of them
(`followup` ×2, `cs_onboarding`, `cs_support`, `cs_retention`) share **one** `measure_sql` that counts
`notifications` sent within 24 h — it reported **59.44 %** against a 95 % target at 2026-09-07 03:30 UTC.
That instrument measures the outbox, not customer issues; there are 0 customer issues to measure.
`channel_specialist` owns "Hard bounce rate", measured **5.85 %** against a target of 2 (from `leads`).
`followup` id 116 ("Alerts raised that reach the founder") carries `no_measure_reason`:
"NEEDS DEMAND THAT DOES NOT EXIST."

**Goals.** `company_goals` with `owner_dept='customer_experience'`: `customers_registered` 5,000 (measure
`count(*) from customers` → 1), `customers_active` 1,500 (measure `count(distinct customer_id) from
inquiries` in 30 d → 0), `customer_satisfaction` 4.5 (measure `avg(rating) from reviews` → null, 0 rows),
`customer_retention` 85 % and `csat` 95 % — both carry `no_measure_reason` "NO INSTRUMENT EXISTS."
The revenue goal `revenue_annual` (AED 1,000,000, deadline **2027-08-31**) is owned by `finance` and
measured as `sum(coalesce(reveal_fee, app_fee)) from transactions where revealed_at > now()-365d and
refund_confirmed_at is null`.

**Channels.** `notifications` = 855 (sent/email 632, digested/email 170, expired/email 33,
skipped/whatsapp 13, skipped/email 7). `messaging_template` = 14: approved WhatsApp templates exist
en+ar for `customer_new_quote`, `customer_supplier_unlocked`, `supplier_new_inquiry`,
`supplier_doc_expiry`, `supplier_quote_accepted`; `founder_alert` is `pending`; `control_mode_code` is
`rejected` ("Application does not have permission for this action"). There is **no** approved template for
a refund-ladder chase, a welcome, or a satisfaction request.
`phase_d_external_message_contract` = 4 rows; only `reveal.customer.email` is sent today —
`reveal.supplier.email`, `reveal.customer.whatsapp` and `reveal.supplier.whatsapp` are marked `required`
and "not sent today". `response_template` = 13 active rows (`greeting` and `thanks` used 3 times each,
the other 11 `used_count=0`). `email_suppressions` = 37 (36 `hard_bounce:permanent`),
`email_block_pattern` = 4 active, `v_email_deadletter` = 0. `company_faq` = 484 rows, **477 embedded**
with `embedding_gte`; approved: 304 internal, 105 public/all, 29 non-public/all, 25 public/customer,
21 public/supplier.

**Knowledge held.** `agent_knowledge` for the 5 seats = 58 rows (`followup` 19, `cs_retention` 11,
`cs_support` 11, `cs_onboarding` 9, `channel_specialist` 8). Every `layer='experience'` row is
`validation_status` `quarantined` or `unsourced`; every `layer='profession'` row is `unvalidated`.
`ops_knowledge` = 9,140 rows, of which `dept_key='customer_experience'` = 95 and the legacy
`dept_key='customer_success'` = 271. Every one of the 95 CX rows has `deterministic=false`.

**Certifications.** `role_certification` holds 10 rows for these seats (below, per seat).
`certification_exam_result` holds results for **`cs_support` only**: HDI-SCA sat twice on 2026-09-07 —
`method='lexical'` scored **2.50 %** (1/40) and `method='semantic'` scored **35.00 %** (14/40) against a
75 % pass mark; across the 80 answer slots **48 were abstentions**. No exam result exists for `followup`,
`cs_onboarding`, `cs_retention` or `channel_specialist`. `certification_knowledge_gap` has **no rows** for
any seat in this department. `org_onboarding` has one row, `followup`: `status='onboarding'`, `l1_score`
100, `l2`–`l4` null, `certified_at` null, `probation_reviews_done` 0 of 3, and `department` recorded as
the retired key `'customer_success'`.

**Workflows this department appears in** (`public.workflow` / `workflow_step`): `complaint` (10 steps,
`customer.complaint`), `refund` (10 steps, `refund.requested`), `customer_registration` (8 steps,
`customer.registered`), `payment` #7 and `rfq_handling` #1/#17. `phase_b_sla_policy` = 34 rows, including
`SLA-SUPPORT-ACK` 15 minutes, `SLA-SUPPORT-RESOLVE` 4 business hours, `SLA-REFUND-TRIAGE` 4 business
hours, `SLA-CUSTOMER-ONBOARD` 30 minutes, `SLA-NOTIFICATION` 5 minutes, `SLA-CUSTOMER-INPUT` 24 hours,
`SLA-IDENTITY-VERIFY` 5 minutes. `org_tasks` for this department: 90 rows (57 done, 20 cancelled,
13 assigned).

**Legal ground.** `legal_documents`: `refund-policy` v1.3 (eff. 2026-09-06), `complaints-policy` v1.1
(eff. 2026-09-06), `customer-terms` v5 (eff. 2026-09-06), `supplier-agreement` v8 (eff. 2026-09-06),
`privacy` v1.2 (eff. 2026-09-06), `data-retention-policy` v1.1, `acceptable-use` v1.1.

**Model dependence today.** `support_ai` is a retired 410 stub (22 Jul 2026). The live public assistant is
`site_assistant`, which routes through `ai_gateway` with `try_faq=true` — the FAQ can answer with no model
at all, but a miss buys a model call. `llm_calls` shows 78 rows for `fn='site_assistant'`, last on
2026-08-14. `wa_inbound` contains no LLM reference. `email_triage`, `intent_router` and `copilot` do.

---

## followup — Customer Success Director

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|----|----------------------|------|-----------|----------|---------------------------|
| F01 | Is this reveal now at day 3 with no supplier response — do we chase today? | gate | per open reveal, hourly | `fn_refund_ladder_sweep` (cron 343) | Chasing early burns supplier goodwill; chasing late pushes the day-5 call past the promise in `refund-policy` v1.3 |
| F02 | Is this reveal now at day 5 — does the founder get the final call? | escalation | per open reveal, hourly | the sweep, then the founder | Paging him early breaks "only refunds reach the founder"; paging late breaks his own 5-working-day ruling |
| F03 | Did the supplier actually respond, or did we only *think* they did? | diagnosis | per ladder tick | the ladder | A false "responded" strands the customer with no refund; a false "silent" charges an innocent supplier AED 250 + 9 % |
| F04 | What exactly goes in the founder's day-5 case file? | craft | per final call | the founder | An incomplete case file makes him ask questions, which is the failure mode this seat exists to prevent |
| F05 | The supplier replied *after* the founder was paged — do we withdraw the refund? | gate | per late response | the founder, the customer | Refunding after a real response charges a supplier who performed |
| F06 | A customer asks for the reveal fee back for a reason that is *not* supplier silence — what happens? | gate | per request | the customer | Treating a buyer's-remorse request as a ladder case fabricates a supplier fault |
| F07 | Is this customer's complaint a `complaint` workflow case or a `refund` workflow case? | sequencing | per complaint | `cs_support` | The wrong workflow routes money to the wrong gate |
| F08 | Which remedy do we offer when the answer is "not a refund"? | allocation | per complaint | `cs_support`, the customer | An unauthorised credit or waiver is money movement this seat may not make |
| F09 | Does this issue touch a `legal_triggers` phrase and therefore leave the department? | gate | per complaint | `cs_support` | Answering a liability question is the single fastest way to create one |
| F10 | Is this SLA breached, and against which `phase_b_sla_policy` row? | diagnosis | continuous | `sla_watch_hourly` (cron 101) | Measuring against the wrong SLA produces a green board over a real breach |
| F11 | Who owns this breach — this department, marketplace, or supply? | allocation | per breach | the COO | Owning another department's breach hides its cause |
| F12 | Is the department's SLA attainment number measuring what it claims to? | diagnosis | weekly | the founder, the COO | The current 59.44 % measures the outbox, not customers (see §2, M4) |
| F13 | Should this reveal's customer get a proactive post-reveal check-in? | sequencing | per reveal, day 1 | this seat | A missed check-in is how a silent-supplier case is discovered on day 5 instead of day 1 |
| F14 | Is this customer at risk of leaving after a bad first outcome? | forecast | per completed reveal | `cs_retention` | A missed save costs the whole lifetime value of the only demand we have |
| F15 | Do we ask this customer for a rating now, or is now the wrong moment? | sequencing | per reveal | `cs_retention` | Asking at the wrong moment buys a 1-star answer to a question about our timing |
| F16 | Is this a systemic pattern across cases or one unhappy customer? | diagnosis | weekly | the COO | Fixing a symptom five times instead of the cause once |
| F17 | Which lifecycle messages should exist for this event, and in which language? | allocation | per new event type | `channel_specialist` | A missing template means an event fires with nothing sent |
| F18 | Is an approved WhatsApp template available for what we want to say? | gate | per send | `channel_specialist` | Sending outside an approved template gets the WABA restricted |
| F19 | Is this notification allowed to reach the founder at all? | gate | per founder-bound alert | `fn_notify_founder` | A kind with no `founder_mail_policy` row either leaks to him or is silently dropped |
| F20 | Has an alert raised for the founder actually reached him, or only been digested? | diagnosis | weekly | the founder | The KPI that would answer this (id 116) has no measure |
| F21 | Do we escalate this to the COO or resolve it inside the department? | escalation | per stuck case | `cs_support` | Escalating everything makes the ladder noise; escalating nothing hides failure |
| F22 | This case is stuck because another department has not acted — what now? | escalation | per handoff stall | this seat | `handoff_stalled` is explicitly not the founder's; it must go up the receiving lane |
| F23 | Is the customer's expectation of supplier response time set from real data or from hope? | craft | per reveal | the customer | Promising a response window the marketplace has never met |
| F24 | The revealed supplier's contact details are wrong or dead — what is the remedy? | gate | per bad reveal | the customer | This is a platform fault, not a supplier fault; the ladder must not be used for it |
| F25 | The buyer wants to bypass the platform after revealing — do we act? | gate | per detection | trust & safety | Over-policing a legitimate direct relationship; under-policing a repeatable leak |
| F26 | Do we suspend this supplier for repeat non-response? | escalation | per pattern | supply / marketplace | This department may *recommend*; the marketplace director decides |
| F27 | What do we tell a customer whose refund the founder has just approved? | craft | per approval | the customer | Quoting the wrong settlement window turns one complaint into two |
| F28 | What do we tell a customer whose refund the founder has just declined? | craft | per rejection | the customer | A declined refund with no reasoning is the chargeback we then have to fight |
| F29 | Is this the same customer asking for a third refund? | diagnosis | per request | this seat | Serial free-look abuse is paid for by suppliers |
| F30 | Which department's KPI did this failure actually move? | diagnosis | per closed case | data_intel | Attributing a failure wrongly retrains the wrong seat |
| F31 | Do we owe this customer a written apology, and at what seniority? | craft | per severity ≥ high | this seat | An apology from the wrong level reads as a brush-off |
| F32 | The customer is abusive — where is the line? | gate | per incident | `cs_support` | No line means the seat absorbs abuse; too low a line bans a paying customer |
| F33 | Is this RFQ suspected fake, and does support pause the journey? | gate | per suspicion | trust & safety | Pausing a real buyer is worse than screening a fake one |
| F34 | Do we hold contact for this customer during Ramadan / a public holiday / prayer times? | sequencing | seasonal | `channel_specialist` | Working-day arithmetic that ignores UAE holidays mis-dates the whole ladder |
| F35 | Is the department's open-task load inside its back-pressure ceiling? | gate | daily | dispatcher | Above `dispatch_max_open_per_dept` (250) the department stops receiving work silently |
| F36 | Which of this department's five seats should carry this task? | allocation | per task | the dispatcher | Every task landing on the director defeats the org |
| F37 | Is a seat failing repeatedly, and what is its remediation? | diagnosis | monthly | people_ops | `improvement_plan` on all five seats currently repeats one aggregate root cause |
| F38 | Is a knowledge record this department relies on stale or unvalidated? | gate | per retrieval | this seat | 58 of 58 `agent_knowledge` rows here are unvalidated, quarantined or unsourced |
| F39 | Does the department have an answer to this question at all, or must it refuse? | gate | per inbound question | any seat | A guess from a department with 0 tickets of history is fabrication |
| F40 | What is the department's quarterly commitment against the AED 1,000,000 goal? | forecast | quarterly | the founder | Committing to a number the funnel cannot produce |
| F41 | Is `customers_registered` moving, and is this department the constraint? | diagnosis | weekly | the CEO | Owning growth's shortfall as if it were a CX failure |
| F42 | Has the customer accepted the current terms version? | gate | per customer | general_counsel | The only real customer has `tos_accepted_at = null` |
| F43 | Is this customer reachable on the channel we are about to use? | gate | per send | `channel_specialist` | The only real customer has `phone_verified=false` and `wa_optin=false` |
| F44 | A data-subject request has arrived through a support channel — what happens? | escalation | rare | general_counsel | PDPL clocks start on receipt, not on routing |
| F45 | Is a remedy we granted last month consistent with the one we are granting now? | gate | per remedy | this seat | Inconsistent precedent is how a marketplace loses a dispute |

### 2. Domain logic (the models this seat reasons with)

**M1 — The refund ladder clock.** Already live and exact. Inputs: `transactions.revealed_at`,
`transactions.supplier_ack_at`, `messages` from the supplier after `revealed_at`,
`pricing_config.chase_after_working_days` (3) and `refund_window_working_days` (5),
`decision_policy.refund_notify_after_working_days` (1). Procedure: `fn_add_working_days` from
`revealed_at`; state from `fn_refund_state`. Outputs: `chase_due_at`, `founder_call_due_at`,
`can_notify`, `refund_approvable`. **Unmeasured:** the working-day calendar's treatment of UAE public
holidays — `fn_add_working_days` exists but no table of UAE holidays was found in this estate, so today
the ladder can only be weekend-aware. Any Eid or National Day inside a 5-day window silently shortens it.

**M2 — Refund arithmetic.** `fn_refund_amount_aed(paid_aed, paid_at, refund_at)`:
`customer_refund = paid` (no deduction, enforced by `fn_refund_amount_is_the_fee_paid`);
`supplier_charge = paid + 250 + paid × 0.09 × days/365`, `days` = calendar days between the two instants in
Asia/Dubai. Settlement string `7-14` working days from `pricing_config`. Nothing to build.

**M3 — Reveal fee identity.** `reveal_fee = 0.03 × quote_amount`, capped at
`standard_reveal_cap = 99,999,999` (i.e. uncapped in practice). Inputs `quotes.amount`,
`pricing_config.standard_reveal_rate`. This is the only revenue line this department can move.
**Unmeasured:** the average and distribution of `quote_amount` — 0 quotes exist, so every downstream
"reveals needed" figure is a function, not a fact (see §8).

**M4 — SLA attainment, per owner.** Correct form:
`attainment = |{cases where first_response_at − opened_at ≤ target}| / |{cases}|`, grouped by
`sla_policy_id` and by owning seat, over a stated window. Inputs: `phase_b_sla_policy.target`, a case
table. **Unmeasured, and this is the department's largest instrument defect:** there is no support-case
table in this estate. The five KPI rows that claim to measure "Customer issues resolved within SLA" run
`select … from notifications where created_at > now()-7d` — they measure whether the *outbox* flushed,
against a population that contained 0 customer issues. The 59.44 % figure is real arithmetic over the wrong
subject. Until a case table exists this metric must be reported as "not measured", not as 59.44 %.

**M5 — Case severity score (deterministic).**
`severity = 3·money_involved + 3·safety_or_compliance + 2·legal_trigger_hit + 2·repeat_case
+ 1·sla_breached + 1·public_channel`, where `money_involved` = a `transactions` row with `reveal_fee > 0`
exists; `safety_or_compliance` = the inquiry category is in `decision_policy.sensitive_categories`
(fire, security, electrical, structural, gas, lifts, medical); `legal_trigger_hit` = the text matches
`decision_policy.legal_triggers` (contract change, liability, indemnity, termination, dispute, refund
dispute, regulatory complaint, data subject request, subpoena, chargeback). Bands: ≥8 critical, 5–7 high,
3–4 normal, ≤2 low. Every input exists today except a case row to hang it on.

**M6 — Escalation routing.** Deterministic lookup, no judgement call: `decision_policy.action_autonomy`
gives the accountable role per kind (`customer_escalation → customer_success_director`,
`legal_flag → general_counsel`, `security_incident → cto`); `founder_mail_policy` gives
`allowed_to_email` and `owner_role` per kind; `org_role.escalation_targets` gives the up-line
(`customer_success_director → chief_of_staff`). Nothing to invent.

**M7 — Founder-case completeness check.** A day-5 case file is complete iff all of:
supplier name and at least one contact channel; customer name and email; `transaction_id`, `inquiry_id`,
`quote_amount`, `reveal_fee`, `revealed_at`; the `refunds.id` in `requested` status; the five figures from
M2; `chased_at` present or explicitly stated absent; `customer_notified_at` present or stated absent; and
the two named actions (approve → refund + settlement window; reject → note + case closes).
`fn_refund_ladder_sweep` already composes exactly this. The model here is the *checklist*, run as a
boolean over the composed text before it is sent.

**M8 — Repeat/abuse counter.** `refund_requests_by_customer_90d = count(refunds where customer_id = X and
requested_at > now()-90d)`; `free_look_ratio = refund_requests / reveals` for the same customer. Bands in
§4. Inputs exist (`refunds`, `transactions`); population is 0 today.

**M9 — Working-day arithmetic.** `fn_add_working_days` and `fn_working_days_between` exist and are used by
`fn_refund_state`. The Dubai week is Monday–Friday for business purposes since 2022. **Unmeasured:** no
UAE public-holiday table (see M1).

**M10 — Department capacity.** `open_tasks(dept) < decision_policy.dispatch_max_open_per_dept` (250) or
back-pressure applies; per seat, `org_agents.max_open_tasks` (50 for all four active specialists and the
director). Current open load: 13 assigned of 90 lifetime rows.

### 3. Reasoning procedures

**F01/F02 — the ladder tick (the department's most important procedure).**
1. Evidence: every `transactions` row with `revealed_at not null`, `reveal_fee > 0`, `revealed_at` inside
   120 days, and `refund_status` not already terminal.
2. For each, call `fn_refund_state`. Stop immediately on `error`, on `supplier_responded`, and on any state
   other than `chase_due` or `final_call_due` — this is the refusal, and it is a hard stop, not a judgement.
3. `chase_due` → compose the chase from the stored template slots (supplier company name, reveal date,
   chase-day count, final-call date, reveal fee, the AED 250 + 9 % consequence). Queue one email to the
   supplier with the customer in `cc_emails`. Open one `org_tasks` row on `followup`, `tier='advisory'`,
   `needs_founder=false`, carrying the ladder JSON in `result`.
4. `final_call_due` → compute M2; file the refund through `fn_refund_request` **only if no `refunds` row
   already exists for this transaction**; then `fn_notify_founder(p_kind='refund_final_call',
   p_dedupe_key='refund_final_call:'||transaction_id)`. The dedupe key is the idempotency record: the same
   transaction can never page him twice.
5. Composition: the founder's email is assembled from fixed labelled blocks — SUPPLIER, CUSTOMER, REVEAL,
   REFUND REQUEST, AMOUNTS, YOUR CALL. Run M7 over the assembled text; if any block is empty, send it
   anyway with the block marked `(not recorded)` rather than omitting it, so he can see what we do not know.
6. Refuse when: `revealed_at` is null; `reveal_fee` is 0 or null; the supplier row has no email *and* no
   phone (say so in the task, do not silently skip).

**F03 — did the supplier respond?**
Evidence in this order: (a) `transactions.supplier_ack_at`; (b) any `messages` row with
`inquiry_id = t.inquiry_id`, `supplier_id = t.supplier_id`, `sender='supplier'`, `blocked=false`,
`created_at > revealed_at`. Nothing else counts — not an email in the operator's inbox, not a claim by the
supplier on the phone, unless it has been written back to one of those two places. If a human records a
response, they must set `supplier_ack_at`; the procedure reads state, never anecdote. Refuse to declare
"no response" if `messages` is unavailable.

**F06 — a refund request that is not supplier silence.**
1. Read `fn_refund_state`. If `supplier_responded`, the ladder does not apply.
2. Classify by reason against a fixed taxonomy stored as data (supplier silence; wrong or dead contact
   details; duplicate/accidental reveal; disputed charge; buyer's remorse; quality dispute after contact).
3. Only "supplier silence" enters the ladder. "Wrong or dead contact details" is a **platform** fault:
   it is escalated as a `customer_escalation` to this seat, and the remedy proposed to the founder is a
   refund with the supplier **not** charged. "Duplicate/accidental reveal" is a platform/product question.
   "Buyer's remorse" gets the published `refund-policy` v1.3 position, not a ladder.
4. Every path that ends in money still terminates at the founder's gate. This seat never approves.
5. Refuse when the reason does not match any stored class above threshold — open a task naming the
   unclassified text, do not guess.

**F07 — complaint or refund workflow.**
Run M5. If a `transactions` row with `reveal_fee > 0` exists *and* the customer asks for money back, it is
the `refund` workflow (10 steps, founder gate at #7). Otherwise it is the `complaint` workflow (10 steps,
department-head gate at #6/#7). If M5 flags `legal_trigger_hit`, step #5 (Legal Counsel) is mandatory and
this seat may not decide the remedy first.

**F10/F12 — is this SLA breached, and does the number mean anything.**
1. Identify the `sla_policy_id` from the workflow scope, never from the seat's own opinion.
2. Compute attainment per M4, grouped by owner. Never report the aggregate alone.
3. Before reporting any attainment figure, assert that the measured population is the population the KPI
   names. Today it is not: the population is `notifications`. The correct answer to "what is our SLA
   attainment" is **"not measured — the instrument counts outbox rows, and there have been 0 customer
   cases"**, with the outbox figure reported separately under its own name.

**F19/F20 — does this reach the founder.**
1. Look the `kind` up in `founder_mail_policy`. No row → refuse to send and open a task to add one; a kind
   with no policy row is a routing hole, not a default-allow.
2. `allowed_to_email = false` → route to `owner_role` as one owned org task; the founder never sees it.
3. `allowed_to_email = true` → send, and record the `dedupe_key`.
4. For F20, the honest answer today is that the attainment KPI for this has `no_measure_reason` set and no
   `measure_sql`; the seat must say so rather than produce a number.

**F13/F14 — post-reveal check-in and churn risk.**
1. Trigger deterministically at `fn_add_working_days(revealed_at, 1)` — the same instant
   `refund_notify_after_working_days` makes the "notify supplier" button available.
2. Evidence: `fn_refund_state.supplier_responded`, `messages` count, `reviews` for the transaction.
3. Score with `customer_health` (the live view: engagement, satisfaction, progress, service → `health`,
   `risk_tier`). Bands in §4.
4. Refuse to compute a churn *probability*: `customer_score` has 0 rows and `fn_emit_churn_signal` fires on
   `churn_risk >= 0.7`, a field nothing currently populates. Report the health score, which is real, and
   say the churn model does not exist.

**F39 — the department's honest refusal.**
Match the incoming question to this taxonomy by lexical overlap plus `gte` cosine against a stored
embedding of each row's text. No type above threshold → reply with: the closest two types and their scores;
the named tables that would have to hold evidence; and the `org_tasks` row just opened. Never answer from
the 58 unvalidated `agent_knowledge` rows without labelling them unvalidated.

### 4. Judgement rules

1. `state ∈ {chase_due}` and `chased_at is null` → chase today. Reason: the founder set day 3 and the
   customer is already waiting.
2. `state ∈ {final_call_due}` and `final_call_sent_at is null` → page the founder. Reason: day 5 is his
   ruling of 6 Sep 2026, stored verbatim.
3. `supplier_responded = true` at any point → the ladder stops, whatever the customer feels. Reason: the
   AED 250 + 9 % lands on a supplier, and we do not charge a supplier who answered.
4. Any refund, credit, discount, waiver or comp → the founder. **Even when it scores well.** A goodwill
   AED 50 credit "to save the relationship" is money movement; `auto_action_max_aed = 0` means agents never
   move money without a human, and `founder_review_gates` names refunds as his.
5. A supplier with no email **and** no phone on file → do not run the ladder; open a data-quality task
   instead. Reason: we would be charging a supplier we never actually contacted.
6. `refunds` row already exists for this transaction → never file a second. Reason: double-refund risk;
   `fn_unsafe_check_double_refund` exists precisely because this failure is expensive.
7. A `kind` with no `founder_mail_policy` row → refuse to notify him, open a task. Reason: silence and leak
   are both failures, and only the policy table distinguishes them.
8. `legal_triggers` phrase present → the answer leaves this department before it leaves the building.
   **Even when the answer looks obvious.** Reason: `org_role.forbidden_decisions` for every seat here
   includes legal or regulatory conclusions.
9. `customer_health.risk_tier = 'high'` **and** `total_inq = 0` → do not run a retention campaign; run a
   first-outcome intervention. Reason: you cannot retain someone who has not yet transacted.
10. `refund_requests_by_customer_90d ≥ 3` **or** `free_look_ratio ≥ 0.5` → attach the pattern to the case
    file and recommend decline; still send it to the founder. Reason: the pattern is evidence, not a
    decision this seat may take.
11. A remedy inconsistent with one granted on the same facts in the last 90 days → refuse and escalate to
    the director for a precedent decision. Reason: inconsistent precedent is what loses a dispute.
12. `wa_optin = false` or `phone_verified = false` → WhatsApp is not an available channel for that person,
    regardless of urgency. **Even for a day-5 case.** Reason: consent, and `email` is the identity.
13. `tos_accepted_at is null` → the customer is on no terms version; any commitment quoted from
    `customer-terms` is unenforceable. Flag it, route to `general_counsel` (`terms_not_accepted`,
    `allowed_to_email=false`), and do not use it as a reason to withhold service.
14. `open_tasks(department) ≥ 250` → stop accepting non-demand work and say so. Reason:
    `dispatch_max_open_per_dept`; silent back-pressure looks like an idle department.
15. Never report an SLA attainment figure whose measured population is not the population the metric names.
    **Even when the number is flattering.** Reason: the 59.44 % is the estate's clearest example.
16. Never report a CSAT or retention figure at all today. Reason: both `company_goals` rows carry
    `no_measure_reason` "NO INSTRUMENT EXISTS", and `reviews` has 0 rows.
17. An answer built from an `agent_knowledge` row whose `validation_status` is `quarantined` or `unsourced`
    must carry that label in the answer. Reason: all 58 rows for this department are in that state.
18. A supplier suspension is recommended, never decided, by this department. Reason:
    `org_role.forbidden_decisions` for `customer_success_director` includes "overriding a marketplace
    decision on quote quality"; suspension sits with the marketplace director.
19. Abuse: two documented instances of threats or slurs in one case → one written boundary notice, then the
    case moves to `trust_and_safety_manager`. Reason: a boundary that is never enforced is not a boundary.
20. Never quote a supplier response time we have not measured. Today the measured value is *nothing*
    (0 transactions). Say "we have not yet measured this", not "usually within 48 hours".

### 5. Technical knowledge

- **The ladder as code**: `fn_refund_state`, `fn_refund_ladder_sweep` (cron 343, `35 * * * *`),
  `fn_refund_request`, `fn_refund_decide`, `fn_refund_settle`, `fn_refund_quarantine`,
  `fn_refund_amount_aed`, `fn_refund_amount_resolve`, `fn_kernel_refund_decision_record`,
  `qd_on_refund_resolved`, `fn_refund_transition_allowed` and the 32-row `refund_status_transition`
  matrix (which states may follow which, and the four that are explicitly `allowed=false` as out-of-order).
- **The founder door**: `fn_notify_founder(p_kind)`, `founder_mail_policy` (kind, `allowed_to_email`,
  `owner_role`), `fn_founder_mail_route`, `founder_alerts.dedupe_key`,
  `decision_policy.founder_review_gates`, `phase_c_action_class.founder_approval_required`,
  and the guards `fn_founder_approval_refund_only`, `fn_kernel_founder_routing_is_refund_only`,
  `fn_phase_c_non_refund_founder_approvals`.
- **Money surfaces**: edge functions `refund_flow` (customer-facing) and `refunds_api` (founder/admin);
  `stripe_webhook`, `stripe_confirm`; `transactions.refund_stripe_id / refund_amount_aed /
  refund_confirmed_at`; `payment_dispute` (0 rows).
- **SLA machinery**: `phase_b_sla_policy` (34 rows), `fn_kernel_sla_due(policy_id, from)`, `fn_sla_watch`
  (cron 101, hourly), `fn_org_task_sla_watch` (cron 286, daily).
- **Workflow machinery**: `workflow` / `workflow_step` / `workflow_run` / `workflow_step_run`; the
  `complaint`, `refund` and `customer_registration` definitions and their `actor_role` and `gate` columns.
- **Task machinery**: `org_tasks` (`dept_key`, `assigned_agent`, `tier`, `needs_founder`, `action_class`,
  `result` JSON), `event_delivery`, `company_event`, `fn_emit`.
- **Working-day arithmetic**: `fn_add_working_days`, `fn_working_days_between`, Asia/Dubai (UTC+4) as the
  business timezone for every customer-facing date.
- **What must be stored so this seat never has to ask**: the case taxonomy of F06 as a table with
  embeddings; the founder's day-5 case-file checklist (M7) as a table of required slots; the precedent
  register of remedies granted (does not exist); the UAE public-holiday calendar (does not exist).

### 6. Academic knowledge

Disciplines this seat generalises from: service operations management, queueing and capacity theory,
service-recovery research, contract and consumer-protection law as it applies to a UAE introducer platform,
and cohort/survival analysis for retention.

| framework | why this seat needs it | lawful primary source |
|---|---|---|
| Complaints-handling management system | The `complaint` workflow's 10 steps are a house implementation of one | ISO 10002 (buy a licensed copy from ISO or ESMA/MoIAT; the free ISO abstract and scope page are usable now) |
| Customer-satisfaction monitoring and measurement | Before building any CSAT instrument | ISO 10004 (same licensing route) |
| CX competency model | The seat's own certification | CXPA published **CCXP Competency Framework and exam blueprint**, free from cxpa.org |
| Customer-success operating model | Onboarding→adoption→renewal logic | SuccessCOACHING published CCSM syllabus outline (free); Gainsight and Totango public playbook documentation |
| Service quality dimensions | Deciding what a "good" outcome even is | Parasuraman, Zeithaml & Berry, *SERVQUAL* — the published instrument dimensions in the original journal article |
| Repeat-purchase / churn modelling without a model call | M8 and the churn work the estate lacks | Fader & Hardie's author-published BTYD technical notes (freely distributed by the authors at brucehardie.com) |
| Queueing (Erlang C) | Capacity per seat against arrival rate | Public-domain formula; A. K. Erlang's original papers |
| UAE consumer protection | Every refund and remedy | **Federal Law No. 15 of 2020** on Consumer Protection and **Cabinet Decision No. 66 of 2023** (Executive Regulation), from the UAE Government official legislation portal and the Ministry of Economy |
| UAE e-commerce / modern-technology trade | The platform's own legal frame | **Federal Decree-Law No. 14 of 2023** on Modern Technology-Based Trade (official portal) |
| UAE data protection | Every case that touches customer data | **Federal Decree-Law No. 45 of 2021 (PDPL)** (official portal) |
| Late-payment interest ceiling | The 9 % p.a. in M2 | The UAE Civil Transactions / Commercial Transactions provisions cited in `supplier-agreement` v8, from the official portal |
| Chargeback and dispute rules | F28 and `payment_dispute` | Visa Core Rules and Product & Service Rules (free PDF, visa.com); Mastercard Chargeback Guide (free PDF); Stripe public disputes documentation |
| Public holiday calendar | M9 | UAE Cabinet / FAHR official public-holiday announcements |
| Market and demographic base rates | Sizing, §8 | UAE Federal Competitiveness and Statistics Centre; Dubai Pulse open data |

**Certifications this seat holds** (`role_certification`): CCXP (CXPA, pass 68 %, rank 1) across
Customer Insights and Understanding; Customer Experience Strategy; Metrics Measurement and ROI; Experience
Design Improvement and Innovation; Organizational Adoption and Accountability; Culture and Accountability.
CCSM (SuccessCOACHING, pass 80 %, rank 2) across Customer Success Fundamentals; Onboarding and Adoption;
Customer Health Scoring; Escalation and Risk Management; Renewals Retention and Churn; Expansion and
Advocacy.
**Syllabus areas failed: does not exist** — `certification_exam_result` holds no row for `followup`, and
`certification_knowledge_gap` holds no row for any seat in this department. This seat has never sat either
exam. Its `org_onboarding` row shows `l1_score` 100 and `l2`–`l4` null, `certified_at` null, probation
0 of 3, under the retired department key `customer_success`.

### 7. Corporate knowledge

- **The founder's refund ruling of 6 Sep 2026**, verbatim, in
  `decision_policy.refund_policy_founder_decision_2026_09_06`. Five working days from payment; chase on
  day 3; his final call on day 5; banks take 7–14 working days; AED 250 admin fee and 9 % p.a. are the
  supplier's, never deducted from the customer; and it ends "you should never ask me about it again."
- **Only refunds reach him.** `founder_review_gates = ['refund_decision','refund_outside_policy']`;
  `founder_mail_policy` denies him `customer_escalation`, `refund_complaint` and `customer_welcome` and
  names this seat's role as the owner of the first two.
- **The 17 Aug 2026 ruling** that every refund needs the founder, restated 5 Sep and 6 Sep 2026, recorded
  in `employee_authority.note` for this seat's `refund_within_window` row.
- **Pricing**: 3 % reveal fee, uncapped in practice; supplier registration AED 1,000/year with the first
  1,000 registrants exempt permanently and registration free until 31 July 2027
  (`pricing_config`, `response_template.pricing_model`, `company_faq`).
- **The workflows this seat owns**: `complaint` steps 6 and 7 (decide the remedy; hand a refund remedy to
  the refund workflow — explicitly "the only founder gate"); `refund` steps 3 and 4 (formally notify the
  supplier copying the customer; wait out the working-day ladder); `customer_registration` steps 6 and 8;
  `rfq_handling` step 17; `payment` step 7 is `customer_retention`'s.
- **Who it hands to**: `org_role.handoff_targets` = `marketplace_director`, `general_counsel`, `cfo`,
  `lifecycle_channel_operations`. It escalates to `chief_of_staff`.
- **What it may not do**: `forbidden_decisions` = issuing a refund; changing price; overriding a
  marketplace decision on quote quality; approving its own department's output.
- **Published promises it is bound by**: `refund-policy` v1.3, `complaints-policy` v1.1,
  `customer-terms` v5, `supplier-agreement` v8, all effective 2026-09-06.
- **History it must not forget**: `comms_manager` was parked on 3 Sep 2026 and its live accountability
  moved here; `notification_ops` merged into `channel_specialist` on 14 Aug 2026; `support_ai` was retired
  on 22 Jul 2026 and the live assistant is `site_assistant`. The department's five KPI rows have shared
  one wrong-subject measure since 26 Jul 2026.
- **A precedent register of remedies granted: does not exist.** Rule 11 of §4 cannot be executed until it
  does. This is the single highest-value thing to build for this seat.

### 8. One-year plan

**Objective.** Convert every paid reveal into a customer who reveals again, and make the refund ladder so
reliable that the founder's only refund decision is a genuine judgement call, never a chase for facts.

**Metrics this seat owns.**
1. *Ladder integrity* — of reveals reaching day 3 with no supplier response, the share chased inside the
   same working day; and of those reaching day 5, the share where the founder's case file passed the M7
   completeness check on first send. Target 100 % / 100 %. Measurable the moment the first reveal exists;
   currently 0 of 0.
2. *Repeat reveal rate* — customers with ≥2 reveals ÷ customers with ≥1 reveal, trailing 90 days.
   **Currently unmeasurable: 0 transactions.**
3. *First-response time on a customer case* — **currently unmeasurable: no case table exists.** Building
   that table is this seat's Q1 dependency, not a metric it can report on today.

**Quarterly milestones.**
- *Q1 (Sep–Nov 2026)*: the precedent register and the case table exist; the five wrong-subject KPI rows are
  either re-pointed at the case table or given an honest `no_measure_reason`; the UAE public-holiday
  calendar exists and `fn_add_working_days` reads it; the day-1 post-reveal check-in fires deterministically.
- *Q2 (Dec 2026–Feb 2027)*: first real reveals pass through the full ladder; ladder integrity reported from
  measured cases; the CCXP and CCSM exams are actually sat and the gaps written to
  `certification_knowledge_gap`.
- *Q3 (Mar–May 2027)*: repeat reveal rate reported from a non-zero base; a satisfaction instrument exists
  (a 1–5 rating at reveal close writing to `reviews`, which already has six dimension columns and 0 rows).
- *Q4 (Jun–Aug 2027)*: consistency audit — every remedy granted in the year checked against the precedent
  register; the department reports SLA attainment per owner from real cases.

**Capacity check.** `max_open_tasks` = 50 for this seat, department ceiling 250, current open load 13. The
ladder is hourly and O(open reveals). At AED 1,000,000 of reveal fees and a 3 % rate, the year needs
**AED 33,333,333 of revealed quote value**. The number of reveals that represents depends on average quote
value, which is **unmeasured (0 quotes)**; the identity is `reveals = 33,333,333 ÷ avg_quote_aed`, so at an
average of AED 50,000 it is ~667 reveals and at AED 20,000 it is ~1,667. Either figure is well inside this
seat's mechanical capacity — 1,667 reveals is about 7 per working day, and the ladder is a cron job. **The
capacity constraint is not this seat.**

**Dependencies.** `supply` and `marketplace` for suppliers who respond at all (the ladder only ever fires
because a supplier did not); `growth` for registrations (`customers_registered` = 1 of 5,000);
`product_eng` for the case table and the reveal-fee flow; `finance` and the founder for every refund
decision; `channel_specialist` for the approved templates the ladder's messages will need.

**Is the slice achievable?** **No, as the department objectives are written today.** `department_objective`
74 (5,000 registered customers) stands at 1 and 75 (1,500 monthly active) stands at 0, measured
2026-09-07 03:25 UTC, against a 2027-08-31 deadline — 359 days. Reaching 5,000 registrations from 1
requires roughly 14 net new registered customers *every day* for a year, and this department does not
acquire customers; it keeps them. What would make the revenue slice achievable is far narrower and is not
in this department's gift: enough responding suppliers that a reveal is worth paying for, and enough
inbound RFQs to reveal against. What *is* in this seat's gift, and what it should be held to, is that
**every reveal that does happen either produces an outcome or produces a clean day-5 case file** — a 100 %
target on a small base, which is the honest commitment.

### 9. What this seat cannot do without a model

1. **Free-text intent classification of a message it has never seen a variant of.** Lexical plus `gte`
   embedding against the taxonomy will match paraphrases of known types; it cannot classify a genuinely
   novel complaint. The design answer is refusal plus a task, not a model — and that is acceptable.
2. **Composing a genuinely bespoke apology.** The templated composition in §3 produces a professional,
   specific memo; it does not produce warmth calibrated to one person's distress. Accepted degradation.
3. **Reading sarcasm, irony or negation in Arabic or English free text.** No deterministic method here is
   honest. The seat must not attempt sentiment scoring at all rather than do it badly.
4. **Summarising a long unstructured email thread into a case file.** The estate can extract structured
   fields; it cannot narrate. The day-5 case file is fully structured, so this does not block the ladder.

---

## cs_onboarding — Customer Onboarding Specialist

`org_agents.responsibilities`: "Onboards new buyers, ensures first RFQ is well-formed."
`org_role.customer_onboarding`, `authority_level='execute_low'`, `budget_limit=0`, `runtime_enabled=true`.
Owns: the onboarding sequence for a customer; first-inquiry guidance. Forbidden: promising quotation
outcomes; exposing supplier identity before reveal. Escalates to `customer_success_director`.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|----|----------------------|------|-----------|----------|---------------------------|
| O01 | A customer registered — has the welcome actually been queued and sent? | gate | per registration | `fn_customer_onboarding_check` | The only real registration waited 11 h 22 min for its welcome |
| O02 | Is the mobile number verified, and if not what is blocked? | gate | per registration | `customer_registration` #2 | The only real customer has `phone_verified=false`; every phone channel is closed |
| O03 | Has this customer accepted terms, and which version? | gate | per registration | `customer_registration` #3 | `tos_accepted_at=null` on the only customer means nothing we quote is enforceable |
| O04 | Is this a duplicate or previously banned identity? | gate | per registration | `customer_registration` #4 | Activating a banned identity re-admits a known bad actor |
| O05 | Did the customer give WhatsApp consent, and does the estate know it? | gate | per registration | `customer_registration` #5 | `wa_optin=false` and no consent record means WhatsApp is unavailable, not "not yet used" |
| O06 | Which language does this customer get everything in? | allocation | per registration | `channel_specialist` | `locale='en'` on the only customer; an Arabic buyer sent English is a lost buyer |
| O07 | Is this customer's first RFQ well-formed enough to dispatch? | gate | per first RFQ | `rfq_handling` #1 | A malformed RFQ produces no quotes and one permanently disappointed buyer |
| O08 | Which mandatory fields are missing from this RFQ? | diagnosis | per RFQ | the customer | Asking for everything at once abandons the form; asking for too little wastes suppliers |
| O09 | Is the job value above the AED 500 platform minimum? | gate | per RFQ | the customer | Dispatching a below-minimum job burns supplier attention |
| O10 | Is this category one we actually cover? | gate | per RFQ | the customer | F&B and on-site-visit-priced services are out of scope and must be refused early |
| O11 | Is this category open — does it have the minimum supplier count? | gate | per RFQ | `supply` | `category_open_min_suppliers = 10`; dispatching into an empty category guarantees zero quotes |
| O12 | Is the customer's expected timeline realistic against `SLA-QUOTE-WINDOW`? | forecast | per RFQ | the customer | An over-promise here becomes a complaint on day 3 |
| O13 | Does this RFQ need a drawing, BOQ or photo before it can be quoted? | diagnosis | per RFQ | the customer | Dispatching an unquotable RFQ produces silence that looks like supplier failure |
| O14 | Is any supplier-identifying or customer-identifying detail leaking into the RFQ text? | gate | per RFQ | privacy review | Anonymity is the product; one leak is the whole proposition |
| O15 | Is the customer asking a question the FAQ already answers? | diagnosis | per question | the customer | Escalating an answered question wastes the department's only real capacity |
| O16 | Which of the 484 FAQ rows answers this, and is it approved and public? | craft | per question | the customer | Quoting an `internal` FAQ to a customer leaks commercial terms |
| O17 | Has this customer stalled mid-registration, and for how long? | forecast | daily | this seat | A stalled registration is the cheapest customer we will ever recover |
| O18 | Is the customer within `SLA-CUSTOMER-ONBOARD` (30 minutes when inputs are complete)? | gate | per registration | `sla_watch_hourly` | Breaching the onboarding SLA on the first interaction sets the whole relationship |
| O19 | Do we chase a customer for missing information, and when? | sequencing | per incomplete RFQ | this seat | `SLA-CUSTOMER-INPUT` is 24 hours; chasing at hour 2 is harassment |
| O20 | What do we tell a customer whose RFQ received zero quotes? | craft | per empty RFQ | the customer | "No suppliers were interested" is both untrue and unrecoverable |
| O21 | Should this customer be told about the 3 % reveal fee now or at reveal? | sequencing | per journey | the customer | A fee discovered at the payment step is a trust failure |
| O22 | Does this customer understand that quoting is blind? | craft | per registration | the customer | The `anonymity` response template exists and has been used 0 times |
| O23 | Is the welcome email deliverable to this address at all? | gate | per registration | `channel_specialist` | 37 suppressions and 4 block patterns exist for exactly this reason |
| O24 | Is this registration inside a rehearsal window (a fixture, not a person)? | gate | per registration | this seat | Two of the three `customer_welcome` rows are `@example.invalid` fixtures |
| O25 | Has the customer's first RFQ actually been dispatched, and to how many suppliers? | diagnosis | per RFQ | the customer | `match_max_fanout = 5`; a customer who thinks 50 suppliers saw it will be disappointed by 3 quotes |
| O26 | Is the customer's industry recorded, and does it matter for routing? | allocation | per registration | data_intel | `industry=null` on the only customer; category routing loses a signal |
| O27 | Does the customer need a human being right now? | escalation | per interaction | the customer | The published direct line exists; refusing to give it is worse than any script |
| O28 | Is this the customer's second RFQ — do we still call this onboarding? | sequencing | per RFQ | `cs_retention` | Onboarding a returning customer wastes their time and ours |
| O29 | What does "activation" mean for this customer, and have they reached it? | diagnosis | per customer | the CEO | `customers_active` is measured as a distinct `customer_id` in `inquiries` in 30 days — registering is not activating |
| O30 | Is the registration funnel leaking, and at which of the 8 steps? | diagnosis | weekly | `growth` | Blaming acquisition for an onboarding leak |
| O31 | Does this customer need identity verification beyond email? | gate | per registration | fraud & risk | `SLA-IDENTITY-VERIFY` is 5 minutes; a slow verification is an abandoned registration |
| O32 | Is the onboarding sequence itself missing a step the workflow defines? | diagnosis | monthly | this seat | The workflow has 8 steps; the estate currently executes some of them nowhere |

### 2. Domain logic

**M1 — Onboarding completeness vector.** Per customer, six booleans read directly from `customers`:
`email_verified`, `phone_verified`, `tos_accepted_at is not null`, `wa_optin`, `locale is not null`,
`industry is not null`. `completeness = count(true)/6`. For the only real customer this is **3/6**
(email verified, locale set, not banned — phone, terms and WhatsApp consent all absent). No model needed;
`fn_customer_onboarding_check` already assembles the welcome half of this.

**M2 — Welcome latency.** `queue_latency = welcome.created_at − customers.created_at`;
`send_latency = welcome.sent_at − welcome.created_at`. Measured for the one real case:
**11 h 22 min 20 s** and **1 min 30 s**. The `SLA-CUSTOMER-ONBOARD` target is 30 minutes. The outbox is
fast; the *trigger* is what missed. Inputs: `customers.created_at`, `notifications` where
`kind='customer_welcome'`.

**M3 — RFQ well-formedness score.** A weighted checklist over the inquiry record, thresholded, not judged:
category present and in the covered set (weight 3); emirate present (2); quantity or scope figure present
(2); budget or an explicit "no budget" (1); at least one attachment where the category requires drawings
(3); free-text length above a floor (1); no contact detail pattern in the free text (hard gate — email,
phone or URL regex → refuse and strip). Dispatch threshold and the per-category attachment requirement are
stored in `category_reqs` (an edge function of that name exists). **Unmeasured:** there are 0 inquiries, so
neither the weights nor the threshold have ever been calibrated against an outcome.

**M4 — Category openness.** `open(category) = confirmed_suppliers(category) ≥
pricing_config.category_open_min_suppliers` (10). Inputs `supplier_capabilities`,
`supplier_capability_confirmation`. This is the single most important pre-dispatch gate and it is
arithmetic. **Unmeasured here:** the current per-category confirmed counts belong to `supply`; this seat
reads them, never computes them.

**M5 — Missing-information sequencing.** Ask for at most the *minimum sufficient* set: order the missing
fields by M3 weight descending, take the top 3, ask once. Then wait `SLA-CUSTOMER-INPUT` (24 h) before one
reminder, then expire or continue by policy. All three parameters are stored, none inferred.

**M6 — FAQ resolution.** `company_faq` = 484 rows, 477 with `embedding_gte`. Resolution is: lexical
overlap on `question` + `tags`, then `gte` cosine, then a hard filter on `status='approved'` and the
audience gate — a customer may only be shown rows with `public=true` and `audience ∈ {all, customer}`,
which is **130 rows** (105 + 25). Below the similarity floor, refuse and hand to `cs_support`.
**This is the model-free path and it already exists in the estate.**

**M7 — Stall detection.** `stalled = customers.created_at < now() − 48 h AND no inquiries row`. A
deterministic daily sweep, no model. The only real customer registered 2026-09-06 07:38 UTC and has no
inquiry, so this becomes true at **2026-09-08 07:38 UTC** — not yet, as of the 2026-09-07 08:02 UTC
measurement. Nothing in the estate runs this sweep today.

### 3. Reasoning procedures

**O01/O18 — did the welcome land, inside SLA.**
1. Evidence: the `customers` row; the latest `notifications` row with `kind='customer_welcome'` and a
   matching lowercase email.
2. Not found → the honest verdict is "NOT QUEUED", with the repair named:
   `public.fn_customer_welcome(id, true)`. `fn_customer_onboarding_check` already emits exactly this string.
3. Found and `sent_at` set → compute M2 against the 30-minute target and report both latencies separately.
   Never collapse them: an 11-hour trigger delay and a 90-second outbox are different failures with
   different owners.
4. Found and `status='skipped'` → read `last_error`. If it names a reserved domain, this is a fixture, not
   a customer; say so and stop.
5. Refuse to declare "onboarding complete" on the strength of a welcome email alone — M1 is the verdict.

**O07/O08/O13 — is the first RFQ dispatchable.**
1. Run M3. Any hard gate fail (contact detail in free text, category out of scope, value below AED 500) →
   stop, explain, and offer the specific correction. Never dispatch and repair afterwards.
2. Run M4 for the category. Closed category → do **not** tell the customer "no suppliers were interested".
   Tell them the category is still being opened, give the honest expectation, and raise a coverage task to
   `supply`. This is the difference between a recoverable and an unrecoverable first impression.
3. Missing fields → M5. One request, at most three items, then the 24-hour clock.
4. Dispatch decision is the marketplace's (`route_inquiry`, `match_relevance_floor = 35`,
   `match_max_fanout = 5`), not this seat's. This seat's output is "well-formed / not well-formed" plus the
   reason.

**O15/O16 — answer or escalate.**
1. Run M6 with the customer audience filter.
2. Above floor → compose from the FAQ answer verbatim plus a stored framing sentence. Cite the FAQ id.
3. Below floor → refuse, name the two nearest FAQs and their scores, and hand to `cs_support`.
4. Never paraphrase an approved FAQ. The approval is on the exact text.

**O03/O05 — consent and terms.**
1. `tos_accepted_at is null` → the customer is on no version. Record the gap, route
   `terms_not_accepted` to `general_counsel` (`allowed_to_email=false` — never the founder), and continue
   serving. Do not use it to withhold service; do not quote `customer-terms` as binding on them.
2. `wa_optin=false` or `phone_verified=false` → the phone and WhatsApp channels are **closed** for this
   person. Record it as a channel constraint on the customer record, not as a to-do to work around.

**O30 — where is the funnel leaking.**
Walk the 8 `customer_registration` steps in order and, for each, name the table that would prove it
happened: #1 `customers` row; #2 `customers.phone_verified`; #3 `tos_accepted_at`/`tos_version`/`tos_ip`;
#4 a screening record; #5 `wa_optin`; #6 an `inquiries` row; #7 the customer KPI rows; #8 an approved
`messaging_template` for the event. Report the first step with no evidence. Today, on n=1, steps 2, 3 and 5
have no evidence and step 8 has **no approved welcome template of any kind**.

### 4. Judgement rules

1. Free text containing an email, phone number or URL → strip and refuse to dispatch until corrected.
   **Even when the customer insists.** Reason: anonymity until paid reveal is the product.
2. Category not covered (F&B, or anything priced only by an on-site visit) → refuse at registration, with
   the reason. Reason: a dispatched impossible RFQ costs supplier trust and produces a guaranteed complaint.
3. Job value below AED 500 → refuse. Reason: the published minimum.
4. Category closed under M4 → never dispatch, never blame suppliers, always raise the coverage task.
   **Even when the customer is waiting and dispatching would look responsive.**
5. Never promise a quote count, a price, or a response time. Reason: `forbidden_decisions` says "promising
   quotation outcomes", and the marketplace has produced 0 quotes to date, so any number is invention.
6. Welcome not queued within 30 minutes of registration → this is an SLA breach, report it as one, and run
   the named repair. Do not report the send latency as if it were the whole latency.
7. Recipient domain matches an `email_block_pattern` or sits in `email_suppressions` → do not attempt the
   send; mark the customer unreachable by email and escalate the channel problem.
8. A registration at `@example.invalid` or named `ZZ DEMO` is a fixture. Never count it in a funnel metric.
   **Even though it inflates the number.**
9. Ask for at most three missing items in one message. Reason: M5; abandonment rises with each field.
10. `tos_accepted_at is null` is a legal gap, not a service gap. Route it; never make the customer feel it.
11. Never quote an `internal` FAQ row to a customer. Reason: 304 of the 484 rows are internal and include
    commercial terms.
12. If the customer asks for a human, give the published direct line immediately. Reason: it is on the
    public contact page; withholding it converts a question into a complaint.
13. A second RFQ from the same customer is retention's, not onboarding's. Reason: role boundary, and a
    repeated onboarding sequence reads as an organisation that does not know its own customer.
14. Never declare a customer "activated" on registration. Reason: `customers_active` is measured from
    `inquiries`; registration is step 1 of 8.

### 5. Technical knowledge

- `customers` and every column that gates a channel or a promise: `email_verified`, `phone_verified`,
  `tos_accepted_at`, `tos_version`, `tos_ip`, `wa_optin`, `locale`, `industry`, `banned`, `chat_strikes`,
  `signed_terms_url`.
- `fn_customer_welcome(customer_id, send)`, `fn_customer_welcome_trg`, `z55_customer_welcome`,
  `fn_customer_onboarding_check(step_run_id)` — including its exact repair string.
- `notifications` (`kind`, `status`, `attempts`, `last_error`, `channel`) and `send_outbox`.
- `company_faq` (484 rows, `status`, `audience`, `public`, `embedding_gte`) and `kb_embed` — free,
  in-region `gte` embedding, the only retrieval this seat needs.
- The registration surfaces: edge functions `customer_api`, `customer_portal`, `login_otp`, `mobile_otp`,
  `voice_otp`, `auth_api`, `contact_submit`.
- The RFQ surfaces: `inquiry_intake`, `inquiry_parse`, `inquiry_dedup_check`, `category_reqs`,
  `route_inquiry`, and `decision_policy.match_relevance_floor` (35) / `match_max_fanout` (5).
- `phase_b_sla_policy` rows `SLA-CUSTOMER-ONBOARD` (30 min), `SLA-IDENTITY-VERIFY` (5 min),
  `SLA-CUSTOMER-INPUT` (24 h), `SLA-INQUIRY-FIRST-RESPONSE` (5 min).
- `decision_policy.demo_rehearsal_active` and the `@example.invalid` / `ZZ DEMO` fixture convention.
- **What must be stored so this seat never asks anyone**: the per-category mandatory-field and attachment
  matrix (partly in `category_reqs`); the covered/not-covered category list as a table (**today it lives
  only in `site_assistant`'s hard-coded FACTS strings and in `company_faq` prose — it does not exist as a
  table**); the minimum job value AED 500 (same problem — prose, not a column).

### 6. Academic knowledge

| framework | why | lawful primary source |
|---|---|---|
| Service-desk front-line standard | The seat's rank-1 certification | HDI published **HDI-CSR** certification standard and exam blueprint (free, thinkhdi.com) |
| Customer-success onboarding and time-to-value | The seat's rank-2 certification | SuccessCOACHING published **CCSM** syllabus outline (free) |
| Form design and abandonment | M5's "at most three items" | Nielsen Norman Group public research articles; the W3C **WCAG 2.2** success criteria on labels, errors and help (free, w3.org) |
| Progressive disclosure and minimum-sufficient questioning | O08 | Published HCI literature; the estate's own `02_MINIMUM_SUFFICIENT_QUESTION_POLICY_V3.yaml` (already in `agent_knowledge`, currently `quarantined`) |
| RFQ / tender document completeness | M3's weights | **FIDIC** published guidance summaries; UAE Federal Procurement Regulations (Cabinet Decision) via the official portal; ICC published model tender terms |
| Bilingual EN/AR service expectations | O06 | UAE Government official bilingual service standards (u.ae); the UAE Government Services Handbook (free) |
| Identity verification proportionality | O31 | UAE Central Bank AML/KYC published guidance; **Federal Decree-Law No. 45 of 2021 (PDPL)** on data minimisation |
| Email deliverability at first contact | O23 | **RFC 7208 (SPF)**, **RFC 6376 (DKIM)**, **RFC 7489 (DMARC)**, **RFC 8058** (one-click unsubscribe); M3AAWG published Best Common Practices |
| Consumer information duties before a fee | O21 | **Federal Law No. 15 of 2020** and **Cabinet Decision No. 66 of 2023** on pre-contract disclosure |

**Certifications held** (`role_certification`): HDI-CSR (HDI, pass 75 %, rank 1) — Service Desk Role and
Responsibilities; Customer Service Skills; Communication Skills; Problem Solving and Troubleshooting;
Incident Management Process; Documentation and Escalation. CCSM (SuccessCOACHING, pass 80 %, rank 2) —
Customer Success Fundamentals; Onboarding and Adoption; Customer Health Scoring; Escalation and Risk
Management; Renewals Retention and Churn; Expansion and Advocacy.
**Syllabus areas failed: does not exist.** `certification_exam_result` holds no row for `cs_onboarding`;
it has never sat either exam. `org_onboarding` holds no row for this seat either.

### 7. Corporate knowledge

- **The one real customer**, `e0dee407-…`, registered 2026-09-06 07:38:12 UTC. Email verified; phone not;
  no terms acceptance; no WhatsApp consent; English; no industry. Welcome sent 2026-09-06 19:02:02 UTC.
  Zero inquiries since. This customer is the entire live population of this seat's job.
- **Pricing the seat must state correctly**: posting and comparing quotes is free for the customer; 3 %
  applies only at reveal; supplier registration is free until 31 July 2027 and the first 1,000 suppliers
  never pay (`pricing_config`, `response_template.pricing_model`).
- **Coverage**: all seven emirates; all trades and product categories quotable from specifications,
  drawings or photos; **not** F&B and **not** services priced only by an on-site visit; minimum job value
  AED 500. Source today: `site_assistant`'s FACTS strings and `company_faq`. **As a queryable table: does
  not exist.**
- **Anonymity**: identities hidden until a paid reveal; suppliers never see each other's quotes
  (`response_template.anonymity`, used 0 times).
- **The workflow it owns**: `customer_registration` steps 1, 2 and 5 sit with `Customer Support Specialist`
  in the stored definition, step 3 with `Compliance Manager`, step 4 with `Fraud & Risk Analyst`, step 6
  with the director. `rfq_handling` step 1 — "Registration and initial guidance" — is this seat's,
  by `actor_role='customer_onboarding'`.
- **Who it hands to**: `customer_success_director` only. It escalates to the same, then `chief_of_staff`.
- **History**: the department's onboarding KPI has measured the notifications outbox since 26 Jul 2026 and
  read 59.44 % at 2026-09-07 03:30 UTC. This seat's `improvement_plan` records a departmental root cause of
  "capacity or conversion shortfall: attainment 49.2 %" — an aggregate that was never about this seat.

### 8. One-year plan

**Objective.** Every registered customer reaches a well-formed first RFQ, or is told honestly and quickly
why they cannot.

**Metrics owned.**
1. *Welcome-inside-SLA* — welcomes queued within 30 minutes of registration ÷ registrations. Measured
   today on n=1: **0 %** (11 h 22 min). Directly fixable.
2. *Registration → first RFQ conversion within 7 days.* Today **0 %** (1 registration, 0 inquiries).
3. *First-RFQ well-formedness* — RFQs passing M3 on first submission. **Unmeasurable: 0 inquiries.**

**Quarterly milestones.**
- *Q1*: the covered-category list and the AED 500 minimum exist as tables, not prose; the welcome trigger
  fires at registration, not 11 hours later; the M3 checklist exists as a stored, versioned rule set; the
  registration funnel's 8 steps each have a named evidence table.
- *Q2*: first-RFQ well-formedness measured on a real base; M3 weights calibrated against whether the RFQ
  actually drew quotes; the HDI-CSR exam is sat and its gaps written to `certification_knowledge_gap`.
- *Q3*: registration → first RFQ conversion reported weekly; the "zero quotes" message path proven against
  a real closed category.
- *Q4*: onboarding hand-off to `cs_retention` at second RFQ is automatic and measured.

**Capacity check.** `max_open_tasks = 50`. Onboarding one customer is, in mechanical terms, one welcome,
one completeness check, and at most two clarification exchanges. At the AED 1,000,000 target and a 3 %
rate, the year needs AED 33,333,333 of revealed quote value; the number of *customers* behind that depends
on average quote value and reveals per customer, **both unmeasured (0 quotes, 0 transactions)**. Even at
the pessimistic end — say 1,667 reveals from 1,667 distinct customers — that is under 7 onboardings per
working day, which one deterministic sequence handles without strain. **Capacity is not the constraint;
arrivals are.**

**Dependencies.** `growth` for registrations at all; `supply` for open categories (M4); `product_eng` for
the welcome trigger timing and for the category/minimum-value tables; `channel_specialist` for a
deliverable welcome and an approved template.

**Is the slice achievable?** The `customers_registered` objective (5,000 by 2027-08-31, actual **1**) is
**not achievable** and is in any case not this seat's to deliver — it acquires nobody. What this seat can
be held to, and what should replace its share of the slice, is: **100 % of registrations get a welcome
inside 30 minutes, and 100 % of first RFQs are either dispatchable or refused with a named reason.** Both
are achievable on day one and both are currently 0 %.

### 9. What this seat cannot do without a model

1. **Judging whether a free-text job description is *technically* complete** for a trade nobody has
   codified — M3 checks structure, not engineering sufficiency. Mitigation: per-category required-field
   tables; where none exists, refuse and route to the category specialist.
2. **Rewriting a customer's vague description into a good RFQ.** The seat can ask for the missing fields;
   it cannot author the request. Accepted: the customer writes it.
3. **Detecting an out-of-scope category expressed in words nobody anticipated** (a novel service phrased
   unusually). Mitigation: the covered-category table plus embedding similarity, then refusal.

---

## cs_support — Customer Support Specialist

`org_agents.responsibilities`: "Handles inbound support and complaints within SLA."
`org_role.customer_support`, `authority_level='execute_low'`, `budget_limit=0`, `runtime_enabled=true`.
Owns: answering a customer question from validated knowledge; raising an internal handoff. Forbidden:
legal or regulatory conclusions; refunds; exposing another party's identity. Hands off to
`customer_success_director`, `rfq_success`, `trust_and_safety_manager`.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|----|----------------------|------|-----------|----------|---------------------------|
| S01 | Can I answer this from approved knowledge, or must I refuse? | gate | every inbound | the customer | A confident wrong answer from a department with no case history is fabrication |
| S02 | Which of the 130 customer-visible FAQ rows answers this? | craft | every inbound | the customer | Quoting an internal row leaks commercial terms |
| S03 | Is this a question, a complaint, or a refund request? | diagnosis | every inbound | the customer | The classification decides which of three workflows runs |
| S04 | What is this case's severity band? | diagnosis | per case | this seat | Severity sets the SLA, the owner and whether legal is mandatory |
| S05 | Does this text hit a `legal_triggers` phrase? | gate | every inbound | `general_counsel` | Answering a liability question creates the liability |
| S06 | Is the category `sensitive` (fire, security, electrical, structural, gas, lifts, medical)? | gate | per case | this seat | Low-confidence output on a life-safety trade is the worst failure available |
| S07 | Have we acknowledged inside `SLA-SUPPORT-ACK` (15 minutes)? | gate | per case | `sla_watch_hourly` | The acknowledgement is the promise; the resolution is the work |
| S08 | Will this resolve inside `SLA-SUPPORT-RESOLVE` (4 business hours)? | forecast | per case | this seat | Silence past the target is what turns a case into a complaint |
| S09 | Which specialist does this hand to? | allocation | per case | this seat | Handing to the wrong seat restarts the clock |
| S10 | Is this the same issue as an open case? | diagnosis | per inbound | this seat | Two cases on one issue produce two different answers |
| S11 | Is the customer asking about a reveal they have already paid for? | diagnosis | per inbound | this seat | This is the ladder's territory and must not be answered ad hoc |
| S12 | Is the customer asking us to reveal a supplier's identity early? | gate | per inbound | the customer | The single hardest "no" this seat gives, and the one it must never soften |
| S13 | Is the customer asking what another supplier quoted? | gate | per inbound | the customer | Blind quoting is a supplier-side promise; breaking it loses the supply base |
| S14 | Is this an abusive or threatening message? | gate | per inbound | this seat | No line means the seat absorbs abuse indefinitely |
| S15 | Is this RFQ suspected fake or fraudulent? | escalation | per suspicion | trust & safety | Both false positives and false negatives are expensive |
| S16 | Is this a data-subject request under PDPL? | escalation | rare | `general_counsel` | A statutory clock starts on receipt, and it is not ours to run |
| S17 | Is the customer disputing the reveal charge itself? | sequencing | per dispute | this seat | A charge dispute is a chargeback in waiting; it goes to the refund path |
| S18 | What do we say when the supplier's revealed details are wrong or dead? | craft | per case | the customer | This is a platform fault; treating it as supplier silence charges an innocent party |
| S19 | The buyer says the quote is too expensive — is that a support case? | diagnosis | per case | the customer | Negotiating price is not this platform's role |
| S20 | The supplier responded, then went silent mid-negotiation — what now? | sequencing | per case | the customer | Outside the ladder (the supplier *did* respond); needs its own path |
| S21 | Does this complaint name a specific supplier, and should that be recorded? | allocation | per complaint | supply | Un-recorded complaints leave a bad supplier in rotation |
| S22 | Is this complaint a symptom of something we have seen before? | diagnosis | weekly | this seat | Fixing five symptoms instead of one cause |
| S23 | Which response template fits, and is it active? | craft | per reply | this seat | 11 of the 13 templates have never been used |
| S24 | Is this the customer's language? | gate | per reply | `channel_specialist` | Replying in the wrong language is a non-answer |
| S25 | Is the channel the customer used one we may reply on? | gate | per reply | `channel_specialist` | Replying on WhatsApp without opt-in is a consent breach |
| S26 | Has the customer already been told something contradictory? | gate | per reply | this seat | Two answers to one question is worse than a slow answer |
| S27 | Do we owe this customer an update even though nothing has changed? | sequencing | per open case | this seat | Silence during a wait is the most common cause of escalation |
| S28 | Is the answer we are about to give sourced from a validated record? | gate | every reply | this seat | All 11 `agent_knowledge` rows for this seat are quarantined or unsourced |
| S29 | Is the customer entitled to what they are asking for under `customer-terms` v5? | diagnosis | per claim | `general_counsel` | Reading terms is fine; concluding on them is forbidden |
| S30 | Is this case actually about a supplier's obligation under `supplier-agreement` v8? | allocation | per case | supply | Answering for the supply side creates commitments we cannot keep |
| S31 | Does this need the founder? | gate | per case | this seat | Almost never: only a refund does |
| S32 | Should this case be closed, or is "closed" hiding an escalation? | gate | per closure | QA | Counting escalations as resolutions is the classic metric fraud |
| S33 | Is our answer inside the published `complaints-policy` v1.1 process? | gate | per complaint | `general_counsel` | A published process we do not follow is a legal exposure |
| S34 | What does the customer get told about timing? | craft | per case | the customer | Every unmet timing promise costs more than the original problem |
| S35 | Is the FAQ wrong, and should this answer become a new FAQ? | craft | per novel question | knowledge | 484 FAQ rows exist; none was written from a real case |
| S36 | Is this inbound actually from a supplier, not a customer? | gate | per inbound | this seat | Supplier-side facts are commercially sensitive and audience-gated |
| S37 | Are we inside UAE working hours, and does the answer change? | sequencing | continuous | this seat | Sun–Thu 9–6 GST is published on the contact page; the platform is 24/7 |
| S38 | Is a public holiday or Ramadan changing the response expectation? | sequencing | seasonal | this seat | The holiday calendar does not exist in this estate |
| S39 | Has this customer had three strikes? | gate | per case | trust & safety | `customers.chat_strikes` exists and nothing populates it |
| S40 | Is the case load above what this seat can carry? | gate | daily | the director | `max_open_tasks = 50` |
| S41 | What is the honest deflection rate, and is it being gamed? | diagnosis | monthly | the director | A deflection target rewards not answering |
| S42 | Is the knowledge this seat retrieved stale? | gate | every reply | knowledge | `v_knowledge_review_due` exists for this reason |

### 2. Domain logic

**M1 — Intent classification without a model.** Two stages. (a) Lexical: token overlap against the
taxonomy rows above, against `response_template.intent` (13 stored intents: anonymity, apology,
appointment, complaint, delivery, follow_up, greeting, opening_hours, location, payment, pricing, shipping,
thanks) and against `company_faq.question` + `tags`. (b) Semantic: `gte` cosine against
`company_faq.embedding_gte` (477 of 484 rows embedded) and against embeddings of the taxonomy rows.
Decision: take the top match only if its score clears a floor **and** its margin over the runner-up clears
a separation floor. **This margin rule is the lesson of this seat's own exam**: in the semantic HDI-SCA
run, 48 of 80 answer slots abstained with scores of 0.72–0.98 but margins as low as 0.0007 — high
similarity with no separation. A floor on score alone would have produced 48 confident wrong answers.
Both floors must be stored parameters, tuned against a labelled set. **Unmeasured:** no labelled set of
real customer questions exists (0 cases), so the floors are currently untuned.

**M2 — Severity.** As `followup` M5, computed here first:
`3·money + 3·safety_or_compliance + 2·legal_trigger + 2·repeat + 1·sla_breached + 1·public_channel`.
`safety_or_compliance` reads `decision_policy.sensitive_categories`; `legal_trigger` reads
`decision_policy.legal_triggers`. Bands: ≥8 critical, 5–7 high, 3–4 normal, ≤2 low.

**M3 — SLA clock.** `ack_due = opened_at + 15 min` (`SLA-SUPPORT-ACK`);
`resolve_due = opened_at + 4 business hours` (`SLA-SUPPORT-RESOLVE`); for a refund-shaped case,
`triage_due = opened_at + 4 business hours` (`SLA-REFUND-TRIAGE`). Business hours from the Dubai working
week. **Unmeasured:** there is no case table to hang `opened_at` on — the estate has `inbound_messages`
(4 rows), `contact_messages` (0 rows), `wa_messages` (12 rows, all founder traffic) and `feedback`
(0 rows), none of which is a case.

**M4 — Audience gate.** Facts are partitioned: `company_faq.audience ∈ {all, customer, supplier,
internal}` and `public ∈ {true,false}`. A customer may be shown only `approved AND public AND audience ∈
{all, customer}` — **130 rows**. A supplier only `approved AND public AND audience ∈ {all, supplier}` —
**126 rows**. The 304 `internal` rows are never quotable. Audience is determined by the path and the
wording rules already implemented in `site_assistant` (`audienceFromPath`, `SUP_RE`, `CUS_RE`), which are
pure regex and need no model.

**M5 — Contradiction check.** Before replying, retrieve every prior reply on the same
`(customer, subject)` and compare the *structured claim slots* (amount, date, entitlement yes/no, next
action). Any slot differing from a prior answer → refuse to send and escalate. **Unmeasured:** requires the
case table.

**M6 — Honest deflection.** `deflection = answered_from_FAQ ÷ total_inbound`, reported alongside
`reopen_rate` and `escalation_after_deflection`. A deflection number without those two is a suppression
target, not a service metric. This pairing is stored guidance in `ops_knowledge`
(`ops-customer_experience-deep-266421608c822aaedae5`, "KPI: deflection rate measured honestly, not as a
suppression target").

**M7 — Staleness.** A record is usable if `validation_status='validated'` and
`review_due > now()`. **Today no record this seat holds passes**: all 11 `agent_knowledge` rows are
`quarantined` or `unsourced`, and all 95 CX `ops_knowledge` rows carry `deterministic=false`. The 484
`company_faq` rows are `approved` and are the only clean source.

### 3. Reasoning procedures

**S01/S02 — answer or refuse.**
1. Determine audience (M4, regex only).
2. Run M1. If no type clears both the score floor and the margin floor → **refuse**: name the two nearest
   candidates and their scores, give the published human contact line, and open a task. This is the correct
   outcome, not a failure.
3. Above both floors and the match is a `company_faq` row → reply with the approved answer **verbatim**,
   wrapped in a stored framing sentence, citing the FAQ id.
4. Above both floors and the match is a taxonomy row → run that row's procedure.
5. Before sending, run M5 (contradiction) and M7 (staleness). Either fails → hold and escalate.

**S03/S04 — classify and set the clock.**
1. Money asked back + a paid reveal exists → refund path (`followup` F06). Do not answer the money question.
2. Otherwise, complaint if the text hits the complaint intent or M2 ≥ 3; else question.
3. Compute M2. Critical or `sensitive_categories` hit → acknowledge immediately, escalate before
   investigating, and do not compose a substantive answer.
4. Start M3's clocks. Acknowledge first, always, inside 15 minutes — the acknowledgement is not the answer
   and must not wait for one.

**S05/S16/S29 — the legal boundary.**
1. Match against the 10 stored `legal_triggers`. Any hit → stop composing.
2. Route to `general_counsel` via the `legal_flag` kind (`founder_mail_policy.allowed_to_email=false` —
   he never sees it).
3. The seat may quote `customer-terms` v5 or `supplier-agreement` v8 **verbatim with a version and clause
   reference**. It may never state what they mean for this case. That distinction is the whole rule.
4. A PDPL data-subject request routes as `pdpl_request` to `general_counsel` on receipt, with the receipt
   timestamp recorded, because the statutory clock starts then.

**S12/S13 — the two hard refusals.**
Identity before paid reveal, and another supplier's quote. Both are answered from the stored `anonymity`
template plus a fixed explanation of why the rule exists (it is what makes suppliers quote at all). No
escalation path exists that produces a different answer, so the seat should not offer one. If the customer
presses a third time, hand to the director — not because the answer changes, but because a third press is
a signal about the customer.

**S14/S39 — abuse.**
1. Match against a stored pattern list (threats, slurs, doxxing). One hit → one stored boundary notice,
   increment `customers.chat_strikes`.
2. Second hit in the same case → hand to `trust_and_safety_manager`.
3. Never argue, never match tone, never ban. Banning is not this seat's decision.
4. **`chat_strikes` exists as a column and nothing writes to it today** — this procedure is unimplementable
   until something does.

**S32/S41 — closing honestly.**
A case is `resolved` only if the customer's original question has an answer *and* no handoff is open.
A case with an open handoff is `escalated`, never `resolved`. Deflection is reported only with reopen rate
and post-deflection escalation rate beside it.

### 4. Judgement rules

1. Score above floor but margin below the separation floor → **abstain**. Reason: this seat's own
   HDI-SCA semantic run produced 0.9631 with a margin of 0.0007. High similarity is not knowledge.
2. Any `legal_triggers` hit → never answer, always route. **Even when the answer is obviously "yes".**
3. Any `sensitive_categories` hit with a below-threshold match → escalate, do not answer.
   Reason: fire, gas, structural and medical are where a wrong answer hurts a person.
4. Identity before paid reveal: refuse, always, at any seniority, for any reason. Reason: it is the product.
5. Another supplier's quoted price: refuse, always. Reason: blind quoting is a promise to the supply side.
6. Money asked back → this seat does not answer the money question at all; it classifies and hands over.
   Reason: `forbidden_decisions` includes refunds and `budget_limit = 0`.
7. Acknowledge inside 15 minutes even with nothing to say. Reason: `SLA-SUPPORT-ACK`; silence is the
   escalation trigger, not delay.
8. Never send a reply that contradicts a prior reply on the same subject. Hold and escalate instead.
   **Even when the new answer is the correct one** — the customer needs one voice, and a correction must be
   an explicit correction.
9. A case with an open handoff is never counted as resolved. **Even though it improves the number.**
10. Never quote an `internal` FAQ row, and never quote supplier-side commercial facts to a customer.
    Reason: 304 internal rows and the audience gate exist precisely to prevent this.
11. Never state a supplier response time, quote count or price. Reason: 0 quotes have ever been produced.
12. Reply only on a channel the customer is contactable on: email always; WhatsApp only with `wa_optin`
    and `phone_verified`. Reason: consent, and the only real customer has neither.
13. If the answer would come from a `quarantined` or `unsourced` record, say so in the answer or do not
    send it. Reason: 11 of 11 records this seat holds are in that state.
14. Third refusal on the same demand from the same customer → escalate the *relationship*, not the answer.
15. Give the published human contact line whenever the seat refuses. Reason: a refusal without a route is
    an abandonment.
16. Never report a deflection rate alone. Reason: it is a suppression target the moment it stands by itself.

### 5. Technical knowledge

- The retrieval stack: `company_faq` (484 rows / 477 embedded), `kb_embed` (free, in-region `gte`),
  `kb_retrieve`, `kb_search`, `ops_knowledge.embedding_gte`, `agent_knowledge.embedding_gte`.
- `response_template` (13 rows: key, channel, intent, body, active, used_count) — the composition source.
- The inbound surfaces: `site_assistant` (public widget; routes through `ai_gateway` with `try_faq=true`,
  so a FAQ hit costs **no model call**), `wa_inbound` (no LLM reference), `inbound_email`,
  `resend_inbound`, `resend_webhook`, `contact_submit`, `messages_api`. `support_ai` is a **retired 410
  stub** since 22 Jul 2026.
- `email_triage` and `intent_router` **do** reference an LLM and must not be on this seat's critical path.
- The policy tables: `decision_policy.legal_triggers` (10 phrases), `.sensitive_categories` (7),
  `.confidence_min` (0.6), `.action_autonomy`, `founder_mail_policy`.
- The SLA rows: `SLA-SUPPORT-ACK` 15 min, `SLA-SUPPORT-RESOLVE` 4 business hours, `SLA-REFUND-TRIAGE`
  4 business hours, `SLA-INQUIRY-FIRST-RESPONSE` 5 min.
- The workflow: `complaint`, 10 steps; this seat holds #1, #2, #3 and #8. Step #5 is Legal (gate `review`),
  #6/#7 are the director (gate `dept_head`), #9 is QA, #10 is the supplier-intelligence analyst.
- Published documents it quotes from, never interprets: `customer-terms` v5, `supplier-agreement` v8,
  `refund-policy` v1.3, `complaints-policy` v1.1, `privacy` v1.2 — all effective 2026-09-06.
- **What must be stored so this seat can act alone**: a **support case table** (does not exist — this is
  the department's largest structural gap); the abuse pattern list (does not exist); the labelled question
  set that tunes M1's two floors (does not exist); the UAE public-holiday calendar (does not exist).

### 6. Academic knowledge

| framework | why | lawful primary source |
|---|---|---|
| Support-centre analyst standard (incident, problem, service level, knowledge) | The seat's rank-1 certification | HDI published **HDI-SCA** certification standard and exam blueprint (free, thinkhdi.com) |
| Front-line service standard | Rank-2 certification | HDI published **HDI-CSR** blueprint (free) |
| ITSM incident vs problem management | S22 — symptom vs cause | ITIL 4 Foundation **published syllabus outline** (free from PeopleCert/AXELOS); the ITIL study text itself is copyrighted and must be licensed, not ingested |
| Knowledge-Centered Service (KCS) | S35 — turning a case into a FAQ | Consortium for Service Innovation published **KCS v6 Practices Guide** (freely published by the consortium) |
| Complaints handling | S33 | **ISO 10002** (licensed copy; free abstract) and the estate's own `complaints-policy` v1.1 |
| Service recovery paradox and its limits | S27, S34 | Published journal literature (Smith, Bolton & Wagner); use the published findings, not a textbook |
| Information retrieval: precision, recall, and the margin/abstention trade-off | M1's two floors — the direct lesson of this seat's own exam | TREC published evaluation methodology (NIST, free); the published literature on selective prediction and reject options |
| Text classification without a model | M1 | Published BM25 / Okapi specification; the `pgvector` and Postgres `tsvector` documentation (open) |
| UAE consumer protection and complaint duties | S29, S33 | **Federal Law No. 15 of 2020**; **Cabinet Decision No. 66 of 2023**; Ministry of Economy consumer-protection publications |
| UAE data protection | S16 | **Federal Decree-Law No. 45 of 2021 (PDPL)** |
| UAE cyber and messaging conduct | S14 | **Federal Decree-Law No. 34 of 2021** (official portal) |
| Working calendar | S37, S38 | UAE Cabinet / FAHR official public-holiday announcements |

**Certifications held**: HDI-SCA (HDI, pass 75 %, rank 1) — Support Center Overview; Incident Management;
Problem Management; Service Level Management; Knowledge Management; Customer Service Skills; Support Center
Tools and Technology. HDI-CSR (HDI, pass 75 %, rank 2) — six areas as listed for `cs_onboarding`.

**Syllabus areas failed — measured, and this is the only seat in the department with an exam result.**
Both sittings on 2026-09-07, 40 questions, pass mark 75 %:

| method | score | correct | weakest areas (correct/asked) |
|---|---|---|---|
| `lexical` | **2.50 %** | 1/40 | every area 0 except Service Delivery Methods and Technology 1/6 |
| `semantic` | **35.00 %** | 14/40 | Communication and Customer Management **1/7**; ITSM Processes and Metrics **1/6**; Problem Solving and Troubleshooting **2/6**; The Support Center Role and Value **2/5**; Security and Information Management **2/4**; Service Delivery Methods and Technology 3/6; Strategic Framework 3/6 |

Across the 80 answer slots, **48 were abstentions**. Two findings the founder should see: (1) the seat is
far below its own pass mark in every area, worst in the two that are most of its job — communication and
ITSM process/metrics; (2) **the exam's area names do not match the syllabus stored against the
certification.** `role_certification` lists "Incident Management", "Problem Management", "Service Level
Management", "Knowledge Management"; the exam asked "Strategic Framework", "Service Delivery Methods and
Technology", "Communication and Customer Management", "Security and Information Management". Remediation
targeted at the stored areas will not move the measured score. `certification_knowledge_gap` holds **no
rows** for this seat, so nothing has been fed back.

### 7. Corporate knowledge

- **Refunds are not this seat's.** `budget_limit = 0`, `forbidden_decisions` names refunds, and
  `employee_authority` gives it `advisory` at threshold 0 on `refund_within_window`. Its job on a money
  question is classification and handover, in that order.
- **Only refunds reach the founder.** `customer_escalation` is `allowed_to_email=false` with
  `owner_role='customer_success_director'`.
- **The two absolute refusals** (identity before paid reveal; another supplier's quote) and why they exist.
- **The published direct line** on the contact page: +971 50 931 9355 (call or WhatsApp, Sun–Thu 9am–6pm
  GST) and management@quotesdone.com. This is public and must be given whenever the seat refuses.
- **Operator identity**: QuotesDone Technologies, Dubai DET E-Trader Licence No. **1633275**. No VAT
  registration until the AED 375,000 threshold. Both are settled and must never be re-asked.
- **The complaint workflow's shape**: this seat opens, classifies, acknowledges and executes; QA
  investigates and traces cause; Legal reviews where a contract, licence or regulation is in scope; the
  director decides the remedy; only a refund remedy crosses to the founder.
- **The 13 response templates** and the fact that 11 have never been used — this seat's composition
  vocabulary is untested against a real customer.
- **History**: `support_ai` was retired 22 Jul 2026 with 0 references and a dead model slug; the live
  assistant is `site_assistant`. The seat's KPI has measured the notifications outbox since 26 Jul 2026.
  On 2026-09-07 this seat sat the same certification twice and scored 2.50 % lexically and 35.00 %
  semantically.

### 8. One-year plan

**Objective.** Every inbound gets a correct answer or an honest refusal with a route, inside the published
SLA, from an approved source — with abstention treated as a success, not a miss.

**Metrics owned.**
1. *Acknowledgement inside 15 minutes* — target 100 %. **Unmeasurable today: no case table.**
2. *Answer accuracy on a labelled set* — target: the abstention rate falls while accuracy on non-abstained
   answers stays above 95 %. Baseline exists and is brutal: 35.00 % with 60 % abstention on the seat's own
   certification.
3. *Escalation-after-deflection rate* — the honesty guard on metric 2. **Unmeasurable today.**

**Quarterly milestones.**
- *Q1*: the support case table exists (`opened_at`, `channel`, `customer_id`, `intent`, `severity`,
  `sla_policy_id`, `acknowledged_at`, `resolved_at`, `handoff_open`); M1's two floors exist as stored
  parameters; the abstention path is wired to produce a refusal + task, not a silence;
  `certification_knowledge_gap` is populated from the 2026-09-07 results.
- *Q2*: a labelled question set of at least 200 real or fixture questions exists; the floors are tuned
  against it; HDI-SCA is re-sat and the delta reported; the abuse pattern list and `chat_strikes` writing
  path exist.
- *Q3*: acknowledgement and resolution measured from real cases; the FAQ grows from real cases (KCS loop);
  contradiction checking (M5) runs before every send.
- *Q4*: deflection reported only in its honest triple; a full audit that no `resolved` case had an open
  handoff.

**Capacity check.** `max_open_tasks = 50`, department ceiling 250. If the year produces ~1,667 reveals
(the pessimistic arithmetic in `followup` §8) and support contacts run at even 0.5 per reveal, that is
~830 cases a year — about 3.5 per working day. Mechanically trivial. **The constraint is answer quality,
not volume:** at the measured 35 % accuracy with 60 % abstention, this seat would refuse two of every three
questions and get one of the remaining three wrong. That is the number that has to move, and it moves with
the case table, the labelled set and the two floors — not with more capacity.

**Dependencies.** `product_eng` for the case table and the inbound surfaces; `data_intel` / knowledge for
the labelled set and for validating the 11 quarantined records; `general_counsel` for every legal-trigger
case; `followup` for every money question; `channel_specialist` for channel eligibility.

**Is the slice achievable?** This seat owns no revenue line. Its honest slice of the AED 1,000,000 is
**protective**: every reveal that produces a support case must not produce a refund that a better answer
would have prevented. On the current base (0 cases) that is 100 % by default and meaningless. The
achievable, meaningful commitment for the year is: **a case table, a tuned classifier with a measured
abstention rate, and a re-sat certification showing movement from 35 %.** Without those three the seat
cannot be said to be doing the job at all.

### 9. What this seat cannot do without a model

1. **Answering a question that is genuinely novel** — outside the 484 FAQs and the taxonomy. The design
   answer is refusal with a route, and that is correct behaviour, not a gap. But it does mean the seat's
   coverage is exactly the size of its stored corpus.
2. **Sentiment, sarcasm and negation in free text, especially across EN/AR.** No honest deterministic
   method. The seat must not attempt it; severity comes from M2's structural signals instead.
3. **Summarising a long thread.** Structured extraction only.
4. **Writing a new FAQ answer from a resolved case (S35).** A human or a model must author it; the seat can
   only flag that the case had no FAQ and open the task.
5. **Translating a reply into Arabic that was not pre-translated.** Every customer-facing string must exist
   in both languages as stored data, or the seat replies in the language it has and says so.

---

## cs_retention — Customer Retention Specialist

`org_agents.responsibilities`: "Monitors churn signals and drives repeat usage."
`org_role.customer_retention`, `authority_level='execute_low'`, `budget_limit=0`, `runtime_enabled=true`.
Owns: retention outreach within policy; **rating solicitation timing**. Forbidden: discounting outside
policy; contacting a customer who has opted out. Escalates to `customer_success_director`.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|----|----------------------|------|-----------|----------|---------------------------|
| R01 | Is this customer at risk of leaving? | forecast | weekly per customer | this seat | A missed save costs a whole lifetime; a false alarm costs an unwanted message |
| R02 | Which risk signal actually fired — and is it a signal or an empty table? | diagnosis | per alert | this seat | `customer_score` has 0 rows; a churn "score" today would be invention |
| R03 | Is this customer dormant, or simply new? | diagnosis | per customer | this seat | The only real customer has `total_inq = 0` and `last_activity = null` — that is *new*, not dormant |
| R04 | Do we reach out now, and on which channel? | sequencing | per at-risk customer | `channel_specialist` | Reaching out on a channel with no consent is a compliance breach, not a save |
| R05 | Exactly when do we ask for a rating? | sequencing | per reveal | this seat | The founder's ruling: **at the reveal moment**. Asking at any other time measures the wrong thing |
| R06 | Do we ask for a rating at all on a case that ended badly? | gate | per closed case | this seat | Soliciting a rating from a customer we failed is asking to be punished in public |
| R07 | Which of the six review dimensions do we ask about? | allocation | per solicitation | this seat | `reviews` has `r_communication`, `r_quality`, `r_punctuality`, `r_documentation`, `r_after_sales`, `r_compliance` and 0 rows |
| R08 | What is the repeat-reveal rate, and against which base? | diagnosis | monthly | the CEO | 0 transactions; any rate is undefined, not zero |
| R09 | Is this a win-back or a first-outcome problem? | diagnosis | per case | this seat | You cannot win back someone who never transacted |
| R10 | What retention offer is inside policy? | gate | per save attempt | `followup` | `budget_limit = 0`; any credit, waiver or discount is money and is the founder's |
| R11 | Is this offer a discount outside policy? | gate | per save attempt | `followup` | Explicitly forbidden in `org_role.forbidden_decisions` |
| R12 | Has this customer opted out of contact? | gate | every outreach | `channel_specialist` | Explicitly forbidden; also a deliverability and legal failure |
| R13 | Is the customer's silence after a reveal a churn signal or a normal gap? | diagnosis | per reveal | this seat | Chasing a normal gap is harassment; missing a real one loses the customer |
| R14 | Did the supplier the customer paid to reveal actually perform? | diagnosis | per reveal | `followup` | Retention outreach to a customer mid-refund-ladder is tone-deaf |
| R15 | Is this customer's health score moving, and in which component? | diagnosis | weekly | this seat | `customer_health` gives engagement, satisfaction, progress, service — the composite hides the cause |
| R16 | What is this customer's next best action? | allocation | per customer | this seat | A generic nudge to a specific problem is worse than silence |
| R17 | Should this customer be asked for a referral or a testimonial? | sequencing | per delighted customer | marketing | Asking too early converts a good outcome into an ask |
| R18 | Is a cohort of customers behaving differently from the rest? | diagnosis | monthly | data_intel | Cohort blindness is how a systemic regression looks like bad luck |
| R19 | Is a category producing systematically worse outcomes? | diagnosis | monthly | marketplace | Retention cannot fix a supply problem, and must not be measured as if it could |
| R20 | Is the customer's second RFQ materially different from the first? | diagnosis | per repeat | this seat | It tells us whether the first outcome was useful |
| R21 | How long is this customer's natural re-purchase cycle? | forecast | per customer | this seat | **Unmeasured — 0 transactions.** Assuming a cycle is invention |
| R22 | Is a reactivation campaign justified, and to whom? | allocation | quarterly | `followup` | A campaign to a base of 1 is not a campaign |
| R23 | Which lifecycle message does this moment call for? | allocation | per trigger | `channel_specialist` | No approved template exists for any retention moment |
| R24 | Is this outreach inside the per-recipient frequency cap? | gate | every outreach | `channel_specialist` | Frequency capping is the difference between lifecycle and spam |
| R25 | Are we contacting during Ramadan, a holiday, or outside working hours? | sequencing | seasonal | `channel_specialist` | The holiday calendar does not exist in this estate |
| R26 | Did the last outreach to this customer get a response? | diagnosis | per outreach | this seat | Repeating an ignored message is how a list dies |
| R27 | Is this customer's dissatisfaction about us or about the supplier? | diagnosis | per complaint | `cs_support` | Apologising for the wrong party teaches nothing |
| R28 | Should a supplier be recorded as the cause of a retention loss? | allocation | per loss | supply | `rv_nonresponse_refunds` and `supplier_perf` exist for this |
| R29 | Is the CSAT number we are about to report real? | gate | monthly | the founder | `csat` and `customer_retention` both carry "NO INSTRUMENT EXISTS" |
| R30 | Is a rating a complaint in disguise? | diagnosis | per review | `cs_support` | `fn_emit_customer_complaint_from_review` exists precisely for this |
| R31 | Is this seat's retention KPI measuring retention? | diagnosis | weekly | the director | It measures the notifications outbox: 59.44 % at 2026-09-07 03:30 UTC |
| R32 | What is the lifetime value of a customer here? | forecast | quarterly | finance | `customer_score.lifetime_value_aed` exists as a column with 0 rows |
| R33 | Is a win-back attempt worth its cost? | gate | per attempt | this seat | Cost is measurable (a send); value is not (0 transactions) |
| R34 | Is a customer's opt-out being honoured everywhere, not just on one channel? | gate | per opt-out | `channel_specialist` | A partial opt-out is a breach with a paper trail |

### 2. Domain logic

**M1 — Health score (live, arithmetic, no model).** The `customer_health` VIEW already computes, per
customer: `engagement`, `satisfaction`, `progress`, `service` and a composite `health` with a `risk_tier`
band, from `total_inq`, `active_inq`, `progressed_inq`, `completed_inq`, `stalled_inq`, `avg_resp_hrs`,
`avg_review`, `bad_reviews`, `disputes`, `dormant`, `strikes`, `banned`, `last_activity`. Measured today
for the only customer: `health 46.8`, `risk_tier 'medium'`, `engagement 5`, `satisfaction 70`,
`progress 50`, `service 60`, all activity counters 0. **This is the seat's real instrument and it works.**

**M2 — Churn risk: does not exist.** `customer_score` has the columns (`churn_risk`,
`lifetime_value_aed`, `last_active`, `rfqs_posted`, `rfqs_awarded`, `avg_budget_aed`,
`preferred_categories`) and **0 rows**. `fn_emit_churn_signal` fires `customer.churn_signal` when
`churn_risk >= 0.7`, so the trigger exists and can never fire because nothing populates the table. Until
something does, this seat must report the health score and say the churn model does not exist rather than
present M1 as if it were M2.

**M3 — Dormancy.** `dormant = last_activity < now() − N days` where N is a stored parameter.
**Unmeasured:** N has never been derived, because deriving it needs a re-purchase-cycle distribution and
there are 0 transactions. Rule: until N is derived from data, do not classify anyone as dormant; classify
them as `new` (`total_inq = 0`) or `active`.

**M4 — Rating solicitation timing.** The founder's standing decision is that the ask happens **at the
reveal moment**. Deterministic trigger: on `transactions.revealed_at` being set, and again — only if the
first went unanswered — once at `fn_add_working_days(revealed_at, N_followup)`. Gates before sending:
`fn_refund_state.state ∉ {chase_due, chased, final_call_due, final_call_sent}` (never ask a customer for a
rating while we are chasing the supplier they paid for), channel consent, and the frequency cap. Writes to
`reviews` with `rating` plus the six dimension columns.

**M5 — Repeat-reveal rate.** `repeat = |{customers with ≥2 transactions in 365d}| ÷ |{customers with ≥1}|`.
Today the denominator is **0**, so the rate is undefined, not 0 %. Report "undefined (no transactions)".

**M6 — Next best action, as a lookup not a judgement.** A stored decision table keyed on the customer's
state vector — `(has_registered, has_inquiry, has_quote, has_reveal, refund_state, health_band,
channel_consent, days_since_last_activity)` — mapping to exactly one action from a fixed catalogue:
`welcome_repair`, `first_rfq_guidance` (hand to `cs_onboarding`), `category_closed_explanation`,
`post_reveal_checkin`, `rating_ask`, `refund_ladder_case` (hand to `followup`), `reactivation_nudge`,
`no_action`. Every branch resolves to one row; ties resolve by a stored priority. For the only real
customer the vector is `(true, false, false, false, n/a, medium, email_only, 1)` → **`first_rfq_guidance`**,
which is `cs_onboarding`'s, not this seat's. That is the correct answer and it is arithmetic.

**M7 — Frequency cap.** `sends_to_recipient_in_window < cap`, both stored. **Does not exist as a table
today**; `org_role.communications_manager` owned "per-recipient frequency policy" and that role is retired,
its accountability moved to `followup`. This is a live gap.

**M8 — Attribution of a loss.** For a lost customer, walk back the causal chain deterministically:
was there a reveal? did `fn_refund_state` show `supplier_responded = false`? was there a refund? was there
a bad review naming a supplier? The first `true` names the owner — supply, marketplace or us. Never
attribute to "customer experience" by default.

### 3. Reasoning procedures

**R01/R02/R03 — is this customer at risk.**
1. Read `customer_health` for the composite and the four components.
2. Read `customer_score` for `churn_risk`. **Empty → say so.** Do not substitute the health score and call
   it churn risk.
3. If `total_inq = 0`, the customer is *new*, not at risk of churn — route to M6, which will hand to
   onboarding. This is the single most common misclassification available to this seat and the estate's
   only live customer is exactly this case.
4. If `total_inq > 0`, band by `risk_tier` and read which component is lowest; the component names the
   intervention, the composite does not.
5. Refuse to produce a probability. Report the score, the band, the lowest component and the date measured.

**R05/R06/R07 — the rating ask.**
1. Trigger on `revealed_at`. Not on quote receipt, not on case closure, not on a weekly sweep — the
   founder's ruling is the reveal moment.
2. Gate: `fn_refund_state` must not be in any chase or final-call state. Gate: channel consent. Gate:
   frequency cap (M7 — currently unenforceable).
3. Compose from a stored, approved template in the customer's `locale`. **No approved WhatsApp template
   for a rating ask exists** (`messaging_template` holds none), so today the only lawful channel is email.
4. Write `rating` plus whichever of the six dimensions the template asked. A rating of 1 or 2 is a
   complaint: `fn_emit_customer_complaint_from_review` already emits `customer.complaint` for it, and the
   `complaint` workflow takes over.
5. Refuse to ask a second time. One reminder maximum, and only if the first went unanswered.

**R10/R11 — the save offer.**
1. Enumerate offers from a fixed catalogue that contains **no money**: expedited re-dispatch, a wider
   category fan-out, a human call from the director, a written explanation of what went wrong.
2. Any offer involving a credit, waiver, discount or comp is out of catalogue → hand to `followup`, who
   hands to the founder. `budget_limit = 0` and `auto_action_max_aed = 0` make this unambiguous.
3. Score the remaining offers by (relevance to the lowest health component) × (stored effectiveness
   weight). **The effectiveness weights are unmeasured** — until a save has ever succeeded, treat them as
   equal and say so.
4. Refuse when the customer has opted out, when the frequency cap would be breached, or when the case is
   mid-ladder.

**R08/R29/R31 — reporting honestly.**
1. Repeat-reveal rate: denominator 0 → **undefined**, stated as such.
2. CSAT: `company_goals.csat` has `no_measure_reason` "NO INSTRUMENT EXISTS" and `reviews` has 0 rows →
   report "not measured", never a number.
3. Retention: `company_goals.customer_retention` likewise.
4. The seat's own KPI reads 59.44 % from `notifications`. Report the outbox figure under the name
   "notification send-within-24h", and report retention as not measured. **Never let the outbox number
   stand where a retention number is expected.**

**R12/R34 — opt-out.**
An opt-out is global, not per channel. On receipt: write the suppression, verify across email, WhatsApp and
SMS, and confirm to the customer. Then verify the *absence* of future sends by query, not by assumption.
`email_suppressions` (37 rows) and `unsubscribe` (edge function) exist; a cross-channel consent ledger
**does not exist**.

### 4. Judgement rules

1. `total_inq = 0` → the customer is new. Never run a retention or win-back play. **Even when the health
   score is low** — 46.8 with zero activity is an unstarted journey, not a fading one.
2. Never present the health score as a churn probability. Reason: `customer_score` is empty and
   `fn_emit_churn_signal` has never fired.
3. Any offer that moves money → out of catalogue, hand to `followup` → founder. **Even a AED 25 credit that
   would obviously work.** Reason: `auto_action_max_aed = 0`, `budget_limit = 0`, and the founder's
   refunds-only boundary.
4. Never contact an opted-out customer, for any reason, including an apology. Reason: explicitly forbidden.
5. Never ask for a rating while the refund ladder is running on that transaction. Reason: we are chasing
   the supplier the customer paid for; the ask reads as contempt.
6. Ask for a rating at the reveal moment, once, with at most one reminder. Reason: the founder's ruling.
7. A rating of 1 or 2 is a complaint and enters the complaint workflow automatically. Reason:
   `fn_emit_customer_complaint_from_review`.
8. Never report a retention or CSAT figure. Reason: both goals carry "NO INSTRUMENT EXISTS" and `reviews`
   is empty. **Even when a plausible proxy exists** — a proxy reported under the real metric's name is the
   estate's most-repeated failure.
9. Report an undefined rate as undefined, never as 0 %. Reason: 0 % says we tried and failed; undefined
   says nothing has happened yet, and those lead to opposite actions.
10. Never send an outreach that repeats an ignored message. Reason: R26; the second identical send is the
    one that gets marked spam.
11. Never attribute a loss to this department without walking M8. **Even when it looks like our failure.**
12. Never run a "campaign" to a base smaller than a stored minimum. Reason: a campaign to n=1 is a message,
    and calling it a campaign corrupts the metric.
13. A referral or testimonial ask requires a *completed* good outcome, evidenced by a rating ≥ 4 and no open
    case. Reason: asking earlier converts goodwill into an obligation.
14. If the frequency cap cannot be evaluated because M7 does not exist, treat the cap as **1 outreach per
    customer per 14 days** and say the cap is provisional. Reason: an unenforceable cap is not a licence.

### 5. Technical knowledge

- `customer_health` (VIEW — the live instrument), `customer_score` (BASE TABLE, 0 rows),
  `fn_emit_churn_signal` (fires at `churn_risk >= 0.7`), `company_event` / `event_delivery` / `fn_emit`.
- `reviews` (rating + `r_communication`, `r_quality`, `r_punctuality`, `r_documentation`, `r_after_sales`,
  `r_compliance`; 0 rows), `feedback` (0 rows), `fn_emit_customer_complaint`,
  `fn_emit_customer_complaint_from_review`.
- `transactions.revealed_at` as the rating trigger; `fn_refund_state` as the gate before any ask.
- `email_suppressions` (37), `email_block_pattern` (4), the `unsubscribe` edge function, `wa_optin_set`.
- `messaging_template` — and the measured fact that **no approved template exists for any retention or
  rating moment**; the approved set is `customer_new_quote`, `customer_supplier_unlocked`,
  `supplier_new_inquiry`, `supplier_doc_expiry`, `supplier_quote_accepted`.
- `supplier_perf`, `supplier_reputation`, `v_obj_supplier_retention_case` for M8's supply-side attribution.
- `phase_b_sla_policy.SLA-SUPPLIER-RETENTION` (1 business day after signal) — the supply-side analogue this
  seat should mirror on the customer side; **no customer-retention SLA row exists**.
- **What must be stored so this seat can act alone**: the next-best-action decision table (M6, does not
  exist); the frequency-cap table (M7, does not exist); the cross-channel consent ledger (does not exist);
  the dormancy parameter N (M3, underivable today); a customer-retention SLA row (does not exist).

### 6. Academic knowledge

| framework | why | lawful primary source |
|---|---|---|
| CX competency model — insight, metrics, design, accountability | The seat's rank-1 certification | CXPA published **CCXP Competency Framework and exam blueprint** (free, cxpa.org) |
| Front-line service standard | Rank-2 certification | HDI published **HDI-CSR** blueprint (free) |
| Buy-till-you-die / repeat-purchase modelling | M5, R21, R32 — deriving a re-purchase cycle from data instead of assuming one | Fader & Hardie's **author-published technical notes** at brucehardie.com (freely distributed by the authors) |
| Survival analysis and cohort retention curves | R18, R21 | Kaplan–Meier: the original published paper; `lifelines` and R `survival` package documentation (open source) |
| Customer-satisfaction monitoring | R07, R29 | **ISO 10004** (licensed copy; free abstract) |
| Service quality dimensions | Choosing which of the six review dimensions matter | Parasuraman, Zeithaml & Berry, published **SERVQUAL** dimensions |
| Kano model of satisfaction | R16 — which improvements actually move satisfaction | Kano et al., published paper |
| Recommendation-likelihood scoring | R29 | Use a plain 0–10 "would you recommend" item. **Do not use the term "NPS"** — it is a registered trademark of Bain & Company / Satmetrix; the underlying question is not |
| Consent and marketing conduct in the UAE | R12, R24, R34 | **TDRA** published anti-spam and messaging regulations; **Federal Decree-Law No. 45 of 2021 (PDPL)** on consent and withdrawal; **Federal Law No. 15 of 2020** on consumer communications |
| Messaging-platform consent rules | R04, R23 | Meta **WhatsApp Business Platform** published policy and template guidelines; Twilio published messaging-policy documentation |
| Public holidays and cultural timing | R25 | UAE Cabinet / FAHR official public-holiday announcements; official Ramadan working-hours circulars |

**Certifications held**: CCXP (CXPA, pass 68 %, rank 1) — six competency areas. HDI-CSR (HDI, pass 75 %,
rank 2) — six areas.
**Syllabus areas failed: does not exist.** `certification_exam_result` holds no row for `cs_retention`, and
`certification_knowledge_gap` holds none. This seat has never sat either exam.

### 7. Corporate knowledge

- **The founder's rating-solicitation ruling: at the reveal moment.** This is a standing decision, not a
  preference, and it is the seat's only timing authority.
- **The reveal notifies both parties** — the founder stated it directly; `phase_d_external_message_contract`
  records four required messages of which **only `reveal.customer.email` is sent today**. The other three
  (supplier email, customer WhatsApp, supplier WhatsApp) are `required` and not sent. This seat's rating
  ask rides the same moment and inherits the same gap.
- **No money, ever.** `budget_limit = 0`; `forbidden_decisions` names discounting outside policy;
  `auto_action_max_aed = 0`; refunds are the founder's alone.
- **The one real customer** has `total_inq = 0` — this seat currently has nobody to retain, and saying so
  is the correct report.
- **The workflow it owns**: `payment` step 7 — "Start the supplier response clock (nudge at 24h and 48h)",
  `actor_role='customer_retention'`, `action_class='nudge'`. Note the tension the seat must hold: the
  24h/48h nudges live here, while the 3-day/5-day ladder lives with `followup`. Both read the same
  `transactions` row.
- **Who it hands to**: `customer_success_director`. It escalates to the same, then `chief_of_staff`.
- **History**: the seat's KPI has measured the notifications outbox since 26 Jul 2026 (59.44 % at
  2026-09-07 03:30 UTC). Its `improvement_plan` carries a departmental root cause about "attainment 49.2 %"
  that was never about retention. `customer_score` has existed with 0 rows throughout.

### 8. One-year plan

**Objective.** Make the second reveal happen — and, until there is a first, make sure the first outcome is
not quietly lost.

**Metrics owned.**
1. *Rating capture rate at reveal* — ratings written ÷ reveals. Today **undefined** (0 reveals). This is
   the first thing this seat can genuinely own, because the trigger and the table already exist.
2. *Repeat-reveal rate* (M5) — today **undefined**, not 0 %.
3. *Health-score movement on intervened customers* — the change in `customer_health.health` 30 days after
   an intervention versus a matched non-intervened set. Requires a base; today n=1.

**Quarterly milestones.**
- *Q1*: the rating ask exists as an approved, bilingual template and fires deterministically at
  `revealed_at`, gated on `fn_refund_state`; the next-best-action table (M6) exists; the frequency cap (M7)
  and the cross-channel consent ledger exist; a customer-retention SLA row is added to
  `phase_b_sla_policy`.
- *Q2*: first ratings land in `reviews`; the 1-or-2-star → complaint path is proven end to end;
  the CCXP exam is sat and gaps written to `certification_knowledge_gap`.
- *Q3*: dormancy parameter N derived from the first real inter-purchase intervals (or still honestly
  reported as underivable); cohort curves produced from a real base.
- *Q4*: repeat-reveal rate reported from a non-zero denominator; `customer_score` populated by a
  deterministic job so `fn_emit_churn_signal` can fire for the first time.

**Capacity check.** `max_open_tasks = 50`. Every mechanism here is a triggered send or a scored lookup —
volume is not a constraint at any plausible year-one scale. The binding constraint is that **retention has
no population**: 1 customer, 0 inquiries, 0 transactions, 0 reviews.

**Dependencies.** `marketplace` and `supply` for the reveals that create anything to retain;
`channel_specialist` for an approved bilingual template and an enforceable frequency cap; `product_eng`
for `customer_score` population and for the consent ledger; `followup` for every money decision.

**Is the slice achievable?** The department objective this seat is nearest to — `customers_active`
1,500/month (`department_objective` 75, actual **0**, measured 2026-09-07 03:25 UTC) — is **not
achievable** and is not this seat's to deliver: monthly-active is measured from `inquiries`, which come
from acquisition and from a marketplace that can quote them. The honest year-one commitment for this seat
is different and fully within its control: **every reveal produces a rating ask at the reveal moment, and
no customer is ever contacted without consent or outside the cap.** Both are 0 % today because the
mechanisms do not exist; both are achievable in Q1 and neither depends on demand.

### 9. What this seat cannot do without a model

1. **Reading an open-text review comment for its actual grievance.** The star rating and the six dimensions
   are structured and sufficient to route; the prose is not machine-readable here. Accepted: route on the
   numbers, hand the prose to a human.
2. **Writing a personalised save message.** The catalogue in M6 plus stored templates produces a correct,
   specific message; it does not produce a persuasive bespoke one.
3. **Predicting churn.** This is not a model-dependency in the LLM sense — a churn model is ordinary
   statistics — but it is currently impossible for a different reason: **zero labelled history.** No
   technique, model or otherwise, produces a churn probability from 0 churn events.

---

## channel_specialist — Lifecycle Channel Operations Specialist

`org_agents.responsibilities`: "Own every lifecycle message from queue to inbox: outbox depth, retries,
dead letters and the digest, and deliverability, sender reputation, bounces, suppressions, opt-outs,
template approval and per-recipient caps. A message that is never sent and a message that lands in spam are
the same failure."
`org_role.lifecycle_channel_operations`, `authority_level='execute_low'`, `runtime_enabled=true`.
Owns: outbox handling, retries and dead letters; suppression and opt-out enforcement; sender-reputation
actions. Forbidden: **writing message content**; sending to a suppressed or opted-out recipient.
`employee_authority` gives it exactly one row: `analysis`, `supervised`.
Its `escalation_targets` still name `communications_manager`, a role that is `status='retired'`.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|----|----------------------|------|-----------|----------|---------------------------|
| C01 | Is the outbox draining, and how deep is it? | diagnosis | continuous | this seat | 52 of 142 notifications in the last 7 days have no `sent_at` |
| C02 | Is this notification `queued`, `digested`, `skipped`, `expired` or `sent` — and why? | diagnosis | per row | this seat | Five statuses with different owners; conflating them hides real failures |
| C03 | Should this alert be sent individually or folded into the daily digest? | allocation | per alert | `decision_policy.alert_digest_types` | Digesting a money, security or founder alert is a hard breach |
| C04 | Is this recipient suppressed? | gate | every send | this seat | 37 suppressions exist; sending to one is a reputation hit we chose |
| C05 | Does this address match a block pattern? | gate | every send | this seat | 4 active patterns, including reserved domains and role mailboxes |
| C06 | Is this a hard bounce or a soft bounce? | diagnosis | per bounce | this seat | Suppressing on a soft bounce loses a real recipient |
| C07 | What is the hard-bounce rate, and is it above the ceiling? | diagnosis | weekly | this seat | Measured **5.85 %** against a target of **2** |
| C08 | Is the bounce rate driven by one list or spread across all sends? | diagnosis | per spike | this seat | A list problem fixed as a domain problem stays broken |
| C09 | Is sender reputation degrading at a specific receiving domain? | diagnosis | weekly | this seat | Reputation is per-domain; the aggregate hides the one that matters |
| C10 | Are SPF, DKIM and DMARC aligned and passing? | gate | continuous | this seat | Alignment failure is invisible until a whole domain rejects us |
| C11 | Is the DMARC policy at the right enforcement level? | gate | quarterly | this seat | `p=none` sees problems; `p=reject` prevents them |
| C12 | Does every bulk message carry a working one-click unsubscribe? | gate | every bulk send | this seat | RFC 8058 and the bulk-sender rules make this mandatory |
| C13 | Is an opt-out honoured on every channel, not just the one it arrived on? | gate | per opt-out | `cs_retention` | A cross-channel consent ledger does not exist |
| C14 | Is there an approved WhatsApp template for this message? | gate | every WA send | this seat | Sending outside a template gets the WABA restricted |
| C15 | Is the template in the right category — UTILITY, MARKETING or AUTHENTICATION? | gate | per template | this seat | Two approved templates are miscategorised as MARKETING today |
| C16 | Is the template approved in **both** English and Arabic? | gate | per template | this seat | An English-only template silently excludes Arabic customers |
| C17 | Why was `control_mode_code` rejected, and does it affect anything else? | diagnosis | one-off | this seat | The rejection is a WABA **permission** error, not a content error |
| C18 | Is `founder_alert` still `pending`, and what is blocked while it is? | diagnosis | continuous | this seat | The founder's WhatsApp path is not approved |
| C19 | Is the recipient contactable on this channel at all? | gate | every send | `cs_support` | The only real customer has `wa_optin=false` and `phone_verified=false` |
| C20 | Which of the four required reveal messages actually fire? | diagnosis | per reveal | `followup` | Measured: **1 of 4** — customer email only |
| C21 | Is a message retryable, and how many attempts have been made? | sequencing | per failure | this seat | `attempts` and `last_error` exist per row |
| C22 | When does a failed message become a dead letter? | gate | per failure | this seat | `v_email_deadletter` = 0 today; the definition must not be silently loose |
| C23 | Is the digest itself being delivered? | gate | daily | this seat | 170 notifications are `digested`; a digest that never arrives loses all of them |
| C24 | Is the per-recipient frequency cap respected? | gate | every send | `cs_retention` | The cap table does not exist |
| C25 | Are we inside a rehearsal window — should this send be held? | gate | continuous | this seat | `demo_rehearsal_active` holds every non-`.invalid` recipient |
| C26 | Is this recipient a fixture rather than a person? | gate | every send | this seat | 2 of 3 welcome rows went to `@example.invalid` and were correctly skipped |
| C27 | Is the send inside `SLA-NOTIFICATION` (first attempt within 5 minutes)? | gate | per message | `sla_watch_hourly` | The measured welcome took 90 seconds; the trigger took 11 hours |
| C28 | Which language does this recipient get, and does the template exist in it? | allocation | every send | this seat | Arabic templates exist for 5 keys and nothing else |
| C29 | Is a template's status stale — approved once, changed since? | gate | per send | this seat | `last_checked_at` exists; `wa_templates_watch` refreshes it |
| C30 | Is the WhatsApp session window open, or does this need a template? | gate | per WA send | this seat | Outside the 24-hour window only templates are permitted |
| C31 | Is inbound WhatsApp being routed to a person or a seat? | allocation | per inbound | this seat | 12 `wa_messages`, all founder traffic, 0 escalated |
| C32 | Should this send be held for UAE working hours or a holiday? | sequencing | seasonal | this seat | The holiday calendar does not exist |
| C33 | Is the sending domain warmed for this volume? | forecast | per campaign | this seat | A cold domain sending 22,265 invites is a blocklisting |
| C34 | Is a receiving provider rate-limiting or greylisting us? | diagnosis | per spike | this seat | Retrying into a rate limit compounds it |
| C35 | Is the unsubscribe endpoint working end to end? | gate | monthly | this seat | `unsubscribe` is a deployed edge function; untested is unproven |
| C36 | Is a notification kind missing from `founder_mail_policy`? | gate | per new kind | `followup` | A kind with no row either leaks to the founder or vanishes |
| C37 | Are the 13 `founder_alert` rows with `status='skipped'` a bug or a policy? | diagnosis | one-off | `followup` | Measured in the last 7 days; nobody has said which |
| C38 | Is the department's own KPI for this seat measuring the right thing? | diagnosis | weekly | the director | Hard-bounce rate is measured from `leads`, which is supply's list, not this seat's sends |

### 2. Domain logic

**M1 — Outbox state machine.** `notifications.status ∈ {queued, sent, digested, skipped, expired}` with
`attempts` and `last_error`. Measured totals (855 rows): sent/email **632**, digested/email **170**,
expired/email **33**, skipped/whatsapp **13**, skipped/email **7**. Last 7 days: **142** created, **87**
sent within 24 h, **52** with no `sent_at` — of which 18 `health_alert`, 7 `ops_alert`, 6
`resilience_alert`, 4 `exception_alert` and 1 `policy_inconsistency` are `digested` (by design, they are in
`decision_policy.alert_digest_types`), 13 `founder_alert` and 2 `customer_welcome` are `skipped`, and 1
`exception_alert` is `skipped`. **The important arithmetic:** 31 of the 52 "unsent" are digested by policy
and are not failures at all. The seat must report `queued_stuck`, `skipped_by_policy`,
`skipped_undeliverable` and `digested` as four separate numbers, never as one "unsent".

**M2 — Deliverability rates.** `hard_bounce_rate = hard_bounces ÷ delivered_attempts`;
`complaint_rate = spam_complaints ÷ delivered`. Industry enforcement thresholds published by the major
bulk-mail receivers: complaint rate must stay **below 0.3 %**, and spam rate should be held near 0.1 %.
This seat's KPI reads **5.85 %** hard bounce against a target of **2** — but its `measure_sql` is
`count(*) filter (where invite_status='bounced') / count(*) filter (where invited_at is not null)` **from
`leads`**, i.e. 10 ÷ 171. That measures the supplier invite list's quality, which `supply` owns, not this
seat's sending. **Unmeasured:** this seat's own delivered/bounced/complained counts per send — the
`notifications` table has `attempts` and `last_error` but no per-provider event ledger, so no true
deliverability rate exists.

**M3 — Suppression logic.** A recipient is unsendable if: present in `email_suppressions` (37 rows: 36
`hard_bounce:permanent`, 1 blocked QA pattern), **or** matching an active `email_block_pattern`
(4 patterns: `^qa[.]`, `^(no-?reply|do-?not-?reply|postmaster|abuse|spam|bounce)@`,
`example[.](com|org|net)$`, `[.](test|invalid|localhost|local)$`), **or** opted out. Deterministic, already
enforced — the two skipped welcomes carry exactly the expected reason string.

**M4 — Retry and dead-letter.** Retry only on a retryable class (4xx rate limit, 5xx, timeout, greylist);
never on a hard bounce, an invalid address, a suppression or a policy skip. Backoff exponential with a
cap; after N attempts the row becomes a dead letter. `v_email_deadletter` = 0 today and
`fn_notifications_dead_letter_held(days)` exists. **Unmeasured:** N and the backoff schedule are not
recorded as stored parameters anywhere this seat can read.

**M5 — Digest eligibility.** `decision_policy.alert_digest_types` lists 13 kinds folded into the daily
brief (`health_alert`, `smoke_alert`, `exception_alert`, `ops_alert`, `supply_health`, `agent_silence`,
`uptime_alert`, `rfq_sla_breach`, `ai_quality_alert`, `doc_expiry`, `expense_logged`, `agent_created`,
`policy_inconsistency`). Money, security, legal, critical and `founder_alert` are **hard-excluded
regardless**. `trg_notifications_digest` parks the eligible ones; `fn_notifications_digest` and
`run_pending_digest` compose. Pure lookup.

**M6 — Template eligibility (WhatsApp).** A send is permitted iff: an approved
`messaging_template` row exists for `(template_key, lang)`, its `status='approved'`, its `category` fits
the message's purpose, and either the 24-hour session window is open or the template is used as a
template. Measured inventory — approved en+ar for `customer_new_quote`, `customer_supplier_unlocked`,
`supplier_new_inquiry`, `supplier_doc_expiry`, `supplier_quote_accepted`; `founder_alert` **pending**;
`control_mode_code` **rejected** with a permission error; two `supplier_quote_accepted` rows sitting in
`received`. **Category defect, measured:** `customer_new_quote/ar` and `supplier_new_inquiry/en` are
approved as **MARKETING** while their English/Arabic twins are **UTILITY**. A transactional message
approved as marketing is subject to marketing opt-out and to different delivery treatment — the pair should
match.

**M7 — Reveal message contract.** `phase_d_external_message_contract` names 4 required messages;
**1 fires**. `reveal.customer.email` is sent by `trg_reveal_receipt`; `reveal.supplier.email` is not
("the trigger inserts one row with `to_role=customer`"); both WhatsApp legs are not ("the trigger names no
channel and no phone"). Completion arithmetic: **25 %**.

**M8 — Authentication posture.** SPF (RFC 7208), DKIM (RFC 6376), DMARC (RFC 7489) with alignment, plus
one-click unsubscribe (RFC 8058) on bulk. Each is a DNS/header check with a boolean answer — no judgement.
`email_domain_mx` exists as a table for the MX half. **Unmeasured:** no stored record of the current SPF,
DKIM selector, DMARC policy or their pass rates was found.

**M9 — Rehearsal hold.** `decision_policy.demo_rehearsal_active` (currently `false`): while true, every
`notifications` insert whose recipient is not a reserved `.invalid` address is **held**, and
`fn_notifications_release_held()` lets the backlog go afterwards. `zzz_fn_notifications_demo_guard`
enforces it.

### 3. Reasoning procedures

**C01/C02 — is the outbox healthy.**
1. Partition the last window into the five statuses. Then split "not sent" four ways per M1.
2. `digested` where the kind is in `alert_digest_types` → healthy by design. Verify the digest itself was
   delivered (C23) — otherwise 170 messages have quietly disappeared into a mail nobody got.
3. `skipped` → read `last_error`. A reserved-domain reason is a fixture and is healthy. Any other reason is
   a defect with a named owner.
4. `queued` older than `SLA-NOTIFICATION` (5 minutes) → this is the only true backlog. Report it alone as
   "outbox depth".
5. `expired` (33 rows, 2026-08-16 to 2026-08-30) → a closed window; report the count and the date range,
   and do not retry.
6. Refuse to publish a single "unsent" figure. It is four different failures with four different owners.

**C04/C05/C06 — may we send to this address.**
Order matters and is fixed: block pattern → suppression → opt-out → frequency cap → channel consent →
template availability. Fail at any step: do not send, record the step that refused, and do **not** count it
as a delivery failure. Bounce handling: hard bounce → suppress permanently; soft bounce → retry per M4 and
suppress only after N consecutive soft bounces to the same address.

**C07/C08/C38 — what is our bounce rate really.**
1. State the measured KPI figure with its actual source: 5.85 %, from `leads.invite_status`, 10 bounced of
   171 invited.
2. State plainly that this measures the **supplier invite list**, owned by `supply`, and not this seat's
   sending. The instrument measures the wrong subject.
3. Compute the seat's own rate only if a per-send provider event ledger exists. It does not. Report "not
   measured" and open the task to build it.
4. Group by receiving domain before drawing any conclusion — an aggregate rate driven by one dead domain
   leads to the wrong repair.

**C14/C15/C16/C29 — may we send this WhatsApp.**
1. Look up `(template_key, lang)` in `messaging_template`. No approved row → refuse; there is no
   "send it as free text" fallback outside the session window.
2. Check `category` against purpose. A transactional message on a MARKETING template → flag the mismatch
   and use the correctly categorised twin if one exists.
3. Check `last_checked_at`. Stale → refresh via `wa_templates_watch` before sending, not after.
4. Check recipient consent (`wa_optin`) and `phone_verified`. Either false → WhatsApp is unavailable;
   fall back to email and record that the WhatsApp leg did not fire.
5. Refuse for `founder_alert` today: it is `pending`, not approved.

**C20 — which reveal messages fired.**
Read `phase_d_external_message_contract` (4 required), then for each check the notification that would
prove it. Report the completion fraction — today **1/4** — with the three named gaps and their stated
causes, not as a single "reveal notifications working" boolean.

**C03/C36 — individual, digested, or nowhere.**
1. Kind in `alert_digest_types` and not money/security/legal/critical/founder → digest.
2. Kind in `founder_mail_policy` with `allowed_to_email=true` → send individually to the founder.
3. Kind in `founder_mail_policy` with `allowed_to_email=false` → route to `owner_role` as an owned task.
4. Kind absent from `founder_mail_policy` → **refuse to send and raise a task.** This is the routing hole
   rule, and it is the same rule `followup` F19 applies from the other side.

### 4. Judgement rules

1. Never send to a suppressed address, a blocked pattern, or an opted-out recipient. **Even a critical
   founder alert.** Reason: the address is dead or the consent is withdrawn; the message would not arrive
   and would cost reputation.
2. Never retry a hard bounce. Reason: it is permanent by definition; retrying is a self-inflicted
   reputation loss.
3. Never send a WhatsApp message without an approved template for that exact `(key, lang)` outside the
   24-hour session window. **Even when the content is identical to an approved English template.**
4. Never write message content. Reason: `forbidden_decisions`; content is `followup`'s and the wording
   belongs with whoever owns the customer relationship.
5. Report the outbox as four numbers, never one. Reason: 31 of the 52 "unsent" rows are working as designed.
6. Never report the 5.85 % hard-bounce figure as this seat's performance without naming its source.
   **Even though it is this seat's stated KPI.** Reason: it measures `leads`, which supply owns.
7. A notification kind with no `founder_mail_policy` row → hold and raise. Reason: default-allow leaks to
   the founder; default-deny loses the message. Neither is acceptable.
8. `demo_rehearsal_active = true` → every non-`.invalid` recipient is held, without exception, and
   `fn_notifications_release_held()` runs only after teardown. Reason: this is the guard that stops a
   rehearsal reaching a real person.
9. A digest that cannot be proven delivered means every message inside it is undelivered. Report it that
   way. Reason: 170 rows currently rest on that assumption.
10. Never suppress on a single soft bounce. Reason: a full mailbox is not a dead address.
11. Never raise sending volume on a domain faster than a stored warm-up schedule. Reason: 22,265 leads
    exist; a burst would blocklist the domain and take the transactional mail with it.
12. Every bulk message carries a working one-click unsubscribe, verified end to end monthly. Reason:
    RFC 8058 and the bulk-sender requirements; an unverified unsubscribe is a complaint generator.
13. An approved template whose category contradicts its twin is a defect to raise, not a preference.
    Reason: category determines opt-out treatment and delivery.
14. If a message cannot be sent on the recipient's only consented channel, say the message did not reach
    them. **Never mark it sent because another leg fired.** Reason: `phase_d_external_message_contract`
    counts four legs, and 1/4 is the honest number.
15. This seat's `escalation_targets` name a retired role (`communications_manager`). Until that is
    corrected, escalate to `followup` — accountability moved there on 3 Sep 2026 — and raise the stale
    reference. Reason: an escalation to a retired role is an escalation into a void.

### 5. Technical knowledge

- `notifications` (id, type, kind, to_email, cc_emails, to_role, channel, to_phone, status, attempts,
  last_error, html, sent_at) and its triggers: `trg_notifications_digest`,
  `fn_notifications_founder_mail_policy`, `zzz_fn_notifications_demo_guard`.
- Outbox routines: `fn_notifications_digest`, `run_pending_digest`,
  `fn_notifications_dead_letter_held(days)`, `fn_notifications_release_held(max)`,
  `fn_phase_c_outbox_emit / _claim / _deliver / _settle`, `fn_kernel_outbox_emit / _deliver`,
  `fn_kernel_outbox_refuse_cancelled_subject`, `v_email_deadletter` (0).
- Edge functions: `send_outbox`, `email_cron`, `send_whatsapp`, `send_sms`, `wa_inbound`, `wa_optin_set`,
  `wa_template_setup`, `wa_templates_watch`, `unsubscribe`, `resend_webhook`, `resend_inbound`,
  `inbound_email`, `email_fix`.
- WhatsApp: `messaging_template` (sid, channel, template_key, lang, name, category, status, submitted_at,
  approved_at, rejection_reason, last_checked_at), `wa_messages`, `fn_wa_fanout`, `fn_wa_context`,
  `fn_wa_lead_id`, `trg_wa_message_to_kernel`, cron 34 `wa_flush` (`*/2 * * * *`).
- Deliverability: `email_suppressions`, `email_block_pattern`, `email_domain_mx`, `email_verifications`
  (139 rows), and the standards — SPF **RFC 7208**, DKIM **RFC 6376**, DMARC **RFC 7489**, one-click
  unsubscribe **RFC 8058**, `List-Unsubscribe` **RFC 2369**, ARC **RFC 8617**.
- Policy: `decision_policy.alert_digest_types` (13 kinds), `.demo_rehearsal_active`, `founder_mail_policy`,
  `phase_d_external_message_contract` (4 rows), `phase_b_sla_policy.SLA-NOTIFICATION` (5 minutes).
- **What must be stored so this seat can act alone**: a per-send provider event ledger
  (delivered / bounced / complained / opened, by domain) — **does not exist**; the retry schedule and
  dead-letter threshold as parameters — **do not exist**; the current SPF/DKIM/DMARC posture — **does not
  exist**; the per-recipient frequency cap — **does not exist**; a cross-channel consent ledger —
  **does not exist**; the domain warm-up schedule — **does not exist**; the UAE public-holiday calendar —
  **does not exist**.

### 6. Academic knowledge

| framework | why | lawful primary source |
|---|---|---|
| Service management, value chain and practices | The seat's rank-1 certification | **ITIL 4 Foundation published syllabus outline** (free from PeopleCert/AXELOS). The ITIL study text is copyrighted and must be licensed, never ingested |
| Lifecycle messaging: segmentation, canvases, deliverability | Rank-2 certification | **Braze Docs and Braze Learning**, publicly published by Braze |
| Email authentication | M8, C10, C11 | **RFC 7208** (SPF), **RFC 6376** (DKIM), **RFC 7489** (DMARC), **RFC 8617** (ARC), **RFC 8058** and **RFC 2369** (unsubscribe) — all free from the IETF |
| Bulk-sender requirements and thresholds | C07, C12, C33 | Google **Email sender guidelines** and Yahoo **Sender requirements** — both publicly published; the ≤0.3 % complaint-rate requirement is stated there |
| Deliverability best practice | C33, C34 | **M3AAWG published Best Common Practices** (free at m3aawg.org), including sender best practices and bulk-mail BCPs |
| SMTP behaviour, status codes, greylisting | M4's retryable classes | **RFC 5321** (SMTP), **RFC 3463** (enhanced status codes), **RFC 6647** (greylisting) |
| Messaging-platform policy and template rules | C14–C18, C30 | Meta **WhatsApp Business Platform** published policy, template guidelines and category definitions; **Twilio** published messaging-policy and Content Template Builder documentation |
| Queueing and backlog dynamics | C01 — outbox depth as a queue, not a list | Little's Law and Erlang C — public-domain results |
| Reliability engineering: retries, backoff, dead letters | M4 | Google **SRE Book**, published free online by Google; AWS published Architecture Blog on exponential backoff and jitter |
| UAE messaging and anti-spam regulation | C12, C13, C32 | **TDRA** published regulatory policies; **Federal Decree-Law No. 45 of 2021 (PDPL)** on consent and withdrawal |
| Working calendar | C32 | UAE Cabinet / FAHR official public-holiday announcements |

**Certifications held**: ITIL 4 Foundation (PeopleCert/AXELOS, pass 65 %, rank 1) — Key Concepts of Service
Management; The Four Dimensions; The Guiding Principles; The Service Value System; The Service Value
Chain; ITIL Practices; Continual Improvement. Braze Certified Marketer (Braze, pass 75 %, rank 2) —
Audience Segmentation; Campaign and Canvas Creation; Messaging Channels; Personalization and Liquid;
Analytics and Reporting; Deliverability and Compliance.
**Syllabus areas failed: does not exist.** `certification_exam_result` holds no row for
`channel_specialist`, and `certification_knowledge_gap` holds none. This seat has never sat either exam.
Its 8 `agent_knowledge` rows include one `profession`-layer record titled "Deliverability and sender
reputation", `validation_status='unvalidated'`.

### 7. Corporate knowledge

- **The seat is a merger.** `notification_ops` merged into it on 14 Aug 2026; `comms_manager` was parked on
  3 Sep 2026 with accountability moved to `followup`. Its own `escalation_targets` still point at the
  retired `communications_manager` — a live stale reference.
- **It does not write content.** `forbidden_decisions` is explicit. Its job ends at "did this arrive".
- **The founder's WhatsApp is his command channel**, and `founder_alert` as a WhatsApp template is
  `pending`, not approved. `control_mode_code` was rejected with a WABA **permission** error
  ("Application does not have permission for this action"), not a content rejection — retrying the content
  will not fix it.
- **The reveal notifies both parties**, by the founder's direct statement, and today only one of the four
  required messages fires. This is the single largest customer-facing channel gap in the estate and it
  belongs to this seat jointly with `product_eng`.
- **The approved WhatsApp inventory** (measured 2026-09-06): `customer_new_quote` en+ar,
  `customer_supplier_unlocked` en+ar, `supplier_new_inquiry` en+ar, `supplier_doc_expiry` en+ar,
  `supplier_quote_accepted` en+ar (plus two more in `received`). **Nothing for a welcome, a rating ask, a
  refund-ladder chase, or a retention nudge.**
- **The digest bargain**: 13 alert kinds are folded into the daily brief; money, security, legal, critical
  and `founder_alert` never are. 170 notifications currently rest on the digest arriving.
- **The rehearsal guard**: `demo_rehearsal_active`, `ZZ DEMO`, `@example.invalid`, and
  `fn_notifications_release_held()`. Two of the three welcome rows in production are fixtures that this
  guard correctly refused.
- **History**: 33 notifications `expired` between 2026-08-16 and 2026-08-30; 13 `founder_alert` rows were
  `skipped` in the last 7 days and nobody has recorded whether that is policy or a defect.

### 8. One-year plan

**Objective.** Every message the company decides to send arrives, on a consented channel, in the
recipient's language — and every message it decides not to send is refused for a named, recorded reason.

**Metrics owned.**
1. *Contract completion* — required external messages that actually fire ÷ required.
   Measured today: **1 of 4 = 25 %** (`phase_d_external_message_contract`). Target 100 %. Fully in scope,
   independent of demand.
2. *Outbox honesty* — every not-sent row classified into exactly one of `queued_stuck`,
   `skipped_by_policy`, `skipped_undeliverable`, `digested`, with a reason string. Target 100 %.
   Measurable immediately on the existing 855 rows.
3. *True deliverability* — hard-bounce and complaint rate from this seat's own sends, by receiving domain,
   held below the published bulk-sender thresholds (complaint rate < 0.3 %). **Unmeasurable today: no
   provider event ledger.** Its existence is the Q1 milestone.

**Quarterly milestones.**
- *Q1*: the provider event ledger exists; the four outbox classes are reported separately; SPF/DKIM/DMARC
  posture is recorded and verified; the one-click unsubscribe is tested end to end; the stale
  `escalation_targets` reference is corrected; the 13 skipped `founder_alert` rows are diagnosed and
  recorded as policy or defect.
- *Q2*: the three missing reveal legs fire (supplier email, both WhatsApp legs) — contract completion 4/4;
  approved bilingual templates exist for welcome, rating ask and refund-ladder chase; the MARKETING /
  UTILITY category mismatch on the two approved pairs is corrected; `founder_alert` is approved or its
  absence is formally accepted.
- *Q3*: the frequency cap and cross-channel consent ledger exist and are enforced; the retry schedule and
  dead-letter threshold are stored parameters; the domain warm-up schedule exists before any volume rise;
  ITIL 4 Foundation is sat and its gaps written to `certification_knowledge_gap`.
- *Q4*: deliverability reported per receiving domain against the published thresholds; the seat's KPI is
  re-pointed from `leads` to its own sends, or given an honest `no_measure_reason`.

**Capacity check.** All of this is cron-driven (`wa_flush` every 2 minutes, `send_outbox`, the daily
digest) and scales with volume, not with attention. The estate has already handled 855 notifications and
22,265 leads without an outbox failure that produced a dead letter (`v_email_deadletter` = 0). At the
year-one arithmetic — say ~1,667 reveals, each triggering four contract messages plus onboarding,
retention and ladder traffic — the order of magnitude is **low tens of thousands of messages a year**,
which is a trivial volume for the machinery and a **non-trivial volume for sender reputation**. The
constraint is reputation and consent, not throughput.

**Dependencies.** `product_eng` for `trg_reveal_receipt` to emit all four legs and for the provider event
ledger; `followup` for message content and for every `founder_mail_policy` kind; `cs_retention` for the
frequency policy the retired `comms_manager` used to own; Meta/Twilio approval cycles for every new
template, which are external and cannot be compressed.

**Is the slice achievable?** This seat carries no revenue line, and its share of the AED 1,000,000 is
**enabling**: at a 3 % reveal rate, every AED 33.33 of revenue depends on a reveal message reaching two
parties, and **three of the four required legs do not fire today.** That is the clearest, most achievable,
demand-independent contribution in the whole department: **contract completion from 25 % to 100 %.** It
requires no customers, no suppliers and no model — only the trigger work and the template approvals. It
should be committed to for Q2 and held to.

### 9. What this seat cannot do without a model

**None.** Every question in this seat's taxonomy resolves to a lookup, a regex, a rate, an RFC-defined
check or a stored policy row. The only work here that a model could plausibly do is **writing message
content**, and that is explicitly forbidden to this seat by `org_role.forbidden_decisions` — content
belongs to whoever owns the relationship, and every string it sends must exist as approved, versioned,
bilingual data before the send is attempted. This is the one seat in the department that is already fully
deterministic by design.

---

## Department-level summary for the founder

| seat | question types specified | needs a model at run time |
|---|---|---|
| `followup` — Customer Success Director | 45 | 4 items, all degradable to refusal or template |
| `cs_onboarding` — Customer Onboarding Specialist | 32 | 3 items, all degradable |
| `cs_support` — Customer Support Specialist | 42 | 5 items, all degradable to refusal + route |
| `cs_retention` — Customer Retention Specialist | 34 | 3 items (one is a data problem, not a model problem) |
| `channel_specialist` — Lifecycle Channel Operations | 38 | **none** |
| **total** | **191** | |

**The three things that would change this department most, in order:**

1. **A support case table.** Five of the department's seven KPI rows measure the `notifications` outbox
   because there is nothing else to measure. Until a case exists as a row with `opened_at`,
   `acknowledged_at`, `resolved_at`, `sla_policy_id` and `handoff_open`, this department cannot report a
   single honest service number, and `cs_support` cannot run its own procedures.
2. **The three missing reveal messages.** `phase_d_external_message_contract` says four are required and
   one fires. Every AED of revenue passes through that moment.
3. **The welcome trigger.** The estate's only real customer waited 11 hours 22 minutes for a welcome the
   outbox then sent in 90 seconds, against a 30-minute SLA.

**What is already right and should not be touched:** the refund ladder. `fn_refund_state`,
`fn_refund_ladder_sweep` (cron 343, hourly), `fn_refund_amount_aed` and the founder-only routing implement
his 6 September ruling exactly, deterministically, with no model, and with a dedupe key so he can never be
paged twice for the same case. Every seat above defers to it rather than reimplementing it.
