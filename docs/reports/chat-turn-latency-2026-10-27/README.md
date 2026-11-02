# Portal assistant turn latency, 27 Oct 2026

Seats: customer_support owns the conversation, and it_engineer owns latency. The defect was found while verifying ledger
1248. Branch `customer_support/chat-turn-latency-27-oct`. Per-turn evidence is in `turns.json`, next to this file.

## The defect

In the customer portal, assistant turns were slow and sometimes failed. A turn that reached the edge's 150 s idle wall
came back as a 504 HTML page. `PortalShell` called `r.json()` on it, which threw, and the customer saw "Something went
wrong" partway through the conversation.

## How it was measured

Both conversations ran in parallel:

- 12 English turns: a custom wardrobe;
- 12 Arabic turns: a kitchen.

Each conversation belonged to its own ZZ DEMO `@example.invalid` customer, inside a capped rehearsal window.

| | **Before**: production `sales_engineer` v308 | **After**: this branch, served locally against production data and the real ai_gateway |
|---|---:|---:|
| turns answered | 21 / 24 | **24 / 24** |
| failures shown to the customer | 2 × 504 `IDLE_TIMEOUT` at 150.3 s, 1 × 503 `BOOT_ERROR` | **0** |
| total per turn, p50 | 78.6 s | **10.2 s** |
| total per turn, p95 | 150.3 s (the wall) | **13.0 s** |
| total per turn, max | 150.3 s | 34.6 s (one turn; the guard asked for 2 model rewrites) |
| first words on screen, p50 / p95 | none: the old client waited for the whole turn | **7.6 s / 11.7 s** |
| first byte (status line) | at the end of the turn | **≤ 25 ms** |
| gateway calls | 66 for 24 turns | 26 for 24 turns |
| serial model time | 1,547 s | 188 s |
| model spend | AED 1.49 (≈ 0.062 per turn) | AED 1.72 (≈ 0.072 per turn) |

The two 504s were AR turn 6 and EN turn 12, the "summarise every spec we agreed" turn. That is the same turn that
failed in the 27 Oct 07:41Z replay.

## Where the time went before

The source is `ai_cost_log` for fn `sales_engineer`, from the run's own `e2e_run_tag`. Each turn ran
`supportReply` → `think()`, which is 3 to 5 serial model calls with no clock on the whole turn:

| step | class / model | n | p50 | p95 |
|---|---|---:|---:|---:|
| plan (decompose) | routine_employee_reasoning / gpt-6-luna-pro | 23 | 23.2 s | 27.2 s |
| answer, corrective rewrite, plain-language rewrite | customer_communication / gpt-6-luna-pro | 35 | 27.8 s | 39.5 s |
| independent check | knowledge_validation / claude-sonnet-5.5 | 6 | 6.9 s | 7.9 s |

The answer's prompt grew with every turn: about 44k tokens on average, and up to 62k tokens in the 07:41Z replay. A
customer who already has quotes would also have paid for a whole extra think() decision, `quoteQuestion`, before the
answer. These replays had no quotes, so they did not hit it.

## Where the time goes after

The source is the `agent_runs` laps that the new handler writes. Each lap is cumulative from the start of the turn.

| stage | measured |
|---|---|
| embedding | ≤ 7 ms locally. gte-small exists only on the edge, where it is bounded at 1.5 s. |
| reads, in parallel: recall, `fn_sales_assist`, conversation, company brief, own quotes | 1.0–3.3 s |
| one streamed `customer_portal_assistant` call on claude-sonnet-5.5 | p50 6.6 s, p95 12.3 s |

47 of the 48 turns measured across the two after-runs were a single call.

## Caveats

- The "after" numbers come from the branch code served locally against production, not from the edge. On the edge, add
  at most 1.5 s for the gte-small embedding and the edge boot time (34–84 ms in today's function logs).
- The edge functions deploy at merge. Nothing was deployed or applied from this branch.
- The cost per turn is about 15% higher. Each turn now carries the company brief of about 144k tokens, which the widget
  already sends on every signed-in turn under ruling 1219; about 99.7% of it is read from cache. The cost is per
  customer message, so the idle spend does not change.

## What the first after-run caught

The first run of the new turn returned correct answers wrapped as `{"answer":"..."}`. The shared rules in `aiSystem`
ask for JSON, and only `aiReply` parses it. Two changes fixed it:

- `aiSystem` now has a `plainText` option;
- `portal_turn.wrappedReply` makes the per-sentence check refuse any JSON-wrapped sentence, so the model rewrites it.

The re-run above (`after2`) is the corrected code.
