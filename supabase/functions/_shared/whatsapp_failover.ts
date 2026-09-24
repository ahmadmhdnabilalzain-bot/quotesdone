// WHATSAPP -> SMS FAILOVER (customer_support, 24 Sep 2026, founder ledger 994).
// "Nothing may depend on WhatsApp alone." While WhatsApp is healthy a notice goes by WhatsApp (its email
// twin goes regardless); while it is down it goes by SMS; when it recovers it goes back to WhatsApp.
// Health is the IT engineer's integration watch: an OPEN it_engineer_finding under WA_SENDER_FINDING_KEY
// means the sender is failing (measured 24 Sep: open since 09:45Z, Twilio 63005, ticket 29665983). The
// watch closes that finding the moment the sender answers again, so recovery needs nothing from here.
// The SMS twin itself is written by public.fn_wa_sms_twin, which allows ONE twin per notice.
import { isDemoPhone } from './demo_identity.ts';

export const WA_SENDER_FINDING_KEY = 'duty:integration:twilio_whatsapp_sender';
/** What send_whatsapp stamps on a WhatsApp row whose notice went by SMS (fn_wa_sms_twin writes it). */
export const FAILOVER_MARK = 'sms failover:';
const SMS_MAX = 600; // send_sms cuts at 600 characters

export type WaHealth = { healthy: boolean; reason: string | null };

/** openFinding: the open finding row for the sender, or null when none is open. */
export function waHealthFrom(openFinding: { started_at?: string | null } | null): WaHealth {
  if (!openFinding) return { healthy: true, reason: null };
  return { healthy: false, reason: 'WhatsApp sender is failing (IT finding ' + WA_SENDER_FINDING_KEY
    + (openFinding.started_at ? ' open since ' + openFinding.started_at : '') + ')' };
}

/** Where one queued WhatsApp notice goes. A fixture number goes nowhere, on either channel. */
export function routeFor(h: WaHealth, phone: string): 'whatsapp' | 'sms' | 'suppress' {
  if (isDemoPhone(phone)) return 'suppress';
  return h.healthy ? 'whatsapp' : 'sms';
}

/** The SMS text: the notice's own subject and body, one paragraph, with its link always kept at the end. */
export function smsTextFor(n: { subject?: string | null; body?: string | null }, link: string | null): string {
  const subject = String(n.subject || '').replace(/\s+/g, ' ').trim();
  let body = String(n.body || '').replace(/\s+/g, ' ').trim();
  if (subject && body.startsWith(subject)) body = body.slice(subject.length).trim();
  const text = ['QuotesDone:', subject, body].filter(Boolean).join(' ');
  const tail = link && !text.includes(link) ? ' ' + link : '';
  const room = SMS_MAX - tail.length;
  return (text.length > room ? text.slice(0, room - 1) + '…' : text) + tail;
}

export type RpcFn = (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: unknown; error: { message: string } | null }>;
/** Queues the SMS twin. Idempotent in the database: a second call for one notice adds nothing. */
export async function queueSmsTwin(rpc: RpcFn, id: number, body: string, reason: string): Promise<{ ok: boolean; outcome: string }> {
  const { data, error } = await rpc('fn_wa_sms_twin', { p_notification_id: id, p_body: body, p_reason: reason.slice(0, 300) });
  if (error) return { ok: false, outcome: 'error: ' + error.message };
  const d = (data || {}) as { ok?: boolean; outcome?: string };
  return { ok: !!d.ok, outcome: String(d.outcome || 'unknown') };
}
