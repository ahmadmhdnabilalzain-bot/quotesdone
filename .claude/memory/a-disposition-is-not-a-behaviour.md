---
name: a-disposition-is-not-a-behaviour
description: A routine recorded READ_ONLY_HISTORICAL was still UPDATE-ing; check what a retired routine DOES, not what its disposition column says.
metadata:
  type: project
---

`fn_phase_c_outbox_settle` carried disposition `READ_ONLY_HISTORICAL` in `kernel_retired_path` and,
called, still `UPDATE`d `phase_c_event_outbox`. Both cannot be true; the database agreed with the
second. All eight retired paths were also still executable by `service_role` — the role every Edge
Function holds.

**Why:** a disposition column is a claim about a routine. Nothing made the routine agree with it,
so the two drifted and the register read as compliance.

**How to apply:** for every entry in a retirement register, ask what the deployed body actually does
and who can still call it — `information_schema.routine_privileges` for the grant,
`prosrc` for the writes. A retired path should REFUSE, not merely be unused. Related:
[[connected-is-a-claim-not-a-measurement]], [[instruments-report-on-the-wrong-subject]].

It surfaced sideways: two guard cases had been failing on a latent cast bug inside it
(`invalid input syntax for type timestamp with time zone`) — which is a routine that *ran and got as
far as writing*, not one that refused. **A test failing on a type error is telling you the path is
live.** Fixed in `kernel_k35_*` and `kernel_k36_*`.
