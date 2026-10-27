---
name: a-fixs-own-check-measures-the-case-the-fix-handles
description: "The lens behind most defects caught on 23 Sep — an author's new check tests the case the fix handles, so it goes green while the live defect survives in the case the fix missed"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8c4972a3-8a16-4cb0-a308-31a4f45e00bb
  modified: 2026-09-23T01:27:21.390Z
---

23 Sep 2026, three times in one session, on three different PRs. The pattern is not a weak check — it
is a check whose **subject is the fix rather than the property**.

- #859's service gate was written per-inquiry instead of per-trade, so it delivered the property for a
  single-trade inquiry. Its new guard measured **one trade's services at a time**, so after the apply it
  would have gone green while a two-trade inquiry still reached **zero** suppliers in one of them — and
  every inquiry production actually holds is multi-trade (one carries five keys across three trades).
- #854's thin-market floor was arithmetically invertible at n=3 and n=5, and its test asserted at one
  convenient value.
- #853 reported a false green because it piped to `tail`, so the exit status was the pipe's.

**Why:** the author writes the check from the same mental model that produced the fix. If the model is
missing a case, the check is missing it too, and the green then certifies the gap. This is worse than no
check, because it converts an outage into confidence — the same reason
[[checks-retired-with-their-subject]] says never to soften a check to green.

**How to apply it:** when reviewing a fix, do not ask whether its check passes. Ask **what case the
check measures, and what case the fix handles** — if they are the same case, the check proves the fix
ran, not that the property holds. Then find the case the author did not think of (the multi-trade
inquiry, the second boundary, the concurrent caller) and measure THAT against production. A guard must
assert the property over the whole table, not over the row the fix touched — which is also why
[[a-nearest-neighbour-is-always-found]] and [[group-per-class-not-in-aggregate]] keep paying.

The corollary that held all day: every PR sent back on 23 Sep had a defect in the **fix**, not in the
diagnosis. The diagnoses were right. See [[code-extremely-well-built]] — the independent review before
every merge is what caught all of them, and it is permanent for this reason.
