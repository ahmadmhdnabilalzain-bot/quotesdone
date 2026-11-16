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
- The agreement (15 Nov, the CEO's decision under founder ruling 1696): Supplier Agreement **v18** clause 12, EN and AR: "valid
  for the period the Supplier states in it ... If a quotation states no period, QuotesDone asks the Supplier to state one;
  until the Supplier does, the quotation may be shown to the Customer marked “Validity: not stated by the supplier”" (the
  portal's q_validity_not_stated, word for word; the delta review of 16 Nov 2026 found the earlier "before the quotation is
  shown" untrue: the 24-hour hold releases it, waited_24h, whether or not he answers). It only widens the supplier's
  freedom, so v18 CARRIES v17 (`supplier_terms_carries_from` = 'v17'): nobody re-signs. v17 stays byte-exact as `supplier-agreement-v17` (SHA-256 54f23ad7..., on every v17 acceptance).
  Registry SQL (pending): scripts/sql/the_supplier_agreement_v18_lets_a_quotation_be_valid_for_the_period_the_supplier_states.sql;
  guard: scripts/checks/the_supplier_agreement_v18_..._asks_nobody_to_sign_again.test.mjs. "Asks him to state one" is the
  quotation review rule 7 and the hold desk (they ask; they impose no period).
- A period counted from an event we cannot know ("from LPO / PO / delivery", «من تاريخ أمر الشراء») is no expiry; a date
  without a year moves forward only when within ~6 months; "1/2 month" is no expiry; the period beside "valid / validity"
  wins over a delivery or payment period (review of 15 Nov, items 2-5); a warranty's period ("warranty validity 2 years")
  is never the validity, and "valid" inside another term's clause ("Delivery: 2 weeks (valid for stock items)") states
  none (delta review of 16 Nov).

**Why:** the agreement said 30 days and the database defaulted to 14; the customer was shown a date nobody stated.
**How to apply:** any code, text or seat answer about how long a quotation holds reads the supplier's own validity; if he
stated none, say so. Supersedes the "Quotation validity 30 days" line in [[the-only-hard-rules-and-operating-doctrine]].
