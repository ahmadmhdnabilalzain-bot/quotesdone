---
name: close-a-finding-by-its-exact-key-never-by-title-match
description: Close it_engineer_finding rows only by exact issue_key after proving the fix covers that key; a title/ilike sweep closed an unfixed finding on 15 Sep 2026
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-15T08:16:30.377Z
---

On 15 Sep 2026, after adding the charge.dispute.* events to the LIVE Stripe webhook, I closed findings with a sweep: `title ilike '%dispute%' or issue_key ilike '%stripe%webhook%'`. It matched two rows. `duty:payment:live:webhook` was fixed. `duty:payment:test:webhook` was NOT fixed, because the test-mode webhook was never touched. A false closure was on record for a few minutes, until I reopened it.

**Why:** a closed finding claims something is fixed. The founder's rule is "never state what you have not measured" ([[never-state-what-you-have-not-measured]]), and a closure is a statement. A fuzzy match can't tell live from test, or one table from its sibling.

**How to apply:**
- List the matching findings first, as a read-only step.
- Decide per issue_key whether the fix you made covers it.
- Close each one by exact key: `fn_it_engineer_finding_close('<exact key>', note)`. Never close in a loop over a pattern.
- If a closure turns out wrong, reopen it immediately with a note saying why, and tell the user.
