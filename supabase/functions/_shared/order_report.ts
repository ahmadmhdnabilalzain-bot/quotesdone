// _shared/order_report.ts — a seat closes a hand-over from its own operator door; a CEO ORDER is REPORTED, not just closed
// (ceo, 15 Nov 2026; third review of the CEO pool branch, item 3: "No code anywhere calls fn_seat_reports_done ... so every
// fix order comes back as late and repeats").
//
// fn_seat_reports_done (scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql) closes the order only with
// a sentence saying what was done, writes it on the CEO's decision, files the finding's sender its next step (re-verify) and,
// for a supply order, lets the CEO's loop measure the outcome beside the report. Any other hand-over closes as before
// (fn_seat_handoff_complete with the caller's evidence). Used by the accountant's and the sales engineer's complete_handoff
// and the marketing seat's report_order; customer support has no edge function: its orders close by their measure
// (fn_ceo_grows_supply) or with their finding.
// prevented by: supabase/functions/_shared/order_report.test.ts
export type RpcResult = { data: unknown; error: { message?: string } | null };
export type Rpc = (fn: string, args: Record<string, unknown>) => PromiseLike<RpcResult>;
export type Handoff = { id: number; agent: string; detail?: Record<string, unknown> | null };

/** The sentence a seat reports an order with: body.report, else the evidence's reply, note or outcome. */
export function orderReportText(body: Record<string, unknown>): string {
  const ev = (body?.evidence && typeof body.evidence === 'object' ? body.evidence : {}) as Record<string, unknown>;
  for (const v of [body?.report, ev.reply, ev.note, ev.outcome]) {
    const s = typeof v === 'string' ? v.trim() : '';
    if (s) return s.slice(0, 600);
  }
  return '';
}

export function isCeoOrder(h: Handoff): boolean {
  return String(h?.detail?.type ?? '') === 'ceo.order';
}

/** Close or report: { status, body } for the door to answer with. */
export async function reportOrClose(rpc: Rpc, seat: string, h: Handoff, body: Record<string, unknown>): Promise<{ status: number; body: unknown }> {
  if (isCeoOrder(h)) {
    const report = orderReportText(body);
    if (report.length < 12) return { status: 400, body: { ok: false, error: 'report_required', detail: 'a CEO order closes with what was done: body.report, 12 characters or more' } };
    const { data, error } = await rpc('fn_seat_reports_done', { p_handoff_id: h.id, p_seat: seat, p_report: report });
    if (error) return { status: 400, body: { ok: false, error: error.message ?? String(error) } };
    const d = (data || {}) as Record<string, unknown>;
    return d.ok === false ? { status: 400, body: d } : { status: 200, body: { ...d, reported: true } };
  }
  const { data, error } = await rpc('fn_seat_handoff_complete', { p_id: h.id, p_evidence: (body?.evidence ?? {}) as unknown });
  if (error) return { status: 400, body: { ok: false, error: error.message ?? String(error) } };
  return { status: 200, body: data };
}
