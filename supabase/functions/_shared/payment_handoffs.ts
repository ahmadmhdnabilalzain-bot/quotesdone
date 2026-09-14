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

export type Seat = 'accountant' | 'sales_engineer' | 'customer_support' | 'ceo' | 'it_engineer';
export interface HandoffType { type: string; from: Seat; to: Seat; }

export const HANDOFF_TYPES: readonly HandoffType[] = [
  // accountant -> sales engineer: money happened, somebody must be told
  { type: 'reveal.paid', from: 'accountant', to: 'sales_engineer' },
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
  // sales engineer -> accountant: somebody asked about money, the books must answer
  { type: 'refund.requested', from: 'sales_engineer', to: 'accountant' },
  { type: 'billing.question', from: 'sales_engineer', to: 'accountant' },
  { type: 'charge.disputed', from: 'sales_engineer', to: 'accountant' },
  // the CEO sends back what failed his checks, and the fix a post-payment mismatch needs
  { type: 'refund.remediate', from: 'ceo', to: 'accountant' },
  { type: 'refund.remediate', from: 'ceo', to: 'sales_engineer' },
  { type: 'incident.fix', from: 'ceo', to: 'accountant' },
  // customer_support is the only seat that sends email or WhatsApp (founder, 14 Sep 2026)
  { type: 'delivery.request', from: 'sales_engineer', to: 'customer_support' },
  { type: 'delivery.request', from: 'ceo', to: 'customer_support' },
  { type: 'delivery.request', from: 'accountant', to: 'customer_support' },
  { type: 'delivery.result', from: 'customer_support', to: 'sales_engineer' },
  // the IT engineer verifies the Dropbox backup; the sales engineer refiles what it finds missing
  // (founder, 14 Sep 2026: scripts/sql/the_dropbox_backup_is_confirmed_not_assumed.sql)
  { type: 'backup.refile', from: 'it_engineer', to: 'sales_engineer' },
  // the CEO sends instructions back on an escalated backup case (the refund rejection-loop pattern)
  { type: 'backup.remediate', from: 'ceo', to: 'sales_engineer' },
] as const;
