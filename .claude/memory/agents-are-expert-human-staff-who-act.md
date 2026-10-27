---
name: agents-are-expert-human-staff-who-act
description: "Founder's rule — treat every agent as an expert real human staff member who ACTS; build for agency, not just knowledge."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-01T21:25:20.430Z
---

Founder's standing rule (2 Sep 2026): **"always consider every agent as an expert real human staff. this is a rule. accordingly when you build something you have to keep that into your consideration. a real human staff will always act so our agents should as well."**

**Why:** the company is an autonomous org of AI employees (see [[autonomous-company-is-the-standard]]). An agent that only *knows* things, or that sits dormant, is not doing its job — a real expert employee **acts**: they monitor, investigate, decide, respond, remediate, follow up. Knowledge (Step 2/3) is necessary but not sufficient; the agent must be wired to ACT on it like the professional it represents.

**How to apply — every time you build:**
- Build for **agency**, not just awareness. Ask: "what would a real expert human in this role DO here?" — then wire the agent to actually do it (real actions, real effects), not just observe or advise.
- A security analyst actively watches logs, catches intrusions, opens incidents, and responds — so our security agent must actively detect + respond, not just hold security knowledge. Same for every role.
- The deterministic parts of the job (routine monitoring, pre-authorized responses, raising alerts, opening tickets) should ACT **now**, without waiting on inference — a real employee doesn't stop working because a decision is hard. The judgment layer (reasoning) adds on top when the runtime is on; it does not gate the whole role into dormancy.
- Never deliver a "knows but does nothing" capability and call it done. That is not how a real staff member behaves. Relates to [[build-the-connection-even-without-data]] / the "build the connection even with no real data" rule — build the acting connection, so the agent behaves like the expert human it is.

**"Act" means SOLVE it — not notify the founder** (founder clarified 2 Sep 2026: *"by act i mean it, its not that they just send a notification on my email for me to open a session with you to solve it."*). The agent must actually do the remediating work: the security agent stops the attack / closes the door / rotates the key; the eng agent diagnoses, fixes, and deploys the bug fix. An alert or email is a RECORD of what the agent did, never a substitute for doing it, and never a hand-off asking the founder to solve it with Claude. Escalation to the founder is the exception, reserved ONLY for his true boundaries — money/refunds ([[every-refund-needs-the-founder]]), destructive production changes, and decisions only he holds ([[founder-sets-boundaries-not-methods]], [[dont-ask-him-technical-questions]]) — never the default disposition. Building "detect → email the founder" is a failure of the rule; build "detect → the agent resolves it".

**The IT/eng/security department owns ALL technical issues, end to end, autonomously** (founder, 2 Sep 2026: *"anything related to IT should be handled by that department… if suddenly a customer is trying to pay but stripe is hanging or lagging, the agent need to solve it. in real life no IT department will communicate with the founder to solve an issue."*). Concrete bar: a payment hanging / Stripe lagging → the IT agent detects, diagnoses, and resolves it (retry/failover/fix/deploy) in the moment — the founder is never the one who solves a technical problem. This means building the department a real operations loop: monitor → open an incident owned by an IT agent (never the founder) → resolve via deterministic playbooks now (retry, roll back, close a door, apply a known fix) and via judgment when the runtime is on → verify. The founder is out of the technical loop entirely.

**This applies to EVERY department, not just IT** (founder, 2 Sep 2026: *"the same applies to all agents in their respective departments"*). Every department is a fully autonomous, self-solving team of expert staff that owns and resolves every issue in its own domain — finance handles finance issues, marketing handles marketing issues, procurement handles procurement issues — without the founder. The monitor → own → resolve → verify loop is the pattern for ALL of them. The founder reaches the operational loop of no department; only his true boundaries (§3 / money, destructive, his-decisions) ever surface to him. This is [[autonomous-company-is-the-standard]] in full.
