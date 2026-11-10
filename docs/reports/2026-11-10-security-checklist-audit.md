# Security checklist audit, 10 Nov 2026

**Seat:** it_engineer. **Asked by:** the founder, ledger 1605: are these done for our app?
**Branch:** `it_engineer-security-audit-10-nov`. Fixes: commit `cc5a570b5`. Nothing was applied or deployed. No PR was opened.

**Builds on:** `docs/reports/security/prelaunch_audit_27_oct.md`, `docs/reports/security/SECURITY_HARDENING_27_OCT.md`
and `docs/reports/2026-11-09-launch-checklist.md`. Rows those reports measured are measured again here, or the row
says what was not re-measured.

**How each row was measured.** One of these, and the row names which:
- **[code]** a `file:line` read on `origin/main` at `67e7bccdb`, today.
- **[check]** a test or check that enforces it. It was run today and passed, unless the row says otherwise.
- **[live]** a probe of `https://quotesdone.com`, of the 78 edge functions, or a read-only Management API or catalogue
  query against `htdblwldjkcgjvmqkbeh`.

The probes used GET or OPTIONS only, with no credential or an invalid one. Catalogue reads went through `readOnly: true`
statements. No write, load, fuzzing or account action was made, no person was messaged, and no model was called.

Status: **DONE** means in place and enforced. **PARTIAL** means in place with a named gap. **MISSING** means not in
place. **N-A** means it does not apply to this stack. A status marked "(fixed here)" is the status after this branch is
merged and deployed.

## Critical first

**No critical finding.** No exploitable hole was found that would show a supplier before payment, or one party's inquiry
or quote to another. The paywall reads hold. Every quote, inquiry, transaction, project and clarification read by id is
scoped to the caller. Supplier identity fields are returned only when `transactions.revealed_at` is set
(`customer_api/actions/inquiry_lifecycle.ts:295`, `actions/reviews.ts:100,106`). Because nothing was critical, nothing
was escalated mid-run.

Fixed on this branch. Each fix has a test, and each test was run against the old code first and failed there:

| # | finding | severity | fix |
|---|---|---|---|
| F1 | **Brand proxy path traversal.** `next.config.mjs` rewrote `/m/brand/:path*` to the storage host. A `..` segment reached the upstream URL. **[live]** `curl --path-as-is https://quotesdone.com/m/brand/../site/admin/index.html` returned 200 and served the stale "QuotesDone · Admin" page from another bucket. So quotesdone.com proxied any path on the project host. It added no credential, so it gave no privilege, but it is an unvalidated path on our origin. | Medium | The source pattern now accepts only file-name segments, so `.` and `..` cannot match. All 81 `brand` objects fit (counted today). `scripts/checks/the_brand_proxy_serves_only_the_brand_bucket.test.mjs` compiles the rewrite with Next's own matcher. |
| F2 | **Customer drawing-path IDOR (open M1 from 9 Nov).** `create_inquiry` stored `drawing.drawing_file_path` from the request body. `my_inquiries` then signed it back for an hour (`lib/storage.ts:6`). A customer who knew another customer's path could read that customer's original drawing. | Medium (needs a leaked path) | `customer_api/drawing_path.ts` accepts only `drawings/<caller customers.id>/…` with no dot segment. Anything else gets 403 `drawing_not_yours` before the write (`actions/inquiry_create.ts:191-194`, import at `:23`). Test: `customer_api/drawing_path.test.ts`. |
| F3 | **Supplier document-path mass assignment (open M1 from 9 Nov).** `PROFILE_COLS` let `save_profile` write `egr_doc_path` from the body. A supplier could point it at any `supplier-docs` object, another supplier's licence included, and the portal would sign it back. | Medium (needs a leaked path) | `egr_doc_path` is off the allow-list (`supplier_api/lib/fields.ts:13-18`). Only the portal upload writes it, under `certs/<supplier id>/`, and nothing in `src/` sent it. Test: `supplier_api/profile_cols.test.ts`. It fails if any `*_path` column returns to the list, or if the body is spread into the update. |
| F4 | **Chat renderer wrote a link inside a link.** `ChatWidget.render` (also used by the portal assistant through `dangerouslySetInnerHTML`) ran four `replace()` calls over its own output. An e-mail inside a URL put a second `<a href="mailto:…">` inside the first link's `href` and closed it early. A digit run broke the href: `https://a.co/1234567890` became `href="https://a.co/<bdi>…`. No script ran, because the patterns carry only escaped characters. | Low (hardening) | `src/lib/chatRender.ts` matches every span once, in one pass. Both chat surfaces import it. Test: `scripts/checks/the_chat_renderer_never_writes_a_link_inside_a_link.test.mjs`. |
| F5 | **`supplier_ack` compared its token with `!==`** (9 Nov row 40), and it did not validate the `tx` parameter. | Low | Uses `sameSecret` (constant time), and both ids must be UUIDs (`supplier_ack/index.ts:50-55`). Test: `supplier_ack/token.test.ts` drives the real handler against stubbed PostgREST. |

Open, ordered by what to do first. None is critical.

1. **Admin accounts have one factor.** An admin signs in with an e-mail code. After that, `refunds_api:32` and eight
   other functions accept any JWT whose e-mail is in `admin_emails`. Anyone who takes over that mailbox can act as
   admin. Fix: a second factor for owner and admin sessions. This is a design change, not a one-line fix.
   **Built 10 Nov 2026 (it_engineer, branch `it_engineer-admin-two-step-sign-in`, not yet deployed):** TOTP authenticator
   app at `/admin`; the ten JWT admin doors require `aal2` through `_shared/admin_session.ts`. Release and recovery steps:
   [admin-two-step-sign-in.md](../runbooks/admin-two-step-sign-in.md).
2. **The legacy HS256 JWT secret is still trusted.** **[live]** `signing-keys`: HS256 is `previously_used` and ES256
   is `in_use`. The secret leaked (27 Oct item 3). Until it is revoked, anyone holding it can mint a `service_role`
   token. The steps are in `SECURITY_HARDENING_27_OCT.md` §3.
3. **The live site's publishable key is the one the 27 Oct report said to revoke.** **[live]** The JS bundle carries
   `sb_publishable_WimJ_…`. The Management API names that key `quotesdone2`, described "gpt test". Memory
   `quotesdone2-is-the-live-publishable-key.md` already says never to revoke it. But the 27 Oct table still said
   "unknown consumer, revoke after the move", and revoking it would take the site down. That row is corrected on this
   branch (`SECURITY_HARDENING_27_OCT.md` §3). The key's description still reads "gpt test", and changing it is a
   production setting, so it was left as it is.
4. **Stale admin and CRM pages in the public `site` bucket (27 Oct L2).** **[live]** These three return 200 as
   `text/plain`: `storage/v1/object/public/site/admin/index.html`, `os/app.html` and `app/index.html`. Plain text, so
   they do not render, but they are still public. Deleting them is destructive, so it was left to the release operator.
5. **No absolute or idle session limit.** **[live]** auth config: `sessions_timebox: 0` and
   `sessions_inactivity_timeout: 0`. Tokens live in `localStorage`.
6. **`kyc` `verify_email`** counts wrong guesses with a read-then-write, and its limiter fails open
   (`kyc/index.ts:62-64, 317-345`). Impact is low: the caller is already signed in, and the address is their own.

## The checklist

### Injection and code execution

| item | status | evidence | fix / commit |
|---|---|---|---|
| OS command injection (CWE-78) | DONE | [code] 0 `Deno.Command`, `Deno.run`, `child_process`, `spawn` or `execSync` in `supabase/functions` (grep). The one `execFileSync` is `src/app/sitemap.xml/route.ts:1`, which runs at build time with fixed arguments. | — |
| Code injection | DONE | [code] 0 `eval(` and 0 `new Function(` in `supabase/functions`, `_shared/vendor` and `src`. [live] The production CSP has no `'unsafe-eval'`. It has `'wasm-unsafe-eval'` only, for the self-hosted OCR core. | — |
| Command injection (CWE-77) | DONE | [code] No shell anywhere at runtime (see CWE-78). | — |
| SQL injection (CWE-89) | DONE | [code] Edge access goes through the PostgREST builder, which is parameterised. 8 `.or()` filters interpolate a value. Each is a server value, a validated shape, or stripped of filter syntax: `messages_api:88-91`, `inbound_email:102` (`orSafeDomain`), `sales_engineer/actions/operator.ts:514-515`, `customer_api/lib/drawings.ts:256`, `cad_dispatch.ts:28`, `_shared/drawing_pages.ts:97`, `resend_inbound/steps/supplier_docs.ts:31`. [code] In plpgsql, 23 `EXECUTE` statements use `%s` or `\|\|` (mirror scan). All are in SECURITY DEFINER routines. [live] 0 SECURITY DEFINER routines are executable by anon, and the 6 executable by authenticated are not among the 23 (`anon-definer` check, 11/11 pass today). `fn_ceo_directive_*` runs stored SQL text, which is a service-role-only primitive. | — |

### Request handling

| item | status | evidence | fix / commit |
|---|---|---|---|
| SSRF (CWE-918) | DONE | [code] `_shared/safe_url.ts` refuses private and metadata ranges and follows each redirect hop by hand, up to 5. [check] `ssrf_guard_refuses_private_addresses.mjs` (gate step `ssrf`). [live] PostgREST serves only `public,graphql_public`, so pg_net cannot be reached, and no client-executable routine calls it (`anon-definer`). **Residual:** the pg_net grant itself needs `supabase_admin` (27 Oct M1). | — |
| Open redirects | DONE | [code] Stripe return URLs must be on an allowed host (`_shared/site_origins.ts:58-68`). Browser navigations go only to server-returned URLs (`QuoteCard.tsx:99`, `Billing.tsx:56,106`). The two OAuth 302s go to provider URLs built on the server (`oauth_connect:50`, `marketing_social_connect:59`). No `next=` or `return_to` parameter is read. | — |
| Path traversal | DONE (fixed here) | [live] `/m/brand/..` traversal, see F1. [code] Storage paths are built on the server with `safeFilename` and an id prefix (`_shared/attachment.ts:462`). Supplier uploads check `${folder}/${sup.id}/` (`supplier_api/actions/documents.ts:61`). | F1, F2 |
| Mass assignment | DONE (fixed here) | [code] Every write builds an explicit object. `save_profile` copies only `PROFILE_COLS`. `egr_doc_path` left that list, see F3. [check] `profile_cols.test.ts` asserts the body is never spread. | F3 |

### Authorization

| item | status | evidence | fix / commit |
|---|---|---|---|
| Missing or incorrect authorization (CWE-862/863) | DONE (fixed here) | [code] Every id-taking action resolves the caller from the JWT and scopes the read to the owner. In customer_api, 16 sites: for example `inquiry_lifecycle.ts:53,96,381`, `reports.ts:29,59,83,108`, `reveal.ts:22,36`, `reviews.ts:33,57,82,100`, `discovery.ts:29`, `inquiry_create.ts:45`. Also `supplier_api` (`lib/quote_gate.ts:68-74` `matchedInquiry`, `actions/inbox.ts:284`, `actions/quotes.ts:128`), `messages_api:126-166`, `project_api:121,140,166` and `refund_flow:63-72`. | F2 |
| Missing authentication on a critical function (CWE-306) | DONE | [live] 78 functions are deployed: 20 with `verify_jwt=true` and 58 with `false`. 0 differ from `supabase/config.toml`. [live] A GET with an invalid bearer to all 78: every internal, user and webhook function answered 401, 403, 400, 405 or 410. Six answered 200, each public by design: `role_guard` (the same constant answer for every identifier, `role_guard:51,61,71`), `voice_otp` (fixed TwiML, reads and writes nothing), `wa_inbound` (empty TwiML), `resilience_ping` (liveness only), `stripe_setup_page` (a form; its target `stripe_setup` is token-gated with a lockout), and `login_otp` / `claim_lookup` (400). | — |
| Improper authentication (CWE-287) | PARTIAL | [code] User functions resolve the JWT through `signedInUser` or `auth.getUser`. OTP codes are HMAC-hashed (`login_otp:45-48`) and verified atomically by `fn_login_otp_email_verify` [check: gate step `otp-race`]. Internal callers use scoped credentials checked by `fn_internal_auth`. **Gap:** the legacy HS256 secret is still trusted (open item 2). | — |
| Trust boundary violation (CWE-501) | DONE (fixed here) | [code] Identity comes from the JWT, never the body. Redacted drawing pages are resolved from the caller's own run rows (`customer_api/lib/drawings.ts:224-270`). Fees are computed on the server (`_shared/reveal_fee.ts`). Document text is passed to the model as untrusted (`_shared/untrusted.ts`). The two places that took a path from the body are closed (F2, F3). | F2, F3 |
| Improper privilege management (CWE-269) | DONE | [live] `anon-definer` 11/11 pass today: 0 of 1,779 SECURITY DEFINER routines are anon-executable; 6 are authenticated-executable, pinned by name; 0 relations are writable by a client role; 0 maintenance grants; 0 sequence grants. [live] 793 of 793 public tables have RLS on. authenticated can SELECT 6 tables, each behind a per-user policy; anon can SELECT 2 (`blog_posts`, `category_specs`). **Residual:** the pg_net default grant (27 Oct M1). | — |
| IDOR on the customer and supplier APIs (paywall) | DONE (fixed here) | [code] Before a reveal, `my_inquiries` returns `supplier_ref: null`, no `supplier_name`, `emirate` or `win_rate`, and only banded rating and years (`inquiry_lifecycle.ts:295`). `supplier_history` refuses without `revealed_at` (`reviews.ts:100,106`). Unrevealed quote text is generalised (`inquiry_lifecycle.ts:281`). A supplier sees an inquiry only when matched to it (`quote_gate.ts:68`, `quote_review_actions.ts:70-74`). The one same-bucket path IDOR is F2. | F2 |

### Sessions and accounts

| item | status | evidence | fix / commit |
|---|---|---|---|
| Session fixation (CWE-384) | DONE | [code] `src/lib/authFragment.ts:32-39` strips a session from the URL fragment and never adopts it; `detectSessionInUrl: false` (`src/lib/supaClient.ts:34`). [check] `src/lib/authFragment.test.mjs`. | — |
| Session management | PARTIAL | [live] auth config: `jwt_exp 3600` and `refresh_token_rotation_enabled true`, but `sessions_timebox 0` and `sessions_inactivity_timeout 0`. [code] Tokens are kept in `localStorage`. | open item 5 |
| Two-factor authentication (admin MFA) | DONE (built 10 Nov on `it_engineer-admin-two-step-sign-in`; deploy pending) | [code] Before: admins signed in with an e-mail code only, and ten functions accepted a JWT whose e-mail is in `admin_emails`: `refunds_api:32`, `accountant`, `ceo_agent`, `compliance_archive`, `extract_text`, `it_engineer`, `marketing`, `pdf_native`, `quote_compare` and `sales_engineer`. (This row first named `email_triage` and `wa_templates_watch`; both read `admin_emails` only as a recipient list and accept no JWT. It missed `ceo_agent`, `marketing` and `sales_engineer`.) Now: all ten go through `_shared/admin_session.ts`, which also requires `aal: aal2` (an authenticator-app TOTP code; phone MFA is paid and stays off), and an aal1 admin gets 403 `two_step_required` with the step, sent to enrolment at `/admin` when no factor exists. [live] read only: `mfa_totp_enroll_enabled true`, `mfa_totp_verify_enabled true`, `mfa_phone_* false`. [check] `every_admin_door_requires_a_two_step_session.test.mjs`, `<fn>/two_step.test.ts` x10, `_shared/admin_session.test.ts`, `src/lib/adminTwoStep.test.mjs`. Recovery: `docs/runbooks/admin-two-step-sign-in.md`. | open item 1 |
| Brute force protection | DONE | [code] `login_otp`: 5 tries per code (`:30`), verify capped per IP and per e-mail (`:508-509`), and the limiter fails closed (`:88-110`). `stripe_setup` locks out after 10 bad tokens (`stripe_setup/index.ts:56-67`). `role_guard` is capped per IP. **Gap:** `kyc` `verify_email` (open item 6). [live] Captcha is off (`security_captcha_enabled false`). | — |
| Account lockout (OTP limits) | DONE | [code] A code is burned after 5 wrong tries. There are 10 verify attempts per e-mail per hour from any IP. Twilio Verify enforces its own 5. | — |
| Password reset flows | N-A | [live] There are no passwords: `disable_signup: true`, `mailer_autoconfirm: false`. Sign-in is by OTP only. GoTrue's `/recover` and `/otp` stay reachable with the publishable key for an existing user. They were not probed, because a probe would mail a real person. | — |
| Magic links | N-A | [code] `generateLink('magiclink')` runs only on the server, inside `login_otp`, after the code is proven. A session in a URL is refused (`authFragment.ts`). | — |
| SSO | N-A | No identity-provider integration. Buyers and suppliers are SMEs. | — |
| Role-based access control | DONE | [code] Roles are separate identity tables: `customers` by e-mail, and `leads.claimed_by` for suppliers. `login_otp` allows one identity per role. Admin is `admin_emails` / `fn_role_of`. [live] The 13 `os_owner_admin_read` policies cannot fire, because authenticated holds SELECT on none of those tables. | — |
| Row-level security | DONE | [live] 793 of 793 tables have RLS on, and 0 are off. 434 are deny-all (RLS on, no policy). Every `USING (true)` policy is `TO service_role`, apart from `category_specs` (anon read) and `brand_assets`, where anon holds no SELECT grant. `storage.objects` has RLS on and 0 policies. | — |
| API keys | PARTIAL | [live] Only the publishable key ships in the bundle (33 chunks scanned, no secret pattern found). That key is the one the 27 Oct report said to revoke (open item 3). [code] Third-party keys are plaintext rows in `app_secrets`. Internal credentials are stored HMAC-hashed. | open item 3 |
| Token expiration and refresh | DONE | [live] `jwt_exp 3600`, `refresh_token_rotation_enabled true`, `security_refresh_token_reuse_interval 10`. [code] `autoRefreshToken: true` (`supaClient.ts:34`). Internal credentials expire after one year and rotate 30 days ahead. | — |
| Cookie flags (HttpOnly, Secure, SameSite) | DONE | [live] The only site cookie is `NEXT_LOCALE=en; Path=/; SameSite=lax`. It is not sensitive. Auth uses no cookie. [code] The OAuth state cookie is `HttpOnly; Secure; SameSite=Lax` (`oauth_connect/index.ts:40,51`). | — |

### Browser-side protection

| item | status | evidence | fix / commit |
|---|---|---|---|
| Buffer overflow (CWE-120) | N-A | TypeScript and Deno only. The only native-like code is the self-hosted tesseract WASM core (pinned sha256 in `public/ocr/SHA256SUMS`), which runs in the WASM sandbox. | — |
| XSS (CWE-79) | DONE (fixed here) | [code] React escapes by default. `dangerouslySetInnerHTML` is used on committed static content (blog, legal, marketing), on JSON-LD through `ldHtml` (escapes `<`, `src/lib/seo.ts:139`), on the SVG markup (`me/markup.ts`, labels escaped), and on the chat renderer (F4). [live] HTML from edge functions is served `text/plain` with `CSP: default-src 'none'; sandbox`. | F4 |
| CSRF | DONE | [code] Authentication is an `Authorization: Bearer` header, never a cookie. [live] `form-action 'self'`. The OAuth state is an HMAC plus a cookie. | — |
| Content Security Policy | PARTIAL | [live] CSP is present: `default-src 'self'`, `object-src 'none'`, `base-uri 'self'`, `frame-ancestors 'none'`, a closed `connect-src`. **Gap:** `script-src 'unsafe-inline'` (the nonce work in #1482 is on the founder's hold) and the whole of `cdnjs.cloudflare.com`. | — |
| Security headers | DONE | [live] `/`: HSTS `max-age=63072000; includeSubDomains`, `nosniff`, `X-Frame-Options DENY`, `Referrer-Policy strict-origin-when-cross-origin`, `Permissions-Policy` and CSP. Pages also carry `access-control-allow-origin: *` (Vercel), which is harmless because no response depends on a cookie. | — |
| Clickjacking | DONE | [live] `frame-ancestors 'none'` and `X-Frame-Options: DENY` on every path. The edge OAuth pages also send `X-Frame-Options: DENY`. | — |

### Secrets and data protection

| item | status | evidence | fix / commit |
|---|---|---|---|
| Secrets management | PARTIAL | [check] `no_source_file_hardcodes_a_legacy_supabase_key.test.mjs`. [live] The bundle scan found no secret pattern. **Gap:** third-party secrets sit in `public.app_secrets`, which every function can read with the service role. Vault is not used. | — |
| Secret rotation | PARTIAL | [code] Internal credentials rotate automatically (`credential_rotate_daily`), and the Twilio key rotates by API. Other third-party keys get key-age reminders. **Gap:** the HS256 secret is not revoked (open item 2). | — |
| Environment variables | DONE | [code] `src/` reads `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` and `NEXT_PUBLIC_VERCEL_ENV` as public variables, all public by design (`src/lib/supaEnv.ts`). Server-only keys are listed in `.env.example`. No `.env` is in the repository. | — |
| Audit logs | PARTIAL | [code] `security_audit_log`, append-only `internal_credential_audit`, per-function run tables, and the PDPL operator log. **Gap:** no log of who read which customer's PII. | — |
| Encryption at rest | PARTIAL | Supabase encrypts disks and backups (provider statement; not measurable from here). [code] Social OAuth tokens are sealed with AES-GCM (`_shared/marketing_social_oauth.ts:82-86`). **Gap:** `leads.emirates_id`, `trn` and `owner_dob` are plaintext columns. | — |
| Encryption in transit | DONE | [live] `ssl-enforcement {"database":true}`. Network restrictions were applied 9 Nov 23:21 UTC and allow only documentation addresses. HSTS `includeSubDomains`. | — |
| Hashing vs encryption | DONE (fixed here) | [code] OTP codes are HMAC-SHA256 (`login_otp:45`). Internal credentials are hashed (`fn_internal_auth`). Tokens that must be reused are encrypted, not hashed (AES-GCM above). Secret comparisons are constant time (`stripe_setup/webhook_plan.ts:71`, `inbound_email:55`), and `supplier_ack` now is too. | F5 |
| Principle of least privilege | PARTIAL | [live] Client roles can read 2 or 6 tables, write 0, and execute 0 definer routines outside the pinned 6. **Gap:** every edge function holds the service-role key and can read all of `app_secrets`. pg_net grant (27 Oct M1). | — |
| Data validation on the server | DONE | [code] UUID and shape checks on every id. CHECK constraints and raising triggers (`fn_leads_mandatory_six_gate`). The reveal fee is recomputed and cross-checked on the server (`_shared/reveal_fee.ts`, `stripe_checkout`). | — |
| File upload security | PARTIAL | [code] Magic-byte sniffing that refuses HTML and SVG (`_shared/attachment.ts:173,268-274`), plus polyglot and macro checks (`:309,381`), EXIF strip (`:406-436`) and a VirusTotal hash lookup (`_shared/malware.ts:215`). [live] Every bucket a user writes to has a size cap and a MIME list (`drawing-files` and `quote-files` 25 MB, `supplier-docs` 100 MB, `review-photos` 5 MB). Private buckets are read only through the service role or a signed URL. **Gaps:** a missing VirusTotal key records the file as "NOT scanned" instead of holding it (`malware.ts:118`). `evidence`, `reports` and `ml-models` have no limits, but only the service role writes them. Stale `site` pages (open item 4). | — |
| Webhook signature verification | DONE | [code] Stripe: HMAC-SHA256, ±600 s window, constant-time compare (`stripe_webhook/index.ts:11,140-157`). Resend: Svix, timing-safe (`resend_webhook/index.ts:40-53`). Twilio: `x-twilio-signature` (`sms_inbound:147`, `wa_status:109`, `_shared/twilio_inbound_signature.ts:45`). Meta: `x-hub-signature-256` (`marketing_social_inbox:105`). Inbound mail: shared secret, constant time (`inbound_email:55`). [live] Each answered 403 or 405 to an unsigned GET. Twilio signatures carry no timestamp, so replay protection rests on MessageSid dedupe. | — |

### Dependencies

| item | status | evidence | fix / commit |
|---|---|---|---|
| Dependency vulnerabilities | PARTIAL | [check] `npm audit` (all) and `npm audit --omit=dev`: 0 at every level today. Gate step `audit` (`--audit-level=high`) passed. **Gap:** Deno dependencies are outside npm audit. 82 imports float on `jsr:@supabase/supabase-js@2` and `https://esm.sh/@supabase/supabase-js@2`, and the gate runs `--no-lock`. Other esm.sh and deno.land imports are pinned. | — |

### Exposure checks

| item | status | evidence | fix / commit |
|---|---|---|---|
| Source maps off in production | DONE | [live] `<chunk>.js.map` returns 403 for 3 sampled chunks, and 0 `sourceMappingURL` comments were found in them. `productionBrowserSourceMaps` is unset in `next.config.mjs`. | — |
| No .git on the live site | DONE | [live] `/.git/HEAD` and `/.git/config` return 404. | — |
| No .env or backups in /public | DONE | [live] 404 for `/.env`, `.env.local`, `.env.production`, `.env.example`, `/backup.sql`, `/dump.sql`, `/db.sql`, `/.DS_Store`, `/package.json` and `/vercel.json`. [code] `public/` holds brand, fonts and OCR assets only, with no dotfile, `.sql`, `.bak` or `.zip`. | — |
| No secrets in NEXT_PUBLIC_ vars | DONE | [code] The four `NEXT_PUBLIC_` names hold only public values. [live] The bundle scan found only `sb_publishable_…`. | — |
| Debug mode off in production | DONE | [live] There is no `'unsafe-eval'` and no `ws:` in the CSP (both are dev-only). `/_next/webpack-hmr` and `/__nextjs_original-stack-frame` return 404. `/api/health` returns only `ok`, the service name, the time and the deployment id. Some edge 500s echo the exception message (for example `customer_api/index.ts:118`), which is minor. | — |
| No open admin or API docs pages | PARTIAL | [live] 404 for `/admin`, `/wp-admin`, `/swagger`, `/swagger.json`, `/openapi.json`, `/api-docs`, `/api/docs`, `/graphql` and `/phpinfo.php`. `/api/resilience-ping` returns 401 without `CRON_SECRET`. **Gap:** the public `site` bucket still serves "QuotesDone · Admin" and "QuotesDone CRM" pages as `text/plain` (open item 4). Until F1 deploys, those pages are also reachable through quotesdone.com. | F1 |

## Verification on this branch

- New tests, all passing. Each was also run against the original code, where it failed:
  - `supabase/functions/customer_api/drawing_path.test.ts`: 4 tests.
  - `supabase/functions/supplier_api/profile_cols.test.ts`: 2 tests.
  - `supabase/functions/supplier_ack/token.test.ts`: 5 tests.
  - `scripts/checks/the_chat_renderer_never_writes_a_link_inside_a_link.test.mjs`: 6 tests.
  - `scripts/checks/the_brand_proxy_serves_only_the_brand_bucket.test.mjs`: 3 tests.
- Existing checks that read the changed files passed: `the_mandatory_six_have_one_definition`,
  `only_a_readable_uae_authority_is_approved`, `the_portals_are_the_sales_engineer` (including its live part),
  `the_supplier_portal_fixes_of_21_september_stay_fixed`, `the_widget_finds_a_stored_answer_and_redraws_its_history`,
  `every_test_file_is_run`, and the static parts of `arabic_reaches_the_same_answer_as_english`.
- `anon_cannot_execute_security_definer.test.mjs` passed against production (read-only): 11 of 11.
- `npm run gate -- --offline --skip=npm-test`: exit 0. All 14 offline steps passed: ssrf, fetch-timeout, dwg, redact-page, scan-redact, scan-takeoff (passed on the rerun after a memory kill), migration-lint, lint, typecheck, audit, deno-gated, deno-all, otp-race. Production steps were skipped (`--offline`), and `npm-test` was skipped by name.

## To ship

The fixes change the website (F1, F4) and three edge functions: `customer_api` (F2), `supplier_api` (F3) and
`supplier_ack` (F5). After merge, the release operator deploys those three functions (`docs/runbooks/release-without-ci.md`)
and lets Vercel build the site. Then two checks:
- `curl --path-as-is -o /dev/null -w '%{http_code}' https://quotesdone.com/m/brand/../site/admin/index.html` must
  return 404.
- `https://quotesdone.com/m/brand/icon_192.png` must still return 200.

No SQL is involved, so there is no MANIFEST line and no pending note.
