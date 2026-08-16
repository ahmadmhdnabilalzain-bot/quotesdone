# Phase C correction 1 — the founder-command trace lifecycle

**Migration:** `scripts/sql/phase_c_30_command_trace_lifecycle.sql`

## What the audit measured

Command 222 reached `tasks_created` while its own root trace still said `interpreting`, status
`open`. All four child tasks carried `trace_id NULL`, and the founder-facing thread rendered that
null straight through. Across the whole table, **12 of 12 tasks had no trace**. The only trace
invariant that could have seen it looked at `closed_at is not null`, and no task had ever closed.

## What was built

| Requirement | Implementation |
|---|---|
| Command trace created at ingestion | unchanged — `fn_founder_command_submit` already wrote it |
| Trace status advances with command status | `a00_founder_command_trace_guard`, a BEFORE UPDATE trigger on `founder_command`, calls `fn_phase_c_trace_advance` on every state change and then **asserts** the two agree |
| Every child task receives a non-null trace_id | `a00_phase_c_task_trace_guard`, BEFORE INSERT on `phase_c_task`, writes a `TRACE-TASK` row and sets `new.trace_id` |
| Task trace references the root command trace | new column `phase_c_trace.parent_trace_id`; the trigger resolves the root from `founder_command.trace_id`, or from `phase_c_workflow_run.trace_id` for an autonomous task |
| Review traces reference the task trace | same column; `fn_phase_c_trace_advance` carries `parent_trace_id` forward when it supersedes |
| Completion/failure/cancellation closes the trace | the task trigger seals on `completed`, `failed`, `cancelled`, `superseded`; the command trigger seals on the command's terminal states |
| A command cannot reach `tasks_created` while its root trace remains `interpreting` | the command trigger raises `23514` if the trace and the state disagree after the advance |
| A task cannot become active or completed with a null trace | the task trigger raises `23514` on any state in the active or terminal set with `trace_id is null` |

**One move is named and allowed**: `received → interpreting`, because that is the transition the
router makes *in order to* open the trace, on the very next statement of the same transaction. A
guard that demanded a trace there would have made writing the first trace impossible — the same
defect wearing the opposite sign. Every state after it is enforced.

The task trace is written BEFORE INSERT, so it cannot know the id it is about to create. A second
trigger, `z90_phase_c_task_trace_subject`, stamps `task_id` and `subject_ref` onto it immediately
after the row exists — evidence that does not name its subject is the same defect in miniature.

## Repairing the existing evidence, without deleting history

`scripts/sql/phase_c_38_repair_historical_evidence.sql`. Nothing is deleted.

- **8 tasks** created before the trigger existed received a trace each, parented to their command's
  root, and labelled `retrofitted: true` with the reason — reconstructed from the task row, which is
  the only record of them that exists. They are not presented as evidence of work that was traced at
  the time.
- **5 command root traces** were advanced to the state their command had actually reached.
- A sealed trace is never rewritten: `fn_phase_c_trace_advance` supersedes it with a new row and
  links them. The append-only guard refused an edit during this work and was right to.

## Measured after

```
founder_command : required 7  complete 7  incomplete 0  missing 0
phase_c_task    : required 27 complete 27 incomplete 0  missing 0
```

`commands_ahead_of_their_trace = 0`. `tasks_without_trace = 0 of 27`.
Canary A: root trace 509 at `tasks_created`; child traces 510–513, each `parent_trace_id = 509`.
