// holding.ts - the WhatsApp holding line and typing indicator (it_engineer, 11 Nov 2026, founder ruling 1636).
// One hook, in say.ts before the model is asked: armWaHolding. The typing indicator goes at once; the holding line goes
// HOLDING_AFTER_MS after the person's last message if no reply has left by then (_shared/holding_notice.ts), once per turn.
// Any reply that leaves through sendWa (replies.ts) settles it, and the turn's end settles it (index.ts finally).
//
// THROUGH THE OUTBOX'S GUARD, RECORDED IN THE OUTBOX. The holding line is checked by the outbox duplicate guard
// (_shared/outbox_duplicate_guard.ts, #1938): the same line to the same person inside outbox_duplicate_window_min (10 min) is
// not sent again, it is recorded cancelled with the earlier row named. Every holding line, sent, refused, captured or failed,
// is a notifications row (type wa_holding_notice), so it is in the person's history and in the outbox's own counts.
// It is SENT here, inside the turn, not drained by send_whatsapp: its shelf life is a few seconds, and a holding line a
// flush delivered minutes later (after the answer) would be worse than none. So the row is written with its outcome and is
// never 'queued'; a failed send is 'failed' and is never retried.
// prevented by: wa_inbound/holding.test.ts
import { armHolding, holdingDelay, holdingLine, registerHolding, type Holding } from '../_shared/holding_notice.ts';
import { duplicateNote, duplicateOf, recentSends, windowFrom } from '../_shared/outbox_duplicate_guard.ts';
import { FIXTURE_CAPTURE_NOTE, isDemoPhone } from '../_shared/demo_identity.ts';
import { sendTypingIndicator } from '../_shared/wa_send.ts';
import { admin, sec } from './shared.ts';
import { sendWa } from './replies.ts';
import type { WaTurn } from './turn.ts';

export const HOLDING_TYPE = 'wa_holding_notice';

// deno-lint-ignore no-explicit-any
type Admin = any;
export interface HoldingDeps {
  admin: Admin;
  setting: (k: string) => Promise<string>;
  send: (to: string, text: string) => Promise<{ ok: boolean; err?: string }>;
  typing: (to: string, sid: string) => Promise<{ ok: boolean; err?: string }>;
}
const liveDeps: HoldingDeps = { admin, setting: sec, send: (to, text) => sendWa(to, text), typing: (to, sid) => sendTypingIndicator(admin, to, sid) };

/** Send the holding line once, through the duplicate guard, and record it in notifications. Returns what happened. */
export async function sendHoldingLine(d: HoldingDeps, o: { to: string; lang: 'en' | 'ar'; audience: string; stillDue: () => boolean }): Promise<string> {
  if ((await d.setting('wa_autoreply_enabled')) !== 'true') return 'autoreply_off';
  const text = holdingLine(o.lang, o.audience);
  const phone = o.to.replace(/^whatsapp:/, '');
  const row = { id: 'new', channel: 'whatsapp', type: HOLDING_TYPE, to_phone: phone, subject: null, body: text };
  const windowMin = windowFrom(await d.setting('outbox_duplicate_window_min'));
  const recent = await recentSends(d.admin, [row], windowMin);
  const earlier = recent ? duplicateOf(row, recent, windowMin) : null;
  const record = (status: string, extra: Record<string, unknown> = {}) => d.admin.from('notifications').insert({
    type: HOLDING_TYPE, channel: 'whatsapp', to_phone: phone, to_role: o.audience, body: text, lang: o.lang === 'ar' && o.audience !== 'supplier' ? 'ar' : 'en',
    status, sender: 'customer_support', kind: 'holding_notice', requested_by: 'wa_inbound', ...extra,
  }).then(() => null, () => null);
  if (earlier) { await record('cancelled', { last_error: duplicateNote(earlier) }); return 'duplicate'; }
  if (!o.stillDue()) return 'reply_ready';   // the reply left while the history was read: nothing is sent
  if (isDemoPhone(phone)) { await record('suppressed', { last_error: FIXTURE_CAPTURE_NOTE }); return 'fixture_captured'; }
  const r = await d.send(o.to, text);
  await record(r.ok ? 'sent' : 'failed', r.ok ? { sent_at: new Date().toISOString(), attempts: 1 } : { attempts: 1, last_error: String(r.err || 'send failed').slice(0, 500) });
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
  const h = armHolding({ delayMs: holdingDelay(arrived), send: async (stillDue) => {
    const what = await sendHoldingLine(d, { to: t.From, lang, audience: aud, stillDue });
    mark('holding', what);
    if (what === 'sent') { mark('holding_sent_ms', Date.now() - arrived); typing('after_holding'); }   // the indicator clears on delivery
  } });
  t.holding = registerHolding(t.From, h);
  return t.holding;
}
