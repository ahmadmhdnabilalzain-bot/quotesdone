// resend_send — one POST /emails for the code senders (login_otp, kyc), retried ONCE on 429.
//
// Resend allows 10 requests a second per team (resend.com/docs/api-reference/introduction, read
// 21 Sep 2026), shared by every key on the account. On a campaign day send_outbox drains the
// invitation mail on the same account while suppliers ask for sign-in codes, so a code can be refused
// for a busy second. One retry after the Retry-After the response names (default 1 s, capped at 3 s so
// the caller is never kept waiting) turns that into a delivered code; a second refusal is returned as
// false and the caller says so rather than claiming the code was sent.
export type ResendMail = { from: string; to: string; subject: string; html: string };
type Fetch = (url: string, init: RequestInit) => Promise<Response>;

export async function resendWithRetry(key: string, mail: ResendMail, fetchFn: Fetch = fetch, sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))): Promise<boolean> {
  const post = () => fetchFn('https://api.resend.com/emails', { method: 'POST', headers: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' }, body: JSON.stringify(mail) });
  try {
    let r = await post();
    if (r.status === 429) {
      const after = Number(r.headers.get('retry-after'));
      await sleep(Math.min(Number.isFinite(after) && after > 0 ? after * 1000 : 1000, 3000));
      r = await post();
    }
    return r.ok;
  } catch {
    return false;
  }
}
