// quote_line_compare — suppliers' per-line quantities and unit rates set beside OUR quantity, so a
// difference in take-off is shown to the customer instead of hidden inside a total. No model.
//
// WHY (founder, 14 Sep 2026, relayed). A drawing line nobody confirmed goes out as "estimated from
// drawing, supplier to verify take-off" (boq_open_lines). Each supplier then quotes its OWN quantity
// and unit rate for that line. Comparing totals would reward the supplier who counted fewest; so the
// comparison normalises by unit rate, and flags, per line:
//   * a supplier whose quantity differs from ours by more than TOLERANCE,
//   * suppliers whose quantities differ from EACH OTHER by more than TOLERANCE,
//   * a line whose quantity was never confirmed, so every supplier's number is its own take-off.
// "Never assume silently": every flag carries the numbers that caused it.

export const TOLERANCE = 0.1;
export type OurLine = { key: string; description: string; unit: string; qty: number | null; qty_status?: string };
export type SupplierLine = { key: string; qty: number | null; unit_rate: number | null };
export type SupplierQuote = { supplier: string; lines: SupplierLine[] };
export type LineCompare = {
  key: string; description: string; unit: string; our_qty: number | null; verified_by_supplier: boolean;
  suppliers: { supplier: string; qty: number | null; unit_rate: number | null; line_total: number | null; vs_ours: 'same' | 'higher' | 'lower' | 'no_qty' | 'no_ours'; diff_pct: number | null }[];
  cheapest_rate: string | null; flags: string[];
};

const pct = (a: number, b: number) => (b === 0 ? null : Math.round(((a - b) / b) * 1000) / 10);

export function compareLines(ours: OurLine[], quotes: SupplierQuote[], tol = TOLERANCE): LineCompare[] {
  return ours.map((o) => {
    const rows = quotes.map((q) => {
      const l = q.lines.find((x) => x.key === o.key);
      const qty = l?.qty ?? null, rate = l?.unit_rate ?? null;
      let vs: LineCompare['suppliers'][number]['vs_ours'] = 'no_qty'; let diff: number | null = null;
      if (qty != null && o.qty != null) { diff = pct(qty, o.qty); vs = diff == null || Math.abs(diff) <= tol * 100 ? 'same' : diff > 0 ? 'higher' : 'lower'; }
      else if (qty != null) vs = 'no_ours';
      return { supplier: q.supplier, qty, unit_rate: rate, line_total: qty != null && rate != null ? Math.round(qty * rate * 100) / 100 : null, vs_ours: vs, diff_pct: diff };
    });
    const flags: string[] = [];
    const verified = o.qty_status === 'estimated_supplier_to_verify';
    if (verified) flags.push(`our quantity${o.qty != null ? ` (${o.qty} ${o.unit})` : ''} was estimated from the drawing; each supplier's number is its own take-off`);
    for (const r of rows) if (r.vs_ours === 'higher' || r.vs_ours === 'lower') flags.push(`${r.supplier} quotes ${r.qty} ${o.unit}, ${Math.abs(r.diff_pct!)}% ${r.vs_ours} than our ${o.qty}`);
    const qs = rows.map((r) => r.qty).filter((n): n is number => n != null);
    if (qs.length >= 2 && Math.min(...qs) > 0 && Math.max(...qs) / Math.min(...qs) > 1 + tol) flags.push(`suppliers' quantities differ from each other: ${Math.min(...qs)} to ${Math.max(...qs)} ${o.unit}`);
    const priced = rows.filter((r) => r.unit_rate != null).sort((a, b) => a.unit_rate! - b.unit_rate!);
    return { key: o.key, description: o.description, unit: o.unit, our_qty: o.qty, verified_by_supplier: verified, suppliers: rows, cheapest_rate: priced[0]?.supplier ?? null, flags };
  });
}

/** Each supplier's total at OUR quantities and their own unit rates: the like-for-like figure. */
export function totalsAtOurQuantities(cmp: LineCompare[]): Record<string, { total: number; lines_priced: number; lines_missing: number }> {
  const out: Record<string, { total: number; lines_priced: number; lines_missing: number }> = {};
  for (const c of cmp) for (const s of c.suppliers) {
    const t = (out[s.supplier] ||= { total: 0, lines_priced: 0, lines_missing: 0 });
    const q = c.our_qty ?? s.qty;
    if (q != null && s.unit_rate != null) { t.total = Math.round((t.total + q * s.unit_rate) * 100) / 100; t.lines_priced++; } else t.lines_missing++;
  }
  return out;
}
