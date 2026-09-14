// Checked before any sign-in code is sent (login_otp, mobile_otp, voice_otp).
//
// Two things the IT engineer can change without touching code (duty 11, OTP pumping):
//   * public.otp_blocked_prefix — prefixes that receive no code, via fn_otp_prefix_blocked
//   * public.it_threshold otp_sms_per_ip_hour / otp_signup_global_hour — the hourly ceilings
// Deterministic. If the check itself cannot be read, a code is NOT refused on that account: a broken
// guard must not lock real customers out of sign-in (the same rule rl() in login_otp follows), and the
// failure is returned so the caller logs it.
// deno-lint-ignore no-explicit-any
type Admin = { rpc: (fn: string, args: Record<string, unknown>) => any };

export async function prefixBlocked(admin: Admin, phone: string): Promise<{ blocked: boolean; error?: string }> {
  try {
    const { data, error } = await admin.rpc('fn_otp_prefix_blocked', { p_phone: phone });
    if (error) return { blocked: false, error: error.message };
    return { blocked: data === true };
  } catch (e) {
    return { blocked: false, error: String((e as Error)?.message || e) };
  }
}

/** A ceiling from public.it_threshold, or the given default when it cannot be read. */
export async function otpCeiling(admin: Admin, key: 'otp_sms_per_ip_hour' | 'otp_signup_global_hour', fallback: number): Promise<number> {
  try {
    const { data, error } = await admin.rpc('fn_it_threshold', { p_key: key });
    const n = Number(data);
    return !error && Number.isFinite(n) && n > 0 ? n : fallback;
  } catch {
    return fallback;
  }
}
