---
name: select-into-no-rows-nulls-every-target
description: A plpgsql SELECT INTO that matches no rows sets every target to NULL rather than leaving the initialiser — so a counter initialised to 1 becomes null and the next insert fails NOT NULL.
metadata: 
  node_type: memory
  type: reference
  originSessionId: ace6f8ec-4a15-4994-b9f6-37f766585534
  modified: 2026-08-15T11:09:34.560Z
---

```sql
v_attempt bigint := 1;
...
select step_run_id, attempt_no into v_prev, v_attempt from ... limit 1;
if v_prev is not null then v_attempt := v_attempt + 1; end if;
```

Reads as "keep 1 when there is no previous row". It is not. **`SELECT INTO` matching no rows nulls
EVERY target**, initialiser included. `v_attempt` became null on the first attempt at any workflow
step and the insert died on `attempt_no NOT NULL` — so the first advance of any step was impossible
while looking, in the source, like the obviously-safe case.

Fix: derive after the lookup instead of mutating a value the lookup may have wiped.

```sql
select step_run_id, attempt_no into v_prev, v_prev_attempt from ... limit 1;
v_attempt := coalesce(v_prev_attempt, 0) + 1;
```

Same family as [[least-ignores-nulls-in-postgres]] and
[[error-and-empty-must-not-return-the-same-value]]: after `SELECT INTO`, *no rows* and *a null
value* are indistinguishable unless you check `FOUND` or coalesce afterwards.

Two more from the same session, cheaper but each costs an hour:

- **`RAISE` does not understand `%L` or `%I`.** Only `%` substitutes. `raise exception 'owner %L
  ...', v` prints the value followed by a literal `L`, so the error message garbles the identifier
  it is complaining about.
- **A declared plpgsql variable shadows a table alias of the same name.** `declare p record` plus
  `from phase_b_sla_policy p` resolves `p.target` to the record and fails with `record "p" has no
  field "target"` — at run time, on every call.
