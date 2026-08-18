# Gate 5 — one founder command, one business effect

Submitted through the actual deployed Command Center HTTP path
`POST https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/os_api`, action `founder_command`,
bearer a real founder session for `management@quotesdone.com` minted through
`admin/generate_link` → `verify` (no email was sent; `generate_link` returns the token).

Idempotency key: `AUDIT-FINAL-CANARY-2026-08-18-A`

Message, verbatim:

> Prepare one additional social-media post explaining how QuotesDone makes supplier sourcing easier.
> Do not publish it, do not send anything externally, do not use paid advertising, and do not use
> paid AI. Return the prepared work to this Command Center thread.

## What the kernel returned

| field | value |
|---|---|
| status | `tasks_created` |
| intent | `CMD-W20` |
| outcome | `ROUTE_AND_CREATE_TASKS` |
| command_id | 1680 |
| command owner | `chief_of_staff` |
| workflow_ids | `["W20"]` |
| primary owner | `marketing_director` |
| plan_id / plan_items | 1479 / 4 |
| task_ids | `[4211]` |
| step_run_id | 2757 |
| trace_id | 21277 |
| outbox_id | 3421 |
| event_id | `EV-W20-STARTED` |
| correlation_id | `cmd:1680` |
| handoff_run_id | null |
| founder_approval_required | false |
| interpretation | deterministic registry rule CR-066 |

## Measured immediately (04:46 UTC), from normalized columns

| object | count |
|---|---|
| founder commands | 1 |
| command plans | 1 |
| canonical workflow runs | 1 (run_id 2752) |
| step runs | 1 (2757, W20-S01) |
| operational tasks | 1 (4211) |
| outbox rows | 1 (3421) |
| handoff runs | 0 |
| tasks / runs / step runs without a trace | 0 / 0 / 0 |

Four plan items exist; exactly one is an active operational task. Future plan items are not tasks.

## Measured again after the worker ran (04:47:47 UTC)

`cron.phase_c_outbox_deliver_1min` claimed and delivered outbox 3421 at **04:47:00**.

| object | count after delivery |
|---|---|
| workflow runs | **1** — no second run |
| tasks | **1** — no second initial task |
| outbox rows | **1** |
| delivery attempts | **1** |
| status | `delivered`, `last_error` empty, `first_failure` null |

The delivered row is a **fact**, not a request: `payload.fact = "workflow.started"`, producer
`kernel:workflow_start`. No event was produced by anything but the kernel start, so there is no
self-emission and no re-application of the producer action by the consumer.

Event identity was read from normalized columns, never by parsing `dedupe_value`:

```
command_id       1680
workflow_id      W20
workflow_run_id  2752
step_run_id      2757
task_id          4211
event_id         EV-W20-STARTED
correlation_id   cmd:1680
causation_id     command:1680
trace_id         21278
```

## Replay

The identical submission with the same idempotency key returned HTTP 200 with `duplicate: true`,
`duplicate_of_idempotency_key: AUDIT-FINAL-CANARY-2026-08-18-A`, and the **same** `command_id` 1680,
`task_ids [4211]` and `trace_id 21277`. Zero additional effects.

## External effect

Measured from 04:46:00 UTC onward:

| | |
|---|---|
| notifications rows | 0 |
| founder_alerts rows | 0 |
| llm_attempt rows | 0 |
| ai_cost_log rows | 0 |
| founder approval requests | 0 |

No publish, no send, no paid inference, no founder approval request.

## Cleanup — canonical path only

Cancelled through the deployed control action the frontend uses
(`founder_command_control`, `op: cancel`, `target`), never by deletion:

```
closed: {plan:1, tasks:1, command:1, handoffs:0, step_runs:1, workflow_runs:1, outbox_superseded:0}
```

Replaying the cancel closed nothing. Final state of command 1680: `cancelled`, with 0 active tasks,
0 active runs and 0 deliverable events.

**Gate 5: PASS.**
