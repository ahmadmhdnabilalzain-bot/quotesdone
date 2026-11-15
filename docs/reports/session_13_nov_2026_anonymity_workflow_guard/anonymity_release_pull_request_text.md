## Summary

Founder's ruling 1683 (13 Nov 2026): anonymity is the core of the platform. Nothing below the emirate reaches a supplier
before a paid reveal; no supplier's identity reaches a customer before it; an old supplier's name, references and prices
never reach new suppliers (ruling 1686: items, quantities and specifications may). This is the text side and the
customer-to-supplier doors, released together. Drawings follow in their own pull request.

## Seat

sales_engineer

## What changed

- **Text (`_shared/identity_text.ts`, `identity_places.ts`, `anonymise.ts`, `site_location.ts`)**: a gazetteer of places
  below the emirate; a place crosses as its emirate; phones in column-spaced and tab-separated text; a tab is a cell
  boundary; hyphenated premises numbers; a customer's name inside an ordinary word is no longer read as his name
  (Rami and "Ceramic", Hani and "mechanical" were withheld on main), while a name joined to a particle or another seed
  still is.
- **Doors (`supplier_api/what_a_supplier_receives.ts`, `customer_api`, `messages_api`, `supplier_portal`, `inquiry_intake`,
  `drawing_boq/quotation_gate.ts`)**: one function decides what a supplier receives at the inbox, the portal, the inquiry
  PDF, the new-inquiry e-mail and WhatsApp, clarifications and notes; a quotation the customer uploads is rebuilt as our
  inquiry with no prices, names or references of the old supplier (Arabic-Indic digits and "dirhams" included; the old
  supplier's name with or without its legal form); edits that name the customer or his site are refused with the part
  named.
- **SQL (one file, routine replacements only)**: `before_a_reveal_a_supplier_portal_title_is_the_trade_and_the_emirate.sql`
  with its probe and pending note.
- 654-sentence permanent over-redaction corpus; adversarial timing test; planted rows for every leak closed.

## How it was verified

- Independent reviews: text ×3 rounds, doors ×3 rounds, two independent FINAL reviews of the combined tree, and an
  independent check of the final fixes (all in the session's review log). The last check's corrections are applied as
  its own tested diff.
- Auditors' probes on the combined tree: supplier-to-customer 46 → 2 (both on the second-reader list: an unlabelled
  person, a house brand); customer-to-supplier 0 of 62; place probes 1 of 60 and 1 of 40 (unlisted sub-communities).
- Over-redaction: 60 fresh quoting sentences ×2 reviewers, 0 changed by this code; the 654 corpus unchanged.
- deno suites on the merged tree: see the gate log lines in the first comment-free section below.
- Local gate (`npm run gate -- --offline --skip=npm-test`) on the exact tree merged with main: GATE_RESULT.
- The SQL file and its probe were run on a LOCAL Postgres 16 built from the mirror (PROBE OK); nothing was rehearsed on
  production (incident of 13 Nov).

## Production impact

- Deploy 22 functions (supplier_portal first): accountant, customer_api, doc_extract, drawing_boq, drawing_redact,
  inbound_email, inquiry_intake, license_extract, messages_api, public_site, quote_compare, quote_extract,
  resend_inbound, resilience_ping, reveal_invoice, sales_engineer, stripe_checkout, stripe_confirm, supplier_api,
  supplier_catalog_ingest, supplier_portal, wa_inbound.
- Apply the one SQL file (CREATE OR REPLACE of two routines + two REVOKEs; ACCESS SHARE on user tables only).
- What users notice: before a reveal a supplier's portal title reads "Fit out work in Sharjah · Job 160501"; a site
  below the emirate reads as the emirate or "[site details withheld]"; a customer whose note names his site is told
  which part is kept back; a customer's edit that names him is refused with the part named.

## Risks and rollback

- Known remaining leaks, by design left to the second reader (not built yet): an unlabelled person's name, a house
  brand, an unlisted sub-community or project, a landmark with no cue, prices written in words, an old price in the
  customer's own free text, a phone followed by a single space and a figure.
- Rollback: redeploy the 22 functions from the previous main (`scripts/deploy_functions.mjs`), and re-apply the previous
  bodies of the two routines (in git history); either order of function and routine is safe.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01MHFn2pe3REUYi65EDVrW7G
