---
name: a-customer-is-answered-from-his-whole-request
description: "16 Nov 2026, ledger 1711: every customer channel reads fn_customer_inquiry_facts with what he asked and what his portal shows (price per quote under its letter, before the reveal too); the model reasons, OWN_REQUEST_RULE says how; a figure in facts needs its unit or the reply guard strips it"
metadata:
  type: project
  modified: 2026-11-16
---

# A customer is answered from his whole request, on every channel

The founder (ledger 1711): a budget said in the request chat must be known when he later asks on WhatsApp "did you find anyone
below 5,000?", and "I don't want the system to be rule-based only ... it's scenarios".

- **The facts.** `public.fn_customer_inquiry_facts` (scripts/sql/a_customer_is_answered_from_his_whole_request_on_every_channel.sql)
  gives per request `asked` (budget as he wrote it, required_by and his words, emirate and his site, materials and brands asked,
  items, accepted alternatives), `changes_he_sent_after`, and per live quote its portal letter, `price_as_shown`, VAT as stated,
  validity, lead time and warranty (masked), the sales engineer's review notes and the request thread with that supplier; plus the
  cached comparison. Read by WhatsApp (fn_wa_context, fn_wa_fact_pack), the widget, e-mail, and the portal chat (`asked` only).
- **Anonymity.** The portal already shows each quote's price under its letter before the reveal (customer_api my_inquiries,
  QuoteCard). WhatsApp now shows the same; the supplier's name, contacts and brand stay sealed. Do not "restore" the band-only rule.
- **The model reasons.** `_shared/own_request_facts.ts` OWN_REQUEST_RULE is the one rule every door gives. No intent row and no
  code comparison of price against budget.
- **A figure in the facts needs its unit.** The reply guard (`_shared/company_brief.ts` figuresOf/allowedNumbers) knows a money
  figure only as "AED 4,600" or "4,600 AED"; a bare `4600` under a key named `_aed` is not one, so the model's "AED 4,600" was
  refused and rewritten until the figures were gone (paid smoke, 16 Nov). Give money as words with the unit.
- **Letters.** No stored letter on main; the facts derive it as the portal does and switch to `customer_supplier_letter` when the
  plain-words branch lands. Until then a quote held by the code-side hold rule can shift letters between the portal and WhatsApp.
- Bank and checks: scripts/eval/customer_follow_up_bank.mjs (51 scenarios), scripts/checks/a_customer_is_answered_from_his_whole_request.test.mjs
  (facts per scenario on a LOCAL database), paid eval scripts/eval/customer_follow_up/run.ts (cap USD 1.50).
