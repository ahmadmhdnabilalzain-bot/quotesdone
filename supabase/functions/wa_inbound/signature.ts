// signature.ts - WEBHOOK AUTHENTICITY for the Twilio form path: the provenance lookup (v10) and the X-Twilio-Signature
// check (v11). Moved out of index.ts unchanged (9 Nov 2026, customer_support); the order they are called in is
// in arrival.ts.
import { sec } from './shared.ts';
import { signedUrlCandidates, verifyInboundSignature } from '../_shared/twilio_inbound_signature.ts';

// PROVENANCE (v10, 19 Jul 2026) ---------------------------------------------------------------
// This endpoint is verify_jwt=false and was completely unauthenticated on the Twilio form path:
// anyone who knew the URL could POST From/Body and the function would (a) run an LLM completion,
// and (b) call sendWa(From, ...) - sending a real WhatsApp message from the QuotesDone business
// number TO ANY NUMBER THE CALLER CHOSE. That is an open relay for message-bombing plus unbounded
// Twilio and OpenRouter spend on our account, and it lets an attacker put words in our mouth.
//
// The textbook fix is HMAC-SHA1 validation of X-Twilio-Signature - but that requires the Twilio
// AUTH TOKEN, and only twilio_account_sid / twilio_api_key_sid / twilio_api_key_secret are stored
// (no auth token anywhere in app_secrets), so signature validation is not currently possible.
//
// Instead we verify PROVENANCE with the credentials we do have: every genuine Twilio webhook
// carries a MessageSid, so we ask Twilio's REST API whether that message actually exists, is
// inbound, and came from the number the payload claims. A forged POST cannot satisfy this - the
// attacker would have to guess a real SID of a real inbound message from that exact sender.
// This is weaker than a signature (it is a lookup, not a cryptographic proof) but it closes the
// open relay, and it is the strongest check available until an auth token is added.
//
// TO UPGRADE LATER: store the Twilio auth token as app_secrets.twilio_auth_token, then validate
// X-Twilio-Signature = base64(HMAC-SHA1(authToken, fullUrl + sorted k+v of the POST params)),
// rebuilding fullUrl from x-forwarded-proto / x-forwarded-host. Keep this check as defence in depth.
//
// FAILURE POSTURE: if the Twilio API itself is unreachable we do NOT silently auto-reply, and we
// do NOT discard the message. We record the inbound message, skip the LLM and the outbound send,
// and alert - so a real supplier message survives for manual follow-up while a forged one gets
// nothing. Losing an auto-reply for one cycle is cheap; relaying attacker-chosen messages is not.
export async function verifyProvenance(messageSid: string, from: string): Promise<{ verified: boolean; apiReachable: boolean; reason: string }> {
  if (!messageSid || !/^[A-Z]{2}[0-9a-f]{32}$/i.test(messageSid)) {
    return { verified: false, apiReachable: true, reason: 'no valid MessageSid in payload (genuine Twilio webhooks always include one)' };
  }
  const acct = await sec('twilio_account_sid'); const kSid = await sec('twilio_api_key_sid'); const kSec = await sec('twilio_api_key_secret');
  if (!acct || !kSid || !kSec) return { verified: false, apiReachable: false, reason: 'twilio credentials not configured - cannot verify' };
  try {
    const ctrl = new AbortController(); const tt = setTimeout(() => ctrl.abort(), 6000);
    const r = await fetch('https://api.twilio.com/2010-04-01/Accounts/' + acct + '/Messages/' + messageSid + '.json',
      { headers: { 'Authorization': 'Basic ' + btoa(kSid + ':' + kSec) }, signal: ctrl.signal });
    clearTimeout(tt);
    if (r.status === 404) return { verified: false, apiReachable: true, reason: 'Twilio has no message with SID ' + messageSid + ' - the webhook was forged' };
    if (!r.ok) return { verified: false, apiReachable: false, reason: 'Twilio API returned HTTP ' + r.status + ' while verifying the message' };
    const j = await r.json();
    const norm = (s: string) => String(s || '').replace(/^whatsapp:/i, '').replace(/[^\d+]/g, '').trim();
    if (norm(j?.from) !== norm(from)) return { verified: false, apiReachable: true, reason: 'MessageSid exists but its sender does not match the From in the payload - spoofed sender' };
    if (!String(j?.direction || '').toLowerCase().startsWith('inbound')) return { verified: false, apiReachable: true, reason: 'MessageSid refers to an OUTBOUND message being replayed as if inbound' };
    return { verified: true, apiReachable: true, reason: 'ok' };
  } catch (e) {
    return { verified: false, apiReachable: false, reason: 'could not reach Twilio to verify: ' + String((e as Error)?.message || e).slice(0, 120) };
  }
}

// SIGNATURE VALIDATION (v11, 19 Jul 2026) ------------------------------------------------------
// The upgrade path described above is now implemented. It is DORMANT until an auth token exists.
//
//   app_secrets.twilio_auth_token ABSENT  -> returns {checked:false}; caller falls through to
//                                            verifyProvenance(), i.e. behaviour is byte-for-byte
//                                            what it was before this function existed.
//   app_secrets.twilio_auth_token PRESENT -> HMAC-SHA1 over (fullUrl + sorted k+v of POST params),
//                                            base64, compared to X-Twilio-Signature in constant
//                                            time. A mismatch is REJECTED outright - we do NOT
//                                            fall back to the weaker provenance lookup, because
//                                            once cryptographic proof is available, failing it is
//                                            a forgery, not an inconclusive result.
//
// To activate: insert twilio_auth_token into app_secrets. Nothing else needs changing, and no
// redeploy is required - the value is read per request.
//
// A valid signature sets trusted=true and SKIPS verifyProvenance. That is deliberate: the
// signature is cryptographic proof of origin, strictly stronger than a REST lookup, and skipping
// saves one Twilio API round trip on every inbound message. Provenance remains the fallback for
// the no-token case, so the layered defence is preserved.
//
// 22 Sep 2026: the URL is no longer rebuilt from req.url alone — see _shared/twilio_inbound_signature.ts. Inside the edge
// runtime req.url's path is /wa_inbound, Twilio signs /functions/v1/wa_inbound, and every genuine
// webhook failed here for twelve days.
export async function verifyTwilioSignature(req: Request, params: Record<string, string>): Promise<{ checked: boolean; valid: boolean; reason: string; urls?: string[] }> {
  const authToken = await sec('twilio_auth_token');
  if (!authToken) return { checked: false, valid: false, reason: 'twilio_auth_token not in app_secrets - signature validation unavailable' };

  const sig = req.headers.get('x-twilio-signature') || '';
  if (!sig) return { checked: true, valid: false, reason: 'twilio_auth_token is configured but the request carried no X-Twilio-Signature header' };

  try {
    const urls = signedUrlCandidates(req.url, req.headers, Deno.env.get('SUPABASE_URL') || '');
    const r = await verifyInboundSignature(authToken, urls, params, sig);
    return { checked: true, valid: r.valid, urls,
             reason: r.valid ? 'signature valid (url form ' + r.url_form + ')' : r.reason + ' - payload altered, not signed by our Twilio account, or signed with a different auth token' };
  } catch (e) {
    // A crypto failure must not silently downgrade to the weaker path.
    return { checked: true, valid: false, reason: 'signature check errored: ' + String((e as Error)?.message || e).slice(0, 120) };
  }
}
