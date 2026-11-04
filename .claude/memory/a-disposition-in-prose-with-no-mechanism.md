---
name: a-disposition-in-prose-with-no-mechanism
description: "A routine whose \"kernel-internal primitive\" status lives only in a why column, with neither the REVOKE nor the register row — and the check that would notice filtered it out by name prefix."
metadata: 
  node_type: memory
  type: project
  originSessionId: d089c73b-6b45-4e66-aa23-4b1eefd1aff0
  modified: 2026-08-17T21:49:24.979Z
---

17 Aug 2026. `kernel_write_authority.why` described four routines as kernel-internal primitives.
Two of their siblings say the same thing **and** carry the two mechanisms that make it true: a row in
`kernel_retired_path`, and no `EXECUTE` for any ordinary role. Same probe, as `service_role`, one
aborted transaction:

- `fn_phase_c_workflow_start`, `fn_phase_c_task_create` (registered + revoked) → REFUSED `42501`
- `fn_phase_c_outbox_emit` (neither) → **ACCEPTED, and it wrote** a `phase_c_event_outbox` row with
  `status='pending'`, `next_attempt_at` defaulting to `now()`, `trace_id` NULL — a deliverable event
  injected outside the kernel, untraced. `fn_phase_c_handoff_open`, `fn_phase_c_handoff_decide`,
  `fn_phase_c_task_transition` likewise ACCEPTED.

**Why no instrument saw it.** `kernel_positive_controls.test.mjs` derived its denominator as
`kernel_write_authority` minus `kernel_retired_path` **and** `like 'fn\_kernel\_%'`. The prefix was a
third term nobody had written down, and it removed the door before the "every door has a control"
loop ran — so the suite printed `13 door(s), 13 accepted` about a door it had just walked through.
`fn_kernel_retired_path_state()` was no help either: its `paths_with_no_recorded_disposition` reads
`0 of 0` because its denominator is `kernel_retired_path` itself. See
[[a-list-with-no-third-answer]] and [[filter-values-written-by-a-path-that-never-ran]].

**Second instance the same day: a row-level guard cannot see TRUNCATE.** `fn_kernel_write_guard` is a
`BEFORE INSERT/UPDATE/DELETE` row trigger, and `service_role` held `TRUNCATE` on all seven protected
tables. `truncate public.phase_c_handoff_run` as `service_role` went **7 rows → 0**, firing nothing
and writing no trace. `kernel_write_guard_both_directions.test.mjs` proves seven cases; none is a
TRUNCATE.

**Why:** a disposition enforced by one mechanism is one `grant all` from gone, and a disposition
enforced by zero mechanisms is a sentence. Both fixes ship the grant **and** the guard —
`kernel_s4_a_disposition_that_is_not_a_grant_is_a_sentence.sql`.

**How to apply:** when a register column explains why something is safe, ask which *mechanism*
enforces that sentence, and drive it from outside — `set local role service_role` in an aborted
transaction. Then ask what the check that should have caught it *filters on*: if the derivation has a
term the stated rule does not mention (a name prefix, a status, a date), that term is where the
missing case lives. And when a guard is a row trigger, TRUNCATE is always the case it cannot see.

Related: [[a-disposition-is-not-a-behaviour]], [[promote-carries-the-definition-not-the-grants]],
[[a-rehearsal-proves-creation-not-execution]], [[group-per-class-not-in-aggregate]].
