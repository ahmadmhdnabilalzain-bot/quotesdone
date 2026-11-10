// ADMIN POWER NEEDS A TWO-STEP SESSION (security checklist audit 10 Nov 2026, open item 1; it_engineer).
//
// Measured 10 Nov 2026: ten edge functions turned a signed-in JWT into admin power with the same inline
// test — the account's e-mail is in app_secrets.admin_emails — and nothing else. The founder signs in with
// an e-mail code (or the SMS code to admin_mfa_phone), so whoever reads that mailbox, or holds that SIM, was
// the admin of refunds_api, accountant, ceo_agent, it_engineer, marketing, sales_engineer, quote_compare,
// compliance_archive, pdf_native and extract_text. `admin_mfa_sessions` was retired earlier and nothing
// replaced it.
//
// This is now the ONE place a JWT becomes an admin, and it asks two questions, not one:
//   1. is the account's e-mail in admin_emails (unchanged), and
//   2. does THIS token carry `aal: 'aal2'` — Supabase Auth's own claim that the session passed a second
//      factor. The only factor this estate enrols is TOTP from an authenticator app (free on every plan).
//      Phone/SMS MFA is a paid Supabase add-on and the founder ruled on 10 Nov 2026 (ledger 1606) that
//      nothing that costs money is added, so a phone factor is never offered and never required here.
// An admin whose token is aal1 gets 403 `two_step_required` with the step named, and is SENT TO ENROLMENT
// when no authenticator is enrolled yet (`factor: 'none'`) — never refused forever. That is the lock-out
// safety: the first factor still opens the door to /admin, where the second factor is set up.
// Recovery when the authenticator is lost: docs/runbooks/admin-two-step-sign-in.md.
//
// WHY THE CLAIM CAN BE READ FROM THE PAYLOAD. signedInUser() has already had the auth server accept this
// exact token (GET /auth/v1/user verifies the signature and expiry), so the payload read below is the
// payload the auth server just vouched for. A token whose `sub` is not the user it resolved to is refused.
//
// What this does NOT change: the internal credential (`__secret`, requireInternal) is not a JWT and keeps
// its own door — the seats, the cron jobs and the founder's Claude sessions are unaffected. Customers and
// suppliers are not admins and need no second factor; for them every caller behaves exactly as before.
// Prevented by: _shared/admin_session.test.ts (the decision), <fn>/two_step.test.ts (each real handler) and
// scripts/checks/every_admin_door_requires_a_two_step_session.test.mjs (no function reads admin_emails
// to grant power without this module).
import { signedInUser, AUTH_TIMEOUT_MS } from './signed_in_user.ts';

type AuthUser = { id: string; email?: string | null; factors?: { factor_type?: string; status?: string }[] | null };
type AuthLike = {
  auth: { getUser: (jwt: string) => Promise<{ data: { user: AuthUser | null }; error: { status?: number; name?: string } | null }> };
};
export type SecretReader = (key: string) => Promise<string | null | undefined>;

/** Where the second factor is set up and entered. Named in every refusal so the step is never a guess. */
export const TWO_STEP_URL = 'https://quotesdone.com/admin';

/** app_secrets.admin_emails, parsed the way every one of the ten sites parsed it before. */
export function adminList(raw: string | null | undefined): string[] {
  return String(raw || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
}

/** The payload of a JWT, or null. Only ever read AFTER the auth server accepted the same token. */
export function jwtClaims(jwt: string): Record<string, unknown> | null {
  try {
    const seg = jwt.split('.')[1] || '';
    const b64 = seg.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(seg.length / 4) * 4, '=');
    const v = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))));
    return v && typeof v === 'object' ? v as Record<string, unknown> : null;
  } catch (_e) { return null; }
}

/** 'verified' if an authenticator app is enrolled and confirmed, 'unverified' if one was started, else 'none'. */
export function totpFactor(user: AuthUser): 'verified' | 'unverified' | 'none' {
  const totp = (user.factors || []).filter((f) => f && f.factor_type === 'totp');
  if (totp.some((f) => f.status === 'verified')) return 'verified';
  return totp.length ? 'unverified' : 'none';
}

export type TwoStepBody = { error: 'two_step_required'; step: 'enrol' | 'challenge'; message: string; url: string };

/** The 403 body: names the step, and says which one this account is at. Carries no e-mail. */
export function twoStepBody(factor: 'verified' | 'unverified' | 'none'): TwoStepBody {
  return factor === 'verified'
    ? { error: 'two_step_required', step: 'challenge', url: TWO_STEP_URL,
      message: 'Two-step sign-in required: this admin action needs a session that has passed the authenticator-app code. Sign in at ' + TWO_STEP_URL + ' and enter the 6-digit code from your authenticator app.' }
    : { error: 'two_step_required', step: 'enrol', url: TWO_STEP_URL,
      message: 'Two-step sign-in required: no authenticator app is enrolled on this admin account yet. Sign in at ' + TWO_STEP_URL + ' to enrol one (a QR code for Google Authenticator, Microsoft Authenticator, 1Password or similar); admin actions open once it is set up.' };
}

export type AdminCaller =
  /** admin_emails AND an aal2 session: admin power. */
  | { kind: 'admin'; email: string; userId: string }
  /** admin_emails, but this session has one factor: refuse with 403 and the step. */
  | { kind: 'two_step_required'; status: 403; body: TwoStepBody }
  /** signed in, not an admin: the caller's own non-admin path runs exactly as before. */
  | { kind: 'not_admin'; email: string; userId: string }
  /** no usable session (missing, malformed, expired, refused, or auth unavailable). */
  | { kind: 'signed_out'; status: 401 | 503; reason: string };

/** The one door from a JWT to admin power. */
export async function adminCaller(client: AuthLike, readSecret: SecretReader, authHeader: string | null,
  timeoutMs = AUTH_TIMEOUT_MS): Promise<AdminCaller> {
  const who = await signedInUser(client, authHeader, timeoutMs);
  if (!who.ok) return { kind: 'signed_out', status: who.status, reason: who.reason };
  const userId = String(who.user.id || '');
  const allow = adminList(await readSecret('admin_emails'));
  if (!allow.includes(who.email)) return { kind: 'not_admin', email: who.email, userId };
  const claims = jwtClaims(String(authHeader || '').replace(/^Bearer\s+/i, '').trim());
  // An admin e-mail on a token that is not this user's own is no session at all.
  if (!claims || claims.sub !== userId) return { kind: 'signed_out', status: 401, reason: 'subject_mismatch' };
  if (claims.aal !== 'aal2') return { kind: 'two_step_required', status: 403, body: twoStepBody(totpFactor(who.user as AuthUser)) };
  return { kind: 'admin', email: who.email, userId };
}
