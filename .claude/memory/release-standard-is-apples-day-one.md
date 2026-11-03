---
name: release-standard-is-apples-day-one
description: "Founder 3 Nov 2026: 'good to go' means Apple's day-one bar, every scenario proven on demo data; never say ready until docs/release/qualification_matrix.md's checklist is measured green the same day"
metadata:
  node_type: memory
  type: feedback
  modified: 2026-11-03
---

The founder's release standard (3 Nov 2026): the app is judged "good to go" the way Apple judges a new iOS or
any major app on day one. Once it is released, the only bugs allowed are the small day-to-day kind, fixed by a
weekly patch. "Literally every single scenario is possible." Two examples he gave:

- A supplier uploads a 300-page company profile. The sales agent must read all of it, summarise it correctly and
  set the right trades and keywords.
- A customer explains a complex inquiry over a long conversation. The agent must never hallucinate.

"The workflow needs to be 100% correct." No real users and no live pilots: everything is proven on demo data
(ZZ DEMO, @example.invalid, fixture numbers) in the sandbox.

**Why.** He relies on the machine fully and cannot troubleshoot it himself. A marketplace launches once. A
premature "ready" puts real suppliers and customers on a broken path.

**How to apply:**
- The standard is `docs/release/qualification_matrix.md`. It sets severities P0–P3, a scenario list per flow
  with the universal edge suite, statistical eval specs for every AI step (0 failures in N ≥ 300 trials is
  needed to claim ≤ 1%), failure drills, load/soak, monitoring, rollback, and the ranked gap list.
- Never say "ready" or "good to go" until the matrix's section 7 checklist is filled from runs made the **same
  day** on the deployed commit, with 0 open P0/P1, and every P2/P3 listed, given a fix date ≤ 7 days and
  accepted by the ceo seat. Otherwise say "not ready because X".
- Any hallucinated company fact, price, term or document field is at least P1, and P0 when it touches money or
  terms. A GAP or NOT MEASURED line blocks the word "ready" exactly as a FAIL does.
- When a flow changes, add its lines to the matrix in the same PR.

Related: [[ready-means-every-gate-measured]], [[never-state-what-you-have-not-measured]],
[[launch-only-when-perfect-sandbox]], [[nothing-is-done-until-a-browser-proved-it]].
