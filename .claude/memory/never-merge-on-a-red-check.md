---
name: never-merge-on-a-red-check
description: "22 Sep 2026 — a chained `gh pr checks --watch; ...; gh pr merge` merged #817 with a failing check; gate the merge on zero failures"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-21T23:27:53.399Z
---

On 22 Sep 2026 I ran `gh pr checks N --watch; gh pr checks N | awk <print failures>; gh pr merge N`. The awk printed a failure, but the merge ran anyway because nothing tested the result. #817 was merged with the repository-root guard red. A dated graphify backup over 5 MB had been committed by a hook. It took a follow-up PR to remove it.

**Why:** printing a failure is not the same as stopping on one. Any merge chain has to exit before the merge when a check failed.

**How to apply:** use `F=$(gh pr checks N | awk -F'\t' '$2=="fail"||$2=="pending"'); [ -z "$F" ] && gh pr merge N --squash || echo "NOT MERGED: $F"`. Never put `;` before `gh pr merge`. Related: [[a-merge-chain-must-read-status-contexts-by-state]], [[code-extremely-well-built]].
