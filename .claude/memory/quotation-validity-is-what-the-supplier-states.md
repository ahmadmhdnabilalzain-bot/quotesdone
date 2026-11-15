---
name: quotation-validity-is-what-the-supplier-states
description: "Founder ruling 15 Nov 2026 (ledger 1697): a quotation is valid for the period the supplier states in it; QuotesDone sets no period of its own. Replaces the 30 days (agreement) / 14 days (system) contradiction."
metadata:
  node_type: memory
  type: feedback
---

Founder, 15 Nov 2026, ledger 1697, verbatim: "Quotation validity depends on what the supplier mentions in his quotation.
No specific period".

- The expiry is computed by code from his own words: `public.fn_quote_validity_until(validity, quotation_date, received)`
  in scripts/sql/a_quotation_is_valid_for_the_period_the_supplier_states_and_for_no_period_we_choose.sql (periods, dates,
  Arabic, working days; from the quotation's own date, else the day received; end of the last day in Dubai).
- He states nothing readable: NO expiry date. The customer reads "Validity: not stated by the supplier" (portal card,
  quote PDF). Never a default, a cap or a fallback period anywhere: not in SQL, not in the reveal period, not in a seat's
  knowledge, not in the FAQ.
- The reveal period after a paid reveal keeps its own 30-day cap (decision B, 13 Nov): a rule about the request, not a
  quotation's validity.
- OPEN with the founder (15 Nov): the signed Supplier Agreement v17 clause 12 still says 30 days. Its words change only as
  a new version; a new version with an empty `supplier_terms_carries_from` asks every registered supplier to accept again.
  Which way is his decision (see the validity hand-back of 15 Nov).

**Why:** the agreement said 30 days and the database defaulted to 14; the customer was shown a date nobody stated.
**How to apply:** any code, text or seat answer about how long a quotation holds reads the supplier's own validity; if he
stated none, say so. Supersedes the "Quotation validity 30 days" line in [[the-only-hard-rules-and-operating-doctrine]].
