# Reliability checklist audit, 10 Nov 2026

Owner: it_engineer. Asked by the founder (ledger 1605): "are these done for our app?". Branch
`it_engineer-reliability-audit-10-nov`. It builds on the 9 Nov launch checklist
([2026-11-09-launch-checklist.md](2026-11-09-launch-checklist.md)), which had no production access. This pass had
read-only production access, so most rows here are measured on production, not taken from code alone.

## Summary for the founder

1. **61 items** in your list. Idempotency counts as one item; the table gives its three cases a row each, so it has 63 rows.
   **DONE 22, PARTIAL 26, MISSING 5, N-A 8.** (By row: DONE 24, because all three idempotency cases are DONE.)
   Three of the PARTIAL items were improved on this branch: timeouts, indexing and time zones.
2. **Fixed on this branch (5 changes, each with a test).** They are committed and pushed. They are not merged, applied or deployed.
   (a) Timeouts. The 13 Stripe, Twilio and Resend calls in the money and messaging functions that could wait forever now give up after 15 seconds. The check now holds those functions at 0 such calls.
   (b) Dates. Six places printed a document date in UTC, so a PDF made after 20:00 UTC (midnight in Dubai) showed yesterday's date. They now print the Dubai date.
   (c) An index. The email sender and the chat look up a supplier by address by reading all 20,300 leads. The new index brings the planner's cost from 2,230 to 48.
   (d) A new check that every fire-and-forget call handles its own failure. There are 0 such gaps today, and the check keeps it at 0.
   (e) The debt register: one row updated (TD-03) and five added (TD-19 to TD-23; TD-18 was taken on main the same day).
3. **The two gaps that matter most.** Neither is built here; each has a proposal below.
   - **Point-in-time recovery is OFF in production** (`pitr_enabled: false`). Recovery is the daily backup, so up to 24 hours of data can be lost.
   - **A whole-database restore has never been run.** Only one table at a time has been restored. The weekly single-table drill passes; the last run was 8 Nov.
4. **Healthy, measured today.**
   - Scheduled jobs: 99 of 99 active, 26,698 runs in 24 h, 0 failed.
   - Backups: a daily table export every day (last 10 Nov 00:47 UTC), plus 7 daily platform backups.
   - Database connections are encrypted and the database is closed to the internet.
   - Sign-up is closed (`disable_signup: true`).
   - Stripe, email, WhatsApp and quote submits are all protected against double processing.
5. **Not urgent but real.**
   - The site's server code runs in Washington, the database is in Singapore, and the customers are in the UAE.
   - There is no rate-limit rule in front of the website.
   - No outside service checks that the site is up.
   - 175 indexes have no recorded use (202 MB).
6. **Honest limits.**
   - GitHub branch protection and the Actions settings could not be read: the proxy answered 403.
   - The usage counters behind the index findings have never been reset, so I do not know the window they cover.
   - No load test was run: the rules forbid one against production, and there is nowhere else to run it. (11 Nov 2026: one has now been run against production with tools that commit nothing and reach no one, under ruling 1622. See item 30 and [2026-11-11-load-test.md](2026-11-11-load-test.md).)

## How to read the table

- Status: DONE (exists and measured working), PARTIAL (exists, with a measured gap), MISSING, N-A (the platform does
  it; the row says what the platform gives).
- Evidence: **[P]** read-only production query or management-API read, 10 Nov 2026 17:15 to 17:50 UTC.
  **[L]** live HTTP response from quotesdone.com, same time. **[V]** Vercel API. **[C]** file:line on this branch.
  **[K]** an enforcing check under `scripts/checks` or a gate step.
- Fix/commit: `this branch` means the commit on `it_engineer-reliability-audit-10-nov` that carries this report.
  TD-nn is a row in [../engineering/tech-debt.md](../engineering/tech-debt.md).

## The table

### Traffic and limits

| # | Item | Status | Evidence | Fix / commit |
|---|---|---|---|---|
| 1 | Load balancing | N-A | Platform-managed. Vercel's edge network routes every request; [L] `server: Vercel`, `x-vercel-id: iad1::…`. Supabase fronts the database and the functions with its own gateway. | none needed |
| 2 | Rate limiting | PARTIAL | [C] `rl_check` in 13 edge-function files. [C] `customer_api/actions/inquiry_create.ts:129` returns 429 after 20 inquiries an hour. [P] Supabase auth limits: `rate_limit_otp: 30`, `rate_limit_verify: 30`, `rate_limit_email_sent: 30`. [V] The Vercel firewall API answers 404 "config not found", so there is no edge rule; only Vercel's built-in DDoS protection applies. | TD-23 |
| 3 | Reverse proxies | N-A | Platform-managed: Vercel for the site, the Supabase gateway for functions, Supavisor for the database. | none needed |
| 4 | API gateways | N-A | Platform-managed: the Supabase functions gateway, with `verify_jwt` pinned per function ([C] 79 entries in `supabase/config.toml`). Model calls all pass through our own `ai_gateway`. | none needed |
| 5 | CDNs | DONE | [L] the homepage answers `x-vercel-cache: HIT`, `age: 3184`. Supabase Storage serves files through its CDN. | (no `next/image`; see item 62) |
| 6 | Caching and cache invalidation | PARTIAL | [L] Pages: `cache-control: public, max-age=0, must-revalidate` at the browser and HIT at Vercel, which purges on every deploy. `/api/health`: `no-store`. [C] `next.config.mjs:127` gives fonts 30 days at fixed URLs with no version in the name, so a changed font is not picked up for up to 30 days. `llm_cache` is keyed by hash. | none (low) |
| 7 | HTTPS / TLS | DONE | [L] `strict-transport-security: max-age=63072000; includeSubDomains` on quotesdone.com. [P] `ssl-enforcement {"database":true}`. Network restrictions allow only the documentation ranges `192.0.2.1/32` and `2001:db8::1/128`, so the database is closed to the internet. Minor: the `www.quotesdone.ae` redirect sends HSTS without `includeSubDomains`. | none needed |

### Configuration

| # | Item | Status | Evidence | Fix / commit |
|---|---|---|---|---|
| 8 | Environment variables | DONE | [C] `.env.example` lists every variable the site needs. [C] `src/lib/supaClient.ts:27`: a preview build without `NEXT_PUBLIC_SUPABASE_URL` connects to no database at all. Edge functions read only the injected `SUPABASE_*` variables; other settings live in `app_secrets` ([P] 286 rows). | none needed |
| 9 | Feature flags | PARTIAL | [P] There is no flag system. 22 of the 286 `app_secrets` keys are switches by name (`*_enabled`, `*_golive`, `*_switch`, `*_on`), for example `invite_enabled`. They sit in the same table as the secrets and have no flag-level audit trail or UI. | proposal, gap 7 |
| 10 | Staging environments | MISSING (by ruling) | The staging project was deleted on 15 Aug 2026 by founder ruling. [V] 0 custom Vercel environments. [P] the only Supabase branch is `main`. Vercel previews are public (`ssoProtection: null`) but connect to no database (item 8). The nearest thing to staging is `npm run db:local`, which builds the schema locally with no data. | proposal, gap 3 (not built: the ruling stands) |
| 11 | Infrastructure as code | PARTIAL | [C] In code: `supabase/config.toml`, `vercel.json`, `Dockerfile`, `docker-compose.yml`, the schema mirror, and `scripts/sql/MANIFEST.txt` with read-back. Not in code, but read today: Supabase auth, SSL and network settings, PITR, the pooler, Vercel domains and protection, and environment variables. | proposal, gap 8 |

### Requests and errors

| # | Item | Status | Evidence | Fix / commit |
|---|---|---|---|---|
| 12 | Input validation | PARTIAL | [C] Every field is checked by hand: UUID regexes, caps, enums. No function uses a schema library (0 imports of zod). The open findings are those in the 9 Nov checklist (M1: storage paths taken from the request body). | none here |
| 13 | HTTP status codes | PARTIAL | [C] 429 on the inquiry limit (`inquiry_create.ts:129`); 409 on `already_revealed` and `inquiry_concluded` (`supplier_api/actions/quotes.ts:193`, `:226`). [C] `_shared/observe.ts` records 5xx as error and 4xx as warn. But some internal ticks answer 200 with `ok:false`, e.g. `send_outbox/index.ts:205` when the claim fails. No check covers status consistency across 78 functions. | none (low) |
| 14 | Error handling | PARTIAL | [C] `observe()` wraps 66 of the 78 functions. Not wrapped: backup, embed_ml, it_engineer, marketing_channels, marketing_outreach, marketing_social_connect, oauth_connect, public_site, site_error_ingest, stripe_setup_page, voice_otp, voice_otp_capture. [P] In 24 h, `agent_runs` under `fn:*`: 10,708 ok, 358 warn, 981 error. [C] Bilingual `error.tsx` and `global-error.tsx`. | none here |
| 15 | Timeouts | PARTIAL, improved | [K] `every_outbound_fetch_has_a_timeout.mjs` (gate step `fetch-timeout`). Before: 65 calls with no timeout. Now: **52**. The money and messaging functions (accountant, stripe_*, send_*, wa_*, refund*, supplier_pay, reveal_invoice, sms_inbound) are **held at 0** by a new rule in the same check; a deliberately added call made it fail, as it should. [P] Database `statement_timeout` 120 s; each scheduled duty sets 60 s. | **this branch**: 13 calls wrapped in `timedFetch` (`accountant/actions/duties.ts:34,121`, `refunds.ts:252`, `expenses.ts:63`, `send_whatsapp/twilio.ts:65`, `stripe_setup/index.ts:38,75,221`, `wa_template_setup/index.ts` x5) + the zero rule; TD-03 |
| 16 | Exponential backoff | DONE | [C] `send_outbox/index.ts:33`: retries at 5 then 20 minutes, honouring `Retry-After`. [C] `scripts/lib/db.mjs`: doubling waits with jitter. The model gateway stops after 2 paid attempts. | none needed |
| 17 | Idempotency: Stripe webhooks | DONE | [C] `stripe_webhook/index.ts:237` records `fn_stripe_event_seen`. [P] Event ledger keyed on `stripe_events_pkey (event_id)`; `transactions_quote_id_uidx` and `transactions_refund_stripe_uidx` are unique. A duplicate delivery is logged and ignored (`:265`, `:313`, `:397`). [C] Our own calls to Stripe send an `Idempotency-Key` (`stripe_checkout/index.ts:250`, refunds `qd_refund_<id>`). | none needed |
| 18 | Idempotency: message sends | DONE | [C] Rows are claimed with `FOR UPDATE SKIP LOCKED` (`fn_notifications_claim`; `send_whatsapp/index.ts:206`, `send_outbox/index.ts:204`). Each email to Resend carries `Idempotency-Key: qd-notif-<id>` (`send_outbox/index.ts:476`), so a timeout cannot cause a second email. [P] Today: 1,093 sent, 10 queued, 0 rows retried. Note: `notifications.dedupe_key` has a unique index, but 0 of 1,434 rows set it. | none needed |
| 19 | Idempotency: quote submits | DONE | [P] `quotes_inquiry_supplier_option_key UNIQUE (inquiry_id, supplier_id, option_no)`. [C] 409 when the quote was already revealed or the inquiry concluded (`supplier_api/actions/quotes.ts:193`, `:226`). | none needed |
| 20 | Circuit breakers | PARTIAL | Models: `llm_route_health` plus the `ai_gateway` circuit. [P] It is working: 734 HTTP 503 `circuit_open` answers between 15:00 and 17:07 UTC today, and 0 of 24 routes open at 17:40. WhatsApp has sender failover and the invitations have a bounce brake. There is still no breaker for Resend, Stripe or Twilio themselves. | TD-12, proposal, gap 9 |

### Data

| # | Item | Status | Evidence | Fix / commit |
|---|---|---|---|---|
| 21 | Database indexing | PARTIAL, improved | [P] The `leads` table: 122,481 sequential scans, 2.45 billion rows read. One named cause: `leads.claimed_by ilike $1`, 8,038 calls at 9.9 ms (`send_outbox/index.ts:182`, `site_assistant/index.ts:137`, and two more). EXPLAIN: Seq Scan, 20,300 rows removed. **Rehearsed, rolled back:** a partial trigram index makes the planner use a Bitmap Heap Scan (cost 2,230.90 down to 47.56), probe PROBE OK. Also found: 175 indexes nothing reads (202 MB); the email-check batch takes 424 ms every 5 min to find nothing. | **this branch**: `scripts/sql/a_signed_in_supplier_is_found_by_index_not_by_reading_every_lead.sql` + `_probe.sql` + pending notes; TD-19, TD-20 |
| 22 | Database migrations | PARTIAL | [C] One file per change in `scripts/sql/` plus MANIFEST order; `apply_sql.mjs --apply --ddl` reads the definition back; pending notes; `rehearse_sql.mjs` runs a file rolled back on production. Still open: `supabase/migrations` cannot rebuild the database (TD-10). | TD-10 |
| 23 | Backups | DONE | [P] `table_export_run`: a run finished every day, the last on 10 Nov 00:47 UTC (incremental); the last full one on 6 Nov. [P] Management API: `walg_enabled: true` and 7 daily physical backups (3 to 9 Nov, all COMPLETED). [P] `dropbox_backup_second_scheduler` copies off-platform every 6 h. **But `pitr_enabled: false`**, so the platform's recovery point is the last daily backup. | see item 58 |
| 24 | Database normalization | PARTIAL | [P] 793 tables; heavy use of jsonb; id types drift between tables (9 Nov checklist). No normalization review has been done. | none (large, not a launch matter) |
| 25 | Soft deletes | PARTIAL (by design) | [P] Only 2 of 793 tables have a `deleted_at` / `archived_at` / `is_deleted` column. Deletes are hard, PDPL erasure runs daily (item 59), and leads use `merged_into`. Undoing a delete depends on backups, and PITR is off. | none here |
| 26 | Connection pooling | DONE | [P] Supavisor in transaction mode on port 6543; PostgREST pool timeout 10 s; `max_connections` 120; about 23 sessions open when measured, 9 of them PostgREST idle. No direct `pg` client in `src`. | none needed |
| 27 | Read replicas | N-A | [P] One primary in `ap-southeast-1`, database 3,657 MB. The platform offers replicas as an add-on; nothing at pre-launch load needs one. | none |
| 28 | Race conditions | DONE | [C] Schema mirror: 43 `FOR UPDATE SKIP LOCKED`, 27 advisory locks. [K] Gate step `otp-race` (a burst against a throwaway Postgres, plus the founding-rank lock), `_shared/founding_rank_race.check.ts`. Unique indexes on every money table (item 17). | none needed |

### Testing and change

| # | Item | Status | Evidence | Fix / commit |
|---|---|---|---|---|
| 29 | Automated testing (unit, integration, end-to-end) | PARTIAL | Unit: [C] 403 Deno `*.test.ts` and 33 `src` tests. Checks: [K] 543 `scripts/checks/*.test.mjs`. Integration: `otp-race` on real Postgres, and `rehearse_sql.mjs` against production rolled back. End-to-end: Playwright walk workflows exist (`.github/workflows/*-walk.yml`, `nightly-journey.yml`), but **they do not run while Actions is off** (ledger 1564). | proposal, gap 6 |
| 30 | Load testing | PARTIAL (11 Nov 2026) | [M] Measured on production with tools that commit nothing and reach nobody ([2026-11-11-load-test.md](2026-11-11-load-test.md)). Website: 200 users, 0% errors. Public functions: 400 users, 0.02% errors, in-region p95 94 ms. 50 inquiry writes at once, rolled back: 0 errors, p95 2.3 s (CPU-bound). **First limit: `embed_ml`**, 7 to 15% 546/503 on a cold ramp at about 10 a second. The chat turn with the stubbed model is ready but not run: the stub needs deploying. | `scripts/load/ramp_driver.mjs`, `db_write_burst.mjs`, `chat_load_run.mjs`; stub `_shared/load_stub.ts`; 546 retry in `_shared/ml_embed_client.ts`; TD-32 to TD-34 |
| 31 | Code review | PARTIAL | [C] `.github/pull_request_template.md`; merge only by PR. No `CODEOWNERS`. Branch protection on `main` could not be read (GitHub API 403 to this session). | gap list |
| 32 | Branching strategy | DONE | Trunk on `main`, a branch and a PR for every change (this audit is `it_engineer-reliability-audit-10-nov`). | none needed |
| 33 | Semantic versioning | MISSING | [C] `package.json` version `0.1.0`. The 4 tags are checkpoint and phase markers, not versions. No `CHANGELOG.md`. | gap list |
| 34 | API versioning | MISSING (low) | Functions are addressed as `/functions/v1/<name>`, but that is the platform's version, not ours; our own payloads carry none. The site (Vercel) and the functions (Supabase) deploy separately, so a browser holding an old page can call a changed contract. | gap list |
| 35 | API documentation | PARTIAL | [C] `docs/api/` holds 4 documents (the supplier-portal contracts) for 78 functions. No OpenAPI. | gap list |
| 36 | CI/CD | PARTIAL | GitHub Actions is off (ledger 1564). The proxy refused the Actions settings API, so its state was not re-read. Its replacement: [K] `npm run gate` (`scripts/ci/local_gate.mjs`, about 30 steps; production steps show as SKIPPED offline, never PASS). Releases go by `docs/runbooks/release-without-ci.md` and `deploy_functions.mjs`, which refuses a `verify_jwt` drift. [V] Vercel deploys on push; latest deployment READY. | none (ruling) |

### Jobs

| # | Item | Status | Evidence | Fix / commit |
|---|---|---|---|---|
| 37 | Message queues | DONE | [P] The `notifications` table is the outbox (statuses sent 1,093, skipped 172, suppressed 98, cancelled 61, queued 10); rows are claimed with `SKIP LOCKED`, with a 5-minute claim expiry. `cad_read_jobs`, `review_queue` and `doc_backups` follow the same pattern. | none needed |
| 38 | Background jobs | DONE | [P] `seat_duty`: 157 duties, 155 enabled, 83 with their own cron job. One duty was failing: `customer_support.knowledge_request_deadline`, 8 failures since 2 Nov. It raised `it_engineer_finding` `seat_duty:customer_support.knowledge_request_deadline`, so the alerting worked, and the fix went live at 16:18 UTC today. Its next run, 20:05 UTC, will show whether the fix holds. | none (already fixed today; watch the 20:05 run) |
| 39 | Cron jobs | DONE | [P] `cron.job`: 99 jobs, 99 active. `cron.job_run_details` in 24 h: 26,698 succeeded, 0 failed. Vercel cron `/api/resilience-ping` every 15 minutes (`vercel.json`). `cron_history_purge_hourly` keeps the history table bounded. | none needed |
| 40 | Webhooks | DONE | [C] Stripe HMAC with a ±600 s window plus the event ledger. Twilio HMAC with `MessageSid` dedupe. Resend checked by Svix in constant time. Meta `x-hub-signature-256`. Channel handlers answer first and do the work after (`_shared/async_webhook.ts:33` `ackThenWork`). | none needed |

### Runtime

| # | Item | Status | Evidence | Fix / commit |
|---|---|---|---|---|
| 41 | Docker | DONE (local only) | [C] `Dockerfile` (non-root; `HEALTHCHECK` now calls `/api/health`, `Dockerfile:83-84`, which the 9 Nov checklist had open) and `docker-compose.yml`. Production does not use Docker; it is Vercel and Supabase. | none needed |
| 42 | Stateless services | DONE | Next on Vercel and the edge functions keep no session state; state lives in Postgres. | none needed |
| 43 | Horizontal vs vertical scaling | N-A | Platform-managed. Vercel functions and Supabase edge functions scale horizontally on their own. The database scales vertically by plan ([P] `shared_buffers` 1 GB, `max_connections` 120). | none |
| 44 | Health checks | DONE | [L] `/api/health` answers 200 with `no-store`. [P] `edge_health_probe`: 868 probes in 24 h, every one `up` or `ALIVE`. `/api/resilience-ping` (authenticated) is the deeper check. | none needed |
| 45 | Graceful shutdown | N-A | Platform-managed: Vercel and Supabase drain their own isolates. The Docker runner starts `next` directly with `init: true` (`Dockerfile:86`, `docker-compose.yml`). | none |
| 46 | Concurrency and async/await (unawaited promises) | DONE, now guarded | [C] Measured: 3 calls that start a statement without `await`, all deliberate and all with a failure handler (`customer_api/actions/inquiry_create.ts:124`, `customer_api/index.ts:105`, `site_assistant/index.ts:442`). 18 hand-offs to `EdgeRuntime.waitUntil`. Deno stops an isolate on an unhandled rejection, and no function registers a listener for one (0). | **this branch**: [K] `scripts/checks/every_fire_and_forget_call_handles_its_rejection.test.mjs` |
| 47 | Memory leaks | N-A (mostly) | Edge isolates are short-lived, and [C] the functions contain 0 `setInterval`. The one long-lived process is the Docker `next start`, used locally only. Never profiled. | none |

### Observability

| # | Item | Status | Evidence | Fix / commit |
|---|---|---|---|---|
| 48 | Logging and structured logging | PARTIAL | [C] `observe()` writes one structured row per run to `agent_runs` (agent `fn:<slug>`, status from the HTTP code, counts as jsonb) for 66 functions. Elsewhere `console.*` is free text. There is no request id to follow one request from Vercel to a function to the database. | proposal, gap 10 |
| 49 | Monitoring | DONE | [P] `edge_health_probe` (868 probes in 24 h), 155 seat duties, `resilience_ping` every 15 minutes, `it_engineer_finding`. | none needed |
| 50 | Alerting | DONE | [P] The failing duty in item 38 became the finding `seat_duty:customer_support.knowledge_request_deadline` with its alert fields set. `openrouter_low_balance_hourly` ran 8 times in 24 h. Single recipient, no on-call rota. | none needed |
| 51 | Distributed tracing | N-A | Two hops (site to function to database) at pre-launch volume. The structured run row per function covers diagnosis today. The cheap step is a request id (item 48), not a tracing system. | gap 10 |
| 52 | Error tracking | PARTIAL | [P] `error_events` in 7 days: 1,123 `site_report_ready` (info) and **0** `runtime_error`. The server path is wired (`src/instrumentation.ts:39` `onRequestError`). The browser has no `window.onerror` or `unhandledrejection` reporter, so a client-side failure is not seen. Function errors go to `agent_runs` (981 errors in 24 h; 945 from `ai_gateway`, of which 734 were the model circuit, item 20). | gap list |
| 53 | Uptime monitoring | PARTIAL | Only the internal `/api/resilience-ping`, run by a Vercel cron on the same platform it watches. No external monitor (TD-13). | TD-13 (you hold the account; about 30 minutes) |
| 54 | Debugging and profiling | PARTIAL | [P] `pg_stat_statements` on since its reset of 2 Nov 07:12 UTC, but `track = top`, so statements inside routines are not attributed (this is why the `leads` scans could only be partly explained). `log_min_duration_statement = -1`, so slow queries are not logged. No front-end profiling. | gap list |

### Correctness details

| # | Item | Status | Evidence | Fix / commit |
|---|---|---|---|---|
| 55 | Time zones (Asia/Dubai vs UTC) | PARTIAL, fixed | [P] Database `TimeZone` UTC, `cron.timezone` GMT; 1,352 `timestamptz` columns against 1 `timestamp`. Edge functions run in UTC. [C] Six formatters printed the UTC day, so between 20:00 and 24:00 UTC a document showed yesterday's date: `pdf_native/render.ts:194,197`, `_shared/quote_documents/kit.ts:43`, `_shared/quote_documents/inquiry_document.ts:54`, `customer_api/actions/reviews.ts:107`, and `fmtDate` in `_shared/supplier_charge_documents.ts`, which dated the supplier agreement in the recovery letter. All six now print the Dubai date. | **this branch**: the fix, [K] `scripts/checks/every_date_we_print_is_dubai_time.test.mjs`, and the behaviour test `supabase/functions/_shared/document_dates_are_dubai_dates.test.ts` |
| 56 | Character encoding (Arabic) | DONE | [P] `server_encoding` UTF8. [K] Arabic checks in the suite (`nothing_a_supplier_reads_can_be_arabic` 131/131 pass, `pricing_arabic_parity`, `arabic_reaches_the_same_answer_as_english`, and others). `<html lang dir>` is set. Pre-existing on main, not this branch: `every_arabic_message_is_written_not_translated` fails on 7 unreviewed lines in `scripts/sql/two_customer_support_duties_read_only_their_own_kind_of_row.sql`. | owned by customer_support (not this change) |

### Cost and resilience

| # | Item | Status | Evidence | Fix / commit |
|---|---|---|---|---|
| 57 | Cost monitoring (AI spend, low-credit warning) | DONE | [P] `openrouter_low_balance_hourly` (`23 * * * *`) is active, with 8 successful runs in 24 h. [K] `the_founder_hears_before_the_ai_credit_runs_out.test.mjs` pins the USD 10 and USD 2 bands, one warning a day per band, through `fn_notify_founder`. `ai_cost_log` has 50,975 rows; the weekly provider-cost watch is a seat duty. Vercel, Supabase, Twilio and Resend invoices are not read automatically. | none here |
| 58 | Disaster recovery (has a restore been tested?) | PARTIAL | [P] `it_restore_drill_result`: 10 drills, every one a **single table** (the last on 8 Nov, `pricing_config`, ok, 100 rows rebuilt). The one failure, on 14 Sep, was fixed. **A whole-database restore has never been run. PITR is off.** The 4-hour recovery time is a target, not a measurement. | proposal, gaps 1 and 2; TD-21 |

### Compliance and quality

| # | Item | Status | Evidence | Fix / commit |
|---|---|---|---|---|
| 59 | Data privacy (UAE PDPL / GDPR: retention, deletion, consent) | PARTIAL | [P] `pdpl_erasure_daily` and `conversation_retention_daily` each succeeded 3 times in 3 days; `retention_policy` covers 11 storage buckets (tax 2,555 days, operational 365 to 1,095). Consent: [C] `src/components/CookieConsent.tsx`, plus the WhatsApp opt-in rules. [P] `pdpl_requests` has 0 rows, so no data request has ever been made through it in production. Data leaves the UAE: the database is in Singapore, the site functions in the US (iad1), and the models are external. That transfer basis needs a legal reading against the privacy notice, not an engineering one. | legal check (not engineering) |
| 60 | Accessibility | PARTIAL | [C] `<html lang dir>`, a skip link, and the jsx-a11y rules in oxlint (warn counts in `docs/engineering/linting.md`, for example 118 `prefer-tag-over-role`). No axe or Lighthouse run anywhere. | gap list |
| 61 | Mobile responsiveness | PARTIAL | [K] `the_mobile_panels_sit_on_the_tab_bars_real_height.test.mjs`; Playwright is installed. No device matrix or screenshot run. | gap list |
| 62 | Performance budgets | MISSING | No bundle-size or LCP budget in the gate; 0 uses of `next/image`. [L] The server functions run in **iad1 (Washington)** while the database is in Singapore, so every server-side database call crosses the Pacific. | TD-22, gap list |
| 63 | Technical debt | DONE | [C] `docs/engineering/tech-debt.md`. This pass updated TD-03 and added TD-19 to TD-23 (TD-18 was taken on main the same day), each with its measurement. | **this branch** |

(63 rows for 61 items: idempotency has three rows, 17 to 19. By row: DONE 24, PARTIAL 26, MISSING 5, N-A 8. By item:
DONE 22, PARTIAL 26, MISSING 5, N-A 8.)

## Gaps, in priority order, with effort

Effort: S under 1 day, M 1 to 3 days, L more than 3 days. "You" means only the founder can do it (an account he holds, or money).

| # | Gap | Why it matters | Proposal | Cost | Risk if left | Effort |
|---|---|---|---|---|---|---|
| 1 | **PITR off** | A wrong write or delete at 18:00 can only be undone to the last daily backup: up to 24 h of inquiries, quotes and payments lost. | Turn on the Supabase PITR add-on (7-day retention). It is a setting; no code changes. | Money (yours): the add-on is priced per month on top of the plan, and it needs the Small compute add-on or larger. Check the current price in the dashboard; I did not read billing. | H | S (you, about 10 minutes) |
| 2 | **No whole-database restore ever run** | The 4 h recovery time is a claim. The single-table drill shows a table export can be read; it does not show the database can come back. | Once: create a Supabase branch, restore the newest physical backup (or the full table export) into it, run `fn_it_full_restore_compare`, and record the elapsed time and row counts in `it_restore_drill_result` (runbook: `docs/runbooks/restore-and-disaster-recovery.md`). Then quarterly. | A branch costs compute by the hour while it exists (a few dollars for one drill). | H | M |
| 3 | No staging | Every change goes straight to the one project. The ruling of 15 Aug ("nothing in staging that can affect our build up process… anything that can cost me extra money") stands. | Do not rebuild a staging project. Use a short-lived Supabase branch per risky release (create, apply, test, delete), with ZZ DEMO seed data. | Hourly branch compute, only while it exists. | M | M |
| 4 | No external uptime monitor (TD-13) | If Vercel or Supabase is down, the only watcher runs on the same platform. | An external monitor on `/api/health` (quotesdone.com and quotesdone.ae), every 1 to 5 minutes, alerting by email or WhatsApp. | Free tier of a common monitor is enough. | H | S (you, about 30 minutes) |
| 5 | No load test | Unknown limits on inquiry creation, sign-in and the outbox before paid traffic. | k6 scripts against a Supabase branch (gap 3) with ZZ DEMO data, never production: 20, 50 and 100 users on sign-in and inquiry-to-quote. Record p95 and errors. | Branch hours only. | M | M |
| 6 | End-to-end tests do not run while Actions is off | The walk workflows prove the whole funnel, but nothing runs them. | Run the walk scripts from the local gate or a Claude cloud routine (`release-without-ci.md` §3) against ZZ DEMO fixtures on a schedule. | None. | M | M |
| 7 | Flags mixed with secrets | A switch change is a secret-table write with no flag-level history. | A `feature_flag` table (key, on, owner seat, changed_by, changed_at, reason) with an audit trigger; read through one helper. Move the 22 switches in batches. | None. | L | M |
| 8 | Platform settings not in code | Auth, network, SSL, PITR and Vercel settings can drift silently. | A read-only check that reads the management API (as this audit did) and compares with a committed `infra/expected.json`, run in the gate's production steps. | None. | M | S |
| 9 | No breaker for Resend, Stripe and Twilio (TD-12) | During a provider outage every send waits out its timeout and retries. | A per-provider breaker in `_shared` (opens after N consecutive failures, half-open after M minutes), recorded in `edge_health_probe`. | None. | M | M |
| 10 | No request id | One customer's failure cannot be followed across the site, a function and the database. | Generate `x-qd-request-id` at the site and in each function, forward it on internal calls, and write it into `agent_runs.counts`. | None. | L | S |
| 11 | No edge rate-limit rule (TD-23) | Abuse reaches the functions before `rl_check`. | One Vercel firewall rate-limit rule on `/api/*` and the sign-in pages. | Included in the Vercel plan or a small add-on. | M | S |
| 12 | Server region (TD-22) | iad1 to Singapore adds a long round trip to every server-side database call. | Set `regions` in `vercel.json` near the database or near the customer, measured before and after on one server route. | None. | M | S |
| 13 | Debt from this pass: TD-19 (email-check batch, 424 ms every 5 min), TD-20 (175 indexes nothing reads, 202 MB) | Wasted database time and disk. | TD-19: rewrite the due test onto two indexes. TD-20: reset the counters, wait 30 days, then drop by a reviewed file. | None. | L | S each |
| 14 | Browser errors not reported | A client-side crash is invisible (0 `runtime_error` in 7 days). | `window.onerror` and `unhandledrejection` posting to `site_error_ingest`, rate-limited per page load. | None. | M | S |
| 15 | Small items | Semantic versioning (tag `v1.0.0` at launch, start `CHANGELOG.md`); `CODEOWNERS`; an OpenAPI index for the 78 functions; API version field in payloads; axe and Lighthouse on 6 key pages; a performance budget in the gate; `log_min_duration_statement` at 1 s. | As listed. | None. | L | S each |

## What was built on this branch, and how it was proved

| Change | Files | Proof |
|---|---|---|
| Timeouts on money and messaging calls; those functions held at 0 | `accountant/actions/{duties,refunds,expenses}.ts`, `send_whatsapp/twilio.ts`, `stripe_setup/index.ts`, `wa_template_setup/index.ts`, `scripts/checks/every_outbound_fetch_has_a_timeout.mjs`, `outbound_fetch_timeout_baseline.json` (65 to 52) | The check: 0 findings, 52 calls. Control: an unbounded call added to `send_whatsapp` made it exit 1 and name the line; then removed. Deno tests for `send_whatsapp`, `stripe_setup` and `pdf_native`: 99 passed, 0 failed. |
| Document dates in Dubai time | `pdf_native/render.ts`, `_shared/quote_documents/{kit,inquiry_document}.ts`, `customer_api/actions/reviews.ts`, `_shared/supplier_charge_documents.ts` (`dubaiDay`) | `document_dates_are_dubai_dates.test.ts` (22:30 UTC on 14 Sep prints 15 September; the boundary is 20:00 UTC; a plain due date is never shifted) and `supplier_charge_documents.test.ts`: 13 passed. `every_date_we_print_is_dubai_time.test.mjs`: 2 passed. |
| Index for the signed-in supplier look-up | `scripts/sql/a_signed_in_supplier_is_found_by_index_not_by_reading_every_lead.sql`, `_probe.sql`, two notes in `scripts/sql/pending/` | `node scripts/ci/rehearse_sql.mjs <file> <probe>` gave PROBE OK, rolled back. The plan changed from a Seq Scan to a Bitmap Heap Scan on the new index. Afterwards production still has no such index (`pg_class` count 0), so nothing was applied. |
| Fire-and-forget calls must handle their failure | `scripts/checks/every_fire_and_forget_call_handles_its_rejection.test.mjs` | 2 passed (the scanner's own cases, then 0 findings across the functions). |
| Debt register | `docs/engineering/tech-debt.md` (TD-03 updated; TD-19 to TD-23 added) | This document. |

Not done here: no merge, no apply, no deploy, no PR, and no model call. Nobody was messaged. No load was sent to
production.

Local gate, `npm run gate -- --offline --skip=npm-test` on this branch (10 Nov 2026, 17:31 to 17:54 UTC):
- 12 steps PASS: ssrf, fetch-timeout, dwg, redact-page, scan-redact, migration-lint, lint, typecheck, audit,
  deno-gated, deno-all, otp-race.
- 1 step, `scan-takeoff`, was killed twice by the kernel for memory. Four gates were running at once on the 13.4 GB
  container. Re-run alone, the same command passed: 2 of 2. This change does not touch it.
- Production steps were SKIPPED (offline).

Run separately, all passing: `canonical_routine_manifest.mjs` (with the token: 0 findings), `each_pending_sql_file_has_its_own_note`,
`canonical_routine_manifest_applies_at_merge`, `every_sql_replay_goes_through_safe_replay`, `every_test_file_is_run`,
and the Deno tests named above.

Failing on main and not caused here: `every_arabic_message_is_written_not_translated` (item 56) and
`arabic_glossary.mjs` (2 banned renderings). Both fail identically with this branch's tracked changes stashed.
