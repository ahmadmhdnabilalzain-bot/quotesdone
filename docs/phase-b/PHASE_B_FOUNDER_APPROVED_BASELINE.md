# Phase B — founder-approved baseline

**Approved by the founder on 15 Aug 2026** as the final QuotesDone business-workflow architecture.
**Tag:** `phase-b-founder-approved-2026-08-15`
**Project:** `htdblwldjkcgjvmqkbeh` (the only project)
**Recorded in:** `public.org_phase_baseline` where `phase = 'B'`

## What the approval covers

Workflow purpose · sequence · ownership · handoffs · inputs and outputs · business states ·
transitions · rules · gates · exceptions · SLAs · founder boundaries.

## What it explicitly does not claim

> It does not claim that the current application runtime already executes all workflows correctly.

The founder said this in the approval, and it is recorded verbatim on the baseline row. The seven
runtime gaps he named are stored in `public.phase_b_phase_c_wiring_gap` as **Phase C work, not
Phase B defects**.

## The approved baseline

| | |
| --- | --- |
| canonical workflows | 30 |
| accountable steps | 257 |
| handoffs | 161 |
| cross-department handoffs | 47 |
| canonical business objects | 56 |
| business rules | 54 |
| gates | 32 |
| exception and escalation patterns | 50 |
| SLA policies | 34 |
| canonical events | 347 |
| workflow states / allowed transitions | 14 / 35 |
| step states / allowed transitions | 11 / 19 |
| founder-reserved boundaries | 10 |
| current-to-target classifications | 719 |
| canonical roles represented | 90 / 90 |
| departments represented | 10 / 10 |
| category overlays governed | 86 / 86 |
| **effective errata resolved** | **3 / 3** |
| **unresolved Phase B errata** | **0** |

## The three errata, resolved in the effective registry

Answerable by query, not by reading this page:

```sql
select * from public.fn_phase_b_effective_errata();
```

| erratum | condition | measured |
| --- | --- | --- |
| EX-006 | complete, and escalation independent of detection | escalation `general_counsel`, detection `compliance_and_privacy_officer`, response present, closure present |
| W13 | primary object references an existing canonical object | `primary_object = notification`, exists |
| W22 | exactly one explicit closure step, it reaches `WORKFLOW_COMPLETE`, and GATE-008 is attached to it | 1 closure step, reaches complete, **GATE-008 → W22-S07** |

W22 needed one more thing than the other two. The closure step was already explicit, but GATE-008
reached it only through `workflow_scope = 'ALL'` — which is scope, not attachment. A gate that
applies to everything and is anchored to nothing cannot be checked. `fn_phase_b_gate_attachment()`
now resolves every gate to the steps it guards and labels each row with **how** it was anchored,
so a derived attachment is never displayed as a declared one:

- `declared_step_property` — the registry itself identifies the step (GATE-008 → the closure step;
  GATE-005 → founder-gated steps; GATE-004 → reviewed steps; GATE-007 → handoff-sending steps)
- `universal` — governs every step
- `workflow_scope` — scoped to a workflow with no finer anchor declared
- `phase_level` — governs the phase, not a step

## Recorded checksums

Every registry digest is taken **twice**, from the live database and from the committed CSV. If a
pair disagrees, the repository and the database have diverged and the baseline is not a baseline.

| registry | rows | database | artefact |
| --- | --- | --- | --- |
| workflow_registry | 30 | `831d7708297fb1c1…` | `c8282d5244dfdf98…` |
| step_registry | 257 | `3737a727eb0a80da…` | `f0df0886761727fe…` |
| handoff_registry | 161 | `881adb51a12f6e9e…` | `83b91c88d2d41ba7…` |
| object_registry | 56 | `2e3b9b17cc94e80c…` | `517bcc2e80a91c3d…` |
| rule_registry | 54 | `b68e3445a2af2777…` | `5c4fcd37d8c89b32…` |
| gate_registry | 32 | `c24cea77682c4d6c…` | `9cf3ae27778c92ff…` |
| exception_registry | 50 | `77f6a85be8d2ee57…` | `e5de877672747e5a…` |
| sla_registry | 34 | `3493f2d15e988cdf…` | `8ad44ce0624b7b3d…` |
| event_registry | 347 | `d9822c9d98c487ee…` | `574452a162d39b90…` |
| state_machine | 79 | `bb95d1c9375e0b79…` | `ef51224bc067f542…` |
| crosswalk | 719 | `aa66e16df36b3e9b…` | `87728e99b9e03570…` |
| founder_boundary | 10 | `eeda61514495c2b2…` | `130e8e5ae7c7bdb9…` |
| effective_errata | 3 | `de0b247709553067…` | *(database only — no CSV; recording a path here would invent one)* |

Production organization/workflow fingerprint: `a405638c021a4d704d7d616c16621b6ee3432af640b4cc957d019b5d45e8d5e3`

Full values, including all 11 migration file digests and the rollback digest:

```sql
select counts, registry_sha256, migrations, rollbacks, organization_sha256
from public.org_phase_baseline where phase = 'B';
```

### `final_commit` versus the tag

Phase A recorded `final_commit = d5107300` while its tag sits on merge commit `00f1f47`. Both are
correct and nothing explained the difference. Phase B records both and says which is which:

- **`final_commit`** — the commit whose tree the registry digests were computed from.
- **`counts->>'git_tag'`** — `phase-b-founder-approved-2026-08-15`, placed on the merge that
  carries the architecture *and* its freeze. Resolve with `git rev-list -n 1 <tag>`. The SHA is
  deliberately not hard-coded: it cannot be known until the commit containing that record has
  itself been merged.

## The freeze

`z90_phase_b_freeze` on 11 tables refuses any statement that changes the approved architecture.

**It compares a digest, not a count.** Phase A's guard compares counts, so a change that swaps two
managers while keeping the head-count identical passes the trigger and is caught only later by the
separate digest check. Phase B refuses it at the moment it is written — swapping two step owners
changes the `step_ownership` digest even though no row count moves.

Nine frozen subjects, each forced to fire inside an aborted transaction:

```
FREEZE PROBE refused=9/9 accepted=[none]
```

workflow ownership · workflow order · gates · business rules · handoff accountability ·
category-overlay authority · founder boundaries · states/transitions · workflow state terminality.

And the hatch opens, or this would be a wall rather than a change process:

```
HATCH OPENS=t
```

### What is **not** frozen, and why

Said here rather than left to be discovered:

- **`phase_b_sla_policy`** — master spec §14 states SLA values may be adjusted by authorized
  management without reopening the structural definition, provided the accountable owner is
  unchanged and no gate is weakened. Freezing them would contradict the approved spec.
- **`phase_b_crosswalk`** — it is a *measurement* of the current runtime and Phase C must
  re-measure it. Freezing a measurement freezes the estate's own reflection.
- **`phase_b_exception`, `phase_b_business_object`, `phase_b_event`** — not in the founder's list.
  `fn_phase_b_baseline_drift()` reports a count change in them, but they are **not guarded at
  write time**. That is a real limit of the freeze, not an oversight to be implied away.

### Changing anything frozen

A formal Phase B change request, stated in the same transaction:

```sql
set local app.phase_b_change_reason = 'PBCR-nnn: <the eleven required elements>';
```

The eleven elements the founder requires: observed problem · evidence · current workflow and step ·
proposed change · affected owners · state-machine impact · gate and rule impact ·
customer/supplier impact · privacy, legal and financial impact · backward compatibility ·
founder approval requirement.

The template is `docs/phase-b/PHASE_B_CHANGE_REQUEST_TEMPLATE.md`. The setting is the audit trail,
not the obstacle — a sentence typed to get past the guard is not a change request.

## How to check the freeze is intact

```sql
select * from public.fn_phase_b_baseline_drift();     -- must be 0 rows
select * from public.fn_phase_a_baseline_drift();     -- must be 0 rows
select * from public.fn_phase_b_effective_errata();   -- all three resolved
```

```bash
node scripts/checks/phase_b_invariants.test.mjs
node scripts/checks/phase_b_guards_reject_injected_defects.test.mjs
```

## The seven Phase C wiring gaps

Accepted by the founder as Phase C work, not Phase B defects.
`select * from public.phase_b_phase_c_wiring_gap;`

1. 12 of 19 current runtime workflow definitions have zero runs.
2. `rfq_handling` has zero complete runtime journeys.
3. 407 cron and Edge Function execution paths lack canonical accountability.
4. 64 Edge Functions have no known caller or external entry point.
5. W21 has no runtime implementation.
6. Eleven canonical workflows have no runtime-step implementation.
7. Four deployment-parity items remain unverifiable.
