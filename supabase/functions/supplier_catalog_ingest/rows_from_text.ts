// A PDF catalogue's text layer -> product rows, by code, where the page states a price.
//
// 15 Sep 2026. Every PDF catalogue went to the model, and the model is on hold, so a price list
// exported to PDF produced nothing. linesOf() rebuilds visual lines but joins cells with single
// spaces, so column boundaries are gone; what survives reliably is a line that PRINTS A PRICE next to
// the item. That is the only line taken: "<name> ... AED 12.50" (or "12.50 AED", "Dhs", "درهم").
// A line without a price is not guessed at — it stays for the model when the hold lifts.
export type TextProduct = { name: string; model: string | null; unit: string | null; price: number; brand: null; description: null; attributes: Record<string, unknown> };

// Currency-first is tried first: in "PT-6060 AED 45.50" the model number also sits before "AED".
const PRE = /(?<![A-Za-z])(?:AED|Dhs?\.?|درهم)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i;
const POST = /(?<![\w.,-])([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*(?:AED|Dhs?\.?|درهم)(?![A-Za-z])/i;
const MODEL = /\b(?=[A-Z0-9-]*[0-9])(?=[A-Z0-9-]*[A-Z])[A-Z0-9][A-Z0-9-]{2,}\b/;
const UNIT = /(?:\/|\bper)\s*(sqm|m2|lm|rm|m|pcs?|nos?|each|kg|ton|roll|box|set|ltr|l)\b/i;

export function productsFromText(text: string): TextProduct[] {
  const out: TextProduct[] = [];
  for (const raw of String(text ?? '').split('\n')) {
    const line = raw.replace(/\s+/g, ' ').trim();
    if (!line || line.length > 200) continue;
    const m = PRE.exec(line) || POST.exec(line);
    if (!m) continue;
    const price = Number(m[1].replace(/,/g, ''));
    const unit = line.match(UNIT)?.[1]?.toLowerCase() ?? null;
    const name = line.replace(m[0], ' ').replace(UNIT, ' ').replace(/\s+/g, ' ').replace(/^[\s\-–:|•]+|[\s\-–:|•]+$/g, '').trim();
    if (!/[A-Za-z؀-ۿ]{3}/.test(name) || /^(grand\s+)?(total|subtotal|sum|vat)\b/i.test(name)) continue;
    if (!Number.isFinite(price) || price <= 0) continue;
    out.push({ name: name.slice(0, 200), model: name.match(MODEL)?.[0] ?? null, unit, price, brand: null, description: null, attributes: { source_line: line } });
  }
  return out;
}
