// quote_labels.ts — the anonymous name a customer sees for each quote.
//
// Until 14 Sep 2026 every quote was "Supplier " + its place in the price order, so two options from
// one supplier would have read as two suppliers. The founder: options "will be considered two
// different quotations ... each will have its own ID", so each keeps its own row, but it must still
// say whose it is: "Supplier A – Option 1", "Supplier A – Option 2" ("المورّد A – الخيار 1"). A
// supplier with one quote is plain "Supplier A", exactly as before.
//
// ONE LETTER PER SUPPLIER PER REQUEST, GIVEN ONCE AND KEPT (15 Nov 2026, sales_engineer; journey A, exhibits 4/6/8/9). The
// letter was the quote's place in the PRICE order, worked out separately by each surface at the moment it ran: the customer's own
// quotation PDFs for Cool Breeze and for Arabian BOTH said "Supplier A" (QD-166739-A), while the comparison, run later over both,
// called them B and A. Working the letter out from ARRIVAL order instead still moved it (review REVIEW_plain item 1): a revised
// upload after a hold, a withdrawal and a re-held live quote each re-ordered the suppliers. So the letter is no longer worked out
// at all. THE RULE NOW: the first time a supplier's quote (or its first question in the request's thread) is SHOWN to the
// customer, the surface showing it records (request, supplier) -> the next letter in public.customer_supplier_letter
// (fn_customer_supplier_letters; scripts/sql/a_suppliers_letter_is_kept_from_the_first_time_the_customer_sees_it.sql), and every
// customer surface reads that row afterwards. Nothing ever updates it, so a withdrawal, a re-hold, a revised upload or a release
// cannot move a letter; a supplier never shown (held, sanctioned) has no row, so the letters run A, B, C with no gap.
//   - recordShown: the surfaces that SHOW a supplier first (the portal cards, the comparison, the question thread). Several
//     suppliers shown for the first time in one view are lettered in the order their quotes arrived (created_at, then id).
//   - storedLetters: the surfaces that only repeat a letter the customer has already seen (the quotation PDF, the reveal
//     invoice, the sales engineer's chat).
// A read that fails returns null and no surface guesses: the cards and the chat say "Supplier" with no letter; the comparison,
// the PDF and the invoice refuse so the caller retries.
// prevented by: supabase/functions/_shared/quote_labels.test.ts,
//               scripts/sql/a_suppliers_letter_is_kept_from_the_first_time_the_customer_sees_it_probe.sql (the moving cases, LOCAL)

export type LabelInput = { id: string; supplier_id: number | string | null; option_no?: number | null; created_at?: string | null };
export type QuoteLabel = { letter: string; option_no: number; multi: boolean; en: string; ar: string };
/** supplier id -> its stored letter on one request */
export type Letters = ReadonlyMap<string, string>;
export type ShownBy = 'quote_card' | 'comparison' | 'question';
/**
 * ONE ALIAS PER SUPPLIER PER JOB, on the supplier's own side (audit 21 Sep 2026, finding 29). The
 * supplier's letter is its place in the job's match order (inquiry_matches by id) — the question thread
 * (messages_api) and the supplier's own quotation (supplier_api quote_pdf) both read it from here. It is
 * NOT the customer's letter above: that one is stored from the first time the customer saw each supplier, an order
 * a supplier must never learn. A supplier not in the order (never matched) is "Supplier ?" and is refused upstream.
 */
export function jobAlias(order: Array<number | string>, supplierId: number | string): string {
  const i = order.findIndex((x) => String(x) === String(supplierId));
  return 'Supplier ' + (i >= 0 ? letter(i) : '?');
}

export function letter(i: number): string { let n = Number(i) || 0, out = ''; do { out = String.fromCharCode(65 + (n % 26)) + out; n = Math.floor(n / 26) - 1; } while (n >= 0); return out; }

const keyOf = (q: LabelInput) => String(q.supplier_id ?? '');

/** The order in which suppliers shown for the first time IN ONE VIEW are lettered: their earliest quote's created_at, then the
 *  quote id. It never decides a letter already given (that one is stored). */
export function arrivalOrder(quotes: LabelInput[]): string[] {
  const at = (q: LabelInput) => { const t = Date.parse(String(q.created_at ?? '')); return Number.isFinite(t) ? t : Infinity; };
  const first = new Map<string, { t: number; id: string }>();
  for (const q of quotes) {
    const k = keyOf(q); if (!k) continue;
    const t = at(q), id = String(q.id), f = first.get(k);
    if (!f || t < f.t || (t === f.t && id < f.id)) first.set(k, { t, id });
  }
  return [...first.entries()].sort(([, a], [, b]) => (a.t === b.t ? 0 : a.t < b.t ? -1 : 1) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0)).map(([k]) => k);
}

/** The labels of `quotes` from the STORED letters. A quote whose supplier has no stored letter gets no label (its surface says
 *  "Supplier" with no letter). "Option N" is shown when the supplier has more than one live quote among `siblings` (all the
 *  request's live quotes the surface read; by default the quotes themselves). */
export function labelQuotes(quotes: LabelInput[], letters: Letters, siblings: LabelInput[] = quotes): Map<string, QuoteLabel> {
  const count = new Map<string, number>();
  for (const q of siblings) count.set(keyOf(q), (count.get(keyOf(q)) ?? 0) + 1);
  const out = new Map<string, QuoteLabel>();
  for (const q of quotes) {
    const k = keyOf(q); const L = k ? letters.get(k) : undefined;
    if (!L) continue;
    const n = Number(q.option_no) || 1; const multi = (count.get(k) ?? 1) > 1;
    out.set(String(q.id), { letter: L, option_no: n, multi, en: `Supplier ${L}${multi ? ` – Option ${n}` : ''}`, ar: `المورّد ${L}${multi ? ` – الخيار ${n}` : ''}` });
  }
  return out;
}
/** What a surface prints for a supplier with no stored letter: the word alone, never a guessed letter. */
export const NO_LETTER = { en: 'Supplier', ar: 'المورّد' } as const;

type Row = { inquiry_id: unknown; supplier_id: unknown; letter: unknown };
function byInquiry(rows: Row[], ids: string[]): Map<string, Map<string, string>> {
  const out = new Map<string, Map<string, string>>(ids.map((i) => [i, new Map<string, string>()]));
  for (const r of rows) {
    const m = out.get(String(r.inquiry_id)); const L = String(r.letter ?? '');
    if (m && /^[A-Z]{1,3}$/.test(L)) m.set(String(r.supplier_id), L);
  }
  return out;
}

/** RECORD the suppliers being shown to the customer now and return every stored letter of these requests, by request. `shown`
 *  is what this surface shows, per request (live, not held, not sanctioned: the function refuses a sanctioned supplier and one
 *  with no live quote or question on the request whatever is passed). One call for many requests. null when it failed. */
// deno-lint-ignore no-explicit-any
export async function recordShown(admin: any, shown: Map<string, LabelInput[]> | Record<string, LabelInput[]>, by: ShownBy, alsoRead: string[] = []): Promise<Map<string, Map<string, string>> | null> {
  const entries = shown instanceof Map ? [...shown.entries()] : Object.entries(shown);
  const ids = [...new Set([...entries.map(([k]) => String(k)), ...alsoRead.map(String)].filter(Boolean))];
  if (!ids.length) return new Map();
  const list = entries.flatMap(([iid, qs]) => arrivalOrder(qs).map((sid) => ({ inquiry_id: String(iid), supplier_id: sid })));
  try {
    const { data, error } = await admin.rpc('fn_customer_supplier_letters', { p_inquiry_ids: ids, p_shown: list, p_shown_by: by });
    if (error || !Array.isArray(data)) return null;
    return byInquiry(data, ids);
  } catch (_e) { return null; }
}

/** READ the letters already given on these requests (no new letter). null when the read failed. */
// deno-lint-ignore no-explicit-any
export async function storedLetters(admin: any, inquiryIds: string[]): Promise<Map<string, Map<string, string>> | null> {
  const ids = [...new Set(inquiryIds.map(String).filter(Boolean))];
  if (!ids.length) return new Map();
  try {
    const { data, error } = await admin.from('customer_supplier_letter').select('inquiry_id,supplier_id,letter').in('inquiry_id', ids);
    if (error || !Array.isArray(data)) return null;
    return byInquiry(data, ids);
  } catch (_e) { return null; }
}

/** One quote's stored letter: { ok: false } when the read failed (the caller refuses), { ok: true, letter: null } when the
 *  customer has not been shown this supplier (the caller prints "Supplier" with no letter). */
// deno-lint-ignore no-explicit-any
export async function storedLetterOf(admin: any, q: { inquiry_id: unknown; supplier_id: unknown }): Promise<{ ok: false } | { ok: true; letter: string | null }> {
  const m = await storedLetters(admin, [String(q.inquiry_id ?? '')]);
  if (!m) return { ok: false };
  return { ok: true, letter: m.get(String(q.inquiry_id))?.get(String(q.supplier_id)) ?? null };
}
