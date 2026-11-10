// need_fallback — A TURNKEY REQUEST NO TURNKEY CONTRACTOR MATCHES GOES TO ITS TRADES' SPECIALISTS, AND SAYS SO
// (sales_engineer; evidence run of 10 Nov 2026, ledger 1604, finding c).
//
// MEASURED (the write-up's probe, read-only, ZZ DEMO, torn down): fn_match_capability with p_trades [interior_fitout,
// joinery] and the four PVC service keys matched the wallpaper supplier at p_need 'executes' (score 15, "reached through
// wallpaper") and nobody at 'whole_scope', which only a turnkey_fitout role passes. The request had been sent as turnkey by
// the composer's preselected default, so it reached nobody.
//
// The rule: ask the need the request carries; when that need is 'whole_scope' and nobody clears the gates, ask again per
// trade ('executes') with every other criterion unchanged. The answer says which need found the suppliers (fallback), so
// the match record, the inquiry's routing and the customer's confirmation can all say it. Any other need, or a per-trade
// ask that also finds nobody or fails, leaves the first answer as it was: an honest zero is a coverage gap, not a widened ask.
export type MatchArgs = Record<string, unknown> & { p_need: string };
/** One call of public.fn_match_capability (the caller's own, so the decision step stays where every check reads it). */
export type Rpc = (args: Record<string, unknown>) => PromiseLike<{ data: unknown; error: { message: string } | null }>;
export interface NeedFallback { from: 'whole_scope'; to: 'executes'; reason: 'no_turnkey_contractor_matched'; candidates_before: 0 }
export async function matchWithNeedFallback(rpc: Rpc, args: MatchArgs): Promise<{ rows: Record<string, unknown>[]; error: { message: string } | null; need: string; fallback: NeedFallback | null }> {
  const first = await rpc(args);
  if (first.error) return { rows: [], error: first.error, need: args.p_need, fallback: null };
  const rows = (Array.isArray(first.data) ? first.data : []) as Record<string, unknown>[];
  if (rows.length || args.p_need !== 'whole_scope') return { rows, error: null, need: args.p_need, fallback: null };
  const again = await rpc({ ...args, p_need: 'executes' });
  const per = (!again.error && Array.isArray(again.data) ? again.data : []) as Record<string, unknown>[];
  if (!per.length) return { rows, error: null, need: args.p_need, fallback: null };
  return { rows: per, error: null, need: 'executes', fallback: { from: 'whole_scope', to: 'executes', reason: 'no_turnkey_contractor_matched', candidates_before: 0 } };
}
