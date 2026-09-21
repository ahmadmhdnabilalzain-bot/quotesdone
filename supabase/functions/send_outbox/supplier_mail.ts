// The three send-time rules that keep supplier mail lawful and honest (21 Sep 2026, customer_support).
// Pure functions so supplier_mail.test.ts can replay each failure without a network or a database.
import { UNSUBSCRIBE_MAILBOX } from '../_shared/unsubscribe_mailbox.ts';

/** Addresses are compared case-folded: suppressions are stored lower-case, lead emails are not. */
export function foldEmail(e: unknown): string {
  return String(e ?? '').trim().toLowerCase();
}

/**
 * Supplier mail that is not a licence/document request is marketing, and marketing never leaves
 * without an unsubscribe link. true = hold the row instead of sending it.
 */
export function holdForNoUnsubscribe(supplierSide: boolean, docRequest: boolean, unsub: string): boolean {
  return supplierSide && !docRequest && !String(unsub || '').trim();
}

/** The text/plain alternative: the body, the legal footer, and the unsubscribe URL, in one language. */
export function plainTextPart(o: { body: string; unsub: string; ar: boolean; internal: boolean }): string {
  const body = String(o.body || '').trim();
  if (o.internal) return body;
  const footer = o.ar
    ? 'QuotesDone · دبي، الإمارات العربية المتحدة · رخصة تاجر إلكتروني - دائرة الاقتصاد والسياحة في دبي 1633275'
    : 'QuotesDone · Dubai, UAE · Dubai DET E-Trader Licence 1633275';
  const unsub = o.unsub
    ? (o.ar ? `إلغاء الاشتراك: ${o.unsub}\nأو مراسلة ${UNSUBSCRIBE_MAILBOX} لإزالة عنوانكم من القائمة.` : `Unsubscribe: ${o.unsub}\nor email ${UNSUBSCRIBE_MAILBOX} to be removed.`)
    : '';
  return [body, '--', footer, unsub].filter(Boolean).join('\n\n');
}
