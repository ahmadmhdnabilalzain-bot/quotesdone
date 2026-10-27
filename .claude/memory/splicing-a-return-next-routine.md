---
name: splicing-a-return-next-routine
description: "Inserting into a plpgsql board between a check's assignment and its own return next emits the new name twice and loses the old — and apply_sql prints success both times."
metadata: 
  node_type: memory
  type: project
  originSessionId: ba4ede58-946f-4477-8042-69cef19ee057
  modified: 2026-08-20T04:17:19.910Z
---

Splicing rows into a `returns table … return next` routine (the estate's board pattern), I anchored
on one `check_name := '…';` line plus the line after it. `handlers_not_writing_a_business_object`
emits over **two** lines:

```
check_name := 'handlers_not_writing_a_business_object';
expected := '0'; actual := (n_needwrite - n_wired)::text;
ok := (n_needwrite - n_wired = 0); return next;
```

The new block landed between the assignment and its own `return next`, so the reassigned
`check_name` was emitted twice and the original vanished. The board showed the new name twice and the
old one not at all.

**`apply_sql.mjs` printed `read back and identical to the file` both times, and was correct** — the
read-back compares the live body to the file, and the file was wrong. Same shape on a different
subject as [[the-read-back-covers-bodies-not-grants]].

**Why:** a routine's OUTPUT is not its body. Any verification that stops at "the deployed text equals
the intended text" cannot see a logic error in the intended text.

**How to apply:** anchor a splice on a **complete** emit — up to and including `return next;` — and
after applying, **list the rows**: `group by check_name having count(*) > 1` catches a duplicate, and
comparing the check_name set before and after catches a loss. Same rule as
[[a-rehearsal-proves-creation-not-execution]]: run the thing, read what it returns.
