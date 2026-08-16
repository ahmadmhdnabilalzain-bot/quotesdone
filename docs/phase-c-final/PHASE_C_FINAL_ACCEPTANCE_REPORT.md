# Phase C — final independent acceptance audit

**Date:** 2026-08-16 · window 09:19–09:56 UTC · project `htdblwldjkcgjvmqkbeh` (the one project)
**Mode:** audit and canary verification only. Nothing was redesigned, no finding was fixed.
**Enforced for every command:** `NO_PAID_AI=true`, `OPENROUTER_DISABLED=true`, `AI_PROVIDER_MODE=mock`.

---

# PHASE_C_FINAL_ACCEPTANCE_FAIL

---

## Result by gate

| Gate | Subject | Verdict |
|---|---|---|
| 1 | Phase A / Phase B frozen fingerprints, zero drift | **PASS** |
| 2 | 90 role reporting paths, 86 overlay relationships | **PASS** |
| 3 | Active state-changing components: role, actor, scope, authority, trace policy | **PASS** |
| 4 | Zero generic owners, zero unclassified active components | **FAIL** |
| 5 | Real authenticated founder-command HTTP canary | **PASS** |
| 6 | The twelve command-canary facts | **FAIL** (10 of 12 pass; trace and emitted event fail) |
| 7 | Ambiguous command, deterministic | **PASS** |
| 8 | Autonomous-event canary through the actual ingress path | **FAIL** |
| 9 | Multi-department event fixture | **FAIL** |
| 10 | Refund-only founder approval, executor ≠ reconciler | **PASS** |
| 11 | Creator/reviewer separation | **PASS** |
| 12 | Task contract, acceptance, closure, valid states | **PASS** |
| 13 | Meaningful decision-trace coverage, zero missing | **FAIL** |
| 14 | Command Center read paths | **FAIL** (6 of 7 pass) |
| 15 | Idempotency and atomicity without reissuing the command | **PASS** |
| 16 | Zero-cost evidence | **FAIL** |
| 17 | DEFERRED_RUNTIME_IMPLEMENTATION register | **PASS** |
| 18 | Production/repository parity and rollback | **FAIL** |

Ten pass, eight fail.

---

## The gates that passed, with what was measured

### GATE 1 — the frozen phases
`fn_phase_a_baseline_drift()` **0 rows**. `fn_phase_b_baseline_drift()` **0 rows**.
`fn_phase_b_effective_errata()` unresolved: **0**. `fn_phase_c_baseline_drift()` **0 rows**.
`fn_phase_c_reporting_map_drift()` **0 rows**. Nothing in this audit wrote to a frozen table.

### GATE 2 — reporting and overlays
`PHASE_C_ROLE_AND_OVERLAY_RESULT.csv`: **176 of 176 PASS** — 90 roles + 86 overlays, no CHECK rows.

- 90 `phase_c_role_binding` rows ↔ 90 `phase_c_reporting_authority` rows, one to one.
- 89 roles report to a manager that resolves `kind = 'canonical'`. The 90th is `ceo → founder`, which resolves
  `kind = 'founder'` — correct by design, not a break. Zero blank managers.
- 86 overlays: every `invocation_role_id` and every `result_returns_to_role_id` resolves canonical; every
  `overlay_id` resolves `kind = 'overlay'`; **no overlay owns a task** (`overlay_owning_a_task` = 0), so an
  overlay advises and never becomes an accountable identity.
- All 90 role bindings and all 86 overlay bindings are `connection_status = 'CONNECTED'`, and every routine
  named by any binding is deployed (17 of 17).

### GATE 3 — component accountability
1,117 components are state-changing and not inactive/disabled. Every one carries a non-empty
`accountable_role_id`, `canonical_system_actor`, `workflow_id`, `authority_class` and `trace_policy_id` —
**0 missing on all five fields**. `component_owners_resolve` = 0 unresolved. 482 carry no `step_id` and are
scoped technically instead (`SYSTEM_SCOPE` and similar), which the gate permits as justified technical scope.

### GATE 5 — the authenticated canary
A genuine session was minted for `management@quotesdone.com` and five real HTTPS requests were made to
`os_api`. `os_audit_log` records `actor = management@quotesdone.com` for all five. This is the first Phase C
canary that is not a SQL probe and not the build-mode identity. Full detail in
`PHASE_C_FOUNDER_COMMAND_CANARY.md`.

### GATE 7 — the ambiguous command
`"Make marketing better."` → exactly one clarification, `tasks_created: 0`, `workflow_ids: []`, and a database
delta of `tasks 0, approvals 0, outbox 0, llm_attempts 0`. Deterministic: matched rule `CR-066` through
`fn_phase_c_command_specificity`, no model involved.

### GATES 10 and 11 — approvals and review separation
Each guard was forced to refuse and then forced to accept. Detail in
`PHASE_C_REFUND_ONLY_APPROVAL_RESULT.md`.

### GATE 12 — the task contract
Executed end to end: `queued → assigned → accepted → in_progress → completed`, four `ok:true` results, a trace
written at every transition (476–479), `closed_at` set and `task.trace_id` populated at closure. Illegal moves
(`queued → in_progress`, `queued → completed`, `completed → queued`) all refused with `invalid_transition`.
11 states, 22 transitions. Acceptance and closure criteria are non-empty on every task the canary created.

### GATE 15 — idempotency and atomicity
Two replays of the identical request with the same key returned `command_id: 222` and a zero delta on every
counter. Atomicity evidenced by one shared transaction timestamp across the message, the command and all four
tasks.

### GATE 17 — the deferred register
137 of 257 step bindings are `DEFERRED_RUNTIME_IMPLEMENTATION`. All 137 are exported to
`PHASE_C_DEFERRED_PHASE_D_REGISTER.csv` and every one of them carries, with **zero blanks**: an owner role, the
missing handler, the expected entry point, the gap, the Phase D action, a trace policy and evidence. They are
labelled `DEFERRED_RUNTIME_IMPLEMENTATION`, not `CONNECTED` — they are not falsely presented as connected.

---

## THE FAILURES

Ordered by consequence. Each carries the exact evidence, the affected object, and the smallest correction.
**None of these was fixed in this session.**

---

### FAIL 1 — GATE 8, GATE 9. The autonomous half of the company does not deliver work to anybody

**The claim under test:** *event → canonical event router → canonical workflow and step → exact accountable
employee → specialists/reviewers → outcome and KPI → manager response.*

**What executed.** A real workflow start for W05, a real step advance for W05-S01, a real cross-department
handoff open and accept for H-W02-01-02 (exec → data_intel). All succeeded. Owners resolved, 12 gates were
evaluated, authority was checked, the founder and the Chief of Staff were bypassed exactly as required, and
traces were written for the step and the handoff.

**What did not happen:**

| Measured | Value |
|---|---|
| `phase_c_task` rows created for the W05 run | **0** |
| `phase_c_task` rows created for the W02 multi-department run | **0** |
| Outbox rows emitted by workflow start, step advance, handoff open, handoff accept, task transition | **0** |
| `phase_c_event_delivery_attempt` rows, ever | **0** |
| Cron jobs referencing the outbox or any `phase_c` object | **0** |
| Routines in the database that call `fn_phase_c_outbox_emit` | **1** — `fn_founder_command_submit` |
| `phase_c_workflow_run` / `step_run` / `handoff_run` rows before this audit | **0 / 0 / 0** |
| `phase_c_event_binding` rows marked `connection_status = 'CONNECTED'` | **347 of 347** |

The step completed with `started_at == finished_at` and both `input_hash` and `output_hash` equal to
`e3b0c442…b855`, the SHA-256 of the empty string. No input, no output, no assignee.

**Affected:** `public.fn_phase_c_workflow_start`, `public.fn_phase_c_step_advance`,
`public.fn_phase_c_handoff_open`, `public.fn_phase_c_handoff_decide`, `public.phase_c_event_binding` (347 rows),
`public.phase_c_event_outbox`, `public.fn_phase_c_outbox_claim`, `cron.job`.

**Smallest required correction (Phase D, not now):**
1. `fn_phase_c_step_advance` must call `fn_phase_c_task_create` for the step's accountable role instead of
   completing the step in the same statement.
2. `fn_phase_c_workflow_start`, `fn_phase_c_step_advance` and `fn_phase_c_handoff_*` must call
   `fn_phase_c_outbox_emit` with the event id their own binding names.
3. One scheduled consumer that calls `fn_phase_c_outbox_claim` and `fn_phase_c_outbox_settle`, and one cron job
   pointing at it.
4. Until 1–3 exist, `phase_c_event_binding.connection_status` must read `DEFERRED_RUNTIME_IMPLEMENTATION` for
   the 347 rows, not `CONNECTED`. That single word is what turns this from a known gap into a false statement.

---

### FAIL 2 — GATE 13. Trace coverage is not zero-missing, and the instruments that say it is are reading empty tables

`phase_c_trace` holds **5 rows** for the life of the table. Missing, measured exactly: **12 of 12 tasks** had
`trace_id` NULL at creation; **3 of 3** workflow runs created had `trace_id` NULL; **3 of 3** outbox rows have
`trace_id` NULL; command 222's own trace is `status='open'`, `state_after='interpreting'` while the command
reached `tasks_created`; and every scheduled execution in the window (nine cron `agent_run` rows) produced no
trace at all under `TRACE-SYSTEM-EXECUTION`, which is `trace_required = YES`,
`completed_without_trace_allowed = NO`.

Four invariants report this clean — `closed_tasks_without_trace`, `completed_step_runs_without_trace`,
`handoff_runs_without_trace`, `completed_commands_without_trace` — and all four read tables that hold zero rows.

**Affected:** `public.phase_c_trace`, `public.fn_phase_c_task_create`, `public.fn_phase_c_workflow_start`,
`public.fn_phase_c_outbox_emit`, `public.fn_founder_command_submit`,
`scripts/sql/phase_c_09_invariants.sql` (the four checks above).

**Smallest required correction:** write a trace at task creation, at workflow-run creation and at outbox emit;
seal the founder-command trace when the command changes state; and re-express the four invariants as
`rows_without_trace / rows_total` so a zero numerator over a zero denominator can never read as coverage.
Detail in `PHASE_C_TRACE_COVERAGE.md`.

---

### FAIL 3 — GATE 16. Six outbound OpenRouter requests inside the audit window, and eleven functions hold an unrestricted key

Cron job **102 `ai_health_15min`** (`7,22,37,52 * * * *`, **active**) calls
`https://openrouter.ai/api/v1/key` with the live `openrouter_api_key`
(`supabase/functions/ai_health/index.ts:53`). `os_audit_log` records it succeeding at **08:37, 08:52, 09:07,
09:22, 09:37 and 09:52 UTC** — six times during this audit — each logging *"confirmed the OpenRouter gateway
and API key are reachable"*.

Stated precisely: `/api/v1/key` is a **free metadata endpoint, not inference**. Paid inference in the window was
**0 calls and USD 0.00** on both ledgers (`llm_attempt`, `ai_cost_log`), and that part of the gate holds. What
fails is the stated boundary "OpenRouter requests = 0".

Separately, **12 deployed edge functions read `app_secrets.openrouter_api_key`** and only **one**
(`ai_gateway`) calls `fn_llm_preflight`, the routine that reads the founder's hold in `llm_route_health`. Three
of the other eleven name `openrouter.ai` directly. `ai_gateway/index.ts:455` records the remaining hole:
*"fn_llm_preflight answers allowed=true for a null/unknown route"*.

And the invariant that certifies zero cost anchors its window to `max(recorded_at)` from
`phase_c_package_erratum` — a table that moves for unrelated reasons — rather than to a Phase C start
timestamp.

**Affected:** `cron.job` 102, `supabase/functions/ai_health/index.ts:53`,
`supabase/functions/cost_snapshot/index.ts:51`, `supabase/functions/resend_inbound/index.ts`, the twelve
key-reading functions, `public.app_secrets.openrouter_api_key`, `public.fn_llm_preflight`,
`scripts/sql/phase_c_09_invariants.sql:356`.

**Smallest required correction:** deactivate cron job 102 for the duration of the zero-cost boundary (or gate
its fetch on `fn_os_paid_ai_allowed()`); route the eleven non-gateway key holders through `ai_gateway` so
`fn_llm_preflight` is unavoidable; make `fn_llm_preflight` deny-by-default on an unknown route; and anchor
`paid_inference_since_phase_c_started` to a stored constant, summing both cost ledgers.
Detail in `PHASE_C_ZERO_COST_EVIDENCE.md`.

---

### FAIL 4 — GATE 6. A founder command for W20 emits `EV-W01-STARTED` and hands it to the CEO

```
outbox_id 238 | event_id 'EV-W01-STARTED' | workflow_id 'W01'
accountable_role_id 'ceo' | primary_consumer_role_id 'ceo'
payload {"tasks":[773,774,775,776],"intent":"CMD-W20","command_id":222}
```

The command routed to **W20**, primary owner **marketing_director**. The event says W01 and routes to the CEO.
The payload carries the correct intent; the routing fields do not. All three founder-command outbox rows ever
written (commands 186, 217, 222 — every one a `CMD-W20`) carry the same hard-coded event id.

**Affected:** `public.fn_founder_command_submit`, `public.phase_c_event_outbox` (3 rows).

**Smallest required correction:** in `fn_founder_command_submit`, resolve the event id from
`phase_c_workflow_binding.start_event` for the workflow actually selected, and take
`accountable_role_id` / `primary_consumer_role_id` from `phase_c_event_binding` for that event.

---

### FAIL 5 — GATE 6. Tasks are created with no trace, and the founder's thread renders the null

All four child tasks were created with `trace_id = NULL`, and `founder_command_thread` returns
`"trace_id": null` on each. Command 222's own trace never left `interpreting`.

**Affected:** `public.fn_founder_command_submit`, `public.fn_phase_c_task_create`, `public.phase_c_task`.
**Smallest required correction:** write a `TRACE-TASK` row inside the creating transaction and set
`phase_c_task.trace_id` from it; advance the command trace when `founder_command.state` changes.

---

### FAIL 6 — GATE 4. Ninety-nine active state-changing components are labelled unclassified, and the invariant that reports it is looking at a different column value

`public.phase_c_component`:

| classification | activation_state | mutates_state | rows |
|---|---|---|---|
| NO_CALLER_UNCLASSIFIED | deployed | **true** | **99** |
| NO_CALLER_UNCLASSIFIED | deployed | false | 187 |

286 components carry the literal classification `NO_CALLER_UNCLASSIFIED`; 99 of them change state and are not
inactive or disabled, which is precisely the population the gate names. The invariant
`unclassified_components` reports **0** because its definition
(`scripts/sql/phase_c_09_invariants.sql:186`) is `where classification = ''` — the empty string — and no row
has an empty string. `unclassified_edge_functions` has the same shape.

Generic owners are genuinely zero (`generic_owner_used` = 0, `component_owners_resolve` = 0), so the first half
of gate 4 holds.

**Affected:** `public.phase_c_component` (99 rows, listed as `FAIL_UNCLASSIFIED` in
`PHASE_C_COMPONENT_ACCOUNTABILITY_RESULT.csv`), `scripts/sql/phase_c_09_invariants.sql:186` and `:191`.

**Smallest required correction:** change both invariants to
`where classification in ('', 'NO_CALLER_UNCLASSIFIED')` restricted to
`mutates_state and activation_state not in ('inactive','disabled')`, then classify the 99.

---

### FAIL 7 — GATE 14. A clarification can never be closed

`founder_command_control(223, 'cancel')` → **HTTP 409**,
*"A command in 'clarification_required' cannot be cancelled; the state model does not allow it."*

`phase_c_command_transition` permits exactly one move out of `clarification_required`: → `interpreting`. It is
the only state of the eight with no terminal exit. `fn_founder_command_control` implements four operations —
`cancel`, `reprioritize`, `supersede`, `explain` — and **none** performs that transition.

Command 223 ("Make marketing better.") is therefore permanently open in the founder's inbox and this audit
could not remove it. Every future ambiguous command adds another that cannot be dismissed.

**Affected:** `public.phase_c_command_transition`, `public.fn_founder_command_control`
(`scripts/sql/phase_c_04_command_center.sql:521–576`), `supabase/functions/os_api/index.ts`.

**Smallest required correction:** add `clarification_required → cancelled` to `phase_c_command_transition`, or
add an `answer` operation to `fn_founder_command_control` that drives `clarification_required → interpreting`
with the founder's reply. One row or one branch.

---

### FAIL 8 — GATE 18. The committed schema export does not match production

| Check | Result |
|---|---|
| `scripts/checks/sql_files_match_live.test.mjs` | **PASS** — 423 routines, 0 not present, 0 drifted |
| `node scripts/verify_deploy_parity.mjs --all` | **PASS** — 202 edge functions carry the repo's current code |
| `scripts/checks/export_from_either_source_is_identical.mjs` | **FAIL — exit 1** |

```
live export                    : 58103 lines, 3100165 chars
supabase/schema/full_schema.sql: 58083 lines, 3098895 chars
identical    : NO
differing    : 18158 lines, first at line 39722
  database: "  -- PREREQUISITES. phase_b_handoff declares from_step_id -> to_step_id for every ordered"
  git     : "  select role_id into v_owner from public.fn_phase_c_resolve_actor(p_actor);"
```

Project refs embedded in the export: 0 — portability is fine; the content is not.

**Rollback availability:** the routine-level rollback path is intact and verified — every one of the 423 live
routines is byte-identical to its newest file under `scripts/sql/`, so any single routine can be restored from
the repository. What is **not** available is a whole-schema rollback: the committed full-schema artefact is not
the schema that is running.

**Affected:** `supabase/schema/full_schema.sql`.
**Smallest required correction:** regenerate and commit the schema export; it has fallen behind PRs #420–#423.

---

## Two repository checks that will now fail permanently, and should be read as instrument defects

`scripts/checks/phase_c_founder_chain.test.mjs` and
`scripts/checks/phase_c_command_center_entry_point.test.mjs` each end with an assertion named *"the probe left
nothing behind"* whose implementation is:

```sql
select count(*) from public.founder_command_message ... = 0
```

That is not "my probe left nothing"; it is "the table is globally empty". Three real founder commands existed
before this audit (186, 217, 256/217's message) and two more exist now. Both checks currently report
`1 check(s) failed` on that line while every other assertion in them passes. The correct form is a
before/after delta, not an absolute count. This is an instrument defect, not a Phase C design defect, and it is
listed here so it is not later mistaken for one.

---

## What this audit changed in production

Under instruction, gate 5 required a real command to be sent. It was, and it is disclosed here in full:

| Object | State now |
|---|---|
| `founder_command_message` 261, `founder_command` **222** | **cancelled** through the authenticated HTTP path; 4 child tasks closed; every closed task carries a trace; `closed_without_trace = 0` |
| `phase_c_task` 773–776 | **cancelled**, live tasks remaining: 0 |
| `founder_command_message` 262, `founder_command` **223** | **still open** in `clarification_required` — see FAIL 7; it cannot be closed |
| `phase_c_event_outbox` 238 | pending, undelivered — the wrong-event row described in FAIL 4 |

Everything else was executed inside transactions that ended in `raise exception` and left no rows: the W05
autonomous canary, the W02 multi-department fixture, the refund guard probes and the task-lifecycle probe.
No Phase A object, Phase B object, workflow ownership, reporting line, role responsibility, overlay authority
or founder boundary was modified.

---

## "Would it have passed if automation were not paused?"

The obvious challenge to FAIL 1, FAIL 2 and FAIL 4, and it was tested rather than argued.

**The stand-down deactivated jobs; it did not delete them.** `cron.job` holds **205** jobs — 22 active, 183
inactive. The scheduler is alive: 190,018 runs in the last 30 days, last fired 2026-08-16 10:05 UTC. A paused
Phase C dispatcher would therefore still be present with `active = false`.

No Phase C dispatcher exists in that table in either state. The single job matching a `workflow_start` pattern
is `workflow_start_due` → `fn_workflow_start_due(1440)`, which is the **legacy** engine over `company_event`
and `workflow`; `prosrc ilike '%phase_c%'` on it is **false**.

The deeper measurement: **zero routines outside the `fn_phase_c*` family call `fn_phase_c_task_create`,
`fn_phase_c_workflow_start`, `fn_phase_c_step_advance` or `fn_phase_c_handoff_open`**, and no edge function
calls them either — a repo-wide search returns only test files, `scripts/phase_c/build_bindings.mjs`, two
`scripts/sql` files and `supabase/schema/full_schema.sql`. The runtime has no caller anywhere. Nothing was
switched off; nothing was ever wired in.

| Failure | Sensitive to the pause? |
|---|---|
| FAIL 1 (gates 8, 9) — no tasks, no events | **No.** The entry points were invoked *directly and live* in this audit. They returned `ok:true` and produced zero tasks and zero events. A scheduler cannot change what a routine does when it is called. |
| FAIL 2 (gate 13) — no traces | **No.** Cron executed nine times during the audit window and `phase_c_trace` gained nothing from any of them. That is the running case, measured. |
| FAIL 4 (gate 6) — `EV-W01-STARTED` for a W20 command | **No.** Observed on a live authenticated HTTPS request; the event id is a hard-coded literal in `fn_founder_command_submit`. |
| FAIL 5 (gate 6) — tasks created with `trace_id NULL` | **No.** Same live request. |
| FAIL 6, 7, 8 (gates 4, 14, 18) | **No.** Registry rows, state-model rows, and a committed file. |
| FAIL 3 (gate 16) — six OpenRouter requests | **Inverted.** They occurred *because* cron job 102 was still active. A complete pause would have made that half of gate 16 pass. |

The pause explains none of the eight failures, and one of them exists only because the pause was incomplete.

The genuine boundary is a different and narrower one, already stated below: with no live external event
source, this audit could not measure what a real customer event would do. That gap sits *upstream* of the
runtime and does not rescue it — the entry points, called directly, still delivered no work to anyone.

## Artifacts

| File | Contents |
|---|---|
| `PHASE_C_FINAL_ACCEPTANCE_REPORT.md` | this document |
| `PHASE_C_ROLE_AND_OVERLAY_RESULT.csv` | 176 rows — 90 roles + 86 overlays, per-row result |
| `PHASE_C_COMPONENT_ACCOUNTABILITY_RESULT.csv` | 1,799 rows — 1,018 PASS, 99 FAIL_UNCLASSIFIED, 682 not in scope |
| `PHASE_C_FOUNDER_COMMAND_CANARY.md` | gates 5, 6, 7, 15 |
| `PHASE_C_AUTONOMOUS_EVENT_CANARY.md` | gates 8, 9 |
| `PHASE_C_REFUND_ONLY_APPROVAL_RESULT.md` | gates 10, 11 |
| `PHASE_C_TRACE_COVERAGE.md` | gate 13 |
| `PHASE_C_COMMAND_CENTER_READBACK.md` | gate 14 |
| `PHASE_C_DEFERRED_PHASE_D_REGISTER.csv` | 137 deferred steps, full register |
| `PHASE_C_ZERO_COST_EVIDENCE.md` | gate 16 |

## Boundaries of this audit

Said plainly, so no reader takes a wider claim than the evidence supports.

- Everything above was measured against the live project `htdblwldjkcgjvmqkbeh` on 2026-08-16 between 09:19 and
  09:56 UTC. Nothing was inferred from a document.
- The eight cost-relevant edge functions that read `openrouter_api_key` **without** naming `openrouter.ai` were
  not traced further; they may route through `ai_gateway`. The three that do both, without a preflight, were
  measured directly.
- `TRACE-SYSTEM-EXECUTION` coverage was established by showing cron executed in the window and the trace table
  gained nothing. Every scheduled execution in the estate was not enumerated against every component id.
- The 482 active state-changing components with no `step_id` were accepted as justified technical scope on the
  basis of their `workflow_id` value (`SYSTEM_SCOPE` and similar). Each justification was not read individually.
- The autonomous canaries prove what the runtime does when its canonical entry points are called directly.
  There is no live external event source feeding them, so "what a real customer event would do" is not
  something this audit could measure.

---

# PHASE_C_FINAL_ACCEPTANCE_FAIL

Failed gates: **4, 6, 8, 9, 13, 14, 16, 18.**

Phase D was not begun. No finding was corrected.
