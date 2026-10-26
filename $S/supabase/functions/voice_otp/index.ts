// voice_otp - the number's VOICE answer. Says the line is WhatsApp-only, then hangs up.
//
// WHAT IT USED TO BE, AND WHY THAT WAS REMOVED (18 Jul 2026, security). This endpoint took no
// request object and performed no authentication of any kind. Its entire response was TwiML
// embedding app_secrets.voice_capture_token in cleartext:
//   <Gather action="...voice_otp_capture?k=<TOKEN>" .../>
// Anyone on the internet could fetch it and read the token. That token was the ONLY gate on
// voice_otp_capture, which upserts attacker-controlled text into app_secrets.voice_otp_last - the
// value an admin voice-OTP flow reads back. The "single-purpose token" defence was self-defeating:
// the endpoint that issued the token was itself public.
//
// SPOKEN SIGN-IN CODES ARE NOT COMING BACK, so there is nothing here to restore. MEASURED 22 Sep
// 2026: no Postgres routine and no edge function calls voice_otp (grep over supabase/functions,
// src and pg_proc.prosrc - the only hits are ownership registries, the write map and retired
// checks); app_secrets.voice_otp_last was last written 2026-07-01 while admin_mfa_sessions ran on
// to 2026-07-07, i.e. admin MFA moved to Twilio Verify and never came back. Sign-in is the mobile
// number plus an OTP (founder: no observe mode - plain login), and a phone may confirm, never
// select.
//
// SO WHY NOT KEEP THE 410? Because a caller is a person, not a route. The 410 answered
// "<Say>This service is unavailable.</Say>" to anyone who DIALLED our published Twilio number -
// the same number we print on WhatsApp invitations - and the comment above it blamed a missing
// twilio_auth_token, which has been in app_secrets since 7 Sep. Both were wrong: the token is
// there, and the person on the line is a customer or a supplier, not a broken integration.
//
// The sentences, and which domain a UAE caller hears, are in ./twiml.ts with their own test.
//
// NO SECRET IS READ AND NOTHING IS WRITTEN, so this needs no signature check: the response is the
// same fixed sentence for every caller, which is why it is safe to serve unauthenticated. It is
// also why there is nothing here to rate-limit - a flood costs one string concatenation.
import { inUae, twiml } from './twiml.ts';

Deno.serve(async (req: Request) => {
  let p: Record<string, string> = {};
  try {
    if (req.method === 'POST') p = Object.fromEntries((await req.formData()).entries()) as Record<string, string>;
    else p = Object.fromEntries(new URL(req.url).searchParams.entries());
  } catch (_e) { /* unreadable params: answer on .com, which redirects a UAE visitor itself */ }
  return new Response(twiml(inUae(p.FromCountry || '', p.From || '')), {
    status: 200, headers: { 'Content-Type': 'text/xml' },
  });
});
