---
name: a-succession-record-unreachable-behind-the-row-it-replaces
description: A lens — a fallback that only fires when the primary lookup misses, while the primary still matches
metadata:
  type: reference
---

`fn_phase_c_resolve_actor` looked a role token up in `org_role` first and consulted
`org_role_alias` only when nothing canonical matched. Parking a role does not delete its
`org_role` row — it sets `status='retired'` — so the canonical lookup kept succeeding and
returned "inactive" before the alias was ever read.

The `merged_role` alias for `inquiry_quality_analyst` → `document_intelligence_manager` was
written on 3 Sep for exactly this case and had never once been read. W05 stalled at handoff
H-W05-05-06, so W05-S06 and W05-S07 never ran.

**The lens:** when a fallback is guarded by "the primary lookup found nothing", check whether the
primary still finds something in the very case the fallback exists for. A succession record that is
only reachable while the predecessor is still active records nothing. Sibling of
[[guarded-by-a-condition-that-cannot-occur]] and [[finished-capability-with-no-entry-point]].

Fixed 7 Sep 2026 in
`scripts/sql/a_merged_role_alias_is_unreachable_while_the_retired_row_still_exists.sql`: one hop of
recorded succession, followed only from a non-active role, only to an active successor.
