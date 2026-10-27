---
name: a-branch-can-silently-revert-main
description: "27 Oct 2026: PR #1672's commit deleted an applied data file, two MANIFEST lines and a mirror routine that main already carried. Its diff against main showed it, but the PR's own story did not. Review the whole diff against main, not just the files the PR means to change."
metadata:
  type: feedback
  modified: 2026-10-27
---

#1672 meant to add 8 lines to an alarm register. Its branch had been built from a tree in which #1661 and #1670 were
not yet merged, and the author committed that tree wholesale. Against main, the PR therefore:
- deleted #1661's applied data file and its probe;
- removed the MANIFEST lines for #1661 and #1670;
- re-created #1670's pending note;
- reverted the schema mirror's copy of the live delivery-watch routine.

The reviewer caught it and restored 7 paths from main.

**Why:** a PR's description says what the author intended. The diff against main says what merging will do. A stale base
turns every file the author did not mean to touch into a silent revert.

**How to apply:** a reviewer reads `git diff origin/main...HEAD --stat` first, and every path that is not in the PR's stated scope
is a finding until explained. An author re-merges main before pushing and never commits a whole tree they did not change.
See [[diff-sql-against-live-production-not-the-mirror]].
