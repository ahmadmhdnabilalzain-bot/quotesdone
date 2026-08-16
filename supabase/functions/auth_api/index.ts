// Disabled 27 Jul 2026. Permanently retired — password signup surface, replaced by login_otp (passwordless codes) + kyc.
// Reason: unauthenticated and zero callers anywhere in the repo (src/ and functions/ both grep clean; only docs and a
// comment in supplier_api still name it). Its signup_customer / signup_supplier path minted a CONFIRMED auth user with a
// caller-chosen password for any email that had no auth user yet, so anyone could squat the account of a prospect or a
// competitor before that person ever registered — and, because every account is created email_confirm:true, arrive
// pre-verified. The 18 Jul 2026 fix closed the takeover-of-an-existing-account variant; this closes the squatting one by
// removing the surface. Do not revive: sign-in is login_otp, account completion is kyc, password reset no longer exists.
// The 410 body names itself and its replacement. A caller that hits a retired surface used to
// receive {"error":"disabled"} and learn nothing about where the surface went — and, because
// "disabled" is 8 characters, deploy parity could derive no signature from this function and
// reported it UNVERIFIED rather than verified. One honest sentence fixes both.
Deno.serve(() => new Response(JSON.stringify({
  error: 'disabled',
  fn: 'auth_api',
  retired: 'auth_api was permanently retired on 27 Jul 2026: its signup path let anyone claim an unregistered email. Sign-in is login_otp, account completion is kyc.',
}), { status: 410, headers: { 'Content-Type': 'application/json' } }));
