# The office: who owns what, who hears what, who may decide what

Seat: ceo. 13 Nov 2026, founder ledger 1688 ("a shared pool where they all know what's going on around ... how is the
authority given from one and approvals from 1 to 2"). Narrative and index only: the source of truth is the database
(`public.event_subscription`, `public.ceo_standing_grant`, `public.seat_handoff_kind`) and
`supabase/functions/_shared/decision_point_grants.json`. Built by
`scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql`; checked by
`scripts/checks/every_seat_reads_one_pool.test.mjs` and `scripts/checks/every_report_and_handoff_comes_back.test.mjs`.

## 1. How a seat knows what the others did

Every seat's model path (think() for every seat's reasoning, the CEO's reviews and the IT postmortems; aiReply for
conversation replies; the CEO's judgement) reads ONE routine, `fn_seat_pool_context(seat, subject, audience)`, through
`_shared/seat_pool.ts`:

- **the subject's timeline across seats**: the last 6 things any seat did or decided about the same customer, supplier,
  request, quotation, payment or refund (events, hand-overs with their outcome, recorded judgements), newest first;
- **the company today** (internal readers only): counts of what this seat hears by digest in the last 24 hours, the
  notable items, and what waits on this seat; built once per 15 minutes per seat into `seat_pool_digest`, real and demo
  kept apart;
- **your hand-overs**: "no answer yet from <seat> since <time>" for this seat's own unanswered hand-overs.

A customer's or supplier's reply reads the timeline as kinds and states only (no name, no payload text). Budget: at most
1,300 characters (about 300 tokens); measured 13 Nov on production data, rolled back: company today alone 69-303
characters per seat, with a real supplier's timeline 280-514.

## 2. Who owns each event and who hears it (`public.event_subscription`, edit the rows there)

`delivery`: **digest** = the seat reads it in its company-today block; **handover** = the duty files a hand-over that
needs an answer (none seeded: every event that needs an answer already has a hand-over filed by its producer);
**none** = said, with the reason. A hand-over echo (`handoff.<kind>.<status>`) is owned by the receiver and read through
the hand-over row itself, which is why most say `none`.

| event type | seat | owns | how it hears | why |
|---|---|---|---|---|
| `customer.registered` | sales_engineer | OWNER | digest | a new customer is the start of customer intake (org_role: the sales engineer owns intake) |
| `customer.registered` | customer_support |  | digest | the customer may write in next; support answers knowing he is new |
| `customer.registered` | marketing |  | digest | registrations are the result marketing is measured on |
| `customer.registered` | ceo |  | digest | a count the CEO reads every day |
| `deploy.completed` | it_engineer | OWNER | digest | the IT engineer watches what the estate runs; a deploy is an engineering fact |
| `handoff.ceo.decision_closed.done` | accountant | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.ceo.decision_closed.sent` | accountant | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.ceo.decision_owed.done` | ceo | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.ceo.decision_owed.sent` | ceo | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.ceo.decision_owed.waiting` | ceo | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.ceo.directive.done` | accountant | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.ceo.directive.sent` | accountant | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.ceo.directive.waiting` | accountant | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.ceo.improvement.done` | accountant | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.ceo.improvement.sent` | accountant | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.ceo.improvement.waiting` | accountant | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.ceo.lesson_reapproval_overdue.sent` | ceo | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.ceo.lesson_reapproval_overdue.waiting` | ceo | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.ceo.month_directive.done` | accountant | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.ceo.month_directive.sent` | accountant | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.ceo.month_directive.waiting` | accountant | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.ceo.revise.done` | accountant | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.ceo.revise.sent` | accountant | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.ceo.revise.waiting` | accountant | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.ceo.root_cause.done` | accountant | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.ceo.root_cause.sent` | accountant | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.ceo.root_cause.waiting` | accountant | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.deliberation.review.done` | ceo | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.deliberation.review.reviewed` | ceo | OWNER | none | the reviewed echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.deliberation.review.sent` | ceo | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.deliberation.review.waiting` | ceo | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.delivery.request.done` | customer_support | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.delivery.request.sent` | customer_support | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.delivery.request.waiting` | customer_support | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.delivery.result.done` | accountant | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.delivery.result.sent` | accountant | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.invite.reply.done` | sales_engineer | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.invite.reply.sent` | sales_engineer | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.invite.reply.waiting` | sales_engineer | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.invoice.issued.done` | sales_engineer | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.invoice.issued.sent` | sales_engineer | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.it.finding.done` | accountant | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.it.finding.sent` | accountant | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.it.finding.waiting` | accountant | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.knowledge.request.done` | ceo | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.knowledge.request.sent` | ceo | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.knowledge.request.waiting` | ceo | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.mailbox.supplier_reply.done` | sales_engineer | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.mailbox.supplier_reply.sent` | sales_engineer | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.mailbox.supplier_reply.waiting` | sales_engineer | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.marketing.report.done` | ceo | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.marketing.report.sent` | ceo | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.marketing.review.done` | ceo | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.marketing.review.sent` | ceo | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.nonresponse.charge_raised.done` | sales_engineer | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.nonresponse.charge_raised.sent` | sales_engineer | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.overdue.escalated` | ceo | OWNER | digest | a hand-over past its reply window, escalated once to the sender's superior (this file) |
| `handoff.payment.exception.done` | ceo | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.payment.exception.sent` | ceo | OWNER | none | a hand-over: the receiver already holds it as work; its answer reaches the sender through the sender's subject timeline |
| `handoff.payment.exception.sent` | sales_engineer |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.payment.exception.sent` | customer_support |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.payment.exception.waiting` | ceo | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.payment.unrecorded.done` | it_engineer | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.payment.unrecorded.sent` | it_engineer | OWNER | none | a hand-over: the receiver already holds it as work; its answer reaches the sender through the sender's subject timeline |
| `handoff.payment.unrecorded.sent` | ceo |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.payment.unrecorded.sent` | sales_engineer |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.payment.unrecorded.sent` | customer_support |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.payment.unrecorded.waiting` | it_engineer | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.refund.paid.done` | sales_engineer | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.refund.paid.sent` | sales_engineer | OWNER | none | a hand-over: the receiver already holds it as work; its answer reaches the sender through the sender's subject timeline |
| `handoff.refund.paid.sent` | ceo |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.refund.paid.sent` | customer_support |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.refund.request_checked.done` | sales_engineer | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.refund.request_checked.sent` | sales_engineer | OWNER | none | a hand-over: the receiver already holds it as work; its answer reaches the sender through the sender's subject timeline |
| `handoff.refund.request_checked.sent` | ceo |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.refund.request_checked.sent` | customer_support |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.refund.request_checked.waiting` | sales_engineer | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.refund.requested.done` | accountant | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.refund.requested.sent` | accountant | OWNER | none | a hand-over: the receiver already holds it as work; its answer reaches the sender through the sender's subject timeline |
| `handoff.refund.requested.sent` | ceo |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.refund.requested.sent` | customer_support |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.refund.requested.waiting` | accountant | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.report.five_numbers.done` | ceo | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.report.five_numbers.sent` | ceo | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.reveal.paid.done` | sales_engineer | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.reveal.paid.sent` | sales_engineer | OWNER | none | a hand-over: the receiver already holds it as work; its answer reaches the sender through the sender's subject timeline |
| `handoff.reveal.paid.sent` | ceo |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.reveal.paid.sent` | customer_support |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.reveal.paid.waiting` | sales_engineer | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.reveal.reconcile.done` | accountant | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.reveal.reconcile.sent` | accountant | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.reveal.reconcile.waiting` | accountant | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.review.requested.sent` | accountant | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.review.requested.waiting` | accountant | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.sale.made.done` | ceo | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.sale.made.sent` | ceo | OWNER | none | a hand-over: the receiver already holds it as work; its answer reaches the sender through the sender's subject timeline |
| `handoff.sale.made.sent` | sales_engineer |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.sale.made.sent` | customer_support |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.sale.made.waiting` | ceo | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.spec.not_sure.done` | sales_engineer | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.spec.not_sure.sent` | sales_engineer | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.spec.not_sure.waiting` | sales_engineer | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.support.case_open.done` | customer_support | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.support.case_open.sent` | customer_support | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.support.case_open.waiting` | customer_support | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.support.root_cause.done` | accountant | OWNER | none | the done echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `handoff.support.root_cause.sent` | accountant | OWNER | none | a hand-over: the receiver already holds it as work and the sender reads its answer in its subject timeline; a second notice would be noise |
| `handoff.support.root_cause.waiting` | accountant | OWNER | none | the waiting echo of a hand-over; the hand-over row itself is the record both seats read (subject timeline, "no answer yet" line) |
| `invoice.received` | accountant | OWNER | digest | an expense invoice is the accountant's to capture and book |
| `invoice.received` | ceo |  | digest | spend is a CEO number (break-even) |
| `quote.received` | sales_engineer | OWNER | digest | the sales engineer reads every quotation (hold gate, comparison) |
| `quote.received` | customer_support |  | digest | the customer may ask about the quotation he just received |
| `quote.received` | ceo |  | digest | quotations in is one of the day's numbers |
| `request.reopened` | sales_engineer | OWNER | digest | the sales engineer reopens a paid request |
| `request.reopened` | accountant |  | digest | a reopened request moves the refund window |
| `request.reopened` | customer_support |  | digest | the customer may ask about the reopening |
| `request.reveal_outcome` | sales_engineer | OWNER | digest | the sales engineer closes a paid request (sales_engineer branch, 13 Nov) |
| `request.reveal_outcome` | accountant |  | digest | the refund window runs from the payment; the accountant must know the request's state |
| `request.reveal_outcome` | customer_support |  | digest | the customer may ask what happens next |
| `request.reveal_outcome` | ceo |  | digest | a sale's outcome is a CEO number |
| `request.reveal_period_ended` | sales_engineer | OWNER | digest | the sales engineer ends the reveal period |
| `request.reveal_period_ended` | accountant |  | digest | the refund window and the period end together |
| `request.reveal_period_ended` | customer_support |  | digest | the customer may ask why he can no longer reveal |
| `request.reveal_period_ended` | ceo |  | digest | a closed request is a CEO number |
| `request.step_failed` | sales_engineer | OWNER | digest | a step of a paid request failed; the sales engineer re-runs it |
| `request.step_failed` | it_engineer |  | digest | a failed step is a fault; the sales_engineer branch also files an IT finding, so this is a digest line, not a second hand-over |
| `request.step_failed` | ceo |  | digest | a failed step on a paid request is an exception the CEO should see |
| `rfq.classified` | sales_engineer | OWNER | digest | the sales engineer classified the request |
| `rfq.classified` | customer_support |  | digest | the customer may ask where his request stands |
| `rfq.classified` | ceo |  | digest | requests are one of the day's numbers |
| `rfq.created` | sales_engineer | OWNER | digest | a customer request is the sales engineer's to qualify and dispatch |
| `rfq.created` | customer_support |  | digest | the customer may ask where his request stands |
| `rfq.created` | ceo |  | digest | requests are one of the day's numbers |
| `supplier.applied` | sales_engineer | OWNER | digest | a supplier application is the sales engineer's to verify |
| `supplier.applied` | customer_support |  | digest | the applicant may write in while he waits |
| `supplier.applied` | marketing |  | digest | an application is the result of the supplier campaign |
| `supplier.applied` | it_engineer |  | digest | registration is a surface the IT engineer certifies |
| `supplier.applied` | ceo |  | digest | applications are one of the day's numbers |
| `supplier.approved` | sales_engineer | OWNER | digest | the sales engineer verified the supplier's licence and capability (org_role: supplier identity and capability verification) |
| `supplier.approved` | it_engineer |  | digest | founder 1688: the IT engineer must know a supplier was verified (his portal, his alerts, his registration checks) |
| `supplier.approved` | customer_support |  | digest | the supplier may write in next; support answers knowing he is approved |
| `supplier.approved` | marketing |  | digest | an invited supplier who is approved is marketing's conversion |
| `supplier.approved` | ceo |  | digest | suppliers approved is one of the day's numbers |
| `test.failed` | it_engineer | OWNER | digest | a scheduled check failed: the IT engineer diagnoses it (its own duties already read scheduled_run) |

## 3. Authority: who may decide what, where it is written, where it is enforced

| layer | where written | where enforced | state on 13 Nov |
|---|---|---|---|
| a seat's standing authority | `public.ceo_standing_grant` (23 rows; `sales.invitation` and `it.job_rerun` inactive; `accountant.refund_decision` and `accountant.meta_ads_spend` capped at AED 0) | `fn_agent_may_act(seat, action_class, amount)`, asked at call time by the it_engineer edge, the accountant's refund and seat actions, and the customer-support wrapper | most decide surfaces do not ask it (below) |
| what a seat owns / must not do | `public.org_role.owned_decisions`, `forbidden_decisions` | nothing: prose read by the model | |
| the CEO's approvals (refunds) | `public.ceo_approval` (append-only, 38 rows) | `fn_refund_execution_requires_ceo_approval` (trigger on the money), `fn_refund_decide` | enforced |
| the CEO's own authority | the founder's constitution, `the_ceo_is_the_final_internal_authority_and_nothing_waits_for_the_founder.sql` | by ruling | |
| the reporting line | `public.org_reporting_edge` (five seats -> ceo) | `fn_support_report_to_ceo`, `fn_handoff_overdue_escalate` | |
| department-era authority | `public.org_authority` (0 rows), `employee_authority` (320 rows) | `fn_org_authority_guard`, `fn_ops_authority_check`, `fn_task_approve` | dead: no live seat |

Each of the 121 decision points (`decision_points.json`) now names the grant it acts under in
`decision_point_grants.json`, or the gap. 100 name a grant; 21 name a gap:

| gap | decision points |
|---|---|
| quote readiness: org_role gives the sales engineer 'whether an inquiry is quote-ready and on what quote basis', and the hold gate reads, holds and releases a supplier's quotation, but no row of public.ceo_standing_grant names reading or holding a quotation | `sql.fn_quote_spec_group`, `line_specs.same_value`, `line_specs.vague`, `line_specs.assess`, `supplier_api.quote_review_match`, `line_specs.options_derive_vat`, `quote_extract.document`, `sql.fn_rfq_short_of_quotes_tick`, `sql.trg_quote_quality`, `line_specs.workflow_installation`, `documents.quote_duration_emirates`, `quote.line_specs_readerless`, `quote_review_notes.text_readings`, `quote_generalise.identity_terms` |
| supplier outreach: sales.invitation is INACTIVE since 9 Sep 2026 and marketing holds no outreach grant, yet this point classifies the replies to outreach that is being sent | `marketing.outreach_reply` |
| knowledge upkeep for every seat is decided in IT-owned code; the it_engineer's grants are monitoring, diagnosis and escalation, and its charter forbids it to act | `knowledge.support_ceo_vectors`, `knowledge.seat_lexeme_retrieval`, `knowledge.regulatory_review_date` |
| changing a person's mailing consent: support.reply covers answering a message, not recording an unsubscribe; no standing grant names it | `resend_inbound.unsubscribe_request`, `email.unsubscribe_request` |
| the department-era org_task queue: no live seat holds a grant over it (org_authority, its guard's table, has 0 rows) | `org_task.faq_answered` |

Approvals nothing checks: a grant is checked only where a seat's code calls `fn_agent_may_act`; the sales engineer's
matching and dispatch, marketing's publishing and the accountant's bookkeeping act under grants nothing asks at call time.
The CEO's approval is enforced only on refund money.

## 4. Why 196 hand-overs were open past their window (13 Nov)

All 196 had been answered by their receiver. Six were not late at all (five November month directives due 30 Nov and a directive due 16 Nov): the audit's count, and mine, ignored `detail.due_at`.

| cluster | n | cause | what changed |
|---|---|---|---|
| it.finding, fault still open | 162 | the it_engineer escalated each to the CEO (170 reports, all accepted = founder e-mailed as a new bug); fn_ceo_queue_work relists them daily on a "CEO queue overdue" task nothing decides; the CEO's model slot is unset and its think() runs never saw its queue | the CEO's every model call now carries "waiting on you"; the it_engineer's carries the 218 answered hand-overs it has not closed; the code fault itself still needs a fix |
| it.finding, fault cleared | 8 | the incident's cause/fix/regression check is blank; fn_it_loop_reverify waits for a person (file owned by the money-side branch) | not changed; reported |
| deliberation.review by a non-CEO author | 8 | fn_ceo_closes_answered_handoffs closes only deliberations the CEO wrote: no closer existed | fn_authors_close_reviewed_deliberations (1 closable on 13 Nov; the other 7 tasks are still working) |
| support.case_open, lesson reapproval, ceo.root_cause, knowledge.request, ceo.revise | 12 | the seat or the CEO owes the next move | escalated once by fn_handoff_overdue_escalate (13 on 13 Nov: 8 to the CEO, 5 CEO-own to the founder's brief) |
