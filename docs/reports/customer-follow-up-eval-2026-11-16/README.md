# Customer follow-up scenario bank, paid run of 16 Nov 2026 (customer_support, ledger 1711)

Bank: `scripts/eval/customer_follow_up_bank.mjs` (51 scenarios). Runner: `scripts/eval/customer_follow_up/run.ts` (WhatsApp
compose + modelSays through the production gateway, judge of another family). Facts: the bank's ZZ DEMO fixture on a LOCAL
Postgres 16, never production. Total spend USD 0.97 of the USD 1.50 cap, three run tags:

| run | tag | scenarios | passed | USD | note |
|---|---|---:|---:|---:|---|
| smoke | qd_run:evalcfdabea6d5ff | 2 | 0 | 0.108 | found the reply guard stripping "AED 4,600" (facts held a bare 4600) -> `price_as_shown` |
| 1 | qd_run:evalcfaa9c9815c5 | 18 of 51, stopped | 2 | 0.176 | found aiReply reading only 6,000 characters of the facts -> `FACTS_MAX_CHARS` 16,000 |
| 2 | qd_run:evalcf01f2687d31 | 51 | 25 | 0.686 | `run.json` (every reply, code grade and judge verdict) |

## Run 2: why the 26 failures failed (read from run.json)
- **The question names no request** and the fixture customer has five open ones (7): en_a_or_b, en_one_quote_price,
  en_cheapest, en_eur_budget, en_remember_date, gulf_remember_budget ask which one he means; en_what_next picked the wrong
  one. In a real chat the earlier turns or the case name it; the bank sends one message alone. Next run: give each scenario
  one prior turn naming its request.
- **The judge, not the reply** (8): three judge calls cut at the gateway deadline twice (en_paint_late, en_negotiate,
  gulf_why_one); en_what_did_b_ask was failed for "naming Supplier B" (a letter, not an identity); en_validity, en_who_is_a,
  gulf_supplier_number were failed for "inventing" details of his other requests that are in the facts (the judge saw only
  their summaries); en_zero_quotes for a UTC date.
- **Real reply defects** (11): an invented edit window or "free cancellation" / "quotes cannot be revised" on a change or
  cancel (en_cancel, en_add_units, arabizi_add_units, gulf_cancel, en_over_budget_options; in production the database's
  answer for change_request / cancel_request rides with these turns, the eval did not give it); an omitted fact the criteria
  required (en_why_one_quote "late", en_when_quotes "3 suppliers", en_usd_budget currency note, ar_with_vat 4,830); one empty
  reply (en_remember_budget); one English reply to Arabizi (arabizi_paint_status).

No reply named an unrevealed supplier, gave a planted phone or a planted brand (code grader, 51 of 51).
