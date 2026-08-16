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

## Every remaining OpenRouter path, closed — and two audit findings corrected

The Phase C audit reported that eleven of the twelve functions reading `openrouter_api_key` bypass
the hold. That number was **wider than the evidence supported**, and the audit said so at the time:
it had not traced what the eight functions that read the key without naming `openrouter.ai` do with
it. Traced now:

- **Eight of them** — `archive_rfq`, `doc_render`, `ea_meeting_summary`, `enrich_capability`,
  `gen_category_knowledge`, `gen_category_personas`, `learn_gaps`, `reflect` — read the key **only
  as a presence check** and then route through `_shared/llm.ts`, which is a thin client for
  `ai_gateway`. None of them contains a `fetch` to any external host. They were never an
  unrestricted path; `ai_gateway`, and the `fn_llm_preflight` call inside it, is their only route
  out.
- The audit also quoted a code comment saying `fn_llm_preflight` *"answers allowed=true for a
  null/unknown route"*. Reading the routine itself: a **null** model returns allowed with the reason
  *"deterministic path, no provider call"*, and an **unregistered** model is **refused** with
  `route_not_registered`. It is already deny-by-default on an unknown route. That finding was
  overstated and is withdrawn.

What was genuinely open, and is now closed:

| Function | Endpoint | Was | Now |
|---|---|---|---|
| `ai_health` | `/api/v1/key` — metadata | active cron 102, no gate | gated; `skipped_due_to_zero_cost_mode` confirmed 10:37 |
| **`resend_inbound`** | **`/api/v1/chat/completions` — real paid inference** | **no gate at all**, on a path an inbound supplier email with an attachment triggers | gated on `fn_os_paid_ai_allowed()`; the attachment is still stored and linked, the classification is recorded as `skipped_due_to_zero_cost_mode` and counted in `classify_skipped_zero_cost` |
| `cost_snapshot` | `/api/v1/credits` — metadata | no gate; both cron jobs inactive | gated; reports from `fn_os_provider_state_cached()` instead |

All three treat a gate they cannot read as **closed**, and none falls back to another key. Deployed:
`ai_health` v11, `resend_inbound` v24, `cost_snapshot` v11.

**No path in the estate now reaches OpenRouter without first asking whether it may.** That claim is
bounded to the twelve functions that read `app_secrets.openrouter_api_key` and to a repo-wide search
for `openrouter.ai`, which returns no other caller.
