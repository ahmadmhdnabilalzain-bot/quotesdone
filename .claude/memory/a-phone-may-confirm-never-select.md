---
name: a-phone-may-confirm-never-select
description: "Identity rule for QuotesDone — email is unique and is the identity; phone deliberately repeats (UAE shared numbers) so it may confirm an identity, never select one."
metadata: 
  node_type: memory
  type: project
  originSessionId: 4ca61bec-f10b-4b3c-a015-46d98c25918e
  modified: 2026-08-13T21:04:45.985Z
---

Decided and enforced 13 Aug 2026 after /me showed the founder `management@quotesdone.com` for an
account he registered as `djzaino@outlook.com`.

- **Email is the identity.** `customers_email_lower_uidx` and `leads_claimed_by_lower_uidx`, both on
  `lower(btrim(...))` — case variants are the same mailbox and every reader already lowercases.
- **Phone deliberately repeats.** UAE families, colleagues and whole companies share one number;
  this estate holds the founder's office landline on one record and his mobile on another. A unique
  index would lock out real buyers. The reason lives in a `comment on column customers.phone`.
- **Therefore a phone may CONFIRM an identity and never SELECT one.** More than one account on a
  number → HTTP 409 asking for the email. Refusing is correct; guessing hands someone another
  person's account.

**The lens that found it:** ask what a lookup KEYS ON, then ask whether that column is unique.
`login_otp` had three phone-keyed resolutions — an unconditional admin short-circuit that ran before
it checked `kind`, an `ilike + limit(1)` with no ORDER BY, and a "whoever last used this handset"
read of `phone_verifications`. See [[addressed-to-an-identity-nobody-models]].

**The cause was a previous fix.** /os sent `user_kind:'customer'` so the shared resolver would reach
`admin_mfa_phone` — that fixed /os mobile login and broke the customer portal for the same number.
There is now a third kind, `'admin'`, and only it consults admin_mfa_phone.

**Also:** `phone_verifications` stores the resolver's own output at send time, so it is a production
log of what the resolver returned — better evidence than re-reading the code. See
[[never-state-what-you-have-not-measured]].
