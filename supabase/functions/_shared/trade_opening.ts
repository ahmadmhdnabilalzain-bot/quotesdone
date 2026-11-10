// trade_opening — A TRADE OPENS TO CUSTOMERS AS SOON AS IT HAS ENOUGH VERIFIED SUPPLIERS (10 Nov 2026, ceo with sales_engineer;
// founder ledger 1614, standing). The customer doors ask the database one question before a request goes out:
// public.fn_trade_waitlist_join (scripts/sql/a_trade_opens_to_customers_as_soon_as_it_has_enough_verified_suppliers.sql).
//   * 'open'          every taxonomy trade the request names is open: it proceeds exactly as before;
//   * 'unclassified'  it names no taxonomy trade ('general'): it proceeds as before (no trade to count coverage on);
//   * 'not_open'      a trade is still short of verified suppliers: the customer is put on that trade's waiting list and
//                     told so, honestly, in their language; the database tells them again when the trade opens.
// The words are the database's (fn_trade_waitlist_message), in English and Arabic, so the portal, WhatsApp and the notice
// can never say three different things.
//
// AN OUTAGE OF THE QUESTION IS NOT A REFUSAL. A failed call (the routine not yet applied, a timeout) answers 'unknown' and
// the caller posts as it did before this build, with a finding for the it_engineer: refusing every request because a
// read failed would close the whole marketplace on a fault. The reveal side does the opposite (reveal_guard.ts): money
// never moves on an unreadable answer.
// prevented by: supabase/functions/_shared/trade_opening.test.ts
type Rpc = (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: unknown; error?: { message: string } | null }>;

export type TradeGate = {
  state: 'open' | 'not_open' | 'unclassified' | 'unknown';
  codes: string[];
  closed: { code: string; verified: number; open_at: number }[];
  message?: string; message_en?: string; message_ar?: string;
  waitlisted?: boolean; error?: string;
};

/** The digits-only WhatsApp number the waiting list keys on ('whatsapp:+9715...' -> '+9715...'). */
export function waPhone(from: string): string {
  const d = String(from || '').replace(/^whatsapp:/i, '').replace(/[^0-9+]/g, '');
  return d ? (d.startsWith('+') ? d : '+' + d) : '';
}

/** Ask the door's question and, when the trade is not open, record the customer on its waiting list (one row per trade). */
export async function joinIfNotOpen(db: { rpc: Rpc }, o: { slugs: string[]; channel: 'portal' | 'whatsapp'; customerId?: string | null;
  phone?: string | null; lang: 'en' | 'ar'; intakeId?: string | null }): Promise<TradeGate> {
  const slugs = [...new Set((o.slugs || []).map((s) => String(s || '').trim()).filter(Boolean))].slice(0, 8);
  if (!slugs.length) return { state: 'unclassified', codes: [], closed: [] };
  try {
    const { data, error } = await db.rpc('fn_trade_waitlist_join', { p_slugs: slugs, p_channel: o.channel, p_customer: o.customerId ?? null,
      p_phone: o.phone ?? null, p_lang: o.lang, p_intake: o.intakeId ?? null });
    if (error || !data || typeof data !== 'object') return { state: 'unknown', codes: [], closed: [], error: error?.message ?? 'no answer' };
    const g = data as Record<string, unknown>;
    const state = (['open', 'not_open', 'unclassified'] as const).find((s) => s === g.state) ?? 'unknown';
    return { state, codes: Array.isArray(g.codes) ? g.codes.map(String) : [], closed: Array.isArray(g.closed) ? g.closed as TradeGate['closed'] : [],
      message: g.message ? String(g.message) : undefined, message_en: g.message_en ? String(g.message_en) : undefined,
      message_ar: g.message_ar ? String(g.message_ar) : undefined, waitlisted: g.waitlisted === true };
  } catch (e) {
    return { state: 'unknown', codes: [], closed: [], error: String((e as Error)?.message ?? e) };
  }
}

/** The portal's answer for a request whose trade is not open yet: a 409 carrying both languages (portalText errText). */
export function notOpenAnswer(g: TradeGate): { body: Record<string, unknown>; status: number } {
  return { status: 409, body: { ok: false, error: 'trade_not_open', code: 'trade_not_open', waitlisted: g.waitlisted === true,
    trades: g.closed.map((c) => c.code), message: g.message_en ?? g.message ?? '', message_ar: g.message_ar ?? g.message ?? '' } };
}
