// replies.ts - the two doors every text leaves through: toContact (support_reply_guard, then bidi isolation) and sendWa
// (the fixture guard, the status callback and the Twilio call, in _shared/wa_send.ts). Moved out of index.ts
// unchanged (9 Nov 2026, customer_support).
import { guardSupportReply } from '../_shared/support_reply_guard.ts';
import { sendWhatsApp } from '../_shared/wa_send.ts';
import { answeredHoldingFor, settleHoldingFor } from '../_shared/holding_notice.ts';
import { FIXTURE_CAPTURE_NOTE } from '../_shared/demo_identity.ts';
import type { Content } from './menu_flow.ts';
import { admin } from './shared.ts';

const LRI = '⁦', PDI = '⁩';
export function bidiSafe(s: string): string {
  if (!/[؀-ۿ]/.test(s)) return s;
  return s
    .replace(/https?:\/\/[^\s]+/g, (m) => LRI + m + PDI)
    .replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, (m) => LRI + m + PDI)
    .replace(/\+?\d[\d\s\-()]{6,}\d/g, (m) => LRI + m + PDI);
}
// Every text to a customer or supplier goes through here: support_reply_guard.ts (no licence number, no
// "AI", no internal error or prompt wording), then bidi isolation. Only the founder's command-channel
// replies use bidiSafe alone. support_replies_never_carry_the_licence_or_ai.test.mjs counts the sites.
export function toContact(s: string): string {
  return bidiSafe(guardSupportReply(s, /[؀-ۿ]/.test(s) ? 'ar' : 'en').text);
}

// v17's report-as-PDF (WANTS_DOC, mdToHtml, renderReportPdf) is removed with the agent_brain call it
// rendered (22 Sep 2026): it only ever rendered agent_brain's prose, and agent_brain is not deployed.

// Every reply leaves through here: the fixture guard, the status callback and the Twilio call live in
// _shared/wa_send.ts (moved 23 Sep 2026 so the reasoning replay sends a held answer the same way).
export async function sendWa(to: string, body: string, mediaUrl?: string | null, content?: Content): Promise<{ ok: boolean; err?: string }> {
  settleHoldingFor(to);   // a reply is leaving: a holding line not yet sent to this person never follows it (ruling 1636)
  const r = await sendWhatsApp(admin, to, body, mediaUrl, content);
  // ONLY A DELIVERED REPLY COUNTS (review of 12 Nov 2026): the holding line is answered, and the turn's case step may record
  // the exchange, only when the send succeeded or a reserved fixture number captured it. A failed send leaves the holding line
  // unanswered, so index.ts files the turn for the re-ask, and records nothing on the case.
  if (r.ok || r.err === FIXTURE_CAPTURE_NOTE) { answeredHoldingFor(to); delivered(to, body); }
  return r;
}

// ---- who hears that a reply was delivered (the turn, for its case step: say.ts) -------------------------------------------
const listeners = new Map<string, Set<(body: string) => void>>();
const tail = (to: string) => String(to || '').replace(/[^0-9]/g, '').slice(-9);
/** Hear every reply delivered to this recipient until the returned function is called. */
export function onDelivered(to: string, fn: (body: string) => void): () => void {
  const k = tail(to);
  const set = listeners.get(k) ?? new Set();
  set.add(fn); listeners.set(k, set);
  return () => { set.delete(fn); if (!set.size && listeners.get(k) === set) listeners.delete(k); };
}
function delivered(to: string, body: string): void {
  for (const fn of listeners.get(tail(to)) ?? []) { try { fn(body); } catch (_e) { /* a listener never costs the send */ } }
}
