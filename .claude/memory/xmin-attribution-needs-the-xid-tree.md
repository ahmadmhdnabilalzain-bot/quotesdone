---
name: xmin-attribution-needs-the-xid-tree
description: A subtransaction gets its own xid, so `xmin = pg_current_xact_id()` misses rows your own transaction wrote.
metadata:
  type: reference
---

Cleaning up "the rows this transaction wrote" with `where xmin::text::bigint =
pg_current_xact_id()` silently misses anything written inside a plpgsql `begin/exception` block —
`fn_event_dispatch` has one, the kernel adapters have one. Measured 24 Aug 2026: it left org_tasks
+2, phase_c_trace +5, phase_c_task +1, phase_d_dispatch +1, phase_c_workflow_run +1,
phase_c_workflow_step_run +1.

The correct test is the one J04's outbound helper already used, now
`public.fn_phase_d_row_is_ours(xid)`: a row VISIBLE to us whose xmin is still `in progress` can only
have been written by our own transaction tree, because no other transaction's uncommitted rows are
visible under READ COMMITTED.

```sql
v_top8 bigint := pg_current_xact_id()::text::bigint;
v_top32 bigint := mod(v_top8, 4294967296);
-- ours iff  x >= v_top32  and  pg_xact_status(((v_top8 - v_top32) + x)::text::xid8) = 'in progress'
```
