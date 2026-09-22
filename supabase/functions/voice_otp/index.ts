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
// there, and the person on the line is a customer or a supplier, not a broken integration. They
// now hear, in English and then in Arabic, where to reach us.
//
// NO SECRET IS READ AND NOTHING IS WRITTEN, so this needs no signature check: the response is the
// same fixed sentence for every caller, which is why it is safe to serve unauthenticated.
const SAY_EN = 'Thank you for calling QuotesDone. This number is for WhatsApp messages only. '
  + 'Please message us on WhatsApp or visit quotesdone.com.';
const SAY_AR = 'شكرًا لاتصالكم بـ QuotesDone. هذا الرقم مخصص لرسائل واتساب فقط، '
  + 'يُرجى مراسلتنا عبر واتساب أو زيارة موقعنا quotesdone.com.';

// Polly.Hala is Twilio's Gulf Arabic neural voice; ar-AE is the locale the founder's market speaks.
const TWIML = '<?xml version="1.0" encoding="UTF-8"?>'
  + '<Response>'
  + `<Say language="en-US">${SAY_EN}</Say>`
  + `<Say language="ar-AE" voice="Polly.Hala">${SAY_AR}</Say>`
  + '<Hangup/>'
  + '</Response>';

Deno.serve(() => new Response(TWIML, { status: 200, headers: { 'Content-Type': 'text/xml' } }));
