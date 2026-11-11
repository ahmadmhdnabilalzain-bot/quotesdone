---
name: supplier-registration-certification
description: "11 Nov 2026: the certification that decides 'ready to invite' (founder ruling 1620), how to run it free and paid, and what its first free rounds found about the registration a supplier meets"
metadata:
  type: project
  modified: 2026-11-11
---

Founder ruling 1620 (10 Nov 2026): he will invite general managers from his own network to register as suppliers only once IT
confirms the registration is "not laggy, reads their trade licence, understands what they do". The bar is
`docs/release/supplier-registration-certification.md`; the driver is `scripts/e2e/supplier_registration_certification.mjs`.
**Ready to invite = a `--paid` run with every criterion PASS on two runs, the same day.** A free run never certifies the reading.

**Run it** (cloud session: Node reaches the management API only through the proxy, so `NODE_USE_ENV_PROXY=1`):
`node scripts/e2e/supplier_registration_certification.mjs` (free: models off, USD 0), `--estimate`, `--paid --runs 2 --cap-usd 1.50`.
It registers eight ZZ DEMO companies, one at a time, from the fixtures in `scripts/e2e/fixtures/registration/`
(`registration_fixtures.mjs --write` regenerates them; every licence number carries "ZZ").

**What the first free rounds found (11 Nov 2026), so nobody re-derives it:**
- A licence value that WRAPS in its table cell was cut by the code reader. A Dubai DET legal name read as half the name, and
  ruling 1176 then RENAMED the company to it and e-mailed the supplier. Activities lost every wrapped word. Fixed on branch
  `customer_support-registration-certification` (`_shared/document_expiry/licence_fields.ts`). It takes effect only when the
  readers are deployed.
- The registration form showed EMPTY "Trade licence no." and "Licensing authority" after code read a licence whole. Only the
  model branch put them in the answer. Fixed in the same branch: `supplier_api/lib/licence_shown_back.ts`.
- **A reload after "Create company" lands in the WORKSPACE**, never the registration form again. Dashboard shows Onboarding only
  for `no_company`. That broke `fixture_mobile.recordFixtureMobile`, whose reload never saw the form again; use
  `recordFixtureMobileBeforeTheForm`. evidence_pack.mjs still uses the reload path.
- **An invited supplier never sees the registration form.** After Verify he is in the workspace (Pending, profile score 0/100)
  and finishes through the Documents tab, then the Profile tab (Account menu), then Services.
- With the models off, nothing is proposed from a profile, and the trade picked at sign-up is NOT on the Services checklist
  (only `supplier_capabilities.trades` is). So Confirm stays disabled and the registration stays `services_unconfirmed`. A
  free run therefore cannot reach "verified". The same would happen to a real supplier whenever the reader is down.
- The expired licence: the licence step shows only "expires 2026-08-31". Submit then says "Still needed to register: the trade
  licence on file has expired."
- Arabic a supplier can see: the `/supplier` page's language switch leads to a full Arabic supplier page (`/ar/supplier`), and the
  Supplier Agreement page prints QuotesDone's Arabic registered name.
- First full free round (tags f331a927, 506f549f): USD 0, 0 dispatched, 0 leftovers. Desktop Verify -> "Register your company"
  took 3.5 s median, over the 3 s bar: login_otp verify, then me / dashboard / kyc state, in series. Licence code reading was
  1 of 5 whole on production (6 of 6 with the branch fix, offline). J2 (invitation) and J6 were verified in 2.7 min. A
  building-materials licence proposed only plumbing. Report: `docs/reports/2026-11-11-supplier-registration-certification-free-round.md`.
- Free-run model calls are stubbed (ai_cost_log model "none", cost null) and UNTAGGED. A paid run must check that its reader rows
  are tagged with real spend. Otherwise the paid verdict on reading stands for code alone.

Related: [[a-journey-step-is-proved-by-its-outcome]], [[the-registration-walk-reads-the-real-code-through-a-resend-sink]],
[[supplier-verification-mandatory-six]], [[chromium-in-the-cloud-container-cuts-requests-at-30-seconds]].
