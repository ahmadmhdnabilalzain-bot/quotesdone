// WHICH inbound_messages ROWS ARE A CUSTOMER'S OWN CORRESPONDENCE.
//
// Seen live 14 Sep 2026, customer portal /me -> Messages, signed in as the founder: the e-mail
// channel showed "Fw: Renewal receipt for order #4161152146 — [expense subscription] GoDaddy 40.95
// AED ... accountant historical sweep, Resend inbound id ...". messages_api joins inbound_messages
// on the signed-in address alone, and the founder's address is both a customer and the permitted
// receipt forwarder, so every receipt he forwarded to the accountant read as his customer mail.
//
// A row is back-office mail, never a customer thread, when ANY of these holds:
//   1. it was addressed to one of our internal mailboxes (expenses@ is the accountant's intake —
//      the same address resend_inbound and accountant each hold as EXPENSE_MAILBOX; docs@ and
//      supplier@ are supplier intake; management@ is the company's own). info@ is NOT internal:
//      it is where customers write to us.
//   2. owner_role is set — fn_receipt_hand_to_bookkeeper stamps it on rows a seat owns (6 Sep 2026).
//   3. its body carries the tag the accountant / receipt path writes: "[expense ...]",
//      "[REFUSED — ...]", "[HELD — ...]", "[receipt received but NOT booked ...]".
import { INVITATION_MAILBOX, isUnsubscribeRequest } from './unsubscribe_mailbox.ts';
export const EXPENSE_MAILBOX = 'expenses@mail.quotesdone.com';
const INTERNAL_LOCALS = new Set(['expenses', 'docs', 'supplier', 'management']);
const OUR_DOMAIN = /^(?:mail\.)?quotesdone\.com$/;
const BACK_OFFICE_TAG = /^\[(?:expense|receipt|refused|held)\b/i;

export function isInternalMailbox(addr: unknown): boolean {
  return String(addr ?? '').toLowerCase().split(/[,;]/).some((a) => {
    const m = a.trim().match(/<?([^<>\s]+)@([^<>\s]+?)>?$/);
    if (!m) return false;
    return (m[1] + '@' + m[2]) === EXPENSE_MAILBOX || (OUR_DOMAIN.test(m[2]) && INTERNAL_LOCALS.has(m[1]));
  });
}

export function isCustomerCorrespondence(row: { to_email?: unknown; owner_role?: unknown; body?: unknown }): boolean {
  if (row.owner_role) return false;
  if (BACK_OFFICE_TAG.test(String(row.body ?? '').trim())) return false;
  return !isInternalMailbox(row.to_email);
}

// ── WHICH MAIL IS ANSWERED BY THE MACHINE (28 Sep 2026, customer_support) ──────────────────────────────
// Founder: a customer gets a reply in under a minute, and no person is brought in unless the customer asks
// for one. email_triage therefore answers every inbound mail EXCEPT these, which must never get an
// automatic reply. Every rule reads the sender's IDENTITY (address, RFC headers, attachment type), never
// what the mail says - the "no word matching" ruling of 23 Sep 2026 is about meaning, and none of these
// is a reading of meaning:
//   founder        the founder's own addresses (admin_emails, founder_email): he is not a customer;
//   internal       back-office rows (isCustomerCorrespondence) and our own domains;
//   bounce         mailer-daemon / postmaster, or a multipart/report delivery-status message;
//   no_reply       a no-reply, notification or verification sender (LinkedIn's security-noreply@, 23 Sep);
//   auto_submitted RFC 3834 Auto-Submitted other than "no": a machine wrote it, and a reply would loop;
//   calendar       a calendar reply: a text/calendar part, or our calendar+ / plan+ reply addresses.
export type NoAutoReply = 'founder' | 'internal' | 'bounce' | 'no_reply' | 'auto_submitted' | 'calendar' | 'daily_answer_cap';
export interface MailFacts {
  from_email?: unknown; to_email?: unknown; owner_role?: unknown; body?: unknown;
  /** inbound_messages.raw as resend_inbound stores it: message_id, auto_submitted, content_type, calendar. */
  raw?: { auto_submitted?: unknown; content_type?: unknown; calendar?: unknown; x_autoreply?: unknown; precedence?: unknown; list_unsubscribe?: unknown } | null;
  subject?: unknown;
}
const OWN_DOMAIN = /(^|\.)quotesdone\.(com|ae)$/;
// MicrosoftExchange<hex>@<tenant>.onmicrosoft.com: Exchange's own delivery reports (measured 2 Nov 2026).
const BOUNCE_LOCAL = /^(mailer-daemon|postmaster|microsoftexchange[0-9a-f]*)$/;
const NO_REPLY_LOCAL = /(^|[-_.+])(no-?reply|do-?not-?reply|donotreply|notifications?|verify|verification|bounces?)([-_.+]|$)/;

export function noAutoReply(m: MailFacts, founderAddrs: string[]): NoAutoReply | null {
  const from = String(m.from_email ?? '').trim().toLowerCase();
  const [local = '', domain = ''] = from.split('@');
  if (!local || !domain) return 'no_reply';
  if (founderAddrs.map((a) => a.trim().toLowerCase()).includes(from)) return 'founder';
  if (OWN_DOMAIN.test(domain) || !isCustomerCorrespondence(m)) return 'internal';
  const ct = String(m.raw?.content_type ?? '').toLowerCase();
  if (BOUNCE_LOCAL.test(local) || ct.startsWith('multipart/report')) return 'bounce';
  if (NO_REPLY_LOCAL.test(local)) return 'no_reply';
  const auto = String(m.raw?.auto_submitted ?? '').trim().toLowerCase();
  if (auto && auto !== 'no') return 'auto_submitted';
  // An out-of-office, a newsletter or a mailing list, on every mailbox now the whole tenant is read (2 Nov 2026): a reply
  // to one loops or is noise.
  if (autoReplied(m)) return 'auto_submitted';
  const to = String(m.to_email ?? '').toLowerCase();
  if (m.raw?.calendar === true || ct.includes('text/calendar') || /(^|[<\s,])(calendar|plan)\+/.test(to)) return 'calendar';
  return null;
}

// AN INVITED SUPPLIER'S REPLY TO THE INVITATION MAILBOX IS ANSWERED (sales_engineer, 28 Oct 2026, ledger 1375: "tomorrow
// morning i need suppliers receiving invitations and registering"). supplier@ is listed above as an internal intake box,
// so noAutoReply calls every mail to it 'internal'. Since 6 Oct the Microsoft 365 lane sends the invitation from
// supplier@ with no Reply-To, so a supplier's "yes" lands exactly there -- and was never answered. Measured on
// production 27 Oct: all three replies to supplier@ (inbound_messages 653-655) read "Not answered automatically:
// internal"; a ZZ DEMO invited lead's "yes" probed 28 Oct got the same, and only a waiting sales-engineer handoff.
// The exception is narrow on purpose: the mailbox is the ONLY reason the row is internal (no owner_role, no back-office
// tag, no other internal address), the sender is not on our domain, and the caller has proved the sender is a lead
// (fn_mail_sender_known = 'supplier'). The founder's own warm-up replies and any stranger writing to supplier@ stay
// unanswered, exactly as before.
// One definition, beside the stop rule that reads it (unsubscribe_mailbox.ts, 28 Oct 2026).
export { INVITATION_MAILBOX } from './unsubscribe_mailbox.ts';
// NEVER TO SOMEONE WHO SAID STOP, AND NEVER TO A MACHINE (review of #1699, 28 Oct 2026). A "stop" that resend_inbound
// could not apply is stored for review with a body starting "[UNSUBSCRIBE REQUEST NOT APPLIED" (needs_review true), which
// no back-office tag matched: without this, a lead who asked to be left alone would have been sent the registration
// pitch. The same for an address already in email_suppressions (the caller passes `suppressed`), a mail that reads as an
// unsubscribe request, and an out-of-office or other auto-reply (X-Autoreply, Precedence, the usual subject lines), so
// two auto-responders can never answer each other through supplier@.
const AUTO_REPLY_SUBJECT = /^\s*(automatic reply|auto(matic)?[- ]?(reply|response)|out of (the )?office|ooo\b|away from (the )?office|رد تلقائي|خارج المكتب)/i;
export function autoReplied(m: MailFacts & { subject?: unknown }): boolean {
  if (m.raw?.x_autoreply != null && String(m.raw.x_autoreply).trim() !== '') return true;
  if (m.raw?.list_unsubscribe != null && String(m.raw.list_unsubscribe).trim() !== '') return true;
  if (/^(auto[_-]?reply|bulk|junk|list)$/i.test(String(m.raw?.precedence ?? '').trim())) return true;
  return AUTO_REPLY_SUBJECT.test(String(m.subject ?? ''));
}
function identityRefuses(m: MailFacts, suppressed: boolean): boolean {
  if (suppressed) return true;
  const text = String(m.body ?? '').trim();
  if (/^\[unsubscribe\b/i.test(text) || isUnsubscribeRequest({ to: String(m.to_email ?? ''), subject: String(m.subject ?? ''), text })) return true;
  if (autoReplied(m)) return true;
  if (m.owner_role) return true;
  if (BACK_OFFICE_TAG.test(String(m.body ?? '').trim())) return true;
  const from = String(m.from_email ?? '').trim().toLowerCase();
  return OWN_DOMAIN.test(from.split('@')[1] || '');
}
// MAIL TO THE SUPPLIER MAILBOX THAT ITS READING SAID TO ANSWER (11 Nov 2026, customer_support, ruling 1633). The mailbox alone no
// longer makes it 'internal': email_triage/supplier_mailbox_reading.ts read what it is first. A stop, a suppressed address,
// an auto-reply, a seat already owning it, a back-office tag or our own domain still refuse it, exactly as for the rule below.
export function answerableOnceRead(m: MailFacts & { subject?: unknown }, suppressed = false): boolean {
  return !identityRefuses(m, suppressed);
}
function onlyTheMailboxMadeItInternal(m: MailFacts, suppressed: boolean, box: (address: string) => boolean): boolean {
  if (identityRefuses(m, suppressed)) return false;
  const to = String(m.to_email ?? '').toLowerCase().split(/[,;]/).map((a) => (a.trim().match(/<?([^<>\s]+@[^<>\s]+?)>?$/) || [])[1] || '').filter(Boolean);
  return to.some(box) && to.every((a) => box(a) || !isInternalMailbox(a));
}
export function invitationReplyAnswerable(m: MailFacts & { subject?: unknown }, senderRelation: unknown, suppressed = false): boolean {
  return senderRelation === 'supplier' && onlyTheMailboxMadeItInternal(m, suppressed, (a) => a === INVITATION_MAILBOX);
}

// MAIL TO management@ OR docs@ IN THE TENANT GETS THE NORMAL TRIAGE (2 Nov 2026, customer_support; founder: "All our emails
// should be with the agents"). Those two are internal so that the portal never shows them as a customer thread
// (isCustomerCorrespondence), and that also stopped every answer. supplier@ keeps its narrower rule above: a stranger
// there goes to sales_engineer through z53. expenses@ is the accountant's and is never answered.
const ANSWERED_INTERNAL_BOX = /^(management|docs)@quotesdone\.com$/;
export function tenantMailAnswerable(m: MailFacts, suppressed = false): boolean {
  return onlyTheMailboxMadeItInternal(m, suppressed, (a) => ANSWERED_INTERNAL_BOX.test(a));
}

// A machine's mail handed in from another tenant mailbox has nothing to answer and nobody to wait for: customer_support
// owns the row, and it stays off the founder's Inbox. supplier@ is excluded: z53 hands its declines to their seats.
export function declinedRowFields(m: { to_email?: unknown; provider_email_id?: unknown }): { owner_role: string; needs_review: boolean } | Record<string, never> {
  if (!String(m.provider_email_id ?? '').startsWith('m365:')) return {};
  return String(m.to_email ?? '').toLowerCase().includes(INVITATION_MAILBOX) ? {} : { owner_role: 'customer_support', needs_review: false };
}

// An autoresponder that slips every other rule cannot loop: at most this many automatic answers to one address a day.
export const DAILY_AUTO_ANSWER_CAP = 5;
export function overDailyAnswerCap(sentInTheLastDay: number | null | undefined): boolean { return Number(sentInTheLastDay || 0) >= DAILY_AUTO_ANSWER_CAP; }

/** The e-mail around a reply. The reply itself is ALWAYS written by a model in the moment (aiReply; founder rulings
 *  1195/1196, 12 Oct 2026): the person-handoff sentence, the quoted knowledge passage and the 'we received it' receipt that
 *  stood here were removed. Only the fixed greeting and sign-off are code. */
export function composeMailReply(o: { lang: 'en' | 'ar'; answer: string }): string {
  const ar = o.lang === 'ar';
  const hello = ar ? 'مرحباً،' : 'Hello,';
  const bye = ar ? 'مع أطيب التحيات،\nفريق QuotesDone' : 'Kind regards,\nThe QuotesDone Team';
  return hello + '\n\n' + o.answer.trim() + '\n\n' + bye;
}
