// A SESSION HANDED OVER IN THE URL IS TAKEN OUT OF THE URL IN PLACE (customer-portal audit 21 Sep
// 2026, item 29; seat: it_engineer).
//
// Measured on production, 21 Sep 2026, with a ZZ DEMO supplier: a Supabase magic link lands on
// /portal#access_token=…&refresh_token=…. supabase-js (auth-js 2.111, detectSessionInUrl) read the
// session and then cleared it with `window.location.hash = ''` — an assignment, which PUSHES a new
// history entry. The entry the browser landed on, token and refresh token included, stayed one Back
// press away (the harness pressed Back and read the token URL again).
//
// Now: supaClient() is built with detectSessionInUrl off, and each portal calls this FIRST on mount.
// It rewrites the CURRENT entry with history.replaceState — no new entry, nothing left behind — and
// hands the pair to the portal, which signs in with it the same way a code sign-in does (onAuth ->
// setSession). A fragment that is not a session (the customer portal's own #account, #spatial …) is
// left alone. An auth ERROR fragment is stripped too; it carries nothing to sign in with.
// Tested in authFragment.test.mjs; the nightly journey (scripts/e2e/journey_audit_buttons.mjs) opens
// a real magic link and presses Back.
type Win = {
  location: { pathname: string; search: string; hash: string };
  history: { state: unknown; replaceState: (s: unknown, t: string, u: string) => void };
};

const AUTH_KEYS = /(?:^#|&)(?:access_token|refresh_token|error|error_code|error_description)=/;

// SESSION FIXATION (CWE-384 audit, 19 Oct 2026; seat: it_engineer). A fragment is attacker-craftable: a link to
// /portal#access_token=<attacker's>&refresh_token=<attacker's> signed the visitor into the ATTACKER's account, where
// they would upload a licence or a bank letter. No product flow delivers a session in the URL any more: sign-in is
// OTP codes only (login_otp verifies the token_hash server-side and returns the session in its JSON body), there is
// no signUp/OAuth/password-reset return. So a URL session is NEVER adopted: the fragment is stripped from the
// address bar (it must not sit in history) and dropped. Always returns null; kept as a function so both portals
// keep stripping it first. Admin-generated magic links (scripts/e2e founder_demo_tour, journey_audit) no longer
// sign in by design.
export function takeAuthFragment(win: Win | undefined = (globalThis as unknown as { window?: Win }).window): null {
  if (!win) return null;
  const hash = String(win.location.hash || '');
  if (!AUTH_KEYS.test(hash)) return null;
  try { win.history.replaceState(win.history.state, '', win.location.pathname + win.location.search); }
  catch (e) { console.error('takeAuthFragment: the session could not be removed from the address bar', e); }
  console.error('takeAuthFragment: a session in the URL was dropped; sign-in is by code only');
  return null;
}
