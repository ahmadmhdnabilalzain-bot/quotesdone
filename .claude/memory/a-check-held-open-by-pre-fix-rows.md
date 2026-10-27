---
name: a-check-held-open-by-pre-fix-rows
description: "Before building anything for a red per-row universal, split the population by the deploy timestamp — five Row #3 checks were already fixed and merely waiting for old rows to leave the window"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 6ee28b3e-1f95-4b49-9341-54ffe11ece66
  modified: 2026-08-14T01:03:54.169Z
---

A per-row universal over a rolling window ("EVERY recommendation in 30 days carries seven fields",
"ALL snapshots in 14 days", "every meeting in 60 days") stays red long after the mechanism is fixed,
because the pre-fix rows are still inside the window. The check is correct; the diagnosis "this needs
building" is what's wrong.

**Why:** on 14 Aug 2026 FIVE of Row #3's seventeen remaining reds were in exactly this state, and the
session brief described two of them as real work still to do:

| check | mechanism fixed | closes on its own |
|---|---|---|
| `time-machine-restores-six-dimensions` | `customers` key added to the snapshot writer 9 Aug | 23 Aug |
| `s36-recommendation-seven-fields` | field filler, 13 Aug 19:37 | 12 Sept |
| `explain-alternatives-considered` | same filler, 13 Aug 19:37 | 12 Sept |
| `s24-board-before-major-decisions` | `fn_decide` passes `subject_ref` | ~5 Sept (decision 42) |
| `exec-meeting-priorities-agreed` | `fn_exec_meeting` emits rank/owner objects | ~5 Oct |

The brief called `explain-alternatives-considered` "an output-contract change across many agents —
that is the real work". Measured: 6 of 6 actions created after the fix carry alternatives, 170 of
1,510 before. The work was already done.

**How to apply:** split the population by the deploy timestamp before writing any code —
`group by (created_at >= '<deploy ts>')`. If the post-fix slice is 100%, build nothing and report the
date the window clears. Then confirm the mechanism with an **aborted-transaction probe** rather than
trusting the slice, because a slice of 6 rows can be luck: inserting a bare `agent_actions` row and
reading it back proved all seven fields fill, and proved `alternatives` is the authority gate's real
permitted/held decision with a stated reason — not the invented fallback the brief warned about.
Never back-fill pre-fix rows to close one of these. See [[session-briefs-carry-misdiagnoses]] and
[[checks-can-measure-row-age-not-mechanism]].
