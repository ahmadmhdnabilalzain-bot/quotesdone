---
name: regenerate-the-mirror-after-the-last-apply
description: The schema mirror must be regenerated after the FINAL apply of a session, not mid-chain; and two API-heavy scripts must never run at once.
metadata:
  type: feedback
---

`supabase/schema/full_schema.sql` was regenerated, verified `identical: YES`, and committed —
and CI still failed with 22,269 differing lines, because two more increments (D24, D25) were
applied afterwards. **A mirror captured mid-chain is not a mirror.** Regenerate it as the LAST
action before the final push, after every `apply_sql --apply` in the session has landed.

Same session, same shape: the export regeneration and the Row #3 scorer and
`scripts/checks/run.mjs` all hammer the management API. Running any two together produced
18 x HTTP 429 and 19 "failures" that were pure throttling, and left the blueprint scorer at
122 of 152 items with no `N/152` line — twice. **Run them strictly one at a time**, and treat
any run without its own total line as a partial, never as a result. See
[[production-429-during-the-end-of-session-sweep]] and [[never-state-what-you-have-not-measured]].

Also: `pgrep -f` does not see node processes reliably in Git Bash on Windows, so a monitor that
waits on `pgrep` fires immediately and reports a partial file as a clean run. Wait on the output
file's line count going quiet instead.
