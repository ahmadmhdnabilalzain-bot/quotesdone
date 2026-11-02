---
name: zero-cannot-tell-a-dead-guard-from-an-idle-system
description: "A new guard returning 0 proves nothing — build a positive test that forces it to fire, or you ship a guard that can never match."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 0ac5c5e2-c087-483c-b4d1-2cb949855d6b
  modified: 2026-08-15T08:24:15.565Z
---

14 Aug 2026: I added a recurrence cool-down to `fn_event_dispatch` and copied its discriminator
from the guard directly above it — `decided_by = 'fn_event_dispatch'`. That column is not
provenance, it is WHO DECIDED, and the executor overwrites it when it settles the row. Measured:
`select count(*) from org_tasks where decided_by='fn_event_dispatch' and status in
('done','closed','cancelled')` returned **0**. Not few — there has never been one.

The smoke test passed. The function returned its new keys and `suppressed_recurring: 0`.

**Why:** a guard that can never match returns 0, and so does a guard with nothing to guard. On an
idle queue those two are byte-identical in the output. The smoke test was measuring the wrong
subject — it proved the code deployed, not that the branch can execute.

**How to apply:** after adding any conditional path, construct the input that MUST take it and
assert it did — an aborted-transaction probe that emits the triggering event and checks the effect,
not the return code. Here: emitting `test.failed / scheduled_run / archive_rfq` attached the
`knowledge` delivery to closed task 721 instead of minting a new one, while `qa` (no closed copy in
window) correctly still minted. That is the test; `0 suppressions` was not.

Corollary worth its own check: when reusing a column as a filter, ask whether anything downstream
WRITES to it. `decided_by`, `status`, `updated_at` and `source` are all overwritten by later stages
here. The durable join was `event_delivery.task_id`, which 362 closed tasks actually carry.

**15 Aug 2026 — the same defect, one level up, in a test's own injection.** The Phase B
injected-defect suite reported that two handoff guards had ACCEPTED their defects. They had not:
five cases targeted `H-W12-01-02`, a handoff id that does not exist. The `UPDATE` matched zero
rows, raised nothing, and the suite read that silence as acceptance. A zero row count cannot tell
a dead guard from an injection that never landed either.

**How to apply to a negative test:** wrap every mutation so it fails loudly when it matches
nothing — `do $$ begin <stmt>; if not found then raise exception 'INJECTION MISSED'; end $$;` —
and derive ids from the live table rather than hard-coding them. A test that cannot land its
input is not a test.

Sibling of [[guarded-by-a-condition-that-cannot-occur]] and
[[instrument-measuring-wrong-subject-is-the-lens]].
