# Seat qualification audit: the six seats measured against a company that must break even by June 2027

Seat: ceo · 10 Nov 2026 · founder ledger **1609** (the brief), with 1438, 1455, 1456, 1574, 1595, 1606, 1607 and 1609's
launch order. Branch `ceo-seat-qualification-audit`. Production `htdblwldjkcgjvmqkbeh` was read only: every query ran
inside a `read only` transaction through the management API (`scripts/apply_sql.mjs`'s endpoint). No model call was
made, no person was written to, nothing was applied or deployed. The four SQL changes are committed with pending notes
and rehearsed rolled back.

This report builds on `docs/reports/2026-11-10-design-seats-act-not-report.md`, written the same morning, and on the
phase-1 build that followed it (#1879, `ea8401e7f`). That build already closed the handoff stalls, the rejection cycle,
the org_task handlers, IT's safe fixes and the bank-free month close. Those items are not re-measured here. The
customer, supplier and channel journeys are being audited by other sessions in parallel, so they are left out as well.

**Founder figures, taken as given and not broken down:** about **AED 19,000** spent so far. The founder also funds
OpenRouter and keeps the subscriptions running, and nothing else.

---

## 0. The answer

| seat | verdict | the measured reason, in one line |
|---|---|---|
| **ceo** | **NOT QUALIFIED** | It holds the 24 Sep investor-model plan, not a break-even plan. Its launch rule needs all 223 trades at 10 suppliers. 0 of 101 growth decisions applied. It e-mailed the founder a second daily note with a false "sending slows down". Its own weekly verdict grades every seat, itself included, **junior**. |
| **sales_engineer** | **NOT QUALIFIED** on supply, **PARTLY** on the customer side | 137 invitations ever, 4 replies, 1 start, **0 registrations**. 30-day bounce rate 11 of 97 (11.3 %). 16,167 of 20,274 real leads are unchecked. Phone and referral channels are not built. |
| **customer_support** | **PARTLY** | About 6,750 deliveries for the other seats, and WhatsApp answered in under a minute. It owns the supplier mailbox whose bounce rate is 11.3 %. 9 of 14 e-mails went unanswered in the last case week (seats-act report). |
| **accountant** | **PARTLY** | The books agree with the founder's figure: GL expenses **AED 18,386.82**, revenue 0. The 13-week cash forecast leaves out 8 of the 10 measured recurring costs. There is no break-even line. 0 invoices out. |
| **it_engineer** | **PARTLY** | Monitors everything, recall en 0.80 / ar 0.72 (the best seat), safe fixes since phase 1. It sent 4,058 handoffs to customer_support and 1,349 to the CEO in 30 days (179 pending). The placement verdict that keeps e-mail open **expires 26 Nov**, and no duty can renew it. |
| **marketing** | **NOT QUALIFIED** | 66 posts published, the last on 21 Oct. The November and December plans have sat in `ceo_reviewing`. 0 articles live. The 2 praise comments of 6 Oct are still unanswered (`social_send_enabled = off`). 17 "comment needs a person" questions are past their deadline. Insights are read daily (3,061 rows). |

**Is break-even by 30 June 2027 reachable?** **No, not with the current model and the measured conversion.** The case
in §D:

- **The cost to cover is AED 42,500-46,900 by 30 Jun 2027.**
  - AED 19,000 founder figure.
  - Plus 7.67 months of measured running cost at AED 2,915-3,487 a month.
  - Plus the trade-licence renewal due 24 Jun 2027 (AED 1,200 last time).
- **The revenue model as built is the 3 % reveal fee only.** The supplier subscription starts at supplier #1,001, and
  there is no commission. Net of Stripe, a reveal on a quotation of value Q earns 0.0289 × Q − 1.05 AED.
- **What January to June must deliver:**
  - 68-163 reveals in total, which is 11-27 a month;
  - 84-181 customer requests a month, at the plan's assumed 15 % reveal rate;
  - supply of at least 10 verified suppliers in every trade those requests come from.
- **What the measured channel delivers:** the e-mail channel, at the measured 0.79 % start rate, yields about 60
  suppliers by June at the warm-up ceiling. Today only the Google mail class (2,751 never-invited addresses, 751
  checked) is open.
- **What blocks it outright:** the CEO's launch rule (`fn_ceo_launch_readiness`: "Customers launch only when every
  trade is covered") keeps customers out until 2,230 suppliers exist.

What would make it reachable is ranked in §E.2.

**What this session built** (4 commits, all pending, all rehearsed):

1. **ceo:** the CEO's safety-side growth powers apply without waiting for the switch, and the brake floor keeps the
   rate measurable.
2. **ceo:** the CEO note is no longer mailed to the founder; the daily brief is his one daily message.
3. **ceo:** the daily-run job description says so too.
4. **marketing:** the article-release job description names the CEO as approver (ledger 1058), with a check that no
   duty names the founder as an approver he has retired.

---

## A. The seats

How each seat is read:

- **Duties:** `public.seat_duty`. 157 rows in total, of which 36 are ceo, 29 sales_engineer, 20 customer_support,
  24 accountant, 29 it_engineer and 19 marketing. Each duty has its own interval, and 99 `cron.job` rows drive them,
  including 83 `seat_duty:*` own-job crons. The `resilience_ping` steps are in `public.resilience_step` (45 rows, 13
  columns, `owner_seat`).
- **Knowledge:** the seat's own pack table, plus `seat_knowledge_recall` (the free retriever test, latest complete day
  22 Oct) and `seat_self_review`.
- **Powers:** `ceo_standing_grant`, the seat's typed routines and the app_secrets levers it writes.
- **Model and cost:** `ai_cost_log`, real traffic only (`e2e_run_tag is null`), in AED.
- **Links:** `agent_actions` of kind `handoff` over 30 days, from `detail->>'from'` to `agent`.

**Common to all six seats:**

- **Every monthly self-review since October reads `no_exam`.** The seat-exam files exist in the repository:
  `knowledge/exams/{ceo,marketing,accountant,it_engineer,customer_support,sales_engineer}.json`, with 119 / 78 / 109 /
  109 / 96 / 122 items. They were never loaded into the table `seat_self_review` reads. 12 rows across Oct-Nov carry
  the advice "write knowledge/exams/<seat>.json … and load it".
- **`ceo.senior_verdict` of week 2026-11-09 grades all six seats `junior`.** Its `last_result.levels` holds one value
  per seat.
- **The model-graded exam (`seat_knowledge_exam`) was retired on 24 Sep.** Its 12 rows read "retired unanswered".
  `it_engineer.knowledge_pass_rate` therefore grades 0 items a month on every seat: it measures nothing.

### A.1 CEO

**1. The job.** At a UAE B2B procurement marketplace that has spent AED 19k and must reach break-even by June 2027, the
CEO:

- owns one number, cumulative net revenue against cumulative cost;
- picks the few trades and the channels that can get there;
- turns that into a monthly order per seat with a measured done test;
- reads the result weekly and changes the method when a number does not move;
- holds the safety limits so growth never costs the domain, the WhatsApp number or the money;
- approves or rejects other seats' work with reasons;
- never asks the owner anything an executive should decide.

**2. The standard.**

| # | requirement |
|---|---|
| C1 | A plan that shows cumulative revenue against cumulative cost to 30 Jun 2027, rebuilt from measured rates |
| C2 | Launch and category decisions that let revenue start (no rule that cannot be met) |
| C3 | Orders to seats that name the lever, the owner action and a done test on the metric itself |
| C4 | Weekly check of every order; a missed order changes the lever, not the date |
| C5 | Acts within the safety limits without waiting for the founder; never exceeds them |
| C6 | Sends the founder only what he asked for or what only he can do, never a question or a known fact |
| C7 | Knowledge enough for those calls: marketplace cold start, unit economics, deliverability, WhatsApp tiers |
| C8 | Spends model money like a CEO who knows the balance is USD 29 |
| C9 | Approvals with reasons that change the work (not a rubber stamp) |

**3. What it has today.**

- **Duties:** 36, all enabled, 0 failing.
  - Hourly: directive, improvement_review, queue_work, report_answer, supplier_growth, daily_number, org_task_handlers,
    close_answered_handoffs.
  - Daily: company_stage, daily_run, directive_review, experiment_month, five_number_report, market_report,
    marketing_plan, month_close, month_plan, register_review, revision_refile, self_review, strategy_memo,
    supplier_target, target_verdict.
  - Weekly: constraint_lever, experiment_review, forecast_counter_action, improvement, improvement_burn_down,
    launch_readiness, management_review, pricing_evidence, pricing_monitor, refund_decision_metric, seat_audit,
    senior_verdict, target_forecast.
  - Resilience steps: ceoDecisions, ceoPlan, ceoWeekly, ceoWeeklyReview, digest, orgtasks.
- **Knowledge:**
  - `ceo_knowledge` 798 rows, 28 domains, imported 7 Sep-10 Nov, 0 without a vector.
  - Coverage, measured by term (`ilike`, 10 Nov):
    - "break-even" 9, "runway" 27, "unit economics" 15, "liquidity" 18, "chicken" (cold start) 4.
    - **"warm-up" 0**, "domain reputation" 0, "bounce rate" 1.
    - The CEO owns the invitation cap (ledger 1455) and has no entry on how a sending domain is warmed.
  - Recall (22 Oct): en 0.608, ar 0.556, the lowest of the six seats.
- **Powers:**
  - `fn_ceo_growth_decide` / `fn_ceo_growth_act` (cap, ceiling, reachable-only, channel, trade order, directive),
    clamped to ledger 1231's schedule and 1455's +10 a week ceiling.
  - `fn_ceo_decide_refund`, the improvement and deliberation approvals, and `fn_ceo_directive_issue`.
  - **The growth powers have never acted.** `app_secrets.ceo_growth_act_golive = false` since 2 Nov, and
    `ceo_growth_action` holds 101 rows, 0 applied.
- **Model and cost:**
  - Opus 5.5 for hard tasks, Luna Pro otherwise (ledger 1056 / #1879).
  - 30 days of real traffic: AED 212.72, of which Opus 499 calls is AED 203.45. That is **the largest seat model
    line**.
  - Last 7 days: AED 1.13 a day.
- **Links (30 days):**
  - ceo → customer_support 1,711 (mostly delivery requests); ceo → it_engineer 77, → accountant 53,
    → sales_engineer 49, → marketing 43.
  - Received: customer_support → ceo 1,702; it_engineer → ceo 1,349 (179 pending); marketing → ceo 34;
    sales_engineer → ceo 4.
- **The plan it holds:**
  - `ceo_year_plan` (12 months) is the 24 Sep investor model ("founder targets 24 Sep 2026 (ledger 971)"), with a cost
    ceiling of AED 18,598 a month. That ceiling includes the founder's AED 10k fee and AED 5k of ads, neither of which
    is in ledger 1609's break-even.
  - It plans 325 verified suppliers in January 2027, 13 reveals and AED 8,400 of fees. Measured today: **0** registered.
  - The plan's demand rule (`scripts/checks/the_ceo_year_one_plan_follows_the_founder_targets.test.mjs` `plan()`):
    requests = 20 % of verified suppliers; reveals = 15 % of those; fee AED 390 per reveal (Q = AED 13,000).
- **Launch rule:** `fn_ceo_launch_readiness` decides from 1 Dec 2026 ("Customers launch only when every trade is
  covered"). `ceo_launch_gate` 2026-11-09 reads 0 of 223 trades ready.

**4. Verdict per requirement.**

| # | verdict | evidence |
|---|---|---|
| C1 | **NOT** | no break-even target in any `ceo_*` table; the plan is the 24 Sep model with a founder fee and ads in its cost line, and 325 suppliers in Jan against 0 measured |
| C2 | **NOT** | `fn_ceo_launch_readiness`: "every trade" × `pricing_config.category_open_min_suppliers = 10` = 2,230 suppliers before any customer |
| C3 | **PARTLY** | directives carry `done_sql`, but the text is a metric gap (seats-act report §3.2) and the supplier-growth directives never issued (switch off) |
| C4 | **PARTLY** | a missed directive is re-issued word for word; `ceo_supplier_channel.access_needed` lists 4 blocked channels that never became an order |
| C5 | **NOT → fixed in part** | 0 of 101 growth decisions applied, including 8 days of bounce-brake cuts; fixed by commit 1 (safety side) |
| C6 | **NOT → fixed in part** | 7 "CEO note" e-mails in 14 days on top of the brief, one with a false remediation claim; fixed by commits 2-3. §B lists the rest |
| C7 | **PARTLY** | cold start and unit economics present; 0 deliverability or warm-up entries; recall 0.61 / 0.56 |
| C8 | **PARTLY** | Opus at AED 203 in 30 days is the biggest real seat spend; the balance is USD 29.18 (`v_openrouter_position`, 10 Nov 19:46Z) |
| C9 | **PARTLY** | 123 of 123 improvements approved in round 1 (seats-act report); November and December marketing plans sit in `ceo_reviewing` (`marketing_month_plan`), so the CEO is the bottleneck on the one item the founder approves |

**5. Duplicated work.**

- **Six CEO duties grade the same supplier funnel**, and each can open its own task or directive for the same miss:
  - `ceo.supplier_target` (daily);
  - `ceo.supplier_growth` (daily);
  - `ceo.target_verdict` (daily);
  - `ceo.directive` (hourly, from target misses);
  - `ceo.forecast_counter_action` (weekly);
  - `ceo.target_forecast` (weekly).
- `ceo.pricing_evidence` and `ceo.pricing_monitor` are both weekly and both read requests, quotes and reveals.
- **Two weekly founder reports:** `ceo_weekly_review` and `board_report`, 2 each in 14 days.

**6. Missing duties.**

- A break-even ledger: monthly measured net revenue against the accountant's measured cost, to 30 Jun 2027 (proposal
  P2).
- Category-by-category launch (P1).
- One consolidated access-and-funding request with costs, on a schedule (P4).
- A deliverability knowledge entry: the warm-up curve, bounce and complaint thresholds, Microsoft and Google bulk
  rules.
- A planned GlockApps re-test before 26 Nov (§C).

### A.2 Sales engineer

**1. The job.** The sales engineer owns both sides (founder, 24 Sep). It recruits, verifies and activates suppliers
trade by trade to the plan's coverage. It keeps the list clean so the domain survives. It runs intake, matching,
quotes, comparison and reveals for customers, and it turns every reply and every stalled registration into a
completed one.

**2. The standard.**

| # | requirement |
|---|---|
| S1 | Verified suppliers to the plan's per-trade coverage, on the plan's dates |
| S2 | Invitation list quality: bounce under 2 %, every address checked before it is mailed |
| S3 | Every supplier reply answered within a working day |
| S4 | Every started registration chased to submission |
| S5 | At least three acquisition channels beyond cold e-mail |
| S6 | Trade knowledge deep enough to qualify an inquiry in any trade |
| S7 | Customer side: intake, matching, quotes, comparison and reveal proved in the sandbox |

**3. What it has today.**

- **Duties:** 29, all enabled, 0 failing. Among them:
  - supplier_outreach (15 min);
  - lead_email_check (5 min, free checks: syntax, typo domains, DNS);
  - invite_restart (5 min);
  - supplier_reply_followups (15 min);
  - supplier_onboarding (daily);
  - supply_gap and supply_gap_recruitment (daily);
  - the customer-side duties: concierge, comparison_report, negotiation_round, reveal_followup, stalled_inquiry_rescue
    and others.
  - Resilience steps: ladder, specoffer.
- **Knowledge:** `sales_knowledge` 8,992 rows, 264 domains (the trade packs, 223 trades). Recall en 0.719, ar 0.592.
- **Powers:** `sales.intake`, `sales.matching`, `sales.dispatch`, `sales.scope_validation`.
  `sales.invitation` was issued inactive on 9 Sep for want of consent records; the invitation route runs through the
  outreach golive switches instead.
- **Model and cost:** Luna Pro, with Sonnet as fallback and Opus for the comparison. 30 days of real traffic AED 95.94;
  last 7 days AED 0.81 a day.
- **Links:** → customer_support 3,785 (deliveries) and ← 3,784; → accountant 7 (refund requests); → ceo 4; and
  **0 handoffs to marketing**, while marketing → sales_engineer has 8.

**4. Verdict per requirement.**

| # | verdict | evidence |
|---|---|---|
| S1 | **NOT** | `fn_ceo_supplier_goal_status()` 10 Nov: sent 137, delivered 126, replied 4, started 1, submitted 0, registered 0; most reachable at the measured rate: 12 against 300 |
| S2 | **NOT** | `fn_invite_send_health`: 30 d 11 bounced of 97; 7 d 3 of 40; unchecked leads bounced 9 of 35 (CEO reading); 16,167 of 20,274 real leads carry no `email_verified` |
| S3 | **QUALIFIED** | the CEO reading's `replied_unanswered = 0` |
| S4 | **NOT** | `started_stuck = 1`; the chase directive was decided daily and never issued (switch off) |
| S5 | **NOT** | `ceo_supplier_channel`: phone_outbound missing, supplier_referral missing, linkedin_manual missing (needs a person), whatsapp_opt_in blocked (0 opt-ins, template not approved), email_extra_mailboxes missing |
| S6 | **QUALIFIED** for the packs, **PARTLY** on Arabic | 8,992 records; recall 0.72 / 0.59 |
| S7 | **PARTLY** | built and walked in the sandbox (memory, checkpoints of 10 Nov); the journeys are another session's audit |

**5. Duplicated work.** Three seats build per-trade gap lists, and the outputs do not travel as handoffs:

- sales_engineer: `supply_gap`, `supply_gap_recruitment` and `demand_forecast`;
- marketing: `gap_recruitment_plans` (227 rows), `recruitment_funnel` and `manual_outreach_targets`;
- the CEO: `supplier_growth` trade order.

**6. Missing duties.**

- The referral ask at approval, with a code per referrer.
- The founder's own network intake (ledger 971: 50 within 2 weeks; never instrumented).
- A per-company second address when the first bounces.
- An order from the CEO naming the trades that open first (P1).

### A.3 Customer support

**1. The job.** The communication seat (founder, 24 Sep). It covers the homepage chat, the e-mail and WhatsApp
channels and every message the other seats send. It answers every inbound within its SLA. It owns the health of the
channels it sends on: suppression, bounce and complaint handling, and the WhatsApp quality rating.

**2. The standard.**

| # | requirement |
|---|---|
| CS1 | Every inbound e-mail and WhatsApp answered within the SLA |
| CS2 | Every other seat's message delivered with a verified outcome returned |
| CS3 | The sending channels kept healthy: bounce under 2 %, complaints under 0.1 %, WhatsApp HIGH |
| CS4 | Knowledge gaps it finds closed into the FAQ |
| CS5 | Only an explicit request for a person reaches the founder (ruling 1264) |

**3. What it has today.**

- **Duties:** 20, all enabled. `knowledge_request_deadline` was failing before phase 1 and its last result now reads
  "closed 50, still open 12".
  - Resilience steps: outbox, whatsapp, ratings, deliveryCanary, supportCampaignList, supportVoice.
- **Knowledge:** `support_knowledge` 730, 35 domains; recall 0.730 / 0.590.
- **Powers:** `support.reply`, `support.notify`, `support.document_intake`, `support.refund_investigate`.
- **Model and cost:** Sonnet 5.5 (1,828 real calls, AED 172.15 in 30 days) and Luna. AED 1.57 a day over the last
  7 days, the highest of the six seats.
- **Links:** the hub. It receives 4,058 from it_engineer, 3,785 from sales_engineer and 1,711 from the CEO; it sends
  3,784 to sales_engineer and 1,702 to the CEO.

**4. Verdict per requirement.**

| # | verdict | evidence |
|---|---|---|
| CS1 | **PARTLY** | WhatsApp 7 of 7 replied, median 0.6 min; e-mail 9 of 14 unanswered in the last case week (seats-act report §5.2) |
| CS2 | **QUALIFIED** | about 6,750 deliveries in 30 days; `delivery_outcome_return` every 15 min |
| CS3 | **NOT** | `ceo_supplier_channel.email_supplier_mailbox.owner_seat = customer_support`; 11.3 % 30-day bounce on it; the brakes that read it belong to sales_engineer and the CEO |
| CS4 | **PARTLY** | 50 of 62 knowledge requests closed since phase 1, 12 open |
| CS5 | **QUALIFIED** | 4 person-request mails and 4 WhatsApp in 14 days, all of kind person_request / whatsapp_human_request |

**5. Duplicated work.** Delivery health is read four times:

- `customer_support.delivery_health`;
- `customer_support.delivery_outcome_return`;
- the `deliveryCanary` step;
- IT's `duty:delivery:*` findings (4,911 families in 30 days, seats-act report).

**6. Missing.** The seat that owns the mailbox has no duty of its own on that mailbox's bounce rate.

### A.4 Accountant

**1. The job.** Everything financial. That covers:

- the books;
- the monthly close from the month-end receipt scan (ledger 1559);
- the 13-week cash forecast with every recurring cost;
- Stripe reconciliation and invoices out at every reveal;
- the non-response charge;
- VAT thresholds;
- and, for this company now, **the break-even tracker the CEO plans against**.

**2. The standard.**

| # | requirement |
|---|---|
| A1 | Books complete: every receipt booked, the P&L matches the founder's own figure |
| A2 | A cash forecast that carries every recurring cost the books show |
| A3 | Monthly cost and run-rate per vendor, measured, handed to the CEO |
| A4 | An invoice, a PDF and a Dropbox copy for every reveal, proved before launch |
| A5 | VAT and licence deadlines held as dated tasks |
| A6 | OpenRouter spend booked per day against the provider's meter |

**3. What it has today.**

- **Duties:** 24, 23 enabled (`receipt_bank_match` was retired by ruling 1559), 0 failing.
  - Resilience steps: accountantDuties, refunds, vat, weekly.
- **Knowledge:** `accountant_knowledge` 403, 52 domains; recall 0.782 / 0.581.
- **Model and cost:** AED 42.62 in 30 days (Sonnet 308 calls); AED 0.00 over the last 7 days.
- **Links:** → sales_engineer 29 (reveal and refund events); ↔ customer_support 5 each; **0 handoffs to the CEO in
  30 days**. Its reports go by e-mail and report tables.

**4. Verdict per requirement.**

| # | verdict | evidence |
|---|---|---|
| A1 | **QUALIFIED** | `gl_pnl`: 6000 Software & AI AED 16,508.21 + 6300 G&A AED 1,878.61 = **AED 18,386.82**; revenue 0; agrees with the founder's ~19,000 within the receipts not yet forwarded |
| A2 | **NOT** | `accountant_cash_forecast_week` 2026-11-09 flows: OpenAI 799, Anthropic 799 and the Mashreq fee 199 + 9.95 only. It leaves out Supabase (Aug-Oct average AED 319), Vercel (Oct AED 334.79), GoDaddy/M365 93.80, Resend 73.45, GlockApps 65.50, Twilio 36.76, Google 26.99 and OpenRouter (Oct AED 753.29), all of them booked in `expense_entries` |
| A3 | **PARTLY** | per-vendor receipts exist; no run-rate row the CEO reads; `budget_lines` is AED 2,553 a month of cost and AED 6,250 a month of revenue from Jan 2027, an older budget |
| A4 | **PARTLY** | `accountant.reveal_invoice_filing` exists; `accountant_issued_document` holds 0 rows (seats-act report) |
| A5 | **QUALIFIED** | `v_company_subscriptions` holds the licence (24 Jun 2027), domains (7-8 Jun 2027), TLS and keys with `renews_on`; `accountant.vat_threshold` daily against 187,500 / 375,000 |
| A6 | **QUALIFIED** | `openrouter_day` per day `authoritative_basis = measured`; an `expense_entries` row per day (34 OpenRouter AED rows since 7 Oct) |

**5. Duplicated work.** `accountant.cash_truth` and `accountant.cash_forecast_weekly` read the same opening balance.

**6. Missing duties.**

- Forecast completeness: every vendor with 2 or more receipts in 120 days becomes a recurring flow.
- The break-even line (P2).
- Stripe live activation as a dated owner-only task before the customer launch (§B).

### A.5 IT engineer

**1. The job.** It monitors everything, fixes what is operationally safe, and keeps the sender reputation, the
credentials, backups, uptime and model spend inside their limits. It brings each seat the few findings that seat can
act on, and gives the session a single list of what needs code.

**2. The standard.**

| # | requirement |
|---|---|
| I1 | Every production surface monitored with a measured SLO |
| I2 | Safe faults fixed by itself (ruling 1574), audited |
| I3 | Findings reach a seat at a rate the seat can act on |
| I4 | Deliverability technical state (SPF, DKIM, DMARC, placement verdict) never lapses |
| I5 | Cost watch over every provider, weekly |

**3. What it has today.**

- **Duties:** 29, 28 enabled; 13 `it_duty_schedule` perimeter checks.
  - Resilience steps: it, itdetect, itduties, itintegrations, itlater, itscheduled, openrouter, dropboxHealth,
    vercelSnapshot, seatDuties and others.
- **Knowledge:** 431 rows, 59 domains; recall 0.804 / 0.716 (the best seat).
- **Model and cost:** Luna Pro (1,597 calls) and Sonnet. AED 39.45 in 30 days; AED 0.92 a day over the last 7 days.
- **Links:** → customer_support 4,058, → ceo 1,349 (179 pending), → sales_engineer 520 (30 pending), → accountant 252,
  → marketing 139 (32 pending).

**4. Verdict per requirement.**

| # | verdict | evidence |
|---|---|---|
| I1 | **QUALIFIED** | uptime, latency, perimeter, model-spend, backup and DR duties all with `last_ok_at` inside their intervals (0 stale) |
| I2 | **PARTLY** | `it_engineer.safe_fix`, 8 families since phase 1; the 10 Nov digest still lists 178 overdue postmortem questions on its own seat |
| I3 | **NOT** | 1,349 handoffs to the CEO in 30 days, 179 pending; 32 pending at marketing |
| I4 | **NOT** | the only placement verdict is GlockApps `2026-10-27-22:50:26:837t`: google 25 of 25 inbox, microsoft 0 of 18, so only google is open (`fn_invite_placement_open_providers()`); "a verdict is good for 30 days", so on **26 Nov 2026 ~22:50Z no class is open** and invitations stop. The test needs the session's GlockApps connector and a credit; no seat duty can run it |
| I5 | **QUALIFIED** | `it_engineer.cost_watch` weekly; `openrouter_unattributed` daily |

**5. Duplicated work.** `knowledge_recall`, `knowledge_pass_rate` (measuring 0 graded items),
`sales_engineer.knowledge_gap_sweep` and `customer_support.knowledge_request_deadline` all measure knowledge.

**6. Missing.** A dated placement re-test plan, raised to the session list 7 days before expiry. A rate limit on
findings per seat per day.

### A.6 Marketing

**1. The job.** The ruling of 1609 is that content is designed with the founder and handed over. Marketing then:

- schedules and publishes it on working days;
- **answers every comment and DM**;
- reads the insights and says what works;
- runs SEO and GEO through one market article a week (the CEO reviews it, ledger 1058);
- builds the January customer launch plan;
- recruits suppliers through every non-email channel the rules allow.

**2. The standard.**

| # | requirement |
|---|---|
| M1 | The approved calendar published on UAE working days, with no gap month |
| M2 | Every comment and DM answered within 2 working hours |
| M3 | Insights read daily and turned into a weekly "what works" |
| M4 | One market article a week live (CEO-approved) |
| M5 | Supplier recruitment beyond e-mail (LinkedIn, WhatsApp opt-in, social) |
| M6 | No paid spend (ledger 1456) |

**3. What it has today.**

- **Duties:** 19, all enabled. Resilience steps: marketing (kicked), marketingChannels, marketingOutreach.
- **Knowledge:** `marketing_knowledge` 286, all imported 10 Nov, 13 domains; recall 0.706 / 0.613.
- **Model and cost:** Luna Pro 1,959 calls; AED 45.58 in 30 days; AED 1.52 a day over the last 7 days.
- **Links:** → ceo 34, → sales_engineer 8; ← ceo 43; ← it_engineer 139 (32 pending).
- **Switches:** `marketing_golive = false`, `social_send_enabled = off`, `social_model_enabled = off`,
  `meta_autospend_golive = false`.

**4. Verdict per requirement.**

| # | verdict | evidence |
|---|---|---|
| M1 | **NOT** | `marketing_post`: 66 published, last 21 Oct; `marketing_month_plan` 2026-11 and 2026-12 are both `ceo_reviewing` |
| M2 | **NOT** | `social_message`: 19 rows, 6-12 Oct; 2 `praise` marked `reply_held`; 2 outbound `held_switch_off`; the 10 Nov IT digest: "17 question(s) … comment needs a person were not answered by their deadline" |
| M3 | **QUALIFIED** | `marketing_insight_day` 3,061 rows, 21 Sep to 9 Nov; `kpi_scorecard` daily |
| M4 | **NOT** | `marketing_article`: 0 live, 1 approved (13 Oct) unreleased, 5 withdrawn |
| M5 | **NOT** | WhatsApp 0 opt-ins; LinkedIn needs a person with page admin; organic social paused |
| M6 | **QUALIFIED** | `meta_autospend_golive = false`; `ceo_supplier_channel` has no ad channel |

**5. Duplicated work.** The gap lists (see A.2). Also two plan loops: `ceo.marketing_plan` (the CEO checks that the plan
reached it) and `marketing.month_plan` (marketing mails it), and neither unsticks a plan that sits in `ceo_reviewing`.

**6. Missing duties.**

- Answering the 2 praise comments (a canned reply from `social_reply_library`, 13 rows).
- An escalation when its own month plan has waited on the CEO for more than 3 days.
- The January customer-demand plan per category that opens (P1).

---

## B. Decision flow: what reaches the founder

### B.1 What reached him, 28 Oct - 10 Nov (14 days)

Rows in `notifications` addressed to `to_role` founder or admin, to one of the inboxes `fn_is_founder_own_inbox` names,
or to his mobile: **50 rows, 48 sent**.

| kind | e-mail | WhatsApp | asked by him? | what it is | who should own it instead |
|---|---|---|---|---|---|
| founder_brief, "QuotesDone daily brief" | 14 | – | yes (policy) | daily report; "Nothing here needs a reply" | keep |
| founder_brief, **"[Attention] CEO note"** (`fn_ceo_daily_run`) | **7** | – | **no** | repeats the brief's facts; 5-9 Nov "sending slows down" was false; 5-6 Nov "on hold by your decision" was false (invite_enabled true since 28 Oct) | **CEO keeps it on the day: fixed, commit 2** |
| supplier_campaign_daily_list | 3 | – | yes (24 Sep) | tomorrow's invitees PDF | keep (information) |
| ceo_weekly_review | 2 | – | yes (1009) | weekly PDF | keep; merge with board_report (P6) |
| board_report | 2 | – | yes | weekly | merge (duplicate of the above) |
| accountant_weekly_report | 2 | – | yes (9 Sep) | finance PDF | keep |
| person_request | 2 | 2 | ruling 1264 | a visitor asked for a person | keep (his ruling) |
| whatsapp_human_request | 2 | 2 | ruling 759 | same, on WhatsApp | keep |
| refund_ceo_summary | 2 | 2 | policy | "Refund mismatch on reveal #30e17bdd … Refunds and supplier charges stay PAUSED" | CEO decides; founder told after. Keep as information only |
| ceo_market_report | 1 | – | yes (1019) | monthly | keep |
| ceo_strategy_memo | 1 | – | yes (1013) | monthly | keep |
| integration_reauth_needed | 1 | – | 979 | "reconnect needed: virustotal" | **owner-only** (account holder); schedule, batch into P4 |
| it_daily_digest | 1 | – | 642 | "No decision of yours is needed today. What a working session must fix …" | a session's to-do list, not his; deliver to the session (P5) |
| support_case_closed / support_csat_request | 2 | 2 (skipped) | – | a case he opened himself | test traffic; no change |

### B.2 Every path in code that can reach him

`pg_proc` source matching `fn_notify_founder(`, `'recipient_role', 'founder'` or `to_role … founder` gives **54
routines**. The `a10_notifications_founder_mail_policy` trigger refuses any founder-bound row whose kind is not one of
the **38 allowed kinds** of `founder_mail_policy`; unlisted kinds are routed to a seat.

**What asks him something or puts a decision on him, and what replaces it:**

| path | asks / decides | legally owner-only? | replacement |
|---|---|---|---|
| `fn_ceo_daily_run` → CEO note (kind founder_brief) | unasked report | no | **built:** kept on `ceo_day.matters`, never mailed |
| `fn_ceo_growth_act` behind `ceo_growth_act_golive` | a switch only he flips, holding the CEO's brakes | no (ledgers 1438 and 1455 delegate the cap) | **built:** safety-side applies without the switch. The raising side still waits for it (P3) |
| `marketing.article_release` duty text "sent to the founder for approve" | stale approval | no (1058) | **built:** CEO named; check added |
| `marketing.month_plan` / `marketing_calendar` | his one approval (1059) | no, but his ruling | keep; content is designed with him (1609) |
| `marketing.launch_plan`, "sent for approval from 1 December" | an approval | no; his 28 Sep ruling | conflicts with 1609 ("no decision goes to him") → **P7: his call to record** |
| `fn_ceo_launch_readiness` (kind founder_brief, from 1 Dec) | a notice of the CEO's launch decision | no | keep as a notice; the rule itself is the problem (P1) |
| `ceo.pricing_monitor` "a proposal goes to the founder" | pricing proposal | **yes**: pricing is in the signed T&C | keep as a scheduled item, only at 20+ quoted requests |
| `fn_marketing_outreach_deliver` (marketing_outreach_list) | asks him to send LinkedIn messages by hand | no (LinkedIn forbids automation; it needs a person) | dormant while `marketing_golive` is false; replace with an access request for a page admin (P4) |
| `fn_ceo_it_escalation_decide`, `fn_it_ceo_silence_watch`, `fn_customer_support_sends_the_it_digest` (kind it_new_bug / it_daily_digest) | "a working session must fix" | no | deliver to the session-start list, not his inbox (P5) |
| `fn_openrouter_low_balance_tick` (finance_reminder) | "TOP UP OPENROUTER NOW" | **yes**: he funds OpenRouter | keep; it is the funding task he kept |
| `fn_it_integration_settle` (integration_reauth_needed) | reconnect an account | **yes**: account holder | keep, batched (P4) |
| `fn_action_invoke_dispatch` (spend_approval_needed) | spend approval | money; but no spend exists (1456, 1606) | dormant |
| `fn_backup_watch`, `fn_site_uptime_tick`, security_critical | emergencies | no | keep; emergencies he asked for (642) |

**Legally owner-only items, which become dated planned tasks rather than surprises.**

| item | date | where it lives today | gap |
|---|---|---|---|
| Trade licence renewal (DET 1633275) | **24 Jun 2027**, inside the break-even window; AED 1,200 last time | `v_company_subscriptions` (owner ceo) | none |
| Domains quotesdone.com and quotesdone.ae | 7-8 Jun 2027 | same | none |
| Stripe live activation (KYC, bank) | before the first live reveal | **nowhere** | the 10 Nov ruling keeps Stripe in test payments, and the launch order puts Stripe last; no dated task exists (P4) |
| VAT registration | voluntary at AED 187,500, mandatory at AED 375,000 | `accountant.vat_threshold` | none; not reachable before June |
| TDRA NOL | 14 Sep 2027 | `v_company_subscriptions` | none |

---

## C. Guardrails: what can harm the company, and what stops it in code

| harm | hard limit in code / SQL today | can the CEO or a seat exceed it? | gap |
|---|---|---|---|
| **E-mail volume against warm-up** | `invite_daily_cap` 20; `invite_warmup.ceiling_cap` 50, ramp ×1.5 only at ≥80 % used and bounce < 2 %; `fn_invite_founder_cap` = the ledger 1231 schedule (20→30→40→50) or the CEO ceiling; `fn_ceo_growth_act` clamps every cap with `least(to, founder_cap)` and the ceiling with `founder_cap + 10`; `daily_send_cap` 400 for all e-mail in `send_outbox` | **No.** "100 invitations a day" cannot be written by any routine: the cap is clamped to the schedule, the ceiling rises 10 at most weekly on 14 clean days (`fn_ceo_growth_decide`), and the outbox stops at 400 | the ceiling has no absolute top; P3 proposes one |
| **Bounce rate** | enqueue 3-day brake (`backoff_bounce_rate` 3 %); `fn_invite_same_day_brake` (5 %, ≥3 bounces); `invite_restart` probation (`invite_max_bounce_rate` 5 % since resume; a second breach goes to the CEO with no auto-restart); the CEO's 7-day brake | the seats can only lower | **four brakes, four windows, and they disagree:** 10 Nov reads since-resume 0 of 20 against 7-day 3 of 40. **The CEO's brake never applied (fixed, commit 1).** At cap ≤ 2 the 7-day rate goes blind (fixed: floor 5) |
| **Complaint rate** | `pause_complaint_rate` 0.1 %, ≥1 complaint pauses; restart refused on any complaint in 3 days | no | none measured (0 complaints ever) |
| **Placement** | `fn_invite_placement_gate`, per class, bar in `invite_placement_bar` (Microsoft ≥ 80 % inbox) | no | **the verdict expires 26 Nov**; then all classes close. Nothing schedules the re-test (P8) |
| **WhatsApp tier and quality** | `send_whatsapp`: `wa_daily_cap` 40 a rolling 24 h, `wa_per_recipient_24h` 1; supplier invites only to opt-ins (`supplier_whatsapp_optin`) AND both golive switches AND a HIGH reading; the CEO closes on a brake or a low reading | no; founder alerts bypass the cap by design | none |
| **OpenRouter spend against balance** | balance read hourly (`v_openrouter_position`: USD 29.18 of 580 topped up); `openrouter_low_balance_hourly` warns at the bands; at most 2 provider calls per request; fixture stubs | **yes:** nothing refuses a paid call when the balance is low; idle spend is kept low by design (ruling of 24 Sep: no caps) | real traffic AED 5.96 a day over the last 7 days against a USD 1-2 a day aim, inside it; session eval days (3 Nov: USD 81.75) are the risk. P9 proposes a reserve for customer-facing calls; it touches the 24 Sep "no caps" ruling, so it is his to record |
| **Paid spend (ads)** | `meta_autospend_golive = false`, `meta_daily_budget_cap_aed` 30; ledger 1456 | no routine sets the switch (the existing check asserts this file cannot) | none |
| **Legal and customer-visible copy** | the drift checks on pricing and terms (`marketing.fact_register` daily, the reveal-copy checks); refunds only through `fn_refund_execute_authorized` | refunds: the CEO decides, the accountant pays | none in this audit's scope |
| **Data exposure** | identity scrubbing before reveal (`_shared/identity_text.ts`); RLS; `anon_cannot_execute_security_definer` in CI | – | audited by the security session (#1890); not repeated |
| **A switch flipped by a seat** | `app_secrets` triggers: `fn_protect_app_secret`, `fn_autonomy_control_guard`, `fn_app_secrets_no_paid_ai_*`, audit trigger | – | none |

---

## D. The break-even plan the CEO must own

### D.1 Cost base

| line | AED a month | basis |
|---|---|---|
| Spent to date | **19,000** (one-off) | **founder's figure**; measured cross-check: GL expenses AED 18,386.82 (`gl_pnl`) |
| Anthropic (Claude subscription) | 775.01 | measured, receipt 19 Oct (`expense_entries`) |
| OpenAI (ChatGPT) | 799.00 | measured, receipt Sep; forecast flow 19 Nov |
| Supabase | 319.00 | measured, average of Aug 130.85, Sep 265.74, Oct 560.42 (rising) |
| Vercel | 334.79 | measured, Oct (USD 91.16) |
| GoDaddy (M365 mailbox) | 93.80 | measured, Oct |
| Resend | 73.45 | measured, Oct |
| GlockApps | 65.62 | measured, Oct and Nov |
| Twilio | 36.76 | measured, Oct auto-recharge |
| Google Play (Dropbox) | 26.99 | measured, Oct |
| Mashreq fee + VAT | 208.95 | measured from the statement (forecast flow) |
| **Recurring without OpenRouter** | **2,733.37** | measured |
| OpenRouter | 181 to 753 | measured: 181 = real traffic over the last 7 days × 30.4 (AED 5.96 a day); 753.29 = October booked, session evals included |
| GitHub Actions, Ubicloud, Namespace | 0 forward | **assumed** off. October carried GitHub AED 2,514.49, Namespace 367.25 and Ubicloud 148.11; ledger 1564 switched Actions off. Whether Namespace still renews is **not measured** |
| Trade licence renewal | 1,200 once, 24 Jun 2027 | measured price of 25 Jun 2026; the 2027 price is **assumed** equal |

Running cost from 11 Nov 2026 to 30 Jun 2027 (7.67 months) comes to **AED 22,345 to 26,731**, plus AED 1,200 for the
licence. **The total to cover by 30 Jun 2027 is AED 42,545 to 46,931.** Not included, because ledger 1609 defines the
target without them: the founder's fee and ads, which the 24 Sep plan carries in its AED 18,598 a month ceiling.

### D.2 Revenue model, as built

- **Reveal fee, the only live line.**
  - Rate and timing: `pricing_config.standard_reveal_rate = 0.03`, cap 99,999,999 (no cap), charged once per reveal
    to the customer.
  - The charge: `revealCharge()` in `supabase/functions/_shared/reveal_fee.ts:81` charges `base_fee` with
    `processing_fee: 0`.
  - Stripe's cost is absorbed (`CARD_FEE_CHARGED_TO_BUYER = false`, Cabinet Res. 66/2023):
    - 2.9 % domestic or 3.9 % international;
    - + 0.5 % invoicing;
    - + AED 1;
    - all × 1.05 VAT on the fees (`reveal_fee.ts:33-38`).
  - **Net per reveal = 0.9643 × 0.03 × Q − 1.05.** Q 10,000 → AED 288; Q 13,000 → AED 375; Q 21,538 → AED 622.
- **Supplier subscription.** AED 1,000 a year (`supplier_reg_fee`), free for the first 1,000 suppliers
  (`supplier_free_count = 1000`). **AED 0 before supplier #1,001**, so nothing before June.
- **Non-response charge.** 3 % + AED 500 admin + 12 % a year (`supplier_nonresponse_admin_fee_aed`,
  `supplier_nonresponse_interest_apr`). This is recovery of a refunded fee, not revenue to plan on. The memory note
  says AED 250 and 9 %; the live config reads 500 and 12 %. The difference is noted, not resolved here.
- **Commission:** none (`gl_accounts` 4100 holds 0, by the T&C).

### D.3 The funnel to break-even, against the limits

Customers launch in January 2027 (ruling of 24 Sep), so revenue has the six months January to June.

| Q (average quotation) | reveals needed, total | per month | requests a month at 15 % reveal (plan assumption) |
|---|---|---|---|
| AED 10,000 | 148 to 163 | 25 to 27 | 181 |
| AED 13,000 (plan's fee 390) | 113 to 125 | 19 to 21 | 139 |
| AED 21,538 (plan's January fee 646) | 68 to 75 | 11 to 13 | 84 |

**Supply.** A request can be posted only in an open category (10 verified suppliers,
`category_open_min_suppliers`). 84 to 181 requests a month across a focused 15-20 trades means **150 to 200 verified
suppliers in those trades by mid-January**.

**What the e-mail channel can give, inside the guardrails:**

- **Volume.** Nov-Dec room at the schedule is 1,750 sends (`schedule_room_sends`). January to June at the 50 a day
  ceiling over about 21.7 working days a month adds 6,510. That is **about 8,260 sends by 30 Jun**, if every
  placement class were open.
- **Conversion.** At the measured start rate of 0.79 % of delivered, about **60 suppliers by June**, even counting
  every start as verified. At the plan's assumed 4.1 % × 75 %, about 234.
- **Pool.** Only Google is open: 2,751 never-invited, 751 of them checked. With checked-only on, that pool lasts 15 to
  37 sending days. It yields about 6 suppliers at the measured rate. Microsoft (3,321) and "other" (12,564, of which
  6,331 are Etisalat, memory) wait on a Microsoft placement pass.
- **Need.** To reach 200 verified at the measured rate takes about 27,500 sends, **3.3 times what the warm-up allows
  by June.**

**The launch rule.** Until it changes, revenue cannot start at all: 223 trades × 10 suppliers is 2,230 suppliers.

**Verdict.** The target is not reachable with:

- e-mail as the only working channel,
- the measured 0.79 % start rate,
- one open mailbox class,
- and the every-trade launch rule.

It becomes arithmetically reachable only if all of the following hold. These are proposals, not facts:

1. Customers open per category as each focused trade reaches 10 (P1).
2. The start-to-registration conversion reaches about the plan's 3 %, a fourfold rise. The levers are a cleaner list
   (checked-only, commit 1), a second warmed mailbox, and Microsoft placement passed so that 15,885 more addresses
   open.
3. At least one non-email channel works by January. The cheapest are supplier referral (build), WhatsApp opt-ins asked
   in live conversations (the CEO's standing directive, now applied), and the founder's own network (ledger 971's 50).
4. Average Q is near the plan's AED 13,000 or more. That is **assumed**; there is no measured quotation yet.

### D.4 How the plan becomes orders

These are proposed monthly targets. They are not created as tasks: ledger rule 7 Sep, no task without his
confirmation; 1609 asks for this audit, not for the tasks.

| month | ceo | sales_engineer | marketing | customer_support | accountant | it_engineer |
|---|---|---|---|---|---|---|
| Nov | pick the 15 launch trades by demand and pool; issue the per-trade order | 1,000 checked sends, bounce < 2 %, 15 registrations in the 15 trades | answer the 2 open comments; November calendar live | mailbox bounce < 2 % (owner) | complete forecast (A2) and a break-even line | placement re-test before 26 Nov (session) |
| Dec | weekly check; a miss changes the lever | 60 verified, the referral ask live | January demand plan per opening trade; 4 articles | – | December close on the books | Microsoft placement fix |
| Jan-Jun | categories open at 10; monthly re-plan from measured rates | 10 verified per launch trade, then the next 15 | 84-181 requests a month from SEO, GEO and organic | SLA on every inbound | monthly net revenue against cost | – |

**The weekly check:** the CEO reads its own break-even row (P2) every Monday. A miss on the binding stage climbs the
ladder from the seats-act design G4: re-issue, change the lever, reassign, then a strategy memo recorded as
information to the founder.

---

## E. Fixes and proposals

### E.1 Built on this branch (pending, not applied)

| commit | seat | what | evidence | prevented by |
|---|---|---|---|---|
| `2ba9d5483` | ceo | safety-side growth decisions apply without `ceo_growth_act_golive` (cuts, checked-only, close, its own re-open, trade order, directives); the ceiling, raises past its own cut, unchecked again and WhatsApp open stay behind the switch; reviews may always roll back a raise; the brake floor is 5, not 1 | rehearsed with its probe: **PROBE OK**, the next Dubai day 10 decisions, 9 applied on the safety side, the cap raise 20 → 30 held back, the ceiling untouched | `scripts/checks/the_ceo_applies_its_safety_side_growth_powers_without_waiting_for_a_switch.test.mjs` (3/3) |
| `b52af09c3` | ceo | `fn_ceo_daily_run` keeps the note on the day and mails nothing; the two checks that read it replay the pending file | REHEARSED; 9/9 checks pass, and on main the new assertion fails (note true) | `scripts/checks/the_ceo_year_one_plan_follows_the_founder_targets.test.mjs` |
| `0c74ef090` | ceo | the `ceo.daily_run` job description matches | REHEARSED | same |
| `23bc5ac51` | marketing | the `marketing.article_release` job description names the CEO (1058) | REHEARSED; the check fails on main | `scripts/checks/no_seat_duty_names_the_founder_as_an_approver_he_has_retired.test.mjs` |

Apply order at merge, one file each with `--apply --ddl`, then delete each pending note and append to MANIFEST:

1. `the_ceo_applies_its_safety_side_growth_powers_without_waiting_for_a_switch.sql` (`--seat ceo`)
2. `the_ceo_note_is_not_mailed_to_the_founder_the_brief_is_his_one_daily_message.sql` (`--seat ceo`)
3. `the_article_release_duty_says_the_ceo_approves_and_the_founder_is_only_told.sql` (`--seat marketing`)

**What the first one will do on its first run** (measured in the rehearsal): `invite_reachable_only` becomes true,
because unchecked leads bounced 9 of 35; five trades go first; three directives are issued (bounce within limit, the
stopped start, WhatsApp opt-ins). The cap stays 20.

### E.2 Ranked proposals (not built: each changes a founder ruling, or is large)

1. **P1 Launch customers category by category.**
   - Replace "every trade covered" in `fn_ceo_launch_readiness` with: a category opens to customers when it has 10
     verified suppliers, which the platform already enforces through `category_open_min_suppliers`. The CEO picks the
     first 15 trades.
   - Why first: without it, no revenue is possible before 2,230 suppliers.
   - Founder ruling touched: 24 Sep, "customers are launched only once the supplier base is strong enough to quote
     every inquiry". This reading (every inquiry that can be posted) needs his confirmation.
2. **P2 A break-even ledger the CEO plans on.** One row a month to 30 Jun 2027: measured net reveal revenue, the
   accountant's measured cost (D.1), cumulative gap. The CEO year plan's cost line drops the founder fee and ads.
   Large: it re-bases `ceo_year_plan` and the target contracts.
3. **P3 Turn on the raising side.** Flip `ceo_growth_act_golive` once, inside the 1455 bounds, and add an absolute
   ceiling (for example 150 a day per mailbox) in `fn_invite_founder_cap`. 1438 and 1455 already delegate the cap.
   This is a switch held for his confirmation since 2 Nov, so it is his or the merge session's to record (ruling 1596
   makes technical calls the session's).
4. **P4 One consolidated access-and-funding request, dated.** It covers:
   - Stripe live activation (KYC, bank);
   - a LinkedIn page admin;
   - a UAE company number for phone outreach;
   - an e-mail verification vendor with its quoted cost (1606: no paid upgrades now, so it waits);
   - M365 admin for a second mailbox;
   - virustotal re-auth.

   One message, each item with its cost and expected effect, replacing per-item mail.
5. **P5 The IT digest goes to the session, not the founder.** Write the "what a working session must fix" list to a
   table that a session reads at start (and the checkpoint memory), instead of e-mailing him daily (it_daily_digest).
6. **P6 One weekly founder report.** Merge `board_report` into `ceo_weekly_review` (2 + 2 in 14 days).
7. **P7 The January launch plan approval** (`marketing.launch_plan`, ruling of 28 Sep) against 1609's "no decision goes
   to him". He decides which ruling stands.
8. **P8 A dated GlockApps re-test** before 26 Nov, plus a seat duty that raises it to the session list 7 days ahead.
   It needs the session's connector and one credit.
9. **P9 An OpenRouter reserve.** Below USD 10, background paid classes wait and customer-facing chat continues. This
   touches the 24 Sep "no caps" ruling.
10. **P10 Load the six seat exams** that are already in `knowledge/exams/` (`seat_qualification_exam.mjs --load`), so
    the monthly self-review grades something. Add a CEO deliverability entry: warm-up curve, Gmail and Microsoft bulk
    thresholds.
11. **P11 Unstick marketing.** Answer the 2 held praise comments from the reply library. The CEO decides the November
    and December plans (in `ceo_reviewing` since they arrived), or the plan escalates after 3 days.
12. **P12 Consolidate the duplicates.**
    - One supplier-funnel grader instead of six CEO duties.
    - One per-trade gap list, owned by sales_engineer and read by marketing.
    - One knowledge meter: retire `knowledge_pass_rate`, which grades 0 items.
13. **P13 Accountant forecast completeness.** Every vendor with 2 or more receipts in 120 days becomes a forecast flow.
    Today the forecast misses about AED 951 a month plus OpenRouter.

---

## Evidence: how each number was measured

All from production, read-only, 10 Nov 2026 between about 20:00 and 21:30 UTC, unless a row says otherwise. Test
traffic was excluded with `e2e_run_tag is null` on `ai_cost_log`, and demo leads with `not coalesce(is_demo, false)`.

| what | where it was read |
|---|---|
| seats | `org_role` where `status = 'active'` (6) |
| duties | `seat_duty` (157), `cron.job` (99), `resilience_step` (45) |
| knowledge | the six pack tables (counts, domains, `imported_at` / `updated_at`, `embedding_gte is null`); terms by `ilike`; `seat_knowledge_recall` latest complete day per seat; `seat_self_review`; `seat_knowledge_exam`; `ceo.senior_verdict.last_result` |
| model and cost | `ai_cost_log` (30 and 7 days, by seat and model, AED); `v_openrouter_position`; `openrouter_day` |
| money | `expense_entries` by vendor and month, USD at 3.6725; `gl_pnl`; `budget_lines`; `accountant_cash_forecast_week` (2026-11-09); `v_company_subscriptions`; `pricing_config` |
| funnel and limits | `fn_ceo_supplier_goal_status()`; `fn_invite_send_health(…)`; `ceo_growth_action`; `ceo_supplier_channel`; `invite_brake`; `app_secrets` (switch and cap keys only, secrets hidden); `leads` by `email_verified` and `fn_mail_provider_of_email`; `fn_invite_placement_open_providers()`; `deliverability_test`; `ceo_launch_gate` |
| founder traffic | `notifications` with `fn_is_founder_own_inbox` / `to_role` / mobile match; `founder_mail_policy` allowed kinds (38); `pg_proc` source scan (54 routines) |
| links | `agent_actions` kind handoff, 30 days |
| marketing | `marketing_post`, `marketing_month_plan`, `marketing_article`, `social_message`, `marketing_insight_day` |
| code | `supabase/functions/_shared/reveal_fee.ts:33-84`; `supabase/functions/send_outbox/index.ts:199-213`; `supabase/functions/send_whatsapp/index.ts:165-198`; `fn_ceo_growth_decide`, `fn_ceo_growth_act`, `fn_ceo_growth_review`, `fn_ceo_daily_run`, `fn_ceo_launch_readiness`, `fn_sales_engineer_restarts_invites_after_a_brake`, `fn_invite_campaign_pause`, `fn_openrouter_low_balance_tick`, all read from production and diffed equal to their canonical files before editing |

**Not established here:**

- whether Namespace still renews;
- the 2027 licence fee;
- any real average quotation value;
- why 9 of 14 e-mails counted as unanswered (seats-act report);
- whether reveal #30e17bdd was a Stripe test-mode payment.
