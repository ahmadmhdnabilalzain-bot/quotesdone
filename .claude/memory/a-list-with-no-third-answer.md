---
name: a-list-with-no-third-answer
description: "an allow-list and a deny-list that together cover only 22 of 46 kinds leaves the rest never selected, silently, by every reader"
metadata: 
  node_type: memory
  type: project
  originSessionId: 749db893-10fc-4da9-9f6c-2629cba707a8
  modified: 2026-08-12T23:48:46.974Z
---

`agent_actions.kind` was classified by a 14-item WORKABLE list and an 8-item NEVER list, hard-coded
**twice** — a SQL `IN` list in `fn_agent_action_work_sweep` and two TypeScript `Set`s in
`action_worker`. They agreed, but nothing made them agree, and neither had a third answer:
**24 kinds appear in neither**, so they were not refused with a reason — they were never *selected*,
silently, by both readers. 1,459 rows had been written under them.

Fixed 13 Aug 2026 with `agent_action_kind_policy` (kind → 'auto' | 'founder'), read by both. An
unknown kind is refused **and named** by `fn_founder_queue().unrouted_kinds`.

**Why:** a pair of literal lists encodes "yes" and "no" but cannot encode "nobody has decided", and
absence produces silence rather than a question.

**How to apply:** when two lists partition a domain, ask what the code does with a value in neither
— and make that case loud. Same shape as `org_action_executor.unattended_ok` (default false, so a
new human-notifying executor is refused until someone decides). Related:
[[guarded-by-a-condition-that-cannot-occur]], [[absent-input-scores-as-satisfied]].
