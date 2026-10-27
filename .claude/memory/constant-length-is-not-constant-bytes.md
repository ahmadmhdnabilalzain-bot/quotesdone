---
name: constant-length-is-not-constant-bytes
description: "The prompt-cache prefix was cut with left(x, 19500) and called byte-stable; it drifted four times in 45 minutes. Hash it over time before claiming stability."
metadata: 
  node_type: memory
  type: project
  originSessionId: 0ac5c5e2-c087-483c-b4d1-2cb949855d6b
  modified: 2026-08-14T04:14:49.172Z
---

14 Aug 2026. `fn_agent_context_capped` cut the cacheable half with `left(v_head, v_room)` and its
comment read: *"head is left() to a CONSTANT length, so for a given agent and budget these bytes
are identical on every call."*

Measured by hashing the first 19,500 characters returned for `procurement`:

    03:10  a7f351e…   03:18  03d7025…   03:30  d2eaa6c…   03:55  b26a841…

Four prefixes in forty-five minutes. At 03:55 three *different questions* returned the same hash,
so it was never query-dependence — it was time. The head carries `# YOUR CURRENT WORKLOAD (live)`,
the live risk register and `## Pricing & fees (LIVE — auto-synced)`, and `org_tasks` moved 999 →
1,014 in that window.

**Why it matters:** a provider prompt cache pays only on a byte-identical prefix. Turning
`prompt_cache_enabled` on against a block that moves would have bought a 1.25x cache WRITE on every
call and read none — raising the bill. The 0.1% hit rate in `ai_cost_log` was that fact already in
the ledger, and it was being read as "caching is off" rather than "caching cannot work here".

**How to apply:** never accept a stability claim from a comment or from one sample. Hash the block
across MINUTES, and separately across different inputs — they fail differently. If a generator has
live sections or `order by <non-unique key> limit N` (this one has ~a dozen), it cannot be made
deterministic and should not be asked to be: store the prefix instead and refresh it on a schedule.
That is `agent_context_head` + `fn_agent_context_head_refresh()`, refreshed 6-hourly.

Related: [[openrouter-reports-cache-under-prompt-tokens-details]] for the break-even arithmetic
(5-min TTL pays above 22% hits, 1h above 53%; measured here 34.5% / 72.7%).
