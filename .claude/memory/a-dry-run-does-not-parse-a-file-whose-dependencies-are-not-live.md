---
name: a-dry-run-does-not-parse-a-file-whose-dependencies-are-not-live
description: "apply_sql's dry run stops at the first missing dependency, so a multi-file PR's later files are never parsed by Postgres until the real apply"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-14T18:12:07.272Z
---

14 Sep 2026, PR #645 (accountant duties, 11 SQL files in MANIFEST order). Every dry run "passed its guards", but nine of the eleven only got as far as "calls a routine another file defines, not live yet". Postgres never saw them. At the real apply, the_accountant_chases_what_a_silent_supplier_owes.sql was refused twice, at lines 200 and 231, for "mismatched parentheses": an extra `)` closing a nested jsonb_build_object. By then files 1-2 were already live, so production was half-applied until the fix.

**Why:** a dry run proves nothing about syntax for any file behind an unapplied dependency. A green dry run on a dependent chain is not evidence.
**How to apply:**
- apply a multi-file PR file by file in MANIFEST order, stopping at the first failure (loop that greps `^APPLIED`), and fix forward;
- before applying, grep the files for lines ending `)));` and count each nested jsonb_build_object;
- tell builders to count parentheses themselves.
Related: [[new-sql-file-needs-a-manifest-line]], [[check-a-prs-base-before-merging]].
