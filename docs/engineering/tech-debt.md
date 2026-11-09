# Technical-debt register

Owner: it_engineer. Seeded 9 Nov 2026 from the launch-readiness audits. Every size is a measurement with its
date and method; re-measure before acting on it, and update the row when it moves. Risk: H = can hurt customers
or money, M = slows or endangers changes, L = hygiene.

| id | area | debt | measured size, date, how | risk | next step | owner seat |
|---|---|---|---|---|---|---|
| TD-01 | web types | `@ts-nocheck` files in `src/components/me` and SupplierPortal | 12 files, 9 Nov 2026, grep for `@ts-nocheck` (guarded by `src/components/nocheck_files_have_no_redeclarations.test.mjs`) | M | type one file at a time, smallest first; delete the pragma in the same PR | it_engineer |
| TD-02 | web lint | oxlint warnings (policy and counts in [linting.md](linting.md)) | 255 warnings by rule, 9 Nov 2026, `npm run lint` | L | burn down by rule; each fix needs a browser to prove | it_engineer |
| TD-03 | resilience | outbound `fetch` without a timeout | 66 call sites, 9 Nov 2026, `scripts/checks/every_outbound_fetch_has_a_timeout.mjs` against `scripts/checks/outbound_fetch_timeout_baseline.json` | H | add `AbortSignal.timeout` per site and shrink the baseline; the baseline may only go down | it_engineer |
| TD-04 | edge functions | duplicated helpers: JSON response helper | 65 copies, per `audit_backend.md`, 9 Nov 2026, grep across `supabase/functions` | M | move to `_shared`, replace copies in batches with a check that the count only falls | it_engineer |
| TD-05 | edge functions | duplicated CORS literal | 45 copies, same audit and method | M | same, one shared constant | it_engineer |
| TD-06 | edge functions | duplicated service-role client construction | 77 copies, same audit and method | M | one shared factory | it_engineer |
| TD-07 | edge functions | duplicated secret reader | 49 copies, same audit and method | M | one shared reader | it_engineer |
| TD-08 | tests | functions with no test of their own | 36 of 78 functions, `audit_backend.md`, 9 Nov 2026 | M | list them, order by money/PII exposure, add one behavioural test each | it_engineer |
| TD-09 | tests, money | `accountant` function has 0 tests and sends refunds | 0 tests, 9 Nov 2026, `audit_backend.md` | H | tests first for the refund path (idempotency, amount, who may trigger); any change to refund behaviour is the founder's call | it_engineer |
| TD-10 | database | database not rebuildable from the repository | migrations replay to 414 tables vs 784 live, 9 Nov 2026, replay vs live schema | H | make `supabase start` build the live schema (fold the out-of-band baseline into the repo), record the count match | it_engineer |
| TD-11 | database | foreign keys without a covering index | 162 of 387 FKs, 9 Nov 2026, regex scan of `supabase/schema/full_schema/01_*.sql` (multi-expression indexes may be misread); busy tables are covered | L | index `po_orders(inquiry_id, project_id, quote_id)`, `messages(document_id, project_id)`, `leads.merged_into` | it_engineer |
| TD-12 | resilience | no circuit breaker for email, Stripe or WhatsApp providers | none found in code, 9 Nov 2026, audit | H | a per-provider breaker in `_shared` that opens on consecutive failures and reports to the IT tick | it_engineer |
| TD-13 | operations | no external uptime monitor | none configured, 9 Nov 2026; only the internal `resilience_ping` (Vercel cron + daily cross-check) | H | point an external monitor at `/api/health` on quotesdone.com and quotesdone.ae; the founder holds the account | it_engineer |
| TD-14 | tooling | `deno --node-modules-dir=auto` rewrites the shared `node_modules` and breaks `next build` | measured 9 Nov 2026: next resolved a second React and `useContext` was null | M | fix = clean `npm ci`; stop running deno with that flag in the repo root, or point it at its own directory | it_engineer |
| TD-15 | docs | `scripts/sql/MANIFEST.txt` header says "852 files" | stale count, line 23, last measured 21 Aug 2026 | L | re-measure (`wc -l` of non-comment lines vs files on disk) and replace the number with the check's name | it_engineer |
