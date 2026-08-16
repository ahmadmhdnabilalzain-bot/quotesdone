# Phase C correction 10 — repository / live schema source of truth

## What the audit measured

`scripts/checks/export_from_either_source_is_identical.mjs` exited **1**:

```
live export                    : 58103 lines, 3100165 chars
supabase/schema/full_schema.sql: 58083 lines, 3098895 chars
identical    : NO
differing    : 18158 lines, first at line 39722
```

Routine-level parity and edge-function parity both passed; only the committed whole-schema artefact
had fallen behind.

## The repository already had the better design — preserved, not duplicated

No new mechanism was created. What already exists:

| Layer | Source of truth | Check |
|---|---|---|
| **Deployable routines** | the numbered files in `scripts/sql/`, applied through `scripts/apply_sql.mjs`, which reads every definition back out of the database and compares it to the file | `scripts/checks/sql_files_match_live.test.mjs` — newest file per routine, by **git commit time** |
| **Edge functions** | `supabase/functions/<slug>/index.ts` | `scripts/verify_deploy_parity.mjs --all` |
| **Whole schema** | **generated**, by `public.fn_schema_export()` on production, written to `supabase/schema/full_schema.sql` by `export_from_either_source_is_identical.mjs --write` | the same script with no flag |
| **CI** | `.github/workflows/project-parity.yml:48` already runs `export_from_either_source_is_identical.mjs` | — |

**The policy, stated:** migrations under `scripts/sql/` are the deployable source of truth.
`supabase/schema/full_schema.sql` is a **generated schema-only snapshot of current production**. It
is not directly deployable and must never be hand-edited — `scripts/checks/schema_dump_not_replayable.test.mjs`
exists for exactly that reason.

## What was done

The file was **not manually patched**. It was regenerated from the live definitions through the
existing `--write` path, after the final Phase C correction increment.

| Measure | Result |
|---|---|
| live export | 59,103 lines, 3,152,703 chars |
| `supabase/schema/full_schema.sql` | 59,103 lines, 3,152,703 chars |
| identical | **YES** |
| exit code | **0** |
| table data included | none — schema only |
| secret values included | none |
| project refs embedded | **0** |
| CI drift check | already present, `.github/workflows/project-parity.yml` |

`sql_files_match_live`: 439 routines defined across 655 files, **0 not present on production, 0
drifted**. `verify_deploy_parity --all`: 202 edge functions carry the repository's current code.
