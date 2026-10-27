---
name: apify-paused-until-2027
description: "Apify supplier scraping is deliberately cancelled from 10 Aug 2026; work the existing 20,470 leads first, revisit around Feb 2027. s26-discover-suppliers must NOT be \"fixed\"."
metadata: 
  node_type: memory
  type: project
  originSessionId: 66640db3-8fe2-45d3-89e5-ee7511b35d99
  modified: 2026-08-10T03:28:45.875Z
---

On 10 Aug 2026 the founder cancelled the Apify subscription (`compass/crawler-google-places`,
the supplier discovery scraper). The instruction: exhaust the **20,470 leads already in
`public.leads`** before buying any more, and revisit Apify in roughly six months — around
**February 2027**.

**Why:** paying a third party for new supplier leads while 20,399 of the existing 20,470 have
never been contacted is buying inventory the company cannot process.

**How to apply:** `s26-discover-suppliers` in `scripts/staging/verify_os2_blueprint.mjs` reads
MISSING because `scrape_runs` has no row in 30 days (last ever 19 June 2026, 22 runs, all manual,
**no cron has ever existed for it**). This is a deliberate founder decision, NOT a build order and
NOT a defect — do not schedule the scraper, do not re-subscribe, do not "fix" the check. It stays
red until the founder restarts it. See [[decide-dont-present-options]] for why spend decisions
escalate rather than get taken.

Related: [[specs-are-upgrades-not-repairs]] — this is the documented exception to "MISSING means
build it".

**SUPERSEDED IN PART 12 Oct 2026 (ledger 1184/1186):** the founder now wants the marketing seat to find NEW complete supplier leads continuously (safe sources only: no logged-in LinkedIn scraping, no bans). Apify itself still needs a cost quote before buying.
