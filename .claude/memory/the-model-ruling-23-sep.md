---
name: the-model-ruling-23-sep
description: "The founder's model-per-seat ruling of 23 Sep 2026 (instructions 841 and 844) — GLM 5.3 Flash internally, Qwen 3.8 Max or GPT Sol 5.6 for anything customer-facing or Arabic, Opus as plan B"
metadata:
  node_type: memory
  type: project
  originSessionId: 8c4972a3-8a16-4cb0-a308-31a4f45e00bb
  modified: 2026-09-29T10:04:36.051Z
---

Founder ruling, 23 Sep 2026, instructions 841 then 844. He decided it himself and told me not to run a
comparison test first.

**Plan A.** `qwen/qwen3.8-max-0902` is the primary for the quote comparison and for the CEO seat, and
for anything else that needs real reasoning. `z-ai/glm-5.3-flash` wherever it is possible — "we want to
cut cost as much as possible".

**Plan B.** Opus 5 for everything that needs reasoning, GLM 5.3 Flash for everything that does not.

**The refinement that settled the split (844), after he checked the Arabic himself:** the line is the
audience, not the difficulty. *Internal* operations → GLM 5.3 Flash, it can do it. *Customer-facing,
anything involving Arabic, anything reading a document* → Qwen 3.8 Max or GPT Sol 5.6, whichever is
cheaper. I had told him GLM's Arabic would not hold at customer quality and he confirmed it
independently.

**Why it is not urgent that customers are on the better model yet:** he also said the first six weeks
are supplier registration only, suppliers deal in English, and there are no customers until roughly
1,000 suppliers are on.

**Prices that decided it** (USD per Mtok, in/out, read live off OpenRouter 23 Sep 2026): glm-5.3-flash
0.15/0.50 with a 1.31M window; qwen3.8-max-0902 2.00/6.00 with a 1M window and text+image+video;
gpt-5.6-sol 2.00/10.00; opus-5 5.00/25.00; opus-5.5 4.00/20.00. **Only the Gemini family carries
audio**, which is why `speech_transcription` is on gemini regardless of the ruling.

**WHOLLY SUPERSEDED 29 Sep 2026 by ledger 1056, the full seat matrix:**
- **CEO:** Opus 5.5 for hard tasks, Gemini 3.8 Flash for easy ones; plan B GPT 6 Luna.
- **Sales engineer:** Gemini 3.8 Flash for everything except the comparison report, which runs on Opus 5.5; plan B GPT 6 Luna.
- **Every other seat:** Gemini 3.8 Flash; plan B DeepSeek v4.1 Flash.

Review classes run on the author seat's plan-B family, which keeps the cross-family rule. The 23 Sep text below is history.

**Earlier (ledger 1055, folded into 1056):** the deep quote comparison (quote_comparison) runs on anthropic/claude-opus-5.5; everything else the sales engineer does runs on google/gemini-3.8-flash. It stays ONE seat: he accepted "no new technical-manager agent". Shared classes are split so the other seats keep the 23 Sep routes.

**How to apply it:** never write a model id into a seat. `llm_seat_binding` has no model column — it is
attribution only. Routing is `fn_ai_route(task_class, dept_key, …)` → `model_policy` →
`model_registry` → `llm_route_health`, with `model_policy_by_identity` as the second table
`fn_ai_route` reads. The matrix applied on 23 Sep is in [[checkpoint-23-sep-the-deep-audit-and-the-model-ruling]].

The routes are live and **the hold still stands** (`llm_route_health.open_until` = 2126-08-15). Opening
it is his, and so is `app_secrets.ceo_model_slot`. See [[never-raise-openrouter-again]] — never ask him
to raise the OpenRouter budget.
