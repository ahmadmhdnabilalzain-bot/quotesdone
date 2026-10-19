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
export type UrlSession = { access_token: string; refresh_token: string };
type Win = {
  location: { pathname: string; search: string; hash: string };
  history: { state: unknown; replaceState: (s: unknown, t: string, u: string) => void };
};

const AUTH_KEYS = /(?:^#|&)(?:access_token|refresh_token|error|error_code|error_description)=/;

// SESSION FIXATION (CWE-384 audit, 19 Oct 2026; seat: it_engineer). A fragment is attacker-craftable: a link to
// /portal#access_token=<attacker's>&refresh_token=<attacker's> used to REPLACE whoever was signed in, so the victim
// went on working (uploading a licence, a bank letter) inside the attacker's account. A fragment session for a
// DIFFERENT user than the one already signed in on this browser is now dropped; the stored session stays. To
// switch accounts, sign out first. Residual: a browser with no session still adopts a crafted link (implicit flow);
// the upgrade is the PKCE flow, whose code is useless without the verifier held in the browser that asked for it.
const subOf = (jwt: string | null | undefined): string => {
  try { const b = String(jwt || '').split('.')[1] || ''; return String(JSON.parse(atob(b.replace(/-/g, '+').replace(/_/g, '/'))).sub || ''); } catch { return ''; }
};

export function takeAuthFragment(win: Win | undefined = (globalThis as unknown as { window?: Win }).window, currentToken?: string | null): UrlSession | null {
  if (!win) return null;
  const hash = String(win.location.hash || '');
  if (!AUTH_KEYS.test(hash)) return null;
  const p = new URLSearchParams(hash.slice(1));
  try { win.history.replaceState(win.history.state, '', win.location.pathname + win.location.search); }
  catch (e) { console.error('takeAuthFragment: the session could not be removed from the address bar', e); }
  const access_token = p.get('access_token') || '';
  const refresh_token = p.get('refresh_token') || '';
  if (!access_token || !refresh_token) return null;
  const held = subOf(currentToken);
  if (held && subOf(access_token) !== held) { console.error('takeAuthFragment: a link for another account was ignored; this browser stays signed in as before'); return null; }
  return { access_token, refresh_token };
}
