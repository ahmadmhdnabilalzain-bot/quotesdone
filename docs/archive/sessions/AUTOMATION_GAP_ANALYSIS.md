# What is actually missing before QuotesDone runs itself

Measured on production `htdblwldjkcgjvmqkbeh`, 10 Aug 2026, 09:00–12:00 UTC. Every number here is a
query, not an estimate. Nothing in this document is a plan to write a plan.

---

## 1. WHY THE DASHBOARD LOOKS BASIC — AND IT IS NOT THE UI

The founder opened the OS on 10 Aug and said it *"looks extremely basic still. Definitely not what
I was expecting."* That judgement is correct and the cause is not the front end.

The OS shell defines **31 modules** and **every one has a purpose-built component** — `RfqApp`,
`SuppliersApp`, `CustomersApp`, `FinanceApp`, `AgentsApp`, `GovernanceApp` and so on, with a
floating-window layer, not a generic table renderer. Structurally it is not thin.

What is behind those modules on production:

| screen | rows |
|---|---|
| **RFQs & Procurement** (`inquiries`) | **0** |
| **Quotes** | **0** |
| Customers | 10 |
| Documents | 8 |
| Governance (`decision_record`) | 11 |
| Suppliers / Leads (`leads`) | **20,470** |
| Smart Engine (`agent_runs`) | 18,723 |
| Escalations (`agent_actions`) | 2,353 |
| Company memory (`org_memory`) | 407 |
| Company events | 849 |

**The marketplace has never run a single transaction.** Zero inquiries, zero quotes. Roughly a
third of the modules are organised around a pipeline that has never carried anything, so they
render correctly and render nothing.

**But the expectation is still right, and this is the real design gap.** The company IS working —
18,723 agent runs, 20,470 leads, 849 events, 785 tasks — and almost none of that is what the OS
leads with. The founder opens a CRM for a business with no customers instead of a control room for
a workforce that ran 18,723 times. The fix is not more panels; it is that **the home screen should
show the company that exists**, not the one the pipeline model assumes.

---

## 2. THE COMPANY CAN DECIDE. IT LARGELY CANNOT ACT.

This is the single biggest blocker to full autonomy and it is one number:

```
org_action_executor            55   action types registered
org_action_executor_rpc_allowed 16  action types that can actually execute
```

**39 of 55 registered actions have no executable path.** An employee reaches a conclusion, and for
39 kinds of conclusion the only thing it can do is write a row asking a human.

That queue, measured now:

```
agent_actions status='needs_review'      208      oldest 9 July 2026
  of which kind='handoff'                 84      (85 yesterday — the inbox IS keeping pace)
  everything else                        124      across 21 OTHER kinds
```

The 124, by kind:

```
improvement_question 23 · knowledge_task 23 · report_recommendation 12 · customer_escalation 10
incident 10 · strategy_rec 8 · objective_step 6 · legal_flag 6 · marketing_recommendation 4
ai_improvement 4 · security_incident 3 · doc_task 2 · autonomy_stall 2 · report_task 2
prompt_approval 2 · ops_recommendation 2 · finance_marketing_budget 1 · compliance_update 1
finance_alert 1 · supply_health 1 · decision.route_category 1
```

**The handoff inbox shipped yesterday solved exactly one of 22 kinds.** It works — handoffs are flat
at 84 while new ones keep arriving. The other 21 kinds have **no consumer of any sort**. Every one
is the company saying "a human must decide this", addressed to a founder whose only channel is the
dashboard he finds basic.

**This is the build.** Not one more panel: a consumer per kind, or an executor per kind, so that
`needs_review` means "genuinely needs Ahmad" rather than "nobody wrote the other half".

### UPDATE, same day — half of this is now done, and the other half is specified

**Done:** the inbox no longer filters `kind='handoff'`. It shows every kind addressed to an
employee, marks the founder's items *"FOUNDER DECIDES — do not close"*, and `fn_handoff_answer`
closes only the company's own internal work via `fn_agent_inbox_closable_kinds()`. Of the 92 items
held by employees that run, **89 are now reachable and 3 correctly are not.** Eleven employees have
a non-empty inbox where six did. The whole line is bounded at 215 characters so the block is 647
and cannot drift back into the `agent_brain` timeout.

**Specified, not built — and deliberately so.** The 39 action classes that cannot execute are not
broken rows. Their `target` is an **edge function** — `quote_compare`, `uptime_check`, `match`,
`knowledge_exam`, `ai_health`, `send_outbox` — not a database routine, which is why
`fn_execution_run` cannot call them: it does not invoke anything. It writes an `agent_actions` row
addressed to an employee, so "execution" today means "tell a person".

What is missing is one HTTP invoker, and `org_action_executor` was **already designed for it**:
`idempotency_strategy`, `timeout_seconds`, `max_attempts`, `backoff`, `required_authority` and
`compensation_action_class` are all columns on that table and **nothing implements a single one of
them**.

It was not built at the end of this session on purpose. The same list contains
`outreach_send` (high risk, **not reversible**), `pdpl_action` (high, not reversible),
`collections_chase` (not reversible) and `refund_within_window` — and a refund is the one action
the founder has reserved to himself. A generic invoker built without room to watch it is how a
session hands AI employees the ability to email strangers and move money on the same afternoon.

**Build it in this order:** the 28 that are `advisory_safe = true, reversible = true,
risk_tier = low` first, one at a time, each proved by execution; then the medium tier; and
`outreach_send`, `pdpl_action`, `collections_chase` and `refund_within_window` last, or never
without an explicit decision each.

---

## 3. THE WORKFORCE STILL DOES NOT WORK

```
active employees                    66
distinct agents that ran in 30 days  6 of 66 reach agent_brain
gated authorities                   34 rows / 14 employees, none on probation
open org_tasks                     487
```

Nothing here is new and nothing here is fixed. The evolution scan raised it itself at 06:00 on
10 Aug: 44 of 66 employees dormant, four departments holding ≥5 open tasks with nobody running
them, 13 departments with two or more wholly dormant employees.

**The 34 gated authorities are residue from a scoring bug that has since been fixed** — `health_report`
gated for 2 employees while autonomous for 7, `uptime_verify` 2/6, `forecast` 2/4. `fn_reputation_recompute`
can take an authority away and **there is no statement anywhere that gives one back**. Two of the
affected classes are `money_verify` and `invoice_review`.

Previously this was parked as a founder escalation. It is not one any more — the only thing needing
approval is a refund. **Restoring these, and writing the missing restore path, is a session's job.**

---

## 4. WHAT PREVIOUS BUILDS LEFT BEHIND

| left behind | state today |
|---|---|
| **`quote_compare` had no model-free path** | **FIXED today.** Every model attempt failing used to show the customer nothing at HTTP 200. Now serves a deterministic ranking, proved on staging against four real quotes with the model forced to fail |
| **The 22 pack task classes were inserted inactive** | **FIXED today.** 59 of 60 policies active on both projects, mapped onto models production actually serves |
| **`department.conflict` has no detector** | Still none. `fn_decision_conflict_scan` finds one actor reaching two verdicts, which is not two departments disagreeing. Wiring it would be mislabelling |
| **`customer.churn_signal`, `customer.complaint`** | Still no emitter — genuinely blocked on customers using the product |
| **`s24` board review before major decisions** | Still one guarded `perform fn_board_review(...)` inside `fn_decide`. Cannot flip before ~9 Sept either way |
| **21 of 22 `needs_review` kinds have no consumer** | Untouched — section 2 |
| **`fn_reputation_recompute` has no restore path** | Untouched — section 3 |
| **Production carries 3,325 redundant `kb_stage.decision_rules` keys** | Same rules stored twice under two keys; staging is the clean projection. Nothing reads either yet |
| **`visitor_chat` has no model policy** | The ONE purpose in `llm_calls` over 30 days, and it falls back to `general_drafting`. The only live AI path in the company is the one nobody routed |

---

## 5. WHAT FULL AUTONOMY NEEDS, IN THE ORDER IT SHOULD BE BUILT

1. **An executor or a consumer for each of the 21 orphaned `needs_review` kinds.** Biggest single
   lever. Until this exists the company escalates what it should execute, and the queue only grows.
2. **A restore path in `fn_reputation_recompute`,** plus restoring the 34 gated authorities. The
   company can currently only ever become less autonomous over time.
3. **Wake the 60 dormant employees or retire them.** Four Row #3 checks, 43 stranded handoffs and
   every per-employee measurement depend on this one decision, and the estate has already asked for
   it in writing.
4. **A home screen showing the company that exists** — runs, events, tasks, leads, decisions —
   rather than an empty transaction pipeline. Section 1.
5. **The WhatsApp command channel.** The founder's stated primary surface: he texts from his
   registered number, anything he asks gets done and answered. Explicitly deferred by him on
   10 Aug, recorded so it is not lost.
6. **Founder auth simplified** — mobile number, verification, in. No mode he must enter to see his
   own company. Control Mode's 90 registered actions should keep gating *writes*; nothing should
   gate *reading*.
7. **A model policy for `visitor_chat`,** the only live AI caller in the company.

---

## 6. THE MONEY, WHICH IS NOT MINE TO SPEND

```
OpenRouter   $16.88  09 Aug 05:00
             $12.91  10 Aug 05:00
             $11.87  10 Aug 07:00     ~$4.62/day  ->  roughly 2.5 days
```

`agent_brain` is ~93% of it. As of today, the one customer-facing path that used to break when the
balance hits zero — quote comparison — no longer does. The rest of the estate still stops.
