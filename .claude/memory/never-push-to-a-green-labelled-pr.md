---
name: never-push-to-a-green-labelled-pr
description: "30 Sep: a commit pushed to a green review-approved PR lost the race to the release train and never merged; unlabel, push, re-label"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8c4972a3-8a16-4cb0-a308-31a4f45e00bb
  modified: 2026-09-29T21:25:13.957Z
---

On 30 Sep 2026 the release operator pushed a registry row (`duty_pause`) to #1137 while it was green and labelled `review-approved`. The train had already merged the evaluated head (b1147e9). It merges with `gh pr merge --match-head-commit`, so the late commit fda61e4 never landed. Main went red until the follow-up #1144.

**Why:** the train merges the head it evaluated, and any commit pushed after that is silently left behind.

**How to apply:** to change a labelled PR, first remove `review-approved`, then push, then re-label once CI is green. Tell every release operator and fixer agent this.

Related: [[never-merge-on-a-red-check]].
