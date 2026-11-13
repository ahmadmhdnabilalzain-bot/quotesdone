# The office: who owns what, who hears what, who may decide what

Seat: ceo. 13 Nov 2026, founder ledger 1688 ("a shared pool where they all know what's going on around ... how is the
authority given from one and approvals from 1 to 2"). Narrative and index only: the truth is the database
(`public.event_subscription`, `public.subject_link`, `public.ceo_standing_grant`, `public.seat_handoff_kind`,
`public.decision_policy` 'ceo_daily_judgements') and `supabase/functions/_shared/decision_point_grants.json`. Built by
`scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql`; applied as `docs/runbooks/apply-the-shared-pool.md`
says; checked by `scripts/checks/every_seat_reads_one_pool.test.mjs` and `scripts/checks/every_report_and_handoff_comes_back.test.mjs`.

## 1. How a seat knows what the others did

Every seat's model path (think() for every seat's reasoning, including the CEO's reviews and triage and the IT postmortems;
aiReply for conversation replies; the CEO's judgement) reads ONE routine, `fn_seat_pool_context(seat, subject, audience)`,
through `_shared/seat_pool.ts`, ordered by importance inside 1,200 characters (with its header at most 1,300, about 300 tokens):

1. **your hand-overs**: "NO ANSWER YET: <seat> on <kind> #id since <time> (escalated to <superior>)" and what waits on the seat;
2. **this subject**, newest first, as many lines as fit: every event, hand-over (with its outcome) and judgement linked to the
   same customer, supplier, request, quotation, payment, refund, support case or IT finding (`subject_link`, filled by
   `fn_pool_keys`, one resolver: a transaction is also its request, customer and supplier; a quote its request and supplier;
   a support case its party; a notification its person and request). The actor printed is the one recorded; else "the platform
   (automatic)";
3. **the company today**: what this seat hears by digest in the last 24 hours, in words ("a customer paid the reveal fee of
   AED 135.00 on request 151767 (painting, Dubai)"), no person's details; rebuilt every 15 minutes, real and demo apart.

A customer's or supplier's reply passes his own id and reads only his own events in neutral words ("a quotation was
received"): no seat, no hand-over, no other party, and a supplier no money event.

Coverage, measured 13 Nov (SELECT, 30 days, 24,371 hand-overs): 15,048 (62%) resolve to a customer, supplier, request,
quotation, payment or refund; 8,869 more to an IT finding: 23,917 (98%) to at least one subject. 454 remain, all company-internal
records (ceo_improvement 131, ceo_decision_round 111, sales_knowledge_gap 66, marketing_report 30, a support case with no party 29,
five_numbers 25 ...).

## 2. The CEO judges

Before 13 Nov the CEO decided nothing with a model. Its answer to an IT finding was code (`fn_seat_answers_it_finding`:
"acknowledged ... no deterministic remedy", replied in 0 s). Its operational judgement in `ceo_agent` waits on
`app_secrets.ceo_model_slot`, a key that has never existed (the only slot-like key is `social_model_enabled`), so that branch
has never run. Its other model work is scheduled reviews (knowledge refresh, management review, forecasts). The `think.answer`
judgements that "stopped on 1 Nov" were a knowledge quiz (questions such as "When NRR is greater than 100 percent, what is that
telling us?"): 323 on 19 Oct, 6 on 27 Oct, 5 on 1–2 Nov, none after. They were never decisions about the company's work, and no
commit stopped them: the batches simply ended. The accountant's model path is also idle (0 judgements in the last 7 days).

Now `fn_ceo_takes_it_finding` leaves the finding to the model. The `ceo.company_pool` duty (every 15 minutes) files at most
5 a tick (oldest and most severe first, then the hand-overs escalated to the CEO), under a daily cap held as data
(`decision_policy.ceo_daily_judgements`: 30 questions and AED 0.50 a day). Each is a held question that the existing replay
reasons with think() on the CEO's routine route.

- Choices for `ceo.it_finding`: `fix_now:<seat>` (within 7 days), `accept_risk` (14 days, then asked again),
  `duplicate_of:<id>`, `needs_founder:<money | destructive_production_change | fact_only_he_holds>`.
- Choices for `ceo.overdue_handoff`: `chase`, `wait`, `needs_founder:<category>`.
- What the CEO sees: the finding's evidence and the shared pool.
- Where the decision goes: onto the hand-over where the it_engineer reads it, and the it_engineer's next step (and the owning
  seat's, for fix_now) is filed as a `ceo.decision_closed` hand-over.
- What reaches the founder: a needs_founder question and the CEO's own overdue items, in one deduplicated note a day
  (`fn_notify_founder`, kind `ceo_needs_the_founder`).
- Cost: 1 model call a finding (no plan, no review), the CEO's routine call measured at AED 0.0106 (ai_cost_log, 30 days, 561
  calls). That is about AED 0.32 a day at the cap, and about AED 2.3 over about 7 days for the 216-finding backlog.
- The it.finding itself is still CLOSED by the it_engineer (its originator) when the fault clears; that loop's file is owned by
  the money-side branch.

## 3. Who owns each event and who hears it (`public.event_subscription`)

- **Owner**: the seat that PRODUCES the type. For a hand-over echo, the one seat that sends the kind; with several senders, the
  one that sent most in 30 days; with none seen, the receiver whose service it is.
- **Delivery**: `digest` = the company-today block; `handover` = a hand-over that needs an answer (`event.act`:
  request.step_failed, supplier.applied); `none` = said, with the reason.
- **Failed deliveries are not routed here**: a failed delivery.result already carries retry_request_id and escalation.
- **Edits are kept**: a row someone edits is stamped `edited_by`, and a re-run never overwrites it.

| event type | seat | owns | how it hears | why |
|---|---|---|---|---|
| `customer.registered` | sales_engineer | OWNER | digest | intake is the sales engineer's (org_role); the customer registers himself |
| `customer.registered` | customer_support |  | digest | he may write in next; support answers knowing he is new |
| `customer.registered` | marketing |  | digest | registrations are what marketing is measured on |
| `customer.registered` | ceo |  | digest | a number the CEO reads every day |
| `customer.registered` | accountant |  | none | nobody: a registration moves no money |
| `customer.registered` | it_engineer |  | none | nobody: sign-up faults reach IT as findings, not as this event |
| `deploy.completed` | it_engineer | OWNER | digest | the IT engineer watches what the estate runs |
| `deploy.completed` | ceo |  | none | nobody: an engineering fact; a failed deploy reaches him as a finding |
| `test.failed` | it_engineer | OWNER | digest | a scheduled check failed; IT diagnoses it (its duties read scheduled_run) |
| `test.failed` | ceo |  | none | nobody: IT files a finding when it matters |
| `quote.received` | sales_engineer | OWNER | digest | the sales engineer reads every quotation (hold gate, comparison) |
| `quote.received` | customer_support |  | digest | the customer may ask about it |
| `quote.received` | ceo |  | digest | quotations in is a daily number |
| `quote.received` | accountant |  | none | nobody until it is paid (reveal.paid) |
| `invoice.received` | accountant | OWNER | digest | an expense invoice is the accountant's to capture and book |
| `invoice.received` | ceo |  | digest | spend is a CEO number (break-even) |
| `supplier.approved` | sales_engineer | OWNER | digest | supplier verification is the sales engineer's (org_role); the row is written by code (fn_emit_supplier_approved, actor system), so the timeline says who approved only when it is recorded |
| `supplier.approved` | it_engineer |  | digest | founder 1688: IT must know a supplier was approved (his portal, his alerts) |
| `supplier.approved` | customer_support |  | digest | the supplier may write in next |
| `supplier.approved` | marketing |  | digest | an invited supplier approved is marketing's conversion |
| `supplier.approved` | ceo |  | digest | suppliers approved is a daily number |
| `supplier.applied` | sales_engineer | OWNER | handover | the sales engineer verifies the application; a hand-over makes the verification owed, not a duty that may skip it (the sales engineer verifies every application) |
| `supplier.applied` | customer_support |  | digest | the applicant may write in while he waits |
| `supplier.applied` | marketing |  | digest | an application is the campaign's result |
| `supplier.applied` | it_engineer |  | digest | registration is a surface IT certifies |
| `supplier.applied` | ceo |  | digest | applications are a daily number |
| `rfq.classified` | sales_engineer | OWNER | digest | the sales engineer classified the request |
| `rfq.classified` | customer_support |  | digest | the customer may ask where it stands |
| `rfq.classified` | ceo |  | digest | requests are a daily number |
| `rfq.created` | sales_engineer | OWNER | digest | a request is the sales engineer's to qualify and dispatch |
| `rfq.created` | customer_support |  | digest | the customer may ask where it stands |
| `rfq.created` | ceo |  | digest | requests are a daily number |
| `rfq.created` | marketing |  | digest | demand is what marketing is measured on |
| `request.reveal_outcome` | sales_engineer | OWNER | digest | the sales engineer closes a paid request (sales_engineer branch) |
| `request.reveal_outcome` | accountant |  | digest | the refund window runs from the payment |
| `request.reveal_outcome` | customer_support |  | digest | the customer may ask what happens next |
| `request.reveal_outcome` | ceo |  | digest | a sale's outcome is a CEO number |
| `request.reveal_period_ended` | sales_engineer | OWNER | digest | the sales engineer ends the reveal period |
| `request.reveal_period_ended` | accountant |  | digest | the refund window and the period end together |
| `request.reveal_period_ended` | customer_support |  | digest | the customer may ask why he can no longer reveal |
| `request.reveal_period_ended` | ceo |  | digest | a closed request is a CEO number |
| `request.reopened` | sales_engineer | OWNER | digest | the sales engineer reopens a paid request |
| `request.reopened` | accountant |  | digest | a reopened request moves the refund window |
| `request.reopened` | customer_support |  | digest | the customer may ask about it |
| `request.reopened` | ceo |  | digest | a reopened sale is an exception the CEO should see |
| `request.step_failed` | sales_engineer | OWNER | handover | the sales engineer re-runs the failed step of a paid request; a hand-over makes it work with a deadline, not a count (a step of a paid request failed and the sales engineer must re-run it) |
| `request.step_failed` | it_engineer |  | digest | a failed step is a fault (the branch also files a finding) |
| `request.step_failed` | ceo |  | digest | a failed step on a paid request is an exception |
| `handoff.overdue.escalated` | ceo | OWNER | digest | a hand-over past its window, escalated once to the sender's superior (this file); the CEO decides it (ceo.overdue_handoff) |
| `handoff.overdue.escalated` | it_engineer |  | none | nobody: the IT engineer reads its own overdue hand-overs in YOUR HAND-OVERS |
| `handoff.adspend.booked.sent` | accountant | OWNER | none | the one seat that sends adspend.booked; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.adspend.booked.sent` | marketing |  | none | marketing holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.adspend.booked.waiting` | accountant | OWNER | none | the one seat that sends adspend.booked; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.adspend.booked.waiting` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.adspend.booked.done` | accountant | OWNER | none | the one seat that sends adspend.booked; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.adspend.booked.done` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.adspend.booked.failed` | accountant | OWNER | digest | the one seat that sends adspend.booked; a failed hand-over is the sender's to re-send |
| `handoff.adspend.booked.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.adspend.recorded.sent` | marketing | OWNER | none | the one seat that sends adspend.recorded; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.adspend.recorded.sent` | accountant |  | none | accountant holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.adspend.recorded.waiting` | marketing | OWNER | none | the one seat that sends adspend.recorded; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.adspend.recorded.waiting` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.adspend.recorded.done` | marketing | OWNER | none | the one seat that sends adspend.recorded; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.adspend.recorded.done` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.adspend.recorded.failed` | marketing | OWNER | digest | the one seat that sends adspend.recorded; a failed hand-over is the sender's to re-send |
| `handoff.adspend.recorded.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.backup.refile.sent` | it_engineer | OWNER | none | the one seat that sends backup.refile; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.backup.refile.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.backup.refile.waiting` | it_engineer | OWNER | none | the one seat that sends backup.refile; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.backup.refile.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.backup.refile.done` | it_engineer | OWNER | none | the one seat that sends backup.refile; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.backup.refile.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.backup.refile.failed` | it_engineer | OWNER | digest | the one seat that sends backup.refile; a failed hand-over is the sender's to re-send; nobody else: the IT engineer is the owner and watches its own faults |
| `handoff.backup.remediate.sent` | ceo | OWNER | none | the one seat that sends backup.remediate; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.backup.remediate.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.backup.remediate.waiting` | ceo | OWNER | none | the one seat that sends backup.remediate; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.backup.remediate.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.backup.remediate.done` | ceo | OWNER | none | the one seat that sends backup.remediate; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.backup.remediate.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.backup.remediate.failed` | ceo | OWNER | digest | the one seat that sends backup.remediate; a failed hand-over is the sender's to re-send |
| `handoff.backup.remediate.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.billing.answer.sent` | accountant | OWNER | none | the one seat that sends billing.answer; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.billing.answer.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.billing.answer.waiting` | accountant | OWNER | none | the one seat that sends billing.answer; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.billing.answer.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.billing.answer.done` | accountant | OWNER | none | the one seat that sends billing.answer; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.billing.answer.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.billing.answer.failed` | accountant | OWNER | digest | the one seat that sends billing.answer; a failed hand-over is the sender's to re-send |
| `handoff.billing.answer.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.billing.question.sent` | sales_engineer | OWNER | none | the one seat that sends billing.question; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.billing.question.sent` | accountant |  | none | accountant holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.billing.question.waiting` | sales_engineer | OWNER | none | the one seat that sends billing.question; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.billing.question.waiting` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.billing.question.done` | sales_engineer | OWNER | none | the one seat that sends billing.question; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.billing.question.done` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.billing.question.failed` | sales_engineer | OWNER | digest | the one seat that sends billing.question; a failed hand-over is the sender's to re-send |
| `handoff.billing.question.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.ceo.decision_closed.sent` | ceo | OWNER | none | the one seat that sends ceo.decision_closed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.decision_closed.sent` | customer_support |  | none | customer_support holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.decision_closed.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.decision_closed.sent` | accountant |  | none | accountant holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.decision_closed.sent` | it_engineer |  | none | it_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.decision_closed.sent` | marketing |  | none | marketing holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.decision_closed.waiting` | ceo | OWNER | none | the one seat that sends ceo.decision_closed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.decision_closed.waiting` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.ceo.decision_closed.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.ceo.decision_closed.waiting` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.ceo.decision_closed.waiting` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.ceo.decision_closed.waiting` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.ceo.decision_closed.done` | ceo | OWNER | none | the one seat that sends ceo.decision_closed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.decision_closed.done` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.ceo.decision_closed.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.ceo.decision_closed.done` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.ceo.decision_closed.done` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.ceo.decision_closed.done` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.ceo.decision_closed.failed` | ceo | OWNER | digest | the one seat that sends ceo.decision_closed; a failed hand-over is the sender's to re-send |
| `handoff.ceo.decision_closed.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.ceo.decision_owed.sent` | it_engineer | OWNER | none | sent most of the ceo.decision_owed hand-overs in the last 30 days (1 of 1); the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.decision_owed.sent` | ceo |  | none | ceo holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.decision_owed.waiting` | it_engineer | OWNER | none | sent most of the ceo.decision_owed hand-overs in the last 30 days (1 of 1); the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.decision_owed.waiting` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.ceo.decision_owed.done` | it_engineer | OWNER | none | sent most of the ceo.decision_owed hand-overs in the last 30 days (1 of 1); the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.decision_owed.done` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.ceo.decision_owed.failed` | it_engineer | OWNER | digest | sent most of the ceo.decision_owed hand-overs in the last 30 days (1 of 1); a failed hand-over is the sender's to re-send; nobody else: the IT engineer is the owner and watches its own faults |
| `handoff.ceo.directive.sent` | ceo | OWNER | none | the one seat that sends ceo.directive; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.directive.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.directive.sent` | customer_support |  | none | customer_support holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.directive.sent` | accountant |  | none | accountant holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.directive.sent` | it_engineer |  | none | it_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.directive.sent` | marketing |  | none | marketing holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.directive.waiting` | ceo | OWNER | none | the one seat that sends ceo.directive; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.directive.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.ceo.directive.waiting` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.ceo.directive.waiting` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.ceo.directive.waiting` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.ceo.directive.waiting` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.ceo.directive.done` | ceo | OWNER | none | the one seat that sends ceo.directive; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.directive.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.ceo.directive.done` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.ceo.directive.done` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.ceo.directive.done` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.ceo.directive.done` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.ceo.directive.failed` | ceo | OWNER | digest | the one seat that sends ceo.directive; a failed hand-over is the sender's to re-send |
| `handoff.ceo.directive.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.ceo.improvement.sent` | ceo | OWNER | none | the one seat that sends ceo.improvement; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.improvement.sent` | accountant |  | none | accountant holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.improvement.sent` | it_engineer |  | none | it_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.improvement.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.improvement.sent` | customer_support |  | none | customer_support holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.improvement.sent` | marketing |  | none | marketing holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.improvement.waiting` | ceo | OWNER | none | the one seat that sends ceo.improvement; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.improvement.waiting` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.ceo.improvement.waiting` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.ceo.improvement.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.ceo.improvement.waiting` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.ceo.improvement.waiting` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.ceo.improvement.done` | ceo | OWNER | none | the one seat that sends ceo.improvement; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.improvement.done` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.ceo.improvement.done` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.ceo.improvement.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.ceo.improvement.done` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.ceo.improvement.done` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.ceo.improvement.failed` | ceo | OWNER | digest | the one seat that sends ceo.improvement; a failed hand-over is the sender's to re-send |
| `handoff.ceo.improvement.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.ceo.lesson_reapproval_overdue.sent` | it_engineer | OWNER | none | the one seat that sends ceo.lesson_reapproval_overdue; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.lesson_reapproval_overdue.sent` | ceo |  | none | ceo holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.lesson_reapproval_overdue.waiting` | it_engineer | OWNER | none | the one seat that sends ceo.lesson_reapproval_overdue; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.lesson_reapproval_overdue.waiting` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.ceo.lesson_reapproval_overdue.done` | it_engineer | OWNER | none | the one seat that sends ceo.lesson_reapproval_overdue; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.lesson_reapproval_overdue.done` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.ceo.lesson_reapproval_overdue.failed` | it_engineer | OWNER | digest | the one seat that sends ceo.lesson_reapproval_overdue; a failed hand-over is the sender's to re-send; nobody else: the IT engineer is the owner and watches its own faults |
| `handoff.ceo.month_directive.sent` | ceo | OWNER | none | the one seat that sends ceo.month_directive; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.month_directive.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.month_directive.sent` | customer_support |  | none | customer_support holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.month_directive.sent` | marketing |  | none | marketing holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.month_directive.sent` | accountant |  | none | accountant holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.month_directive.sent` | it_engineer |  | none | it_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.month_directive.waiting` | ceo | OWNER | none | the one seat that sends ceo.month_directive; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.month_directive.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.ceo.month_directive.waiting` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.ceo.month_directive.waiting` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.ceo.month_directive.waiting` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.ceo.month_directive.waiting` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.ceo.month_directive.done` | ceo | OWNER | none | the one seat that sends ceo.month_directive; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.month_directive.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.ceo.month_directive.done` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.ceo.month_directive.done` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.ceo.month_directive.done` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.ceo.month_directive.done` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.ceo.month_directive.failed` | ceo | OWNER | digest | the one seat that sends ceo.month_directive; a failed hand-over is the sender's to re-send |
| `handoff.ceo.month_directive.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.ceo.revise.sent` | ceo | OWNER | none | the one seat that sends ceo.revise; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.revise.sent` | customer_support |  | none | customer_support holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.revise.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.revise.sent` | accountant |  | none | accountant holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.revise.sent` | it_engineer |  | none | it_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.revise.sent` | marketing |  | none | marketing holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.revise.waiting` | ceo | OWNER | none | the one seat that sends ceo.revise; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.revise.waiting` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.ceo.revise.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.ceo.revise.waiting` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.ceo.revise.waiting` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.ceo.revise.waiting` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.ceo.revise.done` | ceo | OWNER | none | the one seat that sends ceo.revise; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.revise.done` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.ceo.revise.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.ceo.revise.done` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.ceo.revise.done` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.ceo.revise.done` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.ceo.revise.failed` | ceo | OWNER | digest | the one seat that sends ceo.revise; a failed hand-over is the sender's to re-send |
| `handoff.ceo.revise.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.ceo.root_cause.sent` | ceo | OWNER | none | the one seat that sends ceo.root_cause; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.root_cause.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.root_cause.sent` | customer_support |  | none | customer_support holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.root_cause.sent` | accountant |  | none | accountant holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.root_cause.sent` | it_engineer |  | none | it_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.root_cause.sent` | marketing |  | none | marketing holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.ceo.root_cause.waiting` | ceo | OWNER | none | the one seat that sends ceo.root_cause; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.root_cause.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.ceo.root_cause.waiting` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.ceo.root_cause.waiting` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.ceo.root_cause.waiting` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.ceo.root_cause.waiting` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.ceo.root_cause.done` | ceo | OWNER | none | the one seat that sends ceo.root_cause; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.ceo.root_cause.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.ceo.root_cause.done` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.ceo.root_cause.done` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.ceo.root_cause.done` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.ceo.root_cause.done` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.ceo.root_cause.failed` | ceo | OWNER | digest | the one seat that sends ceo.root_cause; a failed hand-over is the sender's to re-send |
| `handoff.ceo.root_cause.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.charge.corrected.sent` | accountant | OWNER | none | the one seat that sends charge.corrected; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.charge.corrected.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.charge.corrected.sent` | ceo |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.charge.corrected.sent` | customer_support |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.charge.corrected.waiting` | accountant | OWNER | none | the one seat that sends charge.corrected; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.charge.corrected.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.charge.corrected.done` | accountant | OWNER | none | the one seat that sends charge.corrected; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.charge.corrected.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.charge.corrected.failed` | accountant | OWNER | digest | the one seat that sends charge.corrected; a failed hand-over is the sender's to re-send |
| `handoff.charge.corrected.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.charge.dispute_answer.sent` | accountant | OWNER | none | the one seat that sends charge.dispute_answer; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.charge.dispute_answer.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.charge.dispute_answer.sent` | ceo |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.charge.dispute_answer.sent` | customer_support |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.charge.dispute_answer.waiting` | accountant | OWNER | none | the one seat that sends charge.dispute_answer; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.charge.dispute_answer.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.charge.dispute_answer.done` | accountant | OWNER | none | the one seat that sends charge.dispute_answer; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.charge.dispute_answer.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.charge.dispute_answer.failed` | accountant | OWNER | digest | the one seat that sends charge.dispute_answer; a failed hand-over is the sender's to re-send |
| `handoff.charge.dispute_answer.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.charge.disputed.sent` | sales_engineer | OWNER | none | the one seat that sends charge.disputed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.charge.disputed.sent` | accountant |  | none | accountant holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.charge.disputed.sent` | ceo |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.charge.disputed.sent` | customer_support |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.charge.disputed.waiting` | sales_engineer | OWNER | none | the one seat that sends charge.disputed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.charge.disputed.waiting` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.charge.disputed.done` | sales_engineer | OWNER | none | the one seat that sends charge.disputed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.charge.disputed.done` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.charge.disputed.failed` | sales_engineer | OWNER | digest | the one seat that sends charge.disputed; a failed hand-over is the sender's to re-send |
| `handoff.charge.disputed.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.complaint.due.sent` | customer_support | OWNER | none | the one seat that sends complaint.due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.complaint.due.waiting` | customer_support | OWNER | none | the one seat that sends complaint.due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat's hand-over to itself; its own queue is the record |
| `handoff.complaint.due.done` | customer_support | OWNER | none | the one seat that sends complaint.due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat's hand-over to itself; its own queue is the record |
| `handoff.complaint.due.failed` | customer_support | OWNER | digest | the one seat that sends complaint.due; a failed hand-over is the sender's to re-send |
| `handoff.complaint.due.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.data.correction.sent` | customer_support | OWNER | none | the one seat that sends data.correction; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.data.correction.sent` | it_engineer |  | none | it_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.data.correction.waiting` | customer_support | OWNER | none | the one seat that sends data.correction; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.data.correction.waiting` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.data.correction.done` | customer_support | OWNER | none | the one seat that sends data.correction; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.data.correction.done` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.data.correction.failed` | customer_support | OWNER | digest | the one seat that sends data.correction; a failed hand-over is the sender's to re-send |
| `handoff.data.correction.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.deliberation.review.sent` | ceo | OWNER | none | sent most of the deliberation.review hand-overs in the last 30 days (4 of 13); the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.deliberation.review.sent` | marketing |  | none | marketing holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.deliberation.review.sent` | accountant |  | none | accountant holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.deliberation.review.waiting` | ceo | OWNER | none | sent most of the deliberation.review hand-overs in the last 30 days (4 of 13); the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.deliberation.review.waiting` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.deliberation.review.waiting` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.deliberation.review.done` | ceo | OWNER | none | sent most of the deliberation.review hand-overs in the last 30 days (4 of 13); the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.deliberation.review.done` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.deliberation.review.done` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.deliberation.review.failed` | ceo | OWNER | digest | sent most of the deliberation.review hand-overs in the last 30 days (4 of 13); a failed hand-over is the sender's to re-send |
| `handoff.deliberation.review.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.deliberation.review.reviewed` | ceo | OWNER | none | sent most of the deliberation.review hand-overs in the last 30 days (4 of 13); the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.deliberation.review.reviewed` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.deliberation.review.reviewed` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.deliberation.rework.sent` | ceo | OWNER | none | the one seat that sends deliberation.rework; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.deliberation.rework.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.deliberation.rework.sent` | customer_support |  | none | customer_support holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.deliberation.rework.sent` | marketing |  | none | marketing holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.deliberation.rework.sent` | accountant |  | none | accountant holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.deliberation.rework.sent` | it_engineer |  | none | it_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.deliberation.rework.waiting` | ceo | OWNER | none | the one seat that sends deliberation.rework; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.deliberation.rework.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.deliberation.rework.waiting` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.deliberation.rework.waiting` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.deliberation.rework.waiting` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.deliberation.rework.waiting` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.deliberation.rework.done` | ceo | OWNER | none | the one seat that sends deliberation.rework; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.deliberation.rework.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.deliberation.rework.done` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.deliberation.rework.done` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.deliberation.rework.done` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.deliberation.rework.done` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.deliberation.rework.failed` | ceo | OWNER | digest | the one seat that sends deliberation.rework; a failed hand-over is the sender's to re-send |
| `handoff.deliberation.rework.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.deliverability.inbox_placement.sent` | it_engineer | OWNER | none | the one seat that sends deliverability.inbox_placement; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.deliverability.inbox_placement.sent` | marketing |  | none | marketing holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.deliverability.inbox_placement.waiting` | it_engineer | OWNER | none | the one seat that sends deliverability.inbox_placement; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.deliverability.inbox_placement.waiting` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.deliverability.inbox_placement.done` | it_engineer | OWNER | none | the one seat that sends deliverability.inbox_placement; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.deliverability.inbox_placement.done` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.deliverability.inbox_placement.failed` | it_engineer | OWNER | digest | the one seat that sends deliverability.inbox_placement; a failed hand-over is the sender's to re-send; nobody else: the IT engineer is the owner and watches its own faults |
| `handoff.delivery.remediate.sent` | ceo | OWNER | none | the one seat that sends delivery.remediate; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.delivery.remediate.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.delivery.remediate.waiting` | ceo | OWNER | none | the one seat that sends delivery.remediate; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.delivery.remediate.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.delivery.remediate.done` | ceo | OWNER | none | the one seat that sends delivery.remediate; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.delivery.remediate.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.delivery.remediate.failed` | ceo | OWNER | digest | the one seat that sends delivery.remediate; a failed hand-over is the sender's to re-send |
| `handoff.delivery.remediate.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.delivery.request.sent` | sales_engineer | OWNER | none | sent most of the delivery.request hand-overs in the last 30 days (4365 of 9105); the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.delivery.request.sent` | customer_support |  | none | customer_support holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.delivery.request.waiting` | sales_engineer | OWNER | none | sent most of the delivery.request hand-overs in the last 30 days (4365 of 9105); the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.delivery.request.waiting` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.delivery.request.done` | sales_engineer | OWNER | none | sent most of the delivery.request hand-overs in the last 30 days (4365 of 9105); the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.delivery.request.done` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.delivery.request.failed` | sales_engineer | OWNER | digest | sent most of the delivery.request hand-overs in the last 30 days (4365 of 9105); a failed hand-over is the sender's to re-send |
| `handoff.delivery.request.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.delivery.result.sent` | customer_support | OWNER | none | the one seat that sends delivery.result; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.delivery.result.sent` | marketing |  | none | marketing holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.delivery.result.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.delivery.result.sent` | accountant |  | none | accountant holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.delivery.result.sent` | ceo |  | none | ceo holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.delivery.result.sent` | it_engineer |  | none | it_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.delivery.result.waiting` | customer_support | OWNER | none | the one seat that sends delivery.result; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.delivery.result.waiting` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.delivery.result.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.delivery.result.waiting` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.delivery.result.waiting` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.delivery.result.waiting` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.delivery.result.done` | customer_support | OWNER | none | the one seat that sends delivery.result; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.delivery.result.done` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.delivery.result.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.delivery.result.done` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.delivery.result.done` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.delivery.result.done` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.delivery.result.failed` | customer_support | OWNER | digest | the one seat that sends delivery.result; a failed hand-over is the sender's to re-send |
| `handoff.delivery.result.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.event.act.sent` | sales_engineer | OWNER | none | the one seat that sends event.act; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat's hand-over to itself; its own queue is the record |
| `handoff.event.act.waiting` | sales_engineer | OWNER | none | the one seat that sends event.act; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat's hand-over to itself; its own queue is the record |
| `handoff.event.act.done` | sales_engineer | OWNER | none | the one seat that sends event.act; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat's hand-over to itself; its own queue is the record |
| `handoff.event.act.failed` | sales_engineer | OWNER | digest | the one seat that sends event.act; a failed hand-over is the sender's to re-send |
| `handoff.event.act.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.fraud.money_held.sent` | accountant | OWNER | none | the one seat that sends fraud.money_held; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.fraud.money_held.sent` | customer_support |  | none | customer_support holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.fraud.money_held.sent` | ceo |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.fraud.money_held.sent` | sales_engineer |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.fraud.money_held.waiting` | accountant | OWNER | none | the one seat that sends fraud.money_held; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.fraud.money_held.waiting` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.fraud.money_held.done` | accountant | OWNER | none | the one seat that sends fraud.money_held; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.fraud.money_held.done` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.fraud.money_held.failed` | accountant | OWNER | digest | the one seat that sends fraud.money_held; a failed hand-over is the sender's to re-send |
| `handoff.fraud.money_held.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.fraud.money_released.sent` | accountant | OWNER | none | the one seat that sends fraud.money_released; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.fraud.money_released.sent` | customer_support |  | none | customer_support holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.fraud.money_released.sent` | ceo |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.fraud.money_released.sent` | sales_engineer |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.fraud.money_released.waiting` | accountant | OWNER | none | the one seat that sends fraud.money_released; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.fraud.money_released.waiting` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.fraud.money_released.done` | accountant | OWNER | none | the one seat that sends fraud.money_released; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.fraud.money_released.done` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.fraud.money_released.failed` | accountant | OWNER | digest | the one seat that sends fraud.money_released; a failed hand-over is the sender's to re-send |
| `handoff.fraud.money_released.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.incident.fix.sent` | ceo | OWNER | none | the one seat that sends incident.fix; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.incident.fix.sent` | accountant |  | none | accountant holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.incident.fix.waiting` | ceo | OWNER | none | the one seat that sends incident.fix; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.incident.fix.waiting` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.incident.fix.done` | ceo | OWNER | none | the one seat that sends incident.fix; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.incident.fix.done` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.incident.fix.failed` | ceo | OWNER | digest | the one seat that sends incident.fix; a failed hand-over is the sender's to re-send |
| `handoff.incident.fix.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.inquiry.status_chase.sent` | customer_support | OWNER | none | the one seat that sends inquiry.status_chase; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.inquiry.status_chase.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.inquiry.status_chase.waiting` | customer_support | OWNER | none | the one seat that sends inquiry.status_chase; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.inquiry.status_chase.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.inquiry.status_chase.done` | customer_support | OWNER | none | the one seat that sends inquiry.status_chase; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.inquiry.status_chase.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.inquiry.status_chase.failed` | customer_support | OWNER | digest | the one seat that sends inquiry.status_chase; a failed hand-over is the sender's to re-send |
| `handoff.inquiry.status_chase.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.invite.reply.sent` | marketing | OWNER | none | the one seat that sends invite.reply; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.invite.reply.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.invite.reply.waiting` | marketing | OWNER | none | the one seat that sends invite.reply; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.invite.reply.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.invite.reply.done` | marketing | OWNER | none | the one seat that sends invite.reply; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.invite.reply.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.invite.reply.failed` | marketing | OWNER | digest | the one seat that sends invite.reply; a failed hand-over is the sender's to re-send |
| `handoff.invite.reply.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.invoice.issued.sent` | accountant | OWNER | none | the one seat that sends invoice.issued; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.invoice.issued.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.invoice.issued.waiting` | accountant | OWNER | none | the one seat that sends invoice.issued; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.invoice.issued.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.invoice.issued.done` | accountant | OWNER | none | the one seat that sends invoice.issued; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.invoice.issued.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.invoice.issued.failed` | accountant | OWNER | digest | the one seat that sends invoice.issued; a failed hand-over is the sender's to re-send |
| `handoff.invoice.issued.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.it.finding.sent` | it_engineer | OWNER | none | the one seat that sends it.finding; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.it.finding.sent` | marketing |  | none | marketing holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.it.finding.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.it.finding.sent` | accountant |  | none | accountant holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.it.finding.sent` | customer_support |  | none | customer_support holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.it.finding.sent` | ceo |  | none | ceo holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.it.finding.waiting` | it_engineer | OWNER | none | the one seat that sends it.finding; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.it.finding.waiting` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.it.finding.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.it.finding.waiting` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.it.finding.waiting` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.it.finding.waiting` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.it.finding.done` | it_engineer | OWNER | none | the one seat that sends it.finding; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.it.finding.done` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.it.finding.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.it.finding.done` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.it.finding.done` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.it.finding.done` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.it.finding.failed` | it_engineer | OWNER | digest | the one seat that sends it.finding; a failed hand-over is the sender's to re-send; nobody else: the IT engineer is the owner and watches its own faults |
| `handoff.knowledge.request.sent` | customer_support | OWNER | none | the one seat that sends knowledge.request; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.knowledge.request.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.knowledge.request.sent` | ceo |  | none | ceo holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.knowledge.request.waiting` | customer_support | OWNER | none | the one seat that sends knowledge.request; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.knowledge.request.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.knowledge.request.waiting` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.knowledge.request.done` | customer_support | OWNER | none | the one seat that sends knowledge.request; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.knowledge.request.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.knowledge.request.done` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.knowledge.request.failed` | customer_support | OWNER | digest | the one seat that sends knowledge.request; a failed hand-over is the sender's to re-send |
| `handoff.knowledge.request.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.mailbox.supplier_reply.sent` | marketing | OWNER | none | the one seat that sends mailbox.supplier_reply; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.mailbox.supplier_reply.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.mailbox.supplier_reply.waiting` | marketing | OWNER | none | the one seat that sends mailbox.supplier_reply; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.mailbox.supplier_reply.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.mailbox.supplier_reply.done` | marketing | OWNER | none | the one seat that sends mailbox.supplier_reply; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.mailbox.supplier_reply.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.mailbox.supplier_reply.failed` | marketing | OWNER | digest | the one seat that sends mailbox.supplier_reply; a failed hand-over is the sender's to re-send |
| `handoff.mailbox.supplier_reply.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.marketing.lead_sourcing.sent` | marketing | OWNER | none | the one seat that sends marketing.lead_sourcing; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.marketing.lead_sourcing.sent` | ceo |  | none | ceo holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.marketing.lead_sourcing.waiting` | marketing | OWNER | none | the one seat that sends marketing.lead_sourcing; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.marketing.lead_sourcing.waiting` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.marketing.lead_sourcing.done` | marketing | OWNER | none | the one seat that sends marketing.lead_sourcing; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.marketing.lead_sourcing.done` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.marketing.lead_sourcing.failed` | marketing | OWNER | digest | the one seat that sends marketing.lead_sourcing; a failed hand-over is the sender's to re-send |
| `handoff.marketing.lead_sourcing.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.marketing.report.sent` | marketing | OWNER | none | the one seat that sends marketing.report; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.marketing.report.sent` | ceo |  | none | ceo holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.marketing.report.waiting` | marketing | OWNER | none | the one seat that sends marketing.report; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.marketing.report.waiting` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.marketing.report.done` | marketing | OWNER | none | the one seat that sends marketing.report; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.marketing.report.done` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.marketing.report.failed` | marketing | OWNER | digest | the one seat that sends marketing.report; a failed hand-over is the sender's to re-send |
| `handoff.marketing.report.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.marketing.review.sent` | marketing | OWNER | none | the one seat that sends marketing.review; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.marketing.review.sent` | ceo |  | none | ceo holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.marketing.review.waiting` | marketing | OWNER | none | the one seat that sends marketing.review; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.marketing.review.waiting` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.marketing.review.done` | marketing | OWNER | none | the one seat that sends marketing.review; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.marketing.review.done` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.marketing.review.failed` | marketing | OWNER | digest | the one seat that sends marketing.review; a failed hand-over is the sender's to re-send |
| `handoff.marketing.review.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.nonresponse.charge_raised.sent` | accountant | OWNER | none | the one seat that sends nonresponse.charge_raised; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.nonresponse.charge_raised.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.nonresponse.charge_raised.waiting` | accountant | OWNER | none | the one seat that sends nonresponse.charge_raised; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.nonresponse.charge_raised.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.nonresponse.charge_raised.done` | accountant | OWNER | none | the one seat that sends nonresponse.charge_raised; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.nonresponse.charge_raised.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.nonresponse.charge_raised.failed` | accountant | OWNER | digest | the one seat that sends nonresponse.charge_raised; a failed hand-over is the sender's to re-send |
| `handoff.nonresponse.charge_raised.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.nonresponse.charge_reminder.sent` | accountant | OWNER | none | the one seat that sends nonresponse.charge_reminder; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.nonresponse.charge_reminder.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.nonresponse.charge_reminder.waiting` | accountant | OWNER | none | the one seat that sends nonresponse.charge_reminder; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.nonresponse.charge_reminder.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.nonresponse.charge_reminder.done` | accountant | OWNER | none | the one seat that sends nonresponse.charge_reminder; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.nonresponse.charge_reminder.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.nonresponse.charge_reminder.failed` | accountant | OWNER | digest | the one seat that sends nonresponse.charge_reminder; a failed hand-over is the sender's to re-send |
| `handoff.nonresponse.charge_reminder.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.nonresponse.final_demand.sent` | accountant | OWNER | none | the one seat that sends nonresponse.final_demand; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.nonresponse.final_demand.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.nonresponse.final_demand.waiting` | accountant | OWNER | none | the one seat that sends nonresponse.final_demand; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.nonresponse.final_demand.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.nonresponse.final_demand.done` | accountant | OWNER | none | the one seat that sends nonresponse.final_demand; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.nonresponse.final_demand.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.nonresponse.final_demand.failed` | accountant | OWNER | digest | the one seat that sends nonresponse.final_demand; a failed hand-over is the sender's to re-send |
| `handoff.nonresponse.final_demand.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.overcharge.customer_notice.sent` | accountant | OWNER | none | the one seat that sends overcharge.customer_notice; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.overcharge.customer_notice.sent` | customer_support |  | none | customer_support holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.overcharge.customer_notice.sent` | ceo |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.overcharge.customer_notice.sent` | sales_engineer |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.overcharge.customer_notice.waiting` | accountant | OWNER | none | the one seat that sends overcharge.customer_notice; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.overcharge.customer_notice.waiting` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.overcharge.customer_notice.done` | accountant | OWNER | none | the one seat that sends overcharge.customer_notice; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.overcharge.customer_notice.done` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.overcharge.customer_notice.failed` | accountant | OWNER | digest | the one seat that sends overcharge.customer_notice; a failed hand-over is the sender's to re-send |
| `handoff.overcharge.customer_notice.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.payment.exception.sent` | accountant | OWNER | none | the one seat that sends payment.exception; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.payment.exception.sent` | ceo |  | none | ceo holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.payment.exception.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.payment.exception.sent` | customer_support |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.payment.exception.waiting` | accountant | OWNER | none | the one seat that sends payment.exception; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.payment.exception.waiting` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.payment.exception.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.payment.exception.done` | accountant | OWNER | none | the one seat that sends payment.exception; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.payment.exception.done` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.payment.exception.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.payment.exception.failed` | accountant | OWNER | digest | the one seat that sends payment.exception; a failed hand-over is the sender's to re-send |
| `handoff.payment.exception.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.payment.failed.sent` | accountant | OWNER | none | the one seat that sends payment.failed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.payment.failed.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.payment.failed.sent` | ceo |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.payment.failed.sent` | customer_support |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.payment.failed.waiting` | accountant | OWNER | none | the one seat that sends payment.failed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.payment.failed.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.payment.failed.done` | accountant | OWNER | none | the one seat that sends payment.failed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.payment.failed.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.payment.failed.failed` | accountant | OWNER | digest | the one seat that sends payment.failed; a failed hand-over is the sender's to re-send |
| `handoff.payment.failed.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.payment.received.sent` | accountant | OWNER | none | the one seat that sends payment.received; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.payment.received.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.payment.received.sent` | ceo |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.payment.received.sent` | customer_support |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.payment.received.waiting` | accountant | OWNER | none | the one seat that sends payment.received; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.payment.received.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.payment.received.done` | accountant | OWNER | none | the one seat that sends payment.received; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.payment.received.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.payment.received.failed` | accountant | OWNER | digest | the one seat that sends payment.received; a failed hand-over is the sender's to re-send |
| `handoff.payment.received.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.payment.unrecorded.sent` | accountant | OWNER | none | the one seat that sends payment.unrecorded; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.payment.unrecorded.sent` | it_engineer |  | none | it_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.payment.unrecorded.sent` | customer_support |  | none | customer_support holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.payment.unrecorded.sent` | ceo |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.payment.unrecorded.sent` | sales_engineer |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.payment.unrecorded.waiting` | accountant | OWNER | none | the one seat that sends payment.unrecorded; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.payment.unrecorded.waiting` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.payment.unrecorded.waiting` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.payment.unrecorded.done` | accountant | OWNER | none | the one seat that sends payment.unrecorded; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.payment.unrecorded.done` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.payment.unrecorded.done` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.payment.unrecorded.failed` | accountant | OWNER | digest | the one seat that sends payment.unrecorded; a failed hand-over is the sender's to re-send |
| `handoff.payment.unrecorded.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.refund.declined.sent` | accountant | OWNER | none | the one seat that sends refund.declined; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.refund.declined.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.refund.declined.sent` | ceo |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.refund.declined.sent` | customer_support |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.refund.declined.waiting` | accountant | OWNER | none | the one seat that sends refund.declined; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.refund.declined.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.refund.declined.done` | accountant | OWNER | none | the one seat that sends refund.declined; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.refund.declined.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.refund.declined.failed` | accountant | OWNER | digest | the one seat that sends refund.declined; a failed hand-over is the sender's to re-send |
| `handoff.refund.declined.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.refund.in_progress.sent` | accountant | OWNER | none | the one seat that sends refund.in_progress; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.refund.in_progress.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.refund.in_progress.sent` | ceo |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.refund.in_progress.sent` | customer_support |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.refund.in_progress.waiting` | accountant | OWNER | none | the one seat that sends refund.in_progress; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.refund.in_progress.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.refund.in_progress.done` | accountant | OWNER | none | the one seat that sends refund.in_progress; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.refund.in_progress.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.refund.in_progress.failed` | accountant | OWNER | digest | the one seat that sends refund.in_progress; a failed hand-over is the sender's to re-send |
| `handoff.refund.in_progress.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.refund.paid.sent` | accountant | OWNER | none | the one seat that sends refund.paid; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.refund.paid.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.refund.paid.sent` | ceo |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.refund.paid.sent` | customer_support |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.refund.paid.waiting` | accountant | OWNER | none | the one seat that sends refund.paid; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.refund.paid.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.refund.paid.done` | accountant | OWNER | none | the one seat that sends refund.paid; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.refund.paid.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.refund.paid.failed` | accountant | OWNER | digest | the one seat that sends refund.paid; a failed hand-over is the sender's to re-send |
| `handoff.refund.paid.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.refund.remediate.sent` | ceo | OWNER | none | the one seat that sends refund.remediate; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.refund.remediate.sent` | accountant |  | none | accountant holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.refund.remediate.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.refund.remediate.sent` | customer_support |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.refund.remediate.waiting` | ceo | OWNER | none | the one seat that sends refund.remediate; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.refund.remediate.waiting` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.refund.remediate.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.refund.remediate.done` | ceo | OWNER | none | the one seat that sends refund.remediate; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.refund.remediate.done` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.refund.remediate.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.refund.remediate.failed` | ceo | OWNER | digest | the one seat that sends refund.remediate; a failed hand-over is the sender's to re-send |
| `handoff.refund.remediate.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.refund.request_checked.sent` | accountant | OWNER | none | the one seat that sends refund.request_checked; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.refund.request_checked.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.refund.request_checked.sent` | ceo |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.refund.request_checked.sent` | customer_support |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.refund.request_checked.waiting` | accountant | OWNER | none | the one seat that sends refund.request_checked; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.refund.request_checked.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.refund.request_checked.done` | accountant | OWNER | none | the one seat that sends refund.request_checked; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.refund.request_checked.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.refund.request_checked.failed` | accountant | OWNER | digest | the one seat that sends refund.request_checked; a failed hand-over is the sender's to re-send |
| `handoff.refund.request_checked.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.refund.requested.sent` | sales_engineer | OWNER | none | the one seat that sends refund.requested; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.refund.requested.sent` | accountant |  | none | accountant holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.refund.requested.sent` | ceo |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.refund.requested.sent` | customer_support |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.refund.requested.waiting` | sales_engineer | OWNER | none | the one seat that sends refund.requested; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.refund.requested.waiting` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.refund.requested.done` | sales_engineer | OWNER | none | the one seat that sends refund.requested; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.refund.requested.done` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.refund.requested.failed` | sales_engineer | OWNER | digest | the one seat that sends refund.requested; a failed hand-over is the sender's to re-send |
| `handoff.refund.requested.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.renewal.due.sent` | it_engineer | OWNER | none | the one seat that sends renewal.due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.renewal.due.sent` | accountant |  | none | accountant holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.renewal.due.waiting` | it_engineer | OWNER | none | the one seat that sends renewal.due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.renewal.due.waiting` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.renewal.due.done` | it_engineer | OWNER | none | the one seat that sends renewal.due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.renewal.due.done` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.renewal.due.failed` | it_engineer | OWNER | digest | the one seat that sends renewal.due; a failed hand-over is the sender's to re-send; nobody else: the IT engineer is the owner and watches its own faults |
| `handoff.report.five_numbers.sent` | ceo | OWNER | none | the one seat that sends report.five_numbers; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat's hand-over to itself; its own queue is the record |
| `handoff.report.five_numbers.waiting` | ceo | OWNER | none | the one seat that sends report.five_numbers; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat's hand-over to itself; its own queue is the record |
| `handoff.report.five_numbers.done` | ceo | OWNER | none | the one seat that sends report.five_numbers; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat's hand-over to itself; its own queue is the record |
| `handoff.report.five_numbers.failed` | ceo | OWNER | digest | the one seat that sends report.five_numbers; a failed hand-over is the sender's to re-send |
| `handoff.report.five_numbers.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.reveal.paid.sent` | accountant | OWNER | none | the one seat that sends reveal.paid; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.reveal.paid.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.reveal.paid.sent` | ceo |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.reveal.paid.sent` | customer_support |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.reveal.paid.waiting` | accountant | OWNER | none | the one seat that sends reveal.paid; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.reveal.paid.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.reveal.paid.done` | accountant | OWNER | none | the one seat that sends reveal.paid; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.reveal.paid.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.reveal.paid.failed` | accountant | OWNER | digest | the one seat that sends reveal.paid; a failed hand-over is the sender's to re-send |
| `handoff.reveal.paid.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.reveal.reconcile.sent` | sales_engineer | OWNER | none | the one seat that sends reveal.reconcile; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.reveal.reconcile.sent` | accountant |  | none | accountant holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.reveal.reconcile.sent` | ceo |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.reveal.reconcile.sent` | customer_support |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.reveal.reconcile.waiting` | sales_engineer | OWNER | none | the one seat that sends reveal.reconcile; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.reveal.reconcile.waiting` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.reveal.reconcile.done` | sales_engineer | OWNER | none | the one seat that sends reveal.reconcile; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.reveal.reconcile.done` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.reveal.reconcile.failed` | sales_engineer | OWNER | digest | the one seat that sends reveal.reconcile; a failed hand-over is the sender's to re-send |
| `handoff.reveal.reconcile.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.review.requested.sent` | customer_support | OWNER | none | the one seat that sends review.requested; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.review.requested.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.review.requested.sent` | ceo |  | none | ceo holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.review.requested.sent` | it_engineer |  | none | it_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.review.requested.sent` | accountant |  | none | accountant holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.review.requested.waiting` | customer_support | OWNER | none | the one seat that sends review.requested; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.review.requested.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.review.requested.waiting` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.review.requested.waiting` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.review.requested.waiting` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.review.requested.done` | customer_support | OWNER | none | the one seat that sends review.requested; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.review.requested.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.review.requested.done` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.review.requested.done` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.review.requested.done` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.review.requested.failed` | customer_support | OWNER | digest | the one seat that sends review.requested; a failed hand-over is the sender's to re-send |
| `handoff.review.requested.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.sale.made.sent` | accountant | OWNER | none | the one seat that sends sale.made; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.sale.made.sent` | ceo |  | none | ceo holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.sale.made.sent` | sales_engineer |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.sale.made.sent` | customer_support |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.sale.made.waiting` | accountant | OWNER | none | the one seat that sends sale.made; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.sale.made.waiting` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.sale.made.done` | accountant | OWNER | none | the one seat that sends sale.made; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.sale.made.done` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.sale.made.failed` | accountant | OWNER | digest | the one seat that sends sale.made; a failed hand-over is the sender's to re-send |
| `handoff.sale.made.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.sales.escalation.sent` | sales_engineer | OWNER | none | the one seat that sends sales.escalation; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.sales.escalation.sent` | ceo |  | none | ceo holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.sales.escalation.waiting` | sales_engineer | OWNER | none | the one seat that sends sales.escalation; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.sales.escalation.waiting` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.sales.escalation.done` | sales_engineer | OWNER | none | the one seat that sends sales.escalation; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.sales.escalation.done` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.sales.escalation.failed` | sales_engineer | OWNER | digest | the one seat that sends sales.escalation; a failed hand-over is the sender's to re-send |
| `handoff.sales.escalation.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.social.escalation.sent` | marketing | OWNER | none | the one seat that sends social.escalation; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.social.escalation.sent` | customer_support |  | none | customer_support holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.social.escalation.waiting` | marketing | OWNER | none | the one seat that sends social.escalation; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.social.escalation.waiting` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.social.escalation.done` | marketing | OWNER | none | the one seat that sends social.escalation; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.social.escalation.done` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.social.escalation.failed` | marketing | OWNER | digest | the one seat that sends social.escalation; a failed hand-over is the sender's to re-send |
| `handoff.social.escalation.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.social.lead.sent` | marketing | OWNER | none | the one seat that sends social.lead; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.social.lead.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.social.lead.waiting` | marketing | OWNER | none | the one seat that sends social.lead; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.social.lead.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.social.lead.done` | marketing | OWNER | none | the one seat that sends social.lead; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.social.lead.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.social.lead.failed` | marketing | OWNER | digest | the one seat that sends social.lead; a failed hand-over is the sender's to re-send |
| `handoff.social.lead.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.spec.not_sure.sent` | customer_support | OWNER | none | the one seat that sends spec.not_sure; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.spec.not_sure.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.spec.not_sure.waiting` | customer_support | OWNER | none | the one seat that sends spec.not_sure; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.spec.not_sure.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.spec.not_sure.done` | customer_support | OWNER | none | the one seat that sends spec.not_sure; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.spec.not_sure.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.spec.not_sure.failed` | customer_support | OWNER | digest | the one seat that sends spec.not_sure; a failed hand-over is the sender's to re-send |
| `handoff.spec.not_sure.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.subscription.due.sent` | accountant | OWNER | none | the one seat that sends subscription.due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.subscription.due.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.subscription.due.waiting` | accountant | OWNER | none | the one seat that sends subscription.due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.subscription.due.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.subscription.due.done` | accountant | OWNER | none | the one seat that sends subscription.due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.subscription.due.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.subscription.due.failed` | accountant | OWNER | digest | the one seat that sends subscription.due; a failed hand-over is the sender's to re-send |
| `handoff.subscription.due.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.subscription.dunning.sent` | accountant | OWNER | none | the one seat that sends subscription.dunning; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.subscription.dunning.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.subscription.dunning.waiting` | accountant | OWNER | none | the one seat that sends subscription.dunning; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.subscription.dunning.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.subscription.dunning.done` | accountant | OWNER | none | the one seat that sends subscription.dunning; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.subscription.dunning.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.subscription.dunning.failed` | accountant | OWNER | digest | the one seat that sends subscription.dunning; a failed hand-over is the sender's to re-send |
| `handoff.subscription.dunning.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.subscription.payment_failed.sent` | accountant | OWNER | none | the one seat that sends subscription.payment_failed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.subscription.payment_failed.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.subscription.payment_failed.sent` | ceo |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.subscription.payment_failed.sent` | customer_support |  | digest | money moved: founder 1685, every seat with a step knows a payment, a refund or a sale |
| `handoff.subscription.payment_failed.waiting` | accountant | OWNER | none | the one seat that sends subscription.payment_failed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.subscription.payment_failed.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.subscription.payment_failed.done` | accountant | OWNER | none | the one seat that sends subscription.payment_failed; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.subscription.payment_failed.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.subscription.payment_failed.failed` | accountant | OWNER | digest | the one seat that sends subscription.payment_failed; a failed hand-over is the sender's to re-send |
| `handoff.subscription.payment_failed.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.subscription.renewal_reminder.sent` | accountant | OWNER | none | the one seat that sends subscription.renewal_reminder; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.subscription.renewal_reminder.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.subscription.renewal_reminder.waiting` | accountant | OWNER | none | the one seat that sends subscription.renewal_reminder; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.subscription.renewal_reminder.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.subscription.renewal_reminder.done` | accountant | OWNER | none | the one seat that sends subscription.renewal_reminder; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.subscription.renewal_reminder.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.subscription.renewal_reminder.failed` | accountant | OWNER | digest | the one seat that sends subscription.renewal_reminder; a failed hand-over is the sender's to re-send |
| `handoff.subscription.renewal_reminder.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.supplier.portfolio_incomplete.sent` | sales_engineer | OWNER | none | the one seat that sends supplier.portfolio_incomplete; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.supplier.portfolio_incomplete.sent` | customer_support |  | none | customer_support holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.supplier.portfolio_incomplete.waiting` | sales_engineer | OWNER | none | the one seat that sends supplier.portfolio_incomplete; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.supplier.portfolio_incomplete.waiting` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.supplier.portfolio_incomplete.done` | sales_engineer | OWNER | none | the one seat that sends supplier.portfolio_incomplete; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.supplier.portfolio_incomplete.done` | customer_support |  | none | nobody else: customer_support wrote this answer itself |
| `handoff.supplier.portfolio_incomplete.failed` | sales_engineer | OWNER | digest | the one seat that sends supplier.portfolio_incomplete; a failed hand-over is the sender's to re-send |
| `handoff.supplier.portfolio_incomplete.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.support.case_open.sent` | customer_support | OWNER | none | the one seat that sends support.case_open; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.support.case_open.waiting` | customer_support | OWNER | none | the one seat that sends support.case_open; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat's hand-over to itself; its own queue is the record |
| `handoff.support.case_open.done` | customer_support | OWNER | none | the one seat that sends support.case_open; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat's hand-over to itself; its own queue is the record |
| `handoff.support.case_open.failed` | customer_support | OWNER | digest | the one seat that sends support.case_open; a failed hand-over is the sender's to re-send |
| `handoff.support.case_open.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.support.decision_objection.sent` | customer_support | OWNER | none | the one seat that sends support.decision_objection; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.support.decision_objection.sent` | ceo |  | none | ceo holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.support.decision_objection.waiting` | customer_support | OWNER | none | the one seat that sends support.decision_objection; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.support.decision_objection.waiting` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.support.decision_objection.done` | customer_support | OWNER | none | the one seat that sends support.decision_objection; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.support.decision_objection.done` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.support.decision_objection.failed` | customer_support | OWNER | digest | the one seat that sends support.decision_objection; a failed hand-over is the sender's to re-send |
| `handoff.support.decision_objection.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.support.human_requested.sent` | customer_support | OWNER | none | the one seat that sends support.human_requested; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.support.human_requested.waiting` | customer_support | OWNER | none | the one seat that sends support.human_requested; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat's hand-over to itself; its own queue is the record |
| `handoff.support.human_requested.done` | customer_support | OWNER | none | the one seat that sends support.human_requested; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo; nobody else: a seat's hand-over to itself; its own queue is the record |
| `handoff.support.human_requested.failed` | customer_support | OWNER | digest | the one seat that sends support.human_requested; a failed hand-over is the sender's to re-send |
| `handoff.support.human_requested.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.support.promise_due.sent` | customer_support | OWNER | none | the one seat that sends support.promise_due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.support.promise_due.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.support.promise_due.waiting` | customer_support | OWNER | none | the one seat that sends support.promise_due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.support.promise_due.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.support.promise_due.done` | customer_support | OWNER | none | the one seat that sends support.promise_due; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.support.promise_due.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.support.promise_due.failed` | customer_support | OWNER | digest | the one seat that sends support.promise_due; a failed hand-over is the sender's to re-send |
| `handoff.support.promise_due.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.support.root_cause.sent` | customer_support | OWNER | none | the one seat that sends support.root_cause; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.support.root_cause.sent` | sales_engineer |  | none | sales_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.support.root_cause.sent` | accountant |  | none | accountant holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.support.root_cause.sent` | it_engineer |  | none | it_engineer holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.support.root_cause.sent` | marketing |  | none | marketing holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.support.root_cause.sent` | ceo |  | none | ceo holds it as a hand-over in its own queue (the row itself, not this echo) |
| `handoff.support.root_cause.waiting` | customer_support | OWNER | none | the one seat that sends support.root_cause; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.support.root_cause.waiting` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.support.root_cause.waiting` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.support.root_cause.waiting` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.support.root_cause.waiting` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.support.root_cause.waiting` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.support.root_cause.done` | customer_support | OWNER | none | the one seat that sends support.root_cause; the sender reads the answer in its subject timeline and YOUR HAND-OVERS, not from this echo |
| `handoff.support.root_cause.done` | sales_engineer |  | none | nobody else: sales_engineer wrote this answer itself |
| `handoff.support.root_cause.done` | accountant |  | none | nobody else: accountant wrote this answer itself |
| `handoff.support.root_cause.done` | it_engineer |  | none | nobody else: it_engineer wrote this answer itself |
| `handoff.support.root_cause.done` | marketing |  | none | nobody else: marketing wrote this answer itself |
| `handoff.support.root_cause.done` | ceo |  | none | nobody else: ceo wrote this answer itself |
| `handoff.support.root_cause.failed` | customer_support | OWNER | digest | the one seat that sends support.root_cause; a failed hand-over is the sender's to re-send |
| `handoff.support.root_cause.failed` | it_engineer |  | digest | a failed hand-over is a fault IT watches |
| `handoff.complaint.due.sent` | sales_engineer |  | digest | a complaint is about a request the sales engineer owns; he must know before he next speaks to that customer |
| `handoff.complaint.due.sent` | ceo |  | digest | complaints are a CEO number and may need his decision |
| `handoff.support.human_requested.sent` | ceo |  | digest | a person asked for a person: the CEO sees how often the seats could not help |
| `handoff.support.case_open.sent` | sales_engineer |  | digest | an open support case on a customer or supplier he serves; the timeline shows it when he works that subject |

## 4. Authority: who may decide what, where it is written, where it is enforced

| layer | where written | where enforced | state on 13 Nov |
|---|---|---|---|
| a seat's standing authority | `public.ceo_standing_grant` (23 rows; `sales.invitation` and `it.job_rerun` inactive; `accountant.refund_decision` and `accountant.meta_ads_spend` capped at AED 0) | `fn_agent_may_act`: one SQL caller (`fn_support_may_act`), TS callers in it_engineer, accountant (refunds, grants listing) and sales_engineer (the operator's match) | almost no decision asks it |
| what a seat owns / must not do | `public.org_role.owned_decisions`, `forbidden_decisions` | nothing: prose the model reads | |
| the CEO's approvals | `public.ceo_approval` (append-only, 38 rows) | `fn_refund_execution_requires_ceo_approval`, `fn_refund_decide` | refund money only |
| the CEO's own authority | `the_ceo_is_the_final_internal_authority_and_nothing_waits_for_the_founder.sql` | by ruling | |
| the reporting line | `public.org_reporting_edge` (five seats -> ceo) | `fn_support_report_to_ceo`, `fn_handoff_overdue_escalate` | |
| department-era authority | `public.org_authority` (0 rows), `employee_authority` (320 rows) | `fn_org_authority_guard`, `fn_ops_authority_check` | dead |

The 121 decision points (`decision_point_grants.json`): **1 grant named AND checked in code** (documents.caption_class,
`fn_support_may_act('document')`), **99 grant named but NOT checked**, **21 no grant** (14 quote-reading or hold decisions, 3
knowledge upkeep, 2 unsubscribe, 1 outreach, 1 org_task).

**Dangerous, for the founder:**
- `resend_inbound.unsubscribe_request` and `email.unsubscribe_request`: customer_support records a person's unsubscribe (his
  consent) under no grant.
- `org_task.faq_answered`: decides on the department-era queue whose guard table `org_authority` is empty.
- `marketing.outreach_reply`: classifies replies to supplier outreach while `sales.invitation` is INACTIVE. Measured 13 Nov
  (SELECT, 7 days):
  - 52 `supplier_invite` sent by customer_support;
  - 20 `supplier_invite_nudge` by sales_engineer;
  - 258 `invite_m365_seed` by it_engineer.
  The switches read `invite_enabled = false` and `supplier_outreach_golive = true`. **The campaign runs under the founder's
  go-live switch and under no standing grant.**

## 5. Why 196 hand-overs were open past their window (13 Nov)

All 196 had been answered by their receiver. Six were not late at all (due later, `detail.due_at`).

| cluster | n | cause | what changed |
|---|---|---|---|
| it.finding, fault still open | 162 | escalated to the CEO (170 reports accepted = founder e-mailed); the CEO decided nothing (section 2) | the CEO now judges each one with the model; its decision and the it_engineer's next step are written |
| it.finding, fault cleared | 8 | the incident's cause/fix/regression check is blank; the IT loop waits for a person | not changed (the IT loop's file belongs to the money-side branch) |
| deliberation.review by a non-CEO author | 8 | no closer; and every reviewed verdict in 60 days was revise (30) or reject (1), none agree | an agreeing verdict closes; a revise or reject goes back to its author as work (deliberation.rework, 3 days) |
| support.case_open, lesson reapproval, ceo.root_cause, knowledge.request, ceo.revise | 12 | the seat or the CEO owes the next move | escalated once: to the CEO as a held question he decides, the CEO's own to the founder's daily note |
