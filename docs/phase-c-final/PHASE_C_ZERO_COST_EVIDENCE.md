# Phase C — zero-cost evidence

Audit window: **2026-08-16 09:19:21 UTC → 2026-08-16 09:55 UTC**, project `htdblwldjkcgjvmqkbeh` (the one project).
Environment enforced for every command in this session: `NO_PAID_AI=true`, `OPENROUTER_DISABLED=true`,
`AI_PROVIDER_MODE=mock`.

## What was measured

| Measure | Source | Result |
|---|---|---|
| Paid-inference attempts in the audit window | `public.llm_attempt where created_at > 2026-08-16 09:00Z` | **0** |
| Paid-inference cost rows in the audit window | `public.ai_cost_log where occurred_at > 2026-08-16 09:00Z` | **0** |
| Cost recorded in the audit window | `sum(ai_cost_log.cost_aed)` | **AED 0.00 = USD 0.00** |
| Last paid inference anywhere in the estate | `max(llm_attempt.created_at)` | 2026-08-15 02:51:33 UTC |
| Last cost row anywhere in the estate | `max(ai_cost_log.occurred_at)` | 2026-08-15 02:51:33 UTC |
| Phase C traces carrying a non-zero cost | `phase_c_trace where coalesce(cost_usd,0) <> 0` | **0** |
| Phase C traces carrying a provider | `phase_c_trace where provider is not null` | **0** |
| Provider circuit rows held open | `llm_route_health` | 8 of 8, `open_until = 2126-08-15 02:51:36Z` |

**Paid inference during the audit: zero, on both ledgers, with zero cost.** That statement is bounded to
`llm_attempt` and `ai_cost_log`; those are the two ledgers this estate writes.

## GATE 16 FAILS — outbound OpenRouter requests were not zero

The gate as written is *"OpenRouter requests = 0"* and *"any outbound request to OpenRouter … is an automatic
Phase C failure."* That did not hold.

`cron.job` id **102**, `ai_health_15min`, schedule `7,22,37,52 * * * *`, **active = true**, invokes the
`ai_health` edge function. `supabase/functions/ai_health/index.ts:53`:

```ts
const r = await fetch('https://openrouter.ai/api/v1/key', { headers: { 'Authorization': 'Bearer ' + key }, ... });
```

`public.os_audit_log` records that it ran and reached the provider six times inside the audit window:

| at (UTC) | actor | ok | note |
|---|---|---|---|
| 2026-08-16 08:37:01 | ai_health | true | "confirmed the OpenRouter gateway and API key are reachable" |
| 2026-08-16 08:52:01 | ai_health | true | same |
| 2026-08-16 09:07:01 | ai_health | true | same |
| 2026-08-16 09:22:01 | ai_health | true | same |
| 2026-08-16 09:37:01 | ai_health | true | same |
| 2026-08-16 09:52:01 | ai_health | true | same |

Said precisely, because the difference matters: **`/api/v1/key` is a free metadata endpoint, not inference.**
No tokens were generated and no money was spent — the cost ledgers above are zero and they are correct. What
failed is the stated boundary "no outbound request to OpenRouter", not the cost target.

`cost_snapshot_weekly` (job 36) and `cost_snapshot_balance_daily` (job 175) call
`https://openrouter.ai/api/v1/credits` in the same way, but both are `active = false` and did not run.

## GATE 16 FAILS — the fallback key is not restricted

`app_secrets.openrouter_api_key` is present and live. Twelve deployed edge functions read it:

```
ai_gateway  ai_health  archive_rfq  cost_snapshot  doc_render  ea_meeting_summary
enrich_capability  gen_category_knowledge  gen_category_personas  learn_gaps  reflect  resend_inbound
```

Only **one** of the twelve — `ai_gateway` — calls `fn_llm_preflight`, the routine that reads the founder's hold
in `llm_route_health`. The other eleven hold the credential and consult no hold at all. Four of the twelve
contain a literal `openrouter.ai` endpoint (`ai_gateway`, `ai_health`, `cost_snapshot`, `resend_inbound`); three
of those four have no preflight.

`ai_gateway/index.ts:455` states the remaining hole in its own words: *"fn_llm_preflight answers allowed=true for
a null/unknown route"*. The hold is enumerated per `model_id` — eight rows — so a model id absent from that table
is not held even on the one path that checks.

Boundary on this finding: I verified which files read the key, which name the endpoint, and which call the
preflight. I did **not** trace what the eight functions that read the key without naming `openrouter.ai` do with
it; they may route through `ai_gateway`. The three that both hold the key and name the endpoint without a
preflight are measured directly.

## The instrument that reports zero is anchored to the wrong thing

`fn_phase_c_invariants()` returns `paid_inference_since_phase_c_started = 0`. Its definition
(`scripts/sql/phase_c_09_invariants.sql:356`) is:

```sql
select count(*) from public.ai_cost_log
where occurred_at > (select coalesce(max(recorded_at), now() - interval '1 day')
                     from public.phase_c_package_erratum);
```

The window does not start at a Phase C start timestamp. It starts at the newest row in
`phase_c_package_erratum` — currently `2026-08-15 10:06:35 UTC`. Recording one more erratum moves the window
forward and the check goes green over whatever spend it just stepped over; emptying that table moves the anchor
to `now() - 1 day`. It also reads one of the two cost ledgers.

The number it reports today is true. The way it computes the number is not a measurement of the thing its name
claims.

## Verdict for this artifact

- Paid inference: **0 calls, USD 0.00** — verified on both ledgers.
- OpenRouter outbound requests: **6 in the audit window** — verified from `os_audit_log` and the deployed source.
- Unrestricted fallback key: **present** — 11 of 12 key-holding functions bypass the hold.

**GATE 16: FAIL.**
