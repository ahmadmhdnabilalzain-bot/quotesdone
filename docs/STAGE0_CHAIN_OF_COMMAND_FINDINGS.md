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

---

## Second pass — 28 August 2026 (read-only + two fixes, zero cost, under every hold)

### Defect 2 (182 self-approvals) — CLOSED, mechanism proven fixed

The reviewer picker `fn_pick_reviewer(dept, author)` was fixed on 14 Aug 2026: it resolves the author
via `fn_org_agent_resolve` and excludes the author in every branch (independent reviewer → manager →
escalate), and **never returns the author**. Proven by measurement:

- Called for all 31 department heads as author: **0 self-reviews** (each returns an independent
  reviewer or escalates).
- A **write-time guard** `a00_review_chain_no_self_review` (BEFORE INSERT/UPDATE) resolves BOTH sides
  via alias, raises `check_violation` on equality, and canonicalizes both sides on write. **Forced to
  fire** in an aborted probe: author `cfo` + reviewer `finance_ai` (an alias of `cfo`) → guard fired,
  rejected, rolled back. So no path can record a self-approval, and the recurring alias root cause is
  closed at write time.
- Newest self-approval row: **2026-08-14 02:51 UTC**; none since. The 285 legacy rows (182 approvals)
  are historical record of reviews that happened, not live authority — correctly left untouched (never
  back-date or mass-close data).

### Defect 3 (2 stale authority grants) — FIXED and verified

`employee_authority` held two grants keyed to inactive/superseded agents:
`gov_relations_mgr/analysis` (→ resolves to active `partnerships_mgr`) and
`marketing_copy/content_draft autonomous` (→ resolves to active `marketing_content`). Every authority
consumer canonicalizes the agent key via `fn_org_agent_resolve` BEFORE matching `employee_authority`
raw (verified in `fn_check_spend`), so the ghost rows were already **unreachable**. Deleted them
(migration `scripts/sql/stage0_remove_two_stale_authority_grants.sql`); verified **0 ghost rows, 0
grants held by any missing/inactive agent**. Not re-keyed on purpose — re-keying would silently
elevate `marketing_content` content_draft from advisory→autonomous, which is an authority change, not
a cleanup.

### Remaining items — measured

- **Escalation termination:** only `ceo.escalation_targets = ['founder']` points at the founder; every
  other role escalates internally. That single edge is the founder's own described major-issue email
  signal (escalation of a genuine major issue), **not** a blocking approval gate — and approvals remain
  refund-only (`required_authority='founder'` on exactly `refund_within_window`). Aligned with the vision.
- **Conflicting authorities:** the only genuine cross-role overlap in `owned_decisions` is
  **"dispute handling path"**, owned by BOTH `payments_and_billing_manager` (finance/payments) and
  `trust_and_safety_manager` (legal). Candidate conflict — needs scope disambiguation (payment-dispute
  vs abuse-dispute) OR a single owner. The 10 decision-labels shared by all 86 category overlays
  (pricing drivers, required documents, escalation rules, …) are **category-scoped by design** — each
  overlay owns the decision for its own category — and are NOT conflicts.
- **actor_role staffing:** `public.workflow_step` — 184 steps, **0 blank**, 96 distinct actor_roles.
  All resolve to a canonical/active role EXCEPT a generic `owner` (15 steps) and `Director` (1 step),
  **all 16 in the single `employee_task` template workflow**, where the actor is the task's owner bound
  at runtime — a generic template pattern, not a mis-wired manager. Confirm runtime binding before any
  change; do not hard-assign a fixed role blindly.

### Stage 0 status after this pass

| defect | status |
|---|---|
| 1 — No AI-managerial approval tier | **BUILT + proven (28 Aug 2026).** See below. |
| 2 — 182 self-approvals | **CLOSED** (mechanism + write-time guard proven; legacy rows are history) |
| 3 — 2 stale authority grants | **FIXED + verified** |

New, low-severity, for Stage 1: (a) the `dispute handling path` dual-ownership; (b) confirm the
`employee_task` template's `owner`/`Director` actors resolve at runtime. Neither is a blocker.

### Defect 1 — the AI-managerial approval tier — BUILT and proven

The dispatcher `fn_action_invoke_dispatch` no longer collapses "needs approval" into "a human must be
involved." A **middle tier** now exists: `consequential action → the accountable AI head/officer
approves → runs autonomously`. Built without touching any frozen object — `fn_action_invoke_dispatch`
is NOT in `phase_c_frozen_subject` (verified: the 23 frozen routines are kernel primitives + refund
guards), and the refund path stays frozen and founder-only.

Mechanism (`scripts/sql/stage1_ai_managerial_approval_tier.sql` + the dispatcher edit in
`scripts/sql/the_queue_that_had_nobody_to_hand_it_to.sql`):

- **`action_approval`** ledger — one row per action_execution (uuid key): `requested` → `approved`/
  `rejected`, single-use (`consumed_at`), RLS on, no anon/authenticated grants.
- **`fn_action_resolve_approver(dept, risk_tier)`** — the entitled approver by risk: medium → the
  department head (execute_medium or stronger); high → an execute_high officer, escalating to the CEO
  when the head lacks the tier.
- **`fn_action_head_approve(action_id, decision, reason, approver)`** — the head's decision, recorded
  with identity and authority basis. Refuses: a founder-reserved (refund) action, an irreversible
  action with no compensation, a non-entitled approver, and self-approval by the action's own author.
- The dispatcher now classifies each queued action three ways: **absolute refuse** (inactive /
  founder-reserved / irreversible-no-comp), **auto-dispatch** (low + advisory_safe + reversible, not
  human-notifying-unattended — unchanged), or **consequential** → route to the entitled head and park
  (`awaiting_head_approval`, still queued) until approved, then dispatch; a rejection refuses it.

Proven by two aborted-transaction probes (nothing committed, `net.http_request_queue` rolled back to
0, zero live effect):

- **Probe A:** a `supplier_verify` action (marketplace, medium, reversible) → first sweep
  `awaiting_approval=1`, parked with `procurement` as the entitled approver; a wrong approver (`cfo`)
  refused; `procurement` approved; second sweep **dispatched=1**.
- **Probe B:** `refund_within_window` → refused `reserved to the founder` and unapprovable by the CEO;
  `collections_chase` (irreversible-no-comp) → refused and unapprovable; a head rejection → the action
  is refused on the next sweep.

Safe under the holds: all three `action_invoke_*` crons are INACTIVE, and a consequential action only
dispatches after a head calls `fn_action_head_approve` — which nothing does autonomously while
automation is stood down. Phase A/B/C freeze drift 0 after the change; Phase D input schemas 8/8.

v1 limits (for a later pass, not blockers): independence forbids self-approval only when the author is
recorded on the action request; a consequential action that fails and retries re-seeks approval
(conservative); high-risk approvable executors are currently all irreversible-no-comp and therefore
still refused — when a reversible high-risk executor appears, the CEO-officer route already handles it.
