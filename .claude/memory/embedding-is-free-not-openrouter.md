---
name: embedding-is-free-not-openrouter
description: "kb_embed uses Supabase's in-region gte-small, not OpenRouter — embedding the corpus is a throughput problem, never a spend decision."
metadata: 
  node_type: memory
  type: project
  originSessionId: 03690ce0-a2c8-41da-b9d4-9343ce87c730
  modified: 2026-08-10T14:38:27.527Z
---

`kb_embed` builds a `Supabase.ai.Session('gte-small')` and runs it inside the edge worker. It
never calls OpenRouter. Embedding all 115,148 pack records costs nothing beyond compute already
paid for, so any brief that frames it as a spend decision on the OpenRouter balance is wrong on
the facts — the part-9 brief did, on 10 Aug 2026.

The real constraint is throughput, and the lever is more INVOCATIONS, not a bigger batch: each
invocation is a fresh worker with its own model session, and the session's allocation grows with
each `run()` inside one invocation. **A batch above 5 returns HTTP 546 WORKER_RESOURCE_LIMIT.**
The comment in `kb_embed/index.ts` reading "limit 40 -> 546, limit 20 -> 546, limit 10 -> 546,
limit 8 -> 546, limit 5 -> 200" lists HTTP STATUS CODES, not row counts — misreading it as row
counts collapsed the rate from 164/min to 17/min.

Measured working configuration: the original once-a-minute job plus `kb_embed_backfill_boost`
firing six posts a minute at `limit 5` → ~31/min, zero 546s.

**Why:** two sessions in a row have treated a free operation as a money decision and deferred it.
**How to apply:** check whether the model is in-region before calling anything a spend decision;
if the rate matters, add invocations and leave the batch at 5.

Related: [[quotesdone-definition-of-done]], [[session-briefs-carry-misdiagnoses]]
