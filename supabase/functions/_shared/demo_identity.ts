// WHO IS A DEMO IDENTITY — the one TypeScript answer (14 Sep 2026, it_engineer's tooling for the ceo).
//
// The founder: "do what is needed cause you need to keep browsing stuff without my credentials".
// The end-to-end harness (scripts/e2e/) therefore creates its own customers and suppliers on the
// ONE production project. Two rules make that safe, and both hinge on recognising those accounts:
//
//   1. nothing addressed to them may reach a real person, and
//   2. they are never charged with a LIVE Stripe key.
//
// A demo identity is one that a real person can never own:
//   - an email on an RFC 2606 reserved domain (example.com/.net/.org, .test, .example, .invalid,
//     localhost). Nobody can receive mail there, so nobody can pass the OTP that proves ownership.
//     This is the same vocabulary send_outbox has refused since 3 Sep 2026 (RESERVED_TEST_DOMAIN).
//   - a mobile in the reserved fixture block +971 50 000 00xx. The harness addresses every demo
//     party there; a message to one is captured, never sent.
//
// The database holds the same rule in public.fn_is_demo_email / public.fn_is_demo_phone
// (scripts/sql/demo_identities_are_marked_and_never_reach_a_real_person.sql). The two MUST agree;
// demo_identity.test.ts pins the TypeScript side with the cases the SQL probe asserts.

export const RESERVED_TEST_DOMAIN =
  /@(?:[a-z0-9_-]+[.])*(?:example[.](?:com|net|org)|test|example|invalid|localhost)$/i;

/** +971 50 000 00xx in any formatting: 12 digits once non-digits are stripped. */
export const RESERVED_FIXTURE_MOBILE = /^9715000000\d{2}$/;

export function isDemoEmail(email: unknown): boolean {
  return RESERVED_TEST_DOMAIN.test(String(email ?? '').trim());
}

export function isDemoPhone(phone: unknown): boolean {
  return RESERVED_FIXTURE_MOBILE.test(String(phone ?? '').replace(/\D/g, ''));
}

// A FIXTURE NUMBER IS NEVER HANDED TO TWILIO, ON ANY CHANNEL (15 Sep 2026, it_engineer).
// send_whatsapp refused them from 14 Sep; login_otp, kyc, mobile_otp, send_sms and wa_inbound did
// not. On 14 Sep 21:17-21:23Z an e2e fixture supplier held +971500000042, a check asked login_otp to
// text that number, and Twilio Verify logged four SMS attempts to it (UNDELIVERED, error 30005). A
// number that looks fake is not guaranteed to be unassigned. Every function that reaches Twilio calls
// isDemoPhone() first and records this note instead of sending; <fn>/fixture_number.test.ts proves
// each one makes zero requests to twilio.com for a fixture number. There is no test-code bypass:
// the harness records a demo mobile as verified in the database, so no code is ever checked for one.
export const FIXTURE_CAPTURE_NOTE =
  'captured: reserved fixture mobile (+971 50 000 00xx) - recorded for the rehearsal, never handed to Twilio';
export const FIXTURE_REFUSAL = {
  ok: false, captured: true, code: 'fixture_number',
  error: 'This is a reserved test number. No code or message is ever sent to it, so none can be checked.',
} as const;

/**
 * Which Stripe key pair a caller may use. A demo customer is served ONLY by the test pair, and
 * when that pair is absent the answer is "not configured" — never a fall-through to live. A real
 * customer is never served the test pair, whatever the request says: the switch is derived from
 * the account on the server, not from anything the browser sends.
 */
export function stripeKeyNames(demo: boolean): { secret: string; publishable: string; mode: 'live' | 'test' } {
  return demo
    ? { secret: 'stripe_secret_key_test', publishable: 'stripe_publishable_key_test', mode: 'test' }
    : { secret: 'stripe_secret_key', publishable: 'stripe_publishable_key', mode: 'live' };
}
