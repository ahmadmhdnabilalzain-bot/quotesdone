# Phase C final acceptance — zero-cost result

Gate 16. Observed across the **whole** acceptance window, 15:03 → 15:48 UTC on 17 Aug 2026, not
sampled at one moment. Every command in the session ran with:

```
NO_PAID_AI=true  OPENROUTER_DISABLED=true  AI_PROVIDER_MODE=mock
```

---

## RESULT — **PASS**

| required | measured |
|---|---|
| OpenRouter HTTP requests = 0 | **0** |
| other paid AI provider requests = 0 | **0** |
| `llm_attempt` rows = 0 | **0** created in the window |
| paid inference cost = USD 0.00 | **0** |
| no fallback key | confirmed in the deployed source |
| gate read failure denies | confirmed by code path |
| route table empty or malformed denies | **executed** — see below |
| `ai_health` records zero-cost skip | 3 of 3 runs |
| no direct provider client bypasses the central gate | 5 of 5 provider-touching functions use it |

---

## 1. Nothing was spent

Measured at the close of the window:

```
llm_attempt rows created in the window        0
newest llm_attempt row in the whole table     2026-08-15 02:51:33 UTC   (two days before this session)
phase_c_trace  sum(cost_usd) in the window    0
phase_c_trace  rows naming a model            0
ai_usage rows in the window                   0
```

`fn_os_provider_state_cached()` at close:

```json
{ "paid_ai_allowed": false,
  "routes_held": 8, "routes_total": 8,
  "held_until": "2126-08-15T02:51:36+00:00",
  "hold_reason": "HELD BY THE FOUNDER 15 Aug 2026: no OpenRouter calls until he releases it.
                  Release with: update llm_route_health set open_until = null;",
  "key_present": true,
  "last_paid_attempt_at": "2026-08-15T02:51:33+00:00",
  "cost_aed_since_phase_c": 0 }
```

The key is present and unused. The hold is the founder's, dated 15 Aug 2026, and it held throughout.

---

## 2. The one job that reaches OpenRouter did not

Cron **102** `ai_health_15min` runs at :07, :22, :37 and :52 and, when permitted, calls
`https://openrouter.ai/api/v1/key`. It fired three times inside the window and **made no request**:

```
2026-08-17 15:07:00  ok  ai_health made NO request to any paid provider:
                         skipped_due_to_zero_cost_mode: 8/8 routes held until 2126-08-1…
2026-08-17 15:22:00  ok  ai_health made NO request to any paid provider: …
2026-08-17 15:37:00  ok  ai_health made NO request to any paid provider: …

runs in the window that called a provider: 0 of 3
```

The deployed source is explicit that this is a skip and not a masked failure:

> *"Not 'ok' in the sense of 'the provider answered' — ok here means the estate is in the state the
> founder asked for. Saying otherwise would page someone for a deliberate hold."*

and, on the absence of a fallback:

> *"Cost governance is not removed: while the hold is on, the check reports from the state the
> database already holds. It does NOT fall back to another key, and it does not guess."*

`ai_health` consults the shared gate **and** honours `NO_PAID_AI` / `OPENROUTER_DISABLED`
independently, so either alone stops it.

---

## 3. The gate fails closed — proved, not read

`fn_kernel_paid_provider_gate` was executed directly, including with its route table emptied inside
a transaction that aborted:

| condition | result |
|---|---|
| normal, model `openrouter/metadata` | `allowed = false`, rule **`founder_hold`** |
| a model nobody registered | `allowed = false` |
| **`llm_route_health` emptied** | `allowed = false`, rule **`empty_route_state`** |

An empty route table denies. It does not read as "no restriction found".

The client half, `supabase/functions/_shared/paid_gate.ts`, denies on every failure mode rather than
on one:

```
RPC returned an error        -> DENY  gate_rpc_error
gate could not be reached    -> DENY  gate_unreachable
gate returned null           -> DENY  gate_returned_nothing   "absence is not permission"
gate returned a non-object   -> DENY  gate_malformed
allowed !== true             -> DENY  (rule and reason carried through)
```

Only a literal `allowed === true` opens it.

---

## 4. No direct provider client bypasses the gate

Every Edge Function in the repository that names a paid provider host was enumerated, then checked
for the gate:

| function | names a provider host | routes through `paidProviderGate` / `_shared/llm` |
|---|---|---|
| `ai_gateway` | yes | **yes** |
| `ai_health` | yes | **yes** |
| `cost_snapshot` | yes | **yes** |
| `designer` | yes | **yes** |
| `resend_inbound` | yes | **yes** |

**5 of 5.** No other function in `supabase/functions` references `openrouter.ai`,
`api.openai.com`, `api.anthropic.com` or `generativelanguage.googleapis.com`.

---

## 5. Every mutating path exercised in this acceptance was deterministic

The paths driven during the window and their measured AI cost:

| path | new `llm_attempt` | trace `cost_usd` |
|---|---|---|
| founder command 337 (Gate 4) | 0 | 0 |
| founder command 338, clarification and cancel (Gate 5) | 0 | 0 |
| autonomous contact-form entry → W18 (Gate 6) | 0 | 0 |
| existing-workflow document signal → W07 (Gate 7) | 0 | 0 |
| five workflow drives, 43 step completions (Gate 8) | 0 | 0 |
| 32 write-guard probes (Gate 9) | 0 | 0 |
| 8 retired-path executions (Gate 10) | 0 | 0 |
| goal-retirement trigger (Gate 14) | 0 | 0 |
| cron-class firing, job 103 (Gate 13) | 0 | 0 |
| 55 + 20 injected-defect guards (Gate 15) | 0 | 0 |

`os_api` states it on the command path itself — *"Everything below is deterministic. No model is
called on this path: fn_founder_command_submit classifies against a registered rule"* — and the
returned interpretation confirms it: *"deterministic registry rule CR-066"*.

---

## Boundary of this measurement

What was measured: `llm_attempt`, `ai_usage`, `phase_c_trace.cost_usd`, `agent_runs` for
`ai_health`, `fn_os_provider_state_cached()`, the deployed gate's behaviour under three conditions,
and a static sweep of `supabase/functions` for provider hosts.

What was **not** measured: OpenRouter's own account-side request log. I cannot read it from here.
The claim "OpenRouter HTTP requests = 0" therefore rests on the estate's own records — the one job
that calls OpenRouter recorded that it made no call on all three firings, the gate denied on every
evaluation, and no other code path in the repository can reach a paid provider without passing that
gate. Stated plainly rather than asserted as certainty about a system I cannot see.

**GATE 16: PASS**
