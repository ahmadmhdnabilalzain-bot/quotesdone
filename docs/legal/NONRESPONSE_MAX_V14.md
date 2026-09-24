# The non-response charge at the maximum UAE law safely allows — Supplier Agreement v14

Seat: ceo (legal). Founder ledger 965 (23 Sep 2026) and 990 (24 Sep 2026: "collect the maximum possible for
damages that UAE law safely allows (admin fee, interest, recovery costs)"). UAE federal law only. Written 24 Sep 2026.

## 1. Sources, and what was read on the primary text

| Instrument | Read how | Status |
|---|---|---|
| Commercial Transactions Law, Federal Decree-Law 50/2022 (CTL), official EN PDF from u.ae (assets.u.ae/api/public/content/79793d384f884bccb59171817ba1e9d4) | text extracted this session, Arts 69–92 read in full | **primary, verified today** |
| Civil Transactions Law, Federal Decree-Law 25/2025 (in force 1 Jun 2026), Art 340(1)–(5) | quoted verbatim from uaelegislation.gov.ae/en and /ar/legislations/4011 on 14 Sep 2026 (docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md §3f) | primary, verified 14 Sep; re-fetch today blocked by the site's Cloudflare (HTTP 403), not re-read |
| Same, Art 340 | Mondaq and ABS Partners summaries read today | secondary, consistent with the 14 Sep reading |
| Dubai Courts service C5 (payment order) fee | dc.gov.ae, read 14 Sep (same doc §8.5) | primary, 14 Sep |
| Civil Procedure Code, Federal Decree-Law 42/2022 — which article awards costs to the losing party | not read | **not verified**; the clause does not cite it |
| Old Commercial Transactions Law, Federal Law 18/1993 Art 76 (12% ceiling where no rate agreed) | memory of secondary sources only | **not verified**; used only as background below, never in the clause |

## 2. Findings

### a) Pre-agreed compensation (the admin fee) — Civil Transactions Law 25/2025 Art 340
- 340(1): the parties may fix compensation in advance in the contract.
- 340(2): the court may REDUCE it only if the debtor proves the estimate was excessive, or that the obligation
  was partly performed. The burden is on the supplier. The old law (5/1985 Art 390) let the judge adjust the sum
  to equal the actual loss on either party's application; the new text is narrower.
- 340(3): it may be reduced where the creditor's own fault contributed.
- 340(4): the creditor may claim MORE than the agreed sum only on proof of fraud or gross fault.
- 340(5): an agreement against the article is void, so the clause may not exclude the reduction power.

**What makes a fixed fee defensible:** that it is a genuine pre-estimate of a real cost the clause names, and
that it is not a disguised penalty for a sum the law already gives. A fee above the real cost is the exact case
340(2) lets the supplier attack.

### b) Late-payment interest — CTL 50/2022 (read today)
- Art 72: interest on a commercial loan is at the rate the contract states; only where NO rate is stated is it the
  market rate "provided that it does not exceed (9%)". **9% is the no-agreement ceiling, not a ceiling on an
  agreed rate.**
- Art 73: where a rate is stipulated and the debtor delays, delay interest runs at the agreed rate until full
  repayment.
- Art 84: a commercial obligation that is a sum of money, certain when created, carries the Art 72/73 interest
  on delay "unless otherwise agreed".
- Art 85: no proof of damage is needed. Art 86: interest runs from maturity.
- Art 87(1): compensation beyond the delay interest only on proof of the debtor's deception or serious error;
  87(2): bad-faith prolonging of the dispute lets the court cut the interest.
- Art 88: no compound interest.
- No cap on an AGREED rate appears in Arts 69–92, and no "interest may not exceed principal" rule.
- **Reading note.** Art 72 is written for a commercial LOAN. The clause cites it for its rule that an agreed rate
  governs, and Art 84 carries Arts 72/73 over to any certain commercial sum of money paid late. So the 12% stands mainly
  on Arts 73 and 84, with Art 72 read through Art 84. The "or the maximum permitted by UAE law if lower" words mean
  the worst case is a cut to 9%, never nothing.
- **Wording in the clause (review, 24 Sep).** Art 87(1) in the official English says "deception or serious error";
  the Arabic clause says تدليسًا أو خطأً جسيمًا. Arabic prevails, and that is the statute's own Arabic sense.

**Choice: 12% simple per annum.** The statute sets no ceiling on an agreed commercial rate, so any rate is
lawful on the text. "Safely" limits it: a judge who treats delay interest as compensation could apply
340(2) to a rate that looks punitive. 12% keeps a clear margin above the 9% statutory fallback while staying at
a level UAE commercial practice treats as ordinary (the 1993 law's own no-agreement ceiling was 12% — background
only, not verified on the primary text, and not cited in the clause). A higher figure (18%, 24%) would be lawful
on the text, but it would put the whole interest line in the zone a court reduces. Not compounded (Art 88).

### c) Recovery costs, proven extra loss, set-off
- **Official recovery fees** (court and payment-order filing fees, execution fees, notary or attestation fees for
  a formal notice) are sums QuotesDone actually pays. The Dubai Courts C5 payment-order fee is 6%, minimum
  AED 500; a notarised notice costs AED 200 plus AED 100 per signature. These are actual, receipted costs, not a
  pre-estimate, so 340(2) ("the estimate was excessive") does not reach them. **Added.**
- **Lawyer or collection-agency fees are NOT added.** CTL Art 87(1) allows compensation beyond delay interest
  only for deception or serious error. A general contractual fee on top of interest invites exactly that
  objection, and QuotesDone uses no lawyer.
- **Further proven loss:** kept open only where the statute allows it: 340(4) (fraud or gross fault) and CTL
  87(1) (deception or serious error). The clause states both, so nothing is waived, and it claims nothing the
  statutes refuse. **Added as a preservation sentence.**
- **Set-off:** QuotesDone holds no supplier funds, but it may come to owe a supplier a sum (for example a
  subscription credit or refund). Agreed set-off between two merchants' certain, due debts is ordinary
  contract. v10–v13 said "no set-off against held sums applies". v14 lets QuotesDone set off any sum it owes
  against the charge. **Added.**

### d) The unrecovered card-processing fee — an ACTUAL loss the supplier causes
Since 24 Sep 2026 no buyer pays a card fee (Cabinet Res. 66/2023 Art 5(3)), so v13 (a) is the reveal fee only.
But QuotesDone still paid Stripe's fee on the reveal payment. Stripe keeps that fee when a payment is refunded,
so a refund the supplier causes costs QuotesDone that fee on top of the refunded amount. It is recorded per
payment (`transactions.stripe_fee_fils`). It is a measured loss, not an estimate, so 340(2) does not apply to it.
**Added as (b), for v14 signers.**

## 3. The admin fee: why it stays AED 500
The real cost of a non-response refund, from our actual process (the refund ladder, collections and the
accountant seat):

| Step | Who does it | Cash cost |
|---|---|---|
| Day-3 chase, copy to the customer | customer_support seat, email + WhatsApp template | fils (Resend and Meta per-message) |
| Day-5 final call | ceo seat, call over Twilio | a few AED per call |
| Refund | accountant seat through Stripe | the processor fee Stripe keeps: now charged at cost as (b) |
| Charge notice, reminders 1 and 2, final demand | accountant seat, supplier_charge_documents.ts, delivered by customer_support | fils per delivery |
| Books, dues ledger, follow-up to payment or court | accountant seat | seat time |

Most of the handling is automated. The only material cash cost (Stripe's fee) is now claimed at its actual value.
On these numbers AED 500 is already a generous pre-estimate of handling and seat time. **Raising it would put it
in the 340(2) "excessive" zone with no cost to point to, so it stays at AED 500.** The v14 clause says the AED 500
does not include the processor's fee, so the two can never be argued as double recovery.

## 4. Recommended package (v14), and what a v13-or-earlier supplier owes

| Head | v14 (accepted before the reveal) | v13 | v12 and earlier |
|---|---|---|---|
| (a) exact amount refunded | yes | yes | yes (incl. the card fee a pre-24-Sep buyer paid) |
| (b) processor fee QuotesDone could not recover | **yes, at cost** | — | — |
| (c) administrative fee (Art 340(1)) | AED 500 | AED 500 | AED 250 |
| (d) simple interest from the due date | **12% p.a.** | 9% | 9% |
| official recovery fees on default | **yes, at cost** | — | — |
| set-off against sums QuotesDone owes | **yes** | no | no |
| further loss on fraud / gross fault / deception | stated (the statutes give it anyway) | statute only | statute only |

**Never retroactive.** Each head is the one in the version the supplier had accepted when the customer revealed
it. `fn_accountant_nonresponse_charge` and `supplier_charge.ts` `termsAt()` apply the same rule. v14 takes
effect for a supplier only on re-acceptance: the portal asks, and clause 23 gives 30 days' notice of a material
change.

## 5. Residual risk, stated
- A court could treat 12% as agreed compensation under 340(2). The supplier then carries the burden of proving it
  excessive; the fallback is the 9% statutory rate, never zero.
- The "sum certain" point (CTL Art 84, payment-order route) is unchanged from v11–v13. The notice fixes the sum,
  and (b) is read from Stripe's record, so it is certain when the notice issues.
- The article of the Civil Procedure Code that awards costs was not read. The clause relies on the contract for
  official fees, not on that article.
