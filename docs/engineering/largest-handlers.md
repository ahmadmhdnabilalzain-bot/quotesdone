# The two largest handlers, and how to split them

Owner: it_engineer. Measured 10 Nov 2026 (base `origin/main` 6f9ebbd9b), `wc -l` over every non-test, non-fixture,
non-vendored `.ts`/`.tsx` in `supabase/functions` and `src`. **Proposal only: neither file is split here.** Both are on
the hot path (every customer turn, every model call), so each split is a PR of its own with the behaviour pinned first.

| lines | file | what it is |
|---:|---|---|
| 1,124 | `supabase/functions/inquiry_intake/handle.ts` | the customer's intake conversation: one `handle(req)` of ~1,080 lines, one turn end to end |
| 898 | `supabase/functions/ai_gateway/handle.ts` | the model gateway every seat calls: one `handle(req)` of ~880 lines |

(Larger files exist but are not handlers: vendored WASM bindings under `_shared/vendor/`, and `src` copy tables.)

## How each split should be done (the order matters)

1. **Pin the behaviour before the move**, the way `accountant/actions_contract.test.ts` pinned the accountant split on
   9 Nov (it drove the real handler over a stubbed `fetch`, passed on the single file, and was proved to bite).
2. **Move code verbatim** into stage modules; the handler becomes the sequence of stages. A stage takes and returns one
   explicit turn/request object instead of closing over the ~40 `let`s the single function shares today.
3. **Repoint the checks.** 9 checks read `functionSource('inquiry_intake')` and 9 read `functionSource('ai_gateway')`;
   `functionSource` reads the whole folder, so a move inside the folder keeps them asserting (see
   `.claude/memory/checks-read-split-code-through-a-sources-helper.md`). Run them before and after.
4. Deploy and read back the one function, then measure a live turn (intake) or a call per route (gateway) the same day.

## inquiry_intake/handle.ts: one customer turn

Already beside it: `classify.ts`, `interview.ts`, `knowledge.ts`, `llm.ts`, `shared.ts`, `slots.ts`, `supplier_count.ts`,
`turn_clock.ts`, and 11 tests (`journey_a_replay`, `generators_replay`, `conversation_holds_together`, `turn_clock`,
`the_cap_and_the_carry`, `the_expert_advises_and_places_the_trade`, and others). The body reads as thirteen stages:

| lines (today) | stage | proposed module |
|---|---|---|
| 41-65 | method, user, a re-ask poll answered from the row, rate limit | `turn/entry.ts` |
| 66-132 | the customer record, the draft (carried from the portal or new) | `turn/draft.ts` |
| 133-227 | request state, taxonomy, turn placement and retry, the handoff/over short-circuit | `turn/placement.ts` |
| 228-374 | trade, checklist, ordered questions, the specialist, its knowledge (four reads started together) | `turn/context.ts` (extends `knowledge.ts`) |
| 375-474 | the prompt: state, the expert's options, identity block | `turn/prompt.ts` |
| 475-568 | the model call, OpenRouter-down and founder-hold paths, the trade reasoned only when absent | `turn/model.ts` (beside `llm.ts`) |
| 569-753 | slots merged, trades kept, the semantic shadow interpreter, status | `turn/reading.ts` (beside `slots.ts`) |
| 754-896 | ONE DEFINITION OF READY, the requirement answers, the BOQ and CAD questions | `turn/readiness.ts` |
| 897-1012 | the brief and the readiness bar | `turn/brief.ts` |
| 1013-1077 | the reply in the model's words, the reply guard, never an empty bubble | `turn/reply.ts` |
| 1078-1122 | the run log, the state patch, the QA line | `turn/persist.ts` |

The risk is the shared mutable state (`category`, `checklist`, `status`, `out`, `brief`, `nextQuestion` are reassigned
across stages): carry them on one `Turn` object and let each stage's signature say which fields it reads and writes.
`turn_clock.ts` already measures each stage's time, so the split can keep the per-stage laps it records today.

## ai_gateway/handle.ts: one model call

Already beside it: `body.ts`, `cache_hit.ts`, `caller.ts`, `confidence.ts`, `payload.ts`, `provider_privacy.ts`,
`shared.ts`, `stream_usage.ts`, `system_message.ts`, and 6 tests including `drill_provider_faults.test.ts`. 97 files
outside the folder call it, so its request and response contract must not move by a byte.

| lines (today) | stage | proposed module |
|---|---|---|
| 43-56 | `action: 'embed'` handed to embed_ml | `embed.ts` |
| 57-132 | rate key, the stable and volatile halves, the shared prefix | `request.ts` (beside `body.ts`) |
| 133-238 | the route, and a review routed away from its author's family (never unreviewed) | `route.ts` |
| 239-354 | the semantic cache, the run-tag proof, "our own work" | `semantic_cache.ts` (beside `cache_hit.ts`) |
| 355-432 | prompt caching, the wall budget, the breaker's entry point | `budget.ts` |
| 433-537 | KERNEL K12 (the one fail-closed gate), the ladder, a reviewer that cannot be called is held | `gate.ts` |
| 538-787 | recording each attempt (billed failures get a ledger row), the provider loop, streaming | `attempt.ts` (beside `stream_usage.ts`) |
| 788-896 | usage and cache accounting, a fragment never stored for replay, the response | `accounting.ts` |

`gate.ts` is the one to move most carefully: K12 says there is only one gate, and a split must leave exactly one.
