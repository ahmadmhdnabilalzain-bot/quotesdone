# K6 — the trace ledger: aborted-transaction rehearsal

Everything below was executed against the ONE production project (`htdblwldjkcgjvmqkbeh`) on
17 Aug 2026, inside transactions that end in `raise exception`. Nothing was applied. The atomicity
of that arrangement was itself verified first, because a rehearsal that silently commits is worse
than no rehearsal:

```sql
create table public.zz_k6_probe2(x int);
do $t$ begin raise exception 'MULTI-STATEMENT ATOMICITY PROBE'; end $t$;
-- then, in a new statement:
select to_regclass('public.zz_k6_probe2') is null as rolled_back;   -->  rolled_back = true
```

Production after all rehearsals: 72 traces, 3 still `status='sealed'` with `sealed_at` NULL,
`phase_c_trace_sealed_ck` absent, 0 triggers on `phase_c_workflow_step_run`,
`fn_kernel_trace_integrity` does not exist, `a00_founder_command_trace_guard` still `tgtype=19`
(BEFORE UPDATE ROW). Untouched.

---

## 1. The three defects, proven live BEFORE the migration

Run as one aborted transaction against the live database. This is the "prove it fires" baseline —
without it, the guards below could be refusing something that was never possible.

```sql
do $probe$
declare t0 int; t1 int; v_step bigint; v_cmd bigint; rpt text := '';
begin
  select count(*) into t0 from public.phase_c_trace;
  insert into public.phase_c_task (source_kind, source_ref, run_id, workflow_id, step_id,
      accountable_role_id, objective, acceptance_criteria, closure_criteria, authority_class,
      idempotency_key)
  values ('workflow_event','PROBE', 136, 'W20','W20-S01','marketing_director','probe','probe','probe',
      'routine_operational_decision','run:136:step:W20-S01')
  on conflict (idempotency_key) do nothing;
  select count(*) into t1 from public.phase_c_trace;
  rpt := rpt || E'\nP1 BEFORE-FIX: skipped ON CONFLICT insert created ' || (t1-t0) || ' trace row(s).';

  insert into public.phase_c_workflow_step_run (run_id, step_id, accountable_role_id, state, idempotency_key)
  values (136,'W20-S02','marketing_director','active','PROBE-K6-STEP')
  returning step_run_id into v_step;
  update public.phase_c_workflow_step_run set state='completed', finished_at=now() where step_run_id=v_step;
  rpt := rpt || E'\nP2 BEFORE-FIX: step_run ' || v_step || ' active->completed, trace_id='
      || coalesce((select trace_id::text from public.phase_c_workflow_step_run where step_run_id=v_step),'NULL')
      || ' — nothing refused it.';

  insert into public.founder_command (message_id, intent_id, outcome, state)
  values (309,'PROBE','probe','in_progress')
  returning command_id into v_cmd;
  rpt := rpt || E'\nP3 BEFORE-FIX: founder_command ' || v_cmd || ' INSERTED at state=in_progress, trace_id='
      || coalesce((select trace_id::text from public.founder_command where command_id=v_cmd),'NULL')
      || ' — the BEFORE UPDATE guard never saw it.';

  raise exception '%', rpt using errcode='23514';
end $probe$;
```

Verbatim output:

```
ERROR:  23514:
P1 BEFORE-FIX: skipped ON CONFLICT insert created 1 trace row(s).
P2 BEFORE-FIX: step_run 83 active->completed, trace_id=NULL — nothing refused it.
P3 BEFORE-FIX: founder_command 263 INSERTED at state=in_progress, trace_id=NULL — the BEFORE UPDATE guard never saw it.
```

All three confirmed. The brief's diagnosis of P1 was right about the mechanism and wrong about the
count: see §4.

---

## 2. How the rehearsal is run

```sql
-- one statement batch, ending in raise; the whole batch is one implicit transaction
\i scripts/sql/kernel_k6_trace_ledger.sql
-- then the probe block below, which ends in `raise exception` and rolls the whole thing back
```

The commit-time assertions are `DEFERRABLE INITIALLY DEFERRED` constraint triggers, so in a
transaction that never commits they would never run. Each probe that must prove one forces it with
`set constraints all immediate`, and the last thing the probe block does is force ALL of them, for
every row the rehearsal touched.

## 3. The probe block

```sql
do $probe$
declare
  s text := ''; t0 int; t1 int; v_task bigint; v_step bigint; v_step2 bigint; v_cmd bigint;
  v_tr bigint; v_old bigint; v_new bigint; v jsonb; r record;
begin
  s := s || E'\n===== INVARIANT IMMEDIATELY AFTER THE MIGRATION (no probe writes yet) =====';
  for r in select * from public.fn_kernel_trace_integrity() order by ok, check_name loop
    s := s || E'\n' || case when r.ok then '  ok  ' else ' FAIL ' end
           || rpad(r.check_name, 50) || ' expected=' || rpad(r.expected,13) || ' actual=' || r.actual;
  end loop;

  -- [A1] an insert that is skipped must add ZERO trace rows
  select count(*) into t0 from public.phase_c_trace;
  insert into public.phase_c_task (...) values (... ,'run:136:step:W20-S01')
  on conflict (idempotency_key) do nothing;
  select count(*) into t1 from public.phase_c_trace;

  -- [A3] an insert that lands gets a trace that names it
  insert into public.phase_c_task (...) values (... ,'K6-A3-KEY') returning task_id into v_task;

  -- [A2] delete that trace -> must fail at COMMIT
  begin
    delete from public.phase_c_trace where trace_id = v_tr;
    set constraints all immediate;
  exception when others then ... end;

  -- [B1] a step run inserted 'active' gets a trace
  -- [B3] clearing trace_id on the way to 'completed' is refused
  -- [B4] repointing trace_id seals and supersedes the trace left behind
  -- [B2] a step run whose trace is deleted fails at COMMIT
  -- [C1] a founder_command INSERTed at a late state with a null trace is refused
  -- [C2] received, then received -> interpreting with a null trace, still allowed
  -- [C3] interpreting -> routed with a null trace is refused
  -- [D1] fn_phase_c_trace_write(status=sealed) stamps sealed_at
  -- [D2] a status-only seal is refused by phase_c_trace_sealed_ck
  -- [ING] fn_phase_c_event_ingress still completes end to end
  set constraints all immediate;   -- every deferred check, every touched row

  s := s || E'\n\n===== INVARIANT AT THE END OF THE REHEARSAL (includes probe rows) =====';
  for r in select * from public.fn_kernel_trace_integrity() order by ok, check_name loop ... end loop;

  raise exception '%', s using errcode='23514';
end $probe$;
```

## 4. Verbatim output

```
ERROR:  23514:
===== INVARIANT IMMEDIATELY AFTER THE MIGRATION (no probe writes yet) =====
 FAIL orphan_traces_task                                 expected=0             actual=7 of 75
 FAIL system_execution_components_with_no_trace          expected=0             actual=609 of 656
 FAIL terminal_objects_with_open_trace_handoff_run       expected=0             actual=1 of 1
 FAIL trace_state_disagrees_with_subject_handoff_run     expected=0             actual=1 of 1
 FAIL trace_state_disagrees_with_subject_workflow_run    expected=0             actual=4 of 8
 FAIL traces_written_under_trace_system_execution        expected=more than 0   actual=0 of 75
  ok  active_objects_without_trace_founder_command       expected=0             actual=0 of 8
  ok  active_objects_without_trace_handoff_run           expected=0             actual=0 of 1
  ok  active_objects_without_trace_step_run              expected=0             actual=0 of 8
  ok  active_objects_without_trace_task                  expected=0             actual=0 of 32
  ok  active_objects_without_trace_workflow_run          expected=0             actual=0 of 8
  ok  completed_traces_still_mutable                     expected=0             actual=0 of 75
  ok  orphan_traces_founder_command                      expected=0             actual=0 of 75
  ok  orphan_traces_handoff_unresolvable_subject_ref     expected=0             actual=0 of 75
  ok  orphan_traces_step_run                             expected=0             actual=0 of 75
  ok  orphan_traces_workflow_run                         expected=0             actual=0 of 75
  ok  raw_terminal_objects                               expected=informational actual=36 of 57
  ok  raw_total_traced_objects                           expected=informational actual=57 of 57
  ok  raw_total_traces                                   expected=informational actual=75 of 75
  ok  terminal_objects_with_open_trace_founder_command   expected=0             actual=0 of 8
  ok  terminal_objects_with_open_trace_step_run          expected=0             actual=0 of 8
  ok  terminal_objects_with_open_trace_task              expected=0             actual=0 of 32
  ok  terminal_objects_with_open_trace_workflow_run      expected=0             actual=0 of 8
  ok  trace_state_disagrees_with_subject_founder_command expected=0             actual=0 of 8
  ok  trace_state_disagrees_with_subject_step_run        expected=0             actual=0 of 8
  ok  trace_state_disagrees_with_subject_task            expected=0             actual=0 of 32
  ok  traces_carrying_a_k6_backfill_annotation           expected=informational actual=16 of 75
  ok  traces_sealed_at_set_but_status_open               expected=0             actual=0 of 75
  ok  traces_sealed_with_no_sealed_at                    expected=0             actual=0 of 75
  ok  traces_superseded                                  expected=informational actual=0 of 75
  ok  traces_with_unmapped_subject_kind                  expected=0             actual=0 of 75

===== PROOF PROBES =====
[A1] skipped ON CONFLICT task insert -> trace rows created = 0   (required: 0)
[A3] landed task 979 -> trace 1042 | trace.task_id=979 | trace.subject_ref=979 | parent=817
[A2] task whose trace was deleted, refused at COMMIT: 23503 phase_c_task 979: trace 1042 does not exist at commit
[B1] step run 95 inserted active -> trace 1043 | trace.step_run_id=95
[B3] step run driven to completed with trace_id cleared, refused: 23514 phase_c_workflow_step_run 95: state completed requires a trace and trace_id is null
[B4] trace repointed 1043 -> 1044 | old.sealed_at=2026-08-16 21:06:13.400246+00 | old.superseded_by=1044
[B2] step run whose trace was deleted, refused at COMMIT: 23503 phase_c_workflow_step_run 96: trace 1045 does not exist at commit
[C1] founder_command INSERTed at in_progress with null trace, refused: 23514 founder_command: cannot be created at state in_progress with no trace; only received is trace-less at birth
[C2] insert at received ok; received -> interpreting with null trace still allowed, state=interpreting
[C3] interpreting -> routed with null trace, refused: 23514
[D1] trace_write(status=sealed) -> sealed_at=2026-08-16 21:06:13.400246+00
[D2] status-only seal (sealed_at left NULL) refused: 23514 new row for relation "phase_c_trace" violates check constraint "phase_c_trace_sealed_ck"
[ING] full ingress ok=true run=154 step_run=97 task=980 run_trace=1047 task_trace=1049
[COMMIT] every deferred trace check forced IMMEDIATE for every row this rehearsal touched: PASSED

===== INVARIANT AT THE END OF THE REHEARSAL (includes probe rows) =====
 FAIL active_objects_without_trace_founder_command       expected=0             actual=1 of 9
 FAIL orphan_traces_task                                 expected=0             actual=7 of 83
 FAIL system_execution_components_with_no_trace          expected=0             actual=609 of 656
 FAIL terminal_objects_with_open_trace_handoff_run       expected=0             actual=1 of 1
 FAIL trace_state_disagrees_with_subject_handoff_run     expected=0             actual=1 of 1
 FAIL trace_state_disagrees_with_subject_workflow_run    expected=0             actual=4 of 9
 FAIL traces_written_under_trace_system_execution        expected=more than 0   actual=0 of 83
  ok  active_objects_without_trace_handoff_run           expected=0             actual=0 of 1
  ok  active_objects_without_trace_step_run              expected=0             actual=0 of 11
  ok  active_objects_without_trace_task                  expected=0             actual=0 of 34
  ok  active_objects_without_trace_workflow_run          expected=0             actual=0 of 9
  ok  completed_traces_still_mutable                     expected=0             actual=0 of 83
  ok  orphan_traces_founder_command                      expected=0             actual=0 of 83
  ok  orphan_traces_handoff_unresolvable_subject_ref     expected=0             actual=0 of 83
  ok  orphan_traces_step_run                             expected=0             actual=0 of 83
  ok  orphan_traces_workflow_run                         expected=0             actual=0 of 83
  ok  raw_terminal_objects                               expected=informational actual=37 of 64
  ok  raw_total_traced_objects                           expected=informational actual=63 of 64
  ok  raw_total_traces                                   expected=informational actual=83 of 83
  ok  terminal_objects_with_open_trace_founder_command   expected=0             actual=0 of 9
  ok  terminal_objects_with_open_trace_step_run          expected=0             actual=0 of 11
  ok  terminal_objects_with_open_trace_task              expected=0             actual=0 of 34
  ok  trace_state_disagrees_with_subject_founder_command expected=0             actual=0 of 9
  ok  trace_state_disagrees_with_subject_step_run        expected=0             actual=0 of 11
  ok  trace_state_disagrees_with_subject_task            expected=0             actual=0 of 34
  ok  traces_carrying_a_k6_backfill_annotation           expected=informational actual=16 of 83
  ok  traces_sealed_at_set_but_status_open               expected=0             actual=0 of 83
  ok  traces_sealed_with_no_sealed_at                    expected=0             actual=0 of 83
  ok  traces_superseded                                  expected=informational actual=1 of 83
  ok  traces_with_unmapped_subject_kind                  expected=0             actual=0 of 83
```

## 5. What each probe had to answer

| Probe | Required | Got |
|---|---|---|
| A1 skipped `ON CONFLICT DO NOTHING` task insert | 0 trace rows created | 0 (was 1) |
| A3 task insert that lands | trace exists, `trace.task_id` = the task, `subject_ref` = the task_id, parent set | task 979 → trace 1042, task_id 979, subject_ref 979, parent 817 |
| A2 task whose trace is deleted | refused at COMMIT | 23503 at `set constraints all immediate` |
| B1 step run inserted `active` | trace written and stamped | step run 95 → trace 1043, `trace.step_run_id`=95 |
| B3 step run driven to `completed` with a cleared trace | refused | 23514 |
| B4 step run trace repointed | old trace sealed AND `superseded_by` set | sealed 21:06:13, superseded_by 1044 |
| B2 step run whose trace is deleted | refused at COMMIT | 23503 |
| C1 founder_command INSERTed at a late state | refused | 23514 |
| C2 `received` insert, then `received -> interpreting` with a null trace | still allowed (the one exemption) | allowed, state=interpreting |
| C3 `interpreting -> routed` with a null trace | refused | 23514 |
| D1 `trace_write(status=sealed)` | `sealed_at` stamped in the same statement | stamped |
| D2 status-only seal | refused by `phase_c_trace_sealed_ck` | 23514 |
| ING full `fn_phase_c_event_ingress` | still completes with run, step run, task and both traces | ok=true, all six ids returned |
| COMMIT `set constraints all immediate` over everything | passes | passed |

`traces_superseded` moved from 0 to 1 during the rehearsal, on the B4 path. Before K6 nothing in
this database had ever set `superseded_by`.

The one FAIL that appears only in the second invariant read —
`active_objects_without_trace_founder_command 1 of 9` — is the C2 probe command, sitting at
`interpreting` with a null trace. That is the exemption working: a real router opens the trace on
the next statement, and this probe deliberately stops before it does. It is not present in the
post-migration read.

## 6. The checks that are still non-zero, and why

Six, none of them tuned:

| Check | Actual | Why it stays red |
|---|---|---|
| `orphan_traces_task` | 7 of 75 | The seven pre-K6 orphans, kept on purpose (deliverable E). They are annotated with what they are and why, and counted here **by kind** rather than filtered out. They cannot recur: A1 proves the mechanism that made them is gone. |
| `system_execution_components_with_no_trace` | 609 of 656 | TRACE-SYSTEM-EXECUTION declares `trace_required=YES` and 609 state-changing components are scoped to it. None writes a trace. K6 measures it; weakening the policy to make this green is the defect the policy exists to prevent. |
| `traces_written_under_trace_system_execution` | 0 of 75 | Same gap, stated from the trace side. |
| `terminal_objects_with_open_trace_handoff_run` | 1 of 1 | Handoff run 48 is `accepted` and points at trace 522, which was never sealed. |
| `trace_state_disagrees_with_subject_handoff_run` | 1 of 1 | The same row: trace 522 still says `state_after='open'`. The accept trace (523) exists and says `accepted`, but `handoff_run.trace_id` was never repointed to it. |
| `trace_state_disagrees_with_subject_workflow_run` | 4 of 8 | Runs 91, 92, 93 and 96 are `cancelled`; their bound traces (484, 486, 488, 530) still say `queued` and were sealed at that value by K4. `fn_kernel_cancel` writes a fresh cancellation trace, records its id in `closure_evidence`, and never moves `run.trace_id`. |

The last three are one K4 defect, not a K6 one, and there was **no invariant for them at all**
before this file — that is exactly the gap the brief listed as item 8. Repairing them means
deciding what `trace_id` means on a run and a handoff (root, or latest) and then moving pointers
that currently reference sealed evidence. That decision is not made by quietly editing sealed rows
inside a migration named "trace ledger".

## 7. Rollback rehearsal

`scripts/sql/rollback/kernel_k6_trace_ledger.rollback.sql` was run as its own aborted transaction
against production and parses and applies in order:

```
ERROR:  23514: ROLLBACK REHEARSAL OK: parses and applies in order; k6-annotated rows deliberately left = 0
```

(`0` because K6 has not been applied to production; after it is applied the same query returns 16.)

The ordering that matters: `phase_c_trace_sealed_ck` is dropped **before** `fn_phase_c_trace_write`
is restored. The pre-K6 writer never stamps `sealed_at`, so with the constraint still in place the
first caller asking for a sealed trace — `fn_kernel_cancel` and `fn_phase_c_step_advance` both do —
would fail.

## 8. A latent break this file also had to fix

`fn_phase_c_trace_advance`'s supersede branch wrote a new trace and then issued two follow-up
`UPDATE`s on it (`parent_trace_id`, then `sealed_at`). Once `fn_phase_c_trace_write` correctly
stamps `sealed_at` at insert time, that row is sealed the instant it exists and
`fn_phase_c_trace_append_only` refuses both updates — a guard firing on the correct behaviour.
Both are folded into the write. The single surviving `UPDATE` sets `superseded_by` alone on the old
row, which is the one change the append-only guard permits. B4 exercises this path.
