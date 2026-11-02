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
// 'supplier_rfq_widened_invite' (22 Sep 2026, ceo): a supplier invited only by the short-of-quotes sweep, to a
// request he was not originally matched to -- cold outreach, so an opt-out stops it. The SQL mirror is
// public.fn_opt_out_types() (scripts/sql/complaints_quotes_reveals_and_support_replies_each_run_on_a_clock.sql);
// scripts/checks/every_duty_has_an_owner_and_a_clock.test.mjs fails if the two lists differ.

// 'supplier_invite_nudge' (28 Oct 2026, sales_engineer; ledger 1401 audit, S6): the day-3/7/14 reminder of an unopened
// invitation is the same cold outreach. It was missing, so an unsubscribe did not stop a nudge already queued (the
// onboarding duty queues it after midnight Dubai for the 09:00 window): send_outbox's suppressionStops answered false.
// fn_email_type_is_marketing already counted it as marketing; the SQL mirror moves with this list
// (scripts/sql/a_supplier_who_said_stop_is_never_nudged.sql).
export const OPT_OUT_TYPES: readonly string[] = ['supplier_invite', 'supplier_invite_nudge', 'supplier_registration_reminder', 'supplier_rfq_widened_invite'];

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
//
// THE SHAPE OF A REPEATED HEADER, MEASURED (re-review, 22 Sep 2026, on the two real inbound mails):
// `headers` is an object keyed by lower-case name. A header that occurs ONCE comes back as a plain string.
// A header that occurs more than once does NOT come back as an array: `received` (3 instances in the raw
// message) came back as ONE string holding a JSON-encoded array ('["from mail-pj2 ...", ...]'), and
// `dkim-signature` (2 instances) as a JSON-encoded array of parsed objects. So a sender who adds their own
// Authentication-Results makes the value a '['-string, and one who hides a second verdict inside a value
// leaves a second "amazonses.com;" in it. Both are refused here rather than parsed: the verdict is read
// ONLY from a plain string that is exactly one SES header, clause by clause, and anything else fails closed
// (the caller keeps the mail for review and suppresses nothing).

const aligned = (d: string, from: string) => d === from || from.endsWith('.' + d) || d.endsWith('.' + from);

/** true when the receiving MTA authenticated the From domain (DMARC pass, or an aligned DKIM/SPF pass). */
// A REPEATED HEADER FROM THE SENDER'S OWN MAIL SYSTEM (24 Sep 2026, marketing). Microsoft 365 stamps its own
// internal Authentication-Results on every message it sends ("dkim=none (message not signed) header.d=none;
// dmarc=none action=none header.from=..."), so EVERY Outlook reply arrives with two instances and Resend hands
// them over as one JSON-encoded array. Refusing every '['-string refused the founder's own "Approve" to the
// September calendar (inbound_messages 162: SES wrote spf=pass and dmarc=pass header.from=quotesdone.com; the
// outcome was not_authenticated). SES always adds its own header, so a sender-supplied SES-looking entry makes
// TWO SES entries and still fails closed; an entry that is not SES's is ignored, because only the receiving
// server's verdict was ever trusted.
function sesHeaderOf(authResults: unknown): string | null {
  if (typeof authResults !== 'string') return null;                       // missing, or an array object
  const raw = authResults.trim();
  if (!raw.startsWith('[')) return raw;
  let list: unknown;
  try { list = JSON.parse(raw); } catch { return null; }
  if (!Array.isArray(list) || !list.every((x) => typeof x === 'string')) return null;
  const ses = (list as string[]).filter((x) => /^amazonses\.com\s*;/i.test(x.trim()));
  return ses.length === 1 ? ses[0].trim() : null;                          // none, or two SES verdicts: ambiguous
}

export function fromDomainAuthenticated(authResults: unknown, fromEmail: string): boolean {
  const one = sesHeaderOf(authResults);
  if (one === null) return false;
  const ar = one.toLowerCase();
  const dom = String(fromEmail || '').trim().toLowerCase().split('@')[1] || '';
  if (!dom || /[\r\n]/.test(ar)) return false;
  if (!ar.startsWith('amazonses.com;')) return false;                      // not SES's, or a JSON list of several
  // Clauses of THIS header only. Comments are dropped first; a property clause (envelope-from=, header.from=)
  // belongs to the method clause before it, which is how SES writes spf=pass (...) client-ip=...; envelope-from=...
  const clauses = ar.slice('amazonses.com;'.length).replace(/\([^()]*\)/g, ' ').split(';').map((c) => c.trim()).filter(Boolean);
  // A second authserv-id clause is a second verdict hidden in the value: ambiguous. (Counted as a CLAUSE, not
  // as text -- SES's own "helo=a14-56.smtp-out.amazonses.com" is part of a genuine header.)
  if (clauses.some((c) => /^amazonses\.com\b/.test(c))) return false;
  return clausesAuthenticate(clauses, dom);
}

function clausesAuthenticate(clauses: string[], dom: string): boolean {
  let method = '', result = '';
  for (const c of clauses) {
    const mr = c.match(/^(spf|dkim|dmarc)=([a-z]+)\b/);
    if (mr) { method = mr[1]; result = mr[2]; }
    if (result !== 'pass') continue;
    const d = method === 'dmarc' ? c.match(/\bheader\.from=([a-z0-9.-]+)/)
      : method === 'dkim' ? c.match(/\bheader\.(?:i=@?|d=)([a-z0-9.-]+)/)
      : c.match(/(?:^|\s)envelope-from=[^@\s]*@([a-z0-9.-]+)/);
    if (d && aligned(d[1], dom)) return true;
  }
  return false;
}

// A REPLY TO THE MICROSOFT 365 MAILBOX (19 Oct 2026, marketing + it_engineer, release review of #1524). With the
// invitation's body link gone, "reply stop" is a stated opt-out, and such a reply reaches resend_inbound through
// _shared/m365_reply_inbox.ts, never through SES: its headers are Graph's internetMessageHeaders, where Exchange
// Online Protection's own Authentication-Results is the FIRST instance (headersOf keeps the first; a header the
// sender wrote sits below the ones the receiving server prepends). EOP writes no authserv-id:
//   "spf=pass (sender IP is ...) smtp.mailfrom=example.com; dkim=pass (signature was verified) header.d=example.com;
//    dmarc=pass action=none header.from=example.com;compauth=pass reason=100"
// fromDomainAuthenticated refused it ("not SES's"), so every M365 "stop" went to review and nothing was suppressed.
// Only the caller decides that a delivery came over that lane (its email_id carries the m365: prefix, set by our own
// signed handover); this reads the one EOP verdict with the same clause rules, and fails closed on anything else.
export function microsoftDomainAuthenticated(authResults: unknown, fromEmail: string): boolean {
  if (typeof authResults !== 'string') return false;
  const ar = authResults.trim().toLowerCase();
  const dom = String(fromEmail || '').trim().toLowerCase().split('@')[1] || '';
  if (!dom || !ar || ar.startsWith('[') || /[\r\n]/.test(ar) || ar.startsWith('amazonses.com')) return false;
  const clauses = ar.replace(/\([^()]*\)/g, ' ').split(';').map((c) => c.trim()).filter(Boolean)
    .map((c) => c.replace(/(?:^|\s)smtp\.mailfrom=([a-z0-9.-]+)/, ' envelope-from=x@$1').trim());
  return clausesAuthenticate(clauses, dom);
}

/** Did the receiving server authenticate the From domain, read on the lane the mail arrived by: EOP's verdict for a reply
 *  handed in from the Microsoft 365 mailbox (provider id 'm365:...', set only by our own signed handover), SES's for the
 *  rest. Review of #1699, 28 Oct 2026: raw.sender_authenticated used SES's reader alone, so every invited supplier's reply
 *  (they all arrive through the M365 mailbox) was stored unauthenticated (3 of 3 live m365 rows) and email_triage never
 *  gave a verified lead its own facts. The unsubscribe path above already read the lane this way. */
export function senderAuthenticated(providerEmailId: unknown, authResults: unknown, fromEmail: string): boolean {
  return String(providerEmailId || '').startsWith('m365:') ? microsoftDomainAuthenticated(authResults, fromEmail)
    : fromDomainAuthenticated(authResults, fromEmail);
}

/** The headers a tenant-written delivery report can prove itself by (null = absent). */
export type TenantStamp = { authAs?: string | null; isNdr?: string | null; authResults?: string | null; arcResults?: string | null };
/** OUR tenant's system senders only: Exchange's own NDR address and postmaster, on our tenant's onmicrosoft domain (the
 *  sender of the 6 measured NDRs, 29-30 Oct) or quotesdone.com. Any other tenant is someone else's Exchange. */
const SYSTEM_SENDER = /^(microsoftexchange[0-9a-f]{32}|postmaster)@(netorgft20811795\.onmicrosoft\.com|quotesdone\.com)$/i;

/** Our own tenant's Exchange wrote it, or null (2 Nov 2026, final review of #1792). ONE proof only:
 *  X-MS-Exchange-Organization-AuthAs: Internal on a delivery handed in from the M365 mailbox (provider id 'm365:', our own
 *  signed handover) from our tenant's system sender. Exchange's header firewall strips X-MS-Exchange-Organization-* from
 *  mail arriving from outside, so the value is our organisation's own.
 *  Refused on purpose: X-MS-Exchange-Message-Is-Ndr (not stripped: anyone can set it); ARC-Authentication-Results (any hop
 *  writes it); a DMARC pass for quotesdone.com (our SPF includes shared senders, so others can pass as us).
 *  Fails closed on everything else. The headers stay in TenantStamp for the read-only measurement (m365_ndr_headers). */
export function tenantStampOf(providerEmailId: unknown, h: TenantStamp, fromEmail: string): 'auth_as_internal' | null {
  const from = (String(fromEmail || '').match(/[^<>\s"]+@[^<>\s"]+/)?.[0] || '').toLowerCase();
  if (!String(providerEmailId || '').startsWith('m365:') || !SYSTEM_SENDER.test(from)) return null;
  return typeof h.authAs === 'string' && h.authAs.trim().toLowerCase() === 'internal' ? 'auth_as_internal' : null;
}
export function exchangeInternal(providerEmailId: unknown, h: TenantStamp, fromEmail: string): boolean {
  return tenantStampOf(providerEmailId, h, fromEmail) !== null;
}
/** The stamp's headers out of a lower-cased header map (m365_reply_inbox headersOf). */
export function stampHeaders(get: (k: string) => string | null | undefined): TenantStamp {
  const v = (k: string) => { const x = get(k); return x == null ? null : String(x); };
  return { authAs: v('x-ms-exchange-organization-authas'), isNdr: v('x-ms-exchange-message-is-ndr'),
           authResults: v('authentication-results'), arcResults: v('arc-authentication-results') };
}

/** Addresses no email may ever suppress: our own domains and the people who run the company. */
export function neverSuppressible(email: string, protectedList: string[]): boolean {
  const e = String(email || '').trim().toLowerCase();
  const dom = e.split('@')[1] || '';
  if (/(^|\.)quotesdone\.(com|ae)$/.test(dom)) return true;
  return protectedList.map((x) => x.trim().toLowerCase()).filter(Boolean).includes(e);
}
