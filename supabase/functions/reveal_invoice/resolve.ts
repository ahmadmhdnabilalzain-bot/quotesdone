// WHICH INVOICE A SIGNED-IN CUSTOMER GETS (14 Sep 2026, agent: accountant).
//
// Founder, 14 Sep 2026: "when a customer pays the reveal fee, a copy of stripe invoice should be
// already showing in the portal in the right tab. so he can click it anytime and it would open the
// pdf from stripe". Stripe's invoice_pdf link is not permanent, so the link is fetched fresh from
// Stripe at the moment of the click rather than served from what the webhook stored.
//
// OWNERSHIP IS DECIDED BEFORE STRIPE IS ASKED ANYTHING. The sale must name the caller's own
// customer row; another customer's quote id gets a 403 and no Stripe call is made for it.
export type Sale = {
  id: string; customer_id: string | null;
  stripe_invoice_id: string | null; stripe_invoice_number: string | null; doc_path: string | null;
};
export type ResolveDeps = {
  customerIdByEmail: (email: string) => Promise<string | null>;
  saleByQuote: (quoteId: string) => Promise<Sale | null>;
  /** Fresh invoice_pdf from Stripe for this invoice id, or null if Stripe would not give one. */
  stripeInvoicePdf: (invoiceId: string) => Promise<string | null>;
  /** Signed link to the copy of the same PDF held in finance-docs. */
  signedStoredCopy: (path: string) => Promise<string | null>;
  /** The customer registered in Arabic. Stripe Invoicing has no Arabic (docs.stripe.com/invoicing/
   *  customize, "Customer preferred languages"), so their document is the QuotesDone receipt in Arabic. */
  preferReceipt?: boolean;
};
export type Resolved =
  | { status: 403 | 404; body: { error: string } }
  | { status: 200; body: { ok: true; url: string; source: 'stripe' | 'stored_copy'; invoice_no: string | null } }
  | { status: 200; fallback: true; sale: Sale };

export async function resolveInvoice(deps: ResolveDeps, email: string, quoteId: string): Promise<Resolved> {
  const custId = await deps.customerIdByEmail(String(email || '').toLowerCase());
  if (!custId) return { status: 403, body: { error: 'No customer profile' } };
  const sale = quoteId ? await deps.saleByQuote(quoteId) : null;
  if (!sale) return { status: 404, body: { error: 'No paid reveal found for this quote' } };
  if (String(sale.customer_id || '') !== String(custId)) return { status: 403, body: { error: 'Not your transaction' } };
  if (deps.preferReceipt) return { status: 200, fallback: true, sale };
  if (sale.stripe_invoice_id) {
    const fresh = await deps.stripeInvoicePdf(sale.stripe_invoice_id);
    if (fresh) return { status: 200, body: { ok: true, url: fresh, source: 'stripe', invoice_no: sale.stripe_invoice_number } };
  }
  if (sale.doc_path) {
    const copy = await deps.signedStoredCopy(sale.doc_path);
    if (copy) return { status: 200, body: { ok: true, url: copy, source: 'stored_copy', invoice_no: sale.stripe_invoice_number } };
  }
  // No Stripe invoice for this sale (paid before invoice_creation was on): the QuotesDone receipt.
  return { status: 200, fallback: true, sale };
}

// ONE INVOICE PER SALE (15 Sep 2026, agent: accountant). Stripe's invoice is the only invoice; the
// QuotesDone document is a RECEIPT with no number series of its own. It cites the Stripe invoice
// number when the sale has one, and otherwise (a sale paid before invoicing was on) only the payment
// reference printed on it. Until this date the receipt carried a second, QuotesDone-made invoice
// number derived from the transaction id, so one payment could hold two invoice numbers.
export function receiptCitation(sale: Pick<Sale, 'id' | 'stripe_invoice_number'>): { invoiceNo: string | null; fileName: string } {
  const n = String(sale.stripe_invoice_number || '').trim();
  return { invoiceNo: n || null, fileName: 'receipt-' + String(sale.id).replace(/-/g, '').slice(0, 8).toUpperCase() };
}
