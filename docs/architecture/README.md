# Architecture maps

Owner: it_engineer. Started 10 Nov 2026 for the reader who has never seen this repository, most likely an external
auditor. `ARCHITECTURE.md` at the repository root says where each kind of thing lives and how the money and the
messages flow; the pages here are the maps you navigate with once you know that.

| page | what | how it stays true |
|---|---|---|
| [database/](database/README.md) | every routine, table, view, cron job and edge function production runs, filed by business area, with the canonical SQL file of each routine and the seat that owns each cron job | **generated** by `node scripts/architecture/database_map.mjs` from the schema mirror and the committed SQL, and refreshed by the mirror refresh itself; `scripts/checks/the_database_map_is_complete_and_current.test.mjs` fails when a name is in no area or a page is stale |

The engineering debt that still stands in a reader's way (type checking switched off, copied helpers, the largest
handlers) is measured in [../engineering/tech-debt.md](../engineering/tech-debt.md) and the pages it links.
