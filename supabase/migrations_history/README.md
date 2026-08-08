# Migration history (archived, not replayed)

These 736 files are the project's real migration history. They are kept for the record and are
**not** applied by anything. The replay path is `supabase/migrations/`, which holds two generated
files describing the schema as it actually is.

## Why they were moved here

The Supabase Preview check builds an empty database and replays `supabase/migrations/` in filename
order. It had never once passed. Eight rounds of diagnosis, each a real defect, each fixed:

| # | What was wrong | Fix |
|---|---|---|
| 1 | 34 files named `20260724_*` collapsed to one version and replayed alphabetically, so `analytics` ALTERed `org_action_executor` before `supplier_success` CREATEd it | renamed 21 files to their true recorded versions |
| 2 | 41 public tables — `leads`, `inquiries`, `documents` — were ALTERed and INSERTed into by migrations and created by none | generated a baseline from production's catalog |
| 3 | `00000000000000` and `29999999999999` are not valid `YYYYMMDDHHMMSS` timestamps, so the CLI silently skipped both files | real dates, `20200101000000` and `20991231235959` |
| 4 | 445 recorded migrations had no file at all — the repo held only the last third of its own history | recovered them verbatim from `schema_migrations.statements` |
| 5 | the preview target had accumulated partial state across every failed run and had never started empty | reset it, and reset before each subsequent run |
| 6 | `pg_cron` and `pg_net` were never installed; only extensions backing a column TYPE were emitted | emit every extension `pg_extension` reports |
| 7 | a view referenced `inquiries.pipeline_stage`, a column no migration adds | baseline widened to every table and every column |
| 8 | `public.quotes` has generated columns calling `margin_rate()`, a user function | emit those functions first, under `check_function_bodies = off` |

Round nine was not a schema defect at all. The CLI's own statement recorder could not store
`20260706101940_decision_policy_escalation.sql`: a plpgsql body containing `reasons text[] := '{}'`
breaks the array literal it builds for `schema_migrations.statements`.

That is where replaying the history stopped being worth it. The database was built substantially by
hand alongside its migrations — tables, columns and objects created directly — so the history is
not a faithful recipe for the schema and never was. Replaying it can only ever approach the truth
that `supabase/migrations/` now states outright.

## What is safe about this

Nothing in CI or in `scripts/` runs `supabase db push`. Deployment goes through
`scripts/apply_sql.mjs` and the Management API, which read and write objects directly. Moving these
files changes no deployment path.

Production and staging still record all 715 of these versions in `schema_migrations`. Nothing was
deleted from either database, and the generated baseline was proven a no-op against staging before
every commit: 5362 columns and 848 constraints, unchanged each time.

## If you need one of these

They are ordinary SQL. Read them, or apply one with:

```bash
node scripts/apply_sql.mjs supabase/migrations_history/<file>.sql
```

## Regenerating the replay path

```bash
node scripts/gen_baseline_migration.mjs --all
node scripts/check_migration_order.mjs
```

The baseline is generated from production's live catalog, never hand-edited. If the schema changes,
re-run the generator rather than patching the file.
