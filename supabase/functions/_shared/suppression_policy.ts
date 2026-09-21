// WHAT A SUPPRESSION STOPS (22 Sep 2026, customer_support; independent review of PR #804).
//
// email_suppressions holds two different facts under one table:
//   * a deliverability fact -- a hard bounce, a spam complaint, a guardrail block. The mailbox rejects us
//     or its owner reported us; NOTHING should be sent there, a sign-in code included.
//   * a preference -- reason 'unsubscribe', written by the signed link (source 'link') or by an unsubscribe
//     email (source 'reply'). The person asked us to stop MARKETING them. It is not a request to be locked
//     out of their account.
// Measured on main before this file: login_otp and kyc refused the sign-in / verification code for ANY row,
// so a supplier who clicked "unsubscribe" on an invitation could never sign in again; send_outbox suppressed
// every notification to that address, quote and reveal notices included.
//
// Which mail an opt-out stops: the outreach a person never asked for -- the campaign invitation and its
// registration reminders. send_outbox's holdForNoUnsubscribe marks ALL supplier mail except document requests
// as needing the link, and that stays (the link is on every supplier mail); but an opt-out must not stop a
// registered supplier's requests for quotation: the agreement charges for non-response, and a supplier who
// never received the request would be charged for not answering it. So the list is the cold outreach only.
// A new campaign kind is added HERE, and suppression_policy.test.ts pins the list.

export const OPT_OUT_TYPES: readonly string[] = ['supplier_invite', 'supplier_registration_reminder'];

/** A preference row (the person unsubscribed), as opposed to a deliverability fact. */
export function isOptOut(reason: unknown): boolean {
  return String(reason ?? '').trim().toLowerCase() === 'unsubscribe';
}

/** Does a suppression row with this reason stop a notification of this type? */
export function suppressionStops(reason: unknown, type: unknown): boolean {
  return !isOptOut(reason) || OPT_OUT_TYPES.includes(String(type ?? ''));
}

/** For senders of codes and account mail (login_otp, kyc): only a deliverability fact refuses. */
export function blocksTransactional(reason: unknown): boolean {
  return !isOptOut(reason);
}

// ── AN UNSUBSCRIBE EMAIL IS HONOURED ONLY WHEN WE CAN BELIEVE IT ──
// Svix proves Resend delivered the webhook, not who wrote the mail: a forged From: header would let anyone
// suppress anyone. Measured 22 Sep 2026: GET /emails/receiving/{id} returns the message headers, and Resend's
// receiving MTA (Amazon SES) adds an Authentication-Results header at the top, e.g.
//   "amazonses.com; spf=pass (...) envelope-from=...@send.quotesdone.com; ...; dkim=pass header.i=@quotesdone.com;
//    dmarc=pass header.from=quotesdone.com;"
// Only the FIRST such header counts (a sender can paste their own further down), and only if it is SES's.

const aligned = (d: string, from: string) => d === from || from.endsWith('.' + d) || d.endsWith('.' + from);

/** true when the receiving MTA authenticated the From domain (DMARC pass, or an aligned DKIM/SPF pass). */
export function fromDomainAuthenticated(authResults: unknown, fromEmail: string): boolean {
  const first = Array.isArray(authResults) ? authResults[0] : authResults;
  const ar = String(first ?? '').toLowerCase();
  const dom = String(fromEmail || '').toLowerCase().split('@')[1] || '';
  if (!dom || !/^\s*amazonses\.com;/.test(ar)) return false;
  for (const m of ar.matchAll(/dmarc=pass[^;]*header\.from=([a-z0-9.-]+)/g)) if (aligned(m[1], dom)) return true;
  for (const m of ar.matchAll(/dkim=pass[^;]*header\.(?:i=@?|d=)([a-z0-9.-]+)/g)) if (aligned(m[1], dom)) return true;
  const spf = ar.match(/spf=pass[^;]*envelope-from=[^@;\s]*@([a-z0-9.-]+)/);
  return !!spf && aligned(spf[1], dom);
}

/** Addresses no email may ever suppress: our own domains and the people who run the company. */
export function neverSuppressible(email: string, protectedList: string[]): boolean {
  const e = String(email || '').trim().toLowerCase();
  const dom = e.split('@')[1] || '';
  if (/(^|\.)quotesdone\.(com|ae)$/.test(dom)) return true;
  return protectedList.map((x) => x.trim().toLowerCase()).filter(Boolean).includes(e);
}
