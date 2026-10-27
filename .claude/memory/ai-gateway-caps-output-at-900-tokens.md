---
name: ai-gateway-caps-output-at-900-tokens
description: "ai_gateway returns ~900 output tokens whatever `max` the caller asks for — measured at 1,100, 3,000 and 4,000, all 900 with finish_reason \"length\"."
metadata: 
  node_type: memory
  type: project
  originSessionId: b8f9a77d-66be-4ac4-aff5-ec6af2024801
  modified: 2026-08-14T09:39:55.602Z
---

14 Aug 2026, building `agent_train`. Answers kept arriving cut off mid-JSON, so the parser
returned `{}` and the grader honestly reported "the answer is empty" — which read as the agent
failing when it had in fact written a good answer.

Measured: `max: 1100` → 900 output tokens. `max: 3000` → 900. `max: 4000` → 900. Every one with
`finish_reason: "length"`. The ceiling belongs to the gateway (its own `model_policy` row for
the resolved `task_class`), not to the caller, and raising the request does nothing.

**Why:** a caller that trusts its own request parameter will keep raising it, keep getting the
same truncation, and blame the model or the prompt.

**How to apply:** design any gateway caller to survive a ~900-token answer — ask for a compact
shape and parse defensively. Better still, do not require the response to be well-formed JSON at
all: `agent_train` grades the RAW text, so a truncated answer is still scored on the moves it
made. Read `finish_reason` and `truncated` on every response before concluding anything about
quality. The gateway also names its fields `prompt_tokens` / `output_tokens` / `cost_usd` — not
`input_tokens` / `cost_aed`, which read as `undefined` and logged every call at zero cost.
Related: [[an-error-string-that-was-our-own-timeout]], the same lesson one layer up.
