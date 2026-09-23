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
  // 22 Sep 2026 (documents-language audit, DL-06). "Dubai DET E-Trader Licence 1633275" named a
  // licence class the DET does not issue and the company does not hold: the printed licence says
  // Trader Licence No. 1633275, and the TDRA permit (NOL-26-100000665) was missing from the footer
  // altogether. The Arabic said «رخصة تاجر إلكتروني», the same wrong class. Both now match the paper.
  const footer = o.ar
    ? 'QuotesDone Technologies · دبي، الإمارات العربية المتحدة · رخصة تاجر رقم 1633275 – دائرة الاقتصاد والسياحة في دبي · خطاب عدم ممانعة هيئة تنظيم الاتصالات والحكومة الرقمية NOL-26-100000665'
    : 'QuotesDone Technologies · Dubai, UAE · DET Trader Licence No. 1633275 · TDRA NOL-26-100000665';
  const unsub = o.unsub
    ? (o.ar ? `إلغاء الاشتراك: ${o.unsub}\nأو مراسلة ${UNSUBSCRIBE_MAILBOX} لإزالة عنوانكم من القائمة.` : `Unsubscribe: ${o.unsub}\nor email ${UNSUBSCRIBE_MAILBOX} to be removed.`)
    : '';
  return [body, '--', footer, unsub].filter(Boolean).join('\n\n');
}
