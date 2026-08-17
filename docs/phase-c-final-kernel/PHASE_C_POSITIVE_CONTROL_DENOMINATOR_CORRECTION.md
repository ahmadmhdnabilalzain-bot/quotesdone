# Correction — the positive-control denominator was never 20

**Corrects:** `docs/phase-c-kernel/PHASE_C_BUILDER_CLOSURE.md` and
`docs/phase-c-final-kernel/PHASE_C_FIVE_ROOT_CAUSES_CLOSURE.md`, the line
*"positive cases accepted | **20 / 20** (Phase B suite, both directions)"*.

**Raised by:** the final independent Phase C re-acceptance, 17 Aug 2026.
**Status:** the denominator is corrected UPWARD in substance and downward in name. Nothing was
lowered to make a number fit.

---

## What the closure claimed

> positive cases accepted — **20 / 20** (Phase B suite, both directions)

## What that suite actually is

`scripts/checks/phase_b_guards_reject_injected_defects.test.mjs` holds **20 cases**. Counted:

| | count | examples |
|---|---|---|
| negative injections — a defect that must be REFUSED | **18** | unknown owner, creator is own reviewer, handoff to itself, frozen architecture changed with no change request |
| genuine positive controls — an allowed operation that must SUCCEED | **2** | *frozen architecture changed WITH a change request* (the hatch must open), *invalid state transition* (`fn_phase_b_transition_allowed('completed','active')` must return false and the harness records the refusal) |

Calling 18 refusals "positive cases accepted" is an instrument reporting on the wrong subject. The
suite is sound; the label was not.

## Is 20 the approved denominator?

**No.** The phrase "positive control" appears nowhere in the Phase C package
(`docs/phase-c/package/`), in the master prompt, or in any Phase C specification document. Measured:
the only occurrences anywhere under `docs/` are in the V3 certification record, which is a different
subject and out of scope for this work. There is no accepted Phase C requirement for 20 positive
controls to meet, and inventing 20 cases to reach a number nobody asked for would be padding, not
evidence.

## The denominator that is defensible, and how it is derived

A positive control is owed for every **canonical kernel entry door**: a routine that

1. holds write authority over a business table (`public.kernel_write_authority`), and
2. is named `fn_kernel_*` or `fn_founder_command_*` — an entry point rather than a trigger body, and
3. is **not** recorded in `public.kernel_retired_path`.

That set is read from production at run time by
`scripts/checks/kernel_positive_controls.test.mjs`, compared against the controls the file
implements, and **a door with no control is a failure**. It is therefore not a number in a
document: a new door cannot be opened without a positive control, and a retired one cannot leave a
stale case behind.

**Measured on 17 Aug 2026: 13 doors, 13 controls, 13 accepted.**

```
fn_founder_command_clarify   fn_founder_command_control   fn_founder_command_submit
fn_kernel_cancel             fn_kernel_handoff_accept     fn_kernel_open_step
fn_kernel_outbox_deliver     fn_kernel_outbox_emit        fn_kernel_review_decide
fn_kernel_signal_submit      fn_kernel_step_complete      fn_kernel_trigger_submit
fn_kernel_workflow_start
```

Each control asserts three things, not one:

- the door **accepted** the legitimate call;
- a **state effect** was measured — the run opened, the step completed, the handoff was accepted,
  the priority moved, the event was delivered — never merely "no error was raised";
- a **trace** exists for the subject.

Every control runs inside a transaction that ends in `raise exception`, and seven table counts are
asserted unchanged afterwards, so production carries nothing away.

## Why this is stricter than what it replaces

The 2 real positive controls inside the Phase B suite remain where they are and still run. The 13
new ones cover the entire current kernel surface, which the old count did not touch at all: of the
13 doors, the previous evidence exercised `fn_kernel_workflow_start` and the maintenance door only,
in `kernel_write_guard_both_directions.test.mjs`.

## The corrected headline

| | |
|---|---|
| negative injected defects, refused | **55 / 55** — `phase_c_guards_reject_injected_defects.test.mjs` |
| Phase B architecture guards fired | **20 / 20** — 18 negative injections + 2 positive controls |
| **genuine positive controls, accepted** | **13 / 13** — `kernel_positive_controls.test.mjs`, denominator derived from `kernel_write_authority` minus `kernel_retired_path` |

`PHASE_C_BUILDER_CLOSURE.md` is regenerated against these three lines. No suite was weakened and no
assertion was deleted to produce them.
