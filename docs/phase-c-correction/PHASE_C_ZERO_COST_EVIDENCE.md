# Phase C correction 9 — the zero-cost provider guard

**Migration:** `scripts/sql/phase_c_37_zero_cost_provider_guard.sql`
**Code:** `supabase/functions/ai_health/index.ts` (deployed v11)

## The path that was making the requests

`cron.job` id **102**, `ai_health_15min`, schedule `7,22,37,52 * * * *`, **active**, invoking the
`ai_health` edge function, which fetched `https://openrouter.ai/api/v1/key` with the live
`openrouter_api_key` on every run — six outbound OpenRouter requests inside the 37-minute audit
window. Nothing on that path consulted the founder's hold in `llm_route_health`.

`cost_snapshot_weekly` (job 36) and `cost_snapshot_balance_daily` (job 175) call `/api/v1/credits`
the same way; both are `active = false` and did not run.

Said precisely: those calls cost nothing. `/api/v1/key` is free metadata, not inference. What failed
was the boundary "no outbound request to OpenRouter", and the fact that a caller could reach the
provider without consulting the hold at all.

## The guard

`public.fn_os_paid_ai_allowed()` — one answer to *"may anything reach a paid inference provider
right now"*:

- **false** while any row in `llm_route_health` has `open_until > now()` (the founder's hold);
- **false** while `app_secrets.no_paid_ai` is set;
- **false when the route table is empty** — deny by default, because an absent hold is not a
  permission.

`public.fn_os_provider_state_cached()` returns the internal state the check now reports from: routes
held, routes total, hold reason, held-until, key presence, last paid attempt, last cost row, and
cost since Phase C began. No network.

`ai_health` consults the gate first, and also honours `NO_PAID_AI` / `OPENROUTER_DISABLED` from the
environment. When either says no it:

- makes **no** request to OpenRouter;
- reports from the cached state above;
- records `skipped_due_to_zero_cost_mode` with the reason;
- **does not fall back to another key**;
- a gate it cannot read is treated as closed.

Cost governance is not removed: the run still records, still counts consecutive failures, and still
pages on the real failure path when paid AI is permitted again.

## Proof, from `os_audit_log`

| at (UTC) | note |
|---|---|
| 10:22:01 | "ai_health confirmed the OpenRouter gateway and API key are reachable" ← last request, **before** the fix |
| **10:37:03** | **"ai_health made NO request to any paid provider: skipped_due_to_zero_cost_mode: 8/8 routes held until 2126-08-15T02:51:36+00; key_present=true; no request was made to any paid provider"** |

## Required results, for the correction and canary window

| Measure | Result |
|---|---|
| OpenRouter HTTP requests after the guard deployed | **0** |
| Paid inference requests (`llm_attempt` since 10:00 UTC) | **0** |
| Paid inference cost (`ai_cost_log` since 10:00 UTC) | **0 rows, USD 0.00** |
| `fn_os_paid_ai_allowed()` | **false** |
| Routes held open-circuit | 8 of 8, until 2126-08-15 |
| Unrestricted fallback used | none — the guard does not fall back to another key |

## Still open, and named rather than claimed fixed

Eleven of the twelve edge functions that read `app_secrets.openrouter_api_key` still do not call
`fn_llm_preflight`; only `ai_gateway` does. This correction closed the path that was **actually
making requests** (cron 102) and gave the estate one authoritative gate to call. Routing the
remaining key-holders through `ai_gateway`, and making `fn_llm_preflight` deny-by-default on an
unknown route, is Phase D work and is not claimed here.
