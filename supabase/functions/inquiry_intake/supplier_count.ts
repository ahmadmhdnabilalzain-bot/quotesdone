// supplier_count — the summary card's "Recommended suppliers: N" is the dispatch's own question (10 Nov 2026, sales_engineer).
//
// MEASURED (design audit 10 Nov 2026): inquiry_intake asked fn_match_capability with the RAW intake slugs, while dispatch
// (sales_engineer/actions/operator.ts) first resolves them through fn_taxonomy_trades_for. 39 of the 56 intake slugs are
// not taxonomy codes ('glass' -> glass, glazing; 'fitout' -> fitout, interior_fitout; 'carpentry-joinery' ->
// carpentry_joinery, joinery), so for those trades the card could say 0 where dispatch reaches suppliers. The count now
// asks exactly what dispatch asks: the same resolver, exact only (founder, 14 Sep 2026: "either exact match or no match"),
// then the same matcher with the same services, emirate and limit. A resolver that fails leaves the slugs as they were.
// prevented by: inquiry_intake/supplier_count.test.ts
type Rpc = (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: unknown; error?: { message: string } | null }>;

export const DISPATCH_LIMIT = 24;

/** The taxonomy codes dispatch matches on, for these intake slugs. */
export async function taxonomyTrades(db: { rpc: Rpc }, slugs: string[]): Promise<string[]> {
  const clean = [...new Set(slugs.map(String).filter(Boolean))];
  if (!clean.length) return [];
  const { data, error } = await db.rpc('fn_taxonomy_trades_for', { p_slugs: clean });
  return !error && Array.isArray(data) && data.length ? [...new Set(data.map(String))] : clean;
}

export async function supplierCount(db: { rpc: Rpc }, o: { trades: string[]; emirate: string | null; services: string[] }): Promise<{ count: number; codes: string[]; basis: string }> {
  const codes = await taxonomyTrades(db, o.trades);
  // the same call scripts/checks/every_matcher_that_has_a_brief_passes_its_services.test.mjs reads: services always passed
  const { data: cand } = await db.rpc('fn_match_capability', {
    p_trades: codes, p_need: 'executes', p_products: [], p_brands: [],
    p_project_type: null, p_value: null, p_emirate: o.emirate || null, p_limit: DISPATCH_LIMIT, p_services: o.services,
  });
  return { count: Array.isArray(cand) ? cand.length : 0, codes,
    basis: 'fn_match_capability, the routine dispatch itself uses, over taxonomy trades [' + codes.join(',') + '] (from fn_taxonomy_trades_for of [' + o.trades.join(',') + '])'
      + (o.services.length ? ' for services [' + o.services.join(',') + ']' : '') + (o.emirate ? ' in ' + o.emirate : '') };
}
