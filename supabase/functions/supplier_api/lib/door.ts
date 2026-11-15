// supplier_api — WHO IS ASKING, AND IS HE BARRED: the sign-in and the sanctions read at the door, together (15 Nov 2026,
// customer_support; the code e-mail to the registration form measured 3,026 and 3,078 ms against 3,000, create_company 797 ms of
// server time at 15:13:57).
//
// Every supplier_api request waited on auth.getUser (the auth server), THEN on sanctionedEmail (public.sanctions_ban) for the
// address getUser answered: two round trips in series before any action. The address is already in the token (the `email` claim
// GoTrue signs into every session it issues), so the ban read leaves beside getUser for that address, and is USED only when the
// address getUser verified is the same one. Any other case (no claim, a claim that differs, a token getUser refuses) asks the ban
// for the verified address after getUser, exactly as before. So the refusal is decided, as before, from public.sanctions_ban for
// the address auth.getUser verified, and nothing is answered before getUser has verified the token: the early read only saves the
// wait. A ban read that fails still fails closed (sanctionedEmail throws; the handler's catch answers unexpected_error), and an
// early read that is not used is observed here so its failure never surfaces unhandled.
// Prevented by: supplier_api/door.test.ts.
import type { User } from 'jsr:@supabase/supabase-js@2';

/** The lower-cased `email` claim of a JWT, read WITHOUT verifying it ('' when there is none). Only ever a hint for an early read. */
export function emailClaimOf(jwt: string): string {
  try {
    const part = String(jwt || '').split('.')[1] || '';
    if (!part) return '';
    const b64 = part.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (part.length % 4)) % 4);
    const claims = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))));
    return typeof claims?.email === 'string' ? claims.email.trim().toLowerCase() : '';
  } catch {
    return '';
  }
}

export type DoorDeps = {
  getUser: (jwt: string) => Promise<User | null>;
  sanctioned: (email: string) => Promise<boolean>;
};
export type Door = { kind: 'unauthorized' } | { kind: 'sanctioned' } | { kind: 'in'; user: User; email: string };

/** The door's verdict: getUser verifies the token; the ban is read for the address it verified (started early when the token names it). */
export async function atTheDoor(jwt: string, deps: DoorDeps): Promise<Door> {
  const hinted = emailClaimOf(jwt);
  const early = hinted ? deps.sanctioned(hinted) : null;
  early?.catch(() => {});   // awaited below when it is used; this only stops an unused one failing unobserved
  const user = await deps.getUser(jwt);
  if (!user || !user.email) return { kind: 'unauthorized' };
  const email = user.email.toLowerCase();
  if (await (early && hinted === email ? early : deps.sanctioned(email))) return { kind: 'sanctioned' };
  return { kind: 'in', user, email };
}

// THE PORTAL'S PREFLIGHT WARM (15 Nov 2026, customer_support; src/components/portal/supplier/api.ts preflightNow). The portal sends
// {"action":"warm"} with the anonymous key beside the code check, so the browser's CORS preflight for supplier_api is paid while
// login_otp answers and create_company does not wait on it. Answered 204 before the sign-in check: no session, no database read,
// nothing done (like the x-qd-warm keep-warm, which a browser cannot send: that header is not in the preflight's allow-list).
/** True for the portal's warm request; never for an internal door (those carry __secret). */
export function warmOnly(peek: unknown): boolean {
  const p = peek as { action?: unknown; __secret?: unknown } | null;
  return !!p && p.action === 'warm' && p.__secret == null;
}
