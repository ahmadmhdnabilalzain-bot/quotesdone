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
// header or no match and nothing is treated as genuine and nothing is answered.
//
// A REFUSAL IS TOLD, NOT ONLY FILED (independent review of #849). Recording a failed signature and
// telling nobody is how wa_inbound lost twelve days: the rows existed and no instrument read them.
// So this does exactly what wa_inbound does on the same event - one throttled founder_alerts row
// per 30 minutes, and an agent_runs row at status 'error'. agent_runs IS the reader: the IT
// detection engine ranks a failing subject off it, and sms_inbound is registered in
// public.it_watch_subject (public_surface, verify_jwt false, no secret gate) by the same commit.
//
// AND IT IS BOUNDED. This is an UNAUTHENTICATED PUBLIC WRITE, so a flood must not be able to spend
// the database one insert at a time. Three bounds, cheapest first:
//   1. no X-Twilio-Signature header at all costs ZERO database calls. Every genuine Twilio webhook
//      carries one, so junk is refused before anything is read or written.
//   2. fn_rate_limit (the same routine ai_gateway uses on public surfaces) caps the sender at
//      SMS_PER_HOUR before the secret read and before the insert. Keyed on From, with one shared
//      bucket for a missing From so a flood cannot mint a new bucket per request.
//   3. the auth token is cached per worker for TOKEN_TTL_MS, so a burst is one app_secrets read
//      rather than one per request.
// The partial unique index on message_sid is idempotency, not a bound - a flood with no MessageSid
// slips straight past it - which is why it is not counted here.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
import { signedUrlCandidates, verifyInboundSignature } from '../_shared/twilio_inbound_signature.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const EMPTY = '<?xml version="1.0" encoding="UTF-8"?><Response></Response>';
const XML = (status = 200) => new Response(EMPTY, { status, headers: { 'Content-Type': 'text/xml' } });

// A real sender does not text us 40 times an hour. Generous enough that a genuine burst (a supplier
// splitting a long message into segments) is never refused, small enough that a flood is.
const SMS_PER_HOUR = 40;
// ponytail: per-worker cache, not a shared one. A rotation is picked up within five minutes on every
// worker; a shared cache would need an invalidation path nothing else in this estate has.
const TOKEN_TTL_MS = 5 * 60_000;
let tokenCache: { value: string; at: number } | null = null;

async function authToken(): Promise<string> {
  if (tokenCache && Date.now() - tokenCache.at < TOKEN_TTL_MS) return tokenCache.value;
  const { data } = await admin.from('app_secrets').select('value').eq('key', 'twilio_auth_token').maybeSingle();
  tokenCache = { value: (data?.value as string) || '', at: Date.now() };
  return tokenCache.value;
}

async function logRun(status: string, counts: Record<string, unknown>, note: string): Promise<void> {
  try {
    await admin.from('agent_runs').insert({
      agent: 'sms_inbound', status, counts, note: String(note).slice(0, 500),
      started_at: new Date().toISOString(), finished_at: new Date().toISOString(),
    });
  } catch (e) { console.error('sms_inbound: run not logged:', String((e as Error)?.message || e)); }
}

/** One alert per event per 30 minutes, so a forgery flood cannot burn the founder's inbox. */
async function alertThrottled(event: string, level: string, detail: string): Promise<void> {
  try {
    const since = new Date(Date.now() - 30 * 60_000).toISOString();
    const { count } = await admin.from('founder_alerts')
      .select('id', { count: 'exact', head: true }).eq('event', event).gte('created_at', since);
    if ((count || 0) > 0) return;
    await admin.from('founder_alerts').insert({ level, event, detail, channel: 'system' });
  } catch (e) { console.error('sms_inbound: alert not raised:', event, String((e as Error)?.message || e)); }
}

Deno.serve(observe('sms_inbound', async (req: Request) => {
  if (req.method !== 'POST') return XML(405);

  // BOUND 1 - refuse before any database call. A genuine Twilio webhook always presents this header.
  const presented = req.headers.get('x-twilio-signature');
  if (!presented) return XML(403);

  let params: Record<string, string> = {};
  try {
    params = Object.fromEntries((await req.formData()).entries()) as Record<string, string>;
  } catch (_e) {
    return XML(400);   // not a Twilio form post: nothing to record and nothing to answer
  }

  // BOUND 2 - cap the sender before the secret read and before the insert. A missing From shares
  // one bucket on purpose: a per-request bucket is not a limit, it is a row generator.
  const from = String(params.From || '').slice(0, 40) || 'unknown';
  try {
    const { data: rl } = await admin.rpc('fn_rate_limit', {
      p_bucket: 'sms_inbound:' + from, p_limit: SMS_PER_HOUR, p_window_seconds: 3600,
    });
    if (rl && rl.allowed === false) {
      await alertThrottled('sms_inbound_rate_limited', 'warn',
        'The SMS webhook refused traffic from one sender after ' + SMS_PER_HOUR
        + ' messages in an hour. Genuine SMS from that number is being dropped for the rest of the window, '
        + 'so if this is a real supplier they need answering by hand. Throttled to one alert per 30 minutes.');
      await logRun('error', { rate_limited: 1, limit: SMS_PER_HOUR },
        'sms_inbound rate-limited a sender at ' + SMS_PER_HOUR + '/hour. Nothing was recorded for those messages. '
        + 'This is the flood bound on an unauthenticated public write; a genuine sender does not reach it.');
      return XML(429);
    }
  } catch (e) {
    // The limiter failing must not take the channel down with it; the signature check still stands.
    console.error('sms_inbound: rate limit unavailable:', String((e as Error)?.message || e));
  }

  const token = await authToken();
  const urls = signedUrlCandidates(req.url, req.headers, Deno.env.get('SUPABASE_URL') || '', 'sms_inbound');
  const check = token
    ? await verifyInboundSignature(token, urls, params, presented)
    : { valid: false, reason: 'twilio_auth_token not in app_secrets - signature validation unavailable', url_form: null };

  // A REFUSED MESSAGE IS STILL A MESSAGE THAT ARRIVED. The row is written either way and `verified`
  // says which it was, so "no SMS arrived" and "every SMS was refused" can never look the same.
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

  if (!check.valid) {
    await alertThrottled('sms_bad_signature', 'warn',
      'An SMS webhook FAILED X-Twilio-Signature validation and was rejected (' + check.reason + '). '
      + 'This is cryptographic proof the request was not signed by our Twilio account, or that our auth '
      + 'token is wrong - and if it is the token, every genuine SMS is being refused too. The payload was '
      + 'stored in sms_messages with verified=false. Throttled to one alert per 30 minutes.');
    await logRun('error', { authorised: 0, signature_valid: 0, recorded: error ? 0 : 1 },
      'sms_inbound REJECTED an SMS webhook that failed HMAC-SHA1 signature validation: ' + check.reason
      + '. Nothing was answered. The payload is in sms_messages (verified=false). A genuine Twilio webhook '
      + 'cannot fail this check, so this is a forgery or a misconfigured auth token.');
    return XML(403);
  }

  await logRun('ok', { authorised: 1, signature_valid: 1, recorded: error ? 0 : 1, media: Number(params.NumMedia || 0) },
    'sms_inbound recorded an SMS on a verified X-Twilio-Signature and answered an empty <Response/>. '
    + 'It does not reply: customer_support sends on this channel from send_sms.');
  return XML(200);
}));
