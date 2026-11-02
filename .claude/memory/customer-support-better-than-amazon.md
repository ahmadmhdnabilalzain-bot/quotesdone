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
- **Measured 27 Oct, evening (#1635 with #1640 merged, local serve):** 22 scenarios, 22/22 code gates, 0/22 at
  >= 95 %, mean 83 %; per-turn p50 11.5 s / p95 25.6 s, 0 lost turns. What is left: conversations that stall before
  the summary, timeline never asked, and re-asks in other words or Arabic word forms (code cannot see paraphrase).
  Evidence: `docs/reports/adaptive-conversations-2026-10-27/`.
- **The harness teardown does NOT remove a turn's chat side effects.** Every bank turn writes `assistant_logs`,
  `sales_decision_log`, `support_reply_readability`, and every unanswered question opens a `sales_knowledge_gap`
  row AND an `org_tasks` row (fn_sales_assist) - tasks nobody confirmed. Remove them after a run, matched by the md5
  of the bank's scripted texts (the read guard refuses the word "do" in plain text), then recount to 0.
- **27 Oct, late: what the portal asks next is CODE's, per trade (`sales_engineer/conversation_plan.ts`).** Every
  playbook section in `knowledge/brief/conversation/*.md` has a "Must-haves" line (slot ids, location and timing in
  each; `id [a|b]` = only once the customer's words name a or b). After each customer turn code computes filled slots,
  "to confirm" (asked, then unsure or skipped; or required next for two replies and still open), and the single next
  must-have (+1 optional); all in, or 6 replies, = the summary turn, which must ask "is this correct?". Re-asks are
  compared by the SLOT a question targets (Arabic normalised and stemmed, article-insensitive), not its words. Add a
  word to a detector in `CATALOGUE` when a run shows a question placed on no slot - that is how every deadlock began.
- **The bank's own fact patterns are the rubric, not the product.** Some must-haves fail `must_asked` because the
  bank's regex wants one wording (fire_alarm_office's tie-in wants "main panel"/"connect"; roof_waterproofing_ar's
  existing system wants الحالي, not حالي). Read the transcript before "fixing" the seat; never edit the bank to pass.
- **json_extraction runs on gpt-6-luna-pro in 7-13 s** (27 Oct): too slow for every portal turn; it is called only
  when two slots were asked and no detector read the answer. A fast route would need a model_policy row (SQL).
- **Founder ruling 27 Oct: the seat never replies without the model unless OpenRouter is down.** Code decides what is
  asked; every shown sentence is the model's (tested in portal_conversation.test.ts).
- **Measured 27 Oct, late (the plan, 6cf746dea, local serve):** the same 22: 0 stalls (was 8), timeline 21/22 (was 16),
  re-ask flags 14 (was 57), p50/p95 10.1/17.7 s; but 20/22 code gates, 0/22 >= 95 %, mean 76 % (was 83 %). The whole
  bank: 0/43, mean 76.5 %. What cost points: detector gaps that deadlock a turn (44-64 s, then a bare reply), "to
  confirm" items from other trades, and rigid labels (a doors-only job asked the kitchen layout). Next: when every
  question in a reply is dropped as a re-ask, skip the rewrite and move the slot to "to confirm". Evidence:
  `docs/reports/adaptive-conversations-2026-10-27/`.
- **Audit the filter's drops in agent_runs (`counts.dropped`, "<reason> | <sentence>") after every run.** The first
  audit found 4 false drops in 15.
