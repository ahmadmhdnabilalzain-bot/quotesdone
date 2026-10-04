# Rotating the third-party keys

Owner: it_engineer (watches the ages and verifies each key after a rotation). The rotation itself is
the founder's: it happens in each provider's dashboard, and no seat enters a key into a dashboard.
This file holds no values.

**Founder ruling 1090 (30 Sep 2026).** Only credentials the company rotates through a provider API are
rotated (today: the Twilio API key, `fn_it_provider_rotation_*`). Every credential that needs the founder
(Meta, an OAuth sign-in, a console-only key) is classed `founder_required` in `public.it_credential_class`
and is **ignored**: no rotation attempt, no reminder, no renewal handoff, no digest line, no email or
WhatsApp to him. The IT engineer still records its state and any real outage as its own finding.
Guarded by `scripts/checks/a_credential_only_the_founder_can_renew_is_never_rotated_or_reminded.test.mjs`.

## Internal and third-party keys

**Internal credentials rotate themselves.** These are the `internal_credential` rows whose secrets live
in `app_secrets.cred_*`. IT duty 15 (`fn_it_credential_rotate`, which runs inside the daily 'rotation'
duty of `fn_it_duties_scheduled`) rotates any credential older than 90 days, up to 3 a day. The old
secret stays valid for the 24-hour overlap plus two cadences of the duty. It is retired only after it
has gone quiet. See `scripts/sql/a_rotated_credential_stays_valid_until_the_run_that_retires_it.sql`.
Measured 15 Sep 2026: the oldest active credential was created 3 Aug 2026, so the first rotations fall
due around 1 Nov 2026.

**Third-party keys are minted by a provider.** Only the founder can replace them. The estate can
remember when each one is due:

- Each key below is a `key:<app_secrets key>` row of `public.it_expiry` (kind `token`).
- Its date is **one year after its current value was first seen**. For a key already stored when the
  row was created, that is `app_secrets.updated_at`, the best evidence there is.
- The daily rotation duty refreshes the ages (`fn_it_key_age_refresh`). It recognises a value by a
  keyed hash, so a rewrite of the same value does not count as a rotation.
- 30 days before that date, `fn_it_renewal_watch` opens a `renewal.due` handoff to the accountant and
  records a finding. If the handoff is not closed, it escalates to the ceo.
- When a rotated value is stored, the date moves and the watch closes its own handoff.

## The keys

"Last written" is the date of `app_secrets.updated_at` on 15 Sep 2026. It is when the row was last
written, which is not necessarily when the provider minted the key. "Used by" is from the repository
at 4cf0cd2 (`supabase/functions`, excluding `dropbox_backup`, which is being rebuilt).

| app_secrets key | Last written | First reminder (≈) | Used by |
|---|---|---|---|
| `openrouter_api_key` | 2026-06-08 | 2027-05-09 | ai_gateway, resilience_ping (health) |
| `stripe_secret_key` (live) | 2026-06-30 | 2027-05-31 | stripe_setup, stripe_webhook, supplier_pay, reveal_invoice, accountant, _shared/stripe_refund, _shared/demo_identity, IT duty readings |
| `stripe_webhook_secret` (live) | 2026-06-30 | 2027-05-31 | stripe_webhook (signature check); stripe_setup writes it |
| `resend_api_key` | 2026-06-10 | 2027-05-11 | send_outbox, resend_inbound, conversation_archive, email_cron, kyc, login_otp, accountant, IT duty readings |
| `resend_webhook_signing_secret` | 2026-07-19 | 2027-06-19 | resend_webhook |
| `resend_inbound_signing_secret` | 2026-07-19 | 2027-06-19 | resend_inbound |
| `github_token` | 2026-09-14 | 2027-08-15 | IT duty readings (patch and change verdicts, access review) |
| `vercel_token` | 2026-06-19 | 2027-05-20 | resilience_ping, IT duty readings |
| `dropbox_app_secret`, `dropbox_refresh_token` (with `dropbox_app_key`) | 2026-07-03 | 2027-06-03 | compliance_archive, dropbox_backup, IT duty readings |
| `twilio_api_key_secret` (with `twilio_api_key_sid`) | 2026-06-25 | 2027-05-26 | wa_inbound, send_whatsapp, send_sms, mobile_otp, login_otp, kyc, wa_templates_watch, wa_template_setup, IT duty readings |
| `twilio_auth_token` | 2026-09-07 | 2027-08-08 | wa_inbound (checks Twilio's webhook signature) |

**Not tracked by the reminder:** `SUPABASE_ACCESS_TOKEN`, a GitHub Actions secret used by the deploy,
smoke and weekly-readings workflows. It is not in `app_secrets`, so its age cannot be read from the
database. Rotate it on the same yearly rhythm.

**OpenRouter is on hold** (the founder's standing limit). Rotating its key is not spending, but leave
its limits as they are.

## Rotation steps for the founder

All the functions read these keys from `app_secrets` on every call, so storing the new value moves
every caller at once. There is no redeploy.

The general pattern:

1. Mint the new key in the provider's dashboard.
2. Store it in the Supabase SQL editor:
   ```sql
   update app_secrets set value = '<new>', updated_at = now() where key = '<key>';
   ```
3. Wait for the next hourly IT duty. It checks each provider key with a live call and raises a finding
   if the key fails.
4. Only then revoke the old key in the dashboard.

Provider-specific steps:

- **OpenRouter:** go to Keys, create a key, store it in `openrouter_api_key`, then delete the old key
  once `ai_gateway` has answered with the new one.
- **Stripe secret key (live):** go to Developers, then API keys, and use **Roll key**. Stripe lets the
  old key stay valid for a period you choose. Pick at least a day, then store the new key in
  `stripe_secret_key`.
- **Stripe webhook secret (live):** go to Developers, then Webhooks, open the endpoint and use
  **Roll secret** with an expiry for the old secret. Store the new secret in `stripe_webhook_secret`
  before the old one expires, or Stripe events will fail signature checks.
- **Resend API key:** go to API Keys, create a key with the same permission, store it in
  `resend_api_key`, check that the outbox sends, then delete the old key.
- **Resend webhook and inbound signing secrets:** each belongs to one webhook endpoint. If the
  endpoint page offers no way to roll its secret, create a new endpoint to the same URL and store its
  secret (`resend_webhook_signing_secret` or `resend_inbound_signing_secret`). Only then delete the
  old endpoint. Until the secret is stored, the old endpoint's deliveries fail verification.
- **GitHub token:** create a new fine-grained token with the same repository and permissions and a
  one-year expiry, so its expiry matches the reminder. Store it in `github_token`, then revoke the old
  token.
- **Vercel token:** go to Account Settings, then Tokens, and create one scoped to the team with a
  one-year expiry. Store it in `vercel_token`, then delete the old token.
- **Dropbox:** in the App Console, regenerate the app secret. Then run the app's OAuth flow once to
  get a new refresh token, and store both (`dropbox_app_secret`, `dropbox_refresh_token`). The
  refresh token is tied to the app key and secret, so store both together.
- **Twilio API key:** go to Account, then API keys, and create a key. Store its SID and secret
  (`twilio_api_key_sid`, `twilio_api_key_secret`) in one statement, confirm that an OTP and a
  WhatsApp message send, then delete the old key.
- **Twilio auth token:** in Console, then Auth tokens, create a secondary token, store it in
  `twilio_auth_token`, then promote it to primary. Twilio signs inbound webhooks with the primary
  token, so `wa_inbound` must hold the new token before the promotion.

After any rotation, the next daily run records the new first-seen date, and the renewal handoff for
that key closes on its own.
