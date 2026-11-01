// A BOUNCE THAT COMES BACK AS MAIL (1 Nov 2026, sales_engineer; founder ledger 1423).
// MEASURED: invitations sent through the Microsoft 365 lane get no Resend webhook, so a dead address comes back only as a
// delivery report to supplier@. On 29 Oct the report for sales@mayyashomes.com was stored for review and nothing else
// happened: the lead stayed live, no suppression was written, and the 3-day bounce brake counted 0.
//
// Only a permanent failure from a mail system counts: the sender is mailer-daemon or postmaster, and the report says the
// address does not exist. A full mailbox or a temporary refusal is not a bounce. The caller must also check that we sent
// this address an invitation, because a From header can be forged.
const REPORT_SENDER = /^(mailer-daemon|postmaster)@/i;
const PERMANENT = /(address not found|does(?:n't| not) exist|no such user|user unknown|recipient not found|5\.1\.[01]\b)/i;
const NAMED = [
  /wasn'?t delivered to\s+<?([^\s<>"']+@[^\s<>"',;]+?)>?[\s.,]/i,
  /final-recipient:\s*rfc822;\s*<?([^\s<>"']+@[^\s<>"',;]+)>?/i,
];

/** The address that permanently failed, lower-cased, or null when this is not a permanent delivery report. */
export function permanentlyBouncedAddress(from: unknown, text: unknown): string | null {
  const body = String(text ?? '');
  const sender = /([^<>\s"]+@[^<>\s"]+)/.exec(String(from ?? ''))?.[1] ?? '';
  if (!REPORT_SENDER.test(sender) || !PERMANENT.test(body)) return null;
  for (const re of NAMED) {
    const m = re.exec(body + ' ');
    if (m) return m[1].replace(/.+$/, '').toLowerCase();
  }
  return null;
}
