# Phase C — final independent acceptance

**Run:** 17 Aug 2026, 15:03–16:10 UTC, against production `htdblwldjkcgjvmqkbeh`.
**Repository state:** `main` at `1fddbbd`, identical to `origin/main`.
**Mode:** `NO_PAID_AI=true OPENROUTER_DISABLED=true AI_PROVIDER_MODE=mock` on every command.
**Nothing was repaired.** Every finding below is left exactly as found.

The builder's statement `PHASE_C_EXECUTION_KERNEL_READY_FOR_ONE_FINAL_ACCEPTANCE`,
`PHASE_C_BUILDER_CLOSURE.md` and every builder-generated CSV were treated as claims. Each number
below was re-measured from the live database, the deployed HTTP surface, or the repository — not
read out of a builder artefact.

---

## RESULT

# PHASE_C_FINAL_ACCEPTANCE_FAIL

Six gates fail: **1, 2, 5, 7, 13, 15**. Ten gates pass. The failures are named, evidenced and
attributed to the smallest responsible component below. Phase D must not begin.

| Gate | Subject | Verdict |
|---|---|---|
| 1 | Frozen baselines and source of truth | **FAIL** — conflicting current routine definitions = 2, not 0 |
| 2 | Source-inventory reconciliation | **FAIL** — 10 of 67 rows carry a CUT_OVER verdict the runtime refuses |
| 3 | Founder authentication | PASS |
| 4 | One founder command, one workflow effect | PASS |
| 5 | Clarification and cancellation | **FAIL** — cancellation does not propagate past the task |
| 6 | Autonomous new-work entry | PASS |
| 7 | Existing-workflow signal | **FAIL** — 10 of 12 active signal sources cannot be accepted |
| 8 | Step engine and workflow closure | PASS |
| 9 | Kernel-only business writes | PASS |
| 10 | Legacy-path retirement | PASS (one stated boundary) |
| 11 | Refund-only founder approval | PASS |
| 12 | Trace integrity | PASS |
| 13 | System-execution instrumentation | **FAIL** — 1 of 517 traces has no execution record |
| 14 | Goal cascade | PASS |
| 15 | Guard quality | **FAIL** — 23 of 55 assertions match a human message, not a code |
| 16 | Zero-cost mode | PASS |

---

## GATE 1 — FROZEN BASELINES AND SOURCE OF TRUTH — **FAIL**

| Required | Measured | |
|---|---|---|
| Phase A drift = 0 | `fn_phase_a_baseline_drift()` → **0 rows** | ok |
| Phase B drift after PBCR-001 = 0 | `fn_phase_b_baseline_drift()` → **0 rows** | ok |
| departments = 10 | `org_departments where active` → **10** | ok |
| canonical roles = 90 | `org_role active, runtime_mode <> knowledge_overlay` → **90** | ok |
| category overlays = 86 | `org_role active, runtime_mode = knowledge_overlay` → **86** | ok |
| workflows = 30 | `phase_b_workflow` → **30** | ok |
| workflow steps = 257 | `phase_b_workflow_step` → **257** | ok |
| repository → production drift = 0 | `sql_files_match_live` → 520 routines, **0 drifted, 0 missing** | ok |
| production → repository drift = 0 | 995 live non-extension `public` routines; **0** with no definition in main | ok |
| uncommitted application DDL = 0 | `git status --porcelain -- scripts/sql supabase/ src/` → **empty** | ok |
| production Edge Functions match the repository | `verify_deploy_parity --all` → **202 of 202 carry the repo's code** | ok |
| main contains every deployed definition | see prod → repo above; 1,536 `.sql` files scanned, 1,010 distinct routine names | ok |
| PR #428, #429 merged | MERGED 05:44 and 06:21 UTC today | ok |
| production not ahead of main | `HEAD` = `origin/main` = `1fddbbda7ae…` | ok |
| **conflicting current routine definitions = 0** | **2** | **FAIL** |

The Phase A drift function is not a count check: it recomputes six SHA-256 registry digests exactly
as `freeze.mjs` computed them. The Phase B function recomputes nine structure digests and compares
them to `org_phase_baseline.registry_sha256->'structure'`. I recomputed all nine live and compared
them to the recorded values myself — all nine match, so the re-freeze after PBCR-001 was not a
rubber stamp of a changed literal. PBCR-001 is recorded in `phase_b_change_request` with all
eleven elements, founder approval quoted, and `digest_subjects_moved = {step_ownership,
overlay_authority, handoff_accountability}`; the handoff count moved 161 → 159, which the change
request states explicitly (H-W14-04-05 and H-W14-05-06 deleted).

### The failure

`scripts/sql/operations_assistance_company_reports.sql` and
`scripts/sql/operations_company_remaining_lists.sql` were added in the **same commit**
(`deff052`, PR #417) and **both** define `public.fn_ws_operations()` and `public.fn_ws_company()`
with **different bodies**:

| routine | file | normalised body length | matches live |
|---|---|---|---|
| `fn_ws_operations` | `operations_assistance_company_reports.sql` | 2,976 | **no** |
| `fn_ws_operations` | `operations_company_remaining_lists.sql` | 3,124 | yes |
| `fn_ws_company` | `operations_assistance_company_reports.sql` | 1,635 | **no** |
| `fn_ws_company` | `operations_company_remaining_lists.sql` | 1,735 | yes |

`sql_files_match_live` ranks files by git commit time and, for a tie inside one commit, "accepts
live if it matches ANY of them" (its own comment, line 94). So it certifies whichever body happens
to be deployed and reports 0 drift. A later session that edits and applies
`operations_assistance_company_reports.sql` would silently revert both workspace readers and the
drift check would still print 0.

Two further pairs are **not** defects and are recorded so the count is not overstated:
`fn_founder_command_thread` is defined twice inside one file (the later statement wins,
deterministically) and `fn_agent_context` has two live overloads, both present in one file.

**Smallest responsible component:** the pair of files above — one of them is a superseded record of
a change; and, structurally, the tie-breaking rule in
`scripts/checks/sql_files_match_live.test.mjs` (the `candidates` loop, lines 91–127), which cannot
report a same-commit conflict because it treats any matching candidate as proof.

---

## GATE 2 — SOURCE-INVENTORY RECONCILIATION — **FAIL**

The inventory was reproduced independently from `public.phase_c_source_cutover` and cross-checked
against the live catalogue. **67 rows**, reconciled row by row:

| | register | measured | |
|---|---|---|---|
| total | 67 | **67** | ok |
| ACTIVE | 54 | **54** | ok |
| DISABLED | 13 | **13** | ok |
| A NEW_WORK_REQUEST | 28 | **20 active + 8 disabled = 28** | ok |
| B EXISTING_WORKFLOW_SIGNAL | 14 | **12 active + 2 disabled = 14** | ok |
| C READ_ONLY_MONITOR | 22 | **19 active + 3 disabled = 22** | ok |
| D RETIRE_OR_HISTORICAL | 3 | **3 active + 0 disabled = 3** | ok |
| CUT_OVER | 32 | **20 A-active + 12 B-active = 32** | ok |
| READ_ONLY | 19 | **19 C-active** | ok |
| RETIRED_OR_INACTIVE | 16 | **13 disabled + 3 D-active** | ok |

Every one of the 67 rows carries all twelve required columns; the blank-column scan returned
**0 rows** for source component, activation, class, entry point, adapter/disposition, workflow or
signal, accountable role, system actor, idempotency rule, trace policy, evidence and
`disposition_evidence`.

### Why CUT_OVER 32 + READ_ONLY 19 = 51 while active = 54

The three-row difference is **the whole of class D**, which is active but is neither cut over nor
read-only. Named exactly, with each condition verified by execution rather than accepted:

| # | source row | condition | how it was verified |
|---|---|---|---|
| 1 | `dbtrigger:public.company_goals:trg_goal_cascade` | **technically active but business-disabled** | Retired a live company goal inside an aborted transaction: 0 new workflow runs, 0 new W02 runs, 0 new `phase_c_task`, 0 new `org_tasks`, 0 new trigger-inbox rows. The `org_tasks` insert is present in the deployed body only as a comment. |
| 2 | `edge:voice_otp` | **historical** | `POST /functions/v1/voice_otp` on production returns **HTTP 410** with `<Say>This service is unavailable.</Say><Hangup/>`. |
| 3 | `edge:voice_otp_capture` | **historical** | `POST /functions/v1/voice_otp_capture` returns **HTTP 410** with `<Hangup/>`. |

None of the three is incorrectly classified.

### Required outcomes

| Required | Measured | |
|---|---|---|
| unexplained source rows = 0 | 0 | ok |
| active source bypassing kernel = 0 | 0 — proved structurally by Gate 9, not by the register | ok |
| active source without adapter/disposition = 0 | 0 | ok |
| active business-state source falsely marked read-only = 0 | 0 — no C-class routine writes any of the eight protected tables | ok |
| inactive or retired source still creating business work = 0 | 0 | ok |
| **coverage claims with nothing behind them = 0** | **10** | **FAIL** |

### The failure

`fn_kernel_cutover_measure` awards the verdict **CUT_OVER** when the routine a source names in
`disposition_evidence` exists and its body calls one of the three kernel doors. It never asks
whether the door **accepts** the call. Ten of the twelve ACTIVE `B EXISTING_WORKFLOW_SIGNAL` rows
name a signal type that `kernel_signal_type` records as `activation_state = 'inactive'`, and
`fn_kernel_signal_submit` refuses every such submission at step 3:

| source row | signal type | type state |
|---|---|---|
| `dbtrigger:public.inquiry_matches:notify_matched_supplier` | `followup.due` | inactive |
| `dbtrigger:public.notifications:trg_invite_status_on_send` | `provider.callback` | inactive |
| `dbtrigger:public.quote_items:quote_items_roll` | `supplier.quote_revision` | inactive |
| `dbtrigger:public.supplier_dues:trg_due_paid` | `provider.callback` | inactive |
| `dbtrigger:public.transactions:trg_refund_resolved` | `provider.callback` | inactive |
| `edge:messages_api` | `clarification.response` | inactive |
| `edge:stripe_confirm` | `provider.callback` | inactive |
| `edge:supplier_ack` | `supplier.acknowledgement` | inactive |
| `edge:supplier_portal` | `supplier.quote_revision` | inactive |
| `ui:/[locale]/me` | `clarification.response` | inactive |

Proved by execution, in an aborted transaction: a W14 run was opened, then
`fn_kernel_signal_submit` was called with `supplier.quote_revision` against it —

```
ok      = false
status  = refused
reason  = signal type 'supplier.quote_revision' is registered with activation_state 'inactive'
          and does not accept submissions.
```

Only `document.arrived_for_run` is active, covering `edge:customer_documents` and `edge:sup_dob`.
So 10 of the 67 register rows are recorded as cut over to a path that cannot currently accept them.
This is not a bypass — the kernel is reached and refuses — but the verdict overstates the state of
the estate, and `coverage_claims_with_nothing_behind_them` reports 0 because it measures the caller,
not the callee.

**Smallest responsible component:** the `kernel_caller` CTE inside
`public.fn_kernel_cutover_measure` — it resolves a source's disposition to "calls a kernel door"
and stops there; the 10 rows and the 10 inactive `kernel_signal_type` rows are the consequence.

### Boundary of this reconciliation

The register scopes **24 of 206** cron jobs (11 of the 23 currently active), **14 of 237** enabled
`public` triggers, **24 of 202** deployed Edge Functions and 5 frontend routes. I did not accept
that scoping on trust: the 12 active cron jobs outside the register were resolved to their
underlying routines and none writes `org_tasks`, `agent_actions`, `notifications`,
`founder_approval_request` or any of the eight protected tables. Beyond that, completeness of the
population rests on the Gate 9 structural proof, not on the register.

---

## GATE 3 — FOUNDER AUTHENTICATION — **PASS**

A real founder bearer and a real non-founder bearer were minted against production
(management token → `api-keys?reveal` → `admin/generate_link` → the action link's session), then
fired at the deployed `POST /functions/v1/os_api`.

| case | status | body |
|---|---|---|
| no headers at all | **401** | `unauthorized — the Command Center requires a bearer token` |
| anon key only, no bearer | **401** | same |
| invalid bearer | **401** | `unauthorized` |
| valid non-founder JWT | **403** | `forbidden` |
| valid enabled founder JWT | **200** | `user: management@quotesdone.com` |

Every founder action verifies the identity, not only the read one — `founder_command`,
`founder_command_clarify`, `founder_command_control`, `founder_command_status` and
`founder_command_thread` each return 401 with anon only and 403 with a non-founder JWT.

Build-mode identity: `phase_c_founder_identity` row `build-mode@quotesdone.local` has
`active = false` and `kind = 'build_mode'`; `fn_phase_c_require_founder` accepts only
`kind = 'email'` **and** `active`, and refuses an empty actor with SQLSTATE 28000 rather than
defaulting.

Direct RPC bypass — with correct parameter names, so a 404 signature miss could not be mistaken for
a refusal:

```
401 / 403   fn_founder_command_submit    42501 permission denied for function
401 / 403   fn_kernel_workflow_start     42501 permission denied for function
401 / 403   fn_kernel_trigger_submit     42501 permission denied for function
401 / 403   fn_kernel_signal_submit      42501 permission denied for function
401 / 403   fn_founder_command_control   42501 permission denied for function
```

Confirmed at the catalogue: every kernel door and founder door is `SECURITY DEFINER` with ACL
`postgres=X/postgres service_role=X/postgres` — `anon` and `authenticated` hold nothing.

---

## GATE 4 — ONE FOUNDER COMMAND, ONE WORKFLOW EFFECT — **PASS**

Submitted through the deployed Command Center HTTP path as the authenticated founder, verbatim as
specified. Full evidence in `PHASE_C_FINAL_COMMAND_CANARY.md`. Command **337**.

Measured immediately after submission and again after the one-minute outbox worker had run twice —
both readings identical:

| required | measured |
|---|---|
| one founder command | 1 |
| one command plan | 1 |
| one canonical workflow run | 1 (W20) |
| one initial active step run | 1 |
| one operational task for the first ready step | 1 (task 1582) |
| plan items are not operational tasks | 4 plan items, 1 task |
| one factual workflow-start event | 1 (`EV-W20-STARTED`, outbox 934) |
| no second workflow run after outbox delivery | 1 run, outbox delivered |
| no second initial task | 1 |
| no duplicate notification | 0 new `notifications` |
| no event self-emission | 1 outbox row total |
| all derived objects carry the founder command ID | 0 tasks under the run missing `command_id` |
| all derived work appears in the founder thread | `founder_command_thread` returns plan, task, owner, due date |
| root and child traces present | 4 traces: 2 root, 2 child |
| no external publish or message | 0 new `notifications`, 0 new `org_tasks`, 0 new `agent_actions` |
| no founder approval request | 0 |
| idempotent replay creates zero additional effects | replay returned `duplicate: true`, same `command_id 337`, same `task_ids [1582]` |
| no paid AI | 0 new `llm_attempt`, trace `cost_usd` = 0 |

---

## GATE 5 — CLARIFICATION AND CANCELLATION — **FAIL**

### Clarification — passes

`"Make marketing better."` submitted through the same deployed path → command **338**,
`intent = AMBIGUOUS`, `status = clarification_required`. Measured immediately:

```
workflow_runs 0   tasks 0   step_runs 0   outbox 0   plans 0
approval_requests 0   clarifications 1   llm_attempt (new) 0
```

`founderCommandClarify` has a real frontend caller — `src/components/osx/OsxShell.tsx:1449`, via
`src/lib/osClient.ts:187`. Answering through that action:

- original command ID retained — still 338, no second `founder_command` row was created
- the exact clarification is stored byte-for-byte in `founder_command_clarification` (id 21),
  question and answer, with `asked_at` and `answered_at`
- the canonical workflow started **only after** the answer — W20, task 1583
- derived work remains in the original thread: `founder_command_thread(338)` returns
  `said: "Make marketing better."` alongside the task it produced

### Cancellation — fails

Cancelled through the actual control the UI calls (`OsxShell.tsx:1488` →
`founderCommandControl(commandId, 'cancel')` → `os_api` `founder_command_control` →
`fn_founder_command_control`). It returned `ok: true, status: cancelled, child_tasks_closed: 1`.
Measured immediately afterwards:

| required | measured | |
|---|---|---|
| command cancelled | `cancelled` | ok |
| tasks closed | 0 open | ok |
| pending handoffs closed | 0 open | ok |
| **run cancelled** | **run 538 (W20) still `active`** | **FAIL** |
| **open steps cancelled** | **step run 531 (W20-S01) still `active`** | **FAIL** |
| **traces sealed** | **2 unsealed** | **FAIL** |
| queued work beneath cancelled commands = 0 | 1 live run, 1 live step run | **FAIL** |

**Cause, measured:** `fn_founder_command_control` does not call `fn_kernel_cancel` at all —
`prosrc ~ 'fn_kernel_'` is **false**. It closes child tasks itself and stops there. It is a second
writer of business state for the same subject, which is the shape Phase C exists to remove.

**A second, independent defect in the canonical canceller.** `fn_kernel_cancel` *does* propagate to
runs, steps, tasks and handoffs (proved: a W17 run cancelled by `fn_kernel_cancel` in an aborted
transaction left 0 open step runs, 0 open tasks, 0 open handoffs, run state `cancelled`). But its
undelivered-outbox sweep, section (g), matches on `payload->>'run_id'`:

```sql
where status in ('pending','claimed','retry_wait')
  and ( … or (payload->>'run_id') in (select rr::text from unnest(v_runs) as rr) )
```

Measured on a live run, the two producers write different keys:

```
EV-W17-STARTED        payload run_id = <ABSENT>   column workflow_run_id = 536
EV-W17-S01-COMPLETED  payload run_id = 536        column workflow_run_id = 536
```

So the workflow-start event survives cancellation as `pending` and will be delivered. The
function's own leftover check (`v_left_outbox`, lines 190–193) uses the **same predicate as the
write**, so it counts zero left behind and the function reports success. The column
`phase_c_event_outbox.workflow_run_id` is populated on both rows and would have matched.

**A third instrument is blind to the same thing.**
`fn_kernel_historical_register_state`'s `queued_work_beneath_cancelled_commands` joins
`phase_c_task` to `founder_command` and counts nothing else. It reports **0** while run 538 and
step run 531 sit open beneath cancelled command 338.

**Smallest responsible component:** `public.fn_founder_command_control` — the founder-facing cancel
op must delegate to `fn_kernel_cancel` instead of closing tasks itself. Secondarily
`public.fn_kernel_cancel` section (g) predicate, and the task-only denominator in
`fn_kernel_historical_register_state`.

**Live residue from this test, left unrepaired as instructed:** workflow run **538** (W20) and step
run **531** (W20-S01) are `active` on production beneath cancelled founder command **338**.

---

## GATE 6 — AUTONOMOUS NEW-WORK ENTRY — **PASS**

Source used: `edge:contact_submit` / `ui:/[locale]/contact`. Real entry path, not a manual kernel
call — an insert into `public.contact_messages`, which is what both the Edge Function and the
public contact route do. Whole chain inside a transaction that aborted. Full evidence in
`PHASE_C_FINAL_AUTONOMOUS_CANARY.md`.

```
insert contact_messages
  -> trigger z95_contact_message_to_kernel
  -> fn_kernel_source_emit('edge:contact_submit', …)
  -> kernel_trigger_inbox   1 row, status accepted
  -> phase_c_workflow_run   1, workflow W18
  -> phase_c_workflow_step_run 1
  -> phase_c_task           1, step W18-S01, owner customer_support
  -> phase_c_trace          5
  -> phase_c_event_outbox   1
```

| required | measured |
|---|---|
| founder absent | 0 `founder_command` rows behind the run |
| Chief of Staff absent, AI CEO absent | 0 tasks owned by `chief_of_staff`, `ai_ceo`, `chief_executive` |
| one workflow | 1 |
| one initial task | 1 |
| exact accountable role | `customer_support` — `phase_b_workflow_step.W18-S01.accountable_role_id` is `customer_support` |
| canonical trace | 5 trace rows under the run |
| duplicate source delivery produces no duplicate workflow | second `fn_kernel_source_emit` with the same ref → inbox still 1, runs still 1, tasks still 1 |
| source does not directly write workflow/task state | proved structurally in Gate 9 |
| no paid inference | 0 new `llm_attempt` |
| no external customer/supplier side effect | 0 new `notifications`; the transaction aborted |

---

## GATE 7 — EXISTING-WORKFLOW SIGNAL — **FAIL**

Source used: `edge:customer_documents`. Real path — an insert into `public.documents` with
`ref_table = 'inquiries'`, which fires `z95_document_to_kernel`. Aborted transaction.

Against the source I drove, every listed requirement holds:

| required | measured |
|---|---|
| existing workflow found | run 541, opened for `inquiry:ZZ-ACCEPT-G7` |
| no second workflow created | 1 run for that business object |
| signal validated against the current workflow state | `status = attached`, `result = {"attached_to_run": 541, "active_step": "W07-S01"}` |
| current step updated | signal attached to the active step run; ATTACH_ONLY is the declared disposition for `document.arrived_for_run`, and the registry states why completing a step from a file arrival would certify work nobody did |
| trace and causation preserved | `trace_id 5485`; `correlation_id signal:edge:customer_documents:37:document.arrived_for_run:541`; `causation_id edge:customer_documents:37` |
| duplicate signal produces no duplicate action | second emit with the same ref → 1 signal row, 1 run |
| invalid signal refused explicitly | a document for an inquiry with no run → `status = refused`, reason *"a signal about an existing workflow must name workflow_run_id. There is no lookup by business object here on purpose…"*, 0 runs created |

### The failure

The gate cannot be satisfied for the rest of the estate. `kernel_signal_type` holds 11 registered
signal types and **10 are `activation_state = 'inactive'`** — including every type that changes
state:

| disposition | types | active |
|---|---|---|
| ATTACH_ONLY | `document.arrived_for_run`, `deadline.due`, `followup.due`, `provider.callback`, `retry.due`, `sla.breach`, `supplier.acknowledgement`, `supplier.quote_revision` | **1 of 8** |
| COMPLETE_STEP | `clarification.response` | **0 of 1** |
| REVIEW_VERDICT | `review.verdict` | **0 of 1** |
| CANCEL | `run.cancellation_requested` | **0 of 1** |

`fn_kernel_signal_submit` contains real implementations of all four dispositions — COMPLETE_STEP
delegates to `fn_kernel_step_complete`, REVIEW_VERDICT to `fn_kernel_review_decide`, CANCEL to
`fn_kernel_cancel`. None of them can be reached today, because no active signal type carries those
dispositions. `public.kernel_signal_inbox` holds **0 rows** on production: outside an aborted
transaction, no signal has ever been submitted.

The consequence for the ten affected source rows is recorded under Gate 2.

**Smallest responsible component:** the `activation_state` column of `public.kernel_signal_type` —
ten rows carry `inactive` while `phase_c_source_cutover` records their sources as ACTIVE and
CUT_OVER.

---

## GATE 8 — STEP ENGINE AND WORKFLOW CLOSURE — **PASS**

Five workflows were driven end to end by an independent driver, each inside a transaction that
always aborted. Full evidence in `PHASE_C_FINAL_WORKFLOW_ENGINE.md`.

### A. W14

```
W14-S01 -> S02 -> S03 -> S04 -> S05 -> S06 -> S07 -> S08 -> S09
run state completed, closed_at set, 11 engine passes, 2 handoffs accepted
```

- W14-S05 accountable role = **`quote_evaluation`** (registry and step run agree)
- `relevant_category_overlay` is a **contributor** on W14-S05 and accountable nowhere in the 257
- overlay-owned tasks across all five runs: **0** (join `phase_c_task` → `org_role` on
  `runtime_mode = 'knowledge_overlay'`)
- no unresolved successor: `fn_kernel_workflow_graph_validate()` returns `OK` for all 30 and
  `unresolved successor owners 0`
- W14 reached its explicit closure step W14-S09
- **mandatory blockers prevent premature closure** — proved with a *fully valid* payload, not with
  a malformed one. W14-S08 names `rfq_success` as independent reviewer; closing it without the
  verdict was refused with SQLSTATE **23514**: *"step W14-S08 names rfq_success as its independent
  reviewer and no approved, independent verdict from that role exists on task 1530. Record it with
  fn_kernel_review_decide first."*

### B. Representative classes

| class | workflow | result |
|---|---|---|
| same-owner multi-step | W09 (1 owner, 0 handoffs) | 9 steps, closure at W09-S09, `completed` |
| cross-owner requiring handoffs | W17 (7 owners, 9 handoffs) | 11 steps, 9 handoffs accepted, `completed` |
| internal reviewer | W30 (3 reviewers) and W14 (1) | 11 steps, 10 handoffs, `completed` |
| failure-state path | W05, S03 completed with `outcome = fail` | run state `blocked`, not closed |
| cancelled path | W17 via `fn_kernel_cancel` | run `cancelled`, 0 open steps, 0 open tasks, 0 open handoffs |

| required | measured |
|---|---|
| workflows without an executable closure path | **0 of 30** |
| nonterminal steps treated as terminal | 0 |
| unresolved successor owners | 0 |
| duplicate successor tasks | 0 — no run had two tasks for one step |
| duplicate handoff runs on one edge | 0 |
| workflow completed with open mandatory blockers | 0 |
| step replay creates no additional effect | every step was replayed with the same idempotency key; task count never rose by more than the one the step itself creates |

One observation, not a gate failure: `fn_kernel_review_decide` **accepts** a verdict on a step whose
registry names no independent reviewer (tested on W14-S01, which has none). Recording an extra
verdict bypasses nothing and no listed requirement covers it; it is noted so it is not discovered
later as a surprise.

---

## GATE 9 — KERNEL-ONLY BUSINESS WRITES — **PASS**

Thirty-two direct writes were attempted — eight protected tables × four identities — each inside a
transaction that always aborted, each under `set local role`, and each with **column names taken
from `information_schema`** so that no refusal is a parse error masquerading as a guard.

| identity | result across all 8 tables |
|---|---|
| `anon` | 8 refused — `42501 permission denied for table …` |
| `authenticated` | 8 refused — `42501 permission denied for table …` |
| `service_role` | 8 refused — `42501 INSERT on public.… is refused: no routine with write authority for this table is on the call stack` |
| `service_role` + forged kernel context (`kernel.maintenance_reason`, `kernel.writer`, `app.kernel_context` all set) | 8 refused, identically |

**Direct business writes accepted outside the kernel: 0 of 32.**

Tables protected, each carrying `a00_kernel_write_guard` BEFORE INSERT OR UPDATE OR DELETE:
`phase_c_workflow_run`, `phase_c_workflow_step_run`, `phase_c_task`, `phase_c_handoff_run`,
`kernel_trigger_inbox`, `kernel_signal_inbox`, `phase_c_event_outbox`, `phase_c_refund_decision`.
Review verdicts are written on `phase_c_task` by `fn_kernel_review_decide` and covered by the same
guard.

The K37 fix was verified at the catalogue rather than taken on trust: `fn_kernel_write_guard` has
`prosecdef = false` — SECURITY INVOKER — so `current_user` inside it is the caller, not the owner.

**Positive control** — the guard is not merely refusing everything: authorised kernel writes were
accepted throughout Gate 8. Five workflow runs were created, 60-plus step runs opened and closed,
21 handoff runs opened and accepted and 43 tasks created, all through
`fn_kernel_workflow_start` / `fn_kernel_open_step` / `fn_kernel_step_complete` /
`fn_kernel_handoff_accept`, every one of which is listed in `kernel_write_authority` against the
table it writes.

Audit/maintenance access is a distinct operation: the maintenance door checks the table owner
before the privileged act, and records to `kernel_maintenance_write`.

---

## GATE 10 — LEGACY-PATH RETIREMENT — **PASS**

Eight paths in `kernel_retired_path`, each disposition verified independently.

| required | measured |
|---|---|
| active callers of old workflow-start logic | 0 outside the kernel |
| active callers of old step-progression logic | 0 |
| active direct task creators | `fn_phase_c_task_create` is called by `fn_kernel_open_step` and `fn_kernel_workflow_start` only |
| active old outbox workers | 0 |
| old cron jobs invoking parallel runtime | 0 — cron 278 calls `fn_kernel_outbox_deliver` |
| direct grants permitting bypass | 0 |
| compatibility wrappers call only the canonical kernel | both are 2–3 lines; `fn_phase_c_event_consume` calls `fn_kernel_event_consume`, `fn_phase_c_outbox_deliver` calls `fn_kernel_outbox_deliver` |
| compatibility wrappers contain no independent business logic | 2 newlines each |
| retired functions refuse state-changing execution | executed, see below |
| historical reads remain available | `fn_phase_c_outbox_settle` refuses to write and the historical outbox rows are readable |

Grants measured directly from `pg_proc.proacl`, not from the builder's check — all eight are
`postgres=X/postgres` and nothing else. `has_function_privilege` for `anon`, `authenticated` and
`service_role` is **false** for all eight, so the PUBLIC-grant trap does not apply here.

Executed with correct signatures, each in an aborted transaction:

```
DISABLED   fn_phase_c_event_ingress   refused 23514 "…is retired: an event records that a state
                                      change happened, it does not cause one…"
DISABLED   fn_phase_c_step_advance    refused 23514 "…is retired: it derived successors from
                                      phase_b_handoff alone…"
READONLY   fn_phase_c_outbox_settle   refused 23514 "…is READ_ONLY_HISTORICAL and no longer settles
                                      anything"
WRAPPER    fn_phase_c_event_consume   ran (delegates to the kernel — correct)
WRAPPER    fn_phase_c_outbox_deliver  ran (delegates to the kernel — correct)
```

`fn_phase_c_event_binding_status` appears to name `fn_phase_c_outbox_claim` but the match is inside
a **string literal** describing the binding, not a call; the state check excludes it by name for
that reason. Verified by reading the matching lines.

**Stated boundary.** The three `KERNEL_INTERNAL_PRIMITIVE` paths —
`fn_phase_c_workflow_start`, `fn_phase_c_task_create`, `fn_phase_c_outbox_claim` — do **not** refuse
when called directly by the database owner (`postgres`), because they hold write authority and the
guard permits them. Their protection is the GRANT: no role an Edge Function, a browser or a
PostgREST client can hold may execute them. This is recorded so the property is not overstated as
"the body refuses".

---

## GATE 11 — REFUND-ONLY FOUNDER APPROVAL — **PASS**

| required | measured |
|---|---|
| general founder approval UI absent | no general approval action in `src/lib/osClient.ts`; the only `founder_approval_required` reference is a display field |
| general founder approval endpoint absent or inaccessible | `os_api` exposes `prompt_approve`, `simulation_approve` and `report_recommend_approve` — operational approvals of a prompt version, a simulation and a report recommendation. None writes `founder_approval_request`, none is a founder approval of routine business work |
| non-refund founder approval records = 0 | `founder_approval_request` holds **0 rows**; `action_class` allow-list is `refund_decision` only |
| routine work blocked on founder = 0 | `org_tasks` with `needs_founder` and a non-terminal status: **0** |
| informational critical alerts do not create approvals | the K21 page path writes a `notifications` row and emits a W29 incident; it creates no approval request and sets no `needs_founder` |
| specific refund approval inbox present | `v_founder_inbox`, 0 non-refund rows of 0 |
| refund cannot execute without an immutable founder decision | guard suite: *a refund decided by someone other than the founder is refused* (28000 + `fn_phase_c_require_founder`); *a refund executed against a REJECTED decision is refused* |
| founder refund decisions append-only and undeletable | `a00_phase_c_refund_decision_immutable` BEFORE **DELETE OR UPDATE** on `phase_c_refund_decision` |
| decision changes require a superseding row | `supersedes_decision_id` and `supersession_reason` columns exist and are the declared route |
| payment executor and reconciler are separate canonical identities | `z10_phase_c_refund_decision_guard` BEFORE INSERT OR UPDATE; guard suite: *a refund whose executor is also its reconciler is refused*; 0 stored rows violate it |

A direct insert of a probe refund decision was itself refused by `a00_kernel_write_guard` — refund
decisions can only be written through the kernel — so the immutability triggers were verified from
the catalogue definitions and from the injected-defect suite rather than from a row I created.

---

## GATE 12 — TRACE INTEGRITY — **PASS**

Current operational state, measured independently of the builder's function:

| required | measured |
|---|---|
| active commands without trace | 0 |
| active workflow runs without trace | 0 |
| active step runs without trace | 0 |
| active tasks without trace | 0 |
| active handoffs without trace | 0 |
| new state-changing system executions without trace | 0 of 516 since the kernel epoch |
| terminal current objects with incomplete/open trace | 0 |
| active orphan traces | 0 |
| sealed traces without `sealed_at` | 0 |
| failed duplicate/idempotent inserts leaving orphan traces | 0 |

Historical, reported separately and never as current compliance:

| required | measured |
|---|---|
| exactly 38 historical exceptions | **38** — HISTORICAL_STATE_TRACE_MISMATCH 22, HISTORICAL_ORPHAN_TRACE 7, HISTORICAL_DUPLICATE_EFFECT 6, VALID_HISTORICAL_RECORD 3 |
| every exception explicitly labelled | 38 of 38 carry a class |
| no historical retrofit presented as contemporaneous | 0 of 38 dated after the kernel cutover; 0 of 38 without an original timestamp; 0 of 38 without a recorded reason it cannot be reconstructed |
| no active effect from a historical duplicate/cancellation defect | 0 of 6 |
| register append-only | a trigger refusing UPDATE and DELETE is present |

The `queued_work_beneath_cancelled_commands` line in this register reads 0 but only counts tasks;
that is reported as part of the Gate 5 failure, not as a Gate 12 failure.

---

## GATE 13 — SYSTEM-EXECUTION INSTRUMENTATION — **FAIL**

Register completeness across the 595 active components (566 of which change state):

| required | measured |
|---|---|
| accountable role missing | **0** |
| system actor missing | **0** |
| authority missing | **0** |
| workflow/step or justified scope missing | **0** |
| trace policy missing on a state-changing component | **0** |
| business-state-changing component using a read-only trace exemption | **0** — the 566 split TRACE-SYSTEM-EXECUTION 438, TRACE-WORKFLOW 119, TRACE-ROLE-ACTION 9; none is a read-only policy |
| active state-changing component without trace instrumentation | 0 |
| active state-changing cron components not wrapped | 0 of 22 |

One safe, zero-cost firing per execution class, each producing a trace:

| class | firing | trace |
|---|---|---|
| cron job | `fn_kernel_cron_exec(103)` (policy_consistency_weekly, read-only monitor), aborted | trace **5523**, +1 `phase_c_system_execution`, component `cron:policy_consistency_weekly`, policy TRACE-SYSTEM-EXECUTION, actor `system.scheduler`, role `general_counsel`, authority `allowed_autonomous:legal_contract_within`, status `sealed` |
| database trigger | `contact_messages` insert (Gate 6), aborted | 5 traces under the run |
| edge function | `os_api` founder command (Gate 4) | 4 traces, 2 root 2 child |
| frontend path | the same `os_api` door the UI calls (Gate 5 clarify + cancel) | traces on command 338 |

### The failure

`fn_kernel_system_trace_state` returns **1 failing of 13**:

```
system_execution_traces_without_a_complete_record
  expected 0 of the traces under TRACE-SYSTEM-EXECUTION
  actual   1 of 517        ok = false
```

The trace:

```
trace_id 3730
component_id     dbfn:fn_kernel_trigger_submit(jsonb)
subject          trigger_inbox 46
status           sealed
created_at       2026-08-17 05:05:00.033+00
system_actor     system.health_monitor
accountable_role it_operations_engineer
```

There is no `phase_c_system_execution` row carrying `trace_id = 3730`. The trace was created at
**05:05 UTC today**, roughly ten hours before this acceptance session opened at 15:03 UTC, so it is
not residue from these tests — it is a pre-existing condition that the builder's closure
(`fn_kernel_system_trace_state` "0 of 13") does not reflect.

**Smallest responsible component:** whichever path wrote trace 3730 without its paired
`phase_c_system_execution` record — the trace names `dbfn:fn_kernel_trigger_submit(jsonb)` under
system actor `system.health_monitor`, on trigger-inbox row 46.

---

## GATE 14 — GOAL CASCADE — **PASS**

| required | measured |
|---|---|
| does not incorrectly start W02 for goal retirement | a live `company_goals` row was retired inside an aborted transaction: **0** new workflow runs, **0** new W02 runs, **0** new `phase_c_task`, **0** new `org_tasks`, **0** new trigger-inbox rows |
| business side effect disabled | the `insert into public.org_tasks` statement is present in the deployed body only as a comment; the regex for a live insert returns false |
| recorded as an explicit Phase B/Phase C wiring gap | `phase_b_phase_c_wiring_gap` **gap 27** — *"no Phase B workflow defines what happens when a company goal is retired"*, with the evidence command and the reasoning that W01 starts from a founder mandate and W02 from a material KPI miss, which a deliberate retirement is not |
| cannot create work until an approved handler exists | the only work-creating statement is disabled and no kernel door is called |
| preserves historical behaviour and evidence | the trigger keeps its definition; the disabled statement is left visible as a comment rather than deleted; the register keeps the classification and its reason |

---

## GATE 15 — GUARD QUALITY — **FAIL**

`scripts/checks/phase_c_guards_reject_injected_defects.test.mjs`:

```
55/55 injected defects refused
row counts before/after every aborted injection:
  tasks 48   cmds 13   msgs 13   appr 0   runs 14   outbox 29
  traces 714   handoffs 7   release_appr 1   probe_components 0     — all unchanged
```

`scripts/checks/phase_b_guards_reject_injected_defects.test.mjs`: **20/20 guards fired**, row counts
unchanged at steps 257, handoffs 159, exceptions 50 — this is the positive-control suite, and every
one of the twenty behaves as expected, including the two that must *open* (a declared change request
must let a frozen-architecture change through).

| required | measured | |
|---|---|---|
| injected defects executed: 55 | 55 | ok |
| injected defects refused: 55 | 55 | ok |
| positive controls accepted: exact expected count | 20 of 20 in the Phase B suite; 28 value/sequence cases in the Phase C suite assert an accepted result | ok |
| stale human-message assertions = 0 | 0 — every case passes | ok |
| row counts unchanged after refused operations | 10 of 10 counters unchanged | ok |
| **assertions use SQLSTATE, structured refusal code or result status** | **23 of 55 do not** | **FAIL** |

Of the 55 cases: 21 `VALUE_CASES` and 7 `SEQ_CASES` assert a **returned value or result status**,
which the gate permits. The 26 pure-refusal `CASES` assert a substring of the raised message, and
only **3** of those use the structured `[SQLSTATE, raising guard]` form:

```
['28000', 'fn_phase_c_require_founder']
['23514', 'fn_phase_c_refund_decision_guard']
['23514', 'fn_kernel_workflow_run_trace_guard']
```

The remaining 23 match on prose — `'does not resolve to an active canonical role'`,
`'is not an approval path any more'`, and so on. None is stale today; all 23 are one message edit
away from becoming stale, which is the condition this gate exists to remove. The builder's closure
correctly reports that three stale messages were converted; the gate asks for all of them.

**Smallest responsible component:** the `CASES` array in
`scripts/checks/phase_c_guards_reject_injected_defects.test.mjs` — 23 of its 26 `expect` values are
prose substrings rather than the `[SQLSTATE, guard]` pair the same file already supports.

---

## GATE 16 — ZERO-COST MODE — **PASS**

Observed across the whole acceptance window, 15:03 → 16:10 UTC.

| required | measured |
|---|---|
| OpenRouter HTTP requests = 0 | `ai_health` fired 3 times in the window (15:07, 15:22, 15:37) and each run recorded *"ai_health made NO request to any paid provider: skipped_due_to_zero_cost_mode: 8/8 routes held until 2126-08-15…"* |
| other paid AI provider requests = 0 | the only five Edge Functions in the repository that name a paid provider host — `ai_gateway`, `ai_health`, `cost_snapshot`, `designer`, `resend_inbound` — all import the shared gate; there is no direct provider client outside it |
| `llm_attempt` rows = 0 | 0 rows created since 15:00 UTC; the newest row in the table is dated 2026-08-15 02:51 |
| paid inference cost = USD 0.00 | `sum(cost_usd)` over every trace created in the window = **0**; `ai_usage` rows in the window = 0 |
| no fallback key | `ai_health` reports from cached state when held and *"does NOT fall back to another key, and does not guess"* — verified in the deployed source |
| gate read failure denies | `paidProviderGate` returns DENY on RPC error, on unreachable, on `null` (*"absence is not permission"*), on a non-object, and on anything that is not `allowed === true` |
| route table empty or malformed denies | executed: with `llm_route_health` emptied inside an aborted transaction, `fn_kernel_paid_provider_gate('openrouter/metadata')` returned **`allowed = false`, rule `empty_route_state`**. Normally it returns `allowed = false`, rule `founder_hold`. An unregistered model also returns `allowed = false` |
| `ai_health` records zero-cost skip | yes, in `agent_runs.note`, on all 3 runs |
| no direct provider client bypasses the central gate | 5 of 5 provider-touching functions route through `paidProviderGate` / `_shared/llm` |

The founder hold is in force: `fn_os_provider_state_cached()` reports **8 of 8 routes held** until
2126-08-15, reason *"HELD BY THE FOUNDER 15 Aug 2026: no OpenRouter calls until he releases it."*

---

## What was NOT run, as instructed

V3 certification; the knowledge-pack scorecard; unrelated Row #3 backlog checks; professional
model-quality testing. No repository code, database definition, production configuration, Phase A
or Phase B object, role, department, workflow definition or expected result was modified by this
session.

## Production residue created by these tests

Left in place, unrepaired, as instructed:

- founder command **337** (the Gate 4 canary) with workflow run 537, task 1582 — behaving correctly
- founder command **338**, cancelled, with **workflow run 538 (W20) and step run 531 (W20-S01) left
  `active`** — this is the Gate 5 defect itself, not a test artefact to tidy away
- 3 `founder_command_clarification` / plan rows belonging to those two commands

Every other probe ran inside a transaction that aborted.
