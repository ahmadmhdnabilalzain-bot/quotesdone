# Stage 0 — chain-of-command scan, first pass

**Read-only on production `htdblwldjkcgjvmqkbeh`, 27 August 2026. Zero cost, under every hold.**
This is the measurement Stage 0 of `LAUNCH_READINESS_PLAN.md` calls for. It is a first pass — the
core integrity checks, the founder boundary, and the autonomy gate. The remaining Stage 0 items are
listed at the bottom.

## The headline: the autonomy tier the founder's vision needs does not exist

The founder's rule is: the company runs itself, the only human approval is refunds, and every other
approval terminates at an AI department head or officer — no agent, not even the CEO, waits on the
founder for anything else.

The autonomous dispatcher `fn_action_invoke_dispatch` **refuses** an action if any of these hold:

```
not active
OR required_authority = 'founder'
OR (not reversible AND no compensation_action_class)
OR (notifies_human AND not unattended_ok)
OR NOT (risk_tier = 'low' AND advisory_safe AND reversible)
```

So the only things that run autonomously today are **low-risk, advisory-safe, reversible** actions.
Everything consequential — medium/high risk, irreversible, or human-notifying — is refused. And it is
refused to *nothing*: there is no "an AI head approves it, then it runs" path in the dispatcher. The
code collapses "needs approval" straight into "a human must be involved."

That is the gap. The founder's vision requires a **middle tier** that the dispatcher does not have:

> consequential action → **approved by an AI department head or officer** → executes autonomously

Without that tier, a self-running company can only ever do trivial, reversible things on its own;
anything that actually moves the business (send a quote reveal, verify a supplier, chase a payment,
send outreach) cannot complete autonomously. This is the single most important thing to build for the
vision, and it is not a bug in an existing mechanism — it is a mechanism that was never built.

## What is already correct (confirmed by measurement)

- **The founder gate is refund-only, at the authority level.** `required_authority = 'founder'`
  appears on **exactly one** of 56 action classes: `refund_within_window`. That matches the founder's
  rule precisely — refunds, and nothing else, require him.
- Every one of 184 workflow steps carries an `actor_role` (0 blank).
- Every active agent's manager resolves to an active agent (0 dangling, 0 self-managed).
- The CEO is the one agent with no manager — correct, the apex reports to the founder.

## Defects found

| # | defect | measured | severity |
|---|---|---|---|
| 1 | **No AI-managerial approval tier** — dispatcher refuses all consequential actions instead of routing them to an AI head for approval | see headline | **blocker for the vision** |
| 2 | **182 self-approvals** — an agent approved work it authored: dept_review 112, cos_review 35, published 35 | `review_chain where author_agent = reviewer_agent`, all ≤ 2026-08-14 | high — independent review bypassed |
| 3 | **2 stale authority grants** held by agents no longer active | `gov_relations_mgr / analysis`, `marketing_copy / content_draft` | low — authority held by ghosts |

Defect 2 needs one more measurement before it is a build: whether the *current* reviewer-picker still
selects the author, or whether these 182 rows are legacy from before a prior fix. The recurring
history of this defect (a picker returning a department's own designer; a review defaulting to the
author) says treat it as live until proven otherwise.

## Remaining Stage 0 items (next)

- Conflicting authorities: two roles both claiming one decision.
- Escalation termination for the non-refund cases: every escalation must land on an accountable AI
  head/officer and never on the founder.
- `actor_role` → live staffed role resolution (confirmed non-blank; not yet confirmed each resolves to
  a staffed, correctly-ranked role).
- The 12-of-19 never-run runtime workflows: wiring gap or legitimate.
- Notification volume: would `notifies_human` on 10 action classes flood the founder's inbox during a
  year-long absence, drowning the one real major-issue signal?
