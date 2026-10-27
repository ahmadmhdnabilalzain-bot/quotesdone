---
name: security-hardening-27-oct-state
description: "27 Oct 2026: SSL enforcement, network restrictions, the leaked legacy JWT secret and pg_net. None was applied; why not; the exact next step for each; the legacy-key consumer list and the log query that says when revocation is safe"
metadata:
  node_type: memory
  type: project
  modified: 2026-10-27T15:40:00.000Z
---

Founder, 27 Oct 2026: *"i dont have time to do all these, cant you do them?"* Full evidence is in
`docs/reports/security/SECURITY_HARDENING_27_OCT.md`. The pg_net ticket is in
`docs/reports/security/PG_NET_SUPPORT_TICKET_27_OCT.md`. **Nothing was changed in production in that pass.**

- **SSL enforcement is still off.** Every external Postgres client already uses TLS 1.3. Only Supabase's own Auth
  and exporter use loopback without TLS. Turning it on **restarts the database** (Supabase docs: seconds to minutes),
  which breaks the zero-downtime rule. It needs the founder's OK for a window. Steps and rollback are in the report.
- **Network restrictions are still open (`0.0.0.0/0`, `::/0`).** We have no direct-DB clients of our own: all
  tooling goes through the Management API, and the site and functions use PostgREST. But Supabase Storage logs into
  PgBouncer from `2406:da18:243:74xx::` and the Management API connects from `2600:1f18:2a66:6e0x::`. The docs do not
  say these are exempt, so a restriction could break storage or every apply. Waits for Supabase's answer ("ticket B"
  in the report). `log_connections` is off, so past direct connections cannot be listed.
- **Legacy JWT secret.** The new keys already exist (since 6 Jun):
  - publishable `default`
  - secret `default`
  - ES256 signing key `in_use`

  The HS256 key `746f6064-…` is `previously_used`, which means **still trusted**. That is the exposure.
  - The gateway accepts the publishable key on `verify_jwt=true` functions (proved), so no flag needs changing.
  - Edge runtime and the database already hold only new keys. The exception is `app_secrets.anon_key`, read by
    `fn_lead_sourcing_kick`.
  - Still on legacy keys: the browser (`src/lib/supaEnv.ts` plus the hardcoded fallback), Vercel
    `SUPABASE_SERVICE_ROLE_KEY` (resilience-ping), `stripe_setup_page` (hardcoded), and 22 scripts that pick
    `name === 'service_role'`/`'anon'` from `api-keys?reveal=true`. The scripts are most of the ~17,700 HS256
    calls a day.
  - Order of work: PR moving those consumers (with fallbacks), then 24–48 h of zero HS256 rows in the report's logs
    query, then disable the legacy keys (`PUT …/api-keys/legacy?enabled=false`, reversible), then revoke HS256
    (`PATCH …/config/auth/signing-keys/{id}` with status `revoked`).
- **The secret can leak again from one endpoint.** `GET /v1/projects/{ref}/postgrest` returns `jwt_secret`. Never print
  that response whole. Read only the field you need.
- **pg_net.** Revoking as `postgres` is a silent no-op: the owner is `supabase_admin` and `postgres` is not a member
  (rolled-back probe, 27 Oct). Supabase's event trigger `issue_pg_net_access` re-grants USAGE to anon and
  authenticated on any pg_net DDL. Only support can fix it. The ticket is written; the founder pastes it.

Related: [[checkpoint-27-oct-cloud-invitations-held]], [[an-apply-can-lock-sign-in]], [[supabase-access-has-three-paths]]
