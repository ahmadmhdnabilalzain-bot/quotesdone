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
import { isLiveQuote } from './quote_live.ts';
import { requirementsOf, type Line, type Terms } from './line_specs/assess.ts';
import { sanctionedLead, screeningOpen } from './sanctioned.ts';

// deno-lint-ignore no-explicit-any
type Admin = { from: (t: string) => any; rpc: (fn: string, args: Record<string, unknown>) => any };
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
      notes: it.notes, spec: it.spec ?? null, spec_source: it.spec_source ?? null,
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

/**
 * A quote_items row as the comparison carries it, WITH its spec_source (sales_engineer, 2 Nov 2026). quote_compare
 * mapped its own rows and dropped spec_source, so every value the gate's reading wrote (source 'reasoned': which line
 * names the customer's glass and profile, which line is no material) was invisible to the ranking's re-check. The
 * re-check then held every quote the gate had accepted: journey run 41450058264, three submitted, gate-accepted quotes
 * answered on_hold=3 "needs at least two complete quotes". One mapping, here, so the gate's persisted reading is the
 * reading every surface checks. prevented by: _shared/the_comparison_reads_what_the_gate_read.test.ts
 */
export function compareItem(r: ItemRow) {
  return { line: r.line_no, description: r.description, brand: r.brand, model: r.model, specification: r.specification, qty: r.qty, unit: r.unit,
    unit_price: r.unit_price, labour: r.labour, install: r.install, commissioning: r.commissioning, amount: r.amount, country_of_origin: r.country_of_origin,
    notes: r.notes, spec: r.spec || null, spec_source: r.spec_source || null };
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
  // country_of_origin: read by the sales engineer's review notes (quote_review_notes.ts, ledger 1588), never shown raw by this.
  const COLS = 'quote_id,line_no,description,brand,model,specification,qty,unit,unit_price,labour,install,amount,country_of_origin,notes,spec,spec_source';
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
  // THE REVEAL PERIOD (sales_engineer, 13 Nov 2026; a_paid_reveal_closes_the_request_and_everyone_on_it_is_told.sql): after a
  // paid reveal the other quotations stay revealable while they are valid (inquiries.reveal_open_until), then no longer.
  reveal_period_ended: {
    status: 409,
    en: 'The other quotations on this request can no longer be revealed: their validity after your first reveal has ended. The supplier you revealed is still in your Messages.',
    ar: 'لم يعد بالإمكان كشف العروض الأخرى في هذا الطلب، إذ انتهت مدة صلاحيتها بعد الكشف الأول. ويبقى المورّد الذي كشفتَ عنه في رسائلك.',
  },
  quote_on_hold: {
    status: 409,
    en: 'This quote is on hold: the supplier has not stated every detail your request needs, so we are asking them for it. It is not ready to reveal yet.',
    ar: 'هذا العرض معلّق: لم يذكر المورّد كل التفاصيل التي يحتاجها طلبك، ونحن نطلبها منه. لا يمكن كشفه بعد.',
  },
  // THE ACCOUNTANT'S SCREEN BEFORE MONEY MOVES (29 Sep 2026, founder ledger 1018): a high-severity fraud flag on
  // the customer or the supplier holds the reveal for review. Nobody is banned and nothing is charged; the
  // customer is also e-mailed by customer_support, and again when the hold is released.
  under_review: {
    status: 409,
    en: 'Before a supplier is revealed we run a routine check on the accounts involved, and this reveal is waiting for a person to look at it. You have not been charged. We will e-mail you as soon as you can reveal.',
    ar: 'قبل كشف أي مورّد نُجري تحققًا اعتياديًا على الحسابات المعنية، وهذا الكشف بانتظار مراجعة أحد موظفينا. لم يُخصم منكم أي مبلغ، وسنراسلكم بالبريد الإلكتروني فور إتاحة الكشف.',
  },
  // A TRADE UNDER THE FLOOR IS NEVER A PAID REVEAL (founder ledger 1614; public.fn_trade_reveal_allowed): fewer than 5 verified
  // suppliers left in the request's trade means the comparison it would pay to act on is not the one the T&C describe.
  trade_below_floor: {
    status: 409,
    en: 'Requests in this trade are paused while we onboard more verified suppliers, so a supplier cannot be revealed on it right now. You have not been charged, and your quotes are kept.',
    ar: 'أوقفنا الطلبات في هذا التخصص مؤقتًا ريثما نسجّل مزيدًا من الموردين المعتمدين، لذلك لا يمكن كشف مورّد فيه الآن. لم يُخصم منكم أي مبلغ، وعروضكم محفوظة.',
  },
  // AN OPEN SANCTIONS-SCREENING HIT ON EITHER PARTY (16 Nov 2026, sanctioned.ts screeningOpen): the party is frozen until
  // the CEO decides, within a day. No reason is stated (a screening is never explained to a third party, and telling the
  // party itself would tip it off); what is said is true: nothing is charged and the reveal waits.
  compliance_review: {
    status: 409,
    en: 'This reveal is paused while we complete a routine account check. Please try again later.',
    ar: 'هذا الكشف متوقف مؤقتًا ريثما نُكمل تحققًا اعتياديًا من الحساب. يُرجى المحاولة لاحقًا.',
  },
  // THE SUPPLIER'S LIVE STANDING (sales_engineer, 16 Nov 2026; fn_reveal_standing in
  // a_supplier_can_say_not_for_me_and_is_never_stopped_without_being_told.sql). A customer is told before paying, never after.
  // 'supplier_away' is written with his date by refuseAway below; these two have no variable part.
  supplier_not_revealable: {
    status: 409,
    en: 'This supplier cannot take on work right now (their account or trade licence is not in order), so they cannot be revealed. You have not been charged; please choose another quote.',
    ar: 'لا يستطيع هذا المورّد قبول أعمال في الوقت الحالي (حسابه أو رخصته التجارية ليست سارية)، لذلك لا يمكن كشفه. لم يُخصم منكم أي مبلغ، ويُرجى اختيار عرض آخر.',
  },
  figure_unconfirmed: {
    status: 409,
    en: 'This quote\'s total is far from the other quotes on your request, so we have asked the supplier to confirm it before you pay anything. You have not been charged. Please try again later, or choose another quote.',
    ar: 'إجمالي هذا العرض بعيد جدًا عن بقية العروض على طلبك، لذلك طلبنا من المورّد تأكيده قبل أن تدفعوا أي مبلغ. لم يُخصم منكم شيء. يُرجى المحاولة لاحقًا، أو اختيار عرض آخر.',
  },
  account_sanctioned: {
    status: 403,
    en: 'This supplier account is permanently closed and cannot be revealed.',
    ar: 'حساب هذا المورّد مغلق نهائيًا ولا يمكن كشفه.',
  },
};

const fmtDate = (d: string, lang: 'en' | 'ar') => {
  const t = Date.parse(d + 'T00:00:00Z');
  if (!Number.isFinite(t)) return null;
  return new Date(t).toLocaleDateString(lang === 'ar' ? 'ar-AE-u-nu-latn' : 'en-GB', { day: 'numeric', month: lang === 'ar' ? 'long' : 'short', year: 'numeric', timeZone: 'UTC' });
};
/** The supplier is away: "back on <date>" when he set one, otherwise paused with no date. Never charged. */
export function refuseAway(backOn: string | null | undefined): Refusal {
  const en = backOn ? fmtDate(String(backOn), 'en') : null, ar = backOn ? fmtDate(String(backOn), 'ar') : null;
  return { ok: false, status: 409, code: 'supplier_away', error: 'supplier_away',
    message: en ? `This supplier is away and back on ${en}. You have not been charged: you can reveal them from that date, or choose another quote.`
      : 'This supplier has paused their work for now, so they cannot be revealed. You have not been charged; please choose another quote.',
    message_ar: ar ? `هذا المورّد غائب ويعود في ${ar}. لم يُخصم منكم أي مبلغ، ويمكنكم كشفه ابتداءً من ذلك التاريخ أو اختيار عرض آخر.`
      : 'أوقف هذا المورّد عمله مؤقتًا، لذلك لا يمكن كشفه الآن. لم يُخصم منكم أي مبلغ، ويُرجى اختيار عرض آخر.' };
}

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
  if (!q || !isLiveQuote(q.status)) return refuse('quote_not_found');
  // rfq_no and summary travel with the row because the callers print them (the Stripe line item's
  // reference, the supplier's notice); one read, not three.
  const { data: inq } = await admin.from('inquiries').select('id,customer_id,status,category,spec,rfq_no,summary,reveal_open_until').eq('id', q.inquiry_id).maybeSingle();
  if (!inq || String(inq.customer_id) !== String(opts.customerId)) return refuse('not_your_inquiry');
  // 'revealed' and 'completed' are NOT closed: a customer may reveal a second supplier on a job
  // they already revealed or hired on. Cancelled and closed are the end of the request.
  if (['cancelled', 'closed'].includes(String(inq.status || ''))) return refuse('inquiry_closed');
  const { data: existing } = await admin.from('transactions').select('id').eq('quote_id', qid).maybeSingle();
  const already = !!existing;
  // a quotation already paid for is always shown again; ANOTHER one only while the request's reveal period runs
  if (!already && inq.reveal_open_until && Date.parse(String(inq.reveal_open_until)) <= Date.now()) return refuse('reveal_period_ended');
  // Sanctions bite even on an already-paid reveal: instruction 516 is "never shown to a customer".
  if (await sanctionedLead(admin, q.supplier_id)) return refuse('account_sanctioned');
  // Frozen pending the CEO's sanctions decision, on either side, paid or not (the freeze is on dealing with the party).
  if (await screeningOpen(admin, { leadId: q.supplier_id, customerId: opts.customerId })) return refuse('compliance_review');
  // A quote already paid for is never re-held: the customer owns that disclosure.
  if (!already) {
    const held = heldQuoteIds([{ quote: q, items: (await itemsByQuote(admin, [qid]))[qid] || [] }], inq.category ?? null, inq.spec);
    if (held.has(qid)) return refuse('quote_on_hold');
    // The trade's verified suppliers at the moment of payment (ledger 1614). FAIL CLOSED like the screen below: an
    // unreadable answer is a 500 from the caller, never a charge.
    const tr = await admin.rpc('fn_trade_reveal_allowed', { p_inquiry: inq.id });
    if (tr?.error) throw new Error('fn_trade_reveal_allowed failed: ' + JSON.stringify(tr.error));
    if (tr?.data && (tr.data as { allowed?: boolean }).allowed === false) return refuse('trade_below_floor');
    // THE SUPPLIER'S LIVE STANDING (16 Nov 2026, SUPPLIER hole 3, CUSTOMER hole 8): away (with the date he is back), his account
    // or licence not in order, or a total far from its peers that he has not confirmed (he is asked once, in SQL; after the floor, which writes nothing). FAIL CLOSED
    // like the screens below: an unreadable standing is a 500 from the caller, never a charge.
    const st = await admin.rpc('fn_reveal_standing', { p_quote: qid });
    if (st?.error) throw new Error('fn_reveal_standing failed: ' + JSON.stringify(st.error));
    const outcome = (st?.data as { outcome?: string; back_on?: string | null } | null)?.outcome;
    if (outcome === 'away') return refuseAway((st.data as { back_on?: string | null }).back_on ?? null);
    if (outcome === 'not_revealable') return refuse('supplier_not_revealable');
    if (outcome === 'figure_unconfirmed') return refuse('figure_unconfirmed');
    // Last, because it writes: the accountant re-screens both parties now and records a hold or a note
    // (scripts/sql/the_accountant_screens_every_party_and_holds_money_for_review_before_it_moves.sql).
    // FAIL CLOSED, like the sanctions read: an unreadable screen is a 500 from the caller, never a charge.
    const screen = await admin.rpc('fn_accountant_money_screen', {
      p_move: 'reveal', p_ref: qid, p_customer: String(opts.customerId), p_supplier: q.supplier_id ?? null });
    if (screen?.error) throw new Error('fn_accountant_money_screen failed: ' + JSON.stringify(screen.error));
    if (screen?.data?.hold === true) return refuse('under_review');
  }
  return { ok: true, quote: q, inquiry: inq, already_revealed: already };
}
