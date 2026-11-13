// scripts/e2e/journey_proof/dossier_words.ts — the sentences the dossier repeats, in one place so every journey says the
// same thing the same way. Seat: customer_support.
// deno-lint-ignore no-explicit-any
type Any = any;

/** What the anonymity check looked at and what it could not see, said before its table. */
export function scanNote(a: Any, receiver: string): string {
  const looked = (a.checked || []).join('; ') || 'nothing';
  const blind = (a.not_checked || []).length ? ` NOT checked, because the check cannot read text drawn as a picture: ${(a.not_checked || []).join('; ')}. Look at those pictures in this dossier yourself.` : '';
  const short = (a.too_short_to_check || []).length ? ` Too short to search for safely (would match ordinary numbers): ${a.too_short_to_check.join(', ')}.` : '';
  return `Every detail below went in on the other side. Each was searched for, before the reveal, in everything the ${receiver} received: ${looked}. Case, spacing and punctuation are ignored; a phone number is found however it is written, in Western or Arabic digits. The emirate may show; the area and the villa or plot number may not.${blind}${short}`;
}

/** The line every composed-but-not-sent message carries. */
export const SUPPRESSED = 'composed, delivery suppressed for a demo identity';
