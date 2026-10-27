// The contact form's message cap, shared by contact_submit (the rule) and its test. The form mirrors it
// as maxLength in src/components/ContactInner.tsx (CONTACT_MESSAGE_MAX) - keep the two numbers equal.
// Until 19 Oct 2026 the handler silently cut anything past 4000 characters: public QA posted 20,000
// and got "Thanks", while the inbox received a truncated message the customer never knew was cut.
export const CONTACT_MESSAGE_MAX = 4000;

/** null when the message is acceptable, otherwise the EN and AR error the form shows. */
export function contactMessageError(message: string): { error: string; error_ar: string } | null {
  const n = [...message].length; // code points, so an emoji counts once, as the visitor sees it
  if (n < 4) return { error: 'Please write a short message.', error_ar: 'يُرجى كتابة رسالة قصيرة.' };
  if (n > CONTACT_MESSAGE_MAX) return {
    error: `Your message is too long (${n} characters). Please keep it under ${CONTACT_MESSAGE_MAX} characters.`,
    error_ar: `رسالتكم طويلة جدًا (${n} حرفًا). يُرجى ألا تتجاوز ${CONTACT_MESSAGE_MAX} حرف.`,
  };
  return null;
}
