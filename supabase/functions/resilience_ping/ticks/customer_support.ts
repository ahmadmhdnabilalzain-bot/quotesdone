// resilience_ping ticks owned by the customer_support seat. Moved out of index.ts unchanged (9 Nov 2026);
// the order they run in is still set in index.ts (STEP_RUN).
import { heartbeatDeps } from '../../_shared/think.ts';
import { renderPdfAndAttach } from './ceo.ts';
import { admin } from '../shared.ts';

// SUPPORT'S RATING REQUEST HANGS HERE FOR THE SAME REASON THE DIGEST DOES.
// The founder, 9 Sep 2026: "support should send an email after 3 weeks from the reveal date."
// fn_support_request_ratings_due is idempotent on notifications_rating_request_uidx, so calling it
// every 15 minutes enqueues each reveal's ask exactly once and returns asked:0 the rest of the time.
// Swallowed the same way: a rating survey must never take the watchdog down.
export async function ratingTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_support_request_ratings_due');
    if (error) return { ok: false, error: error.message };
    return data;
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE SEAT CLOCKS (22 Sep 2026, ceo; founder instruction 583). Complaint deadlines, requests short of
// 3 quotes, the 7-day reveal outcome check and time to first support reply, each on its owning seat
// (complaints_quotes_reveals_and_support_replies_each_run_on_a_clock.sql). It queues mail, so it must
// run before the outbox drain, which is place=last.
export async function seatClocksTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_seat_clocks_tick');
    if (error) return { ok: false, error: error.message };
    return data;
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

export async function supportVoiceTick(): Promise<unknown> {
  const { writeOwedDutyMessages, liveVoiceIO } = await import('../_shared/duty_voice.ts');
  // heartbeatDeps: any embedding this step ever asks for runs in embed_ml, never in this worker (2 s CPU cap, #1678)
  return await writeOwedDutyMessages(liveVoiceIO(admin, heartbeatDeps(admin)), 3);
}

// THE FOUNDER'S 18:00 SUPPLIER LIST (24 Sep 2026, customer_support). fn_customer_support_campaign_list_tick
// builds, by code, the list of suppliers the campaign invites on the next sending day from the sender's own
// fn_supplier_invite_candidates, with the day's counts; this renders it on the company template and
// fn_customer_support_campaign_list_attach mails it (founder_mail_policy supplier_campaign_daily_list). A failed
// render is retained and retried next beat. scripts/sql/the_founder_sees_tomorrows_supplier_invitations_at_six.sql
export async function supportCampaignListTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_customer_support_campaign_list_tick');
    if (error) return { ok: false, error: error.message };
    // deno-lint-ignore no-explicit-any
    const t = data as any;
    if (!t?.pdf_pending || !t?.pdf_blocks || !t?.id) return t;
    return await renderPdfAndAttach(t, 'customer_support/supplier_list', 'supplier_list', false, 'fn_customer_support_campaign_list_attach');
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}
