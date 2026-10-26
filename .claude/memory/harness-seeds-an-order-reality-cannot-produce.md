---
name: harness-seeds-an-order-reality-cannot-produce
description: "A green end-to-end test can prove nothing if its setup creates a row the real flow creates later — check the ORDER the harness walks, not just its steps."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: d59a0e58-a4df-44cd-a572-d0275ee07862
  modified: 2026-08-12T15:27:30.604Z
---

`journey_test.mjs` called `customer_api me` (which inserts the `customers` row) **before** the OTP
step, so `login_otp`'s `update customers set email_verified = true` always found a row. A real
first-time customer produces the opposite order — code first, row later — and the UPDATE matched
nothing. 13 of 14 staging customers were verified; production's only real one was not.

**Why:** an end-to-end harness that seeds state in a convenient order is not testing the path, it is
testing a path. The bug lived in the gap between the two orderings and every gate stayed green.

**How to apply:** when a defect appears in production but the e2e suite is green, diff the *order* of
the harness's first three calls against what a human actually does. Also assert the effect from the
database, not from HTTP 200 — the broken write returned 200 throughout. Related:
[[guarded-by-a-condition-that-cannot-occur]], [[finished-capability-with-no-entry-point]],
[[never-state-what-you-have-not-measured]].
