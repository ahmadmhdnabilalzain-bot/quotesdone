// holding.ts - the WhatsApp holding line and typing indicator (it_engineer, 11 Nov 2026, founder ruling 1636).
// One hook, in say.ts before the model is asked: armWaHolding. The typing indicator goes at once; the holding line goes
// HOLDING_AFTER_MS after the person's last message if no reply is ready by then (_shared/holding_notice.ts), once per turn.
// The reply being ready settles it (say.ts adopt), any reply that leaves through sendWa (replies.ts) answers it, and the turn's
// end settles it (index.ts finally).
//
// ONCE PER PERSON PER QUIET WINDOW, AND READ FROM THEIR HISTORY FIRST (ruling 1631; final audit 12 Nov 2026, W2). Before it is
// sent, the person's holding lines of the last day are read from notifications: one inside HOLDING_QUIET_MIN means this turn
// sends none; otherwise the wording is one they were not given last time. The send is CLAIMED first: one row per person per
// window under a unique key (holdingClaimKey), so two turns due together cannot both send (review of 12 Nov 2026). Every holding line sent, captured or failed is a
// notifications row (type wa_holding_notice), so it is in the person's history and in the outbox's own counts. A history that
// cannot be read sends nothing: the line is a courtesy, a repeat is the harm it must not do.
// WHY THE AUDIT FOUND IT ON EVERY TURN: the row named requested_by 'wa_inbound', trigger a05 (fn_notifications_sender_of_record)
// refuses any requester that is not an active seat, and the error was discarded, so the history never held one (0 rows ever,
// 33 refusals in the Postgres log of 11 Nov). The requester is customer_support (the seat that sends it), a refused write is now
// an it_engineer finding (the requester is now 'platform', HOLDING_REQUESTER says why), and the row names no to_role: trigger a03 judges a customer's or supplier's row by their CONFIRMED
// number and would mark a line already sent to the number writing to us as 'skipped'.
// It is SENT here, inside the turn, not drained by send_whatsapp: its shelf life is a few seconds, and a holding line a
// flush delivered minutes later (after the answer) would be worse than none. So the row is written with its outcome and is
// never 'queued'; a failed send is recorded 'cancelled' with its reason and is never retried. A row the rehearsal guard (zzz_notifications_demo_guard)
// turns into 'held' on insert is set back to the outcome that happened, so a release can never send it later.
// NEVER FOLLOWED BY SILENCE: a turn that sent the line and then ends with no reply files the turn for the model's re-ask
// (index.ts finally, say.ts heldTurn), which answers within about a minute.
// prevented by: wa_inbound/holding.test.ts
import { armHolding, holdingDelay, holdingLine, HOLDING_QUIET_MIN, registerHolding, type Holding } from '../_shared/holding_notice.ts';
import { FIXTURE_CAPTURE_NOTE, isDemoPhone } from '../_shared/demo_identity.ts';
import { sendTypingIndicator, sendWhatsApp } from '../_shared/wa_send.ts';
import { admin, itFinding, sec } from './shared.ts';
import type { WaTurn } from './turn.ts';

export const HOLDING_TYPE = 'wa_holding_notice';
/** The requester trigger a05 accepts (an active seat, or 'platform'). 'platform' (review round 2, 12 Nov 2026, read from the
 *  live triggers): a seat as requester makes z90_every_send_is_tracked file a delivery.request handoff for every holding line,
 *  and fn_customer_support_delivery_watch then reports each one to the CEO as 'sent_unconfirmed' (the row has no provider id).
 *  z90 skips 'platform', a05 accepts it, and the sender stays customer_support (notifications_sender_is_customer_support). */
export const HOLDING_REQUESTER = 'platform';
/** The statuses that mean the person got (or, on a fixture number, would have got) a holding line; 'skipped' is a claim whose
 *  outcome is not written yet (counted, so a claim that died mid-send never lets a second line through). */
const WENT = ['sent', 'sending', 'suppressed', 'skipped'];

// deno-lint-ignore no-explicit-any
type Admin = any;
export interface HoldingDeps {
  admin: Admin;
  setting: (k: string) => Promise<string>;
  send: (to: string, text: string) => Promise<{ ok: boolean; err?: string }>;
  typing: (to: string, sid: string) => Promise<{ ok: boolean; err?: string }>;
  finding: (key: string, title: string, evidence: Record<string, unknown>) => Promise<unknown>;
  now?: () => number;
}
// NOT through replies.ts sendWa (review round 2, 12 Nov 2026): sendWa counts a delivered send as the ANSWER to the holding
// line, so the line answered itself and a turn that then died was never re-asked. The line goes straight to Twilio.
/** The live transport of the holding line: Twilio's REST API through _shared/wa_send.ts, never replies.ts sendWa. */
export const liveSend = (db: Admin) => (to: string, text: string) => sendWhatsApp(db, to, text);
const liveDeps: HoldingDeps = { admin, setting: sec, send: liveSend(admin), typing: (to, sid) => sendTypingIndicator(admin, to, sid),
  finding: (key, title, evidence) => itFinding(key, title, evidence) };

/** This person's holding lines of the last day, newest first; null when the history cannot be read. */
async function earlierLines(d: HoldingDeps, phone: string, nowMs: number): Promise<{ id: number; body: string; status: string; created_at: string }[] | null> {
  try {
    const { data, error } = await d.admin.from('notifications').select('id,body,status,created_at').eq('type', HOLDING_TYPE).eq('channel', 'whatsapp')
      .eq('to_phone', phone).gte('created_at', new Date(nowMs - 86_400_000).toISOString()).order('created_at', { ascending: false }).limit(10);
    if (error || !Array.isArray(data)) return null;
    return data;
  } catch (_e) { return null; }
}

/** The one claim per person per quiet window: its key is unique in notifications (notifications_dedupe_key_uidx, a partial
 *  unique index on dedupe_key, read on production 12 Nov 2026), so two turns of the same person due in the same second (two
 *  photos sent together are two turns: attachments are never merged) cannot both send. 23505 = another turn holds it. */
export const holdingClaimKey = (phone: string, nowMs: number) =>
  'wa_holding:' + phone.replace(/[^0-9]/g, '').slice(-9) + ':' + Math.floor(nowMs / (HOLDING_QUIET_MIN * 60_000));
/** The claimed row's interim state: 'skipped' is terminal for every dispatcher (never 'sending': fn_notifications_claim requeues
 *  it, and never a status a flush drains), and the outcome replaces it a moment later. */
export const CLAIM_NOTE = 'claimed by this turn; the holding line is being sent and this row is set to what happened';

/** Send the holding line at most once per quiet window, in a wording they did not get last time. CLAIM, then send, then record
 *  the outcome on the claimed row (review of 12 Nov 2026: read-send-record let two turns due together both send). */
export async function sendHoldingLine(d: HoldingDeps, o: { to: string; lang: 'en' | 'ar'; audience: string; stillDue: () => boolean; /** unused since the claim is per person and window */ turnKey?: string }): Promise<string> {
  if ((await d.setting('wa_autoreply_enabled')) !== 'true') return 'autoreply_off';
  const phone = o.to.replace(/^whatsapp:/, '');
  const nowMs = (d.now ?? Date.now)();
  const earlier = await earlierLines(d, phone, nowMs);
  if (!earlier) return 'history_unavailable';
  const went = earlier.filter((r) => WENT.includes(String(r.status)));
  if (went.some((r) => Date.parse(r.created_at) > nowMs - HOLDING_QUIET_MIN * 60_000)) return 'already_held';
  const text = holdingLine(o.lang, o.audience, went.map((r) => String(r.body ?? '')));
  if (!o.stillDue()) return 'reply_ready';   // the reply became ready while the history was read: nothing is claimed or sent
  const fixture = isDemoPhone(phone);
  const claimed = fixture ? 'suppressed' : 'skipped';
  const unrecorded = (status: string, e: unknown) => d.finding('wa_inbound:holding_unrecorded',
    'A WhatsApp holding line could not be recorded in notifications, so the next turn cannot see it was sent',
    { status, code: (e as { code?: string })?.code ?? null, error: String((e as { message?: string })?.message ?? e).slice(0, 300), phone_tail: phone.replace(/\D/g, '').slice(-4) }).catch(() => null);
  let id: number | null = null;
  try {
    const { data, error } = await d.admin.from('notifications').insert({
      type: HOLDING_TYPE, channel: 'whatsapp', to_phone: phone, body: text, lang: o.lang === 'ar' && o.audience !== 'supplier' ? 'ar' : 'en',
      status: claimed, last_error: fixture ? FIXTURE_CAPTURE_NOTE : CLAIM_NOTE, sender: 'customer_support', kind: 'holding_notice',
      requested_by: HOLDING_REQUESTER, dedupe_key: holdingClaimKey(phone, nowMs),
    }).select('id,status').maybeSingle();
    if (error) {
      if (String(error.code ?? '') === '23505') return 'already_held';   // another turn of this person holds the window
      await unrecorded(claimed, error);
      return 'unrecorded';   // no claim, no send: a second line is the harm, a missing one is not
    }
    id = data?.id ?? null;
    // a guard that changed the outcome on insert ('held' in a rehearsal) would leave a row a release could send later
    if (id != null && data.status !== claimed) await d.admin.from('notifications').update({ status: claimed }).eq('id', id);
  } catch (e) { await unrecorded(claimed, e); return 'unrecorded'; }
  const outcome = async (patch: Record<string, unknown>) => {
    if (id == null) return;
    try {
      const { error } = await d.admin.from('notifications').update(patch).eq('id', id);
      if (error) await unrecorded(String(patch.status), error);
    } catch (e) { await unrecorded(String(patch.status), e); }
  };
  if (fixture) return 'fixture_captured';
  if (!o.stillDue()) { await outcome({ status: 'cancelled', last_error: 'not sent: the reply was ready first' }); return 'reply_ready'; }
  const r = await d.send(o.to, text);
  // a line that could not be sent is 'cancelled', never 'failed' (review round 2): send_whatsapp re-sends a failed WhatsApp row by
  // SMS, and a holding line arriving by SMS minutes later, after the answer, is worse than none
  await outcome(r.ok ? { status: 'sent', sent_at: new Date().toISOString(), attempts: 1, last_error: null }
    : { status: 'cancelled', attempts: 1, last_error: ('not sent, and never retried (a holding line is due now or not at all): ' + String(r.err || 'send failed')).slice(0, 500) });
  return r.ok ? 'sent' : 'failed';
}

/** THE HOOK (say.ts, before the model is asked): arm this turn's holding line once, and show the typing indicator. */
export function armWaHolding(t: WaTurn, aud: string, lang: 'en' | 'ar', d: HoldingDeps = liveDeps): Holding | null {
  if (t.holding !== undefined || aud === 'founder' || !t.From) return t.holding ?? null;
  // a burst is measured from its LAST message (burst.ts), and the typing indicator names that message
  const arrived = Math.max(Date.parse(t.receivedAt) || Date.now(), t.burst?.lastAt ?? 0);
  const sid = t.burst?.lastSid || t.MessageSid;
  const mark = (k: string, v: number | string) => { if (t.timings) (t.timings as Record<string, number | string>)[k] = v; };
  const typing = (when: string) => void (async () => {
    if ((await d.setting('wa_typing_indicator')) === 'off') return;
    const r = await d.typing(t.From, sid);
    mark('typing_' + when, r.ok ? 'ok' : String(r.err || 'refused').slice(0, 80));
  })().catch(() => null);
  typing('at_ask');
  t.holdingFor = { aud, lang };
  const h = armHolding({ delayMs: holdingDelay(arrived), send: async (stillDue) => {
    const what = await sendHoldingLine(d, { to: t.From, lang, audience: aud, stillDue });
    mark('holding', what);
    if (what === 'sent' || what === 'fixture_captured') t.holdingWent = true;
    if (what === 'sent') { mark('holding_sent_ms', Date.now() - arrived); typing('after_holding'); }   // the indicator clears on delivery
  } });
  t.holding = registerHolding(t.From, h);
  return t.holding;
}

/** THE TURN'S END (index.ts finally): a holding line went, and no reply followed it and nothing was filed for the re-ask.
 *  The turn is filed now, so the model's answer reaches them within about a minute: "shortly" stays true. */
export async function noSilenceAfterHolding(t: WaTurn): Promise<boolean> {
  // the second lock (R1): a reply delivered to this person after the line went is an answer, whatever the registration says
  if (!t.holdingWent || t.holding?.answered || t.repliedAfterHolding || t.heldFiled || !t.heldTurn || !t.holdingFor) return false;
  const aud = t.holdingFor.aud === 'supplier' ? 'supplier' : t.holdingFor.aud === 'customer' ? 'customer' : 'visitor';
  await t.heldTurn(aud, t.holdingFor.lang, 'The holding line was sent, then this turn stopped before a reply was sent. Answer their message now.', 'no_reply_after_holding');
  return true;
}

/** THE TURN'S END for the holding line (index.ts finally, in this order): release it (settled, no longer reachable), then file the
 *  re-ask only if it went and no reply followed it. */
export async function endTurnHolding(t: WaTurn): Promise<boolean> {
  try { await t.holding?.release(); } catch (_e) { /* a holding line never costs the turn */ }
  return await noSilenceAfterHolding(t);
}
