// quote_labels.ts — the anonymous name a customer sees for each quote.
//
// Until 14 Sep 2026 every quote was "Supplier " + its place in the price order, so two options from
// one supplier would have read as two suppliers. The founder: options "will be considered two
// different quotations ... each will have its own ID", so each keeps its own row, but it must still
// say whose it is: "Supplier A – Option 1", "Supplier A – Option 2" ("المورّد A – الخيار 1"). A
// supplier with one quote is plain "Supplier A", exactly as before.
//
// ONE LETTER PER SUPPLIER PER REQUEST, GIVEN ONCE (15 Nov 2026, sales_engineer; journey A, exhibits 4/6/8/9). The letter was the
// quote's place in the PRICE order, worked out separately by each surface at the moment it ran: the customer's own quotation
// PDFs for Cool Breeze and for Arabian BOTH said "Supplier A" (QD-166739-A; each was the cheapest live quote when its PDF was
// made), while the comparison, run later over both, called them B and A. A price rank moves every time a cheaper quote arrives,
// so no letter was ever stable. THE RULE NOW: a supplier's letter is the order in which its first quote reached the customer
// (`live_since`: when a quality hold released it, else created_at; ties by quote id), counted over EVERY live quote of the
// request, including one held for missing details or from a sanctioned supplier, so hiding or releasing a quote never moves
// another's letter. A later quote, cheaper or not, takes the next letter; an earlier supplier's letter never changes.
// customerQuoteLabels is the one read every customer surface uses (portal cards, quote PDF and its file name, comparison,
// reveal invoice, the sales engineer's chat); none of them computes a letter of its own.
// prevented by: supabase/functions/_shared/quote_labels.test.ts (three quotes arriving in every order)
import { isLiveQuote, NOT_LIVE_QUOTE_IN } from './quote_live.ts';

export type LabelInput = { id: string; supplier_id: number | string | null; option_no?: number | null;
  /** when the quote reached the customer: quote_quality_hold.released_at for a quote a quality hold released, else quotes.created_at */
  live_since?: string | null; created_at?: string | null };
export type QuoteLabel = { letter: string; option_no: number; multi: boolean; en: string; ar: string };

/**
 * ONE ALIAS PER SUPPLIER PER JOB, on the supplier's own side (audit 21 Sep 2026, finding 29). The
 * supplier's letter is its place in the job's match order (inquiry_matches by id) — the question thread
 * (messages_api) and the supplier's own quotation (supplier_api quote_pdf) both read it from here. It is
 * NOT the customer's letter above: that one is the order the live quotes reached the customer, which a
 * supplier must never learn. A supplier not in the order (never matched) is "Supplier ?" and is refused upstream.
 */
export function jobAlias(order: Array<number | string>, supplierId: number | string): string {
  const i = order.findIndex((x) => String(x) === String(supplierId));
  return 'Supplier ' + (i >= 0 ? letter(i) : '?');
}

export function letter(i: number): string { let n = Number(i) || 0, out = ''; do { out = String.fromCharCode(65 + (n % 26)) + out; n = Math.floor(n / 26) - 1; } while (n >= 0); return out; }

/** The labels, by arrival (above). A caller that passes no times keeps the order it passed (the rule before 15 Nov). */
export function labelQuotes(quotes: LabelInput[]): Map<string, QuoteLabel> {
  const at = (q: LabelInput) => { const t = Date.parse(String(q.live_since ?? q.created_at ?? '')); return Number.isFinite(t) ? t : Infinity; };
  const keyOf = (q: LabelInput) => String(q.supplier_id ?? 'q:' + q.id);
  // each supplier's first arrival: its earliest quote (time, then id), and where that quote stood in the input
  const first = new Map<string, { t: number; id: string; i: number }>(); const count = new Map<string, number>();
  quotes.forEach((q, i) => {
    const k = keyOf(q), t = at(q), id = String(q.id), f = first.get(k);
    if (!f) first.set(k, { t, id, i });
    else if (t < f.t || (t === f.t && t !== Infinity && id < f.id)) first.set(k, { t, id, i: f.i });
    count.set(k, (count.get(k) ?? 0) + 1);
  });
  const order = [...first.entries()].sort(([, a], [, b]) => (a.t - b.t) || (a.t !== Infinity && a.id !== b.id ? (a.id < b.id ? -1 : 1) : 0) || (a.i - b.i)).map(([k]) => k);
  const letterOf = new Map<string, string>(order.map((k, i) => [k, letter(i)]));
  const out = new Map<string, QuoteLabel>();
  for (const q of quotes) {
    const k = keyOf(q); const L = letterOf.get(k)!; const n = Number(q.option_no) || 1; const multi = (count.get(k) ?? 1) > 1;
    out.set(String(q.id), { letter: L, option_no: n, multi, en: `Supplier ${L}${multi ? ` – Option ${n}` : ''}`, ar: `المورّد ${L}${multi ? ` – الخيار ${n}` : ''}` });
  }
  return out;
}

/** The quotes as labelQuotes reads them: each live quote with `live_since`, the latest release of a hold on it (a quote a quality
 *  or spec hold kept back is a draft until released, so it reached the customer then, not at created_at). */
export function arrivals(quotes: Array<{ id: unknown; supplier_id: number | string | null; option_no?: number | null; created_at?: string | null; status?: unknown }>,
  holds: Array<{ quote_id: unknown; released_at?: string | null }> = []): LabelInput[] {
  const released = new Map<string, string>();
  for (const h of holds) {
    if (!h || !h.released_at || !Number.isFinite(Date.parse(String(h.released_at)))) continue;
    const k = String(h.quote_id), was = released.get(k);
    if (!was || Date.parse(String(h.released_at)) > Date.parse(was)) released.set(k, String(h.released_at));
  }
  return quotes.filter((q) => isLiveQuote(q.status)).map((q) => ({ id: String(q.id), supplier_id: q.supplier_id, option_no: q.option_no ?? 1,
    created_at: q.created_at ?? null, live_since: released.get(String(q.id)) ?? null }));
}

/** THE ONE READ (above), for one or many requests: every live quote of each and the quality and spec holds that released any of
 *  them (three reads in parallel), labelled per request. A request whose quotes cannot be read gets no entry, and its caller
 *  says "Supplier" with no letter rather than a guessed one; a hold table that cannot be read leaves created_at to decide. */
// deno-lint-ignore no-explicit-any
export async function customerQuoteLabelsByInquiry(admin: any, inquiryIds: string[]): Promise<Map<string, Map<string, QuoteLabel>>> {
  const out = new Map<string, Map<string, QuoteLabel>>();
  const ids = [...new Set(inquiryIds.map(String).filter(Boolean))];
  if (!ids.length) return out;
  try {
    // deno-lint-ignore no-explicit-any
    const holdsOf = async (table: string): Promise<any[]> => { try { const { data, error } = await admin.from(table).select('quote_id,released_at').in('inquiry_id', ids).not('released_at', 'is', null); return !error && Array.isArray(data) ? data : []; } catch (_e) { return []; } };
    const [qr, quality, spec] = await Promise.all([
      admin.from('quotes').select('id,inquiry_id,supplier_id,option_no,created_at,status').in('inquiry_id', ids).not('status', 'in', NOT_LIVE_QUOTE_IN).limit(2000),
      holdsOf('quote_quality_hold'), holdsOf('quote_spec_hold'),
    ]);
    if (qr?.error || !Array.isArray(qr?.data)) return out;
    const holds = [...quality, ...spec];
    for (const iid of ids) out.set(iid, labelQuotes(arrivals(qr.data.filter((q: { inquiry_id: unknown }) => String(q.inquiry_id) === iid), holds)));
    return out;
  } catch (_e) { return out; }
}
// deno-lint-ignore no-explicit-any
export async function customerQuoteLabels(admin: any, inquiryId: string): Promise<Map<string, QuoteLabel>> {
  return (await customerQuoteLabelsByInquiry(admin, [String(inquiryId)])).get(String(inquiryId)) ?? new Map();
}
