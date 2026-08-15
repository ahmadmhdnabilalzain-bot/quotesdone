# Phase C — Zero-Cost Test Evidence

Every gate in `PHASE_C_ZERO_COST_TEST_PLAN.md`, with the command that produced the result.
Measured on `htdblwldjkcgjvmqkbeh`, 15 Aug 2026.

## The headline

```text
OpenRouter requests:            0
Other paid inference requests:  0
Paid inference cost:            USD 0.00  (AED 0.00)
Provider routes opened:         0
```

Measured from `public.llm_route_health.open_until` and `public.ai_cost_log.occurred_at` — **not**
inferred from a caught query error, which the test plan explicitly forbids.

| | |
| --- | --- |
| provider routes registered | 8 |
| routes held open-circuit | **8 of 8** |
| held until | 2126-08-15 02:51:36 UTC |
| last paid AI call anywhere in the estate | 2026-08-15 **02:51:33** UTC |
| paid inference calls during Phase C | **0** |
| paid inference cost during Phase C | **0** |

The last paid call predates the first Phase C write. The hold was never released and was never
asked about.

## Gate C0 — Baseline

```bash
node scripts/phase_c/validate_package.mjs
```

- 52/52 package files verified against `SHA256SUMS.txt`.
- All 17 declared counts exact: 90 roles · 86 overlays · 30 workflows · 257 steps · 161 handoffs ·
  347 events · 32 gates · 54 rules · 26 authority classes · 35 intents · 20 acceptance cases ·
  13+24 command states/transitions · 11+22 task states/transitions · 10 system actors ·
  11 trace policies.
- Live: 10 departments, 90 canonical roles, 86 overlays.
- `fn_phase_a_baseline_drift()` = **0 rows**; `fn_phase_b_baseline_drift()` = **0 rows**;
  `fn_phase_b_effective_errata()` — all three resolved; `fn_phase_a_organization_violations()` = 0.
- Tags: `phase-a-founder-approved-2026-08-15` → `00f1f47`,
  `phase-b-founder-approved-2026-08-15` → `763e318`.
- Production ref exact: `htdblwldjkcgjvmqkbeh`.

## Gate C1 — Component inventory

```bash
node scripts/phase_c/inventory.mjs && node scripts/phase_c/build_crosswalk.mjs
```

**1,799 components.** 0 unclassified. 0 active state-changing without an accountable role, a
system actor or a scope. 0 generic owners.

Coverage: routed frontend actions (24), API actions, edge functions (202), database
functions/procedures (1,000), triggers (189), cron jobs (205), event subscriptions (60),
outbox consumers, webhooks, state tables (100), agent/task/workflow runners (19).

## Gate C2 — Identity and ownership

```bash
node scripts/checks/phase_c_guards_reject_injected_defects.test.mjs
```

Canonical, legacy, merged, packaged-role and title resolution all tested.
Refused: unknown identity, inactive role, overlay as task owner, generic name, unresolved alias as
reviewer. New writes use canonical ids only, enforced by trigger.

## Gate C3 — Frozen workflow binding

| required | measured |
| --- | --- |
| 30/30 workflow bindings | **30** |
| 257/257 step bindings or explicit `DEFERRED_RUNTIME_IMPLEMENTATION` | **257** (120 connected, 137 deferred) |
| 161/161 handoff bindings | **161** |
| 347/347 event classifications | **347** |
| 32/32 gate classifications | **32** |
| 54/54 rule classifications | **54** |
| 90/90 role bindings | **90** |
| 86/86 overlay bindings | **86** |

Every deferral carries an owner, a safe entry boundary and the exact missing implementation — a
CHECK constraint refuses one that does not.

## Gate C4 — Founder command center

```bash
node scripts/checks/phase_c_command_acceptance.test.mjs      # 20/20
node scripts/checks/phase_c_command_center_entry_point.test.mjs
```

**20/20 acceptance cases pass**, each inside a transaction that always rolls back.
`leftover after 20 aborted probes: {"msgs":0,"cmds":0,"tasks":0,"appr":0}`

Asserted per case: founder authentication · immutable raw message · safe intent **or** clarification ·
exact workflow and role · atomic command/task creation · task ids returned immediately ·
status/cancel/reprioritize/explain · multi-department plan · refund approval semantics ·
**no founder approval for any non-refund action** · no raw side effect · non-null traces.

## Gate C5 — Authority and reviewer independence

Injected and refused, all without state change: unknown action class · self-review · self-review
through an alias · non-refund founder approval · a second founder-approval action class ·
founder-initiated-only committed autonomously · refund authorised by an employee · refund decided
by someone other than the founder · refund executed against a rejected decision · refund whose
executor is also its reconciler · wrong employee advancing a frozen step · overlay owning a step
outside its declared scope.

## Gate C6 — Trace coverage

Eleven trace-required populations, each with its own denominator. On the Phase C fixtures:

| | |
| --- | --- |
| completed commands without trace | **0** |
| closed tasks without trace | **0** |
| completed step runs without trace | **0** |
| handoff runs without trace | **0** |

One of these was 4 before the cancellation defect was fixed. See
`PHASE_C_TRACE_COVERAGE_REPORT.md`.

## Gate C7 — Events, handoffs, idempotency

Duplicate, delayed, out-of-order, rejected and retried messages all tested.

- duplicate command → **same command id**, 1 message row
- duplicate workflow start → **same run id**, 1 run
- duplicate event emit → **same outbox id**
- retry → new step run, `first_preserved=true`, 2 rows
- delivery `ok` with no downstream record → **`retry_wait`**, not delivered
- rejected handoff without a reason → refused
- handoff that flips ownership before acceptance → refused
- dead letter visible after 5 attempts

## Gate C8 — Output validation

Valid, malformed, incomplete and truncated fixtures. Invalid output **cannot mutate state** —
`fn_phase_c_step_advance` returns `failed_incomplete` before writing the step run. Eight fixtures,
all refused, listed in `PHASE_C_IDEMPOTENCY_OUTPUT_REPORT.md`.

## Gate C9 — Provider block and cost

Stated at the top of this document. Additionally:

- No file in `scripts/phase_c/` or `scripts/sql/phase_c_*` contains a provider endpoint, an API
  key, or a call to `_shared/llm.ts`.
- Command interpretation is a **table** (`phase_c_command_rule`, 27 ordered rules) plus six
  registered specificity patterns. No model is consulted at any point on the command path.
- `fn_phase_c_knowledge_scope` returns `retrieval_performed: false` in its payload; it resolves
  scope and does not retrieve.
- `fn_phase_c_role_context` returns `paid_model_route: "DISABLED_PHASE_C"`.
- V3 certification questions and answer keys were not read. They are in the exclusion list of
  every knowledge-scope response.

## Gate C10 — Production rehearsal and deploy

```bash
node scripts/phase_c/rehearse.mjs
```

```text
pre-rehearsal  digest: 17c3757a6db4143a09d2fff03e7973df78e901316235e0bce57d9a9ea0ba3e2f
REHEARSAL components=1799 roles=90 overlays=86 steps=257 handoffs=161 events=347
          gates=32 rules=54 action_classes=26 command_rules=27 invariants=58/58 FAILED=[none]
post-rehearsal digest: 17c3757a6db4143a09d2fff03e7973df78e901316235e0bce57d9a9ea0ba3e2f
production fingerprint unchanged across the abort.
REHEARSAL PASSED
```

1,842 KB of the exact committed bytes, sent as one implicit transaction with a trailing `raise`
that reads the post-change counts first. The script refuses to report success if the migration
does not raise — a rehearsal that committed is not a rehearsal.

- deployed source hashes match git: **202/202** functions (4 unverifiable by signature — see the
  deployment report).
- all Phase A, Phase B and Phase C invariants pass after deployment.
- **no activation state changed**: cron jobs 205, active 186, before and after.
- **no persistent test fixtures remain**: `founder_command` 0, `founder_command_message` 0,
  `phase_c_task` 0, `founder_approval_request` 0, `phase_c_workflow_run` 0, `phase_c_trace` 0.

## The tally

| suite | result |
| --- | --- |
| package validation | 52/52 checksums, 17/17 counts |
| command routing acceptance | **20/20** |
| injected defects refused | **55/55** |
| Phase C invariants on production | **58/58** |
| command centre entry point | verified |
| repo SQL ↔ live routine definitions | 408/408 identical, 0 missing, 0 drifted |
| schema export ↔ git mirror | byte-identical |
| edge function deploy parity | 202/202 live |
| `fn_os_portals_gates()` | 23/23 met |

## What a green suite here does not claim

- It does not claim the 137 deferred steps do their business work. They have an owner and a safe
  boundary; the handler is Phase D.
- It does not claim the 12 runtime workflows with zero runs work. They are owned and bound; nothing
  has executed them.
- It does not claim professional judgement quality, and it does not claim launch readiness. Both
  are explicitly out of scope.
