---
name: a-brand-is-generalised-at-the-customer-door-not-in-the-supplier-copy
description: "Founder ledger 1588-1590 (10 Nov 2026): every pre-reveal surface runs _shared/quote_generalise.ts; the stored quote keeps the raw brand (the hold gate needs it); review notes come from _shared/quote_review_notes.ts; measure with the 24-trade corpus"
metadata:
  type: lesson
  modified: 2026-11-10
---

Founder, 10 Nov 2026 (ledger 1588-1590): the sales engineer reviews every quotation against the request and the
customer sees NOTES (EN + AR); before the reveal no brand, model number, product line or the supplier's own name
reaches the customer, and a brand becomes a FACTUALLY CORRECT "<tier> <origin> brand" (Grohe is German, never
"premium Italian"); the comparison's top 3 weighs unmet requirements on cost-to-value.

**How to apply:**
- Generalise at the CUSTOMER DOOR, not in the supplier's working copy. Generalising quote_from_document's lines made the
  quotation chat ask a painter for the brand his own file stated (8 tests in supplier_api/quote_review.test.ts): the hold
  gate needs the raw brand and product. Raw stays in quote_items; my_inquiries, the quotation PDF, quote_compare (last-gate
  generaliseDeep over the whole analysis) and the sales-engineer chat (own_quotes.ts) generalise. The model path's prompt
  generalises at source, and its output passes the module too.
- A new pre-reveal surface calls generaliseQuoteTerms / generaliseLine / generaliseDeep with ctxOfQuote(lines, [supplier name]).
- Brand facts: scripts/kb/brand_facts.mjs builds _shared/brand_facts.generated.ts from the packs' uae_market_brands plus
  knowledge/brands/origin_and_tier.json; when the k1/k2 knowledge branches add per-brand origin/tier to the packs, rerun it
  (the pack wins). A nationality is never a brand ("Malaysian" was, and "Malaysian origin" lost its origin).
- Re-measure with `deno run --no-lock --allow-read scripts/e2e/quote_review_corpus.ts --detail` (USD 0). 10 Nov: leaks
  125 -> 0 of 177, deviations 40 -> 124 of 124, 0 false flags. The corpus was written with the code, so ALSO measure
  over-redaction on text nobody wrote for it: the packs' prose (13,820 sentences) had codes taken in 493 sentences on the
  first draft, 105 after the spec shapes were added. A spec shape (SS316, E7018, A15, TIA-568.2-D) is never a model.
- quotes.review_notes is pending SQL (scripts/sql/a_quote_carries_the_sales_engineers_review_notes.sql); every surface
  recomputes the notes, so nothing waits on it.

Related: [[identity-shapes-live-in-one-list]], [[exact-specs-or-the-quote-is-held]].
