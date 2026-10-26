---
name: the-primary-identity-is-not-how-producers-key-a-subject
description: "phase_d_business_object_binding.primary_identity is NOT how three live producers key their business_object_id — enforcing on it refuses real work."
metadata:
  type: project
---

`public.phase_d_business_object_binding` gives each of the 56 canonical business objects a
`canonical_relation` and a `primary_identity`, and a run's `business_object_id` is
`<object_id>:<identity>`. **Three producers do not use that key**, measured 27 Aug 2026:

| producer | writes | the map says |
|---|---|---|
| W29 `trg_page_high_agent_action` | `incident:agent_action:<agent_actions.id>` | `incident:<os_incidents.id>` (ids 1..32) |
| W16 reveal path | `payment_transaction:<transactions.payment_ref>` | `payment_transaction:<transactions.id>` — and `payment_ref` is **not unique**, so no candidate-key rule reaches it |
| Phase D drives | `dispatch_batch:chk-w12-s06`, `payment_transaction:probe:reveal:1` | invented inside an aborting transaction |

A guard enforcing `identity = primary_identity` refused every W16 run the estate can produce and
every Phase D drive. `fn_kernel_business_subject_resolve` therefore asks three questions in order:
the primary identity; then **any** comparable column of that relation; then the `<token>:<id>` shape
against a public table the token names. Only after all three is a subject `PARENT_MISSING`. A
verified `fn_phase_d_fixture_context()` (HMAC over txid + approved operation) is exempt entirely.

**How to apply:** the estate's own maps describe intent, not what the running code emits. Before
enforcing a map, SELECT what the producers actually wrote and count the disagreements.
Related: [[a-guard-that-manufactures-what-it-prevents]], [[an-identity-is-never-a-fixture]],
[[instruments-report-on-the-wrong-subject]].

**3 Sep 2026 — the DELETE guard had the same blind spot, and the resolver's output hides the fix.**
a00_kernel_parent_delete_guard searched live runs as `payment_transaction:<id>`; W16 keys by
payment_ref, so deleting a transaction under an active W16 run cancelled nothing and orphaned the run
(found via fn_kernel_orphaned_work after the revenue-loop rehearsal). Fixed in
scripts/sql/parent_delete_guard_matches_how_producers_key_the_subject.sql. GOTCHA:
`fn_kernel_business_subject_resolve` returns resolution=RESOLVED but **identity_column='id'** (the
binding's identity) even when it matched under another column — only `resolved_in` says
"(under a column other than id)" in prose. Any consumer comparing `OLD->>identity_column` to
identity_value silently never matches for payment_ref-keyed subjects; compare against every column
(`jsonb_each_text(to_jsonb(OLD))`) as the resolver itself searched. Also: a demo reveal births a
REAL W16 kernel run (payment.received → outbox → fn_phase_c_workflow_start); with the guard fixed,
the harness's plain `delete from transactions` now cancels it in-transaction — no teardown step needed.
