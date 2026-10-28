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
//
// THE WORDS SUPPLIERS ACTUALLY WRITE (28 Oct 2026, sales_engineer; ledger 1401 audit, scenario S6). Measured: on
// production an invited ZZ DEMO lead's "Not interested" reply to the invitation was stored and NOT suppressed (HTTP 200,
// email_suppressions 0, the inbound row left for email_triage); offline, this test answered false for "Not interested",
// "Please remove us from your mailing list.", "Remove", "Please remove", "No thank you", "Cancel", "End", "stopall" and
// "Do not contact us again" (only "stop" and "unsubscribe" were true). So the day-3/7/14 reminders stayed due and
// email_triage (invitationReplyAnswerable reads this same test) was free to answer with the registration pitch, while
// fn_marketing_files_invite_reply already treated 'not interested', 'remove', 'please remove', 'cancel', 'end' and
// 'stopall' as stop replies and filed no handoff: two vocabularies for one decision. The reminder itself tells the
// supplier "reply to this one and we will remove your address". This list is now the superset, and
// unsubscribe_mailbox.test.ts reads the SQL list from its canonical file and fails if any phrase of it is not
// recognised here. Still a WHOLE subject or first line: a sentence that merely contains one of the words is not one.
const POLITE = String.raw`(?:(?:please|kindly)[\s,]+)?`;
const THANKS = String.raw`(?:[\s,]+(?:please|thanks|thank\s+you|thx))?`;
const OUT = [
  String.raw`unsubscribe(?:\s+(?:me|us))?`,
  String.raw`stop(?:\s*all)?`, 'end', 'cancel', 'quit',
  String.raw`opt[\s-]?out`,
  String.raw`remove(?:\s+(?:me|us|my\s+(?:e-?mail|address)|our\s+(?:e-?mail|address|company)))?(?:\s+(?:from|off)\s+(?:your|the|this)\s+(?:mailing\s+|e-?mail\s+|contact\s+)?list)?`,
  String.raw`(?:(?:i\s+am|i'm|we\s+are|we're)\s+)?not\s+interested`,
  String.raw`no[\s,]+thank(?:s|\s+you)`,
  String.raw`stop\s+(?:sending|e-?mailing|mailing|contacting)(?:\s+(?:me|us))?(?:\s+(?:any\s+)?(?:more\s+)?(?:e-?mails?|messages?))?`,
  String.raw`(?:do\s+not|don'?t)\s+(?:contact|e-?mail|mail|write\s+to)\s+(?:me|us)(?:\s+again)?`,
  'إلغاء الاشتراك', 'الغاء الاشتراك', 'ألغوا اشتراكي', 'إزالة', String.raw`غير\s+مهتم(?:ين)?`, String.raw`لا[،,]?\s*شكر(?:ا|اً)`,
];
const PHRASE = new RegExp(String.raw`^(?:(?:re|aw|fwd?|رد)\s*:\s*)*` + POLITE + `(?:${OUT.join('|')})` + THANKS + String.raw`[\s.!،,]*$`, 'i');

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
