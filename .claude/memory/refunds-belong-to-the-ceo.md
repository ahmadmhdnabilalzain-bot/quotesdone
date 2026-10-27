---
name: refunds-belong-to-the-ceo
description: "8 Sep 2026 — ALL approvals are the CEO's, including refunds; nothing is reserved to the founder any more"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-08T01:51:24.955Z
---

Founder, 8 September 2026, in two messages minutes apart:

> **"refunds belong to the CEO from now on."**
> **"all approvals are from CEO. nothing goes to me."**

**Why:** he is building a company that runs without him. Refunds were the last thing reserved to him
personally, and he has now removed that and every other approval from himself. The founder is not an
approver in this system; he is its owner.

**How to apply:**

- This SUPERSEDES [[every-refund-needs-the-founder]] (17 Aug) and the "only refunds reach the
  founder" boundary in [[launch-governance-loop-closed]]. Do not cite either as a live rule.
- It also supersedes `.claude/skills/quotesdone-session/SKILL.md` §3, which named Stripe refunds as
  the ONE thing requiring his approval. **Nothing requires his approval now.** The three escalation
  cases that remain are unchanged in kind but not in this direction: destructive production changes
  and facts only he holds (tokens he must mint, commercial intent). Money decisions inside the
  business go to the CEO seat.
- The old implementation must be dismantled, not re-pointed: `refunds.refund_decision_id` FK into
  `phase_c_refund_decision`, the BEFORE trigger `fn_phase_c_refund_execution_requires_decision`,
  `founder_approval_request`, `fn_founder_queue`, `fn_founder_approval_refund_only`,
  `fn_kernel_founder_routing_is_refund_only` and the `phase_c_action_class` boundary were all built
  to route approvals TO him.
- The CEO decides through its own typed tools — `fn_ceo_request_decision`, `fn_ceo_decide_refund`,
  `fn_refund_execute_authorized` (which takes neither a destination nor a decision parameter,
  deriving both) — on CEO-owned tables.
- **Removing his approval is not removing the controls.** A decision record, an amount ceiling, an
  authority ladder and an audit trail all still belong in the CEO's own tables. He removed a person
  from the loop, not the loop.

Paired ruling the same day: **"for the new CEO we will build proper tables and edge functions and
everything. we dont rely on the old structure"** — so all of this is re-homed under new CEO-owned
objects, never by keeping a Phase C table alive as their landlord.
See [[the-ceo-seat-has-tools-but-no-runtime]].

Founder mail still exists as NOTIFICATION, not approval: he is told things, he does not gate them.
See [[founder-mail-goes-through-founder-mail-policy]].
