---
name: checks-can-measure-row-age-not-mechanism
description: "Several Row #3 checks are universals over stored rows, so they read MISSING because the rows predate the fix, not because the mechanism is broken — probe the mechanism before rebuilding it."
metadata: 
  node_type: memory
  type: project
  originSessionId: 9e304e25-2c45-4722-877e-761ec03b37f2
  modified: 2026-08-11T10:14:59.222Z
---

Row #3 checks are frequently written as "every row in X carries Y". When a fix lands, the check keeps
reading MISSING until the old rows age out — or forever, if the check has no time window.

Measured instances on 2026-08-11:

- **`s24-board-before-major-decisions`** — `fn_decide` already called
  `fn_board_review(problem, decision_record_id)`. Probed: 7 opinions, 7 advisors, `subject_ref` set on
  all 7. It had simply never been exercised since the wiring landed. "0 of 11" was the age of the
  rows, not the health of the mechanism.
- **`what-if-projected-deltas` / `what-if-confidence-score`** — `N('simulations')` is
  `count(*) ... where true`, **no window**. Five July rows without the revenue+leads+profit triple
  will fail these two checks permanently, however correct the simulator becomes.
- **`explain-confidence-score`** — reads the 8 most recent `decision_log` rows with a `route_to`.
  Fixing the writer only shows up as those 8 roll over, at roughly 4–5 gated actions an hour.

**How to apply:** before rebuilding anything the brief calls missing, run the mechanism in an aborted
transaction and read the verdict. If the mechanism works, the fix is to the writer or to time, not to
the feature — and say so rather than rebuilding. Never re-date or rewrite historical rows to make a
universal pass; that converts an honest MISSING into a false MET.

Related: [[session-briefs-carry-misdiagnoses]], [[quotesdone-definition-of-done]]
