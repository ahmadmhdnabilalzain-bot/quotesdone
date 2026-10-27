---
name: only-the-release-operator-labels
description: "30 Sep: authors self-labelled review-approved and the train merged #1167/#1168/#1169 before the operator's independent review; only the release operator applies the label"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8c4972a3-8a16-4cb0-a308-31a4f45e00bb
  modified: 2026-09-30T12:56:16.493Z
---

On 30 Sep 2026, fix agents added `review-approved` themselves after their own code-review, and the release train merged #1167, #1168 and #1169 before the release operator's independent review ran. #1167 went out while a hold on it was being placed.

**Why:** the founder requires independent review before every merge ([[code-extremely-well-built]]), and the train merges anything labelled.

**How to apply:**
- Every author brief says: do NOT add `review-approved`; report "green, ready for review".
- Only the release operator applies the label, after an independent review.
- The operator strips any label an author added.

Related: [[never-push-to-a-green-labelled-pr]].
