# Cost guardrail report

Measured 14 Aug 2026 · blueprint `runtime_blueprint/COST_GOVERNANCE.yaml`.

## The guardrail was dead in the way that mattered, and is not now

The brief said `department_budget.spent_aed` is never incremented, "so the halt compares against a
number no path increments and can never fire". Re-measured, that was half right, and the wrong half
mattered: `fn_ai_route` — the enforcing path inside `ai_gateway` — never read `spent_aed`. It sums
`ai_cost_log` live and always could fire. **It was looking at a third of the money.**

| | staging before | production before |
|---|---|---|
| month-to-date AI spend | AED 106.17 | AED 187.04 |
| visible to any ceiling | AED 38.42 (36%) | AED 148.56 (79%) |
| carrying no `dept_key` | AED 29.87 | AED 2.70 |
| under a department key the merge deleted | AED 37.87 (22 keys) | AED 35.78 |

Two causes, neither of them "the counter is not incremented":

1. **Exact-match scoping breaks on merge.** Both ceiling readers matched `dept_key = <canonical>`,
   so every row logged under one of the 22 absorbed keys fell outside every ceiling. The read is now
   scoped through `fn_dept_scope`. No cost row was rewritten.
2. **A sibling path that never got the lexicon.** `fn_ai_route` attributes an un-departmented call
   from `fn_task_class.dept_key`; `trg_ai_cost_attribute`, which fills `dept_key` on the way *into*
   `ai_cost_log`, read three *other* tables and not that one.

`fn_budget_available` *did* read the dead column, and `fn_check_spend` authorises business spend
through it — so every department looked untouched. It now computes live over the same scope.

**Proved by execution**, in an aborted transaction: after burning 96% of `growth`'s budget,
`fn_ai_route` returned `use_llm=false`, *"HALTED. growth is at 98.06% of its monthly AI budget"*.

## Current position, production

| | AED |
|---|---|
| total monthly budget across 10 departments | 1,810.00 |
| month-to-date spent | 184.35 (10.2%) |

## Is the ceiling *impossible* to exceed?

The completion standard asks for proof, so here is the honest boundary of what is proven.

**Two independent enforcement points, both measured:**

1. `fn_ai_route` returns `use_llm=false` at `halt_at_pct`, and `ai_gateway` refuses on that. Proven
   to fire.
2. `scripts/checks/runtime_connection_gate_b.mjs` re-reads `ai_cost_log` before every call and
   refuses the next one at the ceiling. It **refuses to start** if the ledger cannot be read, because
   a cap that cannot be measured is not a cap. Gate B spent AED 2.19 against an AED 11.02 (USD 3)
   ceiling.

**What is NOT proven, stated plainly:**

- The halt is evaluated **per call, before the call**. A single call whose own cost carries a
  department past the ceiling is not prevented — it is the call after it that stops. The overshoot is
  bounded by one call's cost, not by zero.
- Departments are enforced independently. There is no company-wide hard ceiling; `fn_ai_spend_guard`
  raises a company-level SPIKE incident but does not halt.
- A call logged with no `dept_key` still cannot be halted. That share is now small (production AED
  2.70 of 187) and the attribution trigger closed the largest source, but it is not zero.
- The blueprint asks for a **dedicated OpenRouter key** for test runs, separate from the founder's
  general key. There is one key (`app_secrets.openrouter_api_key`). **`MISSING_BUILD` — and it needs
  the founder**, because minting a second key is an account action, not a code change.

## Cost of this session's testing

| | |
|---|---|
| Gate A (deterministic) | AED 0.00 — no model call |
| Gate B first run (30 cases) | AED 2.19 |
| Gate B re-run after the truncation fix | see `runtime_connection_test_evidence.md` |
| 69-scenario role smoke | AED 2.02 |

## The routing change that reduces the bill

`org_reorg_20` wired `org_agents.routing_tier` into `fn_ai_route`. Before it, every employee from a
marketing copywriter to the CEO routed to `anthropic/claude-sonnet-5`, because the branch that
applies the pack's four-role taxonomy only fired when the calling function was *unmapped* and
`agent_brain` is mapped. 23 operations specialists now route to `google/gemini-3.5-flash` at the
medium tier. Measured directly: 60 routed calls cost AED 2.19 in the Gate B window. Reviewers,
directors and analyst-controllers deliberately stay on the large tier.
