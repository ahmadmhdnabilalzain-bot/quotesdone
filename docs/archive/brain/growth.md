# Company brain — Growth (Demand)

**Department:** `growth` — "the Demand team" (`ops_knowledge` record `qd-company:org-growth`).
**Written:** 7 September 2026. **Measured against production** (`htdblwldjkcgjvmqkbeh`) at `2026-09-07 08:01 UTC`.
**Status:** a plan for the founder to approve. Nothing in this file has been applied to production.

**The hard constraint this whole document obeys:** *no position may depend on a language model at run
time.* Every resolver below is a table lookup, an arithmetic formula, a threshold comparison, a ranked
catalogue or a templated composition. The only model-shaped thing used anywhere is the **free in-region
`gte-small` embedding** (`kb_embed`), which is used exclusively to *route a question to a question type*
and to *retrieve stored records by meaning* — never to generate an answer, never to form a judgement.
Where a question genuinely cannot be answered without a model, it is named in that seat's section 9 and
nowhere else. **With OpenRouter switched off, every seat below still answers or honestly refuses.**

---

## 0. The measured baseline every seat in this department shares

These are the numbers as production reports them today. Every "what is UNMEASURED" line in the sections
below traces back to this table. No figure here is estimated.

### 0.1 The seats

`select * from public.org_agents where active and department='growth'` returns **7 rows**:

| agent_key | title | seniority | manager | org_role.role_id | authority_level | budget_limit AED |
|---|---|---|---|---|---|---|
| `sales_director` | Chief Revenue Officer | director | `ceo` | `chief_revenue_officer` | `execute_medium` | 10,000 |
| `brand_mgr` | Brand & Creative Manager | specialist | `sales_director` | `brand_and_creative` | `execute_low` | 1,000 |
| `marketing_analyst` | Marketing Performance Analyst | specialist | `sales_director` | `marketing_performance_analyst` | `advisory` | 0 |
| `marketing_content` | Content Strategy & Copy Specialist | specialist | `sales_director` | `content_strategy_and_copy` | `execute_low` | 0 |
| `marketing_design` | Visual Design Specialist | specialist | `sales_director` | `visual_design` | `advisory` | 1,000 |
| `marketing_social` | Social Media & Community Manager | specialist | `sales_director` | `social_media_and_community` | `execute_low` | 1,000 |
| `optimisation_eng` | Product Optimisation Engineer | specialist | `sales_director` | `product_optimization_engineer` | `execute_low` | 0 |

Five further `growth` rows are `active=false` and are **not** written up here: `account_mgr` and
`crm_pipeline_mgr` (parked 3–4 Sep 2026, accountability moved to `sales_director`), `marketing`
(Marketing Director, parked 3 Sep 2026), `marketing_copy` (folded into `marketing_content` 14 Aug 2026),
and `gov_relations_mgr` (inactive, manager `bd`).

### 0.2 The revenue reality

| fact | value | source |
|---|---|---|
| Inquiries, all time | **0** | `public.inquiries` |
| Quotes, all time | **0** | `public.quotes` |
| Transactions, all time | **0** | `public.transactions` |
| Reveals, all time | **0** | `transactions where revealed_at is not null` |
| Recognised revenue, all time | **AED 0** | `company_goals.revenue_annual.measure_sql` |
| Customers | **1** | `public.customers` |
| Registered suppliers | **0** | `v_invite_funnel`, sum of `registered` over 37 trades |
| Supplier invites sent | **344** (323 delivered, 21 bounced) | `v_invite_funnel` |
| Scraped supplier leads | **22,265** (19,896 with an email) | `public.leads` |
| Supplier capability rows | **15,306** | `public.supplier_capabilities` |

The company has never taken an inquiry, never produced a quote, never taken a reveal fee. **Every
conversion rate this department would normally reason with has a zero denominator.** That is the single
most important fact in this file and it constrains every plan below.

### 0.3 The demand surfaces

| surface | count | state |
|---|---|---|
| Social posts (`public.social_posts`) | **10** | all `status='sent'` to Postiz **as drafts**; `social_published = 0`; **0 created in the last 7 days** |
| Recorded engagement metrics on those posts | **0** | `social_posts` has **no impressions, views, likes, comments, shares or reach column at all** |
| Blog posts | 32 published of 32 | `public.blog_posts` |
| Site pages | 18 | `public.pages` |
| SEO category pages | 24 generated of 24 | `public.seo_categories` |
| Content drafts pending | 1 (id 36, `draft`, 11 Aug 2026) | `public.content_drafts` |
| Brand asset files | 58 | `public.brand_assets` |
| Brand rules (colour, logo, contrast, sizes, imagery) | 53 | `public.company_brand` |
| Marketing reference corpus | 317 rows, 6 categories, 18 domains | `public.marketing_library` |
| Marketing snapshots | 38, **last one 2026-08-15** (23 days stale) | `public.marketing_snapshots` |

Five of the ten posts carry `permalink_missing = "Postiz draft (state DRAFT) — not published to a
network"`; four carry a note that Postiz no longer lists their ids at all; one is a pipeline self-test.
**The account has published nothing. There is no engagement history in this estate — not a low number,
no column.**

### 0.4 The money and the switches

| knob | value | source |
|---|---|---|
| Founder's paid-media daily cap | **AED 30/day** | `app_secrets.meta_daily_budget_cap_aed = '30'` |
| Autospend go-live switch | **false** | `app_secrets.meta_autospend_golive` |
| Meta access token | **absent** | `fn_ads_autospend_state().token_present = false` |
| Effective real-campaign ceiling today | **AED 0/day** | `fn_ads_autospend_state().live_allowed = false` |
| Policy daily cap / per-campaign max / min | 30 / 30 / 20 AED | `ad_spend_policy` |
| Kill multiplier · learning phase · scale step | 3× · 3 days **and** AED 100 · +20% | `ad_spend_policy` |
| **Target cost per lead** | **NULL** | `ad_spend_policy.target_cpl_aed` — *see §0.6* |
| Live / decided ad campaigns | 0 / 0 | `ad_campaign_state`, `ad_decision` |
| Growth department AI budget | AED 120/month, AED 0 spent, degrade 70%, halt 95% | `department_budget` |
| Marketing go-live | **false** | `app_secrets.marketing_golive` |
| Supplier invites enabled | **false** | `app_secrets.invite_enabled` |
| Reveal fee | **3.00%** of quote value (standard and promo), cap 99,999,999 | `pricing_config` |
| Supplier registration fee | AED 1,000/year — **first 1,000 suppliers free** | `pricing_config.supplier_free_count = 1000` |
| Category opens at | **10 confirmed suppliers** | `pricing_config.category_open_min_suppliers` |
| Refund ladder | chase at 3 working days, founder call at 5, bank 7–14 | `pricing_config`, `decision_policy` |
| Agent autonomous money limit | **AED 0** | `decision_policy.auto_action_max_aed` |
| Human review threshold | AED 10,000 | `decision_policy.financial_review_aed` |
| Founder review gates | **refunds only** | `decision_policy.founder_review_gates` |

### 0.5 The department's own goals

`company_goals where owner_dept='growth'` — **five goals, five without an instrument:**

| key | goal | target | `measure_sql` |
|---|---|---|---|
| `website_visitors` | 250,000 visitors/year | 250,000 | **null** — "NO INSTRUMENT EXISTS" |
| `organic_traffic` | organic ≥ 60% of traffic | 60% | **null** — "NO INSTRUMENT EXISTS" |
| `lead_conversion` | visitor→lead ≥ 5% | 5% | **null** — "NO INSTRUMENT EXISTS" |
| `social_engagement` | engagement ≥ 7% | 7% | **null** — "NO INSTRUMENT EXISTS" |
| `marketing_roi` | ≥ 5:1 | 5 | **null** — "NO INSTRUMENT EXISTS" |

The company-wide target this department serves is `revenue_annual`: **AED 1,000,000 recognised revenue
in a trailing 12 months**, owned by `finance`, measured as
`sum(coalesce(reveal_fee, app_fee, 0)) from transactions where revealed_at > now() - 365 days and refund_confirmed_at is null`.

There is **no analytics table of any kind** in this database: a scan for
`visit|session|pageview|analytic|traffic|referr|utm|web_` returns only `admin_mfa_sessions`,
`control_mode_session`, `executive_control_session`, `founder_command_session`. **Four of the five
departmental goals cannot be measured because the instrument does not exist**, and no seat below is
allowed to pretend otherwise.

### 0.6 Six defects this measurement found (stated, not fixed — this is a plan)

1. **`ad_spend_policy.target_cpl_aed` is NULL.** The `kill_3x` rule compares cost-per-lead to
   `kill_multiplier × target_cpl_aed`. With a null target, the comparison is null and the rule can only
   fire on its second limb ("spend and no leads at all"). The autopilot would scale a winner it cannot
   define. **A number the founder sets is missing, not a bug in the code.**
2. **Every "brand review" KPI reads a retired department key.** Six growth KPIs measure
   `review_chain where dept_key='marketing'`. In the last 30 days that key has **16 rows** (14 approve →
   87.5%, which is exactly the value stored on all six KPIs), while the department actually writes
   **328 rows** under `dept_key='growth'` (209 approve). The 87.5% is the dying tail of a key retired on
   10 Aug 2026; within days it becomes null and every one of those KPIs goes dark.
3. **`Publishing cadence met` and `Engagement rate` are unmeasurable by construction.** The first reads
   `social_posts where status='published'` — a status this estate has never written. The second reads
   `marketing_snapshots.kpis->>'engagement_rate'` — a key no snapshot carries. Both have
   `actual_value = null`, `measured_at = null`.
4. **Seven of the eleven growth-related cron jobs are inactive**: `social_stage_hourly`,
   `blog_weekly_mon`, `marketing_ai_daily`, `seo_gen_weekly`, `content_revise_hourly`,
   `agent_marketing_weekly`, `invite_ramp_daily`. Active: `supplier_invites_daily`, `meta_sync_daily`,
   `ads_autopilot_daily`. **The department's production line is switched off; only its meters run.**
5. **Two experiments have been "running" since 6 July 2026** (`homepage_cta`, `supplier_invite_count`)
   with **1 assignment and 0 events** between them. They are not experiments, they are open tabs.
6. **Six of seven seats have never sat their certification.** `certification_exam_result` holds exactly
   two rows for this department, both `marketing_analyst`, both **failed** (see §3.6).

---
## sales_director — Chief Revenue Officer

The department head. Owns the AED 1,000,000 line, reviews everything that leaves the department, and is
the only seat here with `execute_medium` authority and a five-figure budget limit (AED 10,000). Since
3–4 September 2026 it also carries the parked `account_mgr` and `crm_pipeline_mgr` accountability.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| SD-01 | Are we on track for AED 1,000,000 in the trailing 12 months, and by how much are we off? | forecast | weekly | ceo, founder | A false "on track" delays the only correction that matters; a false alarm burns the AED 30/day cap on panic spend |
| SD-02 | Given 0 reveals ever, what is the earliest date the first reveal fee can land? | forecast | monthly | founder | Anchors every hiring, spend and runway decision on a fantasy |
| SD-03 | How many reveals per month does AED 1,000,000 require at a 3% fee? | forecast | quarterly | ceo | Sizes the whole plan; wrong by 2× means the department builds the wrong machine |
| SD-04 | Which single constraint is binding today — demand, supply, or product? | diagnosis | weekly | ceo | Spending on the non-binding side produces zero revenue and looks like effort |
| SD-05 | Should the department spend anything at all this month? | allocation | monthly | founder | With 0 registered suppliers, demand spend buys RFQs nobody can quote |
| SD-06 | Is the AED 30/day paid cap the binding limit, or is `live_allowed=false` the binding limit? | diagnosis | monthly | founder, marketing_analyst | Asking the founder to raise a cap that is not the constraint wastes his only scarce input |
| SD-07 | Which trade should open first, given `category_open_min_suppliers = 10`? | sequencing | monthly | marketplace, supply | Opening a category at 3 suppliers produces a thin comparison and a buyer who never returns |
| SD-08 | Approve or reject an outbound asset before it leaves the department | gate | daily | brand_mgr, marketing_content, marketing_social | A non-compliant public claim is a UAE advertising-law exposure and a brand cost |
| SD-09 | Is this outbound send inside `outreach_send` authority or does it need the gate? | gate | daily | marketing_social, supply | An ungated send to a real address breaches the standing rehearsal rule |
| SD-10 | Which of the 37 invited trades deserves the next invite batch? | allocation | weekly | supply | 344 invites produced 0 registrations; repeating the same allocation repeats the same zero |
| SD-11 | Has the supplier funnel's zero registration rate changed enough to resume invites? | gate | weekly | supply, founder | Resuming a broken funnel manufactures bounce and domain reputation damage |
| SD-12 | What is the department's forecast confidence, and what would make it higher? | forecast | monthly | ceo | Presenting a point estimate from zero data is the classic senior failure here |
| SD-13 | Is a reported KPI value real or an artefact of a retired key? | diagnosis | weekly | marketing_analyst | The 87.5% brand-compliance number is exactly this artefact (§0.6.2) |
| SD-14 | Does this campaign proposal serve `revenue_annual` or only a vanity goal? | gate | weekly | marketing_social, marketing_content | Effort that moves no company goal is the department's main leak |
| SD-15 | Should we chase a large one-off tender or many small RFQs? | allocation | quarterly | founder, bd | The stored failure-mode record `exam:1122` names whale-chasing as the trap |
| SD-16 | What is the fee revenue of a given quote value, and does it clear the floor? | pricing | per RFQ | marketplace | Misquoting the 3% to a customer is a commercial and legal error |
| SD-17 | Does a discount, waiver or promo ever get offered? | pricing | ad hoc | founder, marketplace | `exam:1209` — discount addiction structurally erodes reveal-fee revenue |
| SD-18 | Which seat is accountable for a missed number this month? | diagnosis | monthly | ceo, people_ops | Blaming a seat whose instrument does not exist destroys the org's honesty |
| SD-19 | Is a proposed spend inside `budget_limit` (10,000) and `auto_action_max_aed` (0)? | gate | per action | any seat | AED 0 autonomous money movement is a hard rule; breaching it is a governance incident |
| SD-20 | Does this decision need the founder, or does it belong to a role here? | escalation | daily | any seat | `founder_review_gates` is refunds only; every other escalation to him is a rule breach |
| SD-21 | Should `marketing_golive` be recommended to flip to true? | gate | monthly | founder | Flipping publishing on before the creative rubric passes puts unreviewed work in public |
| SD-22 | Should `invite_enabled` be recommended to flip to true? | gate | monthly | founder, supply | Same, for the supply side |
| SD-23 | What is the pipeline, stated honestly, when `inquiries = 0`? | diagnosis | weekly | ceo | Reporting scraped leads as pipeline is the single most tempting lie available to this seat |
| SD-24 | Which company goal does this week's work serve, named explicitly? | gate | weekly | all growth seats | Unattributed work cannot be stopped when it stops paying |
| SD-25 | Is a claimed win statistically real or an underpowered read? | diagnosis | monthly | optimisation_eng, marketing_analyst | `exam:1128` — peeking and p-hacking accumulate changes that do nothing |
| SD-26 | Do we have enough supply depth in trade X to accept demand in trade X? | gate | weekly | marketplace | Accepting demand into an empty category burns the buyer permanently |
| SD-27 | What does the department tell a buyer who asks "how many suppliers do you have?" | craft | ad hoc | customer_experience | An inflated answer is a misrepresentation; the honest answer is 0 registered |
| SD-28 | Should the department run a paid probe at AED 30/day to learn CPL? | allocation | once | founder | The only way to obtain a cost-per-lead this estate has never measured |
| SD-29 | What is the department's monthly AI budget consumption against AED 120? | allocation | weekly | finance, optimisation_eng | Overrunning at 95% halts the department's own automation |
| SD-30 | Is this a `growth` decision or a `marketplace` / `supply` decision? | escalation | daily | any | Cross-department land-grabs produce duplicate, contradictory decisions |
| SD-31 | Which quarter's milestone has slipped, and is the slip recoverable? | forecast | quarterly | ceo | Late detection of a slip removes every cheap remedy |
| SD-32 | Approve or refuse the department's own headcount change | gate | quarterly | people_ops | Seats without an instrument produce KPIs that cannot be met |
| SD-33 | What does a competitor's public pricing imply for our 3%? | pricing | quarterly | founder | Reactive repricing without elasticity data is a guess dressed as strategy |
| SD-34 | Should a partnership (chamber, association, platform) be pursued? | allocation | quarterly | bd | `exam:883` names these as the aggregators worth the effort |
| SD-35 | Is this public claim substantiated to UAE advertising standards? | gate | per asset | brand_mgr | `exam:1211` — unsubstantiated claims are a regulatory exposure |
| SD-36 | Has any seat's KPI gone `measured_at = null`, and for how long? | diagnosis | weekly | people_ops | A dark KPI silently converts accountability into theatre |
| SD-37 | What is the honest one-line answer to "how is growth going?" | craft | weekly | founder | The founder's standing rule: never state what has not been measured |
| SD-38 | Should the department stop doing something it is currently doing? | allocation | monthly | ceo | Seven inactive crons mean the department is already half-stopped and nobody decided it |
| SD-39 | Which single input from the founder unblocks the most revenue? | sequencing | monthly | founder | His attention is the scarcest resource in the company |
| SD-40 | Refuse: any question needing visitor, traffic or engagement data | escalation | daily | anyone | Answering it invents a number; the instrument does not exist |

### 2. Domain logic (the models this seat reasons with)

**M-SD-1 — Reveal arithmetic (the company's revenue identity).**
```
reveal_fee_aed      = quote_value_aed × pricing_config.standard_reveal_rate      (= 0.03)
                      capped at pricing_config.standard_reveal_cap               (= 99,999,999, non-binding)
revenue_period_aed  = Σ reveal_fee_aed over transactions
                        where revealed_at in period and refund_confirmed_at is null
reveals_required    = target_aed / (avg_quote_value_aed × 0.03)
```
Inputs: `pricing_config` (live), `transactions` (live, **0 rows**).
Outputs: required reveal count for any target.
**UNMEASURED: `avg_quote_value_aed`.** `quotes` has 0 rows. Until a real quote exists this seat must
publish the *function* `reveals_required(avg_quote_value)`, never a single number. Worked at three
anchor values so the founder can pick: at AED 20,000/quote → AED 600/reveal → **1,667 reveals/year
(≈139/month)**; at AED 50,000 → AED 1,500 → **667/year (≈56/month)**; at AED 100,000 → AED 3,000 →
**334/year (≈28/month)**.

**M-SD-2 — The funnel identity (six stages, four rates).**
```
visitors → inquiries → matched → quoted → revealed → paid
inquiries      = visitors × visit_to_rfq_rate
matched        = inquiries × match_rate
quoted         = matched   × quote_rate
revealed       = quoted    × reveal_rate
revenue        = revealed  × avg_quote_value × 0.03
```
Inputs: `marketing_kpis` view supplies `inquiries_30d, matched_30d, quoted_30d, revealed_30d,
revenue_30d, inq_to_quote_pct, quote_to_reveal_pct` — **all currently 0 or null**.
**UNMEASURED: every one of the four rates, and `visitors` has no instrument at all.** The seat's
correct output is the identity plus the named missing terms, with a refusal to invent them.

**M-SD-3 — The binding-constraint test.** For each of the three candidate constraints, a boolean
computed from live rows; the binding constraint is the first that is true in this order:
```
supply_binding  := (select sum(registered) from v_invite_funnel) < pricing_config.category_open_min_suppliers   -- 0 < 10 → TRUE today
demand_binding  := supply_binding is false and (select count(*) from inquiries where created_at > now()-30d) = 0
product_binding := supply and demand both false and quoted_30d > 0 and revealed_30d = 0
```
Today this returns **supply_binding = TRUE (0 < 10)**, which is the department's single most important
computed fact: *demand spend cannot produce revenue this month.*

**M-SD-4 — Paid-media capacity ceiling.**
```
annual_paid_ceiling_aed = ad_spend_policy.daily_cap_aed × 365                = 30 × 365 = 10,950
max_reveals_from_paid   = annual_paid_ceiling_aed / cost_per_reveal_aed
implied_cpr_at_target   = annual_paid_ceiling_aed / reveals_required
```
At the AED 50,000-quote anchor (667 reveals) the implied affordable cost per reveal is
**AED 10,950 / 667 = AED 16.42**. At the AED 20,000 anchor it is **AED 6.57**.
**UNMEASURED: actual cost per lead and cost per reveal** (`ad_decision` and `ad_campaign_state` are
empty; `marketing_kpis.meta_cpl` is null). The seat may not assert those figures are unachievable — it
may only report that *no measured CPL exists in this estate*, and that the arithmetic shows the AED
30/day cap alone must deliver a cost per reveal in the AED 6–17 range to carry the target by itself.
That framing is the honest one and it is what makes SD-28 (the paid probe) the highest-value experiment
available.

**M-SD-4b — The effective ceiling is not the cap.** `fn_ad_spend_daily_ceiling()` returns the founder's
cap only when `fn_ads_autospend_state().live_allowed` is true. Today `golive=false` and
`token_present=false`, so the **real ceiling is AED 0/day** and the AED 30 is dormant. This seat must
never report "we are capped at 30" when the true statement is "we are capped at 0 until the token and
the go switch exist".

**M-SD-5 — Category-open readiness score.** For each trade in `v_invite_funnel`:
```
readiness   = registered / pricing_config.category_open_min_suppliers        (open when ≥ 1.0)
reachable   = delivered - bounced
conversion  = registered / nullif(delivered,0)
priority    = reachable × (1 - readiness)      -- most reachable, furthest from open
```
Today every trade scores `readiness = 0`, `conversion = 0`; `priority` reduces to `reachable`, ranking
`(unclassified)` 37, `Civil & construction works` 20, `Cleaning & facility services` 16,
`Interior fit-out` 15, `Aluminium & cladding` 15 at the top.

**M-SD-6 — Budget headroom.**
```
headroom_pct = 100 × spent_aed / monthly_aed        (department_budget, growth: 0 / 120 = 0%)
state = 'normal' when < degrade_at_pct (70) ; 'degrade' when < halt_at_pct (95) ; 'halt' otherwise
```

**M-SD-7 — Escalation routing.** `founder_review_gates = ['refund_decision','refund_outside_policy']`.
Every other decision resolves to an `org_role.role_id` via `decision_policy.action_autonomy`. A decision
whose class is not in `action_autonomy` **refuses and opens an org task** — it never defaults to the
founder.

### 3. Reasoning procedures

**SD-01 — "Are we on track for AED 1,000,000?"**
1. Evidence: run `company_goals.revenue_annual.measure_sql` verbatim → **AED 0**.
2. Compute elapsed fraction of the trailing-12-month window and the linear-pace requirement.
3. Run M-SD-3. If `supply_binding` is true, the answer is *not* a percentage — it is
   "0 of 1,000,000; the binding constraint is supply, at 0 registered of 10 required to open one
   category". A percentage here would imply a trajectory that does not exist.
4. Compute M-SD-1 at all three anchor quote values and present the function, not a point.
5. Stop condition: if `transactions` has 0 rows, **refuse to give a completion date** and name the two
   observable events that would first make one computable (first registered supplier, first inquiry).

**SD-04 — "Which constraint is binding?"**
1. Run M-SD-3 in order; return the first TRUE with its exact operands (`0 < 10`).
2. Attach the cheapest action that would flip it: for supply, the invite funnel's conversion is
   `0/323`, so the action is *diagnose why 323 delivered invites produced 0 registrations*, not *send
   more invites*.
3. Escalate to `supply` / `marketplace` with a named handoff; do not act inside their department.

**SD-05 / SD-28 — "Should we spend this month, and on what?"**
1. Read `fn_ads_autospend_state()`. If `live_allowed=false`, the only truthful answer is
   "we cannot spend; the token and the go switch are absent". Stop.
2. If live: read M-SD-3. If `supply_binding`, allocate **0** to buyer demand and route the whole
   AED 30/day to supplier recruitment creative, because a buyer acquired now meets an empty category.
3. If demand-binding: rank candidate campaigns by `expected_reveals / cost`, where `expected_reveals`
   is null for every candidate until a probe returns. With all candidates null, the ranked list is
   empty and the seat proposes **one** probe at the minimum per-campaign budget (AED 20/day) whose sole
   deliverable is a measured CPL. Refuse to propose a second until the first returns.
4. Every proposal is written to `ad_decision` first (the ledger is the trace) and passes
   `fn_ad_spend_ceiling_guard` or it does not happen.

**SD-08 — "Approve or reject this outbound asset."**
1. Retrieve the asset and its cited brand rule from `company_brand` (53 rows) and `brand_assets` (58).
2. Run the creative rubric of §4 of `marketing_design` as a checklist; every check is boolean.
3. Run the claims check: every factual claim must resolve to a live row (supplier count → `v_invite_funnel`;
   fee → `pricing_config`; categories → `seo_categories`). A claim with no row is a **reject**, not a
   revision.
4. Verdict written to `review_chain` with `dept_key='growth'` (**not** `'marketing'` — see §0.6.2).
5. Stop condition: if the asset makes a comparative or superlative claim about a named competitor,
   refuse and route to `legal` (`decision_policy.legal_triggers`).

**SD-13 — "Is this KPI real?"**
1. For the KPI in question, read `employee_kpi.measure_sql` and execute it.
2. Count the rows in its own window. If the row count is < 20, mark the value **LOW-N** and report the
   count beside the percentage.
3. Check whether the filter's literal (e.g. `dept_key='marketing'`) still receives writes: compare
   `max(created_at)` for that literal against `now()`. If the gap exceeds 14 days, the verdict is
   **STALE KEY** and the KPI is reported as dark, not as its stored value.
4. Today this procedure marks all six "brand review" KPIs STALE KEY (16 rows, last write 10 Aug 2026)
   while `dept_key='growth'` took 328 rows in the same window.

**SD-23 — "What is the pipeline?"**
1. `count(*) from inquiries` → 0. `count(*) from quotes` → 0. `count(*) from transactions` → 0.
2. Compose: "Pipeline is zero. What exists is 22,265 scraped supplier leads and 344 delivered invites,
   which are **supply prospecting, not demand pipeline**." The template forbids the word "pipeline"
   appearing in the same sentence as `leads`.

**SD-39 — "Which founder input unblocks the most revenue?"**
1. Enumerate the blocked switches with their live values: `invite_enabled=false`,
   `marketing_golive=false`, `meta_autospend_golive=false`, `meta_access_token` absent,
   `ad_spend_policy.target_cpl_aed` null.
2. For each, compute the downstream count of currently-dead capability (crons disabled, seats whose
   `max_tier` action cannot execute).
3. Rank by count; present at most three; state for each the exact `app_secrets` key and the value it
   needs. Never present more than three — his attention is the scarce input.

### 4. Judgement rules

| # | condition | verdict | reason |
|---|---|---|---|
| J-SD-1 | `sum(registered) from v_invite_funnel < category_open_min_suppliers` | **No buyer-side demand spend, at any budget** | A buyer entering an empty category is lost permanently; the acquisition cost is spent twice |
| J-SD-2 | `transactions` has 0 rows | **No completion date for the revenue goal may be stated** | Never state what you have not measured |
| J-SD-3 | A metric's row count in its own window < 20 | Report the count beside the value; never report the percentage alone | 87.5% from 8 rows is not a rate |
| J-SD-4 | A KPI's filter literal has taken no write in 14 days | Report the KPI as **dark**, not as its stored value | §0.6.2 |
| J-SD-5 | `fn_ads_autospend_state().live_allowed = false` | Report the ceiling as **AED 0/day**, not AED 30 | The cap is dormant; saying "capped at 30" implies spend is possible |
| J-SD-6 | Any single money action ≥ AED 10,000 | Human review | `decision_policy.financial_review_aed` |
| J-SD-7 | Any autonomous money movement > AED 0 | **Refuse** | `decision_policy.auto_action_max_aed = 0` |
| J-SD-8 | Decision class not in `decision_policy.action_autonomy` | Refuse and open an org task | Never default an unmapped decision to the founder |
| J-SD-9 | Decision is a refund | Founder | The only founder gate that exists |
| J-SD-10 | Asset contains a comparative claim about a named competitor | Route to `legal`, do not approve | `legal_triggers`; UAE advertising substantiation |
| J-SD-11 | A campaign proposal cites no `company_goals.key` | Reject unread | Unattributed work cannot be stopped |
| J-SD-12 | A proposal offers a discount or fee waiver | **Reject even when it scores well** | `exam:1209`: discounting trains the market to wait and erodes the 3% structurally |
| J-SD-13 | A proposal targets a single large tender | **Reject even when the value scores highest** | `exam:1122`: whale tenders crowd out the frequent small RFQs the marketplace is built for |
| J-SD-14 | An experiment has been running > 30 days with < 100 assignments | Stop it and record why | Two such experiments have run since 6 Jul 2026 with 1 assignment |
| J-SD-15 | A question requires visitor, traffic, session or engagement data | **Refuse; name the missing instrument** | No such table exists in this estate |
| J-SD-16 | Growth budget consumption ≥ 95% of AED 120 | Halt department automation | `department_budget.halt_at_pct` |
| J-SD-17 | A seat reports a number it did not compute from a named row | Return it unapproved | The department's honesty rule, applied inward |
| J-SD-18 | Supplier registration conversion is 0 after ≥ 300 delivered invites | **Stop inviting; diagnose** | Repeating a 0/323 funnel manufactures bounces and burns domain reputation |
| J-SD-19 | An outbound would go to a real address outside a rehearsal window | **Refuse** | Standing rule: fixtures only, `ZZ DEMO` / `@example.invalid` |
| J-SD-20 | Two seats claim the same decision | Route to `org_role.owned_decisions`; if still ambiguous, escalate to `ceo` | Duplicate ownership produces contradictory public output |

### 5. Technical knowledge

- **The revenue instrument itself:** `transactions` (`revealed_at`, `reveal_fee`, `app_fee`,
  `refund_confirmed_at`), `company_goals.revenue_annual.measure_sql`, and why `coalesce(reveal_fee,
  app_fee)` exists.
- **`pricing_config` as the single source of fee truth** — 3% standard and promo, cap, supplier
  registration AED 1,000/year with `supplier_free_count = 1000`, `category_open_min_suppliers = 10`,
  and the refund ladder (3 / 5 working days, banks 7–14).
- **The authority model:** `employee_authority` rows for this seat (`outreach_draft` autonomous to AED
  10,000; `outreach_send` **gated**), `org_role.authority_level = execute_medium`,
  `budget_limit = 10,000`, and `decision_policy.auto_action_max_aed = 0` overriding both for money.
- **The escalation model:** `decision_policy.action_autonomy` (25 kinds), `founder_review_gates`
  (refunds only), `founder_mail_policy` + `fn_founder_mail_route`, `apex_backup = ops_director`.
- **The review chain:** `fn_review_submit(subject_type, subject_id, dept_key, author, content)` and the
  fact that this department's live key is `growth`, not `marketing`.
- **The paid-media stack:** `ad_spend_policy`, `ad_campaign_state`, `ad_decision`,
  `fn_ads_autospend_state()`, `fn_ad_spend_daily_ceiling(p_demo)`, `fn_ad_spend_ceiling_guard()`,
  `fn_ads_manage(p_demo)`, `fn_ads_autopilot_tick()`, `edge:meta_ads`, `edge:meta_sync`,
  `cron:ads_autopilot_daily` (jobid 316, `20 4 * * *`), `cron:meta_sync_daily` (jobid 72).
- **The funnel views:** `marketing_kpis` (29 columns), `v_invite_funnel`, `v_marketplace_liquidity`,
  `v_mkt_over_budget`, `v_obj_content_campaign`.
- **The budget instrument:** `department_budget` (`growth`, AED 120/month, degrade 70%, halt 95%).
- **What must be stored so this seat never asks anyone:** the three anchor quote values the founder
  wants modelled; `ad_spend_policy.target_cpl_aed`; the definition of a "qualified" inquiry; and the
  ordered list of trades to open. **None of these four exist in a table today.**

### 6. Academic knowledge

| discipline | framework | lawful primary source we may ingest |
|---|---|---|
| Procurement (the buyer's own training) | CIPS Level 4 syllabus areas as published | CIPS public qualification specifications |
| Sales process and ethics | NASP CSP competency outline | NASP published standard |
| Marketplace liquidity economics | Two-sided market balance, cold-start sequencing | Published academic working papers and public marketplace post-mortems |
| Statistics of experimentation | Power, minimum detectable effect, sequential-testing error | NIST/SEMATECH Engineering Statistics Handbook (US Government, public domain) |
| Advertising claim substantiation | Truthful-and-substantiated standard | UAE Media Council published advertising regulations; UAE Federal Decree-Law on Consumer Protection |
| Fee and unit economics | Contribution margin, payback period, LTV | Public regulator filings and open textbooks only |

**Certifications held** (`public.role_certification`): rank 1 **CSP (Certified Sales Professional)**,
NASP, pass mark 80% — syllabus: Prospecting and Qualification · Needs Discovery · Presenting Solutions ·
Handling Objections · Closing and Negotiation · Account Management and Ethics. Rank 2 **CIPS Level 4
Diploma in Procurement and Supply**, pass mark 50% — 7 syllabus areas.
**Exams sat: none.** `certification_exam_result` holds **0 rows** for `sales_director`. There is
therefore **no failed syllabus area to report** — the seat is uncertified, not weak, and this document
must not imply otherwise.
**Stored knowledge:** 10 `agent_knowledge` rows, including the `profession`-layer record
*"Selling a marketplace that has not launched"* (priority 74) and the failure-mode records
`exam:1209` (discount addiction), `exam:965` (seeding supply that will not quote),
`exam:1211` (UAE advertising claims), `exam:1210` (supplier tiering).

### 7. Corporate knowledge

- **The founder's standing decisions** live in `ops_knowledge` record `qd-company:decisions` and in
  `decision_policy`. The ones this seat must never re-ask: refunds are the only founder gate
  (17 Aug 2026, restated 5 Sep); the AED 250 refund admin fee and the 3%+9% p.a. refund composition
  (6 Sep 2026, verbatim in `decision_policy.refund_policy_founder_decision_2026_09_06`); trade licence
  DET 1633275 valid to 24 Jun 2027 and no VAT until the AED 375k threshold; agents never move money
  (`auto_action_max_aed = 0`).
- **Pricing:** `pricing_config` — and the fact that the *promo* and *standard* reveal rates are both
  3.00%, so there is currently no promotional lever at all.
- **Workflows owned:** department review gate (`fn_review_submit` with `dept_key='growth'`), the
  paid-media go/no-go recommendation, the trade-opening sequence recommendation, the department budget.
- **Hands to:** `marketplace` and `supply` (category readiness, supplier registration diagnosis),
  `finance` (revenue recognition, `revenue_annual`), `legal` (any comparative or regulated claim),
  `people_ops` (seat accountability), `ceo` (constraint escalation).
- **Receives from:** all six specialists below; `evsub:sales_director@content.published`.
- **History it must not forget:** 344 invites → 0 registrations (the funnel has been proven not to
  convert once); the marketing department key was retired on 10 Aug 2026 and six KPIs still point at it;
  seven of eleven growth crons were switched off and no decision record says who switched them off or
  why. **That last item does not exist anywhere in this estate** — there is no `cron` change ledger for
  these jobs.

### 8. One-year plan

**Objective:** produce the demand side of the company's first AED 1,000,000, and — before that is even
possible — produce the *first reveal in the company's history*.

**Slice of AED 1,000,000:** this seat owns the department's whole contribution, because every dirham of
revenue is a reveal fee and every reveal begins with a buyer this department must bring. It is
**not** a fractional slice; growth is on the critical path for 100% of the target and is the *sole*
owner of none of it (supply must exist for a reveal to be possible).

**Metrics owned (3):**
1. **Reveals in the trailing 30 days** — `count(*) from transactions where revealed_at > now()-30d`.
   Today **0**. This is the only metric on this list that is measurable today.
2. **Qualified inquiries from marketing per month** — `employee_kpi` id 1, target **60/month**,
   actual **0**, measured 7 Sep 2026.
3. **Days to first reveal** — a new metric this plan proposes; **does not exist** today.

**Quarterly milestones** (quarters run from approval of this plan):

| quarter | milestone | measurable as |
|---|---|---|
| Q1 | The supply constraint is retired in **one** trade: 10 confirmed suppliers | `v_invite_funnel.registered ≥ 10` for one `trade_code` |
| Q1 | A measured cost-per-lead exists for the first time | ≥ 1 executed `ad_decision` row with an insight-backed CPL, inside the AED 30/day ceiling |
| Q2 | **First inquiry** and **first quote** in company history | `count(*) from inquiries > 0` and `from quotes > 0` |
| Q2 | `avg_quote_value_aed` computable from ≥ 20 real quotes | `avg(value) from quotes` over ≥ 20 rows |
| Q3 | **First reveal** — the first dirham of revenue | `count(*) from transactions where revealed_at is not null > 0` |
| Q3 | Reveal→revenue rate measured; M-SD-1 stops being a function and becomes a number | ≥ 20 reveals |
| Q4 | 60 qualified inquiries in one month (KPI id 1 met for the first time) | `employee_kpi` id 1 actual ≥ 60 |

**Capacity check — can this seat's work produce AED 1,000,000?**
No, and the arithmetic says so plainly. Three independent bounds:
1. **Supply.** 0 registered suppliers; 10 needed to open one category. Zero reveals are possible until
   this changes, and it is not this department's lever.
2. **Paid media.** The founder's cap of AED 30/day is AED 10,950/year. Carrying 667 reveals (the
   AED 50,000-quote anchor) from that budget alone requires a cost per reveal of **AED 16.42**. This
   estate has never measured a cost per lead, so that figure cannot be called impossible — it can only
   be called **unevidenced**, and the Q1 probe exists to evidence it.
3. **Time.** Even on the optimistic path above, the first reveal lands in Q3. A trailing-12-month
   AED 1,000,000 measured from a Q3 start would require the run-rate of a mature marketplace inside two
   quarters.

**Verdict, stated plainly: the AED 1,000,000 target is not achievable in the coming year on the
current inputs.** What would make it achievable, in the order the arithmetic ranks them:
(a) supplier registrations — the 0/323 invite conversion diagnosed and fixed, which is a `supply`
deliverable this seat can only escalate; (b) `meta_access_token` minted and `meta_autospend_golive` set
true, so the AED 30/day cap stops being AED 0; (c) `ad_spend_policy.target_cpl_aed` given a number, so
the autopilot's kill and scale rules can fire at all; (d) a raise of the daily cap **after**, never
before, a measured CPL exists; (e) `marketing_golive` and `invite_enabled` flipped once the creative
rubric and the invite diagnosis are done.

**Dependencies on other seats:** `supply` (supplier registration — hard blocker); `marketplace`
(category readiness, matching); `finance` (`revenue_annual` measurement); `product_eng` (the visitor and
traffic instrument that five departmental goals need and that does not exist); `legal` (claim
substantiation); and all six specialists in this department for execution.

### 9. What this seat cannot do without a model

- Nothing in sections 1–8 requires one. Every resolver is SQL, arithmetic, a threshold or a ranked
  catalogue; question routing uses the free in-region `gte-small` embedding only to pick a type.
- Two things are *outside* what a coded seat can do and are honestly named here rather than dressed up:
  **(a)** drafting genuinely novel long-form persuasive prose for a new audience — the seat can select,
  assemble and verify from the 317-row `marketing_library` and the stored templates, but it cannot
  *invent* a new argument; **(b)** interpreting an unstructured founder instruction that matches no
  question type above threshold — that produces an honest refusal naming what it would need, plus an
  org task, which is the correct behaviour and not a gap to be filled by a model.

---

## brand_mgr — Brand & Creative Manager

`responsibilities`: *"Owns brand guidelines and is the authority on whether output complies with them."*
`authority_level = execute_low`, `budget_limit = 1,000`. In `employee_authority` it is **advisory** on
`content_calendar`, `content_draft`, `content_revise`, `seo_produce` and **autonomous** on
`boost_recommend`. It is the gate, not the producer.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| BM-01 | Does this creative pass the brand rubric — pass/fail per check, not an opinion | gate | per asset | marketing_design, marketing_social | A failed asset in public is a permanent brand artefact; a wrongly-failed asset stalls the only publishing pipeline there is |
| BM-02 | Is this colour pair legible — what is the measured contrast ratio? | gate | per asset | marketing_design | White on brand teal is 2.5:1 and fails WCAG AA; shipping it makes the brand look amateur and excludes readers |
| BM-03 | Is the logo used in a permitted variant, size and clear space? | gate | per asset | marketing_design | `company_brand.logo.master` is founder-approved artwork; altering it is the one thing nothing may change |
| BM-04 | Does an Arabic asset mirror correctly to RTL? | gate | per Arabic asset | marketing_design, marketing_content | An un-mirrored Arabic layout reads as a machine translation to every UAE buyer |
| BM-05 | Is the claim in this copy substantiated by a live row? | gate | per asset | marketing_content, sales_director | An unsubstantiated claim is a UAE advertising exposure |
| BM-06 | Is the tone right for a procurement audience, not a consumer one? | gate | per asset | marketing_content | The audience is at work on Sunday–Thursday; consumer tone destroys credibility |
| BM-07 | Which brand asset should this surface use, by platform and size? | craft | per asset | marketing_design, marketing_social | Wrong dimensions crop the mark; 58 assets exist and each has one correct use |
| BM-08 | Does the brand promise (comparability without exposure) survive this message? | gate | per campaign | sales_director | Anonymity **is** the product; a message that undermines it undermines the company |
| BM-09 | Should a new brand rule be written, and where does it live? | craft | monthly | founder, marketing_design | A rule not in `company_brand` is a rule that no seat can apply |
| BM-10 | Is this a brand decision or a legal one? | escalation | weekly | sales_director | Comparative claims are legal's, not brand's |
| BM-11 | Has the brand kit drifted from `logo.master`? | diagnosis | monthly | marketing_design | Drift is invisible until it is everywhere |
| BM-12 | Which of the 53 `company_brand` rules does this asset cite? | gate | per asset | marketing_design | An asset citing no rule cannot be reviewed, only argued about |
| BM-13 | Is the tagline used correctly (`UAE SOURCING MARKETPLACE`, Poppins Medium caps, teal-light)? | gate | per asset | marketing_design | The tagline is a registered-style element |
| BM-14 | Does this PDF/email follow the document brand (navy band, teal markers, gold totals)? | gate | per template | product_eng, finance | Customer-facing documents are the brand more often than social is |
| BM-15 | Is the favicon / app icon set complete and derived from the brand square? | gate | quarterly | product_eng | Incomplete icon sets show as generic globes in tabs |
| BM-16 | Should this asset be boosted (`boost_recommend`)? | allocation | weekly | marketing_social | The seat's only autonomous action; a bad recommendation spends the AED 30/day on a weak asset |
| BM-17 | Does the creative have exactly one call to action? | gate | per asset | marketing_design | Two CTAs measurably split intent; the rubric makes this binary |
| BM-18 | Does the video/reel state its hook inside the first 1.5 seconds? | gate | per video | marketing_design, marketing_social | Feed autoplay decides in under two seconds; a slow hook wastes the whole spend |
| BM-19 | Are text and logo inside the platform's safe zone? | gate | per asset | marketing_design | Story/Reel UI overlays the top 250 px and bottom 340 px of a 1080×1920 frame |
| BM-20 | Is the file within the platform's format and weight limits? | gate | per asset | marketing_social | A rejected upload is an invisible failure |
| BM-21 | Does this asset reuse an approved template or invent a new layout? | gate | per asset | marketing_design | Invented layouts are how a brand system dies |
| BM-22 | Which brand rules are missing that reviewers keep arguing about? | diagnosis | quarterly | founder | Every recurring argument is a rule that should have been written |
| BM-23 | Is a competitor's visual similarity a risk to our mark? | diagnosis | quarterly | legal | Trademark dilution |
| BM-24 | Does the brand voice differ for buyer vs supplier audiences, and how? | craft | per campaign | marketing_content | Two audiences with opposite anxieties (stored `agent_knowledge`) |
| BM-25 | Should an asset be withdrawn after publication? | escalation | ad hoc | sales_director | Withdrawal is public; the bar must be a rule, not a mood |
| BM-26 | Is the brand rule this asset breaks a hard rule or a preference? | gate | per rejection | marketing_design | Rejecting on a preference kills throughput |
| BM-27 | What is the department's first-time brand pass rate, honestly? | diagnosis | monthly | sales_director, people_ops | Today's stored 87.5% comes from 8 rows under a retired key |
| BM-28 | Does this asset need Arabic at all? | sequencing | per campaign | marketing_content | Arabic-first is a cost; skipping it in the wrong category loses the buyer |
| BM-29 | Is the image real UAE trade context, or stock? | gate | per asset | marketing_design | `imagery.style` explicitly forbids stock handshakes and blue corporate clip art |
| BM-30 | Refuse: "which creative performs best?" | escalation | weekly | anyone | **There are no performance metrics.** 10 posts, 0 published, no engagement column |

### 2. Domain logic — the creative rubric, as arithmetic

**M-BM-1 — Contrast ratio (WCAG 2.1, exact, deterministic).**
```
for each channel c in {R,G,B} of an sRGB colour, with s = c/255:
    L(c) = s/12.92                     when s ≤ 0.03928
    L(c) = ((s + 0.055)/1.055) ^ 2.4   otherwise
relative_luminance = 0.2126·L(R) + 0.7152·L(G) + 0.0722·L(B)
contrast = (L_lighter + 0.05) / (L_darker + 0.05)
```
Thresholds applied as gates: **body text ≥ 4.5:1**; **large text (≥ 24 px, or ≥ 19 px bold) ≥ 3.0:1**;
**non-text UI and focus indicators ≥ 3.0:1**.
Inputs: the asset's colour pairs; the 53 rows of `public.company_brand` (group `colour`, `contrast`).
The estate has already computed and stored the brand's own matrix (`contrast.on_navy`,
`contrast.on_white`, measured 6 Sep 2026), so the rubric mostly *looks up* rather than recomputes:

| pair | ratio | verdict |
|---|---|---|
| paper `#EAF4F2` on navy `#0C2330` | 14.4:1 | AAA |
| white on navy | 16.2:1 | AAA |
| teal-light `#6EE7D4` on navy | 10.8:1 | AAA |
| gold `#E3C065` on navy | 9.2:1 | AAA |
| muted `#9DB2B2` on navy | 7.3:1 | AAA |
| teal `#14B8A6` on navy | 6.5:1 | AA |
| navy on white | 16.2:1 | AAA |
| teal-deep `#0B8276` on white | 4.7:1 | AA (links, small text) |
| gold-deep `#BD8E36` on white | 3.0:1 | **large text only** |
| teal `#14B8A6` on white | 2.5:1 | **decorative only — fails body text** |
| gold `#E3C065` on white | 1.8:1 | **decorative only** |
| white label on teal button | 2.5:1 | **forbidden** (`contrast.buttons`) |

**M-BM-2 — Safe zones (geometry, per platform).** A text or logo bounding box passes when it lies
entirely inside the frame minus the platform's reserved margins.
```
pass_safe_zone := (box.top ≥ margin_top) ∧ (box.bottom ≤ H - margin_bottom)
                 ∧ (box.left ≥ margin_x) ∧ (box.right ≤ W - margin_x)
```
| surface | canvas (from `company_brand.size.posts` / `size.covers`) | reserved |
|---|---|---|
| Story / Reel / TikTok | 1080 × 1920 | top 250 px (profile + close), bottom 340 px (caption + CTA), sides 60 px |
| Instagram square | 1080 × 1080 | 64 px all sides |
| Instagram portrait | 1080 × 1350 | 64 px sides, 120 px bottom |
| Landscape / in-feed | 1200 × 675 | 60 px all sides |
| Link preview (OG) | 1200 × 630 | 60 px all sides |
| YouTube cover | 2560 × 1440 | **safe area 1546 × 423, centred** (stored value) |
| LinkedIn company cover | 1128 × 191 | 40 px sides |

Only the YouTube safe area is a stored company value today; **the other reserved margins do not exist
in this estate** and must be written into `company_brand` before the rubric can run unattended.

**M-BM-3 — Hook timing.** For any moving asset:
```
pass_hook := (t_first_legible_word ≤ 1.5 s) ∧ (t_first_brand_mark ≤ 3.0 s) ∧ (legible_without_sound = true)
```
`t_first_legible_word` is read from the asset's own caption/keyframe manifest, not judged.
**UNMEASURED: this estate stores no video assets and no keyframe manifest.** `brand_assets` holds 58
static files (avatars, covers, templates, icons, vector source). The rule is written now so that the
first video cannot ship without it.

**M-BM-4 — One CTA.**
```
cta_count := number of elements whose text matches the approved CTA lexicon
             ∪ number of tappable link/button elements
pass_cta  := cta_count = 1
```
The approved CTA lexicon **does not exist** as a table today; it must be created (a short enumerated
list, e.g. *Post your RFQ · Get quotes · Register as a supplier · Compare quotes*) so the count is a
lookup and never a judgement.

**M-BM-5 — Arabic mirrored RTL.** For an Arabic variant of an approved English asset:
```
pass_rtl := (text_direction = 'rtl')
          ∧ (logo_x_mirrored: logo_left_in_EN ⇒ logo_right_in_AR, within ±2 px of the mirrored coordinate)
          ∧ (reading_order = right→left for every text block)
          ∧ (rule/accent bar mirrored: `imagery.social` places the 14 px teal-to-gold rule on the LEFT
             in English ⇒ it must sit on the RIGHT in Arabic)
          ∧ (numerals and AED amounts NOT mirrored, and Latin brand name "QuotesDone" NOT reversed)
          ∧ (font supports Arabic shaping and diacritics)
pass_ar_parity := (ar_asset exists for every en_asset in the same campaign)
```
**UNMEASURED: `brand_assets` has no `locale` column and no Arabic asset. `company_brand` has no Arabic
typography rule.** `brand_acceptance_policy_value` proves the estate already carries Arabic labels
(`label_ar`) elsewhere, so the pattern exists — it has simply never been applied to creative.

**M-BM-6 — The rubric as a single verdict.**
```
rubric_score = Σ over checks of (weight × pass)
verdict      = FAIL if any HARD check fails, else PASS
```
| check | class | source of truth |
|---|---|---|
| Logo variant, clear space (≥ Q-ring height), min size (24 px / 120 px lockup) | HARD | `company_brand.logo.*` |
| No recolour / stretch / rotate / outline / shadow on the mark | HARD | `logo.dont` |
| Every colour pair meets its contrast threshold | HARD | M-BM-1 |
| Text and logo inside the safe zone | HARD | M-BM-2 |
| Exactly one CTA | HARD | M-BM-4 |
| Hook ≤ 1.5 s (moving assets) | HARD | M-BM-3 |
| Arabic variant mirrored correctly | HARD (when an Arabic variant exists) | M-BM-5 |
| Every factual claim resolves to a live row | HARD | §3 below |
| Correct canvas size for the platform | HARD | `company_brand.size.*` |
| Uses an approved template from `kit/03_Social_Post_Templates` | SOFT | `brand_assets` |
| Imagery is real UAE trade context, not stock | SOFT | `imagery.style` |
| Tagline styled correctly when present | SOFT | `logo.tagline` |

**M-BM-7 — First-time pass rate.**
```
ftp = 100 × count(decision='approve') / count(*)   over review_chain where dept_key = 'growth'
```
Live: **209 / 328 = 63.7%** in the last 30 days under `dept_key='growth'`. The value stored on this
seat's KPI is **87.5%**, computed from `dept_key='marketing'` — **16 rows, last written 10 Aug 2026**.
The seat must report 63.7% (n=328) and flag the stored KPI as reading a retired key.

### 3. Reasoning procedures

**BM-01 — "Does this creative pass?"**
1. Load the asset manifest (dimensions, colour pairs, text boxes, CTA elements, locale, cited rules).
2. Look up the platform row in M-BM-2; compute every box against the reserved margins.
3. For each colour pair, look up `company_brand.contrast.*`; if the pair is not in the stored matrix,
   compute M-BM-1 from the hex values. Compare against the size-dependent threshold.
4. Count CTAs (M-BM-4). Count logo violations against `logo.dont` and `logo.min_size`.
5. If `locale='ar'`, run M-BM-5 against the English original.
6. Extract every factual claim and resolve it: supplier count → `v_invite_funnel` (**0 registered**);
   fee → `pricing_config` (**3%**); categories → `seo_categories` (**24**); blog count →
   `blog_posts where published` (**32**). A claim with no resolving row is a HARD fail.
7. Verdict = FAIL on any HARD miss; the memo lists **every** failing check with its measured value and
   its threshold, so the fix is mechanical.
8. Write to `review_chain` with `dept_key='growth'`.
9. **Stop condition:** if the asset is a video and no keyframe manifest exists, refuse with
   "cannot evaluate the hook check — no timing manifest", and open the task to add one. Never pass a
   video by assuming its hook.

**BM-04 — "Does this Arabic asset mirror correctly?"**
1. Require the English original in the same campaign; without it, refuse (there is nothing to mirror).
2. Run M-BM-5 check by check, reporting the measured coordinate against the mirrored expectation.
3. Assert the non-mirrored exceptions explicitly: Latin brand name, AED figures, phone numbers, URLs.
4. **Stop condition:** `brand_assets` has no `locale` column today, so step 1 cannot be executed
   automatically. Until that column exists the seat refuses and says exactly that.

**BM-16 — "Should this asset be boosted?"** (the seat's one autonomous action)
1. Read `fn_ads_autospend_state()`. If `live_allowed=false` → recommend **no boost** and state the
   reason is the absent token and go-switch, not the asset.
2. If live: the asset must have passed BM-01 within 7 days, and must carry a measured engagement
   baseline. **There is no engagement column in `social_posts`**, so today every asset fails this
   precondition and the honest recommendation is always "cannot rank; no engagement instrument".
3. Cap the recommendation at `ad_spend_policy.min_daily_per_campaign_aed` (AED 20) for a first boost.

**BM-27 — "What is our brand pass rate?"** Run M-BM-7 on both keys, report `growth` as the answer and
`marketing` as the artefact, with row counts beside both. Never report a percentage without its n.

**BM-30 — "Which creative performs best?"** Refuse. Compose:
"Cannot answer. The account holds 10 posts, all of them Postiz drafts, `social_published = 0`, and
`social_posts` carries no impressions, reach, likes, comments or shares column. There is no performance
data in this estate — not a low number, no instrument. To answer this I need an engagement table fed
from the network APIs." Open the org task; do not guess.

### 4. Judgement rules

| # | condition | verdict | reason |
|---|---|---|---|
| J-BM-1 | Any HARD rubric check fails | **Reject** | The rubric is boolean by design so rejection is never an opinion |
| J-BM-2 | Body text contrast < 4.5:1 | Reject | WCAG AA; teal on white is 2.5:1 and this is the most common breach available |
| J-BM-3 | White label on a teal button | Reject | `contrast.buttons` forbids it explicitly (2.5:1) |
| J-BM-4 | The mark is recoloured, stretched, rotated, outlined or shadowed | Reject, no revision offered | `logo.dont`; the master is founder-approved artwork |
| J-BM-5 | Mark below 24 px on screen or 8 mm in print | Reject | `logo.min_size` |
| J-BM-6 | CTA count ≠ 1 | Reject | Two CTAs split intent; zero CTAs waste the impression |
| J-BM-7 | Moving asset with no legible hook by 1.5 s | Reject | Autoplay decides before 2 s |
| J-BM-8 | Arabic asset not mirrored, or Arabic missing where the campaign promised parity | Reject | An un-mirrored Arabic layout reads as machine output |
| J-BM-9 | A claim with no resolving live row | Reject, **not** revise | Unsubstantiated public claims are a regulatory exposure |
| J-BM-10 | Asset states a supplier count | Reject unless it equals `sum(registered) from v_invite_funnel` (**0**) | The most dangerous number this company could publish today |
| J-BM-11 | Asset is stock imagery / handshake / blue corporate clip art | Reject | `imagery.style` names these |
| J-BM-12 | Asset scores highly but invents a new layout outside the template kit | **Reject even though it scores well** | A one-off great layout costs more in system decay than it earns in one post |
| J-BM-13 | Asset is on brand but undermines anonymity as the product | **Reject even though it passes every visual check** | The brand promise is comparability without exposure |
| J-BM-14 | Comparative or superlative claim naming a competitor | Route to `legal`, never approve here | `decision_policy.legal_triggers` |
| J-BM-15 | A rejection cannot cite a `company_brand` row | **Do not reject** — approve and open a task to write the missing rule | Rejecting on an unwritten preference is how a gate loses legitimacy |
| J-BM-16 | Asked to rank creative performance | Refuse and name the missing instrument | 10 posts, 0 published, no engagement column |
| J-BM-17 | Boost recommended while `live_allowed=false` | Refuse; state the token/go-switch as the reason | Never blame the asset for a switch |
| J-BM-18 | An asset was approved and later found non-compliant | Withdraw only on a HARD breach; log both decisions | Public withdrawal has its own cost |

### 5. Technical knowledge

- **`public.company_brand`** — all 53 rows, by group: `colour` (15), `contrast` (4), `gradient` (3),
  `logo` (9), `imagery` (3), `sizes` (4) and the rest. The seat must know the exact tokens: teal
  `#14B8A6` (primary), navy `#0C2330` (background), gold `#E3C065` (secondary), paper `#EAF4F2`, muted
  `#9DB2B2`, teal-deep `#0B8276`, gold-deep `#BD8E36`, ink `#0A0A0A`; the three gradients; the mark's
  SVG geometry (`viewBox 0 0 800 800`, circle `cx 400 cy 398 r 92 stroke 50`, check
  `M434 470 L486 524 L582 408 stroke 44`).
- **`public.brand_assets`** — 58 files with `kind`, `platform`, `bucket`, `path`, `folder`, `bytes`,
  `sha256`, `width`, `height`, `usage`. The eight kit folders (`01_Social_Avatars` …
  `08_Vector_Source`). `sha256` is what makes drift detectable.
- **WCAG 2.1 relative-luminance and contrast formulas** (M-BM-1) — the seat must be able to compute,
  not only look up, because a new colour will appear.
- **Platform canvases and safe zones** — the sizes are stored; **the reserved margins are not**.
- **Arabic/RTL mechanics** — bidirectional text, mirrored layout, non-mirrored numerals and Latin
  strings, Arabic shaping. `brand_acceptance_policy_value.label_ar` shows the estate's Arabic pattern.
- **`fn_brand_scan()`** (a registered `phase_c_component`), `table:brand_signal` — **`brand_signal` is
  empty**, so the scan has never recorded a signal.
- **`fn_review_submit(...)` and `review_chain`**, with `dept_key='growth'` as the live key.
- **`evsub:brand_mgr@content.drafted`** — the event that wakes this seat.
- **What must be stored so the seat never asks anyone:** per-platform reserved margins; the approved CTA
  lexicon; a `locale` column on `brand_assets`; a keyframe/timing manifest for video; and the Arabic
  typography rule. **None of these five exist today.**

### 6. Academic knowledge

| discipline | framework | lawful primary source |
|---|---|---|
| Accessibility | WCAG 2.1 / 2.2 success criteria 1.4.3, 1.4.11, 1.4.6 | W3C Recommendation (public standard) |
| Colour science | sRGB transfer function, relative luminance | IEC 61966-2-1 as published; W3C definitions |
| Internationalisation | Unicode Bidirectional Algorithm; CSS Logical Properties | Unicode Standard Annex #9 (public); W3C CSS specs |
| Typography and layout | Grid systems, optical alignment, minimum legible size | Public type-foundry specimens and W3C guidance |
| Advertising regulation | Truthful and substantiated claims, prohibited comparatives | UAE Media Council published advertising regulations |
| Trademark | Distinctiveness, colour-and-black-and-white filing practice | WIPO published guidance; UAE Ministry of Economy trademark rules |
| Brand strategy | Positioning, brand promise, category entry points | CIM published syllabus outlines |

**Certification held:** rank 1 **CIM Level 6 Diploma in Professional Marketing**, pass mark 50% —
syllabus: Marketing and Digital Strategy · Innovation in Marketing · Marketing Communications ·
Digital Optimisation · Driving Innovation · Corporate Digital Communications.
**Exams sat: none** (`certification_exam_result` has 0 rows for `brand_mgr`). No failed syllabus area
exists to report.
**Stored knowledge:** 5 `agent_knowledge` rows — the `profession`-layer record *"Brand for a marketplace
whose product is anonymity"* (priority 74), plus `exam:736` (RFQ-form friction), `exam:737` (optimising
paid campaigns to leads instead of reveals), `exam:739` (category specialist OS), `exam:authority`
(the UAE Media Council as the licensing authority for advertising).

### 7. Corporate knowledge

- **The founder-approved artwork is immutable**: `company_brand.logo.master` =
  `kit/07_Trademark_and_License/ORIGINAL_approved_master_800.png`, with the note *"Nothing about the
  logo changes without him; everything else in the kit may be upgraded."* This is a founder ruling and
  must never be re-asked.
- **The brand promise** — comparability without exposure — is the product, not a slogan. Stored in this
  seat's own `agent_knowledge` and in `ops_knowledge:qd-company:brand` and `qd-company:identity`.
- **The sidebar is approved**: a standing founder decision that the portal sidebar is not to be "fixed".
  Brand review must not raise it.
- **What this seat gates:** every asset before it leaves the department; it does **not** own the
  calendar (advisory), the copy (advisory) or publishing (that is `marketing_social`, gated by
  `sales_director`).
- **Hands to:** `marketing_design` (fix list), `marketing_content` (claim substantiation),
  `sales_director` (final departmental approval), `legal` (comparative claims), `product_eng`
  (document and email templates).
- **History it must not forget:** the ten posts of June–August 2026 were reviewed and staged but never
  published; four of them can no longer be recovered from Postiz at all. Nothing in the estate records
  a brand rejection of those posts — `review_chain` shows exactly **one** `reject` under `dept_key='marketing'`,
  on 26 July 2026. The kit was last updated 6 September 2026.

### 8. One-year plan

**Objective:** make "on brand" a computed verdict rather than a discussion, so that the department can
publish at volume without a human in the loop and without brand decay.

**Slice of AED 1,000,000:** this seat produces **AED 0 directly** and should never be given a revenue
number — it is a gate. Its contribution is stated as *throughput enabled without brand loss*: the
number of assets that reach publication with a first-time PASS. Assigning it a revenue slice would
create exactly the incentive to approve weak work.

**Metrics owned (2):**
1. **First-time PASS rate**, M-BM-7 on `dept_key='growth'`. Live **63.7% (n=328)**. Target: **≥ 85%
   with n ≥ 100/month** — and the target is met by improving *briefs*, not by loosening the rubric.
2. **Rubric coverage** — the share of HARD checks that are machine-executable today.
   Live: 5 of 9 (logo rules, contrast, canvas size, CTA count once the lexicon exists, claim
   resolution). Safe zones, hook timing, Arabic mirroring and template compliance are **not
   executable** because the reserved margins, the timing manifest and the `locale` column do not exist.
   Target: **9 of 9**.

**Quarterly milestones:**

| quarter | milestone | measurable as |
|---|---|---|
| Q1 | Per-platform reserved margins written into `company_brand` | rows exist for 7 surfaces |
| Q1 | Approved CTA lexicon table created | table exists, ≥ 4 entries |
| Q1 | `brand_assets.locale` column added; every existing asset labelled | `count(*) where locale is null = 0` |
| Q2 | Rubric runs as a single deterministic function returning a per-check verdict | one routine, 9 boolean outputs |
| Q2 | Arabic parity rule live; first Arabic asset passes M-BM-5 | ≥ 1 asset with `locale='ar'` and PASS |
| Q3 | Keyframe/timing manifest format defined; first video passes the 1.5 s hook check | ≥ 1 video asset with a manifest |
| Q3 | `fn_brand_scan()` writes its first `brand_signal` rows (drift detection live) | `count(*) from brand_signal > 0` |
| Q4 | First-time PASS ≥ 85% at n ≥ 100/month, with zero HARD breaches published | `review_chain` |

**Capacity check:** yes — but only for the checks that have stored thresholds. Four of the nine HARD
checks cannot run today for want of data this seat can specify but must have created for it. The
throughput ceiling is not the seat, it is that **`marketing_golive = false` and nothing is being
published at all**: a gate with no traffic has infinite capacity and zero value.

**Dependencies:** `marketing_design` (produces what is gated), `marketing_content` (claims),
`marketing_social` (publishing, currently off), `sales_director` (final approval), `product_eng`
(the `locale` column, the margins table, the CTA lexicon table), `legal` (comparative claims).

### 9. What this seat cannot do without a model

- **Nothing in the rubric.** Contrast is arithmetic, safe zones are geometry, CTA count is a lexicon
  lookup, hook timing is a manifest read, RTL mirroring is coordinate comparison, claim substantiation
  is a row lookup. All nine HARD checks are deterministic.
- **Genuinely subjective aesthetic quality** — "is this beautiful", "is this the strongest of three
  compliant options" — is not decidable by rule and is honestly out of scope. The seat's answer is
  "all three PASS; ranking them requires a performance measurement this estate does not have", which is
  the correct professional answer and does not need a model either.
- **Reading an image file to extract its colour pairs, text boxes and CTA elements** requires a
  *manifest*, not a model: the producer (`marketing_design`, `edge:marketing_image`) must emit the
  manifest alongside the asset. If instead the seat were asked to judge an arbitrary uploaded PNG with
  no manifest, that would need vision — and the answer is to require the manifest, not to add a model.

---

## marketing_analyst — Marketing Performance Analyst

`responsibilities`: *"Measures campaign performance and reports which company goal each campaign moved."*
`authority_level = advisory`, `budget_limit = 0`. `employee_authority`: **advisory** on everything except
`boost_recommend` (autonomous) and an explicit `recommend` row noted *"Analysis and recommendation
only."* This seat measures and refuses; it never executes.

It is also the only seat in this department that has ever sat an exam — and it failed both attempts.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| MA-01 | How many likes should this post get, and how many did it? | forecast | per post | marketing_social | The whole social programme is unfalsifiable without a stated expectation |
| MA-02 | What is our cost per lead? | diagnosis | weekly | sales_director, founder | The single number that decides whether the AED 30/day cap is worth raising |
| MA-03 | What is our cost per reveal — the only cost that maps to revenue? | diagnosis | weekly | sales_director | Optimising to leads instead of reveals is the stored failure mode `exam:737` |
| MA-04 | Which channel produced this inquiry? | diagnosis | per inquiry | sales_director | **`inquiries` carries no channel field** — a fabricated attribution poisons every later decision |
| MA-05 | Is this month's movement signal or noise? | diagnosis | monthly | sales_director | Acting on noise burns the only budget there is |
| MA-06 | Is this A/B result statistically real? | gate | per experiment | optimisation_eng | `exam:1128`: peeking and p-hacking accumulate changes that do nothing |
| MA-07 | How many impressions do we need for one reveal? | forecast | monthly | sales_director | Sizes the entire top of the funnel |
| MA-08 | What is the minimum sample size to detect a given lift? | gate | per experiment | optimisation_eng | An underpowered test wastes the test *and* the traffic |
| MA-09 | Has a KPI gone dark, and since when? | diagnosis | weekly | people_ops, sales_director | A dark KPI silently converts accountability into theatre |
| MA-10 | Is a stored KPI value real or an artefact of a retired filter? | diagnosis | weekly | sales_director | Six growth KPIs read `dept_key='marketing'`, retired 10 Aug 2026 |
| MA-11 | What does a zero actually mean here — no demand, no instrument, or a dead guard? | diagnosis | weekly | sales_director, ceo | The department's most repeated error; `marketing_says_what_a_zero_might_also_mean.sql` exists for this |
| MA-12 | What is the trailing-30-day AI spend for this department against AED 120? | diagnosis | weekly | finance, optimisation_eng | Overrun halts the department's automation at 95% |
| MA-13 | Which of the five departmental goals can be measured at all? | diagnosis | monthly | sales_director | **Zero of five** have a `measure_sql` |
| MA-14 | What is the invite funnel's conversion, by trade? | diagnosis | weekly | supply, sales_director | 344 invited → 0 registered; the per-trade split is where a cause hides |
| MA-15 | Is the bounce rate on invites a deliverability problem or a list problem? | diagnosis | weekly | supply | 21/344 bounced; the wrong diagnosis burns domain reputation |
| MA-16 | What is the forecast for reveals next quarter, with its confidence interval? | forecast | quarterly | ceo | A point estimate from zero data is the classic failure of this seat |
| MA-17 | Which campaign moved which `company_goals.key`? | diagnosis | monthly | sales_director | The seat's stated responsibility and its own KPI |
| MA-18 | Is this campaign's attribution window long enough for a B2B journey? | gate | per campaign | marketing_social | `exam:1138`: B2B journeys span sessions and weeks |
| MA-19 | Should this campaign be killed, scaled or left in learning? | allocation | daily (when live) | sales_director | The autopilot's rules need a target CPL that is **null** today |
| MA-20 | What CPL would make the AED 30/day cap worth raising? | forecast | monthly | founder | The one calculation that turns his cap into a decision |
| MA-21 | Is the marketing snapshot fresh enough to answer from? | gate | per answer | anyone | Last snapshot 2026-08-15, 23 days stale |
| MA-22 | What is the engagement rate on our social account? | diagnosis | monthly | sales_director, founder | **No engagement column exists**; any number is invented |
| MA-23 | How many of the 22,265 leads are reachable? | diagnosis | monthly | supply | 19,896 have an email; the rest cannot be contacted at all |
| MA-24 | Which category has demand signal we are not serving? | diagnosis | monthly | marketplace | `marketing_category_demand` exists but the funnel is empty |
| MA-25 | What is the LTV of a buyer under a reveal-fee model? | forecast | quarterly | sales_director | `exam:884`: reveals × fee × retention, discounted; retention is unmeasured |
| MA-26 | What is the payback period on an acquired buyer? | forecast | quarterly | finance | `exam:1133`: payback overrides LTV:CAC as the cash constraint |
| MA-27 | Is a benchmark number safe to plan on? | gate | ad hoc | anyone | `exam:894`: benchmarks are hypotheses, never targets |
| MA-28 | Does this report state a number nobody measured? | gate | per report | all seats | The founder's standing rule, enforced at the reporting layer |
| MA-29 | Is the difference between two cohorts explained by mix rather than performance? | diagnosis | monthly | sales_director | Simpson's paradox; group per class, never in aggregate |
| MA-30 | What is the run rate, as distinct from the 30-day total? | forecast | monthly | finance, ceo | A 30-day total is not a run rate |
| MA-31 | Which single instrument, if built, would unlock the most currently-unanswerable questions? | sequencing | quarterly | product_eng, founder | Ranks the instrument backlog by questions unblocked |
| MA-32 | Refuse: any traffic, visitor, session or organic-share question | escalation | weekly | anyone | No analytics table exists in this estate |

### 2. Domain logic (the models this seat reasons with)

**M-MA-1 — The social funnel identity (the arithmetic the department was asked to hold).**
```
impressions  = reach × frequency
views        = impressions × view_rate           -- a "view" per the platform's own definition
likes        = impressions × view_rate × like_rate
             = views × like_rate
engagements  = likes + comments + shares + saves + link_clicks
engagement_rate = engagements / impressions      -- state the denominator every time
clicks       = impressions × ctr
sessions     = clicks × (1 - bounce_before_load)
inquiries    = sessions × visit_to_rfq_rate
reveals      = inquiries × match_rate × quote_rate × reveal_rate
revenue_aed  = reveals × avg_quote_value_aed × 0.03
```
Inverted, so the seat can answer "how much top of funnel does one dirham need":
```
impressions_per_reveal = 1 / (view_rate × like_rate)            -- when optimising to engagement
impressions_per_reveal = 1 / (ctr × visit_to_rfq × match × quote × reveal)   -- when optimising to revenue
```
Inputs and where each comes from:

| term | live source | value today |
|---|---|---|
| `impressions`, `reach`, `frequency` | `marketing_kpis.meta_impressions_30d`; a network insights table | **0** / **does not exist for organic** |
| `view_rate`, `like_rate`, `comments`, `shares`, `saves` | **does not exist** — `social_posts` has no such column | **UNMEASURED** |
| `ctr`, `clicks` | `marketing_kpis.meta_clicks_30d` | **0** |
| `sessions`, `bounce` | **does not exist** — no analytics table in this estate | **UNMEASURED** |
| `visit_to_rfq_rate` | `inquiries` / sessions | **UNMEASURED** (0 inquiries, no sessions) |
| `match_rate`, `quote_rate`, `reveal_rate` | `marketing_kpis.inq_to_quote_pct`, `quote_to_reveal_pct` | **null** |
| `avg_quote_value_aed` | `quotes` | **UNMEASURED** (0 rows) |
| fee rate | `pricing_config.standard_reveal_rate` | **0.03** |

**Every rate in the identity is unmeasured. Exactly one term — the 3% fee — is known.** The seat's
correct behaviour is therefore to publish the identity, name each missing term with the table that
would hold it, and **refuse to produce a number**. The identity is not decoration: it is the instrument
backlog, ordered.

**M-MA-2 — Paid economics against the founder's cap.**
```
effective_daily_ceiling = fn_ad_spend_daily_ceiling()        -- AED 0 today; AED 30 once live_allowed
monthly_paid_ceiling    = effective_daily_ceiling × 30.4     -- AED 912 at the cap
annual_paid_ceiling     = effective_daily_ceiling × 365      -- AED 10,950 at the cap
cpl                     = spend / leads
cpr (cost per reveal)   = spend / reveals
reveals_affordable      = annual_paid_ceiling / cpr
raise_the_cap_when      = cpr × reveals_required < revenue_at_target   (i.e. paid pays for itself)
break_even_cpr          = avg_quote_value_aed × 0.03                   -- AED 1,500 at the 50k anchor
```
`break_even_cpr` is the sharp version of MA-20: **paid media is worth raising above AED 30/day exactly
when the measured cost per reveal is below 3% of the average quote value.** Both operands are
unmeasured today, which is why the AED 30/day probe (SD-28) is the highest-value experiment available.

**M-MA-3 — The autopilot's own rule arithmetic** (so the seat can predict what the manager will do):
```
in_learning  := (now - started_at) < learning_phase_days (3)  OR  spend < learning_min_spend_aed (100)
kill_3x      := not in_learning AND ( cpl > kill_multiplier (3) × target_cpl_aed  OR  (spend > 0 AND leads = 0) )
scale_winner := not in_learning AND cpl ≤ target_cpl_aed AND budget < max_daily_per_campaign_aed (30)
                AND headroom under the ceiling → new_budget = budget × 1.20
tracking_gate:= spend > learning_min_spend_aed AND results field absent → pause
```
**`target_cpl_aed` is NULL.** With a null target, `cpl > 3 × null` is null and `cpl ≤ null` is null, so
`kill_3x` can only fire on its "spend and no leads" limb and `scale_winner` can never fire at all. The
seat must report this as a **missing founder input**, not as a code defect.

**M-MA-4 — Significance and power (no model, standard statistics).**
For a two-proportion test at α = 0.05, power = 0.80 (z₁₋α/₂ = 1.96, z₁₋β = 0.84):
```
n_per_arm = ( z₁₋α/₂ ·√(2·p̄·(1-p̄))  +  z₁₋β ·√(p₁(1-p₁)+p₂(1-p₂)) )² / (p₂-p₁)²
approximation for planning: n_per_arm ≈ 16 · p̄ · (1-p̄) / (MDE)²
```
Worked so the seat has a stored answer: to detect a lift from a 2% baseline to 2.4% (a 20% relative
MDE), `n_per_arm ≈ 16 × 0.022 × 0.978 / 0.004² ≈ 21,500` exposures **per arm**.
Live: `experiments` = 2, `experiment_assignments` = **1**, `experiment_events` = **0**. Both
experiments have been "running" since 6 July 2026. **Neither can ever reach significance**; the correct
verdict is to stop them.

**M-MA-5 — What a zero means (three causes, one number).**
```
zero_cause :=
  'NO INSTRUMENT'  when the measure_sql is null or the column does not exist
  'NO TRAFFIC'     when the instrument exists and its table has 0 rows in the window
  'DEAD GUARD'     when the instrument exists, rows exist, but the filter literal has taken no write in 14 days
```
Applied today: `website_visitors`, `organic_traffic`, `lead_conversion`, `social_engagement`,
`marketing_roi` → **NO INSTRUMENT**. `Qualified inquiries from marketing` (0) → **NO TRAFFIC**.
`Brand compliance rate` (87.5%) → **DEAD GUARD**. Three identical-looking zeros, three different
actions. Reporting them as one number is the department's most expensive habit.

**M-MA-6 — Run rate vs total.**
```
run_rate_monthly = (total over window) × (30.4 / window_days)     -- only valid when the window is stationary
stationary       := no more than one order of magnitude between the busiest and quietest day
```
`ai_cost_log`: 11–15 Aug 2026 ran AED 38.00, 22.58, 21.54, 29.30, 15.73, 7.55/day; 3–7 Sep 2026 ran
**AED 0.00/day on 78–293 calls**. The window is **not** stationary (OpenRouter is held), so a 30-day
total may not be presented as a run rate at all.

**M-MA-7 — Attribution, honestly.** `inquiries` has no channel, source, campaign or UTM column, and no
session table exists to join to. Therefore:
```
attributable_share = 0 / count(*) inquiries    -- 0/0 today; would be 0/n once inquiries exist
```
The seat's own stored `agent_knowledge` opens with exactly this: *"The honest position first: inquiries
carry no channel field, so channel attribution cannot currently be computed."* Until a channel column
and a first-touch capture exist, **every attribution answer is a refusal with a named remedy.**

### 3. Reasoning procedures

**MA-01 — "How many likes should this post get?"**
1. Retrieve the post from `social_posts`; read `channels` and `status`.
2. Attempt to read the impression and view counts. **They do not exist as columns.**
3. Attempt a historical baseline: `social_published = 0` across all 10 posts, so there is no prior.
4. Compose the refusal with the identity intact:
   *"Cannot forecast. likes = impressions × view_rate × like_rate. None of the three terms exists in
   this estate: `social_posts` has no impressions, views, likes, comments or shares column, all 10 posts
   are Postiz drafts and 0 have been published, so there is no prior to draw a rate from. To answer this
   I need (a) publication actually enabled — `marketing_golive` is false — and (b) a
   `social_post_metrics` table fed from the network APIs on a schedule."*
5. Open the org task for the instrument. Never substitute an industry benchmark
   (J-MA-6 / `exam:894`).

**MA-02 / MA-03 — "What is our cost per lead / per reveal?"**
1. `ad_decision` → 0 rows. `ad_campaign_state` → 0 rows. `marketing_kpis.meta_spend_30d` → 0.00,
   `meta_cpl` → null.
2. `fn_ads_autospend_state()` → `golive=false, token_present=false, cap_aed=30, live_allowed=false`.
3. Verdict: **no spend has ever occurred, so no CPL exists.** Report the two facts the founder can act
   on: the cap he set (AED 30/day) is dormant because the token and go-switch are absent, and the
   break-even cost per reveal is `avg_quote_value × 0.03`, itself unmeasured.
4. Refuse to quote a market benchmark as our CPL.

**MA-05 / MA-11 — "Is this signal, and what does the zero mean?"**
1. Run M-MA-5 to classify the zero. Report the class, not the number, first.
2. If NO INSTRUMENT: name the table that would hold it and the routine that would fill it; open a task
   against `product_eng`; stop.
3. If NO TRAFFIC: state the window, the row count and the upstream stage that is also zero, so the
   reader sees the chain (`0 inquiries ← 0 sessions ← nothing published ← marketing_golive=false`).
4. If DEAD GUARD: report the filter literal, its last write date and the live literal that is receiving
   writes instead.

**MA-06 / MA-08 — "Is this A/B result real?"**
1. Read `experiments`, `experiment_assignments`, `experiment_events`.
2. If `events = 0`, no test statistic is computable. **Stop** — report "no exposures recorded", not
   "no difference detected". Those are opposite statements.
3. If events exist, compute the required `n` from M-MA-4 **before** looking at the outcome, and record
   it; compare the achieved n. Under-powered → report UNDERPOWERED and the achieved MDE.
4. Only then compute the two-proportion z and the confidence interval. Report the interval, never a
   bare p-value.
5. Refuse to report a "winner" from a test with a single interim look and no pre-registered n.

**MA-10 — "Is this stored KPI real?"** — the same three-step as SD-13, run for every row of
`employee_kpi where agent_key in (this department)` on a weekly schedule; the output is a table of
`kpi | stored value | recomputed value | n | class`. Today it returns six DEAD GUARD rows (87.5% from
n=16 under `marketing`, against 63.7% from n=328 under `growth`) and two NULL rows
(`Publishing cadence met` and `Engagement rate`, both `measured_at = null`).

**MA-31 — "Which instrument unlocks the most?"**
1. For each unanswerable question type across this whole department, record the missing table/column.
2. Group by missing instrument; count the question types blocked.
3. Rank. Today the ranking is: **(1) a web analytics instrument** — blocks `website_visitors`,
   `organic_traffic`, `lead_conversion`, plus every `visit_to_rfq` term in M-MA-1;
   **(2) a social metrics table** — blocks `social_engagement`, the whole of M-MA-1's engagement half,
   MA-01, MA-22 and `brand_mgr`'s BM-16 and BM-30; **(3) a channel column on `inquiries`** — blocks all
   attribution and `marketing_roi`.

### 4. Judgement rules

| # | condition | verdict | reason |
|---|---|---|---|
| J-MA-1 | The measure for a question does not exist | **Refuse and name the instrument** | The founder's standing rule: never state what you have not measured |
| J-MA-2 | A metric's denominator is 0 | Report "undefined", never 0% and never 100% | 0/0 is not a rate |
| J-MA-3 | n < the pre-registered required sample | Report UNDERPOWERED; do not declare a winner | `exam:1128` |
| J-MA-4 | An experiment has 0 recorded events | "No exposures recorded" — **never** "no difference" | Opposite statements; both experiments are in this state |
| J-MA-5 | An experiment has run > 30 days with < 100 assignments | Recommend stopping it | Two have run since 6 Jul 2026 with 1 assignment |
| J-MA-6 | A benchmark is offered as a target or as our own figure | **Reject even though it is convenient** | `exam:894`: benchmarks are hypotheses, validated against our own cohort or not used |
| J-MA-7 | An attribution is requested | Refuse; `inquiries` has no channel column | The seat's own `agent_knowledge` states this as its opening position |
| J-MA-8 | A window is non-stationary | Do not convert a total into a run rate | Sep AI spend is AED 0/day against an Aug peak of AED 38/day |
| J-MA-9 | A KPI's filter literal has had no write in 14 days | Class it DEAD GUARD; report it dark | Six KPIs are in this state |
| J-MA-10 | Two cohorts differ and their mix also differs | Report per class, never in aggregate | Mix effects masquerade as performance |
| J-MA-11 | The marketing snapshot is > 7 days old | Refuse to answer from it; state its date | Last snapshot 2026-08-15 |
| J-MA-12 | A campaign optimises to leads rather than reveals | **Flag it even though the lead numbers look good** | `exam:737`: choosing the wrong conversion event is the most expensive paid-media error available |
| J-MA-13 | `target_cpl_aed` is null and someone asks whether to scale a campaign | Refuse; the scale rule cannot fire | Missing founder input, not a defect |
| J-MA-14 | Asked for a forecast with no historical rate | Give the identity and the missing terms, not a number | A point estimate from zero data is a fabrication |
| J-MA-15 | A report contains a number with no cited row | Return the report unpublished | The seat is the department's honesty gate |
| J-MA-16 | Asked to execute anything | Refuse — `advisory` only | `employee_authority`: *"Analysis and recommendation only."* |
| J-MA-17 | A "record month" is claimed on n < 30 | Report the count beside the claim | Small-sample records are noise with a headline |
| J-MA-18 | A fix makes a headline number fall | **Say so explicitly** | Standing rule; a falling honest number beats a rising false one |

### 5. Technical knowledge

- **`marketing_kpis`** — all 29 columns and what each is derived from; today: `inquiries_30d` 0,
  `matched_30d` 0, `quoted_30d` 0, `revealed_30d` 0, `revenue_30d` 0, `inq_to_quote_pct` null,
  `quote_to_reveal_pct` null, `blog_published` 32, `social_staged` 10, `social_published` **0**,
  `seo_pages` 24, `leads_total` 22,265, `outreach_sent` 20, `mkt_spend` 0, `new_customers_30d` 1,
  `cac` null, `roi` null, `meta_*` all 0 or null.
- **`marketing_snapshots`** — 38 rows, `kpis` and `plan` jsonb, last `snapshot_date` **2026-08-15**.
  The seat's own KPI ("Campaign attribution coverage", target 100%, actual 100%) is satisfied merely by
  *a snapshot existing in 30 days* — a KPI that measures its own heartbeat, not attribution.
- **`experiments` / `experiment_assignments` / `experiment_events`** — 2 / 1 / 0.
- **`ai_cost_log`** — `occurred_at`, `cost_aed`, `cached`, `could_be_cheaper`, `model_used`, `tier`,
  `ok`, `fn`. `department_budget` for `growth`: AED 120/month.
- **The paid stack** as listed for `sales_director`, plus `fn_ads_autopilot_tick()` reporting the
  autospend state so a silent tick says why.
- **`v_invite_funnel`** — per-trade `invited / delivered / bounced / registered`; 37 trades,
  344 / 323 / 21 / **0**.
- **Two-proportion tests, power, MDE, confidence intervals, sequential-testing error** — computed, not
  looked up.
- **What must be stored so the seat never asks anyone:** `ad_spend_policy.target_cpl_aed`; a
  `social_post_metrics` table; a `web_sessions` table; a `channel` / first-touch column on `inquiries`;
  and the pre-registered sample size on every `experiments` row. **None of these five exist.**

### 6. Academic knowledge

| discipline | framework | lawful primary source |
|---|---|---|
| Statistics | Hypothesis testing, power, confidence intervals, sequential error | **NIST/SEMATECH e-Handbook of Statistical Methods** (US Government, public domain) |
| Experimental design | Randomisation, pre-registration, MDE | Public methodological papers and open pre-registration templates (OSF) |
| Measurement | Definition of impressions, reach, frequency, viewability | **IAB / MRC Measurement Guidelines** (published standards) |
| Web analytics | Event and conversion modelling, attribution models | Google Analytics 4 published developer documentation |
| Marketing mix and ROI | Contribution, incrementality, holdout design | Public regulator and standards-body publications only |
| Causal inference | Confounding, Simpson's paradox, difference-in-differences | Open-access textbooks and public lecture notes |

**Certifications held:** rank 1 **Google Analytics 4 Certification** (Google, pass mark **80%**) —
syllabus: GA4 Property Setup · Data Collection and Events · Conversions and Audiences · Reports and
Explorations · Attribution and Data Modelling · Integrations and Data Quality. Rank 2
**CDMP-DMI** (Digital Marketing Institute, pass mark 60%) — 7 syllabus areas.

**Exams sat — and this is the only exam record in the department.** `certification_exam_result` holds
**two attempts at GA4, both on 2026-09-07, both failed against the 80% pass mark**:

| method | questions | correct | score | passed |
|---|---|---|---|---|
| `semantic` | 40 | 10 | **25%** | false |
| `lexical` | 40 | 14 | **35%** | false |

Weakest syllabus areas, by attempt (`asked → correct`):

| syllabus area | semantic | lexical |
|---|---|---|
| Key events and conversions | 6 → **0** | 6 → 2 |
| Events and parameters | 7 → **1** | 7 → 1 |
| Explorations | 7 → **1** | 7 → 3 |
| Audiences | 4 → 1 | 4 → 2 |
| Data collection and configuration | 7 → 2 | 7 → 3 |
| Attribution | 6 → 3 | 6 → **1** |
| Reporting identity | 3 → 2 | 3 → 2 |

The two areas the seat is worst at — **key events/conversions** and **attribution** — are precisely the
two this company needs (choosing the reveal, not the lead, as the conversion event; and channel
attribution). This is the department's most actionable training signal and it is real, measured, and
should not be softened.

**Stored knowledge:** 8 `agent_knowledge` rows including the `profession`-layer record *"Attribution for
a marketplace with no attribution data yet"* (priority 74) and `exam:1122` (whale tenders),
`exam:1123` (brand statements need approval), `exam:878` (RFQ landing-page CRO),
`exam:879` (paid social for B2B: retargeting and supply recruitment beat cold prospecting).

### 7. Corporate knowledge

- **The reporting rule:** never state what has not been measured; where a number is absent, say
  "does not exist" and name the instrument. This is a founder rule, not a style preference.
- **The three-cause zero** (M-MA-5) and the estate's own precedent file
  `scripts/sql/marketing_says_what_a_zero_might_also_mean.sql`.
- **The fee model:** 3% reveal, no promotional differential (promo rate = standard rate = 3%), supplier
  registration AED 1,000/year with the first 1,000 free — so **supplier fees contribute AED 0 to
  year-one revenue by design**, and every dirham modelled must be a reveal fee.
- **The founder's cap:** AED 30/day, `meta_daily_budget_cap_aed`. Dormant while
  `meta_autospend_golive=false` and the token is absent.
- **Workflows owned:** the weekly KPI-integrity sweep, the monthly campaign→goal attribution report
  (its own KPI), the experiment gate, the instrument backlog ranking.
- **Hands to:** `sales_director` (all recommendations — this seat cannot execute), `optimisation_eng`
  (experiment design), `product_eng` (instrument requests), `finance` (spend reconciliation),
  `people_ops` (dark-KPI findings).
- **History it must not forget:** OpenRouter is held, so `ai_cost_log` shows AED 0.00/day in September
  against an August peak of AED 38.00/day — the drop is a policy change, not an efficiency win, and
  must never be reported as one. The marketing department key was retired 10 Aug 2026. The
  reflection-throttle history (`workflow_reflection_steps_per_day`) records a prior instance of exactly
  the error this seat exists to prevent: a per-step cost derived by dividing estate-wide spend by a step
  count, later measured directly at AED 0.146/step instead of AED 0.086.

### 8. One-year plan

**Objective:** make this company's growth numbers *true* — build, or specify and then verify, the
instruments without which no other seat's plan can be judged.

**Slice of AED 1,000,000:** **AED 0 direct.** This seat is advisory with `budget_limit = 0`; giving it a
revenue number would create an incentive to report flattering figures, which is the exact opposite of
its job. Its contribution is measured as *decisions correctly enabled or correctly refused*.

**Metrics owned (3):**
1. **Instrument coverage** — the share of this department's ~230 question types that are answerable
   from a live row. Baseline computed from this document: of the 5 departmental `company_goals`,
   **0 of 5** have a `measure_sql`; of the department's 15 `employee_kpi` rows, **2** have
   `measured_at = null` and **6** read a retired key. Target: **0 dark KPIs, ≥ 3 of 5 goals measurable**.
2. **Campaign attribution coverage** — its existing KPI (id 8, target 100%, actual 100%). This target is
   currently met by a snapshot merely existing; the plan re-specifies it as
   *campaigns with a goal-linked, row-cited performance report* once campaigns exist.
3. **GA4 certification passed** — currently **failed twice at 25% and 35% against an 80% pass mark**.
   Target: **pass**, with the two weakest areas (key events/conversions, attribution) at ≥ 80%.

**Quarterly milestones:**

| quarter | milestone | measurable as |
|---|---|---|
| Q1 | Every dark KPI in the department classed and reported weekly | a standing report; 0 KPIs silently null |
| Q1 | The six KPIs reading `dept_key='marketing'` re-pointed at `growth` | recomputed value matches `review_chain` n=328 |
| Q1 | `target_cpl_aed` obtained from the founder and written | `ad_spend_policy.target_cpl_aed is not null` |
| Q1 | Both stale experiments stopped with a written reason | `experiments.stopped_at is not null` |
| Q2 | Social metrics instrument live; the first real `like_rate` in company history | `social_post_metrics` rows > 0 |
| Q2 | GA4 re-sat and passed | `certification_exam_result.passed = true` |
| Q3 | Web analytics instrument live; `visit_to_rfq_rate` computable | `lead_conversion.measure_sql is not null` |
| Q3 | First measured CPL and CPR from the AED 30/day probe | ≥ 1 `ad_decision` with executed spend and an insight-backed CPL |
| Q4 | `marketing_roi` measurable for the first time | `marketing_roi.measure_sql is not null` |

**Capacity check:** the *analysis* capacity is not the constraint — one seat can compute all of this.
The constraint is that **four of the five instruments it needs do not exist and are `product_eng`
deliverables**, and that with 0 inquiries and 0 published posts there is nothing to analyse. This seat
can reach full value only in the quarter after the instruments land. Until then its honest output is
refusals with named remedies, and that output is worth more than any number it could invent.

**Dependencies:** `product_eng` (all four instruments), `founder` (`target_cpl_aed`, the Meta token,
the go switches), `marketing_social` (publication, so engagement data can exist),
`optimisation_eng` (experiment plumbing), `finance` (spend reconciliation).

### 9. What this seat cannot do without a model

- **Nothing.** Every model in section 2 is closed-form arithmetic or standard statistics: the funnel
  identity, the power calculation, the two-proportion test, the zero classifier, the run-rate
  stationarity test, the break-even cost per reveal. None of them is an inference problem.
- The seat's hardest task — deciding **which** of three identical-looking zeros it is looking at — is
  solved by M-MA-5, a three-branch rule over schema and row-age facts. That is exactly the kind of
  judgement a model would get wrong more often than a rule.
- The one place a model would be *tempting* is writing the narrative around the numbers. That temptation
  is the failure mode, not a capability gap: the memo template plus cited rows produces a better
  document than generated prose, because every sentence in it is falsifiable.

---

## marketing_content — Content Strategy & Copy Specialist

`responsibilities`: *"Owns content pillars and the editorial calendar, briefs copy, aligns output to
demand and SEO."* Absorbed the retired `marketing_copy` seat on 14 August 2026, so it owns the calendar
**and** the words. `authority_level = execute_low`, `budget_limit = 0`. `employee_authority`: the only
seat in the department with **autonomous** `content_calendar`; advisory on `content_draft`,
`content_revise`, `seo_produce`.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| MC-01 | What goes on the editorial calendar next month, in what order? | sequencing | monthly | sales_director | The seat's one autonomous decision; a wrong order publishes into categories with no supply |
| MC-02 | Which content pillar is this piece, and is the pillar under-served? | allocation | per piece | brand_mgr | 32 published posts with no pillar column is a library, not a strategy |
| MC-03 | Which of the 84 categories deserves the next landing page? | sequencing | monthly | marketplace, optimisation_eng | 24 SEO pages exist for 84 categories; the choice is a portfolio decision |
| MC-04 | What is the procurement search intent behind this keyword? | diagnosis | per page | optimisation_eng | `exam:892`: ranking for informational queries brings readers, not RFQs |
| MC-05 | Does this page target RFQ intent or informational intent? | gate | per page | sales_director | Informational traffic does not convert to a reveal and inflates a vanity metric |
| MC-06 | Is this claim substantiated by a live row? | gate | per piece | brand_mgr | Unsubstantiated claims are a UAE advertising exposure |
| MC-07 | Does this piece need an Arabic version? | sequencing | per piece | brand_mgr | UAE B2B procurement reads both; the wrong call loses a whole audience |
| MC-08 | What is the correct title, meta description and heading structure? | craft | per page | optimisation_eng | Structural SEO is deterministic and there is no excuse for getting it wrong |
| MC-09 | Should this piece be refreshed rather than written new? | allocation | monthly | sales_director | Refreshing a ranking page beats a new page that competes with it |
| MC-10 | Do two of our pages compete for the same query? | diagnosis | quarterly | optimisation_eng | Cannibalisation splits authority between our own pages |
| MC-11 | What is the internal link target for this page? | craft | per page | optimisation_eng | Orphan pages carry no authority |
| MC-12 | Which schema markup does this page type need? | craft | per page | product_eng | Structured data is a published standard, not a preference |
| MC-13 | Is this copy in the buyer's voice or the supplier's? | gate | per piece | brand_mgr | Two audiences with opposite anxieties |
| MC-14 | What is the one CTA on this page? | gate | per page | brand_mgr | Rubric HARD check: exactly one |
| MC-15 | Does the RFQ form on this page add friction that filters out real buyers? | diagnosis | quarterly | optimisation_eng | `exam:736`: the form is the conversion gate |
| MC-16 | Is this piece explaining anonymity correctly? | gate | per piece | brand_mgr | Anonymity is the product; a wrong explanation is a product error |
| MC-17 | Does the piece state the 3% fee correctly and completely? | gate | per piece | legal, finance | A misstated fee is a commercial misrepresentation |
| MC-18 | Does the piece state the refund policy correctly (3 / 5 working days, banks 7–14, AED 250 admin fee)? | gate | per piece | legal | The founder's ruling of 6 Sep 2026 is verbatim and final |
| MC-19 | Should this piece be gated behind a form? | allocation | per piece | sales_director | Gating without a nurture path collects addresses nobody uses |
| MC-20 | What is the reading level and sentence length target? | craft | per piece | brand_mgr | Procurement readers skim; measurable, not a taste question |
| MC-21 | Which stored `marketing_library` records support this brief? | craft | per piece | brand_mgr | 317 rows exist; ignoring them re-derives what is already known |
| MC-22 | Is this topic already covered by one of the 32 blog posts? | gate | per brief | sales_director | Duplicate coverage is the cheapest error to avoid and the most common |
| MC-23 | What is the publishing cadence we can actually sustain? | forecast | quarterly | sales_director | Committing to a cadence that halts is worse than a slower one |
| MC-24 | Is a piece stale enough to need a factual refresh? | diagnosis | quarterly | brand_mgr | Fee, licence and category facts change; stale pages become false pages |
| MC-25 | Should we publish a data story from our own numbers? | gate | quarterly | sales_director, legal | Our numbers are 0 inquiries and 0 reveals; publishing them is a strategic disclosure |
| MC-26 | Which content actually produced an inquiry? | diagnosis | monthly | marketing_analyst | **No attribution instrument exists**; the honest answer is a refusal |
| MC-27 | Does this piece need legal review? | escalation | per piece | legal | `legal_triggers` list |
| MC-28 | What is the brief for a designer, in checkable terms? | craft | per asset | marketing_design | A vague brief produces a rubric failure downstream |
| MC-29 | Which supplier-side content would move registrations? | sequencing | monthly | supply | 323 delivered invites produced 0 registrations; content may be the missing half |
| MC-30 | Should the calendar be paused entirely? | allocation | monthly | sales_director | `blog_weekly_mon`, `seo_gen_weekly`, `content_revise_hourly` are all **inactive** already |
| MC-31 | What does "content pillar coverage" mean when the KPI counts published blog posts? | diagnosis | monthly | people_ops | Its own KPI measures 32 against a target of 100 — a count masquerading as a percentage |
| MC-32 | Refuse: "which article performs best?" | escalation | monthly | anyone | No traffic instrument exists |

### 2. Domain logic (the models this seat reasons with)

**M-MC-1 — Editorial calendar allocation (the seat's one autonomous decision).**
```
for each candidate topic t:
  supply_ready(t)   = registered_suppliers(trade(t)) / category_open_min_suppliers (10)     -- capped at 1
  demand_signal(t)  = leads_in_category(t) / max_leads_in_any_category                       -- proxy, see below
  coverage_gap(t)   = 1  if no published blog_post or seo_category covers t, else 0
  refresh_need(t)   = 1  if the covering page cites a fact that has since changed, else 0
  effort(t)         = 1 (short) | 2 (standard) | 3 (long-form or Arabic parity)

  score(t) = (2·coverage_gap + 1·refresh_need) × (0.5 + 0.5·supply_ready) × demand_signal / effort
calendar = top-N by score, N = sustainable_cadence (M-MC-5)
```
Inputs: `blog_posts` (32 published), `seo_categories` (24), `leads` / `lead_category` (17,107 rows) /
`lead_subcategory` (25,438), `v_invite_funnel` (registered, **0 everywhere**), `pricing_config`.
Outputs: an ordered calendar with a cited reason per row.
**UNMEASURED: real demand.** `demand_signal` above uses the **supply-side** lead distribution as a
proxy, because there are 0 inquiries and no search-volume table in this estate. The seat must label
every calendar row with `demand_signal = PROXY (supply-side lead density)`, never as demand.
**Also UNMEASURED: the pillar itself.** `blog_posts` has no pillar column, so `coverage_gap` is computed
by title/slug matching plus embedding similarity against the 24 `seo_categories` — not by a stored
taxonomy. **A content pillar table does not exist.**

**M-MC-2 — Intent classification (deterministic, no model).**
```
intent(query) =
  'RFQ'           when the query matches the procurement lexicon
                  (quote|quotation|rfq|tender|supplier|vendor|price list|rate|bulk|wholesale|
                   contractor|fit-out|supply and install|approved equal|boq)
  'COMMERCIAL'    when it matches (best|top|compare|vs|cost of|price of) + a category term
  'INFORMATIONAL' otherwise
publish_gate    := intent ∈ {RFQ, COMMERCIAL}
```
The lexicon is a stored table, matched by `tsvector` (`marketing_library.tsv` already uses this
mechanism) plus `gte-small` similarity for near-misses. `exam:892` is the stored record behind this
rule: *"ranking for informational [queries]"* brings the wrong reader.
**UNMEASURED: search volume and difficulty.** No keyword table exists in this estate; the seat may
rank *intent* but must never assert *volume*.

**M-MC-3 — Structural SEO checks (all boolean, all computable from the page itself).**
```
exactly one <h1>; heading levels never skip (h1→h2→h3)
title length 30–60 characters; meta description 70–160
title contains the primary term; slug is lowercase-hyphenated and ≤ 75 characters
canonical present and self-referential; hreflang pair present when an ar/en counterpart exists
≥ 2 internal links out, ≥ 1 internal link in (no orphans)
every image has alt text; alt text is not the filename
JSON-LD present and valid for the page type (Article | FAQPage | BreadcrumbList | Organization)
no two published pages share a primary term (cannibalisation check)
```
Inputs: `public.pages` (18), `public.blog_posts` (32), `public.seo_categories` (24),
`route:/[locale]/blog` and `route:/[locale]/blog/[slug]` (registered components).
**The `[locale]` segment in the live routes proves the site is already multi-locale**, which makes the
missing Arabic content a gap in the calendar, not in the platform.

**M-MC-4 — Claim resolution (shared with `brand_mgr`, enforced here at the draft stage).**
Every factual sentence must bind to a row:

| claim type | resolving query | value today |
|---|---|---|
| number of suppliers | `sum(registered) from v_invite_funnel` | **0** |
| number of categories | `count(*) from seo_categories` | 24 (of an 84-category goal) |
| the fee | `pricing_config.standard_reveal_rate` | 3.00% |
| supplier registration cost | `supplier_reg_fee` / `supplier_free_count` | AED 1,000/yr, **first 1,000 free** |
| refund terms | `pricing_config` + `decision_policy.refund_policy_founder_decision_2026_09_06` | chase 3 wd, founder call 5 wd, banks 7–14 wd, AED 250 admin fee, 9% p.a. |
| trade licence | `company_registration` | DET 1633275, valid to 24 Jun 2027 |
| VAT | `company_registration` | not registered; below the AED 375,000 threshold |
| customers / reveals / revenue | `customers`, `transactions` | 1 / **0** / **AED 0** |

An unbound claim is a HARD reject, not a revision request.

**M-MC-5 — Sustainable cadence.**
```
sustainable_cadence = min( editorial_capacity, review_capacity, publishing_capacity )
publishing_capacity = 0 while marketing_golive = false
review_capacity     = f(brand_mgr first-time pass rate = 63.7%)   -- 1 review slot yields 0.637 published
```
Live: `cron:blog_weekly_mon` **inactive**, `cron:seo_gen_weekly` **inactive**,
`cron:content_revise_hourly` **inactive**, `marketing_golive = false`.
**Sustainable cadence today is 0 published items per week**, and the honest calendar is therefore a
*queue*, not a schedule. Saying otherwise would commit the department to a cadence its own switches
forbid.

**M-MC-6 — Readability, measurably.**
```
mean sentence length ≤ 22 words; no sentence > 40 words
paragraphs ≤ 4 sentences; ≥ 1 subheading every 300 words
passive-voice share ≤ 20% of sentences
jargon terms defined on first use, checked against a stored glossary
one CTA (shared HARD check with the rubric)
```
The glossary table **does not exist**; it must be created for the jargon check to run.

### 3. Reasoning procedures

**MC-01 — "What goes on next month's calendar?"**
1. Gather: `blog_posts` (32), `seo_categories` (24), `pages` (18), `lead_category` /
   `lead_subcategory` densities, `v_invite_funnel` registrations (0 across 37 trades).
2. Build the candidate set from the categories in `seo_categories` plus the trades in `v_invite_funnel`
   that have no covering page.
3. Score with M-MC-1. Label `demand_signal` as PROXY on every row.
4. Apply M-MC-5. If `sustainable_cadence = 0`, output a **queue** with the note *"nothing can publish
   while `marketing_golive` is false and `blog_weekly_mon` is inactive"* and recommend to
   `sales_director` that the switch be raised with the founder. Do not schedule dates that cannot happen.
5. Apply J-MC-2: because `supply_ready = 0` in every trade, buyer-facing acquisition content is
   **deprioritised below supplier-recruitment content** for the whole period.
6. Write the calendar with one cited reason per row.

**MC-03 — "Which category gets the next landing page?"**
1. 24 of 84 categories have a page; list the 60 without one.
2. For each, compute lead density (supply proxy) and `registered` (0 everywhere today).
3. Rank by `reachable_suppliers = delivered - bounced` from `v_invite_funnel` as the tiebreak, because
   the binding constraint is supply: `(unclassified)` 37, `Civil & construction works` 20,
   `Cleaning & facility services` 16, `Interior fit-out` 15, `Aluminium & cladding` 15.
4. **Stop condition:** if a candidate's page would claim suppliers exist in that category, refuse the
   candidate — the page would fail M-MC-4 on the supplier-count claim.

**MC-05 / MC-04 — "Is this RFQ intent?"**
1. Tokenise the target query; match against the procurement lexicon (M-MC-2) by `tsvector`, then by
   `gte-small` similarity for near-misses above threshold.
2. Classify. If INFORMATIONAL, **refuse the brief** and return the nearest RFQ-intent variant from the
   lexicon.
3. Never assert volume. State "intent class only; no search-volume instrument exists in this estate."

**MC-06 / MC-17 / MC-18 — "Is every claim in this draft true?"**
1. Extract factual sentences (numbers, named entities, policy statements) by pattern.
2. Bind each to its resolving query from M-MC-4 and execute it.
3. Compare literal values. A mismatch or an unbound claim is a HARD reject with the measured value
   quoted back, so the fix is mechanical.
4. Route to `legal` when the sentence matches `decision_policy.legal_triggers`
   (contract change, liability, indemnity, termination, dispute, refund dispute, regulatory complaint,
   data subject request, subpoena, chargeback).

**MC-22 — "Is this already covered?"**
1. Embed the brief with `gte-small`; retrieve the nearest `blog_posts`, `pages` and `seo_categories`.
2. **Corroborate lexically** — a nearest neighbour is always found, so a similarity score alone is not
   evidence. Require a shared lexeme overlap above threshold before declaring duplicate coverage.
3. If duplicate: recommend a refresh of the existing page (M-MC-1 `refresh_need`), never a second page.

**MC-26 / MC-32 — "Which article performs best / produced an inquiry?"** Refuse:
*"Cannot answer. There is no analytics table in this database and `inquiries` carries no source column.
32 blog posts are published; how many were read is not recorded anywhere. I need a web-sessions
instrument and a first-touch source column on `inquiries`."* Open the org task.

### 4. Judgement rules

| # | condition | verdict | reason |
|---|---|---|---|
| J-MC-1 | Target query classifies INFORMATIONAL | Reject the brief | `exam:892`: informational rankings bring readers, not RFQs |
| J-MC-2 | `registered = 0` in the target trade | Buyer-acquisition content is **deprioritised even when it scores highest** | A buyer who arrives at an empty category is lost for good |
| J-MC-3 | A claim does not bind to a live row | **Reject, not revise** | Unsubstantiated claims are a regulatory exposure |
| J-MC-4 | The draft states a supplier count other than 0 | Reject | The most dangerous number this company could publish today |
| J-MC-5 | The draft states the fee as anything but 3% of quote value | Reject | `pricing_config` is the only source of fee truth |
| J-MC-6 | The draft describes the refund policy | It must match the 6 Sep 2026 ruling exactly, or reject | The founder said "never ask me about it again"; the text is final |
| J-MC-7 | The topic duplicates an existing page on both embedding and lexeme overlap | Refresh, never publish a second | Self-cannibalisation |
| J-MC-8 | Two published pages target the same primary term | Consolidate and redirect | Splits our own authority |
| J-MC-9 | `sustainable_cadence = 0` | Publish a **queue**, never a dated schedule | `marketing_golive=false` and three crons inactive |
| J-MC-10 | A piece would be gated behind a form with no nurture path | Reject | Collecting addresses nobody uses is a liability, not an asset |
| J-MC-11 | A data story would publish our own zero counts | Escalate to `sales_director` and `legal` | Strategic disclosure, not a content decision |
| J-MC-12 | A high-scoring topic requires a claim we cannot substantiate | **Reject even though it scores well** | The score is not a defence |
| J-MC-13 | The piece explains anonymity in a way that implies the buyer is hidden after reveal | Reject | Reveal notifies both parties; a wrong explanation is a product error |
| J-MC-14 | Sentence length, passive share or CTA count outside M-MC-6 bounds | Return for revision (SOFT) | Measurable, so not a taste argument |
| J-MC-15 | An Arabic variant is promised in a campaign but absent | Hold the whole campaign | Partial Arabic reads worse than none |
| J-MC-16 | Asked for content performance | Refuse; name the missing instrument | No analytics table exists |
| J-MC-17 | A stale page cites a fact that has changed | Refresh **before** any new commissioning | A false page costs more than a missing one |
| J-MC-18 | Asked to execute `content_draft` autonomously | Refuse — advisory; only `content_calendar` is autonomous | `employee_authority` |

### 5. Technical knowledge

- **`public.blog_posts`** (32, all published), **`public.pages`** (18), **`public.seo_categories`**
  (24 generated of 24), **`public.content_drafts`** (1 pending, id 36, 11 Aug 2026) and
  `content_drafts_backup_20260724` (30 rows).
- **`public.marketing_library`** — 317 rows, `category`, `domain`, `title`, `content`, `tags`, `tsv`;
  six categories: Regulation/Governance/Marketing-Operations, Strategy/Brand/Content/Localization,
  SEO/Paid-Search/CRO, Social/Influencer/Paid-Social/Video, Analytics/MarTech/Automation/DM,
  Ecommerce/Marketplaces/B2B/LinkedIn. Searched by `fn_marketing_library_search(p_query, p_limit)`.
- **`fn_marketing_blog_publish(p_id, p_published, p_by)`** — the publish routine, and the fact that
  `trigger:blog_posts.trg_blog_dirty` and `trigger:seo_categories.trg_seo_dirty` exist.
- **The pipeline components:** `edge:marketing_draft`, `edge:content_revise`, `edge:blog_weekly`,
  `edge:seo_gen`, `fn_marketing_studio()`, `fn_marketing_ai()`, `fn_ws_marketing()`,
  `fn_emit_content_drafted()`, `fn_emit_campaign_published_from_content()`. **Their crons
  (`blog_weekly_mon`, `seo_gen_weekly`, `content_revise_hourly`, `marketing_ai_daily`) are all
  inactive.**
- **The multi-locale routes** `route:/[locale]/blog` and `route:/[locale]/blog/[slug]`.
- **Structured data**: schema.org `Article`, `FAQPage`, `BreadcrumbList`, `Organization`; `hreflang`
  pairing for ar/en; canonical rules.
- **What must be stored so the seat never asks anyone:** a **content pillar table** (does not exist), a
  **procurement keyword lexicon** (does not exist), a **jargon glossary** (does not exist), a
  **search-volume source** (does not exist), and a `pillar` column on `blog_posts` (does not exist).

### 6. Academic knowledge

| discipline | framework | lawful primary source |
|---|---|---|
| Information retrieval | Query intent taxonomy (navigational / informational / transactional) | Published IR literature and open search-quality guidelines |
| Search standards | Structured data vocabularies | **schema.org** published vocabulary; W3C JSON-LD 1.1 Recommendation |
| Internationalisation | `hreflang`, locale negotiation, RTL text | W3C i18n specifications; Unicode Standard Annex #9 |
| Readability | Sentence-length and passive-voice measures | Public plain-language standards (e.g. published government plain-English guidance) |
| Marketing communications | Message hierarchy, audience segmentation | CIM Level 6 published syllabus outline |
| Advertising regulation | Substantiation of claims | UAE Media Council published advertising regulations |
| Procurement vocabulary | Scope, BOQ, approved-equal, prequalification | CIPS published syllabus; the estate's own `brand_acceptance_policy_value` enum |

**Certifications held:** rank 1 **CIM Level 6 Diploma in Professional Marketing** (pass mark 50%);
rank 2 **CDMP-DMI** (pass mark 60%).
**Exams sat: none.** `certification_exam_result` holds 0 rows for `marketing_content`.
**Stored knowledge:** 12 `agent_knowledge` rows — the `profession`-layer record *"Content and SEO for
UAE B2B procurement buyers"* (priority 74) plus `exam:1126` (time-to-first-quote as the liquidity metric
buyers feel), `exam:1127` (reveal-fee pricing experiments), `exam:1128` (peeking and p-hacking),
`exam:882` (reveal-fee unit economics), `exam:883` (partnership channels: associations, chambers),
`exam:884` (LTV in a reveal-fee model), `exam:1447` (the marketing department manifest).

### 7. Corporate knowledge

- **Anonymity is the product.** Every explanatory piece must describe the flow correctly: post an RFQ
  anonymously → verified UAE suppliers quote → the buyer compares → the buyer pays the 3% reveal fee →
  **both parties are notified** at the reveal. The last clause is a founder ruling and is the one most
  often written wrongly.
- **The fee facts:** 3% standard **and** promo (no differential exists), supplier registration
  AED 1,000/year with the first 1,000 free, category opens at 10 confirmed suppliers.
- **The refund ruling of 6 Sep 2026**, verbatim in `decision_policy`, including the AED 250 admin fee
  charged to the supplier, the refunded 3%, 9% **per annum** interest, chase at 3 working days, the
  founder's call on day 5, bank settlement 7–14 working days.
- **Licence and tax, closed:** DET licence 1633275 (expires 24 Jun 2027); not VAT-registered, below the
  AED 375,000 threshold. Never to be re-asked; rendered into `ops_knowledge` by
  `fn_company_self_knowledge_sync()`.
- **Workflows owned:** the editorial calendar (autonomous), the brief-to-designer handoff, the SEO page
  specification, the refresh audit.
- **Hands to:** `marketing_design` (briefs), `brand_mgr` (review), `marketing_social` (distribution),
  `optimisation_eng` (page conversion), `legal` (regulated claims), `sales_director` (approval).
- **History it must not forget:** its own KPI *"Content pillar coverage"* is defined as
  `select count(*) from blog_posts where published` with a target of **100** and a unit of **percent** —
  a raw count reported as a percentage. It reads **32**. The KPI is mis-specified and the seat must say
  so rather than chase 100 blog posts. The `marketing_copy` seat was folded in on 14 Aug 2026 and its
  rule — *"must cite the brand guideline it followed on every draft"* — came with it.

### 8. One-year plan

**Objective:** turn 32 undifferentiated blog posts and 24 auto-generated category pages into a
**procurement-intent content system** whose every page can be traced to a category, an intent class and
a substantiated claim set — and which can publish the moment `marketing_golive` is raised.

**Slice of AED 1,000,000:** content's contribution is organic RFQ volume, and **it cannot be quantified
today**: there is no traffic instrument, no attribution, and 0 inquiries. The honest slice is stated as
a *conditional*: if a category page converts visitors to RFQs at the departmental goal rate
(`lead_conversion` target 5%) and the reveal chain holds, then at the AED 50,000-quote anchor each
reveal is worth AED 1,500 and **667 reveals carry the whole company target**. What share of those come
from content is unknowable until attribution exists. Claiming a percentage now would be an invention.

**Metrics owned (3):**
1. **RFQ-intent page coverage** — categories with a published page whose target query classifies RFQ or
   COMMERCIAL. Baseline **24 pages of 84 categories = 28.6%**, intent class **unclassified** (the
   lexicon does not exist). Target: **60 of 84 with a classified RFQ/COMMERCIAL target**.
2. **Claim integrity** — the share of published pieces where every factual sentence binds to a live
   row. Baseline **not computable** (no claim index exists). Target: **100%, computed weekly**.
3. **Content pillar coverage** — its existing KPI (id 5), re-specified from "count of published blog
   posts" to "pillars with ≥ 1 live page", which requires the pillar table that does not exist.

**Quarterly milestones:**

| quarter | milestone | measurable as |
|---|---|---|
| Q1 | Content pillar table created; all 32 posts and 24 SEO pages labelled | `count(*) where pillar is null = 0` |
| Q1 | Procurement keyword lexicon table created and every page's target query classified | 74 pages classified |
| Q1 | Claim index built; every published page's claims bound and verified against live rows | 0 unbound claims |
| Q2 | The 5 highest-`reachable` trades each get an RFQ-intent landing page | `seo_categories` 24 → 29 |
| Q2 | Refresh audit: every page citing a changed fact corrected | 0 stale facts |
| Q3 | Arabic parity for the top 10 pages (`hreflang` pairs live) | 10 `ar` pages |
| Q3 | Cadence resumes when `marketing_golive` is raised; `blog_weekly_mon` reactivated | cron active, ≥ 4 publishes/month |
| Q4 | 60 of 84 categories covered with classified intent | `seo_categories` + `pages` |

**Capacity check:** the *writing* is not the constraint. Two hard limits bind first:
**(1)** `marketing_golive = false` and three of the pipeline's four crons are inactive, so
**sustainable cadence is literally 0** — the plan above is a queue until the founder raises the switch;
**(2)** three of the seat's own instruments (pillar table, keyword lexicon, glossary) do not exist and
must be built before the scoring model can run unattended. Given both, the Q1 milestones are
*data-modelling* work, not writing, and that is the correct sequence.

**Dependencies:** `founder` (`marketing_golive`), `product_eng` (pillar table, lexicon, glossary,
cron reactivation, analytics instrument), `brand_mgr` (review), `marketing_design` (assets),
`supply` (whether any trade will have suppliers to write about), `legal` (regulated claims).

### 9. What this seat cannot do without a model

- **Intent classification, structural SEO, claim binding, duplicate detection, calendar scoring and
  readability are all deterministic** — lexicon matching, boolean checks, row lookups, arithmetic, and
  `gte-small` retrieval corroborated by lexeme overlap.
- **Genuinely original long-form prose cannot be generated deterministically.** This is the one real
  gap in this department and it is stated plainly. What a coded seat *can* do without a model:
  assemble a piece from stored, approved components — a template skeleton, cited `marketing_library`
  passages (317 rows), computed live values, and the approved CTA — then verify every claim. That
  produces a correct, publishable, and rather dry page. It does not produce a new argument or a fresh
  turn of phrase. **The founder's constraint therefore implies a house style built from templates and
  citations, and this plan accepts that consequence rather than hiding it.**
- The honest boundary: for a *new* category page with a known structure, the templated path is
  sufficient. For a piece whose purpose is persuasion in a voice we have not written before, it is not,
  and the seat should say so and hand the brief to a human rather than call a model.

---

## marketing_design — Visual Design Specialist

`responsibilities`: *"Produces creatives from brand_assets, enforces logo, colour and typography rules."*
`authority_level = advisory`, `budget_limit = 1,000`. Uniquely in this department its
`employee_authority.content_draft` is **autonomous** with the note *"Must cite the brand asset used."*
It is the only seat that may produce without asking — provided it cites.

Where `brand_mgr` **judges** the rubric, this seat **constructs assets that cannot fail it**: it emits
the manifest that makes every check computable, rather than making something and hoping.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| MD-01 | Which canvas does this surface need? | craft | per asset | marketing_social | Wrong canvas = crop, rejection at upload, or a cut-off mark |
| MD-02 | Which of the 58 brand assets is the correct source file here? | craft | per asset | brand_mgr | Each file has one stated `usage`; the wrong one is an instant rubric failure |
| MD-03 | Which colour pair goes on this element, and what is its measured contrast? | gate | per element | brand_mgr | Teal on white is 2.5:1; picking it for body text fails WCAG AA |
| MD-04 | Where do text and logo sit so they survive the platform's safe zone? | gate | per asset | brand_mgr | Story UI eats the top 250 px and bottom 340 px of a 1080×1920 frame |
| MD-05 | What is the hook frame, and is it legible by 1.5 s? | gate | per video | marketing_social | Feed autoplay decides before two seconds |
| MD-06 | Where is the single CTA, and is there exactly one? | gate | per asset | brand_mgr | Rubric HARD check |
| MD-07 | How does this asset mirror to Arabic RTL? | craft | per Arabic asset | brand_mgr | Mirroring the wrong elements (numerals, Latin brand name) is worse than not mirroring |
| MD-08 | Which type sizes keep the copy legible at feed scale? | gate | per asset | brand_mgr | 1080-wide art is read at ~400 px on a phone |
| MD-09 | Does this asset emit a complete manifest? | gate | per asset | brand_mgr | Without a manifest the rubric cannot be run at all and the asset must be refused |
| MD-10 | Is the mark's clear space and minimum size respected? | gate | per asset | brand_mgr | `logo.clear_space`, `logo.min_size` |
| MD-11 | Which gradient applies — teal, gold or navy? | craft | per asset | brand_mgr | Three gradients exist and `imagery.style` forbids any fourth |
| MD-12 | Should this be a new template or an instance of an existing one? | allocation | per asset | brand_mgr | Template proliferation is how a system decays |
| MD-13 | Is the source asset's `sha256` still the approved one? | diagnosis | per asset | brand_mgr | Silent drift from `logo.master` |
| MD-14 | Which icon/avatar size is missing from the kit? | diagnosis | quarterly | product_eng | Incomplete sets show as generic icons |
| MD-15 | Does the document template (PDF/email) follow `imagery.documents`? | gate | per template | finance, product_eng | Customer-facing PDFs are the brand more often than social is |
| MD-16 | Is the image real UAE trade context or stock? | gate | per asset | brand_mgr | `imagery.style` names the forbidden clichés |
| MD-17 | What file format and weight does this platform accept? | craft | per asset | marketing_social | A rejected upload is an invisible failure |
| MD-18 | Does a dark-mode or on-photograph variant exist where needed? | craft | per asset | product_eng | `mark_white` exists precisely for this |
| MD-19 | Which asset variant does a supplier-facing message need vs a buyer-facing one? | craft | per campaign | marketing_content | Two audiences with opposite anxieties |
| MD-20 | How many creative variants should a test carry? | allocation | per test | optimisation_eng | More arms need more traffic; there is currently none |
| MD-21 | Should an asset be regenerated or retouched? | allocation | per revision | brand_mgr | Regenerating loses approved history |
| MD-22 | Is the alt text meaningful and not the filename? | gate | per asset | marketing_content | Accessibility and SEO, both checkable |
| MD-23 | Does the asset embed any text that will be translated later? | sequencing | per asset | marketing_content | Baked-in text blocks localisation |
| MD-24 | Which template does `edge:marketing_image` use for this post? | craft | per post | marketing_social | The in-house card spec is stored and specific |
| MD-25 | Is the business card / print artwork at 300 DPI with bleed? | gate | quarterly | ops | `size.icons` names 1125×675 at 300 DPI with bleed |
| MD-26 | Are the trademark filing artworks (colour and black-and-white) current? | gate | annually | legal | Filings want both; `logo.variants` says so |
| MD-27 | What is the asset's expected lifetime before refresh? | forecast | quarterly | brand_mgr | Assets citing changed facts become false assets |
| MD-28 | Refuse: "make it pop" / "which of these looks better?" | escalation | ad hoc | anyone | Not decidable by rule and there is no performance data to decide it by |

### 2. Domain logic (the models this seat reasons with)

**M-MD-1 — The asset manifest (the artefact that makes every rubric check computable).**
Every produced asset emits a manifest alongside the file. Without it, `brand_mgr` must refuse
(BM-01 step 9). Shape:
```
{ asset_id, sha256, locale: 'en'|'ar', surface, canvas: {w,h},
  source_assets: [brand_assets.id, ...],            -- the "must cite the brand asset used" rule
  template_id,
  colour_pairs: [ {role, fg_hex, bg_hex, text_px, bold} ... ],
  boxes:        [ {kind: 'text'|'logo'|'cta', x, y, w, h} ... ],
  cta_elements: [ {text, kind: 'button'|'link'} ... ],
  timing:       [ {t_ms, event: 'first_legible_word'|'brand_mark'|'cta'} ... ],   -- moving assets
  alt_text, cited_rules: ['company_brand.logo.lockup', ...] }
```
**This structure does not exist in the estate today.** `brand_assets` has `kind, platform, filename,
url, bucket, path, folder, bytes, sha256, width, height, usage` — no colour pairs, no boxes, no
`locale`, no timing. Creating it is this seat's single highest-leverage deliverable, because it converts
four of `brand_mgr`'s nine HARD checks from "not executable" to "executable".

**M-MD-2 — Contrast, at production time.** Same WCAG formula as M-BM-1, but used *forwards*: given a
background, the palette of permitted foregrounds is a stored lookup, not a computation.
```
permitted_fg(bg = navy #0C2330, body text)  = { paper #EAF4F2 (14.4), white (16.2),
                                                teal-light #6EE7D4 (10.8), gold #E3C065 (9.2),
                                                muted #9DB2B2 (7.3), teal #14B8A6 (6.5) }
permitted_fg(bg = white,        body text)  = { navy #0C2330 (16.2), ink #0A0A0A (19.8),
                                                teal-deep #0B8276 (4.7) }
permitted_fg(bg = white,        large ≥24px)= above ∪ { gold-deep #BD8E36 (3.0) }
forbidden always                            = { white on teal (2.5), teal on white body (2.5),
                                                gold on white (1.8) }
```
So the designer never *chooses and then checks* — it selects from a set that cannot fail. Buttons are
fully specified by `company_brand.contrast.buttons`: primary = teal fill + **navy** label (6.5:1),
focus = 2 px teal-light ring, disabled = 40% opacity, destructive = gold-deep fill + navy label.

**M-MD-3 — Layout geometry against safe zones.** The margins of M-BM-2, applied as a constraint on the
layout solver rather than as a test:
```
content_box(surface) = (margin_x, margin_top, W - 2·margin_x, H - margin_top - margin_bottom)
place every text/logo/CTA box inside content_box(surface)
logo clear space     ≥ q_ring_height on all four sides        (company_brand.logo.clear_space)
logo min size        ≥ 24 px screen / 8 mm print; lockup ≥ 120 px wide / 30 mm
```
Worked for the two surfaces that matter most:
*Story/Reel 1080×1920* → content box `(60, 250, 960, 1330)`.
*Instagram square 1080×1080* → content box `(64, 64, 952, 952)`.
**The reserved margins are not stored in `company_brand`** — only the YouTube safe area (1546×423) is.
This seat must specify the other six and have them written.

**M-MD-4 — Legibility at delivered scale.**
```
delivered_scale   = typical_display_width_px / canvas_width_px      (phone feed ≈ 400/1080 ≈ 0.37)
effective_px      = type_size_px × delivered_scale
constraint        : effective_px ≥ 11  ⇒  type_size_px ≥ 30 on a 1080-wide canvas
headline          : ≥ 64 px on 1080 (effective ≈ 24)
body/eyebrow      : ≥ 36 px on 1080 (effective ≈ 13)
legal/footer      : ≥ 30 px on 1080 (effective ≈ 11) — the floor, never below
```
**UNMEASURED: our own audience's device mix.** No analytics table exists, so `delivered_scale` uses the
stated phone-feed assumption and must be labelled as an assumption, not a measurement.

**M-MD-5 — Motion timing (moving assets).**
```
t_first_legible_word ≤ 1500 ms      -- HARD
t_brand_mark         ≤ 3000 ms
t_cta                ≥ t_first_legible_word,  and CTA on screen ≥ 2000 ms
sound_off_legible    = true         -- captions burned in, inside the safe zone
```
The manifest's `timing` array is what makes these checkable. **No video asset and no timing manifest
exists in the estate today**; the rule is written before the first video, deliberately.

**M-MD-6 — Arabic derivation (mechanical mirroring).** Given an approved English layout, the Arabic
variant is *derived*, not redesigned:
```
for every box b:            b_ar.x = W - (b.x + b.w)          -- horizontal mirror
text_direction              = 'rtl';  reading order right→left
the 14 px teal-to-gold rule moves from the left edge to the right edge   (imagery.social)
the mark moves from top-left to top-right
DO NOT MIRROR:  numerals, AED amounts, phone numbers, URLs, the Latin string "QuotesDone",
                photographic content containing text or handedness
font must support Arabic shaping; line height +15% over the Latin setting
parity rule:    every campaign is en+ar or en-only, never a partial set
```
**UNMEASURED / MISSING:** `brand_assets` has no `locale` column, `company_brand` has no Arabic
typography rule, and there is **not one Arabic asset in the kit**. The mechanism is fully specified
above and can run the day those three exist.

**M-MD-7 — Drift detection.**
```
drift := brand_assets.sha256 ≠ the approved sha256 for that path
```
`brand_assets` already stores `sha256` per file (e.g. the Universal master
`11050f84…ac0041`, 1000×1000, 164,354 bytes). `fn_brand_scan()` and `table:brand_signal` are registered
components — **`brand_signal` is empty**, so drift detection has never produced a signal. Note the
kit's own honest quirk: `avatar_LinkedIn_400x400.png` and `avatar_X_Twitter_400x400.png` share the
identical sha256 `6b2391cb…688650`, i.e. they are the same file under two names. That is correct (same
square for every platform, per `size.avatars`) and the drift rule must not flag it.

### 3. Reasoning procedures

**MD-01 → MD-09 — "Produce an asset" (the whole production procedure).**
1. Read the brief from `marketing_content`; read the surface and locale.
2. Look up the canvas in `company_brand.size.*`; compute the content box (M-MD-3).
3. Select the source files from `brand_assets` by `kind` + `platform` and record their ids and
   `sha256` — this satisfies the standing authority note *"Must cite the brand asset used."*
4. Choose the ground (navy gradient per `gradient.navy`), then select **only** from
   `permitted_fg(ground, size_class)` (M-MD-2). A failing pair is unreachable by construction.
5. Place boxes inside the content box; enforce clear space and minimum sizes; set type at or above the
   M-MD-4 floors.
6. Place exactly one CTA from the approved lexicon (**which does not exist yet** — until it does, the
   CTA text comes from the brief and the brief must name it).
7. If `locale='ar'`, derive by M-MD-6 from the approved English layout; never lay out Arabic from
   scratch.
8. Emit the manifest (M-MD-1) with every colour pair, box, CTA element, cited rule and, for motion, the
   timing array.
9. Submit to `brand_mgr`. **Stop condition:** if any required manifest field cannot be produced
   (no timing for a video, no `locale` column to record the variant), do not submit — report the
   blocker instead. An unverifiable asset is worse than a late one.

**MD-07 — "Mirror this to Arabic."**
1. Require an approved English original in the same campaign; refuse without one.
2. Apply M-MD-6 box by box, emitting both coordinates so the reviewer can check `b_ar.x = W - (b.x+b.w)`
   to ±2 px.
3. Enumerate the non-mirrored elements explicitly in the manifest so the check is positive, not an
   absence.
4. Assert the parity rule at campaign level; if any English asset lacks an Arabic sibling, flag the
   **campaign**, not the asset.

**MD-13 — "Has the kit drifted?"**
1. Recompute `sha256` for every row of `brand_assets` against the stored value.
2. Exclude the legitimate duplicate pair noted in M-MD-7.
3. Any mismatch on a `07_Trademark_and_License` path is an immediate escalation to `brand_mgr` and
   `legal` — that folder holds the founder-approved master.
4. Write findings to `brand_signal` (**currently empty**).

**MD-20 — "How many creative variants for this test?"**
1. Ask `marketing_analyst` for the required n per arm (M-MA-4).
2. Divide the available exposures by the arm count. With `experiment_events = 0` and nothing published,
   available exposures are **0**, so the answer is: **one asset, no test**, until traffic exists.
3. Refuse to build variants for a test that cannot reach power.

**MD-28 — "Which looks better?"** Refuse. Compose: *"Both pass every HARD check. Choosing between
compliant options requires performance data; this estate has 10 posts, 0 published, and no engagement
column. I can rank them on nothing but preference, which is not a design decision I should make for the
company."* Escalate the *instrument*, not the choice.

### 4. Judgement rules

| # | condition | verdict | reason |
|---|---|---|---|
| J-MD-1 | The asset cannot emit a complete manifest | **Do not submit** | An unverifiable asset cannot be reviewed, only argued over |
| J-MD-2 | A colour pair is not in `permitted_fg` for its size class | Do not use it | Failure is designed out, not tested out |
| J-MD-3 | White label on a teal button | Never | 2.5:1; `contrast.buttons` forbids it explicitly |
| J-MD-4 | Any box crosses the safe zone | Re-place; never "it will probably be fine" | Story UI is not negotiable |
| J-MD-5 | Type below 30 px on a 1080-wide canvas | Reject own work | Effective size falls under 11 px at feed scale |
| J-MD-6 | Video with no legible word by 1.5 s | Rebuild the opening | The hook check is HARD |
| J-MD-7 | CTA count ≠ 1 | Rebuild | HARD check |
| J-MD-8 | Arabic laid out from scratch rather than derived | Reject own work | Derivation is what makes mirroring checkable |
| J-MD-9 | Numerals, AED figures or "QuotesDone" mirrored | Reject | Mirroring the wrong things is worse than not mirroring |
| J-MD-10 | A brief asks for a new layout that an existing template covers | **Refuse even when the new one is better** | One excellent one-off costs more in system decay than it earns |
| J-MD-11 | The mark would be recoloured, stretched, rotated, outlined or shadowed | Refuse, no negotiation | `logo.dont`; founder-approved artwork |
| J-MD-12 | A fourth gradient is proposed | Refuse | `imagery.style`: no gradients outside the three |
| J-MD-13 | Stock photography, handshakes or blue corporate clip art | Refuse | `imagery.style` names them |
| J-MD-14 | `sha256` mismatch inside `07_Trademark_and_License` | Escalate immediately to `brand_mgr` + `legal` | That folder is the approved master |
| J-MD-15 | Alt text equals the filename or is absent | Fix before submit | Accessibility and SEO, both checkable |
| J-MD-16 | Text is baked into an image that will be localised | Re-do with text as a layer | Baked text blocks every future locale |
| J-MD-17 | Asked to choose between compliant options on taste | Refuse; escalate the missing instrument | No performance data exists |
| J-MD-18 | Producing variants for an underpowered test | Refuse | Building for a test that cannot conclude is pure waste |

### 5. Technical knowledge

- **`public.brand_assets`** — 58 files across eight kit folders: `01_Social_Avatars` (10 platform
  avatars + a 1000×1000 Universal master), `02_Social_Covers`, `03_Social_Post_Templates`,
  `04_Web_App_Icons`, `05_Logo_Lockups` (OnLight, OnDark, Black_Mono, on_white, on_navy, mark_only,
  mark_white), `06_Print_Business_Card`, `07_Trademark_and_License`, `08_Vector_Source`. Every row
  carries `sha256`, `width`, `height`, `bytes` and a stated `usage`.
- **`public.company_brand`** — the 53 rules, especially `size.avatars` (LinkedIn 400 · Instagram 320 ·
  Facebook 500 · X 400 · YouTube 800 · WhatsApp 640 · TikTok 200 · Threads 400 · Pinterest 280 ·
  Google Business 250; master 1000), `size.posts`, `size.covers`, `size.icons` (favicon 16/32/48/64 +
  .ico, Apple touch 180, PWA 192 and maskable 512, store 1024, business card 1125×675 @300 DPI with
  bleed), `logo.mark` (the exact SVG geometry), `gradient.*`, `contrast.*`, `imagery.social`
  (1080×1080 navy gradient, 14 px teal-to-gold rule on the left, mark top-left, Poppins Bold headline,
  teal-light eyebrow, footer), `imagery.documents`.
- **WCAG 2.1 contrast arithmetic** — computed, because a new colour will appear.
- **RTL derivation mechanics** — mirroring, shaping, non-mirrored classes, line-height adjustment.
- **`edge:marketing_image`** and `edge:brand_upload` — the production and ingestion functions;
  `fn_brand_scan()`; `table:brand_signal` (**empty**);
  `evsub:marketing_design@content.drafted` (the event that wakes this seat).
- **Formats:** PNG/JPEG/WebP for static, MP4 H.264 for motion, SVG for source; sRGB throughout; 300 DPI
  with bleed for print.
- **What must be stored so the seat never asks anyone:** the **manifest schema** (M-MD-1), the
  **reserved-margin table**, the **approved CTA lexicon**, `brand_assets.locale`, the **Arabic
  typography rule**, and a **timing manifest format**. **All six do not exist today.**

### 6. Academic knowledge

| discipline | framework | lawful primary source |
|---|---|---|
| Accessibility | WCAG 2.1/2.2 SC 1.4.3, 1.4.6, 1.4.11, 1.4.12 | W3C Recommendation |
| Colour science | sRGB EOTF, relative luminance, gamut | IEC 61966-2-1 as published; W3C definitions |
| Typography | Optical sizing, x-height and legibility at distance | Public foundry specimens; W3C text guidance |
| Internationalisation | Unicode Bidi Algorithm; CSS Logical Properties; Arabic shaping | UAX #9 (public); W3C CSS Logical Properties |
| Layout | Modular scale, grid systems, safe-area insets | W3C CSS Environment Variables; published platform specs |
| Image and video encoding | Colour subsampling, bitrate/quality, container limits | ITU-T H.264 published spec; W3C media guidance |
| Print | Bleed, trim, 300 DPI, CMYK conversion | ISO 12647 as published |

**Certification held:** rank 1 **Adobe Certified Professional in Visual Design** (Adobe, pass mark
**70%**) — syllabus: Working in the Design Industry · Project Setup and Interface · Organizing Documents
· Creating and Modifying Visual Elements · Publishing Digital Media · Typography and Colour.
**Exams sat: none** (0 rows). No failed syllabus area exists to report.
**Stored knowledge:** 9 `agent_knowledge` rows — the `profession`-layer record *"Design for a two-sided
B2B marketplace"* (priority 74, *"two audiences with opposite anxieties: buyers fear being chased and
overcharged, suppliers fear wasting time"*), plus `exam:1132` (seeding supply that will not quote),
`exam:1133` (payback period), `exam:887` (budget allocation by reveal-payback ranking),
`exam:888` (demand and supply must scale in lockstep), `exam:889` (cross-category expansion).

### 7. Corporate knowledge

- **The one immutable thing:** `logo.master` —
  `kit/07_Trademark_and_License/ORIGINAL_approved_master_800.png`, founder-approved, *"Nothing about the
  logo changes without him; everything else in the kit may be upgraded."*
- **Its own KPI is inverted from every other seat's:** *"Creative rejected at review"*, unit
  `percent_max`, target **≤ 10%**, actual **6.25%** — computed as
  `count(decision<>'approve') / count(*)` over `review_chain where dept_key='marketing'`, i.e. from the
  same **16-row, retired-key** window as everything else (§0.6.2). Under the live key `growth` the
  department's non-approve share is **119/328 = 36.3%**. The seat must report both and treat 6.25% as
  an artefact.
- **The design authority note:** `content_draft` is autonomous **only** because of the citation
  requirement. Producing without citing a `brand_assets` row voids the autonomy.
- **The brand square derivation:** every avatar and app icon derives from
  `kit/07_Trademark_and_License/BRAND_SQUARE_color_2000.png` — navy gradient, gold hairline frame, mark
  centred, "QUOTES DONE" beneath.
- **Hands to:** `brand_mgr` (review), `marketing_social` (publishing), `marketing_content` (briefs),
  `product_eng` (icons, document templates, the manifest schema), `legal` (trademark artwork).
- **History it must not forget:** the ten staged posts used just four distinct images
  (`x7LqW3Ok2v.png` appears on three of them); one post is a self-test carrying
  `media_missing = "no media designed yet"`. Four of the ten no longer resolve in Postiz at all. Nothing
  in the kit is Arabic.

### 8. One-year plan

**Objective:** make every asset **verifiable by construction** — a manifest, cited sources, a palette
that cannot fail contrast, a layout that cannot cross a safe zone, and an Arabic variant that is
derived rather than redrawn.

**Slice of AED 1,000,000:** **AED 0 direct.** Design is a production seat with `advisory` authority; its
contribution is throughput and compliance, not revenue. Assigning it a revenue number would push it
toward volume over correctness, which is precisely the wrong incentive for the seat that owns the
company's only visual identity.

**Metrics owned (2):**
1. **Manifest completeness** — the share of produced assets emitting a complete M-MD-1 manifest.
   Baseline **0%** (the schema does not exist). Target **100%**.
2. **First-time PASS at brand review**, the mirror of its own KPI, recomputed on `dept_key='growth'`.
   Baseline **63.7% (n=328)** departmental; the seat's stored 93.75% pass / 6.25% reject figure comes
   from n=16 under a retired key. Target: **≥ 90% on the live key, at n ≥ 50/month**.

**Quarterly milestones:**

| quarter | milestone | measurable as |
|---|---|---|
| Q1 | Manifest schema defined and emitted by `edge:marketing_image` | ≥ 1 asset with a complete manifest |
| Q1 | Reserved-margin table written for all 7 surfaces | rows exist |
| Q1 | `brand_assets.locale` added; all 58 assets labelled | `count(*) where locale is null = 0` |
| Q2 | `permitted_fg` palette stored so contrast cannot be chosen wrongly | a table, not a habit |
| Q2 | First Arabic asset derived by M-MD-6 and passed | ≥ 1 asset `locale='ar'` PASS |
| Q3 | Timing manifest format defined; first motion asset produced and passed | ≥ 1 video with timing |
| Q3 | `fn_brand_scan()` writes its first drift signals | `brand_signal` rows > 0 |
| Q4 | Every published asset in the estate has a manifest and a citation | 0 unmanifested published assets |

**Capacity check:** production capacity is not the constraint — the constraint is that
**nothing is being published** (`marketing_golive = false`, `social_stage_hourly` inactive), so the
seat's output currently has nowhere to go, and that **six of its own instruments do not exist**. The
Q1–Q2 milestones are therefore schema and data work, not artwork, which is the honest sequence. A
design seat producing assets into a switched-off pipeline is the department's clearest example of
effort that cannot become revenue.

**Dependencies:** `product_eng` (manifest schema, `locale` column, margin table, CTA lexicon table),
`brand_mgr` (rubric and rule authorship), `marketing_content` (briefs), `marketing_social` (the
publishing switch), `founder` (`marketing_golive`).

### 9. What this seat cannot do without a model

- **Every check and every derivation above is deterministic**: palette selection from a stored
  permitted set, box arithmetic against stored margins, type-size floors, mechanical RTL mirroring,
  `sha256` comparison, manifest emission.
- **Generating a genuinely new visual concept is not deterministic**, and this is stated plainly rather
  than dressed up. Without a model the seat can: instantiate an approved template with new copy and a
  new approved photograph; derive an Arabic variant; produce every size in a set from one master;
  regenerate the icon and avatar family from the brand square; and refuse anything outside that. It
  cannot invent a new layout language. **The founder's constraint therefore implies a
  template-instantiation design system, and this plan accepts that consequence.** Given the kit already
  contains `03_Social_Post_Templates` and a fully specified card format in `imagery.social`, the
  template path covers the whole of the coming year's known needs.
- **Judging arbitrary uploaded imagery** (is this stock? is this a handshake photo?) would need vision.
  The deterministic answer is to require assets to come from `brand_assets` with a stated `usage`, which
  the estate already supports — so the requirement removes the need rather than papering over it.

---

## marketing_social — Social Media & Community Manager

`responsibilities`: *"Owns the channel calendar, drafts and schedules posts, monitors engagement,
escalates brand-risk content to the Director."* `authority_level = execute_low`, `budget_limit = 1,000`.
`employee_authority`: **autonomous** on `content_draft` with the note *"May draft and schedule; may not
publish"*, and **advisory** on `content_publish` with the note *"Must submit to the Marketing Director"*
— a role that was parked on 3 Sep 2026, so publication approval now sits with `sales_director`.

**The defining fact for this seat:** it is charged with monitoring engagement on an account that has
**10 posts, 0 of them published, and no engagement column of any kind**.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| MS-01 | What is on the channel calendar this week, by channel and slot? | sequencing | weekly | sales_director | Publishing a buyer post into a category with no suppliers wastes the only reach we have |
| MS-02 | Which of the four channels does this post belong on? | allocation | per post | marketing_content | LinkedIn and WhatsApp are the UAE B2B channels; consumer channels are decoration |
| MS-03 | What time and day should this post go out? | sequencing | per post | marketing_content | The audience is at work Sunday–Thursday; a Friday-evening post reaches nobody |
| MS-04 | How many likes / views / impressions should this post get? | forecast | per post | marketing_analyst | Without a stated expectation the whole programme is unfalsifiable |
| MS-05 | Did this post meet its expectation? | diagnosis | per post | sales_director | **No engagement instrument exists**; any answer today is invented |
| MS-06 | What is our engagement rate this month? | diagnosis | monthly | sales_director, founder | Its own KPI, target 3%, `actual_value = null`, `measured_at = null` |
| MS-07 | Did we meet publishing cadence? | diagnosis | weekly | people_ops | Its own KPI reads `status='published'` — a status this estate has **never written** |
| MS-08 | Should this post be boosted, and at what daily budget? | allocation | weekly | sales_director | The AED 30/day cap and the AED 20 per-campaign floor bound the whole answer |
| MS-09 | Is this comment or DM a lead, a complaint, or noise? | diagnosis | daily (when live) | customer_experience | Misrouting a complaint into the marketing queue loses a customer |
| MS-10 | Does this inbound need `legal`? | escalation | ad hoc | legal | `legal_triggers` list |
| MS-11 | Should we respond publicly or privately? | craft | ad hoc | brand_mgr | Public responses become permanent brand artefacts |
| MS-12 | Is this content brand-risk and must it be escalated before it goes out? | escalation | per post | brand_mgr, sales_director | The seat's stated escalation duty |
| MS-13 | What is the correct caption length and hashtag count for this network? | craft | per post | marketing_content | Network-specific and measurable, not a taste question |
| MS-14 | Which post is a supplier-recruitment post and which is buyer-acquisition? | allocation | per post | supply, sales_director | With 0 registered suppliers the split should be heavily supply-weighted |
| MS-15 | Does WhatsApp carry this message, and under which approved template? | gate | per send | customer_experience, legal | WhatsApp is rule-bound; an unapproved template is a policy breach |
| MS-16 | Is a scheduled post still factually correct at publish time? | gate | per post | marketing_content | Fees, licence and counts change between drafting and publishing |
| MS-17 | Has a scheduled post silently failed to publish? | diagnosis | daily | product_eng | Five of ten posts sit in Postiz as drafts and nobody was told |
| MS-18 | Are the Postiz integration ids still valid? | diagnosis | weekly | product_eng | Four posts' ids no longer resolve in Postiz at all |
| MS-19 | Which post should be pinned or reused? | allocation | monthly | brand_mgr | Without performance data this cannot be ranked |
| MS-20 | Should the account post at all while `marketing_golive = false`? | gate | weekly | sales_director | Publishing against a false switch is a governance breach |
| MS-21 | What cadence can we sustain across four channels? | forecast | monthly | sales_director | Over-committing produces gaps that read as abandonment |
| MS-22 | Is this hashtag set relevant or decorative? | craft | per post | marketing_content | UAE B2B hashtags are few and specific |
| MS-23 | Does the post need an Arabic variant? | sequencing | per post | brand_mgr | Parity is all-or-nothing per campaign |
| MS-24 | Which community (association, chamber, group) is worth joining? | allocation | quarterly | sales_director | `exam:883`: aggregators of demand or supply |
| MS-25 | Is a follower count a real audience or a vanity number? | diagnosis | monthly | sales_director | Followers are not reach and reach is not RFQs |
| MS-26 | Should a post be deleted after publication? | escalation | ad hoc | brand_mgr, legal | Deletion is itself public |
| MS-27 | Is an inbound DM asking something only `customer_experience` may answer? | escalation | daily | customer_experience | Marketing must not quote fees or terms in DMs |
| MS-28 | What does a zero engagement number mean here? | diagnosis | monthly | marketing_analyst | Three causes: no instrument, no publication, or genuinely no response |
| MS-29 | Refuse: "what is our best-performing channel?" | escalation | monthly | anyone | Nothing has ever been published on any channel |

### 2. Domain logic (the models this seat reasons with)

**M-MS-1 — The engagement funnel (the department's stated arithmetic).**
```
impressions      = reach × frequency
views            = impressions × view_rate
likes            = impressions × view_rate × like_rate      =  views × like_rate
comments         = views × comment_rate
shares           = views × share_rate
saves            = views × save_rate
engagements      = likes + comments + shares + saves + link_clicks
engagement_rate  = engagements / impressions        -- always state the denominator
link_clicks      = impressions × ctr
```
and inverted for planning:
```
impressions_needed(target_likes) = target_likes / (view_rate × like_rate)
posts_needed(target_likes)       = impressions_needed / impressions_per_post
```
| term | where it would live | value today |
|---|---|---|
| `reach`, `frequency`, `impressions` | a `social_post_metrics` table | **table does not exist** |
| `view_rate`, `like_rate`, `comment_rate`, `share_rate`, `save_rate` | derived from the same table | **UNMEASURED** |
| `ctr`, `link_clicks` | same table + a web-sessions table | **both do not exist** |
| paid impressions | `marketing_kpis.meta_impressions_30d` | **0** |

**Worked, so the seat has a concrete answer the moment data exists:** to obtain 100 likes at a 40%
view rate and a 2% like rate requires `100 / (0.40 × 0.02) = 12,500 impressions`. At 800 impressions per
organic post that is **≈ 16 posts**; at 30 posts it implies 417 impressions per post. Those two rates
are **assumptions written here as placeholders and must never be reported as ours** — this estate has
never recorded a single impression.

**M-MS-2 — The account, measured.**
```
select count(*) from social_posts                        -> 10
select count(*) from social_posts where status='published'-> 0
select count(*) from social_posts where created_at > now()-7d -> 0
columns available for engagement                          -> none
```
The ten rows break down as: 3 from `marketing_agent` (24 Jun 2026), 6 from `postiz_sync` (25 Jul and
6 Aug 2026), 1 `selftest`. All ten carry `mode='draft'` and `status='sent'` — *sent to Postiz*, not
*published to a network*. Five carry `permalink_missing = "Postiz draft (state DRAFT) — not published to
a network"`; four carry a note that Postiz no longer lists their ids (checked 6 Sep 2026) so **no
network URL exists to recover**; one is the pipeline self-test with `media_missing = "no media designed
yet"`. Channels named on nine of them: `instagram`, `linkedin`, `x`, `facebook`.
**Consequence: `social_published = 0`, engagement columns = none, and therefore every rate in M-MS-1 is
undefined. This is the seat's baseline and it must be stated in every report it writes.**

**M-MS-3 — Cadence and slotting (deterministic).**
```
sustainable_cadence = min(draft_capacity, review_capacity, publish_capacity)
publish_capacity    = 0 while marketing_golive = false  OR  cron:social_stage_hourly inactive
                      (both are true today)
slot(post) = (channel, day, hour) chosen from a stored slot table
constraints: business days Sun–Thu; UAE is UTC+4; no slot on a public holiday;
             ≥ 24 h between two posts on the same channel;
             supplier-recruitment share ≥ 70% while registered_suppliers < category_open_min_suppliers
```
**The slot table does not exist**; the UAE public-holiday calendar does not exist in this estate either.
Both are small stored tables and both are prerequisites for autonomous scheduling.

**M-MS-4 — Boost decision (bounded entirely by the founder's cap).**
```
eligible(post) := passed brand review ≤ 7 days ago
                ∧ has a measured engagement baseline        -- impossible today
                ∧ fn_ads_autospend_state().live_allowed      -- false today
budget(post)    = clamp( proposed, min_daily_per_campaign_aed (20), max_daily_per_campaign_aed (30) )
ceiling check   = fn_ad_spend_daily_ceiling()               -- AED 0 today, AED 30 when live
guard           = fn_ad_spend_ceiling_guard() refuses AD_SPEND_GOLIVE / AD_SPEND_CEILING
```
Because the founder's whole daily ceiling (AED 30) is only AED 10 above the per-campaign floor
(AED 20), **at most one boosted campaign can run at a time**. That is a real structural consequence of
his cap and the seat must plan around it rather than proposing parallel tests.

**M-MS-5 — Inbound triage (rules, no model).**
```
route(message) =
  'legal'               when it matches decision_policy.legal_triggers
                        (contract change|liability|indemnity|termination|dispute|refund dispute|
                         regulatory complaint|data subject request|subpoena|chargeback)
  'customer_experience' when it contains an order, fee, refund, account or complaint token
  'supply'              when the sender is a supplier or asks how to register
  'sales_director'      when it is a partnership or press approach
  'marketing_social'    otherwise (community reply from an approved reply template)
```
Fee, refund and account questions are **never** answered in a DM by this seat — they are quoted from
`pricing_config` only by the seat that owns them.

**M-MS-6 — Publication integrity.**
```
for each social_posts row:  expected_state = 'published'  when schedule_at < now() and mode='publish'
silent_failure := expected_state='published' and status <> 'published'
orphan         := postiz_ids present and the provider no longer lists them
```
Live: **10 of 10 rows are `mode='draft'`**, so the silent-failure rule finds none — the pipeline never
attempted a publish. **4 of 10 are orphans.** The estate's own file
`scripts/sql/a_pipeline_self_test_is_not_a_draft_post.sql` records that this distinction has already
bitten once.

### 3. Reasoning procedures

**MS-04 — "How many likes will this post get?"**
1. Read the post's channels from `social_posts`.
2. Attempt to read `impressions`, `view_rate`, `like_rate` from history. **No column, no history:
   `social_published = 0`.**
3. Refuse, with the arithmetic intact:
   *"Cannot forecast. likes = impressions × view rate × like rate. This account has 10 posts, all
   Postiz drafts, none published, and `social_posts` carries no impressions, views, likes, comments,
   shares or saves column. There is no prior. To answer this I need `marketing_golive` raised so posts
   actually publish, and a `social_post_metrics` table fed from the network APIs."*
4. Open the org task for the instrument. Do **not** substitute an industry benchmark (`exam:894`).

**MS-01 / MS-03 — "Build this week's calendar."**
1. Take the approved queue from `marketing_content`.
2. Apply M-MS-3. Since `publish_capacity = 0`, produce a **staging queue with no dates**, and state the
   two switches that gate it (`marketing_golive`, `cron:social_stage_hourly`).
3. Apply the supply weighting: `sum(registered) = 0 < 10`, so **≥ 70% of the queue is
   supplier-recruitment content**, addressed to the 19,896 reachable leads' audience, not to buyers.
4. Assign channels by audience: LinkedIn primary for both audiences; WhatsApp for supplier follow-up
   under an approved template only; Instagram/Facebook/X secondary.
5. Submit to `sales_director` (the parked Marketing Director's approval now routes there).

**MS-08 — "Should we boost this?"**
1. `fn_ads_autospend_state()` → `live_allowed = false`. **Stop**: the answer is no, and the reason is
   the absent Meta token and the `meta_autospend_golive=false` switch — never the post's quality.
2. Were it live: check eligibility (M-MS-4). The engagement-baseline clause fails for every post
   because no baseline can exist. So even with a token, **the first boost must be framed as a
   measurement probe**, budgeted at the AED 20 floor, whose only deliverable is the account's first
   real impression and click numbers.
3. Write the decision to `ad_decision` (ledger first) and let `fn_ad_spend_ceiling_guard()` adjudicate.

**MS-06 / MS-07 — "What is our engagement rate / did we meet cadence?"**
1. Execute the stored `measure_sql` verbatim.
   `Engagement rate` reads `avg((kpis->>'engagement_rate')::numeric) from marketing_snapshots where
   created_at > now()-30d` — **no snapshot carries that key, and the last snapshot is 2026-08-15**, so
   it returns null. `Publishing cadence met` reads
   `count(*) filter (where status='published') / count(*) from social_posts where created_at > now()-7d`
   — **0 rows in the window**, so 0/0 → null.
2. Classify both as **NO INSTRUMENT** (M-MA-5), not as poor performance.
3. Report: target 3% / actual null / measured_at null, and name the two changes that would make each
   measurable.

**MS-17 / MS-18 — "Did anything silently fail?"**
1. Run M-MS-6 across `social_posts`.
2. Report the 4 orphaned rows explicitly, with the recorded note that Postiz returned none for that
   month on 6 Sep 2026 and **no network URL exists to recover**.
3. Distinguish the self-test row from the marketing rows; do not count it as content.

**MS-29 — "What is our best-performing channel?"** Refuse:
*"Nothing has been published on any channel. All 10 posts are Postiz drafts; `social_published = 0`.
There is no per-channel data of any kind in this estate."*

### 4. Judgement rules

| # | condition | verdict | reason |
|---|---|---|---|
| J-MS-1 | `marketing_golive = false` | **Do not publish, at all** | Publishing against a false switch is a governance breach, not initiative |
| J-MS-2 | Asked for an engagement number | Refuse; name the missing table | 10 posts, 0 published, no engagement column |
| J-MS-3 | Asked to forecast likes with no prior | Give the identity and the missing terms; never a number | A forecast from no data is a fabrication |
| J-MS-4 | An industry benchmark is offered as our rate | **Reject even though it sounds authoritative** | `exam:894`: benchmarks are hypotheses |
| J-MS-5 | `registered_suppliers < 10` | ≥ 70% of the queue must be supplier recruitment | Buyer reach into an empty marketplace is spent twice |
| J-MS-6 | `live_allowed = false` and a boost is proposed | Refuse; blame the switch, not the post | Never let a switch masquerade as a quality verdict |
| J-MS-7 | A boost is proposed above AED 30/day or below AED 20/day | Clamp or refuse | `ad_spend_policy` bounds; the guard will refuse anyway |
| J-MS-8 | Two boosts proposed in parallel | Refuse the second | AED 30 ceiling minus AED 20 floor leaves no room for two |
| J-MS-9 | A DM asks about fees, refunds or an account | Route to `customer_experience`; do not answer | Marketing must not quote commercial terms |
| J-MS-10 | Inbound matches `legal_triggers` | Route to `legal` immediately, no public reply | `decision_policy` |
| J-MS-11 | A post would go to a real address or a real audience outside a rehearsal | Refuse | Standing rule: fixtures are `ZZ DEMO` / `@example.invalid` inside `withRun` |
| J-MS-12 | WhatsApp send without an approved template | Refuse | `qd-company:messaging-templates` records approval status; unapproved is a policy breach |
| J-MS-13 | A scheduled post's facts changed since drafting | Re-verify before publish or pull it | Fees, licence and counts move |
| J-MS-14 | Asked which channel performs best | Refuse | Nothing has ever been published |
| J-MS-15 | A post states a supplier count other than 0 | Refuse | The most dangerous number available |
| J-MS-16 | A post is brand-risk | Escalate to `sales_director` **before** scheduling, not after | The seat's stated escalation duty |
| J-MS-17 | Follower growth is reported as a result | Report reach and engagements instead, or refuse | Followers are not reach; reach is not RFQs |
| J-MS-18 | A publish attempt fails silently | Raise it the same day | Five posts sat as drafts for months and nobody was told |
| J-MS-19 | Asked to delete a published post | Escalate to `brand_mgr` + `legal` | Deletion is itself a public act |

### 5. Technical knowledge

- **`public.social_posts`** — all 15 columns (`source`, `content` jsonb, `image_url`, `channels[]`,
  `schedule_at`, `mode`, `status`, `postiz_ids` jsonb, `error`, `permalinks`, `permalink_missing`,
  `media_missing`, `preview_url`) and, critically, **which columns do not exist**: no impressions, no
  reach, no views, no likes, no comments, no shares, no saves, no clicks.
- **Postiz** as the scheduling provider: `postiz_api_key` present (64 chars), `postiz_ids` mapping
  `postId` → `integration`, `GET /public/v1/posts` as the reconciliation call, `preview_url` of the form
  `https://platform.postiz.com/p/<postId>?share=true`, and the distinction between
  **`type=draft` (sent to Postiz)** and **published to a network**.
- **`edge:social_stage`** and `cron:social_stage_hourly` (jobid 27, `17 * * * *`, **inactive**);
  `evsub:marketing_social@campaign.launched`.
- **The paid stack** as it bounds boosting: `ad_spend_policy` (30 / 30 / 20 / 3× / 3 days / AED 100 /
  +20%), `fn_ad_spend_daily_ceiling()`, `fn_ad_spend_ceiling_guard()`, `ad_decision` as the
  ledger-first trace, `edge:meta_ads`, `edge:meta_sync`, `cron:ads_autopilot_daily`.
- **Network mechanics** it must know without asking: canvas sizes per surface (from
  `company_brand.size.posts` / `size.covers`), caption limits, hashtag conventions per network,
  business-hours behaviour in the UAE (Sun–Thu, UTC+4), and WhatsApp's template-approval regime.
- **`app_secrets` switches:** `marketing_golive` **false**, `invite_enabled` **false**,
  `meta_autospend_golive` **false**, `meta_daily_budget_cap_aed` **30**.
- **What must be stored so the seat never asks anyone:** a **`social_post_metrics` table** (does not
  exist), a **slot table** (does not exist), a **UAE public-holiday calendar** (does not exist), an
  **approved reply-template set** (does not exist), and a `campaign_id` on `social_posts` so a post can
  be tied to a goal (does not exist).

### 6. Academic knowledge

| discipline | framework | lawful primary source |
|---|---|---|
| Measurement definitions | Impression, reach, frequency, viewable impression | **IAB / MRC Measurement Guidelines** (published) |
| Audience measurement | Sampling, frequency capping, incrementality | Published industry standards and open academic work |
| Messaging regulation | Consent, opt-out, template approval, sender identity | UAE TDRA regulations as published; Meta's public WhatsApp Business Policy |
| Advertising regulation | Truthful and substantiated claims, disclosure of paid promotion | UAE Media Council published advertising regulations |
| Data protection | Lawful basis for contacting business recipients | UAE Federal Decree-Law No. 45 of 2021 (PDPL) as published |
| Community management | Escalation ladders, response-time standards | Public service-management frameworks (e.g. ITIL published summaries) |
| Statistics | Sample size for engagement-rate comparisons | NIST/SEMATECH e-Handbook (public domain) |

**Certifications held:** rank 1 **Meta Certified Digital Marketing Associate** (Meta, pass mark 70%) —
syllabus: Meta Business Manager Setup · Campaign Objectives and Structure · Audience Targeting ·
Creative Best Practices · Measurement and Optimisation · Policies and Compliance. Rank 2 **CDMP-DMI**
(pass mark 60%).
**Exams sat: none** (0 rows). No failed syllabus area exists to report — which is itself notable, since
this seat holds the only certification whose issuing body is the platform whose token the company does
not have.
**Stored knowledge:** 12 `agent_knowledge` rows — the `profession`-layer record *"Social and community
for a UAE B2B marketplace"* (priority 74: *"The audience is on LinkedIn and WhatsApp, not on consumer
channels, and they are at work on Sunday to Thursday"*), plus `exam:1137` (WhatsApp as a UAE B2B growth
channel, fast, trusted and rule-bound), `exam:1138` (attribution windows too short for a multi-session
B2B journey), `exam:1136` (cross-category expansion), `exam:892` (procurement keyword research),
`exam:893` (discount addiction), `exam:894` (benchmarks are hypotheses), `exam:1455`–`1457`
(the marketing operations role charter and department operating model).

### 7. Corporate knowledge

- **WhatsApp is the founder's own command channel** and a regulated business channel. Templates and
  their Meta approval status live in `ops_knowledge:qd-company:messaging-templates`. Nothing goes out
  on it without an approved template.
- **`ops_knowledge:qd-company:content-social`** is the company's own record of its social posts — the
  seat should read its own history from there rather than re-deriving it.
- **The publication chain of command changed:** the note on `content_publish` says *"Must submit to the
  Marketing Director"*, but `marketing` (Marketing Director) was parked on 3 Sep 2026 with accountability
  moved to `sales_director`. **The authority note is stale text pointing at a parked seat** and should be
  corrected; until it is, the seat routes to `sales_director`.
- **Reveal notifies both parties** — the seat must never write a caption implying the buyer stays hidden
  after the reveal.
- **The 3% is the fee, promo and standard alike** — there is no promotional rate to advertise.
- **Hands to:** `sales_director` (publication approval, brand-risk escalation), `brand_mgr` (creative
  review), `customer_experience` (any commercial inbound), `legal` (triggers), `supply` (supplier
  enquiries), `marketing_analyst` (measurement).
- **History it must not forget:** the account's entire history is ten drafts across three dates in
  June, July and August 2026, four of which can no longer be recovered from the provider. **Nothing has
  ever been published.** Any claim of social "performance" in this company is, today, false by
  construction.

### 8. One-year plan

**Objective:** get the account **publishing at all**, and simultaneously build the instrument that makes
publication measurable — because publishing without measurement would repeat the last three months
exactly.

**Slice of AED 1,000,000:** **not quantifiable, and this plan refuses to invent it.** Social's revenue
contribution runs through impressions → clicks → RFQs → reveals, and every one of those four terms is
unmeasured. What can be stated is the arithmetic bound: with the founder's paid ceiling at AED 30/day
(AED 10,950/year) and only one boosted campaign possible at a time, **paid social cannot be the engine
of a AED 1,000,000 year** — it is a measurement instrument that costs AED 20–30 a day. Organic social's
contribution is unbounded in principle and zero in fact.

**Metrics owned (3):**
1. **Posts actually published** — `count(*) from social_posts where status='published'`.
   Baseline **0** (all time). Target: a sustained weekly cadence once `marketing_golive` is raised.
2. **Engagement rate** — its existing KPI (target 3%), currently `actual_value = null`,
   `measured_at = null`, reading a snapshot key that does not exist. Target: **measurable at all**,
   from a real `social_post_metrics` table, before any target value is discussed.
3. **Supplier registrations attributable to social** — the only metric on this list that maps to
   revenue, given the binding supply constraint. Baseline **0 registrations from any source**.

**Quarterly milestones:**

| quarter | milestone | measurable as |
|---|---|---|
| Q1 | `social_post_metrics` table exists and is fed from the network APIs | rows > 0 |
| Q1 | Slot table + UAE holiday calendar written; the queue becomes a schedule | tables exist |
| Q1 | The 4 orphaned Postiz rows reconciled and closed with a written reason | `permalink_missing` resolved on 4 rows |
| Q1 | `Engagement rate` and `Publishing cadence met` KPIs re-pointed at real instruments | `measured_at is not null` |
| Q2 | **First published post in company history** (needs `marketing_golive`) | `social_published ≥ 1` |
| Q2 | First measured impression, view rate and like rate — M-MS-1 stops being placeholders | 3 rates computed from ≥ 20 posts |
| Q3 | First boosted post inside the AED 30/day cap, one campaign at a time | ≥ 1 executed `ad_decision` |
| Q3 | Approved reply-template set live; inbound triage running to M-MS-5 | template table + routed inbounds |
| Q4 | Arabic parity on the top of the queue | `locale='ar'` posts published |

**Capacity check — can this seat produce its share?** Not today, and the reasons are external to it:
`marketing_golive = false`, `cron:social_stage_hourly` **inactive**, `meta_autospend_golive = false`,
no Meta token, and **no engagement column to learn from**. A social seat that may draft and schedule but
"may not publish", pointed at an approver that was parked, with a metrics table that does not exist, has
a structural capacity of **zero published posts per week**, which is exactly what the last three months
produced. **Its capacity is a switch, not a workload.**

**Dependencies:** `founder` (`marketing_golive`, the Meta token, `meta_autospend_golive`),
`product_eng` (`social_post_metrics`, slot and holiday tables, cron reactivation),
`sales_director` (publication approval, now that the Marketing Director seat is parked),
`brand_mgr` (creative review), `marketing_content` (the queue), `marketing_analyst` (rate computation),
`customer_experience` and `legal` (inbound routing).

### 9. What this seat cannot do without a model

- **Scheduling, slotting, triage routing, boost bounding, cadence arithmetic and publication-integrity
  checks are all deterministic** — stored tables, rules over keyword lists, and clamped arithmetic
  against `ad_spend_policy`.
- **Community replies to unanticipated messages** are the one genuine gap. The deterministic answer is
  an **approved reply-template set** keyed to the triage classes of M-MS-5, plus an honest escalation
  for anything that matches no class: *"routed to a person / to `customer_experience`"*. That is
  better behaviour than a generated reply in a public channel, where a wrong sentence is permanent.
- **Writing net-new caption copy** shares `marketing_content`'s limitation: the seat can instantiate
  approved caption templates with computed values and cited facts, but it cannot invent a new voice.
  Accepted consequence, stated in the open.

---

## optimisation_eng — Product Optimisation Engineer

`responsibilities`: *"Owns cost per decision, cost per RFQ, model tier routing, response caching and
automation coverage. Finds the cheapest path that still satisfies the priority hierarchy."*
`authority_level = execute_low`, `budget_limit = 0`. `employee_authority`: **autonomous** on `recommend`
(*"May propose model and cost changes"*), **gated** on `code_selfheal` (*"Cost changes touching
production need review"*). It is `kind='agent'`, not `kind='brain'` — the only such seat in this
department.

**The honest observation this seat's own plan must open with:** two of its three stated
responsibilities — *model tier routing* and *response caching* — are responsibilities for **LLM** calls.
Under the founder's constraint that nothing may depend on a language model at run time, those two
shrink toward zero and the seat's centre of gravity moves to **cost per decision, automation coverage
and conversion optimisation**. Its two live KPIs measure the world that is being switched off.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| OE-01 | What does one decision cost this company, in AED? | diagnosis | weekly | finance, sales_director | The number every automation trade-off is made against |
| OE-02 | What does one RFQ cost end to end? | diagnosis | monthly | sales_director | With 0 RFQs the denominator is zero; a fabricated figure poisons every plan |
| OE-03 | Which calls could a cheaper tier have served? | allocation | weekly | its own KPI | Its KPI reads 39.93% against a target of ≤ 10% |
| OE-04 | What share of calls is served from cache? | diagnosis | weekly | its own KPI | 2.1% against a target of 20% |
| OE-05 | Which routine still requires a model and could be replaced by code? | sequencing | weekly | founder, cto | **The central question of this whole plan** |
| OE-06 | Is a proposed deterministic replacement actually equivalent? | gate | per replacement | cto, assurance | A "cheaper" path that changes behaviour is a regression, not a saving |
| OE-07 | Is the growth department inside its AED 120/month AI budget? | diagnosis | weekly | finance | 95% halts the department's automation |
| OE-08 | What is automation coverage — what share of this department's work runs without a human? | diagnosis | monthly | ceo | The autonomous-company target depends on it |
| OE-09 | Which cron is inactive, and was that a decision or a drift? | diagnosis | weekly | product_eng, sales_director | Seven of eleven growth crons are off and **nothing records who turned them off** |
| OE-10 | Should this experiment run, and at what sample size? | gate | per experiment | marketing_analyst | An underpowered experiment costs traffic and yields nothing |
| OE-11 | Is this experiment result real? | gate | per experiment | sales_director | `exam:1128` |
| OE-12 | Which page element is the conversion bottleneck? | diagnosis | monthly | marketing_content | **No analytics instrument exists**; the honest answer is a refusal |
| OE-13 | Does the RFQ form add friction that filters out genuine buyers? | diagnosis | quarterly | marketing_content | `exam:736`: the form is the visit-to-RFQ gate |
| OE-14 | What is the cheapest path that still satisfies the priority hierarchy? | allocation | weekly | cto | The seat's stated purpose |
| OE-15 | Is a latency regression a cost problem or a correctness problem? | diagnosis | weekly | product_eng | Optimising latency by dropping a check is a false saving |
| OE-16 | Which cached response is stale and must be invalidated? | gate | daily | product_eng | A stale cached answer about fees is a commercial error |
| OE-17 | Is a zero in the cost log a saving or a switched-off system? | diagnosis | weekly | finance, marketing_analyst | Sept 2026 is AED 0.00/day and that is **policy, not efficiency** |
| OE-18 | What is the marginal cost of one more automated decision? | forecast | monthly | ceo | Sizes how far autonomy can scale on the current budget |
| OE-19 | Which routine is called most and is therefore worth optimising first? | sequencing | monthly | product_eng | Optimising a cold path is wasted effort |
| OE-20 | Should this workflow step be throttled? | allocation | weekly | cto | The reflection-throttle precedent (`workflow_reflection_steps_per_day`) |
| OE-21 | Is a proposed change inside `code_selfheal` authority or does it need review? | gate | per change | cto | Cost changes touching production are gated |
| OE-22 | Which of the department's questions are answerable without a model today? | diagnosis | quarterly | founder | The measure of whether this plan is working |
| OE-23 | What is the cost of an embedding call, and is it really free? | diagnosis | monthly | finance | In-region `gte-small` is free; assuming a paid path would kill a legitimate tool |
| OE-24 | Is the response cache hit rate low because of misses or because of low volume? | diagnosis | weekly | product_eng | 41 cache rows against thousands of calls is a volume story, not a design story |
| OE-25 | Does this optimisation change a founder-set number? | escalation | per change | founder | Caps and thresholds he set are his, not the optimiser's |
| OE-26 | Which conversion event should paid campaigns optimise to? | gate | per campaign | marketing_analyst | `exam:737`: optimising to leads instead of reveals is the expensive error |
| OE-27 | Is branded search cannibalising organic? | diagnosis | quarterly | marketing_content | `exam:1160`: paying for clicks we already own |
| OE-28 | Is a local-SEO surface (emirate, free zone) worth building? | allocation | quarterly | marketing_content | `exam:1158`: UAE B2B local intent is strong |
| OE-29 | Should a failing automation be retried, throttled or dead-lettered? | allocation | daily | product_eng | `dead_letter` holds 122 rows |
| OE-30 | Refuse: "which variant won?" when there are no exposures | escalation | monthly | anyone | 2 experiments, 1 assignment, **0 events** |

### 2. Domain logic (the models this seat reasons with)

**M-OE-1 — Cost per decision.**
```
cost_per_decision = Σ cost_aed over ai_cost_log in window / count(decisions in window)
```
Measured, 30-day window to 7 Sep 2026:

| day | calls | AED | cached | could_be_cheaper |
|---|---|---|---|---|
| 2026-09-07 | 78 | **0.0000** | 0 | 0 |
| 2026-09-05 | 30 | **0.0000** | 0 | 0 |
| 2026-09-04 | 293 | **0.0000** | 0 | 0 |
| 2026-09-03 | 1 | **0.0000** | 0 | 0 |
| 2026-08-15 | 69 | 7.5486 | 0 | 61 |
| 2026-08-14 | 291 | 15.7278 | 10 | 259 |
| 2026-08-13 | 400 | 29.2980 | 14 | 372 |
| 2026-08-12 | 334 | 21.5391 | 18 | 284 |
| 2026-08-11 | 766 | 38.0009 | 17 | 137 |
| 2026-08-10 | 489 | 22.5815 | 2 | 0 |

**The September zeros are the OpenRouter hold, not an optimisation.** Reporting them as a cost win would
be the exact error this seat exists to prevent, and J-OE-1 forbids it. The August window gives a real
per-call figure: 2,349 calls for AED 134.70 over 11–15 Aug = **AED 0.0573/call**.

**M-OE-2 — Cost per RFQ.**
```
cost_per_rfq = (AI cost + infrastructure allocated) / count(inquiries in window)
```
**Denominator is 0.** `inquiries` has never had a row. The seat must publish the formula and refuse the
number — this is the cleanest example in the department of a metric whose absence is honest.

**M-OE-3 — Tier routing (deterministic, and mostly obsolete under the constraint).**
```
tier(task) = 'code'      when a deterministic routine exists for it        -- the target state
           = 'embed'     when the task is retrieval by meaning              -- free, in-region gte-small
           = 'small'     when it needs generation and fits a small model
           = 'large'     otherwise
could_be_cheaper := actual_tier > tier(task)
```
Live KPI: **`AI cost efficiency` = 39.93%** of calls could have been served more cheaply, against a
target of **≤ 10%** — measured over the last 30 days of `ai_cost_log`. Under the no-model constraint the
correct remedy is not "route to a smaller model" but **"replace with `tier='code'`"**, which takes the
metric to a place its own definition did not anticipate.

**M-OE-4 — Cache economics.**
```
hit_rate      = cached_calls / total_calls
saving_aed    = hit_rate × total_calls × unit_cost
break_even    : caching is worth building when  expected_hits × unit_cost > build + storage + staleness_risk
```
Live: **`Response cache adoption` = 2.1%** against a target of 20%; `llm_cache` holds **41 rows**.
Diagnosis by M-OE-8 below: with 2,349 calls in the busiest week and 41 distinct cached entries, the low
hit rate is a **key-diversity** story (few repeated prompts), not a broken cache. Chasing 20% by
loosening the cache key would trade correctness for a metric.

**M-OE-5 — Automation coverage.**
```
coverage = automated_steps / (automated_steps + human_steps)
```
Proxies available today: `company_goals.autonomous_decision_rate` (target ≥ 90%) measured as
`count(*) filter (where not needs_founder) / count(*) from org_tasks` over 30 days, and
`human_intervention` (target ≤ 2%). For this department specifically, coverage has an unusual shape:
**seven of eleven growth crons are inactive**, so a high "autonomous decision rate" coexists with a
production line that is not running. Coverage must therefore be reported as a pair:
`(share of decisions that need no human, share of the department's pipelines that are switched on)` —
today **the second number is 4/11 = 36%**.

**M-OE-6 — Experiment sizing.** Identical to M-MA-4 (two-proportion power). This seat owns the
*plumbing* — assignment, exposure logging, invalidation — and `marketing_analyst` owns the verdict.
Live: `experiments` 2, `experiment_assignments` **1**, `experiment_events` **0**, both running since
6 July 2026. **The exposure logger is not writing.** That is an engineering defect in this seat's own
area, not an analysis problem.

**M-OE-7 — Budget guard.**
```
pct  = 100 × department_budget.spent_aed / monthly_aed          -- growth: 0 / 120 = 0%
state= normal (<70) | degrade (<95) | halt (≥95)
```

**M-OE-8 — Three causes of a low rate (the seat's own version of M-MA-5).**
```
low_rate_cause :=
  'NO VOLUME'      when the denominator is small enough that the rate is noise
  'DESIGN'         when volume is adequate and the mechanism genuinely misses
  'SWITCHED OFF'   when the mechanism did not run at all in the window
```
Applied: cache adoption 2.1% → **NO VOLUME + key diversity**; September cost AED 0 →
**SWITCHED OFF** (OpenRouter held); experiment events 0 → **SWITCHED OFF** (the logger never fired).

**M-OE-9 — Deterministic-replacement equivalence gate.** Before any model-backed step is replaced by
code:
```
equivalent := on a stored corpus of past inputs, output_code == output_model on ≥ 99% of cases
            ∧ every disagreement is reviewed and classified as (code better | code worse | tie)
            ∧ the replacement's refusal behaviour is at least as conservative as the original's
```
**UNMEASURED: no such corpus exists in this estate.** Building it is a prerequisite for doing this plan
safely, and it is this seat's single most important deliverable.

### 3. Reasoning procedures

**OE-01 / OE-17 — "What does a decision cost, and is this zero a saving?"**
1. Query `ai_cost_log` by day over 30 days.
2. Run M-OE-8. If the window contains a policy change (OpenRouter held from ~16 Aug 2026), **split the
   window at the change** and report both halves separately. Never average across a policy boundary.
3. Report: *"AED 0.0573/call measured over 11–15 Aug 2026 (2,349 calls, AED 134.70). September is
   AED 0.00/day on 402 calls — that is the OpenRouter hold, not an efficiency gain."*
4. Refuse to present the September figure as a run rate (a total is not a run rate; the window is not
   stationary).

**OE-05 — "Which routine still requires a model?"** (the central procedure of this plan)
1. Enumerate every call site in `ai_cost_log` by `fn`, with call counts and cost over the last window
   where spend existed.
2. For each, classify the task: **retrieval** (→ embed, free), **classification against a closed set**
   (→ code + lexicon), **arithmetic or lookup** (→ code), **extraction into a fixed schema** (→ code +
   patterns, with an honest refusal path), **open generation** (→ genuinely needs a model).
3. Rank by `calls × unit_cost` so the hottest paths convert first.
4. For each conversion, require M-OE-9 equivalence before it ships, and `code_selfheal` is **gated** —
   so every one goes through review.
5. **Stop condition:** if the equivalence corpus does not exist for that call site, do not convert;
   build the corpus first. Converting blind is how a cost win becomes a silent behaviour change.

**OE-03 / OE-04 — "Why is the efficiency KPI at 39.93% and the cache at 2.1%?"**
1. Recompute both from `ai_cost_log` in the window where spend existed (August), not the September
   window where every call is free and every flag is 0.
2. Note the shape: on 11 Aug, 766 calls produced only 137 `could_be_cheaper` flags, while on 13 Aug,
   400 calls produced 372. The flag rate is not stationary either — **report the two regimes, not one
   average**.
3. For the cache: 41 entries against thousands of calls → classify **NO VOLUME / key diversity**
   (M-OE-8), and refuse the tempting remedy of a looser cache key (J-OE-6).
4. Recommend the real remedy under the founder's constraint: convert hot call sites to `tier='code'`,
   which removes the call rather than making it cheaper.

**OE-09 — "Was this cron switched off deliberately?"**
1. List `cron.job` for the department: **inactive** — `agent_marketing_weekly` (12),
   `social_stage_hourly` (27), `blog_weekly_mon` (46), `marketing_ai_daily` (71),
   `backfill_invite_trades` (120), `invite_ramp_daily` (121), `content_revise_hourly` (131),
   `seo_gen_weekly` (177). **Active** — `supplier_invites_daily` (2), `meta_sync_daily` (72),
   `ads_autopilot_daily` (316).
2. For each inactive job, look for a decision record: a `cron_registry` note, an org task, a commit
   reference. **For these eight, no such record was found in this estate.**
3. Report each as **UNEXPLAINED INACTIVE** and open one task per job asking for a decision: re-enable
   or retire. A pipeline that is off for no recorded reason is neither running nor decided.

**OE-10 / OE-11 / OE-30 — "Should this experiment run / did it win?"**
1. Require a pre-registered sample size from M-OE-6 **before** launch, stored on the `experiments` row.
2. Verify the exposure logger writes an `experiment_events` row on assignment. **Today it does not:
   0 events against 1 assignment across two experiments open since 6 July 2026.** Until that is fixed,
   refuse to launch any new experiment — a test that cannot record exposures is not a test.
3. On completion, hand the arithmetic to `marketing_analyst`; never declare a winner in this seat.
4. If asked "which variant won" with 0 events, answer **"no exposures recorded"**, never "no
   difference".

**OE-12 / OE-13 — "Where is the conversion bottleneck?"** Refuse:
*"Cannot answer. There is no analytics table in this estate — no sessions, no pageviews, no funnel
events — and `inquiries` has 0 rows, so there is no conversion to decompose. What I can do without an
instrument is a heuristic audit of the RFQ form against `exam:736` (field count, required-field count,
whether each field is needed before a supplier can quote), and hand that to `marketing_content` as a
hypothesis, explicitly labelled as untested."*

### 4. Judgement rules

| # | condition | verdict | reason |
|---|---|---|---|
| J-OE-1 | Cost fell because a system was switched off | **Never report it as an optimisation** | September's AED 0.00/day is the OpenRouter hold |
| J-OE-2 | A window spans a policy change | Split it; never average across the boundary | Non-stationary windows produce false rates |
| J-OE-3 | A denominator is 0 | Publish the formula, refuse the number | `cost_per_rfq` has no denominator |
| J-OE-4 | A replacement lacks an equivalence corpus | **Do not ship it**, however large the saving | A cheaper path that changes behaviour is a regression |
| J-OE-5 | A cost change touches production | Gated review, always | `employee_authority.code_selfheal = gated` |
| J-OE-6 | Cache hit rate could be raised by loosening the key | **Refuse even though the KPI would improve** | Trading correctness for a metric is the definition of gaming |
| J-OE-7 | An optimisation would change a founder-set number (AED 30 cap, 3% fee, 10-supplier threshold, AED 0 autonomous money) | Refuse; escalate | Those numbers are his |
| J-OE-8 | An experiment has no pre-registered n | Do not launch | `exam:1128` |
| J-OE-9 | An experiment records 0 exposures | "No exposures recorded", never "no difference" | Opposite statements |
| J-OE-10 | An experiment has run > 30 days below its required n | Stop it and record why | Two are in exactly this state since 6 Jul 2026 |
| J-OE-11 | A cron is inactive with no recorded decision | Report UNEXPLAINED INACTIVE and open a task | Eight are in this state |
| J-OE-12 | Latency improved by removing a check | Refuse | A dropped check is not a saving |
| J-OE-13 | Asked to optimise a path that runs 1 call/day | Refuse; optimise by call volume | Cold-path optimisation is effort with no return |
| J-OE-14 | A campaign optimises to leads rather than reveals | Flag to `marketing_analyst` and `sales_director` | `exam:737` |
| J-OE-15 | Paid bidding on our own brand terms | Flag as cannibalisation | `exam:1160` |
| J-OE-16 | Budget ≥ 95% of AED 120/month | Halt department automation | `department_budget.halt_at_pct` |
| J-OE-17 | An embedding call is proposed | Allow — in-region `gte-small` is free and permitted | Do not confuse it with paid inference |
| J-OE-18 | A paid model call is proposed | **Refuse** | OpenRouter is held; deterministic code is the standard |
| J-OE-19 | A retrieval returns a nearest neighbour with no lexical overlap | Treat as no match | A nearest neighbour is always found; similarity alone is not evidence |

### 5. Technical knowledge

- **`public.ai_cost_log`** — `occurred_at`, `cost_aed`, `model_used`, `tier`, `tokens`, `cached`,
  `could_be_cheaper`, `ok`, `fn`. And its companions: `ai_cost_fn_map`, `ai_spend_probe` (12,711 rows),
  `v_ai_spend`, `v_cost_optimisation`.
- **`public.llm_cache`** — 41 rows; the cache key design and its staleness rules.
- **`public.experiments` / `experiment_assignments` / `experiment_events`** — 2 / 1 / **0**, and the
  assignment-and-exposure contract that is currently not being honoured.
- **`public.department_budget`** — growth AED 120/month, `degrade_at_pct` 70, `halt_at_pct` 95.
- **`decision_policy` throttles:** `cos_reflection_tasks_per_day` 500,
  `workflow_reflection_steps_per_day` 2000, `dispatch_max_batch` 500,
  `dispatch_max_open_per_dept` 250, `event_recur_cooldown_days` 7, `prompt_cache_enabled` true,
  `confidence_min` 0.6.
- **`cron.job`** for this department (11 jobs, listed in OE-09) and `fn_kernel_cron_exec`,
  `fn_kernel_wrap_and_enable_cron`, `cron_registry`.
- **`public.dead_letter`** (122 rows) and `v_dead_letter_open`.
- **The free embedding path:** in-region `gte-small` via `kb_embed`, `agent_knowledge.embedding_gte`,
  `edge:embed_leads`. **Free and permitted** — distinct in every respect from OpenRouter.
- **Statistics for experiments** — power, MDE, two-proportion tests, sequential-testing error.
- **What must be stored so the seat never asks anyone:** an **equivalence corpus** per model-backed call
  site (does not exist), a **pre-registered n** column on `experiments` (does not exist), a **decision
  record for every disabled cron** (does not exist), and a **cost-per-decision denominator definition**
  (does not exist — what counts as "a decision" is undefined).

### 6. Academic knowledge

| discipline | framework | lawful primary source |
|---|---|---|
| Experimental design | Power, MDE, pre-registration, sequential error | **NIST/SEMATECH e-Handbook** (public domain); OSF public templates |
| Conversion optimisation | Research → hypothesis → experiment → analysis | CXL published programme outline (syllabus structure only) |
| Queueing and throughput | Little's Law, utilisation vs latency | Open-access operations-research texts |
| Caching | Locality, key design, invalidation, staleness cost | Published systems literature; open documentation |
| Cost modelling | Marginal vs average cost, unit economics | Open-access economics texts |
| Measurement | Event and conversion definitions | Google Analytics 4 published documentation; IAB/MRC guidelines |
| Reliability | Retry, backoff, dead-lettering, idempotency | Published cloud-provider architecture guidance |

**Certifications held:** rank 1 **CXL Conversion Optimization Minidegree** (CXL, pass mark **80%**) —
syllabus: Research and Data Collection · Heuristic Analysis and User Research · Hypothesis Building ·
Experiment Design and Statistics · A/B Test Execution and Analysis · Optimization Programme Management.
Rank 2 **Google Analytics 4 Certification** (pass mark 80%).
**Exams sat: none** (0 rows). No failed syllabus area exists to report. Note that its rank-2
certification is the same GA4 exam the `marketing_analyst` seat failed twice at 25% and 35% — the
department should expect this seat to fail it too until the underlying knowledge is loaded.
**Stored knowledge:** 12 `agent_knowledge` rows — the `profession`-layer record *"Cost and latency
optimisation of an AI-run company"* (priority 74: *"The spend is per-call, metered into `ai_cost_log`
with `model_used`, `tier`, `tokens`, `cached` and `could_be_cheaper`"*), plus `exam:1158` (local SEO for
UAE B2B: Google Business, free zones, area pages), `exam:1160` (branded-search cannibalisation),
`exam:914` (referral loops in a relationship-driven market), `exam:915` (supplier tiering),
`exam:916` (the liquidity-reachability scorecard for choosing the next category).

### 7. Corporate knowledge

- **OpenRouter is held.** Paid inference is not an option; the standard is ~95% deterministic code.
  In-region `gte-small` embedding is free and allowed. The seat's own KPIs were written for a world
  where model calls were the cost centre; under this plan they must be re-specified.
- **The founder's numbers are not optimisation targets:** AED 30/day cap, 3% reveal fee, 10 suppliers to
  open a category, AED 0 autonomous money movement, AED 10,000 human-review threshold, AED 250 refund
  admin fee. Changing any of them is an escalation, never an optimisation.
- **The reflection-throttle precedent** (`decision_policy.workflow_reflection_steps_per_day`) is this
  seat's own institutional memory and should be read before every cost estimate: a per-step cost of
  AED 0.086 was derived by dividing estate-wide spend by a step count; measured directly from
  `ai_cost_log where fn='workflow_dispatch'` over 11–14 Aug 2026 the true figure was **AED 0.146/step**.
  *Always measure the subject, never divide an aggregate.*
- **`cos_reflection_tasks_per_day` exists because** on 6 Aug 2026 a 346-row self-analysis queue took the
  daily AI bill from ~AED 1 to AED 11–15 with zero customers, inquiries or quotes. Demand-linked tasks
  are never throttled.
- **Workflows owned:** the weekly cost report, the tier-and-cache review, the experiment plumbing, the
  cron-inactivity audit, the deterministic-replacement programme.
- **Hands to:** `cto` / `product_eng` (all gated changes), `marketing_analyst` (experiment verdicts),
  `finance` (budget), `sales_director` (recommendations), `founder` (only when a founder-set number is
  implicated).
- **History it must not forget:** its two KPIs read **39.93%** (`AI cost efficiency`, target ≤ 10%) and
  **2.1%** (`Response cache adoption`, target 20%), both computed over a window that ends inside the
  OpenRouter hold. Neither number means today what it meant when it was written.

### 8. One-year plan

**Objective:** make this department answerable **without a model** — convert every model-backed step in
its pipelines to deterministic code with a proven equivalence, and rebuild the cost and experiment
instruments so the conversion can be verified rather than asserted.

**Slice of AED 1,000,000:** **AED 0 direct**, and this seat should never be given a revenue number:
`budget_limit = 0`, `advisory`/`gated` authority, and a cost-reduction incentive attached to a revenue
target is how correctness gets traded away. Its contribution is stated as **cost avoided and capability
made deterministic**. The measurable frame: at AED 0.0573/call (measured 11–15 Aug 2026), the estate's
busiest observed day (766 calls) cost AED 38.00. Converting the hot paths to code removes that cost
entirely rather than reducing it — and, more importantly, removes the dependency the founder has ruled
out twice.

**Metrics owned (3):**
1. **Deterministic coverage** — the share of this department's question types (≈ 230 across the seven
   seats in this document) that resolve with **no model call**. Baseline: **not computable** — no
   inventory of call sites by question type exists. Target: **100% of the types listed in this
   document**, with section 9 of each seat as the agreed exception list.
2. **AI cost efficiency** — its existing KPI, **39.93%** against a target of ≤ 10%, recomputed over a
   spend-bearing window and re-specified so that `tier='code'` counts as the cheapest tier.
3. **Pipelines switched on** — **4 of 11** growth crons active today. Target: every one of the eleven
   either active or formally retired with a written reason; **zero UNEXPLAINED INACTIVE**.

**Quarterly milestones:**

| quarter | milestone | measurable as |
|---|---|---|
| Q1 | Call-site inventory: every `ai_cost_log.fn` classified into the five task classes of OE-05 | inventory table exists, 100% classified |
| Q1 | Equivalence corpus built for the top 5 call sites by volume | corpus rows > 0 for 5 sites |
| Q1 | Exposure logger fixed; `experiment_events` writes on every assignment | events > 0 |
| Q1 | All 8 inactive crons given a decision: re-enable or retire, in writing | 0 UNEXPLAINED INACTIVE |
| Q2 | Top 3 call sites converted to `tier='code'` at ≥ 99% equivalence, through gated review | 3 conversions merged |
| Q2 | `cost_per_decision` published weekly with the denominator defined | a standing report |
| Q3 | Both stale experiments retired; the first properly-powered experiment launched with a pre-registered n | `experiments.stopped_at` set on 2; 1 new with n |
| Q3 | Cache re-specified: hit rate reported with its key-diversity denominator, not chased | report shape changed |
| Q4 | Deterministic coverage at 100% of the documented question types | the exception list matches the section 9s |

**Capacity check:** this is the one seat in the department whose year-one plan is **fully executable
with what exists today** — `ai_cost_log`, `cron.job`, `experiments`, `llm_cache` and
`department_budget` are all live and populated, and the work is engineering rather than instrument-
waiting. The constraints are two: `code_selfheal` is **gated**, so every conversion needs `cto` review
(correctly), and the equivalence corpus must be built before any conversion, which front-loads Q1 with
unglamorous data work. The AED 120/month departmental budget is not a constraint at AED 0 spent.

**Dependencies:** `cto` / `product_eng` (gated review, cron decisions, the exposure logger),
`marketing_analyst` (experiment verdicts and the power calculation), `assurance` (equivalence
sign-off), `finance` (budget), `founder` (only where a founder-set number is implicated).

### 9. What this seat cannot do without a model

- **Nothing in its own work.** Cost arithmetic, tier classification, cache economics, power
  calculations, cron auditing and equivalence testing are all deterministic by construction.
- Its job is, in fact, **to remove the model from everyone else's work**, and the four exceptions it
  cannot engineer away are named honestly in the other seats' section 9s: original long-form copy
  (`marketing_content`), original visual concepts (`marketing_design`), free-form community replies
  (`marketing_social`), and unstructured founder instructions that match no question type
  (`sales_director`). For each, the deterministic substitute is a **template plus a citation plus an
  honest refusal path**, not a smaller model.
- One boundary worth stating: judging whether a deterministic replacement is *semantically* equivalent
  to a model's output on a disagreement case is a human review, not a model call. M-OE-9 routes every
  disagreement to review precisely so that this judgement never gets automated by the thing being
  replaced.

---

## Department summary — the one-year slice, assembled

| seat | direct revenue slice | why |
|---|---|---|
| `sales_director` | **owns the department's whole contribution** — on the critical path for 100% of the AED 1,000,000, sole owner of none of it | every dirham is a reveal fee; supply must exist for a reveal to be possible |
| `brand_mgr` | AED 0 | a gate; a revenue target would create an incentive to approve weak work |
| `marketing_analyst` | AED 0 | advisory, `budget_limit = 0`; a revenue target would bias its reports |
| `marketing_content` | not quantifiable — no attribution instrument exists | claiming a share would be an invention |
| `marketing_design` | AED 0 | production seat; a revenue target would push volume over correctness |
| `marketing_social` | not quantifiable — no engagement instrument exists | the arithmetic bound is that AED 30/day cannot be an engine |
| `optimisation_eng` | AED 0 (cost avoided, not revenue earned) | a cost-reduction incentive tied to revenue trades away correctness |

**The department's slice of AED 1,000,000, stated plainly.** All company revenue is reveal fees at 3%
of quote value (supplier registration contributes **AED 0** in year one by design: the first 1,000
suppliers are free). Growth is on the critical path for all of it. The required reveal count is
`1,000,000 / (avg_quote_value × 0.03)` — **1,667/year at an AED 20,000 average quote, 667 at AED 50,000,
334 at AED 100,000** — and `avg_quote_value` is **unmeasured**, because `quotes` has 0 rows.

**Is it achievable? No — not in the coming year on the current inputs**, and the arithmetic rather than
an opinion says so:
- **0 registered suppliers** against a threshold of **10** to open a single category. No reveal is
  possible until this changes, and it is not this department's lever.
- **AED 0/day of usable paid media.** The founder's AED 30/day cap is dormant: `meta_autospend_golive`
  is false and no Meta token exists, so `fn_ads_autospend_state().live_allowed = false`. Even at the
  full cap, AED 10,950/year implies a cost per reveal of **AED 16.42** to carry 667 reveals alone — a
  figure this estate has never measured and therefore cannot claim is achievable *or* impossible.
- **Nothing is publishing.** `marketing_golive` is false, `invite_enabled` is false, and seven of eleven
  growth crons are inactive with no recorded decision.
- **Four of the department's five own goals have no instrument**, and there is no analytics table of any
  kind in this database.

**What would make it achievable, in the order the arithmetic ranks them:**
1. Diagnose and fix the supplier funnel — **344 invited, 323 delivered, 0 registered**. This is the
   binding constraint and it belongs to `supply`, not here.
2. `meta_access_token` minted and `meta_autospend_golive` set true, so the AED 30/day cap stops being
   AED 0 and the company's first cost-per-lead can be measured.
3. `ad_spend_policy.target_cpl_aed` given a value — it is **NULL**, so the autopilot's scale rule can
   never fire and its kill rule fires on only one of its two limbs.
4. `marketing_golive` raised, so the ten drafted posts and the content queue can actually publish.
5. Three instruments built by `product_eng`: **web sessions**, **social post metrics**, and a
   **first-touch channel column on `inquiries`**. These three unblock more of this department's
   question types than anything else on the list.
6. Only after (2) and (5): a decision on whether to raise the AED 30/day cap, taken against a measured
   cost per reveal versus the break-even of `avg_quote_value × 3%`.


