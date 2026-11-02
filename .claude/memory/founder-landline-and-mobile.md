---
name: founder-landline-and-mobile
description: "The founder's customer record carries his office LANDLINE (+971 4 258 7734); his SMS-reachable mobile is +971 50 931 9355, stored as app_secrets.admin_mfa_phone."
metadata: 
  node_type: memory
  type: user
  originSessionId: e5b298f0-12e8-4cda-8c29-f9b16960b3bd
  modified: 2026-08-12T21:11:45.531Z
---

Proven against Twilio on 13 Aug 2026, not inferred:

- `+97142587734` — Lookup says `type: landline`, carrier Etisalat AE. Verify SMS returns **HTTP 400,
  code 21635, "'To' number cannot be a landline"**. Verify **voice** (`Channel=call`) returns HTTP
  201 / pending, so a landline can still be verified by phone call.
- `+971509319355` — `app_secrets.admin_mfa_phone`, Lookup says `type: mobile`. Twilio's Verify
  Attempts history shows an SMS to it CONFIRMED on 14 Jul 2026, so SMS to that number demonstrably
  arrives and he demonstrably entered the code.

**Why it matters:** `create_inquiry` refuses until `customers.phone_verified`, and the customer row
holds the landline. Any future "he cannot receive the code" question is answered by which of the two
numbers is in the box.

**How to apply:** never re-diagnose this from scratch — Lookup and the Attempts API settle it in one
call each, and the credentials for both are in `app_secrets`. `app_secrets.sms_enabled` is NOT the
gate and no longer exists; see [[instruments-report-on-the-wrong-subject]].

**Update 2 Nov 2026 (ledger 1482):** the mobile is no longer a public number. Public calling is +971 56 791 8605, WhatsApp is +1 218 316 6814. The mobile stays the SMS-reachable MFA/OTP number (login_otp, voice_otp read it server-side) and is printed on no current public legal page. See [[a-contact-only-terms-version-asks-nobody-to-sign-again]].
