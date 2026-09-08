# The CEO seat

The company's only decision-maker. The founder's instructions arrive here; the company's approvals
leave from here.

## What it is responsible for

**Receiving instructions.** `ceo_agent` (`action=command`) takes what the founder says, classifies it
deterministically against `ceo_command_rule`, records it in `ceo_command`, and turns it into work in
`ceo_task` when it asks for work.

The classifier is a pattern table and a rank, not a model call. Three tiers, and the order matters:
**framing (5) beats action verbs (10–60) beats topic words (90)**. A sentence is classified by what it
*does*, not what it is *about* — "refunds belong to the CEO from now on" is a standing rule, not an
order to decide a refund. Both of those tiers exist because the live probe got a real sentence wrong.

**Deciding.** Every approval in QuotesDone is the CEO's. Founder ruling, 8 September 2026:
*"all approvals are from CEO. nothing goes to me"*, and *"cause there is nothing to be approved by
founder"*. Decisions are recorded in `ceo_approval`, append-only, superseded rather than edited, and
`decided_by` must be an active row in `ceo_identity` — checked against a table, never trusted as
supplied.

**Refunds.** Replacing the 17 August rule that every refund needed the founder personally. The guards
on `public.refunds` refuse money reaching approved, processing or succeeded without a standing,
unsuperseded CEO decision. A refund request opens a `ceo_task` — a guard with no route is a refusal
with no path to a yes.

## What it must never do

- **Route anything to the founder for approval.** He is told things; he is not a step in a queue.
- **Let money move on a decision that cites nothing, or that has been superseded.** The hole this
  keeps shut is the refund that approved itself as `policy:auto_window`.
- **Close a task as done without evidence, or blocked without a reason.** Both are database CHECK
  constraints, not conventions, and `ceo_agent` returns the refusal verbatim rather than smoothing it.

## What it does not have yet

- **No model.** Every route in `llm_route_health` is held until 2126 under the founder's own hold, so
  the seat is entirely deterministic today. That is a limitation of the hold, not of the design — but
  the classifier is deliberately deterministic regardless, because an instruction from the founder
  must route the same way twice and be explainable by pointing at the row that matched.
- **No scheduled work.** `cron.job` holds one inactive job.
- **Not tested by the founder.** His words, 8 September: *"we dint finish the testing of the customer
  support agent thats why. once done we will start testing the CEO we build today."*
