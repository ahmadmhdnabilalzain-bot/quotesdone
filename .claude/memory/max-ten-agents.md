---
name: max-ten-agents
description: "Founder 15 Nov 2026 (ledger 1707) — up to 10 agents at once, replacing the 5 of ledger 1417; the model follows the task: Opus / Sonnet / Haiku 5.5 (ledger 1708)"
metadata:
  type: feedback
  modified: 2026-11-16
---
**Run up to 10 agents or tasks at the same time, across the whole session.** This limit overrides "use max parallel agents".

**Current rulings, 15 Nov 2026.** Ledger 1707: *"Use as many agents needed. I can't wait for this whole week to get over till we solve all what I've mentioned now. Use more agents, it's fine. Use up to 10 agents."* Ledger 1708: *"depending on the task complexity, you select the model. You have Opus 5.5, Sonnet 5.5, and Haiku 5.5."*

**Why the cap was 5 (1 Nov):** the weekly Claude limit went in about 24 hours in the week of 26 Oct. The laptop transcripts measured 935M tokens on 26-27 Oct: 83% in Opus subagents, 94% cache re-reads, and up to 486k tokens per call on the largest run. Cloud sessions were not measured.

**How to apply:**
- Count running agents before launching one; queue anything beyond 10.
- Pick the model by the task (1708): `haiku` for simple work (searches, reads, measuring), `sonnet` for moderate work (mechanical edits, drafting), Opus for design, hard debugging and independent review.
- One task per agent. Start a fresh agent for the next task rather than growing one run.

Related: [[always-max-parallel-agents]].

**History:**
- 23 Sep 2026: "you can use up to 10 agents maximum. keep that as a rule" (confirms ledger 942).
- 23 Sep evening: raised to 12. 23 Sep night: raised to 15.
- 26 Oct 2026: back to 10 (ledger 1280).
- 1 Nov 2026: 5 (ledger 1417).
- 15 Nov 2026: up to 10 (ledger 1707). This is the limit now.
