// turnkey_miss — A TURNKEY REQUEST NO TURNKEY CONTRACTOR MATCHES IS NEVER SPLIT ON THE MATCHER'S OWN ACCOUNT; THE
// CUSTOMER IS ASKED (sales_engineer; evidence run of 10 Nov 2026, ledger 1604, finding c; standing rulings 1021 and 1025:
// "for breaking big projects into trades, that should be asked to the customer before proceeding"; "the default is one
// contractor").
//
// MEASURED (the write-up's read-only probe, ZZ DEMO, torn down): fn_match_capability with p_trades [interior_fitout,
// joinery] and the four PVC service keys matched the wallpaper supplier at p_need 'executes' (score 15) and nobody at
// 'whole_scope', which only a turnkey_fitout role passes. So the request reached nobody, and nobody told the customer that
// separate quotes per trade would reach someone.
//
// THE RULE. The request is matched on the need it carries, and only that decides who is invited. When that need is
// 'whole_scope' and nobody clears the gates, the same criteria are COUNTED per trade ('executes'): nobody is invited,
// nothing is split. The count is what the customer is asked with ("no single contractor is available yet; would you like
// separate quotes per trade?"), and only their recorded 'multi' re-posts it per trade (customer_api repeat_inquiry with
// edits.sourcing = 'multi' -> create_inquiry, whose split guard a03_inquiry_split_needs_the_customers_choice accepts only
// a parent recorded 'multi'). The miss stays a coverage gap for the sales engineer either way.
export type Rpc = (args: Record<string, unknown>) => PromiseLike<{ data: unknown; error: { message: string } | null }>;
/** What the customer is asked with: how many specialists of the request's trades could quote it as separate packages. */
export interface SeparateOffer { ask: 'separate_quotes_per_trade'; specialists: number }
export async function matchTurnkeyOrAsk(rpc: Rpc, args: Record<string, unknown> & { p_need: string }): Promise<{ rows: Record<string, unknown>[]; error: { message: string } | null; separate_offer: SeparateOffer | null }> {
  const first = await rpc(args);
  if (first.error) return { rows: [], error: first.error, separate_offer: null };
  const rows = (Array.isArray(first.data) ? first.data : []) as Record<string, unknown>[];
  if (rows.length || args.p_need !== 'whole_scope') return { rows, error: null, separate_offer: null };
  // Counted, never invited: these rows are not returned and nobody is written or notified from them.
  const per = await rpc({ ...args, p_need: 'executes' });
  const n = !per.error && Array.isArray(per.data) ? per.data.length : 0;
  return { rows, error: null, separate_offer: n > 0 ? { ask: 'separate_quotes_per_trade', specialists: n } : null };
}
