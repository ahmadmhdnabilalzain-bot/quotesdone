# 12 Aug 2026, part 5 — the sign-in code did not count

Continues parts 1–4. PR [#275](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/275) merged, both projects.

---

## Item 1 — the promoter exists, is reachable, and has never once run

**What promotes a ready intake into an inquiry:** `customer_api`, action `create_inquiry`. It is
fired by the **Send** button on the ready-brief card — `CustomerPortal.tsx` → `NewRequest.submit`
(line 841) — and it resolves the intake **server-side**: it re-reads `inquiry_intake`, requires the
row to be owned by the caller's email and to carry `status = 'ready'`, and marks it `consumed` on
success. `fn_split_inquiry` is the only other writer of `inquiries` and it only splits one that
already exists. There is no cron, no sweep, and no agent in this path — **the customer presses a
button**.

**Has it ever run?** No.

```
production   inquiries 0 · intake rows 4 (3 ready, 1 needs_info) · intakes ever consumed 0
staging      inquiries 11 · intakes consumed 2      <- the harness path only
```

## The first gate was silently losing its own write

`create_inquiry` refuses on line 1 unless `customers.email_verified`. `login_otp` recorded proof of
email ownership with an **UPDATE** against `public.customers` — and a first-time customer has no row
to update. `login_otp` never creates one, and the row that appears seconds later (`kyc
save_customer`, `customer_api me`, `mobile_otp`) inserts with the flag defaulting to false.

Measured on production, in order:

```
15:00:49  code issued        email_verifications, purpose=login, user_kind=customer
15:04:40  code used          login_otp UPDATE matches 0 rows — no customers row exists yet
15:05:26  row inserted       kyc save_customer, agent_runs counts {created: true}
          email_verified     false, ever since
```

The supplier branch of the identical line is safe for the opposite reason and is deliberately left
an UPDATE: a lead already exists to be claimed, which is why lead 30466 carries
`owner_email_verified` true from that same statement. Creating a lead on a sign-in would invent a
supplier out of nothing.

**Correction to my own commit message.** I wrote that a new customer was *permanently* unverified.
That is wrong. The portal's `ProfileGate` offers `kyc send_email` / `verify_email`, and `kyc` handles
the missing row correctly — it inserts with `email_verified: true`. The customer could recover by
proving the same address **a second time**, inside the portal, after the sign-in code had already
proved it. The defect is a lost write forcing duplicate verification and holding the dashboard
behind it, not a welded door. That `create_inquiry` refused while the flag was false is measured and
stands.

### Why the journey test never caught it

`journey_test.mjs` called `customer_api me` **before** the OTP step, and `me` creates the customers
row. The harness manufactured the one ordering in which the bug cannot occur — which is also why 13
of 14 staging customers were verified and production's only real one was not. Verification now runs
first, exactly as a human does it, and `email_verified` is asserted **from the database** rather than
from HTTP 200: a 200 was returned throughout the broken period.

Verified by execution against deployed staging: a first-time email with **no** customers row, code
seeded and hashed the way `login_otp` hashes it → verify returns 200 → exactly **1** row, with
`email_verified` **true**.

Backfill was evidence-gated, not fabricated: a row is flipped only where `email_verifications`
already holds a **used**, customer-kind login code for that address. **1 row on production, 0 on
staging.** No other gate granted.

---

## Item 2 — the /me sign-in, settled

It is **not broken**. The mechanism ran end to end for a real person today: a login code was issued
at 15:00:49, consumed at 15:04:40, a session was minted, `kyc save_customer` wrote the profile at
15:05:26, and five `inquiry_intake` turns followed on that session reaching `status = ready` at
15:08. Nothing in that chain failed. The earlier inability to drive it from the browser tools was
tooling, not the front door.

What it *did* have was the lost write above. That is fixed.

## What actually stands between intake `18e2c133` and an inquiry — and both are yours

| gate | state |
|---|---|
| `email_verified` | **true** — repaired today |
| `full_name`, `date_of_birth` | set |
| `phone_verified` | **false** — the number on file is `+971 4 258 7734`, a Dubai **landline**. Twilio Verify sends SMS; it cannot reach it. |
| `tos_accepted_at` | **null** — and `ProfileGate` only renders the Terms checkbox once phone **and** email are verified, so this is downstream of the row above. |

Two founder-held acts, neither of them code: **enter a mobile number that can receive an SMS**, and
**tick the Terms box**. The Send button, the server-side intake resolution and dispatch behind it are
all in place. I did not fabricate an inquiries row.

---

## Verified state

```
Row #3        not re-scored this session — see below
journey       39/40 on staging after the edit (step 27 supplier inbox, see below)
journey       39/40 on staging after the edit (step 27 supplier inbox, see below)
gates         23/23 met on BOTH projects
parity        BOTH PROJECTS IN SYNC (anon-executable SECURITY DEFINER 56/56)
OpenRouter    0 refusal/credit/rate-limit errors in agent_runs in the last 6h; the 15:07 intake
              turns logged llm_call_ok=1, llm_parse_ok=1
customers     1 on production, email_verified true, phone_verified false, terms not accepted
demand        inquiries 0 — UNCHANGED, and now blocked only on the two acts above
```

## Not done — stated plainly

- **Row #3 scorer was not re-run to completion**, and no pack scorecard was run. Nothing this session
  touched a scored surface (one edge function, one test harness, one evidence-gated data repair), but
  that is reasoning, not a measurement, and 127/152 should not be treated as re-confirmed.
- **One journey step fails, and it is not mine.** Full run after the edit: **39/40 on staging**,
  with steps 2 and 3 passing in the new order — *"customers.email_verified = true for a customer
  whose row did not exist when the code was verified"* — and step 14 `create inquiry` passing, so
  the loop does close on staging. The failure is step 27, *supplier receives the inquiry*, inbox 0.
  Step 14 routed with `no_capability_match` because the harness creates the supplier **after** the
  RFQ, and step 26's re-dispatch returns `skip: already_dispatched` instead of fanning out to the
  supplier that has since appeared. My diff is confined to the OTP ordering and an added assertion
  and cannot reach supplier matching, but I did not run the harness *before* the edit, so I have not
  measured how long step 27 has been failing. **It wants a look next session:** either the
  re-dispatch must not skip when the previous dispatch reached nobody, or the harness must create
  the supplier first.
- Items 3–7 of the brief (s36 columns, invite ramp, Row #3 residue, Spec #3 UI, BoQ fixtures) were
  not started.
