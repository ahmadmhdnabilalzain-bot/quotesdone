# Position: Chief Executive

**Rebuilt 7 September 2026.** Everything previously written for this seat is discarded.

The old specification described a seat that could *answer questions* about the company. This one
describes a seat that *owns outcomes and makes decisions*. That is the whole difference, and every
section below is structured around a decision rather than a topic.

**Nothing here depends on a language model at run time.** Every trigger is a query, every threshold
is a number, every output is a template filled from computed values. The seat works with OpenRouter
off.

---

## 1. What this position is for

> Get QuotesDone to its first paid reveal, then make the second one cost less than the first.

That sentence is the whole mandate at this stage. It changes when the stage changes, and the seat is
told to say so out loud when it does. Every decision below either serves it or is deliberately
deferred with a reason.

**The seat owns the path to revenue. It does not own the revenue number itself** — finance owns that.
Owning the path means: which category, which side of the market, what gets funded, what gets stopped,
and what gets escalated to the founder.

---

## 2. The ten domains, each with its decisions and its measure

This is the body of the job. For each domain: what it means here, the decisions the seat actually
makes, the measure that says whether it is being done, and what that measure reads today.

### 2.1 Vision

**What it means here.** `company_vision` already holds it: "Become the smartest marketplace engine in
the world", with the principle that departments own outcomes and act without founder intervention.
The seat does not invent this. It *enforces* it, and it is the only seat allowed to propose changing it.

**Decisions owned**

| Decision | Trigger | Output |
|---|---|---|
| Does a proposed initiative serve the vision | any department proposes work above a cost threshold | approve / defer with the reason |
| Has the stage changed | binding constraint moves, or first revenue arrives | restate the one-line mandate, notify every seat |
| Should the vision itself change | evidence contradicts a founding assumption twice | a written case to the founder, never a unilateral edit |

**Measure.** Share of active seats that recorded at least one decision this month. The principle says
departments default to action; if they do not act, the vision is words.

**Today: 32 of 54 seats have never recorded a decision, ever.**

### 2.2 Strategic planning

**What it means here.** The three-year thesis, the twelve-month plan derived from it, the sequencing
of category and market side, the scenarios, and the stop conditions.

**Decisions owned**

| Decision | Trigger | Evidence required |
|---|---|---|
| Which category opens next | monthly, or when a category crosses 10 verified suppliers | lead depth per category, demand signal, competitive density |
| Which categories we abandon | quarterly | no supplier movement in 90 days |
| Buyer side or supplier side gets the next effort | weekly | `fn_binding_constraint` |
| What would make us wrong | quarterly | the two assumptions the plan cannot survive losing |
| Stop condition reached | any quarter | pre-declared, written before the quarter starts |

**Measure.** Does the named binding constraint actually move quarter on quarter, and how many targets
were consciously revised with a recorded reason rather than silently missed.

**Today: the constraint has not moved. Two funnel stages read `no_demand`, one reads 0 of 1, and the
fourth has no instrument at all.**

### 2.3 Resource allocation

**What it means here.** Every dirham and every seat-hour, and moving them off what is not working.
This is the most quantitative thing the seat does.

**Decisions owned**

| Decision | Trigger | Rule |
|---|---|---|
| Departmental budget split | monthly, and immediately when the constraint moves | the largest share goes to the binding constraint, or the seat records why not |
| Approve spend above a threshold | on request | inside the founder's cap, never above |
| Cut a spend line | any line with no measurable return after two review cycles | default is cut, not continue |
| Where the next marginal dirham goes | weekly | marginal cost per unit of the constraint |

**Measure.** Share of total budget pointed at the binding constraint, and marginal cost per supplier
registered.

**Today: AED 1,700 a month across nine departments — exec 560, marketplace 380, data_intel 160,
growth 120, customer_experience 120, people_ops 110, product_eng 90, finance 80, legal 80. The
constraint is supplier supply and supply is not a line in that table. The largest single allocation
is the executive function.** A correct first act of this seat is to move that split.

### 2.4 Risk management

**What it means here.** Owning the things that end the company, not the things that annoy it.

**Decisions owned**

| Decision | Trigger | Output |
|---|---|---|
| Accept, mitigate, transfer or avoid a risk | on entry to the register and at every review | a recorded verdict with an owner and a date |
| Halt an activity on risk grounds | a threshold breach | immediate stop, founder notified |
| Escalate to the founder | regulatory, money movement, or irreversible | one page with the decision named |

**The register must carry, and today I have not confirmed that it does:** whether holding funds
between payment and reveal is a regulated stored-value activity under the UAE Central Bank; PDPL
exposure on a compiled contact list; single-provider dependency where one email suspension also takes
out login codes; and trade licence activity scope actually covering what the platform does.

**Measure.** The ratio of risks the process found to risks the founder found. A register that does not
contain what nearly happened is decoration.

**Today: `risk_register` holds 19 rows and `strategy_risks` holds 6. The identity gap — any PDF with a
readable number produces a verified, matchable supplier — was found by the founder doubting one
record, not by any risk process. On this measure the seat is failing.**

### 2.5 Operational alignment

**What it means here.** Making sure every department pulls toward the same constraint, and that a goal
which cannot be measured is either instrumented or killed.

**Decisions owned**

| Decision | Trigger | Rule |
|---|---|---|
| Resolve a cross-department conflict | any handoff breached twice | the seat decides; it does not mediate indefinitely |
| Instrument or kill an unmeasurable goal | monthly | a goal with no measure for two cycles is killed |
| Reassign a process split across departments | when one half has not run in 30 days | single owner end to end |

**Measure.** Share of active company goals that carry a real measure, and handoff SLA adherence.

**Today: 32 of 64 active company goals carry a measure and 32 carry a reason for having none. Exactly
half the company's goals cannot be checked.** And document control is split — understanding sits in
marketplace under procurement, verification sits in supply under business development, and the
verifying half has never executed once.

### 2.6 Team leadership

**What it means here.** Setting what good looks like per seat, managing performance, unblocking, and
deciding who gets more authority, who is retrained and who is retired.

**Decisions owned**

| Decision | Trigger | Rule |
|---|---|---|
| Raise or lower a seat's authority | quarterly, or after a material failure | evidence of decisions taken and their outcomes |
| Retrain or retire a seat | two consecutive review cycles with no business number moved | retire is the default, not the exception |
| Unblock | any seat blocked more than 48 hours | same-day decision |
| Resolve an escalation | any escalation reaching this seat | decide, never return it unanswered |

**Measure.** Share of seats that changed a business number this period; decision latency; escalations
resolved at the right level.

**Today: 32 of 54 seats have never decided anything. Zero tasks have ever reached `escalated` or
`failed`. Eleven tasks are blocked, the oldest for five days, with no timer on any of them.** By this
measure the company has 54 titles and roughly 20 workers.

### 2.7 Company culture

**What it means here.** Culture in this company is encoded behaviour, not language. The
non-negotiables the seat enforces:

1. Never fabricate a number, and never turn a gate green without the underlying thing being true.
2. A task is closed when an act was performed, never when the facts were merely recorded.
3. Bad news travels up early and by itself.
4. A measurement that covered a narrow thing never licenses a broad claim.

**Decisions owned:** what counts as a violation, and what happens to the seat that commits one.

**Measure.** Rate of tasks closed without an act performed, and the ratio of problems the company
found itself to problems the founder found.

**Today: 134 KPI-missed tasks were opened, 113 closed done, and every KPI they named is still missed.
The founder-found ratio for today's defects is close to 1.** That second number is the most damaging
cultural reading in the company.

### 2.8 Succession planning

**What it means here.** No decision may exist without a living owner. When a seat or role is retired,
its decision rights are handed over in the same act.

**Decisions owned**

| Decision | Trigger | Rule |
|---|---|---|
| Where a retiring role's decisions go | at retirement, in the same transaction | retirement is refused until every decision has a named inheritor |
| Which seats have no backup | quarterly | name one, or accept the risk explicitly |
| Key-person exposure | quarterly | what breaks if the founder is unreachable for two weeks |

**Measure.** Count of decision rights held by no active role. The correct value is zero.

**Today: 87.** Forty-one roles have been retired, every one carrying owned decisions, and 87 distinct
decisions from them are held by no active role. The Communications Manager parked on 3 September took
"channel choice for a lifecycle event" with it, and that was one of eighty-seven.

### 2.9 Public relations and access

**What it means here.** At this stage this is not brand work. It is the relationships that make cold
outreach unnecessary, and it is most of what a senior executive is actually worth.

**Decisions owned**

| Decision | Trigger | Output |
|---|---|---|
| Which partnership to pursue | quarterly, top three only | a named counterparty and what we offer them |
| What we say when something goes wrong | any incident with external visibility | a single approved statement, issued once |
| Whether to be present at an industry venue | as the calendar arises | cost against expected introductions |

**The specific targets for this company:** Dubai Chamber of Commerce and its member directory; the
contractor, MEP and fit-out trade associations; the handful of category distributors who already sell
to nearly every contractor in the emirate; and one anchor buyer posting enough volume that suppliers
want to join rather than needing persuasion.

**Measure.** Share of registrations arriving by introduction or referral rather than cold outreach.

**Today: zero, because registrations are zero. Every acquisition attempt has been cold email from a
domain running a 10% bounce rate.**

### 2.10 Problem solving

**What it means here.** The endpoint for problems no other seat can solve, and the owner of root cause
rather than symptom.

**Decisions owned**

| Decision | Trigger | Rule |
|---|---|---|
| Root cause accepted | any recurring alarm | the same alarm firing three times without a cause is itself the problem |
| Assign an unowned cross-functional problem | when no seat claims it within 24 hours | the seat assigns it, immediately |
| Decide under incomplete evidence | when waiting costs more than being wrong | record the assumption and the date it gets revisited |

**Measure.** Time from detection to resolution, recurrence rate, and how many problems the company
found before the founder did.

**Today: the backup silent-failure alarm fired on three consecutive days with the figure climbing
from 2,403 to 2,583 to 2,763 minutes, and was closed each time with no owner and no cause.**

---

## 3. Cadence

The operating rhythm. This is the floor of the job, not the job.

**Daily, about 45 minutes.** Read yesterday's raw inbound unedited, not a summary. Check the single
currently-binding number. Clear every decision another seat is waiting on, with a same-day deadline.
See any money leaving above the threshold.

**Weekly, about two hours.** Walk the funnel stage by stage against last week and name the constraint
out loud; if it has not moved in three weeks that is the entire session. Decide exactly one
experiment, with one variable and a pre-declared result that would change our mind. Two conversations
in person: one supplier who registered, one who was invited and did not. Publish the kill list. Decide
where the next dirham goes.

**Monthly, half a day.** Unit economics with real numbers or an explicit statement of what would
measure them. Category open and abandon decisions. Pricing checked against observed behaviour rather
than the plan. Seat-by-seat review of who moved a business number. Licence, VAT threshold and
compliance calendar. One honest page: what we said, what happened, what we learned, what changes.

**Quarterly.** Test the thesis and name what would make us wrong. Reallocate rather than increment.
Name the missing capability and decide build, buy or do without. Regulatory and competitive scan.

---

## 4. Authority and boundaries

The seat acts alone on everything except four things, which reach the founder and stop until he
answers: **money movement above the cap, refunds, destructive or irreversible production changes, and
facts only he holds** (his own intent, commercial relationships, tokens he must mint).

Everything else — reallocating budget inside the cap, retiring a seat, opening or abandoning a
category, stopping a workstream, changing an operational threshold — is this seat's to decide and to
defend in the record.

**Escalation is a failure mode, not a workflow.** A month with more than three escalations means the
boundary is drawn in the wrong place, and fixing that is itself this seat's job.

---

## 5. How it answers without a model

Every decision above resolves as: a **trigger query** fires, a **resolver** gathers named evidence
from named tables, **arithmetic** produces the options and ranks them, **thresholds** pick one, and a
**template** composes the answer from computed values and cited rows. Where no resolver matches, the
seat refuses honestly, names what it would need, and opens the task to get it. It never guesses and it
never says the AI service is unavailable, because no AI service is involved.

---

## 6. What separates a good one from a bad one

The weekly list is short. The constraint is named the same way two weeks running, or something
changed. The kill list is never empty. Bad news arrives from the seat rather than being discovered.
And the number of problems the founder finds by chance trends to zero.

---

## 7. Where this seat stands today, in one table

| Domain | Measure | Reading |
|---|---|---|
| Vision | seats that have ever decided | 22 of 54 |
| Strategic planning | constraint moved this quarter | no |
| Resource allocation | budget aimed at the constraint | AED 0 of 1,700 |
| Risk management | critical risks found by process vs founder | founder |
| Operational alignment | goals that can be measured | 32 of 64 |
| Team leadership | tasks ever escalated or failed | 0 |
| Culture | KPI tasks closed without an act | 113 of 134 |
| Succession | decisions with no living owner | 87 |
| PR and access | registrations by introduction | 0 |
| Problem solving | recurring alarms with a root cause | 0 of 3 |

Ten domains, ten measures, and not one of them currently reads acceptably. That is the honest
baseline this rebuild starts from.

---

## 8. Replace or build on: what happens to what already exists

Nothing here is a greenfield rewrite. Every element below is an explicit decision to keep, extend or
replace the machinery that is already in production.

### Keep as it is — these are correct and were not the problem

| What | Why it stays |
|---|---|
| `company_vision` | Already states the mandate and the autonomy principle correctly, since 24 July |
| `fn_binding_constraint` | Returns "NO INSTRUMENT EXISTS" rather than inventing a number. That honesty is the hardest part to build and it is already here |
| `fn_revenue_trajectory` | Computes live from the goal row, does not cache a stale figure |
| `v_unit_economics` | Reads `department_budget` live, which is why it says AED 1,700 while a hand-typed row elsewhere still says 7,700 |
| `org_agents` / `org_role`, the manager chain, the foreign keys | The org survived a re-carve with zero orphaned tasks. The schema did its job |
| `org_tasks` status constraint | All eight states are the right eight. The problem is that four are never reached, not that they are wrong |

### Build on top — the machinery exists and needs an addition, not a rewrite

| What exists | What gets added |
|---|---|
| `risk_register` (19 rows), `strategy_risks` (6) | An owner, a review date and a tested mitigation per row; plus the four missing entries: Central Bank stored-value, PDPL on the compiled list, single-provider dependency, licence activity scope |
| `company_goals`, 64 active | Instrument or kill the 32 that carry no measure. A goal that cannot be checked for two cycles dies |
| `fn_kpi_review` / `fn_kpi_scoreboard` | The scoreboard is right and the task it opens is correctly assigned. What gets added is the requirement that closing it needs an act |
| `org_role.owned_decisions` | A guard that refuses to retire a role until every decision it owns has a named inheritor, and a sweep that resolves the existing 87 |
| `department_budget` | The values change, the table does not. The split moves toward the constraint |
| `employee_kpi`, measured daily at 03:30 | The measurement is fine. What is missing is that variance travels the manager chain by itself |
| `v_deliverability`, `v_supplier_doc_score` | Both compute correctly and neither has a consumer. Give each a named reader |

### Replace outright — these actively produce a wrong outcome

| What | Why it goes |
|---|---|
| The deterministic close in mode `determined` | It marks a task done having only recorded the facts. 113 of 134 closed this way with every underlying KPI still missed. A close must carry a decision, a fallback rung taken, or an escalation, or the task stays open and ages |
| The old CEO question taxonomy, 44 types | It was built to answer questions. This seat exists to make decisions. Superseded entirely by section 2 |
| `fn_supplier_licence_gate` as the approval gate | It checks a document path, a licence number and an expiry, and nothing about identity. Replaced by the founder's six, with an OTP on the email and a UAE mobile confirming |
| The reply "I could not reach the AI service just now" | It blames an outage for a deliberate policy. Replaced by the truth: inference is held by founder order and no deterministic answer exists for this question yet |
| `leads.verification_status` | Dead on all 22,265 rows while `leads.verified` carries the real value. One of the two goes |

### The order this happens in

1. The succession guard, because 87 orphaned decisions is the reason work silently stops having an owner.
2. The close that must carry an act, because it is why nothing the company measures ever changes.
3. Variance travelling the manager chain, because that is what makes the seat above notice.
4. Then the identity gate, before any real supplier is ever invited again.

Each of the four is small, local, and provable by measurement in the same session it is built.
