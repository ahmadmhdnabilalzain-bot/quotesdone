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
  // 24 Sep 2026 (marketing, ledger 993): the founder's campaign rules - no trade licence number in
  // supplier mail, and the address is Al Furjan, Dubai. The TDRA permit stays: it is the site's permit,
  // not the licence. Mirrors templates.email_supplier
  // (scripts/sql/the_supplier_mail_names_al_furjan_and_no_licence_number.sql).
    ? 'QuotesDone Technologies · الفرجان، دبي، الإمارات العربية المتحدة · خطاب عدم ممانعة هيئة تنظيم الاتصالات والحكومة الرقمية NOL-26-100000665'
    : 'QuotesDone Technologies · Al Furjan, Dubai, UAE · TDRA NOL-26-100000665';
  const unsub = o.unsub
    ? (o.ar ? `إلغاء الاشتراك: ${o.unsub}\nأو مراسلة ${UNSUBSCRIBE_MAILBOX} لإزالة عنوانكم من القائمة.` : `Unsubscribe: ${o.unsub}\nor email ${UNSUBSCRIBE_MAILBOX} to be removed.`)
    : '';
  return [body, '--', footer, unsub].filter(Boolean).join('\n\n');
}
