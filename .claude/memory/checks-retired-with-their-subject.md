---
name: checks-retired-with-their-subject
description: 13 CI checks were retired on 7 Sep 2026 because what they asserted was deliberately deleted — never edit a check until it passes against an empty schema
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-08T22:57:36.522Z
---

When the founder removed the org chart, the workflows and the kernel gates on 7 Sep 2026, thirteen
CI checks went red because every noun in them had been deleted on purpose.

Retired to `scripts/checks/<name>.RETIRED.mjs`, each with a header saying what it checked, what
removed its subject, and that nothing replaces it yet: `kernel_positive_controls`,
`phase_c_guards_reject_injected_defects`, `kernel_write_guard_both_directions`,
`active_signal_types_are_executable`, `company_is_fully_wired`, `application_source_of_truth`,
`phase_d_dispatch_reaches_executed`, `phase_d_input_schemas_are_typed_and_closed`,
`phase_d_object_record_has_a_contract`, `kernel_boards_are_green`,
`a_failed_scheduled_run_has_a_reader`, `org_connectivity_signal_path`,
`org_connectivity_scenarios`. All removed from `.github/workflows/project-parity.yml`.

**Why:** a check edited until it goes green against an empty schema asserts nothing while still
looking like a guard — worse than no check. Retiring with a written reason is honest; softening is
not. Sibling of [[never-weaken-a-check]] thinking in the session skill.

**One was INVERTED rather than retired**, which is the better move where the ruling itself is worth
guarding: `phase_c_components_are_owned` now asserts *no component names a department, because
there are none*, so the ruling goes red if anyone reaches for a `dept_key` again. Its other test
became *a component that NAMES an owner names an active role* — an absent owner is his decision, a
wrong owner is still a bug.

**Still green and still guarding:** `kernel_invariants`, `cancellation_reaches_the_kernel`,
`every_discharge_claim_reaches_its_table`, `anon_cannot_execute_security_definer` (security, never
depended on the org), `phase_c_components_are_owned`, `canonical_routine_manifest`,
`export_from_either_source_is_identical`, `receipts_never_wait_on_the_founder`.

## 9 September 2026 — 18 more, and the rule held under pressure

The Phase A–D removal and the last of the 7 Sep deletions took eighteen further checks. Of that
list above, `phase_c_components_are_owned` and `kernel_invariants` have since gone too. Retiring is
never the default answer; each was decided against production:

- **Retired though GREEN.** `phase_d_migrations_are_classified` passed with 0 failures on the day it
  was retired. It classified 226 phase_d SQL files by whether each could be rolled back, and nothing
  is left to roll back. A passing check over a dead subject still asserts nothing.
- **Repaired where the property outlived its plumbing.** `anon_cannot_execute_security_definer`
  (ceiling 4 → 2 — a ratchet must move DOWN when the surface shrinks, or it stops being a ratchet);
  `the_refund_ladder_texts_agree` (reads the terms pins directly instead of a dropped aggregate, and
  GAINED two assertions — the old routine compared with `is not distinct from`, so a wiped pin
  compared equal to null and went green); `agent_action_fields_are_filled_after_the_gate` (the named
  trigger was gone but the filler survived under a name that sorts differently, so the assertion was
  widened to "sorts after EVERY other BEFORE row trigger").
- **Repair attempted and refused on the evidence.** `an_exam_answer_never_becomes_knowledge` looked
  repairable — the knowledge body is one of the five kept things. Re-pointing it at the surviving
  question bank would have been red on day one: 703 of 1,530 reference answers are exactly 700
  characters, the signature of a truncated knowledge slice. Shipping a permanently red check and
  tuning the probe until it passed are both forbidden, so it retired with that evidence in its header.

**The counter-lesson, and it cost nothing only because an agent pushed back.** A brief instructed a
rewrite of one scenario into a `to_regclass`-null assertion "because the founder layer is gone". It
refused, correctly: `founder_alerts` still exists, holds 15 rows and is named by 17 live routines.
What was dropped was the COMMAND layer, not the NOTIFICATION table. Verify before retiring — the
instruction to retire can itself be the wrong one, including when it comes from me.
