// THE KYC E-MAIL CODE: ONE GUESS IS ONE COUNTED ATTEMPT, EVEN WHEN GUESSES ARRIVE TOGETHER (it_engineer, 17 Nov 2026).
//
// Security audit of 17 Nov (docs/reports/2026-11-17-security-audit.md, finding 5; 10 Nov open item 6). kyc's
// verify_email read `attempts`, compared the code, then wrote `attempts + 1` from the value it had read. Requests sent
// in parallel all read the same count, all passed the 5-try cap, and each got its comparison: the cap held only for
// a caller who waited for each answer. login_otp does the same check inside one locked routine
// (fn_login_otp_email_verify, `for update`), which counts every attempt, the right one included.
//
// Here each comparison first CLAIMS its attempt: `attempts` moves from the value read to one more, only where it
// still holds that value and the code is unused (a compare-and-set, one UPDATE). A request that loses that race
// compares nothing and is told to try again. So at most KYC_EMAIL_MAX_ATTEMPTS comparisons are ever made per code,
// however the guesses are timed. Same counting rule as login_otp: the right guess spends an attempt too.

export type EmailCodeRow = { id: string; expires_at: string; attempts: number | null; token_hash: string | null };

export type EmailCodeDb = {
  /** The newest unused kyc code for this address, or null. */
  newest(): Promise<EmailCodeRow | null>;
  /** attempts: from -> from + 1 where it still reads `from` and used_at is null. True only if this call moved it. */
  claim(id: string, from: number): Promise<boolean>;
  /** Spend the code without verifying it (the cap was reached). */
  burn(id: string): Promise<void>;
  /** The code was entered right: used_at and verified_at. */
  verified(id: string): Promise<void>;
};

export type EmailCodeVerdict = 'ok' | 'no_code' | 'expired' | 'burned' | 'retry' | 'wrong';

export async function checkEmailCode(db: EmailCodeDb, code: string, hash: (c: string) => Promise<string>,
                                     maxAttempts: number, now = new Date()): Promise<EmailCodeVerdict> {
  const row = await db.newest();
  if (!row) return 'no_code';
  if (new Date(row.expires_at) < now) return 'expired';
  const tries = row.attempts || 0;
  if (tries >= maxAttempts) { await db.burn(row.id); return 'burned'; }
  if (!(await db.claim(row.id, tries))) return 'retry';
  // Only the HMAC is compared (16 Nov 2026): no plaintext token is left on any row.
  const match = !!row.token_hash && (await hash(code)) === row.token_hash;
  if (!match) return 'wrong';
  await db.verified(row.id);
  return 'ok';
}
