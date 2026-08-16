# Phase C — autonomous event canary (gates 8, 9)

Both canaries were executed against the live database inside a transaction that ends in
`raise exception`, so the runtime really ran and nothing was left behind. Every number below is from the
aborted transaction's own payload.

---

## GATE 8 — one safe autonomous event through the actual ingress path

Subject: workflow **W05** (RFQ qualification), business object `ZZ-AUDIT-RFQ-PHASEC-FINAL`, start event
`EV-W05-STARTED`. Entry through `public.fn_phase_c_workflow_start` — the `runtime_entrypoint` the workflow
binding itself names.

### What worked

```
run_id 85 | workflow W05 | state 'queued'
accountable_role_id 'rfq_qualification_manager'   <- a department employee, not the CoS, not the founder
start_event 'EV-W05-STARTED' | dedupe_key 'W05:ZZ-AUDIT-RFQ-PHASEC-FINAL:1'
```

`fn_phase_c_step_advance(85, 'W05-S01', 'rfq_qualification_manager', …)` returned `ok: true`:

- step_run 34, owner `rfq_qualification_manager`, attempt 1
- **12 gates evaluated**, each with a verdict and a reason — GATE-001…008, 010, 011, 031, 032
- authority checked: `"routine_operational_decision permitted under autonomous_internal for rfq_qualification_manager"`
- `founder_boundary: "none"`
- trace 473 written and attached to the step run

| Requirement | Result |
|---|---|
| Chief of Staff bypassed | **PASS** — `founder_command` rows created: 0 |
| Founder bypassed | **PASS** — `founder_command_message` rows: 0; `founder_approval_request` rows: 0 |
| Canonical workflow/step selected | **PASS** — W05 / W05-S01 from the binding |
| Trace exists | **PARTIAL** — step run traced (473); `phase_c_workflow_run.trace_id` is **NULL** |
| No external or financial side effect | **PASS** — no outbound call, no money, no mail |
| **Canonical employee receives one task** | **FAIL** — `phase_c_task where run_id = 85` = **0** |

### 8.1 FAILS — nobody receives any work

The step went `started_at == finished_at`, state `completed`, in the same statement that opened it. Its
`input_hash` and `output_hash` are both `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` —
the SHA-256 of the empty string. No input was consumed, no output produced, and no task was created for
`rfq_qualification_manager`.

The authoritative design requires: *event → canonical event router → canonical workflow and step → exact
accountable employee → specialists/reviewers → outcome and KPI → manager response.* The chain reaches "canonical
workflow and step" and stops. `fn_phase_c_task_create` exists and works (proved below), but nothing on the
autonomous path calls it.

### 8.2 FAILS — the canonical event router has no producer, no consumer and no clock

`fn_phase_c_workflow_start` and `fn_phase_c_step_advance` emitted **zero** outbox rows
(`events_emitted_now = 0`), although `phase_c_workflow_binding` names an `event_outbox_writer` and the run row
stores `start_event = 'EV-W05-STARTED'`.

Measured across the whole database:

| Fact | Query | Result |
|---|---|---|
| Routines that call `fn_phase_c_outbox_emit` | `pg_proc.prosrc ilike '%fn_phase_c_outbox_emit%'` | **one**: `fn_founder_command_submit` |
| Rows ever written to the outbox | `count(*) phase_c_event_outbox` | **3**, all `status = 'pending'`, `attempts = 0` |
| Delivery attempts, ever | `count(*) phase_c_event_delivery_attempt` | **0** |
| Cron jobs referencing the outbox or any `phase_c` object | `cron.job where command ilike '%outbox%' or '%phase_c%'` | **0** |
| Workflow runs, ever (before this audit) | `count(*) phase_c_workflow_run` | **0** |
| Step runs, ever | `count(*) phase_c_workflow_step_run` | **0** |
| Handoff runs, ever | `count(*) phase_c_handoff_run` | **0** |

`fn_phase_c_outbox_claim(int)` — the `delivery_worker` named by all 347 event bindings — only marks rows
`claimed` and returns them. It dispatches to nothing, and nothing calls it.

All **347** rows of `phase_c_event_binding` carry `connection_status = 'CONNECTED'` and
`outbox_writer = "public.phase_c_event_outbox (written in the same transaction as the business state)"`. One
producer exists, it writes one hard-coded event id, and no consumer has ever read a row.

**GATE 8: FAIL.**

---

## GATE 9 — one safe multi-department event fixture

Subject: workflow **W02**, business object `ZZ-AUDIT-MULTIDEPT-2`, handoff `H-W02-01-02`, crossing
`exec → data_intel`.

The first attempt was refused, correctly, and that is worth recording: an incomplete packet returned

```json
{"ok": false, "error": "incomplete_packet",
 "missing": "business_object_id, object_version, output, requested_action",
 "message": "The sender keeps this. An incomplete packet does not become the receiver's problem.",
 "return_owner": "corporate_performance_director"}
```

With a complete packet, `fn_phase_c_handoff_open` then `fn_phase_c_handoff_decide('accept', …)` produced:

```
handoff_run 47 | H-W02-01-02 | status 'accepted'
sending_role_id            corporate_performance_director   (exec)
receiving_role_id          data_intelligence_director       (data_intel)
accountable_until_accept   corporate_performance_director -> then data_intelligence_director
return_owner_role_id       corporate_performance_director
packet_hash 3a7a5b97…      sla_policy_id SLA-HANDOFF-STANDARD   due_at +4h
acceptance_criteria        "Prior required step accepted or workflow start event. …"
traces 474 (open) and 475 (accept)
```

| Requirement | Result | Evidence |
|---|---|---|
| One overall coordination owner | **PASS** | one `phase_c_workflow_run` (run 89), `accountable_role_id` singular |
| Explicit handoffs | **PASS** | sender, receiver, packet hash, acceptance criteria, SLA, return owner, and who is accountable at each moment — all recorded, both traced |
| No founder approval | **PASS** | `founder_approval_request` created during the probe: 0 |
| **One accountable owner per child task** | **FAIL** | `phase_c_task where run_id = 89` = **0** |
| Events emitted | **FAIL** | `events_emitted = 0` across workflow start, handoff open and handoff accept |

**GATE 9: FAIL** — for the same reason as gate 8. Coordination and accountability are modelled correctly and
enforced correctly; the runtime never creates the child tasks that the requirement is about, so the per-task
owner cannot be verified because there are no tasks.

---

## What the task runtime *does* do, when called directly

So that the failures above are not read as "the task machinery is broken" — it is not. Called directly, in a
third aborted transaction:

```
fn_phase_c_task_create(...)               -> task 778, state 'queued', trace_id null
fn_phase_c_task_transition -> assigned    -> ok, trace 476
                           -> accepted    -> ok, trace 477
                           -> in_progress -> ok, trace 478
                           -> completed   -> ok, trace 479, closed_at set, task.trace_id = 479
```

An illegal jump (`queued -> in_progress`, `queued -> completed`, `completed -> queued`) is refused with
`invalid_transition` and the message *"The Phase C task state model does not allow that move."* 11 states,
22 transitions, all enforced.

The contract works. Nothing on either autonomous entry path invokes it.
