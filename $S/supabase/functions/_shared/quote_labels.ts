// quote_labels.ts — the anonymous name a customer sees for each quote.
//
// Until 14 Sep 2026 every quote was "Supplier " + its place in the price order, so two options from
// one supplier would have read as two suppliers. The founder: options "will be considered two
// different quotations ... each will have its own ID", so each keeps its own row, but it must still
// say whose it is: "Supplier A – Option 1", "Supplier A – Option 2" ("المورّد A – الخيار 1"). A
// supplier with one quote is plain "Supplier A", exactly as before. Letters follow the order the
// quotes arrive in (callers pass them cheapest first, the existing rule), per supplier.
export type LabelInput = { id: string; supplier_id: number | string | null; option_no?: number | null };
export type QuoteLabel = { letter: string; option_no: number; multi: boolean; en: string; ar: string };

/**
 * ONE ALIAS PER SUPPLIER PER JOB, on the supplier's own side (audit 21 Sep 2026, finding 29). The
 * supplier's letter is its place in the job's match order (inquiry_matches by id) — the question thread
 * (messages_api) and the supplier's own quotation (supplier_api quote_pdf) both read it from here. It is
 * NOT the customer's letter above: that one is the price rank among live quotes, which a supplier must
 * never learn. A supplier not in the order (never matched) is "Supplier ?" and is refused upstream.
 */
export function jobAlias(order: Array<number | string>, supplierId: number | string): string {
  const i = order.findIndex((x) => String(x) === String(supplierId));
  return 'Supplier ' + (i >= 0 ? letter(i) : '?');
}

export function letter(i: number): string { let n = Number(i) || 0, out = ''; do { out = String.fromCharCode(65 + (n % 26)) + out; n = Math.floor(n / 26) - 1; } while (n >= 0); return out; }

export function labelQuotes(quotes: LabelInput[]): Map<string, QuoteLabel> {
  const letterOf = new Map<string, string>(); const count = new Map<string, number>();
  for (const q of quotes) { const k = String(q.supplier_id ?? 'q:' + q.id); if (!letterOf.has(k)) letterOf.set(k, letter(letterOf.size)); count.set(k, (count.get(k) ?? 0) + 1); }
  const out = new Map<string, QuoteLabel>();
  for (const q of quotes) {
    const k = String(q.supplier_id ?? 'q:' + q.id); const L = letterOf.get(k)!; const n = Number(q.option_no) || 1; const multi = (count.get(k) ?? 1) > 1;
    out.set(String(q.id), { letter: L, option_no: n, multi, en: `Supplier ${L}${multi ? ` – Option ${n}` : ''}`, ar: `المورّد ${L}${multi ? ` – الخيار ${n}` : ''}` });
  }
  return out;
}
