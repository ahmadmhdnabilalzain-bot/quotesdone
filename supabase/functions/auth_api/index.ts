// Disabled 27 Jul 2026. Permanently retired — password signup surface, replaced by login_otp (passwordless codes) + kyc.
// Reason: unauthenticated and zero callers anywhere in the repo (src/ and functions/ both grep clean; only docs and a
// comment in supplier_api still name it). Its signup_customer / signup_supplier path minted a CONFIRMED auth user with a
// caller-chosen password for any email that had no auth user yet, so anyone could squat the account of a prospect or a
// competitor before that person ever registered — and, because every account is created email_confirm:true, arrive
// pre-verified. The 18 Jul 2026 fix closed the takeover-of-an-existing-account variant; this closes the squatting one by
// removing the surface. Do not revive: sign-in is login_otp, account completion is kyc, password reset no longer exists.
Deno.serve(() => new Response(JSON.stringify({ error: 'disabled' }), { status: 410, headers: { 'Content-Type': 'application/json' } }));
