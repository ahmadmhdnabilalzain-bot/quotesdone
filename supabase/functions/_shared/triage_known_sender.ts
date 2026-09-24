// triage_known_sender — email_triage does not pay the model again for a sender it has already settled.
// Seat: it_engineer, 24 Sep 2026 (the OpenRouter inventory: email_triage ~AED 0.2/day of routine calls).
// The lookup is EXACT: the from_email value as stored, against that address's own earlier triage rows
// (public.inbound_messages.ai_category). No word of the mail is read. Only one route is deterministic: an address
// whose last SPAM_AFTER triages were all spam, and never anything else, is spam again (no reply is drafted for spam,
// so nothing is lost). Every other sender, known or not, still gets the model, because its reply must be written.
export const SPAM_AFTER = 2;
/** The category a known sender routes to without the model, from its earlier triages (newest first), else null. */
export function knownSenderCategory(prior: (string | null)[]): 'spam' | null {
  const seen = prior.filter((c): c is string => !!c);
  return seen.length >= SPAM_AFTER && seen.every((c) => c === 'spam') ? 'spam' : null;
}
