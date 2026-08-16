# Phase C correction 5 — event-binding status, derived rather than typed

**Migration:** `scripts/sql/phase_c_33_event_binding_status.sql`

All **347** rows of `phase_c_event_binding` read `CONNECTED`. One routine in the database emitted
anything, nothing had ever consumed a row, and `phase_c_event_delivery_attempt` had never held one.
A status column is prose someone typed at build time; on a dashboard it reads exactly like evidence.

## The legs a binding must have to say CONNECTED

```
producer → durable event/outbox → claim → delivery worker → consumer
         → result/task/state transition → delivery evidence
```

## Not assigned — computed

`public.fn_phase_c_event_binding_status(event_id)` returns the status **and the evidence** for it,
and all 347 rows were re-evaluated through it. A trigger,
`a00_phase_c_event_binding_status_guard`, refuses any hand-written value the legs do not support:
*"Wire the missing leg; do not relabel the row."* Re-running the derivation after any further wiring
moves the counts by itself.

| Status | Count | Why |
|---|---|---|
| **CONNECTED** | **287** | 30 `*.started` events — producer `fn_phase_c_event_ingress` / `fn_founder_command_submit` via `fn_phase_c_lifecycle_event`; consumer creates run, step run and task. 257 `*.<step>.completed` events — producer `fn_phase_c_step_advance` via `fn_phase_c_step_event`; consumer hands the successor step to its accountable owner through `phase_b_handoff` |
| **DEFERRED_RUNTIME_IMPLEMENTATION** | **60** | workflow-level `*.completed` and `*.blocked` events. No deployed producer emits them and `fn_phase_c_event_consume` has no branch for them. Phase D adds the emitter at the state change the event names, and a consumer branch |
| **INTENTIONALLY_INACTIVE** | 0 | no binding qualifies today |
| **HISTORICAL_ONLY** | 0 | no binding qualifies today |
| **BROKEN** | 0 | every event resolves in the frozen registry and every primary consumer resolves to a canonical actor |

**347 = 287 + 60.** No registry-only binding is labelled CONNECTED.

The invariant `event_bindings_claiming_more_than_the_legs_support` compares every stored value
against the derivation on every run, so the table cannot drift back.
