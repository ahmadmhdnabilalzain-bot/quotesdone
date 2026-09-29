# Backups: recovery objectives, drills and the full restore

Owner: it_engineer. The numbers below are stored in `public.it_threshold`, and the duties read them from there. This page explains them. If the two ever disagree, the database is correct and this page is stale.

| Key | Value | Meaning |
|---|---|---|
| `backup_rpo_hours` | 26 | At most 26 h of data may be lost. The table export runs daily at about 23:00 UTC and takes about 12 minutes, so the budget is 24 h plus 2 h of slack. |
| `backup_rto_hours` | 4 | Service must be back within 4 h. |
| `restore_drill_every_days` | 7 | The table restore drill runs weekly. |

## What is measured, and how

- **Achieved RPO** (`it_engineer.backup_objectives`, daily) is the larger of two figures: the hours since the newest finished `table_export_run`, and the widest gap between finished exports over the last 7 days. If it goes over the target, the duty raises `duty:backup_objectives:rpo`.
- **Achieved RTO** comes from the last drill that both passed and restored at least one row. It is the time from that drill's `restore_table_pick` to its recorded result, meaning a real download of one page and its restore into scratch. If no such drill exists inside 9 days, the duty raises `rto_unproven`. If the drill took longer than the target, it raises `rto`. **Limit:** this figure is a sample-page restore time and does not measure a whole-database restore. The whole-database figure comes from the quarterly drill below.
- **Drill cadence:** `it_duty_schedule.restore_table` runs every 7 days (it was 30). If no drill has been recorded in 9 days, the duty raises `drill_stale`.
- **Credential rotation** is duty 15. `fn_it_credential_rotate` already writes one `it_credential_rotation` row per rotation. `it_engineer.credential_rotation_age` (daily) raises two kinds of finding: a credential that is past `credential_rotate_days` + 7 days of grace and has no rotation open, and a `rotated_at` that has no rotation row.

## Quarterly full-database restore

**Never run this against production.** Every step runs on a Supabase branch.

1. Create a branch. Then, on the branch, restore the nightly dump into a scratch schema, for example `restore_q4`. To do that, run `pg_restore` with the schema renamed, or restore into a second database and move the schema across.
2. On the branch, run `select public.fn_it_full_restore_compare('restore_q4');`. It compares every public table with its restored copy by row count and by an order-independent checksum (the md5 of the sorted row md5s). It then records one `it_restore_drill_result` row with the subject `full_database into restore_q4`.
3. `it_engineer.dr_review` runs every 90 days. It raises `duty:dr_review:full_restore` when no full restore has compared equal within the last 92 days.

## Monthly reviews

- `it_engineer.capacity_review` compares the database size with `db_disk_limit_bytes` and storage bytes with `cap_supabase_storage_bytes`, each at `cap_warn_ratio`.
- `it_engineer.code_health` looks for three problems: SECURITY DEFINER routines without a pinned `search_path`, RLS tables that have no policy, and seat duties that have failed 3 or more times in a row.

## The 14 Sep 2026 supplier_dues drill (#3, failed)

That drill failed on three counts. The newest export was 7 days old, against a limit of 2. No full copy existed. The page held 0 rows. All three have since been fixed upstream: exports now finish daily, and an empty page now fails honestly. The drill that followed (#70, 15 Sep) passed with 0 rows restored, before the 23 Sep fix went in. As of 28 Sep, no drill has restored a row and passed, so the new duty raises `rto_unproven` until the first weekly drill completes.

Prevented by: `scripts/checks/the_backups_are_held_to_a_stated_rpo_and_rto.test.mjs`.
