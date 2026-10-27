---
name: down-scripts-live-in-a-subdirectory
description: A Phase D rollback belongs in scripts/sql/down/, never beside its migration, or the classifier reads it as a migration.
metadata:
  type: project
---

`scripts/phase_d/build_migration_rollback_classification.mjs` globs `scripts/sql/phase_d_*.sql` and
looks for each file's rollback at `scripts/sql/down/<stem>_down.sql`. A `_down.sql` written beside
its migration matches the glob, so it is classified AS a migration — and a rollback that drops a
function and recreates a view classifies as `IRREVERSIBLE_WITH_FOUNDER_APPROVAL`, which then fails
the check demanding it cite the founder decision it asserts.

Three checks went red this way on 25 Aug 2026. `scripts/sql/down/` already held 100 files and a
README. The fix was `git mv`, not a code change.

**Why:** the classifier's denominator is a glob, and a glob does not know intent.

**How to apply:** write the rollback to `scripts/sql/down/`. Down scripts are NOT listed in
`MANIFEST.txt` or `PENDING.txt` — the classifier finds them by name — and per that directory's own
README nothing runs them automatically. Related: [[a-row-added-without-its-artefact]],
[[stage-paths-never-git-add-all]].
