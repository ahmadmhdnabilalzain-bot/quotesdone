# Company brain — Supply department

Plan for the founder to approve. Nothing here is applied to production.

**Hard constraint honoured throughout: no position in this department calls a language model at run time.**
Every resolver below is retrieval + arithmetic + threshold logic over named tables and routines. Free in-region
`gte-small` embedding (`kb_embed`) is used only to *route a question to a type*, never to compose an answer.
Everything a seat says is assembled from a template whose slots are computed values and cited rows. Section 9 of
each seat lists, honestly, what it cannot do without a model.

---

## Measured state of this department — production, 7 September 2026, 08:01–08:35 UTC

Every number below was read from `htdblwldjkcgjvmqkbeh` in this session. Nothing is estimated.

### The funnel

| Fact | Value | Source |
|---|---|---|
| Leads in the pool | 22,265 | `leads` |
| …with an email address | 19,896 | `leads.email` |
| …with an E.164 phone | 6,937 | `leads.phone_e164` |
| Invited, ever | 171 (161 `sent`, 10 `bounced`) | `leads.invite_status` |
| Claimed their profile | 0 | `leads.claimed` |
| Registered | 1 | `leads.lifecycle_stage='registered'` |
| Approved | 1 | `leads.approval_status='approved'` |
| `verified = true` | 1 | `leads.verified` |
| `verification_status = 'unverified'` | 22,265 (all of them) | `leads.verification_status` |
| Accepted the supplier terms | 1 | `leads.accepted_terms_at` |
| Banned / matching-blocked / permanently closed | 0 / 3 / 2 | `leads` |
| Lifecycle spread | not_contacted 22,090 · no_response 164 · undeliverable 10 · registered 1 | `leads.lifecycle_stage` |
| Emirate spread | Dubai 10,585 · Abu Dhabi 4,728 · Sharjah 3,453 · Ajman 1,414 · null 860 · RAK 644 · Fujairah 395 · UAQ 178 · 7 rows where a street address landed in the emirate column | `leads.emirate` |

The single registered supplier is `leads.id = 30466`, **MERIDIAN MEP CONTRACTING LLC**, Dubai, trade licence
`1145872` expiring 2027-03-14, terms accepted 2026-08-12 11:41 UTC. Its `email` is NULL, its `approved_at` is NULL
and its `approval_decided_by` is NULL — so it was **not** approved through `fn_supplier_autoapprove_clean`, which
sets all three and also sets `verification_status='verified'`. This row carries `verified=true` and
`verification_status='unverified'` simultaneously. **The company's one supplier is in a state no routine produces.**

### Coverage

| Fact | Value | Source |
|---|---|---|
| Catalogue categories | 86 | `catalog_supplier_categories` |
| Categories at the 10-approved target | 0 | `v_supply_gap where approved>=10` |
| Categories with a viable pool at the 5% planning conversion | 25 | KPI 78, measured 2026-09-07 03:30 UTC |
| Category status spread | POOL TOO THIN 58 · IN PROGRESS 25 · NO POOL 3 | `v_supply_gap.status` |
| Same, from the daily scan | NO SUPPLY (pool exists, nobody approved) 80 · BELOW TARGET 3 · NO POOL 3 | `supply_health_snapshots` 2026-09-07, `fn_supply_gap_scan` |
| Categories with zero usable supply | 83 of 86 | same snapshot, `no_supply` |
| Matchable suppliers, whole marketplace | 3 (one supplier counted in three categories) | same snapshot |
| Sendable leads across categories | 16,242 | `v_supply_gap.sendable` |
| Sendable shortfall to reach 10 approved everywhere at 5% | 10,025 | `v_supply_gap.sendable_shortfall` |
| Trades / subcategories / keyword rows | 40 / 470 / 1,839 category + 6,553 subcategory | `taxonomy_trade`, `catalog_subcategories`, `category_keyword`, `subcategory_keyword` |
| Lead→category / lead→subcategory links | 18,539 / 25,438 | `lead_category`, `lead_subcategory` |
| Structured capability records | 15,306 | `supplier_capabilities` |

### The gates that are shut

| Gate | State | Where |
|---|---|---|
| `fn_supplier_outreach_golive()` | **false** | reads `app_secrets.supplier_outreach_golive` |
| `invite_enabled` | **false** | `app_secrets` |
| `invite_daily_cap` | 50 | `app_secrets` |
| `invite_target_per_category` | 10 | `app_secrets` |
| `invite_max_bounce_rate` | 0.05 | `app_secrets` |
| `pricing_config.category_open_min_suppliers` | 10 | a category is *closed* below 10 approved suppliers |
| `pricing_config.auto_approve_suppliers` | true | |
| `pricing_config.supplier_free_count` / `supplier_reg_fee` / `supplier_charging_starts` | 1000 / AED 1,000 yearly / **NULL** | the first 1,000 suppliers pay nothing and no charging start date is set |

`invite_schedule` holds 15 rows. The last real send was **2026-08-15 (50 invites)**. Every row from 2026-09-03
onward is `planned 50, sent 0, status pending`, each carrying the note *"batch of 50 from a pool of 19725
never-invited lead(s) with an email, cap 50; HELD — real invitations wait for the founder's go
(app_secrets.invite_enabled)"*.

### Screening

`screening_run` has 18 runs; the newest pair is 2026-09-07 03:00 UTC — `un_consolidated` 4,157 entries and
`uae_local_terrorist_list` 804 entries, both `ok`. Two `uae_local_terrorist_list` runs on 2026-09-06 recorded
`entries=0, status='failed'`. `screening_entry` holds 4,961 normalised names. `supplier_screening_hit` holds
**0 rows** — which, with one supplier on the platform, is what a working screen and a dead screen both look like.
Cron `345 sanctions_screen_weekly '0 3 * * 1'` is **active**; `fn_sanctions_screen_tick()` posts to the
`sanctions_screen` edge function using `app_secrets.cred_cron_compliance`.

### Cron reality

134 of 235 cron jobs are active estate-wide. In this department:

- **Active:** 2 `supplier_invites_daily` (09:00), 32 `pending_suppliers_digest`, 85 `scan_new_supplier_categories`,
  180 `supplier_registration_state_resync_daily`, 313 `supplier_suspension_proposed_daily`,
  322 `supplier_discovery_daily`, 344 `supplier_outreach_daily`, 345 `sanctions_screen_weekly`.
- **Inactive:** 39 `embed_suppliers_daily`, 68 `supplier_success_daily`, 100 `licence_block_reconcile_daily`,
  118 `supplier_capability_chase_daily`, 120 `backfill_invite_trades`, 121 `invite_ramp_daily`,
  178 `supplier_exception_sweep_daily`, 208 `supplier_score_refresh_daily`, 209/210/211 `supplier_risk_*`.

### The marketplace this department feeds

`inquiries` 0 · `quotes` 0 · `transactions` 0 · `reveal_invoices` 0 · `customers` 1. There is no demand yet.
`supplier_score` holds 20,465 rows but `response_rate` is non-null on **2** of them, `quotes_submitted > 0` on
**0**, and `computed_at` last moved **2026-08-16** (its refresh cron 208 is off).

### Three instruments in this department measure the wrong subject

These are stated because a seat that trusts them will report a healthy department that does not exist.

1. **`v_category_coverage.coverage`** reads `COMPLIANT` for 84 of 86 categories. Its definition makes `COMPLIANT`
   mean *"the category **agent** holds 14 required knowledge modules"*. It says nothing about suppliers. Its
   sibling column `supplier_supply` counts **leads whose `invite_trades` overlap the trade** — 19,120 links, 23
   categories at ten or more — not approved suppliers. Approved suppliers in those same categories: 0.
2. **`department_objective` "Grow verified supplier coverage across active categories"** (target 5 per category)
   reports `actual_value = 215.57`. Its sibling objective "10 approved suppliers in every one of the 86
   categories" reports `0`. Same subject, two instruments, opposite verdicts; the first is counting the lead pool.
3. **`registered_supplier_count()`** returns **7**. Its body is `select coalesce(max(founding_rank),0) from leads`
   — a rank, not a count. One lead is registered.

A fourth: `employee_kpi` 123 "Supplier response rate" reports **100.00%** against a 60% target, computed as
`avg(rv_response_rate) where rv_reveals > 0` over **2 rows**. It is a two-row average dressed as a department KPI.

### Certification and knowledge held today

`role_certification` holds 12 rows, two per seat (listed in each seat's §6).
`certification_exam_result` holds 22 rows and **not one belongs to a supply seat** — bookkeeper, cs_support,
marketing_analyst, procurement and security have sat exams; bd, onboarding, partnerships_mgr, supplier_coverage,
supplier_retention and supplier_verification have **never sat one**. No syllabus area has therefore been failed,
because none has been examined.

`agent_knowledge` rows per seat: bd 8 · onboarding 14 · partnerships_mgr 12 · supplier_coverage 9 ·
supplier_retention 9 · supplier_verification 11. The majority of these are `exam:` topics (single ingested
documents), not operating knowledge. `ops_knowledge where dept_key='supply'` holds **9 rows** (8
`decision_playbook`, 1 `department_shared`) against `procurement` 558, `supplier_success` 416 and
`supplier_knowledge` 136. `dept_library` holds **no rows** for supply.

`org_tasks` for `dept_key='supply'`: 55 done, 11 assigned.
`founder_mail_policy` carries exactly three supply kinds — `invite_paused_bounce`, `supplier_registered`,
`supply_health` — all with `allowed_to_email = false`, owner role `business_development`. Correct: the founder is
emailed refunds only.

### The workflows this department owns

`phase_b_workflow` — **W09 Supplier onboarding** (9 steps, accountable `supplier_onboarding_specialist`,
founder boundary "No self-approval"), **W10 Supplier verification** (8 steps, criticality *critical*, accountable
`supplier_verification`, boundary "No approval without evidence"), **W11 Supplier coverage and acquisition gaps**
(7 steps, accountable `supplier_coverage`, boundary "No unapproved outreach/spend"), **W19 Supplier retention**
(7 steps, accountable `supplier_retention`, boundary "No override of verification/enforcement").
**There is no partnerships workflow.** `partnerships_mgr` appears nowhere in `phase_b_workflow_step`;
`employee_workflow` gives it only `employee_task`. `supplier_coverage` and `supplier_retention` have **no
`employee_workflow` rows at all** despite owning W11 and W19.

### The revenue arithmetic every seat in this department shares

`pricing_config`: reveal fee **3%** of quote value, cap 99,999,999 (effectively none); supplier registration
**AED 1,000/year**, first **1,000** suppliers free, `supplier_charging_starts` **NULL**.

Therefore, for year one: **this department bills nothing.** Every supplier it recruits, up to a thousand of them,
pays zero, and no start date for charging exists. Supply's entire contribution to the founder's AED 1,000,000 is
*enabling* — it is the constraint that decides whether reveal-fee revenue can exist at all, because
`category_open_min_suppliers = 10` means a category with fewer than ten approved suppliers is closed and cannot
produce a paid reveal. **Zero categories are open today.** Each seat's §8 works its slice from that fact.

---

## bd — Business Development Manager

Seniority `director`, `routing_tier` director, manager `ceo`. The only director in this department; the other five
seats report to it. Owns the invite programme's commercial case and the enterprise/government pipeline.

### 1. Question and decision taxonomy

| # | Question or decision | Kind | Frequency | Who asks | Cost of a wrong answer |
|---|---|---|---|---|---|
| 1 | Which category do we open next, given a fixed invite budget? | allocation | weekly | ceo, supplier_coverage | Invites burned on a category with no demand; 10,025 sendable-lead shortfall grows |
| 2 | How many invites per day can we send without breaching the 5% bounce ceiling? | gate | daily | onboarding | Domain reputation loss; the 10 bounced leads become 500 |
| 3 | Is the outreach go-live gate ready to be recommended to the founder? | escalation | weekly | ceo | Sending 19,725 cold invites before the portal can complete a registration |
| 4 | What conversion rate should we plan the next quarter at? | forecast | monthly | ceo, finance | Plan built on 5% when the measured rate is 0.58% |
| 5 | Which emirate do we prioritise for a given trade? | allocation | monthly | supplier_coverage | Dubai-only supply; Abu Dhabi RFQs unquotable |
| 6 | Should this lead be invited at all, or discovered further first? | gate | daily (per batch) | onboarding | Invite to a dead domain; bounce budget spent on nothing |
| 7 | Is an enterprise or government account worth a named pursuit? | allocation | monthly | ceo | Months spent on a tender we cannot legally bid |
| 8 | What is the cost per approved supplier by channel? | diagnosis | monthly | finance | Doubling down on the channel that produces nothing |
| 9 | Is the pipeline moving, or is it a stack of untouched leads? | diagnosis | weekly | ceo | 22,090 `not_contacted` leads reported as pipeline |
| 10 | Which of the 58 POOL-TOO-THIN categories do we scrape versus abandon? | sequencing | monthly | supplier_coverage, data_intel | Scraping a category with no UAE demand |
| 11 | Do we re-invite a `no_response` lead, and after how long? | sequencing | weekly | onboarding | Nuisance sending; suppression list growth |
| 12 | Do we re-invite a `bounced` lead after a corrected address? | gate | weekly | onboarding | Repeated hard bounce; reputation |
| 13 | What does a category need before it is worth inviting into? | gate | monthly | supplier_coverage | Ten approved suppliers in a category nobody buys |
| 14 | Should we accept a channel partner's supplier list? | gate | quarterly | partnerships_mgr | Unconsented data; PDPL exposure |
| 15 | What registration fee, if any, do we quote a prospective supplier? | pricing | per conversation | onboarding | Contradicting `pricing_config` (free for the first 1,000) |
| 16 | Is the department on track for 300 registrations this month? | forecast | weekly | ceo, founder brief | A "yes" against a measured 0 |
| 17 | Which trade has demand we cannot serve? | diagnosis | weekly | supplier_coverage | Demand routed to an empty category |
| 18 | Do we pause the invite programme after a deliverability event? | escalation | on trigger | onboarding | A blacklisted sending domain |
| 19 | What is the honest headline for the weekly supply report? | craft | weekly | ceo | Reporting `v_category_coverage` COMPLIANT 84/86 as supplier coverage |
| 20 | Should this category's target be 10, or something else? | pricing | quarterly | ceo | Chasing 10 sanitaryware suppliers when 4 would clear the RFQs |
| 21 | Does an inbound supplier enquiry get a human-style reply or the standard path? | sequencing | daily | onboarding | Losing the rare inbound registrant |
| 22 | Do we accept a supplier who serves only one emirate? | gate | weekly | onboarding | A category "covered" but unquotable outside Dubai |
| 23 | What is the marginal value of the 11th supplier in a category? | forecast | quarterly | ceo | Over-supplying a category while 83 sit empty |
| 24 | Is a lead a duplicate of an existing supplier? | diagnosis | daily | onboarding | Double-inviting; two profiles quoting one RFQ |
| 25 | Which categories should the discovery crawler run next? | sequencing | weekly | data_intel | Crawler cost on categories with no shortfall |
| 26 | Should we buy a supplier list? | escalation | quarterly | ceo, finance | Spend outside authority; unconsented data |
| 27 | Do we approach a competitor's supplier directly? | gate | monthly | partnerships_mgr | Reputational and contractual risk |
| 28 | What does the founder need to decide, and what can we decide? | escalation | weekly | ceo | Escalating a non-refund decision to the founder |
| 29 | Is a category's supply concentrated in too few owners? | diagnosis | monthly | supplier_coverage | Three "suppliers" that are one group |
| 30 | What broke: the pipeline, the portal, or the offer? | diagnosis | on KPI miss | ceo | Scraping harder when the registration page is the blocker |

### 2. Domain logic

**M1 — Invite budget allocation.** For each category *c*: `deficit(c) = max(0, 10 − approved(c))`;
`need(c) = ceil(deficit(c) / p)` where *p* is the planning conversion; `feasible(c) = min(need(c), sendable(c))`.
Rank by `demand_weight(c) × feasible(c) / need(c)`. Inputs: `v_supply_gap` (`approved`, `sendable`,
`sendable_needed_at_5pct`, `sendable_shortfall`), `app_secrets.invite_daily_cap` (50),
`pricing_config.category_open_min_suppliers` (10). Output: an ordered category list with an invite count each.
**UNMEASURED:** `demand_weight(c)` — `inquiries` holds 0 rows, so there is no demand signal at all. Until there
is, the model must fall back to `feasible(c)/need(c)` alone and say so in the answer.

**M2 — Conversion ladder.** `sent → delivered → claimed → registered → approved`. Measured today:
sent 161, bounced 10, claimed **0**, registered 1, approved 1. Invite→approval = 1/171 = **0.58%**
(`employee_kpi` 81 reports 0.58). Planning assumption baked into `v_supply_gap` and KPI 78 = **5%**, an 8.6×
optimism. Inputs: `leads.invite_status`, `leads.lifecycle_stage`, `leads.approval_status`. Output: stage-to-stage
rates with denominators. **UNMEASURED:** delivery (there is no delivered state; `email_verified='valid'` is 0 rows
across all 22,265 leads), and open/click (no instrument exists).

**M3 — Bounce budget.** `bounce_rate = bounced / (sent + bounced)` = 10/171 = **5.85%**, already above the
`invite_max_bounce_rate` of 0.05. `headroom(d) = floor(cap × max_rate) − bounced_to_date`. Inputs:
`leads.invite_status`, `app_secrets.invite_max_bounce_rate`, `invite_schedule.sent`. Output: sends permitted
today. **Note for the founder:** on today's numbers this model returns *zero* — the programme is already over its
own bounce ceiling and must clean addresses before it resumes, independent of the go-live gate.

**M4 — Days-to-target.** `days = ceil(need_total / daily_cap)` where `need_total = Σ ceil(deficit(c)/p)`.
At p = 5%: 860 approvals needed → 17,200 invites → **344 days** at 50/day. At the measured p = 0.58%:
860 approvals → **148,276 invites** → 2,966 days, and only 19,896 leads with an email exist. Inputs: `v_supply_gap`,
`app_secrets.invite_daily_cap`. Output: a date, or the string "not reachable from this pool".

**M5 — Cost per approved supplier.** `cpa = channel_spend / approvals_from_channel`. Inputs: `expenses` (18 rows),
`leads.source`, `leads.enrich_source`. **UNMEASURED:** no spend row is attributed to a supplier channel and only
one approval exists, so the denominator is 1 and the numerator is unattributable. The seat must refuse this
question, not divide.

**M6 — Pipeline truth.** `real_pipeline = leads where invite_status is not null and lifecycle_stage not in
('undeliverable')` = 161. Everything else (22,090 `not_contacted`) is a **list**, not a pipeline. Output: two
numbers, never one.

### 3. Reasoning procedures

**Type 1 — which category next.** (a) Read `v_supply_gap` for all 86 rows. (b) Drop the 3 `NO POOL` rows into a
discovery hand-off to data_intel — they cannot be invited into. (c) For the remaining 83, compute M1. (d) Because
`demand_weight` is unmeasured, order by `feasible/need` and state that the ordering is supply-side only.
(e) Apply M3: if bounce headroom is zero, return "no category — the bounce ceiling is breached" and stop.
(f) Apply the go-live gate: `fn_supplier_outreach_golive()` is false, so the output is a *plan*, marked HELD, not
a send. (g) Emit the ranked list with, per row, `approved`, `sendable`, `need`, `feasible` and the cited view.

**Type 3 — recommend the go-live gate.** Checklist, all from production, all must pass: bounce rate ≤ 5%
(**fails today at 5.85%**); a registration path that has completed end-to-end at least once
(`leads.claimed = 0` — **fails**; nobody has ever claimed a profile); `supplier_registration_state_resync_daily`
active (**passes**, cron 180); `sanctions_screen_weekly` active with a fresh run inside 7 days (**passes**,
2026-09-07 03:00); at least one category within reach of 10 (**fails**: best is 3). Verdict template:
"Do not recommend go-live. N of 5 conditions fail: …". Never recommends on a partial pass.

**Type 4 — conversion to plan at.** Compute M2. If `approved < 30`, the rate is not a rate — return the raw
counts and the confidence interval's width instead, and refuse to project. Today approved = 1. The seat answers:
"1 approval from 171 invites. No projection is defensible below 30 approvals; the 5% figure in `v_supply_gap`
and KPI 78 is a planning assumption, not a measurement, and the only measurement we have is 0.58%."

**Type 9 — is the pipeline moving.** Run M6. Compare `invite_schedule.sent` for the trailing 30 days
(**0 since 2026-08-15**) against `planned` (200 planned, 0 sent, all `pending`). Read the held note. Answer:
"Nothing moved in 23 days. 200 invites were planned and 0 sent; `invite_enabled` is false."

**Type 16 — on track for 300 this month.** Read `employee_kpi` 150 (`actual_value` 0, measured 2026-09-07 03:30)
and `department_objective` 32816 (actual 0). Compute days elapsed in month and required run rate:
300 in September with 0 by day 7 needs 13.0/day for the rest of the month; at the measured 0.58% that needs
2,241 invites/day against a cap of 50. Answer: "No — and not reachable: it requires 45× the daily invite cap."

**Type 19 — the weekly headline.** Template-composed, four numbers only: approved suppliers (1), categories at
target (0 of 86), invites sent in the last 7 days (0), and the gate state (held). It is forbidden from citing
`v_category_coverage.coverage` — see §4 rule B4.

**Type 30 — what broke.** Ordered elimination, stopping at the first failure: (1) sending — did
`invite_schedule.sent` move? No → the gate, stop. (2) delivery — bounce rate above ceiling? (3) landing —
`leads.claimed`, 0 forever → the registration path, stop. (4) completion — `registration_submitted_at` present
but no approval? (5) approval — applicants waiting in `fn_supplier_autoapprove_clean`'s scan. Today it stops at
step 1 and names the gate. It never reports "supply is hard"; it names a stage.

### 4. Judgement rules

- **B1.** `bounce_rate > invite_max_bounce_rate` → **stop sending**, regardless of category deficit. Reason: a
  burnt sending domain costs more than a month of coverage, and it is the one loss that cannot be undone by
  spending more.
- **B2.** `fn_supplier_outreach_golive() = false` OR `invite_enabled = false` → every outreach answer is a plan
  marked HELD; never an instruction to send. Reason: the founder's go is the gate, and the note in
  `invite_schedule` says so in the row itself.
- **B3.** `approved < 30` → refuse to state a conversion *rate*; give counts. Reason: 1/171 has a 95% interval
  roughly 0.01%–3.2%; any plan built on the point estimate is fiction.
- **B4.** Never cite `v_category_coverage.coverage` as supplier coverage. It measures the category agent's
  knowledge modules. Use `v_supply_gap.approved` or `supply_health_snapshots.metrics->>'target_met'`.
- **B5.** Never cite `registered_supplier_count()`. It returns `max(founding_rank)` = 7 against 1 registered
  supplier.
- **B6.** A category with `sendable = 0` is a **discovery** task for data_intel, never an invite task. Three
  categories are in this state today (Tax Consultants, Pharmaceutical Suppliers, Domestic Services Companies).
- **B7.** *Do not do this even though it scores well:* do not invite the whole 19,896-lead email pool to open 86
  categories at once. It scores highest on M4 and it is wrong — one deliverability event ends the programme, and
  a supplier invited before there is any RFQ demand churns before demand arrives. Cap at the daily cap, always.
- **B8.** *Do not do this even though it scores well:* do not raise `invite_target_per_category` from 10 to hit
  "categories covered" faster by lowering the bar. The 10 is `pricing_config.category_open_min_suppliers` and it
  is what makes a reveal fee defensible; moving it moves the product, not the metric.
- **B9.** Spend above `decision_policy.auto_action_max_aed` (**0**) is never autonomous. Any list purchase, any
  paid channel, goes to the accountable role — not to the founder, whose only gate is refunds
  (`decision_policy.founder_review_gates` = refund_decision, refund_outside_policy).
- **B10.** `employee_authority`: `outreach_draft` autonomous, `outreach_send` **advisory** — bd may compose an
  invite campaign, never dispatch it.
- **B11.** A KPI whose denominator is under 10 rows is reported as a fraction, never a percentage. Applies today
  to `employee_kpi` 123 (100.00% from 2 rows).
- **B12.** If a category's supply is concentrated — a majority of its approved suppliers sharing a
  `license_authority` and address — treat the category as **not** covered and say why. Reason: three profiles of
  one group cannot produce three independent quotes.

### 5. Technical knowledge

Tables and views: `leads` (151 columns; the ones that matter here are `invite_status`, `invited_at`,
`invite_followups`, `invite_last_followup_at`, `invite_trades`, `lifecycle_stage`, `approval_status`, `source`,
`enrich_source`, `emirate`, `email`, `email_domain`), `invite_schedule`, `v_supply_gap`, `supply_health_snapshots`,
`lead_category`, `lead_trade_map`, `taxonomy_trade`, `expenses`, `opportunity` (42 rows).
Routines: `enqueue_supplier_invites(int)`, `fn_org_exec_invite(int)`, `fn_invite_ramp()`, `fn_invite_week_activate()`,
`fn_invite_status_on_send()`, `trg_invite_cap_allocation()`, `fn_supplier_outreach_daily()`,
`fn_supplier_outreach_golive()`, `fn_supplier_lead_sourcing(text)`, `fn_supplier_discovery_promote(int,int)`,
`fn_supplier_invite_followups(text)`.
Gates: `app_secrets` keys `invite_enabled`, `invite_daily_cap`, `invite_max_bounce_rate`,
`invite_target_per_category`, `invite_target_per_trade`, `supplier_outreach_golive`, `bd_outreach_enabled`,
`invite_subject`, `invite_body`. **Values are read by name inside routines and never printed.**
Platform mechanics it must know: email suppression lives in `email_suppressions` (37 rows) and
`email_domain_mx` (8,764 rows); a real send must never be made by hand; fixtures are `ZZ DEMO — …` /
`@example.invalid` inside a `rehearsal_window` (30 rows).
**Must be stored so this seat can act alone:** a per-channel spend attribution (does not exist), a delivered/opened
state on an invite (does not exist), and a `demand_weight` per category (does not exist — `inquiries` is empty).

### 6. Academic knowledge

Disciplines: procurement and supply management; sales methodology; two-sided-marketplace economics; sampling
statistics; email deliverability standards.

`role_certification` holds two for this seat:
**CIPS Level 4 Diploma in Procurement and Supply** (CIPS, pass 50%) — syllabus: Scope and Influence of Procurement
and Supply; Defining Business Needs; Commercial Contracting; Ethical and Responsible Sourcing; Commercial
Negotiation; Supplier Relationships; Whole Life Asset Management.
**CSP, Certified Sales Professional** (NASP, pass 80%) — Prospecting and Qualification; Needs Discovery;
Presenting Solutions; Handling Objections; Closing and Negotiation; Account Management and Ethics.
**Syllabus areas failed: none — this seat has never sat either exam.** `certification_exam_result` holds no row
for `bd`.

Lawful primary sources we may ingest: CIPS published syllabus and ethical code (public); UAE Ministry of Economy
commercial-agency and company-law materials; Dubai DET and Abu Dhabi ADDED licensing pages; UAE Federal
Decree-Law No. 45/2021 on personal data protection (PDPL) and the TDRA anti-spam requirements, which bind cold
invitation; IETF RFC 8058 (one-click unsubscribe), RFC 7489 (DMARC), RFC 6376 (DKIM) and M3AAWG's published
sender best-practice documents — all free to reproduce. Two-sided-market theory (Rochet–Tirole, Armstrong) via
their open-access working papers, never a textbook.

### 7. Corporate knowledge

Policies and rulings it must carry: the founder's only approval is a Stripe refund
(`decision_policy.founder_review_gates`); the 3% reveal fee and the AED 1,000/year registration fee with the
first 1,000 free (`pricing_config`); `category_open_min_suppliers = 10`; `matching_strike_limit = 3`
(`decision_policy`, founder decision 3 Aug 2026); the trade licence DET 1633275 expiring 24 Jun 2027 and no VAT
registration until the AED 375,000 threshold (rendered into `ops_knowledge` as `qd-company:*` by
`fn_company_self_knowledge_sync()`); the refund ladder of 6 Sep 2026 (5 working days, chase at 3, AED 250 admin
fee, 9% p.a.) because it is what a supplier is signing up to.
Workflows it participates in: **W11 step 5** — it receives the prioritised acquisition target from
`marketplace_director` and must give every target one owner, one channel, one expected result and a budget
boundary. It owns no workflow of its own; `employee_workflow` gives it only `employee_task`.
Hands to: `onboarding` (the invited lead), `supplier_coverage` (the gap that justified the invite),
`data_intel` (the discovery request), `partnerships_mgr` (a channel that could bring a list).
History it must not forget: the 81-invite / 0-registration result of early August, now 171 invites and 1
registration; and that `leads.claimed` has been 0 for the entire life of the platform, which means the claim link
has never once been used successfully.
**Does not exist:** a written supplier-acquisition playbook for this seat (`dept_library` has 0 supply rows;
`ops_knowledge where dept_key='supply'` has 9 rows total).

### 8. One-year plan

**Objective.** Open enough categories that a paid reveal is possible, then keep them open. bd bills nothing —
`supplier_free_count` is 1,000 and `supplier_charging_starts` is NULL, so every supplier it recruits in year one
pays AED 0.

**Its slice of AED 1,000,000.** AED 0 direct. Indirect and total: at a 3% reveal fee, AED 1,000,000 of revenue
requires **AED 33,333,333 of revealed quote value**. No category can produce a paid reveal below 10 approved
suppliers, and 0 of 86 are there. **bd's slice is the whole gate, and it is worth AED 0 until the gate opens.**

**Metrics it owns.** (1) Approved suppliers — `leads where approval_status='approved'`, today **1**, target 860
(`employee_kpi` 79). (2) Registrations per calendar month — `employee_kpi` 150, today **0**, founder target **300**.
(3) Invite→approval conversion with its denominator — today **1/171**.

**Quarterly milestones.** Q1: bounce rate back under 5% and a claim path proven end-to-end once (both are
prerequisites the current numbers fail); go-live recommendation delivered with its five-condition checklist.
Q2: first category at 10 approved. Q3: ten categories at 10. Q4: thirty categories at 10.

**Capacity check — honest.** It does not work. To reach 860 approvals at the estate's 5% planning assumption
needs 17,200 invites; at 50/day that is **344 days**, leaving no room for the 25%+ that will be dead addresses.
At the *measured* 0.58% it needs **148,276 invites** against a pool of 19,896 emailable leads — **7.4× more
invites than there are leads**. The 300-registrations-a-month target needs 6,000 invites a month at 5%, which is
200/day, **4× the current cap of 50**. Three things must change or the number is not reachable: the daily cap
must rise (which requires the bounce rate fixed first), the conversion must be measured rather than assumed
(which requires a claim path that has worked at least once), and the pool must grow — `employee_kpi` 80 "lead
pool growth" reads **0 of 2,000** new sendable leads in 30 days, so the pool is currently static.

**Dependencies.** `product_eng` for a claim/registration path that has completed once (blocks everything);
the founder for `invite_enabled` and `supplier_outreach_golive`; `data_intel` for the 3 NO-POOL categories and
for growing the pool; `growth` for whether any demand will exist to justify the categories chosen.

### 9. What this seat cannot do without a model

- Writing a *new* invitation body for an unseen category. Templated composition from `invite_subject`/`invite_body`
  plus category and emirate slots covers the existing pattern; a genuinely new persuasive angle does not.
- Reading a free-text inbound reply from a supplier ("who are you, we already work with X, call me Tuesday") and
  extracting the intent. A keyword classifier over `inbound_messages` handles the common cases; the long tail
  needs a model or a human.
- Judging whether an enterprise or government tender document is one QuotesDone may lawfully bid. That is a legal
  reading, and it must go to `legal` as a task, not be guessed.

---

## onboarding — Supplier Onboarding Specialist

Seniority `specialist`, `routing_tier` director, manager `bd`. Accountable role for **W09 Supplier onboarding**
(9 steps). Owns seven of this department's fifteen KPIs.

### 1. Question and decision taxonomy

| # | Question or decision | Kind | Frequency | Who asks | Cost of a wrong answer |
|---|---|---|---|---|---|
| 1 | Is this registration file complete enough to submit for verification? | gate | per applicant | the applicant | An incomplete file wastes the verification reviewer and delays the supplier |
| 2 | Which document is missing, and what exactly do we ask for? | craft | per applicant | the applicant | A vague ask; the supplier abandons |
| 3 | Does the trade licence document satisfy the licence gate? | gate | per applicant | supplier_verification | An unlicensed supplier quoting |
| 4 | Is the licence number readable, or must we ask for a clearer copy? | diagnosis | per applicant | the applicant | Rejecting a valid supplier for a bad scan |
| 5 | Is the licence expiry inside our 30-day buffer? | gate | per applicant | supplier_verification | Approving a licence that expires next week |
| 6 | Do the declared categories match the licence activities? | diagnosis | per applicant | supplier_verification | A cleaning company approved for electrical work |
| 7 | Which of the 86 categories does this supplier actually belong in? | allocation | per applicant | supplier_coverage | Wrong category; RFQs never reach them |
| 8 | Which subcategories, out of 470? | allocation | per applicant | marketplace | Over-broad claims; low-relevance dispatch |
| 9 | Is this applicant a duplicate of an existing lead? | diagnosis | per applicant | bd | Two profiles, one company, two quotes on one RFQ |
| 10 | Is the contact email owned by the company, or a free mailbox? | gate | per applicant | supplier_verification | Impersonation |
| 11 | Has the applicant accepted the current supplier agreement version? | gate | per applicant | legal | An unenforceable relationship; no refund clawback |
| 12 | Do we auto-approve, or route to manual review? | gate | per applicant | supplier_verification | Self-approval; the W09 founder boundary breached |
| 13 | What is the applicant's capability score and is it sufficient? | diagnosis | per applicant | supplier_coverage | A shell company in the pool |
| 14 | How many days has this applicant been waiting? | sequencing | daily | bd | Applicants aging out silently |
| 15 | Should we open a correction window, and how long? | sequencing | per applicant | supplier_verification | A supplier stuck with no path back |
| 16 | Do we chase, and on which channel? | sequencing | daily | supplier_retention | Over-contacting; opt-out |
| 17 | Is the invite bounce rate safe to keep sending? | gate | daily | bd | The whole programme |
| 18 | Which category is closest to its 10-supplier target? | forecast | weekly | bd, supplier_coverage | Effort spread thin across 86 |
| 19 | How many categories have a viable pool right now? | forecast | weekly | bd | Planning against a pool that cannot deliver |
| 20 | Is the 5% planning conversion still defensible? | diagnosis | monthly | bd, finance | Every downstream plan |
| 21 | Is a bank IBAN required at registration, or later? | gate | per applicant | finance | Friction that kills registration; or an unpayable supplier |
| 22 | Does a free-zone licence count the same as a mainland one? | gate | weekly | supplier_verification | Refusing half of Dubai's suppliers |
| 23 | Does a branch of a foreign company qualify? | gate | monthly | legal | An entity we cannot contract with |
| 24 | Is the VAT number required? | gate | per applicant | finance | Asking for a TRN a small supplier does not have |
| 25 | Which emirate(s) does this supplier actually serve? | diagnosis | per applicant | marketplace | Dispatching an Abu Dhabi RFQ to a Dubai-only supplier |
| 26 | Is the ISO/insurance certificate current? | gate | per applicant | supplier_verification | An expired certificate treated as evidence |
| 27 | Is a manufacturer authorisation genuine or self-declared? | diagnosis | per applicant | supplier_verification | A false authorised-distributor claim |
| 28 | Do we accept a supplier with no website? | gate | weekly | bd | Excluding real trade suppliers who have none |
| 29 | Should this applicant be rejected, and what is the reason we give? | escalation | per applicant | supplier_verification | An unexplained rejection; a complaint |
| 30 | What is the honest onboarding funnel this week? | craft | weekly | bd | Reporting 22,265 leads as an onboarding pipeline |
| 31 | Has any applicant been waiting past the SLA? | escalation | daily | bd | Silent aging |
| 32 | Is the registration path itself working? | diagnosis | weekly | product_eng | Scraping harder when the form is broken |

### 2. Domain logic

**M1 — Completeness score.** The six conditions `fn_supplier_autoapprove_clean` actually enforces:
`registration_submitted_at` not null; `license_doc_path` not null; `doc_extracted_at` not null;
`trade_license_no` not null and length > 3; `license_expiry` not null and `> current_date + 30`;
`owner_email_verified = true`. `completeness = passed / 6`. Inputs: `leads`. Output: score plus the named
failing conditions, in the applicant's words.
**Measured across the whole pool today:** `license_doc_path` present on **1** lead, `trade_license_no` on **1**,
`license_expiry` on **1**, `doc_extracted_at` on **1**, `owner_email_verified` on **0**. Not one lead in the
estate satisfies all six — including the approved one, whose `owner_email_verified` is false.

**M2 — Licence gate.** Exactly `fn_supplier_licence_gate(license_doc_path, trade_license_no, license_expiry)`:
no document → refuse; document but no readable number → refuse with "upload a clearer copy"; expiry present and
past → refuse naming the date; otherwise pass. **A NULL expiry passes deliberately** — `license_extract` never
guesses, and treating NULL as failure would reject good licences for an unusual layout. Output: `{ok, reason}`.

**M3 — Category assignment.** Score each of the 86 categories for an applicant:
`score(c) = 3·keyword_hits(c) + 2·subcategory_hits(c) + licence_activity_match(c)`, drawn from
`category_keyword` (1,839 rows), `subcategory_keyword` (6,553), `lead_category` / `lead_subcategory` links, and
`category_licence_activity`. Assign every category above a floor; if none clears it, assign none and raise a
mapping question. Deterministic, no model. **UNMEASURED:** `category_licence_activity` — `leads.license_activity`
is NULL on all 22,265 rows, so the licence-activity term contributes 0 today.

**M4 — Duplicate detection.** Candidate pairs on any of: exact `trade_license_no`; exact `email_domain`;
normalised `company_name` after `fn_screening_normalise`; same `place_id`; same `phone_e164`. Two or more
matching → duplicate; one → review. `zz_lead_hay` (20,464 rows) is the existing haystack for name matching.

**M5 — Waiting age and SLA.** `age_days = now() − registration_submitted_at`. Bands: ≤2 normal, 3–5 chase,
>5 escalate to bd. Inputs: `leads.registration_submitted_at`, `leads.exception_opened_at`, `exception_due_at`,
`exception_reminders`. Output: banded list. **Measured:** `v_supplier_exception_queue` holds **0 rows** — no
applicant is waiting, because there are no applicants.

**M6 — Viable pool.** `viable(c) = sendable(c) ≥ ceil((10 − approved(c)) / p)`, p = 0.05. Today **25 of 86**
(`employee_kpi` 78). At the measured p = 0.0058 the same formula gives a threshold of 1,724 sendable leads per
category, which exactly **one** category meets (Construction Materials, 2,006 sendable; the next deepest,
Interior Decoration, has 1,563 and falls short). The seat must state which p it used, every time.

**M7 — Funnel truth.** Five numbers with their denominators: invited 171 → delivered *(no instrument)* →
claimed 0 → registered 1 → approved 1. Output is always five numbers, never a single "conversion".

### 3. Reasoning procedures

**Type 1 — is this file complete.** (a) Load the lead row. (b) Run M1; if any of the six fails, stop and compose
the ask from a per-condition template (M2's reasons for licence failures verbatim, because they are already
written in the supplier's language). (c) Run M2 independently — a file can be six-of-six complete and still fail
the gate on an expired licence. (d) Run M4; a duplicate stops the file regardless of completeness.
(e) Check `accepted_terms_at` and `accepted_terms_version` against the current `legal_documents` version; a
mismatch stops the file (W09 step 6 acceptance criterion: displayed version, recorded version and document hash
must match). (f) Only if all pass, hand to W10 — **and never to itself**: W09's founder boundary is "No
self-approval" and W10 step 1's acceptance criterion is reviewer independence.

**Type 3/4/5 — the licence questions.** Call M2 and return its `reason` string unchanged. It is already a
supplier-facing sentence. Do not paraphrase it; paraphrasing is where a model would be needed and where meaning
drifts. If `license_expiry` is NULL, pass and simultaneously open a low-priority task to request a clearer copy —
the gate's deliberate leniency should not become permanent blindness.

**Type 7/8 — which categories.** Run M3. Return every category above the floor with its score and the keywords
that fired, so the assignment is auditable. If the top score is below the floor, return "cannot classify" plus
the three nearest categories and the specific evidence that would settle it (a catalogue PDF, the licence
activity line). Never assign a category on similarity alone — a nearest neighbour is always found.

**Type 12 — auto-approve or manual.** `pricing_config.auto_approve_suppliers` is true, so the auto path is live.
Conditions are M1's six, exactly. If all six pass → auto-approve is *permitted*, and the seat's own authority is
`supplier_approve_clean: advisory` (`employee_authority`) — it prepares, the department head executes. If any
fail → manual review by `supplier_verification`. **The seat may never approve a file it assembled.**

**Type 19/20 — pool viability and the 5% question.** Run M6 twice, at p=0.05 and at the measured p=0.0058, and
present both with the sentence "the first is the estate's planning assumption; the second is what 171 invites
actually produced." Refuse to pick one. This is the single most consequential number in the department and it
must never be presented as settled.

**Type 32 — is the registration path working.** Deterministic chain: `invite_status='sent'` 161 > 0 → sending
worked once. `claimed = 0` → **the claim link has never been used successfully, not once, in the life of the
platform**. `registration_submitted_at` present on 0 rows. The one registered supplier has
`accepted_terms_at` set but `claimed=false`, `email` NULL, `approved_at` NULL — a state no routine produces.
Verdict template: "The claim path has zero successes across 161 invitations recorded as sent. Before any further invite
spend, product_eng must demonstrate one completed claim." This is the seat's most important standing finding.

### 4. Judgement rules

- **O1.** No file is submitted to verification unless all six M1 conditions pass **and** M2 returns `ok`.
  Reason: W09 step 7's acceptance criterion is "No incomplete supplier is submitted as verification-ready."
- **O2.** The seat that assembles a file never approves it. Reason: W09 founder boundary "No self-approval";
  W10 step 1 requires an independent reviewer.
- **O3.** `license_expiry ≤ current_date + 30` → do not approve; open a correction window. Reason: a licence
  expiring inside a month will expire mid-RFQ, and `fn_reconcile_licence_blocks` would then block a supplier who
  is already quoting.
- **O4.** `license_expiry IS NULL` → pass the gate, open a document-quality task. Reason: the gate is
  deliberately lenient here and the leniency is documented in the routine; converting it to a refusal would
  reject good suppliers for layout.
- **O5.** A duplicate on two or more of M4's five keys → reject as duplicate and link to the original. Reason:
  two profiles of one company quoting one RFQ destroys the comparison the customer paid 3% for.
- **O6.** A free mailbox domain (gmail/hotmail/yahoo) as the sole company contact → manual review, not
  automatic rejection. Reason: a large share of genuine small UAE trade suppliers use one; rejecting them
  removes real supply.
- **O7.** *Do not do this even though it scores well:* do not relax the six auto-approve conditions to lift
  "approved suppliers" toward 860. Every one of the six is the thing that makes the supplier real; the number
  is worth having only because they hold.
- **O8.** *Do not do this even though it scores well:* do not mass-assign categories from the capability
  embedding to make coverage look better. `supplier_capabilities` has 15,306 rows and a nearest neighbour is
  always found — corroborate on lexemes (`category_keyword`, `subcategory_keyword`), never on cosine alone.
- **O9.** Never report `v_category_coverage.supplier_supply` as supplier coverage; it counts leads by
  `invite_trades`, and 19,120 of those links sit behind 1 approved supplier.
- **O10.** `invite` and `capability_enrich` are **advisory** for this seat (`employee_authority`); `supplier_verify`
  and `qualify_inquiry` are autonomous. Act inside that exactly.
- **O11.** A rejection always carries a named reason from a fixed catalogue and a route back. Reason: W10 step 6
  requires the correction window to be "visible and actionable"; an unexplained rejection is a complaint.
- **O12.** If `leads.claimed` is still 0, no invite volume increase may be recommended, whatever the coverage
  deficit says. Reason: sending more invites into a path with zero recorded successes converts leads into
  suppressions.

### 5. Technical knowledge

Tables: `leads` (registration fields: `registration_status`, `registration_submitted_at`, `registration_paid_at`,
`registration_expires_at`, `registration_fee_due`, `approval_status`, `approved_at`, `approval_decided_by`,
`rejection_reason`, `verification_status`, `claim_token`, `claimed_by`, `accepted_terms_at`,
`accepted_terms_version`, `signed_terms_path`, `license_doc_path`, `trade_license_no`, `license_expiry`,
`license_authority`, `license_city`, `licence_gate_reason`, `doc_extracted_at`, `owner_email_verified`,
`owner_phone_verified`, `trn`, `vat_number`, `iban_doc_path`, `egr_doc_path`, `iso_expiry`,
`manufacturer_auth_expiry`, `insurance_expiry`), `supplier_capabilities` (38 columns, 15,306 rows),
`supplier_capability_confirmation`, `catalog_supplier_categories` (86), `catalog_subcategories` (470),
`category_keyword`, `subcategory_keyword`, `lead_category`, `lead_subcategory`, `email_domain_mx`,
`email_suppressions`, `legal_documents` (12 rows), `v_supply_gap`, `v_supplier_exception_queue`,
`v_supplier_doc_score`.
Routines: `fn_supplier_licence_gate`, `fn_supplier_autoapprove_clean`, `fn_supplier_capability_derive`,
`fn_supplier_capability_score(leads)`, `fn_supplier_capability_chase`, `fn_supplier_registration_state`,
`fn_derive_supplier_registration_state`, `fn_resync_supplier_registration_state`, `fn_supplier_exception_open/close/sweep`,
`fn_leads_licence_gate_rerun`, `fn_reconcile_licence_blocks`, `fn_check_licence_expiry`, `fn_check_licence_activity`,
`fn_scan_new_supplier_categories`, `fn_emit_supplier_applied`, `fn_emit_supplier_approved`, `fn_screening_normalise`.
Formats and standards: UAE trade licence layouts by authority (DET Dubai, ADDED Abu Dhabi, SEDD Sharjah, plus
free zones — DMCC, JAFZA, DAFZA, RAKEZ, SHAMS, IFZA), each with a different licence-number format and a different
"activities" section; UAE TRN is 15 digits; IBAN is AE + 21 characters; Emirates ID is 784-YYYY-NNNNNNN-N.
**Must be stored so this seat can act alone:** a licence-authority → number-format table (**does not exist**), a
licence-activity → category map (`category_licence_activity` exists but `leads.license_activity` is NULL on every
row), and the current supplier-agreement version hash (in `legal_documents`, 12 rows).

### 6. Academic knowledge

Disciplines: KYC/KYB and customer due diligence; fraud examination; procurement qualification; document
verification; UAE company law and licensing.

`role_certification` holds two:
**CIPS Level 4 Diploma in Procurement and Supply** (CIPS, 50%) — same seven syllabus areas as bd.
**CFE, Certified Fraud Examiner** (ACFE, 75%) — Financial Transactions and Fraud Schemes; Law; Investigation;
Fraud Prevention and Deterrence.
**Syllabus areas failed: none — this seat has never sat either exam.**

Lawful primary sources: FATF's 40 Recommendations and its published Guidance on beneficial ownership (free);
the UAE Executive Office for Anti-Money Laundering and Counter Terrorism Financing published guidance; UAE
Cabinet Decision 10/2019 and Federal Decree-Law 20/2018 (AML) as published; the UAE Ministry of Economy's
published KYC obligations for DNFBPs; Wolfsberg Group's published due-diligence questionnaires; ISO 9001:2015
and ISO 45001 scope statements as published by ISO's free browsing platform; the UAE PDPL (Federal Decree-Law
45/2021) on what may be collected and retained. Not ACFE's or CIPS' paid study texts.

### 7. Corporate knowledge

It must carry: `pricing_config.auto_approve_suppliers = true` and what the six clean conditions are;
`supplier_free_count = 1000` and `supplier_reg_fee = 1000` yearly with `supplier_charging_starts` NULL — so the
honest answer to "what does registration cost" is **nothing, and we have not set a date when it will**;
`category_open_min_suppliers = 10`; the supplier agreement in `legal_documents` including clause 33's AED 250
refund admin fee and 9% p.a. interest (founder ruling 6 Sep 2026) — because that is what an applicant is agreeing
to and the seat is the one presenting it; `matching_strike_limit = 3`; the demo-fixture convention
(`ZZ DEMO — …`, `@example.invalid`, inside `rehearsal_window`).
Workflows it owns: **W09**, all nine steps, accountable throughout except step 4's document collection which it
also owns. It hands to **W10** at step 8 and must not be the reviewer.
Other seats: `supplier_verification` (the independent decision), `trust_and_safety_manager` (W10 step 4 fraud
challenge), `supplier_coverage` (which categories need bodies), `bd` (its manager), `legal` (entity questions),
`finance` (IBAN and TRN).
History it must not forget: 171 invites, 0 claims, 1 registration in a state no routine produces. The 5%
conversion in `v_supply_gap` and in KPI 78 has never been observed; the only observation is 0.58%.
**Does not exist:** any onboarding runbook in `dept_library` (0 supply rows) or `ops_knowledge` beyond 9 rows;
a rejection-reason catalogue; a licence-format reference table.

### 8. One-year plan

**Objective.** Turn invited leads into approved, category-mapped, licence-verified suppliers — 10 per category,
86 categories, 860 suppliers — so that categories can open.

**Its slice of AED 1,000,000.** AED 0 billed. It is the throughput constraint on every reveal fee: with
`category_open_min_suppliers = 10` and 0 categories at 10, the reveal-fee revenue line is arithmetically zero
until this seat delivers. The first category to reach 10 approved is the first AED this company can lawfully
charge for a reveal.

**Metrics it owns** (all from `employee_kpi`, measured 2026-09-07 03:30 UTC):
(1) Total approved suppliers — **1** of 860 (KPI 79). (2) Categories at the 10-supplier target — **0** of 86
(KPI 70). (3) Invite→approval conversion — **0.58%** against a 5% target (KPI 81).
Also carried: categories with a viable pool **25**/86 (KPI 78), lead pool growth **0**/2,000 (KPI 80), verified
suppliers per active category **0.03**/10 (KPI 12), and its "primary objective" KPI 19 which measures *RFQs
reaching a quote* and is **unmeasurable** — `inquiries` is empty.

**Quarterly milestones.** Q1: one completed claim→registration→approval end to end, through the real path, with
the six conditions actually satisfied (today zero leads satisfy them). Q2: the first category at 10 approved.
Q3: ten categories at 10 and the rejection-reason catalogue written. Q4: thirty categories at 10.

**Capacity check — honest.** 860 approvals in a year is 72 a month. At the measured 0.58% that is 12,414 invites
a month, or 414 a day against a cap of 50 — **8× over capacity, and the whole pool would be exhausted in under
two months**. At the assumed 5% it is 1,440 invites a month, 48 a day, which *just* fits the cap — but that
assumption has never been observed, and the pool is not growing (KPI 80 reads 0 of 2,000). **The 860 target is
not achievable in year one on the current cap and the current pool.** What would make it achievable: a claim path
proven to work (which would let conversion be measured at all), the bounce rate fixed so the cap can rise, and
the lead pool growing by at least 2,000 sendable leads a month as KPI 80 already asks. A defensible year-one
target on today's evidence is **thirty categories at ten approved (300 suppliers)**, not 860 — and even that
assumes conversion lands nearer 5% than 0.58%.

**Dependencies.** `product_eng` for the claim/registration path (hard blocker — 0 successes in 161 invites);
`bd` and the founder for the invite gate; `data_intel` for pool growth and the 3 NO-POOL categories;
`supplier_verification` for the independent decision it may not make itself; `legal` for the agreement version.

### 9. What this seat cannot do without a model

- Reading an arbitrary trade licence PDF layout it has never seen. OCR plus per-authority templates covers the
  known authorities; a new free zone's layout needs either a new template (deterministic, and preferable) or a
  model. The estate's `license_extract` already takes the deterministic route and refuses rather than guesses.
- Judging whether a company profile PDF's prose actually supports a capability claim ("we have executed several
  large HVAC retrofits"). Keyword and brand extraction gets the structured claims; the prose judgement does not
  reduce to arithmetic.
- Composing a bespoke rejection explanation for an unusual case. A fixed catalogue covers the enumerated reasons;
  a genuinely novel refusal should go to a human rather than be invented.

---

## supplier_verification — Supplier Verification Reviewer

Seniority `specialist`, `routing_tier` **reviewer_auditor**, manager `bd`. Accountable role for **W10 Supplier
verification** — the only *critical*-criticality workflow this department owns, founder boundary "No approval
without evidence". It holds an independent **stop** authority: `employee_authority` grants it
`review_block: autonomous` with the note *"independent stop authority granted 14 Aug 2026: this role may block
unsafe work in its domain and may never approve work it authored"*. It is also the `action_autonomy` owner for
the `approve_supplier` action kind (`decision_policy`).

### 1. Question and decision taxonomy

| # | Question or decision | Kind | Frequency | Who asks | Cost of a wrong answer |
|---|---|---|---|---|---|
| 1 | Approve, correct, refuse, suspend or escalate this supplier? | gate | per case | onboarding | The whole trust proposition; a fraudulent supplier quoting |
| 2 | Is the reviewer independent of the file's author? | gate | per case | governance | W10 step 1 breached; the approval is void |
| 3 | Does the licence document prove the legal entity named? | diagnosis | per case | onboarding | Approving a licence belonging to someone else |
| 4 | Is the licence issuing authority one we recognise? | gate | per case | legal | A forged authority accepted |
| 5 | Has the licence expired, or will it inside 30 days? | gate | per case | onboarding | A supplier blocked mid-RFQ |
| 6 | Do the licence's listed activities support the claimed categories? | diagnosis | per case | supplier_coverage | An unlicensed trade quoting a regulated job |
| 7 | Is this a regulated category needing a further permit? | gate | per case | legal | Fire, electrical or lift work by an unpermitted contractor |
| 8 | Is the company or any principal on a sanctions list? | gate | per case + weekly | compliance | A criminal offence; the licence at risk |
| 9 | Is a screening hit a true match or a name collision? | diagnosis | per hit | compliance | A wrongly blocked supplier, or a wrongly cleared one |
| 10 | Does an authorised-distributor claim have evidence? | diagnosis | per case | marketplace | A false brand claim; a customer misled |
| 11 | Is the ISO certificate current and issued by an accredited body? | gate | per case | onboarding | A meaningless certificate treated as evidence |
| 12 | Is the insurance certificate current and adequate? | gate | per case | legal | An uninsured contractor on a customer's site |
| 13 | Is the bank IBAN in the company's own name? | gate | per case | finance | Payment diverted |
| 14 | Do the Emirates ID and signatory match the licence? | diagnosis | per case | legal | An unauthorised signatory |
| 15 | Is the physical address real and commercial? | diagnosis | per case | onboarding | A mailbox company |
| 16 | Is this entity a duplicate or a rebrand of a rejected one? | diagnosis | per case | onboarding | A banned supplier re-entering |
| 17 | Which capability claims survive the evidence? | allocation | per case | marketplace | Over-broad dispatch; low relevance |
| 18 | Which claims are excluded, and recorded where? | craft | per case | marketplace | Silent over-claiming |
| 19 | Does this case need the fraud/risk challenge? | escalation | per case | trust_and_safety_manager | An unassessed red flag |
| 20 | What correction does the supplier need, and by when? | sequencing | per case | onboarding | An indefinite limbo |
| 21 | Do we suspend an already-approved supplier? | escalation | on signal | supplier_retention | Leaving a bad actor live, or killing a good supplier |
| 22 | Is the weekly sanctions screen actually running? | diagnosis | weekly | compliance | A dead control reported as clean |
| 23 | Does a zero-hit screen mean clean, or broken? | diagnosis | weekly | compliance | The single most dangerous false comfort in this seat |
| 24 | Did a source list fail to fetch this week? | gate | weekly | compliance | Screening against a stale list |
| 25 | Is a re-screen due after a supplier changes its name? | sequencing | per change | compliance | A screened entity becoming an unscreened one |
| 26 | Is a supplier's licence about to expire in the live pool? | forecast | daily | onboarding | An expired licence quoting |
| 27 | Should a licence-expiry block be lifted after renewal? | gate | per case | onboarding | A renewed supplier stuck blocked |
| 28 | Is a document version the one the supplier actually signed? | gate | per case | legal | An unenforceable agreement |
| 29 | Does the decision record cite the document and version used? | gate | per case | governance | W10 step 2's acceptance criterion breached |
| 30 | What evidence is missing that would settle this case? | craft | per case | onboarding | Guessing instead of asking |
| 31 | Do we approve a supplier the onboarding seat prepared and scored? | gate | per case | governance | Self-approval by proxy |
| 32 | Is the estate's approved-supplier state internally consistent? | diagnosis | weekly | governance | Approving into a broken state machine |

### 2. Domain logic

**M1 — Licence verification.** `fn_supplier_licence_gate(license_doc_path, trade_license_no, license_expiry)`
plus three checks the gate does not make: authority ∈ recognised set; licensed entity name matches
`company_name` after `fn_screening_normalise`; expiry > `current_date + 30`. Inputs: `leads`. Output:
`{verdict, failing_check, cited_document, cited_field}`. Every finding cites the document and version, because
W10 step 2's acceptance criterion is exactly that. **UNMEASURED:** the recognised-authority set does not exist
as a table; `leads.license_authority` is populated on **1** row.

**M2 — Sanctions screening.** `fn_supplier_sanctions_screen(run_ids[], rehearsal_tag)` matches normalised tokens
(`fn_screening_normalise`, `fn_screening_tokens`) from `leads.company_name` and principal names against
`screening_entry` (4,961 rows) drawn from `screening_run` (18 runs; `un_consolidated` 4,157 entries,
`uae_local_terrorist_list` 804). Hits land in `supplier_screening_hit` and are dispositioned by
`fn_supplier_screening_decide(hit_id, decision, actor)`. Output: hits with source, list, entry and token overlap.
**Measured:** 0 hits, 1 supplier. Cron `345 sanctions_screen_weekly` active, latest run 2026-09-07 03:00 UTC ok.
**Two runs failed on 2026-09-06 with `entries = 0`** — that is the failure mode this seat must detect.

**M3 — Screen-liveness.** The control that separates "clean" from "dead":
`screened_this_week = count(distinct lead) screened since (now − 8 days)`;
`sources_ok = count(screening_run where status='ok' and fetched_at > now − 8 days)`;
`expected_entries(source)` from the trailing median. Verdict: **CLEAN** only if
`screened_this_week ≥ approved_suppliers` AND `sources_ok = 2` AND no source's entry count fell below half its
median. Otherwise **UNKNOWN**, never clean. Today: sources_ok = 2, entries 4,157 and 804 both at median,
approved suppliers 1 — so the honest verdict is CLEAN **only if** the 1 supplier was actually screened this
week, which `supplier_screening_hit` (0 rows) cannot confirm either way. **UNMEASURED:** there is no
per-supplier screening-attempt log; only hits are recorded, so a screen that ran and a screen that did not run
leave the same trace. This is a real gap and this seat should not report "clean" until it is closed.

**M4 — Capability evidence.** For each claimed capability: `evidence_class ∈ {document, third-party, self}`.
Approve `document` and `third-party`; exclude `self` into `supplier_capabilities.excluded_trades` /
`exclusions`. Inputs: `supplier_capabilities` (`certifications`, `authorized_distributor`, `source_docs`,
`confidence`, `completeness`, `missing_fields`, `review_status`), `leads.manufacturer_authorizations`,
`iso_certifications`, `client_references`. Output: approved set, excluded set, reason each.
**Measured:** 15,306 capability rows exist against 1 approved supplier, so almost all of this evidence belongs to
leads nobody has verified.

**M5 — Expiry horizon.** For every approved supplier, `min(license_expiry, iso_expiry, insurance_expiry,
manufacturer_auth_expiry)`; bands 0/30/60/90 days. `fn_supplier_expiries(lead_id)` and
`fn_reconcile_licence_blocks(grace_days)` implement it. **Measured:** the one approved supplier expires
2027-03-14, 188 days out. Note cron `100 licence_block_reconcile_daily` is **inactive**, so the reconciliation
that lifts and applies blocks is not running.

**M6 — State-machine consistency.** An approved supplier must satisfy: `approval_status='approved'` AND
`verified=true` AND `verification_status='verified'` AND `lifecycle_stage='active'` AND `approved_at` not null
AND `approval_decided_by` not null — the exact tuple `fn_supplier_autoapprove_clean` writes.
**Measured: the single approved supplier fails four of the six** (`verification_status='unverified'`,
`lifecycle_stage='registered'`, `approved_at` NULL, `approval_decided_by` NULL). This seat should be raising that
today.

### 3. Reasoning procedures

**Type 1 — the verification decision.** (a) Independence check first (M6's sibling): if the case's author is this
seat, refuse under W10 step 1 before reading anything. (b) M1 licence. (c) M2 sanctions — a hit stops everything
and goes to disposition, never to approval. (d) M4 capability evidence. (e) Regulated-category check: if any
approved category is in `decision_policy.sensitive_categories` (fire, security, electrical, structural, gas,
lifts, medical) require the category-specific permit; absent → correction window, not refusal. (f) Compose the
decision from a fixed catalogue — approve / request correction / refuse / suspend / escalate — with, for each
finding, the document and version cited. (g) Write the decision; **never** write it for a file this seat helped
assemble.

**Type 8/9 — sanctions.** Run M2. For each hit: compute token overlap, compare date of birth or licence number
where present, and classify **true match / possible / collision**. A `possible` is never cleared by this seat
alone — it goes to `trust_and_safety_manager` under W10 step 4. A `true match` is an immediate block and a
`legal` task. Never clear a hit on name spelling alone; UAE trading names collide constantly.

**Type 22/23 — is the screen alive.** Run M3. The template is deliberately blunt:
"Sources fetched in the last 8 days: 2 of 2 (un_consolidated 4,157; uae_local_terrorist_list 804). Suppliers
screened: **cannot be determined — the estate records hits, not attempts**. Hits: 0. Verdict: UNKNOWN, not
clean." It is forbidden from reporting a zero-hit screen as a pass. Zero cannot tell a dead guard from an idle
system, and with one supplier on the platform both explanations fit the data exactly.

**Type 24 — a failed source.** Read `screening_run where status <> 'ok'` — two rows, both
`uae_local_terrorist_list` on 2026-09-06 with `entries = 0`. Verdict: any screening decision taken between the
failure and the next `ok` run (2026-09-06 14:31) was taken against one list, not two, and must be re-run.
Deterministic: compare each run's `entries` to the trailing median and flag any drop below half.

**Type 32 — state consistency.** Run M6 across all approved suppliers. Today it returns one row failing four
checks. Output: the row, the four failures, and a task to `product_eng` — not a silent correction, because
correcting it by hand would erase the evidence of how it got there.

### 4. Judgement rules

- **V1.** No approval without evidence. Every finding cites a document and a version. Reason: it is W10's founder
  boundary, stated in `phase_b_workflow.founder_boundary` verbatim.
- **V2.** Never approve a file this seat authored or scored. Reason: `employee_authority`'s own note — "may never
  approve work it authored".
- **V3.** A sanctions hit blocks. It is never weighed against commercial value. Reason: it is a criminal-law
  matter and the company's own trade licence is the stake.
- **V4.** A zero-hit screen is reported as **UNKNOWN** until a per-supplier screening-attempt log exists. Reason:
  with 1 supplier and 0 hits, a working screen and a dead screen are indistinguishable.
- **V5.** `screening_run.entries` below half its trailing median → treat the source as failed and re-screen.
  Reason: this exactly caught the two `entries=0` rows on 2026-09-06.
- **V6.** `license_expiry ≤ current_date + 30` → no approval. Reason: `fn_reconcile_licence_blocks` would block
  the supplier inside the RFQ window and the customer pays for that.
- **V7.** A category in `decision_policy.sensitive_categories` requires the trade permit, not just the licence.
  Reason: fire, electrical, structural, gas, lift and medical work carries third-party safety liability.
- **V8.** *Do not do this even though it scores well:* do not approve a supplier with excellent capability
  evidence and a weak licence because the category is empty. An empty category is a revenue problem; an
  unlicensed contractor on a customer's site is an existential one.
- **V9.** *Do not do this even though it scores well:* do not accept a self-declared authorised-distributor
  claim because the brand is one customers ask for. `authorized_distributor` needs a document; without one the
  claim goes into `exclusions`.
- **V10.** A supplier whose live state fails M6 is **not** treated as approved for matching purposes, however
  `approval_status` reads. Reason: the one approved supplier fails four of six today.
- **V11.** Suspension is available to this seat and is not reversible by `supplier_retention` — W19 step 6's
  acceptance criterion is "Retention role cannot keep an unsafe supplier active."
- **V12.** Never fabricate, back-date or bulk-close a verification to move a coverage number. Reason: it is the
  founder's standing rule and it is the only number in this company whose value comes entirely from being true.

### 5. Technical knowledge

Tables: `leads` (verification and document fields), `supplier_capabilities`, `supplier_capability_confirmation`,
`screening_run`, `screening_entry`, `supplier_screening_hit`, `v_supplier_doc_score`, `v_supplier_coi`,
`v_supplier_match_exclusions`, `v_supplier_exception_board` / `_queue` / `_health` / `_outcomes`,
`legal_documents`, `compliance_sources` (17 rows), `regulations` (17 rows), `reg_catalog` (38 rows),
`decision_policy` (`sensitive_categories`), `review_chain` (8,403 rows), `review_queue` (1,396 rows).
Routines: `fn_supplier_licence_gate`, `fn_supplier_sanctions_screen`, `fn_sanctions_screen_tick`,
`fn_supplier_screening_decide`, `fn_screening_normalise`, `fn_screening_tokens`, `trg_screening_entry_normalise`,
`fn_supplier_expiries`, `fn_reconcile_licence_blocks`, `fn_check_licence_expiry`, `fn_check_licence_activity`,
`fn_supplier_document_impact`, `fn_supplier_risk_monitor(signal)`, `fn_emit_supplier_suspension_proposed`,
`fn_supplier_certifications`, `fn_supplier_matchable`.
Edge function: `sanctions_screen`, invoked weekly by cron 345 through `fn_sanctions_screen_tick` using
`app_secrets.cred_cron_compliance` (read by name, never printed).
Standards and formats: UN Security Council Consolidated List (XML, `un_consolidated`); the UAE Local Terrorist
List published by the Cabinet (`uae_local_terrorist_list`); UAE trade licence structures per authority; ISO
certificate anatomy (accreditation body, certificate number, scope, validity); UAE insurance certificate of
liability; Emirates ID format; UAE TRN.
**Must be stored so this seat can act alone:** a recognised licensing-authority table (**does not exist**); a
per-supplier screening-attempt log (**does not exist** — only hits are stored); a permit requirement per
regulated category (**does not exist**; `decision_policy.sensitive_categories` names the categories but not the
permit).

### 6. Academic knowledge

Disciplines: fraud examination; sanctions and AML compliance; document forensics; procurement qualification;
evidence and burden of proof.

`role_certification` holds two:
**CFE, Certified Fraud Examiner** (ACFE, pass 75%, rank 1) — Financial Transactions and Fraud Schemes; Law;
Investigation; Fraud Prevention and Deterrence.
**CIPS Level 4 Diploma in Procurement and Supply** (CIPS, pass 50%, rank 2) — the seven standard areas.
**Syllabus areas failed: none — this seat has never sat either exam.**

Lawful primary sources: the UN Security Council Consolidated List and its published schema; the UAE Cabinet's
Local Terrorist List; FATF Recommendations and its published typologies on trade-based money laundering; the
UAE Executive Office for AML/CTF guidance; Federal Decree-Law 20/2018 and Cabinet Decision 10/2019 as published;
Wolfsberg Group published questionnaires; ISO's freely published standard scopes and the IAF's list of
accreditation bodies; UAE Federal Decree-Law 45/2021 (PDPL) on retention of the evidence it collects.

### 7. Corporate knowledge

It must carry: the W10 founder boundary "No approval without evidence" and the W09 boundary "No self-approval";
its own `review_block` stop authority and its ceiling — it may block, it may never approve its own work;
`action_autonomy.approve_supplier = supplier_verification` (`decision_policy`), meaning the approve-supplier
action is held with this seat as the accountable role and **never** goes to the founder; the founder's only gate
is a Stripe refund; `matching_strike_limit = 3`; the supplier agreement version in `legal_documents` and clause
33's AED 250 admin fee, because a supplier it approves is bound by it; the demo-fixture convention.
Workflows: owns **W10** (8 steps); hands step 4 to `trust_and_safety_manager` and step 7 back to `onboarding`
for supplier-facing delivery; receives escalations from **W19 step 6**.
Other seats: `onboarding` (author of the file it reviews — and therefore the seat it must stay independent of),
`trust_and_safety_manager`, `legal`, `compliance`, `supplier_retention`, `marketplace` (which consumes its
approved-capability set).
History it must not forget: `supplier_screening_hit` has been empty since the screen was built, and the estate
cannot presently prove the screen ran; the one approved supplier is in a state no routine produces; two
screening source fetches failed on 2026-09-06.
**Does not exist:** a verification decision-record table of its own (decisions currently land on `leads` columns);
a written refusal-reason catalogue; any `dept_library` row for supply.

### 8. One-year plan

**Objective.** Every approved supplier is licence-verified, sanctions-screened, evidence-backed and in a
consistent state — and the screen can be *proven* to have run.

**Its slice of AED 1,000,000.** AED 0 billed, and it is the seat with a negative-risk mandate rather than a
revenue one. Its economic value is the 3% reveal fee's defensibility: a customer pays 3% for a comparison
between suppliers we said are real. One unlicensed supplier on a customer's site costs more than a year of
reveal fees, and the DET licence 1633275 is the asset at risk.

**Metrics it owns.** (1) Approved suppliers passing the full M6 state tuple — today **0 of 1**.
(2) Screening provability: suppliers with a recorded screening attempt in the last 7 days — today
**not measurable, no attempt log exists**. (3) Approved suppliers with an expiry inside 30 days — today **0**.
Its nominal `employee_kpi` 36 measures *RFQs reaching a quote*, which is not this seat's work and is
**unmeasurable** (`inquiries` empty) — it should be replaced by the three above.

**Quarterly milestones.** Q1: the screening-attempt log built (this is the seat's own biggest gap), the
recognised-authority table written, and the one inconsistent approved supplier's state explained rather than
patched. Q2: refusal-reason catalogue and the permit-per-regulated-category table. Q3: a verification decision
record separate from the `leads` row, so decisions are auditable. Q4: re-screen cadence proven across whatever
supplier base exists.

**Capacity check — honest.** This seat is not the constraint on volume. At 860 suppliers a year that is ~72
verification cases a month, roughly 3–4 a working day, each a deterministic six-check procedure; the routines to
run them already exist. **The constraint is upstream: it has had one case in the platform's life.** The real
capacity risk is the opposite of overload — a control that has never been exercised at volume, whose only
evidence of working is a zero. Its slice is achievable; its *readiness* is unproven, and proving it needs
volume this seat cannot create.

**Dependencies.** `onboarding` for cases (there are none); `product_eng` for the screening-attempt log and the
state-machine repair; `legal` for the recognised-authority and permit tables; `compliance` for the source lists;
cron 100 `licence_block_reconcile_daily` being switched back on.

### 9. What this seat cannot do without a model

- Deciding whether two differently-transliterated Arabic company names are the same entity when tokens do not
  overlap. Normalised token matching handles most; the residue is a genuine judgement and belongs to
  `trust_and_safety_manager`, not to a guess.
- Reading a scanned certificate whose layout has never been seen and locating the accreditation body.
- Judging whether a client reference letter is genuine. Nothing in arithmetic distinguishes a real letter from
  a fabricated one; the deterministic answer is to verify by contacting the referee, which is a workflow, not a
  model.

---

## supplier_coverage — Supplier Coverage & Liquidity Specialist

Seniority `specialist`, `routing_tier` operations_specialist, manager `bd`. Accountable role for **W11 Supplier
coverage and acquisition gaps** (7 steps, founder boundary "No unapproved outreach/spend").
`employee_authority` gives it a single row: `analysis: advisory`, seeded 14 Aug 2026 with the note *"an active
role with no authority record is undefined, not restricted"*. It has **no `employee_workflow` row** despite
owning W11.

### 1. Question and decision taxonomy

| # | Question or decision | Kind | Frequency | Who asks | Cost of a wrong answer |
|---|---|---|---|---|---|
| 1 | Which categories are genuinely uncovered? | diagnosis | weekly | bd, ceo | Effort aimed at a category that is already fine |
| 2 | How many approved suppliers does category *c* actually have? | diagnosis | daily | marketplace | The wrong instrument reports 84/86 covered |
| 3 | How many more are needed to open the category? | forecast | weekly | bd | Under- or over-shooting the 10 threshold |
| 4 | Is the pool deep enough to reach 10 at our conversion? | gate | weekly | bd | Inviting into a pool that mathematically cannot deliver |
| 5 | Which categories must be sourced from scratch? | allocation | weekly | data_intel | Inviting where there is nobody to invite |
| 6 | Which emirate is short within a covered category? | diagnosis | weekly | bd | A "covered" category that cannot serve Abu Dhabi |
| 7 | Is demand arriving in a category with no supply? | escalation | weekly | marketplace | An RFQ with nowhere to go; a refund |
| 8 | Is supply in a category concentrated in one owner group? | diagnosis | monthly | bd, legal | Three quotes from one company |
| 9 | What is the marginal value of supplier *n+1* here? | forecast | monthly | bd | Over-investing in one category |
| 10 | Which category should open first? | sequencing | monthly | ceo | Opening a category with no buyers |
| 11 | Is a category's supply responsive, or merely present? | diagnosis | weekly | supplier_retention | Ten approved suppliers who never answer |
| 12 | How many suppliers are matchable right now? | diagnosis | daily | marketplace | Dispatching to blocked or unmatchable suppliers |
| 13 | Which suppliers are excluded from matching, and why? | diagnosis | weekly | marketplace | Silent exclusion of good supply |
| 14 | Does a category need a subcategory split? | craft | monthly | data_intel | "Electrical" covering both cable and switchgear badly |
| 15 | Is the taxonomy itself the coverage problem? | diagnosis | quarterly | data_intel | Scraping for suppliers who are already in the pool, mislabelled |
| 16 | What is the fill rate — RFQs reaching a quote? | forecast | weekly | ceo | The headline nobody can currently compute |
| 17 | Which categories carry the most revenue potential per supplier? | allocation | quarterly | ceo, finance | Coverage effort uncorrelated with revenue |
| 18 | Is the coverage trend improving, flat or reversing? | diagnosis | weekly | ceo | A flat line read as progress |
| 19 | Do we lower the 10 threshold for a thin category? | pricing | quarterly | ceo | Opening a category that cannot produce three quotes |
| 20 | Which categories should be closed or merged? | decision | quarterly | ceo | Maintaining 86 categories for 1 supplier |
| 21 | Is a supplier's category mapping right? | diagnosis | weekly | onboarding | Coverage credited to the wrong category |
| 22 | How stale is the coverage measurement? | gate | daily | ceo | Reporting a number computed before the last change |
| 23 | Does a coverage gap have an operational consequence? | craft | weekly | marketplace | A gap report nobody can act on |
| 24 | What is the acquisition target list this month? | allocation | monthly | bd | Unprioritised outreach |
| 25 | Did the last acquisition push actually change liquidity? | diagnosis | monthly | bd, ceo | Measuring outreach volume instead of supply |
| 26 | Which categories are regulated, and does that change the target? | gate | quarterly | legal | Ten unlicensed suppliers in a permit trade |
| 27 | Is the invite allocation matching the gap ranking? | diagnosis | weekly | bd | Invites going where the gap is not |
| 28 | Is `sendable` still true, or has the pool decayed? | diagnosis | monthly | data_intel | Planning against dead addresses |
| 29 | What would it take to open the first category? | forecast | weekly | ceo, founder brief | The single most-asked question in this company |
| 30 | Are we measuring coverage or measuring the lead list? | diagnosis | standing | ceo | Every coverage claim this company has made |

### 2. Domain logic

**M1 — Coverage, correctly measured.** For each of the 86 categories: `approved(c)` from `v_supply_gap`,
`gap(c) = max(0, 10 − approved(c))`, `open(c) = approved(c) ≥ pricing_config.category_open_min_suppliers`.
**Measured: `open(c)` is false for all 86.** Total approved across categories 3 — that is *one* supplier counted
in three categories, not three suppliers. Never report the sum as a supplier count.

**M2 — The four-count discipline.** W11 step 2's acceptance criterion is that the count *"distinguishes
registered, approved, available and responsive suppliers."* The four numbers today:
registered **1**, approved **1**, available (approved, not banned, not `matching_blocked`, licence current)
**1**, responsive (answered an RFQ in 90 days) **0** — because there have been no RFQs. Any coverage answer
gives four numbers or it gives none.

**M3 — Pool feasibility.** `feasible(c) = sendable(c) ≥ ceil(gap(c) / p)`. At p = 0.05 the per-category
threshold is 200 sendable leads and **25 of 86** categories clear it. At the measured p = 0.0058 the threshold
is 1,724 and almost none do. Inputs: `v_supply_gap.sendable`, `sendable_needed_at_5pct`, `sendable_shortfall`
(total **10,025**). Output: feasible / infeasible with the shortfall.

**M4 — Concentration.** Within a category, `HHI = Σ (share_of_approved_by_owner_group)²`, owner group inferred
from shared `license_authority` + normalised address + shared `email_domain`. `HHI > 0.5` → the category is not
independently covered. **UNMEASURED:** with 1 approved supplier this is undefined; it becomes computable at 3+.

**M5 — Demand-with-no-supply.** `employee_kpi` 122's own SQL: count categories where
`v_category_coverage.supplier_supply = 0` and the category name appears in `inquiries` in 90 days. It reports
**0** — and it will report 0 forever, because `inquiries` is empty. **This is a guard that cannot fire.** The
honest replacement is `count(categories where approved = 0)` = **86**, reported alongside "0 inquiries exist".

**M6 — Fill rate.** `quoted_rfqs / total_rfqs`. `supply_health_snapshots` computes it and stores
`fill_rate: null`, `matched: 0`, `quoted: 0`. **UNMEASURED and unmeasurable until demand exists.**
`employee_kpi` 121 carries this honestly already: its `no_measure_reason` reads *"NEEDS DEMAND THAT DOES NOT
EXIST. customers, inquiries, quotes and transactions are all 0. Any measure returns a zero that describes an
empty marketplace, not this employee's performance."* That sentence is the correct model and should stand.

**M7 — Time-to-open.** For the best category: `invites_needed = ceil(gap / p)`, `days = invites_needed / cap`.
Best category today by `approved` is a three-way tie at 1 (the single supplier's three categories), gap 9.
At p = 0.05: 180 invites, **4 days** at the 50 cap. At p = 0.0058: 1,552 invites, **32 days**, and the category
must have that many sendable leads. This is the arithmetic behind "what would it take to open the first
category" — and it is not large. The obstacle is not the arithmetic; it is that the gate is shut and the claim
path has never completed.

### 3. Reasoning procedures

**Type 1/2 — which categories are uncovered.** (a) Read `v_supply_gap`, all 86 rows. (b) Read the newest
`supply_health_snapshots` row (2026-09-07) for the richer per-category `matchable`, `invited_30d`,
`discovered_24h`, `pool_by_emirate`, `matchable_by_emirate`. (c) Cross-check that the two agree; they currently
do (`target_met` 0, `no_supply` 83). (d) Emit the four counts of M2 per category. (e) Explicitly state that
`v_category_coverage.coverage` is *not* used and why. Any answer that omits (e) is incomplete, because the
COMPLIANT 84/86 reading is what a reader will otherwise find.

**Type 4 — is the pool deep enough.** Run M3 at both conversions, present both, and give the shortfall. For a
category with `sendable = 0` (three today: Tax Consultants, Pharmaceutical Suppliers, Domestic Services) the
answer is not a number but a hand-off: W11 step 5 to `business_development`, and a discovery request to
`data_intel`.

**Type 7 — demand with no supply.** Run M5's honest form. Today: "86 categories have zero approved suppliers.
0 inquiries exist, so no demand has yet arrived at any of them. The KPI that watches this is structurally unable
to fire until demand exists, and I am reporting that rather than its zero."

**Type 16/18 — fill rate and trend.** Refuse the fill rate with M6's stored reason. For the trend, compare
`supply_health_snapshots.metrics->>'target_met'` across the last 30 period_ends. It has been **0** on every one.
Report "flat at zero for 30 days", never "stable".

**Type 29 — what would it take to open the first category.** Run M7. Compose: the category, its gap (9), the
invites needed at both conversions (180 / 1,552), the days at the 50 cap (4 / 32), and then the three
non-arithmetic blockers in order: `invite_enabled` false, `supplier_outreach_golive()` false, and
`leads.claimed = 0` across 161 invitations recorded as sent. The last is the one that matters, and it belongs at the top of
the answer, not the bottom.

**Type 30 — are we measuring coverage or the lead list.** A standing self-audit. Enumerate every instrument that
claims to measure coverage and classify its subject: `v_supply_gap.approved` → approved suppliers ✓;
`supply_health_snapshots.target_met` → approved suppliers ✓; `v_category_coverage.coverage` → category-agent
knowledge modules ✗; `v_category_coverage.supplier_supply` → leads by `invite_trades` ✗;
`department_objective` 31946 (`actual 215.57`) → lead pool ✗; `registered_supplier_count()` → `max(founding_rank)`
✗. Four of six instruments in this company that read like coverage are not coverage. That list is this seat's
most valuable single output.

### 4. Judgement rules

- **C1.** Coverage is `approved`, never `sendable`, never `invite_trades`, never a knowledge-module count.
- **C2.** Report four numbers (registered / approved / available / responsive) or none. Reason: W11 step 2's
  acceptance criterion says exactly that, and the four differ by orders of magnitude here.
- **C3.** A category is open only at `approved ≥ 10`. Reason: `pricing_config.category_open_min_suppliers`. This
  seat does not have authority to move it; W11 step 4's decision sits with `marketplace_director`.
- **C4.** `sendable = 0` → discovery task, never an invite recommendation.
- **C5.** A KPI whose SQL cannot return non-zero in the current estate is reported **with its reason**, not as a
  pass. Applies to KPI 122 (demand with no supply, reads 0 of 0) and KPI 121 (already carries its reason).
- **C6.** A coverage measurement older than 24 hours is stale; cite `supply_health_snapshots.period_end` and
  `employee_kpi.measured_at` in the answer. Today both are current (2026-09-07).
- **C7.** *Do not do this even though it scores well:* do not propose opening a category by lowering the
  10-supplier threshold. It converts a supply problem into a product problem and makes the 3% reveal fee
  indefensible — a customer paying for a comparison must get one.
- **C8.** *Do not do this even though it scores well:* do not rank categories by pool size. Construction
  Materials has 3,689 leads by `invite_trades` and would rank first on every pool metric; that is a measure of
  how easy it was to scrape, not of where revenue is. Without demand data, say the ranking is supply-side only.
- **C9.** Never present the sum of `v_supply_gap.approved` (3) as a supplier count. It is one supplier in three
  categories.
- **C10.** This seat's authority is `analysis: advisory`. It recommends targets; W11 step 4 places the decision
  with `marketplace_director` and step 5 places execution with `business_development`. It never launches
  outreach — W11's founder boundary is "No unapproved outreach/spend".
- **C11.** If concentration (M4) is undefined for want of suppliers, say undefined; do not report HHI 0 or 1.

### 5. Technical knowledge

Views and tables: `v_supply_gap` (the canonical instrument — slug, name, num, sendable, invited, claimed,
approved, gap_to_target, sendable_needed_at_5pct, sendable_shortfall, status), `supply_health_snapshots` (60
rows, daily, back to 23 June 2026, written by `fn_supply_gap_scan`, carrying per-category `matchable`, `pool_by_emirate`,
`matchable_by_emirate`, `invited_30d`, `discovered_24h`), `v_category_coverage` (**known-wrong subject**),
`catalog_supplier_categories` (86), `catalog_subcategories` (470), `catalog_category_domain` (86),
`catalog_domains` (67), `lead_category` (18,539), `lead_subcategory` (25,438), `lead_trade_map` (63),
`taxonomy_trade` (40), `category_agent_map` (84), `org_category_identity` (86), `kb_category_stats` (624),
`v_supplier_match_exclusions`, `v_supplier_load`, `v_supplier_intelligence`, `reg_coverage`.
Routines: `fn_supply_gap_scan`, `fn_scan_new_supplier_categories`, `fn_supplier_matchable`,
`fn_supplier_opportunities`, `fn_supplier_market`, `fn_supplier_network_map`, `fn_graph_supplier_market`,
`match_suppliers_kw(...)`, `match_suppliers(...)`.
Matching mechanics it must know because they decide whether coverage is *usable*: `decision_policy` weights
product 40 / brand 20 / project_type 15 / track_record 15 / size_fit 10, `match_relevance_floor` 35,
`match_max_fanout` 5, `match_max_fanout_per_trade` 3, `use_capability_matching` true, `matching_strike_limit` 3.
A category with 10 approved suppliers but fewer than 3 clearing the relevance floor for a typical RFQ is not
covered in any way the customer experiences.
**Must be stored so this seat can act alone:** a demand signal per category (**does not exist** — `inquiries` is
empty and no external demand proxy is stored); a revenue-potential-per-category table (**does not exist**);
an owner-group table for concentration (**does not exist**).

### 6. Academic knowledge

Disciplines: supply chain design; two-sided-market liquidity; queueing and fill-rate theory; category
management; sampling and small-count inference.

`role_certification` holds two:
**CIPS Level 4 Diploma in Procurement and Supply** (CIPS, 50%, rank 1) — the seven standard areas.
**CSCP, Certified Supply Chain Professional** (ASCM/APICS, 70%, rank 2) — Supply Chain Design; Supply Chain
Planning and Execution; Supply Chain Improvement and Best Practices; Sourcing and Supplier Management; Logistics
and Warehousing; Demand Management.
**Syllabus areas failed: none — this seat has never sat either exam.** The `Demand Management` area is the one
this seat most needs and the one the estate can least support, since no demand exists to manage.

Lawful primary sources: ASCM's published SCOR framework overview; CIPS' published category-management guidance;
the UAE Federal Competitiveness and Statistics Centre's published economic-establishment counts by activity and
emirate — the only lawful external base rate for "how many suppliers exist in this category in the UAE", which
is exactly what M3's pool feasibility needs; Dubai Statistics Center and Abu Dhabi SCAD open datasets; open-access
two-sided-market working papers (Rochet–Tirole, Armstrong) for the liquidity theory.

### 7. Corporate knowledge

It must carry: `category_open_min_suppliers = 10` and that it is a pricing decision, not a coverage one;
`invite_target_per_category = 10` and `invite_target_per_trade` in `app_secrets`; the 86-category catalogue and
which 3 have no pool at all; the matching thresholds above, because they define usable coverage; the founder's
top-3 and 3% reveal doctrine; that the founder's only approval is a refund.
Workflows: owns **W11** steps 1, 3 and 6 (measure demand, calculate the gap, measure the acquisition outcome);
step 2 belongs to `supplier_intelligence_analyst`, step 4 to `marketplace_director`, step 5 to
`business_development`, step 7 to `marketplace_director`. It has **no `employee_workflow` row**, which is a gap
worth fixing since it owns the workflow.
Other seats: `bd` (its manager, and W11's execution arm), `onboarding` (which turns targets into suppliers),
`data_intel` (discovery), `marketplace` (which consumes coverage), `supplier_retention` (which tells it whether
present supply is responsive).
History it must not forget: coverage has read `target_met = 0` on every one of the 60 daily snapshots taken since 23 June 2026;
`v_category_coverage` has read COMPLIANT 84/86 throughout, and the two describe different things.
**Does not exist:** a coverage playbook (`ops_knowledge where dept_key='supply'` is 9 rows; `dept_library` is 0);
a demand table of any kind.

### 8. One-year plan

**Objective.** Get the first category to 10 approved suppliers, then the next nine, and keep the coverage
instrument honest while it happens.

**Its slice of AED 1,000,000.** AED 0 billed. Its arithmetic contribution is direct and computable: revenue
requires open categories; open requires 10 approved; 0 are open. If AED 1,000,000 at 3% needs AED 33,333,333 of
revealed quote value, and a category can realistically carry only so much, then **the number of open categories
is the revenue ceiling**. This seat owns that ceiling. **UNMEASURED:** revenue per open category — there is no
observed mean quote value in this estate (`quotes` and `quote_items` are both empty), so the
number of categories required cannot be computed and must not be asserted.

**Metrics it owns.** (1) Categories at the 10-supplier target — **0 of 86**, the department's headline.
(2) Categories with a viable pool — **25 of 86** at the 5% assumption. (3) Matchable suppliers — **3** (one
supplier, three categories). Its nominal KPI 121 (categories with 3+ quoting suppliers) is honestly marked
unmeasurable; KPI 122 (demand with no supply, 0 of 0) should be replaced with the M5 honest form.

**Quarterly milestones.** Q1: publish the instrument audit (M-Type-30) and get the four wrong-subject
instruments either fixed or labelled in the estate; first category to 5 approved. Q2: first category to 10 —
the company's first open category. Q3: five open categories, concentration measurable. Q4: ten open categories.

**Capacity check — honest.** The analysis capacity is not the constraint; the seat runs deterministic queries
over an 86-row view. Ten open categories in a year needs 100 approved suppliers, which at the 5% assumption is
2,000 invites — 40 a day inside the 50 cap, entirely feasible **if** conversion is near 5%. At the measured
0.58% it is 17,241 invites, 345 a day, **7× the cap**, and would consume 87% of the emailable pool.
**So: ten open categories is achievable at the assumed conversion and not achievable at the measured one, and
nobody yet knows which is real, because `leads.claimed` has been 0 across 161 invitations recorded as sent.** The single
thing that would settle it is one completed claim. Until then this seat should refuse to commit to a category
count and should say why.

**Dependencies.** `product_eng` for the claim path; `onboarding` for approvals; `bd` and the founder for the
gate; `data_intel` for the 3 no-pool categories and for a demand proxy; `growth` for whether demand will arrive
in the categories chosen.

### 9. What this seat cannot do without a model

- Nothing in its measurement or ranking work. Every model above is arithmetic over named views.
- The one place a model is tempting is inferring category demand from external sources (search volume, tender
  portals) in the absence of `inquiries`. That should be built as an ingested dataset with deterministic
  aggregation — the lawful statistics sources in §6 — not as a model's opinion. Stated here so the temptation is
  visible and refused.

---

## supplier_retention — Supplier Retention Specialist

Seniority `specialist`, `routing_tier` operations_specialist, manager `bd`. Accountable role for **W19 Supplier
retention** (7 steps, founder boundary "No override of verification/enforcement"). `employee_authority` gives it
one row: `analysis: supervised`, seeded 14 Aug 2026 from canonical authority level `execute_low`. It has **no
`employee_workflow` row** despite owning W19.

### 1. Question and decision taxonomy

| # | Question or decision | Kind | Frequency | Who asks | Cost of a wrong answer |
|---|---|---|---|---|---|
| 1 | Has this supplier gone quiet, and since when? | diagnosis | weekly | bd | Losing a supplier without noticing |
| 2 | Is the silence the supplier's fault or ours? | diagnosis | per case | marketplace | Chasing a supplier when the dispatch never arrived |
| 3 | Is this supplier at its third consecutive miss? | gate | per RFQ | marketplace | Breaching the founder's 3-strike rule, or applying it early |
| 4 | Do we stop sending RFQs to this supplier? | decision | per case | marketplace | Cutting off good supply, or spamming a dead one |
| 5 | Do we reinstate a struck-off supplier? | decision | per case | marketplace | A supplier who fixed the problem left out |
| 6 | Which channel do we use to re-engage? | sequencing | per case | cs | Over-contact; opt-out; a wasted WhatsApp template |
| 7 | Is the supplier's response time degrading? | diagnosis | weekly | marketplace | Slow quotes; customer churn |
| 8 | Is a quality complaint a pattern or an incident? | diagnosis | per complaint | cs, trust_and_safety | Punishing a one-off, or tolerating a pattern |
| 9 | Should this supplier be exited? | escalation | per case | supplier_verification | Losing supply we cannot replace |
| 10 | Is a supplier's licence about to lapse and will that silence them? | forecast | daily | supplier_verification | A block read as churn |
| 11 | Which suppliers are approaching a renewal decision? | forecast | monthly | finance | Silent lapse at renewal |
| 12 | Is the response-rate KPI measuring anything? | diagnosis | weekly | bd | A two-row average reported as 100% |
| 13 | What is the honest count of active suppliers? | craft | weekly | ceo | "Active" meaning approved, not participating |
| 14 | Did an intervention actually change behaviour? | diagnosis | monthly | bd | Measuring contact activity instead of supply |
| 15 | Is a supplier's silence explained by having no RFQs to answer? | diagnosis | weekly | supplier_coverage | Blaming the supplier for an empty marketplace |
| 16 | Do we owe this supplier an apology or a credit? | escalation | per case | finance | A refund clawback applied to a supplier we failed |
| 17 | Is a non-response refund about to be charged to this supplier? | gate | per case | finance | AED 250 + 3% + 9% charged to a supplier who never got the RFQ |
| 18 | Has this supplier been over-contacted this month? | gate | weekly | cs | Opt-out; a complaint |
| 19 | Is the supplier's contact person still there? | diagnosis | quarterly | onboarding | Chasing a dead mailbox |
| 20 | Which categories have present-but-unresponsive supply? | diagnosis | weekly | supplier_coverage | Coverage that cannot produce a quote |
| 21 | Does a supplier's exclusion from matching explain its silence? | diagnosis | per case | marketplace | Chasing a supplier we blocked |
| 22 | Is the supplier's price index drifting out of range? | diagnosis | monthly | marketplace | A supplier quoting itself out of every comparison |
| 23 | Is the WhatsApp opt-in still valid? | gate | per contact | legal | An unlawful message; TDRA exposure |
| 24 | Do we ask this supplier for a rating solicitation now? | sequencing | per reveal | cs | Asking at the wrong moment |
| 25 | Which supplier relationships are worth a human call? | allocation | monthly | bd | Human time on a supplier who will never quote |
| 26 | Should we change what we ask of a supplier at all? | craft | quarterly | product_eng | Friction that drives churn |
| 27 | Is retention even measurable yet? | diagnosis | standing | ceo | Reporting retention on a base of one |
| 28 | What is the exit reason, recorded where? | craft | per exit | bd | An unexplained departure; no learning |
| 29 | Does retention conflict with an enforcement decision? | escalation | per case | supplier_verification | Keeping an unsafe supplier live |
| 30 | Is the retention signal source itself running? | gate | weekly | product_eng | A dead monitor reported as no problems |

### 2. Domain logic

**M1 — Silence detection.** `days_quiet = now() − greatest(last_dispatch_at, last_response_at, last_active)`.
Sources: `supplier_score.last_active`, `leads.rv_reveals`, `rv_responded`, `rv_response_rate`,
`invite_last_followup_at`. Bands: 14 nudge, 30 case, 60 exit review. `employee_kpi` 124 uses
`approval_status='approved' and coalesce(rv_responded,0)=0` and reports **1** against a target of 0 — that one
is the single approved supplier, which has never been sent an RFQ because none exist.
**The KPI is firing on a supplier who has done nothing wrong.** M1 must therefore always compute
`dispatches_received` first and return "no signal — this supplier has received 0 RFQs" rather than "quiet".

**M2 — Attribution: theirs or ours.** Ordered elimination before any chase:
(1) Was an RFQ actually dispatched? `inquiry_matches` = **0 rows** across the estate.
(2) Was a notification created and delivered? `notifications` 855 rows, `event_delivery` 4,297.
(3) Is the supplier excluded from matching? `leads.matching_blocked` (3 rows), `v_supplier_match_exclusions`.
(4) Is the supplier licence-blocked? `leads.licence_gate_reason`.
Only if all four clear is the silence the supplier's. **Today step 1 stops every case.**

**M3 — Three strikes.** `decision_policy.matching_strike_limit = 3` (founder decision, 3 Aug 2026): three
consecutive unanswered RFQs and the supplier stops receiving them. Counter: consecutive `inquiry_matches`
with no `quotes` row. **Measured: 0 RFQs, so 0 strikes, and the counter has never incremented.** The rule is
correct and untested.

**M4 — Response quality.** From `supplier_score`: `response_rate`, `avg_response_hours`, `quotes_submitted`,
`quotes_won`, `rejection_count`, `price_index`, `quality_rating`, `reliability`.
**Measured: 20,465 rows; `response_rate` non-null on 2; `quotes_submitted > 0` on 0; `computed_at` last moved
2026-08-16** — its refresh cron (208 `supplier_score_refresh_daily`) is **inactive**. Every value in this table
is at least three weeks stale and almost all of it is null-equivalent.

**M5 — Contact budget.** Per supplier per 30 days: at most 1 invite follow-up
(`leads.invite_followups`, `invite_last_followup_at`), 1 re-engagement, 1 survey. WhatsApp requires
`leads.wa_optin`. Inputs: `notifications`, `email_suppressions` (37), `leads.wa_optin`. Output: allowed / blocked
with the reason.

**M6 — Non-response refund exposure.** Founder ruling 6 Sep 2026: a supplier whose non-response caused a refund
owes the refunded 3% reveal fee **plus AED 250 admin fee plus 9% p.a. interest**
(`decision_policy.refund_admin_fee_aed`, `refund_late_fee_annual_pct`, Supplier Agreement clause 33).
Before any such charge, M2 must clear all four steps — a supplier charged AED 250 for an RFQ that was never
dispatched is the worst outcome this seat can produce. Ladder: `pricing_config.refund_window_working_days` 5,
`chase_after_working_days` 3, bank settlement 7–14 working days. **Measured: `refunds` 0 rows, `reveal_invoices`
0 rows — no exposure exists yet.**

**M7 — Retention rate.** `retained = suppliers active at t−90 still active at t / suppliers active at t−90`.
**UNMEASURABLE:** the base is 1 supplier, approved 2026-08-12, and there is no activity to be retained from.
`company_goals.supplier_retention` (target 90%, owner `marketplace`) has no instrument. Report the base size,
never the percentage.

### 3. Reasoning procedures

**Type 1/2 — has this supplier gone quiet.** Always M2 before M1. (a) Count RFQs dispatched to the supplier —
if 0, the answer is "no signal; this supplier has never been asked anything", and the case closes without
contact. (b) If dispatches exist, check delivery, exclusion and licence block. (c) Only then compute
`days_quiet` and band it. (d) W19 step 2's acceptance criterion is exactly this: the analysis *"distinguishes
supplier-side cause from platform demand or workflow failure."*

**Type 3/4 — strikes and stopping.** Count consecutive dispatched-and-unanswered. At 3, stop dispatch and open a
W19 case. Never at 2. Never on non-consecutive misses. Never counting an RFQ the supplier could not have seen.

**Type 12 — is the response-rate KPI measuring anything.** Read `employee_kpi` 123: 100.00% against 60%, SQL
`avg(rv_response_rate) where rv_reveals > 0`, denominator **2 rows**. Answer template: "The KPI reads 100% from
two suppliers with a reveal. It is a two-row average and should be reported as 2/2, not as 100%. The department
objective it feeds (`department_objective` 31945, target 85%) inherits the same denominator."

**Type 15/20 — is the silence ours.** Join `v_supply_gap` to dispatch counts: a category with approved suppliers
and zero dispatches is a **demand** problem for `growth`, not a retention problem. Today every category is in
that state. Output routes the case out of this department rather than generating a chase.

**Type 17 — non-response refund gate.** Run M2 in full. If any of the four steps fails, **block the charge** and
open a task naming which step failed. This is the seat's hardest rule and it protects the supplier against the
company's own instrumentation. The founder's ruling sets the amounts; it does not authorise charging a supplier
for a message that never left the building.

**Type 27 — is retention measurable.** Run M7. Answer: "No. The base is one supplier approved 26 days ago, with
zero RFQs dispatched. A retention rate over that base is not a number; it is a division by a base too small to
divide by. `company_goals.supplier_retention` (90%) has no instrument in this estate."

**Type 30 — is the signal source running.** Check the crons this seat depends on:
`208 supplier_score_refresh_daily` **inactive** (so `supplier_score` is stale since 2026-08-16),
`209/210/211 supplier_risk_*` **all inactive** (complaints, response delays, performance drops — the three
signals W19 step 1 opens cases from), `178 supplier_exception_sweep_daily` **inactive**,
`68 supplier_success_daily` **inactive**, `118 supplier_capability_chase_daily` **inactive**.
**Five of this seat's six signal sources are switched off.** Verdict template: "No retention signal is being
produced. The absence of cases is not evidence of healthy suppliers."

### 4. Judgement rules

- **R1.** Never chase a supplier who has received zero RFQs. Reason: it is our silence, not theirs, and the
  contact spends goodwill we will need later.
- **R2.** Attribution before action, always — M2's four steps in order. Reason: W19 step 2's acceptance criterion.
- **R3.** Three strikes means three *consecutive dispatched and delivered* misses. Reason: founder decision
  3 Aug 2026; a strike for an undelivered RFQ is a fabricated strike.
- **R4.** Retention may never keep an unsafe supplier active; enforcement wins. Reason: W19 step 6's acceptance
  criterion and W19's founder boundary, both stated in production.
- **R5.** A non-response refund charge is blocked until M2 clears all four steps. Reason: AED 250 + 3% + 9% p.a.
  charged wrongly is both a financial and a relationship loss, and the supplier has no way to contest it.
- **R6.** WhatsApp only with `leads.wa_optin = true`. Reason: TDRA consent rules and the founder's channel policy.
- **R7.** Contact budget M5 is a hard cap, not a guideline.
- **R8.** Any metric with a denominator under 10 is reported as a fraction. Reason: KPI 123's 100.00% from 2 rows
  is currently the department's healthiest-looking number and it means nothing.
- **R9.** *Do not do this even though it scores well:* do not run a re-engagement campaign across the 164
  `no_response` leads to lift the response-rate metric. They are not suppliers; they never registered. Contacting
  them is an invite, not a retention action, and it belongs to `bd` under the shut gate.
- **R10.** *Do not do this even though it scores well:* do not exit a supplier for silence during a period when
  the estate dispatched nothing. That is the current period, and it would delete the company's only supplier.
- **R11.** Report the absence of retention cases with the reason (five signal crons off), never as good news.
  Zero cannot tell a dead guard from an idle system.
- **R12.** `analysis: supervised` is this seat's authority. Interventions are approved at W19 step 4 by
  `marketplace_director`; this seat executes and measures at step 5.

### 5. Technical knowledge

Tables and views: `supplier_score` (11 columns, 20,465 rows, stale since 2026-08-16), `supplier_kpi_snapshots`
(0 rows), `leads` (`rv_reveals`, `rv_responded`, `rv_response_rate`, `rv_nonresponse_refunds`, `chat_strikes`,
`matching_blocked`, `matching_block_reason`, `banned`, `banned_reason`, `wa_optin`, `invite_followups`,
`invite_last_followup_at`, `exception_*`), `supplier_health`, `supplier_perf`, `supplier_reputation`,
`supplier_twin`, `v_supplier_load`, `v_supplier_exception_board` / `_queue` / `_health` / `_outcomes`,
`v_supplier_match_exclusions`, `notifications` (855), `event_delivery` (4,297), `email_suppressions` (37),
`wa_messages` (0), `inbound_messages` (4), `refunds` (0), `reveal_invoices` (0).
Routines: `fn_supplier_risk_monitor(signal)` for `complaints` / `response_delays` / `performance_drops`,
`fn_supplier_score_refresh`, `fn_supplier_success`, `fn_supplier_capability_chase(days, max_chases)`,
`fn_supplier_exception_open/close/sweep`, `fn_supplier_invite_followups(tag)`, `fn_notify_supplier`,
`fn_notify_matched_supplier`, `recompute_supplier_rating(supplier)`, `fn_supplier_tier`, `fn_supplier_quality`,
`fn_supplier_stats`, `fn_emit_supplier_suspension_proposed(lookback_minutes)`.
Channel mechanics: `founder_mail_policy` — this department's three kinds are all `allowed_to_email = false`,
owner `business_development`; nothing here reaches the founder. Fixtures are `ZZ DEMO — …` /`@example.invalid`
inside a `rehearsal_window`; a real message is never sent by hand.
**Must be stored so this seat can act alone:** a per-supplier dispatch log (**does not exist** —
`inquiry_matches` is empty and there is no historical dispatch table); an exit-reason catalogue
(**does not exist**); a contact-history view per supplier across channels (**does not exist**; `notifications`
holds sends but is not aggregated per supplier).

### 6. Academic knowledge

Disciplines: customer/partner experience measurement; churn and survival analysis; service recovery; contract
and relationship management.

`role_certification` holds two:
**CCXP, Certified Customer Experience Professional** (CXPA, pass 68%, rank 1) — Customer Insights and
Understanding; Customer Experience Strategy; Metrics Measurement and ROI; Experience Design Improvement and
Innovation; Organizational Adoption and Accountability; Culture and Accountability.
**CIPS Level 4 Diploma in Procurement and Supply** (CIPS, pass 50%, rank 2) — the seven standard areas.
**Syllabus areas failed: none — this seat has never sat either exam.** The CCXP area *Metrics Measurement and
ROI* is precisely where the estate's current retention metrics fail, and it is the area to examine first.

Lawful primary sources: CXPA's published competency framework; the UAE TDRA's published anti-spam and consent
regulations, which bind every channel this seat uses; UAE Federal Decree-Law 45/2021 (PDPL) on contact data and
consent withdrawal; published survival-analysis method papers (Kaplan–Meier, Cox) from open-access statistics
journals; the ACSI methodology description, published free.

### 7. Corporate knowledge

It must carry: `matching_strike_limit = 3` (founder, 3 Aug 2026); the refund ladder of 6 Sep 2026 in full —
5 working days from payment, chase at day 3, founder's final call at day 5, AED 250 admin fee, 9% p.a. interest,
7–14 working days at the bank — because the supplier side of that ladder is this seat's to manage and the
founder said it must never be re-asked; that the reveal notifies both parties and rating solicitation happens
at the reveal moment; that a phone may confirm but never select — email is the identity; that nothing here
routes to the founder.
Workflows: owns **W19** steps 1, 3, 5 and 7; step 2 is `supplier_intelligence_analyst`, step 4 is
`marketplace_director`, step 6 hands to `supplier_verification`. It has **no `employee_workflow` row**, which
should be added.
Other seats: `supplier_verification` (enforcement, which outranks it), `marketplace` (dispatch and matching),
`cs` (complaints), `finance` (refunds and clawback), `supplier_coverage` (whether silence is a coverage or a
demand problem), `bd` (its manager).
History it must not forget: the department's healthiest-looking KPI (response rate 100%) rests on two rows; five
of its six signal crons have been off; and the company has never dispatched an RFQ, so it has never observed a
single genuine retention event.
**Does not exist:** any retention playbook (`ops_knowledge where dept_key='supply'` is 9 rows total,
`dept_library` 0); an exit-reason catalogue; `supplier_kpi_snapshots` is an empty table.

### 8. One-year plan

**Objective.** Keep every supplier the department wins actually answering RFQs — and, until RFQs exist, keep the
company honest about the fact that retention has not yet been tested.

**Its slice of AED 1,000,000.** AED 0 billed. Its arithmetic contribution is the difference between a category
that has 10 approved suppliers and a category that can produce three comparable quotes. The founder's top-3
doctrine means a reveal needs three real quotes; `match_max_fanout` is 5 and `match_max_fanout_per_trade` is 3.
If response rate is *r*, a fan-out of 5 yields an expected 5*r* quotes, and three quotes needs r ≥ 0.60 — which
is exactly the target on `employee_kpi` 123. **So this seat's number is load-bearing on revenue: below a 60%
response rate the reveal cannot reliably deliver what the customer paid 3% for.** That is the honest statement
of its slice, and it cannot be converted into AED until a mean quote value is observed, which it is not.

**Metrics it owns.** (1) Supplier response rate — reported as a fraction until the denominator reaches 10;
today **2/2**, nominally 100% against a 60% target. (2) Suppliers gone quiet — today **1** against a target of
0, and that 1 has received zero RFQs. (3) Dispatch-attributed silence (ours vs theirs) — **does not exist as an
instrument today**; building it is this seat's first deliverable.

**Quarterly milestones.** Q1: switch on and validate the five dead signal crons (208, 209, 210, 211, 178);
build the per-supplier dispatch log; replace KPI 124's SQL so it cannot fire on a supplier with zero dispatches.
Q2: exit-reason catalogue and contact-budget enforcement. Q3: first genuine strike counter increment observed
end-to-end. Q4: response rate reported on a denominator of at least 30.

**Capacity check — honest.** The work is not volume-bound; it is signal-bound. This seat could handle several
hundred suppliers on deterministic banding. **What it cannot do is retain suppliers in a marketplace with no
demand.** Every supplier the department wins between now and the first RFQ will be asked for nothing, and
suppliers who are asked for nothing leave. That is the retention risk nobody has priced: the department's
recruitment target of 300 a month and the marketplace's zero RFQs are, together, a churn machine.
**Recommendation for the founder:** do not recruit far ahead of demand. Open categories in the sequence demand
arrives in, not in the sequence pools are deepest.

**Dependencies.** `marketplace` for dispatch (blocking — no dispatch log exists); `product_eng` for the five
crons and the KPI SQL; `growth` for demand; `supplier_verification` for enforcement it may not override.

### 9. What this seat cannot do without a model

- Reading a free-text complaint or a supplier's explanation of why it did not quote. Classification into the
  enumerated causes is achievable with a keyword map over a small cause catalogue; nuance is not.
- Writing a bespoke re-engagement message to a valuable supplier who has a specific grievance. Templates cover
  the enumerated cases; a genuinely bespoke apology should be written by a person, not generated.
- Judging tone in an inbound message well enough to decide whether a relationship is recoverable. That should
  escalate, not be inferred.

---

## partnerships_mgr — Partnerships Manager

Seniority `specialist`, `routing_tier` director, manager `bd`. `org_agents.responsibilities` reads in full:
*"Builds channel and association partnerships that bring qualified RFQ volume."*
**This seat owns no workflow.** It appears in no `phase_b_workflow_step` row; `employee_workflow` gives it only
`employee_task`; `employee_authority` gives it two rows, `outreach_draft: autonomous` and
`outreach_send: advisory`. Its only KPI (`employee_kpi` 49) measures *qualified pipeline against plan* over
`inquiries`, which is empty, so it has never been measured. Of the six seats in this department it is the one
with the least machinery behind it, and the plan below says so plainly.

### 1. Question and decision taxonomy

| # | Question or decision | Kind | Frequency | Who asks | Cost of a wrong answer |
|---|---|---|---|---|---|
| 1 | Is this partnership worth pursuing? | allocation | monthly | bd | Months on a logo that brings nothing |
| 2 | Does it bring supply, demand, or only a logo? | diagnosis | per candidate | bd, ceo | A partnership that adds neither side |
| 3 | Which trade associations cover our thinnest categories? | allocation | quarterly | supplier_coverage | Partnering into a category already full |
| 4 | Can we lawfully receive a partner's member list? | gate | per candidate | legal | PDPL breach; unconsented contact |
| 5 | Does a partner's member list overlap our pool? | diagnosis | per candidate | bd | Paying for leads we already have |
| 6 | What do we offer a partner that costs us nothing? | pricing | per candidate | ceo, finance | Committing revenue share against a 3% fee |
| 7 | Can we discount the registration fee for a partner's members? | pricing | per candidate | ceo | Contradicting `pricing_config` (already free to 1,000) |
| 8 | Does a partnership require a signed agreement? | gate | per candidate | legal | An unenforceable arrangement |
| 9 | Who owns the relationship after signature? | sequencing | per partnership | bd | An orphaned partnership |
| 10 | What does "qualified RFQ volume" mean in measurable terms? | craft | standing | bd, ceo | A KPI that can never be measured |
| 11 | Is a developer/contractor partnership a demand or a supply play? | diagnosis | quarterly | growth | Building the wrong side |
| 12 | Should we integrate with a partner's system? | escalation | quarterly | product_eng | Engineering spend on a dead channel |
| 13 | Do we co-brand, and under whose licence? | gate | per candidate | legal, brand | Trade-name misuse |
| 14 | Is a free-zone authority a viable channel? | allocation | quarterly | bd | The single highest-density supplier channel in the UAE, missed |
| 15 | What is the attributable yield of a partnership? | forecast | quarterly | finance | Renewing a channel that produced nothing |
| 16 | Should a partnership be ended? | decision | quarterly | bd | Sunk-cost persistence |
| 17 | Does a partner's exclusivity demand conflict with our model? | gate | per candidate | legal, ceo | An exclusivity that closes a category |
| 18 | Can a partner introduce enterprise or government demand? | allocation | quarterly | bd | Missing the only large-ticket route |
| 19 | Which partnerships does the founder need to decide? | escalation | per candidate | bd | Escalating a non-refund decision to the founder |
| 20 | Does a partner require a data-processing agreement? | gate | per candidate | legal | PDPL controller/processor exposure |
| 21 | Is a referral fee lawful and payable? | pricing | per candidate | finance, legal | An unbudgeted commission |
| 22 | What is the pipeline of candidate partnerships? | diagnosis | monthly | bd | An empty pipeline reported as active |
| 23 | Does a partner's members' licence profile pass our gate? | diagnosis | per candidate | supplier_verification | A list of suppliers we cannot approve |
| 24 | Is a partnership's supply concentrated in one emirate? | diagnosis | per candidate | supplier_coverage | Dubai-only supply again |
| 25 | Should we attend or sponsor a trade event? | allocation | quarterly | finance | Spend outside authority (auto_action_max_aed = 0) |
| 26 | Is there a partnership record at all, anywhere? | diagnosis | standing | ceo | Reporting partnerships that exist only in conversation |

### 2. Domain logic

**M1 — Partnership value.** `value = supply_added + demand_added − cost`, where
`supply_added = Σ over categories of min(members_in_c, gap(c))` valued at the cost of acquiring that supplier by
invite instead, and `demand_added` = expected RFQs × mean quote value × 3%.
Inputs: `v_supply_gap` for `gap(c)`; the partner's member count by category (**does not exist as a table**);
`pricing_config.standard_reveal_rate` 0.03. **UNMEASURED and structurally so:** mean quote value has never been
observed (`quotes` 0 rows), so `demand_added` cannot be computed in AED. The seat must express demand value in
*RFQs*, not dirhams, and say why.

**M2 — Overlap.** `new_leads = partner_members − (partner_members ∩ leads)`, matched on `trade_license_no`,
`email_domain`, normalised `company_name` (`fn_screening_normalise`) and `place_id`. With 22,265 leads already
scraped across all 86 categories, overlap is likely to be the deciding term for any UAE-wide association.
Output: net new, with the match keys that fired.

**M3 — Channel density.** `density(source) = qualified_suppliers / contacts`. The comparison baseline is the
invite channel's measured 1/171 = **0.58%**. Any partnership must beat it to be worth the overhead.
**UNMEASURED:** no partnership has ever produced a contact, so there is no partnership-channel rate to compare.

**M4 — Lawful data receipt.** A three-condition gate before any member list is accepted: the partner has a
lawful basis to share (PDPL Art. 4/5 consent or legitimate interest); the purpose is compatible; a
data-processing agreement exists. Fail any → refuse the list and propose an opt-in route instead (the partner
invites its own members, we never touch the list). Output: accept / refuse-with-alternative.

**M5 — Cost boundary.** `decision_policy.auto_action_max_aed = 0` — this seat may commit **nothing**
autonomously. `financial_review_aed = 10,000` is the human-review threshold above. Any sponsorship, referral fee
or revenue share goes to the accountable role, never to the founder, whose only gate is a refund.
`employee_authority`: `outreach_send` is **advisory**. Output: a recommendation with an owner, never a commitment.

**M6 — Attribution.** `leads.source` and `leads.enrich_source` are the only attribution fields that exist.
**No partnership source value is defined**, so a partnership's yield is currently unattributable by construction.
This must be fixed before the first partnership, not after.

### 3. Reasoning procedures

**Type 1/2 — is this partnership worth it.** (a) Classify: supply-side, demand-side, or neither. Reject
"neither" immediately — the seat's mandate is *qualified RFQ volume*, not visibility. (b) Run M2 overlap; if net
new is below the number the invite channel could reach in a month at the current cap (50/day × 30 = 1,500), the
partnership must justify itself on quality, not volume. (c) Run M1 with demand expressed in RFQs. (d) Run M4;
an unlawful data route ends the case regardless of value. (e) Run M5; produce a recommendation with an owner.
(f) Cite `v_supply_gap` rows for the categories it would fill.

**Type 3/14 — which associations and authorities.** Rank the 86 categories by `gap_to_target` and
`sendable_shortfall` (**10,025 total**), take the 58 POOL-TOO-THIN and 3 NO-POOL categories, and map each to the
UAE bodies whose membership is that category: the free-zone authorities (DMCC, JAFZA, DAFZA, RAKEZ, SHAMS, IFZA,
KIZAD) whose member directories are published, the Dubai and Abu Dhabi Chambers of Commerce, and the
category-specific associations. **The free-zone route is the highest-density supply channel available and this
company has no record of ever using it.** Output: a ranked candidate list with the category gap each addresses.

**Type 10 — what does "qualified RFQ volume" mean.** The seat's own KPI is unmeasurable, so it must define the
measure before it can be held to it. Deterministic proposal: an RFQ is *qualified* if it reaches
`inquiries.rfq_ready` (the field `employee_kpi` 49 already uses) and is routed to a category with at least
`category_open_min_suppliers` approved suppliers. Today both terms are zero. Output: the definition plus the
statement that it cannot be measured until `inquiries` is non-empty.

**Type 22/26 — is there a pipeline.** Read the estate: there is **no partnerships table**, no partner record,
no partnership in `opportunity` (42 rows, none partnership-typed), and no `phase_b_workflow` for partnerships.
Answer template: "There is no partnership pipeline in this estate. Nothing is recorded, which means nothing can
be reported. The first deliverable of this seat is the record itself."

**Type 4/20 — lawful data.** Run M4. The default answer is the opt-in alternative: the partner mails its own
members with our registration link; we never receive the list. It is lawful, it costs nothing, and it is
measurable through a distinct `leads.source` value — which M6 says must be created first.

### 4. Judgement rules

- **P1.** A partnership that adds neither supply nor demand is declined, however prestigious. Reason: the seat's
  mandate is qualified RFQ volume, stated in `org_agents.responsibilities`.
- **P2.** Never accept a member list without M4's three conditions. Prefer the opt-in route by default. Reason:
  PDPL, and one unconsented bulk contact would end the invite programme's deliverability too.
- **P3.** Nothing is committed autonomously — `auto_action_max_aed = 0`, `outreach_send: advisory`.
- **P4.** No exclusivity that would close a category to other suppliers. Reason: `category_open_min_suppliers`
  requires 10 and the top-3 doctrine requires genuine choice; exclusivity makes the 3% fee indefensible.
- **P5.** No registration-fee discount may be offered. Reason: `pricing_config.supplier_free_count = 1000` and
  `supplier_charging_starts` is NULL — registration is already free, so a discount is a fiction, and pricing is
  not this seat's to move.
- **P6.** A partnership must have an attribution value in `leads.source` **before** it launches. Reason: M6 —
  without it the yield can never be measured and the renewal decision can never be made.
- **P7.** *Do not do this even though it scores well:* do not sign a large association whose members overlap the
  existing 22,265-lead pool by 80%+. It looks like thousands of suppliers and delivers hundreds we already have,
  and it costs relationship capital we cannot spend twice.
- **P8.** *Do not do this even though it scores well:* do not build a system integration for a partner before
  that partner has produced a single registered supplier through the opt-in route. Reason: `product_eng` capacity
  is the scarcest resource in this company and the claim path is ahead of it in the queue.
- **P9.** Legal triggers — `decision_policy.legal_triggers` includes contract change, liability, indemnity,
  termination — route to `legal` and are never auto-answered.
- **P10.** Partnership decisions do **not** go to the founder. `decision_policy.founder_review_gates` is refunds
  only; the founder's ruling of 17 Aug 2026, restated 5 Sep 2026, says partnership decisions belong to their
  accountable roles.
- **P11.** Report the empty pipeline as empty. Reason: there is no partnerships record in this estate at all, and
  a seat that describes conversations as pipeline is the one failure mode this seat can produce unaided.

### 5. Technical knowledge

Tables it uses today: `v_supply_gap` (the gap it is trying to fill), `catalog_supplier_categories` (86),
`leads` (`source`, `enrich_source`, `trade_license_no`, `email_domain`, `place_id`, `license_authority`),
`opportunity` (42 rows), `legal_documents` (12), `decision_policy`, `pricing_config`, `expenses` (20).
Routines: `fn_screening_normalise` (for overlap matching), `fn_supplier_lead_intake(tag)`,
`fn_supplier_lead_sourcing(tag)`, `fn_supplier_discovery_promote(limit, classify)` — the routes by which any
partner-sourced lead would actually enter the pool.
Authority: `outreach_draft` autonomous, `outreach_send` advisory (`employee_authority`).
External mechanics it must know: UAE free-zone authority member directories and their published formats; Dubai
Chamber and Abu Dhabi Chamber membership structures; the difference between a mainland DED licence and a
free-zone licence for what a member can legally do on the mainland — which decides whether a free-zone partner's
members can even serve a Dubai mainland RFQ.
**Must be stored so this seat can act alone — none of it exists today:** a `partnership` table (partner, type,
status, owner, agreement version, attribution source value, expected and actual yield); a partner-member intake
route; a partnership `leads.source` vocabulary; a partnership workflow in `phase_b_workflow`.
**Every one of these is "does not exist".** This seat currently has a mandate and no machinery.

### 6. Academic knowledge

Disciplines: strategic alliance management; channel economics; B2B sales; data-sharing law.

`role_certification` holds two:
**CSAP, Certified Strategic Alliance Professional** (ASAP, pass 70%, rank 1) — Alliance Strategy and Planning;
Partner Selection and Qualification; Alliance Structuring and Negotiation; Alliance Operations and Governance;
Alliance Performance Management; Alliance Transformation and Exit.
**CSP, Certified Sales Professional** (NASP, pass 80%, rank 2) — Prospecting and Qualification; Needs Discovery;
Presenting Solutions; Handling Objections; Closing and Negotiation; Account Management and Ethics.
**Syllabus areas failed: none — this seat has never sat either exam.** *Alliance Performance Management* is the
area the estate cannot currently support at all, since M6 shows no attribution mechanism exists.

Lawful primary sources: ASAP's published alliance-management framework overview; UAE Federal Decree-Law 45/2021
(PDPL) and its executive regulations on controller/processor roles and lawful sharing — the binding law for any
member-list arrangement; UAE Federal Law on Commercial Agencies (as published) for what an exclusive arrangement
means in the UAE; the free-zone authorities' own published member directories and licensing rules (DMCC, JAFZA,
DAFZA, RAKEZ, SHAMS, IFZA); Dubai Chamber and Abu Dhabi Chamber published membership statistics; the Federal
Competitiveness and Statistics Centre's establishment counts by activity, which give the denominator for any
claim about how much of a category a partner represents.

### 7. Corporate knowledge

It must carry: the pricing it may not move (3% reveal; AED 1,000/year registration, first 1,000 free,
no charging start date); that the founder approves refunds only and partnership decisions belong to their
accountable roles (ruling 17 Aug 2026, restated 5 Sep 2026); `auto_action_max_aed = 0`;
`category_open_min_suppliers = 10`, which is what any partnership is ultimately trying to reach; the trade
licence DET 1633275 (expires 24 Jun 2027) and the fact that no VAT registration exists until AED 375,000, both
of which a partner will ask about; the demo-fixture convention; that a real email or WhatsApp is never sent by
hand.
Workflows: **none.** It is not named in any `phase_b_workflow_step`. The nearest thing is W11 step 5, which
hands acquisition targets to `business_development`, not to this seat.
Other seats: `bd` (its manager and the executor of any outreach it drafts), `supplier_coverage` (which tells it
which categories a partnership must fill), `legal` (every agreement and every data route), `finance` (any fee),
`onboarding` (which processes whatever the partnership delivers).
History it must not forget: this seat has existed since 26 July 2026 and has produced no recorded partnership,
because there is nowhere in the estate to record one.
**Does not exist:** a partnerships table, a partnership workflow, a partner agreement template in
`legal_documents` (12 rows, none partnership-typed), a partnership attribution source, any partnership entry in
`ops_knowledge` (the department has 9 rows in total).

### 8. One-year plan

**Objective.** Open two or three high-density supply channels — free-zone authorities and category associations
for the thinnest of the 86 categories — through a lawful opt-in route, and build the record that makes their
yield measurable.

**Its slice of AED 1,000,000.** AED 0 billed directly, and — stated plainly — **this seat has the weakest claim
to a revenue slice of the six.** It cannot charge, it cannot commit spend, it owns no workflow, its only KPI is
unmeasurable, and there is no table in the estate in which a partnership can exist. Its honest year-one
contribution is measured in **net-new sendable leads in categories with a shortfall**, and the department's
total shortfall is **10,025**. A defensible target is that partnerships supply **2,000 net-new sendable leads in
POOL-TOO-THIN categories** — 20% of the shortfall — which at the 5% planning conversion would be 100 approved
suppliers, or ten opened categories.

**Metrics it owns.** (1) Net-new sendable leads by partnership, in shortfall categories — **0 today, and
unattributable until a `leads.source` value exists**. (2) Partnerships with a signed agreement and a named owner
— **0**, and no table to hold them. (3) Suppliers approved through a partnership route — **0**.
Its current KPI 49 (qualified pipeline against plan, over an empty `inquiries` table) should be retired and
replaced by these three.

**Quarterly milestones.** Q1: the `partnership` table, the attribution source vocabulary, and a partner
agreement template in `legal_documents` — the machinery, before any partner. Q2: first two free-zone or
association partnerships signed with an opt-in route and a named owner. Q3: 500 net-new sendable leads
attributed. Q4: 2,000 net-new sendable leads attributed, yield per partnership computed and one renewal decision
made on evidence.

**Capacity check — honest.** **The slice is not achievable as the seat stands today, and the reason is not
effort.** There is no partnerships table, no workflow, no agreement template, no attribution field and no
authority to commit anything. A seat cannot deliver 2,000 attributed leads through machinery that does not
exist. What would make it achievable, in order: (1) the `partnership` record and the `leads.source` vocabulary —
small engineering, and until it exists every partnership is unmeasurable; (2) a partner agreement template from
`legal`; (3) a partnership workflow in `phase_b_workflow` giving the seat the steps and the reviewer it
currently lacks; (4) a decision on who signs, since this seat may commit nothing and the founder does not
approve partnerships. **If the founder wants this seat to carry a revenue slice at all, item (4) is the one he
alone can settle: he has ruled that partnership decisions belong to their accountable roles, and no accountable
role is currently named for a partnership agreement.** That is the one open question this department has for
him, and it is a boundary question, not a technical one.

**Dependencies.** `product_eng` for the partnership record and attribution (blocking); `legal` for the agreement
template and every data route; `supplier_coverage` for the category ranking; `bd` for execution, since this
seat's outreach authority is advisory; `finance` for any fee.

### 9. What this seat cannot do without a model

- Drafting a bespoke partnership proposal for an association it has never dealt with. Templated composition
  from the category gap and the standard offer covers the structure; the persuasion does not.
- Reading a partner's own contract and identifying where it conflicts with our model. That is a legal reading
  and belongs to `legal` as a task under `decision_policy.legal_triggers`, not to a model and not to a guess.
- Judging the reputation or standing of a body from unstructured public material. The deterministic route is
  the published registries in §6 — member counts, licence status — not an inferred opinion.

---

## Department summary for the founder

**Six seats, all active, all coded to answer with OpenRouter switched off.** Every resolver above is a query,
an arithmetic model, and a threshold. Section 9 of each seat lists the four kinds of thing that genuinely need a
model — writing new persuasive prose, reading unseen document layouts, understanding free-text replies, and
legal judgement — and every one of them is routed to a template, a task, or a person, never guessed.

**The department's binding constraint, measured:** 22,265 leads, 171 invited, **0 claimed**, 1 registered,
1 approved, **0 of 86 categories at the 10-supplier threshold that makes a category tradeable**. The invite gate
(`invite_enabled`, `supplier_outreach_golive`) is shut and 200 planned invites have gone unsent since 15 August.

**The finding that matters most:** `leads.claimed` is **0** across 161 invitations recorded as sent, for the whole life
of the platform. The claim path has never once completed. Every plan in this document — bd's 344 days, onboarding's
860 approvals, supplier_coverage's ten open categories — is arithmetic on a conversion rate that has never been
observed, because the step where it would be observed has never succeeded. **Before another invitation is sent,
one claim must complete end to end.**

**The second finding:** four of the six instruments in this estate that read like supplier coverage measure
something else — category-agent knowledge modules, leads by `invite_trades`, the lead pool, and
`max(founding_rank)`. Three of them currently report health. One of them, `v_category_coverage`, reports
**COMPLIANT for 84 of 86 categories** while the number of categories with ten approved suppliers is **zero**.

**Year one, honestly:** this department bills **AED 0**. `supplier_free_count` is 1,000 and
`supplier_charging_starts` is NULL, so no supplier it recruits pays anything, and no date exists on which they
would start. Its entire contribution to the AED 1,000,000 is that **no reveal fee can be charged in a category
with fewer than ten approved suppliers, and there are none**. The 860-approved-supplier target is not reachable
this year on the current daily cap of 50, the current pool of 19,896 emailable leads, and a conversion rate of
either 0.58% (measured) or 5% (assumed). A defensible year-one commitment is **thirty categories at ten approved
suppliers**, contingent on the claim path working and the bounce rate — currently **5.85%, already above its own
5% ceiling** — being brought back under control first.

**The one boundary question for the founder** is in partnerships_mgr §8: no accountable role is named for
signing a partnership agreement, and he has ruled that partnership decisions do not come to him. Someone has to
be named, or that seat cannot act.
