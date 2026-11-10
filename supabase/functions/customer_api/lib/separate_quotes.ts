// THE SEPARATE-QUOTES QUESTION IS ASKED ONCE (sales_engineer, customer-journey audit 10 Nov 2026).
//
// A turnkey request no single contractor matched carries routing.separate_offer, and the request card asks the customer
// "would you like separate quotes per trade?" (requests/SeparateQuotesAsk.tsx; finding c of 10 Nov 2026, rulings 1021 and
// 1025). Their yes re-posts the request per trade through repeat_inquiry with edits.sourcing = 'multi'; the turnkey
// original stays open for one contractor. MEASURED on origin/main: nothing recorded that the question had been answered.
// my_inquiries kept serving separate_quotes on the original, so after the page reloaded the same question and the same
// button were back; pressing it inside three minutes answered 409 "already_repeated" as an error, and after three minutes
// it posted ANOTHER per-trade copy, inviting every specialist again. The answer is the per-trade copy itself: a top-level
// request of this customer whose repeat_of is the original and whose scope_type is 'multi' (create_inquiry stores both).
// prevented by: supabase/functions/customer_api/separate_quotes.test.ts

type Row = { id?: unknown; repeat_of?: unknown; scope_type?: unknown; parent_inquiry_id?: unknown; routing?: unknown };

/** The ids of the requests the customer has already re-posted as separate quotes per trade. */
export function answeredSeparately(rows: Row[] | null | undefined): Set<string> {
  return new Set((rows || []).filter((r) => r && r.repeat_of && r.scope_type === 'multi' && !r.parent_inquiry_id).map((r) => String(r.repeat_of)));
}

/** What the card asks: how many specialists could quote it per trade, or null when there is nothing (left) to ask. */
export function separateQuotesOf(i: Row, answered: Set<string>): { specialists: number } | null {
  if (i.scope_type !== 'turnkey' || answered.has(String(i.id))) return null;
  // deno-lint-ignore no-explicit-any
  const n = Number((i.routing as any)?.separate_offer?.specialists);
  return n > 0 ? { specialists: n } : null;
}
