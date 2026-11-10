// Live WhatsApp health, the Twilio sends and the template ledger (split out of index.ts, 9 Nov 2026; a pure move).
import { timedFetch } from '../_shared/timed_fetch.ts';
// v8 (22 Sep 2026): every send names where Twilio reports delivered / read / failed (supabase/functions/
// wa_status). 'sent' with a SID now means only "Twilio accepted it"; whether it ARRIVED is the
// provider_status that callback (or its 30-minute backstop poll) writes onto the row.
import { statusCallbackUrl } from '../_shared/twilio_status.ts';
import { WA_SENDER_FINDING_KEY, waHealthFrom, type WaHealth } from '../_shared/whatsapp_failover.ts';
import { admin } from './client.ts';

// LIVE WHATSAPP HEALTH: the IT engineer's integration watch. An unreadable finding table reads as healthy,
// because the per-message failover below still catches every send that then fails.
export async function waHealth(): Promise<WaHealth> {
  const { data, error } = await admin.from('it_engineer_finding').select('started_at')
    .eq('issue_key', WA_SENDER_FINDING_KEY).is('closed_at', null).limit(1);
  if (error) return { healthy: true, reason: null };
  return waHealthFrom((data && data[0]) || null);
}
// THE SEND, AND WHAT IT MEANS WHEN IT DOES NOT COME BACK (22 Sep 2026, it_engineer, CONN-03).
// Both of these used a bare `await fetch` with no deadline and no catch. A timeout or a dropped
// connection therefore threw out of the whole drain loop, the row stayed 'queued', and the next run
// sent it AGAIN — after Twilio had already accepted it. `threw` is the third outcome the caller needs:
// not accepted, not rejected, UNKNOWN, and a message that may already have gone is never re-sent.
//
// NO IDEMPOTENCY KEY, AND THAT IS NOT PARITY WITH EMAIL — SAID PLAINLY (22 Sep 2026, after independent
// review asked for it). send_outbox sends Resend an `Idempotency-Key`, which Resend honours for 24
// hours, so a retried email row cannot become a second email. Twilio's Messages.json offers no
// equivalent, so nothing here can make a repeated POST a no-op at the provider. What closes the gap
// instead, and exactly how far:
//   * the claim means two CONCURRENT senders cannot hold the same row at all;
//   * this request is bounded at 15 s and the claim expires at 5 minutes, so a second sender can never
//     pick up a row the first is still sending;
//   * a request that does not return is recorded as sent-unconfirmed and never drained again.
//   * RESIDUAL, not closed: if the isolate DIES between Twilio accepting the message and the row being
//     updated, no catch runs, the row stays 'sending', and the claim requeues it after 5 minutes — one
//     duplicate WhatsApp message. Narrow, real, and unfixable from this side while Twilio has no key.
// code: Twilio's numeric error code (its REST error object), the structured signal a rejection is judged by.
type WaSend = { ok: boolean; sid: string | null; error: string | null; code?: number | string | null; threw?: boolean };
async function twilioSend(acct:string, auth:string, form:URLSearchParams): Promise<WaSend> {
  try {
    const r = await timedFetch(`https://api.twilio.com/2010-04-01/Accounts/${acct}/Messages.json`,
      { method:'POST', headers:{ 'Authorization':'Basic '+auth, 'Content-Type':'application/x-www-form-urlencoded' }, body: form.toString() }, 15_000);
    const jd = await r.json().catch(()=>({}));
    return { ok:r.ok, sid: jd?.sid||null, error: r.ok?null:(jd?.message||('http '+r.status)), code: r.ok ? null : (jd?.code ?? null) };
  } catch (e) {
    return { ok:false, sid:null, threw:true, error: 'the request to Twilio did not return: ' + String((e as Error)?.message || e).slice(0,160) };
  }
}
export function waSendBody(acct:string, ks:string, kk:string, from:string, to:string, body:string){
  return twilioSend(acct, btoa(ks + ':' + kk),
    new URLSearchParams({ To: 'whatsapp:'+to, From: 'whatsapp:'+from, Body: body, StatusCallback: statusCallbackUrl() }));
}
export function waSendTemplate(acct:string, ks:string, kk:string, from:string, to:string, contentSid:string, vars:Record<string,string>){
  return twilioSend(acct, btoa(ks + ':' + kk),
    new URLSearchParams({ To: 'whatsapp:'+to, From: 'whatsapp:'+from, ContentSid: contentSid, ContentVariables: JSON.stringify(vars), StatusCallback: statusCallbackUrl() }));
}
// 6 SEP 2026: the ledger decides. public.messaging_template holds Twilio's word for every registered
// SID; 'approved' is trusted as read, anything else is re-asked of Twilio at most every ten minutes
// and written back, so approval is noticed within ten minutes of Meta's answer with no cron of its own.
// An approved row is re-checked with Twilio once a day by wa_templates_watch (29 Sep 2026); if Meta
// paused or rejected it, that run rewrites the row and this function stops using the template.
export async function templateStatus(auth:string, sid:string, key:string, lang:string):Promise<{status:string; reason:string|null}>{
  const { data: row } = await admin.from('messaging_template').select('status,last_checked_at,approved_at,rejection_reason').eq('sid', sid).maybeSingle();
  const fresh = !!row && (row.status === 'approved' || (!!row.last_checked_at && Date.now() - Date.parse(row.last_checked_at) < 600000));
  if (fresh) return { status: String(row!.status), reason: (row!.rejection_reason as string|null) || null };
  const r = await fetch('https://content.twilio.com/v1/Content/' + sid + '/ApprovalRequests', { headers: { 'Authorization': 'Basic ' + auth } });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) return { status: String(row?.status || 'unknown'), reason: 'twilio http ' + r.status };
  const st = String(j?.whatsapp?.status || j?.status || 'unknown'); const now = new Date().toISOString();
  await admin.from('messaging_template').upsert({ sid, channel: 'whatsapp', template_key: key, lang, status: st, last_checked_at: now,
    name: j?.whatsapp?.name || null, category: j?.whatsapp?.category || null, rejection_reason: j?.whatsapp?.rejection_reason || null,
    approved_at: st === 'approved' ? (row?.approved_at || now) : null }, { onConflict: 'sid' });
  return { status: st, reason: j?.whatsapp?.rejection_reason || null };
}
