# Phase C — refund-only founder approval (gate 10) and creator/reviewer separation (gate 11)

Every result below comes from forcing the guard to fire inside an aborted transaction. A guard that has never
been made to refuse anything is indistinguishable from a guard that is dead, so each one was given the exact
input it is supposed to reject, and then the input it is supposed to accept.

---

## GATE 10 — the four required facts

### 10.1 Non-refund founder approval requests = 0 — and cannot be created

Population today: `select count(*) from public.founder_approval_request` = **0**. Zero on an empty table proves
nothing, so the boundary was attacked directly.

Attempt: insert `action_class = 'marketing_publish'`.

```
23514  founder_approval_request: marketing_publish is not a founder-approval action class.
       The founder is not the company's approval queue; only a specific refund decision reaches him.
```

Refused by trigger `fn_founder_approval_refund_only()` **and** by CHECK constraint
`founder_approval_request_refund_only_ck: CHECK (action_class = 'refund_decision')`. Two independent layers.

An earlier attempt using `action_class = 'refund'` was also refused — the only accepted value is the exact token
`refund_decision`. **PASS.**

### 10.2 Refund execution without a founder decision = refused

A pending `refund_decision` request was created, then a refund decision was written against it by
`finance_operations_manager`:

```
28000  phase_c_refund_decision: finance_operations_manager is not the registered founder identity;
       the command secretary cannot approve a refund
```

**PASS.** The guard also refuses the literal string `'founder'` — it demands the registered identity from
`public.phase_c_founder_identity`, not a role name.

The accepting path was then proved so that this is not a guard that refuses everything: with the request
approved and `decided_by = 'management@quotesdone.com'`, the insert was **ACCEPTED**. The guard discriminates.

### 10.3 A founder-issued policy command does not require a second approval

Command 222 (`PHASE_C_FOUNDER_COMMAND_CANARY.md`) returned `founder_approval_required: false` and created
**zero** `founder_approval_request` rows while creating four real tasks. The founder's own instruction is not
put back in front of him. **PASS.**

### 10.4 Payment executor and reconciler are separate identities

Attempt: `executor_role_id = reconciler_role_id = 'payments_operations'`.

Refused. `phase_c_refund_decision_ck` is
`CHECK ((decision = ANY (ARRAY['approved','rejected'])) AND (executor_role_id <> reconciler_role_id))` — the
separation is a column-level constraint, not a convention. The accepted path used
`executor payments_operations` / `reconciler finance_controller`. **PASS.**

### One honest note on the invariants

`fn_phase_c_invariants()` reports `refund_executions_without_founder_decision = 0` and
`refund_executor_equals_reconciler = 0`. Both are computed over `public.phase_c_refund_decision`, which holds
**0 rows**. Those two greens are vacuous as reported; the probes above are what actually establishes the
behaviour, and they establish it.

**GATE 10: PASS.**

---

## GATE 11 — creator/reviewer separation for every required review class

| Measure | Result |
|---|---|
| `fn_phase_c_reviewer_independent('marketing_director','marketing_director')` | **false** — self-review refused |
| `fn_phase_c_reviewer_independent('marketing_director','quality_and_release_director')` | **true** |
| Step bindings where reviewer = accountable owner | **0** of 257 |
| Step bindings that declare an independent reviewer | **28** |
| `step_bindings_with_self_review` invariant | 0, over a non-empty population of 28 |
| GATE-004 "Creator-reviewer separation, hard" evaluated in the live step run | present and satisfied (step run 34, W05-S01) |

The check is non-vacuous: 28 bindings carry a reviewer, the function returns `false` for a collision, and the
gate is one of the twelve actually evaluated when a step advances.

Boundary, stated plainly: `creator_reviewer_collisions` — the *task*-level invariant — is computed over
`phase_c_task where reviewer_required`, and **no task in the table has `reviewer_required = true`**. That
particular green is vacuous. The step-binding evidence and the function's own behaviour are not.

**GATE 11: PASS**, on the step-binding population and the function's measured behaviour.
