// ai_gateway — THE single AI router. Every model call in the company should come through here.
//
// WHY THIS EXISTS. Before it, ~68 edge functions called OpenRouter, 37 of them with their own
// hand-rolled fetch. Those 37 are invisible to ai_cost_log, so the company could not even see what
// it was spending, let alone control it. model_policy held 26 carefully written routing rules that
// had never executed once, because _shared/llm.ts only consults them when a caller passes taskClass
// and no caller did. The result: 100% of measured calls went to Sonnet or Opus, there was no cheap
// tier in existence, the cache had zero rows, and the budget halt was unreachable.
//
// This function is where all of that becomes real, in one place, so behaviour can change without
// redeploying 68 functions.
//
// 29 JUL 2026 — MODALITIES. The first migration wave stalled with ~33 functions still calling
// OpenRouter directly, and it was not stubbornness: the gateway could only carry plain text.
// Anything needing eyes (a scanned trade licence), ears (Arabic/English voice notes), the web
// plugin (grounded UAE research) or tool-calling (the Secretary) had nowhere to go. Rather than
// leave a third of the company's spend unmeasured, the gateway now carries all four, and
// CAPABILITY is a routing input: fn_ai_route substitutes a capable model rather than letting the
// provider reject the payload. The caller does not declare its needs - we infer them from what it
// actually sent, because a caller that has to remember a flag will eventually forget it.
//
// ORDER OF OPERATIONS — cheapest possible outcome first, every time:
//   1. rate limit        - refuse abuse before spending anything
//   2. Level 0           - templates and the approved FAQ answer with NO model at all
//   3. routing           - fn_ai_route picks the tier from the calling function or task_class,
//                          then substitutes for capability if the payload needs it
//   4. refusal           - tier='none' means deterministic code is correct; we decline
//   5. (no budget halt)  - removed 24 Sep 2026, founder_instruction 987: no caps on LLM spend
//   6. cache             - exact hash, then SEMANTIC similarity on free in-region embeddings
//   7. the call          - with Anthropic prompt caching, a hard token cap, and a model ladder
//   8. log               - real cost from model_registry, including cache-read pricing
//
// dry_run:true runs 1-6 and returns the decision WITHOUT calling a model, so the whole thing can be
// verified for zero spend.
// The request handler (the ordered stages above) is handle.ts; shared.ts, body.ts, payload.ts, confidence.ts and caller.ts hold what it uses.
import { annotate, observe } from '../_shared/observe.ts';
import { claimedCaller } from './caller.ts';
import { handle } from './handle.ts';

Deno.serve(observe('ai_gateway', async (req) => {
  const claimed = claimedCaller(await req.clone().json().catch(() => ({})));
  return annotate(await handle(req), claimed);
}));
