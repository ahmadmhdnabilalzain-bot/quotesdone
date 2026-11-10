# Seats that act, not report: organisation audit and design

Seat: ceo (organisation audit) · 10 Nov 2026 · read-only on production htdblwldjkcgjvmqkbeh, window = last 30 days
unless stated · no model calls, no writes.

Governing ruling: **founder_instruction 1574** (10 Nov 2026, standing): *"Every seat must ACT, not just report: the IT
engineer fixes the glitches it can fix itself (not core code) instead of sending counts of problems; the CEO plans to reach
the target and gives orders to the agents (e.g. low invitation response -> find other channels/emails) instead of emailing
that we are behind; the accountant keeps every finance record (invoices out, expenses from the month-end email scan); customer
support handles its tasks. The company runs on its own with an approval sequence like a real 20-person company; the founder
only gives direction, guidelines and funding."* Read alongside 1438 / 1455 (CEO owns the supplier target and the cap), 1059
(a rejection never ends the cycle), 1559 (no bank-statement reconciliation; month-end email scan the founder triggers),
1564 (GitHub Actions off), 1058 (blogs reviewed by the CEO, founder only notified).

---

## 0. The answer in six lines

1. **The CEO's powers have never fired.** `ceo_growth_act` logged **81 decisions since 2 Nov, 0 applied**, because
   `app_secrets.ceo_growth_act_golive = false`. That includes **8 consecutive daily bounce-brake decisions (cap 20 -> 10,
   bounce 16 % against a 5 % limit) and 2 "close the mailbox" decisions that were never applied.**
2. **The IT engineer has never remediated anything by playbook.** 54 `it_playbook` rows, **1** with a `remedy_routine`,
   **0** `agent_runs` with `job = 'playbook'` ever. Of 5,837 it.finding handoffs in 30 days, 4,747 were answered with the
   boilerplate "Its playbook has no deterministic remedy" and **2** carried a remedy. Every one of the 6,223 closures in
   30 days was "the duty no longer finds it".
3. **CEO orders are generic and close falsely.** 156 directives issued in 30 days: 17 met, 15 missed, 41 escalated, 80 open.
   The text is "Name the step that is not converting and change that step". 3 of the 17 "met" were closed on 31 Oct
   21:30 UTC with the metric still at **0** (the plan's month rolled over; the miss disappeared from the list).
4. **The approval chain stalls at the originator.** 0 of the 14 items the CEO rejected have reached approval. 27 seat
   revisions are parked as `held_question` ("held after 5 failed reasonings ... ceo_revision"). The CEO leaves its own
   ceo.revise / ceo.root_cause / deliberation.review handoffs answered but not closed (35 pending, oldest 29 Sep).
5. **The October close is waiting for a Mashreq statement**, which ruling 1559 abolished. `accountant.close_by_day_five`
   reads `status = waiting_for_statement`. 14 receipts have been held for more than 24 hours with no owner.
6. **The supplier target:** 0 registered against 300-400 by 31 Dec. 117 sent, 4 replied, 1 started. Measured at the
   current rate, the most the company can reach is **15** (`fn_ceo_supplier_goal_status`). The CEO knows this and lists the
   access it needs per channel (`ceo_supplier_channel.access_needed`). That list has never been turned into an order or
   an access request.

---

## 1. Seats, duties and the split of outputs

### 1.1 Seats that exist

The live seat table is `public.org_role`, 6 rows, all `status = active` and `runtime_enabled = true`: accountant, ceo,
customer_support, it_engineer, marketing, sales_engineer. No other seat exists.

### 1.2 Duties

| seat | seat_duty (enabled) | not ok inside 2 days | failing | resilience_step | it_duty_schedule |
|---|---|---|---|---|---|
| accountant | 24 (24) | 0 | 0 | 4 | – |
| ceo | 34 (34) | 4 (weekly duties) | 0 | 8 | – |
| customer_support | 20 (20) | 4 | **1** (knowledge_request_deadline, 8 failures, last ok 1 Nov) | 7 | 1 |
| it_engineer | 28 (27; knowledge_exam retired) | 6 | 0 | 21 | 13 |
| marketing | 19 (19) | 1 | 0 | 3 | – |
| sales_engineer | 29 (29) | 1 | 0 | 2 | 2 |

**Duties classified by what they do.** I read each duty's `what` text and the routine it names. *Act* means it changes
state outside its own report tables: it sends, closes, books, posts, merges, suppresses or resumes. *Report* means it
measures, raises a finding or hands off a request.

| seat | act | report / check | the acting duties |
|---|---|---|---|
| accountant | 3 | 21 | receipt_intake (posts expenses), close_by_day_five (blocked), charge_recovery |
| ceo | 13 (orders) | 21 | directive, forecast_counter_action, improvement(+burn_down,+review), queue_work, report_answer, revision_refile, experiment_month, company_stage, month_plan, target_verdict, **supplier_growth (switched off)** |
| customer_support | 11 | 9 | case_idle_close, complaint_deadlines, data_requests, dead_answer_rescue, delivery_outcome_return, incident_notices, person_followup_email, public_complaints, status_chase_close, unanswered_inbound, knowledge_request_deadline (failing) |
| it_engineer | **1** | 26 | contact_dedup (merges demo groups only). game_day, load_test and dr_review are tests, not remediation |
| marketing | 6 | 13 | social_publish, social_inbox, whatsapp_supplier_invites (blocked), reputation, geo_fix, trend_decision |
| sales_engineer | 21 | 8 | outreach, onboarding, concierge, negotiation_round, quote_quality_hold, stalled_inquiry_rescue, follow-ups, invite_restart … |

### 1.3 Measured outputs, 30 days: actions against reports

| seat | ACTIONS (state changed) | REPORTS / notifications / findings |
|---|---|---|
| **it_engineer** | playbook remediations **0** · rehearsal windows closed **2** · signup_purge 5 · seed_reply 3 | it.finding handoffs **5,837** (4,747 boilerplate acknowledgements) · CEO reports 1,635 · findings tracked ≈6,400 families-rows (delivery 4,911, model_spend 959) · founder alerts 4 |
| **ceo** | growth powers applied **0 of 81** · experiments started 1 · refunds decided 11 · improvements approved 74 (all round 1) | founder briefs 30 + founder alerts 21 + board reports 5 · delivery.request receipts for support_ceo_report **1,583** · five-number reports 22 · directives 156 (63 addressed to itself, register_review) |
| **accountant** | expense entries booked **58** · journals posted **76** · customer invoices issued **0** (accountant_issued_document 0; only 1 transaction ever, pre-launch) | weekly report 5 · CEO reports 51 · month close Oct **not done** |
| **customer_support** | message deliveries completed (delivery.result) **≈6,750** · support cases 111 opened, 70 first-replied, 58 closed · bounce suppressions 3 | CEO reports 321 (91 never accepted) · knowledge.request handoffs 56 (52 stuck) · founder alerts 6 |
| **sales_engineer** | delivery.requests (customer/supplier messages) **3,237** · supplier verifications 7 · approvals 3 | CEO reports 63 · held_question 346 pending · doc_trades_held 141 pending |
| **marketing** | social posts published **0** (ceo_supplier_channel.organic_social, published_30d = 0) · supplier-reply routing 7 | marketing.report to CEO 30 · held_question 116 pending |

**The "answered" handoff is a receipt, not an action.** `fn_seat_answers_it_finding` answers every it.finding instantly
with `'<seat> acknowledged "<title>". Its playbook has no deterministic remedy … it needs a code or configuration change.'`.
The only branch that acts closes a demo rehearsal window, and it ran twice in 30 days. The receiving seats' median reply
time is therefore 0.00 h on every type. That tells you the handlers are registered. It does not tell you any work was
done.

---

## 2. IT engineer

### 2.1 Auto-remediated against left open

| measure | value |
|---|---|
| it_playbook rows | 54 |
| … with a remedy_routine | **1** (`credential_still_presented` → `fn_it_credential_reverify`) |
| playbook executions ever (`agent_runs`, job=playbook) | **0** |
| it.finding handoffs, 30 d | 5,837, of which 2 with a remedy and 4,747 "no deterministic remedy" |
| finding closures, 30 d | 6,223, all "the <duty> duty no longer finds it" (self-clearing or the condition passed) |
| it_incident, 30 d | 4,647; 4,296 tagged with a playbook class by `fn_it_learning_from_playbook` (a label, not a fix); 1,040 with not_automatable_reason |
| it_finding_closure | 219 rows, 12 open, 7 past deadline, 80 reopens |
| findings open now (non-demo) | 290 (workflow_audit 67, credential_rotation_age 40, journey 19, handoff_sla 18, delivery 16, marketing_platform_spec_freshness 13, model_spend 10, cad_read_held 10, latency_slo 8 …) |

`fn_it_playbook_first` exists and works: it runs `remedy_routine` once per occurrence and logs to `agent_runs`. Because
only one class names a routine, and that class has had no occurrence, it has never run. `fn_it_attach_learning` closes a
handoff only when cause, fix and regression check are all written, and the "fix" is text. The 27 Oct file
(`scripts/sql/the_seven_parked_it_finding_families_of_27_october_each_have_a_measured_playbook_class.sql`) gave all 7 parked
families (support_reply_sla, charge_audit, org_task_queue ×2, invite_m365_lane_refused, acct:expenses, expiry, cost_watch) a
`not_automatable_reason` and no routine.

The seat's charter forbids acting. `org_role.it_engineer.forbidden_decisions` lists deploy, code change, production
config, data mutation, job re-run, and "reporting to, or taking direction from, the CEO". These are founder rulings of
9 Sep. `ceo_standing_grant it.job_rerun` is `active = false` "because cron_registry records no idempotency fact".
cron_registry has 4 columns: jobname, human_name, category, purpose.

### 2.2 Recurring families that could be fixed safely and are not

All are operational. None touches core code, deploys, secrets or business data.

| family (30 d volume / open now) | safe automatic remedy | why it is safe |
|---|---|---|
| `duty:handoff_sla:*:unclosed` (29 / 18), plus 43 cleared it.finding handoffs to the CEO still pending | Close every handoff whose finding is already cleared. `fn_it_loop_reverify` already does this, but its walk stops after **1 second per tick** (27 Oct), so the backlog never drains. Give the close-only pass its own budget or a set-based UPDATE. | bookkeeping on agent_actions; the close rule exists |
| `duty:delivery:request:*` (4,911 / 16; 143,489 sightings) | Re-poll the provider status once at age N. After the provider's final window (Resend about 72 h, Twilio's 30-min backstop), mark the request `outcome_unknown` and close the request finding. Raise one rate finding only when the unknown share passes a threshold. | read-and-label; no message re-sent |
| `duty:model_spend:unlisted:*` (959 / 10) | When the caller is a registered edge function owned by a seat (`function_owner`), insert the it_model_consumer row with reason "auto-registered from function_owner" and re-check. Keep the finding only for callers that cannot be attributed. | the playbook remedy is literally "add the consumer"; reversible registry row |
| `duty:workflow_audit:*` (67 / 67, since 2 Nov) | Park the whole family with reason "GitHub Actions off, ledger 1564". Re-open when Actions return. | data-only; the findings describe workflows that cannot run |
| `duty:credential_rotation_age:overdue:*` (43 / 40) | Call the existing scheduled rotation for internal credentials past 90 + 7 days, then `fn_it_credential_reverify`. | the charter already says "rotation stays with the credential rotation that already runs on a schedule"; this triggers it, it does not invent one |
| `watch:queue_stalled:doc_backups_failed` (689 h) and `backup_coverage` (38 pending, since 14 Sep) | Re-queue through `fn_enqueue_doc_backups`, the remedy the `backup_gap` playbook already names. Register the `conversation_retention` source in the backup registry. | idempotent enqueue |
| `marketing:step_quarantined:*` (5 / 5, 5,961 sightings) | Re-queue the step once with a fresh run. If it fails again, hand it to marketing with the error. | bounded retry (1) |
| `duty:marketing_platform_spec_freshness:*` (13 / 13 since 23 Oct) | Re-read the source page and re-hash it. If the content diff is only cosmetic, accept the new hash. Otherwise hand it to marketing. | read-only reader refresh |
| `seat_duty:<duty>` failing with a plan-time error | Activate `it.job_rerun` after adding `idempotent boolean` + `max_reruns` to cron_registry / seat_duty, then re-run only idempotent duties once. | the founder's own condition for the grant |
| held_question backlog (822 pending, oldest 25 Sep) | Expire the ones whose subject has closed or been superseded (`fn_ceo_queue_work` already does this for CEO items; extend it to every seat). Re-ask the live ones once on a different model family, respecting review independence. | cleanup plus one bounded retry |
| `duty:org_task_queue:routine_operational_decision:*` (4 open, oldest 47 days, 71 attempts) | Map the class (§3.3). | routing only |

These are not automatable and should stay as access requests: SPF / DKIM / DMARC (DNS host account), blocklist delisting,
Meta template approval, provider outages, the M365 app credential, and the CAD reader runner
(`sales_engineer:cad_read_held`, 10 open), which needs infrastructure, so the session builds it.

These need a code fix by the session and cannot be fixed by IT:
- **`customer_support.knowledge_request_deadline`** has failed 8 runs since 1 Nov. The error is "handoff 310924
  (knowledge.request) is closed only by its originator customer_support … an unnamed caller tried to close it". The routine
  does not set `qd.handoff_closer = 'customer_support'` before `fn_seat_handoff_complete`. As a result, 52
  knowledge.request handoffs (37 to the CEO, 15 to sales_engineer) have been answered but stuck since 27 Oct.
- **`duty:latency_slo:supplier_api:error_budget`**: 30-day availability 93.05 % against 99.9 %, open since 29 Sep. This is
  real and customer-facing.

---

## 3. CEO

### 3.1 Targets

It sets them. `ceo_supplier_goal` holds 300-400 by 31 Dec. `target_path` (262 rows) and `target_daily_verdict` (663) are
evaluated daily, and `ceo_seat_directive` issues month directives (10: 1 met, 4 missed, 5 issued).
`fn_ceo_supplier_goal_status` today reads: registered 0, sent 117, delivered 106, replied 4, started 1; it would take 35,100
sends (975 a day) to reach the low target; the most reachable at the measured rate is **15**.

### 3.2 Orders issued, accepted and done (30 d)

| channel | issued | accepted (answered) | done |
|---|---|---|---|
| ceo_directive | 156 (63 to itself) | n/a | met 17 (3 of them false, at a month rollover), missed 15, escalated 41, open 80, paused 3 |
| ceo.improvement handoffs | 133 | 133 at 0.00 h | 133 closed, median 1 h (approved round 1, 123/123 all time) |
| ceo_improvement rows | 147 | – | done 82, assigned 65 |
| ceo.directive handoffs | 8 | 8 | 7 done (median close 120 h) |
| ceo.month_directive | 5 | 5 | **0** closed (all pending since 31 Oct) |
| ceo.revise | 22 | 22 | 8 done, 14 pending (revisions held, §4) |
| ceo.root_cause | 14 | 14 | 9 done, 11 pending past 2 days (oldest 29 Sep) |
| growth powers (cap / channel / reachable / trade / directive) | 81 decisions | – | **0 applied** |

Follow-up exists, but it is mechanical. Missed directives are re-issued word for word ("RE-ISSUED after the deadline …"),
and escalation goes to the CEO's own queue. None of the follow-ups changes the lever or the method. The order text is a
metric gap ("Bring registrations_submitted back to its path … Name the step … change that step"). It is not an
instruction such as "sales_engineer: verify 2,000 leads through vendor X" or "marketing: send the 45 LinkedIn targets
through the page admin".

### 3.3 org_tasks with no handler

8 rows are `assigned`. `fn_org_task_consume_tick` handles `knowledge_gap` and has no branch that can finish
`routine_operational_decision`:

| id | seat | age | attempts | title |
|---|---|---|---|---|
| 579392 / 579393 | ceo | 47 d | 71 | "Invitation: become a founding supplier…" / "x" (inbound mail, nothing to decide) |
| 579436 | ceo | 43 d | 65 | "WhatsApp templates approved — notifications are now LIVE" (a notice) |
| 581515 | ceo | 14 d | 23 | "A question about your work in the UAE" |
| 582156 | sales_engineer | 8 d | 16 | "Supplier invites paused - deliverability risk" |
| 582174 | **customer_support** | 4 d | 9 | "CEO: the AED 1M revenue forecast needs your decision" (**misrouted**; this is the CEO's) |
| 580964 / 581232 | cs / se | 16 / 14 d | 27 / 24 | knowledge_gap "I am not sure, what do you recommend?" (EN / AR) |

### 3.4 Supplier-target powers (ledger 1438 / 1455)

Built in `scripts/sql/the_ceo_holds_the_supplier_target_and_acts_within_bounded_powers.sql`:

- `fn_ceo_growth_decide` is pure and `fn_ceo_growth_act` is the hourly duty (it acts once a Dubai day). The powers are
  cap, channel, reachable, trade order and directive.
- Bounds, in order: the bounce and complaint brakes win; the ceiling rises 10 a week at most, after 14 clean days; the
  placement gate; no ads (1456); WhatsApp only with opt-in, an approved template and a HIGH rating.
- **They have never fired.** The switch `ceo_growth_act_golive = 'false'`, so every decision is written with
  `applied = false`, and the daily "run" row says "10 decisions, 0 applied, 0 reviewed; switch off".
- What the CEO would have done if the switch had been on:
  - 2-9 Nov: halved the cap every day on the bounce brake (4-11 bounces in 25-75 sends, 16 % against 5 %);
  - 3-4 Nov: closed the supplier mailbox;
  - set `invite_reachable_only = true` ("unchecked leads bounced 9 of 35");
  - put signage, civil_works, painting, flooring and interior_fitout first.
- `invite_daily_cap` is still 20, `invite_ceo_ceiling` is still 0, and `ceo_daily_number_golive` is still false.
- `ceo_supplier_channel` records the alternative channels and what each needs:
  - phone_outbound: a company UAE number with Twilio approval;
  - supplier_referral: not built;
  - linkedin_manual: a page admin;
  - email_extra_mailboxes: an M365 admin plus DNS;
  - email verification: a paid verification vendor key for the 14,202 unchecked leads;
  - whatsapp_opt_in: 0 opt-ins and the template not approved.

  None of these has become an order or an access request to the founder, which is the step ledger 1438 asks for ("Tell
  me what access they need, and they do it").

---

## 4. The approval chain

**Who approves what, today**

| item | author | approver | rule |
|---|---|---|---|
| refunds | accountant / support investigate | CEO (`fn_ceo_decide_refund`) | founder ruling; 23 decided, all round 1 |
| improvements | CEO sweep → seat | CEO (`fn_ceo_reviews_answered_improvements`, hourly) | 123 approved, 0 rejected, all round 1 |
| experiments, marketing month plan, seat deliberations | seat | CEO through `ceo_decision_round`, with reasons (1059) | **14 rejections; 0 resubmitted to approval** |
| monthly social calendar | marketing | founder (his one approval, 1059 / 1058) | – |
| blog | marketing | CEO, founder notified (1058) | **conflict:** the `marketing.article_release` duty text says "sent to the founder for 'approve'" |
| any model review | author model | a different model family (review_independence) | `review_hold`: 2 open, one since 3 Nov ("reviewer call failed: empty completion"), one 10 Nov ("no independent reviewer outside the openai families") |
| it.finding | IT → seat | the receiver acknowledges; **IT, as originator, closes** | 225 pending to the CEO (all answered; 43 already cleared and simply not closed) |

**Latency, and where it sticks**

- Receivers answer at once: median 0.00 h on every type, because the handlers are code.
- Originator close:
  - it.finding to the CEO: median 18 h, p90 139 h;
  - it.finding to customer_support: p90 345 h;
  - ceo.directive: median 120 h;
  - spec.not_sure: median 343 h.
- Stuck now, answered but not closed by the originator:
  - **IT**: 43 cleared it.finding to the CEO, 2 to SE, 4 to marketing, 3 to CS, 1 to the accountant;
  - **CEO**: 14 ceo.revise, 11 ceo.root_cause, 5 ceo.month_directive, 6 deliberation.review to the accountant, and
    3 lesson_reapproval;
  - **customer_support**: 52 knowledge.request (the code defect in §2.2) and 2 support.case_open.
- `duty:handoff_sla` has 18 open findings. The oldest is `ceo.root_cause:it_engineer:unclosed`, since 4 Oct.

**A rejection never ends the cycle (1059).** It is not working. The last decision on every one of the 14 rejected items
is still "rejected": 3 experiments, 2 marketing plans and 9 deliberations, with a maximum of 4 rounds. The revision is
written by `fn_seat_revises_for_the_ceo` through the model. When it fails 5 times it becomes a `held_question`: 27 are
pending, across marketing 11, sales_engineer 11, customer_support 3 and it_engineer 2. `ceo.revision_refile` refiles the
ask, and the ask is held again. The loop guard ("after 4 rounds: replace or withdraw, with reasons") applies only to
rounds that were decided. A revision that was never produced is not a round, so the guard never trips.

---

## 5. Accountant and customer support

### 5.1 Accountant

**Duties:** 24, all green. They cover:
- Stripe and reveal reconciliation;
- receipt intake;
- the close by day 5;
- the founder close pack;
- the cash forecast;
- VAT;
- sanctions and UBO screening;
- fraud and risk;
- runway;
- the year-end pack.

**What it did in 30 days:**
- booked 58 expense entries;
- posted 76 journals;
- sent 5 weekly reports;
- sent 51 CEO reports.

There are 0 customer invoices, but that is consistent with the stage: 1 transaction ever, and launch is January 2027.

**Gaps against 1574 / 1559:**
- **The October close is not done.** `accountant.close_by_day_five` returns `status = waiting_for_statement`, "no
  readable Mashreq statement for 2026-10 has been received". `founder_close_pack` and `receipt_bank_match` are also built
  on the bank statement, and `stripe_reconcile` matches payouts to "Mashreq statement lines". The code still treats the
  statement as the close precondition (`scripts/sql/the_accountant_books_a_late_item_as_a_prior_period_adjustment.sql`
  decides not_due / waiting_for_statement / due / closed). Ruling 1559 exists only in `founder_instruction`.
- **There is no founder-triggered "month-end email scan" event.** Nothing records "the founder asked for the scan on
  date D, the scan ran across mailboxes M, it found N receipts and booked K". The scan is a session step that the books
  cannot see.
- **`acct:mailbox:held_waiting`:** 14 receipts held more than 24 hours, 0 given an owner, 0 posted. It has been open
  since 24 Sep. The playbook classes `books_stale` and `expense_without_document` both say "the accountant posts", and no
  duty does it.
- The `v_expense_receipt_gap` view has 64 rows.
- The `cash_truth` duty reports `gl_minus_bank_aed = -3,493.09`. The book position does not reconcile to the last
  statement, and nothing reports that difference as a finding.
- The invoices-out path must be proved before January. `accountant.reveal_invoice_filing` checks that the Stripe invoice
  is filed, the portal PDF exists and a Dropbox copy is made. `accountant_issued_document` and `reveal_invoices` hold 0
  rows.

### 5.2 Customer support

**Duties:** 20, of which 11 act.

**Actions in 30 days:**
- about 6,750 deliveries completed for the other seats;
- 111 cases opened, 70 with a first reply, 58 closed;
- WhatsApp: 7 of 7 replied, median 0.6 min.

**Gaps:**
- **Email in the last case week:** 14 received, 5 replied, 9 unanswered, p90 first reply 237 min. Meanwhile
  `customer_support.unanswered_inbound` reports `email_driven: 0`. The duty and the review disagree. The likely cause is
  the 9 no-reply senders that the 27 Oct playbook describes. That cause is not established, so the next session should
  read inbound_messages for that week.
- 17 cases opened in 30 days are still open and never replied to.
- The knowledge.request chase has failed since 1 Nov, leaving 52 answers that never reach the FAQ (§2.2).
- 91 CEO reports are still `sent`, never accepted, and 224 are `accepted` but not completed.
- org_task 582174 (a CEO decision) sits in support's queue.

Customer launch is January, so most of support's real traffic today is supplier mail and the harness.

---

## 6. Verdicts

| seat | verdict | the measured reason |
|---|---|---|
| it_engineer | **NOT MET** | 0 playbook remediations ever; 1 of 54 playbooks automatable; 4,747 boilerplate acknowledgements; 290 findings open |
| ceo | **PARTLY** | sets targets and issues 156 directives and 133 improvements, but 0 of 81 growth decisions applied, orders generic, 3 false "met", 35 of its own handoffs unclosed, 4 org_tasks 47 days old |
| accountant | **PARTLY** | books expenses (58) and journals (76); the October close is blocked on a statement ruled out by 1559; 14 held receipts with no owner |
| customer_support | **PARTLY** | delivers about 6,750 messages and answers WhatsApp in under a minute; 9 of 14 emails unanswered in the week; knowledge chase broken |
| sales_engineer | **PARTLY** | 3,237 outbound messages; 0 registrations; 346 held questions, 141 document reads held |
| marketing | **NOT MET** | 0 posts in 30 days, organic channel paused, reports only (30 to the CEO) |
| approval chain | **NOT MET** | 0 of 14 rejections resubmitted to approval; originators do not close; 822 held questions with no owner |

---

## 7. Gaps ranked by "the company cannot run on its own without this", with a design for each

### G1. The CEO's bounded powers are switched off (blocks the one target of the quarter)

**Design: "CEO acts, founder funds".**
- **Lowering-side powers apply automatically.** These are the brake cap, `invite_reachable_only`, closing a channel and
  the trade order. The brakes are already the first bound, and a lowering power cannot raise risk.
- **Raising-side powers apply within the 1455 ceiling rule.** That means +10 a week at most, after 14 clean days, with
  automatic rollback when the next reading is bad.
- **`directive` becomes a concrete order to a seat, chosen from a lever catalogue:**
  - verify the next N unchecked leads;
  - add mailbox M once warmed;
  - send today's LinkedIn list;
  - ask approved suppliers for referrals;
  - submit the WhatsApp template.

  Each order carries `done_sql` on the funnel stage it moves. Every action is a `ceo_growth_action` row with baseline,
  `review_on` and verdict.
- **An access request is a first-class output.** When a lever needs something only the founder holds (a vendor key and
  its quoted cost, an M365 admin, a UAE number, a LinkedIn admin), the CEO sends **one** consolidated "access and funding
  request" through `founder_mail_policy`: what, why, the measured effect expected, and the cost. This is ledger 1438
  ("Tell me what access they need"), in place of "we are behind".
- **Guardrails:** 1456 no ads; WhatsApp only with an opt-in; no scraped numbers; the placement gate is untouched; demo
  leads are never contacted.
- **Approval:** the founder flips `ceo_growth_act_golive` **once**. After that, each decision is the CEO's.
- **Conflict to settle:** `org_role.ceo.forbidden_decisions` lists "changing a go-live switch" and "spending money
  without the founder". 1438 / 1455 delegate the cap and the channels. The founder should record that 1438 / 1455 cover
  the growth switches, and that money still needs him (the vendor key quote).

### G2. Handoffs that are answered but never closed stall every loop

**Design: one "originator closes" sweeper, `fn_originators_close_answered`, per seat.**
- Set-based. For each pending handoff with `replied_at` set:
  - re-run the type's `done_sql` or the finding check;
  - close the handoff with `qd.handoff_closer = <originator>` when the condition holds;
  - when it fails, re-open it to the receiver with the reading.
- Each seat gets its own budget, so IT's one-second walk cannot starve the CEO's.
- **Bug fix, by the session:** set `qd.handoff_closer` in `fn_customer_support_knowledge_request_tick`.
- **Guardrails:** close only on a measured predicate, never on age; every close records the reading.
- **Approval:** none. This is bookkeeping, and the predicate is the approval.

### G3. The rejection cycle has no fallback when the revision cannot be written (1059)

**Design:**
1. A revision that fails is re-asked on another model family, respecting review_independence, within 24 h.
2. If it fails again, the originator writes a deterministic revision from the CEO's reasons. For example, a marketing
   plan drops the rejected items and keeps the approved structure.
3. A held revision counts as a round, so the 1059 loop guard (round 4: replace or withdraw, with reasons) always trips.
   The founder is never in the loop.

- **Guardrails:** every round is kept, and the database refuses a decision with no reasons (already built).
- **Approval:** the CEO, as today.

### G4. CEO orders must be specific, measured on the metric and followed up by changing the method

**Design:** `ceo_directive` gets three fields:
- `lever`, from the same catalogue as G1;
- `owner_action`, a concrete instruction;
- `done_sql`, read on the metric's own value against a threshold, never on "is not in the miss list". That kills the
  month-rollover false "met" (3 of 17).

The follow-up ladder, in place of a verbatim re-issue:

| miss | step |
|---|---|
| 1 | re-issue with the reading |
| 2 | change the lever |
| 3 | reassign, or split the target across seats |
| 4 | the CEO writes a strategy change into `ceo_strategy_memo` and reports it to the founder as information |

The CEO stops sending directives to itself (`register_review`, 63) and instead runs them as its own duties.

- **Guardrails:** a directive cannot ask for anything in a seat's `forbidden_decisions`.
- **Approval:** the CEO. A seat may object once, with evidence, through deliberation.review.

### G5. The IT engineer remediates within an operational-safe class (1574)

**Design:**
- **A new grant, `it.safe_remediation`.** Each `it_playbook` row gets `remedy_routine` plus `safety` (idempotent,
  reversible, bounded) and `max_runs_per_occurrence`.
- **The families in §2.2 are the first set:**
  - close cleared handoffs;
  - delivery status re-poll and label;
  - auto-register attributable model consumers;
  - park workflow_audit under 1564;
  - trigger the scheduled internal-credential rotation;
  - re-queue doc backups;
  - re-queue quarantined marketing steps once;
  - refresh spec hashes;
  - activate `it.job_rerun` for duties marked idempotent;
  - expire superseded held questions.
- `fn_it_playbook_first` already runs a routine once per occurrence and logs it. The receiving seat's
  `fn_seat_answers_it_finding` stops sending the boilerplate. When a remedy ran, it says which; when none exists, it says
  "needs the session" and puts the item in **one** daily list for the session (G7), not one handoff per sighting.
- **Guardrails:** no deploys, no code, no schema change, no secrets (apart from triggering the existing rotation), and no
  business-data edits (leads, quotes, money). Verify after acting. Two failed remedies park the class and report it. A
  regression check is required per class.
- **Approval:** the CEO approves each new playbook routine once, as an improvement with reasons. After that it runs
  automatically.
- **Conflict to settle:** the 9 Sep charter (`org_role.it_engineer.forbidden_decisions`: data_mutation, job_rerun,
  production_config, "never repairs production itself", "not taking direction from the CEO") against 1574's "fixes the
  glitches it can fix itself (not core code)" and "an approval sequence". 1574 is later and specific, but the org_role
  text still carries the 9 Sep wording. The founder should record that 1574 supersedes those clauses for the
  operational-safe class only. Deploy, code and secrets stay forbidden. In practice the CEO already sends ceo.improvement
  (61) and ceo.root_cause to it_engineer.

### G6. The month close runs without a bank statement (1559)

**Design:**
- **The close precondition becomes "the month-end email scan is recorded".** Add `accountant_month_scan`:
  - fields: month, requested_by = founder, scanned_at, mailboxes, receipts_found, receipts_booked, receipts_unbooked
    with reasons;
  - the session writes the row when the founder says "scan";
  - the accountant closes within 2 days of it, or by day 5 on the books alone when no scan has been asked.
- **Cash position:** say "book balance, not confirmed by a statement" in place of blocking.
- **Retire or relabel** `receipt_bank_match` and the bank side of `stripe_reconcile` / `founder_close_pack` / `cash_truth`.
  Reconcile Stripe payouts against Stripe's own payout ledger.
- **Held receipts:** after 24 h with no owner, the accountant books the draft at the extracted figures, flagged
  `needs_review`, so the books are complete and the doubt is visible. A receipt it cannot read goes to the
  `expense_without_document` list for the next scan.
- **Invoices out:** before January, prove that a reveal produces the invoice, the PDF and the Dropbox copy end to end on
  a ZZ DEMO run.
- **Guardrails:** no figure without a source row; nothing invented to close a gap.
- **Approval:** the CEO reviews the close pack and the founder receives it. That is a report, not an approval.
- **Conflict:** the current code and duty text contradict 1559. The fix is code, by the session.

### G7. Work with no handler and no owner (org_tasks, 822 held questions, 141 held document reads)

**Design:**
- Every `action_class` × seat has a handler, or it is refused at insert.
  - `routine_operational_decision` gets a classifier step:
    - a notice or a mail with nothing to decide is closed as "information, no decision" with the reason;
    - a real decision is routed to its owner seat, so 582174 goes to the CEO.
- A `held_question` gets an owner seat and a deadline. On expiry it is either re-asked on another family or decided
  deterministically, with the uncertainty stated.
- **One daily "needs the session" list** goes to the founder in place of per-item mail, and only for items no seat can
  act on: code defects, infrastructure, access.
- **Guardrails:** no automatic close of a task that has a customer or supplier waiting.
- **Approval:** none for routing; the owner seat decides.

### G8. Customer support handles its own queue end to end

**Design:**
- `unanswered_inbound` must agree with `case_review`: one definition of "unanswered" for the no-reply exemption, kept in
  one place.
- A case with no reply after the SLA is answered from knowledge, or a knowledge_gap is opened with a holding reply. It is
  never left open.
- CEO reports from support close when the CEO accepts them, or after 7 days as "information, no decision needed".
- **Guardrails:** sending is unchanged (suppression, opt-out, no figure without a citation).
- **Approval:** none per reply; the CEO decides only on complaints and refunds.

### G9. Marketing acts on the supplier gap

0 posts in 30 days. The monthly calendar is the founder's one approval, so the duty must make sure a calendar is waiting
for him on day 1, and must then publish it.

LinkedIn manual outreach needs a person. That person belongs in the G1 access request, not in a report.

**Approval:** the founder approves the calendar, and the CEO approves everything else (1058).

---

## 8. Founder rulings: kept intact, and the conflicts found

Kept intact by every design above:
- 1059: a rejection never ends the cycle, and the founder is never in it.
- 1058: blogs are reviewed by the CEO; the founder approves only the monthly social calendar.
- 1455: brakes always win; the cap is the CEO's.
- 1456: no ads.
- 1564: no GitHub Actions; the session runs the gate, the applies and the deploys.
- 1559: no bank-statement reconciliation.
- 9 Sep: no human escalation queue.
- Supplier-only focus until January 2027.

Conflicts to put to the founder (or record as a supersession in `founder_instruction`):

1. **The IT charter (9 Sep) against 1574.** "Never repairs production itself", the job_rerun / data_mutation /
   production_config prohibitions, and "not taking direction from the CEO", against "fixes the glitches it can fix
   itself (not core code)" and "an approval sequence".
2. **The CEO charter against 1438 / 1455.** The CEO is forbidden "changing a go-live switch" and "spending money without
   the founder". The growth switch has stayed off, so the delegated powers have never been used.
3. **The accountant code against 1559.** The close, the receipt-bank match, the Stripe-bank match and the founder close
   pack all still require the Mashreq statement.
4. **The `marketing.article_release` duty text against 1058.** The text says the founder approves each article. The code
   path behind it was not traced in this audit.
5. **workflow_audit findings (67) against 1564.** They raise faults on workflows that the ruling switched off.

---

## 9. How each number was measured

Read-only SQL, 10 Nov 2026. Notes on the figures:
- "30 d" is `created_at` / `issued_at` / `decided_at` greater than now() minus 30 days.
- Demo rows were excluded where the table marks them: issue_key ILIKE '%demo%' and `detail.demo`.

Tables read:
- `org_role`, `seat_duty`, `resilience_step`, `it_duty_schedule`;
- `agent_actions` (kind = handoff / held_question; `detail->>'from'` is the sender and `agent` the receiver);
- `seat_handoff_kind`;
- `it_engineer_finding`, `it_finding_closure`, `it_playbook`, `it_incident`, `agent_runs`;
- `ceo_directive`, `ceo_task`, `ceo_improvement`, `ceo_seat_directive`, `ceo_growth_action`, `ceo_supplier_channel`;
- `fn_ceo_supplier_goal_status()`, `app_secrets` (switch keys only), `ceo_decision_round`, `review_hold`,
  `seat_deliberation`, `ceo_review`;
- `org_tasks`, `support_ceo_report`, `notifications` (to_role founder / admin);
- `accountant_month_close`, `expense_entries`, `gl_journal`, `accountant_issued_document`, `reveal_invoices`,
  `v_expense_receipt_gap`;
- `support_case`, `ai_cost_log`, `ceo_standing_grant`.

Routines read:
- `fn_it_handoff_sla_items`, `fn_it_playbook_first`, `fn_it_attach_learning`, `fn_it_loop_reverify`;
- `fn_seat_answers_it_finding`, `fn_org_task_consume_tick`.

Files read:
- `scripts/sql/the_ceo_holds_the_supplier_target_and_acts_within_bounded_powers.sql`;
- `scripts/sql/the_seven_parked_it_finding_families_of_27_october_each_have_a_measured_playbook_class.sql`.

Not established, and left for the next session:
- the exact count of demo groups merged by `contact_dedup`;
- why 9 of 14 emails count as unanswered while `unanswered_inbound` drove 0;
- whether `marketing.article_release` still mails the founder.
