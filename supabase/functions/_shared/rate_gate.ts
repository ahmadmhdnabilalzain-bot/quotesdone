// ONE ANSWER FROM THE ESTATE'S LIMITER, AND AN OUTAGE IS NOT A YES (it_engineer, 17 Nov 2026).
//
// The security audit of 17 Nov (docs/reports/2026-11-17-security-audit.md, finding 5) found complaint_status and kyc
// asking public.rl_check and answering "allowed" when it errored or threw. A database fault therefore removed the cap
// on ticket lookups and on e-mail code guesses at the moment nobody was watching. login_otp closed the same hole on
// 6 Oct (its own `Gate`). This is that answer, shared: 'ok', 'limited', or 'down' when the limiter could not say.
// Each caller refuses on 'down' with a "try again" message, never a "you tried too often" one.
//
// Other functions still carry their own fail-open copy (contact_submit, role_guard, site_assistant,
// marketing_social_inbox); the audit did not rank them and this change does not touch them.

export type Gate = 'ok' | 'limited' | 'down';

type Rpc = (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: unknown; error: unknown }>;

export async function rateGate(rpc: Rpc, key: string, limit: number, seconds: number): Promise<Gate> {
  try {
    const { data, error } = await rpc('rl_check', { p_key: key, p_limit: limit, p_seconds: seconds });
    if (error) return 'down';
    return data === false ? 'limited' : 'ok';
  } catch (_e) {
    return 'down';
  }
}
