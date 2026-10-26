---
name: test-without-the-founders-credentials
description: Founder 14 Sep 2026 — testing and browsing must never need his accounts; use the autonomous ZZ DEMO E2E harness
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-14T12:03:17.500Z
---

Founder, 14 Sep 2026: "do what is needed cause you need to keep browsing stuff without my credentials. you
shouldn't need me to browse and test functions."

- Test both portals and the full journey with the E2E harness (branch `e2e-harness`, scripts/e2e/, docs/e2e.md):
  ZZ DEMO customers/suppliers created by the admin API, sessions injected (no OTP), outbound captured not sent,
  Playwright on the live site, Stripe TEST mode for demo accounts only, full cleanup.
- Don't ask him to sign in or register test accounts. The only thing he may need to supply is a Stripe test key
  in app_secrets if it is missing.

**Why:** he can't be the bottleneck for every check; manual account creation by me is off-limits anyway.
**How to apply:** before asking him for access, run or extend the harness. Related: [[demo-fixture-convention]],
[[safe-marketplace-demo-rehearsal]], [[rehearsals-and-probes-page-the-founder]].
