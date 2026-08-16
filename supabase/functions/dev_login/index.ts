// Disabled. This endpoint was a temporary QA helper and is permanently turned off.
// Names itself in the 410 body: a caller learns which surface is gone, and deploy parity gains the
// distinctive literal it needs to report this function verified instead of UNVERIFIED.
Deno.serve(() => new Response(JSON.stringify({
  error: 'disabled',
  fn: 'dev_login',
  retired: 'dev_login was retired: a development sign-in shortcut has no place on a production project. Sign in through login_otp.',
}), { status: 410, headers: { 'Content-Type': 'application/json' } }));
