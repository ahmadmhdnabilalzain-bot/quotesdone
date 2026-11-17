# Security audit, 17 Nov 2026: what an attacker could do today

**Seat:** it_engineer. **Asked by:** the founder, ledger 1143: "a deep security audit; if I ever get hacked or someone
stole my data...". **Code read:** `origin/main` at `09e43394c`. **Branch:** `it_engineer-the-security-audit-of-17-november`.
Nothing was changed, applied or deployed. No production routine was called, and no request was sent to a live function.

**Builds on** `docs/reports/2026-11-10-security-checklist-audit.md`, `docs/reports/security/prelaunch_audit_27_oct.md` and
`SECURITY_HARDENING_27_OCT.md`. This report does not repeat their checklist. It covers what changed since 10 Nov,
measures again the items those reports left open, and ranks what an attacker could actually do.

**Evidence marks.** **FACT/READ** means proved by reading the code at the stated `file:line`. **FACT/SELECT** means proved by
a read-only catalogue or table SELECT on `htdblwldjkcgjvmqkbeh`, done today between 09:00 and 09:40 UTC; only counts and
object names were read, never a person's details. **SUSPECTED** means a code-level reading that this run did not carry
out end to end. **NOT RE-MEASURED** means the item needs a Management API read, which this run was not allowed to make.

## Ranking

| # | impact | finding | evidence | effort to fix |
|---|---|---|---|---|
| 1 | **High.** Takeover of a customer's account and theft of their data | A wildcard in the signed-in e-mail selects another customer | FACT/READ, with the precondition measured by SELECT | S |
| 2 | Low | Stale admin and CRM pages are still public in the `site` bucket (10 Nov open item 4) | FACT/SELECT | S |
| 3 | Low (latent) | 13 sensitive tables are in the Realtime publication, behind admin policies that do not ask for the second factor | FACT/SELECT | S |
| 4 | Low (hygiene) | An anon-executable SECURITY DEFINER routine sits outside `public`, where the gate check does not look | FACT/SELECT | S |
| 5 | Low | Two rate limiters fail open, a counter is read then written, and an unsubscribe token is compared non-constant-time | FACT/READ | S |
| 6 | Low | The retired shared secret is still a row in `app_secrets` and still opens the Resend query gates (a signature is also needed) | FACT/SELECT + READ | S |
| 7 | Residual (known) | pg_net grants to client roles | FACT/SELECT | Supabase support |

No finding lets an anonymous caller read or write data, reveal a supplier without paying, or reach money. **Finding 1 is
the only one that needs action before customers sign up in numbers.**

---

## 1. A wildcard in the signed-in e-mail selects another customer (High)

**Where (FACT/READ).**
- `supabase/functions/sales_engineer/lib/caller.ts:54`: `admin.from('customers').select('id').ilike('email', email).maybeSingle()`.
  Here `email` is the caller's JWT e-mail, passed **unescaped** as a LIKE pattern.
- `supabase/functions/site_assistant/index.ts:175`: the same for `customers`. `:177` does the same for
  `leads.claimed_by`.

In a LIKE pattern, `_` matches any one character and `%` matches any run. Elsewhere the estate escapes the pattern
(`supplier_api/create_company.ts:191` `ilikeExact`, `email_triage/index.ts:72`, `send_outbox/index.ts:184`). These three
lines do not.

**Why the precondition is easy (FACT/READ).**
- Signing in as a *supplier* with any address you control mints a session and creates no customer row.
  `login_otp/index.ts:603-621` inserts into `customers` only when `kind === 'customer'`. For a supplier it only updates
  `leads` where `claimed_by` equals the address.
- The role-conflict check uses an exact `eq` (`login_otp/index.ts:117-121`). A look-alike address therefore passes it.
- **FACT/SELECT:** 20 of the 32 auth users have neither a customer row nor a claimed listing. A JWT with no customer row
  behind it is normal on this system.

**Exploit in one sentence.** Suppose the victim is `john.smith@hotmail.com`. The attacker registers
`john_smith@hotmail.com` (Outlook and Yahoo allow `_`), signs in on the supplier portal, and posts
`{"action":"conversations"}` to `sales_engineer`. `whoami` then resolves the attacker as the victim's customer row.

**What the attacker gets (FACT/READ).**
- `sales_engineer/actions/records.ts:18-31` `conversations`: the victim's whole conversation record through
  `fn_conversation_record`, meaning e-mail, WhatsApp, portal and widget messages. It also includes one-hour signed links
  to the stored PDFs.
- `records.ts:43-51` `report`: the victim's portal report (requests, spend, ratings).
- `records.ts:61` `ask_accountant`: questions about the victim's charges and refunds, in the victim's name.
- `sales_engineer/actions/portal.ts:79,154` `assist`: answers drawn from the victim's own requests and quotes
  (`lib/own_quotes.ts:36`). After a paid reveal, those include the revealed supplier.
- Through the website widget, `site_assistant/index.ts:431` → `after_reveal_door.ts:24` files a complaint, dispute or
  refund claim against the victim's revealed supplier, in the victim's name (`fn_customer_after_reveal_message`,
  `p_customer` = the victim's id). The result is mailed to the victim, so the attacker does not see it. The attacker can
  still raise disputes against a real supplier.

**Conditions.**
- The attacker needs an address at the **same domain** as the victim, where any one or more characters are replaced by
  `_`. A domain name cannot carry a wildcard.
- The attacker must have **no customer row** of their own. With one, two rows match, `maybeSingle` errors, and the
  caller resolves to nobody.
- Realistic cases are free-mail providers that allow `_` in the local part, and a colleague on the same corporate
  domain.

**Exposure today (FACT/SELECT).** There are 4 customer rows. 2 have a `.` or `-` in the local part. 0 of those are at
outlook.com, hotmail.com, live.com, msn.com, yahoo.com, ymail.com or icloud.com. 0 customer e-mails are stored with
capitals. Exposure is small today and grows with every buyer who signs up. The path was **not executed** against
production.

**Smallest fix.**
- `customers.email` is stored lower-case, so use `.eq('email', email)` at `caller.ts:54` and `site_assistant/index.ts:175`.
- Use `.eq('claimed_by', email)` at `site_assistant/index.ts:177`. That matches how `login_otp`, `customer_api`,
  `customer_portal`, `messages_api`, `project_api` and `procurement_api` already resolve the caller (FACT/READ).
- Add a test: a JWT e-mail containing `_` or `%` resolves to no other customer.
- Add a gate check: no `.ilike(` whose value is a caller's e-mail is left unescaped. The remaining unescaped site is
  `inbound_email/index.ts:98`, which is harmless today because profile enrichment was removed (`:133-160`).

## 2. Stale admin and CRM pages are still public (Low)

FACT/SELECT: the public `site` bucket still holds 10 objects last written on 8 Jun, 19 Jun and 7 Jul 2026:

- `admin/index.html`
- `app/index.html`
- `os/app.html`
- `os/os_components.js`
- `os/os_design.css`
- legal and supplier pages

The 27 Oct audit (L2) found no secret in them. They describe internal screens and call functions that are no longer
deployed. **Fix:** delete the `site` bucket's objects, then the bucket. Nothing in `src/` reads it (`/m/brand` proxies
`brand` only).

The other public buckets hold only public material (FACT/SELECT):
- `brand`: 81 objects.
- `social-media`: 34 brand and marketing images.
- `ml-models`: 5 files of a public embedding model.
- `demo-assets`: 1 sample mp3.

Every private bucket stays private. `storage.objects` has RLS on and no policy for any role.

## 3. Sensitive tables in the Realtime publication (Low, latent)

FACT/SELECT: `supabase_realtime` publishes these tables:

- `leads`, `customers`, `inquiries`, `transactions`
- `expenses`, `gl_journal`
- `org_agents`, `workflow`, `risk_register`
- `ai_cost_log`, `vision_horizon`, `edge_health_probe`, `kb_chunks`

Each has an `os_owner_admin_read` policy keyed on `fn_role_of(jwt email)`. That policy does **not** require an `aal2`
session. Nothing leaks today, because `authenticated` holds no SELECT grant on any of them (FACT/SELECT), and Realtime
delivers only what the role can SELECT.

The risk is latent. One future grant would stream customer, supplier and money rows to any session on an admin address,
including a one-factor session, which bypasses the 10 Nov two-step door.

**Fix:** drop these tables from the publication and drop the 13 dead policies. Admin screens read through the
`_shared/admin_session.ts` doors.

Admin second factor today (FACT/SELECT): 2 admin addresses, of which 1 has a verified authenticator factor. The doors
require `aal2` (READ, `_shared/admin_session.ts`), so the address without one cannot act as admin.

## 4. An anon-executable definer routine outside `public` (Low, hygiene)

FACT/SELECT: `holdout_v2.fn_run_pending(integer, integer)` is SECURITY DEFINER, and anon and authenticated may execute
it, through the PUBLIC grant. What stops them is only that neither role has USAGE on schema `holdout_v2`. The routine
inserts and deletes in `public`.

The gate's `anon_cannot_execute_security_definer.test.mjs` asserts only on `public`, so it cannot see this routine.

**Fix:**
- `revoke execute on function holdout_v2.fn_run_pending(integer, integer) from public, anon, authenticated;`
- Widen the check to every non-system schema. Its MANIFEST line and probe follow `quotesdone-apply-discipline`.

## 5. Small authentication weaknesses (Low)

- **Limiters that fail open.** `complaint_status/index.ts:16-17` and `kyc/index.ts:88-89` let the request through when
  `rl_check` errors. Complaint lookups need the ticket number and the e-mail. The kyc limiter guards a signed-in user's
  own address.
- **`kyc` `verify_email` counts wrong guesses with a read, then a write** (`kyc/index.ts:360-368`). Parallel guesses can
  pass the 5-try cap. This is 10 Nov open item 6, still open. Fix: one `UPDATE … SET attempts = attempts + 1 …
  RETURNING`, as `fn_login_otp_email_verify` already does.
- **`unsubscribe` compares its token with `===`** (`unsubscribe/index.ts:43-46`). The token is the first 80 bits of an
  HMAC. A refused call writes `unsubscribe_refusal` with no rate limit in the function; the code says the table throttles
  it. Fix: `sameSecret`.
- **CORS `*`** is set on 15 functions without `siteCors`. These include `site_assistant`, `public_site`, `ceo_agent`,
  `it_engineer` and `marketing`. No function authenticates by cookie, since bearer tokens live in `localStorage`, so this
  is informational.

## 6. The retired shared secret is still live as a query token (Low)

FACT/SELECT: the `legacy.shared` internal credential was retired on 3 Sep 2026, and 85 scoped credentials are live. But
the `inbound_secret` row is still in `app_secrets`, and two places still accept it:

- `resend_inbound/steps/authenticate.ts:14` (`?s=`)
- `resend_webhook/index.ts:75` (`?key=`)

Both also require a valid Svix signature (`authenticate.ts:30-32`), so the token alone is not enough.

**Fix:** confirm in `agent_runs` that no `via: legacy_shared_secret` row has appeared for 7 days. Then drop the
`inbound_secret` comparison from both files and delete the row.

## 7. Known residual: pg_net (no change)

FACT/SELECT: `anon` and `authenticated` hold USAGE on schema `net` and all four privileges on `net.http_request_queue`
and `net._http_response`. Neither role can reach them:

- PostgREST exposes only `public` and `graphql_public` (the gate step).
- `pg_graphql` is **not installed**. The extensions are plpgsql, pg_stat_statements, uuid-ossp, pgcrypto, supabase_vault,
  vector, pg_net, pg_cron and pg_trgm.
- No client-executable routine calls pg_net.

The revoke needs `supabase_admin` (27 Oct M1, support ticket on file).

---

## What was checked and holds

### Edge functions with `verify_jwt = false` (58, from `supabase/config.toml`; READ)

| what authenticates the request | functions |
|---|---|
| Scoped internal credential (`requireInternal` → `fn_internal_auth`, fails closed) | ai_gateway, backup, cad_convert, conversation_archive, doc_extract, drawing_boq, drawing_redact, dropbox_backup, email_cron, email_triage, embed_ml, license_extract, marketing_outreach, quote_extract, sanctions_screen, send_outbox, send_sms, send_whatsapp, wa_template_setup |
| Admin JWT with `aal2`, or an internal credential | compliance_archive, extract_text, pdf_native, refunds_api |
| User JWT (`auth.getUser` / `signedInUser`), scoped to the caller by exact e-mail or id | customer_documents, customer_portal, kyc, my_data_pdf, refund_flow, reveal_invoice, stripe_checkout, stripe_confirm, supplier_pay, transcribe, rfq_flag (forwards to messages_api) |
| Provider signature | stripe_webhook (HMAC-SHA256, 600 s window, `index.ts:183-255`), resend_inbound and resend_webhook (Svix), sms_inbound, wa_inbound, wa_status (Twilio), marketing_social_inbox (Meta `x-hub-signature-256`) |
| Constant-time shared secret | inbound_email (`:56`), site_error_ingest (`:97`), resilience_ping (CRON_SECRET or an internal credential) |
| Unguessable single-use token | customer_followup (UUID), supplier_ack (`sameSecret` + UUIDs), unsubscribe (HMAC, see 5), claim_lookup (UUID claim token; the old numeric id is refused), marketing_social_connect (hashed 40-64 char link token + PKCE + HttpOnly state cookie), oauth_connect (`verifyState`) |
| Public by design, reads no private data | public_site (catalogue, counters, pricing), site_assistant (anonymous voice; signed-in path is finding 1), login_otp, role_guard (constant answer), complaint_status (ticket + e-mail), voice_otp (fixed TwiML), voice_otp_capture (410, disabled), stripe_setup_page (form; `stripe_setup` is token-gated) |

The 20 functions with `verify_jwt = true` include customer_api, supplier_api, messages_api, project_api,
procurement_api, supplier_portal, sales_engineer, quote_compare and it_engineer. Each resolves the caller from the JWT.
Apart from finding 1, each matches the caller exactly (READ: `customer_api/index.ts:95,118`, `customer_portal/index.ts:51-52`,
`project_api/index.ts:16`, `procurement_api/index.ts:33`, `messages_api/index.ts:152,312,322`).

The new supplier-company door (`supplier_api/actions/team.ts`, 16 Nov) scopes every action to the company resolved from
the session, never to an id from the body. Its routines take the signed-in address as the actor (READ).

### Database (FACT/SELECT)

- SECURITY DEFINER in `public`: 0 anon-executable. 6 authenticated-executable, all pinned by the gate:
  - `fn_customer_document_refs`, `fn_customer_documents`
  - `pdpl_request_me`, `pdpl_confirm_me`, `pdpl_cancel_me`, `pdpl_status_me`
- All of these resolve the caller by exact lower-cased JWT e-mail (`fn_pdpl_my_verified_email`, `fn_customer_document_refs`).
- Client-readable tables in `public`:
  - anon: `blog_posts` (published rows), `category_specs`.
  - authenticated: `category_specs`, `customer_spec_guide` (published), `documents` (own refs only; a supplier's quote file
    only after a paid reveal), and `quote_reviews`, `quote_review_messages`, `quote_review_request` (the supplier's own
    rows, by `owner_email`). The `quote_reviews` JSON holds the supplier's own quotation and review only.
- Client-writable tables in `public`: none.
- `app_secrets` and `vault.decrypted_secrets` are not readable by anon or authenticated. Vault holds 0 secrets, and the
  third-party keys are the 288 `app_secrets` rows, readable by the service role only (10 Nov "Secrets management" gap,
  unchanged).

### Money

`stripe_confirm` re-reads the Checkout Session from Stripe, checks that the inquiry belongs to the caller, and records a
reveal only on `payment_status === 'paid'` (`stripe_confirm/index.ts:46-76`, READ). The webhook verifies the signature
before any write (`stripe_webhook/index.ts:227-255`, READ).

### Anonymity before the paid reveal (READ)

- **API responses.** `my_inquiries` returns `supplier_ref: null` and generalised quote text for an unrevealed quote
  (`customer_api/actions/inquiry_lifecycle.ts:338-361`). Suppliers read the inquiry through `inquiries_supplier_safe`
  (`supplier_api/actions/prints.ts`).
- **Files.** The customer cannot download a supplier's own quotation file before paying, by both RLS and the door
  (`customer_documents/index.ts:160-166`). Drawings sent to suppliers lose `/Info`, the trailer `ID` and every XMP
  `/Metadata` (`_shared/pdf_vector_redact.ts:137-144`). Rendered pages are re-encoded with no EXIF or XMP
  (`_shared/drawing_redact_page.ts:171`). Review photos lose EXIF and XMP (`customer_api/review_photos.ts`).
- **E-mail headers.** Every outbound `reply_to` is a platform mailbox (`send_outbox/payload.ts:21`,
  `send_outbox/m365_lane.ts:503-508`). No party's address is placed in a header.
- **The pre-reveal Q&A** (`messages_api` `clarify_*`, `clarify_ask_supplier`) masks both ways through
  `messages_api/strip_contact.ts` and the shared identity scrubbers. That release (#2001) carries its own corpus and the
  480-trial measure. This audit did not run it again (no test suites today), so its result stands as last measured.

### Secrets in the repository (READ)

- A `git grep` over every tracked file for Supabase PATs, `sb_secret_`, Stripe live keys, `whsec_`, AWS, GitHub, Slack,
  Google, Resend and SendGrid keys, JWTs and private-key blocks found only test fixtures (`sk_live_ZZDEMOlive`, a
  generated PEM in `search_console.test.ts`) and the documented all-zero `sbp_` placeholder.
- The only tracked env file is `.env.example`.

### Closed since 10 Nov (READ)

- The supplier "verified phone" mass-assignment (9 Nov H1): `supplier_api/actions/profile.ts:140-142` now clears
  `owner_phone_verified` when the number changes.
- The F2 and F3 path checks are still in place.

### NOT RE-MEASURED

These need the Management API, which this run did not use:

- whether the legacy HS256 signing key is revoked (10 Nov open item 2)
- the session timebox and inactivity settings (open item 5)
- live `verify_jwt` parity with `config.toml`

### The gate already covers (not duplicated here)

- `anon_cannot_execute_security_definer.test.mjs`: definer grants, client table and sequence grants, and exposed schemas.
  `public` only, see finding 4.
- `security_advisors_match_the_baseline.mjs`
- `the_brand_proxy_serves_only_the_brand_bucket.test.mjs`
- `every_admin_door_requires_a_two_step_session.test.mjs`
- `ssrf_guard_refuses_private_addresses.mjs`
- the identity-leak corpus checks

None of them would catch finding 1 or finding 3.

## Order of work

1. **Finding 1:** three one-line `eq` changes, plus the test and the gate check. Deploy `sales_engineer` and
   `site_assistant`.
2. Finding 6, then finding 5's `kyc` counter.
3. Finding 2 (delete the `site` bucket), finding 3 (publication and dead policies), finding 4 (revoke and widen the
   check). Each SQL file gets its MANIFEST line under `quotesdone-apply-discipline`.
