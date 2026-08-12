# 12 Aug 2026, part 4 — ten workflows, and a counter that inverted itself

Continues parts 1–3. PRs [#261](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/261)–[#270](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/270) merged. Both projects, every change verified by execution.

---

## org_task #1394 is closed: all ten workflows can execute

Ten workflow definitions carried no `action_class` on any step — the operating model written down as workflows nothing could pick up. Classified in six slices, safest first, **0 of 163 step definitions now unclassified**.

| slice | workflow | runs woken |
|---|---|---|
| 1 | `supplier_onboarding` | 7 (backfilled deliberately — tiny and safe) |
| 2 | `rfq_handling` | 0 |
| 3 | `complaint`, `campaign_publishing` | 0 |
| 4 | `supplier_suspension` | 0 |
| 5 | `customer_registration` | **0 — definition only** |
| 6 | `payment`, `refund`, `invoice_approval` | 0 |
| 7 | `employee_task` | **0 — definition only** |

The class decides which of two consumers gets a step: `fn_workflow_step_sweep` queues it to a real executor only when one is low-risk, advisory-safe, reversible and non-notifying; otherwise `fn_workflow_step_claim` hands it to an agent. **A class with no safe executor is not a gap — it routes the step to reasoning instead of automation.** NULL routes it nowhere.

Rules applied throughout, and every one cost something:

- **Anything that speaks to a customer or supplier routes to an agent.** `complaint` steps 3 and 8 got `coordinate` even though `outreach_draft` would have passed the safe test — the steps say *acknowledge* and *tell*, not draft, and classifying them as drafting would quietly change what the step means.
- **`campaign_publishing` step 9, Publish, is doubly held** — `outreach_send` fails the safe test on three attributes at once (high risk, not advisory-safe, *not reversible*, notifies human) *and* the claim function excludes founder-gated steps outright.
- **`supplier_suspension` automates only reading.** There is no blocking executor in the estate, which is the right state; step 7, *apply the block*, gets `coordinate` deliberately rather than a suspension-shaped class, because naming it something that sounds like an automation would invite someone to build one.
- **`employee_task` step 12, Execute, stays manual.** It is a generic instruction to do whatever the task said — it could be anything the company does.
- **Definition-only where waking runs would do harm.** `customer_registration` has 56 parked runs and step 2 sends an OTP against customers that no longer exist; `employee_task` has 986, and its siblings are marked *"the owning task was performed and reviewed as one act"* — it is a shadow of `org_tasks`, and waking it would re-run completed work.

### And the step that refunds a card had no gate at all

`refund` step 8 — *"Execute the refund in Stripe and record refund_stripe_id, refund_amount_aed, refund_confirmed_at"* — carried **`gate = none`**. `invoice_approval` step 8, *Approve payment*, correctly carried `founder`. The single most irreversible step in the estate was the one with no gate on it. Now `gate = founder`, which the claim function excludes outright.

`payment` step 3, *Take payment through Stripe*, is deliberately **not** founder-gated: gating revenue capture would block every sale, and the charge happens in the app's Stripe checkout, not this workflow.

---

## A counter that reported the exact opposite of the truth

`scenario_library` holds 32 named failure scenarios. Not one had ever been checked, because **`fn_scenario_run_all()` has no caller** — the hourly cron runs `fn_ops_scenarios_sweep()`, a different function. Seventh finished-capability-with-no-entry-point this week.

And wiring it up blind would have been worse than leaving it: `fn_scenario_run` was deliberately renamed to return `staffed` instead of `ready` (*"READY beside 'OpenRouter becomes unavailable' reads as 'we are ready for that outage'"*), and the rename never reached the tally, which still counted `ready`/`partial` and swept everything else into `gap`.

```
before:  ready=0  partial=0  gap=32
after:   staffed=32  staffed_unmanaged=0  gap=0
```

A complete inversion on the same data. **Fourth two-vocabularies defect found today**, after `leads.invite_trades` vs `taxonomy_trade`, `action_worker`'s `outcome` vs the extractor's three key names, and `ai_budget_aed` vs a `\y`-anchored regex. Every time: a counter and its source drifted apart, nothing failed, nothing noticed.

`last_run` deliberately untouched — `fn_scenario_run` says *"last_run belongs to a real rehearsal and this is not one."* `s34` stays MISSING, correctly.

---

## The scorer itself was understating

`s23-reallocation-three-classes` reported *"0 of 3 resource classes moved in 62d"*. Production holds twelve `allocation_change` rows and every one is `ai_budget_aed`. `_` is a **word character** in Postgres regex, so `\yai\y` never matched — measured, `'ai_budget_aed' ~* '\yai\y'` is false.

Fixed at the source expression by normalising `-` and `_` to spaces, not by loosening the anchors (dropping them would fire `ai` on `email_budget`). **The verdict moves 0 of 3 → 1 of 3 and stays MISSING** — marketing budget and supplier capacity have genuinely never been reallocated. The point is only that "0" was false. A verdict that understates is the same defect as one that overstates.

---

## Row #3 is 127/152, and much of the residue is time, not code

Three checks are **already fixed and waiting to age into their windows**:

- `explain-knowledge-used` — all 29 uncited decisions are dated 5–6 Aug, nothing newer. Clears **13 Aug**.
- `s24-board-before-major-decisions` — `fn_decide` invokes the board keyed by `subject_ref`; probed live, a new decision draws **7 of 7 advisors**. Fails on one historical row (decision 42, executed 6 Aug before that shipped). Clears **5 Sep**.
- `explain-alternatives-considered` — `decision_log.alternatives` went from 0 to **67 of 67 (100%) on 12 Aug**. The governance surface shows the most recent 15 escalations, which predate the fix. Clears as new escalations arrive.

Others are demand-blocked (`s22` needs customer/rfq/quote/revenue node kinds; `s29` needs external search-term data with Apify paused; `s30` needs churn and CSAT with zero customers) or history-blocked (`what-if-*` — the six stored simulations keep their old shapes, and rewriting a stored result would change an answer the company may have acted on).

`s36-recommendation-seven-fields` is the one genuinely buildable item left: `assumptions`, `alternatives`, `expected impact` and `cost` have **no column at all** on `agent_actions`, across 41 writing routines. Adding them with defaults would satisfy the letter and defeat the spec.

---

## Verified state

```
Row #3        127/152 (full run) · gates 23/23 both · parity IN SYNC · advisors 0 ERROR both
workflows     163 of 163 step definitions classified · refund Stripe step gate=founder
scenarios     32 staffed · 0 gaps · wired to a weekly cron and registered
tasks         137 assigned by hand + cron · 0 over ceiling · employees holding work 5 -> 33
crons         0 undocumented on BOTH projects (backfill_invite_trades registered on staging)
knowledge     trade/regulation/material 732 of 2,090 embedded and climbing · retrievable 56.2%
spend         17.60 AED today · 0 model failures in 3 hours
demand        customers 0 · inquiries 0 · quotes 0 — UNCHANGED
```
