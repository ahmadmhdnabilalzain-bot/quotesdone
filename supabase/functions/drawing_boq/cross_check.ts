// cross_check — the MODEL reads the drawing first; code's exact count of the same text layer CROSS-CHECKS it
// (3 Nov 2026, sales_engineer; founder via the coordinator: "it should feel as if I'm attaching a drawing to you —
// you understand it"). Until today a PDF set that code counted completely was answered by code alone and the model
// never saw it (27 Oct, ledger 580), so the customer got tag counts and nothing of what the drawing is about.
//
// Now both read the same PDF at once (no added wait: the model call is the clock either way) and they are merged:
//   * a line code counted and the model also listed with the SAME quantity -> confirmed by both (cross_check.agrees);
//   * the same line with a DIFFERENT quantity -> code's count stays the quantity (it is the printed tags counted one
//     by one: on 27 Oct the model doubled EF-1/EF-2 and missed three items on the set code read 7/7), the model's figure
//     is kept beside it, and the line is marked to_confirm so the sales engineer asks the customer (boq_open_lines.ts);
//   * a line only code found -> kept, marked that the model did not list it;
//   * a line only the model found (scope code cannot count: finishes, areas, notes) -> kept as the model's ESTIMATE,
//     to_confirm, never as a read quantity.
// Nothing is gated on agreement: every disagreement is FLAGGED in the line and in missing_info.
// deno-lint-ignore-file no-explicit-any

type Line = Record<string, any>;
const tagOf = (l: Line): string | null => {
  const m = String(l.type || '').match(/^tag:([A-Z0-9][A-Z0-9/.-]*?)(?::|$)/i);
  return m ? m[1].toUpperCase() : null;
};
const text = (l: Line) => `${l.item || ''} ${l.description || ''} ${l.section || ''}`.toUpperCase();
/** The model line names this tag as a whole token (FD-1 is not FD-10; "FD1" and "FD 1" are FD-1). */
function names(tag: string, l: Line): boolean {
  const [type, n] = [tag.replace(/-?\d+[A-Z]?$/, ''), (tag.match(/(\d+[A-Z]?)$/) || [])[1]];
  if (!n) return new RegExp(`(^|[^A-Z0-9])${type}([^A-Z0-9]|$)`).test(text(l));
  return new RegExp(`(^|[^A-Z0-9])${type.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}[- ]?${n}([^0-9A-Z]|$)`).test(text(l));
}
const sameQty = (a: unknown, b: unknown) => a != null && b != null && Math.abs(Number(a) - Number(b)) < 1e-9;

export type CrossChecked = { boq: Line[]; agreed: number; disagreed: string[]; code_only: string[]; model_only: number };

/** Merge the model's draft lines with code's completely-counted set (both from the same PDF). */
export function crossCheck(modelLines: Line[], codeLines: Line[]): CrossChecked {
  const used = new Set<number>();
  const out: Line[] = [];
  const disagreed: string[] = [], codeOnly: string[] = [];
  let agreed = 0;
  for (const c of codeLines) {
    const tag = tagOf(c);
    const hits = tag ? modelLines.map((m, i) => [m, i] as const).filter(([m, i]) => !used.has(i) && names(tag, m)) : [];
    hits.forEach(([, i]) => used.add(i));
    if (!hits.length) { out.push({ ...c, cross_check: { by: 'model', model_qty: null, agrees: null } }); if (tag) codeOnly.push(tag); continue; }
    const modelQty = hits.reduce((a, [m]) => a + (Number(m.qty) || 0), 0);
    if (sameQty(modelQty, c.qty)) { agreed++; out.push({ ...c, cross_check: { by: 'model', model_qty: modelQty, agrees: true } }); continue; }
    disagreed.push(`${tag} (drawing text ${c.qty}, model ${modelQty})`);
    out.push({ ...c, qty_status: 'to_confirm', estimate: c.qty, cross_check: { by: 'model', model_qty: modelQty, agrees: false } });
  }
  let modelOnly = 0;
  modelLines.forEach((m, i) => {
    if (used.has(i)) return;
    modelOnly++;
    out.push({ ...m, ...(m.qty != null ? { qty_status: 'to_confirm', estimate: m.qty } : {}), cross_check: { by: 'code', code_qty: null, agrees: null } });
  });
  return { boq: out, agreed, disagreed, code_only: codeOnly, model_only: modelOnly };
}

/** The notes the customer and the supplier read about the cross-check (src/lib/boqNotes.ts renders them in Arabic). */
export function crossCheckNotes(x: CrossChecked): string[] {
  const notes: string[] = [];
  if (x.disagreed.length) notes.push(`The drawing reading and the count of the drawing's own tags disagree on ${x.disagreed.join('; ')}; the tag count is shown and is confirmed with the customer.`);
  if (x.code_only.length) notes.push(`Counted from the drawing's own tags but not listed by the drawing reading: ${x.code_only.join(', ')}.`);
  if (x.model_only) notes.push(`${x.model_only} line(s) come from the drawing reading alone; they are estimates and are confirmed with the customer.`);
  return notes;
}
