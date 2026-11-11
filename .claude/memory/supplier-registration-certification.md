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
- **Branch `customer_support-registration-defects` (11 Nov, after #1918) fixes findings 4-7, 9 and 3b**: the sign-up trade
  (leads.sector) is on the checklist as source `signup`; a licence activity's SUBJECT ("Building Materials" of "... Trading") is
  decided exactly (fn_norm_trades, or a whole part of a trade's own English name); an expired licence is said at upload
  (`licenceExpiry.ts`); any company that has not submitted its registration (an invited listing above all) opens the same
  registration form; `me` is warmed beside the dashboard and both start at HTML-parse time on /portal (`SupplierBootPrefetch`);
  evidence_pack uses `recordFixtureMobileBeforeTheForm`. The harness walks J2 through the form now.
- Finding 8 was NOT changed: ruling 1008 covers messages (e-mail, WhatsApp, SMS, PDF), not web pages, and ruling 342 makes the
  agreement's Arabic text the one that prevails. Criterion 6's "no Arabic on any screen" is wider than 1008: a decision for the CEO.
- Function edge logs of the free round: each supplier_api / supplier_portal call is 0.3-0.6 s of server time
  (x_envoy_upstream_service_time p50) from the US container to ap-southeast-1; the lag is round trips in series, not slow SQL.
- Free-run model calls are stubbed (ai_cost_log model "none", cost null) and UNTAGGED. A paid run must check that its reader rows
  are tagged with real spend. Otherwise the paid verdict on reading stands for code alone.

Related: [[a-journey-step-is-proved-by-its-outcome]], [[the-registration-walk-reads-the-real-code-through-a-resend-sink]],
[[supplier-verification-mandatory-six]], [[chromium-in-the-cloud-container-cuts-requests-at-30-seconds]].
