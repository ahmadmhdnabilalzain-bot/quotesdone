# Supabase schema mirror

`full_schema/` is the definition export of the live database (project `htdblwldjkcgjvmqkbeh`),
produced by `public.fn_schema_export()` and committed after every apply by the release train. It is
the "the repository records what production runs" mirror for the database layer. Edge-function
source lives separately under `supabase/functions/`.

## Eleven parts, read as one

Until 29 Sep 2026 this was one file, `full_schema.sql`. It grew from 2.67 MB (10 Sep) to 5.26 MB
(29 Sep) and crossed the 5 MiB ceiling that
`scripts/checks/the_repository_root_holds_only_the_product.test.mjs` applies to every tracked file.
It is now split by object kind, with the routines split again by name:

| part | holds |
|---|---|
| `01_extensions_sequences_tables_constraints_indexes.sql` | the capture banner, then extensions, sequences, tables, constraints, indexes |
| `02_views.sql` | views |
| `03_functions_before_fn_c.sql` … `10_functions_fn_t_onwards.sql` | routines, in name order, cut at `fn_c`, `fn_d`, `fn_i`, `fn_m`, `fn_p`, `fn_s`, `fn_t` |
| `11_triggers_rls_policies_cron_secret_names.sql` | triggers, RLS enables, policies, cron jobs, secret key NAMES |

Every cut is at the start of a line, so the parts joined in order are the export byte for byte.
Read the mirror with `readSchemaMirror()` from `scripts/lib/schema_mirror.mjs`, never a single part;
that module also holds the part list and the cut rule, and explains when to add a boundary.

- Regenerate: `node scripts/checks/export_from_either_source_is_identical.mjs --write`
- Verify: the same command with no flag fails if the database and the mirror disagree.

## What it deliberately excludes

- **Secret values.** Only `app_secrets` key *names* are mirrored, as comments.
- **Row data.** No table contents.

## Fidelity

A reference mirror, not a restore procedure: table DDL is reconstructed from catalogs. To rebuild,
use Supabase managed backups / PITR.
