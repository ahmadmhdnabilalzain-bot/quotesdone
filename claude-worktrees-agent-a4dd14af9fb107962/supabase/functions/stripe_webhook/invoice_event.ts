// invoice.finalized / invoice.paid for a REVEAL FEE (14 Sep 2026, agent: accountant).
//
// The invoice names its sale through invoice_data.metadata.quote_id, set by stripe_checkout. The
// sale must already be recorded (checkout.session.completed or stripe_confirm wrote it); an invoice
// event never creates a sale. Idempotent by construction: a sale that already holds its stored PDF
// is left alone, and fn_transaction_attach_invoice is write-once on the invoice identity, so a
// replayed or out-of-order delivery can at most fill in what is still missing.
export type InvoiceEventDeps = {
  findSale: (quoteId: string) => Promise<{ id: string; doc_path: string | null; stripe_invoice_id: string | null } | null>;
  capture: (saleId: string, invoiceId: string) => Promise<void>;
};

export type InvoiceEventResult =
  | { action: 'captured'; sale: string }
  | { action: 'already_filed'; sale: string }
  | { action: 'not_a_reveal' }
  | { action: 'no_sale_yet'; quote_id: string }
  | { action: 'other_invoice'; sale: string };

export async function handleRevealInvoiceEvent(deps: InvoiceEventDeps, inv: Record<string, any>): Promise<InvoiceEventResult> {
  const quoteId = String(inv?.metadata?.quote_id || '');
  const invoiceId = String(inv?.id || '');
  if (!quoteId || !/^in_/.test(invoiceId)) return { action: 'not_a_reveal' };
  const sale = await deps.findSale(quoteId);
  if (!sale) return { action: 'no_sale_yet', quote_id: quoteId };
  if (sale.stripe_invoice_id && sale.stripe_invoice_id !== invoiceId) return { action: 'other_invoice', sale: sale.id };
  if (sale.doc_path && sale.stripe_invoice_id === invoiceId) return { action: 'already_filed', sale: sale.id };
  await deps.capture(sale.id, invoiceId);
  return { action: 'captured', sale: sale.id };
}
