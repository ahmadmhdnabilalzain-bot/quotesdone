# Gate 18 — zero-cost observation window

Audit window: 2026-08-18 04:23 → 04:52 UTC, project `htdblwldjkcgjvmqkbeh`.

## A real scheduled execution, observed live

`cron.job` 102 `ai_health_15min` runs at `7,22,37,52 * * * *` and is `active`. Three firings landed
inside the window; the one at **04:37:00** was observed end to end.

`cron.job_run_details`:

```
jobid 102  status succeeded  start_time 2026-08-18 04:37:00.020106+00
jobid 102  status succeeded  start_time 2026-08-18 04:22:00.018064+00
jobid 102  status succeeded  start_time 2026-08-18 04:07:00.018301+00
```

`phase_c_system_execution` for that firing:

```
component_id        cron:ai_health_15min
system_actor        system.scheduler
accountable_role_id ai_director
workflow_id/step    W23 / W23-S01
trace_id            20942
state_before/after  scheduled_due -> succeeded
correlation_id      0486d38c-db4a-4598-a9bc-22aca6f0841d
causation_id        cron.job/102@2026-08-18T04:37:00.022Z
authority_result    allowed_autonomous:model_prompt_change:autonomous_internal_review
```

`agent_runs` for the same firing, verbatim:

> **ai_health made NO request to any paid provider: skipped_due_to_zero_cost_mode: 8/8 routes held
> until 2126-08-15T02:51:36.685096+00:00; key_present=true; no request was made to any paid provider**

The 04:22 and 04:07 firings recorded the identical string. `skipped_due_to_zero_cost_mode` is
**recorded**, on a real scheduled run, not asserted from a document.

## The ledgers

Phase C starts at `2026-08-15 02:51:36+00`. Both cost ledgers are counted, not one.

| | since Phase C start | in the last 2 hours |
|---|---|---|
| `llm_attempt` rows | **0** | 0 |
| `ai_cost_log` rows | **0** | 0 |
| `ai_usage` rows | — | 0 |

Last row of any kind, ever: `llm_attempt` at `2026-08-15 02:51:33.055144+00` and `ai_cost_log` at
`2026-08-15 02:51:33.108565+00` — **three seconds before** the hold was applied at 02:51:36. Nothing
has been billed since.

Paid inference cost since Phase C started: **USD 0.00**.

## The hold itself

`public.llm_route_health`, all 8 rows:

```
open_until       2126-08-15 02:51:36.685096+00   (all 8, one hundred years out)
opened_reason    HELD BY THE FOUNDER 15 Aug 2026: no OpenRouter calls until he releases it.
                 Release with: update llm_route_health set open_until = null;
```

Models held: `anthropic/claude-sonnet-5`, `anthropic/claude-opus-4.8`,
`~anthropic/claude-haiku-latest`, `google/gemini-3.1-flash-lite`,
`google/gemini-3.1-flash-lite-image`, `google/gemini-3.5-flash`, `qwen/qwen3.7-plus`, and `none`.

The invariant `openrouter_routes_open` counts `open_until <= now()` — routes whose breaker has
*closed*, i.e. routes usable again. It reads 0, and the underlying data confirms the reading is the
right way round: 0 rows in the past, 8 in the future, 0 null.

## Fail-closed behaviour, proved by execution

An aborted-transaction probe against `fn_os_paid_ai_allowed()`:

| condition | returns |
|---|---|
| as production stands now | **false** |
| every hold expired (`open_until = now() - 1 day`) | true — this is the release condition, and it works |
| route table emptied entirely | **false** |

An empty route state **denies**. The gate does not read an absent table as permission.

## No client bypasses the central gate

Every function in the repository whose source names `openrouter.ai` also carries the gate:

| function | gate references |
|---|---|
| `ai_gateway` | 3 |
| `ai_health` | 3 |
| `cost_snapshot` | 3 |
| `designer` | 2 |
| `resend_inbound` | 3 |

`ai_health` asks `paidProviderGate(admin, 'openrouter/metadata')` — the shared fail-closed client, in
which a throw, a null, a malformed shape and an explicit refusal all arrive as `allowed=false` with a
named rule — and additionally honours `NO_PAID_AI` / `OPENROUTER_DISABLED` from the environment. The
`fetch('https://openrouter.ai/api/v1/key')` call sits in the final `else` branch and is unreachable
while either says no. The metadata endpoint is inside the boundary, not exempt from it.

No fallback provider key is consulted: the skipped branch reports from `fn_os_provider_state_cached`
and does not guess.

## Other zero-cost requirements

| requirement | measured |
|---|---|
| OpenRouter HTTP requests | 0 — the only scheduled caller skipped, three times, on record |
| other paid-AI provider requests | 0 — no other provider host appears in any edge function |
| live email | 0 rows added to `notifications` during the window |
| live SMS or WhatsApp | none; no such component fired |
| social publication | none; the canary command explicitly forbade it and produced no publish |
| payment or refund execution | 0 rows in `phase_c_refund_decision`; refund actions returned 401/403 to every non-founder caller |
| external supplier/customer notification | 0 |

## One honest caveat

The four variables the brief names — `NO_PAID_AI`, `OPENROUTER_DISABLED`, `AI_PROVIDER_MODE`,
`PHASE_D_EXTERNAL_EFFECT_MODE` — were exported for every command in this audit. They are **read** by
three edge functions (`ai_health`, `cost_snapshot`, `resend_inbound`) and by nothing in the Node test
suite. Zero cost during this audit was therefore enforced by the database route hold and the shared
`paidProviderGate`, which held completely; the environment variables were a label on the run rather
than a second mechanism. That distinction is recorded here rather than glossed, and it is the basis
for readiness criterion 8 failing in `PHASE_D_TEST_HARNESS_READINESS.md`.

**Gate 18: PASS.**
