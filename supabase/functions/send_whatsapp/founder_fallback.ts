// The founder is never left in the queue: the email fallback (split out of index.ts, 9 Nov 2026; a pure move).
import { admin } from './client.ts';
import { logThrottled } from './run_log.ts';

// THE FOUNDER IS NEVER LEFT IN THE QUEUE (18 Sep 2026). WhatsApp can stop delivering for reasons
// that have nothing to do with this code — a template rejected or paused at Meta, a quality
// throttle, a hard Twilio rejection — and a CRITICAL alert must not depend on one channel that can
// stall silently. Every path below that cannot send a founder-addressed row calls this instead of
// requeueing it. fn_wa_founder_alert_fallback confirms the email twin or queues one carrying the
// row's own `kind` (so a10_notifications_founder_mail_policy admits it rather than dropping it),
// then marks THIS row 'skipped' with the reason. It returns null for a row that is not the
// founder's, so the caller falls through to the behaviour it always had.
export type WaRow = { id: number; type?: string|null; to_phone?: string|null; to_role?: string|null;
               subject?: string|null; body?: string|null; created_at?: string|null; lang?: string|null; lead_id?: number|null;
               attachments?: unknown };
// isFounderRow decides the CAP EXEMPTIONS only. Who the founder is for the fallback is decided in
// one place — fn_wa_founder_alert_fallback, which uses a10's own test (to_role, or to_phone equal
// to admin_mfa_phone) — so this function does not pre-filter and the two cannot disagree about a
// row. fn_notify_founder always stamps to_role='founder', so the two agree for every writer today.
export const isFounderRow = (n: WaRow) => ['founder','admin','owner'].includes(String(n.to_role || ''));
export async function founderFallback(n: WaRow, reason: string): Promise<string|null> {
  try {
    const { data, error } = await admin.rpc('fn_wa_founder_alert_fallback',
      { p_notification_id: n.id, p_reason: String(reason).slice(0, 300) });
    if (error) {
      // The fallback itself failing is the one thing that must never be quiet: the row stays queued
      // so the next tick retries it, and the failure is logged rather than swallowed.
      await logThrottled('founder_fallback_broken', 30, 'error', { notification: n.id }, 'founder WhatsApp fallback FAILED (the alert is still queued): '
        + String(error.message || error).slice(0, 250));
      return null;
    }
    const out = (data as { ok?: boolean; outcome?: string } | null);
    // 'already_handled' means an overlapping run claimed the row first: it is terminal and must NOT
    // be written again by this caller, so it counts as handled even though ok is false.
    if (out?.ok || out?.outcome === 'already_handled') return String(out.outcome);
    return null;
  } catch (e) {
    await logThrottled('founder_fallback_broken', 30, 'error', { notification: n.id }, 'founder WhatsApp fallback threw (the alert is still queued): '
      + String((e as Error)?.message || e).slice(0, 250));
    return null;
  }
}
