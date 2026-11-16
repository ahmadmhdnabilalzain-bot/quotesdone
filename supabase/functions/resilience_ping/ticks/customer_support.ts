// resilience_ping ticks owned by the customer_support seat. Moved out of index.ts unchanged (9 Nov 2026);
// the order they run in is still set in index.ts (STEP_RUN).
import { heartbeatDeps, type ThinkDeps } from '../../_shared/think.ts';
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
  const { writeOwedDutyMessages, liveVoiceIO } = await import('../../_shared/duty_voice.ts');
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

// THE CASE SUMMARY A REPLY OWES (customer_support, 12 Nov 2026; founder ruling 1635: "After each exchange the agent records a
// summary of the case"). The summary is written after each WhatsApp reply inside the turn's worker; a worker killed first leaves
// it owed. This writes the owed ones from the conversation (_shared/support_case_memory.ts catchUpOwedSummaries), at most 3 a
// beat, each one case_summary model call. scripts/sql/a_case_summary_owed_after_a_reply_is_written_by_the_next_beat.sql
export async function caseCatchupTick(): Promise<unknown> {
  try {
    const { catchUpOwedSummaries } = await import('../../_shared/support_case_memory.ts');
    const since = () => new Date(Date.now() - 86_400_000).toISOString();
    // heartbeatDeps, never defaultDeps: an embedding this step asks for runs in embed_ml, not in this worker (2 s CPU cap, #1678).
    // Measured 12 Nov 2026 on main 2f6074958: held_replay_keeps_gte_out_of_the_worker.test.ts failed on this line after #1953.
    const whatsapp = await catchUpOwedSummaries(heartbeatDeps(admin), async (tail) => {
      if (!/^[0-9]{9}$/.test(tail)) return null;
      const { data, error } = await admin.from('wa_messages').select('inbound,reply,created_at').like('wa_from', '%' + tail)
        .gte('created_at', since()).order('created_at', { ascending: true }).limit(40);
      return error || !Array.isArray(data) ? null : (data as { inbound: string | null; reply: string | null }[]).map((r) => ({ inbound: String(r.inbound ?? ''), reply: String(r.reply ?? '') }));
    }, 3);
    return { ...(whatsapp as Record<string, unknown>), email: await emailCaseCatchup(heartbeatDeps(admin), 3) };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE E-MAIL CASE SUMMARY A REPLY OWES (customer_support, 16 Nov 2026). email_triage writes it after the reply, past the response
// (recordCaseExchange, never awaited), so a worker ended first leaves it owed exactly as on WhatsApp, and the beat above read only
// WhatsApp. public.fn_support_case_email_summaries_owed lists the owed e-mail cases with the exchange itself (their last answered
// mail and the reply that went); the same summariseExchange writes it. At most `limit` a beat, one case_summary call each.
// prevented by: resilience_ping/email_case_catchup.test.ts
type Summarise = (deps: ThinkDeps, o: { memory: { ref: string; summaryText: string; version: number; profile: number }; theirMessage: string; ourReply: string; seat?: string }) => Promise<{ ok: boolean; reason?: string }>;
export async function emailCaseCatchup(deps: ThinkDeps, limit = 3, summarise?: Summarise): Promise<{ ok: boolean; owed: number; written: number; failed: number; reason?: string }> {
  try {
    const write = summarise ?? (await import('../../_shared/support_case_memory.ts')).summariseExchange;
    const { data, error } = await deps.rpc('fn_support_case_email_summaries_owed', { p_limit: limit });
    if (error) return { ok: false, owed: 0, written: 0, failed: 0, reason: String(error.message ?? error).slice(0, 200) };
    // deno-lint-ignore no-explicit-any
    const owed = (Array.isArray(data) ? data : []) as any[];
    let written = 0, failed = 0;
    for (const c of owed) {
      const their = String(c.their_message ?? '').trim(), ours = String(c.our_reply ?? '').trim();
      if (!their || !ours) continue;
      const r = await write(deps, { memory: { ref: String(c.case_ref), summaryText: String(c.summary_text ?? ''), version: Number(c.summary_version ?? 0), profile: Number(c.profile ?? 0) },
        theirMessage: their, ourReply: ours, seat: 'customer_support' });
      if (r.ok) written++; else failed++;
    }
    return { ok: failed === 0, owed: owed.length, written, failed };
  } catch (e) { return { ok: false, owed: 0, written: 0, failed: 0, reason: 'threw: ' + String((e as Error)?.message || e).slice(0, 200) }; }
}
