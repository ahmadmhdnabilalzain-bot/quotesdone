---
name: exact-specs-or-the-quote-is-held
description: "Founder rule 14 Sep 2026 — every quote line needs exact technical specs; missing specs hold the quote until the supplier fills them (portal, regenerated + supplier-approved) or resubmits"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-14T11:54:22.835Z
---

Founder, 14 Sep 2026: the comparison report must be technically detailed — not just delivery time or installation.
For fit-out, e.g., the exact material, type of wood, thickness, etc. "this is a rule".

- "Missing details" means ALL FOUR (his words, same day): 1) specs of material, 2) delivery date,
  3) installation (if applicable), 4) warranty (if applicable). Applicability is deterministic per trade/item.
- Missing any of them → quote is HELD (never "rejected", never shown to the customer).
- The sales agent (sales_engineer seat) notifies the supplier exactly what is missing.
- Supplier either fills the missing details on the portal → sales agent regenerates the standardised quote →
  supplier approves it is correct → released; or resubmits a revised quote.
- The comparison report compares specs line by line across quotes.
- Also: quotation/comparison PDFs must look professional (not "very simple") and the Arabic version must be
  Arabic throughout, not English words here and there.

- Intake (same day): the sales/intake agent ASKS the customer: installation needed? warranty needed? material
  preference per component (e.g. table legs steel/wood/acrylic — or no preference; "our job is to ask"),
  required delivery date. Answers are the baseline for matches/differs.
- A supplier's options are SEPARATE quotations, each with its own ID — never merged into one.
- "we don't assume stuff" (founder 14 Sep): the intake ALWAYS asks installation, warranty, materials and date for
  every trade (explicit "Not needed"/"Supply only" answers); applicability comes from the customer's answer, not
  trade defaults.
- The check is NOT a fixed per-trade list (founder 14 Sep): required set = the customer's inquiry answers taken
  by the sales agent + the general standards for that inquiry. Below the customer's minimum = differs.
- Hold notices/reminders/approval requests reach the supplier through customer_support on WhatsApp AND email
  (+ portal notice); the sales engineer talks directly only inside a portal chat the supplier already started.
- Timing (founder 14 Sep): notify immediately; NO deadline or reminders — a held quote stays fixable until the
  customer reveals a quote on that request; unresolved then = an "ignored hold" incident, kept as a record.
  2nd consecutive incident → sales tells support + gentle EN/AR warning ("after the 3rd you're removed from
  matching") sent by support; 3rd consecutive → supplier on matching hold (no new requests). A fix resets.
- Lifting a supplier's matching hold is the FOUNDER'S ONLY (14 Sep): he calls the supplier himself and tells us in
  a session; then run the service-role lift routine citing his founder_instruction id. No agent may lift it.

**Why:** customers compare like for like; a price without specs is not comparable.
**How to apply:** any quote/extraction/report change must keep per-line spec attributes per trade and the hold
gate. Related: [[the-only-hard-rules-and-operating-doctrine]] (incomplete quotes held with notes).
