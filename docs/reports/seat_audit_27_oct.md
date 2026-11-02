# Seat audit against a senior human: 27 October 2026

Seat: **ceo**. Founder ledger **1003**, which asks for two stages:

> "Audit every seat against a real senior human expert in two stages. (1) Qualifications: define the qualifications and
> knowledge of a senior person in that role, measure our agent's actual qualifications, and state how senior it truly
> is. (2) Contribution: if we hired that senior human at QuotesDone, what would they do to help the company grow?
> Compare with what our agent does, and build what is missing. Agents exist to grow the company, not just run tasks.
> Never call a seat 'good to go' on opinion."

All numbers below were measured on production (`htdblwldjkcgjvmqkbeh`) on 27 Oct 2026, read-only or inside a
rolled-back transaction. Where a measure has a boundary, the boundary is stated.

## Verdict

**No seat is senior. All six are junior.** The deciding measure for every seat is stage 1, the exam. Each seat's real
models answered the reworded exam, and a reader graded every answer against its `answer_must`. No seat passes half of
its bank above 53%, and the bar for senior is 95%. On stage 2, three seats now have every senior contribution running.

| seat | level | stage 1: judged exam | stage 1: graded judgements (90 d) | stage 2: contributions live | stage 2: duties on clock | stage 2: own actions / handoffs sent (30 d) |
|---|---|---:|---:|---:|---:|---:|
| ceo | **junior** | 63 / 119 = 52.9% | none graded | 14 / 14 | 31 / 31 existing (+ the new verdict duty, not yet run) | 32 / 977 |
| sales_engineer | **junior** | 50 / 122 = 41.0% | 59 graded, **35.6% right** | 14 / 14 | 24 / 24 | 241 / 2,214 |
| accountant | **junior** | 53 / 109 = 48.6% | none graded | 16 / 16 | 23 / 23 | 15 / 91 |
| it_engineer | **junior** | 42 / 109 = 38.5% | none graded | 15 / 17 | 24 / 24 | 244 / 3,272 |
| marketing | **junior** | 38 / 78 = 48.7% | none graded | 9 / 15 | 9 / 10 | 56 / 35 |
| customer_support | **junior** | 35 / 96 = 36.5% | none graded | 8 / 14 | 6 / 6 | 25 / 3,026 |

How each level is decided (`fn_ceo_seat_senior_verdict`, and the same bars as `scripts/eval/seat_senior_audit.mjs`):

- **senior**: no shortfall at all. That means:
  - the exam is at or above 95%;
  - every senior contribution is live;
  - at least 95% of duties are on their clock;
  - at least 90% of windowed handoffs were answered in their window;
  - when 20 or more judgements have been graded, at least 80% were right.
- **mid**: the exam is at or above 80% and at least 90% of contributions are live.
- **junior**: anything else.

A missing measurement counts as not met. A seat with no judged exam cannot be mid or senior.

What each column measures:

- **Judged exam.** The source is `knowledge/exams/judged/<seat>.json`, the 19 Oct LLM-on run of
  `scripts/eval/seat_exam_through_think.ts` using reworded questions. The denominator is the whole bank, so an item that
  was never asked counts as not passed.
- **Graded judgements.** This is `seat_judgement.outcome_correct` over 90 days. Only sales_engineer's judgements are
  graded at all; for the other five seats, nothing grades a judgement against its outcome.
- **Contributions live.** A contribution is live when every duty named for it in `knowledge/standards/<seat>.json` is
  enabled and has run OK within twice its own clock plus a day.

## Method

1. **The standard.** `knowledge/standards/<seat>.json` (19 Oct) sets out what a senior human with 20 years in the role
   holds:
   - the qualifications;
   - the professional checklist each qualification rests on, where every item names the knowledge entries that hold it
     and the exam items that test it;
   - the contributions that senior hire would make to grow QuotesDone, each mapped to the `seat_duty` keys that make it.

   The 1003 stage-1 checklist is 100% backed by loaded knowledge and 100% examined for every seat. This was measured
   by `seat_senior_audit.mjs` against each seat's knowledge table.
2. **Stage 1, qualification:**
   - the judged exam;
   - the graded outcome accuracy of the seat's real decisions;
   - knowledge recall in English and Arabic (`seat_knowledge_recall`, latest day 22 Oct, informational).
3. **Stage 2, contribution:**
   - the senior contributions that are live;
   - duties on their clock;
   - handoffs answered inside their reply window, measured by the receiver's `detail.replied_at` (see finding 4);
   - re-verifications the seat owes as an originator;
   - the seat's own non-handoff actions;
   - the handoffs it sent.
4. **The weekly verdict now runs in production.** It is the `ceo.senior_verdict` duty, built in this PR. This report is
   its first reading, taken inside a rolled-back transaction before apply.

## Per seat

### ceo: junior

- **The senior standard.** The role is Chief Executive Officer of a UAE B2B procurement marketplace, with 13
  qualifications. They cover:
  - unit economics;
  - two-sided liquidity;
  - pricing evidence;
  - forecasting and the driver tree;
  - strategy and the binding constraint;
  - enterprise risk;
  - UAE tax and regulatory calendar;
  - UAE law;
  - first hires;
  - investor readiness;
  - governance;
  - managing the seats;
  - operating cadence.

  The 14 contributions are what that hire would do to grow the company, such as a weekly binding constraint turned into
  an improvement, a monthly growth experiment, and a daily supplier-target check against the 50 / 200 / 300 milestones.
- **Stage 1.** The exam reads 52.9% (63 of 119), the best of the six seats and still 42 points under the bar. The
  reader's notes in `knowledge/exams/judged/ceo.json` show the shape of the misses: it computes a figure but never states
  the benchmark that judges it, and it claims as its own a decision that is the founder's. No CEO judgement is graded
  against its outcome.
- **Stage 2.** All 14 contributions are live. CEO-C14, the register review, had been listed as missing although
  `ceo.register_review` had run since 19 Oct; it is corrected in this PR. The probe read 31 of 32 duties on their clock. The 32nd
  is `ceo.senior_verdict` itself, registered inside the probe's transaction and not yet run. On the live table, all 31
  existing CEO duties are on their clock. Across the company, the only enabled duty off its clock on 27 Oct is
  `marketing.month_plan`. All
  1,319 windowed handoffs to the CEO in 30 days were answered in their window. The CEO owes **21 re-verifications** on
  handoffs it sent that were answered and are waiting for it to close.

### sales_engineer: junior

- **The senior standard.** The role is Senior Sales Engineer and Quantity Surveyor. Its 13 qualifications are:
  - drawings and specifications;
  - take-off under a method of measurement;
  - UAE authorities and standards;
  - exact specs and submittals;
  - BOQ pricing;
  - quote levelling;
  - supplier vetting;
  - alternatives;
  - neutral negotiation;
  - UAE contract law;
  - the founder's hard rules;
  - supply building;
  - the customer pipeline.

  It has 14 contributions.
- **Stage 1.** The exam reads 41.0% (50 of 122). This is the only seat whose decisions are graded against what
  happened: **59 graded judgements, 35.6% right**, against an 80% bar. That is the strongest evidence in the estate that
  the seat's judgement is not yet senior.
- **Stage 2.** All 14 contributions are live. SE-C12 negotiation, SE-C13 win/loss and SE-C14 framework proposals were
  listed as missing but have run since 19 Oct; they are corrected in this PR. All 24 duties are on their clock, and all
  617 windowed handoffs were answered in their window.

### accountant: junior

- **The senior standard.** The role is Group Financial Controller and Head of Tax and Compliance, UAE. Its 14
  qualifications are:
  - corporate tax;
  - VAT;
  - statutory compliance;
  - IFRS for SMEs;
  - marketplace revenue as agent;
  - bookkeeping;
  - close by day 5;
  - internal control;
  - Stripe;
  - bank and expenses;
  - treasury and FP&A;
  - collections and fraud;
  - sanctions and UBO;
  - people and founder money.

  It has 16 contributions.
- **Stage 1.** The exam reads 48.6% (53 of 109). No accountant judgement is graded against its outcome.
- **Stage 2.** All 16 contributions are live. Five of them were listed as missing or partial although their duties have
  run since 19 Oct: ACC-C11 receipt intake, C12 charge recovery, C14 VAT threshold, C15 weekly finance report and C16
  year end. They are corrected in this PR. All 23 duties are on their clock, and all 284 windowed handoffs were answered
  in their window.

### it_engineer: junior

- **The senior standard.** The role is Head of Infrastructure, Reliability and Security. Its 13 qualifications are:
  - SLOs;
  - incident command;
  - serverless reliability;
  - change safety;
  - backup and DR;
  - Postgres DBA;
  - OWASP, API and LLM security;
  - security governance;
  - deliverability;
  - UAE law;
  - cost and data integrity;
  - seat knowledge;
  - the mandate.

  It has 17 contributions.
- **Stage 1.** The exam reads 38.5% (42 of 109). No IT judgement is graded.
- **Stage 2.** 15 of 17 contributions are live. Two are not:
  - **IT-C14**, failure clusters in `agent_runs`, had no duty. It is **built in this PR** and goes live at apply.
  - **IT-C17**, expired licences removed from matching, is performed daily but not by this seat. The
    `it_duty_schedule supplier_docs` schedule (owner sales_engineer, last OK 26 Oct) runs `fn_reconcile_doc_blocks`,
    which pauses matching on the expiry day. Suppliers belong to the sales engineer under the 24 Sep map, so the
    standard's owner is what is wrong. This is stated in the standard's gap rather than counted as live.

  All 24 duties are on their clock. IT owes **916 re-verifications**: it.finding handoffs it sent were answered by their
  receivers and are still waiting, past the 4-hour window, for IT to re-verify and close them. This is the largest open
  loop in the company.

### marketing: junior

- **The senior standard.** The role is Senior Marketing and Growth Manager. Its 15 qualifications are:
  - GEO;
  - bilingual SEO;
  - campaigns;
  - video;
  - copy;
  - trends and competitors;
  - posting craft;
  - UAE advertising law;
  - positioning and crisis;
  - cold-start growth;
  - owned channels;
  - paid media;
  - honest measurement;
  - PR;
  - working as a seat.

  It has 15 contributions.
- **Stage 1.** The exam reads 48.7% (38 of 78). No marketing judgement is graded.
- **Stage 2.** 9 of 15 contributions are live:
  - MKT-C01: the month plan duty `marketing.month_plan` is failing, with 7 consecutive failures and last OK 19 Oct. Its last error says the plan for November 2026 is not
    with the founder.
  - MKT-C10 to C14 have no duty: native publishing, community management, the weekly trend scan, the monthly scorecard
    and the fact register.

  9 of 10 duties are on their clock. **PR #1551 is building these and is under review by another agent. This PR does
  not touch them.**

### customer_support: junior

- **The senior standard.** The role is Head of Customer Experience and Support, with 12 qualifications. They cover:
  - one customer voice across chat, email and WhatsApp;
  - PDPL;
  - complaint law;
  - compliant messaging;
  - the ISO 10001 to 10004 complaint and satisfaction family;
  - case operations;
  - senior writing in English and Gulf Arabic;
  - honest experience metrics;
  - a grounded knowledge base;
  - procurement fluency;
  - payments and refunds;
  - fraud and abuse.

  It has 14 contributions.
- **Stage 1.** The exam reads 36.5% (35 of 96), the lowest of the six seats. No support judgement is graded.
- **Stage 2.** 8 of 14 contributions are live. The six that are not are:
  - CS-C01: same-reply answers;
  - CS-C08: verified delivery outcomes;
  - CS-C09: delivery health;
  - CS-C11: PDPL requests;
  - CS-C12: incident notices;
  - CS-C13: public reviews.

  All 6 duties are on their clock. **PR #1549 is building these and is under review by another agent. This PR does not
  touch them.** This PR adds one support duty that #1549 does not cover: the plain-language score of every notice (see
  "Built in this PR").

## Findings across the seats

1. **Stage 1 was blind in production.**
   - The quarterly `ceo.seat_audit` reads its knowledge measure from `seat_knowledge_exam`, which holds 2 graded items
     per seat in 90 days because the model-graded exam was retired on 24 Sep. So its knowledge line reads "not
     measured" for all six seats.
   - Every seat's monthly self-review reads `trend = 'no_exam'` with 0 items, because `seat_exam_item` is empty.
   - The judged exam existed only in the repository.

   The weekly verdict built here reads the judged exam from seeded rows.
2. **The standards were measuring their author.** Thirteen contributions were listed as "missing" or "partial" with no
   duty, although the duties for them have run since 19 Oct. A hand-run audit therefore reported 57 to 93%
   contributions live where the truth for those four seats is 100%. The standards are corrected in this PR, and a check
   now holds every named duty to a key that exists.
3. **Stage 1 is the gap that matters, and code cannot close it.** The exam measures what the seat's model answers from
   its knowledge and prompt. Every seat's checklist is 100% backed by loaded knowledge, yet answers miss the benchmark,
   the boundary or the rule the item tests. The fix is reasoning and grounding (the prompts, retrieval reaching the right
   entry, answer structure), followed by a fresh judged run. That is the next build order for 1003. It needs the
   seats' models, and is not a deterministic duty.
4. **The quarterly audit counts a handoff as late when it is not.** On a kind that the originator closes,
   `decided_at` is the originator's re-verification and `detail.replied_at` is the receiver's answer.
   - sales_engineer answered all 414 of its it.finding handoffs in time; only 21 were closed in time.
   - The quarterly audit's 43 "late handoffs" for sales_engineer, 15 for accountant and 17 for customer_support count
     handoffs already answered and waiting for their originator.
   - The verdict built here measures the receiver's answer, and reports the originator's owed closes separately.

   `fn_ceo_seat_audit` itself is not changed here.
5. **The receiver half of every handoff is saturated.** Registered handlers answer by code at once, so every seat
   answers 100% in time. The real lag is the originator closing the loop: IT owes 916, the CEO 21 and marketing 1.
   Nothing yet holds an originator to its own close window.
6. **Only sales_engineer's judgements are graded against outcomes.** The other five seats make reasoned judgements
   (`seat_judgement`, 387 to 1,898 each in 30 days) and none is ever scored for whether it turned out right. Without
   that, stage 1 rests on the exam alone.

## Built in this PR (branch `ceo/senior-seat-audit-27-oct`)

Every item below is code only, with no model. Each was proved by a rolled-back probe on production and is pending until
applied at merge.

| what | seat | file | prevented by |
|---|---|---|---|
| Weekly two-stage senior verdict per seat (`ceo.senior_verdict`), seeded from the repository standard and judged exam; a falling level gets one CEO improvement | ceo | `scripts/sql/the_ceo_measures_every_seat_against_its_senior_standard_every_week.sql` | `scripts/checks/the_senior_verdict_is_measured_against_the_standard_in_the_repository.test.mjs` |
| The 13 stale contribution maps corrected; IT-C14 mapped to the new duty; IT-C17's real performer named | ceo | `knowledge/standards/{accountant,ceo,it_engineer,sales_engineer}.json` | same check, plus `every_seat_is_held_to_a_senior_standard.test.mjs` |
| IT-C14: every failing run label (more than 5 runs and more than half not OK in 7 days, fixture runs apart) becomes one owned finding; an unowned label says so; a cleared one closes | it_engineer | `scripts/sql/the_it_engineer_turns_every_failing_run_label_into_an_owned_finding.sql` | `scripts/checks/the_it_engineer_turns_every_failing_run_label_into_an_owned_finding.test.mjs` |
| Ledger 1013: a handoff closes only when its receiver cites the handover note, or records why not | ceo, customer_support | `scripts/sql/a_handoff_closes_only_when_its_receiver_cites_the_note_or_says_why_not.sql` | `scripts/checks/a_handoff_closes_only_when_its_receiver_cites_the_note.test.mjs` |
| Ledger 1013 item 7: every notice a customer or supplier reads is scored for plain language by the SQL twin of the reply gate; a failing type goes to the seat that writes it | customer_support | `scripts/sql/customer_support_scores_every_notice_a_customer_or_supplier_reads_for_plain_language.sql` | `scripts/checks/the_plain_language_score_is_the_same_in_sql_and_typescript.test.mjs` |

What the probes measured on real data, rolled back:

- **1013, handover citation.** In 30 days, 199 handoffs closed with neither a citation nor a reason. All were
  `delivery.request` rows that `fn_customer_support_adopts_untracked_send` files already closed. After the change:
  - a bare close is refused;
  - the adoption records why it cannot cite;
  - the citing closer still closes;
  - the measurement reads 0 "neither".
- **1013, plain language.** 395 notices from the last 35 days were scored: 382 fixtures and 13 real.
  - Real defects found: the supplier invitation has a 34-word sentence (4 of 4 failing); the customer activation notice
    has a 38-word sentence; and `support_case_closed` shows the internal identifier `customer_support` to a customer.
  - The SQL score equals the TypeScript gate on 24 of 24 recorded cases, in English and Arabic.
- **IT-C14.** It opened 2 real findings for the last 7 days: `fn:quote_compare`, 15 of 15 runs warn, owner
  sales_engineer; and `fn:unsubscribe`, 10 of 10 warn, owner customer_support.

## What remains (build orders, not done here)

- **Stage 1 for every seat.** Raise the judged exam from 36.5–52.9% to 95%. Start with the reader's notes in
  `knowledge/exams/judged/<seat>.json`, then re-run `scripts/eval/seat_exam_through_think.ts --answer --reworded`, have
  a reader judge it, and re-seed with `node scripts/eval/seat_senior_standard_seed.mjs --write`.
- **Grade judgements against outcomes for the five seats that have none.** Until this exists, stage 1 for those seats
  rests on the exam alone.
- **Hold an originator to its own close window.** IT owes 916 re-verifications.
- **Correct the quarterly audit's late-handoff count** (finding 4).
- **Marketing MKT-C01 and C10 to C14, and customer_support CS-C01, C08, C09 and C11 to C13.** These are in #1551 and
  #1549.
- **The three plain-language template defects above.** They belong to the seats that write those notices; the new duty
  hands each one over once a type reaches 3 notices in 30 days.
