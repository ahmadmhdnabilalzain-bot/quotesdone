# The company brain — plan for approval

7 September 2026. Written for the founder to check **before** anything is applied.

## 0. What was asked

Per position, at the standard of *a senior human with twenty years in a top international company*:

1. position knowledge, 2. position logic, 3. position reasoning, 4. position judgement rules,
5. technical knowledge, 6. academic knowledge, 7. corporate knowledge, 8. a one-year plan tied to the revenue target.

**With one hard constraint, stated twice: none of it may depend on a language model at run time. Every position must
answer with OpenRouter switched off.**

That constraint is the whole design problem, so section 1 is about it. Everything after assumes it.

---

## 1. How a coded position answers an open question

A language model answers anything because it will generate something for any input. A coded system cannot do that, and
pretending otherwise produces the thing you already rejected: a lookup dressed as thinking. So the honest architecture
has four parts and one boundary.

**1. A question taxonomy per position.** Each seat has an enumerated set of question and decision types it is
responsible for. Not infinite. A real senior in a real seat handles perhaps thirty to sixty recurring classes, and the
rest they escalate. Each department's section lists them explicitly.

**2. Matching, without a model.** An incoming question is matched to a type by lexical search plus embedding
similarity. The estate already embeds text with a free in-region model, so meaning-matching costs nothing and needs no
paid provider. Above the threshold, the type resolves. Below it, see the boundary.

**3. A resolver per type.** A coded procedure: gather evidence from named tables, run the domain model (arithmetic),
apply the judgement rules (thresholds and gates), generate the option set from the lever catalogue, score and rank,
compute the flip condition. Every number traces to a row with a date.

**4. Composition.** The answer is assembled from a structured template whose slots are computed values and cited rows.
It reads like a professional memo because its structure is one. This is not a model writing prose; it is a report
being generated, the way a bank statement is generated.

**The boundary, stated plainly.** When no type matches, the seat says so: what it understood, what it would need, and
the task it opened. It does not guess. That refusal is a feature, and it is the honest price of the no-model rule. The
way we make the boundary rare is by enumerating well and by measuring, every week, what fraction of real questions
fell outside it. Target: under ten percent by the end of the build, and every one of those becomes a new type.

---

## 2. The eight layers, as things that can actually be built

Each layer below is data or code, per position, verifiable.

| # | Layer | What it physically is | Where the content comes from |
|---|---|---|---|
| 1 | **Position knowledge** | the seat's own records in `agent_knowledge`, scoped, sourced and dated | primary sources, the certification syllabus areas it failed, the company's own documents |
| 2 | **Position logic** | named quantitative models: formulas with inputs bound to live tables | written per domain; the shared business models below |
| 3 | **Position reasoning** | the step-by-step resolver per question type, stored as a procedure | written per type, reusing the eight decision kinds |
| 4 | **Judgement rules** | testable rows: condition → verdict → reason, including the red lines that override a good score | the seat's discipline, the founder's rulings, the regulator |
| 5 | **Technical knowledge** | the systems, formats, platform mechanics and specifications the seat must operate | vendor documentation, platform specifications, our own schema |
| 6 | **Academic knowledge** | the generalising theory, mapped to the certification syllabus | lawful primary sources only: standards bodies, regulators, published frameworks. Never copyrighted study texts |
| 7 | **Corporate knowledge** | QuotesDone's own facts, rulings, pricing, workflows, history | already largely exists; rendered into every head every fifteen minutes |
| 8 | **One-year plan** | the seat's objective, its two or three owned metrics, quarterly milestones, capacity check, dependencies | derived from the revenue target by the arithmetic in section 5 |

Layers 1, 5, 6 and 7 are **knowledge**: they are ingested and cited. Layers 2, 3 and 4 are **reasoning**: they are code
and rows. Layer 8 is **direction**: it is arithmetic against your target.

---

## 3. What "highest standard" means, and how it is proved

"Senior human, twenty years, top international company" has to become a measurement or it is a slogan. Four, all built
or in build today:

- **Certification.** Every position now holds the certifications a genuine senior in that seat would hold: 105
  assignments, 52 certifications, 2,080 questions at the real bodies' pass marks. The employee sits them from its own
  knowledge with no model. First real result: the Financial Controller scored 15% on ACCA against a pass mark of 50,
  abstaining on 25 of 40 because nothing in its library spoke to the question. That is the baseline we improve from.
- **Decision evaluation.** Fifty real decisions from this company across the eight decision kinds, each with a
  reference answer. The coded resolver sits the same set. Measured per position: reached the reference, abstained
  correctly, or was confidently wrong. Confidently wrong is the only unacceptable outcome.
- **Calibration.** Every decision registers an expected outcome and a date. When the outcome lands, the error is
  recorded. A seat whose confidence is not justified by its results is not senior, whatever it scored on an exam.
- **Coverage.** The fraction of real questions that matched a type rather than being refused. A seat that answers
  everything but is often wrong, and a seat that refuses everything, are both failures.

---

## 4. The shared spine, built once

Not fifty-four brains. Eight decision kinds, four business models, one composition engine, and per-position data.

**The eight decision kinds**: allocation, gate (accept or reject against a standard), pricing, sequencing under
dependency, diagnosis, forecast, craft judgement against a rubric, escalation. Every question type in every department
is one of these. The solver is written once and configured per seat.

**The four business models**, which make an answer specific to QuotesDone rather than generic advice:

- **Marketplace stocks and flows.** Verified suppliers, trust and cash are stocks that fill slowly and drain fast;
  invitations, registrations, RFQs and reveals are flows with delays between them. This model is what prevents the
  classic error of pushing demand into an empty marketplace.
- **Funnel identity.** revenue = customers × RFQs per customer × reveal rate × average quote value × 3%.
- **Unit economics and payback**, against the cash position and the AED 30 per day cap.
- **Risk and reversibility**, which decides what escalates to you regardless of score.

**The composition engine** turns a resolved decision into the memo: what was asked, the constraint, the options with
their scores, the rejected ones with reasons, the evidence with dates, the flip condition, and what would be done next.

---

## 5. Layer 8: the year-one plan, and a conflict in your targets

Your goals as recorded: **AED 1,000,000 annual revenue by 31 August 2027**, and **AED 100,000 revenue in month 12**.

The revenue identity gives the rest. The reveal fee is 3%, so revenue per reveal is 3% of the quote value. Average
quote value is **unmeasured** — there are zero quotes in the system — so the plan carries it as a range and the first
job of the marketplace seats is to measure it.

| If the average quote is | Fee per reveal | Reveals needed for AED 1M | Reveals needed for AED 100k in a month |
|---|---|---|---|
| AED 10,000 | AED 300 | 3,333 | 333 |
| AED 25,000 | AED 750 | 1,333 | 133 |
| AED 50,000 | AED 1,500 | 667 | 67 |

**The conflict.** If "AED 1,000,000 annual" means the sum of twelve months, then a smooth ramp reaching AED 100,000 in
month 12 sums to roughly AED 600,000, not a million. To sum to a million with a smooth ramp, month 12 must be about
AED 165,000. If instead it means the annualised run rate at month 12, then AED 100,000 in month 12 is AED 1.2M
annualised and the two rows agree. I will build to the **run-rate reading**, because it is the common commercial one
and it makes your two recorded goals consistent. Say the word if you meant the cumulative one, because it is a
sixty-five percent harder target and it changes every department's slice.

**Where the plan actually binds.** Today: one customer, zero inquiries, zero quotes, zero transactions, 22,265 leads,
and no category with the ten verified suppliers your rule requires. Every demand-side number above multiplies by a
reveal rate that is structurally zero until supply exists. So the year-one plan is supply-first by arithmetic, not by
preference, and the honest capacity statement is this: month 12 at AED 100,000 requires the supplier loop to start
within roughly two months and the first categories to reach ten verified suppliers by roughly month four. Each
department's section states its own slice and whether it is achievable.

---

## 5b. Layer 8 in full: a year of targets and tasks, per department and per position

The founder's instruction: **targets and detailed tasks for every agent and every department, for a year, to
1 October 2027.** The planning horizon is therefore **7 September 2026 to 30 September 2027, thirteen months**, with
the recorded revenue milestone falling inside it on 31 August 2027.

### What every one of the 54 positions gets

| Part | Content |
|---|---|
| Objective | one measurable sentence for the thirteen months |
| Owned metrics | two or three, each with its baseline **measured today** and its target at 30 Sep 2027; a baseline that does not exist is written as unmeasured, never guessed |
| Month-by-month plan | thirteen rows: what this seat does that month, what it must produce, and what it needs from other seats first |
| Quarterly gates | at 31 Dec 2026, 31 Mar 2027, 30 Jun 2027 and 30 Sep 2027: what must be true, and what changes in the plan if it is not |
| Capacity check | the volume of work implied against what this seat can actually process, stated in the seat's own unit (invitations, quotes reviewed, screenings, reports) |
| Dependencies | the named seats it waits on and the named seats waiting on it |
| Change conditions | what would make this plan wrong, and what replaces it |

### What every one of the 10 departments gets

Its aggregate targets by quarter, its slice of the revenue identity, the sequencing across its own seats so two of
them are not blocked on each other, the single number the department is accountable for, and the month at which its
work becomes the binding constraint for the company.

### The three ordering facts every plan must obey

1. **Supply precedes demand.** No category transacts below ten verified suppliers, so every demand-side month before
   that threshold produces zero revenue by arithmetic, not by opinion.
2. **The constraint moves.** After supplier count comes quote quality, then response time, then category coverage.
   Each department's plan must name the month its own constraint arrives and pre-position for it.
3. **Nothing runs until the founder releases it.** Supplier outreach is held behind his switch. The plans are written
   to start on release, and every month-one task is a preparation task that costs nothing if the release slips.

Delivered as one file per department, , written after that department's
taxonomy and models exist, because a task list written before the models is a wish list.

## 5c. Every plan has a Plan B, and the agent executes the branch itself

A plan that only describes success is a wish. Every position's plan is therefore a **state machine with dated
checkpoints**, stored as rows the agent runs, not prose it reads:

| Part | What it is |
|---|---|
| **Target** | an exact number, for an exact week, in the seat's own unit |
| **Mechanism** | the specific action that is supposed to produce it, with volume and cost |
| **Measurement** | the query that reads the actual, run automatically at the checkpoint |
| **Trigger** | the threshold that decides pass, warn or fail, set before the week starts |
| **Plan B** | the named alternative the agent switches to on failure, with its own target and its own checkpoint |
| **Plan C** | the second alternative, tried only when B has failed on measurement |
| **Escalation** | what reaches the founder when the ladder is exhausted, and the exact decision he is being asked for |

Two rules keep it honest. A branch is taken on **measurement**, never on a feeling that it is going badly. And no
branch may be taken twice without changing something, because repeating a failed action is how a company spends a
quarter learning nothing.

### Worked in full: supplier registration, the company's binding constraint

**What is measured today.** 22,265 leads, of which 19,896 carry a distinct email address. 161 invitations have been
sent. 10 bounced. **Zero registered.** That is the entire evidence base for supplier acquisition.

**What zero out of 161 actually tells us.** It does not mean the true conversion rate is zero. With 161 trials and no
successes, the rate is below roughly **1.9%** with 95% confidence, and that upper bound is the number the plan must be
built against until a better one is measured.

**The arithmetic that follows, and it is uncomfortable.** The founder's target is 300 registrations a month. At the
best rate still consistent with the evidence, 1.9%, that requires about **15,800 invitations every month**. The entire
list holds 19,896 addresses. So the list supports **roughly five weeks** of the target and would produce at most about
**380 registrations in total**, against a twelve-month need of 3,600.

**Therefore the plan cannot be "send invitations".** It has to be, in this order: measure the real conversion on a
small batch before burning the list, then either fix the conversion or change the channel, and in parallel replace the
list faster than it is consumed.

### The ladder the business development seat actually executes

**Plan A — measure before scaling.** Week 1: send 200 invitations to the highest-quality segment, one message
variant. Target: 4 registrations, which is 2%. Checkpoint Friday. Cost: nothing but the sending.

- **Pass (4 or more):** scale to 1,000 in week 2, then 2,500 in week 3, holding the message constant, and recompute the
  list runway at the measured rate every week.
- **Warn (1 to 3):** hold volume at 200 and run a second variant against a fresh 200 in week 2, changing exactly one
  thing: the subject line. One variable at a time or the result teaches nothing.
- **Fail (0):** do not send a third email batch. Go to Plan B. Sending more of a message that produced nothing is the
  most common way a list is destroyed.

**Plan B — the channel, not the message.** Two variants at 200 each produced under 1%. The hypothesis changes from
"wrong words" to "wrong medium". Week 3 to 4: WhatsApp to 200 leads whose mobile numbers we hold, and 50 direct calls
by the seat that owns supplier onboarding. Target: 5 registrations from 250 touches, which is 2%. Same checkpoint
discipline.

**Plan C — the offer, not the medium.** Both channels under 1%. The hypothesis changes again: suppliers do not believe
the offer. Week 5 to 6: change what is being offered rather than how it is said. Lead with a live customer request in
their category, so the first contact carries a job rather than an invitation, and register them to answer it. This
requires demand to exist in that category, which is why the marketplace seats' week-4 milestone is to have at least one
live request per target category.

**Plan D — borrow the audience.** All three failed on measurement. Week 7 to 8: approach trade associations, category
distributors and the two largest suppliers already known, offering a partnership rather than a signup, since a
credible introducer converts where a cold approach does not.

**Escalation, with the exact decision requested.** If, by the end of week 8, cumulative registrations are under 20 and
the measured conversion across all four routes is under 1%, the acquisition assumption is broken and this is not a
question the company may answer by itself. What reaches the founder is one page: the four routes tried, the number of
touches and registrations for each, the resulting cost per registration, and three costed options, which are paid
acquisition at a stated budget, a field agent paid per registration, or a reduced target with the revenue consequence
stated in dirhams. He picks one. Nothing restarts until he does.

### The same shape, everywhere

Every one of the fifty-four positions gets this structure, in its own units. The collections seat's ladder runs from
reminder to call to formal notice to the founder's write-off decision. The marketing seat's runs from organic to a
thirty dirham test to a changed hook to a changed audience to the honest report that the channel does not work for
this product. The compliance seat's runs from automatic screening to manual review to suspension to legal advice. In
every case the target is a number on a date, the branch is taken on a measurement, and the last rung is a page for the
founder with the decision named.

---

## 5d. Every plan bottoms out in dated work items, specified to the field

A plan that stops at "run supplier outreach" or "post on social" is not executable. Every role's plan therefore ends
in **work items**: dated, fully specified objects the seat can execute without asking anyone anything. Each role has
one or two unit types, and each unit type has a fixed field set.

| Department | Unit of work | Every item carries |
|---|---|---|
| growth | a post, an ad set, a landing page test | date, audience segment, objective metric, content type, hook (exact words), visual specification, call to action and destination, language, budget, the single variable under test, expected result with its basis, success and failure thresholds, fallback |
| supply | an invitation batch, a follow-up, a verification review | segment and size, channel, message variant, send window, expected registrations with basis, checkpoint date, fallback rung |
| marketplace | an RFQ qualification, a matching run, a quote comparison | inputs required, completeness gate, supplier set and why, top-three rule applied, escalation trigger |
| finance | a reconciliation, a dunning action, a close task | period, source of truth, tolerance, exception rule, escalation amount |
| customer_experience | a lifecycle message, a support resolution, a save attempt | trigger event, channel, template and version, timing rule, success metric, next rung |
| legal | a document review, a screening run, a policy update | scope, source of law, the clause tested, verdict, retention rule |
| product_eng | a change, a release, an incident response | risk class, gate battery, rollback, evidence recorded |
| data_intel | an experiment, a measurement, a report | hypothesis, sample size required, power, stopping rule, decision it informs |
| people_ops | an ingestion batch, an exam sitting, a calibration review | seat, syllabus area, source, before and after score |
| exec | a decision memo, a plan revision, an allocation | constraint named, options with scores, rejected with reasons, flip condition, review date |

### Worked in full: the first four weeks of social posts

Audience is **suppliers**, not customers, because supply is the binding constraint and every customer-side impression
multiplies by a reveal rate that is structurally zero until categories open. Budget is the founder's AED 30 per day,
so AED 210 a week, and the design spends it as two tests plus a scale-up rather than spreading it thin.

**The experimental discipline: one variable per week.** Week 1 tests the hook. Week 2 takes the winning hook and tests
the format. Week 3 takes both winners and tests the audience segment. Week 4 tests the offer framing. Changing two
things at once means the result teaches nothing, which is how a year of posting produces no knowledge.

| # | Date | Variable under test | Content type | Hook (exact words) | Budget | Expected |
|---|---|---|---|---|---|---|
| 1 | Mon 14 Sep, 09:00 | hook A | animated video, 12 s, 9:16 | "Dubai contractors: stop paying for leads." | AED 60 over 2 days | ~2,000 impressions, 15-25 likes, 20-40 profile visits |
| 2 | Wed 16 Sep, 09:00 | hook B | identical animation, hook swapped | "You keep 100% of every job you win." | AED 60 over 2 days | same, and the comparison is the point |
| 3 | Sun 20 Sep, 09:00 | scale the winner | winning hook, unchanged | winner | AED 90 over 3 days | ~3,000 impressions |
| 4 | Mon 21 Sep, 09:00 | format | static carousel, 5 frames, winning hook | winner | AED 60 | tests whether motion is worth its production cost |
| 5 | Wed 23 Sep, 09:00 | format control | animation, winning hook | winner | AED 60 | the control for post 4 |
| 6 | Mon 28 Sep, 09:00 | segment | winning hook and format | winner | AED 60 | audience narrowed to MEP and fit-out contractors |
| 7 | Wed 30 Sep, 09:00 | segment control | winning hook and format | winner | AED 60 | audience narrowed to trading and supply companies |
| 8 | Mon 5 Oct, 09:00 | offer framing | winning everything | "A customer in your category is asking for quotes today." | AED 60 | tests demand-led framing against feature-led |

**What every one of those items carries in full, using post 1 as the example.**

- **Objective metric**: profile visits and link clicks, not likes. Likes are the founder's stated target and are
  recorded, but the metric that predicts registrations is the click.
- **Audience**: UAE, business interests in construction, MEP, fit-out, trading and manufacturing, ages 25-55, English
  and Arabic.
- **Content**: twelve seconds, four beats. Hook, 1.5 s. The mechanism in three shots, 6 s: a customer posts a request,
  you quote anonymously, they pay to reveal you. The offer, 2.5 s: free for the first 1,000 suppliers, no commission.
  The call to action, 2 s: register in three minutes, with the link.
- **Visual specification**: 1080 x 1920, navy ground from the brand kit, teal for motion accents, gold used only on the
  call to action so the eye has one landing place, display face at no less than the equivalent of 24 px, contrast
  measured at or above 4.5 to 1, all text outside the bottom fifth and top sixth where the platform's interface sits,
  first frame legible as a still because that is the thumbnail, captions burned in because the feed is watched muted.
- **Language**: English master, Arabic cut with the layout mirrored right to left and numerals localised, not a
  translated caption over an English composition.
- **Expected result and its basis**: at AED 60 and a UAE B2B video CPM of roughly 20 to 40 dirhams, about 1,500 to
  3,000 impressions; at a like rate of 1 to 2 percent of viewers, 15 to 25 likes; at a click rate of 0.5 to 1 percent,
  10 to 20 clicks. **Every one of those rates is an industry prior, not our measurement, because the account has ten
  posts and zero recorded engagement metrics.** They are labelled as priors in the plan and replaced by our own numbers
  after week 1.
- **Success and failure**: success is 10 or more link clicks and at least 1 registration started. Failure is fewer
  than 3 clicks, which means the audience or the offer is wrong rather than the wording.
- **The statistical honesty**: 2,000 impressions per variant can detect a doubling of the click rate, not a twenty
  percent improvement. So week 1 answers "is one hook much better", not "which hook is slightly better", and the plan
  says so rather than over-reading the winner.
- **Fallback**: if both hooks fail at under 3 clicks each, the seat does not write a third hook. It moves to the
  channel rung of the ladder, because two failures on the same axis mean the axis is wrong.

---

## 6. Sequence of work

| Phase | What is built | How you will know it worked |
|---|---|---|
| **A** | The spine: eight solvers, four business models, the composition engine, the refusal path | the CEO answers "what should we do to increase revenue" with numbers, options, rejected alternatives and a flip condition, with the model off |
| **B** | One position end to end, all eight layers, chosen for the question you already asked: the social media seat and the first three posts | you read its answer and judge it against a senior human's |
| **C** | Layers 2, 3, 4 for all 54: the taxonomies, models, resolvers and judgement rules from the department sections | coverage measured: what share of real questions match a type |
| **D** | Layers 1, 5, 6: the knowledge ingestion from lawful primary sources, driven by the failed certification areas | certification re-sits show movement, per position |
| **E** | Layer 8 for all 54 and all 10 departments: thirteen months of targets and tasks to 30 Sep 2027, with quarterly gates and capacity checks | every seat and every department has a dated plan whose arithmetic reaches the target, or says plainly that it does not |
| **F** | The evaluation set of fifty real decisions, and the weekly coverage and calibration report | one page per week: coverage, correctness, calibration, refusals |

Phases A and B are the ones that decide whether this works. I would rather be judged on B before building C.

---

## 7. Honest limits

- **Novel situations.** Anything genuinely outside the taxonomy is refused, not answered. That is the price of no
  model, and it is the right price, but you should expect it and see it in the coverage number.
- **Taste.** The wording of a hook, the judgement that a design is flat, the sense that a supplier is lying. Rubrics
  get close and do not arrive.
- **The knowledge is thin today.** Six ACCA areas have nothing in the estate at all. Some layers cannot be filled from
  what we hold and will need lawful material, which may cost money. Those arrive as a costed list, never bought
  without you.
- **This is a large build.** It is fifty-four positions across eight layers. The spine is weeks; the full depth is
  months. Anyone who tells you otherwise has not counted.

---

## 8. What I need from you

1. **The target reading**: run rate or cumulative (section 5). I will build to run rate unless you say otherwise.
2. **Approval of this plan's shape** before I apply anything.
3. Later, and only when it arrives as a costed list: a yes or no on any licensed material.

Nothing else. The rest is engineering.

---

## Appendix — the per-position detail

One file per department, each covering every position in it: the question taxonomy, the domain models, the reasoning
procedures, the judgement rules, technical and academic knowledge with lawful sources, corporate knowledge, and the
year-one slice.

- `docs/brain/exec.md`
- `docs/brain/finance.md`
- `docs/brain/supply.md`
- `docs/brain/growth.md`
- `docs/brain/marketplace.md`
- `docs/brain/customer_experience.md`
- `docs/brain/legal.md`
- `docs/brain/product_eng.md`
- `docs/brain/data_intel.md`
- `docs/brain/people_ops.md`
