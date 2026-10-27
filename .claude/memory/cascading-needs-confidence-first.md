---
name: cascading-needs-confidence-first
description: Building the OpenRouter model cascade before the output contract carries a confidence increases cost instead of cutting it.
metadata: 
  node_type: memory
  type: project
  originSessionId: 0081aec4-fde6-48b7-8226-cd4e593cbe56
  modified: 2026-08-11T13:13:41.311Z
---

`model_fallback` is configured on **47 of 61** `model_policy` rows, so the cascade ladder looks ready
to switch on. It is not.

Measured over 7 days to 11 Aug 2026 (1,642 calls): **confidence is reported on 5 calls (0.3%) and on
0 of 622 `claude-sonnet-5` calls.** A confidence-gated cascade with no confidence escalates every
time and pays for both models.

The blocker is the output contract, not the router: `agent_brain` returns prose plus an
`@@ACTIONS@@` JSON tail, and `selfReportedConfidence()` only parses whole-JSON bodies.

**Why:** spec #8 §4 says "never directly call expensive models", so a session reading the spec will
reach for the cascade first. Doing it in that order raises the bill.

**How to apply:** make the model output carry a confidence before touching the cascade. The cheaper
lever meanwhile is the cache — `llm_cache` is fully built, has a `cache_ttl_min` on all 61 policies,
and holds 1 row / 2 hits / $0.00 saved, so 2 of 1,642 calls were hits. Related:
[[openrouter-reports-cache-under-prompt-tokens-details]].
