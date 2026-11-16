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
// So a refusal does what wa_inbound does - one throttled founder_alerts row per 30 minutes, and an
// agent_runs row at status 'error'. agent_runs IS the reader: fn_it_detect reads it
// (D1 failures, D9 refusals), the throttle only ever limits founder_alerts, and sms_inbound is registered in
// public.it_watch_subject (public_surface, verify_jwt false, no secret gate) by the same commit.
//
// ── THE ORDER OF THIS HANDLER IS ITS FLOOD BOUND, AND IT IS NOT DECORATIVE ────────────────────
// Second review of #849 found the first version bypassable, and it was exactly right. It rate-
// limited on 'sms_inbound:' + params.From BEFORE verifying the signature - and params is
// attacker-controlled body content at that point. Rotating From per request minted a fresh
// 40/hour bucket every time, so a flood cost one ai_rate_limit row, one sms_messages insert, one
// founder_alerts SELECT and one agent_runs insert PER REQUEST, unbounded. The shared bucket for an
// absent From covered the one case an attacker would never choose.
//
// So the signature is verified FIRST. It is pure crypto over the body with a token this worker has
// already cached: no database call at all. Only after it passes is `From` something we may key a
// bucket on, because only then is it Twilio's word and not the caller's.
//
//   1. wrong method, or no X-Twilio-Signature header -> refused before anything is read. Not free:
//      observe() writes ONE agent_runs row at status 'warn' for every 4xx (observe.ts: 4xx -> warn,
//      and error rows are never sampled), handed to EdgeRuntime.waitUntil so it lands after the
//      response. One insert, no reads, nothing else - and that row is the only evidence a probe
//      reached us at all, so it is worth its cost. "Zero database calls" was wrong and is corrected.
//   2. a bad signature is capped by ONE GLOBAL bucket, UNSIGNED_PER_HOUR. A forgery cannot be keyed
//      on its own From, so there is one bucket for all of them, and past the cap a forged request
//      writes NOTHING beyond observe's row - no sms_messages insert, no alert lookup, no logRun.
//      The limiter failing counts as over the cap: fail closed is free here, because a genuine
//      webhook never reaches this branch.
//   3. a VERIFIED sender is capped per sender at SMS_PER_HOUR, which is now a real bound because
//      Twilio signed the From it is keyed on. Here the limiter failing fails OPEN - a limiter outage
//      must not drop a real supplier's message - and being refused alerts and logs, because
//      silently dropping genuine SMS is the same failure one layer out.
//   4. the auth token is cached per worker for TOKEN_TTL_MS, so a burst is one app_secrets read
//      rather than one per request.
//
// The partial unique index on message_sid is idempotency against Twilio's own redelivery, not a
// bound - a flood with no MessageSid slips straight past it - which is why it is not counted here.
//
// TWO agent_runs ROWS PER REFUSAL, and that is deliberate. observe() writes one (status 'warn', no
// reason - it only sees the status code) and logRun writes one naming the cause. Neither is
// throttled, because agent_runs is what the IT engine reads and a throttle there would hide the
// repeat count that tells "probed once" from "under attack". They are bounded instead, by the caps
// above: the whole refusal path cannot run more than UNSIGNED_PER_HOUR times an hour.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
import { signedUrlCandidates, verifyInboundSignature } from '../_shared/twilio_inbound_signature.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const EMPTY = '<?xml version="1.0" encoding="UTF-8"?><Response></Response>';
const XML = (status = 200) => new Response(EMPTY, { status, headers: { 'Content-Type': 'text/xml' } });

// A real sender does not text us 40 times an hour. Generous enough that a genuine burst (a supplier
// splitting a long message into segments) is never refused, small enough that a flood is.
const SMS_PER_HOUR = 40;
// Forgeries share one bucket, so this is a whole-estate ceiling on how much a probe can make us
// write. 20 an hour is plenty to see a campaign in agent_runs and diagnose it.
const UNSIGNED_PER_HOUR = 20;
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

/**
 * One tick of a bucket. `onError` is the answer when the limiter itself is unreachable, and the two
 * callers want opposite answers: a forgery is refused (nothing is lost), a genuine sender is let
 * through (a message would be).
 */
async function withinLimit(bucket: string, limit: number, onError: boolean): Promise<boolean> {
  try {
    const { data } = await admin.rpc('fn_rate_limit', { p_bucket: bucket, p_limit: limit, p_window_seconds: 3600 });
    return !(data && data.allowed === false);
  } catch (e) {
    console.error('sms_inbound: rate limit unavailable for', bucket, String((e as Error)?.message || e));
    return onError;
  }
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

async function record(params: Record<string, string>, valid: boolean, reason: string, urlForm: number | null) {
  const { error } = await admin.from('sms_messages').insert({
    sms_from: params.From || '',
    sms_to: params.To || '',
    body: params.Body || '',
    message_sid: params.MessageSid || null,
    verified: valid,
    meta: {
      signature_reason: reason,
      signature_url_form: urlForm,
      num_media: Number(params.NumMedia || 0),
      from_country: params.FromCountry || null,
      from_city: params.FromCity || null,
    },
  });
  if (error) console.error('sms_inbound: message not recorded:', error.message);
  return !error;
}

Deno.serve(observe('sms_inbound', async (req: Request) => {
  if (req.method !== 'POST') return XML(405);

  // STEP 1 - refused before the body is read. A genuine Twilio webhook always presents this header.
  const presented = req.headers.get('x-twilio-signature');
  if (!presented) return XML(403);

  let params: Record<string, string> = {};
  try {
    params = Object.fromEntries((await req.formData()).entries()) as Record<string, string>;
  } catch (_e) {
    return XML(400);   // not a Twilio form post: nothing to record and nothing to answer
  }

  // STEP 2 - PROVE IT IS OURS BEFORE TRUSTING ONE FIELD OF IT. Pure HMAC over the body against a
  // token this worker has cached: no database call, so this is the cheapest possible gate and it
  // runs before every write.
  const token = await authToken();
  const check = token
    ? await verifyInboundSignature(token, signedUrlCandidates(req.url, req.headers, Deno.env.get('SUPABASE_URL') || '', 'sms_inbound'), params, presented)
    : { valid: false, reason: 'twilio_auth_token not in app_secrets - signature validation unavailable', url_form: null };

  if (!check.valid) {
    // ONE GLOBAL BUCKET. `From` here is the caller's claim, not Twilio's, so keying on it would let
    // a rotating From mint a bucket per request - which is precisely the bypass the second review
    // found. Past the cap this returns having written nothing but observe's own row.
    if (!await withinLimit('sms_inbound:unsigned', UNSIGNED_PER_HOUR, false)) return XML(403);

    const saved = await record(params, false, check.reason, check.url_form);
    await alertThrottled('sms_bad_signature', 'warn',
      'An SMS webhook FAILED X-Twilio-Signature validation and was rejected (' + check.reason + '). '
      + 'This is cryptographic proof the request was not signed by our Twilio account, or that our auth '
      + 'token is wrong - and if it is the token, every genuine SMS is being refused too. The payload was '
      + 'stored in sms_messages with verified=false. Throttled to one alert per 30 minutes.');
    await logRun('error', { authorised: 0, signature_valid: 0, recorded: saved ? 1 : 0 },
      'sms_inbound REJECTED an SMS webhook that failed HMAC-SHA1 signature validation: ' + check.reason
      + '. Nothing was answered. The payload is in sms_messages (verified=false). A genuine Twilio webhook '
      + 'cannot fail this check, so this is a forgery or a misconfigured auth token. Bounded at '
      + UNSIGNED_PER_HOUR + ' refusals an hour across all senders.');
    return XML(403);
  }

  // STEP 3 - the signature held, so From is Twilio's word and a per-sender bucket is a real bound.
  const from = String(params.From || '').slice(0, 40) || 'unknown';
  if (!await withinLimit('sms_inbound:' + from, SMS_PER_HOUR, true)) {
    await alertThrottled('sms_inbound_rate_limited', 'warn',
      'The SMS webhook refused a VERIFIED sender after ' + SMS_PER_HOUR + ' messages in an hour. Their SMS '
      + 'is being dropped for the rest of the window, and the signature proves these are real messages from '
      + 'a real number, so they need answering by hand. Throttled to one alert per 30 minutes.');
    await logRun('error', { rate_limited: 1, limit: SMS_PER_HOUR, signature_valid: 1 },
      'sms_inbound rate-limited a SIGNED sender at ' + SMS_PER_HOUR + '/hour and recorded nothing for those '
      + 'messages. Unlike the unsigned cap this drops genuine traffic, so if it fires the limit is wrong or '
      + 'somebody holds our auth token.');
    return XML(429);
  }

  const saved = await record(params, true, check.reason, check.url_form);
  await logRun('ok', { authorised: 1, signature_valid: 1, recorded: saved ? 1 : 0, media: Number(params.NumMedia || 0) },
    'sms_inbound recorded an SMS on a verified X-Twilio-Signature and answered an empty <Response/>. '
    + 'It does not reply: customer_support sends on this channel from send_sms.');
  return XML(200);
}));
