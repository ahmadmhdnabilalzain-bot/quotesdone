# QuotesDone — the road to launch

**Written 27 August 2026, at the founder's request.**

The founder's standing instruction, 27 August: *"You need to come up with fixes and missing stuff
you believe we need to reach my target. I shouldn't be the one telling you do this and that."* So
this plan is mine to drive, not a menu for him to pick from. I own finding what is broken and what
is missing; he owns the boundaries (only refunds gate to him) and the target (a company that runs
itself toward the CEO's numbers).

Accordingly: the **zero-cost, under-the-hold** stages (0, 1, most of 4) I proceed with without
asking — that is what "don't make me tell you" means. The only stages that wait for an explicit
boundary decision are the ones that spend money or fire external effects (Stage 3's soak onward) and
Stage 2's supplier-acquisition dependency, because those cross the money/effects line the founder
drew, and that line is his, not mine.

## The bar this plan is built against

The founder stated it plainly on 27 August:

> "We have to launch it perfect, because once we launch I will be busy with another thing totally
> and will literally just check my email notifications in case a major issue happened. But in terms
> of the company operation, I am expecting the company to carry on by itself. That's why the CEO has
> targets. Accordingly the internal communication in the company should be 100% accurate so that
> these targets are reached."

And:

> "If more things apart from refunds require my approval then it's a major issue. Approvals are
> either by heads of departments, or higher management. I am literally not involved in any... if I
> didn't [request a change], then no agent should need me, even the CEO."

So the definition of done is **not** "a working MVP." It is:

1. **The company runs itself for a year with no feature changes and no human in the loop.** The only
   inbound human signal is the founder occasionally checking email for a major issue. Nobody catches
   drift for twelve months, so the chain of command must be provably correct, not approximately so.
2. **The only human approval gate is refunds.** Every other approval terminates at an AI department
   head or an AI officer, with correct authority. No agent — not even the CEO — ever waits on the
   founder for anything but a refund.
3. **The CEO's targets are pursued autonomously.** The org must decompose the CEO's targets into
   department objectives that actually drive 90 agents' behaviour, and drive toward them without
   supervision.

This is a company that must be **perfect at the moment of launch**, because there is no second
chance to patch a feature for a year.

## The two things that are NOT code, and are the founder's to decide

1. **A real, verified supplier base.** The marketplace cannot serve a customer with zero confirmed
   suppliers, and verifying a supplier is a real-world act, not a fixture. Apify scraping is paused
   until ~Feb 2027 by the founder's own instruction. Supplier acquisition is therefore a business
   decision that gates Stage 2, and no amount of code closes it alone.
2. **The soak spend.** A company that has never been allowed to spend cannot be *proven* to spend
   wisely by reasoning about it. The final proof — running the whole company unsupervised for a
   sustained window before the founder steps away — will cost real OpenRouter credits and send real
   effects, deliberately, as the last gate. "Zero cost" ends at Stage 3. The founder must budget for
   a multi-week live soak.

## The stages

Session counts are **estimates pending Stage 0's measurement.** The low end of each range assumes the
chain-of-command gap is moderate; the high end assumes it is severe. Stage 0 converts these from
guesses to commitments.

### Stage 0 — Measure the truth (1 session, zero cost, under the hold)

The one thing that must happen before any count is trustworthy. A company-wide, read-only scan on
production:

- Every one of the ~90 active agents: does it resolve to a live, correct manager?
- Every authority / decision-right grant: does it resolve, and is it held by the right role?
- Every review chain: does it resolve to a real reviewer who is neither the author nor a
  wrongly-placed subordinate?
- Every escalation path: does it terminate at an accountable AI head or officer — and does anything
  except a refund terminate at the founder?
- Every execution path across all 30 workflows: is it owned, or is it one of the ownerless paths?
- Any conflicting authorities (two roles both claiming one decision)?
- Do the 12-of-19 never-run runtime workflows have a real reason, or a wiring gap?

**Output:** exact numbers that size Stages 1–3. This is the honest prerequisite; the rest of this
plan's session counts are estimates until it runs.

### Stage 1 — Chain of command to 100% (2–4 sessions, zero cost, under the hold)

The heart of the founder's requirement #1 and #2. Fix everything Stage 0 surfaces:

- Every wrong manager, every ownerless path, every self-review or subordinate-reviews-boss defect.
- Every escalation re-terminated at the correct AI head/officer.
- The human gate reduced to **exactly refunds**: audit that nothing else reaches the founder, and
  that the refund gate is correct (guards the deciding row not the asking row, exempts
  Stripe-originated refunds, any amount).
- The reputation→authority loop verified safe (it must never strip authority for inactivity that the
  founder himself caused).

**Exit test:** a fresh company-wide scan returns 0 ownerless paths, 0 mis-wired managers, 0 bad
reviewers, 0 non-refund founder gates, 0 conflicting authorities.

### Stage 2 — End-to-end runtime proof (2–4 sessions + supplier dependency)

Prove the business actually runs, without the test harness seeding it.

- Make a real (non-fixture) inquiry flow customer → RFQ → match → quote → reveal → revenue, with
  every handoff accepted by an accountable owner.
- Make the 12 never-run workflows run.
- Stand up a working supplier base so the matching gate admits real leads (**blocked on the
  founder's supplier-acquisition decision — see above**).

**Exit test:** one real transaction completes end to end and earns one real dirham, with a full
decision trace and no harness involvement.

### Stage 3 — Autonomous operation toward targets, safely (3–5 sessions + calendar soak)

Wire and prove the self-driving part.

- CEO targets → department objectives → agent behaviour, verified to actually move agents.
- Cost governance correct for a year unsupervised (model routing, caching, budget guards) — spec
  file #8 territory; large-model tier was 76% of spend and accelerating, which is unacceptable for an
  unwatched year.
- Every external effect (email, OpenRouter, payments) correct and safe, because nobody is watching —
  this is Phase D's consequential-output work.
- Controlled re-activation of the automation the founder stood down, then a **sustained soak**: run
  the whole company for a meaningful window and prove it drives toward targets, needs the founder for
  nothing but refunds, and does not produce garbage. **This costs real credits, by design.**

**Exit test:** the company runs unsupervised for the soak window, pursues the CEO's targets, and the
founder's inbox stays quiet except for genuine major issues.

### Stage 4 — Phase D acceptance + the founder's visibility layer (2–3 sessions)

- Close the two open Phase D gates: FD-01 (governance approval authenticity) and FD-02
  (consequential output-field domains). These are the machinery that keeps autonomous decisions
  traceable and constrained — load-bearing for a year unsupervised.
- Make the founder's ONE channel flawless: email/WhatsApp notifications must surface every major
  issue and nothing trivial. If that is the only wire into a year-long absence, it must never spam
  and never stay silent on a real problem.
- Address the OS dashboard the founder was disappointed with on 10 August, to the extent it is his
  window in during the year.

### Stage 5 — Launch rehearsal and go/no-go (1–2 sessions + soak)

Full dress rehearsal with everything on, in a controlled window. Confirm targets are pursued, only
refunds reach the founder, cost is bounded, notifications work, and the chain of command holds under
real load. Then the go/no-go decision, which is the founder's.

## The honest total

**Roughly 12–18 working sessions, plus a multi-week live soak that costs real credits**, with two
things that can move it materially:

- **How large the chain-of-command gap actually is** — measured in Stage 0, not before.
- **The real-supplier dependency** — partly a business decision, not code, and it can add calendar
  time regardless of engineering pace.

Stages 0, 1, and most of 4 are zero-cost and can run entirely under the current holds. The cost and
the external effects begin at Stage 3's soak, deliberately, as the final proof — because a company
that has never spent cannot be certified to spend wisely without being watched doing it once.

## What this plan is not

It is not a promise that 12 sessions produces a perfect company. It is the honest shape of the work
and its dependencies. The single most important line in it is Stage 0: until the chain of command is
measured, every number here is an estimate, and the founder should hold me to replacing them with
committed numbers the moment that scan runs.
