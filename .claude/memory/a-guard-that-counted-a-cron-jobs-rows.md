---
name: a-guard-that-counted-a-cron-jobs-rows
description: A watermark delta over a shared table attributes a concurrent cron's rows to your own write; attribute by xmin and pg_xact_status.
metadata:
  type: reference
---

`fn_phase_d_object_write` refused Phase D drives with "writing inquiry to public.inquiries enqueued
2 outbound HTTP request(s): POST .../dropbox_backup, POST .../uptime_check". Neither came from the
write: `cron.job` 88 `dropbox_backup_scan` and 35 `uptime_check_15min` are both `*/15 * * * *`, they
commit while a Phase D transaction is open, and READ COMMITTED shows their rows to the next
statement. The guard counted `where q.id > v_net_max` — every row above a watermark, by whoever — so
a drive failed four times an hour, on the quarter hour.

**Why:** the guard was right and its POPULATION was wrong. Same family as
[[instruments-report-on-the-wrong-subject]].

**How to apply:** a visible row whose writer is still in progress can only be yours — another
in-flight transaction's rows are not visible at all, and a committed one reports `committed`. Filter
`xmin::text::bigint >= mod(pg_current_xact_id()::text::bigint, 4294967296)` first (this also fixes
the epoch), then
`pg_xact_status(((top8 - top32) + xmin::text::bigint)::text::xid8) = 'in progress'`. Verified: a row
inserted inside a plpgsql `begin ... exception ... end` carries a SUBtransaction xid and still
reports 'in progress'.
