---
name: the-database-map-is-generated-and-must-be-regenerated
description: "10 Nov 2026: docs/architecture/database/ maps every routine, table, view, cron job and edge function to one of ten business areas, with each routine's canonical file and each cron job's seat. It is generated (scripts/architecture/database_map.mjs) and npm test fails when it is stale or a name is unmapped. A new routine or SQL file means: run the generator and commit the pages. The canonical-file rule now lives in scripts/lib/canonical_routines.mjs."
metadata:
  type: project
  modified: 2026-11-10
---

**The rule.** After adding or redefining a routine, table or cron job, or adding an edge function:

    node scripts/architecture/database_map.mjs          # rewrites docs/architecture/database/
    node scripts/architecture/database_map.mjs --check  # what the_database_map_is_complete_and_current.test.mjs asserts

- A name that no rule places is UNMAPPED and fails the check. Name it well (the rules match words like `refund`,
  `supplier`, `kb_`), or add one line to `OVERRIDES` in `scripts/architecture/database_areas.mjs`. There is no
  catch-all area on purpose.
- The mirror refresh (`export_from_either_source_is_identical.mjs --write`) also rewrites the map, so the release
  train carries both in one commit.
- Cron owners come from the `writer_seat` / `seat_duty` rows the committed SQL inserts (replayed as text, offline).
  All 97 jobs resolved to a seat on 10 Nov.

**The canonical-file rule has one home.** `scripts/lib/canonical_routines.mjs` is the repository half of
`scripts/checks/canonical_routine_manifest.mjs`, moved verbatim (the check's `--all --emit` output and CSV were
byte-identical before and after). A test that copies the check into a fixture repository must copy the library too
(`canonical_routine_manifest_applies_at_merge.test.mjs` does).

**A check can read a parameter list.** Typing an untyped `src` file can fail a check whose regex spelled the old
signature (`a_supplier_upload_survives_one_gateway_failure` matched `(kind, file, token)`). Run the checks that read
the file (grep its name and `readCustomerPortal`/`readSupplierPortal`) before committing a type-only change.
