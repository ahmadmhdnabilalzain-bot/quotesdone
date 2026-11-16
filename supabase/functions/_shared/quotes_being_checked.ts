// A CUSTOMER WHO MAY BE A SUPPLIER IN DISGUISE DOES NOT READ RIVALS' PRICES WHILE IT IS CHECKED (16 Nov 2026, FAILURES item 5).
//
// The accountant raises customer_matches_supplier when a customer account shares an identifier with a registered supplier
// (phone, e-mail, terms IP, company domain: equality only). The flag goes to the accountant's reasoning with the facts
// (scripts/sql/every_flag_and_sanctions_hit_is_reasoned_by_its_seat_and_frozen_until_decided.sql). While it is open or
// escalated, public.fn_customer_quotes_being_checked names that customer's requests in the matched supplier's trades
// (every request when the supplier's trades are unknown), and their quotes are held from the list and counted as
// "being checked". A benign verdict dismisses the flag and they appear again; the reveal is held separately by the money
// screen. FAILS CLOSED like the sanctions reads: an unreadable answer throws, and the caller answers 500 rather than
// listing what may be a rival's price to the rival.
type Admin = { rpc: (fn: string, args: Record<string, unknown>) => any };

/** The ids of this customer's requests whose quotes are held while a customer_matches_supplier flag is open. */
export async function quotesBeingChecked(admin: Admin, customerId: string | null | undefined): Promise<Set<string>> {
  if (!customerId) return new Set();
  const r = await admin.rpc('fn_customer_quotes_being_checked', { p_customer: customerId });
  if (r?.error) throw new Error('fn_customer_quotes_being_checked failed: ' + JSON.stringify(r.error));
  const ids = (r?.data && Array.isArray((r.data as { inquiry_ids?: unknown[] }).inquiry_ids)) ? (r.data as { inquiry_ids: unknown[] }).inquiry_ids : [];
  return new Set(ids.map((x) => String(x)));
}
