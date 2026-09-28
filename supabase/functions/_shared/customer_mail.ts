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
export type NoAutoReply = 'founder' | 'internal' | 'bounce' | 'no_reply' | 'auto_submitted' | 'calendar';
export interface MailFacts {
  from_email?: unknown; to_email?: unknown; owner_role?: unknown; body?: unknown;
  /** inbound_messages.raw as resend_inbound stores it: message_id, auto_submitted, content_type, calendar. */
  raw?: { auto_submitted?: unknown; content_type?: unknown; calendar?: unknown } | null;
}
const OWN_DOMAIN = /(^|\.)quotesdone\.(com|ae)$/;
const BOUNCE_LOCAL = /^(mailer-daemon|postmaster)$/;
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
  const to = String(m.to_email ?? '').toLowerCase();
  if (m.raw?.calendar === true || ct.includes('text/calendar') || /(^|[<\s,])(calendar|plan)\+/.test(to)) return 'calendar';
  return null;
}

/** The words that go back. `answer` is a verified reasoned answer; `passage` a reviewed knowledge passage,
 *  quoted verbatim; with neither, an honest receipt that promises only what the replay delivers. */
export function composeMailReply(o: { lang: 'en' | 'ar'; answer?: string | null; passage?: string | null; person?: boolean }): string {
  const ar = o.lang === 'ar';
  const hello = ar ? 'مرحباً،' : 'Hello,';
  const bye = ar ? 'مع أطيب التحيات،\nفريق QuotesDone' : 'Kind regards,\nThe QuotesDone Team';
  let mid: string;
  if (o.person) mid = ar ? 'شكراً لرسالتكم. طلبتم التحدث مع أحد أعضاء فريقنا، وقد أحلنا رسالتكم إليه، وسيرد عليكم في هذه المحادثة نفسها.'
    : 'Thank you for your message. You asked to speak to a person, so we have passed it to a member of our team, who will reply to you in this same thread.';
  else if (o.answer && o.answer.trim()) mid = o.answer.trim();
  else if (o.passage && o.passage.trim()) mid = (ar ? 'شكراً لرسالتكم. إليكم ما يتعلق بسؤالكم:' : 'Thank you for your message. Here is what applies to your question:') + '\n\n' + o.passage.trim().replace(/^#+\s*/gm, '').slice(0, 1500)
    + '\n\n' + (ar ? 'إن لم يُجب هذا عن سؤالكم، فردّوا على هذه الرسالة بمزيد من التفاصيل.' : 'If this does not answer your question, reply to this e-mail with a little more detail.');
  else mid = ar ? 'شكراً لرسالتكم، لقد وصلتنا. سنرسل إليكم الإجابة في هذه المحادثة نفسها. ويمكنكم أيضاً الاطلاع على الأسئلة الشائعة على https://quotesdone.com'
    : 'Thank you for your message, which we have received. We will send you the answer in this same thread. Our frequently asked questions are also at https://quotesdone.com';
  return hello + '\n\n' + mid + '\n\n' + bye;
}
