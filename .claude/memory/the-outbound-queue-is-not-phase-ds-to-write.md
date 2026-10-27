---
name: the-outbound-queue-is-not-phase-ds-to-write
description: Two kernel boards forbid a Phase D write map or fixture stage targeting public.notifications; that is why object round trips are 55/56 and not 56/56.
metadata:
  type: project
---

`fn_phase_d_effect_state.phase_d_write_maps_into_the_outbound_notification_table` and
`fn_phase_d_fixture_state.fixture_stage_targeting_public_notifications` both expect 0. The first
sits beside `kernel_owned_objects_with_a_phase_d_writer` — the same rule about a different
relation: the outbound queue is not Phase D's to write, **whatever state the row is in**.

23 Aug 2026: a notification fixture stage was built and measured clean (30 records written, 0
deliverable, status forced to `suppressed` by the outbound door, which no sender selects). Both
boards went red anyway, and they were removed rather than disclosed — `kernel-boards.json`'s own
check says do not add an entry to make a test pass.

**Why:** a structural rule that can be satisfied by choosing the right column value is not a
structural rule.

**How to apply:** `notification` is reported NOT_CREATED_BY_ANY_STAGE by design. Reaching 56/56
needs a founder decision — either the queue stops being off-limits, or the object's creation is
proved somewhere other than the fixture factory. Do not rebuild the stage.
Related: [[read-the-guards-before-working-around-them]], [[a-guard-that-fires-when-the-system-works]].
