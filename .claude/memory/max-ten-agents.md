---
name: max-five-agents
description: "Founder 1 Nov 2026 (ledger 1417) — at most 5 agents at once; simple tasks run on Sonnet. Replaces the limit of 10 (ledger 1280)"
metadata:
  type: feedback
  modified: 2026-11-01
---
**Run at most 5 agents or tasks at the same time, across the whole session.** This limit overrides "use max parallel agents".

**Current ruling, 1 Nov 2026 (ledger 1417):** *"5 agents limits is fine. and of course if there are simple tasks that sonnet can handle then definitely proceed"*

**Why:** the weekly Claude limit went in about 24 hours in the week of 26 Oct. The laptop transcripts measured 935M tokens on 26-27 Oct: 83% in Opus subagents, 94% cache re-reads, and up to 486k tokens per call on the largest run. Cloud sessions were not measured.

**How to apply:**
- Count running agents before launching one; queue anything beyond 5.
- Pass `model: "sonnet"` for simple work: searches, reads, measuring, mechanical edits, drafting. Keep Opus for design, hard debugging and independent review.
- One task per agent. Start a fresh agent for the next task rather than growing one run.

Related: [[always-max-parallel-agents]].

**History:**
- 23 Sep 2026: "you can use up to 10 agents maximum. keep that as a rule" (confirms ledger 942).
- 23 Sep evening: raised to 12. 23 Sep night: raised to 15.
- 26 Oct 2026: back to 10 (ledger 1280).
- 1 Nov 2026: 5. This is the limit now.
