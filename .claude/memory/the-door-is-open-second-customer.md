---
name: the-door-is-open-second-customer
description: "The founder's registration gate is PASSED — a second customer row (djzaino@outlook.com) has phone_verified, email_verified and terms all true since 13 Aug 2026."
metadata: 
  node_type: memory
  type: project
  originSessionId: 5cddcd24-7d49-4fa9-84c5-f33b74a74e52
  modified: 2026-08-13T02:28:08.330Z
---

There are two customer rows, and briefs written before 13 Aug 2026 describe the wrong one.

- `dbb4e36f…` — `ahmadmhdnabilalzain+qdcust1@gmail.com`, phone `+971 4 258 7734` (the office
  LANDLINE), `phone_verified = false`. This is the row every brief up to 13 Aug called "mine", and
  the source of "the door is still shut".
- `70f15bc3…` — **`djzaino@outlook.com`**, phone `+971509319355` (his SMS-reachable mobile),
  created 2026-08-13 00:56 UTC, `email_verified` **true**, `phone_verified` **true**,
  `tos_accepted_at` 00:57 UTC. He completed the whole gate himself, one minute after registering.

Measured on production 13 Aug 2026: `fn_wa_context('customer','djzaino@outlook.com')` returns
`profile.can_post_request = true`. **`create_inquiry`'s gate is satisfied.** There is nothing left
for him to do before an inquiry can exist — 0 inquiries is now a "nobody has posted one yet"
problem, not a blocked-door problem.

**Why:** two sessions in a row were told "phone_verified is false, tell him when you want him on the
screen", and both would have asked him to do something he had already done. See
[[session-briefs-carry-misdiagnoses]] and [[founder-landline-and-mobile]].

**How to apply:** before repeating any claim about his verification state, run
`select email, phone_verified, email_verified, tos_accepted_at from customers order by created_at desc`
— and read the NEWEST row, not the one the brief names. To sign in as him for testing without
emailing him a code: insert a row into `email_verifications` with
`token_hash = encode(hmac('<code>', (select value from app_secrets where key='otp_hmac_key'), 'sha256'),'hex')`,
`purpose='login'`, `user_kind='customer'`, then POST `login_otp` `action:'verify'`.
