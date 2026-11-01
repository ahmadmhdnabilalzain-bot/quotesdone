// A BOUNCE THAT COMES BACK AS MAIL (1 Nov 2026, sales_engineer; founder ledger 1423).
// MEASURED: invitations sent through the Microsoft 365 lane get no Resend webhook, so a dead address comes back only as a
// delivery report to supplier@. On 29 Oct the report for sales@mayyashomes.com was stored for review and nothing else
// happened: the lead stayed live, no suppression was written, and the 3-day bounce brake counted 0.
//
// Only a permanent failure from a mail system counts: the sender is mailer-daemon or postmaster, and the report says the
// address does not exist. A full mailbox or a temporary refusal is not a bounce. The caller must also check that we sent
// this address an invitation, because a From header can be forged.
//
// 2 Nov 2026 (customer_support, ledger 1423+): MEASURED six reports in supplier@'s Junk from Microsoft's own sender,
// MicrosoftExchange<hex>@<tenant>.onmicrosoft.com, in Exchange's wording. A refused connection says the server was
// unreachable, not that the address is dead, so it counts only when the report says repeated attempts failed.
const REPORT_SENDER = /^(mailer-daemon|postmaster|microsoftexchange[0-9a-f]*)@/i;
const PERMANENT = /(address not found|does(?:n['’]t| not) exist|no such user|user unknown|recipient not found|wasn['’]?t found at|5\.1\.[01]\b)/i;
const REFUSED = /(refused the connection|connection (?:was )?refused|could(?:n['’]?t| not) connect)/i;
const REPEATED = /repeated attempts/i;
const NAMED = [
  /wasn'?t delivered to\s+<?([^\s<>"']+@[^\s<>"',;]+)/i,
  /final-recipient:\s*rfc822;\s*<?([^\s<>"']+@[^\s<>"',;]+)>?/i,
  /your message to\s+<?([^\s<>"']+@[^\s<>"',;]+?)>?\s+could(?:n['’]?t| not) be delivered/i,
  /delivery has failed to these recipients or groups:[^@]*?([^\s<>"'(]+@[^\s<>"'(),;]+)/i,
];

/** Is this From a mail system's delivery-report sender? The address only; the caller reads the wording. */
export function isDeliveryReportSender(from: unknown): boolean {
  return REPORT_SENDER.test(/([^<>\s"]+@[^<>\s"]+)/.exec(String(from ?? ''))?.[1] ?? '');
}

/** The address that permanently failed, lower-cased, or null when this is not a permanent delivery report. */
export function permanentlyBouncedAddress(from: unknown, text: unknown): string | null {
  const body = String(text ?? '');
  if (!isDeliveryReportSender(from)) return null;
  if (REFUSED.test(body) ? !REPEATED.test(body) : !PERMANENT.test(body)) return null;
  for (const re of NAMED) {
    const m = re.exec(body + ' ');
    if (m) return m[1].replace(/\.+$/, '').toLowerCase();
  }
  return null;
}
