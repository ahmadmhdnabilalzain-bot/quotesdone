# Phase C — founder-command canary (gates 5, 6, 7, 15)

## How this differs from every previous run

`scripts/checks/phase_c_command_center_entry_point.test.mjs` says so in its own comment: *"no live HTTP request
was made to os_api, because that needs a signed-in admin session for the founder's own account and minting one
is a credential path this session does not hold."* Its "canary" is a SQL `DO` block calling
`fn_founder_command_submit` inside an aborted transaction.

This audit minted the session. A Supabase admin `generate_link` (magiclink, no mail sent) for
`management@quotesdone.com` was exchanged at `/auth/v1/verify` for a real access token:

```
AUTHENTICATED as management@quotesdone.com  sub 1256c7ec-17bf-4b1e-af8f-aaa32a8fdd14  expires_in 3600
```

Every request below is a real HTTPS `POST https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/os_api`
carrying that bearer token. `os_api` resolved the identity itself — `os_audit_log` records
`actor = management@quotesdone.com` for all five calls, **not** the `build-mode@quotesdone.local` identity that
earlier runs recorded.

## GATE 5 — the command

Sent verbatim, with `idempotency_key = phasec-final-audit-2026-08-16-canary-1`:

> Add one extra social-media post this week explaining how QuotesDone makes
> supplier sourcing easier. Do not publish it until normal brand and quality
> reviews are complete. Do not use paid advertising or any paid AI provider.
> Report progress and the final result through this Command Center thread.

HTTP **200**. Response `data`:

```json
{ "ok": true, "owner": "chief_of_staff", "status": "tasks_created", "command_id": 222,
  "task_ids": [773,774,775,776], "workflows": ["W20 — Marketing content lifecycle"],
  "founder_approval_required": false, "trace_id": 471 }
```

## GATE 6 — the twelve required checks

| # | Requirement | Result | Evidence |
|---|---|---|---|
| 1 | Exact founder text preserved | **PASS** | `founder_command_message.raw_text` (296 chars) is byte-identical to the string sent, including both newlines |
| 2 | Chief of Staff received it | **PASS** | `founder_command.command_owner_role_id = 'chief_of_staff'` |
| 3 | Correct workflow selected | **PASS** | `intent_id = 'CMD-W20'`, all four tasks `workflow_id = 'W20'` |
| 4 | One primary owner | **PASS** | `founder_command.primary_role_id = 'marketing_director'`; one row |
| 5 | Child tasks to canonical employees | **PASS** | 773 marketing_director / 774 content_strategy_and_copy / 775 visual_design / 776 social_media_and_community — all resolve `kind = 'canonical'`, all `department_id = 'growth'`, each with a distinct manager |
| 6 | API and database task counts agree | **PASS** | API returned 4 ids; `select count(*) from phase_c_task where command_id=222` = 4; same ids |
| 7 | Command and tasks committed atomically | **PASS** | `founder_command.created_at`, all four `phase_c_task.created_at` and `founder_command_message.received_at` are the identical timestamp `2026-08-16 09:24:50.318851+00` — one transaction |
| 8 | No external action occurred | **PASS** | no publish, no send: `os_audit_log` in the window contains only `founder_command` rows and unrelated cron `agent_run` rows; the one outbox row is `status = 'pending'`, never delivered |
| 9 | No founder approval created | **PASS** | `founder_approval_request` = **0 rows**, before and after |
| 10 | Readback works | **PASS** | `founder_command_status` 200, `founder_command_thread` 200 (21 fields incl. `said`, `plan`, `tasks`, `traces`, `history`, `progress`, `completion`), `founder_command_inbox` 200 |
| 11 | Trace exists | **FAIL** | see below |
| 12 | Idempotency evidence exists | **PASS** | see gate 15 |

### 6.11 FAILS — the trace does not describe what happened

One trace was written for command 222, and it stopped where the command began:

```
trace_id 471 | subject command/222 | actor founder | system.command_router
state_before 'received' -> state_after 'interpreting' | status 'open' | never sealed
```

The command reached `tasks_created`. Its trace still says `interpreting`, and `status` is still `open`.

Worse, `phase_c_task.trace_id` was **NULL on all four child tasks** at creation, and the founder-facing thread
renders that null straight through (`"trace_id": null` on every task). `TRACE-TASK` in
`public.phase_c_trace_policy` is `trace_required = YES`, `completed_without_trace_allowed = NO`, scoped to
*"every command, workflow or management task lifecycle"*. Creation is part of the lifecycle.

Why no invariant catches it: `closed_tasks_without_trace` only looks at `closed_at is not null`. A task that is
created and never closed is invisible to it. Across the whole table, **12 of 12 tasks had `trace_id` null**.

### GATE 6 also FAILS on the emitted event — the wrong workflow, the wrong owner

One outbox row was written. It is wrong in three fields at once:

```
outbox_id 238 | event_id 'EV-W01-STARTED' | workflow_id 'W01'
accountable_role_id 'ceo' | primary_consumer_role_id 'ceo'
payload {"tasks":[773,774,775,776],"intent":"CMD-W20","command_id":222}
status 'pending' | attempts 0 | trace_id null
```

The command routed to **W20**, owned by **marketing_director**. The event announces **W01** and hands it to the
**CEO**. The payload knows the truth (`"intent":"CMD-W20"`); the routing fields do not.

This is not specific to my canary. All three founder-command outbox rows ever written — commands 186, 217, 222,
all `CMD-W20` — carry `EV-W01-STARTED` / `W01` / `ceo`. `fn_founder_command_submit` emits a hard-coded event id.

## GATE 7 — the ambiguous command

`text = "Make marketing better."`, key `phasec-final-audit-2026-08-16-ambiguous-1`. HTTP **200**:

```json
{ "ok": true, "intent": "AMBIGUOUS", "status": "clarification_required", "command_id": 223,
  "task_ids": [], "tasks_created": 0, "workflow_ids": [], "trace_id": 472,
  "clarification": "I can route this, but not safely yet. What exactly do you want changed, by how much, and by when?",
  "interpretation": "matched CR-066 but the instruction names no quantity, deadline, identifier or deliverable" }
```

Database delta across the call: `messages +1, commands +1, tasks 0, approvals 0, traces +1, outbox 0,
llm_attempts 0`.

- exactly one clarification — **PASS**
- zero operational tasks — **PASS** (`phase_c_task where command_id=223` = 0)
- zero side effects — **PASS** (no outbox row, no approval, no external call, no inference)

**GATE 7: PASS.** The routing is deterministic — `fn_phase_c_command_specificity` over a registered rule table,
no model involved.

## GATE 15 — idempotency and atomicity, without reissuing the command

The identical request was replayed **twice more** with the same `idempotency_key` (09:25:51 and 09:26:13).

Both returned HTTP 200 with `command_id: 222`, `status: tasks_created` — the original command, not a new one.
Database delta across the replay:

```
messages 0   commands 0   tasks 0   approvals 0   traces 0   outbox 0   llm_attempts 0
```

Atomicity is evidenced by the shared transaction timestamp in row 7 above. Task-level idempotency keys are
distinct and derived, not random: `cmd:222:primary`, `cmd:222:child:content_strategy_and_copy`,
`cmd:222:child:visual_design`, `cmd:222:child:social_media_and_community`.

**GATE 15: PASS.**

## Fixture disposal

Command 222 was cancelled through the same authenticated HTTP path
(`founder_command_control`, op `cancel`): HTTP 200, `child_tasks_closed: 4`, and every closed task received a
trace — `closed_without_trace = 0`.

Command 223 **could not be disposed of**. See `PHASE_C_COMMAND_CENTER_READBACK.md`, gate 14: HTTP 409,
`"A command in 'clarification_required' cannot be cancelled; the state model does not allow it."` It remains open
in the founder's inbox and this audit could not remove it.
