// THE TWO-STEP ADMIN SIGN-IN, AS LOGIC (security checklist audit 10 Nov 2026, open item 1; it_engineer).
//
// src/components/admin/AdminTwoStep.tsx is the screen; this is what it decides, kept apart so
// src/lib/adminTwoStep.test.mjs can drive it with the REAL @supabase/auth-js client over a stubbed auth server
// (enrol -> challenge -> verify -> aal2) without a browser and without reaching production.
//
// The only factor is TOTP from an authenticator app (free on every Supabase plan). A phone factor is never enrolled:
// phone MFA is a paid add-on and the founder ruled on 10 Nov 2026 (ledger 1606) that nothing that costs money is added.
import type { Factor, GoTrueClient } from '@supabase/auth-js';

export type AdminStep = 'email' | 'enrol' | 'challenge' | 'done';
export type Standing = { step: AdminStep; factor: Factor | null; expiresAt: number | null };
export type Enrolment = { factorId: string; qr: string; secret: string };

/** Where this browser's admin session stands: none -> email; aal2 -> done; a verified factor -> challenge; else enrol.
 *  An admin with no authenticator is sent to ENROL, never refused: that is the lock-out safety. */
export async function standing(auth: GoTrueClient): Promise<Standing> {
  const { data: s } = await auth.getSession();
  if (!s.session) return { step: 'email', factor: null, expiresAt: null };
  const { data: aal, error } = await auth.mfa.getAuthenticatorAssuranceLevel();
  if (error || !aal) throw error || new Error('Could not read this session. Sign in again.');
  const { data: f } = await auth.mfa.listFactors();
  const factor = (f?.totp || [])[0] ?? null;   // `totp` lists VERIFIED authenticator factors only
  const step: AdminStep = aal.currentLevel === 'aal2' ? 'done' : factor ? 'challenge' : 'enrol';
  return { step, factor, expiresAt: s.session.expires_at ?? null };
}

/** Starts an authenticator enrolment. A QR shown earlier and never confirmed left an unverified factor; it is removed
 *  first so the new enrolment is not refused and nothing half-made is left on the account. */
export async function startEnrolment(auth: GoTrueClient, today = new Date()): Promise<Enrolment> {
  const { data: f } = await auth.mfa.listFactors();
  for (const stale of (f?.all || []).filter((x) => x.factor_type === 'totp' && x.status === 'unverified')) {
    const { error } = await auth.mfa.unenroll({ factorId: stale.id });
    if (error) throw error;
  }
  const { data, error } = await auth.mfa.enroll({ factorType: 'totp', issuer: 'QuotesDone', friendlyName: 'QuotesDone admin ' + today.toISOString().slice(0, 10) });
  if (error || !data) throw error || new Error('Enrolment did not start.');
  return { factorId: data.id, qr: data.totp.qr_code, secret: data.totp.secret };
}

/** Checks a 6-digit authenticator code against a factor; on success the stored session is aal2. */
export async function verifyCode(auth: GoTrueClient, factorId: string, code: string): Promise<{ ok: true } | { ok: false; reason: 'format' | 'rejected' }> {
  const c = code.replace(/\s+/g, '');
  if (!/^\d{6}$/.test(c)) return { ok: false, reason: 'format' };
  const { error } = await auth.mfa.challengeAndVerify({ factorId, code: c });
  return error ? { ok: false, reason: 'rejected' } : { ok: true };
}
