---
name: new-sql-file-needs-a-manifest-line
description: every new scripts/sql/*.sql file must be appended to scripts/sql/MANIFEST.txt or CI fails
metadata: 
  node_type: memory
  type: project
  originSessionId: 98fd9354-41f6-44c4-aefd-9361a73cd530
  modified: 2026-08-31T20:00:57.731Z
---

A new `scripts/sql/*.sql` file is NOT complete until its path is a line in `scripts/sql/MANIFEST.txt`.
That file is the tier-4 sequence key for the canonical routine engine
(`scripts/checks/canonical_routine_manifest.mjs` / `canonical_routines.test.mjs`, the successor to the
retired `sql_files_match_live`). A scripts/sql file on disk that MANIFEST.txt does not list is a
**MANIFEST GAP** — a countable finding that exits 1, so `npm test` (the "classification, pricing and
refund checks" CI job) AND the "repo and database agree" parity job both go red.

Line position IS the sequence: the HIGHEST line wins and is canonical; earlier files defining the same
routine are reported SUPERSEDED (not a conflict). So **append at the end** — a CREATE OR REPLACE that
carries the current body then supersedes the routine's original definition file correctly. Two files
at the same sequence key would be CONFLICTING, but one-path-per-line makes that impossible.

Cost me a red CI run on 31 Aug 2026: 5 new `launch_step1_*.sql` files, none in MANIFEST.txt → 5 gaps →
the run.mjs suite exited 1. Fix was one commit appending the 5 paths. Verify locally with the token:
`node scripts/checks/canonical_routine_manifest.mjs --all` → 0 findings (it also proves
repository→production and production→repository drift are both 0). See [[two-files-one-routine-one-commit]].
