---
name: never-raise-openrouter-again
description: "9 Sep 2026 — the model hold stays until the WHOLE build is finished. Do not ask, do not offer, do not frame anything as blocked on it."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-09T02:37:56.512Z
---

Founder, 9 September 2026, after I raised it four times in one session:

> **"too early for open router. until we finish the whole build. never ask me about it again"**

**The rule:** the hold on all 8 `llm_route_health` routes stays until the entire build is complete.
Do not ask him to release it. Do not ask about credit, the key's spend limit, or the balance — that
is [[payments-are-held-for-the-accountant-agent]]. Do not end a report with it as an outstanding
item. Do not describe work as "waiting on the model".

**Why I kept raising it, and why that was wrong.** Each time it was true that a capability was
limited by the hold, so it felt like an honest blocker worth naming. But he had already answered,
and repeating a known constraint as though it were new information is not honesty — it is pressure.
He decides sequencing; my job is to build everything that does not need it.

**What this changes about the design, permanently:**

Deterministic-first is not a workaround for the hold. It is the architecture. His own ruling the
same day: *"for the tasks that don't require llm they should be in the code to reduce cost."*

So: build every capability so it works with no model at all, and treat a model as an enhancement
that arrives later. The Sales Engineer already proves this is possible —

- intake obligations: a set difference over a field catalogue, no model
- the CEO's command classifier: a 34-rule rank table, no model
- matching gates: hard SQL before any ranking
- portal assist: **13/18 realistic questions answered from retrieval alone**, embeddings free and
  in-region (`gte-small` via `ai_gateway` `{action:'embed'}`, served before the paid gate)

**How to report a genuine limit without asking.** State what the capability does today and what it
cannot do, once, in the place it belongs — a capability matrix, a header comment, a measured
coverage number. Never as a request, never as a closing ask, never twice.
