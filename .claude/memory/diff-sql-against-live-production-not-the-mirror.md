---
name: diff-sql-against-live-production-not-the-mirror
description: "27 Oct 2026: a reviewer passed #1660 by diffing against a stale schema mirror; applying it would have removed #1644's live v_test branch from fn_sales_assist. Diff every CREATE OR REPLACE against live pg_get_functiondef."
metadata:
  type: feedback
  modified: 2026-10-27
---

Two reviews of PR #1660 used `supabase/schema/full_schema/` in a worktree that predated #1644, and both passed it.
The file replaced four routines from that old copy. Applying it would have deleted #1644's live
`v_test` / `test_traffic` branch from `fn_sales_assist`. The release operator caught this by reading production,
not the mirror.

**Why:** the mirror is only as current as the last `export --write` on the reviewer's base. A PR that is
merged and applied but not yet in the reviewer's checkout is invisible there. `CREATE OR REPLACE` silently
reverts it.

**How to apply:** any review or author of a PR with `CREATE OR REPLACE FUNCTION` reads the live body
(`select pg_get_functiondef('public.fn_x(...)'::regprocedure)` through `scripts/lib/db.mjs`). The live body
must equal the file minus only the intended change. #1660 now carries the test that guards this: a file may not
drop any line of the live body it replaces. See [[regenerate-the-mirror-after-the-last-apply]].
