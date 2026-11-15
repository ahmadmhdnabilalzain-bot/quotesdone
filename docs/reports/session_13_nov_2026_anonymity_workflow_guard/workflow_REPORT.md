AUDIT: does a paid reveal reach every seat that has a step in it? Short answer: no. Production has never shown the chain working. Production was only read, never written. Code read at origin/main 2cef71f27. Skills used: quotesdone-work-is-assigned (live seats read), quotesdone-session, quotesdone-organised-like-an-auditor-will-read-it.

Most serious first:

**1. There is no production evidence of the chain.**
- Production keeps ONE paid reveal: tx 29ac49f5, 21 Sep, ZZ DEMO, test mode. Stripe logged 69 checkout.session.completed and 75 invoice.paid.
- The last 3 paid reveals (12 Nov 00:02 AED 3,212.97; 11 Nov 23:45 AED 286.62; 11 Nov 23:26 AED 223.68) were torn down: no transaction, quote, notification, GL or CEO row is left.
- What survives: their accountant_reveal_reconcile_item rows (mislabelled `test_mode_not_demo`, 10 attempts each, never resolved) and about 24 customer_support delivery handoffs closed in the same second.
- `fn_seat_handoff` files nothing for a demo payload (ruling 1199). The last `handoff.reveal.paid.sent` was on 18 Oct, so no rehearsal can show the chain after the fact.

**2. The chain, step by step.**

| step | who | does he | evidence |
|---|---|---|---|
| Invoice issued and sent | customer | PARTLY | The invoice stored at sale is Stripe's own PDF (doc_kind stripe_invoice). Our template (_shared/reveal_fee_documents.ts) is rendered only on click (reveal_invoice/index.ts:85-98); reveal_invoices has 0 rows. reveal_receipt and invoice_ready go by email and WhatsApp with no attachment. The trace shows invoice_ready sent 3 times and reveal_receipt 2 times on WhatsApp (retries). |
| Told the payment arrived | accountant | NO | trg_reveal_receipt sends reveal.paid FROM accountant TO sales_engineer. payment_handoffs.ts has no reveal kind addressed to the accountant. The trace has 0 handoffs to the accountant. |
| Uses judgement | accountant | PARTLY, code only | Hourly reconcile (reveal_reconcile.ts) and a duplicate-payment finding (reveal_sale.ts:81-93). The accountant made 0 model decisions on any reveal (365 of its 366 judgements in 30 days are think.answer). On 29ac49f5 its charge_audit found an AED 38.77 surcharge, answered "playbook has no deterministic remedy" and closed it 33 days later with no refund (agent_actions 100357). |
| Books | accountant | NO, never run | 0 reveal_fee journals ever, because fn_gl_fixture_or_orphan excludes demos. The posting logic is right when it runs (Dr 1050 net / Dr 6100 fee / Cr 4000, immutable, no VAT line). But it does not name the invoice, leaves out the Invoicing fee, and does not defer revenue (2400 unused). A refund posts Dr 6900 / Cr 1050. By hand for 29ac49f5: 25,920 × 3% = 777.60 plus the old 38.77 surcharge = 816.37; expected Dr 1050 781.89 / Dr 6100 34.48 / Cr 4000 816.37. Actual: none. |
| Refund window | accountant, sales_engineer, ceo | PARTLY | The clock counts 5 working days from revealed_at (trg_reveal_window). revealed_at is set to `new Date()` at insert (reveal_sale.ts:51), not Stripe's paid time, so a late webhook starts the window late. The supplier_response_watch, the day-3 chase and the day-5 CEO decision exist. The customer is never given an end date: the receipt wording is relative and the PDFs print no date. |
| Told of the sale | ceo, founder | NO, a count only | report.five_numbers (ceo to ceo, demo excluded) and the founder brief line ("Customers who paid a reveal fee: none today", 12 Nov). |
| Learns paid and which supplier | sales_engineer | YES, as code | A fixed plpgsql template, fn_sales_engineer_acts_on_handoff (mirror 09_functions_fn_s.sql:522). |
| Request closed | sales_engineer | NO | Status becomes 'revealed' with outcome null (reveal_sale.ts:65-71). |
| Other suppliers told | sales_engineer | NO, not at payment | fn_sales_engineer_tells_losing_suppliers runs only on a hire. |
| Chosen supplier told | sales_engineer | YES | quote_accepted by email and WhatsApp. |
| Follow-up | sales_engineer, customer_support | PARTLY | The day-3/day-14 "did you hire?" tick. |
| Failed or late webhook | customer_support, it_engineer | PARTLY | "PAID BUT NOT RECORDED" is only an agent_runs log line (stripe_webhook/index.ts:343-345). The hourly reconcile heals it. Nobody tells the customer. |
| Disputes, refunds | accountant, ceo | PARTLY | Disputes: fn_accountant_dispute_record (0 in production). Refunds: refund.paid goes to sales_engineer; the CEO hears only if he approves. |

**3. Refund policy wording.** The refund policy says the non-response refund ladder "runs automatically from the moment you pay". Terms v11 says "no refund is automatic". The two documents contradict each other; I quoted them, I did not judge legality.

**4. VAT and the fee base (1687): correct on every door I tested, with weak points.**
- Every charge path computes revealCharge(quotes.quote_amount), and storedPrice (stated_price.ts:180) sets quote_amount to the ex-VAT figure after any discount.
- I ran 13 offline cases with deno. Inclusive with a stated rate, subtotal plus VAT, "exclusive" in words, not registered, discount before VAT, discount after VAT, and "do not include VAT" all came out ex-VAT. Silence and inclusive-without-a-rate are held, and canReveal refuses a held quote.
- Weak points:
  - A held quote stores the VAT-inclusive total in quote_amount, and the portal shows a fee computed from it. Only the hold stops a charge on the gross.
  - Zero-rated or exempt quotes are held as "not stated".
  - The typed form has no currency field.
- I found no path that charges 3% of a VAT-inclusive figure on a quote that can be revealed. All 3 quotes in production have quote_amount = price_ex_vat.
- The invoice says: "QuotesDone Technologies is not registered for VAT; no VAT has been charged on this amount." No TRN, never "Tax Invoice".
- The comparison ranks on ex-VAT figures throughout (quote_compare/index.ts:275).
- Side finding in the books: account 1150 VAT Recoverable holds AED 288.31 of expense VAT. A company that is not VAT-registered cannot recover input VAT.

**5. The office (1688).** Six live seats.

| seat | model or code | 30-day judgements |
|---|---|---|
| customer_support | model replies, code delivery | 7,140 |
| sales_engineer | model in portals and quotes, code for the reveal step | 6,103 |
| marketing | model | 1,200 |
| it_engineer | model postmortems; its charter forbids it to act | 787 |
| ceo | model | 464 (AED 210.7 of model spend) |
| accountant | code on money | 366, almost all think.answer |

- **There is no shared pool.** company_event received 59,582 rows (84 types) in 30 days, but event_subscription has 0 rows, event_delivery has 0 rows, and fn_event_dispatch has no schedule.
- A seat's context is the static company brief, one person's case, and fn_case_recall of similar past cases. No seat sees what happened today across the company.
- **Handoffs, 30 days:** 24,050 in total; 14,962 (62%) closed within 2 seconds by the receiving SQL; 0 never picked up; 261 replied but not closed; 208 open past their reply window. Of those, 97 are it_engineer→ceo, 35 →sales_engineer, 28 →marketing, and all 4 sales_engineer→ceo escalations.
- **The founder's example:** verifying a supplier writes a supplier.approved event (4 in production). Nothing subscribes to it, so the IT engineer has no way to know.
- Plainly: the money chain is deterministic code with seat names on it. He is paying for model judgement in chat, quote reading, matching, CEO reviews and IT postmortems, not in the money chain.

**6. What to build** (most serious first; smallest real fix; owner):
1. it_engineer: a demo reveal records its handoffs and GL entry in a shadow tagged by run, kept through teardown until the check has read it.
2. accountant: a handoff TO the accountant on payment that reconciles invoice, PaymentIntent and balance transaction, and sends a mismatch to the CEO for review.
3. ceo: register a sale.made conversation from accountant to ceo, and list each sale in the founder brief.
4. accountant: store transactions.paid_at from Stripe and count the window from it.
5. accountant: put the invoice number in the journal, book the Invoicing fee, decide on deferral, and move 1150 into expense.
6. sales_engineer: on reveal.paid, set the request's outcome or pipeline, tell the other suppliers anonymously, and open the follow-up row.
7. sales_engineer: put the window end date (EN/AR) in the receipt and on the PDFs.
8. ceo: fix the "automatic" contradiction between the refund policy and the terms.
9. accountant: label torn-down rehearsal payments as such and resolve them.
10. sales_engineer: store a null quote_amount on a held quote, read zero-rated and exempt, add a currency field to the typed form.
11. ceo: subscribe seats to the event types they own, or drop the dead dispatcher.

**7. Tests.**
- What exists:
  - journeys.mjs: proves both parties are told, but only through a rolled-back probe.
  - drill_webhook_replay.test.ts: idempotency under duplicate and out-of-order delivery.
  - the_reveal_invoice…test.mjs: invoice filed once, one handoff, rolled back.
  - payments_are_the_accountant.test.mjs: ownership, list equality, the refund ladder rolled back.
  - every_report_and_handoff_comes_back.test.mjs: every originator-closed kind has a closer.
  - Unit tests for the fee and VAT readers.
- Nothing asserts: the CEO told, the accountant addressed or judging, a books entry, the clock starting at payment, the request closed, the other suppliers told, the end date sent.
- The new check is on branch `it_engineer-a-paid-reveal-is-known-to-every-seat-with-a-step`, commit f5ce86f4d, pushed, no PR.
  - Files: `scripts/it/a_paid_reveal_is_known_to_every_seat_with_a_step.gaps.mjs`, plus the fixture `scripts/fixtures/zz_demo_paid_reveal_trace_2026-09-21.json` (a read-only production capture with demo addresses removed).
  - Live mode reads only: REVEAL_TX=<uuid>.
  - The name is not *.test.mjs, so the gate does not pick it up.
  - Run: `node --test scripts/it/a_paid_reveal_is_known_to_every_seat_with_a_step.gaps.mjs`
  - Result: 17 tests, 5 pass, 12 fail.
  - The 5 HOLDS: fee = 3% of ex-VAT; sales engineer told and acted; support delivered and reported back; deadline = revealed_at + 5 working days; no VAT or TRN.
  - The 12 GAPS: accountant not addressed; no reconcile judgement; no journal; journal check cannot run; no invoice number in the ledger; clock starts at insert; CEO not told; request not closed; other suppliers not told; no follow-up row; no end date to the customer; demo leaves no chain.

**8. What I could not determine.**
- How many tokens a seat's prompt holds for one inquiry; measuring it needs a model call.
- Anything beyond the few surviving rows for the last 3 reveals; teardown deleted the rest.
- How far revealed_at lags the real payment; no paid_at is stored to compare.
- Whether the Stripe invoice PDF shows a tax line; I did not open it.

**Deviations from your brief:**
- I could not write REPORT.md: the harness refuses report files from a subagent. This message is the full report.
- I signed the commit `Co-Authored-By: Claude Opus 5.5` (the model that actually wrote it, per the session's attribution rule), not "Fable 5.2"; the Claude-Session line is as you gave it.
- The worktree /tmp/claude-0/audit-workflow is removed.