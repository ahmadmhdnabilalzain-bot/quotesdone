// reveal_guard.ts — ONE DOOR DECIDES WHETHER A QUOTE MAY BE REVEALED.
//
// Customer-portal audit, 22 Sep 2026 (CP-01, CP-09, CP-15). Three surfaces reveal a supplier and
// each checked something different:
//   * customer_api `reveal` checked ownership and sanctions, not completeness.
//   * stripe_checkout checked ownership only — no sanctions check, no quote status, no inquiry
//     status — so a customer's card could be charged 3% to be handed a party the platform has
//     permanently banned (founder instruction 516), or the contact for a quote the comparison
//     itself refuses to rank.
//   * stripe_confirm checked sanctions at disclosure and nothing else.
// The checks now live here, in one function all three call, so a door cannot be added without them.
//
// THE HOLD RULE IS NOT A SECOND COPY. quote_compare withholds a quote that is missing a line spec,
// a delivery date, installation or warranty where they apply, or its ex-VAT price (the founder's
// hold rule, 14 Sep 2026; line_specs/assess.ts decides, line_specs/compare.ts `rankable` counts).
// `heldQuoteIds` below is that same predicate reached through the same `rankable`; the only thing
// added here is the mapping from database rows to its input, which quote_compare, my_inquiries and
// this guard all now share.
import { rankable } from './line_specs/compare.ts';
import { requirementsOf, type Line, type Terms } from './line_specs/assess.ts';
import { sanctionedLead } from './sanctioned.ts';

// deno-lint-ignore no-explicit-any
type Admin = { from: (t: string) => any };
// deno-lint-ignore no-explicit-any
export type QuoteRow = Record<string, any>;
// deno-lint-ignore no-explicit-any
export type ItemRow = Record<string, any>;

/** A quotes row plus its quote_items rows, as line_specs wants them. Written once, read three times. */
export function assessInput(q: QuoteRow, items: ItemRow[]): { lines: Line[]; terms: Terms } {
  return {
    lines: (items || []).map((it) => ({
      line_no: Number(it.line_no ?? it.line ?? 0), description: String(it.description || ''),
      brand: it.brand, model: it.model, specification: it.specification, qty: it.qty, unit: it.unit,
      unit_price: it.unit_price, labour: it.labour, install: it.install, amount: it.amount,
      notes: it.notes, spec: it.spec ?? null,
    })),
    // price_ex_vat AND NOTHING ELSE. It is the figure the founder's hold rule names and the figure
    // the 3% is charged on (line_specs/vat.ts); quote_amount is the supplier's headline total and
    // may be VAT-inclusive or ambiguous, which is exactly the condition assess.ts holds a quote
    // for. Falling back to it would silently UN-hold those quotes on all three surfaces — review
    // of #850, 22 Sep 2026. Null travels as null; a quote with no exact ex-VAT price stays held.
    terms: { lead_time: q.lead_time, warranty: q.warranty, scope: q.scope, exclusions: q.exclusions,
      conditions: q.conditions, notes: q.notes, terms_spec: q.terms_spec,
      price_ex_vat: q.price_ex_vat ?? null },
  };
}

/** The ids of the quotes that are ON HOLD for missing details — never ranked, never revealable. */
export function heldQuoteIds(
  rows: { quote: QuoteRow; items: ItemRow[] }[], category: string | null, spec: unknown,
): Set<string> {
  const all = rows.map((r) => ({ id: String(r.quote.id), ...assessInput(r.quote, r.items) }));
  const ok = new Set(rankable(all, category, requirementsOf(spec)).rankable.map((x) => x.id));
  return new Set(all.map((x) => x.id).filter((id) => !ok.has(id)));
}

/**
 * quote_items for these quote ids, grouped by quote.
 *
 * PAGED, NOT CAPPED (review of #850, 22 Sep 2026). One read with .limit(2000) across every quote
 * id at once silently drops the highest line numbers once a customer's requests carry more than
 * 2000 lines between them — and a dropped line is a line whose missing mandatory spec is never
 * counted, so an INCOMPLETE quote reads as rankable and becomes revealable. The read is therefore
 * paged to exhaustion in id chunks; a missing line must never be the reason a quote looks complete.
 */
export async function itemsByQuote(admin: Admin, quoteIds: string[]): Promise<Record<string, ItemRow[]>> {
  const out: Record<string, ItemRow[]> = {};
  if (!quoteIds.length) return out;
  const COLS = 'quote_id,line_no,description,brand,model,specification,qty,unit,unit_price,labour,install,amount,notes,spec';
  const CHUNK = 25;     // quote ids per request — keeps the URL short and the page small
  const PAGE = 1000;    // rows per page; paged until a short page says the chunk is exhausted
  for (let i = 0; i < quoteIds.length; i += CHUNK) {
    const ids = quoteIds.slice(i, i + CHUNK);
    for (let from = 0; ; from += PAGE) {
      const { data } = await admin.from('quote_items').select(COLS)
        .in('quote_id', ids).order('quote_id', { ascending: true }).order('line_no', { ascending: true })
        .range(from, from + PAGE - 1);
      const rows = data || [];
      for (const r of rows) (out[String(r.quote_id)] ||= []).push(r);
      if (rows.length < PAGE) break;
    }
  }
  return out;
}

// Every refusal carries a machine code AND both languages, because the three callers answer
// customers in the language they registered in and none of them should be writing sentences.
export type Refusal = { ok: false; status: number; code: string; error: string; message: string; message_ar: string };
export type Allowed = { ok: true; quote: QuoteRow; inquiry: QuoteRow; already_revealed: boolean };

const REFUSALS: Record<string, { status: number; en: string; ar: string }> = {
  quote_not_found: { status: 404, en: 'That quote is no longer available.', ar: 'هذا العرض لم يعد متاحًا.' },
  not_your_inquiry: { status: 403, en: 'That request is not on your account.', ar: 'هذا الطلب ليس ضمن طلباتك.' },
  inquiry_closed: { status: 409, en: 'This request is closed, so a supplier cannot be revealed on it.', ar: 'هذا الطلب مغلق، فلا يمكن كشف مورّد فيه.' },
  quote_on_hold: {
    status: 409,
    en: 'This quote is on hold: the supplier has not stated every detail your request needs, so we are asking them for it. It is not ready to reveal yet.',
    ar: 'هذا العرض معلّق: لم يذكر المورّد كل التفاصيل التي يحتاجها طلبك، ونحن نطلبها منه. لا يمكن كشفه بعد.',
  },
  account_sanctioned: {
    status: 403,
    en: 'This supplier account is permanently closed and cannot be revealed.',
    ar: 'حساب هذا المورّد مغلق نهائيًا ولا يمكن كشفه.',
  },
};

export function refuse(code: keyof typeof REFUSALS | string): Refusal {
  const r = REFUSALS[String(code)] || { status: 409, en: 'This supplier cannot be revealed right now.', ar: 'لا يمكن كشف هذا المورّد الآن.' };
  return { ok: false, status: r.status, code: String(code), error: String(code), message: r.en, message_ar: r.ar };
}

/**
 * May this customer be handed (or charged for) this supplier's identity?
 * Checked in the order that costs least and refuses earliest; the sanctions read throws rather than
 * failing open (see sanctioned.ts), so the caller's catch answers 500 instead of disclosing.
 */
export async function canReveal(
  admin: Admin, opts: { quoteId: string; customerId: string },
): Promise<Refusal | Allowed> {
  const qid = String(opts.quoteId || '');
  if (!qid) return refuse('quote_not_found');
  const { data: q } = await admin.from('quotes')
    .select('id,inquiry_id,supplier_id,status,quote_amount,price_ex_vat,lead_time,warranty,scope,exclusions,conditions,notes,terms_spec,original_file_path,original_file_name')
    .eq('id', qid).maybeSingle();
  // A draft is not a quote the customer has (customer_api never lists one), so it has no reveal.
  if (!q || String(q.status || '') === 'draft') return refuse('quote_not_found');
  // rfq_no and summary travel with the row because the callers print them (the Stripe line item's
  // reference, the supplier's notice); one read, not three.
  const { data: inq } = await admin.from('inquiries').select('id,customer_id,status,category,spec,rfq_no,summary').eq('id', q.inquiry_id).maybeSingle();
  if (!inq || String(inq.customer_id) !== String(opts.customerId)) return refuse('not_your_inquiry');
  // 'revealed' and 'completed' are NOT closed: a customer may reveal a second supplier on a job
  // they already revealed or hired on. Cancelled and closed are the end of the request.
  if (['cancelled', 'closed'].includes(String(inq.status || ''))) return refuse('inquiry_closed');
  const { data: existing } = await admin.from('transactions').select('id').eq('quote_id', qid).maybeSingle();
  const already = !!existing;
  // Sanctions bite even on an already-paid reveal: instruction 516 is "never shown to a customer".
  if (await sanctionedLead(admin, q.supplier_id)) return refuse('account_sanctioned');
  // A quote already paid for is never re-held: the customer owns that disclosure.
  if (!already) {
    const held = heldQuoteIds([{ quote: q, items: (await itemsByQuote(admin, [qid]))[qid] || [] }], inq.category ?? null, inq.spec);
    if (held.has(qid)) return refuse('quote_on_hold');
  }
  return { ok: true, quote: q, inquiry: inq, already_revealed: already };
}
