---
name: idle-llm-spend-max-two-dollars
description: "Idle LLM spend must be ≤ USD 1-2/day BECAUSE the code is correct — NO caps, ceilings or key limits (founder 24 Sep)"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8c4972a3-8a16-4cb0-a308-31a4f45e00bb
  modified: 2026-09-24T09:46:11.238Z
---

Founder, 24 Sep 2026: with no customers or suppliers active, the company must spend at most USD 1-2 a day on the LLM. Then he ruled that this is **not enforced by a cap**: *"I don't want caps… It shouldn't reach the limit because the code is correct, not because we have a cap."*

**Why:** a cap interrupts real work. A high bill means the code is wrong (routine work sent to the model, internal work on an expensive model, re-filing loops, paid replays of test backlogs), and the fix belongs in that code.

**How to apply:**
- Never propose or build a daily AED ceiling, per-class or per-kind call caps, or an OpenRouter key limit.
- Make the code correct instead:
  - routine work is code;
  - internal think() runs on GLM;
  - dedupe, so nothing re-files;
  - test and fixture traffic never reaches a paid route;
  - the stale backlog is expired as a data-correctness fix.
- Keep the existing guards that are correctness, not budget:
  - fixture stubs;
  - at most 2 provider calls per request;
  - retry limits against infinite loops.
- After the OpenRouter top-up, measure idle spend per class from ai_cost_log and report it. If it is over USD 2, find the wrong code and fix it.

Related: [[routine-work-is-code-not-llm]], [[the-model-ruling-23-sep]].
