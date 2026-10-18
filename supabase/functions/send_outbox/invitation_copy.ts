// THE SUPPLIER INVITATION ENDS WITH ONE QUESTION A SUPPLIER CAN ANSWER BY REPLYING (24 Sep 2026, marketing).
//
// Measured on production 24 Sep 2026 (app_secrets.invite_body, read-only): the invitation ended
// "... We look forward to welcoming you." - a closing with nothing to answer, so the only thing a supplier
// could do was click or ignore. A one-line reply is the easiest step there is, and it lands in
// suppliers@mail.quotesdone.com, which resend_inbound stores in inbound_messages with needs_review
// (trg_inbound_supplier_reply, scripts/sql/a_supplier_reply_reaches_a_mailbox_that_is_read.sql).
//
// The stored copy owns the wording (scripts/sql/the_supplier_invitation_ends_with_one_question_and_is_always_english.sql).
// withReplyQuestion is the fallback in code: an English invitation whose stored body does not end with a
// question gets this one appended, so the rendered mail ends with it whichever half is deployed first.
// invitationCopyLint is the rule set, shared by invitation_copy.test.ts, the node check and
// scripts/invitation_inbox_check.mjs, so the live copy and the fixture are held to the same rules.

export const INVITE_REPLY_QUESTION =
  'Before you register, one quick question you can answer by simply replying to this email: which trades does your company cover?';

// Escapes, not the letters themselves: every_arabic_message_is_written_not_translated reads literal Arabic as copy.
const ARABIC = /[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]/;
// The founder's rule: the word is never used in anything a customer or supplier reads; say "smart".
const THE_FORBIDDEN_WORD = /\bai\b/i;
// NO DATES IN THE COPY (founder ruling 6 Sep 2026; coordinator finding 5 Oct 2026: the live invite_body still said
// the offer was free "until" a 2027 date, then a subscription from the next day). A year, or a month name beside a
// day or year, fails. The offer is "free permanently for the first 1,000 supplier registrations", with no date.
const MONTH = '(?:jan(?:uary)?|feb(?:ruary)?|march|april|may|june|july|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)';
export const A_DATE = new RegExp(`\\b(?:19|20)\\d\\d\\b|\\b${MONTH}\\s+\\d{1,4}\\b|\\b\\d{1,2}\\s+${MONTH}\\b`, 'i');

/** The last non-empty paragraph of a plain-text body, trimmed. */
export function lastParagraph(body: string): string {
  const parts = String(body || '').replace(/\r/g, '').split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean);
  return parts.length ? parts[parts.length - 1] : '';
}

// Abbreviations whose full stop is not the end of a sentence ("e.g. MEP", "Acme Co. LLC", "L.L.C."). Mirrored in the
// verdict row of the_supplier_invitation_ends_with_one_question_and_is_always_english.sql.
const ABBREVIATION = /\b(?:e\.g|i\.e|etc|co|l\.l\.c|ltd|inc|no|st|mr|mrs|ms|dr)\./gi;

/** True when the body's last paragraph is ONE sentence and it is a question. */
export function endsWithOneQuestion(body: string): boolean {
  const last = lastParagraph(body);
  if (!last.endsWith('?')) return false;
  if ((last.match(/\?/g) || []).length !== 1) return false;
  // a sentence break inside the paragraph (". ", "! " followed by more text) means two sentences
  return !/[.!]\s+\S/.test(last.replace(ABBREVIATION, ''));
}

/**
 * An invitation row in Arabic is held, never sent (ledger 993: invitations always in English). A row queued with
 * lang 'ar' before fn_supplier_invite_candidates was made English-only carries only the Arabic text and no
 * question; the English copy cannot be rebuilt from the row (no claim token, no company), so it waits instead.
 */
// SINCE 28 SEP 2026 EVERY SUPPLIER-BOUND ROW IS ENGLISH (founder; E2E stage 1 D3, 30 Sep): a supplier-side row
// queued with lang 'ar' is held the same way, whatever its type, so no Arabic path can reach a supplier.
export function holdArabicInvitation(type: unknown, lang: unknown, supplierSide = false): boolean {
  return (supplierSide || String(type || '').startsWith('supplier_invite')) && String(lang || '').toLowerCase() === 'ar';
}

/**
 * The code fallback: append the question to an invitation that does not already end with one. The caller
 * decides the language (send_outbox passes English invitations only); the body itself may carry Arabic
 * script legitimately, in the company's own name after "Dear" (2 of the first 50 candidates, 24 Sep 2026).
 */
export function withReplyQuestion(body: string): string {
  const b = String(body || '');
  if (!b.trim() || endsWithOneQuestion(b)) return b;
  return b.replace(/\s+$/, '') + '\n\n' + INVITE_REPLY_QUESTION;
}

export type CopyRule = { rule: string; ok: boolean; detail?: string };

/**
 * Every rule the invitation COPY must satisfy - the stored subject, body and preheader, filled with a fixture
 * company name (a real company's own name may be written in Arabic and is not copy). `link` is the portal URL
 * as filled into the body.
 */
export function invitationCopyLint(o: { lang: string; subject: string; body: string; preheader: string; link?: string }): CopyRule[] {
  const fields: [string, string][] = [['subject', o.subject || ''], ['body', o.body || ''], ['preheader', o.preheader || '']];
  const arabic = fields.filter(([, v]) => ARABIC.test(v)).map(([k]) => k);
  const word = fields.filter(([, v]) => THE_FORBIDDEN_WORD.test(v)).map(([k]) => k);
  const last = lastParagraph(o.body);
  const qAt = o.body.lastIndexOf(last);
  const linkAt = o.link ? o.body.indexOf(o.link) : -1;
  const dated = fields.filter(([, v]) => A_DATE.test(v)).map(([k]) => k);
  return [
    { rule: 'the invitation is English only', ok: o.lang === 'en' && arabic.length === 0,
      detail: o.lang !== 'en' ? `lang=${o.lang}` : `Arabic script in ${arabic.join(', ')}` },
    { rule: 'never the word AI (the founder\'s rule: say "smart")', ok: word.length === 0, detail: `found in ${word.join(', ')}` },
    { rule: 'the body ends with one question the supplier can answer by replying', ok: endsWithOneQuestion(o.body),
      detail: `last paragraph: "${last.slice(-160)}"` },
    { rule: 'the question comes after the portal link', ok: !o.link || (linkAt >= 0 && qAt > linkAt),
      detail: linkAt < 0 ? 'portal link not found in the body' : 'the question sits above the link' },
    { rule: 'no date in the copy (founder ruling 6 Sep 2026)', ok: dated.length === 0, detail: `a date in ${dated.join(', ')}` },
  ];
}
