// WHAT A SUPPLIER HELD ONLY FOR ITS UNCONFIRMED SERVICES IS TOLD (founder ledger 1469, 2 Nov 2026), and what the founder's mailbox is told.
// save_profile used to answer every 'pending' decision with "all six items are in, our sales engineer is reviewing it" and mail the
// founder "waiting for approval (auto-approve is off)". For a services hold both are false: nobody is reviewing, auto-approve may be on,
// and the one thing left is the supplier's own confirmation. English only (suppliers are always written to in English).
export const SERVICES_UNCONFIRMED = 'services_unconfirmed';

export function servicesHoldMail(name: string): { subject: string; body: string } {
  return {
    subject: 'Thanks for registering with QuotesDone: one step left',
    body: `Thank you for registering ${name}. Your six required items are in. One step is left: sign in to your supplier portal, open the Services tab, check the summary and keywords we prepared from your company profile, and press Confirm my services. You are verified as soon as you confirm.`,
  };
}

/** The founder-mailbox subject for a supplier whose decision is 'pending'. */
export function pendingFounderSubject(reason: string | null | undefined): string {
  return reason === SERVICES_UNCONFIRMED
    ? 'New supplier registered: waiting for its own services confirmation'
    : 'New supplier waiting for approval (auto-approve is off)';
}
