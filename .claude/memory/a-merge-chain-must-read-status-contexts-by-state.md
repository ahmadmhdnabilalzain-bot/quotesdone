---
name: a-merge-chain-must-read-status-contexts-by-state
description: gh statusCheckRollup mixes check runs (status/conclusion) and status contexts (state only); a merge chain that reads .status/.conclusion misjudges Vercel
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-15T07:28:24.342Z
---

`gh pr view --json statusCheckRollup` returns two kinds of entries:
- **check runs** (GitHub Actions) carry `name`, `status` (IN_PROGRESS/COMPLETED) and `conclusion` (SUCCESS/FAILURE/SKIPPED/NEUTRAL, or `""` while running);
- **status contexts** (Vercel, and a nameless entry) carry `context` and `state` (SUCCESS/PENDING/FAILURE), with NO `status` and NO `conclusion`.

**What went wrong on 15 Sep 2026:**
- **An early stop:** chain `bcigwge8r` treated an in-progress check's `conclusion: ""` as a failure and stopped early.
- **A merge while pending:** a one-off merge of #700 printed `pending=1` for the Vercel context and merged anyway, because the merge wasn't conditioned on it. Vercel had in fact succeeded, so no harm was done.

**Why:** the founder's rule is that nothing merges before every check is green ([[code-extremely-well-built]]). A filter that misreads one kind of entry either merges too early or stops for no reason.

**How to apply:** in merge chains, judge each entry as follows.
- **Finished:** `(.status=="COMPLETED") or (.state!=null and .state!="PENDING")`.
- **Failed:** `(.conclusion // .state) not in SUCCESS/SKIPPED/NEUTRAL`, once finished.
- **Unnamed entries:** skip only entries that have neither a `name` nor a `context`.
- **Never merge unconditionally:** gate the merge command on zero pending and zero failed, in the same shell step.

Related: [[two-applied-prs-deadlock-each-others-database-check]].
