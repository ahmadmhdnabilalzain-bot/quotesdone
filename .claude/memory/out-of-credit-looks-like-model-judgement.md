---
name: out-of-credit-looks-like-model-judgement
description: "OpenRouter running out of credit presents as agents \"choosing not to use their tools\" — fast, cheap-looking, plausible answers with zero tool calls."
metadata: 
  node_type: memory
  type: project
  originSessionId: 681a6f7f-1c08-4a22-82b9-fb80cd8c8f0e
  modified: 2026-08-14T14:44:11.623Z
---

14 Aug 2026, mid-way through the V3 remediation regression run, every model route began failing at
14:24 UTC. The observable symptom was not an outage: agents returned **normal-looking answers in
6–17 seconds with zero tool calls**, where a healthy turn takes 27–111 seconds and executes 2–11
tools. It read exactly like a model declining to reach for its tools — the precise competency the
certification had faulted. It was billing:

> `{"message":"This request requires more credits, or fewer max_tokens. You requested up to 8000
> tokens, but can only afford 1454."}`

160 attempts, both rungs of the tool-capable ladder (`claude-opus-4.8`, `claude-sonnet-5`), all the
same message. The failure taxonomy had no class for it and filed all 160 under `unclassified`.

**Why:** an out-of-credit refusal arrives as a *provider response*, not a transport error, so the
gateway records a completion and the caller gets a plausible short answer. It is indistinguishable
from a model exercising judgement unless you read `llm_attempt.err_excerpt`. It also survives
retries identically, so a retry loop just burns the wall budget.

**How to apply:** before concluding anything about agent *behaviour* from a run, check
`select model_route, ok, count(*) from llm_attempt group by 1,2` for the run window and look for a
step change. A sudden collapse in tool calls plus a collapse in latency is the signature — treat it
as infrastructure until the error text says otherwise. `insufficient_credit` now exists as a
failure class (not retryable, opens the breaker on first occurrence) so it classifies itself. The
remedy is the founder topping up OpenRouter; it is money, so escalate rather than engineer around
it. Related: [[an-error-string-that-was-our-own-timeout]], [[a-30-day-total-is-not-a-run-rate]].
