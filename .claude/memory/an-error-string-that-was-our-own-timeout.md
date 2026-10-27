---
name: an-error-string-that-was-our-own-timeout
description: "the model returned nothing" was an 8/10 client-side abort at exactly 72s — read latency_ms before believing any LLM failure message
metadata:
  type: feedback
---

`action_worker` logged 10 failures reading **"the model returned nothing"**, which reads as an
OpenRouter refusal. It was not. `ai_cost_log.latency_ms` on eight of the ten was **72,056–72,086 ms**
against a `makeLlm(..., { timeoutMs: 70000 })` — our own `AbortSignal`. One row said so outright:
*"ALL MODELS FAILED after the full ladder: The signal has been aborted."*

Cause: `max` was raised 900 → 8,000 tokens without raising the timeout. Successful calls ran 34.5s
to 72.0s for 2,762–6,138 output tokens, so **the harder the agent worked, the more likely we hung up
on it** — and the failure message blamed the model.

**Why:** an LLM failure string is written by our own catch block, not by the provider. It describes
what we observed (empty output), not what happened.

**How to apply:** before believing any LLM error text, check `latency_ms` against the caller's
timeout and `output_tokens` against the ceiling. A tight cluster at the timeout wall is ours. When
raising a token ceiling, raise the clock in the same change, and keep it under the caller's own
timeout — here `org_action_executor.timeout_seconds = 120`, so 105s. Related:
[[never-state-what-you-have-not-measured]], [[instruments-report-on-the-wrong-subject]].
