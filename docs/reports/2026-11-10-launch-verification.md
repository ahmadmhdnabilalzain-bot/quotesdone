# Launch verification, 10 Nov 2026 — the supplier/customer funnel and the channels, on production with the real AI

Seat: ceo (it_engineer tooling). Founder ruling 1563: a green light before suppliers are invited, every feature proved
end to end. All runs used ZZ DEMO identities on reserved domains, run tags, rehearsal windows and full teardown
(0 leftovers on every tag). "Measured" = run today; "inferred" = read from a transcript or the code.

## Summary

| Area | Verdict | AI spend |
|---|---|---|
| Supplier registration, approval, receiving an inquiry, quoting (held / two options / complete), comparison, PDFs EN+AR | **GO** — e2e run.mjs tag 8514ddd6: 217 PASS, 7 FAIL, 5 SKIP | USD 0.91 |
| Customer test reveal, invoice, refund | **NOT PROVED** — this cloud session cannot reach checkout.stripe.com (environment, not product); last proved by a nightly run, findings closed 2 Nov | — |
| WhatsApp, customer EN/AR and supplier | **GO** — conversation_quality, real handler and model: 0 leaks, 0 invented facts, holds the job and changes, refuses injection | USD 1.19 |
| Homepage widget, visitor not signed up | **GO** — 3/3 scenarios meet; live widget_matrix 70/77 (the 7 are harness graders, not the product) | USD 0.79 |
| Drawings: reading + hand-off to suppliers without identity | **GO for PDF, DXF and small DWG** — drawing_reaches_suppliers 35/36, cad_identity 15/15, identity leaks 0 of 480 | USD 0.52 |
| Large DWG (over the edge ceiling) | **OFF** — its worker ran on GitHub Actions (off, ledger 1564); move to the Claude "CAD read worker" routine before inviting at volume | — |
| Supplier licence and profile reading | **GO** — licence fields exact, expired licence held, recall 100% on 6 of 7 real files | USD 0.04 |

## Should-fix before inviting suppliers at volume
1. `fn_sales_engineer_verifies_supplier` after a supplier confirms services: one statement timeout and one 40 s run
   (the page then shows nothing, or the supplier stays Pending until the 24 h re-run). Queue the re-run or give it its
   own statement_timeout.
2. A text profile tells suppliers "Reading the rest is waiting on the language model, which is switched off for now."
   decision_policy supplier_catalogue_model_enabled / supplier_photo_vision_enabled have been false since 21 Sep, before
   rulings 1175 and 1260 — switch on or change the copy.
3. Mobile customer portal: with the account assistant open, the tab bar and the More sheet open underneath it (14 FAIL on
   a new empty account). Fixed in ef25fc98e (branch it_engineer-verify-funnel); the full 10/10 EN+AR mobile browser pass
   is still owed.
4. Supplier Agreement signing is asynchronous; once in 13 fixtures the signed PDF had not landed after 60 s. Proposal: a
   sweep that re-signs a lead accepted-but-unsigned after 5 minutes.
5. Quote-PDF review asks a supplier for 1-2 details the PDF already states (dimensions).
6. Customer overview 2.5-2.8 s against 2.5 s (7 function calls from a US container to ap-southeast-1).
7. Drawing take-off lists the duct size but no linear metres; one cover-only profile produced one invented trade.

## Harness fixes landed
- continuity grader allows the published contact lines, not the founder's private mobile (5e81f970f).
- conversation_quality graders read the Arabic "3٪" and "أعتذر" (a7706e77b).

## Still owed
- Journeys d/e (Stripe TEST reveal, invoice, refund ladder) from a network that reaches Stripe.
- The full mobile pass on the fixed portal build; stage2.mjs at founder scale (estimate USD 1.6).
