---
name: the-prompt-diet-switches-and-where-the-tokens-go
description: "11 Nov 2026, ruling 1619: where the ~45k tokens per call go (think() settled facts + 12 rows a retrieval step), the prompt_diet switch registry, which cuts are ON (structural) and OFF (content, until scripts/eval/prompt_diet_eval.mjs passes)."
metadata:
  type: project
  modified: 2026-11-11
---

Report: docs/reports/2026-11-11-prompt-diet.md (it_engineer, branch it_engineer-prompt-diet). Measured on production, read-only.

- **The ~45k average is think() over internal seat duties, not the reply brief.** A think() call carries the settled facts
  (12.6-16.9k approx-tokens, about 20-27k billed on Luna Pro) on the plan, the answer and the review. The answer also carries
  every retrieved row: **12 rows a step, every step** (927 of 927 measured), 21-56 rows a run, 1.4-7.1 cited. The reply brief
  is 85-91% cache reads.
- **Luna Pro bills about 1.6 times `approxTokens`** for the same text (the same brief path: 42.3k on Sonnet against 67-73k on
  Luna Pro). Do not compare the two models' token counts as if they were one unit.
- **A review route's `cache` flag is the BASE route's** (fn_ai_route_review_for swaps only the model). A Sonnet pick on a
  Luna-primary class went uncached: 20 calls on 10 Nov, 0 read and 0 written. The gateway now takes the flag of the model it
  calls (`ai_gateway/route_cache.ts`).
- **One cache block per seat is never read by another seat.** The settled facts now travel as a shared head plus the seat
  card (`think/settled.ts` splitSettled), byte-identical overall.
- **Turning caching off for "sparse" classes is wrong.** Over 30 days caching paid on every Anthropic class but one (USD −0.13).
  Give the shared part its own breakpoint instead.
- **Switches:** `_shared/prompt_diet.ts`, overridden by the decision_policy row `prompt_diet`, no deploy needed. Structural
  switches are ON. The content switches stay OFF until the paid round passes (`node scripts/eval/prompt_diet_eval.mjs plan`,
  USD 1.34 expected): retrieval top rows, the reviewer reads cited sources only, and a trend relevance choice plans nothing.
  Never flip a content default in code.
- **Not cut, on purpose:**
  - History, under the 18 Oct "no turn limit" ruling (and the max is 12 turns in 30 days).
  - The planner's settled facts: on Luna Pro they warm the answer's prefix, so the net is about zero.
  - The English reply's Arabic guide: it is a cache read, and cutting it would split the shared block.
- **Claude Haiku 5.5** is only a candidate for internal reviewer and fallback work (pending SQL, unapproved and inactive). Ledger
  1217 keeps customer chat off the small Claude model. Related: [[openrouter-reports-cache-under-prompt-tokens-details]],
  [[the-tier-is-the-bill-not-the-prompt]], [[a-seat-plan-b-overrides-a-class-fallback-and-other-routing-eval-lessons]].
