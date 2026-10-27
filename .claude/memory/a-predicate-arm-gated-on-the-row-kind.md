---
name: a-predicate-arm-gated-on-the-row-kind
description: "A check whose only satisfying arm is gated on a source kind excludes a whole class from ever passing — 5 of the 9 \"kernel bypasses\" were frontend rows that structurally could not pass."
metadata: 
  node_type: memory
  type: project
  originSessionId: f9a36089-6fc5-4d31-8137-ab97b324a4b4
  modified: 2026-08-24T21:07:42.287Z
---

`v_kernel_trigger_source_derived.routes_through_inbox` has three arms: the source's own routine
calls a kernel submit function; an edge-writes→trigger join; or a recorded flag. The middle arm —
the only one that can resolve a real call chain — is gated on `s.source_kind = 'edge_function'`.

Five of the nine rows in `fn_kernel_trigger_state :: active_autonomous_source_not_yet_routing_through_the_inbox`
(9 of 37, measured 24 Aug 2026) are `frontend_path` rows. A browser writes nothing and calls an edge
function, so **no frontend route can ever satisfy that predicate**. They were not bypassing the
kernel; they were structurally incapable of reading as routed.

Measured outcome of the nine: **1 real defect** (`edge:inquiry_intake` INSERTs `public.customers`,
which carries no kernel-routing trigger), **0 held**, **8 false or stale measurements**.

**Why:** a class that cannot pass a check is not being measured by it, and its count reads as a
backlog. Sibling shapes already in memory: [[two-boards-one-subject-neither-right]],
[[zero-cannot-tell-a-dead-guard-from-an-idle-system]], [[a-list-with-no-third-answer]].

**How to apply:** before believing a red count, ask *which rows in this population could ever
satisfy the predicate?* If a whole `kind` cannot, the number is about the check. Either give the
predicate an arm for that kind, or hold the kind out of the population by disposition the way
`FOUNDER_COMMAND_SURFACE` already is — never leave it counted.
