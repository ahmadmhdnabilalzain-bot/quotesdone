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
  agreement's Arabic text the one that prevails. DECIDED 11 Nov by the main session (founder told): the agreement's Arabic name and
  the language switch stay; criterion 6 now judges messages (code e-mail + every notification) and English pages, the agreement's
  legal text and Arabic the supplier chose excepted (`judgeArabic`).
- Second free round (11 Nov 02:57-03:41, after #1924): J2, J3, J8 pass. J4 (photo) and J5 (scan) stay `licence_being_read` with
  models off: correct (#1909 re-reads; demo rows never re-read in real mode), now NOT RUN via `waitsOnTheModel`. Both licence doors
  had told the supplier to send a clearer copy of a licence OUR reader had not read; they now say it is ours. A portal chunk 502
  left /portal blank for 240 s: no production deploy in the window, chunk a Vercel cache HIT before and after, and the container's
  egress relay logged tunnel failures to quotesdone.com then; `PortalBootFallback` now says the portal is opening and offers a
  reload after 12 s. The certification opens quotesdone.ae (what UAE contacts get). login_otp verify returns `has_company`.
- Function edge logs of the free round: each supplier_api / supplier_portal call is 0.3-0.6 s of server time
  (x_envoy_upstream_service_time p50) from the US container to ap-southeast-1; the lag is round trips in series, not slow SQL.
- PAID round (11 Nov 06:07, USD 0.033): absurd SERVICES for every company (Recording studio equipment for 4 of 6 from "our own
  team and equipment"). Causes: profile_services.servicesOfText called proposeByMeaning WITHOUT the trade confirmation tradesOfText
  passes (13 Oct rule), and proposedServicesOf proposed services in trades nothing grounded. Fixed on
  customer_support-registration-defects-3: a service stands only in a trade the document or the licence names; dispatch and the
  intake count keep prose-read service keys only in the request's own trades (keysInTrades). Live proof on the six ZZ DEMO profiles:
  right trades, 0 absurd, 2 readings each. facilities_management on J1 was the model's own trade choice in run 1 only (0 of 7 other
  readings); not changed. "Confirm" FAILed on a missing acknowledgement locator in the walk, not lag.
- **SUPERSEDED BY RULING 1627 (11 Nov, branch `customer_support-services-are-read`)**: "it's not word matching ... it has to be
  read". The model reads ALL a supplier's documents together (supplier_doc_trades.readTogether: profile and catalogues first, licence
  last, each under "=== kind: name ===") and names trades AND services (keys from the trade's own list) with the line it understood
  each from and its own licence judgement; code only checks keys and quotes, and drops a trade or service quoted only from the
  licence. tradesOfText, servicesOfText, proposedServicesOf, keysInTrades, serviceKeysOf and the Services tab's "Read my catalogue"
  are DELETED. No model: nothing proposed, documents say "still being read" (portal state `pending`), the sign-up trade stays, and the
  sweep re-asks from the `<path>.read.txt` sidecar, 10 min x 2^n, 8 times (rereadTogether). Ruling 1628: inquiry keys are the
  intake model's or the customer's choice; dispatch matches them in code; none named = trade level. Live (tag 5ec510d7, USD 0.0381,
  28 calls, 14 readings): right trades and 0 absurd on all six + the "General Trading" hard case (every service not_covered there).
  The model folds P2's doors into joinery.wooden_doors and names P5's specific packaging trades, not the umbrella: judged PASS.
  Cost per registration ~USD 0.003 (one combined reading, chooser + second look). Ruling 1618 comparison NOT possible without a
  model_policy row: Qwen 3.8 Flash exists only on reviewer classes (knowledge_validation refuses without counterpart_model) and
  Gemini is voice-only.
- Slow moments at :x0 / :x5 (08:10, 06:10): 89 `seat_duty:*` pg_cron jobs (98 jobs) all run `*/5`. Edge calls in the first 10 s
  after a mark: p50 1.1 s vs 0.63 s, p90 3.4 s vs 1.4 s, 18.5% over 3 s vs 3.8% (05:30-08:40, supplier_api/kyc/supplier_portal).
- Free-run model calls are stubbed (ai_cost_log model "none", cost null) and UNTAGGED. A paid run must check that its reader rows
  are tagged with real spend. Otherwise the paid verdict on reading stands for code alone.

Related: [[a-journey-step-is-proved-by-its-outcome]], [[the-registration-walk-reads-the-real-code-through-a-resend-sink]],
[[supplier-verification-mandatory-six]], [[chromium-in-the-cloud-container-cuts-requests-at-30-seconds]].
