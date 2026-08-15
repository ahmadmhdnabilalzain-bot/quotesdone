# Phase C — Founder Command Center

**The founder gives an order. The Chief of Staff turns it into a plan and real tasks owned by
exact canonical employees, in one transaction, before the API answers.**

Measured on `htdblwldjkcgjvmqkbeh`, 15 Aug 2026.

## What the founder clicks

The existing OS is the Command Center; no competing console was built. `os_api` gained four
actions, and they are registered in **both** gates in the same change — `ACTION_CLASS` inside the
edge function and `public.control_mode_action` in the database. An action present in one and absent
from the other is what made read-only screens demand a phone code once already.

| action | class | what it does |
| --- | --- | --- |
| `founder_command` | mutating | submit an instruction; returns command id, plan, task ids, owners, priority, due date |
| `founder_command_control` | mutating | cancel, reprioritise, supersede, explain |
| `founder_command_status` | read-only | one command, its plan, its tasks, their owners and blockers |
| `founder_command_inbox` | read-only | recent commands, what is open, what is blocked, what needs his refund decision |

`os_api` v59 is deployed and its bundle matches the repository.

The UI label may be **Founder Command Secretary — Chief of Staff**. No 91st role was created:
`command_owner_role_id` is constrained to the literal `chief_of_staff`, and the constraint is
validated.

## The interpretation is deterministic, and it is data

There is no model call anywhere on this path. Classification is a table:

```sql
select rule_id, rule_order, pattern, intent_id, outcome, workflow_ids, primary_role_id
from public.phase_c_command_rule order by rule_order;
```

**27 ordered rules.** First match wins; `rule_order` is unique so a tie is impossible. Reading the
table tells you exactly what any sentence will do, without reading a function body.

Ordering is part of the design, not an accident:

1. **Refusals first** (CR-010). An unscoped destructive or financial instruction is refused
   *before* anything tries to route it. "Refund every customer immediately" never reaches a router.
2. **Control commands** (CR-020…023) — status, cancel, reprioritise, explain.
3. **Refund approval** (CR-030) — the one routine founder decision.
4. **Founder-reserved matters** (CR-040…042) — reveal fee, department creation, country research.
   These produce a founder-initiated workflow, never an approval queue.
5. **Multi-department** (CR-050, CR-051).
6. **Single-workflow orders** (CR-060…075), most specific first.

### Why "Make marketing better" creates nothing

A rule match is not enough. A command must also carry a **specificity signal** — one of six
registered patterns: a quantity, a deadline, an identifier, a concrete deliverable, a geography or
a named scope.

- *"Add one extra social media post this week…"* matches CR-066 **and** carries `quantity`,
  `deadline`, `deliverable` → routes, creates 4 tasks.
- *"Make marketing better."* matches CR-066 and carries **nothing** → one clarification question,
  **zero tasks**.

That is CC-014, and it is the difference between a router and a guess.

## The atomic guarantee

`fn_founder_command_submit(founder_identity, text, idempotency_key, ctx)` returns successfully only
when all of this is already committed:

- the immutable message row (append-only; a trigger refuses UPDATE and DELETE);
- the command row;
- the interpretation, versioned;
- the workflow links;
- every immediate task, each with a canonical owner, a manager, a department, an authority class,
  an idempotency key and a due date;
- the command plan;
- the event-outbox row;
- the trace.

Proven, not asserted: the entry-point probe reads `status=tasks_created`, `db_tasks=4`,
`returned=4`, `trace=true` — the task count read back **from the database** equals the count in the
response.

**Idempotency.** The same client key returns the *same* command, not a second one. Measured:
`true|1|tasks=3` — same command id, one message row, three tasks. `os_api` derives a key from the
message hash when the caller supplies none, so a double-tap cannot open two commands either.

## The 20 acceptance cases

Every row of `PHASE_C_COMMAND_ROUTING_ACCEPTANCE_CASES.csv`, run against the live routines inside
transactions that always roll back. **20/20 pass. Zero persistent rows.**

| case | routed to | tasks | founder approval |
| --- | --- | --- | --- |
| CC-001 add a social post | CMD-W20 → W20 | 4 | no |
| CC-002 find 20 scaffolding suppliers | CMD-W11 → W11 | 2 + 1 overlay invocation | no |
| CC-003 supplier response rate dropped | CMD-W02 → W02;W19 | 4 | no |
| CC-004 fix the supplier signup error | CMD-W22 → W22;W24 | 6 | no |
| CC-005 90-day cash forecast | CMD-W27 → W27 | 3 | no |
| CC-006 supplier agreement, UAE privacy | CMD-W28 → W28 | 3 | no |
| CC-007 security and quality gate | CMD-W24 → W24;W29 | 4 | no |
| CC-008 Arabic registration on mobile | CMD-W22 → W22;W24 | 6 | no |
| CC-009 approve refund TX-123 | CMD-W17 → W17 | 2 | **yes** |
| CC-010 reject refund TX-124 | CMD-W17 → W17 | 2 | **yes** |
| CC-011 change the reveal fee | CMD-W01 → W01;W27;W28 | 4 | no — founder-initiated |
| CC-012 status of TASK-42 | CMD-STATUS | 0 | no |
| CC-013 cancel CMD-77 | CMD-CANCEL | 0 | no |
| CC-014 make marketing better | **AMBIGUOUS** | **0** | no |
| CC-015 campaign + cleaning suppliers | CMD-MULTI → W03;W11;W20 | 4 | no |
| CC-016 ban supplier 123 for fraud | CMD-W17 → W10;W17 | 3 | no — internal review |
| CC-017 refund every customer | **refused** | **0** | no |
| CC-018 deploy the latest code now | CMD-W24 → W24;W29 | 4 | no — release gate |
| CC-019 create a Procurement department | CMD-W30 → W30 | 3 | no — Phase A change request |
| CC-020 should we enter Saudi Arabia | CMD-W01 → W01;W21;W28 | 4 | no — research only |

Two of these deserve naming.

**CC-016** — "Ban supplier 123 for suspected fraud" does **not** ban anyone. It opens an evidence
review owned by `trust_and_safety_manager` with `fraud_analyst` and `supplier_verification`
contributing. A raw command cannot reach a side-effecting executor; that is the whole point of the
registry sitting between them.

**CC-019** — "Create a separate Procurement department" creates a formal Phase A change request
owned by `organization_designer`. It does not touch `org_departments`. Phase A is frozen and
`z90_phase_a_freeze` would refuse it anyway; the command centre does not try.

## A category overlay is invoked, not assigned

CC-002 names `opcat-004` among its child roles. The first run of the acceptance suite tried to
create a task owned by `category_overlay_004_formwork-and-scaffolding-suppliers`, and the guard
`z10_phase_c_overlay_not_accountable` refused it.

**The guard was right.** An overlay advises and returns to a named canonical owner; it may never
own work or hold dispatch authority. The router now calls `fn_phase_c_overlay_invoke`, records the
result in `founder_command_overlay_invocation`, and traces it under `TRACE-CATEGORY-ADVICE`. The
plan summary names the invocation so it is visible, not silent.

## Control commands

| operation | behaviour |
| --- | --- |
| `status` | command, plan, tasks, owners, blockers, SLA, clarification, trace id |
| `cancel` | refused unless the state model allows it; closes each child task **individually with its own trace** |
| `reprioritize` | P0–P3 only; updates the command and its open tasks |
| `supersede` | links the replacing command; child tasks superseded with a trace each |
| `explain` | the recorded interpretation and every trace, never an invented narrative |

Cancellation originally closed tasks with a bulk `UPDATE`, which bypassed the routine that writes
`TRACE-TASK`. Four tasks closed with no trace and the invariant caught it at 4. Fixed: one task at
a time, one trace each, recording who cancelled it.

## Founder identity

Two registered identities in `public.phase_c_founder_identity`, both measured from
`app_secrets.admin_emails`: `management@quotesdone.com` and
`ahmadalzain1993@admin.quotesdone.com`. Anyone else gets `not_the_founder` and no command row.

## The state model

13 command states, 24 transitions, both loaded from the package and enforced by
`z20_founder_command_state_guard`. A transition outside the model raises and is recorded in
`founder_command_status_history`. Injected and refused: forcing a `tasks_created` command back to
`received`.

## What is live right now

`founder_command` = 0, `founder_command_message` = 0, `phase_c_task` = 0,
`founder_approval_request` = 0.

**Nothing.** Every test above ran inside an aborted transaction. The Command Center is deployed,
reachable and proven, and it is carrying no synthetic work.

## What was not proven

**No live HTTP request was made to `os_api`.** Doing so needs a signed-in admin session for the
founder's own account, and minting one is a credential path this session does not hold. The HTTP
layer is evidenced instead by three things: the deployed bundle contains the dispatch (verified by
`verify_deploy_parity`), both gates classify all four actions (checked in both directions), and the
routines the dispatch calls execute correctly (20 acceptance cases + the end-to-end probe). The
gap between "the routine works and the deployed function calls it" and "a browser click did it" is
real and is stated rather than glossed.
