// wa_status — what became of every WhatsApp and SMS Twilio accepted (customer_support, 22 Sep 2026).
//
// Two doors, one recorder (public.fn_twilio_status_arrived, which never moves a status backwards):
//
//   1. TWILIO'S STATUS CALLBACK (form POST). Every Messages.json send sets StatusCallback to this
//      function (_shared/twilio_status.ts). The X-Twilio-Signature is checked with the account's auth
//      token over the exact callback URL and every posted parameter. FAIL CLOSED: no token, no header
//      or a mismatch is refused and nothing is recorded — a forged "delivered" must never close a loop.
//
//   2. THE BACKSTOP POLL (JSON POST with an internal credential; resilience_ping's whatsappTick calls
//      it every tick). Callbacks can be lost — Twilio does not retry a failed status callback, and a
//      fast failure can arrive before send_whatsapp has written the SID it would be matched on. So any
//      message sent more than 30 minutes ago with no final status is asked of Twilio directly, at most
//      POLL_LIMIT per call, each row at most once per 30 minutes (fn_twilio_status_poll_claim).
//
// What a failure then does is the database's: the row becomes 'failed' with Twilio's error in plain
// words, and fn_customer_support_delivery_watch returns that as the delivery.result to the seat that
// asked (every_whatsapp_says_whether_it_arrived.sql).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { observe } from '../_shared/observe.ts';
import { statusCallbackUrl, verifyTwilioSignature } from '../_shared/twilio_status.ts';
import { J } from '../_shared/json_response.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const POLL_LIMIT = 20;
/** What fn_twilio_status_poll_claim returns: one row per message to ask Twilio about. */
export type PollRow = { notification_id: number; sid: string };
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'wa_status', status, counts, note: note.slice(0, 500),
      started_at: new Date().toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* logging never blocks the recorder */ }
}
async function record(sid: string, status: string, code: string | null, source: string) {
  const { data, error } = await admin.rpc('fn_twilio_status_arrived',
    { p_sid: sid, p_status: status, p_error_code: code, p_source: source });
  if (error) throw new Error('fn_twilio_status_arrived: ' + error.message);
  return data as { matched?: boolean; applied?: boolean };
}

async function poll(): Promise<Response> {
  const acct = await sec('twilio_account_sid'); const ks = await sec('twilio_api_key_sid'); const kk = await sec('twilio_api_key_secret');
  if (!acct || !ks || !kk) { await logRun('error', { poll: true }, 'status backstop cannot run: Twilio API key missing'); return J({ ok: false, error: 'twilio_not_configured' }); }
  const { data: due, error } = await admin.rpc('fn_twilio_status_poll_claim', { p_limit: POLL_LIMIT });
  if (error) { await logRun('error', { poll: true }, 'fn_twilio_status_poll_claim: ' + error.message); return J({ ok: false, error: error.message }, 500); }
  let asked = 0, applied = 0, unreadable = 0; let gaveUp = 0;
  const failures: Array<{ id: number; http: number | null; code: string | null }> = [];
  // THE CLAIM ANSWERS (notification_id, sid) (22 Sep 2026, INT-01 / SEATS-03). This loop read the
  // notification table's own column name instead — a field the claim does not return — so every poll asked
  // Twilio for a URL ending "undefined.json", got 404, discarded the status and called the message
  // unreadable. Notifications 35433, 35569 and 37899 were polled that way six times; a GET by each of their
  // real SIDs answered HTTP 200 with status 'read'.
  for (const r of (due || []) as PollRow[]) {
    asked++;
    let http: number | null = null; let code: string | null = null;
    try {
      const res = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${acct}/Messages/${r.sid}.json`,
        { headers: { Authorization: 'Basic ' + btoa(ks + ':' + kk) }, signal: AbortSignal.timeout(8000) });
      http = res.status;
      if (res.ok) {
        const m = await res.json();
        const out = await record(r.sid, String(m?.status || ''), m?.error_code == null ? null : String(m.error_code), 'poll');
        if (out?.applied) applied++;
        continue;
      }
      // Twilio's own error body names a numeric code (20404 not found, 20003 auth); keep it with the HTTP status.
      const e = await res.json().catch(() => ({}));
      code = e?.code == null ? null : String(e.code);
    } catch (e) { code = String((e as Error)?.name || 'fetch_error').slice(0, 40); }
    unreadable++;
    failures.push({ id: r.notification_id, http, code });
    // After POLL_GIVE_UP failed reads the row is marked provider_status='unreadable' with that status, so it
    // stops being asked and the IT duty reports it as unreadable rather than as silently undelivered.
    // THE RPC'S OWN ERROR IS READ (22 Sep 2026). Discarding it hid the whole remedy: until this SQL is
    // applied the routine does not exist, and writing 'unreadable' is refused by the live CHECK until the
    // same apply widens it — both come back as `error` with data null, which without this branch reads as
    // "recorded, nobody gave up" and the poll looks healthy while recording nothing. Deploy order is
    // therefore: apply every_whatsapp_says_whether_it_arrived.sql FIRST, then deploy this function.
    const { data: f, error: fe } = await admin.rpc('fn_twilio_status_poll_failed', { p_notification_id: r.notification_id, p_http: http, p_code: code });
    if (fe) {
      await logRun('error', { poll: true, notification_id: r.notification_id, http, code },
        'wa_status could not record a failed status read on notification ' + r.notification_id + ': ' + fe.message
        + ' — the give-up counter did not move, so this message will be asked again and again. If this says the '
        + 'function does not exist or the status is not allowed, every_whatsapp_says_whether_it_arrived.sql has not been applied yet.');
    } else if ((f as { gave_up?: boolean } | null)?.gave_up) gaveUp++;
  }
  // Logged only when it did something, so an idle backstop does not bury the run log.
  if (asked) await logRun(unreadable ? 'error' : 'ok', { poll: true, asked, applied, unreadable, gave_up: gaveUp, failures: failures.slice(0, 20) },
    unreadable ? unreadable + ' of ' + asked + ' message statuses could not be read from Twilio (per-message HTTP status and Twilio code in counts.failures); '
      + (gaveUp ? gaveUp + ' marked unreadable after repeated failures, the rest are ' : 'they are ') + 'asked again in 30 minutes' : '');
  return J({ ok: true, asked, applied, unreadable, gave_up: gaveUp });

}

Deno.serve(observe('wa_status', async (req) => {
  if (req.method !== 'POST') return J({ error: 'method_not_allowed' }, 405);
  const ctype = req.headers.get('content-type') || '';
  if (ctype.includes('application/json')) {
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const auth = await requireInternal(admin, body?.__secret, 'wa_status');
    if (!auth.ok) return J({ error: 'forbidden' }, 403);
    return await poll();
  }
  const params: Record<string, string> = {};
  for (const [k, v] of new URLSearchParams(await req.text())) params[k] = v;
  const token = await sec('twilio_auth_token');
  const check = await verifyTwilioSignature(token, statusCallbackUrl(), params, req.headers.get('x-twilio-signature'));
  if (!check.valid) {
    await logRun(token ? 'warn' : 'error', { refused: true }, 'status callback refused: ' + check.reason);
    // 503 without a token: that is our configuration, not the caller's fault. 403 otherwise.
    return J({ error: 'forbidden' }, token ? 403 : 503);
  }
  const sid = params.MessageSid || params.SmsSid || '';
  const status = params.MessageStatus || params.SmsStatus || '';
  if (!sid || !status) return J({ ok: false, error: 'no MessageSid or MessageStatus' }, 400);
  try {
    const out = await record(sid, status, params.ErrorCode || null, 'callback');
    return J({ ok: true, ...out });
  } catch (e) {
    await logRun('error', { sid }, String((e as Error)?.message || e));
    return J({ ok: false }, 500);
  }
}));
