# Restore and disaster recovery

Owner: it_engineer. Written 9 Nov 2026. The objectives, the measurement and the quarterly drill are defined in
[../it/BACKUP_RPO_RTO.md](../it/BACKUP_RPO_RTO.md) (RPO 26 h, RTO 4 h, stored in `public.it_threshold`; the
database wins over the page). This runbook says which copy to reach for and how to rehearse it. Undoing a bad
release (code, functions, routines) is [../it/ROLLBACK.md](../it/ROLLBACK.md), not a restore.

## Which copy do I use?

| Copy | What it is | Granularity | Use it when |
|---|---|---|---|
| **Supabase PITR** | continuous WAL archive of the one production project | to the second, inside the plan's retention | a bad write, a wrong `DELETE`, a bad migration, recently. Needs the PITR add-on: confirm it is on in the dashboard (Database, Backups) before launch; the repo cannot see it |
| **`backup` function** | daily (about 23:00 UTC, about 12 min) table export into the `backups` storage bucket; recorded in `table_export_run` | one table, one day | one table needs rows back, or PITR is not available / out of retention |
| **`dropbox_backup` function** | chunked copy outside Supabase every 6 hours (`dropbox_backup_second_scheduler`), with a health op | whole export, off-platform | the Supabase project itself is lost or inaccessible |

Rule of thumb: PITR for "undo the last few hours", the daily export for "get this table back", Dropbox for
"Supabase is gone". Nothing here is restored over production directly; restore beside it, compare, then copy
the needed rows across with a reviewed statement (a destructive production change, so the founder rule in
[incident-response.md](incident-response.md) applies).

## Restore drill on a Supabase branch

Never run a drill against production. The branch is a throwaway copy.

1. **Create a branch** of the production project (dashboard, or the Supabase MCP `create_branch`). Note the
   branch ref and the time.
2. **Pick the subject**: one table for the weekly drill; the whole database for the quarterly one.
3. **Table drill**: download the newest export page for that table from the `backups` bucket (or the Dropbox
   copy), restore it into a scratch table on the branch, and compare row count and checksum with the live
   table. The weekly duty `restore_table` does this and writes `it_restore_drill_*` rows.
4. **Full drill**: restore the nightly dump into a scratch schema on the branch (for example `restore_q4`),
   then `select public.fn_it_full_restore_compare('restore_q4');`. Steps and the 90-day duty are in
   [../it/BACKUP_RPO_RTO.md](../it/BACKUP_RPO_RTO.md).
5. **PITR drill** (once before launch): on the branch, restore to a timestamp 1 hour ago and confirm a row
   written since is absent.
6. **Delete the branch.**

### What to record

For every drill, in the `it_restore_drill_result` row and in `docs/it/postmortems/` (or `docs/reports/`) if it
failed: the date; the subject; the copy used; the **elapsed time** from step 1 to a passing comparison (this is
the real RTO sample); rows restored (a drill that restores 0 rows has proved nothing); the age of the newest
export used (the real RPO sample); who ran it; and any step that was unclear. A drill that fails is a SEV3
finding with an owner, not a footnote.

## Status on 9 Nov 2026

Per the launch audit: backups exist and are scheduled in code, but **a full restore has never been evidenced
in the repository** and PITR plan tier is unconfirmed. Both are launch-readiness items: run the PITR drill and
one full drill on a branch, and record them as above. The database is also not rebuildable from the repo alone
(see [../engineering/tech-debt.md](../engineering/tech-debt.md)), which is why the export and PITR are the only
recovery path today.
