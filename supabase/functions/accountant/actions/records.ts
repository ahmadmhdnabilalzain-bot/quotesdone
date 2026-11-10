// accountant — the outcomes only a person can record: filing_outcome, court_step, charge_resolve.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (the 1,715-line index.ts split into modules, a pure move).
import { type ActionCtx, J, admin, run } from '../context.ts';

export async function recordActions(c: ActionCtx): Promise<Response | undefined> {
  const { body, action } = c;
    // ── The two outcomes only a person can record ─────────────────────────────────────────────────
    if (action === 'filing_outcome') {
      const { data, error } = await admin.rpc('fn_accountant_record_filing_outcome', {
        p_due_id: Number(body.due_id), p_outcome: String(body.outcome || ''), p_reference: body.reference ?? null });
      if (error) return J({ ok: false, error: error.message }, 400);
      await run('filing_outcome', 'ok', { due_id: Number(body.due_id) });
      return J(data);
    }
    // What happened in court on a supplier charge (duty 3 of the five further duties): filed, order_issued,
    // order_served, grievance_filed, recovered or withdrawn, on the day it happened.
    if (action === 'court_step') {
      const { data, error } = await admin.rpc('fn_accountant_record_court_step', {
        p_due_id: Number(body.due_id), p_step: String(body.step || ''), p_on: body.on ?? null, p_reference: body.reference ?? null });
      if (error) return J({ ok: false, error: error.message }, 400);
      await run('court_step', 'ok', { due_id: Number(body.due_id), step: String(body.step || '') });
      return J(data);
    }
    if (action === 'charge_resolve') {
      const { data, error } = await admin.rpc('fn_accountant_charge_audit_resolve', {
        p_transaction_id: String(body.transaction_id || ''), p_resolution: String(body.resolution || '') });
      if (error) return J({ ok: false, error: error.message }, 400);
      await run('charge_resolve', 'ok', { transaction_id: String(body.transaction_id || '') });
      return J(data);
    }
}
