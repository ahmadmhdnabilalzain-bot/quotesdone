---
name: the-prompt-diet-switches-and-where-the-tokens-go
description: "11 Nov 2026, ruling 1619: where the ~45k tokens per call go (think() settled facts + 12 rows a retrieval step), the prompt_diet switch registry, which cuts are ON (structural) and OFF (content, until scripts/eval/prompt_diet_eval.mjs passes)."
metadata:
  type: project
  modified: 2026-11-12
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
- **The paid round ran 11-12 Nov (final audit; report section 8; USD 1.39; run tags `evaldiet*`). Nothing passed that a switch
  hangs on:** retrieval top rows FAIL (7 of 16 cases run), trend relevance without a plan FAIL (15 of 16 same choice), reviewer
  reads cited sources FAIL (4 of 6 verdicts agree). Haiku 5.5 passed as the reviewer of 60 short chat drafts and failed as the
  fallback of internal answers. All three content switches stay OFF and Haiku 5.5 stays unrouted.
- **The eval cannot pass anything as designed.** The same prompt asked twice (`--control`) failed the rule in 2 of 4 and changed
  its decision in 3 of 4; the judge reversed itself on 2 of 6 pairs it read twice. Each arm is asked once at temperature 0.2,
  and the rule needs every case equal. A second round asks each arm three times, runs the control beside every part, and
  judges by majority. Do not read the three FAILs as "the cut lowered quality".
- **An eval call is booked under the class of the step it IS.** knowledge_validation is a review class: an author row booked
  there with its own family as counterpart is flagged SAME_FAMILY_REVIEW, and the cross-family check fails on any such row for
  30 days. A sampled question is a fixture: think() holds it `fixture_no_spend` unless it runs inside `E2E_RUN` for a tag whose
  window is open. A cost row loses its tag when its window closes (even mid-call), and the cap reads spend by tag.
- **Qwen 3.8 Flash is slow and overthinks.** As the think() reviewer it took p50 53 s, p90 104 s (53 calls) against the 45 s a
  think() call is given; at high effort it can spend its whole budget reasoning and return nothing. As a judge it needs its own
  effort (medium, then low) and a 6,000-token answer budget. A judge must be shown the case context, the decision and the
  sources the answer was given, or it lists the case's own figures as violations.
- **At the class's high effort (ruling 1630) the internal answer on Luna Pro wrote 7.7k output tokens and took 62 s on average**
  (47 calls); the direct replay must send `effortFor(class)` or it does not measure the call production makes.
- **Claude Haiku 5.5** is only a candidate for internal reviewer and fallback work (pending SQL, unapproved and inactive). Ledger
  1217 keeps customer chat off the small Claude model. Related: [[openrouter-reports-cache-under-prompt-tokens-details]],
  [[the-tier-is-the-bill-not-the-prompt]], [[a-seat-plan-b-overrides-a-class-fallback-and-other-routing-eval-lessons]].
