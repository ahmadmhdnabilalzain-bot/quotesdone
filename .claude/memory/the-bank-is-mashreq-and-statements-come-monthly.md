---
name: the-bank-is-mashreq-and-statements-come-monthly
description: "Mashreq Bank, AED 200/month charges, same account Stripe settles into; founder shares statements monthly — do not book until then"
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-14T21:42:34.039Z
---

Founder, 9 Sep 2026: *"our bank account is with mashreq bank and the monthly charges are 200 AED.
so far they deducted that twice so you can keep that in the records as well but i cant share a
receipt cause its like fixed running charge every month. later once we start operating and generate
revenue, on monthly basis i will share the bank statement with the accountant. its the same bank
account used for stripe btw"*

Then, immediately after: *"you dont have to record that now for mashreq bank. later i will share
the bank statement."*

**So nothing is booked and nothing is registered.** I had written
`the_bank_charge_has_no_receipt_and_is_still_a_cost.sql` and deleted it unapplied. Verified: 0 rows
in `expenses`, 0 in `expense_entries`, no `Bank` category in `gl_expense_map`.

**Facts to use when the first statement arrives:**
- Bank is **Mashreq**. Account maintenance charge **AED 200/month**, and two had been debited as of
  9 Sep 2026 (AED 400) — the months were never stated.
- A bank never issues a receipt for this; **the statement is the evidence**, and it arrives monthly
  from the founder once the company is operating.
- **It is the same account Stripe settles into.** One statement will carry both the settlements and
  the charge, so they are not independent sources and must not be reconciled as if they were.
- `expense_entries.charged_on` is NOT NULL, which is why the two past charges could not be booked
  from his message alone — the amount was known, the dates were not. Do not invent them.
- A bank charge is not software: `Subscription` maps to 6000 Software & AI, so bank fees need their
  own category mapping to **6300 General & Administrative** when they are first booked.

**14 Sep 2026 update, the standing route (founder_instruction 369):** *"every month end i will share
the bank statement. its that simple. i will share it on the same email i use for sharing invoices"*.
The statement arrives in the expenses mailbox at every month end, and the accountant's own sweep reads it.
The #666 Mashreq reader reconciles it to the fils; unreadable statements become a finding, never a
guess. Never ingest by hand from a chat attachment. If a statement comes via chat, ask for it to be
forwarded to the mailbox. His own transfers in are capital: [[owner-money-in-is-capital]].

**Measured on the real August 2026 statement (14 Sep).** 6 lines; opening 0.00, closing 582.96, and it
reconciles to the fils: 1000 − 199 − 9.95 − 9.95 − 199 + 0.86. So the monthly charge is **AED 199 +
AED 9.95 "Value Added Tax - Output"**, not a flat 200, and August carries two of each. The VAT is booked with
the fee to 6300, because we are not VAT registered. Interest (0.86) goes to 7000 (other income, outside 4xxx
revenue).

**Bank-booking hold lifted, 14 Sep 2026.** `gl_settings.bank_booking_on_hold` 1 → 0. I lifted it on my reading
of his "what i meant was for future months" and told him to say "keep the hold" to reverse it; he didn't. A
draft made while the hold was on is never auto-promoted.

**His ruling (founder_instruction 384):** *"if the agent cant read it then fix it"*. An unreadable statement is
a reader defect for the it_engineer, never a question for him. The live `resend_inbound` path first missed
statements and held the August one as a receipt (inbound_messages #152); PR #676 routes both paths through one
reader.

Related: [[the-accountant-only-sees-what-was-forwarded]], [[expenses-email-source-of-truth]],
[[never-state-what-you-have-not-measured]].
