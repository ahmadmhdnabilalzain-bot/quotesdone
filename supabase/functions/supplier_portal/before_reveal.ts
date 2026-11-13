// before_reveal — the supplier portal's own door applies the reveal rule to what three routines return (13 Nov 2026,
// sales_engineer; founder ruling 1683; independent review of F2, item 3).
// MEASURED on production (SELECT only): fn_supplier_workspaces titled every matched supplier's workspace, before any reveal,
// with fn_supplier_safe_text(summary_masked), and that SQL mask kept "Al Nahda", "Villa 15 Al Barsha 2 near Mall of the
// Emirates" and "AED 32,816.70"; its reveal test had no revealed_at. fn_supplier_opportunities served raw_input_masked (the
// whole chat) as `requirement`; fn_supplier_quote_recommend a safe_text summary. The SQL is corrected in
// scripts/sql/before_a_reveal_a_supplier_portal_title_is_the_trade_and_the_emirate.sql (pending); this door holds the rule
// whichever lands first: before a reveal (a transactions row WITH revealed_at) a supplier gets the trade and the emirate only,
// no customer sentence, no requirement, no estimated value, and no customer file name.
// prevented by: supplier_portal/the_portal_titles_name_no_customer_before_a_reveal.test.ts
import { tradeWords } from '../supplier_api/what_a_supplier_receives.ts';

export const portalTitle = (category: unknown, emirate: unknown) => tradeWords(String(category || '')) + (emirate ? ' in ' + String(emirate) : '');

// deno-lint-ignore no-explicit-any
type J = Record<string, any>;
/** fn_supplier_workspaces' answer, as a supplier may read it. `revealed` holds the inquiry ids this supplier has revealed. */
export function workspacesBeforeReveal(ws: J | null, revealed: Set<string>): J | null {
  if (!ws || !Array.isArray(ws.workspaces)) return ws;
  return { ...ws, workspaces: ws.workspaces.map((w: J) => {
    if (revealed.has(String(w?.inquiry_id))) return w;
    const p = w?.project || {};
    return { ...w, project: { ...p, title: portalTitle(p.category, p.emirate) },
      files: Array.isArray(w?.files) ? w.files.map((f: J) => ({ ...f, name: 'Job file (' + String(f?.kind || 'document') + ')' })) : w?.files };
  }) };
}
/** fn_supplier_opportunities' answer, as a supplier may read it. */
export function opportunitiesBeforeReveal(op: J | null, revealed: Set<string>): J | null {
  if (!op || !Array.isArray(op.opportunities)) return op;
  return { ...op, opportunities: op.opportunities.map((o: J) => revealed.has(String(o?.inquiry_id)) ? o
    : { ...o, project_title: portalTitle(o.category, o.emirate), requirement: null, estimated_value: null }) };
}
/** fn_supplier_quote_recommend's answer: its `summary` is a SQL-masked customer sentence; before a reveal, the trade and emirate. */
export function recommendBeforeReveal(rec: J | null, revealed: boolean, inq: { category?: unknown; emirate?: unknown } | null): J | null {
  if (!rec || revealed || !('summary' in rec)) return rec;
  return { ...rec, summary: inq ? portalTitle(inq.category, inq.emirate) : null };
}
/** The inquiries this supplier has revealed: a transactions row WITH revealed_at, the rule every other door reads. */
// deno-lint-ignore no-explicit-any
export async function revealedBy(admin: any, supId: number | string): Promise<Set<string>> {
  try {
    const { data } = await admin.from('transactions').select('inquiry_id').eq('supplier_id', supId).not('revealed_at', 'is', null);
    return new Set((data || []).map((t: { inquiry_id: string }) => String(t.inquiry_id)));
  } catch (_e) { return new Set(); }   // unknown: everything is treated as not revealed (fails closed)
}
