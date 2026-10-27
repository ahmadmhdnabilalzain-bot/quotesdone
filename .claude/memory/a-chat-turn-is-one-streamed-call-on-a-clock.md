---
name: a-chat-turn-is-one-streamed-call-on-a-clock
description: "27 Oct 2026: the portal assistant's turns took 58-150 s and one 504'd because the turn ran think() (3-5 serial model calls, no clock). A customer chat turn is ONE streamed conversation-route call inside a turn deadline; never a reasoning chain."
metadata:
  type: feedback
---

**What happened, 27 Oct 2026** (found while verifying ledger 1248). On production, a 12-turn ZZ DEMO wardrobe replay in the
customer portal took 58-150 s per turn, and turn 7 hit the edge's 150 s idle wall. The 504 page is not JSON, so
`PortalShell`'s `r.json()` threw and the customer saw "Something went wrong" partway through the conversation.

**Why it was slow** (ai_cost_log fn `sales_engineer`, 07:41-08:13Z). `sales_engineer` `assist` ran
`supportReply` → `think()`, which makes 3-5 SERIAL calls on gpt-6-luna-pro per turn:

- a plan (`routine_employee_reasoning`, 18-31 s);
- the answer (`customer_communication`, 13-48 s on a 35-62k-token payload that grew every turn);
- on 4 of 14 turns, a check plus a corrective rewrite (+40 s);
- on 8 of 14 turns, a plain-language rewrite (16-35 s).

Nothing bounded the whole turn. When the customer had quotes, a second think() decision (`quoteQuestion`, 40-60 s) also
ran before all of that. The website widget had already moved to one streamed call (#1330); the portal had not.

**The rule.** A customer conversation turn is ONE streamed call on the conversation route:
`_shared/brief_answer.ts`, class `customer_portal_assistant` / `visitor_chat` / `conversation_reply`, Sonnet 5.5 per
ruling 1219.

- Give it the company brief, the retrieved records and the customer's own data as FACTS.
- Check each sentence before it is shown.
- Pass a `deadline` (portal: `PORTAL_TURN_MS`, `sales_engineer/portal_turn.ts`), so every rung of the ladder is bounded
  and the gateway is told `client_timeout_ms`.

`think()` is for deliberate seat decisions, never for a chat turn. Its planner alone costs more than a whole streamed
answer.

**Measured on the same 12 EN + 12 AR script** (`docs/reports/chat-turn-latency-2026-10-27/`):

| | before | after |
|---|---|---|
| p50 | 78.6 s | 10.2 s |
| p95 | 150.3 s, two 504s | 13.0 s, 0 failures |
| first words | none until the turn ended | 7.6 s |
| cost per turn | AED 0.062 | AED 0.072 |

**A streamed reply must be plain text.** `aiSystem` asks for JSON unless it is passed `plainText`; the first run showed
`{"answer":...}` on screen.

**How to apply:**
- Before adding any model call to a chat turn, add up the worst case of every serial call against the 150 s edge wall.
  A per-call timeout is not a turn budget.
- A client must never `r.json()` a function response unguarded. A 504 is HTML. Use `src/lib/portalReply.ts`
  (`readReply`), which never throws, shows only approved text, and falls back to looking for the stored answer.
- Measure per turn from `ai_cost_log` (task_class, latency_ms, prompt_tokens) next to `agent_runs` `fn:<slug>`
  `counts.ms`. The gap before the first call's start is the pre-model time.
- A replay killed before teardown leaves fixtures and chat rows behind. Turns in flight still land on the server. Clean
  up by the run's exact tag, its customers' ids and its full scripted question list, then prove 0 remain.

Related: [[an-error-string-that-was-our-own-timeout]], [[an-edge-function-has-a-cpu-cap-a-deadline-does-not-bound]],
[[ai-gateway-caps-output-at-900-tokens]], [[chat-model-candidates-only]].
