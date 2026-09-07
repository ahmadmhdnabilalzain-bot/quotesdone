# Company brain — Exec department

**Scope.** The three active seats in `public.org_agents where active and department = 'exec'`, measured on production
`htdblwldjkcgjvmqkbeh` on 7 September 2026 between 08:01 and 10:05 UTC, read-only, with no paid model call and nothing
written:

| agent_key | title | seniority | manager | max_open_tasks |
|---|---|---|---|---|
| `ceo` | Chief Executive (AI) | executive | — (apex) | 50 |
| `brief` | Chief of Staff | executive | `ceo` | 50 |
| `cpo` | Chief Performance Officer | chief | `ceo` | 50 |

A fourth row, `strategy_director` (Strategy Director), is `active = false` — parked 4 Sep 2026 with
`unavailable_reason` "STAFF_ORG #3/#4: one strategy officer; cpo carries the scorecard mechanisms". It gets no block
here; if it is ever re-hired, its taxonomy is the diagnosis and forecast half of the `cpo` block below.

**The run-time constraint this plan is written against.** The founder has said twice that nothing may depend on a
language model at run time. Every resolver below is a SQL routine or an arithmetic procedure over named tables. The
only model-shaped step anywhere is question→type matching, and that is done with `pg_trgm` lexical similarity plus the
free in-region `gte-small` embedding already on `agent_knowledge.embedding_gte` and `ops_knowledge.embedding_gte` — no
provider call. Section 9 of each block is the honest list of what is left over.

**Measured baseline every seat in this department shares** (all figures read from production on 7 Sep 2026):

| Fact | Value | Source |
|---|---|---|
| Revenue to date | AED 0 | `company_goals.revenue_annual.measure_sql` executed by `fn_revenue_trajectory()` |
| Target | AED 1,000,000 by 2027-08-31 | `company_goals` (`deadline` set) |
| Days remaining | 358 | `fn_revenue_trajectory()` |
| Required run rate | **AED 85,027.93 / month**, AED 2,793.30 / day | `fn_revenue_trajectory()` |
| Reveals ever paid | 0 | `transactions` = 0 rows |
| Inquiries ever | 0 | `inquiries` = 0 rows |
| Quotes ever | 0 | `quotes` = 0 rows |
| Customers | 1 | `customers` |
| Supplier leads scraped | 22,265 | `leads` |
| Invited | 171 (161 `sent`, 10 `bounced`) | `leads.invite_status` |
| Registered | 1 | `leads.lifecycle_stage = 'registered'` |
| Verified | 1 (MERIDIAN MEP CONTRACTING LLC) | `leads.verified` |
| Confirmed capability suppliers | 1 | `supplier_capabilities.confirmed_at is not null` |
| Categories OPEN (≥ 10 verified) | **0 of 86** | `v_category_open` |
| Categories with any supply pipeline | 23 of 86 | `v_marketplace_liquidity` |
| Cash & Bank + Stripe Clearing | **AED −5,227.80** | `gl_account_balances` codes 1000, 1050 |
| Declared department budgets | AED 1,700 / month (9 departments) | `sum(department_budget.monthly_aed)` |
| AI spend, trailing 30 days | AED 154.22 over 2,954 calls | `ai_cost_log` |
| Go-live switches | `invite_enabled=false`, `bd_outreach_enabled=false`, `marketing_golive=false`, `supplier_outreach_golive=false`, `meta_autospend_golive=false` | `app_secrets` |
| Reveal fee | 3%, no cap, no discount (constraint-enforced) | `pricing_config`, `company_policy_decision.reveal_no_discount_no_cap` |
| Exec department library | **does not exist** — `dept_library` has rows for legal 451, marketplace 361, assurance 318, finance 290, company 36, and none for `exec` | `dept_library` |
| Exec senior-expert knowledge | **does not exist** — `ops_knowledge where dept_key='exec'` = 295 rows, of which 0 have `source_authority = 'senior_expert_uae'` (finance has 94, legal 90) | `ops_knowledge` |
| Certification exams sat by exec seats | **do not exist** — `certification_exam_result` has 22 rows for `bookkeeper`, `cs_support`, `marketing_analyst`, `procurement`, `security` only; none for `ceo`, `cpo`, `brief` | `certification_exam_result` |

---

## ceo — Chief Executive (AI)

Role of record: "CEO AI — company strategy, priorities, capital and risk." Responsibilities of record: "Sets quarterly
priorities and OKRs, approves major initiatives and budgets, monitors company_goals and risk, reviews department
performance. Does not create content." Authority of record (`employee_authority`): `escalate_founder`, `exec_review`,
`coordinate` — all `autonomous` at a **AED 100,000** threshold.

### 1. Question and decision taxonomy

| # | Question or decision | kind | How often | Who asks | What a wrong answer costs |
|---|---|---|---|---|---|
| C1 | What should we do to increase revenue? | diagnosis | weekly + on demand | founder, `brief` | The company spends a quarter on a stage that is not binding. At 358 days left and AED 85,028/month required, one wasted quarter removes 25% of the remaining horizon and cannot be bought back. |
| C2 | Are we going to survive the quarter? | forecast | monthly, and on any cash event | founder, `cfo` | A late "no" is a shutdown; a wrong "yes" spends reserve that was the only thing standing between the company and stopping. |
| C3 | Should we cut the reveal fee below 3%? | pricing | on demand, usually after a slow month | founder, `marketing`, `sales_director` | Cutting price to fix a liquidity problem destroys 1/3 of gross revenue per transaction and fixes nothing; also breaches a founder ruling and a DB constraint. |
| C4 | Which category do we open next? | sequencing | fortnightly | `supply`, `bd`, `procurement` | Opening a category whose pipeline cannot yield 10 verified suppliers burns the outreach budget and leaves the category dead — three dead categories with a healthy total is three dead categories. |
| C5 | Is the binding constraint still where it was last month? | diagnosis | monthly | `cpo`, `brief` | Every allocation made after the constraint moved is misallocated. |
| C6 | Which stage becomes binding once we fix this one? | sequencing | with C5 | `brief`, department heads | The company fixes one stage, celebrates, and discovers the next wall with no plan and less runway. |
| C7 | Should we raise the invite daily cap? | allocation | monthly | `supply`, `onboarding` | Too low and the supplier target is arithmetically unreachable (risk_register #19); too high and deliverability collapses and the domain is burned. |
| C8 | Should we spend on buyer acquisition before supply is verified? | sequencing | on demand | `marketing`, founder | Demand arriving at 0 open categories produces inquiries with no quotes, refunds and a permanently damaged first impression. |
| C9 | What is the cheapest experiment that would change a decision we are about to make? | forecast | before every non-trivial commitment | `cpo`, `brief` | Spending on information that cannot change the decision; or committing blind when AED 200 of measurement would have settled it. |
| C10 | Should we switch on `marketing_golive`? | gate | once, reversible | founder, `marketing` | Premature: paid traffic to an empty marketplace. Late: the funnel is never measured and `visitors_to_registration` stays uninstrumented. |
| C11 | Should we switch on `invite_enabled` / `supplier_outreach_golive`? | gate | once per channel | `supply` | Same shape as C10 on the supply side; also a deliverability and reputation risk (`email_domain_mx`, 10 bounces already). |
| C12 | Should paid inference (OpenRouter) be activated? | escalation | when engineering says the code is ready | `cto`, `cpo` | **Founder-reserved.** Activating without his word breaks a standing rule; refusing to prepare the case wastes his time when he asks. |
| C13 | Do we have the cash to commit to X? | gate | every commitment above the reserve rule | any department head | Committing past the reserve is the one error that ends the company rather than delaying it. |
| C14 | Which department gets the next AED of budget? | allocation | monthly | department heads | Budget to a non-binding department is activity, not revenue. |
| C15 | Should we open a second emirate, or KSA? | sequencing | quarterly | founder | Breadth before depth in a two-sided market multiplies the thin side; `feature_flags.ksa_market` is off for that reason. |
| C16 | Should we change the supplier registration fee or the free-1,000 cohort? | escalation | on demand | `cfo`, `bd` | **Founder-decided 6 Sep 2026 and marked never-ask-again.** Re-opening it wastes his attention and desynchronises 6 downstream readers. |
| C17 | Is a target unreachable, and should it be restated rather than missed? | diagnosis | quarterly | `cpo`, founder | A target nobody believes stops being an instrument; a target quietly lowered to be met is a lie in the ledger. |
| C18 | Should we declare a company-level risk? | gate | on any score change | `cpo`, `brief` | Declaring everything is noise; declaring nothing means the register is decoration. There is currently **no criterion in any row** for this. |
| C19 | Two departments are both within authority and disagree — who wins? | escalation | weekly | `brief` | An unarbitrated conflict idles the work; an arbitrary ruling teaches departments to escalate everything. |
| C20 | Is this quarter's plan capacity-feasible? | forecast | quarterly | `brief`, department heads | A plan that cannot physically produce the number is a plan to miss it and to blame execution afterwards. |
| C21 | What breaks first if inquiries start arriving tomorrow? | diagnosis | monthly | `cto`, `marketplace` | The company's one shot at a first impression is spent on an untested path. |
| C22 | Should a parked seat be re-activated? | allocation | on demand | `people_ops` | Head-count that does not touch the binding constraint adds AI cost and review load, not revenue. |
| C23 | Should a seat be retired or merged? | allocation | quarterly | `people_ops`, `cpo` | Retiring a seat that owns a handoff silently orphans the handoff (`v_handoff_without_contract`). |
| C24 | Is the company measurably better than last month? | diagnosis | monthly | founder | This is `cpo`'s answer; the CEO's job is to refuse a "yes" that rests on activity metrics. |
| C25 | What must the founder decide this week, and what is merely FYI? | craft | weekly | founder | Sending him non-decisions trains him to stop reading; withholding a real decision stalls the company. |
| C26 | Should we accept a buyer or supplier who would concentrate revenue? | gate | on occurrence | `bd`, `sales_director` | `strategy_risks` #41 already recorded 100% quote concentration once. Concentration is priced as risk, not celebrated as traction. |
| C27 | Is anonymity being circumvented? | diagnosis | monthly | `trust_safety_mgr`, `legal` | Anonymity before the reveal **is** the product; circumvention converts every future reveal fee to zero. The AED 15,000 / 3× rule is the only deterrent. |
| C28 | What is the expected value of opening category C versus category D? | allocation | fortnightly | `supply` | Same as C4 but as a ranking; a wrong ranking wastes the whole outreach quarter. |
| C29 | Should we buy a data source again (Apify etc.)? | allocation | on renewal | `cfo`, `data_intel` | Apify is paused to ~Feb 2027; restarting spend before the invite→register rate is measured buys more of an input that has produced 1 registration from 22,265 leads. |
| C30 | Is AED 1,000,000 by 31 Aug 2027 still the right target? | escalation | quarterly | founder | **Founder-owned.** The CEO may report the gap and the feasibility; changing the number is his. |
| C31 | Should the refund window, chase day or admin fee change? | escalation | on complaint | `cfo`, `legal` | **Founder-decided 6 Sep 2026, verbatim, never-ask-again.** |
| C32 | Which of our metrics is lying to us? | diagnosis | monthly | `cpo` | A scorecard with a unit error (see P4 in `cpo` §4) makes every decision downstream of it wrong in the same direction. |
| C33 | What is the runway? | forecast | monthly | founder, `cfo` | The ledger currently reports **negative** cash; a runway number computed over it is fiction. |
| C34 | Should we accept a liability we cannot price? | gate | on occurrence | `legal` | An indemnity or SLA the company cannot fund converts a marketing win into an existential exposure. |
| C35 | What is the path to the first dirham and how many weeks is it? | sequencing | monthly | founder | Every plan whose lead time exceeds the remaining horizon is a plan to miss, and must be said so on the day it is written. |
| C36 | Depth (10 verified in one category) or breadth (1 in ten)? | sequencing | fortnightly | `supply` | Breadth in a two-sided market yields 0 open categories, which is exactly the measured state today. |
| C37 | Is this department's plan serving a company goal, or itself? | diagnosis | weekly | `brief`, `cpo` | Departments that plan for themselves consume budget and produce no movement in `company_goals`. |
| C38 | Should the company stand down to preserve cash? | gate | on cash event | founder | `company_stand_down` exists (6 rows) — standing down late is a shutdown, standing down early forfeits the year. |
| C39 | A real fix made the headline number fall — what now? | craft | on occurrence | `cpo`, founder | Hiding it destroys the only honest instrument the company has; over-reporting it panics the founder. |
| C40 | Which founder-held fact is blocking the most decisions right now? | escalation | weekly | founder | He is emailed exceptions only; asking him for the wrong fact burns the channel. |
| C41 | Should the category-open threshold of 10 change? | escalation | on demand | `supply` | **Founder-decided 6 Sep 2026** (`pricing_config.category_open_min_suppliers = 10`). |
| C42 | Is the ledger's negative cash position real? | diagnosis → escalation | on sight | `cfo` | If real, the company is insolvent on its own books; if an artefact of unrecorded founder funding, every runway and break-even answer in the estate is computed on a false base. |
| C43 | Has a competitor changed its pricing or copied the anonymity mechanic? | diagnosis | quarterly | founder, `marketing` | The wedge is that 0 of 27 recorded competitors offer anonymity. The day one does, the product's defensibility changes and the 3% fee has to be re-argued from a different premise. |
| C44 | Are we priced out of the supplier side? | pricing | quarterly | `bd`, `cfo` | Biznex.ae charges vendors from AED 365/yr against QuotesDone's AED 1,000/yr — a 2.7× gap the supplier-acquisition seat is arguing against every day, and the CEO must know it before setting an outreach target. |

### 2. Domain logic (the models this seat reasons with)

Arithmetic only. Each model names its inputs, the live table or routine each comes from, and what is UNMEASURED.

#### M1 — Marketplace stock-and-flow with delays

The marketplace is a chain of stocks connected by rate-limited flows with lags. Revenue is the last stock in the chain,
so revenue this month was determined by flows set several lags ago. This is the model that makes "increase revenue"
answerable.

*Stocks (levels), measured 7 Sep 2026:*

| Stock | Symbol | Source | Value |
|---|---|---|---|
| Un-invited leads | L₀ | `leads where invite_status is null` | 22,094 |
| Invited, undecided | L₁ | `leads where invite_status='sent' and lifecycle_stage='no_response'` | 164 |
| Registered | L₂ | `leads where lifecycle_stage='registered'` | 1 |
| Verified (licence on file, unexpired) | L₃ | `leads where verified` | 1 |
| Confirmed capability in a category | L₄ | `supplier_capabilities where confirmed_at is not null` | 1 |
| Open categories | K | `v_category_open where is_open` | 0 |
| Registered buyers | B | `customers` | 1 |
| Live inquiries | I | `inquiries` | 0 |
| Quoted inquiries | Q | `distinct quotes.inquiry_id` | 0 |
| Paid reveals | R | `transactions where revealed_at is not null and refund_confirmed_at is null` | 0 |
| Cash | C | `gl_account_balances` 1000 + 1050 | AED −5,227.80 |

*Flows (per week) and their governing limits:*

| Flow | Governed by | Value |
|---|---|---|
| scrape → L₀ | `scrape_runs`; Apify paused to ~Feb 2027 | 25 runs recorded; rate currently 0 |
| L₀ → L₁ (invite) | `app_secrets.invite_daily_cap` (read by name, never printed; `risk_register` #19 records it as 10/day on 26 Jul 2026) and `invite_enabled` = **false** | 0 while the switch is off |
| L₁ → L₂ (register) | supplier's own decision | **0 observed from 161 sends** |
| L₂ → L₃ (verify) | `supplier_verification` seat | 1 of 1 |
| L₃ → L₄ (confirm a category) | `supplier_capability_confirmation` | 1 |
| B → I (post an inquiry) | buyer demand; `marketing_golive` = false | 0 |
| I → Q (fan out and receive a quote) | `decision_policy.match_max_fanout` 5, `match_max_fanout_per_trade` 3, `match_relevance_floor` 35, `matching_strike_limit` 3 | no observation |
| Q → R (pay to reveal) | buyer's decision, 3% of quote value | no observation |
| R → C (cash) | Stripe payout schedule | **does not exist** — the connector reports no payout has ever occurred |
| R → refund (leak) | `pricing_config`: chase day 3, founder call day 5, bank 7–14 working days | no observation |

*Delays (τ), the reason the model exists:*

| Delay | Source | Measured? |
|---|---|---|
| τ(invite→register) | `leads.invited_at` → `registration_submitted_at` | **UNMEASURED** — 0 registrations from 161 invites; the delay is censored, not long |
| τ(register→verify) | `registration_submitted_at` → `approved_at` | one observation only; not a rate |
| τ(verify→category confirmed) | `supplier_capability_confirmation` | one observation only |
| τ(inquiry→first quote) | `fn_supply_health()` computes `median_hours_to_first_quote` | **UNMEASURED** — null, 0 inquiries |
| τ(reveal→refund decision) | `pricing_config.refund_window_working_days` = 5, chase at 3 | **declared, never exercised** |
| τ(reveal→cash) | Stripe payout cadence | **does not exist** |
| τ(category open) | 10 verified suppliers must accumulate | derived from the above, therefore unmeasured |

*Procedure.* Weekly discrete time. For each stock `S` with upstream stock `U`, pass-through `p` and delay `τ` weeks:

```
S(t+1) = S(t) + p · outflow_U(t − τ) − outflow_S(t)
```

*Output.* (a) the projected R(t) for t = 1…52; (b) **pipeline lead time to the first dirham** = Στ along
lead→invite→register→verify→category-open→inquiry→quote→reveal→cash; (c) the week in which a flow set today first
shows up as cash.

*Honest state.* Five of the seven τ are unmeasured and four of the eight pass-throughs have never been observed, so
the model's only defensible output today is a **bound**, not a projection. The resolver must emit
`projection_state = 'bounded_not_forecast'` and name each unmeasured τ. Any seat that emits a point forecast from
this model with those inputs missing is fabricating.

#### M2 — Constraint-migration map

`fn_binding_constraint(p_days)` already exists and returns the lowest measured stage pass-through. It answers *where*
the constraint is. It does not answer *where it moves next*, which is the question a CEO with 358 days actually has.

*Formula.* Each stage `i` has a weekly capacity `Cᵢ` and a pass-through `pᵢ`. System throughput is

```
T = min over i of ( Cᵢ · Π_{j<i} pⱼ )
```

The binding stage is the argmin. The migration map is produced by relaxing one stage at a time:

```
for each stage i:
    T_i* = min over k≠i of ( C_k · Π_{j<k} p_j )      # throughput if stage i were uncapped
    successor(i) = argmin of that expression
emit the ordered chain: binding → successor(binding) → successor(successor(binding)) → …
with T at each step, until T ≥ the required rate from fn_revenue_trajectory()
```

*Capacity inputs and their sources:*

| Stage | Capacity source | State |
|---|---|---|
| invite | `app_secrets.invite_daily_cap` × 7, gated by `invite_enabled` | switch is off; capacity effectively 0 |
| register | none — supplier-side, no capacity, only a rate | rate unmeasured |
| verify | no declared capacity anywhere | **does not exist** |
| category open | `pricing_config.category_open_min_suppliers` = 10 | declared |
| match / fan out | `decision_policy.match_max_fanout` 5, `_per_trade` 3, `match_relevance_floor` 35 | declared |
| supplier response | `leads.rv_response_rate` | 2 rows only; see the unit defect in `cpo` §4 P4 |
| reveal | buyer decision, no cap | unmeasured |
| cash | Stripe payout cadence | **does not exist** |

*Measured output today.* `fn_binding_constraint(90)` returns `binding_stage = 'registration_to_inquiry'` at 0%
pass-through with **`stages_ranked = 1`**: three of four stages are excluded (two `no_demand`, one
`not_instrumented`). One ranked stage is not a ranking. The correct CEO answer today is therefore *"the binding
constraint is not known, because only one stage can be measured; the first move is to instrument
`visitors_to_registration`"* — which is exactly what the routine's own `reallocation_rule` says. The migration map is
built but returns `unknown` until at least three stages are measured.

#### M3 — Survival objective versus expected value

Two objectives that disagree, and a rule for which one governs.

*Expected value:* maximise `E[revenue over the horizon]`. *Survival:* maximise `P(C(t) ≥ reserve for all t ≤ T)`.

*Arithmetic:*

```
B      = monthly burn
       = sum(department_budget.monthly_aed)          = AED 1,700    (9 departments, period 2026-09)
       + measured AI spend                            = AED 154.22   (ai_cost_log, trailing 30 days)
       + subscriptions                                = read from `expenses` (20 rows) and `gl_journal`
C₀     = gl_account_balances(1000) + (1050)           = AED −5,227.80
runway = C₀ / B                                       = UNDEFINED — C₀ < 0
reserve_months = company_goals.cash_reserve.target    = 6   (declared; measure_sql is null, so never measured)
```

*Ruin-constrained decision rule.* Rank options by expected value, then **reject** any option whose worst-case
cumulative draw exceeds `C₀ − reserve_months · B`. With `C₀` negative, every discretionary commitment is rejected by
this rule and the seat's correct output is an escalation (see J-C1 in §4), not a ranking.

*Regime switch.* A pre-revenue company optimises survival; a company past break-even optimises expected value. The
switch condition is arithmetic:

```
switch to EV when reveals_30d ≥ v_unit_economics.breakeven_reveals_per_month
```

Measured: `reveals_30d = 0`; `breakeven_reveals_per_month` is **null** because `ai_cost_per_reveal_aed` is null
because reveals are zero. The switch cannot fire, which is the correct behaviour: the company stays in survival mode
by construction until the first reveal.

*Contradiction to resolve.* `company_economics` #9 states break-even against "department_budget total AED 7,700/month
declared" and `metric_definition.ai_cost_30d` carries a target of 7,700, while `sum(department_budget.monthly_aed)`
measured today is **AED 1,700**. The 7,700 figure is stale in two places. The resolver reads the sum, never the
sentence, and opens a task to correct the two rows.

#### M4 — Value-of-information arithmetic

*Expected value of perfect information*, for a decision between options `a` over an uncertain quantity `θ`:

```
EVPI = E_θ[ max_a U(a,θ) ]  −  max_a E_θ[ U(a,θ) ]
```

*Two-option, one-threshold form* (the form this seat actually uses). If option A is optimal when `θ < θ*` and B when
`θ ≥ θ*`, and A is optimal under the prior:

```
VOI = P(θ ≥ θ*) · ( U(B | θ ≥ θ*) − U(A | θ ≥ θ*) )
```

*Decision rule:* run the experiment **iff** `VOI > cost_of_experiment` **and** the experiment finishes before the
decision must be taken (the lead time comes from M1). An experiment that cannot flip any option has VOI = 0 no matter
how interesting it is.

*Conjugate posterior for a conversion rate the company has never observed.* With a Beta(1,1) prior and `k` successes
in `n` trials, the posterior mean is `(k+1)/(n+2)`; when `k = 0` the 95% upper bound is well approximated by the rule
of three, `3/n`.

*Worked, on measured production data — the single most decisive piece of arithmetic available to this seat today:*

```
invites sent            n = 161            (leads.invite_status = 'sent')
registrations from them k = 0              (leads.lifecycle_stage = 'registered' from an invite: 0)
posterior mean p̂       = 1/163            = 0.61%
95% upper bound         ≈ 3/161            = 1.86%
```

Consequences, all arithmetic:

- Whole scraped pool: `22,265 × 1.86% = 414` registrations at the **upper** bound. The company goal
  `suppliers_verified = 2,000` is unreachable from the existing lead pool through the existing invite channel, even
  if every remaining lead is invited and the true rate is at the top of its confidence interval.
- Category feasibility: reaching 10 verified suppliers needs `10 / 0.0186 = 538` leads in that category at the upper
  bound. Measured: **16 of 86 categories** hold ≥ 538 leads in pipeline; 22 hold ≥ 100; 23 hold any at all.
- At the recorded invite cap of 10/day: `10 × 1.86% × 365 = 68` registrations per year, upper bound.

The highest-VOI action available is therefore not a bigger scrape or a bigger budget — it is any cheap intervention
that produces a **non-zero** registration count, because `k = 0` is what makes every downstream number a bound rather
than a plan. Cost of that experiment: one invite batch under the existing cap, AED 0 of new spend. VOI: it decides
whether the supply channel exists at all.

#### M5 — Revenue back-solve

```
revenue = reveal_revenue + supplier_registration_revenue
reveal_revenue           = N_reveals × 0.03 × V            (V = accepted quote value, AED)
registration_revenue     = max(0, registrations − 1000) × AED 1,000     (founder rule, no date)
```

Registration revenue in year one is **AED 0** by arithmetic, not by opinion: the free cohort is the first 1,000
registrations, and the upper bound on registrations from the entire lead pool is 414. So 100% of the AED 1,000,000
must come from reveal fees.

`V` has never been observed (`quotes` = 0), so the seat emits a table, never a single number:

| Average accepted quote V (AED) | Reveal fee (AED) | Reveals needed for AED 1,000,000 | Reveals / month over 11.76 months |
|---|---|---|---|
| 25,000 | 750 | 1,334 | 113 |
| 50,000 | 1,500 | 667 | 57 |
| 100,000 | 3,000 | 334 | 28 |
| 250,000 | 7,500 | 134 | 12 |

Chained back through the company's own declared conversion targets (`quote_conversion_rate` 25%,
`rfq_completion_rate` 80%), at V = AED 100,000: 28 reveals/month → 112 quoted inquiries/month → **140 inquiries per
month**, against a demand instrument (`metric_definition.inquiries_7d`) whose target of 50/week ≈ 217/month. The two
targets are consistent within a factor of 1.5; neither has ever been observed.

#### M6 — Category opening rank

For each of the 86 catalogue categories:

```
gap_c        = max(0, 10 − verified_c)                     # pricing_config.category_open_min_suppliers
leads_needed = gap_c / p_register                          # p_register upper bound 1.86% from M4
feasible_c   = ( suppliers_in_pipeline_c ≥ leads_needed )
demand_c     = inquiries_c                                 # v_marketplace_liquidity — 0 for all 86
score_c      = feasible_c · ( demand_c + prior_demand_c )
```

Measured today: `verified_c ≤ 1` for every category, so `gap_c ≥ 9` everywhere; `leads_needed ≈ 484–538`;
`feasible_c` is true for the 16 categories holding ≥ 538 leads, headed by construction-materials-suppliers (3,689),
fit-out-contractors (1,677), paints-and-finishing (1,395), flooring (1,393), electrical (1,347).
`demand_c = 0` for all 86, so **the demand term is unmeasured and the ranking today is supply-feasibility only**.
The resolver must say so in the answer rather than presenting a supply ranking as a demand ranking.
`prior_demand_c` — a demand prior per category (search volume, tender frequency, UAE construction spend by trade) —
**does not exist** in this estate.

#### M7 — Plan capacity feasibility

```
for each quarter target:
    required_rate  = fn_revenue_trajectory().required_per_month
    achievable     = T from M2 at the current capacities
    verdict        = achievable ≥ required_rate ? FEASIBLE : INFEASIBLE
    if INFEASIBLE:  name the stage whose capacity is the argmin and the multiple needed
```

This is the routine that converts "the plan says AED 85,028/month" into "the invite stage would have to run at
N× its recorded cap for that to be possible", which is the sentence the founder can act on.

#### M8 — Reveal-fee sensitivity

```
revenue = N · f · V         (f = fee rate)
d(revenue)/revenue = dN/N + df/f
```

Cutting `f` from 3% to 2% is a 33.3% cut in revenue per reveal; break-even requires `N` to rise by
`0.03/0.02 − 1 = 50%`. There is **no measured price elasticity** — 0 reveals have ever been priced — so the required
50% lift has zero evidence behind it. Independently, `pricing_config` carries a CHECK constraint
(`pricing_config_no_discount_no_cap_ck`) forbidding any discount or cap, recorded as founder ruling
`company_policy_decision.reveal_no_discount_no_cap`. The resolver's output is a refusal that cites both.

### 3. Reasoning procedures

**P-C1 — "What should we do to increase revenue?" (C1)**

1. Read `fn_revenue_trajectory()`. Record `gap_to_target`, `days_remaining`, `required_per_month`. If
   `measured = false`, stop and return the refusal naming `not_measured_reason`.
2. Read `fn_binding_constraint(90)`. If `stages_ranked < 3`, **stop generating options**: return
   "the binding constraint is not known — N of 4 stages cannot be measured", list the excluded stages with their
   reasons, and emit exactly one recommended action: instrument the excluded stage with the largest upstream stock.
   *(This is the answer today: `stages_ranked = 1`.)*
3. If `stages_ranked ≥ 3`, take the binding stage. Build the migration map (M2) so the answer names not only the
   current wall but the next two.
4. Generate options **only from the catalogue of levers that touch the binding stage** — the levers are enumerated,
   not invented: `app_secrets.invite_daily_cap`, `invite_enabled`, `bd_outreach_enabled`, `marketing_golive`,
   `meta_daily_budget_cap_aed`, `decision_policy.match_max_fanout`, `match_relevance_floor`, `matching_strike_limit`,
   `pricing_config.category_open_min_suppliers`, `department_budget.monthly_aed` per department, category selection
   from M6, `company_stand_down`.
5. Score each option: `Δthroughput at the binding stage × Π downstream pass-throughs × 0.03 × V`, using the M5 table
   for `V` rather than a single value.
6. Apply the ruin constraint (M3). Delete every option whose worst-case draw exceeds `C₀ − 6B`.
7. Apply the judgement rules in §4 in order. Any option that trips a red line is removed with the rule id printed.
8. Rank the survivors. Compute the **flip condition** for the top two: the value of the one input at which the
   ranking reverses, and where that input would be measured.
9. Compose the memo (§ "Composition" below). Cite the row behind every number.

**Stop and refuse when:** `fn_revenue_trajectory().measured = false`; or `stages_ranked = 0`; or the newest
`v_bi_scorecard.taken_at` is older than 24 hours; or an option's score depends on a pass-through with `n = 0`
observations and no bound can be stated.

**P-C2 — "Are we going to survive the quarter?" (C2, C33)**

1. `C₀` from `gl_account_balances` 1000 + 1050. If `C₀ < 0` → **do not compute a runway.** Return
   `state = 'ledger_negative'`, the amount, and escalate: either the company is insolvent on its own books or the
   founder is funding it outside the ledger, and only he holds that fact (`founder_mail_policy` kind required).
   *This is the measured state today: AED −5,227.80.*
2. `B` from `sum(department_budget.monthly_aed)` for the current `period_label`, plus `ai_cost_log` trailing 30 days,
   plus recurring `expenses`. Do not use the 7,700 sentence in `company_economics` #9 (M3).
3. `inflow` from `transactions` over the same window (0 today) — never from a forecast.
4. `months_of_cash = C₀ / (B − inflow)` when `C₀ > 0`.
5. Verdict bands: `< 3` → RED with a stand-down option costed; `3–6` → AMBER, discretionary spend frozen;
   `> 6` → GREEN.
6. Every verdict cites `department_budget.updated_at` and the `ai_cost_log` window so the founder can see the age of
   the inputs.

**P-C3 — "Should we cut the reveal fee?" (C3)**

1. Read `pricing_config`. Detect the CHECK constraint and the founder ruling
   `company_policy_decision.reveal_no_discount_no_cap` (`never_ask_again = true`).
2. Return a refusal, not an analysis: *"3% with no cap and no discount is the founder's decision of 6 Sep 2026,
   enforced by a database constraint; it is marked never-ask-again."*
3. Attach the arithmetic anyway (M8), because the person asking usually has a liquidity problem wearing a pricing
   costume: state that a 2% fee needs 50% more reveals to stand still, that elasticity is unmeasured at n = 0, and
   that the binding stage is not price.
   Add the competitive context from `public.competitor` (27 sourced rows, verified 2026-07-27): the buyer-side
   comparators charge the *supplier*, not the buyer — RFQsNow AED 1,200/month plus AED 800–8,000 per unlocked RFQ,
   Biznex from AED 365/year — and **none of the 27 offers anonymity**. QuotesDone's 3% is a buyer-side fee for a
   thing nobody else sells, so there is no like-for-like price to be undercut by.
4. Route the underlying problem to the binding stage's owner as a task.

**P-C4 — "Which category do we open next?" (C4, C28, C36)**

1. Pull all 86 rows of `v_marketplace_liquidity` and `v_category_open`.
2. Compute `gap_c`, `leads_needed` and `feasible_c` per M6 using the M4 upper bound for `p_register`.
3. If `sum(inquiries) = 0` across all categories, set `demand_term = unmeasured` and label the output
   **"supply-feasibility ranking, not a demand ranking"**. Do not silently rank on supply and call it a
   recommendation.
4. Rank the feasible set by pipeline depth; break ties by `catalog_category_domain` concentration (one domain, one
   outreach template, one specialist seat) rather than by alphabetical or category number.
5. Apply J-C6 (regulated categories) and J-C8 (depth before breadth).
6. Emit the top three with, for each: leads in pipeline, gap to 10, invites required at the upper bound, invites
   required at the posterior mean, and the flip condition — the measured `p_register` above which a shallower
   category overtakes.

**P-C5 — "Which stage becomes binding next?" (C5, C6)**

1. `fn_binding_constraint(30)`, `(90)` and `(180)`. Compare `binding_stage` across the three windows; a stage that is
   binding at 30 days but not at 180 is a recent regression, not a structural constraint, and gets a different owner.
2. Build the migration chain (M2).
3. For each link, state the throughput ceiling and the required rate from `fn_revenue_trajectory()`. Stop the chain
   at the first step where throughput ≥ required rate, and report how many walls stand between here and the target.
4. If any stage in the chain is `not_instrumented`, the chain is truncated there and the answer says so.

**P-C6 — "What is the cheapest experiment worth running?" (C9)**

1. Enumerate the decisions due in the next 30 days from `org_tasks` where `dept_key='exec'` and `decision_record`.
2. For each, identify the one uncertain input whose value flips the decision, and the threshold `θ*`.
3. Compute VOI per M4 with the current posterior over `θ`.
4. Enumerate candidate experiments from a fixed catalogue: an invite batch under the existing cap; a single-category
   depth push; instrumenting `visitors_to_registration`; a demand probe in one category; switching one go-live flag
   for a bounded window.
5. Cost each from `department_budget` and `ai_cost_log` unit costs. Duration from M1's delays.
6. Rank by `VOI / cost`, delete any whose duration exceeds the decision date, and return the top one with the
   decision it settles.

**P-C7 — "Is this plan capacity-feasible?" (C20, C35)**

1. `required_per_month` from `fn_revenue_trajectory()`.
2. `T` from M2 at current capacities.
3. `lead_time` = Στ from M1. If `lead_time > days_remaining`, the plan is INFEASIBLE **on timing alone** regardless of
   capacity, and that is the headline.
4. If `T < required_rate`, name the argmin stage and print the multiple: "the invite stage would have to run at N×".
5. Never round an infeasible verdict up to "challenging".

**P-C8 — "What must the founder decide this week?" (C25, C40)**

1. Read `founder_mail_policy` for the permitted kinds. Anything without a policy row cannot be sent and becomes an
   owned org task via `fn_founder_mail_route`.
2. Collect candidates: items in `founder_review_gates` (refunds only), facts only he holds
   (from `docs/KNOWLEDGE_PLAN_2026-09-06.md` §5 open rows — today: UBO filing status), money above AED 10,000,
   destructive production changes.
3. Rank by cost of delay = (revenue at risk per week) × (weeks blocked).
4. Emit at most three decisions plus a one-line FYI block. If there are no real decisions, say so — an empty
   decisions section is a valid brief and is better than a manufactured one.

### 4. Judgement rules

Each rule is condition → verdict → reason, and each is testable against a row.

| id | Condition | Verdict | Reason |
|---|---|---|---|
| J-C1 | `gl_account_balances(1000)+(1050) < 0` | Refuse every discretionary commitment; escalate the ledger itself | A negative recorded cash balance makes runway, break-even and every ROI in the estate fiction. Fix the instrument before spending against it. |
| J-C2 | `fn_binding_constraint().stages_ranked < 3` | Do not recommend a reallocation | One or two ranked stages is not a ranking. The routine's own `reallocation_rule` says instrument first. |
| J-C3 | A conversion rate has `n = 0` observations | Quote the rule-of-three upper bound, never a point estimate | `k=0` from `n` trials bounds the rate at 3/n; presenting 0% as the rate is as wrong as presenting 5%. |
| J-C4 | An option's payback exceeds `days_remaining` from `fn_revenue_trajectory()` | Reject even if its NPV is the highest | An investment that matures after the deadline scores well and cannot count. |
| J-C5 | Worst-case cash draw > `C₀ − 6·B` | Reject regardless of expected value | Survival dominates EV until the break-even switch fires. Ruin is absorbing. |
| J-C6 | Category is in `decision_policy.sensitive_categories` (fire, security, electrical, structural, gas, lifts, medical) | Do not open on supply feasibility alone; require licence-activity evidence | Safety and liability categories cost trust, and trust is the whole product. |
| J-C7 | `demand_c` unmeasured for every category | Label any category ranking "supply-feasibility only" | An instrument measuring supply and captioned "demand" is the estate's most-repeated defect. |
| J-C8 | `verified` suppliers < 10 in every category | Depth before breadth: put all outreach into one feasible category | 0 of 86 categories are OPEN today; 86 categories at 1 supplier is worth exactly nothing, one category at 10 is a live market. |
| J-C9 | `marketing_golive = true` proposed while `v_category_open` has 0 open categories | Reject | Paid demand into a marketplace that cannot quote produces refunds and a burnt first impression. |
| J-C10 | An action would move money above AED 10,000, or is destructive/irreversible in production | Escalate to the founder | Founder's standing rules, `company_policy_decision.founder_standing_rules`. |
| J-C11 | The question is refunds, reveal pricing, supplier registration pricing, the category-open threshold, the AED 1M target, Corporate Tax, VAT, or the auditor | Answer from `company_policy_decision` and refuse to re-open | All are marked `never_ask_again = true`. Re-asking a settled question is a cost, not diligence. |
| J-C12 | Activating paid inference (OpenRouter) | Never autonomous; prepare the case, wait for his word | `company_policy_decision.openrouter_credit`: paid inference is HELD until he activates it. |
| J-C13 | A department's proposal names no `company_goals.key` it moves | Return it unapproved | `metric` without a goal is activity. `brief` #14 in `risk_register` records this failure mode already. |
| J-C14 | A real fix makes a headline number fall | Report the fall, with the cause, in the same brief | Never fabricate, back-date or mass-close to hold a number up. This is a founder hard rule. |
| J-C15 | Two figures for the same quantity disagree (e.g. burn AED 1,700 measured vs AED 7,700 in `company_economics` #9) | Use the measured sum, name the stale row, open a correction task | A stale sentence in a knowledge row outranks nothing; it is a defect with a location. |
| J-C16 | A single supplier or buyer would exceed 30% of quotes or revenue | Flag as a concentration risk in `strategy_risks`, do not celebrate it | Already recorded once at 100% (`strategy_risks` #41). |
| J-C17 | Evidence newer than the decision is available but not read (`v_bi_scorecard.taken_at` > 24h old) | Refuse and refresh | The seat's own knowledge row says quote operational numbers only from live state. |
| J-C18 | A target is arithmetically unreachable at maximum capacity | Say so plainly in the same cycle it becomes true | A target nobody believes stops working as an instrument; the honest move is to restate it to the founder, never to quietly lower it. |
| J-C19 | An option scores best but depends on a switch the founder has not turned on | Present it as a decision for him, not as a plan | `marketing_golive`, `meta_autospend_golive`, `invite_enabled` are his switches. |
| J-C20 | Anonymity circumvention is detected | Treat as a P0 product risk, not a commercial dispute | Anonymity before the reveal is the entire product; the AED 15,000 / 3× rule is the only deterrent the company has. |
| J-C21 | An answer would need a number the estate does not hold | Return "cannot answer", name the missing table and open the task | The alternative — a plausible number — is the failure this whole plan exists to prevent. |

### 5. Technical knowledge

The seat must hold, as stored records it can read without asking anyone:

- **The revenue and constraint routines and their exact semantics:** `fn_revenue_trajectory()` (STABLE; executes
  `company_goals.measure_sql` live; nulls propagate rather than defaulting), `fn_binding_constraint(p_days)` (STABLE;
  excludes `not_instrumented` and `no_demand` stages from the ranking), `fn_goal_attainment(p_horizon)`,
  `fn_goal_pace()`, `fn_company_situation()`, `fn_company_state()`, `fn_health_index()`, `fn_revenue_cascade(dept,
  role)`, `fn_finance_forecast()`, `fn_strategy_metrics()`, `fn_dept_decision_thresholds(dept)`,
  `fn_cost_per_os(days)`, `fn_budget_available(dept)`, `fn_decision_outcomes(kind, days)`.
- **Which routines write.** `fn_supply_health()`, `fn_strategy_scan()`, `fn_exec_meeting()`, `fn_founder_brief()`,
  `fn_decision_gate()` and `fn_strategy_ai()` are VOLATILE and insert rows (`agent_runs`, `agent_actions`,
  `notifications`). A read-only question must never call them. The seat needs this list stored, because calling a
  writer to answer a question is how a probe pages the founder.
- **The views:** `v_unit_economics` (the single row that says PRE-REVENUE and holds `breakeven_reveals_per_month`),
  `v_bi_scorecard` (14 metrics with `state` and `taken_at`), `v_marketplace_liquidity` (86 rows, `liquidity_status`),
  `v_category_open` (`is_open`, `min_required`), `v_business_health`, `v_department_health`, `v_founder_inbox`,
  `v_phase_c_what_reaches_the_founder`, `v_resource_pressure`, `v_customer_ltv`, `v_payment_health`.
- **The switch surface:** `app_secrets` keys `invite_enabled`, `bd_outreach_enabled`, `marketing_golive`,
  `supplier_outreach_golive`, `meta_autospend_golive`, `meta_sync_enabled`, `invite_daily_cap`,
  `meta_daily_budget_cap_aed`, `agent_autonomy_enabled`, `email_enabled`. Read by name inside a routine; **values are
  never printed** and secrets are never emitted into a memo.
- **The escalation plumbing:** `founder_mail_policy` (61 rows; a new notification kind needs a policy row or it is
  silently routed), `fn_founder_mail_route`, `fn_notify_founder(p_kind, …)`, `decision_policy.founder_review_gates`
  = `['refund_decision','refund_outside_policy']` and nothing else, `decision_policy.apex_backup` = `ops_director`,
  `phase_c_action_class.founder_approval_required`.
- **The decision record contract:** `decision_record`, `decision_log`, `decision_trace`, `fn_write_decision_trace(p)`,
  `fn_seal_decision_trace(id)`, `v_decision_trace_incomplete`, `v_executions_without_decision_trace`. Every CEO
  decision leaves a trace row or it did not happen.
- **Money and ledger mechanics:** `gl_accounts` (30), `gl_account_balances`, `gl_journal` / `gl_journal_lines`,
  `gl_expense_map`, `expenses`, `department_budget` (`degrade_at_pct` 70, `halt_at_pct` 95), Stripe: `stripe_events`
  (4 rows), PSP fee 2.9% + AED 1, `supplier_dues`, `ap_open_bills`.
- **Currency, units and calendar:** AED throughout; Dubai is UTC+4 and every stored timestamp is UTC; the UAE working
  week and `public_holidays` / `company_calendar` (55 rows); "working days" in the refund ladder means UAE working
  days, not calendar days.
- **The knowledge substrate it answers from:** `ops_knowledge` (`dept_key`, `record_type`, `deterministic`,
  `embedding_gte`), `fn_ops_knowledge_search(dept, query, limit)`, `fn_company_knowledge_search(question, limit)`,
  `fn_company_hard_rules()`, `fn_agent_context(text,int)`, `pg_trgm` `word_similarity` / `strict_word_similarity` for
  the lexical half of type matching.
- **What it must not do:** call a paid model; write to production from a read question; print a secret; send mail to a
  real address outside a `rehearsal_window`; approve anything that belongs to the founder's two refund gates.

### 6. Academic knowledge

Theory that generalises, each with a lawful primary source this estate may ingest. No copyrighted study texts.

| Discipline | Framework the seat needs | Lawful primary source |
|---|---|---|
| System dynamics | Stocks, flows, delays, the bullwhip effect; why a marketplace responds to a policy change months later (M1) | MIT OpenCourseWare 15.871 *Introduction to System Dynamics* (OCW, open licence); NIST/NASA systems-engineering handbooks (public domain) |
| Theory of constraints / queueing | Identify–exploit–subordinate–elevate; Little's Law `L = λW`; why elevating a non-binding stage changes nothing (M2) | Public queueing-theory lecture notes under open licence; ITU-T E-series traffic-engineering recommendations (standards body) |
| Decision analysis | EVPI / EVSI, decision trees, threshold ("flip") analysis, sensitivity analysis (M4) | ISO 31010 *Risk management — risk assessment techniques* (standards body, licensed copy); NIST SP 800-30 rev.1 risk-assessment guide (US government, freely redistributable — used for method only, not US law) |
| Probability and inference | Beta-binomial conjugacy, rule of three for zero-event data, censored observations (M4) | NIST/SEMATECH *e-Handbook of Statistical Methods* (US Dept of Commerce, public domain) |
| Ruin theory / capital adequacy | Probability of ruin, reserve requirements, why EV maximisation is wrong near zero (M3) | Basel Committee published frameworks (BIS, freely published) for the reserve-and-buffer logic only |
| Two-sided market economics | Cross-side network effects, chicken-and-egg, take-rate defence, single-homing vs multi-homing | Open-access journal articles under CC-BY; OECD Competition Committee published papers on platform markets (freely published) |
| Procurement and category management | Category strategy, supplier segmentation, prequalification, the RFQ lifecycle | UNCITRAL Model Law on Public Procurement (UN, freely published); CIPS published Level 6 syllabus outline (the certification the seat holds); ISO 20400 *Sustainable procurement* |
| Corporate governance and finance | Board reporting, capital allocation, financial statements, internal control | IFRS Foundation freely published standards summaries; COSO framework executive summary (freely published); UAE Federal Decree-Law 32/2021 (Commercial Companies) from the official gazette |
| UAE market context | Mainland vs free-zone supplier landscape, LPO culture, 30–90 day terms, tender norms, seasonality | Dubai DET published licensing guidance; Ministry of Economy and Federal Competitiveness and Statistics Centre published datasets; Dubai Economic Agenda D33 published text; TDRA and MoIAT/ESMA published standards lists |
| Project and programme management | Scope/schedule/risk discipline, the business-environment domain | PMI published PMP *Examination Content Outline* (freely published by PMI — the syllabus, not a study guide) |

**Certifications on record for this seat** (`public.role_certification`, created 7 Sep 2026):

| rank | Certification | Issuing body | Pass mark | Syllabus areas |
|---|---|---|---|---|
| 1 | CPA (Certified Public Accountant) | AICPA/NASBA | 75% | Auditing and Attestation; Financial Accounting and Reporting; Taxation and Regulation; Business Environment and Concepts; Ethics and Professional Responsibilities |
| 2 | MCIPS (CIPS Level 6 Professional Diploma) | CIPS | 50% | Strategic Ethical Leadership; Global Commercial Strategy; Global Strategic Supply Chain Operations; Category Management; Supply Network Design; Strategic Programme Leadership |
| 3 | PMP (Project Management Professional) | PMI | 61% | People; Process; Business Environment; Predictive Plan-Based Methodologies; Agile and Hybrid Approaches |

**Syllabus areas failed: does not exist.** `certification_exam_result` holds 22 rows and none is for `ceo` — this
seat has never sat any of its three certifications, so there is no failed-area list to cross-reference. The only exam
this seat has taken is the internal knowledge exam (`knowledge_exam_results`): 36 graded answers — 8 correct,
11 partial, 9 wrong, 7 not_covered, 1 unverifiable. Note for whoever builds the exam: with a 75% pass mark, the CPA
is the hardest bar in the estate and the seat has 0 attempts; sitting it is a prerequisite to claiming the seat
operates at senior standard.

**Corpus gap, measured.** `ops_knowledge where dept_key='exec'` = 295 rows, **0** with
`source_authority = 'senior_expert_uae'` (finance holds 94, legal 90). `dept_library` for `exec`: **0 rows**. The exec
`kb_chunks` corpus (60,206 chunks per the 6 Sep knowledge audit) is WEF reports, OpenStax textbooks, JPMorgan annual
reports, Kahneman, Porter and Rumelt, with no UAE/GCC market or marketplace-economics source among the 25 largest.
The academic layer above is therefore an ingest plan, not a description of what is there.

### 7. Corporate knowledge

What this seat must know about QuotesDone specifically, and where each item lives today.

**Founder rulings it must never re-open** (`company_policy_decision`, all `never_ask_again = true`):
`founder_standing_rules`, `every_refund_is_the_founders` (17 Aug 2026), `refund_ladder` (5 working days, chase at 3,
banks 7–14), `refund admin fee AED 250 + 9% p.a.` (`decision_policy.refund_policy_founder_decision_2026_09_06`,
verbatim), `reveal_no_discount_no_cap` (3%, no cap, no coupon, no free reveal — constraint-enforced),
`supplier_pricing` (free for the first 1,000 registrations, AED 1,000/yr thereafter, no calendar date),
`category_open_threshold` (10 verified registered suppliers), `finance_budget` (no limit until profitable),
`corporate_tax`, `auditor`, `meta_token_and_daily_cap` (AED 30/day), `no_founder_cpl_target`, `openrouter_credit`.

**The pricing and economics of record:** `pricing_config` (one row: reveal 3% promo and standard, cap 99,999,999 =
no cap, supplier_free_count 1,000, supplier_reg_fee AED 1,000/yr, refund window 5 working days, chase 3,
bank settlement 7–14, category_open_min_suppliers 10, auto_approve_suppliers true) and `company_economics` (10 rows,
all `every_employee_must_know`: revenue model, reveal fee, supplier registration, the liquidity constraint,
contribution margin per reveal, CAC supplier, CAC buyer, LTV buyer, break-even, what destroys the economics). Row #9's
"AED 7,700/month" is stale against a measured `department_budget` sum of AED 1,700.

**Company identity:** `company_registration` — DET Dubai Trader Licence 1633275, trade name "quotesdone
technologies", issued 25 Jun 2026, expires **24 Jun 2027** (inside the target horizon — a renewal the CEO must
diarise), owner Ahmad Mhd Nabil Alzain 100%, activities 722901 and 724003, DE@AE Tier 1 home-registered digital
business, not VAT-registered until AED 375,000 taxable supplies, no Corporate Tax registration, no auditor.
`company_vision` — vision, mission and the autonomy principles.

**The goal tree:** `company_goals` — 64 rows, **all 64 active**. The exec department owns exactly **two**:
`autonomous_decision_rate` (≥ 90% monthly, has `measure_sql`) and `human_intervention` (≤ 2% monthly, has
`measure_sql`). The revenue target `revenue_annual` is owned by **finance**, not exec — a structural fact this seat
must know, because it means the CEO influences the company's headline number entirely through other departments.
Of the 64 active goals, **32** carry `no_measure_reason` instead of `measure_sql` — 20 "NO INSTRUMENT EXISTS" and 12
"THE NUMERATOR AND DENOMINATOR ARE A BUSINESS DECISION".

**Its own KPI:** `employee_kpi` id 34, "CEO AI — primary objective", metric "Company goals with active work and no red
status", target 100%, cadence weekly, `serves_goal = revenue_annual`, measured 93.75% at 2026-09-07 03:30 UTC. It
measures whether goals have open tasks — **not** whether the company earned anything. The CEO must know that its own
KPI would read 93.75% on a day of zero revenue, and must never present it as a health score.

**Its authority:** `employee_authority` — `escalate_founder`, `exec_review`, `coordinate`, all autonomous at AED
100,000. Against `decision_policy.auto_action_max_aed = 0` (agents never move money without a human) and
`financial_review_aed = 10,000`. The AED 100,000 in `employee_authority` is a review threshold, not a spending
mandate; the seat must not read it as one.

**Workflows it owns or sits in:** `employee_workflow` — `strategic_review` (step actor), `employee_task` (approver),
`campaign_publishing` (approver). `org_workflow_ownership`, `workflow_step`.

**Who it hands to:** `brief` (Chief of Staff, its standing deputy, arbiter in governance rules 5 and 9, third step of
the approval hierarchy); `cpo` (performance diagnosis, the weekly review, quality gates); `cfo`/finance (owner of
`revenue_annual`); `ops_director` (`decision_policy.apex_backup`); the founder, for refunds only.

**History it must not forget:**
- `risk_register` #18 (open, owner `ceo`): "Marketplace go-live gated behind three unreviewed boolean switches —
  invite_enabled, bd_outreach_enabled and marketing_golive are all false. Every zero metric depends on it." Raised
  26 Jul 2026, still open on 7 Sep 2026.
- `risk_register` #19 (open): invite throughput cannot reach the year-one supplier target at a cap of 10/day.
- `strategy_risks` #3: "Negative cash position … −5,227.80 AED" — status `closed`, updated 7 Sep 2026, while the
  ledger still reads −5,227.80. A risk closed while its condition holds is a defect, not a resolution.
- `employee_kpi` id 71 was retired 6 Aug 2026 because it selected from `fn_kpi_scoreboard()` inside the scoreboard and
  recursed to statement timeout — one row made all 95 KPIs unmeasurable. The lesson (a measure must not read the
  instrument it is part of) belongs to this seat as much as to `cpo`.
- `review_chain`, measured 7 Sep 2026: of the CEO's 667 authored rows, **every one of the 330 that reached a decision
  was `escalate`** (plus 7 `owned` and 330 still undecided). As reviewer it recorded 822 `approve`, 301 `owned` and
  **1** `reject`. A seat whose own work only ever escalates, and whose reviewing rejects once in 1,124, is not
  exercising either function.

**The competitor map, which does exist and this seat must hold.** `public.competitor` holds **27 rows**, every one
carrying a `source_url` and `verified_at = 2026-07-27`: 6 marked `high` threat, 13 `medium`, 8 `low`, across
6 tender portals, 6 directories, 5 marketplaces, 4 global platforms, 4 adjacent players and 2 recorded incumbent
behaviours (Google Search/Maps, and "WhatsApp to three known contractors"). The decisive measured fact:
**0 of the 27 offer anonymity** (`offers_anonymity = false` on every row) — the QuotesDone wedge is evidenced, not
asserted. Two competitor prices the CEO must carry: RFQsNow charges suppliers AED 1,200/month plus AED 800–8,000 to
unlock a single RFQ plus AED 1,500 verification; Biznex.ae charges vendors from AED 365/year against QuotesDone's
AED 1,000/year. `market_intel`, by contrast, has **0 rows**, which is what `strategy_risks` #5 records.

**What does not exist for this seat:** a UAE B2B procurement market primer; a demand prior per category; a criterion
for declaring a company-level risk; a worked decision record of any kind; a senior-expert knowledge layer for `exec`;
a `dept_library` for `exec`; a Stripe payout cadence; any *operational* benchmark (conversion rates, response times,
take-rate norms) — the competitor rows carry pricing and positioning, not funnel numbers.

### 8. One-year plan

**Objective.** Own the *path* to AED 1,000,000 by 31 Aug 2027 — the sequencing, the capital allocation and the
constraint work — while `finance` owns the number itself. Concretely: make the binding constraint knowable, then
move it, until the measured throughput of the funnel can produce AED 85,028/month.

**Metrics this seat owns (two, plus one it should own and does not):**

1. `autonomous_decision_rate` ≥ 90% monthly — `company_goals`, has `measure_sql`.
2. `human_intervention` ≤ 2% monthly — `company_goals`, has `measure_sql`.
3. *Proposed and does not exist:* **stages_ranked** — the count of funnel stages in `fn_binding_constraint()` that are
   in state `measured`. Today it is 1 of 4. Everything in this plan is downstream of it, and no goal or KPI in the
   estate measures it.

**Its slice of AED 1,000,000: AED 0 of direct revenue.** This seat books nothing. Its slice is the *enabling*
condition, and the honest statement is that **the AED 1,000,000 target is not achievable on the measured evidence**:

- 358 days remain and AED 85,027.93/month is required from a base of AED 0.
- Registration revenue is arithmetically AED 0 for the year (the free cohort is 1,000; the upper bound on
  registrations from the entire 22,265-lead pool is 414). So the whole target must come from 3% reveal fees.
- At an assumed average accepted quote of AED 100,000 — a value never observed — that is 334 reveals, 28 per month.
- A reveal requires an open category. **0 of 86 categories are open**, and opening one needs 10 verified suppliers
  against a measured verified count of 1 and an invite→register rate whose 95% upper bound is 1.86%.
- Every go-live switch that would start the flows is off, and turning them on is the founder's, not this seat's.

**What would make it achievable.** Not effort — the following, in this order, and each is checkable:

1. A **measured, non-zero** invite→register rate. Until `k > 0`, every plan is a bound. This is the single
   highest-VOI action in the company and costs nothing beyond the existing invite cap.
2. The founder switching on `invite_enabled` and `supplier_outreach_golive`.
3. One category taken to 10 verified suppliers (depth, not breadth). Construction-materials-suppliers holds 3,689
   leads — the only category where the upper-bound arithmetic clears the requirement with margin.
4. `visitors_to_registration` instrumented, so `stages_ranked` reaches 3 and the constraint becomes knowable.
5. A measured average quote value, which turns the M5 table into a single number.
6. The cash ledger reconciled, so survival arithmetic runs on a real base.

**Quarterly milestones (this seat's own work, all deterministic):**

| Quarter | Milestone | Verified by |
|---|---|---|
| Q1 (Sep–Nov 2026) | `stages_ranked ≥ 3`; the constraint-migration map returns a chain rather than `unknown`; the ledger's negative cash escalated and resolved; a measured `p_register` with `k > 0` or a written statement that the channel is dead | `fn_binding_constraint(90).stages_ranked`; `gl_account_balances`; `leads` registration count |
| Q2 (Dec 2026–Feb 2027) | One category OPEN (`v_category_open.is_open = true` for ≥ 1 row); first inquiry recorded; τ(inquiry→first quote) measured for the first time | `v_category_open`; `inquiries`; `fn_supply_health()` snapshot |
| Q3 (Mar–May 2027) | First paid reveal; `v_unit_economics.breakeven_reveals_per_month` becomes non-null; the survival→EV switch condition evaluable | `transactions`; `v_unit_economics` |
| Q4 (Jun–Aug 2027) | Measured monthly revenue reported against AED 85,028 with the shortfall stated plainly; DET licence renewed before 24 Jun 2027 | `fn_revenue_trajectory()`; `company_registration.expires_on` |

**Capacity check.** This seat's own work — decisions, memos, escalations — has no throughput problem: `max_open_tasks`
50, `context assemblies/30d` 18, 6 runs in the last 7 days. It cannot itself produce revenue at any capacity. The
company's capacity to produce AED 85,028/month does not exist today at any stage of the funnel, and the honest
one-year plan says so on page one rather than at the end of Q4.

**Dependencies.** `supply` and `onboarding` for the invite and verification flows; `marketplace` for matching and
quote handling; `finance`/`cfo` for the ledger, break-even and the revenue goal it owns; `growth`/`marketing` for
demand and the `visitors_to_registration` instrument; `product_eng` for instrumenting the uninstrumented stage;
`cpo` for the measurement validity of everything above; the founder for five switches, the refund gate, and the
ledger fact only he holds.

### 9. What this seat cannot do without a model

1. **Reading an unstructured founder message** in natural language and deciding it is question type C4 rather than
   C28. The type matcher (lexical + `gte-small` cosine over stored exemplars) handles paraphrases of questions it has
   seen; a genuinely novel phrasing falls below threshold and produces an honest refusal naming the closest types.
   That is the designed behaviour, and it is a real limitation, not a bug.
2. **Composing prose for a novel situation.** The memo templates cover the 44 enumerated types. A situation outside
   all 44 gets a structured refusal with the evidence attached, not an essay.
3. **Reading an external document** — a new UAE regulation, a competitor's pricing page, a supplier's contract — and
   extracting the fact that changes a decision. Ingestion of external text is a model task; once ingested as a row,
   every use of it here is deterministic.
4. **Judging whether a category's demand prior is plausible** when the estate has no demand data at all. The
   arithmetic can rank supply feasibility; it cannot invent a demand estimate, and it must not.

Nothing in sections 1–8 depends on a model at run time. With OpenRouter switched off, this seat answers all 44
question types from SQL and arithmetic, and refuses honestly on the four cases above.

---

## brief — Chief of Staff

Role of record: "Chief of Staff — runs the company against objectives." Responsibilities of record: "Coordinates all
departments, resolves cross-department conflict, prioritises company work against company_goals, escalates strategy to
the CEO." Authority (`employee_authority`): `escalate_founder`, `exec_review`, `coordinate` — autonomous at AED
100,000. `manager_key = ceo`. The most active seat in exec: 139 runs in 7 days, 143 context assemblies in 30 days.

### 1. Question and decision taxonomy

| # | Question or decision | kind | How often | Who asks | What a wrong answer costs |
|---|---|---|---|---|---|
| B1 | Which department owns this request? | allocation | many times daily | any seat, the founder | An unowned request idles; a wrongly owned one is done badly by a seat without the knowledge. |
| B2 | This request is owned by nobody — who takes it? | allocation | weekly | `ceo` | Work that belongs to nobody is the most common cause of a stalled objective. |
| B3 | Does this belong to the founder at all? | escalation | daily | any seat | Sending him a non-refund breaks the exceptions-only channel; withholding a real one stalls the company. |
| B4 | What goes in today's founder brief, and what does not? | craft | daily | founder | A brief of FYIs trains him to stop reading it. |
| B5 | What is the single most important thing today (the BLUF)? | craft | daily | founder | A brief with no lead item is a list, and a list is not a brief. |
| B6 | This task has been open past its timer — why, and what unblocks it? | diagnosis | daily | department heads | An unexplained stall repeats; the same task stalls again next week for the same reason. |
| B7 | A handoff was never accepted — who is accountable? | diagnosis | daily | `v_handoff_stalled` | Work sitting between two seats belongs to neither and is invisible in every department's numbers. |
| B8 | Should this deliverable be approved, returned or escalated? | gate | many times daily | every authoring seat | Approving 2,554 of 2,554 as reviewer (measured 7 Sep) means the review adds nothing; returning everything stops the company. |
| B9 | On what specific ground is this deliverable returned? | gate | with B8 | the author | A return without a named `violated_rule` cannot be learned from. |
| B10 | Two departments are both within authority and disagree — how is it settled? | escalation | weekly | department heads | An idle conflict is a stalled objective wearing a polite face. |
| B11 | What is the priority order of the open queue? | sequencing | daily | every department | Working the wrong order costs the same effort and produces less. |
| B12 | Is this department's plan serving a company goal? | diagnosis | weekly | `cpo`, `ceo` | Departments planning for themselves consume budget and move nothing. |
| B13 | Which goals have no active work? | diagnosis | weekly | `ceo` | This is literally its own KPI's numerator; 93.75% measured means 4 of 64 goals have no open task. |
| B14 | Is this a P0/P1 incident, and who leads it? | escalation | on occurrence | any seat | A crisis with two coordinators has none. |
| B15 | A cross-department crisis is running — what is the comms cadence? | craft | during incidents | founder, heads | Silence during an incident is read as absence. |
| B16 | This founder instruction is ambiguous — clarify or act? | gate | on occurrence | founder | Acting on a guess wastes a cycle; asking a technical question breaks a standing rule. |
| B17 | Turn a one-line WhatsApp instruction into a task packet — scope, owner, done-criteria, deadline | craft | on occurrence | founder | An incomplete packet (BR-008) produces work that cannot be accepted. |
| B18 | Is this instruction already covered by an existing task? | diagnosis | on occurrence | founder | Duplicate dispatch, already a recorded lesson for this department. |
| B19 | Has a settled question been re-opened? | gate | weekly | any seat | Re-asking a `never_ask_again` decision costs the founder's attention. |
| B20 | Which department is over its dispatch back-pressure limit? | diagnosis | daily | `dispatch_max_open_per_dept` = 250 | An over-full queue silently drops the event bus into back-pressure. |
| B21 | Is the daily operating loop actually producing evidence? | diagnosis | daily | `cpo` | `day_cadence` is `cpo`'s KPI and this seat's operating rhythm; a loop that runs and evidences nothing is theatre. |
| B22 | What changed since the last brief? | craft | daily | founder | Repeating yesterday's state as news is how a brief loses its reader. |
| B23 | Which numbers in this brief are stale? | gate | daily | founder | An executive told to quote only live state must be able to prove the state is live. |
| B24 | Which decisions are waiting on the founder, and for how long? | escalation | weekly | founder | Cost of delay compounds silently. |
| B25 | Is a deadline going to be missed, and who must know today? | forecast | daily | heads, founder | Late notice removes every option except apology. |
| B26 | Is the review chain adding signal or just approving? | diagnosis | monthly | `cpo`, `ceo` | Measured 7 Sep: 2,554 approvals as reviewer, 0 rejections. |
| B27 | Which of the 64 active goals are at risk this week? | diagnosis | weekly | `ceo` | Reporting all 64 is reporting none. |
| B28 | Should this task be cancelled rather than chased? | gate | weekly | heads | Chasing dead work is the cheapest way to look busy. |
| B29 | Who covers a seat that is unavailable? | allocation | on occurrence | `people_ops` | `org_agents.unavailable_until` exists; an uncovered seat's queue stops. |
| B30 | Does this work need a decision record? | gate | daily | any seat | An untraced decision cannot be reviewed, reversed or learned from. |
| B31 | Is this notification an exception or routine? | gate | continuously | `notifications` | Routine types belong in the digest (`decision_policy.alert_digest_types`); money, security, legal and critical never do. |
| B32 | Which company facts must be in the brief because they changed? | craft | daily | founder | Licence expiry, pricing, legal versions and the go-live switches are the facts whose change he must not learn late. |
| B33 | What is the UAE operating-calendar effect this week? | sequencing | weekly | all | A Friday-evening deadline in a UAE working week is a Sunday deadline nobody meets. |
| B34 | Is a department asking for more budget or more capacity? | diagnosis | monthly | `ceo`, `cfo` | They need different answers and are described in the same sentence. |
| B35 | Has an escalation resolved, or just gone quiet? | diagnosis | weekly | `ceo` | A quiet escalation is an open one. |
| B36 | Which lesson from `institutional_memory` applies to this decision? | craft | daily | any seat | The company has 2,101 recorded lessons and repeats mistakes anyway. |
| B37 | Is the company's own knowledge in sync with a decision just taken? | gate | on every ruling | `data_intel` | A ruling recorded in one table and contradicted in three others is worse than no ruling. |
| B38 | Should this be one task or three? | sequencing | daily | heads | Over-splitting produces handoffs nobody accepts; under-splitting produces a task nobody can finish. |
| B39 | Which open item has the highest cost of delay? | sequencing | weekly | `ceo` | This is the only ordering that matters when capacity is fixed. |
| B40 | Is the company doing anything that no goal asks for? | diagnosis | monthly | `ceo`, `cpo` | Unasked-for work is the cheapest thing to stop and the hardest thing to see. |

### 2. Domain logic

#### M-B1 — Cost-of-delay priority score

The only ordering that survives contact with a fixed-capacity company.

```
CoD(task)   = value_at_risk_per_week × P(the delay actually bites)
value_at_risk_per_week
            = ( fn_revenue_trajectory().required_per_month / 4.33 )      # AED/week the company must earn
              × goal_weight(task.company_goal)                            # 1.0 if it touches the binding stage, else 0.2
priority    = CoD / expected_effort_weeks                                 # CD3: cost of delay divided by duration
```

Inputs: `org_tasks` (2,466 rows; `dept_key`, `status`, `priority`, timers), `company_goals` (64 active),
`fn_binding_constraint()` for `goal_weight`, `fn_revenue_trajectory()` for the AED/week base.
**UNMEASURED:** `expected_effort_weeks` — no estimate column exists on `org_tasks`; today the seat must substitute
the median historical age of closed tasks of the same `fn_task_class` (71 classes) and say it is doing so.

#### M-B2 — Ownership resolution

```
owner(request) = first non-null of:
  1. exact match on org_role.owned_decisions                       (org_role, 180 rows)
  2. org_agent_alias / org_department_alias / org_role_alias hit   (293 / 34 / 362 rows)
  3. embedding match: cosine(request, org_role responsibilities)   over gte-small, threshold 0.80
  4. lexical: strict_word_similarity(request, responsibilities)    threshold 0.45
  5. department of the company_goal the request serves             (company_goals.owner_dept)
  6. decision_policy.apex_backup = 'ops_director'
  7. NOBODY  → open a task on `ceo` to assign an owner (never guess)
```

The 7-step ladder is the point: it terminates in an explicit "nobody owns this" rather than in a plausible guess.
`org_role` carries owned and forbidden decisions per role, but **no prompt section or knowledge row renders the
ownership map today** — it exists as rows and is not delivered.

#### M-B3 — Stall taxonomy

Every stalled item has exactly one of six causes, each with a named remedy and a table that detects it:

| Cause | Detected by | Remedy |
|---|---|---|
| Handoff never accepted | `v_handoff_stalled`, `phase_d_handoff_acceptance` (0 rows) | Re-issue to the named accepting role; if unnamed, `v_handoff_without_contract` |
| Returned by review, not re-worked | `review_queue` (1,396), `review_chain` (8,403) with `violated_rule` | Return to author with the specific rule |
| Timer breached | `org_tasks` due dates, BR-044 | Escalate one level; never silently extend |
| Missing evidence | `decision_trace` incomplete (`v_decision_trace_incomplete`) | Name the missing artefact |
| Authority exceeded | `employee_authority` threshold vs the action's AED | Route to the seat that holds the tier |
| Blocked on the founder | `v_founder_inbox`, `founder_command` state | Report the age in the brief; never re-ask |

**UNMEASURED:** no row in the estate lists these causes and remedies today; the seat has 7 experience lessons and no
taxonomy.

#### M-B4 — Review verdict rule

```
verdict(deliverable) =
  REJECT   if any of the three grounds fails
  ESCALATE if it passes but exceeds the author's authority tier
  APPROVE  otherwise

grounds (the vocabulary already in review_chain.violated_rule):
  is_actual_work            — does it contain a produced artefact, or only a plan to produce one?
  states_its_result         — does it say what happened, with a number and its source row?
  grounded_in_this_business — does it name QuotesDone tables, prices, categories, or is it generic?
```

Measured baseline (7 Sep 2026): as reviewer this seat recorded **2,554 `approve` and 0 `reject`**. A rule with a 100%
pass rate over 2,554 trials is either unnecessary or unapplied. The target is not a rejection quota — it is that the three grounds are evaluated
and recorded, so the pass rate becomes evidence rather than a default.

#### M-B5 — Brief construction

```
brief = BLUF + decisions_needed + exceptions + changed_since_last + FYI
BLUF               = argmax over open items of M-B1 priority
decisions_needed   = items in founder_review_gates + facts only he holds + money > AED 10,000
exceptions         = notifications where type NOT IN decision_policy.alert_digest_types
changed_since_last = diff(v_bi_scorecard now, v_bi_scorecard at last brief) where state changed
FYI                = at most 3 lines
constraint: every number cites its row and its taken_at; nothing older than 24h without saying so
```

`decision_policy.alert_digest_types` holds the 13 routine types that fold into the digest; money, security, legal,
critical and `founder_alert` are hard-excluded from digesting regardless.
**UNMEASURED:** there is no stored example brief, so the template has no reference implementation.

#### M-B6 — Goal coverage (its own KPI, and its known defect)

```
coverage = 100 × count(goals with ≥1 org_task where status <> 'done') / count(active goals)
```
Measured 93.75% on 2026-09-07 03:30 UTC. The defect this seat must state whenever it reports the number: a goal with
an open task scores the same as a goal being delivered, so coverage is an **activity** measure and cannot be read as
progress. Four exec KPI rows (`brief` id 17, `brief` id 14, `ceo` id 34, `cpo` id 35) share this identical
`measure_sql` — four rows, one number, 93.75%.

#### M-B7 — Conflict arbitration order

Deterministic tie-break, applied in strict order until one side wins:

```
1. safety and legality               (decision_policy.legal_triggers, sensitive_categories)
2. an explicit founder ruling        (company_policy_decision, never_ask_again)
3. the binding constraint            (fn_binding_constraint — the side that touches it wins)
4. the company goal with the nearer deadline  (company_goals.deadline)
5. reversibility                     (the reversible option wins a tie)
6. the priority hierarchy            (priority_hierarchy, 6 ranks — see below)
7. escalate to ceo with both cases stated
```

Step 6 is populated and is the company's written order of precedence (`priority_hierarchy`, 6 rows, each
`overrides_below = true`): 1 protect legal and regulatory compliance; 2 protect customer trust and data security
(anonymity, confidentiality, PDPL — never reveal a supplier identity before authorisation); 3 deliver high-quality
outcomes (a correct answer late beats a fast wrong one); 4 support sustainable revenue growth (prefer actions that
move a company goal; revenue that damages trust or compliance is not growth); 5 improve efficiency and reduce costs
(deterministic code over an LLM, small model over large); 6 continuously learn and improve. Ranks 1 and 2 duplicate
step 1 of this order by design — the redundancy is deliberate, not a defect.

### 3. Reasoning procedures

**P-B1 — Ownership (B1, B2)**
1. Normalise the request text; strip courtesy.
2. Run the M-B2 ladder in order, stopping at the first hit; record which rung matched.
3. If rungs 3 or 4 matched below threshold, do **not** assign — emit "no owner above threshold", list the two closest
   roles with their scores, and open a task on `ceo`.
4. Check `org_role.forbidden_decisions` for the proposed owner. A forbidden match overrides an owned match.
5. Emit owner, rung, score and the alternative considered.

**P-B2 — Founder brief (B4, B5, B22, B23, B32)**
1. Refresh `v_bi_scorecard`; if `max(taken_at)` is over 24h old, the brief leads with that fact.
2. Diff every metric's `state` against the last brief in `exec_reports` (325 rows) — only changes are news.
3. Collect decisions per P-C8's ladder; if none, write "no decisions needed".
4. Collect exceptions: `notifications` not in `alert_digest_types`; `founder_alerts` (185 rows); open items in
   `v_founder_inbox`.
5. Check the change-sensitive company facts: `company_registration.expires_on` (24 Jun 2027),
   `legal_documents` versions, `pricing_config.updated_at`, the five go-live switches.
6. Rank the whole set by M-B1; the top item becomes the BLUF.
7. Fill the template. Every number carries `table.column` and `taken_at`. Refuse to emit any figure without a source.

**P-B3 — Review verdict (B8, B9, B26)**
1. Load the deliverable and its `workflow_step` contract.
2. Evaluate the three grounds of M-B4 mechanically: `is_actual_work` = does an artefact row exist
   (`doc_versions`, `org_tasks.result`, a written table row)? `states_its_result` = does the text contain a numeral
   with a cited source? `grounded_in_this_business` = does it contain at least one QuotesDone-specific token
   (a category slug, a price from `pricing_config`, a table name, an emirate)?
3. Any failure → REJECT with the failed ground written into `review_chain.violated_rule`.
4. Pass + authority exceeded → ESCALATE.
5. Record the verdict with the grounds evaluated, so the approval rate becomes measurable evidence instead of a
   default.

**P-B4 — Stalled item triage (B6, B7, B28)**
1. Pull items past their timer from `org_tasks`, `review_queue`, `v_handoff_stalled`, `dead_letter` (122 rows).
2. Classify each into exactly one of the six M-B3 causes by the detecting query — never by narrative.
3. Apply the remedy for that cause.
4. If an item has stalled for the same cause three times, stop chasing and put the **cause** on the agenda as a
   process defect for `cpo` (B28).

**P-B5 — Priority ordering (B11, B39)**
1. Compute M-B1 for every open item.
2. Apply back-pressure: any department at `dispatch_max_open_per_dept` (250) has new work deferred, not queued.
3. Apply the UAE calendar (`company_calendar`, 55 rows; `public_holidays`) to due dates.
4. Emit the ordered queue with the CoD of the top five shown, so the ordering can be argued with.

**P-B6 — Founder instruction → task packet (B16, B17, B18)**
1. Match the instruction against `founder_command_interpretation` history (42 rows) and the intent catalogue
   (`CMD-W20`, `CMD-W25`, `CMD-STATUS`, `AMBIGUOUS`, `CMD-RETIRED-RITUAL`).
2. If it matches `AMBIGUOUS` above threshold, produce a clarification with **options**, never an open question, and
   never a technical one.
3. Check for an existing open task covering it (`event_recur_cooldown_days` = 7 governs the same logic on the bus).
4. Build the packet: scope, owner (P-B1), done-criteria (a row that will exist), deadline (calendar-adjusted).
5. Record the link in `founder_command_task_link`.

**Stop and refuse when:** the ownership ladder terminates at NOBODY; a required threshold is missing; the scorecard is
stale and the question depends on it; the instruction touches a `never_ask_again` decision.

### 4. Judgement rules

| id | Condition | Verdict | Reason |
|---|---|---|---|
| J-B1 | The brief would contain a number without a source row and a `taken_at` | Do not send | An executive briefed on remembered numbers is briefed on fiction. |
| J-B2 | There are no real decisions for the founder this cycle | Write "no decisions needed" | A manufactured decision costs him more than an empty section. |
| J-B3 | The item is a technical question | Never send it to him; engineering decides and records | Founder standing rule; he sets boundaries, not methods. |
| J-B4 | The request touches refunds | Route to him; every refund of any amount is his | `every_refund_is_the_founders`, 17 Aug 2026. |
| J-B5 | The request touches anything else in `company_policy_decision` with `never_ask_again` | Answer from the row; do not escalate | Re-asking a settled question wastes the one channel the company has to him. |
| J-B6 | The ownership ladder returns NOBODY | Say NOBODY and open an assignment task | A guessed owner produces bad work and hides the gap. |
| J-B7 | The reviewer would approve without evaluating the three grounds | Do not approve | 2,554 approvals with 0 rejections and no recorded grounds is not a review. |
| J-B8 | The same item stalls for the same cause a third time | Stop chasing; escalate the cause as a process defect | Chasing a symptom three times is the definition of the wrong intervention. |
| J-B9 | A department is at its dispatch back-pressure limit | Defer new work; do not queue it | Queueing past back-pressure moves the failure from visible to invisible. |
| J-B10 | The deadline falls on a UAE weekend or public holiday | Move it to the next working day and say so | A deadline nobody can meet is a fiction that reads as a miss. |
| J-B11 | Two seats are in conflict | Run the seven-step order; record the ruling with the step that decided it | An unrecorded ruling gets re-litigated next month. |
| J-B12 | Rank 5 (efficiency) would win over rank 4 (revenue growth) or higher | Rank 5 loses — every rank overrides everything below it | `priority_hierarchy.overrides_below = true` on all 6 ranks: cheapness never outranks trust, quality or a company goal. |
| J-B13 | A notification type is not in `founder_mail_policy` | It cannot be emailed; route it as an owned task | A new kind without a policy row is silently mis-delivered. |
| J-B14 | Reporting goal coverage (93.75%) | State that it counts open tasks, not delivery | The number would read 93.75% on a day of zero revenue. |
| J-B15 | An escalation has had no movement for 7 days | Re-raise it in the brief with its age | A quiet escalation is an open one. |
| J-B16 | A ruling has just been taken | Verify every table that states the same fact is in step, and open corrections | A ruling contradicted in three tables is worse than no ruling. |
| J-B17 | The brief exceeds one page | Cut the FYI block first, the exceptions second, never the decisions | The decisions are the only part that must be read. |
| J-B18 | A crisis is running | One coordinator, one thread, one voice; convene by the incident map | Two coordinators is none. |
| J-B19 | An item has high CoD but the effort estimate is missing | Use the median age of closed tasks in its `fn_task_class` and say the estimate is substituted | A missing estimate must not silently become zero. |
| J-B20 | A department's plan names no `company_goals.key` | Return it | Already a recorded lesson in this seat's own experience layer. |

### 5. Technical knowledge

- **Task and queue machinery:** `org_tasks` (2,466), `fn_org_task_execute_sweep(limit)`, `fn_task_class` (73),
  `fn_task_is_demand`, `review_queue` (1,396), `review_chain` (8,403) and its `violated_rule` vocabulary,
  `dead_letter` (141), `escalations_archive_20260724`.
- **Event bus and back-pressure:** `event_subscription` (94), `event_delivery` (4,297), `event_rollup`,
  `phase_c_event_outbox`, `fn_event_dispatch`, and the three governing keys — `dispatch_max_batch` 500,
  `dispatch_max_open_per_dept` 250, `event_recur_cooldown_days` 7.
- **Handoff machinery:** `phase_b_handoff` / `phase_c_handoff_binding` (134), `phase_d_handoff_contract` (134),
  `phase_d_handoff_acceptance` (**0 rows**), `v_handoff_stalled`, `v_handoff_without_contract`, `fn_handoff_answer`.
- **Workflow machinery:** `workflow` / `workflow_step` (187) / `workflow_run` (1,734) / `workflow_step_run` (27,117),
  `org_workflow_ownership` (30), `employee_workflow` (112). Its own memberships: `strategic_review` (step actor),
  `employee_task` and `campaign_publishing` (approver), `rfq_handling` (participant).
- **Founder channel:** `founder_command` (27) and its intent vocabulary, `founder_command_interpretation` (42),
  `founder_command_plan` / `_plan_item` / `_task_link` / `_status_history`, `founder_mail_policy` (61),
  `fn_founder_mail_route`, `fn_notify_founder(p_kind, …)`, `founder_alerts` (202), `v_founder_inbox`,
  `v_phase_c_what_reaches_the_founder`, `inbound_messages`, `wa_messages` (12).
- **Brief and report surfaces:** `fn_founder_brief()` (**VOLATILE — writes**), `fn_company_brief(max_chars)` (STABLE),
  `fn_exec_meeting()` (VOLATILE), `exec_reports` (325), `board_reports` (183), `day_cadence` (160),
  `fn_os_health_brief()`.
- **Org structure:** `org_agents` (96), `org_role` (181) with owned/forbidden decisions, `org_departments` (33),
  the three alias registries (`org_agent_alias` 293, `org_role_alias` 362, `org_department_alias` 36),
  `v_org_chart`, `v_org_open_tasks`, `org_authority` (809), `employee_authority` (320).
- **Retrieval:** `fn_ops_knowledge_search(dept, query, limit)`, `fn_company_knowledge_search(question, limit)`,
  `institutional_memory` (2,101), `org_memory` (1,041), `agent_memory` (975), `memory_promotions` (60),
  `pg_trgm` similarity operators, `embedding_gte` columns.
- **Calendar:** `company_calendar` (55), `public_holidays`, the UAE working week, Dubai = UTC+4, all stored timestamps
  UTC.
- **Never:** call a VOLATILE routine to answer a read question; email a real address outside a `rehearsal_window`;
  print a secret; approve anything reserved to the founder.

### 6. Academic knowledge

| Discipline | Framework | Lawful primary source |
|---|---|---|
| Programme and project management | Scope/schedule/risk, stakeholder management, the business-environment domain, predictive vs agile | PMI published PMP *Examination Content Outline* (freely published syllabus); ISO 21500 *Guidance on project management* |
| Queueing and flow | Little's Law, WIP limits, cost of delay, CD3 scheduling, back-pressure | Open-licence lecture notes; ITU-T E-series traffic engineering |
| Decision and prioritisation theory | Weighted shortest job first, multi-criteria decision analysis, lexicographic tie-breaking | ISO 31010 (techniques catalogue); NIST/SEMATECH e-Handbook (public domain) |
| Incident command | Single-coordinator doctrine, severity classification, comms cadence | ISO 22320 *Emergency management — guidelines for incident management*; NIST SP 800-61 rev.2 (public domain, method only) |
| Governance and internal control | Segregation of duties, creator/reviewer separation, no self-certification | COSO Internal Control framework executive summary (freely published); ISO 37000 *Governance of organizations* |
| Customer experience | Journey mapping, voice-of-customer, experience metrics and their limits | CXPA published CCXP competency framework (freely published); ISO 10002 *Complaints handling* |
| Executive communication | BLUF, decision-first structure, exception reporting | Published government and standards-body writing guidance (e.g. plain-language standards issued by public bodies) |
| UAE operating context | Working week, public holidays, Ramadan hours, procurement seasonality | UAE Government official calendar publications; Dubai DET published guidance |

**Certifications on record** (`public.role_certification`):

| rank | Certification | Body | Pass mark | Syllabus areas |
|---|---|---|---|---|
| 1 | PMP (Project Management Professional) | PMI | 61% | People; Process; Business Environment; Predictive Plan-Based Methodologies; Agile and Hybrid Approaches |
| 2 | CCXP (Certified Customer Experience Professional) | CXPA | 68% | Customer Insights and Understanding; Customer Experience Strategy; Metrics Measurement and ROI; Experience Design Improvement and Innovation; Organizational Adoption and Accountability; Culture and Accountability |

**Syllabus areas failed: does not exist.** No row in `certification_exam_result` is for `brief`; neither
certification has been sat. The internal knowledge exam (`knowledge_exam_results`) gives 36 graded answers —
6 correct, 5 partial, 13 wrong, 12 not_covered. The 6 Sep audit records that ten of the wrong answers were
trade-regulator questions (food-import permits, cosmetics registration) asked of a Chief of Staff because the examiner
read "brief" as a sourcing brief; five trade-route exam fills are still sitting in this seat's learned layer.
Contamination visible today in `agent_knowledge`: `exam:744 03_QUOTE_READINESS_AND_COMPARISON_V2.yaml`,
`exam:745 source_route_manifest.json` (Luxury & Concierge catalogue), `exam:authority` (Dubai food-import approval),
`exam:compliance` (ECAS), `exam:scope` (CIF Incoterm) — none of which is Chief-of-Staff knowledge.

**Corpus gap:** `dept_library` for `exec` = **0 rows**.

### 7. Corporate knowledge

**Its own KPIs** (`employee_kpi`): id 17 "Chief of Staff — primary objective" (goal coverage, target 100%, measured
93.75%), id 14 "Company goals with active work" (the identical `measure_sql` — a duplicate row), id 26 "Documentation
Manager — primary objective" (QA gate pass rate, target 95%, measured 100.00%, `serves_goal =
customer_satisfaction`). It must know that id 14 and id 17 are the same measurement recorded twice, and that neither
measures delivery.

**Its authority and its position:** autonomous at AED 100,000 on `escalate_founder`, `exec_review`, `coordinate`; the
CEO's standing deputy; arbiter in governance rules 5 and 9; third step of the approval hierarchy; `manager_key = ceo`.

**The founder's standing rules verbatim** (`company_policy_decision.founder_standing_rules`): nothing needs his
approval except Stripe refunds; he is emailed exceptions only; he is never asked technical questions; he sets
boundaries, not methods; one completion line or an honest hand-over; WhatsApp is his command channel; money above AED
10,000, destructive production changes and facts only he holds escalate; paid inference stays off until he activates
it; the OS stays signed in and the company solves its own problems.

**The escalation surface:** `decision_policy.founder_review_gates` = refunds only.
`decision_policy.action_autonomy` maps 25 action kinds to `ack` or to an accountable role — **none routes to the
founder**. `apex_backup` = `ops_director`. Anything without a `founder_mail_policy` row cannot be emailed to him.

**The goals it runs the company against:** 64 active `company_goals` across 10 owner departments; exec owns 2; 32 of
the 64 have no `measure_sql`.

**Handoffs it owns:** to `ceo` (strategy and anything above its tier); to `cpo` (performance diagnosis, KPI misses,
process defects); to department heads (routing and unblocking); to `legal` for `decision_policy.legal_triggers`;
to the founder for refunds only.

**History it must not forget:**
- As reviewer (measured 7 Sep 2026): **2,554 `approve`, 0 `reject`**. As author: 1,037 rows — 627 approve, 199 owned,
  1 reject, 210 still undecided.
- Its `improvement_plan` records 331 deliverables returned by review across the department, with the recorded reason
  "grounded_in_this_business (minor): The work order says: Be concrete and specific to QuotesDone" — that is the
  ground this seat is failing and the ground it is meant to enforce.
- Recorded lessons in its own experience layer: verify the org structure before publishing authority maps; verify a
  target is reachable before treating a miss as an execution failure; check for a shared systemic cause when several
  `kpi.missed` alerts fire together; watch for duplicate dispatch; treat "I could not reach the AI service" as a
  failed run, not an output.

**What does not exist for this seat:** the ownership map as a rendered record; an example founder brief; the stall
taxonomy; rejection criteria for its own review; a numeric scoring rule for priority (the six-rank
`priority_hierarchy` gives precedence, not a score); `phase_d_handoff_acceptance` rows; a UAE operating-calendar knowledge record; a `dept_library` for `exec`.

### 8. One-year plan

**Objective.** Guarantee that every one of the 64 active company goals has a named owner, live work and a truthful
weekly status, and that the founder receives, once a day, a brief he can act on in under two minutes with nothing in
it that is not measured.

**Metrics it owns:**
1. **Goal coverage** — goals with active work, target 100%, measured 93.75%. To be re-specified during Q1 so that it
   measures *delivery against the goal's own measure*, not the existence of an open task; the current form is an
   activity measure and this seat is the one that must say so.
2. **Review signal** — the share of reviews where all three grounds are recorded. Baseline: 0% of 2,554. Target 100%
   by end of Q2. This is not a rejection quota; it is evidence that a review happened.
3. **Brief integrity** — the share of numerals in each founder brief carrying a source row and a `taken_at`.
   Baseline: **does not exist** (never measured). Target 100%.

**Its slice of AED 1,000,000: AED 0 of direct revenue, and one hard dependency.** No routing decision books a dirham.
Its contribution is measurable in one way only: whether the seat that owns the binding constraint has the work, the
authority and the unblocked path to move it. The honest statement is the same as the CEO's — on the measured evidence
the AED 1,000,000 is not achievable, and this seat's job in that reality is to make sure the founder learns it from a
brief in Q1 rather than from the ledger in Q4.

**Quarterly milestones:**

| Quarter | Milestone | Verified by |
|---|---|---|
| Q1 | The ownership map rendered from `org_role` into a record every seat reads; the stall taxonomy recorded with its six detecting queries; the three review grounds recorded on every review | `ops_knowledge where dept_key='exec'`; `review_chain.violated_rule` non-null rate |
| Q2 | Goal coverage re-specified to measure delivery; brief integrity instrumented and at 100%; a numeric priority score recorded on top of the six-rank precedence order | `employee_kpi.measure_sql`; `ops_knowledge where dept_key='exec'` |
| Q3 | Every one of the 64 goals has an owner, a live measure or an explicit `no_measure_reason`, and a named next action | `company_goals`; `org_tasks` |
| Q4 | Zero items in `v_handoff_stalled` older than 7 days; zero escalations open more than 14 days without a re-raise | `v_handoff_stalled`; `founder_alerts` age |

**Capacity check.** 139 runs in 7 days ≈ 20/day, against `max_open_tasks` 50 and `dispatch_max_open_per_dept` 250.
The daily brief, the weekly review and routing at the current volume (2,466 tasks, 1,390 review items) fit
comfortably. If inquiry volume reaches the M5 requirement of ~140/month, routing load rises but stays inside the cap.
The seat's real constraint is not throughput — it is that three of its core procedures (ownership map, stall taxonomy,
review grounds) have no stored definition, so it currently performs them from an undelivered profession layer.

**Dependencies.** `product_eng` to render the ownership map and instrument brief integrity; `people_ops` to fix the
duplicate KPI rows and the exam remit; `data_intel` to populate `dept_library` for exec; `cpo` for the re-specified
coverage metric; `ceo` for arbitration escalations; the founder for the five switches and the refund gate.

### 9. What this seat cannot do without a model

1. **Reading a free-text WhatsApp instruction that matches no stored intent.** The matcher covers paraphrases of the
   five recorded intents; a genuinely new instruction falls below threshold and produces a clarification with
   options, which is the correct behaviour but is a limitation.
2. **Writing the brief in a human voice for a situation the templates do not cover.** The templates cover the 40
   enumerated types; anything else is emitted as a structured exception.
3. **Judging tone** — whether a founder message is urgent, frustrated or rhetorical. Priority comes from the cost-of-
   delay arithmetic and from `founder_command.priority`, never from reading his mood.
4. **Summarising an unstructured external artefact** (a PDF, a screenshot, a long email thread) into a task packet.
   Extraction is a model task; once the fields are rows, the packet is built deterministically.

Everything else in sections 1–8 runs with OpenRouter switched off.

---

## cpo — Chief Performance Officer

Role of record: "executive", title "Chief Performance Officer", `seniority = chief`, `manager_key = ceo`.
Responsibilities of record: "Owns company, department and employee performance end to end. Reviews the KPI scoreboard
weekly, diagnoses every missed target, opens improvement initiatives with a named metric and a baseline, grades them
against that claim through the outcome ledger, promotes what worked and reverses what did not. Owns AI efficiency,
automation coverage, cost per decision, process optimisation and benchmarking. Answers one question: is this company
measurably better than last week?"

Authority (`employee_authority`): `recommend` autonomous at AED 0 ("may open improvement initiatives unprompted");
`coordinate` autonomous at AED 0 ("may assign improvement work across departments"); `exec_review` autonomous at AED 0
("owns the weekly performance review"); `qa_gate` **gated** ("may hold work that fails a quality gate");
`escalate_founder` **advisory** at AED 0. It is the only exec seat whose money threshold is zero — it changes how the
company works, never what it spends.

### 1. Question and decision taxonomy

| # | Question or decision | kind | How often | Who asks | What a wrong answer costs |
|---|---|---|---|---|---|
| P1 | Is this company measurably better than last week? | diagnosis | weekly | founder, `ceo` | A "yes" built on activity metrics is the most expensive sentence in the estate. |
| P2 | This KPI missed — is the work bad or the target wrong? | diagnosis | weekly, per miss | department heads | Punishing a seat for an unreachable target destroys the instrument and the seat. |
| P3 | Is this KPI measuring the right subject at all? | diagnosis | on definition and quarterly | every seat | An instrument on the wrong subject makes every decision downstream wrong in the same direction. |
| P4 | Do this metric's units match its target's units? | gate | on definition | every seat | Measured defect: `supplier_response_rate` returns a 0–1 fraction and is compared against a target of 60 *percent*. |
| P5 | Is this a leading or a lagging indicator, and is it being used as the wrong one? | gate | on definition | heads | Steering on a lagging indicator is steering by the rear-view mirror. |
| P6 | Is the denominator the right population? | gate | on definition | heads | `supplier_response_rate` averages over 2 rows; `refund_rate` over 0. |
| P7 | Is this number stale? | gate | weekly | every consumer | A stale number is worse than a missing one because it is used. |
| P8 | Zero — is that a dead instrument or an idle system? | diagnosis | weekly | `ceo` | The estate's most-repeated failure: 0 reveals and a broken reveal counter look identical. |
| P9 | This number moved — was it the intervention or the population? | diagnosis | per initiative | initiative owners | Crediting a fix for a population change promotes a placebo. |
| P10 | What is a valid baseline for this initiative? | gate | per initiative | initiative owners | Without a pre-declared baseline the outcome ledger grades against hindsight. |
| P11 | Did this improvement work? | gate | per initiative, at grading | `ceo` | Measured: 43.30% of initiatives graded against a target of 80%. |
| P12 | Should this improvement be promoted or reversed? | gate | per graded initiative | heads | An un-reversed failure becomes permanent process debt. |
| P13 | Which KPIs cannot be measured at all, and why? | diagnosis | weekly | `ceo`, founder | Measured: 88.33% measurability against a target of 100%; 30 of 63 company goals carry `no_measure_reason`. |
| P14 | Is this "no instrument exists" honest, or is someone avoiding the work? | gate | quarterly | heads | Both failure modes exist and they need opposite responses. |
| P15 | What is our cost per decision, and is it falling? | diagnosis | weekly | `ceo`, `cfo` | AI cost is a variable cost per transaction, not overhead; model routing is an economic decision. |
| P16 | Which model calls could a cheaper model or deterministic code have served? | diagnosis | weekly | `cto` | Measured: **38.9–39.93% avoidable** against a target of ≤ 10%. |
| P17 | What share of our actions are deterministic versus model-routed? | diagnosis | monthly | `ceo` | The founder's ~95/5 doctrine is unmeasured unless this is. |
| P18 | Is a held model call being recorded as an error? | gate | weekly | `cto` | A held provider looks exactly like a broken one; the CEO's own runs show 5 of 6 "skipped". |
| P19 | Where is the constraint in the review chain? | diagnosis | monthly | `brief` | Returns and rework are the cheapest capacity in the company and the least visible. |
| P20 | Why did this department's return rate rise? | diagnosis | monthly | heads | Measured: 331 deliverables returned in exec recently. |
| P21 | Is the daily operating loop producing evidence at every stage? | diagnosis | daily | `brief` | Its own KPI, `day_cadence`, currently has **no measured value at all**. |
| P22 | Which process step has the worst rework rate? | diagnosis | monthly | heads | Rework is invisible in throughput and enormous in cost. |
| P23 | Is this SLA being met, and is the SLA the right one? | gate | monthly | heads | An SLA nobody set deliberately is a number someone typed. |
| P24 | Is this seat's KPI actually measurable? | gate | on hire and quarterly | `people_ops` | Open finding on record: "Employee has no measurable KPI". |
| P25 | Are two KPIs measuring the same thing? | gate | quarterly | `people_ops` | Measured: `brief` id 14 and id 17 carry identical `measure_sql`; four exec KPI rows share one number. |
| P26 | Does this KPI read the instrument it is part of? | gate | on definition | every seat | Measured precedent: KPI id 71 recursed into `fn_kpi_scoreboard()` and made all 95 KPIs unmeasurable. |
| P27 | Is a target above current capability, or is it a real shortfall? | diagnosis | per miss | heads | The two look identical in the number and need opposite responses. Both bands are already recorded in the department's improvement plans. |
| P28 | Should this work be held at a quality gate? | gate | continuously | authoring seats | Its `qa_gate` authority is *gated*, so a hold that should be a block must be escalated. |
| P29 | Is the automation coverage number counting the right actions? | gate | monthly | `ceo` | Coverage that counts a skipped held call as automated is a lie in the right direction. |
| P30 | What is the benchmark for this metric, and where did it come from? | forecast | quarterly | `ceo` | An unsourced benchmark is a made-up target with a confident tone. |
| P31 | Is this experiment powered enough to conclude anything? | gate | per experiment | initiative owners | With 0 reveals and 1 customer, almost nothing in this estate is powered. |
| P32 | Did several KPI misses share one systemic cause? | diagnosis | weekly | `ceo`, `brief` | Already a recorded lesson: mass calibration events produce simultaneous misses. |
| P33 | Is this metric's owner the seat that can actually move it? | gate | quarterly | `people_ops` | A metric owned by a seat with no lever is a grievance, not a KPI. |
| P34 | Which measurement defect is costing the most decisions right now? | diagnosis | monthly | `ceo` | This is the seat's highest-leverage output and nothing measures it today. |
| P35 | Has an improvement been left open rather than graded? | gate | monthly | initiative owners | Measured: 56.7% of `outcome_record` rows are ungraded. |

### 2. Domain logic

#### M-P1 — Measurement validity test (applied to every metric before it is trusted)

Six checks, all mechanical, all failing loudly:

| Check | Test | Fails today on |
|---|---|---|
| Subject | Does the `measure_sql`'s FROM clause name the entity the label claims? | — |
| Units | `metric_definition.target` unit vs the scale the SQL returns (fraction vs percent vs count) | **`supplier_response_rate`**: SQL returns `avg(rv_response_rate)` = 1.000 (a fraction, = 100%); the target is 60 (percent); the scorecard prints "1.0" and states OFF_TARGET |
| Population | Is the denominator the set the decision is about, and is `n` big enough to read? | `supplier_response_rate` n = 2; `refund_rate` n = 0; `quotes_per_inquiry` n = 0 |
| Nulls | Does the expression propagate null, or does a null silently become 0 or "on target"? | — |
| Freshness | `taken_at` age against the decision cadence | `v_bi_scorecard` refreshed 06:35 UTC 7 Sep — inside 24h |
| Self-reference | Does the measure read the instrument it is inside? | KPI id 71, retired 6 Aug 2026 for exactly this |

*Reconciliation check.* `leads` has **2 rows with `rv_reveals > 0`** while `transactions` has **0 rows**. A
denormalised counter and the ledger disagree; the counter is what `supplier_response_rate` reads. Every derived
supplier-reliability number in the estate rests on it.

#### M-P2 — KPI-miss cause taxonomy

```
attainment = actual / target        (direction-adjusted)

band:
  no throughput        : denominator = 0                → NOT under-performance; the system is idle
  instrument defect    : M-P1 fails any check           → fix the measure, not the work
  target above capability : attainment ≥ 0.80 and the process's demonstrated ceiling < target
  capacity shortfall   : attainment < 0.80 and effort was applied at capacity
  conversion shortfall : attainment < 0.80 and the input volume was present
  population change    : the denominator changed by > 20% in the period
```

The first two bands are already in production text: the department's improvement plans carry
"Root cause (deterministic band, no model call): target above current capability: attainment 88.5% …" and
"capacity or conversion shortfall: attainment 32.2% …". The taxonomy above is the full set; only two bands exist
today.

**Split rule.** When a fix has a date, never compare a single pooled number across it. Split the population at the
fix date and compare the two halves; a pooled average across an intervention hides the intervention.

#### M-P3 — Improvement-initiative lifecycle

```
1. baseline   : the metric's value over the N periods BEFORE the intervention, declared and stored
                before any change ships. N ≥ 4 periods or the initiative is not gradeable.
2. hypothesis : "metric M will move from B to B' by date D because of change C"
3. intervene  : one change, one metric, one owner
4. observe    : the same measure_sql, the same population, N periods after
5. grade      : improved | no_change | worse | not_gradeable(no valid baseline)
6. act        : improved → promote; worse → reverse; no_change → reverse (the default is reversal,
                because an unreversed no-change is permanent complexity for zero benefit)
```

Inputs: `outcome_record` (134 rows), `evolution_proposal` (116), `experiments` (2), `experiment_events` (**0 rows** — the experiment instrument
exists, holds 1 assignment and has never recorded an event), `metric_snapshot` (1,218),
`employee_kpi_history` (1,332).
Measured: **43.30%** graded against a target of 80%; of those graded, **76.19%** improved against a target of 60%.
The second number is healthy and the first is not — the company is good at improving and bad at closing the loop.
**UNMEASURED:** no row anywhere defines what a valid baseline is.

#### M-P4 — Cost per decision

```
cost_per_decision = ai_cost_aed(window) / decisions_completed(window)
avoidable_share   = count(ai_cost_log where could_be_cheaper) / count(all)
deterministic_share = 1 − ( model_routed_steps / total_steps )
```

Measured over the trailing 30 days: AED 154.22 across 2,954 calls = **AED 0.0522 per call**;
`avoidable_ai_pct` = **38.9%** (scorecard) / 39.93% (KPI id 75) against a ceiling of 10%.
Denominator sources: `workflow_step_run` (27,117), `action_execution` (2,037), `decision_log` (2,099),
`org_tasks` closed.
Governing keys the seat must cite: `cos_reflection_tasks_per_day` = 500,
`workflow_reflection_steps_per_day` = 2,000 (whose description records the measured AED 0.146/step that replaced a
wrong AED 0.086/step derived by dividing estate-wide spend by a step count — a worked example of M-P1's population
check).
**UNMEASURED:** cost per *reveal*, because reveals are 0; `v_unit_economics.ai_cost_per_reveal_aed` is null.

#### M-P5 — Review-chain flow analysis

```
return_rate(dept)   = returned / authored
rework_cost(dept)   = returned × median_effort_per_deliverable
constraint_step     = argmax over workflow steps of ( queue_time / total_cycle_time )
```

Inputs: `review_chain` (8,403) with `violated_rule`, `review_queue` (1,396), `workflow_step_run` (27,117),
`qa_results` (288).
Measured 7 Sep 2026: exec has 331 returns recorded in its improvement plans, while `brief` as reviewer recorded 2,554
`approve` and 0 `reject`, so the returns are being generated somewhere other than that reviewer.
**UNMEASURED:** `median_effort_per_deliverable` — no effort column exists.

#### M-P6 — Statistical power for a pre-launch funnel

```
For a proportion test at α = 0.05, power 0.80, to detect a lift from p to p(1+δ):
    n per arm ≈ 16 · p(1−p) / (p·δ)²
```

At the estate's measured scale — 1 customer, 0 inquiries, 0 reveals — the required `n` for any conversion experiment
exceeds the entire population by orders of magnitude. The seat's honest verdict on almost every proposed A/B test
today is **not powered; use a bound, not a test.** The correct instrument at `n = 0` is the rule-of-three upper bound
(CEO M4), not a significance test.

#### M-P7 — Benchmark sourcing rule

```
benchmark := (value, source_row, date, population_definition)
A benchmark without all four fields is rejected and the target is set from the company's own
demonstrated ceiling instead.
```

`market_intel` has **0 rows** (`strategy_risks` #5: "No competitor records in market_intel"). `public.competitor`,
however, holds **27 rows**, all with a `source_url` and `verified_at = 2026-07-27` — so **pricing and positioning
benchmarks do exist and pass the four-field test** (e.g. RFQsNow supplier pricing, Biznex AED 365/yr). What does not
exist anywhere in this estate is an **operational** benchmark: no external conversion rate, response time, quotes-per-
RFQ or take-rate figure with a source. Every operational target today must therefore be internal-ceiling-derived or
declared an aspiration, and labelled as which.

### 3. Reasoning procedures

**P-P1 — "Is the company measurably better than last week?" (P1)**
1. Snapshot `v_bi_scorecard` and `fn_kpi_scoreboard()`; store to `metric_snapshot`.
2. Run M-P1 on every metric. Any metric failing a check is **excluded from the verdict** and listed separately as a
   measurement defect — it does not count as good or bad news.
3. Diff surviving metrics against last week's snapshot.
4. Verdict per metric: improved / no change / worse / not comparable (population changed > 20%).
5. **Never** emit a composite score. `v_business_health` already shows why: "overall_score_measurable 94" beside
   "overall_score_all_departments 31" with 22 unmeasurable — a single number would report 94 on a zero-revenue day.
6. Answer format: counts by verdict, the defect list, and the one metric whose movement mattered most.

**P-P2 — KPI-miss diagnosis (P2, P27, P32)**
1. Compute attainment, direction-adjusted.
2. Run M-P1. If any check fails → band = `instrument defect`; the remedy is the measure, and the seat is not at
   fault. Stop.
3. If the denominator is 0 → band = `no throughput`. State plainly that this is an idle system, not
   under-performance. Stop.
4. Otherwise place the miss in an M-P2 band using the demonstrated ceiling from `employee_kpi_history`.
5. Check for a shared cause: if ≥ 3 KPIs missed in the same period, test for a common upstream event
   (`company_event`, `agent_runs` failures, a calibration change) before writing three separate diagnoses.
6. Emit: band, evidence, the one action, the owner, and the date the band will be re-tested.

**P-P3 — Metric definition review (P3–P7, P24–P26, P33)**
1. Parse the candidate `measure_sql`: FROM tables, WHERE population, the returned scale.
2. Run all six M-P1 checks.
3. Check for duplication: compare normalised `measure_sql` text against all active `employee_kpi` and
   `metric_definition` rows. An exact match is a duplicate and one row is retired.
   *(This check, run today, flags `brief` id 14 vs id 17.)*
4. Check the owner has a lever: does the owning seat's `employee_authority` include an action class that can move it?
5. Check leading/lagging classification against how it is used in the cadence.
6. Verdict: ACCEPT / ACCEPT WITH A UNIT FIX / REJECT with the failing check named.

**P-P4 — Improvement grading (P10–P12, P35)**
1. Retrieve the declared baseline. **If none was declared before the change, grade `not_gradeable`** and record why —
   never reconstruct a baseline after the fact.
2. Re-run the identical `measure_sql` over the same population, N periods after.
3. Split at the intervention date; compare halves, not a pooled average.
4. Grade improved / no_change / worse.
5. Act: improved → promote and record the promotion; no_change or worse → **reverse**, and record the reversal.
6. Update `outcome_record`; the ungraded share is this seat's own KPI.

**P-P5 — AI efficiency review (P15–P18, P29)**
1. `ai_cost_log` over 30 days: total AED, calls, cost per call, split by `fn` and by model tier.
2. `could_be_cheaper` share vs the 10% ceiling.
3. Separate **held** from **failed**: a held provider must not appear in the error count. Cross-check `agent_runs`
   status `skipped` against `llm_attempt` / `llm_failure_class`.
4. Deterministic share from `workflow_step_run.used_llm`.
5. Rank the top spending functions and, for each, state whether a deterministic path exists.
6. Emit the actions with an AED figure each; the reflection caps
   (`cos_reflection_tasks_per_day`, `workflow_reflection_steps_per_day`) are the levers.

**P-P6 — Zero-diagnosis (P8)**
For any metric reading zero, decide between three causes before reporting it:
1. **Idle system** — the upstream stock is genuinely empty (`inquiries` = 0 → `quotes_per_inquiry` null).
2. **Dead instrument** — the query runs but reads the wrong table, or the job that populates it has not run
   (`cron_registry`, `agent_runs`, `edge_health_probe`).
3. **Suppressed** — a guard, flag or hold prevents the event (`invite_enabled` = false → invite metrics are zero by
   configuration, not by failure).
The three have opposite remedies and identical readings. Never report a zero without naming which one it is.

**Stop and refuse when:** the baseline was not declared before the change; `n` is too small for the claim; the metric
fails a validity check and the question presumes it is valid; a benchmark has no source row.

### 4. Judgement rules

| id | Condition | Verdict | Reason |
|---|---|---|---|
| J-P1 | A metric fails any M-P1 check | Exclude it from the verdict and report it as a defect | A broken instrument must not vote on the company's health in either direction. |
| J-P2 | The metric's SQL returns a fraction and its target is a percent | REJECT the definition until the units agree | Live defect: `supplier_response_rate` reads 1.000 (100%) and is scored OFF_TARGET against 60. |
| J-P3 | The denominator is 0 | Report "no throughput", never "0% performance" | An idle system and a failing one read identically and need opposite responses. |
| J-P4 | `n < 30` for a proportion, or the population changed > 20% | Do not conclude; state the bound | With 1 customer and 0 reveals almost nothing here is powered. |
| J-P5 | A measure reads the instrument it belongs to | REJECT | KPI id 71 recursed into `fn_kpi_scoreboard()` and made all 95 KPIs unmeasurable for weeks. |
| J-P6 | Two active KPIs share identical `measure_sql` | Retire one | `brief` id 14 and id 17 are the same measurement counted twice. |
| J-P7 | No baseline was declared before the change | Grade `not_gradeable`; never reconstruct one | A retro-fitted baseline grades against hindsight and always passes. |
| J-P8 | An initiative grades `no_change` | **Reverse it** | Unreversed no-change is permanent complexity for zero benefit. The default is removal. |
| J-P9 | A benchmark has no source row, date and population | Reject it; set the target from the demonstrated internal ceiling | `competitor` supplies sourced *pricing* benchmarks (27 rows, all with `source_url`); no sourced *operational* benchmark exists anywhere, and `market_intel` has 0 rows. |
| J-P10 | A held model call is counted as an error | Fix the classification first | A held provider reads exactly like a broken one; the CEO's own runs show 5 of 6 "skipped". |
| J-P11 | Automation coverage would count a skipped held call as automated | Reject the definition | Coverage that flatters itself is worse than no coverage number. |
| J-P12 | ≥ 3 KPIs missed in the same period | Look for one systemic cause before writing three diagnoses | Recorded lesson in this department's own experience layer. |
| J-P13 | A KPI's owner has no authority class that could move it | Re-assign the KPI or remove it | A metric owned by a seat with no lever is a grievance. |
| J-P14 | An improvement's metric moved but the population also changed | Grade `not comparable` | Crediting a fix for a population change promotes a placebo. |
| J-P15 | A department reports improvement with no `outcome_record` | Do not accept it | 43.30% graded means the majority of claimed improvements are unclosed. |
| J-P16 | Avoidable AI share > 10% | Open an initiative naming the top three functions and the deterministic path for each | Measured 38.9%; AI cost is a variable cost per transaction, not overhead. |
| J-P17 | A composite health score is requested | Refuse; give counts and the defect list | `v_business_health` shows 94 vs 31 on the same day; an average over half-unmeasured items is the exact instrument that reported 97.7% on a zero-revenue day. |
| J-P18 | A real fix makes a headline number fall | Report the fall with its cause and defend it | Never weaken a check or fabricate to hold a number up. |
| J-P19 | A "NO INSTRUMENT EXISTS" reason is claimed | Verify no table could serve it before accepting | 18 of 63 goals carry this reason; some are honest and some are avoidance, and they need opposite responses. |
| J-P20 | `qa_gate` would block work | Its authority is *gated*, not autonomous — hold and escalate, do not block unilaterally | Exceeding the recorded tier is the failure this rule exists to prevent. |
| J-P21 | A counter and the ledger disagree | Trust the ledger; open a defect on the counter | `leads.rv_reveals > 0` on 2 rows while `transactions` = 0 rows. |

### 5. Technical knowledge

- **Measurement machinery:** `employee_kpi` (127 rows, **120 active**) and its `measure_sql` / `no_measure_reason` / `kpi_class` /
  `actual_value` / `measured_at`, `employee_kpi_history` (1,332), `fn_employee_kpi_measure()`,
  `fn_employee_kpi_assign()`, `fn_kpi_scoreboard()`, `fn_kpi_review()`, `metric_definition` (14),
  `metric_snapshot` (1,218), `v_bi_scorecard`, `goal_period` (316), `fn_goal_attainment`, `fn_goal_pace`,
  `fn_goal_period_refresh`, `fn_dept_objective_measure()`, `fn_os_objective_measure()`, `fn_objective_cascade()`,
  `fn_objective_review()`.
- **Improvement machinery:** `outcome_record` (134), `evolution_proposal` (116), `experiments` (2),
  `experiment_events` (**0 rows**), `experiment_assignments` (1 row), `promotion_record`, `agent_remediation`,
  `improvement_lifecycle` and `metric_lifecycle` workflows (it is a step actor in both).
- **Cost machinery:** `ai_cost_log` (3,909) with `could_be_cheaper` and `fn`, `ai_spend_probe` (12,751),
  `ai_usage`, `fn_model_cost_usd(model, in, out, cached_in)`, `fn_cost_per_os(days)`, `model_policy` (62),
  `model_policy_by_identity` (120), `model_registry` (6), `llm_attempt` (69), `llm_calls` (78),
  `llm_failure_class`, `llm_route_health`, `v_ai_spend`, `v_cost_optimisation`, `v_llm_model_mix`,
  `v_llm_offpolicy`, `v_llm_calls_without_task_class`, and the two reflection caps in `decision_policy`.
- **Quality machinery:** `qa_results` (288), `review_chain` (8,403) with `violated_rule`, `review_queue` (1,396),
  `artifact_review` (**0 rows**), `agent_expectations` (203), `agent_reputation` (96), `challenge_record` (66),
  `red_episode` (58), `canon_eval_questions` (100), `canon_eval_runs` (29 rows; the 6 Sep audit records the last model-graded run as
  2026-08-10, so the instrument exists and has been idle since the paid hold).
- **Operating rhythm:** `day_cadence` (160) — the source of its own unmeasured KPI — `fn_company_reflect()`,
  `fn_company_reflect_night(date)`, `fn_decision_outcomes(kind, days)`, `fn_strategy_metrics()`.
- **Health surfaces:** `v_business_health` (measurable 94 / all-departments 31 / 22 unmeasurable / 15 open risks /
  25 open P1), `v_department_health`, `v_os_scoreboard`, `v_ai_agent_health`, `v_ai_observability`,
  `v_ai_quality_proxy`, `health_checks` (6,203), `health_state`.
- **Statistics it must be able to run in SQL:** proportions and their confidence intervals, the rule of three for
  zero-event data, median and percentile (`percentile_cont`), moving averages, before/after split comparison,
  population-change detection. All available in Postgres; none needs a model.
- **Never:** emit a composite score; grade against a reconstructed baseline; count a held call as an error; run a
  VOLATILE routine to answer a read question.

### 6. Academic knowledge

| Discipline | Framework | Lawful primary source |
|---|---|---|
| Statistical process control and quality | DMAIC, control charts, common vs special cause, measurement systems analysis (gauge R&R applied to a metric definition) | ASQ published CSSBB *Body of Knowledge* outline (freely published syllabus); ISO 7870 series *Control charts*; ISO 22514 *Statistical methods in process management* |
| Measurement theory | Construct validity, reliability, units and dimensional analysis, proxy risk | NIST/SEMATECH *e-Handbook of Statistical Methods* (public domain); JCGM 100 *Guide to the expression of uncertainty in measurement* (BIPM, freely published) |
| Experimental design | Power analysis, randomisation, sequential testing, why underpowered tests mislead | Open-licence design-of-experiments course notes; NIST/SEMATECH DOE chapters (public domain) |
| Causal inference | Difference-in-differences, interrupted time series, confounding by population change | Open-access methods papers under CC-BY; published guidance from national statistical offices |
| Theory of constraints and lean | Identify the constraint, the seven wastes, rework as hidden capacity | Public open-licence operations-management course material; ISO 18404 *Six Sigma and Lean competencies* |
| Performance management | Leading vs lagging indicators, goal cascading, Goodhart's law, gaming resistance | ISO 9001 clause 9 (performance evaluation); ISO 30414 *Human capital reporting guidelines* |
| Cost accounting for software | Unit economics, variable vs fixed cost attribution, cost per transaction | IFRS Foundation published standards summaries; open-licence managerial accounting texts (e.g. OpenStax, CC-BY) |
| Software quality | Defect taxonomy, rework rate, gate criteria | ISO/IEC 25010 *Systems and software quality models*; ISO/IEC 20246 *Work product reviews* |

**Certifications on record** (`public.role_certification`):

| rank | Certification | Body | Pass mark | Syllabus areas |
|---|---|---|---|---|
| 1 | CSSBB (Six Sigma Black Belt) | ASQ | 73% | Organization-wide Planning and Deployment; Team Management; Define; Measure; Analyze; Improve; Control; Design for Six Sigma |
| 2 | PMP (Project Management Professional) | PMI | 61% | People; Process; Business Environment; Predictive Plan-Based Methodologies; Agile and Hybrid Approaches |

**Syllabus areas failed: does not exist.** No `certification_exam_result` row is for `cpo`; neither certification has
been sat. The internal knowledge exam (`knowledge_exam_results`) gives 30 graded answers — 10 correct, 8 partial,
4 wrong, 8 not_covered, the best of the three exec seats. The 6 Sep audit records that this was **10/10 pack-file
recall and 0 domain questions**: the exam measured whether the seat could recall the file it was given, not whether it
can diagnose. Contamination in its learned layer today includes `exam:1023 rfq_quality_gate.yaml` (Bearings & Power
Transmission), `exam:1024 quote_comparison_contract.yaml`, `exam:780 Notification & Communications scenario 03` —
category-route material written into a performance seat.

Its single profession row is **"Product on a two-sided anonymous marketplace"** — a product-design paragraph, not a
performance-management row. The seat whose whole job is diagnosis holds no diagnostic method in its own profession
layer, and its department holds 0 senior-expert records.

### 7. Corporate knowledge

**Its own KPIs** (`employee_kpi`, measured 2026-09-07 03:30 UTC):

| id | KPI | Target | Actual | Verdict |
|---|---|---|---|---|
| 76 | Daily operating rhythm — stages of the daily loop producing evidence | 100% | **null** | Never measured. The KPI that says the loop works has no value. |
| 73 | Improvements graded — closed with a verdict, not left open | 80% | 43.30% | Missing by half |
| 74 | Improvements that worked | 60% | 76.19% | Met |
| 72 | KPI measurability — share of active KPIs measurable at all | 100% | 88.33% (of 120 active rows) | Missing |
| 75 | Over-specified AI calls | ≤ 10% | 39.93% | Missing by 4× |
| 35 | "Strategy & Performance Director — primary objective" | 100% | 93.75% | Inherited from the parked seat; identical `measure_sql` to three other exec KPIs |
| 71 | Company KPI attainment | 70% | — | **RETIRED 6 Aug 2026**: it selected from `fn_kpi_scoreboard()` while inside it and recursed to statement timeout; one row made all 95 KPIs unmeasurable and `kpi_review_weekly` had never once succeeded. |

Row 71's retirement note is the single most important piece of corporate knowledge this seat holds, and it must be
able to state it: a measure must never read the instrument it is part of.

**Its authority:** the only exec seat at AED 0 on every class. `recommend`, `coordinate` and `exec_review` autonomous;
`qa_gate` **gated**; `escalate_founder` **advisory**. It changes how the company works and never what it spends.

**Its workflows:** `change_deployment`, `metric_lifecycle`, `improvement_lifecycle`, `strategic_review` (step actor);
`employee_task`, `campaign_publishing` (approver).

**Company thresholds it enforces:** `decision_policy` — `confidence_min` 0.6, `auto_action_max_aed` 0,
`financial_review_aed` 10,000, `cos_reflection_tasks_per_day` 500, `workflow_reflection_steps_per_day` 2,000,
`fraud_score_max` 0.7, `match_relevance_floor` 35, `matching_strike_limit` 3, `dispatch_max_open_per_dept` 250.
`department_budget` degrade at 70%, halt at 95%.

**Company reality it must never forget:** 0 reveals, 0 inquiries, 0 quotes, 1 customer, 1 verified supplier, 0 open
categories, AED 0 revenue. Every performance verdict it issues is a verdict about a company that has not yet traded,
and the correct diagnosis for most of its zeroes is `no throughput`, not `under-performance`.

**Open findings against its department** (from its own `improvement_plan`): "Employee has no measurable KPI";
"Agent failing repeatedly"; 331 deliverables returned by review recently, the recorded reason being
`grounded_in_this_business`.

**Who it hands to:** `ceo` (verdicts and unreachable targets); `brief` (process defects and stalls);
`people_ops`/`learning_dev_mgr` (KPI assignment, the exam remit, curriculum); `cto`/`product_eng` (model routing,
instrumentation); `cfo` (cost attribution, unit economics); every department head (KPI-miss diagnoses).

**What does not exist for this seat:** a definition of a valid baseline; a failure-mode set for measurement validity;
the KPI-miss cause taxonomy beyond two bands; an AI cost model record inside `exec` scope; a review-return taxonomy;
any external benchmark; `experiment_events` rows; `artifact_review` rows; a `dept_library` for `exec`;
a performance-management profession row.

### 8. One-year plan

**Objective.** Make every number the company steers by trustworthy, then make the company measurably cheaper per
decision, so that when trading starts the instruments are already honest and the improvement loop already closes.

**Metrics it owns:**
1. **KPI measurability** — target 100%, measured 88.33% over the 120 active `employee_kpi` rows.
2. **Improvements graded** — target 80%, measured 43.30%.
3. **Over-specified AI calls** — ceiling 10%, measured 39.93%.
(Plus `Improvements that worked` 60% / 76.19% — met, and `Daily operating rhythm` 100% / **never measured**, which is
itself a Q1 item.)

**Its slice of AED 1,000,000: AED 0 of direct revenue, and one measurable cost reduction.** The only line in this
seat's plan that touches the P&L is AI cost: 38.9% of AED 154.22/month is **AED 60/month** of avoidable spend, AED 720
over the year. Against a target of AED 1,000,000 that is rounding, and this seat should say so rather than dress cost
work as revenue work. Its real contribution to the target is upstream of every number in the CEO's plan: without
`stages_ranked`, honest units, real baselines and a closed improvement loop, every strategic decision the company
makes for the next 358 days is made on instruments that have never been validated.

**The honest statement.** This seat cannot produce revenue and should not be given a revenue slice. It should be
judged on whether the company's numbers can be trusted — and today three of its own five KPIs miss, one has never
been measured, one duplicates three other rows, and one was retired for recursing into the scoreboard. That is the
work.

**Quarterly milestones:**

| Quarter | Milestone | Verified by |
|---|---|---|
| Q1 | All six M-P1 validity checks run over all 120 active `employee_kpi` and 14 `metric_definition` rows; the `supplier_response_rate` unit defect fixed; the duplicate `brief` KPI retired; `day_cadence` producing a measured value for KPI 76 | `employee_kpi.actual_value`; `metric_definition`; a re-run of the check |
| Q2 | A stored definition of a valid baseline; `outcome_record` graded share ≥ 80%; the six-band KPI-miss taxonomy recorded with its detecting queries | `employee_kpi` id 73; `ops_knowledge where dept_key='exec'` |
| Q3 | Avoidable AI share ≤ 10%; deterministic share measured and reported against the founder's ~95/5 doctrine; cost per decision reported weekly with a trend | `ai_cost_log`; `workflow_step_run.used_llm` |
| Q4 | KPI measurability 100% or an explicit, verified `no_measure_reason` on every exception; review-return taxonomy in use with return rates per department | `employee_kpi`; `review_chain.violated_rule` |

**Capacity check.** 85 runs in 7 days, 112 context assemblies in 30 days, `max_open_tasks` 50. Reviewing the 120
active KPIs and 14 metric definitions against six mechanical checks is 804 checks — a single SQL pass, not a capacity problem. The
constraint is not throughput; it is that the seat holds no stored method: one profession row, and that row is about
product design.

**Dependencies.** `people_ops`/`learning_dev_mgr` for KPI assignment and the exam remit; `product_eng`/`cto` for
instrumentation and model routing; `cfo` for cost attribution; `data_intel` for `dept_library` and the senior-expert
ingest; `brief` and `ceo` to accept diagnoses that say a target, not a seat, is the problem.

### 9. What this seat cannot do without a model

1. **Judging whether a metric's *label* honestly describes its *subject*** when the mismatch is semantic rather than
   structural. The six mechanical checks catch units, population, nulls, freshness and self-reference; a metric
   labelled "customer satisfaction" that measures ticket closure passes all six. Detecting that needs either a model
   or a human — today it needs a stored, human-authored subject definition per metric, which is the mitigation.
2. **Writing the narrative of a diagnosis for a cause outside the six bands.** New causes are emitted as
   `band = unclassified` with the evidence attached, never as invented prose.
3. **Reading an external benchmark document** and extracting a comparable figure with its population definition.
   Ingestion is a model task; once it is a row with all four required fields, every use is deterministic.
4. **Deciding whether a "NO INSTRUMENT EXISTS" claim is honest or avoidance** in a genuinely novel domain. The
   mitigation is mechanical and partial: search the schema for any table whose columns could serve the metric, and
   escalate the remainder to a human rather than accept or reject it.

Everything else in sections 1–8 runs with OpenRouter switched off.

---

## Measurement boundary

Every figure in this document was read from production `htdblwldjkcgjvmqkbeh` on 7 September 2026 between 08:01 and
10:05 UTC. Nothing was written; the only routines executed were STABLE (`fn_revenue_trajectory()`,
`fn_binding_constraint(90)`) and read-only views. No paid model call was made. Where this document says a thing
"does not exist", that is a measured absence — a zero row count or a null column — and the query that measured it is
named beside it. Where a number could not be measured, the text says unmeasured rather than substituting an estimate.

Two figures in this document are derived rather than read, and both are stated with their arithmetic: the AED 1,700
monthly burn (`sum(department_budget.monthly_aed)` over the 9 rows for period 2026-09) and the 1.86% upper bound on
the invite→register rate (rule of three, 3/161, from 161 sends and 0 registrations).
