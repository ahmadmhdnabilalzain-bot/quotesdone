// THE UNSUBSCRIBE BY EMAIL, AND THE ONE PLACE THAT DECIDES WHAT COUNTS AS ONE (21 Sep 2026, customer_support).
//
// Measured on production 21 Sep 2026, before the supplier campaign: every supplier mail said "or reply to
// this email to be removed" and its List-Unsubscribe header offered mailto:supplier@quotesdone.com. That
// mailbox is on Microsoft 365 (MX quotesdone-com.mail.protection.outlook.com) and no code reads it, so a
// supplier who replied "unsubscribe" reached a human inbox and was mailed again. The link path was proved
// the same evening (one-click POST -> email_suppressions source 'link'); the reply path had no reader.
//
// mail.quotesdone.com is Resend's inbound domain (MX inbound-smtp.us-east-1.amazonaws.com) and every
// address on it reaches resend_inbound -- proved the same evening: a message to UNSUBSCRIBE_MAILBOX
// arrived as inbound_messages#154. So the mail frame now names UNSUBSCRIBE_MAILBOX, the header's mailto
// points at it, and resend_inbound suppresses the sender of what isUnsubscribeRequest() accepts -- only after
// the gates in _shared/suppression_policy.ts (protected addresses, an authenticated From domain, and an
// address we actually sent an invitation or reminder to).
//
// Pure, so unsubscribe_mailbox.test.ts replays each case without a network.

export const UNSUBSCRIBE_MAILBOX = 'unsubscribe@mail.quotesdone.com';

// A subject or first line that is ONLY the request, optionally behind reply prefixes and punctuation.
// Whole-line match on purpose: "please do not stop the tender" must never unsubscribe anybody.
const PHRASE = /^(?:(?:re|aw|fwd?|رد)\s*:\s*)*(?:unsubscribe|remove me|stop|opt[ -]?out|إلغاء الاشتراك|الغاء الاشتراك|ألغوا اشتراكي|إزالة)[\s.!،,]*$/i;

/** true when this inbound mail is a request to stop mailing its sender. */
export function isUnsubscribeRequest(o: { to: string; subject: string; text: string }): boolean {
  const toLocal = String(o.to || '').trim().toLowerCase();
  // Anything sent to the dedicated mailbox is a request, whatever it says: that is how a mail client's
  // List-Unsubscribe mailto works (it may send an empty body or a subject of its own choosing).
  if (toLocal === UNSUBSCRIBE_MAILBOX) return true;
  if (PHRASE.test(String(o.subject || '').trim())) return true;
  const first = String(o.text || '').split(/\r?\n/).map((l) => l.trim()).find((l) => l.length > 0) || '';
  return PHRASE.test(first);
}
