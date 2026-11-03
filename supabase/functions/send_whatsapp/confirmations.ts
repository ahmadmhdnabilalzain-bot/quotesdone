// THE THREE CONFIRMATIONS (customer_support, 3 Nov 2026). The founder, 3 Nov 2026: after a customer registers "he gets a
// confirmation on email and whatsapp that his account is active"; a supplier who "finish the registration process fully"
// gets "a confirmation email and whatsapp message for that"; after a customer pays the reveal fee "an invoice from our app is
// shared on email and whatsapp with the customer".
//
// Each confirmation is a notice about the person's own account or payment, sent once, to the number they confirmed with a
// code minutes earlier. The per-recipient cap (one WhatsApp per number per 24 h) exists so a stranger who never opted in is
// not messaged three times in a day; applied here it held the second confirmation of a customer who registered and paid on
// the same day until the next morning, and the 24 h staleness bar then shelved it unsent. So these types are exempt from the
// per-recipient cap only. The daily cap, the template ledger, the demo capture and the failover still apply to them.
// prevented by: send_whatsapp/confirmations.test.ts
export const CONFIRMATION_TYPES: readonly string[] = ['customer_account_active', 'supplier_approved', 'reveal_receipt'];
export const isConfirmation = (type: string | null | undefined) => CONFIRMATION_TYPES.includes(String(type || ''));

// The reveal receipt's WhatsApp twin carries its invoice as a signed storage link that reveal_invoice (action 'attach')
// appended to the row's body when it attached the PDF to the email twin. Only that shape is read: a Supabase signed
// object URL. Anything else in the body (a portal link, a supplier's site) is never sent as "your invoice".
const SIGNED = /https:\/\/[A-Za-z0-9.-]+\/storage\/v1\/object\/sign\/[^\s"'<>]+/;
export function invoiceLink(body: string | null | undefined): string | null {
  const m = String(body || '').match(SIGNED);
  // A WhatsApp template variable is capped at 1,024 characters; a link that would be cut is not a link.
  return m && m[0].length <= 1000 ? m[0] : null;
}
