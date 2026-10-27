# Security hardening pass, 27 Oct 2026

**Seat:** it_engineer. **Asked by:** the founder, 27 Oct 2026: *"i dont have time to do all these, cant you do them?"*
**Project:** `htdblwldjkcgjvmqkbeh` (the one project). **Hard rule for this pass:** zero downtime. Every change gets a
read-back and a smoke test, and is rolled back at once if anything breaks.

**Production changes made in this pass: none.** All four items were measured first. Each change that was in scope
either costs downtime (item 1), rests on something that cannot be established with certainty from our side (item
2), cannot be finished without code changes that need review and a deploy (item 3), or needs `supabase_admin`
(item 4). The only statements run against production were reads, plus one rolled-back probe (item 4). After the
probe, a read-back showed nothing had changed.

| # | item | state | what is left |
|---|---|---|---|
| 1 | Enforce SSL on Postgres | **not done.** Client survey done: every external client already uses TLS | founder's OK for a short restart window |
| 2 | Restrict direct Postgres network access | **not done.** The client set is not certain | Supabase's answer to ticket B below |
| 3 | Legacy JWT secret exposure | **partly done.** New keys and an ES256 signing key confirmed live; every consumer listed; the gateway proved to accept the new key | code PR (steps A1 to A6), 24 to 48 h of zero legacy traffic, then disable and revoke |
| 4 | pg_net over-broad grant | **ticket written.** Proved we cannot revoke it ourselves | founder pastes `PG_NET_SUPPORT_TICKET_27_OCT.md` |

Smoke test at the end of the pass (about 15:25 UTC):
- `https://quotesdone.com/` returned 200.
- `www` returned 308, which is the redirect.
- `resilience_ping` returned 200.
- `public_site` returned 405 to a GET, which is expected: it takes POST.
- `/auth/v1/health` returned 401 without an apikey, which is expected.
- Edge-function 5xx per 30 minutes stayed at its earlier level: 2 to 5 per window from 12:00 to 15:00 UTC, against an
  82-error spike at 13:30 that came before this pass began.

---

## 1. SSL enforcement: not enabled

**Read-back of the current state** (`GET /v1/projects/{ref}/ssl-enforcement`):
`{"currentConfig":{"database":false},"appliedSuccessfully":true}`.

**Who connects, and whether they use TLS.** Measured 27 Oct, about 15:15 UTC.

`pg_stat_activity` joined to `pg_stat_ssl`, client backends:

| role | application | from | TLS |
|---|---|---|---|
| `authenticator` (PostgREST) | postgrest | `::1` | TLSv1.3 |
| `postgres` | mgmt-api | `2600:1f18:2a66:6e07:…` (AWS us-east-1, Supabase Management API) | TLSv1.3 |
| `supabase_read_only_user` | mgmt-api | `2600:1f18:2a66:6e06:…` | TLSv1.3 |
| `supabase_storage_admin` | Supabase Storage API | `127.0.0.1` | TLSv1.3 |
| `pgbouncer` | (dedicated pooler) | `127.0.0.1` | TLSv1.3 |
| `supabase_admin` | (blank) | `::1` | TLSv1.3 |
| `supabase_admin` | postgres_exporter | `::1` | **none** |
| `supabase_auth_admin` | (Auth) | `127.0.0.1` | **none** |

Dedicated pooler (PgBouncer) logs, 24 h to 15:16 UTC: every client login was `supabase_storage_admin`, 3,433 of them,
from `2406:da18:243:74xx::` (AWS ap-southeast-1). Each server connection logged `SSL established: TLSv1.3`.

Other places checked:
- **Repository.** No production code opens a Postgres connection. `scripts/apply_sql.mjs` and `scripts/lib/db.mjs`
  go through the Management API (`/v1/projects/{ref}/database/query`), which is HTTPS. The only Postgres driver in
  the tree is `supabase/functions/login_otp/verify_race.check.ts` (`npm:postgres`). It runs only against a throwaway
  local container (`127.0.0.1:55432` in `scripts/ci/local_gate.mjs`).
- **Edge functions.** `SUPABASE_DB_URL` is injected by the platform, but no function reads it (grep over
  `supabase/functions`).
- **Vercel** (`quotesdone-next`, production). The Supabase integration created `POSTGRES_URL`, `POSTGRES_PRISMA_URL`,
  `POSTGRES_URL_NON_POOLING`, `POSTGRES_HOST`, `POSTGRES_USER`, `POSTGRES_PASSWORD` and `POSTGRES_DATABASE`. **The site
  reads none of them.** The only `process.env.*` names in `src/` are `NEXT_PUBLIC_SUPABASE_URL`,
  `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `CRON_SECRET`, `SITE_ERROR_INGEST_SECRET`, `VERCEL_ENV`,
  `NEXT_PUBLIC_VERCEL_ENV`, `VERCEL_DEPLOYMENT_ID` and `NODE_ENV`.
- **Login roles.** No custom login role exists. `cli_login_postgres` expired on 14 Sep 2026.

**Conclusion:** every external client already uses TLS 1.3. The only non-TLS sessions are Supabase's own Auth and
metrics exporter, over loopback.

**Why it was not switched on.** Supabase's documentation for this setting
(<https://supabase.com/docs/guides/platform/ssl-enforcement>) says: *"Applying or updating SSL enforcement triggers a
fast database reboot … larger databases may see a longer interruption"*. Elsewhere on the same page: *"a few minutes of
downtime"*. A database restart drops every connection: PostgREST, Auth, Storage, 54 cron jobs and in-flight edge
functions. That breaks the zero-downtime rule, so it was not applied.

**To finish (needs the founder's OK for a window of a few minutes).** Invitations are held, so the quietest hour is
any time outside 10:00 Dubai, preferably at night.
1. Wait until 0 applies are running. Memory `an-apply-can-lock-sign-in` applies.
2. Enable it:
   `PUT /v1/projects/htdblwldjkcgjvmqkbeh/ssl-enforcement` with `{"requestedConfig":{"database":true}}`.
3. Poll `GET …/ssl-enforcement` until `currentConfig.database=true`, `appliedSuccessfully=true`.
4. Test: a `select 1` through the Management API (TLS client); `pg_stat_ssl` shows every non-loopback client backend
   with `ssl=true`; and the smoke set above, plus a sign-in OTP request on the sandbox account.
5. Roll back: the same `PUT` with `false`. It costs the same restart.

Ticket B below also asks Supabase to confirm that loopback service connections (Auth, exporter) are exempt. All the
signs say they are, but it is not written down.

---

## 2. Network restrictions: not applied

**Read-back of the current state** (`GET /v1/projects/{ref}/network-restrictions`):
`{"entitlement":"allowed","config":{"dbAllowedCidrs":["0.0.0.0/0"],"dbAllowedCidrsV6":["::/0"]},"status":"applied"}`.
That means open to all.

**Legitimate direct clients found outside Supabase: none.** The sources are the same as item 1: the repository, edge
functions, Vercel env, login roles, `pg_stat_activity` and 24 h of PgBouncer logs. Every tool the estate uses goes
through the Management API (`apply_sql.mjs`, `db.mjs`, every check, the Supabase MCP `execute_sql`). Edge functions
and the site use PostgREST over HTTPS, which network restrictions do not cover. The founder's laptop holds no keys
(memory `checkpoint-27-oct-cloud-invitations-held`). It is also not a database client: it was never set up with a
connection string. So a restriction would not lock out any laptop tool.

**Why it was still not applied.** Two Supabase-run clients reach the database from outside the host, over the public
network:

| client | role | from | volume |
|---|---|---|---|
| Supabase Storage → dedicated pooler | `supabase_storage_admin` | `2406:da18:243:7400::/…`, `…:7401`, `…:7402` (AWS ap-southeast-1) | 3,433 logins / 24 h |
| Supabase Management API (our whole toolchain) | `postgres`, `supabase_read_only_user` | `2600:1f18:2a66:6e06::/…`, `…:6e07` (AWS us-east-1) | every check and apply |

Supabase's documentation (<https://supabase.com/docs/guides/platform/network-restrictions>) says restrictions are
*"applied to all database connection routes, whether pooled or direct"*. It does not say whether Supabase's own
Storage and Management API connections are exempt.

- If Storage is not exempt, an allow-list without those ranges breaks every file upload and download for every
  user.
- If the Management API is not exempt, it breaks every apply and check. The restriction could still be lifted again,
  because the setting is changed over the same control plane, but that does not make it zero-downtime.

These AWS ranges are Supabase's infrastructure, not ours. They are not published as stable, so allow-listing them
would be a guess. The brief says: if the client set cannot be established with certainty, do not restrict. It was
not restricted.

Two gaps in the evidence, stated plainly:
- `log_connections` is off on this project (postgres_logs hold no `connection authorized` lines), so a past direct
  connection cannot be listed. The survey covers the live snapshot plus the 24 h PgBouncer log.
- The shared pooler (Supavisor) has no log source on this project.

**To finish:** once Supabase confirms the exemptions (ticket B), apply the minimal set. With no external clients,
that is a single unroutable placeholder. Read it back, then run the smoke set and one Management API `select 1`.

```
POST /v1/projects/htdblwldjkcgjvmqkbeh/network-restrictions/apply
{"dbAllowedCidrs":["127.0.0.1/32"],"dbAllowedCidrsV6":["::1/128"]}
```

Roll back with `{"dbAllowedCidrs":["0.0.0.0/0"],"dbAllowedCidrsV6":["::/0"]}`.

---

## 3. Legacy JWT secret exposure: safe intermediate state

**What the exposure means.** A token that verifies against the leaked HS256 secret is accepted for as long as that
key is trusted. Anyone holding the secret can mint a `service_role` token, which bypasses RLS on every table. Rotation
is finished only when the HS256 key is **revoked**.

**Where it can surface.** `GET /v1/projects/{ref}/postgrest` returns `jwt_secret` alongside `db_schema`. Only
`scripts/checks/anon_cannot_execute_security_definer.test.mjs` reads that endpoint, and it keeps `db_schema` only. A
session that prints that response whole will print the secret. Once the HS256 key is revoked, the secret is inert.

**Current key state** (`GET …/api-keys?reveal=false`, `GET …/config/auth/signing-keys`, 27 Oct). Values were never
printed.

| key | type | state |
|---|---|---|
| `anon` | legacy JWT (HS256) | active |
| `service_role` | legacy JWT (HS256) | active |
| `default` `sb_publishable_1T9I2…` | publishable | active since 6 Jun 2026 |
| `quotesdone2` `sb_publishable_WimJ_…` | publishable, description "gpt test" | active since 29 Jul 2026. Unknown consumer: revoke after the move |
| `default` `sb_secret_…` | secret | active since 6 Jun 2026 |
| `0aa3b3b3-…` | ES256 signing key | **in_use**. User sessions are already ES256 |
| `746f6064-…` | HS256 (the legacy secret) | **previously_used**, so still trusted for verification. This is the exposure |

So the new publishable and secret keys, and the asymmetric signing key, **already exist**, and nothing needed creating.

**Proved: the functions gateway accepts the new key.** A read-only probe called `customer_api` (a `verify_jwt=true`
function) with no session in three ways:
- the legacy anon JWT as apikey and bearer;
- the publishable key as apikey and bearer;
- the publishable key as apikey only.

All three reached the function and got its own `401 {"error":"Not signed in"}`, not a gateway rejection. So the 20
`verify_jwt=true` functions do **not** need their flag changed for the move.

**Every consumer of the legacy keys.** API gateway logs (`edge_logs`), 24 h to 16:00 UTC 27 Oct, grouped by caller.
The HS256 traffic was about 17,700 `service_role` requests and about 390 `anon` requests.

| # | consumer | key | evidence | move to |
|---|---|---|---|---|
| A1 | Browser: the site's Supabase client | legacy anon | `src/lib/supaEnv.ts` reads `NEXT_PUBLIC_SUPABASE_ANON_KEY` and hardcodes the legacy anon JWT as a production fallback | read `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, which already exists in Vercel production, set by the integration. Replace the hardcoded fallback with the publishable key |
| A2 | Vercel cron `/api/resilience-ping` | legacy service_role (Vercel `SUPABASE_SERVICE_ROLE_KEY`) | `node` from AWS N. Virginia, about 4 per hour, on `/rest/v1/edge_health_probe`. Relayed into `resilience_ping`, whose `tickCaller` replays it against `/rest/v1/app_secrets` (the `Deno/2.1.4 SupabaseEdgeRuntime` HS256 rows) | read `SUPABASE_SECRET_KEY`, which already exists in Vercel. `tickCaller` already accepts either format. Update `SITE_ENV_NAMES` in `resilience_ping` |
| A3 | `supabase/functions/stripe_setup_page/index.ts` | legacy anon, hardcoded | source | publishable key |
| A4 | `app_secrets.anon_key` | legacy anon | read by `fn_lead_sourcing_kick()` (cron 396 `lead_sourcing_batch`) | publishable value, set by the same PR's SQL and read back |
| A5 | 22 repo scripts that fetch keys from `…/api-keys?reveal=true` and pick `name === 'service_role'` / `'anon'` | both legacy | `node` from Google LLC since 05:00 UTC and `Deno/2.9.4` from Anthropic, PBC. These are the cloud sessions, about 15,000 requests a day | select `type === 'secret'` / `type === 'publishable'`. Files: `scripts/staging/{journey_test,smoke_staging,prove_quote_builder,prove_supplier_onboard,prove_supplier_opportunities,prove_catalog_ingest,sync_staging_assets,verify_cost}.mjs`, `scripts/lib/demo_factory.mjs`, `scripts/expense_documents_backfill.mjs`, `scripts/deploy_functions.mjs`, `scripts/marketing/{ingest_post,business_development,load_calendar}.mjs`, `scripts/media/measure_marketing_assets.mjs`, `scripts/cad_read_worker.ts`, `scripts/it/dropbox_tree_repair.ts`, `scripts/eval/{seat_exam_llm_on,seat_exam_through_think}.ts`, `scripts/checks/{every_expense_record_can_be_opened,a_phone_cannot_select_an_account}.test.mjs` |
| A6 | Vercel `SUPABASE_JWT_SECRET` (integration-managed) | the leaked secret itself | env listing. The site never reads it | becomes inert at step C. Delete it, or disconnect the integration's DB vars, afterwards |
| — | A UAE client (`node`, du ISP) | legacy service_role | 26 Oct 19:00 to 27 Oct 05:00 UTC, mostly `/storage/v1/object`. **Nothing since 05:00 UTC.** This fits the laptop's move to the cloud this morning | nothing, if it stays silent. If it reappears, it is a client still holding the old key |
| ok | Edge-function runtime | already new keys | `/v1/projects/{ref}/secrets`: the injected `SUPABASE_ANON_KEY` digest equals `sb_publishable default`, and `SUPABASE_SERVICE_ROLE_KEY` equals `sb_secret default` (sha256 compared in memory; values never printed) | nothing |
| ok | Database: Vault, cron commands, routine bodies | none | 0 legacy keys in `vault.decrypted_secrets`, 0 in `cron.job.command`, 0 in `pg_proc.prosrc` | nothing |

**Why it stopped here.** A1 to A5 are code changes on the live site, an edge function, a stored secret and 22
scripts. They need the independent review this repository requires before any merge, and a deploy. The legacy key
can only be revoked after the logs show zero HS256 traffic for a full day, so revoking today is not possible without
breaking A1, A2 and A5. Nothing was half-moved. Moving one consumer would not have allowed revocation today, and each
move is a production change that is better verified together.

**Remaining steps, in order:**
1. **Step A: one PR (it_engineer), changes A1 to A5.**
   - Every read of a new key falls back to the legacy one for the transition, so the deploy is zero-downtime.
   - Prove it before merge: a sandbox journey with the publishable key (sign-in OTP, `/me` overview, contact form,
     the site chat), the resilience-ping cron returning 200, and one `fn_lead_sourcing_kick` run in a quiet hour.
2. **Step B: watch for 24 to 48 h** until this logs query returns 0 rows outside Supabase's own `/admin/v1/*` paths:
   ```sql
   select log_attributes['request.cf.asOrganization'] org, log_attributes['request.path'] p, count() n
   from logs where source = 'edge_logs'
     and (log_attributes['request.sb.jwt.apikey.payload.algorithm'] = 'HS256'
       or log_attributes['request.sb.jwt.authorization.payload.algorithm'] = 'HS256')
     and log_attributes['request.path'] not like '/admin/%'
   group by org, p order by n desc
   ```
3. **Step C1: disable the legacy API keys.** `PUT /v1/projects/{ref}/api-keys/legacy?enabled=false`. Read back with
   `GET …/api-keys/legacy`, then run the smoke set. **This step is reversible** (`enabled=true`), so it is the safe test
   that nothing still needs the legacy keys. Leave it a day.
4. **Step C2: revoke the HS256 signing key** `746f6064-…`, the leaked secret. Move it to `revoked` through the
   signing-keys endpoint (`PATCH …/config/auth/signing-keys/746f6064-…` with `{"status":"revoked"}`). Read back with
   `GET …/config/auth/signing-keys`, then run the smoke set. After it, a token minted with the leaked secret is
   refused. Supabase requires C1 before C2. Per Supabase's signing-keys guide, a revoked key can be moved back to
   standby, and only *deletion* is permanent. So C2 is reversible too, but reversing it would re-open the
   exposure. State changes are throttled about 5 minutes apart.
5. **Step D: tidy up.** Delete Vercel `SUPABASE_JWT_SECRET`, the unused `POSTGRES_*` vars and the unexplained
   `quotesdone2` publishable key ("gpt test", 29 Jul). Re-run `security_advisors_match_the_baseline.mjs`.

No user is signed out by C2: user sessions are already signed with ES256. The logs show `ES256 authenticated` on
every signed-in request, and 0 `HS256 authenticated` rows in the 24 h.

---

## 4. pg_net grant: we cannot revoke it ourselves, ticket written

Measured, and proved with a rolled-back probe:
- All 12 `net` functions have a NULL ACL, which is EXECUTE to PUBLIC.
- `net.http_request_queue` and `net._http_response` grant ALL to PUBLIC.
- The sequence grants `rwU` to PUBLIC.
- Schema `net` grants USAGE to PUBLIC, `anon` and `authenticated`.
- The owner is `supabase_admin`.

A revoke issued as `postgres` raises no error and changes nothing, because `postgres` is not a member of
`supabase_admin`. The event trigger `issue_pg_net_access` re-grants USAGE to `anon` and `authenticated` on any
pg_net DDL, so dropping and re-creating the extension ourselves would not hold either.

The ticket text, with the exact SQL for support to run as `supabase_admin` and the verification query, is in
**`docs/reports/security/PG_NET_SUPPORT_TICKET_27_OCT.md`**.

It is not reachable today: `net` is not served by PostgREST, and no client-executable invoker routine touches it.
Both conditions are asserted on every gate run by `scripts/checks/anon_cannot_execute_security_definer.test.mjs`.

---

## Ticket B: questions for Supabase, to unblock items 1 and 2 (paste as a second ticket)

**Subject:** Network restrictions and SSL enforcement: are Supabase's own Storage and Management API connections exempt? (project htdblwldjkcgjvmqkbeh)

Hello Supabase team,

On project **htdblwldjkcgjvmqkbeh** (ap-southeast-1) we want to enable SSL enforcement and network restrictions
with a minimal allow-list. We have no database clients of our own outside your platform: everything goes through
PostgREST, edge functions and the Management API. Before applying, we need to be sure we will not cut off your own
services. We observe these connections from outside the database host:

1. `supabase_storage_admin` logs into the dedicated pooler (PgBouncer) from `2406:da18:243:7400::/…`, `…:7401` and
   `…:7402` (about 3,400 logins a day).
2. The Management API's `database/query` endpoint connects as `postgres` and `supabase_read_only_user`
   (application_name `mgmt-api`) from `2600:1f18:2a66:6e06::/…` and `…:6e07`.
3. Supabase Auth (`supabase_auth_admin`) and `postgres_exporter` connect over loopback without SSL.

Questions:
- With network restrictions set to `dbAllowedCidrs: ["127.0.0.1/32"], dbAllowedCidrsV6: ["::1/128"]`, do (1) and (2)
  keep working, along with the dashboard SQL editor, pg_cron, Realtime and Auth? Or must we allow-list ranges, and if
  so which ones and are they stable?
- With SSL enforcement on, are the loopback connections in (3) exempt?
- How long is the restart that enabling SSL enforcement causes, on our compute size? Is there any way to apply it
  without a restart, or during a maintenance window you schedule?

Thank you.
