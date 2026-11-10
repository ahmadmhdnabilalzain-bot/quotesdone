// twilio_status.ts — the one place a Twilio message send learns where to report what became of it,
// and the one check that a report claiming to be from Twilio really is.
//
// MEASURED 22 Sep 2026 (customer_support), via the Twilio API: the WhatsApp sender
// whatsapp:+12183166814 has its incoming webhook on functions/v1/wa_inbound and NO status callback,
// no send in supabase/functions set StatusCallback, and nothing polled a message's status. So a
// WhatsApp that Twilio accepted and Meta then refused (63016 outside the 24-hour window, 63024 not a
// WhatsApp user, a template not approved) stayed 'sent' for ever, and delivered/read were never known.
//
// Every Messages.json POST in the estate now carries StatusCallback = statusCallbackUrl(), and
// supabase/functions/wa_status receives it, checks the signature below, and hands the status to
// public.fn_twilio_status_arrived (scripts/sql/every_whatsapp_says_whether_it_arrived.sql).

// THE CALLBACK RUNS IN THE DATABASE'S REGION, AND A MESSAGE SENT BEFORE THAT STILL VERIFIES (it_engineer, 10 Nov 2026; channels
// audit R6). A function runs where its caller enters (_shared/db_region.ts): Twilio's status callbacks enter at us-east-1, so
// wa_status's database trips crossed the Pacific. The StatusCallback a send names now carries ?forceFunctionRegion=ap-southeast-1.
// Twilio signs the URL it was GIVEN, query included, and a message's callbacks (sent, delivered, read) keep arriving for hours
// after its send: a message sent before this deploy is signed over the old URL. So the signature is checked against both, the
// pinned one and the old one; a callback signed over neither is still refused.
// prevented by: _shared/twilio_status.test.ts (a callback for a message sent before the pin verifies)
import { inDbRegion } from './db_region.ts';
/** The base of the URL Twilio calls back, without the region pin: what every message sent before 10 Nov 2026 names. */
export function legacyStatusCallbackUrl(): string {
  return String(Deno.env.get('SUPABASE_URL') || '').replace(/\/+$/, '') + '/functions/v1/wa_status';
}
/** The exact URL a send names as its StatusCallback, and therefore the URL Twilio signs: wa_status, in the database's region. */
export function statusCallbackUrl(): string {
  return inDbRegion(legacyStatusCallbackUrl());
}
/** Every URL a genuine callback may be signed over: the pinned one, then the old one (messages still in flight). */
export function statusCallbackUrls(): string[] {
  return [statusCallbackUrl(), legacyStatusCallbackUrl()];
}

/** Twilio's scheme: the full URL, then every POST parameter as name+value, names in case-sensitive
 *  (code-unit) order, HMAC-SHA1 with the account's auth token, base64. */
export async function twilioSignature(authToken: string, url: string, params: Record<string, string>): Promise<string> {
  let data = url;
  for (const k of Object.keys(params).sort()) data += k + params[k];
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(authToken), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(data)));
  let bin = '';
  for (const b of mac) bin += String.fromCharCode(b);
  return btoa(bin);
}

/** FAIL CLOSED: no token, no header, or any mismatch is invalid. Compared in constant time. */
export async function verifyTwilioSignature(authToken: string | null | undefined, url: string,
  params: Record<string, string>, presented: string | null | undefined): Promise<{ valid: boolean; reason: string }> {
  if (!authToken) return { valid: false, reason: 'no twilio_auth_token to check against' };
  if (!presented) return { valid: false, reason: 'no X-Twilio-Signature header' };
  const expected = await twilioSignature(authToken, url, params);
  if (expected.length !== presented.length) return { valid: false, reason: 'signature mismatch' };
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ presented.charCodeAt(i);
  return diff === 0 ? { valid: true, reason: 'signature valid' } : { valid: false, reason: 'signature mismatch' };
}

/** Valid when the signature was computed over ANY of `urls` (statusCallbackUrls); the reason names the one that matched. */
export async function verifyTwilioSignatureAny(authToken: string | null | undefined, urls: string[],
  params: Record<string, string>, presented: string | null | undefined): Promise<{ valid: boolean; reason: string; url?: string }> {
  let last = { valid: false, reason: 'no callback URL to check against' };
  for (const url of urls) {
    last = await verifyTwilioSignature(authToken, url, params, presented);
    if (last.valid) return { ...last, url };
  }
  return last;
}
