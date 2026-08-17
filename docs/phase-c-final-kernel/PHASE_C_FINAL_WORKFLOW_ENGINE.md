# Phase C final acceptance — step engine and workflow closure

Gates 8 and 9. Every run below was driven by an independent driver written for this acceptance, not
by the builder's rehearsal script, and every transaction aborted.

---

## Gate 8A — W14 — **PASS**

Driven from start through W14-S05 to explicit closure with deterministic inputs.

```
run 517
path   W14-S01 -> S02 -> S03 -> S04 -> S05 -> S06 -> S07 -> S08 -> S09
passes 11   handoffs accepted 2   reviews recorded 9   tasks 9
duplicate tasks per step 0   duplicate handoff runs per edge 0
overlay-owned tasks 0
last step W14-S09   run state completed   closed_at set
```

| required | measured |
|---|---|
| W14-S05 accountable role = `quote_evaluation` | registry: `phase_b_workflow_step` W14-S05 `accountable_role_id = quote_evaluation`, `actor_kind = canonical_role`; the step run executed under the same role |
| relevant category overlay = contributor only | W14-S05 `contributors = {relevant_category_overlay, relevant_domain_specialist}`; `relevant_category_overlay` is accountable on **none** of the 257 steps |
| overlay owns no task | joining `phase_c_task` to `org_role` on `runtime_mode = 'knowledge_overlay'` returned **0** across all five drives |
| no unresolved successor | `fn_kernel_workflow_graph_validate()` — every one of the 30 returns `OK`; SUMMARY reports `unresolved successor owners 0` |
| workflow reaches its explicit closure | W14-S09, run state `completed`, `closed_at` set |
| mandatory blockers prevent premature closure | see below |

### The mandatory blocker, tested honestly

A first attempt at this used a payload that was missing its `output` field, and the engine refused
it with `22023 … required fields missing [output]`. That is a payload-validation refusal, not proof
of the review blocker, so it was discarded and redone.

The real test: drive W14 to **W14-S08**, which names `rfq_success` as its independent reviewer, then
attempt closure with a **complete and valid** payload and no verdict recorded.

```
step                  W14-S08
registry_reviewer     rfq_success
close_without_review  refused_by_raise: 23514
  "fn_kernel_step_complete: step W14-S08 names rfq_success as its independent reviewer and no
   approved, independent verdict from that role exists on task 1530. Record it with
   fn_kernel_review_decide first."
```

The blocker holds against a valid payload. Once the verdict was recorded through
`fn_kernel_review_decide`, the same step closed.

---

## Gate 8B — representative execution classes — **PASS**

| class | workflow | steps | handoffs | reviews | last step | run state | closed |
|---|---|---|---|---|---|---|---|
| same-owner multi-step | **W09** (1 owner, 0 handoffs) | 9 | 0 | 9 | W09-S09 | `completed` | yes |
| cross-owner requiring handoffs | **W17** (7 owners, 9 handoffs) | 11 | 9 | 11 | W17-S11 | `completed` | yes |
| internal reviewer | **W14** (1 reviewer) and **W30** (3) | 9 / 11 | 2 / 10 | 9 / 11 | W14-S09 / W30-S11 | `completed` | yes |
| failure-state path | **W05**, S03 completed with `outcome = fail` | 3 | 2 | 3 | W05-S03 | **`blocked`** | **no** |
| cancelled path | **W17** via `fn_kernel_cancel` | 1 | 0 | 0 | — | **`cancelled`** | — |

The failure path is the important negative: a failed step leaves the run `blocked` and **not**
closed, and the driver stopped there rather than walking on.

The cancellation, driven through the canonical canceller in an aborted transaction:

```
fn_kernel_cancel {subject_kind: workflow_run, subject_ref: 539, actor: kernel:acceptance, reason: …}
  -> {"ok":true,"op":"cancel","closed":{"tasks":1,"step_runs":1,"workflow_runs":1,
                                        "handoffs":0,"traces_sealed":2,"outbox_superseded":1}}
  run_state = cancelled   open_step_runs = 0   open_tasks = 0   open_handoffs = 0
```

One outbox row (`EV-W…-STARTED`) survived as `pending`; that is the Gate 5 defect, evidenced in
`PHASE_C_FINAL_COMMAND_CANARY.md`.

### Required outcomes

| required | measured |
|---|---|
| workflows without an executable closure path | **0 of 30** — `fn_kernel_workflow_graph_validate()` SUMMARY: *"workflows with no EXECUTABLE closure path 0 of 30; with no topological closure path 0 of 30"* |
| nonterminal steps treated as terminal | **0** — *"false terminal steps 0"* |
| unresolved successor owners | **0** |
| reachable steps the engine cannot progress from | **0** |
| duplicate successor tasks | **0** — no run held two tasks for one `step_id` |
| duplicate handoff runs on one edge | **0** — no run held two handoff runs for one `handoff_id` |
| workflow completed with open mandatory blockers | **0** |
| step replay creates no additional effect | every step was immediately replayed with the **same idempotency key**; the driver aborted the run if the task count rose by more than the one the step itself creates. It never did, across 43 step completions |

Per the brief, all 30 were not driven end to end: the graph validator proves all 30 statically and
the five runtime drives above prove each execution class.

### One observation, not a gate failure

`fn_kernel_review_decide` **accepts** a verdict on a step whose registry names no independent
reviewer — tested on W14-S01, which has none, and the call returned `ok: true`. Recording an extra
verdict bypasses nothing and no Gate 8 requirement covers it. It is recorded so it is not
discovered later as a surprise. The related detail is that
`phase_c_workflow_step_run.reviewer_role_id` is written as `coalesce(independent_reviewer_role_id,'')`
— an empty string, not NULL — so a reader testing `is not null` sees a reviewer on every step.

---

## Gate 9 — kernel-only business writes — **PASS**

Thirty-two direct writes: eight protected tables × four identities. Each inside a transaction that
always aborted, each under `set local role`, and each with **column names taken from
`information_schema`**, so that no refusal could be a parse error dressed up as a guard. (A first
pass used guessed column names and produced eight `42703 column does not exist` results; those were
discarded and the whole matrix rerun.)

| identity | phase_c_workflow_run | workflow_step_run | task | handoff_run | trigger_inbox | signal_inbox | event_outbox | refund_decision |
|---|---|---|---|---|---|---|---|---|
| `anon` | 42501 | 42501 | 42501 | 42501 | 42501 | 42501 | 42501 | 42501 |
| `authenticated` | 42501 | 42501 | 42501 | 42501 | 42501 | 42501 | 42501 | 42501 |
| `service_role` | guard | guard | guard | guard | guard | guard | guard | guard |
| `service_role` + forged kernel context | guard | guard | guard | guard | guard | guard | guard | guard |

`42501` for `anon` / `authenticated` is `permission denied for table …`. "guard" is
`42501 INSERT on public.… is refused: no routine with write authority for this table is on the call
stack`, raised by `fn_kernel_write_guard` with the call stack in the DETAIL.

The forged context set `kernel.maintenance_reason`, `kernel.writer` **and** `app.kernel_context`
before the write. All eight were refused identically.

### DIRECT BUSINESS WRITES ACCEPTED OUTSIDE THE KERNEL: **0 of 32**

### The guard is not simply dead

`fn_kernel_write_guard` has `prosecdef = false` — **SECURITY INVOKER** — so `current_user` inside it
is the caller, not the table owner. This is the K37 condition, verified at the catalogue rather than
taken from the closure document.

Positive control: authorised kernel writes were accepted throughout Gate 8 — 5 workflow runs
created, 43 step runs opened and closed, 21 handoff runs opened and accepted, 43 tasks created, all
through `fn_kernel_workflow_start`, `fn_kernel_open_step`, `fn_kernel_step_complete` and
`fn_kernel_handoff_accept`, each of which appears in `kernel_write_authority` against the table it
writes.

### Coverage

`a00_kernel_write_guard` is present on all eight tables, BEFORE INSERT OR UPDATE OR DELETE, FOR EACH
ROW, with the `a00_` prefix that makes it fire first:

```
kernel_signal_inbox        kernel_trigger_inbox        phase_c_event_outbox
phase_c_handoff_run        phase_c_refund_decision     phase_c_task
phase_c_workflow_run       phase_c_workflow_step_run
```

Review verdicts are written on `phase_c_task` by `fn_kernel_review_decide` and are covered by the
same guard. Founder refund decisions carry two further triggers:
`a00_phase_c_refund_decision_immutable` (BEFORE DELETE OR UPDATE) and
`z10_phase_c_refund_decision_guard` (BEFORE INSERT OR UPDATE).

Audit and maintenance access is a distinct, recorded operation: the maintenance door checks the
table owner before the one privileged act and writes `kernel_maintenance_write`.
