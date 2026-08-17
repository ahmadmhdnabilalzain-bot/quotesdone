# Phase C final acceptance — trace integrity and system-execution instrumentation

Gates 12, 13 and 15. Current operational state is reported separately from preserved historical
exceptions, as required.

---

## Gate 12 — trace integrity — **PASS**

### Current operational state, measured independently

Each row below is my own query against the live tables, not a reading of the builder's state
function.

| required | measured |
|---|---|
| active commands without trace | **0** |
| active workflow runs without trace | **0** |
| active step runs without trace | **0** |
| active tasks without trace | **0** |
| active handoffs without trace | **0** |
| new state-changing system executions without trace | **0 of 516** wrapped cron executions since the kernel epoch |
| terminal current objects with incomplete or open trace | **0** |
| active orphan traces | **0** created after the kernel epoch |
| sealed traces without `sealed_at` | **0** |
| failed duplicate/idempotent inserts leaving orphan traces | **0** — the Gate 4 idempotent replay produced no new trace; the Gate 6 duplicate source delivery produced no new trace |

One caveat is stated rather than hidden: the builder's
`fn_kernel_historical_register_state.queued_work_beneath_cancelled_commands` reports **0**, but it
joins only `phase_c_task` to `founder_command` and never looks at `phase_c_workflow_run` or
`phase_c_workflow_step_run`. Run 538 and step run 531 are open beneath cancelled command 338 and are
invisible to it. That is reported as part of the **Gate 5** failure, not as a Gate 12 failure, since
every Gate 12 requirement above is about traces and holds.

### Historical exceptions — preserved, labelled, never presented as compliance

| required | measured |
|---|---|
| exactly 38 historical exceptions, or the currently committed exact count | **38** |
| every historical exception explicitly labelled | 38 of 38 carry a class |
| no historical retrofit presented as contemporaneous evidence | **0 of 38** dated after the kernel cutover; **0 of 38** without an original timestamp; **0 of 38** without a recorded reason it cannot be reconstructed |
| no active effect remains from a historical duplicate/cancellation defect | **0 of 6** |
| register append-only | a trigger refusing UPDATE and DELETE is present |

The 38, by class:

```
HISTORICAL_STATE_TRACE_MISMATCH   22
HISTORICAL_ORPHAN_TRACE            7
HISTORICAL_DUPLICATE_EFFECT        6
VALID_HISTORICAL_RECORD            3
                                  ——
                                  38      plus 31 retrofit entries, recorded as retrofits
```

The register also reports, on their own informational lines and never as coverage: 16,941 of 17,457
wrapped-cron firings predate the kernel epoch and have no trace *by design*; 191,190 of 192,681
cron firings on record predate the epoch; and 428 of 633 components on TRACE-SYSTEM-EXECUTION are
edge functions, database triggers or event subscriptions whose invocation log this database does not
hold, so their coverage is stated as **unknown, not 100%**. That distinction is correct and is the
reason this gate passes rather than being quietly inflated.

**GATE 12: PASS**

---

## Gate 13 — system-execution instrumentation — **FAIL**

### The register is complete

Across the **595 active** components, of which **566 change state**:

| required | measured |
|---|---|
| accountable role missing | **0** |
| system actor missing | **0** |
| authority missing | **0** |
| workflow/step or justified scope missing | **0** |
| trace policy missing on a state-changing component | **0** |
| active state-changing component without trace instrumentation | **0** |
| active state-changing cron components not wrapped | **0 of 22** |
| business-state-changing component using a read-only trace exemption | **0** |

On that last line: a first, crude reading counted 128 state-changing components whose policy was not
`TRACE-SYSTEM-EXECUTION` and would have reported them as a failure. Resolving the policies showed
they are business trace policies, not read-only exemptions —

```
TRACE-SYSTEM-EXECUTION  438
TRACE-WORKFLOW          119
TRACE-ROLE-ACTION         9
                        ———
                        566
```

— so the correct figure is **0**, and the earlier number is recorded here only so the correction is
visible rather than silent. Separately, 23 components were moved off TRACE-SYSTEM-EXECUTION with a
recorded exemption; **0 of those 23** change state.

### One safe, zero-cost firing per execution class

| class | firing | trace produced |
|---|---|---|
| **cron job** | `fn_kernel_cron_exec(103)` — `policy_consistency_weekly`, a READ_ONLY_MONITOR — inside an aborted transaction | trace **5523**, `+1 phase_c_system_execution`. component `cron:policy_consistency_weekly`, policy `TRACE-SYSTEM-EXECUTION`, system actor `system.scheduler`, accountable role `general_counsel`, authority `allowed_autonomous:legal_contract_within`, status `sealed` |
| **database trigger** | insert into `public.contact_messages` (Gate 6), aborted | **5** trace rows under the resulting W18 run |
| **edge function** | `POST /functions/v1/os_api` founder command (Gate 4) | **4** traces — 2 root, 2 child |
| **frontend path** | the same `os_api` door the OS shell calls — clarify and cancel (Gate 5) | traces on command 338, including the 2 that were left unsealed by the cancel defect |

All components were not fired, as the brief allows.

### The failure

`fn_kernel_system_trace_state` returns **1 failing of 13** checks:

```
check   system_execution_traces_without_a_complete_record
expect  0 of the traces under TRACE-SYSTEM-EXECUTION
actual  1 of 517
ok      false
```

The offending trace:

```
trace_id           3730
component_id       dbfn:fn_kernel_trigger_submit(jsonb)
trace_policy_id    TRACE-SYSTEM-EXECUTION
subject            trigger_inbox 46
system_actor_id    system.health_monitor
accountable_role   it_operations_engineer
status             sealed
created_at         2026-08-17 05:05:00.033303+00
```

No row in `public.phase_c_system_execution` carries `trace_id = 3730`. The check's definition is
sound — a trace under this policy must have an execution record — and it is the trace, not the
check, that is incomplete.

**This is not residue from this acceptance.** Trace 3730 was created at **05:05 UTC**, roughly ten
hours before this session opened at 15:03 UTC. `PHASE_C_BUILDER_CLOSURE.md` states
`fn_kernel_system_trace_state` is "0 of 13"; at acceptance time the instrument says otherwise.

**Smallest responsible component:** whichever path wrote trace 3730 without its paired
`phase_c_system_execution` record. The trace names `dbfn:fn_kernel_trigger_submit(jsonb)` under
system actor `system.health_monitor`, against trigger-inbox row 46 — one system-execution wrapper
firing that recorded its trace and not its execution.

**GATE 13: FAIL**

---

## Gate 15 — guard quality — **FAIL**

### The suites

`scripts/checks/phase_c_guards_reject_injected_defects.test.mjs`:

```
55/55 injected defects refused

row counts before/after every aborted injection
  tasks 48   cmds 13   msgs 13   appr 0   runs 14
  outbox 29   traces 714   handoffs 7   release_appr 1   probe_components 0
  — all unchanged
```

`scripts/checks/phase_b_guards_reject_injected_defects.test.mjs`:

```
20/20 guards fired
row counts unchanged: steps 257, handoffs 159, exceptions 50
```

The Phase B suite is the positive-control set and behaves correctly in both directions, including
the pair that must *open*: *"frozen architecture changed with no change request"* is refused and
*"frozen architecture changed WITH a change request"* is permitted — the freeze is a gate, not a
wall.

| required | measured | |
|---|---|---|
| injected defects executed: 55 | **55** | ok |
| injected defects refused: 55 | **55** | ok |
| positive controls accepted: exact expected count | **20 of 20** in the Phase B suite; in the Phase C suite the 21 `VALUE_CASES` and 7 `SEQ_CASES` each assert an accepted result and all 28 pass | ok |
| stale human-message assertions = 0 | **0** — every case passes today | ok |
| row counts unchanged after refused operations | **10 of 10** counters unchanged; 0 probe components persisted | ok |
| **assertions use SQLSTATE, structured refusal code or result status** | **23 of 55 do not** | **FAIL** |

### The failure

The Phase C suite has three case blocks:

| block | cases | what the assertion is |
|---|---|---|
| `CASES` | 26 | a substring the raised message must contain — **or**, in the new form, a `[SQLSTATE, raising guard]` pair |
| `VALUE_CASES` | 21 | a returned value or result status — permitted by the gate |
| `SEQ_CASES` | 7 | a returned value or result status — permitted by the gate |

Only **three** of the 26 `CASES` use the structured pair:

```
['28000', 'fn_phase_c_require_founder']
['23514', 'fn_phase_c_refund_decision_guard']
['23514', 'fn_kernel_workflow_run_trace_guard']
```

The other **23** match on prose — for example `'does not resolve to an active canonical role'`,
`'is not an approval path any more'`, `'is not a second pair of eyes'`. None is stale today. Every
one of them is a single message edit away from becoming stale, which is the condition this gate
exists to remove; the file already supports the structured form, so the remedy is mechanical.

The builder's closure is accurate about what it did — it converted three stale messages to SQLSTATE
plus the raising guard, fixed two cases that tested a retired path, corrected two that encoded a
pre-kernel expectation, and fixed `fn_phase_c_outbox_settle` itself. The gate asks for the
conversion to cover **all** refusal assertions, and it does not.

**Smallest responsible component:** the `CASES` array in
`scripts/checks/phase_c_guards_reject_injected_defects.test.mjs` — 23 of its 26 `expect` values are
prose substrings rather than the `[SQLSTATE, guard]` pair used by the other three.

**GATE 15: FAIL**
