// ceo_agent — the objective and the limits at the CEO's door (ceo, 15 Nov 2026; founder ledger 1701 and 1696).
//
//   coverage  (the founder or the CEO; read-only)  supplier coverage against target (fn_supplier_coverage, the one routine),
//             the funnel (fn_supplier_funnel_reading), the company limits with any waiting change (fn_company_limits) and the
//             CEO's latest supply decisions (ceo_supply_decision).
//   limit     (the CEO only)  change a company limit with a reason; it takes effect 24 hours later and is in the founder's
//             daily summary (fn_ceo_sets_company_limit). Nothing lets a seat exceed the value in force meanwhile.
//   target    (the CEO only)  set, change or retire (target null) a coverage target with a reason (fn_ceo_sets_coverage_target).
// The founder reads; he is never asked to approve (ledger 1696). The limits and targets are data the routines enforce, so a
// sentence here never decides anything.
// prevented by: supabase/functions/ceo_agent/coverage.test.ts
export type RpcResult = { data: unknown; error: { message?: string } | null };
export type Db = {
  rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<RpcResult>;
  recentDecisions: (limit: number) => PromiseLike<RpcResult>;
};
export type Who = 'founder' | 'ceo';
export type Answer = { status: number; body: Record<string, unknown> };

export const COVERAGE_ACTIONS = ['coverage', 'limit', 'target'] as const;

export async function coverageAction(db: Db, who: Who, action: string, body: Record<string, unknown>): Promise<Answer | null> {
  if (action === 'coverage') {
    const days = Number(body.days ?? 30);
    const [cov, fun, lim, dec] = await Promise.all([
      db.rpc('fn_supplier_coverage', { p_limit: 10 }),
      db.rpc('fn_supplier_funnel_reading', { p_days: Number.isFinite(days) && days > 0 ? Math.min(days, 365) : 30 }),
      db.rpc('fn_company_limits', {}),
      db.recentDecisions(20),
    ]);
    const err = [cov, fun, lim, dec].find((r) => r.error)?.error;
    if (err) return { status: 503, body: { ok: false, error: 'coverage_unavailable', detail: err.message ?? String(err) } };
    return { status: 200, body: { ok: true, coverage: cov.data, funnel: fun.data, limits: lim.data, decisions: dec.data ?? [] } };
  }
  if (action === 'limit' || action === 'target') {
    if (who !== 'ceo') return { status: 403, body: { error: 'only the ceo changes a company ' + action, detail: 'The founder reads the change in the CEO\'s daily summary (founder ledger 1696). Present the fn.ceo_agent credential.' } };
    const reason = String(body.reason ?? '').trim();
    if (reason.length < 20) return { status: 400, body: { error: 'reason_required', detail: 'say why, in a sentence (20 characters or more)' } };
    const r = action === 'limit'
      ? await db.rpc('fn_ceo_sets_company_limit', { p_key: String(body.key ?? ''), p_value_aed: Number(body.value_aed), p_reason: reason })
      : await db.rpc('fn_ceo_sets_coverage_target', { p_trade: String(body.trade ?? ''), p_emirate: String(body.emirate ?? 'UAE'),
          p_target: body.target === null || body.target === undefined ? null : Number(body.target), p_reason: reason });
    if (r.error) return { status: 400, body: { ok: false, error: r.error.message ?? String(r.error) } };
    const d = (r.data || {}) as Record<string, unknown>;
    return { status: d.ok === false ? 400 : 200, body: d };
  }
  return null;
}
