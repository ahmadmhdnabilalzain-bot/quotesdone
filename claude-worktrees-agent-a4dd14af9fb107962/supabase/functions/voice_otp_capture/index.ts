// voice_otp_capture - DISABLED 18 Jul 2026 (security), paired with voice_otp.
//
// WHY: this wrote attacker-controllable text into app_secrets.voice_otp_last, gated only by a
// static token (?k=) that its sibling voice_otp handed out to any anonymous caller. With the
// token public, this was an unauthenticated write into app_secrets - the value an admin
// voice-OTP flow reads back, so it could be used to inject a known OTP.
//
// A write into app_secrets from an unauthenticated endpoint is not something to mitigate
// partially, so the path is closed rather than narrowed.
//
// TO RE-ENABLE: add app_secrets.twilio_auth_token, then validate X-Twilio-Signature here
// (HMAC-SHA1 over the full request URL + sorted POST params, base64, constant-time compare)
// and drop the token-in-URL scheme. Notes on the two things that break naive implementations:
// read the body ONCE as text and re-parse it, and rebuild the URL from x-forwarded-proto and
// x-forwarded-host because req.url reports the internal origin behind the Supabase gateway.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const HANGUP = '<?xml version="1.0" encoding="UTF-8"?><Response><Hangup/></Response>';
const XML = { 'Content-Type': 'text/xml' };
const T0 = Date.now();
Deno.serve(async () => {
  // Log attempts: while disabled, any hit here is either a stale Twilio callback or someone
  // probing the old hole. Either is worth seeing.
  try {
    await admin.from('agent_runs').insert({ agent: 'voice_otp_capture', status: 'error', counts: { disabled: true },
      note: 'voice_otp_capture is disabled (unauthenticated write into app_secrets). A caller reached it - stale Twilio callback or a probe of the closed hole.',
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging matter here */ }
  return new Response(HANGUP, { status: 410, headers: XML });
});
