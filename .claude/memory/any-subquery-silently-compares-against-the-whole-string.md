---
name: any-subquery-silently-compares-against-the-whole-string
description: "`x = any((select col ...))` is the SUBQUERY form of ANY — it compares against whole rows, not array members, and never errors."
metadata: 
  node_type: memory
  type: reference
  originSessionId: f4baf9ca-e2a9-4d49-aa5b-18d5d5fefa11
  modified: 2026-08-20T22:32:59.424Z
---

`public.phase_b_workflow.allowed_terminal_states` is **TEXT**, holding `'completed; cancelled;
superseded'` — not an array. I wrote:

```sql
v_run_state = any((select allowed_terminal_states from public.phase_b_workflow where workflow_id = v_wf))
```

expecting array membership. Postgres parsed it as `expr = ANY (subquery)` and compared the run state
against the WHOLE semicolon-separated string as one value. **False for every run ever driven**, with
no error and no warning. `state_is_terminal` read false on all 30 rows and the Phase D deliverable
reported 0 of 30 reaching a terminal state while every run was in fact `completed`.

**Why:** `= any(array)` and `= any(subquery)` are different constructs with identical syntax at the
call site. The array form errors loudly on a text column (`op ANY/ALL (array) requires array on
right side`); wrap the same expression in a subquery and it silently becomes the other form.

**How to apply:** before writing `= any(...)`, check the column's `data_type` in
`information_schema.columns`. For a delimited text column use
`unnest(string_to_array(col, ';'))` with `btrim` on each element. And note the general shape — this
is [[instrument-measuring-wrong-subject-is-the-lens]] inside a single SQL operator: the predicate ran,
returned a boolean, and answered a different question. It was caught by the deliverable's own
reproduction test, not by reading the code.
