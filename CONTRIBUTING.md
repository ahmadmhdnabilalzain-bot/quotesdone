# Contributing to QuotesDone

Owner: it_engineer. Written 11 Nov 2026. The short version of how a change gets in. Each step links to the page
that holds the detail; this page does not restate them.

## 1. Before you start

- **Name the seat that owns the change.** Every change belongs to one of the active seats (`ceo`,
  `customer_support`, `sales_engineer`, `accountant`, `marketing`, `it_engineer`; read the live list with
  `select role_id from public.org_role where status = 'active'`). The seat goes in the commit message as
  `Assigned: <seat>` and in the subject as `<seat>: ...`. There are no departments.
- **Look for what already owns the subject** before writing something new: the database map
  (`docs/architecture/database/README.md`) for routines and tables, `supabase/functions/_shared/` for shared code.
  A second implementation of something that exists is the commonest way this repository gets messy.
- **Never test on a real person.** Fixtures are `ZZ DEMO ...` names and `@example.invalid` addresses; a probe must be
  incapable of reaching a real customer or supplier, not just careful to clean up.

## 2. Make the change

| kind of change | where | the rule |
|---|---|---|
| website or portal | `src/` | `npm run lint` (0 errors) and `npm run typecheck` (0 errors); a file carrying `@ts-nocheck` should lose it, not gain company (`docs/engineering/ts-nocheck.md`) |
| edge function | `supabase/functions/<name>/` | `deno check --no-lock supabase/functions/<name>/index.ts`; `verify_jwt` only in `supabase/config.toml` (`supabase/README.md`) |
| database | `scripts/sql/<sentence>.sql` + the last line of `scripts/sql/MANIFEST.txt` | one file per subject; revoke and pin `search_path` on a new `SECURITY DEFINER` routine; RLS and a policy on a new table (`README.md`, "Change the database") |
| a guard | `scripts/checks/<sentence>.test.mjs` | the check must fail on the original input; break it once to see. A check retires with its subject (renamed `*.RETIRED.mjs`), it is never softened |
| narrative | `docs/` | dated, measured, and never the only place a rule lives |

Every fix ships with the thing that fails when its cause comes back (a test, a check, or a verdict-row probe), and
the commit names it: `Prevented by: <file>`.

Comments say what was measured, what was wrong and why the code is the way it is, with the date. A comment that
restates the code protects nothing.

## 3. Prove it

```bash
npm run gate -- --offline        # without production credentials (production steps listed SKIPPED)
npm run gate                     # with SUPABASE_ACCESS_TOKEN: the full gate, as CI would have run it
```

GitHub Actions is off, so the local gate is CI. A step may be skipped only when it cannot run on the machine, and
the skip is said in the PR, never used to turn the table green. Verify behaviour by running it, not by reading it:
assert on a non-zero effect, not on an HTTP 200.

## 4. Merge and release

1. Push the branch and open a pull request from `.github/pull_request_template.md`; review the whole diff against
   `main`, because a branch can silently revert work that landed after it was cut.
2. Post the gate table on the PR (`npm run gate -- --pr <n>`).
3. After the merge the same session applies the SQL, deploys the changed functions and regenerates the schema mirror:
   `docs/runbooks/release-without-ci.md`.

## 5. Where to read more

| need | page |
|---|---|
| the product and the repository | `README.md` |
| how it works | `ARCHITECTURE.md` |
| standards, lint, typing, the debt register | `docs/engineering/README.md` |
| runbooks: incidents, restore, release, keys, local database, Docker | `docs/runbooks/README.md` |
| how a Claude Code session must work here | `.claude/CLAUDE.md` and `.claude/skills/` |
