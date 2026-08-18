# Phase D — zero-cost and zero-external-effect evidence

Required deliverable 13 of 15. Covers the Phase D working session on **2026-08-18, 14:00 → 15:10
UTC** (database clock), project `htdblwldjkcgjvmqkbeh`.

## The required final evidence

`PHASE_D_ZERO_COST_AND_PROVIDER_POLICY.md` names six numbers. All six, measured:

| required evidence | measured | how |
|---|---|---|
| OpenRouter HTTP requests | **0** | no Phase D code path reaches a provider; the gate below refuses every route |
| other paid AI requests | **0** | same |
| `llm_attempt` rows | **0** | `select count(*) from public.llm_attempt where created_at > '2026-08-18 14:00:00+00'` |
| paid inference cost | **USD 0.00** | `select coalesce(sum(cost_aed),0) from public.ai_cost_log where occurred_at > '2026-08-18 14:00:00+00'` → **0**, over **0 rows** |
| live notifications / publications / payments / refunds | **0** | see below |
| — | | |

## The provider gate, read rather than asserted

The hold is not quoted from a status column. `fn_kernel_paid_provider_gate` was **called** with a
representative paid route and asked to decide:

```
select public.fn_kernel_paid_provider_gate('openai/gpt-4o-mini');

{"gate":"kernel_k12","held":8,"rule":"founder_hold","model":"openai/gpt-4o-mini",
 "reason":"8 of 8 routes are held open-circuit until 2126-08-15 02:51:36.685096+00",
 "routes":8,"allowed":false}
```

`fn_kernel_paid_provider_state()` — 5 checks, all green, including
`paid_inference_rows_since_the_hold: expected 0, actual 0`.

BR-054 in `phase_d_rule_enforcement` is wired to this gate as a `PREDICATE`, so every Phase D
handler execution re-reads the live hold rather than trusting a recorded claim.

## The environment the tests ran under

```
NO_PAID_AI=true OPENROUTER_DISABLED=true AI_PROVIDER_MODE=mock PHASE_D_EXTERNAL_EFFECT_MODE=mock
node scripts/checks/run.mjs
```

## Live external effects

**0 produced by Phase D work.**

Four rows appeared in `public.notifications` inside the 12-hour window. Naming them precisely
rather than reporting a bare zero, because "0 external effects" from a query that did not look is
the shape of claim this estate has been burned by:

| id | type | created (UTC) | to | status | `sent_at` | attempts |
|---|---|---|---|---|---|---|
| 1944 | `founder_brief` | 04:30 | management@quotesdone.com | pending | NULL | 0 |
| 1945 | `smoke_alert` | 08:00 | management@quotesdone.com | pending | NULL | 0 |
| 1946 | `health_alert` | 08:00 | management@quotesdone.com | digest | NULL | 0 |
| 1947 | `health_alert` | 14:30 | management@quotesdone.com | digest | NULL | 0 |

All four are **row insertions by the pre-existing read-only monitoring crons** that remain active
under the founder's selective automation hold, addressed to the founder's own admin address. Every
one has `sent_at = NULL` and `attempts = 0`: **none was delivered.** None originated from Phase D
code — the only Phase D execution in the window was a single aborted-transaction probe of W01-S01,
whose one emitted event went to the outbox and was rolled back with the rest of the transaction.

Other effect classes:

| | |
|---|---|
| `phase_c_refund_decision` rows | **0** |
| `phase_c_event_outbox` pending | **0** |
| live email / SMS / WhatsApp / social publish | **0** |
| payments or refunds executed | **0** |

## Persistent demo data

**None created.** `PHASE_D_PRODUCTION_DIRECT_PROTOCOL.md` forbids persistent demo customers and
suppliers and permits "local fixtures, aborted transactions or explicitly namespaced/cleaned
canaries". What this session used, and what it left:

| probe | left behind |
|---|---|
| W01 executor probe (workflow run 5151, step run 5195) | **0** — ended in `raise exception`; `select count(*) from phase_c_workflow_run where business_object_id like 'PD-PROBE%'` → **0** |
| `zz-phase-d-canary@example.invalid` auth identity (D0-AUTH-002) | **0** — deleted in the same run; removal proved by read-back `DELETE 200` then `GET 404`; `select count(*) from auth.users where email like 'zz-phase-d-canary%'` → **0** |
| customers, suppliers, inquiries, quotes created | **0** |

The canary was an **auth identity only**. No business row of any kind was created for it.

## Capability boundary — why no mock completed a business step

21 of the 257 steps are classified `CAPABILITY_BOUNDARY_READY`. `fn_phase_d_handler_execute`
refuses them outside an explicit test context:

```
pd_capability_unavailable — step %s depends on capability %s ... and no capability provider is
available in Phase D. Paid inference is held until Phase E. Refusing rather than completing a
business step from a fixture.
```

This is D9's requirement — *"real business steps completed from Phase D mock: 0"* — enforced in the
executor rather than asserted in prose. The one probe that did run used
`execution_context = 'test'` on a step classified `NONE`, so no capability path was exercised at
all.

## Boundary of this evidence

This covers the Phase D session window named at the top, on the one project. It is a statement
about what Phase D work caused and what the named tables and gate report for that window. It is
**not** a claim about the estate's entire history, nor about any window before 14:00 UTC on
2026-08-18.
