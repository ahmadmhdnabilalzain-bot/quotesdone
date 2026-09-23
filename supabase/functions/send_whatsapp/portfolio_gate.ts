// THE PORTFOLIO REMINDER'S LAST CHECK (instruction 858; review of #869, 23 Sep 2026).
// Before a supplier_portfolio_incomplete WhatsApp copy leaves, the portfolio is read again. The answer
// FAILS CLOSED: only an explicit "still due" sends. "Complete" cancels the row; an error, an unreadable
// answer or no answer within the deadline HOLDS it queued with the reason, and the drain moves on.
export type PortfolioGate = { action: 'send' } | { action: 'cancel'; reason: string } | { action: 'hold'; reason: string };
// The signal CANCELS the call at the deadline (review of #869): a Promise.race alone stops waiting but
// leaves a hung request running until the database's own statement timeout.
// deno-lint-ignore no-explicit-any
type Rpc = (fn: string, args: Record<string, unknown>, signal?: AbortSignal) => PromiseLike<{ data: any; error: { message?: string } | null }>;

export const PORTFOLIO_GATE_TIMEOUT_MS = 4000;
export const COMPLETED_NOTE = 'cancelled: the supplier completed his portfolio after the email was sent, so this WhatsApp copy would no longer be true';

export async function portfolioGate(rpc: Rpc, leadId: number | null | undefined, timeoutMs = PORTFOLIO_GATE_TIMEOUT_MS): Promise<PortfolioGate> {
  if (!leadId) return { action: 'hold', reason: 'held: the reminder names no supplier, so it cannot be re-checked before sending' };
  let timer: ReturnType<typeof setTimeout> | undefined;
  const abort = new AbortController();
  const deadline = new Promise<'timeout'>((res) => { timer = setTimeout(() => { abort.abort(); res('timeout'); }, timeoutMs); });
  try {
    const r = await Promise.race([Promise.resolve(rpc('fn_supplier_portfolio_reminder_still_due', { p_lead_id: leadId }, abort.signal)), deadline]);
    if (r === 'timeout') return { action: 'hold', reason: `held: the portfolio re-check did not answer within ${timeoutMs} ms; not sent, retried next run` };
    if (r.error) return { action: 'hold', reason: 'held: the portfolio re-check failed (' + String(r.error.message || 'unknown').slice(0, 160) + '); not sent, retried next run' };
    if (r.data === true) return { action: 'send' };
    if (r.data === false) return { action: 'cancel', reason: COMPLETED_NOTE };
    return { action: 'hold', reason: 'held: the portfolio re-check gave no clear answer; not sent, retried next run' };
  } catch (e) {
    return { action: 'hold', reason: 'held: the portfolio re-check threw (' + String((e as Error)?.message || e).slice(0, 160) + '); not sent, retried next run' };
  } finally {
    clearTimeout(timer);
  }
}
