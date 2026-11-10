---
name: an-edge-call-runs-where-its-caller-is
description: "10 Nov 2026: WhatsApp replies took p50 32 s. A Twilio webhook enters at us-east-1, so wa_inbound, ai_gateway and embed_ml all ran there while the database is in ap-southeast-1: ~3 s of gateway work per model call before the provider was asked. Function-to-function calls now name forceFunctionRegion=ap-southeast-1 (_shared/db_region.ts)."
metadata:
  type: feedback
---

**What was measured (10 Nov 2026, customer_support, read-only; walks fbc40fbd and f5d32825).** Supabase runs an edge function in
the region nearest its CALLER. The database is in ap-southeast-1. Twilio, the walks' driver and US cron callers enter at us-east-1,
and a function they call calls the next one from there, so the whole chain ran in Virginia and every database trip crossed the
Pacific (~0.2-0.25 s each).

- ai_gateway's own work BEFORE the provider call (agent_runs fn:ai_gateway joined to llm_attempt, 7 days): **p50 3,337 ms in
  us-east-1 (n=1,788) against 357 ms in ap-southeast-1 (n=534)**. A gateway call refused before any model: p50 2,733 ms vs 391 ms.
- embed_ml: p50 916 ms vs 170 ms, and all 419 of its 546s (WORKER_LIMIT) in the walks' hour were us-east-1 workers.
- With the model cap hit (f5d32825 after 15:56Z, every call refused, no model time at all) a WhatsApp turn still took 29-37 s.

**The fix.** `_shared/db_region.ts` `inDbRegion(url)` adds `?forceFunctionRegion=ap-southeast-1`; `_shared/llm.ts` and
`wa_inbound/shared.ts` (ai_gateway), `_shared/ml_embed_client.ts` and `_shared/meaning_embed.ts` (embed_ml) use it. The callee
reads only the pathname, so nothing else changes. Keep the literal `'/functions/v1/<slug>'` in the caller's source:
`no_function_calls_an_undeployed_function` reads callees from it.

**Still open.** wa_inbound itself runs where Twilio enters (us-east-1) until the Twilio webhook URL carries the same parameter
(the signature check already signs the query string: `_shared/twilio_inbound_signature.ts signedUrlCandidates`). Other functions
that build their own gateway URL (quote_extract, license_extract, drawing_boq, site_assistant, ...) are not pinned yet.

**How to apply:** when a function is slow, read its edge region first (`function_edge_logs` `response.headers.x_sb_edge_region`,
or `agent_runs.counts.region`). Before adding a call from one function to another, pin it with `inDbRegion`. A per-call timing
that is mostly fixed overhead (the same ~2.5-3 s whatever the prompt size) is distance, not the model.

Related: [[a-chat-turn-is-one-streamed-call-on-a-clock]], [[whatsapp-reply-model-was-never-shown-the-conversation]].
