// Disabled. Temporary QA session minter, permanently turned off after the launch-readiness audit.
// Names itself in the 410 body: a caller learns which surface is gone, and deploy parity gains the
// distinctive literal it needs to report this function verified instead of UNVERIFIED.
Deno.serve(() => new Response(JSON.stringify({
  error: 'disabled',
  fn: 'qa_login',
  retired: 'qa_login was retired: a test sign-in shortcut has no place on a production project. Sign in through login_otp.',
}), { status: 410, headers: { 'Content-Type': 'application/json' } }));
