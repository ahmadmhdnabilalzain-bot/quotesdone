// inquiry_posted — ONE answer shape for customer_api create_inquiry, whatever the request became.
// Assigned: sales_engineer.
//
// MEASURED 14 Sep 2026 (harness journey a, 16:40 UTC): a request with two trades is posted as a
// combined PARENT (status 'split') with one CHILD per trade, and create_inquiry answered
//   single / turnkey  {ok, inquiry_id, matches}
//   split             {ok, split, parent_id, children:[{inquiry_id,...}]}   <- no top-level id
// so the harness (reading id ?? inquiry_id) and anything else keyed on the id could not tell which
// request it had just created. Now every path answers with:
//   inquiry_id  the request the customer made: the single request, or the combined parent
//   parent_id   the combined parent, or null
//   child_ids   the per-trade requests suppliers quote on ([] when not split)
//   children    [{inquiry_id, trade, label, matches}] ([] when not split)
//   quotable_ids the ids a supplier can quote on (children when split, else the request itself)
//   matches     suppliers reached, summed over the children for a split
//   scope_type  'single' | 'turnkey' | 'multi'
//   matching_pending  true when the matcher did not answer for the request (or one of its parts) and it is waiting for
//               the re-match (customer_api/lib/rematch.ts): the portal says "we are matching your request", not
//               "no supplier covers this trade" — measured 10 Nov 2026, it said the second over a trade never searched
// The old keys (split, parent_id, children, routing) are kept, so no existing reader breaks.

export type PostedChild = { inquiry_id: string; trade: string; label: string; matches: number; matching?: boolean };
export type Posted = {
  ok: true; inquiry_id: string; parent_id: string | null; child_ids: string[]; children: PostedChild[];
  quotable_ids: string[]; matches: number; scope_type: 'single' | 'turnkey' | 'multi'; split: boolean; matching_pending: boolean;
  trades?: string[]; routing?: unknown; failed_trades?: string[];
};

export function postedSingle(id: string, scope: 'single' | 'turnkey', matches: number, routing?: unknown): Posted {
  return { ok: true, inquiry_id: String(id), parent_id: null, child_ids: [], children: [], quotable_ids: [String(id)], matches: Number(matches) || 0, scope_type: scope, split: false, matching_pending: !!(routing && (routing as { matcher_unavailable?: unknown }).matcher_unavailable === true), ...(routing !== undefined ? { routing } : {}) };
}

export function postedSplit(parentId: string, children: PostedChild[], trades: string[], failedTrades: string[] = []): Posted {
  const ids = children.map((c) => String(c.inquiry_id));
  return {
    ok: true, inquiry_id: String(parentId), parent_id: String(parentId), child_ids: ids, children,
    quotable_ids: ids, matches: children.reduce((n, c) => n + (Number(c.matches) || 0), 0),
    scope_type: 'multi', split: true, matching_pending: children.some((c) => c.matching === true), trades, ...(failedTrades.length ? { failed_trades: failedTrades } : {}),
  };
}
