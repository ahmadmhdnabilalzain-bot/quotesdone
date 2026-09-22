// sms_inbound - the SMS webhook on the Twilio number (customer_support, 22 Sep 2026, finding INT-03).
//
// MEASURED 22 Sep 2026: the number's SmsUrl was https://demo.twilio.com/welcome/sms/reply, the
// account's factory default. Every SMS anyone has ever sent to our line was answered by Twilio's
// demo responder and never reached this estate - not a row, not a log, not a finding. WhatsApp on
// the same number has had wa_inbound since July; SMS had nothing.
//
// THIS IS DELIBERATELY NOT A RESPONDER. It authenticates the webhook, records the message so a
// person can be answered, and returns an empty <Response/> so Twilio sends nothing back. SMS is not
// a channel we have opted anyone into and an auto-reply on it is a message we did not agree to send;
// the founder's rule is that customer_support is the only sender, and it sends from send_sms.
//
// AUTHENTICITY IS THE SAME CHECK WA_INBOUND MAKES, not a second implementation of it:
// _shared/twilio_inbound_signature.ts (moved there from wa_inbound/ by this change) knows which URL
// Twilio actually signs inside the edge runtime - the platform strips the /functions/v1 prefix, and
// hashing the stripped path is what silenced WhatsApp for twelve days. Fail closed: no token, no
// header or no match and nothing is recorded as genuine and nothing is answered.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
import { signedUrlCandidates, verifyInboundSignature } from '../_shared/twilio_inbound_signature.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const EMPTY = '<?xml version="1.0" encoding="UTF-8"?><Response></Response>';
const XML = (status = 200) => new Response(EMPTY, { status, headers: { 'Content-Type': 'text/xml' } });

async function sec(k: string): Promise<string> {
  const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle();
  return (data?.value as string) || '';
}

Deno.serve(observe('sms_inbound', async (req: Request) => {
  if (req.method !== 'POST') return XML(405);
  let params: Record<string, string> = {};
  try {
    params = Object.fromEntries((await req.formData()).entries()) as Record<string, string>;
  } catch (_e) {
    // Not a Twilio form post. Nothing to record and nothing to answer.
    return XML(400);
  }

  const authToken = await sec('twilio_auth_token');
  const presented = req.headers.get('x-twilio-signature');
  const urls = signedUrlCandidates(req.url, req.headers, Deno.env.get('SUPABASE_URL') || '', 'sms_inbound');
  const check = authToken
    ? await verifyInboundSignature(authToken, urls, params, presented)
    : { valid: false, reason: 'twilio_auth_token not in app_secrets - signature validation unavailable', url_form: null };

  // A REFUSED MESSAGE IS STILL A MESSAGE THAT ARRIVED. wa_inbound records its refusals for exactly
  // this reason: twelve days of "signature mismatch" were invisible because nothing wrote them down.
  // The row is written either way and `verified` says which it was.
  const { error } = await admin.from('sms_messages').insert({
    sms_from: params.From || '',
    sms_to: params.To || '',
    body: params.Body || '',
    message_sid: params.MessageSid || null,
    verified: check.valid,
    meta: {
      signature_reason: check.reason,
      signature_url_form: check.url_form,
      num_media: Number(params.NumMedia || 0),
      from_country: params.FromCountry || null,
      from_city: params.FromCity || null,
    },
  });
  if (error) console.error('sms_inbound: message not recorded:', error.message);

  return XML(check.valid ? 200 : 403);
}));
