---
name: least-ignores-nulls-in-postgres
description: "PostgreSQL least()/greatest() IGNORE nulls instead of propagating them — least(100, NULL) is 100, which silently scored 56 unmeasured goals as perfect."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 71e4809a-7cb5-4158-86a9-7a2a2e63b4d5
  modified: 2026-08-11T09:03:34.286Z
---

`least(100.0, NULL)` returns **100.0** in PostgreSQL. Unlike almost every other
expression, `least()` and `greatest()` skip null arguments rather than
propagating null.

This produced the worst founder-facing defect found in the 11 Aug 2026 audit:
`fn_founder_brief` scored goal attainment as
`least(100.0, 100.0*actual/nullif(target,0))`, so every goal with no measured
actual scored a perfect 100 and was averaged with the real ones. The daily email
read "Monthly goal attainment: 97.7% against target" on a day of AED 0 revenue
against an AED 83,333 target. Corrected figure: 50.0% across 2 of 61 goals.

Whenever an aggregate is built over a population that may be unmeasured, publish
the denominator alongside the percentage — `fn_goal_attainment` returns
`goals_measured` and `goals_total` so a caller cannot quote the rate without its
base. Relates to [[session-briefs-carry-misdiagnoses]].
