// WHOSE SALE IS THIS (14 Sep 2026, agent: accountant; reshaped 21 Sep 2026).
//
// OWNERSHIP IS DECIDED BEFORE ANYTHING ELSE. The sale must name the caller's own customer row;
// another customer's quote id gets a 403 and nothing is fetched, rendered or signed for it.
//
// Until 21 Sep 2026 this file also chose WHICH document the customer got: Stripe's invoice_pdf,
// fetched fresh at click time, then the stored copy of that same Stripe file, and our receipt only
// when neither existed. The founder ruled on 21 Sep (instructions 568, 569) that no PDF reaches a
// person unless it is on the QuotesDone template, so there is no longer a choice to make: every
// customer gets the invoice and the receipt built by _shared/reveal_fee_documents.ts. The Stripe file
// stays in finance-docs as the accountant's source record and is never handed out.
export type Sale = {
  id: string; customer_id: string | null;
  stripe_invoice_id: string | null; stripe_invoice_number: string | null;
};
export type ResolveDeps = {
  customerIdByEmail: (email: string) => Promise<string | null>;
  saleByQuote: (quoteId: string) => Promise<Sale | null>;
};
export type Resolved =
  | { status: 403 | 404; body: { error: string } }
  | { status: 200; sale: Sale };

export async function resolveSale(deps: ResolveDeps, email: string, quoteId: string): Promise<Resolved> {
  const custId = await deps.customerIdByEmail(String(email || '').toLowerCase());
  if (!custId) return { status: 403, body: { error: 'No customer profile' } };
  const sale = quoteId ? await deps.saleByQuote(quoteId) : null;
  if (!sale) return { status: 404, body: { error: 'No paid reveal found for this quote' } };
  if (String(sale.customer_id || '') !== String(custId)) return { status: 403, body: { error: 'Not your transaction' } };
  return { status: 200, sale };
}
