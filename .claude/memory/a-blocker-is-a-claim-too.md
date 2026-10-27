---
name: a-blocker-is-a-claim-too
description: 23 of 39 recorded "cannot run" blockers were wrong; re-measure the blocker before accepting it.
metadata:
  type: feedback
---

A NOT_RUN row's stated blocker is a claim, and in Phase D **23 of the 39 were wrong** when
re-measured on 24 Aug 2026. Four shapes, all recurring:

- **"needs a COMMITTED row"** — `inquiries`, `quotes` and `phase_d_object_record` hold 0 rows
  *outside* a fixture. Inside `fn_phase_d_fixture_scenario` they do not. The case needed a
  scenario, not a commit — and the deliverable driver opens the fixture context and builds none.
- **"SECTION 8 NOT BUILT"** — it was built days earlier and the report wrapper already overrode it.
- **the wrong table named** — "the founder-approval path is phase_c_refund_decision"; it is
  `public.founder_approval_request`, which carries the exact refusal.
- **"no Phase D path writes that table"** — true and irrelevant; the rule was registered at a
  routine, not at the table.

**Why:** a blocker is written once by whoever could not make the case run that day, and then read
as a fact forever. It ages worse than any other text in the estate.

**How to apply:** before accepting any "cannot execute / not built / needs X" text, measure the
thing it names. Then move the reason out of the code into a register a check can contradict —
see [[a-reason-in-a-string-literal-is-read-once]].
