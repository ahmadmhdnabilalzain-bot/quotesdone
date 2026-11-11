// wa_send — one in-session WhatsApp send through Twilio's REST API. Seat: customer_support.
//
// Moved here from wa_inbound (23 Sep 2026) so the reasoning replay (_shared/reasoned_delivery.ts) sends a
// reasoned answer exactly the way a live reply is sent — the same fixture guard, the same status callback —
// instead of a second copy drifting. It sends FREE TEXT, which WhatsApp allows only inside the customer's
// 24-hour window; outside it the caller queues a template row for send_whatsapp instead.
import { timedFetch } from './timed_fetch.ts';
import { FIXTURE_CAPTURE_NOTE, isDemoPhone } from './demo_identity.ts';
import { statusCallbackUrl } from './twilio_status.ts';

export type Content = { sid: string; variables: Record<string, string> };
// deno-lint-ignore no-explicit-any
type Admin = any;
const secOf = async (admin: Admin, k: string) => { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; };

export async function sendWhatsApp(admin: Admin, to: string, body: string, mediaUrl?: string | null, content?: Content): Promise<{ ok: boolean; err?: string }> {
  // A fixture number is never replied to. The caller stores err as its send_error, which is the capture record.
  if (isDemoPhone(to)) return { ok: false, err: FIXTURE_CAPTURE_NOTE };
  const [sid, kSid, kSec, from] = await Promise.all(['twilio_account_sid', 'twilio_api_key_sid', 'twilio_api_key_secret', 'twilio_wa_from'].map((k) => secOf(admin, k)));
  if (!sid || !kSid || !kSec || !from) return { ok: false, err: 'twilio_not_configured' };
  const form = new URLSearchParams({ From: 'whatsapp:' + (from.startsWith('+') ? from : '+' + from), To: to.startsWith('whatsapp:') ? to : ('whatsapp:' + to), Body: body });
  // WhatsApp caps a media caption at 1,024 characters, well below the 1,200 used for a plain
  // message, so the caller must send the summary here and the substance in the document.
  if (mediaUrl) form.set('MediaUrl', mediaUrl);
  // An in-session interactive menu (twilio/list-picker). The Content item carries its own text.
  if (content) { form.delete('Body'); form.set('ContentSid', content.sid); form.set('ContentVariables', JSON.stringify(content.variables)); }
  form.set('StatusCallback', statusCallbackUrl());
  try {
    const r = await timedFetch('https://api.twilio.com/2010-04-01/Accounts/' + sid + '/Messages.json', { method: 'POST', headers: { 'Authorization': 'Basic ' + btoa(kSid + ':' + kSec), 'Content-Type': 'application/x-www-form-urlencoded' }, body: form.toString() });
    if (r.ok) return { ok: true };
    let detail = 'http_' + r.status;
    try { const j = await r.json(); if (j?.code || j?.message) detail = String(j.code || '') + ' ' + String(j.message || ''); } catch (_e) { /* keep status */ }
    return { ok: false, err: detail.slice(0, 300) };
  } catch (e) { return { ok: false, err: String((e as Error)?.message || e).slice(0, 300) }; }
}

// THE WHATSAPP TYPING INDICATOR (it_engineer, 11 Nov 2026, founder ruling 1636). Twilio's Typing Indicators resource,
// POST https://messaging.twilio.com/v3/Indicators/Typing.json with { messageId, channel: 'whatsapp' } (Public Beta, read from
// twilio.com/docs/whatsapp/api/typing-indicators-resource on 11 Nov 2026): it names the INBOUND message being answered (its
// SM/MM sid), marks that message read on the person's phone and shows "typing…" until our reply is delivered or 25 s pass.
// Same API key as the send. It is a courtesy beside the holding line, never instead of it: an account without the beta,
// a refusal or a timeout returns { ok: false } and nothing else changes. A fixture number is never contacted.
export const TYPING_URL = 'https://messaging.twilio.com/v3/Indicators/Typing.json';
export async function sendTypingIndicator(admin: Admin, to: string, messageSid: string): Promise<{ ok: boolean; err?: string }> {
  if (isDemoPhone(to)) return { ok: false, err: FIXTURE_CAPTURE_NOTE };
  if (!/^(SM|MM)[0-9a-f]{32}$/i.test(String(messageSid || ''))) return { ok: false, err: 'no inbound message sid' };
  const [kSid, kSec] = await Promise.all(['twilio_api_key_sid', 'twilio_api_key_secret'].map((k) => secOf(admin, k)));
  if (!kSid || !kSec) return { ok: false, err: 'twilio_not_configured' };
  try {
    const r = await timedFetch(TYPING_URL, { method: 'POST', headers: { 'Authorization': 'Basic ' + btoa(kSid + ':' + kSec), 'Content-Type': 'application/json' },
      body: JSON.stringify({ messageId: messageSid, channel: 'whatsapp' }) }, 5_000);
    if (r.ok) return { ok: true };
    let detail = 'http_' + r.status;
    try { const j = await r.json(); if (j?.code || j?.message) detail = String(j.code || '') + ' ' + String(j.message || ''); } catch (_e) { /* keep status */ }
    return { ok: false, err: detail.slice(0, 300) };
  } catch (e) { return { ok: false, err: String((e as Error)?.message || e).slice(0, 300) }; }
}
