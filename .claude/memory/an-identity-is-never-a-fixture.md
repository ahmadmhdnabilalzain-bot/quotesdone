---
name: an-identity-is-never-a-fixture
description: "A test harness that generates a value for an identity key answers its own question — three instances in one session, one of which created four customer accounts for one onboarding."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: d93d072c-73b8-4175-b694-f8f16c737720
  modified: 2026-08-18T19:07:11.499Z
---

A fixture generator that fills in every declared key will eventually fill in an **identity**, and
that is never a fixture. Three instances on 18 Aug 2026, all in `fn_phase_d_drive_workflow`:

- GATE-002 declares `actor_role_id` as evidence → generator produced `ZZ DEMO — actor_role_id` →
  the executor merges caller context **last**, so it replaced the real accountable owner and BR-004
  refused the step as non-canonical.
- GATE-008 gained `step_run_id` as declared evidence → generator produced a string → the gate cast
  it to bigint and threw.
- The write map's key column (`customers.id`) got a fresh uuid **per step** → W04 created **four**
  customer accounts for one onboarding, and the effect ledger counted all four as successes.

**Why:** the harness is supposed to exercise the subject, not supply it. An identity fixture makes
the subject whatever the harness says it is, and the resulting pass or refusal is about the fixture.

**How to apply:** identities come from the row under test or from a per-run memo, never from the
generator — `step_id`, `run_id`, `step_run_id`, `actor_role_id`, `reviewer_role_id`, and the target
table's key column. Foreign keys are the same class: refuse rather than invent, because an invented
parent either violates the constraint or passes by pointing at somebody's real row. See
[[harness-seeds-an-order-reality-cannot-produce]] and [[a-picker-not-told-who-wrote-it]].

Two related shapes from the same session, both "a condition that cannot NOT fire"
([[a-condition-that-cannot-not-fire]]): GATE-006 refused all 55 steps whose success state equals the
state the run is already in, because *no transition* is not *an undeclared transition*; GATE-008
counted the closure step run that was asking it, making it unpassable for all 30 closure steps.
