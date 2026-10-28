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
  if (PHRASE.test(first)) return true;
  return toInvitationMailbox(o.to) && invitationOptOut(String(o.subject || ''), String(o.text || ''));
}

// ── A REPLY TO THE INVITATION THAT ASKS TO STOP (28 Oct 2026, sales_engineer; supplier-journey audit, ledger 1401) ──
// Measured on production that morning (run 490a318b): a reply "Please remove me / stop" to supplier@ matched none of
// the above, because PHRASE takes a line that is ONLY the request. So resend_inbound did not suppress it, email_triage
// answered it ("Understood. We will not contact you again...") and the address stayed sendable: the day-3 nudge would
// have gone. The invitation itself tells the supplier to reply "stop" (m365_lane.ts STOP_LINE), and a supplier writes it
// his own way. So on the INVITATION mailbox, one of the reply's first three lines of its own words (not the quoted
// invitation) that says only the request, with politeness around it, is the request: "Please remove me / stop",
// "Stop please", "Kindly unsubscribe us, thanks", "No thanks", "We are not interested", "توقف", "لا ترسلوا",
// "إلغاء الاشتراك من فضلك". Every word of that line must be an opt-out phrase or politeness: one other word ("do not
// STOP the tender", "stop by our office", "No, we are interested") and it is not; and a "yes" or "interested" (not
// "not interested") in those lines vetoes it. Read by code, never by a model: a stop must be honoured whether or not
// any model is reachable (coordinator, 28 Oct: "a model decision alone is not enough"). Everywhere else PHRASE alone
// decides, as before.
export const INVITATION_MAILBOX = 'supplier@quotesdone.com';
function toInvitationMailbox(to: unknown): boolean {
  return String(to || '').toLowerCase().split(/[,;]/).some((a) => ((a.trim().match(/<?([^<>\s]+@[^<>\s]+?)>?$/) || [])[1] || '') === INVITATION_MAILBOX);
}
// Arabic folded the way people type it: no diacritics or tatweel, one alef, final yaa.
const arFold = (s: string) => s.replace(/[ً-ْـ]/g, '').replace(/[أإآ]/g, 'ا').replace(/ى/g, 'ي');
const fold = (s: string) => arFold(String(s || '').toLowerCase()).replace(/[’'`]/g, '').replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
const OPT_OUT_PHRASES: string[][] = [
  'unsubscribe', 'unsubscribe me', 'unsubscribe us', 'remove', 'remove me', 'remove us', 'remove me from your list', 'remove us from your list',
  'remove me from your mailing list', 'remove us from your mailing list', 'remove me from the list', 'remove us from the list',
  'remove my email', 'remove our email', 'take me off your list', 'take us off your list', 'take me off', 'take us off',
  'stop', 'stop it', 'stop emailing me', 'stop emailing us', 'stop sending', 'stop sending emails', 'stop sending me emails',
  'stop sending us emails', 'stop contacting me', 'stop contacting us', 'opt out', 'optout', 'do not contact me', 'do not contact us',
  'dont contact me', 'dont contact us', 'do not email me', 'do not email us', 'dont email me', 'dont email us', 'no more emails',
  'not interested', 'we are not interested', 'i am not interested', 'im not interested', 'were not interested', 'no', 'no thanks',
  'not relevant', 'this is not relevant', 'not relevant to us',
  'الغاء الاشتراك', 'الغوا اشتراكي', 'الغوا الاشتراك', 'ازاله', 'ازالة', 'الازاله', 'الازالة', 'الحذف', 'ازيلوني', 'ازيلونا', 'احذفوني', 'احذفونا', 'توقف', 'توقفوا', 'اوقف',
  'اوقفوا', 'لا ترسل', 'لا ترسلوا', 'لا ترسلوا لنا', 'لا ترسلوا لي', 'لا تراسلونا', 'لا تراسلوني', 'لا تتواصلوا معنا', 'لا تتواصلوا معي',
  'غير مهتم', 'غير مهتمين', 'لسنا مهتمين', 'لا شكرا',
].map((p) => fold(p).split(' ')).sort((a, b) => b.length - a.length);
// Politeness and greetings around the request: dropped before the line is read. Never a word that could carry meaning.
const FILLER = new Set(['please', 'pls', 'plz', 'kindly', 'thanks', 'thank', 'you', 'thankyou', 'thx', 'ty', 'ok', 'okay', 'sir', 'madam',
  'dear', 'hi', 'hello', 'hey', 'team', 'regards', 'best', 'kind', 'many', 'and', 'also', 'just', 'asap', 'immediately', 'now', 'sorry',
  'quotesdone', 'من', 'فضلك', 'فضلكم', 'لو', 'سمحت', 'سمحتم', 'الرجاء', 'رجاء', 'شكرا', 'مع', 'الشكر', 'تحياتي', 'مرحبا', 'و']);
// A leading greeting clause ("Hi Ahmad, ...", "مرحبا، ...") is dropped from a line; a line that is only a greeting is skipped.
const GREETING = /^(hi|hello|hey|dear|good (morning|afternoon|evening)|greetings|مرحبا|السلام عليكم|عزيزي|الاخ|السيد)\b[^,.!،\n]{0,40}[,.!،]\s*/i;
const GREETING_WORDS = new Set(['hi', 'hello', 'hey', 'dear', 'good', 'greetings', 'مرحبا', 'السلام', 'عزيزي', 'الاخ', 'السيد']);
// Where the reply's own words end: the quoted invitation, a forwarded block, an Outlook header block, a phone signature.
const QUOTED = /^\s*(>|on .+ wrote:?\s*$|(from|sent|to|subject|date|cc):\s|-{2,}\s*(original|forwarded) message|_{8,}|sent from my |في .+ كتب)/i;
/** Does this one line say only "stop" (opt-out phrases and politeness, nothing else)? */
export function lineSaysStop(line: string): boolean {
  const s = fold(String(line || '').replace(GREETING, '')).replace(/^((re|aw|fw|fwd|رد)\s+)+/, '');
  const t = s.split(' ').filter((w) => w && !FILLER.has(w));
  if (!t.length) return false;
  for (let i = 0; i < t.length;) {
    const p = OPT_OUT_PHRASES.find((ph) => ph.every((w, k) => t[i + k] === w));
    if (!p) return false;
    i += p.length;
  }
  return true;
}
const greetingOnly = (l: string) => { const t = fold(l).split(' ').filter(Boolean); return t.length > 0 && t.length <= 4 && GREETING_WORDS.has(t[0]) && !lineSaysStop(l); };
// "yes" or "interested" (but not "not interested") in the reply's own lines: never an opt-out, whatever else it says.
const saysYes = (l: string) => {
  const f = ' ' + fold(l) + ' ';
  return / (yes|نعم|ايوه|اكيد) /.test(f) || / interested /.test(f.replace(/ not interested /g, ' '))
    || / مهتم(ين)? /.test(f.replace(/ (غير|لسنا) مهتم(ين)? /g, ' '));
};
/** The reply's own first three lines (greetings skipped, the quoted invitation never read), or its subject, say stop. */
export function invitationOptOut(subject: string, text: string): boolean {
  const own: string[] = [];
  for (const raw of String(text || '').split(/\r?\n/)) {
    if (QUOTED.test(raw)) break;
    const l = raw.trim();
    if (!l || greetingOnly(l)) continue;
    own.push(l);
    if (own.length === 3) break;
  }
  if (own.some(saysYes)) return false;
  return own.some(lineSaysStop) || lineSaysStop(String(subject || '').replace(/^\s*((re|aw|fw|fwd|رد)\s*:\s*)+/i, ''));
}
