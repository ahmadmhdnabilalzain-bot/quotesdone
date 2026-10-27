---
name: openrouter-reports-cache-under-prompt-tokens-details
description: "OpenRouter reports prompt-cache hits at usage.prompt_tokens_details.cached_tokens, not at the top level — and cache_control only pays on a byte-stable prefix."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 71e4809a-7cb5-4158-86a9-7a2a2e63b4d5
  modified: 2026-08-11T09:03:28.814Z
---

OpenRouter's chat/completions response reports prompt caching **only** under
`usage.prompt_tokens_details.{cached_tokens, cache_write_tokens}`. There is no
top-level `cached_tokens` or `cache_read_input_tokens`. Reading the wrong name is
how QuotesDone measured "0.19% of calls cached" for weeks while caching was on.

Measured 11 Aug 2026 on `anthropic/claude-sonnet-5` (Bedrock), two identical calls:
2,697 prompt tokens cost **$0.0108 → $0.0006**, an 18x drop on a cache read.

Cache economics, and the arithmetic that decides the TTL:
- default (5-minute) block: write 1.25x input rate, read 0.10x → break-even at a **22%** repeat rate
- `ttl:'1h'`: accepted by OpenRouter (HTTP 200), write **2.0x**, read 0.10x → break-even at **53%**

`cache_control` only ever pays on a prefix that is **byte-identical** between
calls. Marking a prompt whose tail carries live numbers or `now()` buys a write
premium on every call and a read on none — worse than not caching at all. Split
the prompt and mark only the stable half. See [[quotesdone-definition-of-done]].
