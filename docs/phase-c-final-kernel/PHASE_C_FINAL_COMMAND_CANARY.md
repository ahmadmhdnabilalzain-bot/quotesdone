# Phase C final acceptance — founder command canary

Gates 3, 4 and 5. Every call below went to the **deployed** HTTP surface,
`POST https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/os_api`, with a real founder bearer.
Nothing was called through the database.

---

## How the session was obtained

No credential was invented and no build-mode door was used. The bearer was minted the way a real
sign-in produces one:

1. management token → `GET https://api.supabase.com/v1/projects/htdblwldjkcgjvmqkbeh/api-keys?reveal=true`
   → the `anon` and `service_role` keys
2. `POST /auth/v1/admin/generate_link` `{type: magiclink, email: management@quotesdone.com}`
3. followed the returned `action_link` without redirect; the session came back in the fragment

A second bearer was minted the same way for `acceptance-nonfounder@example.invalid`, which is a real
authenticated user and **not** a founder identity.

---

## Gate 3 — the authentication matrix

| case | HTTP | body |
|---|---|---|
| no headers at all | **401** | `{"error":"unauthorized","hint":"sign in — the Command Center requires a bearer token"}` |
| anon key only, no bearer | **401** | same |
| invalid bearer (`Bearer not.a.real.jwt`) | **401** | `{"error":"unauthorized"}` |
| valid non-founder JWT | **403** | `{"error":"forbidden"}` |
| valid enabled founder JWT | **200** | `{"ok":true,"user":"management@quotesdone.com","data":{…}}` |

Per action, so that no founder action is protected only by the read path:

| action | anon only | non-founder JWT |
|---|---|---|
| `founder_command` (submit) | 401 | 403 |
| `founder_command_clarify` | 401 | 403 |
| `founder_command_control` (cancel) | 401 | 403 |
| `founder_command_status` (read) | 401 | 403 |
| `founder_command_thread` (read) | 401 | 403 |

**No founder data and no command action is available anonymously.**

### Build-mode identity

```
phase_c_founder_identity
  management@quotesdone.com          kind=email       active=true
  ahmadalzain1993@admin.quotesdone.com kind=email     active=true
  build-mode@quotesdone.local        kind=build_mode  active=FALSE
```

`fn_phase_c_require_founder` requires `active` **and** `kind = 'email'`, and refuses an empty actor
with SQLSTATE `28000` rather than defaulting one. The build-mode identity cannot authenticate.

### Direct RPC bypass

Called with the **correct parameter names**, so that a PostgREST 404 signature miss could not be
mistaken for a refusal:

```
POST /rest/v1/rpc/fn_founder_command_submit    anon → 401 · founder JWT → 403   42501 permission denied for function
POST /rest/v1/rpc/fn_kernel_workflow_start     anon → 401 · founder JWT → 403   42501 permission denied for function
POST /rest/v1/rpc/fn_kernel_trigger_submit     anon → 401 · founder JWT → 403   42501 permission denied for function
POST /rest/v1/rpc/fn_kernel_signal_submit      anon → 401 · founder JWT → 403   42501 permission denied for function
POST /rest/v1/rpc/fn_founder_command_control   anon → 401 · founder JWT → 403   42501 permission denied for function
```

Catalogue confirmation: every kernel and founder door is `SECURITY DEFINER` with ACL
`postgres=X/postgres service_role=X/postgres`. `anon` and `authenticated` hold no EXECUTE.

**GATE 3: PASS**

---

## Gate 4 — one command, one effect

Submitted verbatim as specified:

> "Prepare one additional social-media post explaining how QuotesDone makes supplier sourcing
> easier. Do not publish it, do not send anything externally, do not use paid advertising, and do
> not use paid AI. Return the prepared work to this Command Center thread."

Response, HTTP 200:

```json
{ "ok": true, "owner": "chief_of_staff", "intent": "CMD-W20",
  "status": "tasks_created", "outcome": "ROUTE_AND_CREATE_TASKS",
  "command_id": 337, "plan_id": 285, "plan_items": 4,
  "workflow_ids": ["W20"], "step_run_id": 530, "task_ids": [1582], "tasks_created": 1,
  "event_id": "EV-W20-STARTED", "outbox_id": 934, "trace_id": 5459,
  "correlation_id": "cmd:337", "handoff_run_id": null,
  "primary_owner": "marketing_director", "priority": "P1",
  "due_at": "2026-08-19T15:22:20.807915+00:00",
  "child_owners": ["content_strategy_and_copy","visual_design","social_media_and_community"] }
```

`interpretation: deterministic registry rule CR-066 (CC-001; CC-014 falls to the specificity
requirement)` — no model was consulted on this path.

### Measured immediately after submission, and again after the one-minute outbox worker ran twice

Both readings were **identical**:

| required | measured |
|---|---|
| one founder command | **1** |
| one command plan | **1** |
| plan items are not operational tasks | **4** plan items, **1** task |
| one canonical workflow run | **1** (W20) |
| one initial active step run | **1** active, **1** total |
| one operational task for the first ready step | **1** (task 1582) |
| one factual workflow-start event | **1** (`EV-W20-STARTED`) |
| no second workflow run after outbox delivery | 1 run; outbox `undelivered = 0`, so delivery had happened |
| no second initial task | 1 |
| no duplicate notification | **0** new `notifications` rows |
| no event self-emission | **1** outbox row in total for the command |
| all derived objects carry the founder command ID | tasks under the run with a different or absent `command_id`: **0**; `founder_command_task_link` 1; `founder_command_workflow_link` 1 |
| root and child traces present | **4** traces — 2 root, 2 child |
| no founder approval request | **0** |
| no external publish or message | 0 new `notifications`, 0 new `org_tasks`, 0 new `agent_actions` |
| no paid AI | 0 new `llm_attempt`; `sum(cost_usd)` over the command's traces = **0** |

### Idempotent replay

The identical request with the identical `idempotency_key` was submitted a second time:

```json
{ "ok": true, "duplicate": true, "command_id": 337, "task_ids": [1582],
  "tasks_created": 1, "trace_id": 5459, "child_owners": [] }
```

Same command, same task, same trace. **Zero additional business effects.**

The Command Center displays the four plan items; only one of them became an operational task,
because only W20-S01 was the first ready step.

**GATE 4: PASS**

---

## Gate 5 — clarification, then cancellation

### 5.1 The vague instruction

`"Make marketing better."` → command **338**, HTTP 200:

```json
{ "ok": true, "owner": "chief_of_staff", "intent": "AMBIGUOUS",
  "status": "clarification_required", "command_id": 338,
  "clarification": "I can route this, but not safely yet. What exactly do you want changed, by how much, and by when?",
  "tasks_created": 0, "task_ids": [], "workflow_ids": [],
  "interpretation": "matched CR-066 but the instruction names no quantity, deadline, identifier or deliverable" }
```

Measured:

```
workflow_runs 0   step_runs 0   tasks 0   outbox 0   plans 0
approval_requests 0   clarifications 1   new llm_attempt 0
founder_command.state = clarification_required
```

**Clarification requested, operational tasks 0, workflow runs 0, external side effects 0.**

### 5.2 Answering in the same visible thread

`founderCommandClarify` has a real frontend caller:
`src/components/osx/OsxShell.tsx:1449` → `src/lib/osClient.ts:187` →
`os_api` action `founder_command_clarify` → `fn_founder_command_clarify`.

Answered through that action. HTTP 200:

```json
{ "ok": true, "actor": "management@quotesdone.com", "command_id": 338,
  "intent": "CMD-W20", "status": "tasks_created", "outcome": "ROUTE_AND_CREATE_TASKS",
  "plan_id": 286, "task_ids": [1583], "tasks_created": 1, "workflow_id": "W20",
  "event_emitted": "EV-W20-STARTED", "answer_recorded": true, "clarification_id": 21,
  "interpretation": "after clarification: deterministic registry rule CR-066 …" }
```

| required | measured |
|---|---|
| `founderCommandClarify` has a real frontend caller | `OsxShell.tsx:1449` |
| original command ID retained | **338**, unchanged |
| exact clarification stored | `founder_command_clarification` id 21 holds the question and the answer byte-for-byte, with `asked_at` and `answered_at` |
| no second founder command created | only 337 and 338 exist since 15:20 UTC |
| canonical workflow starts only after clarification | 0 runs before, 1 run (W20) after |
| derived work remains visible in the original thread | `founder_command_thread(338)` returns `said: "Make marketing better."` together with task 1583, its owner `marketing_director`, manager `chief_revenue_officer`, department `growth`, due date and trace |

### 5.3 Cancellation — **THE FAILURE**

Cancelled through the actual control the UI uses:
`OsxShell.tsx:1488` → `founderCommandControl(commandId, 'cancel')` → `os_api`
`founder_command_control` → `fn_founder_command_control`. The frontend helper defaults
`target` to the command id, which is what makes the call valid; sent the same way.

HTTP 200:

```json
{ "ok": true, "actor": "management@quotesdone.com", "status": "cancelled",
  "command_id": 338, "superseded_by": null, "child_tasks_closed": 1 }
```

Measured immediately afterwards:

| subject | required | measured |
|---|---|---|
| founder command | cancelled | `cancelled` — ok |
| tasks | 0 open | 0 — ok |
| pending handoffs | 0 open | 0 — ok |
| **workflow run** | cancelled | **run 538 (W20) still `active`** |
| **open step runs** | 0 | **step run 531 (W20-S01) still `active`** |
| **traces** | sealed | **2 unsealed** |
| **queued work beneath cancelled commands** | 0 | **1 run + 1 step run** |

```
run_id  workflow_id  run_state   step_run_id  step_id   step_state
538     W20          active      531          W20-S01   active
```

**Cause.** `fn_founder_command_control` never calls the canonical canceller:

```sql
select (prosrc ~ 'fn_kernel_cancel') , (prosrc ~ 'fn_kernel_')
  from pg_proc where proname='fn_founder_command_control';
-- false, false
```

It closes child tasks itself and stops. The canonical `fn_kernel_cancel` **does** propagate — driven
directly against a W17 run in an aborted transaction it returned
`{"closed":{"tasks":1,"step_runs":1,"workflow_runs":1,"traces_sealed":2,"outbox_superseded":1}}`
and left 0 open step runs, 0 open tasks, 0 open handoffs — but the founder-facing control does not
reach it.

**A second defect inside the canonical canceller.** Its undelivered-outbox sweep matches
`payload->>'run_id'`. Measured on a live run:

```
EV-W17-STARTED        payload run_id = <ABSENT>   column workflow_run_id = 536
EV-W17-S01-COMPLETED  payload run_id = 536        column workflow_run_id = 536
```

`EV-W17-STARTED` survives cancellation as `pending` and will be delivered. The function's own
leftover check (`v_left_outbox`) uses the same predicate as the write, so it counts zero left behind
and reports success. `phase_c_event_outbox.workflow_run_id` is populated on both rows.

**A third instrument shares the blind spot.**
`fn_kernel_historical_register_state.queued_work_beneath_cancelled_commands` joins only
`phase_c_task` to `founder_command`; it reports **0** while run 538 and step run 531 are open.

**Smallest responsible component:** `public.fn_founder_command_control`. Secondarily the section (g)
predicate of `public.fn_kernel_cancel`, and the task-only denominator in
`public.fn_kernel_historical_register_state`.

**Not repaired.** Run 538 and step run 531 remain `active` on production beneath cancelled command
338 — that is the defect, left in place as evidence.

**GATE 5: FAIL**
