// PAYMENTS ARE THE ACCOUNTANT'S, AND THE ACCOUNTANT TALKS TO THE SALES ENGINEER.
//
// Founder, 14 Sep 2026, verbatim: "anything related to payment is under the accountant agent. and
// the accountant need to be in communication back and forth with the sales agent. its one company
// eventually."
//
// This file is the ONE list of the conversations the two seats have about money. The database holds
// the same list in public.fn_seat_handoff_types() (scripts/sql/payments_are_the_accountant_and_the_seats_close_every_refund_together.sql),
// and scripts/checks/payments_are_the_accountant.test.mjs fails if the two ever differ, so a new
// handoff cannot exist on one side and not the other.
//
// A handoff is a row in public.agent_actions (kind 'handoff'), addressed to the receiving seat, carrying
// its type, the ids it is about, who sent it and its status. The receiving seat acts on it inside
// public.fn_seat_handoff_act: the sales engineer writes the customer- or supplier-facing message in its
// own voice; the accountant reads and checks the money. The accountant is never named to a customer
// or a supplier.

export type Seat = 'accountant' | 'sales_engineer' | 'customer_support' | 'ceo' | 'it_engineer' | 'marketing';
export interface HandoffType { type: string; from: Seat; to: Seat; }

export const HANDOFF_TYPES: readonly HandoffType[] = [
  // accountant -> sales engineer: money happened, somebody must be told
  { type: 'reveal.paid', from: 'accountant', to: 'sales_engineer' },
  // the stored Stripe reveal invoice was filed into the customer's Documents (fn_accountant_files_reveal_invoice)
  { type: 'invoice.issued', from: 'accountant', to: 'sales_engineer' },
  { type: 'payment.failed', from: 'accountant', to: 'sales_engineer' },
  { type: 'payment.received', from: 'accountant', to: 'sales_engineer' },
  { type: 'refund.request_checked', from: 'accountant', to: 'sales_engineer' },
  { type: 'refund.paid', from: 'accountant', to: 'sales_engineer' },
  { type: 'refund.declined', from: 'accountant', to: 'sales_engineer' },
  { type: 'refund.in_progress', from: 'accountant', to: 'sales_engineer' },
  { type: 'nonresponse.charge_raised', from: 'accountant', to: 'sales_engineer' },
  { type: 'charge.corrected', from: 'accountant', to: 'sales_engineer' },
  { type: 'subscription.due', from: 'accountant', to: 'sales_engineer' },
  { type: 'billing.answer', from: 'accountant', to: 'sales_engineer' },
  { type: 'charge.dispute_answer', from: 'accountant', to: 'sales_engineer' },
  // the accountant's notices (14 Sep 2026), each answered by fn_sales_engineer_writes_money_notice
  // (scripts/sql/the_accountant_raises_its_findings_into_the_loop_the_it_engineer_runs.sql)
  { type: 'nonresponse.charge_reminder', from: 'accountant', to: 'sales_engineer' },
  { type: 'nonresponse.final_demand', from: 'accountant', to: 'sales_engineer' },
  { type: 'subscription.renewal_reminder', from: 'accountant', to: 'sales_engineer' },
  { type: 'subscription.dunning', from: 'accountant', to: 'sales_engineer' },
  { type: 'subscription.payment_failed', from: 'accountant', to: 'sales_engineer' },
  // sales engineer -> accountant: somebody asked about money, the books must answer
  { type: 'refund.requested', from: 'sales_engineer', to: 'accountant' },
  { type: 'billing.question', from: 'sales_engineer', to: 'accountant' },
  { type: 'charge.disputed', from: 'sales_engineer', to: 'accountant' },
  // it_engineer -> accountant: a licence, NOL or domain is inside its renewal window; the accountant budgets
  // the fee and the it_engineer closes it once it reads the new expiry
  // (scripts/sql/the_accountant_budgets_every_renewal_the_it_engineer_sees_coming.sql)
  { type: 'renewal.due', from: 'it_engineer', to: 'accountant' },
  // the CEO sends back what failed his checks, and the fix a post-payment mismatch needs
  { type: 'refund.remediate', from: 'ceo', to: 'accountant' },
  { type: 'refund.remediate', from: 'ceo', to: 'sales_engineer' },
  { type: 'incident.fix', from: 'ceo', to: 'accountant' },
  // the CEO hands himself yesterday's five numbers every morning (ruling 1209; the_ceo_reads_five_numbers_every_morning.sql)
  { type: 'report.five_numbers', from: 'ceo', to: 'ceo' },
  // marketing puts its monthly plan before the CEO on the review machine: another model family, blind first
  // (founder_instructions 866 and 873; the_marketing_seat_watches_its_videos_studies_the_market_and_argues_its_month_with_the_ceo.sql)
  { type: 'deliberation.review', from: 'marketing', to: 'ceo' },
  { type: 'deliberation.review', from: 'customer_support', to: 'ceo' },   // a dispute's fault finding (#904)
  { type: 'deliberation.review', from: 'accountant', to: 'ceo' },         // a fee-circumvention finding (#904)
  { type: 'deliberation.review', from: 'sales_engineer', to: 'marketing' }, // a supply gap marketing should recruit for (#905)
  { type: 'deliberation.review', from: 'ceo', to: 'accountant' },         // the CEO's pricing or forecast call, reviewed (#906)
  { type: 'deliberation.review', from: 'it_engineer', to: 'ceo' },        // the CEO judges a seat's case (#913)
  { type: 'deliberation.review', from: 'sales_engineer', to: 'ceo' },     // the CEO judges a seat's case (#913)
  { type: 'sales.escalation', from: 'sales_engineer', to: 'ceo' },        // thin supply or a disputed reveal, decided by the CEO (ledger 983)
  // customer_support is the only seat that sends email or WhatsApp (founder, 14 Sep 2026)
  { type: 'delivery.request', from: 'sales_engineer', to: 'customer_support' },
  { type: 'delivery.request', from: 'ceo', to: 'customer_support' },
  { type: 'delivery.request', from: 'accountant', to: 'customer_support' },
  { type: 'delivery.request', from: 'it_engineer', to: 'customer_support' },
  { type: 'delivery.request', from: 'customer_support', to: 'customer_support' },
  // every send comes back to whoever asked (founder, 14 Sep 2026: "nothing literally should ever be a
  // one way communication"; scripts/sql/every_send_comes_back_to_whoever_asked.sql)
  { type: 'delivery.result', from: 'customer_support', to: 'sales_engineer' },
  { type: 'delivery.result', from: 'customer_support', to: 'accountant' },
  { type: 'delivery.result', from: 'customer_support', to: 'ceo' },
  { type: 'delivery.result', from: 'customer_support', to: 'it_engineer' },
  { type: 'delivery.result', from: 'customer_support', to: 'customer_support' },
  // the IT engineer hands a fault to the seat that owns it, re-verifies and closes
  // (scripts/sql/the_it_engineer_closes_every_loop_it_opens.sql)
  { type: 'it.finding', from: 'it_engineer', to: 'sales_engineer' },
  { type: 'it.finding', from: 'it_engineer', to: 'accountant' },
  { type: 'it.finding', from: 'it_engineer', to: 'customer_support' },
  { type: 'it.finding', from: 'it_engineer', to: 'ceo' },
  // the IT engineer verifies the Dropbox backup; the sales engineer refiles what it finds missing
  // (founder, 14 Sep 2026: scripts/sql/the_dropbox_backup_is_confirmed_not_assumed.sql)
  { type: 'backup.refile', from: 'it_engineer', to: 'sales_engineer' },
  // the CEO sends instructions back on an escalated backup case (the refund rejection-loop pattern)
  { type: 'backup.remediate', from: 'ceo', to: 'sales_engineer' },
  // the CEO decided a notice that missed a real customer or supplier: the sales engineer tries another
  // channel on file and the CEO closes it once the resend is confirmed or none exists
  // (scripts/sql/the_ceo_decides_every_sales_engineer_report_and_every_sender_closes_its_handoff.sql)
  { type: 'delivery.remediate', from: 'ceo', to: 'sales_engineer' },
  // the complaint clock hands customer_support its own complaint before the Complaints Policy due date and
  // closes it on the final response (scripts/sql/complaints_quotes_reveals_and_support_replies_each_run_on_a_clock.sql)
  { type: 'complaint.due', from: 'customer_support', to: 'customer_support' },
  // a WhatsApp problem report waits for its first reply and closes with the case; a "Talk to a person"
  // request waits for the founder's DONE or the 23-hour follow-up
  // (scripts/sql/the_whatsapp_menu_answers_like_a_senior_member_of_staff.sql, instruction 763)
  { type: 'support.case_open', from: 'customer_support', to: 'customer_support' },
  { type: 'support.human_requested', from: 'customer_support', to: 'customer_support' },
  // a support cause recurring past the weekly threshold goes to the seat that owns it; customer_support measures
  // the weekly volume afterwards and closes it when it falls
  // (scripts/sql/customer_support_finds_the_root_cause_each_week_and_measures_the_fix.sql, instruction 1009)
  { type: 'support.root_cause', from: 'customer_support', to: 'sales_engineer' },
  { type: 'support.root_cause', from: 'customer_support', to: 'accountant' },
  { type: 'support.root_cause', from: 'customer_support', to: 'it_engineer' },
  { type: 'support.root_cause', from: 'customer_support', to: 'marketing' },
  { type: 'support.root_cause', from: 'customer_support', to: 'ceo' },
  // three working days after verification the sales engineer hands support one reminder of what a supplier's
  // portfolio is missing; support re-checks and sends it, the sales engineer re-verifies delivery and closes
  // (scripts/sql/a_verified_supplier_is_told_what_his_portfolio_is_missing.sql, instruction 858)
  { type: 'supplier.portfolio_incomplete', from: 'sales_engineer', to: 'customer_support' },
  // the CEO's daily plan names the binding constraint each seat can move; the CEO re-measures and closes it
  // (scripts/sql/the_ceo_plans_every_day_and_directs_the_seats.sql, applied 22 Sep 2026). Missing here until
  // 22 Sep: that file inserts its four rows with INSERT ... SELECT FROM unnest(...), a shape the static
  // parser in payments_are_the_accountant.test.mjs did not read, so only the production half saw them.
  { type: 'ceo.directive', from: 'ceo', to: 'sales_engineer' },
  { type: 'ceo.directive', from: 'ceo', to: 'customer_support' },
  { type: 'ceo.directive', from: 'ceo', to: 'accountant' },
  { type: 'ceo.directive', from: 'ceo', to: 'it_engineer' },
  // the accountant's screen before money moves held, or released, a customer's reveal or refund; customer_support
  // tells that customer (ledger 1018; scripts/sql/the_accountant_screens_every_party_and_holds_money_for_review_before_it_moves.sql)
  { type: 'fraud.money_held', from: 'accountant', to: 'customer_support' },
  { type: 'fraud.money_released', from: 'accountant', to: 'customer_support' },
  // the demand stage is the marketing seat's (instruction 721): the CEO steers it like every other seat, never approves
  { type: 'ceo.directive', from: 'ceo', to: 'marketing' },
  // a rejection never ends the cycle (founder_instruction 1059; MANIFEST 1894,
  // scripts/sql/a_rejection_never_ends_the_cycle_the_ceo_gives_reasons_and_the_seat_revises.sql): the CEO sends a
  // submission back with reasons, returns its final decision, and is owed one when a revision stalls
  { type: 'ceo.revise', from: 'ceo', to: 'customer_support' },
  { type: 'ceo.revise', from: 'ceo', to: 'sales_engineer' },
  { type: 'ceo.revise', from: 'ceo', to: 'accountant' },
  { type: 'ceo.revise', from: 'ceo', to: 'it_engineer' },
  { type: 'ceo.revise', from: 'ceo', to: 'marketing' },
  { type: 'ceo.decision_closed', from: 'ceo', to: 'customer_support' },
  { type: 'ceo.decision_closed', from: 'ceo', to: 'sales_engineer' },
  { type: 'ceo.decision_closed', from: 'ceo', to: 'accountant' },
  { type: 'ceo.decision_closed', from: 'ceo', to: 'it_engineer' },
  { type: 'ceo.decision_closed', from: 'ceo', to: 'marketing' },
  { type: 'ceo.decision_owed', from: 'customer_support', to: 'ceo' },
  { type: 'ceo.decision_owed', from: 'sales_engineer', to: 'ceo' },
  { type: 'ceo.decision_owed', from: 'accountant', to: 'ceo' },
  { type: 'ceo.decision_owed', from: 'it_engineer', to: 'ceo' },
  { type: 'ceo.decision_owed', from: 'marketing', to: 'ceo' },
  // the root cause of a target miss (the ambition build, #913) and the year-one plan's month directive and improvement (#923)
  { type: 'ceo.root_cause', from: 'ceo', to: 'sales_engineer' },
  { type: 'ceo.root_cause', from: 'ceo', to: 'customer_support' },
  { type: 'ceo.root_cause', from: 'ceo', to: 'marketing' },
  { type: 'ceo.root_cause', from: 'ceo', to: 'accountant' },
  { type: 'ceo.root_cause', from: 'ceo', to: 'it_engineer' },
  { type: 'ceo.month_directive', from: 'ceo', to: 'sales_engineer' },
  { type: 'ceo.month_directive', from: 'ceo', to: 'customer_support' },
  { type: 'ceo.month_directive', from: 'ceo', to: 'marketing' },
  { type: 'ceo.month_directive', from: 'ceo', to: 'accountant' },
  { type: 'ceo.month_directive', from: 'ceo', to: 'it_engineer' },
  { type: 'ceo.improvement', from: 'ceo', to: 'sales_engineer' },
  { type: 'ceo.improvement', from: 'ceo', to: 'customer_support' },
  { type: 'ceo.improvement', from: 'ceo', to: 'marketing' },
  { type: 'ceo.improvement', from: 'ceo', to: 'accountant' },
  { type: 'ceo.improvement', from: 'ceo', to: 'it_engineer' },
  // THE MARKETING SEAT (founder instruction 721, 22 Sep 2026; scripts/sql/the_company_gets_a_marketing_seat_that_reports_the_picture_to_the_ceo.sql).
  // It reports the overall picture to the CEO, who READS it and closes it (never approves); it reports ad spend to
  // the accountant, who records it and answers; email and WhatsApp still go through customer_support.
  { type: 'marketing.report', from: 'marketing', to: 'ceo' },
  // The quarterly brand review and the monthly GEO report (ledger 983, marketing gap 8).
  { type: 'marketing.review', from: 'marketing', to: 'ceo' },
  { type: 'marketing.lead_sourcing', from: 'marketing', to: 'ceo' },
  { type: 'adspend.recorded', from: 'marketing', to: 'accountant' },
  { type: 'adspend.booked', from: 'accountant', to: 'marketing' },
  // legal finding 1: an unresolved objection to an automated decision
  // (scripts/sql/the_support_desk_takes_an_objection_to_an_automated_decision.sql)
  { type: 'support.decision_objection', from: 'customer_support', to: 'ceo' },
  { type: 'delivery.request', from: 'marketing', to: 'customer_support' },
  { type: 'delivery.result', from: 'customer_support', to: 'marketing' },
  { type: 'it.finding', from: 'it_engineer', to: 'marketing' },
  // a seed invitation landed in junk or elsewhere: the batch still sends, marketing fixes the cause (ledger 1001;
  // scripts/sql/the_invitation_batch_waits_for_the_mornings_seed_to_land_in_both_inboxes.sql)
  { type: 'deliverability.inbox_placement', from: 'it_engineer', to: 'marketing' },
  // a public comment the seat must not answer in public, and a lead from a comment; marketing re-checks and
  // closes each once the receiving seat has answered (scripts/sql/the_marketing_seat_answers_comments_on_every_channel.sql)
  { type: 'social.escalation', from: 'marketing', to: 'customer_support' },
  { type: 'social.lead', from: 'marketing', to: 'sales_engineer' },
  // an invited supplier replied to the invitation (usually with its trades): the sales engineer sets up its company page
  // (scripts/sql/the_supplier_invitation_carries_no_link_and_a_reply_with_trades_reaches_the_sales_engineer.sql)
  { type: 'invite.reply', from: 'marketing', to: 'sales_engineer' },
  // a customer answered "not sure" to a spec on a held request: the sales engineer takes that spec up
  // (scripts/sql/a_not_sure_spec_opens_a_handoff_to_the_sales_engineer.sql, handler fn_sales_engineer_spec_handoff_waits)
  { type: 'spec.not_sure', from: 'customer_support', to: 'sales_engineer' },
] as const;
