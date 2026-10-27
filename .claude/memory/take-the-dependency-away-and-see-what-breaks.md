---
name: take-the-dependency-away-and-see-what-breaks
description: "To prove nothing depends on X, remove X and run the system — reading the code only proves the code says so"
metadata: 
  node_type: memory
  type: reference
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-07T20:54:00.943Z
---

When the task is "prove nothing depends on the founder / this table / this service any more",
reading the code is worthless. Code says "no founder approval needed" very easily. The way a
dependency actually survives a rewrite is as a WRITE nobody noticed — an insert inside a
helper, a notification the happy path takes for granted — and it stays invisible for exactly
as long as the thing it depends on keeps working.

**The move:** rename the dependency out from under the running code inside an aborted
transaction, then drive the real paths. Anything still reaching for it raises
`undefined_table` and is heard. "Nothing depends on it" stops being a claim about the code and
becomes an observation about what happened when it was removed.

```sql
alter table public.founder_alerts rename to founder_alerts__absent_for_this_test;
-- ... drive ordinary work, a refund end to end, an authenticated command ...
alter table public.founder_alerts__absent_for_this_test rename to founder_alerts;
```

Rename rather than DROP: the rollback restores it either way, but a rename survives a
mid-block failure more kindly and keeps the data.

**Check the opposite error in the same block.** Removing the dependency must not remove the
controls that were near it. The founder-absent test re-asserts, while he is gone, that
execution without a CEO decision is still refused and an expired grant still authorises
nothing — otherwise "it all still works" could mean the guards left with him.

Live instance: group 11 of `scripts/checks/support_acceptance_scenarios.mjs`.
Related: [[zero-cannot-tell-a-dead-guard-from-an-idle-system]],
[[connected-is-a-claim-not-a-measurement]], [[a-blocker-is-a-claim-too]].
