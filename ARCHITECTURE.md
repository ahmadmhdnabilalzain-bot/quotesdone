# QuotesDone — architecture

Written 22 September 2026 by the it_engineer seat, for the reader who has never seen this
repository: an investor, an external auditor, or the next engineer. **Every claim here was read
out of the code on that date and cites the file.** Where something could not be verified it says
so. Where a document and the code disagree, the code is right.

---

## 1. Where each kind of thing lives

| what | where | the rule |
|---|---|---|
| a database change | `scripts/sql/<lowercase_sentence>.sql` + a line at the END of `scripts/sql/MANIFEST.txt` | one file per subject; the manifest order decides which file is canonical |
| runtime | `supabase/functions/<surface>/index.ts` | one directory per surface, 73 of them (23 Sep 2026), all deployed |
| code shared between functions | `supabase/functions/_shared/*.ts` | the paid-provider gate, the internal-auth gate, attachments, the SSRF guard |
| the web app | `src/app` (App Router, `en` at `/`, `ar` at `/ar` — `src/i18n/routing.ts:8`), `src/components`, `src/content` | the browser calls edge functions directly; `src/app/api/resilience-ping/route.ts` is the ONLY Next API route |
| a gate | `scripts/checks/*.mjs`, run by `scripts/checks/run.mjs` | a check retires WITH its subject — renamed `*.RETIRED.mjs` into `scripts/checks/retired/`, never softened |
| tooling | `scripts/lib/` is what other scripts IMPORT; `scripts/` root and its subject folders (`checks/`, `staging/`, `e2e/`, `sql/`, `kb/`…) are what a person or a workflow RUNS | one-shot scripts that already ran are in `scripts/archive/` with an index |
| the founder's words | `public.founder_instruction` | verbatim, the moment he says them; a trigger refuses `done` with no evidence |
| a settled policy | `public.company_policy_decision` + the guard that enforces it | the database enforces it, not a comment |
| conduct rules | `.claude/skills/*/SKILL.md` | a rule about HOW to work is a skill, not a document |
| narrative and history | `docs/`, and `docs/archive/` for what the company has left | never the source of truth for behaviour |

What decides a script's home is **who depends on it**, not whether it can be run. `scripts/lib/`
holds the modules other scripts import, and one of them — `demo_factory.mjs` — also answers a
command line: `--selftest` is how the fixture factory proves it returns the database to its exact
baseline. A module carrying its own self-test is a module you can trust; it is still a library,
because **70 files import it** (`qd_guard.mjs`, with **105**, has no CLI at all).

Those two counts are *files under `scripts/` containing an `import … from` or `await import(…)`
statement that names the module, excluding `scripts/archive/`* — 87 and 126 if the archived copies
are counted, measured 23 Sep 2026. Stating what was counted is the point: an earlier draft of this
paragraph said 77 and 104, which matched neither set.

Two exceptions a literal reader would trip on. `scripts/lib/` also holds three `*.test.mjs` files
(`canonical_sql`, `demo_pdf`, `retry`) that nothing imports — `scripts/checks/run.mjs` RUNS them,
which is exactly the dependency the rule is about. And the inverse is the rule that really matters:
something in `scripts/` root that nothing imports and nothing runs belongs in `scripts/archive/`.

**To find a routine, a table or a cron job by subject**, open `docs/architecture/database/README.md`: every one
production runs, filed under ten business areas with its canonical file and owning seat. It is generated
(`node scripts/architecture/database_map.mjs`) and a check fails when it drifts, so it can be trusted where this page
cannot be kept current by hand.

### The four SQL apply tiers

A routine can be defined in more than one file. Which definition is real is decided by an explicit
sequence, never by a commit timestamp — `scripts/checks/canonical_routine_manifest.mjs:20-30`:

| tier | source | sequence key |
|---|---|---|
| 1 | `supabase/migrations_history/<version>_*.sql` | `1 \| <version>` |
| 2 | `supabase/migrations/<version>_*.sql` | `2 \| <version>` |
| 3 | `ai-organization/db-functions/*.sql` | `3 \| <filename>` |
| 4 | `scripts/sql/*.sql` | `4 \| <line position in MANIFEST.txt>` |

The **highest** sequence wins; everything below it is recorded as superseded. Two files sharing a
key is itself a failure, so no tie is ever broken by a heuristic. `scripts/sql/rollback/**`,
`supabase/rollback/**`, `supabase/seeds/**` and `supabase/migrations-superseded-consolidated/**`
can never be canonical. The check also fails on repo→prod drift, on a live application routine no
file defines, and on any manifest gap in either direction.

That is why tier 3 still exists: `ai-organization/db-functions/` is read by the check at line 182
and holds definitions nothing else has replaced. It is not decoration and must not be moved.

## 2. The six seats, and what each owns

Ownership is a row in `public.function_owner`, and
`scripts/checks/every_deployed_function_has_an_owner.mjs` fails on either mismatch: a function
deployed with no owner, or an owner row whose function is gone. It reads the LIVE deployment list,
not the repository folders — a function serving on the internet with no source would otherwise
pass. Run 23 Sep 2026, against 73 deployed functions:

| seat | functions | what it is |
|---|---|---|
| `sales_engineer` | 29 | matching, supplier onboarding and catalogue, drawings and take-off, document extraction |
| `customer_support` | 19 | the customer's side: the portal backend, the chat widget, complaints, ratings, messaging, inbound SMS |
| `it_engineer` | 10 | the estate itself: the tick, backups, deployment parity, alerts |
| `accountant` | 10 | money: Stripe, refunds, invoices, the books, AI spend |
| `marketing` | 4 | channels, outreach, the social inbox |
| `ceo` | 1 | `ceo_agent` — the daily plan, the weekly report, the decisions |

The counts move. `sms_inbound` arrived on 23 Sep and made it 73 and customer_support 19 while this
document was in review, which is why the numbers carry the date they were read and the command that
reads them: `node scripts/checks/every_deployed_function_has_an_owner.mjs` prints the table above.

Every job and every task names a seat. There are no departments.

## 3. The customer's money, end to end

1. A signed-in customer drafts a request in the portal — `src/components/me/NewRequest.tsx:121`
   POSTs to the `inquiry_intake` function, which persists a DRAFT (`inquiry_intake/index.ts:85`,
   rate-limited at `:54`) and enriches it: category routing `fn_kb_route_decide` (`:132`), the
   category's questions `fn_category_questions` (`:183`), knowledge `fn_category_knowledge`
   (`:271`), and a fan-out preview through `fn_match_capability` (`:633`).
2. The real RFQ is created by `customer_api` action `create_inquiry`
   (`customer_api/index.ts:995`), inserting into **`public.inquiries`** (`:1243`) and marking the
   draft consumed (`:1244`). There is no `rfq` table; the RFQ is an inquiry.
3. Readiness is computed, not claimed: trigger `trg_rfq_complete` sets `completeness` and
   `rfq_ready` from `fn_rfq_score`, which uses `fn_rfq_required_check`.
4. Matching — `matchAndNotify` (`customer_api/index.ts:211`) calls the `sales_engineer` function's
   `match` action (`:249`), which runs **`fn_match_capability`**; eligibility is `fn_is_matchable`.
   **There is no keyword fallback**: if the matcher fails, the inquiry waits unmatched and a
   finding is raised (`:278-291`). Matches land in `public.inquiry_matches` (`:296`).
5. The supplier sees it through `supplier_api` action `inbox`, which reads `inquiry_matches` and
   then the masked view `inquiries_supplier_safe` (`supplier_api/index.ts:752-767`).
6. The supplier quotes — `submit_quote` (`:1180`) inserts into `public.quotes` as `draft` (`:1272`);
   accepting it flips the quote to `submitted` and the inquiry to `quoted` (`:154-155`).
7. **The reveal.** `customer_api` action `reveal` (`:1577`) checks ownership (`:1587`), refuses on
   a sanctions hit BEFORE any charge (`:1585`), and short-circuits an existing transaction (`:1589`).
8. **The 3%.** The rate is `public.pricing_config.standard_reveal_rate`, `DEFAULT 0.03 NOT NULL`,
   and a constraint (`pricing_config_no_discount_no_cap_ck`) neutralises any promo or cap. The
   arithmetic is in ONE module — `revealCharge()` in `supabase/functions/_shared/reveal_fee.ts:69`
   — called by the dialog (`customer_api/index.ts:1591`) and by the charge
   (`stripe_checkout/index.ts:66`), and **checkout aborts if the two disagree** (`:67`).
9. Stripe takes the money (`stripe_checkout/index.ts:219`, or the Elements flow in
   `element_pay.ts:34`). `stripe_confirm` writes `public.transactions` (`:70`) with the reveal fee,
   the processing fee, the total, `revealed_at` and a `refund_deadline` from `fn_add_working_days`.
   `stripe_webhook` is the idempotent second writer for the same row (`:355`), deduping on
   `fn_stripe_event_seen` (`:246`) and reconciling Stripe's ACTUAL fee onto it (`:111`).
10. `reveal_invoice` renders the invoice and caches it in `public.reveal_invoices` (`:108`). Every
    charge is then audited against what Stripe really took —
    `scripts/sql/every_reveal_charge_is_audited_against_what_stripe_took.sql:44`.

## 4. The supplier, end to end

1. Sign-up is at `src/app/[locale]/supplier/page.tsx`. `supplier_onboard` is **advisory only**: it
   reads free text into a profile and returns `write_path: 'supplier_api:create_company+save_profile'`
   (`supplier_onboard/index.ts:228`). Nothing is approved there.
2. `supplier_api` action `create_company` inserts into **`public.leads`** (`:289`) — suppliers are
   leads. An invited supplier claims an existing row (`:300`). Re-registration after a sanctions
   hit is refused by a database trigger, not by the function.
3. Terms — action `accept_terms` (`:571`); a trigger writes the signature certificate into
   `leads.signed_terms_path`.
4. **The mandatory six have exactly one definition**: `public.fn_supplier_mandatory_six(leads)`
   returns the missing codes — `reg_name`, `reg_mobile` (verified AND matching `^9715[0-9]{8}$`),
   `reg_email` (verified), `reg_licence` and `reg_profile` (the object must EXIST in the
   `supplier-docs` bucket, not merely be named), `reg_terms`. A trigger
   (`fn_leads_mandatory_six_gate`) refuses to verify an incomplete supplier;
   `fn_sales_engineer_verifies_supplier` reads the same function to approve. The TypeScript in
   `_shared/supplier_registration.ts` is presentation only and is held to the SQL by
   `scripts/checks/the_mandatory_six_have_one_definition.test.mjs`.
5. Catalogue — `supplier_catalog_ingest` takes untrusted bytes, writes `public.supplier_catalog`
   (`:208`) and upserts parsed lines into `public.supplier_product` (`:324`).
6. Quotes are gated before insert: terms accepted (`supplier_api/index.ts:1183`), `approval_status
   = 'approved'` (`:1187`), and the registration-fee state fail-closed (`:1198-1201`).

## 5. Telling someone: the outbox

`public.notifications` **is** the outbox — there is no `outbox` table. A row carries the channel,
the recipient, the body, `attempts`, `last_error`, a `kind`, and `attachments jsonb`.

- **Email** — `send_outbox` posts to **Resend** (`send_outbox/index.ts:222`), with the key from
  `app_secrets.resend_api_key`, three attempts then dead-letter, suppression and daily-cap gates.
  Attachments are references (`{bucket,path,filename}`) resolved at send time from an allow-list of
  five buckets with a 20 MB ceiling; an unreadable attachment FAILS the row rather than sending a
  mail without it (`:208-210`).
- **SMS and WhatsApp** — `send_sms` and `send_whatsapp` through Twilio, credentials from
  `app_secrets`. WhatsApp sends approved templates only, gated on `wa_templates_ready`, and falls
  back to email for a founder alert.
- **The founder is emailed exceptions only.** `fn_notify_founder(event, detail, level, kind,
  dedupe_key, owner_agent)` consults `public.founder_mail_policy`: not allowed for that `kind` →
  it opens an org_task for the owning seat instead; allowed → 24-hour dedupe, then an email, plus a
  WhatsApp twin when the level is critical/urgent/high/danger.

## 6. The scheduler: one cron, one tick

`vercel.json` has a single cron — `/api/resilience-ping`, `*/15 * * * *`. The route
(`src/app/api/resilience-ping/route.ts`) holds no secret of its own beyond `CRON_SECRET` and POSTs
to the `resilience_ping` edge function, which is where the company's recurring work happens.

The tick does not run a hard-coded list. `public.fn_resilience_tick_plan(p_budget_ms)`
(`scripts/sql/the_tick_runs_what_is_stalest_not_what_is_first_in_the_list.sql:150-189`) reads
`public.resilience_step`, takes the steps whose `every` has elapsed, orders them by **staleness
ratio**, cuts the list to the budget (70 s of a 110 s deadline), and appends the `place='last'`
steps. It returns what it ran, what it deferred, and what is **starved** — deferred four times or
more. A step whose name the function does not know becomes a failing step rather than silence, and
failures become IT findings through `fn_it_duty_settle`.

What it dispatches, grouped by the routine each step calls (the prefix names the seat):

- **accountant** — `weekly` report, `vat` threshold, `refunds`, the refund `ladder`,
  `accountantDuties`, `openrouter` (reads the live spend meter).
- **ceo** — `digest` (daily, with the PDF attached), `ceoWeekly`, `ceoDecisions`, `ceoPlan`.
- **customer_support** — `ratings` (`fn_support_request_ratings_due`, three weeks after a reveal),
  `seatClocks`.
- **sales_engineer** — `supplierOutreach`, `specoffer`, `deliveryCanary`.
- **marketing** — `marketing`, `marketingChannels`, `marketingOutreach`.
- **it_engineer** — `backup`, `backupVerify`, `dropboxHealth`, `tableExport`, `backupPrune`,
  `itdetect`, `itduties`, `itscheduled`, `itlater`, `launchpath`, `whatsapp`,
  `orphans` (a nested budget for send_sms, email_cron, templates, doc_extract, triage, sanctions).
- **three steps run on EVERY tick**, whatever the budget, because they are how anything else is
  heard about: `it` (the alert tick), `outbox` (drain 20 notifications), `archive`
  (`conversation_archive`).

Each tick also warms the portal functions and reads `fn_cron_liveness`; if the scheduler itself is
down, it pages the founder.

## 7. AI: one gateway, deliberately held

Every model call goes through `supabase/functions/ai_gateway/index.ts`. Before it existed, ~68
functions called OpenRouter directly, 37 with their own hand-rolled fetch, so the company could not
see what it spent. The gateway's order of operations is cheapest-first: rate limit → a Level-0
answer with no model at all → routing by `fn_ai_route` → refusal when deterministic code is the
right answer → the budget halt → an exact-hash then semantic cache on **free in-region** `gte-small`
embeddings → the call with a hard token cap → the log with real cost. `dry_run:true` runs all of it
and returns the decision without spending anything.

Permission to reach a paid provider is one function, `paidProviderGate()`
(`_shared/paid_gate.ts:44`), and **its default is refusal**: a throw, a null, a missing `allowed`,
anything that is not literally `true`, is a denial with a reason. The shape it replaced had three
separate routes to a paid call with no permission.

**OpenRouter is held on the founder's standing instruction.** The architecture is
deterministic-first: code decides, and a model is used only where code cannot.

## 8. Backups

`dropbox_backup` drains `public.doc_backups`: customer, supplier and quote documents are enqueued
only once the object actually exists in storage (`waiting_source` until then), demo rows are forced
to `entity='zz_demo'` and excluded, and uploads over 8 MiB are chunked and resumable. Three things
start it — a `pg_net` kick on insert, the tick's `backup`/`backupVerify`/`dropboxHealth` steps, and
an independent GitHub Actions schedule (`dropbox-backup-second-scheduler.yml`, `41 */6 * * *`) that
exists so a broken tick cannot silently stop the backups. Every document is confirmed by reading
its size and `content_hash` back from Dropbox; every run writes an `agent_runs` row.

## 9. Secrets

No third-party credential is in the repository, in a `.env`, or in a function's environment. Each
one is a row in `public.app_secrets`, read at call time by a `sec()` helper that fail-closes on a
short or missing value — Resend (`send_outbox/index.ts:117`), Twilio (`send_sms/index.ts:15`),
Dropbox (`dropbox_backup/index.ts:79-95`), Vercel and the site URL
(`resilience_ping/index.ts:1094-1099`). The only environment variables an edge function reads are
the three Supabase injects plus a handful of test switches. A credential is warned 30 days before
it expires and a rotated one stays valid until the run that retires it
(`scripts/sql/a_rotated_credential_stays_valid_until_the_run_that_retires_it.sql`).

Internal calls between functions are authenticated by `requireInternal()`
(`_shared/internal_auth.ts:65`) against a per-caller credential, not a shared static secret.

---

### What this document does NOT cover

The customer and supplier portals' screen-by-screen behaviour (`docs/CUSTOMER_PORTAL.md`,
`docs/SUPPLIER_PORTAL.md`), the knowledge corpus and how it is certified (`docs/knowledge/`,
`docs/expertise/`), and the seats' own operating rules (`.claude/skills/`). It also does not
describe staging: `scripts/staging/` targets a second Supabase project used for rehearsal only,
and `scripts/lib/qd_guard.mjs` is what makes a staging write incapable of reaching production.
