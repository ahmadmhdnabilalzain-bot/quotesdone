---
name: an-fk-to-an-emptied-table-fails-every-writer
description: "A foreign key whose parent table was emptied stops catching bad writers and starts failing all of them — silently, if the caller swallows the error"
metadata: 
  node_type: memory
  type: reference
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-08T22:31:25.354Z
---

Found 9 Sep 2026 in QuotesDone. `org_tasks.dept_key` had
`FOREIGN KEY (dept_key) REFERENCES org_departments(dept_key)`. On 7 Sep the founder
removed every department and `org_departments` went to 0 rows.

A parent with no rows means the constraint can only ever be satisfied by NULL. It did
not become inert — it inverted. It stopped catching one bad writer and began failing
**every** writer. Eight live routines inserted `org_tasks` with a `dept_key`; all eight
raised.

**What made it invisible for two days:** the caller swallowed it. `fn_founder_mail_route`
caught the exception, wrote a row to `founder_alerts`, and DROPPED the notification.
Real customer messages ("A new quotation for inquiry RFQ-1042", and its Arabic twin)
were discarded in silence. Nothing was 500ing; a table was just quietly not filling.

**The lens.** After deleting the rows of any parent table, go looking for the FKs that
still point at it. Emptying a parent is not the same as dropping it — dropping cascades
loudly, emptying fails quietly at the next write. Query `pg_constraint` for
`confrelid = <parent>::regclass` before you consider the removal finished.

**Two matching traps, both hit here:**
- The alert named ONE routine. A `prosrc` scan — not a repo grep, which misses what is
  deployed — found eight. Patching only the path the alert named would have left seven
  broken. See [[a-mention-is-not-a-reference]].
- Dropping the **column** was NOT the fix: 33 live routine bodies still read or write
  `dept_key`, and an index hung off its attnum. The FK was the dead thing; the column is
  now a label with no referent, which is recorded rather than hidden.

Related: [[guarded-by-a-condition-that-cannot-occur]] is the mirror image — a guard that
can never fire. This is a guard that can never NOT fire. See also
[[a-condition-that-cannot-not-fire]] and [[the-org-is-two-agents-and-no-departments]].
