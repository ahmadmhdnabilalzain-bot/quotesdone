// The one door for Vercel cron routes (6 Oct 2026, review of #1246). Vercel signs a cron invocation with
// `Authorization: Bearer <CRON_SECRET>`. A route that runs privileged work must refuse when the secret is
// unset or the header is not exactly that: there is no "open when unconfigured" mode.
/** True only when CRON_SECRET is set and the request carries exactly `Bearer <CRON_SECRET>`. */
export function cronAuthorized(req: Request, secret: string | undefined): boolean {
  if (!secret) return false;
  const got = req.headers.get('authorization') || '';
  const want = `Bearer ${secret}`;
  if (got.length !== want.length) return false;
  let d = 0;
  for (let i = 0; i < want.length; i++) d |= got.charCodeAt(i) ^ want.charCodeAt(i);
  return d === 0;
}
