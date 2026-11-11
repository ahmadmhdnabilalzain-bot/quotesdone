# supabase/ — the backend

Owner: it_engineer. Rewritten 11 Nov 2026. The earlier version of this page (21 Jul 2026) described a way of
pulling deployed functions back into git with `scripts/edge-functions.sh`. That was the right tool when production
was ahead of the repository. It is the wrong tool now that the repository is the source of truth, so the script is
in `scripts/archive/` and this page describes how the backend is changed today.

## What is here

| path | what it is |
|---|---|
| `functions/<name>/index.ts` | one Supabase edge function (Deno, TypeScript) per directory: **78**, counted 11 Nov 2026 with `ls supabase/functions/*/index.ts \| wc -l`. Large functions are split into `actions/`, `lib/` and `handle.ts` beside the `index.ts` |
| `functions/_shared/` | code shared between functions: auth gates, the paid-provider gate, the outbox, document readers, PDF rendering, the JSON helpers. Vendored third-party code is in `_shared/vendor/` |
| `functions/**/*.test.ts` | Deno tests beside the code they cover, run by `npm test` (`scripts/checks/run.mjs`) |
| `config.toml` | the one place `verify_jwt` is set per function. `scripts/deploy_functions.mjs` checks it against production before every deploy and refuses on a mismatch |
| `schema/full_schema/` | the schema mirror: the whole `public` schema as production has it, regenerated after every apply by `node scripts/checks/export_from_either_source_is_identical.mjs --write` |
| `migrations/`, `migrations_history/` | the first two of the four SQL apply tiers (see `ARCHITECTURE.md` section 1). New database changes go in `scripts/sql/`, not here |
| `migrations-superseded-consolidated/`, `rollback/`, `seeds/` | history and seed data; none of it can be canonical for a routine |

Which seat owns each function is a row in `public.function_owner`; `node scripts/checks/every_deployed_function_has_an_owner.mjs`
prints the table and fails when a deployed function has no owner or an owner row has no function.

## Change a function

```bash
deno check --no-lock supabase/functions/<name>/index.ts      # the green build for an edge function
node scripts/deploy_functions.mjs --ref=htdblwldjkcgjvmqkbeh --production <name>
node scripts/verify_deploy_parity.mjs <name>                 # or --all
```

`deploy_functions.mjs` refuses without an explicit `--ref`, refuses production without `--production`, never passes a
`verify_jwt` flag (it reads `config.toml`), and confirms the deploy by reading the function's version before and after
rather than trusting the CLI's exit code. `verify_deploy_parity.mjs` samples the deployed bundle's string literals; it is
a sampler, so a small change to a large function should also be verified by calling it.

GitHub Actions is off (founder ruling, ledger 1564), so a session runs these itself after the merge:
`docs/runbooks/release-without-ci.md`.

## The one trap

A function that authenticates itself (an internal credential, an admin JWT) must have `verify_jwt = false` in
`config.toml`. If the gateway enforces a JWT, it answers 401 to every internal caller before the function body runs,
and the function still looks healthy in the dashboard. This happened to `pdf_native` on 21 Jul 2026.
