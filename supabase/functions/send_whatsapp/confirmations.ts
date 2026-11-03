// THE CONFIRMATIONS (customer_support, 3 Nov 2026). The founder, 3 Nov 2026: after a customer registers "he gets a
// confirmation on email and whatsapp that his account is active"; a supplier who "finish the registration process fully"
// gets "a confirmation email and whatsapp message for that"; after a customer pays the reveal fee "an invoice from our app is
// shared on email and whatsapp with the customer" (the reveal receipt, then "Your invoice is ready" carrying the invoice).
//
// Each confirmation is a notice about the person's own account or payment, sent once, to the number they confirmed with a
// code. The per-recipient cap (one WhatsApp per number per 24 h) exists so a stranger who never opted in is not messaged
// three times in a day; applied here it held the second confirmation of a customer who registered and paid on the same day
// until the next morning, and the 24 h staleness bar then shelved it unsent. So these types are exempt from the
// per-recipient cap only. The daily cap, the template ledger, the demo capture and the failover still apply to them.
// prevented by: send_whatsapp/confirmations.test.ts
export const CONFIRMATION_TYPES: readonly string[] = ['customer_account_active', 'supplier_approved', 'reveal_receipt', 'invoice_ready'];
export const isConfirmation = (type: string | null | undefined) => CONFIRMATION_TYPES.includes(String(type || ''));

// The invoice on an invoice_ready WhatsApp twin is the PDF REFERENCE reveal_invoice (action 'attach') put on the row's
// attachments, never a link read out of its body: the body is text a writer composed, and a link in it could be anything
// (review of this PR: a supplier named like a URL). Only a QuotesDone invoice in agent-docs under reveal_invoice/ is
// accepted; send_whatsapp signs it for INVOICE_LINK_TTL seconds at the moment it sends, so no link is ever stored.
export const INVOICE_LINK_TTL = 7 * 24 * 3600;
export function invoiceAttachment(attachments: unknown): { bucket: string; path: string } | null {
  if (!Array.isArray(attachments)) return null;
  for (const a of attachments) {
    const bucket = String((a as { bucket?: unknown })?.bucket || ''), path = String((a as { path?: unknown })?.path || '');
    if (bucket === 'agent-docs' && /^reveal_invoice\/[A-Za-z0-9_-]+\/[A-Za-z0-9._-]+\.pdf$/.test(path) && !path.includes('..')) return { bucket, path };
  }
  return null;
}
