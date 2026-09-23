# Company brain — Marketplace department

**Written 7 September 2026. Measured against production (`htdblwldjkcgjvmqkbeh`) on 7 Sep 2026 between
08:01 and 08:45 UTC. Nothing in this document was applied to production; it is a plan for the founder
to approve.**

**The binding constraint on every position in this section: no answer may depend on a language model at
run time.** Every resolver below is a table lookup, a set operation, an arithmetic score, a threshold
comparison or a template fill. Where a seat genuinely cannot answer without a model, it is named in that
seat's section 9 and nowhere else.

---

## What was measured before anything below was asserted

**Positions.** `public.org_agents where active and department='marketplace'` returns exactly seven seats:
`procurement` (Marketplace Director, seniority director, manager_key `ceo`, routing_tier director),
`doc_intel_manager` (Document Intelligence Manager, specialist, routing_tier director),
`inquiry_router`, `spec_commercial` (title *Supplier Matching & Dispatch Operator*), `quote_evaluation`,
`rfq_qualification_mgr`, `rfq_success` — the last five all `manager_key='procurement'`. Three further
rows are inactive and are **not** written up here: `boq_analyst` and `drawing_analyst` (both parked
4 Sep 2026 by STAFF_ORG merge, accountability moved to `doc_intel_manager`) and `inquiry_scoring`.

**The founder's rules, read live from `fn_company_hard_rules()` on 7 Sep 2026.** These are quoted
throughout and are never restated from memory:

1. **Reveal fee** — the *customer* pays **3.00%** of the selected quotation value. No cap, no discount,
   no promotional rate, no coupon, no free reveal (founder, 6 Sep 2026; `pricing_config` forbids them by
   constraint). Ex-VAT, once per reveal. Comparing quotes is free. Suppliers pay **no commission, ever**.
   Supplier registration is free for the first **1000** registrations (permanently exempt), then
   **AED 1000/year** — no calendar start date; charging begins with registration 1001, whenever that is.
2. **Top-3 comparison report** — however many quotations arrive (3 or 100+), the report ranks them **all**
   and shows the best **three** on technical **and** commercial merit. Never cheapest-wins.
3. **Supplier non-response ladder** — a revealed supplier must begin responding within **5 working days**
   of the customer's payment (UAE week Mon–Fri, public holidays excluded). No response by working day 3 →
   the Customer Success Director chases, customer copied. Still silent on working day 5 → the founder is
   notified for his final call. No response to that → refund. **Every refund of any amount is the
   founder's decision, never automatic.** The customer gets the **full** 3.00% back, nothing deducted, and
   is told banks take 7–14 working days. The supplier then owes 3.00% + **AED 250** administrative fee +
   **9% per annum** simple interest, and is blocked from matching until it is paid.
4. **Anti-circumvention** — identities stay anonymous until the reveal, no off-platform contact before it.
   A supplier taking an introduced customer off-platform within 24 months owes **AED 15,000 per incident
   or three times the fee, whichever is higher**, plus the unpaid fee.
5. **Category opening** — a category is OPEN once it has **10 verified registered suppliers**
   (`public.v_category_open`); matching an RFQ still needs at least **one confirmed** supplier.

**`public.pricing_config` (id=1, updated 2026-09-06 14:22 UTC).** `standard_reveal_rate` 0.03,
`promo_reveal_rate` 0.03, both caps 99 999 999, `reveal_currency` AED, `supplier_reg_fee` 1000,
`supplier_reg_period` yearly, `supplier_free_count` 1000, `supplier_charging_starts` NULL, `promo_until`
NULL, `auto_approve_suppliers` true, `chase_after_working_days` 3, `refund_window_working_days` 5,
`category_open_min_suppliers` 10, `bank_settlement_working_days_min/max` 7/14.

**`public.decision_policy` — the numbers the deterministic gates actually enforce.**
`match_relevance_floor` 35 · `match_max_fanout` 5 · `match_max_fanout_per_trade` 3 ·
`score_w_product` 40 · `score_w_brand` 20 · `score_w_project_type` 15 · `score_w_track_record` 15 ·
`score_w_size_fit` 10 · `matching_strike_limit` 3 · `use_capability_matching` true ·
`confidence_min` 0.6 · `fraud_score_max` 0.7 · `financial_review_aed` 10000 · `auto_action_max_aed` 0 ·
`sensitive_categories` = [fire, security, electrical, structural, gas, lifts, medical] ·
`refund_notify_after_working_days` 1 · `refund_reveal_fee_pct` 3 · `refund_admin_fee_aed` 250 ·
`refund_late_fee_annual_pct` 9 · `founder_review_gates` = [refund_decision, refund_outside_policy] ·
`dispatch_max_open_per_dept` 250 · `dispatch_max_batch` 500 · `legal_triggers` (10 phrases).

**Demand side — all zero.** `inquiries` 0 · `quotes` 0 · `transactions` 0 · `reveal_invoices` 0 ·
`quote_comparisons` 0 · `inquiry_matches` 0 · `inquiry_requirement` 0 · `quote_requirements` 0 ·
`inquiry_gate_required` 0 · `comparison_run_v2` 0 · `phase_d_quote_normalisation` 0 · `refunds` 0 ·
`supplier_perf` 0 · `customers` 1 · `documents` 10 (all status `done`).

**Supply side.** `leads` 22 265 rows (the supplier registry; `public.suppliers` **does not exist** —
`supplier_capabilities.supplier_id` is a foreign key to `leads(id)`). Of those: **verified 1**,
**matchable under `fn_is_matchable` 1**, banned 0, permanently_closed 2, matching_blocked 3,
`invited_at` not null **171**, claimed 0, signed 0, `approved_at` not null **0**, with an email 19 896,
with a trade licence number **1**. `supplier_capabilities` 15 306 rows (one per supplier):
**confirmed 1**, derived 15 305. Confirmed **and** matchable trade coverage is one supplier spanning
four trades: electrical 1, hvac 1, mep_general 1, plumbing 1. `v_category_open`: 86 categories,
**0 open**, maximum `verified_registered_suppliers` in any single category **0**, 19 regulated.
`supplier_score` 20 465 rows, of which **0** have `quotes_submitted > 0`.

**Vocabulary and specification assets that already exist.** `taxonomy_trade` 40 · `taxonomy_role` 8 ·
`category_keyword` 1 839 · `subcategory_keyword` 6 553 · `catalog_category_domain` 86 ·
`catalog_subcategories` 470 · `catalog_domains` 67 · `category_route_map` 16 · `kb_operational_route` 86 ·
`kb_operational_alias` 4 255 · `kb_operational_route_test` 344 · `category_agent_map` 84 ·
`subcategory_agent_map` 434 · `category_specs` 56 · `category_quote_specs` 141 (regex-matched spec
aspects per spec_group; security 5, glazing 5, joinery 4, plumbing 4, electrical 4, fire 4, hvac 4, the
rest 3 each) · `field_definition` 552 (9 shared, 543 trade-specific; 529 approved, 23
`question_for_founder`) · `field_definition_source` 880 · `mep_trade_pattern` 123 ·
`qualification_playbooks` 29 · `business_rules` 4 · `phase_b_sla_policy` 34.

**Knowledge already loaded for these seats.** `agent_knowledge`: procurement 22, quote_evaluation 12,
rfq_success 10, rfq_qualification_mgr 10, doc_intel_manager 9, spec_commercial 8, inquiry_router 7.
`employee_knowledge`: spec_commercial 24, procurement 14, quote_evaluation 14, rfq_qualification_mgr 14,
rfq_success 11 — **`inquiry_router` and `doc_intel_manager` have no `employee_knowledge` rows at all**.
`ops_knowledge where dept_key='marketplace'` = 105 rows: decision_playbook 29, failure_mode 27, kpi 18,
policy 10, authority 8, reference 7, remediation 6.

**Certifications** (`public.role_certification`, all 14 rows written 7 Sep 2026 06:06 UTC) are listed per
seat in each section 6. **`public.certification_exam_result` holds results for exactly one of these seven
seats**: `procurement` sat MCIPS twice on 7 Sep 2026 and failed both times — 27.50% (method `semantic`,
11/40) at 07:49 UTC and 10.00% (method `lexical`, 4/40) at 07:56 UTC, against a 50% pass mark. The other
six seats have **no exam result — they have not sat**. `certification_knowledge_gap` holds 23 rows
estate-wide and **none** for any of these seven seats.

**Two model-free engines already exist and are the foundation of this plan.**
`supabase/functions/quote_compare/deterministic.ts` computes the whole top-3 without a model, and
`supabase/functions/route_inquiry/index.ts` serves a deterministic retrieval shortlist when the
adjudicator is unavailable. Both currently label themselves `degraded`. **This plan's central proposal is
that the founder's constraint makes these the primary path, not the fallback, and that the word
`degraded` must come off them** — a permanent configured state is not a degradation.

**One measured regression to carry into the plan.** `match_eval_runs` id 11, ran 2026-09-07 05:00 UTC:
recall 100%, **precision 32%** over 5 cases. Run id 9 (2026-08-10) was precision **100%** on the same 5
cases. Matching now returns the same five suppliers for every case.

---

## Department-wide conventions used below

- **Answer types.** Each seat answers only within its enumerated taxonomy. An incoming question is matched
  by (a) exact alias hit in `kb_operational_alias` / `org_agent_alias`, then (b) weighted keyword hit in
  `category_keyword` / `subcategory_keyword`, then (c) `gte-small` embedding cosine over the seat's own
  `agent_knowledge` and `ops_knowledge` rows via `fn_ops_knowledge_match`. Embedding is free and in-region
  (`kb_embed`); it is not a language model call.
- **The refusal rule.** No match above threshold, or an input the resolver needs that is missing or stale,
  produces a refusal that names the missing input, cites the table it would have come from, and opens an
  `org_tasks` row addressed to the seat that owns that input. It never guesses and never returns a nearest
  neighbour as if it were an answer — a nearest neighbour is always found.
- **Composition.** Every answer is a template with computed slots. The templates live in
  `public.response_template` (13 rows today) and `public.messaging_template` (14 rows today); this plan
  adds the memo templates each seat needs, per seat below.
- **Escalation.** `founder_review_gates` is [`refund_decision`, `refund_outside_policy`] and nothing else.
  Any other "escalation" in this document means escalation to the accountable *role*, resolved through
  `org_role` / `org_role_alias`, never to the founder.

---

## procurement — Marketplace Director

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| P1 | Which of the 86 catalogue categories do we open next, given supply, demand signal and regulatory load? | allocation | monthly | ceo, growth | Supply spend lands in a category with no buyers — economics item 10(3) |
| P2 | Is category X open? (10 verified registered suppliers per founder rule 5) | gate | per RFQ | inquiry_router, spec_commercial, site | Telling a buyer we serve a category we cannot quote burns the first impression |
| P3 | May an RFQ dispatch into a category that is not open but has ≥1 confirmed supplier? | gate | per RFQ in a thin category | spec_commercial | Either a dead RFQ or a one-quote "comparison" that breaks rule 2 |
| P4 | What is the minimum viable supplier count for this specific category before we advertise it? | forecast | per category | growth, ceo | Advertising ahead of supply produces refunds, which is economics item 10(1) |
| P5 | Which trade should the 3-trade Dubai launch be? | allocation | once, revisited quarterly | ceo | The whole year-one plan hangs off this |
| P6 | Is the reveal fee correct for this quote? | pricing | per reveal | customer_experience, finance | A wrong fee is a legal exposure against published Terms |
| P7 | May we ever discount, cap, waive or promote the reveal fee? | pricing | whenever asked | anyone | Founder rule 1 forbids it; a yes is a direct breach |
| P8 | Should supplier registration charging start now? | pricing | quarterly | finance | Charging before registration 1001 breaks founder rule 1 |
| P9 | Is this RFQ safe to send to suppliers (no buyer identity leak)? | gate | per RFQ | spec_commercial | Anonymity is the product; one leak is unrecoverable |
| P10 | Has a supplier circumvented the platform? What is owed? | escalation | per report | rfq_success, legal | AED 15 000 or 3× the fee is unclaimable if not evidenced at the time |
| P11 | Should this supplier be blocked from matching? | gate | weekly | spec_commercial, supplier ops | Blocking a good supplier removes irreplaceable supply from a thin category |
| P12 | Should a blocked supplier be unblocked? | gate | weekly | supplier ops | An unpaid clawback re-entering matching |
| P13 | Which department owns this cross-boundary marketplace failure? | sequencing | weekly | ceo, ops_director | An orphaned failure is a failure nobody fixes |
| P14 | Is the matching engine's precision acceptable this week? | diagnosis | weekly | ceo | Precision 32% means four in five contacted suppliers should not have been |
| P15 | Is a supply coverage gap real, or did retrieval break? | diagnosis | per zero-fit RFQ | rfq_success | Telling a buyer "nobody serves you" when retrieval errored is a false statement to a customer |
| P16 | What is the department's AI spend against its AED 380/month budget? | gate | daily | finance | Halt at 95% stops the marketplace, not just the reflection |
| P17 | Should this RFQ be split into per-trade children? | sequencing | per multi-trade RFQ | rfq_qualification_mgr | An unsplit multi-trade RFQ gets quotes nobody can compare |
| P18 | How many suppliers may a single RFQ contact? | allocation | per dispatch | spec_commercial | Over-fanout is supplier spam; under-fanout is a thin comparison |
| P19 | Does this RFQ touch a sensitive category needing an authority credential? | gate | per RFQ | rfq_qualification_mgr | Sending a fire or lift job to an unapproved contractor is a safety and licensing exposure |
| P20 | Is this quote value above `financial_review_aed` (AED 10 000)? | gate | per quote | quote_evaluation | Autonomy above the review line breaches `decision_policy` |
| P21 | What is our contribution margin per reveal right now? | forecast | monthly | finance, ceo | A negative-margin reveal is worse than no reveal |
| P22 | Which categories should stop receiving supply acquisition spend? | allocation | monthly | growth | Spend on categories with no demand |
| P23 | Is the department's KPI set actually measuring this department? | diagnosis | monthly | people_ops | Four of the seven seats' KPIs currently return zero because there is no demand |
| P24 | Should we accept a supplier whose licence expires inside the quote validity window? | gate | per verification | rfq_qualification_mgr | A quote from a supplier who cannot legally deliver |
| P25 | What is the department's stance when a buyer asks for a supplier by name? | craft | occasional | customer_experience | Naming a supplier pre-reveal destroys the anonymity model |
| P26 | Does this RFQ duplicate one the same customer already posted? | gate | per RFQ | inquiry_router | Duplicate RFQs double supplier fatigue for one job |
| P27 | Should the top-3 report show fewer than three when fewer than three quotes arrive? | craft | per comparison | quote_evaluation | Rule 2 says rank all and show best three; padding is fabrication |
| P28 | Which seat handles an inbound that matches no seat's taxonomy? | sequencing | weekly | any seat | Unrouted work silently dies |
| P29 | Is this supplier's non-response on the ladder? Which working day are we on? | sequencing | per revealed transaction | rfq_success | Missing day 3 or day 5 breaks the founder's published ladder |
| P30 | Should the department pause dispatch entirely (back-pressure)? | gate | daily | ops_director | 250 open tasks per department is the declared ceiling |
| P31 | Is a matching-precision fix worth the fall it will cause in the fanout headline? | diagnosis | per change | ceo | A fix that makes the headline fall is still a fix |
| P32 | Which quarter's revenue milestone is this department behind on and why? | forecast | quarterly | ceo, finance | Late detection of a year-one miss |
| P33 | Is an inbound "urgent" RFQ genuinely urgent or self-declared? | diagnosis | per RFQ | rfq_success | Urgency inflation destroys the SLA signal |
| P34 | Does this decision need Legal? | escalation | per case | any seat | `legal_triggers` names ten phrases that must never be auto-answered |

### 2. Domain logic (the models this seat reasons with)

**M-P1 — Category readiness index.**
`readiness(cat) = min(1, verified_registered(cat) / 10) × 0.5 + min(1, confirmed_capability(cat) / 3) × 0.3 + demand_signal(cat) × 0.2`
Inputs: `v_category_open.verified_registered_suppliers` (measured today: max 0 across all 86);
`supplier_capabilities` joined to `leads` under `fn_is_matchable` with `confirmed_at is not null`
(measured today: 1 supplier, 4 trades); demand_signal from `inquiries` grouped by category. Output: a
0–1 index and an OPEN/THIN/CLOSED band (OPEN ≥ 1.0 on the first term per founder rule 5).
**UNMEASURED:** `demand_signal` — `inquiries` holds 0 rows, so the third term is 0 for every category and
readiness is currently a pure supply index. Say so in the answer; do not present it as demand-aware.

**M-P2 — Reveal revenue identity.**
`reveal_revenue = Σ (selected_quote_value × 0.03)`, rate from `pricing_config.standard_reveal_rate`,
computed by `public.reveal_fee(amount, at_time)`. Cap is 99 999 999 and therefore never binds.
**UNMEASURED:** average selected quote value — `transactions` and `quotes` are both 0 rows. Every
revenue projection in this document is therefore stated as a function of an assumed average quote value,
never as a single number.

**M-P3 — Contribution per reveal.**
`contribution = reveal_fee − psp_fee − ai_cost_per_inquiry − refund_provision`
(`company_economics` id 5). psp ~2.9% + AED 1 (stated in `company_economics`, **not** measured from a
Stripe settlement — `stripe_events` holds 4 rows and `transactions` 0). `ai_cost_per_inquiry` from
`ai_cost_log` attributed by `fn`. `refund_provision` = P(non-response) × reveal_fee, and P(non-response)
is **UNMEASURED** — 0 reveals have ever occurred.

**M-P4 — Fanout budget.**
`fanout(rfq) = min(match_max_fanout, Σ_trades min(match_max_fanout_per_trade, eligible(trade)))`
with `match_max_fanout` 5 and `match_max_fanout_per_trade` 3 from `decision_policy`. Eligible set from
`fn_match_capability` filtered at `score ≥ match_relevance_floor` (35).

**M-P5 — Matching quality.**
`precision = |returned ∩ expected| / |returned|`, `recall = |returned ∩ expected| / |expected|`,
from `match_eval_runs.detail`. Measured 7 Sep 2026 05:00 UTC: precision 32, recall 100, 5 cases.
Alert rule: precision below 60 on the standing case set is a defect, not noise, because the same set
scored 100 on 10 Aug 2026.

**M-P6 — Supply gap attribution.**
A zero-fit RFQ is classified `genuine_gap` only when retrieval ran clean: no
`vector_rpc_error`, `kw_rpc_error`, `leads_fetch_error`, `approval_filter_error` or
`fallback_query_error` in the `route_inquiry` diagnostic block. Otherwise it is `retrieval_failure` and
must never be counted as a coverage gap. This distinction already exists in the function's log lines.

**M-P7 — Department budget burn.**
`burn_pct = spent_aed / monthly_aed`; marketplace `monthly_aed` = 380 for period 2026-09,
`degrade_at_pct` 70, `halt_at_pct` 95, `spent_aed` 0.0000 as of 2026-09-01 00:40 UTC.

**M-P8 — Circumvention claim.**
`owed = max(15000, 3 × unpaid_reveal_fee) + unpaid_reveal_fee`, per founder rule 4, within 24 months of
introduction. **UNMEASURED:** there is no `circumvention_claim` table. It **does not exist**.

### 3. Reasoning procedures

**P2 — "Is category X open?"**
1. Resolve X to a catalogue slug through `category_route_map` (16 rows) then `catalog_category_domain`
   (86 rows). No resolution → refuse, naming the unmapped string, and open a task to add the alias.
2. Read `v_category_open` for that slug: `verified_registered_suppliers`, `min_required`, `is_open`,
   `regulated`.
3. Verdict OPEN iff `is_open`. Today this returns CLOSED for all 86 (max verified = 0).
4. If CLOSED, compute the shortfall `min_required − verified_registered_suppliers` and, separately,
   whether ≥1 *confirmed* supplier exists (which permits matching under rule 5 even when closed).
5. Compose: verdict, the two counts, the shortfall, the named rule, and the date read.
Stops and refuses when: the slug does not resolve, or `v_category_open` is stale beyond 24 h.

**P14 — "Is matching precision acceptable?"**
1. Read the two most recent `match_eval_runs` rows.
2. Compute the delta in `precision_pct` and `recall_pct`.
3. If precision fell by more than 20 points against any earlier run on the same `cases_total`, classify
   `regression` and name the earliest run that scored higher (id 9, 100%, 2026-08-10).
4. Inspect `detail[].forbidden_hit`: if every case shares the same forbidden set, the failure mode is
   "the pool is not being filtered per case", which is a different defect from "scoring is wrong".
   Measured today: all five cases return the identical five-supplier fit list, so it is the former.
5. Compose with the case-level table. Open a defect task to `product_eng` naming the routine.
Stops and refuses when: fewer than two runs exist, or `cases_total` differs between runs.

**P15 — "Is this coverage gap real?"** Apply M-P6 verbatim. If `retrieval_failure`, the customer-facing
sentence "no supplier serves you" is **forbidden**; the answer is "we could not complete the search",
and a defect task is opened. This is the difference between a true statement and a false one to a
customer, and the seat treats it as a red line, not a nuance.

**P1 — "Which category next?"**
1. Compute M-P1 for all 86 categories.
2. Reject any category where `regulated` is true and the required authority credential is not held by at
   least three candidate suppliers (`taxonomy_trade.authority_required` intersected with
   `supplier_capabilities.authority_approvals`). 19 of the 86 are regulated.
3. Rank the survivors by readiness, then by directory depth (`leads` count filtered to the category
   through `category_keyword` weights), then by lowest authority load.
4. Return the top three with the flip condition: "this ordering flips if category Y gains N verified
   suppliers", N computed exactly.
Stops and refuses when: `demand_signal` is zero for all candidates — which is true today — in which case
the answer must state that the ranking is supply-only and cannot see demand.

**P6/P7 — reveal fee questions.** `reveal_fee(amount)` is the only source. Any request to discount, cap,
waive, promote or make free is answered NO with founder rule 1 quoted and the `pricing_config`
constraint named. There is no branch in which the answer is yes.

**P29 — non-response ladder.** Working days computed against `public.public_holidays` (16 rows) on a
Mon–Fri week. Day 0 = the payment timestamp on the transaction. Day 3 → chase (Customer Success
Director, customer copied). Day 5 → notify the founder for his call. The seat never issues the refund
itself; `founder_review_gates` contains `refund_decision`.

### 4. Judgement rules

| # | condition | verdict | reason |
|---|---|---|---|
| JP1 | A request to discount, cap, waive or promote the reveal fee, from anyone | REFUSE | Founder rule 1, 6 Sep 2026; `pricing_config` forbids it by constraint |
| JP2 | Category has ≥10 verified registered suppliers | OPEN | Founder rule 5 |
| JP3 | Category is closed but has ≥1 confirmed matchable supplier | MAY MATCH, MUST NOT ADVERTISE | Founder rule 5 splits these two permissions |
| JP4 | Zero fits **and** any retrieval diagnostic error present | NOT a coverage gap | A false "nobody serves you" is worse than a slow answer |
| JP5 | Fanout would exceed 5 for a single-trade RFQ | CLAMP to 5 | `match_max_fanout` |
| JP6 | Splitting a multi-trade RFQ would contact more suppliers in total than not splitting | CLAMP per-trade to 3 | `match_max_fanout_per_trade` exists precisely for this |
| JP7 | Supplier has 3 consecutive unanswered RFQs | STOP sending | `matching_strike_limit` 3, founder decision 3 Aug 2026 |
| JP8 | Supplier owes a clawback | BLOCKED from matching until paid | Founder rule 3 |
| JP9 | Quote value ≥ AED 10 000 | Human review before any money-affecting action | `financial_review_aed` |
| JP10 | Any money movement by an agent | FORBIDDEN | `auto_action_max_aed` = 0 |
| JP11 | Category in `sensitive_categories` and confidence < 0.6 | REVIEW, never auto-act | Safety and liability |
| JP12 | Text matches any of the 10 `legal_triggers` | ROUTE TO LEGAL, never auto-answer | `decision_policy.legal_triggers` |
| JP13 | A supplier tier would change who gets matched | REFUSE | Founder decision 8 Aug 2026: "a tier shouldnt effect a match" — encoded in `fn_supplier_tier.affects_matching=false` |
| JP14 | A supply-acquisition proposal in a category with zero demand signal **and** high readiness | DO NOT FUND even though it scores well | `company_economics` item 10(3): buying supply where there is no demand is one of the four things that destroy the economics |
| JP15 | A proposal to raise the fanout ceiling to fill a thin comparison | REFUSE even though it improves quotes-per-RFQ | Contacting marginal suppliers below score 35 is what `match_relevance_floor` exists to prevent; the fix is supply, not reach |
| JP16 | A metric improves because the denominator shrank | NOT an improvement | Report the base, always |
| JP17 | Department burn ≥ 70% of AED 380 | DEGRADE non-demand work first | `degrade_at_pct`; demand-linked work is never throttled |
| JP18 | A refund of any amount, however small | FOUNDER | Founder rule 3, restated 5 Sep 2026 |
| JP19 | A supplier asks to be shown as preferred | REFUSE | Every supplier is matched on fit alone |
| JP20 | An RFQ would go out with a buyer-identifying field | BLOCK DISPATCH | Anonymity is the product |

### 5. Technical knowledge

- **The routines this seat reads**, all confirmed present in `pg_proc` on 7 Sep 2026:
  `fn_match_capability`, `fn_is_matchable`, `fn_matching_strike_limit`, `match_suppliers_kw`,
  `match_suppliers`, `fn_rfq_score`, `fn_rfq_required_check`, `fn_inquiry_dispatch_eligible`,
  `fn_split_inquiry`, `reveal_fee`, `fn_supplier_tier`, `registered_supplier_count`,
  `fn_rfq_redispatch_sweep`, `fn_rfq_board`, `fn_suppliers_board`, `fn_freeze_supplier_brief`.
- **The views**: `v_category_open` (86 rows), `v_marketplace_liquidity` (exists), `v_supplier_load`,
  `v_supplier_match_exclusions`, `v_workstream_dispatch`.
- **The edge functions in this department's path** and which of them call `ai_gateway` today (measured by
  import): `route_inquiry`, `inquiry_parse`, `inquiry_intake`, `inquiry_ai`, `quote_compare`,
  `quote_extract`, `quote_review`, `doc_extract`, `drawing_boq`, `capability_agent`, `supplier_review`,
  `category_reqs`, `project_consultant` **all call the gateway**. `dispatch_inquiry`, `match`,
  `match_eval`, `inquiry_dedup_check`, `quote_quality` and `procurement_api` **do not**.
- **UAE regulatory mechanics this seat must hold as data, not as prose**: DEWA/SEWA/ADDC utility
  connection approval for electrical; Dubai Civil Defence for fire and life safety; SIRA for security and
  CCTV; Dubai Municipality for installed signage and displays; trade-licence activity codes; free-zone vs
  mainland licensing. Today these live scattered across `business_rules` (4 rows),
  `category_specs.compliance_checklist`, `taxonomy_trade.authority_required` and `regulations` (17 rows).
  **What must be stored so this seat can act alone:** a single `authority_requirement` table keyed
  (trade, emirate, work_type) → required approval, issuing authority, evidence document, validity period.
  It **does not exist**.
- **Working-day arithmetic**: `public_holidays` (16 rows) plus a Mon–Fri week. The seat must never compute
  a ladder day with a naive date difference.

### 6. Academic knowledge

Disciplines that generalise for this seat: **strategic sourcing and category management**, **two-sided
market design** (the liquidity constraint, cold-start, and which side to subsidise), **auction and
mechanism design** (sealed-bid, first-price, the winner's curse in construction tendering), **service
operations** (queueing and SLA design), and **UAE construction contract practice**.

Lawful primary sources we may ingest:

| framework | lawful primary source |
|---|---|
| CIPS Procurement Cycle, L4/L5/L6 syllabus structure | CIPS published syllabus outlines and qualification specifications (cips.org) |
| ISM CPSM competency model | ISM published exam content outline |
| ASCM/APICS SCOR reference model | ASCM published SCOR framework overview |
| FIDIC contract structure and risk allocation | FIDIC published guidance summaries and public contract-suite descriptions |
| UAE Federal Decree-Law 50/2022 (Commercial Transactions) — the 9% statutory interest basis in founder rule 3 | UAE Ministry of Justice / official gazette text |
| UAE Federal Decree-Law 45/2021 (Personal Data Protection) — anonymity and buyer-identity handling | UAE official gazette text |
| Dubai Civil Defence fire and life-safety code | DCD published code of practice |
| SIRA security-systems regulation | SIRA published regulations |
| Dubai Municipality building and signage regulation | DM published circulars |
| ISO 9001, ISO 45001 clause structure | ISO published standard abstracts and clause listings |
| Two-sided market theory | Published academic papers (Rochet–Tirole and successors) available open-access |
| Public construction cost indices for the UAE | Federal Competitiveness and Statistics Centre published series |

**Never** copyrighted study texts, CIPS/ISM course workbooks, or paywalled question banks.

Certifications this seat holds in `public.role_certification`: **MCIPS (CIPS Level 6 Professional
Diploma)**, issuing body CIPS, pass mark 50.00%, rank 1, syllabus areas Strategic Ethical Leadership,
Global Commercial Strategy, Global Strategic Supply Chain Operations, Category Management, Supply Network
Design, Strategic Programme Leadership; and **CPSM (ISM)**, pass mark 70.00%, rank 2, eight syllabus
areas.

**Syllabus areas it failed** (`certification_exam_result`, 7 Sep 2026 — the only seat in this department
with any exam record, and it failed both sittings): in the 27.50% semantic sitting —
L6M3 Global Strategic Supply Chain Operations 0/5, L6M2 Global Commercial Strategy 1/6, L6M9 Supply
Network Design 1/5, L6M4 Future Strategic Challenges 1/4, L6M5 Strategic Programme Leadership 1/4,
L6M8 Innovation in Procurement and Supply 1/4, L6M10 Global Logistics Strategy 1/3, L6M7 Commercial Data
Management 2/4, L6M1 Strategic Ethical Leadership 3/5. In the 10.00% lexical sitting, six areas scored
**zero**: L6M10, L6M2, L6M4, L6M5, L6M7, L6M9. The single largest and most repeated gap is **L6M9 Supply
Network Design**, which is precisely the P1/P4 category-opening decision this seat owns. Reading order for
this seat's knowledge build is therefore L6M9 → L6M2 → L6M3 → L6M5 → L6M7 → L6M10 → L6M4 → L6M8.

### 7. Corporate knowledge

- **The five hard rules** — `fn_company_hard_rules()`, read live, never memorised.
- **The founder's rulings this seat must not re-litigate**: refunds only to the founder (17 Aug 2026,
  restated 5 Sep 2026, `founder_review_gates`); a tier must never affect a match (8 Aug 2026, encoded in
  `fn_supplier_tier`); 3 strikes then stop (3 Aug 2026, `matching_strike_limit`); no discount, cap or free
  reveal (6 Sep 2026, `pricing_config`); AED 250 admin fee stays (6 Sep 2026, `decision_policy` +
  Supplier Agreement clause 33); category opens at 10 (6 Sep 2026).
- **Pricing** — `pricing_config` only. **Economics** — `company_economics` (10 rows, all flagged
  `every_employee_must_know`).
- **Workflows this seat owns**: `rfq_handling` (owner), `employee_task` (approver),
  `invoice_approval` (reviewer), `supplier_onboarding` (participant) — from `employee_workflow`.
- **Authority**: `employee_authority` gives this seat `gated` at AED 10 000 on all eight marketplace
  action classes (capability_enrich, supplier_verify, compare_quotes, route_category, qualify_inquiry,
  match_inquiry, supplier_approve_clean, invite), noted "Inherits department authority as head".
- **Seats it hands to**: `inquiry_router` (intake classification), `rfq_qualification_mgr`
  (completeness), `spec_commercial` (dispatch), `quote_evaluation` (comparison), `rfq_success`
  (chase and award), `doc_intel_manager` (documents); outward to `customer_experience` (the chase at
  ladder day 3), `finance` (reveal accounting, clawbacks), `legal` (the 10 `legal_triggers`),
  `growth` (which categories to advertise).
- **History it must not forget**: the marketplace has taken **0 inquiries, 0 quotes and 0 trades** to
  date; the 22 265 `leads` are a scraped directory asset, not customers; 171 suppliers have been invited
  and **0** have registered; matching precision was 100% on 10 Aug and is 32% today.
- **Where a stale statement lives**: `knowledge/COMPANY_CANON.md` is dated 24 Jul 2026 and still says the
  refund eligibility window is **3 working days** and that the founder approves "marketing posts, ad-boost
  budgets and refunds". Both are superseded — the window is **5** working days with a chase at 3
  (`pricing_config`, 6 Sep 2026), and the founder approves **refunds only**. This seat must read
  `fn_company_hard_rules()` and `pricing_config`, never the canon file, and should raise a task to correct
  the canon.

### 8. One-year plan

**Objective.** Own the marketplace half of the AED 1 000 000 year-one target (`company_goals.revenue_annual`,
deadline **2027-08-31**, owner_dept finance). Revenue identity from `company_economics` id 1:
`revenue = reveal_fees + supplier_registration_fees`.

**The arithmetic, stated honestly.** Registration revenue is **AED 0** for year one unless registration
1001 is reached, and registrations today are **0** (`leads.approved_at is not null` = 0). So the whole
AED 1 000 000 must come from reveals at 3%:

`required revealed quote value = 1 000 000 / 0.03 = AED 33 333 333`

| assumed average selected quote | reveals needed | reveals/month (12 mo) |
|---|---|---|
| AED 25 000 | 1 334 | 112 |
| AED 50 000 | 667 | 56 |
| AED 100 000 | 334 | 28 |
| AED 250 000 | 134 | 12 |

Average selected quote value is **UNMEASURED** (`quotes` 0 rows, `transactions` 0 rows), so the seat must
present the table, not a single number.

**Metrics this seat owns** (from `company_goals where owner_dept='marketplace'`): `rfq_completion_rate`
(share of inquiries reaching ≥1 submitted quote, target 80%), `quote_conversion_rate` (quoted inquiries
reaching a paid reveal), `matching_accuracy` (target 95%; measured 32% precision on the standing case
set). Also owned: `quotes_per_rfq` ≥5, `rfqs_successful` ≥95%, `suppliers_verified` 2 000,
`suppliers_active` 1 500, `supplier_retention` ≥90%, `qualification_time` <5 min, `matching_time` <30 s,
`supplier_response_time` <24 h.

**Quarterly milestones.**
- **Q1 (Sep–Nov 2026).** Move the deterministic engines from fallback to primary and drop the `degraded`
  label. Fix the precision regression to ≥80 on the standing 5-case set. Get **3 Dubai trades to 10
  verified registered suppliers** (rule 5) — that is 30 verified suppliers from a base of 1. Load
  `quote_requirements` (0 rows today) so `quote_gate` stops returning "no standard defined".
- **Q2 (Dec 2026–Feb 2027).** First paid reveal. Prove the ladder end-to-end against a rehearsal fixture.
  10 categories open. Target 30 reveals in the quarter.
- **Q3 (Mar–May 2027).** 25 categories open, 200 reveals in the quarter, `quotes_per_rfq` ≥3 measured.
- **Q4 (Jun–Aug 2027).** 40 categories open, 400+ reveals in the quarter.

**Capacity check — the honest answer.** *This seat's work cannot produce AED 1 000 000 by 31 Aug 2027 from
today's position, and the constraint is not this seat's throughput.* Deterministically:
`fn_match_capability` requires `confirmed_at is not null` **and** `fn_is_matchable`. Exactly **one**
supplier satisfies both, across four trades. Until that number is in the hundreds, the department can
qualify, route, dispatch, compare and reveal perfectly and still produce zero revenue, because there is
nobody to quote. Founder rule 2 compounds it: a top-3 report needs at least three quotes to be a
comparison rather than a formality, and three quotes need materially more than three matched suppliers
once non-response is priced in.

**What would make it achievable.** Two dependencies, both outside this department:
(a) **Supplier registration conversion** — 171 invited, 0 registered. Every downstream number is
multiplied by this ratio and it is currently zero. Owner: supply / growth.
(b) **Buyer demand** — `inquiries` 0, `customers` 1, and `company_economics` records buyer CAC as
"currently unmeasurable: marketing_golive is false". Owner: growth.
With 300 verified suppliers concentrated in 3–5 Dubai trades and a live buyer channel, the 56 reveals a
month at an AED 50 000 average is reachable. Without both, no arrangement of this department's work gets
there, and the seat should say so rather than forecast a number it cannot produce.

**Dependencies on other seats.** `doc_intel_manager` for BOQ-derived RFQ line items;
`rfq_qualification_mgr` for the completeness gate; `spec_commercial` for dispatch;
`quote_evaluation` for the rule-2 report; `rfq_success` for the ladder; finance for reveal accounting and
clawbacks; legal for the circumvention claim mechanics that **do not exist** as a table today.

### 9. What this seat cannot do without a model

- **Nothing in its taxonomy.** Every P-type above resolves to table reads, set operations and arithmetic.
- The one adjacent thing it must **stop** doing rather than model: writing free-prose strategic narrative
  for board consumption. Replace with a template whose slots are the computed figures above. That is a
  scope change, not a model dependency.

---

## inquiry_router — Inquiry Router

Responsibility of record (`org_agents.responsibilities`): *"Classify every incoming inquiry to a trade
category and route it to the owning specialist desk. Detect multi-trade scope and split it. Refuse to
guess: an unroutable inquiry is escalated with the reason, never routed to the nearest thing."*

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| R1 | Which trade code does this free-text request belong to? | diagnosis | every inquiry | intake, customer | Wrong trade → wrong suppliers → zero usable quotes |
| R2 | Which catalogue category (of 86) and subcategory (of 470)? | diagnosis | every inquiry | intake | Wrong category breaks the open/closed gate and the spec checklist |
| R3 | Is this single-trade or multi-trade? | diagnosis | every inquiry | rfq_qualification_mgr | An unsplit multi-trade RFQ produces non-comparable quotes |
| R4 | If multi-trade, which trades, and in what dependency order? | sequencing | per multi-trade | spec_commercial | Dispatching finishing before first fix wastes supplier time |
| R5 | Is this a turnkey/main-contractor job rather than a set of trades? | diagnosis | weekly | rfq_qualification_mgr | Splitting a turnkey job destroys the buyer's single point of responsibility |
| R6 | Which specialist desk owns this category? | sequencing | every inquiry | routing | Unowned inquiries die silently |
| R7 | Is this a supply-only, install-only, or supply-and-install request? | diagnosis | every inquiry | spec_commercial | `taxonomy_role` gates who can even quote it |
| R8 | Is the requested emirate stated, and is it one of the seven? | gate | every inquiry | spec_commercial | Coverage matching cannot run without it |
| R9 | Does this text match no route above threshold? | escalation | daily | any | Routing to the nearest thing is the named failure this seat exists to prevent |
| R10 | Is this actually an RFQ, or a support question / spam / a supplier enquiry? | diagnosis | every inbound | intake | A support question in the RFQ funnel wastes suppliers and skews every rate |
| R11 | Is this a duplicate of an inquiry the same customer already posted? | gate | every inquiry | rfq_qualification_mgr | Duplicate dispatch doubles supplier fatigue for one job |
| R12 | Does the text name a brand that implies a trade? | diagnosis | frequent | routing | Brand→trade inference is the cheapest strong signal we have |
| R13 | Does the text name a UAE authority (DEWA, SIRA, Civil Defence, DM) that implies a trade? | diagnosis | frequent | routing | Authority mentions are near-deterministic trade signals |
| R14 | Is the request in Arabic, English, or mixed? | craft | every inquiry | composition | The reply and the field labels must match |
| R15 | Does the request contain buyer-identifying content that must not reach suppliers? | gate | every inquiry | spec_commercial | Anonymity breach |
| R16 | Is the category regulated (19 of 86)? | gate | every inquiry | rfq_qualification_mgr | Sends a fire or lift job down an unregulated path |
| R17 | Does the inquiry name a product that maps to `products_norm`? | diagnosis | frequent | spec_commercial | 40 of the 100 match points hang on product hits |
| R18 | Is the stated scope large enough to trigger the AED 500 000 references rule? | gate | occasional | rfq_qualification_mgr | `business_rules` id 4 |
| R19 | Which of the 29 qualification playbooks applies? | sequencing | every inquiry | rfq_qualification_mgr | The wrong playbook asks the wrong mandatory questions |
| R20 | Which `category_specs` row (of 56) supplies the mandatory field set? | sequencing | every inquiry | rfq_qualification_mgr | The completeness gate has nothing to check against |
| R21 | Is this an emergency/urgent job requiring a different SLA? | diagnosis | occasional | rfq_success | Urgency inflation destroys the SLA signal |
| R22 | Does the request belong to a category that is closed? | gate | every inquiry | procurement | Accepting a request we cannot service |
| R23 | Should an ambiguous request be clarified rather than routed? | escalation | frequent | customer | One clarifying question beats a wrong route |
| R24 | Which clarifying question, exactly, would resolve this ambiguity? | craft | frequent | customer | A vague clarification wastes the customer's only patience |
| R25 | Is a second trade implied but not stated (e.g. "new DB board" implies DEWA approval work)? | diagnosis | frequent | rfq_qualification_mgr | A missing implied trade produces a quote that cannot be delivered |
| R26 | Does the routing decision need to be re-run because the taxonomy changed? | sequencing | monthly | data_intel | Stale routes silently mis-send |
| R27 | Is the routing accuracy of this seat within target? | diagnosis | weekly | procurement | 90% target, currently unmeasurable |
| R28 | Does this inbound match a `legal_trigger` phrase? | escalation | rare | legal | Ten phrases must never be auto-answered |
| R29 | Is the customer asking for a named supplier? | escalation | occasional | customer_experience | Naming pre-reveal breaks anonymity |
| R30 | Should this inquiry be attached to an existing project rather than standing alone? | sequencing | occasional | rfq_qualification_mgr | Fragmenting one project into unrelated RFQs |

### 2. Domain logic

**M-R1 — Deterministic route score (no model).**
For each candidate route r (a `kb_operational_route`, 86 rows) over the normalised inquiry text T:

`route_score(r) = Σ_p [ weight(p) × hit(p, T) × sign(p) ]`

where p ranges over `category_keyword` (1 839 rows: `slug`, `pattern`, `weight`, `negative`) and
`subcategory_keyword` (6 553 rows). `sign(p)` is −1 when `negative` is true. Matching uses
`fn_text_matches_pattern` / `fn_term_matches` (already present, language-aware). Alias expansion comes
from `kb_operational_alias` (4 255 rows).
Output: ranked routes with scores. Verdict thresholds are **new and must be set from the 344 rows in
`kb_operational_route_test`**, which is the labelled set this estate already holds:
- top score < `T_refuse` → refuse and ask one clarifying question;
- top score ≥ `T_accept` **and** margin over the runner-up ≥ `T_margin` → route;
- otherwise → clarify.
**UNMEASURED:** `T_refuse`, `T_accept`, `T_margin` **do not exist**. They must be fitted against
`kb_operational_route_test` before this seat runs, and the fitted values recorded in `decision_policy`.

**M-R2 — Embedding corroboration, never the decision.**
`gte-small` cosine over `leads.embedding_gte` and the route corpus, via `kb_embed` (free, in-region).
Used only to **corroborate** a lexical winner or to **break a tie**, never to produce a route on its own,
because a nearest neighbour is always found. A route selected by embedding alone with no lexeme hit is a
refusal, not a route.

**M-R3 — Multi-trade detection.**
`trades(T) = { t ∈ taxonomy_trade : score_t(T) ≥ T_trade }` using `fn_norm_trades` over
`taxonomy_trade` aliases and `mep_trade_pattern` (123 rows) plus `mep_trade_route` (6) and
`mep_evidence_weight` (7).
`multi = |trades(T)| ≥ 2`. Turnkey override: if the text matches the turnkey lexeme set already encoded
in `match_suppliers_kw` (`turnkey`, `fit-out`, `fit out`, `renovation`, `general contract`,
`main contract`, `interior`), classify **turnkey** and do **not** split — a turnkey buyer wants one
counterparty.
Split executed by `fn_split_inquiry(parent, trades[])`, which is idempotent (never splits a parent twice)
and marks the parent `status='split'`, `rfq_ready=false` so it is never dispatched itself.

**M-R4 — Authority implication.**
`implied_authority(T) = { a : a ∈ taxonomy_trade.authority_required for any t ∈ trades(T) }`.
Measured: `electrical → electrical_utility`, `fire_fighting → civil_defence`; the other 38 trades declare
none. Textual authority mentions (DEWA, SEWA, ADDC, SIRA, Civil Defence, Dubai Municipality, Trakhees,
DDA) are a **positive trade signal** with a high weight.

**M-R5 — Duplicate detection.**
`recent_duplicate_inquiry(customer, summary, window)` exists in production. It is a text-similarity check
over the same customer's recent inquiries. **UNMEASURED:** the window and the similarity threshold it
uses have never been exercised — `inquiries` holds 0 rows.

**M-R6 — Language detection.** Arabic script range detection on the raw text; no model. `qd_i18n`
(30 rows) and `field_definition.label_ar` (present on all 552 rows) carry the Arabic surface.

**M-R7 — Routing accuracy.**
`accuracy = routed_first_time_without_escalation / total_inquiries`. Target 90% (`employee_kpi` id 96).
**UNMEASURED and honestly so** — the KPI row itself records `no_measure_reason`: "NEEDS DEMAND THAT DOES
NOT EXIST. customers, inquiries, quotes and transactions are all 0."

### 3. Reasoning procedures

**R1/R2 — "Which trade and category?"**
1. Normalise T: lowercase, strip punctuation, expand `kb_operational_alias`.
2. Run M-R1 over all 86 routes. Keep the full ranked list, not just the winner.
3. Run M-R4: any authority mention adds its implied trade at high weight.
4. Run M-R2 as corroboration only. If the lexical top score has **zero** lexeme hits, discard the
   embedding suggestion and go to step 7.
5. If `top ≥ T_accept` and `margin ≥ T_margin` → route. Record the winning lexemes as the reason.
6. If `T_refuse ≤ top < T_accept`, or the margin is thin, generate **one** clarifying question chosen from
   `field_question_variant` (22 rows) for the field that best discriminates the top two routes — i.e. the
   `field_definition` whose `allowed_values` partition the two candidates.
7. Otherwise refuse: name the top three candidates with their scores, state that no route cleared the
   threshold, and open a task to `data_intel` to add the missing alias.
Stops and refuses when: the text is under a minimum token count, the thresholds are unset, or
`kb_operational_route` is stale.

**R3/R4 — "Single or multi-trade, and in what order?"**
1. Compute M-R3.
2. Turnkey check first — it overrides the split.
3. If multi and not turnkey, order the trades by construction dependency using a stored
   `trade_precedence` edge list (demolition → civil → MEP first fix → gypsum/partitions → MEP second fix →
   finishes → joinery → cleaning). **This edge list does not exist** and must be added; it is 40 nodes and
   perhaps 60 edges, all deterministic.
4. Call `fn_split_inquiry`. Report parent → children with the trade on each.
Stops and refuses when: fewer than two trades clear `T_trade`, or the trade set contains a trade with no
confirmed matchable supplier (route it, but flag the child as un-dispatchable and say why).

**R9/R23/R24 — the refusal path.** This is the seat's defining behaviour and it must never be softened.
The refusal names: the text it could not route, the top three candidate routes with scores, the threshold
it failed, the single clarifying question that would resolve it, and the task opened. It never returns
"probably electrical".

**R10 — "Is this even an RFQ?"** Classify against four disjoint lexeme sets held as data: RFQ intent
(quote, price, supply, install, tender, BOQ), support intent (refund, login, password, invoice, complaint),
supplier intent (register, join, my company, we supply), and spam (URL density, no trade lexeme, known
bad domains in `app_blocked_domains`, 24 rows). Ties go to a clarifying question, never to RFQ.

**R25 — implied second trade.** A stored implication table: `new DB board → electrical + electrical_utility
approval`; `kitchen → joinery + plumbing + electrical`; `bathroom → plumbing + tiling + waterproofing`;
`false ceiling with lights → gypsum + electrical`; `CCTV → security + networking`. **This table does not
exist**; `mep_trade_pattern` (123 rows) is the nearest existing asset and covers MEP only.

### 4. Judgement rules

| # | condition | verdict | reason |
|---|---|---|---|
| JR1 | No route clears `T_accept` | REFUSE with one clarifying question | The seat's charter forbids routing to the nearest thing |
| JR2 | Embedding suggests a route with zero lexeme hits | REFUSE | A nearest neighbour is always found; corroborate by lexemes or not at all |
| JR3 | Turnkey lexeme present | DO NOT SPLIT even though multiple trades scored | A turnkey buyer bought single-point responsibility |
| JR4 | Two routes within `T_margin` | CLARIFY, do not pick the higher | A 51/49 route is a coin toss dressed as a decision |
| JR5 | Text names an authority (DEWA/SIRA/DCD/DM) | The implied trade is a hard positive, not a hint | Authorities do not appear by accident |
| JR6 | Category is regulated | Attach the authority requirement to the RFQ before routing on | Founder rule 5 plus `business_rules` |
| JR7 | Duplicate of the same customer's recent inquiry | HOLD and ask, do not dispatch | Supplier fatigue is the scarcest resource we have |
| JR8 | Text matches a `legal_trigger` | LEGAL, never auto-answer | `decision_policy.legal_triggers` |
| JR9 | Customer names a supplier | REFUSE to route to them | Anonymity is the product |
| JR10 | The category is closed | ROUTE ANYWAY but mark un-dispatchable and say why | Routing and dispatch are different permissions (founder rule 5) |
| JR11 | Arabic input | Reply and field labels in Arabic | `field_definition.label_ar` exists on all 552 rows; using English is a choice, not a limitation |
| JR12 | A route scores well because a generic word matched (e.g. "supply", "service") | SUPPRESS via a negative keyword | `category_keyword.negative` exists for exactly this |
| JR13 | Routing accuracy cannot be computed | Say "unmeasured, no demand", never report 0% or 100% | Zero cannot tell a dead guard from an idle system |

### 5. Technical knowledge

- **Tables**: `kb_operational_route` (86), `kb_operational_route_map` (426), `kb_operational_alias`
  (4 255), `kb_operational_route_test` (344 labelled cases), `category_keyword` (1 839, with `weight`
  and `negative`), `subcategory_keyword` (6 553), `category_route_map` (16), `catalog_category_domain`
  (86), `catalog_subcategories` (470), `taxonomy_trade` (40), `taxonomy_role` (8), `mep_trade` (5),
  `mep_trade_pattern` (123), `mep_trade_route` (6), `mep_evidence_weight` (7), `category_agent_map` (84),
  `subcategory_agent_map` (434), `app_blocked_domains` (24), `qd_i18n` (30).
- **Routines**: `fn_kb_route(text,int)`, `fn_kb_route_decide(text)`, `fn_kb_route_test_run(int)`,
  `fn_text_matches_pattern`, `fn_term_matches`, `fn_route_party`, `fn_split_inquiry`,
  `recent_duplicate_inquiry`, `trg_inquiry_enrich`, `trg_inquiry_received`.
- **What must be stored so this seat can act without asking anyone**: (a) the three thresholds
  `T_refuse` / `T_accept` / `T_margin` in `decision_policy` — **do not exist**; (b) the
  `trade_precedence` edge list — **does not exist**; (c) the implied-trade table — **does not exist**;
  (d) the four intent lexeme sets for R10 — **do not exist**.
- **Standards and formats**: UAE emirate names and their Arabic forms (`mdm_emirates`, 7 rows);
  UAE trade-licence activity vocabulary; `mdm_brands` (51), `mdm_manufacturers` (22), `mdm_standards`
  (22), `mdm_units` (23) for brand→trade and unit normalisation.

### 6. Academic knowledge

Disciplines: **information retrieval and text classification** (lexical scoring, precision/recall
trade-offs, threshold calibration), **taxonomy and ontology design** (facets, polysemy, the difference
between a category and a trade), **construction trade taxonomy**, **Arabic/English bilingual
lexical processing**, and **decision theory under abstention** (when refusing beats guessing).

Lawful primary sources: CIPS published syllabus outlines (Defining Business Needs); ASCM published SCOR
overview; UN **CPC** and **UNSPSC** published classification code lists; **NACE / ISIC Rev.4** published
economic activity classifications; **MasterFormat / Uniclass** published table structures for construction
work sections; UAE Federal Competitiveness and Statistics Centre published business-activity
classifications; Dubai DED / DET published trade-licence activity lists; W3C **SKOS** specification for
concept schemes; **Unicode CLDR** Arabic data. Never copyrighted study texts.

Certifications held (`role_certification`): **CIPS Level 4 Diploma in Procurement and Supply** (CIPS,
pass 50.00%, rank 1) — syllabus areas Scope and Influence of Procurement and Supply, Defining Business
Needs, Commercial Contracting, Ethical and Responsible Sourcing, Commercial Negotiation, Supplier
Relationships, Whole Life Asset Management; and **CSCP (ASCM/APICS)** (pass 70.00%, rank 2) — Supply Chain
Design, Supply Chain Planning and Execution, Supply Chain Improvement and Best Practices, Sourcing and
Supplier Management, Logistics and Warehousing, Demand Management.

**Syllabus areas failed: none recorded — this seat has never sat either exam.**
`certification_exam_result` holds no row for `inquiry_router`, and `certification_knowledge_gap` holds
none either. That is an absence of evidence, not a pass. The first quarterly milestone below is to sit
both.

### 7. Corporate knowledge

- The charter sentence in `org_agents.responsibilities` is the seat's red line: *refuse to guess*.
- The five hard rules; in particular rule 5, because routing and dispatching are separate permissions.
- **Authority**: `employee_authority` gives this seat exactly one row — `analysis`, `supervised`, no
  threshold, seeded 14 Aug 2026. **It has no `route_category` authority row**, even though routing is its
  entire job. That is a gap in the authority ledger and should be corrected before the seat runs.
- **Knowledge**: 7 `agent_knowledge` rows. **`employee_knowledge` holds zero rows for this seat** — it is
  one of only two marketplace seats with none.
- **KPI**: one row, "Inquiries routed without escalation", target 90% weekly, with
  `no_measure_reason` recorded. The seat must quote that reason rather than report a number.
- **Hands to**: `rfq_qualification_mgr` (with the chosen `category_specs` row and playbook),
  `spec_commercial` (with the trade set and emirate), `procurement` (unroutable escalations),
  `legal` (trigger phrases), `customer_experience` (support-intent inbounds).
- **History**: `match_eval_runs` shows the five standing routing cases scoring 100% precision on
  10 Aug 2026 and 32% on 7 Sep 2026 with the identical five-supplier fit list returned for every case —
  the pool is not being filtered per case. This seat must not be blamed for a matching-pool defect, and
  must not absorb it silently either.

### 8. One-year plan

**Objective.** Every inquiry reaches the right desk with the right trade set, first time, without a model.

**Metrics owned.** (1) `routing_accuracy` — routed first time without escalation, target 90%
(`employee_kpi` id 96). (2) `refusal_precision` — of refusals, the share that a later human or
structured answer confirms were genuinely unroutable; target ≥80%, because a seat that refuses everything
is as useless as one that guesses. (3) `clarification_efficiency` — inquiries resolved after exactly one
clarifying question; target ≥70%.

**Quarterly milestones.**
- **Q1.** Fit `T_refuse`/`T_accept`/`T_margin` against the 344 `kb_operational_route_test` rows and store
  them in `decision_policy`. Build the `trade_precedence` edge list and the implied-trade table. Sit CIPS
  L4 and CSCP. Target: ≥85% accuracy on the 344 stored cases with a model switched off.
- **Q2.** Arabic parity: every refusal and clarification available in both languages from
  `field_definition.label_ar`. Route the first real inquiries.
- **Q3.** Expand the labelled test set from 344 to ≥1 000 cases drawn from real inbound. Accuracy ≥90%
  on the expanded set.
- **Q4.** Hold ≥90% while category coverage grows from 3 trades to 40.

**Capacity check.** Yes — this seat can carry its slice. Routing throughput is a Postgres query over
1 839 + 6 553 patterns; at 25 000 RFQs a year (`company_goals.rfqs_processed`) that is 68 a day, which is
nothing. **The seat's slice of revenue is indirect**: it owns no revenue metric. Its contribution is that
a mis-routed RFQ produces zero quotes and therefore zero reveal fee, so at 90% accuracy the department
loses 10% of its revenue potential at the very first step. On the AED 50 000 / 667-reveal scenario, each
point of routing accuracy is worth roughly **AED 10 000 of year-one revenue**.

**Dependencies.** `data_intel` owns `kb_operational_route` and the alias registry;
`doc_intel_manager` supplies extracted text when the request arrives as a document; `procurement` sets
the thresholds' governance.

### 9. What this seat cannot do without a model

- **Nothing in its taxonomy**, provided the thresholds are fitted and the three missing tables are built.
  Lexical scoring plus free in-region embedding corroboration covers R1–R30.
- **Honest caveat, not a model dependency**: a genuinely novel request using vocabulary absent from all
  1 839 + 6 553 patterns and 4 255 aliases will be **refused**, not routed. That is the designed and
  correct outcome, and the cost is a clarifying question rather than a wrong dispatch. A model would
  guess; this seat is instructed not to.

---

## rfq_qualification_mgr — RFQ Qualification Manager

Responsibility of record: *"Owns inquiry completeness: no RFQ reaches suppliers without the mandatory
fields for its category."*

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| Q1 | Is this RFQ complete enough to dispatch? | gate | every inquiry | spec_commercial | An incomplete RFQ gets guesses, not quotes; rule 2's top-3 becomes meaningless |
| Q2 | Which mandatory fields are missing, exactly? | gate | every incomplete RFQ | customer | A vague "please add detail" gets ignored |
| Q3 | What is the single next question to ask the customer? | craft | per incomplete RFQ | customer | Asking eight questions at once loses the customer |
| Q4 | Which `category_specs` field set applies here? | sequencing | every inquiry | self | The wrong checklist gates on the wrong things |
| Q5 | Which of the 29 qualification playbooks applies? | sequencing | every inquiry | self | Same |
| Q6 | Is a field genuinely answered, or answered with "n/a" / "tbc" / "as per drawing"? | diagnosis | frequent | self | A non-answer counted as an answer is the commonest way an incomplete RFQ escapes |
| Q7 | Does the attached document already answer this field? | diagnosis | frequent | doc_intel_manager | Asking for what the customer already sent is the fastest way to lose them |
| Q8 | Do two sources give conflicting answers for the same field? | escalation | occasional | customer | Suppliers quote different jobs |
| Q9 | Which answer wins when the customer's text contradicts the BOQ? | gate | occasional | doc_intel_manager | Precedence must be a rule, not a preference |
| Q10 | Is the quantity plausible for the stated area/scope? | diagnosis | frequent | self | An order-of-magnitude error produces useless quotes and wastes every supplier |
| Q11 | Is the stated budget plausible for the scope? | diagnosis | frequent | self | An unrealistic budget wastes a whole dispatch cycle |
| Q12 | Does this scope cross the AED 500 000 references threshold? | gate | occasional | spec_commercial | `business_rules` id 4 |
| Q13 | Does this scope cross the AED 1 000 000 fire-safety threshold? | gate | rare | spec_commercial, legal | `business_rules` id 1 requires ISO 9001, Civil Defence approval, PI insurance, manufacturer authorisation, and escalates |
| Q14 | Which authority approvals must the supplier hold? | gate | every regulated inquiry | spec_commercial | Sending a DEWA job to a non-registered contractor |
| Q15 | Is the required-by date achievable given typical lead times? | forecast | frequent | rfq_success | Promising an impossible date |
| Q16 | Is the delivery window stated and unambiguous? | gate | every inquiry | self | "ASAP" is not a date |
| Q17 | Is the site access / working-hours constraint captured? | gate | frequent | self | A quote priced for day work delivered as night work is a dispute |
| Q18 | Is this a variation on an existing RFQ rather than a new one? | sequencing | occasional | inquiry_router | Fragmentation |
| Q19 | Should a thin RFQ be dispatched anyway because the category is thin? | gate | occasional | procurement | Trading completeness for coverage is a decision, not a default |
| Q20 | Is a workstream dispatch-eligible? | gate | per workstream | spec_commercial | `fn_inquiry_dispatch_eligible` is the gate |
| Q21 | Which shared fields apply across every workstream of this group? | sequencing | per multi-trade | self | Asking the emirate three times |
| Q22 | Has the customer answered but with a value outside `allowed_values`? | gate | frequent | customer | Free-text where an enum was required breaks downstream matching |
| Q23 | Is the unit correct and normalised (sqm vs sqft, m vs lm)? | gate | frequent | quote_evaluation | Unit confusion is a 10× pricing error |
| Q24 | Does the RFQ contain buyer-identifying content? | gate | every inquiry | spec_commercial | Anonymity breach |
| Q25 | Should we stop asking and dispatch what we have? | gate | frequent | procurement | Over-qualifying loses more RFQs than under-qualifying |
| Q26 | How many clarification rounds has this RFQ had? | sequencing | per RFQ | rfq_success | Round three is where customers leave |
| Q27 | Has the customer's 24-hour response window expired? | gate | per pending RFQ | rfq_success | `SLA-CUSTOMER-INPUT` |
| Q28 | Is a mandatory field unanswerable by this customer (a homeowner asked for a load calculation)? | diagnosis | frequent | self | Gating on a question the customer cannot answer kills the RFQ |
| Q29 | Should the field be answered by us from stored reference data instead of asked? | craft | frequent | self | Every avoidable question is a conversion loss |
| Q30 | Is the completeness score's denominator honest? | diagnosis | monthly | procurement | A checklist with keyless fields inflates completeness |
| Q31 | Does this inquiry need a site visit before anyone can quote? | diagnosis | occasional | rfq_success | Quotes on an unvisited complex job are fiction |
| Q32 | Which fields, if answered, would most raise the quote comparability? | forecast | per RFQ | quote_evaluation | The point of qualification is comparable quotes, not full forms |

### 2. Domain logic

**M-Q1 — Generic RFQ readiness score (`fn_rfq_score`, exists in production).**
Points: category 20 · emirate 10 · scope detail (>20 alphanumeric chars in `spec`) 25 · scope_type 15 ·
budget 15 · supporting detail (trades **or** drawing path **or** BOQ) 15. `generic_ready = score ≥ 70`.

**M-Q2 — Category mandatory-field check (`fn_rfq_required_check`, exists).**
Reads `category_specs.fields` for the inquiry's category (56 rows exist). For each field with
`required=true`: satisfied if the key is answered directly, or a concept-equivalent key is answered
(`_rfq_concept`), or a token of the key (≥4 chars) matches an answered key, or one of the field's
`options` appears as a ≥4-char token in the blob of `summary + raw_input + spec`.
`required_ok = (missing = [])`. **A required field with no `key` is advisory only and never blocks** —
this is already in the function and is the correct behaviour, but it means the completeness denominator
excludes keyless fields, which section Q30 above exists to police.

**M-Q3 — Combined readiness.** `ready = generic_ready AND category_required_ok` (`fn_rfq_score`).

**M-Q4 — Workstream dispatch eligibility (`fn_inquiry_dispatch_eligible`, exists).**
Over `inquiry_workstream_group` → `inquiry_workstream` → `v_workstream_dispatch`:
eligible iff **every active workstream** has `mandatory_complete` ∧ `no_unresolved_conflict` ∧
`gates_passed`. Zero workstreams → eligible (a single-trade RFQ). Returns the blocking list with
`missing_mandatory` and `blocked_by` per workstream.
**UNMEASURED:** all of `inquiry_workstream`, `inquiry_workstream_group`, `inquiry_requirement`,
`inquiry_answer`, `inquiry_answer_conflict` hold **0 rows**. The machinery is built and unexercised.

**M-Q5 — Answer precedence (the Q9 rule).** `fn_inquiry_answer_set` takes an
`answer_precedence` enum and `fn_inquiry_answer_supersede` handles replacement. The precedence order this
seat must apply, highest first: **customer confirmation > tender/contract document > BOQ line >
drawing annotation > customer free text > our own inference**. An inference never wins.
**UNMEASURED:** the enum's declared ordering is in the type, not in a policy row; it must be written down
in `decision_policy` so this seat can quote it.

**M-Q6 — Non-answer detection (`_rfq_answered`, exists).** A value is not an answer if it is empty or in
the non-answer lexicon. The lexicon must include: `n/a`, `na`, `tbc`, `tba`, `-`, `?`, `as per drawing`,
`as discussed`, `standard`, `usual`, `any`, `don't know`, `not sure`, `asap`, `best price`, and their
Arabic equivalents. **UNMEASURED:** the current lexicon's contents were not read; it must be stated and
stored explicitly rather than being a regex nobody can quote.

**M-Q7 — Quantity plausibility (arithmetic, no model).**
For each (trade, unit) pair, a stored band `[min_ratio, max_ratio]` against the driving dimension:
e.g. flooring sqm ≈ 0.9–1.15 × floor area; skirting linear metres ≈ 0.7–1.1 × room perimeter;
gypsum ceiling sqm ≈ 0.85–1.05 × floor area; paint litres ≈ area_sqm / 8–12 per coat;
light points ≈ 1 per 4–9 sqm office; sockets ≈ 1 per 6–12 sqm office; AC tonnage ≈ area_sqm / 12–20
for UAE office load. Flag when outside the band; **never silently correct**.
**UNMEASURED:** this band table **does not exist**. It is roughly 40 trades × 2–4 dimensions and is
entirely deterministic.

**M-Q8 — Budget plausibility.** `expected_range(trade, unit, emirate) × quantity` vs stated budget.
Source would be `category_price_stats` — **which holds 0 rows**. Until it does, this seat must say
"budget plausibility is unmeasured; we hold no price statistics", not produce a band.

**M-Q9 — Clarification round budget.** Maximum **2** rounds, each with at most **3** questions, chosen by
discriminating power (Q32): rank missing fields by how many downstream gates they unblock
(`category_quote_specs` aspects, `business_rules` conditions, `fn_match_capability` inputs). After round 2,
either dispatch what we have (with the gaps named to suppliers) or close the RFQ. This budget **does not
exist** today and must be set.

### 3. Reasoning procedures

**Q1 — "Is this RFQ complete enough to dispatch?"**
1. `fn_rfq_score(i)` → generic score, have[], missing[].
2. `fn_rfq_required_check(i)` → category applicability, required_total, missing[], advisory_missing[].
3. `fn_inquiry_dispatch_eligible(i.id)` → workstream verdict and blocking list.
4. Verdict READY iff generic ≥70 **and** category required_ok **and** workstreams eligible.
5. If not ready, produce the **ordered** missing list by discriminating power (M-Q9), not by the order
   they appear in `category_specs`.
6. Compose: verdict, the three sub-verdicts with their numbers, the ordered gaps, the next question, and
   the SLA clock (`SLA-INQUIRY-FIRST-RESPONSE` 5 minutes; `SLA-CUSTOMER-INPUT` 24 hours).
Stops and refuses when: no `category_specs` row exists for the category (the function already returns
`applicable=false`, and the seat must say "no checklist exists for this category" rather than "complete").

**Q7 — "Does the attached document already answer this?"**
1. For each missing field, look for an `inquiry_answer_document` row linking a document to that field.
2. Where the document is a BOQ, look for a `boq` line whose `section`/`description` matches the field's
   `validation_ref` lexemes.
3. If found, set the answer with source_kind `document` at BOQ precedence and **do not ask the customer**.
4. If the document exists but nothing matched, say so — the customer sent a document and it did not
   contain the answer, which is a different message from "please send more detail".
Stops and refuses when: `inquiry_answer_document` holds 0 rows (it does today) — in which case the seat
must state that document-to-field linking is not yet exercised.

**Q8/Q9 — conflicts.** `inquiry_answer_conflict` and `inquiry_answer_conflict_value` exist (0 rows).
Procedure: gather all values for the field, apply M-Q5 precedence, and if the top two sources are at the
**same** precedence with different values, do not pick — raise the conflict to the customer with both
values and their sources shown verbatim.

**Q10 — plausibility.** Compute M-Q7. Outside the band → a clarifying question that shows the arithmetic:
"You have asked for 850 sqm of flooring for a 78 sqm apartment. Which is right?" Never correct silently,
never drop the RFQ.

**Q25 — "Stop asking and dispatch?"** Deterministic: dispatch when (a) round budget exhausted, **or**
(b) every remaining gap is advisory or keyless, **or** (c) the category is thin (fewer than 3 confirmed
matchable suppliers) and `procurement` has recorded a standing decision to prefer coverage over
completeness for it. In case (c) the RFQ goes out with the gaps **stated to the supplier**, so the quote
comes back with assumptions declared rather than hidden.

### 4. Judgement rules

| # | condition | verdict | reason |
|---|---|---|---|
| JQ1 | Generic score ≥70 but a category mandatory field is missing | NOT READY | `fn_rfq_score` requires both |
| JQ2 | No `category_specs` row for the category | SAY "no checklist exists" | Not "complete" — an absent gate is not a passed gate |
| JQ3 | A required field has no `key` | ADVISORY only, never blocks | Already in `fn_rfq_required_check`; a field we cannot address cannot be gated on |
| JQ4 | Field answered with a non-answer token | TREAT AS MISSING | `_rfq_answered` |
| JQ5 | Two sources conflict at the same precedence | ASK, do not pick | Picking manufactures a fact |
| JQ6 | Our own inference conflicts with a customer statement | CUSTOMER WINS, always | An inference never outranks the buyer |
| JQ7 | Quantity outside the plausibility band | ASK, never correct | Silent correction is fabrication |
| JQ8 | Clarification round 3 would be needed | DISPATCH WITH GAPS NAMED or CLOSE | Round three is where customers leave |
| JQ9 | Scope > AED 500 000 | Require client references and completed similar projects | `business_rules` id 4 |
| JQ10 | Fire category and > AED 1 000 000 | Require ISO 9001 + Civil Defence approval + PI insurance + manufacturer authorisation, and ESCALATE | `business_rules` id 1 |
| JQ11 | Security / CCTV category | Require SIRA approval and EN 62676 | `business_rules` id 2 |
| JQ12 | Electrical category | Require DEWA/authority NOC and BS 7671 | `business_rules` id 3 |
| JQ13 | A field is unanswerable by this customer type | ANSWER IT OURSELVES from reference data or DROP the gate | Gating on an impossible question kills the RFQ |
| JQ14 | Category is thin **and** the RFQ is 90% complete | DISPATCH even though it scores below the gate | Coverage beats perfection when there is one supplier; but the gaps must be named to that supplier |
| JQ15 | The completeness rate improved because keyless fields were added to the checklist | NOT an improvement | Report the denominator |
| JQ16 | A buyer-identifying value appears in any answered field | STRIP before dispatch, and flag | Anonymity is the product |
| JQ17 | The customer's 24-hour window expired | Reminder, then expire or continue by policy — never silently dispatch a stale RFQ | `SLA-CUSTOMER-INPUT` |
| JQ18 | Unit is ambiguous (sqm vs sqft) | ASK; never assume metric | A 10.76× error is not recoverable downstream |

### 5. Technical knowledge

- **Tables**: `category_specs` (56, with `fields`, `compliance_checklist`, `supplier_requirements`),
  `qualification_playbooks` (29, `category` + `questions[]` with `key`/`type`/`label`/`options`/
  `required`/`decision`), `field_definition` (552: 9 shared, 543 trade-specific; 529 approved,
  23 `question_for_founder`; every row carries `label_en`, `label_ar`, `answer_type`, `unit`,
  `allowed_values`, `numeric_tolerance`, `validation_ref`, `evidence_rule`, `applies_when`),
  `field_definition_source` (880), `field_question_variant` (22), `business_rules` (4),
  `inquiry_gate` / `inquiry_gate_required` (0 rows), `inquiry_requirement` (0),
  `inquiry_answer` + `_scope` + `_conflict` + `_conflict_value` + `_corroboration` + `_document` (all 0),
  `inquiry_workstream` + `_group` + `_requirement` (all 0), `mdm_units` (23), `public_holidays` (16).
- **Routines**: `fn_rfq_score`, `fn_rfq_required_check`, `_rfq_answered`, `_rfq_concept`,
  `fn_category_quote_ready`, `fn_category_checklist`, `fn_inquiry_dispatch_eligible`,
  `fn_inquiry_answer_set/confirm/supersede`, `fn_inquiry_workstream_activate/deactivate`,
  `fn_inquiry_interpret`, `trg_inquiry_gate_state_sync`, `trg_gate_incomplete_match`,
  `trg_inquiry_answer_value_domain`, `trg_inquiry_answer_value_immutable`.
- **What must be stored so this seat can act alone**: the quantity plausibility bands (M-Q7) — **do not
  exist**; the non-answer lexicon as data (M-Q6) — must be made explicit; the answer-precedence order in
  `decision_policy` (M-Q5) — **does not exist**; the clarification round budget (M-Q9) — **does not
  exist**; `category_price_stats` — table exists, **0 rows**, so budget plausibility is unmeasured.
- **Standards to hold as data**: unit systems and conversions (sqm/sqft, m/lm, kg/t, kW/TR);
  BS 7671 and EN 62676 clause identifiers as citation strings; Civil Defence and SIRA approval names;
  the UAE working week and `public_holidays`.

### 6. Academic knowledge

Disciplines: **requirements engineering** (completeness, consistency, traceability), **survey and
questionnaire design** (question order, discriminating power, respondent burden), **measurement and
units**, **construction quantity surveying** (measurement rules and quantity derivation), and
**decision analysis** (value of information — which question to ask first).

Lawful primary sources: CIPS published L4 syllabus outline (Defining Business Needs); ISM published CPSM
content outline; **RICS New Rules of Measurement** published summaries and RICS public guidance notes;
**CESMM / SMM7** published measurement-rule structures; **ISO 80000** quantities and units (published
abstract and clause list); **ISO/IEC/IEEE 29148** requirements-engineering standard abstract;
**BS 7671** published scope and part structure (IET public summaries); **EN 62676** published scope;
Dubai Civil Defence published code of practice; SIRA published regulations; UAE Federal Decree-Law
45/2021 for buyer-identity handling; UAE public-holiday circulars from the Ministry of Human Resources
and Emiratisation. Never copyrighted study texts or paywalled standard bodies' full texts.

Certifications held: **CIPS Level 4 Diploma in Procurement and Supply** (pass 50.00%, rank 1) and
**CPSM (ISM)** (pass 70.00%, rank 2).
**Syllabus areas failed: none recorded — this seat has never sat either exam** (no
`certification_exam_result` row, no `certification_knowledge_gap` row). Sitting both is a Q1 milestone.

### 7. Corporate knowledge

- The five hard rules, and specifically why completeness matters to rule 2: a top-3 comparison of quotes
  answering different questions is not a comparison.
- **Authority** (`employee_authority`): **autonomous** at AED 1 000 for `supplier_verify`,
  `compare_quotes`, `qualify_inquiry`; **advisory** at AED 1 000 for `capability_enrich`, `route_category`,
  `match_inquiry`, `supplier_approve_clean`, `invite` — "may prepare, but execution requires the
  department head". So this seat may qualify autonomously and may **not** dispatch.
- **Workflows**: `employee_task` (owner), `invoice_approval` (reviewer), `rfq_handling` (participant),
  `supplier_onboarding` (participant).
- **Knowledge**: 10 `agent_knowledge` rows, 14 `employee_knowledge` rows.
- **KPI**: one row, "RFQ Qualification Manager — primary objective", metric *RFQs reaching at least one
  submitted quote*, target 80% monthly, `measure_sql` present, `actual_value` null. Note this KPI does
  **not** measure qualification; it measures the whole funnel. A qualification-specific KPI (share of
  dispatched RFQs whose mandatory set was complete) **does not exist** and should be added.
- **Hands to**: `spec_commercial` (dispatch-eligible RFQs), `doc_intel_manager` (document-derived
  answers), `rfq_success` (clarification chasing), `quote_evaluation` (the mandatory set becomes the
  comparison baseline), `legal` (fire/high-value escalations under `business_rules` id 1).
- **History**: every one of the answer, requirement, workstream and gate tables holds **0 rows**. The
  qualification machinery is fully built and has never processed a real inquiry. It must be exercised
  against fixtures before the first customer, not on the first customer.

### 8. One-year plan

**Objective.** No RFQ reaches a supplier without the mandatory set for its category, and no customer is
asked a question we could answer ourselves.

**Metrics owned.** (1) **Dispatch completeness** — share of dispatched RFQs where
`fn_rfq_required_check.required_ok` was true at dispatch; target 100% (it is a gate, not an average).
(2) **Questions per RFQ** — target ≤3 in ≤2 rounds. (3) **Qualification time** — `company_goals`
`qualification_time` <5 minutes, owner_dept marketplace.

**Quarterly milestones.**
- **Q1.** Fill the four missing assets: quantity plausibility bands, non-answer lexicon, precedence order,
  round budget. Extend `category_specs` from 56 to all 86 categories. Exercise the workstream/answer
  machinery against `phase_d_fixture_catalogue` (157 rows) so it is not first exercised on a customer.
  Sit CIPS L4 and CPSM.
- **Q2.** Field-level answer coverage: every one of the 543 trade-specific `field_definition` rows
  reachable from a `category_specs` checklist, and the 23 `question_for_founder` rows resolved.
- **Q3.** Document-to-field linking live: `inquiry_answer_document` non-empty, and ≥40% of mandatory
  fields answered from an attached document rather than by asking.
- **Q4.** Hold 100% dispatch completeness at 40 open categories with ≤3 questions per RFQ.

**Capacity check.** Yes. Qualification is two SQL functions plus a template; throughput is not the
constraint. **The slice of revenue is conditional, not additive**: on the AED 50 000 / 667-reveal
scenario, `company_goals.rfq_completion_rate` targets 80% of inquiries reaching ≥1 quote. Completeness is
the largest single lever on that 80%, because an incomplete RFQ is the commonest reason a supplier does
not quote. If completeness moves the completion rate by 10 points, that is roughly **AED 100 000 of
year-one revenue**. That number is an assumption, not a measurement — there are 0 inquiries.

**Dependencies.** `inquiry_router` for the category and playbook selection; `doc_intel_manager` for
document-derived answers; `data_intel` for `category_specs` coverage beyond 56 categories;
`procurement` for the thin-category standing decision (JQ14); finance/`category_price_stats` for budget
plausibility, which is **0 rows** today.

### 9. What this seat cannot do without a model

- **Nothing in its taxonomy**, once the four missing tables exist. Completeness is set membership;
  plausibility is a band comparison; question ordering is a sort by unblocked-gate count.
- **One honest boundary**: judging whether a *free-prose* scope narrative ("make the office nice, modern,
  like the pictures I sent") is substantively complete is not a set operation. The deterministic answer
  is to **refuse to treat prose as a scope** and require the structured field set — which is exactly this
  seat's charter. That is a product decision the founder should confirm, not a hidden model dependency:
  it means a customer who will only write prose is asked the structured questions instead of having their
  prose interpreted.

---

## spec_commercial — Supplier Matching & Dispatch Operator

Responsibility of record: *"Executes supplier dispatch for approved, quote-ready, supplier-safe inquiries:
eligibility, matching, idempotent assignment, one notification per supplier, and a recorded reason for
every selection and exclusion."*

(The `role` column still reads "Commercial Services Specialist" and five legacy `employee_kpi` rows still
carry the old specialist titles — Construction & Civil, MEP, Interior & Fit-Out, Industrial & Energy,
Commercial Services. The live title is the one above.)

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| S1 | Which suppliers should receive this RFQ? | allocation | every dispatch | rfq_qualification_mgr | The whole quality of the top-3 report is set here |
| S2 | Is this supplier eligible at all? | gate | per candidate | self | An unverified or blocked supplier reaching a buyer costs trust |
| S3 | How many suppliers may this RFQ contact? | allocation | every dispatch | self | `match_max_fanout` 5, per-trade 3 |
| S4 | Does this candidate clear the relevance floor of 35? | gate | per candidate | self | Below 35 we do not contact them, even on a strong verdict |
| S5 | Why was this supplier selected? (a recorded reason) | craft | per selection | procurement, audit | An unexplained selection cannot be audited or improved |
| S6 | Why was this supplier excluded? (a recorded reason) | craft | per exclusion | procurement | Silent exclusion is how good supply disappears |
| S7 | Has this supplier already been notified for this RFQ? | gate | per notification | self | Duplicate notification is spam and breaks idempotency |
| S8 | Does the supplier hold the mandatory authority approval for this trade? | gate | per regulated RFQ | rfq_qualification_mgr | A DEWA or Civil Defence job to an unapproved firm |
| S9 | Does the supplier cover the requested emirate? | gate | per candidate | self | A Fujairah-only supplier quoting a Dubai job |
| S10 | Is the job value inside the supplier's declared project range? | gate | per candidate | self | Sending an AED 2 m job to a firm whose max is AED 200 k |
| S11 | Has the supplier declared this trade as excluded? | gate | per candidate | self | `excluded_trades` is a supplier's own negative scope; overriding it is a breach of their declaration |
| S12 | Can this supplier's role actually do this kind of work (supplies vs executes vs whole_scope)? | gate | per candidate | self | A trader sent an installation job |
| S13 | Is the supplier at 3 consecutive non-responses? | gate | per candidate | self | `matching_strike_limit` 3 |
| S14 | Is the supplier's licence or insurance expired? | gate | per candidate | self | `matching_blocked` is reconciled daily; an expired licence means they cannot legally deliver |
| S15 | Is the supplier-safe package free of buyer identity? | gate | every dispatch | procurement | Anonymity breach |
| S16 | Has the supplier brief been frozen before dispatch? | gate | every dispatch | audit | An unfrozen brief means suppliers quoted different documents |
| S17 | Should a multi-trade RFQ be dispatched as children or as one? | sequencing | per multi-trade | inquiry_router | Rule 2's comparison requires like-for-like |
| S18 | What is the quote window for this RFQ? | sequencing | every dispatch | rfq_success | `SLA-QUOTE-WINDOW` 48 h default, inquiry-configurable |
| S19 | Should we re-dispatch because too few quotes arrived? | sequencing | per stalled RFQ | rfq_success | Under-dispatching leaves the buyer with one quote |
| S20 | Which additional suppliers on re-dispatch, and why not first time? | allocation | per re-dispatch | self | Repeating the same five is not a re-dispatch |
| S21 | Is a zero-fit result genuine or a retrieval failure? | diagnosis | per zero-fit | procurement | Telling a buyer nobody serves them when the query broke |
| S22 | Is the candidate pool being filtered per RFQ, or returning the same set every time? | diagnosis | weekly | procurement | Measured today: the same five suppliers for all five test cases |
| S23 | Should the fanout be reduced because the category is thin? | allocation | per thin category | procurement | Contacting the only supplier three times |
| S24 | Which notification channel for this supplier (email, WhatsApp, SMS)? | craft | per notification | self | Channel mismatch is a non-response that was never a refusal |
| S25 | Is `demo_rehearsal_active` set, and is this a fixture? | gate | per dispatch | self | Sending a rehearsal RFQ to a real supplier |
| S26 | Is the department at its 250-open-task back-pressure ceiling? | gate | per dispatch batch | ops_director | `dispatch_max_open_per_dept` |
| S27 | Should this dispatch be held because the RFQ is not dispatch-eligible? | gate | every dispatch | rfq_qualification_mgr | `fn_inquiry_dispatch_eligible` |
| S28 | Which suppliers were in the pool but scored below the floor, and by how much? | diagnosis | per dispatch | procurement | This is the supply-gap signal that tells growth what to acquire |
| S29 | Does the score's track-record component mean anything today? | diagnosis | monthly | procurement | `supplier_perf` has 0 rows, so 15 of the 100 points are dead weight |
| S30 | Should a supplier be contacted about capability confirmation rather than about this RFQ? | sequencing | frequent | supplier ops | 15 305 of 15 306 capability rows are derived, not confirmed |
| S31 | What is the dispatch SLA state for this RFQ? | gate | per dispatch | rfq_success | `SLA-DISPATCH` 15 minutes after safe approval |
| S32 | Is this an idempotent re-run of a dispatch we already performed? | gate | per run | self | Double assignment |

### 2. Domain logic

**M-S1 — Capability match score (`fn_match_capability`, exists and is the canonical engine).**
Hard gates, all of which must pass before any scoring:
`confirmed_at is not null` (supplier confirmed their own scope) ∧ `trades && p_trades` ∧
`not (excluded_trades && p_trades)` ∧ `fn_is_matchable(...)` ∧ role can do the `need`
(`taxonomy_role.supplies` / `.executes` / `.whole_scope`) ∧ every `taxonomy_trade.authority_required`
code present in `authority_approvals` ∧ job value inside `[min_project_value, max_project_value]` ∧
emirate covered (or coverage not stated, or the lead's own emirate matches).

Score, weights from `decision_policy`:
`score = 40 × (product_hits / |products|) + 20 × brand_hit + 15 × ptype_hit + 15 × track + 10 × size_known`
where `size_known` contributes 10 when both project-value bounds are known and 5 otherwise, and
`track = clamp(0,1, coalesce(supplier_perf.quote_rate, supplier_perf.perf_score, 0))`.
Ordering: score desc, track desc, supplier_id.

**Two measured facts about this score that the seat must state whenever it uses it:**
(a) `supplier_perf` holds **0 rows**, so `track = 0` for every supplier and the 15 track-record points are
currently unearnable by anyone — the effective maximum score is **85, not 100**, and the floor of 35 is
therefore a higher bar than it looks (41% of the achievable range, not 35%).
(b) The hard gate `confirmed_at is not null` is satisfied by exactly **one** supplier in the estate, so
`fn_match_capability` can return at most one row today.

**M-S2 — Eligibility (`fn_is_matchable`, exists).**
`verified ∧ ¬banned ∧ ¬matching_blocked ∧ ¬permanently_closed ∧ approval_status ∉ {action_required,
rejected} ∧ chat_strikes < fn_matching_strike_limit()` (=3). Measured: **1** of 22 265 leads passes.

**M-S3 — Fanout.** `fanout = min(5, Σ_trades min(3, |eligible(trade)|))` (M-P4). Single trade → ≤5.
Split multi-trade → ≤3 per child, so a split job never contacts more suppliers overall than a combined one.

**M-S4 — Keyword retrieval (`match_suppliers_kw`, exists).** The pre-capability shortlist:
`match_score = min(strong_hits,6)×2 + min(name_hits,2) + 3×cat_match + 5×turnkey_match + 1×has_app_rev`,
ordered `in_emirate desc, match_score desc, rating desc, reviews desc`. It applies `fn_is_matchable` but
**not** `confirmed_at`, so it is a wider net than `fn_match_capability` — that is by design, and the
difference between the two pools is the capability-confirmation backlog (15 305 rows).

**M-S5 — Vector retrieval (`match_suppliers`, exists).** `gte-small` cosine over `leads.embedding_gte`.
Free, in-region. Corroboration and recall widening only; never the sole basis for contacting a supplier,
for the same reason as M-R2.

**M-S6 — Exclusion ledger.** For every candidate in the retrieved pool that is not dispatched, record the
**first failing gate** and, if it passed all gates, the score and the shortfall against 35. This turns
every dispatch into a supply-gap measurement: `v_supplier_match_exclusions` exists as a view; the per-RFQ
persisted ledger **does not exist** and must be added.

**M-S7 — Re-dispatch (`fn_rfq_redispatch_sweep`, exists).** Trigger when quotes received < target after
the quote window. New candidates only: the exclusion ledger's near-misses ordered by shortfall, then the
keyword pool beyond the capability pool. **UNMEASURED:** the quote target and the re-dispatch delay are
not in `decision_policy` and **do not exist**.

**M-S8 — Idempotency.** One `inquiry_matches` row per (inquiry, supplier), one notification per row.
`trg_autodispatch_inquiry`, `fn_notify_matched_supplier` and `trg_gate_incomplete_match` exist.
`inquiry_matches` holds **0 rows**.

### 3. Reasoning procedures

**S1 — "Which suppliers get this RFQ?"**
1. Refuse immediately if `fn_inquiry_dispatch_eligible` is false — report the blocking workstreams.
2. Refuse if the supplier-safe package is not frozen (`fn_freeze_supplier_brief`) or contains a
   buyer-identifying field.
3. Build the pool: `fn_match_capability(trades, need, products, brands, project_type, value, emirate,
   limit)`. Record the full returned set with scores.
4. Widen with `match_suppliers_kw` and `match_suppliers` **only to detect what capability matching
   missed**; anything from the wider pool that lacks `confirmed_at` is not dispatched — it is queued for
   capability confirmation (S30) instead.
5. Drop everything below `match_relevance_floor` 35. Record each drop with its shortfall.
6. Apply the fanout budget (M-S3).
7. Dispatch idempotently; one notification per supplier on the channel resolved by S24.
8. Compose the dispatch memo: RFQ, trade set, pool size, gates that eliminated whom (counts per gate),
   the selected list with score and `why` string from `fn_match_capability`, the near-miss list with
   shortfalls, and the fanout used against the budget.
Stops and refuses when: the pool is empty **and** any retrieval diagnostic error is present (that is a
`retrieval_failure`, not a coverage gap); or the RFQ is not frozen; or `demo_rehearsal_active` is true and
the recipients are not `@example.invalid`.

**S21/S22 — "Is this zero-fit genuine?"** M-P6, plus the per-case pool check: if two different RFQs in
different trades return the identical candidate set, the pool is not being filtered per RFQ. This is the
**measured defect today** — `match_eval_runs` id 11 returns `["pool","fitout","elec","land","cctv"]` for
all five cases, giving precision 32% at recall 100%. Run id 9 on 10 Aug returned exactly one correct fit
per case at precision 100%. The seat must report this as a regression with both run ids and dates, and
must not describe current matching as working.

**S29 — "Does track record mean anything?"** Read `supplier_perf` row count (0) and
`supplier_score where quotes_submitted > 0` (0 of 20 465). Answer: no — the 15-point track component is
inert, the achievable maximum is 85, and the floor of 35 should be re-derived once any supplier has
quoted. Do not silently reweight; state it and ask `procurement` for the decision.

**S8 — authority gate.** `taxonomy_trade.authority_required` measured: `electrical → electrical_utility`,
`fire_fighting → civil_defence`, all other 38 trades empty. Cross-check against `business_rules`
(security → SIRA, electrical → DEWA NOC, fire > AED 1 m → four requirements). **These two sources
disagree in coverage**: `business_rules` requires SIRA for security but `taxonomy_trade` declares no
authority for security trades. The seat must apply the **union** of both and raise the inconsistency as a
task, not silently prefer one.

### 4. Judgement rules

| # | condition | verdict | reason |
|---|---|---|---|
| JS1 | Candidate score < 35 | DO NOT CONTACT, whatever else says | `match_relevance_floor`: it protects suppliers from marginal inquiries |
| JS2 | Supplier has not confirmed their own capability scope | DO NOT DISPATCH; queue for confirmation | `fn_match_capability` gate; a derived scope is our guess about them, not their statement |
| JS3 | Trade appears in `excluded_trades` | EXCLUDE, no override | Their declared negative scope is theirs |
| JS4 | Mandatory authority approval absent | EXCLUDE | Safety and licensing |
| JS5 | 3 consecutive non-responses | STOP sending | `matching_strike_limit`, founder 3 Aug 2026 |
| JS6 | Licence or insurance expired (`matching_blocked`) | EXCLUDE until renewed; auto-restore on renewal, no fee | Published supplier terms |
| JS7 | Fanout would exceed 5 (or 3 per split trade) | CLAMP | `decision_policy` |
| JS8 | Same supplier already notified for this RFQ | DO NOT re-notify | Idempotency; duplicate contact is spam |
| JS9 | A supplier scores 90 but has never confirmed capability | STILL DO NOT DISPATCH even though it scores well | The score is computed from data we derived about them; contacting on our own guess is how a marketplace loses suppliers |
| JS10 | Pool empty and a retrieval diagnostic error is set | NOT a coverage gap | A false "nobody serves you" is a false statement to a customer |
| JS11 | The same candidate set is returned for materially different RFQs | DEFECT, not a result | Measured 7 Sep 2026 |
| JS12 | `demo_rehearsal_active` true and a recipient is not `@example.invalid` | HALT | Rehearsal safety |
| JS13 | Department at 250 open tasks | HOLD dispatch batch | `dispatch_max_open_per_dept` |
| JS14 | Only one eligible supplier exists in the category | DISPATCH, and tell the buyer the comparison will not be a top-3 | Rule 2 promises the best three of what arrives; promising three quotes we cannot get is the lie |
| JS15 | A tier or rating would change who is matched | REFUSE | Founder 8 Aug 2026: a tier must not affect a match |
| JS16 | Raising fanout would fill a thin comparison | REFUSE even though quotes-per-RFQ would improve | The fix is supply, not reach |
| JS17 | Supplier brief not frozen | BLOCK DISPATCH | Suppliers must quote the same document |
| JS18 | Buyer-identifying content in the safe package | BLOCK DISPATCH | Anonymity is the product |

### 5. Technical knowledge

- **Tables**: `leads` (22 265; the supplier registry — `public.suppliers` **does not exist**),
  `supplier_capabilities` (15 306; the columns that matter: `trades`, `roles`, `products_norm`, `brands`,
  `project_types`, `min_project_value`, `max_project_value`, `coverage_emirates`, `authority_approvals`,
  `excluded_trades`, `confirmed_at`, `review_status`, `completeness`, `missing_fields`),
  `taxonomy_trade` (40), `taxonomy_role` (8), `supplier_perf` (**0 rows**), `supplier_score` (20 465, none
  with a submitted quote), `inquiry_matches` (0), `inquiry_supplier_brief` (0),
  `inquiries_supplier_safe` / `inquiries_supplier_live` (0), `notifications` (855),
  `messaging_template` (14), `invite_schedule` (15).
- **Routines**: `fn_match_capability`, `fn_is_matchable`, `fn_matching_strike_limit`,
  `match_suppliers_kw`, `match_suppliers`, `fn_supplier_matchable`, `fn_supplier_product_match`,
  `fn_freeze_supplier_brief`, `fn_notify_matched_supplier`, `fn_rfq_redispatch_sweep`,
  `fn_inquiry_dispatch_eligible`, `trg_autodispatch_inquiry`, `trg_gate_incomplete_match`,
  `fn_unsafe_match_eligibility_guard`, `fn_unsafe_check_ineligible_match`, `scrub_inquiry_contacts`.
- **Edge functions**: `dispatch_inquiry` and `match` — **neither calls the AI gateway**, which means the
  dispatch path is already model-free. `route_inquiry` does call it, but has a deterministic degraded
  path that serves the retrieval shortlist.
- **What must be stored so this seat can act alone**: the per-RFQ exclusion ledger (M-S6) — **does not
  exist**; the re-dispatch quote target and delay (M-S7) — **do not exist**; the channel-preference rule
  per supplier (S24) — `leads.wa_optin` and `email_verified` exist but the preference order **does not**;
  the reconciled authority table (S8) — **does not exist**.
- **Platform mechanics**: notification idempotency, `rehearsal_window` (30 rows) and
  `demo_rehearsal_active`, the ZZ DEMO / `@example.invalid` fixture convention, `email_suppressions`
  (37 rows) and `app_blocked_domains` (24).

### 6. Academic knowledge

Disciplines: **matching-market theory** (many-to-one matching, congestion, and why unrestricted fanout
degrades a market), **information retrieval evaluation** (precision/recall, the pooling bias), **auction
participation economics** (bidder entry costs and the winner's curse — every RFQ we send costs the
supplier real estimating hours), **supplier segmentation and Kraljic positioning**, and **queueing/SLA
design**.

Lawful primary sources: ASCM published **SCOR** overview (Source process); CIPS published L4 syllabus
outline (Supplier Relationships); ISM published CPSM content outline (Sourcing, Supplier Relationship
Management); Roth & Sotomayor and Roth's published open-access work on matching-market congestion;
**TREC** published evaluation methodology for precision/recall; UN **UNSPSC** and **CPC** published code
lists; DEWA / SEWA / ADDC published contractor-registration requirements; SIRA published regulations;
Dubai Civil Defence published code of practice; UAE Federal Decree-Law 45/2021 (data protection) for the
anonymity boundary. Never copyrighted study texts.

Certifications held: **CSCP (ASCM/APICS)** (pass 70.00%, rank 1) — Supply Chain Design, Supply Chain
Planning and Execution, Supply Chain Improvement and Best Practices, Sourcing and Supplier Management,
Logistics and Warehousing, Demand Management; and **CIPS Level 4 Diploma** (pass 50.00%, rank 2).
**Syllabus areas failed: none recorded — this seat has never sat either exam.** Sitting both is a Q1
milestone; CSCP *Sourcing and Supplier Management* is the area this seat's daily work sits in and should
be examined first.

### 7. Corporate knowledge

- The five hard rules; rule 2 in particular, because dispatch decides whether three comparable quotes can
  even exist, and rule 5 because matching is permitted at one confirmed supplier while advertising is not.
- **Founder rulings**: a tier must never affect a match (8 Aug 2026, `fn_supplier_tier.affects_matching`
  is false and says so in its own payload); three strikes then stop (3 Aug 2026).
- **Authority** (`employee_authority`): **autonomous at AED 0** for `supplier_verify`, `compare_quotes`,
  `qualify_inquiry`; **advisory at AED 0** for `match_inquiry`, `route_category`, `capability_enrich`,
  `supplier_approve_clean`, `invite`. Note the tension with the seat's own title: **`match_inquiry` is
  advisory, meaning execution requires the department head.** Either the authority row or the title is
  wrong, and this should be resolved before the seat runs autonomously.
- **Workflows**: `employee_task` (owner), `invoice_approval` (reviewer), `rfq_handling` (participant),
  `supplier_onboarding` (participant).
- **Knowledge**: 8 `agent_knowledge` rows, 24 `employee_knowledge` rows — the largest
  `employee_knowledge` set in the department.
- **KPIs**: five rows, all measuring *RFQs reaching at least one submitted quote* at 80% monthly, carried
  over from five retired specialist titles. None of them measures dispatch. A dispatch KPI (share of
  dispatched RFQs receiving ≥1 quote within the quote window; share of dispatches with a recorded reason
  for every selection and exclusion) **does not exist** and should replace the five duplicates.
- **Hands to**: `quote_evaluation` (the dispatched set becomes the comparison population),
  `rfq_success` (the quote window and the chase), supplier ops (capability confirmation backlog),
  `growth` (the exclusion ledger is the supply shopping list), `procurement` (zero-fit adjudication).
- **History**: `inquiry_matches` 0 rows; 171 suppliers invited, 0 registered; one supplier has confirmed
  capability out of 15 306; matching precision fell from 100% (10 Aug) to 32% (7 Sep) on the same five
  cases.

### 8. One-year plan

**Objective.** Every quote-ready, supplier-safe RFQ reaches the right suppliers, with a recorded reason for
every inclusion and exclusion, without a model.

**Metrics owned.** (1) **Matching accuracy** — `company_goals.matching_accuracy`, target 95%, owner_dept
marketplace; measured today as 32% precision / 100% recall on the 5-case standing set. (2) **Quotes per
RFQ** — `company_goals.quotes_per_rfq` ≥5. (3) **Matching time** — `company_goals.matching_time` <30 s.

**Quarterly milestones.**
- **Q1.** Restore precision to ≥80 on the standing set and expand that set from 5 to ≥50 cases. Build the
  exclusion ledger. Reconcile `taxonomy_trade.authority_required` with `business_rules`. Resolve the
  `match_inquiry` advisory/title contradiction. Take confirmed capability from **1** supplier to **≥100**.
  Sit CSCP and CIPS L4.
- **Q2.** Confirmed capability ≥300 across 3 Dubai trades, so a real fanout of 5 is achievable. First real
  dispatches. Re-dispatch rule live with a stored target and delay.
- **Q3.** Confirmed capability ≥800 across 25 categories; `quotes_per_rfq` ≥3 measured;
  precision ≥90 on the ≥50-case set.
- **Q4.** `quotes_per_rfq` ≥5 measured; precision ≥95 (the `company_goals` target) at 40 open categories.

**Capacity check — the constraint lives here.** `fn_match_capability` requires
`confirmed_at is not null`; **one** supplier in the estate satisfies it. Founder rule 2 needs at least
three quotes for a top-3 report to mean anything; with a 5-supplier fanout and a realistic response rate,
three quotes needs roughly 5–8 genuinely eligible suppliers per RFQ, i.e. **10+ confirmed suppliers per
active category**, which is exactly what founder rule 5 already says. So the arithmetic of the founder's
own rules gives this seat its target: **10 confirmed, matchable suppliers × the number of active
categories**. For 3 Dubai trades that is 30; for 40 categories it is 400. Today it is 1.

On the AED 50 000 / 667-reveal scenario, this seat's lever is quotes-per-RFQ: at 1 quote per RFQ the
reveal is a formality with no comparison and the customer has no reason to pay 3%; at 3+ quotes the
comparison is the product. **The revenue slice is therefore effectively all of it** — no other seat's
work converts without this one, and the seat should say so plainly rather than claim a fraction.

**Dependencies.** Supplier ops / `supply` for capability confirmation and registration (171 invited, 0
registered); `product_eng` for the pool-filtering defect; `rfq_qualification_mgr` for dispatch
eligibility; `data_intel` for the reconciled authority table.

### 9. What this seat cannot do without a model

- **Nothing in its taxonomy.** Every gate is a set or interval test; the score is a weighted sum from
  `decision_policy`; ordering is a sort. `dispatch_inquiry` and `match` already make no model call.
- **What is lost by dropping the model adjudicator in `route_inquiry`**, stated honestly: the model
  currently reads each candidate against the RFQ text and returns a fit/no-fit verdict with a reason. The
  deterministic path replaces that with the capability gates plus the weighted score, and its reason
  string is `fn_match_capability.why` (trades matched, product hits, brand match, project type, coverage).
  That is a **less expressive reason**, not a less correct decision — the gates are stricter than the
  model's judgement, and the model was never allowed to overrule the floor of 35 anyway. The measurable
  cost is recall on RFQs whose wording does not surface a `products_norm` hit; the mitigation is the free
  gte-small vector pool, which is already wired.

---

## quote_evaluation — Quote Evaluation Specialist

Responsibility of record: *"Normalises and compares received quotes, flags non-comparable scope, produces
the buyer-facing comparison."* This seat owns founder rule 2.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| E1 | Which three quotes are the top three? | craft | every comparison | customer | Founder rule 2 is the product; a wrong top-3 is a wrong purchase |
| E2 | Why is quote #1 first? (a stated, checkable reason) | craft | every comparison | customer | An unexplained ranking is not a comparison, it is an oracle |
| E3 | Are these quotes comparable at all? | gate | every comparison | rfq_success | Comparing a supply-only quote with a supply-and-install quote is a lie by arithmetic |
| E4 | Is this quote submittable? (quality score ≥70) | gate | every quote | spec_commercial | A quote missing prices and terms wastes the buyer's decision |
| E5 | What exactly is missing from this quote? | craft | every failing quote | supplier | "Improve your quote" is not actionable |
| E6 | Does the quote's scope deviate from the RFQ's mandatory set? | diagnosis | every quote | customer | A cheaper quote that excluded half the scope reads as the best one |
| E7 | Which line items are missing versus the BOQ? | diagnosis | per BOQ RFQ | customer | The commonest way a low price hides a big number |
| E8 | Is the unit price plausible for this item? | diagnosis | per line | customer | An order-of-magnitude line error |
| E9 | Are units consistent across quotes (sqm vs sqft)? | gate | every comparison | customer | A 10.76× apparent price difference that is a unit, not a price |
| E10 | Has this quote expired? | gate | every comparison | customer | Revealing on an expired quote is a refund waiting to happen |
| E11 | What is the price spread, and is it explainable? | diagnosis | every comparison | customer | An unexplained 3× spread means the scope is not the same |
| E12 | Is the cheapest quote also the best value? | diagnosis | every comparison | customer | Rule 2 forbids cheapest-wins; the buyer must see when cheapest is not best |
| E13 | What is the lead time, normalised to days? | diagnosis | every quote | customer | "2 weeks" and "10 working days" are not the same number |
| E14 | Are payment terms stated, and how do they compare? | diagnosis | every quote | customer | 100% advance vs 30% down is a real commercial difference |
| E15 | Is warranty stated, and for how long? | diagnosis | every quote | customer | Unstated warranty is a post-purchase dispute |
| E16 | What did each quote exclude? | craft | every quote | customer | Exclusions are where the price difference usually lives |
| E17 | Is the quote itemised or a lump sum? | diagnosis | every quote | customer | A lump sum cannot be checked item by item |
| E18 | Does the quote leak the supplier's identity? | gate | every quote | procurement | Anonymity breach before the reveal |
| E19 | What is the reveal fee for the selected quote? | pricing | every reveal | customer, finance | `reveal_fee()` — a wrong fee is a Terms breach |
| E20 | Does the quote meet the category's mandatory quote sections? | gate | every quote | supplier | `quote_gate` — but see the measured defect below |
| E21 | Does the quote address every mandatory spec aspect for its spec_group? | gate | every quote | customer | `category_quote_specs` regexes exist for exactly this |
| E22 | Should a quote be rejected outright rather than ranked low? | gate | occasional | supplier | Ranking a non-quote fourth is kinder than telling the supplier it failed |
| E23 | Fewer than three quotes arrived — what does the report say? | craft | frequent early on | customer | Rule 2 says rank all and show the best three; three of two does not exist |
| E24 | More than 20 quotes arrived — does the report change? | craft | rare | customer | Rule 2: rank them ALL, show three |
| E25 | Two quotes are within 1% — how is the tie broken? | craft | occasional | customer | An arbitrary tie-break reads as bias |
| E26 | Should the buyer be warned before revealing? | escalation | frequent | customer | An expired or incomplete quote should carry a warning at the moment of payment |
| E27 | Is the supplier's quote a copy of another supplier's? | diagnosis | rare | procurement, legal | Collusion is a marketplace-ending event |
| E28 | Does a quote reference a brand the RFQ did not ask for? | diagnosis | frequent | customer | A substitution the buyer never agreed to |
| E29 | Is a specification substitution equivalent or inferior? | diagnosis | frequent | customer | The core technical judgement in any comparison |
| E30 | How should the comparison read in Arabic? | craft | frequent | customer | Half the market reads Arabic first |
| E31 | Did the comparison publish inside its SLA? | gate | every comparison | rfq_success | `SLA-COMPARISON-PUBLISH` 30 minutes |
| E32 | Is the comparison visible to the right party only? | gate | every comparison | procurement | `fn_phase_d_comparison_visible` |

### 2. Domain logic

**M-E1 — Quote completeness score (`fn_quote_structured_score` / `fn_quote_score_json`, both exist).**
Line items present 15 · every item priced 20 · brand+model on every item 15 · specification on ≥half the
items 10 · labour or install stated 10 · warranty 6 · lead time 6 · payment terms 6 · exclusions 6 ·
validity 6. Total 100. `submittable = score ≥ 70`. Missing components are returned as a named list — this
is the E5 answer, already computed.

**M-E2 — The top-3 ranking (the model-free engine, `quote_compare/deterministic.ts`, exists).**
- `price_score = spanScore(price, min, max)` — 5 for the cheapest, 1 for the dearest, linear between,
  **3 for a genuine tie**, 1 for an unstated price. Span, not ratio: ratio scoring gave every quote 5/5
  on four real staging quotes within 22% of each other and the ranking collapsed onto lead time.
- `delivery_score = spanScore(lead_time_days, min, max)` with `leadTimeDays` parsing the first number and
  its unit (week ×7, month ×30, bare number = days), unparseable → null → 1.
- `quality_score` from completeness: ≥85→5, ≥70→4, ≥50→3, ≥30→2, else 1, +1 if itemised **and** warranty
  stated; when completeness is absent, rebuilt from how many of the five commercial terms are stated.
- `composite = 0.4 × price + 0.4 × quality + 0.2 × delivery`.
- Rank by composite desc, tie → cheaper, a quote with no price never wins a tie, final tie → label.
- `top3 = ranked.slice(0,3)`.
This satisfies founder rule 2 exactly: **all** quotes are scored, the best **three** are shown, and the
weighting is 40% commercial / 40% technical-completeness / 20% delivery — never cheapest-wins.

**M-E3 — Scope-deviation detection, deterministic (this is the piece the current engine refuses to do).**
The existing `deterministic.ts` deliberately returns empty `spec_deviation`, `missing_from_request` and
`line_findings` because "judging a quote against the brief needs reading". **It does not, if the RFQ was
answered structurally.** Two deterministic routes already exist in the estate:
- **(a) Mandatory aspect coverage.** `category_quote_specs` holds **141 rows** — per `spec_group`, an
  `aspect`, a `label`, a `mandatory` flag and a **`match_regex`**. Example measured row: security /
  resolution / mandatory / `\d+\s*mp|megapixel|\d{3,4}\s*[x×]\s*\d{3,4}|\b4k\b|1080p|2mp|4mp|8mp`, note
  "SIRA: 4MP general, 8MP entries/cash points". `fn_quote_spec_group(category)` maps a category to one of
  ~40 spec groups. So: for every mandatory aspect of the quote's spec_group, test the quote text and line
  items against `match_regex`; an unmatched mandatory aspect is a **stated, citable gap**, not a guess.
- **(b) Requirement set difference.** When the RFQ was answered through `field_definition` /
  `inquiry_requirement`, deviation is `required_set − quoted_set` over field ids, with
  `numeric_tolerance` from `field_definition` deciding whether a numeric answer matches.
**UNMEASURED:** `inquiry_requirement` and `quote_requirements` both hold **0 rows**, so route (b) has
never run. Route (a) is runnable today against the 141 stored regexes.

**M-E4 — Category quote gate (`quote_gate(category, quote)`, exists) — and a measured defect.**
It reads `quote_requirements.required_sections` for the category, falling back to the `default` row.
**`public.quote_requirements` holds 0 rows.** Therefore `quote_gate` currently returns
`{pass:true, score:100, missing:[], note:'no standard defined'}` for **every quote in every category**.
It is a gate that cannot fail. Filling `quote_requirements` for the 56 categories that have
`category_specs`, and a `default` row, is a Q1 must.

**M-E5 — Unit normalisation.** `mdm_units` (23 rows) plus a conversion table. sqft→sqm ×0.092903;
sqm→sqft ×10.7639; lm = m; TR→kW ×3.51685; gallon(US)→litre ×3.78541. Normalise **before** any span
score, or the price span is meaningless.
**UNMEASURED:** the conversion table itself **does not exist** as a row set; only the unit names do.

**M-E6 — Price plausibility per line.** `unit_price` against `category_price_stats` — which holds
**0 rows**. Until quotes exist there is no distribution, so the seat must say "no price history exists"
rather than invent a band. The one deterministic check available from day one is **internal**: within a
single comparison, a line whose unit price is more than 5× the median of the same line across the other
quotes is flagged for the buyer's attention, with all the numbers shown.

**M-E7 — Duplicate/collusion signal.** Jaccard similarity over the normalised line-item description sets
of two quotes on the same RFQ, plus exact equality of unusual numbers. High similarity between two
independent suppliers is a **flag to procurement and legal**, never a customer-facing statement.
**UNMEASURED:** no such check exists.

**M-E8 — Reveal fee.** `reveal_fee(selected_quote_amount)` = `round(amount × 0.03, 2)`. No cap, no promo.
The only source.

### 3. Reasoning procedures

**E1/E2 — "Produce the top-3."**
1. Gather every quote on the RFQ with `status` submittable. Reject nothing at this stage — rule 2 says
   rank them all.
2. Normalise units (M-E5) and lead times (M-E2) across the whole set. If a unit cannot be normalised,
   the quote is marked **non-comparable** and is ranked but flagged, never silently span-scored.
3. Compute `quality_score` from `fn_quote_structured_score` (or rebuild from stated terms).
4. Compute `price_score` and `delivery_score` as span scores across this RFQ's own quotes.
5. Run M-E3 route (a): for every mandatory `category_quote_specs` aspect of the spec_group, test the
   regex. Unmatched mandatory aspects become **stated deviations with the aspect label and its note**.
6. Composite, sort, tie-break, take three.
7. Compose the report: the three, each with `why` (the three sub-scores and the completeness reason),
   the trade-off (its first flag), the full considered count, the cheapest label, the best-value label,
   the price spread, the watch-outs, and — new — the mandatory-aspect gaps per quote with the aspect note
   quoted (e.g. "SIRA: 4MP general, 8MP entries/cash points").
8. Publish inside `SLA-COMPARISON-PUBLISH` (30 minutes).
Stops and refuses when: no quote states a price **and** no quote is itemised (there is nothing to compare);
or units are inconsistent and unconvertible; or `fn_phase_d_comparison_visible` denies the caller.

**E3 — "Are these comparable?"** Deterministic comparability test, all four must hold:
same trade set, same `need` (supplies / executes / whole_scope), units normalisable to a common base, and
quantity within `numeric_tolerance` of the RFQ's stated quantity. Any failure → the quote is shown in a
separate "not directly comparable, and here is why" block rather than mixed into the ranking. This is the
seat's most important craft judgement and it is entirely a set test.

**E23 — "Fewer than three quotes."** Say exactly what arrived. `shortlist_reason` already reads
"All N quotes were scored on stated figures and the strongest M are shown." Never pad, never imply three.
Founder rule 2 promises the best three **of what arrives**, and the honest sentence when N=1 is that this
is not yet a comparison — with the re-dispatch already requested (S19).

**E12 — "Is cheapest also best?"** Compute both labels (`cheapest_label`, `best_value_label`). When they
differ, that difference is the single most useful sentence in the report and must be stated first with
the arithmetic: "X is AED N cheaper but scores C/5 on completeness against Y's D/5, and excludes Z."

**E26 — "Warn before reveal."** Before the 3% is charged, if the selected quote is expired, non-itemised,
below 70 completeness, or has an unmatched mandatory aspect, the buyer sees the warning **at the payment
step**, not after. A reveal on a bad quote is the direct cause of the refund ladder, which is
`company_economics` item 10(1) — the first of the four things that destroy the economics.

### 4. Judgement rules

| # | condition | verdict | reason |
|---|---|---|---|
| JE1 | Any number of quotes ≥1 | Rank ALL, show the best three | Founder rule 2, verbatim |
| JE2 | Cheapest quote has the highest composite | Say so plainly | Rule 2 forbids cheapest-wins, not cheapest-being-best |
| JE3 | Unstated price, lead time or warranty | Scores 1, not the average | An unstated term is a risk, not a neutral |
| JE4 | Genuine tie on a span | Everyone gets 3, never everyone 5 | Found by measurement: ratio scoring collapsed a real 4-quote ranking |
| JE5 | Quote with no price | Never wins a tie against one with a price | Tie-break in the engine |
| JE6 | Quotes use different units | NON-COMPARABLE until normalised | A 10.76× illusion |
| JE7 | Quote expired | Flag at the top; warn before reveal | Revealing on an expired quote produces a refund |
| JE8 | Completeness < 70 | Not submittable; coach the supplier with the named missing list | `fn_quote_structured_score` |
| JE9 | Mandatory `category_quote_specs` aspect unmatched | STATE the gap with the aspect note | 141 stored regexes exist for this |
| JE10 | `quote_gate` returns "no standard defined" | Report it as NO GATE, not as a pass | A gate that cannot fail is not a gate — measured: 0 rows in `quote_requirements` |
| JE11 | Two quotes on one RFQ are near-identical in line structure | Flag to procurement and legal, never to the customer | Collusion allegations are legal territory |
| JE12 | Quote names a brand the RFQ did not ask for | STATE the substitution; do not judge equivalence | Equivalence is section 9 territory |
| JE13 | A supplier-identifying string appears in a quote | STRIP and flag | Anonymity is the product until the reveal |
| JE14 | Buyer asks us to recommend one supplier by name pre-reveal | Give the ranking and the reasons; never a name | Names are what the 3% buys |
| JE15 | A quote scores highest but excluded half the scope | It does not rank first — comparability is tested before ranking | The commonest way a comparison misleads |
| JE16 | The report would be prettier with an invented reason | REFUSE | The engine's own rule: never invent a specification, a deviation, a line finding or a reason |
| JE17 | Reveal fee request with a discount, cap or waiver | REFUSE | Founder rule 1 |
| JE18 | Comparison would publish after 30 minutes | Escalate the privacy/data mismatch | `SLA-COMPARISON-PUBLISH` |

### 5. Technical knowledge

- **Tables**: `quotes` (0 rows; columns include `quote_amount`, `lead_time`, `validity`, `payment_terms`,
  `warranty`, `scope`, `conditions`, `exclusions`, `anonymized`, `masked_terms`, `extracted`,
  `expires_at`, `committed_at`, `committed_hash`, `committed_items`, `quality`, `structured`,
  `submittable`, `stale_at`, `stale_reason`), `quote_items` (0), `quote_committed_items` (0),
  `quote_comparisons` (0), `quote_requirements` (**0 — the gate's own standard is empty**),
  `quote_reviews` (0), `quote_pdf_cache` (0), `comparison_run_v2` / `comparison_candidate_v2` (0),
  `category_quote_specs` (**141**, the deterministic deviation asset), `category_specs` (56),
  `mdm_units` (23), `mdm_brands` (51), `mdm_standards` (22), `category_price_stats` (**0**).
- **Routines**: `fn_quote_score_json`, `fn_quote_structured_score`, `fn_quote_category_score`,
  `fn_quote_spec_group`, `quote_gate`, `fn_category_quote_ready`, `fn_quote_coach`,
  `fn_quote_recompute_submittable`, `trg_quote_quality`, `trg_quote_items_rescore`,
  `trg_quote_items_roll`, `trg_quote_expiry`, `trg_quote_committed_hash`, `trg_mask_quote_contact`,
  `trg_quote_comparison_publication_stamp`, `fn_phase_d_comparison_visible`,
  `fn_phase_d_quote_original_intact`, `reveal_fee`, `scrub_quote_contacts`.
- **Code**: `supabase/functions/quote_compare/deterministic.ts` — 188 lines, already written, already
  tested (`deterministic.test.mjs`), currently reached only when the model fails. This plan makes it the
  primary engine.
- **What must be stored so this seat can act alone**: `quote_requirements` for all categories plus a
  `default` row — **0 rows today**; the unit conversion table — **does not exist**;
  `category_price_stats` — **0 rows**; the collusion similarity check — **does not exist**;
  an equivalence table for common brand/spec substitutions — **does not exist**.
- **Formats and standards**: quote PDF and Excel extraction shapes; UAE VAT presentation (the reveal fee
  is ex-VAT per founder rule 1; the company is below the AED 375 000 VAT threshold and is not registered);
  incoterms for supply-only quotes; BS/EN/ISO standard identifiers as citation strings.

### 6. Academic knowledge

Disciplines: **multi-criteria decision analysis** (weighted additive models, normalisation choice, rank
reversal), **cost and price analysis** (should-cost, price vs cost analysis, learning curves),
**bid evaluation and tender adjudication practice**, **measurement and unit systems**, and
**behavioural decision-making** (how a buyer reads a three-item shortlist — anchoring, the compromise
effect, and why the middle option is chosen more often than it should be).

Lawful primary sources: CIPS published **L5 Advanced Diploma** syllabus outline (Managing Supply Chain
Risk, Category Management); ISM published CPSM content outline (**Cost and Price Management**);
**RICS** published guidance on tender evaluation and cost analysis; **FIDIC** published contract-suite
descriptions for evaluation and variation mechanics; **ISO 80000** quantities and units;
**EN 62676** (video surveillance) and **BS 7671** published scopes for the aspect notes;
SIRA published camera-resolution requirements (the source of the measured `category_quote_specs` note);
open-access MCDA literature (Keeney & Raiffa's published framework summaries; the published TOPSIS and
weighted-sum method descriptions); UAE Federal Tax Authority published VAT guidance for the
registration threshold. Never copyrighted study texts.

Certifications held: **CIPS Level 5 Advanced Diploma in Procurement and Supply** (pass 50.00%, rank 1) —
Managing Teams and Individuals, Managing Supply Chain Risk, Managing Contracts and Relationships,
Category Management, Achieving Competitive Advantage through the Supply Chain, Sustainability in Supply
Chains; and **CPSM (ISM)** (pass 70.00%, rank 2) — the *Cost and Price Management* area is this seat's
core competence.
**Syllabus areas failed: none recorded — this seat has never sat either exam.** Sitting both is a Q1
milestone.

### 7. Corporate knowledge

- **Founder rule 2 is this seat's charter and must be quoted, not paraphrased**: "however many quotations
  arrive (3 or 100+), the report ranks them ALL and shows the best THREE on technical AND commercial
  merit — never cheapest-wins."
- **Founder rule 1**: the 3% reveal fee is computed by `reveal_fee()` from `pricing_config` and is never
  discounted, capped or waived. Comparing quotes is free — the comparison itself must never be gated
  behind a payment.
- **Authority** (`employee_authority`): **autonomous at AED 0** for `compare_quotes`, `supplier_verify`,
  `qualify_inquiry`; advisory for the rest. So this seat may compare and publish autonomously.
- **Workflows**: `employee_task` (owner), `invoice_approval` (reviewer), `rfq_handling` (participant),
  `supplier_onboarding` (participant).
- **Knowledge**: 12 `agent_knowledge` rows, 14 `employee_knowledge` rows.
- **KPI**: one row, "Quote Evaluation Specialist — primary objective", metric *RFQs reaching at least one
  submitted quote*, 80% monthly, `actual_value` null. That measures dispatch, not evaluation. A comparison
  KPI (share of comparisons published within 30 minutes; share of comparisons with ≥3 comparable quotes;
  share of reveals not followed by a refund claim) **does not exist**.
- **Hands to**: the customer (the report), `rfq_success` (the reveal and the ladder), suppliers (coaching
  via `fn_quote_coach`), `procurement` and `legal` (collusion flags), `finance` (the reveal fee).
- **History**: 0 quotes, 0 comparisons, 0 reveals have ever existed. The deterministic engine was written
  because OpenRouter's shared balance fell to $11.87 on 10 Aug 2026 at ~$4.62/day, and at zero every model
  attempt failed while `quote_compare` returned `{ok:false,error:'parse_failed'}` at **HTTP 200** — the
  customer at the decision step got nothing, invisibly. That is the failure this seat exists to prevent,
  and the founder's constraint now makes the fix permanent.

### 8. One-year plan

**Objective.** Every RFQ with quotes produces a rule-2 report the buyer can act on, computed without a
model, inside 30 minutes.

**Metrics owned.** (1) **Comparison completeness** — share of comparisons where every mandatory
`category_quote_specs` aspect was tested and reported; target 100%. (2) **Quote quality** — share of
received quotes scoring ≥70 on `fn_quote_structured_score`; target ≥80%. (3) **Reveal-to-refund rate** —
share of reveals that end in a refund claim; target ≤5%, because every refund is a full 3% reversed plus
the founder's time.

**Quarterly milestones.**
- **Q1.** Promote `deterministic.ts` to the primary engine and remove the `degraded` label and the
  "AI adviser was unavailable" disclaimer, replacing it with an accurate statement of what the engine does
  and does not read. Populate `quote_requirements` for the 56 categories plus a `default` row so
  `quote_gate` can fail. Wire M-E3 route (a) — the 141 `category_quote_specs` regexes — into the report so
  `spec_deviation` stops being permanently empty. Build the unit conversion table. Sit CIPS L5 and CPSM.
- **Q2.** First real comparisons. Arabic parity on the whole report (the engine already carries Arabic
  strings for every slot). Warn-before-reveal live.
- **Q3.** `category_price_stats` populated from real quotes; per-line plausibility live.
  Comparison KPI replacing the inherited funnel KPI.
- **Q4.** Reveal-to-refund ≤5% measured over ≥100 reveals; quote quality ≥80%.

**Capacity check.** Yes, on throughput — the whole comparison is arithmetic over at most a few dozen
quotes and runs in milliseconds. **The revenue slice**: this seat sits directly on the money. The 3% is
paid at the moment the buyer chooses from this seat's report; a report the buyer does not trust is a
reveal that does not happen. On the AED 50 000 / 667-reveal scenario, a 5-point improvement in the
quoted-to-revealed conversion is worth roughly **AED 50 000 of year-one revenue**, and a 5-point
reduction in the refund rate protects roughly **AED 50 000 more**. Both figures are assumptions —
`transactions` holds 0 rows and no conversion has ever been observed.

**Dependencies.** `spec_commercial` for at least three comparable quotes per RFQ (today at most one
supplier can be matched); `rfq_qualification_mgr` for the mandatory set that makes deviation computable;
`doc_intel_manager` for quote extraction when the supplier sends a PDF; `data_intel` for
`quote_requirements` and the price statistics.

### 9. What this seat cannot do without a model

Honest, and shorter than it first appears:

- **Judging whether a substituted specification is technically equivalent** ("supplier offered a Hikvision
  DS-2CD2143G2 instead of the Axis M3116 you asked for — is that equivalent?"). Deterministically the seat
  can state the substitution, and can test both against the mandatory aspect regexes (resolution, channel
  count, IP rating). It **cannot** conclude equivalence in the general case without an equivalence table.
  **The deterministic fix is a table, not a model**: an `equivalence_class(trade, aspect, product_a,
  product_b, verdict, source)` table sourced from manufacturer datasheets. It **does not exist** today.
  Until it does, the seat states the substitution and the measured aspect gaps and leaves the judgement to
  the buyer — which is more honest than a model's opinion anyway.
- **Reading a free-prose scope narrative inside a quote** and deciding whether it covers the RFQ's prose
  scope. Same resolution as `rfq_qualification_mgr` section 9: when the RFQ is structured, this is set
  arithmetic; when it is prose, the seat reports "scope stated as free text on both sides; we compare the
  stated commercial terms only and you must read the scope yourself" — which is exactly what the existing
  deterministic engine's disclaimer already says.
- **Everything else in E1–E32 is arithmetic and set membership.** The top-3 itself — the founder's rule 2 —
  needs no model at all, and the code that proves it is already deployed.

---

## rfq_success — RFQ Success Specialist

Responsibility of record: *"Owns the RFQ through to award; chases stalled inquiries and quote gaps."*
This seat owns founder rule 3, the supplier non-response ladder.

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| F1 | Which working day of the non-response ladder is this transaction on? | sequencing | daily per revealed transaction | customer, founder | Missing day 3 or day 5 breaks a published rule and a customer promise |
| F2 | Should the supplier be chased now? | sequencing | daily | customer_experience | Chasing early is noise; chasing late is a refund |
| F3 | Should the founder be notified for his final call? | escalation | daily | founder | Only he decides a refund; a late notification delays his decision, never replaces it |
| F4 | What exactly does the customer see at each ladder step? | craft | per step | customer | The published ladder is a promise; the wording is the promise |
| F5 | Is this RFQ stalled, and at which stage? | diagnosis | daily | procurement | A stall nobody names is a lost RFQ |
| F6 | Zero quotes after the window — re-dispatch, extend, or close? | sequencing | per stalled RFQ | spec_commercial | Closing a live RFQ loses a customer; extending forever loses them too |
| F7 | One quote after the window — is that a comparison? | gate | frequent early on | quote_evaluation | Rule 2 promises the best three of what arrives; one quote must be said plainly |
| F8 | Has the customer's 24-hour clarification window expired? | gate | daily | rfq_qualification_mgr | `SLA-CUSTOMER-INPUT` |
| F9 | Should we nudge the customer about an unrevealed comparison? | sequencing | daily | customer | A comparison nobody opens is revenue that never happens |
| F10 | Should we nudge a supplier who opened but did not quote? | sequencing | daily | supplier | Opened-not-quoted is the highest-yield nudge there is |
| F11 | Is a supplier's non-response a strike? | gate | per unanswered RFQ | spec_commercial | Three strikes stops their matching; a wrong strike removes scarce supply |
| F12 | Is this the supplier's third strike? | gate | occasional | procurement | `matching_strike_limit` 3 |
| F13 | Is the refund request inside policy? | gate | per request | founder | Outside-policy requests are a separate founder gate |
| F14 | What is the refund amount? | pricing | per refund | founder, finance | The full 3%, nothing deducted — founder rule 3 |
| F15 | What does the supplier owe after a refund? | pricing | per refund | finance, legal | 3% + AED 250 + 9% p.a., and blocked until paid |
| F16 | Has the supplier been blocked from matching pending payment? | gate | per refund | spec_commercial | An unpaid clawback re-entering matching |
| F17 | Is this a circumvention case rather than a non-response? | escalation | rare | legal | AED 15 000 or 3× the fee — evidence must be captured at the time |
| F18 | Which channel reaches this supplier? | craft | per chase | self | A chase on a dead channel is not a chase |
| F19 | How many times may we contact a supplier about one RFQ? | gate | per chase | self | Over-chasing is how suppliers leave |
| F20 | Is the customer's stated urgency real? | diagnosis | frequent | procurement | Urgency inflation destroys the SLA signal |
| F21 | Should this RFQ be archived? | sequencing | weekly | procurement | Live RFQs that are dead distort every rate |
| F22 | Was the award recorded, and against which quote? | gate | per award | finance | An unrecorded award loses the transaction trail |
| F23 | Did the customer rate the experience? | craft | per reveal | customer_experience | Rating is solicited at the reveal moment |
| F24 | Is a complaint a service issue, a legal trigger, or a refund? | escalation | per complaint | legal, founder | Ten `legal_triggers` must never be auto-answered |
| F25 | What is the SLA state across every open RFQ right now? | diagnosis | daily | procurement | An SLA nobody watches is not an SLA |
| F26 | Which RFQs will breach an SLA in the next 24 hours? | forecast | daily | self | Prevention beats a breach report |
| F27 | Is the notification actually being delivered? | diagnosis | daily | product_eng | The seat's own KPI currently measures notification latency, not customer outcomes |
| F28 | Should a customer be told their category has no suppliers? | craft | occasional | procurement | Only when the gap is genuine, never after a retrieval failure |
| F29 | Is the working-day count correct against UAE holidays? | gate | per ladder step | founder | A ladder day computed on a naive date difference breaks a published promise |
| F30 | Has the reveal window opened for this transaction? | gate | per reveal | customer | `trg_reveal_window` |

### 2. Domain logic

**M-F1 — The ladder clock (founder rule 3, and the single most important arithmetic in this seat).**
`D0` = the customer's **payment** timestamp on the transaction (not the reveal request, not the quote
date). Working days are Mon–Fri excluding `public_holidays` (16 rows), Dubai UTC+4.
- `wd(D0, now) = 3` → **chase**: Customer Success Director contacts the supplier, customer copied.
  (`pricing_config.chase_after_working_days` = 3.)
- `wd(D0, now) = 5` → **notify the founder** for his final call.
  (`pricing_config.refund_window_working_days` = 5.)
- Founder decides. If refund: customer receives the **full** reveal fee (3.00%), nothing deducted, and is
  told banks take **7–14 working days** (`pricing_config.bank_settlement_working_days_min/max`).
- Supplier then owes `reveal_fee + 250 + 9% p.a. simple interest` and is **blocked from matching until
  paid**.
Also live: `decision_policy.refund_notify_after_working_days` = 1 — after **1** working day the customer
may press "Notify supplier" (one email). That is a customer-initiated nudge, distinct from our day-3
chase.
**A note the seat must carry**: `decision_policy.refund_claim_after_working_days` = 3 is marked **RETIRED
6 Sep 2026** in its own description — the ladder no longer has a claim window after the call. The seat
reads `pricing_config`, not that key.

**M-F2 — Stall taxonomy (deterministic, from timestamps only).**
| stage | stall condition |
|---|---|
| awaiting_clarification | customer has not answered > 24 h (`SLA-CUSTOMER-INPUT`) |
| awaiting_dispatch | dispatch-eligible > 15 min without a dispatch (`SLA-DISPATCH`) |
| awaiting_ack | dispatched > 4 h with no supplier acknowledgement (`SLA-SUPPLIER-ACK`) |
| awaiting_quote | dispatched > 48 h with fewer than the target quotes (`SLA-QUOTE-WINDOW`) |
| awaiting_comparison | quotes present > 30 min without a published comparison (`SLA-COMPARISON-PUBLISH`) |
| awaiting_reveal | comparison published, no reveal, > N days |
| awaiting_response | revealed and paid, supplier silent — this is the ladder |
`awaiting_reveal`'s N **does not exist** and must be set.

**M-F3 — Nudge policy.** Existing routines: `run_no_quote_nudges()`, `qd_reveal_nudges()`,
`fn_supplier_invite_followups()`. Caps must be explicit and stored: at most **2** supplier nudges per RFQ
(at +24 h and at the window minus 6 h), at most **2** customer nudges per comparison, none inside the UAE
weekend or a public holiday, none after 20:00 Dubai time.
**UNMEASURED:** these caps **do not exist** in `decision_policy`.

**M-F4 — Strike accounting.** `leads.chat_strikes` is the counter and `fn_matching_strike_limit()` = 3 is
the ceiling. A strike is recorded for a **dispatched, acknowledged-or-not, unanswered** RFQ. A strike is
**not** recorded when: the supplier declined explicitly (a decline is a response), the RFQ was cancelled,
the notification failed to deliver (`notifications` shows a terminal failure), or the RFQ was withdrawn
inside the window. Recording a strike for an undelivered notification is punishing a supplier for our
own failure.

**M-F5 — Refund arithmetic.**
`customer_refund = reveal_fee_paid` (full 3.00%, no deduction — founder rule 3).
`supplier_owes = reveal_fee_paid + 250 + reveal_fee_paid × 0.09 × (days_outstanding / 365)`.
`refund_reveal_fee_pct` 3, `refund_admin_fee_aed` 250, `refund_late_fee_annual_pct` 9 — all from
`decision_policy`, and the 9% is **per annum**, not per month, because the signed Supplier Agreement says
so and the document governs.

**M-F6 — SLA horizon scan.** For every open RFQ, `time_to_breach = sla_target − elapsed`. Sort ascending;
anything under 4 hours is the day's work list. Sources: `phase_b_sla_policy` (34 rows) joined to the
workflow stage.

**M-F7 — Award recording.** `inquiries.hired_supplier_id`, `completed_at`, `outcome`. `transactions` and
`reveal_invoices` carry the money. All **0 rows**.

### 3. Reasoning procedures

**F1/F2/F3 — the ladder.**
1. For every transaction with a paid reveal and no recorded supplier contact, compute `wd(D0, now)` with
   M-F1. Never a naive date difference.
2. `wd = 1` → the customer's "Notify supplier" button becomes available (one email).
3. `wd = 3` → open the chase: route to the Customer Success Director role
   (resolved through `org_role` / `org_role_alias`, never hard-coded), customer copied, on the channel
   from F18.
4. `wd = 5` → `fn_notify_founder` with the correct `p_kind` through `founder_mail_policy`, carrying:
   transaction id, quote value, reveal fee paid, supplier, the chase record, and the exact refund amount
   if he says yes. **The seat never issues the refund** — `founder_review_gates` contains
   `refund_decision`.
5. Record every step in `refund_status_transition` (32 rows exist, so the machinery has been exercised).
Stops and refuses when: `public_holidays` has no rows for the period being counted (the count would be
wrong and a wrong ladder day breaks a published promise); or the payment timestamp is missing.

**F6/F7 — "Zero or one quote after the window."**
1. Read the dispatch record: how many contacted, how many acknowledged, how many quoted.
2. Read the exclusion ledger (M-S6) for near-misses.
3. If contacted < fanout budget **and** near-misses exist → request re-dispatch from `spec_commercial`
   (`fn_rfq_redispatch_sweep`) and extend the window once.
4. If contacted = the entire eligible set and it is small → tell the customer the truth: how many
   suppliers in this category can quote, how many were contacted, how many replied, and that this is a
   supply gap we are working on. **Only if M-P6 says the gap is genuine.**
5. If one quote arrived, say plainly that this is one quote and not yet a comparison, and offer the choice
   to wait for re-dispatch or proceed.
Stops and refuses when: the zero-fit was a retrieval failure — the customer must not be told nobody serves
them.

**F11/F12 — strikes.** Apply M-F4's exclusion list before incrementing. Before the third strike, which
stops matching entirely, check the supplier's delivery history in `notifications`: if any of the three
notifications shows a terminal delivery failure, the strike count is invalid and the seat must say so and
open a defect task rather than block the supplier.

**F24 — complaint triage.** Test the text against the ten `legal_triggers` first (contract change,
liability, indemnity, termination, dispute, refund dispute, regulatory complaint, data subject request,
subpoena, chargeback). Any hit → Legal, no auto-answer. Otherwise classify as service issue (resolve
within policy, `SLA-SUPPORT-RESOLVE` 4 business hours) or refund request (founder gate).

### 4. Judgement rules

| # | condition | verdict | reason |
|---|---|---|---|
| JF1 | Working day 3 since payment, supplier silent | CHASE, customer copied | Founder rule 3 |
| JF2 | Working day 5 since payment, supplier silent | NOTIFY THE FOUNDER | Founder rule 3; his call, not ours |
| JF3 | Any refund, any amount | FOUNDER DECIDES | `founder_review_gates`; restated 5 Sep 2026 |
| JF4 | Refund approved | Customer gets the FULL 3%, nothing deducted | Founder rule 3 |
| JF5 | Refund paid | Supplier owes 3% + AED 250 + 9% p.a. and is BLOCKED until paid | Founder rule 3 |
| JF6 | Ladder day computed without `public_holidays` | INVALID — do not act on it | A wrong day breaks a published promise |
| JF7 | Notification shows terminal delivery failure | NOT a strike | Never punish a supplier for our delivery failure |
| JF8 | Explicit decline from a supplier | NOT a strike | A decline is a response |
| JF9 | Third strike would block the only supplier in a category | STILL BLOCK, and raise a supply alert | The rule is the rule; the alert is the mitigation |
| JF10 | Zero fits caused by a retrieval error | NEVER tell the customer nobody serves them | A false statement to a customer |
| JF11 | More than 2 nudges to one supplier on one RFQ | STOP | Over-chasing is how suppliers leave |
| JF12 | Nudge would land in the UAE weekend, a public holiday, or after 20:00 Dubai | HOLD to the next working morning | A weekend nudge is not urgency, it is rudeness |
| JF13 | Text matches a `legal_trigger` | LEGAL | `decision_policy` |
| JF14 | Customer declares urgency with no date | Ask for the date; do not re-prioritise on the word | Urgency inflation |
| JF15 | An RFQ has had no state change for 30 days | ARCHIVE, and say so to the customer | Dead RFQs distort every rate |
| JF16 | A refund would be faster than a chase | STILL CHASE FIRST | The ladder is published; skipping a step is a breach even when it favours the customer |
| JF17 | Customer asks for the supplier's name before revealing | REFUSE | Names are what the 3% buys |
| JF18 | Circumvention suspected | Capture evidence now, route to Legal | AED 15 000 or 3× the fee is unclaimable without contemporaneous evidence |

### 5. Technical knowledge

- **Tables**: `transactions` (0), `reveal_invoices` (0), `refunds` (0), `refund_status_transition` (32),
  `refund_event_quarantine` (0), `phase_c_refund_decision` (0), `payment_dispute` (0),
  `notifications` (855), `email_suppressions` (37), `email_verifications` (139),
  `phone_verifications` (9), `public_holidays` (16), `messaging_template` (14), `response_template` (13),
  `phase_b_sla_policy` (34), `inquiry_cancellations` (0), `rfq_archives` (0), `reviews` (0),
  `rate_dims` (the six-dimension rating), `founder_mail_policy` (61).
- **Routines**: `run_no_quote_nudges`, `qd_reveal_nudges`, `fn_rfq_redispatch_sweep`,
  `fn_supplier_invite_followups`, `fn_cancel_inquiry`, `fn_edit_inquiry`, `fn_notify_supplier`,
  `trg_reveal_window`, `trg_reveal_receipt`, `trg_rfq_complete`, `fn_phase_d_reveal_permitted`,
  `fn_refund_amount_aed`, `fn_kernel_refund_decision_record`, `fn_founder_mail_route`,
  `fn_notify_founder` (needs `p_kind`).
- **Channels**: email (Resend), WhatsApp (template-gated), SMS. `leads.wa_optin`, `email_verified`,
  `phone_e164` decide reachability. Never send a real message by hand; fixtures are `ZZ DEMO` /
  `@example.invalid` inside a `rehearsal_window`.
- **What must be stored so this seat can act alone**: the nudge caps and quiet hours (M-F3) — **do not
  exist**; the `awaiting_reveal` stall threshold (M-F2) — **does not exist**; a
  `circumvention_claim` table (F17) — **does not exist**; the stall taxonomy itself as a view — **does
  not exist**.
- **Money mechanics**: Stripe both ways; QuotesDone never holds supplier bank details; bank settlement
  7–14 working days; the refund is the full 3% with **no** processing deduction (the 3% "refund
  processing deduction" in `knowledge/COMPANY_CANON.md` is **superseded** by founder rule 3 and must not
  be quoted).

### 6. Academic knowledge

Disciplines: **service operations and SLA design** (queueing, escalation ladders, the economics of a
promise), **customer experience measurement** (CSAT, NPS, effort score, and their failure modes),
**dispute resolution and consumer-protection practice**, **collections and receivables** (the supplier
clawback is a receivable), and **behavioural nudge timing**.

Lawful primary sources: **CXPA** published CCXP competency framework (the six domains this seat is
certified against); CIPS published L4 syllabus outline (Commercial Contracting, Supplier Relationships);
**UAE Federal Decree-Law 50/2022** (Commercial Transactions) — the 9% statutory maximum interest that
founder rule 3 cites; **UAE Federal Law 15/2020** on consumer protection and its executive regulations;
UAE Ministry of Human Resources and Emiratisation published public-holiday circulars (the working-day
calendar); **UAE Central Bank** published payment-settlement guidance for the 7–14 working-day statement;
**ITIL 4** published service-management practice summaries; published open-access literature on
service recovery (the service-recovery paradox). Never copyrighted study texts.

Certifications held: **CIPS Level 4 Diploma** (pass 50.00%, rank 1) and **CCXP (CXPA)** (pass 68.00%,
rank 2) — Customer Insights and Understanding, Customer Experience Strategy, Metrics Measurement and ROI,
Experience Design Improvement and Innovation, Organizational Adoption and Accountability, Culture and
Accountability.
**Syllabus areas failed: none recorded — this seat has never sat either exam.** Sitting both is a Q1
milestone; CCXP *Metrics Measurement and ROI* is the area that would have caught this seat's own
mis-specified KPI (below).

### 7. Corporate knowledge

- **Founder rule 3 verbatim**, including that every refund of any amount is the founder's decision and
  that the customer gets the full 3% with nothing deducted.
- **Founder ruling 17 Aug 2026, restated 5 Sep 2026**: refunds are the *only* thing routed to the
  founder. `founder_review_gates` = [`refund_decision`, `refund_outside_policy`]. Marketing, budget,
  legal, strategy, partnership and security decisions belong to their accountable roles.
- **Founder mail policy**: every notification to the founder goes through `founder_mail_policy`
  (61 rows) and `fn_founder_mail_route`; `fn_notify_founder` requires `p_kind`; a new kind needs a policy
  row first.
- **Rating solicitation** happens at the reveal moment, not later.
- **Authority** (`employee_authority`): three rows, all **advisory at AED 0** — `nudge`,
  `refund_within_window`, `resolve_within_policy`, each noted "may prepare, but execution requires the
  department head". So this seat prepares the chase and the founder packet; it executes neither the
  refund nor, strictly, the nudge.
- **Workflows**: `employee_task` (owner), `rfq_handling` (participant).
- **Knowledge**: 10 `agent_knowledge` rows, 11 `employee_knowledge` rows.
- **KPI — and a measured defect this seat must report about itself.** Its single KPI row is *"Customer
  issues resolved within SLA"*, target 95% weekly, but the `measure_sql` is
  `select round(100.0*count(*) filter (where sent_at is not null and sent_at - created_at < interval '24 hours')/nullif(count(*),0),2) from notifications where created_at > now() - interval '7 days'`.
  That measures **notification send latency**, not customer issues resolved. It reported **59.44%** at
  2026-09-07 03:30 UTC. The seat must not present 59.44% as its resolution rate; it must say the
  instrument measures the wrong subject and open a task to replace it.
- **Hands to**: `customer_experience` (the day-3 chase is theirs to send), the founder (day 5),
  `finance` (refund execution by `payments_and_billing_manager`, reconciliation by
  `financial_controller` — both named in `decision_policy`), `legal` (triggers, circumvention),
  `spec_commercial` (strikes, blocks, re-dispatch), `procurement` (stalls and supply gaps).
- **History**: 0 transactions, 0 reveals, 0 refunds. `refund_status_transition` holds 32 rows from
  rehearsals, so the state machine has been exercised without money. The published canon file still
  states a 3-working-day refund window and a 3% processing deduction; **both are superseded** by founder
  rule 3 and `pricing_config`.

### 8. One-year plan

**Objective.** Every RFQ reaches an award or an honest close, and every revealed transaction runs the
published ladder exactly, on the correct working-day count.

**Metrics owned.** (1) **Ladder fidelity** — share of revealed transactions where the day-3 chase and the
day-5 founder notification happened on the correct working day; target **100%**, because it is a published
promise, not an average. (2) **Reveal conversion** — share of published comparisons that reach a paid
reveal; this is the seat's direct revenue metric. (3) **Stall recovery** — share of stalled RFQs that
reach a quote after intervention.

**Quarterly milestones.**
- **Q1.** Replace the mis-specified KPI. Build the stall taxonomy view, the nudge caps and quiet hours,
  and the `awaiting_reveal` threshold. Prove the full ladder end-to-end against a `ZZ DEMO` fixture inside
  a `rehearsal_window`, including the founder packet, with the working-day arithmetic checked across a
  UAE public holiday. Sit CIPS L4 and CCXP.
- **Q2.** First real reveal and first real ladder run. Reveal conversion measured for the first time.
- **Q3.** Stall recovery ≥50%. Rating solicitation live at the reveal moment.
- **Q4.** Ladder fidelity 100% over ≥100 reveals; reveal-to-refund ≤5% (shared with `quote_evaluation`).

**Capacity check.** Yes on throughput — the ladder is a daily scan over open transactions and a
working-day subtraction. **The revenue slice is the conversion step**: the 3% is earned when a customer
who has a comparison chooses to reveal. On the AED 50 000 / 667-reveal scenario, 667 reveals a year is
about **13 a week** — trivially within a deterministic scanner's capacity. The risk this seat carries is
not throughput but **refund leakage**: every non-response refund reverses a full 3% *and* consumes the
founder's attention, and `company_economics` item 10 lists it as the **first** of the four things that
destroy the economics. At a 20% refund rate the AED 1 000 000 becomes AED 800 000 of recognised revenue
plus a clawback receivable against suppliers who have already shown they do not answer.

**Dependencies.** `spec_commercial` for re-dispatch and strike enforcement; `quote_evaluation` for the
comparison that makes a reveal worth paying for; `customer_experience` for the day-3 chase;
finance for refund execution and clawback collection; the founder for every refund decision.

### 9. What this seat cannot do without a model

- **Nothing in its taxonomy.** The ladder is calendar arithmetic; stalls are timestamp comparisons;
  strikes are counters with an exclusion list; the refund amount is a formula; triage is a lexeme test
  against ten stored phrases.
- **What is deliberately templated rather than written**: the customer-facing wording at each ladder step,
  the chase to the supplier, and the founder packet. These are `response_template` /
  `messaging_template` rows with computed slots (working day, amount, dates, supplier reference). A
  template is the right answer here anyway — a published promise should be worded identically every time,
  and a model that rephrases it each run is a liability, not a feature.
- **One genuine limit, honestly stated**: an inbound message that is neither a `legal_trigger` hit nor a
  recognisable service/refund intent is **not classified** — it is escalated to
  `customer_experience` with the text quoted. The seat does not attempt to understand novel free prose.

---

## doc_intel_manager — Document Intelligence Manager

Responsibility of record: *"Own document understanding across the platform: classification, extraction,
comparison and validation. Every uploaded file leaves this department as structured data or as a named
reason it could not."* Since 4 September 2026 this seat also carries the live accountability of the parked
`boq_analyst` and `drawing_analyst` seats.

**This is the one seat in the department with a genuine, unavoidable model dependency, and section 9 says
so plainly rather than pretending otherwise.**

### 1. Question and decision taxonomy

| id | question or decision | kind | how often | who asks | what a wrong answer costs |
|---|---|---|---|---|---|
| D1 | What kind of document is this? | diagnosis | every upload | intake | The wrong extractor produces confident nonsense |
| D2 | Is this document machine-readable text or a scan? | gate | every upload | self | Running a text extractor on a scan returns nothing and looks like an empty document |
| D3 | Which pages of a 200-page tender actually matter? | sequencing | per tender | rfq_qualification_mgr | Extracting everything costs more than extracting the right ten pages |
| D4 | Can the trade licence number be read and does it validate? | gate | every supplier | supplier ops | The trade licence is the **only** required supplier document |
| D5 | Does the licence's activity cover the trade the supplier claims? | gate | every supplier | spec_commercial | Matching a supplier to work their licence does not permit |
| D6 | When does this licence or insurance expire? | gate | every supplier document | spec_commercial | An expired licence must pause matching |
| D7 | Does an expiry fall inside the quote validity window? | gate | frequent | rfq_qualification_mgr | A quote from a supplier who cannot legally deliver |
| D8 | Which BOQ lines are in this file? | diagnosis | per BOQ | rfq_qualification_mgr | The RFQ's line items come from here |
| D9 | What quantity and unit does each line carry? | diagnosis | per BOQ line | quote_evaluation | A unit error is a 10× pricing error |
| D10 | Is a BOQ line missing a quantity, a unit, or a description? | gate | per BOQ | customer | Suppliers guess, and guesses are not comparable |
| D11 | Do the BOQ totals add up? | gate | per BOQ | customer | Arithmetic errors in a BOQ are common and checkable |
| D12 | Are two BOQ lines contradictory (same item, different quantity)? | escalation | occasional | customer | Suppliers quote different jobs |
| D13 | Which trade does each BOQ section belong to? | diagnosis | per BOQ | inquiry_router | Multi-trade split depends on this |
| D14 | What does this drawing show, and what does it not show? | diagnosis | per drawing | rfq_qualification_mgr | "The drawing does not show the ceiling void" is a real, useful answer |
| D15 | How many rooms / fixtures / points does the drawing indicate? | diagnosis | per drawing | rfq_qualification_mgr | Counts drive quantities |
| D16 | Does the drawing carry buyer-identifying content (title block, client name, address)? | gate | every drawing | spec_commercial | Anonymity breach — a title block names the client |
| D17 | Has the drawing been redacted before dispatch? | gate | every drawing | spec_commercial | Same |
| D18 | Which quote fields can be read from this supplier PDF? | diagnosis | every quote upload | quote_evaluation | The comparison's inputs |
| D19 | Are the quote's line items extractable, or is it a lump-sum image? | gate | every quote upload | quote_evaluation | A lump-sum image cannot be compared item by item |
| D20 | Does the extracted total match the sum of the extracted lines? | gate | every quote upload | quote_evaluation | The cheapest arithmetic check there is, and the most valuable |
| D21 | Is the extraction confident enough to use? | gate | every extraction | all | A low-confidence extraction used as fact is the worst outcome available |
| D22 | What is the named reason this document could not be read? | craft | per failure | customer, supplier | The charter sentence: structured data **or a named reason** |
| D23 | Is this document a duplicate of one already on file? | gate | every upload | self | Re-extracting costs money and creates conflicting answers |
| D24 | Which fields did this document answer, and which are still open? | sequencing | per upload | rfq_qualification_mgr | Stops us asking for what we already have |
| D25 | Is the document's language Arabic, English, or mixed? | diagnosis | every upload | self | Extraction and field labels both depend on it |
| D26 | Does the document contain personal data requiring PDPL handling? | gate | every upload | legal | Federal Decree-Law 45/2021 |
| D27 | How long must this document be retained, and when is it purged? | gate | per document | legal | `retention_policy` |
| D28 | Is the extraction pipeline's accuracy within target? | diagnosis | weekly | procurement | 95% target against the fixture set |
| D29 | Should a document be escalated to a human/specialist rather than extracted? | escalation | occasional | procurement | `SLA-DOCUMENT-COMPLEX` says escalate unreadable or complex documents |
| D30 | Did this document meet its processing SLA? | gate | every upload | rfq_success | 15 min standard, 2 h complex |

### 2. Domain logic

**M-D1 — Document classification (deterministic).**
A scored classifier over: file extension and MIME; PDF metadata (`phase_d_metadata_scan` exists, 5 rows);
page count; text-layer presence and character density; and a **keyword fingerprint per document class**
held as rows — trade licence (`licence`, `رخصة`, `DED`, `DET`, `establishment`, `activity`, `issue date`,
`expiry date`), BOQ (`bill of quantities`, `item`, `description`, `qty`, `unit`, `rate`, `amount`, `sqm`,
`nos`, `lm`), drawing (`scale`, `drawing no`, `title block`, `rev`, `north`, `A1`, `A3`), quote
(`quotation`, `quote no`, `validity`, `payment terms`, `warranty`, `subtotal`, `VAT`), insurance
(`policy`, `insured`, `period of insurance`, `sum insured`), ISO certificate (`ISO 9001`, `certificate
no`, `accredited`, `surveillance`).
**UNMEASURED:** this fingerprint table **does not exist**. It is perhaps 8 classes × 15 lexemes and is
entirely deterministic.

**M-D2 — Text-layer test (deterministic).** `characters_extracted / page_count`. Below a threshold the
document is a scan and needs OCR. `extract_text` and `pdf_native` edge functions exist.
**UNMEASURED:** the threshold **does not exist**; ~100 characters per page is the usual industry line and
must be fitted against real files, not assumed.

**M-D3 — Trade licence field extraction (deterministic, pattern-based).**
UAE trade licence numbers, issue and expiry dates, and issuing authority are **positionally and lexically
regular**: a labelled field followed by a value. `fn_supplier_licence_gate(license_doc_path,
trade_license_no, license_expiry)` already exists as the gate. Extraction by labelled-field regex per
issuing authority (DED/DET Dubai, DED Abu Dhabi, Sharjah SEDD, Ajman, RAK, UAQ, Fujairah, plus the free
zones) is deterministic; only the **layout variation across authorities** makes it work, and that is a
table of patterns, not a judgement.
**UNMEASURED:** that per-authority pattern table **does not exist**. `leads.license_authority` exists as a
column. Measured: exactly **1** lead in 22 265 has a `trade_license_no`.

**M-D4 — BOQ extraction (partly deterministic).**
A BOQ in a spreadsheet (xlsx/csv) is **fully deterministic**: header detection by lexeme match on the
first ten rows, then column mapping to (item, description, qty, unit, rate, amount), then row extraction.
`make_xlsx` exists; a reader does not.
A BOQ in a **structured PDF table** is largely deterministic via table extraction.
A BOQ embedded in **prose or a scanned image** is not.
Checks that are pure arithmetic once lines exist: `amount = qty × rate` per line; `total = Σ amount`;
`qty > 0`; `unit ∈ mdm_units` (23 rows); section→trade mapping via `taxonomy_trade` aliases and
`mep_trade_pattern` (123 rows).
**Measured today:** `boq_fixture` holds **2** fixtures and `boq_fixture_run` **6** runs. Runs 1 and 2
(12 Aug 2026) both **failed** with `drawing_boq returned no boq array` — the function returned a prose
summary object instead of a line array. Run 3 succeeded and returned properly shaped lines (e.g. 78 sqm
porcelain floor tiles with `basis` "Total built-up area of 78 sqm as per drawing notes", confidence
high). So the pipeline is **shape-unstable**, which is exactly the failure mode a model produces and a
parser does not.

**M-D5 — Quote extraction and the arithmetic check.**
Once lines exist: `Σ (qty × unit_price) = stated_total ± tolerance`. A mismatch is a **named, citable
finding** and needs no judgement at all. This single check catches most quote transcription errors and is
free.

**M-D6 — Redaction (deterministic where it counts).**
Drawing title blocks are positionally regular (bottom-right, or a right-hand strip). Client name, project
address, consultant name and contact details are the targets. `drawing_redact` and
`drawing_redaction_runs` exist (**0 rows**). A deterministic redaction is: mask the title-block region by
geometry, then mask any occurrence of the customer's known strings (name, company, phone, email, address)
found anywhere in the extracted text layer. The second half is exact string matching against known values
— no judgement. The first half is geometry.
**UNMEASURED:** `drawing_redaction_runs` has never run.

**M-D7 — Extraction confidence, honestly defined.**
`confidence = f(text_layer_density, fields_matched / fields_expected, arithmetic_checks_passed)`.
Below threshold → **do not use the extraction as fact**; return the named reason (D22). This must be a
stored threshold, not a feeling. **It does not exist.**

**M-D8 — Accuracy measurement.** Against `boq_fixture` (2) and any fixture set added.
`employee_kpi` id 103 measures the latest run per fixture where `ok`. Measured: **null** — because the
only successful run's `score_pct` is null and two of three fixtures failed on shape.

### 3. Reasoning procedures

**D1/D2 — "What is this, and can I read it?"**
1. MIME and extension → candidate classes.
2. Extract the text layer (`extract_text` / `pdf_native`). Compute characters per page.
3. Score the fingerprint (M-D1) over the extracted text. Highest class wins if it clears a margin.
4. If characters per page is below the scan threshold, mark `needs_ocr` and route accordingly.
5. If no class clears the margin, **return the named reason**: "this file has N pages, M characters of
   text, and matched no known document class; the closest were X (score) and Y (score)". Never guess.
Stops and refuses when: the file is encrypted, corrupt, or over the size limit — each a distinct named
reason.

**D4/D5/D6 — the trade licence path (the highest-value deterministic path in this seat).**
1. Classify as licence.
2. Identify the issuing authority by its lexeme set.
3. Apply that authority's labelled-field patterns to pull licence number, issue date, expiry date,
   legal name, activities.
4. Compare the extracted number with `leads.trade_license_no`. Mismatch → hold, do not approve.
5. Compare the extracted expiry with `leads.license_expiry`. Expired or expiring within the quote
   validity window → `matching_blocked`.
6. Map the licence **activities** to `taxonomy_trade` codes through the alias registry. Any claimed trade
   not covered by an activity is a **stated gap**, not a rejection — the supplier may hold a second
   licence.
7. Feed the result to `fn_supplier_licence_gate`.
Stops and refuses when: the authority is unrecognised (name it), or the expiry cannot be parsed (say so
rather than defaulting).

**D8–D13 — the BOQ path.**
1. Spreadsheet → deterministic reader (header detect, column map, row extract). PDF with a table layer →
   table extraction. Scanned or prose → see section 9.
2. Arithmetic: per-line `amount = qty × rate`; `total = Σ amount`; `qty > 0`; unit in `mdm_units`.
3. Completeness: any line missing qty, unit or description is listed by row number.
4. Contradiction: two lines with the same normalised description and different quantities in the same
   section → raise to the customer with both rows quoted.
5. Section→trade: map each section heading through `taxonomy_trade` aliases and `mep_trade_pattern`;
   unmapped sections are listed, not silently dropped.
6. Emit `inquiry_requirement` rows.
Stops and refuses when: fewer than a threshold fraction of rows produce a (qty, unit) pair — that is a
prose document wearing a table's name, and the named reason says so.

**D14–D17 — the drawing path.**
1. Redact first (M-D6), always before anything leaves the department.
2. Extract the text layer for room names, dimensions, drawing number, scale, revision.
3. Counts of repeated symbols (sockets, light points, sprinkler heads) are **not** deterministic from a
   text layer; see section 9.
4. **State what the drawing does not show** — this is a genuine deliverable and it is deterministic:
   the absence of a section, an elevation, a ceiling plan, or a services layout is checkable from the
   sheet list.
Stops and refuses when: redaction has not run — a drawing with an unredacted title block must never reach
a supplier.

**D22 — the named reason.** The charter sentence. Every failure returns: the document class attempted,
the specific step that failed, the numbers behind it (pages, characters, rows parsed, fields matched),
and what would make it work (a spreadsheet instead of a scan, a clearer copy, the missing page).

### 4. Judgement rules

| # | condition | verdict | reason |
|---|---|---|---|
| JD1 | Document class does not clear the margin | NAMED REASON, never a guess | The charter: structured data **or** a named reason |
| JD2 | Extraction confidence below threshold | DO NOT USE AS FACT | A confident wrong number is worse than no number |
| JD3 | Licence number on the document ≠ the one on file | HOLD; do not approve | Identity mismatch is the whole point of the check |
| JD4 | Licence expired, or expiring inside the quote validity window | BLOCK matching | The supplier cannot legally deliver |
| JD5 | Licence activity does not cover the claimed trade | STATE the gap; do not auto-reject | They may hold a second licence |
| JD6 | BOQ line `amount ≠ qty × rate` | RAISE, never correct | Silent correction is fabrication |
| JD7 | BOQ unit not in `mdm_units` | RAISE | An unrecognised unit is a comparison hazard |
| JD8 | Two BOQ lines contradict | ASK the customer with both rows quoted | Suppliers must quote one job |
| JD9 | Drawing not redacted | BLOCK dispatch absolutely | A title block names the client |
| JD10 | Document contains personal data | PDPL handling; retention policy applies | Federal Decree-Law 45/2021 |
| JD11 | Duplicate of a document already on file | DO NOT re-extract; link to the existing extraction | Re-extraction creates conflicting answers |
| JD12 | Extraction returned a prose summary where a line array was expected | TREAT AS FAILURE | Measured: `boq_fixture_run` 1 and 2 failed exactly this way and returned `ok:true` |
| JD13 | A pipeline returns `ok:true` with an empty or wrong-shaped payload | FAILURE, and a defect task | An HTTP 200 with no usable content is the invisible failure mode |
| JD14 | Complex or unreadable document | ESCALATE within `SLA-DOCUMENT-COMPLEX` (2 h) | Published SLA |
| JD15 | An extracted value conflicts with a customer's own statement | CUSTOMER WINS | An extraction is evidence, not testimony |
| JD16 | Accuracy cannot be computed because fixtures failed on shape | SAY SO; do not report a null as a pass | Zero cannot tell a dead guard from an idle system |

### 5. Technical knowledge

- **Tables**: `documents` (10, all `done`), `document_inventory` (0), `doc_versions` (385),
  `doc_backups` (193), `boq_fixture` (2), `boq_fixture_run` (6), `drawing_redaction_runs` (**0**),
  `inquiry_answer_document` (0), `phase_d_metadata_scan` (5), `phase_d_file_revision` (7),
  `phase_d_personal_identifier_class` (11), `retention_policy` (11), `pdpl_requests` / `pdpl_erase_files`
  (0), `mdm_units` (23), `mdm_standards` (22), `mdm_brands` (51), `mdm_manufacturers` (22),
  `field_definition` (552, with `evidence_rule` and `validation_ref` per field),
  `field_definition_source` (880), `mep_trade_pattern` (123), `taxonomy_trade` (40).
- **Routines and functions**: `fn_supplier_licence_gate`, `fn_supplier_document_impact`,
  `fn_supplier_expiries`, `fn_supplier_certifications`, `fn_freeze_supplier_brief`,
  `trg_reg_inquiry_doc`, `trg_reg_quote_doc`, `fn_phase_d_file_revision_dispatchable`,
  `fn_phase_d_quote_original_intact`.
- **Edge functions**: `doc_extract`, `extract_text`, `pdf_native`, `drawing_boq`, `drawing_redact`,
  `cad_convert`, `quote_extract`, `license_extract`, `make_pdf`, `make_xlsx`, `doc_render`,
  `boq_fixture_check`, `transcribe`. Of these, `doc_extract`, `drawing_boq`, `quote_extract`,
  `license_extract`, `extract_text`, `transcribe` and `drawing_redact` **call the AI gateway today**.
  `boq_fixture_check`, `make_pdf`, `make_xlsx` and `pdf_native` do not.
- **Formats that must be known as data, not inferred**: PDF (text layer vs image, embedded tables),
  xlsx/csv, DWG/DXF (via `cad_convert`), IFC, JPEG/PNG scans, and the UAE trade-licence layouts per
  issuing authority.
- **What must be stored so this seat can act alone**: the document-class fingerprint table — **does not
  exist**; the scan threshold — **does not exist**; the per-authority licence pattern table — **does not
  exist**; the confidence threshold — **does not exist**; a spreadsheet BOQ reader — **does not exist**;
  the title-block geometry rules — **do not exist**.

### 6. Academic knowledge

Disciplines: **information and records management** (capture, classification, retention, disposition),
**document and table understanding** (layout analysis, table structure recognition), **OCR and
information extraction** (the difference between recognition, extraction and understanding),
**data quality and metadata management**, and **construction measurement** (how a BOQ is written, so it
can be read).

Lawful primary sources: **AIIM** published CIP competency framework (the five domains this seat is
certified against); **DAMA-DMBOK** published framework overview and knowledge-area list (the CDMP
syllabus); **ISO 15489** records management published abstract; **ISO 19005 (PDF/A)** published abstract;
**ISO 32000 (PDF)** published specification abstract; **ISO 8000** data quality published abstract;
**buildingSMART IFC** published specification (open standard); **RICS New Rules of Measurement** and
**CESMM** published structures for how BOQs are organised; UAE **Federal Decree-Law 45/2021** (PDPL) and
its executive regulations; Dubai **DET/DED** published trade-licence formats and activity lists, and the
equivalent published formats from Abu Dhabi ADDED, Sharjah SEDD, Ajman, RAK, UAQ and Fujairah;
**ICDAR** published competition datasets and task definitions for table recognition (public research
datasets). Never copyrighted study texts.

Certifications held: **CIP (AIIM)** (pass 70.00%, rank 1) — Creating and Capturing Information,
Extracting Intelligence from Information, Digitalizing Information-Intensive Processes, Automating
Governance and Compliance, Implementing an Information Management Solution; and **CDMP (DAMA)**
(pass 60.00%, rank 2) — Data Governance, Data Architecture, Data Modelling and Design, Data Quality,
Metadata Management, Master and Reference Data Management, Data Warehousing and BI, Data Security.
**Syllabus areas failed: none recorded — this seat has never sat either exam.** Sitting both is a Q1
milestone; AIIM *Extracting Intelligence from Information* is this seat's core competence and CDMP
*Data Quality* is what D20/D21 depend on.

### 7. Corporate knowledge

- The five hard rules, and specifically the anonymity boundary: a drawing title block or a quote letterhead
  is the commonest way an identity leaks before the reveal.
- **The trade licence is the only required supplier document** (published canon and supplier onboarding).
  Insurance, ISO, manufacturer authorisation, EGR and catalogues are optional and only widen reach.
- **The company's own licence and tax status**, which this seat must never re-ask: DET licence **1633275**,
  expiry **24 Jun 2027**; no VAT registration until the AED 375 000 threshold is crossed.
- **Authority** (`employee_authority`): one row — `analysis`, `supervised`, no threshold, seeded
  14 Aug 2026. It has **no document-specific action class** despite owning every document decision. That
  is a gap in the authority ledger.
- **Knowledge**: 9 `agent_knowledge` rows. **`employee_knowledge` holds zero rows for this seat** — one of
  only two marketplace seats with none.
- **KPIs** — four rows, and this seat should quote all four honestly:
  - *Documents parsed to structured output*, target 85%, **actual 60.00%** measured 2026-09-07 03:30 UTC
    over `documents where status='done'`.
  - *BOQ lines extracted correctly*, target 95%, actual **null** — the measure reads the latest `ok` run
    per fixture and there is no scored successful run.
  - *Drawings linked to RFQ items*, target 70%, `no_measure_reason`: "NEEDS DEMAND THAT DOES NOT EXIST…
    2 drawings are on file but `inquiry_requirement`, `quote_requirements` and `inquiry_answer_document`
    hold 0 rows, so there is no RFQ line item to link a drawing to. This starts answering with the first
    inquiry; it is a wait, not a build."
  - *Inquiries complete before a supplier is invited*, target 85%, same `no_measure_reason`. **This KPI
    belongs to `rfq_qualification_mgr`, not to this seat** — it should be moved.
- **Hands to**: `rfq_qualification_mgr` (document-derived answers and `inquiry_requirement` rows),
  `quote_evaluation` (extracted quote lines), `spec_commercial` (redacted, frozen supplier package),
  supplier ops (licence verification and expiry blocks), `legal` (PDPL and retention).
- **History it must not forget**: the two parked seats (`boq_analyst`, `drawing_analyst`) whose work this
  seat inherited on 4 Sep 2026; the two `boq_fixture_run` failures on 12 Aug 2026 where the pipeline
  returned `ok:true` with a prose summary instead of a line array — an HTTP-200 failure that ordinary
  error monitoring cannot see.

### 8. One-year plan

**Objective.** Every uploaded file leaves as structured data or as a named reason, and the deterministic
share of that work rises every quarter.

**Metrics owned.** (1) **Structured-output rate** — `employee_kpi` id 101, target 85%, **measured 60.00%**.
(2) **Deterministic share** — the share of documents processed with **zero** model calls; **this metric
does not exist today and is the one the founder's constraint makes central**; target ≥70% by Q4.
(3) **BOQ line accuracy** against the fixture set, target 95%, currently unmeasurable because the fixtures
fail on shape.

**Quarterly milestones.**
- **Q1.** Build the four missing tables (class fingerprints, scan threshold, per-authority licence
  patterns, confidence threshold) and the **spreadsheet BOQ reader**, which is pure code and removes the
  model from the commonest BOQ format entirely. Fix the shape instability that failed
  `boq_fixture_run` 1 and 2 — a schema check on the returned payload, so `ok:true` with the wrong shape
  becomes a failure. Grow `boq_fixture` from 2 to ≥20 fixtures. Sit CIP and CDMP.
  **Target: deterministic share ≥30%.**
- **Q2.** Deterministic licence extraction live for the seven emirates' authorities plus the main free
  zones — this alone covers the only *required* supplier document, on the path that gates 22 264 unverified
  leads. Deterministic drawing redaction (title-block geometry + known-string masking) with
  `drawing_redaction_runs` non-empty. **Deterministic share ≥50%.**
- **Q3.** Table-layer extraction for structured PDF BOQs and quotes without a model. The
  `amount = qty × rate` and `total = Σ` checks live on every extraction. **Deterministic share ≥65%.**
- **Q4.** **Deterministic share ≥70%**, structured-output rate ≥85%, BOQ accuracy ≥95% on a ≥20-fixture
  set.

**Capacity check.** Partly. The deterministic paths — classification, spreadsheet BOQs, licence fields,
redaction, arithmetic validation — are all buildable and all scale. **The residual is real**: scanned
drawings and scanned prose BOQs cannot be read deterministically, and they are common in UAE
construction. The honest position is that this seat can reach roughly 70% deterministic and the remaining
30% must either use a model, be refused with a named reason, or be pushed back to the customer as
"please send the BOQ as a spreadsheet".

**The revenue slice.** Indirect but large. This seat gates the **only required supplier document**, and
today **1** of 22 265 leads has a trade licence number on file. Every supplier verification runs through
here, and `fn_match_capability` cannot return a supplier who is not verified. So the year-one supply
target — 10 confirmed suppliers per active category, 30 for the 3-trade Dubai launch, 400 for 40
categories — is throttled by this seat's licence path. At 30 verifications needed for Q1 and 400 for the
year, deterministic licence extraction is worth more to the AED 1 000 000 than any other single thing in
this section.

**Dependencies.** Supplier ops for the documents to arrive at all (171 invited, 0 registered);
`rfq_qualification_mgr` for `inquiry_requirement` to exist so drawings can be linked to anything;
`product_eng` for the payload schema check; `legal` for PDPL and retention.

### 9. What this seat cannot do without a model

This is the honest list the brief asks for, and it is the only substantial one in the department.

1. **Reading a scanned (image-only) document.** OCR itself is not a language model, and an OCR engine is a
   legitimate deterministic-adjacent tool; but the estate's current path runs scans through the AI
   gateway. **A dedicated OCR engine would remove the model dependency for recognition** while leaving
   understanding still open. That is a build decision for the founder: an OCR engine is a fixed cost, a
   model is a per-page cost.
2. **Interpreting a construction drawing** — counting sockets, light points, sprinkler heads, or reading a
   layout to derive quantities. There is no deterministic route from a raster drawing to a quantity.
   `drawing_boq` calls the gateway, and the measured evidence (`boq_fixture_run` 1 and 2 failing on shape)
   shows even the model path is not reliable. **Deterministic alternative: refuse, and ask the customer
   for a BOQ or an area figure.** For a DWG/DXF or IFC file, `cad_convert` opens a genuinely deterministic
   route — geometry and object counts are *in* the file — and that route should be built.
3. **Extracting a BOQ that is written as prose or embedded in a scanned image.** Deterministic
   alternative: refuse with a named reason and ask for a spreadsheet. This is a real conversion cost and
   the founder should know it.
4. **Judging whether an ISO certificate or a manufacturer authorisation is genuine.** Deterministic
   alternative: check the certificate number against the issuing body's public register where one exists
   (a lookup, not a model), and otherwise mark it *unverified* rather than *valid*. Since these documents
   are **optional**, marking them unverified costs the supplier reach but never blocks them.

**Everything else in D1–D30 — classification of text-layer documents, spreadsheet BOQs, licence fields,
expiry arithmetic, unit validation, the `amount = qty × rate` and `total = Σ` checks, duplicate
detection, redaction by geometry and known-string masking, the named-reason composition — needs no model
at all**, and none of it is built yet. That is where this seat's first year goes.

---

## Cross-cutting: what this department needs built, and what it must stop claiming

**Assets that do not exist and are required for a model-free department** (all named above, gathered here
so the founder can see the size of the ask):

| # | asset | owner seat | why it blocks |
|---|---|---|---|
| 1 | Route thresholds `T_refuse` / `T_accept` / `T_margin` in `decision_policy`, fitted against the 344 `kb_operational_route_test` rows | inquiry_router | Without them, routing has no refusal rule |
| 2 | `trade_precedence` edge list (40 trades) | inquiry_router | Multi-trade sequencing |
| 3 | Implied-trade table ("new DB board → electrical + utility approval") | inquiry_router | Missing implied trades produce undeliverable quotes |
| 4 | Four intent lexeme sets (RFQ / support / supplier / spam) | inquiry_router | Non-RFQs enter the funnel |
| 5 | Quantity plausibility bands per (trade, unit) | rfq_qualification_mgr | Order-of-magnitude errors reach suppliers |
| 6 | Non-answer lexicon as data | rfq_qualification_mgr | "tbc" counted as an answer |
| 7 | Answer-precedence order in `decision_policy` | rfq_qualification_mgr | Conflicts resolved by preference, not rule |
| 8 | Clarification round budget | rfq_qualification_mgr | Over-qualifying loses RFQs |
| 9 | Per-RFQ exclusion ledger | spec_commercial | The supply shopping list does not exist |
| 10 | Re-dispatch target and delay | spec_commercial | Stalled RFQs have no rule |
| 11 | Reconciled authority table (trade, emirate, work_type) → approval | spec_commercial | `taxonomy_trade` and `business_rules` disagree |
| 12 | `quote_requirements` rows (56 categories + a `default`) | quote_evaluation | `quote_gate` currently cannot fail — 0 rows |
| 13 | Unit conversion table | quote_evaluation | Price spans are meaningless across units |
| 14 | `category_price_stats` rows | quote_evaluation | Budget and price plausibility unmeasured |
| 15 | Equivalence table for spec substitutions | quote_evaluation | The one comparison judgement that needs data or a model |
| 16 | Nudge caps and quiet hours | rfq_success | Over-chasing loses suppliers |
| 17 | Stall taxonomy view | rfq_success | Stalls are invisible |
| 18 | `circumvention_claim` table | rfq_success / legal | Founder rule 4 is unclaimable without contemporaneous evidence |
| 19 | Document-class fingerprints, scan threshold, licence patterns, confidence threshold | doc_intel_manager | Every deterministic document path |
| 20 | Spreadsheet BOQ reader | doc_intel_manager | Removes the model from the commonest BOQ format |

**Things the department must stop claiming, because they are measured false today:**

- That matching works — precision is **32%** on the standing case set, down from 100% on 10 Aug 2026, and
  the same five suppliers are returned for every case.
- That `quote_gate` gates anything — `quote_requirements` has **0 rows**, so it passes every quote at
  score 100 with the note "no standard defined".
- That the supplier score is a 0–100 scale — `supplier_perf` has **0 rows**, so the 15 track-record points
  are unearnable and the achievable maximum is **85**.
- That the deterministic engines are a degradation — under the founder's constraint they are the
  configured primary path, and the `degraded` label and "the AI adviser was unavailable" disclaimer are
  now inaccurate.
- That `knowledge/COMPANY_CANON.md` is current — it is dated 24 Jul 2026 and still states a 3-working-day
  refund window, a 3% refund processing deduction, and a founder who approves marketing posts and ad
  budgets. All three are superseded by founder rule 3, `pricing_config` and `founder_review_gates`.
- That six of these seven seats hold their certifications — **only `procurement` has sat an exam, and it
  failed both attempts** (27.50% and 10.00% against a 50% pass mark, 7 Sep 2026). The other six have no
  `certification_exam_result` row at all.

**The department's honest one-line answer on the AED 1 000 000.** At 3% of quote value, AED 1 000 000
needs **AED 33 333 333** of revealed quote value — between 134 and 1 334 reveals depending on the average
quote, which is **unmeasured** because no quote has ever existed. Everything this department can build is
buildable without a language model, and none of it produces a dirham until the supply side moves from
**1 confirmed matchable supplier** to at least **10 per active category**, which is the founder's own
rule 5. That is the sentence the founder should read first.

