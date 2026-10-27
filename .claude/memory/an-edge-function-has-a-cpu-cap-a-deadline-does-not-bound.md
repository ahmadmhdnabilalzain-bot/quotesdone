---
name: an-edge-function-has-a-cpu-cap-a-deadline-does-not-bound
description: "A Supabase edge function is killed (546 \"CPU Time exceeded\") by a per-request CPU cap that a wall-clock slice deadline never sees; the kill skips every finally/finding path, so a fix that adds CPU work can create a new SILENT failure"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-15T00:21:20.696Z
---

**What happened, 14–15 Sep 2026.** PR #686 fixed the daily table export: Cloudflare's WAF was refusing a
`kb_chunks` page that held OWASP SQL-injection text. The fix escaped WAF-trigger characters with a per-character
`wafSafeJson`. It was reviewed CLEAN, deployed as `backup` v9, and was correct. But it took 99–331 ms per page,
against 2–10 ms for `JSON.stringify`, so a hop of about 10 pages burned 1–3 s of CPU.

The next hop was killed at 00:14:39Z: 546, `CPU Time exceeded`. The hop's only budget was a 30 s wall-clock slice
deadline (`backup/index.ts:179`), which doesn't count CPU.

**Why it's worse than a crash:** a CPU kill ends the worker instantly. No `catch` or `finally` runs, so no
`settle()`, no failure mark and no finding. The day stays `running` forever. The attempt counter only goes up on
`failed`, so the retry cap never fires, and nobody is told. That breaks the founder's rule that an internal cause is
never silent (founder_instruction 208). Our own fix caused it. The first guess (that the deploy killed the hop) was
wrong. Measure; don't guess: [[never-state-what-you-have-not-measured]].

**How to apply:**
- Any per-item transform in an edge function hot loop (escaping, parsing, hashing, compression) needs a CPU budget,
  not only a wall-clock one. Bound work per invocation by bytes or items, and measure the per-item cost on real data
  before shipping.
- A review must ask: "What does this cost per call, and does it stay under the platform CPU cap on the largest real
  input?" A correct fix can still be a production outage.
- A chained or background job must detect its own silent death from OUTSIDE: the scheduler that resumes a stale
  `running` job must raise a loud finding (PR 2, "a stalled export day is never silent"), because the dying worker
  can't.
- After deploying a fix to a long-running job, watch it past the exact point it used to fail, and past a few more
  hops. "Deployed" is not "working": [[quotesdone-definition-of-done]].

Related: [[two-applied-prs-deadlock-each-others-database-check]], [[post-deploy-smokes-overlap-manual-e2e]],
[[zero-cannot-tell-a-dead-guard-from-an-idle-system]].
