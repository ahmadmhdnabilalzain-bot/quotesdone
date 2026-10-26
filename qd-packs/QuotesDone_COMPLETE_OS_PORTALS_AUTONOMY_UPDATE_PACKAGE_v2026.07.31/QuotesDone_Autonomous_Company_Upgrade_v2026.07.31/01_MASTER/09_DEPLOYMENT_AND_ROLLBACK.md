# Deployment and rollback

1. Create a dedicated branch and staging Supabase project/schema.
2. Snapshot schema, secrets metadata, cron definitions and relevant data before migrations.
3. Apply one phase at a time.
4. Backfill in bounded batches with checkpoint tables.
5. Keep old endpoints compatible until frontend cutover is complete.
6. Use feature flags for comparison v2, portal v2 and OS Observe Mode.
7. Run shadow comparisons: old AI result versus deterministic v2, without changing customer output.
8. Promote only after acceptance metrics pass.
9. Rollback by disabling feature flags, restoring old endpoint routing and applying down migrations where safe.
10. Never delete old data during the first release; archive after stable operation and legal retention review.
