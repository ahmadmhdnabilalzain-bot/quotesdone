# The database, by business area

**Generated** by `node scripts/architecture/database_map.mjs` from the schema mirror (`supabase/schema/full_schema/`),
the canonical-file rule (`scripts/lib/canonical_routines.mjs`, the same code the gate runs) and the committed SQL.
Do not edit these pages by hand: change `scripts/architecture/database_areas.mjs` or the SQL, then run the script.
`scripts/checks/the_database_map_is_complete_and_current.test.mjs` fails when a name is in no area or a page is stale.

Everything lives in one Postgres schema, `public`. An area is where a reader looks, not a runtime boundary: a
routine in one area may read tables in another. Areas are assigned by the words of a name (rules and the short
override list in the areas file), so a routine is found by its subject even though the schema has no folders.

| area | routines | tables | views | cron jobs | edge functions |
|---|---:|---:|---:|---:|---:|
| [Quotes, reveal and payments](quotes-reveal-payments.md) | 75 | 35 | 1 | 0 | 11 |
| [Matching](matching.md) | 40 | 14 | 1 | 1 | 1 |
| [Messaging, outbox and WhatsApp](messaging.md) | 127 | 48 | 1 | 2 | 20 |
| [Suppliers and registration](suppliers-registration.md) | 257 | 77 | 10 | 18 | 9 |
| [Customers and inquiries](customers-inquiries.md) | 192 | 87 | 11 | 17 | 17 |
| [Accounting](accounting.md) | 175 | 51 | 19 | 10 | 1 |
| [Marketing](marketing.md) | 173 | 75 | 4 | 9 | 7 |
| [Knowledge](knowledge.md) | 127 | 69 | 8 | 2 | 3 |
| [IT, operations and monitoring](it-ops-monitoring.md) | 370 | 116 | 16 | 21 | 6 |
| [Seats, agents and duties](seats-agents-duties.md) | 580 | 232 | 17 | 21 | 3 |
| **total** | **2116** | **804** | **88** | **101** | **78** |

## How to read a routine row

- **canonical file**: the one SQL file whose definition is the real one, by the rule in
  `scripts/lib/canonical_routines.mjs` (the highest of: `supabase/migrations_history`, `supabase/migrations`,
  `ai-organization/db-functions`, then `scripts/sql/` in `scripts/sql/MANIFEST.txt` order). To change a routine,
  edit that file, not an earlier one: an earlier definition is superseded and applying it would revert production.
- **overloads**: how many argument lists production carries under that name.

## How to read a cron row

- **owner seat** comes from the `writer_seat` row (kind `cron_job`) or, for a `seat_duty:<duty>` job, the duty's
  `seat_duty.owner_seat`, as the committed SQL inserts them. "not recorded in the repository" means no committed file
  inserts one; `scripts/checks/every_run_label_and_cron_job_names_its_seat.test.mjs` is the production check of the same
  rule. **name / category** are the job's `cron_registry` row.
- A cron job is filed with the routine it runs.

Counts measured from the mirror at generation. 420 further routine names have a canonical file but are not in
the mirror (dropped from production on purpose, recorded in `scripts/sql/DROPPED.txt`, or applied after the mirror was
taken); they are not listed here.

Matching itself is mostly not SQL: the supplier choice runs in `supabase/functions/customer_api/lib/matching.ts`, which
is why the Matching area holds few routines.
