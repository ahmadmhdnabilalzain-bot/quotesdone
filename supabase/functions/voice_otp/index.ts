// voice_otp - DISABLED 18 Jul 2026 (security).
//
// WHY: this endpoint took no request object and performed no authentication of any kind.
// Its entire response was TwiML embedding app_secrets.voice_capture_token in cleartext:
//   <Gather action="...voice_otp_capture?k=<TOKEN>" .../>
// Anyone on the internet could fetch it and read the token. That token was the ONLY gate on
// voice_otp_capture, which upserts attacker-controlled text into app_secrets.voice_otp_last -
// the value an admin voice-OTP flow reads back. So the "single-purpose token" defence was
// self-defeating: the endpoint that issued the token was itself public.
//
// EVIDENCE THIS PATH IS UNUSED: app_secrets.voice_otp_last was last written 2026-07-01, while
// admin_mfa_sessions continued to 2026-07-07 - i.e. admin MFA moved to the SMS/Twilio Verify
// path and this voice fallback stopped being exercised. No Postgres function references it.
//
// PROPER FIX (to re-enable): Twilio webhooks must be authenticated with X-Twilio-Signature,
// an HMAC-SHA1 over the full request URL plus sorted POST params, keyed with the account's
// AUTH TOKEN. app_secrets currently holds twilio_account_sid, twilio_api_key_sid and
// twilio_api_key_secret, but NOT twilio_auth_token - API keys cannot verify webhook
// signatures. Add twilio_auth_token, then restore this function with signature validation
// (and drop the token-in-URL scheme entirely).
//
// Returning 410 rather than deleting so the route stays discoverable and reversible.
const GONE = '<?xml version="1.0" encoding="UTF-8"?><Response><Say>This service is unavailable.</Say><Hangup/></Response>';
Deno.serve(() => new Response(GONE, { status: 410, headers: { 'Content-Type': 'text/xml' } }));
