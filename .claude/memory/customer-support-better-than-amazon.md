---
name: customer-support-better-than-amazon
description: "22 Sep 2026 (instr 781) — customer support runs with the LLM always on, better than the Amazon chat bot; proven by an automated scenario suite, never declared ready without it"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-22T16:59:18.740Z
---

The founder, 22 Sep 2026, after two WhatsApp replies leaked internal wording:

> "for customer support LLM should be active all the time otherwise there will be always a trick in the wording that will leak such replies. i cant be testing 500 scenarios … make sure that its built properly so that after we activate the LLM it doesnt act weird. our customer support agent should be extremely support[ive] and even better than amazon chat bot. our standards are much higher … otherwise dont say its ready."

**Why:** keyword and fixed-reply routing always has an edge case that produces an odd or leaky reply. He will not hand-test hundreds of scenarios.

**How to apply:**
- Customer support (WhatsApp, the site assistant, the social inbox, email replies) runs with a model grounded in company knowledge, once the LLM per seat is chosen.
- Keep the deterministic guardrails as a safety layer around the model, not as the conversation. They cover:
  - no internal figures or technical errors;
  - exact-trade claims only;
  - identity rules;
  - human handoff.
- Before calling it ready, build:
  - a written support standard that goes above Amazon-level;
  - an automated evaluation suite of hundreds of English and Arabic scenarios, graded automatically for groundedness, tone, no leaks, correct routing and handoff, and graded again after the model is switched on.
- Report the suite's score, not an opinion.
- Never say "ready" without it.
- Related: [[founder-plan-audit-then-llm-then-full-test]], [[code-extremely-well-built]].
