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

/** The last non-empty paragraph of a plain-text body, trimmed. */
export function lastParagraph(body: string): string {
  const parts = String(body || '').replace(/\r/g, '').split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean);
  return parts.length ? parts[parts.length - 1] : '';
}

/** True when the body's last paragraph is ONE sentence and it is a question. */
export function endsWithOneQuestion(body: string): boolean {
  const last = lastParagraph(body);
  if (!last.endsWith('?')) return false;
  if ((last.match(/\?/g) || []).length !== 1) return false;
  // a sentence break inside the paragraph (". ", "! " followed by more text) means two sentences
  return !/[.!]\s+\S/.test(last);
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
  return [
    { rule: 'the invitation is English only', ok: o.lang === 'en' && arabic.length === 0,
      detail: o.lang !== 'en' ? `lang=${o.lang}` : `Arabic script in ${arabic.join(', ')}` },
    { rule: 'never the word AI (the founder\'s rule: say "smart")', ok: word.length === 0, detail: `found in ${word.join(', ')}` },
    { rule: 'the body ends with one question the supplier can answer by replying', ok: endsWithOneQuestion(o.body),
      detail: `last paragraph: "${last.slice(-160)}"` },
    { rule: 'the question comes after the portal link', ok: !o.link || (linkAt >= 0 && qAt > linkAt),
      detail: linkAt < 0 ? 'portal link not found in the body' : 'the question sits above the link' },
  ];
}
