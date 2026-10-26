# Aikido local scan: quotesdone (it_engineer, 19 Oct 2026)

**Scope.** This scan covers origin/main at `febe250` in a detached worktree. Only the quotesdone repo was scanned. The tool was `aikido_scan_paths` (SAST and secrets), run in batches of 50 or fewer.

**Files scanned.** 2,874 first-party files:

| Area | Files |
|---|---|
| `supabase/functions/**/*.ts` | 395 |
| `src/**/*.{ts,tsx}` | 260 |
| `scripts/**/*.{mjs,ts}`, excluding `scripts/sql` | 463 |
| `scripts/sql/*.sql` | 1,742 |
| `.github/workflows/*.yml` | 13 |
| `next.config.mjs`, `vercel.json` | 2 |

**What was excluded.** `node_modules`, vendored code (`_shared/vendor/**`), `*.fixtures.ts` and `*.test.*`.

**How the SQL files were scanned.**
- 50 SQL files were scanned one by one.
- The other 1,692 were joined into 6 files for the scan (`-- @@FILE` markers). Aikido reported 0 findings. SAST has no SQL rules, so for these files the scan is a secrets check only.
- A separate grep for live-key patterns found nothing: sk_live, rk_live, whsec, AKIA, JWT, Resend `re_`, `sbp_`, `ghp_` and private keys.

**Limits.**
- **IaC (Checkov) did not run** for any batch: `checkov.exe ENOENT` (the plugin's bundled binary is missing). The workflow findings below come from Aikido's own YAML rules, not from Checkov.
- Listing issues from the Aikido feed needs the paid plan, so it was not used.

## Counts

- **Total findings: 711.**
- **Real high or critical: 0.** No fix PRs were opened, so nothing was sent to the release operator.
- **Real but low (hardening): 6 subjects**, all in CI workflows and the blog renderer (rows marked REAL-LOW below).
- **False positives or operator-only (not reachable by any user): the rest.**

## Table

The severity column is Aikido's 0-100 score.

| File | Rule | Sev | # | Verdict | Fix PR |
|---|---|---|---|---|---|
| .github/workflows/deploy-functions.yml:142 | template-injection | 80 | 1 | REAL-LOW: `${{ github.event.inputs.target/slugs }}` goes straight into `run:`. Only `workflow_dispatch` reaches it, which needs write access, and the repo is PRIVATE. `event.before` is a SHA. Hardening: pass the values through `env:`. | #1459 |
| .github/workflows/release-train.yml:66 | template-injection | 80 | 1 | REAL-LOW: `${{ inputs.pr }}` goes into `run:`. Dispatch only, same mitigation as above. | #1459 |
| .github/workflows/release-train.yml:35, it-weekly-readings.yml:19 | overly-broad-permissions | 68 | 2 | REAL-LOW: `contents: write` is set at workflow level. Both jobs do push, so scoping it to the job is hygiene only. | #1459 |
| .github/workflows (cad-read-worker, checks x3, deploy-functions, release-train) | action not pinned by SHA (denoland/setup-deno@v2, supabase/setup-cli@v3) | 70 | 7 | REAL-LOW: supply-chain hardening. Other actions are already SHA-pinned. | #1459 |
| .github/workflows (13 checkout steps) | checkout persist-credentials default | 30 | 13 | REAL-LOW: hygiene. Only release-train needs the token. | #1459 |
| .github/workflows/it-post-deploy-smoke.yml:27 | workflow_run trigger | 20 | 1 | FP: triggers on our own deploy workflow on main and checks out no fork code. | n/a |
| src/components/BlogPost.tsx:132 | dangerouslySetInnerHTML (body_html) | 80 | 1 | REAL-LOW: `blog_posts.body_html` from the DB is rendered unsanitised. Only seats with service-role write it (CEO-reviewed), and next.config has a CSP. Defence in depth: sanitise on publish. | #1461 |
| src/components/BlogIndex.tsx, BlogPost.tsx (title/excerpt) | dangerouslySetInnerHTML | 80 | 4 | FP: Arabic layout only (`bidiText`), on our own DB text | n/a |
| src/components/ChatWidget.tsx:173, me/PortalShell.tsx:203 | dangerouslySetInnerHTML / "express render" | 80 | 3 | FP: `render()` HTML-escapes every character first and links only http(s) URLs, so the output cannot break out of the attribute. The "express.render" label is a misidentification. | n/a |
| src/components/FaqInner, LegalDoc, MarketingDoc, ServiceDoc | dangerouslySetInnerHTML | 80 | 15 | FP: static repo content (`src/content/*.json`) | n/a |
| src/middleware.ts:25,35 | open redirect | 85 | 2 | FP: the target is the fixed `/ar` prefix or the fixed `AE_ORIGIN`, plus the same path | n/a |
| src/components/portal/SupplierPortal.tsx:162,212; DocumentVault.tsx:222; quoteReviewApi.ts:94; lib/openDocument.ts:14 | xss via location | 75 | 5 | FP: the URL comes from our own edge function (Stripe checkout or a signed storage URL) | n/a |
| src/lib/supaEnv.ts:25; supabase/functions/stripe_setup_page/index.ts:2 | jwt secret | 80 | 2 | FP: the decoded role is `anon`, a public key by design | n/a |
| src/components/me/ocrClient.ts:136 | ssrf | 60 | 1 | FP: `fetch()` of a `data:` URL in the browser | n/a |
| src/lib/og.tsx:22 | path traversal | 70 | 1 | FP: fixed font names | n/a |
| supabase/functions/** (customer_api, drawing_boq/redact/pages, backup, dropbox_backup, marketing*, supplier_api/portal/catalog_ingest, wa_inbound, stripe_webhook, reveal_invoice, pdf_native, it_restore_drill, it_scheduled_readings, bank_statement_intake, supplier_doc_trades, supplier_services, conversation_archive, doc_extract) | supabase storage path traversal | 70 | 34 | FP: each path is built on the server from ids or DB rows. User file names go through `safeFilename` (`[^A-Za-z0-9._ -]` becomes `_`, so no `/`) or a generated name. Whether a caller may reach a row is an IDOR question, which the launch-checklist audit covers. | n/a |
| supabase/functions/doc_extract/index.ts:173 | ssrf | 60 | 1 | FP: fetches a signed URL from our own storage | n/a |
| supabase/functions/drawing_boq/drawing_input.ts:25; supplier_api/quote_review.ts:825 | prototype pollution | 75 | 2 | FP: keys are allow-listed (`known.has`, or `/^[a-z][a-z0-9_:]{0,60}$/`, which blocks `__proto__`), and values are scalars | n/a |
| supabase/functions/dropbox_backup/row.ts:36 | timing attack | 70 | 1 | FP: compares a content hash, not a secret | n/a |
| supabase/functions/_shared/reveal_sale.ts:33 | sql injection | 85 | 1 | FP: concatenates an error message, not SQL | n/a |
| scripts/** (staging, e2e, lib/demo_factory, kb, eval, checks, it, cad_read_worker, ...) | sql injection (node_sqli / template literal) | 85 | 392 | FP / operator-only: CLI and CI scripts run by us with management or service credentials. Values are our own constants or `lit()`/`q()`-quoted ids. No user input path. | n/a |
| scripts/** | generic path traversal | 70 | 215 | FP / operator-only: repo-relative reads from `readdirSync` or fixed dirs on our own machine or runner | n/a |
| scripts/** (e2e/journeys, pdf_facts, legal, marketing, staging) | ssrf | 60 | 5 | FP / operator-only: fixed provider or our own URLs | n/a |
| scripts/marketing/load_calendar.mjs:17 | generic-api-key | 80 | 1 | FP: the JSON example in a comment (`"key": "2026-month1-..."`) | n/a |
| scripts/sql/*.sql (1,742) | secrets | - | 0 | clean (Aikido and grep) | n/a |

## Optional hardening

None of these is urgent. If wanted, one it_engineer PR could cover all of the workflow items:
- move the dispatch inputs into `env:` in deploy-functions and release-train;
- pin `denoland/setup-deno` and `supabase/setup-cli` by commit SHA;
- add `persist-credentials: false` everywhere except release-train;
- scope `contents: write` to the job.

The blog renderer could sanitise `body_html` at publish time.

## Follow-up (same day, on the coordinator's instruction)
Both low-risk subjects are fixed by the it_engineer seat and are with the release operator for independent review. Neither goes ahead of the launch queue.
- **#1459:** workflow hardening (inputs passed through env, actions pinned by SHA, persist-credentials, job-level permissions). It changes workflow files, so it needs a hand-merge.
- **#1461:** blog `body_html` is allow-list sanitised when the bake publishes it. Its test passes 3/3.
