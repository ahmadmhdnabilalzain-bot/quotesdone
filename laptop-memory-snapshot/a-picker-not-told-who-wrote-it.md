---
name: a-picker-not-told-who-wrote-it
description: fn_pick_reviewer took only a department and returned its head — 182 self-approvals. A selector missing the actor will eventually select the actor.
metadata: 
  node_type: memory
  type: project
  originSessionId: fd0754be-8798-4bcf-aec6-6ae1c72265c4
  modified: 2026-08-14T13:05:30.518Z
---

`fn_review_submit(subject, id, dept, **author**, content)` held the author and called
`fn_pick_reviewer(dept)`, which answers with the department head. Whenever the head was the author,
the head approved itself: **285 of 1,882 `review_chain` rows had `author_agent = reviewer_agent`,
182 of them approvals**, the most recent five hours before the fix on 14 Aug 2026.

**Why:** the information needed to prevent it was already in the caller's parameters. Nothing
failed, no check covered it, and the reviewer field was populated — it just held the wrong name.

**How to apply:** for any "pick the reviewer / approver / second pair of eyes" function, ask what it
is NOT told. Then add the exclusion, and add the constraint so it is unrepresentable —
`review_chain_no_self_approval_ck`, `NOT VALID` so the history that proves the defect survives.
The general lens: **does this selector know who it must not select?**

Related: [[guarded-by-a-condition-that-cannot-occur]], [[a-condition-that-cannot-not-fire]].
