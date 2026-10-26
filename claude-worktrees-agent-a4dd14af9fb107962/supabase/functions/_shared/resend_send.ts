// resend_send — one POST /emails for the code senders (login_otp, kyc), retried ONCE on 429.
//
// Resend allows 10 requests a second per team (resend.com/docs/api-reference/introduction, read
// 21 Sep 2026), shared by every key on the account. On a campaign day send_outbox drains the
// invitation mail on the same account while suppliers ask for sign-in codes, so a code can be refused
// for a busy second. One retry after the Retry-After the response names (default 1 s, capped at 3 s so
// the caller is never kept waiting) turns that into a delivered code; a second refusal is returned as
// false and the caller says so rather than claiming the code was sent.
//
// A RESERVED ADDRESS NEVER REACHES RESEND (22 Sep 2026, it_engineer). The harness signs in and
// confirms email on @example.invalid / ZZ DEMO fixtures; login_otp and kyc minted the code and posted
// it, and Resend recorded 6 hard bounces against our sending domain. send_outbox has refused these
// domains since 3 Sep; this is the same rule (isDemoEmail) at the one door both code senders use.
// The answer is `true` so the harness flow is unchanged: nobody can own a reserved mailbox, so
// nobody was waiting for the mail. resend_send.test.ts proves no request leaves for one.
import { isDemoEmail } from './demo_identity.ts';

export type ResendMail = { from: string; to: string; subject: string; html: string; reply_to?: string };
type Fetch = (url: string, init: RequestInit) => Promise<Response>;

export async function resendWithRetry(key: string, mail: ResendMail, fetchFn: Fetch = fetch, sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))): Promise<boolean> {
  if (isDemoEmail(mail.to)) {
    console.log('resend_send: suppressed - reserved test address, never handed to Resend');
    return true;
  }
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
