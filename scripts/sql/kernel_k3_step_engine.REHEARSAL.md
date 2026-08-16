# K3 — the canonical step engine: rehearsal

Rehearsed on **htdblwldjkcgjvmqkbeh** (the one project) on **16 Aug 2026, 22:34–23:5x UTC**, in a
single **aborted** transaction: `scripts/sql/kernel_k3_step_engine.sql` and
`scripts/sql/kernel_k3b_graph_validation.sql` were applied, a whole workflow was driven from start
to `completed`, every refusal case was fired, `set constraints all immediate` forced K6's DEFERRABLE
trace triggers to run, the estate's whole invariant board was read, and the last statement raised so
the transaction rolled back. **Nothing was applied to production.** No paid provider was called; no
edge function was invoked.

The lead engineer applies the exact files. The rollback rehearsal is at the bottom.

---

## 1. What was measured first, before anything was built

The session brief says *"96 steps whose `next_step_if_pass` names a real step have NO handoff edge"*
and that the engine must *"report how many of the 96 fall in this class"* (owner change, no handoff).
Re-measured on the frozen registry:

| measurement | value |
|---|---|
| `phase_b_workflow_step` | 257 |
| `next_step_if_pass = 'WORKFLOW_COMPLETE'` | 30 |
| `is_closure_step = true` | 30 |
| both, agreeing, on the same rows | **30 — 0 disagreements** |
| steps naming a real successor | 227 |
| of those, **owner changes** | 161 |
| of those 161, a `phase_b_handoff` edge `(from,to)` exists | **161 — all of them** |
| of those 161, **no** handoff edge | **0** |
| of the 227, **owner stays the same** | 66 |
| of those 66, a handoff edge exists | **0 — and none is owed** |
| `phase_b_handoff` rows | 161 |
| handoff rows whose `(from,to)` equals the sender's `next_step_if_pass` | **161 — all of them** |

**The brief's 96 is 66 + 30.** 66 are same-owner hops with a real successor and no handoff, which the
old consumer reported as the end of the chain; the other 30 are the closure steps, which correctly
have no outgoing edge. The registry-gap class the brief asks about — *owner changes and no handoff
edge is declared* — is **0 of 227**. The guard for it stays in the classifier and fails closed; it
simply has no subjects in today's registry.

Other frozen-registry facts K3 depends on, all re-measured:

- `next_step_if_fail` is **prose in all 257 rows**. K3 never parses it.
- `failure_workflow_state` is **`blocked` in all 257 rows**, and `blocked` is **not terminal** in
  `phase_b_workflow_state` (terminal = completed, cancelled, superseded only). A failed step parks
  the run at `blocked` with a named reason; it does not end it.
- `success_workflow_state`: `completed` 30, `waiting_handoff` 126, `active` 55, `waiting_review` 46 —
  and it agrees with the successor class exactly: all 55 `active` are same-owner hops, all 30
  `completed` are closure steps, 124 of the 126 `waiting_handoff` are owner changes with an edge.
- Every workflow declares `EV-Wnn-STARTED`, `EV-Wnn-COMPLETED`, `EV-Wnn-BLOCKED`. **No workflow
  declares a `.failed` or `.cancelled` event.** All 257 steps declare `EV-Wnn-Snn-COMPLETED`.
- 28 of 257 steps name an independent reviewer; **0 of the 28** fail
  `fn_kernel_reviewer_independent`.
- Before K3: `phase_c_workflow_run` held 4 `cancelled`, 4 `queued`, 1 `active` — **0 completed, ever.**

---

## 2. The registry finding K3 refuses to paper over

**W14-S05 "Validate technical completeness"** carries `actor_kind = 'category_overlay'` and
`accountable_role_id = 'relevant_category_overlay'`. That is a placeholder token, not an overlay id:
`fn_phase_c_resolve_actor` returns `kind = 'unknown'`, reason *"no active canonical role, alias or
system actor named 'relevant_category_overlay'"*. It is **the only step of 257 whose owner does not
resolve.**

**How the engine treats it:** a category overlay advises and may never own a task — that is already
enforced by `z10_phase_c_overlay_not_accountable` on `phase_c_task` — so K3 **refuses** to open a
step run or a task for W14-S05 and raises `23514 k3_no_valid_successor` when W14-S04 passes. It does
not substitute an owner, does not skip the step, and does not fall through to the next one.

Consequence, measured and reported rather than repaired:

- **workflows with no EXECUTABLE closure path: 1 of 30 (W14).**
- workflows with no *topological* closure path: 0 of 30 — the graph is intact; only the ownership is not.
- **unresolved successor owners: 1** (W14-S05, reached from W14-S04).

Phase B is frozen. Editing `phase_b_workflow_step` to name a real owner would make both numbers
green and would be a Phase B change dressed as a Phase C fix. It has not been done. This needs a
Phase B change request (`docs/phase-b/PHASE_B_CHANGE_REQUEST_TEMPLATE.md`) naming the canonical role
that owns technical validation in W14, with the overlay left as an advisor.

A second, smaller finding: **`phase_b_business_rule` holds 47 `hard` rules as prose with no machine
predicate.** K3 records the hard rules in scope on the run's `closure_evidence` and on its trace, and
does **not** score them. A rule scorer that can only return pass is worse than no scorer; this is a
stated Phase C gap, not a silent one. Closure blocks on the four measurable blocker classes and on
the hard gates instead.

---

## 3. Verbatim transcript — one aborted production transaction

```
Failed to run sql query: ERROR:  P0001: K3 REHEARSAL (aborted)
A00 start        run=204 state=active step=W06-S01 step_run=194 task=1084 handoff=-
R2 wrong actor   REFUSED 23514 | fn_kernel_step_complete: step W06-S01 is accountable to inquiry_router and cfo holds no active delegation for it. Phase B froze step ownership; Phase C does not reassign it at runtime. (k3_not_the_accountable_owner)
R3a output absent REFUSED 22023 | fn_kernel_step_complete: step W06-S01 passed with no output key at all. The step contract asks for Routing evidence set.. (k3_output_key_absent)
R3b output json null REFUSED 22023 | fn_kernel_step_complete: step W06-S01 sent output as a JSON null. A null is a stated absence of a result, not a result. (k3_output_is_json_null)
R3c output empty  REFUSED 22023 | fn_kernel_step_complete: step W06-S01 sent an empty output object. An empty object is not evidence that anything was produced. (k3_output_empty)
R7 inputs missing REFUSED 22023 | fn_kernel_step_complete: step W06-S01 declares required inputs (Workflow record; prior accepted outputs; applicable policy.) and the call names none. Send inputs as a non-empty object. (k3_required_inputs_missing)
A01 W06-S01 pass succ=same_owner next=W06-S02 new_step_run=195 new_task=1085 run_state=active created={"tasks": 1, "events": 1, "handoffs": 0, "step_runs": 1}
A02 W06-S02 pass succ=same_owner next=W06-S03 new_step_run=196 run_state=active created={"tasks": 1, "events": 1, "handoffs": 0, "step_runs": 1}
A03 W06-S03 pass succ=cross_owner handoff=H-W06-03-04 handoff_run=131 next_step_run=NONE run_state=waiting_handoff created={"tasks": 0, "events": 1, "handoffs": 1, "step_runs": 0}
A04 accept H-W06-03-04      to_step=W06-S04 step_run=197 task=1087 accountable_now=rfq_qualification_manager run_state=active
A05 W06-S04 pass succ=cross_owner handoff_run=132 run_state=waiting_handoff created={"tasks": 0, "events": 1, "handoffs": 1, "step_runs": 0}
A06 accept H-W06-04-05      to_step=W06-S05 step_run=198 task=1088 run_state=active
R6 reviewer missing REFUSED 23514 | fn_kernel_step_complete: step W06-S05 names inquiry_quality_analyst as its independent reviewer and no approved, independent verdict from that role exists on task 1088. Record it with fn_kernel_review_decide first. (k3_reviewer_verdict_missing)
A07 review       ok=true reviewer=inquiry_quality_analyst independent=true trace=2239
A08 W06-S05 pass succ=cross_owner handoff_run=133 run_state=waiting_handoff created={"tasks": 0, "events": 1, "handoffs": 1, "step_runs": 0}
A09 accept H-W06-05-06      to_step=W06-S06 step_run=199 run_state=active
A10 W06-S06 pass succ=cross_owner handoff_run=134 run_state=waiting_handoff
A11 accept H-W06-06-07      to_step=W06-S07 step_run=200 run_state=active
A12 W06-S07 pass succ=closure run_state=completed terminal=true blockers=[] ev_step=EV-W06-S07-COMPLETED ev_wf=EV-W06-COMPLETED created={"tasks": 0, "events": 2, "handoffs": 0, "step_runs": 0}
A13 run 204 FINAL state=completed closed_at=t | step_runs=7 tasks=7 handoffs=4 events=9
A14 step run states: W06-S01=completed, W06-S02=completed, W06-S03=completed, W06-S04=completed, W06-S05=completed, W06-S06=completed, W06-S07=completed
A15 task states:     W06-S01=completed, W06-S02=completed, W06-S03=completed, W06-S04=completed, W06-S05=completed, W06-S06=completed, W06-S07=completed
A16 handoff states:  H-W06-03-04=accepted/acct=rfq_qualification_manager, H-W06-04-05=accepted/acct=inquiry_router, H-W06-05-06=accepted/acct=rfq_qualification_manager, H-W06-06-07=accepted/acct=inquiry_router
A17 events emitted:  EV-W06-STARTED, EV-W06-S01-COMPLETED, EV-W06-S02-COMPLETED, EV-W06-S03-COMPLETED, EV-W06-S04-COMPLETED, EV-W06-S05-COMPLETED, EV-W06-S06-COMPLETED, EV-W06-S07-COMPLETED, EV-W06-COMPLETED
A18 run trace 2195 sealed=sealed | traces on run=25, unsealed=0
B01 REPLAY key=zz-k3-A-S07 replay=true ok=true run_state=completed | step_runs 7->7 tasks 7->7 handoffs 4->4 events 9->9 | DELTAS 0/0/0/0
R5 closure blocked REFUSED 23514 | fn_kernel_step_complete: run 205 cannot close — 3 mandatory blocker class(es) are open: [{"count": 1, "detail": "W06-S01=active", "blocker": "open_step_runs"}, {"count": 1, "detail": "1091=queued", "blocker": "open_tasks"}, {"count": 6, "detail": "W06-S01, W06-S02, W06-S03, W06-S04, W06-S05, W06-S06", "blocker": "mandatory_steps_never_executed"}]. (k3_closure_blocked)
R4 no successor  REFUSED 23514 | fn_kernel_step_complete: step W14-S04 passed and has no valid successor [successor_owner_unresolved]: step W14-S04 declares successor W14-S05, whose accountable_role_id 'relevant_category_overlay' does not resolve to an active canonical role (no active canonical role, alias or system actor named 'relevant_category_overlay'). A category overlay advises and may never own a task, so no step run and no task may be opened for it. (k3_no_valid_successor)
E01 W03-S01 by deputy delegated=true authority=delegated: business_development acted for chief_revenue_officer under an active delegation_rule succ=cross_owner run_state=waiting_handoff
F01 W06-S01 fail step_state=failed run_state=blocked terminal=false ev_wf=EV-W06-BLOCKED created={"tasks": 0, "events": 1, "handoffs": 0, "step_runs": 0}
G01 consume outbox 495 -> run:204 handled=true created=-
G01 consume outbox 496 -> kernel_opened:W06-S02 handled=true created=0
G01 consume outbox 497 -> kernel_opened:W06-S03 handled=true created=0
G01 consume outbox 498 -> kernel_handoff:H-W06-03-04 handled=true created=0
G01 consume outbox 499 -> kernel_handoff:H-W06-04-05 handled=true created=0
G01 consume outbox 500 -> kernel_handoff:H-W06-05-06 handled=true created=0
G01 consume outbox 501 -> kernel_handoff:H-W06-06-07 handled=true created=0
G01 consume outbox 502 -> closure_step:W06-S07 handled=true created=0
G01 consume outbox 503 -> run_completed:204 handled=true created=0
G02 delivery created tasks=0 step_runs=0 (must be 0 and 0)
H01 re-entry     REFUSED 23514 | re-entry refused: fn_kernel_step_complete is a kernel writer and was called from event delivery
I01 unsealed traces on run 204: (none)
I02 superseded-or-sealed of those unsealed: 0 of 0
K3b W01     steps=8   start=W01-S01  reach=8   unreach=0 cyc=0 no_succ=0 not_a_step=0 bad_owner=0 gap=0 false_term=0 same_owner_noedge=0   own_unres=0 closure=1 topo=t exec=t fail_ok=t OK :: clean
K3b W02     steps=9   start=W02-S01  reach=9   unreach=0 cyc=0 no_succ=0 not_a_step=0 bad_owner=0 gap=0 false_term=0 same_owner_noedge=0   own_unres=0 closure=1 topo=t exec=t fail_ok=t OK :: clean
K3b W03     steps=9   start=W03-S01  reach=9   unreach=0 cyc=0 no_succ=0 not_a_step=0 bad_owner=0 gap=0 false_term=0 same_owner_noedge=0   own_unres=0 closure=1 topo=t exec=t fail_ok=t OK :: clean
K3b W04     steps=7   start=W04-S01  reach=7   unreach=0 cyc=0 no_succ=0 not_a_step=0 bad_owner=0 gap=0 false_term=0 same_owner_noedge=6   own_unres=0 closure=1 topo=t exec=t fail_ok=t OK :: clean
    ... W05 through W13 and W15 through W30 all: unreach=0 cyc=0 no_succ=0 not_a_step=0
        bad_owner=0 gap=0 false_term=0 own_unres=0 closure=1 topo=t exec=t fail_ok=t OK :: clean
        (the full 30 rows are in docs/phase-c-kernel/K3_WORKFLOW_CLOSURE.csv)
K3b W14     steps=9   start=W14-S01  reach=9   unreach=0 cyc=0 no_succ=1 not_a_step=0 bad_owner=1 gap=0 false_term=0 same_owner_noedge=4   own_unres=1 closure=1 topo=t exec=f fail_ok=t REGISTRY_DEFECT :: 1 reachable step(s) the engine cannot progress from; 1 successor owner(s) that do not resolve to an active canonical role; 1 step owner(s) unresolved; closure is topologically reachable but NOT executable: the walk stops at a step the engine refuses to open
K3b W30     steps=11  start=W30-S01  reach=11  unreach=0 cyc=0 no_succ=0 not_a_step=0 bad_owner=0 gap=0 false_term=0 same_owner_noedge=0   own_unres=0 closure=1 topo=t exec=t fail_ok=t OK :: clean
K3b SUMMARY steps=257 start=-        reach=257 unreach=0 cyc=0 no_succ=1 not_a_step=0 bad_owner=1 gap=0 false_term=0 same_owner_noedge=66  own_unres=1 closure=30 topo=t exec=f fail_ok=t REGISTRY_DEFECT :: workflows with no EXECUTABLE closure path 1 of 30; with no topological closure path 0 of 30; reachable steps the engine cannot progress from 1; false terminal steps 0; unresolved successor owners 1; registry gaps with no handoff 0; successors that are not a step 0; cycles 0; step owners unresolved 1; legitimate same-owner hops with no handoff edge 66 (not a defect)
J01 phase_a_baseline_drift rows=0 | phase_b_baseline_drift rows=0 (both must be 0)
J02 phase_c_baseline_drift rows=1 :: outbox_dead_letter approved=0 live=1
J03 FAILING phase_c_invariants :: outbox_dead_letter | expected=0 actual=1
J03 FAILING kernel_trace_integrity :: terminal_objects_with_open_trace_handoff_run | expected=0 actual=1 of 10
J03 FAILING kernel_trace_integrity :: trace_state_disagrees_with_subject_handoff_run | expected=0 actual=1 of 10
J03 FAILING kernel_trace_integrity :: trace_state_disagrees_with_subject_workflow_run | expected=0 actual=6 of 15
J03 FAILING kernel_trace_integrity :: orphan_traces_task | expected=0 actual=7 of 210
J03 FAILING kernel_trace_integrity :: system_execution_components_with_no_trace | expected=0 actual=609 of 656
J03 FAILING kernel_trace_integrity :: traces_written_under_trace_system_execution | expected=more than 0 actual=0 of 210
J03 FAILING kernel_orphaned_work :: open_traces_of_cancelled_subjects | expected=0 actual=4 of 56
J04 board totals: invariants 70/71 ok, trace 25/31, orphaned 5/6, review 4/4, exposure 5/5, founder 5/5, paid 5/5
K3 REHEARSAL END — transaction rolled back
CONTEXT:  PL/pgSQL function inline_code_block line 5 at RAISE
```

---

## 4. Reading the transcript

### The whole workflow closed (A00–A18)

**W06 "Category routing"** was chosen because it exercises every progression class in one run: two
same-owner hops (S01→S02, S02→S03), four cross-owner handoffs, one step with an independent reviewer
(S05, `inquiry_quality_analyst`), and a closure step. The run reached
**`state=completed`, `closed_at` set, run trace `sealed`**, with **7 step runs all `completed`,
7 tasks all `completed`, 4 handoffs all `accepted`, 9 events** — and **0 unsealed traces** on the run.

**A01 and A02 are the defect this increment exists to fix.** `W06-S01 → W06-S02` and
`W06-S02 → W06-S03` carry no `phase_b_handoff` row. Under the old consumer both would have returned
`handled=true, downstream_ref='no_edge_for_declared_successor:...'` and the chain would have stopped
two steps in. K3 classifies them `same_owner`, opens the next step run and exactly one next task, and
**invents no handoff** (`"handoffs": 0`).

**A03 is the other half.** `W06-S03 → W06-S04` changes owner, so K3 opens the declared handoff
`H-W06-03-04` and creates **`next_step_run=NONE`, `"tasks": 0`**. The receiving owner has no task
until they accept. A04 shows acceptance transferring accountability
(`accountable_now=rfq_qualification_manager`) and only then creating the step run and its one task.

### The five required refusals, plus four more

| case | line | errcode | fired |
|---|---|---|---|
| replay | B01 | — | `replay=true`, **deltas 0/0/0/0** |
| wrong actor | R2 | 23514 | `k3_not_the_accountable_owner` |
| empty output | R3c | 22023 | `k3_output_empty` |
| no successor | R4 | 23514 | `k3_no_valid_successor` (W14-S04) |
| closure with open blocker | R5 | 23514 | `k3_closure_blocked`, 3 classes |
| output key absent | R3a | 22023 | `k3_output_key_absent` |
| output is JSON null | R3b | 22023 | `k3_output_is_json_null` |
| required inputs missing | R7 | 22023 | `k3_required_inputs_missing` |
| reviewer verdict missing | R6 | 23514 | `k3_reviewer_verdict_missing` |
| consumer re-entry | H01 | 23514 | `fn_kernel_assert_not_in_delivery` |

**The output refusals are three different errors, not one.** A missing key, a JSON `null` and an
empty object each name what is actually wrong, because they are three different mistakes.

**The replay proof is all four counts, not a flag.** B01 re-called `fn_kernel_step_complete` with the
same `idempotency_key` on the already-closed closure step: step runs 7→7, tasks 7→7, handoffs 4→4,
events 9→9, and the stored result came back with `replay=true`. **0 additional step runs, 0 tasks,
0 handoffs, 0 events.**

**R5 fired three blocker classes at once** on a second W06 run whose closure step was opened while its
entry step was still live: `open_step_runs 1`, `open_tasks 1`,
`mandatory_steps_never_executed 6` — and it named every one.

### Delegated authority (E01)

`W03-S01` is accountable to `chief_revenue_officer`. `business_development` completed it and the
engine recorded `delegated=true`, *"business_development acted for chief_revenue_officer under an
active delegation_rule"*. The identity is resolved on both sides through `fn_phase_c_resolve_actor`,
never string-matched: the `delegation_rule` row stores `when_agent='sales_director'` and
`delegate_to='bd'`, which are aliases, not role ids.

### Failure (F01)

`outcome='fail'` moved the step run to `failed` and the run to `blocked` — the registry's
`failure_workflow_state`, not a parse of `next_step_if_fail` — and emitted `EV-W06-BLOCKED`,
the only failure-shaped event any workflow declares. `terminal_run=false`, correctly: `blocked` is
recoverable in the frozen state model. Getting out of it is `fn_kernel_cancel` or an authorised retry.

### The consumer stopped being the progression engine (G01, G02)

All nine outbox rows of the completed run were delivered. Every one returned `handled=true` with a
specific `downstream_ref` naming what the kernel had already done —
`kernel_opened:W06-S02`, `kernel_handoff:H-W06-03-04`, `closure_step:W06-S07`, `run_completed:204` —
and **`created=0` on every one**. **G02: delivery created 0 tasks and 0 step runs.** Under the old
consumer the four `.completed` events with handoff edges would each have created a task, handing four
receiving owners work they had never accepted.

`downstream_ref` is now never the string `terminal_step:` for a non-terminal step. The only step
reported as terminal is `closure_step:W06-S07`, which is the declared closure step.

---

## 5. K3b — the real numbers

Required by the brief, measured not asserted, from
`fn_kernel_workflow_graph_validate()` over all 30 workflows (full table:
`docs/phase-c-kernel/K3_WORKFLOW_CLOSURE.csv`):

| required | measured | verdict |
|---|---|---|
| workflows with no valid closure path — **0 of 30** | **0 of 30** topologically; **1 of 30** executably (W14) | ✗ for the executable reading, and the reason is a frozen-registry defect, named in §2 |
| reachable nonterminal steps without successor — **0** | **1** (W14-S05, from W14-S04) | ✗ — same one defect |
| false terminal steps — **0** | **0** | ✓ |
| unresolved successor owners — **0** | **1** (W14-S05) | ✗ — same one defect |
| unreachable steps | 0 of 257 | ✓ |
| cycles in step progression | 0 | ✓ |
| valid start per workflow | 30 of 30 | ✓ |
| closure steps explicitly marked (sentinel AND flag) | 30 of 30, 0 disagreements | ✓ |
| failure outcomes map to a declared workflow state | 257 of 257 | ✓ |
| registry gaps: owner change with no handoff | **0 of 227** | ✓ |
| successors that are not a step | **0 of 227** | ✓ |
| same-owner hops with no handoff edge (legitimate, named) | **66** | — |

**Three of the four required zeros are one defect: W14-S05.** They are not tuned. Making them green
means either giving W14-S05 a canonical owner (a Phase B change request) or accepting that W14 has an
advisory step that no runtime can execute. That is a founder-level call about how quotation technical
validation is owned, not an engineering one, and it is not being decided here.

`false_terminal_steps` deserves its definition stated, because the number is 0 and a 0 that cannot be
non-zero is worthless. It is **not** derived from the classifier's own verdict. It counts steps that
have no outgoing `phase_b_handoff` row, are not the declared closure step, and for which the engine
has no successor it can open — the exact shape that stops a chain while reporting success. It has
subjects available: if W14-S05 also had no handoff edge it would be 1. It is 0 because every step in
that shape today is a same-owner hop the engine opens.

---

## 6. Regression check against the whole estate, not just this increment

The board was read **before** K3 (live, nothing applied) and **after** K3 plus the full drive, inside
the aborted transaction. Numerators, not percentages:

| check | before K3 | after K3 + drive | K3's delta |
|---|---|---|---|
| `phase_c_invariants: outbox_dead_letter` | 1 | 1 | **0** |
| `terminal_objects_with_open_trace_handoff_run` | 1 of 3 | 1 of 10 | **0** |
| `trace_state_disagrees_with_subject_handoff_run` | 1 of 3 | 1 of 10 | **0** |
| `trace_state_disagrees_with_subject_workflow_run` | 6 of 10 | 6 of 15 | **0** |
| `orphan_traces_task` | 7 of 99 | 7 of 210 | **0** |
| `system_execution_components_with_no_trace` | 609 of 656 | 609 of 656 | **0** |
| `traces_written_under_trace_system_execution` | 0 of 99 | 0 of 210 | **0** |
| `open_traces_of_cancelled_subjects` | 4 of 56 | 4 of 56 | **0** |

Board totals after: invariants **70/71**, trace **25/31**, orphaned **5/6**, review **4/4**, exposure
**5/5**, founder approval **5/5**, paid provider **5/5**. `fn_phase_a_baseline_drift()` **0 rows**,
`fn_phase_b_baseline_drift()` **0 rows** — Phase A and Phase B untouched.
`fn_phase_c_baseline_drift()` 1 row (`outbox_dead_letter`), pre-existing.

**The first rehearsal of K3 was not clean, and that is why this table exists.** It pushed three of
those numerators up — handoff traces 1→5, workflow-run traces 6→10 — because `phase_c_workflow_run`
and `phase_c_handoff_run` had **no BEFORE UPDATE trace guard**, unlike `phase_c_workflow_step_run` and
`phase_c_task` which have had one since K6. Patching K3's own call sites would have left every other
writer of those two tables producing the same drift, so the fix went where all of them route: one
trigger per table, in the shape the other two already use
(`a00_kernel_workflow_run_trace_guard`, `a00_kernel_handoff_run_trace_guard`).

A third asymmetry surfaced the same way: `fn_phase_c_task_trace_guard` never sealed and superseded
the trace a task is repointed **away** from, though `fn_phase_c_step_run_trace_guard` always has.
Every task walking `queued → assigned → accepted → in_progress → completed` therefore abandoned one
open trace that nothing pointed at — measured at **exactly 7 per 7-task run, 0 of them carrying
`superseded_by`**. No check counts them, which is why they had accumulated unnoticed. K3 adds the
six lines the step-run guard already had. After the fix: **0 unsealed traces on the completed run**
(I01, I02).

The guards **do not back-date** the pre-existing rows. The 6 workflow-run and 1 handoff-run
disagreements from before K3 keep saying what they said; advancing them now would be writing evidence
for a transition nobody recorded. They stay in the numerator and are reported as pre-existing.

K6's DEFERRABLE constraint triggers (`z95_phase_c_task_trace_committed`,
`z95_phase_c_step_run_trace_committed`) fire at COMMIT, which an aborted transaction never reaches.
`set constraints all immediate;` was issued before the final raise so they actually ran. They passed.

---

## 7. Rollback rehearsal

`scripts/sql/rollback/kernel_k3_step_engine.rollback.sql` was applied in a second aborted transaction
immediately after K3 and K3b, with the two replaced function bodies hashed before and after:

```
K3 ROLLBACK REHEARSAL
RB fn_kernel_event_consume pre=ef72995783ba post=ef72995783ba IDENTICAL=t
RB fn_phase_c_task_trace_guard pre=c2ace04ffee5 post=c2ace04ffee5 IDENTICAL=t
RB dropped: step_successor=0 open_step=0 step_complete=0 handoff_accept=0 graph_validate=0 wf_trace_guard=0 ho_trace_guard=0 completion_table=absent (all must be 0/absent)
```

Both replaced routines come back **byte-identical** to their pre-K3 definitions, and every object K3
adds is gone. The rollback **deletes no run, step run, task, handoff, trace or outbox row**: evidence
is superseded, never removed. What rolling back costs is stated at the top of that file.

---

## 8. What the lead engineer applies

```
scripts/sql/kernel_k3_step_engine.sql         # after k5, k2, k6
scripts/sql/kernel_k3b_graph_validation.sql   # after k3 — it calls fn_kernel_step_successor
```

Both are `--apply --ddl`. Every SECURITY DEFINER function K3 **creates** is revoked from `public` and
granted to `service_role` in the same file; the two it **replaces**
(`fn_kernel_event_consume`, `fn_phase_c_task_trace_guard`) use `CREATE OR REPLACE`, which preserves
the ACL, so they carry no revoke. `set search_path to 'public','pg_temp'` is pinned on every function
including the three trigger functions.

After applying, the one number that says K3 landed:

```sql
select count(*) from public.phase_c_workflow_run where state = 'completed';
-- was 0 before K3, and 0 is what "nothing closes a workflow" looks like.
```
