---
name: the-engineer-and-support-reply-only-through-the-model
description: "27 Oct 2026, founder_instruction 1339 — every customer/supplier reply from sales_engineer and customer_support is written by the model via OpenRouter; a code-written reply only when the OpenRouter call failed"
metadata:
  node_type: memory
  type: feedback
  modified: 2026-10-27T15:00:00.000Z
---

The founder, 27 Oct 2026 ~14:15Z (ledger 1339), verbatim:

> "the engineer and customer support never replies without llm unless the server of open router is down"

**Meaning.** Every message the `sales_engineer` or `customer_support` seat sends to a customer or supplier is written by
the model, called through ai_gateway → OpenRouter. Code may still decide WHAT to say (the question, the slot, the
checklist options, a routine's result), compute data, validate and filter the model's output, and drop an unsafe
sentence. The words the person reads are the model's. A code-written or templated reply is allowed ONLY when the
model call FAILED: a network error, a 5xx, a timeout or the turn's deadline, an open provider circuit (the founder's hold
included), or no credential to reach the gateway.

**Not an outage** (so never a licence for code text): a model that answered and whose answer was refused by a guard,
was unparseable, was wrapped in JSON, or was dropped sentence by sentence; a 4xx; one sender's rate limit (that is a
status notice, not a reply).

**How it is built (PR "replies only through the model", 27 Oct 2026):**
- `supabase/functions/_shared/openrouter_down.ts`: `isOpenRouterDown(error, http)` is the one test;
  `modelOrOutage(r, codeText)` is the one sanctioned door for a code fallback.
- `aiReply` returns `outage` (true only when no call reached a model), keeps the model's own passing sentences when no
  whole draft passes (`salvage`), and takes `must` (a reference or job number the reply has to carry).
- WhatsApp's HELD_NOTICE and the supplier quote review's QR_HELD_NOTICE go out only on an outage; otherwise nothing
  conversational is sent and the turn is queued for the model replay. The WhatsApp case and accepted-offer
  confirmations are written by the model (`must` carries the reference).
- The request chat (inquiry_intake) landed with the intake turn clock on PR #1646 (commit a78b6e731): HELD_FOR_SPECS
  and every sentence code composes (interview, replyFromState, the four questions' lead, drawing confirm, CAD ask,
  held-for-trade) are written by the model through `slots.ts intakeVoice` on `clock.replyDeadline()`; the draft only
  `if (llmDown)`.
- The guards: `scripts/checks/replies_are_written_by_the_model_unless_openrouter_is_down.test.mjs` (WhatsApp, supplier
  thread, shared writer) and `scripts/checks/the_intake_reply_is_the_models_unless_openrouter_is_down.test.mjs` (the
  intake, on #1646). Each fails on the pre-fix code and has known-bad controls.

**Notifications stay templated and are not replies**: OTP, receipts, status pages, proactive spec-offer/reminder
messages, the supplier's submission receipt, the closed-thread notice, the founder's FIGURES, menu list frames that
Meta's approved Content template fixes. If a new path answers a person's message, it is a reply and this rule applies.

**The other half: never silent (the asynchronous re-ask, 27 Oct 2026).** "No code text while the model is up" left a gap:
a turn whose every draft was refused got NO reply (independent review of #1640). Now such a turn is filed in
reasoning_held_question on a re-ask surface (`_shared/reask.ts` REASK_SURFACES = SQL `fn_reask_surfaces()`: WhatsApp,
the supplier quotation thread, the portal chat, the request chat's held-for-trade turn). pg_cron `reask_refused_turns`
checks every minute; sales_engineer `reask_turns` asks the model again on the other family first, high effort, with the
refused drafts' problems named, runs every guard again (customerSafe re-run for the portal), and delivers into the same
conversation, once (`fn_reask_record` 'sending'). 3 refusals -> the owning seat (held_question); a reviewed reply goes
back through `fn_reask_reviewed_reply` and the same gates. The portal and the request chat show "still working on your
answer" (UI state) and poll. The 15-minute holding notice (`reasoned_delivery.holdingNotice`) is model-written too; its
fixed line only on an outage. Any NEW reply surface that can refuse must file its turn the same way.

**How to apply:** before adding any text a customer or supplier reads in answer to their message, route it through the
model with the decided content as facts; keep a code fallback only behind `outage` / `modelOrOutage`. Related:
[[customer-support-better-than-amazon]], [[openrouter-stays-on-all-tests-with-ai]], [[routine-work-is-code-not-llm]]
(routine operations stay code; conversation is the model's).
