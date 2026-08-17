# Section 2 — repair the pre-kernel historical state: aborted-transaction rehearsal

Everything below was executed against the ONE production project (`htdblwldjkcgjvmqkbeh`) on
17 Aug 2026, inside transactions that end in `raise exception`. **Nothing was applied.** The
project's own clock read `2026-08-16 22:40:57 UTC` at the start of the measurement (Dubai is
UTC+4, so 17 Aug 02:40 local).

The atomicity of the arrangement was verified first, because a rehearsal that silently commits is
worse than no rehearsal:

```sql
create table public.zz_s2_probe(x int);
do $t$ begin raise exception 'S2 ATOMICITY PROBE'; end $t$;
-- then, as a separate request:
select to_regclass('public.zz_s2_probe') is null as rolled_back;
```

```
Error: HTTP 400: ERROR: P0001: S2 ATOMICITY PROBE
[ { "rolled_back": true } ]
```

Every run below submits `scripts/sql/kernel_s2_historical_repair.sql` in full, followed by a probe
block that raises. The driver is `scratchpad/s2_rehearse.mjs`.

---

## 0. The estate is moving under this measurement

Another session is writing to the same project. Between the first and last query of this
rehearsal the trace table went **80 → 93 → 99 → 123 rows**, founder commands 270 and 273 and
tasks 984-989 appeared, and command 270 was created and cancelled inside a 2-second window at
22:39. Every number in this document is therefore stamped with what it counted, and the migration
computes its own population at apply time rather than carrying a hard-coded id list. The four
"terminal object with an open trace" rows created at 22:39 are treated exactly like the four from
10:35 — same class, same repair — but the file records that they are **not** pre-kernel.

---

## 1. BEFORE — the invariant with the ledger empty and no repair statement run

Submitted: the file's Section 1 (views), Section 2 (ledger) and Section 5 (invariant) only, with
the classify and repair blocks cut out at their section markers, then the invariant read and
raised.

```
=== BEFORE (ledger empty, no repair statement has run) ===
FAIL active_duplicate_founder_command_effects................. 2 of 9
FAIL active_orphan_traces..................................... 7 of 99
ok   historical_records_classified_HISTORICAL_CANCEL_PROPAGATI 0 of 0
ok   historical_records_classified_HISTORICAL_DUPLICATE_EFFECT 0 of 0
ok   historical_records_classified_HISTORICAL_ORPHAN_TRACE.... 0 of 0
ok   historical_records_classified_HISTORICAL_STATE_TRACE_MISM 0 of 0
ok   historical_records_classified_VALID_HISTORICAL_RECORD.... 0 of 0
ok   historical_retrofits_recorded............................ 0 of 0
ok   object_states_not_in_the_state_model..................... 0 of 72
ok   queued_work_derived_from_cancelled_commands.............. 0 of 24
ok   raw_traces_carrying_an_s2_retrofit_annotation............ 0 of 99
FAIL terminal_objects_with_open_trace......................... 8 of 92
ok   unlabelled_retrofits..................................... 0 of 0
```

`queued_work_derived_from_cancelled_commands` is **already 0 of 24**. The brief listed
"historical work still queued beneath a cancelled command" as an open defect; it is not one. K4
closed it. This file classifies and checks the class and repairs nothing under it, rather than
claiming a repair it did not make.

---

## 2. AFTER — the whole file, classification and repair, in one aborted transaction

```
=== AFTER (classification + repair applied, same transaction) ===
ok   active_duplicate_founder_command_effects................. 0 of 9
ok   active_orphan_traces..................................... 0 of 123
ok   historical_records_classified_HISTORICAL_CANCEL_PROPAGATI 0 of 24
ok   historical_records_classified_HISTORICAL_DUPLICATE_EFFECT 6 of 24
ok   historical_records_classified_HISTORICAL_ORPHAN_TRACE.... 7 of 24
ok   historical_records_classified_HISTORICAL_STATE_TRACE_MISM 8 of 24
ok   historical_records_classified_VALID_HISTORICAL_RECORD.... 3 of 24
ok   historical_retrofits_recorded............................ 17 of 41
ok   object_states_not_in_the_state_model..................... 0 of 72
ok   queued_work_derived_from_cancelled_commands.............. 0 of 34
ok   raw_traces_carrying_an_s2_retrofit_annotation............ 8 of 123
ok   terminal_objects_with_open_trace......................... 0 of 116
ok   unlabelled_retrofits..................................... 0 of 17
```

Every required check, before → after:

| check | before | after |
|---|---|---|
| `active_duplicate_founder_command_effects` | **2 of 9** | 0 of 9 |
| `queued_work_derived_from_cancelled_commands` | 0 of 24 | 0 of 34 |
| `terminal_objects_with_open_trace` | **8 of 92** | 0 of 116 |
| `active_orphan_traces` | **7 of 99** | 0 of 123 |
| `unlabelled_retrofits` | 0 of 0 | 0 of 17 |

The moving denominators are real, not cosmetic. Traces went 99 → 123 because `fn_kernel_cancel`
wrote its own sealed cancellation traces for the two commands it closed. Tasks derived from a
terminal command went 24 → 34 because ten tasks under commands 223 and 252 joined that population
the moment those commands were cancelled. Both are the repair's own effect on the denominator,
which is why the numerator is reported beside it and never on its own.

---

## 3. The ledger — one row per affected record, written BEFORE any repair statement

24 CLASSIFICATION rows, 17 RETROFIT rows.

```
CLASSIFICATION founder_command  186   HISTORICAL_DUPLICATE_EFFECT       cancelled
CLASSIFICATION founder_command  217   HISTORICAL_DUPLICATE_EFFECT       cancelled
CLASSIFICATION founder_command  222   HISTORICAL_DUPLICATE_EFFECT       cancelled
CLASSIFICATION founder_command  223   HISTORICAL_DUPLICATE_EFFECT       tasks_created
CLASSIFICATION founder_command  227   HISTORICAL_DUPLICATE_EFFECT       cancelled
CLASSIFICATION founder_command  252   HISTORICAL_DUPLICATE_EFFECT       tasks_created
CLASSIFICATION founder_command  269   VALID_HISTORICAL_RECORD           tasks_created
CLASSIFICATION founder_command  270   VALID_HISTORICAL_RECORD           cancelled
CLASSIFICATION founder_command  273   VALID_HISTORICAL_RECORD           tasks_created
CLASSIFICATION trace            490   HISTORICAL_ORPHAN_TRACE           sealed
CLASSIFICATION trace            491   HISTORICAL_ORPHAN_TRACE           sealed
CLASSIFICATION trace            492   HISTORICAL_ORPHAN_TRACE           sealed
CLASSIFICATION trace            520   HISTORICAL_STATE_TRACE_MISMATCH   open
CLASSIFICATION trace            522   HISTORICAL_STATE_TRACE_MISMATCH   open
CLASSIFICATION trace            526   HISTORICAL_STATE_TRACE_MISMATCH   open
CLASSIFICATION trace            527   HISTORICAL_STATE_TRACE_MISMATCH   open
CLASSIFICATION trace            534   HISTORICAL_ORPHAN_TRACE           sealed
CLASSIFICATION trace            536   HISTORICAL_ORPHAN_TRACE           sealed
CLASSIFICATION trace            537   HISTORICAL_ORPHAN_TRACE           sealed
CLASSIFICATION trace            827   HISTORICAL_ORPHAN_TRACE           sealed
CLASSIFICATION trace            1072  HISTORICAL_STATE_TRACE_MISMATCH   open
CLASSIFICATION trace            1073  HISTORICAL_STATE_TRACE_MISMATCH   open
CLASSIFICATION trace            1074  HISTORICAL_STATE_TRACE_MISMATCH   open
CLASSIFICATION trace            1075  HISTORICAL_STATE_TRACE_MISMATCH   open
RETROFIT       founder_command  223   S2-RETROFIT-DUPLICATE-EFFECT-CANCELLED  cancelled
RETROFIT       founder_command  252   S2-RETROFIT-DUPLICATE-EFFECT-CANCELLED  cancelled
RETROFIT       trace            490   S2-RETROFIT-ORPHAN-INVALID              sealed
RETROFIT       trace            491   S2-RETROFIT-ORPHAN-INVALID              sealed
RETROFIT       trace            492   S2-RETROFIT-ORPHAN-INVALID              sealed
RETROFIT       trace            520   S2-RETROFIT-SEAL-TERMINAL-SUBJECT       sealed
RETROFIT       trace            522   S2-RETROFIT-SEAL-TERMINAL-SUBJECT       sealed
RETROFIT       trace            526   S2-RETROFIT-SEAL-TERMINAL-SUBJECT       sealed
RETROFIT       trace            527   S2-RETROFIT-SEAL-TERMINAL-SUBJECT       sealed
RETROFIT       trace            534   S2-RETROFIT-ORPHAN-INVALID              sealed
RETROFIT       trace            536   S2-RETROFIT-ORPHAN-INVALID              sealed
RETROFIT       trace            537   S2-RETROFIT-ORPHAN-INVALID              sealed
RETROFIT       trace            827   S2-RETROFIT-ORPHAN-INVALID              sealed
RETROFIT       trace            1072  S2-RETROFIT-SEAL-TERMINAL-SUBJECT       sealed
RETROFIT       trace            1073  S2-RETROFIT-SEAL-TERMINAL-SUBJECT       sealed
RETROFIT       trace            1074  S2-RETROFIT-SEAL-TERMINAL-SUBJECT       sealed
RETROFIT       trace            1075  S2-RETROFIT-SEAL-TERMINAL-SUBJECT       sealed
```

The full evidence column per row is in `docs/phase-c-kernel/S2_HISTORICAL_CLASSIFICATION.csv`.

---

## 4. A guard that refuses op='supersede' — and it is right

The first draft cancelled the duplicate effects with `op='supersede'`, because superseding reads
better than cancelling for a defect repair. The estate refused it:

```
ERROR: 23514: phase_c_workflow_run 97: transition queued -> superseded is not in the
       frozen Phase B state model
CONTEXT: PL/pgSQL function fn_phase_c_workflow_state_guard() line 5 at RAISE
```

Measured directly rather than argued with:

```sql
select fn_phase_c_workflow_transition_allowed('queued','cancelled'),   -- true
       fn_phase_c_workflow_transition_allowed('queued','superseded'),  -- false
       fn_phase_c_workflow_transition_allowed('active','cancelled'),   -- true
       fn_phase_c_workflow_transition_allowed('active','superseded');  -- false
```

There is **no `superseded` terminal for a workflow run anywhere in the frozen Phase B model**. The
repair uses `op='cancel'`, which the model does allow, and says so in the reason string it writes.

Worth passing on to whoever owns K4: `fn_kernel_cancel` advertises `op='supersede'`, and for any
subject that reaches a workflow run that op cannot succeed under the frozen model. It is an option
that always raises.

---

## 5. Can each check fire? Forced, not assumed

Four defect rows were created **after** the repair had already turned every check green, inside the
same aborted transaction: a new unsealed unclassified orphan trace; a new open trace bound to
task 793, which is completed; a RETROFIT ledger row claiming `wrote_to_row` against a trace that
carries no `s2_retrofit` key; and a queued task under command 186, which is cancelled.

```
=== CAN THE CHECKS FIRE? ===
ok   active_duplicate_founder_command_effects................. 0 of 9
FAIL active_orphan_traces..................................... 1 of 126
ok   object_states_not_in_the_state_model..................... 0 of 73
FAIL queued_work_derived_from_cancelled_commands.............. 1 of 35
FAIL terminal_objects_with_open_trace......................... 1 of 118
FAIL unlabelled_retrofits..................................... 1 of 18
```

Four of the five fired on demand. The fifth, `active_duplicate_founder_command_effects`, was
already **FAIL 2 of 9** in the BEFORE run — it does not need a synthetic row to prove it works.

### The linkable-orphan branch is not dead code

`subject_proven` is false for all seven orphans, so the LINK branch matches nothing today. A
permanent zero is indistinguishable from a branch that cannot run, so it was forced: an orphan
trace was created that a real task genuinely names, and the classifier's own test was read back.

```
probe trace 1763, probe task 1043
  tasks naming this trace  = 1
  classifier verdict       = subject_proven=true  -> repair_action LINK
```

### The ledger cannot be edited, and cannot hold an unlabelled retrofit

```
UPDATE refused: 23514 phase_c_historical_repair is append-only: UPDATE on repair_id 1 is refused
DELETE refused: 23514 phase_c_historical_repair is append-only: DELETE on repair_id 1 is refused
unlabelled RETROFIT refused: 23514 violates check constraint "phase_c_historical_repair_shape_ck"
unknown classification refused: 23514 violates check constraint "phase_c_historical_repair_class_ck"
```

---

## 6. Did the repair break anything that was already green?

`fn_kernel_trace_integrity()` and `fn_kernel_orphaned_work()`, read live before the file and again
inside the aborted transaction after it.

| check | before | after | |
|---|---|---|---|
| `terminal_objects_with_open_trace_handoff_run` | FAIL 1 of 3 | **ok 0 of 3** | fixed |
| `open_traces_of_cancelled_subjects` | FAIL 4 of 56 | **ok 0 of 98** | fixed |
| `orphan_traces_task` | FAIL 7 of 99 | FAIL 7 of 123 | unchanged, preserved on purpose |
| `trace_state_disagrees_with_subject_handoff_run` | FAIL 1 of 3 | FAIL 1 of 3 | unchanged, correctly |
| `system_execution_components_with_no_trace` | FAIL 609 of 656 | FAIL 609 of 656 | unchanged, the real gap |
| `traces_written_under_trace_system_execution` | FAIL 0 of 99 | FAIL 0 of 123 | unchanged, the real gap |
| **`trace_state_disagrees_with_subject_workflow_run`** | **FAIL 6 of 10** | **FAIL 8 of 10** | **worse by 2 — my regression** |

Every other check in both functions is green before and after.

### The +2 is disclosed, not tuned away

`fn_kernel_cancel` writes a fresh sealed cancellation trace, records its id in the run's
`closure_evidence`, and never repoints `phase_c_workflow_run.trace_id`. So runs 97 and 136, which
this repair closes, end up cancelled while the trace they still point at says `queued`. That is
K6's item 6 — the pointer defect — and closing any run at all joins that class.

It could have been avoided by repointing those two runs at their cancellation traces. It was not,
deliberately: six other runs are already on the old convention, and repointing two of eight leaves
one table with two meanings for `trace_id`. Repointing is one decision for all eight and it belongs
to whoever owns K4. Until then the number is 8 of 10 and is visible.

---

## 7. Records left unrepaired, with the reason

* **Handoff run 48's pointer.** Trace 522 is sealed by this file, so
  `terminal_objects_with_open_trace_handoff_run` goes green. `handoff_run.trace_id` still names 522
  rather than the accept trace 523, so `trace_state_disagrees_with_subject_handoff_run` stays 1 of
  3. Same pointer decision as above; not made here.

* **The seven orphan traces are not linked.** For every one of them the task holding the matching
  idempotency key was created **before** the trace and already carries a different trace. The
  timestamps refute the link rather than supporting it. They are marked invalid, with the proof,
  and kept. Deleting them would delete the only surviving evidence that a `BEFORE INSERT` trace
  guard wrote evidence for an insert the idempotency index then discarded.

* **The producer of traces 1072-1075.** They were created at 22:39:28 today and their subjects
  were cancelled at 22:39:30 by a cancellation carrying `fn_kernel_cancel`'s own evidence shape
  (`{"actor": "management@quotesdone.com", "reason": "founder cancel of command 270"}` on traces
  1076-1083). `fn_kernel_cancel`'s live body matches `scripts/sql/kernel_k4_cancellation.sql` at
  step (h), the step that is supposed to seal exactly those rows. **I did not determine why step
  (h) did not match them and I am not going to state a cause I have not proven.** What is measured
  is above. `terminal_objects_with_open_trace` is repaired to 0 and can go red again on the next
  cancellation; that is the check working.

* **A cancel-propagation failure under a command with no workflow run** would be REFUSED rather
  than repaired: `fn_kernel_cancel` reaches such a command only through
  `subject_kind='founder_command'`, which calls `fn_phase_c_require_founder`, and this migration
  will not present itself as the founder in order to close a record. There are zero such rows
  today; the branch is written, and its refusal is recorded in the ledger rather than aborting the
  migration.

---

## 8. Production is untouched

Read back after every run above:

```sql
select to_regclass('public.phase_c_historical_repair') is null as table_absent,     -- true
       to_regclass('public.v_phase_c_object_terminal')  is null as view_absent,     -- true
       to_regprocedure('public.fn_kernel_historical_repair_state()') is null as fn_absent;  -- true
```

No `apply_sql.mjs --apply`, no `--promote`, no `--ddl`, no deploy, no edge-function invocation, no
paid provider call, no mail, no SMS, no customer, supplier or payment effect. Phase A and Phase B
were read and never written.
