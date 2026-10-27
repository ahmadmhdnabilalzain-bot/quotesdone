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

## 27 Oct 2026 — the adaptive conversation bank (ledger 1200), customer_support
- The bank is `scripts/e2e/adaptive_conversation_bank.mjs` (43 scenarios, EN + Gulf Arabic, expert follow-ups,
  must-haves, wrong-spec traps, a changed mind). The harness is `scripts/e2e/live_seat_conversations.mjs`; the daily
  job runs `--slice today` (7 slices = the whole bank weekly), the weekly audit re-runs the gaps.
- **The portal chat is `sales_engineer {action:'assist'}`** (PortalShell.askAssistant), not `site_assistant` with
  path '/me'. The harness graded the wrong function until 27 Oct.
- **The portal turn is one streamed call** (#1640, merged into #1635): `brief_answer.ts` with the whole compiled
  BRIEF_TEXT (trade playbooks included), not supportReply/think. Portal-only rules live in
  `sales_engineer/portal_turn.ts` (clock, format, facts) and `sales_engineer/portal_conversation.ts` (the intake
  rule, the reply shape, what the customer already gave).
- **A prompt rule did not stop re-asks or unasked lines; code does.** "Never ask again" sat in aiSystem AND the intake
  rule and the model still re-asked in nearly every conversation. `heldState` lists the filled slots and asked
  questions for the model; `replyFilter` (brief_answer's `drop`) removes a re-ask, an unasked fee/turnaround/
  supplier-process line, a repeated greeting or restatement, and any question past the third, before it is shown.
- **A portal turn has 150 s.** Measured 27 Oct: plan + answer + check + corrective re-pass + plain-language rewrite
  ran past it on 9 of 10 conversations (HTTP 546 / no reply). Count the calls before adding one to the portal path.
- Spend: a text turn is about USD 0.05-0.07, a photo turn about USD 0.58 uncached; a full bank run does not fit USD 5.
