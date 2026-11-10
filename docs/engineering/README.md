# Engineering

Owner: it_engineer. Written 9 Nov 2026.

| Page | What it is |
|---|---|
| [linting.md](linting.md) | oxlint policy, the warn rules and their counts |
| [ts-nocheck.md](ts-nocheck.md) | the `src` files type checking does not see, with error counts per file |
| [duplicated-helpers.md](duplicated-helpers.md) | helpers copied across edge functions: what was merged into `_shared`, what was not and why |
| [largest-handlers.md](largest-handlers.md) | the two largest handlers and the proposed split of each |
| [tech-debt.md](tech-debt.md) | The technical-debt register: each item measured, dated, sized and owned |

Operational procedures are in [../runbooks/](../runbooks/README.md).

## Engineering standards

### Where things live
`ARCHITECTURE.md` at the repository root, section 1 ("Where each kind of thing lives"), is the answer. This
page does not restate it.

### Finding things
The database, by business area: `docs/architecture/database/README.md` (generated, drift-checked). The index of maps
is `docs/architecture/README.md`.

### How to run things
| Need | Command |
|---|---|
| Same toolchain on any machine | Docker: [../runbooks/docker.md](../runbooks/docker.md) (`docker compose up app`, `docker compose run --rm checks`) |
| The gate without production credentials | `npm run gate -- --offline` (production steps are listed SKIPPED, never PASS) |
| The full gate | `npm run gate` (needs `SUPABASE_ACCESS_TOKEN`) |
| Lint | `npm run lint` |
| Types | `npm run typecheck` |
| Repository checks | `npm test` |

### The rules for a change
1. Work on a branch and merge by pull request; use `.github/pull_request_template.md`.
2. The local gate must be green (`npm run gate`). GitHub Actions is off, so "green" means the local gate.
3. Name the seat that owns the change in the commit message.
4. A check that caught something goes in `scripts/checks` so it cannot recur; the comment carries the measurement.
5. New debt goes in [tech-debt.md](tech-debt.md) with a measurement, not a feeling.
