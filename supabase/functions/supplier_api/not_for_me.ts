// not_for_me.ts - THE PORTAL'S DOORS FOR "NOT FOR ME", "I'M AVAILABLE", A TRADE CORRECTION, A FIGURE CONFIRMATION AND GOING ON LEAVE
// (sales_engineer, 16 Nov 2026; agent NOT_FOR_ME; holes SUPPLIER 2, 3, 7, OPERATIONS H8, FAILURES 2, CUSTOMER 8).
// The supplier id always comes from the caller's own JWT (actions/not_for_me.ts), never from the body. Each write is a routine of
// a_supplier_can_say_not_for_me_and_is_never_stopped_without_being_told.sql scoped to that id; the profile removal is the Services
// tab's own writer (removeFromProfile -> servicesSaveRewrite). In the portal one tap IS his confirmation, so a removal he presses
// is proposed and applied in the same call; by e-mail or WhatsApp it waits for his "yes" (_shared/supplier_instruction.ts).
// prevented by: supplier_api/not_for_me.test.ts
import { removeFromProfile } from '../_shared/supplier_instruction.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;
export const NOT_FOR_ME_ACTIONS = ['decline_request', 'say_available', 'standing', 'remove_work', 'correction_decide', 'confirm_quote_figure', 'leave_quotes'] as const;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const strs = (v: unknown, n = 10) => (Array.isArray(v) ? v.map((x) => String(x ?? '').trim()).filter(Boolean).slice(0, n) : []);

export async function notForMe(admin: Admin, sid: number, action: string, body: Record<string, unknown>,
  opts: { remove?: typeof removeFromProfile } = {}): Promise<[number, Record<string, unknown>]> {
  const remove = opts.remove ?? removeFromProfile;
  const rpc = async (fn: string, args: Record<string, unknown>) => {
    const { data, error } = await admin.rpc(fn, args);
    if (error) throw new Error(fn + ': ' + String(error.message ?? error));
    return data as Record<string, unknown>;
  };
  if (action === 'decline_request') {
    const inq = String(body.inquiry_id ?? '');
    if (!UUID.test(inq)) return [400, { ok: false, code: 'bad_request', error: 'Which request?' }];
    // one tap; the reason is optional and in his own words (the weekly review's model reads it)
    const d = await rpc('fn_supplier_declines_request', { p_supplier: sid, p_inquiry: inq, p_reason: body.reason == null ? null : String(body.reason).slice(0, 1000), p_channel: 'portal' });
    if (!d?.ok) return [d?.code === 'not_found' ? 404 : 409, { ...d, error: d?.error ?? d?.code }];
    // the offer to stop that trade: only when it is his and not his last
    return [200, { ...d, offer: d.can_remove_trade ? { trades: [d.trade], label: d.trade_label } : null }];
  }
  if (action === 'say_available') return [200, await rpc('fn_supplier_says_available', { p_supplier: sid, p_channel: 'portal' })];
  if (action === 'standing') return [200, { ok: true, standing: await rpc('fn_supplier_live_standing', { p_supplier: sid }) }];
  if (action === 'remove_work') {
    const p = await rpc('fn_supplier_trade_correction_propose', { p_supplier: sid, p_source: body.from_decline ? 'not_for_me' : 'portal',
      p_trades: strs(body.trades), p_services: strs(body.services, 60), p_why: body.reason == null ? null : String(body.reason).slice(0, 1000),
      p_inquiry: UUID.test(String(body.inquiry_id ?? '')) ? String(body.inquiry_id) : null });
    if (!p?.ok) return [409, { ...p, error: p?.error ?? p?.code }];
    const c = p.correction as { id: number; remove_trades: string[]; remove_services: string[]; labels: string[] };
    const res = await remove(admin, sid, { trades: c.remove_trades ?? [], services: c.remove_services ?? [] });
    await rpc('fn_supplier_trade_correction_decide', { p_id: c.id, p_supplier: sid, p_decision: res.ok ? 'applied' : 'failed', p_channel: 'portal', p_result: res });
    return res.ok ? [200, { ok: true, removed: c.labels }] : [409, { ok: false, code: res.code ?? 'save_failed', error: 'Your services could not be changed just now. Please try again, or edit them under Services.' }];
  }
  if (action === 'correction_decide') {
    const s = await rpc('fn_supplier_live_standing', { p_supplier: sid });
    const c = (s?.open_correction ?? null) as { id: number; remove_trades: string[]; remove_services: string[]; labels: string[] } | null;
    if (!c || Number(body.id) !== Number(c.id)) return [409, { ok: false, code: 'not_open', error: 'This suggestion has already been answered.' }];
    if (body.decision === 'keep') {
      await rpc('fn_supplier_trade_correction_decide', { p_id: c.id, p_supplier: sid, p_decision: 'declined', p_channel: 'portal', p_result: null });
      return [200, { ok: true, kept: c.labels }];
    }
    if (body.decision !== 'apply') return [400, { ok: false, code: 'bad_decision' }];
    const res = await remove(admin, sid, { trades: c.remove_trades ?? [], services: c.remove_services ?? [] });
    await rpc('fn_supplier_trade_correction_decide', { p_id: c.id, p_supplier: sid, p_decision: res.ok ? 'applied' : 'failed', p_channel: 'portal', p_result: res });
    return res.ok ? [200, { ok: true, removed: c.labels }] : [409, { ok: false, code: res.code ?? 'save_failed' }];
  }
  if (action === 'confirm_quote_figure') {
    const q = String(body.quote_id ?? '');
    if (!UUID.test(q)) return [400, { ok: false, code: 'bad_request' }];
    const d = await rpc('fn_supplier_confirms_quote_figure', { p_supplier: sid, p_quote: q, p_channel: 'portal' });
    return [d?.ok ? 200 : 404, d];
  }
  if (action === 'leave_quotes') {
    // GOING ON LEAVE (SUPPLIER hole 3): keep his live quotations (the customer may reveal him when he is back, and is told the date
    // before paying), or withdraw them: only his own, only those still a draft or with the customer and never revealed.
    const live = (await rpc('fn_supplier_live_quotes', { p_supplier: sid })) as unknown as { quote_id: string }[] | null;
    if (body.decision === 'keep') return [200, { ok: true, kept: (live ?? []).length }];
    if (body.decision !== 'withdraw') return [400, { ok: false, code: 'bad_decision' }];
    const ids = (live ?? []).map((x) => x.quote_id);
    if (!ids.length) return [200, { ok: true, withdrawn: 0 }];
    const { data: done, error } = await admin.from('quotes').update({ status: 'withdrawn' }).eq('supplier_id', sid).in('id', ids).in('status', ['draft', 'submitted']).select('id');
    if (error) return [500, { ok: false, code: 'could_not_withdraw' }];
    return [200, { ok: true, withdrawn: (done ?? []).length }];
  }
  return [400, { ok: false, code: 'unknown_action' }];
}
