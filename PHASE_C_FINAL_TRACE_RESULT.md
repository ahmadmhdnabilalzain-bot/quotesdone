# Gate 14 — trace and system-execution integrity

Current operational state is reported separately from historical exceptions throughout, because the
two are measured by different functions and answering with one number would hide the other.

## Current state — clean

`fn_kernel_trace_integrity()`, live:

| check | actual | required |
|---|---|---|
| active objects without a trace — step_run | 0 of 24 | 0 |
| active objects without a trace — founder_command | 0 of 18 | 0 |
| active objects without a trace — handoff_run | 0 of 7 | 0 |
| active objects without a trace — task | 0 of 52 | 0 |
| active objects without a trace — workflow_run | 0 of 18 | 0 |
| terminal objects with an open trace — all five kinds | 0 | 0 |
| traces sealed with no `sealed_at` | 0 of 1171 | 0 |
| `sealed_at` set but status open | 0 of 1171 | 0 |
| orphan traces — founder_command / workflow_run / step_run | 0 / 0 / 0 | 0 |
| orphan traces — handoff, unresolvable subject_ref | 0 of 1171 | 0 |
| orphan traces — system_execution | 0 of 1171 | 0 |
| completed traces still mutable | 0 of 1171 | 0 |

`fn_kernel_historical_repair_state()` confirms the same from the other side:

| check | actual |
|---|---|
| active duplicate founder-command effects | 0 of 15 |
| queued work derived from cancelled commands | 0 of 46 |
| terminal objects with an open trace | 0 of 230 |
| active orphan traces | 0 of 1171 |
| unlabelled retrofits | 0 of 32 |
| object states not in the state model | 0 of 119 |

## System execution — begin/finish/fail create subject and trace atomically

`fn_kernel_system_trace_state()`:

| check | actual |
|---|---|
| new state-changing system executions with the required trace | **933 of 933** since the epoch |
| new state-changing system executions missing a trace | 0 of 933 |
| active state-changing cron components not wrapped | 0 of 22 |
| state-changing components sitting on a read-only policy | 0 of 23 |
| read-only components without a recorded exemption | 0 of 23 |
| system-execution traces without a complete record | 0 of 934 |
| new system executions claiming founder authority | 0 of 934 |
| new system executions recorded as failed | 0 of 934 |

Observed directly rather than inferred: the scheduled `ai_health` firing at 04:37:00 UTC wrote
`phase_c_system_execution` and `phase_c_trace` 20942 in the same statement, with
`started_at 04:37:00.022539`, `finished_at 04:37:00.027490`, `recorded_at 04:37:00.020332`,
`state_before scheduled_due`, `state_after succeeded`, `correlation_id` and `causation_id`
`cron.job/102@2026-08-18T04:37:00.022Z`, and `authority_result allowed_autonomous:...`.

`fn_kernel_cron_exec` runs the original command in a sub-transaction so a failure rolls the work back
and still leaves the trace writable; the ponytail note in the body states the consequence honestly —
`cron.job_run_details` will read *succeeded* for a run whose work failed, and the trace carries
`result='failed'` with the SQLSTATE instead.

**Bound stated:** the four safe aborted cases the brief asks for (successful begin/finish, failed
execution, duplicate idempotency key, subject-insert failure, finish failure) were **not** driven as
five separate probes in this audit. What was measured is the live population above plus one real
scheduled execution end to end.

## Trace 3730

| requirement | measured |
|---|---|
| original trace row not edited | `trace_id 3730`, `created_at` = `sealed_at` = `2026-08-17T05:05:00.033303+00`, `subject_kind` still `trigger_inbox`, `subject_ref` still `46`, `status sealed`, `superseded_by` null |
| reconstructed execution labelled a historical reconstruction | yes — the reconstruction carries the original instant in `started_at` and the repair instant in `recorded_at`, and `repair_action` says so in words |
| not presented as contemporaneous evidence | `cannot_reconstruct` states: the execution is fully reconstructable; what cannot be reconstructed is a *contemporaneous* execution row, because none was ever written |
| immutable repair relationship and reason | `repair_id 83` (`entry_kind CLASSIFICATION`, migration `rc4_execution_and_trace_are_atomic.sql`) was **superseded**, not rewritten, by `repair_id 85` (`entry_kind RETROFIT`, `retrofit_label CORRECTION 17 Aug 2026`, migration `rc4b_3730_is_not_history.sql`) |

The correction is itself worth recording: repair 83 had classified 3730 as `HISTORICAL_ORPHAN_TRACE`,
and repair 85 states plainly that this was wrong — 3730 was created at 05:05 on 17 Aug, **after** the
kernel cutover at 2026-08-16 23:18:23, so it was a live defect of the kernel era that was repaired,
not a preserved historical exception. The correction did not delete the earlier row.

`fn_phase_c_trace_append_only` refuses editing a sealed trace, which is why the original survives
unchanged; `completed_traces_still_mutable` is 0 of 1171 independently.

## Historical exceptions — the count reconciles to 38

The expected builder claim is 38. The raw table holds more than that, so the arithmetic matters:

| | |
|---|---|
| `phase_c_historical_repair` rows total | 71 |
| of which retrofits | 32 |
| of which classifications | **39** |
| `HISTORICAL_STATE_TRACE_MISMATCH` | 22 |
| `HISTORICAL_ORPHAN_TRACE` | 8 |
| `HISTORICAL_DUPLICATE_EFFECT` | 6 |
| `HISTORICAL_CANCEL_PROPAGATION_FAILURE` | 0 |
| `VALID_HISTORICAL_RECORD` | 3 |
| less repair_id 83, superseded by repair_id 85 | −1 |
| **effective historical exceptions** | **38** |

39 classifications minus the one supersession is exactly the committed 38. All are labelled, none
carries an active effect (`active_effect_now = false` on both 3730 rows; `active orphan traces` 0),
and `unlabelled_retrofits` is 0 of 32 — no retrofit is presented as contemporaneous evidence.

## Where the deployed board disagrees with itself

`fn_kernel_trace_integrity()` also carries five rows that are red:

| check | actual | reading |
|---|---|---|
| `trace_state_disagrees_with_subject_workflow_run` | 4 of 18 | inside the 22 labelled `HISTORICAL_STATE_TRACE_MISMATCH` |
| `trace_state_disagrees_with_subject_handoff_run` | 1 of 7 | same population |
| `orphan_traces_task` | 7 of 1171 | inside the 8 labelled `HISTORICAL_ORPHAN_TRACE` |
| `traces_with_unmapped_subject_kind` | 1 of 1171 | trace 3730's `trigger_inbox` subject kind |
| `system_execution_components_with_no_trace` | **589 of 635** | 430 of the 635 are edge functions, database triggers or event subscriptions for which this database holds no invocation log — `fn_kernel_system_trace_state` says so explicitly and declines to score them |

None of these is a current-state defect: `fn_kernel_historical_repair_state()` accounts for the first
four as labelled historical exceptions and `fn_kernel_system_trace_state()` accounts for the fifth as
unobservable-from-this-database. **Gate 14 therefore passes on current operational state.**

What does not pass is the instrumentation around it: `fn_kernel_trace_integrity()` is read by no test
and no CI job, and it reports these five as failures against an expected `0`. A reader looking at that
board alone would conclude the trace estate is broken; a reader looking at `npm test` alone would
never see the board at all. That is recorded under the Gate 12 / instrumentation finding in
`PHASE_C_FINAL_ACCEPTANCE_AUDIT.md`, not as a Gate 14 failure.

**Gate 14: PASS.**
