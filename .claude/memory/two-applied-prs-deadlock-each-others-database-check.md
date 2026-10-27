---
name: two-applied-prs-deadlock-each-others-database-check
description: "Two PRs applied to production before either merges each fail \"the database is running what this repository says\" on the other's live routines; apply one, merge it, then apply the next"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-15T08:32:55.547Z
---

**What happens.** The CI check "the database is running what this repository says" compares production against the
PR's own branch. If PR A and PR B are both applied to the single production database before either merges:
- A's branch lacks B's routines, so A goes red on "production has routines with no canonical file";
- B's branch lacks A's routines, so B goes red the same way.

Neither can go green by itself. Every other open PR also goes red, because main has neither.

**Happened twice on 14 Sep 2026:**
- **#661 / #673:** #661's routines were live, so #673 was red; #673's preview fix was missing on #661, so #661 was red.
- **#676 / #672:** #676 was red on #672's 13 `fn_backup_prune_*` routines plus 2 drifted registry routines; #672 was
  red on `fn_accountant_statement_reader_defects`.

**How to apply:**
- Serialize production applies. Apply one PR, merge it as soon as its check is green, then apply the next. Parallel
  helpers may build and review in parallel, but applying is a queue ([[parallel-agents-must-not-do-git-in-a-shared-tree]]
  is the same principle for git).
- If it has already happened, don't force-merge a red check. Merge one PR's branch into the other (never rebase or
  force-push) so a single PR carries both sets of routines. Put both PRs' MANIFEST lines last, in apply order, and
  regenerate the mirror. Merging that PR lands both, and the other closes as merged.
- Remember main goes red too while a PR is applied but unmerged. That's expected and clears on merge, but keep the
  window short.

- **PRs with no SQL go red too.** While ANY PR is applied but not merged, every other open PR fails the DB check. That includes pure code or test PRs, which carry no SQL at all. On 15 Sep, #712 and #708 had no SQL, yet their merge chains failed twice: first behind #710 (fn_gl_post plus two retired routines), then behind #709. Merge SQL-free PRs in a **quiet window**: after one applied PR merges and BEFORE the next apply. Pattern: apply A → merge A → update-branch and merge each SQL-free PR → apply B.

Related: [[check-a-prs-base-before-merging]], [[new-sql-file-needs-a-manifest-line]].
