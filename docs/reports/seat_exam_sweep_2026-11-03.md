# Seat-exam full sweep — 3 Nov 2026

Assigned: **ceo** (company knowledge). Qualification matrix gap #13 / row E14 (`docs/release/qualification_matrix.md`):
*"Seat exams cover 18 of 633 items."* This sweep asked all **641** items (633 seat-exam items plus 8 trade-bank items),
graded them by code first, sent only what code could not decide to a calibrated judge, traced every failure to its
cause, fixed the source, and re-asked.

Pass bar (E14): **≥ 98% per seat, and 100% on money/terms/legal items** (241 of the 641, tagged by code from each
item's own words, `isMoneyOrTerms` in `scripts/eval/seat_exam_canon.mjs`).

## Result

**Before**: round 1, on the knowledge merged on `main` at `0ddfd1c`; every item asked once, graded by the final grader
(after the independent review's corrections, below).

| seat | asked | passed | rate | money/terms | bar |
|---|---:|---:|---:|---:|---|
| ceo | 119 | 112 | 94.1% | 55/58 | not met |
| customer_support | 96 | 81 | 84.4% | 17/27 | not met |
| sales_engineer | 130 | 127 | 97.7% | 40/41 | not met |
| accountant | 109 | 108 | 99.1% | 76/77 | not met |
| it_engineer | 109 | 106 | 97.2% | 18/19 | not met |
| marketing | 78 | 71 | 91.0% | 16/19 | not met |
| **all** | **641** | **605** | **94.4%** | **222/241** | 0 of 6 seats |

**After**: this branch's knowledge; each item at its latest asking (rounds 2 to 6).

| seat | asked | passed | rate | money/terms | bar |
|---|---:|---:|---:|---:|---|
| ceo | 119 | 119 | 100.0% | 58/58 | met |
| customer_support | 96 | 96 | 100.0% | 27/27 | met |
| sales_engineer | 130 | 130 | 100.0% | 41/41 | met |
| accountant | 109 | 109 | 100.0% | 77/77 | met |
| it_engineer | 109 | 109 | 100.0% | 19/19 | met |
| marketing | 78 | 78 | 100.0% | 19/19 | met |
| **all** | **641** | **641** | **100.0%** | **241/241** | 6 of 6 seats |

How to read the "after" table:

- **It is a composite, not one run.** Every re-ask used a fresh wording, written blind to the key.
  - Round 2 re-asked 142 items: every round-1 failure, every item whose expected entry or key had changed, and a
    seeded 15% sample of the other passes.
  - Rounds 3 and 4 re-asked the failures left after the item and entry fixes.
  - Round 5 re-asked the 11 items the independent review's fixes touched.
  - Round 6 re-asked accountant-exam-12 after the settled facts were clarified.
  - Every other item keeps its round-1 pass.
- **The robustness number is the regression sample.** Of the 106 round-1 passes re-asked in a new wording, **104 still
  passed (98.1%)**. ceo-exam-112 and marketing-exam-54 flipped to a fail, then passed again in round 3. Re-asking
  failures until they pass flatters a score; this sample is the honest estimate. On an unseen wording, a seat drops
  about 2% of the items it had passed.
- Round by round (composite after each, `knowledge/exams/judged/2026-11-03-sweep/<round>.json`):

  | after round | items asked | passed | composite | money/terms | seats at bar |
  |---|---:|---:|---:|---:|---:|
  | 2 | 142 | 131 | 630/641 | 234/241 | 1 |
  | 3 | 10 | 9 | 638/641 | 239/241 | 4 |
  | 4 | 1 | 1 | 639/641 | 240/241 | 5 |
  | 5 | 11 | 11 | 641/641 | 241/241 | 6 |
  | 6 | 1 | 1 | 641/641 | 241/241 | 6 |

## How it was run, and its boundary

`scripts/eval/seat_exam_sweep.mjs` (`audit | prepare | grade | rejudge | score | calibrate-prepare | calibrate`).

**The seat.** The seat is stood in for by a model on the founder's subscription (the Claude Code subagent `sonnet` model),
given exactly what `think()` gives an internal seat:

- the **settled facts**: `knowledge/brief/company.md`, `knowledge/brief/seats.md` and the seat's card
  (`think.ts settledFacts`);
- six **sources**, each cut at 2,400 characters (`think.ts EXCERPT_MAX`).

It was told to answer only from those, in 40–250 words. Each batch file held no key, rubric or expected fact.

**Grading: code first** (`gradeAnswer`):

1. **Canon.** An answer that contradicts the canon fails, and no judge can overturn it. The canon is
   `src/content/company_facts.json` (via `scripts/legal/company_facts.mjs`), plus value and forbidden claims from
   company.md, seats.md and COMPANY_CANON.md, each claim naming its source line (`scripts/eval/seat_exam_canon.mjs`).
2. **Facts.** Every expected fact must be present (case, punctuation and hyphens ignored).
3. **Figures.** Every AED amount and percentage must appear somewhere in what the seat was given.

Code passed 424 of 641 in round 1 and failed 8 on the canon. The other 209 went to the judge.

**The judge** is an independent model run. It sees the question, the rubric (`answer_must`), the key facts, the
reference entries and the answer; it never sees the answering prompt. It is used only after passing calibration:
`tests/fixtures/seat_exam_judge_calibration.json`, 25 correct and 25 planted-error answers over 25 real items (all six
seats), written by hand. The bar is ≥ 48/50 right and ≤ 1 good answer flagged (matrix §4).

- **Rule v1: 50/50, 0 flagged.**
- **Rule v2: 50/50, 0 flagged.** The rule was corrected mid-run (see "grader corrections" below) and recalibrated
  before use.
- Both sets of verdicts are in `knowledge/exams/judged/2026-11-03-sweep/judge_calibration.json`.

**What this does NOT measure. Read every score with these limits:**

- **Retrieval rank.** The live embedder (gte-small, via the project's gateway) is not reachable from a cloud session,
  and nothing here touched production. Each item's six sources were its expected entries plus the nearest other
  entries of the same pack by BM25. Whether gte-small puts the expected entry in the top 5 is measured by
  `scripts/eval/seat_qualification_exam.mjs` and row E15, not here.
- **The production model and pipeline.** Answers came from a subscription model reading the same inputs, not from
  `think()` (decompose, retrieve, synthesise, verify) on the gateway's model. The model-on exam
  (`seat_exam_llm_on.mjs`) needs `SUPABASE_ACCESS_TOKEN` and the gateway; OpenRouter is on hold.
- **The source library was shared within a batch (rounds 1 and 2).** A question's file also showed the sources handed
  to the other questions in its batch. One answer (ceo-exam-65, round 2) quoted a correct pack figure that was not
  among its own six sources. Rounds 3 and 4 used one question per file. The effect is that the sweep measures what
  the seat's pack holds, slightly more generously than retrieval would.
- **Arabic.** Every wording was English. The Arabic bodies were corrected wherever the English was, but not examined.

## What was wrong, and what was fixed

Every round-1 failure was traced to its cause against the entry the seat was handed. The same applies to rounds 2
and 3, and to the code audit of the knowledge itself. Causes:

- **K**: the knowledge was wrong, contradictory or missing.
- **I**: the item was wrong.
- **S**: the seat omitted a point its source held.
- **G**: the grader was wrong.

### 1. The knowledge contradicted the signed terms (code audit, before any model was asked)

`seat_exam_sweep.mjs audit` found **84 contradictions on main, 0 on this branch** (English and Arabic, with the final
detectors):

- **"Automatic" refunds.** 22 served seat-pack entries said a silent supplier's refund is "automatic", in English and
  Arabic, across ceo, customer_support, accountant, it_engineer and marketing (for example
  `customer_support:supplier-non-response`, `ceo:company-hard-rules`, `marketing:company-pricing-message`).
  `customer_support:refund-timing-and-tracing` said "The CEO seat approves refunds **except** the automatic
  non-response refund".
  - The signed Customer Terms v11 clause 5: "Every refund is decided by QuotesDone … **no refund is automatic**". The
    customer need not ask; the ladder runs from payment.
  - All 22 entries now say: refunded in full without the customer asking, decided on the record by the CEO seat, never
    automatic.
  - In round 1, 7 answers repeated the error and failed on the canon.
- **Interest date.** Two accountant entries (`non-response-charge-accounting`, `company-pricing-and-fee-arithmetic`),
  and the accountant card, said the non-response interest runs "from the refund date". company.md §5 and Supplier
  Agreement clauses 31 and 33 say it runs from the due date (payable within 7 days of notice). accountant-exam-12
  repeated the error in rounds 1 and 2, and passed in rounds 5 and 6.
- **The v14 boundary.** seats.md and COMPANY_CANON cited "Supplier Agreement v15 clause 33" and listed v13 and
  v10–v12, so v14 was named nowhere; an answer said 12% applies "from v15". They now say clause 33 is the same from
  v14 to the current v17 (`company_facts.json`: 9% is v13 or earlier).
- **Refund timing.** Four entries said banks show a refund in "5 to 10" days; the Terms say 7 to 14 working days.
  `accountant:stripe-refunds-accounting` now quotes Stripe's own 5–10 beside the figure QuotesDone gives a customer.
- **COMPANY_CANON.md** described "10 departments", and said the founder gives final approval on refunds and that
  customers launch on "3 trades in Dubai". These are now re-grounded on seats.md and company.md: six seats, every
  approval the CEO seat's, customers from January 2027.
- **customer_support-exam-84** expected "5 to 10 business days". The item was wrong; it is corrected to the Terms'
  figure, with the clause cited.
- The seat cards (`knowledge/brief/seats/*.md`) and `brief.generated.ts` were recompiled from the corrected packs.

### 2. Knowledge defects found by the answers (K)

| item | defect | fix |
|---|---|---|
| accountant-exam-22 | `accountant:anti-circumvention-penalty-accounting`, `ceo:company-hard-rules` and `accountant:company-hard-rules` merged two clauses into "no off-platform contact … AED 20,000" | Supplier Agreement clause 10 (sharing contact details, AED 10,000 per incident) and clause 24 (taking a customer off-platform, AED 20,000 or 5× the fee, 24 months) are now stated apart |
| ceo-exam-08 | `ceo:llc-manager-duties-and-liability`, `ceo:llc-legal-form-basics` and `ceo:cap-table-hygiene` (and the ceo card) treated QuotesDone as an LLC with a Memorandum and a manager | QuotesDone Technologies is a Sole Establishment (Terms preamble, company.md §1); only its owner or his written delegate binds it |
| ceo-exam-26 | `ceo:premortem` gave mitigations no owner | owner seat and date per mitigation (from `ceo:risk-register`) |
| ceo-exam-28 | `ceo:risk-register` scored 1–5 while `ceo:risk-scoring-matrix` scores high/medium/low; neither gave a review date | one scale, plus status and a next-review date per line |
| ceo-exam-52 | `ceo:weekly-management-review` listed "seat scorecards" with no order or verdict | inputs first, then outputs, then a verdict per seat (from `ceo:input-vs-output-metrics`, `ceo:seat-scorecard`) |
| ceo-exam-100 | `ceo:ai-seat-governance` did not say reserved decisions are blocked in code, and its Arabic body lacked the accountability sentence | added (from the card and `ceo:automated-decision-governance`) |
| customer_support-exam-70 | `customer_support:consumer-or-commercial-buyer` said the Terms apply "identically" to a consumer and a company; `cpl-consumer-definition-b2b` told support never to decide which one is asking | Customer Terms clauses 15 and 22 define a business customer and charge it differently; both entries now say so |
| customer_support-exam-81 | `customer_support:incident-communication` said "holding reply in EN and AR" for everyone | suppliers always receive English (seats.md, FI 1008) |
| customer_support-exam-74 | `customer_support:service-vs-marketing-message` scattered the three obligations of a marketing message; failed in three wordings | stated together: consent (Terms clause 10), a WhatsApp marketing template, and Cabinet Resolution 56/2024 |
| it_engineer-exam-99 | `it_engineer:webhook-idempotency-ordering` (never order any provider's events by created time) contradicted `it_engineer:resend-webhooks-delivery` (Resend: sort by created_at when order matters) | the Stripe rule is scoped to Stripe; the key follows |
| it_engineer-exam-81 (secondary) | `it_engineer:sli-slo-sla` said no SLO is set, while the job description sets 99.9% for every core journey | states both |

Every fix is in English and Arabic.

### 3. Item defects (I): the asked wording did not ask what the rubric grades

This was the most common cause: **18 items** (14 rewordings, 2 rubric points removed, 2 keys corrected). The rubric was written for `q_en`, but the rewording asked something
narrower or different (another audience, one slice, or a false premise). A correct answer to the wording asked
therefore failed.

Corrected wordings (rubric kept, wording now asks what q_en asks):

- sales_engineer-exam-98;
- customer_support-exam-68, -75, -80 and -92;
- ceo-exam-65 and -76;
- marketing-exam-56, -69, -70 and -72;
- accountant-exam-22: its rewording asked about clause 10 while its key graded clause 24;
- se-trade-22 and se-trade-24: each of their three bank wordings asked one slice of a two-point rubric.

Rubric points asked by neither q_en nor the rewording, removed with that evidence:

- marketing-exam-53;
- marketing-exam-76 point 3.

Keys that graded something the knowledge does not say:

- it_engineer-exam-72: "should not page" is stated nowhere in the repository; the entry's rule is a postmortem
  action.
- customer_support-exam-81: an Arabic reply to suppliers contradicts the always-English ruling.

**This class is not closed by this sweep.** Only the items that failed were examined. Other items may carry a drifted
rewording that the seat happened to answer anyway. A check that every rubric point is asked by every wording would
need a reader; it is recommended, not built.

### 4. Seat omissions (S)

The point was in the handed source, and the seat left it out. These items were re-asked in fresh wordings and
passed:

- ceo-exam-112 (a round-2 regression flip);
- customer_support-exam-73, -82 and -85;
- it_engineer-exam-81;
- marketing-exam-54.

### 5. The independent review

Before the PR, an independent agent reviewed the whole diff against the governing texts, re-running probes.

- It found **18 problems**: 8 in the grader, 6 in changed passages, 2 in the Arabic, 2 in items.
- Every one was fixed, the affected rounds were re-graded, and the items they touched were re-asked (round 5).
- The grader findings are listed under G below.
- The knowledge findings are in sections 1 and 2:
  - interest from the due date;
  - `ceo:automated-decision-governance` listing refunds as founder-reserved;
  - the LLC entry's remaining manager and Memorandum points;
  - an Arabic bullet that had never been translated.
- The item findings: marketing-exam-53 and -76 get their removed rubric points back, with rewordings that ask them,
  so that one policy applies to every such item: keep the rubric and make the question ask it.

### 6. Grader corrections (G)

Each correction was made with evidence and has a test case in
`scripts/checks/the_seat_exam_sweep_grades_by_the_canon.test.mjs`.

- **Legacy figures.** Two correct accountant answers failed by code. AED 250 and 9% for a supplier on v12 is what that
  supplier signed (`company_facts.json` `legacy`); "the processing cost is booked separately" is not a surcharge.
  Fix: a legacy figure counts only when it is named within 250 characters of its version.
- **Judge rule v1.** The judge failed answers for stating settled facts it could not see, such as the TDRA NOL number,
  the day-3/day-5 ladder and the January 2027 launch. Code already traces every figure against everything the seat
  was given.
  - Rule v2: fail a statement only if it contradicts the reference or the rubric.
  - Recalibrated at 50/50, 0 flagged.
  - The 40 cases the judge had failed were re-judged; 12 passed. A rule that only removes a reason to fail leaves every
    pass a pass, so nothing else was re-judged.
- **Answer length.** The first answering rule capped answers at 160 words; production synthesis allows about 900
  output tokens. The cap is now 250 words.
- **From the independent review.** Each item below has a test case.
  - The figure check matched a bare number anywhere in the ~25k-character context, so an invented "2% handling fee"
    passed. It now compares figures, against the batch file the seat was actually shown.
  - The refund detector missed "processed / happens automatically", "refunds you automatically" and "money back
    automatically", and spanned commas. It now catches them; only the ladder or clock running by itself is excused.
  - Negation now stops at the clause, so "Don't worry, the refund is automatic" is caught, and a question is not a
    claim.
  - "The founder is notified after the CEO seat approves" no longer reads as a founder decision.
  - A legacy figure is excused only by the version named nearest to it.
  - Arabic is now audited too.
  - Re-grading every round with the corrected grader moved 6 round-1 verdicts:
    - accountant-12 failed on the canon (the interest-date error);
    - two items whose "AED 20" could no longer be traced went to the judge, which passed both;
    - three became code passes.

## Model spend

All on the founder's subscription; nothing on OpenRouter, the gateway or any paid API.

- **46 subagent runs, 6,947,307 tokens** in total, as the harness reports them (`subagent_tokens`, including what each
  agent read).
- By role:
  - answering seats: 21 runs;
  - judge: 17 runs, including 3 calibrations and 1 re-judge;
  - blind wording writers: 5 runs;
  - failure diagnosis: 2 runs, and the independent review: 1 run, all three on the session model; everything else on
    Sonnet.
- Not counted:
  - 5 answering agents stopped seconds after launch, when round 1 was re-prepared from `main`; their usage was not
    reported;
  - the orchestrating session itself.

## Files

- `scripts/eval/seat_exam_sweep.mjs` (the sweep) and `scripts/eval/seat_exam_canon.mjs` (the code grader for company
  facts).
- `scripts/checks/the_seat_exam_sweep_grades_by_the_canon.test.mjs`, offline. It fails if any seat-pack entry, card,
  brief, canon or exam key contradicts the canon again, or if the grader or calibration rule weakens.
- `tests/fixtures/seat_exam_judge_calibration.json`: the 50 labelled cases.
- `knowledge/exams/judged/2026-11-03-sweep/{before,after,r3,r4}.json`: every item asked, with its wording, its six
  sources, the answer, the verdict, and who decided it (code or judge, with the judge's note).

To reproduce, start with the code audit:

```bash
node scripts/eval/seat_exam_sweep.mjs audit
```

Then prepare the batches, answer them, grade, judge, and score:

```bash
QD_SWEEP_BATCH_CHARS=200000 node scripts/eval/seat_exam_sweep.mjs prepare --dir <D>
node scripts/eval/seat_exam_sweep.mjs grade --dir <D>
node scripts/eval/seat_exam_sweep.mjs score --dir <D> [--carry <D_prev>,<D_prev2>]
```

Between `prepare` and `grade`, a subscription model answers `<D>/batches/*.md` into `<D>/answers/`. Between `grade`
and `score`, the calibrated judge answers `<D>/judge/*.md` into `<D>/judged/`.

## Open: one conflict between the Terms and the brief

Customer Terms v11 clause 5 (and Refund Policy v1.9) say a refund is decided "by QuotesDone under its published rules,
by the QuotesDone operations team using automated tools", and that the operations team makes the day-5 final contact
attempt. company.md §5 tells the customer-facing seats: "day 5 the case goes to QuotesDone's CEO for a final call …
Every refund is decided by QuotesDone's CEO". seats.md says the same internally.

This branch follows company.md and seats.md, since the seats speak from them. Both texts agree that no refund is
automatic, and that is what was fixed. They differ only on whom to name to a customer. That is the wording of a signed
legal text, so it is not changed here. To settle it, company.md §5 should either quote the Terms' wording or the Terms
should name the CEO.

## Not done here, on purpose

- **No production change.** The corrected packs reach the seats only when they are loaded into the seat tables after
  merge (`scripts/kb/load_verified_packs.mjs`). Until then, production seats still read the old text, including
  "automatic" refunds. Loading them is the first thing to do after merge.
- **The model-on exam through `think()`** (`seat_exam_llm_on.mjs`), which also covers retrieval rank, the gateway model
  and Arabic, still waits on a management token and the gateway.
