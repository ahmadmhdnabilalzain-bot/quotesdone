# Pre-launch security audit, 27 Oct 2026

**Seat:** it_engineer. **Mandate:** founder ledger 1143, *"once we live, you need to make a deep security audit. if i ever
get hacked or someone stole my data, thats purely on you."* This is the pre-launch subset. The deep audit after launch is
listed at the end.

**Method:** read-only on production `htdblwldjkcgjvmqkbeh`. Sources were catalogue queries (`has_*_privilege`, `pg_policy`,
`pg_proc`, `storage.*`), the Management API (`/advisors/security`, `/postgrest`, `/config/auth`, `/functions`,
`/network-restrictions`, `/ssl-enforcement`) and public GETs of public-bucket objects. Every write was proved inside an
aborted transaction (a DO block ending in `raise exception`), so nothing was committed. Repository: `npm audit`, a grep for
secrets over tracked files, a review of the edge functions' auth gates, and the workflows. Nothing was applied, deployed or
rotated, and `app_secrets` was not touched.

## Summary

| severity | count | fixed in this PR | left open |
|---|---:|---|---|
| Critical | 0 | | |
| High | 0 | | |
| Medium | 3 | M1 guarded, M2 fixed (SQL pending at merge) | M1 residual, M3 |
| Low | 6 | L1 fixed | L2 to L6 |

Nothing found needs action before this PR merges.

## The four earlier security PRs

The brief said #1505 and #1507 were closed unmerged and never integrated. **Measured on `origin/main` (679bf9e), all four
are in main.** Each was closed as carried by an integration PR, and the code was read on main to confirm it:

| PR | subject | how it reached main | verified on main |
|---|---|---|---|
| #1459 | workflow hardening (Aikido) | #1578 (29345a7) | `persist-credentials`, `permissions: {}`, inputs passed through `env:`, setup-deno/setup-cli pinned |
| #1505 | sender never adds a PostgREST filter (CWE-943) | #1496 (129a2b9) | `_shared/or_filter_email.ts`; guarded calls at `resend_inbound:734` and `inbound_email:97`; test present |
| #1506 | safeFetch checks every redirect hop (CWE-918) | #1578 (29345a7) | `_shared/safe_url.ts:116-129` follows redirects manually, max 5 hops; `safe_url.test.ts` present |
| #1507 | a session in the URL is never adopted (CWE-384) | #1496 (129a2b9) | `src/lib/authFragment.ts` strips the fragment and returns null; test present |

Nothing needed porting. Every other `.or()` that interpolates a value was checked as well: `messages_api:90,334`,
`customer_api:771` and `sales_engineer:1011` are each guarded by a strict shape check or by stripping characters. #1482
(CSP nonce) is on hold by the founder and was not touched.

## Findings

### M1 — pg_net is executable by anon and authenticated (Medium; guarded, residual open)

`net.http_post`, `net.http_get` and `net.http_delete` are executable by `anon` and `authenticated`. Both roles also hold
SELECT/INSERT on `net.http_request_queue` and `net._http_response`. That is pg_net's default ACL. These objects belong to
`supabase_admin`. **A revoke issued as `postgres` does nothing:** it was proved in an aborted transaction, and every
privilege was still true afterwards. Anyone who could reach these objects could make the database send HTTP requests
from inside Supabase (SSRF), and could read the responses of the estate's own internal calls.

Two things keep it unreachable today, and both were measured:
- PostgREST exposes only `public,graphql_public`. `net` is not served.
- No SECURITY INVOKER routine that a client role can execute references `net.*`. All 10 routines that call
  `net.http_*` are SECURITY DEFINER, owned by `postgres`.

**Fix in this PR:** both conditions are now asserted in
`scripts/checks/anon_cannot_execute_security_definer.test.mjs` (gate step `anon-definer`, kernel gate, no skip). The
PostgREST read keeps only `db_schema`; the same response carries the JWT secret, which the check never prints.
**Residual:** the grant itself. Removing it needs `supabase_admin` (a Supabase support ticket), or moving the outbound
calls to edge functions and dropping pg_net. Post-launch item 1.

### M2 — 99 sequences and 8 table privileges for the internet roles (Medium; fixed, applies at merge)

Every one of the 99 sequences in `public` grants USAGE, SELECT and UPDATE to both `anon` and `authenticated`. UPDATE
means `setval()`: rewinding `leads_id_seq` would make every later insert collide. Separately, `templates`, `undo_log`,
`legal_documents` and `category_specs` grant TRIGGER, and `category_specs` also grants REFERENCES and MAINTAIN. Neither
role inserts anywhere (asserted), so none of these grants has a use. None is reachable over REST today, so this is
defence in depth.

**Fix:** `scripts/sql/the_internet_roles_hold_no_sequence_and_no_table_maintenance_grant.sql`, with a pending note. Proved
on production in an aborted transaction: sequences went from 99 to 0 for each role, the table privileges from 8 to 0, the
SELECT grants the public site uses were unchanged, service_role kept its sequences, and the file's own verdict query
returned `PROBE OK`. **Prevented by:** two new tests in `anon_cannot_execute_security_definer.test.mjs`. While the file is
pending, a grant passes only if the file would remove it; after the apply the floor is zero. A break-test with the
pending note removed made both tests fail against the current production grants.

### M3 — direct Postgres connections are open to any IP, with SSL not enforced (Medium; open)

`/network-restrictions` allows `0.0.0.0/0` and `::/0`, and `/ssl-enforcement` reports `database: false`. The direct
connection still needs the database password, so this is exposure rather than a hole. **Not changed:** this is a
production setting, and restricting it could cut off a tool that connects directly. Before launch, first measure which
clients use a direct connection string (edge functions use the REST/service client; the scripts use the Management API).
Then enable SSL enforcement and restrict the CIDRs to those clients. The release operator can do this as one reversible
dashboard change.

### L1 — third-party actions on mutable tags, in a job that holds the account token (Low; fixed)

`seat-exam-and-gap-audit.yml` ran `denoland/setup-deno@v2` and `anthropics/claude-code-action@v1` (twice). That job
writes the account-wide `SUPABASE_ACCESS_TOKEN` to disk and holds `contents: write`. #1459 had pinned the other workflows,
but this file was added later. The severity is Low only because Actions has been off since 26 Oct (ledger 1279) and the
job runs on dispatch only. **Fix:** both actions are pinned to the commits their tags point at today (setup-deno v2.0.5
`22d081ff…`, claude-code-action v1.0.263 `8041f1d1…`), so behaviour is unchanged. **Prevented by:**
`scripts/checks/every_third_party_action_is_pinned_to_a_commit.test.mjs`. Run against main's version of the file, it
reports exactly those three lines.

### L2 — stale admin and CRM pages in the public `site` bucket (Low; open)

The public `site` bucket still serves pages last updated in June and July: `admin/index.html` ("QuotesDone · Admin"),
`os/app.html` ("QuotesDone CRM"), `app/index.html` and others. They contain no secret; a grep for key, token and
service-role patterns found none. They call `admin_api`, `dispute_api` and `inquiry_ai`, none of which is deployed. They
are an old surface that someone could use for phishing, and they show internal structure. **Recommendation:** delete
`site/admin/*` and `site/os/*`, and the bucket too if nothing serves from it. That is a destructive production change,
so it is left to the release operator.

### L3 — self-service sign-up is open at the auth layer (Low; needs measurement)

`disable_signup=false`, email provider on, captcha off, and the email-send rate limit is 30/h. The product signs in only
through `login_otp`, which uses the admin `generateLink`. GoTrue's own `/auth/v1/otp` and `/signup` may therefore be
reachable with the public anon key, letting anyone create users and send mail from the project. **Not changed**, because
switching signups off might also refuse `generateLink` for a first-time user. This needs a sandbox test with a ZZ DEMO
address before the setting is changed.

### L4 — legacy JWT secret (Low; open, founder's decision)

The project signs JWTs with the legacy shared HS256 secret, and the Management API returns it in `/postgrest`.
**Disclosure:** this audit's first read of `/postgrest` printed that response, secret included, into this session's
tool output once. It was not written to any file, commit, PR or report. The secret is reachable by anyone holding the
management token, which is the same trust as before. No key was rotated, because rotating the secret signs every user out
and invalidates the anon key now in the site. **Recommendation:** after launch, move to Supabase's asymmetric JWT signing
keys and the publishable/secret API keys, then retire the legacy secret.

### L5 — inbound_email compares its webhook secret with `!==` (Low; open)

`supabase/functions/inbound_email/index.ts:51` is not constant-time. A remote timing attack on a JS string comparison
behind the edge gateway is not practical, so this is hygiene. Two copies of a constant-time `sameString` already exist
(`_shared/oauth_connect.ts`, `_shared/marketing_social_oauth.ts`). The fix is to move one into a neutral
`_shared/` module and use it here, rather than add a third copy. Post-launch item 4.

### L6 — extensions in `public` (Low; in the baseline)

`vector`, `pg_net` and `pg_trgm` live in `public`. These are advisor WARN findings and already in the baseline. Moving
`vector` touches every embedding column and index, so it is a post-launch change.

## Verified clean (measured 27 Oct)

- **RLS:** all 744 tables in `public` have RLS on, with 0 off. 434 have no policy, which means deny-all and service-role
  only; the advisor reports these as INFO and they are in the baseline.
- **anon** can SELECT exactly `blog_posts` (policy `published = true`) and `category_specs`. It can write nothing.
- **authenticated** can SELECT 6 tables, each behind a per-user policy: `documents` through
  `fn_customer_document_refs()`, the `quote_review*` tables through the JWT email, and `customer_spec_guide` where
  published. It can write nothing.
- **SECURITY DEFINER:** 1,618 routines. All have a pinned `search_path`, and 0 functions in `public` of any kind lack one.
  0 are anon-executable. 6 are authenticated-executable, each reviewed and pinned by name: the customer-document pair and
  the 4 PDPL self-service routines, which derive the caller's address from `fn_pdpl_my_verified_email()`.
- **Views:** 0 definer views are readable by anon or authenticated.
- **Storage:** RLS is on for `storage.objects` and `storage.buckets` with 0 policies, so only the service role or a signed
  URL can read. **`evidence` is private.** The public buckets (`site`, `brand`, `demo-assets`, `social-media`,
  `ml-models`) hold only brand, marketing and model files, apart from L2.
- **Realtime:** `leads`, `customers`, `transactions`, `expenses`, `gl_journal` and others are in `supabase_realtime`, but
  postgres_changes delivers only what the subscriber's role can SELECT, which for anon and authenticated is none of them.
- **Advisors:** `security_advisors_match_the_baseline.mjs` reports 493 findings (484 INFO
  `rls_enabled_no_policy`, 6 WARN authenticated definer, 3 WARN extension_in_public), **0 NEW**, exit 0.
- **Edge functions:** 78 deployed. The live `verify_jwt` flag matches `supabase/config.toml` for every one. All 58 with
  `verify_jwt=false` have their own gate: `requireInternal` (shared secret) on the internal ones; a user JWT through
  `auth.getUser` (`customer_portal`, `customer_documents`, `stripe_*`, `refund_flow`, `transcribe`, `reveal_invoice`); a
  provider signature (`stripe_webhook`, `resend_*`, Twilio `wa_*`/`sms_inbound`/`voice_otp_capture`, Meta
  `marketing_social_inbox`); an unguessable single-use token or HMAC link (`claim_lookup`, `supplier_ack`,
  `customer_followup`, `unsubscribe`, `oauth_connect`, `marketing_social_connect`); or they are public by design and rate
  limited (`login_otp`, `role_guard`, `complaint_status`, `public_site`, `site_error_ingest`). `stripe_setup` (key entry) is
  `verify_jwt=true`, token-gated with a lockout, and has no CORS.
- **Secrets in code:** no live key pattern in tracked files (Stripe, Supabase PAT, OpenRouter, Anthropic, AWS, GitHub,
  Slack, Resend, webhook, PEM). The JWTs committed in `src/lib/supaEnv.ts`, `stripe_setup_page` and the knowledge seed
  decode to `role: anon`, which is the public key by design. The only `sk_live_` is the fixture `sk_live_ZZDEMOlive`.
- **Dependencies:** `npm audit --omit=dev`: 0 vulnerabilities at any level.

## Post-launch deep audit (what this pass did not cover)

1. Remove pg_net's grant to anon/authenticated through Supabase support, or move outbound calls to edge functions and drop
   the extension (M1 residual).
2. Network restrictions and SSL enforcement, after measuring which clients connect directly (M3).
3. Auth hardening in the sandbox: whether signups can be off with `generateLink` still working; captcha on the OTP
   paths; session timebox and inactivity timeout; JWT signing-key migration (L3, L4).
4. A line-by-line review of each of the 58 self-gated edge functions: replay windows on the webhook signatures,
   constant-time comparisons (L5), a full CORS origin list, rate limits under a burst, error bodies that leak detail.
5. Authorization tests of every action in `customer_api`, `supplier_api` and `messages_api` as a second ZZ DEMO user
   (IDOR across customers and suppliers), driven by the role, not by reading the code.
6. The 110 anon-executable SECURITY INVOKER routines and 149 extension routines: bounded today by the two-table read set,
   but each is a DoS surface (an expensive call by an unauthenticated caller).
7. Storage: signed-URL lifetimes, upload content-type and size enforcement per bucket, and deleting the stale `site`
   pages (L2).
8. Frontend: the CSP (#1482, on hold by the founder), the remaining security headers, and third-party scripts.
9. Secrets lifecycle: which `app_secrets` keys are past rotation, and who can read `app_secrets` (service role only:
   verify that every reader is an edge function).
10. GitHub: branch protection, the token scopes of the bot account, and secret scanning on history, not only on HEAD.
