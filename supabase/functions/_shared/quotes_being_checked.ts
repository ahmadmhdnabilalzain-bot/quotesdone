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

type AdminWithFrom = Admin & { from: (t: string) => any };

/** THE COMPARISON AND THE QUOTE DOCUMENTS TOO (review of 16 Nov 2026, hole 5 through compare). my_inquiries held these
 *  quotes, but quote_compare (and so compare_pdf, compare_csv and the Arabic report's finisher, which read its analysis)
 *  and quote_pdf still showed their prices. Of these quotes on ONE request, the ones withheld while its customer is being
 *  checked: every quote on a request fn_customer_quotes_being_checked names, except a quote he already paid to reveal (a
 *  transaction on it: that disclosure is his, as on the cards). Empty when the request is not named. Fails closed: an
 *  unreadable flag answer or transaction read throws, and the caller refuses rather than show a rival's price. */
export async function withheldWhileChecked(admin: AdminWithFrom, customerId: string | null | undefined, inquiryId: string, quoteIds: string[]): Promise<Set<string>> {
  if (!customerId || !quoteIds.length) return new Set();
  const checking = await quotesBeingChecked(admin, customerId);
  if (!checking.has(String(inquiryId))) return new Set();
  const { data, error } = await admin.from('transactions').select('quote_id').eq('customer_id', customerId).in('quote_id', quoteIds);
  if (error) throw new Error('transactions read failed while withholding quotes being checked: ' + JSON.stringify(error));
  const paid = new Set(((data || []) as Array<{ quote_id: unknown }>).map((t) => String(t.quote_id)));
  return new Set(quoteIds.map(String).filter((id) => !paid.has(id)));
}

/** What a customer reads when the one quote he asked for is withheld while it is checked (the portal's own sentence). */
export const BEING_CHECKED_REFUSAL = {
  error: 'being_checked', code: 'being_checked',
  message: 'This quote is being checked by our team. It appears here once the check is done.',
  message_ar: 'يتحقق فريقنا من هذا العرض، وسيظهر هنا فور انتهاء التحقق.',
} as const;
