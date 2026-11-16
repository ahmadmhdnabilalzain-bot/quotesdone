// accountant — what other seats handed this one: handoffs, complete_handoff.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (the 1,715-line index.ts split into modules, a pure move).
import { type ActionCtx, J, admin, run } from '../context.ts';
import { isCeoOrder, reportOrClose } from '../../_shared/order_report.ts';

export async function handoffActions(c: ActionCtx): Promise<Response | undefined> {
  const { body, action } = c;
    // ── HANDOFFS ───────────────────────────────────────────────────────────────────────────────
    // What the sales engineer and the CEO handed this seat and it has not closed, and the door to
    // close one with evidence (a remediation that needed a person, a Stripe fix done by hand).
    if (action === 'handoffs') {
      const { data } = await admin.from('agent_actions').select('id,status,title,detail,evidence,created_at')
        .eq('kind', 'handoff').eq('agent', 'accountant').neq('status', 'done').order('id').limit(100);
      return J({ ok: true, seat: 'accountant', open: data || [] });
    }
    if (action === 'complete_handoff') {
      const { data: h } = await admin.from('agent_actions').select('id,agent,detail').eq('id', Number(body.id)).eq('kind', 'handoff').maybeSingle();
      if (!h || h.agent !== 'accountant') return J({ error: 'not_this_seats_handoff' }, 404);
      // a CEO order is REPORTED with what was done (fn_seat_reports_done), any other hand-over closes as before
      // (ceo, 15 Nov 2026, third review item 3; _shared/order_report.ts)
      const r = await reportOrClose((fn, args) => admin.rpc(fn, args), 'accountant', h, body);
      if (r.status !== 200) return J(r.body, r.status);
      await run('complete_handoff', 'ok', { handoff_id: Number(body.id), reported: isCeoOrder(h) });
      return J(r.body);
    }
}
