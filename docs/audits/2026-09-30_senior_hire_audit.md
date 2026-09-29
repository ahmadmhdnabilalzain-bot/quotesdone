# Senior-hire audit of the six seats, 30 Sep 2026

**Owner:** ceo · **Ledger:** founder_instruction 1063 (task ownership) and the 24 Sep seat ownership map · **Review cadence:** monthly (`ceo.seat_audit`)

**Constraint:** the founder froze new upgrades until next week. This PR fixes only wrong owners. Everything below is a written proposal: evidence first, then the fix. No paid LLM calls were made (the model hold is on).

## How it was measured

All figures are from production (`htdblwldjkcgjvmqkbeh`), read-only, on 29 Sep 2026 at 19:23 UTC.

| Source | Rows | Rows naming an active seat |
|---|---|---|
| `seat_duty` | 83 | 83 |
| `it_duty_schedule` | 14 | 14 |
| `function_owner` | 78 | 78 |
| Deployed edge functions | 78 | 78 (every slug has a `function_owner` row; it matches the repo's 78 directories) |
| `seat_handoff_kind` | 105 | 105 |
| `cron.job` | 2 | By name only: `ceo-strategy-memo-monthly` (active) and `wa_flush` (inactive, customer_support) |

**Boundary of the measurement:**
- The run logs are `agent_runs` for the last 7 days and each duty's own `last_ok_at` and `last_result`.
- `handoff_contract` had 0 rows in the last 7 days, so seat-to-seat traffic was not measured there.
- "Zero effect" means the duty's last result had no positive count. Pre-launch that is often correct (customers start Jan 2027). It is reported as such and never as DEAD unless the duty cannot act.

## Task A: ownership

### (a) Nothing without an owner in the registries

Every duty, schedule, function and handoff kind names an active seat. Three things have no registry row, and each one's owner is known only by its name:

| Item | Evidence | Proposed fix |
|---|---|---|
| cron `ceo-strategy-memo-monthly` | Scheduled directly by `the_ceo_writes_a_one_page_strategy_memo_every_month.sql`; it is not a `seat_duty` | Register it as `ceo.strategy_memo` on the seat clock and unschedule the raw cron job. This is a behaviour change, so it waits for the freeze to lift. |
| `agent_runs` writers `backup_kick` (507 runs/7d), `brief` (7), `company_snapshot` (6), `supplier_invites` (7), `supplier_sanctions_screen` (13) | These run labels match no `seat_duty`, `it_duty_schedule` or `function_owner` key | Add a `run_label -> seat` register and a check that every `agent_runs.agent` label resolves to a seat. Proposed owners: backup_kick = it_engineer, brief and company_snapshot = ceo, supplier_invites = marketing, supplier_sanctions_screen = accountant. |

### (b) Wrong owner, fixed in this PR (owner only, behaviour unchanged)

| Item | Was | Now | Why (24 Sep map) |
|---|---|---|---|
| `seat_duty` followup (day-3/day-14 "did you hire?" after a reveal) | customer_support | sales_engineer | Reveals and their outcome belong to sales_engineer. Support "does NOT own reveals". |
| `seat_duty` concierge (first-request guidance, missing specs) | customer_support | sales_engineer | Inquiries and specs belong to sales_engineer. |
| `seat_duty` activation (no request / no quote after 3, 5 and 10 days) | customer_support | sales_engineer | Customers, inquiries and quotes belong to sales_engineer. |
| `seat_duty` winback (60-day dormant customer) | customer_support | sales_engineer | sales_engineer owns customers. Marketing owns campaigns, not one-to-one account work. |
| `function_owner` customer_followup | customer_support | sales_engineer | This is the edge function behind followup and the 60-day nudge. |

Notes on the move:
- The duty key is renamed (`customer_support.x` becomes `sales_engineer.x`) because `seat_duty_check` requires the key's prefix to match its owner.
- Routines, clocks and last-run state are unchanged. Every message still goes out through `fn_customer_support_duty_send`, so support still delivers.
- File: `scripts/sql/customer_lifecycle_duties_belong_to_the_sales_engineer_support_still_delivers.sql`. It is pending and gets applied at merge.

### Wrong owner, not fixed here (needs a code change)

| Item | Evidence | Proposed fix |
|---|---|---|
| Handoff kind `deliberation.review` customer_support -> ceo, whose meaning is "customer support's reasoned finding on a post-reveal dispute" | The dispute finding moved to sales_engineer on 24 Sep. The row is still registered. `handoff_contract` has 0 rows from customer_support of this kind. | Delete the row, or re-word it for a support-owned judgement if one exists. First confirm that no live routine writes it; `fn_customer_support_dispute_consider` still names a `customer_support.dispute` surface. |
| Routine names `fn_customer_support_{followup,concierge,activation,winback}_tick` | Their owner is now sales_engineer | Rename to `fn_sales_engineer_*` with DROPPED.txt lines, the REGISTER keys in `every_alarm_is_quiet_on_a_healthy_day`, and the knowledge pack. |
| Knowledge `knowledge/seats/customer_support.json` ("Two customer duties belong to support (instr 898)", refs `internal:seat_duty/customer_support.activation` and `.winback`) and `docs/seats/customer_support_playbook.md` | These cite the old keys | Move the lesson to `knowledge/seats/sales_engineer.json` and re-import. The playbook regenerates from `seat_duty`. |
| Accountant screening duties `fraud_watch`, `risk_screen`, `sanctions_rescreen`, `ubo_*` | These screen parties, not only money | Kept with the accountant on purpose: they gate money (a held reveal or refund). Recorded here so the choice is visible. |

## Task B: senior-hire job descriptions and gaps

**Status labels:**
- **MISSING:** a senior would do this and nothing does.
- **NOTIFY-ONLY:** the system detects the problem but does not act on it.
- **DEAD:** the duty exists but never runs or never acts.

**Duty counts are after this PR's move.** "Ran 7d" is how many duties have a `last_ok_at` in the last 7 days.

### ceo: visionary chief executive

**Job description (senior hire):**
- Sets strategy and the monthly plan per seat.
- Owns the AED 1M target path and holds every seat accountable: audits, directives, reviews.
- Decides pricing and runs experiments.
- Approves refunds and escalations.
- Sends the founder one board pack each month.

**Cadence and KPIs:**
- Weekly: target forecast and management review.
- Monthly: memo, plan, seat audit.
- KPIs: target verdicts on track, directives closed per seat, experiments with verdicts.

**Code (production):**
- 18 duties; 18 ran in the last 7 days.
- 6 had zero effect: experiment_review, improvement_review, company_stage, target_forecast, marketing_plan, month_plan.

| # | Gap | Type | Evidence | Proposed fix |
|---|---|---|---|---|
| 1 | Month plan closed 0 seats and issued 0 directives for September | NOTIFY-ONLY / possibly DEAD | `ceo.month_plan` last_result `{"month":"2026-09-01","closed":0,"issued":0,"reported":null}` | Check why no seat plan was closed on the 1st. A month with 0 issued directives should be a finding. |
| 2 | The revenue target is AT_RISK but no counter-action is tracked | NOTIFY-ONLY | `ceo.target_forecast`: verdict AT_RISK on REVENUE_AED_1M_BY_2027_10_01, remaining 1,000,000 | Each AT_RISK verdict should open a dated CEO directive to the binding seat. |
| 3 | No experiments are running | MISSING | `ceo.experiment_review` started 0, measured 0 | Once the freeze lifts, one supplier-recruitment experiment per month (the Oct-Dec supplier-only focus). |
| 4 | The strategy memo runs outside the seat clock | ownership | See Task A (a) | Register it as `ceo.strategy_memo`. |

### sales_engineer: owns suppliers and customers end to end

**Job description (senior hire):**
- Runs supplier onboarding and quality.
- Takes inquiries in; handles drawings and specs, matching, and quote QC.
- Produces the comparison report and runs reveals and their outcomes.
- Handles disputes and enterprise accounts.
- Rescues stalled inquiries and fills supply gaps.

**Cadence and KPIs:**
- Hourly to daily: pipeline duties. Weekly: quality review.
- KPIs: inquiry-to-comparison hours, share of inquiries with 3+ quotes, supplier activation rate, dispute cycle time.

**Code (production):**
- 17 duties after the move; 12 of the original 13 ran in the last 7 days.
- `enterprise_pipeline` failed on 24 Sep. Its routine was fixed on 28 Sep, and a call on 29 Sep returned `{"accounts":0,"plan_due":[]}`. It is weekly, so it recovers on its next tick (1 Oct).

| # | Gap | Type | Evidence | Proposed fix |
|---|---|---|---|---|
| 1 | 175 invited suppliers, 1 quoting | NOTIFY-ONLY | `supplier_onboarding` stages `{invited:175, quoting:1, approved:3, registering:1, action_required:2}`, nudged 0 | Invited-but-not-registered suppliers are nudged by the invite campaign (marketing), and the handoff between the two seats is not measured. Add a stage-conversion finding. |
| 2 | The supplier portal returned 175 401s and 1 503 in 7 days, and nobody owns the follow-up | NOTIFY-ONLY | `agent_runs` fn:supplier_portal: 176 of 2,533 not ok | it_engineer should classify expired sessions versus real failures, and sales_engineer should act on suppliers who hit repeated 401s. |
| 3 | `quote_extract` rejected every call (8/8, 403 wrong inbound secret) | DEAD in practice | `agent_runs` quote_extract status error 8/8: "rejected a caller with a missing/wrong inbound secret" | This is a defect for it_engineer: the caller's secret does not match. Every supplier-quote extraction is lost. Top priority after the freeze. |
| 4 | `claim_lookup` returned 165 404s in 7 days | NOTIFY-ONLY | fn:claim_lookup warn 165/778: "claim link is no longer available" | Resend a fresh claim link automatically on a 404 for a lead that is still invited. |
| 5 | Comparison KPIs are empty | pre-launch | `comparison_kpi` reports 0 | None. It is correct until inquiries flow. |

### customer_support: the communication seat

**Job description (senior hire):**
- Handles homepage chat, email and WhatsApp (the only seat with WhatsApp).
- Delivers every message for every seat.
- Owns cases, first-reply SLA, CSAT, the knowledge requests behind unanswered questions, and the root-cause loop.

**Cadence and KPIs:**
- Continuous: channels. Weekly: case review and root cause. Monthly: tone review.
- KPIs: first-reply time, unanswered rate, repeat contacts, CSAT.

**Code (production):**
- 5 duties after the move; all ran in the last 7 days.
- 1 IT-scheduled check (`whatsapp_delivery`).
- 20 functions before the move, 19 after.

| # | Gap | Type | Evidence | Proposed fix |
|---|---|---|---|---|
| 1 | 4 of 4 emails received in the week were unanswered | NOTIFY-ONLY | `case_review` (week ending 24 Sep): email received 4, replied 0, unanswered 4 | Every inbound email should get a first reply or a case within the SLA. This needs routing, not only counting. |
| 2 | 12 of 39 chat questions were not answered, and none were filed as knowledge requests by the review | NOTIFY-ONLY | `case_review` chat answered 27 of 39; knowledge still_open 12, filed_by_this_review 0 | The review should file each unanswered question. It reports `filed 0` while 12 are open. |
| 3 | WhatsApp first-reply time is not recorded | MISSING | `case_review` whatsapp `first_reply_minutes_note`: "not recorded: wa_messages writes the reply on the inbound's row with no reply time" | Add `replied_at` to the reply write. |
| 4 | `wa_templates_watch` returned 403 on 314 of 352 runs | DEAD in practice | fn:wa_templates_watch warn 314/352, "forbidden" | The Meta token or scope is missing. it_engineer should rotate or rescope it. |
| 5 | `unsubscribe` returned 400 on 125 of 146 calls | NOTIFY-ONLY | fn:unsubscribe warn 125/146 (HTML 400) | Read the requests. If these are real people, opt-outs are being lost, which is a compliance risk. |
| 6 | `wa_flush` cron is inactive | DEAD | `cron.job` wa_flush active=false | Confirm that `send_whatsapp` replaced it, then unschedule it. No job should exist without a purpose. |

### marketing: senior marketing manager

**Job description (senior hire):**
- Supplier-recruitment campaigns (Oct-Dec: suppliers only).
- Social posting, comments and insights.
- SEO/GEO blog (1 post a week, CEO reviews).
- Competitor and trend watch, reputation, and ad-spend reporting to the accountant.

**Cadence and KPIs:** daily and weekly. KPIs: suppliers registered per campaign, GEO citations, posts, cost per registered supplier.

**Code (production):** 10 duties; 10 ran in the last 7 days; 3 had zero effect (competitor_scan, month_plan, reputation).

| # | Gap | Type | Evidence | Proposed fix |
|---|---|---|---|---|
| 1 | `marketing` runs errored 203 of 301 times in 7 days, with no note | NOTIFY-ONLY | `agent_runs` marketing status error 203, note null | The error needs a reason, and a failing marketing run should be an it_engineer finding. |
| 2 | Competitor scan collects nothing | DEAD | `competitor_scan` (hourly) `{collected:0, requested:0}` | Nothing is requested, so the competitor list or fetch never starts. Fix the input list. |
| 3 | Reputation is waiting on a review link | NOTIFY-ONLY | `reputation` `waiting_for_link: true`, asks_sent 0 | Set up the review link. This is a founder-held account fact, so ask him once. |
| 4 | The social inbox fails half the time | NOTIFY-ONLY | fn:marketing_social_inbox 8/16 not ok | it_engineer should triage it. |

### accountant: everything money

**Job description (senior hire):**
- Stripe at every reveal; the expenses mailbox; refunds, invoices and charges.
- Books, bank reconciliation (Mashreq), VAT, and close by day 5.
- Runway and fraud/risk screening on money.

**Cadence and KPIs:**
- Daily: reconciliation. Monthly: close pack.
- KPIs: unreconciled lines, days to close, refund correctness, cash-truth delta.

**Code (production):** 15 duties; 15 ran in the last 7 days. 11 had zero effect, which is expected with 0 reveals pre-launch.

| # | Gap | Type | Evidence | Proposed fix |
|---|---|---|---|---|
| 1 | Stripe webhook had 5 non-ok results out of 29 in 7 days | NOTIFY-ONLY | fn:stripe_webhook 5/29 not ok; stripe_webhook 2/31 | Every failed webhook should become a reconciliation item the accountant closes. Confirm they are not the TEST-mode webhook. |
| 2 | The compliance archive refused every Terms-acceptance certificate (118 of 118) | DEAD | `compliance_archive` error 118/118: "refused to issue a Terms-acceptance certificate for qd-…cust0@e…" | These are probably fixture accounts, looping. Stop re-trying refused rows and exclude fixtures. The owner is sales_engineer (function_owner); the accountant needs the certificates for evidence. |

### it_engineer: monitors the whole platform

**Job description (senior hire):**
- Uptime, latency and SLOs; backups and DR; credential rotation; cost and model spend.
- Code health, data quality, postmortems.
- Owns every red signal until it is closed.

**Cadence and KPIs:**
- Hourly: SLOs. Daily: health. Monthly: DR.
- KPIs: open findings age, uptime, MTTR, postmortems closed.

**Code (production):**
- 18 duties: 17 enabled, all 17 ran in the last 7 days.
- 12 IT-scheduled checks.
- 52 open `it_engineer_finding` rows.

| # | Gap | Type | Evidence | Proposed fix |
|---|---|---|---|---|
| 1 | Failure clusters in `agent_runs` do not become findings | NOTIFY-ONLY | quote_extract 8/8, compliance_archive 118/118, wa_templates_watch 314/352 and login_otp 507/700 (409: one mobile number on more than one account) are all visible in the logs. Whether each has an open finding was not verified. | Add a daily duty: any `agent_runs` label with a non-ok share over 50% and more than 5 runs opens a finding for the owning seat. |
| 2 | `it_engineer.knowledge_exam` is retired but its row remains | DEAD | enabled=false; `what` says "RETIRED 24 Sep 2026" | Delete the row. A retired duty should not stay registered. |
| 3 | login_otp: one mobile number is shared by more than one account (507 warnings) | NOTIFY-ONLY | fn:login_otp 409 | This is a data defect. Dedupe the accounts, or route to sales_engineer for account merge. |

## Per-seat gap counts

| Seat | MISSING | NOTIFY-ONLY | DEAD | Ownership | Total |
|---|---|---|---|---|---|
| ceo | 1 | 2 | 0 (1 possible) | 1 | 4 |
| sales_engineer | 0 | 3 | 1 | 0 (4 fixed in) | 4 |
| customer_support | 1 | 3 | 2 | 0 (4 fixed out) | 6 |
| marketing | 0 | 3 | 1 | 0 | 4 |
| accountant | 0 | 1 | 1 | 0 | 2 |
| it_engineer | 0 | 2 | 1 | 0 | 3 |

A seat's "pre-launch" rows are excluded from the counts.

## Also observed

In `scripts/checks/customer_support_and_accountant_duties_act.test.mjs`, the production probe fails on the fraud-flag assertion:
- **Expected:** 3 flags.
- **Got:** 4. The extra flag is `free_email_company/open`, which `accountant.risk_screen` added after the check was written.

Ownership is not involved: the duty-registration assertions pass with this PR. The fix belongs to the accountant: update the expectation, or scope the probe away from risk_screen.
